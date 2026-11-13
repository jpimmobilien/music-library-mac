import SwiftUI
import AppKit
import MLCore
import MLStore
import MLTags

/// Zentraler Zustand der App (entspricht `MusicViewModel` der Android-App).
///
/// Hält die Bibliothek (Index, Favoriten, Playlists, Statistik, Verlauf), Navigation, Suche und Einstellungen.
/// Wiedergabe (`PlayerService`), Einlesen (`LibraryService`) und Metadaten (`MetadataService`) sind eigene Dienste.
@MainActor
final class AppModel: ObservableObject {
    static var shared: AppModel!

    let store: LibraryStore
    let player: PlayerService
    let library: LibraryService
    let metadata: MetadataService
    /// „Hinzufügen“ (2.4): Internet-Adressen und Dateien laden, schneiden, umwandeln. Führt Warteschlange,
    /// Verlauf und Einstellungen beider Bereiche.
    private(set) var addStudio: StudioModel!
    /// „Studio“ (2.4): Titel der Bibliothek schneiden und bearbeiten.
    private(set) var studio: StudioModel!
    /// Demo-Modus (Vorschaubilder/Snapshots): keine Dateizugriffe, keine Wiedergabe.
    let demo: Bool

    // MARK: Bibliothek
    @Published private(set) var index: LibraryIndex = .empty
    @Published private(set) var favoriteTracks: [Int64: Int64] = [:]
    @Published private(set) var favoriteAlbums: [String: FavoriteAlbum] = [:]
    @Published private(set) var stats: [Int64: PlayStats] = [:]
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var folders: [LibraryFolder] = []
    @Published private(set) var libraryLoaded = false
    @Published var scanState: ScanState = .idle

    // MARK: Abgeleitete Listen (je Bereich gesucht, gefiltert und sortiert)
    /// Alle Listen in einem Wert: Eine Neuberechnung löst genau eine Aktualisierung der Oberfläche aus.
    @Published private(set) var lists = Lists()
    var trackList: [Track] { lists.tracks }
    var albumList: [AlbumInfo] { lists.albums }
    /// Abschnitte bei Sortierung nach Erscheinungsjahr oder „Hinzugefügt“ (sonst nil).
    var trackSections: [LibrarySectionRun]? { lists.trackSections }
    var albumSections: [LibrarySectionRun]? { lists.albumSections }
    var artistList: [ArtistInfo] { lists.artists }
    var genreList: [GenreInfo] { lists.genres }
    var smartPlaylists: [SmartPlaylist] { lists.smart }
    var playlistList: [Playlist] { lists.playlists }
    var favoriteTrackList: [Track] { lists.favoriteTracks }
    var favoriteAlbumList: [AlbumInfo] { lists.favoriteAlbums }
    var missingFavoriteAlbums: [FavoriteAlbum] { lists.missingFavoriteAlbums }
    /// Auswahlwerte der Filter (Genres, Jahrzehnte, Interpreten, Formate) aus allen verfügbaren Titeln.
    var facets: FilterFacets { lists.facets }
    /// Anzahl je Bereich ohne Suche und Filter (für „12 von 340“).
    var unfilteredCount: [LibraryViewContext: Int] { lists.unfilteredCount }

    /// Filter je Bereich (bewusst nicht gespeichert – beim nächsten Start ist wieder alles sichtbar).
    @Published private(set) var filters: [LibraryViewContext: LibraryFilter] = [:]

    // MARK: Navigation und Oberfläche
    @Published var section: LibrarySection = .tracks
    @Published var stacks: [LibrarySection: [Destination]] = [:]
    @Published var queries: [LibrarySection: String] = [:]
    @Published var playerOpen = false
    /// Arbeitsbereich statt der Bibliothek („Hinzufügen“, „Studio“ – eigene Einträge in der Navigation).
    @Published var workspace: MainWorkspace = .library
    /// Ein Arbeitsbereich ist offen (keine Bibliotheksansicht).
    var studioOpen: Bool { workspace != .library }
    /// Modell des offenen Arbeitsbereichs (nil = Bibliothek).
    var activeStudio: StudioModel? {
        switch workspace {
        case .library: return nil
        case .add: return addStudio
        case .studio: return studio
        }
    }
    @Published var sidePanel: SidePanel?
    @Published var toasts: [Toast] = []
    @Published var searchFocusRequest = 0
    /// Ziel für „Zu Playlist hinzufügen …“ (öffnet das Auswahlblatt).
    @Published var addToPlaylistUids: [Int64]?
    /// Titel für das Bearbeitungsfenster (Metadaten).
    @Published var editorUids: [Int64] = []

