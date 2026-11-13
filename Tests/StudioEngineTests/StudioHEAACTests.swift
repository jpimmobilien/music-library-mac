import AVFoundation
import XCTest
import MLStudio
@testable import StudioEngine

/// Instagram (und andere Plattformen) liefern Ton häufig als HE-AAC (SBR, bei v2 zusätzlich Parametric Stereo),
/// oft in fragmentiertem MP4 (DASH) oder als Tonspur eines Videos. Die Formatbeschreibung solcher Dateien nennt
/// die Kern-Abtastrate des AAC-Grundlayers (halb so hoch) und bei v2 nur einen Kanal. Wer diese Angaben
/// übernimmt, liest den Ton halb so schnell und eine Oktave tiefer.
///
/// Prüft mit einem 1-kHz-Sinus (6 s) in allen Varianten: Abtastrate, Kanäle, Dauer, Tonhöhe und Lesezeit –
/// über `SourceOpener` (wie die App) und nach dem Export als MP3.
final class StudioHEAACTests: XCTestCase {
    static let seconds = 6.0
    static let frequency = 1000.0

    struct Variant {
        let name: String
        let file: URL
        let rate: Double
        /// Kanäle nach dem Dekodieren (HE-AAC v2: Stereo, obwohl der Grundlayer Mono ist).
        let channels: Int
    }

    struct Measurement {
        var rate: Double = 0
        var channels = 0
        var frames = 0
        var seconds: Double { rate > 0 ? Double(frames) / rate : 0 }
        var pitch = 0.0
        var openMs = 0.0
        var readMs = 0.0
        var reader = ""
    }

    static var afconvert: String? {
        FileManager.default.isExecutableFile(atPath: "/usr/bin/afconvert") ? "/usr/bin/afconvert" : nil
    }

