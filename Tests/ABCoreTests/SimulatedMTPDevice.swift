import Foundation
@testable import ABCore

/// Simuliertes MTP-Gerät für Unit-Tests (nur Tests – die App selbst verwendet nie simulierte Daten).
/// Bildet die USB-Bulk-Semantik nach: Lesen endet bei vollem Puffer oder kurzem Paket; Nullpakete;
/// optional Geräte ohne Nullpaket (Antwort läuft dann in denselben Lesepuffer).
final class SimulatedMTPDevice: MTPBulkTransport {
    struct Object {
        var storage: UInt32
        var parent: UInt32
        var name: String
        var isFolder: Bool
        var data: Data
        var modified: String = "20240102T030405"
    }

    struct OutTransfer {
        var data: Data
        var isZLP: Bool { data.isEmpty }
    }

    let maxPacketSize: Int
    let bufferSize: Int
    var sendsZeroLengthPackets = true
    var forceUnknownLengthForGetObject = false
    /// Containerkopf als eigener kurzer Transfer (ältere Android-Versionen bei Datenphasen > 4 GB).
    var sendHeaderSeparately = false
    var supportsPropList = true
    /// Manche Geräte löschen nur leere Ordner.
    var refuseNonEmptyFolderDelete = false
    /// Geschützte Objekte (Löschen wird verweigert).
    var protectedHandles = Set<UInt32>()
    private(set) var deleteRequests = 0
    var storages: [UInt32: (desc: String, removable: Bool)] = [0x0001_0001: ("Interner gemeinsamer Speicher", false),
                                                                0x0002_0001: ("SD-Karte", true)]
    var objects: [UInt32: Object] = [:]
    var nextHandle: UInt32 = 100
    var sessionOpen = false
    var cancelRequests: [UInt32] = []
    private(set) var receivedWrites: [Int] = []

    private var outbound: [OutTransfer] = []
    private var inbound = Data()
    private var pendingCommand: (code: UInt16, tid: UInt32, params: [UInt32])?
    private var pendingSendObjectHandle: UInt32?

    init(maxPacketSize: Int = 512, bufferSize: Int = 4096) {
        self.maxPacketSize = maxPacketSize
        self.bufferSize = bufferSize
    }

    // MARK: - Transport

    func read(maxLength: Int, timeout: TimeInterval) throws -> Data {
        var out = Data()
        while out.count < maxLength, !outbound.isEmpty {
            if outbound[0].isZLP {
                if out.isEmpty { outbound.removeFirst(); return out }
                return out
            }
            var t = outbound[0]
            let take = min(maxLength - out.count, t.data.count)
            out.append(t.data.prefix(take))
            t.data = Data(t.data.dropFirst(take))
            if t.data.isEmpty {
                outbound.removeFirst()
                let total = out.count
                _ = total
                // Ende des Transfers: kurzes Paket?
                if take % maxPacketSize != 0 { return out }
                // Länge war Vielfaches der Paketgröße
                if sendsZeroLengthPackets {
                    if out.count < maxLength { return out }
                    outbound.insert(OutTransfer(data: Data()), at: 0)
                    return out
                }
                continue // ohne Nullpaket läuft der nächste Transfer in denselben Puffer
            } else {
                outbound[0] = t
            }
        }
        if out.isEmpty { throw MTPError.timeout }
        return out
    }

    func write(_ data: Data, timeout: TimeInterval) throws {
        receivedWrites.append(data.count)
        inbound.append(data)
        try processInbound(lastWriteSize: data.count)
    }

    func cancelTransaction(_ transactionID: UInt32) throws {
        cancelRequests.append(transactionID)
        outbound.removeAll()
        inbound.removeAll()
        pendingCommand = nil
    }

    func clearStalls() {}

    // MARK: - Geräteseite

    private func queueContainer(type: PTPContainerType, code: UInt16, tid: UInt32, payload: Data, unknownLength: Bool = false) {
        var header = PTPContainerHeader(length: UInt32(12 + payload.count), type: type.rawValue, code: code, transactionID: tid)
        if unknownLength { header.length = 0xFFFF_FFFF }
        if sendHeaderSeparately && type == .data {
            outbound.append(OutTransfer(data: Data(header.encoded())))
            if !payload.isEmpty { outbound.append(OutTransfer(data: payload)) }
            return
        }
        var d = Data(header.encoded())
        d.append(payload)
        outbound.append(OutTransfer(data: d))
    }

    /// Späte Antwort einer früheren Transaktion in den Kanal legen (Daten + Antwort).
    func injectStaleReply(tid: UInt32 = 999) {
        queueContainer(type: .data, code: 0x9805, tid: tid, payload: Data(repeating: 0xAB, count: 700))
        respond(.ok, tid: tid)
    }