    // MARK: Einstellungen
    /// Gespeicherte Einstellungen. Bewusst kein `@Published`: Eine Zuweisung mit unverändertem Wert (z. B. aus
    /// einer Bindung, die beim Aufbau zurückschreibt) löst **keine** Aktualisierung aller Fenster aus –
    /// sonst können sich Ansichten und Bindungen gegenseitig endlos neu auslösen.
    private var storedSettings: AppSettings
    var settings: AppSettings {
        get { storedSettings }
        set {
            guard newValue != storedSettings else { return }
            objectWillChange.send()
            let oldValue = storedSettings
            storedSettings = newValue
            settingsDidChange(from: oldValue)
        }
    }

    private func settingsDidChange(from oldValue: AppSettings) {
        scheduleSave()
        if settings.effects != oldValue.effects || settings.pitch != oldValue.pitch {
            player.applyAudioSettings(effects: settings.effects, pitch: settings.pitch)
        }
        if settings.skipSeconds != oldValue.skipSeconds && !demo { player.updateSkipInterval() }
        if sortsChanged(oldValue) { recomputeLists() }
        if settings.watchFolders != oldValue.watchFolders { library.setWatching(settings.watchFolders) }
        if settings.mediaKeysEnabled != oldValue.mediaKeysEnabled { player.setMediaKeysEnabled(settings.mediaKeysEnabled) }
        if settings.coverCacheLimitMB != oldValue.coverCacheLimitMB { ArtworkStore.shared.setDiskLimit(megabytes: settings.coverCacheLimitMB) }
        if settings.visualizer != oldValue.visualizer || settings.animationLevel != oldValue.animationLevel {
            player.setVisualizer(settings.visualizer && PlayerMotionPolicy.continuous(settings))
        }
        if settings.dynamicCoverColors != oldValue.dynamicCoverColors {
            CoverAmbience.shared.update(for: player.current, enabled: settings.dynamicCoverColors)
        }
    }

    private var recomputeTask: Task<Void, Never>?
    private var pendingRecompute: DispatchWorkItem?
    private var pendingSave: DispatchWorkItem?

    init(store: LibraryStore, demo: Bool = false) {
        self.store = store
        self.demo = demo
        self.storedSettings = AppModel.loadSettings()
        self.player = PlayerService(store: store, demo: demo)
        self.library = LibraryService(store: store)
        self.metadata = MetadataService(store: store)
        self.section = settings.startSection ?? settings.lastSection   // Einstellung „Bereich beim Start“
        AppModel.shared = self
        let adder = StudioModel(app: self, services: demo ? .demo : .live, preview: demo ? nil : StudioPreviewFactory.make(), demo: demo)
        self.addStudio = adder
        self.studio = StudioModel(app: self, services: demo ? .demo : .live, preview: demo ? nil : StudioPreviewFactory.make(), demo: demo,
                                  workspace: .edit, queueHost: adder)
        player.model = self
        library.model = self
        metadata.model = self
        // Tonhöhe gilt bis zum Neustart (wie Android), außer „Tonhöhe beibehalten“ ist eingeschaltet
        if !settings.keepPitchOnRelaunch && !settings.pitch.isOriginal {
            settings.pitch = PitchSettings()
        }
        player.applyAudioSettings(effects: settings.effects, pitch: settings.pitch)
        // Pegelanalyse: erlaubt, wenn die Visualisierung eingeschaltet ist; sie rechnet nur, solange eine
        // Pegelanzeige sichtbar ist (`retainVisualizer`/`releaseVisualizer`).
        player.setVisualizer(settings.visualizer && PlayerMotionPolicy.continuous(settings))
        if !demo {
            if !settings.mediaKeysEnabled { player.setMediaKeysEnabled(false) }
            player.updateSkipInterval()
            ArtworkStore.shared.setDiskLimit(megabytes: settings.coverCacheLimitMB)
        }
    }

    // MARK: - Einstellungen speichern

    private static let settingsKey = "settings.v1"

    static func loadSettings() -> AppSettings {
        AppSettings.decode(from: UserDefaults.standard.data(forKey: settingsKey))
    }

