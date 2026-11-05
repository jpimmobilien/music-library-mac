import SwiftUI
import AppKit
import MLCore
import MLRender

// MARK: - Mini-Mittelstücke (v2)
//
// Der Mini-Player zeigt das gewählte Design im Kleinen: Platte mit Cover-Label, Kassette mit Naben,
// CD mit Cover-Ring, Tonband-Spulen, Aurora-Ring oder Cover mit Lichtschein. Alles ist aus wenigen,
// ruhenden Formen gebaut; je Bild ändert sich nur ein Drehwinkel (TimelineView, höchstens 40 Bilder/s,
// nur während der Wiedergabe und nur, solange der große Player geschlossen ist).

/// Drehbewegung mit weichem An- und Auslaufen (Grad, Grad/s).
final class SpinMotion: ObservableObject {
    private(set) var angle: Double = 0
    private(set) var velocity: Double = 0
    private let clock = FrameClock()

    /// Ein Bild weiter; Rückgabe: dreht sich noch?
    @discardableResult
    func step(_ now: Date, target: Double) -> Bool {
        let dt = Double(clock.dt(now))
        let tau: Double = target > velocity ? 0.25 : 0.4
        velocity += (target - velocity) * (1 - exp(-dt / tau))
        if abs(target - velocity) < 0.5 { velocity = target }
        angle = (angle + velocity * dt).truncatingRemainder(dividingBy: 360)
        return !(target == 0 && velocity == 0)
    }
}

/// Liefert einen Drehwinkel an den Inhalt; läuft nur, solange sich etwas dreht.
struct MiniSpinner<Content: View>: View {
    let running: Bool
    let allowed: Bool
    let degreesPerSecond: Double
    @ViewBuilder let content: (Double) -> Content
    @StateObject private var motion = SpinMotion()
    @State private var idleTick = 0

    var body: some View {
        let moving = allowed && (running || motion.velocity != 0)
        TimelineView(.animation(minimumInterval: 1.0 / 40, paused: !moving)) { ctx in
            let _ = idleTick
            let active = moving ? motion.step(ctx.date, target: running ? degreesPerSecond : 0) : false
            content(motion.angle)
                .onChange(of: active) { a in if !a { DispatchQueue.main.async { idleTick &+= 1 } } }
        }
    }
}

/// Mittelstück des Mini-Players im gewählten Design (oder schlichtes Cover).
struct MiniHeroView: View {
    let theme: PlayerTheme
    let showsDesign: Bool
    /// Höhe des Mittelstücks (Breite = Höhe × `theme.uiMiniAspect`).
    let side: CGFloat
    let track: Track?
    @ObservedObject var artwork: NowPlayingArtwork
    let playing: Bool
    /// Dauerhafte Bewegung erlaubt (Einstellung, Systemeinstellung, großer Player geschlossen).
    let animate: Bool
    let speed: Float
    let cassetteColor: CassetteColor
    let clock: PlaybackClock

    static func width(theme: PlayerTheme, showsDesign: Bool, side: CGFloat) -> CGFloat {
        showsDesign ? side * theme.uiMiniAspect : side
    }

    var body: some View {
        let category = GenreStyle.category(track?.genres.first)
        let cover = MiniCoverInput(image: artwork.image, category: category, loading: artwork.loading, key: artwork.key ?? "-")
        let glow = Color(argb: artwork.palette.glow)
        Group {
            if showsDesign {
                design(cover: cover, glow: glow)
            } else {
                MiniCoverGlow(side: side, cover: cover, glow: glow, playing: playing, glass: false)
            }
        }
        .frame(width: MiniHeroView.width(theme: theme, showsDesign: showsDesign, side: side), height: side)
    }

