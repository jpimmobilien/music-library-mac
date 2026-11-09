import SwiftUI
import AetherCore

// =============================================================================================
// Übersicht „Studio“ – Bühne, Live-Leiste und Module.
//
// Ehrlichkeit: Jede Zahl, Linie, Säule und jeder Datenstrom kommt aus einer Messung (Telemetry). Die
// Gerätesilhouette ist als Illustration beschriftet; fehlt ein Wert, steht „–“ mit dem Grund.
// Leistung: Jede Ansicht beobachtet nur, was sie zeigt. Große Zahlen ändern sich nur bei sichtbarer Änderung,
// Diagramme rücken einmal je Messung weiter, Datenströme laufen im Fensterserver.
// =============================================================================================

// MARK: - Bühne

/// Gerätebühne: links Rechenleistung, Mitte das Gerät mit der Last je Kern auf dem Bildschirm und den Datenströmen,
/// rechts Arbeitsspeicher und Netzwerk.
struct OverviewStage: View {
    @ObservedObject var system: SystemStore
    let telemetry: Telemetry
    let gpu: GPUStore

    var body: some View {
        // SystemStore ändert sich alle 2 s (Eigenverbrauch) – die Bühne nur, wenn sich die Hardware ändert.
        StageContent(hardware: system.hardware, telemetry: telemetry, gpu: gpu)
            .equatable()
    }
}

private struct StageContent: View, Equatable {
    @EnvironmentObject private var model: AppModel
    @Environment(\.aether) private var theme
    let hardware: HardwareSummary
    let telemetry: Telemetry
    let gpu: GPUStore

    static func == (a: StageContent, b: StageContent) -> Bool {
        a.hardware == b.hardware && a.telemetry === b.telemetry && a.gpu === b.gpu
    }

