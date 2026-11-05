import Foundation
import XCTest
@testable import MLRender

/** Cover-Label (Zuschnitt, Kreis, CD-Ring) und Bewegungslogik der Player-Designs. */
final class CoverLabelAndMotionTests: XCTestCase {

    /** Querformat-Cover: linke Hälfte rot, rechte Hälfte blau, 40-px-Rand grün (wird abgeschnitten). */
    private func landscapeCover() -> RasterImage {
        var img = RasterImage(width: 280, height: 200)
        for y in 0..<200 {
            for x in 0..<280 {
                img[x, y] = x < 40 || x >= 240 ? 0xFF00_FF00 : (x < 140 ? 0xFFFF_0000 : 0xFF00_00FF)
            }
        }
        return img
    }

    func testCircularLabel_mittigQuadratisch_runderRand() {
        let size = 101
        let label = CoverLabel.circular(landscapeCover(), size: size)
        XCTAssertEqual(label.width, size); XCTAssertEqual(label.height, size)
        XCTAssertEqual(label.alpha(x: 0, y: 0), 0)                      // Ecke außerhalb des Kreises
        XCTAssertEqual(label[25, 50], 0xFFFF_0000)                       // linke Hälfte rot
        XCTAssertEqual(label[75, 50], 0xFF00_00FF)                       // rechte Hälfte blau
        // kein Grün (der Rand des Querformats wird abgeschnitten, nicht gestaucht)
        XCTAssertFalse(label.pixels.contains { ($0 >> 8 & 255) > 8 && $0 >> 24 > 0 })
        // Kante geglättet: entlang des Randes gibt es halbtransparente Pixel
        let partial = label.pixels.filter { $0 >> 24 > 0 && $0 >> 24 < 255 }.count
        XCTAssertTrue(partial > 100, "nur \(partial) geglättete Randpixel")
    }

    func testCdRing_mitteFrei() {
        let size = 200
        let label = CoverLabel.cdRing(landscapeCover(), size: size)
        XCTAssertEqual(label.alpha(x: 100, y: 100), 0)                   // Mittelloch
        let inner = Int(100 * CdGeometry.LABEL_HOLE_FRACTION)
        XCTAssertEqual(label.alpha(x: 100 - inner + 6, y: 100), 0)       // noch im Loch
        XCTAssertEqual(label.alpha(x: 100 - inner - 6, y: 100), 255)     // Druck
        XCTAssertEqual(label.alpha(x: 2, y: 100), 255)
        XCTAssertEqual(label.alpha(x: 0, y: 0), 0)
    }

    func testSquareCrop_verkleinertMitFlaechenmittel() {
        // 2×2-Schachbrett schwarz/weiß in 64 px → 1 px: Mittelwert grau
        var img = RasterImage(width: 64, height: 64)
        for y in 0..<64 { for x in 0..<64 { img[x, y] = (x + y) % 2 == 0 ? 0xFF00_0000 : 0xFFFF_FFFF } }
        let one = CoverLabel.squareCrop(img, size: 1)
        let g = Int(one[0, 0] >> 8 & 255)
        XCTAssertTrue(abs(g - 128) <= 1, "Grau \(g)")
        // Vergrößern bleibt farbtreu
        let up = CoverLabel.squareCrop(RasterImage(width: 1, height: 1, pixels: [0xFF12_3456]), size: 9)
        XCTAssertTrue(up.pixels.allSatisfy { $0 == 0xFF12_3456 })
    }

    func testScaled_ganzesBildOhneZuschnitt() {
        // 4×2: links rot, rechts blau → 2×1 behält beide Hälften (kein Zuschnitt)
        let img = RasterImage(width: 4, height: 2, pixels: [0xFFFF_0000, 0xFFFF_0000, 0xFF00_00FF, 0xFF00_00FF,
                                                           0xFFFF_0000, 0xFFFF_0000, 0xFF00_00FF, 0xFF00_00FF])
        let s = CoverLabel.scaled(img, width: 2, height: 1)
        XCTAssertEqual(s.pixels, [0xFFFF_0000, 0xFF00_00FF])
        let p32 = CoverLabel.scaled(landscapeCover(), width: 32, height: 32)
        XCTAssertEqual(p32.width, 32); XCTAssertEqual(p32.height, 32)
        XCTAssertEqual(p32[0, 16] >> 8 & 255, 255) // grüner Rand bleibt enthalten
    }

    func testEasing_fastOutSlowIn() {
        let e = CubicBezierEasing.fastOutSlowIn
        XCTAssertEqual(e.transform(0), 0); XCTAssertEqual(e.transform(1), 1)
        XCTAssertEqual(e.transform(0.5), 0.7746, accuracy: 0.002) // bekannter Wert der Compose-Kurve
        var last: Float = 0
        for i in 1...20 { let v = e.transform(Float(i) / 20); XCTAssertTrue(v >= last); last = v }
    }

    func testTurntableSpin_anUndAuslaufen() {
        var spin = TurntableSpin()
        let target = TurntableSpin.targetSpeed(playing: true, speed: 1)
        XCTAssertEqual(target, 200)
        for _ in 0..<30 { spin.step(target: target, dt: 1 / 60) }      // 0,5 s: fast voll
        XCTAssertTrue(spin.velocity > 185 && spin.velocity < 200)
        for _ in 0..<42 { spin.step(target: target, dt: 1 / 60) }      // 1,2 s: eingerastet
        XCTAssertEqual(spin.velocity, 200)
        var steps = 0
        while spin.step(target: 0, dt: 1 / 60) { steps += 1 }
        XCTAssertEqual(spin.velocity, 0)
        XCTAssertTrue(steps > 30 && steps < 120, "Auslauf \(steps) Bilder")  // ≈ 1–2 s
        XCTAssertTrue(spin.angle >= 0 && spin.angle < 360)
    }

