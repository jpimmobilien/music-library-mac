import Foundation
import MLStudio
import StudioEngine

/// Dateiarbeiten des Audio Studios (Hintergrund, nie auf dem Hauptthread): fertige Datei an einen freien
/// Namen verschieben, Original sicher ersetzen (Sicherung mit Prüfung) und das Ersetzen rückgängig machen.
enum StudioFileOps {
    /// Angaben zu einem ersetzten Original, neben der Sicherung gespeichert („ersetzt.json“).
    struct ReplaceRecord: Codable, Hashable {
        var uid: Int64
        var originalPath: String
        var backupPath: String
        var originalSize: Int64
        var originalSHA256: String
        /// Vom Studio geschriebene Datei – „Rückgängig“ nur, solange die Datei noch genau diese ist.
        var writtenSize: Int64
        var writtenSHA256: String
        var date: Date
    }

    static let recordName = "ersetzt.json"

    // MARK: Fertige Datei ablegen

    /// Verschiebt `temp` an einen freien Namen „Name.ext“, „Name (2).ext“ … im Ordner (wird angelegt).
    /// Liegt der Ordner auf einem anderen Laufwerk, wird erst versteckt daneben kopiert und dann umbenannt,
    /// damit nie eine halbe Datei unter dem endgültigen Namen sichtbar ist.
    static func moveIntoPlace(_ temp: URL, directory: String, base: String, ext: String) throws -> String {
        let fm = FileManager.default
        do {
            try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
        } catch {
            throw StudioError.other("Der Zielordner „\(directory)“ konnte nicht angelegt werden: \(error.localizedDescription)")
        }
        let dirURL = URL(fileURLWithPath: directory, isDirectory: true)
        var staged = temp
        if !sameVolume(temp, dirURL) {
            staged = dirURL.appendingPathComponent(".studio-\(UUID().uuidString).\(ext)")
            do {
                try fm.copyItem(at: temp, to: staged)
            } catch {
                try? fm.removeItem(at: staged)
                throw mapWriteError(error)
            }
            try? fm.removeItem(at: temp)
        }
        for _ in 0..<100 {
            let path = FileNames.unique(base: base, ext: ext, in: directory, exists: { fm.fileExists(atPath: $0) })
            do {
                try fm.moveItem(at: staged, to: URL(fileURLWithPath: path))
                return path
            } catch {
                // Inzwischen belegt (anderes Programm)? Dann nächsten freien Namen versuchen.
                if fm.fileExists(atPath: path) { continue }
                if staged != temp { try? fm.removeItem(at: staged) }
                throw mapWriteError(error)
            }
        }
        throw StudioError.other("Im Zielordner wurde kein freier Dateiname gefunden.")
    }

