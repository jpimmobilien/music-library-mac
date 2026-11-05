import SwiftUI
import AppKit
import MLCore
import MLRender

// MARK: - Studio Reel (v2)

/// Maße des Tonbandgeräts (Einheit: Kantenlänge des Mittelstücks, Ursprung oben links).
enum ReelGeometry {
    static let leftCenter = CGPoint(x: 0.275, y: 0.325)
    static let rightCenter = CGPoint(x: 0.725, y: 0.325)
    static let flangeRadius: CGFloat = 0.205
    static let coreRadius: CGFloat = 0.062
    static let fullRadius: CGFloat = 0.188
    static let guideLeft = CGPoint(x: 0.115, y: 0.715)
    static let guideRight = CGPoint(x: 0.885, y: 0.715)
    static let guideRadius: CGFloat = 0.026
    static let capstan = CGPoint(x: 0.655, y: 0.741)
    static let pinch = CGPoint(x: 0.655, y: 0.771)
    static let vuLeft = CGRect(x: 0.055, y: 0.828, width: 0.3, height: 0.132)
    static let vuRight = CGRect(x: 0.645, y: 0.828, width: 0.3, height: 0.132)
    static let counter = CGRect(x: 0.395, y: 0.836, width: 0.21, height: 0.064)

    /// Wickelradien bei Fortschritt `p` (Bandmenge ∝ Wickelfläche – links voll am Anfang).
    static func packRadii(_ p: Float) -> (left: CGFloat, right: CGFloat) {
        let q = CGFloat(min(1, max(0, p)))
        let c2 = coreRadius * coreRadius
        let span = fullRadius * fullRadius - c2
        return ((c2 + (1 - q) * span).squareRoot(), (c2 + q * span).squareRoot())
    }

    /// Punkte eines Kreisbogens (eindeutige Richtung: von `from` nach `to` im Bogenmaß).
    static func arc(_ c: CGPoint, _ r: CGFloat, from: Double, to: Double, steps: Int = 16) -> [CGPoint] {
        (0...steps).map { i in
            let a = from + (to - from) * Double(i) / Double(steps)
            return CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
        }
    }
}

/// Bewegung der Spulen: Motor läuft weich an und aus; kleine Wickel drehen schneller (gleiche Bandgeschwindigkeit).
final class OpenReelMotion: ObservableObject {
    private(set) var angleLeft: Double = 0
    private(set) var angleRight: Double = 47
    private(set) var motor: Double = 0
    private(set) var time: Double = 0
    private let clock = FrameClock()

    /// Ein Bild weiter; Rückgabe: bewegt sich noch etwas?
    @discardableResult
    func step(now: Date, playing: Bool, speed: Float, left: CGFloat, right: CGFloat) -> Bool {
        let dt = Double(clock.dt(now))
        let target: Double = playing ? min(4, max(0.25, Double(speed))) : 0
        let tau: Double = target > motor ? 0.32 : 0.45
        motor += (target - motor) * (1 - exp(-dt / tau))
        if abs(target - motor) < 0.004 { motor = target }
        // Bandgeschwindigkeit in Seitenlängen je Sekunde (gleiche Einheit wie die Radien)
        let tape: Double = 0.11 * motor
        angleLeft = (angleLeft + tape / max(Double(left), 0.02) * 57.29578 * dt).truncatingRemainder(dividingBy: 360)
        angleRight = (angleRight + tape / max(Double(right), 0.02) * 57.29578 * dt).truncatingRemainder(dividingBy: 360)
        time += dt * motor
        return motor != 0 || target != 0
    }
}

