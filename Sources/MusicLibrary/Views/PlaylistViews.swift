import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MLCore

// Bereich „Playlists“ (Android: PlaylistsScreens): automatische Playlists (Favoriten, Zuletzt hinzugefügt,
// Zuletzt gespielt, Meistgespielt, Am wenigsten/Nie gespielt, Am besten bewertet, Jahrzehnte, Genres), eigene
// Playlists mit Drag & Drop, Verlauf. v2: alle fünf Ansichten, sichtbare Sortierung.

extension SmartKind {
    var icon: String {
        switch self {
        case .favorites: return Icons.favorite
        case .mostPlayed: return Icons.trending
        case .leastPlayed: return Icons.history
        case .decade: return Icons.vinyl
        case .recentlyAdded: return LibIcon.newReleases
        case .recentlyPlayed: return LibIcon.schedule
        case .neverPlayed: return LibIcon.discover
        case .genre: return LibIcon.category
        case .topRated: return Icons.starFill
        }
    }

    var tintARGB: UInt32 {
        switch self {
        case .favorites: return 0xFFD4566F
        case .mostPlayed: return 0xFF8C5F9E
        case .leastPlayed: return 0xFF5E7DB0
        case .decade: return 0xFFC99A45
        case .recentlyAdded: return 0xFF4F9592
        case .recentlyPlayed: return 0xFF7E9F78
        case .neverPlayed: return 0xFF6E6869
        case .genre: return 0xFFB27390
        case .topRated: return 0xFFD9765F
        }
    }

    var tint: Color { Color(argb: tintARGB) }

    var emptyText: String {
        switch self {
        case .favorites: return "Klicke bei einem Titel auf das Herz – er erscheint dann automatisch hier."
        case .mostPlayed, .recentlyPlayed: return "Sobald Titel gespielt wurden, erscheinen sie hier."
        case .topRated: return "Bewerte Titel (z. B. im Informationsfenster) mit vier oder fünf Sternen – sie erscheinen dann hier."
        case .neverPlayed: return "Du hast bereits alle Titel mindestens einmal gehört."
        case .recentlyAdded: return "In den letzten Wochen wurden keine Titel hinzugefügt."
        case .leastPlayed, .decade, .genre: return "Für diese automatische Playlist gibt es derzeit keine Titel."
        }
    }

    /// Gruppen in der Übersicht.
    var isDecade: Bool { self == .decade }
    var isGenre: Bool { self == .genre }
}

/// Symbol und Farbe einer automatischen Playlist (Genre-Playlists in den Farben ihrer Genre-Familie).
enum SmartArt {
    static func icon(_ smart: SmartPlaylist, index: LibraryIndex) -> String {
        if smart.kind == .genre, let key = smart.genreKey, let genre = index.genreByKey[key] { return GenreStyle.icon(genre.category) }
        return smart.kind.icon
    }

    static func argb(_ smart: SmartPlaylist, index: LibraryIndex) -> UInt32 {
        if smart.kind == .genre, let key = smart.genreKey, let genre = index.genreByKey[key] { return GenrePalette.forCategory(genre.category) }
        return smart.kind.tintARGB
    }

    /// Zusatzangabe rechts in der Titelliste der automatischen Playlist.
    static func trailing(_ kind: SmartKind, stats: [Int64: PlayStats]) -> ((Track) -> String?)? {
        switch kind {
        case .mostPlayed, .leastPlayed:
            return { t in "\(stats[t.uid]?.playCount ?? 0)×" }
        case .recentlyPlayed:
            return { t in LibraryFormat.date(ms: stats[t.uid]?.lastPlayedAt) }
        case .recentlyAdded:
            return { t in LibraryFormat.date(seconds: t.dateAdded) }
        case .topRated:
            return { t in LibraryFormat.stars(t.rating) }
        case .favorites, .neverPlayed, .decade, .genre:
            return nil
        }
    }
}

// MARK: - Übersicht

/// Eintrag der Playlist-Übersicht.
enum PlaylistElement: Identifiable {
    case smart(SmartPlaylist)
    case own(Playlist)
    case history(count: Int)
    case create

