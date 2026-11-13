import SwiftUI
import AppKit
import Combine
import QuartzCore
import AetherCore

// =============================================================================================
// ORBIT Core – der Systemzustand als Kern mit sechs Umlaufbahnen (innen → außen):
// CPU · GPU · Arbeitsspeicher · Massenspeicher · Netzwerk · Akku.
//
// Ehrlichkeit: Jeder Bogen ist ein gemessener Anteil (Telemetrie von Monitoring 2.0). Das Netzwerk hat keinen
// festen Höchstwert; sein Bogen ist ausdrücklich „bezogen auf die Spitze der letzten 5 Minuten“. Fehlt ein Wert
// (kein Akku, GPU-Auslastung nicht verfügbar, noch keine zweite Messung), bleibt die Bahn gestrichelt und leer.
// Bewegung: Bögen gleiten nur bei sichtbarer Änderung (0,5-%-Raster); der Lichtpunkt auf der Netzwerkbahn kreist nur,
// solange Daten fließen – seine Geschwindigkeit folgt dem Durchsatz. Alles über Core Animation, nicht SwiftUI.
// =============================================================================================

/// Bündelt die Messwerte für die Ringe und veröffentlicht nur bei sichtbarer Änderung eines Bogens.
@MainActor
final class OrbitCoreFeed: ObservableObject {
    @Published private(set) var rings: [OrbitRingState] = OrbitRingKind.allCases.map { OrbitRingState(kind: $0, fraction: nil, basis: .measured) }
    /// Durchsatz relativ zur Spitze (0…1) – steuert den Lichtpunkt; nil = kein Wert.
    @Published private(set) var flow: Double?

    private var cancellables: Set<AnyCancellable> = []
    private var peak = RollingPeak(window: 300, bucket: 15)
    private weak var telemetry: Telemetry?
    private var raw = false
    private var physicalMemory: UInt64?
    private var storage: (capacity: Int64, available: Int64)?
    private var started = false

    func start(telemetry: Telemetry, storage store: StorageStore) {
        guard !started else { return }
        started = true
        self.telemetry = telemetry
        let ids: [(MetricID, MetricUnit)] = [(.cpuTotal, .fraction), (.gpu, .fraction), (.memoryUsed, .bytes),
                                             (.networkDown, .bytesPerSecond), (.networkUp, .bytesPerSecond),
                                             (.batteryPercent, .percentInteger)]
        for (id, unit) in ids {
            telemetry.value(id, unit: unit).objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.recompute() }
                .store(in: &cancellables)
        }
        store.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                if let root = snapshot?.startup {
                    self?.storage = (root.capacity, root.available)
                } else {
                    self?.storage = nil
                }
                self?.recompute()
            }
            .store(in: &cancellables)
        recompute()
    }

    func configure(raw: Bool, physicalMemory: UInt64?) {
        // Bytes bleiben UInt64 bis in AetherCore (dort getestet umgerechnet): `map(Double.init)` traf in Lauf 24
        // `Double(bitPattern:)` – der Speicherring stand deshalb auf 100 %.
        guard raw != self.raw || physicalMemory != self.physicalMemory else { return }
        self.raw = raw
        self.physicalMemory = physicalMemory
        recompute()
    }

    private func value(_ id: MetricID, _ unit: MetricUnit) -> Double? {
        guard let metric = telemetry?.value(id, unit: unit), metric.isAvailable else { return nil }
        return metric.display(raw: raw)
    }

    private func recompute() {
        let now = Date().timeIntervalSinceReferenceDate
        let down = value(.networkDown, .bytesPerSecond)
        let up = value(.networkUp, .bytesPerSecond)
        let throughput: Double? = (down == nil && up == nil) ? nil : (down ?? 0) + (up ?? 0)
        if let throughput { peak.add(throughput, at: now) }
        let network = OrbitCoreModel.networkFraction(current: throughput, peak: peak.peak(at: now))
        let next: [OrbitRingState] = [
            OrbitRingState(kind: .cpu, fraction: value(.cpuTotal, .fraction), basis: .measured),
            OrbitRingState(kind: .gpu, fraction: value(.gpu, .fraction), basis: .measured),
            OrbitRingState(kind: .memory, fraction: OrbitCoreModel.memoryFraction(used: value(.memoryUsed, .bytes), physicalBytes: physicalMemory),
                           basis: .measured),
            OrbitRingState(kind: .storage, fraction: OrbitCoreModel.storageFraction(capacity: storage?.capacity, available: storage?.available),
                           basis: .measured),
            OrbitRingState(kind: .network, fraction: network, basis: .relativeToPeak(window: 300)),
            OrbitRingState(kind: .battery, fraction: value(.batteryPercent, .percentInteger).map { $0 / 100 }, basis: .measured),
        ]
        if next.map(\.arc) != rings.map(\.arc) || next.map(\.basis) != rings.map(\.basis) { rings = next }
        let quantizedFlow = network.map { ($0 * 20).rounded() / 20 }
        if quantizedFlow != flow { flow = quantizedFlow }
    }
}

