import Foundation

/// Alle bearbeitbaren Metadatenfelder. Die Reihenfolge entspricht der Reihenfolge im Bearbeitungsfenster.
public enum TagField: String, CaseIterable, Codable, Hashable, Sendable {
    case title
    case artists
    case album
    case albumArtists
    case composers
    case grouping
    case work
    case genres
    case year
    case trackNumber
    case trackTotal
    case discNumber
    case discTotal
    case compilation
    case rating
    case bpm
    case comment
    case lyrics
    case titleSort
    case artistSort
    case albumSort
    case albumArtistSort
    case composerSort
    case copyright
    case publisher
    case isrc
    case encodedBy

    public var label: String {
        switch self {
        case .title: return "Titel"
        case .artists: return "Interpret"
        case .album: return "Album"
        case .albumArtists: return "Albuminterpret"
        case .composers: return "Komponist"
        case .grouping: return "Gruppierung"
        case .work: return "Werk"
        case .genres: return "Genre"
        case .year: return "Jahr"
        case .trackNumber: return "Titelnummer"
        case .trackTotal: return "Titelanzahl"
        case .discNumber: return "Disc-Nummer"
        case .discTotal: return "Disc-Anzahl"
        case .compilation: return "Compilation"
        case .rating: return "Bewertung"
        case .bpm: return "BPM"
        case .comment: return "Kommentar"
        case .lyrics: return "Liedtext"
        case .titleSort: return "Sortiertitel"
        case .artistSort: return "Sortierinterpret"
        case .albumSort: return "Sortieralbum"
        case .albumArtistSort: return "Sortier-Albuminterpret"
        case .composerSort: return "Sortierkomponist"
        case .copyright: return "Copyright"
        case .publisher: return "Label"
        case .isrc: return "ISRC"
        case .encodedBy: return "Codiert von"
        }
    }

    /// Felder, die bei Mehrfachauswahl nicht sinnvoll gemeinsam gesetzt werden (Titel ist je Datei verschieden).
    public var isPerTrackOnly: Bool {
        switch self {
        case .title, .lyrics, .titleSort, .isrc: return true
        default: return false
        }
    }
}

/// Art eines eingebetteten Bildes (ID3v2-APIC-Typen; MP4 kennt nur „Cover“).
public enum PictureKind: Int, CaseIterable, Codable, Hashable, Sendable {
    case other = 0
    case fileIcon = 1
    case otherFileIcon = 2
    case frontCover = 3
    case backCover = 4
    case leafletPage = 5
    case media = 6
    case leadArtist = 7
    case artist = 8
    case conductor = 9
    case band = 10
    case composer = 11
    case lyricist = 12
    case recordingLocation = 13
    case duringRecording = 14
    case duringPerformance = 15
    case movieScreenCapture = 16
    case colouredFish = 17
    case illustration = 18
    case bandLogo = 19
    case publisherLogo = 20

    public var label: String {
        switch self {
        case .frontCover: return "Vorderseite"
        case .backCover: return "Rückseite"
        case .leafletPage: return "Booklet"
        case .media: return "Medium (CD/Platte)"
        case .leadArtist, .artist, .band: return "Interpret"
        case .illustration: return "Illustration"
        case .bandLogo: return "Logo"
        default: return "Weiteres Bild"
        }
    }

    /// Im Bearbeitungsfenster angebotene Arten.
    public static let editable: [PictureKind] = [.frontCover, .backCover, .leafletPage, .media, .artist, .illustration, .other]
}

/// Ein in die Datei eingebettetes Bild.
public struct EmbeddedPicture: Hashable, Sendable {
    public var kind: PictureKind
    /// „image/jpeg“ oder „image/png“ (andere Formate werden vor dem Einbetten umgewandelt).
    public var mimeType: String
    public var description: String
    public var data: Data

    public init(kind: PictureKind = .frontCover, mimeType: String, description: String = "", data: Data) {
        self.kind = kind
        self.mimeType = mimeType
        self.description = description
        self.data = data
    }
}

