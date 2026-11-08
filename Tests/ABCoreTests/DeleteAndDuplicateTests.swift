import XCTest
@testable import ABCore

final class DeleteTreeTests: XCTestCase {
    private func device() -> SimulatedMTPDevice {
        let d = SimulatedMTPDevice()
        d.objects[1] = .init(storage: 0x10001, parent: 0, name: "Urlaub", isFolder: true, data: Data())
        d.objects[2] = .init(storage: 0x10001, parent: 1, name: "a.jpg", isFolder: false, data: Data([1, 2, 3]))
        d.objects[3] = .init(storage: 0x10001, parent: 1, name: "Tag 2", isFolder: true, data: Data())
        d.objects[4] = .init(storage: 0x10001, parent: 3, name: "b.jpg", isFolder: false, data: Data([4]))
        d.objects[5] = .init(storage: 0x20001, parent: 0, name: "sd.jpg", isFolder: false, data: Data([9]))
        d.objects[6] = .init(storage: 0x10001, parent: 0, name: "einzeln.pdf", isFolder: false, data: Data([7]))
        return d
    }

    func testDeleteSingleFile() throws {
        let d = device(); let s = MTPSession(transport: d); try s.openSession()
        let r = try s.deleteTree(6, storage: 0x10001, isFolder: false)
        XCTAssertTrue(r.succeeded)
        XCTAssertNil(d.objects[6])
    }

    func testDeleteFileOnSDCard() throws {
        let d = device(); let s = MTPSession(transport: d); try s.openSession()
        XCTAssertTrue(try s.deleteTree(5, storage: 0x20001, isFolder: false).succeeded)
        XCTAssertNil(d.objects[5])
    }

    func testDeleteFolderRecursivelyAndroidStyle() throws {
        let d = device(); let s = MTPSession(transport: d); try s.openSession()
        let r = try s.deleteTree(1, storage: 0x10001, isFolder: true)
        XCTAssertTrue(r.succeeded)
        XCTAssertNil(d.objects[1]); XCTAssertNil(d.objects[2]); XCTAssertNil(d.objects[3]); XCTAssertNil(d.objects[4])
        XCTAssertNotNil(d.objects[6])
    }

    func testDeleteFolderOnDeviceThatOnlyDeletesEmptyFolders() throws {
        let d = device(); d.refuseNonEmptyFolderDelete = true
        let s = MTPSession(transport: d); try s.openSession()
        let r = try s.deleteTree(1, storage: 0x10001, isFolder: true)
        XCTAssertTrue(r.succeeded)
        XCTAssertTrue(d.objects.keys.allSatisfy { $0 == 5 || $0 == 6 })
    }

    func testProtectedFileIsReportedOthersDeleted() throws {
        let d = device(); d.refuseNonEmptyFolderDelete = true; d.protectedHandles = [4]
        let s = MTPSession(transport: d); try s.openSession()
        let r = try s.deleteTree(1, storage: 0x10001, isFolder: true)
        XCTAssertFalse(r.succeeded)
        XCTAssertEqual(r.failed[4], PTPResponse.accessDenied.rawValue)
        XCTAssertNil(d.objects[2])
        XCTAssertNotNil(d.objects[4])
        XCTAssertNotNil(d.objects[1], "Ordner mit geschütztem Inhalt bleibt bestehen")
        // Sitzung bleibt benutzbar
        XCTAssertEqual(try s.storageIDs().count, 2)
    }

    func testDeleteMissingObjectIsNotAnError() throws {
        let d = device(); let s = MTPSession(transport: d); try s.openSession()
        XCTAssertTrue(try s.deleteTree(999, storage: 0x10001, isFolder: false).succeeded)
    }

    func testCancelledBeforeDeleteThrows() throws {
        let d = device(); let s = MTPSession(transport: d); try s.openSession()
        XCTAssertThrowsError(try s.deleteTree(6, storage: 0x10001, isFolder: false, cancelled: { true }))
        XCTAssertNotNil(d.objects[6])
    }

