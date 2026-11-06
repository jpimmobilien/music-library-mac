import SwiftUI
import AppKit
import MLCore

// Favoriten (Android: FavoritesScreen mit Umschalter Titel/Alben), Duplikate und Dialoge.

struct FavoritesView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors

    var body: some View {
        let tracksTab = model.settings.favoritesTab == .tracks
        let context: LibraryViewContext = tracksTab ? .favoriteTracks : .favoriteAlbums
        let q = model.query(.favorites).trimmingCharacters(in: .whitespaces)
        let narrowed = !q.isEmpty || !model.filter(context).isEmpty
        let summary: String = tracksTab
            ? librarySummary(model.favoriteTrackList.count, model.unfilteredCount[.favoriteTracks] ?? model.favoriteTracks.count, narrowed: narrowed, Formatting.tracks)
            : librarySummary(model.favoriteAlbumList.count, model.unfilteredCount[.favoriteAlbums] ?? model.favoriteAlbums.count, narrowed: narrowed, Formatting.albums)
        LibraryScaffold(title: "Favoriten", toolbar: { toolbar(tracksTab) }) {
            VStack(spacing: 0) {
                LargeTitleHeader(title: "Favoriten", section: .favorites,
                                 placeholder: tracksTab ? "Favorisierte Titel durchsuchen" : "Favorisierte Alben durchsuchen",
                                 summary: summary, filterContext: context) {
                    SegmentedControl(options: FavoritesTab.allCases, selection: Binding(get: { model.settings.favoritesTab }, set: { model.settings.favoritesTab = $0 }),
                                     label: { $0.label }, icon: { $0 == .tracks ? Icons.musicNote : Icons.album })
                        .frame(maxWidth: 320)
                        .padding(.top, 12)
                }
                if tracksTab {
                    tracksContent(q)
                } else {
                    albumsContent(q)
                }
            }
            .padding(.horizontal, Spacing.gutter)
        }
    }

    @ViewBuilder
    private func tracksContent(_ q: String) -> some View {
        if model.favoriteTracks.isEmpty {
            EmptyStateView(icon: Icons.favoriteBorder, title: "Noch keine Lieblingstitel",
                           text: "Klicke bei einem Titel auf das Herz – er erscheint dann hier und in der automatischen Playlist „Favoriten“.")
        } else if model.favoriteTrackList.isEmpty {
            NoMatchesView(context: .favoriteTracks, query: q, noun: "Kein favorisierter Titel")
        } else {
            TrackCollection(context: .favoriteTracks, tracks: model.favoriteTrackList,
                            source: PlaybackSource(kind: .favorites, label: "Favoriten"),
                            sort: ColumnSorts.spec(ColumnSorts.favoriteTrack, sort: model.settings.favoriteTrackSort) { model.settings.favoriteTrackSort = $0 })
        }
    }

    @ViewBuilder
    private func albumsContent(_ q: String) -> some View {
        if model.favoriteAlbums.isEmpty {
            EmptyStateView(icon: Icons.favoriteBorder, title: "Noch keine Lieblingsalben",
                           text: "Öffne ein Album und klicke auf das Herz, oder nutze im Kontextmenü „Album zu Favoriten hinzufügen“.")
        } else {
            if model.favoriteAlbumList.isEmpty {
                if !model.missingFavoriteAlbums.isEmpty && q.isEmpty && model.filter(.favoriteAlbums).isEmpty {
                    EmptyView()
                } else {
                    NoMatchesView(context: .favoriteAlbums, query: q, noun: "Kein favorisiertes Album")
                }
            } else {
                AlbumCollection(context: .favoriteAlbums, albums: model.favoriteAlbumList,
                                sort: ColumnSorts.spec(ColumnSorts.favoriteAlbum, sort: model.settings.favoriteAlbumSort) { model.settings.favoriteAlbumSort = $0 })
            }
            if !model.missingFavoriteAlbums.isEmpty && q.isEmpty {
                MissingFavoriteAlbums()
            }
        }
    }

    /// „Mischen“: Titel-Favoriten = nur die (angezeigten) Lieblingstitel; Lieblingsalben = die angezeigten
    /// Alben in Zufallsfolge, jedes in Titelreihenfolge.
    @ViewBuilder
    private func toolbar(_ tracksTab: Bool) -> some View {
        if tracksTab {
            let list = model.favoriteTrackList
            let shuffle: (() -> Void)? = list.isEmpty ? nil : {
                player.play(uids: list.map(\.uid), startIndex: nil, shuffle: .on, source: PlaybackSource(kind: .favorites, label: "Favoriten (gemischt)"))
            }
            LibraryToolbar(context: .favoriteTracks, style: .full, sort: model.settings.favoriteTrackSort,
                           setSort: { model.settings.favoriteTrackSort = $0 },
                           shuffleLabel: "Lieblingstitel gemischt abspielen", shuffle: shuffle)
        } else {
            let albums = model.favoriteAlbumList
            let shuffle: (() -> Void)? = albums.isEmpty ? nil : {
                player.shuffleAlbums(albums.map(\.trackUids), source: PlaybackSource(kind: .favorites, label: "Lieblingsalben (gemischt)"))
            }
            LibraryToolbar(context: .favoriteAlbums, style: .full, sort: model.settings.favoriteAlbumSort,
                           setSort: { model.settings.favoriteAlbumSort = $0 },
                           shuffleLabel: "Lieblingsalben gemischt abspielen (Alben in Zufallsfolge, jedes in Titelreihenfolge)", shuffle: shuffle)
        }
    }
}