/// Inhalt der Tags einer Datei (Lesen und Schreiben).
public struct TagValues: Hashable, Sendable {
    public var title: String?
    public var artists: [String] = []
    public var album: String?
    public var albumArtists: [String] = []
    public var composers: [String] = []
    public var grouping: String?
    public var work: String?
    public var genres: [String] = []
    /// Jahr (aus TDRC/©day/DATE gelesen; beim Schreiben bleibt ein vollständiges Datum erhalten, wenn das Jahr gleich ist).
    public var year: Int?
    /// Vollständiges Datum wie in der Datei (z. B. „2024-05-17“), nur zur Information.
    public var date: String?
    public var trackNumber: Int?
    public var trackTotal: Int?
    public var discNumber: Int?
    public var discTotal: Int?
    public var compilation: Bool = false
    /// 0…100; `nil` = keine Bewertung.
    public var rating: Int?
    public var bpm: Int?
    public var comment: String?
    /// Liedtext (unsynchronisiert, ggf. im LRC-Format mit Zeitmarken).
    public var lyrics: String?
    public var titleSort: String?
    public var artistSort: String?
    public var albumSort: String?
    public var albumArtistSort: String?
    public var composerSort: String?
    public var copyright: String?
    public var publisher: String?
    public var isrc: String?
    public var encodedBy: String?
    public var pictures: [EmbeddedPicture] = []

    public init() {}

    /// Wert eines Feldes als Text (für Vergleich, Anzeige, Kopieren/Einfügen). Mehrfachwerte mit „; “ getrennt.
    public func text(for field: TagField) -> String {
        func n(_ v: Int?) -> String { v.map(String.init) ?? "" }
        switch field {
        case .title: return title ?? ""
        case .artists: return artists.joined(separator: "; ")
        case .album: return album ?? ""
        case .albumArtists: return albumArtists.joined(separator: "; ")
        case .composers: return composers.joined(separator: "; ")
        case .grouping: return grouping ?? ""
        case .work: return work ?? ""
        case .genres: return genres.joined(separator: "; ")
        case .year: return n(year)
        case .trackNumber: return n(trackNumber)
        case .trackTotal: return n(trackTotal)
        case .discNumber: return n(discNumber)
        case .discTotal: return n(discTotal)
        case .compilation: return compilation ? "1" : "0"
        case .rating: return n(rating)
        case .bpm: return n(bpm)
        case .comment: return comment ?? ""
        case .lyrics: return lyrics ?? ""
        case .titleSort: return titleSort ?? ""
        case .artistSort: return artistSort ?? ""
        case .albumSort: return albumSort ?? ""
        case .albumArtistSort: return albumArtistSort ?? ""
        case .composerSort: return composerSort ?? ""
        case .copyright: return copyright ?? ""
        case .publisher: return publisher ?? ""
        case .isrc: return isrc ?? ""
        case .encodedBy: return encodedBy ?? ""
        }
    }

    /// Feld aus Text setzen (Gegenstück zu `text(for:)`). Leerer Text löscht den Wert.
    public mutating func setText(_ raw: String, for field: TagField) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        func opt() -> String? { value.isEmpty ? nil : value }
        func list() -> [String] {
            value.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        func int() -> Int? { Int(value.filter { $0.isNumber }.prefix(9)) }
        switch field {
        case .title: title = opt()
        case .artists: artists = list()
        case .album: album = opt()
        case .albumArtists: albumArtists = list()
        case .composers: composers = list()
        case .grouping: grouping = opt()
        case .work: work = opt()
        case .genres: genres = list()
        case .year: year = int()
        case .trackNumber: trackNumber = int()
        case .trackTotal: trackTotal = int()
        case .discNumber: discNumber = int()
        case .discTotal: discTotal = int()
        case .compilation: compilation = (value == "1" || value.lowercased() == "true" || value.lowercased() == "ja")
        case .rating: rating = int().map { min(100, max(0, $0)) }
        case .bpm: bpm = int()
        // Kommentar und Liedtext behalten Zeilenumbrüche und Einrückungen.
        case .comment: comment = raw.isEmpty ? nil : raw
        case .lyrics: lyrics = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : raw
        case .titleSort: titleSort = opt()
        case .artistSort: artistSort = opt()
        case .albumSort: albumSort = opt()
        case .albumArtistSort: albumArtistSort = opt()
        case .composerSort: composerSort = opt()
        case .copyright: copyright = opt()
        case .publisher: publisher = opt()
        case .isrc: isrc = opt()
        case .encodedBy: encodedBy = opt()
        }
    }

