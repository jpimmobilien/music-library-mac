import SwiftUI
import AppKit
import AetherCore

// =============================================================================================
// Visualisierungen der Designsprache „Studio“ – nur Vektorformen und Verläufe (keine Shader, kein Canvas), damit
// sie auf jeder Grafik, auch älterer Intel-Grafik, ohne spürbare Last laufen.
//
// Ehrlichkeit: Bewegung zeigt nur Daten. Netzströme laufen nur bei gemessenem Durchsatz; ihre Dichte und ihr
// Tempo folgen ihm (logarithmisch). Gerätesilhouetten, Glanz und Bühnenlicht sind dekorativ und tragen keine Daten.
// =============================================================================================

// MARK: - Gerät

/// Gerätebild passend zum Modell. `screen` wird in den Bildschirm des Geräts gesetzt.
struct DeviceArt<Screen: View>: View {
    @Environment(\.aether) private var theme
    let kind: DeviceKind
    @ViewBuilder var screen: () -> Screen

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            switch family {
            case .laptop: laptop(size)
            case .allInOne: allInOne(size)
            case .desktop: desktop(size, tower: false)
            case .tower: desktop(size, tower: true)
            }
        }
        .accessibilityHidden(true)
    }

    private enum Family { case laptop, allInOne, desktop, tower }

    private var family: Family {
        switch kind {
        case .macBookPro, .macBookAir, .macBook: return .laptop
        case .iMac: return .allInOne
        case .macPro: return .tower
        case .macMini, .macStudio, .virtualMachine, .unknown: return .desktop
        }
    }

    // Farben des Gehäuses (Aluminium) – dekorativ
    private var metalTop: Color { theme.isDark ? Color(white: 0.24) : Color(white: 0.86) }
    private var metalBottom: Color { theme.isDark ? Color(white: 0.11) : Color(white: 0.70) }
    private var edge: Color { theme.isDark ? Color.white.opacity(0.22) : Color.white.opacity(0.9) }

    private func laptop(_ size: CGSize) -> some View {
        let lidW = min(size.width * 0.86, size.height * 1.32)
        let lidH = lidW * 0.63
        let baseW = lidW * 1.15
        let baseH = max(6, lidW * 0.034)
        let top = (size.height - lidH - baseH) / 2
        return ZStack(alignment: .topLeading) {
            groundShadow(width: baseW * 1.05)
                .position(x: size.width / 2, y: top + lidH + baseH + 6)
            // Deckel
            RoundedRectangle(cornerRadius: lidW * 0.032, style: .continuous)
                .fill(LinearGradient(colors: [metalTop, metalBottom], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: lidW * 0.032, style: .continuous).strokeBorder(edge, lineWidth: 1))
                .frame(width: lidW, height: lidH)
                .position(x: size.width / 2, y: top + lidH / 2)
            display(width: lidW - lidW * 0.05, height: lidH - lidW * 0.05, corner: lidW * 0.02)
                .position(x: size.width / 2, y: top + lidH / 2)
            // Unterteil mit Griffmulde
            LaptopBaseShape()
                .fill(LinearGradient(colors: [metalTop, metalBottom.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                .overlay(LaptopBaseShape().stroke(edge.opacity(0.7), lineWidth: 0.8))
                .frame(width: baseW, height: baseH)
                .position(x: size.width / 2, y: top + lidH + baseH / 2)
            Capsule()
                .fill(metalBottom.opacity(0.9))
                .frame(width: lidW * 0.14, height: baseH * 0.35)
                .position(x: size.width / 2, y: top + lidH + baseH * 0.22)
        }
    }

    private func allInOne(_ size: CGSize) -> some View {
        let w = min(size.width * 0.78, size.height * 1.15)
        let screenH = w * 0.58
        let chinH = w * 0.08
        let standH = w * 0.16
        let top = (size.height - screenH - chinH - standH) / 2
        return ZStack(alignment: .topLeading) {
            groundShadow(width: w * 0.5)
                .position(x: size.width / 2, y: top + screenH + chinH + standH)
            // Fuß und Hals
            StandShape()
                .fill(LinearGradient(colors: [metalTop, metalBottom], startPoint: .top, endPoint: .bottom))
                .frame(width: w * 0.3, height: standH)
                .position(x: size.width / 2, y: top + screenH + chinH + standH / 2)
            // Gehäuse
            RoundedRectangle(cornerRadius: w * 0.02, style: .continuous)
                .fill(LinearGradient(colors: [metalTop, metalBottom], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: w * 0.02, style: .continuous).strokeBorder(edge, lineWidth: 1))
                .frame(width: w, height: screenH + chinH)
                .position(x: size.width / 2, y: top + (screenH + chinH) / 2)
            display(width: w - w * 0.04, height: screenH - w * 0.02, corner: w * 0.012)
                .position(x: size.width / 2, y: top + screenH / 2 + w * 0.006)
        }
    }

    private func desktop(_ size: CGSize, tower: Bool) -> some View {
        let w = min(size.width * 0.66, size.height * 1.12)
        let screenH = w * 0.58
        let standH = w * 0.13
        let top = (size.height - screenH - standH) / 2
        let boxW = tower ? w * 0.26 : w * 0.34
        let boxH = tower ? w * 0.5 : w * 0.1
        return ZStack(alignment: .topLeading) {
            groundShadow(width: w * 0.9)
                .position(x: size.width / 2, y: top + screenH + standH)
            StandShape()
                .fill(LinearGradient(colors: [metalTop, metalBottom], startPoint: .top, endPoint: .bottom))
                .frame(width: w * 0.24, height: standH)
                .position(x: size.width / 2 - w * 0.1, y: top + screenH + standH / 2)
            RoundedRectangle(cornerRadius: w * 0.02, style: .continuous)
                .fill(LinearGradient(colors: [metalTop, metalBottom], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: w * 0.02, style: .continuous).strokeBorder(edge, lineWidth: 1))
                .frame(width: w, height: screenH)
                .position(x: size.width / 2 - w * 0.1, y: top + screenH / 2)
            display(width: w - w * 0.035, height: screenH - w * 0.035, corner: w * 0.012)
                .position(x: size.width / 2 - w * 0.1, y: top + screenH / 2)
            // Rechner (Mac mini / Studio bzw. Mac Pro)
            BoxArt(tower: tower, metalTop: metalTop, metalBottom: metalBottom, edge: edge, accent: theme.accent)
                .frame(width: boxW, height: boxH)
                .position(x: size.width / 2 + w * 0.46, y: top + screenH + standH - boxH / 2)
        }
    }

    private func display(width: CGFloat, height: CGFloat, corner: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color.black)
            screen()
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            // Glasreflex (dekorativ)
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(stops: [.init(color: .white.opacity(0.07), location: 0),
                                             .init(color: .clear, location: 0.45)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .allowsHitTesting(false)
        }
        .frame(width: width, height: height)
    }

    private func groundShadow(width: CGFloat) -> some View {
        Ellipse()
            .fill(RadialGradient(colors: [Color.black.opacity(theme.isDark ? 0.55 : 0.22), .clear],
                                 center: .center, startRadius: 0, endRadius: width / 2))
            .frame(width: width, height: width * 0.08)
    }
}

/// Unterteil eines Notebooks (leicht trapezförmig, vorne abgerundet).
struct LaptopBaseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.width * 0.012
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - inset * 2.5, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY * 0.9))
        path.addLine(to: CGPoint(x: rect.minX + inset * 2.5, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + inset, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.maxY * 0.9))
        path.closeSubpath()
        return path
    }
}

