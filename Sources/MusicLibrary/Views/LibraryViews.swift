import SwiftUI
import AppKit
import MLCore

// Bereiche „Titel“, „Alben“, „Interpreten“, „Genres“ mit Detailansichten (Android: TracksScreen, AlbumsScreens,
// ArtistsGenresScreens). v2: jede Übersicht in fünf Ansichten (Raster, kompaktes Raster, Liste, Detailliste,
// Cover Flow), sichtbare Sortierung, Filter und Darstellungsoptionen in der Werkzeugkapsel.

/// Zahnrad in den Werkzeugkapseln.
struct SettingsAction: View {
    var body: some View {
        BarAction(icon: Icons.settings, label: "Einstellungen (⌘,)") {
            WindowRouter.shared.openSettings()
        }
    }
}

// MARK: - Titel

struct TracksView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService

    var body: some View {
        let tracks = model.trackList
        let q = model.query(.tracks).trimmingCharacters(in: .whitespaces)
        let filtered = !model.filter(.tracks).isEmpty
        let total = model.unfilteredCount[.tracks] ?? model.index.tracks.count
        let summary: String? = model.index.tracks.isEmpty ? nil
            : librarySummary(tracks.count, total, narrowed: !q.isEmpty || filtered, Formatting.tracks)
        let label: String = !q.isEmpty ? "Suche „\(q)“" : (filtered ? "Gefilterte Titel" : "Alle Titel")
        let source = PlaybackSource(kind: .list, label: label)
        LibraryScaffold(title: "Titel", toolbar: { toolbar(tracks) }) {
            VStack(spacing: 0) {
                LargeTitleHeader(title: "Titel", section: .tracks, placeholder: "Titel, Interpret, Album oder Genre",
                                 summary: summary, filterContext: .tracks)
                if model.index.tracks.isEmpty {
                    LibraryEmptyState()
                } else if tracks.isEmpty {
                    NoMatchesView(context: .tracks, query: q, noun: "Kein Titel")
                } else {
                    TrackCollection(context: .tracks, tracks: tracks, source: source, sort: sortSpec, sections: model.trackSections)
                }
            }
            .padding(.horizontal, Spacing.gutter)
        }
    }

    private var sortSpec: TableSortSpec {
        ColumnSorts.spec(ColumnSorts.track, sort: model.settings.trackSort) { model.settings.trackSort = $0 }
    }

    /// „Mischen“ im Bereich Titel: alle Titel der aktuellen (gesuchten, gefilterten, sortierten) Ansicht.
    private func toolbar(_ tracks: [Track]) -> some View {
        let shuffle: (() -> Void)? = tracks.isEmpty ? nil : {
            player.play(uids: tracks.map(\.uid), startIndex: nil, shuffle: .on, source: PlaybackSource(kind: .list, label: "Alle Titel (gemischt)"))
        }
        return LibraryToolbar(context: .tracks, style: .full, sort: model.settings.trackSort, setSort: { model.settings.trackSort = $0 },
                              shuffleLabel: "Alle angezeigten Titel gemischt abspielen", shuffle: shuffle) {
            BarAction(icon: Icons.difference, label: "Duplikate finden") { model.open(.duplicates) }
        }
    }
}

/// Leere Bibliothek: Musikordner hinzufügen (statt Android „Musik wird gesucht“).
struct LibraryEmptyState: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.scanState.isRunning || !model.libraryLoaded {
            EmptyStateView(icon: Icons.vinyl, title: "Musik wird eingelesen …", text: "Die App liest deine Musikordner ein. Das geschieht nur beim ersten Mal ausführlich.")
        } else if model.folders.isEmpty {
            EmptyStateView(icon: Icons.musicNote, title: "Willkommen in deiner Musikbibliothek",
                           text: "Wähle die Ordner mit deiner Musik – auch auf externen Laufwerken. Die Dateien bleiben, wo sie sind; neue Titel erscheinen automatisch.") {
                PillButton(title: "Musikordner hinzufügen …", icon: Icons.folderOpen, style: .filled) { model.library.chooseFolders() }
            }
        } else {
            EmptyStateView(icon: Icons.musicNote, title: "Noch keine Musik gefunden",
                           text: "In den gewählten Ordnern wurden keine Audiodateien gefunden (MP3, AAC/M4A, ALAC, FLAC, WAV, AIFF, Ogg Vorbis).") {
                HStack(spacing: 10) {
                    PillButton(title: "Jetzt prüfen", icon: Icons.refresh) { model.library.rescan(reason: "Manuell") }
                    PillButton(title: "Ordner hinzufügen …", icon: Icons.folderOpen) { model.library.chooseFolders() }
                }
            }
        }
    }
}

