import SwiftUI
import AppKit
import MLCore
import MLRender

/// Bewegungszustand des Plattenspielers (Teller + Tonarm), je Bild fortgeschrieben.
final class VinylMotion: ObservableObject {
    var spin = TurntableSpin()
    let arm = TonearmMotion(target: -1, playing: false)
    let clock = FrameClock()
    private var initialized = false

    /// Startzustand ohne Animation (Spec 2.5: Ziel ohne Animation, pauseLift je nach Wiedergabe).
    func prepare(target: Float, playing: Bool) {
        guard !initialized else { return }
        initialized = true
        arm.snap(to: target, playing: playing)
    }

    /// Ein Bild fortschreiben. Rückgabe: bewegt sich noch etwas?
    @discardableResult
    func step(now: Date, playing: Bool, speed: Float, target: Float) -> Bool {
        let dt = clock.dt(now)
        arm.setTarget(target)
        arm.setPlaying(playing)
        arm.step(dt)
        let spinning = spin.step(target: TurntableSpin.targetSpeed(playing: playing, speed: speed), dt: dt)
        return spinning || arm.isAnimating
    }
}

/// Vinyl Studio – realistischer Plattenspieler mit Cover-Label und Tonarm (Spec 2).
struct VinylHero: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    @Environment(\.displayScale) private var displayScale
    let side: CGFloat
    @ObservedObject var artwork: NowPlayingArtwork
    /// Ruhende Vorschau (Design-Auswahl): keine Bewegung, Arm angehoben bei Fortschritt 0,3.
    var still: Bool = false

    @State private var layers: VinylLayers?
    @State private var label: CGImage?
    @State private var labelKey: String?
    @State private var fade: Double = 0
    @State private var idleTick = 0
    @StateObject private var motion = VinylMotion()

    var body: some View {
        let scale = max(1, displayScale)
        let S = max(64, Int((side * scale).rounded()))
        ZStack(alignment: .topLeading) {
            // Bodenschatten
            RadialGradient(colors: [Color.black.opacity(colors.dark ? 0.55 : 0.22), .clear],
                           center: UnitPoint(x: 0.5, y: 0.56), startRadius: 0, endRadius: 0.62 * side)
                .frame(width: side, height: side)
            // Schlagschatten des Gehäuses (statische Form – nicht pro Bild neu berechnen)
            RoundedRectangle(cornerRadius: 0.07 * side, style: .continuous)
                .fill(Color.black)
                .frame(width: side, height: side)
                .shadow(color: Color.black.opacity(0.30), radius: 12, y: 12)
                .shadow(color: colors.glassShadow, radius: 12)
                .opacity(layers == nil ? 0 : fade)
            if fade < 1 { placeholder }
            if let L = layers {
                ProgressObserver(clock: player.clock) { positionMs, durationMs in
                    let hasMedia = player.current != nil
                    let progress: Float = still ? 0.3 : (durationMs > 0 ? Float(min(1, max(0, Double(positionMs) / Double(durationMs)))) : 0)
                    let target: Float = hasMedia || still ? progress : -1
                    let playing = !still && player.isPlaying
                    let moving = !still && (playing || motion.spin.velocity != 0 || motion.arm.isAnimating)
                    TimelineView(.animation(minimumInterval: nil, paused: !moving)) { ctx in
                        let _ = idleTick
                        let active = still ? false : motion.step(now: ctx.date, playing: playing, speed: model.settings.pitch.speed, target: target)
                        turntable(L, scale: CGFloat(L.size) / side, playing: playing)
                            .onChange(of: active) { a in if !a { DispatchQueue.main.async { idleTick &+= 1 } } }
                    }
                    .onAppear { motion.prepare(target: target, playing: playing) }
                }
                .opacity(fade)
            }
        }
        .frame(width: side, height: side)
        .task(id: S) {
            if let cached = VinylLayers.cache.cached(S) {
                layers = cached
                fade = 1
                return
            }
            let l = await VinylLayers.cache.layers(S)
            layers = l
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.42)) { fade = l == nil ? 0 : 1 }
        }
        .task(id: "\(artwork.key ?? "-")|\(layers?.labelPx ?? 0)|\(artwork.image != nil)") {
            guard let L = layers else { return }
            let key = artwork.key
            let img = await CoverLabels.make(artwork.image, size: L.labelPx, cd: false)
            withAnimation(.easeInOut(duration: 0.38)) {
                label = img
                labelKey = key
            }
        }
        .accessibilityElement()
        .accessibilityLabel(player.current == nil ? "Plattenspieler, keine Wiedergabe" : (player.isPlaying ? "Plattenspieler: Platte dreht sich, Tonarm aufgesetzt" : "Plattenspieler: angehalten, Tonarm angehoben"))
    }

    private var placeholder: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 0.07 * side, style: .continuous)
                .fill(Color(argb: 0xFF1B191A))
            Circle()
                .fill(Color(argb: 0xFF0B0A0B))
                .frame(width: 0.83 * side, height: 0.83 * side)
                .offset(x: 0.455 * side - 0.415 * side, y: 0.5 * side - 0.415 * side)
        }
        .frame(width: side, height: side)
    }

    /// Alle Ebenen in px-Koordinaten (`k` = px je pt).
    @ViewBuilder
    private func turntable(_ L: VinylLayers, scale k: CGFloat, playing: Bool) -> some View {
        let S = CGFloat(L.size)
        let recordPt = CGFloat(L.recordPx) / k
        let recordLeft = (0.455 * S - CGFloat(L.recordPx) / 2).rounded() / k
        let recordTop = (0.5 * S - CGFloat(L.recordPx) / 2).rounded() / k
        let labelPt = CGFloat(L.labelPx) / k
        let pose = TonearmPose(size: Float(S), arm: L.armRaster, progress: motion.arm.progress, lift: motion.arm.lift)
        let armW = CGFloat(L.armRaster.arm.width) / k
        let armH = CGFloat(L.armRaster.arm.height) / k
        let pivot = UnitPoint(x: CGFloat(L.armRaster.pivotX) / CGFloat(L.armRaster.arm.width), y: CGFloat(L.armRaster.pivotY) / CGFloat(L.armRaster.arm.height))
        let shadowW = CGFloat(L.armRaster.shadow.width) / k
        let shadowH = CGFloat(L.armRaster.shadow.height) / k
        let shadowPivot = UnitPoint(x: CGFloat(L.armRaster.pivotX) / CGFloat(L.armRaster.shadow.width), y: CGFloat(L.armRaster.pivotY) / CGFloat(L.armRaster.shadow.height))
        ZStack(alignment: .topLeading) {
            // 1 Gehäuse
            Image(decorative: L.plinth, scale: k).frame(width: side, height: side)
            // 2–4 Platte, Label, Papier (drehen gemeinsam)
            ZStack {
                Image(decorative: L.record, scale: k)
                labelView(L, labelPt: labelPt)
                    .frame(width: labelPt, height: labelPt)
                    .id(labelKey ?? "-")
                    .transition(.opacity)
                PaperOverlay(radius: labelPt / 2)
                    .frame(width: labelPt, height: labelPt)
            }
            .frame(width: recordPt, height: recordPt)
            .rotationEffect(.degrees(Double(motion.spin.angle)))
            .offset(x: recordLeft, y: recordTop)
            // 5 Lichtreflexe (stehen still)
            Image(decorative: L.sheen, scale: k)
                .frame(width: recordPt, height: recordPt)
                .offset(x: recordLeft, y: recordTop)
            // 6 Betriebsleuchte
            PowerLED(size: side, speed: model.settings.pitch.speed, playing: playing)
            // 7 Tonarm-Schatten
            Image(decorative: L.armShadow, scale: k)
                .frame(width: shadowW, height: shadowH)
                .rotationEffect(.degrees(Double(pose.angleDegrees)), anchor: shadowPivot)
                .offset(x: CGFloat(pose.shadowOriginX) / k, y: CGFloat(pose.shadowOriginY) / k)
                .opacity(Double(pose.shadowAlpha))
            // 8 Tonarm
            Image(decorative: L.arm, scale: k)
                .frame(width: armW, height: armH)
                .scaleEffect(CGFloat(pose.armScale), anchor: pivot)
                .rotationEffect(.degrees(Double(pose.angleDegrees)), anchor: pivot)
                .offset(x: CGFloat(pose.armOriginX) / k, y: CGFloat(pose.armOriginY) / k)
        }
        .frame(width: side, height: side, alignment: .topLeading)
    }

    @ViewBuilder
    private func labelView(_ L: VinylLayers, labelPt: CGFloat) -> some View {
        if artwork.loading && label == nil {
            ZStack {
                Circle().fill(Color(argb: 0xFF1A1718))
                Circle().stroke(Color(argb: 0xFF2A2526), lineWidth: 0.012 * labelPt).frame(width: 0.92 * labelPt, height: 0.92 * labelPt)
            }
        } else if let label {
            Image(decorative: label, scale: CGFloat(L.labelPx) / labelPt)
        } else if artwork.image == nil {
            ZStack(alignment: .bottom) {
                Image(decorative: L.fallbackLabel, scale: CGFloat(L.labelPx) / labelPt)
                let base = min(14, max(7, labelPt * 0.085))
                VStack(spacing: 0) {
                    Text(player.current?.displayTitle ?? "Musikbibliothek")
                        .font(Typo.inter(base, .semibold))
                        .foregroundColor(Color(argb: 0xFFF3E6DE))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    if let a = player.current?.artistText {
                        Text(a)
                            .font(Typo.inter(base * 0.8, .medium))
                            .foregroundColor(Color(argb: 0xFFF3E6DE).opacity(0.8))
                            .lineLimit(1)
                    }
                }
                .frame(width: labelPt * 0.62)
                .padding(.bottom, labelPt * 0.04)
            }
        }
    }
}

