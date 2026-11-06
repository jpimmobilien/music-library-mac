import Foundation

/// Zugriff auf die Bulk-Endpunkte einer MTP-Schnittstelle. Die macOS-App setzt das mit IOUSBHost um,
/// die Tests mit einem simulierten Gerät.
public protocol MTPBulkTransport: AnyObject {
    /// Maximale Paketgröße des Bulk-Endpunkts (512 bei USB 2.0, 1024 bei USB 3.x).
    var maxPacketSize: Int { get }
    /// Größe einer einzelnen USB-Anforderung (Vielfaches von maxPacketSize).
    var bufferSize: Int { get }
    /// Liest bis zu `maxLength` Bytes. Weniger Bytes bedeuten: kurzes Paket – Ende des USB-Transfers.
    func read(maxLength: Int, timeout: TimeInterval) throws -> Data
    /// Schreibt die Bytes als einen USB-Transfer (leere Daten = Nullpaket).
    func write(_ data: Data, timeout: TimeInterval) throws
    /// Sendet die Klassenanforderung „Cancel Request“ (0x64) für eine Transaktion.
    func cancelTransaction(_ transactionID: UInt32) throws
    /// Hebt einen Endpunkt-Stillstand auf (nach Fehlern).
    func clearStalls()
}

public enum MTPError: Error, Equatable, CustomStringConvertible {
    case response(UInt16)
    case transport(String)
    case timeout
    case cancelled
    case disconnected
    case accessDenied
    case busy
    case protocolError(String)
    case notSupported(String)
    case incomplete(expected: UInt64, received: UInt64)

    public var responseCode: UInt16? { if case let .response(c) = self { return c } else { return nil } }

    public var description: String {
        switch self {
        case let .response(code):
            if let r = PTPResponse(rawValue: code) { return "MTP-Antwort \(r) (0x\(String(code, radix: 16)))" }
            return "MTP-Antwort 0x\(String(code, radix: 16))"
        case let .transport(s): return "USB: \(s)"
        case .timeout: return "Zeitüberschreitung"
        case .cancelled: return "Abgebrochen"
        case .disconnected: return "Gerät getrennt"
        case .accessDenied: return "Zugriff verweigert"
        case .busy: return "Gerät belegt"
        case let .protocolError(s): return "Protokollfehler: \(s)"
        case let .notSupported(s): return "Nicht unterstützt: \(s)"
        case let .incomplete(e, r): return "Unvollständig (\(r) von \(e) Bytes)"
        }
    }
}

public struct MTPResponseResult: Equatable, Sendable {
    public var code: UInt16
    public var params: [UInt32]
    public var isOK: Bool { code == PTPResponse.ok.rawValue }
}

/// Ausgehende Datenphase: Gesamtlänge und Lieferant für die Bytes (liefert leere Daten am Ende).
public struct MTPOutgoingData {
    public var length: UInt64
    public var next: (Int) throws -> Data

    public init(length: UInt64, next: @escaping (Int) throws -> Data) {
        self.length = length
        self.next = next
    }

    public init(_ data: Data) {
        var offset = 0
        self.length = UInt64(data.count)
        self.next = { max in
            let end = min(data.count, offset + max)
            defer { offset = end }
            return data.subdata(in: offset..<end)
        }
    }
}

/// Fortschritt: bisher übertragene Bytes; Rückgabe `false` bricht ab.
public typealias MTPProgress = (UInt64) -> Bool

/// Eine MTP-Sitzung. Nicht threadsicher – der Aufrufer serialisiert alle Zugriffe (eine Warteschlange je Gerät),
/// denn MTP erlaubt nur eine Transaktion zur selben Zeit.
public final class MTPSession {
    public let transport: MTPBulkTransport
    public private(set) var isOpen = false
    public private(set) var deviceInfo: MTPDeviceInfo?
    public var commandTimeout: TimeInterval = 5
    public var dataTimeout: TimeInterval = 30
    public var responseTimeout: TimeInterval = 60

    private var transactionID: UInt32 = 0
    private var pending = Data()
    private var lastReadWasShort = false
    /// Der Lesevorgang, der den letzten Containerkopf brachte, enthielt auch Nutzdaten.
    private var headerReadHadPayload = false
    /// Datenphase vollständig empfangen bzw. gesendet (auch wenn danach ein Fehler auftrat).
    private var lastReceiveCompleted = false
    private var lastSendCompleted = false

