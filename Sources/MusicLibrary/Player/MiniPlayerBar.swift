import SwiftUI
import AppKit
import MLCore

/// Mini-Player (v2): schwebende Liquid-Glass-Fläche mit Tiefe am unteren Fensterrand, in drei Größen
/// (`settings.miniPlayerSize`). Links das gewählte Player-Design im Kleinen (Platte, Kassette, CD, Spulen,
/// Aurora, Cover) mit Titel und Favorit, in der Mitte Wiedergabetasten und Zeitleiste, rechts kompakte
/// Werkzeuge: Tonhöhe und Equalizer als Popover, Lautstärke, Liedtext, Warteschlange, Größe, Optionen und
/// großer Player. Klick auf das Mittelstück oder den Titel öffnet den großen Player.
///
/// Leistung: Der Körper liest keine hochfrequenten Werte. Position und Fortschritt lesen nur `MiniTimeline`
/// bzw. die Wickel; gedreht wird nur im kleinen Mittelstück (und nur, solange der große Player zu ist).
/// Der Schatten liegt als ruhende Form außerhalb der Glasfläche und wird nicht je Bild neu berechnet.
struct MiniPlayerBar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    @StateObject private var artwork = NowPlayingArtwork(size: .medium)

    var body: some View {
        let size = model.settings.miniPlayerSize
        let height = CGFloat(size.height)
        let radius: CGFloat = min(height / 2, size == .large ? 34 : 30)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let glow = Color(argb: artwork.palette.glow)
        GeometryReader { geo in
            MiniBarContent(width: geo.size.width, height: height, size: size, artwork: artwork)
        }
        .frame(height: height)
        .background(MiniBarTint(glow: glow, dark: colors.dark, radius: radius))
        .glassSurface(shape, strong: true)
        .background(OuterShadow(cornerRadius: radius, color: colors.glassShadow, radius: 16, y: 7))
        .background(OuterShadow(cornerRadius: radius, color: glow.opacity(colors.dark ? 0.30 : 0.22), radius: 26, y: 12))
        .task(id: player.current?.coverKey) { await artwork.update(for: player.current) }
        .gesture(DragGesture(minimumDistance: 18).onEnded { g in
            if g.translation.height < -20 { model.playerOpen = true }
        })
        .animation(Motion.easeOut(Motion.medium), value: size)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mini-Player")
    }
}

/// Maße je Größe.
enum MiniMetrics {
    static func heroSide(_ size: MiniPlayerSize) -> CGFloat {
        switch size {
        case .compact: return 48
        case .standard: return 66
        case .large: return 90
        }
    }

    /// Breite der Zeitleiste (passt sich der Fensterbreite an).
    static func timelineWidth(_ size: MiniPlayerSize, width: CGFloat) -> CGFloat {
        switch size {
        case .compact: return min(240, max(150, width * 0.2))
        case .standard: return min(290, max(200, width * 0.29))
        case .large: return min(330, max(210, width * 0.3))
        }
    }

    /// Kompakt: Zeitleiste in derselben Zeile (sonst nur eine feine Fortschrittslinie).
    static func compactTimeline(width: CGFloat) -> Bool { width >= 820 }

    /// Lautstärkeregler direkt in der Leiste (sonst als Popover).
    static func inlineVolume(width: CGFloat) -> Bool { width >= 980 }
}

/// Zarter Lichtschein in der Coverfarbe auf der Glasfläche (links, hinter dem Mittelstück).
private struct MiniBarTint: View {
    let glow: Color
    let dark: Bool
    let radius: CGFloat

