import AVFoundation
import XCTest
import MLCore
import MLStudio
import MLTags
@testable import StudioEngine

/// Gegenprüfung mit ffprobe/ffmpeg (falls installiert; der Studio-Workflow installiert es):
/// Codec, Abtastrate, Kanäle, Bittiefe, Bitrate, Dauer, Tags, Cover-Stream, dekodierte Länge.
final class StudioFFprobeTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        guard TS.ffprobePath != nil else { throw XCTSkip("ffprobe nicht installiert") }
        dir = try TS.makeDir("ffprobe")
    }

    override func tearDownWithError() throws {
        if let dir { try? FileManager.default.removeItem(at: dir) }
    }

    func testFFprobeAgreesForEveryFormat() async throws {
        let seconds = 5.0
        let source = try TS.writePCM(dir.appendingPathComponent("q.wav"), rate: 44_100, channels: 2, bits: 24, seconds: seconds, signal: .sweep)
        var cases: [(ExportOptions, String, Int?)] = []
        for kbps in ExportOptions.mp3Bitrates { cases.append((ExportOptions(format: .mp3, mp3Bitrate: kbps), "mp3", nil)) }
        cases += [
            (ExportOptions(format: .wav, pcmDepth: .int16), "pcm_s16le", 16),
            (ExportOptions(format: .wav, pcmDepth: .int24), "pcm_s24le", 24),
            (ExportOptions(format: .wav, pcmDepth: .float32), "pcm_f32le", 32),
            (ExportOptions(format: .aiff, pcmDepth: .int16), "pcm_s16be", 16),
            (ExportOptions(format: .aiff, pcmDepth: .int24), "pcm_s24be", 24),
            (ExportOptions(format: .aiff, pcmDepth: .float32), "pcm_f32be", 32),
            (ExportOptions(format: .flac, pcmDepth: .int16, flacKeepSourceDepth: false), "flac", 16),
            (ExportOptions(format: .flac, flacKeepSourceDepth: true, flacLevel: 8), "flac", 24),
            (ExportOptions(format: .aac, aacBitrate: 192), "aac", nil),
            (ExportOptions(format: .m4a, aacBitrate: 192), "aac", nil),
        ]
        var failures: [String] = []
        for (o, codec, bits) in cases {
            let meta = TS.metadata(cover: TS.jpeg)
            let name = "\(o.format.rawValue)-\(o.mp3Bitrate)-\(o.pcmDepth.rawValue)-\(o.flacLevel)"
            let out = dir.appendingPathComponent("\(name).\(o.format.fileExtension)")
            let (r, _) = try await TS.export(ExportRequest(input: source, trim: nil, options: o, metadata: meta, output: out))
            guard let json = TS.probe(out),
                  let streams = json["streams"] as? [[String: Any]],
                  let format = json["format"] as? [String: Any] else {
                failures.append("\(name): ffprobe kann die Datei nicht lesen")
                continue
            }
            let audio = streams.first { ($0["codec_type"] as? String) == "audio" } ?? [:]
            let video = streams.first { ($0["codec_type"] as? String) == "video" }
            let gotCodec = audio["codec_name"] as? String ?? "?"
            let rate = Int(audio["sample_rate"] as? String ?? "") ?? 0
            let channels = audio["channels"] as? Int ?? 0
            let duration = Double(format["duration"] as? String ?? "") ?? 0
            let bitRate = Double(audio["bit_rate"] as? String ?? format["bit_rate"] as? String ?? "") ?? 0
            let tags = (format["tags"] as? [String: Any]) ?? (audio["tags"] as? [String: Any]) ?? [:]
            let lower = Dictionary(tags.map { ($0.key.lowercased(), "\($0.value)") }, uniquingKeysWith: { a, _ in a })
            let rawBits = Int(audio["bits_per_raw_sample"] as? String ?? "") ?? (audio["bits_per_sample"] as? Int ?? 0)
            let decoded = TS.ffmpegDecodedFrames(out, channels: 2)
            var notes: [String] = []
            if gotCodec != codec { notes.append("Codec \(gotCodec) statt \(codec)") }
            if rate != 44_100 { notes.append("Rate \(rate)") }
            if channels != 2 { notes.append("Kanäle \(channels)") }
            if let bits, rawBits != bits { notes.append("Bits \(rawBits) statt \(bits)") }
            if o.format == .mp3 {
                let target = Double(o.mp3Bitrate * 1000)
                if abs(bitRate - target) / target > 0.02 { notes.append("Bitrate \(bitRate)") }
                // ffprobe-Dauer zählt alle Frames (ohne LAME-Angaben); FFmpeg dekodiert samplegenau
                if let decoded, decoded != Int(seconds * 44_100) { notes.append("dekodiert \(decoded) Frames") }
            } else if o.format.isLossless {
                if abs(duration - seconds) > 1.0 / 44_100 + 1e-6 { notes.append("Dauer \(duration)") }
                if let decoded, decoded != Int(seconds * 44_100) { notes.append("dekodiert \(decoded) Frames") }
            } else if o.format == .m4a {
                if abs(duration - seconds) > 0.03 { notes.append("Dauer \(duration)") }
            }
            if o.format.supportsTags {
                if lower["title"] != meta.title { notes.append("Titel \(lower["title"] ?? "nil")") }
                if lower["artist"] != meta.artist { notes.append("Interpret \(lower["artist"] ?? "nil")") }
                if lower["album"] != meta.album { notes.append("Album \(lower["album"] ?? "nil")") }
                if o.format != .wav && o.format != .aiff && video == nil { notes.append("kein Cover-Stream") }
            }
            if !notes.isEmpty { failures.append("\(name): \(notes.joined(separator: ", "))") }
            TS.log(String(format: "ffprobe %@: Codec %@, %d Hz, %d Kan., Bits %d, %.0f bit/s, Dauer %.6f s (Engine %.6f s), FFmpeg dekodiert %@ Frames, Titel „%@“, Cover-Stream %@%@",
                          o.summary(), gotCodec, rate, channels, rawBits, bitRate, duration, r.duration, decoded.map { "\($0)" } ?? "–",
                          lower["title"] ?? "–", video == nil ? "nein" : "ja", notes.isEmpty ? "" : " – ABWEICHUNG: " + notes.joined(separator: ", ")))
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }
}