    public init(transport: MTPBulkTransport) {
        self.transport = transport
    }

    // MARK: - Transaktionen

    private func nextTransactionID() -> UInt32 {
        transactionID &+= 1
        if transactionID == 0 || transactionID == 0xFFFF_FFFF { transactionID = 1 }
        return transactionID
    }

    /// Führt eine vollständige Transaktion aus: Befehl → (Daten) → Antwort.
    @discardableResult
    public func transaction(_ op: UInt16, params: [UInt32] = [], outgoing: MTPOutgoingData? = nil,
                            incoming: ((Data) throws -> Void)? = nil, progress: MTPProgress? = nil,
                            transactionIDOverride: UInt32? = nil, dataTimeoutOverride: TimeInterval? = nil) throws -> MTPResponseResult {
        let tid = transactionIDOverride ?? nextTransactionID()
        let dataWait = dataTimeoutOverride ?? dataTimeout
        try transport.write(Data(PTPContainers.command(op, transactionID: tid, params: params)), timeout: commandTimeout)
        if let outgoing {
            do {
                try sendData(op: op, tid: tid, outgoing, progress: progress)
            } catch MTPError.disconnected {
                throw MTPError.disconnected
            } catch {
                // Lesefehler der Quelldatei, Zeitüberschreitung, Abbruch: Das Gerät wartet sonst weiter auf Daten
                // und hielte die nächsten Befehle für Dateiinhalt.
                if !lastSendCompleted { abort(tid: tid) }
                throw error
            }
        }
        var received: UInt64 = 0
        var staleContainers = 0
        while true {
            let header: PTPContainerHeader
            do {
                header = try readHeader(timeout: incoming != nil ? dataWait : responseTimeout)
            } catch MTPError.timeout {
                // Gerät hat nicht rechtzeitig geantwortet – Transaktion abbrechen, damit eine späte Antwort
                // nicht in die nächste Anfrage läuft.
                abort(tid: tid)
                throw MTPError.timeout
            }
            if header.transactionID != tid {
                // Rest einer früheren (abgebrochenen bzw. zu spät beantworteten) Transaktion – verwerfen.
                staleContainers += 1
                if staleContainers > 16 { throw MTPError.protocolError("Zu viele veraltete Antworten") }
                try receivePayload(header, timeout: dataWait) { _ in }
                continue
            }
            switch header.containerType {
            case .data:
                lastReceiveCompleted = false
                do {
                    try receivePayload(header, timeout: dataWait) { chunk in
                        received += UInt64(chunk.count)
                        try incoming?(chunk)
                        if let progress, !progress(received) { throw MTPError.cancelled }
                    }
                } catch MTPError.disconnected {
                    throw MTPError.disconnected
                } catch {
                    if lastReceiveCompleted {
                        // Alle Daten waren schon da (Fehler beim letzten Stück): nicht abbrechen – ein später
                        // Abbruchwunsch würde sonst die nächste Übertragung treffen. Antwort normal lesen.
                        _ = try? readResponse(tid: tid)
                    } else {
                        // Abbruch durch den Benutzer oder Fehler beim Schreiben am Ziel: Gerät sendet noch.
                        abort(tid: tid)
                    }
                    throw error
                }
            case .response:
                var payload = Data()
                try receivePayload(header, timeout: responseTimeout) { payload.append($0) }
                var r = PTPReader(payload)
                var ps: [UInt32] = []
                while r.remaining >= 4 && ps.count < 5 { ps.append(try r.u32()) }
                return MTPResponseResult(code: header.code, params: ps)
            case .event, .command, .none:
                // Unerwartet auf dem Bulk-Kanal: Nutzdaten verwerfen und weiterlesen.
                try receivePayload(header, timeout: dataWait) { _ in }
            }
        }
    }

    /// Liest die Antwort einer Transaktion (Datencontainer werden verworfen).
    private func readResponse(tid: UInt32) throws -> MTPResponseResult {
        for _ in 0..<8 {
            let header = try readHeader(timeout: responseTimeout)
            var payload = Data()
            try receivePayload(header, timeout: responseTimeout) { payload.append($0) }
            if header.containerType == .response && header.transactionID == tid {
                var r = PTPReader(payload)
                var ps: [UInt32] = []
                while r.remaining >= 4 && ps.count < 5 { ps.append(try r.u32()) }
                return MTPResponseResult(code: header.code, params: ps)
            }
        }
        throw MTPError.protocolError("Keine Antwort")
    }