    /// Restdaten einer abgebrochenen Übertragung (z. B. App während eines Downloads beendet).
    func injectLeftoverBytes(_ count: Int) {
        outbound.append(OutTransfer(data: Data(repeating: 0x55, count: count)))
    }

    private func respond(_ code: PTPResponse, tid: UInt32, params: [UInt32] = []) {
        var w = PTPWriter()
        for p in params { w.u32(p) }
        queueContainer(type: .response, code: code.rawValue, tid: tid, payload: w.data)
    }

    private func sendData(_ payload: Data, op: UInt16, tid: UInt32, unknownLength: Bool = false) {
        queueContainer(type: .data, code: op, tid: tid, payload: payload, unknownLength: unknownLength)
    }

    private func processInbound(lastWriteSize: Int) throws {
        while inbound.count >= 12 {
            let header = try PTPContainerHeader.parse([UInt8](inbound.prefix(12)))
            if header.type == PTPContainerType.command.rawValue {
                guard inbound.count >= Int(header.length) else { return }
                var r = PTPReader(bytes: [UInt8](inbound.prefix(Int(header.length))), offset: 12)
                var params: [UInt32] = []
                while r.remaining >= 4 { params.append(try r.u32()) }
                inbound = Data(inbound.dropFirst(Int(header.length)))
                handleCommand(code: header.code, tid: header.transactionID, params: params)
            } else if header.type == PTPContainerType.data.rawValue {
                let complete: Bool
                if header.hasUnknownLength {
                    complete = lastWriteSize % maxPacketSize != 0 || lastWriteSize == 0
                } else {
                    complete = inbound.count >= Int(header.length)
                }
                guard complete else { return }
                let len = header.hasUnknownLength ? inbound.count : Int(header.length)
                let payload = Data(inbound.subdata(in: 12..<len))
                inbound = Data(inbound.dropFirst(len))
                handleData(payload)
            } else {
                inbound.removeAll()
            }
        }
    }

