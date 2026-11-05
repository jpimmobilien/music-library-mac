import XCTest
@testable import MLCore

/// Modell-Teile von `audio/EffectsEngineTest.kt` (die Signalverarbeitung selbst läuft auf dem Mac über
/// AVAudioEngine); Sollwerte zusätzlich mit der Kotlin-Fassung auf der JVM berechnet.
final class EqualizerModelTests: XCTestCase {

    func testAutoAussteuerung_senktVorverstaerkung() {
        let s = AudioEffectsSettings(autoHeadroom: true).withBand(0, 6)
        XCTAssertEqual(s.headroomDb, -3)
        XCTAssertEqual(AudioEffectsSettings(autoHeadroom: true).withBand(0, -6).headroomDb, 0)
        XCTAssertEqual(AudioEffectsSettings(autoHeadroom: false).withBand(0, 6).headroomDb, 0)
    }

    func testPresets_vollstaendig() {
        let required = ["Neutral", "Bass Boost", "Rock", "Pop", "Klassik", "Jazz"]
        XCTAssertTrue(Set(EqPresets.all.map(\.name)).isSuperset(of: required))
        XCTAssertTrue(EqPresets.all.allSatisfy { p in p.gains.count == 10 && p.gains.allSatisfy { (EqBands.minDb...EqBands.maxDb).contains($0) } })
        XCTAssertNotNil(EqPresets.matching(EqPresets.rock.gains))
        XCTAssertEqual(AudioEffectsSettings().withPreset(EqPresets.rock).activePreset, EqPresets.rock)
        XCTAssertNil(AudioEffectsSettings().withPreset(EqPresets.rock).withBand(3, 7).activePreset)
        XCTAssertEqual(EqPresets.byID("jazz"), EqPresets.jazz)
        XCTAssertNil(EqPresets.byID("gibtsnicht"))
        XCTAssertEqual(EqBands.labels.count, EqBands.count)
    }

    func testHohesBandBeiNiedrigerAbtastrate_wirdUebersprungen() {
        XCTAssertNil(PeakingFilter.coefficients(frequency: 16_000, gainDb: 6, q: EqBands.q, sampleRate: 22_050))
        XCTAssertNil(PeakingFilter.coefficients(frequency: 1_000, gainDb: 0, q: EqBands.q, sampleRate: 44_100))
        XCTAssertNotNil(PeakingFilter.coefficients(frequency: 1_000, gainDb: 3, q: EqBands.q, sampleRate: 44_100))
    }

    func testFrequenzgaenge_wieKotlin() {
        XCTAssertEqual(EqResponse.lowShelfDb(30, f0: 100, gainDb: 12), 11.87099894242799, accuracy: 1e-9)
        XCTAssertEqual(EqResponse.lowShelfDb(100, f0: 100, gainDb: 12), 6.0, accuracy: 1e-9) // halbe Wirkung
        XCTAssertEqual(EqResponse.lowShelfDb(500, f0: 100, gainDb: 12), 0.025795227622096406, accuracy: 1e-9)
        XCTAssertEqual(EqResponse.peakingDb(1000, f0: 1000, gainDb: 6, q: EqBands.q), 6.0, accuracy: 1e-9)
        XCTAssertEqual(EqResponse.equalizerDb(62, bands: EqPresets.rock.gains), 4.707876320976924, accuracy: 1e-9)
        XCTAssertEqual(EqResponse.bassFrequencies.count, 16)
        XCTAssertEqual(EqResponse.bassFrequencies[3], 30.31433133020796, accuracy: 1e-9)
        XCTAssertEqual(EqResponse.bassFrequencies.last!, 160, accuracy: 1e-9)
        let c = LowShelfFilter.coefficients(frequency: 100, gainDb: 6, sampleRate: 44_100)
        let expected = [1.0035029502277621, -1.9829760253579642, 0.9797574006574319, -1.9830469379593583, 0.9831894382838002]
        for (a, b) in zip(c, expected) { XCTAssertEqual(a, b, accuracy: 1e-12) }
    }

