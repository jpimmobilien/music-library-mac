import SwiftUI
import AppKit
import QuartzCore
import AetherCore

// =============================================================================================
// ORBIT – „Spatial Liquid Glass“: Farben, Auftakt, lebendiger Hintergrund, Glasreflexion, magnetisches Schweben,
// leere Zustände, flüssiger Fortschritt und ruhige Zahlenwechsel.
//
// Leistungsregeln (gemessen im Selbsttest, siehe docs/ORBIT.md):
//  - Dauerbewegung nur über Core Animation (läuft im Render-Server, nicht im Hauptthread) und gedrosselt
//    (preferredFrameRateRange ≤ 12 Bilder/s), nie über SwiftUI-Zeitgeber.
//  - Zeigerverfolgung schreibt in ein eigenes Objekt; neu gezeichnet wird nur die Reflexionsebene, nicht die Karte.
//  - Keine Canvas-, Metal- oder drawingGroup-Effekte (Intel-Macs ohne Metal-Gerät in VMs, siehe GRENZEN.md).
// =============================================================================================

// MARK: - Farben

extension AetherTheme {
    /// System (Blau)
    var arcticBlue: Color { Color(isDark ? RGBA(0x5AA9FF) : RGBA(0x0B6BEA)) }
    /// Datenströme (Cyan)
    var electricCyan: Color { Color(isDark ? RGBA(0x2EE6F6) : RGBA(0x0598B3)) }
    /// Intelligente Funktionen, Auswertungen (Violett)
    var softViolet: Color { Color(isDark ? RGBA(0xA48CFF) : RGBA(0x6E56E8)) }
    var sapphire: Color { Color(isDark ? RGBA(0x8F9BFF) : RGBA(0x2446C8)) }
    var deepOcean: Color { Color(OrbitPalette.deepOcean) }
    var pearlWhite: Color { Color(OrbitPalette.pearlWhite) }

    /// Glanzlicht für Reflexionen (auf hellem Glas weißer, auf dunklem zurückhaltender).
    var reflection: Color { isDark ? Color.white.opacity(0.10) : Color.white.opacity(0.65) }
    var reflectionEdge: Color { isDark ? Color.white.opacity(0.40) : Color.white.opacity(0.95) }
}

// MARK: - ORBIT-Zeichen (Kern mit zwei Umlaufbahnen) – Auftakt und leere Zustände

struct OrbitMark: View {
    @Environment(\.aether) private var theme
    var size: CGFloat = 96
    var symbol: String? = nil
    var muted = false

    var body: some View {
        let core = size * 0.34
        ZStack {
            Ellipse()
                .stroke(ringGradient(1), lineWidth: max(1, size * 0.018))
                .frame(width: size, height: size * 0.42)
                .rotationEffect(.degrees(-24))
            Ellipse()
                .stroke(ringGradient(0.7), lineWidth: max(1, size * 0.014))
                .frame(width: size * 0.84, height: size * 0.34)
                .rotationEffect(.degrees(38))
            Circle()
                .fill(LinearGradient(colors: muted ? [theme.textTertiary.opacity(0.35), theme.textTertiary.opacity(0.2)]
                                                  : [theme.electricCyan, theme.arcticBlue, theme.sapphire],
                                     startPoint: .topTrailing, endPoint: .bottomLeading))
                .frame(width: core, height: core)
                .overlay(Circle().strokeBorder(Color.white.opacity(theme.isDark ? 0.25 : 0.6), lineWidth: 1))
                .shadow(color: muted ? .clear : theme.arcticBlue.opacity(0.45), radius: size * 0.08)
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: core * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Circle()
                .fill(muted ? theme.textTertiary : theme.electricCyan)
                .frame(width: size * 0.07, height: size * 0.07)
                .offset(x: size * 0.45, y: -size * 0.12)
        }
        .frame(width: size, height: size * 0.62)
        .accessibilityHidden(true)
    }