    var id: String {
        switch self {
        case .smart(let smart): return smart.id
        case .own(let playlist): return "p:\(playlist.id)"
        case .history: return PlaylistElement.historyID
        case .create: return PlaylistElement.createID
        }
    }

    var isCreate: Bool {
        if case .create = self { return true }
        return false
    }

    static let historyID = "verlauf"
    static let createID = "neu"

    /// Kennung einer eigenen Playlist aus der Eintragskennung („p:12“ → 12).
    static func playlistID(_ id: String) -> Int64? {
        guard id.hasPrefix("p:") else { return nil }
        return Int64(id.dropFirst(2))
    }
}

struct PlaylistGroup: Identifiable {
    let id: String
    let title: String
    let elements: [PlaylistElement]
    /// Spaltenköpfe sortieren (nur eigene Playlists).
    let sortable: Bool
}

struct PlaylistsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService

    var body: some View {
        let q = model.query(.playlists).trimmingCharacters(in: .whitespaces)
        let groups = makeGroups(searching: !q.isEmpty)
        let shown: Int = model.smartPlaylists.count + model.playlistList.count
        let total: Int = model.unfilteredCount[.playlists] ?? (model.playlists.count + model.smartPlaylists.count)
        let summary: String = librarySummary(shown, total, narrowed: !q.isEmpty, Formatting.playlists)
        LibraryScaffold(title: "Playlists", actions: { toolbar(.collapsed) }) {
            VStack(spacing: 0) {
                LargeTitleHeader(title: "Playlists", section: .playlists, placeholder: "Playlist suchen",
                                 summary: summary, toolbar: { toolbar(.full) })
                if groups.isEmpty {
                    NoMatchesView(context: .playlists, query: q, noun: "Keine Playlist")
                } else {
                    PlaylistCollections(groups: groups, sort: sortSpec)
                }
                if model.playlists.isEmpty && q.isEmpty {
                    EmptyStateView(icon: Icons.playlistAdd, title: "Noch keine eigenen Playlists",
                                   text: "Lege eine Playlist an und ziehe Titel, Alben oder Interpreten einfach darauf – oder nutze im Kontextmenü „Zu Playlist hinzufügen“.")
                }
            }
            .padding(.horizontal, Spacing.gutter)
        }
    }

    private func makeGroups(searching: Bool) -> [PlaylistGroup] {
        let smart = model.smartPlaylists
        let baseSmart: [PlaylistElement] = smart.filter { !$0.kind.isDecade && !$0.kind.isGenre }.map { PlaylistElement.smart($0) }
        let history: [PlaylistElement] = searching ? [] : [PlaylistElement.history(count: model.history.count)]
        let decades: [PlaylistElement] = smart.filter { $0.kind.isDecade }.map { PlaylistElement.smart($0) }
        let genres: [PlaylistElement] = smart.filter { $0.kind.isGenre }.map { PlaylistElement.smart($0) }
        let create: [PlaylistElement] = searching ? [] : [PlaylistElement.create]
        let own: [PlaylistElement] = model.playlistList.map { PlaylistElement.own($0) }
        let all: [PlaylistGroup] = [
            PlaylistGroup(id: "auto", title: "Automatisch", elements: baseSmart + history, sortable: false),
            PlaylistGroup(id: "jahrzehnte", title: "Jahrzehnte", elements: decades, sortable: false),
            PlaylistGroup(id: "genres", title: "Nach Genre", elements: genres, sortable: false),
            PlaylistGroup(id: "eigene", title: "Meine Playlists", elements: create + own, sortable: true),
        ]
        return all.filter { !$0.elements.isEmpty }
    }

    private var sortSpec: TableSortSpec {
        ColumnSorts.spec(ColumnSorts.playlist, sort: model.settings.playlistSort) { model.settings.playlistSort = $0 }
    }

    private func toolbar(_ style: LibraryToolbarStyle) -> some View {
        let ownUids: [Int64] = ArtistsView.union(model.playlistList.map { $0.entries.map(\.trackUid) })
        let shuffle: (() -> Void)? = ownUids.isEmpty ? nil : {
            player.play(uids: ownUids, startIndex: nil, shuffle: .on, source: PlaybackSource(kind: .list, label: "Alle eigenen Playlists (gemischt)"))
        }
        return LibraryToolbar(context: .playlists, style: style, sort: model.settings.playlistSort, setSort: { model.settings.playlistSort = $0 },
                              shuffleLabel: "Titel aller eigenen Playlists gemischt abspielen", shuffle: shuffle) {
            BarAction(icon: Icons.add, label: "Neue Playlist (⌘N)") { NewPlaylistDialog.present(model: model, trackUids: []) }
        }
    }
}

