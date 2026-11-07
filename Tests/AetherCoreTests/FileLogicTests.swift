import XCTest
@testable import AetherCore

final class FileNamingTests: XCTestCase {
    func testSplit() {
        XCTAssertEqual(FileNaming.split("Bericht.final.pdf").base, "Bericht.final")
        XCTAssertEqual(FileNaming.split("Bericht.final.pdf").ext, "pdf")
        XCTAssertEqual(FileNaming.split(".zshrc").ext, "")
        XCTAssertEqual(FileNaming.split("Ordner.v2", isDirectory: true).ext, "")
        XCTAssertEqual(FileNaming.split("ende.").ext, "")
    }

    func testUniqueName() {
        XCTAssertEqual(FileNaming.uniqueName(for: "a.txt", existing: []), "a.txt")
        XCTAssertEqual(FileNaming.uniqueName(for: "a.txt", existing: ["A.TXT"]), "a 2.txt")
        XCTAssertEqual(FileNaming.uniqueName(for: "a.txt", existing: ["a.txt", "a 2.txt"]), "a 3.txt")
        XCTAssertEqual(FileNaming.uniqueName(for: "a 2.txt", existing: ["a 2.txt"]), "a 3.txt")
        XCTAssertEqual(FileNaming.uniqueName(for: "Projekt.v1", existing: ["Projekt.v1"], isDirectory: true), "Projekt.v1 2")
    }

    func testValidate() {
        XCTAssertNil(FileNaming.validate("Notizen.txt"))
        XCTAssertEqual(FileNaming.validate("  "), .empty)
        XCTAssertEqual(FileNaming.validate("a/b"), .containsSlash)
        XCTAssertEqual(FileNaming.validate("a:b"), .containsColon)
        XCTAssertEqual(FileNaming.validate(".."), .reserved)
        XCTAssertEqual(FileNaming.validate(String(repeating: "x", count: 256)), .tooLong)
        XCTAssertEqual(FileNaming.validate(".hidden"), .hidden)
        XCTAssertFalse(FileNaming.isBlocking(.hidden))
        XCTAssertTrue(FileNaming.isBlocking(.empty))
    }
}

final class BatchRenameTests: XCTestCase {
    private let items: [(name: String, isDirectory: Bool)] = [("IMG_001.jpg", false), ("IMG_002.jpg", false), ("Ordner", true)]

    func testReplaceKeepsExtension() {
        let plan = BatchRenamePlanner.plan(items, mode: .replace(find: "img_", with: "Urlaub ", caseSensitive: false), others: [])
        XCTAssertEqual(plan.map(\.proposed), ["Urlaub 001.jpg", "Urlaub 002.jpg", "Ordner"])
        XCTAssertTrue(plan.allSatisfy { $0.problem == nil })
        XCTAssertTrue(BatchRenamePlanner.canApply(plan))
        let caseSensitive = BatchRenamePlanner.plan(items, mode: .replace(find: "img_", with: "X", caseSensitive: true), others: [])
        XCTAssertFalse(BatchRenamePlanner.canApply(caseSensitive))
    }

    func testAddAndFormat() {
        let add = BatchRenamePlanner.plan(items, mode: .add(text: "-alt", atEnd: true), others: [])
        XCTAssertEqual(add.map(\.proposed), ["IMG_001-alt.jpg", "IMG_002-alt.jpg", "Ordner-alt"])
        let format = BatchRenamePlanner.plan(items, mode: .format(base: "Foto ", start: 9, digits: 2, atEnd: true), others: [])
        XCTAssertEqual(format.map(\.proposed), ["Foto 09.jpg", "Foto 10.jpg", "Foto 11"])
    }

    func testConflicts() {
        let duplicate = BatchRenamePlanner.plan(items, mode: .replace(find: "IMG_00", with: "", caseSensitive: true), others: [])
        XCTAssertNil(duplicate[0].problem)
        let same = BatchRenamePlanner.plan([("a.txt", false), ("b.txt", false)],
                                           mode: .format(base: "x", start: 1, digits: 1, atEnd: true), others: ["X1.TXT"])
        XCTAssertEqual(same[0].problem, .existsInFolder)
        let collide = BatchRenamePlanner.plan([("a1.txt", false), ("a2.txt", false)],
                                              mode: .replace(find: "1", with: "2", caseSensitive: true), others: [])
        XCTAssertEqual(collide[0].problem, .duplicateInBatch)
        let invalid = BatchRenamePlanner.plan([("a.txt", false)], mode: .add(text: "/", atEnd: false), others: [])
        XCTAssertEqual(invalid[0].problem, .invalidName(.containsSlash))
        XCTAssertFalse(BatchRenamePlanner.canApply(invalid))
    }
}

final class PathTests: XCTestCase {
    func testPermissions() {
        XCTAssertEqual(PosixPermissions.string(0o755), "rwxr-xr-x")
        XCTAssertEqual(PosixPermissions.string(0o640), "rw-r-----")
    }

    func testAncestorsAndInside() {
        XCTAssertEqual(PathTrail.ancestors(of: "/Users/anna/Documents/"), ["/", "/Users", "/Users/anna", "/Users/anna/Documents"])
        XCTAssertEqual(PathTrail.ancestors(of: "/"), ["/"])
        XCTAssertTrue(PathTrail.isInside("/a/b/c", folder: "/a/b"))
        XCTAssertTrue(PathTrail.isInside("/a/b", folder: "/a/b"))
        XCTAssertFalse(PathTrail.isInside("/a/bc", folder: "/a/b"))
    }
}