    var body: some View {
        LinearGradient(stops: [
            .init(color: glow.opacity(dark ? 0.24 : 0.16), location: 0),
            .init(color: glow.opacity(0), location: 0.5),
        ], startPoint: .leading, endPoint: .trailing)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .animation(.easeInOut(duration: 0.8), value: glow)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct MiniBarContent: View {
    let width: CGFloat
    let height: CGFloat
    let size: MiniPlayerSize
    @ObservedObject var artwork: NowPlayingArtwork

    var body: some View {
        let hero = MiniMetrics.heroSide(size)
        let inset = max(8, (height - hero) / 2)
        let inlineTimeline = size != .compact || MiniMetrics.compactTimeline(width: width)
        HStack(spacing: 0) {
            MiniNowPlaying(size: size, heroSide: hero, artwork: artwork)
            Spacer(minLength: 10)
            Group {
                if size == .compact {
                    HStack(spacing: 8) {
                        MiniTransport(large: false)
                        if inlineTimeline {
                            MiniTimeline()
                                .frame(width: MiniMetrics.timelineWidth(size, width: width))
                        }
                    }
                } else {
                    VStack(spacing: size == .large ? 4 : 0) {
                        MiniTransport(large: size == .large)
                        MiniTimeline()
                            .frame(width: MiniMetrics.timelineWidth(size, width: width))
                    }
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 10)
            MiniTools(size: size, inlineVolume: MiniMetrics.inlineVolume(width: width))
                .layoutPriority(1)
        }
        .padding(.leading, inset)
        .padding(.trailing, inset + 4)
        .frame(width: width, height: height)
        .overlay(alignment: .bottom) {
            if !inlineTimeline {
                MiniProgressLine()
                    .padding(.horizontal, 30)
                    .frame(height: 2)
                    .padding(.bottom, 1)
            }
        }
    }
}

/// Mittelstück im Design, Titel, Interpret (groß: Album) und Favorit.
private struct MiniNowPlaying: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    let size: MiniPlayerSize
    let heroSide: CGFloat
    @ObservedObject var artwork: NowPlayingArtwork

    var body: some View {
        let t = player.current
        let animate = PlayerMotionPolicy.continuous(model.settings) && !model.playerOpen
        HStack(spacing: size == .compact ? 10 : 12) {
            Button { model.playerOpen = true } label: {
                MiniHeroView(theme: model.settings.playerTheme, showsDesign: model.settings.miniPlayerShowsDesign, side: heroSide,
                             track: t, artwork: artwork, playing: player.isPlaying, animate: animate,
                             speed: model.settings.pitch.speed, cassetteColor: model.settings.cassetteColor, clock: player.clock)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle(scale: 0.95))
            .help("Großen Player öffnen (⌘⇧F)")
            .accessibilityLabel("Großen Player öffnen")
            Button { model.playerOpen = true } label: {
                MiniTitles(track: t, size: size)
                    .frame(minWidth: 60, maxWidth: 260, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Großen Player öffnen")
            .accessibilityLabel(t.map { "\($0.displayTitle) von \($0.artistText ?? "unbekanntem Interpreten") – großen Player öffnen" } ?? "Großen Player öffnen")
            if let t {
                HeartButton(favorite: model.isFavorite(t.uid), iconSize: size == .large ? 18 : 16, touch: 30,
                            inactiveTint: colors.textSecondary.opacity(0.8), subject: "„\(t.displayTitle)“") {
                    model.toggleFavorite([t.uid])
                }
            }
        }
    }
}

private struct MiniTitles: View {
    @Environment(\.musicColors) private var colors
    let track: Track?
    let size: MiniPlayerSize

    var body: some View {
        VStack(alignment: .leading, spacing: size == .large ? 2 : 1) {
            Text(track?.displayTitle ?? "")
                .font(Typo.inter(size == .large ? 15.5 : 14, .semibold))
                .foregroundColor(colors.textPrimary)
                .lineLimit(1)
            Text(track?.artistText ?? "Unbekannter Interpret")
                .textStyle(size == .large ? Typo.bodyMedium : Typo.bodySmall)
                .foregroundColor(colors.textSecondary)
                .lineLimit(1)
            if size == .large, let album = track?.album, !album.isEmpty {
                Text(album)
                    .textStyle(Typo.bodySmall)
                    .foregroundColor(colors.textTertiary)
                    .lineLimit(1)
            }
        }
        .id(track?.uid)
        .transition(.opacity)
        .animation(.easeOut(duration: 0.25), value: track?.uid)
    }
}

/// Zufall · Zurück · Play/Pause · Weiter · Wiederholen.
private struct MiniTransport: View {
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    let large: Bool

    var body: some View {
        let fg = colors.textPrimary
        let on = colors.accentText
        let small: CGFloat = large ? 18 : 16
        let mid: CGFloat = large ? 26 : 22
        HStack(spacing: large ? 8 : 4) {
            IconTap(icon: Icons.shuffle, label: player.shuffleEnabled ? "Zufallswiedergabe aus" : "Zufallswiedergabe an",
                    tint: player.shuffleEnabled ? on : fg.opacity(0.7), iconSize: small, touch: large ? 34 : 30) { player.toggleShuffle() }
                .overlay(alignment: .bottom) { ActiveDot(on: player.shuffleEnabled) }
            IconTap(icon: Icons.previous, label: "Vorheriger Titel bzw. Titelanfang", tint: fg, iconSize: mid, touch: large ? 40 : 34) { player.previous() }
            MiniPlayButton(large: large)
            IconTap(icon: Icons.next, label: "Nächster Titel", tint: fg, iconSize: mid, touch: large ? 40 : 34) { player.next() }
                .disabled(!player.queue.hasNext)
            IconTap(icon: player.repeatMode == .one ? Icons.repeatOne : Icons.repeatAll, label: player.repeatMode.label,
                    tint: player.repeatMode == .off ? fg.opacity(0.7) : on, iconSize: small, touch: large ? 34 : 30) { player.cycleRepeat() }
                .overlay(alignment: .bottom) { ActiveDot(on: player.repeatMode != .off) }
        }
    }
}

/// Kleiner Punkt unter aktiven Schaltern (Zufall, Wiederholen).
private struct ActiveDot: View {
    @Environment(\.musicColors) private var colors
    let on: Bool

    var body: some View {
        Circle()
            .fill(colors.accent)
            .frame(width: 3.5, height: 3.5)
            .opacity(on ? 1 : 0)
            .offset(y: -1)
            .allowsHitTesting(false)
            .animation(Motion.easeOut(), value: on)
    }
}

private struct MiniPlayButton: View {
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    let large: Bool
    @State private var hover = false

    var body: some View {
        let d: CGFloat = large ? 48 : 40
        Button { player.togglePlay() } label: {
            Icon(player.isPlaying ? Icons.pause : Icons.play, size: large ? 30 : 25, color: colors.textPrimary)
                .frame(width: d, height: d)
                .background(Circle().fill(colors.textPrimary.opacity(hover ? 0.11 : 0.06)))
                .contentShape(Circle())
                .animation(.easeOut(duration: 0.16), value: player.isPlaying)
        }
        .buttonStyle(PressScaleStyle(scale: 0.88))
        .onHover { hover = $0 }
        .help(player.isPlaying ? "Pause (Leertaste)" : "Abspielen (Leertaste)")
        .accessibilityLabel(player.isPlaying ? "Pause" : "Abspielen")
    }
}

// MARK: - Werkzeuge rechts

private struct MiniTools: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    let size: MiniPlayerSize
    let inlineVolume: Bool

    var body: some View {
        let panel = model.sidePanel
        HStack(spacing: 2) {
            MiniPitchButton()
            MiniEqButton()
            if inlineVolume {
                MiniVolumeInline().frame(width: 136)
            } else {
                MiniVolumeButton()
            }
            IconTap(icon: Icons.lyrics, label: panel == .lyrics ? "Liedtext ausblenden (⌘L)" : "Liedtext einblenden (⌘L)",
                    tint: panel == .lyrics ? colors.accentText : colors.textPrimary, iconSize: 18, touch: 30) { toggle(.lyrics) }
            IconTap(icon: Icons.queue, label: panel == .queue ? "Warteschlange ausblenden (⌥⌘U)" : "Warteschlange einblenden (⌥⌘U)",
                    tint: panel == .queue ? colors.accentText : colors.textPrimary, iconSize: 18, touch: 30) { toggle(.queue) }
            IconTap(icon: size == .large ? PlayerIcons.expandLess : PlayerIcons.unfoldMore,
                    label: "Mini-Player-Größe: \(size.label) – zu „\(nextSize.label)“ wechseln", tint: colors.textSecondary, iconSize: 17, touch: 30) {
                model.settings.miniPlayerSize = nextSize
            }
            MiniMoreMenu(size: size)
            IconTap(icon: Icons.openFull, label: "Großen Player öffnen (⌘⇧F)", iconSize: 15, touch: 30) { model.playerOpen = true }
        }
    }

    private var nextSize: MiniPlayerSize {
        switch size {
        case .compact: return .standard
        case .standard: return .large
        case .large: return .compact
        }
    }

    private func toggle(_ p: SidePanel) {
        model.sidePanel = model.sidePanel == p ? nil : p
    }
}

/// Kapsel-Beschriftung für Popover-Schalter (Symbol + optional Wert).
private struct MiniChip: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.isEnabled) private var enabled
    let icon: String
    let text: String?
    let active: Bool
    @State private var hover = false

    var body: some View {
        let fg = active ? colors.accentText : colors.textPrimary
        HStack(spacing: 4) {
            Icon(icon, size: 16, color: fg.opacity(enabled ? 1 : 0.35))
            if let text {
                Text(text)
                    .font(Typo.inter(11.5, .semibold))
                    .monospacedDigit()
                    .foregroundColor(fg)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, text == nil ? 0 : 8)
        .frame(minWidth: 30, minHeight: 28)
        .background(Capsule().fill(active ? colors.accentSoft : colors.textPrimary.opacity(hover ? 0.08 : 0)))
        .contentShape(Capsule())
        .onHover { hover = $0 }
    }
}

/// Tonhöhe: Kapsel mit aktuellem Wert, Popover mit Feineinstellung.
private struct MiniPitchButton: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService

    var body: some View {
        let pitch = model.settings.pitch
        let tempoText: String = pitch.mode == .key && pitch.tempo != 1 ? " · Tempo \(Formatting.percent(pitch.tempo))" : ""
        GlassMenuButton(help: "Tonhöhe: \(Formatting.semitones(pitch.semitones))\(tempoText) (\(pitch.mode.label))", arrowEdge: .top, width: 320, label: {
            MiniChip(icon: pitch.mode == .key ? Icons.pitch : Icons.vinyl, text: PitchText.short(pitch.semitones), active: !pitch.isOriginal)
        }) { _ in
            PitchControls(compact: true)
                .padding(8)
                .environmentObject(model)
                .environmentObject(player)
        }
    }
}

/// Equalizer: Symbol (aktiv = Rosé), Popover mit Ein/Aus, Presets, Kurve und Weg zu allen Einstellungen.
private struct MiniEqButton: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService

