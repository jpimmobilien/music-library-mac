import Foundation

/// Herkunft einer Quelle.
public enum SourceKind: String, Codable, Hashable, Sendable {
    case localFile
    case youtube
    case soundcloud
    case spotify
    case web

    public var label: String {
        switch self {
        case .localFile: return "Datei"
        case .youtube: return "YouTube"
        case .soundcloud: return "SoundCloud"
        case .spotify: return "Spotify"
        case .web: return "Web"
        }
    }

    /// Audio kann aus dieser Quelle geladen werden. Spotify-Audio ist kopiergeschützt (DRM) – nur Metadaten.
    public var supportsAudio: Bool { self != .spotify }
}

/// Erkennt unterstützte Adressen. Nur http(s); keine Dateisystem- oder Sonderschemata.
public enum SourceURL {
    public static func classify(_ text: String) -> (kind: SourceKind, url: URL)? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if !t.contains("://") { t = "https://" + t }
        guard let url = URL(string: t), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased(), host.contains(".") else { return nil }
        let h = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if h == "youtube.com" || h.hasSuffix(".youtube.com") || h == "youtu.be" || h == "youtube-nocookie.com" { return (.youtube, url) }
        if h == "soundcloud.com" || h.hasSuffix(".soundcloud.com") || h == "snd.sc" || h == "on.soundcloud.com" { return (.soundcloud, url) }
        if h == "open.spotify.com" || h == "spotify.com" || h == "spotify.link" { return (.spotify, url) }
        return (.web, url)
    }

    /// Instagram-Adresse (Reels, Videos, Beiträge). Geführt als Web-Quelle – derselbe gespeicherte Typ wie bisher,
    /// damit ältere Versionen Verlauf und Einstellungen weiter lesen –, aber in der Oberfläche eigens benannt.
    public static func isInstagram(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let h = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return h == "instagram.com" || h.hasSuffix(".instagram.com") || h == "instagr.am"
    }

    /// Anzeigename der Herkunft („Instagram“ statt „Web“).
    public static func label(kind: SourceKind, url: URL?) -> String {
        if kind == .web, let url, isInstagram(url) { return "Instagram" }
        return kind.label
    }
}

/// Ergebnis der Analyse einer Quelle (Datei oder Adresse).
public struct SourceInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: SourceKind
    /// Ursprüngliche Adresse (bei Dateien: file-URL).
    public var url: URL
    public var title: String
    /// Kanal/Hochlader bzw. Interpret aus den Metadaten.
    public var uploader: String?
    public var duration: Double?
    public var thumbnailURL: URL?
    /// Bereits geladenes Vorschaubild (JPEG/PNG).
    public var thumbnail: Data?
    /// Vorschlag für die Tags (aus Datei-Tags, yt-dlp-Feldern „track“, „artist“, „album“, „release_year“ …).
    public var suggested: StudioMetadata
    /// Angaben zum Audio der Quelle, soweit bekannt.
    public var codec: String?
    public var bitrateKbps: Int?
    public var sampleRate: Int?
    public var bitDepth: Int?
    public var channels: Int?
    public var isLossless: Bool?
    public var fileSize: Int64?
    /// Live-Übertragung (nicht unterstützt).
    public var isLive: Bool
    /// Lokale Audiodatei (bei Dateien sofort, bei Adressen nach dem Laden).
    public var localFile: URL?
    /// Titel aus der eigenen Bibliothek (Schneiden vorhandener Songs): Kennung des Titels.
    public var libraryUid: Int64?

    public init(id: String, kind: SourceKind, url: URL, title: String, uploader: String? = nil, duration: Double? = nil,
                thumbnailURL: URL? = nil, thumbnail: Data? = nil, suggested: StudioMetadata = StudioMetadata(), codec: String? = nil,
                bitrateKbps: Int? = nil, sampleRate: Int? = nil, bitDepth: Int? = nil, channels: Int? = nil, isLossless: Bool? = nil,
                fileSize: Int64? = nil, isLive: Bool = false, localFile: URL? = nil, libraryUid: Int64? = nil) {
        self.id = id
        self.kind = kind
        self.url = url
        self.title = title
        self.uploader = uploader
        self.duration = duration
        self.thumbnailURL = thumbnailURL
        self.thumbnail = thumbnail
        self.suggested = suggested
        self.codec = codec
        self.bitrateKbps = bitrateKbps
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channels = channels
        self.isLossless = isLossless
        self.fileSize = fileSize
        self.isLive = isLive
        self.localFile = localFile
        self.libraryUid = libraryUid
    }

    /// Format der Quelle als Zielformat (für „Format wie Original“ beim Schneiden), falls exportierbar.
    public var sameFormat: StudioFormat? {
        let ext = (localFile ?? url).pathExtension.lowercased()
        switch ext {
        case "mp3": return .mp3
        case "wav", "wave": return .wav
        case "flac": return .flac
        case "aac": return .aac
        case "m4a", "mp4", "m4b": return codec?.lowercased().contains("alac") == true ? nil : .m4a
        case "aif", "aiff", "aifc": return .aiff
        default: return nil
        }
    }
}