    /// Wie `transaction`, wirft aber bei jeder Antwort außer OK.
    @discardableResult
    public func checked(_ op: PTPOperation, params: [UInt32] = [], outgoing: MTPOutgoingData? = nil,
                        incoming: ((Data) throws -> Void)? = nil, progress: MTPProgress? = nil) throws -> MTPResponseResult {
        let r = try transaction(op.rawValue, params: params, outgoing: outgoing, incoming: incoming, progress: progress)
        guard r.isOK else { throw MTPError.response(r.code) }
        return r
    }

    /// Transaktion mit eingehenden Daten, gesammelt in einem Puffer (nur für kleine Datensätze).
    public func fetch(_ op: PTPOperation, params: [UInt32] = [], timeout: TimeInterval? = nil) throws -> Data {
        var data = Data()
        let r = try transaction(op.rawValue, params: params, incoming: { data.append($0) }, dataTimeoutOverride: timeout)
        guard r.isOK else { throw MTPError.response(r.code) }
        return data
    }

    // MARK: - Lesen

    private func fill(atLeast count: Int, timeout: TimeInterval) throws {
        var emptyReads = 0
        while pending.count < count {
            let chunk = try transport.read(maxLength: transport.bufferSize, timeout: timeout)
            lastReadWasShort = chunk.count < transport.bufferSize
            if chunk.isEmpty {
                // Nullpaket (Ende einer vorherigen Datenphase) – ignorieren.
                emptyReads += 1
                if emptyReads > 4 { throw MTPError.protocolError("Keine Daten vom Gerät") }
                continue
            }
            pending.append(chunk)
        }
    }

    private func readHeader(timeout: TimeInterval) throws -> PTPContainerHeader {
        try fill(atLeast: PTPContainerHeader.size, timeout: timeout)
        let header: PTPContainerHeader
        do {
            header = try PTPContainerHeader.parse([UInt8](pending.prefix(PTPContainerHeader.size)))
        } catch {
            pending.removeAll()
            throw MTPError.protocolError("\(error)")
        }
        pending.removeFirst(PTPContainerHeader.size)
        pending = Data(pending) // Startindex auf 0 setzen
        headerReadHadPayload = !pending.isEmpty
        return header
    }

    private func receivePayload(_ header: PTPContainerHeader, timeout: TimeInterval, sink: (Data) throws -> Void) throws {
        if let total = header.payloadLength {
            var remaining = total
            if remaining == 0 { lastReceiveCompleted = true }
            if !pending.isEmpty {
                let take = Int(min(UInt64(pending.count), remaining))
                if take > 0 {
                    let part = pending.prefix(take)
                    pending = Data(pending.dropFirst(take))
                    remaining -= UInt64(take)
                    if remaining == 0 { lastReceiveCompleted = true }
                    try sink(Data(part))
                }
            }
            while remaining > 0 {
                let size = PTPContainers.readRequestSize(remaining: remaining, bufferSize: transport.bufferSize,
                                                          maxPacketSize: transport.maxPacketSize)
                let chunk = try transport.read(maxLength: size, timeout: timeout)
                lastReadWasShort = chunk.count < size
                if chunk.isEmpty {
                    throw MTPError.incomplete(expected: total, received: total - remaining)
                }
                let take = Int(min(UInt64(chunk.count), remaining))
                remaining -= UInt64(take)
                if take < chunk.count { pending.append(chunk.subdata(in: take..<chunk.count)) }
                if remaining == 0 { lastReceiveCompleted = true }
                try sink(take == chunk.count ? chunk : chunk.prefix(take))
                if remaining > 0 && chunk.count < size {
                    throw MTPError.incomplete(expected: total, received: total - remaining)
                }
            }
        } else {
            // Länge unbekannt (> 4 GB): bis zum kurzen Paket lesen. Kam der Kopf als eigener kurzer Transfer
            // (ohne Nutzdaten), folgen die Daten erst noch.
            var finished = lastReadWasShort && headerReadHadPayload
            if !pending.isEmpty {
                let part = pending
                pending = Data()
                if finished { lastReceiveCompleted = true }
                try sink(part)
            }
            while !finished {
                let size = transport.bufferSize
                let chunk = try transport.read(maxLength: size, timeout: timeout)
                finished = chunk.count < size || chunk.count % max(1, transport.maxPacketSize) != 0
                lastReadWasShort = finished
                if finished { lastReceiveCompleted = true }
                if !chunk.isEmpty { try sink(chunk) }
            }
        }
    }

