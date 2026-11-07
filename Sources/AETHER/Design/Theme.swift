import SwiftUI
import AppKit
import AetherCore

// =============================================================================================
// Designsystem von AETHER
//
// – Themes kommen als Daten aus AetherCore (Kontraste dort unit-getestet) und werden hier in Farben übersetzt.
// – Glas für Navigation und Werkzeuge, ruhigere, stärker getönte Flächen für Zahlen und Diagramme.
// – Systemschrift (SF Pro), Zahlen mit festen Ziffernbreiten, 4-pt-Raster, weiche Federn.
// – macOS 26: natives Liquid Glass. macOS 13–15: Nachbildung mit echter Hintergrundunschärfe.
// =============================================================================================

extension Color {
    init(_ rgba: RGBA) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}

/// Aufgelöstes Theme für die aktuelle Erscheinung – über die Umgebung an alle Ansichten verteilt.
struct AetherTheme {
    var id: ThemeID
    var palette: ThemePalette
    var usesGlass: Bool
    var accent: Color
    var onAccent: Color
    /// 0…1 – 0 heißt deckende Flächen.
    var glassIntensity: Double
    var density: Density
    var motion: MotionLevel

    var isDark: Bool { palette.isDark }

    // Flächen
    var backgroundTop: Color { Color(palette.backgroundTop) }
    var backgroundBottom: Color { Color(palette.backgroundBottom) }
    var surface: Color { Color(palette.surface) }
    var hairline: Color { Color(palette.hairline) }
    var fieldFill: Color { Color(palette.fieldFill) }
    var hoverFill: Color { Color(palette.hoverFill) }
    var shadow: Color { Color(palette.shadow) }
    var edgeLight: Color { Color(palette.edgeLight) }
    var edgeDark: Color { Color(palette.edgeDark) }
    var sheen: Color { Color(palette.sheen) }
    var selectionFill: Color { accent.opacity(isDark ? 0.24 : 0.16) }

    // Text
    var textPrimary: Color { Color(palette.textPrimary) }
    var textSecondary: Color { Color(palette.textSecondary) }
    var textTertiary: Color { Color(palette.textTertiary) }

    // Messfarben
    var cpuUser: Color { Color(palette.cpuUser) }
    var cpuSystem: Color { Color(palette.cpuSystem) }
    var gpu: Color { Color(palette.gpu) }
    var memory: Color { Color(palette.memory) }
    var memoryWired: Color { Color(palette.memoryWired) }
    var memoryCompressed: Color { Color(palette.memoryCompressed) }
    var memoryCached: Color { Color(palette.memoryCached) }
    var storage: Color { Color(palette.storage) }
    var networkDown: Color { Color(palette.networkDown) }
    var networkUp: Color { Color(palette.networkUp) }
    var thermal: Color { Color(palette.thermal) }
    var battery: Color { Color(palette.battery) }

    // Status
    var statusNormal: Color { Color(palette.statusNormal) }
    var statusElevated: Color { Color(palette.statusElevated) }
    var statusCritical: Color { Color(palette.statusCritical) }
    var statusUnavailable: Color { Color(palette.statusUnavailable) }

    /// Effektive Glasnutzung (Theme, Regler, „Transparenz reduzieren“ werden vom Aufrufer berücksichtigt).
    var glassActive: Bool { usesGlass && glassIntensity > 0.05 }

    /// Deckkraft der Glastönung: bei 100 % Intensität die Palettenvorgabe, darunter zunehmend deckend.
    func tintOpacity(strong: Bool) -> Double {
        let base = strong ? palette.glassTintStrong.alpha : palette.glassTint.alpha
        let intensity = min(1, max(0, glassIntensity))
        return min(1, base + (1 - intensity) * (1 - base) * 0.9)
    }

    func glassTint(strong: Bool) -> Color {
        let rgba = strong ? palette.glassTintStrong : palette.glassTint
        return Color(rgba.withAlpha(tintOpacity(strong: strong)))
    }

    func color(for severity: PulseSeverity?) -> Color {
        switch severity {
        case .none, .some(.info): return statusNormal
        case .some(.elevated): return statusElevated
        case .some(.critical): return statusCritical
        }
    }

    func color(for pressure: PressureLevel) -> Color {
        switch pressure {
        case .normal: return statusNormal
        case .warning: return statusElevated
        case .critical: return statusCritical
        }
    }

    func color(for thermal: ThermalLevel) -> Color {
        switch thermal {
        case .nominal: return statusNormal
        case .fair: return statusNormal
        case .serious: return statusElevated
        case .critical: return statusCritical
        }
    }