    var body: some View {
        let fx = model.settings.effects
        let active = (fx.eqEnabled && !fx.isEqNeutral) || fx.bassDb != 0
        GlassMenuButton(help: "Equalizer: \(EqualizerText.summary(fx, userPresets: model.settings.eqUserPresets))", arrowEdge: .top, width: 340, label: {
            MiniChip(icon: Icons.tune, text: nil, active: active)
        }) { menu in
            EqualizerQuickPanel(close: menu.close)
                .padding(8)
                .environmentObject(model)
                .environmentObject(player)
        }
    }
}

/// Lautstärke-Texte.
enum VolumeText {
    static func percent(_ v: Double) -> String { "\(Int((v * 100).rounded())) %" }

    static func help(_ v: Double) -> String {
        v > 1.001 ? "Lautstärke \(percent(v)) – digitale Verstärkung, der Limiter verhindert Übersteuern" : "Lautstärke \(percent(v))"
    }
}

/// Lautstärke direkt in der Leiste.
private struct MiniVolumeInline: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors

    var body: some View {
        let maxV = max(1, Double(model.settings.maxVolume))
        let v = min(Double(player.liveVolume), maxV)
        HStack(spacing: 4) {
            IconTap(icon: v == 0 ? Icons.volumeOff : (v > 1.001 ? PlayerIcons.volumeUp : Icons.volumeDown), label: v == 0 ? "Ton an" : "Stumm",
                    tint: v > 1.001 ? colors.accentText : colors.textSecondary, iconSize: 16, touch: 26) {
                let target: Float = v == 0 ? 1 : 0
                player.setLiveVolume(target)
                model.settings.effects.volume = target
            }
            MusicSlider(value: Binding(get: { v }, set: { raw in
                let snapped: Double = abs(raw - 1) < 0.03 ? 1 : raw
                player.setLiveVolume(Float(snapped))
            }), range: 0...maxV, marker: maxV > 1 ? 1 : nil, activeColor: colors.textPrimary.opacity(0.75), step: 0.01,
                        label: "Lautstärke", valueText: VolumeText.percent(v)) { editing in
                if !editing { model.settings.effects.volume = player.liveVolume }
            }
        }
        .help(VolumeText.help(v))
    }
}