/// Verständliche Fehler beim Analysieren, Laden und Exportieren.
public enum StudioError: Error, Hashable, Sendable, LocalizedError {
    case unsupportedURL
    case spotifyDRM
    case toolMissing(String)
    case loginRequired
    case privateContent
    case ageRestricted
    case geoBlocked
    case liveStream
    case previewOnly
    case unavailable(String)
    case network(String)
    case unsupportedFile(String)
    case decodeFailed(String)
    case encodeFailed(String)
    case diskFull
    case cancelled
    case other(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedURL: return "Diese Adresse wird nicht unterstützt."
        case .spotifyDRM: return "Spotify-Audio ist kopiergeschützt (DRM) und kann nicht exportiert werden. Titel, Interpret und Cover lassen sich übernehmen."
        case .toolMissing(let name): return "Für Internet-Quellen wird „\(name)“ benötigt. Du kannst es in den Audio-Studio-Werkzeugen installieren."
        case .loginRequired: return "Diese Quelle erfordert eine Anmeldung. Inhalte hinter einer Anmeldung werden nicht geladen."
        case .privateContent: return "Dieser Inhalt ist privat."
        case .ageRestricted: return "Dieser Inhalt ist altersbeschränkt und erfordert eine Anmeldung – er wird nicht geladen."
        case .geoBlocked: return "Dieser Inhalt ist in deinem Land nicht verfügbar."
        case .liveStream: return "Live-Übertragungen werden nicht unterstützt."
        case .previewOnly: return "Von dieser Quelle ist nur eine kurze Hörprobe frei verfügbar."
        case .unavailable(let detail): return detail.isEmpty ? "Der Inhalt ist nicht verfügbar." : "Der Inhalt ist nicht verfügbar: \(detail)"
        case .network(let detail): return detail.isEmpty ? "Keine Verbindung zum Server." : "Netzwerkfehler: \(detail)"
        case .unsupportedFile(let ext): return ext.isEmpty ? "Dieses Dateiformat wird nicht unterstützt." : "Das Format „\(ext)“ wird nicht unterstützt."
        case .decodeFailed(let detail): return "Die Datei konnte nicht gelesen werden. \(detail)"
        case .encodeFailed(let detail): return "Der Export ist fehlgeschlagen. \(detail)"
        case .diskFull: return "Nicht genug freier Speicherplatz."
        case .cancelled: return "Abgebrochen."
        case .other(let text): return text
        }
    }
}

/// Zuordnung der JSON-Ausgabe von `yt-dlp -J` (nur die benötigten Felder).
public struct YtDlpInfo: Decodable, Sendable {
    public var id: String?
    public var title: String?
    public var fulltitle: String?
    /// Beschreibung bzw. Beitragstext (Instagram: Bildunterschrift).
    public var description: String?
    public var uploader: String?
    public var channel: String?
    public var creator: String?
    public var artist: String?
    public var artists: [String]?
    public var track: String?
    public var album: String?
    public var genre: String?
    public var genres: [String]?
    public var release_year: Int?
    public var upload_date: String?
    public var track_number: Int?
    public var duration: Double?
    public var thumbnail: String?
    public var webpage_url: String?
    public var extractor_key: String?
    public var is_live: Bool?
    public var live_status: String?
    public var availability: String?
    public var abr: Double?
    public var acodec: String?
    public var asr: Int?
    public var audio_channels: Int?
    public var filesize: Int64?
    public var filesize_approx: Int64?
    /// Playlist/Set: Einträge (nur Kennzeichnung, Inhalte werden einzeln analysiert).
    public var _type: String?
    public var entries: [YtDlpEntry]?

    public struct YtDlpEntry: Decodable, Sendable {
        public var id: String?
        public var url: String?
        public var title: String?
        public var duration: Double?
    }

