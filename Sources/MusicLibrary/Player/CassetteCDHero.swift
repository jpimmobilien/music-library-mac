import SwiftUI
import AppKit
import MLCore
import MLRender

// MARK: - Cassette Studio (Spec 4)

final class ReelMotion: ObservableObject {
    var reels = CassetteReels()
    let clock = FrameClock()

    @discardableResult
    func step(now: Date, playing: Bool, speed: Float, left: Float, right: Float) -> Bool {
        let dt = clock.dt(now)
        return reels.step(target: CassetteReels.targetMotor(playing: playing, speed: speed), radiusLeftMm: left, radiusRightMm: right, dt: dt)
    }
}

struct CassetteHero: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.displayScale) private var displayScale
    let side: CGFloat
    @ObservedObject var artwork: NowPlayingArtwork
    var showStatus: Bool = true
    var still: Bool = false

    var body: some View {
        let bayW = side
        let bayH = side / 1.43
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [Color(argb: 0xFF1F1A1C), Color(argb: 0xFF0C0A0B)], startPoint: .top, endPoint: .bottom))
                RadialGradient(colors: [Color(argb: 0x33FF9DB2), .clear], center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: 0.75 * bayW)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                CassetteBody(width: bayW * 0.94, artwork: artwork, still: still,
                             shell: CassetteShell.tint(model.settings.cassetteColor, palette: artwork.palette))
                // Glasscheibe
                ZStack(alignment: .topLeading) {
                    LinearGradient(stops: [
                        .init(color: Color.white.opacity(0.07), location: 0),
                        .init(color: Color.white.opacity(0.015), location: 0.35),
                        .init(color: .clear, location: 0.36),
                        .init(color: .clear, location: 1),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 0.88 * bayW, height: 1.5 / max(1, displayScale))
                        .offset(x: 0.06 * bayW, y: 1.5 / max(1, displayScale))
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .allowsHitTesting(false)
            }
            .frame(width: bayW, height: bayH)
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.black.opacity(0.7), Color.white.opacity(0.10)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            if showStatus {
                Spacer().frame(height: 10)
                DeckStatus(clock: player.clock)
            }
        }
        .frame(width: side, height: side)
        .accessibilityLabel("Kassette: \(player.current?.displayTitle ?? "–"), \(player.isPlaying ? "läuft" : "angehalten")")
    }
}

