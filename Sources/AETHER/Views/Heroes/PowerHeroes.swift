import SwiftUI
import AppKit
import AetherCore

// =============================================================================================
// Hero-Visualisierungen für Temperatur & Lüfter sowie Batterie (Designsprache „Studio“).
//
// Ehrlichkeit:
// – Wärmekarte: Die Flecken zeigen gemessene SMC-Sensorbereiche (Maximum je Bereich). Ihre Lage im Gehäuse ist
//   schematisch und als solche beschriftet. Ohne Sensorwerte gibt es keine Flecken – nur den Grund.
// – Farbe: ein Farbton, nur die Intensität folgt der Temperatur. Keine roten Warnfarben – Apple veröffentlicht keine
//   Grenzwerte, Temperaturen allein lösen nie einen Hinweis aus. Farbige Stufen gibt es nur für den Thermalstatus,
//   den macOS selbst meldet.
// – Batterie: Füllstand = gemessener Ladestand. Das Leuchten erscheint nur, solange macOS „lädt“ meldet; es läuft als
//   Core-Animation-Ebene im Fensterserver (keine Bildberechnung in der App).
// =============================================================================================

// MARK: - Temperatur & Lüfter

/// Kopf der Seite „Temperatur & Lüfter“: Thermalstatus von macOS als Aussage, darunter die Wärmekarte.
struct ThermalHeader: View {
    @ObservedObject var store: PowerStore
    @ObservedObject var system: SystemStore
    let telemetry: Telemetry
    @AppStorage("aether.thermal.range") private var range: ChartRange = .fiveMinutes

    var body: some View {
        let thermal = store.thermal
        StudioHero(section: .thermal, eyebrow: tr("Temperature & Fans"), headline: headline(thermal),
                   lead: tr("The state comes from macOS. Temperatures and fan speeds are read from the System Management Controller – Apple doesn’t publish limits, so temperatures alone never trigger a warning."),
                   height: 340, tools: {
                       // Zeitraumwahl nur, wenn es einen Temperaturverlauf gibt
                       if !(thermal?.sensors.value?.isEmpty ?? true) { RangePicker(range: $range) }
                   }) {
            // SystemStore ändert sich alle 2 s (Eigenverbrauch) – der Inhalt nur bei neuen Messwerten.
            ThermalHeroContent(thermal: thermal, kind: system.hardware.kind, model: system.hardware.macModel,
                               telemetry: telemetry, range: range)
                .equatable()
        }
    }

    private func headline(_ thermal: ThermalSnapshot?) -> String {
        guard let thermal else { return tr("Measuring…") }
        guard let level = thermal.state.value else { return tr("Thermal state not available") }
        return tr("Thermal state: %@", thermalShortName(level))
    }
}

private struct ThermalHeroContent: View, Equatable {
    @Environment(\.aether) private var theme
    let thermal: ThermalSnapshot?
    let kind: DeviceKind
    let model: MacModelInfo?
    let telemetry: Telemetry
    let range: ChartRange

    static func == (a: ThermalHeroContent, b: ThermalHeroContent) -> Bool {
        a.thermal == b.thermal && a.kind == b.kind && a.model == b.model && a.telemetry === b.telemetry && a.range == b.range
    }