/// Favorisierte Alben, die derzeit nicht in der Bibliothek sind (z. B. Laufwerk getrennt).
private struct MissingFavoriteAlbums: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ListLabel("Derzeit nicht verfügbar")
            ForEach(model.missingFavoriteAlbums, id: \.albumKey) { fav in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: Radius.artworkSmall, style: .continuous)
                        .fill(colors.accentSoft)
                        .frame(width: 40, height: 40)
                        .overlay(Icon(Icons.favorite, size: 16, color: colors.heart.opacity(0.7)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(fav.title ?? "Unbekanntes Album").textStyle(Typo.bodyLarge).foregroundColor(colors.textPrimary)
                        Text(fav.artist ?? "").textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary)
                    }
                    Spacer()
                    IconTap(icon: Icons.clear, label: "Aus Favoriten entfernen", tint: colors.textSecondary) { model.removeMissingAlbumFavorite(fav.albumKey) }
                }
                .padding(.horizontal, 6)
                .frame(height: 54)
            }
        }
    }
}

// MARK: - Duplikate

/// Duplikaterkennung (neu gegenüber Android): Gruppen wahrscheinlich doppelter Titel mit Vorschlag,
/// welche Datei behalten wird. Entfernt wird nur nach Bestätigung – wahlweise nur aus der Bibliothek.
struct DuplicatesView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    @State private var groups: [DuplicateGroup] = []
    @State private var computing = true

    var body: some View {
        let status: String = computing ? "Bibliothek wird verglichen …" :
            groups.isEmpty ? "Keine wahrscheinlichen Duplikate gefunden." :
            "\(groups.count == 1 ? "1 Gruppe" : "\(groups.count) Gruppen") · Vorschlag zum Behalten ist markiert (verlustfrei vor hoher Bitrate, mit Cover, mehr Angaben, früher hinzugefügt)."
        LibraryScaffold(title: "Duplikate", onBack: { model.back() }) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Duplikate")
                    .textStyle(Typo.headlineLarge)
                    .foregroundColor(colors.textPrimary)
                    .padding(.horizontal, 4)
                Text(status)
                    .textStyle(Typo.labelMedium)
                    .foregroundColor(colors.textTertiary)
                    .padding(.top, 8)
                    .padding(.leading, 6)
                if computing {
                    ProgressView().padding(40).frame(maxWidth: .infinity)
                } else if groups.isEmpty {
                    EmptyStateView(icon: Icons.checkCircle, title: "Alles sauber", text: "Gleiche Titel mit gleichem Interpreten und fast gleicher Dauer sowie identische Dateien werden hier aufgeführt.")
                } else {
                    ForEach(groups) { group in
                        GlassCard(padding: 10) {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    Text(group.reason)
                                        .textStyle(Typo.sectionLabel)
                                        .foregroundColor(colors.textSecondary)
                                    Spacer()
                                    PillButton(title: "Übrige entfernen …", icon: Icons.delete, style: .plain) {
                                        RemoveTracksDialog.present(model: model, uids: group.others)
                                    }
                                }
                                .padding(.horizontal, 4)
                                ForEach(model.tracks(group.trackUids), id: \.uid) { t in
                                    DuplicateRow(track: t, keep: t.uid == group.keepUid)
                                }
                            }
                        }
                        .padding(.top, 14)
                    }
                }
            }
            .padding(.horizontal, Spacing.gutter)
        }
        .task(id: model.index.tracks.count) {
            computing = true
            let tracks = model.index.tracks.filter(\.available)
            groups = await Task.detached(priority: .userInitiated) { DuplicateFinder.find(tracks) }.value
            computing = false
        }
    }
}

