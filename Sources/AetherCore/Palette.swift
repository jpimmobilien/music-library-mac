import Foundation

// =============================================================================================
// Themes als reine Daten. Die App wandelt sie in Farben um; hier lassen sie sich ohne Apple-Frameworks prüfen
// (Kontrast nach WCAG für jedes Theme, Unit-Tests auch unter Linux).
// =============================================================================================

/// sRGB-Farbe mit Deckkraft.
public struct RGBA: Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(_ hex: UInt32, _ alpha: Double = 1) {
        self.red = Double((hex >> 16) & 0xFF) / 255
        self.green = Double((hex >> 8) & 0xFF) / 255
        self.blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    public func withAlpha(_ alpha: Double) -> RGBA { RGBA(red: red, green: green, blue: blue, alpha: alpha) }

    /// Diese Farbe über einer deckenden Grundfarbe.
    public func composited(over base: RGBA) -> RGBA {
        let a = alpha
        return RGBA(red: red * a + base.red * (1 - a), green: green * a + base.green * (1 - a),
                    blue: blue * a + base.blue * (1 - a), alpha: 1)
    }

    /// Relative Leuchtdichte nach WCAG 2.x.
    public var relativeLuminance: Double {
        func channel(_ c: Double) -> Double { c <= 0.039_28 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// Kontrastverhältnis zweier deckender Farben (1…21).
    public static func contrast(_ a: RGBA, _ b: RGBA) -> Double {
        let la = a.relativeLuminance, lb = b.relativeLuminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Weiß oder fast Schwarz – je nachdem, was auf dieser Fläche besser lesbar ist.
    public var preferredForeground: RGBA {
        let white = RGBA(0xFFFFFF), ink = RGBA(0x0B1020)
        return RGBA.contrast(self, white) >= RGBA.contrast(self, ink) ? white : ink
    }
}

/// Alle Farben eines Themes in einer Erscheinung (hell oder dunkel).
public struct ThemePalette: Equatable, Sendable {
    public var isDark: Bool
    // Hintergrund
    public var backgroundTop: RGBA
    public var backgroundBottom: RGBA
    /// Atmosphäre: weiche Farbinseln hinter dem Glas (leer = keine).
    public var ambient: [RGBA]
    // Flächen
    /// Deckende Karte (ohne Glas bzw. bei Glasintensität 0).
    public var surface: RGBA
    /// Tönung der Glasflächen (mit Deckkraft).
    public var glassTint: RGBA
    /// Stärkere Tönung für Karten mit Zahlen.
    public var glassTintStrong: RGBA
    public var edgeLight: RGBA
    public var edgeDark: RGBA
    public var sheen: RGBA
    public var shadow: RGBA
    public var hairline: RGBA
    public var fieldFill: RGBA
    public var hoverFill: RGBA
    // Text
    public var textPrimary: RGBA
    public var textSecondary: RGBA
    public var textTertiary: RGBA
    // Messfarben
    public var cpuUser: RGBA
    public var cpuSystem: RGBA
    public var gpu: RGBA
    public var memory: RGBA
    public var memoryWired: RGBA
    public var memoryCompressed: RGBA
    public var memoryCached: RGBA
    public var storage: RGBA
    public var networkDown: RGBA
    public var networkUp: RGBA
    public var thermal: RGBA
    public var battery: RGBA
    // Status
    public var statusNormal: RGBA
    public var statusElevated: RGBA
    public var statusCritical: RGBA
    public var statusUnavailable: RGBA

    /// Ungefähre deckende Kartenfarbe für Kontrastprüfungen (Glas-Tönung über der Hintergrundmitte).
    public var contrastBase: RGBA {
        let mid = RGBA(red: (backgroundTop.red + backgroundBottom.red) / 2,
                       green: (backgroundTop.green + backgroundBottom.green) / 2,
                       blue: (backgroundTop.blue + backgroundBottom.blue) / 2)
        return glassTintStrong.composited(over: mid)
    }
}

public enum Appearance: String, Codable, Sendable {
    case light, dark, system
}

/// Die sechs Themes.
public enum ThemeID: String, Codable, Sendable, CaseIterable, Identifiable {
    case liquidGlassDark
    case liquidGlassLight
    case minimalDark
    case minimalLight
    case graphite
    case system

    public var id: String { rawValue }
}

public struct ThemeSpec: Equatable, Sendable {
    public var id: ThemeID
    public var appearance: Appearance
    /// Glasflächen (sonst deckende Flächen mit Haarlinien).
    public var usesGlass: Bool
    public var light: ThemePalette?
    public var dark: ThemePalette?
    public var defaultAccent: AccentChoice

    /// Palette für die tatsächliche Erscheinung.
    public func palette(dark isDark: Bool) -> ThemePalette {
        if isDark { return dark ?? light! }
        return light ?? dark!
    }

    public var palettes: [ThemePalette] { [light, dark].compactMap { $0 } }
}

/// Akzentfarben.
public enum AccentChoice: String, Codable, Sendable, CaseIterable, Identifiable {
    case system
    /// „Arctic Blue“ (ORBIT-Standard). Der gespeicherte Name stammt aus der Zeit vor der Umbenennung.
    case aetherBlue
    /// „Electric Cyan“ (ORBIT)
    case electricCyan
    case mint
    case violet
    case orange
    case pink
    case graphite

    public var id: String { rawValue }

    /// Feste Farbwerte (hell, dunkel). `system` wird in der App aus der Systemeinstellung gelesen.
    public var fixed: (light: RGBA, dark: RGBA)? {
        switch self {
        case .system: return nil
        case .aetherBlue: return (RGBA(0x0B6BEA), RGBA(0x5AB4FF))
        case .electricCyan: return (RGBA(0x007C99), RGBA(0x2EE6F6))
        case .mint: return (RGBA(0x0B8F74), RGBA(0x4FE0BF))
        case .violet: return (RGBA(0x6D3FE6), RGBA(0xAE8DFF))
        case .orange: return (RGBA(0xB4500B), RGBA(0xFFA552))
        case .pink: return (RGBA(0xC72F6A), RGBA(0xFF82AE))
        case .graphite: return (RGBA(0x4B5260), RGBA(0xB3B8C2))
        }
    }
}

public enum ThemeCatalog {
    public static func spec(_ id: ThemeID) -> ThemeSpec {
        switch id {
        case .liquidGlassDark:
            return ThemeSpec(id: id, appearance: .dark, usesGlass: true, light: nil, dark: glassDark, defaultAccent: .aetherBlue)
        case .liquidGlassLight:
            return ThemeSpec(id: id, appearance: .light, usesGlass: true, light: glassLight, dark: nil, defaultAccent: .aetherBlue)
        case .minimalDark:
            return ThemeSpec(id: id, appearance: .dark, usesGlass: false, light: nil, dark: minimalDark, defaultAccent: .aetherBlue)
        case .minimalLight:
            return ThemeSpec(id: id, appearance: .light, usesGlass: false, light: minimalLight, dark: nil, defaultAccent: .aetherBlue)
        case .graphite:
            return ThemeSpec(id: id, appearance: .dark, usesGlass: true, light: nil, dark: graphite, defaultAccent: .graphite)
        case .system:
            return ThemeSpec(id: id, appearance: .system, usesGlass: true, light: glassLight, dark: glassDark, defaultAccent: .system)
        }
    }

    public static var all: [ThemeSpec] { ThemeID.allCases.map(spec) }

    // MARK: Liquid Glass Dark – „Deep Ocean“ (ORBIT)

    public static let glassDark = ThemePalette(
        isDark: true,
        backgroundTop: RGBA(0x0B1830), backgroundBottom: RGBA(0x050A16),
        ambient: [RGBA(0x1E6BFF, 0.34), RGBA(0x12C8E8, 0.22), RGBA(0x7B5CFF, 0.22)],
        surface: RGBA(0x15203A),
        glassTint: RGBA(0x15203A, 0.52), glassTintStrong: RGBA(0x16223D, 0.70),
        edgeLight: RGBA(0xFFFFFF, 0.22), edgeDark: RGBA(0xFFFFFF, 0.05), sheen: RGBA(0xFFFFFF, 0.07),
        shadow: RGBA(0x000000, 0.55), hairline: RGBA(0xFFFFFF, 0.09),
        fieldFill: RGBA(0xFFFFFF, 0.07), hoverFill: RGBA(0xFFFFFF, 0.06),
        textPrimary: RGBA(0xF2F5FA), textSecondary: RGBA(0xA9B2C4), textTertiary: RGBA(0x7F899D),
        cpuUser: RGBA(0x5AA9FF), cpuSystem: RGBA(0xFF7A6B), gpu: RGBA(0x8F9BFF),
        memory: RGBA(0xA48CFF), memoryWired: RGBA(0xFFB648), memoryCompressed: RGBA(0xFF6AC1), memoryCached: RGBA(0x6C7A96),
        storage: RGBA(0x7FD4FF), networkDown: RGBA(0x2EE6F6), networkUp: RGBA(0x9DB4FF),
        thermal: RGBA(0xFF9F45), battery: RGBA(0x4CD964),
        statusNormal: RGBA(0x3DDC84), statusElevated: RGBA(0xFFB340), statusCritical: RGBA(0xFF5A5F),
        statusUnavailable: RGBA(0x7F899D)
    )

    // MARK: Liquid Glass Light – „Pearl White“ (ORBIT)

    public static let glassLight = ThemePalette(
        isDark: false,
        backgroundTop: RGBA(0xF8FAFD), backgroundBottom: RGBA(0xE8EEF6),
        ambient: [RGBA(0x8CC4FF, 0.50), RGBA(0x9EEFFF, 0.40), RGBA(0xCFC2FF, 0.42)],
        surface: RGBA(0xFFFFFF),
        glassTint: RGBA(0xFFFFFF, 0.56), glassTintStrong: RGBA(0xFFFFFF, 0.78),
        edgeLight: RGBA(0xFFFFFF, 0.95), edgeDark: RGBA(0xFFFFFF, 0.30), sheen: RGBA(0xFFFFFF, 0.50),
        shadow: RGBA(0x1B2440, 0.13), hairline: RGBA(0x101828, 0.08),
        fieldFill: RGBA(0x101828, 0.05), hoverFill: RGBA(0x101828, 0.05),
        textPrimary: RGBA(0x0F1524), textSecondary: RGBA(0x566072), textTertiary: RGBA(0x7A8393),
        cpuUser: RGBA(0x0B6BEA), cpuSystem: RGBA(0xE5484D), gpu: RGBA(0x2446C8),
        memory: RGBA(0x6E56E8), memoryWired: RGBA(0xE08A00), memoryCompressed: RGBA(0xD9409E), memoryCached: RGBA(0x98A2B3),
        storage: RGBA(0x0F7FB8), networkDown: RGBA(0x0598B3), networkUp: RGBA(0x4F5FD6),
        thermal: RGBA(0xE8700A), battery: RGBA(0x1FA75A),
        statusNormal: RGBA(0x178F4E), statusElevated: RGBA(0xB57200), statusCritical: RGBA(0xD7373F),
        statusUnavailable: RGBA(0x8A93A3)
    )

    // MARK: Minimal Dark

    public static let minimalDark = ThemePalette(
        isDark: true,
        backgroundTop: RGBA(0x0B0B0D), backgroundBottom: RGBA(0x0B0B0D),
        ambient: [],
        surface: RGBA(0x161618),
        glassTint: RGBA(0x161618, 1), glassTintStrong: RGBA(0x161618, 1),
        edgeLight: RGBA(0xFFFFFF, 0.10), edgeDark: RGBA(0xFFFFFF, 0.10), sheen: RGBA(0xFFFFFF, 0),
        shadow: RGBA(0x000000, 0), hairline: RGBA(0xFFFFFF, 0.09),
        fieldFill: RGBA(0xFFFFFF, 0.07), hoverFill: RGBA(0xFFFFFF, 0.05),
        textPrimary: RGBA(0xF5F5F7), textSecondary: RGBA(0xA1A1A6), textTertiary: RGBA(0x75757B),
        cpuUser: RGBA(0x64C4F5), cpuSystem: RGBA(0xF2867A), gpu: RGBA(0xB898F2),
        memory: RGBA(0x5CCFA5), memoryWired: RGBA(0xEFB45C), memoryCompressed: RGBA(0xEE7DBF), memoryCached: RGBA(0x6E6E76),
        storage: RGBA(0xEFB45C), networkDown: RGBA(0x55C6D3), networkUp: RGBA(0xEE7DBF),
        thermal: RGBA(0xF0A055), battery: RGBA(0x5CCF72),
        statusNormal: RGBA(0x4CCB82), statusElevated: RGBA(0xF0B44A), statusCritical: RGBA(0xF0625F),
        statusUnavailable: RGBA(0x75757B)
    )

    // MARK: Minimal Light

    public static let minimalLight = ThemePalette(
        isDark: false,
        backgroundTop: RGBA(0xF5F5F7), backgroundBottom: RGBA(0xF5F5F7),
        ambient: [],
        surface: RGBA(0xFFFFFF),
        glassTint: RGBA(0xFFFFFF, 1), glassTintStrong: RGBA(0xFFFFFF, 1),
        edgeLight: RGBA(0x000000, 0.08), edgeDark: RGBA(0x000000, 0.08), sheen: RGBA(0xFFFFFF, 0),
        shadow: RGBA(0x000000, 0.04), hairline: RGBA(0x000000, 0.08),
        fieldFill: RGBA(0x000000, 0.045), hoverFill: RGBA(0x000000, 0.04),
        textPrimary: RGBA(0x1D1D1F), textSecondary: RGBA(0x6E6E73), textTertiary: RGBA(0x8A8A8F),
        cpuUser: RGBA(0x0A7AEF), cpuSystem: RGBA(0xDC4A45), gpu: RGBA(0x8656E8),
        memory: RGBA(0x0E9E72), memoryWired: RGBA(0xD08200), memoryCompressed: RGBA(0xCC3D94), memoryCached: RGBA(0xA1A1A6),
        storage: RGBA(0xD08200), networkDown: RGBA(0x0D97A5), networkUp: RGBA(0xCC3D94),
        thermal: RGBA(0xDE6A0A), battery: RGBA(0x1E9E52),
        statusNormal: RGBA(0x1E9E52), statusElevated: RGBA(0xC98000), statusCritical: RGBA(0xD0353C),
        statusUnavailable: RGBA(0x8A8A8F)
    )

    // MARK: Graphite

    public static let graphite = ThemePalette(
        isDark: true,
        backgroundTop: RGBA(0x2B2D31), backgroundBottom: RGBA(0x1F2125),
        ambient: [RGBA(0x5B6170, 0.22), RGBA(0x4A4F5A, 0.18)],
        surface: RGBA(0x323439),
        glassTint: RGBA(0x34363B, 0.55), glassTintStrong: RGBA(0x35373C, 0.74),
        edgeLight: RGBA(0xFFFFFF, 0.16), edgeDark: RGBA(0xFFFFFF, 0.04), sheen: RGBA(0xFFFFFF, 0.05),
        shadow: RGBA(0x000000, 0.45), hairline: RGBA(0xFFFFFF, 0.08),
        fieldFill: RGBA(0xFFFFFF, 0.07), hoverFill: RGBA(0xFFFFFF, 0.06),
        textPrimary: RGBA(0xEDEEF0), textSecondary: RGBA(0xB4B7BE), textTertiary: RGBA(0x8D919A),
        cpuUser: RGBA(0x8FB8DE), cpuSystem: RGBA(0xD99C94), gpu: RGBA(0xB7A3D9),
        memory: RGBA(0x8CCBB4), memoryWired: RGBA(0xD9B77E), memoryCompressed: RGBA(0xCF97B8), memoryCached: RGBA(0x7A7F89),
        storage: RGBA(0xD9B77E), networkDown: RGBA(0x86C5CC), networkUp: RGBA(0xCF97B8),
        thermal: RGBA(0xDDA36F), battery: RGBA(0x8CCB9A),
        statusNormal: RGBA(0x8CCB9A), statusElevated: RGBA(0xE0B464), statusCritical: RGBA(0xE07C78),
        statusUnavailable: RGBA(0x8D919A)
    )
}