    func testTonearm_springtBeiTitelwechsel_folgtSonstLinear() {
        let arm = TonearmMotion(target: 0.2, playing: true)
        for _ in 0..<30 { arm.step(1 / 60) }
        XCTAssertEqual(arm.progress, 0.2, accuracy: 1e-5)
        XCTAssertEqual(arm.lift, 0)
        // kleiner Schritt: lineares Nachführen, kein Anheben
        arm.setTarget(0.21)
        for _ in 0..<8 { arm.step(1 / 60) }
        XCTAssertTrue(arm.progress > 0.2 && arm.progress < 0.21)
        XCTAssertEqual(arm.lift, 0)
        for _ in 0..<20 { arm.step(1 / 60) }
        XCTAssertEqual(arm.progress, 0.21, accuracy: 1e-5)
        // Sprung (Titelwechsel → Anfang): anheben, schwenken, absenken
        arm.setTarget(0)
        var maxLift: Float = 0
        var frames = 0
        repeat { arm.step(1 / 60); maxLift = max(maxLift, arm.lift); frames += 1 } while arm.isAnimating && frames < 600
        XCTAssertEqual(maxLift, 1, accuracy: 1e-4)
        XCTAssertEqual(arm.progress, 0, accuracy: 1e-6)
        XCTAssertEqual(arm.lift, 0)
        XCTAssertTrue(frames > 30 && frames < 90, "Sprung dauerte \(frames) Bilder")
        // Pause hebt an (480 ms)
        arm.setPlaying(false)
        for _ in 0..<15 { arm.step(1 / 60) }
        XCTAssertTrue(arm.lift > 0.3 && arm.lift < 1)
        for _ in 0..<30 { arm.step(1 / 60) }
        XCTAssertEqual(arm.lift, 1)
        XCTAssertEqual(arm.angleDegrees, TurntableGeometry.armAngleForProgress(0), accuracy: 1e-4)
    }

    func testTonearmPose() {
        let raster = VinylRenderer.tonearm(200)
        let pose = TonearmPose(size: 200, arm: raster, progress: 0, lift: 1)
        XCTAssertEqual(pose.armOriginX + raster.pivotX, TurntableGeometry.PIVOT_X * 200, accuracy: 1e-4)
        XCTAssertEqual(pose.shadowOriginX - pose.armOriginX, 200 * 0.026, accuracy: 1e-4)
        XCTAssertEqual(pose.shadowOriginY - pose.armOriginY, 200 * 0.026 * 1.3, accuracy: 1e-4)
        XCTAssertEqual(pose.shadowAlpha, 0.6, accuracy: 1e-6)
        XCTAssertEqual(pose.armScale, 1.03, accuracy: 1e-6)
    }

    func testCassetteReels_kleinerWickelDrehtSchneller_gegenDenUhrzeigersinn() {
        var reels = CassetteReels()
        let (l, r) = CassetteGeometry.packRadii(0.1) // links fast voll, rechts fast leer
        for _ in 0..<120 { reels.step(target: CassetteReels.targetMotor(playing: true, speed: 1), radiusLeftMm: l, radiusRightMm: r, dt: 1 / 60) }
        XCTAssertEqual(reels.motor, 1)
        XCTAssertTrue(reels.angleLeft < 0)                                 // gegen den Uhrzeigersinn
        // rechte Nabe (kleiner Wickel) hat sich weiter gedreht
        let turnedLeft = -reels.angleLeft
        let turnedRight = 37 - reels.angleRight
        XCTAssertTrue(turnedRight.truncatingRemainder(dividingBy: 360) >= 0)
        XCTAssertTrue(CassetteGeometry.degreesPerSecond(r) > CassetteGeometry.degreesPerSecond(l))
        XCTAssertTrue(turnedLeft > 0)
        while reels.step(target: 0, radiusLeftMm: l, radiusRightMm: r, dt: 1 / 60) {}
        XCTAssertEqual(reels.motor, 0)
        XCTAssertEqual(CassetteReels.targetMotor(playing: true, speed: 9), 4)
    }

    func testTangentPoint_liegtAufDemKreisUndIstTangential() {
        let p = CassetteGeometry.tangentPoint(cx: 0, cy: 0, r: 10, fromX: -5, fromY: 30, left: true)
        XCTAssertEqual((p.x * p.x + p.y * p.y).squareRoot(), 10, accuracy: 1e-3)
        // Radius ⟂ Tangente
        let dot = p.x * (-5 - p.x) + p.y * (30 - p.y)
        XCTAssertEqual(dot, 0, accuracy: 1e-2)
        XCTAssertTrue(p.x < 0) // linke, außen liegende Seite
    }

    func testVisualizerSmoothing() {
        var v = VisualizerSmoothing()
        let raw = [Float](repeating: 1, count: 18)
        v.step(raw: raw)
        XCTAssertEqual(v.bands[0], 0.55, accuracy: 1e-6)
        XCTAssertEqual(v.left, 0.5, accuracy: 1e-6)
        v.step(raw: nil)
        XCTAssertEqual(v.bands[0], 0.55 - 0.55 * 0.14, accuracy: 1e-6)
        var energy: Float = 1
        var n = 0
        while energy >= 0.01 && n < 200 { energy = v.step(raw: nil); n += 1 }
        XCTAssertTrue(n < 200)
    }
}
