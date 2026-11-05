import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MLCore

/// Ein Eintrag einer Titelliste (in Playlists darf ein Titel mehrfach vorkommen → eigene Kennung).
struct TrackListItem: Identifiable, Hashable {
    let id: Int64
    let track: Track
    var entryId: Int64? = nil

    static func plain(_ tracks: [Track]) -> [TrackListItem] { tracks.map { TrackListItem(id: $0.uid, track: $0) } }
}

/// Darstellung und Verhalten einer Titelliste.
struct TrackListConfig {
    enum Numbering { case none, trackNumber, position }
    var showArtwork = true
    var showAlbum = true
    var numbering: Numbering = .none
    /// Playlist (Neuordnen per Drag & Drop, „Aus dieser Playlist entfernen“).
    var playlistID: Int64? = nil
    var source: PlaybackSource
    /// Zusätzlicher Text rechts (z. B. „12×“ bei „Meistgespielt“).
    var trailingText: ((Track) -> String?)? = nil
    /// Breites Fenster: Album als eigene Spalte (Zeile zeigt dann nur den Interpreten).
    var albumColumnWidth: CGFloat? = nil
    /// Jahr und Genre leise rechts („Zusatzinfos anzeigen“).
    var showDetails = false
}

/// Anordnung einer Titelliste: Zeilen, Detailliste mit Spalten oder Kacheln (Raster).
enum TrackLayout {
    case rows
    case table(TrackTableSpec)
    case tiles(TileMetrics)
}

/// Spalten und Sortierung der Detailliste von Titeln.
struct TrackTableSpec {
    var context: LibraryViewContext
    var columns: [DetailColumn]
    var sort: TableSortSpec
}

/// Vergleichbare Darstellungsangaben einer Zeile (für `Equatable`-Zeilen).
struct TrackRowStyle: Equatable {
    var showArtwork: Bool
    var showAlbum: Bool
    var numbering: TrackListConfig.Numbering
    var albumColumnWidth: CGFloat?
    var showDetails: Bool

    init(_ config: TrackListConfig) {
        showArtwork = config.showArtwork
        showAlbum = config.showAlbum
        numbering = config.numbering
        albumColumnWidth = config.albumColumnWidth
        showDetails = config.showDetails
    }
}

/// Gemeinsame Tastaturbedienung: Die zuletzt angeklickte Liste reagiert auf Pfeiltasten, Eingabe, Löschen, ⌘A.
@MainActor
final class KeyboardFocus {
    static let shared = KeyboardFocus()
    struct ListHandle {
        var moveSelection: (Int, Bool) -> Void
        var playSelection: () -> Void
        var deleteSelection: () -> Void
        var selectAll: () -> Void
        var selectedUids: () -> [Int64]
    }
    var activeList: ListHandle?
}

/// Pasteboard-Typ für gezogene Titel (Kennungen, kommagetrennt).
enum TrackDrag {
    static let prefix = "musiclibrary-tracks:"

    static func provider(uids: [Int64], entryIds: [Int64]) -> NSItemProvider {
        let text = prefix + uids.map(String.init).joined(separator: ",") + "|" + entryIds.map(String.init).joined(separator: ",")
        return NSItemProvider(object: text as NSString)
    }

    static func decode(_ text: String) -> (uids: [Int64], entryIds: [Int64])? {
        guard text.hasPrefix(prefix) else { return nil }
        let parts = text.dropFirst(prefix.count).split(separator: "|", omittingEmptySubsequences: false)
        let uids = parts.first.map { $0.split(separator: ",").compactMap { Int64($0) } } ?? []
        let entries = parts.count > 1 ? parts[1].split(separator: ",").compactMap { Int64($0) } : []
        return (uids, entries)
    }

    /// Liest gezogene Titel aus Drop-Providern (asynchron).
    static func load(_ providers: [NSItemProvider], completion: @escaping ([Int64], [Int64]) -> Void) {
        guard let p = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return }
        _ = p.loadObject(ofClass: NSString.self) { obj, _ in
            guard let s = obj as? String, let d = decode(s) else { return }
            DispatchQueue.main.async { completion(d.uids, d.entryIds) }
        }
    }
}