// MARK: - Alben

struct AlbumsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService

    var body: some View {
        let albums = model.albumList
        let q = model.query(.albums).trimmingCharacters(in: .whitespaces)
        let narrowed = !q.isEmpty || !model.filter(.albums).isEmpty
        let total = model.unfilteredCount[.albums] ?? model.index.albums.count
        let summary: String? = model.index.albums.isEmpty ? nil : librarySummary(albums.count, total, narrowed: narrowed, Formatting.albums)
        LibraryScaffold(title: "Alben", toolbar: { toolbar(albums) }) {
            VStack(spacing: 0) {
                LargeTitleHeader(title: "Alben", section: .albums, placeholder: "Album, Album-Interpret, Interpret oder Genre",
                                 summary: summary, filterContext: .albums)
                if model.index.albums.isEmpty {
                    EmptyStateView(icon: Icons.album, title: "Keine Alben", text: "Sobald Musik gefunden wurde, erscheinen hier die Alben.")
                } else if albums.isEmpty {
                    NoMatchesView(context: .albums, query: q, noun: "Kein Album")
                } else {
                    AlbumCollection(context: .albums, albums: albums, sort: sortSpec, sections: model.albumSections)
                }
            }
            .padding(.horizontal, Spacing.gutter)
        }
    }

    private var sortSpec: TableSortSpec {
        ColumnSorts.spec(ColumnSorts.album, sort: model.settings.albumSort) { model.settings.albumSort = $0 }
    }

    /// „Mischen“ im Bereich Alben: die angezeigten Alben in Zufallsfolge, jedes Album in Titelreihenfolge.
    private func toolbar(_ albums: [AlbumInfo]) -> some View {
        let shuffle: (() -> Void)? = albums.isEmpty ? nil : {
            player.shuffleAlbums(albums.map(\.trackUids), source: PlaybackSource(kind: .list, label: "Alle Alben (gemischt)"))
        }
        return LibraryToolbar(context: .albums, style: .full, sort: model.settings.albumSort, setSort: { model.settings.albumSort = $0 },
                              shuffleLabel: "Angezeigte Alben gemischt abspielen (Alben in Zufallsfolge, jedes in Titelreihenfolge)",
                              shuffle: shuffle)
    }
}