/// Randabschattung und eingepresste Ringe des Labels (Spec 2.4, Ebene 4).
private struct PaperOverlay: View {
    let radius: CGFloat

    var body: some View {
        let r = radius
        ZStack {
            Circle().fill(RadialGradient(stops: [
                .init(color: .clear, location: 0.80),
                .init(color: Color.black.opacity(0.32), location: 0.97),
                .init(color: Color.black.opacity(0.55), location: 1.0),
            ], center: .center, startRadius: 0, endRadius: r))
            Circle().stroke(Color.white.opacity(0.10), lineWidth: 0.012 * r).frame(width: 1.8 * r, height: 1.8 * r)
            Circle().stroke(Color.black.opacity(0.18), lineWidth: 0.01 * r).frame(width: 1.83 * r, height: 1.83 * r)
        }
        .allowsHitTesting(false)
    }
}

/// Betriebsleuchte 33/45 (Spec 2.6).
private struct PowerLED: View {
    let size: CGFloat
    let speed: Float
    let playing: Bool

    var body: some View {
        let i = speed > 1.17 ? 1 : 0
        let b = TurntableGeometry.SPEED_BUTTONS
        let cx = CGFloat(b[2 * i]) * size
        let cy = (CGFloat(b[2 * i + 1]) - 0.032) * size
        let r = 0.0042 * size
        let glow: Double = playing ? 1 : 0.25
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(argb: 0xFFFF7D98).opacity(0.55 * glow), .clear], center: .center, startRadius: 0, endRadius: 4.5 * r))
                .frame(width: 9 * r, height: 9 * r)
            Circle()
                .fill(Color(argb: 0xFFFF7D98).opacity(0.35 + 0.65 * glow))
                .frame(width: 2 * r, height: 2 * r)
        }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.4), value: playing)
        .position(x: cx, y: cy)
        .frame(width: size, height: size, alignment: .topLeading)
    }
}

