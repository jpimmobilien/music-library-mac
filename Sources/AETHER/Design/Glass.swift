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

/// Glasfläche: natives Liquid Glass auf macOS 26, sonst Unschärfe + Tönung + Lichtkante + Glanz.
/// Bei Themes ohne Glas, Glasintensität 0 oder „Transparenz reduzieren“: deckende Fläche mit Haarlinie.
struct GlassSurface<S: InsettableShape>: ViewModifier {
    @Environment(\.aether) private var theme
    let shape: S
    var strong = false
    var elevated = false
    var interactive = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if !theme.glassActive {
            solid(content)
        } else if LiquidGlass.isAvailable {
            native(content)
        } else {
            fallback(content)
        }
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
            .compositingGroup()
            .shadow(color: elevated ? theme.shadow : theme.shadow.opacity(0.35), radius: elevated ? 16 : 6, y: elevated ? 6 : 2)
    }
}

extension View {
    func glassSurface<S: InsettableShape>(_ shape: S, strong: Bool = false, elevated: Bool = false,
                                          interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, strong: strong, elevated: elevated, interactive: interactive))
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

/// Atmosphärischer Fensterhintergrund: weiche, statische Farbinseln – keine Daueranimation, keine Echtzeit-Unschärfe.
struct AmbientBackground: View {
    @Environment(\.aether) private var theme

    var body: some View {
        GeometryReader { geo in
            let radius = max(geo.size.width, geo.size.height) * 0.75
            let ambient = theme.palette.ambient
            ZStack {
                LinearGradient(colors: [theme.backgroundTop, theme.backgroundBottom], startPoint: .top, endPoint: .bottom)
                if theme.usesGlass {
                    let centers: [UnitPoint] = [UnitPoint(x: 0.05, y: 0.0), UnitPoint(x: 1.0, y: 0.2), UnitPoint(x: 0.45, y: 1.1)]
                    ForEach(Array(ambient.prefix(3).enumerated()), id: \.offset) { index, color in
                        RadialGradient(colors: [Color(color).opacity(0.35 + 0.65 * theme.glassIntensity), .clear],
                                       center: centers[index], startRadius: 0, endRadius: radius * (index == 0 ? 1 : 0.85))
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
