import Foundation
import IOKit
import IOUSBHost
import ABCore
import ABObjC

/// IOKit-Rückgabewerte (die Makros aus IOReturn.h werden in Swift nicht importiert).
enum IOKitReturn {
    static let exclusiveAccess = Int32(bitPattern: 0xE000_02C5)
    static let noDevice = Int32(bitPattern: 0xE000_02C0)
    static let notPermitted = Int32(bitPattern: 0xE000_02E2)
    static let notPrivileged = Int32(bitPattern: 0xE000_02C1)
    static let timeout = Int32(bitPattern: 0xE000_02D6)
    static let aborted = Int32(bitPattern: 0xE000_02EB)
    static let notResponding = Int32(bitPattern: 0xE000_02ED)
    static let offline = Int32(bitPattern: 0xE000_02D9)
    static let busy = Int32(bitPattern: 0xE000_02D5)
    static let notAttached = Int32(bitPattern: 0xE000_02D3)
    static let pipeStalled = Int32(bitPattern: 0xE000_404F)
    static let usbTransactionTimeout = Int32(bitPattern: 0xE000_4051)
    static let usbNotResponding = Int32(bitPattern: 0xE000_4050)
    static let noResources = Int32(bitPattern: 0xE000_02BE)
    static let internalError = Int32(bitPattern: 0xE000_02C9)

    static func code(of error: Error) -> Int32 {
        let ns = error as NSError
        return Int32(truncatingIfNeeded: ns.code)
    }

    static func describe(_ code: Int32) -> String {
        "0x" + String(UInt32(bitPattern: code), radix: 16)
    }

    /// Übersetzt IOKit-Fehler in MTP-Fehler.
    static func map(_ error: Error) -> MTPError {
        let c = code(of: error)
        switch c {
        case exclusiveAccess, busy: return .busy
        case noDevice, notAttached, offline, aborted: return .disconnected
        case notPermitted, notPrivileged: return .accessDenied
        case timeout, notResponding, usbTransactionTimeout, usbNotResponding: return .timeout
        default: return .transport("\((error as NSError).localizedDescription) [\(describe(c))]")
        }
    }
}

/// Bulk-Übertragung über die Android-MTP-Schnittstelle mit Apples Benutzerraum-USB-Framework IOUSBHost
/// (keine Kernel-Erweiterung, keine Treiber, keine Fremdbibliothek).
final class IOUSBHostTransport: ClosableBulkTransport {
    let kindDescription = "IOUSBHost"
    let maxPacketSize: Int
    let bufferSize: Int
    let interfaceNumber: UInt8

    private let interface: IOUSBHostInterface
    private let bulkIn: IOUSBHostPipe
    private let bulkOut: IOUSBHostPipe
    private var readBuffer: NSMutableData
    private var writeBuffer: NSMutableData
    private var closed = false

    /// Öffnet die Schnittstelle exklusiv. Wirft `.busy`, wenn ein anderes Programm (z. B. der macOS-Fotodienst
    /// „ptpcamerad“) sie bereits hält.
    init(interfaceService: io_service_t) throws {
        let iface: IOUSBHostInterface
        do {
            var made: IOUSBHostInterface?
            var reason: NSString?
            var initError: Error?
            let ok = ABCatchObjCException({
                do { made = try IOUSBHostInterface(__ioService: interfaceService, options: [], queue: nil, interestHandler: nil) }
                catch { initError = error }
            }, &reason)
            if !ok { throw MTPError.transport("Ausnahme beim Öffnen: \((reason as String?) ?? "?")") }
            if let initError { throw initError }
            guard let made else { throw MTPError.transport("Schnittstelle konnte nicht geöffnet werden") }
            iface = made
        } catch let e as MTPError {
            throw e
        } catch {
            throw IOKitReturn.map(error)
        }

        let config = iface.configurationDescriptor
        let ifDesc = iface.interfaceDescriptor
        let number = UnsafeRawPointer(ifDesc).load(fromByteOffset: 2, as: UInt8.self)

        var inAddress: UInt8?
        var outAddress: UInt8?
        var packetSize = 512
        var current = UnsafeRawPointer(ifDesc).assumingMemoryBound(to: IOUSBDescriptorHeader.self)
        while let endpoint = IOUSBGetNextEndpointDescriptor(config, ifDesc, current) {
            let raw = UnsafeRawPointer(endpoint)
            let address = raw.load(fromByteOffset: 2, as: UInt8.self)
            let attributes = raw.load(fromByteOffset: 3, as: UInt8.self)
            let mpsLow = raw.load(fromByteOffset: 4, as: UInt8.self)
            let mpsHigh = raw.load(fromByteOffset: 5, as: UInt8.self)
            let mps = Int((UInt16(mpsHigh) << 8 | UInt16(mpsLow)) & 0x07FF)
            if attributes & 0x03 == 0x02 { // Bulk
                if address & 0x80 != 0 {
                    if inAddress == nil { inAddress = address; packetSize = max(mps, 64) }
                } else if outAddress == nil {
                    outAddress = address
                }
            }
            current = UnsafeRawPointer(endpoint).assumingMemoryBound(to: IOUSBDescriptorHeader.self)
        }
        guard let inAddress, let outAddress else {
            iface.destroy()
            throw MTPError.protocolError("Keine Bulk-Endpunkte in der MTP-Schnittstelle")
        }
        // 512 KiB je Anforderung – Vielfaches jeder Paketgröße (64/512/1024).
        let size = 512 * 1024
        let pipeIn: IOUSBHostPipe
        let pipeOut: IOUSBHostPipe
        let rBuf: NSMutableData
        let wBuf: NSMutableData
        do {
            pipeIn = try iface.copyPipe(withAddress: Int(inAddress))
            pipeOut = try iface.copyPipe(withAddress: Int(outAddress))
            rBuf = try iface.ioData(withCapacity: size)
            wBuf = try iface.ioData(withCapacity: size)
        } catch {
            iface.destroy()
            throw IOKitReturn.map(error)
        }
        interface = iface
        interfaceNumber = number
        maxPacketSize = packetSize
        bufferSize = size
        bulkIn = pipeIn
        bulkOut = pipeOut
        readBuffer = rBuf
        writeBuffer = wBuf
    }