struct AlbumDetailView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    let albumKey: String
    @State private var backdrop: NSImage?

    var body: some View {
        if let album = model.index.albumByKey[albumKey] {
            let tracks = model.index.tracksOf(album.trackUids)
            let cover = model.index.coverTrackOf(album)
            let source = PlaybackSource(kind: .album, label: album.title ?? "Album", id: album.key)
            let metaParts: [String?] = [album.genre, album.year.map { String($0) }, Formatting.tracks(album.trackCount), Formatting.longDuration(album.totalDurationMs)]
            let meta: String = metaParts.compactMap { $0 }.joined(separator: " · ")
            // Alben der Ansicht, aus der das Album geöffnet wurde (für „Zufall nach Alben“ im Player)
            let albumKey = album.key
            let context: () -> [[Int64]] = { AlbumPlayContext.albums(containing: albumKey, model: model) ?? [album.trackUids] }
            LibraryScaffold(title: album.title ?? "Album", onBack: { model.back() }, edgeToEdgeTop: true, actions: {
                BarAction(icon: Icons.play, label: "Abspielen") { player.play(uids: album.trackUids, startIndex: 0, shuffle: .off, source: source, albumContext: context()) }
                BarAction(icon: Icons.shuffle, label: "Mischen") { player.play(uids: album.trackUids, startIndex: nil, shuffle: .on, source: source, albumContext: context()) }
            }) {
                VStack(spacing: 0) {
                    DetailHeader(
                        backdrop: backdrop,
                        title: album.title ?? "Unbekanntes Album",
                        subtitle: album.isVarious ? "Verschiedene Interpreten" : album.artist,
                        onSubtitle: (album.isVarious || album.artist == nil) ? nil : ({ model.openArtist(named: album.artist ?? "") } as () -> Void),
                        meta: meta,
                        artwork: {
                            TrackArtwork(track: cover, size: .medium, cornerRadius: Radius.artworkLarge, iconFraction: 0.42)
                                .frame(width: 230, height: 230)
                                .shadow(color: Color.black.opacity(0.28), radius: 22, y: 12)
                        },
                        buttons: {
                            PillButton(title: "Abspielen", icon: Icons.play, style: .filled, minWidth: 130) { player.play(uids: album.trackUids, startIndex: 0, shuffle: .off, source: source, albumContext: context()) }
                            PillButton(title: "Mischen", icon: Icons.shuffle, minWidth: 130) { player.play(uids: album.trackUids, startIndex: nil, shuffle: .on, source: source, albumContext: context()) }
                            GlassIconButton(icon: model.isAlbumFavorite(album.key) ? Icons.favorite : Icons.favoriteBorder,
                                            label: model.isAlbumFavorite(album.key) ? "Album aus Favoriten entfernen" : "Album zu Favoriten hinzufügen",
                                            tint: model.isAlbumFavorite(album.key) ? colors.heart : nil) { model.toggleAlbumFavorite(album) }
                            GlassIconButton(icon: Icons.edit, label: "Informationen zum Album bearbeiten") { model.showInfo(album.trackUids) }
                        }
                    )
                    VStack(alignment: .leading, spacing: 0) {
                        if album.isMultiDisc {
                            ForEach(album.discNumbers, id: \.self) { disc in
                                ListLabel("Disc \(disc)")
                                TrackListView(items: TrackListItem.plain(tracks.filter { ($0.discNumber ?? 1) == disc }),
                                              config: TrackListConfig(showArtwork: false, showAlbum: false, numbering: .trackNumber, source: source,
                                                                      albumContext: context))
                            }
                        } else {
                            TrackListView(items: TrackListItem.plain(tracks),
                                          config: TrackListConfig(showArtwork: false, showAlbum: false, numbering: .trackNumber, source: source,
                                                                  albumContext: context))
                        }
                        if let year = album.year {
                            Text(verbatim: "\(year) · \(Formatting.tracks(album.trackCount)) · \(Formatting.longDuration(album.totalDurationMs))")
                                .textStyle(Typo.bodySmall)
                                .foregroundColor(colors.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 14)
                                .padding(.leading, 6)
                        }
                        MoreAlbumsRow(album: album)
                    }
                    .padding(.horizontal, Spacing.gutter)
                    // darunter folgen ziehbare Albumkacheln: Auswahlrahmen nur knapp unter der Titelliste beginnen
                    .environment(\.libraryMarqueeTail, 16)
                }
            }
            .task(id: cover?.coverKey) {
                if let cover { backdrop = await ArtworkStore.shared.image(for: cover, size: .medium) }
            }
        } else {
            LibraryScaffold(title: "Album", onBack: { model.back() }) {
                EmptyStateView(icon: Icons.album, title: "Album nicht verfügbar", text: "Dieses Album ist derzeit nicht in der Bibliothek (z. B. externes Laufwerk getrennt).")
            }
        }
    }
}

/// „Mehr von …“: weitere Alben des Album-Interpreten als Kachelreihe.
private struct MoreAlbumsRow: View {
    @EnvironmentObject private var model: AppModel
    let album: AlbumInfo

    var body: some View {
        let others = otherAlbums()
        if let artist = album.artist, !album.isVarious, !others.isEmpty {
            SectionTitle(text: "Mehr von \(artist)")
            AlbumShelf(albums: others)
        }
    }

