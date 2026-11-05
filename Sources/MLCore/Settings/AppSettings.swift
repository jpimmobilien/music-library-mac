import Foundation

/// Erscheinungsbild der App.
public enum ThemeMode: String, CaseIterable, Codable, Hashable, Sendable {
    case system = "SYSTEM"
    case light = "LIGHT"
    case dark = "DARK"

    public var label: String {
        switch self {
        case .system: return "Wie macOS"
        case .light: return "Hell"
        case .dark: return "Dunkel"
        }
    }

    public func isDark(systemIsDark: Bool) -> Bool {
        switch self {
        case .system: return systemIsDark
        case .light: return false
        case .dark: return true
        }
    }
}

/// Die sechs Hauptbereiche – Reihenfolge = Reihenfolge in der Seitenleiste.
/// (Auf Android `Section`; hier umbenannt, weil SwiftUI einen gleichnamigen Typ hat.)
public enum LibrarySection: String, CaseIterable, Codable, Hashable, Sendable {
    case tracks = "TRACKS"
    case albums = "ALBUMS"
    case playlists = "PLAYLISTS"
    case artists = "ARTISTS"
    case genres = "GENRES"
    case favorites = "FAVORITES"

    public var label: String {
        switch self {
        case .tracks: return "Titel"
        case .albums: return "Alben"
        case .playlists: return "Playlists"
        case .artists: return "Interpreten"
        case .genres: return "Genres"
        case .favorites: return "Favoriten"
        }
    }
}

public enum FavoritesTab: String, CaseIterable, Codable, Hashable, Sendable {
    case tracks = "TRACKS"
    case albums = "ALBUMS"

    public var label: String { self == .tracks ? "Titel" : "Alben" }
}

/// Design des Players. Alle verwenden dieselbe Bedienung und Wiedergabelogik – nur die Darstellung
/// unterscheidet sich. Gespeichert wird der Name; die Reihenfolge ist die Reihenfolge in der Auswahl
/// (neue Designs kommen ans Ende).
public enum PlayerTheme: String, CaseIterable, Codable, Hashable, Sendable {
    case vinylStudio = "VINYL_STUDIO"
    case classic = "CLASSIC"
    case cassette = "CASSETTE"
    case portableCD = "PORTABLE_CD"

    public var label: String {
        switch self {
        case .vinylStudio: return "Vinyl Studio"
        case .classic: return "Classic Music"
        case .cassette: return "Cassette Studio"
        case .portableCD: return "Portable CD"
        }
    }

    public var description: String {
        switch self {
        case .vinylStudio:
            return "Realistischer Plattenspieler mit Cover-Label und Tonarm – die charakteristische Hauptansicht."
        case .classic:
            return "Großes Albumcover, ruhiger Hintergrund in den Farben des Covers, klare Typografie."
        case .cassette:
            return "Getöntes Kassettengehäuse mit sichtbaren Wickeln, Bandzählwerk und Statusanzeigen."
        case .portableCD:
            return "Tragbarer CD-Player im Stil der 2000er: drehende CD mit Cover-Label unter getöntem Deckel, Anzeige mit Titelnummer und Laufzeit."
        }
    }

    /// Gespeicherten Wert lesen – auch die Einstellung „Darstellung“ aus Android 1.1.0 wird übernommen.
    public static func fromStored(_ theme: String?, legacyVisual: String?) -> PlayerTheme {
        if let theme, let value = PlayerTheme(rawValue: theme) { return value }
        return legacyVisual == "COVER" ? .classic : .vinylStudio
    }
}

/// Was „Löschen“ mit der Datei macht.
public enum DeleteMode: String, CaseIterable, Codable, Hashable, Sendable {
    /// In den Papierkorb des Finders legen (wiederherstellbar).
    case trash = "TRASH"
    /// Endgültig löschen.
    case permanent = "PERMANENT"

    public var label: String { self == .trash ? "In den Papierkorb" : "Endgültig löschen" }
}

/// Dauerhaft gespeicherte Einstellungen (Portierung von `AppSettings` aus `data/SettingsStore.kt`,
/// ergänzt um Mac-Einstellungen). Jeder Bereich hat seine eigene Sortierung.
///
/// Gespeichert als JSON (`Codable`). Lesen ist tolerant: unbekannte Schlüssel werden ignoriert,
/// fehlende oder ungültige Werte (unbekannte Aufzählungswerte, falsche Bandanzahl, …) ergeben den
/// Standardwert bzw. werden in den gültigen Bereich gebracht – ältere oder beschädigte Dateien
/// funktionieren immer.
public struct AppSettings: Hashable, Sendable {
    public var themeMode: ThemeMode = .system
    public var glassEffects = true
    public var trackSort = Sort(TrackSort.title, descending: false)
    public var albumSort = Sort(AlbumSort.title, descending: false)
    public var playlistSort = Sort(PlaylistSort.name, descending: false)
    public var artistSort = Sort(ArtistSort.name, descending: false)
    public var genreSort = Sort(GenreSort.name, descending: false)
    public var favoriteTrackSort = Sort(FavoriteTrackSort.added, descending: true)
    public var favoriteAlbumSort = Sort(FavoriteAlbumSort.added, descending: true)
    public var favoritesTab: FavoritesTab = .tracks
    public var deleteMode: DeleteMode = .trash
    public var effects = AudioEffectsSettings()
    public var lastSection: LibrarySection = .tracks
    public var playerTheme: PlayerTheme = .vinylStudio
    /// Optionale Klangvisualisierung im Player (aus = keinerlei Analyse).
    public var visualizer = false

