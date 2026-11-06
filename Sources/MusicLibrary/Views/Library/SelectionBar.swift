import SwiftUI
import AppKit
import MLCore

// Mehrfachauswahl (v2.1): Die Sammlung bzw. Titelliste meldet ihre Auswahl an einen gemeinsamen Speicher;
// eine schwebende Glasleiste über dem Mini-Player zeigt die Anzahl („12 Titel ausgewählt“,
// „3 Alben ausgewählt (38 Titel)“) und die Aktionen für die ganze Auswahl. Es gibt immer nur eine Auswahl:
// Wählt man in einer anderen Liste aus, wird die vorige aufgehoben.

enum LibrarySelectionKind {
    case tracks, albums, artists, genres, playlists
}

/// Momentaufnahme einer Auswahl (bei jeder Änderung neu gemeldet).
struct LibrarySelectionInfo {
    let owner: UUID
    let kind: LibrarySelectionKind
    /// Anzahl der gewählten Einträge (Titel, Alben, Interpreten …).
    let count: Int
    /// Alle Titel der Auswahl in angezeigter Reihenfolge (in Playlists ggf. mit Wiederholungen).
    let uids: [Int64]
    /// Je gewähltem Eintrag seine Titel (Alben, Interpreten, Genres, Playlists); bei Titeln leer.
    let groups: [[Int64]]
    /// Namen der ersten gewählten Einträge (für Dialoge).
    let names: [String]
    let source: PlaybackSource
    /// Auswahl in einer eigenen Playlist: Einträge für „Aus Playlist entfernen“.
    var playlistID: Int64? = nil
    var entryIds: [Int64] = []
    let clear: () -> Void

    /// Titel ohne Wiederholungen (Reihenfolge bleibt).
    var uniqueUids: [Int64] {
        var seen = Set<Int64>()
        return uids.filter { seen.insert($0).inserted }
    }

    /// „Als Album zusammenfassen …“ ergibt nur für Titel und Alben Sinn.
    var allowsMerge: Bool { (kind == .tracks && count > 1) || kind == .albums }

    /// Löschen von Titeln über Playlists hinweg wäre überraschend – dort nicht angeboten.
    var allowsDelete: Bool { kind != .playlists }

    var summary: String {
        switch kind {
        case .tracks: return "\(Formatting.tracks(count)) ausgewählt"
        case .albums: return "\(Formatting.albums(count)) ausgewählt (\(Formatting.tracks(uids.count)))"
        case .artists: return "\(Formatting.artists(count)) ausgewählt (\(Formatting.tracks(uids.count)))"
        case .genres: return "\(Formatting.genres(count)) ausgewählt (\(Formatting.tracks(uids.count)))"
        case .playlists: return "\(Formatting.playlists(count)) ausgewählt (\(Formatting.tracks(uids.count)))"
        }
    }

    /// Beschreibung für den Löschdialog.
    var deleteSubject: DeleteSubject {
        switch kind {
        case .tracks: return .tracks
        case .albums: return count == 1 ? .album(title: names.first ?? "Unbekanntes Album") : .albums(count: count)
        case .artists: return count == 1 ? .group(label: "Interpret „\(names.first ?? "")“") : .group(label: Formatting.artists(count))
        case .genres: return count == 1 ? .group(label: "Genre „\(names.first ?? "")“") : .group(label: Formatting.genres(count))
        case .playlists: return .group(label: Formatting.playlists(count))
        }
    }
}

@MainActor
final class LibrarySelectionStore: ObservableObject {
    static let shared = LibrarySelectionStore()

    @Published private(set) var info: LibrarySelectionInfo?

    /// Neue Auswahl einer Liste melden (eine Auswahl einer anderen Liste wird dabei aufgehoben).
    func publish(_ new: LibrarySelectionInfo) {
        let previous = info
        info = new
        if let previous, previous.owner != new.owner { previous.clear() }
    }

    /// Die Liste hat keine (sichtbare) Auswahl mehr.
    func withdraw(owner: UUID) {
        if info?.owner == owner { info = nil }
    }

    /// Auswahl aufheben (Schaltfläche, Esc).
    func clear() {
        let current = info
        info = nil
        current?.clear()
    }

    /// Gewählte Gruppen einer Art (z. B. Interpreten für „Mischen“), sonst `nil`.
    func groups(of kind: LibrarySelectionKind) -> [[Int64]]? {
        guard let info, info.kind == kind, !info.groups.isEmpty else { return nil }
        return info.groups
    }
}

/// Für Vorschaubilder: die erste passende Liste wählt beim Erscheinen ihre ersten `count` Einträge aus.
@MainActor
enum LibrarySelectionSeed {
    static var pending: (kind: LibrarySelectionKind, count: Int)?