    // MARK: - Senden

    private func sendData(op: UInt16, tid: UInt32, _ outgoing: MTPOutgoingData, progress: MTPProgress?) throws {
        let bufferSize = transport.bufferSize
        var buffer = Data(PTPContainers.dataHeader(op, transactionID: tid, payloadLength: outgoing.length))
        buffer.reserveCapacity(bufferSize)
        var sent: UInt64 = 0
        var totalWritten: UInt64 = 0
        lastSendCompleted = false
        while true {
            // Puffer exakt füllen (alle Transfers außer dem letzten müssen Vielfache der Paketgröße sein).
            while buffer.count < bufferSize && sent < outgoing.length {
                let want = Int(min(UInt64(bufferSize - buffer.count), outgoing.length - sent))
                let chunk = try outgoing.next(want)
                if chunk.isEmpty {
                    throw MTPError.incomplete(expected: outgoing.length, received: sent)
                }
                buffer.append(chunk)
                sent += UInt64(chunk.count)
            }
            let isLast = sent >= outgoing.length
            if buffer.count > 0 {
                try transport.write(buffer, timeout: dataTimeout)
                totalWritten += UInt64(buffer.count)
            }
            buffer.removeAll(keepingCapacity: true)
            // Nach dem letzten Stück wird nicht mehr abgebrochen (ein später Abbruchwunsch träfe sonst die nächste Übertragung).
            if !isLast, let progress, !progress(sent) {
                throw MTPError.cancelled
            }
            if isLast { _ = progress?(sent); break }
        }
        if PTPContainers.needsZeroLengthPacket(totalBytes: totalWritten, maxPacketSize: transport.maxPacketSize) {
            try transport.write(Data(), timeout: dataTimeout)
        }
        lastSendCompleted = true
    }

    /// Bricht die laufende Transaktion ab und bringt den Kanal in einen definierten Zustand.
    private func abort(tid: UInt32) {
        try? transport.cancelTransaction(tid)
        // Restdaten verwerfen, bis nichts mehr kommt.
        for _ in 0..<4096 {
            guard let chunk = try? transport.read(maxLength: transport.bufferSize, timeout: 0.5) else { break }
            if chunk.isEmpty { break }
        }
        pending = Data()
        lastReadWasShort = false
        headerReadHadPayload = false
        // Endpunkte werden nur bei tatsächlichem Stillstand zurückgesetzt (im Transport), nicht pauschal:
        // ein unnötiges CLEAR_FEATURE kann laufende Anforderungen auf dem Telefon abbrechen.
    }

    /// Verwirft Reste einer früheren, unterbrochenen Verbindung (z. B. App während eines Downloads beendet):
    /// Liegen noch Daten an, wird die alte Transaktion abgebrochen und der Kanal geleert.
    public func flushStaleData() {
        pending = Data()
        guard let first = try? transport.read(maxLength: transport.bufferSize, timeout: 0.25), !first.isEmpty else { return }
        try? transport.cancelTransaction(0)
        for _ in 0..<4096 {
            guard let chunk = try? transport.read(maxLength: transport.bufferSize, timeout: 0.5), !chunk.isEmpty else { break }
        }
        pending = Data()
        lastReadWasShort = false
    }

    // MARK: - Sitzung

    public func getDeviceInfo() throws -> MTPDeviceInfo {
        var data = Data()
        let r = try transaction(PTPOperation.getDeviceInfo.rawValue, incoming: { data.append($0) },
                                transactionIDOverride: isOpen ? nil : 0)
        guard r.isOK else { throw MTPError.response(r.code) }
        let info = try MTPDeviceInfo.parse(data)
        deviceInfo = info
        return info
    }

