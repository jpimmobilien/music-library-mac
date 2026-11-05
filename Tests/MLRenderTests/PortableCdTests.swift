import Foundation
import XCTest
@testable import MLRender

/** Gerät, CD, Drehung und Anzeige des Designs „Portable CD“ (Port von PortableCdTest.kt). */
final class PortableCdTests: XCTestCase {

    private typealias G = CdGeometry

    // ---- Aufbau der CD (Norm-Maße) und des Geräts ---------------------------------------------

    func testCd_aufbauVonInnenNachAussen() {
        let radii = [G.HOLE_RADIUS, G.LABEL_INNER, G.CLEAR_RADIUS, G.STACK_RING_RADIUS, G.LABEL_OUTER, G.DATA_END, G.MIRROR_END, G.DISC_RADIUS]
        XCTAssertEqual(radii.sorted(), radii, "Radien müssen nach außen zunehmen")
        XCTAssertEqual(120, 2 * G.DISC_RADIUS)
        XCTAssertEqual(15, 2 * G.HOLE_RADIUS)
    }

    func testLabel_fuelltNichtDieGanzeCd_spiegelflaecheBleibtSichtbar() {
        // Cover nur im inneren Bereich (anders als beim Plattenlabel über die ganze Fläche)
        XCTAssertTrue(G.LABEL_OUTER / G.DISC_RADIUS <= 0.72)
        // sichtbarer Spiegelring außen mindestens 15 mm breit
        XCTAssertTrue(G.MIRROR_END - G.LABEL_OUTER >= 15)
        // Mittelloch und klarer Ring bleiben frei
        XCTAssertTrue(G.LABEL_INNER > G.HOLE_RADIUS + 3)
        XCTAssertEqual(G.LABEL_INNER / G.LABEL_OUTER, G.LABEL_HOLE_FRACTION, accuracy: 1e-6)
    }

    func testGeraet_cdImFenster_anzeigeUndLeuchteImGehaeuse() {
        XCTAssertTrue(G.DISC_RADIUS < G.WINDOW_RADIUS && G.WINDOW_RADIUS < G.RING_OUTER)
        // Fensterring liegt vollständig im Gehäuse
        XCTAssertTrue(G.DISC_CX - G.RING_OUTER > 0 && G.DISC_CX + G.RING_OUTER < G.BODY_W)
        XCTAssertTrue(G.DISC_CY - G.RING_OUTER > 0)
        // Anzeige unterhalb des Rings, im Gehäuse
        let lcdTop = G.LCD_CY - G.LCD_H / 2
        XCTAssertTrue(lcdTop > G.DISC_CY + G.RING_OUTER, "Anzeige überlappt den Fensterring")
        XCTAssertTrue(G.LCD_CY + G.LCD_H / 2 < G.BODY_H)
        XCTAssertTrue(G.LCD_CX - G.LCD_W / 2 > 0 && G.LCD_CX + G.LCD_W / 2 < G.BODY_W)
        // Leuchte links neben der Anzeige
        XCTAssertTrue(G.LED_X < G.LCD_CX - G.LCD_W / 2)
    }

    func testGroesse_passtInFlaeche_seitenverhaeltnisBleibt() {
        for (w, h) in [(1000, 1000), (600, 1200), (1200, 600), (333, 333)] {
            let width = G.widthToFit(w, h)
            let height = G.heightFor(width)
            XCTAssertTrue(width <= w && height <= h + 1)
            XCTAssertEqual(G.ASPECT, Float(width) / Float(height), accuracy: 0.01)
        }
    }

    // ---- Drehung: nur bei Wiedergabe, Pause hält an, Fortsetzen läuft weiter ------------------

    /** Simuliert [seconds] Sekunden mit 60 Bildern/s; gibt (Winkel, Geschwindigkeit) zurück. */
    private func run(_ angle: Float, _ velocity: Float, playing: Bool, seconds: Float, speed: Float = 1) -> (Float, Float) {
        var a = angle, v = velocity
        let dt: Float = 1 / 60
        for _ in 0..<Int(seconds * 60) {
            v = CdSpin.velocity(current: v, target: CdSpin.targetSpeed(playing: playing, speedFactor: speed), dt: dt)
            a = CdSpin.angle(current: a, velocity: v, dt: dt)
        }
        return (a, v)
    }