    @ViewBuilder
    private func design(cover: MiniCoverInput, glow: Color) -> some View {
        switch theme {
        case .vinylStudio:
            MiniVinyl(side: side, cover: cover, running: playing, allowed: animate, speed: Double(speed))
        case .portableCD:
            MiniCD(side: side, cover: cover, running: playing, allowed: animate, speed: Double(speed))
        case .cassette:
            MiniCassette(height: side, cover: cover, running: playing, allowed: animate,
                         shell: CassetteShell.swatch(cassetteColor, palette: artwork.palette), clock: clock)
        case .reelToReel:
            MiniReels(height: side, cover: cover, running: playing, allowed: animate, clock: clock)
        case .aurora:
            MiniAurora(side: side, cover: cover, lights: AuroraColors(palette: artwork.palette, dark: true), running: playing, allowed: animate)
        case .modernGlass:
            MiniCoverGlow(side: side, cover: cover, glow: glow, playing: playing, glass: true)
        case .classic:
            MiniCoverGlow(side: side, cover: cover, glow: glow, playing: playing, glass: false)
        }
    }
}

/// Cover-Angaben für die kleinen Mittelstücke.
struct MiniCoverInput: Equatable {
    let image: NSImage?
    let category: GenreCategory
    let loading: Bool
    let key: String

    static func == (a: MiniCoverInput, b: MiniCoverInput) -> Bool {
        a.image === b.image && a.category == b.category && a.loading == b.loading && a.key == b.key
    }
}

/// Rundes Cover (Label, Nabe, Ring).
private struct MiniCircleCover: View {
    let cover: MiniCoverInput
    let diameter: CGFloat

    var body: some View {
        ArtworkBox(image: cover.image, category: cover.category, iconFraction: 0.45, loading: cover.loading, circle: true)
            .frame(width: diameter, height: diameter)
    }
}

// MARK: Platte

private struct MiniVinyl: View {
    let side: CGFloat
    let cover: MiniCoverInput
    let running: Bool
    let allowed: Bool
    let speed: Double

    var body: some View {
        ZStack {
            MiniRecordDisc(side: side)
            MiniSpinner(running: running, allowed: allowed, degreesPerSecond: 200 * speed) { angle in
                MiniCircleCover(cover: cover, diameter: side * 0.4)
                    .rotationEffect(.degrees(angle))
            }
            Circle()
                .fill(Color(argb: 0xFFDAD5D7))
                .frame(width: max(2.5, side * 0.035), height: max(2.5, side * 0.035))
            MiniDiscSheen(diameter: side * 0.94, strength: 0.16)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// Schallplatte (rotationssymmetrisch – dreht nicht mit, nur das Label zeigt die Drehung).
private struct MiniRecordDisc: View {
    let side: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.black.opacity(0.35), .clear], center: .center, startRadius: side * 0.44, endRadius: side * 0.53))
                .frame(width: side * 1.06, height: side * 1.06)
                .offset(y: side * 0.025)
            Circle()
                .fill(RadialGradient(colors: [Color(argb: 0xFF1D1B1C), Color(argb: 0xFF0D0C0D), Color(argb: 0xFF181617)], center: .center, startRadius: 0, endRadius: side * 0.48))
                .frame(width: side * 0.96, height: side * 0.96)
            ForEach(0..<6, id: \.self) { i in
                Circle()
                    .stroke(Color.white.opacity(i % 2 == 0 ? 0.075 : 0.04), lineWidth: 0.6)
                    .frame(width: side * (0.5 + 0.075 * CGFloat(i)), height: side * (0.5 + 0.075 * CGFloat(i)))
            }
            Circle()
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                .frame(width: side * 0.96, height: side * 0.96)
        }
        .allowsHitTesting(false)
    }
}

/// Ruhender Glanz auf Platte bzw. CD.
private struct MiniDiscSheen: View {
    let diameter: CGFloat
    let strength: Double