    private func otherAlbums() -> [AlbumInfo] {
        guard let artist = album.artist, !album.isVarious else { return [] }
        let key = ArtistNames.key(ArtistNames.split(artist).primary)
        guard let info = model.index.artistByKey[key] else { return [] }
        let albums = info.albumKeys.filter { $0 != album.key }.compactMap { model.index.albumByKey[$0] }
        return Array(albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }.prefix(24))
    }
}

/// Waagerechte Reihe von Albumkacheln (Detailansichten).
struct AlbumShelf: View {
    let albums: [AlbumInfo]
    var tileWidth: CGFloat = 168

    var body: some View {
        // Alben der Reihe als Kontext für „Zufall nach Alben“
        let context: [[Int64]] = albums.map(\.trackUids)
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 20) {
                ForEach(albums) { album in
                    AlbumTile(album: album, context: context).frame(width: tileWidth)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Interpreten

struct ArtistsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService

    var body: some View {
        let artists = model.artistList
        let q = model.query(.artists).trimmingCharacters(in: .whitespaces)
        let narrowed = !q.isEmpty || !model.filter(.artists).isEmpty
        let total = model.unfilteredCount[.artists] ?? model.index.artists.count
        let summary: String? = model.index.artists.isEmpty ? nil : librarySummary(artists.count, total, narrowed: narrowed, Formatting.artists)
        LibraryScaffold(title: "Interpreten", toolbar: { toolbar(artists) }) {
            VStack(spacing: 0) {
                LargeTitleHeader(title: "Interpreten", section: .artists, placeholder: "Interpret suchen",
                                 summary: summary, filterContext: .artists)
                if model.index.artists.isEmpty {
                    EmptyStateView(icon: "mic", title: "Keine Interpreten", text: "Titel ohne Interpret-Angabe erscheinen nur unter „Titel“ und „Alben“.")
                } else if artists.isEmpty {
                    NoMatchesView(context: .artists, query: q, noun: "Kein Interpret")
                } else {
                    ArtistCollection(artists: artists, sort: sortSpec)
                }
            }
            .padding(.horizontal, Spacing.gutter)
        }
    }

    private var sortSpec: TableSortSpec {
        ColumnSorts.spec(ColumnSorts.artist, sort: model.settings.artistSort) { model.settings.artistSort = $0 }
    }

    /// „Mischen“ im Bereich Interpreten: die Titel der gewählten Interpreten, ohne Auswahl die aller angezeigten.
    private func toolbar(_ artists: [ArtistInfo]) -> some View {
        let shuffle: (() -> Void)? = artists.isEmpty ? nil : {
            let selected = LibrarySelectionStore.shared.groups(of: .artists)
            let groups = selected ?? artists.map(\.trackUids)
            player.play(uids: Self.union(groups), startIndex: nil, shuffle: .on,
                        source: PlaybackSource(kind: .list, label: selected != nil ? "Gewählte Interpreten (gemischt)" : "Interpreten (gemischt)"))
        }
        return LibraryToolbar(context: .artists, style: .full, sort: model.settings.artistSort, setSort: { model.settings.artistSort = $0 },
                              shuffleLabel: "Titel der gewählten bzw. angezeigten Interpreten gemischt abspielen", shuffle: shuffle)
    }

    /// Titel mehrerer Gruppen ohne Doppelte.
    static func union(_ groups: [[Int64]]) -> [Int64] {
        TrackUids.union(groups)
    }
}

struct ArtistDetailView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    let artistKey: String
    @State private var backdrop: NSImage?

    var body: some View {
        if let artist = model.index.artistByKey[artistKey] {
            let tracks = Sorting.tracks(model.index.tracksOf(artist.trackUids), sort: Sort(.title, descending: false), stats: model.stats)
            let albums = artist.albumKeys.compactMap { model.index.albumByKey[$0] }.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
            let cover = tracks.first { $0.hasPicture }
            let source = PlaybackSource(kind: .artist, label: artist.name, id: artist.key)
            let metaParts: [String?] = [Formatting.tracks(tracks.count), albums.isEmpty ? nil : Formatting.albums(albums.count)]
            let meta: String = metaParts.compactMap { $0 }.joined(separator: " · ")
            LibraryScaffold(title: artist.name, onBack: { model.back() }, edgeToEdgeTop: true, actions: {
                BarAction(icon: Icons.play, label: "Abspielen") { player.play(uids: tracks.map(\.uid), startIndex: 0, shuffle: .off, source: source) }
                BarAction(icon: Icons.shuffle, label: "Mischen") { player.play(uids: tracks.map(\.uid), startIndex: nil, shuffle: .on, source: source) }
            }) {
                VStack(spacing: 0) {
                    DetailHeader(
                        backdrop: backdrop,
                        tint: GenreStyle.tint(text: artist.name),
                        title: artist.name,
                        eyebrow: "Interpret",
                        meta: meta,
                        artwork: {
                            Group {
                                if let cover {
                                    TrackArtwork(track: cover, size: .medium, circle: true)
                                } else {
                                    Monogram(name: artist.name, size: 200)
                                }
                            }
                            .frame(width: 200, height: 200)
                            .shadow(color: Color.black.opacity(0.25), radius: 20, y: 10)
                        },
                        buttons: {
                            PillButton(title: "Abspielen", icon: Icons.play, style: .filled, minWidth: 130) { player.play(uids: tracks.map(\.uid), startIndex: 0, shuffle: .off, source: source) }
                            PillButton(title: "Mischen", icon: Icons.shuffle, minWidth: 130) { player.play(uids: tracks.map(\.uid), startIndex: nil, shuffle: .on, source: source) }
                        }
                    )
                    VStack(alignment: .leading, spacing: 0) {
                        if !albums.isEmpty {
                            SectionTitle(text: albums.count == 1 ? "Album" : "Alben")
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 20, alignment: .top)], alignment: .leading, spacing: 22) {
                                ForEach(albums) { album in AlbumTile(album: album, context: albums.map(\.trackUids)) }
                            }
                            .padding(.vertical, 6)
                        }
                        SectionTitle(text: "Titel")
                        TrackListView(items: TrackListItem.plain(tracks), config: TrackListConfig(source: source))
                    }
                    .padding(.horizontal, Spacing.gutter)
                }
            }
            .task(id: cover?.coverKey) { if let cover { backdrop = await ArtworkStore.shared.image(for: cover, size: .medium) } }
        } else {
            LibraryScaffold(title: "Interpret", onBack: { model.back() }) {
                EmptyStateView(icon: "mic", title: "Nicht verfügbar", text: "Zu diesem Interpreten gibt es derzeit keine Titel.")
            }
        }
    }
}