/// Gruppen der Übersicht in der gewählten Ansicht (Cover Flow zeigt alle Playlists in einer Reihe).
struct PlaylistCollections: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    let groups: [PlaylistGroup]
    let sort: TableSortSpec

    var body: some View {
        LibraryModeHost(context: .playlists) { options in
            if options.mode == .coverFlow {
                let all: [PlaylistElement] = groups.flatMap { $0.elements }.filter { !$0.isCreate }
                collection(all, options: options, sortable: false)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { group in
                        ListLabel(group.title)
                        collection(group.elements, options: options, sortable: group.sortable)
                    }
                }
            }
        }
    }

    private func collection(_ elements: [PlaylistElement], options: LibraryViewOptions, sortable: Bool) -> some View {
        let spec: TableSortSpec = sortable ? sort : TableSortSpec.unsorted
        let index = model.index
        let stats = model.stats
        let historyUids = PlaylistItems.historyUids(model.history)
        return LibraryCollection(
            context: .playlists,
            elements: elements,
            options: options,
            makeItem: { (element: PlaylistElement) -> LibraryItem in PlaylistItems.item(element, model: model, historyUids: historyUids) },
            actions: PlaylistItems.actions(model: model, player: player),
            table: CollectionTable(sort: spec, cell: { (element: PlaylistElement, column: DetailColumn) -> String in
                PlaylistItems.cell(element, column, index: index, stats: stats)
            }),
            menu: { (item: LibraryItem, uids: [Int64]) in PlaylistMenuItems(itemID: item.id, title: item.title, uids: uids) }
        )
    }
}

@MainActor
enum PlaylistItems {
    static func historyUids(_ history: [HistoryEntry]) -> [Int64] {
        var seen = Set<Int64>()
        var out: [Int64] = []
        for entry in history where seen.insert(entry.trackUid).inserted { out.append(entry.trackUid) }
        return out
    }

    static func item(_ element: PlaylistElement, model: AppModel, historyUids: [Int64]) -> LibraryItem {
        switch element {
        case .smart(let smart):
            return LibraryItem(
                id: smart.id,
                title: smart.name,
                subtitle: Formatting.tracks(smart.trackUids.count),
                detail: smart.description,
                art: .gradient(icon: SmartArt.icon(smart, index: model.index), argb: SmartArt.argb(smart, index: model.index)),
                automatic: true,
                trackUids: smart.trackUids
            )
        case .own(let playlist):
            let tracks = model.tracks(playlist.entries.map(\.trackUid))
            let totalMs: Int64 = tracks.reduce(Int64(0)) { $0 + $1.durationMs }
            return LibraryItem(
                id: element.id,
                title: playlist.name,
                subtitle: Formatting.tracks(playlist.entries.count) + " · " + Formatting.longDuration(totalMs),
                detail: "Erstellt am " + LibraryFormat.date(ms: playlist.createdAt),
                art: .mosaic(Array(tracks.prefix(32))),
                trackUids: playlist.entries.map(\.trackUid),
                acceptsDrop: true
            )
        case .history(let count):
            return LibraryItem(
                id: element.id,
                title: "Verlauf",
                subtitle: count == 0 ? "Noch nichts gespielt" : "Zuletzt gespielt · \(Formatting.integer(count)) Einträge",
                detail: "Wann welcher Titel lief",
                art: .gradient(icon: Icons.history, argb: 0xFF4F9592),
                automatic: true,
                trackUids: historyUids
            )
        case .create:
            return LibraryItem(
                id: element.id,
                title: "Neue Playlist …",
                subtitle: "Titel hierher ziehen",
                art: .add,
                acceptsDrop: true
            )
        }
    }