/// Liest die Wiedergabeposition (nur dieser Teil wird im 250-ms-Takt neu gezeichnet).
struct ProgressObserver<Content: View>: View {
    @ObservedObject var clock: PlaybackClock
    @ViewBuilder var content: (Int64, Int64) -> Content

    var body: some View { content(clock.positionMs, clock.durationMs) }
}

/// Classic Music – großes Cover auf Farbverlauf aus den Cover-Farben (Spec 3).
struct ClassicHero: View {
    @EnvironmentObject private var player: PlayerService
    let side: CGFloat
    @ObservedObject var artwork: NowPlayingArtwork
    var still: Bool = false

    var body: some View {
        let playing = still || player.isPlaying
        let inner = side * 0.94
        ZStack {
            ArtworkBox(image: artwork.image, category: GenreStyle.category(player.current?.genres.first),
                       cornerRadius: Radius.artworkLarge, iconFraction: 0.4, loading: artwork.loading)
                .frame(width: inner, height: inner)
                .shadow(color: Color(argb: artwork.palette.glow).opacity(0.5), radius: 17)
                .shadow(color: Color.black.opacity(0.55), radius: 17, y: 17)
                .id(artwork.key ?? "-")
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)), removal: .opacity))
        }
        .scaleEffect(playing ? 1 : 0.86)
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.52), value: playing)
        .animation(.easeOut(duration: 0.42), value: artwork.key)
        .frame(width: side, height: side)
        .accessibilityLabel("Albumcover")
    }
}
