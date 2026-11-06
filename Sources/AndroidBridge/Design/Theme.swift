import SwiftUI
import AppKit

// =============================================================================================
// Gestaltung von Android Bridge
//
// Farbwelt: ruhige Graphit- und Glastöne, Akzent „Bridge-Grün“ (zwischen Android-Grün und Apple-Türkis).
// macOS 26 und neuer: natives Liquid Glass (`glassEffect`). macOS 13–15: gleichwertige Nachbildung mit
// echter Hintergrundunschärfe (NSVisualEffectView), feiner Lichtkante und weichem Schatten.
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
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil ? dark : light
        })
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
}

/// Farbpalette.
enum Palette {
    static let bridgeGreen = Color(hex: 0x29B885)
    static let bridgeTeal = Color(hex: 0x1FA3B8)
    static let bridgeBlue = Color(hex: 0x2F7CF6)

    static let background = Color.adaptive(light: NSColor(hex: 0xF4F6F8), dark: NSColor(hex: 0x14161A))
    static let backgroundTop = Color.adaptive(light: NSColor(hex: 0xFAFBFC), dark: NSColor(hex: 0x1A1D22))
    static let surface = Color.adaptive(light: NSColor(hex: 0xFFFFFF), dark: NSColor(hex: 0x23262C))
    static let glassTint = Color.adaptive(light: NSColor(white: 1, alpha: 0.55), dark: NSColor(hex: 0x2A2E35, alpha: 0.45))
    static let glassTintStrong = Color.adaptive(light: NSColor(white: 1, alpha: 0.78), dark: NSColor(hex: 0x2A2E35, alpha: 0.72))
    static let glassEdgeLight = Color.adaptive(light: NSColor(white: 1, alpha: 0.95), dark: NSColor(white: 1, alpha: 0.16))
    static let glassEdgeDark = Color.adaptive(light: NSColor(white: 0, alpha: 0.08), dark: NSColor(white: 0, alpha: 0.45))
    static let glassSheen = Color.adaptive(light: NSColor(white: 1, alpha: 0.55), dark: NSColor(white: 1, alpha: 0.07))
    static let shadow = Color.adaptive(light: NSColor(white: 0, alpha: 0.10), dark: NSColor(white: 0, alpha: 0.45))
    static let hairline = Color.adaptive(light: NSColor(white: 0, alpha: 0.08), dark: NSColor(white: 1, alpha: 0.08))
    static let secondaryText = Color.secondary
    static let ambientA = Color.adaptive(light: NSColor(hex: 0x29B885, alpha: 0.16), dark: NSColor(hex: 0x29B885, alpha: 0.14))
    static let ambientB = Color.adaptive(light: NSColor(hex: 0x2F7CF6, alpha: 0.12), dark: NSColor(hex: 0x2F7CF6, alpha: 0.13))
    static let ambientC = Color.adaptive(light: NSColor(hex: 0xA77BF3, alpha: 0.08), dark: NSColor(hex: 0x7B5CE0, alpha: 0.10))

    static let warning = Color(hex: 0xF5A524)
    static let danger = Color(hex: 0xEF4F4F)
    static let success = Color(hex: 0x2DBE6C)

    static func tint(for kind: FileKindTint) -> Color {
        switch kind {
        case .folder: return Color(hex: 0x3E8EF7)
        case .photo: return Color(hex: 0xF2994A)
        case .video: return Color(hex: 0xE5484D)
        case .audio: return Color(hex: 0xC151D8)
        case .document: return Color(hex: 0x4F7BEE)
        case .archive: return Color(hex: 0x8E8E93)
        case .apk: return Color(hex: 0x29B885)
        case .other: return Color(hex: 0x8E8E93)
        }
    }
}

/// Spiegel von FileKind für die Farbwahl (ohne ABCore-Abhängigkeit in der Palette).
enum FileKindTint { case folder, photo, video, audio, document, archive, apk, other }

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

extension Animation {
    static let bridgeSpring = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let bridgeQuick = Animation.easeOut(duration: 0.18)
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
        v.state = .followsWindowActiveState
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
                .shadow(color: elevated ? Palette.shadow.opacity(0.5) : .clear, radius: elevated ? 14 : 0, y: elevated ? 5 : 0)
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
                        LinearGradient(stops: [.init(color: Palette.glassSheen, location: 0), .init(color: .clear, location: 0.55)],
                                       startPoint: .top, endPoint: .bottom)
                    } else {
                        shape.fill(tint ?? Palette.surface)
                    }
                }
                .clipShape(shape)
            )
            .overlay(
                shape.strokeBorder(LinearGradient(colors: [Palette.glassEdgeLight, Palette.glassEdgeDark, Palette.glassEdgeLight.opacity(0.4)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing),
                                   lineWidth: 0.8)
            )
            .compositingGroup()
            .shadow(color: elevated ? Palette.shadow : .clear, radius: elevated ? 16 : 0, x: 0, y: elevated ? 6 : 0)
    }
}

extension View {
    func glassSurface<S: InsettableShape>(_ shape: S, strong: Bool = false, elevated: Bool = false, tint: Color? = nil,
                                          interactive: Bool = false) -> some View {
        modifier(GlassBackground(shape: shape, strong: strong, elevated: elevated, tint: tint, interactive: interactive))
    }

    func glassCard(cornerRadius: CGFloat = 18, strong: Bool = false, elevated: Bool = false, tint: Color? = nil) -> some View {
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

/// Atmosphärischer Fensterhintergrund: sehr weiche Farbinseln, keine Echtzeit-Unschärfe.
struct AmbientBackground: View {
    @Environment(\.glassEnabled) private var glass

    var body: some View {
        GeometryReader { geo in
            let r = max(geo.size.width, geo.size.height) * 0.62
            ZStack {
                LinearGradient(colors: [Palette.backgroundTop, Palette.background], startPoint: .top, endPoint: .bottom)
                if glass {
                    RadialGradient(colors: [Palette.ambientA, .clear], center: UnitPoint(x: 0.08, y: 0.0), startRadius: 0, endRadius: r)
                    RadialGradient(colors: [Palette.ambientB, .clear], center: UnitPoint(x: 1.0, y: 0.35), startRadius: 0, endRadius: r)
                    RadialGradient(colors: [Palette.ambientC, .clear], center: UnitPoint(x: 0.3, y: 1.05), startRadius: 0, endRadius: r * 0.9)
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Glasknopf (macOS 26: `.glass`, sonst randloser Knopf auf Glasfläche).
struct GlassButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background {
                if prominent {
                    Capsule().fill(LinearGradient(colors: [Palette.bridgeGreen, Palette.bridgeTeal], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .glassSurface(Capsule(), tint: prominent ? Color.clear : nil, interactive: true)
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.bridgeQuick, value: configuration.isPressed)
    }
}
