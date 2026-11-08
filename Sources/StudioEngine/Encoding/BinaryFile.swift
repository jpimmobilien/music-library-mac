import Foundation
import MLStudio

/// Gepufferte Ausgabedatei (C-`FILE*`) mit Fehlerabbildung auf `StudioError` (voller Datenträger → `.diskFull`).
final class BinaryFile {
    private(set) var handle: UnsafeMutablePointer<FILE>?
    let url: URL
    /// Bisher geschriebene Bytes (höchste Position).
    private(set) var length: Int64 = 0
    private var position: Int64 = 0

    /// Legt die Datei neu an (vorhandene wird geleert).
    init(creating url: URL) throws {
        self.url = url
        guard let fp = fopen(url.path, "w+b") else {
            throw BinaryFile.error(errno, action: "Die Zieldatei konnte nicht angelegt werden")
        }
        handle = fp
        setvbuf(fp, nil, _IOFBF, 1 << 20)
    }

    deinit {
        if let fp = handle { fclose(fp) }
    }

    func write(_ pointer: UnsafeRawPointer, count: Int) throws {
        guard count > 0 else { return }
        guard let fp = handle else { throw StudioError.encodeFailed("Datei bereits geschlossen.") }
        let written = fwrite(pointer, 1, count, fp)
        if written != count { throw BinaryFile.error(errno, action: "Schreiben fehlgeschlagen") }
        position += Int64(count)
        if position > length { length = position }
    }

    func write(_ bytes: [UInt8], count: Int? = nil) throws {
        let n = min(count ?? bytes.count, bytes.count)
        try bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            try write(base, count: n)
        }
    }

    func seek(to offset: Int64) throws {
        guard let fp = handle else { throw StudioError.encodeFailed("Datei bereits geschlossen.") }
        if fseeko(fp, off_t(offset), SEEK_SET) != 0 { throw BinaryFile.error(errno, action: "Springen in der Datei fehlgeschlagen") }
        position = offset
    }

    func seekToEnd() throws { try seek(to: length) }

    /// Schreibt alle Puffer und schließt die Datei.
    func close() throws {
        guard let fp = handle else { return }
        handle = nil
        let flushed = fflush(fp)
        let flushErr = errno
        let closed = fclose(fp)
        if flushed != 0 { throw BinaryFile.error(flushErr, action: "Schreiben fehlgeschlagen") }
        if closed != 0 { throw BinaryFile.error(errno, action: "Schließen fehlgeschlagen") }
    }

    /// Schließt ohne Fehlerprüfung (Abbruch).
    func abandon() {
        if let fp = handle { fclose(fp) }
        handle = nil
    }

    static func error(_ code: Int32, action: String) -> StudioError {
        if code == ENOSPC || code == EDQUOT { return .diskFull }
        let text = String(cString: strerror(code))
        return .encodeFailed("\(action): \(text)")
    }
}

/// Kleine Hilfen für Binärformate.
enum ByteWriter {
    static func le16(_ v: Int) -> [UInt8] { [UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8)] }
    static func le32(_ v: Int) -> [UInt8] {
        [UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8), UInt8(truncatingIfNeeded: v >> 16), UInt8(truncatingIfNeeded: v >> 24)]
    }
    static func be16(_ v: Int) -> [UInt8] { [UInt8(truncatingIfNeeded: v >> 8), UInt8(truncatingIfNeeded: v)] }
    static func be32(_ v: Int) -> [UInt8] {
        [UInt8(truncatingIfNeeded: v >> 24), UInt8(truncatingIfNeeded: v >> 16), UInt8(truncatingIfNeeded: v >> 8), UInt8(truncatingIfNeeded: v)]
    }
    static func ascii(_ s: String) -> [UInt8] { Array(s.utf8) }

    /// 80-Bit-Gleitkommazahl (IEEE 754 extended, Big Endian) für die Abtastrate in AIFF.
    static func extended80(_ value: Double) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 10)
        guard value > 0, value.isFinite else { return out }
        let e = Int(floor(log2(value)))
        let exponent = 16383 + e
        let mantissa = UInt64(value * pow(2.0, Double(63 - e)))
        out[0] = UInt8((exponent >> 8) & 0x7F)
        out[1] = UInt8(exponent & 0xFF)
        for i in 0..<8 { out[2 + i] = UInt8(truncatingIfNeeded: mantissa >> UInt64(56 - 8 * i)) }
        return out
    }
}
