import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MLCore
import MLTags

/// Seitenleiste rechts (Desktop-Ergänzung): Warteschlange oder Liedtext als schwebende Glasfläche.
struct SidePanelView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    let panel: SidePanel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SegmentedControl(options: [SidePanel.queue, SidePanel.lyrics], selection: Binding(get: { panel }, set: { model.sidePanel = $0 }),
                                 label: { $0 == .queue ? "Warteschlange" : "Liedtext" },
                                 icon: { $0 == .queue ? Icons.queue : Icons.lyrics })
                IconTap(icon: Icons.close, label: "Seitenleiste schließen", tint: colors.textSecondary, iconSize: 15, touch: 28) { model.sidePanel = nil }
            }
            .padding(12)
            switch panel {
            case .queue: QueuePanel()
            case .lyrics: LyricsPanel()
            }
        }
        .glassSurface(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous), strong: true, elevated: true)
    }
}

// MARK: - Warteschlange (Android `QueueSheet`)

struct QueuePanel: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    @State private var dropIndex: Int?

    var body: some View {
        let upNext = player.queue.upNext
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let current = player.current {
                    ListLabel("Läuft gerade")
                    QueueRow(track: current, current: true)
                }
                HStack {
                    ListLabel(player.queue.source.map { "Als Nächstes · aus „\($0.label)“" } ?? "Als Nächstes")
                    if !upNext.isEmpty {
                        Button("Leeren") { player.clearUpNext() }
                            .buttonStyle(.plain)
                            .font(Typo.inter(11.5, .semibold))
                            .foregroundColor(colors.accentText)
                            .padding(.top, 10)
                    }
                }
                if upNext.isEmpty {
                    Text(player.repeatMode == .all ? "Die Quelle beginnt danach von vorn." : "Danach endet die Wiedergabe.")
                        .textStyle(Typo.bodySmall)
                        .foregroundColor(colors.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 10)
                }
                ForEach(Array(upNext.prefix(300).enumerated()), id: \.element.id) { index, item in
                    if let track = model.track(item.trackUid) {
                        QueueRow(track: track, current: false)
                            .overlay(alignment: .top) {
                                if dropIndex == index { Capsule().fill(colors.accent).frame(height: 2.5) }
                            }
                            .onTapGesture {
                                if NSApp.currentEvent?.clickCount ?? 1 >= 2 { player.jump(to: item) }
                            }
                            .contextMenu {
                                Button("Jetzt abspielen") { player.jump(to: item) }
                                Button("Aus der Warteschlange entfernen") { player.removeFromQueue(item: item) }
                                Divider()
                                Button("Informationen …") { model.showInfo([track.uid]) }
                                Button("Im Audio Studio schneiden …") {
                                    model.studio.openLibraryTrack(track.uid)
                                    model.openStudio()
                                }
                                .disabled(!track.available)
                            }
                            .onDrag { NSItemProvider(object: "queue:\(index)" as NSString) }
                            .onDrop(of: [UTType.plainText], isTargeted: Binding(get: { dropIndex == index }, set: { dropIndex = $0 ? index : (dropIndex == index ? nil : dropIndex) })) { providers in
                                drop(providers, at: index)
                            }
                    }
                }
                if upNext.count > 300 {
                    Text("… und \(upNext.count - 300) weitere")
                        .textStyle(Typo.bodySmall)
                        .foregroundColor(colors.textTertiary)
                        .padding(8)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
    }

    private func drop(_ providers: [NSItemProvider], at index: Int) -> Bool {
        guard let p = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        _ = p.loadObject(ofClass: NSString.self) { obj, _ in
            guard let s = obj as? String else { return }
            DispatchQueue.main.async {
                if s.hasPrefix("queue:"), let from = Int(s.dropFirst(6)) {
                    player.moveUpNext(from: from, to: index)
                } else if let d = TrackDrag.decode(s) {
                    player.playNext(uids: d.uids)
                }
                dropIndex = nil
            }
        }
        return true
    }
}

