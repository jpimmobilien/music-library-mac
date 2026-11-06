import Foundation
import XCTest
@testable import MLCore

/// Objektive Signaltests für die Tempo-/Tonhöhenverarbeitung (`TimePitchEngine`, `TimePitchProcessor`) –
/// Portierung von `audio/TimePitchEngineTest.kt` (Float statt 16 Bit, daher ohne Dither) plus Prüfungen für
/// den Render-Block-Betrieb unter macOS (Frequenzgenauigkeit, Pegel, Blockgrößen, `reset`, Verzerrungsanteil,
/// Zeitbezug, Überblenden, Rechenaufwand).
///
/// Die Schwellen liegen mit Abstand unter den gemessenen Werten, damit die Tests nicht an Rundungsdetails
/// scheitern, aber jede spürbare Verschlechterung auffällt. Messwerte werden zusätzlich ausgegeben.
/// Zeitmessungen werden nur ausgegeben, nicht geprüft (Debug-Builds und CI-Rechner sind unterschiedlich schnell).
final class TimePitchEngineTests: XCTestCase {

    // ------------------------------------------------------------------ Hilfen

    /// Reproduzierbarer Zufall (SplitMix64) mit Normalverteilung (Box-Muller).
    private struct Rng {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func uniform() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
        mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
        mutating func gaussian() -> Double {
            let u1 = max(uniform(), 1e-300)
            let u2 = uniform()
            return (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
        }
    }

    /// Planare Kopie eines Signals mit Kanalzeigern (für die Zeiger-API).
    private final class Planes {
        let channels: Int
        let frames: Int
        let mem: [UnsafeMutablePointer<Float>]
        let ptrs: UnsafeMutablePointer<UnsafePointer<Float>>
        let mptrs: UnsafeMutablePointer<UnsafeMutablePointer<Float>>

        init(_ data: [[Float]]) {
            channels = data.count
            frames = data[0].count
            mem = data.map { ch in
                let p = UnsafeMutablePointer<Float>.allocate(capacity: max(1, ch.count))
                p.initialize(from: ch, count: ch.count)
                return p
            }
            ptrs = .allocate(capacity: channels)
            mptrs = .allocate(capacity: channels)
            for c in 0..<channels {
                ptrs[c] = UnsafePointer(mem[c])
                mptrs[c] = mem[c]
            }
        }

        convenience init(channels: Int, frames: Int) {
            self.init([[Float]](repeating: [Float](repeating: 0, count: frames), count: channels))
        }

        func array() -> [[Float]] { mem.map { Array(UnsafeBufferPointer(start: $0, count: frames)) } }

        deinit {
            mem.forEach { $0.deallocate() }
            ptrs.deallocate()
            mptrs.deallocate()
        }
    }

    private struct Spectrum {
        let power: [Double]
        let binHz: Double
    }

    private func semis(_ s: Double) -> Float { Float(pow(2.0, s / 12.0)) }

    private func tones(_ sr: Int, _ seconds: Double, _ partials: [(Double, Double)]) -> [Float] {
        let n = Int(Double(sr) * seconds)
        var out = [Float](repeating: 0, count: n)
        for t in 0..<n {
            var v = 0.0
            for (f, a) in partials { v += a * sin(2 * Double.pi * f * Double(t) / Double(sr)) }
            out[t] = Float(v)
        }
        return out
    }

    /// Prozessor blockweise; `block` liefert die Größe des jeweils nächsten Blocks. Ausgabe gleich lang wie Eingang.
    private func runProcessor(_ p: TimePitchProcessor, _ input: [[Float]], block: () -> Int) -> [[Float]] {
        let inp = Planes(input)
        let out = Planes(channels: input.count, frames: inp.frames)
        let ip = UnsafeMutablePointer<UnsafePointer<Float>>.allocate(capacity: inp.channels)
        let op = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: inp.channels)
        defer {
            ip.deallocate()
            op.deallocate()
        }
        var pos = 0
        while pos < inp.frames {
            let n = min(block(), inp.frames - pos)
            for c in 0..<inp.channels {
                ip[c] = UnsafePointer(inp.mem[c] + pos)
                op[c] = out.mem[c] + pos
            }
            p.process(input: UnsafePointer(ip), output: UnsafePointer(op), frames: n)
            pos += n
        }
        return out.array()
    }

