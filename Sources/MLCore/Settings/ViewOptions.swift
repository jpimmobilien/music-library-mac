import Foundation

/// Darstellung einer Bibliotheksansicht.
public enum LibraryViewMode: String, CaseIterable, Codable, Hashable, Sendable {
    case grid = "GRID"
    case compactGrid = "COMPACT_GRID"
    case list = "LIST"
    case detailedList = "DETAILED_LIST"
    case coverFlow = "COVER_FLOW"

    public var label: String {
        switch self {
        case .grid: return "Raster"
        case .compactGrid: return "Kompaktes Raster"
        case .list: return "Liste"
        case .detailedList: return "Detailliste"
        case .coverFlow: return "Cover Flow"
        }
    }
}

/// Bereich, für den eine Ansicht gespeichert wird (Favoriten getrennt nach Titeln und Alben).
public enum LibraryViewContext: String, CaseIterable, Codable, Hashable, Sendable {
    case tracks = "TRACKS"
    case albums = "ALBUMS"
    case playlists = "PLAYLISTS"
    case artists = "ARTISTS"
    case genres = "GENRES"
    case favoriteTracks = "FAVORITE_TRACKS"
    case favoriteAlbums = "FAVORITE_ALBUMS"

    public var label: String {
        switch self {
        case .tracks: return "Titel"
        case .albums: return "Alben"
        case .playlists: return "Playlists"
        case .artists: return "Interpreten"
        case .genres: return "Genres"
        case .favoriteTracks: return "Favoriten – Titel"
        case .favoriteAlbums: return "Favoriten – Alben"
        }
    }

    /// Zeigt der Bereich Titel (sonst Gruppen: Alben, Playlists, Interpreten, Genres)?
    public var showsTracks: Bool { self == .tracks || self == .favoriteTracks }
}

/// Spalte der Detailliste.
public enum DetailColumn: String, CaseIterable, Codable, Hashable, Sendable {
    case trackNumber = "TRACK_NUMBER"
    case title = "TITLE"
    case artist = "ARTIST"
    case album = "ALBUM"
    case albumArtist = "ALBUM_ARTIST"
    case genre = "GENRE"
    case year = "YEAR"
    case duration = "DURATION"
    case plays = "PLAYS"
    case lastPlayed = "LAST_PLAYED"
    case dateAdded = "DATE_ADDED"
    case rating = "RATING"
    case bpm = "BPM"
    case format = "FORMAT"
    case bitrate = "BITRATE"
    case trackCount = "TRACK_COUNT"
    case albumCount = "ALBUM_COUNT"

    public var label: String {
        switch self {
        case .trackNumber: return "Nr."
        case .title: return "Titel"
        case .artist: return "Interpret"
        case .album: return "Album"
        case .albumArtist: return "Albuminterpret"
        case .genre: return "Genre"
        case .year: return "Jahr"
        case .duration: return "Dauer"
        case .plays: return "Wiedergaben"
        case .lastPlayed: return "Zuletzt gespielt"
        case .dateAdded: return "Hinzugefügt"
        case .rating: return "Bewertung"
        case .bpm: return "BPM"
        case .format: return "Format"
        case .bitrate: return "Bitrate"
        case .trackCount: return "Titelanzahl"
        case .albumCount: return "Albenanzahl"
        }
    }

    /// Überschrift im jeweiligen Bereich: in Playlists, Interpreten und Genres heißt die Namensspalte
    /// „Name“, in Playlists die Spalte „Hinzugefügt“ „Erstellt“; sonst wie `label`.
    public func label(for context: LibraryViewContext) -> String {
        switch (self, context) {
        case (.title, .playlists), (.title, .artists), (.title, .genres): return "Name"
        case (.dateAdded, .playlists): return "Erstellt"
        default: return label
        }
    }

    /// Übliche Breite in Punkten.
    public var defaultWidth: Double {
        switch self {
        case .trackNumber: return 44
        case .title: return 240
        case .artist, .albumArtist: return 180
        case .album: return 200
        case .genre: return 120
        case .year, .bpm: return 60
        case .duration: return 70
        case .plays, .rating, .bitrate, .trackCount, .albumCount: return 90
        case .lastPlayed, .dateAdded: return 140
        case .format: return 80
        }
    }

    /// Zahlenspalte (rechtsbündig).
    public var numeric: Bool {
        switch self {
        case .trackNumber, .year, .duration, .plays, .bpm, .bitrate, .trackCount, .albumCount: return true
        default: return false
        }
    }
}

/// Gespeicherte Ansicht eines Bereichs.
///
/// Lesen ist tolerant: unbekannte Darstellung → Standard des Bereichs, Größen werden in den gültigen
/// Bereich gebracht, unbekannte oder doppelte Spalten entfallen (keine Spalte übrig → Standardspalten).
public struct LibraryViewOptions: Hashable, Codable, Sendable {
    public var mode: LibraryViewMode
    /// Kachelbreite in Punkten, in `coverSizeRange`.
    public var coverSize: Double
    /// Abstand zwischen Kacheln, in `spacingRange`.
    public var spacing: Double
    /// Interpret/Untertitel unter Kacheln.
    public var showSecondaryText: Bool
    /// Zusätzliche Zeile (Jahr, Anzahl, Dauer).
    public var showDetails: Bool
    /// Sichtbare Spalten der Detailliste, in Reihenfolge.
    public var columns: [DetailColumn]

    public static let coverSizeRange: ClosedRange<Double> = 90...320
    public static let spacingRange: ClosedRange<Double> = 6...40