/// Lautstärke als Popover (schmale Fenster).
private struct MiniVolumeButton: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService

    var body: some View {
        let v = Double(player.liveVolume)
        let icon: String = v == 0 ? Icons.volumeOff : (v > 1.001 ? PlayerIcons.volumeUp : Icons.volumeDown)
        GlassMenuButton(help: VolumeText.help(v), arrowEdge: .top, width: 290, label: {
            MiniChip(icon: icon, text: abs(v - 1) < 0.005 ? nil : VolumeText.percent(v), active: v > 1.001)
        }) { _ in
            VolumePopoverContent()
                .padding(8)
                .environmentObject(model)
                .environmentObject(player)
        }
    }
}

/// Inhalt des Lautstärke-Popovers: Wert, Regler bis zur eingestellten Obergrenze, Hinweis zur Verstärkung.
struct VolumePopoverContent: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors

    var body: some View {
        let maxV = max(1, Double(model.settings.maxVolume))
        let v = min(Double(player.liveVolume), maxV)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Lautstärke").textStyle(Typo.titleSmall).foregroundColor(colors.textPrimary)
                Spacer()
                Text(VolumeText.percent(v))
                    .font(Typo.inter(13, .semibold))
                    .monospacedDigit()
                    .foregroundColor(v > 1.001 ? colors.accentText : colors.textSecondary)
            }
            MusicSlider(value: Binding(get: { v }, set: { raw in
                let snapped: Double = abs(raw - 1) < 0.03 ? 1 : raw
                player.setLiveVolume(Float(snapped))
            }), range: 0...maxV, marker: maxV > 1 ? 1 : nil, step: 0.01, label: "Lautstärke", valueText: VolumeText.percent(v)) { editing in
                if !editing { model.settings.effects.volume = player.liveVolume }
            }
            Text(v > 1.001 ? "Digitale Verstärkung aktiv – der Limiter begrenzt Spitzen, damit nichts verzerrt."
                 : (maxV > 1 ? "Über 100 % verstärkt die App digital (bis \(VolumeText.percent(maxV)))." : "Obergrenze 100 % (in den Einstellungen änderbar)."))
                .textStyle(Typo.bodySmall)
                .foregroundColor(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ChoiceChip(title: "Stumm", selected: v == 0) {
                    player.setLiveVolume(0)
                    model.settings.effects.volume = 0
                }
                ChoiceChip(title: "100 %", selected: abs(v - 1) < 0.005) {
                    player.setLiveVolume(1)
                    model.settings.effects.volume = 1
                }
            }
        }
    }
}