    /// Übernimmt nur die angegebenen Felder aus `other`.
    public mutating func merge(_ other: TagValues, fields: Set<TagField>) {
        for field in fields {
            switch field {
            case .title: title = other.title
            case .artists: artists = other.artists
            case .album: album = other.album
            case .albumArtists: albumArtists = other.albumArtists
            case .composers: composers = other.composers
            case .grouping: grouping = other.grouping
            case .work: work = other.work
            case .genres: genres = other.genres
            case .year: year = other.year
            case .trackNumber: trackNumber = other.trackNumber
            case .trackTotal: trackTotal = other.trackTotal
            case .discNumber: discNumber = other.discNumber
            case .discTotal: discTotal = other.discTotal
            case .compilation: compilation = other.compilation
            case .rating: rating = other.rating
            case .bpm: bpm = other.bpm
            case .comment: comment = other.comment
            case .lyrics: lyrics = other.lyrics
            case .titleSort: titleSort = other.titleSort
            case .artistSort: artistSort = other.artistSort
            case .albumSort: albumSort = other.albumSort
            case .albumArtistSort: albumArtistSort = other.albumArtistSort
            case .composerSort: composerSort = other.composerSort
            case .copyright: copyright = other.copyright
            case .publisher: publisher = other.publisher
            case .isrc: isrc = other.isrc
            case .encodedBy: encodedBy = other.encodedBy
            }
        }
    }

    /// Erstes Bild der Art „Vorderseite“ (oder irgendein Bild).
    public var frontCover: EmbeddedPicture? {
        pictures.first { $0.kind == .frontCover } ?? pictures.first
    }
}

/// Technische Angaben zur Audiodatei.
public struct AudioProperties: Hashable, Sendable {
    public var durationMs: Int64 = 0
    /// kbit/s
    public var bitrate: Int = 0
    public var sampleRate: Int = 0
    public var channels: Int = 0
    public var bitsPerSample: Int = 0
    /// z. B. „MP3“, „AAC“, „ALAC“, „FLAC“, „Vorbis“, „Opus“, „PCM“.
    public var codec: String = ""

    public init(durationMs: Int64 = 0, bitrate: Int = 0, sampleRate: Int = 0, channels: Int = 0, bitsPerSample: Int = 0, codec: String = "") {
        self.durationMs = durationMs
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitsPerSample = bitsPerSample
        self.codec = codec
    }
}

/// Ergebnis des Einlesens einer Datei.
public struct TagReadResult: Hashable, Sendable {
    public var values: TagValues
    public var audio: AudioProperties
    /// Dateiformat, z. B. „MP3“, „MPEG-4 Audio“, „FLAC“, „Ogg Vorbis“, „WAV“, „AIFF“.
    public var fileFormat: String
    /// Verwendete Tag-Formate, z. B. „ID3v2.4, ID3v1“, „MP4“, „Vorbis Comment“.
    public var tagFormat: String
    /// Kann dieses Format Bilder speichern?
    public var supportsPictures: Bool
    /// Kann dieses Format überhaupt beschrieben werden?
    public var writable: Bool

    public init(values: TagValues, audio: AudioProperties, fileFormat: String, tagFormat: String, supportsPictures: Bool, writable: Bool) {
        self.values = values
        self.audio = audio
        self.fileFormat = fileFormat
        self.tagFormat = tagFormat
        self.supportsPictures = supportsPictures
        self.writable = writable
    }
}

/// Änderung an den Bildern einer Datei.
public enum PictureChange: Hashable, Sendable {
    /// Bilder unverändert lassen.
    case keep
    /// Alle Bilder durch diese Liste ersetzen (leer = alle entfernen).
    case replaceAll([EmbeddedPicture])
}

/// Eine Bearbeitung für eine oder mehrere Dateien: nur die gesetzten Felder werden geschrieben.
public struct TagEdit: Hashable, Sendable {
    /// Neue Werte (nur die Felder in `fields` werden verwendet).
    public var values: TagValues
    public var fields: Set<TagField>
    public var pictures: PictureChange

    public init(values: TagValues = TagValues(), fields: Set<TagField> = [], pictures: PictureChange = .keep) {
        self.values = values
        self.fields = fields
        self.pictures = pictures
    }

    public var isEmpty: Bool {
        if !fields.isEmpty { return false }
        if case .keep = pictures { return true }
        return false
    }

    /// Wendet die Bearbeitung auf vorhandene Tags an.
    public func applied(to original: TagValues) -> TagValues {
        var result = original
        result.merge(values, fields: fields)
        if case .replaceAll(let pics) = pictures { result.pictures = pics }
        return result
    }
}

/// Darstellung eines Feldes bei Mehrfachauswahl.
public enum MixedValue<Value: Hashable & Sendable>: Hashable, Sendable {
    /// Alle ausgewählten Titel haben denselben Wert.
    case same(Value)
    /// Die Werte unterscheiden sich („Gemischt“).
    case mixed

    public static func combine<S: Sequence>(_ values: S) -> MixedValue<Value>? where S.Element == Value {
        var first: Value?
        for value in values {
            if let f = first {
                if f != value { return .mixed }
            } else {
                first = value
            }
        }
        return first.map { .same($0) }
    }
}
