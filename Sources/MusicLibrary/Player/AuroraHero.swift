import SwiftUI
import AppKit
import MLCore
import MLRender

// MARK: - Aurora (v2)

/// Aurora – das Cover im Kreis, umgeben von einem lebendigen Lichtring aus Spektralbalken. Mit
/// Klangvisualisierung folgt der Ring den echten Pegeln (16 Bänder, gespiegelt), sonst atmet er ruhig.
/// Dahinter ziehen Polarlicht-Schleier in den Farben des Covers langsam vorbei (nur während der Wiedergabe).
///
/// Leistung: Bild-für-Bild-Anteile sind klein (Ring als Canvas mit 30 Bildern/s, Schleier als verschobene,
/// unveränderte Verlaufsflächen mit 24 Bildern/s); beides ruht in der Pause und bei reduzierter Bewegung.
struct AuroraHero: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    let side: CGFloat
    @ObservedObject var artwork: NowPlayingArtwork
    var still: Bool = false

    var body: some View {
        let lights = AuroraColors(palette: artwork.palette, dark: colors.dark)
        let playing = !still && player.isPlaying
        let animate = !still && PlayerMotionPolicy.continuous(model.settings)
        let useLevels = animate && model.settings.visualizer
        let coverD = side * 0.54
        let ringInner = coverD / 2 + side * 0.035
        ZStack {
            AuroraVeils(lights: lights, side: side, moving: playing && animate, dark: colors.dark)
            AuroraRing(lights: lights, side: side, inner: ringInner, maxLength: side * 0.15,
                       playing: playing, animate: animate, useLevels: useLevels, dark: colors.dark, still: still)
            AuroraCover(image: artwork.image, category: GenreStyle.category(player.current?.genres.first), loading: artwork.loading,
                        coverKey: artwork.key ?? "-", diameter: coverD, lights: lights, dark: colors.dark)
                .scaleEffect(playing || still || !animate ? 1 : 0.95)
                .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.6), value: playing)
        }
        .frame(width: side, height: side)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(player.current.map { "Aurora: Cover von „\($0.displayTitle)“ mit Lichtring" } ?? "Aurora-Lichtring")
    }
}

/// Rundes Cover mit Lichtkante, Glanz und ruhendem Schatten.
private struct AuroraCover: View {
    let image: NSImage?
    let category: GenreCategory
    let loading: Bool
    let coverKey: String
    let diameter: CGFloat
    let lights: AuroraColors
    let dark: Bool

    var body: some View {
        ZStack {
            // Schatten als ruhender Verlauf (keine Unschärfe)
            Circle()
                .fill(RadialGradient(colors: [Color.black.opacity(dark ? 0.55 : 0.22), .clear], center: .center,
                                     startRadius: diameter * 0.42, endRadius: diameter * 0.62))
                .frame(width: diameter * 1.3, height: diameter * 1.3)
                .offset(y: diameter * 0.04)
            ZStack {
                ArtworkBox(image: image, category: category, iconFraction: 0.4, loading: loading, circle: true)
                    .frame(width: diameter, height: diameter)
                Circle()
                    .fill(LinearGradient(stops: [
                        .init(color: Color.white.opacity(0.22), location: 0),
                        .init(color: .clear, location: 0.45),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: diameter, height: diameter)
                    .blendMode(.screen)
                Circle()
                    .strokeBorder(AngularGradient(gradient: Gradient(colors: [lights.highlight.opacity(0.9), lights.primary.opacity(0.5),
                                                                              lights.secondary.opacity(0.8), lights.tertiary.opacity(0.5),
                                                                              lights.highlight.opacity(0.9)]), center: .center),
                                  lineWidth: max(1.5, diameter * 0.012))
                    .frame(width: diameter, height: diameter)
            }
            .id(coverKey)
            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.94)), removal: .opacity))
        }
        .animation(.easeOut(duration: 0.45), value: coverKey)
        .allowsHitTesting(false)
    }
}

