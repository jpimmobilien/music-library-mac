import XCTest
@testable import MLCore

/// Bausteine von „Titel bearbeiten“ (2.3): Filter, Lautheit, Begrenzer, Tonhöhen-/Stimmungs-/Tonarterkennung,
/// Auto-Tune und die ganze Kette – mit Messungen an synthetischen Signalen.
final class EditDSPTests: XCTestCase {
    // MARK: Hilfen

    static func sine(_ f: Double, amp: Float, seconds: Double, rate: Double, phase: Double = 0) -> [Float] {
        let n = Int(seconds * rate)
        return (0..<n).map { amp * Float(sin(2 * Double.pi * f * Double($0) / rate + phase)) }
    }

    /// Klang mit Obertönen (Amplitude 1/k), wie eine einfache Stimme.
    static func voice(_ f: (Double) -> Double, amp: Float, seconds: Double, rate: Double, harmonics: Int = 8) -> [Float] {
        let n = Int(seconds * rate)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / rate
            phase += 2 * Double.pi * f(t) / rate
            var v = 0.0
            for k in 1...harmonics { v += sin(Double(k) * phase) / Double(k) }
            out[i] = amp * Float(v * 0.6)
        }
        return out
    }

    static func rms(_ x: ArraySlice<Float>) -> Double {
        (x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(x.count, 1))).squareRoot()
    }

    /// Ganze Datei durch die Kette (Blöcke ungleicher Größe).
    static func run(_ chain: EditChain, _ channels: [[Float]]) throws -> [[Float]] {
        var out = Array(repeating: [Float](), count: chain.channels)
        let n = channels[0].count
        var pos = 0
        var sizes = [1000, 4096, 777, 10_000, 3]
        var k = 0
        while pos < n {
            let m = min(sizes[k % sizes.count], n - pos)
            k += 1
            let ptrs = channels.map { arr in arr.withUnsafeBufferPointer { $0.baseAddress! + pos } }
            try chain.push(ptrs, frames: m) { p, c in
                for ch in 0..<chain.channels { out[ch].append(contentsOf: UnsafeBufferPointer(start: p[ch], count: c)) }
            }
            pos += m
        }
        sizes.removeAll()
        try chain.finish { p, c in
            for ch in 0..<chain.channels { out[ch].append(contentsOf: UnsafeBufferPointer(start: p[ch], count: c)) }
        }
        return out
    }

    static func detectPitch(_ x: [Float], rate: Double, at seconds: Double) -> Double? {
        let det = PitchDetector(sampleRate: rate, windowSize: 4096, minFrequency: 50, maxFrequency: 2000)
        let start = Int(seconds * rate)
        guard start + 4096 <= x.count else { return nil }
        return x.withUnsafeBufferPointer { det.detect($0.baseAddress! + start)?.frequency }
    }

    // MARK: Filter

    func testBiquadResponses() {
        let fs = 48_000.0
        let peak = BiquadCoefficients.peaking(frequency: 1000, gainDb: 6, bandwidthOctaves: 1, sampleRate: fs)
        XCTAssertEqual(peak.magnitudeDb(at: 1000, sampleRate: fs), 6, accuracy: 0.01)
        XCTAssertEqual(peak.magnitudeDb(at: 20, sampleRate: fs), 0, accuracy: 0.05)
        let shelf = BiquadCoefficients.lowShelf(frequency: 100, gainDb: -8, sampleRate: fs)
        XCTAssertEqual(shelf.magnitudeDb(at: 15, sampleRate: fs), -8, accuracy: 0.3)
        XCTAssertEqual(shelf.magnitudeDb(at: 100, sampleRate: fs), -4, accuracy: 0.1)
        XCTAssertEqual(shelf.magnitudeDb(at: 5000, sampleRate: fs), 0, accuracy: 0.05)
        let hp = BiquadCoefficients.highPass(frequency: 30, sampleRate: fs)
        XCTAssertEqual(hp.magnitudeDb(at: 30, sampleRate: fs), -3.01, accuracy: 0.05)
        XCTAssertLessThan(hp.magnitudeDb(at: 5, sampleRate: fs), -30)
        // Durch die Kette: 1-kHz-Sinus +6 dB → doppelte Amplitude
        var x = Self.sine(1000, amp: 0.25, seconds: 1, rate: fs)
        let chain = BiquadChain(channels: 1, stages: [peak])
        x.withUnsafeMutableBufferPointer { chain.process([$0.baseAddress!], frames: $0.count) }
        XCTAssertEqual(Self.rms(x[24_000...]) / (0.25 / 2.0.squareRoot()), 1.995, accuracy: 0.01)
    }

    // MARK: Lautheit

    func testKWeightingMatchesITUAt48k() {
        let k = LoudnessMeter.kWeighting(sampleRate: 48_000)
        XCTAssertEqual(k[0].b0, 1.53512485958697, accuracy: 1e-9)
        XCTAssertEqual(k[0].b1, -2.69169618940638, accuracy: 1e-9)
        XCTAssertEqual(k[0].b2, 1.19839281085285, accuracy: 1e-9)
        XCTAssertEqual(k[0].a1, -1.69065929318241, accuracy: 1e-9)
        XCTAssertEqual(k[0].a2, 0.73248077421585, accuracy: 1e-9)
        XCTAssertEqual(k[1].a1, -1.99004745483398, accuracy: 1e-9)
        XCTAssertEqual(k[1].a2, 0.99007225036621, accuracy: 1e-9)
    }

    /// EBU Tech 3341, Test 1: Stereo-Sinus 1 kHz bei −23 dBFS → −23,0 ± 0,1 LUFS; auch bei 44,1 kHz.
    /// Stille wird ausgeblendet (Gate), 20 dB leiser → −43 LUFS.
    func testIntegratedLoudness() {
        for rate in [48_000.0, 44_100.0] {
            let amp = Float(pow(10, -23.0 / 20))
            let tone = Self.sine(1000, amp: amp, seconds: 20, rate: rate)
            let meter = LoudnessMeter(sampleRate: rate, channels: 2)
            tone.withUnsafeBufferPointer { b in
                var pos = 0
                while pos < b.count {
                    let n = min(3333, b.count - pos)
                    meter.add([b.baseAddress! + pos, b.baseAddress! + pos], frames: n)
                    pos += n
                }
            }
            let silence = [Float](repeating: 0, count: Int(rate * 10))
            silence.withUnsafeBufferPointer { meter.add([$0.baseAddress!, $0.baseAddress!], frames: $0.count) }
            XCTAssertEqual(meter.integratedLoudness ?? 0, -23, accuracy: 0.1, "\(rate)")
            XCTAssertEqual(meter.samplePeakDb, -23, accuracy: 0.05)

            let quiet = Self.sine(1000, amp: amp / 10, seconds: 10, rate: rate)
            let m2 = LoudnessMeter(sampleRate: rate, channels: 2)
            quiet.withUnsafeBufferPointer { m2.add([$0.baseAddress!, $0.baseAddress!], frames: $0.count) }
            XCTAssertEqual(m2.integratedLoudness ?? 0, -43, accuracy: 0.1)
        }
        let short = LoudnessMeter(sampleRate: 48_000, channels: 1)
        let s = Self.sine(1000, amp: 0.5, seconds: 0.2, rate: 48_000)
        s.withUnsafeBufferPointer { short.add([$0.baseAddress!], frames: $0.count) }
        XCTAssertNil(short.integratedLoudness, "kürzer als ein Block")
    }

    // MARK: Begrenzer

    func testLimiterNeverExceedsCeilingAndKeepsQuietSignal() {
        let rate = 44_100.0
        let ceiling: Float = 0.891   // −1 dBFS
        var lcg: UInt64 = 42
        func rnd() -> Float { lcg = lcg &* 6_364_136_223_846_793_005 &+ 1; return Float(Int64(bitPattern: lcg >> 11) % 2000) / 1000 - 1 }
        var loud = (0..<88_200).map { i -> Float in rnd() * (i % 9000 < 300 ? 2.2 : 0.5) }
        var right = loud.map { $0 * 0.8 }
        let lim = PeakLimiter(sampleRate: rate, channels: 2, ceiling: ceiling)
        loud.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in lim.process([l.baseAddress!, r.baseAddress!], frames: l.count) }
        }
        XCTAssertLessThanOrEqual(loud.map(abs).max() ?? 0, ceiling + 1e-6)
        XCTAssertLessThanOrEqual(right.map(abs).max() ?? 0, ceiling + 1e-6)
        XCTAssertLessThan(lim.minimumGain, 0.5)

        // Leises Signal: unverändert, nur um die Vorausschau verzögert
        let quiet = Self.sine(440, amp: 0.5, seconds: 1, rate: rate)
        var copy = quiet
        let lim2 = PeakLimiter(sampleRate: rate, channels: 1, ceiling: ceiling)
        copy.withUnsafeMutableBufferPointer { lim2.process([$0.baseAddress!], frames: $0.count) }
        let d = lim2.latency
        for i in stride(from: d, to: quiet.count, by: 97) { XCTAssertEqual(copy[i], quiet[i - d], accuracy: 1e-6) }
    }

    // MARK: Erkennung

    func testPitchDetector() throws {
        let rate = 12_000.0
        let det = PitchDetector(sampleRate: rate)
        for f in [82.4, 110.0, 220.0, 440.0, 659.3] {
            let x = Self.voice({ _ in f }, amp: 0.5, seconds: 0.2, rate: rate)
            let r = try XCTUnwrap(x.withUnsafeBufferPointer { det.detect($0.baseAddress! + 500) }, "\(f)")
            XCTAssertEqual(r.frequency, f, accuracy: f * 0.003, "\(f)")
            XCTAssertGreaterThan(r.clarity, 0.9)
        }
        var lcg: UInt64 = 7
        let noise = (0..<4000).map { _ -> Float in lcg = lcg &* 6_364_136_223_846_793_005 &+ 1; return Float(Int64(bitPattern: lcg >> 11) % 2000) / 4000 }
        XCTAssertNil(noise.withUnsafeBufferPointer { det.detect($0.baseAddress!) }, "Rauschen ist stimmlos")
        let silence = [Float](repeating: 0, count: 2000)
        XCTAssertNil(silence.withUnsafeBufferPointer { det.detect($0.baseAddress!) })
    }

    func testScaleQuantization() {
        XCTAssertEqual(MusicScale.chromatic.nearestNote(to: 61.4, key: 0), 61)
        XCTAssertEqual(MusicScale.major.nearestNote(to: 61.4, key: 0), 62)     // C♯ nicht in C-Dur → D
        XCTAssertEqual(MusicScale.major.nearestNote(to: 60.6, key: 0), 60)
        XCTAssertEqual(MusicScale.minor.nearestNote(to: 64.2, key: 9), 64)     // a-Moll: E
        XCTAssertEqual(MusicScale.major.nearestNote(to: 66.0, key: 2), 66)     // D-Dur: F♯
        XCTAssertEqual(MusicMath.retuneFactor(from: 440, to: 432), 432.0 / 440.0, accuracy: 1e-12)
        XCTAssertEqual(MusicMath.cents(432, relativeTo: 440), -31.77, accuracy: 0.01)
    }

    /// Mehrstimmiger Klang in A = 442 Hz: Stimmung ≈ 442 Hz, Tonart C-Dur (Kadenz I–IV–V–I).
    func testTuningAndKeyDetection() throws {
        let rate = 44_100.0
        let ref = 442.0
        let chords: [[Double]] = [[48, 60, 64, 67], [48, 60, 64, 67], [53, 65, 69, 72], [55, 67, 71, 74], [48, 60, 64, 67], [52, 64, 67, 72]]
        var signal: [Float] = []
        for chord in chords {
            var part = [Float](repeating: 0, count: Int(rate * 1.0))
            for m in chord {
                let f = MusicMath.frequency(midi: m, reference: ref)
                let tone = Self.voice({ _ in f }, amp: 0.12, seconds: 1.0, rate: rate, harmonics: 4)
                for i in 0..<part.count { part[i] += tone[i] }
            }
            signal += part
        }
        let analyzer = MusicAnalyzer(sampleRate: rate)
        let size = analyzer.frameSize
        signal.withUnsafeBufferPointer { b in
            var pos = 0
            while pos + size <= b.count { analyzer.analyze(b.baseAddress! + pos); pos += size / 2 }
        }
        let found = try XCTUnwrap(analyzer.referenceFrequency)
        XCTAssertEqual(found, ref, accuracy: 0.7)
        let key = try XCTUnwrap(analyzer.key)
        XCTAssertEqual(key.tonic, 0)
        XCTAssertEqual(key.scale, .major)
    }

    // MARK: Auto-Tune

    /// Gesang 452 Hz (zwischen A und B♭) → chromatisch, Stärke 100 % → 440 Hz; gleiche Länge.
    func testAutoTuneCorrectsToNearestNote() throws {
        let rate = 44_100.0
        let x = Self.voice({ _ in 452 }, amp: 0.4, seconds: 2, rate: rate)
        let chain = EditChain(sampleRate: rate, channels: 1,
                              parameters: EditChainParameters(autoTune: .init(key: 0, scale: .chromatic, strength: 1)))
        let y = try Self.run(chain, [x])[0]
        XCTAssertEqual(y.count, x.count)
        for t in [0.6, 1.0, 1.4] {
            let f = try XCTUnwrap(Self.detectPitch(y, rate: rate, at: t), "\(t)")
            XCTAssertEqual(f, 440, accuracy: 2.5, "bei \(t) s")
        }
        // Pegel bleibt erhalten
        XCTAssertEqual(Self.rms(y[22_050..<66_150]) / Self.rms(x[22_050..<66_150]), 1, accuracy: 0.1)
    }

    /// Glissando 425 → 455 Hz in A-Dur: Ergebnis bleibt bei den Tönen der Tonleiter (A 440 oder G♯ 415/B 494 – hier A).
    func testAutoTuneHoldsGlideOnScaleTone() throws {
        let rate = 44_100.0
        let x = Self.voice({ t in 425 + 15 * t }, amp: 0.4, seconds: 2, rate: rate)
        let chain = EditChain(sampleRate: rate, channels: 1,
                              parameters: EditChainParameters(autoTune: .init(key: 9, scale: .major, strength: 1)))
        let y = try Self.run(chain, [x])[0]
        for t in [0.5, 1.0, 1.5] {
            let f = try XCTUnwrap(Self.detectPitch(y, rate: rate, at: t))
            XCTAssertEqual(f, 440, accuracy: 3, "bei \(t) s (Eingang \(425 + 15 * t) Hz)")
        }
    }

    /// Bereits richtig gestimmt: Auto-Tune verändert kaum etwas; Rauschen bleibt unverändert.
    func testAutoTuneLeavesInTuneAndUnvoicedAlone() throws {
        let rate = 44_100.0
        let x = Self.voice({ _ in 440 }, amp: 0.4, seconds: 1.5, rate: rate)
        let chain = EditChain(sampleRate: rate, channels: 1, parameters: EditChainParameters(autoTune: .init(key: 0, scale: .chromatic, strength: 1)))
        let y = try Self.run(chain, [x])[0]
        let f = try XCTUnwrap(Self.detectPitch(y, rate: rate, at: 0.7))
        XCTAssertEqual(f, 440, accuracy: 1)

        var lcg: UInt64 = 99
        let noise = (0..<Int(rate)).map { _ -> Float in lcg = lcg &* 6_364_136_223_846_793_005 &+ 1; return Float(Int64(bitPattern: lcg >> 11) % 2000) / 8000 }
        let chain2 = EditChain(sampleRate: rate, channels: 1, parameters: EditChainParameters(autoTune: .init(key: 0, scale: .major, strength: 1)))
        let z = try Self.run(chain2, [noise])[0]
        XCTAssertEqual(z.count, noise.count)
        var diff = 0.0
        for i in 0..<noise.count { diff += Double(abs(z[i] - noise[i])) }
        XCTAssertLessThan(diff / Double(noise.count), 0.002, "Rauschen unverändert")
    }

    // MARK: Kette

    func testChainNeutralIsBitExact() throws {
        let x = Self.voice({ _ in 220 }, amp: 0.3, seconds: 1, rate: 48_000)
        let y = try Self.run(EditChain(sampleRate: 48_000, channels: 2, parameters: EditChainParameters()), [x, x])
        XCTAssertEqual(y[0], x)
        XCTAssertEqual(y[1], x)
    }

    func testChainTempoPitchGainAndLimiter() throws {
        let rate = 44_100.0
        let x = Self.voice({ _ in 220 }, amp: 0.3, seconds: 3, rate: rate)
        // Tempo 1,25 ohne Tonhöhenänderung
        let fast = try Self.run(EditChain(sampleRate: rate, channels: 1, parameters: EditChainParameters(speed: 1.25)), [x])[0]
        XCTAssertEqual(fast.count, Int((Double(x.count) / 1.25).rounded()))
        XCTAssertEqual(try XCTUnwrap(Self.detectPitch(fast, rate: rate, at: 1.0)), 220, accuracy: 1.5)
        // Tonhöhe +12 Halbtöne, Tempo gleich
        let up = try Self.run(EditChain(sampleRate: rate, channels: 1, parameters: EditChainParameters(pitch: 2)), [x])[0]
        XCTAssertEqual(up.count, x.count)
        XCTAssertEqual(try XCTUnwrap(Self.detectPitch(up, rate: rate, at: 1.5)), 440, accuracy: 2.5)
        // Umstimmen 440 → 432
        let tuned = try Self.run(EditChain(sampleRate: rate, channels: 1, parameters: EditChainParameters(pitch: 432.0 / 440.0)), [x])[0]
        XCTAssertEqual(try XCTUnwrap(Self.detectPitch(tuned, rate: rate, at: 1.5)), 220 * 432 / 440, accuracy: 1)
        // −6 dB
        let quiet = try Self.run(EditChain(sampleRate: rate, channels: 1, parameters: EditChainParameters(gainDb: -6.0206)), [x])[0]
        XCTAssertEqual(Self.rms(quiet[...]) / Self.rms(x[...]), 0.5, accuracy: 0.001)
        // +12 dB mit Begrenzer −1 dBFS: nie darüber, gleiche Länge
        let loud = try Self.run(EditChain(sampleRate: rate, channels: 2,
                                          parameters: EditChainParameters(gainDb: 12, limiterCeiling: 0.891)), [x, x])
        XCTAssertEqual(loud[0].count, x.count)
        XCTAssertLessThanOrEqual(loud[0].map(abs).max() ?? 0, 0.891 + 1e-6)
        // Equalizer: Bass-Kuhschwanz −12 dB senkt 40 Hz deutlich, 4 kHz kaum
        let low = Self.sine(40, amp: 0.3, seconds: 1, rate: rate)
        let eqd = try Self.run(EditChain(sampleRate: rate, channels: 1, parameters: EditChainParameters(bassDb: -12)), [low])[0]
        XCTAssertLessThan(20 * log10(Self.rms(eqd[22_050...]) / Self.rms(low[22_050...])), -9)
    }
}