    // Mac
    public var pitch = PitchSettings()
    /// Warteschlange, Titel und Position beim Start wiederherstellen (pausiert).
    public var resumeOnLaunch = true
    /// Komponist in Listen und im Player anzeigen.
    public var showComposer = false
    /// Wie lange Sicherungskopien (Datenbank, Originaldateien vor dem Schreiben der Tags) aufbewahrt werden.
    public var backupRetentionDays = 30
    /// Vor dem Schreiben von Tags in Dateien nachfragen.
    public var confirmBeforeWritingTags = true

    public static let backupRetentionRange = 1...3650

    public init() {}

    /// Liest gespeicherte Einstellungen; ungültige Daten ergeben die Standardwerte (wirft nie).
    public static func decode(from data: Data?) -> AppSettings {
        guard let data, !data.isEmpty else { return AppSettings() }
        return (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    /// JSON mit sortierten Schlüsseln (stabile Datei, gut vergleichbar).
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return (try? encoder.encode(self)) ?? Data()
    }
}

extension AppSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case themeMode, glassEffects, trackSort, albumSort, playlistSort, artistSort, genreSort
        case favoriteTrackSort, favoriteAlbumSort, favoritesTab, deleteMode, effects, lastSection
        case playerTheme, visualizer
        case pitch, resumeOnLaunch, showComposer, backupRetentionDays, confirmBeforeWritingTags
    }

    public init(from decoder: Decoder) throws {
        self.init()
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        func value<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            (try? c.decodeIfPresent(type, forKey: key)) ?? nil
        }
        if let v = value(ThemeMode.self, .themeMode) { themeMode = v }
        if let v = value(Bool.self, .glassEffects) { glassEffects = v }
        if let v = value(Sort<TrackSort>.self, .trackSort) { trackSort = v }
        if let v = value(Sort<AlbumSort>.self, .albumSort) { albumSort = v }
        if let v = value(Sort<PlaylistSort>.self, .playlistSort) { playlistSort = v }
        if let v = value(Sort<ArtistSort>.self, .artistSort) { artistSort = v }
        if let v = value(Sort<GenreSort>.self, .genreSort) { genreSort = v }
        if let v = value(Sort<FavoriteTrackSort>.self, .favoriteTrackSort) { favoriteTrackSort = v }
        if let v = value(Sort<FavoriteAlbumSort>.self, .favoriteAlbumSort) { favoriteAlbumSort = v }
        if let v = value(FavoritesTab.self, .favoritesTab) { favoritesTab = v }
        if let v = value(DeleteMode.self, .deleteMode) { deleteMode = v }
        if let v = value(AudioEffectsSettings.self, .effects) { effects = v }
        if let v = value(LibrarySection.self, .lastSection) { lastSection = v }
        playerTheme = PlayerTheme.fromStored(value(String.self, .playerTheme), legacyVisual: nil)
        if let v = value(Bool.self, .visualizer) { visualizer = v }
        if let v = value(PitchSettings.self, .pitch) { pitch = v }
        if let v = value(Bool.self, .resumeOnLaunch) { resumeOnLaunch = v }
        if let v = value(Bool.self, .showComposer) { showComposer = v }
        if let v = value(Int.self, .backupRetentionDays) {
            backupRetentionDays = min(max(v, Self.backupRetentionRange.lowerBound), Self.backupRetentionRange.upperBound)
        }
        if let v = value(Bool.self, .confirmBeforeWritingTags) { confirmBeforeWritingTags = v }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(themeMode, forKey: .themeMode)
        try c.encode(glassEffects, forKey: .glassEffects)
        try c.encode(trackSort, forKey: .trackSort)
        try c.encode(albumSort, forKey: .albumSort)
        try c.encode(playlistSort, forKey: .playlistSort)
        try c.encode(artistSort, forKey: .artistSort)
        try c.encode(genreSort, forKey: .genreSort)
        try c.encode(favoriteTrackSort, forKey: .favoriteTrackSort)
        try c.encode(favoriteAlbumSort, forKey: .favoriteAlbumSort)
        try c.encode(favoritesTab, forKey: .favoritesTab)
        try c.encode(deleteMode, forKey: .deleteMode)
        try c.encode(effects, forKey: .effects)
        try c.encode(lastSection, forKey: .lastSection)
        try c.encode(playerTheme, forKey: .playerTheme)
        try c.encode(visualizer, forKey: .visualizer)
        try c.encode(pitch, forKey: .pitch)
        try c.encode(resumeOnLaunch, forKey: .resumeOnLaunch)
        try c.encode(showComposer, forKey: .showComposer)
        try c.encode(backupRetentionDays, forKey: .backupRetentionDays)
        try c.encode(confirmBeforeWritingTags, forKey: .confirmBeforeWritingTags)
    }
}
