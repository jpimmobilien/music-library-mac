import XCTest
import AVFoundation
import MLStudio
@testable import StudioEngine

/// Echte Internet-Quellen mit frei lizenzierten Testinhalten – nur mit `ML_STUDIO_WEBTEST=1`
/// (siehe scripts/studio_webcheck.sh). Installiert yt-dlp und Deno über den `StudioToolManager` der App,
/// prüft Analyse, Vorschaubild, Download, Lesen mit AVFoundation und Export nach MP3. Keine Cookies, keine
/// Anmeldung: Blockiert ein Dienst den Rechner (z. B. YouTube-Bot-Prüfung), steht das so im Bericht.
final class RemoteWebCheckTests: XCTestCase {
    struct Sample {
        let name: String
        let url: String
        let kind: SourceKind
        let license: String
        /// Ausschnitt für den MP3-Export (nil = ganze Datei, z. B. kurze Reels).
        var trim: TrimRange? = TrimRange(start: 10, end: 40)
        /// Formatliste von yt-dlp (`-F`) in den Bericht schreiben.
        var listFormats = false
    }

    static let samples = [
        Sample(name: "YouTube „Big Buck Bunny“", url: "https://www.youtube.com/watch?v=aqz-KE-bpKQ", kind: .youtube,
               license: "CC BY 3.0, Blender Foundation (peach.blender.org)"),
        Sample(name: "SoundCloud „Echoes“", url: "https://soundcloud.com/scottbuckley/echoes-cc-by", kind: .soundcloud,
               license: "CC BY 4.0, Scott Buckley (scottbuckley.com.au)"),
        // Öffentliches Reel des NASA-Kontos (NASA-Inhalte sind in den USA in der Regel gemeinfrei); keine Anmeldung.
        Sample(name: "Instagram-Reel (NASA)", url: "https://www.instagram.com/reel/Dbn-XJhk0_-/", kind: SourceURL.classify("https://www.instagram.com/reel/Dbn-XJhk0_-/")!.kind,
               license: "NASA (gemeinfrei, nasa.gov/nasa-brand-center/images-and-media)", trim: nil, listFormats: true),
    ]
    /// Öffentliche Spotify-Playlist – nur Metadaten (oEmbed); Audio ist DRM-geschützt.
    static let spotify = "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M"

    final class Report: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var lines: [String] = []
        private(set) var failures: [String] = []
        let file: URL

        init(file: URL) { self.file = file }

        func add(_ status: String, _ text: String) {
            let line = "\(status) \(text)"
            lock.lock()
            lines.append(line)
            if status == "FEHLER" { failures.append(text) }
            lock.unlock()
            print("[Studio] \(line)")
            write()
        }

