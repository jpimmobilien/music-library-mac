import SwiftUI
import AppKit

// =============================================================================================
// Designsystem von Android Bridge 2.0
//
// Grundsätze (übernommen aus der Musikbibliothek, eigenständig umgesetzt):
// – Inhalt bis an den Fensterrand, verdeckte Titelleiste, schwebende Glasflächen über einem
//   getönten Atmosphäre-Hintergrund.
// – Große Titel in Inter Display, ruhige Inter-Texte, klare Hierarchie.
// – Werkzeuge in Glaskapseln rechts neben dem Titel, Auswahlaktionen in einer schwebenden Leiste unten.
// – Feste Abstände (4-pt-Raster), wenige Radien, weiche Federn.
//
// Eigene Identität: kühles Schiefer-Weiß bzw. tiefes Petrol-Schwarz, Akzent „Bridge-Mint“, Atmosphäre aus
// Mint, Himmelblau und Flieder. macOS 26: natives Liquid Glass. macOS 13–15: Nachbildung mit echter
// Hintergrundunschärfe, Lichtkante, Glanz und weichem Schatten.
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

/// Farbpalette (Hell und Dunkel eigenständig abgestimmt, nicht invertiert).
enum Palette {
    // Akzente
    static let bridgeGreen = Color.adaptive(0x12A27E, dark: 0x3DD5A7)
    static let bridgeTeal = Color.adaptive(0x128FA6, dark: 0x3BBAD0)
    static let bridgeBlue = Color.adaptive(0x2F72E6, dark: 0x5C9CFF)
    static let accentSoft = Color.adaptive(0x12A27E, 0.13, dark: 0x3DD5A7, 0.17)
    static let onAccent = Color.adaptive(0xFFFFFF, dark: 0x062019)

    // Flächen
    static let background = Color.adaptive(0xEEF3F2, dark: 0x0B1012)
    static let backgroundTop = Color.adaptive(0xF8FAFA, dark: 0x10171A)
    static let surface = Color.adaptive(0xFFFFFF, dark: 0x172024)
    static let surfaceMuted = Color.adaptive(0xEAF0EF, dark: 0x1C262A)

    // Text
    static let textPrimary = Color.adaptive(0x111A19, dark: 0xF1F6F5)
    static let textSecondary = Color.adaptive(0x5A6866, dark: 0xA3B1AF)
    static let textTertiary = Color.adaptive(0x7D8A88, dark: 0x7E8C8A)
    static let secondaryText = textSecondary

    // Glas
    static let glassTint = Color.adaptive(0xFFFFFF, 0.60, dark: 0x182226, 0.62)
    static let glassTintStrong = Color.adaptive(0xFFFFFF, 0.80, dark: 0x1B262A, 0.82)
    static let glassEdgeLight = Color.adaptive(0xFFFFFF, 0.92, dark: 0xFFFFFF, 0.20)
    static let glassEdgeDark = Color.adaptive(0xFFFFFF, 0.28, dark: 0xFFFFFF, 0.04)
    static let glassSheen = Color.adaptive(0xFFFFFF, 0.50, dark: 0xFFFFFF, 0.06)
    static let shadow = Color.adaptive(0x0D2B25, 0.13, dark: 0x000000, 0.55)
    static let hairline = Color.adaptive(0x0E1A18, 0.08, dark: 0xFFFFFF, 0.08)
    static let fieldFill = Color.adaptive(0x0E1A18, 0.05, dark: 0xFFFFFF, 0.07)
    static let hoverFill = Color.adaptive(0x0E1A18, 0.05, dark: 0xFFFFFF, 0.06)
    static let selectionFill = Color.adaptive(0x12A27E, 0.15, dark: 0x3DD5A7, 0.20)
    static let scrim = Color.adaptive(0x081311, 0.30, dark: 0x000000, 0.55)

    // Atmosphäre
    static let ambientA = Color.adaptive(0x7EDFC1, 0.55, dark: 0x16735B, 0.42)
    static let ambientB = Color.adaptive(0x9CC6F7, 0.50, dark: 0x1C4680, 0.40)
    static let ambientC = Color.adaptive(0xD8CCF4, 0.45, dark: 0x3D2D6E, 0.32)