    /// Engine blockweise inklusive Ausklingen (wie `run` im Kotlin-Test).
    private func runEngine(_ e: TimePitchEngine, _ input: [[Float]], block: () -> Int = { 4096 }, readChunk: Int = 1000) -> [[Float]] {
        let ch = e.channels
        let inp = Planes(input)
        let buf = Planes(channels: ch, frames: readChunk)
        var out = [[Float]](repeating: [], count: ch)
        func drain() {
            while true {
                let r = e.read(UnsafePointer(buf.mptrs), maxFrames: readChunk)
                if r == 0 { break }
                for c in 0..<ch { out[c].append(contentsOf: UnsafeBufferPointer(start: buf.mem[c], count: r)) }
            }
        }
        var pos = 0
        while pos < inp.frames {
            let n = min(block(), inp.frames - pos)
            e.queueInput(UnsafePointer(inp.ptrs), offset: pos, frames: n)
            pos += n
            drain()
        }
        e.queueEndOfStream()
        drain()
        XCTAssertTrue(e.isEnded)
        XCTAssertEqual(e.overflowFrames, 0)
        return out
    }

    private func process(_ input: [[Float]], _ sr: Int, speed: Float, pitch: Float) -> [[Float]] {
        runEngine(TimePitchEngine(sampleRate: Double(sr), channels: input.count, speed: speed, pitch: pitch), input)
    }

    private func processor(_ sr: Int = 44100, channels: Int = 2, semitones: Double) -> TimePitchProcessor {
        TimePitchProcessor(sampleRate: Double(sr), channels: channels, speed: 1, pitch: semis(semitones))
    }

