import SwiftUI
import AppKit
import MLCore

// Bereiche „Titel“, „Alben“, „Interpreten“, „Genres“ mit Detailansichten (Android: TracksScreen, AlbumsScreens,
// ArtistsGenresScreens). Auf dem Mac mit breiteren Rastern, Mehrfachauswahl und Kontextmenüs.

/// Gemeinsame Aktionen in der Titelkapsel: Sortierung und Einstellungen.
struct SortMenu<F: SortField>: View {
    @Environment(\.musicColors) private var colors
    let sort: Sort<F>
    let onChange: (Sort<F>) -> Void

    var body: some View {
        Menu {
            Text("SORTIEREN NACH")
            ForEach(Array(F.allCases), id: \.self) { field in
                Button {
                    onChange(field == sort.field ? Sort(field, descending: !sort.descending) : Sort(field, descending: field.defaultDescending))
                } label: {
                    if field == sort.field {
                        Label(field.label, systemImage: sort.descending ? "arrow.down" : "arrow.up")
                    } else {
                        Text(field.label)
                    }
                }
            }
            Divider()
            Button {
                onChange(Sort(sort.field, descending: false))
            } label: {
                if !sort.descending { Label("Aufsteigend · " + sort.field.ascendingLabel, systemImage: "checkmark") } else { Text("Aufsteigend · " + sort.field.ascendingLabel) }
            }
            Button {
                onChange(Sort(sort.field, descending: true))
            } label: {
                if sort.descending { Label("Absteigend · " + sort.field.descendingLabel, systemImage: "checkmark") } else { Text("Absteigend · " + sort.field.descendingLabel) }
            }
        } label: {
            Icon(Icons.sort, size: 17, color: colors.textPrimary)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sortierung: \(sort.label)")
    }
}

struct SettingsAction: View {
    var body: some View {
        BarAction(icon: Icons.settings, label: "Einstellungen (⌘,)") {
            if #available(macOS 14.0, *) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } else {
                NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            }
        }
    }
}

// MARK: - Titel

struct TracksView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService

    var body: some View {
        let tracks = model.trackList
        let q = model.query(.tracks)
        let source = PlaybackSource(kind: .list, label: q.trimmingCharacters(in: .whitespaces).isEmpty ? "Alle Titel" : "Suche „\(q.trimmingCharacters(in: .whitespaces))“")
        LibraryScaffold(title: "Titel", actions: { actions(tracks) }) {
            VStack(spacing: 0) {
                LargeTitleHeader(title: "Titel", section: .tracks, placeholder: "Titel, Interpret, Album oder Genre",
                                 summary: model.index.tracks.isEmpty ? nil : librarySummary(tracks.count, model.index.tracks.filter(\.available).count, searching: !q.isEmpty, Formatting.tracks),
                                 actions: { actions(tracks) })
                if model.index.tracks.isEmpty {
                    LibraryEmptyState()
                } else if tracks.isEmpty {
                    EmptyStateView(icon: Icons.search, title: "Keine Treffer", text: "Kein Titel passt zu „\(q)“. Gesucht wird in Titel, Interpret, Album und Genre.")
                } else {
                    TrackListView(items: TrackListItem.plain(tracks), config: TrackListConfig(source: source))
                }
            }
            .padding(.horizontal, Spacing.gutter)
        }
    }

    @ViewBuilder
    private func actions(_ tracks: [Track]) -> some View {
        if !tracks.isEmpty {
            BarAction(icon: Icons.shuffle, label: "Alle angezeigten Titel gemischt abspielen") {
                player.play(uids: tracks.map(\.uid), startIndex: nil, shuffle: .on, source: PlaybackSource(kind: .list, label: "Alle Titel (gemischt)"))
            }
        }
        SortMenu(sort: model.settings.trackSort) { model.settings.trackSort = $0 }
        BarAction(icon: Icons.difference, label: "Duplikate finden") { model.open(.duplicates) }
        SettingsAction()
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
        let q = model.query(.albums)
        LibraryScaffold(title: "Alben", actions: { actions(albums) }) {
            VStack(spacing: 0) {
                LargeTitleHeader(title: "Alben", section: .albums, placeholder: "Album, Album-Interpret, Interpret oder Genre",
                                 summary: model.index.albums.isEmpty ? nil : librarySummary(albums.count, model.index.albums.count, searching: !q.isEmpty, Formatting.albums),
                                 actions: { actions(albums) })
                if model.index.albums.isEmpty {
                    EmptyStateView(icon: Icons.album, title: "Keine Alben", text: "Sobald Musik gefunden wurde, erscheinen hier die Alben.")
                } else if albums.isEmpty {
                    EmptyStateView(icon: Icons.search, title: "Keine Treffer", text: "Kein Album passt zu „\(q)“.")
                } else {
                    AlbumGrid(albums: albums)
                }
            }
            .padding(.horizontal, Spacing.gutter)
        }
    }

    @ViewBuilder
    private func actions(_ albums: [AlbumInfo]) -> some View {
        if !albums.isEmpty {
            BarAction(icon: Icons.shuffle, label: "Alben gemischt abspielen") {
                let uids = albums.flatMap(\.trackUids)
                player.play(uids: uids, startIndex: nil, shuffle: .on, source: PlaybackSource(kind: .list, label: "Alle Alben (gemischt)"))
            }
        }
        SortMenu(sort: model.settings.albumSort) { model.settings.albumSort = $0 }
        SettingsAction()
    }
}

