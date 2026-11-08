import SwiftUI
import AppKit

// =============================================================================================
// Designsystem von Android Bridge 3.0 – „Midnight Glass“
//
// Grundsätze (abgeleitet aus Apples Produktpräsentationen, eigenständig umgesetzt):
// – Licht statt Linien: tiefe Flächen, auf denen weiches, farbiges Licht Tiefe erzeugt. Keine Rahmen,
//   wo Licht und Schatten trennen können.
// – Inhalt zuerst: Bilder groß, Text knapp. Große Titel in der Systemschrift (SF Pro), ruhige Metadaten.
// – Glas in Schichten: Unschärfe + Tönung + Innenlicht + Lichtkante + weicher Schatten.
//   macOS 26: natives Liquid Glass. macOS 13–15: gleichwertige Nachbildung mit Systemmaterialien.
// – Bewegung erklärt: Federn für Zustandswechsel, ruhige Lichtfelder im Hintergrund, nichts Hektisches.
//
// Identität: „Signal“-Grün (Android ↔ Mac) als einziges kräftiges Licht; Nebenlichter Tiefblau und Violett.
// =============================================================================================

enum LiquidGlass {
    /// Natives Liquid Glass verfügbar (macOS 26 + mit dem macOS-26-SDK gebaut)?
    static var isAvailable: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return !forceFallback }
        #endif
        return false
    }

    /// Für Vergleichsbilder: Rückfall auch unter macOS 26 erzwingen.
    static var forceFallback = ProcessInfo.processInfo.environment["AB_FORCE_GLASS_FALLBACK"] == "1"
}

extension Color {
    /// Farbe, die sich an Hell/Dunkel anpasst.
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: .adaptive(light: light, dark: dark))
    }

    static func adaptive(_ light: UInt32, _ lightAlpha: CGFloat = 1, dark: UInt32, _ darkAlpha: CGFloat = 1) -> Color {
        adaptive(light: NSColor(hex: light, alpha: lightAlpha), dark: NSColor(hex: dark, alpha: darkAlpha))
    }

    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil ? dark : light
        }
    }
}

/// Farbpalette. Hell und Dunkel sind eigenständig abgestimmt (nicht invertiert).
enum Palette {
    // Licht / Akzente
    static let bridgeGreen = Color.adaptive(0x0E9F74, dark: 0x3EE3A8)   // „Signal“
    static let bridgeTeal = Color.adaptive(0x0B8EA6, dark: 0x3CC7DE)
    static let bridgeBlue = Color.adaptive(0x2F6BE0, dark: 0x6A9BFF)
    static let violet = Color.adaptive(0x7A5BE0, dark: 0x9B85FF)
    static let accentSoft = Color.adaptive(0x0E9F74, 0.12, dark: 0x3EE3A8, 0.16)
    static let onAccent = Color.adaptive(0xFFFFFF, dark: 0x02150E)

    // Flächen
    static let background = Color.adaptive(0xF2F4F7, dark: 0x040506)
    static let backgroundTop = Color.adaptive(0xFAFBFC, dark: 0x0A0D10)
    static let surface = Color.adaptive(0xFFFFFF, dark: 0x15191D)
    static let surfaceMuted = Color.adaptive(0xEBEEF2, dark: 0x1B2025)
    static let mediaWell = Color.adaptive(0xE4E8EE, dark: 0x101317)

    // Text
    static let textPrimary = Color.adaptive(0x0B0F14, dark: 0xF5F7FA)
    static let textSecondary = Color.adaptive(0x5B6470, dark: 0xA0A8B3)
    static let textTertiary = Color.adaptive(0x8A929C, dark: 0x6D7580)
    static let secondaryText = textSecondary

