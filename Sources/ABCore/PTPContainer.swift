import Foundation

/// Kopf eines PTP-USB-Containers (12 Bytes): Länge, Typ, Code, Transaktionsnummer.
public struct PTPContainerHeader: Equatable, Sendable {
    public static let size = 12
    /// Länge 0xFFFFFFFF: Datenphase größer als 4 GB – Ende wird durch ein kurzes USB-Paket angezeigt.
    public static let unknownLength: UInt32 = 0xFFFF_FFFF

    public var length: UInt32
    public var type: UInt16
    public var code: UInt16
    public var transactionID: UInt32

    public init(length: UInt32, type: UInt16, code: UInt16, transactionID: UInt32) {
        self.length = length
        self.type = type
        self.code = code
        self.transactionID = transactionID
    }

    public var containerType: PTPContainerType? { PTPContainerType(rawValue: type) }
    public var hasUnknownLength: Bool { length == Self.unknownLength }
    /// Nutzdatenlänge, falls bekannt.
    public var payloadLength: UInt64? {
        hasUnknownLength ? nil : UInt64(length) - UInt64(min(length, UInt32(Self.size)))
    }

    public static func parse(_ bytes: [UInt8], at offset: Int = 0) throws -> PTPContainerHeader {
        var r = PTPReader(bytes: bytes, offset: offset)
        let length = try r.u32()
        let type = try r.u16()
        let code = try r.u16()
        let tid = try r.u32()
        guard type >= 1 && type <= 4 else { throw PTPDecodingError.invalidHeader("Typ \(type)") }
        guard length >= UInt32(size) else { throw PTPDecodingError.invalidHeader("Länge \(length)") }
        return PTPContainerHeader(length: length, type: type, code: code, transactionID: tid)
    }

    public func encoded() -> [UInt8] {
        var w = PTPWriter()
        w.u32(length)
        w.u16(type)
        w.u16(code)
        w.u32(transactionID)
        return w.bytes
    }
}

public enum PTPContainers {
    /// Befehlscontainer (bis zu 5 Parameter).
    public static func command(_ op: UInt16, transactionID: UInt32, params: [UInt32]) -> [UInt8] {
        precondition(params.count <= 5)
        let header = PTPContainerHeader(length: UInt32(PTPContainerHeader.size + 4 * params.count),
                                        type: PTPContainerType.command.rawValue, code: op, transactionID: transactionID)
        var w = PTPWriter()
        w.append(header.encoded())
        for p in params { w.u32(p) }
        return w.bytes
    }

    /// Kopf eines Datencontainers. Nutzdaten über 4 GB − 12 erhalten die Länge 0xFFFFFFFF.
    public static func dataHeader(_ op: UInt16, transactionID: UInt32, payloadLength: UInt64) -> [UInt8] {
        let total = payloadLength + UInt64(PTPContainerHeader.size)
        let length: UInt32 = total >= UInt64(PTPContainerHeader.unknownLength) ? PTPContainerHeader.unknownLength : UInt32(total)
        return PTPContainerHeader(length: length, type: PTPContainerType.data.rawValue, code: op, transactionID: transactionID).encoded()
    }

    /// Antwortcontainer: Code + Parameter.
    public static func parseResponse(_ bytes: [UInt8]) throws -> (header: PTPContainerHeader, params: [UInt32]) {
        let header = try PTPContainerHeader.parse(bytes)
        var r = PTPReader(bytes: bytes, offset: PTPContainerHeader.size)
        var params: [UInt32] = []
        let end = min(Int(header.length), bytes.count)
        while r.offset + 4 <= end && params.count < 5 { params.append(try r.u32()) }
        return (header, params)
    }

    /// Muss nach einer Datenphase mit `total` Bytes ein Nullpaket gesendet werden?
    /// (Ein Bulk-Transfer endet nur bei einem kurzen Paket; ist die Länge ein Vielfaches der Paketgröße,
    /// signalisiert ein Paket der Länge 0 das Ende.)
    public static func needsZeroLengthPacket(totalBytes: UInt64, maxPacketSize: Int) -> Bool {
        guard maxPacketSize > 0 else { return false }
        return totalBytes > 0 && totalBytes % UInt64(maxPacketSize) == 0
    }

    /// Lesegröße für eine Datenphase: nie mehr als die erwarteten Restbytes (auf Paketgröße aufgerundet),
    /// damit die anschließende Antwort nicht in denselben Puffer läuft.
    public static func readRequestSize(remaining: UInt64?, bufferSize: Int, maxPacketSize: Int) -> Int {
        let mps = max(1, maxPacketSize)
        guard let remaining else { return bufferSize }
        let rounded = ((remaining + UInt64(mps) - 1) / UInt64(mps)) * UInt64(mps)
        return Int(min(UInt64(bufferSize), max(UInt64(mps), rounded)))
    }
}
