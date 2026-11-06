import SwiftUI
import AppKit
import MLCore
import MLRender

/// Blätter des Vollbild-Players (Spec 8).
enum PlayerSheet: String, Identifiable {
    case equalizer, pitch, sleep, queue, info, design
    var id: String { rawValue }
}

/// Inhalt, der im großen Player anstelle des Mittelstücks erscheint (Liedtext, Warteschlange).
enum PlayerOverlay: String, Hashable {
    case lyrics, queue
}

/// Vollbild-Player (Android `FullPlayer`, v2): Hintergrund und Mittelstück je Design (sieben Designs),
/// Titelangaben, Fortschritt, Wiedergabetasten, Lautstärke mit Verstärkung, Werkzeugleiste. Alle Designs teilen
/// Bedienung und Wiedergabelogik; der Wechsel wird weich überblendet.
struct FullPlayerView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var appColors
    @StateObject private var artwork = NowPlayingArtwork()
    @State private var sheet: PlayerSheet?
    @State private var overlay: PlayerOverlay?
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        let theme = model.settings.playerTheme
        // v2.1: Hintergrund „Automatisch“ = bisheriger Farbsatz; feste/eigene Farben mit passender Schrift
        let background = model.settings.playerBackground
        let custom = model.settings.playerBackgroundCustom
        let colors = MusicColors.forPlayer(theme, app: appColors, background: background, custom: custom)
        GeometryReader { geo in
            ZStack {
                PlayerBackground(theme: theme, artwork: artwork, style: background, custom: custom)
                    .environment(\.musicColors, colors)
                    .id(theme)
                    .transition(.opacity)
                    .ignoresSafeArea()
                PlayerStage(size: geo.size, theme: theme, artwork: artwork, sheet: $sheet, overlay: $overlay, dragOffset: $dragOffset)
            }
            .animation(PlayerMotionPolicy.transition(model.settings), value: theme)
            .animation(PlayerMotionPolicy.transition(model.settings), value: background)
            // Oberer Rand: Fenster verschieben (der Inhalt beginnt erst darunter)
            .overlay(alignment: .top) {
                WindowDragArea().frame(height: 26)
            }
            .environment(\.musicColors, colors)
            // Classic, Cassette und Studio Reel sind immer dunkel: auch Glas, Popover und Systemelemente dunkel darstellen
            .environment(\.colorScheme, colors.dark ? .dark : .light)
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
        // v2.1: Die Pegelanalyse steuert AppModel aus den Einstellungen; die Anzeigen melden sich selbst an
        // (`visualizerConsumer`) – hier kein `setVisualizer` mehr.
    }
}

// MARK: - Aufbau (quer: Mittelstück links, Bedienung rechts; hoch: untereinander)

private struct PlayerStage: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    let size: CGSize
    let theme: PlayerTheme
    @ObservedObject var artwork: NowPlayingArtwork
    @Binding var sheet: PlayerSheet?
    @Binding var overlay: PlayerOverlay?
    @Binding var dragOffset: CGFloat

    var body: some View {
        let showBars = model.settings.visualizer && theme.uiShowsSpectrumBars && PlayerMotionPolicy.continuous(model.settings) && overlay == nil
        let landscape = size.width > size.height && size.width >= 560
        // Balken: neutrale Farbe auf farbigem Hintergrund (Rosé auf Rosa wäre kaum sichtbar), sonst Akzent
        let barColor: Color = model.settings.playerBackground == .auto ? colors.accent : colors.textPrimary.opacity(0.8)
        if landscape {
            let barSpace: CGFloat = showBars ? SpectrumLayout.height + 10 : 0
            let maxHeight: CGFloat = size.height - 64 - barSpace
            let side: CGFloat = max(200, min(maxHeight, size.width * 0.48))
            HStack(spacing: 28) {
                VStack(spacing: 10) {
                    HeroArea(theme: theme, side: side, artwork: artwork, overlay: $overlay)
                    if showBars {
                        SpectrumBars(color: barColor)
                            .frame(width: side * SpectrumLayout.widthFraction, height: SpectrumLayout.height)
                            .transition(.opacity)
                    }
                }
                .gesture(closeDrag, including: overlay == nil ? .all : .subviews)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        PlayerHeader(artwork: artwork, sheet: $sheet)
                        PlayerControls(theme: theme, sheet: $sheet, overlay: $overlay)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: 560)
                    .frame(minHeight: size.height - 40)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 28)
            .padding(.top, 30)
            .padding(.bottom, 10)
        } else {
            // 436: Bedienung inkl. Zeile mit Format und Hinzufügedatum (v2.1)
            let reserved: CGFloat = 52 + 436 + (showBars ? SpectrumLayout.height + 10 : 0)
            let side = max(200, min(size.width - 44, size.height - reserved, 520))
            let free = max(0, size.height - reserved - side)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    PlayerHeader(artwork: artwork, sheet: $sheet)
                        .gesture(closeDrag)
                    Spacer().frame(height: min(28, max(4, free / 2)))
                    HeroArea(theme: theme, side: side, artwork: artwork, overlay: $overlay)
                    if showBars {
                        SpectrumBars(color: barColor)
                            .frame(width: min(side, size.width - 44) * SpectrumLayout.widthFraction, height: SpectrumLayout.height)
                            .padding(.top, 10)
                            .transition(.opacity)
                    }
                    Spacer().frame(height: min(28, max(10, free / 2)))
                    PlayerControls(theme: theme, sheet: $sheet, overlay: $overlay)
                        .frame(maxWidth: 560)
                    Spacer().frame(height: 12)
                }
                .padding(.horizontal, 22)
                .padding(.top, 30)
            }
        }
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