    // Glas
    static let glassTint = Color.adaptive(0xFFFFFF, 0.58, dark: 0x161A1F, 0.58)
    static let glassTintStrong = Color.adaptive(0xFFFFFF, 0.78, dark: 0x1A1F25, 0.80)
    static let glassEdgeLight = Color.adaptive(0xFFFFFF, 0.95, dark: 0xFFFFFF, 0.22)
    static let glassEdgeDark = Color.adaptive(0xFFFFFF, 0.25, dark: 0xFFFFFF, 0.03)
    static let glassSheen = Color.adaptive(0xFFFFFF, 0.55, dark: 0xFFFFFF, 0.07)
    static let shadow = Color.adaptive(0x0B1A2A, 0.14, dark: 0x000000, 0.65)
    static let hairline = Color.adaptive(0x0B0F14, 0.08, dark: 0xFFFFFF, 0.08)
    static let fieldFill = Color.adaptive(0x0B0F14, 0.05, dark: 0xFFFFFF, 0.07)
    static let hoverFill = Color.adaptive(0x0B0F14, 0.05, dark: 0xFFFFFF, 0.07)
    static let selectionFill = Color.adaptive(0x0E9F74, 0.14, dark: 0x3EE3A8, 0.18)
    static let scrim = Color.adaptive(0x05080C, 0.35, dark: 0x000000, 0.6)
    static let sidebarTint = Color.adaptive(0xF7F8FA, 0.62, dark: 0x0B0E11, 0.62)

    // Lichtfelder des Hintergrunds
    static let lightA = Color.adaptive(0x6FE3BF, 0.50, dark: 0x0F7A58, 0.55)   // Signal
    static let lightB = Color.adaptive(0x9DBDF7, 0.45, dark: 0x1A3D86, 0.50)   // Tiefblau
    static let lightC = Color.adaptive(0xD3C6F5, 0.40, dark: 0x3A2470, 0.42)   // Violett
    static let ambientA = lightA
    static let ambientB = lightB
    static let ambientC = lightC

    // Zustände
    static let warning = Color.adaptive(0xD38306, dark: 0xF8B640)
    static let danger = Color.adaptive(0xD12F3D, dark: 0xFF6268)
    static let dangerSoft = Color.adaptive(0xD12F3D, 0.10, dark: 0xFF6268, 0.15)
    static let success = Color.adaptive(0x12A15F, dark: 0x3EE38A)

    static func tint(for kind: FileKindTint) -> Color {
        switch kind {
        case .folder: return Color.adaptive(0x2F7CEB, dark: 0x5EA2FF)
        case .photo: return Color.adaptive(0xE8822D, dark: 0xFFA552)
        case .video: return Color.adaptive(0xDE3E52, dark: 0xFF6A7A)
        case .audio: return Color.adaptive(0xB14BD0, dark: 0xD67EF0)
        case .document: return Color.adaptive(0x4A6FE3, dark: 0x82A2FF)
        case .archive: return Color.adaptive(0x8B6B3E, dark: 0xC9A06A)
        case .apk: return bridgeGreen
        case .other: return Color.adaptive(0x7D8793, dark: 0x9AA4B0)
        }
    }
}

/// Spiegel von FileKind für die Farbwahl (ohne ABCore-Abhängigkeit in der Palette).
enum FileKindTint { case folder, photo, video, audio, document, archive, apk, other }

// MARK: - Abstände, Radien, Maße, Bewegung

/// Abstände im 4-pt-Raster.
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    static let section: CGFloat = 40
    /// Seitenrand der Inhalte.
    static let gutter: CGFloat = 32
}

/// Eckenradien.
enum Radius {
    static let thumb: CGFloat = 10
    static let tile: CGFloat = 14
    static let control: CGFloat = 10
    static let card: CGFloat = 20
    static let panel: CGFloat = 26
    static let sheet: CGFloat = 30
    static let hero: CGFloat = 34
}