    static func cell(_ element: PlaylistElement, _ column: DetailColumn, index: LibraryIndex, stats: [Int64: PlayStats]) -> String {
        switch element {
        case .own(let p):
            let facts = GroupFacts(title: p.name, uids: p.entries.map(\.trackUid), trackCount: p.entries.count,
                                   dateAddedSeconds: p.createdAt / 1000, modifiedMs: p.updatedAt)
            return CollectionCells.value(facts, column, index: index, stats: stats)
        case .smart(let s):
            let facts = GroupFacts(title: s.name, uids: s.trackUids, trackCount: s.trackUids.count)
            return CollectionCells.value(facts, column, index: index, stats: stats)
        case .history(let count):
            if column == .title { return "Verlauf" }
            if column == .trackCount { return Formatting.integer(count) }
            return "–"
        case .create:
            return column == .title ? "Neue Playlist …" : ""
        }
    }

    static func source(_ item: LibraryItem) -> PlaybackSource {
        if let pid = PlaylistElement.playlistID(item.id) { return PlaybackSource(kind: .playlist, label: item.title, id: String(pid)) }
        if item.id == PlaylistElement.historyID { return PlaybackSource(kind: .list, label: "Verlauf") }
        return PlaybackSource(kind: .smartPlaylist, label: item.title, id: item.id)
    }

    static func actions(model: AppModel, player: PlayerService) -> CollectionActions {
        CollectionActions(
            open: { item in
                if let pid = PlaylistElement.playlistID(item.id) {
                    model.open(.playlist(pid))
                } else if item.id == PlaylistElement.historyID {
                    model.open(.history)
                } else if item.id == PlaylistElement.createID {
                    NewPlaylistDialog.present(model: model, trackUids: [])
                } else {
                    model.open(.smartPlaylist(item.id))
                }
            },
            play: { item, shuffle in
                guard !item.trackUids.isEmpty else { return }
                player.play(uids: item.trackUids, startIndex: shuffle ? nil : 0, shuffle: shuffle ? .on : .off, source: source(item))
            },
            drop: { item, uids in
                guard !uids.isEmpty else { return }
                if let pid = PlaylistElement.playlistID(item.id) {
                    model.addToPlaylist(pid, trackUids: uids)
                } else if item.id == PlaylistElement.createID {
                    NewPlaylistDialog.present(model: model, trackUids: uids)
                }
            },
            openLabel: "Öffnen"
        )
    }
}

/// Kontextmenü eines Eintrags der Playlist-Übersicht.
struct PlaylistMenuItems: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    let itemID: String
    let title: String
    let uids: [Int64]

    var body: some View {
        if itemID == PlaylistElement.createID {
            Button("Neue Playlist …") { NewPlaylistDialog.present(model: model, trackUids: []) }
        } else {
            let pid = PlaylistElement.playlistID(itemID)
            let playlist = pid.flatMap { model.playlist($0) }
            let single = uidsMatch(playlist)
            let source = single ? PlaylistItems.source(LibraryItem(id: itemID, title: title, art: .add)) : PlaybackSource(kind: .list, label: "Auswahl")
            GroupMenuItems(uids: uids, source: source, suggestedName: single ? title : nil)
            if let playlist, single {
                Divider()
                Button("Öffnen") { model.open(.playlist(playlist.id)) }
                Button("Umbenennen …") { RenamePlaylistDialog.present(model: model, playlist: playlist) }
                Button("Duplizieren") { model.duplicatePlaylist(playlist.id) }
                Divider()
                Button("Playlist löschen …") { DeletePlaylistDialog.present(model: model, playlist: playlist) }
            } else if single, itemID == PlaylistElement.historyID {
                Divider()
                Button("Verlauf öffnen") { model.open(.history) }
            } else if single, let smart = model.smartPlaylist(itemID) {
                Divider()
                Button("Öffnen") { model.open(.smartPlaylist(smart.id)) }
                Button("Als Playlist sichern") {
                    model.createPlaylist(name: model.uniquePlaylistName(smart.name), trackUids: smart.trackUids, open: true)
                }
                .disabled(smart.trackUids.isEmpty)
            }
        }
    }

    /// Wirkt das Menü nur auf diesen Eintrag (nicht auf eine Mehrfachauswahl)?
    private func uidsMatch(_ playlist: Playlist?) -> Bool {
        if let playlist { return playlist.entries.map(\.trackUid) == uids }
        if itemID == PlaylistElement.historyID { return PlaylistItems.historyUids(model.history) == uids }
        if let smart = model.smartPlaylist(itemID) { return smart.trackUids == uids }
        return false
    }
}

