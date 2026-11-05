import SwiftUI
import AppKit
import MLCore
import MLRender

/// Blätter des Vollbild-Players (Spec 8).
enum PlayerSheet: String, Identifiable {
    case equalizer, pitch, sleep, queue, info, design
    var id: String { rawValue }
}

/// Vollbild-Player (Android `FullPlayer`): Hintergrund und Mittelstück je Design, Titelangaben, Fortschritt,
/// Wiedergabetasten, Lautstärke, Werkzeugleiste. Die vier Designs teilen Bedienung und Wiedergabelogik.
struct FullPlayerView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var appColors
    @StateObject private var artwork = NowPlayingArtwork()
    @State private var sheet: PlayerSheet?
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        let theme = model.settings.playerTheme
        let colors = MusicColors.forPlayer(theme, app: appColors)
        GeometryReader { geo in
            ZStack {
                PlayerBackground(theme: theme, artwork: artwork)
                    .environment(\.musicColors, colors)
                    .ignoresSafeArea()
                let showBars = model.settings.visualizer && theme != .cassette && !reduceMotion
                let landscape = geo.size.width > geo.size.height && geo.size.width >= 560
                if landscape {
                    let barSpace: CGFloat = showBars ? 34 : 0
                    let maxHeight: CGFloat = geo.size.height - 64 - barSpace
                    let side: CGFloat = max(200, min(maxHeight, geo.size.width * 0.48))
                    HStack(spacing: 24) {
                        VStack(spacing: 8) {
                            PlayerHero(theme: theme, side: side, artwork: artwork)
                                .frame(width: side, height: side)
                            if showBars {
                                SpectrumBars(color: colors.accent)
                                    .frame(width: side * 0.72, height: 26)
                            }
                        }
                        .gesture(closeDrag)
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 8) {
                                PlayerHeader(sheet: $sheet)
                                PlayerControls(theme: theme, sheet: $sheet)
                            }
                            .padding(.vertical, 8)
                            .frame(maxWidth: 560)
                            .frame(minHeight: geo.size.height - 40)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 30)
                    .padding(.bottom, 10)
                } else {
                    let reserved: CGFloat = 52 + 418 + (showBars ? 34 : 0)
                    let side = max(200, min(geo.size.width - 44, geo.size.height - reserved, 520))
                    let free = max(0, geo.size.height - reserved - side)
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            PlayerHeader(sheet: $sheet)
                                .gesture(closeDrag)
                            Spacer().frame(height: min(28, max(4, free / 2)))
                            PlayerHero(theme: theme, side: side, artwork: artwork)
                                .frame(width: side, height: side)
                            if showBars {
                                SpectrumBars(color: colors.accent)
                                    .frame(width: (geo.size.width - 44) * 0.72, height: 26)
                                    .padding(.top, 8)
                            }
                            Spacer().frame(height: min(28, max(10, free / 2)))
                            PlayerControls(theme: theme, sheet: $sheet)
                                .frame(maxWidth: 560)
                            Spacer().frame(height: 12)
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 30)
                    }
                }
            }
            .environment(\.musicColors, colors)
            .offset(y: max(0, dragOffset))
        }
        .task(id: player.current?.coverKey) { await artwork.update(for: player.current) }
        .sheet(item: $sheet) { s in
            PlayerSheetHost(sheet: s, theme: theme, artwork: artwork)
                .environmentObject(model)
                .environmentObject(player)
                .environment(\.musicColors, colors)
                .preferredColorScheme(colors.dark ? .dark : .light)
        }
        .onAppear { player.setVisualizer(model.settings.visualizer && !reduceMotion) }
        .onDisappear { player.setVisualizer(false) }
        .onChange(of: model.settings.visualizer) { on in player.setVisualizer(on && !reduceMotion) }
    }

    /// Ziehen nach unten schließt (Spec 1.1: > 20 % der Höhe oder schnell).
    private var closeDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { g in dragOffset = max(0, g.translation.height) }
            .onEnded { g in
                let fast = g.predictedEndTranslation.height - g.translation.height > 180
                if g.translation.height > 160 || fast {
                    model.playerOpen = false
                }
                withAnimation(Motion.standardSpring) { dragOffset = 0 }
            }
    }
}

// MARK: - Hintergrund

