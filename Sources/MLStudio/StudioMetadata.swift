import Foundation
import MLCore

/// Metadaten, die beim Export in die Datei geschrieben werden.
public struct StudioMetadata: Codable, Hashable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var albumArtist: String
    public var year: Int?
    public var genre: String
    public var trackNumber: Int?
    /// Coverbild (JPEG oder PNG). Wird beim Export eingebettet, sofern das Format es kann.
    public var cover: Data?

    public init(title: String = "", artist: String = "", album: String = "", albumArtist: String = "", year: Int? = nil,
                genre: String = "", trackNumber: Int? = nil, cover: Data? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.year = year
        self.genre = genre
        self.trackNumber = trackNumber
        self.cover = cover
    }

    public var isEmpty: Bool {
        title.trimmed.isEmpty && artist.trimmed.isEmpty && album.trimmed.isEmpty && genre.trimmed.isEmpty && year == nil && trackNumber == nil && cover == nil
    }

    /// Bearbeitung für MLTags: nur nicht leere Felder werden geschrieben.
    public func tagEdit(coverMimeType: String?) -> TagEdit {
        var values = TagValues()
        var fields: Set<TagField> = []
        if !title.trimmed.isEmpty { values.title = title.trimmed; fields.insert(.title) }
        if !artist.trimmed.isEmpty { values.artists = [artist.trimmed]; fields.insert(.artists) }
        if !album.trimmed.isEmpty { values.album = album.trimmed; fields.insert(.album) }
        if !albumArtist.trimmed.isEmpty { values.albumArtists = [albumArtist.trimmed]; fields.insert(.albumArtists) }
        if let year, year > 0 { values.year = year; fields.insert(.year) }
        if !genre.trimmed.isEmpty { values.genres = [genre.trimmed]; fields.insert(.genres) }
        if let trackNumber, trackNumber > 0 { values.trackNumber = trackNumber; fields.insert(.trackNumber) }
        var pictures = PictureChange.keep
        if let cover, let mime = coverMimeType {
            pictures = .replaceAll([EmbeddedPicture(kind: .frontCover, mimeType: mime, data: cover)])
        }
        return TagEdit(values: values, fields: fields, pictures: pictures)
    }
}

/// Aufbau des Dateinamens.
public enum FileNameScheme: Codable, Hashable, Sendable {
    case artistTitle
    case titleArtist
    case title
    case custom(String)

    public static let presets: [FileNameScheme] = [.artistTitle, .titleArtist, .title]

    public var label: String {
        switch self {
        case .artistTitle: return "Interpret – Titel"
        case .titleArtist: return "Titel – Interpret"
        case .title: return "Titel"
        case .custom: return "Eigener Name"
        }
    }

    /// Dateiname ohne Endung, bereinigt. Fehlt der Interpret, wird nur der Titel verwendet.
    public func render(_ meta: StudioMetadata, fallback: String) -> String {
        let artist = meta.artist.trimmed
        let title = meta.title.trimmed
        let raw: String
        switch self {
        case .artistTitle:
            raw = artist.isEmpty ? title : (title.isEmpty ? artist : "\(artist) – \(title)")
        case .titleArtist:
            raw = artist.isEmpty ? title : (title.isEmpty ? artist : "\(title) – \(artist)")
        case .title:
            raw = title
        case .custom(let text):
            raw = text
        }
        let cleaned = FileNames.sanitize(raw)
        return cleaned.isEmpty ? (FileNames.sanitize(fallback).isEmpty ? "Audio" : FileNames.sanitize(fallback)) : cleaned
    }
}

/// Hilfen für sichere Dateinamen unter macOS.
public enum FileNames {
    /// Entfernt Zeichen, die in macOS-Dateinamen stören (/, :, Steuerzeichen), führende Punkte und
    /// überflüssige Leerzeichen; kürzt auf 180 Zeichen (Platz für Endung und „ (2)“).
    public static func sanitize(_ name: String) -> String {
        var s = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        s = String(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmed
        while s.hasPrefix(".") { s.removeFirst() }
        s = s.trimmed
        if s.count > 180 { s = String(s.prefix(180)).trimmed }
        return s
    }

    /// Freier Name in einem Ordner: „Name.mp3“, sonst „Name (2).mp3“, „Name (3).mp3“ …
    /// `exists` prüft, ob ein Pfad bereits belegt ist (für Tests austauschbar).
    public static func unique(base: String, ext: String, in directory: String, exists: (String) -> Bool) -> String {
        let dir = directory.hasSuffix("/") ? String(directory.dropLast()) : directory
        var candidate = "\(dir)/\(base).\(ext)"
        var n = 2
        while exists(candidate) {
            candidate = "\(dir)/\(base) (\(n)).\(ext)"
            n += 1
        }
        return candidate
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