/// Studio Reel – Tonbandmaschine: zwei große Spulen, deren Wickel dem Fortschritt folgen (links voll am
/// Anfang), Bandweg über Umlenkrollen, Tonköpfe und Capstan, zwei VU-Meter (mit Klangvisualisierung echte
/// Pegel), Bandzählwerk und Lampen. Gebürstete dunkle Frontplatte mit Rosé-Akzenten; immer dunkel.
///
/// Leistung: Frontplatte, Spulen und Skalen sind ruhende Zeichnungen; je Bild ändern sich nur Drehwinkel
/// und Zeiger. Wickel und Bandweg folgen der Position (4 × je Sekunde). Pause → keine Bildschleife.
struct ReelToReelHero: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    let side: CGFloat
    @ObservedObject var artwork: NowPlayingArtwork
    var still: Bool = false
    @StateObject private var motion = OpenReelMotion()
    @StateObject private var vis = VisualizerState()
    @State private var idleTick = 0

    var body: some View {
        let playing = !still && player.isPlaying
        let animate = !still && PlayerMotionPolicy.continuous(model.settings)
        let useLevels = animate && model.settings.visualizer
        let speed = model.settings.pitch.speed
        let category = GenreStyle.category(player.current?.genres.first)
        let hasMedia = still || player.current != nil
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 0.045 * side, style: .continuous)
                .fill(Color.black)
                .frame(width: side, height: side)
                .shadow(color: Color.black.opacity(0.5), radius: 18, x: 0, y: 14)
            ReelDeckPanel(side: side)
            ProgressObserver(clock: player.clock) { pos, dur in
                let progress: Float = still ? 0.35 : (dur > 0 ? Float(min(1, max(0, Double(pos) / Double(dur)))) : 0)
                let radii = ReelGeometry.packRadii(progress)
                let moving = animate && (playing || motion.motor != 0 || (useLevels && vis.hasEnergy))
                ZStack(alignment: .topLeading) {
                    ReelTapeLayer(side: side, left: radii.left, right: radii.right)
                    TimelineView(.animation(minimumInterval: nil, paused: !moving)) { ctx in
                        let _ = idleTick
                        let reels = animate ? motion.step(now: ctx.date, playing: playing, speed: speed, left: radii.left, right: radii.right) : false
                        let _ = useLevels ? vis.step(ctx.date, meter: player.engine.levels) : ()
                        let active = reels || (useLevels && vis.hasEnergy)
                        let needles = needleLevels(useLevels: useLevels, playing: playing, animate: animate)
                        ReelMovingParts(side: side, angleLeft: motion.angleLeft, angleRight: motion.angleRight,
                                        levelLeft: needles.0, levelRight: needles.1,
                                        image: artwork.image, category: category, loading: artwork.loading)
                            .onChange(of: active) { a in if !a { DispatchQueue.main.async { idleTick &+= 1 } } }
                    }
                    ReelCounter(side: side, positionMs: still ? 83_000 : pos, playing: playing, hasMedia: hasMedia)
                }
            }
        }
        .frame(width: side, height: side, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(player.current == nil ? "Tonbandmaschine, keine Wiedergabe"
                            : (player.isPlaying ? "Tonbandmaschine: Spulen drehen sich" : "Tonbandmaschine: angehalten"))
    }

    /// Zeigerstellung 0…1: echte Pegel, sonst ruhige Ruhelage während der Wiedergabe.
    private func needleLevels(useLevels: Bool, playing: Bool, animate: Bool) -> (Double, Double) {
        if useLevels { return (Double(vis.smoothing.left), Double(vis.smoothing.right)) }
        if still { return (0.42, 0.38) }
        guard playing else { return (0, 0) }
        let t = motion.time
        let drift: Double = animate ? 0.015 * sin(t * 1.3) : 0
        return (0.2 + drift, 0.19 - drift)
    }
}

// MARK: - Teile

/// Ruhende Frontplatte (einmal gezeichnet).
private struct ReelDeckPanel: View {
    let side: CGFloat

    var body: some View {
        Canvas { g, size in ReelPainter.panel(g, s: size.width) }
            .frame(width: side, height: side)
            .allowsHitTesting(false)
    }
}