/// Maße der Frequenzbalken unter dem Mittelstück (beide Anordnungen rechnen damit, nichts wird abgeschnitten).
private enum SpectrumLayout {
    static let height: CGFloat = 32
    static let widthFraction: CGFloat = 0.8
}

/// Mittelstück oder – auf Wunsch – Liedtext bzw. Warteschlange an seiner Stelle.
private struct HeroArea: View {
    let theme: PlayerTheme
    let side: CGFloat
    @ObservedObject var artwork: NowPlayingArtwork
    @Binding var overlay: PlayerOverlay?

    var body: some View {
        ZStack {
            if let kind = overlay {
                PlayerInlinePanel(kind: kind) { overlay = nil }
                    .frame(width: side, height: side)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                PlayerHero(theme: theme, side: side, artwork: artwork)
                    .frame(width: side, height: side)
                    .transition(.opacity)
            }
        }
        .frame(width: side, height: side)
        .animation(Motion.easeOut(0.32), value: overlay)
    }
}

/// Liedtext oder Warteschlange als Glasfläche im Player.
private struct PlayerInlinePanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    let kind: PlayerOverlay
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Icon(kind == .lyrics ? Icons.lyrics : Icons.queue, size: 17, color: colors.accentText)
                Text(kind == .lyrics ? "Liedtext" : "Warteschlange")
                    .textStyle(Typo.titleMedium)
                    .foregroundColor(colors.textPrimary)
                Spacer()
                IconTap(icon: Icons.close, label: kind == .lyrics ? "Liedtext schließen" : "Warteschlange schließen",
                        tint: colors.textSecondary, iconSize: 15, touch: 28, action: close)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
            switch kind {
            case .lyrics:
                LyricsPanel(fontSize: CGFloat(model.settings.lyricsFontSize) + 3, center: true)
            case .queue:
                QueuePanel()
            }
        }
        .glassSurface(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous), strong: true)
    }
}

// MARK: - Hintergrund