/// Kassette mit Wickeln, Bandweg, Naben und Etikett (Spec 4.3/4.4).
private struct CassetteBody: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.displayScale) private var displayScale
    let width: CGFloat
    @ObservedObject var artwork: NowPlayingArtwork
    var still: Bool
    /// Gehäusefarbe (`nil` = Original).
    var shell: Color?
    @State private var layers: CassetteLayers?
    @State private var fade: Double = 0
    @State private var idleTick = 0
    @StateObject private var motion = ReelMotion()

    var body: some View {
        let scale = max(1, displayScale)
        let W = max(64, Int((width * scale).rounded()))
        let H = CassetteRenderer.heightFor(W)
        ZStack {
            if let L = layers {
                ProgressObserver(clock: player.clock) { pos, dur in
                    let hasMedia = player.current != nil
                    let progress: Float = still ? 0.3 : (hasMedia && dur > 0 ? Float(min(1, max(0, Double(pos) / Double(dur)))) : 0)
                    let radii = CassetteGeometry.packRadii(progress)
                    let playing = !still && player.isPlaying
                    let animate = !still && PlayerMotionPolicy.continuous(model.settings)
                    let moving = animate && (playing || motion.reels.motor != 0)
                    TimelineView(.animation(minimumInterval: nil, paused: !moving)) { ctx in
                        let _ = idleTick
                        let active = animate ? motion.step(now: ctx.date, playing: playing, speed: model.settings.pitch.speed, left: radii.left, right: radii.right) : false
                        cassette(L, k: CGFloat(L.width) / width, radii: radii)
                            .onChange(of: active) { a in if !a { DispatchQueue.main.async { idleTick &+= 1 } } }
                    }
                }
                .opacity(fade)
            }
        }
        .frame(width: width, height: CGFloat(H) / scale)
        .task(id: W) {
            if let c = CassetteLayers.cache.cached(W) {
                layers = c
                fade = 1
                return
            }
            let l = await CassetteLayers.cache.layers(W)
            layers = l
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.38)) { fade = l == nil ? 0 : 1 }
        }
    }

    @ViewBuilder
    private func cassette(_ L: CassetteLayers, k scale: CGFloat, radii: (left: Float, right: Float)) -> some View {
        let kmm = CGFloat(CassetteRenderer.pxPerMm(L.width))
        let m = CGFloat(CassetteRenderer.MARGIN_MM)
        let X: (CGFloat) -> CGFloat = { mm in (mm + m) * kmm }
        let pt: (CGFloat) -> CGFloat = { px in px / scale }
        let hubL = CGPoint(x: X(CGFloat(CassetteGeometry.HUB_LEFT_X)), y: X(CGFloat(CassetteGeometry.HUB_Y)))
        let hubR = CGPoint(x: X(CGFloat(CassetteGeometry.HUB_RIGHT_X)), y: X(CGFloat(CassetteGeometry.HUB_Y)))
        let packPt = pt(CGFloat(L.packPx))
        let hubPt = pt(CGFloat(L.hubPx))
        ZStack(alignment: .topLeading) {
            Image(decorative: L.back, scale: scale)
            // Wickel
            ForEach(0..<2, id: \.self) { i in
                let c = i == 0 ? hubL : hubR
                let r = CGFloat(i == 0 ? radii.left : radii.right) * kmm
                Image(decorative: L.pack, scale: scale)
                    .frame(width: packPt, height: packPt)
                    .mask(Circle().frame(width: pt(2 * r), height: pt(2 * r)))
                    .offset(x: pt(c.x) - packPt / 2, y: pt(c.y) - packPt / 2)
            }
            // Bandweg
            Canvas { ctx, _ in
                let s = max(0.42 * kmm, 1)
                let color = GraphicsContext.Shading.color(Color(argb: 0xFF2A1D18))
                let lp = CGPoint(x: X(CGFloat(CassetteGeometry.ROLLER_LEFT_X - CassetteGeometry.ROLLER_RADIUS)), y: X(CGFloat(CassetteGeometry.ROLLER_Y)))
                let rp = CGPoint(x: X(CGFloat(CassetteGeometry.ROLLER_RIGHT_X + CassetteGeometry.ROLLER_RADIUS)), y: X(CGFloat(CassetteGeometry.ROLLER_Y)))
                let tl = CassetteGeometry.tangentPoint(cx: Float(hubL.x), cy: Float(hubL.y), r: radii.left * Float(kmm), fromX: Float(lp.x), fromY: Float(lp.y), left: true)
                let tr = CassetteGeometry.tangentPoint(cx: Float(hubR.x), cy: Float(hubR.y), r: radii.right * Float(kmm), fromX: Float(rp.x), fromY: Float(rp.y), left: false)
                var a = Path()
                a.move(to: CGPoint(x: pt(CGFloat(tl.x)), y: pt(CGFloat(tl.y))))
                a.addLine(to: CGPoint(x: pt(lp.x), y: pt(lp.y)))
                var b = Path()
                b.move(to: CGPoint(x: pt(CGFloat(tr.x)), y: pt(CGFloat(tr.y))))
                b.addLine(to: CGPoint(x: pt(rp.x), y: pt(rp.y)))
                ctx.stroke(a, with: color, style: StrokeStyle(lineWidth: pt(s), lineCap: .round))
                ctx.stroke(b, with: color, style: StrokeStyle(lineWidth: pt(s), lineCap: .round))
                var c = Path()
                let ty = X(CGFloat(CassetteGeometry.TAPE_Y))
                c.move(to: CGPoint(x: pt(X(CGFloat(CassetteGeometry.ROLLER_LEFT_X))), y: pt(ty)))
                c.addLine(to: CGPoint(x: pt(X(CGFloat(CassetteGeometry.ROLLER_RIGHT_X))), y: pt(ty)))
                ctx.stroke(c, with: color, style: StrokeStyle(lineWidth: pt(1.1 * s), lineCap: .butt))
            }
            .frame(width: pt(CGFloat(L.width)), height: pt(CGFloat(L.height)))
            // Naben (gegen den Uhrzeigersinn)
            Image(decorative: L.hub, scale: scale)
                .frame(width: hubPt, height: hubPt)
                .rotationEffect(.degrees(Double(motion.reels.angleLeft)))
                .offset(x: pt(CGFloat(Int(hubL.x - CGFloat(L.hubPx) / 2))), y: pt(CGFloat(Int(hubL.y - CGFloat(L.hubPx) / 2))))
            Image(decorative: L.hub, scale: scale)
                .frame(width: hubPt, height: hubPt)
                .rotationEffect(.degrees(Double(motion.reels.angleRight)))
                .offset(x: pt(CGFloat(Int(hubR.x - CGFloat(L.hubPx) / 2))), y: pt(CGFloat(Int(hubR.y - CGFloat(L.hubPx) / 2))))
            // Gehäusefarbe (unter der Vorderschale: Glanz, Kanten, Schrauben und Etikett bleiben darüber)
            if let shell {
                CassetteShellTint(kmm: kmm, scale: scale, color: shell)
                    .frame(width: pt(CGFloat(L.width)), height: pt(CGFloat(L.height)))
                    .transition(.opacity)
            }
            // Vorderschale + Etikett
            Image(decorative: L.front, scale: scale)
            CassetteLabel(kmm: kmm, scale: scale, X: X, artwork: artwork)
        }
        .frame(width: pt(CGFloat(L.width)), height: pt(CGFloat(L.height)), alignment: .topLeading)
        .animation(.easeInOut(duration: 0.45), value: shell)
    }
}