    var body: some View {
        Circle()
            .fill(AngularGradient(gradient: Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: Color.white.opacity(strength), location: 0.1),
                .init(color: .clear, location: 0.21),
                .init(color: .clear, location: 0.5),
                .init(color: Color.white.opacity(strength * 0.7), location: 0.6),
                .init(color: .clear, location: 0.71),
                .init(color: .clear, location: 1),
            ]), center: .center, angle: .degrees(-35)))
            .frame(width: diameter, height: diameter)
            .allowsHitTesting(false)
    }
}

// MARK: CD

private struct MiniCD: View {
    let side: CGFloat
    let cover: MiniCoverInput
    let running: Bool
    let allowed: Bool
    let speed: Double

    var body: some View {
        let d = side * 0.95
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.black.opacity(0.25), .clear], center: .center, startRadius: side * 0.44, endRadius: side * 0.53))
                .frame(width: side * 1.06, height: side * 1.06)
                .offset(y: side * 0.02)
            Circle()
                .fill(LinearGradient(colors: [Color(argb: 0xFFEDEAEC), Color(argb: 0xFFAFAAAD), Color(argb: 0xFFF5F3F4), Color(argb: 0xFF9C979A)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: d, height: d)
            Circle()
                .fill(AngularGradient(gradient: Gradient(colors: [Color(argb: 0x66FF7A9C), Color(argb: 0x66FFD36E), Color(argb: 0x6679E2A8),
                                                                  Color(argb: 0x6670B8FF), Color(argb: 0x66B48CFF), Color(argb: 0x66FF7A9C)]),
                                      center: .center, angle: .degrees(20)))
                .frame(width: d, height: d)
                .blendMode(.overlay)
            MiniSpinner(running: running, allowed: allowed, degreesPerSecond: 216 * speed) { angle in
                MiniCircleCover(cover: cover, diameter: side * 0.72)
                    .mask(MiniRing(innerFraction: 0.38).fill(style: FillStyle(eoFill: true)))
                    .rotationEffect(.degrees(angle))
            }
            Circle()
                .fill(Color(argb: 0xFFDCD8DA).opacity(0.92))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 0.6))
                .frame(width: side * 0.26, height: side * 0.26)
            Circle()
                .fill(Color.black.opacity(0.3))
                .frame(width: side * 0.08, height: side * 0.08)
            MiniDiscSheen(diameter: d, strength: 0.32)
                .blendMode(.screen)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// Kreisring (für den Cover-Ring der CD; mit `eoFill` zu füllen).
struct MiniRing: Shape {
    let innerFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path(ellipseIn: rect)
        let inset = min(rect.width, rect.height) * (1 - innerFraction) / 2
        p.addEllipse(in: rect.insetBy(dx: inset, dy: inset))
        return p
    }
}

// MARK: Kassette

private struct MiniCassette: View {
    let height: CGFloat
    let cover: MiniCoverInput
    let running: Bool
    let allowed: Bool
    let shell: Color
    let clock: PlaybackClock