/// Feste Maße.
enum Metrics {
    static let sidebarWidth: CGFloat = 232
    static let sidebarRailWidth: CGFloat = 72
    /// Unterhalb dieser Fensterbreite wird die Seitenleiste zur Symbolleiste.
    static let railBreakpoint: CGFloat = 1100
    static let sidebarInset: CGFloat = 0
    /// Platz für die Ampel-Knöpfe über der Seitenleiste.
    static let trafficLights: CGFloat = 46
    static let sidebarRow: CGFloat = 34
    static let toolbarButton: CGFloat = 32
    static let toolbarHeight: CGFloat = 40
    static let searchHeight: CGFloat = 34
    static let headerTop: CGFloat = 26
}

/// Bewegung: weiche Federn, Apple-artige Ausklingkurven.
enum Motion {
    static func easeOut(_ duration: Double = 0.26) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: duration) }
    static let spring = Animation.interpolatingSpring(stiffness: 380, damping: 2 * 0.86 * sqrt(380))
    static let gentle = Animation.interpolatingSpring(stiffness: 200, damping: 2 * 0.9 * sqrt(200))
    static let lens = Animation.interpolatingSpring(stiffness: 360, damping: 2 * 0.78 * sqrt(360))
    static let reveal = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.7)
}

extension Animation {
    static let bridgeSpring = Motion.spring
    static let bridgeQuick = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)
}

// MARK: - Typografie (Systemschrift SF Pro)

enum Typo {
    // Stufen
    static let hero = Font.display(44, .bold)
    static let largeTitle = Font.display(32, .bold)
    static let title = Font.display(22, .bold)
    static let title2 = Font.display(17, .semibold)
    static let headline = Font.ui(13.5, .semibold)
    static let body = Font.ui(13)
    static let bodyMedium = Font.ui(13, .medium)
    static let callout = Font.ui(12.5)
    static let caption = Font.ui(11.5)
    static let captionMedium = Font.ui(11.5, .medium)
    static let micro = Font.ui(10.5, .medium)
    static let sectionLabel = Font.ui(11, .semibold)
    static let eyebrow = Font.ui(12, .semibold)
}

extension Font {
    /// Systemschrift (SF Pro Text) – Symbole übernehmen Größe und Gewicht.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Systemschrift für Titel (SF Pro Display wird ab 20 pt automatisch gewählt).
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

// MARK: - Umgebungswerte

private struct GlassEnabledKey: EnvironmentKey { static let defaultValue = true }
private struct AnimationsEnabledKey: EnvironmentKey { static let defaultValue = true }
private struct LightIntensityKey: EnvironmentKey { static let defaultValue: Double = 0.6 }

extension EnvironmentValues {
    var glassEnabled: Bool {
        get { self[GlassEnabledKey.self] }
        set { self[GlassEnabledKey.self] = newValue }
    }
    var animationsEnabled: Bool {
        get { self[AnimationsEnabledKey.self] }
        set { self[AnimationsEnabledKey.self] = newValue }
    }
    /// Stärke des Signal-Lichts (verbunden = hell, getrennt = gedämpft).
    var lightIntensity: Double {
        get { self[LightIntensityKey.self] }
        set { self[LightIntensityKey.self] = newValue }
    }
}

// MARK: - Glas

/// Echte Hintergrundunschärfe (macOS 13–15).
struct BackdropBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blending: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

struct GlassBackground<S: InsettableShape>: ViewModifier {
    @Environment(\.glassEnabled) private var glass
    @Environment(\.colorScheme) private var scheme
    let shape: S
    var strong = false
    var elevated = false
    var tint: Color?
    var interactive = false

    func body(content: Content) -> some View {
        Group {
            if glass && LiquidGlass.isAvailable {
                modern(content)
            } else {
                fallback(content)
            }
        }
    }