    func testDisconnectDuringDeleteThrows() throws {
        final class DeadTransport: MTPBulkTransport {
            let maxPacketSize = 512
            let bufferSize = 4096
            func read(maxLength: Int, timeout: TimeInterval) throws -> Data { throw MTPError.disconnected }
            func write(_ data: Data, timeout: TimeInterval) throws { throw MTPError.disconnected }
            func cancelTransaction(_ transactionID: UInt32) throws {}
            func clearStalls() {}
        }
        let s = MTPSession(transport: DeadTransport())
        XCTAssertThrowsError(try s.deleteTree(1, storage: 1, isFolder: false)) { e in
            XCTAssertEqual(e as? MTPError, .disconnected)
        }
    }
}

/// Speicherdaten als Lesequelle; zählt Zugriffe.
struct UnreadableError: Error {}
struct LostConnectionError: Error {}

final class MemoryReader: DuplicateContentReader, @unchecked Sendable {
    let contents: [String: Data]
    let supportsRanges: Bool
    var unreadable: Set<String> = []
    var disconnectOn: Set<String> = []
    private let lock = NSLock()
    private(set) var rangeReads: [String] = []
    private(set) var fullReads: [String] = []

    init(_ contents: [String: Data], ranges: Bool = true) {
        self.contents = contents
        self.supportsRanges = ranges
    }

    func read(_ file: DuplicateFile, offset: UInt64, length: UInt32) async throws -> Data {
        lock.lock(); rangeReads.append(file.id); lock.unlock()
        if unreadable.contains(file.id) { throw UnreadableError() }
        if disconnectOn.contains(file.id) { throw LostConnectionError() }
        let d = contents[file.id]!
        let start = Int(offset), end = min(d.count, start + Int(length))
        return d.subdata(in: start..<end)
    }

    func stream(_ file: DuplicateFile, chunk: @escaping @Sendable (Data) -> Void) async throws {
        lock.lock(); fullReads.append(file.id); lock.unlock()
        if unreadable.contains(file.id) { throw UnreadableError() }
        if disconnectOn.contains(file.id) { throw LostConnectionError() }
        let d = contents[file.id]!
        var i = 0
        while i < d.count { let e = min(d.count, i + 100_000); chunk(d.subdata(in: i..<e)); i = e }
    }

    func isFatal(_ error: Error) -> Bool { error is LostConnectionError }
}

final class DuplicateFinderTests: XCTestCase {
    private var nextHandle: UInt32 = 1

    private func file(_ name: String, _ path: [String], storage: UInt32 = 0x10001, size: Int, date: Double = 0, w: UInt32 = 0, h: UInt32 = 0) -> DuplicateFile {
        nextHandle += 1
        let e = DeviceEntry(handle: nextHandle, storageID: storage, parent: 0, name: name, isFolder: false, size: UInt64(size),
                            format: 0x3801, modified: Date(timeIntervalSince1970: 1_700_000_000 + date), imageWidth: w, imageHeight: h)
        return DuplicateFile(entry: e, path: path, storageName: storage == 0x10001 ? "Intern" : "SD-Karte")
    }

