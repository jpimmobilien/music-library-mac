import XCTest
@testable import MLCore

/// Portierung von `cover/CoverPaletteTest.kt` (plus exakte Sollwerte der Kotlin-Fassung).
final class CoverPaletteTests: XCTestCase {

    private func rgb(_ r: UInt32, _ g: UInt32, _ b: UInt32) -> UInt32 { 0xFF00_0000 | r << 16 | g << 8 | b }

    private func hue(_ c: UInt32) -> Float {
        let r = Float(c >> 16 & 0xFF) / 255, g = Float(c >> 8 & 0xFF) / 255, b = Float(c & 0xFF) / 255
        let mx = max(r, g, b), mn = min(r, g, b)
        if mx == mn { return -1 }
        let d = mx - mn
        if mx == r { return ((g - b) / d + (g < b ? 6 : 0)) * 60 }
        if mx == g { return ((b - r) / d + 2) * 60 }
        return ((r - g) / d + 4) * 60
    }

    private func pixels(_ f: (Int) -> UInt32) -> [UInt32] { (0..<1024).map(f) }

    func testBlauesCover_ergibtBlauenHintergrund() {
        let px = pixels { $0 % 7 == 0 ? self.rgb(240, 240, 240) : self.rgb(30, 70, 200) }
        let p = CoverPalette.from(pixels: px, width: 32, height: 32)
        XCTAssertEqual(hue(p.top), 225, accuracy: 20)
        XCTAssertGreaterThanOrEqual(CoverPalette.contrastWithWhite(p.top), 7.0)
        XCTAssertGreaterThanOrEqual(CoverPalette.contrastWithWhite(p.bottom), 7.0)
        XCTAssertEqual(p, CoverPalette(top: 0xFF19_2056, bottom: 0xFF0A_0C1E, glow: 0xFF23_37C7)) // wie Kotlin
    }

    func testZweiFarben_obenUndUntenVerschieden() {
        let px = pixels { $0 < 640 ? self.rgb(210, 40, 60) : self.rgb(240, 180, 30) }
        let p = CoverPalette.from(pixels: px, width: 32, height: 32)
        let h1 = hue(p.top), h2 = hue(p.bottom)
        XCTAssertTrue(h1 < 20 || h1 > 340, "oben rot (\(h1))")
        XCTAssertTrue((25...60).contains(h2), "unten gelb/orange (\(h2))")
        XCTAssertEqual(p, CoverPalette(top: 0xFF56_1920, bottom: 0xFF26_1C0C, glow: 0xFFC5_2539)) // wie Kotlin
    }

    func testGraues_oderLeeresCover_ergibtNeutral() {
        XCTAssertEqual(CoverPalette.from(pixels: pixels { _ in self.rgb(128, 128, 128) }, width: 32, height: 32), .neutral)
        XCTAssertEqual(CoverPalette.from(pixels: pixels { _ in 0 }, width: 32, height: 32), .neutral)
        XCTAssertEqual(CoverPalette.from(pixels: [], width: 0, height: 0), .neutral)
    }

    func testAuchSehrHelleCover_bleibenLesbar() {
        let p = CoverPalette.from(pixels: pixels { _ in self.rgb(255, 230, 120) }, width: 32, height: 32)
        XCTAssertGreaterThanOrEqual(CoverPalette.contrastWithWhite(p.top), 7.0)
        XCTAssertGreaterThanOrEqual(CoverPalette.contrastWithWhite(p.bottom), 7.0)
        XCTAssertGreaterThanOrEqual(CoverPalette.contrastWithWhite(CoverPalette.neutral.top), 7.0)
        XCTAssertEqual(p, CoverPalette(top: 0xFF56_4F19, bottom: 0xFF1E_1C0A, glow: 0xFFC7_B223)) // wie Kotlin
        XCTAssertEqual(CoverPalette.neutral, CoverPalette(top: 0xFF32_2427, bottom: 0xFF13_0F11, glow: 0xFF9B_3A53))
    }

    func testNurBildausschnittWirdVerwendet() {
        // 2 × 2 Bild, danach Fremddaten: nur die ersten vier Pixel zählen
        let px: [UInt32] = [rgb(30, 70, 200), rgb(30, 70, 200), rgb(30, 70, 200), rgb(30, 70, 200)] + Array(repeating: rgb(210, 40, 60), count: 100)
        let p = CoverPalette.from(pixels: px, width: 2, height: 2)
        XCTAssertEqual(hue(p.top), 225, accuracy: 20)
    }

    func testErsatzCover_bauplan() {
        let spec = FallbackArtwork.spec(for: .rock)
        XCTAssertNil(spec.artworkName)
        XCTAssertEqual(spec.gradientColors[1], GenrePalette.forCategory(.rock))
        XCTAssertEqual(spec.gradientColors.count, 3)
        XCTAssertEqual(FallbackArtwork.spec(for: .darkwave).artworkName, "genre_art_darkwave")
        XCTAssertEqual(FallbackArtwork.artworkName(.anthems), "genre_art_hymnen")
        XCTAssertEqual(FallbackArtwork.mix(0xFF00_0000, 0xFFFF_FFFF, 0.5), 0xFF7F_7F7F)
        XCTAssertEqual(FallbackArtwork.mix(0xFF10_2030, 0xFF10_2030, 0.3), 0xFF10_2030)
    }
}
