#if canImport(Glibc)
@preconcurrency import Foundation  // URL is not Sendable in swift-corelibs-foundation 5.9
#else
import Foundation
#endif
import MLCore

/// Ein Eintrag im Änderungsprotokoll (Journal) einer Tag-Bearbeitung.
public struct TagWriteJournalEntry: Codable, Hashable, Sendable {
    public var id: UUID
    public var batchID: UUID
    public var timestamp: Date
    /// Bearbeitete Datei (Symlinks aufgelöst).
    public var originalPath: String
    /// Bytegleiche Sicherungskopie des Originals.
    public var backupPath: String
    /// Geänderte Felder (`TagField.rawValue`, zusätzlich „pictures“).
    public var fieldsChanged: [String]
    /// Felder, die das Format nicht speichern kann und die übersprungen wurden.
    public var skippedFields: [String]
    /// Werte vorher/nachher (gekürzt) je geändertem Feld.
    public var before: [String: String]
    public var after: [String: String]
    public var originalSize: Int64
    public var originalSHA256: String
    public var resultSize: Int64
    public var resultSHA256: String
    /// Zeitpunkt des Rückgängigmachens (`nil` = nicht rückgängig gemacht).
    public var undoneAt: Date?
}

/// Journal einer Stapel-Bearbeitung (eine JSON-Datei je Stapel im Sicherungsordner).
public struct TagWriteJournal: Codable, Hashable, Sendable {
    public var batchID: UUID
    public var created: Date
    public var entries: [TagWriteJournalEntry]
}

/// Eine Datei mit ihrer Bearbeitung.
public struct TagWriteRequest: Hashable, Sendable {
    public var url: URL
    public var edit: TagEdit

    public init(url: URL, edit: TagEdit) {
        self.url = url
        self.edit = edit
    }
}

/// Ergebnis für eine Datei eines Stapels.
public struct TagWriteFileResult: Sendable {
    public var url: URL
    public var entry: TagWriteJournalEntry?
    public var error: TagError?
    public var succeeded: Bool { error == nil }
}

/// Ergebnis einer Stapel-Bearbeitung.
public struct TagWriteBatchResult: Sendable {
    public var batchID: UUID
    public var results: [TagWriteFileResult]
    public var succeededCount: Int { results.filter(\.succeeded).count }
    public var failed: [TagWriteFileResult] { results.filter { !$0.succeeded } }
}

/// Ergebnis des Rückgängigmachens für eine Datei.
public struct TagUndoFileResult: Sendable {
    public enum Outcome: Sendable, Equatable {
        /// Original bytegleich wiederhergestellt.
        case restored
        /// Die Datei war bereits im Originalzustand.
        case alreadyOriginal
        case failed(TagError)
    }

    public var path: String
    public var outcome: Outcome
}

public struct TagUndoResult: Sendable {
    public var batchID: UUID
    public var results: [TagUndoFileResult]
    public var allSucceeded: Bool {
        results.allSatisfy { if case .failed = $0.outcome { return false } else { return true } }
    }
}

/// Sicheres Schreiben von Tags.
///
/// Vorgehen je Datei:
/// 1. Prüfen: Datei vorhanden, beschreibbar (Datei und Ordner), Format unterstützt, genug Platz.
/// 2. Original bytegleich in den Sicherungsordner kopieren (`<Wurzel>/<yyyy-MM-dd>/<uuid>-<Name>`), fsync.
/// 3. Original in eine versteckte temporäre Datei im selben Ordner kopieren und dort die Tags schreiben.
/// 4. Temporäre Datei neu einlesen: jedes bearbeitete Feld, die Bilder und alle übrigen Felder sowie
///    die Audio-Eigenschaften (Dauer ±50 ms, Abtastrate, Kanäle, Codec) prüfen; zusätzlich müssen die
///    Audiodaten selbst (ohne Tags) bytegleich sein (CRC32 + Adler-32 über die Nutzdaten).
/// 5. Sicherstellen, dass das Original inzwischen nicht verändert wurde (Größe, Änderungszeit, Inode),
///    Rechte/Attribute übernehmen und das Original atomar per rename(2) ersetzen.
/// 6. Journal-Eintrag schreiben (vor dem Ersetzen; ein misslungenes Ersetzen nimmt ihn zurück).
/// Bei jedem Fehler wird die temporäre Datei gelöscht, das Original bleibt unverändert.
public final class SafeTagWriter: @unchecked Sendable {
    public struct Configuration: Sendable {
        /// Wurzel der Sicherungen, z. B. `<Application Support>/Music Library/Backups`.
        public var backupRoot: URL
        /// Erlaubte Abweichung der Dauer nach dem Schreiben.
        public var durationToleranceMs: Int64 = 50
        /// Zusätzlich frei zu haltender Speicher (Bytes).
        public var freeSpaceReserve: Int64 = 16 * 1024 * 1024
        /// Auch alle nicht bearbeiteten Felder vergleichen (empfohlen).
        public var verifyUntouchedFields = true

