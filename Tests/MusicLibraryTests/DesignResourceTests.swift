import XCTest
import MLCore
@testable import MusicLibrary

/// Gestaltungsquellen: Jedes in der App verwendete Symbol existiert und lässt sich zeichnen,
/// jedes Genre hat ein Symbol, Farbtöne der Themes sind vollständig.
final class DesignResourceTests: XCTestCase {
    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MusicLibrary")
    }

    /// Alle Namen aus `enum Icons` (aus dem Quelltext gelesen, damit kein Name vergessen wird).
    private func iconNames() throws -> [String: String] {
        let text = try String(contentsOf: sourceRoot.appendingPathComponent("Design/Icons.swift"), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"static let (\w+) = "([\w]+)""#)
        var names: [String: String] = [:]
        for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            names[String(text[Range(m.range(at: 1), in: text)!])] = String(text[Range(m.range(at: 2), in: text)!])
        }
        return names
    }

    func testEveryIconConstantResolvesToDrawablePaths() throws {
        let names = try iconNames()
        XCTAssertGreaterThan(names.count, 60)
        for (constant, name) in names.sorted(by: { $0.key < $1.key }) {
            guard let parsed = IconCache.shared.parsed(name) else {
                XCTFail("Icons.\(constant) → „\(name)“ fehlt in IconData")
                continue
            }
            XCTAssertFalse(parsed.parts.isEmpty, "\(name): keine Pfade")
            for part in parsed.parts {
                XCTAssertFalse(part.path.isEmpty, "\(name): leerer Pfad")
                let box = part.path.boundingBoxOfPath
                XCTAssertTrue(box.width > 0 || box.height > 0, "\(name): Pfad ohne Ausdehnung")
                XCTAssertLessThanOrEqual(box.maxX, parsed.width * 1.25, "\(name) ragt rechts heraus")
                XCTAssertLessThanOrEqual(box.maxY, parsed.height * 1.25, "\(name) ragt unten heraus")
            }
        }
    }

    func testIconLiteralsInViewsExist() throws {
        // Symbolnamen, die direkt als Text in Ansichten stehen (z. B. Icon("genre_rock"))
        let files = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" && $0.lastPathComponent != "IconData.swift" }
        let regex = try NSRegularExpression(pattern: #"Icon\("([a-z0-9_]+)""#)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let name = String(text[Range(m.range(at: 1), in: text)!])
                XCTAssertNotNil(IconData.spec(name), "\(file.lastPathComponent): Symbol „\(name)“ fehlt")
            }
        }
    }

    func testEveryGenreCategoryHasIcon() {
        for category in GenreCategory.allCases {
            let name = GenreStyle.icon(category)
            XCTAssertNotNil(IconData.spec(name), "\(category): Symbol „\(name)“ fehlt")
        }
    }

    func testPalettesDifferBetweenLightAndDark() {
        let light = MusicColors.light
        let dark = MusicColors.darkPalette
        XCTAssertNotEqual(light.background, dark.background)
        XCTAssertNotEqual(light.textPrimary, dark.textPrimary)
        XCTAssertNotEqual(light.accentText, dark.accentText)
    }
}