/// Standfuß (Hals + Fuß).
struct StandShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let neck = rect.width * 0.55
        path.move(to: CGPoint(x: rect.midX - neck / 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + neck / 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 3))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - 3, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + 3, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - 3), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Rechnergehäuse in leichter Aufsicht (Mac mini / Mac Studio bzw. Mac Pro mit Lochgitter).
private struct BoxArt: View {
    let tower: Bool
    let metalTop: Color
    let metalBottom: Color
    let edge: Color
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let topH = tower ? h * 0.08 : h * 0.42
            ZStack(alignment: .topLeading) {
                // Oberseite
                RoundedRectangle(cornerRadius: w * 0.08, style: .continuous)
                    .fill(LinearGradient(colors: [metalTop, metalTop.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                    .frame(width: w, height: topH * 1.4)
                // Front
                RoundedRectangle(cornerRadius: w * 0.06, style: .continuous)
                    .fill(LinearGradient(colors: [metalBottom.opacity(0.95), metalBottom], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: w * 0.06, style: .continuous).strokeBorder(edge.opacity(0.6), lineWidth: 0.8))
                    .frame(width: w, height: h - topH)
                    .offset(y: topH)
                if tower {
                    // Lochgitter (dekorativ)
                    VStack(spacing: w * 0.06) {
                        ForEach(0..<7, id: \.self) { _ in
                            HStack(spacing: w * 0.06) {
                                ForEach(0..<5, id: \.self) { _ in
                                    Circle().fill(Color.black.opacity(0.45)).frame(width: w * 0.1, height: w * 0.1)
                                }
                            }
                        }
                    }
                    .frame(width: w, height: h - topH)
                    .offset(y: topH)
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: max(2, w * 0.025), height: max(2, w * 0.025))
                        .offset(x: w * 0.88, y: topH + (h - topH) * 0.45)
                }
            }
        }
    }
}