        public init(backupRoot: URL) {
            self.backupRoot = backupRoot
        }
    }

    /// Eingriffspunkte für Tests (intern).
    struct Hooks {
        var applyEdit: (URL, TagEdit) throws -> Void = { url, edit in _ = try TagFile.write(url: url, edit: edit) }
        var beforeReplace: ((URL) throws -> Void)?
        var freeSpace: (String) -> Int64? = { FileSystem.freeSpace(at: $0) }
        var now: () -> Date = { Date() }
    }

    public let configuration: Configuration
    var hooks = Hooks()
    private let lock = NSLock()

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    public convenience init(backupRoot: URL = SafeTagWriter.defaultBackupRoot) {
        self.init(configuration: Configuration(backupRoot: backupRoot))
    }

    /// `<Application Support>/Music Library/Backups`
    public static var defaultBackupRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Music Library", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
    }

    var journalDirectory: URL { configuration.backupRoot.appendingPathComponent("Journal", isDirectory: true) }

    // MARK: - Writing

    /// Schreibt eine Bearbeitung sicher in eine Datei und liefert den Journal-Eintrag.
    @discardableResult
    public func write(url: URL, edit: TagEdit, batchID: UUID = UUID()) throws -> TagWriteJournalEntry {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard !edit.isEmpty else { throw TagError.nothingToWrite(path: path) }

        // (1) checks
        guard let initial = FileSystem.fileStat(path) else { throw TagError.fileNotFound(path: path) }
        guard initial.isRegularFile else { throw TagError.notAFile(path: path) }
        guard FileSystem.canWriteFile(path) else { throw TagError.fileReadOnly(path: path) }
        let directory = (path as NSString).deletingLastPathComponent
        guard FileSystem.canWriteDirectory(directory) else { throw TagError.directoryNotWritable(path: path) }
        let (before, traits, formatReason) = try inspectOriginal(path)
        if let formatReason { throw TagError.formatNotWritable(path: path, reason: formatReason) }
        let audioBefore = try TagFile.audioPayloadChecksum(url: URL(fileURLWithPath: path))
        try ensureFreeSpace(path: path, directory: directory, size: initial.size, edit: edit)

        // (2) backup
        let backupPath = try makeBackupPath(for: path)
        var keepBackup = false
        defer { if !keepBackup { FileSystem.remove(backupPath) } }
        let originalHash: String
        do {
            originalHash = try FileSystem.copyFile(from: path, to: backupPath)
            guard try FileSystem.sha256(path: backupPath) == originalHash else {
                throw TagError.backupFailed(path: path, reason: "Prüfsumme der Sicherung stimmt nicht")
            }
            FileSystem.syncDirectory((backupPath as NSString).deletingLastPathComponent)
        } catch let error as TagError {
            throw error
        } catch {
            throw TagError.backupFailed(path: path, reason: "\(error)")
        }

        // (3) temporary copy in the same directory, edit applied there
        let fileName = (path as NSString).lastPathComponent
        let tempName = SafeTagWriter.componentName(prefix: "\(SafeTagWriter.tempPrefix)\(UUID().uuidString)-", fileName: fileName)
        let tempPath = (directory as NSString).appendingPathComponent(tempName)
        var committed = false
        defer { if !committed { FileSystem.remove(tempPath) } }
        let tempURL = URL(fileURLWithPath: tempPath)
        do {
            let tempHash = try FileSystem.copyFile(from: path, to: tempPath)
            guard tempHash == originalHash else { throw TagError.originalModified(path: path) }
        } catch let error as TagError {
            throw error
        } catch {
            throw TagError.writeFailed(path: path, reason: "\(error)")
        }
        do {
            try hooks.applyEdit(tempURL, edit)
            try FileSystem.sync(path: tempPath)
        } catch let error as TagError {
            throw TagError.writeFailed(path: path, reason: error.localizedDescription)
        } catch {
            throw TagError.writeFailed(path: path, reason: "\(error)")
        }

        // (4) verification
        let expected = TagFile.expectedValues(before: before.values, edit: edit, traits: traits)
        let after: TagReadResult
        do {
            after = try TagFile.inspect(url: tempURL).result
        } catch {
            throw TagError.verificationFailed(path: path, details: ["Datei nach dem Schreiben nicht lesbar: \(error)"])
        }
        var problems = SafeTagWriter.differences(before: before, after: after, expected: expected, edit: edit,
                                                 traits: traits, toleranceMs: configuration.durationToleranceMs,
                                                 checkUntouched: configuration.verifyUntouchedFields)
        // byte-exact comparison of the audio data (independent of TagLib's audio properties)
        if let audioBefore {
            let audioAfter = try? TagFile.audioPayloadChecksum(url: tempURL)
            if audioAfter != audioBefore { problems.append("Audiodaten verändert") }
        }
        guard problems.isEmpty else { throw TagError.verificationFailed(path: path, details: problems) }

        // (5) original unchanged? then replace atomically
        try hooks.beforeReplace?(URL(fileURLWithPath: path))
        guard let current = FileSystem.fileStat(path), current.isUnchanged(comparedTo: initial) else {
            throw TagError.originalModified(path: path)
        }
        FileSystem.copyMetadata(from: path, to: tempPath, stat: initial)
        let resultHash: String
        do {
            resultHash = try FileSystem.sha256(path: tempPath)
        } catch {
            throw TagError.writeFailed(path: path, reason: "\(error)")
        }
        let resultSize = FileSystem.fileStat(tempPath)?.size ?? 0

        // (6) journal entry first, then replace
        let entry = makeEntry(batchID: batchID, path: path, backupPath: backupPath, edit: edit, traits: traits,
                              before: before.values, after: after.values, originalSize: initial.size,
                              originalHash: originalHash, resultSize: resultSize, resultHash: resultHash)
        try appendToJournal(entry)
        guard let last = FileSystem.fileStat(path), last.isUnchanged(comparedTo: initial) else {
            removeFromJournal(entry)
            throw TagError.originalModified(path: path)
        }
        do {
            try FileSystem.atomicReplace(tempPath, path)
        } catch {
            removeFromJournal(entry)
            throw TagError.replaceFailed(path: path, reason: "\(error)")
        }
        committed = true
        keepBackup = true
        return entry
    }

    /// Schreibt mehrere Dateien; ein Fehler bei einer Datei hält die übrigen nicht auf.
    public func write(batch requests: [TagWriteRequest], batchID: UUID = UUID(),
                      progress: ((Int, Int) -> Void)? = nil) -> TagWriteBatchResult {
        var results: [TagWriteFileResult] = []
        for (index, request) in requests.enumerated() {
            do {
                let entry = try write(url: request.url, edit: request.edit, batchID: batchID)
                results.append(TagWriteFileResult(url: request.url, entry: entry, error: nil))
            } catch let error as TagError {
                results.append(TagWriteFileResult(url: request.url, entry: nil, error: error))
            } catch {
                results.append(TagWriteFileResult(url: request.url, entry: nil,
                                                  error: .internalError(message: "\(error)")))
            }
            progress?(index + 1, requests.count)
        }
        return TagWriteBatchResult(batchID: batchID, results: results)
    }

    // MARK: - Undo

    /// Stellt alle Dateien eines Stapels aus den Sicherungen wieder her (gleiches sicheres Verfahren,
    /// bytegleiche Prüfung per SHA-256). Dateien, die nach der Bearbeitung erneut verändert wurden,
    /// werden nur mit `force` überschrieben.
    public func undo(batch batchID: UUID, force: Bool = false) throws -> TagUndoResult {
        guard var journal = try loadJournal(batchID) else { throw TagError.batchNotFound(batchID: batchID) }
        var results: [TagUndoFileResult] = []
        for index in journal.entries.indices.reversed() {
            let entry = journal.entries[index]
            if entry.undoneAt != nil {
                results.append(TagUndoFileResult(path: entry.originalPath, outcome: .alreadyOriginal))
                continue
            }
            do {
                let outcome = try restore(entry, force: force)
                journal.entries[index].undoneAt = wholeSeconds(hooks.now())
                results.append(TagUndoFileResult(path: entry.originalPath, outcome: outcome))
                try saveJournal(journal)
            } catch let error as TagError {
                results.append(TagUndoFileResult(path: entry.originalPath, outcome: .failed(error)))
            } catch {
                results.append(TagUndoFileResult(path: entry.originalPath,
                                                 outcome: .failed(.internalError(message: "\(error)"))))
            }
        }
        return TagUndoResult(batchID: batchID, results: results)
    }

    private func restore(_ entry: TagWriteJournalEntry, force: Bool) throws -> TagUndoFileResult.Outcome {
        let path = entry.originalPath
        let backup = entry.backupPath
        guard FileSystem.fileStat(backup)?.isRegularFile == true else { throw TagError.backupMissing(path: path) }
        guard (try? FileSystem.sha256(path: backup)) == entry.originalSHA256 else {
            throw TagError.backupCorrupted(path: path)
        }
        guard let initial = FileSystem.fileStat(path) else { throw TagError.fileNotFound(path: path) }
        guard initial.isRegularFile else { throw TagError.notAFile(path: path) }
        let currentHash: String
        do {
            currentHash = try FileSystem.sha256(path: path)
        } catch {
            throw TagError.cannotOpen(path: path)
        }
        if currentHash == entry.originalSHA256 { return .alreadyOriginal }
        if currentHash != entry.resultSHA256 && !force { throw TagError.modifiedSinceWrite(path: path) }
        guard FileSystem.canWriteFile(path) else { throw TagError.fileReadOnly(path: path) }
        let directory = (path as NSString).deletingLastPathComponent
        guard FileSystem.canWriteDirectory(directory) else { throw TagError.directoryNotWritable(path: path) }
        let needed = entry.originalSize + configuration.freeSpaceReserve
        if let free = hooks.freeSpace(directory), free < needed {
            throw TagError.insufficientDiskSpace(path: path, required: needed, available: free)
        }

        let fileName = (path as NSString).lastPathComponent
        let tempName = SafeTagWriter.componentName(prefix: "\(SafeTagWriter.tempPrefix)restore-\(UUID().uuidString)-",
                                                   fileName: fileName)
        let tempPath = (directory as NSString).appendingPathComponent(tempName)
        var committed = false
        defer { if !committed { FileSystem.remove(tempPath) } }
        do {
            let hash = try FileSystem.copyFile(from: backup, to: tempPath)
            guard hash == entry.originalSHA256 else { throw TagError.backupCorrupted(path: path) }
        } catch let error as TagError {
            throw error
        } catch {
            throw TagError.replaceFailed(path: path, reason: "\(error)")
        }
        FileSystem.copyMetadata(from: path, to: tempPath, stat: initial)
        try hooks.beforeReplace?(URL(fileURLWithPath: path))
        guard let current = FileSystem.fileStat(path), current.isUnchanged(comparedTo: initial) else {
            throw TagError.originalModified(path: path)
        }
        do {
            try FileSystem.atomicReplace(tempPath, path)
        } catch {
            throw TagError.replaceFailed(path: path, reason: "\(error)")
        }
        committed = true
        guard (try? FileSystem.sha256(path: path)) == entry.originalSHA256 else {
            throw TagError.restoreVerificationFailed(path: path)
        }
        return .restored
    }

    // MARK: - Journal

    /// Journal eines Stapels (`nil` = nicht vorhanden).
    public func journal(batch batchID: UUID) throws -> TagWriteJournal? {
        try loadJournal(batchID)
    }

    /// Alle vorhandenen Journale, neueste zuerst.
    public func journals() -> [TagWriteJournal] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: journalDirectory.path)) ?? []
        return files.filter { $0.hasSuffix(".json") }
            .compactMap { try? decodeJournal(at: journalDirectory.appendingPathComponent($0).path) }
            .sorted { $0.created > $1.created }
    }

    private func journalPath(_ batchID: UUID) -> String {
        journalDirectory.appendingPathComponent("\(batchID.uuidString).json").path
    }

    private func decodeJournal(at path: String) throws -> TagWriteJournal {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TagWriteJournal.self, from: data)
    }

    private func loadJournal(_ batchID: UUID) throws -> TagWriteJournal? {
        lock.lock()
        defer { lock.unlock() }
        let path = journalPath(batchID)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        do {
            return try decodeJournal(at: path)
        } catch {
            throw TagError.journalFailed(reason: "\(error)")
        }
    }

    private func saveJournal(_ journal: TagWriteJournal) throws {
        lock.lock()
        defer { lock.unlock() }
        try saveJournalLocked(journal)
    }

    private func saveJournalLocked(_ journal: TagWriteJournal) throws {
        do {
            try FileManager.default.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try FileSystem.writeAtomically(try encoder.encode(journal), to: journalPath(journal.batchID))
        } catch {
            throw TagError.journalFailed(reason: "\(error)")
        }
    }

    private func appendToJournal(_ entry: TagWriteJournalEntry) throws {
        lock.lock()
        defer { lock.unlock() }
        let path = journalPath(entry.batchID)
        var journal: TagWriteJournal
        if FileManager.default.fileExists(atPath: path) {
            do {
                journal = try decodeJournal(at: path)
            } catch {
                throw TagError.journalFailed(reason: "\(error)")
            }
        } else {
            journal = TagWriteJournal(batchID: entry.batchID, created: entry.timestamp, entries: [])
        }
        journal.entries.append(entry)
        try saveJournalLocked(journal)
    }

    private func removeFromJournal(_ entry: TagWriteJournalEntry) {
        lock.lock()
        defer { lock.unlock() }
        let path = journalPath(entry.batchID)
        guard var journal = try? decodeJournal(at: path) else { return }
        journal.entries.removeAll { $0.id == entry.id }
        if journal.entries.isEmpty {
            FileSystem.remove(path)
        } else {
            try? saveJournalLocked(journal)
        }
    }

    // MARK: - Cleanup

    /// Löscht Sicherungen (Tagesordner) und Journale, die älter als `days` Tage sind.
    /// Liefert die Anzahl der gelöschten Sicherungsdateien.
    @discardableResult
    public func cleanupBackups(olderThan days: Int, now: Date? = nil) throws -> Int {
        let reference = now ?? hooks.now()
        let cutoff = reference.addingTimeInterval(-Double(max(0, days)) * 86_400)
        let fm = FileManager.default
        let root = configuration.backupRoot.path
        var removed = 0
        lock.lock()
        defer { lock.unlock() }
        let formatter = SafeTagWriter.dayFormatter()
        let calendar = Calendar(identifier: .gregorian)
        for name in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
            guard name.count == 10, let day = formatter.date(from: name),
                  let endOfDay = calendar.date(byAdding: .day, value: 1, to: day), endOfDay <= cutoff else { continue }
            let folder = (root as NSString).appendingPathComponent(name)
            let count = ((try? fm.contentsOfDirectory(atPath: folder)) ?? []).count
            do {
                try fm.removeItem(atPath: folder)
                removed += count
            } catch {
                throw TagError.journalFailed(reason: "Sicherungsordner „\(name)“ konnte nicht gelöscht werden: \(error)")
            }
        }
        let journalDir = journalDirectory.path
        for name in (try? fm.contentsOfDirectory(atPath: journalDir)) ?? [] where name.hasSuffix(".json") {
            let path = (journalDir as NSString).appendingPathComponent(name)
            guard let journal = try? decodeJournal(at: path) else { continue }
            let newest = journal.entries.map(\.timestamp).max() ?? journal.created
            if newest < cutoff { try? fm.removeItem(atPath: path) }
        }
        return removed
    }

    // MARK: - Leftovers

    /// Präfix der versteckten temporären Dateien neben den Originalen.
    public static let tempPrefix = ".mltags-"

    /// Entfernt temporäre Dateien („.mltags-…“), die ein Absturz während des Schreibens in `directory`
    /// hinterlassen hat und die älter als `age` Sekunden sind. Originale werden nie angefasst.
    @discardableResult
    public static func removeLeftoverTemporaryFiles(in directory: URL, olderThan age: TimeInterval = 3600) -> Int {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-age)
        var removed = 0
        for name in (try? fm.contentsOfDirectory(atPath: directory.path)) ?? [] where name.hasPrefix(tempPrefix) {
            let path = directory.appendingPathComponent(name).path
            guard let st = FileSystem.fileStat(path), st.isRegularFile,
                  Date(timeIntervalSince1970: TimeInterval(st.modificationSeconds)) < cutoff else { continue }
            if (try? fm.removeItem(atPath: path)) != nil { removed += 1 }
        }
        return removed
    }

    // MARK: - Helpers

    /// `prefix + fileName`, gekürzt auf höchstens 255 UTF-8-Bytes (NAME_MAX); die Endung bleibt erhalten.
    static func componentName(prefix: String, fileName: String) -> String {
        let limit = 255
        let full = prefix + fileName
        if full.utf8.count <= limit { return full }
        let ext = (fileName as NSString).pathExtension
        let suffix = ext.isEmpty ? "" : "." + ext
        var base = (fileName as NSString).deletingPathExtension
        while !base.isEmpty, (prefix + base + suffix).utf8.count > limit { base.removeLast() }
        return prefix + base + suffix
    }

    /// Journal dates are stored as ISO 8601 without fractions; keep entries identical after a round trip.
    private func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    static func dayFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    private func inspectOriginal(_ path: String) throws -> (TagReadResult, TagFormatTraits, String?) {
        let url = URL(fileURLWithPath: path)
        let (result, traits) = try TagFile.inspect(url: url)
        if !result.writable {
            let file = try BridgeFile(path: path, readOnly: true, readAudioProperties: false)
            let reason = file.isFormatWritable ? "Datei oder Ordner schreibgeschützt" : file.writableReason
            return (result, traits, reason)
        }
        return (result, traits, nil)
    }

    private func ensureFreeSpace(path: String, directory: String, size: Int64, edit: TagEdit) throws {
        var growth: Int64 = 1 << 20
        if case .replaceAll(let pictures) = edit.pictures {
            growth += pictures.reduce(0) { $0 + Int64($1.data.count) }
        }
        growth += Int64((edit.values.lyrics?.utf8.count ?? 0) + (edit.values.comment?.utf8.count ?? 0))
        let reserve = configuration.freeSpaceReserve
        let root = configuration.backupRoot.path
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        let sameVolume = FileSystem.fileStat(root)?.device == FileSystem.fileStat(directory)?.device
        if sameVolume {
            let needed = size + size + growth + reserve
            if let free = hooks.freeSpace(directory), free < needed {
                throw TagError.insufficientDiskSpace(path: path, required: needed, available: free)
            }
        } else {
            let neededHere = size + growth + reserve
            if let free = hooks.freeSpace(directory), free < neededHere {
                throw TagError.insufficientDiskSpace(path: path, required: neededHere, available: free)
            }
            let neededBackup = size + reserve
            if let free = hooks.freeSpace(root), free < neededBackup {
                throw TagError.insufficientDiskSpace(path: path, required: neededBackup, available: free)
            }
        }
    }

    private func makeBackupPath(for path: String) throws -> String {
        let day = SafeTagWriter.dayFormatter().string(from: hooks.now())
        let folder = configuration.backupRoot.appendingPathComponent(day, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw TagError.backupFailed(path: path, reason: "\(error)")
        }
        let name = SafeTagWriter.componentName(prefix: "\(UUID().uuidString)-", fileName: (path as NSString).lastPathComponent)
        return folder.appendingPathComponent(name).path
    }

    private func makeEntry(batchID: UUID, path: String, backupPath: String, edit: TagEdit, traits: TagFormatTraits,
                           before: TagValues, after: TagValues, originalSize: Int64, originalHash: String,
                           resultSize: Int64, resultHash: String) -> TagWriteJournalEntry {
        func short(_ s: String) -> String { s.count > 200 ? String(s.prefix(200)) + "…" : s }
        var changed: [String] = []
        var skipped: [String] = []
        var beforeSummary: [String: String] = [:]
        var afterSummary: [String: String] = [:]
        for field in TagField.allCases where edit.fields.contains(field) {
            if traits.supportedFields.contains(field) {
                changed.append(field.rawValue)
                beforeSummary[field.rawValue] = short(before.text(for: field))
                afterSummary[field.rawValue] = short(after.text(for: field))
            } else {
                skipped.append(field.rawValue)
            }
        }
        if case .replaceAll = edit.pictures {
            changed.append("pictures")
            beforeSummary["pictures"] = SafeTagWriter.pictureSummary(before.pictures)
            afterSummary["pictures"] = SafeTagWriter.pictureSummary(after.pictures)
        }
        return TagWriteJournalEntry(id: UUID(), batchID: batchID, timestamp: wholeSeconds(hooks.now()), originalPath: path,
                                    backupPath: backupPath, fieldsChanged: changed, skippedFields: skipped,
                                    before: beforeSummary, after: afterSummary, originalSize: originalSize,
                                    originalSHA256: originalHash, resultSize: resultSize, resultSHA256: resultHash,
                                    undoneAt: nil)
    }

    static func pictureSummary(_ pictures: [EmbeddedPicture]) -> String {
        if pictures.isEmpty { return "keine Bilder" }
        return pictures.map { "\($0.kind.label) (\($0.mimeType), \($0.data.count) Bytes)" }.joined(separator: "; ")
    }

    /// Vergleicht die gelesenen Werte nach dem Schreiben mit den erwarteten (deutsche Beschreibungen).
    static func differences(before: TagReadResult, after: TagReadResult, expected: TagValues, edit: TagEdit,
                            traits: TagFormatTraits, toleranceMs: Int64, checkUntouched: Bool) -> [String] {
        func short(_ s: String) -> String { s.count > 60 ? String(s.prefix(60)) + "…" : s }
        var problems: [String] = []
        func listKey(_ values: TagValues, _ field: TagField) -> String {
            // order-insensitive comparison where TagLib does not keep the order (WMA)
            guard traits.unstableValueOrder, field.isList else { return values.text(for: field) }
            return values.text(for: field).components(separatedBy: "; ").sorted().joined(separator: "; ")
        }
        for field in TagField.allCases {
            let edited = edit.fields.contains(field) && traits.supportedFields.contains(field)
            if !edited && !checkUntouched { continue }
            if listKey(expected, field) != listKey(after.values, field) {
                let want = expected.text(for: field)
                let got = after.values.text(for: field)
                problems.append("\(field.label): erwartet „\(short(want))“, gelesen „\(short(got))“")
            }
        }
        let picturesEdited: Bool
        if case .replaceAll = edit.pictures { picturesEdited = true } else { picturesEdited = false }
        func pictureOrder(_ pictures: [EmbeddedPicture]) -> [EmbeddedPicture] {
            guard traits.unstableValueOrder else { return pictures }
            return pictures.sorted {
                ($0.kind.rawValue, $0.mimeType, $0.description, $0.data.count, SHA256Digest.hex($0.data))
                    < ($1.kind.rawValue, $1.mimeType, $1.description, $1.data.count, SHA256Digest.hex($1.data))
            }
        }
        if (picturesEdited || checkUntouched) && pictureOrder(expected.pictures) != pictureOrder(after.values.pictures) {
            if expected.pictures.count != after.values.pictures.count {
                problems.append("Bilder: erwartet \(expected.pictures.count), gelesen \(after.values.pictures.count)")
            } else {
                problems.append("Bilder weichen ab")
            }
        }
        let a = before.audio
        let b = after.audio
        if abs(a.durationMs - b.durationMs) > toleranceMs {
            problems.append("Dauer: vorher \(a.durationMs) ms, nachher \(b.durationMs) ms")
        }
        if a.sampleRate != b.sampleRate { problems.append("Abtastrate: vorher \(a.sampleRate), nachher \(b.sampleRate)") }
        if a.channels != b.channels { problems.append("Kanäle: vorher \(a.channels), nachher \(b.channels)") }
        if a.codec != b.codec { problems.append("Codec: vorher \(a.codec), nachher \(b.codec)") }
        if a.bitsPerSample != b.bitsPerSample {
            problems.append("Bittiefe: vorher \(a.bitsPerSample), nachher \(b.bitsPerSample)")
        }
        if before.fileFormat != after.fileFormat {
            problems.append("Dateiformat: vorher \(before.fileFormat), nachher \(after.fileFormat)")
        }
        return problems
    }
}