/// Zeile einer Playlist (Android `PlaylistRow`): Artwork, Name, Untertitel, Hinweis „automatisch“, Pfeil –
/// verwendet im Blatt „Zu Playlist hinzufügen“.
struct PlaylistRow<Art: View>: View {
    @Environment(\.musicColors) private var colors
    let name: String
    let subtitle: String?
    let automatic: Bool
    var accentName: Bool = false
    var dropTargeted: Bool = false
    @ViewBuilder var artwork: () -> Art
    let open: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 14) {
            artwork()
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: Radius.artworkSmall, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(name)
                        .textStyle(Typo.bodyLarge)
                        .fontWeight(.medium)
                        .foregroundColor(accentName ? colors.accentText : colors.textPrimary)
                        .lineLimit(1)
                    if automatic { Icon(Icons.autoAwesome, size: 12, color: colors.accent) }
                }
                if let subtitle {
                    Text(subtitle)
                        .textStyle(Typo.bodySmall)
                        .foregroundColor(colors.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Icon(Icons.chevronRight, size: 17, color: colors.textTertiary.opacity(0.7)).padding(.trailing, 6)
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 64)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(dropTargeted ? colors.accentSoft : (hover ? colors.textPrimary.opacity(0.04) : .clear)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(dropTargeted ? colors.accent : .clear, lineWidth: 1.5))
        .overlay(alignment: .bottom) { Hairline(leading: 70) }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: open)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Eigene Playlist