    private func ringGradient(_ alpha: Double) -> LinearGradient {
        LinearGradient(colors: muted ? [theme.textTertiary.opacity(0.5 * alpha), theme.textTertiary.opacity(0.15 * alpha)]
                                     : [theme.electricCyan.opacity(0.9 * alpha), theme.arcticBlue.opacity(0.5 * alpha),
                                        theme.softViolet.opacity(0.6 * alpha)],
                       startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Auftakt (Ambient Intro)

/// Kurzer Auftakt beim Start: ≈ 0,9 s, liegt über dem bereits gezeichneten Inhalt und nimmt keine Eingaben an –
/// kein künstlicher Ladebildschirm. Mit „Bewegung reduzieren“ nur eine kurze Überblendung, im Profil „Minimal“
/// und mit „Animationen aus“ gar nicht. Einmal pro Programmstart.
struct OrbitIntroOverlay: View {
    @Environment(\.aether) private var theme
    /// Pro Programmstart einmal (weitere Fenster ohne Auftakt).
    @MainActor static var played = false
    let onFinished: () -> Void
    @State private var markVisible = false
    @State private var coverVisible = true

    var body: some View {
        let effects = theme.effects
        Group {
            if effects.ambientIntro {
                ZStack {
                    LinearGradient(colors: [theme.backgroundTop, theme.backgroundBottom], startPoint: .top, endPoint: .bottom)
                    if !effects.introCrossfadeOnly {
                        VStack(spacing: 18) {
                            OrbitMark(size: 120)
                            Text("ORBIT")
                                .font(.system(size: 22, weight: .semibold))
                                .tracking(9)
                                .foregroundStyle(theme.textPrimary)
                        }
                        .scaleEffect(markVisible ? 1 : 0.94)
                        .opacity(markVisible ? 1 : 0)
                    }
                }
                .opacity(coverVisible ? 1 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .task { await run(crossfadeOnly: effects.introCrossfadeOnly) }
            } else {
                Color.clear.onAppear { finish() }
            }
        }
    }

    private func run(crossfadeOnly: Bool) async {
        if crossfadeOnly {
            withAnimation(.easeOut(duration: 0.22)) { coverVisible = false }
            try? await Task.sleep(nanoseconds: 240_000_000)
        } else {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.38)) { markVisible = true }
            try? await Task.sleep(nanoseconds: 420_000_000)
            withAnimation(.easeInOut(duration: 0.42)) { coverVisible = false }
            try? await Task.sleep(nanoseconds: 450_000_000)
        }
        finish()
    }

    private func finish() {
        Self.played = true
        onFinished()
    }
}

// MARK: - Lebendiger Hintergrund (Living Glass Background)

/// Lichtfelder des Fensterhintergrunds als Core-Animation-Ebenen.
/// - „Ausgewogen“: ruhend; beim Bereichswechsel gleiten sie in 1,4 s an eine neue Stelle (räumliche Orientierung).
/// - „Immersiv“: zusätzlich eine sehr langsame Drift (Umlauf 50–70 s) mit höchstens 12 Bildern pro Sekunde.
/// Keine Partikel, keine Echtzeit-Unschärfe, kein Hauptthread-Zeitgeber.
struct AmbientLightsView: NSViewRepresentable {
    struct Light: Equatable {
        var color: RGBA
        var center: UnitPoint
        var radius: CGFloat // Anteil der größeren Fensterseite
    }

    var lights: [Light]
    var shift: CGPoint // Verschiebung als Anteil der Fenstergröße (Bereichswechsel)
    var living: Bool
    var animateShift: Bool

    func makeNSView(context: Context) -> AmbientLightsLayerView { AmbientLightsLayerView() }

    func updateNSView(_ view: AmbientLightsLayerView, context: Context) {
        view.update(lights: lights, shift: shift, living: living, animateShift: animateShift)
    }
}

final class AmbientLightsLayerView: NSView {
    private let container = CALayer()
    private var gradients: [CAGradientLayer] = []
    private var lights: [AmbientLightsView.Light] = []
    private var shift: CGPoint = .zero
    private var living = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let root = CALayer()
        layer = root
        wantsLayer = true
        root.addSublayer(container)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(lights newLights: [AmbientLightsView.Light], shift newShift: CGPoint, living newLiving: Bool, animateShift: Bool) {
        if newLights != lights {
            lights = newLights
            rebuild()
        }
        if newShift != shift {
            shift = newShift
            CATransaction.begin()
            if animateShift {
                CATransaction.setAnimationDuration(1.4)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1))
            } else {
                CATransaction.setDisableActions(true)
            }
            container.position = shiftedPosition
            CATransaction.commit()
        }
        if newLiving != living {
            living = newLiving
            applyDrift()
        }
    }

    private var shiftedPosition: CGPoint {
        CGPoint(x: bounds.midX + shift.x * bounds.width, y: bounds.midY - shift.y * bounds.height)
    }

    override func layout() {
        super.layout()
        layoutLights()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutLights()
    }

