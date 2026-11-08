import Foundation
import MLStudio

/// Aufrufe und Ausgaben von yt-dlp: Argumente, maschinenlesbarer Fortschritt, Fehlertexte → `StudioError`.
/// Reine Funktionen (testbar ohne Netzwerk).
public enum YtDlpOutput {
    /// Kennung der eigenen Fortschrittszeilen.
    public static let progressPrefix = "ML-PROGRESS"

    /// `--progress-template`: Status, geladene Bytes, Gesamtgröße, geschätzte Größe, Geschwindigkeit, Restzeit,
    /// Fragment-Nummer und -Anzahl (HLS/DASH). Fehlende Werte gibt yt-dlp als „NA“ aus.
    public static let progressTemplate = "download:\(progressPrefix) %(progress.status)s %(progress.downloaded_bytes)s %(progress.total_bytes)s "
        + "%(progress.total_bytes_estimate)s %(progress.speed)s %(progress.eta)s %(progress.fragment_index)s %(progress.fragment_count)s"

    /// Formatwahl: zuerst, was AVFoundation direkt lesen kann (M4A/AAC, MP3), sonst bestes Audio.
    public static let audioFormatSelector = "bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/bestaudio[ext=mp3]/bestaudio/best"

    /// Gemeinsame Argumente: keine Konfigurationsdateien des Nutzers, eigener Zwischenspeicher, keine Farben.
    public static func commonArguments(cacheDirectory: URL?) -> [String] {
        var args = ["--ignore-config", "--no-warnings", "--no-color", "--no-playlist", "--socket-timeout", "30"]
        if let cacheDirectory {
            args += ["--cache-dir", cacheDirectory.path]
        } else {
            args.append("--no-cache-dir")
        }
        return args
    }

    /// JavaScript-Laufzeit für YouTube (Deno, ausdrücklich mit Pfad – Apps aus dem Finder haben keinen PATH).
    public static func jsRuntimeArguments(kind: SourceKind, denoPath: String?) -> [String] {
        guard kind == .youtube, let denoPath else { return [] }
        return ["--js-runtimes", "deno:\(denoPath)"]
    }

    /// Argumente für die Analyse (`-J`): Playlists flach (schnell), Formatwahl wie beim Laden, damit Codec und
    /// Bitrate der tatsächlich geladenen Spur angezeigt werden.
    public static func analyzeArguments(url: URL, kind: SourceKind, cacheDirectory: URL?, denoPath: String?) -> [String] {
        ["-J", "--flat-playlist", "--skip-download", "--playlist-items", "1:\(RemoteLookup.maxEntries)", "-f", audioFormatSelector]
            + commonArguments(cacheDirectory: cacheDirectory)
            + jsRuntimeArguments(kind: kind, denoPath: denoPath)
            + ["--", url.absoluteString]
    }

    /// Argumente zum Laden der Audiospur nach `directory`.
    /// - Parameter convertWith: FFmpeg-Pfad, falls die Quelle nur Opus/WebM liefert (→ WAV).
    public static func downloadArguments(url: URL, kind: SourceKind, directory: URL, cacheDirectory: URL?, denoPath: String?,
                                         convertWith ffmpeg: String?) -> [String] {
        var args = ["-f", audioFormatSelector,
                    "-P", directory.path, "-o", "%(id)s.%(ext)s", "--trim-filenames", "120",
                    "--newline", "--progress", "--progress-template", progressTemplate,
                    "--print", "after_move:filepath",
                    "--continue", "--no-mtime", "--no-overwrites", "--retries", "3", "--fragment-retries", "3"]
        if let ffmpeg {
            args += ["--ffmpeg-location", ffmpeg, "-x", "--audio-format", "wav"]
        }
        return args + commonArguments(cacheDirectory: cacheDirectory) + jsRuntimeArguments(kind: kind, denoPath: denoPath) + ["--", url.absoluteString]
    }

    // MARK: Fortschritt

