import SwiftUI
import AppKit

// =============================================================================================
// Farben und Typografie von Panora. Klar und ruhig: tiefes Graphit bzw. kühles Weiß, Akzent im Blau
// des App-Symbols. Keine Lila- oder Violetttöne.
// =============================================================================================

struct PanoraColors {
    let dark: Bool

    var background: Color { dark ? Color(hex: 0x0A0C10) : Color(hex: 0xF3F5F9) }
    var surface: Color { dark ? Color(hex: 0x14171E) : Color.white }
    var surfaceRaised: Color { dark ? Color(hex: 0x1B1F28) : Color(hex: 0xF8FAFD) }
    var surfaceSunken: Color { dark ? Color(hex: 0x0F1116) : Color(hex: 0xEBEEF4) }
    var textPrimary: Color { dark ? Color(hex: 0xF2F4F8) : Color(hex: 0x10141B) }
    var textSecondary: Color { dark ? Color(hex: 0xA9B0BD) : Color(hex: 0x4B5361) }
    var textTertiary: Color { dark ? Color(hex: 0x6E7685) : Color(hex: 0x8A93A3) }
    var accent: Color { dark ? Color(hex: 0x5AA8FF) : Color(hex: 0x1F6FE5) }
    var accentStrong: Color { dark ? Color(hex: 0x7DBBFF) : Color(hex: 0x1559C4) }
    var accentSoft: Color { accent.opacity(dark ? 0.20 : 0.13) }
    var accentText: Color { dark ? Color(hex: 0x8CC4FF) : Color(hex: 0x1559C4) }
    var hairline: Color { dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08) }
    var success: Color { dark ? Color(hex: 0x4FD18B) : Color(hex: 0x16A34A) }
    var warning: Color { dark ? Color(hex: 0xF5B94A) : Color(hex: 0xC27C0E) }
    var danger: Color { dark ? Color(hex: 0xFF6B6B) : Color(hex: 0xDC2626) }
    var teal: Color { dark ? Color(hex: 0x4FD1C5) : Color(hex: 0x0F9488) }

    var glassTint: Color { dark ? Color(hex: 0x161A22).opacity(0.62) : Color.white.opacity(0.62) }
    var glassTintStrong: Color { dark ? Color(hex: 0x161A22).opacity(0.84) : Color.white.opacity(0.84) }
    var glassEdgeLight: Color { dark ? Color.white.opacity(0.16) : Color.white.opacity(0.95) }
    var glassEdgeDark: Color { dark ? Color.white.opacity(0.04) : Color.black.opacity(0.07) }
    var glassShadow: Color { Color.black.opacity(dark ? 0.45 : 0.14) }
    var glassSheen: Color { Color.white.opacity(dark ? 0.06 : 0.45) }

    /// Weiche Farbinseln im Hintergrund: Blau, Türkis, Silber.
    var ambient: [Color] {
        dark ? [Color(hex: 0x1D4ED8).opacity(0.22), Color(hex: 0x0E7490).opacity(0.16), Color(hex: 0x94A3B8).opacity(0.08)]
             : [Color(hex: 0x93C5FD).opacity(0.40), Color(hex: 0x99F6E4).opacity(0.28), Color(hex: 0xCBD5E1).opacity(0.40)]
    }

    /// Farbe einer Modellfamilie (für „Cover“ der Modellkarten).
    func family(_ name: String) -> [Color] {
        switch name {
        case "Qwen": return [Color(hex: 0x2563EB), Color(hex: 0x06B6D4)]
        case "Gemma": return [Color(hex: 0x0EA5E9), Color(hex: 0x34D399)]
        case "Llama": return [Color(hex: 0x0F172A), Color(hex: 0x3B82F6)]
        case "Mistral": return [Color(hex: 0xF97316), Color(hex: 0xFACC15)]
        case "DeepSeek": return [Color(hex: 0x1E3A8A), Color(hex: 0x60A5FA)]
        case "gpt-oss": return [Color(hex: 0x111827), Color(hex: 0x10B981)]
        case "Phi": return [Color(hex: 0x0369A1), Color(hex: 0x7DD3FC)]
        default: return [Color(hex: 0x334155), Color(hex: 0x94A3B8)]
        }
    }
}

private struct PanoraColorsKey: EnvironmentKey {
    static let defaultValue = PanoraColors(dark: true)
}

private struct GlassEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var panora: PanoraColors {
        get { self[PanoraColorsKey.self] }
        set { self[PanoraColorsKey.self] = newValue }
    }

    var glassEnabled: Bool {
        get { self[GlassEnabledKey.self] }
        set { self[GlassEnabledKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

enum Typo {
    static func title(_ size: CGFloat = 34) -> Font { .system(size: size, weight: .bold, design: .default) }
    static func section(_ size: CGFloat = 22) -> Font { .system(size: size, weight: .bold) }
    static func body(_ size: CGFloat = 14, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    static func label(_ size: CGFloat = 12, _ weight: Font.Weight = .medium) -> Font { .system(size: size, weight: weight) }
    static func mono(_ size: CGFloat = 12.5) -> Font { .system(size: size, weight: .regular, design: .monospaced) }
}

enum Motion {
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.84)
    static let lens = Animation.spring(response: 0.38, dampingFraction: 0.8)
    static let quick = Animation.easeOut(duration: 0.18)
    static let medium = Animation.easeOut(duration: 0.28)
}

enum Metrics {
    static let navHeight: CGFloat = 60
    static let navItemWidth: CGFloat = 82
    static let topPadding: CGFloat = 12
    static let contentTop: CGFloat = topPadding + navHeight + 18
    static let pageInset: CGFloat = 40
    static let cardRadius: CGFloat = 14
}
