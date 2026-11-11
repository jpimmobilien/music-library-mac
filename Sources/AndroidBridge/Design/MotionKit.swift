import SwiftUI
import AppKit

// MARK: - Motion-System 5.2
//
// Alle Bausteine hängen an echten Zuständen (Verbindung, Übertragungsfortschritt, Geschwindigkeit,
// Ergebnis). Nichts läuft auf Vorrat: Zeitgesteuerte Ansichten pausieren, sobald nichts passiert,
// ohne Animationen in den Einstellungen oder bei „Bewegung reduzieren“ (macOS).

enum MotionPolicy {
    /// Bewegung erlaubt? (App-Einstellung, macOS „Bewegung reduzieren“, Bildschirmfoto-Modus)
    static func allowed(_ animations: Bool) -> Bool {
        animations && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !SnapshotMode.isActive
    }
}

/// Einmaliger, dezenter Lichtimpuls, wenn eine Verbindung zustande kommt.
struct ConnectionPulse: View {
    var connected: Bool
    var tint: Color = Palette.accent
    @Environment(\.animationsEnabled) private var animations
    @State private var progress: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let d = max(geo.size.width, geo.size.height)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [tint.opacity(0.28), tint.opacity(0.0)], center: .center,
                                         startRadius: 0, endRadius: d * 0.5))
                    .scaleEffect(0.35 + progress * 0.9)
                    .opacity(Double(1 - progress))
                Circle()
                    .strokeBorder(tint.opacity(0.45), lineWidth: 1.5)
                    .scaleEffect(0.2 + progress * 0.85)
                    .opacity(Double(1 - progress) * 0.9)
            }
            .frame(width: d, height: d)
            .position(x: geo.size.width / 2, y: geo.size.height * 0.55)
        }
        .allowsHitTesting(false)
        .onChange(of: connected) { now in
            guard now, MotionPolicy.allowed(animations) else { return }
            progress = 0
            withAnimation(.easeOut(duration: 1.25)) { progress = 1 }
        }
    }
}

/// Auftritt der Geräte: aus der Tiefe nach vorn (beim Trennen umgekehrt).
extension AnyTransition {
    static var deviceStage: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.94)).combined(with: .offset(y: 26)),
                    removal: .opacity.combined(with: .scale(scale: 0.97)).combined(with: .offset(y: -12)))
    }
}

/// Fortschrittsbalken einer Übertragung: echte Füllung, darin wandern Lichtpunkte in Übertragungsrichtung.
/// Tempo der Punkte folgt der gemessenen Geschwindigkeit; ohne Datenfluss stehen sie still.
struct FlowProgressBar: View {
    let fraction: Double
    var tint: Color = Palette.accent
    var toMac = true
    var bytesPerSecond: Double = 0
    var flowing = false
    var height: CGFloat = 7
    @Environment(\.animationsEnabled) private var animations

    var body: some View {
        let animate = flowing && bytesPerSecond > 0 && MotionPolicy.allowed(animations)
        GeometryReader { geo in
            let w = geo.size.width
            let fillW = max(height, w * CGFloat(min(max(fraction, 0), 1)))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.8), tint], startPoint: .leading, endPoint: .trailing))
                    .overlay(
                        Capsule().fill(LinearGradient(stops: [.init(color: .white.opacity(0.45), location: 0),
                                                              .init(color: .white.opacity(0), location: 0.6)],
                                                      startPoint: .top, endPoint: .bottom))
                            .padding(.horizontal, height * 0.3).padding(.top, 1).padding(.bottom, height * 0.45)
                    )
                    .frame(width: fillW)
                    .animation(.easeOut(duration: 0.35), value: fraction)
                if animate {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                        Canvas { c, size in
                            let t = ctx.date.timeIntervalSinceReferenceDate
                            // 0,35 … 1,2 Durchläufe pro Sekunde je nach Geschwindigkeit (logarithmisch)
                            let speed = 0.35 + min(0.85, max(0, log10(max(bytesPerSecond, 1)) - 4) * 0.28)
                            let count = 5
                            for i in 0..<count {
                                var u = (t * speed + Double(i) / Double(count)).truncatingRemainder(dividingBy: 1)
                                if !toMac { u = 1 - u }
                                let x = CGFloat(u) * fillW
                                let fade = sin(Double.pi * u)
                                let r = size.height * 0.36
                                c.fill(Path(ellipseIn: CGRect(x: x - r * 2.2, y: size.height / 2 - r, width: r * 4.4, height: r * 2)),
                                       with: .color(.white.opacity(0.55 * fade)))
                            }
                        }
                    }
                    .frame(width: fillW)
                    .clipShape(Capsule())
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Fortschritt")
        .accessibilityValue("\(Int(fraction * 100)) Prozent")
    }
}

