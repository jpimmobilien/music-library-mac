# v2 – Schnittstellen in MLCore (verbindlich für App-Code)

Diese Namen und Signaturen werden in MLCore umgesetzt (rein, unter Linux testbar). App-Code darf sich darauf
verlassen. Bestehende Schnittstellen bleiben unverändert, nur Ergänzungen. Alle neuen Einstellungen werden
tolerant gelesen (unbekannt/ungültig → Standardwert bzw. in den gültigen Bereich gebracht).

## 1. Sortierung (`Library/Sorting.swift`)

Neue Fälle **hinten angefügt** (gespeicherte Namen bleiben gültig):

```swift
TrackSort:    + .album = "ALBUM", .albumArtist = "ALBUM_ARTIST", .dateAdded = "DATE_ADDED", .rating = "RATING", .bpm = "BPM"
AlbumSort:    + .dateAdded = "DATE_ADDED", .trackCount = "TRACK_COUNT"
ArtistSort:   + .albumCount = "ALBUM_COUNT"
PlaylistSort: + .created = "CREATED", .modified = "MODIFIED"
FavoriteTrackSort: + .dateAdded = "DATE_ADDED", .rating = "RATING"
```

```swift
// AlbumInfo bekommt (in AlbumGrouping berechnet):
public var dateAdded: Int64   // jüngstes dateAdded (Sekunden) seiner Titel

// Sorting.playlists bekommt zusätzliche Parameter mit Standardwerten:
public static func playlists<T>(_ items: [T], sort: Sort<PlaylistSort>, name: (T) -> String, count: (T) -> Int,
                                created: (T) -> Int64 = { _ in 0 }, modified: (T) -> Int64 = { _ in 0 }) -> [T]
```
`ArtistInfo.albumCount` (= `albumKeys.count`) als berechnete Eigenschaft.

## 2. Filter (`Library/LibraryFilter.swift`)

```swift
public enum QuickFilter: String, CaseIterable, Codable, Hashable, Sendable {
    case favorites = "FAVORITES", neverPlayed = "NEVER_PLAYED", recentlyAdded = "RECENTLY_ADDED",
         lossless = "LOSSLESS", withLyrics = "WITH_LYRICS", withoutCover = "WITHOUT_COVER", highRating = "HIGH_RATING"
    public var label: String        // „Favoriten“, „Nie gespielt“, „Neu (30 Tage)“, „Verlustfrei“, „Mit Liedtext“, „Ohne Cover“, „★ 4+“
}

public struct LibraryFilter: Hashable, Codable, Sendable {
    public var genres: Set<String>      // FacetValue.id der Genres
    public var decades: Set<Int>        // 1970, 1980, …
    public var artists: Set<String>     // FacetValue.id der Interpreten
    public var formats: Set<String>     // FacetValue.id der Formate („MP3“, „AAC“, „ALAC“, „FLAC“, „WAV“, „AIFF“, „Ogg Vorbis“, „Opus“, …)
    public var quick: Set<QuickFilter>
    public init()
    public var isEmpty: Bool
    public var activeCount: Int         // Anzahl gesetzter Bedingungen (für Abzeichen)
}

public struct FilterContext: Sendable {
    public var favorites: Set<Int64>
    public var stats: [Int64: PlayStats]
    public var nowSeconds: Int64
    public init(favorites: Set<Int64>, stats: [Int64: PlayStats], nowSeconds: Int64)
}

public struct FacetValue: Hashable, Sendable, Identifiable {
    public var id: String; public var label: String; public var count: Int
}
public struct FilterFacets: Hashable, Sendable {
    public var genres: [FacetValue]     // nach Anzahl absteigend
    public var decades: [FacetValue]    // id = "1980", label = „1980er“, aufsteigend
    public var artists: [FacetValue]    // nach Anzahl absteigend, höchstens 200
    public var formats: [FacetValue]
    public static let empty: FilterFacets
}

public enum AudioFormatFamily {
    public static func of(_ track: Track) -> String      // Familie aus Codec bzw. Dateiendung
    public static func isLossless(_ track: Track) -> Bool
}

public enum LibraryFiltering {
    public static func facets(_ tracks: [Track]) -> FilterFacets
    public static func matches(_ track: Track, _ filter: LibraryFilter, _ ctx: FilterContext) -> Bool
    public static func tracks(_ tracks: [Track], _ filter: LibraryFilter, _ ctx: FilterContext) -> [Track]
    /// Album/Interpret/Genre bleibt, wenn mindestens einer seiner Titel passt.
    public static func albums(_ albums: [AlbumInfo], _ filter: LibraryFilter, index: LibraryIndex, _ ctx: FilterContext) -> [AlbumInfo]
    public static func artists(_ artists: [ArtistInfo], _ filter: LibraryFilter, index: LibraryIndex, _ ctx: FilterContext) -> [ArtistInfo]
    public static func genres(_ genres: [GenreInfo], _ filter: LibraryFilter, index: LibraryIndex, _ ctx: FilterContext) -> [GenreInfo]
}
```