struct PlayerBackground: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.glassEnabled) private var glass
    let theme: PlayerTheme
    @ObservedObject var artwork: NowPlayingArtwork
    /// v2.1: gewählter Hintergrund (`auto` = bisheriges Verhalten je Design).
    var style: PlayerBackgroundStyle = .auto
    var custom: UInt32 = 0

    var body: some View {
        if let base = style.baseARGB(custom: custom) {
            PlayerColorBackground(style: style, base: base, light: style.isLight(custom: custom), artwork: artwork)
                .transition(.opacity)
        } else {
            themeBackground
                .transition(.opacity)
        }
    }

    /// Bisheriger Hintergrund je Design (unverändert).
    private var themeBackground: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                switch theme {
                case .vinylStudio:
                    AmbientBackground()
                    if let img = artwork.image, glass {
                        BlurredCover(image: img, width: w, height: h, opacity: colors.dark ? 0.85 : 0.75, key: artwork.key)
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
                    ScanLines(fraction: 0.62)
                case .portableCD:
                    AmbientBackground()
                    RadialGradient(colors: [Color(argb: artwork.palette.glow).opacity(colors.dark ? 0.22 : 0.16), .clear],
                                   center: UnitPoint(x: 0.5, y: 0.30), startRadius: 0, endRadius: 0.85 * w)
                    RadialGradient(colors: [Color.white.opacity(colors.dark ? 0.05 : 0.30), .clear],
                                   center: UnitPoint(x: 0.2, y: 0.04), startRadius: 0, endRadius: w)
                case .modernGlass:
                    ModernGlassBackground(artwork: artwork, width: w, height: h)
                case .aurora:
                    AuroraBackground(palette: artwork.palette, width: w)
                case .reelToReel:
                    LinearGradient(colors: [Color(argb: 0xFF231F21), Color(argb: 0xFF151214), Color(argb: 0xFF0B090A)], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [Color(argb: 0x2EFFC9A0), .clear], center: UnitPoint(x: 0.3, y: 0), startRadius: 0, endRadius: 0.95 * w)
                    RadialGradient(colors: [Color(argb: artwork.palette.glow).opacity(0.16), .clear], center: UnitPoint(x: 0.85, y: 0.95), startRadius: 0, endRadius: 0.7 * w)
                    ScanLines(fraction: 1)
                }
            }
            .animation(.easeInOut(duration: 0.6), value: artwork.key)
        }
    }
}

/// Farbiger Hintergrund (v2.1): Grundfarbe mit sanftem Verlauf, Glanz von oben, einem Lichtfeld im Farbton der
/// Fläche und etwas Tiefe nach unten – dieselben Schichten wie die Glas- und App-Hintergründe. „Rauchglas“ legt
/// das weichgezeichnete Cover gedämpft darunter (nur mit Glas-Effekten und ohne Leistungsmodus).
private struct PlayerColorBackground: View {
    @Environment(\.glassEnabled) private var glass
    @Environment(\.performanceMode) private var performance
    let style: PlayerBackgroundStyle
    let base: UInt32
    let light: Bool
    @ObservedObject var artwork: NowPlayingArtwork

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let fill = Color(argb: base)
            let tone = PaletteTone.color(base, hueShift: 0.05, minSaturation: 0, brightness: nil)
            ZStack {
                LinearGradient(colors: [ColorARGB.shade(base, light ? 0.05 : 0.08), fill, ColorARGB.shade(base, light ? -0.06 : -0.18)],
                               startPoint: .top, endPoint: .bottom)
                if style == .smokedGlass, glass, !performance, let img = artwork.image {
                    BlurredCover(image: img, width: w, height: h, opacity: 0.42, key: artwork.key)
                    fill.opacity(0.62)
                }
                RadialGradient(colors: [tone.opacity(light ? 0.30 : 0.40), .clear], center: UnitPoint(x: 0.86, y: 0.88), startRadius: 0, endRadius: 0.8 * w)
                RadialGradient(colors: [Color.white.opacity(light ? 0.34 : 0.10), .clear], center: UnitPoint(x: 0.24, y: 0.06), startRadius: 0, endRadius: 0.95 * w)
                LinearGradient(stops: [.init(color: .clear, location: 0.55), .init(color: Color.black.opacity(light ? 0.05 : 0.24), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .animation(.easeInOut(duration: 0.6), value: artwork.key)
            .animation(.easeInOut(duration: 0.35), value: base)
        }
    }
}

/// Weichgezeichnetes Cover als ruhender Hintergrund (bewegt sich nicht – nur beim Titelwechsel überblendet).
private struct BlurredCover: View {
    let image: NSImage
    let width: CGFloat
    let height: CGFloat
    let opacity: Double
    let key: String?

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: height)
            .scaleEffect(1.25)
            .blur(radius: 90, opaque: true)
            .opacity(opacity)
            .clipped()
            .transition(.opacity)
            .id(key)
    }
}

/// Feine waagerechte Linien (Kassette, Tonband) – einmal gezeichnet.
private struct ScanLines: View {
    let fraction: CGFloat

    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            var i = 0
            while y < size.height * fraction {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Color.white.opacity(i % 3 == 0 ? 0.018 : 0.008)))
                y += 3
                i += 1
            }
        }
        .allowsHitTesting(false)
    }
}