struct PlaylistDetailView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    let playlistID: Int64
    @State private var backdrop: NSImage?
    @State private var targeted = false

    var body: some View {
        if let playlist = model.playlist(playlistID) {
            let items: [TrackListItem] = playlist.entries.compactMap { e in
                model.index.trackByUid[e.trackUid].map { TrackListItem(id: e.entryId, track: $0, entryId: e.entryId) }
            }
            let tracks = items.map(\.track)
            let source = PlaybackSource(kind: .playlist, label: playlist.name, id: String(playlist.id))
            let cover = tracks.first { $0.hasPicture }
            let totalMs: Int64 = tracks.reduce(Int64(0)) { $0 + $1.durationMs }
            let missing: Int = playlist.entries.count - items.count
            let missingText: String = missing > 0 ? " · \(missing) nicht verfügbar" : ""
            let meta: String = Formatting.tracks(items.count) + " · " + Formatting.longDuration(totalMs) + missingText
            LibraryScaffold(title: playlist.name, onBack: { model.back() }, edgeToEdgeTop: true, actions: {
                BarAction(icon: Icons.play, label: "Abspielen") { player.play(uids: tracks.map(\.uid), startIndex: 0, shuffle: .off, source: source) }
                BarAction(icon: Icons.shuffle, label: "Mischen") { player.play(uids: tracks.map(\.uid), startIndex: nil, shuffle: .on, source: source) }
            }) {
                VStack(spacing: 0) {
                    DetailHeader(
                        backdrop: backdrop,
                        tint: Color(argb: 0xFFB27390),
                        title: playlist.name,
                        eyebrow: "Playlist",
                        meta: meta,
                        artwork: {
                            MosaicArtwork(tracks: tracks, cornerRadius: Radius.artworkLarge, size: .medium)
                                .frame(width: 220, height: 220)
                                .shadow(color: Color.black.opacity(0.26), radius: 20, y: 10)
                        },
                        buttons: {
                            PillButton(title: "Abspielen", icon: Icons.play, style: .filled, minWidth: 130) { player.play(uids: tracks.map(\.uid), startIndex: 0, shuffle: .off, source: source) }
                                .disabled(tracks.isEmpty)
                            PillButton(title: "Mischen", icon: Icons.shuffle, minWidth: 130) { player.play(uids: tracks.map(\.uid), startIndex: nil, shuffle: .on, source: source) }
                                .disabled(tracks.isEmpty)
                            moreMenu(playlist)
                        }
                    )
                    VStack(spacing: 0) {
                        if items.isEmpty {
                            EmptyStateView(icon: Icons.playlistAdd, title: "Noch leer",
                                           text: "Ziehe Titel, Alben oder Interpreten hierher – oder nutze im Kontextmenü „Zu Playlist hinzufügen“.")
                                .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                    .strokeBorder(targeted ? colors.accent : colors.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                                .onDrop(of: [UTType.plainText], isTargeted: $targeted) { providers in
                                    TrackDrag.load(providers) { uids, _ in model.addToPlaylist(playlist.id, trackUids: uids) }
                                    return true
                                }
                        } else {
                            TrackListView(items: items, config: TrackListConfig(numbering: .none, playlistID: playlist.id, source: source))
                            // Ablage ans Ende
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(targeted ? colors.accentSoft : .clear)
                                .frame(height: 36)
                                .overlay(Text(targeted ? "Hier ablegen" : "").textStyle(Typo.labelMedium).foregroundColor(colors.accentText))
                                .onDrop(of: [UTType.plainText], isTargeted: $targeted) { providers in
                                    TrackDrag.load(providers) { uids, entryIds in
                                        let own = Set(items.compactMap(\.entryId))
                                        if !entryIds.isEmpty && entryIds.allSatisfy({ own.contains($0) }) {
                                            model.movePlaylistEntries(playlist.id, entryIds: entryIds, to: items.count)
                                        } else {
                                            model.addToPlaylist(playlist.id, trackUids: uids)
                                        }
                                    }
                                    return true
                                }
                        }
                    }
                    .padding(.horizontal, Spacing.gutter)
                }
            }
            .task(id: cover?.coverKey) { if let cover { backdrop = await ArtworkStore.shared.image(for: cover, size: .medium) } }
        } else {
            LibraryScaffold(title: "Playlist", onBack: { model.back() }) {
                EmptyStateView(icon: Icons.queue, title: "Playlist nicht gefunden", text: "Diese Playlist wurde gelöscht.")
            }
        }
    }

    /// „Weitere Aktionen“ als Glas-Menü (ein `Menu` mit eigener Beschriftung bliebe auf macOS unsichtbar).
    private func moreMenu(_ playlist: Playlist) -> some View {
        GlassMenuButton(help: "Weitere Aktionen", width: 250, label: {
            Icon(Icons.moreHoriz, size: 18, color: colors.textPrimary)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
                .glassSurface(Circle(), interactive: true)
        }) { menu in
            GlassMenuItem(title: "Umbenennen …", icon: Icons.edit) {
                menu.close()
                DispatchQueue.main.async { RenamePlaylistDialog.present(model: model, playlist: playlist) }
            }
            GlassMenuItem(title: "Duplizieren", icon: Icons.copy) {
                model.duplicatePlaylist(playlist.id)
                menu.close()
            }
            GlassMenuDisclosure(title: "Reihenfolge festlegen nach", icon: LibIcon.sort) {
                GlassMenuItem(title: "Titel") { reorder(playlist, by: Sort(.title, descending: false)); menu.close() }
                GlassMenuItem(title: "Interpret") { reorder(playlist, by: Sort(.artist, descending: false)); menu.close() }
                GlassMenuItem(title: "Album") { reorder(playlist, by: Sort(.album, descending: false)); menu.close() }
                GlassMenuItem(title: "Jahr") { reorder(playlist, by: Sort(.year, descending: false)); menu.close() }
                GlassMenuItem(title: "Dauer") { reorder(playlist, by: Sort(.duration, descending: false)); menu.close() }
                GlassMenuItem(title: "Meistgespielt") { reorder(playlist, by: Sort(.playCount, descending: true)); menu.close() }
                GlassMenuItem(title: "Zuletzt hinzugefügt") { reorder(playlist, by: Sort(.dateAdded, descending: true)); menu.close() }
            }
            GlassMenuDivider()
            GlassMenuItem(title: "Playlist löschen …", icon: Icons.delete, destructive: true) {
                menu.close()
                DispatchQueue.main.async { DeletePlaylistDialog.present(model: model, playlist: playlist) }
            }
        }
    }

    private func reorder(_ playlist: Playlist, by sort: Sort<TrackSort>) {
        let byUid = Dictionary(grouping: playlist.entries, by: \.trackUid)
        let sorted = Sorting.tracks(model.tracks(playlist.entries.map(\.trackUid)), sort: sort, stats: model.stats)
        var used = Set<Int64>()
        var order: [Int64] = []
        for t in sorted {
            for e in byUid[t.uid] ?? [] where !used.contains(e.entryId) {
                used.insert(e.entryId)
                order.append(e.entryId)
            }
        }
        model.setPlaylistOrder(playlist.id, entryIds: order)
    }
}