    private func saveSettings() {
        guard !demo else { return }
        UserDefaults.standard.set(settings.encoded(), forKey: Self.settingsKey)
    }

    /// Speichert gebündelt (Regler und schnelle Änderungen schreiben nicht bei jedem Schritt).
    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveSettings() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Ausstehende Speicherung sofort ausführen (beim Beenden).
    func flushSettings() {
        pendingSave?.cancel()
        pendingSave = nil
        saveSettings()
    }

    // MARK: - Ansichten, Filter, Live-Audio (v2)

    func viewOptions(_ context: LibraryViewContext) -> LibraryViewOptions {
        settings.viewOptions(for: context)
    }

    func setViewOptions(_ options: LibraryViewOptions, for context: LibraryViewContext) {
        guard settings.viewOptions(for: context) != options else { return }
        settings.setViewOptions(options, for: context)
    }

    func filter(_ context: LibraryViewContext) -> LibraryFilter {
        filters[context] ?? LibraryFilter()
    }

    func setFilter(_ filter: LibraryFilter, for context: LibraryViewContext) {
        guard self.filter(context) != filter else { return }
        filters[context] = filter.isEmpty ? nil : filter
        recomputeLists()
    }

    /// Klangeinstellungen hörbar machen, ohne sie zu speichern (während ein Regler gezogen wird).
    func previewEffects(_ effects: AudioEffectsSettings) {
        player.applyAudioSettings(effects: effects, pitch: settings.pitch)
    }

    /// Tonhöhe hörbar machen, ohne sie zu speichern.
    func previewPitch(_ pitch: PitchSettings) {
        player.applyAudioSettings(effects: settings.effects, pitch: pitch)
    }

    private func sortsChanged(_ old: AppSettings) -> Bool {
        old.trackSort != settings.trackSort || old.albumSort != settings.albumSort || old.playlistSort != settings.playlistSort
            || old.artistSort != settings.artistSort || old.genreSort != settings.genreSort
            || old.favoriteTrackSort != settings.favoriteTrackSort || old.favoriteAlbumSort != settings.favoriteAlbumSort
    }

    // MARK: - Laden

    /// Lädt die Bibliothek aus der Datenbank (nach dem Start und nach Änderungen).
    func reloadLibrary() {
        let store = self.store
        Task.detached(priority: .userInitiated) {
            let tracks = (try? store.allTracks()) ?? []
            let index = LibraryIndex.build(tracks)
            let favs = (try? store.favoriteTracks()) ?? []
            let favAlbums = (try? store.favoriteAlbums()) ?? []
            let stats = (try? store.playStats()) ?? [:]
            let playlists = (try? store.playlists()) ?? []
            let history = (try? store.history(limit: 1000)) ?? []
            let folders = (try? store.folders()) ?? []
            let artwork = (try? store.allCustomArtwork()) ?? [:]
            ArtworkStore.shared.setOverrides(artwork)
            await MainActor.run {
                self.index = index
                self.favoriteTracks = Dictionary(favs.map { ($0.trackUid, $0.addedAt) }, uniquingKeysWith: { a, _ in a })
                self.favoriteAlbums = Dictionary(favAlbums.map { ($0.albumKey, $0) }, uniquingKeysWith: { a, _ in a })
                self.stats = stats
                self.playlists = playlists
                self.history = history
                self.folders = folders
                self.libraryLoaded = true
                self.recomputeLists()
                self.player.libraryChanged()
            }
        }
    }

    /// Nur Benutzerdaten neu laden (Favoriten, Playlists, Statistik, Verlauf) – schneller als die ganze Bibliothek.
    func reloadUserData() {
        favoriteTracks = Dictionary(((try? store.favoriteTracks()) ?? []).map { ($0.trackUid, $0.addedAt) }, uniquingKeysWith: { a, _ in a })
        favoriteAlbums = Dictionary(((try? store.favoriteAlbums()) ?? []).map { ($0.albumKey, $0) }, uniquingKeysWith: { a, _ in a })
        stats = (try? store.playStats()) ?? [:]
        playlists = (try? store.playlists()) ?? []
        history = (try? store.history(limit: 1000)) ?? []
        recomputeLists()
    }

    func reloadFolders() {
        folders = (try? store.folders()) ?? []
    }

