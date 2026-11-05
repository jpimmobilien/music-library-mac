import Foundation
import XCTest
@testable import MLRender

/** Mechanik und Grafik der Kassette „Cassette Studio“ (Port von CassetteTest.kt). */
final class CassetteTests: XCTestCase {

    private typealias G = CassetteGeometry

    func testWickel_anfangLinksVoll_endeRechtsVoll() {
        let (l0, r0) = G.packRadii(0)
        XCTAssertEqual(G.FULL_RADIUS, l0, accuracy: 1e-4)
        XCTAssertEqual(G.CORE_RADIUS, r0, accuracy: 1e-4)
        let (l1, r1) = G.packRadii(1)
        XCTAssertEqual(G.CORE_RADIUS, l1, accuracy: 1e-4)
        XCTAssertEqual(G.FULL_RADIUS, r1, accuracy: 1e-4)
    }

    func testBandmenge_bleibtErhalten() {
        // Summe der Wickelflächen (= Bandlänge × Banddicke) ist bei jedem Fortschritt gleich
        func total(_ p: Float) -> Double {
            let (l, r) = G.packRadii(p)
            return Double.pi * Double(l * l + r * r)
        }
        let ref = total(0)
        for i in 0...20 { XCTAssertEqual(ref, total(Float(i) / 20), accuracy: ref * 1e-5) }
    }

    func testWickel_passenNebeneinander() {
        for i in 0...20 {
            let (l, r) = G.packRadii(Float(i) / 20)
            XCTAssertTrue(l + r < G.HUB_RIGHT_X - G.HUB_LEFT_X, "Wickel berühren sich bei \(i * 5) %")
        }
    }

    func testKleinerWickel_drehtSchneller() {
        let small = G.degreesPerSecond(G.CORE_RADIUS)
        let large = G.degreesPerSecond(G.FULL_RADIUS)
        XCTAssertTrue(small > large)
        // 4,76 cm/s bei 8,6 mm Radius ≈ 317 °/s
        XCTAssertEqual(47.6 / 8.6 * 180 / Float(Double.pi), small, accuracy: 0.01)
        // Tonhöhe „Schallplatte“ (schneller) → Naben drehen entsprechend schneller
        XCTAssertEqual(large * 1.5, G.degreesPerSecond(G.FULL_RADIUS, speedFactor: 1.5), accuracy: 0.01)
    }

    func testGrafik_etikettDeckend_gehaeuseDurchscheinend() {
        let w = 400
        let front = CassetteRenderer.front(w)
        let k = CassetteRenderer.pxPerMm(w)
        let m = CassetteRenderer.MARGIN_MM
        func alphaAt(_ mmX: Float, _ mmY: Float) -> UInt32 {
            let x = Int((mmX + m) * k), y = Int((mmY + m) * k)
            return front.pixels[y * front.width + x] >> 24
        }
        XCTAssertEqual(255, alphaAt(50, 9)) // Etikett
        XCTAssertTrue(alphaAt(50, 30.5) < 120, "Fenster muss durchsichtig sein") // klare Schale über den Wickeln
        XCTAssertEqual(0, front.pixels[0] >> 24) // Ecke außerhalb
        XCTAssertEqual(CassetteRenderer.heightFor(w), front.height)
    }

    func testGrafik_nabeUndWickel() {
        let w = 400
        let hub = CassetteRenderer.hub(w)
        let c = hub.width / 2
        XCTAssertEqual(0, hub.pixels[c * hub.width + c] >> 24, "Mitte der Nabe ist offen (Antriebsdorn)")
        let ring = Int(CassetteGeometry.HUB_RADIUS * 0.8 * CassetteRenderer.pxPerMm(w))
        XCTAssertEqual(255, hub.pixels[(c + ring) * hub.width + c] >> 24)
        let pack = CassetteRenderer.pack(w)
        let pc = pack.width / 2
        XCTAssertEqual(255, pack.pixels[pc * pack.width + pc] >> 24)
        XCTAssertEqual(hub.width, CassetteRenderer.hubSizePx(w))
        XCTAssertEqual(pack.width, CassetteRenderer.packSizePx(w))
    }

    func testGrafik_istDeterministisch() {
        XCTAssertEqual(CassetteRenderer.front(200).pixels, CassetteRenderer.front(200).pixels)
        XCTAssertEqual(CassetteRenderer.back(200).pixels, CassetteRenderer.back(200).pixels)
    }
}