    static func take(_ kind: LibrarySelectionKind) -> Int? {
        guard let p = pending, p.kind == kind else { return nil }
        pending = nil
        return p.count
    }
}

enum SelectionBarMetrics {
    static let height: CGFloat = 44
    /// Platz, den die Leiste unten belegt (inkl. Abstand zum Mini-Player).
    static let reservedHeight: CGFloat = height + 10
}

// MARK: - Leiste

/// Zeigt die Auswahlleiste, solange es eine Auswahl gibt (im Hauptfenster über dem Mini-Player).
struct SelectionBarHost: View {
    @ObservedObject private var store = LibrarySelectionStore.shared

    var body: some View {
        ZStack {
            if let info = store.info {
                SelectionBar(info: info)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.easeOut(Motion.short), value: store.info?.owner)
    }
}

/// Platzhalter am Ende des Scrollinhalts: Die letzte Zeile lässt sich über die Auswahlleiste hinaus scrollen.
struct SelectionBarSpacer: View {
    @ObservedObject private var store = LibrarySelectionStore.shared

    var body: some View {
        Color.clear.frame(height: store.info == nil ? 0 : SelectionBarMetrics.reservedHeight)
    }
}

struct SelectionBar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    let info: LibrarySelectionInfo

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(labeled: true)
            bar(labeled: false)
        }
        // Esc hebt die Auswahl auf (unsichtbare Schaltfläche: gilt unabhängig von der gewählten Breite)
        .background(
            Button("Auswahl aufheben") { LibrarySelectionStore.shared.clear() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Auswahl: \(info.summary)")
    }

    private func bar(labeled: Bool) -> some View {
        HStack(spacing: 2) {
            Group {
                Text(info.summary)
                    .font(Typo.inter(13, .semibold))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.leading, 12)
                    .padding(.trailing, 4)
                ToolbarSeparator()
                SelectionBarButton(icon: Icons.play, title: "Wiedergeben", labeled: labeled) { play() }
                SelectionBarButton(icon: Icons.queue, title: "Zur Warteschlange", labeled: labeled) {
                    player.addToQueue(uids: info.uids)
                }
                SelectionBarButton(icon: Icons.playlistAdd, title: "Zu Playlist", labeled: labeled) {
                    model.addToPlaylistUids = info.uids
                }
                SelectionBarButton(icon: Icons.edit, title: "Informationen", labeled: labeled) {
                    model.showInfo(info.uniqueUids)
                }
            }
            Group {
                if info.allowsMerge {
                    SelectionBarButton(icon: Icons.album, title: "Als Album zusammenfassen …", labeled: labeled) {
                        MergeAlbumDialog.present(model: model, uids: info.uniqueUids)
                    }
                }
                if let pid = info.playlistID, !info.entryIds.isEmpty {
                    SelectionBarButton(icon: Icons.playlistRemove, title: "Aus Playlist entfernen", labeled: labeled) {
                        let entries = info.entryIds
                        info.clear()
                        model.removeFromPlaylist(pid, entryIds: entries)
                    }
                }
                if info.allowsDelete {
                    SelectionBarButton(icon: Icons.delete, title: "Löschen …", labeled: labeled, destructive: true) {
                        RemoveTracksDialog.present(model: model, uids: info.uniqueUids, subject: info.deleteSubject)
                    }
                }
                ToolbarSeparator()
                IconTap(icon: Icons.close, label: "Auswahl aufheben (Esc)", tint: colors.textSecondary, iconSize: 15, touch: 30) {
                    LibrarySelectionStore.shared.clear()
                }
                .padding(.trailing, 2)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: SelectionBarMetrics.height)
        .fixedSize()
        .glassSurface(Capsule(), strong: true, elevated: true)
    }

    private func play() {
        if info.kind == .albums {
            player.play(uids: info.uids, startIndex: 0, shuffle: .off, source: info.source, albumContext: info.groups)
        } else {
            player.play(uids: info.uids, startIndex: 0, shuffle: .off, source: info.source)
        }
    }
}

/// Schaltfläche der Auswahlleiste: Symbol, bei genug Platz mit Beschriftung.
private struct SelectionBarButton: View {
    @Environment(\.musicColors) private var colors
    let icon: String
    let title: String
    let labeled: Bool
    var destructive: Bool = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Icon(icon, size: 16, color: tint)
                if labeled {
                    Text(title)
                        .font(Typo.inter(12.5, .semibold))
                        .foregroundColor(tint)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, labeled ? 10 : 0)
            .frame(minWidth: 32, minHeight: 32)
            .background(Capsule().fill((destructive ? colors.danger : colors.textPrimary).opacity(hover ? 0.08 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle(scale: 0.92))
        .onHover { hover = $0 }
        .help(title)
        .accessibilityLabel(title)
    }

    private var tint: Color { destructive ? colors.danger : colors.textPrimary }
}
