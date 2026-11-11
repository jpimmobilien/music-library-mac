import XCTest
import AVFoundation
import Accelerate
import MLCore
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
    private func render(_ input: AVAudioPCMBuffer, seconds: Double? = nil, nativePitch: Bool = false, _ configure: (inout AudioEngine.Parameters) -> Void = { _ in }) throws -> [Float] {
        let audio = AudioEngine(offlineFormat: format, nativePitch: nativePitch)
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

    /// v2: Feinregler und ±-Tasten (Mini-Player, großer Player) – die Werte aus `PitchSettings` kommen
    /// tatsächlich im Klang an (Weg wie im `PlayerService`: Halbtöne → Cent → AVAudioUnitTimePitch).
    func testPitchHalfSemitoneFromSettingsIsAudible() throws {
        let settings = PitchSettings().withSemitones(PitchSettings.fineStep * 5)   // 5 Feinschritte = +0,5 Halbtöne
        let out = steady(try render(sine(440, amplitude: 0.4, seconds: 2.0)) { $0.pitchCents = settings.pitchCents })
        let f = frequency(out)
        let expected = 440 * pow(2, 0.5 / 12)   // 452,9 Hz
        print("[Audio] Tonhöhe +0,5 Halbtöne: \(f) Hz (erwartet \(expected))")
        XCTAssertEqual(f, expected, accuracy: 3)
    }

    func testPitchOneFineStepDownIsAudible() throws {
        let settings = PitchSettings().withSemitones(-PitchSettings.fineStep)   // −0,1 Halbtöne = −10 Cent
        XCTAssertEqual(settings.pitchCents, -10, accuracy: 0.001)
        let out = steady(try render(sine(440, amplitude: 0.4, seconds: 4.0)) { $0.pitchCents = settings.pitchCents })
        let f = frequency(out)
        let expected = 440 * pow(2, -0.1 / 12)   // 437,5 Hz
        print("[Audio] Tonhöhe −0,1 Halbtöne: \(f) Hz (erwartet \(expected))")
        XCTAssertEqual(f, expected, accuracy: 1.2)
        XCTAssertLessThan(f, 439.3, "ein Feinschritt muss hörbar tiefer sein als das Original")
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

    /// 2.2.1: Titelwechsel zwischen verschiedenen Formaten bei laufender Engine (Stereo/Mono, 44,1/48/96 kHz),
    /// genau wie `PlayerService.loadCurrent` (Player stoppen → neu verbinden → starten). Unter macOS 13 brach
    /// AVAudioEngine dabei mit einer Ausnahme ab (Absturz beim Übergang zum nächsten Titel). Danach muss Klang da sein –
    /// mit unveränderter Tonhöhe und mit eigener Tonhöhen-Unit (+2 Halbtöne).
    func testTrackChangeBetweenFormatsWhileRunning() throws {
        for cents: Float in [0, 200] {
            let audio = AudioEngine(offlineFormat: format)
            XCTAssertTrue(audio.isOffline)
            audio.connect(format: format)
            var p = AudioEngine.Parameters()
            p.pitchCents = cents
            audio.apply(p, force: true)
            try audio.start()
            let out = AVAudioPCMBuffer(pcmFormat: audio.engine.manualRenderingFormat, frameCapacity: 4096)!
            let formats: [(Double, AVAudioChannelCount)] = [(44_100, 2), (48_000, 1), (96_000, 2), (44_100, 1), (192_000, 2), (22_050, 2), (44_100, 2)]
            for (rate, ch) in formats {
                let f = AVAudioFormat(standardFormatWithSampleRate: rate, channels: ch)!
                let buf = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: AVAudioFrameCount(rate * 0.7))!
                buf.frameLength = buf.frameCapacity
                for c in 0..<Int(ch) {
                    for i in 0..<Int(buf.frameLength) { buf.floatChannelData![c][i] = Float(0.3 * sin(2 * Double.pi * 440 * Double(i) / rate)) }
                }
                audio.stopPlayer()
                audio.connect(format: f)
                try audio.start()
                audio.player.scheduleBuffer(buf, at: nil)
                audio.player.play()
                var samples: [Float] = []
                for _ in 0..<48 {   // kleine Zyklen wie bei der Ausgabe (512 Frames), ≈ 0,56 s
                    let status = try audio.engine.renderOffline(512, to: out)
                    XCTAssertEqual(status, .success)
                    samples.append(contentsOf: UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
                }
                let level = rms(samples[9000..<22000])
                print("[Audio] Titelwechsel auf \(Int(rate)) Hz, \(ch) Kanal/Kanäle, Tonhöhe \(Int(cents)) Cent: Pegel \(level)")
                XCTAssertGreaterThan(level, 0.1, "kein Klang nach Wechsel auf \(rate) Hz, \(ch) Kanäle, \(cents) Cent")
            }
            audio.player.stop()
            audio.stopEngine()
        }
    }

    func testDiagnoseHighRate() throws {
        let seqs: [[(Double, AVAudioChannelCount)]] = [[(44_100, 2), (48_000, 1), (96_000, 2)], [(48_000, 1), (96_000, 2)], [(44_100, 2), (96_000, 2)], [(48_000, 2), (96_000, 2)], [(48_000, 1), (44_100, 2)]]
        for native in [false, true] {
            for seq in seqs {
                let audio = AudioEngine(offlineFormat: format, nativePitch: native)
                audio.connect(format: format)
                audio.apply(AudioEngine.Parameters(), force: true)
                try audio.start()
                var line = "[Audio] Diagnose native=\(native):"
                for (rate, ch) in seq {
                    let f = AVAudioFormat(standardFormatWithSampleRate: rate, channels: ch)!
                    audio.stopPlayer()
                    audio.connect(format: f)
                    try audio.start()
                    let buf = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: AVAudioFrameCount(rate * 0.7))!
                    buf.frameLength = buf.frameCapacity
                    for c in 0..<Int(ch) { for i in 0..<Int(buf.frameLength) { buf.floatChannelData![c][i] = Float(0.3 * sin(2 * Double.pi * 440 * Double(i) / rate)) } }
                    audio.player.scheduleBuffer(buf, at: nil)
                    audio.player.play()
                    let out = AVAudioPCMBuffer(pcmFormat: audio.engine.manualRenderingFormat, frameCapacity: 4096)!
                    var samples: [Float] = []
                    var statuses: Set<Int> = []
                    for _ in 0..<48 {
                        let st = try audio.engine.renderOffline(512, to: out)
                        statuses.insert(st.rawValue)
                        samples.append(contentsOf: UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
                    }
                    let pf = audio.player.outputFormat(forBus: 0)
                    line += " | \(Int(rate))/\(ch): Pegel \(rms(samples[9000..<22000])) St \(statuses) Player \(Int(pf.sampleRate))/\(pf.channelCount) AU \(audio.pitchAU?.diagnostics ?? "-") lastRender \(audio.player.lastRenderTime?.sampleTime ?? -1) playing \(audio.player.isPlaying)"
                }
                print(line)
                audio.player.stop()
                audio.stopEngine()
            }
        }
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

    /// v2.1: Die Pegelanalyse greift jeden Renderzyklus hinter dem Limiter ab (Ringpuffer) und rechnet auf Abruf.
    func testLevelMeterFollowsRenderedAudio() throws {
        let audio = AudioEngine(offlineFormat: format)
        audio.connect(format: format)
        XCTAssertNil(audio.levels.take(), "ausgeschaltet → keine Werte")
        audio.levels.enabled = true
        audio.player.scheduleBuffer(sine(1000, amplitude: 0.5, seconds: 1.0), at: nil)
        try audio.start()
        audio.player.play()
        let out = AVAudioPCMBuffer(pcmFormat: audio.engine.manualRenderingFormat, frameCapacity: 4096)!
        var rendered = 0
        while rendered < 22_050 {
            _ = try audio.engine.renderOffline(512, to: out)   // kleine Zyklen wie bei der Ausgabe
            rendered += 512
        }
        guard let values = audio.levels.take() else { return XCTFail("keine Pegelwerte") }
        XCTAssertEqual(values.count, LevelMeter.bandCount + 2)
        let bands = Array(values.prefix(LevelMeter.bandCount))
        let loudest = bands.indices.max { bands[$0] < bands[$1] }!
        print("[Audio] Pegel 1 kHz −6 dBFS: Bänder \(bands.map { String(format: "%.2f", $0) }.joined(separator: " ")), L \(values[16]), R \(values[17])")
        // 1 kHz liegt im Band 8 (50 Hz · 280^(8/16) ≈ 837 Hz … 50 Hz · 280^(9/16) ≈ 1,2 kHz)
        XCTAssertEqual(loudest, 8)
        XCTAssertEqual(bands[8], 0.9, accuracy: 0.05, "−6 dBFS → 0,9")
        XCTAssertLessThan(bands[2], 0.45, "ferne Bänder bleiben niedrig")
        XCTAssertGreaterThan(values[LevelMeter.bandCount], 0.8)   // links ≈ −6 dBFS → 0,9
        // Kosten der Analyse im Hauptthread (je Bild höchstens einmal, 30 Bilder/s)
        var spent: TimeInterval = 0
        for _ in 0..<100 {
            _ = try audio.engine.renderOffline(512, to: out)
            let t0 = Date()
            _ = audio.levels.take()
            spent += Date().timeIntervalSince(t0)
        }
        print("[Audio] Pegelanalyse je Bild: \(String(format: "%.3f", spent / 100 * 1000)) ms")
        XCTAssertLessThan(spent / 100, 0.002, "Analyse muss deutlich unter 2 ms je Bild bleiben")
        // Weitere Abrufe ohne neue Abtastwerte: kurz der letzte Stand, danach Nullen (Anzeige klingt aus)
        XCTAssertNotNil(audio.levels.take())
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(audio.levels.take()?.max() ?? 1, 0, "ohne Audio → Ruhe")
        audio.player.stop()
        audio.stopEngine()
    }

    /// v2.1: Jedes eingebaute Preset kommt im Klang an – gemessen an fünf Bandmitten gegen die Filterformel
    /// (`EqResponse`) inklusive automatischer Aussteuerung. Ausgeschalteter EQ ist neutral.
    func testEveryBuiltInPresetIsAudible() throws {
        let probes = [0, 2, 4, 6, 8]   // 31 Hz, 125 Hz, 500 Hz, 2 kHz, 8 kHz
        var baseline: [Int: Float] = [:]
        for b in probes {
            baseline[b] = rms(steady(try render(sine(Double(EqBands.frequencies[b]), amplitude: 0.05, seconds: 1.0))))
        }
        let q = EqBands.q
        let bandwidth = Float(2 / log(2.0) * asinh(1 / (2 * q)))
        for preset in EqPresets.all {
            let fx = AudioEffectsSettings(eqEnabled: false).withPreset(preset)   // Preset schaltet den EQ ein
            XCTAssertTrue(fx.eqEnabled)
            var line: [String] = []
            for b in probes {
                let f = Double(EqBands.frequencies[b])
                let out = rms(steady(try render(sine(f, amplitude: 0.05, seconds: 1.0)) { p in
                    p.bandGains = fx.effectiveBands
                    p.bandwidth = bandwidth
                    p.headroomDb = fx.headroomDb
                }))
                let measured = db(out / baseline[b]!)
                let expected = Float(EqResponse.equalizerDb(f, bands: fx.effectiveBands)) + fx.headroomDb
                line.append(String(format: "%.0f Hz %+.1f/%+.1f", f, measured, expected))
                XCTAssertEqual(measured, expected, accuracy: 1.5, "Preset \(preset.name) bei \(f) Hz")
            }
            print("[Audio] Preset \(preset.name) (gemessen/erwartet dB): " + line.joined(separator: " · "))
        }
        // EQ aus → neutral, auch mit Preset-Bändern
        let off = AudioEffectsSettings(eqEnabled: true).withPreset(EqPresets.rock)
        var disabled = off
        disabled.eqEnabled = false
        XCTAssertTrue(disabled.effectiveBands.allSatisfy { $0 == 0 })
    }

    // MARK: - v2.1 Klangqualität der Tonhöhe

    private func chord(_ freqs: [Double], amplitude: Float, seconds: Double) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
        buffer.frameLength = n
        for c in 0..<2 {
            let p = buffer.floatChannelData![c]
            for i in 0..<Int(n) {
                var v = 0.0
                for f in freqs { v += sin(2 * Double.pi * f * Double(i) / sampleRate) }
                p[i] = amplitude * Float(v / Double(freqs.count))
            }
        }
        return buffer
    }

    /// Störanteil in dB: Energie außerhalb von ±`width` Hz um die erwarteten Teiltöne relativ zur Energie der Teiltöne
    /// (je kleiner, desto sauberer). Hann-Fenster über 2^16 Abtastwerte des eingeschwungenen Bereichs.
    private func distortionDb(_ s: ArraySlice<Float>, expected: [Double], width: Double = 12) -> Float {
        let n = 1 << 16
        precondition(s.count >= n)
        var x = Array(s.prefix(n))
        var w = [Float](repeating: 0, count: n)
        vDSP_hann_window(&w, vDSP_Length(n), Int32(vDSP_HANN_DENORM))
        vDSP_vmul(x, 1, w, 1, &x, 1, vDSP_Length(n))
        let log2n = vDSP_Length(16)
        let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        defer { vDSP_destroy_fftsetup(setup) }
        var re = [Float](repeating: 0, count: n / 2), im = [Float](repeating: 0, count: n / 2)
        var power = [Float](repeating: 0, count: n / 2)
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                x.withUnsafeBufferPointer { xp in
                    xp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2)) }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                power.withUnsafeMutableBufferPointer { vDSP_zvmags(&split, 1, $0.baseAddress!, 1, vDSP_Length(n / 2)) }
            }
        }
        power[0] = 0
        let binHz = sampleRate / Double(n)
        var wanted: Float = 0, other: Float = 0
        for (i, pw) in power.enumerated() where i > 0 {
            let f = Double(i) * binHz
            if f < 30 { continue }
            if expected.contains(where: { abs($0 - f) <= width }) { wanted += pw } else { other += pw }
        }
        return 10 * log10(max(other, 1e-20) / max(wanted, 1e-20))
    }

    /// Tonhöhe +2 Halbtöne auf einen Dur-Akkord (stehende Töne): Störanteil beider Verfahren wird ausgegeben;
    /// die portierte Verarbeitung muss sauber bleiben (< −40 dB) und darf nicht übersteuern.
    func testPitchQualityStationaryChord() throws {
        let freqs = [261.63, 329.63, 392.0, 523.25]
        let factor = pow(2.0, 2.0 / 12)
        let expected = freqs.map { $0 * factor }
        for (name, native) in [("Apple TimePitch (2.0)", true), ("Android-Verfahren (2.1)", false)] {
            let out = try render(chord(freqs, amplitude: 0.6, seconds: 4.0), nativePitch: native) { $0.pitchCents = 200 }
            let steadyPart = out[Int(0.5 * sampleRate)..<Int(3.6 * sampleRate)]
            let d = distortionDb(steadyPart, expected: expected)
            let pk = peak(steadyPart)
            print("[Pitch] Akkord +2 Halbtöne, \(name): Störanteil \(String(format: "%.1f", d)) dB, Spitze \(String(format: "%.3f", pk))")
            XCTAssertLessThanOrEqual(pk, 1.0, "\(name): kein Übersteuern")
            if !native { XCTAssertLessThan(d, -40, "Android-Verfahren: sauberer Akkord") }
        }
    }

    /// Schlagzeugartige Anschläge (abklingendes Rauschen alle 250 ms): Ein Phasen-Vocoder verschmiert Anschläge nach
    /// vorne („Vorecho“, klingt verwaschen/verzerrt). Gemessen wird die Energie 3–30 ms vor jedem Anschlag relativ zu
    /// den 27 ms danach – je kleiner, desto knackiger. Das Android-Verfahren erkennt Anschläge und setzt die Phasen
    /// zurück; es muss hier deutlich besser sein als Apples TimePitch.
    func testPitchTransientsLessSmearedThanAppleTimePitch() throws {
        let n = Int(4.0 * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        buffer.frameLength = AVAudioFrameCount(n)
        var seed: UInt32 = 12345
        for i in 0..<n {
            let t = Double(i % Int(0.25 * sampleRate)) / sampleRate
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Float(Int32(bitPattern: seed)) / Float(Int32.max)
            let v = 0.5 * noise * Float(exp(-t / 0.015))
            buffer.floatChannelData![0][i] = v
            buffer.floatChannelData![1][i] = v
        }
        var results: [Bool: Float] = [:]
        for native in [true, false] {
            for cents: Float in [200, -300] {
                let out = try render(buffer, nativePitch: native) { $0.pitchCents = cents }
                let e = preEchoDb(out)
                if cents == 200 { results[native] = e }
                print("[Pitch] Anschläge \(cents > 0 ? "+" : "")\(Int(cents / 100)) Halbtöne, \(native ? "Apple TimePitch (2.0)" : "Android-Verfahren (2.1)"): Vorecho \(String(format: "%.1f", e)) dB")
            }
        }
        XCTAssertLessThan(results[false]!, results[true]! - 3, "Android-Verfahren muss Anschläge deutlich weniger verschmieren")
    }

    /// Mittleres Vorecho in dB (s. o.): Hüllkurve in 0,5-ms-Blöcken, je 250-ms-Abschnitt der stärkste Block = Anschlag.
    private func preEchoDb(_ out: [Float]) -> Float {
        let block = 22
        let blocks = out.count / block
        var env = [Float](repeating: 0, count: blocks)
        for b in 0..<blocks {
            var e: Float = 0
            for i in 0..<block { let v = out[b * block + i]; e += v * v }
            env[b] = e
        }
        let perSegment = Int(0.25 * sampleRate) / block
        var ratios: [Float] = []
        var start = Int(0.5 * sampleRate) / block
        while start + perSegment < blocks - perSegment {
            let seg = start..<(start + perSegment)
            let peakBlock = seg.max { env[$0] < env[$1] }!
            let pre = (peakBlock - 60)..<(peakBlock - 6)
            let post = peakBlock..<(peakBlock + 54)
            if pre.lowerBound >= 0 && post.upperBound < blocks {
                let a = pre.reduce(Float(0)) { $0 + env[$1] } / Float(pre.count)
                let b = post.reduce(Float(0)) { $0 + env[$1] } / Float(post.count)
                if b > 0 { ratios.append(a / b) }
            }
            start += perSegment
        }
        let mean = ratios.reduce(0, +) / Float(max(1, ratios.count))
        return 10 * log10(max(mean, 1e-12))
    }

    /// Bass, Stimme, Mischung: gleiche Frequenzgenauigkeit für tiefe (55 Hz) und hohe (3 kHz) Töne, Mono-Datei.
    func testPortedPitchAccuracyLowHighAndMono() throws {
        for f in [55.0, 3000.0] {
            let out = steady(try render(sine(f, amplitude: 0.5, seconds: 3.0)) { $0.pitchCents = -100 })
            let measured = frequency(out)
            let expected = f * pow(2, -1.0 / 12)
            print("[Pitch] \(f) Hz −1 Halbton: \(measured) Hz (erwartet \(expected))")
            XCTAssertEqual(measured, expected, accuracy: expected * 0.01)
        }
        // Mono-Kette
        let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let audio = AudioEngine(offlineFormat: format)
        audio.connect(format: mono)
        var p = AudioEngine.Parameters()
        p.pitchCents = 300
        audio.apply(p, force: true)
        let buffer = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: 88_200)!
        buffer.frameLength = 88_200
        for i in 0..<88_200 { buffer.floatChannelData![0][i] = 0.4 * Float(sin(2 * Double.pi * 440 * Double(i) / sampleRate)) }
        audio.player.scheduleBuffer(buffer, at: nil)
        try audio.start()
        audio.player.play()
        let out = AVAudioPCMBuffer(pcmFormat: audio.engine.manualRenderingFormat, frameCapacity: 4096)!
        var samples: [Float] = []
        while samples.count < 88_200 {
            _ = try audio.engine.renderOffline(4096, to: out)
            samples.append(contentsOf: UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
        }
        let f = frequency(steady(samples))
        print("[Pitch] Mono +3 Halbtöne: \(f) Hz (erwartet \(440 * pow(2, 3.0 / 12)))")
        XCTAssertEqual(f, 440 * pow(2, 3.0 / 12), accuracy: 6)
    }
}