    var body: some View {
        let w = height * PlayerTheme.cassette.uiMiniAspect
        let h = w / 1.57
        let shape = RoundedRectangle(cornerRadius: h * 0.08, style: .continuous)
        let window = CGRect(x: w * 0.22, y: h * 0.42, width: w * 0.56, height: h * 0.3)
        let hubL = CGPoint(x: w * 0.33, y: h * 0.57)
        let hubR = CGPoint(x: w * 0.67, y: h * 0.57)
        ZStack(alignment: .topLeading) {
            shape
                .fill(LinearGradient(colors: [shell.opacity(0.95), shell], startPoint: .top, endPoint: .bottom))
                .overlay(shape.fill(LinearGradient(colors: [Color.white.opacity(0.22), .clear, Color.black.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 0.7))
                .frame(width: w, height: h)
            MiniCassetteLabel(width: w, height: h, cover: cover)
            RoundedRectangle(cornerRadius: h * 0.05, style: .continuous)
                .fill(Color(argb: 0xF2181416))
                .frame(width: window.width, height: window.height)
                .offset(x: window.minX, y: window.minY)
            MiniTapePacks(clock: clock, window: window, hubL: hubL, hubR: hubR, maxRadius: h * 0.2, minRadius: h * 0.075)
            MiniSpinner(running: running, allowed: allowed, degreesPerSecond: 150) { angle in
                ZStack(alignment: .topLeading) {
                    MiniHub(diameter: h * 0.15)
                        .rotationEffect(.degrees(-angle))
                        .offset(x: hubL.x - h * 0.075, y: hubL.y - h * 0.075)
                    MiniHub(diameter: h * 0.15)
                        .rotationEffect(.degrees(-angle * 1.3))
                        .offset(x: hubR.x - h * 0.075, y: hubR.y - h * 0.075)
                }
                .frame(width: w, height: h, alignment: .topLeading)
            }
            MiniCassetteHead(width: w, height: h)
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .frame(width: w, height: height)
        .background(
            shape
                .fill(Color.black.opacity(0.28))
                .frame(width: w, height: h)
                .offset(y: h * 0.05)
        )
        .accessibilityHidden(true)
    }
}

/// Papieretikett mit Cover und Rosé-Streifen.
private struct MiniCassetteLabel: View {
    let width: CGFloat
    let height: CGFloat
    let cover: MiniCoverInput

    var body: some View {
        let lw = width * 0.88
        let lh = height * 0.3
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: height * 0.03, style: .continuous)
                .fill(Color(argb: 0xFFF3ECE7))
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Rectangle().fill(Color(argb: 0xFFD4566F)).frame(height: max(1.5, lh * 0.12))
            }
            ArtworkBox(image: cover.image, category: cover.category, cornerRadius: 1.5, iconFraction: 0.5, loading: cover.loading)
                .frame(width: lh * 0.7, height: lh * 0.7)
                .padding(.leading, lh * 0.12)
                .padding(.bottom, lh * 0.12)
        }
        .frame(width: lw, height: lh)
        .clipShape(RoundedRectangle(cornerRadius: height * 0.03, style: .continuous))
        .offset(x: width * 0.06, y: height * 0.07)
    }
}

/// Wickel im Fenster – folgen dem Fortschritt (nur diese kleine Ansicht liest `clock`).
private struct MiniTapePacks: View {
    @ObservedObject var clock: PlaybackClock
    let window: CGRect
    let hubL: CGPoint
    let hubR: CGPoint
    let maxRadius: CGFloat
    let minRadius: CGFloat

    var body: some View {
        let p: CGFloat = clock.durationMs > 0 ? CGFloat(min(1, max(0, Double(clock.positionMs) / Double(clock.durationMs)))) : 0
        let c2 = minRadius * minRadius
        let span = maxRadius * maxRadius - c2
        let rl = (c2 + (1 - p) * span).squareRoot()
        let rr = (c2 + p * span).squareRoot()
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(Color(argb: 0xFF2E211B))
                .frame(width: 2 * rl, height: 2 * rl)
                .offset(x: hubL.x - rl - window.minX, y: hubL.y - rl - window.minY)
            Circle()
                .fill(Color(argb: 0xFF2E211B))
                .frame(width: 2 * rr, height: 2 * rr)
                .offset(x: hubR.x - rr - window.minX, y: hubR.y - rr - window.minY)
        }
        .frame(width: window.width, height: window.height, alignment: .topLeading)
        .clipped()
        .offset(x: window.minX, y: window.minY)
        .allowsHitTesting(false)
    }
}