    var body: some View {
        ZStack {
            StageLight(color: theme.accent)
                .padding(.horizontal, -Spacing.gutter)
                .padding(.vertical, -36)
            HStack(alignment: .center, spacing: 28) {
                leftColumn
                    .frame(width: 196, alignment: .leading)
                centerColumn
                    .frame(maxWidth: .infinity)
                rightColumn
                    .frame(width: 214, alignment: .leading)
            }
        }
        .frame(height: 372)
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 26) {
            InteractiveVisual(action: { model.select(.cpuGPU) }) {
                VStack(alignment: .leading, spacing: 4) {
                    LiveFigure(metric: telemetry.value(.cpuTotal), label: tr("CPU"), format: FigureFormat.percent,
                               size: .giant, source: .cpuTicks, showPeak: true)
                    RawReadout(series: telemetry.series(.cpuTotal), format: { fmt.percent($0) })
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            InteractiveVisual(action: { model.select(.cpuGPU) }) {
                GPUFigure(store: gpu, telemetry: telemetry, size: .small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var centerColumn: some View {
        VStack(spacing: 12) {
            InteractiveVisual(hint: tr("Cores"), action: { model.select(.cpuGPU) }) {
                DeviceArt(model: hardware.macModel, kind: hardware.kind) {
                    CoreScreen(cores: telemetry.cores, kinds: hardware.coreKinds ?? [])
                }
                .frame(height: 246)
            }
            InteractiveVisual(hint: tr("Network"), action: { model.select(.network) }) {
                NetworkLanes(down: telemetry.value(.networkDown, unit: .bytesPerSecond),
                             up: telemetry.value(.networkUp, unit: .bytesPerSecond))
                    .frame(height: 30)
                    .padding(.horizontal, 24)
            }
            HStack(spacing: 14) {
                Label(illustrationCaption, systemImage: "info.circle")
                    .labelStyle(.titleAndIcon)
                if let kinds = hardware.coreKinds, kinds.contains(.efficiency), kinds.contains(.performance) {
                    legendDot(theme.cpuUser, tr("Performance"))
                    legendDot(theme.cpuUser.opacity(0.55), tr("Efficiency"))
                }
            }
            .font(StudioType.caption)
            .foregroundStyle(theme.textTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 26) {
            InteractiveVisual(action: { model.select(.memory) }) {
                VStack(alignment: .leading, spacing: 4) {
                    LiveFigure(metric: telemetry.value(.memoryUsed, unit: .bytes), label: tr("Memory used"),
                               format: FigureFormat.bytes, size: .figure, source: .vmStatistics)
                    if let physical = hardware.physicalMemory {
                        Text(tr("of %@", fmt.bytes(physical, style: .memory)))
                            .font(StudioType.caption)
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            InteractiveVisual(action: { model.select(.network) }) {
                VStack(alignment: .leading, spacing: 14) {
                    LiveFigure(metric: telemetry.value(.networkDown, unit: .bytesPerSecond), label: "↓ " + tr("Download"),
                               format: FigureFormat.rate, color: theme.networkDown, size: .small, source: .interfaceCounters,
                               showPeak: true)
                    LiveFigure(metric: telemetry.value(.networkUp, unit: .bytesPerSecond), label: "↑ " + tr("Upload"),
                               format: FigureFormat.rate, color: theme.networkUp, size: .small, source: .interfaceCounters,
                               showPeak: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var illustrationCaption: String {
        guard let model = hardware.macModel else {
            return tr("Illustration – the screen shows the measured load of each core.")
        }
        return tr("Illustration of %@ – the screen shows the measured load of each core.", model.displayName)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(color).frame(width: 4, height: 10)
            Text(label)
        }
    }
}

/// Bildschirminhalt des Geräts: gemessene Last je Kern.
private struct CoreScreen: View {
    @ObservedObject var cores: CoreActivity
    @Environment(\.aether) private var theme
    let kinds: [CoreCluster.Kind]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.08, blue: 0.13), Color(red: 0.02, green: 0.02, blue: 0.05)],
                           startPoint: .top, endPoint: .bottom)
            if cores.levels.isEmpty {
                Text(tr("Measuring…"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(tr("Load per core"))
                        Spacer()
                        Text(tr("%ld cores", cores.levels.count))
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
                    CoreLights(levels: cores.levels, kinds: kinds, color: theme.cpuUser,
                               efficiencyColor: theme.cpuUser.opacity(0.55))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let values = cores.levels.compactMap { $0 }
        guard !values.isEmpty, let maximum = values.max() else { return tr("Measuring…") }
        return tr("Load per core: highest %@, average %@", fmt.percent(maximum),
                  fmt.percent(values.reduce(0, +) / Double(values.count)))
    }
}

/// Zwei Datenströme: ↓ und ↑ – Dichte und Tempo folgen dem gemessenen Durchsatz.
private struct NetworkLanes: View {
    @ObservedObject var down: MetricValue
    @ObservedObject var up: MetricValue
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.aether) private var theme

    var body: some View {
        VStack(spacing: 6) {
            lane(symbol: "arrow.down", rate: rate(down), color: theme.networkDown, forward: true)
            lane(symbol: "arrow.up", rate: rate(up), color: theme.networkUp, forward: false)
        }
        .help(tr("Data streams: density and speed follow the measured network throughput. No traffic, no particles."))
    }

    private func rate(_ metric: MetricValue) -> Double? {
        metric.isAvailable ? metric.display(raw: settings.showRawValues) : nil
    }

    private func lane(symbol: String, rate: Double?, color: Color, forward: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 12)
            FlowStream(rate: rate, color: color, forward: forward, thickness: 2.5)
                .frame(height: 10)
        }
    }
}

/// GPU-Auslastung – nur wenn macOS sie liefert, sonst „–“ mit Grund.
struct GPUFigure: View {
    @ObservedObject var store: GPUStore
    let telemetry: Telemetry
    var size: BigFigure.FigureSize = .figure

    var body: some View {
        if let utilization = store.utilization {
            if utilization.value == nil, let reason = utilization.reason, reason != .awaitingSecondSample {
                BigFigure(label: tr("GPU"), value: "–", detail: reason.explanation, size: size, source: utilization.source,
                          reason: reason)
            } else {
                LiveFigure(metric: telemetry.value(.gpu), label: tr("GPU"), format: FigureFormat.percent, size: size,
                           source: utilization.source, showPeak: true)
            }
        } else if store.devicesLoaded {
            BigFigure(label: tr("GPU"), value: "–", detail: UnavailableReason.notProvidedByMacOS.explanation, size: size,
                      source: .gpuStatistics, reason: .notProvidedByMacOS)
        } else {
            BigFigure(label: tr("GPU"), value: "–", detail: tr("Measuring…"), size: size)
        }
    }
}

// MARK: - Live-Leiste

/// Aktuelle Werte als ruhige Kacheln mit dem Verlauf der letzten Minute. Klick öffnet den Bereich.
struct LiveStrip: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.aether) private var theme
    @ObservedObject var power: PowerStore
    @ObservedObject var gpu: GPUStore
    @ObservedObject var system: SystemStore
    let telemetry: Telemetry

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("Live"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Label(settings.showRawValues ? tr("Raw values – exactly as measured")
                                             : tr("Smoothed values – peaks stay visible"),
                      systemImage: settings.showRawValues ? "waveform.path" : "waveform.path.ecg")
                    .font(Typo.callout)
                    .foregroundStyle(theme.textSecondary)
                    .help(tr("Large numbers are smoothed so they don’t flicker; peaks stay visible. Settings → Monitoring switches to raw values."))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 320), spacing: 12, alignment: .top)],
                      alignment: .leading, spacing: 12) {
                ForEach(specs) { spec in
                    LiveTile(spec: spec, metric: telemetry.value(spec.id, unit: spec.unit),
                             series: telemetry.series(spec.id, unit: spec.unit))
                        .equatable()
                }
            }
        }
    }

    private var specs: [TileSpec] {
        var list: [TileSpec] = [
            TileSpec(id: .cpuTotal, title: tr("CPU"), symbol: "cpu", unit: .fraction, scale: .fraction,
                     color: theme.cpuUser, section: .cpuGPU, unavailable: nil),
        ]
        let gpuReason: UnavailableReason? = {
            guard let utilization = gpu.utilization else { return gpu.devicesLoaded ? .notProvidedByMacOS : nil }
            guard utilization.value == nil, let reason = utilization.reason, reason != .awaitingSecondSample else { return nil }
            return reason
        }()
        list.append(TileSpec(id: .gpu, title: tr("GPU"), symbol: "cube.transparent", unit: .fraction, scale: .fraction,
                             color: theme.gpu, section: .cpuGPU, unavailable: gpuReason))
        let physical = Double(system.hardware.physicalMemory ?? 0)
        list.append(TileSpec(id: .memoryUsed, title: tr("Memory"), symbol: "memorychip", unit: .bytes,
                             scale: physical > 0 ? .fixed(physical) : .auto(minimum: 1_000_000_000),
                             color: theme.memory, section: .memory, unavailable: nil))
        list.append(TileSpec(id: .networkDown, title: tr("Download"), symbol: "arrow.down", unit: .bytesPerSecond,
                             scale: .auto(minimum: 10_000), color: theme.networkDown, section: .network, unavailable: nil))
        list.append(TileSpec(id: .networkUp, title: tr("Upload"), symbol: "arrow.up", unit: .bytesPerSecond,
                             scale: .auto(minimum: 10_000), color: theme.networkUp, section: .network, unavailable: nil))
        if let sensors = power.thermal?.sensors {
            let reason: UnavailableReason? = (sensors.value?.isEmpty ?? true) ? (sensors.reason ?? .notProvidedByMacOS) : nil
            list.append(TileSpec(id: .hottest, title: tr("Hottest sensor"), symbol: "thermometer.medium", unit: .celsius,
                                 scale: .auto(minimum: 60), color: theme.thermal, section: .thermal, unavailable: reason))
        }
        if let battery = power.battery, battery.isPresent {
            list.append(TileSpec(id: .batteryPercent, title: tr("Battery"), symbol: SymbolName.battery, unit: .percentInteger,
                                 scale: .fixed(100), color: theme.battery, section: .battery,
                                 unavailable: battery.percent.value == nil ? (battery.percent.reason ?? .queryFailed) : nil))
        }
        return list
    }
}

/// Beschreibung einer Kachel (vergleichbar – Kacheln zeichnen sich nur neu, wenn sich ihre Messgröße ändert).
struct TileSpec: Equatable, Identifiable {
    let id: MetricID
    let title: String
    let symbol: String
    let unit: MetricUnit
    let scale: TileScale
    let color: Color
    let section: AppSection
    let unavailable: UnavailableReason?

    enum TileScale: Equatable {
        case fraction
        case fixed(Double)
        case auto(minimum: Double)

        var chartScale: ChartScale {
            switch self {
            case .fraction: return .fraction
            case .fixed(let value): return .fixed(value)
            case .auto(let minimum): return .auto(minimum: minimum)
            }
        }
    }

    func parts(_ value: Double) -> (value: String, unit: String) {
        switch unit {
        case .fraction: return FigureFormat.percent(value)
        case .bytes: return FigureFormat.bytes(value)
        case .bytesPerSecond: return FigureFormat.rate(value)
        case .celsius: return FigureFormat.celsius(value)
        case .rpm: return FigureFormat.rpm(value)
        case .watts: return FigureFormat.watts(value)
        case .percentInteger: return FigureFormat.percentInteger(value)
        }
    }

    func text(_ value: Double) -> String {
        let p = parts(value)
        return p.unit.isEmpty ? p.value : p.value + " " + p.unit
    }
}

private struct LiveTile: View, Equatable {
    @EnvironmentObject private var model: AppModel
    @Environment(\.aether) private var theme
    let spec: TileSpec
    let metric: MetricValue
    let series: MetricSeries

    static func == (a: LiveTile, b: LiveTile) -> Bool {
        a.spec == b.spec && a.metric === b.metric && a.series === b.series
    }

    var body: some View {
        InteractiveVisual(action: { model.select(spec.section) }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: spec.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(spec.color)
                    Text(spec.title)
                        .font(StudioType.label)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                TileValue(metric: metric, spec: spec)
                if spec.unavailable == nil {
                    LiveChart(series: series, range: .oneMinute, color: spec.color, scale: spec.scale.chartScale, height: 30,
                              showsBand: false, showsAxis: false, label: { spec.text($0) })
                } else {
                    Spacer(minLength: 30)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .glassSurface(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }
}

private struct TileValue: View {
    @ObservedObject var metric: MetricValue
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.aether) private var theme
    let spec: TileSpec

    var body: some View {
        if let reason = spec.unavailable {
            VStack(alignment: .leading, spacing: 2) {
                Text("–").font(.system(size: 24, weight: .semibold)).foregroundStyle(theme.textTertiary)
                Text(tr("Not available")).font(StudioType.caption).foregroundStyle(theme.textTertiary)
            }
            .help(reason.explanation)
        } else if metric.isAvailable, let value = metric.display(raw: settings.showRawValues) {
            let parts = spec.parts(value)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(parts.value)
                    .font(.system(size: 24, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                Text(parts.unit)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: spec.title + " " + spec.text(value)))
        } else {
            Text("–")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
                .help(UnavailableReason.awaitingSecondSample.explanation)
        }
    }
}

// MARK: - Module

/// Module der Übersicht – Reihenfolge und Sichtbarkeit wie in „Übersicht anpassen“.
struct OverviewModules: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.aether) private var theme
    @Binding var range: ChartRange

    var body: some View {
        let visible = settings.dashboard.visible
        // GPU steckt im CPU-Modul, solange beide sichtbar sind
        let cards = visible.filter { !($0 == .gpu && visible.contains(.cpu)) }
        VStack(alignment: .leading, spacing: Spacing.l) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("History"))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(tr("Line: smoothed value · band: lowest to highest measured value"))
                        .font(Typo.callout)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
                RangePicker(range: $range)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 18, alignment: .top)],
                      alignment: .leading, spacing: 18) {
                ForEach(cards) { card in
                    module(card, gpuVisible: visible.contains(.gpu))
                }
            }
            .aetherAnimation(Motion.spring, value: settings.dashboard)
        }
    }

    @ViewBuilder
    private func module(_ card: DashboardCard, gpuVisible: Bool) -> some View {
        let engine = model.engine
        switch card {
        case .cpu: CPUModule(telemetry: engine.telemetry, system: engine.system, gpu: engine.gpu, showGPU: gpuVisible, range: range)
        case .gpu: GPUModule(telemetry: engine.telemetry, gpu: engine.gpu, range: range)
        case .memory: MemoryModule(store: engine.memory, telemetry: engine.telemetry, range: range)
        case .thermal: ThermalModule(store: engine.power, telemetry: engine.telemetry, range: range)
        case .battery: BatteryModule(store: engine.power, telemetry: engine.telemetry, range: range)
        case .network: NetworkModule(store: engine.network, telemetry: engine.telemetry, range: range)
        case .storage: StorageModule(store: engine.storage, telemetry: engine.telemetry)
        case .thisMac: ThisMacModule(system: engine.system)
        }
    }
}

