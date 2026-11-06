import SwiftUI
import AppKit
import MLCore

// MARK: - Hintergrund des großen Players (v2.1, §12)
//
// „Automatisch (Cover)“ ist exakt das bisherige Verhalten (Hintergrund je Design aus den Farben des Covers).
// Alle anderen Stile füllen den Hintergrund mit einer festen bzw. eigenen Farbe – mit den Glas- und
// Lichtschichten der App, damit der Charakter erhalten bleibt. Schrift und Bedienelemente richten sich nach der
// Helligkeit der Fläche (`isLight(custom:)`), unabhängig von Hell/Dunkel der App. Auch die immer dunklen
// Designs (Classic, Cassette, Studio Reel) bekommen auf hellen Flächen dunkle Schrift.

extension PlayerBackgroundStyle {
    /// Grundfarbe (deckend) oder `nil` bei „Automatisch“.
    func baseARGB(custom: UInt32) -> UInt32? {
        if self == .auto { return nil }
        return (argb ?? custom) | 0xFF00_0000
    }

    /// Farbe für die Auswahl (Farbfeld); `nil` bei „Automatisch“.
    func swatchColor(custom: UInt32) -> Color? {
        baseARGB(custom: custom).map { Color(argb: $0) }
    }
}

extension AppSettings {
    /// Tönung des Mini-Players in der Farbe des Player-Hintergrunds – `nil` bei „Automatisch“ oder ausgeschaltet
    /// (dann wie bisher der Schein des Covers).
    var miniPlayerTintARGB: UInt32? {
        guard playerBackgroundTintsMini else { return nil }
        return playerBackground.baseARGB(custom: playerBackgroundCustom)
    }
}

extension MusicColors {
    /// Farbsatz des großen Players unter Berücksichtigung des gewählten Hintergrunds.
    static func forPlayer(_ theme: PlayerTheme, app: MusicColors, background: PlayerBackgroundStyle, custom: UInt32) -> MusicColors {
        guard let base = background.baseARGB(custom: custom) else { return forPlayer(theme, app: app) }
        return coloredPlayer(base: base, light: background.isLight(custom: custom), theme: theme, app: app)
    }

    /// Farbsatz für einen farbigen Player-Hintergrund: helle Fläche → dunkle Schrift (heller Farbsatz),
    /// dunkle Fläche → helle Schrift (dunkler Farbsatz bzw. der des immer dunklen Designs). Zweit- und
    /// Drittschrift als durchscheinendes Schwarz bzw. Weiß – so bleibt der Kontrast auf jeder Farbe gleich.
    static func coloredPlayer(base: UInt32, light: Bool, theme: PlayerTheme, app: MusicColors) -> MusicColors {
        let p: MusicColors = light ? .light : (theme.uiAlwaysDark ? forPlayer(theme, app: app) : .darkPalette)
        return MusicColors(
            dark: !light,
            background: Color(argb: base),
            backgroundGrouped: p.backgroundGrouped,
            surface: p.surface,
            surfaceMuted: p.surfaceMuted,
            textPrimary: light ? Color(argb: 0xFF1D1B1C) : Color(argb: 0xFFFFFFFF),
            textSecondary: light ? Color(argb: 0xA81D1B1C) : Color(argb: 0xC2FFFFFF),
            textTertiary: light ? Color(argb: 0x8C1D1B1C) : Color(argb: 0x99FFFFFF),
            accent: p.accent,
            accentText: light ? p.accentText : Color(argb: 0xFFFFA8BA),
            accentStrong: p.accentStrong,
            accentSoft: p.accentSoft,
            onAccent: p.onAccent,
            heart: p.heart,
            danger: p.danger,
            hairline: light ? Color(argb: 0x1A000000) : Color(argb: 0x1FFFFFFF),
            ambient: p.ambient,
            glassTint: p.glassTint,
            glassTintStrong: p.glassTintStrong,
            glassEdgeLight: p.glassEdgeLight,
            glassEdgeDark: p.glassEdgeDark,
            glassSheen: p.glassSheen,
            glassShadow: p.glassShadow,
            scrim: p.scrim,
            backgroundARGB: base,
            accentARGB: p.accentARGB
        )
    }
}

/// Umrechnung Farbe ↔ ARGB (sRGB, deckend).
enum ColorARGB {
    static func argb(_ color: NSColor) -> UInt32 {
        guard let c = color.usingColorSpace(.sRGB) else { return 0xFF6B_4FA0 }
        func byte(_ v: CGFloat) -> UInt32 { UInt32(min(255, max(0, (v * 255).rounded()))) }
        return 0xFF00_0000 | byte(c.redComponent) << 16 | byte(c.greenComponent) << 8 | byte(c.blueComponent)
    }

