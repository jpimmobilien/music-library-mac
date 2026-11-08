import Foundation
import AVFoundation
import MLStudio

/// Internet-Quellen über yt-dlp (YouTube, SoundCloud, …); Spotify nur Metadaten (oEmbed), Audio ist DRM-geschützt.
///
/// Keine Cookies, keine Anmeldung, keine Umgehung von Alters-, Bezahl- oder Privatsperren: solche Quellen
/// werden mit einer verständlichen Meldung abgelehnt.
public struct YtDlpSourceProvider: RemoteSourceProviding {
    public let tools: StudioToolManager

    public init(tools: StudioToolManager) {
        self.tools = tools
    }

    // MARK: Analyse

    public func analyze(url: URL, kind: SourceKind) async throws -> SourceInfo {
        switch try await lookup(url: url, kind: kind) {
        case .single(let info):
            return info
        case .playlist(let title, let entries):
            throw StudioError.other("„\(title)“ ist eine Playlist mit \(entries.count) Titeln – bitte die Adresse direkt eingeben, um alle Titel in die Warteschlange zu legen.")
        }
    }

    public func lookup(url: URL, kind: SourceKind) async throws -> RemoteLookup {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { throw StudioError.unsupportedURL }
        if kind == .spotify { return .single(try await spotify(url)) }
        let paths = await tools.paths()
        guard let ytDlp = paths.ytDlp else { throw StudioError.toolMissing("yt-dlp") }
        if kind == .youtube, paths.deno == nil { throw StudioError.toolMissing("Deno") }
        let args = YtDlpOutput.analyzeArguments(url: url, kind: kind, cacheDirectory: paths.cacheDirectory, denoPath: paths.deno)
        let result = try await StudioProcess.run(ytDlp, args, environment: environment(paths), timeout: 180)
        if result.timedOut { throw StudioError.network("Zeitüberschreitung bei der Abfrage.") }
        guard result.status == 0, let data = result.stdout.data(using: .utf8), !data.isEmpty else {
            throw YtDlpOutput.mapError(result.stderr, kind: kind)
        }
        return try Self.parseLookup(data, kind: kind, requestedURL: url)
    }

    public func expandPlaylist(url: URL) async throws -> [URL] {
        let kind = SourceURL.classify(url.absoluteString)?.kind ?? .web
        if case .playlist(_, let entries) = try await lookup(url: url, kind: kind) { return entries.map(\.url) }
        return [url]
    }

    /// JSON von `yt-dlp -J --flat-playlist` → einzelner Titel oder Playlist.
    static func parseLookup(_ data: Data, kind: SourceKind, requestedURL: URL) throws -> RemoteLookup {
        let decoder = JSONDecoder()
        guard let info = try? decoder.decode(YtDlpInfo.self, from: data), let extra = try? decoder.decode(YtDlpExtra.self, from: data) else {
            throw StudioError.other("Die Antwort von yt-dlp konnte nicht gelesen werden.")
        }
        if extra.isPlaylist {
            let entries = extra.playlistEntries(kind: kind)
            guard !entries.isEmpty else { throw StudioError.unavailable("Die Playlist enthält keine abrufbaren Titel.") }
            return .playlist(title: (extra.title ?? info.title ?? "Playlist").trimmingCharacters(in: .whitespacesAndNewlines), entries: entries)
        }
        if kind == .soundcloud, YtDlpOutput.isPreviewFormat(formatID: extra.format_id, formatNote: extra.format_note, url: extra.url) {
            throw StudioError.previewOnly
        }
        var source = info.sourceInfo(kind: kind, requestedURL: requestedURL)
        if source.codec == nil || source.codec == "none" { source.codec = nil }
        return .single(source)
    }

    // MARK: Laden

