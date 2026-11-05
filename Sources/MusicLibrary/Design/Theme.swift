import SwiftUI
import AppKit

// =============================================================================================
// Designsystem der Musikbibliothek – übertragen aus ui/theme/Tokens.kt und Type.kt der Android-App.
//
// Farben: exakt die Android-Werte (ARGB). Hell und Dunkel sind eigenständig abgestimmt (warmes Weiß bzw.
// warmes Schwarz, Rosé-Akzent), nicht invertiert.
// Größen: Android-Werte in dp wurden für den Mac-Abstand (Bildschirm näher am Auge, Maus statt Finger)
// einheitlich auf ≈ 87 % gebracht – Proportionen und Hierarchie bleiben identisch.
// =============================================================================================

extension Color {
    /// Farbe aus einem Android-ARGB-Wert (0xAARRGGBB).
    init(argb: UInt32) {
        self.init(
            .sRGB,
            red: Double((argb >> 16) & 0xFF) / 255,
            green: Double((argb >> 8) & 0xFF) / 255,
            blue: Double(argb & 0xFF) / 255,
            opacity: Double((argb >> 24) & 0xFF) / 255
        )
    }
}

extension NSColor {
    convenience init(argb: UInt32) {
        self.init(
            srgbRed: CGFloat((argb >> 16) & 0xFF) / 255,
            green: CGFloat((argb >> 8) & 0xFF) / 255,
            blue: CGFloat(argb & 0xFF) / 255,
            alpha: CGFloat((argb >> 24) & 0xFF) / 255
        )
    }
}

/// Farbsatz der App (`MusicColors` in Tokens.kt).
struct MusicColors: Equatable {
    let dark: Bool
    let background: Color
    let backgroundGrouped: Color
    let surface: Color
    let surfaceMuted: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let accent: Color
    let accentText: Color
    let accentStrong: Color
    let accentSoft: Color
    let onAccent: Color
    let heart: Color
    let danger: Color
    let hairline: Color
    let ambient: [Color]
    let glassTint: Color
    let glassTintStrong: Color
    let glassEdgeLight: Color
    let glassEdgeDark: Color
    let glassSheen: Color
    let glassShadow: Color
    let scrim: Color
    /// Rohwerte für AppKit/Renderer.
    let backgroundARGB: UInt32
    let accentARGB: UInt32

    static let light = MusicColors(
        dark: false,
        background: Color(argb: 0xFFFBF8F7),
        backgroundGrouped: Color(argb: 0xFFF4EFEE),
        surface: Color(argb: 0xFFFFFFFF),
        surfaceMuted: Color(argb: 0xFFF1ECEB),
        textPrimary: Color(argb: 0xFF1D1B1C),
        textSecondary: Color(argb: 0xFF6B6466),
        textTertiary: Color(argb: 0xFF716A6C),
        accent: Color(argb: 0xFFD4566F),
        accentText: Color(argb: 0xFFB93A5A),
        accentStrong: Color(argb: 0xFFC23C5C),
        accentSoft: Color(argb: 0x1FD4566F),
        onAccent: Color(argb: 0xFFFFFFFF),
        heart: Color(argb: 0xFFC93D5C),
        danger: Color(argb: 0xFFC62F3A),
        hairline: Color(argb: 0x141D1B1C),
        ambient: [Color(argb: 0x80F4B8C5), Color(argb: 0x73F9D4C2), Color(argb: 0x59E2D3EE)],
        glassTint: Color(argb: 0x9EFFFFFF),
        glassTintStrong: Color(argb: 0xCCFFFFFF),
        glassEdgeLight: Color(argb: 0xE6FFFFFF),
        glassEdgeDark: Color(argb: 0x40FFFFFF),
        glassSheen: Color(argb: 0x59FFFFFF),
        glassShadow: Color(argb: 0x24301018),
        scrim: Color(argb: 0x52140A0E),
        backgroundARGB: 0xFFFBF8F7,
        accentARGB: 0xFFD4566F
    )