    /// Erzeugt alle Varianten (afconvert ist auf jedem Mac vorhanden; FFmpeg nur für fragmentiert/Video).
    static func makeVariants(in dir: URL) throws -> (variants: [Variant], skipped: [String]) {
        guard let afconvert else { throw XCTSkip("afconvert fehlt") }
        var variants: [Variant] = []
        var skipped: [String] = []
        let codecs: [(name: String, id: String, bitrate: Int, channels: Int)] = [
            ("AAC-LC", "aac ", 128_000, 2), ("HE-AAC", "aach", 64_000, 2), ("HE-AAC v2", "aacp", 32_000, 2),
        ]
        let containers: [(ext: String, type: String)] = [("m4a", "m4af"), ("mp4", "mp4f"), ("aac", "adts")]
        for rate in [44_100.0, 48_000.0] {
            let wav = dir.appendingPathComponent("sine-\(Int(rate)).wav")
            try TS.writePCM(wav, rate: rate, channels: 2, bits: 16, seconds: seconds, signal: .sine(frequency, 0.5))
            for codec in codecs {
                for container in containers {
                    let name = "\(codec.name) \(Int(rate / 100) / 10).\(Int(rate / 100) % 10) kHz .\(container.ext)"
                    let out = dir.appendingPathComponent("\(codec.id.trimmingCharacters(in: .whitespaces))-\(Int(rate)).\(container.ext)")
                    let r = TS.run(afconvert, ["-f", container.type, "-d", "\(codec.id)@\(Int(rate))", "-b", "\(codec.bitrate)", wav.path, out.path], timeout: 120)
                    if r.status == 0, TS.fileSize(out) > 0 {
                        variants.append(Variant(name: name, file: out, rate: rate, channels: codec.channels))
                    } else {
                        skipped.append("\(name): afconvert \(r.status) \(r.err.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))")
                    }
                }
            }
        }
        // Wie bei Instagram: fragmentiertes MP4 (DASH-Tonspur) und Video mit HE-AAC-Ton
        if let ffmpeg = TS.ffmpegPath {
            for base in variants where base.file.pathExtension == "m4a" && base.name.hasPrefix("HE-AAC") {
                let stem = base.file.deletingPathExtension().lastPathComponent
                let jobs: [(String, String, [String])] = [
                    ("fragmentiert 2 s (DASH)", "\(stem)-dash.m4a",
                     ["-i", base.file.path, "-c", "copy", "-movflags", "+empty_moov+default_base_moof+global_sidx", "-frag_duration", "2000000", "-f", "mp4"]),
                    ("fragmentiert je Paket", "\(stem)-frag.m4a",
                     ["-i", base.file.path, "-c", "copy", "-movflags", "+frag_keyframe+empty_moov+default_base_moof", "-f", "mp4"]),
                    ("Video", "\(stem)-video.mp4",
                     ["-f", "lavfi", "-i", "color=c=black:s=320x568:r=30", "-i", base.file.path, "-map", "0:v", "-map", "1:a",
                      "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", "-c:a", "copy", "-shortest", "-movflags", "+faststart"]),
                    ("Video fragmentiert", "\(stem)-video-dash.mp4",
                     ["-f", "lavfi", "-i", "color=c=black:s=320x568:r=30", "-i", base.file.path, "-map", "0:v", "-map", "1:a",
                      "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", "-c:a", "copy", "-shortest",
                      "-movflags", "+empty_moov+default_base_moof+global_sidx", "-frag_duration", "2000000", "-f", "mp4"]),
                ]
                for (label, file, args) in jobs {
                    let out = dir.appendingPathComponent(file)
                    let r = TS.run(ffmpeg, ["-v", "error", "-y"] + args + [out.path], timeout: 300)
                    let name = "\(base.name.replacingOccurrences(of: " .m4a", with: "")) \(label) .\(out.pathExtension)"
                    if r.status == 0, TS.fileSize(out) > 0 {
                        variants.append(Variant(name: name, file: out, rate: base.rate, channels: base.channels))
                    } else {
                        skipped.append("\(name): ffmpeg \(r.status) \(r.err.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))")
                    }
                }
            }
        } else {
            skipped.append("fragmentierte und Video-Varianten: FFmpeg nicht installiert")
        }
        return (variants, skipped)
    }

    /// Grundfrequenz über Nulldurchgänge mit Hysterese (Mitte der Datei, Ränder und Encoder-Verzögerung ausgelassen).
    static func pitch(_ samples: [Float], rate: Double) -> Double {
        let skip = Int(rate * 0.5)
        guard samples.count > 3 * skip else { return 0 }
        let part = samples[skip..<(samples.count - skip)]
        var cycles = 0
        var armed = false
        var first: Int?
        var last = 0
        for (i, s) in zip(part.indices, part) {
            if s < -0.05 { armed = true }
            if armed && s > 0.05 {
                armed = false
                if first == nil { first = i } else { cycles += 1; last = i }
            }
        }
        guard let first, cycles > 0, last > first else { return 0 }
        return Double(cycles) / (Double(last - first) / rate)
    }

    static func measure(_ url: URL) async throws -> Measurement {
        var m = Measurement()
        let t0 = Date()
        let reader = try await SourceOpener.open(url, downmixToStereo: true)
        m.openMs = Date().timeIntervalSince(t0) * 1000
        defer { reader.close() }
        m.reader = String(describing: type(of: reader))
        m.rate = reader.sampleRate
        m.channels = reader.channelCount
        let block = FloatBlock(channels: reader.channelCount, capacity: 16_384)
        var left: [Float] = []
        left.reserveCapacity(Int(reader.sampleRate * seconds * 2.2))
        let t1 = Date()
        while true {
            let n = try reader.read(into: block, maxFrames: block.capacity)
            if n == 0 { break }
            left.append(contentsOf: UnsafeBufferPointer(start: block.channels[0], count: n))
            m.frames += n
            if m.frames > Int(reader.sampleRate * 60) { break }   // Schutz gegen Endlosschleifen
        }
        m.readMs = Date().timeIntervalSince(t1) * 1000
        m.pitch = pitch(left, rate: m.rate)
        return m
    }

