import Foundation
import XCTest
@testable import MLRender

/** Geometrie des Tonarms und Plausibilität der berechneten Plattenspieler-Grafik (Port von TurntableTest.kt). */
final class TurntableTests: XCTestCase {

    private typealias G = TurntableGeometry
    private let piF = Float(Double.pi)

    /** Nadelposition (Einheiten von S) bei gegebenem Bild-Drehwinkel. */
    private func stylusAt(_ angleDeg: Float) -> (Float, Float) {
        let a = angleDeg * piF / 180
        let x = G.PIVOT_X + G.stylusX * cos(a) - G.stylusY * sin(a)
        let y = G.PIVOT_Y + G.stylusX * sin(a) + G.stylusY * cos(a)
        return (x, y)
    }

    private func radiusFactorAt(_ angleDeg: Float) -> Float {
        let (x, y) = stylusAt(angleDeg)
        return hypot(x - G.CENTER_X, y - G.CENTER_Y) / G.RECORD_RADIUS
    }

    func testStylusFollowsTheGrooveAreaFromOutsideToInside() {
        XCTAssertEqual(G.STYLUS_START, radiusFactorAt(G.armAngleForProgress(0)), accuracy: 1e-3)
        XCTAssertEqual(G.STYLUS_END, radiusFactorAt(G.armAngleForProgress(1)), accuracy: 1e-3)
        // Unterwegs bleibt die Nadel im Rillenbereich und wandert stetig nach innen.
        var last = Float.greatestFiniteMagnitude
        for i in 0...50 {
            let r = radiusFactorAt(G.armAngleForProgress(Float(i) / 50))
            XCTAssertTrue(r <= G.GROOVE_OUTER && r >= G.GROOVE_INNER, "Radius \(r) bei \(i * 2) %")
            XCTAssertTrue(r <= last + 1e-4, "nicht monoton bei \(i * 2) %")
            last = r
        }
    }

    func testRestPositionIsBesideThePlatter() {
        let r = radiusFactorAt(G.armAngleForProgress(-1))
        XCTAssertTrue(r > G.PLATTER_FACTOR, "Ruhestellung liegt über dem Teller: \(r)")
        XCTAssertEqual(G.armAngleForProgress(-1), G.REST_ANGLE_DEG, accuracy: 1e-4)
    }

    func testArmAnglesMatchTheAndroidValues() {
        // Werte der Kotlin-Fassung (vinylprev/meta.txt): Einlauf, 35 %, Auslauf
        XCTAssertEqual(G.armAngleForProgress(0), 99.88927, accuracy: 1e-4)
        XCTAssertEqual(G.armAngleForProgress(0.35), 108.42381, accuracy: 1e-4)
        XCTAssertEqual(G.armAngleForProgress(1), 124.27369, accuracy: 1e-4)
    }

    func testArmStaysInsideTheTurntableArea() {
        // Gegengewicht (hinten) und Tonkopf (vorn) dürfen die Fläche nicht verlassen.
        for p: Float in [-1, -0.5, 0, 0.5, 1] {
            let a = G.armAngleForProgress(p) * piF / 180
            let backX = G.PIVOT_X - G.ARM_BACK * cos(a) * 0.95
            let backY = G.PIVOT_Y - G.ARM_BACK * sin(a) * 0.95
            let (tipX, tipY) = stylusAt(G.armAngleForProgress(p))
            for (x, y) in [(backX, backY), (tipX, tipY)] {
                XCTAssertTrue(x >= 0 && x <= 1 && y >= 0 && y <= 1, "Fortschritt \(p): (\(x), \(y)) außerhalb")
            }
        }
    }

