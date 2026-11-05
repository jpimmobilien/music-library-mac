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

    // MARK: Abgeleitete Listen (je Bereich gefiltert und sortiert)
    @Published private(set) var trackList: [Track] = []
    @Published private(set) var albumList: [AlbumInfo] = []
    @Published private(set) var artistList: [ArtistInfo] = []
    @Published private(set) var genreList: [GenreInfo] = []
    @Published private(set) var smartPlaylists: [SmartPlaylist] = []
    @Published private(set) var playlistList: [Playlist] = []
    @Published private(set) var favoriteTrackList: [Track] = []
    @Published private(set) var favoriteAlbumList: [AlbumInfo] = []
    @Published private(set) var missingFavoriteAlbums: [FavoriteAlbum] = []

    // MARK: Navigation und Oberfläche
    @Published var section: LibrarySection = .tracks
    @Published var stacks: [LibrarySection: [Destination]] = [:]
    @Published var queries: [LibrarySection: String] = [:]
    @Published var playerOpen = false
    @Published var sidePanel: SidePanel?
    @Published var toasts: [Toast] = []
    @Published var searchFocusRequest = 0
    /// Ziel für „Zu Playlist hinzufügen …“ (öffnet das Auswahlblatt).
    @Published var addToPlaylistUids: [Int64]?
    /// Titel für das Bearbeitungsfenster (Metadaten).
    @Published var editorUids: [Int64] = []

    // MARK: Einstellungen
    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            saveSettings()
            if settings.effects != oldValue.effects || settings.pitch != oldValue.pitch {
                player.applyAudioSettings(effects: settings.effects, pitch: settings.pitch)
            }
            if settings.visualizer != oldValue.visualizer { player.setVisualizer(settings.visualizer) }
            if sortsChanged(oldValue) { recomputeLists() }
        }
    }

    private var recomputeTask: Task<Void, Never>?

    init(store: LibraryStore, demo: Bool = false) {
        self.store = store
        self.demo = demo
        self.settings = AppModel.loadSettings()
        self.player = PlayerService(store: store, demo: demo)
        self.library = LibraryService(store: store)
        self.metadata = MetadataService(store: store)
        self.section = settings.lastSection
        AppModel.shared = self
        player.model = self
        library.model = self
        metadata.model = self
        player.applyAudioSettings(effects: settings.effects, pitch: settings.pitch)
        player.setVisualizer(settings.visualizer)
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

    func query(_ section: LibrarySection) -> String { queries[section] ?? "" }

    func setQuery(_ section: LibrarySection, _ value: String) {
        queries[section] = value
        recomputeLists()
    }

    func recomputeLists() {
        let idx = index
        let s = settings
        let st = stats
        let favs = favoriteTracks
        let favAlbums = favoriteAlbums
        let pls = playlists
        let q = queries
        recomputeTask?.cancel()
        // Große Bibliotheken: im Hintergrund rechnen, Ergebnis gesammelt übernehmen.
        recomputeTask = Task.detached(priority: .userInitiated) { [weak self] in
            let lists = AppModel.computeLists(index: idx, settings: s, stats: st, favorites: favs, favoriteAlbums: favAlbums, playlists: pls, queries: q)
            if Task.isCancelled { return }
            // `[weak self]` erneut erfassen: ein schwach erfasstes `self` des äußeren (Sendable-)Closures darf
            // in Swift < 6.2 nicht in einem weiteren nebenläufigen Closure benutzt werden.
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.trackList = lists.tracks
                self.albumList = lists.albums
                self.artistList = lists.artists
                self.genreList = lists.genres
                self.smartPlaylists = lists.smart
                self.playlistList = lists.playlists
                self.favoriteTrackList = lists.favoriteTracks
                self.favoriteAlbumList = lists.favoriteAlbums
                self.missingFavoriteAlbums = lists.missingFavoriteAlbums
            }
        }
    }

    struct Lists {
        var tracks: [Track] = []
        var albums: [AlbumInfo] = []
        var artists: [ArtistInfo] = []
        var genres: [GenreInfo] = []
        var smart: [SmartPlaylist] = []
        var playlists: [Playlist] = []
        var favoriteTracks: [Track] = []
        var favoriteAlbums: [AlbumInfo] = []
        var missingFavoriteAlbums: [FavoriteAlbum] = []
    }

    nonisolated static func computeLists(index idx: LibraryIndex, settings s: AppSettings, stats st: [Int64: PlayStats], favorites favs: [Int64: Int64],
                                         favoriteAlbums favAlbums: [String: FavoriteAlbum], playlists pls: [Playlist], queries q: [LibrarySection: String]) -> Lists {
        var out = Lists()
        func terms(_ section: LibrarySection) -> [String] { TextNorm.searchTerms(q[section] ?? "") }

        // Titel: nur verfügbare (nicht verfügbare erscheinen nur in Playlists/Favoriten als „nicht verfügbar“)
        let available = idx.tracks.filter(\.available)
        let tt = terms(.tracks)
        let filteredTracks = tt.isEmpty ? available : available.filter { TextNorm.matchesAll(tt, idx.trackSearchText[$0.uid] ?? "") }
        out.tracks = Sorting.tracks(filteredTracks, sort: s.trackSort, stats: st)

        let at = terms(.albums)
        let albums = at.isEmpty ? idx.albums : idx.albums.filter { TextNorm.matchesAll(at, idx.albumSearchText[$0.key] ?? "") }
        out.albums = Sorting.albums(albums, sort: s.albumSort, stats: st)

        let rt = terms(.artists)
        let artists = rt.isEmpty ? idx.artists : idx.artists.filter { TextNorm.matchesAll(rt, TextNorm.key($0.name)) }
        out.artists = Sorting.artists(artists, sort: s.artistSort)

        let gt = terms(.genres)
        let genres = gt.isEmpty ? idx.genres : idx.genres.filter { TextNorm.matchesAll(gt, TextNorm.key($0.name)) }
        out.genres = Sorting.genres(genres, sort: s.genreSort)

        // Playlists: automatische + eigene
        let availableByUid = Dictionary(available.map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
        let favList = favs.map { FavoriteTrack(trackUid: $0.key, addedAt: $0.value) }
        var smart = [SmartPlaylists.favorites(favList, available: availableByUid),
                     SmartPlaylists.mostPlayed(available, stats: st),
                     SmartPlaylists.leastPlayed(available, stats: st)]
        smart.append(contentsOf: SmartPlaylists.decades(available))
        let pt = terms(.playlists)
        func matches(_ name: String) -> Bool { pt.isEmpty || TextNorm.matchesAll(pt, TextNorm.key(name)) }
        out.smart = smart.filter { matches($0.name) }
        out.playlists = Sorting.playlists(pls.filter { matches($0.name) }, sort: s.playlistSort, name: { $0.name }, count: { $0.entries.count })

        // Favoriten
        let ft = terms(.favorites)
        let favTracks = favs.keys.compactMap { idx.trackByUid[$0] }
        let favTracksFiltered = ft.isEmpty ? favTracks : favTracks.filter { TextNorm.matchesAll(ft, idx.trackSearchText[$0.uid] ?? "") }
        out.favoriteTracks = Sorting.favoriteTracks(favTracksFiltered, sort: s.favoriteTrackSort, addedAt: favs)
        let favAlbumInfos = favAlbums.keys.compactMap { idx.albumByKey[$0] }
        let favAlbumsFiltered = ft.isEmpty ? favAlbumInfos : favAlbumInfos.filter { TextNorm.matchesAll(ft, idx.albumSearchText[$0.key] ?? "") }
        out.favoriteAlbums = Sorting.favoriteAlbums(favAlbumsFiltered, sort: s.favoriteAlbumSort, favorites: favAlbums)
        out.missingFavoriteAlbums = favAlbums.values.filter { idx.albumByKey[$0.albumKey] == nil }.sorted { $0.addedAt > $1.addedAt }
        return out
    }

    var unavailableCount: Int { index.tracks.lazy.filter { !$0.available }.count }

    func smartPlaylist(_ id: String) -> SmartPlaylist? {
        if let s = smartPlaylists.first(where: { $0.id == id }) { return s }
        // auch bei aktiver Suche erreichbar
        return AppModel.computeLists(index: index, settings: settings, stats: stats, favorites: favoriteTracks, favoriteAlbums: favoriteAlbums,
                                     playlists: playlists, queries: [:]).smart.first { $0.id == id }
    }

    func playlist(_ id: Int64) -> Playlist? { playlists.first { $0.id == id } }

    func tracks(_ uids: [Int64]) -> [Track] { index.tracksOf(uids) }

    func track(_ uid: Int64) -> Track? { index.trackByUid[uid] }

    func isFavorite(_ uid: Int64) -> Bool { favoriteTracks[uid] != nil }

    // MARK: - Navigation

    func select(_ target: LibrarySection) {
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

    func openEditor() { openEditorAction?() }
    func openMiniPlayer() { openMiniPlayerAction?() }
    func openEqualizer() { openEqualizerAction?() }
}