struct PlayerBackground: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.glassEnabled) private var glass
    let theme: PlayerTheme
    @ObservedObject var artwork: NowPlayingArtwork

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                switch theme {
                case .vinylStudio:
                    AmbientBackground()
                    if let img = artwork.image, glass {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: w, height: h)
                            .scaleEffect(1.25)
                            .blur(radius: 90, opaque: true)
                            .opacity(colors.dark ? 0.85 : 0.75)
                            .clipped()
                            .transition(.opacity)
                            .id(artwork.key)
                        LinearGradient(colors: [colors.background.opacity(colors.dark ? 0.52 : 0.58), colors.background.opacity(colors.dark ? 0.80 : 0.84)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    RadialGradient(colors: [Color.white.opacity(colors.dark ? 0.07 : 0.22), .clear],
                                   center: UnitPoint(x: 0.28, y: 0.12), startRadius: 0, endRadius: 0.95 * w)
                case .classic:
                    let p = artwork.palette
                    LinearGradient(colors: [Color(argb: p.top), Color(argb: p.bottom)], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [Color(argb: p.glow).opacity(0.30), .clear], center: UnitPoint(x: 0.5, y: 0.30), startRadius: 0, endRadius: 0.9 * w)
                    LinearGradient(stops: [.init(color: .clear, location: 0.55), .init(color: Color.black.opacity(0.35), location: 1)], startPoint: .top, endPoint: .bottom)
                case .cassette:
                    LinearGradient(colors: [Color(argb: 0xFF2A2224), Color(argb: 0xFF161213), Color(argb: 0xFF0E0B0C)], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [Color(argb: 0x24FFB8A0), .clear], center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: 1.1 * w)
                    Canvas { ctx, size in
                        var y: CGFloat = 0
                        var i = 0
                        while y < size.height * 0.62 {
                            ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Color.white.opacity(i % 3 == 0 ? 0.018 : 0.008)))
                            y += 3
                            i += 1
                        }
                    }
                case .portableCD:
                    AmbientBackground()
                    RadialGradient(colors: [Color(argb: artwork.palette.glow).opacity(colors.dark ? 0.22 : 0.16), .clear],
                                   center: UnitPoint(x: 0.5, y: 0.30), startRadius: 0, endRadius: 0.85 * w)
                    RadialGradient(colors: [Color.white.opacity(colors.dark ? 0.05 : 0.30), .clear],
                                   center: UnitPoint(x: 0.2, y: 0.04), startRadius: 0, endRadius: w)
                }
            }
            .animation(.easeInOut(duration: 0.6), value: artwork.key)
        }
    }
}

// MARK: - Mittelstück je Design

struct PlayerHero: View {
    let theme: PlayerTheme
    let side: CGFloat
    @ObservedObject var artwork: NowPlayingArtwork

    var body: some View {
        ZStack {
            switch theme {
            case .vinylStudio: VinylHero(side: side, artwork: artwork)
            case .classic: ClassicHero(side: side, artwork: artwork)
            case .cassette: CassetteHero(side: side, artwork: artwork, showStatus: true)
            case .portableCD: CDHero(side: side, artwork: artwork)
            }
        }
        .id(theme)
        .transition(.opacity)
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.42), value: theme)
    }
}

// MARK: - Kopfzeile (Spec 1.4)