    // Zustände
    static let warning = Color.adaptive(0xD98A0B, dark: 0xF5B13D)
    static let danger = Color.adaptive(0xD3333F, dark: 0xFF6B6E)
    static let dangerSoft = Color.adaptive(0xD3333F, 0.11, dark: 0xFF6B6E, 0.16)
    static let success = Color.adaptive(0x18A765, dark: 0x3FD58A)

    static func tint(for kind: FileKindTint) -> Color {
        switch kind {
        case .folder: return Color.adaptive(0x3A86F0, dark: 0x5EA0FF)
        case .photo: return Color.adaptive(0xEB8A35, dark: 0xF7A35A)
        case .video: return Color.adaptive(0xE04650, dark: 0xFF6B73)
        case .audio: return Color.adaptive(0xB24ED0, dark: 0xD27BEC)
        case .document: return Color.adaptive(0x4C72E6, dark: 0x7B9DFF)
        case .archive: return Color.adaptive(0x7D8A88, dark: 0x9AA7A5)
        case .apk: return bridgeGreen
        case .other: return Color.adaptive(0x7D8A88, dark: 0x9AA7A5)
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
    /// Seitenrand der Inhalte.
    static let gutter: CGFloat = 28
}

/// Eckenradien.
enum Radius {
    static let thumb: CGFloat = 8
    static let tile: CGFloat = 12
    static let control: CGFloat = 10
    static let card: CGFloat = 18
    static let panel: CGFloat = 24
    static let sheet: CGFloat = 28
}

/// Feste Maße.
enum Metrics {
    static let sidebarWidth: CGFloat = 236
    static let sidebarInset: CGFloat = 10
    /// Platz für die Ampel-Knöpfe über der Seitenleiste.
    static let trafficLights: CGFloat = 44
    static let sidebarRow: CGFloat = 32
    static let toolbarButton: CGFloat = 30
    static let toolbarHeight: CGFloat = 38
    static let searchHeight: CGFloat = 32
    static let headerTop: CGFloat = 22
}

/// Bewegung: weiche Federn, Apple-artige Ausklingkurven.
enum Motion {
    static func easeOut(_ duration: Double = 0.26) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: duration) }
    static let spring = Animation.interpolatingSpring(stiffness: 380, damping: 2 * 0.86 * sqrt(380))
    static let gentle = Animation.interpolatingSpring(stiffness: 200, damping: 2 * 0.9 * sqrt(200))
    static let lens = Animation.interpolatingSpring(stiffness: 360, damping: 2 * 0.78 * sqrt(360))
}

extension Animation {
    static let bridgeSpring = Motion.spring
    static let bridgeQuick = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)
}

// MARK: - Typografie (Inter, im Programmpaket enthalten; Rückfall: Systemschrift)

enum Typo {
    /// Wurden die Inter-Schriften registriert (ATSApplicationFontsPath)?
    static let interAvailable: Bool = NSFont(name: "Inter-Regular", size: 12) != nil
    static let displayAvailable: Bool = NSFont(name: "InterDisplay-Bold", size: 12) != nil

    static func faceName(_ weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: return "Inter-Bold"
        case .semibold: return "Inter-SemiBold"
        case .medium: return "Inter-Medium"
        default: return "Inter-Regular"
        }
    }

    // Stufen
    static let largeTitle = Font.display(30, .bold)
    static let title = Font.display(21, .bold)
    static let title2 = Font.display(17, .semibold)
    static let headline = Font.inter(13.5, .semibold)
    static let body = Font.inter(13)
    static let bodyMedium = Font.inter(13, .medium)
    static let callout = Font.inter(12.5)
    static let caption = Font.inter(11.5)
    static let captionMedium = Font.inter(11.5, .medium)
    static let micro = Font.inter(10.5, .medium)
    static let sectionLabel = Font.inter(11, .semibold)
}

extension Font {
    /// Inter im gewünschten Gewicht (Symbole übernehmen Größe und Gewicht).
    static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard Typo.interAvailable else { return .system(size: size, weight: weight) }
        return .custom(Typo.faceName(weight), fixedSize: size).weight(weight)
    }

    /// Inter Display für große Titel.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        guard Typo.displayAvailable else { return .system(size: size, weight: weight) }
        return .custom(weight == .semibold ? "InterDisplay-SemiBold" : "InterDisplay-Bold", fixedSize: size)
    }
}

// MARK: - Umgebungswerte

