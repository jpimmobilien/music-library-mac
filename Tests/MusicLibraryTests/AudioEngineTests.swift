import XCTest
import AVFoundation
@testable import MusicLibrary

/// Prüft die echte Klangkette (AVAudioEngine mit TimePitch, Varispeed, EQ, Limiter) im Offline-Modus:
/// Testtöne werden durch die Kette gerechnet und das Ergebnis gemessen – ohne Audiogerät.
final class AudioEngineTests: XCTestCase {
    private let sampleRate: Double = 44_100
    private var format: AVAudioFormat { AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)! }

    private func sine(_ frequency: Double, amplitude: Float, seconds: Double) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
        buffer.frameLength = n
        for c in 0..<2 {
            let p = buffer.floatChannelData![c]
            for i in 0..<Int(n) {
                p[i] = amplitude * Float(sin(2 * Double.pi * frequency * Double(i) / sampleRate))
            }
        }
        return buffer
    }

    /// Rechnet `input` durch die Kette und liefert Kanal 0 der Ausgabe.
    private func render(_ input: AVAudioPCMBuffer, seconds: Double? = nil, _ configure: (inout AudioEngine.Parameters) -> Void = { _ in }) throws -> [Float] {
        let audio = AudioEngine(offlineFormat: format)
        XCTAssertTrue(audio.isOffline)
        audio.connect(format: format)
        var p = AudioEngine.Parameters()
        configure(&p)
        audio.apply(p, force: true)
        audio.player.scheduleBuffer(input, at: nil)
        try audio.start()
        audio.player.play()
        let total = Int((seconds ?? Double(input.frameLength) / sampleRate) * sampleRate)
        let out = AVAudioPCMBuffer(pcmFormat: audio.engine.manualRenderingFormat, frameCapacity: 4096)!
        var samples: [Float] = []
        samples.reserveCapacity(total)
        while samples.count < total {
            let frames = AVAudioFrameCount(min(4096, total - samples.count))
            let status = try audio.engine.renderOffline(frames, to: out)
            guard status == .success else {
                XCTFail("renderOffline: Status \(status.rawValue)")
                break
            }
            samples.append(contentsOf: UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
        }
        audio.player.stop()
        audio.stopEngine()
        return samples
    }

    /// Eingeschwungener Bereich (ohne Anfang/Ende, Latenz von Limiter und TimePitch).
    private func steady(_ s: [Float], from: Double = 0.25, to: Double = 0.85) -> ArraySlice<Float> {
        s[Int(Double(s.count) * from)..<Int(Double(s.count) * to)]
    }

    private func peak(_ s: ArraySlice<Float>) -> Float { s.map(abs).max() ?? 0 }

    private func rms(_ s: ArraySlice<Float>) -> Float {
        guard !s.isEmpty else { return 0 }
        return sqrt(s.reduce(0) { $0 + $1 * $1 } / Float(s.count))
    }

    private func db(_ ratio: Float) -> Float { 20 * log10(max(ratio, 1e-9)) }

    /// Grundfrequenz über Nulldurchgänge.
    private func frequency(_ s: ArraySlice<Float>) -> Double {
        var crossings = 0
        var prev = s.first ?? 0
        for v in s.dropFirst() {
            if (prev < 0 && v >= 0) { crossings += 1 }
            prev = v
        }
        return Double(crossings) / (Double(s.count) / sampleRate)
    }

    func testNeutralChainIsTransparent() throws {
        let out = steady(try render(sine(1000, amplitude: 0.5, seconds: 1.0)))
        let p = peak(out)
        print("[Audio] neutral: Spitze \(p)")
        XCTAssertEqual(p, 0.5, accuracy: 0.03)
        XCTAssertEqual(frequency(out), 1000, accuracy: 15)
    }

    func testVolumeBelowFullScalesLinearly() throws {
        let out = steady(try render(sine(1000, amplitude: 0.5, seconds: 1.0)) { $0.volume = 0.5 })
        let p = peak(out)
        print("[Audio] Lautstärke 50 %: Spitze \(p)")
        XCTAssertEqual(p, 0.25, accuracy: 0.02)
    }

    func testVolumeBoostIsLouderButLimited() throws {
        let base = rms(steady(try render(sine(1000, amplitude: 0.5, seconds: 1.5))))
        let boosted = steady(try render(sine(1000, amplitude: 0.5, seconds: 1.5)) { $0.volume = 3.0 })
        let p = peak(boosted)
        let gain = db(rms(boosted) / base)
        print("[Audio] Lautstärke 300 %: Spitze \(p), Pegelgewinn \(gain) dB")
        XCTAssertGreaterThan(gain, 2.5, "Verstärkung über 100 % muss lauter sein")
        XCTAssertLessThanOrEqual(p, 1.02, "Limiter muss Übersteuern verhindern")
    }

    func testEqualizerBandBoostAtCenterFrequency() throws {
        let base = rms(steady(try render(sine(1000, amplitude: 0.05, seconds: 1.0))))
        let boosted = rms(steady(try render(sine(1000, amplitude: 0.05, seconds: 1.0)) { p in
            p.bandGains[5] = 12 // 1 kHz
        }))
        let gain = db(boosted / base)
        print("[Audio] EQ 1 kHz +12 dB: gemessen \(gain) dB")
        XCTAssertEqual(gain, 12, accuracy: 1.5)
    }

    func testEqualizerLeavesDistantFrequenciesAlone() throws {
        let base = rms(steady(try render(sine(125, amplitude: 0.05, seconds: 1.0))))
        let boosted = rms(steady(try render(sine(125, amplitude: 0.05, seconds: 1.0)) { p in
            p.bandGains[9] = 12 // 16 kHz
        }))
        let gain = db(boosted / base)
        print("[Audio] EQ 16 kHz +12 dB bei 125 Hz: \(gain) dB")
        XCTAssertEqual(gain, 0, accuracy: 0.5)
    }

    func testHeadroomCompensatesBoost() throws {
        let base = rms(steady(try render(sine(1000, amplitude: 0.05, seconds: 1.0))))
        let out = rms(steady(try render(sine(1000, amplitude: 0.05, seconds: 1.0)) { p in
            p.bandGains[5] = 12
            p.headroomDb = -12
        }))
        let gain = db(out / base)
        print("[Audio] EQ +12 dB mit −12 dB Aussteuerung: \(gain) dB")
        XCTAssertEqual(gain, 0, accuracy: 1.5)
    }

    func testBassShelfBoostsLowsOnly() throws {
        let lowBase = rms(steady(try render(sine(50, amplitude: 0.05, seconds: 1.0))))
        let low = rms(steady(try render(sine(50, amplitude: 0.05, seconds: 1.0)) { $0.bassDb = 6 }))
        let highBase = rms(steady(try render(sine(5000, amplitude: 0.05, seconds: 1.0))))
        let high = rms(steady(try render(sine(5000, amplitude: 0.05, seconds: 1.0)) { $0.bassDb = 6 }))
        print("[Audio] Bass +6 dB: 50 Hz \(db(low / lowBase)) dB, 5 kHz \(db(high / highBase)) dB")
        XCTAssertEqual(db(low / lowBase), 6, accuracy: 1.2)
        XCTAssertEqual(db(high / highBase), 0, accuracy: 0.5)
    }

    func testPitchShiftOctaveUpKeepsDuration() throws {
        let out = steady(try render(sine(440, amplitude: 0.4, seconds: 1.5)) { $0.pitchCents = 1200 })
        let f = frequency(out)
        print("[Audio] Tonhöhe +12 Halbtöne: \(f) Hz")
        XCTAssertEqual(f, 880, accuracy: 880 * 0.05)
    }

    func testTempoChangeKeepsPitch() throws {
        let input = sine(440, amplitude: 0.4, seconds: 2.0)
        let samples = try render(input, seconds: 2.0) { $0.tempo = 1.5 }
        let f = frequency(steady(samples, from: 0.1, to: 0.5))
        // Nach 2 s / 1,5 ≈ 1,33 s ist der Ton zu Ende → das letzte Fünftel ist still.
        let tail = rms(steady(samples, from: 0.8, to: 1.0))
        print("[Audio] Tempo 1,5×: \(f) Hz, Restpegel \(tail)")
        XCTAssertEqual(f, 440, accuracy: 440 * 0.05)
        XCTAssertLessThan(tail, 0.01)
    }

    func testVarispeedChangesPitchAndSpeed() throws {
        let samples = try render(sine(440, amplitude: 0.4, seconds: 2.0), seconds: 2.0) { $0.varispeed = 2 }
        let f = frequency(steady(samples, from: 0.1, to: 0.4))
        let tail = rms(steady(samples, from: 0.7, to: 1.0))
        print("[Audio] Drehzahl 2×: \(f) Hz, Restpegel \(tail)")
        XCTAssertEqual(f, 880, accuracy: 880 * 0.05)
        XCTAssertLessThan(tail, 0.01)
    }

    func testEffectiveRate() {
        let audio = AudioEngine(offlineFormat: format)
        var p = AudioEngine.Parameters()
        p.tempo = 1.25
        audio.apply(p)
        XCTAssertEqual(audio.effectiveRate, 1.25, accuracy: 0.001)
        p.tempo = 1
        p.varispeed = 0.75
        audio.apply(p)
        XCTAssertEqual(audio.effectiveRate, 0.75, accuracy: 0.001)
    }

    func testLevelMeterFindsToneBand() {
        let meter = LevelMeter()
        let buffer = sine(1000, amplitude: 0.5, seconds: 0.1)
        meter.process(buffer)
        XCTAssertNil(meter.take(), "ausgeschaltet → keine Werte")
        meter.enabled = true
        meter.process(buffer)
        guard let values = meter.take() else { return XCTFail("keine Pegelwerte") }
        XCTAssertEqual(values.count, LevelMeter.bandCount + 2)
        let bands = Array(values.prefix(LevelMeter.bandCount))
        let loudest = bands.indices.max { bands[$0] < bands[$1] }!
        // 1 kHz liegt im Band 8 (50 Hz · 280^(8/16) ≈ 837 Hz … 50 Hz · 280^(9/16) ≈ 1,2 kHz)
        XCTAssertEqual(loudest, 8)
        XCTAssertGreaterThan(values[LevelMeter.bandCount], 0.8) // links ≈ −6 dBFS → 0,9
        XCTAssertNil(meter.take(), "Werte werden nur einmal geliefert")
    }
}