struct PlayerHeader: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    @Binding var sheet: PlayerSheet?

    var body: some View {
        let source = player.queue.source
        let single = source == nil || source?.kind == .singleTrack
        let size = player.queue.count
        let index = player.queue.currentPlayPosition ?? 0
        let kind: String = single ? "WIEDERGABE" : "SPIELT AUS"
        let position: String = size > 1 ? " · \(index + 1) VON \(size)" : ""
        HStack(spacing: 0) {
            GlassIconButton(icon: Icons.expandMore, label: "Player schließen (Esc)", size: 38, iconSize: 22) { model.playerOpen = false }
            VStack(spacing: 1) {
                Text(kind + position)
                    .textStyle(Typo.sectionLabel)
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(1)
                Text(!single ? (source?.label ?? "") : (size > 1 ? "Einzelner Titel mit Warteschlange" : "Einzelner Titel"))
                    .textStyle(Typo.labelLarge)
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                if let timer = player.sleepTimer {
                    HStack(spacing: 3) {
                        Icon(Icons.sleepFill, size: 11, color: colors.accentText)
                        Text(timer.endOfTrack ? "Titelende" : Formatting.countdown(player.sleepRemainingMs ?? 0))
                            .textStyle(Typo.time)
                            .monospacedDigit()
                            .foregroundColor(colors.accentText)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            Menu {
                Button("Zu Playlist hinzufügen …") { if let c = player.current { model.addToPlaylistUids = [c.uid] } }
                if let c = player.current, model.index.albumKeyByTrack[c.uid] != nil {
                    Button("Album öffnen") { model.openAlbum(of: c) }
                }
                if let c = player.current, let a = c.artists.first {
                    Button("Interpret öffnen") { model.openArtist(named: a) }
                }
                Divider()
                Button("Player-Design …") { sheet = .design }
                Button(model.settings.visualizer ? "Klangvisualisierung aus" : "Klangvisualisierung an") { model.settings.visualizer.toggle() }
                Divider()
                Button("Songinformationen") { sheet = .info }
                Button("Informationen bearbeiten …") { if let c = player.current { model.showInfo([c.uid]) } }
                Button("Mini-Player-Fenster") { WindowRouter.shared.openMiniPlayer() }
            } label: {
                Icon(Icons.more, size: 22, color: colors.textPrimary)
                    .frame(width: 38, height: 38)
                    .glassSurface(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Weitere Aktionen")
        }
        .frame(height: 52)
    }
}

// MARK: - Bedienelemente (Spec 1.5)

struct PlayerControls: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    let theme: PlayerTheme
    @Binding var sheet: PlayerSheet?

    var body: some View {
        VStack(spacing: 0) {
            titleRow
            Spacer().frame(height: 14)
            SeekArea(clock: player.clock)
            Spacer().frame(height: 6)
            switch theme {
            case .vinylStudio, .classic: IconTransport()
            case .cassette: DeckKeys()
            case .portableCD: CDButtons()
            }
            Spacer().frame(height: 10)
            PlayerVolume()
            Spacer().frame(height: 14)
            PlayerToolbar(sheet: $sheet)
        }
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                if let t = player.current {
                    MarqueeText(text: t.displayTitle, font: Typo.inter(Typo.headlineSmall.size + 3, .bold, display: true), color: colors.textPrimary)
                        .frame(height: 30)
                    Text(t.artistText ?? "Unbekannter Interpret")
                        .textStyle(Typo.titleMedium)
                        .foregroundColor(colors.accentText)
                        .lineLimit(1)
                    Button { model.openAlbum(of: t) } label: {
                        Text(t.album ?? "Unbekanntes Album")
                            .textStyle(Typo.bodyMedium)
                            .foregroundColor(colors.textSecondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.index.albumKeyByTrack[t.uid] == nil)
                    .help("Album öffnen")
                }
            }
            .id(player.current?.uid)
            .transition(.opacity)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeOut(duration: 0.28), value: player.current?.uid)
            if let t = player.current {
                HeartButton(favorite: model.isFavorite(t.uid), iconSize: 22, touch: 44, inactiveTint: colors.textPrimary.opacity(0.7), subject: "„\(t.displayTitle)“") {
                    model.toggleFavorite([t.uid])
                }
                .glassSurface(Circle())
            }
        }
    }
}

/// Endlose Laufschrift für lange Titel (Start nach 2,5 s, Pause 2,5 s, 30 pt/s, Abstand ⅓ Breite).
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    @State private var textWidth: CGFloat = 0
    @State private var start = Date()

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let overflow = textWidth > w + 1
            ZStack(alignment: .leading) {
                if overflow && !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                        let gap = w / 3
                        let distance = textWidth + gap
                        let travel = Double(distance) / 30
                        let cycle = 2.5 + travel
                        let t = ctx.date.timeIntervalSince(start)
                        let phase = t < 2.5 ? 0 : (t - 2.5).truncatingRemainder(dividingBy: cycle)
                        let x = phase < travel ? -CGFloat(phase * 30) : 0
                        HStack(spacing: gap) {
                            label
                            label
                        }
                        .offset(x: x)
                    }
                } else {
                    label
                }
            }
            .frame(width: w, alignment: .leading)
            .clipped()
            .mask(LinearGradient(stops: overflow ? [.init(color: .black, location: 0), .init(color: .black, location: 0.92), .init(color: .clear, location: 1)] : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
        }
        .onChange(of: text) { _ in start = Date() }
        .accessibilityLabel(text)
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundColor(color)
            .lineLimit(1)
            .fixedSize()
            .background(GeometryReader { g in Color.clear.onAppear { textWidth = g.size.width }.onChange(of: g.size.width) { textWidth = $0 } })
    }
}

