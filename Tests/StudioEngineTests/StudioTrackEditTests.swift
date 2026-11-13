import AVFoundation
import XCTest
import MLCore
import MLStudio
@testable import StudioEngine

/// „Titel bearbeiten“ (2.3) Ende zu Ende über den echten Exporter: Tempo, Tonhöhe, Umstimmen, Lautheit,
/// Begrenzer, Stille, Rumpelfilter, Equalizer, Auto-Tune, Tags; dazu die Analyse (Stimmung, Tonart, Lautheit).
final class StudioTrackEditTests: XCTestCase {
    /// Schreibt Stereo-Float-Samples als 24-Bit-WAV.
    static func writeWAV(_ url: URL, rate: Double, _ channels: [[Float]]) throws {
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels.count,
                                       AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                                       AVLinearPCMIsNonInterleaved: false]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let n = channels[0].count
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(n))!
        for c in 0..<channels.count { buffer.floatChannelData![c].update(from: channels[c], count: n) }
        buffer.frameLength = AVAudioFrameCount(n)
        try file.write(from: buffer)
    }

    static func tone(_ f: Double, amp: Float, seconds: Double, rate: Double) -> [Float] {
        (0..<Int(seconds * rate)).map { amp * Float(sin(2 * Double.pi * f * Double($0) / rate)) }
    }

    static func voice(_ f: Double, amp: Float, seconds: Double, rate: Double, harmonics: Int = 8) -> [Float] {
        (0..<Int(seconds * rate)).map { i in
            let ph = 2 * Double.pi * f * Double(i) / rate
            var v = 0.0
            for k in 1...harmonics { v += sin(Double(k) * ph) / Double(k) }
            return amp * Float(v * 0.6)
        }
    }

    static func loudness(_ a: TS.Audio) -> Double? {
        let m = LoudnessMeter(sampleRate: a.rate, channels: a.channels.count)
        let ptrs = a.channels.map { ch in ch.withUnsafeBufferPointer { $0.baseAddress! } }
        m.add(ptrs, frames: a.frames)
        return m.integratedLoudness
    }

    private func export(_ input: URL, _ edit: TrackEdit, format: StudioFormat = .wav, out: URL, trim: TrimRange? = nil,
                        copyTags: URL? = nil, metadata: StudioMetadata = StudioMetadata()) async throws -> (ExportResult, Double) {
        var options = ExportOptions.defaults(for: format)
        if format == .wav { options.pcmDepth = .int24 }
        let t0 = Date()
        let (r, _) = try await TS.export(ExportRequest(input: input, trim: trim, options: options, metadata: metadata, output: out,
                                                       copyTagsFrom: copyTags, edit: edit))
        return (r, Date().timeIntervalSince(t0) * 1000)
    }

    func testTempoPitchAndTuning() async throws {
        let dir = try TS.makeDir("edit-tempo")
        defer { try? FileManager.default.removeItem(at: dir) }
        let rate = 44_100.0
        let src = dir.appendingPathComponent("ton.wav")
        let x = Self.voice(220, amp: 0.3, seconds: 6, rate: rate)
        try Self.writeWAV(src, rate: rate, [x, x])
        struct Case { let name: String; let edit: TrackEdit; let seconds: Double; let pitch: Double }
        var cases: [Case] = []
        var e = TrackEdit(); e.speed = 1.25
        cases.append(Case(name: "Tempo 1,25 (Tonhöhe bleibt)", edit: e, seconds: 4.8, pitch: 220))
        e = TrackEdit(); e.speed = 0.8; e.keepPitch = false
        cases.append(Case(name: "Tempo 0,8 wie Schallplatte", edit: e, seconds: 7.5, pitch: 176))
        e = TrackEdit(); e.semitones = 2
        cases.append(Case(name: "+2 Halbtöne", edit: e, seconds: 6, pitch: 220 * pow(2, 2.0 / 12)))
        e = TrackEdit(); e.semitones = -5; e.cents = 30
        cases.append(Case(name: "−5 Halbtöne +30 Cent", edit: e, seconds: 6, pitch: 220 * pow(2, -4.7 / 12)))
        e = TrackEdit(); e.tuningFrom = 440; e.tuningTo = 432
        cases.append(Case(name: "440 → 432 Hz", edit: e, seconds: 6, pitch: 216))
        var failures: [String] = []
        for c in cases {
            let out = dir.appendingPathComponent("out-\(cases.firstIndex { $0.name == c.name }!).wav")
            let (r, ms) = try await export(src, c.edit, out: out)
            let a = try TS.readAll(out)
            let f = StudioHEAACTests.pitch(a.channels[0], rate: a.rate)
            let ok = abs(r.duration - c.seconds) < 0.02 && abs(f - c.pitch) < c.pitch * 0.006
            TS.log(String(format: "Bearbeiten %@ %@: Dauer %.3f s (erwartet %.3f), Grundton %.2f Hz (erwartet %.2f), %.0f ms",
                          ok ? "OK" : "FEHLER", c.name, r.duration, c.seconds, f, c.pitch, ms))
            if !ok { failures.append(c.name) }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: ", "))
    }

    func testEnhanceNormalizesTrimsSilenceAndLimits() async throws {
        let dir = try TS.makeDir("edit-enhance")
        defer { try? FileManager.default.removeItem(at: dir) }
        let rate = 48_000.0
        // 2 s Stille + 6 s leiser Ton (≈ −26 LUFS) mit Rumpeln (10 Hz) + 3 s Stille
        var x = [Float](repeating: 0, count: Int(2 * rate))
        let tone = Self.tone(1000, amp: 0.05, seconds: 6, rate: rate)
        let rumble = Self.tone(10, amp: 0.05, seconds: 6, rate: rate)
        x += zip(tone, rumble).map { $0 + $1 }
        x += [Float](repeating: 0, count: Int(3 * rate))
        let src = dir.appendingPathComponent("leise.wav")
        try Self.writeWAV(src, rate: rate, [x, x])

        var e = TrackEdit()
        e.enhance = true      // Lautheit −14, Rumpelfilter, Begrenzer, Stille entfernen
        let out = dir.appendingPathComponent("verbessert.wav")
        let (r, ms) = try await export(src, e, out: out)
        let a = try TS.readAll(out)
        let lufs = Self.loudness(a) ?? -99
        let peak = a.channels.map { $0.map(abs).max() ?? 0 }.max() ?? 0
        // Rumpeln: Anteil bei 10 Hz nach dem Hochpass (Mittelwert je 1-kHz-Periode; ohne Filter wären es ≈ 0,14 nach +12 dB)
        let mid = Array(a.channels[0][Int(1.5 * rate)..<Int(4.5 * rate)])
        var lowEnergy = 0.0
        let period = Int(rate / 1000)
        for k in stride(from: 0, to: mid.count - period, by: period) {
            let m = mid[k..<(k + period)].reduce(0, +) / Float(period)
            lowEnergy += Double(m * m)
        }
        let lowRms = (lowEnergy / Double(mid.count / period)).squareRoot()
        TS.log(String(format: "Verbessern: Dauer %.3f s (Ton 6 s), Lautheit %.2f LUFS (Ziel −14), Spitze %.3f, Rumpeln %.4f, %.0f ms",
                      r.duration, lufs, peak, lowRms, ms))
        XCTAssertEqual(r.duration, 6.06, accuracy: 0.03, "Stille entfernt (10 ms davor, 50 ms danach bleiben)")
        XCTAssertEqual(lufs, -14, accuracy: 0.5)
        XCTAssertLessThanOrEqual(peak, 0.892)
        XCTAssertLessThan(lowRms, 0.01, "Rumpeln unter 25 Hz entfernt")

        // Lautstärke +12 dB auf lautem Ton: Begrenzer hält −1 dBFS, gleiche Länge
        let loudSrc = dir.appendingPathComponent("laut.wav")
        let y = Self.voice(220, amp: 0.4, seconds: 3, rate: rate)
        try Self.writeWAV(loudSrc, rate: rate, [y, y])
        var g = TrackEdit(); g.gainDb = 12
        let loudOut = dir.appendingPathComponent("laut-out.wav")
        let (r2, _) = try await export(loudSrc, g, out: loudOut)
        let b = try TS.readAll(loudOut)
        let peak2 = b.channels.map { $0.map(abs).max() ?? 0 }.max() ?? 0
        TS.log(String(format: "Lautstärke +12 dB: Spitze %.4f (Grenze 0,891), Dauer %.4f s", peak2, r2.duration))
        XCTAssertLessThanOrEqual(peak2, 0.892)
        XCTAssertEqual(r2.duration, 3, accuracy: 0.001)
    }

    func testEqualizerAndAutoTune() async throws {
        let dir = try TS.makeDir("edit-eq")
        defer { try? FileManager.default.removeItem(at: dir) }
        let rate = 44_100.0
        // Bass-Absenkung: 60 Hz deutlich leiser, 2 kHz unverändert
        let low = Self.tone(60, amp: 0.3, seconds: 2, rate: rate)
        let high = Self.tone(2000, amp: 0.3, seconds: 2, rate: rate)
        let srcLow = dir.appendingPathComponent("tief.wav"), srcHigh = dir.appendingPathComponent("hoch.wav")
        try Self.writeWAV(srcLow, rate: rate, [low, low])
        try Self.writeWAV(srcHigh, rate: rate, [high, high])
        var e = TrackEdit()
        e.bandGains = [-12, -12, -6, 0, 0, 0, 0, 0, 0, 0]
        func rms(_ a: TS.Audio) -> Double {
            let s = a.channels[0][Int(rate * 0.5)..<Int(rate * 1.5)]
            return (s.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(s.count)).squareRoot()
        }
        let outLow = dir.appendingPathComponent("tief-out.wav"), outHigh = dir.appendingPathComponent("hoch-out.wav")
        _ = try await export(srcLow, e, out: outLow)
        _ = try await export(srcHigh, e, out: outHigh)
        let dLow = 20 * log10(rms(try TS.readAll(outLow)) / (0.3 / 2.0.squareRoot()))
        let dHigh = 20 * log10(rms(try TS.readAll(outHigh)) / (0.3 / 2.0.squareRoot()))
        TS.log(String(format: "Equalizer: 60 Hz %+.1f dB, 2 kHz %+.2f dB", dLow, dHigh))
        XCTAssertLessThan(dLow, -9)
        XCTAssertEqual(dHigh, 0, accuracy: 0.3)

        // Auto-Tune: Stimme bei 452 Hz → chromatisch 440 Hz
        let v = Self.voice(452, amp: 0.4, seconds: 3, rate: rate)
        let srcVoice = dir.appendingPathComponent("stimme.wav")
        try Self.writeWAV(srcVoice, rate: rate, [v])
        var at = TrackEdit()
        at.autoTune = true
        at.autoTuneScale = .chromatic
        at.autoTuneStrength = 1
        let outVoice = dir.appendingPathComponent("stimme-out.wav")
        let (r, ms) = try await export(srcVoice, at, out: outVoice)
        let a = try TS.readAll(outVoice)
        let f = StudioHEAACTests.pitch(a.channels[0], rate: a.rate)
        TS.log(String(format: "Auto-Tune: 452 Hz → %.2f Hz (Ziel 440), Dauer %.3f s, %.0f ms", f, r.duration, ms))
        XCTAssertEqual(f, 440, accuracy: 3)
        XCTAssertEqual(r.duration, 3, accuracy: 0.001)
    }

    /// Bearbeitete MP3/M4A/FLAC: Tags und Cover des Originals bleiben, Format und Länge stimmen.
    func testEditedLossyAndLosslessKeepTags() async throws {
        let dir = try TS.makeDir("edit-tags")
        defer { try? FileManager.default.removeItem(at: dir) }
        let wav = dir.appendingPathComponent("quelle.wav")
        try TS.writePCM(wav, rate: 44_100, channels: 2, bits: 16, seconds: 8, signal: .sweep)
        let meta = TS.metadata(cover: TS.makeImage("jpg"))
        var e = TrackEdit(); e.speed = 1.1; e.semitones = 1; e.enhance = true
        for format in [StudioFormat.mp3, .m4a, .flac] {
            // „Original“ mit Tags erzeugen
            let original = dir.appendingPathComponent("original.\(format.fileExtension)")
            _ = try await TS.export(ExportRequest(input: wav, trim: nil, options: .defaults(for: format), metadata: meta, output: original))
            let out = dir.appendingPathComponent("bearbeitet.\(format.fileExtension)")
            let (r, ms) = try await export(original, e, format: format, out: out, copyTags: original)
            let problems = TS.tagProblems(out, expected: meta)
            TS.log(String(format: "Bearbeiten %@: Dauer %.3f s (erwartet ≈ %.3f), %d Hz, Tags %@, %.0f ms",
                          format.label, r.duration, 8 / 1.1, r.sampleRate, problems.isEmpty ? "vollständig" : problems.joined(separator: "; "), ms))
            XCTAssertTrue(problems.isEmpty, "\(format.label): \(problems)")
            XCTAssertEqual(r.duration, 8 / 1.1, accuracy: format == .flac ? 0.02 : 0.08, format.label)
            XCTAssertFalse(r.passthrough)
        }
    }

    /// Analyse: Kammerton 442 Hz, C-Dur, Lautheit −23 LUFS, Stille am Rand.
    func testAnalyzerFindsTuningKeyLoudnessAndSilence() async throws {
        let dir = try TS.makeDir("edit-analyse")
        defer { try? FileManager.default.removeItem(at: dir) }
        let rate = 44_100.0
        let ref = 442.0
        let chords: [[Double]] = [[48, 60, 64, 67], [53, 65, 69, 72], [55, 67, 71, 74], [48, 60, 64, 67], [53, 65, 69, 72], [55, 67, 71, 74], [48, 60, 64, 67]]
        var x = [Float](repeating: 0, count: Int(rate))   // 1 s Stille
        for chord in chords {
            var part = [Float](repeating: 0, count: Int(rate))
            for m in chord {
                let f = MusicMath.frequency(midi: m, reference: ref)
                let t = Self.voice(f, amp: 0.08, seconds: 1, rate: rate, harmonics: 4)
                for i in 0..<part.count { part[i] += t[i] }
            }
            x += part
        }
        x += [Float](repeating: 0, count: Int(rate * 2))
        let src = dir.appendingPathComponent("akkorde.wav")
        try Self.writeWAV(src, rate: rate, [x, x])
        let a = try await TrackEditAnalyzer().analyze(src) { _ in }
        TS.log(String(format: "Analyse: A4 %.2f Hz (Sicherheit %.2f), Tonart %@, Lautheit %.2f LUFS, Stille %.2f / %.2f s",
                      a.reference ?? 0, a.referenceConfidence, a.keyText ?? "?", a.loudness ?? -99, a.leadingSilence, a.trailingSilence))
        XCTAssertEqual(a.reference ?? 0, ref, accuracy: 1)
        XCTAssertEqual(a.keyTonic, 0)
        XCTAssertEqual(a.keyScale, .major)
        XCTAssertEqual(a.leadingSilence, 1, accuracy: 0.02)
        XCTAssertEqual(a.trailingSilence, 2, accuracy: 0.05)
        XCTAssertNotNil(a.loudness)

        let sine = dir.appendingPathComponent("sinus.wav")
        let s = Self.tone(1000, amp: Float(pow(10, -23.0 / 20)), seconds: 10, rate: 48_000)
        try Self.writeWAV(sine, rate: 48_000, [s, s])
        let b = try await TrackEditAnalyzer().analyze(sine) { _ in }
        XCTAssertEqual(b.loudness ?? 0, -23, accuracy: 0.1)
    }
}
