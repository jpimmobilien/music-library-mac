import SwiftUI
import MLRender

/// Geglättete Pegel für die Klangvisualisierung (höchstens 30 Aktualisierungen/s, Spec 6).
final class VisualizerState: ObservableObject {
    var smoothing = VisualizerSmoothing()
    private var lastStep = Date.distantPast

    func step(_ now: Date, meter: LevelMeter) {
        guard now.timeIntervalSince(lastStep) >= 0.033 else { return }
        lastStep = now
        _ = smoothing.step(raw: meter.take())
    }

    /// Ist noch etwas zu sehen (Pegel klingen nach der Pause aus)?
    var hasEnergy: Bool {
        smoothing.left > 0.01 || smoothing.right > 0.01 || smoothing.bands.contains { $0 > 0.01 }
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

/// Frequenzbalken unter dem Mittelstück (Spec 6, `SpectrumBars`).
struct SpectrumBars: View {
    @EnvironmentObject private var player: PlayerService
    @StateObject private var state = VisualizerState()
    @State private var idleTick = 0
    let color: Color

    var body: some View {
        let running = player.isPlaying || state.hasEnergy
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { ctx in
            let _ = idleTick
            let _ = state.step(ctx.date, meter: player.engine.levels)
            let active = player.isPlaying || state.hasEnergy
            Canvas { g, size in
                let n = 16
                let gap = 0.012 * size.width
                let bw = (size.width - CGFloat(n - 1) * gap) / CGFloat(n)
                for i in 0..<n {
                    let v = CGFloat(state.smoothing.bands[i])
                    let x = CGFloat(i) * (bw + gap)
                    g.fill(Path(roundedRect: CGRect(x: x, y: size.height - bw, width: bw, height: bw), cornerRadius: bw / 2), with: .color(color.opacity(0.18)))
                    let h = max(size.height * (0.06 + 0.94 * v * v), bw)
                    g.fill(Path(roundedRect: CGRect(x: x, y: size.height - h, width: bw, height: h), cornerRadius: bw / 2), with: .color(color.opacity(0.35 + 0.55 * Double(v))))
                }
            }
            .onChange(of: active) { a in if !a { DispatchQueue.main.async { idleTick &+= 1 } } }
        }
        .accessibilityHidden(true)
    }
}

/// Pegelanzeigen der Kassette (Spec 6, `VuMeters`).
struct VuMeters: View {
    @EnvironmentObject private var player: PlayerService
    @StateObject private var state = VisualizerState()
    @State private var idleTick = 0

    var body: some View {
        let running = player.isPlaying || state.hasEnergy
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { ctx in
            let _ = idleTick
            let _ = state.step(ctx.date, meter: player.engine.levels)
            let active = player.isPlaying || state.hasEnergy
            Canvas { g, size in
                let segments = 14
                let rh = 0.36 * size.height
                let gap = 0.012 * size.width
                let sw = (size.width - CGFloat(segments - 1) * gap) / CGFloat(segments)
                for (row, value) in [(0, state.smoothing.left), (1, state.smoothing.right)] {
                    let y = row == 0 ? 0 : size.height - rh
                    let lit = Int(value * Float(segments))
                    for s in 0..<segments {
                        let base = s >= 11 ? Color(argb: 0xFFF3B37A) : Color(argb: 0xFFFF9DB2)
                        g.fill(Path(roundedRect: CGRect(x: CGFloat(s) * (sw + gap), y: y, width: sw, height: rh), cornerRadius: rh / 3),
                               with: .color(base.opacity(s < lit ? 0.9 : 0.12)))
                    }
                }
            }
            .onChange(of: active) { a in if !a { DispatchQueue.main.async { idleTick &+= 1 } } }
        }
        .accessibilityHidden(true)
    }
}
