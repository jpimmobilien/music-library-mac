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

/// Titelliste mit Mehrfachauswahl (⌘/⇧-Klick), Doppelklick zum Abspielen, Kontextmenü, Drag & Drop.
struct TrackListView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors

    let items: [TrackListItem]
    let config: TrackListConfig
    @State private var selection: Set<Int64> = []
    @State private var anchor: Int?
    @State private var dropTarget: Int64?

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { position, item in
                TrackRowView(
                    track: item.track,
                    position: position,
                    config: config,
                    selected: selection.contains(item.id),
                    current: player.current?.uid == item.track.uid,
                    playing: player.isPlaying,
                    favorite: model.isFavorite(item.track.uid),
                    dropAbove: dropTarget == item.id
                )
                .contentShape(Rectangle())
                .onTapGesture { click(position, item) }
                .contextMenu { contextMenu(for: item) }
                .onDrag { dragProvider(for: item) }
                .onDrop(of: [UTType.plainText], isTargeted: Binding(get: { dropTarget == item.id }, set: { dropTarget = $0 ? item.id : (dropTarget == item.id ? nil : dropTarget) })) { providers in
                    handleDrop(providers, before: position)
                }
            }
        }
        .onChange(of: items.map(\.id)) { ids in
            selection = selection.intersection(ids)
        }
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
            selection = Set((lower...upper).map { items[$0].id })
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
/// Cover, Titel, Interpret · Album, rechtsbündige Spieldauer mit gleich breiten Ziffern, zurückhaltendes Herz.
struct TrackRowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    let track: Track
    let position: Int
    let config: TrackListConfig
    let selected: Bool
    let current: Bool
    let playing: Bool
    let favorite: Bool
    var dropAbove: Bool = false
    @State private var hover = false

    var body: some View {
        let textStart: CGFloat = config.showArtwork ? Metrics.trackArtwork + 12 : (config.numbering != .none ? 38 : 0)
        HStack(spacing: 0) {
            if !config.showArtwork, config.numbering != .none {
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
            if config.showArtwork {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            if !track.available {
                Text("nicht verfügbar")
                    .textStyle(Typo.labelSmall)
                    .foregroundColor(colors.textTertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(colors.fieldFill))
                    .padding(.trailing, 8)
            }
            if let extra = config.trailingText?(track) {
                Text(extra)
                    .textStyle(Typo.duration)
                    .monospacedDigit()
                    .foregroundColor(colors.accentText)
                    .padding(.trailing, 10)
            }
            if track.durationMs > 0 {
                Text(Formatting.duration(track.durationMs))
                    .textStyle(Typo.duration)
                    .monospacedDigit()
                    .foregroundColor(colors.textTertiary)
                    .frame(minWidth: 40, alignment: .trailing)
            }
            HeartButton(favorite: favorite, iconSize: 15, touch: 30, subject: "„\(track.displayTitle)“") {
                model.toggleFavorite([track.uid])
            }
            .opacity(favorite || hover || selected ? 1 : 0.55)
            .padding(.leading, 4)
        }
        .padding(.leading, 6)
        .padding(.trailing, 2)
        .frame(height: config.showArtwork ? Metrics.trackRowHeight : 44)
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

    private var numberText: String {
        switch config.numbering {
        case .trackNumber: return track.trackNumber.map(String.init) ?? "–"
        case .position: return "\(position + 1)"
        case .none: return ""
        }
    }

    private var subtitle: String {
        var parts: [String] = [track.artistText ?? "Unbekannter Interpret"]
        if config.showAlbum, let album = track.album { parts.append(album) }
        return parts.joined(separator: " · ")
    }
}