        func write() {
            lock.lock()
            let text = lines.joined(separator: "\n") + "\n"
            lock.unlock()
            try? text.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    static func message(_ error: Error) -> String {
        (error as? StudioError)?.errorDescription ?? error.localizedDescription
    }

    func testRealSourcesWithFreeContent() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["ML_STUDIO_WEBTEST"] == "1" else { throw XCTSkip("Nur mit ML_STUDIO_WEBTEST=1 (scripts/studio_webcheck.sh).") }
        let out = URL(fileURLWithPath: env["ML_STUDIO_WEBCHECK_OUT"] ?? NSTemporaryDirectory() + "studio-webcheck", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let report = Report(file: out.appendingPathComponent("report.txt"))
        report.add("INFO", "Rechner: \(ProcessInfo.processInfo.operatingSystemVersionString)")

        // 1. Werkzeuge über den StudioToolManager der App (nur verwaltete Werkzeuge, keine Systeminstallation)
        let tools = StudioToolManager(supportDirectory: out.appendingPathComponent("Tools", isDirectory: true), systemSearchPaths: [])
        let started = Date()
        let lastStep = Report(file: out.appendingPathComponent("install-steps.txt"))
        do {
            let status = try await tools.installOrUpdate { p in
                if !p.step.contains("wird geladen …") || (p.fraction ?? 0) >= 0.4 { lastStep.add("SCHRITT", p.step) }
            }
            report.add(status.ytDlpOrigin == .managed && status.denoOrigin == .managed ? "OK" : "FEHLER",
                       "Werkzeuge installiert (SHA-256 geprüft) in \(Int(Date().timeIntervalSince(started))) s: yt-dlp \(status.ytDlpVersion ?? "?"), Deno \(status.denoVersion ?? "?")")
        } catch {
            report.add("FEHLER", "Werkzeuge: \(Self.message(error))")
            XCTFail(report.failures.joined(separator: "\n"))
            return
        }
        let provider = YtDlpSourceProvider(tools: tools)

        // 2. YouTube und SoundCloud
        for sample in Self.samples {
            await check(sample, provider: provider, out: out, report: report)
        }

        // 3. Spotify: nur Metadaten, Download wird abgelehnt
        do {
            let info = try await provider.analyze(url: URL(string: Self.spotify)!, kind: .spotify)
            report.add("OK", "Spotify: Metadaten „\(info.title)“, Vorschaubild \(info.thumbnail?.count ?? 0) Bytes")
            do {
                _ = try await provider.download(info, into: out.appendingPathComponent("spotify", isDirectory: true), progress: { _ in })
                report.add("FEHLER", "Spotify: Download hätte abgelehnt werden müssen")
            } catch let e as StudioError where e == .spotifyDRM {
                report.add("OK", "Spotify: Download abgelehnt – „\(Self.message(e))“")
            }
        } catch {
            report.add("FEHLER", "Spotify: \(Self.message(error))")
        }
        report.write()
        XCTAssertTrue(report.failures.isEmpty, report.failures.joined(separator: "\n"))
    }

    private func check(_ sample: Sample, provider: YtDlpSourceProvider, out: URL, report: Report) async {
        let name = sample.name
        report.add("INFO", "\(name): \(sample.url) – Lizenz \(sample.license)")
        let info: SourceInfo
        do {
            let t0 = Date()
            info = try await provider.analyze(url: URL(string: sample.url)!, kind: sample.kind)
            report.add("OK", "\(name): Analyse in \(Int(Date().timeIntervalSince(t0))) s – „\(info.title)“, Interpret „\(info.suggested.artist)“, "
                       + "\(Int(info.duration ?? 0)) s, Codec \(info.codec ?? "?"), \(info.bitrateKbps ?? 0) kbit/s, \(info.sampleRate ?? 0) Hz")
        } catch {
            if record(error, step: "Analyse", name: name, report: report), let raw = await rawError(sample, tools: provider.tools) {
                report.add("INFO", "\(name): yt-dlp meldet wörtlich: \(raw)")
            }
            return
        }

        if let thumb = await provider.thumbnail(for: info) {
            let kind = thumb.prefix(2) == Data([0xFF, 0xD8]) ? "JPEG" : (thumb.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]) ? "PNG" : "?")
            report.add(kind == "?" ? "FEHLER" : "OK", "\(name): Vorschaubild \(thumb.count) Bytes (\(kind))")
        } else {
            report.add("HINWEIS", "\(name): kein Vorschaubild")
        }

        if sample.listFormats, let list = await formatList(sample, tools: provider.tools) {
            for line in list { report.add("INFO", "\(name): Format \(line)") }
        }

