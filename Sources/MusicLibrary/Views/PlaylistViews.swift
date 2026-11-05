import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MLCore

// Bereich „Playlists“ (Android: PlaylistsScreens): automatische Playlists (Favoriten, Meistgespielt,
// Am wenigsten gespielt, Jahrzehnte), eigene Playlists mit Drag & Drop, Verlauf.

extension SmartKind {
    var icon: String {
        switch self {
        case .favorites: return Icons.favorite
        case .mostPlayed: return Icons.trending
        case .leastPlayed: return Icons.history
        case .decade: return Icons.vinyl
        }
    }

    var tint: Color {
        switch self {
        case .favorites: return Color(argb: 0xFFD4566F)
        case .mostPlayed: return Color(argb: 0xFF8C5F9E)
        case .leastPlayed: return Color(argb: 0xFF5E7DB0)
        case .decade: return Color(argb: 0xFFC99A45)
        }
    }

    var emptyText: String {
        switch self {
        case .favorites: return "Klicke bei einem Titel auf das Herz – er erscheint dann automatisch hier."
        case .mostPlayed: return "Sobald Titel gespielt wurden, erscheinen sie hier."
        default: return "Für diese automatische Playlist gibt es derzeit keine Titel."
        }
    }
}

struct PlaylistsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        let q = model.query(.playlists)
        LibraryScaffold(title: "Playlists", actions: { actions }) {
            VStack(spacing: 0) {
                LargeTitleHeader(title: "Playlists", section: .playlists, placeholder: "Playlist suchen",
                                 summary: Formatting.playlists(model.playlists.count), actions: { actions })
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 18, alignment: .top)], spacing: 0) {
                    Section {
                        ForEach(model.smartPlaylists) { smart in
                            PlaylistRow(name: smart.name, subtitle: smart.description + " · " + Formatting.tracks(smart.trackUids.count), automatic: true) {
                                GradientTile(icon: smart.kind.icon, base: smart.kind.tint, cornerRadius: Radius.artworkSmall, iconFraction: 0.48)
                            } open: {
                                model.open(.smartPlaylist(smart.id))
                            }
                        }
                        if q.isEmpty {
                            PlaylistRow(name: "Verlauf", subtitle: model.history.isEmpty ? "Noch nichts gespielt" : "Zuletzt gespielt · \(model.history.count) Einträge", automatic: true) {
                                GradientTile(icon: Icons.history, base: Color(argb: 0xFF4F9592), cornerRadius: Radius.artworkSmall, iconFraction: 0.48)
                            } open: {
                                model.open(.history)
                            }
                        }
                    } header: {
                        ListLabel("Automatisch").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Section {
                        if q.isEmpty {
                            PlaylistRow(name: "Neue Playlist …", subtitle: nil, automatic: false, accentName: true) {
                                RoundedRectangle(cornerRadius: Radius.artworkSmall, style: .continuous)
                                    .fill(colors.accentSoft)
                                    .overlay(Icon(Icons.add, size: 24, color: colors.accentText))
                            } open: {
                                NewPlaylistDialog.present(model: model, trackUids: [])
                            }
                        }
                        ForEach(model.playlistList) { p in
                            OwnPlaylistRow(playlist: p)
                        }
                    } header: {
                        ListLabel("Meine Playlists").frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if model.playlists.isEmpty && q.isEmpty {
                    EmptyStateView(icon: Icons.playlistAdd, title: "Noch keine eigenen Playlists",
                                   text: "Lege eine Playlist an und ziehe Titel, Alben oder Interpreten einfach darauf – oder nutze im Kontextmenü „Zu Playlist hinzufügen“.")
                }
            }
            .padding(.horizontal, Spacing.gutter)
        }
    }

    @ViewBuilder private var actions: some View {
        BarAction(icon: Icons.add, label: "Neue Playlist (⌘N)") { NewPlaylistDialog.present(model: model, trackUids: []) }
        SortMenu(sort: model.settings.playlistSort) { model.settings.playlistSort = $0 }
        SettingsAction()
    }
}

/// Zeile einer Playlist (Android `PlaylistRow`): Artwork, Name, Untertitel, Hinweis „automatisch“, Pfeil.
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

