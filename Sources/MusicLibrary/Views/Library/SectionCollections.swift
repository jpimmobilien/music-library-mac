import SwiftUI
import AppKit
import MLCore

// Inhalte der Bereiche in der gewählten Ansicht: Titel, Alben, Interpreten, Genres – mit ihren Aktionen
// (Öffnen, Abspielen, Mischen, Herz) und Kontextmenüs.

// MARK: - Titel

struct TrackCollection: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.libraryViewport) private var viewport
    @Environment(\.displayScale) private var displayScale
    let context: LibraryViewContext
    let tracks: [Track]
    let source: PlaybackSource
    let sort: TableSortSpec

    var body: some View {
        LibraryModeHost(context: context) { options in
            content(options)
        }
    }

    @ViewBuilder
    private func content(_ options: LibraryViewOptions) -> some View {
        switch options.mode {
        case .list:
            TrackListView(items: TrackListItem.plain(tracks), config: listConfig(options))
        case .detailedList:
            TrackListView(items: TrackListItem.plain(tracks), config: TrackListConfig(source: source), layout: .table(tableSpec(options)))
        case .grid, .compactGrid:
            TrackListView(items: TrackListItem.plain(tracks), config: TrackListConfig(source: source),
                          layout: .tiles(TileMetrics(options: options, available: TileMetrics.available(viewport), scale: displayScale)))
        case .coverFlow:
            coverFlow(options)
        }
    }

    /// Liste: bei breitem Fenster eigene Album-Spalte, optional Jahr und Genre.
    private func listConfig(_ options: LibraryViewOptions) -> TrackListConfig {
        let usable: CGFloat = viewport.width - Spacing.gutter * 2
        let albumWidth: CGFloat? = usable > 900 ? min(300, usable * 0.26) : nil
        return TrackListConfig(source: source, albumColumnWidth: albumWidth, showDetails: options.showDetails && usable > 760)
    }

    private func tableSpec(_ options: LibraryViewOptions) -> TrackTableSpec {
        let wanted = options.columns.filter { $0 != context.primaryColumn }
        return TrackTableSpec(context: context, columns: TableLayout.fit(wanted, available: TableLayout.available(viewport)), sort: sort)
    }

    private func coverFlow(_ options: LibraryViewOptions) -> some View {
        let list = tracks
        let currentUid = player.current?.uid
        let favorites = model.favoriteTracks
        let playFrom: (Int) -> Void = { i in
            player.play(uids: list.map(\.uid), startIndex: i, shuffle: .keep, source: source)
        }
        let shuffleAll: () -> Void = {
            player.play(uids: list.map(\.uid), startIndex: nil, shuffle: .on, source: source)
        }
        return CoverFlowView(
            count: list.count,
            memoryKey: context.rawValue,
            options: options,
            item: { i in LibraryItems.track(list[i], favorite: favorites[list[i].uid] != nil, current: list[i].uid == currentUid) },
            activate: playFrom,
            play: { i, shuffle in
                if shuffle { shuffleAll() } else { playFrom(i) }
            },
            openLabel: "Album öffnen",
            open: { i in model.openAlbum(of: list[i]) },
            menu: { i in TrackMenuItems(uids: [list[i].uid], single: list[i], playAction: { playFrom(i) }) }
        )
    }
}

// MARK: - Alben

/// Alben der Ansicht, aus der ein Album gestartet wird (v2.1): Wird später im Player „Zufall“ eingeschaltet,
/// mischt die Wiedergabe nach Alben über genau diese Alben (Reihenfolge wie angezeigt).
@MainActor
enum AlbumPlayContext {
    /// Alben-Bereich bzw. Lieblingsalben (gefiltert und sortiert), je nachdem, wo das Album liegt.
    static func albums(containing key: String, model: AppModel) -> [[Int64]]? {
        let lists: [[AlbumInfo]] = model.section == .favorites
            ? [model.favoriteAlbumList, model.albumList]
            : [model.albumList, model.favoriteAlbumList]
        for list in lists where list.contains(where: { $0.key == key }) {
            return list.map(\.trackUids)
        }
        return nil
    }
}

@MainActor
enum AlbumActions {
    static func source(_ item: LibraryItem) -> PlaybackSource {
        PlaybackSource(kind: .album, label: item.title, id: item.id)
    }