        let dir = out.appendingPathComponent("media/\(sample.kind.rawValue)", isDirectory: true)
        let file: URL
        do {
            let t0 = Date()
            let throttle = ThrottleGate(interval: 5)
            file = try await provider.download(info, into: dir) { p in
                if throttle.allow(force: p.fraction == 1) {
                    print("[Studio] \(name): Download \(Int((p.fraction ?? 0) * 100)) % (\(p.bytesDone ?? 0) Bytes)")
                }
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
            report.add("OK", "\(name): geladen in \(Int(Date().timeIntervalSince(t0))) s – \(file.lastPathComponent), \(size) Bytes")
        } catch {
            _ = record(error, step: "Download", name: name, report: report)
            return
        }

        do {
            let audio = try AVAudioFile(forReading: file)
            let seconds = Double(audio.length) / audio.fileFormat.sampleRate
            report.add("OK", "\(name): AVFoundation liest die Datei – \(String(format: "%.1f", seconds)) s, \(Int(audio.fileFormat.sampleRate)) Hz, "
                       + "\(audio.fileFormat.channelCount) Kanäle")
        } catch {
            report.add("FEHLER", "\(name): AVFoundation kann die Datei nicht lesen – \(error.localizedDescription)")
        }

        // So liest die App die Datei (Abtastrate, Kanäle, Dauer) – im Vergleich zur Dauer laut Quelle
        do {
            let t0 = Date()
            let reader = try await SourceOpener.open(file, downmixToStereo: true)
            let block = FloatBlock(channels: reader.channelCount, capacity: 16_384)
            var frames = 0
            while true {
                let n = try reader.read(into: block, maxFrames: block.capacity)
                if n == 0 { break }
                frames += n
            }
            reader.close()
            let seconds = Double(frames) / reader.sampleRate
            let expected = info.duration ?? 0
            let plausible = expected <= 0 || abs(seconds - expected) < max(1.5, expected * 0.03)
            report.add(plausible ? "OK" : "FEHLER", "\(name): App liest \(type(of: reader)) – \(Int(reader.sampleRate)) Hz, \(reader.channelCount) Kanäle, "
                       + String(format: "%.2f s (Quelle %.2f s), gelesen in %.1f s", seconds, expected, Date().timeIntervalSince(t0)))
        } catch {
            report.add("FEHLER", "\(name): App kann die Datei nicht lesen – \(Self.message(error))")
        }

        let mp3 = out.appendingPathComponent("export-\(sample.kind.rawValue).mp3")
        do {
            var meta = info.suggested
            meta.cover = await provider.thumbnail(for: info)
            let request = ExportRequest(input: file, trim: sample.trim, options: .defaults(for: .mp3), metadata: meta, output: mp3)
            let t0 = Date()
            let r = try await AudioExporter().export(request, pause: nil, progress: { _ in })
            let part = sample.trim.map { String(format: "Ausschnitt %.0f–%.0f s", $0.start, $0.end) } ?? "ganze Datei"
            report.add("OK", "\(name): Export MP3 (\(part)) in \(String(format: "%.1f", Date().timeIntervalSince(t0))) s – \(String(format: "%.2f", r.duration)) s, \(r.bitrateKbps) kbit/s, "
                       + "\(r.sampleRate) Hz, Tags \(r.tagsWritten ? "ja" : "nein")")
        } catch {
            let text = Self.message(error)
            if text.contains("noch nicht verfügbar") {
                report.add("HINWEIS", "\(name): Export nach MP3 nicht geprüft – auf diesem Zweig ist der Exporter noch der Platzhalter des Engine-Teils (\(text))")
            } else {
                report.add("FEHLER", "\(name): Export MP3 – \(text)")
            }
        }
    }

    /// Sperren durch den Dienst (Bot-Prüfung, Land) sind ehrliche Ergebnisse, keine Programmfehler.
    /// - Returns: true, wenn der Dienst den Rechner blockiert hat.
    private func record(_ error: Error, step: String, name: String, report: Report) -> Bool {
        let text = Self.message(error)
        if let e = error as? StudioError {
            switch e {
            case .unavailable(let detail) where detail.contains("Bot"):
                report.add("BLOCKIERT", "\(name): \(step) – \(text)")
                return true
            case .geoBlocked, .loginRequired:
                report.add("BLOCKIERT", "\(name): \(step) – \(text)")
                return true
            default:
                break
            }
        }
        report.add("FEHLER", "\(name): \(step) – \(text)")
        return false
    }

    /// Formatliste (`yt-dlp -F`): Kennung, Endung, Codec, Abtastrate, Bitrate, Protokoll.
    private func formatList(_ sample: Sample, tools: StudioToolManager) async -> [String]? {
        let paths = await tools.paths()
        guard let ytDlp = paths.ytDlp, let url = URL(string: sample.url) else { return nil }
        let args = ["-F", "--ignore-config", "--no-warnings", "--no-color", "--no-playlist"] + YtDlpOutput.jsRuntimeArguments(kind: sample.kind, denoPath: paths.deno)
            + ["--", url.absoluteString]
        guard let r = try? await StudioProcess.run(ytDlp, args, environment: StudioProcess.environment(), timeout: 120) else { return nil }
        let lines = (r.stdout + r.stderr).split(whereSeparator: \.isNewline).map(String.init)
        return Array(lines.filter { !$0.hasPrefix("[") }.prefix(40))
    }

    /// Wörtliche Fehlerzeile von yt-dlp (gleicher Aufruf wie die Analyse) – für einen genauen Bericht.
    private func rawError(_ sample: Sample, tools: StudioToolManager) async -> String? {
        let paths = await tools.paths()
        guard let ytDlp = paths.ytDlp, let url = URL(string: sample.url) else { return nil }
        let args = YtDlpOutput.analyzeArguments(url: url, kind: sample.kind, cacheDirectory: paths.cacheDirectory, denoPath: paths.deno)
        guard let r = try? await StudioProcess.run(ytDlp, args, environment: StudioProcess.environment(), timeout: 120) else { return nil }
        return r.stderr.split(whereSeparator: \.isNewline).last(where: { $0.hasPrefix("ERROR:") }).map(String.init)
    }
}