/// Nabe mit sechs Zähnen (dreht sich).
private struct MiniHub: View {
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color(argb: 0xFFEDE6DF))
            Circle().fill(Color(argb: 0xFF2A2426)).frame(width: diameter * 0.52, height: diameter * 0.52)
            ForEach(0..<6, id: \.self) { i in
                Capsule()
                    .fill(Color(argb: 0xFFEDE6DF))
                    .frame(width: diameter * 0.1, height: diameter * 0.2)
                    .offset(y: -diameter * 0.2)
                    .rotationEffect(.degrees(Double(i) * 60))
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Kopfbereich unten (dunkles Trapez mit Öffnungen).
private struct MiniCassetteHead: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: width * 0.2, y: height))
            p.addLine(to: CGPoint(x: width * 0.24, y: height * 0.8))
            p.addLine(to: CGPoint(x: width * 0.76, y: height * 0.8))
            p.addLine(to: CGPoint(x: width * 0.8, y: height))
            p.closeSubpath()
        }
        .fill(Color.black.opacity(0.42))
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }
}

// MARK: Tonband

private struct MiniReels: View {
    let height: CGFloat
    let cover: MiniCoverInput
    let running: Bool
    let allowed: Bool
    let clock: PlaybackClock

    var body: some View {
        let w = height * PlayerTheme.reelToReel.uiMiniAspect
        let h = height * 0.96
        let r = h * 0.33
        let cl = CGPoint(x: w * 0.28, y: h * 0.42)
        let cr = CGPoint(x: w * 0.72, y: h * 0.42)
        let panel = RoundedRectangle(cornerRadius: h * 0.12, style: .continuous)
        ZStack(alignment: .topLeading) {
            panel
                .fill(LinearGradient(colors: [Color(argb: 0xFF2E2A2C), Color(argb: 0xFF171415)], startPoint: .top, endPoint: .bottom))
                .overlay(panel.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.2), Color.black.opacity(0.4)], startPoint: .top, endPoint: .bottom), lineWidth: 0.7))
                .frame(width: w, height: h)
            MiniReelPacks(clock: clock, width: w, height: h, left: cl, right: cr, maxRadius: r * 0.9, minRadius: r * 0.3)
            MiniSpinner(running: running, allowed: allowed, degreesPerSecond: 90) { angle in
                ZStack(alignment: .topLeading) {
                    MiniFlange(radius: r, cover: cover)
                        .rotationEffect(.degrees(-angle))
                        .offset(x: cl.x - r, y: cl.y - r)
                    MiniFlange(radius: r, cover: cover)
                        .rotationEffect(.degrees(-angle * 1.25 - 40))
                        .offset(x: cr.x - r, y: cr.y - r)
                }
                .frame(width: w, height: h, alignment: .topLeading)
            }
            Capsule()
                .fill(Color(argb: 0xFFFF8FA6))
                .frame(width: w * 0.12, height: max(1.5, h * 0.025))
                .offset(x: w * 0.44, y: h * 0.86)
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .frame(width: w, height: height)
        .accessibilityHidden(true)
    }
}

/// Wickel und Band der Mini-Spulen (folgen dem Fortschritt).
private struct MiniReelPacks: View {
    @ObservedObject var clock: PlaybackClock
    let width: CGFloat
    let height: CGFloat
    let left: CGPoint
    let right: CGPoint
    let maxRadius: CGFloat
    let minRadius: CGFloat

    var body: some View {
        let p: CGFloat = clock.durationMs > 0 ? CGFloat(min(1, max(0, Double(clock.positionMs) / Double(clock.durationMs)))) : 0
        let c2 = minRadius * minRadius
        let span = maxRadius * maxRadius - c2
        let rl = (c2 + (1 - p) * span).squareRoot()
        let rr = (c2 + p * span).squareRoot()
        let tapeY = height * 0.86
        ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: left.x - rl, y: left.y))
                path.addLine(to: CGPoint(x: width * 0.16, y: tapeY))
                path.addLine(to: CGPoint(x: width * 0.84, y: tapeY))
                path.addLine(to: CGPoint(x: right.x + rr, y: right.y))
            }
            .stroke(Color(argb: 0xFF4A372D), style: StrokeStyle(lineWidth: max(0.8, height * 0.02), lineCap: .round, lineJoin: .round))
            Circle()
                .fill(Color(argb: 0xFF2E211B))
                .frame(width: 2 * rl, height: 2 * rl)
                .offset(x: left.x - rl, y: left.y - rl)
            Circle()
                .fill(Color(argb: 0xFF2E211B))
                .frame(width: 2 * rr, height: 2 * rr)
                .offset(x: right.x - rr, y: right.y - rr)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// Kleine Spule mit drei Fenstern und Cover-Nabe.
