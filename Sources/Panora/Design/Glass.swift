import SwiftUI
import AppKit

// =============================================================================================
// Glasflächen: macOS 26 natives Liquid Glass (`glassEffect`), sonst echte Hintergrundunschärfe mit
// Tönung, Glanz und feiner Lichtkante – wie in der Musik-App.
// =============================================================================================

enum LiquidGlass {
    static var forceFallback = ProcessInfo.processInfo.environment["PANORA_FORCE_GLASS_FALLBACK"] == "1"

    static var isAvailable: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return !forceFallback }
        #endif
        return false
    }
}

struct BackdropBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
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
    @Environment(\.panora) private var colors
    @Environment(\.glassEnabled) private var glass

    let shape: S
    var strong: Bool = false
    var elevated: Bool = false
    var interactive: Bool = false

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
            let tint = colors.dark ? Color(hex: 0x12151C).opacity(strong ? 0.55 : 0.32) : Color.white.opacity(strong ? 0.5 : 0.22)
            content
                .glassEffect(interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint), in: shape)
                .shadow(color: elevated ? colors.glassShadow.opacity(0.6) : .clear, radius: elevated ? 16 : 0, y: elevated ? 6 : 0)
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
                    if glass { BackdropBlur(material: colors.dark ? .hudWindow : .popover) }
                    shape.fill(glass ? (strong ? colors.glassTintStrong : colors.glassTint) : colors.surface)
                    if glass {
                        LinearGradient(stops: [.init(color: colors.glassSheen, location: 0), .init(color: .clear, location: 0.5)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                }
                .clipShape(shape)
            )
            .overlay(
                shape.strokeBorder(LinearGradient(colors: [colors.glassEdgeLight, colors.glassEdgeDark, colors.glassEdgeLight.opacity(0.4)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
            )
            .compositingGroup()
            .shadow(color: elevated ? colors.glassShadow : .clear, radius: elevated ? 18 : 0, y: elevated ? 7 : 0)
    }
}

extension View {
    func glassSurface<S: InsettableShape>(_ shape: S, strong: Bool = false, elevated: Bool = false, interactive: Bool = false) -> some View {
        modifier(GlassBackground(shape: shape, strong: strong, elevated: elevated, interactive: interactive))
    }

    func glassSurface(cornerRadius: CGFloat, strong: Bool = false, elevated: Bool = false) -> some View {
        glassSurface(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), strong: strong, elevated: elevated)
    }

    /// Ruhige Karte (ohne Unschärfe) für Inhalte im Raster.
    func cardSurface(_ colors: PanoraColors, radius: CGFloat = Metrics.cardRadius, highlighted: Bool = false) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(colors.surface.opacity(colors.dark ? 0.78 : 0.92)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(highlighted ? colors.accent.opacity(0.7) : colors.hairline, lineWidth: highlighted ? 1.2 : 0.8))
    }
}

/// Atmosphärischer Hintergrund: Graphit bzw. kühles Weiß mit sehr weichen Farbinseln.
struct AmbientBackground: View {
    @Environment(\.panora) private var colors
    @Environment(\.glassEnabled) private var glass

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let h = max(geo.size.height, 1)
            let radius = max(w, h) * 0.6
            ZStack {
                colors.background
                if glass {
                    RadialGradient(colors: [colors.ambient[0], .clear], center: UnitPoint(x: 0.02, y: 0.0), startRadius: 0, endRadius: radius)
                    RadialGradient(colors: [colors.ambient[1], .clear], center: UnitPoint(x: 1.04, y: 0.38), startRadius: 0, endRadius: radius)
                    RadialGradient(colors: [colors.ambient[2], .clear], center: UnitPoint(x: 0.2, y: 1.0), startRadius: 0, endRadius: radius)
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Weicher Auslauf am oberen/unteren Rand, damit Inhalte unter die schwebenden Leisten gleiten.
struct EdgeFade: View {
    @Environment(\.panora) private var colors
    var top: Bool
    var strength: Double = 0.85

    var body: some View {
        LinearGradient(colors: [colors.background.opacity(strength), colors.background.opacity(0)],
                       startPoint: top ? .top : .bottom, endPoint: top ? .bottom : .top)
            .allowsHitTesting(false)
    }
}