/// Farbiges Kassettengehäuse: Schale ohne Fenster, leicht durchscheinend (Wickel schimmern durch),
/// mit Lichtverlauf von links oben. Liegt unter der Vorderschale des Renderers.
private struct CassetteShellTint: View {
    /// Pixel je Millimeter und Pixel je Punkt.
    let kmm: CGFloat
    let scale: CGFloat
    let color: Color

    var body: some View {
        Canvas { ctx, _ in
            let m = CGFloat(CassetteRenderer.MARGIN_MM)
            let k = kmm / scale
            let shellRect = CGRect(x: m * k, y: m * k, width: CGFloat(CassetteGeometry.WIDTH_MM) * k, height: CGFloat(CassetteGeometry.HEIGHT_MM) * k)
            let windowRect = CGRect(x: (19.6 + m) * k, y: (18.3 + m) * k, width: 61.2 * k, height: 24.4 * k)
            let window = Path(roundedRect: windowRect, cornerRadius: 2.2 * k, style: .continuous)
            var body = Path(roundedRect: shellRect, cornerRadius: 3.2 * k, style: .continuous)
            body.addPath(window)
            let eo = FillStyle(eoFill: true)
            ctx.fill(body, with: .color(color.opacity(0.82)), style: eo)
            ctx.fill(body, with: .linearGradient(Gradient(stops: [
                .init(color: Color.white.opacity(0.22), location: 0),
                .init(color: Color.white.opacity(0.0), location: 0.42),
                .init(color: Color.black.opacity(0.28), location: 1),
            ]), startPoint: CGPoint(x: shellRect.minX, y: shellRect.minY), endPoint: CGPoint(x: shellRect.maxX * 0.7, y: shellRect.maxY)), style: eo)
            // Fenster: leicht getönter, klarer Kunststoff
            ctx.fill(window, with: .color(color.opacity(0.12)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Etikett: Cover, Titel, Interpret, Seite „A“ (Spec 4.4).
private struct CassetteLabel: View {
    @EnvironmentObject private var player: PlayerService
    let kmm: CGFloat
    let scale: CGFloat
    let X: (CGFloat) -> CGFloat
    @ObservedObject var artwork: NowPlayingArtwork

    var body: some View {
        let coverPx = CGFloat(Int((15.4 - 3.6 - 2.8) * kmm))
        let coverX = CGFloat(Int(X(4.6 + 1.3)))
        let coverY = CGFloat(Int(X(3.6 + 1.0)))
        let textLeft = X(5.9) + coverPx + 2.2 * kmm
        let textTop = CGFloat(Int(X(3.6 + 1.2)))
        let textWidth = X(95.8 - 9) - textLeft
        ZStack(alignment: .topLeading) {
            ArtworkBox(image: artwork.image, category: GenreStyle.category(player.current?.genres.first), cornerRadius: 2, iconFraction: 0.55, loading: artwork.loading)
                .frame(width: coverPx / scale, height: coverPx / scale)
                .id(artwork.key ?? "-")
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.32), value: artwork.key)
                .offset(x: coverX / scale, y: coverY / scale)
            VStack(alignment: .leading, spacing: 0) {
                Text(player.current?.displayTitle ?? "")
                    .font(Typo.inter(2.7 * kmm / scale, .semibold))
                    .foregroundColor(Color(argb: 0xFF2A2125))
                    .lineLimit(1)
                    .frame(height: 3.4 * kmm / scale)
                Text(player.current?.artistText ?? "Unbekannter Interpret")
                    .font(Typo.inter(2.1 * kmm / scale, .regular))
                    .foregroundColor(Color(argb: 0xFF6E6064))
                    .lineLimit(1)
                    .frame(height: 2.8 * kmm / scale)
            }
            .frame(width: max(0, textWidth / scale), alignment: .leading)
            .offset(x: textLeft / scale, y: textTop / scale)
            Text("A")
                .font(Typo.inter(4.4 * kmm / scale, .bold))
                .foregroundColor(Color(argb: 0xFFD4566F))
                .offset(x: CGFloat(Int(X(95.8 - 6.6))) / scale, y: CGFloat(Int(X(3.6 + 1.6))) / scale)
        }
        .allowsHitTesting(false)
    }
}

/// Statusleiste des Kassettendecks: Zählwerk, PLAY/PAUSE-Leuchten, Pegel oder Restzeit (Spec 4.5).
private struct DeckStatus: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @ObservedObject var clock: PlaybackClock

    var body: some View {
        let warm = Color(argb: 0xFFFF9DB2)
        let hasMedia = player.current != nil
        HStack(spacing: 14) {
            Text(Formatting.duration(clock.positionMs))
                .font(Typo.inter(20 * 0.875, .semibold))
                .monospacedDigit()
                .foregroundColor(warm)
                .background(RadialGradient(colors: [warm.opacity(0.10), .clear], center: .center, startRadius: 0, endRadius: 40))
            VStack(alignment: .leading, spacing: 3) {
                Lamp(label: "PLAY", on: player.isPlaying, color: warm)
                Lamp(label: "PAUSE", on: hasMedia && !player.isPlaying, color: Color(argb: 0xFFF3B37A))
            }
            if model.settings.visualizer && PlayerMotionPolicy.continuous(model.settings) {
                VuMeters()
                    .frame(height: 22)
                    .frame(maxWidth: .infinity)
            } else {
                Spacer()
                Text("−" + Formatting.duration(max(0, clock.durationMs - clock.positionMs)))
                    .textStyle(Typo.time)
                    .monospacedDigit()
                    .foregroundColor(Color(argb: 0xFFABA3A6))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LinearGradient(colors: [Color(argb: 0xFF0D0B0C), Color(argb: 0xFF171314)], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(LinearGradient(colors: [Color.black.opacity(0.6), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}

private struct Lamp: View {
    let label: String
    let on: Bool
    let color: Color

    var body: some View {
        let g: Double = on ? 1 : 0
        HStack(spacing: 5) {
            Circle()
                .fill(color.opacity(0.18 + 0.82 * g))
                .overlay(Circle().fill(color.opacity(0.35 * g)))
                .frame(width: 6, height: 6)
            Text(label)
                .font(Typo.inter(8.5 * 0.875 + 0.5, .semibold))
                .tracking(0.4)
                .foregroundColor(Color.white.opacity(0.35 + 0.45 * g))
        }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.26), value: on)
    }
}

/// Laufwerkstasten (Spec 4.6): vorheriger · zurück · Play/Pause · vor · nächster (Sprungweite aus den Einstellungen).
struct DeckKeys: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService

    var body: some View {
        let skip = model.settings.skipSeconds
        HStack(spacing: 8) {
            DeckKey(icon: Icons.previous, size: 22, label: "Vorheriger Titel") { player.previous() }
                .frame(width: 58)
            DeckKey(icon: Icons.replay10, size: 22, label: SkipText.label(skip, forward: false), skip: (skip, false)) { player.skipBackward() }
                .frame(width: 58)
            DeckKey(icon: player.isPlaying ? Icons.pause : Icons.play, size: 30, label: player.isPlaying ? "Pause" : "Abspielen", lamp: player.isPlaying) { player.togglePlay() }
                .frame(minWidth: 96, maxWidth: 176)
            DeckKey(icon: Icons.forward10, size: 22, label: SkipText.label(skip, forward: true), skip: (skip, true)) { player.skipForward() }
                .frame(width: 58)
            DeckKey(icon: Icons.next, size: 22, label: "Nächster Titel") { player.next() }
                .frame(width: 58)
                .disabled(!player.queue.hasNext)
        }
        .frame(height: 62)
        .frame(maxWidth: .infinity)
    }
}

private struct DeckKeyStyle: ButtonStyle {
    let lamp: Bool?
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let p: Double = configuration.isPressed ? 1 : 0
        configuration.label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Color(argb: 0xFF3A3235).opacity(1 - 0.25 * p), Color(argb: 0xFF1E191B)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.16 - 0.08 * p), Color.black.opacity(0.5)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .overlay(alignment: .top) {
                if let lamp {
                    Capsule()
                        .fill(Color(argb: 0xFFFF8FA6).opacity(lamp ? 1 : 0.25))
                        .frame(width: 14, height: 3)
                        .padding(.top, 6)
                        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.26), value: lamp)
                }
            }
            .offset(y: 2 * p)
            .animation(.linear(duration: 0.09), value: configuration.isPressed)
    }
}

private struct DeckKey: View {
    @Environment(\.isEnabled) private var enabled
    let icon: String
    let size: CGFloat
    let label: String
    var lamp: Bool? = nil
    /// Sprungtaste: Sekunden und Richtung (zeigt die eingestellte Sprungweite).
    var skip: (seconds: Int, forward: Bool)? = nil
    let action: () -> Void

    var body: some View {
        let tint = Color.white.opacity(enabled ? 0.92 : 0.3)
        Button(action: action) {
            if let skip {
                SkipGlyph(seconds: skip.seconds, forward: skip.forward, size: size, color: tint)
            } else {
                Icon(icon, size: size, color: tint)
            }
        }
        .buttonStyle(DeckKeyStyle(lamp: lamp))
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Portable CD (Spec 5)

final class DiscMotion: ObservableObject {
    var velocity: Float = 0
    var angle: Float = 0
    let clock = FrameClock()

    @discardableResult
    func step(now: Date, playing: Bool, speed: Float) -> Bool {
        let dt = clock.dt(now)
        let target = CdSpin.targetSpeed(playing: playing, speedFactor: speed)
        velocity = CdSpin.velocity(current: velocity, target: target, dt: dt)
        angle = CdSpin.angle(current: angle, velocity: velocity, dt: dt)
        return velocity != 0 || target != 0
    }
}

struct CDHero: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.displayScale) private var displayScale
    let side: CGFloat
    @ObservedObject var artwork: NowPlayingArtwork
    var still: Bool = false
    @State private var layers: CDLayers?
    @State private var label: CGImage?
    @State private var labelKey: String?
    @State private var fade: Double = 0
    @State private var idleTick = 0
    @StateObject private var motion = DiscMotion()

    var body: some View {
        let scale = max(1, displayScale)
        let sidePx = Int((side * scale).rounded())
        let W = min(1440, max(64, CdGeometry.widthToFit(sidePx, sidePx)))
        let H = CdGeometry.heightFor(W)
        let wPt = CGFloat(W) / scale
        let hPt = CGFloat(H) / scale
        let state: String = player.current == nil ? "keine Wiedergabe" : (player.isPlaying ? "CD dreht sich" : "angehalten")
        let a11y: String = "CD-Player: \(player.current?.displayTitle ?? "–"), \(state)"
        ZStack {
            // Widerschein in der Coverfarbe hinter dem Gerät (statisch)
            RadialGradient(colors: [Color(argb: artwork.palette.glow).opacity(still ? 0 : 0.22), .clear],
                           center: .center, startRadius: wPt * 0.25, endRadius: wPt * 0.72)
                .frame(width: wPt * 1.4, height: hPt * 1.3)
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.8), value: artwork.palette)
            if fade < 1 { placeholder(W: W, scale: scale) }
            if let L = layers {
                ProgressObserver(clock: player.clock) { pos, _ in
                    let playing = !still && player.isPlaying
                    let animate = !still && PlayerMotionPolicy.continuous(model.settings)
                    let moving = animate && (playing || motion.velocity != 0)
                    TimelineView(.animation(minimumInterval: nil, paused: !moving)) { ctx in
                        let _ = idleTick
                        let active = animate ? motion.step(now: ctx.date, playing: playing, speed: min(2, max(0.5, model.settings.pitch.speed))) : false
                        device(L, scale: CGFloat(L.width) / wPt, positionMs: still ? 83_000 : pos)
                            .onChange(of: active) { a in if !a { DispatchQueue.main.async { idleTick &+= 1 } } }
                    }
                }
                .opacity(fade)
            }
        }
        .frame(width: wPt, height: hPt)
        .frame(width: side, height: side)
        .task(id: W) {
            if let c = CDLayers.cache.cached(W) {
                layers = c
                fade = 1
                return
            }
            let l = await CDLayers.cache.layers(W)
            layers = l
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.38)) { fade = l == nil ? 0 : 1 }
        }
        .task(id: "\(artwork.key ?? "-")|\(layers?.labelPx ?? 0)|\(artwork.image != nil)") {
            guard let L = layers else { return }
            let key = artwork.key
            let img = await CoverLabels.make(artwork.image, size: L.labelPx, cd: true)
            withAnimation(.easeInOut(duration: 0.38)) {
                label = img
                labelKey = key
            }
        }
        .accessibilityLabel(a11y)
    }

    private func placeholder(W: Int, scale: CGFloat) -> some View {
        let k = CGFloat(CdGeometry.pxPerMm(W)) / scale
        let c = CdGeometry.discCenterPx(W)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 30 * k, style: .continuous)
                .fill(Color(argb: 0xFF242022))
                .frame(width: 140 * k, height: 158 * k)
                .offset(x: 6 * k, y: 6 * k)
            Circle()
                .fill(Color(argb: 0xFF0E0C0D))
                .frame(width: 2 * 63.6 * k, height: 2 * 63.6 * k)
                .offset(x: CGFloat(c.x) / scale - 63.6 * k, y: CGFloat(c.y) / scale - 63.6 * k)
        }
        .frame(width: CGFloat(W) / scale, height: CGFloat(CdGeometry.heightFor(W)) / scale, alignment: .topLeading)
    }

    @ViewBuilder
    private func device(_ L: CDLayers, scale: CGFloat, positionMs: Int64) -> some View {
        let c = CdGeometry.discCenterPx(L.width)
        let cx = CGFloat(c.x), cy = CGFloat(c.y)
        let discPt = CGFloat(L.discPx) / scale
        let overlayPt = CGFloat(L.overlayPx) / scale
        let labelPt = CGFloat(L.labelPx) / scale
        ZStack(alignment: .topLeading) {
            Image(decorative: L.body, scale: scale)
            ZStack {
                Image(decorative: L.disc, scale: scale)
                cdLabel(L, labelPt: labelPt)
                    .frame(width: labelPt, height: labelPt)
                    .id(labelKey ?? "-")
                    .transition(.opacity)
            }
            .frame(width: discPt, height: discPt)
            .rotationEffect(.degrees(Double(motion.angle)))
            .offset(x: (cx - CGFloat(L.discPx) / 2).rounded() / scale, y: (cy - CGFloat(L.discPx) / 2).rounded() / scale)
            Image(decorative: L.overlay, scale: scale)
                .frame(width: overlayPt, height: overlayPt)
                .offset(x: (cx - CGFloat(L.overlayPx) / 2).rounded() / scale, y: (cy - CGFloat(L.overlayPx) / 2).rounded() / scale)
            CDDisplayView(k: CGFloat(CdGeometry.pxPerMm(L.width)) / scale, positionMs: positionMs, still: still)
            CDLed(k: CGFloat(CdGeometry.pxPerMm(L.width)) / scale, still: still)
        }
        .frame(width: CGFloat(L.width) / scale, height: CGFloat(L.height) / scale, alignment: .topLeading)
    }

    @ViewBuilder
    private func cdLabel(_ L: CDLayers, labelPt: CGFloat) -> some View {
        let r = labelPt / 2
        let inner = r * CGFloat(CdGeometry.LABEL_HOLE_FRACTION)
        if let label {
            Image(decorative: label, scale: CGFloat(L.labelPx) / labelPt)
        } else if artwork.image != nil || artwork.loading {
            Circle()
                .stroke(Color(argb: 0xFF2A2527), lineWidth: r - inner)
                .frame(width: r + inner, height: r + inner)
        } else {
            ZStack(alignment: .bottom) {
                Image(decorative: L.fallbackLabel, scale: CGFloat(L.labelPx) / labelPt)
                let base = min(15, max(6, labelPt * 0.062))
                VStack(spacing: 0) {
                    Text(player.current?.displayTitle ?? "Musikbibliothek")
                        .font(Typo.inter(base, .semibold))
                        .foregroundColor(Color(argb: 0xFF2C2428))
                        .lineLimit(1)
                    Text(player.current?.artistText ?? "")
                        .font(Typo.inter(base * 0.78, .medium))
                        .foregroundColor(Color(argb: 0xFF6A5E62))
                        .lineLimit(1)
                }
                .frame(width: labelPt * 0.6)
                .padding(.bottom, labelPt * 0.15)
            }
        }
    }
}

