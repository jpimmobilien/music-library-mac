import SwiftUI
import AppKit
import MLCore

/// Eigenes Mini-Player-Fenster (⌥⌘M): kompakte Glaskapsel mit Cover, Titel, Tasten, Fortschritt;
/// aufklappbar mit großem Cover. Optional immer im Vordergrund.
struct MiniPlayerWindow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    @State private var expanded = false
    @State private var floating = true

    var body: some View {
        VStack(spacing: 0) {
            if expanded {
                TrackArtwork(track: player.current, size: .large, cornerRadius: 0, iconFraction: 0.4)
                    .frame(width: 320, height: 320)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    if !expanded {
                        TrackArtwork(track: player.current, size: .small, cornerRadius: Radius.artworkSmall)
                            .frame(width: 52, height: 52)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.current?.displayTitle ?? "Nichts wird gespielt")
                            .textStyle(Typo.bodyLarge).fontWeight(.medium)
                            .foregroundColor(colors.textPrimary).lineLimit(1)
                        Text(player.current?.artistText ?? " ")
                            .textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let t = player.current {
                        HeartButton(favorite: model.isFavorite(t.uid), iconSize: 15, touch: 26) { model.toggleFavorite([t.uid]) }
                    }
                }
                MiniTimeline()
                HStack(spacing: 0) {
                    IconTap(icon: expanded ? Icons.closeFull : Icons.openFull, label: expanded ? "Cover ausblenden" : "Cover einblenden", tint: colors.textSecondary, iconSize: 15, touch: 28) {
                        withAnimation(Motion.easeOut()) { expanded.toggle() }
                    }
                    Spacer()
                    TransportControls(compact: true)
                    Spacer()
                    IconTap(icon: floating ? "keep" : "keep_off", label: floating ? "Nicht mehr im Vordergrund" : "Immer im Vordergrund", tint: floating ? colors.accentText : colors.textSecondary, iconSize: 15, touch: 28) {
                        floating.toggle()
                        applyFloating()
                    }
                }
            }
            .padding(14)
        }
        .frame(width: 320)
        .background(AmbientBackground())
        .onAppear { applyFloating() }
    }

    private func applyFloating() {
        DispatchQueue.main.async {
            for w in NSApp.windows where w.title == "Mini-Player" {
                w.level = floating ? .floating : .normal
                w.collectionBehavior.insert(.canJoinAllSpaces)
                w.titlebarAppearsTransparent = true
                w.standardWindowButton(.miniaturizeButton)?.isHidden = true
                w.standardWindowButton(.zoomButton)?.isHidden = true
            }
        }
    }
}

/// Wiedergabe in der Menüleiste (Menüleisten-Symbol mit kleiner Steuerung).
struct MenuBarPlayer: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                TrackArtwork(track: player.current, size: .small, cornerRadius: Radius.artworkSmall)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.current?.displayTitle ?? "Nichts wird gespielt").textStyle(Typo.titleSmall).lineLimit(1)
                    Text(player.current?.artistText ?? "Music Library").textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).lineLimit(1)
                    Text(player.current?.album ?? "").textStyle(Typo.bodySmall).foregroundColor(colors.textTertiary).lineLimit(1)
                }
            }
            MiniTimeline()
            HStack {
                Spacer()
                TransportControls(compact: true)
                Spacer()
            }
            VolumeControl()
            Divider()
            HStack {
                Button("Music Library öffnen") {
                    NSApp.activate(ignoringOtherApps: true)
                    for w in NSApp.windows where w.title == "Music Library" { w.makeKeyAndOrderFront(nil) }
                }
                .buttonStyle(.plain)
                .foregroundColor(colors.accentText)
                Spacer()
                Button("Beenden") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundColor(colors.textSecondary)
            }
            .font(Typo.inter(12, .medium))
        }
        .padding(14)
        .frame(width: 300)
        .background(AmbientBackground())
    }
}