// MARK: - Kerne als Lichtsäulen

/// Auslastung je Kern als Lichtsäulen (Höhe und Leuchtkraft = geglättete Last). Fehlt ein Wert, bleibt die Säule
/// dunkel.
struct CoreLights: View {
    @Environment(\.aether) private var theme
    let levels: [Double?]
    var kinds: [CoreCluster.Kind] = []
    var color: Color
    var efficiencyColor: Color? = nil

    var body: some View {
        GeometryReader { geo in
            let count = max(1, levels.count)
            // Säulen bleiben schlank (höchstens 18 pt bzw. 12 % der Höhe) – bei wenigen Kernen mittig statt breit
            let barW = min(18, geo.size.height * 0.12,
                           max(2, (geo.size.width - max(2, geo.size.width * 0.012) * CGFloat(count + 1)) / CGFloat(count)))
            let spacing = min(max(2, geo.size.width * 0.012) * 2.5, max(2, (geo.size.width - barW * CGFloat(count)) / CGFloat(count + 1)))
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    let tint = kinds.indices.contains(index) && kinds[index] == .efficiency ? (efficiencyColor ?? color) : color
                    let value = CGFloat(min(1, max(0, level ?? 0)))
                    ZStack(alignment: .bottom) {
                        Capsule()
                            .fill(tint.opacity(0.10))
                        // Kein Schatten (teuer beim Neuzeichnen) – das Leuchten entsteht aus dem Verlauf und der hellen Kappe.
                        Capsule()
                            .fill(LinearGradient(colors: [tint.opacity(0.55 + 0.45 * Double(value)), tint.opacity(0.25)],
                                                 startPoint: .top, endPoint: .bottom))
                            .overlay(alignment: .top) {
                                Capsule()
                                    .fill(Color.white.opacity(0.35 * Double(value)))
                                    .frame(height: min(barW, 4))
                                    .padding(.horizontal, barW * 0.2)
                            }
                            .frame(height: max(barW, geo.size.height * value))
                            .opacity(level == nil ? 0 : 1)
                    }
                    .frame(width: barW)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
        .aetherAnimation(Motion.easeOut(0.6), value: levels.map { (($0 ?? 0) * 100).rounded() })
    }
}

// MARK: - Datenströme

/// Lichtpartikel entlang einer Bahn; Dichte und Tempo folgen dem gemessenen Durchsatz (logarithmisch).
/// 0 B/s oder kein Messwert → keine Partikel. Bei „Bewegung reduzieren“ bzw. Bewegung „Aus“ stehen sie still.
/// Die Bewegung läuft als Core-Animation-Ebene im Fensterserver: Die App selbst rechnet dafür keine Bilder
/// (anders als eine SwiftUI-Zeitleiste mit 30 Bildern/s).
struct FlowStream: View {
    @Environment(\.aether) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bytes pro Sekunde
    let rate: Double?
    var color: Color
    /// true = von links nach rechts
    var forward = true
    var thickness: CGFloat = 3

    /// Partikelzahl 0…12 (ab 100 B/s).
    static func particles(for rate: Double?) -> Int {
        guard let rate, rate >= 100 else { return 0 }
        return min(12, max(1, Int((log10(rate / 100) * 2.6).rounded())))
    }

    /// Tempo 24…220 pt/s, in Stufen zu 12 pt/s (die Animation wird nur bei einer neuen Stufe neu gestartet).
    static func speed(for rate: Double?) -> Double {
        guard let rate, rate >= 100 else { return 0 }
        let raw = min(220, max(24, 24 + 42 * log10(rate / 100)))
        return (raw / 12).rounded() * 12
    }