private struct MiniFlange: View {
    let radius: CGFloat
    let cover: MiniCoverInput

    var body: some View {
        ZStack {
            Canvas { g, size in ReelPainter.flange(g, size: size) }
                .frame(width: radius * 2, height: radius * 2)
            MiniCircleCover(cover: cover, diameter: radius * 0.44)
            Circle().fill(Color(argb: 0xFFFF8FA6)).frame(width: max(2, radius * 0.12), height: max(2, radius * 0.12))
        }
        .frame(width: radius * 2, height: radius * 2)
    }
}

// MARK: Aurora

private struct MiniAurora: View {
    let side: CGFloat
    let cover: MiniCoverInput
    let lights: AuroraColors
    let running: Bool
    let allowed: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [lights.primary.opacity(0.55), lights.secondary.opacity(0.2), .clear], center: .center,
                                     startRadius: side * 0.3, endRadius: side * 0.66))
                .frame(width: side * 1.32, height: side * 1.32)
                .opacity(running ? 1 : 0.6)
                .animation(.easeInOut(duration: 0.6), value: running)
            MiniSpinner(running: running, allowed: allowed, degreesPerSecond: 36) { angle in
                Circle()
                    .strokeBorder(AngularGradient(gradient: Gradient(colors: [lights.primary, lights.secondary, lights.tertiary, lights.highlight, lights.primary]),
                                                  center: .center), lineWidth: max(2, side * 0.07))
                    .frame(width: side * 0.94, height: side * 0.94)
                    .rotationEffect(.degrees(angle))
            }
            MiniCircleCover(cover: cover, diameter: side * 0.7)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.7))
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

// MARK: Cover mit Lichtschein (Classic, Modern Glass, ohne Design)

private struct MiniCoverGlow: View {
    let side: CGFloat
    let cover: MiniCoverInput
    let glow: Color
    let playing: Bool
    /// Modern Glass: kleine Glasscheibe hinter dem Cover.
    let glass: Bool

    var body: some View {
        let corner = side * 0.16
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        ZStack {
            RadialGradient(colors: [glow.opacity(playing ? 0.5 : 0.25), .clear], center: .center, startRadius: side * 0.25, endRadius: side * 0.72)
                .frame(width: side * 1.5, height: side * 1.5)
                .allowsHitTesting(false)
            if glass {
                shape
                    .fill(Color.white.opacity(0.16))
                    .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.6), Color.white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
                    .frame(width: side * 0.86, height: side * 0.86)
                    .rotationEffect(.degrees(-8))
                    .offset(x: -side * 0.06, y: -side * 0.03)
            }
            ArtworkBox(image: cover.image, category: cover.category, cornerRadius: corner * (glass ? 0.8 : 1), iconFraction: 0.45, loading: cover.loading)
                .frame(width: side * (glass ? 0.86 : 1), height: side * (glass ? 0.86 : 1))
                .overlay(shape.strokeBorder(Color.white.opacity(glass ? 0.4 : 0), lineWidth: 0.7).frame(width: side * 0.86, height: side * 0.86))
                .shadow(color: Color.black.opacity(0.22), radius: 3, x: 0, y: 2)
                .offset(x: glass ? side * 0.04 : 0, y: glass ? side * 0.03 : 0)
                .id(cover.key)
                .transition(.opacity)
        }
        .frame(width: side, height: side)
        .scaleEffect(playing ? 1 : 0.92)
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.45), value: playing)
        .animation(.easeOut(duration: 0.3), value: cover.key)
        .accessibilityHidden(true)
    }
}