private struct QueueRow: View {
    @Environment(\.musicColors) private var colors
    @EnvironmentObject private var player: PlayerService
    let track: Track
    let current: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                TrackArtwork(track: track, size: .small)
                if current {
                    RoundedRectangle(cornerRadius: Radius.artworkSmall, style: .continuous).fill(Color.black.opacity(0.38))
                    NowPlayingBars(playing: player.isPlaying, color: .white, size: 12)
                }
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.displayTitle)
                    .textStyle(Typo.bodyMedium)
                    .fontWeight(current ? .semibold : .medium)
                    .foregroundColor(current ? colors.accentText : colors.textPrimary)
                    .lineLimit(1)
                Text(track.artistText ?? "Unbekannter Interpret")
                    .textStyle(Typo.bodySmall)
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !current {
                Icon(Icons.dragHandle, size: 15, color: colors.textTertiary.opacity(hover ? 0.9 : 0.4))
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover ? colors.textPrimary.opacity(0.05) : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

// MARK: - Liedtext

/// Lädt Liedtexte (eingebettet oder .lrc-Datei daneben).
enum LyricsSource {
    /// Nur für Vorschaubilder.
    static var demo: [Int64: String] = [:]

    /// - Parameter useLrc: auch eine `.lrc`-Datei neben der Musikdatei verwenden (Einstellung).
    static func load(_ track: Track, useLrc: Bool = true) async -> String? {
        if let text = demo[track.uid] { return text }
        return await Task.detached(priority: .userInitiated) {
            let url = URL(fileURLWithPath: track.path)
            if let tags = try? TagFile.read(url: url), let text = tags.values.lyrics, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
            guard useLrc else { return nil }
            let lrc = url.deletingPathExtension().appendingPathExtension("lrc")
            if let data = try? Data(contentsOf: lrc) {
                return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
            }
            return nil
        }.value
    }
}

/// Liedtext zum laufenden Titel; synchronisierte Texte (LRC) folgen der Wiedergabe, Klick auf eine Zeile springt dorthin.
struct LyricsPanel: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    /// Schriftgröße (`nil` = Einstellung „Liedtext-Schriftgröße“).
    var fontSize: CGFloat? = nil
    /// Zentriert (großer Player).
    var center: Bool = false
    @State private var lyrics: Lyrics?
    @State private var loadedFor: Int64?
    @State private var loading = false

    var body: some View {
        Group {
            if player.current == nil {
                EmptyStateView(icon: Icons.lyrics, title: "Kein Titel", text: "Spiele einen Titel ab, um seinen Liedtext zu sehen.")
            } else if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let lyrics, lyrics.isSynced || !(lyrics.plainText ?? "").isEmpty {
                LyricsContent(lyrics: lyrics, clock: player.clock, fontSize: fontSize ?? CGFloat(model.settings.lyricsFontSize),
                              color: colors.textPrimary, dim: colors.textTertiary, center: center,
                              autoScroll: model.settings.lyricsAutoScroll) { ms in
                    player.seek(to: ms)
                }
            } else {
                EmptyStateView(icon: Icons.lyrics, title: "Kein Liedtext", text: "Diese Datei enthält keinen Liedtext. Du kannst ihn im Informationsfenster hinzufügen – auch synchronisiert.") {
                    PillButton(title: "Liedtext hinzufügen …", icon: Icons.editNote) {
                        if let uid = player.current?.uid {
                            model.metadata.requestedTab = .lyrics
                            model.showInfo([uid])
                        }
                    }
                }
            }
        }
        .task(id: player.current?.coverKey) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .lyricsChanged)) { _ in Task { await load() } }
    }

    private func load() async {
        guard let t = player.current else { lyrics = nil; return }
        if loadedFor != t.uid { loading = true }
        let text = await LyricsSource.load(t, useLrc: model.settings.lyricsUseLrcFiles)
        lyrics = text.map { LyricsParser.parse($0) }
        loadedFor = t.uid
        loading = false
    }
}

extension Notification.Name {
    static let lyricsChanged = Notification.Name("MusicLibrary.lyricsChanged")
}

/// Darstellung eines (synchronisierten) Liedtextes.
struct LyricsContent: View {
    let lyrics: Lyrics
    @ObservedObject var clock: PlaybackClock
    var fontSize: CGFloat = 17
    var color: Color
    var dim: Color
    var center: Bool = false
    /// Der aktuellen Zeile automatisch folgen.
    var autoScroll: Bool = true
    let seek: (Int64) -> Void

    var body: some View {
        if lyrics.isSynced {
            let currentIndex = lyrics.lineIndex(at: clock.positionMs)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: center ? .center : .leading, spacing: 14) {
                        ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { i, line in
                            let isCurrent: Bool = i == currentIndex
                            let isPast: Bool = i < (currentIndex ?? -1)
                            let textAlign: TextAlignment = center ? .center : .leading
                            let frameAlign: Alignment = center ? .center : .leading
                            let anchor: UnitPoint = center ? .center : .leading
                            Text(line.isGap ? "♪" : line.text)
                                .font(Typo.inter(fontSize, isCurrent ? .bold : .semibold, display: true))
                                .foregroundColor(isCurrent ? color : dim.opacity(isPast ? 0.55 : 0.8))
                                .multilineTextAlignment(textAlign)
                                .frame(maxWidth: .infinity, alignment: frameAlign)
                                .scaleEffect(isCurrent ? 1.0 : 0.97, anchor: anchor)
                                .animation(Motion.easeOut(Motion.medium), value: currentIndex)
                                .id(i)
                                .contentShape(Rectangle())
                                .onTapGesture { seek(line.timeMs) }
                                .help("Zu \(Formatting.duration(line.timeMs)) springen")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 40)
                }
                .onChange(of: currentIndex) { idx in
                    guard autoScroll, let idx else { return }
                    withAnimation(Motion.easeOut(0.45)) { proxy.scrollTo(idx, anchor: UnitPoint(x: 0.5, y: 0.35)) }
                }
            }
        } else {
            ScrollView {
                Text(lyrics.plainText ?? "")
                    .font(Typo.inter(fontSize - 2, .medium))
                    .foregroundColor(color)
                    .lineSpacing(6)
                    .multilineTextAlignment(center ? .center : .leading)
                    .frame(maxWidth: .infinity, alignment: center ? .center : .leading)
                    .textSelection(.enabled)
                    .padding(16)
            }
        }
    }
}