/// Live-Verlauf der gemessenen Übertragungsgeschwindigkeit (letzte ~40 Messungen).
struct SpeedSparkline: View {
    let samples: [Double]
    var tint: Color = Palette.accent

    var body: some View {
        GeometryReader { geo in
            let maxV = max(samples.max() ?? 1, 1)
            let n = max(samples.count - 1, 1)
            let pts = samples.enumerated().map { i, v in
                CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(n), y: geo.size.height * (1 - CGFloat(v / maxV) * 0.9))
            }
            ZStack {
                if pts.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: geo.size.height))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: pts[0])
                        pts.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Kurzes Schütteln (z. B. bei einer fehlgeschlagenen Übertragung). `trigger` hochzählen.
struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 5
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        // bei ganzen Zahlen in Ruhe (sin(k·6π) = 0), dazwischen drei kurze Ausschläge
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * 6), y: 0))
    }
}

/// Erfolgs-Lichtring, der einmal aufgeht (z. B. Übertragung abgeschlossen).
struct SuccessBurst: View {
    var trigger: Bool
    var tint: Color = Palette.success
    @Environment(\.animationsEnabled) private var animations
    @State private var progress: CGFloat = 1

    var body: some View {
        Circle()
            .strokeBorder(tint, lineWidth: 2)
            .scaleEffect(1 + progress * 0.9)
            .opacity(Double(1 - progress))
            .allowsHitTesting(false)
            .onChange(of: trigger) { now in
                guard now, MotionPolicy.allowed(animations) else { return }
                progress = 0
                withAnimation(.easeOut(duration: 0.8)) { progress = 1 }
            }
    }
}

/// Ruhiger Ladeschimmer für Vorschaubilder, die noch geladen werden.
struct LoadingShimmer: ViewModifier {
    var active: Bool
    @Environment(\.animationsEnabled) private var animations
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content.overlay {
            if active && MotionPolicy.allowed(animations) {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, Color.white.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.3)
                }
                .clipped()
                .allowsHitTesting(false)
                .onAppear {
                    phase = -1
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
                }
            }
        }
    }
}

extension View {
    func loadingShimmer(_ active: Bool) -> some View { modifier(LoadingShimmer(active: active)) }

    /// Zahlen zählen weich hoch/runter (macOS 14+), sonst unverändert.
    @ViewBuilder func numericTransition() -> some View {
        if #available(macOS 14.0, *) {
            contentTransition(.numericText())
        } else {
            self
        }
    }
}

/// Scan-Lichtbogen um einen Fortschrittsring, solange ein Scan wirklich läuft.
struct ScanSweep: View {
    var active: Bool
    var tint: Color = Palette.accent
    @Environment(\.animationsEnabled) private var animations

    var body: some View {
        let animate = active && MotionPolicy.allowed(animations)
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animate)) { ctx in
            let angle = animate ? ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4 * 360 : 0
            Circle()
                .stroke(AngularGradient(stops: [.init(color: tint.opacity(0), location: 0),
                                                .init(color: tint.opacity(0.0), location: 0.7),
                                                .init(color: tint.opacity(0.55), location: 1)],
                                        center: .center),
                        lineWidth: 14)
                .blur(radius: 6)
                .rotationEffect(.degrees(angle))
                .opacity(animate ? 1 : 0)
        }
        .allowsHitTesting(false)
    }
}
