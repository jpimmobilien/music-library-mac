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
    // Seit v2
    case modernGlass = "MODERN_GLASS"
    case aurora = "AURORA"
    case reelToReel = "REEL_TO_REEL"

    public var label: String {
        switch self {
        case .vinylStudio: return "Vinyl Studio"
        case .classic: return "Classic Music"
        case .cassette: return "Cassette Studio"
        case .portableCD: return "Portable CD"
        case .modernGlass: return "Modern Glass"
        case .aurora: return "Aurora"
        case .reelToReel: return "Studio Reel"
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
        case .modernGlass:
            return "Schwebendes Cover auf mattiertem Glas in den Farben des Covers – klar, ruhig und modern."
        case .aurora:
            return "Weiche, fließende Farbschleier aus den Farben des Covers, die sich sanft zur Musik bewegen."
        case .reelToReel:
            return "Studio-Tonbandmaschine mit zwei laufenden Spulen, Bandweg über die Tonköpfe und VU-Metern."
        }
    }

    /// Gespeicherten Wert lesen – auch die Einstellung „Darstellung“ aus Android 1.1.0 wird übernommen.
    public static func fromStored(_ theme: String?, legacyVisual: String?) -> PlayerTheme {
        if let theme, let value = PlayerTheme(rawValue: theme) { return value }
        return legacyVisual == "COVER" ? .classic : .vinylStudio
    }
}

/// Farbe des Kassettengehäuses im Design „Cassette Studio“ (und im Mini-Player).
public enum CassetteColor: String, CaseIterable, Codable, Hashable, Sendable {
    case smoke = "SMOKE"
    case rose = "ROSE"
    case ocean = "OCEAN"
    case mint = "MINT"
    case sunset = "SUNSET"
    case ivory = "IVORY"
    /// Aus der Hauptfarbe des aktuellen Covers.
    case cover = "COVER"

    public var label: String {
        switch self {
        case .smoke: return "Rauchglas"
        case .rose: return "Rosé"
        case .ocean: return "Ozean"
        case .mint: return "Mint"
        case .sunset: return "Abendrot"
        case .ivory: return "Elfenbein"
        case .cover: return "Wie das Cover"
        }
    }

    /// Tönung des Gehäuses (ARGB 0xAARRGGBB); `nil` bei `.cover` (aus der Coverfarbe).
    public var argb: UInt32? {
        switch self {
        case .smoke: return 0xFF2B_2628
        case .rose: return 0xFFD9_8A9B
        case .ocean: return 0xFF3F_7FA6
        case .mint: return 0xFF7F_C8A9
        case .sunset: return 0xFFE8_875A
        case .ivory: return 0xFFED_E6D6
        case .cover: return nil
        }
    }
}

/// Größe des Mini-Players.
public enum MiniPlayerSize: String, CaseIterable, Codable, Hashable, Sendable {
    case compact = "COMPACT"
    case standard = "STANDARD"
    case large = "LARGE"

    public var label: String {
        switch self {
        case .compact: return "Kompakt"
        case .standard: return "Standard"
        case .large: return "Groß"
        }
    }

    /// Höhe in Punkten.
    public var height: Double {
        switch self {
        case .compact: return 64
        case .standard: return 84
        case .large: return 112
        }
    }
}

/// Umfang der Animationen (Player, Übergänge).
public enum AnimationLevel: String, CaseIterable, Codable, Hashable, Sendable {
    case full = "FULL"
    case reduced = "REDUCED"
    case off = "OFF"

