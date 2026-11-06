import Foundation

/// Ein Musikstück der Bibliothek (Anzeige- und Logikmodell).
///
/// Entspricht `model/Track.kt` der Android-App, ergänzt um die zusätzlichen Felder der
/// Metadatenbearbeitung (Komponist, Gruppierung, BPM, Bewertung, Kommentar …).
///
/// `uid` ist die app-eigene, dauerhafte Kennung. Daran hängen Favoriten, Playlists, Statistik,
/// Verlauf und Wiedergabeposition. Sie bleibt erhalten, wenn eine Datei verschoben oder ersetzt wird.
/// Alle Metadaten stammen aus den eingebetteten Tags. Fehlt ein Wert, ist er `nil` bzw. leer.
public struct Track: Identifiable, Hashable, Sendable {
    public var uid: Int64
    /// Bibliotheksordner (Musikordner), zu dem die Datei gehört.
    public var folderID: Int64
    /// Vollständiger Dateipfad (POSIX).
    public var path: String
    /// Ordner relativ zum Musikordner, z. B. „Queen/A Night at the Opera/“ (leer = direkt im Musikordner).
    public var relativePath: String
    public var fileName: String

    /// Titel-Tag (`nil` = kein Titel in der Datei; angezeigt wird dann der Dateiname).
    public var title: String?
    public var artists: [String]
    public var album: String?
    public var albumArtists: [String]
    public var genres: [String]
    public var composers: [String]
    public var grouping: String?
    public var year: Int?
    public var trackNumber: Int?
    public var trackTotal: Int?
    public var discNumber: Int?
    public var discTotal: Int?
    public var compilation: Bool
    public var bpm: Int?
    /// Bewertung 0…100 (20 je Stern, wie Apple Musik); `nil` = keine Bewertung.
    public var rating: Int?
    public var comment: String?

    public var durationMs: Int64
    public var sizeBytes: Int64
    /// Änderungsdatum der Datei in Sekunden seit 1970.
    public var dateModified: Int64
    /// Zeitpunkt der Aufnahme in die Bibliothek in Sekunden seit 1970.
    public var dateAdded: Int64
    /// Herkunft von `dateAdded` (v2.1): Apple Musik, Dateisystem oder erster Import.
    public var dateAddedSource: DateAddedSource = .unknown
    /// Codec für die Anzeige, z. B. „AAC“, „MP3“, „FLAC“, „ALAC“.
    public var codec: String?
    public var sampleRate: Int
    /// Bitrate in kbit/s (0 = unbekannt).
    public var bitrate: Int
    public var channels: Int
    public var bitsPerSample: Int

    public var titleSort: String?
    public var artistSort: String?
    public var albumSort: String?
    public var albumArtistSort: String?
    public var composerSort: String?

    /// Enthält die Datei ein eingebettetes Bild?
    public var hasPicture: Bool
    /// Enthält die Datei einen Liedtext (oder liegt eine .lrc-Datei daneben)?
    public var hasLyrics: Bool
    /// Datei derzeit erreichbar (z. B. externes Laufwerk angeschlossen)?
    public var available: Bool

    public var id: Int64 { uid }