/// Fortschritt mit Zeiten, Zufall und Wiederholen (Spec 1.5 Punkt 3).
struct SeekArea: View {
    @EnvironmentObject private var player: PlayerService
    @ObservedObject var clock: PlaybackClock
    @Environment(\.musicColors) private var colors
    @State private var drag: Double?
    @State private var held: (value: Double, until: Date)?

    var body: some View {
        let duration = Double(max(clock.durationMs, 0))
        let reported = duration > 0 ? Double(clock.positionMs) / duration : 0
        let shownFraction: Double = {
            if let drag { return drag }
            if let held, Date() < held.until, abs(held.value * duration - Double(clock.positionMs)) > 1200 { return held.value }
            return reported
        }()
        let shownMs = Int64(shownFraction * duration)
        VStack(spacing: 2) {
            MusicSlider(value: Binding(get: { shownFraction }, set: { drag = $0 }), range: 0...1,
                        label: "Wiedergabeposition", valueText: Formatting.duration(shownMs)) { editing in
                if !editing, let v = drag {
                    player.seek(to: Int64(v * duration))
                    held = (v, Date().addingTimeInterval(1.5))
                    drag = nil
                }
            }
            .disabled(duration == 0)
            HStack(spacing: 0) {
                Text(Formatting.duration(shownMs))
                    .textStyle(Typo.time)
                    .monospacedDigit()
                    .foregroundColor(colors.textSecondary)
                    .frame(width: 56, alignment: .leading)
                Spacer()
                IconTap(icon: Icons.shuffle, label: player.shuffleEnabled ? "Zufallswiedergabe aus" : "Zufallswiedergabe an",
                        tint: player.shuffleEnabled ? colors.accentText : colors.textSecondary, iconSize: 19, touch: 36) { player.toggleShuffle() }
                Spacer().frame(width: 18)
                IconTap(icon: player.repeatMode == .one ? Icons.repeatOne : Icons.repeatAll, label: player.repeatMode.label,
                        tint: player.repeatMode != .off ? colors.accentText : colors.textSecondary, iconSize: 19, touch: 36) { player.cycleRepeat() }
                Spacer()
                Text("−" + Formatting.duration(max(0, clock.durationMs - shownMs)))
                    .textStyle(Typo.time)
                    .monospacedDigit()
                    .foregroundColor(colors.textSecondary)
                    .frame(width: 56, alignment: .trailing)
            }
        }
    }
}

/// Stil ICONS (Vinyl, Classic): −10 s · vorheriger · Play/Pause · nächster · +10 s.
struct IconTransport: View {
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors

    var body: some View {
        HStack {
            // Group: höchstens 10 direkte Elemente je ViewBuilder unter macOS 13
            Group {
                Spacer()
                IconTap(icon: Icons.replay10, label: "10 Sekunden zurück", tint: colors.textSecondary, iconSize: 24, touch: 44) { player.skip(by: -10) }
                Spacer()
            }
            IconTap(icon: Icons.previous, label: "Vorheriger Titel bzw. Titelanfang", iconSize: 36, touch: 54) { player.previous() }
            Spacer()
            Button { player.togglePlay() } label: {
                Icon(player.isPlaying ? Icons.pause : Icons.play, size: 52, color: colors.textPrimary)
                    .frame(width: 70, height: 70)
                    .contentShape(Circle())
                    .animation(.easeOut(duration: 0.16), value: player.isPlaying)
            }
            .buttonStyle(PressScaleStyle(scale: 0.86))
            .accessibilityLabel(player.isPlaying ? "Pause" : "Abspielen")
            Spacer()
            IconTap(icon: Icons.next, label: "Nächster Titel", iconSize: 36, touch: 54) { player.next() }
                .disabled(!player.queue.hasNext)
            Spacer()
            IconTap(icon: Icons.forward10, label: "10 Sekunden vor", tint: colors.textSecondary, iconSize: 24, touch: 44) { player.skip(by: 10) }
            Spacer()
        }
        .frame(height: 76)
    }
}