/// Raster der Alben (Android: GridCells.Adaptive) – auf dem Mac mehr Spalten.
struct AlbumGrid: View {
    let albums: [AlbumInfo]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.gridMinCell, maximum: 260), spacing: 22, alignment: .top)], spacing: 24) {
            ForEach(albums) { album in
                AlbumTile(album: album)
            }
        }
        .padding(.top, 8)
    }
}

struct AlbumTile: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    let album: AlbumInfo
    @State private var hover = false

    var body: some View {
        let cover = model.index.coverTrackOf(album)
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                TrackArtwork(track: cover, size: .medium, cornerRadius: Radius.artwork, iconFraction: 0.42)
                    .aspectRatio(1, contentMode: .fit)
                    .shadow(color: Color.black.opacity(hover ? 0.22 : 0.10), radius: hover ? 12 : 6, y: hover ? 6 : 3)
                if model.isAlbumFavorite(album.key) {
                    Circle()
                        .fill(Color.black.opacity(0.45))
                        .frame(width: 24, height: 24)
                        .overlay(Icon(Icons.favorite, size: 13, color: Color(argb: 0xFFFF8FA6)))
                        .padding(8)
                }
                if hover {
                    Button {
                        player.play(uids: album.trackUids, startIndex: 0, shuffle: .off, source: PlaybackSource(kind: .album, label: album.title ?? "Album", id: album.key))
                    } label: {
                        Icon(Icons.play, size: 18, color: colors.onAccent)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(colors.accent))
                            .shadow(color: Color.black.opacity(0.25), radius: 6, y: 3)
                    }
                    .buttonStyle(PressScaleStyle())
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .transition(.opacity)
                    .help("Album abspielen")
                }
            }
            .scaleEffect(hover ? 1.015 : 1)
            .animation(Motion.easeOut(Motion.short), value: hover)
            Text(album.title ?? "Unbekanntes Album")
                .textStyle(Typo.titleSmall)
                .foregroundColor(colors.textPrimary)
                .lineLimit(1)
                .padding(.top, 8)
            Text(album.isVarious ? "Verschiedene Interpreten" : (album.artist ?? "Unbekannter Interpret"))
                .textStyle(Typo.bodySmall)
                .foregroundColor(colors.textSecondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { model.open(.album(album.key)) }
        .onDrag { TrackDrag.provider(uids: album.trackUids, entryIds: []) }
        .contextMenu {
            Button("Album abspielen") {
                player.play(uids: album.trackUids, startIndex: 0, shuffle: .off, source: PlaybackSource(kind: .album, label: album.title ?? "Album", id: album.key))
            }
            Button("Album mischen") {
                player.play(uids: album.trackUids, startIndex: nil, shuffle: .on, source: PlaybackSource(kind: .album, label: album.title ?? "Album", id: album.key))
            }
            Button("Als Nächstes spielen") { player.playNext(uids: album.trackUids) }
            Button("Zur Warteschlange hinzufügen") { player.addToQueue(uids: album.trackUids) }
            Divider()
            Button(model.isAlbumFavorite(album.key) ? "Album aus Favoriten entfernen" : "Album zu Favoriten hinzufügen") { model.toggleAlbumFavorite(album) }
            Menu("Zu Playlist hinzufügen") {
                Button("Neue Playlist …") { NewPlaylistDialog.present(model: model, trackUids: album.trackUids, suggestedName: album.title) }
                ForEach(model.playlists) { p in Button(p.name) { model.addToPlaylist(p.id, trackUids: album.trackUids) } }
            }
            Divider()
            Button("Album öffnen") { model.open(.album(album.key)) }
            Button("Informationen zum Album …") { model.showInfo(album.trackUids) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
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
            LibraryScaffold(title: album.title ?? "Album", onBack: { model.back() }, edgeToEdgeTop: true, actions: {
                BarAction(icon: Icons.play, label: "Abspielen") { player.play(uids: album.trackUids, startIndex: 0, shuffle: .off, source: source) }
                BarAction(icon: Icons.shuffle, label: "Mischen") { player.play(uids: album.trackUids, startIndex: nil, shuffle: .on, source: source) }
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
                            PillButton(title: "Abspielen", icon: Icons.play, style: .filled, minWidth: 130) { player.play(uids: album.trackUids, startIndex: 0, shuffle: .off, source: source) }
                            PillButton(title: "Mischen", icon: Icons.shuffle, minWidth: 130) { player.play(uids: album.trackUids, startIndex: nil, shuffle: .on, source: source) }
                            GlassIconButton(icon: model.isAlbumFavorite(album.key) ? Icons.favorite : Icons.favoriteBorder,
                                            label: model.isAlbumFavorite(album.key) ? "Album aus Favoriten entfernen" : "Album zu Favoriten hinzufügen",
                                            tint: model.isAlbumFavorite(album.key) ? colors.heart : nil) { model.toggleAlbumFavorite(album) }
                            GlassIconButton(icon: Icons.edit, label: "Informationen zum Album bearbeiten") { model.showInfo(album.trackUids) }
                        }
                    )
                    VStack(spacing: 0) {
                        let ordered = tracks
                        if album.isMultiDisc {
                            ForEach(album.discNumbers, id: \.self) { disc in
                                ListLabel("Disc \(disc)")
                                TrackListView(items: TrackListItem.plain(ordered.filter { ($0.discNumber ?? 1) == disc }),
                                              config: TrackListConfig(showArtwork: false, showAlbum: false, numbering: .trackNumber, source: source))
                            }
                        } else {
                            TrackListView(items: TrackListItem.plain(ordered),
                                          config: TrackListConfig(showArtwork: false, showAlbum: false, numbering: .trackNumber, source: source))
                        }
                        if let year = album.year {
                            Text("\(year) · \(Formatting.tracks(album.trackCount)) · \(Formatting.longDuration(album.totalDurationMs))")
                                .textStyle(Typo.bodySmall)
                                .foregroundColor(colors.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 14)
                                .padding(.leading, 6)
                        }
                    }
                    .padding(.horizontal, Spacing.gutter)
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

// MARK: - Interpreten

struct ArtistsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService

    var body: some View {
        let artists = model.artistList
        let q = model.query(.artists)
        LibraryScaffold(title: "Interpreten", actions: { actions }) {
            VStack(spacing: 0) {
                LargeTitleHeader(title: "Interpreten", section: .artists, placeholder: "Interpret suchen",
                                 summary: model.index.artists.isEmpty ? nil : librarySummary(artists.count, model.index.artists.count, searching: !q.isEmpty, Formatting.artists),
                                 actions: { actions })
                if model.index.artists.isEmpty {
                    EmptyStateView(icon: "mic", title: "Keine Interpreten", text: "Titel ohne Interpret-Angabe erscheinen nur unter „Titel“ und „Alben“.")
                } else if artists.isEmpty {
                    EmptyStateView(icon: Icons.search, title: "Keine Treffer", text: "Kein Interpret passt zu „\(q)“.")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 18, alignment: .top)], spacing: 0) {
                        ForEach(artists) { artist in ArtistRow(artist: artist) }
                    }
                }
            }
            .padding(.horizontal, Spacing.gutter)
        }
    }

    @ViewBuilder private var actions: some View {
        SortMenu(sort: model.settings.artistSort) { model.settings.artistSort = $0 }
        SettingsAction()
    }
}