    private func handleCommand(code: UInt16, tid: UInt32, params: [UInt32]) {
        guard let op = PTPOperation(rawValue: code) else {
            respond(.operationNotSupported, tid: tid)
            return
        }
        switch op {
        case .getDeviceInfo:
            var w = PTPWriter()
            w.u16(100); w.u32(6); w.u16(100); w.string("microsoft.com: 1.0; android.com: 1.0;"); w.u16(0)
            var ops: [UInt16] = [0x1001, 0x1002, 0x1003, 0x1004, 0x1005, 0x1007, 0x1008, 0x1009, 0x100A, 0x100B, 0x100C, 0x100D, 0x9803, 0x9804, 0x95C1]
            if supportsPropList { ops.append(0x9805) }
            w.u32(UInt32(ops.count)); ops.forEach { w.u16($0) }
            w.u32(0); w.u32(0); w.u32(0); w.u32(0)
            w.string("Google"); w.string("Pixel 6 Pro"); w.string("1.0"); w.string("SIM123")
            sendData(w.data, op: code, tid: tid)
            respond(.ok, tid: tid)
        case .openSession:
            if sessionOpen { respond(.sessionAlreadyOpen, tid: tid); return }
            sessionOpen = true
            respond(.ok, tid: tid)
        case .closeSession:
            sessionOpen = false
            respond(.ok, tid: tid)
        case .getStorageIDs:
            var w = PTPWriter()
            let ids = storages.keys.sorted()
            w.u32(UInt32(ids.count)); ids.forEach { w.u32($0) }
            sendData(w.data, op: code, tid: tid)
            respond(.ok, tid: tid)
        case .getStorageInfo:
            guard let s = storages[params.first ?? 0] else { respond(.invalidStorageID, tid: tid); return }
            var w = PTPWriter()
            w.u16(s.removable ? 4 : 3); w.u16(2); w.u16(0)
            w.u64(128_000_000_000); w.u64(64_000_000_000); w.u32(0xFFFF_FFFF)
            w.string(s.desc); w.string("")
            sendData(w.data, op: code, tid: tid)
            respond(.ok, tid: tid)
        case .getObjectHandles:
            let storage = params[0], parent = params[2]
            let p = parent == 0xFFFF_FFFF ? 0 : parent
            let handles = objects.filter { $0.value.storage == storage && $0.value.parent == p }.keys.sorted()
            var w = PTPWriter()
            w.u32(UInt32(handles.count)); handles.forEach { w.u32($0) }
            sendData(w.data, op: code, tid: tid)
            respond(.ok, tid: tid)
        case .getObjectInfo:
            guard let o = objects[params[0]] else { respond(.invalidObjectHandle, tid: tid); return }
            let info = MTPObjectInfo(storageID: o.storage, objectFormat: o.isFolder ? MTPFormat.association : MTPFormat.forFileName(o.name),
                                     compressedSize: UInt32(o.data.count), parentObject: o.parent,
                                     associationType: o.isFolder ? 1 : 0, filename: o.name, modificationDate: o.modified)
            sendData(info.encoded(), op: code, tid: tid)
            respond(.ok, tid: tid)
        case .getObject:
            guard let o = objects[params[0]] else { respond(.invalidObjectHandle, tid: tid); return }
            sendData(o.data, op: code, tid: tid, unknownLength: forceUnknownLengthForGetObject)
            respond(.ok, tid: tid)
        case .getPartialObject64:
            guard let o = objects[params[0]] else { respond(.invalidObjectHandle, tid: tid); return }
            let offset = Int(UInt64(params[1]) | UInt64(params[2]) << 32)
            let end = min(o.data.count, offset + Int(params[3]))
            let slice = offset < end ? o.data.subdata(in: offset..<end) : Data()
            sendData(slice, op: code, tid: tid)
            respond(.ok, tid: tid, params: [UInt32(slice.count)])
        case .getObjectPropValue:
            guard let o = objects[params[0]] else { respond(.invalidObjectHandle, tid: tid); return }
            var w = PTPWriter()
            w.u64(UInt64(o.data.count))
            sendData(w.data, op: code, tid: tid)
            respond(.ok, tid: tid)
        case .getObjectPropList:
            let parent = params[0]
            let children = objects.filter { $0.value.parent == parent }.sorted { $0.key < $1.key }
            var w = PTPWriter()
            w.u32(UInt32(children.count * 5))
            for (h, o) in children {
                w.u32(h); w.u16(MTPProperty.storageID); w.u16(PTPDataType.uint32); w.u32(o.storage)
                w.u32(h); w.u16(MTPProperty.objectFormat); w.u16(PTPDataType.uint16); w.u16(o.isFolder ? MTPFormat.association : MTPFormat.forFileName(o.name))
                w.u32(h); w.u16(MTPProperty.objectSize); w.u16(PTPDataType.uint64); w.u64(UInt64(o.data.count))
                w.u32(h); w.u16(MTPProperty.objectFileName); w.u16(PTPDataType.string); w.string(o.name)
                w.u32(h); w.u16(MTPProperty.dateModified); w.u16(PTPDataType.string); w.string(o.modified)
            }
            sendData(w.data, op: code, tid: tid)
            respond(.ok, tid: tid)
        case .deleteObject:
            deleteRequests += 1
            let h = params[0]
            guard let obj = objects[h] else { respond(.invalidObjectHandle, tid: tid); return }
            if protectedHandles.contains(h) { respond(.accessDenied, tid: tid); return }
            if obj.isFolder {
                let hasChildren = objects.values.contains { $0.parent == h }
                if hasChildren && refuseNonEmptyFolderDelete { respond(.partialDeletion, tid: tid); return }
                // Android: Ordner samt Inhalt löschen (geschützte Inhalte bleiben, dann Teil-Löschung)
                var blocked = false
                func remove(_ parent: UInt32) {
                    for (ch, o) in objects where o.parent == parent {
                        if protectedHandles.contains(ch) { blocked = true; continue }
                        if o.isFolder { remove(ch) }
                        if !objects.values.contains(where: { $0.parent == ch }) { objects[ch] = nil }
                    }
                }
                remove(h)
                if blocked { respond(.partialDeletion, tid: tid); return }
            }
            objects[h] = nil
            respond(.ok, tid: tid)
        case .sendObjectInfo, .sendObject, .setObjectPropValue:
            pendingCommand = (code, tid, params)
        default:
            respond(.operationNotSupported, tid: tid)
        }
    }

    private func handleData(_ payload: Data) {
        guard let cmd = pendingCommand else { return }
        pendingCommand = nil
        switch PTPOperation(rawValue: cmd.code) {
        case .sendObjectInfo:
            guard let info = try? MTPObjectInfo.parse(payload) else { respond(.invalidDataset, tid: cmd.tid); return }
            let storage = cmd.params[0]
            let parent = cmd.params[1] == 0xFFFF_FFFF ? 0 : cmd.params[1]
            let h = nextHandle
            nextHandle += 1
            objects[h] = Object(storage: storage, parent: parent, name: info.filename, isFolder: info.isFolder, data: Data())
            pendingSendObjectHandle = info.isFolder ? nil : h
            respond(.ok, tid: cmd.tid, params: [storage, parent, h])
        case .sendObject:
            guard let h = pendingSendObjectHandle else { respond(.noValidObjectInfo, tid: cmd.tid); return }
            objects[h]?.data = payload
            pendingSendObjectHandle = nil
            respond(.ok, tid: cmd.tid)
        case .setObjectPropValue:
            var r = PTPReader(payload)
            if let name = try? r.string() { objects[cmd.params[0]]?.name = name }
            respond(.ok, tid: cmd.tid)
        default:
            respond(.generalError, tid: cmd.tid)
        }
    }
}