    func testDrehung_wiedergabe_pause_fortsetzen() {
        // Wiedergabe: läuft innerhalb einer Sekunde auf die volle Drehzahl an
        let (a1, v1) = run(0, 0, playing: true, seconds: 1)
        XCTAssertEqual(G.DEGREES_PER_SECOND, v1, accuracy: 0.01)
        XCTAssertTrue(a1 > 0)
        // Pause: läuft aus und steht
        let (a2, v2) = run(a1, v1, playing: false, seconds: 3)
        XCTAssertEqual(0, v2)
        // steht still – der Winkel ändert sich nicht mehr
        let (a3, v3) = run(a2, v2, playing: false, seconds: 2)
        XCTAssertEqual(a2, a3)
        XCTAssertEqual(0, v3)
        // Fortsetzen: dreht vom selben Winkel aus weiter (kein Sprung), Winkel bleibt in 0..360
        let (a4, v4) = run(a3, v3, playing: true, seconds: 0.05)
        XCTAssertTrue(v4 > 0)
        let step = (a4 - a3 + 360).truncatingRemainder(dividingBy: 360)
        XCTAssertTrue(step < 15, "Sprung beim Fortsetzen: \(step)°")
        XCTAssertTrue(a4 >= 0 && a4 <= 360)
    }

    func testDrehung_ohneWiedergabe_stehtStill_undHaengtNichtVonDerPositionAb() {
        // nie gestartet: keine Bewegung
        let (a, v) = run(42, 0, playing: false, seconds: 5)
        XCTAssertEqual(42, a); XCTAssertEqual(0, v)
        // Während des Spielens bleibt die Drehzahl konstant:
        let (_, vSteady) = run(0, 0, playing: true, seconds: 2)
        let (_, vLater) = run(0, vSteady, playing: true, seconds: 3)
        XCTAssertEqual(vSteady, vLater)
        // Tonhöhe „Schallplatte“ (schneller/langsamer) wird begrenzt übernommen
        XCTAssertEqual(G.DEGREES_PER_SECOND * 1.5, CdSpin.targetSpeed(playing: true, speedFactor: 1.5), accuracy: 0.01)
        XCTAssertEqual(G.DEGREES_PER_SECOND * 2, CdSpin.targetSpeed(playing: true, speedFactor: 8), accuracy: 0.01)
        XCTAssertEqual(0, CdSpin.targetSpeed(playing: false, speedFactor: 1))
    }

    func testDrehung_winkelBleibtImBereich_auchRueckwaerts() {
        XCTAssertEqual(10, CdSpin.angle(current: 350, velocity: 20, dt: 1), accuracy: 1e-4)
        XCTAssertEqual(350, CdSpin.angle(current: 10, velocity: -20, dt: 1), accuracy: 1e-4)
    }

    // ---- Anzeige ---------------------------------------------------------------------------

    func testAnzeige_segmenteDerZiffern() {
        XCTAssertEqual(CdDisplay.ALL, CdDisplay.segments("8"))
        XCTAssertEqual(CdDisplay.B | CdDisplay.C, CdDisplay.segments("1"))
        XCTAssertEqual(CdDisplay.G, CdDisplay.segments("-"))
        XCTAssertEqual(0, CdDisplay.segments(" "))
        // jede Ziffer leuchtet mit 2 bis 7 Segmenten, alle verschieden
        let masks = "0123456789".map { CdDisplay.segments($0) }
        XCTAssertEqual(10, Set(masks).count)
        for m in masks { XCTAssertTrue((2...7).contains(m.nonzeroBitCount)) }
    }

    func testAnzeige_titelnummerUndLaufzeit() {
        XCTAssertEqual("03", CdDisplay.trackText(3))
        XCTAssertEqual("42", CdDisplay.trackText(42))
        XCTAssertEqual("120", CdDisplay.trackText(120))
        XCTAssertEqual("--", CdDisplay.trackText(0))
        XCTAssertEqual("----", CdDisplay.trackText(123_456))
        func check(_ ms: Int64, _ m: String, _ s: String) {
            let t = CdDisplay.timeText(ms)
            XCTAssertEqual(t.minutes, m); XCTAssertEqual(t.seconds, s)
        }
        check(83_999, " 1", "23")
        check(600_000, "10", "00")
        check(6_005_000, "100", "05")
        check(-500, " 0", "00")
    }

    func testAnzeige_segmenteLiegenImZiffernfeld() {
        let w: Float = 3.7, h: Float = 7, t: Float = 0.78
        let r = CdDisplay.segmentRects(w, h, t)
        XCTAssertEqual(28, r.count)
        for i in 0..<7 {
            let x = r[i * 4], y = r[i * 4 + 1], sw = r[i * 4 + 2], sh = r[i * 4 + 3]
            XCTAssertTrue(x >= 0 && y >= 0 && x + sw <= w + 1e-4 && y + sh <= h + 1e-4 && sw > 0 && sh > 0, "Segment \(i)")
        }
    }

    // ---- Grafik ----------------------------------------------------------------------------

    private func lum(_ argb: UInt32) -> UInt32 { ((argb >> 16 & 255) * 2126 + (argb >> 8 & 255) * 7152 + (argb & 255) * 722) / 10000 }