/// Optionen des Mini-Players: Größe, Design anzeigen, Player-Design, Fenster.
private struct MiniMoreMenu: View {
    @EnvironmentObject private var model: AppModel
    let size: MiniPlayerSize

    var body: some View {
        GlassMenuButton(icon: Icons.moreHoriz, help: "Mini-Player-Optionen", iconSize: 18, touch: 30, arrowEdge: .top, width: 260) { menu in
            GlassMenuHeader(title: "Größe")
            ForEach(MiniPlayerSize.allCases, id: \.self) { s in
                GlassMenuItem(title: s.label, checked: s == size) {
                    model.settings.miniPlayerSize = s
                    menu.close()
                }
            }
            GlassMenuItem(title: "Player-Design im Mini-Player", icon: PlayerIcons.visibility, checked: model.settings.miniPlayerShowsDesign) {
                model.settings.miniPlayerShowsDesign.toggle()
            }
            GlassMenuDivider()
            GlassMenuDisclosure(title: "Player-Design", icon: PlayerIcons.palette) {
                ForEach(PlayerTheme.allCases, id: \.self) { theme in
                    GlassMenuItem(title: theme.label, icon: theme.uiIcon, checked: model.settings.playerTheme == theme) {
                        model.settings.playerTheme = theme
                    }
                }
            }
            GlassMenuDivider()
            GlassMenuItem(title: "Mini-Player-Fenster", icon: Icons.miniPlayer, detail: "⌥⌘M") {
                menu.close()
                WindowRouter.shared.openMiniPlayer()
            }
            GlassMenuItem(title: "Equalizer-Fenster", icon: Icons.tune, detail: "⌥⌘E") {
                menu.close()
                WindowRouter.shared.openEqualizer()
            }
        }
    }
}