    /// Setzt Bibliotheksdaten direkt (Demo-/Snapshot-Modus).
    func setDemoData(tracks: [Track], favorites: [Int64: Int64], favoriteAlbums: [String: FavoriteAlbum], stats: [Int64: PlayStats], playlists: [Playlist], history: [HistoryEntry]) {
        index = LibraryIndex.build(tracks)
        favoriteTracks = favorites
        self.favoriteAlbums = favoriteAlbums
        self.stats = stats
        self.playlists = playlists
        self.history = history
        libraryLoaded = true
        recomputeLists()
    }

    // MARK: - Abgeleitete Listen

    /// Angewendete Suche eines Bereichs (passt zu den angezeigten Ergebnissen).
    func query(_ section: LibrarySection) -> String { queries[section] ?? "" }

    /// Text im Suchfeld, auch während noch getippt wird.
    func liveQuery(_ section: LibrarySection) -> String { typedQueries[section] ?? queries[section] ?? "" }

    /// Noch nicht übernommene Eingaben – bewusst nicht veröffentlicht: Ein Tastendruck zeichnet nur das
    /// Suchfeld neu, nicht das ganze Fenster mit Tausenden Zeilen.
    private var typedQueries: [LibrarySection: String] = [:]

    func setQuery(_ section: LibrarySection, _ value: String) {
        typedQueries[section] = value
        // Beim Tippen gebündelt übernehmen und neu berechnen (spürbar flüssiger bei großen Bibliotheken)
        pendingRecompute?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applyTypedQueries() }
        pendingRecompute = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func applyTypedQueries() {
        recomputeLists()   // übernimmt die getippten Suchen
    }