    private func bytes(_ seed: UInt8, _ count: Int) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ Int(seed) &* 13) })
    }

    private func run(_ files: [DuplicateFile], _ data: [String: Data], ranges: Bool = true) async throws -> ([DuplicateGroup], MemoryReader) {
        let reader = MemoryReader(data, ranges: ranges)
        let groups = try await ExactDuplicateFinder().find(in: files, reader: reader, progress: { _ in }, isCancelled: { false })
        return (groups, reader)
    }

    func testIdenticalContentDifferentNamesFoldersAndStorages() async throws {
        let a = file("IMG_001.jpg", ["DCIM", "Camera"], size: 300_000, date: 0)
        let b = file("Photo_123.jpg", ["Pictures", "WhatsApp"], size: 300_000, date: 50)
        let c = file("Kopie.jpg", ["DCIM"], storage: 0x20001, size: 300_000, date: 90)
        let content = bytes(1, 300_000)
        let (groups, _) = try await run([a, b, c], [a.id: content, b.id: content, c.id: content])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].files.map(\.id)), [a.id, b.id, c.id])
        XCTAssertEqual(groups[0].kind, .identical)
        XCTAssertEqual(groups[0].suggestedKeep, a.id, "Kameraordner mit Originalname bevorzugt")
        XCTAssertEqual(groups[0].reclaimableBytes, 600_000)
    }

    func testSameNameSameContentIsDuplicate() async throws {
        let a = file("a.pdf", ["Download"], size: 5000)
        let b = file("a.pdf", ["Documents"], size: 5000)
        let d = bytes(3, 5000)
        let (groups, _) = try await run([a, b], [a.id: d, b.id: d])
        XCTAssertEqual(groups.count, 1)
    }

    func testSameSizeDifferentContentIsNotDuplicate() async throws {
        let a = file("x.jpg", ["DCIM"], size: 10_000)
        let b = file("x.jpg", ["Pictures"], size: 10_000)
        let (groups, _) = try await run([a, b], [a.id: bytes(1, 10_000), b.id: bytes(2, 10_000)])
        XCTAssertTrue(groups.isEmpty, "gleicher Name und gleiche Größe genügen nicht")
    }

    func testSameEdgesDifferentMiddleNeedsFullHash() async throws {
        let size = 1_000_000
        var d1 = bytes(5, size)
        var d2 = d1
        d2[size / 2] ^= 0xFF
        let a = file("v1.mp4", ["Movies"], size: size)
        let b = file("v2.mp4", ["Movies"], size: size)
        let (groups, reader) = try await run([a, b], [a.id: d1, b.id: d2])
        XCTAssertTrue(groups.isEmpty)
        XCTAssertEqual(Set(reader.fullReads), [a.id, b.id], "nur bei gleichem Fingerabdruck wird vollständig gelesen")
        d1[0] = 0
        _ = d1
    }

    func testUniqueSizesAreNeverRead() async throws {
        let a = file("a.jpg", ["DCIM"], size: 1000)
        let b = file("b.jpg", ["DCIM"], size: 2000)
        let c = file("c.jpg", ["DCIM"], size: 3000)
        let (groups, reader) = try await run([a, b, c], [a.id: bytes(1, 1000), b.id: bytes(1, 2000), c.id: bytes(1, 3000)])
        XCTAssertTrue(groups.isEmpty)
        XCTAssertTrue(reader.rangeReads.isEmpty && reader.fullReads.isEmpty)
    }

    func testDifferentHeadsSkipFullHash() async throws {
        let size = 2_000_000
        let a = file("a.mov", ["Movies"], size: size)
        let b = file("b.mov", ["Movies"], size: size)
        let (groups, reader) = try await run([a, b], [a.id: bytes(1, size), b.id: bytes(2, size)])
        XCTAssertTrue(groups.isEmpty)
        XCTAssertTrue(reader.fullReads.isEmpty, "verschiedener Anfang → kein vollständiges Lesen nötig")
    }

    func testLargeIdenticalVideosWithoutRangeSupport() async throws {
        let size = 3_000_000
        let d = bytes(9, size)
        let a = file("clip.mp4", ["DCIM", "Camera"], size: size)
        let b = file("clip(1).mp4", ["Download"], size: size)
        let (groups, _) = try await run([a, b], [a.id: d, b.id: d], ranges: false)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].suggestedKeep, a.id)
    }

    func testEmptyFilesAndFoldersIgnored() async throws {
        let a = file("leer1.txt", ["Download"], size: 0)
        let b = file("leer2.txt", ["Download"], size: 0)
        let (groups, _) = try await run([a, b], [a.id: Data(), b.id: Data()])
        XCTAssertTrue(groups.isEmpty)
    }

    func testThousandsOfFilesGrouping() async throws {
        var files: [DuplicateFile] = []
        var data: [String: Data] = [:]
        for i in 0..<5000 {
            let f = file("f\(i).jpg", ["DCIM"], size: 1000 + i)
            files.append(f)
            data[f.id] = bytes(UInt8(i % 250), 1000 + i)
        }
        // 10 echte Duplikate hinzufügen
        for i in 0..<10 {
            let orig = files[i * 100]
            let copy = file("copy\(i).jpg", ["Pictures"], size: Int(orig.entry.size))
            files.append(copy)
            data[copy.id] = data[orig.id]
        }
        let start = Date()
        let (groups, reader) = try await run(files, data)
        XCTAssertEqual(groups.count, 10)
        XCTAssertEqual(reader.rangeReads.count, 20, "nur Dateien mit gleicher Größe werden gelesen")
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }

    func testUnreadableFileIsSkippedNotGrouped() async throws {
        let a = file("a.jpg", ["DCIM"], size: 300_000)
        let b = file("b.jpg", ["DCIM"], size: 300_000)
        let c = file("c.jpg", ["Pictures"], size: 300_000)
        let content = bytes(4, 300_000)
        let reader = MemoryReader([a.id: content, b.id: content, c.id: content])
        reader.unreadable = [c.id]
        var last = DuplicateScanProgress()
        let lock = NSLock()
        let groups = try await ExactDuplicateFinder().find(in: [a, b, c], reader: reader, progress: { p in lock.lock(); last = p; lock.unlock() }, isCancelled: { false })
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].files.map(\.id)), [a.id, b.id], "Nicht lesbare Datei darf nie als Duplikat gelten")
        XCTAssertEqual(last.unreadable, 1)
    }

    func testDisconnectDuringScanAborts() async {
        let a = file("a.jpg", ["DCIM"], size: 300_000)
        let b = file("b.jpg", ["DCIM"], size: 300_000)
        let content = bytes(5, 300_000)
        let reader = MemoryReader([a.id: content, b.id: content])
        reader.disconnectOn = [b.id]
        do {
            _ = try await ExactDuplicateFinder().find(in: [a, b], reader: reader, progress: { _ in }, isCancelled: { false })
            XCTFail("Trennung muss die Suche abbrechen")
        } catch {
            XCTAssertTrue(error is LostConnectionError)
        }
    }

    func testCancellation() async {
        let a = file("a", ["x"], size: 100), b = file("b", ["x"], size: 100)
        let reader = MemoryReader([a.id: bytes(1, 100), b.id: bytes(1, 100)])
        do {
            _ = try await ExactDuplicateFinder().find(in: [a, b], reader: reader, progress: { _ in }, isCancelled: { true })
            XCTFail("sollte abbrechen")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testKeepSuggestionPrefersHigherResolutionForSimilar() {
        let small = file("IMG_1.jpg", ["DCIM", "Camera"], size: 200_000, w: 800, h: 600)
        let big = file("IMG_1_full.jpg", ["Pictures"], size: 4_000_000, w: 4000, h: 3000)
        let g = DuplicateGroup(id: "s", kind: .similar, files: [small, big], checksum: nil)
        XCTAssertEqual(g.suggestedKeep, big.id)
        XCTAssertTrue(g.suggestionReason.contains("Auflösung"))
    }

    func testSelectionAlwaysKeepsOne() {
        let a = file("a", ["DCIM"], size: 10), b = file("b", ["DCIM"], size: 10)
        let g = DuplicateGroup(id: "g", kind: .identical, files: [a, b], checksum: "x")
        let sel = DuplicateSelection.suggested(for: g)
        XCTAssertEqual(sel.count, 1)
        XCTAssertTrue(DuplicateSelection.keepsAtLeastOne(sel, in: g))
        XCTAssertFalse(DuplicateSelection.keepsAtLeastOne([a.id, b.id], in: g))
    }
}

final class PerceptualHashTests: XCTestCase {
    private func gradient(_ shift: Int, noise: Int = 0) -> [UInt8] {
        (0..<72).map { i in
            let row = i / 9, col = i % 9
            let v = (col * 25 + row * 3 + shift + ((i * 31 + noise) % 3)) % 256
            return UInt8(v)
        }
    }

    func testSameImageDifferentResolutionIsSimilar() {
        // gleiche Struktur, leicht anderes Rauschen (andere Kompression/Auflösung)
        let a = PerceptualHash.dHash(gray9x8: gradient(0))!
        let b = PerceptualHash.dHash(gray9x8: gradient(1, noise: 1))!
        XCTAssertLessThanOrEqual(PerceptualHash.distance(a, b), 8)
    }

    func testDifferentImagesAreNotSimilar() {
        let a = PerceptualHash.dHash(gray9x8: gradient(0))!
        let reversed = Array(gradient(0).reversed())
        let b = PerceptualHash.dHash(gray9x8: reversed)!
        XCTAssertGreaterThan(PerceptualHash.distance(a, b), 20)
    }

    func testClusteringSeparatesGroups() {
        let items: [(id: String, hash: UInt64)] = [
            ("a", 0x0F0F_0F0F_0F0F_0F0F), ("b", 0x0F0F_0F0F_0F0F_0F0E), ("c", 0xF0F0_F0F0_F0F0_F0F0),
            ("d", 0xF0F0_F0F0_F0F0_F0F1), ("e", 0x3333_3333_CCCC_CCCC), ("blank", 0),
        ]
        let groups = PerceptualHash.cluster(items, threshold: 4).map { Set($0) }
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.contains(["a", "b"]))
        XCTAssertTrue(groups.contains(["c", "d"]))
    }

    func testInvalidInput() {
        XCTAssertNil(PerceptualHash.dHash(gray9x8: [1, 2, 3]))
    }
}