    /// Leistungsspektrum (Blackman-Harris) eines Ausschnitts.
    private func spectrum(_ x: [Float], _ from: Int, _ length: Int, _ sr: Int) -> Spectrum {
        var n = 1
        while n * 2 <= length { n *= 2 }
        var buf = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let w = 2 * Double.pi * Double(i) / Double(n - 1)
            let window = 0.35875 - 0.48829 * cos(w) + 0.14128 * cos(2 * w) - 0.01168 * cos(3 * w)
            buf[i] = Double(x[from + i]) * window
        }
        let (re, im) = RealFFT(n: n).forward(buf)
        return Spectrum(power: (0...n / 2).map { re[$0] * re[$0] + im[$0] * im[$0] }, binHz: Double(sr) / Double(n))
    }

    /// Energie an den erwarteten Frequenzen (±`lobe` Bins) gegenüber allem anderen (dB) und Energie je Teilton.
    private func purity(_ s: Spectrum, _ expected: [Double], lobe: Int = 6) -> (db: Double, levels: [Double]) {
        let p = s.power
        var mask = [Bool](repeating: false, count: p.count)
        var levels: [Double] = []
        var signal = 0.0
        for f in expected {
            let k = Int((f / s.binHz).rounded())
            var e = 0.0
            for j in max(0, k - lobe)...min(p.count - 1, k + lobe) where !mask[j] {
                mask[j] = true
                e += p[j]
            }
            levels.append(e)
            signal += e
        }
        var total = 0.0
        for j in Int(20.0 / s.binHz)..<p.count { total += p[j] }
        return (10 * log10(signal / max(total - signal, 1e-30)), levels)
    }

    private func db(_ x: Double) -> Double { 10 * log10(max(x, 1e-30)) }

    /// Analysebereich ohne Ein-/Ausschwingen.
    private func middle(_ y: [Float], _ sr: Int, _ seconds: Double = 1.5) -> (Int, Int) {
        (Int(0.6 * Double(sr)), min(Int(Double(sr) * seconds), y.count - Int(0.7 * Double(sr))))
    }

    /// Frequenz eines Sinus über aufsteigende Nulldurchgänge (linear interpoliert).
    private func zeroCrossingFrequency(_ x: [Float], from: Int, to: Int, sr: Int) -> Double {
        var firstT = -1.0
        var lastT = -1.0
        var count = 0
        for i in from..<(to - 1) where x[i] <= 0 && x[i + 1] > 0 {
            let t = Double(i) + Double(-x[i]) / Double(x[i + 1] - x[i])
            if firstT < 0 { firstT = t }
            lastT = t
            count += 1
        }
        return Double(count - 1) / (lastT - firstT) * Double(sr)
    }

    /// Frequenz eines Sinus: FFT-Spitze mit log-parabolischer Interpolation.
    private func fftFrequency(_ x: [Float], from: Int, n: Int, sr: Int) -> Double {
        let s = spectrum(x, from, n, sr)
        var k = 1
        for j in 1..<(s.power.count - 1) where s.power[j] > s.power[k] { k = j }
        let l = log(s.power[k - 1]), c = log(s.power[k]), r = log(s.power[k + 1])
        return (Double(k) + 0.5 * (l - r) / (l - 2 * c + r)) * s.binHz
    }

    private func peak(_ x: [Float]) -> Float { x.reduce(0) { max($0, abs($1)) } }

    private func maxDiff(_ a: [[Float]], _ b: [[Float]]) -> Float {
        var m: Float = 0
        for c in 0..<a.count {
            guard a[c].count == b[c].count else { return .infinity }
            for i in 0..<a[c].count { m = max(m, abs(a[c][i] - b[c][i])) }
        }
        return m
    }

    private func fmt(_ x: Double, _ digits: Int = 1) -> String { String(format: "%.\(digits)f", x) }

    // ------------------------------------------------------------------ Grundverhalten

    func testNeutraleEinstellungen_reichenBitgenauDurch() {
        XCTAssertTrue(TimePitchEngine(sampleRate: 44100, channels: 2, speed: 1, pitch: 1).isPassthrough)
        XCTAssertFalse(TimePitchEngine(sampleRate: 44100, channels: 2, speed: 1, pitch: semis(1)).isPassthrough)
        XCTAssertFalse(TimePitchEngine(sampleRate: 44100, channels: 2, speed: semis(1), pitch: semis(1)).isPassthrough)

        let neutral = TimePitchProcessor(sampleRate: 44100, channels: 2, speed: 1, pitch: 1)
        XCTAssertTrue(neutral.isPassthrough)
        XCTAssertEqual(neutral.latencyFrames, 0)
        XCTAssertFalse(processor(semitones: 0.1).isPassthrough)

        var rng = Rng(state: 1)
        let x = (0..<10_000).map { _ in Float(rng.gaussian() * 0.3) }
        let y = runProcessor(neutral, [x, x], block: { 333 })
        XCTAssertEqual(y[0], x)
        XCTAssertEqual(y[1], x)

        // Mit fester Verzögerung: bitgenau um latencyFrames verschoben
        let delayed = TimePitchProcessor(sampleRate: 44100, channels: 2, speed: 1, pitch: 1, delaysWhenNeutral: true)
        let latency = delayed.latencyFrames
        XCTAssertEqual(latency, processor(semitones: 3).latencyFrames)
        let z = runProcessor(delayed, [x, x], block: { 512 })
        XCTAssertTrue(z[0][0..<latency].allSatisfy { $0 == 0 })
        XCTAssertEqual(Array(z[0][latency...]), Array(x[0..<(x.count - latency)]))
    }

    func testLatenz_fuerAlleTonhoehenGleich_undOhneUnterlauf() {
        // Gleiche Verzögerung für −12…+12 Halbtöne (Grundlage für Überblenden ohne Zeitsprung)
        for sr in [44100, 48000] {
            let latencies = Set([-12.0, -5, -0.1, 0.1, 0.5, 2, 7, 12].map { processor(sr, semitones: $0).latencyFrames })
            XCTAssertEqual(latencies, [6251], "\(sr) Hz")
        }
        print("TimePitch-Latenz: 44,1 kHz \(processor(44100, semitones: 1).latencyFrames) Frames, " +
              "48 kHz \(processor(48000, semitones: 1).latencyFrames), 96 kHz \(processor(96000, semitones: 1).latencyFrames)")
        // Schlimmster Fall Blockgröße 1: die Verarbeitung liefert immer rechtzeitig
        for (sr, st) in [(44100, 12.0), (44100, -12.0), (48000, -0.1), (22050, -12.0)] {
            let p = processor(sr, semitones: st)
            let x = tones(sr, 1.2, [(440, 0.3)])
            _ = runProcessor(p, [x, x], block: { 1 })
            XCTAssertEqual(p.underrunFrames, 0, "\(sr) Hz \(st) HT")
            XCTAssertEqual(p.overflowFrames, 0, "\(sr) Hz \(st) HT")
        }
    }

    func testAusgabelaenge_istGenauEingangDurchSpeed() {
        let sr = 44100
        let x = tones(sr, 2.3, [(440, 0.3)])
        for (speed, pitch) in [(Float(1), semis(5)), (1, semis(-7)), (semis(3), semis(3)), (semis(-12), semis(-12)),
                               (semis(12), semis(12)), (1, semis(12)), (4, 0.5)] {
            let out = process([x, x], sr, speed: speed, pitch: pitch)
            XCTAssertEqual(out[0].count, Int((Double(x.count) / Double(speed)).rounded()), "speed=\(speed) pitch=\(pitch)")
        }
    }

    func testErgebnis_unabhaengigVonBlockgroessen() {
        let sr = 44100
        // Engine (wie Android): zufällige Blöcke 1…3000, Lesen in Stücken zu 333
        let x = tones(sr, 2.0, [(220, 0.3), (1234, 0.2), (5000, 0.1)])
        for (speed, pitch) in [(Float(1), Float(1.25)), (1.25, 1.25), (0.8, 0.8), (1, 0.8)] {
            let a = runEngine(TimePitchEngine(sampleRate: Double(sr), channels: 2, speed: speed, pitch: pitch), [x, x])
            var rnd = Rng(state: 3)
            let b = runEngine(TimePitchEngine(sampleRate: Double(sr), channels: 2, speed: speed, pitch: pitch), [x, x],
                              block: { 1 + rnd.int(3000) }, readChunk: 333)
            XCTAssertEqual(maxDiff(a, b), 0, "speed=\(speed) pitch=\(pitch)")
        }
        // Prozessor: Blöcke 37 / 512 / 4096 / zufällig gegen einen einzigen Block – bitgleich
        var rng = Rng(state: 4)
        var l = tones(sr, 2.0, [(220, 0.3), (1234, 0.2), (5000, 0.1)])
        for i in sr..<(sr + sr / 5) { l[i] += Float(rng.gaussian() * 0.2 * exp(-Double(i - sr) / 1500)) }
        let r = tones(sr, 2.0, [(330, 0.25), (2345, 0.15)])
        for st in [2.0, -7.0] {
            let reference = runProcessor(processor(semitones: st), [l, r], block: { Int.max })
            for size in [37, 512, 4096] {
                XCTAssertEqual(maxDiff(reference, runProcessor(processor(semitones: st), [l, r], block: { size })), 0, "\(st) HT, Block \(size)")
            }
            var rnd = Rng(state: 99)
            XCTAssertEqual(maxDiff(reference, runProcessor(processor(semitones: st), [l, r], block: { 1 + rnd.int(4096) })), 0, "\(st) HT, zufällig")
        }
    }

    func testInPlace_gleichesErgebnis() {
        let sr = 44100
        let x = tones(sr, 1.5, [(440, 0.3), (1500, 0.1)])
        let reference = runProcessor(processor(semitones: 3), [x, x], block: { 512 })
        let p = processor(semitones: 3)
        let buf = Planes([x, x])
        let ip = UnsafeMutablePointer<UnsafePointer<Float>>.allocate(capacity: 2)
        let op = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: 2)
        defer {
            ip.deallocate()
            op.deallocate()
        }
        var pos = 0
        while pos < buf.frames {
            let n = min(512, buf.frames - pos)
            for c in 0..<2 {
                ip[c] = UnsafePointer(buf.mem[c] + pos)
                op[c] = buf.mem[c] + pos
            }
            p.process(input: UnsafePointer(ip), output: UnsafePointer(op), frames: n)
            pos += n
        }
        XCTAssertEqual(maxDiff(reference, buf.array()), 0)
    }

    func testReset_verhaeltSichWieNeueInstanz() {
        let sr = 48000
        let a = tones(sr, 1.0, [(330, 0.4)])
        var noise = Rng(state: 5)
        var b = [Float](repeating: 0, count: sr)
        for i in 0..<sr {
            let burst: Double = 0.2 * noise.gaussian() * exp(-Double(i) / 4000)
            let tone: Double = 0.2 * sin(2 * Double.pi * 777 * Double(i) / Double(sr))
            b[i] = Float(burst + tone)
        }
        for (speed, pitch) in [(Float(1), semis(4)), (semis(-4), semis(-4))] {
            let reused = TimePitchEngine(sampleRate: Double(sr), channels: 2, speed: speed, pitch: pitch)
            _ = runEngine(reused, [a, a])
            reused.reset()
            let afterReset = runEngine(reused, [b, b])
            let fresh = runEngine(TimePitchEngine(sampleRate: Double(sr), channels: 2, speed: speed, pitch: pitch), [b, b])
            XCTAssertEqual(maxDiff(fresh, afterReset), 0, "Engine speed=\(speed) pitch=\(pitch)")
        }
        for st in [4.0, -4.0, 12.0] {
            let reused = processor(sr, semitones: st)
            _ = runProcessor(reused, [a, a], block: { 700 })
            reused.reset()
            let afterReset = runProcessor(reused, [b, b], block: { 512 })
            let fresh = runProcessor(processor(sr, semitones: st), [b, b], block: { 512 })
            XCTAssertEqual(maxDiff(fresh, afterReset), 0, "Prozessor \(st) HT")
        }
    }

    func testStilleBleibtStille() {
        let silence = [Float](repeating: 0, count: 44100)
        let out = process([silence, silence], 44100, speed: 1, pitch: semis(7))
        XCTAssertTrue(out.allSatisfy { $0.allSatisfy { $0 == 0 } }) // Float: exakt 0 (kein Dither)
        let y = runProcessor(processor(semitones: -3), [silence, silence], block: { 512 })
        XCTAssertTrue(y.allSatisfy { $0.allSatisfy { $0 == 0 } })
    }

    // ------------------------------------------------------------------ Modus „Schallplatte“ (Resampling)

    func testSchallplatte_verschiebtTonSauberUndHaeltPegel() {
        let sr = 44100
        for st in [5.0, -7.0] {
            let p = semis(st)
            for f in [1000.0, 10000.0] {
                if f * Double(p) > 0.9 * Double(sr) / 2 { continue }
                let x = tones(sr, 3.0, [(f, 0.5)])
                let y = process([x, x], sr, speed: p, pitch: p)[0]
                let ref = purity(spectrum(x, sr, sr, sr), [f]).levels[0]
                let (a, b) = middle(y, sr)
                let (pur, levels) = purity(spectrum(y, a, b - a, sr), [f * Double(p)])
                // gemessen (Float) ≈ 89–100 dB; Android 16 Bit ≈ 84–86 dB (Dither); Sonic: 20 dB bei 10 kHz
                XCTAssertGreaterThan(pur, 80, "Störabstand \(st) HT, \(f) Hz")
                XCTAssertEqual(db(levels[0] / ref), 0, accuracy: 0.1, "Pegel \(st) HT, \(f) Hz")
            }
        }
    }

    func testSchallplatte_unterdruecktSpiegelfrequenzen() {
        // 18 kHz um +5 Halbtöne → 24 kHz, oberhalb der Nyquistfrequenz (22,05 kHz): muss verschwinden.
        let sr = 44100
        let p = semis(5)
        let x = tones(sr, 3.0, [(18000, 0.5)])
        let y = process([x, x], sr, speed: p, pitch: p)[0]
        let (a, b) = middle(y, sr)
        var inEnergy = 0.0
        var outEnergy = 0.0
        for i in a..<b {
            inEnergy += Double(x[i] * x[i])
            outEnergy += Double(y[i] * y[i])
        }
        // gemessen ≈ −103 dB (Float); Android 16 Bit ≈ −86 dB; Sonic: −0 bis −4 dB
        XCTAssertLessThan(db(outEnergy / inEnergy), -80)
    }

    // ------------------------------------------------------------------ Modus „Tonhöhe“ (Tempo bleibt)

    func testTonhoehe_verschiebtAkkordOhneTempoaenderung() {
        let sr = 44100
        let chord = [(261.63, 0.15), (329.63, 0.12), (392.0, 0.12), (523.25, 0.08), (1046.5, 0.04), (2093.0, 0.02)]
        for st in [4.0, -5.0] {
            let p = semis(st)
            let x = tones(sr, 3.0, chord)
            let out = process([x, x], sr, speed: 1, pitch: p)
            XCTAssertEqual(out[0].count, x.count)
            let (a, b) = middle(out[0], sr)
            let (pur, _) = purity(spectrum(out[0], a, b - a, sr), chord.map { $0.0 * Double(p) })
            // gemessen ≈ 45–46 dB; Sonic: 1–6 dB
            XCTAssertGreaterThan(pur, 35, "Akkord \(st) HT")
        }
    }

    func testTonhoehe_monoUndAndereAbtastraten() {
        for (sr, ch) in [(48000, 2), (96000, 2), (22050, 1), (44100, 1)] {
            let p = semis(4)
            let chord = [(220.0, 0.2), (277.18, 0.15), (329.63, 0.15), (880.0, 0.05)]
            let x = tones(sr, 2.5, chord)
            let out = process(ch == 2 ? [x, x] : [x], sr, speed: 1, pitch: p)
            XCTAssertEqual(out[0].count, x.count)
            let (a, b) = middle(out[0], sr)
            let (pur, _) = purity(spectrum(out[0], a, b - a, sr), chord.map { $0.0 * Double(p) })
            XCTAssertGreaterThan(pur, 35, "\(sr) Hz, \(ch) Kanäle") // gemessen ≈ 52 dB
        }
    }

    func testStereobild_bleibtErhalten() {
        let sr = 44100
        let x = tones(sr, 2.0, [(300, 0.3), (2500, 0.1)])
        let minus = x.map { -$0 }
        for (speed, pitch) in [(Float(1), semis(3)), (semis(3), semis(3))] {
            let out = process([x, minus], sr, speed: speed, pitch: pitch)
            var lr = 0.0, ll = 0.0, rr = 0.0
            for i in (sr / 2)..<(out[0].count - sr / 2) {
                lr += Double(out[0][i] * out[1][i])
                ll += Double(out[0][i] * out[0][i])
                rr += Double(out[1][i] * out[1][i])
            }
            XCTAssertLessThan(lr / (ll * rr).squareRoot(), -0.999, "Korrelation speed=\(speed)")
        }
    }

    func testAnschlaege_bleibenScharf() {
        // Abklingende Rauschimpulse alle 0,5 s; Energie kurz vor dem Anschlag = „Vorecho“.
        let sr = 44100
        var x = [Float](repeating: 0, count: sr * 5)
        var rnd = Rng(state: 7)
        let onsets = (1..<9).map { $0 * sr / 2 }
        for o in onsets {
            for i in 0..<(sr / 5) { x[o + i] += Float(rnd.gaussian() * 0.25 * exp(-Double(i) / (0.03 * Double(sr)))) }
        }
        for st in [5.0, -5.0] {
            let y = process([x, x], sr, speed: 1, pitch: semis(st))[0]
            var nearPre = 0.0, farPre = 0.0, post = 0.0
            for c in onsets {
                for i in (c - Int(0.005 * Double(sr)))..<(c - Int(0.001 * Double(sr))) { nearPre += Double(y[i] * y[i]) }
                for i in (c - Int(0.045 * Double(sr)))..<(c - Int(0.005 * Double(sr))) { farPre += Double(y[i] * y[i]) }
                for i in c..<(c + Int(0.04 * Double(sr))) { post += Double(y[i] * y[i]) }
            }
            // gemessen: 1–5 ms vorher −21,6 (+5) / −34,1 (−5) dB, 5–45 ms vorher −37,8 / −36,5 dB
            XCTAssertLessThan(db(nearPre / post), -15, "\(st) HT, 1–5 ms vor dem Anschlag")
            XCTAssertLessThan(db(farPre / post), -28, "\(st) HT, 5–45 ms vor dem Anschlag")
        }
    }

    func testLautesMaterial_wirdBegrenztStattGeclippt() {
        // Vollaussteuerung mit vielen Teiltönen: Phase-Vocoder/Filter dürfen Spitzen anheben – der
        // Ausgangsbegrenzer muss das abfangen, ohne hart zu clippen.
        let sr = 44100
        let x = tones(sr, 3.0, (1...12).map { (110.0 * Double($0) * 1.01, 1.0 / 12) })
        let pk = peak(x)
        let loud = x.map { $0 / pk }
        for (speed, pitch) in [(Float(1), semis(7)), (1, semis(-7)), (semis(7), semis(7))] {
            let out = process([loud, loud], sr, speed: speed, pitch: pitch)
            let m = max(peak(out[0]), peak(out[1]))
            XCTAssertLessThan(m, 0.99, "speed=\(speed) pitch=\(pitch)") // Begrenzer + weiches Knie: höchstens ≈ 0,9868
        }
    }

    // ------------------------------------------------------------------ Render-Block-Betrieb (macOS)

    func testSinus440_frequenzGenauVerschoben() {
        let sr = 44100
        let x = tones(sr, 3.5, [(440, 0.5)])
        for st in [0.5, -0.1, 12.0, -12.0] {
            let p = processor(sr, semitones: st)
            let y = runProcessor(p, [x, x], block: { 512 })[0]
            let expected = 440 * Double(semis(st))
            let from = p.latencyFrames + sr / 2
            let fz = zeroCrossingFrequency(y, from: from, to: from + 2 * sr, sr: sr)
            let ff = fftFrequency(y, from: from, n: 65536, sr: sr)
            let (pur, _) = purity(spectrum(y, from, 65536, sr), [expected])
            print("TimePitch Sinus 440 Hz \(st) HT: soll \(fmt(expected, 3)) Hz, gemessen \(fmt(fz, 4)) Hz (Nulldurchgänge) / " +
                  "\(fmt(ff, 3)) Hz (FFT), Störabstand \(fmt(pur)) dB")
            // gemessen: Abweichung < 0,003 Hz, Störabstand 89–107 dB
            XCTAssertEqual(fz, expected, accuracy: 0.05, "\(st) HT")
            XCTAssertEqual(ff, expected, accuracy: 0.05, "\(st) HT")
            XCTAssertGreaterThan(pur, 70, "\(st) HT")
        }
    }

    func testAkkordNaheVollaussteuerung_keinClipping_pegelWieEingang() {
        let sr = 44100
        let raw = tones(sr, 3.0, [(440, 1), (554.37, 1), (659.25, 1)])
        let rawPeak = peak(raw)
        for level in [0.99, 0.5] {
            let x = raw.map { Float(Double($0) / Double(rawPeak) * level) }
            let inPeak = Double(peak(x))
            for st in [2.0, -5.0, 12.0, -12.0] {
                let y = runProcessor(processor(sr, semitones: st), [x, x], block: { 512 })
                let outPeak = Double(max(peak(y[0]), peak(y[1])))
                let rel = 20 * log10(outPeak / inPeak)
                print("TimePitch Akkord Spitze \(fmt(inPeak, 3)) \(st) HT: Ausgang \(fmt(outPeak, 4)) (\(fmt(rel, 2)) dB)")
                XCTAssertLessThan(outPeak, 1.0, "\(st) HT")
                XCTAssertLessThan(rel, 0.5, "\(st) HT") // gemessen: −0,03 … +0,01 dB
            }
        }
    }

    func testAkkordPlus2Halbtoene_verzerrungsanteil() {
        // Anteil der Energie außerhalb von ±2,7 Hz um die drei erwarteten Teiltöne (65536er-FFT, ±4 Bins).
        let sr = 44100
        let chord = [(440.0, 0.25), (554.37, 0.25), (659.25, 0.25)]
        let x = tones(sr, 3.5, chord)
        for st in [2.0, -2.0] {
            let p = processor(sr, semitones: st)
            let y = runProcessor(p, [x, x], block: { 512 })[0]
            let expected = chord.map { $0.0 * Double(semis(st)) }
            let (pur, _) = purity(spectrum(y, p.latencyFrames + sr / 2, 65536, sr), expected, lobe: 4)
            print("TimePitch Akkord \(st) HT: Verzerrungs-/Rauschanteil \(fmt(-pur)) dB")
            XCTAssertGreaterThan(pur, 45, "\(st) HT") // gemessen: 59,5 dB (+2) / 60,4 dB (−2)
        }
    }

    func testZeitbezug_anschlagErscheintNachLatenz() {
        let sr = 44100
        var x = [Float](repeating: 0, count: sr * 2)
        var rnd = Rng(state: 21)
        let t0 = sr / 2 + 1234
        for i in 0..<(sr / 4) { x[t0 + i] = Float(rnd.gaussian() * 0.3 * exp(-Double(i) / 2000)) }
        for st in [5.0, -12.0] {
            let p = processor(sr, semitones: st)
            let y = runProcessor(p, [x, x], block: { 512 })[0]
            // erstes 1-ms-Fenster mit mehr als 10 % der größten Fensterenergie
            let window = 44
            var energies: [(Int, Double)] = []
            var i = 0
            while i + window < y.count {
                var e = 0.0
                for j in i..<(i + window) { e += Double(y[j] * y[j]) }
                energies.append((i, e))
                i += 4
            }
            let maxE = energies.map(\.1).max() ?? 0
            let found = energies.first { $0.1 > 0.1 * maxE }?.0 ?? -1
            let offsetMs = Double(found - (t0 + p.latencyFrames)) / Double(sr) * 1000
            XCTAssertEqual(offsetMs, 0, accuracy: 5, "\(st) HT") // gemessen: −0,5 … −1,1 ms
        }
    }

    func testUeberblenden_beimTonhoehenwechselOhneLuecke() {
        let sr = 44100
        let x = tones(sr, 4, [(440, 0.2), (554.37, 0.2), (659.25, 0.2)])
        let old = processor(sr, semitones: 2)
        let new = processor(sr, semitones: 2.1)
        let inp = Planes([x, x])
        let out = Planes(channels: 2, frames: x.count)
        let ip = UnsafeMutablePointer<UnsafePointer<Float>>.allocate(capacity: 2)
        let op = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: 2)
        defer {
            ip.deallocate()
            op.deallocate()
        }
        let switchAt = 2 * sr - (2 * sr) % 512 // Blockgrenze
        var finishedAt = -1
        var pos = 0
        while pos < x.count {
            let n = min(512, x.count - pos)
            for c in 0..<2 {
                ip[c] = UnsafePointer(inp.mem[c] + pos)
                op[c] = out.mem[c] + pos
            }
            if pos < switchAt {
                old.process(input: UnsafePointer(ip), output: UnsafePointer(op), frames: n)
            } else if finishedAt < 0 {
                if old.process(input: UnsafePointer(ip), output: UnsafePointer(op), frames: n, crossfadingTo: new) {
                    finishedAt = pos + n
                }
            } else {
                new.process(input: UnsafePointer(ip), output: UnsafePointer(op), frames: n)
            }
            pos += n
        }
        XCTAssertGreaterThan(finishedAt, switchAt)
        let y = out.array()[0]
        // keine Lücke: RMS in 10-ms-Fenstern nach dem Wechsel nie mehr als 6 dB unter dem größten Wert
        var lo = Double.infinity, hi = 0.0
        let w = sr / 100
        for s in stride(from: switchAt, to: switchAt + sr / 2, by: w) {
            var e = 0.0
            for i in s..<(s + w) { e += Double(y[i] * y[i]) }
            lo = min(lo, (e / Double(w)).squareRoot())
            hi = max(hi, (e / Double(w)).squareRoot())
        }
        XCTAssertGreaterThan(lo, 0.5 * hi) // gemessen: −2,6 dB (Schwebung des Akkords allein: −2,0 dB)
        // nach dem Übergang bitgleich zu einer neuen Instanz ab dem Wechselpunkt
        let tail = runProcessor(processor(sr, semitones: 2.1), [Array(x[switchAt...]), Array(x[switchAt...])], block: { 512 })[0]
        var d: Float = 0
        for i in (finishedAt - switchAt)..<tail.count { d = max(d, abs(tail[i] - y[switchAt + i])) }
        XCTAssertEqual(d, 0)
    }

    func testRechenaufwand_60SekundenStereo() {
        // Nur Ausgabe, keine harte Grenze (Debug-Builds/CI-Rechner). Release unter Linux gemessen: 53–129× Echtzeit.
        let sr = 44100
        let seconds = 60
        var rnd = Rng(state: 8)
        var l = tones(sr, Double(seconds), [(110, 0.1), (220, 0.08), (440, 0.08), (554.37, 0.06), (659.25, 0.06), (1318.5, 0.03)])
        var r = l
        for o in stride(from: 0, to: sr * seconds - sr / 5, by: sr / 2) {
            for i in 0..<(sr / 10) {
                let e = exp(-Double(i) / 800)
                l[o + i] += Float(rnd.gaussian() * 0.1 * e)
                r[o + i] += Float(rnd.gaussian() * 0.1 * e)
            }
        }
        let inp = Planes([l, r])
        let out = Planes(channels: 2, frames: inp.frames)
        let ip = UnsafeMutablePointer<UnsafePointer<Float>>.allocate(capacity: 2)
        let op = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: 2)
        defer {
            ip.deallocate()
            op.deallocate()
        }
        for st in [0.5, 12.0] {
            let p = processor(sr, semitones: st)
            let start = ProcessInfo.processInfo.systemUptime
            var pos = 0
            while pos < inp.frames {
                let n = min(512, inp.frames - pos)
                for c in 0..<2 {
                    ip[c] = UnsafePointer(inp.mem[c] + pos)
                    op[c] = out.mem[c] + pos
                }
                p.process(input: UnsafePointer(ip), output: UnsafePointer(op), frames: n)
                pos += n
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            print("TimePitch Rechenaufwand \(st) HT: \(seconds) s Stereo in \(fmt(elapsed, 3)) s → \(fmt(Double(seconds) / elapsed))× Echtzeit")
            XCTAssertEqual(p.underrunFrames, 0)
        }
    }
}
