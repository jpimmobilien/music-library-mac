import SwiftUI
import MLRender

// MARK: - Pegel (v2.1)

/// Geglättete Pegel der Klangvisualisierung (Spec 6): 16 Bänder + links/rechts, je 0…1.
///
/// Die Glättung rechnet mit der vergangenen Zeit statt je Bild: gleich weich bei 30 Bildern/s, bei
/// ausgelassenen Bildern und in der schnelleren Bildschleife der Tonbandmaschine. Der Analysator wird dabei
/// höchstens ≈ 38-mal je Sekunde abgefragt (30 Bilder/s mit Zeitschwankung – früher fiel bei einem Abstand
/// knapp unter 33 ms jedes zweite Bild aus, die Balken ruckelten). Anstieg schnell (≈ 40 ms), Abfall ruhig
/// (≈ 0,22 s) – dieselbe Wirkung wie `VisualizerSmoothing` bei 30 Schritten je Sekunde.
///
/// Ohne Wiedergabe klingen alle Werte aus; danach meldet `resting`, dass die Bildschleife ruhen darf.
final class VisualizerState: ObservableObject {
    static let bandCount = 16
    private(set) var bands = [Float](repeating: 0, count: VisualizerState.bandCount)
    private(set) var left: Float = 0
    private(set) var right: Float = 0
    /// Nichts mehr zu sehen und keine Wiedergabe → die Bildschleife darf anhalten. Veröffentlicht, damit die
    /// Ansicht ihre `TimelineView` anhält (und beim nächsten Abspielen wieder startet).
    @Published private(set) var resting = true
    private var lastStep: Date?
    private var restingTarget = true

    private static let riseTau = 0.042
    private static let fallTau = 0.22
    private static let levelRiseTau = 0.048
    private static let levelFallTau = 0.26

    /// Ein Bildschritt aus der Bildschleife. Ohne Wiedergabe werden keine Pegel mehr gelesen (alles klingt aus).
    func step(_ now: Date, meter: LevelMeter, playing: Bool) {
        let dt: Double
        if let last = lastStep {
            let gap = now.timeIntervalSince(last)
            if gap >= 0 && gap < 0.026 { return }
            dt = min(max(gap, 0), 0.1)
        } else {
            dt = 1.0 / 30
        }
        lastStep = now
        apply(raw: playing ? meter.take() : nil, dt: dt)
        setResting(!playing && energy < 0.012)
    }

    /// Größter aktueller Wert (0…1).
    var energy: Float { max(bands.max() ?? 0, left, right) }

    /// Ist noch etwas zu sehen?
    var hasEnergy: Bool { energy >= 0.012 }

    private func apply(raw: [Float]?, dt: Double) {
        let up = Float(1 - exp(-dt / Self.riseTau))
        let down = Float(1 - exp(-dt / Self.fallTau))
        for i in 0..<Self.bandCount {
            let target = Self.clean(raw, i)
            let cur = bands[i]
            var next = cur + (target - cur) * (target > cur ? up : down)
            if next < 0.0005 { next = 0 }
            bands[i] = next
        }
        let levelUp = Float(1 - exp(-dt / Self.levelRiseTau))
        let levelDown = Float(1 - exp(-dt / Self.levelFallTau))
        let tl = Self.clean(raw, Self.bandCount)
        let tr = Self.clean(raw, Self.bandCount + 1)
        left += (tl - left) * (tl > left ? levelUp : levelDown)
        right += (tr - right) * (tr > right ? levelUp : levelDown)
        if left < 0.0005 { left = 0 }
        if right < 0.0005 { right = 0 }
    }

    /// Rohwert begrenzt auf 0…1 (fehlend oder ungültig → 0) – nichts ragt über die Anzeige hinaus.
    private static func clean(_ raw: [Float]?, _ i: Int) -> Float {
        guard let raw, raw.indices.contains(i) else { return 0 }
        let v = raw[i]
        guard v.isFinite else { return 0 }
        return min(max(v, 0), 1)
    }

    /// `resting` nie während der Berechnung einer Ansicht veröffentlichen – nachgelagert und nur bei Änderung.
    private func setResting(_ value: Bool) {
        guard value != restingTarget else { return }
        restingTarget = value
        DispatchQueue.main.async { [weak self] in
            guard let self, self.restingTarget == value, self.resting != value else { return }
            self.resting = value
        }
    }
}

/// Fortlaufende Zeit für ruhige Animationen (Lichtfelder, „Atmen“): läuft nur, solange `running` gilt,
/// und springt beim Fortsetzen nicht.
final class PhaseClock: ObservableObject {
    private(set) var t: Double = 0
    private var last: Date?

    func advance(_ now: Date, running: Bool) -> Double {
        if running, let last {
            t += min(0.1, max(0, now.timeIntervalSince(last)))
        }
        last = running ? now : nil
        return t
    }
}

// MARK: - Anmeldung beim Player

/// Meldet eine sichtbare Pegelanzeige beim Player an (`retainVisualizer`/`releaseVisualizer`, immer paarweise).
/// Die Analyse rechnet nur, solange die Klangvisualisierung eingeschaltet ist und mindestens eine Anzeige
/// sichtbar ist – unabhängig davon, in welcher Reihenfolge SwiftUI Ansichten ein- und ausblendet.
private struct VisualizerConsumer: ViewModifier {
    @EnvironmentObject private var player: PlayerService
    let active: Bool
    @State private var retained = false

    func body(content: Content) -> some View {
        content
            .onAppear { setRetained(active) }
            .onDisappear { setRetained(false) }
            .onChange(of: active) { on in setRetained(on) }
    }

