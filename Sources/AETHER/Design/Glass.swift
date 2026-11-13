import SwiftUI
import AppKit
import AetherCore

/// Echte Hintergrundunschärfe für macOS 13–15 (und für den erzwungenen Rückfall).
struct BackdropBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

/// Liquid Glass 2.0 – drei Ebenen:
///   Grund       die Bühne (`AmbientBackground`)
///   Schicht     Inhaltsflächen: getönte Füllung, obere Lichtkante, Haarlinie, weicher Schatten – OHNE eigene
///               Hintergrundunschärfe. Zehn Unschärfeflächen kosteten WindowServer auf Intel-Grafik spürbar Leistung,
///               und hinter den Flächen liegt ohnehin nur der ruhige Verlauf der Bühne.
///   Schwebend   Seitenleiste und Werkzeuge: natives Liquid Glass (macOS 26) bzw. echte Unschärfe (macOS 13–15).
/// Bei Themes ohne Glas, Glasintensität 0 oder „Transparenz reduzieren“: deckende Fläche mit Haarlinie.
struct GlassSurface<S: InsettableShape>: ViewModifier {
    @Environment(\.aether) private var theme
    let shape: S
    var strong = false
    var elevated = false
    var interactive = false
    var floating = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if !theme.glassActive {
            solid(content)
        } else if !floating {
            layer(content)
        } else if LiquidGlass.isAvailable {
            native(content)
        } else {
            fallback(content)
        }
    }

    /// Schicht: Tiefe aus Licht und Schatten, ohne Unschärfe und ohne Offscreen-Komposition.
    private func layer(_ content: Content) -> some View {
        let intensity = theme.glassIntensity
        return content
            .background(
                ZStack {
                    shape.fill(theme.glassTint(strong: strong))
                    shape.fill(LinearGradient(stops: [.init(color: theme.sheen.opacity(0.9 * intensity), location: 0),
                                                      .init(color: .clear, location: 0.42)],
                                              startPoint: .top, endPoint: .bottom))
                }
                .shadow(color: theme.shadow.opacity(elevated ? 1 : 0.45), radius: elevated ? 18 : 8, y: elevated ? 8 : 3)
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [theme.edgeLight.opacity(0.35 + 0.55 * intensity), theme.edgeDark.opacity(0.6),
                                            theme.edgeLight.opacity(0.15 + 0.2 * intensity)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.8)
            )
    }

    private func solid(_ content: Content) -> some View {
        content
            .background(shape.fill(theme.surface))
            .overlay(shape.strokeBorder(theme.hairline, lineWidth: 1))
            .shadow(color: elevated ? theme.shadow : .clear, radius: elevated ? 14 : 0, y: elevated ? 5 : 0)
    }

    @ViewBuilder
    private func native(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = Glass.regular.tint(theme.glassTint(strong: strong))
            content
                .glassEffect(interactive ? glass.interactive() : glass, in: shape)
                .shadow(color: elevated ? theme.shadow.opacity(0.5) : .clear, radius: elevated ? 16 : 0, y: elevated ? 6 : 0)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        let intensity = theme.glassIntensity
        return content
            .background(
                ZStack {
                    BackdropBlur(material: theme.isDark ? .hudWindow : .popover)
                    shape.fill(theme.glassTint(strong: strong))
                        .shadow(color: elevated ? theme.shadow : theme.shadow.opacity(0.35), radius: elevated ? 16 : 6, y: elevated ? 6 : 2)
                    LinearGradient(stops: [.init(color: theme.sheen.opacity(intensity), location: 0),
                                           .init(color: .clear, location: 0.55)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .clipShape(shape)
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [theme.edgeLight.opacity(0.4 + 0.6 * intensity), theme.edgeDark,
                                            theme.edgeLight.opacity(0.25 + 0.25 * intensity)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.8)
            )

    }
}

extension View {
    func glassSurface<S: InsettableShape>(_ shape: S, strong: Bool = false, elevated: Bool = false,
                                          interactive: Bool = false, floating: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, strong: strong, elevated: elevated, interactive: interactive, floating: floating))
    }

    func glassCard(cornerRadius: CGFloat = Radius.card, strong: Bool = true, elevated: Bool = false) -> some View {
        glassSurface(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), strong: strong, elevated: elevated)
    }
}

/// Gruppiert Glasflächen; auf macOS 26 verschmelzen benachbarte Formen.
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

/// Atmosphärischer Fensterhintergrund: weiche Lichtfelder in den ORBIT-Farben (Core Animation, siehe Orbit.swift).
/// „Minimal“: nur der Verlauf. „Ausgewogen“: ruhende Lichtfelder, die beim Bereichswechsel weitergleiten.
/// „Immersiv“: zusätzlich eine sehr langsame Drift. Keine Echtzeit-Unschärfe.
struct AmbientBackground: View {
    @Environment(\.aether) private var theme
    /// Aktueller Bereich – bestimmt die Lage der Lichtfelder (räumliche Orientierung). nil = feste Lage.
    var section: AppSection? = nil

    var body: some View {
        ZStack {
            LinearGradient(colors: [theme.backgroundTop, theme.backgroundBottom], startPoint: .top, endPoint: .bottom)
            if theme.usesGlass && theme.effects.ambientLights && !theme.palette.ambient.isEmpty {
                AmbientLightsView(lights: lights, shift: shift, living: theme.effects.livingBackground,
                                  animateShift: theme.effects.spatialBackground)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var lights: [AmbientLightsView.Light] {
        let centers: [UnitPoint] = [UnitPoint(x: 0.05, y: 0.0), UnitPoint(x: 1.0, y: 0.2), UnitPoint(x: 0.45, y: 1.1)]
        let radii: [CGFloat] = [0.75, 0.64, 0.64]
        let intensity = 0.35 + 0.65 * min(1, max(0, theme.glassIntensity))
        return theme.palette.ambient.prefix(3).enumerated().map { index, color in
            AmbientLightsView.Light(color: color.withAlpha(color.alpha * intensity), center: centers[index], radius: radii[index])
        }
    }

    /// Jeder Bereich hat eine eigene, leicht versetzte Lage der Lichtfelder (höchstens 6 % der Fenstergröße).
    private var shift: CGPoint {
        guard let section, theme.effects.spatialBackground,
              let index = AppSection.allCases.firstIndex(of: section) else { return .zero }
        let angle = Double(index) / Double(AppSection.allCases.count) * 2 * Double.pi
        return CGPoint(x: cos(angle) * 0.06, y: sin(angle) * 0.04)
    }
}