    public init(
        uid: Int64,
        folderID: Int64 = 0,
        path: String,
        relativePath: String = "",
        fileName: String,
        title: String? = nil,
        artists: [String] = [],
        album: String? = nil,
        albumArtists: [String] = [],
        genres: [String] = [],
        composers: [String] = [],
        grouping: String? = nil,
        year: Int? = nil,
        trackNumber: Int? = nil,
        trackTotal: Int? = nil,
        discNumber: Int? = nil,
        discTotal: Int? = nil,
        compilation: Bool = false,
        bpm: Int? = nil,
        rating: Int? = nil,
        comment: String? = nil,
        durationMs: Int64 = 0,
        sizeBytes: Int64 = 0,
        dateModified: Int64 = 0,
        dateAdded: Int64 = 0,
        codec: String? = nil,
        sampleRate: Int = 0,
        bitrate: Int = 0,
        channels: Int = 0,
        bitsPerSample: Int = 0,
        titleSort: String? = nil,
        artistSort: String? = nil,
        albumSort: String? = nil,
        albumArtistSort: String? = nil,
        composerSort: String? = nil,
        hasPicture: Bool = false,
        hasLyrics: Bool = false,
        available: Bool = true
    ) {
        self.uid = uid
        self.folderID = folderID
        self.path = path
        self.relativePath = relativePath
        self.fileName = fileName
        self.title = title
        self.artists = artists
        self.album = album
        self.albumArtists = albumArtists
        self.genres = genres
        self.composers = composers
        self.grouping = grouping
        self.year = year
        self.trackNumber = trackNumber
        self.trackTotal = trackTotal
        self.discNumber = discNumber
        self.discTotal = discTotal
        self.compilation = compilation
        self.bpm = bpm
        self.rating = rating
        self.comment = comment
        self.durationMs = durationMs
        self.sizeBytes = sizeBytes
        self.dateModified = dateModified
        self.dateAdded = dateAdded
        self.codec = codec
        self.sampleRate = sampleRate
        self.bitrate = bitrate
        self.channels = channels
        self.bitsPerSample = bitsPerSample
        self.titleSort = titleSort
        self.artistSort = artistSort
        self.albumSort = albumSort
        self.albumArtistSort = albumArtistSort
        self.composerSort = composerSort
        self.hasPicture = hasPicture
        self.hasLyrics = hasLyrics
        self.available = available
    }

    /// Angezeigter Titel: Titel-Tag oder Dateiname ohne Endung.
    public var displayTitle: String { title ?? Track.fileNameWithoutExtension(fileName) }
    public var titleFromFileName: Bool { title == nil }
    /// Interpreten zur Anzeige, z. B. „Queen, David Bowie“ (`nil` = unbekannt).
    public var artistText: String? { artists.isEmpty ? nil : artists.joined(separator: ", ") }
    public var albumArtistText: String? { albumArtists.isEmpty ? nil : albumArtists.joined(separator: ", ") }
    public var genreText: String? { genres.isEmpty ? nil : genres.joined(separator: ", ") }
    public var composerText: String? { composers.isEmpty ? nil : composers.joined(separator: ", ") }
    /// Ordnerschlüssel (Musikordner + relativer Pfad).
    public var folderKey: String { "\(folderID)/\(relativePath)" }
    /// Schlüssel für die Cover-Zwischenspeicherung: ändert sich, sobald die Datei geändert wird.
    public var coverKey: String { "\(uid)-\(dateModified)-\(sizeBytes)" }
    /// Dateiendung in Kleinbuchstaben („mp3“, „m4a“ …).
    public var fileExtension: String {
        guard let dot = fileName.lastIndex(of: "."), dot != fileName.startIndex else { return "" }
        return String(fileName[fileName.index(after: dot)...]).lowercased()
    }

    public static func fileNameWithoutExtension(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        return String(name[..<dot])
    }
}

/// Speicherformat für Mehrfachwerte in einer Datenbankspalte (wie Android `ListCodec`):
/// Werte durch das Steuerzeichen U+001F getrennt.
public enum ListCodec {
    static let separator: Character = "\u{1F}"
    static let pairSeparator: Character = "\u{1E}"

    public static func encode(_ values: [String]) -> String? {
        let cleaned = values
            .map { $0.replacingOccurrences(of: String(separator), with: " ").replacingOccurrences(of: String(pairSeparator), with: " ") }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return cleaned.isEmpty ? nil : cleaned.joined(separator: String(separator))
    }

    public static func decode(_ text: String?) -> [String] {
        guard let text, !text.isEmpty else { return [] }
        return text.split(separator: separator, omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