/// Polarlicht-Schleier: drei weiche Farbflächen, die langsam wandern (während der Wiedergabe).
private struct AuroraVeils: View {
    let lights: AuroraColors
    let side: CGFloat
    let moving: Bool
    let dark: Bool
    @StateObject private var phase = PhaseClock()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !moving)) { ctx in
            let t = phase.advance(ctx.date, running: moving)
            let a: Double = dark ? 0.6 : 0.42
            ZStack {
                VeilBlob(color: lights.primary.opacity(a), diameter: side * 1.02)
                    .offset(x: side * CGFloat(0.10 * sin(t * 0.21)), y: side * CGFloat(-0.06 + 0.07 * cos(t * 0.17)))
                VeilBlob(color: lights.secondary.opacity(a * 0.85), diameter: side * 0.86)
                    .offset(x: side * CGFloat(-0.16 + 0.08 * cos(t * 0.13 + 1)), y: side * CGFloat(0.12 + 0.06 * sin(t * 0.19)))
                VeilBlob(color: lights.tertiary.opacity(a * 0.75), diameter: side * 0.78)
                    .offset(x: side * CGFloat(0.18 + 0.07 * sin(t * 0.11 + 2)), y: side * CGFloat(0.08 + 0.08 * cos(t * 0.23 + 0.5)))
            }
            .frame(width: side, height: side)
        }
        .animation(.easeInOut(duration: 0.9), value: lights)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Eine weiche Farbfläche (unveränderlich – beim Verschieben wird sie nicht neu gezeichnet).
private struct VeilBlob: View {
    let color: Color
    let diameter: CGFloat

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [color, color.opacity(0)], center: .center, startRadius: 0, endRadius: diameter / 2))
            .frame(width: diameter, height: diameter)
    }
}

/// RGB-Werte für das Mischen der Ringfarben im Canvas.
private struct RingRGB {
    let r: Double
    let g: Double
    let b: Double

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(srgbRed: 1, green: 0.5, blue: 0.6, alpha: 1)
        r = Double(ns.redComponent)
        g = Double(ns.greenComponent)
        b = Double(ns.blueComponent)
    }

    static func mix(_ a: RingRGB, _ b: RingRGB, _ f: Double) -> (Double, Double, Double) {
        (a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f)
    }
}

/// Lichtring aus Spektralbalken um das Cover.
private struct AuroraRing: View {
    @EnvironmentObject private var player: PlayerService
    @StateObject private var vis = VisualizerState()
    @StateObject private var phase = PhaseClock()
    @State private var idleTick = 0
    let lights: AuroraColors
    let side: CGFloat
    let inner: CGFloat
    let maxLength: CGFloat
    let playing: Bool
    let animate: Bool
    let useLevels: Bool
    let dark: Bool
    let still: Bool