    static func argb(_ color: Color) -> UInt32 { argb(NSColor(color)) }

    /// Farbe heller (> 0) bzw. dunkler (< 0) – für die sanften Verläufe der Farbfläche.
    static func shade(_ argb: UInt32, _ amount: Double) -> Color {
        let r = Double((argb >> 16) & 0xFF) / 255
        let g = Double((argb >> 8) & 0xFF) / 255
        let b = Double(argb & 0xFF) / 255
        func mix(_ v: Double) -> Double { amount >= 0 ? v + (1 - v) * amount : v * (1 + amount) }
        return Color(.sRGB, red: mix(r), green: mix(g), blue: mix(b), opacity: 1)
    }
}

/// Systemfarbwähler für die eigene Hintergrundfarbe aus Menüs heraus. Popover schließen sich beim Klick in den
/// Farbwähler – ein `ColorPicker` im Popover verlöre dann seine Verbindung. Darum ein dauerhaftes Ziel, das jede
/// Änderung direkt in die Einstellungen schreibt.
@MainActor
final class PlayerColorPanel: NSObject {
    static let shared = PlayerColorPanel()
    private var apply: ((UInt32) -> Void)?

    func open(initial: UInt32, apply: @escaping (UInt32) -> Void) {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = NSColor(argb: initial | 0xFF00_0000)
        self.apply = apply
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        apply?(ColorARGB.argb(sender.color))
    }
}

/// Schreibt die Auswahl des Player-Hintergrunds (eine Zuweisung – eine Speicherung, eine Aktualisierung).
@MainActor
enum PlayerBackgroundChoice {
    static func select(_ style: PlayerBackgroundStyle, model: AppModel) {
        guard model.settings.playerBackground != style else { return }
        withAnimation(PlayerMotionPolicy.transition(model.settings)) { model.settings.playerBackground = style }
    }

    /// Eigene Farbe setzen (und „Eigene Farbe“ auswählen).
    static func setCustom(_ argb: UInt32, model: AppModel) {
        var s = model.settings
        s.playerBackgroundCustom = argb | 0xFF00_0000
        s.playerBackground = .custom
        model.settings = s
    }
}

/// Rundes Farbfeld eines Hintergrundstils (Automatisch: Farbkreis mit Cover-Symbol, Eigene Farbe: mit Palette).
struct PlayerBackgroundSwatch: View {
    @Environment(\.musicColors) private var colors
    let style: PlayerBackgroundStyle
    let custom: UInt32
    let selected: Bool
    var diameter: CGFloat = 28
    let action: () -> Void