private struct DuplicateRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    let track: Track
    let keep: Bool

    var body: some View {
        let bitrateText: String? = track.bitrate > 0 ? "\(track.bitrate) kbit/s" : nil
        let infoParts: [String?] = [track.artistText, track.album, track.codec, bitrateText]
        let info: String = infoParts.compactMap { $0 }.joined(separator: " · ")
        HStack(spacing: 12) {
            TrackArtwork(track: track, size: .small).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(track.displayTitle).textStyle(Typo.bodyLarge).foregroundColor(colors.textPrimary).lineLimit(1)
                    if keep {
                        Text("BEHALTEN")
                            .textStyle(Typo.labelSmall)
                            .foregroundColor(colors.accentText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(colors.accentSoft))
                    }
                }
                Text(info)
                    .textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).lineLimit(1)
                Text(track.path)
                    .textStyle(Typo.labelSmall).foregroundColor(colors.textTertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(Formatting.duration(track.durationMs)).textStyle(Typo.duration).monospacedDigit().foregroundColor(colors.textTertiary)
            IconTap(icon: Icons.play, label: "Anhören") {
                player.play(uids: [track.uid], startIndex: 0, shuffle: .off, source: PlaybackSource(kind: .singleTrack, label: track.displayTitle))
            }
            IconTap(icon: Icons.folderOpen, label: "Im Finder zeigen") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: track.path)])
            }
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 60)
        .contextMenu { TrackMenuItems(uids: [track.uid], single: track) }
    }
}

// MARK: - Dialoge (native Mac-Dialoge mit App-Texten)

enum NewPlaylistDialog {
    @MainActor
    static func present(model: AppModel, trackUids: [Int64], suggestedName: String? = nil) {
        let alert = NSAlert()
        alert.messageText = "Neue Playlist"
        alert.informativeText = trackUids.isEmpty ? "Gib einen Namen ein." : "\(Formatting.tracks(trackUids.count)) werden hinzugefügt."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = model.uniquePlaylistName(suggestedName ?? "Neue Playlist")
        alert.accessoryView = field
        alert.addButton(withTitle: "Erstellen")
        alert.addButton(withTitle: "Abbrechen")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            model.createPlaylist(name: field.stringValue, trackUids: trackUids, open: trackUids.isEmpty)
        }
    }
}

enum RenamePlaylistDialog {
    @MainActor
    static func present(model: AppModel, playlist: Playlist) {
        let alert = NSAlert()
        alert.messageText = "Playlist umbenennen"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = playlist.name
        alert.accessoryView = field
        alert.addButton(withTitle: "Umbenennen")
        alert.addButton(withTitle: "Abbrechen")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            model.renamePlaylist(playlist.id, to: field.stringValue)
        }
    }
}

enum DeletePlaylistDialog {
    @MainActor
    static func present(model: AppModel, playlist: Playlist) {
        let alert = NSAlert()
        alert.messageText = "Playlist löschen?"
        alert.informativeText = "„\(playlist.name)“ wird gelöscht. Die Musikdateien bleiben unverändert erhalten."
        alert.addButton(withTitle: "Playlist löschen")
        alert.addButton(withTitle: "Abbrechen")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            model.deletePlaylist(playlist.id)
        }
    }
}

// „Titel löschen …“ (Aus der Musikbibliothek entfernen / In den Papierkorb legen): gemeinsamer Glas-Dialog
// `RemoveTracksDialog` in Views/Library/LibraryDialogs.swift.

/// Auswahl der Playlist für „Zu Playlist hinzufügen …“ (Android `AddToPlaylistDialog`).
struct AddToPlaylistSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    @Environment(\.dismiss) private var dismiss
    let uids: [Int64]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Zu Playlist hinzufügen")
                .textStyle(Typo.titleLarge)
                .foregroundColor(colors.textPrimary)
            Text(Formatting.tracks(uids.count))
                .textStyle(Typo.bodySmall)
                .foregroundColor(colors.textSecondary)
                .padding(.top, 2)
            ScrollView {
                VStack(spacing: 0) {
                    PlaylistRow(name: "Neue Playlist …", subtitle: nil, automatic: false, accentName: true) {
                        RoundedRectangle(cornerRadius: Radius.artworkSmall, style: .continuous)
                            .fill(colors.accentSoft)
                            .overlay(Icon(Icons.add, size: 22, color: colors.accentText))
                    } open: {
                        dismiss()
                        DispatchQueue.main.async { NewPlaylistDialog.present(model: model, trackUids: uids) }
                    }
                    ForEach(model.playlists) { p in
                        PlaylistRow(name: p.name, subtitle: Formatting.tracks(p.entries.count), automatic: false) {
                            MosaicArtwork(tracks: model.tracks(p.entries.prefix(8).map(\.trackUid)), cornerRadius: Radius.artworkSmall)
                        } open: {
                            model.addToPlaylist(p.id, trackUids: uids)
                            dismiss()
                        }
                    }
                }
            }
            .frame(minHeight: 200, maxHeight: 420)
            .padding(.top, 12)
            HStack {
                Spacer()
                PillButton(title: "Schließen") { dismiss() }
            }
            .padding(.top, 10)
        }
        .padding(22)
        .frame(width: 440)
        .background(AmbientBackground())
    }
}