    @ViewBuilder
    private func modern(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let base = tint.map { Glass.regular.tint($0) } ?? (strong ? Glass.regular.tint(Palette.glassTint) : Glass.regular)
            content
                .glassEffect(interactive ? base.interactive() : base, in: shape)
                .shadow(color: elevated ? Palette.shadow.opacity(0.7) : .clear, radius: elevated ? 24 : 0, y: elevated ? 10 : 0)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    /// Fünf Schichten: Unschärfe, Tönung, Innenlicht (oben), Lichtkante, Schatten.
    private func fallback(_ content: Content) -> some View {
        content
            .background(
                ZStack {
                    if glass {
                        BackdropBlur(material: scheme == .dark ? .hudWindow : .popover)
                        shape.fill(tint ?? (strong ? Palette.glassTintStrong : Palette.glassTint))
                        LinearGradient(stops: [.init(color: Palette.glassSheen, location: 0),
                                               .init(color: .clear, location: 0.45)],
                                       startPoint: .top, endPoint: .bottom)
                    } else {
                        shape.fill(tint ?? Palette.surface)
                    }
                }
                .clipShape(shape)
            )
            .overlay(
                shape.strokeBorder(LinearGradient(colors: [Palette.glassEdgeLight, Palette.glassEdgeDark, Palette.glassEdgeLight.opacity(0.35)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing),
                                   lineWidth: 0.8)
            )
            .compositingGroup()
            .shadow(color: elevated ? Palette.shadow : Palette.shadow.opacity(0.4), radius: elevated ? 24 : 8, x: 0, y: elevated ? 10 : 3)
    }
}

extension View {
    func glassSurface<S: InsettableShape>(_ shape: S, strong: Bool = false, elevated: Bool = false, tint: Color? = nil,
                                          interactive: Bool = false) -> some View {
        modifier(GlassBackground(shape: shape, strong: strong, elevated: elevated, tint: tint, interactive: interactive))
    }

    func glassCard(cornerRadius: CGFloat = Radius.card, strong: Bool = false, elevated: Bool = false, tint: Color? = nil) -> some View {
        glassSurface(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), strong: strong, elevated: elevated, tint: tint)
    }

    /// Animation nur, wenn in den Einstellungen eingeschaltet.
    func bridgeAnimation<V: Equatable>(_ animation: Animation = .bridgeSpring, value: V, enabled: Bool) -> some View {
        self.animation(enabled ? animation : nil, value: value)
    }

    /// Weiches Einblenden beim ersten Erscheinen (von unten, leicht vergrößert).
    func revealOnAppear(delay: Double = 0) -> some View { modifier(RevealOnAppear(delay: delay)) }
}

struct RevealOnAppear: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.animationsEnabled) private var animations

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                guard animations else { shown = true; return }
                withAnimation(Motion.reveal.delay(delay)) { shown = true }
            }
    }
}

/// Gruppiert Glasflächen (macOS 26: verschmelzende Liquid-Glass-Formen).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            if LiquidGlass.isAvailable {
                GlassEffectContainer(spacing: spacing) { content() }
            } else {
                content()
            }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