/// Rahmen eines Moduls: Überzeile in der Bereichsfarbe, Inhalt, ganzflächig anklickbar.
struct StudioModule<Content: View>: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.aether) private var theme
    let section: AppSection
    let title: String
    let symbol: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        InteractiveVisual(action: { model.select(section) }) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 7) {
                    Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                    Text(title).font(StudioType.eyebrow).tracking(0.3)
                }
                .foregroundStyle(section.tint(theme))
                content()
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 290, alignment: .topLeading)
            .glassSurface(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        }
    }
}

/// „Höchstwert der letzten … : …“ aus den Rohwerten.
struct WindowPeak: View {
    @ObservedObject var series: MetricSeries
    @Environment(\.aether) private var theme
    let range: ChartRange
    let format: (Double) -> String

    var body: some View {
        if let peak = series.raw.maximum(window: range.seconds, now: series.now) {
            Text(tr("Highest in the last %@: %@", rangeName(range), format(peak)))
                .font(StudioType.caption)
                .monospacedDigit()
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
        }
    }
}

/// Kleine Legende für Diagramme mit zwei Linien.
struct SeriesLegend: View {
    @Environment(\.aether) private var theme
    let items: [(label: String, color: Color)]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(items.indices, id: \.self) { index in
                HStack(spacing: 5) {
                    Capsule().fill(items[index].color).frame(width: 12, height: 3)
                    Text(items[index].label)
                }
            }
        }
        .font(StudioType.caption)
        .foregroundStyle(theme.textSecondary)
    }
}