    /// Liest eine Fortschrittszeile; nil für andere Zeilen.
    public static func parseProgress(_ line: String) -> DownloadProgress? {
        guard let range = line.range(of: progressPrefix) else { return nil }
        let fields = line[range.upperBound...].split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !fields.isEmpty else { return nil }
        func number(_ i: Int) -> Double? {
            guard i < fields.count else { return nil }
            let f = fields[i]
            if f == "NA" || f == "None" || f == "null" { return nil }
            guard let v = Double(f), v.isFinite, v >= 0 else { return nil }
            return v
        }
        let status = fields[0]
        let done = number(1)
        let total = number(2) ?? number(3)
        let speed = number(4)
        let eta = number(5)
        let fragIndex = number(6)
        let fragCount = number(7)
        var fraction: Double?
        if let done, let total, total > 0 {
            fraction = min(1, done / total)
        } else if let fragIndex, let fragCount, fragCount > 0 {
            fraction = min(1, fragIndex / fragCount)
        }
        if status == "finished" { fraction = 1 }
        return DownloadProgress(fraction: fraction, bytesDone: done.map { Int64($0) }, bytesTotal: total.map { Int64($0) },
                                bytesPerSecond: speed, etaSeconds: eta)
    }

    // MARK: Fehler

    /// Letzte Fehlerzeile („ERROR: …“) ohne Vorsatz, z. B. „[youtube] abc: Video unavailable“ → „Video unavailable“.
    public static func lastErrorLine(_ stderr: String) -> String? {
        let lines = stderr.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let line = lines.last(where: { $0.hasPrefix("ERROR:") }) ?? lines.last(where: { !$0.isEmpty && !$0.hasPrefix("WARNING:") && !$0.contains(progressPrefix) }) else { return nil }
        var text = line.hasPrefix("ERROR:") ? String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces) : line
        // „[extractor] id: Meldung“ → „Meldung“
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            text = String(text[text.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            if let colon = text.range(of: ": "), !text[..<colon.lowerBound].contains(" ") {
                text = String(text[colon.upperBound...])
            }
        }
        return text.isEmpty ? nil : text
    }

    /// Fehlertext von yt-dlp auf verständliche Fehler abbilden. Anmeldung, Alters- und Bezahlsperren werden
    /// nicht umgangen – sie werden nur benannt.
    public static func mapError(_ stderr: String, kind: SourceKind) -> StudioError {
        let detail = lastErrorLine(stderr) ?? ""
        let t = stderr.lowercased()
        func has(_ needles: String...) -> Bool { needles.contains { t.contains($0) } }

        if has("no space left on device", "errno 28") { return .diskFull }
        if has("not a bot", "confirm you’re not a bot", "confirm you're not a bot") {
            return .unavailable("YouTube verlangt eine Anmeldung zur Bestätigung, dass kein Bot zugreift (häufig in Rechenzentren oder über VPN). Ohne Anmeldung kann der Inhalt nicht geladen werden.")
        }
        if has("confirm your age", "age-restricted", "age restricted", "inappropriate for some users", "age verification", "age-gate", "age gate") {
            return .ageRestricted
        }
        if has("private video", "this video is private", "video is private", "this track is private", "private track", "is private", "private playlist", "playlist is private") {
            return .privateContent
        }
        if has("members-only", "members only", "join this channel", "premium members", "youtube premium", "requires payment", "purchase", "rental",
               "subscriber_only", "subscribers only", "premium_only", "paid content", "go+ ") {
            return .loginRequired
        }
        if has("not available in your country", "not made this video available in your country", "blocked it in your country",
               "geo restrict", "geo-restrict", "geoblock", "not available from your location", "not available in your region", "in your territory") {
            return .geoBlocked
        }
        if has("live event will begin", "this live event", "premieres in", "is live now", "live stream recording is not available",
               "is currently live", "is_live", "is_upcoming", "will begin in") {
            return .liveStream
        }
        if has("preview", "snippet") && kind == .soundcloud { return .previewOnly }
        if has("sign in", "login required", "log in", "--cookies", "cookies-from-browser", "requires authentication", "authentication required") {
            return .loginRequired
        }
        if has("unsupported url") { return .unsupportedURL }
        if has("ffmpeg not found", "ffprobe and ffmpeg not found", "ffmpeg is not installed") {
            return .other("Diese Quelle liefert nur Opus/WebM-Audio. Zum Umwandeln wird FFmpeg benötigt (z. B. über Homebrew: „brew install ffmpeg“).")
        }
        if has("requested format is not available", "no video formats found", "no formats found") {
            return .unavailable("Für diese Quelle wurde keine Audiospur gefunden.")
        }
        if has("n challenge", "nsig extraction", "signature extraction failed", "js runtime", "javascript runtime", "ejs script", "challenge solving") {
            return .other("YouTube konnte nicht entschlüsselt werden. Bitte die Werkzeuge im Audio Studio aktualisieren.")
        }
        if has("video unavailable", "this video is unavailable", "has been removed", "no longer available", "does not exist", "not found",
               "http error 404", "http error 410", "unable to find", "this content isn", "content is not available", "account associated with this video has been terminated",
               "copyright") {
            return .unavailable(detail)
        }
        if has("unable to download webpage", "urlopen error", "timed out", "timeout", "connection reset", "connection refused", "network is unreachable",
               "nodename nor servname", "name or service not known", "temporary failure in name resolution", "ssl", "certificate",
               "http error 5", "http error 429", "too many requests", "remote end closed", "unable to connect", "failed to resolve", "errno 8", "errno 61", "errno 65") {
            return .network(detail)
        }
        return .other(detail.isEmpty ? "yt-dlp ist mit einem Fehler beendet worden." : "yt-dlp: \(detail)")
    }