/// Wickel und Bandweg (ändern sich mit der Position).
private struct ReelTapeLayer: View {
    let side: CGFloat
    let left: CGFloat
    let right: CGFloat

    var body: some View {
        Canvas { g, size in ReelPainter.tape(g, s: size.width, left: left, right: right) }
            .frame(width: side, height: side)
            .allowsHitTesting(false)
    }
}

/// Je Bild bewegte Teile: Spulen (gedreht), Glanz darauf (ruhend), VU-Zeiger.
private struct ReelMovingParts: View {
    let side: CGFloat
    let angleLeft: Double
    let angleRight: Double
    let levelLeft: Double
    let levelRight: Double
    let image: NSImage?
    let category: GenreCategory
    let loading: Bool

    var body: some View {
        let fr = ReelGeometry.flangeRadius * side
        let lc = ReelGeometry.leftCenter
        let rc = ReelGeometry.rightCenter
        ZStack(alignment: .topLeading) {
            ReelSpool(radius: fr, image: image, category: category, loading: loading)
                .rotationEffect(.degrees(-angleLeft))
                .offset(x: lc.x * side - fr, y: lc.y * side - fr)
            ReelSpool(radius: fr, image: image, category: category, loading: loading)
                .rotationEffect(.degrees(-angleRight))
                .offset(x: rc.x * side - fr, y: rc.y * side - fr)
            ReelSheen(radius: fr)
                .offset(x: lc.x * side - fr, y: lc.y * side - fr)
            ReelSheen(radius: fr)
                .offset(x: rc.x * side - fr, y: rc.y * side - fr)
            VUNeedle(side: side, rect: ReelGeometry.vuLeft, level: levelLeft)
            VUNeedle(side: side, rect: ReelGeometry.vuRight, level: levelRight)
        }
        .frame(width: side, height: side, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// Spule: Metallflansch mit drei Fenstern (Wickel scheint durch), Nabe mit Cover-Etikett und Rosé-Kappe.
private struct ReelSpool: View {
    let radius: CGFloat
    let image: NSImage?
    let category: GenreCategory
    let loading: Bool

    var body: some View {
        ZStack {
            Canvas { g, size in ReelPainter.flange(g, size: size) }
                .frame(width: radius * 2, height: radius * 2)
            ArtworkBox(image: image, category: category, iconFraction: 0.45, loading: loading, circle: true)
                .frame(width: radius * 0.42, height: radius * 0.42)
            Circle()
                .fill(Color(argb: 0xFFFF8FA6))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 0.6))
                .frame(width: radius * 0.1, height: radius * 0.1)
        }
        .frame(width: radius * 2, height: radius * 2)
    }
}

/// Ruhender Glanz auf der Spule (dreht nicht mit – wie echtes Licht).
private struct ReelSheen: View {
    let radius: CGFloat

    var body: some View {
        Circle()
            .fill(AngularGradient(gradient: Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: Color.white.opacity(0.22), location: 0.08),
                .init(color: .clear, location: 0.18),
                .init(color: .clear, location: 0.5),
                .init(color: Color.white.opacity(0.14), location: 0.58),
                .init(color: .clear, location: 0.68),
                .init(color: .clear, location: 1),
            ]), center: .center, angle: .degrees(-40)))
            .frame(width: radius * 2, height: radius * 2)
            .blendMode(.screen)
            .allowsHitTesting(false)
    }
}

/// Zeiger eines VU-Meters (dreht um einen Punkt unterhalb der Skala; abgeschnitten an der Skala).
private struct VUNeedle: View {
    let side: CGFloat
    let rect: CGRect
    let level: Double

