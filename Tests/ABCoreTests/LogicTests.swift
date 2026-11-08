import XCTest
@testable import ABCore

final class ClassificationTests: XCTestCase {
    func testPixelInMTPModeWithNamedInterface() {
        let ifaces = [USBInterfaceDescriptor(number: 0, interfaceClass: 0xFF, subClass: 0xFF, interfaceProtocol: 0, name: "MTP")]
        XCTAssertEqual(USBDeviceClassifier.classify(vendorID: 0x18D1, interfaces: ifaces), .fileTransfer(interface: 0, isPTPOnly: false))
    }

    func testUnknownVendorWithNamedMTPStillWorks() {
        // Kein Modell- oder Herstellereintrag nötig: das Protokoll entscheidet.
        let ifaces = [USBInterfaceDescriptor(number: 1, interfaceClass: 0xFF, subClass: 0xFF, interfaceProtocol: 0, name: "MTP")]
        XCTAssertEqual(USBDeviceClassifier.classify(vendorID: 0x9999, interfaces: ifaces), .fileTransfer(interface: 1, isPTPOnly: false))
    }

    func testMTPWithADBPicksMTPInterface() {
        let ifaces = [
            USBInterfaceDescriptor(number: 0, interfaceClass: 0xFF, subClass: 0xFF, interfaceProtocol: 0, name: nil),
            USBInterfaceDescriptor(number: 1, interfaceClass: 0xFF, subClass: 0x42, interfaceProtocol: 1, name: "ADB Interface"),
        ]
        XCTAssertEqual(USBDeviceClassifier.classify(vendorID: 0x18D1, interfaces: ifaces), .fileTransfer(interface: 0, isPTPOnly: false))
    }

    func testStillImageClassInterface() {
        let ifaces = [USBInterfaceDescriptor(number: 0, interfaceClass: 6, subClass: 1, interfaceProtocol: 1, name: nil)]
        XCTAssertEqual(USBDeviceClassifier.classify(vendorID: 0x04E8, interfaces: ifaces), .fileTransfer(interface: 0, isPTPOnly: false))
    }

    func testChargingOnlyWithADB() {
        let ifaces = [USBInterfaceDescriptor(number: 0, interfaceClass: 0xFF, subClass: 0x42, interfaceProtocol: 1)]
        XCTAssertEqual(USBDeviceClassifier.classify(vendorID: 0x18D1, interfaces: ifaces), .androidWithoutFileTransfer)
    }

    func testChargingOnlyKnownVendorNoInterfaces() {
        XCTAssertEqual(USBDeviceClassifier.classify(vendorID: 0x2717, interfaces: []), .androidWithoutFileTransfer)
    }

    func testTetheringIsNotFileTransfer() {
        let ifaces = [USBInterfaceDescriptor(number: 0, interfaceClass: 0xE0, subClass: 1, interfaceProtocol: 3),
                      USBInterfaceDescriptor(number: 1, interfaceClass: 0x0A, subClass: 0, interfaceProtocol: 0)]
        XCTAssertEqual(USBDeviceClassifier.classify(vendorID: 0x18D1, interfaces: ifaces), .androidWithoutFileTransfer)
    }

    func testStorageShortName() {
        let internalStorage = DeviceStorage(id: 1, description: "Interner gemeinsamer Speicher", volumeLabel: "", capacity: 1, free: 1, isRemovable: false, isReadOnly: false)
        XCTAssertEqual(internalStorage.shortName, "Interner Speicher")
        let sd = DeviceStorage(id: 2, description: "SanDisk SD card", volumeLabel: "", capacity: 1, free: 1, isRemovable: true, isReadOnly: false)
        XCTAssertEqual(sd.shortName, "SD-Karte")
        let english = DeviceStorage(id: 3, description: "Internal shared storage", volumeLabel: "", capacity: 1, free: 1, isRemovable: false, isReadOnly: false)
        XCTAssertEqual(english.shortName, "Interner Speicher")
    }

    func testSamsungSSDIsNotAPhone() {
        // Samsung PSSD T5 EVO: Samsung-Hersteller-ID, aber Massenspeicher (UAS/BOT)
        let ssd = [USBInterfaceDescriptor(number: 0, interfaceClass: 0x08, subClass: 0x06, interfaceProtocol: 0x62)]
        XCTAssertEqual(USBDeviceClassifier.classify(vendorID: 0x04E8, interfaces: ssd), .unrelated)
        XCTAssertEqual(USBDeviceClassifier.classify(vendorID: 0x04E8, interfaces: [], productName: "PSSD T5 EVO"), .unrelated)
        XCTAssertEqual(USBDeviceClassifier.classify(vendorID: 0x04E8, interfaces: ssd, productName: "Portable SSD T7"), .unrelated)
        // Samsung-Monitor mit Hub/HID
        let monitor = [USBInterfaceDescriptor(number: 0, interfaceClass: 0x03, subClass: 0, interfaceProtocol: 0)]
        XCTAssertEqual(USBDeviceClassifier.classify(vendorID: 0x04E8, interfaces: monitor), .unrelated)
        // Galaxy-Telefon im Lademodus bleibt erkannt
        XCTAssertEqual(USBDeviceClassifier.classify(vendorID: 0x04E8, interfaces: [], productName: "SAMSUNG_Android"), .androidWithoutFileTransfer)
    }

