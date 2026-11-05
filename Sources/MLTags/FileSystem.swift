import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Fehler einer POSIX-Dateioperation (intern; wird in `TagError` übersetzt).
struct FileSystemError: Error, CustomStringConvertible {
    let operation: String
    let path: String
    let code: Int32

    init(_ operation: String, _ path: String, code: Int32 = errno) {
        self.operation = operation
        self.path = path
        self.code = code
    }

    var description: String {
        "\(operation) „\((path as NSString).lastPathComponent)“: \(String(cString: strerror(code)))"
    }
}

/// Angaben aus stat(2), die für die Änderungserkennung gebraucht werden.
struct FileStat: Equatable {
    var size: Int64
    var modificationSeconds: Int64
    var modificationNanoseconds: Int64
    var inode: UInt64
    var device: UInt64
    var mode: UInt32
    var owner: UInt32
    var group: UInt32
    var isRegularFile: Bool
    var isDirectory: Bool

    /// Gleiche Datei mit unverändertem Inhalt (Größe, Änderungszeit, Inode, Gerät)?
    func isUnchanged(comparedTo other: FileStat) -> Bool {
        size == other.size && modificationSeconds == other.modificationSeconds
            && modificationNanoseconds == other.modificationNanoseconds && inode == other.inode
            && device == other.device
    }
}