    /// - Parameter albums: Alben der Ansicht (gefiltert, sortiert) – für „Mischen“ (nach Alben) und den
    ///   Albumkontext beim Abspielen eines Albums.
    static func collection(model: AppModel, player: PlayerService, albums: @escaping () -> [[Int64]]) -> CollectionActions {
        CollectionActions(
            open: { item in model.open(.album(item.id)) },
            play: { item, shuffle in
                if shuffle {
                    // „Mischen“ im Alben-Bereich: Alben in Zufallsfolge, jedes in Titelreihenfolge
                    player.shuffleAlbums(albums(), source: PlaybackSource(kind: .list, label: "Alben (gemischt)"))
                } else {
                    player.play(uids: item.trackUids, startIndex: 0, shuffle: .off, source: source(item), albumContext: albums())
                }
            },
            toggleFavorite: { item in
                if let album = model.index.albumByKey[item.id] { model.toggleAlbumFavorite(album) }
            },
            openLabel: "Album öffnen",
            source: { item in source(item) },
            albumContext: albums
        )
    }
}

struct AlbumCollection: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    let context: LibraryViewContext
    let albums: [AlbumInfo]
    let sort: TableSortSpec

    var body: some View {
        let currentUid = player.current?.uid
        let index = model.index
        let stats = model.stats
        let list = albums
        let viewAlbums: () -> [[Int64]] = { list.map(\.trackUids) }
        let actions = AlbumActions.collection(model: model, player: player, albums: viewAlbums)
        LibraryModeHost(context: context) { options in
            LibraryCollection(
                context: context,
                elements: albums,
                options: options,
                makeItem: { (album: AlbumInfo) -> LibraryItem in LibraryItems.album(album, model: model, currentUid: currentUid) },
                actions: actions,
                table: CollectionTable(sort: sort, cell: { (album: AlbumInfo, column: DetailColumn) -> String in
                    CollectionCells.album(album, column, index: index, stats: stats)
                }),
                menu: { (target: CollectionMenuTarget) in
                    AlbumMenuItems(albumKey: target.item.id, uids: target.uids, groups: target.groups, names: target.names,
                                   albumContext: viewAlbums)
                }
            )
        }
    }
}

/// Einzelne Albumkachel (Detailansichten: Interpret, Genre, „Mehr von …“).
struct AlbumTile: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    let album: AlbumInfo
    var style = TileStyle(compact: false, showSecondary: true, showDetails: false, artworkSize: .medium)
    /// Alben der umgebenden Reihe bzw. des Rasters (für „Zufall nach Alben“).
    var context: [[Int64]]? = nil

    var body: some View {
        let item = LibraryItems.album(album, model: model, currentUid: player.current?.uid)
        let albums: [[Int64]] = context ?? [album.trackUids]
        let actions = AlbumActions.collection(model: model, player: player, albums: { albums })
        CollectionTile(item: item, style: style, selected: false, playing: item.current && player.isPlaying,
                       onPlay: { actions.play(item, false) },
                       onFavorite: { actions.toggleFavorite?(item) })
            .equatable()
            .contentShape(Rectangle())
            .onTapGesture { actions.open(item) }
            .contextMenu { AlbumMenuItems(albumKey: album.key, uids: album.trackUids, albumContext: { albums }) }
            .onDrag { TrackDrag.provider(uids: album.trackUids, entryIds: []) }
    }
}

