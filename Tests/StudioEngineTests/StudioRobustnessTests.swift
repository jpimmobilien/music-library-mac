import AVFoundation
import XCTest
import MLCore
import MLStudio
import MLTags
@testable import StudioEngine

/// Fehlerfälle, Abbruch, Anhalten, Fortschritt, lange Dateien (Zeit und Speicher).
final class StudioRobustnessTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = try TS.makeDir("robust")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testDamagedAndUnsupportedFiles() async throws {
        // Zufällige druckbare Zeichen: kein 0xFF, also auch kein scheinbarer MP3-Frame-Anfang
        var random = SystemRandomNumberGenerator()
        let garbage = Data((0..<50_000).map { _ in UInt8.random(in: 0x20...0x7E, using: &random) })
        // Echte FLAC-Datei, nach den Kopfdaten abgeschnitten
        let wav = try TS.writePCM(dir.appendingPathComponent("ok.wav"), rate: 44_100, channels: 2, bits: 16, seconds: 2, signal: .sweep)
        let flac = dir.appendingPathComponent("ok.flac")
        _ = try await TS.export(ExportRequest(input: wav, trim: nil, options: .defaults(for: .flac), metadata: StudioMetadata(), output: flac))
        let truncated = try Data(contentsOf: flac).prefix(300)
        try FileManager.default.removeItem(at: wav)
        try FileManager.default.removeItem(at: flac)
        let cases: [(String, Data)] = [
            ("muell.wav", garbage),
            ("muell.mp3", garbage),
            ("text.flac", Data("Das ist keine FLAC-Datei.\n".utf8)),
            ("leer.mp3", Data()),
            ("abgeschnitten.wav", Data("RIFF\u{24}\u{00}\u{00}\u{00}WAVEfmt ".utf8)),
            ("abgeschnitten.flac", Data(truncated)),
            ("unbekannt.xyz", garbage),
        ]
        for (name, data) in cases {
            let url = dir.appendingPathComponent(name)
            try data.write(to: url)
            do {
                _ = try await AudioExporter().export(ExportRequest(input: url, trim: nil, options: .defaults(for: .mp3), metadata: StudioMetadata(),
                                                                   output: dir.appendingPathComponent("aus-\(name).mp3")), pause: nil) { _ in }
                XCTFail("\(name): Export hätte fehlschlagen müssen")
            } catch let e as StudioError {
                let text = e.errorDescription ?? ""
                XCTAssertFalse(text.isEmpty)
                XCTAssertNotEqual(e, .cancelled)
                TS.log("Beschädigt/unbekannt \(name): \(text)")
            }
            do {
                _ = try await LocalSourceAnalyzer().analyze(file: url)
                // Zufallsdaten mit bekannter Endung können als „Audio“ erkannt werden – dann nur berichten
                TS.log("Analyse \(name): ohne Fehler (Format erkannt)")
            } catch let e as StudioError {
                TS.log("Analyse \(name): \(e.errorDescription ?? "")")
            }
            do {
                _ = try await WaveformAnalyzer().waveform(for: url) { _ in }
            } catch let e as StudioError {
                XCTAssertNotEqual(e, .cancelled)
            }
        }
        // Keine Reste im Ordner
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".") || $0.hasPrefix("aus-") }
        XCTAssertEqual(left, [], "keine Restdateien")
        // Fehlende Datei
        do {
            _ = try await AudioExporter().export(ExportRequest(input: dir.appendingPathComponent("fehlt.wav"), trim: nil, options: .defaults(for: .wav),
                                                               metadata: StudioMetadata(), output: dir.appendingPathComponent("x.wav")), pause: nil) { _ in }
            XCTFail("fehlende Datei")
        } catch let e as StudioError {
            TS.log("Fehlende Datei: \(e.errorDescription ?? "")")
        }
    }

    func testCancelMidExportLeavesNothing() async throws {
        let source = try TS.writePCM(dir.appendingPathComponent("q.wav"), rate: 44_100, channels: 2, bits: 16, seconds: 120, signal: .sine(440, 0.5))
        for format in [StudioFormat.mp3, .flac, .wav, .m4a] {
            let out = dir.appendingPathComponent("abbruch.\(format.fileExtension)")
            let log = ProgressLog()
            let task = Task {
                try await AudioExporter().export(ExportRequest(input: source, trim: nil, options: .defaults(for: format), metadata: TS.metadata(cover: TS.png),
                                                               output: out), pause: nil) { log.add($0) }
            }
            let deadline = Date().addingTimeInterval(60)
            while log.last < 0.2 && Date() < deadline { try await Task.sleep(nanoseconds: 5_000_000) }
            let at = log.last
            task.cancel()
            do {
                _ = try await task.value
                XCTFail("\(format.label): Export nicht abgebrochen")
            } catch let e as StudioError {
                XCTAssertEqual(e, .cancelled, format.label)
            }
            let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
            XCTAssertEqual(files, ["q.wav"], "\(format.label): keine Restdatei")
            TS.log(String(format: "Abbruch %@ bei %.0f %%: StudioError.cancelled, Ordner danach: %@", format.label, at * 100, files.joined(separator: ", ")))
        }
    }

    func testPauseAndResume() async throws {
        let source = try TS.writePCM(dir.appendingPathComponent("q.wav"), rate: 44_100, channels: 2, bits: 16, seconds: 90, signal: .sweep)
        let gate = PauseGate()
        let log = ProgressLog()
        let out = dir.appendingPathComponent("pause.flac")
        let task = Task {
            try await AudioExporter().export(ExportRequest(input: source, trim: nil, options: ExportOptions(format: .flac, flacLevel: 8), metadata: StudioMetadata(),
                                                           output: out), pause: gate) { log.add($0) }
        }
        while log.last < 0.1 { try await Task.sleep(nanoseconds: 5_000_000) }
        gate.pause()
        try await Task.sleep(nanoseconds: 300_000_000)
        let frozen = log.last
        try await Task.sleep(nanoseconds: 800_000_000)
        let after = log.last
        XCTAssertEqual(frozen, after, accuracy: 0.0001, "angehalten: kein Fortschritt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path), "Ziel erst am Ende")
        gate.resume()
        let r = try await task.value
        XCTAssertEqual(r.duration, 90, accuracy: 0.001)
        TS.log(String(format: "Anhalten bei %.0f %%: 0,8 s kein Fortschritt (%.4f → %.4f), nach Fortsetzen fertig: %.3f s, Rückrufe max. %d/s",
                      frozen * 100, frozen, after, r.duration, log.maxPerSecond))
        XCTAssertLessThanOrEqual(log.maxPerSecond, 13, "Fortschritt höchstens ~10×/s")

        // Abbruch im angehaltenen Zustand greift sofort
        let gate2 = PauseGate()
        let log2 = ProgressLog()
        let task2 = Task {
            try await AudioExporter().export(ExportRequest(input: source, trim: nil, options: ExportOptions(format: .mp3), metadata: StudioMetadata(),
                                                           output: dir.appendingPathComponent("pause2.mp3")), pause: gate2) { log2.add($0) }
        }
        while log2.last < 0.05 { try await Task.sleep(nanoseconds: 5_000_000) }
        gate2.pause()
        try await Task.sleep(nanoseconds: 200_000_000)
        let t0 = Date()
        task2.cancel()
        do {
            _ = try await task2.value
            XCTFail("nicht abgebrochen")
        } catch let e as StudioError {
            XCTAssertEqual(e, .cancelled)
        }
        TS.log(String(format: "Abbruch im angehaltenen Zustand nach %.0f ms", Date().timeIntervalSince(t0) * 1000))
    }

    /// Lange Datei (30 min): Zeit und Speicher je Format; Wellenform einer Stunde.
    func testLongFilesTimeAndMemory() async throws {
        let long = dir.appendingPathComponent("lang30.wav")
        var t0 = Date()
        try TS.writeLongWAV(long, rate: 44_100, seconds: 30 * 60)
        TS.log(String(format: "Lange Datei: 30 min WAV (%.0f MB) in %.1f s erzeugt", Double(TS.fileSize(long)) / 1_048_576, Date().timeIntervalSince(t0)))
        for o in [ExportOptions(format: .mp3, mp3Bitrate: 320), ExportOptions(format: .flac, flacLevel: 5), ExportOptions(format: .m4a, aacBitrate: 256),
                  ExportOptions(format: .wav, pcmDepth: .int24, sampleRate: 48_000)] {
            let out = dir.appendingPathComponent("lang.\(o.format.fileExtension)")
            let before = TS.footprint()
            var peak = before
            let sampler = Task.detached {
                var m = before
                while !Task.isCancelled {
                    m = max(m, TS.footprint())
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                return m
            }
            t0 = Date()
            let (r, _) = try await TS.export(ExportRequest(input: long, trim: nil, options: o, metadata: TS.metadata(cover: TS.jpeg), output: out))
            let secs = Date().timeIntervalSince(t0)
            sampler.cancel()
            peak = max(peak, await sampler.value)
            TS.log(String(format: "Lange Datei 30 min → %@: %.1f s (%.0f× Echtzeit), Speicher vorher %@, Spitze %@ (+%@), Dauer %.3f s, %d kbit/s, %lld MB",
                          o.summary(), secs, 1800 / secs, TS.mb(before), TS.mb(peak), TS.mb(peak > before ? peak - before : 0), r.duration, r.bitrateKbps, r.fileSize / 1_048_576))
            XCTAssertEqual(r.duration, 1800, accuracy: o.format.isLossless ? 0.001 : 0.05)
            XCTAssertLessThan(peak > before ? peak - before : 0, 300 * 1_048_576, "Speicherbedarf bleibt begrenzt")
            if o.format == .mp3 {
                t0 = Date()
                let w = try await WaveformAnalyzer().waveform(for: out) { _ in }
                TS.log(String(format: "Wellenform 30 min MP3: %.1f s, %d Blöcke", Date().timeIntervalSince(t0), w.levels[0].mins.count))
            }
            try? FileManager.default.removeItem(at: out)
        }
        try? FileManager.default.removeItem(at: long)

        // Wellenform: 1 Stunde 44,1 kHz Stereo
        let hour = dir.appendingPathComponent("stunde.wav")
        try TS.writeLongWAV(hour, rate: 44_100, seconds: 3600)
        let before = TS.footprint()
        t0 = Date()
        let log = ProgressLog()
        let w = try await WaveformAnalyzer().waveform(for: hour) { log.add($0) }
        let secs = Date().timeIntervalSince(t0)
        let expectedBuckets = (3600 * 44_100 + 255) / 256
        TS.log(String(format: "Wellenform 1 h WAV 44,1 kHz Stereo: %.2f s, %d Blöcke (erwartet %d), %d Stufen, Spitze %.3f, Speicher +%@, %d Fortschrittsmeldungen",
                      secs, w.levels[0].mins.count, expectedBuckets, w.levels.count, w.peak, TS.mb(TS.footprint() > before ? TS.footprint() - before : 0), log.count))
        XCTAssertEqual(w.levels[0].mins.count, expectedBuckets)
        XCTAssertEqual(w.duration, 3600, accuracy: 0.001)
        XCTAssertEqual(w.peak, 0.5, accuracy: 0.01)
        XCTAssertLessThan(secs, 60)
        try? FileManager.default.removeItem(at: hour)
    }
}
