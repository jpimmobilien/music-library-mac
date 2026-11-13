import XCTest
@testable import AetherCore

final class OrbitTests: XCTestCase {
    func testEffectProfilesRespectReduceMotionFirst() {
        for profile in EffectProfile.allCases {
            let e = OrbitEffects.resolve(profile: profile, motion: .full, systemReduceMotion: true)
            XCTAssertFalse(e.livingBackground, "\(profile)")
            XCTAssertFalse(e.magneticHover, "\(profile)")
            XCTAssertFalse(e.spatialTransitions, "\(profile)")
            XCTAssertFalse(e.numberTransitions, "\(profile)")
            XCTAssertFalse(e.dataFlow, "\(profile)")
        }
        let balanced = OrbitEffects.resolve(profile: .balanced, motion: .full, systemReduceMotion: true)
        XCTAssertTrue(balanced.ambientIntro)
        XCTAssertTrue(balanced.introCrossfadeOnly, "Mit „Bewegung reduzieren“ nur eine Überblendung")
    }

    func testMinimalProfileHasNoDecorativeMotion() {
        let e = OrbitEffects.resolve(profile: .minimal, motion: .full, systemReduceMotion: false)
        XCTAssertFalse(e.ambientIntro)
        XCTAssertFalse(e.ambientLights)
        XCTAssertFalse(e.livingBackground)
        XCTAssertFalse(e.hoverReflection)
        XCTAssertFalse(e.magneticHover)
        XCTAssertTrue(e.dataFlow, "Datenfluss zeigt echte Aktivität und bleibt")
    }

    func testOnlyImmersiveLetsTheBackgroundLive() {
        XCTAssertFalse(OrbitEffects.resolve(profile: .balanced, motion: .full, systemReduceMotion: false).livingBackground)
        XCTAssertTrue(OrbitEffects.resolve(profile: .immersive, motion: .full, systemReduceMotion: false).livingBackground)
        XCTAssertFalse(OrbitEffects.resolve(profile: .immersive, motion: .reduced, systemReduceMotion: false).livingBackground)
        let off = OrbitEffects.resolve(profile: .immersive, motion: .off, systemReduceMotion: false)
        XCTAssertFalse(off.ambientIntro)
        XCTAssertFalse(off.hoverReflection)
    }

    func testRollingPeakForgetsOldValues() {
        var peak = RollingPeak(window: 60, bucket: 10)
        XCTAssertNil(peak.peak(at: 0))
        peak.add(5_000_000, at: 0)
        peak.add(1_000, at: 30)
        XCTAssertEqual(peak.peak(at: 30), 5_000_000)
        peak.add(2_000, at: 75)
        XCTAssertEqual(peak.peak(at: 75), 2_000, "Spitze nach Ablauf des Fensters vergessen")
        peak.add(.nan, at: 76)
        XCTAssertEqual(peak.peak(at: 76), 2_000)
    }

    func testNetworkRingIsRelativeAndNeverInvented() {
        XCTAssertNil(OrbitCoreModel.networkFraction(current: nil, peak: 1_000_000))
        XCTAssertEqual(OrbitCoreModel.networkFraction(current: 500_000, peak: 1_000_000), 0.5)
        // Ohne nennenswerten Verkehr: Untergrenze verhindert einen „vollen“ Ring bei 2 kB/s
        XCTAssertEqual(OrbitCoreModel.networkFraction(current: 2_000, peak: 2_000)!, 2_000 / OrbitCoreModel.networkFloor, accuracy: 1e-9)
        // Neuer Höchstwert: nie über 100 %
        XCTAssertEqual(OrbitCoreModel.networkFraction(current: 9_000_000, peak: 1_000_000), 1)
    }

    func testStorageAndMemoryFractions() {
        XCTAssertEqual(OrbitCoreModel.storageFraction(capacity: 1_000, available: 250), 0.75)
        XCTAssertNil(OrbitCoreModel.storageFraction(capacity: 0, available: 0))
        XCTAssertNil(OrbitCoreModel.storageFraction(capacity: 100, available: 200))
        XCTAssertEqual(OrbitCoreModel.memoryFraction(used: 8, physical: 16), 0.5)
        XCTAssertNil(OrbitCoreModel.memoryFraction(used: 8, physical: nil))
    }

    func testRingStateClampsAndMarksUnavailable() {
        let none = OrbitRingState(kind: .gpu, fraction: nil, basis: .measured)
        XCTAssertEqual(none.basis, .unavailable)
        XCTAssertEqual(none.arc, 0)
        let over = OrbitRingState(kind: .cpu, fraction: 1.4, basis: .measured)
        XCTAssertEqual(over.fraction, 1)
        XCTAssertEqual(OrbitRingState(kind: .cpu, fraction: 0.4321, basis: .measured).arc, 0.43, accuracy: 1e-9)
        XCTAssertEqual(OrbitRingState(kind: .cpu, fraction: 0.4337, basis: .measured).arc, 0.435, accuracy: 1e-9)
    }

    func testPaletteMatchesAndroid() {
        // Gleiche Werte wie ui/designsystem/…/OrbitPalette.kt (Android)
        XCTAssertEqual(OrbitPalette.arcticBlue, RGBA(0x3D8BFF))
        XCTAssertEqual(OrbitPalette.electricCyan, RGBA(0x18D6F0))
        XCTAssertEqual(OrbitPalette.softViolet, RGBA(0x8C7CFF))
    }

    func testArcticBlueAccentIsReadable() {
        guard let colors = AccentChoice.aetherBlue.fixed, let cyan = AccentChoice.electricCyan.fixed else { return XCTFail() }
        XCTAssertGreaterThanOrEqual(RGBA.contrast(colors.light, colors.light.preferredForeground), 4.5)
        XCTAssertGreaterThanOrEqual(RGBA.contrast(cyan.light, cyan.light.preferredForeground), 4.5)
    }
}