// MARK: - Genres

struct GenresView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService

    var body: some View {
        let genres = model.genreList
        let q = model.query(.genres).trimmingCharacters(in: .whitespaces)
        let narrowed = !q.isEmpty || !model.filter(.genres).isEmpty
        let total = model.unfilteredCount[.genres] ?? model.index.genres.count
        let summary: String? = model.index.genres.isEmpty ? nil : librarySummary(genres.count, total, narrowed: narrowed, Formatting.genres)
        LibraryScaffold(title: "Genres", toolbar: { toolbar(genres) }) {
            VStack(spacing: 0) {
                LargeTitleHeader(title: "Genres", section: .genres, placeholder: "Genre suchen",
                                 summary: summary, filterContext: .genres)
                if model.index.genres.isEmpty {
                    EmptyStateView(icon: "genres_nav", title: "Keine Genres", text: "Sobald Musik gefunden wurde, erscheinen hier die Genres aus den Tags.")
                } else if genres.isEmpty {
                    NoMatchesView(context: .genres, query: q, noun: "Kein Genre")
                } else {
                    GenreCollection(genres: genres, sort: sortSpec)
                }
            }
            .padding(.horizontal, Spacing.gutter)
        }
    }

    private var sortSpec: TableSortSpec {
        ColumnSorts.spec(ColumnSorts.genre, sort: model.settings.genreSort) { model.settings.genreSort = $0 }
    }

    /// „Mischen“ im Bereich Genres: die Titel der gewählten Genres, ohne Auswahl die aller angezeigten.
    private func toolbar(_ genres: [GenreInfo]) -> some View {
        let shuffle: (() -> Void)? = genres.isEmpty ? nil : {
            let selected = LibrarySelectionStore.shared.groups(of: .genres)
            let groups = selected ?? genres.map(\.trackUids)
            player.play(uids: TrackUids.union(groups), startIndex: nil, shuffle: .on,
                        source: PlaybackSource(kind: .list, label: selected != nil ? "Gewählte Genres (gemischt)" : "Genres (gemischt)"))
        }
        return LibraryToolbar(context: .genres, style: .full, sort: model.settings.genreSort, setSort: { model.settings.genreSort = $0 },
                              shuffleLabel: "Titel der gewählten bzw. angezeigten Genres gemischt abspielen", shuffle: shuffle)
    }
}