/// LCD des CD-Players: ▶/❚❚, TRACK, Titelnummer und Zeit als Sieben-Segment-Ziffern, RPT/SHUF (Spec 5.5).
private struct CDDisplayView: View {
    @EnvironmentObject private var player: PlayerService
    let k: CGFloat
    let positionMs: Int64
    let still: Bool

    var body: some View {
        let hasMedia = still || player.current != nil
        let play = still ? false : (player.isPlaying && hasMedia)
        let bl: Double = hasMedia ? 1 : 0.4
        let LIT = Color(argb: 0xFFFFB6C6)
        let lit = LIT.opacity(0.35 + 0.65 * bl)
        let ghost = LIT.opacity(0.075)
        let w = 68 * k, h = 14.4 * k
        let originX = (42 * k).rounded()
        let originY = (144.4 * k).rounded()
        let trackNo = still ? 3 : ((player.queue.currentPlayPosition ?? -1) + 1)
        let track = hasMedia ? CdDisplay.trackText(trackNo) : "--"
        let time = CdDisplay.timeText(positionMs)
        let repeatMode = still ? RepeatSetting.off : player.repeatMode
        let shuffle = still ? false : player.shuffleEnabled
        Canvas { ctx, _ in
            func mm(_ v: CGFloat) -> CGFloat { v * k }
            // Grund
            let bg = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: mm(2.9))
            ctx.fill(bg, with: .radialGradient(Gradient(colors: [LIT.opacity(0.10 * bl), LIT.opacity(0.03 * bl)]),
                                               center: CGPoint(x: 0.5 * w, y: 0.45 * h), startRadius: 0, endRadius: 0.6 * w))
            // ▶
            var tri = Path()
            tri.move(to: CGPoint(x: mm(4.2), y: mm(4.9)))
            tri.addLine(to: CGPoint(x: mm(8.0), y: mm(7.2)))
            tri.addLine(to: CGPoint(x: mm(4.2), y: mm(9.5)))
            tri.closeSubpath()
            ctx.fill(tri, with: .color(hasMedia && play ? lit : ghost))
            // ❚❚
            for x in [9.6, 11.6] {
                ctx.fill(Path(roundedRect: CGRect(x: mm(CGFloat(x)), y: mm(4.9), width: mm(1.2), height: mm(4.6)), cornerRadius: mm(0.3)),
                         with: .color(hasMedia && !play ? lit : ghost))
            }
            // Texte
            let labelFont = Typo.inter(mm(1.75), .semibold)
            ctx.draw(Text("TRACK").font(labelFont).tracking(mm(0.12)).foregroundColor(lit.opacity(0.75)), at: CGPoint(x: mm(16.2), y: mm(1.6)), anchor: .topLeading)
            ctx.draw(Text(repeatMode == .one ? "RPT 1" : "RPT").font(labelFont).tracking(mm(0.12)).foregroundColor(repeatMode != .off ? lit : LIT.opacity(0.16)),
                     at: CGPoint(x: mm(57.4), y: mm(3.0)), anchor: .topLeading)
            ctx.draw(Text("SHUF").font(labelFont).tracking(mm(0.12)).foregroundColor(shuffle ? lit : LIT.opacity(0.16)),
                     at: CGPoint(x: mm(57.4), y: mm(8.2)), anchor: .topLeading)
            // Ziffern
            let dw: CGFloat = 3.7, dh: CGFloat = 7.0, t: CGFloat = 0.78, pitch: CGFloat = 4.7, dy: CGFloat = 4.9
            func digit(_ ch: Character, x: CGFloat, y: CGFloat, ts: CGFloat) {
                let segs = CdDisplay.segments(ch)
                let rects = CdDisplay.segmentRects(Float(dw * ts), Float(dh * ts), Float(t * ts))
                for i in 0..<7 {
                    let rx = CGFloat(rects[4 * i]), ry = CGFloat(rects[4 * i + 1]), rw = CGFloat(rects[4 * i + 2]), rh = CGFloat(rects[4 * i + 3])
                    let skew = 0.10 * dw * ts * (1 - (ry + rh / 2) / (dh * ts))
                    let rect = CGRect(x: mm(x + rx + skew), y: mm(y + ry), width: mm(rw), height: mm(rh))
                    let on = ch != " " && (segs & (1 << i)) != 0
                    ctx.fill(Path(roundedRect: rect, cornerRadius: mm(0.45 * t * ts)), with: .color(on ? lit : ghost))
                }
            }
            let ts: CGFloat = track.count >= 4 ? 0.74 : 1
            for (i, ch) in track.enumerated() {
                digit(ch, x: 16.2 + CGFloat(i) * pitch * ts, y: dy + dh * (1 - ts), ts: ts)
            }
            let sx: CGFloat = 55 - 2 * pitch + (pitch - dw)
            for (i, ch) in time.seconds.enumerated() { digit(ch, x: sx + CGFloat(i) * pitch, y: dy, ts: 1) }
            let colon = hasMedia ? lit : ghost
            for fy in [0.32, 0.70] {
                let r = mm(0.42)
                ctx.fill(Path(ellipseIn: CGRect(x: mm(sx - 1.55) - r, y: mm(dy + CGFloat(fy) * dh) - r, width: 2 * r, height: 2 * r)), with: .color(colon))
            }
            let n = CGFloat(time.minutes.count)
            let mx = (sx - 1.55) - 1.55 - n * pitch + (pitch - dw)
            for (i, ch) in time.minutes.enumerated() { digit(ch, x: mx + CGFloat(i) * pitch, y: dy, ts: 1) }
        }
        .frame(width: w, height: h)
        .offset(x: originX, y: originY)
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.4), value: hasMedia)
        .allowsHitTesting(false)
    }
}