## 3. Ansichten (`Settings/ViewOptions.swift`)

```swift
public enum LibraryViewMode: String, CaseIterable, Codable, Hashable, Sendable {
    case grid = "GRID", compactGrid = "COMPACT_GRID", list = "LIST", detailedList = "DETAILED_LIST", coverFlow = "COVER_FLOW"
    public var label: String   // „Raster“, „Kompaktes Raster“, „Liste“, „Detailliste“, „Cover Flow“
}

/// Bereich, für den eine Ansicht gespeichert wird (Favoriten getrennt nach Titeln und Alben).
public enum LibraryViewContext: String, CaseIterable, Codable, Hashable, Sendable {
    case tracks = "TRACKS", albums = "ALBUMS", playlists = "PLAYLISTS", artists = "ARTISTS", genres = "GENRES",
         favoriteTracks = "FAVORITE_TRACKS", favoriteAlbums = "FAVORITE_ALBUMS"
    public var label: String
}

public enum DetailColumn: String, CaseIterable, Codable, Hashable, Sendable {
    case trackNumber = "TRACK_NUMBER", title = "TITLE", artist = "ARTIST", album = "ALBUM", albumArtist = "ALBUM_ARTIST",
         genre = "GENRE", year = "YEAR", duration = "DURATION", plays = "PLAYS", lastPlayed = "LAST_PLAYED",
         dateAdded = "DATE_ADDED", rating = "RATING", bpm = "BPM", format = "FORMAT", bitrate = "BITRATE",
         trackCount = "TRACK_COUNT", albumCount = "ALBUM_COUNT"
    public var label: String
    public var defaultWidth: Double          // Punkte
    public var numeric: Bool                 // rechtsbündig
}

public struct LibraryViewOptions: Hashable, Codable, Sendable {
    public var mode: LibraryViewMode
    public var coverSize: Double             // Kachelbreite in Punkten, in coverSizeRange
    public var spacing: Double               // in spacingRange
    public var showSecondaryText: Bool       // Interpret/Untertitel unter Kacheln
    public var showDetails: Bool             // zusätzliche Zeile (Jahr, Anzahl, Dauer)
    public var columns: [DetailColumn]       // sichtbare Spalten der Detailliste, in Reihenfolge
    public static let coverSizeRange: ClosedRange<Double>   // 90...320
    public static let spacingRange: ClosedRange<Double>     // 6...40
    public static func defaults(for context: LibraryViewContext) -> LibraryViewOptions
    /// Für den Kontext sinnvolle Spalten (z. B. Alben: Album, Albuminterpret, Jahr, Genre, Titel-Anzahl, Dauer, Hinzugefügt).
    public static func availableColumns(for context: LibraryViewContext) -> [DetailColumn]
}
```
Standard: Titel → Liste, Alben → Raster, Playlists → Liste, Interpreten → Liste, Genres → Raster,
Favoriten-Titel → Liste, Favoriten-Alben → Raster.

## 4. Automatische Playlists (`Library/SmartPlaylists.swift`)

```swift
SmartKind: + .recentlyAdded = "RECENTLY_ADDED", .recentlyPlayed = "RECENTLY_PLAYED", .neverPlayed = "NEVER_PLAYED",
             .genre = "GENRE", .topRated = "TOP_RATED"
SmartPlaylist: + public var genreKey: String?
SmartPlaylists:
    public static func recentlyAdded(_ tracks: [Track], limit: Int = limit) -> SmartPlaylist      // „Zuletzt hinzugefügt“
    public static func recentlyPlayed(_ tracks: [Track], stats: [Int64: PlayStats], limit: Int = limit) -> SmartPlaylist  // „Zuletzt gespielt“
    public static func neverPlayed(_ tracks: [Track], stats: [Int64: PlayStats]) -> SmartPlaylist   // „Nie gespielt“
    public static func topRated(_ tracks: [Track], minRating: Int = 80) -> SmartPlaylist          // „Am besten bewertet“
    public static func byGenre(_ tracks: [Track], minTracks: Int = 10, maxPlaylists: Int = 12) -> [SmartPlaylist]  // „Genre: Rock“ …
```
Stabile IDs: `smart:neu`, `smart:zuletzt`, `smart:nie`, `smart:bewertet`, `smart:genre:<key>`.

## 5. Equalizer (`Audio/EqualizerModel.swift`)