/// Eigene Playlist in der Übersicht – Ziel für Drag & Drop, mit Kontextmenü.
struct OwnPlaylistRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    let playlist: Playlist
    @State private var targeted = false

    var body: some View {
        let tracks = model.tracks(playlist.entries.map(\.trackUid))
        let totalMs: Int64 = tracks.reduce(Int64(0)) { $0 + $1.durationMs }
        let subtitle: String = Formatting.tracks(playlist.entries.count) + " · " + Formatting.longDuration(totalMs)
        PlaylistRow(name: playlist.name, subtitle: subtitle, automatic: false, dropTargeted: targeted) {
            MosaicArtwork(tracks: tracks, cornerRadius: Radius.artworkSmall)
        } open: {
            model.open(.playlist(playlist.id))
        }
        .onDrop(of: [UTType.plainText], isTargeted: $targeted) { providers in
            TrackDrag.load(providers) { uids, _ in model.addToPlaylist(playlist.id, trackUids: uids) }
            return true
        }
        .contextMenu {
            Button("Abspielen") { player.play(uids: playlist.entries.map(\.trackUid), startIndex: 0, shuffle: .off, source: PlaybackSource(kind: .playlist, label: playlist.name, id: String(playlist.id))) }
            Button("Mischen") { player.play(uids: playlist.entries.map(\.trackUid), startIndex: nil, shuffle: .on, source: PlaybackSource(kind: .playlist, label: playlist.name, id: String(playlist.id))) }
            Divider()
            Button("Umbenennen …") { RenamePlaylistDialog.present(model: model, playlist: playlist) }
            Button("Duplizieren") { model.duplicatePlaylist(playlist.id) }
            Divider()
            Button("Playlist löschen …") { DeletePlaylistDialog.present(model: model, playlist: playlist) }
        }
    }
}

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
                            Menu {
                                Button("Umbenennen …") { RenamePlaylistDialog.present(model: model, playlist: playlist) }
                                Button("Duplizieren") { model.duplicatePlaylist(playlist.id) }
                                Menu("Reihenfolge festlegen nach") {
                                    Button("Titel") { reorder(playlist, by: Sort(.title, descending: false)) }
                                    Button("Interpret") { reorder(playlist, by: Sort(.artist, descending: false)) }
                                    Button("Jahr") { reorder(playlist, by: Sort(.year, descending: false)) }
                                    Button("Dauer") { reorder(playlist, by: Sort(.duration, descending: false)) }
                                    Button("Meistgespielt") { reorder(playlist, by: Sort(.playCount, descending: true)) }
                                }
                                Divider()
                                Button("Playlist löschen …") { DeletePlaylistDialog.present(model: model, playlist: playlist) }
                            } label: {
                                Icon(Icons.moreHoriz, size: 18, color: colors.textPrimary)
                                    .frame(width: 34, height: 34)
                                    .glassSurface(Circle())
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
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

struct SmartPlaylistDetailView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    let smartID: String

    var body: some View {
        if let smart = model.smartPlaylist(smartID) {
            let tracks = model.tracks(smart.trackUids)
            let source = PlaybackSource(kind: .smartPlaylist, label: smart.name, id: smart.id)
            let showCounts = smart.kind == .mostPlayed || smart.kind == .leastPlayed
            let totalMs: Int64 = tracks.reduce(Int64(0)) { $0 + $1.durationMs }
            let meta: String = smart.description + " · " + Formatting.tracks(tracks.count) + " · " + Formatting.longDuration(totalMs)
            LibraryScaffold(title: smart.name, onBack: { model.back() }, edgeToEdgeTop: true, actions: {
                BarAction(icon: Icons.play, label: "Abspielen") { player.play(uids: smart.trackUids, startIndex: 0, shuffle: .off, source: source) }
                BarAction(icon: Icons.shuffle, label: "Mischen") { player.play(uids: smart.trackUids, startIndex: nil, shuffle: .on, source: source) }
            }) {
                VStack(spacing: 0) {
                    DetailHeader(
                        backdrop: nil,
                        tint: smart.kind.tint,
                        title: smart.name,
                        eyebrow: "Automatische Playlist",
                        meta: meta,
                        artwork: {
                            GradientTile(icon: smart.kind.icon, base: smart.kind.tint, cornerRadius: Radius.artworkLarge, iconFraction: 0.44)
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
                                trailingText: showCounts ? ({ t in "\(model.stats[t.uid]?.playCount ?? 0)×" } as (Track) -> String?) : nil
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
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE, d. MMMM yyyy"
        return f.string(from: day)
    }
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