    static let darkPalette = MusicColors(
        dark: true,
        background: Color(argb: 0xFF0F0D0E),
        backgroundGrouped: Color(argb: 0xFF151213),
        surface: Color(argb: 0xFF1C1819),
        surfaceMuted: Color(argb: 0xFF231F20),
        textPrimary: Color(argb: 0xFFF6F2F3),
        textSecondary: Color(argb: 0xFFABA3A6),
        textTertiary: Color(argb: 0xFF8E8689),
        accent: Color(argb: 0xFFF27A93),
        accentText: Color(argb: 0xFFFF8FA6),
        accentStrong: Color(argb: 0xFFFF6F8F),
        accentSoft: Color(argb: 0x29F27A93),
        onAccent: Color(argb: 0xFF2A0E17),
        heart: Color(argb: 0xFFFF6F8F),
        danger: Color(argb: 0xFFFF6B6B),
        hairline: Color(argb: 0x17FFFFFF),
        ambient: [Color(argb: 0x528C2F48), Color(argb: 0x474B2440), Color(argb: 0x2E5A3324)],
        glassTint: Color(argb: 0xA81E1A1C),
        glassTintStrong: Color(argb: 0xD1241F21),
        glassEdgeLight: Color(argb: 0x38FFFFFF),
        glassEdgeDark: Color(argb: 0x0DFFFFFF),
        glassSheen: Color(argb: 0x14FFFFFF),
        glassShadow: Color(argb: 0x8C000000),
        scrim: Color(argb: 0x8C000000),
        backgroundARGB: 0xFF0F0D0E,
        accentARGB: 0xFFF27A93
    )

    static func forScheme(_ scheme: ColorScheme) -> MusicColors { scheme == .dark ? darkPalette : light }

    /// Zarte Füllfläche für Eingabefelder, Suchfeld und Segmente (Android: SearchField-Hintergrund).
    var fieldFill: Color { dark ? Color.white.opacity(0.08) : textPrimary.opacity(0.055) }
    /// Füllung der TONAL-Kapselschaltflächen.
    var tonalFill: Color { dark ? Color.white.opacity(0.09) : surfaceMuted }
    /// Feine Kontur um Cover.
    var artworkStroke: Color { dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06) }
    /// Auswahlhintergrund (Mehrfachauswahl in Listen).
    var selectionFill: Color { dark ? Color(argb: 0x38F27A93) : Color(argb: 0x26D4566F) }
}

// MARK: - Abstände, Radien, Bewegung

/// Abstände (4-pt-Raster, wie Android `Spacing`).
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    /// Seitenrand der Inhalte (Android 16 dp; auf dem Mac großzügiger, da Fenster breiter sind).
    static let gutter: CGFloat = 28
}

/// Eckenradien (Android `Radius`, unverändert).
enum Radius {
    static let artworkSmall: CGFloat = 7
    static let artwork: CGFloat = 10
    static let artworkLarge: CGFloat = 14
    static let control: CGFloat = 12
    static let card: CGFloat = 18
    static let panel: CGFloat = 26
    static let bar: CGFloat = 30
}

/// Feste Maße der Bedienelemente (aus den Android-Komponenten abgeleitet).
enum Metrics {
    static let navBarHeight: CGFloat = 52          // Android 64 dp
    static let miniPlayerHeight: CGFloat = 62      // Android 60 dp, auf dem Mac mit Fortschritt & Lautstärke
    static let trackRowHeight: CGFloat = 54        // Android 64 dp
    static let trackArtwork: CGFloat = 40          // Android 48 dp
    static let compactBarHeight: CGFloat = 46      // Android 52 dp
    static let gridMinCell: CGFloat = 168
    static let searchFieldHeight: CGFloat = 34     // Android 42 dp
    static let pillHeight: CGFloat = 34            // Android 44 dp
}

/// Bewegung (Android `Motion`): „Apple-artige“ Ausklingkurve, weiche Federn.
enum Motion {
    static let short: Double = 0.16
    static let medium: Double = 0.28
    static let long: Double = 0.42
    /// cubic-bezier(0.22, 1, 0.36, 1)
    static func easeOut(_ duration: Double = medium) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: duration) }
    static func easeInOut(_ duration: Double = medium) -> Animation { .timingCurve(0.42, 0, 0.2, 1, duration: duration) }
    /// spring(dampingRatio 0.86, stiffness 420) → Antwortzeit ≈ 2π/√k
    static let standardSpring = Animation.interpolatingSpring(stiffness: 420, damping: 2 * 0.86 * sqrt(420))
    static let gentleSpring = Animation.interpolatingSpring(stiffness: 200, damping: 2 * 0.9 * sqrt(200))
    static let bouncySpring = Animation.interpolatingSpring(stiffness: 500, damping: 2 * 0.6 * sqrt(500))
    /// Navigationslinse (Android: dampingRatio 0.78, stiffness 380).
    static let lensSpring = Animation.interpolatingSpring(stiffness: 380, damping: 2 * 0.78 * sqrt(380))
    /// Player öffnen/schließen (Android: dampingRatio 0.9, stiffness 340).
    static let playerSpring = Animation.interpolatingSpring(stiffness: 340, damping: 2 * 0.9 * sqrt(340))
}

// MARK: - Typografie (Inter, wie Android Type.kt)

enum InterWeight {
    case regular, medium, semibold, bold

    var postScript: String {
        switch self {
        case .regular: return "Inter-Regular"
        case .medium: return "Inter-Medium"
        case .semibold: return "Inter-SemiBold"
        case .bold: return "Inter-Bold"
        }
    }