/// Modern Glass: App-Hintergrund, weichgezeichnetes Cover und Lichtfelder in den Coverfarben.
private struct ModernGlassBackground: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.glassEnabled) private var glass
    @ObservedObject var artwork: NowPlayingArtwork
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let lights = AuroraColors(palette: artwork.palette, dark: colors.dark)
        ZStack {
            AmbientBackground()
            if let img = artwork.image, glass {
                BlurredCover(image: img, width: width, height: height, opacity: colors.dark ? 0.55 : 0.45, key: artwork.key)
            }
            RadialGradient(colors: [lights.primary.opacity(colors.dark ? 0.30 : 0.26), .clear], center: UnitPoint(x: 0.2, y: 0.28), startRadius: 0, endRadius: 0.75 * width)
            RadialGradient(colors: [lights.secondary.opacity(colors.dark ? 0.22 : 0.2), .clear], center: UnitPoint(x: 0.88, y: 0.9), startRadius: 0, endRadius: 0.7 * width)
            LinearGradient(colors: [colors.background.opacity(colors.dark ? 0.30 : 0.36), colors.background.opacity(colors.dark ? 0.55 : 0.5)],
                           startPoint: .top, endPoint: .bottom)
        }
        .animation(.easeInOut(duration: 0.9), value: lights)
    }
}

/// Aurora: Nachthimmel (bzw. heller Morgenhimmel) mit ruhenden Polarlicht-Schleiern in den Coverfarben.
private struct AuroraBackground: View {
    @Environment(\.musicColors) private var colors
    let palette: CoverPalette
    let width: CGFloat

    var body: some View {
        let lights = AuroraColors(palette: palette, dark: colors.dark)
        let base: [Color] = colors.dark ? [Color(argb: 0xFF0D0B14), Color(argb: 0xFF07070B)] : [colors.background, Color(argb: 0xFFF2ECF3)]
        ZStack {
            LinearGradient(colors: base, startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [lights.primary.opacity(colors.dark ? 0.30 : 0.22), .clear], center: UnitPoint(x: 0.22, y: 0.12), startRadius: 0, endRadius: 0.8 * width)
            RadialGradient(colors: [lights.tertiary.opacity(colors.dark ? 0.22 : 0.15), .clear], center: UnitPoint(x: 0.85, y: 0.3), startRadius: 0, endRadius: 0.65 * width)
            RadialGradient(colors: [lights.secondary.opacity(colors.dark ? 0.2 : 0.15), .clear], center: UnitPoint(x: 0.5, y: 1.05), startRadius: 0, endRadius: 0.75 * width)
        }
        .animation(.easeInOut(duration: 0.9), value: lights)
    }
}

// MARK: - Mittelstück je Design

struct PlayerHero: View {
    @EnvironmentObject private var model: AppModel
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
            case .modernGlass: ModernGlassHero(side: side, artwork: artwork)
            case .aurora: AuroraHero(side: side, artwork: artwork)
            case .reelToReel: ReelToReelHero(side: side, artwork: artwork)
            }
        }
        .id(theme)
        .transition(PlayerMotionPolicy.themeTransition(model.settings))
    }
}

// MARK: - Kopfzeile (Spec 1.4)

struct PlayerHeader: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    @ObservedObject var artwork: NowPlayingArtwork
    @Binding var sheet: PlayerSheet?

    var body: some View {
        let source = player.queue.source
        let single = source == nil || source?.kind == .singleTrack
        let size = player.queue.count
        let index = player.queue.currentPlayPosition ?? 0
        let kind: String = single ? "WIEDERGABE" : "SPIELT AUS"
        let position: String = size > 1 ? " · \(index + 1) VON \(size)" : ""
        HStack(spacing: 8) {
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
                        Group {
                            if timer.endOfTrack {
                                Text("Titelende")
                            } else {
                                SleepCountdownText(clock: player.clock)
                            }
                        }
                        .textStyle(Typo.time)
                        .monospacedDigit()
                        .foregroundColor(colors.accentText)
                    }
                    .help("Sleep-Timer läuft")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            DesignMenuButton(artwork: artwork, sheet: $sheet)
            PlayerMoreMenu(sheet: $sheet)
        }
        .frame(height: 52)
    }
}