    func testOtherDevicesIgnored() {
        let keyboard = [USBInterfaceDescriptor(number: 0, interfaceClass: 3, subClass: 1, interfaceProtocol: 1)]
        XCTAssertEqual(USBDeviceClassifier.classify(vendorID: 0x046D, interfaces: keyboard), .unrelated)
        let iphone = [USBInterfaceDescriptor(number: 0, interfaceClass: 6, subClass: 1, interfaceProtocol: 1)]
        XCTAssertEqual(USBDeviceClassifier.classify(vendorID: 0x05AC, interfaces: iphone), .unrelated)
    }
}

final class FileLogicTests: XCTestCase {
    func testFileKinds() {
        XCTAssertEqual(FileKind.of(name: "PXL_1.JPG", isFolder: false), .photo)
        XCTAssertEqual(FileKind.of(name: "clip.MP4", isFolder: false), .video)
        XCTAssertEqual(FileKind.of(name: "song.flac", isFolder: false), .audio)
        XCTAssertEqual(FileKind.of(name: "Vertrag.pdf", isFolder: false), .document)
        XCTAssertEqual(FileKind.of(name: "app.apk", isFolder: false), .apk)
        XCTAssertEqual(FileKind.of(name: ".nomedia", isFolder: false), .other)
        XCTAssertEqual(FileKind.of(name: "DCIM", isFolder: true), .folder)
        XCTAssertEqual(FileKind.fileExtension(of: "archive.tar.gz"), "gz")
        XCTAssertEqual(FileKind.fileExtension(of: "README"), "")
    }

    func testMediaFilters() {
        XCTAssertTrue(MediaFilter.screenshots.matches(name: "Screenshot_2024.png", kind: .photo, path: ["Pictures"]))
        XCTAssertTrue(MediaFilter.screenshots.matches(name: "a.png", kind: .photo, path: ["DCIM", "Screenshots"]))
        XCTAssertFalse(MediaFilter.screenshots.matches(name: "IMG_1.jpg", kind: .photo, path: ["DCIM", "Camera"]))
        XCTAssertTrue(MediaFilter.downloads.matches(name: "x.pdf", kind: .document, path: ["Download"]))
        XCTAssertFalse(MediaFilter.all.matches(name: "DCIM", kind: .folder, path: []))
        XCTAssertTrue(MediaFilter.videos.matches(name: "v.mp4", kind: .video, path: []))
    }

    private func entry(_ name: String, folder: Bool = false, size: UInt64 = 0, date: Double? = nil) -> DeviceEntry {
        DeviceEntry(handle: UInt32.random(in: 1...999_999), storageID: 1, parent: 0, name: name, isFolder: folder, size: size,
                    format: 0x3000, modified: date.map { Date(timeIntervalSince1970: $0) })
    }

    func testNaturalSortWithFoldersFirst() {
        let items = [entry("Bild 10.jpg"), entry("bild 2.jpg"), entry("Zeta", folder: true), entry("Alpha", folder: true), entry("Bild 1.jpg")]
        let sorted = EntrySorting.sorted(items, by: .name).map(\.name)
        XCTAssertEqual(sorted, ["Alpha", "Zeta", "Bild 1.jpg", "bild 2.jpg", "Bild 10.jpg"])
    }

    func testDateAndSizeSort() {
        let items = [entry("a", size: 5, date: 100), entry("b", size: 50, date: 300), entry("c", size: 10, date: nil), entry("d", size: 1, date: 200)]
        XCTAssertEqual(EntrySorting.sorted(items, by: .newest).map(\.name), ["b", "d", "a", "c"])
        XCTAssertEqual(EntrySorting.sorted(items, by: .oldest).map(\.name), ["c", "a", "d", "b"])
        XCTAssertEqual(EntrySorting.sorted(items, by: .size).map(\.name), ["b", "c", "a", "d"])
    }

    func testSearch() {
        XCTAssertTrue(EntrySorting.matches(name: "Urlaub_Mallorca_2024.jpg", query: "mallorca 2024"))
        XCTAssertTrue(EntrySorting.matches(name: "Café.png", query: "cafe"))
        XCTAssertFalse(EntrySorting.matches(name: "IMG_1.jpg", query: "urlaub"))
        XCTAssertTrue(EntrySorting.matches(name: "x", query: "  "))
    }