    private func rebuild() {
        gradients.forEach { $0.removeFromSuperlayer() }
        gradients = lights.map { light in
            let g = CAGradientLayer()
            g.type = .radial
            g.startPoint = CGPoint(x: 0.5, y: 0.5)
            g.endPoint = CGPoint(x: 1, y: 1)
            let c = NSColor(srgbRed: light.color.red, green: light.color.green, blue: light.color.blue, alpha: light.color.alpha)
            g.colors = [c.cgColor, c.withAlphaComponent(light.color.alpha * 0.45).cgColor, c.withAlphaComponent(0).cgColor]
            g.locations = [0, 0.45, 1]
            container.addSublayer(g)
            return g
        }
        layoutLights()
        applyDrift()
    }

    private func layoutLights() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.bounds = bounds
        container.position = shiftedPosition
        let span = max(bounds.width, bounds.height)
        for (g, light) in zip(gradients, lights) {
            let r = span * light.radius
            g.bounds = CGRect(x: 0, y: 0, width: r * 2, height: r * 2)
            g.position = CGPoint(x: light.center.x * bounds.width, y: (1 - light.center.y) * bounds.height)
        }
        CATransaction.commit()
    }

    /// Sehr langsame, additive Drift entlang einer Ellipse (Immersiv). Gedrosselt auf höchstens 12 Bilder/s.
    private func applyDrift() {
        for (index, g) in gradients.enumerated() {
            g.removeAnimation(forKey: "orbit.drift")
            guard living else { continue }
            let span = max(bounds.width, bounds.height, 600)
            let rx = span * (0.05 + 0.015 * CGFloat(index))
            let ry = span * (0.035 + 0.01 * CGFloat(index))
            let path = CGMutablePath()
            path.addEllipse(in: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
            let drift = CAKeyframeAnimation(keyPath: "position")
            drift.path = path
            drift.isAdditive = true
            drift.calculationMode = .paced
            drift.duration = 52 + Double(index) * 9
            drift.repeatCount = .infinity
            drift.beginTime = CACurrentMediaTime() - Double(index) * 13
            if #available(macOS 12.0, *) {
                drift.preferredFrameRateRange = CAFrameRateRange(minimum: 4, maximum: 12, preferred: 10)
            }
            g.add(drift, forKey: "orbit.drift")
        }
    }
}

// MARK: - Glasreflexion und magnetisches Schweben

/// Zeigerposition über einem Element. Bewusst kein Zustand der Karte selbst: Nur die Reflexionsebene beobachtet sie.
final class PointerTracker: ObservableObject {
    @Published var location: CGPoint?
}

/// Weiche Reflexion auf Glasflächen, die dem Zeiger folgt – plus Lichtkante in Zeigernähe.
private struct ReflectionLayer: View {
    @ObservedObject var tracker: PointerTracker
    @Environment(\.aether) private var theme
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { geo in
            if let p = tracker.location, geo.size.width > 0, geo.size.height > 0 {
                let center = UnitPoint(x: p.x / geo.size.width, y: p.y / geo.size.height)
                let reach = max(geo.size.width, geo.size.height) * 0.6
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                ZStack {
                    shape.fill(RadialGradient(colors: [theme.reflection, theme.reflection.opacity(0)],
                                              center: center, startRadius: 0, endRadius: reach))
                    shape.strokeBorder(RadialGradient(colors: [theme.reflectionEdge, theme.reflectionEdge.opacity(0)],
                                                      center: center, startRadius: 0, endRadius: reach * 0.7), lineWidth: 1)
                }
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.25), value: tracker.location == nil)
    }
}

/// Verschiebt den Inhalt um höchstens `strength` Punkte zum Zeiger hin (nur Profil „Immersiv“).
private struct MagneticOffset<Content: View>: View {
    @ObservedObject var tracker: PointerTracker
    let size: CGSize
    let strength: CGFloat
    let content: Content

    var body: some View {
        let offset: CGSize = {
            guard let p = tracker.location, size.width > 0, size.height > 0 else { return .zero }
            let dx = (p.x / size.width - 0.5) * 2
            let dy = (p.y / size.height - 0.5) * 2
            return CGSize(width: dx * strength, height: dy * strength)
        }()
        content
            .offset(offset)
            .animation(.interpolatingSpring(stiffness: 220, damping: 26), value: offset)
    }
}