    var body: some View {
        let w = rect.width * side
        let h = rect.height * side
        let pivotX = w / 2
        let pivotY = h * 1.2
        let length = h * 1.08
        let angle = -47 + 94 * min(1, max(0, level))
        ZStack(alignment: .topLeading) {
            Capsule()
                .fill(Color(argb: 0xFF2A2023))
                .frame(width: max(1.2, side * 0.0028), height: length)
                .overlay(alignment: .top) {
                    Capsule().fill(Color(argb: 0xFFD4566F)).frame(width: max(1.4, side * 0.0032), height: length * 0.2)
                }
                .rotationEffect(.degrees(angle), anchor: .bottom)
                .offset(x: pivotX - max(1.2, side * 0.0028) / 2, y: pivotY - length)
            // Glasabdeckung (ruhend)
            LinearGradient(stops: [
                .init(color: Color.white.opacity(0.16), location: 0),
                .init(color: Color.white.opacity(0.03), location: 0.45),
                .init(color: .clear, location: 0.5),
            ], startPoint: .top, endPoint: .bottom)
            .frame(width: w, height: h)
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.012, style: .continuous))
        .offset(x: rect.minX * side, y: rect.minY * side)
    }
}

/// Bandzählwerk und Lampen PLAY/PAUSE.
private struct ReelCounter: View {
    let side: CGFloat
    let positionMs: Int64
    let playing: Bool
    let hasMedia: Bool

    var body: some View {
        let r = ReelGeometry.counter
        let rose = Color(argb: 0xFFFF9DB2)
        let amber = Color(argb: 0xFFF3B37A)
        VStack(spacing: side * 0.012) {
            Text(Formatting.duration(positionMs))
                .font(Typo.inter(max(9, side * 0.036), .semibold))
                .monospacedDigit()
                .foregroundColor(rose)
                .shadow(color: rose.opacity(0.45), radius: 3)
                .frame(width: r.width * side, height: r.height * side)
            HStack(spacing: side * 0.02) {
                ReelLamp(label: "PLAY", on: playing, color: rose, size: side)
                ReelLamp(label: "PAUSE", on: hasMedia && !playing, color: amber, size: side)
            }
        }
        .offset(x: r.minX * side, y: r.minY * side)
        .allowsHitTesting(false)
    }
}

private struct ReelLamp: View {
    let label: String
    let on: Bool
    let color: Color
    let size: CGFloat

    var body: some View {
        let g: Double = on ? 1 : 0
        HStack(spacing: size * 0.008) {
            Circle()
                .fill(color.opacity(0.18 + 0.82 * g))
                .frame(width: size * 0.012, height: size * 0.012)
            Text(label)
                .font(Typo.inter(max(6, size * 0.016), .semibold))
                .tracking(0.4)
                .foregroundColor(Color.white.opacity(0.32 + 0.45 * g))
        }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.26), value: on)
    }
}

// MARK: - Zeichnungen

/// Zeichnet Frontplatte, Wickel/Bandweg und Spulenflansch (ohne Bezug zur Ansicht – darf im Canvas laufen).
enum ReelPainter {
    static let rose = Color(argb: 0xFFFF8FA6)

    static func polyline(_ pts: [CGPoint]) -> Path {
        var p = Path()
        guard let first = pts.first else { return p }
        p.move(to: first)
        for q in pts.dropFirst() { p.addLine(to: q) }
        return p
    }

    // Frontplatte -----------------------------------------------------------------------------