private struct CPUModule: View {
    @Environment(\.aether) private var theme
    let telemetry: Telemetry
    @ObservedObject var system: SystemStore
    let gpu: GPUStore
    let showGPU: Bool
    let range: ChartRange

    var body: some View {
        StudioModule(section: .cpuGPU, title: showGPU ? tr("CPU & GPU") : tr("CPU"), symbol: "cpu") {
            HStack(alignment: .top, spacing: 26) {
                LiveFigure(metric: telemetry.value(.cpuTotal), label: tr("CPU"), format: FigureFormat.percent,
                           source: .cpuTicks, showPeak: true)
                if showGPU {
                    FigureDivider()
                    GPUFigure(store: gpu, telemetry: telemetry)
                }
                Spacer(minLength: 0)
            }
            if showGPU {
                LiveChart(series: telemetry.series(.cpuTotal), secondary: telemetry.series(.gpu), range: range,
                          color: theme.cpuUser, secondaryColor: theme.gpu, scale: .fraction, height: 120,
                          label: { fmt.percent($0) })
                SeriesLegend(items: [(tr("CPU"), theme.cpuUser), (tr("GPU"), theme.gpu)])
            } else {
                LiveChart(series: telemetry.series(.cpuTotal), range: range, color: theme.cpuUser, height: 120)
            }
            HStack(spacing: 8) {
                Text(coreSummary(system.hardware))
                    .font(StudioType.caption)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                WindowPeak(series: telemetry.series(.cpuTotal), range: range, format: { fmt.percent($0) })
            }
        }
    }
}