    var body: some View {
        let palette: [RingRGB] = [RingRGB(lights.primary), RingRGB(lights.secondary), RingRGB(lights.tertiary), RingRGB(lights.highlight)]
        let style = AuroraRingPainter.Style(lights: lights, palette: palette, inner: inner, maxLength: maxLength, playing: playing, dark: dark, still: still)
        let running = animate && (playing || (useLevels && vis.hasEnergy))
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { ctx in
            let _ = idleTick
            let t = phase.advance(ctx.date, running: running && playing)
            let _ = useLevels ? vis.step(ctx.date, meter: player.engine.levels) : ()
            let active = animate && (playing || (useLevels && vis.hasEnergy))
            let bands: [Float]? = useLevels ? vis.smoothing.bands : nil
            Canvas { g, size in
                AuroraRingPainter.draw(g, size: size, t: t, bands: bands, style: style)
            }
            .frame(width: side, height: side)
            .onChange(of: active) { a in if !a { DispatchQueue.main.async { idleTick &+= 1 } } }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Zeichnet den Lichtring (ohne Bezug zur Ansicht – darf im Canvas laufen).
private enum AuroraRingPainter {
    struct Style {
        let lights: AuroraColors
        let palette: [RingRGB]
        let inner: CGFloat
        let maxLength: CGFloat
        let playing: Bool
        let dark: Bool
        let still: Bool
    }

    static func draw(_ g: GraphicsContext, size: CGSize, t: Double, bands: [Float]?, style s: Style) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let inner = s.inner
        let n = 96
        let barWidth: CGFloat = max(1.6, 2 * CGFloat.pi * inner / CGFloat(n) * 0.46)
        let breath: Double = 0.5 + 0.5 * sin(t * 0.8)
        // Weicher Schein hinter den Balken (atmet mit)
        let glowAlpha: Double = (s.dark ? 0.30 : 0.20) + (s.playing ? 0.10 * breath : 0)
        let glowRect = CGRect(x: c.x - inner * 1.45, y: c.y - inner * 1.45, width: inner * 2.9, height: inner * 2.9)
        g.fill(Path(ellipseIn: glowRect), with: .radialGradient(Gradient(stops: [
            .init(color: .clear, location: 0.55),
            .init(color: s.lights.primary.opacity(glowAlpha), location: 0.72),
            .init(color: s.lights.secondary.opacity(glowAlpha * 0.5), location: 0.84),
            .init(color: .clear, location: 1),
        ]), center: c, startRadius: 0, endRadius: inner * 1.45))
        var gc = g
        if s.dark { gc.blendMode = .plusLighter }
        for i in 0..<n {
            let a = 2 * Double.pi * Double(i) / Double(n) - Double.pi / 2
            let v = barValue(i: i, n: n, angle: a, t: t, bands: bands, playing: s.playing, still: s.still)
            let length = max(s.maxLength * CGFloat(v), barWidth * 0.6)
            let ca = CGFloat(cos(a)), sa = CGFloat(sin(a))
            let p0 = CGPoint(x: c.x + ca * inner, y: c.y + sa * inner)
            let p1 = CGPoint(x: c.x + ca * (inner + length), y: c.y + sa * (inner + length))
            let q = Double(i) / Double(n) * 4
            let k = Int(q) % 4
            let rgb = RingRGB.mix(s.palette[k], s.palette[(k + 1) % 4], q - floor(q))
            let base = Color(.sRGB, red: rgb.0, green: rgb.1, blue: rgb.2, opacity: 0.55 + 0.45 * v)
            var path = Path()
            path.move(to: p0)
            path.addLine(to: p1)
            gc.stroke(path, with: .linearGradient(Gradient(colors: [base, base.opacity(0.25)]), startPoint: p0, endPoint: p1),
                      style: StrokeStyle(lineWidth: barWidth, lineCap: .round))
        }
    }

    /// Länge eines Balkens 0…1: echte Pegel (gespiegelt, interpoliert) oder ruhiges Atmen.
    static func barValue(i: Int, n: Int, angle: Double, t: Double, bands: [Float]?, playing: Bool, still: Bool) -> Double {
        if let bands, bands.count >= 16 {
            let half = Double(n) / 2
            let u = Double(i) < half ? Double(i) / half : Double(n - i) / half
            let pos = u * 15
            let lo = min(15, Int(pos))
            let hi = min(15, lo + 1)
            let f = pos - Double(lo)
            let raw = Double(bands[lo]) * (1 - f) + Double(bands[hi]) * f
            return min(1, 0.07 + 0.93 * pow(raw, 1.25))
        }
        if still { return 0.22 + 0.10 * sin(angle * 3 + 0.6) + 0.06 * sin(angle * 7) }
        let wave1: Double = 0.10 * sin(t * 1.1 + angle * 3)
        let wave2: Double = 0.07 * sin(t * 0.63 - angle * 5 + 1.3)
        let wave3: Double = 0.05 * sin(t * 1.7 + angle * 7)
        let base: Double = playing ? 0.26 : 0.16
        return max(0.05, min(1, base + wave1 + wave2 + wave3))
    }
}