final class LetterboxTests: XCTestCase {
    private func image(width: Int, height: Int, content: (Int, Int) -> UInt8) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height { for x in 0..<width { px[y * width + x] = content(x, y) } }
        return px
    }

    func testPillarboxIsCropped() {
        // 160×120 mit Hochformatbild in der Mitte (Balken links/rechts je 40 px)
        let px = image(width: 160, height: 120) { x, _ in (40..<120).contains(x) ? 140 : 0 }
        XCTAssertEqual(Letterbox.contentRect(gray: px, width: 160, height: 120), .init(x: 40, y: 0, width: 80, height: 120))
    }

    func testLetterboxIsCropped() {
        let px = image(width: 120, height: 160) { _, y in (30..<130).contains(y) ? 90 : 5 }
        XCTAssertEqual(Letterbox.contentRect(gray: px, width: 120, height: 160), .init(x: 0, y: 30, width: 120, height: 100))
    }

    func testDarkSkyIsNotCropped() {
        // Dunkler Himmel oben, kein Balken unten → asymmetrisch → nicht abschneiden
        let px = image(width: 160, height: 120) { _, y in y < 50 ? 8 : 120 }
        XCTAssertNil(Letterbox.contentRect(gray: px, width: 160, height: 120))
    }

    func testBlackImageIsNotCropped() {
        let px = [UInt8](repeating: 0, count: 160 * 120)
        XCTAssertNil(Letterbox.contentRect(gray: px, width: 160, height: 120))
    }

    func testNoBars() {
        let px = image(width: 160, height: 120) { x, y in UInt8((x + y) % 200 + 30) }
        XCTAssertNil(Letterbox.contentRect(gray: px, width: 160, height: 120))
    }
}

final class BatteryLevelTests: XCTestCase {
    func testBatteryLevelIsRead() throws {
        let d = SimulatedMTPDevice(); d.batteryLevel = 64
        let s = MTPSession(transport: d); try s.openSession()
        XCTAssertEqual(try s.batteryLevel(), 64)
    }

    func testBatteryLevelUnsupportedThrowsResponse() throws {
        let d = SimulatedMTPDevice(); d.batteryLevel = nil
        let s = MTPSession(transport: d); try s.openSession()
        XCTAssertThrowsError(try s.batteryLevel())
        // Sitzung bleibt danach nutzbar
        XCTAssertFalse(try s.storageIDs().isEmpty)
    }
}