private struct CDLed: View {
    @EnvironmentObject private var player: PlayerService
    let k: CGFloat
    let still: Bool

    var body: some View {
        let hasMedia = still || player.current != nil
        let play = !still && player.isPlaying
        let glow: Double = play ? 1 : (hasMedia ? 0.3 : 0.08)
        let r = 1.15 * k
        let color = Color(argb: 0xFFFF7D98)
        ZStack {
            Circle().fill(RadialGradient(colors: [color.opacity(0.5 * glow), .clear], center: .center, startRadius: 0, endRadius: 4.2 * r))
                .frame(width: 8.4 * r, height: 8.4 * r)
            Circle().fill(color.opacity(0.25 + 0.75 * glow)).frame(width: 2 * r, height: 2 * r)
            Circle().fill(Color.white.opacity(0.35 * glow)).frame(width: 0.8 * r, height: 0.8 * r).offset(x: -0.25 * r, y: -0.3 * r)
        }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.4), value: glow)
        .position(x: (23.5 + 6) * k, y: (145.6 + 6) * k)
        .allowsHitTesting(false)
    }
}

/// CD-Tasten (Spec 5.6): runde Tasten, Play mit rosé Ring.
struct CDButtons: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService

    var body: some View {
        let skip = model.settings.skipSeconds
        HStack {
            // Group: höchstens 10 direkte Elemente je ViewBuilder unter macOS 13
            Group {
                Spacer()
                CDButton(icon: Icons.replay10, diameter: 48, iconSize: 21, label: SkipText.label(skip, forward: false), skip: (skip, false)) { player.skipBackward() }
                Spacer()
            }
            CDButton(icon: Icons.previous, diameter: 56, iconSize: 26, label: "Vorheriger Titel") { player.previous() }
            Spacer()
            CDButton(icon: player.isPlaying ? Icons.pause : Icons.play, diameter: 72, iconSize: 34, label: player.isPlaying ? "Pause" : "Abspielen", play: true, glowing: player.isPlaying) { player.togglePlay() }
            Spacer()
            CDButton(icon: Icons.next, diameter: 56, iconSize: 26, label: "Nächster Titel") { player.next() }
                .disabled(!player.queue.hasNext)
            Spacer()
            CDButton(icon: Icons.forward10, diameter: 48, iconSize: 21, label: SkipText.label(skip, forward: true), skip: (skip, true)) { player.skipForward() }
            Spacer()
        }
        .frame(height: 76)
    }
}