/// Fensterhintergrund: tiefe Fläche mit weichen Lichtfeldern, die sich sehr langsam bewegen.
/// Pausiert ohne Animationen und bei „Bewegung reduzieren“; zeichnet höchstens 20× pro Sekunde.
struct CinematicBackground: View {
    @Environment(\.glassEnabled) private var glass
    @Environment(\.animationsEnabled) private var animations
    @Environment(\.lightIntensity) private var intensity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let animate = animations && !reduceMotion && glass && !SnapshotMode.isActive
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !animate)) { context in
            let t = animate ? context.date.timeIntervalSinceReferenceDate : 0
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let r = max(w, h)
                ZStack {
                    LinearGradient(colors: [Palette.backgroundTop, Palette.background], startPoint: .top, endPoint: .bottom)
                    if glass {
                        // Signal-Licht oben links, atmet mit der Verbindung
                        RadialGradient(colors: [Palette.lightA.opacity(0.35 + 0.65 * intensity), .clear],
                                       center: UnitPoint(x: 0.08 + 0.05 * sin(t / 11), y: -0.05 + 0.06 * cos(t / 13)),
                                       startRadius: 0, endRadius: r * 0.62)
                        RadialGradient(colors: [Palette.lightB, .clear],
                                       center: UnitPoint(x: 0.95 + 0.04 * cos(t / 17), y: 0.18 + 0.08 * sin(t / 19)),
                                       startRadius: 0, endRadius: r * 0.55)
                        RadialGradient(colors: [Palette.lightC, .clear],
                                       center: UnitPoint(x: 0.5 + 0.12 * sin(t / 23), y: 1.15),
                                       startRadius: 0, endRadius: r * 0.6)
                        // feine Vignette für Tiefe
                        RadialGradient(colors: [.clear, Color.black.opacity(0.18)], center: .center,
                                       startRadius: r * 0.35, endRadius: r * 0.85)
                            .blendMode(.multiply)
                    }
                }
                .frame(width: w, height: h)
                .drawingGroup()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Alter Name (Dialoge und Nebenfenster).
typealias AmbientBackground = CinematicBackground

/// Bildschirmfoto-Modus des Builds (statisches Licht, damit Bilder vergleichbar bleiben).
enum SnapshotMode {
    static var isActive = false
}

/// Kapselknopf: `prominent` = Signal-Fläche, sonst tonales Glas; `destructive` = Rot.
struct GlassButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        GlassButtonBody(configuration: configuration, prominent: prominent, destructive: destructive, compact: compact)
    }
}

private struct GlassButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let destructive: Bool
    let compact: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.ui(compact ? 12 : 13, .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, compact ? 12 : 16)
            .frame(height: compact ? 28 : 34)
            .foregroundStyle(foreground)
            .background {
                if prominent {
                    Capsule().fill(destructive ? AnyShapeStyle(Palette.danger)
                                   : AnyShapeStyle(LinearGradient(colors: [Palette.bridgeGreen, Palette.bridgeTeal], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    Capsule().fill(LinearGradient(colors: [Color.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center))
                    Capsule().fill(Color.white.opacity(hovering && isEnabled ? 0.12 : 0))
                } else {
                    Capsule().fill(destructive ? Palette.dangerSoft : Palette.fieldFill)
                    Capsule().fill(hovering && isEnabled ? Palette.hoverFill : Color.clear)
                }
            }
            .overlay(Capsule().strokeBorder(Color.white.opacity(prominent ? 0.25 : 0.0), lineWidth: 0.6))
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(color: prominent && isEnabled ? (destructive ? Palette.danger : Palette.bridgeGreen).opacity(hovering ? 0.45 : 0.3) : .clear,
                    radius: hovering ? 14 : 9, y: 3)
            .animation(.bridgeQuick, value: configuration.isPressed)
            .animation(.bridgeQuick, value: hovering)
            .onHover { hovering = $0 }
    }

    private var foreground: Color {
        if prominent { return destructive ? .white : Palette.onAccent }
        return destructive ? Palette.danger : Palette.textPrimary
    }
}

// MARK: - Fensterrahmen

/// Verdeckte Titelleiste, Inhalt bis an den oberen Fensterrand.
struct WindowConfigurator: NSViewRepresentable {
    var minSize = NSSize(width: 960, height: 640)

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [minSize] in
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarSeparatorStyle = .none
            window.isMovableByWindowBackground = false
            window.minSize = minSize
            window.tabbingMode = .disallowed
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.toolbar = nil
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Fläche, an der sich das Fenster verschieben lässt (Ersatz für die verdeckte Titelleiste).
/// Doppelklick verhält sich wie auf einer Titelleiste.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "Minimize": window.performMiniaturize(nil)
                case "None": break
                default: window.performZoom(nil)
                }
                return
            }
            window.performDrag(with: event)
        }
    }
}
