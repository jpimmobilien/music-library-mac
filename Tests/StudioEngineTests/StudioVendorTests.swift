import Foundation
import XCTest
@testable import StudioEngine

/// Zusatzprüfungen, die nur auf ausdrücklichen Wunsch laufen (Netzzugang bzw. lange Laufzeit):
/// - `ML_VERIFY_VENDOR=1` oder Zeile „vendor“ in `Tests/StudioEngineTests/.ci-extra`: `scripts/verify_vendor.sh`
/// - `ML_UNIVERSAL_BUILD=1` oder Zeile „universal“ in `.ci-extra`: Release-Build von StudioEngine (mit CLame/CFLAC)
///   für arm64-apple-macosx13.0 und x86_64-apple-macosx13.0, Architektur der Objektdateien prüfen
final class StudioVendorTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func enabled(_ env: String, _ word: String) -> Bool {
        if ProcessInfo.processInfo.environment[env] == "1" { return true }
        let marker = root.appendingPathComponent("Tests/StudioEngineTests/.ci-extra")
        guard let text = try? String(contentsOf: marker, encoding: .utf8) else { return false }
        return text.split(whereSeparator: \.isNewline).contains { $0.trimmingCharacters(in: .whitespaces) == word }
    }

    func testEncoderVersions() {
        TS.log("Encoder: \(EncoderVersions.lame), \(EncoderVersions.flac)")
        XCTAssertTrue(EncoderVersions.lame.contains("3.100"))
        XCTAssertTrue(EncoderVersions.flac.contains("1.5.0"))
    }

    func testVerifyVendoredSources() throws {
        guard Self.enabled("ML_VERIFY_VENDOR", "vendor") else { throw XCTSkip("ML_VERIFY_VENDOR nicht gesetzt") }
        let r = TS.run("/bin/bash", [Self.root.appendingPathComponent("scripts/verify_vendor.sh").path], timeout: 600)
        for line in (r.out + r.err).split(separator: "\n") { TS.log("verify_vendor: \(line)") }
        XCTAssertEqual(r.status, 0, "verify_vendor.sh meldet Abweichungen")
    }

    func testUniversalReleaseBuild() throws {
        guard Self.enabled("ML_UNIVERSAL_BUILD", "universal") else { throw XCTSkip("ML_UNIVERSAL_BUILD nicht gesetzt") }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("studio-universal-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: scratch) }
        for arch in ["arm64", "x86_64"] {
            let triple = "\(arch)-apple-macosx13.0"
            let t0 = Date()
            let r = TS.run("/usr/bin/xcrun", ["swift", "build", "-c", "release", "--triple", triple, "--target", "StudioEngine",
                                              "--package-path", Self.root.path, "--scratch-path", scratch.appendingPathComponent(arch).path],
                           timeout: 2400)
            let secs = Date().timeIntervalSince(t0)
            let tail = (r.out + r.err).split(separator: "\n").suffix(5).joined(separator: " | ")
            TS.log(String(format: "Universal: swift build -c release --triple %@ --target StudioEngine → Status %d in %.0f s: %@", triple, r.status, secs, tail))
            XCTAssertEqual(r.status, 0, "Release-Build für \(triple)")
            guard r.status == 0 else { continue }
            // Architektur der übersetzten C-Ziele prüfen
            let find = TS.run("/usr/bin/find", [scratch.appendingPathComponent(arch).path, "-name", "*.o", "-path", "*CLame.build*", "-name", "lame.c.o"])
            let find2 = TS.run("/usr/bin/find", [scratch.appendingPathComponent(arch).path, "-name", "stream_encoder.c.o", "-path", "*CFLAC.build*"])
            for path in (find.out + find2.out).split(separator: "\n").map(String.init) where !path.isEmpty {
                let lipo = TS.run("/usr/bin/lipo", ["-archs", path])
                TS.log("Universal: \(URL(fileURLWithPath: path).lastPathComponent) → \(lipo.out.trimmingCharacters(in: .whitespacesAndNewlines))")
                XCTAssertEqual(lipo.out.trimmingCharacters(in: .whitespacesAndNewlines), arch)
            }
        }
    }
}
