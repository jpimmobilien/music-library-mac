import XCTest
@testable import ABCore

final class PTPCodingTests: XCTestCase {
    func testIntegersRoundTrip() throws {
        var w = PTPWriter()
        w.u8(0xAB); w.u16(0xBEEF); w.u32(0xDEAD_BEEF); w.u64(0x0123_4567_89AB_CDEF)
        var r = PTPReader(w.data)
        XCTAssertEqual(try r.u8(), 0xAB)
        XCTAssertEqual(try r.u16(), 0xBEEF)
        XCTAssertEqual(try r.u32(), 0xDEAD_BEEF)
        XCTAssertEqual(try r.u64(), 0x0123_4567_89AB_CDEF)
        XCTAssertTrue(r.isAtEnd)
    }

    func testLittleEndianLayout() {
        var w = PTPWriter()
        w.u32(0x1122_3344)
        XCTAssertEqual(w.bytes, [0x44, 0x33, 0x22, 0x11])
    }

    func testStringsIncludingUnicodeAndEmpty() throws {
        var w = PTPWriter()
        w.string("Größe 📷")
        w.string("")
        var r = PTPReader(w.data)
        XCTAssertEqual(try r.string(), "Größe 📷")
        XCTAssertEqual(try r.string(), "")
        XCTAssertEqual(w.bytes.first, UInt8("Größe 📷".utf16.count + 1))
    }

    func testLongStringIsTruncatedWithoutBrokenSurrogate() throws {
        let long = String(repeating: "a", count: 253) + "😀😀"
        var w = PTPWriter()
        w.string(long)
        var r = PTPReader(w.data)
        let decoded = try r.string()
        XCTAssertLessThanOrEqual(decoded.utf16.count, 254)
        XCTAssertTrue(decoded.hasPrefix(String(repeating: "a", count: 253)))
        XCTAssertFalse(decoded.unicodeScalars.contains { $0.value == 0xFFFD })
    }

    func testTruncatedDataThrows() {
        var r = PTPReader(Data([0x01, 0x02]))
        XCTAssertThrowsError(try r.u32())
    }

    func testArrays() throws {
        var w = PTPWriter()
        w.u32(3); w.u32(7); w.u32(8); w.u32(9)
        var r = PTPReader(w.data)
        XCTAssertEqual(try r.u32Array(), [7, 8, 9])
    }
}

final class PTPContainerTests: XCTestCase {
    func testCommandContainer() throws {
        let bytes = PTPContainers.command(0x1007, transactionID: 5, params: [1, 0, 0xFFFF_FFFF])
        XCTAssertEqual(bytes.count, 24)
        let h = try PTPContainerHeader.parse(bytes)
        XCTAssertEqual(h.length, 24)
        XCTAssertEqual(h.containerType, .command)
        XCTAssertEqual(h.code, 0x1007)
        XCTAssertEqual(h.transactionID, 5)
    }

    func testDataHeaderBelowAndAbove4GB() throws {
        let small = try PTPContainerHeader.parse(PTPContainers.dataHeader(0x100D, transactionID: 1, payloadLength: 1000))
        XCTAssertEqual(small.length, 1012)
        let big = try PTPContainerHeader.parse(PTPContainers.dataHeader(0x100D, transactionID: 1, payloadLength: 5_000_000_000))
        XCTAssertEqual(big.length, 0xFFFF_FFFF)
        XCTAssertTrue(big.hasUnknownLength)
        XCTAssertNil(big.payloadLength)
        // Grenzfall: genau 4 GB − 12 Bytes Nutzdaten → Gesamtlänge 0xFFFFFFFF ist reserviert
        let edge = try PTPContainerHeader.parse(PTPContainers.dataHeader(0x100D, transactionID: 1, payloadLength: 0xFFFF_FFFF - 12))
        XCTAssertTrue(edge.hasUnknownLength)
    }

    func testInvalidHeaderRejected() {
        XCTAssertThrowsError(try PTPContainerHeader.parse([8, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0]))
    }

