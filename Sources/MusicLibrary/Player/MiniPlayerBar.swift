import SwiftUI
import AppKit
import MLCore

/// Mini-Player (Android `MiniPlayer`): schwebende Glaskapsel mit Cover, Titel, Interpret, Play/Pause und „Weiter“;
/// eine feine Rosé-Linie zeigt den Fortschritt. Auf dem Mac zusätzlich Zurück, Zufall, Wiederholen, Zeitleiste,
/// Lautstärke sowie Warteschlange und Liedtext. Klick auf Cover/Titel öffnet den großen Player.
struct MiniPlayerBar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > 760
            let veryWide = geo.size.width > 900
            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    Button { model.playerOpen = true } label: {
                        HStack(spacing: 12) {
                            TrackArtwork(track: player.current, size: .small, cornerRadius: Radius.artworkSmall)
                                .frame(width: 42, height: 42)
                                .id(player.current?.coverKey)
                                .transition(.opacity)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(player.current?.displayTitle ?? "")
                                    .textStyle(Typo.bodyLarge)
                                    .fontWeight(.medium)
                                    .foregroundColor(colors.textPrimary)
                                    .lineLimit(1)
                                Text(player.current?.artistText ?? "Unbekannter Interpret")
                                    .textStyle(Typo.bodySmall)
                                    .foregroundColor(colors.textSecondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: wide ? 220 : .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Player öffnen (⌘⇧F)")
                    .accessibilityLabel("Player öffnen")

                    if wide {
                        Spacer(minLength: 12)
                        TransportControls(compact: true)
                        Spacer(minLength: 12)
                        if veryWide {
                            MiniTimeline()
                                .frame(minWidth: 140, maxWidth: 260)
                            Spacer(minLength: 10)
                        }
                        VolumeControl()
                            .frame(width: 128)
                        HStack(spacing: 0) {
                            IconTap(icon: Icons.lyrics, label: "Liedtext (⌘L)", tint: model.sidePanel == .lyrics ? colors.accentText : colors.textPrimary, iconSize: 18) {
                                model.sidePanel = model.sidePanel == .lyrics ? nil : .lyrics
                            }
                            IconTap(icon: Icons.queue, label: "Warteschlange (⌥⌘U)", tint: model.sidePanel == .queue ? colors.accentText : colors.textPrimary, iconSize: 18) {
                                model.sidePanel = model.sidePanel == .queue ? nil : .queue
                            }
                            IconTap(icon: Icons.miniPlayer, label: "Mini-Player-Fenster (⌥⌘M)", iconSize: 18) { WindowRouter.shared.openMiniPlayer() }
                        }
                        .padding(.leading, 6)
                    } else {
                        Spacer(minLength: 4)
                        IconTap(icon: player.isPlaying ? Icons.pause : Icons.play, label: player.isPlaying ? "Pause" : "Abspielen", iconSize: 26, touch: 40) { player.togglePlay() }
                        IconTap(icon: Icons.next, label: "Nächster Titel", iconSize: 22, touch: 38) { player.next() }
                            .disabled(!player.queue.hasNext)
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, 8)
                .frame(maxHeight: .infinity)
                if !(wide && veryWide) {
                    MiniProgressLine()
                        .padding(.horizontal, 22)
                        .frame(height: 2)
                        .padding(.bottom, 1)
                }
            }
        }
        .frame(height: Metrics.miniPlayerHeight)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.bar, style: .continuous), strong: true, elevated: true)
        .gesture(DragGesture(minimumDistance: 18).onEnded { g in
            if g.translation.height < -20 { model.playerOpen = true }
        })
    }
}

/// Feine Fortschrittslinie (Android: 2 dp Rosé-Linie am unteren Rand).
private struct MiniProgressLine: View {
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors

    var body: some View {
        ProgressLineContent(clock: player.clock)
    }

    private struct ProgressLineContent: View {
        @ObservedObject var clock: PlaybackClock
        @Environment(\.musicColors) private var colors

        var body: some View {
            GeometryReader { g in
                let p = clock.durationMs > 0 ? min(1, max(0, CGFloat(clock.positionMs) / CGFloat(clock.durationMs))) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(colors.textPrimary.opacity(0.08))
                    Capsule().fill(colors.accent).frame(width: g.size.width * p)
                }
            }
        }
    }
}

/// Zeitleiste mit verstellbarer Position (Mac: im Mini-Player bei breiten Fenstern).
struct MiniTimeline: View {
    @EnvironmentObject private var player: PlayerService
    var body: some View { TimelineContent(player: player, clock: player.clock) }