struct ArtistRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    let artist: ArtistInfo
    @State private var hover = false

    var body: some View {
        let cover = artist.trackUids.lazy.compactMap { model.index.trackByUid[$0] }.first { $0.hasPicture }
        let infoParts: [String?] = [Formatting.tracks(artist.trackCount), artist.albumKeys.isEmpty ? nil : Formatting.albums(artist.albumKeys.count)]
        let info: String = infoParts.compactMap { $0 }.joined(separator: " · ")
        HStack(spacing: 12) {
            if let cover {
                TrackArtwork(track: cover, size: .small, circle: true).frame(width: 46, height: 46)
            } else {
                Monogram(name: artist.name, size: 46)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(artist.name)
                    .textStyle(Typo.bodyLarge)
                    .fontWeight(.medium)
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                Text(info)
                    .textStyle(Typo.bodySmall)
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Icon(Icons.chevronRight, size: 17, color: colors.textTertiary.opacity(0.7))
                .padding(.trailing, 6)
        }
        .padding(.horizontal, 8)
        .frame(height: 62)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hover ? colors.textPrimary.opacity(0.04) : .clear))
        .overlay(alignment: .bottom) { Hairline(leading: 66) }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { model.open(.artist(artist.key)) }
        .contextMenu {
            Button("Alle Titel abspielen") { player.play(uids: artist.trackUids, startIndex: 0, shuffle: .off, source: PlaybackSource(kind: .artist, label: artist.name, id: artist.key)) }
            Button("Mischen") { player.play(uids: artist.trackUids, startIndex: nil, shuffle: .on, source: PlaybackSource(kind: .artist, label: artist.name, id: artist.key)) }
            Button("Als Nächstes spielen") { player.playNext(uids: artist.trackUids) }
            Button("Zur Warteschlange hinzufügen") { player.addToQueue(uids: artist.trackUids) }
        }
        .onDrag { TrackDrag.provider(uids: artist.trackUids, entryIds: []) }
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
            let albums = artist.albumKeys.compactMap { model.index.albumByKey[$0] }
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
                            SectionTitle(text: "Alben")
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 20) {
                                    ForEach(albums) { album in AlbumTile(album: album).frame(width: 176) }
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 2)
                            }
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
    @Environment(\.musicColors) private var colors

    var body: some View {
        let genres = model.genreList
        let q = model.query(.genres)
        LibraryScaffold(title: "Genres", actions: { actions }) {
            VStack(spacing: 0) {
                LargeTitleHeader(title: "Genres", section: .genres, placeholder: "Genre suchen",
                                 summary: model.index.genres.isEmpty ? nil : librarySummary(genres.count, model.index.genres.count, searching: !q.isEmpty, Formatting.genres),
                                 actions: { actions })
                if model.index.genres.isEmpty {
                    EmptyStateView(icon: "genres_nav", title: "Keine Genres", text: "Sobald Musik gefunden wurde, erscheinen hier die Genres aus den Tags.")
                } else if genres.isEmpty {
                    EmptyStateView(icon: Icons.search, title: "Keine Treffer", text: "Kein Genre passt zu „\(q)“.")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 300), spacing: 16, alignment: .top)], spacing: 16) {
                        ForEach(genres) { genre in GenreTile(genre: genre) }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, Spacing.gutter)
        }
    }

    @ViewBuilder private var actions: some View {
        SortMenu(sort: model.settings.genreSort) { model.settings.genreSort = $0 }
        SettingsAction()
    }
}