    func recomputeLists() {
        pendingRecompute?.cancel()
        pendingRecompute = nil
        if !typedQueries.isEmpty {
            var q = queries
            for (section, text) in typedQueries { q[section] = text }
            typedQueries = [:]
            if q != queries { queries = q }
        }
        let idx = index
        let s = settings
        let st = stats
        let favs = favoriteTracks
        let favAlbums = favoriteAlbums
        let pls = playlists
        let q = queries
        let f = filters
        recomputeTask?.cancel()
        // Große Bibliotheken: im Hintergrund rechnen, Ergebnis in einem Schritt übernehmen.
        recomputeTask = Task.detached(priority: .userInitiated) { [weak self] in
            let lists = AppModel.computeLists(index: idx, settings: s, stats: st, favorites: favs, favoriteAlbums: favAlbums,
                                              playlists: pls, queries: q, filters: f)
            if Task.isCancelled { return }
            // `[weak self]` erneut erfassen: ein schwach erfasstes `self` des äußeren (Sendable-)Closures darf
            // in Swift < 6.2 nicht in einem weiteren nebenläufigen Closure benutzt werden.
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.lists = lists
            }
        }
    }

    struct Lists {
        var tracks: [Track] = []
        var albums: [AlbumInfo] = []
        var trackSections: [LibrarySectionRun]?
        var albumSections: [LibrarySectionRun]?
        var artists: [ArtistInfo] = []
        var genres: [GenreInfo] = []
        /// Automatische Playlists passend zur Suche im Bereich Playlists.
        var smart: [SmartPlaylist] = []
        /// Alle automatischen Playlists (ohne Suche) – für Detailansicht und Wiedergabe.
        var smartAll: [SmartPlaylist] = []
        var playlists: [Playlist] = []
        var favoriteTracks: [Track] = []
        var favoriteAlbums: [AlbumInfo] = []
        var missingFavoriteAlbums: [FavoriteAlbum] = []
        var facets: FilterFacets = .empty
        var unfilteredCount: [LibraryViewContext: Int] = [:]
    }

    nonisolated static func computeLists(index idx: LibraryIndex, settings s: AppSettings, stats st: [Int64: PlayStats], favorites favs: [Int64: Int64],
                                         favoriteAlbums favAlbums: [String: FavoriteAlbum], playlists pls: [Playlist],
                                         queries q: [LibrarySection: String], filters: [LibraryViewContext: LibraryFilter] = [:]) -> Lists {
        var out = Lists()
        func terms(_ section: LibrarySection) -> [String] { TextNorm.searchTerms(q[section] ?? "") }
        let ctx = FilterContext(favorites: Set(favs.keys), stats: st, nowSeconds: Int64(Date().timeIntervalSince1970))
        func active(_ c: LibraryViewContext) -> LibraryFilter? {
            guard let f = filters[c], !f.isEmpty else { return nil }
            return f
        }

        // Titel: nur verfügbare (nicht verfügbare erscheinen nur in Playlists/Favoriten als „nicht verfügbar“)
        let available = idx.tracks.filter(\.available)
        out.facets = LibraryFiltering.facets(available)
        out.unfilteredCount[.tracks] = available.count
        let tt = terms(.tracks)
        var filteredTracks = tt.isEmpty ? available : available.filter { TextNorm.matchesAll(tt, idx.trackSearchText[$0.uid] ?? "") }
        if let f = active(.tracks) { filteredTracks = LibraryFiltering.tracks(filteredTracks, f, ctx) }
        out.tracks = Sorting.tracks(filteredTracks, sort: s.trackSort, stats: st)
        out.trackSections = LibrarySectioning.tracks(out.tracks, sort: s.trackSort)

        out.unfilteredCount[.albums] = idx.albums.count
        let at = terms(.albums)
        var albums = at.isEmpty ? idx.albums : idx.albums.filter { TextNorm.matchesAll(at, idx.albumSearchText[$0.key] ?? "") }
        if let f = active(.albums) { albums = LibraryFiltering.albums(albums, f, index: idx, ctx) }
        out.albums = Sorting.albums(albums, sort: s.albumSort, stats: st)
        out.albumSections = LibrarySectioning.albums(out.albums, sort: s.albumSort)

        out.unfilteredCount[.artists] = idx.artists.count
        let rt = terms(.artists)
        var artists = rt.isEmpty ? idx.artists : idx.artists.filter { TextNorm.matchesAll(rt, TextNorm.key($0.name)) }
        if let f = active(.artists) { artists = LibraryFiltering.artists(artists, f, index: idx, ctx) }
        out.artists = Sorting.artists(artists, sort: s.artistSort)

        out.unfilteredCount[.genres] = idx.genres.count
        let gt = terms(.genres)
        var genres = gt.isEmpty ? idx.genres : idx.genres.filter { TextNorm.matchesAll(gt, TextNorm.key($0.name)) }
        if let f = active(.genres) { genres = LibraryFiltering.genres(genres, f, index: idx, ctx) }
        out.genres = Sorting.genres(genres, sort: s.genreSort)

        // Playlists: automatische + eigene
        let availableByUid = Dictionary(available.map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
        let favList = favs.map { FavoriteTrack(trackUid: $0.key, addedAt: $0.value) }
        var smart = [SmartPlaylists.favorites(favList, available: availableByUid),
                     SmartPlaylists.recentlyAdded(available),
                     SmartPlaylists.recentlyPlayed(available, stats: st),
                     SmartPlaylists.mostPlayed(available, stats: st),
                     SmartPlaylists.leastPlayed(available, stats: st),
                     SmartPlaylists.neverPlayed(available, stats: st),
                     SmartPlaylists.topRated(available)]
        smart.append(contentsOf: SmartPlaylists.decades(available))
        smart.append(contentsOf: SmartPlaylists.byGenre(available))
        out.smartAll = smart
        out.unfilteredCount[.playlists] = pls.count + smart.count
        let pt = terms(.playlists)
        func matches(_ name: String) -> Bool { pt.isEmpty || TextNorm.matchesAll(pt, TextNorm.key(name)) }
        out.smart = smart.filter { matches($0.name) }
        out.playlists = Sorting.playlists(pls.filter { matches($0.name) }, sort: s.playlistSort, name: { $0.name }, count: { $0.entries.count },
                                          created: { $0.createdAt }, modified: { $0.updatedAt })

        // Favoriten
        let ft = terms(.favorites)
        let favTracks = favs.keys.compactMap { idx.trackByUid[$0] }
        out.unfilteredCount[.favoriteTracks] = favTracks.count
        var favTracksFiltered = ft.isEmpty ? favTracks : favTracks.filter { TextNorm.matchesAll(ft, idx.trackSearchText[$0.uid] ?? "") }
        if let f = active(.favoriteTracks) { favTracksFiltered = LibraryFiltering.tracks(favTracksFiltered, f, ctx) }
        out.favoriteTracks = Sorting.favoriteTracks(favTracksFiltered, sort: s.favoriteTrackSort, addedAt: favs)
        let favAlbumInfos = favAlbums.keys.compactMap { idx.albumByKey[$0] }
        out.unfilteredCount[.favoriteAlbums] = favAlbumInfos.count
        var favAlbumsFiltered = ft.isEmpty ? favAlbumInfos : favAlbumInfos.filter { TextNorm.matchesAll(ft, idx.albumSearchText[$0.key] ?? "") }
        if let f = active(.favoriteAlbums) { favAlbumsFiltered = LibraryFiltering.albums(favAlbumsFiltered, f, index: idx, ctx) }
        out.favoriteAlbums = Sorting.favoriteAlbums(favAlbumsFiltered, sort: s.favoriteAlbumSort, favorites: favAlbums)
        out.missingFavoriteAlbums = favAlbums.values.filter { idx.albumByKey[$0.albumKey] == nil }.sorted { $0.addedAt > $1.addedAt }
        return out
    }

    var unavailableCount: Int { index.tracks.lazy.filter { !$0.available }.count }

    func smartPlaylist(_ id: String) -> SmartPlaylist? {
        // aus allen automatischen Playlists – auch bei aktiver Suche erreichbar, ohne neu zu rechnen
        lists.smartAll.first { $0.id == id }
    }

    func playlist(_ id: Int64) -> Playlist? { playlists.first { $0.id == id } }

    func tracks(_ uids: [Int64]) -> [Track] { index.tracksOf(uids) }

    func track(_ uid: Int64) -> Track? { index.trackByUid[uid] }

    func isFavorite(_ uid: Int64) -> Bool { favoriteTracks[uid] != nil }

    // MARK: - Navigation

    func select(_ target: LibrarySection) {
        if workspace != .library {
            workspace = .library
            section = target
            settings.lastSection = target
            return
        }
        if section == target {
            // Erneut gewählt: zurück zur Übersicht des Bereichs (wie Android)
            stacks[target] = []
        }
        section = target
        settings.lastSection = target
    }

    func open(_ destination: Destination) {
        var stack = stacks[section] ?? []
        if stack.last != destination { stack.append(destination) }
        stacks[section] = stack
    }

    /// Öffnet ein Ziel im passenden Bereich (z. B. „Album öffnen“ aus dem Player).
    func open(_ destination: Destination, in target: LibrarySection) {
        section = target
        var stack = stacks[target] ?? []
        if stack.last != destination { stack.append(destination) }
        stacks[target] = stack
        playerOpen = false
    }

    @discardableResult
    func back() -> Bool {
        if playerOpen {
            playerOpen = false
            return true
        }
        var stack = stacks[section] ?? []
        guard !stack.isEmpty else { return false }
        stack.removeLast()
        stacks[section] = stack
        return true
    }

    var currentDestination: Destination? { stacks[section]?.last }

    /// Studio öffnen (Navigation, ⌘7, Menü, „Titel bearbeiten …“).
    func openStudio() { open(.studio) }

    /// Arbeitsbereich öffnen („Studio“ ⌘7, „Hinzufügen“ ⌘8).
    func open(_ target: MainWorkspace) {
        playerOpen = false
        workspace = target
    }

    func openAlbum(of track: Track) {
        if let key = index.albumKeyByTrack[track.uid] { open(.album(key), in: .albums) }
    }

    func openArtist(named name: String) {
        let key = ArtistNames.key(ArtistNames.split(name).primary)
        if index.artistByKey[key] != nil { open(.artist(key), in: .artists) }
    }

    // MARK: - Mitteilungen

    func toast(_ text: String, action: String? = nil, isError: Bool = false, perform: (() -> Void)? = nil) {
        let t = Toast(text: text, actionLabel: action, isError: isError, action: perform)
        toasts.append(t)
        let delay: Double = action != nil ? 6.5 : 3.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.toasts.removeAll { $0.id == t.id }
        }
    }

    // MARK: - Favoriten

    func toggleFavorite(_ uids: [Int64]) {
        guard !uids.isEmpty else { return }
        let makeFavorite = !uids.allSatisfy { favoriteTracks[$0] != nil }
        setFavorite(uids, makeFavorite)
    }

    func setFavorite(_ uids: [Int64], _ favorite: Bool) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        for uid in uids { favoriteTracks[uid] = favorite ? (favoriteTracks[uid] ?? now) : nil }
        try? store.setFavorite(trackUids: uids, favorite)
        recomputeLists()
    }

    func isAlbumFavorite(_ key: String) -> Bool { favoriteAlbums[key] != nil }

    func toggleAlbumFavorite(_ album: AlbumInfo) {
        let fav = favoriteAlbums[album.key] == nil
        try? store.setFavoriteAlbum(key: album.key, title: album.title, artist: album.artist, fav)
        if fav {
            favoriteAlbums[album.key] = FavoriteAlbum(albumKey: album.key, title: album.title, artist: album.artist, addedAt: Int64(Date().timeIntervalSince1970 * 1000))
        } else {
            favoriteAlbums[album.key] = nil
        }
        recomputeLists()
    }

    func removeMissingAlbumFavorite(_ key: String) {
        try? store.setFavoriteAlbum(key: key, title: nil, artist: nil, false)
        favoriteAlbums[key] = nil
        recomputeLists()
    }

    // MARK: - Playlists

    func uniquePlaylistName(_ base: String = "Neue Playlist") -> String {
        PlaylistOrdering.uniqueName(base, existing: playlists.map(\.name))
    }

    @discardableResult
    func createPlaylist(name raw: String, trackUids: [Int64] = [], open: Bool = false) -> Int64? {
        guard let name = PlaylistOrdering.cleanName(raw) else { return nil }
        guard let id = try? store.createPlaylist(name: name, trackUids: trackUids) else { return nil }
        reloadUserData()
        toast(trackUids.isEmpty ? "Playlist „\(name)“ erstellt" : "„\(name)“ mit \(Formatting.tracks(trackUids.count)) erstellt")
        if open { self.open(.playlist(id), in: .playlists) }
        return id
    }

    func addToPlaylist(_ id: Int64, trackUids: [Int64], at position: Int? = nil) {
        guard !trackUids.isEmpty else { return }
        try? store.addToPlaylist(id: id, trackUids: trackUids, at: position)
        reloadUserData()
        if let p = playlist(id) { toast("\(Formatting.tracks(trackUids.count)) zu „\(p.name)“ hinzugefügt") }
    }

    func renamePlaylist(_ id: Int64, to raw: String) {
        guard let name = PlaylistOrdering.cleanName(raw) else { return }
        try? store.renamePlaylist(id: id, name: name)
        reloadUserData()
    }

    func deletePlaylist(_ id: Int64) {
        guard let p = playlist(id) else { return }
        let uids = p.entries.map(\.trackUid)
        try? store.deletePlaylist(id: id)
        stacks = stacks.mapValues { $0.filter { $0 != .playlist(id) } }
        reloadUserData()
        toast("Playlist „\(p.name)“ gelöscht", action: "Rückgängig") { [weak self] in
            guard let self else { return }
            if let newId = try? self.store.createPlaylist(name: p.name, trackUids: uids) {
                self.reloadUserData()
                _ = newId
            }
        }
    }

    func duplicatePlaylist(_ id: Int64) {
        guard let p = playlist(id) else { return }
        _ = try? store.duplicatePlaylist(id: id, name: uniquePlaylistName(p.name + " Kopie"))
        reloadUserData()
    }

    func removeFromPlaylist(_ id: Int64, entryIds: [Int64]) {
        guard let p = playlist(id) else { return }
        let removed = p.entries.filter { entryIds.contains($0.entryId) }
        try? store.removeFromPlaylist(id: id, entryIds: entryIds)
        reloadUserData()
        toast("\(Formatting.tracks(removed.count)) aus „\(p.name)“ entfernt", action: "Rückgängig") { [weak self] in
            guard let self else { return }
            for e in removed.sorted(by: { $0.position < $1.position }) {
                try? self.store.addToPlaylist(id: id, trackUids: [e.trackUid], at: e.position)
            }
            self.reloadUserData()
        }
    }

    func movePlaylistEntries(_ id: Int64, entryIds: [Int64], to index: Int) {
        try? store.movePlaylistEntries(id: id, entryIds: entryIds, toIndex: index)
        reloadUserData()
    }

    func setPlaylistOrder(_ id: Int64, entryIds: [Int64]) {
        try? store.setPlaylistOrder(id: id, entryIds: entryIds)
        reloadUserData()
    }

    // MARK: - Statistik und Verlauf

    func resetStats(_ uids: [Int64]) {
        try? store.resetStats(trackUids: uids)
        reloadUserData()
    }

    func clearHistory() {
        let old = history
        try? store.clearHistory()
        reloadUserData()
        toast("Verlauf gelöscht (\(old.count) Einträge)")
    }

    func removeHistory(_ ids: [Int64]) {
        try? store.removeHistory(ids: ids)
        reloadUserData()
    }

    /// Nach einer beendeten Wiedergabe (vom PlayerService).
    func playbackRecorded() {
        stats = (try? store.playStats()) ?? stats
        history = (try? store.history(limit: 1000)) ?? history
        if settings.trackSort.field == .playCount || settings.trackSort.field == .lastPlayed || section == .playlists {
            recomputeLists()
        }
    }

    // MARK: - Titel entfernen

    /// Titel aus der Bibliothek entfernen (Datei bleibt) oder Datei in den Papierkorb legen.
    func removeTracks(_ uids: [Int64], moveFilesToTrash: Bool) {
        let tracks = self.tracks(uids)
        guard !tracks.isEmpty else { return }
        if moveFilesToTrash {
            var failed = 0
            var trashed: [Int64] = []
            for t in tracks {
                do {
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: t.path), resultingItemURL: nil)
                    trashed.append(t.uid)
                } catch {
                    failed += 1
                }
            }
            player.removeFromQueue(uids: trashed)
            try? store.deleteTracks(uids: trashed)
            reloadLibrary()
            if failed > 0 {
                toast("\(failed) Datei(en) konnten nicht in den Papierkorb gelegt werden", isError: true)
            } else {
                toast("\(Formatting.tracks(trashed.count)) in den Papierkorb gelegt")
            }
        } else {
            try? store.setHidden(uids: uids, hidden: true)
            player.removeFromQueue(uids: uids)
            reloadLibrary()
            toast("\(Formatting.tracks(uids.count)) aus der Bibliothek entfernt", action: "Rückgängig") { [weak self] in
                try? self?.store.setHidden(uids: uids, hidden: false)
                self?.reloadLibrary()
            }
        }
    }

    // MARK: - Hinzufügedatum (v2.1)

    /// Fortschritt/Ergebnis der Bestimmung der Hinzufügedaten (Anzeige in den Einstellungen), `nil` = nichts zu melden.
    @Published var datesAddedStatus: String?
    /// Läuft gerade eine Bestimmung?
    @Published var datesAddedRunning = false

    /// Hinzufügedaten aller Titel neu bestimmen (Einstellungen → Bibliothek). Mit `useAppleMusic` wird zusätzlich die
    /// Apple-Musik-Mediathek gelesen (macOS fragt dafür einmal nach der Erlaubnis). Echte Daten aus Apple Musik
    /// werden nie durch schwächere Quellen ersetzt; ein bereits gesetztes Datum wird nie auf später verschoben.
    func rebuildDatesAdded(useAppleMusic: Bool) {
        library.reconstructDatesAdded(useAppleMusic: useAppleMusic, force: true)
    }

    // MARK: - Metadaten

    func showInfo(_ uids: [Int64]) {
        guard !uids.isEmpty else { return }
        editorUids = uids
        WindowRouter.shared.openEditor()
    }
}

/// Öffnet Fenster aus Nicht-View-Code (Menüs, Tastatur) über die in der Szene registrierte Aktion.
@MainActor
final class WindowRouter {
    static let shared = WindowRouter()
    var openEditorAction: (() -> Void)?
    var openMiniPlayerAction: (() -> Void)?
    var openEqualizerAction: (() -> Void)?
    var openSettingsAction: (() -> Void)?

    func openEditor() { openEditorAction?() }
    func openMiniPlayer() { openMiniPlayerAction?() }
    func openEqualizer() { openEqualizerAction?() }
    /// Einstellungen öffnen (optional direkt in einer Kategorie).
    func openSettings(_ category: String? = nil) {
        if let category { pendingSettingsCategory = category }
        NSApp.activate(ignoringOtherApps: true)
        openSettingsAction?()
        NotificationCenter.default.post(name: .openSettingsCategory, object: nil)
    }
    /// Kategorie, die das Einstellungsfenster beim nächsten Öffnen zeigen soll.
    var pendingSettingsCategory: String?
}

extension Notification.Name {
    static let openSettingsCategory = Notification.Name("MusicLibrary.openSettingsCategory")
}