struct OrbitHoverModifier: ViewModifier {
    @Environment(\.aether) private var theme
    var cornerRadius: CGFloat
    var magnetic: Bool
    @State private var tracker = PointerTracker()
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        let effects = theme.effects
        if effects.hoverReflection || (magnetic && effects.magneticHover) {
            MagneticOffset(tracker: tracker, size: size, strength: magnetic && effects.magneticHover ? 2.5 : 0,
                           content: content
                               .overlay {
                                   if effects.hoverReflection && theme.usesGlass {
                                       ReflectionLayer(tracker: tracker, cornerRadius: cornerRadius)
                                   }
                               })
                .background(GeometryReader { geo in Color.clear.onAppear { size = geo.size }.onChange(of: geo.size) { size = $0 } })
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let point): tracker.location = point
                    case .ended: tracker.location = nil
                    }
                }
        } else {
            content
        }
    }
}

extension View {
    /// Glasreflexion (und optional magnetisches Schweben) für interaktive Flächen.
    func orbitHover(cornerRadius: CGFloat = Radius.card, magnetic: Bool = false) -> some View {
        modifier(OrbitHoverModifier(cornerRadius: cornerRadius, magnetic: magnetic))
    }
}

// MARK: - Leere Zustände

/// Leerer Zustand mit eigener Illustration (ORBIT-Zeichen mit Symbol) statt eines grauen Symbols.
struct OrbitEmptyState: View {
    @Environment(\.aether) private var theme
    let symbol: String
    let title: String
    let detail: String
    var problem = false

    var body: some View {
        VStack(spacing: 10) {
            OrbitMark(size: 92, symbol: symbol, muted: problem)
                .padding(.bottom, 6)
            Text(title).font(Typo.bodyMedium).foregroundStyle(theme.textPrimary)
            Text(detail)
                .font(Typo.callout)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

// MARK: - Flüssiger Fortschritt (Dateivorgänge)

/// Fortschrittsbalken mit flüssiger Füllung. Die Füllung folgt dem echten Fortschritt; der Lichtschimmer läuft nur,
/// solange der Vorgang wirklich arbeitet (Core Animation, gedrosselt) – nie als Ersatz für Fortschritt.
struct LiquidProgressBar: NSViewRepresentable {
    var fraction: Double
    var active: Bool
    var color: Color
    var track: Color

    func makeNSView(context: Context) -> LiquidProgressLayerView { LiquidProgressLayerView() }

    func updateNSView(_ view: LiquidProgressLayerView, context: Context) {
        view.update(fraction: fraction, active: active, color: NSColor(color), track: NSColor(track))
    }
}

final class LiquidProgressLayerView: NSView {
    private let trackLayer = CALayer()
    private let fill = CAGradientLayer()
    private let sheen = CAGradientLayer()
    private var fraction: Double = 0
    private var active = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let root = CALayer()
        layer = root
        wantsLayer = true
        root.addSublayer(trackLayer)
        trackLayer.addSublayer(fill)
        fill.addSublayer(sheen)
        trackLayer.masksToBounds = true
        fill.masksToBounds = true
        fill.startPoint = CGPoint(x: 0, y: 0.5)
        fill.endPoint = CGPoint(x: 1, y: 0.5)
        sheen.startPoint = CGPoint(x: 0, y: 0.5)
        sheen.endPoint = CGPoint(x: 1, y: 0.5)
        sheen.colors = [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.withAlphaComponent(0.45).cgColor,
                        NSColor.white.withAlphaComponent(0).cgColor]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 6) }

    func update(fraction newFraction: Double, active newActive: Bool, color: NSColor, track: NSColor) {
        trackLayer.backgroundColor = track.cgColor
        let c = color.usingColorSpace(.sRGB) ?? color
        fill.colors = [c.withAlphaComponent(0.75).cgColor, c.cgColor]
        let clamped = min(1, max(0, newFraction.isFinite ? newFraction : 0))
        if clamped != fraction {
            fraction = clamped
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.35)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            layoutFill()
            CATransaction.commit()
        }
        if newActive != active {
            active = newActive
            applySheen()
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = bounds
        trackLayer.cornerRadius = bounds.height / 2
        layoutFill()
        CATransaction.commit()
        applySheen()
    }

    private func layoutFill() {
        let width = bounds.width * CGFloat(fraction)
        fill.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        fill.cornerRadius = bounds.height / 2
        sheen.frame = CGRect(x: -60, y: 0, width: 60, height: bounds.height)
    }

    private func applySheen() {
        sheen.removeAnimation(forKey: "orbit.sheen")
        sheen.isHidden = !active
        guard active, bounds.width > 0 else { return }
        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = -30
        move.toValue = bounds.width + 30
        move.duration = 1.6
        move.repeatCount = .infinity
        if #available(macOS 12.0, *) {
            move.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 24)
        }
        sheen.add(move, forKey: "orbit.sheen")
    }
}