extension OrbitRingKind {
    var title: String {
        switch self {
        case .cpu: return tr("CPU")
        case .gpu: return tr("GPU")
        case .memory: return tr("Memory")
        case .storage: return tr("Storage")
        case .network: return tr("Network")
        case .battery: return tr("Battery")
        }
    }

    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "cube.transparent"
        case .memory: return "memorychip"
        case .storage: return "internaldrive"
        case .network: return "arrow.up.arrow.down"
        case .battery: return SymbolName.battery
        }
    }

    var section: AppSection {
        switch self {
        case .cpu, .gpu: return .cpuGPU
        case .memory: return .memory
        case .storage: return .storage
        case .network: return .network
        case .battery: return .battery
        }
    }

    func color(_ theme: AetherTheme) -> Color {
        switch self {
        case .cpu: return theme.arcticBlue
        case .gpu: return theme.sapphire
        case .memory: return theme.memory
        case .storage: return theme.storage
        case .network: return theme.electricCyan
        case .battery: return theme.battery
        }
    }
}

// MARK: - Panel

struct OrbitCorePanel: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.aether) private var theme
    @StateObject private var feed = OrbitCoreFeed()
    /// Bewusst nicht beobachtet (veröffentlicht jede Sekunde) – siehe OrbitFeedConfigurator.
    let system: SystemStore
    let telemetry: Telemetry
    let storage: StorageStore
    let gpu: GPUStore
    @State private var expanded: OrbitRingKind?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("ORBIT Core"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text(tr("Each orbit is a measured share – dashed orbits have no value."))
                    .font(Typo.callout)
                    .foregroundStyle(theme.textSecondary)
            }
            HStack(alignment: .top, spacing: 28) {
                OrbitCoreRings(feed: feed, cpu: telemetry.value(.cpuTotal))
                    .frame(width: 260, height: 260)
                VStack(spacing: 6) {
                    ForEach(OrbitRingKind.allCases) { kind in
                        OrbitLegendRow(kind: kind, feed: feed, telemetry: telemetry, storage: storage, gpu: gpu,
                                       expanded: expanded == kind) {
                            expanded = expanded == kind ? nil : kind
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(22)
            .glassSurface(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        }
        .aetherAnimation(theme.effects.morphingCards ? Motion.spring : Motion.quick, value: expanded)
        .background(OrbitFeedConfigurator(system: system, feed: feed, telemetry: telemetry, storage: storage))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(tr("ORBIT Core")))
    }
}

/// Überträgt Einstellungen (Rohwerte) und den eingebauten Arbeitsspeicher an den Feed. Eigene kleine Ansicht, damit
/// nur sie – nicht das ganze Panel – bei jeder Veröffentlichung des Systemzustands neu ausgewertet wird.
private struct OrbitFeedConfigurator: View {
    @ObservedObject var system: SystemStore
    @EnvironmentObject private var settings: AppSettings
    let feed: OrbitCoreFeed
    let telemetry: Telemetry
    let storage: StorageStore

    var body: some View {
        Color.clear
            .onAppear {
                feed.configure(raw: settings.showRawValues, physicalMemory: system.hardware.physicalMemory)
                feed.start(telemetry: telemetry, storage: storage)
            }
            .onChange(of: settings.showRawValues) { raw in
                feed.configure(raw: raw, physicalMemory: system.hardware.physicalMemory)
            }
            .onChange(of: system.hardware.physicalMemory) { memory in
                feed.configure(raw: settings.showRawValues, physicalMemory: memory)
            }
    }
}

// MARK: - Ringe (Core Animation)

private struct OrbitCoreRings: View {
    @ObservedObject var feed: OrbitCoreFeed
    @Environment(\.aether) private var theme
    let cpu: MetricValue

    var body: some View {
        ZStack {
            OrbitRingsLayer(rings: feed.rings.map { ring in
                OrbitRingsLayer.Ring(arc: ring.arc, available: ring.basis != .unavailable, color: NSColor(ring.kind.color(theme)))
            }, track: NSColor(theme.textTertiary.opacity(theme.isDark ? 0.22 : 0.18)),
            core: [NSColor(theme.electricCyan), NSColor(theme.arcticBlue), NSColor(theme.sapphire)],
            flow: feed.flow, animated: theme.effects.dataFlow)
            OrbitCoreCenter(cpu: cpu)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    private var accessibilitySummary: String {
        feed.rings.map { ring in
            ring.fraction.map { "\(ring.kind.title) \(fmt.percent($0))" } ?? "\(ring.kind.title) \(tr("Not available"))"
        }.joined(separator: ", ")
    }
}

/// Kernbeschriftung: CPU-Last (gemessen) – der Kern des Systems.
private struct OrbitCoreCenter: View {
    @ObservedObject var cpu: MetricValue
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.aether) private var theme

    var body: some View {
        VStack(spacing: 0) {
            if cpu.isAvailable, let value = cpu.display(raw: settings.showRawValues) {
                RollingText(text: FigureFormat.percent(value).value)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
            } else {
                Text("–").font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(Color.white.opacity(0.8))
            }
            Text(tr("CPU")).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(Color.white.opacity(0.85))
        }
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}

/// Konzentrische Bahnen als CAShapeLayer: Spur (bzw. gestrichelt ohne Wert), Bogen, Kern mit Verlauf und der
/// Lichtpunkt auf der Netzwerkbahn.
struct OrbitRingsLayer: NSViewRepresentable {
    struct Ring: Equatable {
        var arc: Double
        var available: Bool
        var color: NSColor

        static func == (a: Ring, b: Ring) -> Bool {
            a.arc == b.arc && a.available == b.available && a.color.orbitKey == b.color.orbitKey
        }
    }

    var rings: [Ring]
    var track: NSColor
    var core: [NSColor]
    var flow: Double?
    var animated: Bool

    func makeNSView(context: Context) -> OrbitRingsLayerView { OrbitRingsLayerView() }

    func updateNSView(_ view: OrbitRingsLayerView, context: Context) {
        view.update(rings: rings, track: track, core: core, flow: flow, animated: animated)
    }
}

extension NSColor {
    /// sRGB-Anteile als Vergleichsschlüssel (aus SwiftUI erzeugte Farbobjekte sind jedes Mal neu).
    var orbitKey: [Int] {
        guard let c = usingColorSpace(.sRGB) else { return [] }
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { Int(($0 * 255).rounded()) }
    }
}

final class OrbitRingsLayerView: NSView {
    private let host = CALayer()
    private var tracks: [CAShapeLayer] = []
    private var arcs: [CAShapeLayer] = []
    private let coreGlow = CAGradientLayer()
    private let coreBody = CAGradientLayer()
    private let coreEdge = CAShapeLayer()
    private let satelliteOrbit = CALayer()
    private let satellite = CALayer()
    private var rings: [OrbitRingsLayer.Ring] = []
    private var trackKey: [Int] = []
    private var coreKey: [[Int]] = []
    private var flow: Double?
    private var builtSize: CGSize = .zero

    static let lineWidth: CGFloat = 8
    static let gap: CGFloat = 5.5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let root = CALayer()
        layer = root
        wantsLayer = true
        root.addSublayer(host)
        coreGlow.type = .radial
        coreGlow.startPoint = CGPoint(x: 0.5, y: 0.5)
        coreGlow.endPoint = CGPoint(x: 1, y: 1)
        coreBody.startPoint = CGPoint(x: 1, y: 1)
        coreBody.endPoint = CGPoint(x: 0, y: 0)
        coreEdge.fillColor = nil
        coreEdge.strokeColor = NSColor.white.withAlphaComponent(0.35).cgColor
        coreEdge.lineWidth = 1
        host.addSublayer(coreGlow)
        host.addSublayer(coreBody)
        host.addSublayer(coreEdge)
        satellite.backgroundColor = NSColor.white.cgColor
        satellite.shadowColor = NSColor.white.cgColor
        satellite.shadowOpacity = 0.9
        satellite.shadowRadius = 4
        satellite.shadowOffset = .zero
        satelliteOrbit.addSublayer(satellite)
        satelliteOrbit.speed = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(rings newRings: [OrbitRingsLayer.Ring], track: NSColor, core: [NSColor], flow newFlow: Double?, animated: Bool) {
        let structural = newRings.count != rings.count || newRings.map(\.available) != rings.map(\.available)
            || track.orbitKey != trackKey || core.map(\.orbitKey) != coreKey
            || zip(newRings, rings).contains { $0.color.orbitKey != $1.color.orbitKey }
        let previous = rings
        rings = newRings
        if structural || tracks.count != newRings.count {
            trackKey = track.orbitKey
            coreKey = core.map(\.orbitKey)
            build(track: track, core: core)
        }
        CATransaction.begin()
        if animated && !previous.isEmpty {
            CATransaction.setAnimationDuration(0.6)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1))
        } else {
            CATransaction.setDisableActions(true)
        }
        for (layer, ring) in zip(arcs, rings) {
            layer.strokeEnd = ring.available ? CGFloat(max(0.004, ring.arc)) : 0
        }
        CATransaction.commit()
        if newFlow != flow || structural {
            flow = newFlow
            applySatelliteSpeed(animated: animated)
        }
    }

    override func layout() {
        super.layout()
        if bounds.size != builtSize, !rings.isEmpty { rebuildGeometry() }
    }

    private func build(track: NSColor, core: [NSColor]) {
        tracks.forEach { $0.removeFromSuperlayer() }
        arcs.forEach { $0.removeFromSuperlayer() }
        tracks = []
        arcs = []
        for ring in rings {
            let t = CAShapeLayer()
            t.fillColor = nil
            t.strokeColor = ring.available ? track.cgColor : track.withAlphaComponent(track.alphaComponent * 1.4).cgColor
            t.lineWidth = ring.available ? Self.lineWidth : 1.5
            t.lineDashPattern = ring.available ? nil : [2, 5]
            t.lineCap = .round
            host.insertSublayer(t, below: coreGlow)
            tracks.append(t)
            let a = CAShapeLayer()
            a.fillColor = nil
            a.strokeColor = ring.color.cgColor
            a.lineWidth = Self.lineWidth
            a.lineCap = .round
            a.strokeEnd = 0
            a.shadowColor = ring.color.cgColor
            a.shadowOpacity = 0.35
            a.shadowRadius = 3
            a.shadowOffset = .zero
            host.insertSublayer(a, below: coreGlow)
            arcs.append(a)
        }
        let glowColor = core.dropFirst().first ?? NSColor.systemBlue
        coreGlow.colors = [glowColor.withAlphaComponent(0.45).cgColor, glowColor.withAlphaComponent(0).cgColor]
        coreBody.colors = core.map(\.cgColor)
        if satelliteOrbit.superlayer == nil { host.addSublayer(satelliteOrbit) }
        satellite.backgroundColor = (core.first ?? .white).blended(withFraction: 0.5, of: .white)?.cgColor ?? NSColor.white.cgColor
        rebuildGeometry()
    }

    private func rebuildGeometry() {
        builtSize = bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.frame = bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let outer = min(bounds.width, bounds.height) / 2 - Self.lineWidth / 2 - 2
        let step = Self.lineWidth + Self.gap
        for (index, (t, a)) in zip(tracks, arcs).enumerated() {
            let radius = outer - CGFloat(rings.count - 1 - index) * step
            // Beginn oben (12 Uhr), im Uhrzeigersinn – in der nicht gespiegelten Ebene: von π/2 abwärts
            let path = CGMutablePath()
            path.addArc(center: center, radius: radius, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
            t.path = path
            a.path = path
            t.frame = bounds
            a.frame = bounds
        }
        let innermost = outer - CGFloat(max(0, rings.count - 1)) * step
        let coreRadius = max(18, innermost - Self.lineWidth / 2 - 10)
        coreBody.frame = CGRect(x: center.x - coreRadius, y: center.y - coreRadius, width: coreRadius * 2, height: coreRadius * 2)
        coreBody.cornerRadius = coreRadius
        coreEdge.frame = bounds
        coreEdge.path = CGPath(ellipseIn: coreBody.frame.insetBy(dx: 0.5, dy: 0.5), transform: nil)
        let glow = coreRadius * 1.9
        coreGlow.frame = CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)
        // Lichtpunkt auf der Netzwerkbahn
        if let networkIndex = OrbitRingKind.allCases.firstIndex(of: .network), networkIndex < rings.count {
            let radius = outer - CGFloat(rings.count - 1 - networkIndex) * step
            satelliteOrbit.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
            satelliteOrbit.position = center
            let dot: CGFloat = 5
            satellite.frame = CGRect(x: radius - dot / 2, y: radius * 2 - dot / 2, width: dot, height: dot)
            satellite.cornerRadius = dot / 2
        }
        CATransaction.commit()
        installRotation()
    }

    private func installRotation() {
        guard satelliteOrbit.animation(forKey: "orbit.rotation") == nil else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi
        spin.duration = 1
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        if #available(macOS 12.0, *) {
            spin.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 24)
        }
        satelliteOrbit.add(spin, forKey: "orbit.rotation")
    }

    /// Geschwindigkeit des Lichtpunkts aus dem Durchsatz: Stillstand ohne Daten, ein Umlauf in 12 s bei wenig,
    /// in 2,5 s bei Spitzenlast. Phasentreu umgestellt (kein Springen).
    private func applySatelliteSpeed(animated: Bool) {
        let fraction = flow ?? 0
        let moving = animated && fraction >= 0.02
        satellite.isHidden = flow == nil || (!moving && fraction < 0.02)
        let speed: Float = moving ? Float(1 / (12 - 9.5 * min(1, fraction))) : 0
        let now = CACurrentMediaTime()
        let local = satelliteOrbit.convertTime(now, from: nil)
        satelliteOrbit.timeOffset = local
        satelliteOrbit.beginTime = now
        satelliteOrbit.speed = speed
    }
}