    public func openSession(id: UInt32 = 1) throws {
        transactionID = 0
        pending = Data()
        let r = try transaction(PTPOperation.openSession.rawValue, params: [id], transactionIDOverride: 0)
        if r.code == PTPResponse.sessionAlreadyOpen.rawValue {
            // Sitzung einer früheren Verbindung: schließen und neu öffnen.
            _ = try? transaction(PTPOperation.closeSession.rawValue)
            transactionID = 0
            let again = try transaction(PTPOperation.openSession.rawValue, params: [id], transactionIDOverride: 0)
            guard again.isOK || again.code == PTPResponse.sessionAlreadyOpen.rawValue else { throw MTPError.response(again.code) }
        } else if r.code == PTPResponse.deviceBusy.rawValue {
            throw MTPError.busy
        } else if !r.isOK {
            throw MTPError.response(r.code)
        }
        isOpen = true
    }

    public func closeSession() {
        guard isOpen else { return }
        _ = try? transaction(PTPOperation.closeSession.rawValue)
        isOpen = false
    }

    // MARK: - Speicher

    public func storageIDs() throws -> [UInt32] {
        var r = PTPReader(try fetch(.getStorageIDs))
        // Speicher-IDs mit unterem Wort 0 sind „nicht eingelegt“ (z. B. leerer SD-Kartenschacht).
        return try r.u32Array().filter { $0 & 0xFFFF != 0 }
    }

    public func storageInfo(_ id: UInt32) throws -> MTPStorageInfo {
        try MTPStorageInfo.parse(try fetch(.getStorageInfo, params: [id]))
    }

    // MARK: - Objekte

    public func objectHandles(storage: UInt32, parent: UInt32) throws -> [UInt32] {
        var r = PTPReader(try fetch(.getObjectHandles, params: [storage, 0, parent]))
        return try r.u32Array()
    }

    public func objectInfo(_ handle: UInt32) throws -> MTPObjectInfo {
        try MTPObjectInfo.parse(try fetch(.getObjectInfo, params: [handle]))
    }

    /// 64-Bit-Größe über die Objekteigenschaft „ObjectSize“ (für Dateien ab 4 GB).
    public func objectSize64(_ handle: UInt32) throws -> UInt64 {
        var r = PTPReader(try fetch(.getObjectPropValue, params: [handle, UInt32(MTPProperty.objectSize)]))
        return try r.u64()
    }

    public func propertyList(handle: UInt32, depth: UInt32) throws -> [MTPPropertyEntry] {
        // Android stellt die ganze Liste zusammen, bevor das erste Byte kommt – bei großen Ordnern dauert das.
        try MTPPropertyList.parse(try fetch(.getObjectPropList, params: [handle, 0, 0xFFFF_FFFF, 0, depth], timeout: max(dataTimeout, 120)))
    }

    private var propListUsable: Bool? = nil

    /// Inhalt eines Ordners. Nutzt die schnelle Eigenschaftsliste, wenn das Gerät sie zuverlässig liefert,
    /// sonst je Objekt „GetObjectInfo“.
    public func children(storage: UInt32, parent: UInt32, cancelled: () -> Bool = { false }) throws -> [DeviceEntry] {
        let handles = try objectHandles(storage: storage, parent: parent)
        if handles.isEmpty { return [] }
        var summaries: [UInt32: MTPObjectSummary] = [:]
        let canUsePropList = (deviceInfo?.supports(.getObjectPropList) ?? false) && parent != MTPHandle.root
            && handles.count >= 16 && propListUsable != false
        if canUsePropList {
            if let list = try? propertyList(handle: parent, depth: 1) {
                let map = MTPPropertyList.objects(from: list)
                let wanted = Set(handles)
                summaries = map.filter { wanted.contains($0.key) && $0.value.isComplete }
                // Liefert das Gerät für diese Abfrage nichts Brauchbares, künftig darauf verzichten.
                if summaries.count < handles.count / 2 { propListUsable = false; summaries = [:] }
                else { propListUsable = true }
            } else {
                propListUsable = false
                pending = Data()
            }
        }
        var entries: [DeviceEntry] = []
        entries.reserveCapacity(handles.count)
        for h in handles {
            if cancelled() { throw MTPError.cancelled }
            if let s = summaries[h], var e = DeviceEntry(summary: s) {
                if e.storageID == 0 { e.storageID = storage }
                if e.size == 0xFFFF_FFFF, let big = try? objectSize64(h) { e.size = big }
                entries.append(e)
                continue
            }
            do {
                let info = try objectInfo(h)
                var size: UInt64? = nil
                if info.sizeIsTruncated && !info.isFolder { size = try? objectSize64(h) }
                entries.append(DeviceEntry(handle: h, info: info, fullSize: size))
            } catch let e as MTPError where e.responseCode == PTPResponse.invalidObjectHandle.rawValue {
                // Objekt wurde inzwischen gelöscht – überspringen.
                continue
            }
        }
        return entries
    }

