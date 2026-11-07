import Darwin
import Foundation
import CryptoKit
import AetherC
import AetherCore

/// Durchsucht einen Ordner (nur lesend): Größen, Kategorien, größte Dateien und Ordner, Duplikate (SHA-256).
/// Läuft im Hintergrund, kann jederzeit abgebrochen werden und folgt keinen symbolischen Links und keinen anderen
/// Volumes. Was macOS nicht lesen lässt (Datenschutz), wird gezählt – nicht geschätzt.
public final class StorageScanner: @unchecked Sendable {
    public struct Progress: Sendable, Equatable {
        public enum Phase: Sendable, Equatable { case scanning, comparing }
        public var phase: Phase
        public var files: Int
        public var bytes: Int64
        /// Beim Vergleichen: Anzahl der Dateien, deren Prüfsumme berechnet wird, und wie viele fertig sind.
        public var total: Int
        public var done: Int
        public var currentPath: String

        public init(phase: Phase, files: Int, bytes: Int64, total: Int, done: Int, currentPath: String) {
            self.phase = phase
            self.files = files
            self.bytes = bytes
            self.total = total
            self.done = done
            self.currentPath = currentPath
        }
    }

    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// Zähler für den Fehler-Rückruf des Dateisystem-Durchlaufs.
    private final class ErrorLog: @unchecked Sendable {
        var count = 0
        var samples: [String] = []
        func record(_ url: URL) {
            count += 1
            if samples.count < 12 { samples.append(url.path) }
        }
    }

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isRegularFileKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey,
    ]
    private static let keySet = Set(keys)

    /// Gerät und Inode eines Pfads (ohne symbolischen Links zu folgen).
    static func identity(_ path: String) -> (device: UInt64, inode: UInt64)? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return (UInt64(bitPattern: Int64(info.st_dev)), UInt64(info.st_ino))
    }

    /// Belegter Platz eines Ordnerbaums (für Pakete und Bereinigungsorte).
    private static func treeSize(_ url: URL, errors: ErrorLog?, isCancelled: () -> Bool) -> (bytes: Int64, items: Int) {
        let log = errors
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [],
                                                              errorHandler: { failed, _ in log?.record(failed); return true }) else {
            return (0, 0)
        }
        var bytes: Int64 = 0
        var items = 0
        while let item = enumerator.nextObject() as? URL {
            if items % 2_000 == 0, isCancelled() { break }
            guard let values = try? item.resourceValues(forKeys: keySet) else { continue }
            if values.isSymbolicLink == true || values.isDirectory == true { continue }
            bytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            items += 1
        }
        return (bytes, items)
    }

    /// Ordner durchsuchen. `retainAtLeast` = ab dieser Größe werden Dateien für Listen und Duplikate behalten.
    public func scan(root: URL, retainAtLeast: Int64 = 1_000_000, findDuplicates: Bool = true,
                     duplicateMinimum: Int64 = 1_000_000,
                     progress: @escaping @Sendable (Progress) -> Void) -> StorageScanResult {
        let rootURL = root.standardizedFileURL
        let rootPath = rootURL.path
        var tally = StorageTally(rootPath: rootPath, retainThreshold: min(retainAtLeast, duplicateMinimum))
        let errors = ErrorLog()
        let rootDevice = Self.identity(rootPath)?.device
        var skippedVolumes = 0
        var lastReport = Date.distantPast
        var currentBytes: Int64 = 0

        func report(_ path: String, force: Bool = false) {
            let now = Date()
            guard force || now.timeIntervalSince(lastReport) >= 0.25 else { return }
            lastReport = now
            progress(Progress(phase: .scanning, files: tally.fileCount, bytes: currentBytes, total: 0, done: 0, currentPath: path))
        }

        let log = errors
        if let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: Self.keys, options: [],
                                                           errorHandler: { failed, _ in log.record(failed); return true }) {
            var visited = 0
            while let url = enumerator.nextObject() as? URL {
                visited += 1
                if visited % 500 == 0, isCancelled { break }
                guard let values = try? url.resourceValues(forKeys: Self.keySet) else {
                    errors.record(url)
                    continue
                }
                if values.isSymbolicLink == true { continue }
                let path = url.path
                if values.isDirectory == true {
                    // Andere Volumes (eingehängt unterhalb des Ordners) nicht mitzählen – wie „du -x“.
                    if let rootDevice, let identity = Self.identity(path), identity.device != rootDevice {
                        skippedVolumes += 1
                        enumerator.skipDescendants()
                        continue
                    }
                    if values.isPackage == true {
                        enumerator.skipDescendants()
                        let size = Self.treeSize(url, errors: errors, isCancelled: { self.isCancelled })
                        let identity = Self.identity(path)
                        let file = ScannedFile(path: path, size: size.bytes, logicalSize: size.bytes,
                                               modified: values.contentModificationDate,
                                               category: FileCategory.classify(fileName: url.lastPathComponent), isPackage: true,
                                               device: identity?.device ?? 0, inode: identity?.inode ?? 0)
                        tally.add(file)
                        currentBytes += size.bytes
                    } else {
                        tally.addFolder()
                    }
                    report(path)
                    continue
                }
                guard values.isRegularFile == true else { continue }
                let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
                let logical = Int64(values.fileSize ?? 0)
                var device: UInt64 = 0
                var inode: UInt64 = 0
                if size >= tally.retainThreshold || logical >= tally.retainThreshold, let identity = Self.identity(path) {
                    device = identity.device
                    inode = identity.inode
                }
                tally.add(ScannedFile(path: path, size: size, logicalSize: logical, modified: values.contentModificationDate,
                                      category: FileCategory.classify(fileName: url.lastPathComponent), isPackage: false,
                                      device: device, inode: inode))
                currentBytes += size
                report(path)
            }
        } else {
            errors.record(rootURL)
        }
        report(rootPath, force: true)

        let retained = tally.retained.sorted { $0.size != $1.size ? $0.size > $1.size : $0.path < $1.path }
        var duplicates: [DuplicateGroup] = []
        var checked = false
        if findDuplicates, !isCancelled {
            duplicates = findDuplicateGroups(retained, minimum: duplicateMinimum, scannedFiles: tally.fileCount,
                                             scannedBytes: currentBytes, progress: progress)
            checked = !isCancelled
        }
        return StorageScanResult(rootPath: rootPath, totalSize: tally.totalSize, fileCount: tally.fileCount,
                                 folderCount: tally.folderCount, unreadableCount: errors.count, unreadableSamples: errors.samples,
                                 files: retained, folders: tally.folders(), categories: tally.categories(),
                                 duplicates: duplicates, duplicatesChecked: checked, cancelled: isCancelled, finished: Date(),
                                 skippedOtherVolumes: skippedVolumes)
    }

    /// Zweistufig: erst die ersten 64 KiB, dann für verbleibende Kandidaten die ganze Datei (SHA-256).
    private func findDuplicateGroups(_ files: [ScannedFile], minimum: Int64, scannedFiles: Int, scannedBytes: Int64,
                                     progress: @escaping @Sendable (Progress) -> Void) -> [DuplicateGroup] {
        let candidates = DuplicateFinder.candidates(files, minimumSize: minimum)
        guard !candidates.isEmpty else { return [] }

        // Stufe 1: Anfang der Datei
        var prefixHashes: [String: String] = [:]
        for group in candidates {
            if isCancelled { return [] }
            for file in group {
                if let hash = Self.sha256(path: file.path, limit: 64 * 1024, isCancelled: { self.isCancelled }) {
                    prefixHashes[file.path] = hash
                }
            }
        }
        let narrowed = DuplicateFinder.groups(candidates: candidates, hashes: prefixHashes).map(\.files)
        let total = narrowed.reduce(0) { $0 + $1.count }
        var done = 0
        var lastReport = Date.distantPast

        // Stufe 2: ganze Datei
        var fullHashes: [String: String] = [:]
        for group in narrowed {
            for file in group {
                if isCancelled { return [] }
                let now = Date()
                if now.timeIntervalSince(lastReport) >= 0.25 {
                    lastReport = now
                    progress(Progress(phase: .comparing, files: scannedFiles, bytes: scannedBytes, total: total, done: done,
                                      currentPath: file.path))
                }
                if file.logicalSize <= 64 * 1024 {
                    if let hash = prefixHashes[file.path] { fullHashes[file.path] = hash }
                } else if let hash = Self.sha256(path: file.path, limit: nil, isCancelled: { self.isCancelled }) {
                    fullHashes[file.path] = hash
                }
                done += 1
            }
        }
        progress(Progress(phase: .comparing, files: scannedFiles, bytes: scannedBytes, total: total, done: done, currentPath: ""))
        var mayShare = Set<String>()
        let groups = DuplicateFinder.groups(candidates: narrowed, hashes: fullHashes)
        for group in groups {
            for file in group.files where Self.mayShareBlocks(file.path) == true {
                mayShare.insert(file.path)
            }
        }
        return DuplicateFinder.groups(candidates: narrowed, hashes: fullHashes, mayShareBlocks: mayShare)
    }

    /// SHA-256 als Hex-Text, in Blöcken von 1 MiB gelesen. `limit` = nur die ersten Bytes.
    static func sha256(path: String, limit: Int?, isCancelled: () -> Bool) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        var blocks = 0
        while remaining > 0 {
            let chunkSize = min(1_048_576, remaining)
            let chunk: Data
            do {
                guard let data = try handle.read(upToCount: chunkSize) else { break }
                chunk = data
            } catch {
                return nil
            }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            remaining -= chunk.count
            blocks += 1
            if blocks % 64 == 0, isCancelled() { return nil }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// APFS: Datei kann ihre Datenblöcke mit anderen Dateien teilen (Klon). `nil` = Angabe nicht verfügbar.
    public static func mayShareBlocks(_ path: String) -> Bool? {
        var flag = false
        let ok = path.withCString { aether_file_may_share_blocks($0, &flag) }
        return ok ? flag : nil
    }

    // MARK: - Bereinigungsorte

    /// Misst einen bekannten Ort im Benutzerordner. Löscht nichts.
    public static func measure(_ kind: CleanupKind, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                               isCancelled: () -> Bool = { false }) -> CleanupMeasurement {
        var url = home.appendingPathComponent(kind.relativePath, isDirectory: true)
        if kind == .trash, let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first {
            url = trash
        }
        let path = url.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return CleanupMeasurement(kind: kind, path: path, state: .notPresent)
        }
        // Lässt macOS den Ordner selbst nicht lesen (Datenschutz), gibt es keine Zahl.
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: path)
        } catch {
            return CleanupMeasurement(kind: kind, path: path, state: .notReadable)
        }
        let errors = ErrorLog()
        let size = treeSize(url, errors: errors, isCancelled: isCancelled)
        return CleanupMeasurement(kind: kind, path: path, state: .measured(bytes: size.bytes, items: size.items, partial: errors.count > 0))
    }
}