    var systemWeight: Font.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}

/// Ein Textstil mit Laufweite (Android: letterSpacing in em).
struct TextStyle {
    let font: Font
    let nsFont: NSFont
    let size: CGFloat
    /// Laufweite in Punkt (em × Größe).
    let tracking: CGFloat
    let lineSpacing: CGFloat
}

enum Typo {
    /// Wurden die Inter-Schriften registriert? (Fallback: Systemschrift mit gleichem Gewicht)
    static var interAvailable: Bool = {
        NSFont(name: "Inter-Regular", size: 12) != nil
    }()

    static func inter(_ size: CGFloat, _ weight: InterWeight, display: Bool = false) -> Font {
        if interAvailable {
            if display {
                return .custom(weight == .bold ? "InterDisplay-Bold" : "InterDisplay-SemiBold", fixedSize: size)
            }
            return .custom(weight.postScript, fixedSize: size)
        }
        return .system(size: size, weight: weight.systemWeight, design: .default)
    }

    static func nsInter(_ size: CGFloat, _ weight: InterWeight, display: Bool = false) -> NSFont {
        let name = display ? (weight == .bold ? "InterDisplay-Bold" : "InterDisplay-SemiBold") : weight.postScript
        return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: {
            switch weight {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            }
        }())
    }

    private static func style(_ size: CGFloat, _ line: CGFloat, _ weight: InterWeight, _ trackingEm: CGFloat, display: Bool = false) -> TextStyle {
        TextStyle(font: inter(size, weight, display: display), nsFont: nsInter(size, weight, display: display), size: size,
                  tracking: trackingEm * size, lineSpacing: max(0, line - size * 1.21))
    }

    // Android: displayLarge 56/60 … labelSmall 11/13, hier × ≈ 0,87
    static let displayLarge = style(48, 52, .bold, -0.022, display: true)
    static let displayMedium = style(38, 44, .bold, -0.02, display: true)
    static let displaySmall = style(31, 36, .bold, -0.02, display: true)
    static let headlineLarge = style(28, 33, .bold, -0.02, display: true)
    static let headlineMedium = style(23, 28, .bold, -0.018, display: true)
    static let headlineSmall = style(19, 24, .bold, -0.015, display: true)
    static let titleLarge = style(17.5, 22, .semibold, -0.014)
    static let titleMedium = style(15, 19, .semibold, -0.012)
    static let titleSmall = style(13.5, 17.5, .semibold, -0.009)
    static let bodyLarge = style(14, 18.5, .regular, -0.011)
    static let bodyMedium = style(13, 17.5, .regular, -0.009)
    static let bodySmall = style(11.5, 15, .regular, -0.004)
    static let labelLarge = style(13, 17.5, .semibold, -0.009)
    static let labelMedium = style(11.5, 14, .medium, 0)
    static let labelSmall = style(10, 12, .medium, 0.006)
    /// Kleine Abschnittsüberschrift in Versalien.
    static let sectionLabel = style(10.5, 14, .semibold, 0.04)
    /// Zeit- und Zahlenangaben (gleich breite Ziffern).
    static let time = style(10.5, 14, .medium, 0)
    static let duration = style(11.5, 15, .regular, 0)
}

extension View {
    /// Wendet einen Textstil an (Schrift + Laufweite).
    func textStyle(_ style: TextStyle) -> some View {
        self.font(style.font).tracking(style.tracking)
    }

    /// Gleich breite Ziffern (Android: fontFeatureSettings „tnum“).
    func tabularDigits() -> some View {
        self.monospacedDigit()
    }
}

// MARK: - Umgebung

private struct MusicColorsKey: EnvironmentKey {
    static let defaultValue = MusicColors.light
}

private struct GlassEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var musicColors: MusicColors {
        get { self[MusicColorsKey.self] }
        set { self[MusicColorsKey.self] = newValue }
    }

    /// Glas-Effekte eingeschaltet? (Einstellung; aus = ruhige, undurchsichtige Flächen)
    var glassEnabled: Bool {
        get { self[GlassEnabledKey.self] }
        set { self[GlassEnabledKey.self] = newValue }
    }
}

/// Setzt den Farbsatz passend zum Erscheinungsbild der Ansicht.
struct MusicThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let glass: Bool

    func body(content: Content) -> some View {
        let colors = MusicColors.forScheme(scheme)
        content
            .environment(\.musicColors, colors)
            .environment(\.glassEnabled, glass)
            .tint(colors.accent)
            .foregroundColor(colors.textPrimary)
    }
}

extension View {
    func musicTheme(glass: Bool = true) -> some View { modifier(MusicThemeModifier(glass: glass)) }
}