/// Titelliste mit Mehrfachauswahl (⌘/⇧-Klick), Doppelklick zum Abspielen, Kontextmenü, Drag & Drop –
/// als Zeilen, Detailliste (Spalten, Klick auf den Kopf sortiert) oder Kacheln. Zeilen und Kacheln sind
/// `Equatable`-Werte ohne Umgebungsobjekte (flüssiges Scrollen mit 10.000 Titeln).
struct TrackListView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors

    let items: [TrackListItem]
    let config: TrackListConfig
    var layout: TrackLayout = .rows
    @State private var selection: Set<Int64> = []
    @State private var anchor: Int?
    @State private var dropTarget: Int64?

    var body: some View {
        Group {
            switch layout {
            case .rows: rows
            case .table(let spec): table(spec)
            case .tiles(let metrics): tiles(metrics)
            }
        }
        .onChange(of: items.map(\.id)) { ids in
            selection = selection.intersection(ids)
        }
    }

    // MARK: Anordnungen

    private var rows: some View {
        let style = TrackRowStyle(config)
        let currentUid = player.current?.uid
        return LazyVStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { position, item in
                let uid = item.track.uid
                let current = currentUid == uid
                let row = TrackRowView(
                    track: item.track,
                    position: position,
                    style: style,
                    trailing: config.trailingText?(item.track),
                    selected: selection.contains(item.id),
                    current: current,
                    playing: current && player.isPlaying,
                    favorite: model.isFavorite(uid),
                    dropAbove: dropTarget == item.id,
                    toggleFavorite: { model.toggleFavorite([uid]) }
                )
                interactive(row.equatable(), position: position, item: item)
            }
        }
    }

    private func table(_ spec: TrackTableSpec) -> some View {
        let widths: [CGFloat] = spec.columns.map { CGFloat($0.defaultWidth) }
        let currentUid = player.current?.uid
        return VStack(spacing: 0) {
            DetailTableHeader(context: spec.context, columns: spec.columns, widths: widths, sort: spec.sort)
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { position, item in
                    let track = item.track
                    let current = currentUid == track.uid
                    let stats = model.stats[track.uid]
                    let row = DetailTableRow(
                        item: LibraryItems.track(track, favorite: model.isFavorite(track.uid), current: current),
                        cells: spec.columns.map { TrackCells.value(track, $0, stats: stats) },
                        columns: spec.columns,
                        widths: widths,
                        selected: selection.contains(item.id),
                        unavailable: !track.available,
                        dropAbove: dropTarget == item.id,
                        playing: current && player.isPlaying,
                        onFavorite: { model.toggleFavorite([track.uid]) }
                    )
                    interactive(row.equatable(), position: position, item: item)
                }
            }
        }
        .padding(.top, 4)
    }

    private func tiles(_ metrics: TileMetrics) -> some View {
        let currentUid = player.current?.uid
        return LazyVGrid(columns: metrics.columns, alignment: .leading, spacing: metrics.rowSpacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { position, item in
                let track = item.track
                let current = currentUid == track.uid
                let tile = CollectionTile(
                    item: LibraryItems.track(track, favorite: model.isFavorite(track.uid), current: current),
                    style: metrics.style,
                    selected: selection.contains(item.id),
                    playing: current && player.isPlaying,
                    onPlay: { play(from: position) },
                    onFavorite: { model.toggleFavorite([track.uid]) }
                )
                interactive(tile.equatable(), position: position, item: item)
            }
        }
        .padding(.top, 8)
    }

    /// Klick, Kontextmenü, Ziehen und Ablegen – gleich für alle Anordnungen.
    private func interactive<V: View>(_ view: V, position: Int, item: TrackListItem) -> some View {
        view
            .contentShape(Rectangle())
            .onTapGesture { click(position, item) }
            .contextMenu { contextMenu(for: item) }
            .onDrag { dragProvider(for: item) }
            .onDrop(of: [UTType.plainText], isTargeted: dropBinding(item.id)) { providers in
                handleDrop(providers, before: position)
            }
    }

    private func dropBinding(_ id: Int64) -> Binding<Bool> {
        Binding(
            get: { dropTarget == id },
            set: { on in dropTarget = on ? id : (dropTarget == id ? nil : dropTarget) }
        )
    }

    // MARK: Auswahl

    private func click(_ position: Int, _ item: TrackListItem) {
        let flags = NSEvent.modifierFlags
        let clicks = NSApp.currentEvent?.clickCount ?? 1
        if clicks >= 2 {
            play(from: position)
            return
        }
        if flags.contains(.command) {
            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
            anchor = position
        } else if flags.contains(.shift), let a = anchor {
            // Anker kann nach dem Filtern/Sortieren hinter dem Listenende liegen
            let lower = min(a, position)
            let upper = min(max(a, position), items.count - 1)
            if lower <= upper { selection = Set((lower...upper).map { items[$0].id }) }
        } else {
            selection = [item.id]
            anchor = position
        }
        registerKeyboard()
    }

    private func registerKeyboard() {
        KeyboardFocus.shared.activeList = KeyboardFocus.ListHandle(
            moveSelection: { delta, extend in moveSelection(delta, extend: extend) },
            playSelection: {
                if let first = items.firstIndex(where: { selection.contains($0.id) }) { play(from: first) }
            },
            deleteSelection: { deleteSelected() },
            selectAll: { selection = Set(items.map(\.id)) },
            selectedUids: { selectedTracks().map(\.uid) }
        )
    }

    private func moveSelection(_ delta: Int, extend: Bool) {
        guard !items.isEmpty else { return }
        let current = anchor ?? items.firstIndex(where: { selection.contains($0.id) }) ?? -1
        let next = min(max(current + delta, 0), items.count - 1)
        if extend {
            selection.insert(items[next].id)
        } else {
            selection = [items[next].id]
        }
        anchor = next
    }

    private func selectedTracks() -> [Track] {
        items.filter { selection.contains($0.id) }.map(\.track)
    }

    /// Kontextmenü wirkt auf die Auswahl, wenn der angeklickte Titel dazugehört, sonst nur auf ihn.
    private func targets(for item: TrackListItem) -> [TrackListItem] {
        selection.contains(item.id) ? items.filter { selection.contains($0.id) } : [item]
    }

    private func play(from position: Int) {
        let uids = items.map(\.track.uid)
        player.play(uids: uids, startIndex: position, shuffle: .keep, source: config.source)
    }

    private func deleteSelected() {
        let targets = items.filter { selection.contains($0.id) }
        guard !targets.isEmpty else { return }
        if let pid = config.playlistID {
            model.removeFromPlaylist(pid, entryIds: targets.compactMap(\.entryId))
        } else {
            RemoveTracksDialog.present(model: model, uids: targets.map(\.track.uid))
        }
    }

    // MARK: Drag & Drop

    private func dragProvider(for item: TrackListItem) -> NSItemProvider {
        let t = targets(for: item)
        return TrackDrag.provider(uids: t.map(\.track.uid), entryIds: t.compactMap(\.entryId))
    }

    private func handleDrop(_ providers: [NSItemProvider], before position: Int) -> Bool {
        guard let pid = config.playlistID else { return false }
        TrackDrag.load(providers) { uids, entryIds in
            let own = Set(items.compactMap(\.entryId))
            if !entryIds.isEmpty && entryIds.allSatisfy({ own.contains($0) }) {
                model.movePlaylistEntries(pid, entryIds: entryIds, to: position)
            } else if !uids.isEmpty {
                model.addToPlaylist(pid, trackUids: uids, at: position)
            }
        }
        dropTarget = nil
        return true
    }

    // MARK: Kontextmenü

    @ViewBuilder
    private func contextMenu(for item: TrackListItem) -> some View {
        let t = targets(for: item)
        let uids = t.map(\.track.uid)
        let single = t.count == 1 ? t.first?.track : nil
        TrackMenuItems(uids: uids, single: single, playlistID: config.playlistID, entryIds: t.compactMap(\.entryId),
                       playAction: { if let p = items.firstIndex(of: t[0]) { play(from: p) } })
    }
}