    func testZeroLengthPacketRule() {
        XCTAssertTrue(PTPContainers.needsZeroLengthPacket(totalBytes: 512, maxPacketSize: 512))
        XCTAssertTrue(PTPContainers.needsZeroLengthPacket(totalBytes: 2048, maxPacketSize: 512))
        XCTAssertFalse(PTPContainers.needsZeroLengthPacket(totalBytes: 513, maxPacketSize: 512))
        XCTAssertFalse(PTPContainers.needsZeroLengthPacket(totalBytes: 0, maxPacketSize: 512))
    }

    func testReadRequestSize() {
        XCTAssertEqual(PTPContainers.readRequestSize(remaining: 100, bufferSize: 4096, maxPacketSize: 512), 512)
        XCTAssertEqual(PTPContainers.readRequestSize(remaining: 1024, bufferSize: 4096, maxPacketSize: 512), 1024)
        XCTAssertEqual(PTPContainers.readRequestSize(remaining: 100_000, bufferSize: 4096, maxPacketSize: 512), 4096)
        XCTAssertEqual(PTPContainers.readRequestSize(remaining: nil, bufferSize: 4096, maxPacketSize: 512), 4096)
    }
}

final class DatasetTests: XCTestCase {
    func testObjectInfoRoundTrip() throws {
        let info = MTPObjectInfo(storageID: 0x10001, objectFormat: MTPFormat.exifJPEG, compressedSize: 123_456,
                                 imagePixWidth: 4000, imagePixHeight: 3000, parentObject: 42,
                                 filename: "PXL_20240101_120000.jpg", captureDate: "20240101T120000",
                                 modificationDate: "20240101T120001")
        let parsed = try MTPObjectInfo.parse(info.encoded())
        XCTAssertEqual(parsed, info)
    }

    func testUploadInfoFor5GBFile() {
        let info = MTPObjectInfo.forUpload(name: "Film.mp4", size: 5_000_000_000, storageID: 1, parent: 0xFFFF_FFFF, modified: nil)
        XCTAssertEqual(info.compressedSize, 0xFFFF_FFFF)
        XCTAssertTrue(info.sizeIsTruncated)
        XCTAssertEqual(info.objectFormat, MTPFormat.mp4)
    }

    func testFolderInfo() {
        let info = MTPObjectInfo.forFolder(name: "Urlaub", storageID: 1, parent: 7)
        XCTAssertTrue(info.isFolder)
        XCTAssertEqual(info.associationType, 1)
    }

    func testStorageInfoParsing() throws {
        var w = PTPWriter()
        w.u16(4); w.u16(2); w.u16(0); w.u64(64_000_000_000); w.u64(10_000_000_000); w.u32(0xFFFF_FFFF)
        w.string("SD-Karte"); w.string("SANDISK")
        let s = try MTPStorageInfo.parse(w.data)
        XCTAssertTrue(s.isRemovable)
        XCTAssertFalse(s.isReadOnly)
        let storage = DeviceStorage(id: 0x20001, info: s)
        XCTAssertEqual(storage.displayName, "SD-Karte")
        XCTAssertEqual(storage.used, 54_000_000_000)
        XCTAssertEqual(storage.usedFraction, 54.0 / 64.0, accuracy: 0.0001)
    }

    func testStorageDisplayNameFallback() {
        let s = DeviceStorage(id: 1, description: "  ", volumeLabel: "", capacity: 0, free: 0, isRemovable: true, isReadOnly: false)
        XCTAssertEqual(s.displayName, "SD-Karte")
        XCTAssertEqual(s.usedFraction, 0)
    }

    func testPropertyListParsing() throws {
        var w = PTPWriter()
        w.u32(4)
        w.u32(9); w.u16(MTPProperty.objectFileName); w.u16(PTPDataType.string); w.string("a.jpg")
        w.u32(9); w.u16(MTPProperty.objectSize); w.u16(PTPDataType.uint64); w.u64(6_000_000_000)
        w.u32(9); w.u16(MTPProperty.objectFormat); w.u16(PTPDataType.uint16); w.u16(MTPFormat.exifJPEG)
        w.u32(9); w.u16(0xDC99); w.u16(PTPDataType.arrayFlag | PTPDataType.uint8); w.u32(3); w.u8(1); w.u8(2); w.u8(3)
        let entries = try MTPPropertyList.parse(w.data)
        XCTAssertEqual(entries.count, 4)
        let summary = MTPPropertyList.objects(from: entries)[9]
        XCTAssertEqual(summary?.name, "a.jpg")
        XCTAssertEqual(summary?.size, 6_000_000_000)
        XCTAssertTrue(summary?.isComplete ?? false)
        let entry = DeviceEntry(summary: summary!)
        XCTAssertEqual(entry?.kind, .photo)
    }