private struct CDButtonStyle: ButtonStyle {
    let diameter: CGFloat
    let play: Bool
    let glowing: Bool

    func makeBody(configuration: Configuration) -> some View {
        let p: Double = configuration.isPressed ? 1 : 0
        let r = diameter / 2
        let f = r * (play ? 0.86 : 0.9)
        let g: Double = glowing ? 1 : 0
        ZStack {
            Circle().fill(Color.black.opacity(0.28)).frame(width: 2.04 * r, height: 2.04 * r).offset(y: 0.07 * r)
            if play {
                Circle().fill(RadialGradient(colors: [Color(argb: 0xFFE88AA0).opacity(0.32 * g), .clear], center: .center, startRadius: 0, endRadius: 1.5 * r))
                    .frame(width: 3 * r, height: 3 * r)
                    .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.3), value: glowing)
            }
            Circle().fill(LinearGradient(colors: play ? [Color(argb: 0xFFF2B4C2), Color(argb: 0xFFB45C72), Color(argb: 0xFFE59AAC)] : [Color(argb: 0xFF5A5457), Color(argb: 0xFF1A1718)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 2 * r, height: 2 * r)
            Circle().fill(RadialGradient(colors: [Color(argb: 0xFF4A4447).opacity(1 - 0.2 * p), Color(argb: 0xFF242022), Color(argb: 0xFF1B1819)],
                                         center: UnitPoint(x: 0.5 - 0.35 * f / (2 * f), y: 0.5 - 0.45 * f / (2 * f)), startRadius: 0, endRadius: 1.7 * f))
                .frame(width: 2 * f, height: 2 * f)
            Circle().stroke(Color.white.opacity(0.10 - 0.05 * p), lineWidth: 1).frame(width: 2 * f, height: 2 * f)
            configuration.label
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .scaleEffect(1 - 0.04 * p)
        .animation(.linear(duration: 0.09), value: configuration.isPressed)
    }
}

private struct CDButton: View {
    @Environment(\.isEnabled) private var enabled
    let icon: String
    let diameter: CGFloat
    let iconSize: CGFloat
    let label: String
    var play = false
    var glowing = false
    /// Sprungtaste: Sekunden und Richtung.
    var skip: (seconds: Int, forward: Bool)? = nil
    let action: () -> Void

    var body: some View {
        let tint = Color.white.opacity(enabled ? 0.93 : 0.3)
        Button(action: action) {
            if let skip {
                SkipGlyph(seconds: skip.seconds, forward: skip.forward, size: iconSize, color: tint)
            } else {
                Icon(icon, size: iconSize, color: tint)
            }
        }
        .buttonStyle(CDButtonStyle(diameter: diameter, play: play, glowing: glowing))
        .help(label)
        .accessibilityLabel(label)
    }
}