    func batteryColor(percent: Int) -> Color {
        if percent <= 10 { return statusCritical }
        if percent <= 20 { return statusElevated }
        return battery
    }

    @MainActor
    static func resolve(settings: AppSettings, systemIsDark: Bool, reduceTransparency: Bool) -> AetherTheme {
        let spec = ThemeCatalog.spec(settings.theme)
        let dark: Bool
        switch spec.appearance {
        case .dark: dark = true
        case .light: dark = false
        case .system: dark = systemIsDark
        }
        let palette = spec.palette(dark: dark)
        let accentChoice = settings.accent
        let accent: Color
        let onAccent: Color
        if let fixed = accentChoice.fixed {
            let rgba = dark ? fixed.dark : fixed.light
            accent = Color(rgba)
            onAccent = Color(rgba.preferredForeground)
        } else {
            accent = Color(nsColor: .controlAccentColor)
            onAccent = .white
        }
        return AetherTheme(id: spec.id, palette: palette, usesGlass: spec.usesGlass && !reduceTransparency, accent: accent,
                           onAccent: onAccent, glassIntensity: reduceTransparency ? 0 : settings.glassIntensity,
                           density: settings.density, motion: settings.motion)
    }

    static let fallback = AetherTheme(id: .liquidGlassDark, palette: ThemeCatalog.glassDark, usesGlass: true,
                                      accent: Color(RGBA(0x6FA3FF)), onAccent: .black, glassIntensity: 1,
                                      density: .standard, motion: .full)
}

private struct AetherThemeKey: EnvironmentKey {
    static let defaultValue = AetherTheme.fallback
}

extension EnvironmentValues {
    var aether: AetherTheme {
        get { self[AetherThemeKey.self] }
        set { self[AetherThemeKey.self] = newValue }
    }
}

// MARK: - Abstände, Radien, Maße, Bewegung

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let gutter: CGFloat = 28
}

enum Radius {
    static let chip: CGFloat = 8
    static let control: CGFloat = 10
    static let tile: CGFloat = 14
    static let card: CGFloat = 20
    static let panel: CGFloat = 22
}

enum Metrics {
    static let sidebarWidth: CGFloat = 232
    static let sidebarInset: CGFloat = 10
    /// Platz für die Ampelknöpfe über der Seitenleiste.
    static let trafficLights: CGFloat = 46
    static let sidebarRow: CGFloat = 30
    static let headerTop: CGFloat = 26
    static let minWindow = CGSize(width: 960, height: 640)
}

enum Motion {
    static let spring = Animation.interpolatingSpring(stiffness: 380, damping: 2 * 0.86 * sqrt(380))
    static let gentle = Animation.interpolatingSpring(stiffness: 200, damping: 2 * 0.9 * sqrt(200))
    static func easeOut(_ duration: Double = 0.32) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: duration) }
    static let quick = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)
}

extension View {
    /// Animation abhängig von Einstellung und Systemeinstellung „Bewegung reduzieren“.
    func aetherAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(AetherAnimationModifier(animation: animation, value: value))
    }
}

private struct AetherAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.aether) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(effective, value: value)
    }

    private var effective: Animation? {
        if reduceMotion || theme.motion == .off { return nil }
        if theme.motion == .reduced { return .linear(duration: 0.12) }
        return animation
    }
}

// MARK: - Typografie (Systemschrift)

enum Typo {
    static let pageTitle = Font.system(size: 28, weight: .bold)
    static let pageSubtitle = Font.system(size: 13, weight: .regular)
    static let cardTitle = Font.system(size: 11, weight: .semibold)
    static let metricLarge = Font.system(size: 30, weight: .semibold, design: .rounded)
    static let metric = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let metricSmall = Font.system(size: 15, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 13)
    static let bodyMedium = Font.system(size: 13, weight: .medium)
    static let callout = Font.system(size: 12)
    static let caption = Font.system(size: 11)
    static let captionMedium = Font.system(size: 11, weight: .medium)
    static let mono = Font.system(size: 11, design: .monospaced)
    static let sectionLabel = Font.system(size: 10.5, weight: .semibold)
}

/// Native Liquid-Glass-Verfügbarkeit (macOS 26 und mit dem macOS-26-SDK gebaut).
enum LiquidGlass {
    static var isAvailable: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return !forceFallback }
        #endif
        return false
    }

    /// Für Vergleichsbilder im Build: Rückfall auch auf macOS 26 erzwingen.
    static var forceFallback: Bool = ProcessInfo.processInfo.environment["AETHER_FORCE_GLASS_FALLBACK"] == "1"
        || CommandLine.arguments.contains("--force-fallback")
}