    func testHEAACAndFragmentedMP4KeepRateAndPitch() async throws {
        let dir = try TS.makeDir("heaac")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (variants, skipped) = try Self.makeVariants(in: dir)
        for s in skipped { TS.log("HE-AAC: übersprungen – \(s)") }
        XCTAssertGreaterThanOrEqual(variants.count, 12, "zu wenige Testdateien erzeugt")
        var failures: [String] = []
        for v in variants {
            do {
                let m = try await Self.measure(v.file)
                let ok = m.rate == v.rate && m.channels == v.channels && abs(m.seconds - Self.seconds) < 0.2 && abs(m.pitch - Self.frequency) < 15
                TS.log(String(format: "HE-AAC %@ %@: %@ – %.0f Hz (erwartet %.0f), %d Kanäle (erwartet %d), Dauer %.3f s, Tonhöhe %.1f Hz, Öffnen %.0f ms, Lesen %.0f ms",
                              ok ? "OK" : "FEHLER", v.name, m.reader, m.rate, v.rate, m.channels, v.channels, m.seconds, m.pitch, m.openMs, m.readMs))
                if !ok {
                    failures.append(String(format: "%@: %.0f Hz, %d Kanäle, %.2f s, %.0f Hz Tonhöhe", v.name, m.rate, m.channels, m.seconds, m.pitch))
                }
            } catch {
                TS.log("HE-AAC FEHLER \(v.name): \(error)")
                failures.append("\(v.name): \(error)")
            }
        }
        XCTAssertTrue(failures.isEmpty, "Falsch gelesen:\n" + failures.joined(separator: "\n"))
    }

    /// Ende zu Ende wie in der App: HE-AAC-Quelle → MP3 (Abtastrate „Original“) → Dauer und Tonhöhe der MP3.
    func testHEAACExportToMP3KeepsPitch() async throws {
        let dir = try TS.makeDir("heaac-mp3")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (variants, _) = try Self.makeVariants(in: dir)
        let chosen = variants.filter { $0.name.hasPrefix("HE-AAC") && ($0.file.pathExtension == "mp4" || $0.name.contains("DASH")) }
        XCTAssertFalse(chosen.isEmpty)
        var failures: [String] = []
        for v in chosen {
            let out = dir.appendingPathComponent(v.file.deletingPathExtension().lastPathComponent + "-export.mp3")
            do {
                let t0 = Date()
                let (r, _) = try await TS.export(ExportRequest(input: v.file, trim: nil, options: .defaults(for: .mp3), metadata: StudioMetadata(), output: out))
                let ms = Date().timeIntervalSince(t0) * 1000
                let decoded = try TS.readAll(out)
                let pitch = Self.pitch(decoded.channels[0], rate: decoded.rate)
                let ok = abs(decoded.duration - Self.seconds) < 0.2 && abs(pitch - Self.frequency) < 15 && Double(r.sampleRate) == v.rate
                TS.log(String(format: "HE-AAC → MP3 %@ %@: %d Hz (Quelle %.0f), Dauer %.3f s, Tonhöhe %.1f Hz, Export %.0f ms",
                              ok ? "OK" : "FEHLER", v.name, r.sampleRate, v.rate, decoded.duration, pitch, ms))
                if !ok { failures.append(String(format: "%@: %d Hz, %.2f s, %.0f Hz", v.name, r.sampleRate, decoded.duration, pitch)) }
            } catch {
                TS.log("HE-AAC → MP3 FEHLER \(v.name): \(error)")
                failures.append("\(v.name): \(error)")
            }
        }
        XCTAssertTrue(failures.isEmpty, "Export falsch:\n" + failures.joined(separator: "\n"))
    }
}