/// Kontextmenü eines Albums bzw. mehrerer gewählter Alben: Album wiedergeben, Zur Warteschlange, Zu Playlist,
/// Albuminformationen bearbeiten, Album löschen … (plus Mischen, Als Nächstes, Favorit, Öffnen).
struct AlbumMenuItems: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    let albumKey: String
    let uids: [Int64]
    /// Bei Mehrfachauswahl: die Titel je gewähltem Album (in angezeigter Reihenfolge).
    var groups: [[Int64]] = []
    var names: [String] = []
    /// Alben der Ansicht, aus der das Menü stammt.
    var albumContext: (() -> [[Int64]])? = nil

    var body: some View {
        let album = model.index.albumByKey[albumKey]
        let single: AlbumInfo? = (groups.count <= 1 && album?.trackUids == uids) ? album : nil
        let albumCount = max(groups.count, 1)
        let source = single.map { PlaybackSource(kind: .album, label: $0.title ?? "Album", id: $0.key) }
            ?? PlaybackSource(kind: .list, label: "Auswahl")
        Group {
            Button(single != nil ? "Album wiedergeben" : "\(Formatting.albums(albumCount)) wiedergeben") { play(single: single, source: source, shuffle: false) }
            Button(single != nil ? "Album mischen" : "Auswahl mischen") { play(single: single, source: source, shuffle: true) }
            Button("Als Nächstes spielen") { player.playNext(uids: uids) }
            Button("Zur Warteschlange") { player.addToQueue(uids: uids) }
            Divider()
            PlaylistSubmenu(uids: uids, suggestedName: single?.title)
        }
        Group {
            if let single {
                Button(model.isAlbumFavorite(single.key) ? "Album aus Favoriten entfernen" : "Album zu Favoriten hinzufügen") {
                    model.toggleAlbumFavorite(single)
                }
                Divider()
                Button("Album öffnen") { model.open(.album(single.key)) }
                if let artist = single.artist, !single.isVarious {
                    Button("Interpret öffnen") { model.openArtist(named: artist) }
                }
                Button("Albuminformationen bearbeiten …") { model.showInfo(single.trackUids) }
            } else {
                Divider()
                Button("Informationen bearbeiten (\(Formatting.tracks(uids.count))) …") { model.showInfo(uids) }
                Button("Als Album zusammenfassen …") { MergeAlbumDialog.present(model: model, uids: uids) }
            }
        }
        Group {
            Divider()
            Button(single != nil ? "Album löschen …" : "\(Formatting.albums(albumCount)) löschen …") {
                let title = single?.title ?? names.first ?? "Unbekanntes Album"
                let subject: DeleteSubject = single != nil ? .album(title: title) : DeleteSubject.groups(.albums, count: albumCount, firstName: names.first)
                RemoveTracksDialog.present(model: model, uids: uids, subject: subject)
            }
        }
    }

    /// Ein Album: mit den Alben der Ansicht als Kontext. Mehrere: nacheinander, jedes in Titelreihenfolge.
    private func play(single: AlbumInfo?, source: PlaybackSource, shuffle: Bool) {
        let context: [[Int64]]? = single != nil ? albumContext?() : (groups.isEmpty ? nil : groups)
        player.play(uids: uids, startIndex: shuffle ? nil : 0, shuffle: shuffle ? .on : .off, source: source, albumContext: context)
    }
}

/// „Zu Playlist“ als Untermenü (nativ, mit Textbeschriftung).
struct PlaylistSubmenu: View {
    @EnvironmentObject private var model: AppModel
    let uids: [Int64]
    var suggestedName: String? = nil

    var body: some View {
        Menu("Zu Playlist") {
            Button("Neue Playlist …") { NewPlaylistDialog.present(model: model, trackUids: uids, suggestedName: suggestedName) }
            if !model.playlists.isEmpty { Divider() }
            ForEach(model.playlists) { p in
                Button(p.name) { model.addToPlaylist(p.id, trackUids: uids) }
            }
        }
    }
}

/// Gemeinsame Einträge für Gruppen von Titeln (Interpret, Genre, Playlist, Auswahl).
struct GroupMenuItems: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    let uids: [Int64]
    let source: PlaybackSource
    var suggestedName: String? = nil

    var body: some View {
        let allFavorite = !uids.isEmpty && uids.allSatisfy { model.isFavorite($0) }
        Group {
            Button("Wiedergeben") { player.play(uids: uids, startIndex: 0, shuffle: .off, source: source) }
            Button("Mischen") { player.play(uids: uids, startIndex: nil, shuffle: .on, source: source) }
            Button("Als Nächstes spielen") { player.playNext(uids: uids) }
            Button("Zur Warteschlange") { player.addToQueue(uids: uids) }
            Divider()
            PlaylistSubmenu(uids: uids, suggestedName: suggestedName)
            Button(allFavorite ? "Titel aus Favoriten entfernen" : "Alle Titel zu Favoriten hinzufügen") {
                model.setFavorite(uids, !allFavorite)
            }
        }
    }
}

// MARK: - Interpreten