    var body: some View {
        let base = style.baseARGB(custom: custom)
        let light = style.isLight(custom: custom)
        Button(action: action) {
            ZStack {
                if let base {
                    Circle().fill(LinearGradient(colors: [ColorARGB.shade(base, 0.08), Color(argb: base), ColorARGB.shade(base, -0.12)],
                                                 startPoint: .top, endPoint: .bottom))
                } else {
                    Circle().fill(AngularGradient(gradient: Gradient(colors: [Color(argb: 0xFFF4B8C5), Color(argb: 0xFFF9D4C2), Color(argb: 0xFFB9A6E8),
                                                                              Color(argb: 0xFF7FB2E0), Color(argb: 0xFFF4B8C5)]), center: .center))
                }
                Circle().fill(LinearGradient(colors: [Color.white.opacity(0.32), .clear], startPoint: .topLeading, endPoint: .center))
                if style == .auto {
                    Icon(PlayerIcons.image, size: diameter * 0.46, color: Color.white.opacity(0.95))
                } else if style == .custom {
                    Icon(PlayerIcons.palette, size: diameter * 0.46, color: light ? Color.black.opacity(0.62) : Color.white.opacity(0.92))
                }
                Circle().strokeBorder(colors.textPrimary.opacity(colors.dark ? 0.22 : 0.16), lineWidth: 0.8)
            }
            .frame(width: diameter, height: diameter)
            .padding(3)
            .overlay(Circle().strokeBorder(selected ? colors.accent : .clear, lineWidth: 2))
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.9))
        .help(style == .auto ? "Automatisch – Farben des Covers bzw. des Designs (wie bisher)" : "Player-Hintergrund \(style.label)")
        .accessibilityLabel("Player-Hintergrund \(style.label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Auswahl des Player-Hintergrunds für Einstellungen und das Design-Blatt: Farbfelder, eigene Farbe mit dem
/// Systemfarbwähler (`ColorPicker`) und – optional – die Tönung des Mini-Players.
struct PlayerBackgroundPicker: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    var compact: Bool = false
    var showsMiniTint: Bool = true
    /// Überschrift „Hintergrund“ (in den Einstellungen trägt die Karte bereits den Titel).
    var showsTitle: Bool = true

    var body: some View {
        let s = model.settings
        let current = s.playerBackground
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack {
                if showsTitle {
                    Text("Hintergrund").textStyle(compact ? Typo.labelLarge : Typo.titleMedium)
                } else {
                    Text("Großer Player").textStyle(Typo.bodyLarge).foregroundColor(colors.textPrimary)
                }
                Spacer()
                Text(current.label).textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary)
            }
            PlayerFlowLayout(spacing: compact ? 4 : 6, lineSpacing: compact ? 4 : 6) {
                ForEach(PlayerBackgroundStyle.allCases, id: \.self) { style in
                    PlayerBackgroundSwatch(style: style, custom: s.playerBackgroundCustom, selected: style == current,
                                           diameter: compact ? 22 : 28) {
                        PlayerBackgroundChoice.select(style, model: model)
                    }
                }
            }
            HStack(spacing: 10) {
                Text("Eigene Farbe").textStyle(Typo.bodyMedium).foregroundColor(colors.textPrimary)
                ColorPicker("Eigene Farbe", selection: Binding(
                    get: { Color(argb: model.settings.playerBackgroundCustom | 0xFF00_0000) },
                    set: { c in PlayerBackgroundChoice.setCustom(ColorARGB.argb(c), model: model) }
                ), supportsOpacity: false)
                .labelsHidden()
                .help("Eigene Hintergrundfarbe wählen (Systemfarbwähler)")
                Text(current == .custom ? "aktiv" : "wird beim Wählen übernommen")
                    .textStyle(Typo.labelSmall)
                    .foregroundColor(colors.textTertiary)
                Spacer(minLength: 0)
            }
            Text("„Automatisch“ nimmt wie bisher die Farben des Covers bzw. des Designs. Schrift und Bedienelemente passen sich der Helligkeit der Farbe an – auch in den immer dunklen Designs.")
                .textStyle(Typo.bodySmall)
                .foregroundColor(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if showsMiniTint {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mini-Player tönen").textStyle(Typo.bodyLarge).foregroundColor(colors.textPrimary)
                        Text("Die Farbe färbt den Mini-Player dezent. Bei „Automatisch“ wie bisher der Schein des Covers.")
                            .textStyle(Typo.bodySmall)
                            .foregroundColor(colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    MusicToggle(isOn: Binding(get: { model.settings.playerBackgroundTintsMini },
                                              set: { model.settings.playerBackgroundTintsMini = $0 }),
                                label: "Mini-Player tönen")
                }
            }
        }
    }
}

/// Kurzform für das „…“-Menü des großen Players: Farbfelder, eigene Farbe über den Systemfarbwähler,
/// Tönung des Mini-Players.
struct PlayerBackgroundMenuSection: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    let close: () -> Void

    var body: some View {
        let s = model.settings
        VStack(alignment: .leading, spacing: 4) {
            PlayerFlowLayout(spacing: 3, lineSpacing: 3) {
                ForEach(PlayerBackgroundStyle.allCases, id: \.self) { style in
                    PlayerBackgroundSwatch(style: style, custom: s.playerBackgroundCustom, selected: style == s.playerBackground, diameter: 21) {
                        PlayerBackgroundChoice.select(style, model: model)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            Text(s.playerBackground.label)
                .textStyle(Typo.labelSmall)
                .foregroundColor(colors.textTertiary)
                .padding(.horizontal, 10)
            GlassMenuItem(title: "Eigene Farbe wählen …", icon: PlayerIcons.palette, checked: false) {
                let m = model
                close()
                PlayerColorPanel.shared.open(initial: m.settings.playerBackgroundCustom) { argb in
                    PlayerBackgroundChoice.setCustom(argb, model: m)
                }
                PlayerBackgroundChoice.select(.custom, model: m)
            }
            GlassMenuItem(title: "Mini-Player tönen", icon: Icons.miniPlayer, checked: s.playerBackgroundTintsMini) {
                model.settings.playerBackgroundTintsMini.toggle()
            }
        }
    }
}