    public func download(_ source: SourceInfo, into directory: URL, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL {
        if source.kind == .spotify || !source.kind.supportsAudio { throw StudioError.spotifyDRM }
        if source.kind == .localFile { throw StudioError.unsupportedURL }
        if source.isLive { throw StudioError.liveStream }
        let paths = await tools.paths()
        guard let ytDlp = paths.ytDlp else { throw StudioError.toolMissing("yt-dlp") }
        if source.kind == .youtube, paths.deno == nil { throw StudioError.toolMissing("Deno") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Liefert die Quelle nur Opus/WebM, wandelt yt-dlp mit einem vorhandenen FFmpeg in WAV.
        let needsConversion = YtDlpOutput.needsConversion(codec: source.codec, ext: nil)
        if needsConversion, paths.ffmpeg == nil {
            throw StudioError.other("Diese Quelle liefert nur Opus/WebM-Audio, das die App nicht direkt lesen kann. Zum Umwandeln wird FFmpeg benötigt (z. B. über Homebrew: „brew install ffmpeg“).")
        }
        var file = try await runDownload(ytDlp, source: source, directory: directory, paths: paths,
                                         convert: needsConversion ? paths.ffmpeg : nil, progress: progress)
        var ext = file.pathExtension.lowercased()
        if !YtDlpOutput.readableExtensions.contains(ext) {
            // Format war bei der Analyse nicht bekannt: mit FFmpeg nachträglich umwandeln (yt-dlp verwendet die
            // bereits geladene Datei), sonst verständlich ablehnen.
            guard let ffmpeg = paths.ffmpeg, !needsConversion else {
                try? FileManager.default.removeItem(at: file)
                throw StudioError.other("Diese Quelle liefert nur \(ext.uppercased())-Audio, das die App nicht direkt lesen kann. Zum Umwandeln wird FFmpeg benötigt (z. B. über Homebrew: „brew install ffmpeg“).")
            }
            file = try await runDownload(ytDlp, source: source, directory: directory, paths: paths, convert: ffmpeg, progress: progress)
            ext = file.pathExtension.lowercased()
            guard YtDlpOutput.readableExtensions.contains(ext) else { throw StudioError.unsupportedFile(ext.uppercased()) }
        }
        // SoundCloud-Hörprobe: deutlich kürzer als angegeben (Go+-Titel liefern nur ~30 s).
        if source.kind == .soundcloud, let expected = source.duration, expected >= 60 {
            if let actual = await Self.duration(of: file), actual < 45, actual < expected * 0.6 {
                try? FileManager.default.removeItem(at: file)
                throw StudioError.previewOnly
            }
        }
        progress(DownloadProgress(fraction: 1))
        return file
    }

    private func runDownload(_ ytDlp: String, source: SourceInfo, directory: URL, paths: StudioToolManager.Paths, convert ffmpeg: String?,
                             progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL {
        let args = YtDlpOutput.downloadArguments(url: source.url, kind: source.kind, directory: directory, cacheDirectory: paths.cacheDirectory,
                                                 denoPath: paths.deno, convertWith: ffmpeg)
        let collector = PathCollector()
        let throttle = ThrottleGate(interval: 0.2)
        let result = try await StudioProcess.run(ytDlp, args, environment: environment(paths)) { line, stream in
            if let p = YtDlpOutput.parseProgress(line) {
                if throttle.allow(force: p.fraction == 1) { progress(p) }
            } else if stream == .stdout {
                collector.consider(line)
            }
        }
        try Task.checkCancellation()
        guard result.status == 0 else { throw YtDlpOutput.mapError(result.stderr, kind: source.kind) }
        guard let file = collector.path(in: directory) ?? Self.newestMedia(in: directory) else {
            throw StudioError.other("yt-dlp hat keine Datei geliefert.")
        }
        return file
    }

    /// Neueste fertige Mediendatei im Ordner (Rückfall, falls yt-dlp den Pfad nicht ausgegeben hat).
    static func newestMedia(in directory: URL) -> URL? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return nil }
        let partial: Set<String> = ["part", "ytdl", "temp", "tmp", "json", "jpg", "webp", "png"]
        return items.filter { !partial.contains($0.pathExtension.lowercased()) && !$0.lastPathComponent.contains(".part-Frag") }
            .max { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return da < db
            }
    }

    static func duration(of file: URL) async -> Double? {
        let asset = AVURLAsset(url: file)
        guard let d = try? await asset.load(.duration) else { return nil }
        let s = CMTimeGetSeconds(d)
        return s.isFinite && s > 0 ? s : nil
    }

    // MARK: Vorschaubild

    public func thumbnail(for source: SourceInfo) async -> Data? {
        if let data = source.thumbnail { return StudioHTTP.normalizedImage(data) }
        guard let url = source.thumbnailURL else { return nil }
        return await StudioHTTP.thumbnail(from: url)
    }

    // MARK: Spotify (nur Metadaten)

    private func spotify(_ url: URL) async throws -> SourceInfo {
        guard let endpoint = SpotifyOEmbed.endpoint(for: url) else { throw StudioError.unsupportedURL }
        let data = try await StudioHTTP.data(from: endpoint, maxBytes: 1024 * 1024, timeout: 15, accept: "application/json")
        guard let oembed = try? JSONDecoder().decode(SpotifyOEmbed.self, from: data) else {
            throw StudioError.unavailable("Spotify hat keine Angaben zu dieser Adresse geliefert.")
        }
        var info = oembed.sourceInfo(requestedURL: url)
        if let thumb = info.thumbnailURL { info.thumbnail = await StudioHTTP.thumbnail(from: thumb) }
        return info
    }

    private func environment(_ paths: StudioToolManager.Paths) -> [String: String] {
        var extra: [String] = []
        for p in [paths.ytDlp, paths.deno, paths.ffmpeg].compactMap({ $0 }) {
            extra.append((p as NSString).deletingLastPathComponent)
        }
        return StudioProcess.environment(extraPaths: extra)
    }
}

/// Sammelt den von `--print after_move:filepath` ausgegebenen Pfad.
private final class PathCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var candidates: [String] = []

    func consider(_ line: String) {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("/") else { return }
        lock.lock(); candidates.append(t); lock.unlock()
    }

    func path(in directory: URL) -> URL? {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        for c in candidates.reversed() where fm.fileExists(atPath: c) {
            return URL(fileURLWithPath: c)
        }
        return nil
    }
}

/// Lässt Meldungen höchstens alle `interval` Sekunden durch (Fortschritt ~5×/s).
public final class ThrottleGate: @unchecked Sendable {
    private let lock = NSLock()
    private var last: TimeInterval = -.greatestFiniteMagnitude
    public let interval: TimeInterval

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    public func allow(force: Bool = false) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock(); defer { lock.unlock() }
        if force || now - last >= interval {
            last = now
            return true
        }
        return false
    }
}