/// Einträge des Kontextmenüs eines oder mehrerer Titel (Android `TrackContextMenu`, ergänzt um Mac-Funktionen).
struct TrackMenuItems: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    let uids: [Int64]
    let single: Track?
    var playlistID: Int64? = nil
    var entryIds: [Int64] = []
    var playAction: (() -> Void)? = nil

    var body: some View {
        let allFavorite = uids.allSatisfy { model.isFavorite($0) }
        // In Gruppen: höchstens 10 direkte Elemente je ViewBuilder unter macOS 13
        Group {
            if let playAction {
                Button(single != nil ? "Abspielen" : "\(Formatting.tracks(uids.count)) abspielen", action: playAction)
            }
            Button(single != nil ? "Nur diesen Titel abspielen" : "Nur diese Titel abspielen") {
                player.play(uids: uids, startIndex: 0, shuffle: .off, source: PlaybackSource(kind: .singleTrack, label: single?.displayTitle ?? "Auswahl"))
            }
            Button("Als Nächstes spielen") { player.playNext(uids: uids) }
            Button("Zur Warteschlange hinzufügen") { player.addToQueue(uids: uids) }
            Divider()
            Menu("Zu Playlist hinzufügen") {
                Button("Neue Playlist …") { NewPlaylistDialog.present(model: model, trackUids: uids) }
                if !model.playlists.isEmpty { Divider() }
                ForEach(model.playlists) { p in
                    Button(p.name) { model.addToPlaylist(p.id, trackUids: uids) }
                }
            }
            Button(allFavorite ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen") {
                model.setFavorite(uids, !allFavorite)
            }
        }
        Group {
            if let single {
                Divider()
                Button("Album öffnen") { model.openAlbum(of: single) }
                    .disabled(single.album == nil)
                if let artist = single.artists.first {
                    Button("Interpret öffnen") { model.openArtist(named: artist) }
                }
            }
            Divider()
            Button(single != nil ? "Informationen …" : "Informationen zu \(Formatting.tracks(uids.count)) …") { model.showInfo(uids) }
            Button("Metadaten kopieren") { model.metadata.copyMetadata(from: uids.first) }
                .disabled(uids.count != 1)
            Button("Metadaten einfügen …") { model.metadata.pasteMetadata(to: uids) }
                .disabled(!model.metadata.hasClipboard)
            Button("Im Finder zeigen") {
                let urls = model.tracks(uids).map { URL(fileURLWithPath: $0.path) }
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            }
            if let pid = playlistID, !entryIds.isEmpty {
                Divider()
                Button("Aus dieser Playlist entfernen") { model.removeFromPlaylist(pid, entryIds: entryIds) }
            }
            Divider()
            Button("Aus der Bibliothek entfernen …") { RemoveTracksDialog.present(model: model, uids: uids) }
        }
    }
}