    /// Werte werden begrenzt (Größen) bzw. bereinigt (doppelte Spalten entfallen).
    public init(
        mode: LibraryViewMode = .grid, coverSize: Double = 180, spacing: Double = 18, showSecondaryText: Bool = true,
        showDetails: Bool = false, columns: [DetailColumn] = [.title, .artist, .album, .duration]
    ) {
        self.mode = mode
        self.coverSize = Self.clamp(coverSize, Self.coverSizeRange, fallback: 180)
        self.spacing = Self.clamp(spacing, Self.spacingRange, fallback: 18)
        self.showSecondaryText = showSecondaryText
        self.showDetails = showDetails
        self.columns = columns.distinctInOrder()
    }

    public static func defaults(for context: LibraryViewContext) -> LibraryViewOptions {
        switch context {
        case .tracks:
            return LibraryViewOptions(mode: .list, coverSize: 160, columns: [.title, .artist, .album, .genre, .year, .duration])
        case .favoriteTracks:
            return LibraryViewOptions(mode: .list, coverSize: 160, columns: [.title, .artist, .album, .duration])
        case .albums, .favoriteAlbums:
            return LibraryViewOptions(mode: .grid, coverSize: 180, columns: [.album, .albumArtist, .year, .genre, .trackCount, .duration])
        case .playlists:
            return LibraryViewOptions(mode: .list, coverSize: 160, columns: [.title, .trackCount, .duration])
        case .artists:
            return LibraryViewOptions(mode: .list, coverSize: 160, columns: [.title, .albumCount, .trackCount])
        case .genres:
            return LibraryViewOptions(mode: .grid, coverSize: 160, columns: [.title, .trackCount, .albumCount])
        }
    }

    /// Für den Kontext sinnvolle Spalten (z. B. Alben: Album, Albuminterpret, Jahr, Genre, Titel-Anzahl, Dauer, Hinzugefügt).
    public static func availableColumns(for context: LibraryViewContext) -> [DetailColumn] {
        switch context {
        case .tracks, .favoriteTracks:
            return [.trackNumber, .title, .artist, .album, .albumArtist, .genre, .year, .duration, .plays, .lastPlayed,
                    .dateAdded, .rating, .bpm, .format, .bitrate]
        case .albums, .favoriteAlbums:
            return [.album, .albumArtist, .year, .genre, .trackCount, .duration, .dateAdded, .plays, .lastPlayed]
        case .playlists:
            return [.title, .trackCount, .duration, .dateAdded]
        case .artists:
            return [.title, .albumCount, .trackCount, .plays]
        case .genres:
            return [.title, .trackCount, .albumCount]
        }
    }

    /// Für den Bereich gültige Fassung: Größen begrenzt, Spalten ohne Doppelte und nur die für den Bereich
    /// verfügbaren; bleibt keine übrig, gelten die Standardspalten.
    public func normalized(for context: LibraryViewContext) -> LibraryViewOptions {
        let available = Set(Self.availableColumns(for: context))
        let cols = columns.distinctInOrder().filter(available.contains)
        var copy = LibraryViewOptions(
            mode: mode, coverSize: coverSize, spacing: spacing, showSecondaryText: showSecondaryText,
            showDetails: showDetails, columns: cols
        )
        if copy.columns.isEmpty { copy.columns = Self.defaults(for: context).columns }
        return copy
    }

    static func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey { case mode, coverSize, spacing, showSecondaryText, showDetails, columns }

    /// Ohne Bereich gelesen: fehlende Werte wie in der Titelansicht (in `AppSettings` gilt der Standard
    /// des jeweiligen Bereichs).
    public init(from decoder: Decoder) throws {
        self = StoredViewOptions(from: decoder).resolved(defaults: Self.defaults(for: .tracks))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        try c.encode(coverSize, forKey: .coverSize)
        try c.encode(spacing, forKey: .spacing)
        try c.encode(showSecondaryText, forKey: .showSecondaryText)
        try c.encode(showDetails, forKey: .showDetails)
        try c.encode(columns, forKey: .columns)
    }

    /// Gespeicherte Ansicht mit einzeln lesbaren Werten (wirft nie); fehlende/ungültige Werte sind `nil`.
    struct StoredViewOptions: Decodable {
        var mode: LibraryViewMode?
        var coverSize: Double?
        var spacing: Double?
        var showSecondaryText: Bool?
        var showDetails: Bool?
        var columns: [DetailColumn]?

        init(from decoder: Decoder) {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            func value<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
                (try? c.decodeIfPresent(type, forKey: key)) ?? nil
            }
            mode = value(String.self, .mode).flatMap(LibraryViewMode.init(rawValue:))
            coverSize = value(Double.self, .coverSize)
            spacing = value(Double.self, .spacing)
            showSecondaryText = value(Bool.self, .showSecondaryText)
            showDetails = value(Bool.self, .showDetails)
            columns = value([LenientElement<String>].self, .columns)?.compactMap { $0.value.flatMap(DetailColumn.init(rawValue:)) }
        }

        func resolved(defaults d: LibraryViewOptions) -> LibraryViewOptions {
            var options = LibraryViewOptions(
                mode: mode ?? d.mode,
                coverSize: coverSize.map { LibraryViewOptions.clamp($0, LibraryViewOptions.coverSizeRange, fallback: d.coverSize) } ?? d.coverSize,
                spacing: spacing.map { LibraryViewOptions.clamp($0, LibraryViewOptions.spacingRange, fallback: d.spacing) } ?? d.spacing,
                showSecondaryText: showSecondaryText ?? d.showSecondaryText,
                showDetails: showDetails ?? d.showDetails,
                columns: columns ?? d.columns
            )
            if options.columns.isEmpty { options.columns = d.columns }
            return options
        }
    }
}