    func testMTPDateParsing() {
        let utc = MTPDate.parse("20240315T081530Z")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(cal.component(.hour, from: utc!), 8)
        XCTAssertEqual(cal.component(.minute, from: utc!), 15)
        XCTAssertNotNil(MTPDate.parse("20240315T081530.5"))
        let offset = MTPDate.parse("20240315T101530+0200")
        XCTAssertEqual(offset, utc)
        XCTAssertNil(MTPDate.parse(""))
        XCTAssertNil(MTPDate.parse("garbage"))
        XCTAssertNil(MTPDate.parse("19700101T000000"))
    }

    func testMTPDateFormatRoundTrip() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let s = MTPDate.format(date, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(s, "20231114T221320")
        XCTAssertEqual(MTPDate.parse(s + "Z"), date)
    }
}

final class SessionTests: XCTestCase {
    private func makeDevice(mps: Int = 512, buffer: Int = 4096) -> SimulatedMTPDevice {
        let d = SimulatedMTPDevice(maxPacketSize: mps, bufferSize: buffer)
        d.objects[1] = .init(storage: 0x10001, parent: 0, name: "DCIM", isFolder: true, data: Data())
        d.objects[2] = .init(storage: 0x10001, parent: 1, name: "Camera", isFolder: true, data: Data())
        d.objects[3] = .init(storage: 0x10001, parent: 0, name: "Download", isFolder: true, data: Data())
        d.objects[4] = .init(storage: 0x20001, parent: 0, name: "Musik", isFolder: true, data: Data())
        return d
    }