struct GenreDetailView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    let genreKey: String

    var body: some View {
        if let genre = model.index.genreByKey[genreKey] {
            let tracks = Sorting.tracks(model.index.tracksOf(genre.trackUids), sort: model.settings.trackSort, stats: model.stats)
            let source = PlaybackSource(kind: .genre, label: genre.name, id: genre.key)
            let totalMs: Int64 = tracks.reduce(Int64(0)) { $0 + $1.durationMs }
            let prefix: String = genre.isUnknown ? "Titel ohne Genre-Angabe in den Tags · " : ""
            let meta: String = prefix + Formatting.tracks(tracks.count) + " · " + Formatting.longDuration(totalMs)
            let albums = genreAlbums(genre)
            LibraryScaffold(title: genre.name, onBack: { model.back() }, edgeToEdgeTop: true, actions: {
                BarAction(icon: Icons.play, label: "Abspielen") { player.play(uids: tracks.map(\.uid), startIndex: 0, shuffle: .off, source: source) }
                BarAction(icon: Icons.shuffle, label: "Mischen") { player.play(uids: tracks.map(\.uid), startIndex: nil, shuffle: .on, source: source) }
            }) {
                VStack(spacing: 0) {
                    DetailHeader(
                        backdrop: GenreStyle.artwork(genre.category),
                        tint: GenreStyle.tint(genre.category),
                        title: genre.name,
                        eyebrow: "Genre",
                        meta: meta,
                        artwork: {
                            GenreArtTile(category: genre.category, cornerRadius: Radius.artworkLarge, iconFraction: 0.5)
                                .frame(width: 200, height: 200)
                                .shadow(color: Color.black.opacity(0.25), radius: 20, y: 10)
                        },
                        buttons: {
                            PillButton(title: "Abspielen", icon: Icons.play, style: .filled, minWidth: 130) { player.play(uids: tracks.map(\.uid), startIndex: 0, shuffle: .off, source: source) }
                            PillButton(title: "Mischen", icon: Icons.shuffle, minWidth: 130) { player.play(uids: tracks.map(\.uid), startIndex: nil, shuffle: .on, source: source) }
                        }
                    )
                    VStack(alignment: .leading, spacing: 0) {
                        if !albums.isEmpty {
                            SectionTitle(text: "Alben")
                            AlbumShelf(albums: albums)
                            SectionTitle(text: "Titel")
                        }
                        TrackListView(items: TrackListItem.plain(tracks), config: TrackListConfig(source: source))
                    }
                    .padding(.horizontal, Spacing.gutter)
                }
            }
        } else {
            LibraryScaffold(title: "Genre", onBack: { model.back() }) {
                EmptyStateView(icon: "genres_nav", title: "Nicht verfügbar", text: "Zu diesem Genre gibt es derzeit keine Titel.")
            }
        }
    }

    /// Alben, deren häufigstes Genre dieses ist (höchstens 30, neueste zuerst).
    private func genreAlbums(_ genre: GenreInfo) -> [AlbumInfo] {
        guard !genre.isUnknown else { return [] }
        let matching = model.index.albums.filter { TextNorm.key($0.genre) == genre.key }
        return Array(matching.sorted { ($0.year ?? 0) > ($1.year ?? 0) }.prefix(30))
    }
}