    private struct TimelineContent: View {
        let player: PlayerService
        @ObservedObject var clock: PlaybackClock
        @Environment(\.musicColors) private var colors
        @State private var dragValue: Double?

        var body: some View {
            let duration = Double(max(clock.durationMs, 1))
            let value = dragValue ?? Double(clock.positionMs)
            HStack(spacing: 8) {
                Text(Formatting.duration(Int64(value)))
                    .textStyle(Typo.time)
                    .monospacedDigit()
                    .foregroundColor(colors.textTertiary)
                    .frame(width: 38, alignment: .trailing)
                MusicSlider(value: Binding(get: { value }, set: { dragValue = $0 }), range: 0...duration,
                            activeColor: colors.textPrimary.opacity(0.75), label: "Wiedergabeposition",
                            valueText: Formatting.duration(Int64(value))) { editing in
                    if !editing, let v = dragValue {
                        player.seek(to: Int64(v))
                        dragValue = nil
                    }
                }
                Text("-" + Formatting.duration(max(0, clock.durationMs - Int64(value))))
                    .textStyle(Typo.time)
                    .monospacedDigit()
                    .foregroundColor(colors.textTertiary)
                    .frame(width: 42, alignment: .leading)
            }
        }
    }
}

/// Zufall · Zurück · Play/Pause · Weiter · Wiederholen.
struct TransportControls: View {
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    var compact: Bool = false
    var tint: Color? = nil
    var accent: Color? = nil

    var body: some View {
        let fg = tint ?? colors.textPrimary
        let on = accent ?? colors.accentText
        HStack(spacing: compact ? 2 : 14) {
            IconTap(icon: Icons.shuffle, label: player.shuffleEnabled ? "Zufallswiedergabe aus" : "Zufallswiedergabe an",
                    tint: player.shuffleEnabled ? on : fg.opacity(0.75), iconSize: compact ? 17 : 21, touch: compact ? 32 : 40) { player.toggleShuffle() }
            IconTap(icon: Icons.previous, label: "Vorheriger Titel", tint: fg, iconSize: compact ? 22 : 32, touch: compact ? 36 : 52) { player.previous() }
            Button { player.togglePlay() } label: {
                Icon(player.isPlaying ? Icons.pause : Icons.play, size: compact ? 28 : 44, color: fg)
                    .frame(width: compact ? 40 : 66, height: compact ? 40 : 66)
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle(scale: 0.88))
            .help(player.isPlaying ? "Pause (Leertaste)" : "Abspielen (Leertaste)")
            .accessibilityLabel(player.isPlaying ? "Pause" : "Abspielen")
            IconTap(icon: Icons.next, label: "Nächster Titel", tint: fg, iconSize: compact ? 22 : 32, touch: compact ? 36 : 52) { player.next() }
                .disabled(!player.queue.hasNext)
            IconTap(icon: player.repeatMode == .one ? Icons.repeatOne : Icons.repeatAll, label: player.repeatMode.label,
                    tint: player.repeatMode == .off ? fg.opacity(0.75) : on, iconSize: compact ? 17 : 21, touch: compact ? 32 : 40) { player.cycleRepeat() }
        }
    }
}

/// Lautstärke (0–300 %, Markierung bei 100 %; darüber digitale Verstärkung mit Limiter – Android-Regel).
struct VolumeControl: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    var tint: Color? = nil
    var showsPercent = false

    var body: some View {
        let v = Double(player.liveVolume)
        HStack(spacing: 6) {
            IconTap(icon: v == 0 ? Icons.volumeOff : Icons.volumeDown, label: v == 0 ? "Ton an" : "Stumm", tint: tint ?? colors.textSecondary, iconSize: 16, touch: 26) {
                let target: Float = v == 0 ? 1 : 0
                player.setLiveVolume(target)
                model.settings.effects.volume = target
            }
            MusicSlider(value: Binding(get: { v }, set: { player.setLiveVolume(Float($0)) }),
                        range: 0...Double(AudioEffectsSettings.maxVolume), marker: 1,
                        activeColor: (tint ?? colors.textPrimary).opacity(0.75), step: 0.01, label: "Lautstärke",
                        valueText: "\(Int((v * 100).rounded())) %") { editing in
                if !editing { model.settings.effects.volume = player.liveVolume }
            }
            if showsPercent {
                Text("\(Int((v * 100).rounded())) %")
                    .textStyle(Typo.time)
                    .monospacedDigit()
                    .foregroundColor(v > 1 ? colors.accentText : (tint ?? colors.textTertiary))
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .help("Lautstärke \(Int((v * 100).rounded())) % – über 100 % digitale Verstärkung mit Begrenzer")
    }
}