    deinit { close() }

    func close() {
        guard !closed else { return }
        closed = true
        _ = try? guarded("Schließen") { interface.destroy() }
    }

    /// Führt einen IOUSBHost-Aufruf aus; Objective-C-Ausnahmen werden zu Fehlern (statt Absturz).
    private func guarded<T>(_ what: String, _ body: () throws -> T) throws -> T {
        var result: Result<T, Error>?
        var reason: NSString?
        let ok = ABCatchObjCException({ result = Result { try body() } }, &reason)
        guard ok, let result else {
            let text = (reason as String?) ?? "unbekannte Ausnahme"
            Diagnostics.shared.log(.usb, "Ausnahme in IOUSBHost (\(what)): \(text)", error: true)
            throw MTPError.transport("Ausnahme in IOUSBHost (\(what)): \(text)")
        }
        return try result.get()
    }

    /// Nach Zeitüberschreitung oder Fehler: laufende Anforderung am Endpunkt synchron abbrechen und einen frischen
    /// Puffer verwenden – ein noch belegter Puffer darf nicht wiederverwendet werden.
    private func recover(pipe: IOUSBHostPipe, isRead: Bool, code: Int32?) {
        _ = try? guarded("Abbruch") { try pipe.__abort(with: .synchronous) }
        if code == IOKitReturn.pipeStalled { _ = try? guarded("Stillstand aufheben") { try pipe.clearStall() } }
        if let fresh = try? guarded("Puffer") { try interface.ioData(withCapacity: bufferSize) } {
            if isRead { readBuffer = fresh } else { writeBuffer = fresh }
        }
    }

    func read(maxLength: Int, timeout: TimeInterval) throws -> Data {
        guard !closed else { throw MTPError.disconnected }
        let length = min(maxLength, bufferSize)
        let buffer = readBuffer
        var transferred = 0
        do {
            try guarded("Lesen") {
                buffer.length = length
                try bulkIn.__sendIORequest(with: buffer, bytesTransferred: &transferred, completionTimeout: max(timeout, 1))
            }
        } catch let e as MTPError {
            recover(pipe: bulkIn, isRead: true, code: nil)
            throw e
        } catch {
            let code = IOKitReturn.code(of: error)
            recover(pipe: bulkIn, isRead: true, code: code)
            throw IOKitReturn.map(error)
        }
        return try guarded("Lesepuffer") { Data(bytes: buffer.bytes, count: min(transferred, length)) }
    }

    func write(_ data: Data, timeout: TimeInterval) throws {
        guard !closed else { throw MTPError.disconnected }
        var offset = 0
        repeat {
            let n = min(bufferSize, data.count - offset)
            let buffer = writeBuffer
            var transferred = 0
            do {
                try guarded("Schreiben") {
                    buffer.length = n
                    if n > 0 {
                        data.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
                            if let base = src.baseAddress {
                                buffer.mutableBytes.copyMemory(from: base.advanced(by: offset), byteCount: n)
                            }
                        }
                    }
                    try bulkOut.__sendIORequest(with: buffer, bytesTransferred: &transferred, completionTimeout: max(timeout, 1))
                }
            } catch let e as MTPError {
                recover(pipe: bulkOut, isRead: false, code: nil)
                throw e
            } catch {
                let code = IOKitReturn.code(of: error)
                recover(pipe: bulkOut, isRead: false, code: code)
                throw IOKitReturn.map(error)
            }
            if transferred < n { throw MTPError.incomplete(expected: UInt64(n), received: UInt64(transferred)) }
            offset += n
        } while offset < data.count
    }

    /// Still-Image-Klassenanforderung „Cancel Request“ (bRequest 0x64) mit Code 0x4001 und Transaktionsnummer.
    func cancelTransaction(_ transactionID: UInt32) throws {
        guard !closed else { return }
        let payload = try guarded("Puffer") { try interface.ioData(withCapacity: 6) }
        try guarded("Puffer") { payload.length = 6 }
        var bytes: [UInt8] = [0x01, 0x40]
        for i in 0..<4 { bytes.append(UInt8((transactionID >> (8 * UInt32(i))) & 0xFF)) }
        payload.replaceBytes(in: NSRange(location: 0, length: 6), withBytes: bytes)
        let request = IOUSBDeviceRequest(bmRequestType: 0x21, bRequest: 0x64, wValue: 0, wIndex: UInt16(interfaceNumber), wLength: 6)
        var transferred = 0
        do {
            try guarded("Abbruchanforderung") {
                try interface.__send(request, data: payload, bytesTransferred: &transferred, completionTimeout: 2)
            }
        } catch let e as MTPError {
            throw e
        } catch {
            throw IOKitReturn.map(error)
        }
    }

    func clearStalls() {
        guard !closed else { return }
        _ = try? guarded("Stillstand aufheben") { try bulkIn.clearStall() }
        _ = try? guarded("Stillstand aufheben") { try bulkOut.clearStall() }
    }
}