struct ArtistCollection: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    let artists: [ArtistInfo]
    let sort: TableSortSpec

    var body: some View {
        let currentKeys = LibraryItems.artistKeys(of: player.current)
        let index = model.index
        let stats = model.stats
        let actions = CollectionActions(
            open: { item in model.open(.artist(item.id)) },
            play: { item, shuffle in
                player.play(uids: item.trackUids, startIndex: shuffle ? nil : 0, shuffle: shuffle ? .on : .off,
                            source: PlaybackSource(kind: .artist, label: item.title, id: item.id))
            },
            openLabel: "Interpret öffnen",
            source: { item in PlaybackSource(kind: .artist, label: item.title, id: item.id) }
        )
        LibraryModeHost(context: .artists) { options in
            LibraryCollection(
                context: .artists,
                elements: artists,
                options: options,
                makeItem: { (artist: ArtistInfo) -> LibraryItem in LibraryItems.artist(artist, model: model, currentKeys: currentKeys) },
                actions: actions,
                table: CollectionTable(sort: sort, cell: { (artist: ArtistInfo, column: DetailColumn) -> String in
                    CollectionCells.artist(artist, column, index: index, stats: stats)
                }),
                menu: { (target: CollectionMenuTarget) in
                    ArtistMenuItems(artistKey: target.item.id, name: target.item.title, uids: target.uids, count: target.groups.count)
                }
            )
        }
    }
}

struct ArtistMenuItems: View {
    @EnvironmentObject private var model: AppModel
    let artistKey: String
    let name: String
    let uids: [Int64]
    /// Anzahl der betroffenen Interpreten (> 1 bei Mehrfachauswahl).
    var count: Int = 1

    var body: some View {
        let single = count <= 1 && (model.index.artistByKey[artistKey].map { $0.trackUids == uids } ?? false)
        let source = single ? PlaybackSource(kind: .artist, label: name, id: artistKey) : PlaybackSource(kind: .list, label: "Auswahl")
        GroupMenuItems(uids: uids, source: source, suggestedName: single ? name : nil)
        if single {
            Divider()
            Button("Interpret öffnen") { model.open(.artist(artistKey)) }
        }
        Divider()
        Button("Informationen bearbeiten (\(Formatting.tracks(uids.count))) …") { model.showInfo(uids) }
        Button(single ? "Titel des Interpreten löschen …" : "Titel löschen …") {
            RemoveTracksDialog.present(model: model, uids: uids,
                                       subject: DeleteSubject.groups(.artists, count: max(count, 1), firstName: name))
        }
    }
}

// MARK: - Genres

struct GenreCollection: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    let genres: [GenreInfo]
    let sort: TableSortSpec

    var body: some View {
        let currentKeys = LibraryItems.genreKeys(of: player.current)
        let index = model.index
        let stats = model.stats
        let actions = CollectionActions(
            open: { item in model.open(.genre(item.id)) },
            play: { item, shuffle in
                player.play(uids: item.trackUids, startIndex: shuffle ? nil : 0, shuffle: shuffle ? .on : .off,
                            source: PlaybackSource(kind: .genre, label: item.title, id: item.id))
            },
            openLabel: "Genre öffnen",
            source: { item in PlaybackSource(kind: .genre, label: item.title, id: item.id) }
        )
        LibraryModeHost(context: .genres) { options in
            LibraryCollection(
                context: .genres,
                elements: genres,
                options: options,
                makeItem: { (genre: GenreInfo) -> LibraryItem in LibraryItems.genre(genre, currentKeys: currentKeys) },
                actions: actions,
                table: CollectionTable(sort: sort, cell: { (genre: GenreInfo, column: DetailColumn) -> String in
                    CollectionCells.genre(genre, column, index: index, stats: stats)
                }),
                menu: { (target: CollectionMenuTarget) in
                    GenreMenuItems(genreKey: target.item.id, name: target.item.title, uids: target.uids, count: target.groups.count)
                }
            )
        }
    }
}

struct GenreMenuItems: View {
    @EnvironmentObject private var model: AppModel
    let genreKey: String
    let name: String
    let uids: [Int64]
    /// Anzahl der betroffenen Genres (> 1 bei Mehrfachauswahl).
    var count: Int = 1

    var body: some View {
        let single = count <= 1 && (model.index.genreByKey[genreKey].map { $0.trackUids == uids } ?? false)
        let source = single ? PlaybackSource(kind: .genre, label: name, id: genreKey) : PlaybackSource(kind: .list, label: "Auswahl")
        GroupMenuItems(uids: uids, source: source, suggestedName: single ? name : nil)
        if single {
            Divider()
            Button("Genre öffnen") { model.open(.genre(genreKey)) }
        }
    }
}