// MARK: - Legende mit verwandelbarer Detailkarte (Morphing Card)

/// Zeile der Legende. Ein Klick verwandelt sie in eine Detailkarte mit Verlauf und Sprung in den Bereich –
/// dieselbe Fläche wächst (Feder), der Inhalt blendet über. Ohne Bewegung: sofortiger Wechsel.
private struct OrbitLegendRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.aether) private var theme
    let kind: OrbitRingKind
    @ObservedObject var feed: OrbitCoreFeed
    let telemetry: Telemetry
    let storage: StorageStore
    let gpu: GPUStore
    let expanded: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        let ring = feed.rings.first { $0.kind == kind } ?? OrbitRingState(kind: kind, fraction: nil, basis: .unavailable)
        let available = ring.basis != .unavailable
        VStack(alignment: .leading, spacing: 12) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    ZStack {
                        if available {
                            Circle().fill(kind.color(theme))
                        } else {
                            Circle().strokeBorder(theme.textTertiary, style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
                        }
                    }
                    .frame(width: 10, height: 10)
                    Image(systemName: kind.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(available ? kind.color(theme) : theme.textTertiary)
                        .frame(width: 16)
                    Text(kind.title)
                        .font(Typo.bodyMedium)
                        .foregroundStyle(theme.textPrimary)
                    Spacer(minLength: 8)
                    OrbitLegendValue(kind: kind, ring: ring, telemetry: telemetry)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(available ? basisText(ring) : unavailableText)
            .accessibilityLabel(Text(kind.title))
            .accessibilityHint(Text(expanded ? tr("Hide details") : tr("Show details")))
            if expanded {
                OrbitDetailCard(kind: kind, ring: ring, telemetry: telemetry, storage: storage,
                                basis: available ? basisText(ring) : unavailableText)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, expanded ? 12 : 7)
        .background(
            RoundedRectangle(cornerRadius: expanded ? Radius.tile : 10, style: .continuous)
                .fill(expanded ? theme.fieldFill : (hovering ? theme.hoverFill : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: expanded ? Radius.tile : 10, style: .continuous)
                .strokeBorder(expanded ? kind.color(theme).opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering = $0 }
    }

    private func basisText(_ ring: OrbitRingState) -> String {
        switch ring.basis {
        case .relativeToPeak:
            return tr("Relative to the highest throughput of the last 5 minutes – the network has no fixed maximum.")
        case .measured:
            switch kind {
            case .cpu: return tr("Share of all CPU cores in use (measured).")
            case .gpu: return tr("GPU utilization as reported by the graphics driver.")
            case .memory: return tr("Memory in use (apps, wired and compressed) relative to the installed memory.")
            case .storage: return tr("Used space on the startup volume.")
            case .battery: return tr("Charge level as reported by macOS.")
            case .network: return ""
            }
        case .unavailable:
            return unavailableText
        }
    }

    private var unavailableText: String {
        switch kind {
        case .gpu:
            return gpu.utilization?.reason?.explanation ?? tr("No value yet – waiting for the second measurement.")
        case .battery:
            return tr("No value – this Mac has no battery, or macOS doesn’t report it.")
        default:
            return tr("No value yet – waiting for the second measurement.")
        }
    }
}

/// Wert rechts in der Zeile (beobachtet nur die eigene Messgröße).
private struct OrbitLegendValue: View {
    @Environment(\.aether) private var theme
    let kind: OrbitRingKind
    let ring: OrbitRingState
    let telemetry: Telemetry

    var body: some View {
        Group {
            if kind == .network {
                NetworkRateText(down: telemetry.value(.networkDown, unit: .bytesPerSecond),
                                up: telemetry.value(.networkUp, unit: .bytesPerSecond))
            } else if let fraction = ring.fraction {
                Text(kind == .battery ? FigureFormat.percentInteger(fraction * 100).value + " %" : fmt.percent(fraction))
            } else {
                Text(tr("Not available")).foregroundStyle(theme.textTertiary)
            }
        }
        .font(Typo.callout)
        .monospacedDigit()
        .foregroundStyle(theme.textSecondary)
        .lineLimit(1)
    }
}

private struct NetworkRateText: View {
    @ObservedObject var down: MetricValue
    @ObservedObject var up: MetricValue
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.aether) private var theme

    var body: some View {
        if down.isAvailable || up.isAvailable {
            let d = down.display(raw: settings.showRawValues) ?? 0
            let u = up.display(raw: settings.showRawValues) ?? 0
            Text(verbatim: "↓ \(text(d))  ↑ \(text(u))")
        } else {
            Text(tr("Not available")).foregroundStyle(theme.textTertiary)
        }
    }

    private func text(_ value: Double) -> String {
        let p = FigureFormat.rate(value)
        return p.unit.isEmpty ? p.value : p.value + " " + p.unit
    }
}

/// Detailkarte: Verlauf der letzten 5 Minuten (bzw. Belegung des Startvolumes), Grundlage des Bogens, Sprung in den Bereich.
private struct OrbitDetailCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.aether) private var theme
    let kind: OrbitRingKind
    let ring: OrbitRingState
    let telemetry: Telemetry
    let storage: StorageStore
    let basis: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            chart
            Text(basis)
                .font(Typo.caption)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(tr("Open %@", kind.section.title)) { model.select(kind.section) }
                    .buttonStyle(CapsuleButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        let color = kind.color(theme)
        switch kind {
        case .cpu:
            LiveChart(series: telemetry.series(.cpuTotal), range: .fiveMinutes, color: color, height: 84, showsAxis: false)
        case .gpu:
            if ring.fraction != nil {
                LiveChart(series: telemetry.series(.gpu), range: .fiveMinutes, color: color, height: 84, showsAxis: false)
            }
        case .memory:
            LiveChart(series: telemetry.series(.memoryUsed, unit: .bytes), range: .fiveMinutes, color: color,
                      scale: .auto(minimum: 1_000_000_000), height: 84, showsAxis: false,
                      label: { let p = FigureFormat.bytes($0); return p.value + " " + p.unit })
        case .network:
            LiveChart(series: telemetry.series(.networkDown, unit: .bytesPerSecond),
                      secondary: telemetry.series(.networkUp, unit: .bytesPerSecond), range: .fiveMinutes,
                      color: theme.networkDown, secondaryColor: theme.networkUp, scale: .auto(minimum: 10_000), height: 84,
                      showsAxis: false, label: { let p = FigureFormat.rate($0); return p.value + " " + p.unit })
        case .battery:
            if ring.fraction != nil {
                LiveChart(series: telemetry.series(.batteryPercent, unit: .percentInteger), range: .fiveMinutes, color: color,
                          scale: .fixed(100), height: 84, showsAxis: false,
                          label: { FigureFormat.percentInteger($0).value + " %" })
            }
        case .storage:
            StartupVolumeSummary(storage: storage, color: color)
        }
    }
}

private struct StartupVolumeSummary: View {
    @ObservedObject var storage: StorageStore
    @Environment(\.aether) private var theme
    let color: Color

    var body: some View {
        if let root = storage.snapshot?.startup, root.capacity > 0 {
            let used = root.capacity - root.available
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(root.name).font(Typo.bodyMedium)
                    Spacer()
                    Text(tr("%@ of %@ used", fmt.bytes(used), fmt.bytes(root.capacity)))
                        .font(Typo.callout).monospacedDigit().foregroundStyle(theme.textSecondary)
                }
                FillBar(fraction: Double(used) / Double(root.capacity), color: color)
            }
        } else {
            Text(tr("Not available")).font(Typo.callout).foregroundStyle(theme.textTertiary)
        }
    }
}
