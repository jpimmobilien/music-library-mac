import AVFoundation
import XCTest
import MLCore
import MLStudio
import MLTags
@testable import StudioEngine

/// Lokale Analyse, Wellenform, weitere Eingangsformate (Video, Ogg, FFmpeg-Formate) und Vorhören.
final class StudioSourceTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = try TS.makeDir("source")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testLocalAnalysisOfExportedFiles() async throws {
        let source = try TS.writePCM(dir.appendingPathComponent("q.wav"), rate: 48_000, channels: 2, bits: 24, seconds: 4, signal: .sweep)
        let meta = TS.metadata(cover: TS.png)
        let cases: [(ExportOptions, String, Bool, Int?)] = [
            (ExportOptions(format: .mp3, mp3Bitrate: 256), "MP3", false, nil),
            (ExportOptions(format: .flac, flacKeepSourceDepth: true), "FLAC", true, 24),
            (ExportOptions(format: .wav, pcmDepth: .int16), "PCM", true, 16),
            (ExportOptions(format: .aiff, pcmDepth: .int24), "PCM", true, 24),
            (ExportOptions(format: .m4a, aacBitrate: 192), "AAC", false, nil),
            (ExportOptions(format: .aac, aacBitrate: 192), "AAC", false, nil),
        ]
        for (o, codec, lossless, bits) in cases {
            let out = dir.appendingPathComponent("a.\(o.format.fileExtension)")
            let (r, _) = try await TS.export(ExportRequest(input: source, trim: nil, options: o, metadata: meta, output: out))
            let info = try await LocalSourceAnalyzer().analyze(file: out)
            XCTAssertEqual(info.kind, .localFile)
            XCTAssertEqual(info.localFile, out.standardizedFileURL)
            XCTAssertEqual(info.codec, codec, o.format.label)
            XCTAssertEqual(info.isLossless, lossless, o.format.label)
            XCTAssertEqual(info.bitDepth, bits, o.format.label)
            XCTAssertEqual(info.sampleRate, 48_000, o.format.label)
            XCTAssertEqual(info.channels, 2, o.format.label)
            XCTAssertEqual(info.fileSize, r.fileSize, o.format.label)
            XCTAssertEqual(info.duration ?? 0, 4, accuracy: o.format == .aac ? 0.15 : 0.06, o.format.label)
            XCTAssertNotNil(info.bitrateKbps, o.format.label)
            if o.format.supportsTags {
                XCTAssertEqual(info.title, meta.title, o.format.label)
                XCTAssertEqual(info.suggested.artist, meta.artist, o.format.label)
                XCTAssertEqual(info.suggested.album, meta.album, o.format.label)
                XCTAssertEqual(info.suggested.year, 2024, o.format.label)
                XCTAssertEqual(info.suggested.genre, meta.genre, o.format.label)
                XCTAssertEqual(info.suggested.trackNumber, 7, o.format.label)
                XCTAssertEqual(info.suggested.cover, TS.png, o.format.label)
                XCTAssertEqual(info.thumbnail, TS.png, o.format.label)
            } else {
                XCTAssertEqual(info.title, "a", "ohne Tags: Dateiname")
            }
            TS.log("Analyse \(o.format.label): Titel „\(info.title)“, Interpret „\(info.suggested.artist)“, Codec \(info.codec ?? "–"), \(info.bitrateKbps ?? 0) kbit/s, \(info.sampleRate ?? 0) Hz, Bits \(info.bitDepth.map { "\($0)" } ?? "–"), \(info.channels ?? 0) Kan., verlustfrei \(info.isLossless.map { $0 ? "ja" : "nein" } ?? "–"), Dauer \(String(format: "%.3f", info.duration ?? 0)) s, Cover \(info.thumbnail?.count ?? 0) B, \(info.fileSize ?? 0) B")
        }
    }

    /// Video- und Sonderformate (über ffmpeg erzeugt): Analyse und Export über AVAssetReader, Ogg-Decoder bzw. FFmpeg.
    func testVideoOggAndExoticInputs() async throws {
        guard let ffmpeg = TS.ffmpegPath else { throw XCTSkip("ffmpeg nicht installiert") }
        let base = ["-v", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=3", "-f", "lavfi", "-i", "sine=frequency=660:sample_rate=48000:duration=3"]
        let stereo = ["-filter_complex", "[0:a][1:a]amerge=inputs=2[a]", "-map", "[a]"]
        let videoIn = ["-f", "lavfi", "-i", "testsrc=size=320x240:rate=25:duration=3"]
        let variants: [(String, [String])] = [
            ("video.mp4", ["-v", "error", "-y"] + videoIn + ["-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100:duration=3",
                                                         "-map", "0:v", "-map", "1:a", "-c:v", "mpeg4", "-c:a", "aac", "-b:a", "128k", "-shortest"]),
            ("video.mov", ["-v", "error", "-y"] + videoIn + ["-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=3",
                                                         "-map", "0:v", "-map", "1:a", "-c:v", "mpeg4", "-c:a", "pcm_s16le", "-shortest"]),
            ("vorbis.ogg", base + stereo + ["-c:a", "libvorbis"]),
            ("opus.opus", base + stereo + ["-c:a", "libopus", "-b:a", "128k"]),
            ("webm.webm", base + stereo + ["-c:a", "libopus", "-b:a", "128k"]),
            ("mka.mka", base + stereo + ["-c:a", "flac"]),
        ]
        for (name, args) in variants {
            let url = dir.appendingPathComponent(name)
            var r = TS.run(ffmpeg, args + [url.path], timeout: 120)
            if r.status != 0 && name.hasSuffix(".ogg") {
                // FFmpeg ohne libvorbis: eingebauter Encoder
                r = TS.run(ffmpeg, base + stereo + ["-c:a", "vorbis", "-strict", "-2", "-ac", "2", url.path], timeout: 120)
            }
            if r.status != 0 && (name.hasSuffix(".opus") || name.hasSuffix(".webm")) {
                r = TS.run(ffmpeg, base + stereo + ["-c:a", "opus", "-strict", "-2", url.path], timeout: 120)
            }
            guard r.status == 0 else {
                TS.log("Eingang \(name): konnte nicht erzeugt werden (\(r.err.prefix(200)))")
                continue
            }
            let info = try await LocalSourceAnalyzer().analyze(file: url)
            let out = dir.appendingPathComponent("\(name).wav")
            let (res, _) = try await TS.export(ExportRequest(input: url, trim: TrimRange(start: 0.5, end: 2.5), options: ExportOptions(format: .wav),
                                                             metadata: StudioMetadata(), output: out))
            let decoded = try TS.readAll(out)
            let peak = decoded.channels.flatMap { $0 }.map { abs($0) }.max() ?? 0
            TS.log(String(format: "Eingang %@: Codec %@, %d Hz, %d Kan., Dauer %.3f s, Vorschaubild %d B → WAV-Ausschnitt %.4f s (Δ %+.2f ms), %d Kan., Spitze %.2f",
                          name, info.codec ?? "–", info.sampleRate ?? 0, info.channels ?? 0, info.duration ?? 0, info.thumbnail?.count ?? 0,
                          res.duration, (res.duration - 2) * 1000, res.channels, peak))
            XCTAssertEqual(res.duration, 2, accuracy: 0.002, name)
            XCTAssertGreaterThan(peak, 0.05, "\(name): Signal vorhanden")
            XCTAssertEqual(info.duration ?? 0, 3, accuracy: 0.1, name)
            if name.hasPrefix("video") { XCTAssertNotNil(info.thumbnail, "\(name): Vorschaubild aus dem Video") }
        }
    }

    func testWaveform() async throws {
        let stereo = try TS.writePCM(dir.appendingPathComponent("w.wav"), rate: 44_100, channels: 2, bits: 16, seconds: 10.003, signal: .sine(100, 0.5))
        let log = ProgressLog()
        let w = try await WaveformAnalyzer().waveform(for: stereo) { log.add($0) }
        let frames = Int((10.003 * 44_100).rounded())
        XCTAssertEqual(w.framesPerBucket, 256)
        XCTAssertEqual(w.levels[0].mins.count, (frames + 255) / 256)
        XCTAssertEqual(w.duration, Double(frames) / 44_100, accuracy: 1e-9)
        XCTAssertEqual(w.levels[0].maxs.max() ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(w.levels[0].mins.min() ?? 0, -0.5, accuracy: 0.001)
        XCTAssertGreaterThan(w.levels.count, 0)
        let values = log.values
        XCTAssertEqual(values, values.sorted(), "Fortschritt steigt")
        XCTAssertEqual(values.last ?? 0, 1, accuracy: 1e-9)
        // Beide Kanäle fließen ein: Klick links +0,9, rechts −0,9 → Maximum aus links, Minimum aus rechts
        let mixed = try TS.writePCM(dir.appendingPathComponent("k.wav"), rate: 48_000, channels: 2, bits: 24, seconds: 1, signal: .clicks([1_000, 30_000]))
        let wk = try await WaveformAnalyzer().waveform(for: mixed) { _ in }
        XCTAssertEqual(wk.levels[0].maxs[1_000 / 256], 0.9, accuracy: 0.001)
        XCTAssertEqual(wk.levels[0].mins[1_000 / 256], -0.9, accuracy: 0.001, "Minimum aus dem rechten Kanal")
        // Abbruch
        let task = Task { try await WaveformAnalyzer().waveform(for: stereo) { _ in } }
        task.cancel()
        do {
            _ = try await task.value
            TS.log("Wellenform: Abbruch kam zu spät (Datei bereits fertig)")
        } catch let e as StudioError {
            XCTAssertEqual(e, .cancelled)
        }
        TS.log("Wellenform 10 s: \(w.levels[0].mins.count) Blöcke, \(w.levels.count) Stufen, Spitze \(w.peak), \(values.count) Fortschrittsmeldungen")
    }

    @MainActor
    func testPreviewPlayer() async throws {
        let url = try TS.writePCM(dir.appendingPathComponent("p.wav"), rate: 44_100, channels: 2, bits: 16, seconds: 3, signal: .sine(440, 0.2))
        let player = StudioPreviewPlayer()
        try player.load(url)
        var finished = false
        player.onFinish = { finished = true }
        player.play(from: 1.0, to: 1.6)
        guard player.isPlaying else {
            player.shutdown()
            throw XCTSkip("Audioausgabe nicht verfügbar (AVAudioEngine startet nicht)")
        }
        try await Task.sleep(nanoseconds: 250_000_000)
        let mid = player.position
        let deadline = Date().addingTimeInterval(5)
        while !finished && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        TS.log(String(format: "Vorhören 1,0–1,6 s: Position nach 0,25 s %.3f s, Ende gemeldet: %@, Position danach %.3f s", mid, finished ? "ja" : "nein", player.position))
        XCTAssertTrue(finished, "onFinish am Ende des Bereichs")
        XCTAssertGreaterThan(mid, 1.0)
        XCTAssertLessThan(mid, 1.6)
        XCTAssertFalse(player.isPlaying)
        // Anhalten hält die Position, Stoppen löst kein onFinish aus
        finished = false
        player.play(from: 0, to: nil)
        try await Task.sleep(nanoseconds: 200_000_000)
        player.pause()
        let paused = player.position
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(player.position, paused, accuracy: 0.0001)
        player.stop()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(finished)
        player.shutdown()
        TS.log(String(format: "Vorhören: Anhalten bei %.3f s gehalten, Stoppen ohne onFinish", paused))
    }
}