/// Genre-Kachel (Android: Kachel mit Verlauf/Titelbild, Name und Anzahl).
struct GenreTile: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    let genre: GenreInfo
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            GenreArtTile(category: genre.category, cornerRadius: 12, iconFraction: 0.56)
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 1) {
                Text(genre.name)
                    .textStyle(Typo.titleSmall)
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                Text(Formatting.tracks(genre.trackCount))
                    .textStyle(Typo.bodySmall)
                    .foregroundColor(colors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.card, style: .continuous), tint: hover ? colors.accentSoft : nil)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { model.open(.genre(genre.key)) }
        .contextMenu {
            Button("Abspielen") { player.play(uids: genre.trackUids, startIndex: 0, shuffle: .off, source: PlaybackSource(kind: .genre, label: genre.name, id: genre.key)) }
            Button("Mischen") { player.play(uids: genre.trackUids, startIndex: nil, shuffle: .on, source: PlaybackSource(kind: .genre, label: genre.name, id: genre.key)) }
        }
        .onDrag { TrackDrag.provider(uids: genre.trackUids, entryIds: []) }
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
                    TrackListView(items: TrackListItem.plain(tracks), config: TrackListConfig(source: source))
                        .padding(.horizontal, Spacing.gutter)
                }
            }
        } else {
            LibraryScaffold(title: "Genre", onBack: { model.back() }) {
                EmptyStateView(icon: "genres_nav", title: "Nicht verfügbar", text: "Zu diesem Genre gibt es derzeit keine Titel.")
            }
        }
    }
}