    var body: some View {
        let count = Self.particles(for: rate)
        ZStack {
            // Bahn
            Capsule()
                .fill(LinearGradient(colors: [color.opacity(0), color.opacity(count == 0 ? 0.10 : 0.24), color.opacity(0)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: max(1, thickness * 0.4))
            FlowLayer(configuration: FlowLayerView.Configuration(
                count: count, speed: Self.speed(for: rate), color: NSColor(color), forward: forward, thickness: thickness,
                animated: !reduceMotion && theme.motion != .off))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct FlowLayer: NSViewRepresentable {
    let configuration: FlowLayerView.Configuration

    func makeNSView(context: Context) -> FlowLayerView { FlowLayerView() }

    func updateNSView(_ view: FlowLayerView, context: Context) {
        view.configuration = configuration
    }
}

/// Partikelband: eine Ebene, per CAReplicatorLayer vervielfacht und als Ganzes um einen Abstand verschoben
/// (nahtlose Endlosschleife). Ränder blenden über eine Maske aus.
final class FlowLayerView: NSView {
    struct Configuration: Equatable {
        var count: Int
        var speed: Double
        var color: NSColor
        var forward: Bool
        var thickness: CGFloat
        var animated: Bool

        /// Farben über ihre sRGB-Anteile vergleichen (aus SwiftUI erzeugte NSColor-Objekte sind jedes Mal neu) –
        /// sonst würde die Animation bei jeder Aktualisierung neu starten.
        static func == (a: Configuration, b: Configuration) -> Bool {
            a.count == b.count && a.speed == b.speed && a.forward == b.forward && a.thickness == b.thickness
                && a.animated == b.animated && a.colorKey == b.colorKey
        }

        private var colorKey: [Int] {
            guard let c = color.usingColorSpace(.sRGB) else { return [] }
            return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { Int(($0 * 255).rounded()) }
        }
    }

    var configuration: Configuration? {
        didSet { if configuration != oldValue { rebuild() } }
    }

    private let host = CALayer()
    private let replicator = CAReplicatorLayer()
    private let particle = CAGradientLayer()
    private let fade = CAGradientLayer()
    private var builtSize: CGSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Ebenen-gehostete Ansicht: Die Ebenen gehören uns, AppKit zeichnet hier nichts.
        let root = CALayer()
        layer = root
        wantsLayer = true
        root.addSublayer(host)
        host.addSublayer(replicator)
        replicator.addSublayer(particle)
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fade.locations = [0, 0.14, 0.86, 1]
        host.mask = fade
        host.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        if bounds.size != builtSize { rebuild() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if newSize != builtSize { rebuild() }
    }

    /// Klicks gehen an die darunterliegende Ansicht (z. B. „Details“).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        rebuild()
    }

    private func rebuild() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        builtSize = bounds.size
        host.frame = bounds
        fade.frame = host.bounds
        replicator.removeAllAnimations()
        guard let c = configuration, c.count > 0, bounds.width > 8 else {
            replicator.isHidden = true
            return
        }
        replicator.isHidden = false
        let length = bounds.width
        let spacing = length / CGFloat(c.count)
        let width = min(spacing * 0.8, c.thickness * 6)
        replicator.frame = CGRect(x: -spacing, y: 0, width: length + spacing * 2, height: bounds.height)
        replicator.instanceCount = c.count + 2
        replicator.instanceTransform = CATransform3DMakeTranslation(spacing, 0, 0)
        particle.frame = CGRect(x: 0, y: (bounds.height - c.thickness) / 2, width: width, height: c.thickness)
        particle.cornerRadius = c.thickness / 2
        var colors = [c.color.withAlphaComponent(0).cgColor, c.color.withAlphaComponent(0.9).cgColor,
                      NSColor.white.withAlphaComponent(0.9).cgColor]
        if !c.forward { colors.reverse() }
        particle.colors = colors
        particle.startPoint = CGPoint(x: 0, y: 0.5)
        particle.endPoint = CGPoint(x: 1, y: 0.5)
        guard c.animated, c.speed > 0 else { return }
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0
        animation.toValue = c.forward ? spacing : -spacing
        animation.duration = Double(spacing) / c.speed
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isRemovedOnCompletion = false
        replicator.add(animation, forKey: "flow")
    }
}

// MARK: - Bogenanzeige

/// Ruhige Bogenanzeige (270°) mit Lichtende – für Anteile 0…1.
struct ArcMeter: View {
    @Environment(\.aether) private var theme
    let fraction: Double?
    var color: Color
    var lineWidth: CGFloat = 10

    var body: some View {
        let value = min(1, max(0, fraction ?? 0))
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(theme.fieldFill, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75 * value)
                .stroke(LinearGradient(colors: [color.opacity(0.55), color], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
                .shadow(color: color.opacity(0.45), radius: 8)
                .opacity(fraction == nil ? 0 : 1)
        }
        .aetherAnimation(Motion.easeOut(0.6), value: (value * 100).rounded())
        .accessibilityHidden(true)
    }
}