    static func panel(_ g: GraphicsContext, s: CGFloat) {
        func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x * s, y: y * s, width: w * s, height: h * s) }
        func circle(_ p: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: (p.x - r) * s, y: (p.y - r) * s, width: 2 * r * s, height: 2 * r * s)) }
        let panel = Path(roundedRect: R(0, 0, 1, 1), cornerRadius: 0.045 * s, style: .continuous)
        g.fill(panel, with: .linearGradient(Gradient(colors: [Color(argb: 0xFF2E2A2C), Color(argb: 0xFF1E1B1C), Color(argb: 0xFF151314)]),
                                            startPoint: .zero, endPoint: CGPoint(x: 0, y: s)))
        var inner = g
        inner.clip(to: panel)
        // gebürstetes Metall
        var bright = Path()
        var faint = Path()
        var y: CGFloat = 1
        var i = 0
        while y < s {
            let line = CGRect(x: 0, y: y, width: s, height: 0.5)
            if i % 3 == 0 { bright.addRect(line) } else { faint.addRect(line) }
            y += 1.6
            i += 1
        }
        inner.fill(bright, with: .color(Color.white.opacity(0.028)))
        inner.fill(faint, with: .color(Color.white.opacity(0.011)))
        inner.fill(panel, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.07), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0.35 * s, y: 0.45 * s)))
        g.stroke(panel, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.03), Color.black.opacity(0.6)]),
                                              startPoint: .zero, endPoint: CGPoint(x: 0, y: s)), lineWidth: 1)
        // Schrauben
        for p in [CGPoint(x: 0.03, y: 0.03), CGPoint(x: 0.97, y: 0.03), CGPoint(x: 0.03, y: 0.97), CGPoint(x: 0.97, y: 0.97)] {
            g.fill(circle(p, 0.011), with: .linearGradient(Gradient(colors: [Color(argb: 0xFF8F8A8C), Color(argb: 0xFF3A3638)]),
                                                         startPoint: CGPoint(x: (p.x - 0.011) * s, y: (p.y - 0.011) * s),
                                                         endPoint: CGPoint(x: (p.x + 0.011) * s, y: (p.y + 0.011) * s)))
            var slot = Path()
            slot.move(to: CGPoint(x: (p.x - 0.007) * s, y: (p.y - 0.004) * s))
            slot.addLine(to: CGPoint(x: (p.x + 0.007) * s, y: (p.y + 0.004) * s))
            g.stroke(slot, with: .color(Color.black.opacity(0.7)), lineWidth: max(0.8, 0.0025 * s))
        }
        // Schriftzug und Rosé-Akzent
        let brand = Text("STUDIO REEL").font(Typo.inter(max(7, 0.026 * s), .bold)).tracking(0.003 * s).foregroundColor(Color.white.opacity(0.66))
        g.draw(brand, at: CGPoint(x: 0.07 * s, y: 0.058 * s), anchor: .leading)
        g.fill(Path(roundedRect: R(0.07, 0.079, 0.085, 0.0045), cornerRadius: 0.002 * s), with: .color(rose))
        let spec = Text("2-SPUR · 19 cm/s").font(Typo.inter(max(6, 0.017 * s), .medium)).tracking(0.002 * s).foregroundColor(Color.white.opacity(0.38))
        g.draw(spec, at: CGPoint(x: 0.93 * s, y: 0.058 * s), anchor: .trailing)
        // Spulenteller
        for c in [ReelGeometry.leftCenter, ReelGeometry.rightCenter] {
            g.fill(circle(c, 0.214), with: .color(Color(argb: 0xFF100E0F)))
            g.stroke(circle(c, 0.214), with: .color(Color.white.opacity(0.06)), lineWidth: 1)
        }
        heads(g, s: s)
        vuFace(g, s: s, rect: ReelGeometry.vuLeft, channel: "L")
        vuFace(g, s: s, rect: ReelGeometry.vuRight, channel: "R")
        // Zählwerk-Fenster
        let counter = Path(roundedRect: R(ReelGeometry.counter.minX, ReelGeometry.counter.minY, ReelGeometry.counter.width, ReelGeometry.counter.height),
                           cornerRadius: 0.012 * s, style: .continuous)
        g.fill(counter, with: .color(Color.black.opacity(0.82)))
        g.stroke(counter, with: .color(Color.white.opacity(0.07)), lineWidth: 1)
    }

    /// Kopfträger, Tonköpfe, Umlenkrollen, Capstan und Andruckrolle.
    static func heads(_ g: GraphicsContext, s: CGFloat) {
        func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x * s, y: y * s, width: w * s, height: h * s) }
        func circle(_ p: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: (p.x - r) * s, y: (p.y - r) * s, width: 2 * r * s, height: 2 * r * s)) }
        let block = Path(roundedRect: R(0.285, 0.695, 0.43, 0.108), cornerRadius: 0.014 * s, style: .continuous)
        g.fill(block, with: .linearGradient(Gradient(colors: [Color(argb: 0xFF3B3638), Color(argb: 0xFF221F20)]),
                                            startPoint: CGPoint(x: 0, y: 0.695 * s), endPoint: CGPoint(x: 0, y: 0.803 * s)))
        g.stroke(block, with: .color(Color.white.opacity(0.08)), lineWidth: 1)
        let chrome = Gradient(colors: [Color(argb: 0xFFE4E0E2), Color(argb: 0xFF8E898B), Color(argb: 0xFFCBC7C9)])
        for x in [CGFloat(0.355), 0.44, 0.525] {
            let rect = R(x, 0.737, 0.046, 0.05)
            g.fill(Path(roundedRect: rect, cornerRadius: 0.008 * s), with: .linearGradient(chrome, startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0)))
            var gap = Path()
            gap.move(to: CGPoint(x: rect.midX, y: rect.minY + 1))
            gap.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.45))
            g.stroke(gap, with: .color(Color.black.opacity(0.55)), lineWidth: 0.7)
        }
        for c in [ReelGeometry.guideLeft, ReelGeometry.guideRight] {
            let r = ReelGeometry.guideRadius
            g.fill(circle(c, r), with: .radialGradient(Gradient(colors: [Color(argb: 0xFFEDE9EB), Color(argb: 0xFF8A8587)]),
                                                       center: CGPoint(x: (c.x - r * 0.3) * s, y: (c.y - r * 0.3) * s), startRadius: 0, endRadius: r * 1.4 * s))
            g.fill(circle(c, r * 0.28), with: .color(Color(argb: 0xFF2A2627)))
        }
        g.fill(circle(ReelGeometry.capstan, 0.009), with: .color(Color(argb: 0xFFD2CDCF)))
        g.fill(circle(ReelGeometry.pinch, 0.021), with: .color(Color(argb: 0xFF141112)))
        g.stroke(circle(ReelGeometry.pinch, 0.021), with: .color(Color.white.opacity(0.09)), lineWidth: 1)
        g.fill(circle(ReelGeometry.pinch, 0.005), with: .color(Color(argb: 0xFF6E696B)))
    }

    /// Hinterleuchtete VU-Skala mit Teilung, Rosé-Bereich und Beschriftung.
    static func vuFace(_ g: GraphicsContext, s: CGFloat, rect u: CGRect, channel: String) {
        let rect = CGRect(x: u.minX * s, y: u.minY * s, width: u.width * s, height: u.height * s)
        let bezel = Path(roundedRect: rect.insetBy(dx: -0.007 * s, dy: -0.007 * s), cornerRadius: 0.018 * s, style: .continuous)
        g.fill(bezel, with: .color(Color(argb: 0xFF0C0A0B)))
        let face = Path(roundedRect: rect, cornerRadius: 0.012 * s, style: .continuous)
        g.fill(face, with: .linearGradient(Gradient(colors: [Color(argb: 0xFFF6E2B6), Color(argb: 0xFFE0BF88)]),
                                           startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
        let pivot = CGPoint(x: rect.midX, y: rect.minY + rect.height * 1.2)
        let radius = rect.height * 0.98
        func angle(_ deg: Double) -> Double { (deg - 90) * Double.pi / 180 }
        // Skala
        let scale = polyline(ReelGeometry.arc(pivot, radius, from: angle(-47), to: angle(22), steps: 24))
        g.stroke(scale, with: .color(Color(argb: 0xFF3A2C24).opacity(0.85)), lineWidth: max(0.8, 0.0028 * s))
        let red = polyline(ReelGeometry.arc(pivot, radius, from: angle(22), to: angle(47), steps: 12))
        g.stroke(red, with: .color(Color(argb: 0xFFD4566F)), lineWidth: max(1.6, 0.006 * s))
        for deg in [-47.0, -34, -22, -11, 0, 11, 22, 34, 47] {
            let a = angle(deg)
            let inner = radius * (deg == 0 || deg == 22 ? 0.86 : 0.91)
            var tick = Path()
            tick.move(to: CGPoint(x: pivot.x + inner * CGFloat(cos(a)), y: pivot.y + inner * CGFloat(sin(a))))
            tick.addLine(to: CGPoint(x: pivot.x + radius * CGFloat(cos(a)), y: pivot.y + radius * CGFloat(sin(a))))
            g.stroke(tick, with: .color(deg > 22 ? Color(argb: 0xFFD4566F) : Color(argb: 0xFF3A2C24).opacity(0.85)), lineWidth: max(0.7, 0.0022 * s))
        }
        let ink = Color(argb: 0xFF3A2C24)
        g.draw(Text("VU").font(Typo.inter(max(6, 0.024 * s), .bold)).foregroundColor(ink.opacity(0.8)),
               at: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.66), anchor: .center)
        g.draw(Text(channel).font(Typo.inter(max(5, 0.016 * s), .semibold)).foregroundColor(ink.opacity(0.6)),
               at: CGPoint(x: rect.minX + 0.014 * s, y: rect.maxY - 0.012 * s), anchor: .bottomLeading)
        g.draw(Text("+3").font(Typo.inter(max(5, 0.014 * s), .semibold)).foregroundColor(Color(argb: 0xFFD4566F)),
               at: CGPoint(x: rect.maxX - 0.014 * s, y: rect.minY + 0.012 * s), anchor: .topTrailing)
        g.draw(Text("−20").font(Typo.inter(max(5, 0.014 * s), .semibold)).foregroundColor(ink.opacity(0.7)),
               at: CGPoint(x: rect.minX + 0.014 * s, y: rect.minY + 0.012 * s), anchor: .topLeading)
    }

    // Wickel und Band -------------------------------------------------------------------------

    static func tape(_ g: GraphicsContext, s: CGFloat, left: CGFloat, right: CGFloat) {
        let lc = CGPoint(x: ReelGeometry.leftCenter.x * s, y: ReelGeometry.leftCenter.y * s)
        let rc = CGPoint(x: ReelGeometry.rightCenter.x * s, y: ReelGeometry.rightCenter.y * s)
        for (c, r) in [(lc, left * s), (rc, right * s)] {
            let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
            g.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(stops: [
                .init(color: Color(argb: 0xFF2A1E19), location: 0),
                .init(color: Color(argb: 0xFF1B1310), location: 0.55),
                .init(color: Color(argb: 0xFF3E2D25), location: 0.97),
                .init(color: Color(argb: 0xFF5A4336), location: 1),
            ]), center: c, startRadius: 0, endRadius: r))
            g.stroke(Path(ellipseIn: rect.insetBy(dx: r * 0.3, dy: r * 0.3)), with: .color(Color.white.opacity(0.035)), lineWidth: 1)
            g.stroke(Path(ellipseIn: rect.insetBy(dx: r * 0.62, dy: r * 0.62)), with: .color(Color.white.opacity(0.03)), lineWidth: 1)
        }
        // Bandweg: linker Wickel → Umlenkrolle → Tonköpfe/Capstan → Umlenkrolle → rechter Wickel
        let rg = ReelGeometry.guideRadius * s
        let gl = CGPoint(x: ReelGeometry.guideLeft.x * s, y: ReelGeometry.guideLeft.y * s)
        let gr = CGPoint(x: ReelGeometry.guideRight.x * s, y: ReelGeometry.guideRight.y * s)
        let lp = CGPoint(x: gl.x - rg, y: gl.y)
        let rp = CGPoint(x: gr.x + rg, y: gr.y)
        let tl = CassetteGeometry.tangentPoint(cx: Float(lc.x), cy: Float(lc.y), r: Float(left * s), fromX: Float(lp.x), fromY: Float(lp.y), left: true)
        let tr = CassetteGeometry.tangentPoint(cx: Float(rc.x), cy: Float(rc.y), r: Float(right * s), fromX: Float(rp.x), fromY: Float(rp.y), left: false)
        var pts: [CGPoint] = [CGPoint(x: CGFloat(tl.x), y: CGFloat(tl.y))]
        pts.append(contentsOf: ReelGeometry.arc(gl, rg, from: Double.pi, to: Double.pi / 2, steps: 8))
        pts.append(contentsOf: ReelGeometry.arc(gr, rg, from: Double.pi / 2, to: 0, steps: 8))
        pts.append(CGPoint(x: CGFloat(tr.x), y: CGFloat(tr.y)))
        let path = polyline(pts)
        g.stroke(path, with: .color(Color(argb: 0xFF3A2A22)), style: StrokeStyle(lineWidth: max(1.2, 0.0065 * s), lineCap: .round, lineJoin: .round))
        g.stroke(path, with: .color(Color(argb: 0xFF7A5C4A).opacity(0.35)), style: StrokeStyle(lineWidth: max(0.5, 0.002 * s), lineCap: .round, lineJoin: .round))
    }

    // Spulenflansch ---------------------------------------------------------------------------

    static func flange(_ g: GraphicsContext, size: CGSize) {
        let r = min(size.width, size.height) / 2
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        var disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        var windows = Path()
        for k in 0..<3 {
            let mid = Double(k) * 2 * Double.pi / 3 - Double.pi / 2
            let half = 0.6
            var pts = ReelGeometry.arc(c, r * 0.88, from: mid - half, to: mid + half, steps: 14)
            pts.append(contentsOf: ReelGeometry.arc(c, r * 0.36, from: mid + half * 0.72, to: mid - half * 0.72, steps: 8))
            var w = polyline(pts)
            w.closeSubpath()
            windows.addPath(w)
        }
        disc.addPath(windows)
        let eo = FillStyle(eoFill: true)
        g.fill(disc, with: .color(Color(argb: 0xFFB5B0B2)), style: eo)
        // Drehriefen (rotationssymmetrisch – Drehung bleibt glaubwürdig)
        for f in [CGFloat(0.94), 0.9, 0.3, 0.26] {
            g.stroke(Path(ellipseIn: CGRect(x: c.x - r * f, y: c.y - r * f, width: 2 * r * f, height: 2 * r * f)),
                     with: .color(Color.black.opacity(0.12)), lineWidth: 0.6)
        }
        g.stroke(windows, with: .color(Color.black.opacity(0.45)), lineWidth: 0.8)
        g.stroke(Path(ellipseIn: CGRect(x: c.x - r + 0.5, y: c.y - r + 0.5, width: 2 * r - 1, height: 2 * r - 1)),
                 with: .color(Color.white.opacity(0.35)), lineWidth: 1)
        // Nabe mit drei Mitnehmern
        let hub = r * 0.25
        g.fill(Path(ellipseIn: CGRect(x: c.x - hub, y: c.y - hub, width: 2 * hub, height: 2 * hub)), with: .color(Color(argb: 0xFF5E595B)))
        for k in 0..<3 {
            let a = Double(k) * 2 * Double.pi / 3 + Double.pi / 6
            let p = CGPoint(x: c.x + hub * 0.9 * CGFloat(cos(a)), y: c.y + hub * 0.9 * CGFloat(sin(a)))
            g.fill(Path(ellipseIn: CGRect(x: p.x - hub * 0.16, y: p.y - hub * 0.16, width: hub * 0.32, height: hub * 0.32)), with: .color(Color(argb: 0xFF2C2829)))
        }
    }
}