    var body: some View {
        let sensors = thermal?.sensors
        let list = sensors?.value ?? []
        let reason: UnavailableReason? = list.isEmpty && sensors != nil ? (sensors?.reason ?? .notProvidedByMacOS) : nil
        HStack(alignment: .center, spacing: 30) {
            VStack(alignment: .leading, spacing: 10) {
                HeatMap(groups: SensorCatalog.aggregate(list), kind: kind, model: model, unavailable: reason,
                        measuring: thermal == nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !list.isEmpty {
                    SchematicNote()
                }
                if let model {
                    Text(tr("Outline: %@", model.displayName))
                        .font(StudioType.caption)
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            figures(list: list, reason: reason)
                .frame(width: 270, alignment: .leading)
        }
    }

    @ViewBuilder
    private func figures(list: [ThermalSensor], reason: UnavailableReason?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let level = thermal?.state.value {
                BigFigure(label: tr("Thermal state (macOS)"), value: thermalShortName(level), color: theme.color(for: level),
                          size: .small, source: .thermalState)
            } else {
                BigFigure(label: tr("Thermal state (macOS)"), value: "–", size: .small, source: .thermalState,
                          reason: thermal?.state.reason ?? .awaitingSecondSample)
            }
            if !list.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    LiveFigure(metric: telemetry.value(.hottest, unit: .celsius), label: tr("Hottest sensor"),
                               format: FigureFormat.celsius, size: .giant, source: .smcSensors)
                    if let hottest = thermal?.hottest {
                        Text((hottest.meaning.map(sensorMeaning) ?? sensorGroupName(hottest.group)) + "  ·  " + hottest.key)
                            .font(StudioType.caption)
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                    }
                }
            } else if let reason, let sensors = thermal?.sensors {
                BigFigure(label: tr("Hottest sensor"), value: "–", detail: reason.explanation, size: .figure,
                          source: sensors.source, reason: reason)
            }
            fans
            // Bei mehr als zwei Lüftern reicht der Platz nicht – der Verlauf steht dann in der Tafel darunter.
            if !list.isEmpty, (thermal?.fans.value?.count ?? 0) <= 2 {
                LiveChart(series: telemetry.series(.hottest, unit: .celsius), range: range, color: theme.thermal,
                          scale: .auto(minimum: 60), height: 50, label: { fmt.celsius($0) })
            }
        }
    }