    /// In `SourceInfo` umwandeln. Titel im Format „Interpret - Titel“ werden aufgeteilt, wenn keine
    /// eigenen Musikfelder vorhanden sind.
    public func sourceInfo(kind: SourceKind, requestedURL: URL) -> SourceInfo {
        var shownTitle = (title ?? fulltitle ?? track ?? "Ohne Titel").trimmingCharacters(in: .whitespacesAndNewlines)
        var meta = StudioMetadata()
        let artistField = artists?.first ?? artist ?? creator
        // Instagram & Co.: Titel ist nur „Video by konto“ – die erste Zeile des Beitragstexts sagt mehr.
        var fromCaption = false
        if (track ?? "").isEmpty, Self.isGenericPostTitle(shownTitle), let caption = description.flatMap(Self.captionTitle) {
            shownTitle = caption
            fromCaption = true
        }
        if fromCaption {
            meta.title = shownTitle
            meta.artist = artistField ?? Self.cleanChannel(uploader ?? channel ?? "")
        } else if let track, !track.isEmpty {
            meta.title = track
            meta.artist = artistField ?? uploader ?? channel ?? ""
        } else if let split = Self.splitArtistTitle(shownTitle) {
            meta.artist = artistField ?? split.artist
            meta.title = split.title
        } else {
            meta.title = shownTitle
            meta.artist = artistField ?? Self.cleanChannel(uploader ?? channel ?? "")
        }
        meta.album = album ?? ""
        meta.genre = genres?.first ?? genre ?? ""
        meta.year = release_year ?? upload_date.flatMap { Int($0.prefix(4)) }
        meta.trackNumber = track_number
        let page = webpage_url.flatMap(URL.init(string:)) ?? requestedURL
        return SourceInfo(id: id ?? page.absoluteString, kind: kind, url: page, title: shownTitle, uploader: uploader ?? channel,
                          duration: duration, thumbnailURL: thumbnail.flatMap(URL.init(string:)), suggested: meta,
                          codec: acodec, bitrateKbps: abr.map { Int($0.rounded()) }, sampleRate: asr, channels: audio_channels,
                          isLossless: false, fileSize: filesize ?? filesize_approx,
                          isLive: is_live == true || live_status == "is_live" || live_status == "is_upcoming")
    }

    /// „Interpret - Titel (Official Video)“ → („Interpret“, „Titel“). Zusätze wie „(Official Video)“,
    /// „[Lyrics]“, „(HD)“ werden entfernt; „(… Remix)“ bleibt erhalten.
    public static func splitArtistTitle(_ text: String) -> (artist: String, title: String)? {
        let separators = [" - ", " – ", " — ", " | "]
        for sep in separators {
            if let range = text.range(of: sep) {
                let artist = text[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let title = cleanTitle(String(text[range.upperBound...]))
                if !artist.isEmpty, !title.isEmpty { return (artist, title) }
            }
        }
        return nil
    }

    public static func cleanTitle(_ text: String) -> String {
        let noise = ["official video", "official music video", "official audio", "official lyric video", "lyric video", "lyrics",
                     "audio", "video", "hd", "hq", "4k", "visualizer", "official visualizer", "music video", "clip officiel", "videoclip"]
        var t = text
        let pattern = "\\s*[\\(\\[]([^\\)\\]]*)[\\)\\]]"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = t as NSString
            var result = ""
            var last = 0
            for m in regex.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
                let inner = ns.substring(with: m.range(at: 1)).lowercased().trimmingCharacters(in: .whitespaces)
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                if !noise.contains(inner) { result += ns.substring(with: m.range) }
                last = m.range.location + m.range.length
            }
            result += ns.substring(from: last)
            t = result
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// „Video by nasa“, „Post by …“, „Reel by …“: Ersatztitel von yt-dlp ohne eigenen Inhalt.
    public static func isGenericPostTitle(_ text: String) -> Bool {
        let parts = text.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3, parts[1].lowercased() == "by" else { return false }
        return ["video", "post", "reel", "clip", "photo"].contains(parts[0].lowercased())
    }

    /// Erste aussagekräftige Zeile eines Beitragstexts als Titel: ohne Links, ohne Hashtags und Erwähnungen am Ende,
    /// höchstens 80 Zeichen (an einer Wortgrenze gekürzt). nil, wenn nichts übrig bleibt.
    public static func captionTitle(_ caption: String) -> String? {
        for rawLine in caption.split(whereSeparator: \.isNewline) {
            var words = rawLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                .filter { !$0.lowercased().hasPrefix("http://") && !$0.lowercased().hasPrefix("https://") }
            while let last = words.last, last.hasPrefix("#") || last.hasPrefix("@") { words.removeLast() }
            var line = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard line.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
            if line.count > 80 {
                let cut = line.prefix(80)
                let end = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
                line = end.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:–-")) + " …"
            }
            return line
        }
        return nil
    }

    /// „Künstler - Topic“ / „KünstlerVEVO“ → „Künstler“.
    public static func cleanChannel(_ name: String) -> String {
        var n = name.trimmingCharacters(in: .whitespaces)
        if n.hasSuffix(" - Topic") { n = String(n.dropLast(8)) }
        if n.hasSuffix("VEVO"), n.count > 4 { n = String(n.dropLast(4)) }
        return n.trimmingCharacters(in: .whitespaces)
    }
}

/// Öffentliche oEmbed-Antwort von Spotify (ohne Anmeldung): Titel und Vorschaubild.
public struct SpotifyOEmbed: Decodable, Sendable {
    public var title: String?
    public var thumbnail_url: String?
    public var provider_name: String?

    public static func endpoint(for url: URL) -> URL? {
        var comps = URLComponents(string: "https://open.spotify.com/oembed")
        comps?.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        return comps?.url
    }

    public func sourceInfo(requestedURL: URL) -> SourceInfo {
        let t = title ?? "Spotify"
        return SourceInfo(id: requestedURL.absoluteString, kind: .spotify, url: requestedURL, title: t,
                          thumbnailURL: thumbnail_url.flatMap(URL.init(string:)), suggested: StudioMetadata(title: t))
    }
}