    private func setRetained(_ on: Bool) {
        guard on != retained else { return }
        retained = on
        if on { player.retainVisualizer() } else { player.releaseVisualizer() }
    }
}

extension View {
    /// Diese Ansicht zeigt (bei `active`) echte Pegel – Analyse für die Dauer der Sichtbarkeit anfordern.
    func visualizerConsumer(_ active: Bool = true) -> some View {
        modifier(VisualizerConsumer(active: active))
    }
}

// MARK: - Frequenzbalken

/// Frequenzbalken unter dem Mittelstück (Spec 6, `SpectrumBars`).
///
/// v2.1: schmale Balken, deren Anzahl sich nach der Breite richtet (16 Bänder werden weich auf die Balken
/// verteilt); in Ruhe eine feine Grundlinie statt runder Punkte. Höchstens 30 Bilder/s, nur während der
/// Wiedergabe bzw. bis alles ausgeklungen ist – danach steht die Bildschleife still.
struct SpectrumBars: View {
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    @StateObject private var state = VisualizerState()
    let color: Color

    var body: some View {
        let playing = player.isPlaying
        let running = playing || !state.resting
        let baseline = colors.textPrimary.opacity(colors.dark ? 0.16 : 0.12)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { ctx in
            let _ = state.step(ctx.date, meter: player.engine.levels, playing: playing)
            let bands = state.bands
            Canvas { g, size in
                SpectrumPainter.draw(g, size: size, bands: bands, color: color, baseline: baseline)
            }
        }
        .visualizerConsumer()
        .accessibilityHidden(true)
    }
}

/// Zeichnet die Frequenzbalken (ohne Bezug zur Ansicht – darf im Canvas laufen).
enum SpectrumPainter {
    /// Balkenanzahl für eine Breite: etwa ein Balken je 7 pt, 16 … 64.
    static func barCount(width: CGFloat) -> Int {
        min(64, max(16, Int(width / 7)))
    }

    static func draw(_ g: GraphicsContext, size: CGSize, bands: [Float], color: Color, baseline: Color) {
        guard size.width > 8, size.height > 4, !bands.isEmpty else { return }
        let n = barCount(width: size.width)
        let gapRatio: CGFloat = 0.7
        let bw = size.width / (CGFloat(n) + gapRatio * CGFloat(n - 1))
        let gap = bw * gapRatio
        let lineH: CGFloat = 1.5
        let top = size.height - lineH - 1
        // Ruhende Grundlinie (sichtbar auch ohne Pegel)
        g.fill(Path(roundedRect: CGRect(x: 0, y: size.height - lineH, width: size.width, height: lineH), cornerRadius: lineH / 2),
               with: .color(baseline))
        for i in 0..<n {
            let v = Double(value(at: i, of: n, bands))
            guard v > 0.004 else { continue }
            let shaped = pow(v, 0.8)
            let h = max(1, top * CGFloat(shaped))
            let rect = CGRect(x: CGFloat(i) * (bw + gap), y: size.height - lineH - h, width: bw, height: h + lineH)
            g.fill(Path(roundedRect: rect, cornerRadius: min(bw / 2, 2.5)), with: .color(color.opacity(0.38 + 0.57 * shaped)))
        }
    }

    /// Wert eines Balkens: Bänder linear verteilt, mit leichtem Ausgleich zum Nachbarband (weicher Verlauf).
    static func value(at i: Int, of n: Int, _ bands: [Float]) -> Float {
        let last = bands.count - 1
        guard last > 0, n > 1 else { return bands.first ?? 0 }
        let pos = Float(i) / Float(n - 1) * Float(last)
        let lo = min(last, Int(pos))
        let hi = min(last, lo + 1)
        let f = pos - Float(lo)
        let smooth = f * f * (3 - 2 * f)
        let v = bands[lo] * (1 - smooth) + bands[hi] * smooth
        return min(max(v, 0), 1)
    }
}

// MARK: - Pegelanzeige der Kassette

/// Pegelanzeigen der Kassette (Spec 6, `VuMeters`): je Kanal eine Segmentreihe, ab Segment 12 warm.
struct VuMeters: View {
    @EnvironmentObject private var player: PlayerService
    @StateObject private var state = VisualizerState()

    var body: some View {
        let playing = player.isPlaying
        let running = playing || !state.resting
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { ctx in
            let _ = state.step(ctx.date, meter: player.engine.levels, playing: playing)
            let levels = (state.left, state.right)
            Canvas { g, size in
                let segments = 14
                let rh = 0.36 * size.height
                let gap = 0.012 * size.width
                let sw = (size.width - CGFloat(segments - 1) * gap) / CGFloat(segments)
                for (row, value) in [(0, levels.0), (1, levels.1)] {
                    let y = row == 0 ? 0 : size.height - rh
                    // Anteil des letzten Segments weich einblenden (kein Springen zwischen zwei Segmenten)
                    let exact = Double(min(max(value, 0), 1)) * Double(segments)
                    for s in 0..<segments {
                        let base = s >= 11 ? Color(argb: 0xFFF3B37A) : Color(argb: 0xFFFF9DB2)
                        let lit = min(1, max(0, exact - Double(s)))
                        g.fill(Path(roundedRect: CGRect(x: CGFloat(s) * (sw + gap), y: y, width: sw, height: rh), cornerRadius: rh / 3),
                               with: .color(base.opacity(0.12 + 0.78 * lit)))
                    }
                }
            }
        }
        .visualizerConsumer()
        .accessibilityHidden(true)
    }
}
