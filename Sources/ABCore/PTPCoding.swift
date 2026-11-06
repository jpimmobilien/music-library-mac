import Foundation

public enum PTPDecodingError: Error, Equatable, CustomStringConvertible {
    case truncated(needed: Int, available: Int)
    case invalidString
    case invalidHeader(String)

    public var description: String {
        switch self {
        case let .truncated(n, a): return "PTP-Daten zu kurz (benötigt \(n), vorhanden \(a))"
        case .invalidString: return "Ungültige PTP-Zeichenkette"
        case let .invalidHeader(s): return "Ungültiger PTP-Container: \(s)"
        }
    }
}

/// Liest Little-Endian-Werte und PTP-Zeichenketten aus einem Byte-Puffer.
public struct PTPReader {
    public let bytes: [UInt8]
    public private(set) var offset: Int

    public init(_ data: Data, offset: Int = 0) {
        self.bytes = [UInt8](data)
        self.offset = offset
    }

    public init(bytes: [UInt8], offset: Int = 0) {
        self.bytes = bytes
        self.offset = offset
    }

    public var remaining: Int { bytes.count - offset }
    public var isAtEnd: Bool { offset >= bytes.count }

    private mutating func need(_ n: Int) throws {
        if remaining < n { throw PTPDecodingError.truncated(needed: n, available: remaining) }
    }

    public mutating func u8() throws -> UInt8 {
        try need(1)
        defer { offset += 1 }
        return bytes[offset]
    }

    public mutating func u16() throws -> UInt16 {
        try need(2)
        defer { offset += 2 }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    public mutating func u32() throws -> UInt32 {
        try need(4)
        var v: UInt32 = 0
        for i in 0..<4 { v |= UInt32(bytes[offset + i]) << (8 * UInt32(i)) }
        offset += 4
        return v
    }

    public mutating func u64() throws -> UInt64 {
        try need(8)
        var v: UInt64 = 0
        for i in 0..<8 { v |= UInt64(bytes[offset + i]) << (8 * UInt64(i)) }
        offset += 8
        return v
    }

    public mutating func skip(_ n: Int) throws {
        try need(n)
        offset += n
    }

    /// PTP-Zeichenkette: 1 Byte Zeichenanzahl (inkl. Nullzeichen), danach UTF-16LE.
    public mutating func string() throws -> String {
        let count = Int(try u8())
        if count == 0 { return "" }
        try need(count * 2)
        var units: [UInt16] = []
        units.reserveCapacity(count)
        for _ in 0..<count { units.append(try u16()) }
        while let last = units.last, last == 0 { units.removeLast() }
        return String(decoding: units, as: UTF16.self)
    }

    public mutating func u16Array() throws -> [UInt16] {
        let n = Int(try u32())
        try need(n * 2)
        var out: [UInt16] = []
        out.reserveCapacity(n)
        for _ in 0..<n { out.append(try u16()) }
        return out
    }

    public mutating func u32Array() throws -> [UInt32] {
        let n = Int(try u32())
        try need(n * 4)
        var out: [UInt32] = []
        out.reserveCapacity(n)
        for _ in 0..<n { out.append(try u32()) }
        return out
    }

    /// Überspringt bzw. liest einen Wert eines PTP-Datentyps (für Eigenschaftslisten).
    public mutating func value(ofType type: UInt16) throws -> PTPValue {
        switch type {
        case PTPDataType.int8, PTPDataType.uint8: return .integer(UInt64(try u8()))
        case PTPDataType.int16, PTPDataType.uint16: return .integer(UInt64(try u16()))
        case PTPDataType.int32, PTPDataType.uint32: return .integer(UInt64(try u32()))
        case PTPDataType.int64, PTPDataType.uint64: return .integer(try u64())
        case PTPDataType.int128, PTPDataType.uint128:
            let low = try u64()
            _ = try u64()
            return .integer(low)
        case PTPDataType.string: return .string(try string())
        default:
            if type & PTPDataType.arrayFlag != 0 {
                let element = type & ~PTPDataType.arrayFlag
                let n = Int(try u32())
                var size: Int
                switch element {
                case PTPDataType.int8, PTPDataType.uint8: size = 1
                case PTPDataType.int16, PTPDataType.uint16: size = 2
                case PTPDataType.int32, PTPDataType.uint32: size = 4
                case PTPDataType.int64, PTPDataType.uint64: size = 8
                case PTPDataType.int128, PTPDataType.uint128: size = 16
                default: throw PTPDecodingError.invalidHeader("Unbekannter Array-Typ \(element)")
                }
                try skip(n * size)
                return .unsupported
            }
            throw PTPDecodingError.invalidHeader("Unbekannter Datentyp \(type)")
        }
    }
}

public enum PTPValue: Equatable, Sendable {
    case integer(UInt64)
    case string(String)
    case unsupported

    public var integer: UInt64? { if case let .integer(v) = self { return v } else { return nil } }
    public var string: String? { if case let .string(s) = self { return s } else { return nil } }
}

/// Schreibt Little-Endian-Werte und PTP-Zeichenketten.
public struct PTPWriter {
    public private(set) var bytes: [UInt8] = []

    public init() {}

    public var data: Data { Data(bytes) }

    public mutating func u8(_ v: UInt8) { bytes.append(v) }

    public mutating func u16(_ v: UInt16) {
        bytes.append(UInt8(v & 0xFF))
        bytes.append(UInt8(v >> 8))
    }

    public mutating func u32(_ v: UInt32) {
        for i in 0..<4 { bytes.append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) }
    }

    public mutating func u64(_ v: UInt64) {
        for i in 0..<8 { bytes.append(UInt8((v >> (8 * UInt64(i))) & 0xFF)) }
    }

    /// PTP-Zeichenkette (max. 254 Zeichen + Nullzeichen; längere Namen werden gekürzt).
    public mutating func string(_ s: String) {
        if s.isEmpty {
            u8(0)
            return
        }
        var units = Array(s.utf16)
        if units.count > 254 {
            units = Array(units.prefix(254))
            // kein halbes Ersatzzeichenpaar am Ende
            if let last = units.last, UTF16.isLeadSurrogate(last) { units.removeLast() }
        }
        u8(UInt8(units.count + 1))
        for unit in units { u16(unit) }
        u16(0)
    }

    public mutating func append(_ other: [UInt8]) { bytes.append(contentsOf: other) }
}
