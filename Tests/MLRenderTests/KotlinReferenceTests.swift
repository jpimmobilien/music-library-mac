import Foundation
import XCTest
@testable import MLRender

/**
 * Vergleich mit der Android-Fassung: Summen der Kanäle (A, R, G, B) aller Ebenen bei 160 px, erzeugt
 * mit den Kotlin-Renderern (`VinylRenderer.kt`, `CassetteRenderer.kt`, `CdRenderer.kt`). Unter Linux
 * stimmen die Bilder bitgenau überein; die kleine Toleranz deckt seltene Rundungsunterschiede der
 * Mathematikbibliothek (exp/atan2 im letzten Bit) auf anderen Plattformen ab.
 */
final class KotlinReferenceTests: XCTestCase {

    private struct Ref {
        let name: String
        let width: Int
        let height: Int
        let sums: [UInt64] // A, R, G, B
    }

    private let refs: [Ref] = [
        Ref(name: "cass_back", width: 160, height: 105, sums: [3567730, 655636, 613874, 634166]),
        Ref(name: "cass_front", width: 160, height: 105, sums: [1434657, 1660892, 1428066, 1493274]),
        Ref(name: "cass_hub", width: 28, height: 28, sums: [94282, 84126, 80412, 76775]),
        Ref(name: "cass_pack", width: 67, height: 67, sums: [819243, 167071, 148248, 141703]),
        Ref(name: "cd_body", width: 160, height: 178, sums: [6142897, 1121271, 1014301, 1050297]),
        Ref(name: "cd_disc", width: 130, height: 130, sums: [3031680, 1440417, 1447578, 1475450]),
        Ref(name: "cd_label", width: 86, height: 86, sums: [1362340, 1057830, 996758, 1002812]),
        Ref(name: "cd_overlay", width: 142, height: 142, sums: [723843, 2046523, 2000074, 2044970]),
        Ref(name: "vinyl_arm", width: 132, height: 29, sums: [173270, 61903, 61046, 62368]),
        Ref(name: "vinyl_armshadow", width: 132, height: 29, sums: [124282, 0, 0, 0]),
        Ref(name: "vinyl_label", width: 45, height: 45, sums: [405871, 285166, 165772, 185661]),
        Ref(name: "vinyl_plinth", width: 160, height: 160, sums: [6500404, 915475, 905531, 925782]),
        Ref(name: "vinyl_record", width: 137, height: 137, sums: [3759591, 446292, 441351, 450418]),
        Ref(name: "vinyl_sheen", width: 137, height: 137, sums: [145680, 3569486, 3534407, 3546651]),
    ]

    private func render(_ name: String, _ s: Int) -> RasterImage {
        switch name {
        case "vinyl_plinth": return VinylRenderer.plinth(s)
        case "vinyl_record": return VinylRenderer.record(VinylRenderer.recordSizePx(s))
        case "vinyl_sheen": return VinylRenderer.sheen(VinylRenderer.recordSizePx(s))
        case "vinyl_arm": return VinylRenderer.tonearm(s).arm
        case "vinyl_armshadow": return VinylRenderer.tonearm(s).shadow
        case "vinyl_label": return VinylRenderer.fallbackLabel(VinylRenderer.labelSizePx(s))
        case "cass_back": return CassetteRenderer.back(s)
        case "cass_front": return CassetteRenderer.front(s)
        case "cass_pack": return CassetteRenderer.pack(s)
        case "cass_hub": return CassetteRenderer.hub(s)
        case "cd_body": return CdRenderer.body(s)
        case "cd_disc": return CdRenderer.disc(s)
        case "cd_overlay": return CdRenderer.overlay(s)
        case "cd_label": return CdRenderer.fallbackLabel(CdGeometry.labelSizePx(s))
        default: fatalError(name)
        }
    }

    func testAllLayersMatchTheKotlinRenderers() {
        for ref in refs {
            let img = render(ref.name, 160)
            XCTAssertEqual(img.width, ref.width, ref.name)
            XCTAssertEqual(img.height, ref.height, ref.name)
            var sums = [UInt64](repeating: 0, count: 4)
            for p in img.pixels {
                sums[0] += UInt64(p >> 24); sums[1] += UInt64(p >> 16 & 255)
                sums[2] += UInt64(p >> 8 & 255); sums[3] += UInt64(p & 255)
            }
            // höchstens 1 Einheit Abweichung je 500 Pixel (unter Linux: 0)
            let tolerance = UInt64(img.pixels.count / 500 + 1)
            for ch in 0..<4 {
                let d = sums[ch] > ref.sums[ch] ? sums[ch] - ref.sums[ch] : ref.sums[ch] - sums[ch]
                XCTAssertLessThanOrEqual(d, tolerance, "\(ref.name) Kanal \(ch): \(sums[ch]) statt \(ref.sums[ch])")
            }
        }
    }

    func testPremultipliedConversion() {
        let img = RasterImage(width: 3, height: 1, pixels: [0x80FF_8040, 0xFF12_3456, 0x00FF_FFFF])
        let pm = img.premultipliedPixels()
        XCTAssertEqual(pm[0], 0x8080_4020)
        XCTAssertEqual(pm[1], 0xFF12_3456)
        XCTAssertEqual(pm[2], 0)
    }
}