```swift
public struct EqUserPreset: Hashable, Codable, Sendable, Identifiable {
    public var id: String           // "user-…"
    public var name: String
    public var gains: [Float]       // 10 Werte, geklemmt auf ±12
    public var bassDb: Float?       // optional mitgespeicherter Bass
    public init(id: String = "user-" + UUID().uuidString, name: String, gains: [Float], bassDb: Float? = nil)
}
AudioEffectsSettings:
    public func withUserPreset(_ preset: EqUserPreset) -> AudioEffectsSettings   // Bänder (+ Bass), EQ an
    public func activeUserPreset(in presets: [EqUserPreset]) -> EqUserPreset?    // exakte Übereinstimmung der Bänder
```

## 6. Tonhöhe

```swift
PitchSettings: + public static let fineStep: Float = 0.1, coarseStep: Float = 1
               + public func withSemitones(_:) rundet auf 0,01 und klemmt (bestehende Funktion, Verhalten präzisiert)
Formatting.semitones(_:)  zeigt Zehntel: „+1,5 Halbtöne“, „−0,3 Halbtöne“, „+1 Halbton“, „Original“
Formatting.cents(_ semitones: Float) -> String   // „+150 Cent“
```

## 7. Player-Designs, Mini-Player

```swift
PlayerTheme: + .modernGlass = "MODERN_GLASS", .aurora = "AURORA", .reelToReel = "REEL_TO_REEL"
    labels: „Modern Glass“, „Aurora“, „Studio Reel“ (+ description)
public enum CassetteColor: String, CaseIterable, Codable, Hashable, Sendable {
    case smoke = "SMOKE", rose = "ROSE", ocean = "OCEAN", mint = "MINT", sunset = "SUNSET", ivory = "IVORY", cover = "COVER"
    public var label: String; public var argb: UInt32?   // nil bei .cover (aus Coverfarbe)
}
public enum MiniPlayerSize: String, CaseIterable, Codable, Hashable, Sendable {
    case compact = "COMPACT", standard = "STANDARD", large = "LARGE"
    public var label: String; public var height: Double   // 64, 84, 112
}
public enum AnimationLevel: String, CaseIterable, Codable, Hashable, Sendable { case full = "FULL", reduced = "REDUCED", off = "OFF"; public var label: String }
```

## 8. Neue Einstellungen in `AppSettings` (alle mit Standardwert, tolerant gelesen, gespeichert)

```swift
// Allgemein
public var startSection: LibrarySection?        // nil = zuletzt benutzter Bereich
public var showMenuBarPlayer = true
// Erscheinungsbild
public var dynamicCoverColors = true            // Hintergründe in den Farben des aktuellen Covers
public var reduceTransparency = false           // ruhige, undurchsichtige Flächen (schneller auf älteren Macs)
public var animationLevel: AnimationLevel = .full
// Player
public var cassetteColor: CassetteColor = .smoke
public var miniPlayerSize: MiniPlayerSize = .standard
public var miniPlayerShowsDesign = true         // Mini-Player zeigt Platte/Kassette/CD
// Bibliothek / Ansicht
public var viewOptions: [String: LibraryViewOptions]    // Schlüssel = LibraryViewContext.rawValue
public func viewOptions(for context: LibraryViewContext) -> LibraryViewOptions   // fehlend → defaults(for:)
public mutating func setViewOptions(_ options: LibraryViewOptions, for context: LibraryViewContext)
// Import
public var watchFolders = true
public var scanOnLaunch = true
// Wiedergabe
public var skipSeconds = 10                     // erlaubt: 5, 10, 15, 30
public var rememberLongTrackPosition = true
public var sleepTimerFadeOut = true
// Equalizer
public var eqUserPresets: [EqUserPreset] = []
public mutating func saveEqPreset(name: String) -> EqUserPreset           // aus aktuellen effects; Name eindeutig gemacht
public mutating func renameEqPreset(id: String, to name: String)
public mutating func updateEqPreset(id: String)                          // mit aktuellen effects überschreiben
public mutating func deleteEqPreset(id: String)
// Tonhöhe
public var keepPitchOnRelaunch = false          // false = beim Start wieder Original (wie Android)
// Lautstärke
public var maxVolume: Float = 3.0               // 1.0 … 3.0 (Obergrenze des Reglers)
// Liedtexte
public var lyricsFontSize: Double = 17          // 12 … 30
public var lyricsAutoScroll = true
public var lyricsUseLrcFiles = true             // .lrc-Datei neben der Musikdatei verwenden
// Tastatur
public var mediaKeysEnabled = true
// Speicher
public var coverCacheLimitMB = 500              // 100 … 4000
// Datenschutz
public var recordHistory = true
public var recordPlayCounts = true
```