    @ViewBuilder
    private var fans: some View {
        if let list = thermal?.fans.value {
            if list.isEmpty {
                Label(tr("No fans – passively cooled"), systemImage: SymbolName.fan)
                    .font(Typo.callout)
                    .foregroundStyle(theme.textSecondary)
            } else {
                let shown = Array(list.prefix(4))
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                          alignment: .leading, spacing: 8) {
                    ForEach(shown) { fan in
                        LiveFigure(metric: telemetry.value(.fan(fan.index), unit: .rpm),
                                   label: list.count > 1 ? tr("Fan %ld", fan.index + 1) : tr("Fan"),
                                   format: FigureFormat.rpm, size: .small, source: .smcFans)
                    }
                }
                if list.count > shown.count {
                    Text(tr("+%ld more", list.count - shown.count))
                        .font(StudioType.caption)
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
    }
}

/// Schematische Wärmekarte: Gehäuse in Aufsicht, je gemessenem Sensorbereich ein weicher Lichtfleck.
private struct HeatMap: View {
    @Environment(\.aether) private var theme
    let groups: [SensorGroupSummary]
    let kind: DeviceKind
    let model: MacModelInfo?
    let unavailable: UnavailableReason?
    let measuring: Bool

    private var isLaptop: Bool {
        if let model { return model.design.isPortable }
        switch kind {
        case .macBookPro, .macBookAir, .macBook: return true
        default: return false
        }
    }

    var body: some View {
        GeometryReader { geo in
            let rect = outlineRect(in: geo.size)
            ZStack(alignment: .topLeading) {
                outline
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .opacity(groups.isEmpty ? 0.45 : 1)
                if !groups.isEmpty {
                    ForEach(groups) { summary in
                        let point = position(summary.group)
                        HeatSpot(summary: summary, scale: rect.height)
                            .position(x: rect.minX + rect.width * point.x, y: rect.minY + rect.height * point.y)
                    }
                } else {
                    message
                        .frame(width: max(0, rect.width - 60))
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// Gehäuse des erkannten Modells (Aufsicht bzw. Front) – ohne Modell die neutrale Form.
    @ViewBuilder
    private var outline: some View {
        if model != nil {
            MacTopArt(model: model)
        } else {
            ChassisOutline(laptop: isLaptop)
        }
    }

    @ViewBuilder
    private var message: some View {
        VStack(spacing: 8) {
            Image(systemName: SymbolName.sensor)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(theme.textSecondary)
            if measuring {
                Text(tr("Measuring…")).font(Typo.bodyMedium).foregroundStyle(theme.textSecondary)
            } else {
                Text(tr("No sensor temperatures")).font(Typo.bodyMedium).foregroundStyle(theme.textPrimary)
                if let unavailable {
                    Text(unavailable.explanation)
                        .font(Typo.caption)
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func outlineRect(in size: CGSize) -> CGRect {
        let aspect: CGFloat = model.map { MacTopArt.aspect($0) } ?? (isLaptop ? 1.5 : 1.3)
        let maxW = max(0, size.width - 16)
        let maxH = max(0, size.height - 16)
        let width = min(maxW, maxH * aspect)
        let height = width / aspect
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    /// Schematische Lage je Bereich (nicht die echte Lage der Sensoren).
    private func position(_ group: SensorGroup) -> CGPoint {
        if isLaptop {
            switch group {
            case .cpu: return CGPoint(x: 0.50, y: 0.28)
            case .gpu: return CGPoint(x: 0.67, y: 0.30)
            case .memory: return CGPoint(x: 0.33, y: 0.30)
            case .storage: return CGPoint(x: 0.20, y: 0.50)
            case .wireless: return CGPoint(x: 0.84, y: 0.16)
            case .power: return CGPoint(x: 0.85, y: 0.52)
            case .battery: return CGPoint(x: 0.50, y: 0.80)
            case .enclosure: return CGPoint(x: 0.16, y: 0.16)
            case .other: return CGPoint(x: 0.72, y: 0.76)
            }
        }
        switch group {
        case .cpu: return CGPoint(x: 0.50, y: 0.42)
        case .gpu: return CGPoint(x: 0.69, y: 0.42)
        case .memory: return CGPoint(x: 0.31, y: 0.42)
        case .storage: return CGPoint(x: 0.28, y: 0.72)
        case .wireless: return CGPoint(x: 0.82, y: 0.18)
        case .power: return CGPoint(x: 0.74, y: 0.74)
        case .battery: return CGPoint(x: 0.50, y: 0.86)
        case .enclosure: return CGPoint(x: 0.17, y: 0.17)
        case .other: return CGPoint(x: 0.51, y: 0.72)
        }
    }

    private var accessibilityText: String {
        guard !groups.isEmpty else { return measuring ? tr("Measuring…") : tr("No sensor temperatures") }
        return groups.map { tr("%@: highest %@, average %@ (%ld sensors)", sensorGroupName($0.group), fmt.celsius($0.maximum),
                               fmt.celsius($0.average), $0.count) }
            .joined(separator: "; ")
    }
}

/// Lichtfleck eines Sensorbereichs: Größe und Leuchtkraft folgen dem gemessenen Maximum (30 … 100 °C).
private struct HeatSpot: View {
    @Environment(\.aether) private var theme
    let summary: SensorGroupSummary
    /// Höhe der Gehäusefläche – die Flecken wachsen mit.
    let scale: CGFloat

    var body: some View {
        let t = min(1, max(0, (summary.maximum - 30) / 70))
        let size = scale * (0.20 + 0.26 * CGFloat(t))
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [theme.thermal.opacity(0.30 + 0.5 * t), theme.thermal.opacity(0.10 * t), .clear],
                                     center: .center, startRadius: 0, endRadius: size / 2))
                .frame(width: size, height: size)
            HStack(spacing: 3) {
                Image(systemName: sensorGroupSymbol(summary.group))
                    .font(.system(size: 9, weight: .semibold))
                Text(fmt.number(summary.maximum, fractionDigits: 0) + " °C")
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(theme.backgroundTop.opacity(0.62)))
        }
        .help(tr("%@: highest %@, average %@ (%ld sensors)", sensorGroupName(summary.group), fmt.celsius(summary.maximum),
                 fmt.celsius(summary.average), summary.count))
        .aetherAnimation(Motion.easeOut(0.8), value: Int(summary.maximum.rounded()))
    }
}

/// Gehäuse in Aufsicht (dekorativ): Notebook mit Tastatur und Trackpad bzw. Rechnergehäuse mit Platine.
private struct ChassisOutline: View {
    @Environment(\.aether) private var theme
    let laptop: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let corner = min(w, h) * 0.07
            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(LinearGradient(colors: [theme.fieldFill.opacity(1.4), theme.fieldFill.opacity(0.5)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(theme.hairline, lineWidth: 1))
                if laptop {
                    // Tastaturfeld und Trackpad
                    RoundedRectangle(cornerRadius: corner * 0.5, style: .continuous)
                        .strokeBorder(theme.hairline, lineWidth: 1)
                        .frame(width: w * 0.82, height: h * 0.44)
                        .position(x: w / 2, y: h * 0.36)
                    RoundedRectangle(cornerRadius: corner * 0.5, style: .continuous)
                        .strokeBorder(theme.hairline, lineWidth: 1)
                        .frame(width: w * 0.36, height: h * 0.24)
                        .position(x: w / 2, y: h * 0.78)
                } else {
                    // Platine und Anschlüsse an der Rückseite
                    RoundedRectangle(cornerRadius: corner * 0.6, style: .continuous)
                        .strokeBorder(theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .frame(width: w * 0.80, height: h * 0.72)
                        .position(x: w / 2, y: h * 0.53)
                    HStack(spacing: w * 0.03) {
                        ForEach(0..<6, id: \.self) { _ in
                            Capsule().fill(theme.hairline).frame(width: w * 0.05, height: h * 0.025)
                        }
                    }
                    .position(x: w / 2, y: h * 0.07)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Batterie

/// Kopf der Batterieseite: Ladestand und -zustand als Aussage, darunter die Zelle mit den Kennzahlen.
struct BatteryHeader: View {
    @ObservedObject var store: PowerStore
    let telemetry: Telemetry
    @AppStorage("aether.battery.range") private var range: ChartRange = .oneHour

    var body: some View {
        if let b = store.battery, b.isPresent {
            StudioHero(section: .battery, eyebrow: tr("Battery"), headline: headline(b), lead: lead(b), height: 320,
                       tools: { RangePicker(range: $range) }) {
                // PowerStore ändert sich auch durch die Thermik (alle 3 s) – der Inhalt nur bei neuen Batteriewerten.
                BatteryHeroContent(battery: b, telemetry: telemetry, range: range)
                    .equatable()
            }
        } else {
            let measuring = store.battery == nil
            StudioHero(section: .battery, eyebrow: tr("Battery"), headline: measuring ? tr("Measuring…") : tr("No battery"),
                       lead: measuring ? nil : tr("This Mac runs on mains power."), height: 190) {
                NoBatteryHero(measuring: measuring)
            }
        }
    }

    private func headline(_ b: BatterySnapshot) -> String {
        guard let percent = b.percent.value else { return batteryChargeState(b) }
        return fmt.integer(percent) + " %  –  " + batteryChargeState(b)
    }

    private func lead(_ b: BatterySnapshot) -> String? {
        var parts: [String] = []
        if let condition = b.systemCondition { parts.append(tr("Condition (macOS): %@", condition)) }
        if let cycles = b.cycleCount.value { parts.append(tr("%ld charge cycles", cycles)) }
        if let health = b.computedHealth.value { parts.append(tr("Capacity (computed): %@", fmt.percent(health, fractionDigits: 1))) }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }
}

private struct BatteryHeroContent: View, Equatable {
    @Environment(\.aether) private var theme
    let battery: BatterySnapshot
    let telemetry: Telemetry
    let range: ChartRange

    static func == (a: BatteryHeroContent, b: BatteryHeroContent) -> Bool {
        a.battery == b.battery && a.telemetry === b.telemetry && a.range == b.range
    }

    var body: some View {
        let b = battery
        let percent = b.percent.value
        let charging = b.isCharging == true
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 36) {
                VStack(spacing: 10) {
                    BatteryCell(percent: percent, charging: charging, onAdapter: b.powerSource == .ac,
                                color: theme.batteryColor(percent: percent ?? 100))
                        .frame(width: 300, height: 140)
                    if charging {
                        Text(tr("The glow appears only while macOS reports that the battery is charging."))
                            .font(StudioType.caption)
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(2)
                            .frame(width: 300)
                    }
                }
                figures(b)
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
            LiveChart(series: telemetry.series(.batteryPercent, unit: .percentInteger), range: range, color: theme.battery,
                      scale: .fixed(100), height: 56, label: { fmt.integer(Int($0.rounded())) + " %" })
        }
    }

    private func figures(_ b: BatterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            LiveFigure(metric: telemetry.value(.batteryPercent, unit: .percentInteger), label: tr("Charge"),
                       format: FigureFormat.percentInteger, size: .giant, source: .powerSources,
                       unavailable: b.percent.reason ?? .awaitingSecondSample)
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
                GridRow {
                    timeFigure(b)
                    LiveFigure(metric: telemetry.value(.batteryPower, unit: .watts), label: tr("Battery power"),
                               format: FigureFormat.watts, size: .small, source: .batteryPower,
                               unavailable: b.power.reason ?? .awaitingSecondSample)
                }
                GridRow {
                    if let cycles = b.cycleCount.value {
                        BigFigure(label: tr("Charge cycles"), value: fmt.integer(cycles), size: .small, source: b.cycleCount.source)
                    } else {
                        BigFigure(label: tr("Charge cycles"), value: "–", size: .small, source: b.cycleCount.source,
                                  reason: b.cycleCount.reason ?? .notProvidedByMacOS)
                    }
                    if let health = b.computedHealth.value {
                        BigFigure(label: tr("Capacity (computed)"), value: fmt.number(health * 100, fractionDigits: 1), unit: "%",
                                  size: .small, source: b.computedHealth.source)
                    } else {
                        BigFigure(label: tr("Capacity (computed)"), value: "–", size: .small, source: b.computedHealth.source,
                                  reason: b.computedHealth.reason ?? .notProvidedByMacOS)
                    }
                }
            }
        }
    }

    /// Restlaufzeit bzw. Zeit bis voll – nur wenn sie etwas aussagt (nie „0 s“, nicht bei voller Ladung).
    @ViewBuilder
    private func timeFigure(_ b: BatterySnapshot) -> some View {
        if let time = batteryTimeReading(b) {
            let label = time.charging ? tr("Until full") : tr("Remaining time")
            if let minutes = time.reading.value {
                BigFigure(label: label, value: fmt.duration(seconds: Double(minutes) * 60), size: .small,
                          source: time.reading.source)
            } else {
                BigFigure(label: label, value: "–",
                          detail: time.reading.reason == .awaitingSecondSample ? tr("macOS is still calculating the remaining time") : nil,
                          size: .small, source: time.reading.source,
                          reason: time.reading.reason ?? .notProvidedByMacOS)
            }
        } else {
            BigFigure(label: tr("Status"), value: batteryChargeState(b), size: .small, source: .powerSources)
        }
    }
}

/// Akkuzelle in leichter Perspektive: Glasgehäuse, Füllung = gemessener Ladestand, Polkappe. Kein Wert → leer.
private struct BatteryCell: View {
    @Environment(\.aether) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let percent: Int?
    let charging: Bool
    let onAdapter: Bool
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let capW = max(6, w * 0.045)
            let bodyW = w - capW - 3
            let corner = h * 0.24
            let inset = h * 0.08
            let level = CGFloat(min(100, max(0, percent ?? 0))) / 100
            ZStack(alignment: .leading) {
                // Gehäuse (Glas, dekorativ)
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(LinearGradient(colors: [shellTop, shellBottom], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(edge, lineWidth: 1))
                    .background {
                        if charging {
                            ChargeGlow(configuration: ChargeGlowView.Configuration(
                                color: NSColor(color), corner: corner, animated: !reduceMotion && theme.motion != .off))
                                .padding(-14)
                        }
                    }
                    .frame(width: bodyW, height: h)
                // Füllung = Ladestand
                RoundedRectangle(cornerRadius: max(2, corner - inset * 0.7), style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(0.98), color.opacity(0.62)], startPoint: .top, endPoint: .bottom))
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(Color.white.opacity(0.32))
                            .frame(height: max(2, h * 0.09))
                            .padding(.horizontal, h * 0.12)
                            .padding(.top, h * 0.07)
                    }
                    .frame(width: max(0, (bodyW - inset * 2) * level), height: h - inset * 2)
                    .offset(x: inset)
                    .opacity(percent == nil || level == 0 ? 0 : 1)
                // Glanz über dem ganzen Gehäuse (Wölbung)
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(LinearGradient(stops: [.init(color: .white.opacity(theme.isDark ? 0.16 : 0.45), location: 0),
                                                 .init(color: .clear, location: 0.42),
                                                 .init(color: .black.opacity(theme.isDark ? 0.18 : 0.06), location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: bodyW, height: h)
                    .allowsHitTesting(false)
                // Polkappe
                RoundedRectangle(cornerRadius: capW * 0.45, style: .continuous)
                    .fill(LinearGradient(colors: [shellTop, shellBottom], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: capW * 0.45, style: .continuous).strokeBorder(edge, lineWidth: 1))
                    .frame(width: capW, height: h * 0.36)
                    .offset(x: bodyW + 3)
                if onAdapter {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: h * 0.30, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .frame(width: bodyW, height: h)
                }
            }
            .frame(width: w, height: h, alignment: .leading)
        }
        .aetherAnimation(Motion.easeOut(0.8), value: percent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var shellTop: Color { theme.isDark ? Color(white: 0.22) : Color(white: 0.97) }
    private var shellBottom: Color { theme.isDark ? Color(white: 0.10) : Color(white: 0.84) }
    private var edge: Color { theme.isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.10) }

    private var accessibilityText: String {
        guard let percent else { return tr("Battery") }
        return tr("Battery charge: %@", fmt.integer(percent) + " %")
    }
}

/// Leuchten hinter der Zelle, nur während macOS „lädt“ meldet. Ebenen-gehostet: Das Pulsieren läuft als
/// Core-Animation im Fensterserver.
private struct ChargeGlow: NSViewRepresentable {
    let configuration: ChargeGlowView.Configuration

    func makeNSView(context: Context) -> ChargeGlowView { ChargeGlowView() }

    func updateNSView(_ view: ChargeGlowView, context: Context) {
        view.configuration = configuration
    }
}

final class ChargeGlowView: NSView {
    struct Configuration: Equatable {
        var color: NSColor
        var corner: CGFloat
        var animated: Bool

        /// Farben über ihre sRGB-Anteile vergleichen (aus SwiftUI erzeugte NSColor-Objekte sind jedes Mal neu).
        static func == (a: Configuration, b: Configuration) -> Bool {
            a.corner == b.corner && a.animated == b.animated && a.colorKey == b.colorKey
        }

        private var colorKey: [Int] {
            guard let c = color.usingColorSpace(.sRGB) else { return [] }
            return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { Int(($0 * 255).rounded()) }
        }
    }

    var configuration: Configuration? {
        didSet { if configuration != oldValue { rebuild() } }
    }

    private let glow = CALayer()
    private var builtSize: CGSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let root = CALayer()
        layer = root
        wantsLayer = true
        root.addSublayer(glow)
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
        glow.removeAllAnimations()
        guard let c = configuration, bounds.width > 30, bounds.height > 30 else {
            glow.isHidden = true
            return
        }
        glow.isHidden = false
        // Der leuchtende Körper liegt hinter der Zelle (14 pt eingerückt); sichtbar ist sein Schatten als Aura.
        let frame = bounds.insetBy(dx: 14, dy: 14)
        glow.frame = frame
        glow.cornerRadius = c.corner
        glow.backgroundColor = c.color.withAlphaComponent(0.35).cgColor
        glow.shadowColor = c.color.cgColor
        glow.shadowOffset = .zero
        glow.shadowRadius = 12
        glow.shadowOpacity = 0.9
        glow.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: frame.size), cornerWidth: c.corner,
                                 cornerHeight: c.corner, transform: nil)
        glow.opacity = c.animated ? 0.35 : 0.7
        guard c.animated else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.3
        pulse.toValue = 1.0
        pulse.duration = 1.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.isRemovedOnCompletion = false
        glow.add(pulse, forKey: "pulse")
    }
}

/// Kein Akku: ruhiger Hinweis statt einer Zelle.
private struct NoBatteryHero: View {
    @Environment(\.aether) private var theme
    let measuring: Bool

    var body: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(theme.fieldFill)
                    .frame(width: 96, height: 96)
                Image(systemName: measuring ? SymbolName.battery : "powerplug")
                    .font(.system(size: 40, weight: .thin))
                    .foregroundStyle(theme.textSecondary)
            }
            if !measuring {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("There is no battery charge to show – power comes from the mains."))
                        .font(Typo.bodyMedium)
                        .foregroundStyle(theme.textPrimary)
                    HStack(spacing: 6) {
                        Text(tr("Reported by macOS"))
                            .font(Typo.caption)
                            .foregroundStyle(theme.textSecondary)
                        ProvenanceBadge(source: .powerSources, reason: .notPresent)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
