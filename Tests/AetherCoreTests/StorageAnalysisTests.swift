import XCTest
@testable import AetherCore

final class FileCategoryTests: XCTestCase {
    func testClassification() {
        XCTAssertEqual(FileCategory.classify(fileName: "Urlaub.HEIC"), .images)
        XCTAssertEqual(FileCategory.classify(fileName: "film.mov"), .videos)
        XCTAssertEqual(FileCategory.classify(fileName: "song.flac"), .audio)
        XCTAssertEqual(FileCategory.classify(fileName: "Vertrag.pdf"), .documents)
        XCTAssertEqual(FileCategory.classify(fileName: "backup.tar.gz"), .archives)
        XCTAssertEqual(FileCategory.classify(fileName: "Xcode.app"), .applications)
        XCTAssertEqual(FileCategory.classify(fileName: "main.swift"), .code)
        XCTAssertEqual(FileCategory.classify(fileName: "README"), .other)
        XCTAssertEqual(FileCategory.classify(fileName: ".zshrc"), .other)
        XCTAssertEqual(FileCategory.classify(fileName: "name."), .other)
    }
}

final class StorageTallyTests: XCTestCase {
    private func file(_ path: String, _ size: Int64, logical: Int64? = nil, inode: UInt64 = 0, device: UInt64 = 1,
                      package: Bool = false) -> ScannedFile {
        ScannedFile(path: path, size: size, logicalSize: logical ?? size, modified: nil,
                    category: FileCategory.classify(fileName: String(path.split(separator: "/").last ?? "")), isPackage: package,
                    device: device, inode: inode)
    }

    func testTopLevelComponent() {
        XCTAssertEqual(StorageTally.topLevelComponent(path: "/Users/a/Movies/x.mov", rootPath: "/Users/a"), "Movies")
        XCTAssertNil(StorageTally.topLevelComponent(path: "/Users/a/x.mov", rootPath: "/Users/a"))
        XCTAssertNil(StorageTally.topLevelComponent(path: "/Other/x.mov", rootPath: "/Users/a"))
        XCTAssertEqual(StorageTally.topLevelComponent(path: "/Library/Caches/y", rootPath: "/"), "Library")
        XCTAssertEqual(StorageTally.topLevelComponent(path: "/Users/a/Movies/x.mov", rootPath: "/Users/a/"), "Movies")
    }

    func testTotalsFoldersCategoriesAndRetention() {
        var tally = StorageTally(rootPath: "/r", retainThreshold: 1_000_000)
        tally.add(file("/r/Movies/a.mov", 5_000_000))
        tally.add(file("/r/Movies/b.mov", 3_000_000))
        tally.add(file("/r/Docs/c.pdf", 200))
        tally.add(file("/r/loose.txt", 100))
        tally.addFolder()
        tally.addFolder()
        XCTAssertEqual(tally.totalSize, 8_000_300)
        XCTAssertEqual(tally.fileCount, 4)
        XCTAssertEqual(tally.folderCount, 2)
        XCTAssertEqual(tally.retained.map(\.path).sorted(), ["/r/Movies/a.mov", "/r/Movies/b.mov"])

        let folders = tally.folders()
        XCTAssertEqual(folders.map(\.name), ["Movies", "Docs", ""])
        XCTAssertEqual(folders[0].size, 8_000_000)
        XCTAssertEqual(folders[0].files, 2)
        XCTAssertEqual(folders[0].path, "/r/Movies")
        XCTAssertTrue(folders[2].isLooseFiles)

        let categories = tally.categories()
        XCTAssertEqual(categories.first?.category, .videos)
        XCTAssertEqual(categories.first?.size, 8_000_000)
        XCTAssertEqual(categories.reduce(0) { $0 + $1.files }, 4)
    }

    func testLargestAndThresholds() {
        let files = [file("/r/a", 50_000_000), file("/r/b", 700_000_000), file("/r/c", 2_000_000_000)]
        XCTAssertEqual(StorageAnalysis.largest(files, minimum: SizeThreshold.mb100.bytes).map(\.path), ["/r/c", "/r/b"])
        XCTAssertEqual(StorageAnalysis.largest(files, minimum: SizeThreshold.gb1.bytes).map(\.path), ["/r/c"])
        XCTAssertEqual(StorageAnalysis.largest(files, minimum: 1, limit: 1).map(\.path), ["/r/c"])
        XCTAssertEqual(SizeThreshold.custom(megabytes: 0).bytes, 1_000_000)
        XCTAssertEqual(SizeThreshold.custom(megabytes: 250).bytes, 250_000_000)
    }