private struct GPUModule: View {
    @Environment(\.aether) private var theme
    let telemetry: Telemetry
    let gpu: GPUStore
    let range: ChartRange

    var body: some View {
        StudioModule(section: .cpuGPU, title: tr("GPU"), symbol: "cube.transparent") {
            GPUFigure(store: gpu, telemetry: telemetry)
            LiveChart(series: telemetry.series(.gpu), range: range, color: theme.gpu, height: 120)
            WindowPeak(series: telemetry.series(.gpu), range: range, format: { fmt.percent($0) })
        }
    }
}

private struct MemoryModule: View {
    @Environment(\.aether) private var theme
    @ObservedObject var store: MemoryStore
    let telemetry: Telemetry
    let range: ChartRange

    var body: some View {
        StudioModule(section: .memory, title: tr("Memory"), symbol: "memorychip") {
            let snapshot = store.snapshot
            HStack(alignment: .top, spacing: 26) {
                LiveFigure(metric: telemetry.value(.memoryUsed, unit: .bytes), label: tr("Used"), format: FigureFormat.bytes,
                           source: .vmStatistics)
                FigureDivider()
                if let level = snapshot?.pressure.value {
                    BigFigure(label: tr("Memory pressure"), value: pressureName(level), color: theme.color(for: level),
                              size: .small, source: .memoryPressure)
                } else {
                    BigFigure(label: tr("Memory pressure"), value: "–", size: .small, source: .memoryPressure,
                              reason: snapshot?.pressure.reason ?? .awaitingSecondSample)
                }
                FigureDivider()
                if let swap = snapshot?.swap.value {
                    let parts = fmt.byteParts(Double(swap.used), style: .memory)
                    BigFigure(label: tr("Swap"), value: parts.value, unit: parts.unit, size: .small, source: .swapUsage)
                } else {
                    BigFigure(label: tr("Swap"), value: "–", size: .small, source: .swapUsage,
                              reason: snapshot?.swap.reason ?? .awaitingSecondSample)
                }
                Spacer(minLength: 0)
            }
            if let b = snapshot?.breakdown.value {
                let total = Double(max(b.physical, 1))
                VStack(alignment: .leading, spacing: 8) {
                    SegmentedBar(segments: [(Double(b.app) / total, theme.memory),
                                            (Double(b.wired) / total, theme.memoryWired),
                                            (Double(b.compressed) / total, theme.memoryCompressed),
                                            (Double(b.cached) / total, theme.memoryCached)],
                                 height: 12)
                    HStack(spacing: 14) {
                        LegendItem(color: theme.memory, label: tr("App"), value: fmt.bytes(b.app, style: .memory))
                        LegendItem(color: theme.memoryWired, label: tr("Wired"), value: fmt.bytes(b.wired, style: .memory))
                        LegendItem(color: theme.memoryCompressed, label: tr("Compressed"),
                                   value: fmt.bytes(b.compressed, style: .memory))
                        LegendItem(color: theme.memoryCached, label: tr("Cached"), value: fmt.bytes(b.cached, style: .memory))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
                LiveChart(series: telemetry.series(.memoryUsed, unit: .bytes), range: range, color: theme.memory,
                          scale: .fixed(Double(b.physical)), height: 80, label: { fmt.bytes($0, style: .memory) })
            } else if let breakdown = snapshot?.breakdown {
                UnavailableValue(reason: breakdown.reason ?? .queryFailed, source: breakdown.source)
            }
        }
    }
}

private struct ThermalModule: View {
    @Environment(\.aether) private var theme
    @ObservedObject var store: PowerStore
    let telemetry: Telemetry
    let range: ChartRange

    var body: some View {
        StudioModule(section: .thermal, title: tr("Thermal"), symbol: "thermometer.medium") {
            let thermal = store.thermal
            let sensors = thermal?.sensors
            let hasSensors = !(sensors?.value?.isEmpty ?? true)
            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Text(tr("Thermal state")).font(StudioType.label).foregroundStyle(theme.textSecondary)
                        ProvenanceBadge(source: .thermalState, reason: thermal?.state.reason)
                    }
                    if let level = thermal?.state.value {
                        Text(thermalShortName(level))
                            .font(StudioType.figure)
                            .foregroundStyle(theme.color(for: level))
                        ThermalSteps(level: level)
                    } else {
                        Text("–").font(StudioType.figure).foregroundStyle(theme.textTertiary)
                    }
                    Text(tr("reported by macOS")).font(StudioType.caption).foregroundStyle(theme.textTertiary)
                }
                FigureDivider()
                if hasSensors {
                    VStack(alignment: .leading, spacing: 2) {
                        LiveFigure(metric: telemetry.value(.hottest, unit: .celsius), label: tr("Hottest sensor"),
                                   format: FigureFormat.celsius, source: .smcSensors)
                        if let key = thermal?.hottest?.key {
                            Text(key).font(Typo.mono).foregroundStyle(theme.textTertiary)
                        }
                    }
                } else if let sensors {
                    let reason = sensors.reason ?? .notProvidedByMacOS
                    BigFigure(label: tr("Sensor temperatures"), value: "–", detail: reason.explanation, size: .small,
                              source: sensors.source, reason: reason)
                        .frame(maxWidth: 220, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            if hasSensors {
                LiveChart(series: telemetry.series(.hottest, unit: .celsius), range: range, color: theme.thermal,
                          scale: .auto(minimum: 60), height: 90, label: { fmt.celsius($0) })
            }
            fans(thermal?.fans)
        }
    }

    @ViewBuilder
    private func fans(_ fans: Reading<[FanReading]>?) -> some View {
        if let fans {
            if let list = fans.value {
                if list.isEmpty {
                    Label(tr("No fans – passively cooled"), systemImage: "wind")
                        .font(Typo.callout)
                        .foregroundStyle(theme.textSecondary)
                } else {
                    HStack(alignment: .top, spacing: 22) {
                        ForEach(list) { fan in
                            LiveFigure(metric: telemetry.value(.fan(fan.index), unit: .rpm),
                                       label: list.count > 1 ? tr("Fan %ld", fan.index + 1) : tr("Fan"),
                                       format: FigureFormat.rpm, size: .small, source: .smcFans)
                        }
                        Spacer(minLength: 0)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Text(tr("Fans")).font(Typo.callout).foregroundStyle(theme.textSecondary)
                    UnavailableValue(reason: fans.reason ?? .queryFailed, source: fans.source, compact: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// Vier Stufen des Thermalstatus von macOS.
private struct ThermalSteps: View {
    @Environment(\.aether) private var theme
    let level: ThermalLevel

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(ThermalLevel.allCases, id: \.self) { step in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(step <= level ? theme.color(for: level) : theme.fieldFill)
                    .frame(width: 18, height: 5)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct BatteryModule: View {
    @Environment(\.aether) private var theme
    @ObservedObject var store: PowerStore
    let telemetry: Telemetry
    let range: ChartRange

    var body: some View {
        StudioModule(section: .battery, title: tr("Battery"), symbol: SymbolName.battery) {
            if let b = store.battery {
                if b.isPresent {
                    present(b)
                } else {
                    HStack(spacing: Spacing.m) {
                        Image(systemName: "powerplug")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(theme.textSecondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tr("No battery")).font(StudioType.small).foregroundStyle(theme.textPrimary)
                            Text(tr("This Mac runs on mains power.")).font(Typo.callout).foregroundStyle(theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                        ProvenanceBadge(source: .powerSources, reason: .notPresent)
                    }
                }
            } else {
                Text(tr("Measuring…")).font(Typo.callout).foregroundStyle(theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func present(_ b: BatterySnapshot) -> some View {
        let percent = b.percent.value
        HStack(alignment: .center, spacing: 26) {
            ZStack {
                ArcMeter(fraction: percent.map { Double($0) / 100 }, color: theme.batteryColor(percent: percent ?? 100),
                         lineWidth: 9)
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(percent.map { fmt.integer($0) } ?? "–")
                            .font(StudioType.figure)
                            .monospacedDigit()
                            .foregroundStyle(percent == nil ? theme.textTertiary : theme.textPrimary)
                        if percent != nil {
                            Text("%").font(StudioType.figureUnit).foregroundStyle(theme.textSecondary)
                        }
                    }
                    Image(systemName: b.powerSource == .ac ? "bolt.fill" : SymbolName.battery)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .frame(width: 118, height: 118)
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 7) {
                Text(batteryChargeState(b)).font(Typo.bodyMedium).foregroundStyle(theme.textPrimary)
                if let time = batteryTimeReading(b) {
                    if let minutes = time.reading.value {
                        let text = fmt.duration(seconds: Double(minutes) * 60)
                        HStack(spacing: 4) {
                            Text(time.charging ? tr("Full in %@", text) : tr("%@ remaining", text))
                            ProvenanceBadge(source: time.reading.source, timestamp: time.reading.timestamp)
                        }
                        .font(Typo.callout)
                        .foregroundStyle(theme.textSecondary)
                    } else if time.reading.reason == .awaitingSecondSample {
                        Text(tr("macOS is still calculating the remaining time"))
                            .font(Typo.callout).foregroundStyle(theme.textSecondary)
                    }
                }
                if let watts = b.adapterWatts.value, b.powerSource == .ac {
                    Text(tr("Power adapter: %ld W", watts)).font(Typo.callout).foregroundStyle(theme.textSecondary)
                }
                if let cycles = b.cycleCount.value {
                    Text(tr("%ld charge cycles", cycles)).font(Typo.callout).foregroundStyle(theme.textSecondary)
                }
                if let health = b.computedHealth.value {
                    Text(tr("Capacity (computed): %@", fmt.percent(health, fractionDigits: 1)))
                        .font(Typo.callout).foregroundStyle(theme.textSecondary)
                }
                if let condition = b.systemCondition {
                    Text(tr("Condition (macOS): %@", condition))
                        .font(Typo.callout)
                        .foregroundStyle(b.serviceRecommended == true ? theme.statusElevated : theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        LiveChart(series: telemetry.series(.batteryPercent, unit: .percentInteger), range: range, color: theme.battery,
                  scale: .fixed(100), height: 60, label: { fmt.integer(Int($0.rounded())) + " %" })
    }
}

private struct NetworkModule: View {
    @Environment(\.aether) private var theme
    @ObservedObject var store: NetworkStore
    let telemetry: Telemetry
    let range: ChartRange

    var body: some View {
        StudioModule(section: .network, title: tr("Network"), symbol: "network") {
            HStack(alignment: .top, spacing: 26) {
                LiveFigure(metric: telemetry.value(.networkDown, unit: .bytesPerSecond), label: "↓ " + tr("Download"),
                           format: FigureFormat.rate, source: .interfaceCounters, showPeak: true)
                FigureDivider()
                LiveFigure(metric: telemetry.value(.networkUp, unit: .bytesPerSecond), label: "↑ " + tr("Upload"),
                           format: FigureFormat.rate, source: .interfaceCounters, showPeak: true)
                Spacer(minLength: 0)
            }
            LiveChart(series: telemetry.series(.networkDown, unit: .bytesPerSecond),
                      secondary: telemetry.series(.networkUp, unit: .bytesPerSecond), range: range,
                      color: theme.networkDown, secondaryColor: theme.networkUp, scale: .auto(minimum: 10_000), height: 110,
                      label: { fmt.rate($0) })
            HStack(spacing: 10) {
                SeriesLegend(items: [(tr("Download"), theme.networkDown), (tr("Upload"), theme.networkUp)])
                Spacer(minLength: 8)
                if let snapshot = store.snapshot {
                    Text(tr("Since start: ↓ %@ · ↑ %@", fmt.bytes(snapshot.sessionDownloaded), fmt.bytes(snapshot.sessionUploaded)))
                        .font(StudioType.caption)
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    if !snapshot.activeInterfaces.isEmpty {
                        Text(snapshot.activeInterfaces.joined(separator: ", "))
                            .font(Typo.mono)
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                            .help(tr("Counted interfaces: only network adapters with a routable address – internal connections (e.g. to the T2 chip) are excluded."))
                    }
                }
            }
        }
    }
}

private struct StorageModule: View {
    @Environment(\.aether) private var theme
    @ObservedObject var store: StorageStore
    let telemetry: Telemetry

    var body: some View {
        StudioModule(section: .storage, title: tr("Storage"), symbol: "internaldrive") {
            if let startup = store.snapshot?.startup {
                let available = fmt.byteParts(Double(startup.effectiveAvailable))
                HStack(alignment: .top, spacing: 26) {
                    BigFigure(label: startup.name, value: available.value, unit: available.unit,
                              detail: tr("available · %@ of %@ used", fmt.bytes(startup.used), fmt.bytes(startup.capacity)),
                              source: .volumes)
                    FigureDivider()
                    LiveFigure(metric: telemetry.value(.diskRead, unit: .bytesPerSecond), label: tr("Read"),
                               format: FigureFormat.rate, size: .small, source: .blockStorage, showPeak: true)
                    LiveFigure(metric: telemetry.value(.diskWrite, unit: .bytesPerSecond), label: tr("Write"),
                               format: FigureFormat.rate, size: .small, source: .blockStorage, showPeak: true)
                    Spacer(minLength: 0)
                }
                volumeBar(startup)
                let others = (store.snapshot?.volumes ?? []).filter { !$0.isRoot }.prefix(3)
                if !others.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(Array(others)) { volume in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: volume.isNetwork ? "server.rack"
                                                      : (volume.isRemovable ? "externaldrive" : "internaldrive"))
                                        .font(.system(size: 10))
                                        .foregroundStyle(theme.textSecondary)
                                    Text(volume.name).font(Typo.callout).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Text(tr("%@ available", fmt.bytes(volume.effectiveAvailable)))
                                        .font(StudioType.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(theme.textSecondary)
                                }
                                FillBar(fraction: volume.usedFraction,
                                        color: volume.usedFraction > 0.9 ? theme.statusElevated : theme.storage, height: 4)
                            }
                        }
                    }
                }
            } else {
                Text(tr("Measuring…")).font(Typo.callout).foregroundStyle(theme.textSecondary)
            }
        }
    }

    /// Belegt · löschbar (zählt als verfügbar) · frei.
    private func volumeBar(_ v: VolumeInfo) -> some View {
        let capacity = Double(max(v.capacity, 1))
        let purgeable = Double(v.purgeable ?? 0)
        return VStack(alignment: .leading, spacing: 8) {
            SegmentedBar(segments: [(Double(v.used) / capacity, v.usedFraction > 0.9 ? theme.statusElevated : theme.storage),
                                    (purgeable / capacity, theme.storage.opacity(0.35))],
                         height: 12)
            HStack(spacing: 14) {
                LegendItem(color: theme.storage, label: tr("Used"), value: fmt.bytes(v.used))
                if purgeable > 0 {
                    LegendItem(color: theme.storage.opacity(0.35), label: tr("Purgeable"), value: fmt.bytes(Int64(purgeable)))
                        .help(tr("Space macOS frees up automatically when needed (e.g. caches, local snapshots)."))
                }
                LegendItem(color: theme.fieldFill, label: tr("Free"), value: fmt.bytes(v.available))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }
}

private struct ThisMacModule: View {
    @Environment(\.aether) private var theme
    @ObservedObject var system: SystemStore

    var body: some View {
        let hw = system.hardware
        StudioModule(section: .hardware, title: tr("This Mac"), symbol: deviceSymbol(hw.kind)) {
            HStack(alignment: .center, spacing: Spacing.l) {
                Image(systemName: deviceSymbol(hw.kind))
                    .font(.system(size: 40, weight: .thin))
                    .foregroundStyle(theme.accent)
                    .frame(width: 60)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hw.machineName ?? hw.modelIdentifier ?? "Mac").font(StudioType.small).lineLimit(1)
                    Text(hw.modelIdentifier ?? "").font(Typo.mono).foregroundStyle(theme.textTertiary)
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 6) {
                InfoRow(label: tr("Chip"), value: system.profiler?.chip ?? hw.processor?.displayName ?? "–", source: .hardwareSysctl)
                if let memory = hw.physicalMemory {
                    InfoRow(label: tr("Memory"), value: fmt.bytes(memory, style: .memory))
                }
                InfoRow(label: tr("Architecture"), value: architectureDescription(hw),
                        valueColor: hw.isTranslated ? theme.statusElevated : nil)
                if let os = hw.osVersion {
                    InfoRow(label: "macOS", value: hw.osBuild.map { "\(os) (\($0))" } ?? os, source: .osVersion)
                }
                if let own = system.ownUsage {
                    InfoRow(label: tr("AETHER itself"),
                            value: [own.cpu.map { fmt.percent($0, fractionDigits: 1) }, own.footprint.map { fmt.bytes($0, style: .memory) }]
                                .compactMap { $0 }.joined(separator: " · "))
                }
            }
        }
    }
}