/// Eine Zeile der Titelliste (Android `TrackRow`) – bewusst ohne Karte und ohne Tabellenraster:
/// Cover, Titel, Interpret · Album (bei breitem Fenster Album als eigene Spalte), rechtsbündige Spieldauer
/// mit gleich breiten Ziffern, zurückhaltendes Herz. Ein reiner Wert ohne Umgebungsobjekte.
struct TrackRowView: View, Equatable {
    @Environment(\.musicColors) private var colors
    let track: Track
    let position: Int
    let style: TrackRowStyle
    let trailing: String?
    let selected: Bool
    let current: Bool
    let playing: Bool
    let favorite: Bool
    var dropAbove: Bool = false
    let toggleFavorite: () -> Void
    @State private var hover = false

    static func == (a: TrackRowView, b: TrackRowView) -> Bool {
        a.track == b.track && a.position == b.position && a.style == b.style && a.trailing == b.trailing && a.selected == b.selected
            && a.current == b.current && a.playing == b.playing && a.favorite == b.favorite && a.dropAbove == b.dropAbove
    }

    var body: some View {
        let textStart: CGFloat = style.showArtwork ? Metrics.trackArtwork + 12 : (style.numbering != .none ? 38 : 0)
        HStack(spacing: 0) {
            leading
            texts
                .frame(maxWidth: .infinity, alignment: .leading)
            columns
            trailingItems
        }
        .padding(.leading, 6)
        .padding(.trailing, 2)
        .frame(height: style.showArtwork ? Metrics.trackRowHeight : 44)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? colors.selectionFill : (hover ? colors.textPrimary.opacity(colors.dark ? 0.045 : 0.035) : .clear))
        )
        .overlay(alignment: .bottom) {
            if !selected { Hairline(leading: textStart + 6) }
        }
        .overlay(alignment: .top) {
            if dropAbove {
                Capsule().fill(colors.accent).frame(height: 2.5).padding(.horizontal, 4)
            }
        }
        .onHover { hover = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.displayTitle), \(subtitle)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var leading: some View {
        if !style.showArtwork, style.numbering != .none {
            ZStack {
                if current {
                    NowPlayingBars(playing: playing)
                } else {
                    Text(numberText)
                        .textStyle(Typo.duration)
                        .monospacedDigit()
                        .foregroundColor(colors.textTertiary)
                }
            }
            .frame(width: 30)
            Spacer().frame(width: 8)
        }
        if style.showArtwork {
            ZStack {
                TrackArtwork(track: track, size: .small, cornerRadius: Radius.artworkSmall)
                if current {
                    RoundedRectangle(cornerRadius: Radius.artworkSmall, style: .continuous)
                        .fill(Color.black.opacity(0.38))
                    NowPlayingBars(playing: playing, color: .white)
                }
            }
            .frame(width: Metrics.trackArtwork, height: Metrics.trackArtwork)
            Spacer().frame(width: 12)
        }
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(track.displayTitle)
                .font(Typo.inter(Typo.bodyLarge.size, current ? .semibold : .medium))
                .tracking(Typo.bodyLarge.tracking)
                .foregroundColor(current ? colors.accentText : (track.available ? colors.textPrimary : colors.textTertiary))
                .lineLimit(1)
            Text(subtitle)
                .textStyle(Typo.bodySmall)
                .foregroundColor(colors.textSecondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var columns: some View {
        if let width = style.albumColumnWidth, style.showAlbum {
            Text(track.album ?? "")
                .textStyle(Typo.bodySmall)
                .foregroundColor(colors.textSecondary)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
                .padding(.leading, 12)
        }
        if style.showDetails, let meta = metaText {
            Text(meta)
                .textStyle(Typo.labelMedium)
                .foregroundColor(colors.textTertiary)
                .lineLimit(1)
                .frame(width: 130, alignment: .trailing)
                .padding(.leading, 8)
        }
    }

    @ViewBuilder
    private var trailingItems: some View {
        if !track.available {
            Text("nicht verfügbar")
                .textStyle(Typo.labelSmall)
                .foregroundColor(colors.textTertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(colors.fieldFill))
                .padding(.leading, 8)
        }
        if let trailing {
            Text(trailing)
                .textStyle(Typo.duration)
                .monospacedDigit()
                .foregroundColor(colors.accentText)
                .padding(.leading, 10)
        }
        if track.durationMs > 0 {
            Text(Formatting.duration(track.durationMs))
                .textStyle(Typo.duration)
                .monospacedDigit()
                .foregroundColor(colors.textTertiary)
                .frame(minWidth: 52, alignment: .trailing)
        }
        HeartButton(favorite: favorite, iconSize: 15, touch: 30, subject: "„\(track.displayTitle)“", toggle: toggleFavorite)
            .opacity(favorite || hover || selected ? 1 : 0.55)
            .padding(.leading, 4)
    }

    private var numberText: String {
        switch style.numbering {
        case .trackNumber: return track.trackNumber.map { String($0) } ?? "–"
        case .position: return "\(position + 1)"
        case .none: return ""
        }
    }

    private var subtitle: String {
        var parts: [String] = [track.artistText ?? "Unbekannter Interpret"]
        if style.showAlbum, style.albumColumnWidth == nil, let album = track.album { parts.append(album) }
        return parts.joined(separator: " · ")
    }

    private var metaText: String? {
        let parts: [String?] = [track.year.map { String($0) }, track.genres.first]
        let joined = parts.compactMap { $0 }.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }
}