    static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let ka = try? a.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        let kb = try? b.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        guard let ka = ka as? NSObject, let kb = kb as? NSObject else { return false }
        return ka.isEqual(kb)
    }

    static func mapWriteError(_ error: Error) -> Error {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileWriteOutOfSpaceError { return StudioError.diskFull }
        if ns.domain == NSPOSIXErrorDomain, ns.code == Int(ENOSPC) { return StudioError.diskFull }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSPOSIXErrorDomain, underlying.code == Int(ENOSPC) {
            return StudioError.diskFull
        }
        return error is StudioError ? error : StudioError.other(error.localizedDescription)
    }

    // MARK: Original ersetzen

    /// Ersetzt das Original durch `exported`: Sicherung nach `backupsRoot/<Datum>/` (Größe und SHA-256 geprüft),
    /// dann atomarer Austausch im selben Ordner (`replaceItemAt`) und Prüfung des Ergebnisses.
    /// Ein laufender Hauptplayer liest die alte Datei ungestört weiter (Austausch per Umbenennen).
    static func replaceOriginal(at path: String, with exported: URL, uid: Int64, backupsRoot: URL, now: Date = Date()) throws -> ReplaceRecord {
        let fm = FileManager.default
        let original = URL(fileURLWithPath: path)
        guard fm.fileExists(atPath: path) else { throw StudioError.other("Das Original wurde nicht gefunden: \(path)") }
        let newSize = size(exported)
        guard newSize > 0 else { throw StudioError.encodeFailed("Die neue Datei ist leer – das Original bleibt unverändert.") }

        // 1. Sicherung anlegen und prüfen
        let dir = try uniqueBackupDirectory(in: backupsRoot, date: now)
        let backup = dir.appendingPathComponent(original.lastPathComponent)
        do {
            try fm.copyItem(at: original, to: backup)
        } catch {
            try? fm.removeItem(at: dir)
            throw StudioError.other("Das Original konnte nicht gesichert werden – es bleibt unverändert. \(error.localizedDescription)")
        }
        let originalSize = size(original)
        let originalHash = try ToolChecksum.sha256(of: original)
        guard size(backup) == originalSize, (try? ToolChecksum.sha256(of: backup)) == originalHash else {
            try? fm.removeItem(at: dir)
            throw StudioError.other("Die Sicherung des Originals stimmt nicht mit dem Original überein – es bleibt unverändert.")
        }

        // 2. Neue Datei auf dasselbe Laufwerk legen (versteckt neben dem Original) und atomar austauschen
        let staged = original.deletingLastPathComponent().appendingPathComponent(".\(original.lastPathComponent).studio-neu")
        try? fm.removeItem(at: staged)
        do {
            try fm.copyItem(at: exported, to: staged)
        } catch {
            try? fm.removeItem(at: staged)
            throw mapWriteError(error)
        }
        let writtenHash = try ToolChecksum.sha256(of: staged)
        let writtenSize = size(staged)
        do {
            _ = try fm.replaceItemAt(original, withItemAt: staged, backupItemName: nil, options: [])
        } catch {
            try? fm.removeItem(at: staged)
            throw StudioError.other("Das Original konnte nicht ersetzt werden – es bleibt unverändert. \(error.localizedDescription)")
        }

        // 3. Ergebnis prüfen
        guard (try? ToolChecksum.sha256(of: original)) == writtenHash else {
            throw StudioError.other("Das Ersetzen konnte nicht bestätigt werden. Die Sicherung liegt unter „\(backup.path)“.")
        }
        let record = ReplaceRecord(uid: uid, originalPath: path, backupPath: backup.path, originalSize: originalSize, originalSHA256: originalHash,
                                   writtenSize: writtenSize, writtenSHA256: writtenHash, date: now)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(record).write(to: dir.appendingPathComponent(recordName), options: .atomic)
        return record
    }

    /// Stellt das Original aus der Sicherung wieder her – nur, wenn die Datei noch genau die vom Studio
    /// geschriebene ist (sonst gingen spätere Änderungen verloren).
    static func undoReplace(backupPath: String) throws -> ReplaceRecord {
        let fm = FileManager.default
        let backup = URL(fileURLWithPath: backupPath)
        let recordURL = backup.deletingLastPathComponent().appendingPathComponent(recordName)
        guard let data = try? Data(contentsOf: recordURL), let record = try? JSONDecoder().decode(ReplaceRecord.self, from: data) else {
            throw StudioError.other("Zu dieser Sicherung fehlen die Angaben – Rückgängig ist nicht möglich.")
        }
        guard fm.fileExists(atPath: backup.path) else { throw StudioError.other("Die Sicherung wurde nicht gefunden: \(backup.path)") }
        let original = URL(fileURLWithPath: record.originalPath)
        guard fm.fileExists(atPath: original.path) else {
            throw StudioError.other("Die Datei liegt nicht mehr am ursprünglichen Ort. Die Sicherung liegt unter „\(backup.path)“.")
        }
        guard (try? ToolChecksum.sha256(of: original)) == record.writtenSHA256 else {
            throw StudioError.other("Die Datei wurde nach dem Schneiden verändert – Rückgängig würde diese Änderungen überschreiben. Die Sicherung liegt unter „\(backup.path)“.")
        }
        guard (try? ToolChecksum.sha256(of: backup)) == record.originalSHA256 else {
            throw StudioError.other("Die Sicherung ist beschädigt – das Original kann nicht wiederhergestellt werden.")
        }
        let staged = original.deletingLastPathComponent().appendingPathComponent(".\(original.lastPathComponent).studio-zurueck")
        try? fm.removeItem(at: staged)
        do {
            try fm.copyItem(at: backup, to: staged)
            _ = try fm.replaceItemAt(original, withItemAt: staged, backupItemName: nil, options: [])
        } catch {
            try? fm.removeItem(at: staged)
            throw StudioError.other("Das Original konnte nicht wiederhergestellt werden. \(error.localizedDescription)")
        }
        guard (try? ToolChecksum.sha256(of: original)) == record.originalSHA256 else {
            throw StudioError.other("Die Wiederherstellung konnte nicht bestätigt werden. Die Sicherung liegt unter „\(backup.path)“.")
        }
        return record
    }

    static func uniqueBackupDirectory(in root: URL, date: Date) throws -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let base = f.string(from: date)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var candidate = root.appendingPathComponent(base, isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = root.appendingPathComponent("\(base) (\(n))", isDirectory: true)
            n += 1
        }
        try fm.createDirectory(at: candidate, withIntermediateDirectories: true)
        return candidate
    }

    static func size(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Liegt der Pfad in einem der Ordner?
    static func isInside(_ path: String, folders: [String]) -> Bool {
        folders.contains { root in
            let base = root.hasSuffix("/") ? root : root + "/"
            return path.hasPrefix(base)
        }
    }
}