private struct GlassEnabledKey: EnvironmentKey { static let defaultValue = true }
private struct AnimationsEnabledKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    var glassEnabled: Bool {
        get { self[GlassEnabledKey.self] }
        set { self[GlassEnabledKey.self] = newValue }
    }
    var animationsEnabled: Bool {
        get { self[AnimationsEnabledKey.self] }
        set { self[AnimationsEnabledKey.self] = newValue }
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
                .shadow(color: elevated ? Palette.shadow.opacity(0.6) : .clear, radius: elevated ? 18 : 0, y: elevated ? 6 : 0)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(
                ZStack {
                    if glass {
                        BackdropBlur(material: scheme == .dark ? .hudWindow : .popover)
                        shape.fill(tint ?? (strong ? Palette.glassTintStrong : Palette.glassTint))
                        LinearGradient(stops: [.init(color: Palette.glassSheen, location: 0), .init(color: .clear, location: 0.5)],
                                       startPoint: .top, endPoint: .bottom)
                    } else {
                        shape.fill(tint ?? Palette.surface)
                    }
                }
                .clipShape(shape)
            )
            .overlay(
                shape.strokeBorder(LinearGradient(colors: [Palette.glassEdgeLight, Palette.glassEdgeDark, Palette.glassEdgeLight.opacity(0.5)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing),
                                   lineWidth: 0.8)
            )
            .compositingGroup()
            .shadow(color: elevated ? Palette.shadow : Palette.shadow.opacity(0.35), radius: elevated ? 18 : 6, x: 0, y: elevated ? 7 : 2)
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

/// Atmosphärischer Fensterhintergrund: getönte, sehr weiche Farbinseln (statisch, keine Echtzeit-Unschärfe).
struct AmbientBackground: View {
    @Environment(\.glassEnabled) private var glass

    var body: some View {
        GeometryReader { geo in
            let r = max(geo.size.width, geo.size.height) * 0.7
            ZStack {
                LinearGradient(colors: [Palette.backgroundTop, Palette.background], startPoint: .top, endPoint: .bottom)
                if glass {
                    RadialGradient(colors: [Palette.ambientA, .clear], center: UnitPoint(x: 0.0, y: 0.0), startRadius: 0, endRadius: r)
                    RadialGradient(colors: [Palette.ambientB, .clear], center: UnitPoint(x: 1.0, y: 0.25), startRadius: 0, endRadius: r * 0.85)
                    RadialGradient(colors: [Palette.ambientC, .clear], center: UnitPoint(x: 0.45, y: 1.1), startRadius: 0, endRadius: r * 0.8)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Kapselknopf: `prominent` = Akzentfläche, sonst tonales Glas; `destructive` = Rot.
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
            .font(.inter(compact ? 12 : 13, .semibold))
            .lineLimit(1)
            .padding(.horizontal, compact ? 11 : 15)
            .frame(height: compact ? 28 : 32)
            .foregroundStyle(foreground)
            .background {
                if prominent {
                    Capsule().fill(destructive ? AnyShapeStyle(Palette.danger)
                                   : AnyShapeStyle(LinearGradient(colors: [Palette.bridgeGreen, Palette.bridgeTeal], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    Capsule().fill(Color.white.opacity(hovering && isEnabled ? 0.12 : 0))
                } else {
                    Capsule().fill(destructive ? Palette.dangerSoft : Palette.fieldFill)
                    Capsule().fill(hovering && isEnabled ? Palette.hoverFill : Color.clear)
                }
            }
            .overlay(Capsule().strokeBorder(Color.white.opacity(prominent ? 0.22 : 0), lineWidth: 0.6))
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.42)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(color: prominent && isEnabled ? (destructive ? Palette.danger : Palette.bridgeGreen).opacity(0.28) : .clear, radius: 8, y: 3)
            .animation(.bridgeQuick, value: configuration.isPressed)
            .animation(.bridgeQuick, value: hovering)
            .onHover { hovering = $0 }
    }

    private var foreground: Color {
        if prominent { return .white }
        return destructive ? Palette.danger : Palette.textPrimary
    }
}

// MARK: - Fensterrahmen

/// Verdeckte Titelleiste, Inhalt bis an den oberen Fensterrand.
struct WindowConfigurator: NSViewRepresentable {
    var minSize = NSSize(width: 1000, height: 660)

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [minSize] in
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
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