    func testUniqueNames() {
        XCTAssertEqual(ConflictNaming.uniqueName(for: "Foto.jpg", existing: []), "Foto.jpg")
        XCTAssertEqual(ConflictNaming.uniqueName(for: "Foto.jpg", existing: ["Foto.jpg"]), "Foto 2.jpg")
        XCTAssertEqual(ConflictNaming.uniqueName(for: "Foto.jpg", existing: ["foto.JPG", "Foto 2.jpg"]), "Foto 3.jpg")
        XCTAssertEqual(ConflictNaming.uniqueName(for: "Foto 2.jpg", existing: ["Foto 2.jpg"]), "Foto 3.jpg")
        XCTAssertEqual(ConflictNaming.uniqueName(for: "Ordner", existing: ["Ordner"]), "Ordner 2")
        XCTAssertEqual(ConflictNaming.uniqueName(for: ".nomedia", existing: [".nomedia"]), ".nomedia 2")
    }

    func testMacMetadataFilter() {
        XCTAssertTrue(HiddenFiles.isMacMetadata(".DS_Store"))
        XCTAssertTrue(HiddenFiles.isMacMetadata("._Foto.jpg"))
        XCTAssertTrue(HiddenFiles.isMacMetadata(".Spotlight-V100"))
        XCTAssertFalse(HiddenFiles.isMacMetadata(".nomedia"))
        XCTAssertFalse(HiddenFiles.isMacMetadata(".thumbnails"))
        XCTAssertFalse(HiddenFiles.isMacMetadata("Foto.jpg"))
        XCTAssertFalse(HiddenFiles.isMacMetadata("._"))
    }

    func testFileNameSanitizing() {
        XCTAssertEqual(FileNameSanitizer.androidSafe("Bericht: Q1/Q2?.pdf"), "Bericht_ Q1_Q2_.pdf")
        XCTAssertEqual(FileNameSanitizer.androidSafe("name..."), "name")
        XCTAssertEqual(FileNameSanitizer.androidSafe("  "), "Unbenannt")
        XCTAssertEqual(FileNameSanitizer.macSafe("a/b"), "a_b")
        XCTAssertEqual(FileNameSanitizer.macSafe(".."), "Unbenannt")
    }
}

final class TransferMathTests: XCTestCase {
    func testRateEstimator() {
        var r = TransferRateEstimator()
        r.update(totalBytes: 0, at: 0)
        r.update(totalBytes: 10_000_000, at: 1)
        XCTAssertEqual(r.bytesPerSecond, 10_000_000, accuracy: 1)
        r.update(totalBytes: 30_000_000, at: 2)
        XCTAssertGreaterThan(r.bytesPerSecond, 10_000_000)
        XCTAssertLessThan(r.bytesPerSecond, 20_000_000)
        let eta = r.remainingSeconds(done: 30_000_000, total: 130_000_000)
        XCTAssertNotNil(eta)
        XCTAssertGreaterThan(eta!, 0)
        // zu kurze Abstände ändern nichts
        let before = r.bytesPerSecond
        r.update(totalBytes: 99_000_000, at: 2.05)
        XCTAssertEqual(r.bytesPerSecond, before)
    }

    func testRemainingWithoutRate() {
        let r = TransferRateEstimator()
        XCTAssertNil(r.remainingSeconds(done: 0, total: 100))
        XCTAssertEqual(r.remainingSeconds(done: 100, total: 100), 0)
    }

    func testByteFormatting() {
        XCTAssertEqual(ByteFormat.string(0), "0 Byte")
        XCTAssertEqual(ByteFormat.string(999), "999 Byte")
        XCTAssertEqual(ByteFormat.string(1_500), "1,5 KB")
        XCTAssertEqual(ByteFormat.string(5_000_000_000), "5,0 GB")
        XCTAssertEqual(ByteFormat.string(123_000_000), "123 MB")
    }

    func testDurationFormatting() {
        XCTAssertEqual(DurationFormat.string(5), "5 Sek.")
        XCTAssertEqual(DurationFormat.string(125), "2 Min. 5 Sek.")
        XCTAssertEqual(DurationFormat.string(3_900), "1 Std. 5 Min.")
    }

    func testStatusFlags() {
        XCTAssertTrue(TransferStatus.failed("x").isFinished)
        XCTAssertTrue(TransferStatus.failed("x").canRetry)
        XCTAssertFalse(TransferStatus.running.isFinished)
        XCTAssertTrue(TransferStatus.running.isActive)
        XCTAssertFalse(TransferStatus.completed.canRetry)
    }

    func testVerification() {
        XCTAssertTrue(TransferVerification.sizeMatches(expected: 10, actual: 10))
        XCTAssertFalse(TransferVerification.sizeMatches(expected: 10, actual: 9))
        XCTAssertTrue(TransferVerification.sizeMatches(expected: nil, actual: 9))
    }
}
