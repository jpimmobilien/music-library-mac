import SwiftUI
import AppKit

// =============================================================================================
// Glasflächen („Liquid Glass“) – Übertragung von ui/components/Glass.kt.
//
// Android zeichnet Glas selbst: Weichzeichner des Inhalts dahinter + Tönung (glassTint) + Glanz von oben
// (glassSheen) + Hauch Tiefe nach unten + feine Lichtkante (glassEdgeLight → glassEdgeDark) + weicher Schatten.
//
// macOS 26 und neuer: natives Liquid Glass (`glassEffect`) mit der Tönung der App.
// macOS 13–15: gleichwertige Nachbildung – echte Hintergrundunschärfe des Fensterinhalts
// (NSVisualEffectView, „within window“) mit exakt denselben Schichten wie unter Android.
// Ist „Glas-Effekte“ ausgeschaltet, werden die Flächen ruhig und undurchsichtig (wie Android).
// =============================================================================================

enum LiquidGlass {
    /// Steht natives Liquid Glass zur Verfügung (macOS 26 + mit dem passenden SDK gebaut)?
    static var isAvailable: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return !forceFallback }
        #endif
        return false
    }

    /// Für Vergleichsbilder (Snapshot-Modus): Rückfalllösung auch unter macOS 26 erzwingen.
    static var forceFallback = ProcessInfo.processInfo.environment["ML_FORCE_GLASS_FALLBACK"] == "1"
}

/// Echte Hintergrundunschärfe des Fensterinhalts (macOS 13–15).
struct BackdropBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        v.isEmphasized = false
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

/// Hintergrund einer Glasfläche (Android `GlassSurface`).
struct GlassBackground<S: InsettableShape>: ViewModifier {
    @Environment(\.musicColors) private var colors
    @Environment(\.glassEnabled) private var glass

    let shape: S
    var strong: Bool = false
    var elevated: Bool = false
    var tint: Color? = nil
    var interactive: Bool = false

    private var fill: Color {
        if let tint { return tint }
        if !glass { return colors.surface }
        return strong ? colors.glassTintStrong : colors.glassTint
    }

    func body(content: Content) -> some View {
        Group {
            if glass && LiquidGlass.isAvailable {
                modernGlass(content)
            } else {
                fallbackGlass(content)
            }
        }
    }

    @ViewBuilder
    private func modernGlass(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            // Natives Liquid Glass mit der warmen Tönung der App (Tönung schwächer als bei der Nachbildung,
            // weil Liquid Glass selbst aufhellt bzw. abdunkelt).
            let glassTint = tint ?? (colors.dark ? Color(argb: 0xFF1E1A1C).opacity(strong ? 0.55 : 0.35) : Color.white.opacity(strong ? 0.45 : 0.22))
            content
                .glassEffect(interactive ? Glass.regular.tint(glassTint).interactive() : Glass.regular.tint(glassTint), in: shape)
                .shadow(color: elevated ? colors.glassShadow.opacity(0.6) : .clear, radius: elevated ? 14 : 0, y: elevated ? 5 : 0)
        } else {
            fallbackGlass(content)
        }
        #else
        fallbackGlass(content)
        #endif
    }

    private func fallbackGlass(_ content: Content) -> some View {
        content
            .background(
                ZStack {
                    if glass {
                        BackdropBlur(material: colors.dark ? .hudWindow : .popover)
                    }
                    shape.fill(fill)
                    if glass {
                        // Glanz von oben und ein Hauch Tiefe nach unten (wie Android).
                        LinearGradient(stops: [
                            .init(color: colors.glassSheen, location: 0),
                            .init(color: .clear, location: 0.5),
                        ], startPoint: .top, endPoint: .bottom)
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0.6),
                            .init(color: Color.black.opacity(colors.dark ? 0.10 : 0.025), location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                    }
                }
                .clipShape(shape)
            )
            .overlay(
                shape.strokeBorder(
                    glass
                        ? LinearGradient(colors: [colors.glassEdgeLight, colors.glassEdgeDark, colors.glassEdgeLight.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [colors.hairline, colors.hairline], startPoint: .top, endPoint: .bottom),
                    lineWidth: glass ? 0.8 : 0.6
                )
            )
            .compositingGroup()
            .shadow(color: elevated ? colors.glassShadow : .clear, radius: elevated ? (glass ? 16 : 5) : 0, x: 0, y: elevated ? 6 : 0)
    }
}

extension View {
    /// Glasfläche hinter dem Inhalt (Android `GlassSurface`).
    func glassSurface<S: InsettableShape>(_ shape: S, strong: Bool = false, elevated: Bool = false, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassBackground(shape: shape, strong: strong, elevated: elevated, tint: tint, interactive: interactive))
    }

    func glassSurface(cornerRadius: CGFloat, strong: Bool = false, elevated: Bool = false, tint: Color? = nil) -> some View {
        glassSurface(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), strong: strong, elevated: elevated, tint: tint)
    }
}

/// Gruppiert benachbarte Glasflächen (macOS 26: verschmelzende Liquid-Glass-Formen; sonst ohne Wirkung).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
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

/// Atmosphärischer App-Hintergrund: warmes Weiß bzw. warmes Schwarz mit sehr weichen Rosé-, Pfirsich- und
/// Fliedertönen (radiale Verläufe – Android `AmbientBackground`).
struct AmbientBackground: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.glassEnabled) private var glass

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let radius = max(w, h) * 0.58
            let centers = [CGPoint(x: w * 0.0, y: h * 0.02), CGPoint(x: w * 1.05, y: h * 0.36), CGPoint(x: w * 0.18, y: h * 0.98)]
            ZStack {
                colors.background
                if glass && w > 0 && h > 0 {
                    ForEach(0..<colors.ambient.count, id: \.self) { i in
                        let c = colors.ambient[i]
                        let center = centers[i % centers.count]
                        RadialGradient(colors: [c, c.opacity(0)], center: UnitPoint(x: center.x / w, y: center.y / h), startRadius: 0, endRadius: radius)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Weicher Übergang an Kanten: Inhalte laufen unter schwebenden Leisten sanft aus (Android `EdgeFade`).
struct EdgeFade: View {
    @Environment(\.musicColors) private var colors
    let top: Bool
    var strength: Double = 0.92

    var body: some View {
        let c = colors.background.opacity(strength)
        LinearGradient(stops: top
            ? [.init(color: c, location: 0), .init(color: colors.background.opacity(strength * 0.6), location: 0.55), .init(color: .clear, location: 1)]
            : [.init(color: .clear, location: 0), .init(color: colors.background.opacity(strength * 0.6), location: 0.45), .init(color: c, location: 1)],
            startPoint: .top, endPoint: .bottom)
        .allowsHitTesting(false)
    }
}

/// Atmosphärischer Kopfhintergrund von Detailansichten: Cover groß und weichgezeichnet, nach unten in den
/// App-Hintergrund auslaufend (Android `HeroBackdrop`).
struct HeroBackdrop: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.glassEnabled) private var glass
    let image: NSImage?
    var tint: Color? = nil

    var body: some View {
        ZStack {
            if let image, glass {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 60, opaque: true)
                    .opacity(colors.dark ? 0.65 : 0.55)
                    .clipped()
            } else if let tint {
                LinearGradient(colors: [tint.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
            }
            LinearGradient(stops: [
                .init(color: colors.background.opacity(0.25), location: 0),
                .init(color: colors.background.opacity(0.55), location: 0.55),
                .init(color: colors.background, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .allowsHitTesting(false)
    }
}