// MARK: - Ruhige Zahlenwechsel

/// Text, der bei Änderung kurz von unten einblendet (nur Profil „Immersiv“, nur große Kennzahlen).
struct RollingText: View {
    @Environment(\.aether) private var theme
    let text: String

    var body: some View {
        if theme.effects.numberTransitions {
            ZStack {
                Text(text)
                    .id(text)
                    .transition(.asymmetric(insertion: .offset(y: 6).combined(with: .opacity),
                                            removal: .offset(y: -6).combined(with: .opacity)))
            }
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.28), value: text)
        } else {
            Text(text)
        }
    }
}

// MARK: - Statussymbol mit Zustandswechsel

/// Symbol, das bei einem echten Zustandswechsel (z. B. Thermalstatus) kurz wechselt statt hart zu springen.
struct OrbitStatusSymbol: View {
    @Environment(\.aether) private var theme
    let symbol: String
    let color: Color
    var size: CGFloat = 13

    var body: some View {
        ZStack {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color)
                .id(symbol)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
        .frame(width: size * 1.6, height: size * 1.6)
        .aetherAnimation(.interpolatingSpring(stiffness: 260, damping: 18), value: symbol)
    }
}

/// Bestätigungssymbol, das beim Erscheinen kurz aufspringt (nach abgeschlossenem Vorgang).
struct CompletionSymbol: View {
    @Environment(\.aether) private var theme
    let isError: Bool
    @State private var shown = false

    var body: some View {
        Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .foregroundStyle(isError ? theme.statusElevated : theme.statusNormal)
            .scaleEffect(shown ? 1 : 0.4)
            .opacity(shown ? 1 : 0)
            .onAppear {
                // Ohne Bewegung (Einstellung oder „Bewegung reduzieren“) sofort sichtbar
                if theme.motion == .off || theme.effects.introCrossfadeOnly || !theme.effects.dataFlow {
                    shown = true
                } else {
                    withAnimation(.interpolatingSpring(stiffness: 300, damping: 15)) { shown = true }
                }
            }
    }
}

// MARK: - Lichtfluss (Akku lädt, Daten fließen)

/// Ein weicher Lichtschimmer, der durch eine Fläche wandert – nur einsetzen, solange der dargestellte Vorgang wirklich
/// läuft (z. B. macOS meldet „lädt“). Core Animation, ≤ 24 Bilder/s.
struct SheenFlow: NSViewRepresentable {
    var duration: Double = 2.4
    var intensity: Double = 0.38

    func makeNSView(context: Context) -> SheenFlowLayerView { SheenFlowLayerView() }

    func updateNSView(_ view: SheenFlowLayerView, context: Context) {
        view.configure(duration: duration, intensity: intensity)
    }
}

final class SheenFlowLayerView: NSView {
    private let sheen = CAGradientLayer()
    private var duration: Double = 0
    private var intensity: Double = 0
    private var builtWidth: CGFloat = -1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let root = CALayer()
        root.masksToBounds = true
        layer = root
        wantsLayer = true
        root.addSublayer(sheen)
        sheen.startPoint = CGPoint(x: 0, y: 0.5)
        sheen.endPoint = CGPoint(x: 1, y: 0.5)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(duration newDuration: Double, intensity newIntensity: Double) {
        guard newDuration != duration || newIntensity != intensity else { return }
        duration = newDuration
        intensity = newIntensity
        sheen.colors = [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.withAlphaComponent(intensity).cgColor,
                        NSColor.white.withAlphaComponent(0).cgColor]
        restart()
    }

    override func layout() {
        super.layout()
        if bounds.width != builtWidth { restart() }
    }

    private func restart() {
        builtWidth = bounds.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let w = max(24, bounds.width * 0.35)
        sheen.frame = CGRect(x: -w, y: 0, width: w, height: bounds.height)
        CATransaction.commit()
        sheen.removeAnimation(forKey: "orbit.sheen")
        guard bounds.width > 0, duration > 0 else { return }
        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = -w / 2
        move.toValue = bounds.width + w / 2
        move.duration = duration
        move.repeatCount = .infinity
        move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        if #available(macOS 12.0, *) {
            move.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 24, preferred: 20)
        }
        sheen.add(move, forKey: "orbit.sheen")
    }
}