/// Runde Glas-Beschriftung für Menüschaltflächen in der Kopfzeile.
private struct HeaderGlassLabel: View {
    @Environment(\.musicColors) private var colors
    let icon: String
    var iconSize: CGFloat = 20

    var body: some View {
        Icon(icon, size: iconSize, color: colors.textPrimary)
            .frame(width: 38, height: 38)
            .contentShape(Circle())
            .glassSurface(Circle(), interactive: true)
    }
}

/// Player-Design wählen: Popover mit Vorschauen aller Designs.
private struct DesignMenuButton: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @ObservedObject var artwork: NowPlayingArtwork
    @Binding var sheet: PlayerSheet?

    var body: some View {
        GlassMenuButton(help: "Player-Design wählen (aktuell: \(model.settings.playerTheme.label))", width: 470, label: {
            HeaderGlassLabel(icon: PlayerIcons.palette, iconSize: 19)
        }) { menu in
            DesignQuickPicker(artwork: artwork, more: {
                menu.close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { sheet = .design }
            })
            .environmentObject(model)
            .environmentObject(player)
        }
    }
}

/// Weitere Aktionen (ersetzt das unsichtbare `Menu`).
private struct PlayerMoreMenu: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Binding var sheet: PlayerSheet?

    var body: some View {
        let current = player.current
        let hasAlbum = current.map { model.index.albumKeyByTrack[$0.uid] != nil } ?? false
        let artist = current?.artists.first
        GlassMenuButton(help: "Weitere Aktionen", width: 280, label: {
            HeaderGlassLabel(icon: Icons.more)
        }) { menu in
            Group {
                GlassMenuHeader(title: "Titel")
                GlassMenuItem(title: "Zu Playlist hinzufügen …", icon: Icons.playlistAdd) {
                    menu.close()
                    if let c = current { model.addToPlaylistUids = [c.uid] }
                }
                GlassMenuItem(title: "Album öffnen", icon: Icons.album) {
                    menu.close()
                    if let c = current { model.openAlbum(of: c) }
                }
                .disabled(!hasAlbum)
                GlassMenuItem(title: "Interpret öffnen", icon: PlayerIcons.person) {
                    menu.close()
                    if let a = artist { model.openArtist(named: a) }
                }
                .disabled(artist == nil)
                GlassMenuItem(title: "Songinformationen", icon: Icons.info) { open(.info, menu) }
                GlassMenuItem(title: "Informationen bearbeiten …", icon: Icons.edit) {
                    menu.close()
                    if let c = current { model.showInfo([c.uid]) }
                }
            }
            GlassMenuDivider()
            Group {
                GlassMenuHeader(title: "Player")
                GlassMenuItem(title: "Player-Design …", icon: PlayerIcons.palette, detail: model.settings.playerTheme.label) { open(.design, menu) }
                // v2.1: Hintergrundfarbe direkt wählbar (Farbfelder, eigene Farbe über den Systemfarbwähler)
                GlassMenuDisclosure(title: "Hintergrund", icon: Icons.palette) {
                    PlayerBackgroundMenuSection(close: menu.close)
                        .environmentObject(model)
                }
                GlassMenuItem(title: "Klangvisualisierung", icon: Icons.equalizer, checked: model.settings.visualizer) {
                    model.settings.visualizer.toggle()
                }
                GlassMenuItem(title: "Sleep-Timer …", icon: Icons.sleep) { open(.sleep, menu) }
                GlassMenuItem(title: "Equalizer-Fenster", icon: Icons.tune, detail: "⌥⌘E") {
                    menu.close()
                    WindowRouter.shared.openEqualizer()
                }
                GlassMenuItem(title: "Mini-Player-Fenster", icon: Icons.miniPlayer, detail: "⌥⌘M") {
                    menu.close()
                    WindowRouter.shared.openMiniPlayer()
                }
            }
        }
    }

    /// Popover schließen, dann das Blatt öffnen (nicht gleichzeitig – sonst verschluckt AppKit das Blatt).
    private func open(_ s: PlayerSheet, _ menu: GlassMenuContext) {
        menu.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { sheet = s }
    }
}

// MARK: - Bedienelemente (Spec 1.5)