// MARK: - Automatische Playlist

struct SmartPlaylistDetailView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    let smartID: String

    var body: some View {
        if let smart = model.smartPlaylist(smartID) {
            let tracks = model.tracks(smart.trackUids)
            let source = PlaybackSource(kind: .smartPlaylist, label: smart.name, id: smart.id)
            let totalMs: Int64 = tracks.reduce(Int64(0)) { $0 + $1.durationMs }
            let meta: String = smart.description + " · " + Formatting.tracks(tracks.count) + " · " + Formatting.longDuration(totalMs)
            let tint = Color(argb: SmartArt.argb(smart, index: model.index))
            let icon = SmartArt.icon(smart, index: model.index)
            LibraryScaffold(title: smart.name, onBack: { model.back() }, edgeToEdgeTop: true, actions: {
                BarAction(icon: Icons.play, label: "Abspielen") { player.play(uids: smart.trackUids, startIndex: 0, shuffle: .off, source: source) }
                BarAction(icon: Icons.shuffle, label: "Mischen") { player.play(uids: smart.trackUids, startIndex: nil, shuffle: .on, source: source) }
            }) {
                VStack(spacing: 0) {
                    DetailHeader(
                        backdrop: nil,
                        tint: tint,
                        title: smart.name,
                        eyebrow: "Automatische Playlist",
                        meta: meta,
                        artwork: {
                            GradientTile(icon: icon, base: tint, cornerRadius: Radius.artworkLarge, iconFraction: 0.44)
                                .frame(width: 200, height: 200)
                                .shadow(color: Color.black.opacity(0.25), radius: 20, y: 10)
                        },
                        buttons: {
                            PillButton(title: "Abspielen", icon: Icons.play, style: .filled, minWidth: 130) { player.play(uids: smart.trackUids, startIndex: 0, shuffle: .off, source: source) }
                                .disabled(tracks.isEmpty)
                            PillButton(title: "Mischen", icon: Icons.shuffle, minWidth: 130) { player.play(uids: smart.trackUids, startIndex: nil, shuffle: .on, source: source) }
                                .disabled(tracks.isEmpty)
                            PillButton(title: "Als Playlist sichern", icon: Icons.playlistAdd) {
                                model.createPlaylist(name: model.uniquePlaylistName(smart.name), trackUids: smart.trackUids, open: true)
                            }
                            .disabled(tracks.isEmpty)
                        }
                    )
                    Group {
                        if tracks.isEmpty {
                            EmptyStateView(icon: Icons.queue, title: "Leer", text: smart.kind.emptyText)
                        } else {
                            TrackListView(items: TrackListItem.plain(tracks), config: TrackListConfig(
                                numbering: .none, source: source,
                                trailingText: SmartArt.trailing(smart.kind, stats: model.stats)
                            ))
                        }
                    }
                    .padding(.horizontal, Spacing.gutter)
                }
            }
        } else {
            LibraryScaffold(title: "Playlist", onBack: { model.back() }) {
                EmptyStateView(icon: Icons.queue, title: "Leer", text: "Für diese automatische Playlist gibt es derzeit keine Titel.")
            }
        }
    }
}