// MARK: - Bausteine (auch Mini-Player-Fenster und Menüleiste)

/// Feine Fortschrittslinie (kompakte Größe).
private struct MiniProgressLine: View {
    @EnvironmentObject private var player: PlayerService

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
            .accessibilityHidden(true)
        }
    }
}

/// Zeitleiste mit verstellbarer Position.
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
                .disabled(clock.durationMs <= 0)
                Text("−" + Formatting.duration(max(0, clock.durationMs - Int64(value))))
                    .textStyle(Typo.time)
                    .monospacedDigit()
                    .foregroundColor(colors.textTertiary)
                    .frame(width: 42, alignment: .leading)
            }
        }
    }
}

/// Zufall · Zurück · Play/Pause · Weiter · Wiederholen (Mini-Player-Fenster, Menüleiste).
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

/// Lautstärke (bis zur eingestellten Obergrenze, Markierung bei 100 %; darüber digitale Verstärkung mit Limiter).
struct VolumeControl: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    var tint: Color? = nil
    var showsPercent = false

    var body: some View {
        let maxV = max(1, Double(model.settings.maxVolume))
        let v = min(Double(player.liveVolume), maxV)
        HStack(spacing: 6) {
            IconTap(icon: v == 0 ? Icons.volumeOff : Icons.volumeDown, label: v == 0 ? "Ton an" : "Stumm", tint: tint ?? colors.textSecondary, iconSize: 16, touch: 26) {
                let target: Float = v == 0 ? 1 : 0
                player.setLiveVolume(target)
                model.settings.effects.volume = target
            }
            MusicSlider(value: Binding(get: { v }, set: { raw in
                let snapped: Double = abs(raw - 1) < 0.03 ? 1 : raw
                player.setLiveVolume(Float(snapped))
            }), range: 0...maxV, marker: maxV > 1 ? 1 : nil,
                        activeColor: (tint ?? colors.textPrimary).opacity(0.75), step: 0.01, label: "Lautstärke",
                        valueText: VolumeText.percent(v)) { editing in
                if !editing { model.settings.effects.volume = player.liveVolume }
            }
            if showsPercent {
                Text(VolumeText.percent(v))
                    .textStyle(Typo.time)
                    .monospacedDigit()
                    .foregroundColor(v > 1.001 ? colors.accentText : (tint ?? colors.textTertiary))
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .help(VolumeText.help(v))
    }
}