    func testRecordIsRoundOpaqueAndDark() {
        let size = 240
        let rec = VinylRenderer.record(size)
        XCTAssertEqual(size * size, rec.pixels.count)
        func alpha(_ x: Int, _ y: Int) -> UInt32 { rec.pixels[y * size + x] >> 24 }
        func luminance(_ x: Int, _ y: Int) -> UInt32 {
            let p = rec.pixels[y * size + x]
            return ((p >> 16 & 0xff) * 2126 + (p >> 8 & 0xff) * 7152 + (p & 0xff) * 722) / 10000
        }
        XCTAssertEqual(0, alpha(0, 0)) // Ecke außerhalb des Tellers
        XCTAssertEqual(0, alpha(size - 1, size - 1))
        XCTAssertEqual(255, alpha(size / 2, size / 2))
        // Im Rillenbereich (≈ 70 % des Radius) deckend und nahezu schwarz
        let recordR = Float(size) / 2 / G.PLATTER_FACTOR
        let x = Int(Float(size) / 2 + 0.7 * recordR)
        XCTAssertEqual(255, alpha(x, size / 2))
        XCTAssertTrue(luminance(x, size / 2) < 40, "Vinyl zu hell: \(luminance(x, size / 2))")
    }

    func testLightReflectionPointsTowardsTheLight() {
        let size = 300
        let sheen = VinylRenderer.sheen(size)
        let recordR = Float(size) / 2 / G.PLATTER_FACTOR
        func alphaAt(_ angle: Float) -> UInt32 {
            let x = Int(Float(size) / 2 + cos(angle) * 0.7 * recordR)
            let y = Int(Float(size) / 2 + sin(angle) * 0.7 * recordR)
            return sheen.pixels[y * size + x] >> 24
        }
        let light: Float = -2.25
        let toLight = alphaAt(light)
        let across = alphaAt(light + Float(Double.pi / 2))
        XCTAssertTrue(toLight > across + 20, "Reflex zur Lampe (\(toLight)) muss deutlich heller sein als quer dazu (\(across))")
    }

    func testTonearmHasItsPivotInsideTheImage() {
        let arm = VinylRenderer.tonearm(400)
        XCTAssertTrue(arm.pivotX > 0 && arm.pivotX < Float(arm.arm.width))
        XCTAssertTrue(arm.pivotY > 0 && arm.pivotY < Float(arm.arm.height))
        let center = arm.arm.pixels[Int(arm.pivotY) * arm.arm.width + Int(arm.pivotX)]
        XCTAssertEqual(255, center >> 24, "Lager am Drehpunkt muss deckend sein")
        XCTAssertEqual(arm.arm.width, arm.shadow.width)
        XCTAssertEqual(arm.arm.height, arm.shadow.height)
        // Schatten ist reines Schwarz mit Deckkraft
        XCTAssertTrue(arm.shadow.pixels.allSatisfy { $0 & 0x00FF_FFFF == 0 })
    }

    func testRenderingIsDeterministic() {
        XCTAssertEqual(VinylRenderer.record(160).pixels, VinylRenderer.record(160).pixels)
        XCTAssertEqual(VinylRenderer.sheen(160).pixels, VinylRenderer.sheen(160).pixels)
        XCTAssertEqual(VinylRenderer.plinth(160).pixels, VinylRenderer.plinth(160).pixels)
    }

    func testFallbackLabelIsACircle() {
        let size = 120
        let label = VinylRenderer.fallbackLabel(size)
        XCTAssertEqual(0, label.pixels[0] >> 24)
        XCTAssertEqual(255, label.pixels[(size / 2) * size + size / 2] >> 24)
        // Rand halbtransparent geglättet
        let edge = label.pixels[(size / 2) * size + (size - 1)] >> 24
        XCTAssertTrue(edge <= 255)
    }

    func testAssetSizesMatchTheAndroidCache() {
        // TurntableAssetCache.recordSizePx / labelSizePx (gerundet)
        XCTAssertEqual(VinylRenderer.recordSizePx(1000), 859)
        XCTAssertEqual(VinylRenderer.labelSizePx(1000), 282)
        XCTAssertEqual(VinylRenderer.recordSizePx(1440), 1237)
        XCTAssertEqual(VinylRenderer.labelSizePx(1440), 406)
        let arm = VinylRenderer.tonearm(1000)
        XCTAssertEqual(arm.arm.width, Int((G.ARM_BACK + G.ARM_FRONT) * 1000) + 2)
        XCTAssertEqual(arm.pivotX, G.ARM_BACK * 1000, accuracy: 1e-3)
        XCTAssertEqual(arm.pivotY, Float(arm.arm.height) / 2, accuracy: 1e-6)
    }
}