// MARK: - Verlauf

/// Wiedergabeverlauf (neu gegenüber Android): wann welcher Titel gespielt wurde.
struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors

    var body: some View {
        let entries = model.history.filter { model.index.trackByUid[$0.trackUid] != nil }
        let groups = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: Date(timeIntervalSince1970: Double($0.playedAt) / 1000)) }
        let days = groups.keys.sorted(by: >)
        LibraryScaffold(title: "Verlauf", onBack: { model.back() }, actions: {
            BarAction(icon: Icons.delete, label: "Verlauf löschen") { model.clearHistory() }
        }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Verlauf")
                        .textStyle(Typo.headlineLarge)
                        .foregroundColor(colors.textPrimary)
                    Spacer()
                    if !entries.isEmpty {
                        PillButton(title: "Abspielen", icon: Icons.play) {
                            player.play(uids: PlaylistItems.historyUids(entries), startIndex: 0, shuffle: .off, source: PlaybackSource(kind: .list, label: "Verlauf"))
                        }
                        PillButton(title: "Verlauf löschen", icon: Icons.delete) { model.clearHistory() }
                    }
                }
                .padding(.horizontal, 4)
                Text("Gespeichert wird nur auf diesem Mac. Gezählte Wiedergaben erscheinen auch in „Meistgespielt“.")
                    .textStyle(Typo.labelMedium)
                    .foregroundColor(colors.textTertiary)
                    .padding(.top, 8)
                    .padding(.leading, 6)
                if entries.isEmpty {
                    EmptyStateView(icon: Icons.history, title: "Noch nichts gespielt", text: "Sobald du Musik hörst, erscheint hier, wann welcher Titel lief.")
                } else {
                    ForEach(days, id: \.self) { day in
                        ListLabel(dayLabel(day))
                        let dayEntries = groups[day] ?? []
                        LazyVStack(spacing: 0) {
                            ForEach(dayEntries) { entry in
                                if let track = model.index.trackByUid[entry.trackUid] {
                                    HistoryRow(entry: entry, track: track)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.gutter)
        }
    }

    private func dayLabel(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Heute" }
        if Calendar.current.isDateInYesterday(day) { return "Gestern" }
        return Self.dayFormatter.string(from: day)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE, d. MMMM yyyy"
        return f
    }()
}

private struct HistoryRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    let entry: HistoryEntry
    let track: Track
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            Text(Self.time.string(from: Date(timeIntervalSince1970: Double(entry.playedAt) / 1000)))
                .textStyle(Typo.time)
                .monospacedDigit()
                .foregroundColor(colors.textTertiary)
                .frame(width: 44, alignment: .leading)
            TrackArtwork(track: track, size: .small).frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.displayTitle).textStyle(Typo.bodyLarge).foregroundColor(colors.textPrimary).lineLimit(1)
                Text(track.artistText ?? "Unbekannter Interpret").textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).lineLimit(1)
            }
            Spacer()
            Text(entry.counted ? "gezählt" : "angespielt · \(Formatting.duration(entry.listenedMs))")
                .textStyle(Typo.labelSmall)
                .foregroundColor(entry.counted ? colors.accentText : colors.textTertiary)
        }
        .padding(.horizontal, 6)
        .frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover ? colors.textPrimary.opacity(0.04) : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture {
            if NSApp.currentEvent?.clickCount ?? 1 >= 2 {
                player.play(uids: [track.uid], startIndex: 0, shuffle: .off, source: PlaybackSource(kind: .singleTrack, label: track.displayTitle))
            }
        }
        .onDrag { TrackDrag.provider(uids: [track.uid], entryIds: []) }
        .contextMenu {
            TrackMenuItems(uids: [track.uid], single: track, playAction: {
                player.play(uids: [track.uid], startIndex: 0, shuffle: .off, source: PlaybackSource(kind: .singleTrack, label: track.displayTitle))
            })
            Divider()
            Button("Aus dem Verlauf entfernen") { model.removeHistory([entry.id]) }
        }
    }

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