/// Lautstärke mit Prozentanzeige und Hinweis bei Verstärkung (Spec 1.5 Punkt 7).
struct PlayerVolume: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors

    var body: some View {
        let v = Double(player.liveVolume)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                IconTap(icon: v == 0 ? Icons.volumeOff : Icons.volumeDown, label: "Lautstärke auf 100 %", tint: colors.textSecondary, iconSize: 18, touch: 34) {
                    player.setLiveVolume(1)
                    model.settings.effects.volume = 1
                }
                MusicSlider(value: Binding(get: { v }, set: { raw in
                    let snapped = abs(raw - 1) < 0.04 ? 1 : (raw * 20).rounded() / 20
                    player.setLiveVolume(Float(snapped))
                }), range: 0...Double(AudioEffectsSettings.maxVolume), marker: 1, label: "Lautstärke", valueText: "\(Int((v * 100).rounded())) %") { editing in
                    if !editing { model.settings.effects.volume = player.liveVolume }
                }
                .padding(.horizontal, 4)
                Text("\(Int((v * 100).rounded())) %")
                    .textStyle(Typo.time)
                    .monospacedDigit()
                    .foregroundColor(v > 1 ? colors.accentText : colors.textSecondary)
                    .frame(width: 48, alignment: .trailing)
            }
            if v > 1 {
                Text("Digitale Verstärkung über 100 % aktiv · Limiter begrenzt Spitzen")
                    .textStyle(Typo.labelSmall)
                    .foregroundColor(colors.textSecondary)
                    .padding(.leading, 40)
            }
        }
    }
}

/// Werkzeugleiste: Equalizer · Tonhöhe · Sleep-Timer · Liste · Info (Spec 1.5 Punkt 9).
struct PlayerToolbar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    @Binding var sheet: PlayerSheet?

    var body: some View {
        let fx = model.settings.effects
        let eqActive = (fx.eqEnabled && !fx.isEqNeutral) || fx.bassDb != 0
        let eqLabel: String = {
            if fx.eqEnabled && !fx.isEqNeutral { return fx.activePreset?.name ?? "Eigen" }
            if fx.bassDb != 0 { return "Bass " + short(fx.bassDb) }
            return "Equalizer"
        }()
        let pitch = model.settings.pitch
        let pitchActive = !pitch.isOriginal
        let pitchLabel: String = {
            if pitch.semitones != 0 { return short(pitch.semitones) + " HT" }
            if pitch.tempo != 1 && pitch.mode == .key { return "Tempo \(Int((pitch.tempo * 100).rounded())) %" }
            return "Tonhöhe"
        }()
        let timerLabel: String = {
            guard let t = player.sleepTimer else { return "Timer" }
            return t.endOfTrack ? "Titelende" : Formatting.countdown(player.sleepRemainingMs ?? 0)
        }()
        HStack(spacing: 0) {
            item(Icons.tune, eqLabel, eqActive) { sheet = .equalizer }
            item(Icons.pitch, pitchLabel, pitchActive) { sheet = .pitch }
            item(player.sleepTimer != nil ? Icons.sleepFill : Icons.sleep, timerLabel, player.sleepTimer != nil) { sheet = .sleep }
            item(Icons.queue, "Liste", false) { sheet = .queue }
            item(Icons.info, "Info", false) { sheet = .info }
        }
        .padding(6)
        .frame(height: 68)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.bar, style: .continuous), strong: true)
    }

    private func item(_ icon: String, _ label: String, _ active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Icon(icon, size: 21, color: active ? colors.accentText : colors.textPrimary)
                    .frame(width: 40, height: 28)
                    .background(Capsule().fill(active ? colors.accentSoft : .clear))
                Text(label)
                    .textStyle(Typo.labelSmall)
                    .foregroundColor(active ? colors.accentText : colors.textSecondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.94))
        .help(label)
    }

    /// Kurzzahl („+2“, „−1,5“).
    private func short(_ v: Float) -> String {
        let r = (v * 10).rounded() / 10
        let sign = r > 0 ? "+" : (r < 0 ? "−" : "")
        let a = abs(r)
        let num = a == a.rounded() ? String(Int(a)) : String(format: "%.1f", a).replacingOccurrences(of: ".", with: ",")
        return sign + num
    }
}