    func testBass_mitBassBoostPreset_keineDoppelteAnhebung() {
        let boost = AudioEffectsSettings().withPreset(EqPresets.bassBoost)
        XCTAssertEqual(boost.equalizerBassBoostDb, 7.572754, accuracy: 1e-5)
        let withBass = boost.withBass(12)
        // Equalizer hebt die Bässe bereits an → Regler wird begrenzt, gesamt höchstens +12 dB
        XCTAssertTrue(withBass.bassLimited)
        XCTAssertEqual(withBass.effectiveBassDb, 4.0)
        XCTAssertLessThanOrEqual(withBass.equalizerBassBoostDb + withBass.effectiveBassDb, AudioEffectsSettings.maxBassTotalDb)
        for b in 1...24 {
            let s = boost.withBass(Float(b) / 2)
            XCTAssertLessThanOrEqual(s.equalizerBassBoostDb + s.effectiveBassDb, AudioEffectsSettings.maxBassTotalDb, "Bass \(Float(b) / 2)")
        }
        for f in EqResponse.bassFrequencies {
            let total = EqResponse.equalizerDb(f, bands: withBass.effectiveBands)
                + EqResponse.lowShelfDb(f, f0: AudioEffectsSettings.bassFrequency, gainDb: Double(withBass.effectiveBassDb))
            XCTAssertLessThanOrEqual(total, Double(AudioEffectsSettings.maxBassTotalDb) + 0.6, "Gesamtanhebung bei \(f) Hz: \(total) dB")
        }
        // Absenken bleibt immer voll möglich
        XCTAssertEqual(boost.withBass(-6).effectiveBassDb, -6)
        // ohne Anhebung im Equalizer: volle Wirkung
        XCTAssertEqual(AudioEffectsSettings().withBass(12).effectiveBassDb, 12)
        XCTAssertFalse(AudioEffectsSettings().withBass(12).bassLimited)
        // Rock: 5,16 dB Bassanhebung → noch 6,5 dB Spielraum
        let rock = AudioEffectsSettings().withPreset(EqPresets.rock)
        XCTAssertEqual(rock.equalizerBassBoostDb, 5.1587563, accuracy: 1e-5)
        XCTAssertEqual(rock.withBass(6).effectiveBassDb, 6)
        XCTAssertEqual(rock.withBass(12).effectiveBassDb, 6.5)
    }

    func testBass_unabhaengigVomEqualizerSchalter() {
        var s = AudioEffectsSettings(eqEnabled: false).withPreset(EqPresets.rock)
        s.eqEnabled = false
        s = s.withBass(8)
        XCTAssertEqual(s.effectiveBassDb, 8)
        XCTAssertEqual(s.effectiveBands, EqPresets.flat.gains)
        XCTAssertTrue(s.isEqNeutral)
        XCTAssertFalse(s.isToneNeutral)
    }

    func testBass_rundetAufHalbeDezibel_undBegrenzt() {
        XCTAssertEqual(AudioEffectsSettings().withBass(3.4).bassDb, 3.5)
        XCTAssertEqual(AudioEffectsSettings().withBass(40).bassDb, 12)
        XCTAssertEqual(AudioEffectsSettings().withBass(-40).bassDb, -12)
        XCTAssertEqual(AudioEffectsSettings().withBand(2, 3.3).bandGains[2], 3.5)
        XCTAssertEqual(AudioEffectsSettings().withBand(2, -30).bandGains[2], -12)
        XCTAssertEqual(AudioEffectsSettings().withBand(10, 3), AudioEffectsSettings()) // ungültiges Band
    }

    func testBass_aussteuerung_beruecksichtigtBassanhebung() {
        let s = AudioEffectsSettings().withBass(10)
        XCTAssertEqual(s.headroomDb, -5, accuracy: 0.3)
        XCTAssertEqual(s.headroomDb, -4.99014, accuracy: 1e-4)
        // ohne Bass unverändert gegenüber 1.1.0 (größte Bandanhebung)
        XCTAssertEqual(AudioEffectsSettings().withPreset(EqPresets.bassBoost).headroomDb, -3, accuracy: 0.001)
        XCTAssertEqual(AudioEffectsSettings().withPreset(EqPresets.rock).headroomDb, -2.25)
    }

    func testNeutral_undVerstaerkung() {
        let neutral = AudioEffectsSettings()
        XCTAssertTrue(neutral.isToneNeutral)
        XCTAssertEqual(neutral.headroomDb, 0)
        XCTAssertEqual(neutral.linearGain, 1)
        var e = AudioEffectsSettings().withPreset(EqPresets.electronic)
        e.volume = 1.5
        XCTAssertEqual(e.linearGain, 1.124841313998684, accuracy: 1e-9)
    }

    func testTolerantesLesen() throws {
        let json = #"{"eqEnabled":false,"bandGains":[1,2,3],"volume":99,"bassDb":-40,"unbekannt":1}"#
        let s = try JSONDecoder().decode(AudioEffectsSettings.self, from: Data(json.utf8))
        XCTAssertFalse(s.eqEnabled)
        XCTAssertEqual(s.bandGains, EqPresets.flat.gains)
        XCTAssertEqual(s.volume, 3)
        XCTAssertEqual(s.bassDb, -12)
        XCTAssertTrue(s.autoHeadroom)
        let bands = #"{"bandGains":[20,0,0,0,0,0,0,0,0,-20]}"#
        XCTAssertEqual(try JSONDecoder().decode(AudioEffectsSettings.self, from: Data(bands.utf8)).bandGains, [12, 0, 0, 0, 0, 0, 0, 0, 0, -12])
    }
}
