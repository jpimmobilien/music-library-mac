import Foundation
import IOKit
import ABCore
import ABObjC

/// Gemeinsame Schnittstelle der USB-Zugänge (klassisches IOKit bzw. IOUSBHost).
protocol ClosableBulkTransport: MTPBulkTransport {
    var kindDescription: String { get }
    func close()
}

/// Bulk-Übertragung über die klassische IOKit-USB-Schnittstelle (IOUSBInterfaceInterface) –
/// der Weg von libusb/OpenMTP und Android File Transfer. Erste Wahl; IOUSBHost dient als Rückfall.
final class LegacyUSBTransport: ClosableBulkTransport {
    let maxPacketSize: Int
    let bufferSize = 512 * 1024
    let kindDescription = "IOKit (IOUSBInterfaceInterface)"
    private let usb: ABLegacyUSBInterface
    private let buffer: UnsafeMutableRawPointer
    private var closed = false

    init(interfaceService: io_service_t, seize: Bool = false) throws {
        do {
            usb = try ABLegacyUSBInterface(service: interfaceService, seize: seize)
        } catch {
            throw IOKitReturn.map(error)
        }
        maxPacketSize = Int(usb.maxPacketSize)
        buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 64)
    }

    deinit {
        close()
        buffer.deallocate()
    }

    func close() {
        guard !closed else { return }
        closed = true
        usb.close()
    }

    private func ms(_ t: TimeInterval) -> UInt32 { UInt32(max(1000, min(t * 1000, 600_000))) }

    func read(maxLength: Int, timeout: TimeInterval) throws -> Data {
        guard !closed else { throw MTPError.disconnected }
        let length = min(maxLength, bufferSize)
        var transferred: UInt = 0
        do {
            try usb.read(into: buffer, length: UInt(length), transferred: &transferred, timeoutMs: ms(timeout))
        } catch {
            throw IOKitReturn.map(error)
        }
        return Data(bytes: buffer, count: min(Int(transferred), length))
    }

    func write(_ data: Data, timeout: TimeInterval) throws {
        guard !closed else { throw MTPError.disconnected }
        var offset = 0
        repeat {
            let n = min(bufferSize, data.count - offset)
            if n > 0 {
                data.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
                    if let base = src.baseAddress { buffer.copyMemory(from: base.advanced(by: offset), byteCount: n) }
                }
            }
            do {
                try usb.write(buffer, length: UInt(n), timeoutMs: ms(timeout))
            } catch {
                throw IOKitReturn.map(error)
            }
            offset += n
        } while offset < data.count
    }

    func cancelTransaction(_ transactionID: UInt32) throws {
        guard !closed else { return }
        var bytes: [UInt8] = [0x01, 0x40]
        for i in 0..<4 { bytes.append(UInt8((transactionID >> (8 * UInt32(i))) & 0xFF)) }
        do {
            try bytes.withUnsafeMutableBytes { raw in
                try usb.controlRequestType(0x21, request: 0x64, value: 0, index: UInt16(usb.interfaceNumber),
                                           data: raw.baseAddress, length: 6, timeoutMs: 2000)
            }
        } catch {
            throw IOKitReturn.map(error)
        }
    }

    func clearStalls() {
        guard !closed else { return }
        usb.clearStall(in: true)
        usb.clearStall(in: false)
    }
}