    func testDuplicateCandidatesSkipHardLinksAndPackages() {
        let files = [
            file("/r/a.bin", 2_000_000, inode: 10),
            file("/r/b.bin", 2_000_000, inode: 11),
            file("/r/hardlink.bin", 2_000_000, inode: 10),
            file("/r/c.bin", 3_000_000, inode: 12),
            file("/r/App1.app", 4_000_000, inode: 13, package: true),
            file("/r/App2.app", 4_000_000, inode: 14, package: true),
            file("/r/small1", 10, inode: 15),
            file("/r/small2", 10, inode: 16),
        ]
        let candidates = DuplicateFinder.candidates(files, minimumSize: 1_000_000)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].map(\.path), ["/r/a.bin", "/r/b.bin"])
    }

    func testGroupsFromHashesAndRemoval() {
        let a = file("/r/a", 2_000_000, inode: 1)
        let b = file("/r/b", 2_000_000, inode: 2)
        let c = file("/r/c", 2_000_000, inode: 3)
        let groups = DuplicateFinder.groups(candidates: [[a, b, c]], hashes: ["/r/a": "x", "/r/b": "x", "/r/c": "y"],
                                            mayShareBlocks: ["/r/b"])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].files.map(\.path), ["/r/a", "/r/b"])
        XCTAssertEqual(groups[0].reclaimable, 2_000_000)
        XCTAssertEqual(groups[0].mayShareBlocks, ["/r/b"])
        XCTAssertEqual(DuplicateFinder.fullySelected(groups, selection: ["/r/a", "/r/b"]).count, 1)
        XCTAssertEqual(DuplicateFinder.fullySelected(groups, selection: ["/r/a"]).count, 0)
        XCTAssertTrue(DuplicateFinder.removing(["/r/a"], from: groups).isEmpty)
        // Nicht lesbare Datei (ohne Prüfsumme) fällt heraus
        XCTAssertTrue(DuplicateFinder.groups(candidates: [[a, b]], hashes: ["/r/a": "x"]).isEmpty)
    }

    func testResultRemoval() {
        let a = file("/r/a", 2_000_000, inode: 1)
        let b = file("/r/b", 2_000_000, inode: 2)
        var result = StorageScanResult(rootPath: "/r", totalSize: 4_000_000, fileCount: 2, folderCount: 0, unreadableCount: 0,
                                       unreadableSamples: [], files: [a, b], folders: [], categories: [],
                                       duplicates: [DuplicateGroup(hash: "x", size: 2_000_000, files: [a, b])],
                                       duplicatesChecked: true, cancelled: false, finished: Date(), skippedOtherVolumes: 0)
        result.remove(paths: ["/r/b"])
        XCTAssertEqual(result.files.map(\.path), ["/r/a"])
        XCTAssertTrue(result.duplicates.isEmpty)
        XCTAssertEqual(result.totalSize, 4_000_000, "Summen bleiben die der Messung")
    }

    func testScannedFileNames() {
        let f = file("/Users/a/Movies/x.mov", 1)
        XCTAssertEqual(f.name, "x.mov")
        XCTAssertEqual(f.parentPath, "/Users/a/Movies")
        XCTAssertEqual(file("/x", 1).parentPath, "/")
    }
}

final class NVMeHealthTests: XCTestCase {
    private func log() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 512)
        bytes[0] = 0b0000_0101            // Reserve unter Schwelle + Zuverlässigkeit
        let kelvin = 273 + 38             // 37,85 °C
        bytes[1] = UInt8(kelvin & 0xFF)
        bytes[2] = UInt8(kelvin >> 8)
        bytes[3] = 100                    // Reserve
        bytes[4] = 10                     // Schwelle
        bytes[5] = 3                      // Abnutzung
        bytes[32] = 0x10                  // gelesen: 0x2710 = 10 000 Einheiten
        bytes[33] = 0x27
        bytes[48] = 0x20                  // geschrieben: 0x4E20 = 20 000 Einheiten
        bytes[49] = 0x4E
        bytes[112] = 250                  // Einschaltvorgänge
        bytes[128] = 0xE8                 // Betriebsstunden 1 000
        bytes[129] = 0x03
        bytes[144] = 7                    // unsichere Abschaltungen
        return bytes
    }

    func testDecode() throws {
        let health = try XCTUnwrap(NVMeHealth.decode(log()))
        XCTAssertEqual(health.temperatureCelsius ?? 0, 37.85, accuracy: 0.001)
        XCTAssertEqual(health.availableSpare, 100)
        XCTAssertEqual(health.availableSpareThreshold, 10)
        XCTAssertEqual(health.percentageUsed, 3)
        XCTAssertEqual(health.bytesRead, 10_000 * 512_000)
        XCTAssertEqual(health.bytesWritten, 20_000 * 512_000)
        XCTAssertEqual(health.powerCycles, 250)
        XCTAssertEqual(health.powerOnHours, 1_000)
        XCTAssertEqual(health.unsafeShutdowns, 7)
        XCTAssertEqual(health.mediaErrors, 0)
        XCTAssertEqual(health.warnings, [.spareBelowThreshold, .reliabilityDegraded])
        XCTAssertTrue(health.isPlausible)
    }

    func testEmptyShortOrImplausibleLogs() throws {
        XCTAssertNil(NVMeHealth.decode([UInt8](repeating: 0, count: 512)))
        XCTAssertNil(NVMeHealth.decode([1, 2, 3]))
        var bad = log()
        bad[3] = 200 // Reserve > 100 % ist nicht spezifikationsgemäß
        XCTAssertNil(NVMeHealth.decode(bad))
        var noTemperature = log()
        noTemperature[1] = 0
        noTemperature[2] = 0
        XCTAssertNil(try XCTUnwrap(NVMeHealth.decode(noTemperature)).temperatureCelsius)
    }

    func testUInt128() {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[8] = 1 // 2^64
        XCTAssertEqual(NVMeHealth.uint128(bytes, at: 0), 18_446_744_073_709_551_616.0)
        XCTAssertEqual(NVMeHealth.uint128(bytes, at: 4), 0, "außerhalb des Puffers → 0")
    }
}

final class CleanupKindTests: XCTestCase {
    func testRelativePathsAreInsideHome() {
        for kind in CleanupKind.allCases {
            XCTAssertFalse(kind.relativePath.hasPrefix("/"))
            XCTAssertFalse(kind.relativePath.contains(".."))
        }
        XCTAssertEqual(CleanupKind.xcodeDerivedData.relativePath, "Library/Developer/Xcode/DerivedData")
    }
}