    public var label: String {
        switch self {
        case .full: return "Alle"
        case .reduced: return "Reduziert"
        case .off: return "Aus"
        }
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

    // v2 – Allgemein
    /// Bereich beim Start; `nil` = zuletzt benutzter Bereich.
    public var startSection: LibrarySection?
    public var showMenuBarPlayer = true
    // v2 – Erscheinungsbild
    /// Hintergründe in den Farben des aktuellen Covers.
    public var dynamicCoverColors = true
    /// Ruhige, undurchsichtige Flächen (schneller auf älteren Macs).
    public var reduceTransparency = false
    public var animationLevel: AnimationLevel = .full
    // v2 – Player
    public var cassetteColor: CassetteColor = .smoke
    public var miniPlayerSize: MiniPlayerSize = .standard
    /// Mini-Player zeigt Platte/Kassette/CD.
    public var miniPlayerShowsDesign = true
    // v2 – Bibliothek / Ansicht
    /// Gespeicherte Ansichten; Schlüssel = `LibraryViewContext.rawValue` (fehlend → Standard des Bereichs).
    public var viewOptions: [String: LibraryViewOptions] = [:]
    // v2 – Import
    public var watchFolders = true
    public var scanOnLaunch = true
    // v2 – Wiedergabe
    /// Sprungweite der Vor-/Zurück-Tasten in Sekunden (erlaubt: `skipSecondsOptions`).
    public var skipSeconds = 10
    /// Position langer Titel (Hörbücher, Mixe) merken.
    public var rememberLongTrackPosition = true
    /// Sleep-Timer blendet am Ende sanft aus.
    public var sleepTimerFadeOut = true
    // v2 – Equalizer
    public var eqUserPresets: [EqUserPreset] = []
    // v2 – Tonhöhe
    /// `false` = beim Start wieder Original (wie Android).
    public var keepPitchOnRelaunch = false
    // v2 – Lautstärke
    /// Obergrenze des Lautstärkereglers (1,0 … 3,0).
    public var maxVolume: Float = 3.0
    // v2 – Liedtexte
    public var lyricsFontSize: Double = 17
    public var lyricsAutoScroll = true
    /// .lrc-Datei neben der Musikdatei verwenden.
    public var lyricsUseLrcFiles = true
    // v2 – Tastatur
    public var mediaKeysEnabled = true
    // v2 – Speicher
    /// Obergrenze des Cover-Zwischenspeichers in MB.
    public var coverCacheLimitMB = 500
    // v2 – Datenschutz
    public var recordHistory = true
    public var recordPlayCounts = true

    public static let backupRetentionRange = 1...3650
    public static let skipSecondsOptions = [5, 10, 15, 30]
    public static let defaultSkipSeconds = 10
    public static let maxVolumeRange: ClosedRange<Float> = 1...3
    public static let lyricsFontSizeRange: ClosedRange<Double> = 12...30
    public static let coverCacheLimitRange = 100...4000

    public init() {}

    // MARK: - Ansichten

    /// Gespeicherte Ansicht des Bereichs; fehlend → `LibraryViewOptions.defaults(for:)`.
    public func viewOptions(for context: LibraryViewContext) -> LibraryViewOptions {
        viewOptions[context.rawValue] ?? LibraryViewOptions.defaults(for: context)
    }

    /// Speichert die Ansicht des Bereichs (bereinigt, siehe `LibraryViewOptions.normalized(for:)`).
    public mutating func setViewOptions(_ options: LibraryViewOptions, for context: LibraryViewContext) {
        viewOptions[context.rawValue] = options.normalized(for: context)
    }

    // MARK: - Eigene Equalizer-Presets

    /// Speichert die aktuellen Bänder (und den Bass) als neues Preset. Der Name wird bereinigt und
    /// eindeutig gemacht („Rock“ → „Rock (2)“, wenn es „Rock“ schon gibt).
    @discardableResult
    public mutating func saveEqPreset(name: String) -> EqUserPreset {
        let unique = EqUserPreset.uniqueName(name, existing: eqUserPresets.map(\.name))
        var preset = EqUserPreset(name: unique, gains: effects.bandGains, bassDb: effects.bassDb)
        while eqUserPresets.contains(where: { $0.id == preset.id }) { preset.id = EqUserPreset.idPrefix + UUID().uuidString }
        eqUserPresets.append(preset)
        return preset
    }

    /// Benennt ein Preset um (bereinigt, eindeutig unter den übrigen Presets). Unbekannte Kennung: nichts.
    public mutating func renameEqPreset(id: String, to name: String) {
        guard let i = eqUserPresets.firstIndex(where: { $0.id == id }) else { return }
        let others = eqUserPresets.indices.filter { $0 != i }.map { eqUserPresets[$0].name }
        eqUserPresets[i].name = EqUserPreset.uniqueName(name, existing: others)
    }

    /// Überschreibt ein Preset mit den aktuellen Bändern (und dem Bass). Unbekannte Kennung: nichts.
    public mutating func updateEqPreset(id: String) {
        guard let i = eqUserPresets.firstIndex(where: { $0.id == id }) else { return }
        eqUserPresets[i].gains = EqUserPreset.normalizedGains(effects.bandGains)
        eqUserPresets[i].bassDb = EqUserPreset.normalizedBass(effects.bassDb)
    }

    public mutating func deleteEqPreset(id: String) {
        eqUserPresets.removeAll { $0.id == id }
    }

    /// Gelesene Preset-Liste: doppelte Kennungen (beschädigte Datei) erhalten eine neue.
    static func normalizedPresets(_ presets: [EqUserPreset]) -> [EqUserPreset] {
        var ids = Set<String>()
        return presets.map { p in
            var preset = p
            while ids.contains(preset.id) { preset.id = EqUserPreset.idPrefix + UUID().uuidString }
            ids.insert(preset.id)
            return preset
        }
    }

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
        // v2
        case startSection, showMenuBarPlayer, dynamicCoverColors, reduceTransparency, animationLevel
        case cassetteColor, miniPlayerSize, miniPlayerShowsDesign, viewOptions, watchFolders, scanOnLaunch
        case skipSeconds, rememberLongTrackPosition, sleepTimerFadeOut, eqUserPresets, keepPitchOnRelaunch
        case maxVolume, lyricsFontSize, lyricsAutoScroll, lyricsUseLrcFiles, mediaKeysEnabled, coverCacheLimitMB
        case recordHistory, recordPlayCounts
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

        // v2
        startSection = value(String.self, .startSection).flatMap(LibrarySection.init(rawValue:))
        if let v = value(Bool.self, .showMenuBarPlayer) { showMenuBarPlayer = v }
        if let v = value(Bool.self, .dynamicCoverColors) { dynamicCoverColors = v }
        if let v = value(Bool.self, .reduceTransparency) { reduceTransparency = v }
        if let v = value(AnimationLevel.self, .animationLevel) { animationLevel = v }
        if let v = value(CassetteColor.self, .cassetteColor) { cassetteColor = v }
        if let v = value(MiniPlayerSize.self, .miniPlayerSize) { miniPlayerSize = v }
        if let v = value(Bool.self, .miniPlayerShowsDesign) { miniPlayerShowsDesign = v }
        if let stored = value([String: LibraryViewOptions.StoredViewOptions].self, .viewOptions) {
            for (key, options) in stored {
                guard let context = LibraryViewContext(rawValue: key) else { continue } // unbekannter Bereich
                viewOptions[key] = options.resolved(defaults: LibraryViewOptions.defaults(for: context)).normalized(for: context)
            }
        }
        if let v = value(Bool.self, .watchFolders) { watchFolders = v }
        if let v = value(Bool.self, .scanOnLaunch) { scanOnLaunch = v }
        if let v = value(Int.self, .skipSeconds) {
            skipSeconds = Self.skipSecondsOptions.contains(v) ? v : Self.defaultSkipSeconds
        }
        if let v = value(Bool.self, .rememberLongTrackPosition) { rememberLongTrackPosition = v }
        if let v = value(Bool.self, .sleepTimerFadeOut) { sleepTimerFadeOut = v }
        if let v = value([LenientElement<EqUserPreset>].self, .eqUserPresets) {
            eqUserPresets = Self.normalizedPresets(v.compactMap(\.value)) // ungültige Einträge entfallen
        }
        if let v = value(Bool.self, .keepPitchOnRelaunch) { keepPitchOnRelaunch = v }
        if let v = value(Float.self, .maxVolume), v.isFinite {
            maxVolume = min(max(v, Self.maxVolumeRange.lowerBound), Self.maxVolumeRange.upperBound)
        }
        if let v = value(Double.self, .lyricsFontSize), v.isFinite {
            lyricsFontSize = min(max(v, Self.lyricsFontSizeRange.lowerBound), Self.lyricsFontSizeRange.upperBound)
        }
        if let v = value(Bool.self, .lyricsAutoScroll) { lyricsAutoScroll = v }
        if let v = value(Bool.self, .lyricsUseLrcFiles) { lyricsUseLrcFiles = v }
        if let v = value(Bool.self, .mediaKeysEnabled) { mediaKeysEnabled = v }
        if let v = value(Int.self, .coverCacheLimitMB) {
            coverCacheLimitMB = min(max(v, Self.coverCacheLimitRange.lowerBound), Self.coverCacheLimitRange.upperBound)
        }
        if let v = value(Bool.self, .recordHistory) { recordHistory = v }
        if let v = value(Bool.self, .recordPlayCounts) { recordPlayCounts = v }
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
        // v2
        try c.encodeIfPresent(startSection, forKey: .startSection)
        try c.encode(showMenuBarPlayer, forKey: .showMenuBarPlayer)
        try c.encode(dynamicCoverColors, forKey: .dynamicCoverColors)
        try c.encode(reduceTransparency, forKey: .reduceTransparency)
        try c.encode(animationLevel, forKey: .animationLevel)
        try c.encode(cassetteColor, forKey: .cassetteColor)
        try c.encode(miniPlayerSize, forKey: .miniPlayerSize)
        try c.encode(miniPlayerShowsDesign, forKey: .miniPlayerShowsDesign)
        try c.encode(viewOptions, forKey: .viewOptions)
        try c.encode(watchFolders, forKey: .watchFolders)
        try c.encode(scanOnLaunch, forKey: .scanOnLaunch)
        try c.encode(skipSeconds, forKey: .skipSeconds)
        try c.encode(rememberLongTrackPosition, forKey: .rememberLongTrackPosition)
        try c.encode(sleepTimerFadeOut, forKey: .sleepTimerFadeOut)
        try c.encode(eqUserPresets, forKey: .eqUserPresets)
        try c.encode(keepPitchOnRelaunch, forKey: .keepPitchOnRelaunch)
        try c.encode(maxVolume, forKey: .maxVolume)
        try c.encode(lyricsFontSize, forKey: .lyricsFontSize)
        try c.encode(lyricsAutoScroll, forKey: .lyricsAutoScroll)
        try c.encode(lyricsUseLrcFiles, forKey: .lyricsUseLrcFiles)
        try c.encode(mediaKeysEnabled, forKey: .mediaKeysEnabled)
        try c.encode(coverCacheLimitMB, forKey: .coverCacheLimitMB)
        try c.encode(recordHistory, forKey: .recordHistory)
        try c.encode(recordPlayCounts, forKey: .recordPlayCounts)
    }
}