/// POSIX-Dateioperationen mit fsync (intern).
enum FileSystem {
    static func fileStat(_ path: String) -> FileStat? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        #if os(Linux)
        let seconds = Int64(st.st_mtim.tv_sec)
        let nanos = Int64(st.st_mtim.tv_nsec)
        #else
        let seconds = Int64(st.st_mtimespec.tv_sec)
        let nanos = Int64(st.st_mtimespec.tv_nsec)
        #endif
        let type = UInt32(truncatingIfNeeded: st.st_mode) & UInt32(S_IFMT)
        // field types differ between Darwin and Glibc (dev_t is Int32 on Darwin, mode_t UInt16)
        return FileStat(size: Int64(st.st_size), modificationSeconds: seconds, modificationNanoseconds: nanos,
                        inode: UInt64(truncatingIfNeeded: st.st_ino), device: UInt64(truncatingIfNeeded: st.st_dev),
                        mode: UInt32(truncatingIfNeeded: st.st_mode),
                        owner: UInt32(truncatingIfNeeded: st.st_uid), group: UInt32(truncatingIfNeeded: st.st_gid),
                        isRegularFile: type == UInt32(S_IFREG), isDirectory: type == UInt32(S_IFDIR))
    }

    /// Schreibrecht für die Datei: access(2) und gesetztes Schreibbit des Besitzers.
    /// (Das Schreibbit wird zusätzlich geprüft, weil root jede Datei beschreiben darf, eine vom
    /// Benutzer schreibgeschützte Datei aber trotzdem nicht verändert werden soll.)
    static func canWriteFile(_ path: String) -> Bool {
        guard access(path, W_OK) == 0, let st = fileStat(path) else { return false }
        guard st.mode & UInt32(S_IWUSR) != 0 else { return false }
        #if os(macOS)
        // Finder "Geschützt" (uchg) / System-Immutable
        var s = stat()
        if stat(path, &s) == 0, (s.st_flags & UInt32(UF_IMMUTABLE | SF_IMMUTABLE)) != 0 { return false }
        #endif
        return true
    }

    static func canWriteDirectory(_ path: String) -> Bool {
        guard access(path, W_OK | X_OK) == 0, let st = fileStat(path), st.isDirectory else { return false }
        return st.mode & UInt32(S_IWUSR) != 0 || st.mode & UInt32(S_IWGRP | S_IWOTH) != 0
    }

    /// Kann die App diese Datei sicher bearbeiten (Datei und Ordner beschreibbar)?
    static func isUserWritable(path: String) -> Bool {
        canWriteFile(path) && canWriteDirectory((path as NSString).deletingLastPathComponent)
    }

    /// Freier Speicher (Bytes) des Volumes, auf dem `path` liegt.
    static func freeSpace(at path: String) -> Int64? {
        var s = statvfs()
        guard statvfs(path, &s) == 0 else { return nil }
        return Int64(truncatingIfNeeded: UInt64(s.f_bavail)) * Int64(truncatingIfNeeded: UInt64(s.f_frsize))
    }

    /// Kopiert `source` nach `destination` (darf nicht existieren), schreibt sie mit fsync fest
    /// und liefert die SHA-256-Prüfsumme der gelesenen Bytes.
    @discardableResult
    static func copyFile(from source: String, to destination: String, mode: UInt32 = 0o600) throws -> String {
        let input = open(source, O_RDONLY | O_CLOEXEC)
        guard input >= 0 else { throw FileSystemError("Öffnen", source) }
        defer { close(input) }
        let output = open(destination, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode_t(truncatingIfNeeded: mode))
        guard output >= 0 else { throw FileSystemError("Anlegen", destination) }
        var ok = false
        defer {
            close(output)
            if !ok { unlink(destination) }
        }
        var digest = SHA256Digest()
        let size = 1 << 20
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
        defer { buffer.deallocate() }
        while true {
            let n = read(input, buffer, size)
            if n < 0 {
                if errno == EINTR { continue }
                throw FileSystemError("Lesen", source)
            }
            if n == 0 { break }
            digest.update(UnsafeRawBufferPointer(start: buffer, count: n))
            var written = 0
            while written < n {
                let w = write(output, buffer + written, n - written)
                if w < 0 {
                    if errno == EINTR { continue }
                    throw FileSystemError("Schreiben", destination)
                }
                written += w
            }
        }
        try fullSync(output, path: destination)
        ok = true
        return digest.finalize()
    }

    /// SHA-256 (hex) des Dateiinhalts.
    static func sha256(path: String) throws -> String {
        let fd = open(path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { throw FileSystemError("Öffnen", path) }
        defer { close(fd) }
        var digest = SHA256Digest()
        let size = 1 << 20
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
        defer { buffer.deallocate() }
        while true {
            let n = read(fd, buffer, size)
            if n < 0 {
                if errno == EINTR { continue }
                throw FileSystemError("Lesen", path)
            }
            if n == 0 { break }
            digest.update(UnsafeRawBufferPointer(start: buffer, count: n))
        }
        return digest.finalize()
    }

    /// Schreibt den Inhalt einer (von anderer Stelle geschriebenen) Datei fest.
    static func sync(path: String) throws {
        let fd = open(path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { throw FileSystemError("Öffnen", path) }
        defer { close(fd) }
        try fullSync(fd, path: path)
    }

    private static func fullSync(_ fd: Int32, path: String) throws {
        #if os(macOS)
        if fcntl(fd, F_FULLFSYNC) == 0 { return }
        #endif
        guard fsync(fd) == 0 else { throw FileSystemError("Festschreiben", path) }
    }

    /// fsync auf den Ordner, damit Umbenennen/Anlegen dauerhaft ist (Fehler werden ignoriert).
    static func syncDirectory(_ path: String) {
        let fd = open(path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return }
        _ = fsync(fd)
        close(fd)
    }

    /// Ersetzt `destination` atomar durch `source` (gleiches Volume).
    static func atomicReplace(_ source: String, _ destination: String) throws {
        guard rename(source, destination) == 0 else { throw FileSystemError("Ersetzen", destination) }
        syncDirectory((destination as NSString).deletingLastPathComponent)
    }

    static func remove(_ path: String) {
        _ = unlink(path)
    }

    /// Überträgt Rechte, Besitzer und (unter macOS) erweiterte Attribute, Finder-Tags und das
    /// Erstellungsdatum von `original` auf `target`.
    static func copyMetadata(from original: String, to target: String, stat st: FileStat) {
        _ = chmod(target, mode_t(truncatingIfNeeded: st.mode & 0o7777))
        _ = chown(target, uid_t(st.owner), gid_t(st.group))  // only succeeds where allowed
        #if os(macOS)
        copyExtendedAttributes(from: original, to: target)
        if let created = (try? URL(fileURLWithPath: original).resourceValues(forKeys: [.creationDateKey]))?.creationDate {
            var values = URLResourceValues()
            values.creationDate = created
            var url = URL(fileURLWithPath: target)
            try? url.setResourceValues(values)
        }
        // chmod again: setting xattrs/creation date does not change it, but keep the order explicit
        _ = chmod(target, mode_t(truncatingIfNeeded: st.mode & 0o7777))
        #endif
    }

    #if os(macOS)
    private static func copyExtendedAttributes(from source: String, to target: String) {
        let length = listxattr(source, nil, 0, XATTR_NOFOLLOW)
        guard length > 0 else { return }
        var names = [CChar](repeating: 0, count: length)
        guard listxattr(source, &names, length, XATTR_NOFOLLOW) == length else { return }
        var start = 0
        for i in 0..<length where names[i] == 0 {
            let name = String(cString: Array(names[start...i]))
            start = i + 1
            if name.isEmpty { continue }
            let size = getxattr(source, name, nil, 0, 0, XATTR_NOFOLLOW)
            guard size >= 0 else { continue }
            var value = [UInt8](repeating: 0, count: max(size, 1))
            let read = getxattr(source, name, &value, size, 0, XATTR_NOFOLLOW)
            guard read == size else { continue }
            _ = setxattr(target, name, value, size, 0, XATTR_NOFOLLOW)
        }
    }
    #endif

    /// Schreibt Daten atomar (temporäre Datei + Umbenennen) mit fsync.
    static func writeAtomically(_ data: Data, to path: String) throws {
        let temp = path + ".tmp-" + UUID().uuidString
        let fd = open(temp, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw FileSystemError("Anlegen", temp) }
        var ok = false
        defer {
            if !ok { unlink(temp) }
        }
        do {
            try data.withUnsafeBytes { raw in
                var written = 0
                while written < raw.count {
                    let w = write(fd, raw.baseAddress! + written, raw.count - written)
                    if w < 0 {
                        if errno == EINTR { continue }
                        throw FileSystemError("Schreiben", temp)
                    }
                    written += w
                }
            }
            try fullSync(fd, path: temp)
        } catch {
            close(fd)
            throw error
        }
        close(fd)
        try atomicReplace(temp, path)
        ok = true
    }
}