struct PlayerControls: View {
    @EnvironmentObject private var player: PlayerService
    let theme: PlayerTheme
    @Binding var sheet: PlayerSheet?
    @Binding var overlay: PlayerOverlay?

    var body: some View {
        VStack(spacing: 0) {
            PlayerTitleRow()
            Spacer().frame(height: 14)
            SeekArea(clock: player.clock)
            Spacer().frame(height: 6)
            switch theme {
            case .vinylStudio, .classic, .modernGlass, .aurora: IconTransport()
            case .cassette, .reelToReel: DeckKeys()
            case .portableCD: CDButtons()
            }
            Spacer().frame(height: 10)
            PlayerVolume()
            Spacer().frame(height: 14)
            PlayerToolbar(sheet: $sheet, overlay: $overlay)
        }
    }
}

/// Titel (Laufschrift), Interpret (öffnet den Interpreten), Album (öffnet das Album) und Favorit.
private struct PlayerTitleRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                if let t = player.current {
                    MarqueeText(text: t.displayTitle, font: Typo.inter(Typo.headlineSmall.size + 3, .bold, display: true), color: colors.textPrimary)
                        .frame(height: 30)
                    Button { if let a = t.artists.first { model.openArtist(named: a) } } label: {
                        Text(t.artistText ?? "Unbekannter Interpret")
                            .textStyle(Typo.titleMedium)
                            .foregroundColor(colors.accentText)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .disabled(t.artists.isEmpty)
                    .help("Interpret öffnen")
                    Button { model.openAlbum(of: t) } label: {
                        Text(t.album ?? "Unbekanntes Album")
                            .textStyle(Typo.bodyMedium)
                            .foregroundColor(colors.textSecondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.index.albumKeyByTrack[t.uid] == nil)
                    .help("Album öffnen")
                    PlayerMetaLine(track: t)
                        .padding(.top, 3)
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

/// Format und Hinzufügedatum unter Titel/Interpret/Album (v2.1), z. B. „AAC · 256 kbit/s · 44,1 kHz · 16 Bit“ und
/// „Hinzugefügt am 12. März 2019“. Unbekannte Angaben entfallen. Passt beides nicht in eine Zeile, stehen sie
/// untereinander. Die Hilfe nennt die Herkunft des Datums (z. B. „laut Apple Musik“).
struct PlayerMetaLine: View {
    @Environment(\.musicColors) private var colors
    let track: Track

    var body: some View {
        let format = PlayerMetaText.format(track)
        let added = PlayerMetaText.added(track)
        if format != nil || added != nil {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    if let format { formatText(format) }
                    if format != nil && added != nil { separator }
                    if let added { addedText(added) }
                }
                .fixedSize()
                VStack(alignment: .leading, spacing: 1) {
                    if let format { formatText(format) }
                    if let added { addedText(added) }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var separator: some View {
        Text(verbatim: "  ·  ").textStyle(Typo.labelSmall).foregroundColor(colors.textTertiary)
    }

    private func formatText(_ text: String) -> some View {
        Text(verbatim: text)
            .textStyle(Typo.labelSmall)
            .monospacedDigit()
            .foregroundColor(colors.textTertiary)
            .lineLimit(1)
            .help("Format der Datei")
    }

    private func addedText(_ text: String) -> some View {
        Text(verbatim: text)
            .textStyle(Typo.labelSmall)
            .foregroundColor(colors.textTertiary)
            .lineLimit(1)
            .help("\(text) – \(track.dateAddedSource.label)")
    }
}

/// Texte der Formatzeile (rein, ohne Ansicht).
enum PlayerMetaText {
    /// „AAC · 256 kbit/s · 44,1 kHz · 16 Bit“ – fehlende Angaben entfallen; `nil`, wenn nichts bekannt ist.
    static func format(_ t: Track) -> String? {
        var parts: [String] = []
        if let codec = t.codec?.trimmingCharacters(in: .whitespaces), !codec.isEmpty {
            parts.append(codec)
        } else {
            let ext = (t.fileName as NSString).pathExtension.uppercased()
            if !ext.isEmpty && ext.count <= 5 { parts.append(ext) }
        }
        if t.bitrate > 0 { parts.append(Formatting.bitrate(kbps: t.bitrate)) }
        if t.sampleRate > 0 { parts.append(Formatting.sampleRate(t.sampleRate)) }
        if t.bitsPerSample > 0 { parts.append("\(t.bitsPerSample) Bit") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// „Hinzugefügt am 12. März 2019“; `nil` ohne Datum.
    static func added(_ t: Track) -> String? {
        guard t.dateAdded > 0 else { return nil }
        return "Hinzugefügt am " + dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(t.dateAdded)))
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()
}

/// Endlose Laufschrift für lange Titel (Start nach 2,5 s, Pause 2,5 s, 30 pt/s, Abstand ⅓ Breite).
struct MarqueeText: View {
    @EnvironmentObject private var model: AppModel
    let text: String
    let font: Font
    let color: Color
    @State private var textWidth: CGFloat = 0
    @State private var start = Date()

    var body: some View {
        let animate = PlayerMotionPolicy.continuous(model.settings)
        GeometryReader { geo in
            let w = geo.size.width
            let overflow = textWidth > w + 1
            ZStack(alignment: .leading) {
                if overflow && animate {
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
                IconTap(icon: player.repeatMode == .one ? Icons.repeatOne : Icons.repeatAll, label: "\(player.repeatMode.label) – klicken zum Wechseln",
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

/// Stil ICONS (Vinyl, Classic, Modern Glass, Aurora): zurück · vorheriger · Play/Pause · nächster · vor.
struct IconTransport: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors

    var body: some View {
        let skip = model.settings.skipSeconds
        HStack {
            // Group: höchstens 10 direkte Elemente je ViewBuilder unter macOS 13
            Group {
                Spacer()
                SkipButton(seconds: skip, forward: false)
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
            .help(player.isPlaying ? "Pause (Leertaste)" : "Abspielen (Leertaste)")
            .accessibilityLabel(player.isPlaying ? "Pause" : "Abspielen")
            Spacer()
            IconTap(icon: Icons.next, label: "Nächster Titel", iconSize: 36, touch: 54) { player.next() }
                .disabled(!player.queue.hasNext)
            Spacer()
            Group {
                SkipButton(seconds: skip, forward: true)
                Spacer()
            }
        }
        .frame(height: 76)
    }
}

/// Sprungtaste mit eingestellter Sprungweite (`settings.skipSeconds`).
private struct SkipButton: View {
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    @Environment(\.isEnabled) private var enabled
    let seconds: Int
    let forward: Bool
    @State private var hover = false

    var body: some View {
        Button { if forward { player.skipForward() } else { player.skipBackward() } } label: {
            SkipGlyph(seconds: seconds, forward: forward, size: 24, color: colors.textSecondary.opacity(enabled ? 1 : 0.32))
                .frame(width: 44, height: 44)
                .background(Circle().fill(colors.textPrimary.opacity(hover ? 0.07 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.86))
        .onHover { hover = $0 }
        .help(SkipText.label(seconds, forward: forward))
        .accessibilityLabel(SkipText.label(seconds, forward: forward))
    }
}

/// Lautstärke mit Prozentanzeige, Verstärkung bis `settings.maxVolume` und Hinweis zum Limiter (Spec 1.5 Punkt 7).
struct PlayerVolume: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors

    var body: some View {
        let maxV = max(1, Double(model.settings.maxVolume))
        let v = min(Double(player.liveVolume), maxV)
        let boosted = v > 1.001
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                IconTap(icon: v == 0 ? Icons.volumeOff : (boosted ? PlayerIcons.volumeUp : Icons.volumeDown), label: "Lautstärke auf 100 %",
                        tint: boosted ? colors.accentText : colors.textSecondary, iconSize: 18, touch: 34) {
                    player.setLiveVolume(1)
                    model.settings.effects.volume = 1
                }
                MusicSlider(value: Binding(get: { v }, set: { raw in
                    let snapped = abs(raw - 1) < 0.04 ? 1 : (raw * 20).rounded() / 20
                    player.setLiveVolume(Float(snapped))
                }), range: 0...maxV, marker: maxV > 1 ? 1 : nil, label: "Lautstärke", valueText: VolumeText.percent(v)) { editing in
                    if !editing { model.settings.effects.volume = player.liveVolume }
                }
                .padding(.horizontal, 4)
                Text(VolumeText.percent(v))
                    .textStyle(Typo.time)
                    .monospacedDigit()
                    .foregroundColor(boosted ? colors.accentText : colors.textSecondary)
                    .frame(width: 48, alignment: .trailing)
            }
            if boosted {
                HStack(spacing: 4) {
                    Icon(Icons.warning, size: 11, color: colors.accentText)
                    Text("Verstärkung über 100 % aktiv · Limiter begrenzt Spitzen, damit nichts verzerrt")
                        .textStyle(Typo.labelSmall)
                        .foregroundColor(colors.textSecondary)
                        .lineLimit(2)
                }
                .padding(.leading, 40)
                .transition(.opacity)
            }
        }
        .animation(Motion.easeOut(), value: boosted)
        .help(VolumeText.help(v))
    }
}

/// Werkzeugleiste: Equalizer · Tonhöhe · Sleep-Timer · Liedtext · Warteschlange · Info (Spec 1.5 Punkt 9).
struct PlayerToolbar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    @Binding var sheet: PlayerSheet?
    @Binding var overlay: PlayerOverlay?

    var body: some View {
        let fx = model.settings.effects
        let eqActive = (fx.eqEnabled && !fx.isEqNeutral) || fx.bassDb != 0
        let eqLabel = EqualizerText.short(fx, userPresets: model.settings.eqUserPresets)
        let pitch = model.settings.pitch
        let pitchLabel: String = {
            if pitch.semitones != 0 { return PitchText.short(pitch.semitones) + " HT" }
            if pitch.tempo != 1 && pitch.mode == .key { return "Tempo \(Formatting.percent(pitch.tempo))" }
            return "Tonhöhe"
        }()
        let timer = player.sleepTimer
        HStack(spacing: 0) {
            ToolbarButton(icon: Icons.tune, active: eqActive, help: "Equalizer: \(EqualizerText.summary(fx, userPresets: model.settings.eqUserPresets))") { sheet = .equalizer } label: {
                Text(eqLabel)
            }
            ToolbarButton(icon: Icons.pitch, active: !pitch.isOriginal, help: "Tonhöhe: \(Formatting.semitones(pitch.semitones)) (\(pitch.mode.label))") { sheet = .pitch } label: {
                Text(pitchLabel)
            }
            ToolbarButton(icon: timer != nil ? Icons.sleepFill : Icons.sleep, active: timer != nil, help: "Sleep-Timer") { sheet = .sleep } label: {
                if let timer {
                    if timer.endOfTrack { Text("Titelende") } else { SleepCountdownText(clock: player.clock) }
                } else {
                    Text("Timer")
                }
            }
            ToolbarButton(icon: overlay == .lyrics ? PlayerIcons.lyricsFill : Icons.lyrics, active: overlay == .lyrics,
                          help: overlay == .lyrics ? "Liedtext ausblenden" : "Liedtext anzeigen") { toggle(.lyrics) } label: {
                Text("Liedtext")
            }
            ToolbarButton(icon: overlay == .queue ? PlayerIcons.queueFill : Icons.queue, active: overlay == .queue,
                          help: overlay == .queue ? "Warteschlange ausblenden" : "Warteschlange anzeigen") { toggle(.queue) } label: {
                Text("Liste")
            }
            ToolbarButton(icon: Icons.info, active: false, help: "Songinformationen") { sheet = .info } label: {
                Text("Info")
            }
        }
        .padding(6)
        .frame(height: 68)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.bar, style: .continuous), strong: true)
    }

    private func toggle(_ o: PlayerOverlay) {
        withAnimation(Motion.easeOut(0.32)) { overlay = overlay == o ? nil : o }
    }
}

/// Eintrag der Werkzeugleiste: Symbol und kurze Beschriftung (bei Aktivität rosé hinterlegt).
private struct ToolbarButton<Label: View>: View {
    @Environment(\.musicColors) private var colors
    let icon: String
    let active: Bool
    let help: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Icon(icon, size: 21, color: active ? colors.accentText : colors.textPrimary)
                    .frame(width: 40, height: 28)
                    .background(Capsule().fill(active ? colors.accentSoft : .clear))
                label()
                    .textStyle(Typo.labelSmall)
                    .foregroundColor(active ? colors.accentText : colors.textSecondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.94))
        .help(help)
        .accessibilityLabel(help)
    }
}