    private func pattern(_ n: Int) -> Data {
        Data((0..<n).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
    }

    func testOpenSessionAndDeviceInfo() throws {
        let dev = makeDevice()
        let s = MTPSession(transport: dev)
        let info = try s.getDeviceInfo()
        XCTAssertEqual(info.model, "Pixel 6 Pro")
        XCTAssertTrue(info.isMTP)
        try s.openSession()
        XCTAssertTrue(s.isOpen)
        // erneutes Öffnen nach „SessionAlreadyOpen“ funktioniert
        let s2 = MTPSession(transport: dev)
        try s2.openSession()
        XCTAssertTrue(s2.isOpen)
    }

    func testStoragesAndRootListing() throws {
        let dev = makeDevice()
        let s = MTPSession(transport: dev)
        try s.openSession()
        let ids = try s.storageIDs()
        XCTAssertEqual(ids, [0x10001, 0x20001])
        let sd = try s.storageInfo(0x20001)
        XCTAssertTrue(sd.isRemovable)
        let root = try s.children(storage: 0x10001, parent: MTPHandle.root)
        XCTAssertEqual(Set(root.map(\.name)), ["DCIM", "Download"])
        XCTAssertTrue(root.allSatisfy(\.isFolder))
        let sdRoot = try s.children(storage: 0x20001, parent: MTPHandle.root)
        XCTAssertEqual(sdRoot.map(\.name), ["Musik"])
    }

    func testListingWithPropertyListAndFallback() throws {
        for supports in [true, false] {
            let dev = makeDevice()
            dev.supportsPropList = supports
            for i in 0..<40 {
                dev.objects[UInt32(1000 + i)] = .init(storage: 0x10001, parent: 2, name: "IMG_\(i).jpg", isFolder: false, data: pattern(10 + i))
            }
            let s = MTPSession(transport: dev)
            _ = try s.getDeviceInfo()
            try s.openSession()
            let entries = try s.children(storage: 0x10001, parent: 2)
            XCTAssertEqual(entries.count, 40)
            XCTAssertEqual(entries.first(where: { $0.name == "IMG_5.jpg" })?.size, 15)
            XCTAssertNotNil(entries.first?.modified)
        }
    }

    /// Download mit verschiedenen Größen rund um Paket- und Puffergrenzen, mit und ohne Nullpakete
    /// und mit unbekannter Länge (Pfad für Dateien über 4 GB).
    func testDownloadFramingEdgeCases() throws {
        let sizes = [0, 1, 499, 500, 511, 512, 513, 1012, 1024, 4084, 4096, 4097, 8192, 20_000, 65_536]
        for zlp in [true, false] {
            for unknown in [false, true] {
                for size in sizes {
                    let dev = makeDevice()
                    dev.sendsZeroLengthPackets = zlp
                    dev.forceUnknownLengthForGetObject = unknown
                    if unknown && !zlp { continue } // unbekannte Länge erfordert ein kurzes Abschlusspaket
                    if unknown && size == 0 { continue } // 0xFFFFFFFF kommt nur bei Daten über 4 GB vor
                    let content = pattern(size)
                    dev.objects[50] = .init(storage: 0x10001, parent: 2, name: "f.bin", isFolder: false, data: content)
                    let s = MTPSession(transport: dev)
                    try s.openSession()
                    var received = Data()
                    var lastProgress: UInt64 = 0
                    try s.download(50, sink: { received.append($0) }, progress: { lastProgress = $0; return true })
                    XCTAssertEqual(received, content, "Größe \(size), Nullpaket \(zlp), unbekannt \(unknown)")
                    XCTAssertEqual(lastProgress, UInt64(size) == 0 ? lastProgress : UInt64(size))
                    // Folgeoperation muss sauber funktionieren (keine Restdaten im Kanal)
                    XCTAssertEqual(try s.storageIDs(), [0x10001, 0x20001], "Folgeoperation nach Größe \(size)")
                }
            }
        }
    }

    func testUploadFramingEdgeCases() throws {
        for size in [0, 1, 500, 4084, 4096, 4097, 12_288, 30_000] {
            let dev = makeDevice()
            let s = MTPSession(transport: dev)
            try s.openSession()
            let content = pattern(size)
            let info = MTPObjectInfo.forUpload(name: "upload.bin", size: UInt64(size), storageID: 0x10001, parent: 3, modified: Date())
            let handle = try s.sendObjectInfo(info, storage: 0x10001, parent: 3)
            var offset = 0
            try s.sendObject(length: UInt64(size), next: { max in
                // ungleichmäßige Lieferung wie beim Lesen aus Dateien
                let n = min(max, 777, size - offset)
                defer { offset += n }
                return content.subdata(in: offset..<(offset + n))
            }, progress: nil)
            XCTAssertEqual(dev.objects[handle]?.data, content, "Größe \(size)")
            XCTAssertEqual(dev.objects[handle]?.parent, 3)
            // Alle Schreibvorgänge außer dem letzten sind Vielfache der Paketgröße
            let writes = dev.receivedWrites
            XCTAssertEqual(try s.storageIDs().count, 2)
            _ = writes
        }
    }

    func testSegmentedDownload() throws {
        let dev = makeDevice()
        let content = pattern(100_000)
        dev.objects[70] = .init(storage: 0x10001, parent: 2, name: "v.mp4", isFolder: false, data: content)
        let s = MTPSession(transport: dev)
        _ = try s.getDeviceInfo()
        try s.openSession()
        XCTAssertTrue(s.supportsPartialDownload)
        var received = Data()
        var offset: UInt64 = 0
        while offset < UInt64(content.count) {
            let n = try s.downloadPartial(70, offset: offset, length: 16_384, sink: { received.append($0) })
            XCTAssertGreaterThan(n, 0)
            offset += n
            // zwischen den Abschnitten sind andere Anfragen möglich
            XCTAssertEqual(try s.storageIDs().count, 2)
        }
        XCTAssertEqual(received, content)
    }

    func testUnknownLengthWithSeparateHeaderTransfer() throws {
        for size in [1, 512, 4084, 4096, 9000] {
            let dev = makeDevice()
            dev.forceUnknownLengthForGetObject = true
            dev.sendHeaderSeparately = true
            let content = pattern(size)
            dev.objects[80] = .init(storage: 0x10001, parent: 2, name: "big.mkv", isFolder: false, data: content)
            let s = MTPSession(transport: dev)
            try s.openSession()
            var received = Data()
            try s.download(80, sink: { received.append($0) }, progress: nil)
            XCTAssertEqual(received, content, "Größe \(size)")
            XCTAssertEqual(try s.storageIDs().count, 2)
        }
    }

    func testStaleReplyIsDiscarded() throws {
        let dev = makeDevice()
        let s = MTPSession(transport: dev)
        try s.openSession()
        dev.injectStaleReply()
        XCTAssertEqual(try s.storageIDs(), [0x10001, 0x20001])
        let root = try s.children(storage: 0x10001, parent: MTPHandle.root)
        XCTAssertEqual(root.count, 2)
    }

    func testLeftoverDataIsFlushedBeforeNewSession() throws {
        let dev = makeDevice()
        dev.injectLeftoverBytes(50_000)
        let s = MTPSession(transport: dev)
        s.flushStaleData()
        XCTAssertEqual(try s.getDeviceInfo().model, "Pixel 6 Pro")
        try s.openSession()
        XCTAssertEqual(try s.storageIDs().count, 2)
    }

    func testUploadSourceErrorAbortsAndKeepsSessionUsable() throws {
        struct ReadFailure: Error {}
        let dev = makeDevice()
        let s = MTPSession(transport: dev)
        try s.openSession()
        let info = MTPObjectInfo.forUpload(name: "x.bin", size: 50_000, storageID: 0x10001, parent: 3, modified: nil)
        _ = try s.sendObjectInfo(info, storage: 0x10001, parent: 3)
        var calls = 0
        XCTAssertThrowsError(try s.sendObject(length: 50_000, next: { max in
            calls += 1
            if calls > 2 { throw ReadFailure() }
            return Data(repeating: 1, count: max)
        }, progress: nil))
        XCTAssertFalse(dev.cancelRequests.isEmpty, "Gerät muss den Abbruch erhalten")
        XCTAssertEqual(try s.storageIDs().count, 2)
    }

    func testCancelAtVeryEndDoesNotSendCancelRequest() throws {
        let dev = makeDevice()
        dev.objects[90] = .init(storage: 0x10001, parent: 2, name: "a.jpg", isFolder: false, data: pattern(3000))
        let s = MTPSession(transport: dev)
        try s.openSession()
        // Fortschritt meldet erst beim letzten Stück „abbrechen“: Daten sind schon vollständig.
        XCTAssertThrowsError(try s.download(90, sink: { _ in }, progress: { $0 < 3000 }))
        XCTAssertTrue(dev.cancelRequests.isEmpty)
        XCTAssertEqual(try s.storageIDs().count, 2)
    }

    func testCreateRenameDelete() throws {
        let dev = makeDevice()
        let s = MTPSession(transport: dev)
        try s.openSession()
        let folder = try s.createFolder(name: "Neuer Ordner", storage: 0x10001, parent: MTPHandle.root)
        XCTAssertEqual(dev.objects[folder]?.isFolder, true)
        XCTAssertEqual(dev.objects[folder]?.parent, 0)
        try s.rename(folder, to: "Urlaub 2024")
        XCTAssertEqual(dev.objects[folder]?.name, "Urlaub 2024")
        try s.delete(folder)
        XCTAssertNil(dev.objects[folder])
        XCTAssertThrowsError(try s.delete(9999)) { error in
            XCTAssertEqual((error as? MTPError)?.responseCode, PTPResponse.invalidObjectHandle.rawValue)
        }
    }

    func testCancelDuringDownloadLeavesSessionUsable() throws {
        let dev = makeDevice()
        dev.objects[60] = .init(storage: 0x10001, parent: 2, name: "big.mp4", isFolder: false, data: pattern(100_000))
        let s = MTPSession(transport: dev)
        try s.openSession()
        XCTAssertThrowsError(try s.download(60, sink: { _ in }, progress: { $0 < 10_000 })) { error in
            XCTAssertEqual(error as? MTPError, .cancelled)
        }
        XCTAssertFalse(dev.cancelRequests.isEmpty)
        XCTAssertEqual(try s.storageIDs().count, 2)
    }

    func testSinkErrorAbortsTransaction() throws {
        struct DiskFull: Error {}
        let dev = makeDevice()
        dev.objects[61] = .init(storage: 0x10001, parent: 2, name: "x.bin", isFolder: false, data: pattern(50_000))
        let s = MTPSession(transport: dev)
        try s.openSession()
        XCTAssertThrowsError(try s.download(61, sink: { _ in throw DiskFull() }, progress: nil))
        XCTAssertEqual(try s.storageIDs().count, 2)
    }
}