    func testGrafik_cd_silberUndKlarerInnenring() {
        let w = 400
        let disc = CdRenderer.disc(w)
        let k = G.pxPerMm(w)
        let c = Float(disc.width) / 2
        func at(_ mm: Float, _ angle: Double = 1.0) -> UInt32 {
            let x = Int(c + Float(cos(angle)) * mm * k), y = Int(c + Float(sin(angle)) * mm * k)
            return disc.pixels[y * disc.width + x]
        }
        XCTAssertEqual(255, at(48) >> 24)                       // Datenfläche deckend
        XCTAssertTrue(lum(at(48)) > 70, "Silber zu dunkel")
        XCTAssertTrue(lum(at(9.5)) < 60, "klarer Ring zeigt den dunklen Teller")
        XCTAssertEqual(0, disc.pixels[0] >> 24)                 // außerhalb der CD
        // Spindel mit drei Klauen → die CD-Ebene ist nicht drehsymmetrisch (Drehung sichtbar)
        let claw = (0..<360).map { lum(at(6.3, Double($0) * Double.pi / 180)) }
        XCTAssertTrue(claw.max()! - claw.min()! > 40)
    }

    func testGrafik_reflexeStehenUeberDerCd_deckelscheibeDurchsichtig() {
        let w = 400
        let ov = CdRenderer.overlay(w)
        let k = G.pxPerMm(w)
        let c = Float(ov.width) / 2
        func alpha(_ mm: Float, _ angleDeg: Double) -> Int {
            let a = angleDeg * Double.pi / 180
            let x = Int(c + Float(cos(a)) * mm * k), y = Int(c + Float(sin(a)) * mm * k)
            return Int(ov.pixels[y * ov.width + x] >> 24)
        }
        // Glanzstreifen zum Licht (links oben) deutlich, quer dazu schwach
        XCTAssertTrue(alpha(48, -135) > alpha(48, -45) + 60)
        // Label (Cover) bleibt gut sichtbar: wenig Deckkraft quer zum Licht
        XCTAssertTrue(alpha(28, 90) < 50)
        // Deckelscheibe ist durchsichtig, außerhalb des Fensters nichts
        XCTAssertTrue((1...120).contains(alpha(62, 90)))
        XCTAssertEqual(0, ov.pixels[0] >> 24)
    }

    func testGrafik_gehaeuse_anzeigefensterUndRand() {
        let w = 400
        let body = CdRenderer.body(w)
        let k = G.pxPerMm(w)
        func px(_ mmX: Float, _ mmY: Float) -> UInt32 { body.pixels[Int((mmY + G.MARGIN) * k) * body.width + Int((mmX + G.MARGIN) * k)] }
        XCTAssertEqual(255, px(G.LCD_CX, G.LCD_CY) >> 24)
        XCTAssertTrue(lum(px(G.LCD_CX, G.LCD_CY)) < 40, "Anzeigefenster dunkel")
        XCTAssertEqual(255, px(10, 120) >> 24)                 // Gehäuse
        XCTAssertEqual(0, body.pixels[0] >> 24)                 // Ecke außerhalb (nur Schatten unten)
        XCTAssertEqual(G.heightFor(w), body.height)
        // Fensterring rosé (links, außerhalb des Glanzlichts): Rot deutlich über Grün
        let ring = px(G.DISC_CX - (G.WINDOW_RADIUS + 1.1), G.DISC_CY)
        XCTAssertTrue((ring >> 16 & 255) > (ring >> 8 & 255) + 30)
    }

    func testGrafik_ersatzlabel_ringMitAussparung() {
        let size = 300
        let label = CdRenderer.fallbackLabel(size)
        let c = size / 2
        XCTAssertEqual(0, label.pixels[c * size + c] >> 24)      // Mitte frei
        let r = Int(Float(size / 2) * 0.6)
        XCTAssertEqual(255, label.pixels[c * size + c + r] >> 24)
    }

    func testGrafik_istDeterministisch() {
        XCTAssertEqual(CdRenderer.disc(180).pixels, CdRenderer.disc(180).pixels)
        XCTAssertEqual(CdRenderer.overlay(180).pixels, CdRenderer.overlay(180).pixels)
        XCTAssertEqual(CdRenderer.body(180).pixels, CdRenderer.body(180).pixels)
    }

    func testGroessenDerEbenen() {
        let w = 1037
        XCTAssertEqual(CdRenderer.disc(w).width, G.discSizePx(w))
        XCTAssertEqual(G.discSizePx(w), 822)
        XCTAssertEqual(G.overlaySizePx(w), 901)
        XCTAssertEqual(G.labelSizePx(w), 559)
        XCTAssertEqual(G.heightFor(w), 1159)
        let (cx, cy) = G.discCenterPx(w)
        XCTAssertEqual(cx, 76 * G.pxPerMm(w), accuracy: 1e-3)
        XCTAssertEqual(cy, 75 * G.pxPerMm(w), accuracy: 1e-3)
    }
}
