import AVFoundation
import XCTest
import MLCore
import MLStudio
import MLTags
@testable import StudioEngine

/// Export in jedes Format (alle MP3-Bitraten) mit Prüfung von Lesbarkeit, Endung, Dauer, Abtastrate,
/// Kanälen, Bittiefe, Bitrate, Tags/Cover und Klang (Störabstand gegen die Quelle).
final class StudioFormatExportTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = try TS.makeDir("format")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    struct Case {
        var name: String
        var options: ExportOptions
        var bits: Int?
    }

    static func cases() -> [Case] {
        var list: [Case] = []
        for kbps in ExportOptions.mp3Bitrates {
            list.append(Case(name: "MP3 \(kbps)", options: ExportOptions(format: .mp3, mp3Bitrate: kbps), bits: nil))
        }
        for d in PCMDepth.allCases {
            list.append(Case(name: "WAV \(d.label)", options: ExportOptions(format: .wav, pcmDepth: d), bits: d.bits))
            list.append(Case(name: "AIFF \(d.label)", options: ExportOptions(format: .aiff, pcmDepth: d), bits: d.bits))
        }
        list.append(Case(name: "FLAC 16 Stufe 0", options: ExportOptions(format: .flac, pcmDepth: .int16, flacKeepSourceDepth: false, flacLevel: 0), bits: 16))
        list.append(Case(name: "FLAC 24 Stufe 5", options: ExportOptions(format: .flac, pcmDepth: .int24, flacKeepSourceDepth: false, flacLevel: 5), bits: 24))
        list.append(Case(name: "FLAC wie Quelle Stufe 8", options: ExportOptions(format: .flac, flacKeepSourceDepth: true, flacLevel: 8), bits: 24))
        for kbps in [128, 256] {
            list.append(Case(name: "AAC \(kbps)", options: ExportOptions(format: .aac, aacBitrate: kbps), bits: nil))
            list.append(Case(name: "M4A \(kbps)", options: ExportOptions(format: .m4a, aacBitrate: kbps), bits: nil))
        }
        return list
    }

    /// Stereo-Quelle 44,1 kHz / 24 Bit, 6 s Gleitsinus (links ≠ rechts) → alle Formate.
    func testEveryFormatFromStereo24Bit() async throws {
        let seconds = 6.0
        let source = try TS.writePCM(dir.appendingPathComponent("quelle.wav"), rate: 44_100, channels: 2, bits: 24, seconds: seconds, signal: .sweep)
        let src = try TS.readAll(source)
        let cover = TS.png
        var failures: [String] = []
        for c in Self.cases() {
            let meta = TS.metadata(cover: cover)
            let out = dir.appendingPathComponent("export-\(c.name.replacingOccurrences(of: " ", with: "_")).\(c.options.format.fileExtension)")
            let (result, progress) = try await TS.export(ExportRequest(input: source, trim: nil, options: c.options, metadata: meta, output: out))
            XCTAssertEqual(out.pathExtension, c.options.format.fileExtension, c.name)
            XCTAssertTrue(FileManager.default.fileExists(atPath: out.path), c.name)
            XCTAssertEqual(progress.last ?? 0, 1, accuracy: 0.0001, "\(c.name): Fortschritt endet bei 1")
            let decoded = try TS.readAll(out)   // lesbar über AVAudioFile
            let durationError = (result.duration - seconds) * 1000
            let lossless = c.options.format.isLossless
            let tolerance: Double = lossless ? 1000 / 44_100 : (c.options.format == .aac ? 120 : 30)
            if abs(durationError) > tolerance { failures.append("\(c.name): Dauer Δ \(String(format: "%.2f", durationError)) ms") }
            XCTAssertEqual(result.sampleRate, 44_100, c.name)
            XCTAssertEqual(result.channels, 2, c.name)
            XCTAssertEqual(decoded.channels.count, 2, c.name)
            if let bits = c.bits { XCTAssertEqual(result.bitDepth, bits, c.name) } else { XCTAssertNil(result.bitDepth, c.name) }
            var bitrateText = "\(result.bitrateKbps) kbit/s"
            if c.options.format == .mp3 {
                let target = Double(c.options.mp3Bitrate)
                let info = try MP3Stream.scan(url: out)
                let measured = info.averageKbps
                bitrateText += String(format: " (Ziel %.0f, Audiodaten %.2f kbit/s, Δ %.2f %%)", target, measured, (measured - target) / target * 100)
                if abs(Double(result.bitrateKbps) - target) / target > 0.02 || abs(measured - target) / target > 0.02 {
                    failures.append("\(c.name): Bitrate \(bitrateText)")
                }
                XCTAssertTrue(info.isCBR, c.name)
                XCTAssertEqual(info.infoTag?.isInfo, true, "\(c.name): LAME/Info-Frame")
                XCTAssertEqual(info.infoTag?.frames, info.frameCount, "\(c.name): Frameanzahl im Info-Frame")
            } else if !lossless {
                let target = Double(c.options.aacBitrate)
                bitrateText += String(format: " (Ziel %.0f, Δ %.1f %%)", target, (Double(result.bitrateKbps) - target) / target * 100)
                if abs(Double(result.bitrateKbps) - target) / target > 0.25 { failures.append("\(c.name): Bitrate \(bitrateText)") }
            }
            var tagText = "keine (ADTS)"
            if c.options.format.supportsTags {
                let problems = TS.tagProblems(out, expected: meta)
                tagText = problems.isEmpty ? "Tags+Cover ok" : problems.joined(separator: ", ")
                if !problems.isEmpty { failures.append("\(c.name): \(tagText)") }
                XCTAssertTrue(result.tagsWritten, c.name)
            } else {
                XCTAssertFalse(result.tagsWritten, c.name)
            }
            let (lag, snr) = TS.alignedSNR(reference: src.channels, test: decoded.channels)
            let minSNR: Double
            switch c.bits {
            case 16: minSNR = 80
            case 24, 32: minSNR = 120
            default: minSNR = 10
            }
            if snr < minSNR { failures.append("\(c.name): Störabstand \(String(format: "%.1f", snr)) dB < \(minSNR)") }
            if lossless { XCTAssertEqual(lag, 0, "\(c.name): Versatz") }
            TS.log(String(format: "%@: Dauer %.4f s (Δ %+.2f ms), %d Hz, %d Kan., Bits %@, %@, %@, Größe %lld B, SNR %.1f dB (Versatz %d), Fortschritt %d Meldungen",
                          c.name, result.duration, durationError, result.sampleRate, result.channels,
                          result.bitDepth.map { "\($0)" } ?? "–", bitrateText, tagText, result.fileSize, snr, lag, progress.count))
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    /// 48 und 96 kHz Quellen: Zielrate nach `outputSampleRate`, Störabstand gegen die analytische Referenz.
    func testSampleRatesAndConversion() async throws {
        var failures: [String] = []
        let seconds = 4.0
        for rate in [48_000.0, 96_000.0] {
            let source = try TS.writePCM(dir.appendingPathComponent("q\(Int(rate)).wav"), rate: rate, channels: 2, bits: 24, seconds: seconds, signal: .sweep)
            let variants: [ExportOptions] = [
                ExportOptions(format: .wav, pcmDepth: .int24),
                ExportOptions(format: .wav, pcmDepth: .int24, sampleRate: 44_100),
                ExportOptions(format: .flac, flacKeepSourceDepth: true),
                ExportOptions(format: .aiff, pcmDepth: .float32, sampleRate: 48_000),
                ExportOptions(format: .mp3, mp3Bitrate: 320),
                ExportOptions(format: .m4a, aacBitrate: 256),
            ]
            for o in variants {
                let expectedRate = o.outputSampleRate(sourceRate: Int(rate))
                let out = dir.appendingPathComponent("r\(Int(rate))-\(o.format.rawValue)-\(o.sampleRate ?? 0).\(o.format.fileExtension)")
                let (result, _) = try await TS.export(ExportRequest(input: source, trim: nil, options: o, metadata: StudioMetadata(), output: out))
                let decoded = try TS.readAll(out)
                let ref = TS.reference(.sweep, rate: Double(expectedRate), start: 0, frames: decoded.frames, channels: 2, length: seconds)
                let (lag, snr) = TS.alignedSNR(reference: ref, test: decoded.channels)
                let dErr = (result.duration - seconds) * 1000
                TS.log(String(format: "Abtastrate %d → %@ %@: %d Hz (erwartet %d), Dauer Δ %+.2f ms, SNR %.1f dB (Versatz %d)",
                              Int(rate), o.format.label, o.sampleRate.map { "\($0)" } ?? "Original", result.sampleRate, expectedRate, dErr, snr, lag))
                if result.sampleRate != expectedRate { failures.append("\(o.summary()): Rate \(result.sampleRate) statt \(expectedRate)") }
                let tol = o.format.isLossless ? 1000 / Double(expectedRate) + 0.001 : 30
                if abs(dErr) > tol { failures.append("\(o.summary()) @\(Int(rate)): Dauer Δ \(dErr) ms") }
                if o.format.isLossless && snr < 70 { failures.append("\(o.summary()) @\(Int(rate)): SNR \(snr)") }
                if !o.format.isLossless && snr < 10 { failures.append("\(o.summary()) @\(Int(rate)): SNR \(snr)") }
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    /// Ungewöhnliche Abtastraten (22,05 / 88,2 / 96 kHz) → richtige Zielrate je Format.
    func testUnusualSampleRates() async throws {
        var failures: [String] = []
        for rate in [22_050.0, 88_200.0, 96_000.0] {
            let source = try TS.writePCM(dir.appendingPathComponent("u\(Int(rate)).wav"), rate: rate, channels: 2, bits: 16, seconds: 2, signal: .sweep)
            for o in [ExportOptions(format: .mp3), ExportOptions(format: .aac), ExportOptions(format: .m4a), ExportOptions(format: .flac),
                      ExportOptions(format: .wav), ExportOptions(format: .aiff)] {
                let expected = o.outputSampleRate(sourceRate: Int(rate))
                let out = dir.appendingPathComponent("u\(Int(rate)).\(o.format.fileExtension)")
                let (result, _) = try await TS.export(ExportRequest(input: source, trim: nil, options: o, metadata: StudioMetadata(), output: out))
                TS.log("Ungewöhnliche Rate \(Int(rate)) → \(o.format.label): \(result.sampleRate) Hz (erwartet \(expected)), Dauer \(String(format: "%.4f", result.duration)) s")
                if result.sampleRate != expected { failures.append("\(Int(rate)) → \(o.format.label): \(result.sampleRate) statt \(expected)") }
                // ADTS kann die Encoder-Verzögerung (2112 Samples) nicht kennzeichnen: bis zu 2112 + 1024 Samples länger
                let aacSlack = Double(2112 + 1024) / Double(expected) + 0.002
                if abs(result.duration - 2) > (o.format.isLossless ? 0.001 : (o.format == .aac ? aacSlack : 0.04)) {
                    failures.append("\(Int(rate)) → \(o.format.label): Dauer \(result.duration)")
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    /// Mono bleibt Mono (`keepMono`), sonst Stereo; Mehrkanal (5.1) wird auf Stereo heruntergemischt.
    func testMonoAndMultichannel() async throws {
        let mono = try TS.writePCM(dir.appendingPathComponent("mono.wav"), rate: 44_100, channels: 1, bits: 16, seconds: 3, signal: .sweep)
        for format in [StudioFormat.mp3, .wav, .flac, .m4a, .aiff, .aac] {
            for keep in [true, false] {
                var o = ExportOptions.defaults(for: format)
                o.keepMono = keep
                let out = dir.appendingPathComponent("mono-\(keep)-.\(format.fileExtension)")
                let (r, _) = try await TS.export(ExportRequest(input: mono, trim: nil, options: o, metadata: StudioMetadata(), output: out))
                XCTAssertEqual(r.channels, keep ? 1 : 2, "\(format.label) keepMono=\(keep)")
                let d = try TS.readAll(out)
                if !keep && format.isLossless { XCTAssertEqual(d.channels[0], d.channels[1], "\(format.label): beide Seiten gleich") }
                TS.log("Mono → \(format.label) (Mono behalten: \(keep)): \(r.channels) Kanäle, Dauer \(String(format: "%.4f", r.duration)) s")
            }
        }
        // 5.1 (L R C LFE Ls Rs): Center nur in der Mitte, Surround-links nur links, Surround-rechts nur rechts
        for (index, name, expectLeft, expectRight) in [(2, "Center", true, true), (4, "Surround links", true, false), (5, "Surround rechts", false, true)] {
            let src = try TS.writePCM(dir.appendingPathComponent("kanal\(index).wav"), rate: 48_000, channels: 6, bits: 24, seconds: 1, signal: .onlyChannel(index, 500, 0.5))
            let out = dir.appendingPathComponent("kanal\(index)-stereo.wav")
            _ = try await TS.export(ExportRequest(input: src, trim: nil, options: ExportOptions(format: .wav, pcmDepth: .float32), metadata: StudioMetadata(), output: out))
            let p = TS.peaks(try TS.readAll(out))
            TS.log(String(format: "5.1-Heruntermischen, nur %@: links %.3f, rechts %.3f", name, p[0], p[1]))
            XCTAssertEqual(p.count, 2)
            XCTAssertEqual(p[0] > 0.05, expectLeft, "\(name) links")
            XCTAssertEqual(p[1] > 0.05, expectRight, "\(name) rechts")
        }
        // 5.1 → Stereo, alle Kanäle voll ausgesteuert
        let surround = try TS.writePCM(dir.appendingPathComponent("surround.wav"), rate: 48_000, channels: 6, bits: 24, seconds: 2, signal: .sine(1000, 0.9))
        for format in [StudioFormat.wav, .mp3, .flac] {
            let o = ExportOptions(format: format, pcmDepth: .float32)
            let out = dir.appendingPathComponent("surround.\(format.fileExtension)")
            let (r, _) = try await TS.export(ExportRequest(input: surround, trim: nil, options: o, metadata: StudioMetadata(), output: out))
            let d = try TS.readAll(out)
            let peak = d.channels.flatMap { $0 }.map { abs($0) }.max() ?? 0
            XCTAssertEqual(r.channels, 2, "5.1 → \(format.label)")
            // Verlustbehaftete Codecs können beim Dekodieren leicht überschwingen – geprüft wird das Verlustfreie
            if format.isLossless { XCTAssertLessThanOrEqual(peak, 0.99998, "5.1 → \(format.label): keine Übersteuerung") }
            XCTAssertGreaterThan(peak, 0.2, "5.1 → \(format.label): Signal vorhanden")
            TS.log(String(format: "5.1 → %@: %d Kanäle, Spitze %.3f", format.label, r.channels, peak))
        }
    }

    /// MP3-Dauer: LAME-Angaben (exakt) gegenüber AVFoundation; Einfluss von ID3v2/ID3v1 berichten.
    func testMP3DurationSeenByAVFoundation() async throws {
        let source = try TS.writePCM(dir.appendingPathComponent("q.wav"), rate: 44_100, channels: 2, bits: 16, seconds: 6, signal: .sweep)
        for kbps in ExportOptions.mp3Bitrates {
            let out = dir.appendingPathComponent("d\(kbps).mp3")
            let (r, _) = try await TS.export(ExportRequest(input: source, trim: nil, options: ExportOptions(format: .mp3, mp3Bitrate: kbps),
                                                           metadata: StudioMetadata(), output: out))
            func avDuration() throws -> Double {
                let f = try AVAudioFile(forReading: out)
                return Double(f.length) / f.processingFormat.sampleRate
            }
            let plain = try avDuration()
            try TagFile.write(url: out, edit: TS.metadata(cover: TS.jpeg).tagEdit(coverMimeType: "image/jpeg"))
            let tagged = try avDuration()
            let data = try Data(contentsOf: out)
            let hasV1 = data.count > 128 && data[(data.count - 128)..<(data.count - 125)] == Data("TAG".utf8)
            var withoutV1 = tagged
            if hasV1 {
                try data.prefix(data.count - 128).write(to: out)
                withoutV1 = try avDuration()
            }
            let exact = try MP3Stream.scan(url: out).duration
            TS.log(String(format: "MP3 %d kbit/s Dauer: Ergebnis %.4f s, LAME-Angaben %.4f s, AVAudioFile ohne Tags %.4f s, mit ID3v2+ID3v1 %.4f s, ID3v1 vorhanden %@, ohne ID3v1 %.4f s",
                          kbps, r.duration, exact, plain, tagged, hasV1 ? "ja" : "nein", withoutV1))
            XCTAssertEqual(r.duration, 6, accuracy: 0.0001)
            XCTAssertEqual(exact, 6, accuracy: 0.0001)
            XCTAssertEqual(plain, 6, accuracy: 0.03)
        }
    }
}