    // MARK: Formate

    /// Audio, das die App ohne Umwandlung nicht lesen kann (Opus, Vorbis in WebM/Matroska, …).
    public static func needsConversion(codec: String?, ext: String?) -> Bool {
        let c = (codec ?? "").lowercased()
        let e = (ext ?? "").lowercased()
        if ["webm", "weba", "mkv", "mka", "opus"].contains(e) { return true }
        if c.hasPrefix("opus") || (c.hasPrefix("vorbis") && e != "ogg" && e != "oga") { return true }
        return false
    }

    /// Dateiendungen, die AVFoundation (bzw. der eigene Ogg-Vorbis-Decoder) lesen kann.
    public static let readableExtensions: Set<String> = ["m4a", "mp4", "m4b", "aac", "mp3", "wav", "wave", "aif", "aiff", "aifc", "caf", "flac", "mov", "m4v", "ogg", "oga"]

    /// SoundCloud-Hörprobe (Go+): yt-dlp kennzeichnet solche Formate mit „preview“.
    public static func isPreviewFormat(formatID: String?, formatNote: String?, url: String?) -> Bool {
        [formatID, formatNote, url].contains { ($0 ?? "").lowercased().contains("preview") }
    }
}

/// Zusätzliche Felder der `yt-dlp -J`-Ausgabe, die `YtDlpInfo` nicht enthält.
struct YtDlpExtra: Decodable {
    var _type: String?
    var title: String?
    var ext: String?
    var format_id: String?
    var format_note: String?
    var url: String?
    var entries: [Entry]?
    var playlist_count: Int?

    struct Entry: Decodable {
        var id: String?
        var url: String?
        var webpage_url: String?
        var title: String?
        var duration: Double?
        var ie_key: String?
        var _type: String?
    }

    var isPlaylist: Bool { _type == "playlist" || _type == "multi_video" }

    /// Adressen der Einträge (höchstens `RemoteLookup.maxEntries`); nur http(s).
    func playlistEntries(kind: SourceKind) -> [RemotePlaylistEntry] {
        var out: [RemotePlaylistEntry] = []
        var seen = Set<String>()
        let youtubeID = try? NSRegularExpression(pattern: "^[A-Za-z0-9_-]{11}$")
        func isYouTubeID(_ s: String) -> Bool {
            youtubeID?.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
        }
        for e in entries ?? [] {
            var address = e.webpage_url ?? e.url
            let youtube = kind == .youtube || e.ie_key == "Youtube"
            if let a = address, !a.contains("://") {
                // Ältere yt-dlp-Versionen liefern bei YouTube nur die Kennung
                address = youtube && isYouTubeID(a) ? "https://www.youtube.com/watch?v=\(a)" : nil
            }
            if address == nil, youtube, let id = e.id, isYouTubeID(id) {
                address = "https://www.youtube.com/watch?v=\(id)"
            }
            guard let a = address, let url = URL(string: a), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
                  seen.insert(url.absoluteString).inserted else { continue }
            out.append(RemotePlaylistEntry(url: url, title: e.title, duration: e.duration))
            if out.count >= RemoteLookup.maxEntries { break }
        }
        return out
    }
}