    /// Lädt ein Objekt herunter und reicht die Bytes stückweise weiter (ohne die Datei im Speicher zu halten).
    public func download(_ handle: UInt32, sink: @escaping (Data) throws -> Void, progress: MTPProgress?) throws {
        try checked(.getObject, params: [handle], incoming: sink, progress: progress)
    }

    /// Kann das Gerät Teilstücke liefern (Android: GetPartialObject64)? Dann lassen sich große Dateien in
    /// Abschnitten übertragen – andere Anfragen (Ordner, Vorschaubilder) kommen dazwischen an die Reihe,
    /// und Übertragungen lassen sich anhalten und fortsetzen.
    public var supportsPartialDownload: Bool {
        guard let info = deviceInfo else { return false }
        return info.supports(.getPartialObject64) || info.supports(.getPartialObject)
    }

    /// Lädt einen Abschnitt `[offset, offset+length)` herunter und liefert die Anzahl empfangener Bytes.
    @discardableResult
    public func downloadPartial(_ handle: UInt32, offset: UInt64, length: UInt32, sink: @escaping (Data) throws -> Void) throws -> UInt64 {
        var received: UInt64 = 0
        let counting: (Data) throws -> Void = { chunk in
            received += UInt64(chunk.count)
            try sink(chunk)
        }
        if deviceInfo?.supports(.getPartialObject64) == true {
            try checked(.getPartialObject64, params: [handle, UInt32(truncatingIfNeeded: offset), UInt32(truncatingIfNeeded: offset >> 32), length],
                        incoming: counting)
        } else if deviceInfo?.supports(.getPartialObject) == true, offset < 0xFFFF_FFFF {
            let clamped = UInt32(min(UInt64(length), 0xFFFF_FFFF - offset))
            try checked(.getPartialObject, params: [handle, UInt32(offset), clamped], incoming: counting)
        } else {
            throw MTPError.notSupported("Teilweises Lesen")
        }
        return received
    }

    /// Vorschaubild (meist JPEG, ~160 px) – nicht jedes Objekt hat eines.
    public func thumbnail(_ handle: UInt32) throws -> Data {
        try fetch(.getThumb, params: [handle])
    }

    /// Legt das Objekt an (Datensatz) und liefert das neue Handle.
    public func sendObjectInfo(_ info: MTPObjectInfo, storage: UInt32, parent: UInt32) throws -> UInt32 {
        let r = try transaction(PTPOperation.sendObjectInfo.rawValue, params: [storage, parent],
                                outgoing: MTPOutgoingData(info.encoded()))
        guard r.isOK else { throw MTPError.response(r.code) }
        guard r.params.count >= 3 else { throw MTPError.protocolError("SendObjectInfo ohne Handle") }
        return r.params[2]
    }

    /// Überträgt den Inhalt zum zuvor mit `sendObjectInfo` angelegten Objekt.
    public func sendObject(length: UInt64, next: @escaping (Int) throws -> Data, progress: MTPProgress?) throws {
        let previousTimeout = responseTimeout
        // Nach großen Dateien braucht das Gerät teils lange zum Abschluss (Medienscan).
        responseTimeout = max(previousTimeout, 120)
        defer { responseTimeout = previousTimeout }
        try checked(.sendObject, outgoing: MTPOutgoingData(length: length, next: next), progress: progress)
    }

    public func createFolder(name: String, storage: UInt32, parent: UInt32) throws -> UInt32 {
        try sendObjectInfo(MTPObjectInfo.forFolder(name: name, storageID: storage, parent: parent), storage: storage, parent: parent)
    }

    public func delete(_ handle: UInt32) throws {
        try checked(.deleteObject, params: [handle, 0])
    }

    public func rename(_ handle: UInt32, to name: String) throws {
        var w = PTPWriter()
        w.string(name)
        try checked(.setObjectPropValue, params: [handle, UInt32(MTPProperty.objectFileName)], outgoing: MTPOutgoingData(w.data))
    }
}
