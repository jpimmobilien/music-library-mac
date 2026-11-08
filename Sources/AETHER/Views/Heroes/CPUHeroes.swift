import SwiftUI
import AppKit
import AetherCore

// =============================================================================================
// Hero-Visualisierungen für „CPU & GPU“ und „Aktivität“.
//
// Ehrlichkeit: Gehäuse, Anschlüsse und Anordnung des Chips sind Illustration (als „schematisch“ beschriftet).
// Jede leuchtende Kachel ist die gemessene, geglättete Last eines Kerns; der GPU-Block zeigt die vom
// Grafiktreiber gemeldete Auslastung – liefert macOS sie nicht, bleibt er dunkel mit „–“ und Grund.
// Die Prozesslandschaft zeigt die gemessene CPU-Zeit der größten Verbraucher; nichts davon ist geschätzt.
// =============================================================================================

// MARK: - CPU & GPU

/// Kopf der Seite „CPU & GPU“: Chipname als Aussage, darunter der schematische Chip mit der Last je Kern, daneben
/// die großen Zahlen und der Verlauf.
struct CPUStudioHeader: View {
    @ObservedObject var system: SystemStore
    let telemetry: Telemetry
    let gpu: GPUStore

    var body: some View {
        let hw = system.hardware
        let chip = system.profiler?.chip ?? hw.processor?.displayName ?? tr("Processor")
        StudioHero(section: .cpuGPU, eyebrow: tr("CPU & GPU"), headline: chip, lead: lead(hw), height: 330) {
            // SystemStore ändert sich alle 2 s (Eigenverbrauch) – die Bühne nur, wenn sich die Hardware ändert.
            CPUChipHero(hardware: hw, chipName: chip, telemetry: telemetry, gpu: gpu)
                .equatable()
        }
    }

    private func lead(_ hw: HardwareSummary) -> String {
        [coreSummary(hw), architectureDescription(hw)].filter { !$0.isEmpty }.joined(separator: "  ·  ")
    }
}

private struct CPUChipHero: View, Equatable {
    @Environment(\.aether) private var theme
    let hardware: HardwareSummary
    let chipName: String
    let telemetry: Telemetry
    let gpu: GPUStore

    static func == (a: CPUChipHero, b: CPUChipHero) -> Bool {
        a.hardware == b.hardware && a.chipName == b.chipName && a.telemetry === b.telemetry && a.gpu === b.gpu
    }

    var body: some View {
        HStack(alignment: .center, spacing: 34) {
            VStack(alignment: .leading, spacing: 10) {
                ChipDie(cores: telemetry.cores, gpu: gpu, gpuMetric: telemetry.value(.gpu),
                        kinds: hardware.coreKinds ?? [], chipName: chipName, isAppleSilicon: hardware.isAppleSilicon)
                    .frame(width: 250, height: 250)
                SchematicNote()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 250, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 16) {
                figures
                CPUHeroChart(gpu: gpu, telemetry: telemetry)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var figures: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                LiveFigure(metric: telemetry.value(.cpuTotal), label: tr("Total load"), format: FigureFormat.percent,
                           size: .giant, source: .cpuTicks, showPeak: true)
                RawReadout(series: telemetry.series(.cpuTotal), format: { fmt.percent($0) })
            }
            FigureDivider()
            VStack(alignment: .leading, spacing: 12) {
                LiveFigure(metric: telemetry.value(.cpuUser), label: tr("User"), format: FigureFormat.percent,
                           color: theme.cpuUser, size: .small)
                LiveFigure(metric: telemetry.value(.cpuSystem), label: tr("System"), format: FigureFormat.percent,
                           color: theme.cpuSystem, size: .small)
            }
            FigureDivider()
            GPUFigure(store: gpu, telemetry: telemetry, size: .small)
                .frame(maxWidth: 170, alignment: .leading)
            Spacer(minLength: 0)
        }
    }
}

/// Verlauf CPU (und GPU, sofern der Treiber die Auslastung liefert) mit Zeitraumwahl.
private struct CPUHeroChart: View {
    @ObservedObject var gpu: GPUStore
    @Environment(\.aether) private var theme
    @AppStorage("aether.cpu.range") private var range: ChartRange = .fiveMinutes
    let telemetry: Telemetry

    var body: some View {
        let showGPU = gpu.utilization.map { $0.value != nil || $0.reason == .awaitingSecondSample } ?? false
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                SeriesLegend(items: showGPU ? [(tr("CPU"), theme.cpuUser), (tr("GPU"), theme.gpu)]
                                            : [(tr("CPU"), theme.cpuUser)])
                Spacer(minLength: 8)
                RangePicker(range: $range)
            }
            if showGPU {
                LiveChart(series: telemetry.series(.cpuTotal), secondary: telemetry.series(.gpu), range: range,
                          color: theme.cpuUser, secondaryColor: theme.gpu, scale: .fraction, height: 104,
                          label: { fmt.percent($0) })
            } else {
                LiveChart(series: telemetry.series(.cpuTotal), range: range, color: theme.cpuUser, height: 104)
            }
            WindowPeak(series: telemetry.series(.cpuTotal), range: range, format: { fmt.percent($0) })
        }
    }
}

/// Schematischer Chip: Gehäuse, Anschlüsse und Lage der Kacheln sind Illustration. Die Kacheln zeigen die gemessene
/// Last je Kern (Leistungs- und Effizienzkerne getrennt, wo macOS die Kerntypen nennt), der GPU-Block die
/// gemeldete GPU-Auslastung – nur bei einer GPU im Chip (Apple Silicon, integrierte Grafik).
private struct ChipDie: View {
    @Environment(\.aether) private var theme
    @ObservedObject var cores: CoreActivity
    @ObservedObject var gpu: GPUStore
    let gpuMetric: MetricValue
    let kinds: [CoreCluster.Kind]
    let chipName: String
    let isAppleSilicon: Bool

    private struct CoreGroup: Identifiable {
        let id: Int
        let title: String
        let indices: [Int]
        let efficiency: Bool
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let pinLength = side * 0.045
            let dieInset = pinLength + side * 0.055
            let content = side - 2 * dieInset - 2 * side * 0.04
            ZStack {
                // Anschlüsse und Gehäuse (dekorativ)
                ChipPinsShape(perSide: 12, length: pinLength)
                    .fill(Color(white: 0.62).opacity(theme.isDark ? 0.35 : 0.55))
                RoundedRectangle(cornerRadius: side * 0.07, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.08)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: side * 0.07, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                    .padding(pinLength)
                // Die
                RoundedRectangle(cornerRadius: side * 0.04, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.13), Color(white: 0.05)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: side * 0.04, style: .continuous)
                        .fill(LinearGradient(stops: [.init(color: Color.white.opacity(0.08), location: 0),
                                                     .init(color: .clear, location: 0.5)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .overlay(RoundedRectangle(cornerRadius: side * 0.04, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.8))
                    .padding(dieInset)
                dieContent(size: max(10, content))
                    .frame(width: max(10, content), height: max(10, content))
            }
            .frame(width: side, height: side)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aetherAnimation(Motion.easeOut(0.4), value: cores.levels.map { Int((($0 ?? 0) * 50).rounded()) })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// GPU im Chip? Apple Silicon immer; sonst nur integrierte Grafik (eine eigene Grafikkarte sitzt nicht im Chip).
    private var hasOnChipGPU: Bool {
        if let first = gpu.devices.first { return first.hasUnifiedMemory || first.kind == .integrated }
        return isAppleSilicon
    }

    @ViewBuilder
    private func dieContent(size: CGFloat) -> some View {
        let levels = cores.levels
        let groups = coreGroups(count: levels.count)
        let spacing = size * 0.045
        let header = max(8, size * 0.045)
        let gpuHeight = hasOnChipGPU ? size * 0.24 : 0
        let clusterHeight = size - header - spacing - (hasOnChipGPU ? gpuHeight + spacing : 0)
        VStack(alignment: .leading, spacing: spacing) {
            Text(chipName.uppercased())
                .font(.system(size: header, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.42))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(height: header)
            if levels.isEmpty {
                Text(tr("Measuring…"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(width: size, height: clusterHeight)
            } else {
                HStack(spacing: spacing) {
                    ForEach(groups) { group in
                        ClusterBox(levels: group.indices.map { $0 < levels.count ? levels[$0] : nil },
                                   tint: group.efficiency ? theme.memory : theme.cpuUser,
                                   title: group.title,
                                   size: CGSize(width: width(of: group, in: groups, total: size, spacing: spacing),
                                                height: clusterHeight))
                    }
                }
            }
            if hasOnChipGPU {
                GPUBlock(metric: gpuMetric, store: gpu)
                    .frame(width: size, height: gpuHeight)
            }
        }
    }

    private func coreGroups(count: Int) -> [CoreGroup] {
        if kinds.count == count, count > 0 {
            let performance = kinds.indices.filter { kinds[$0] == .performance }
            let efficiency = kinds.indices.filter { kinds[$0] == .efficiency }
            if !performance.isEmpty, !efficiency.isEmpty {
                return [CoreGroup(id: 0, title: tr("Performance cores"), indices: performance, efficiency: false),
                        CoreGroup(id: 1, title: tr("Efficiency cores"), indices: efficiency, efficiency: true)]
            }
        }
        return [CoreGroup(id: 0, title: tr("CPU"), indices: Array(0..<count), efficiency: false)]
    }

    /// Breite je Gruppe nach Kernzahl (mindestens 30 %).
    private func width(of group: CoreGroup, in groups: [CoreGroup], total: CGFloat, spacing: CGFloat) -> CGFloat {
        let available = total - spacing * CGFloat(max(0, groups.count - 1))
        guard groups.count > 1 else { return available }
        let count = Double(groups.reduce(0) { $0 + $1.indices.count })
        let weights = groups.map { max(0.3, Double($0.indices.count) / max(1, count)) }
        let sum = weights.reduce(0, +)
        let index = groups.firstIndex { $0.id == group.id } ?? 0
        return available * CGFloat(weights[index] / sum)
    }

    private var accessibilityText: String {
        let values = cores.levels.compactMap { $0 }
        guard !values.isEmpty, let maximum = values.max() else { return tr("Measuring…") }
        return tr("Load per core: highest %@, average %@", fmt.percent(maximum),
                  fmt.percent(values.reduce(0, +) / Double(values.count)))
    }
}

/// Eine Kerngruppe als Kachelraster.
private struct ClusterBox: View {
    let levels: [Double?]
    let tint: Color
    let title: String
    let size: CGSize

    var body: some View {
        let titleHeight: CGFloat = 11
        let pad: CGFloat = 6
        let gap: CGFloat = 3
        let count = max(1, levels.count)
        let areaWidth = max(4, size.width - 2 * pad)
        let areaHeight = max(4, size.height - titleHeight - 4 - 2 * pad)
        let columns = max(1, min(count, Int(ceil(sqrt(Double(count) * Double(areaWidth / areaHeight))))))
        let rows = Int(ceil(Double(count) / Double(columns)))
        let tile = max(2, min((areaWidth - CGFloat(columns - 1) * gap) / CGFloat(columns),
                              (areaHeight - CGFloat(rows - 1) * gap) / CGFloat(rows)))
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: titleHeight)
            VStack(alignment: .leading, spacing: gap) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            if index < levels.count {
                                CoreTile(level: levels[index], tint: tint)
                                    .frame(width: tile, height: tile)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(pad)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6))
    }
}

/// Ein Kern: Leuchtkraft = gemessene, geglättete Last. Ohne Messwert bleibt die Kachel dunkel.
private struct CoreTile: View {
    let level: Double?
    let tint: Color

    var body: some View {
        let value = min(1, max(0, level ?? 0))
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(level == nil ? Color.white.opacity(0.05) : tint.opacity(0.14 + 0.86 * value))
            .overlay(RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.3 * value), .clear], startPoint: .top, endPoint: .center)))
            .overlay(RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .strokeBorder(tint.opacity(level == nil ? 0.1 : 0.25 + 0.5 * value), lineWidth: 0.5))
    }
}

/// GPU-Block im Chip: Füllung = vom Treiber gemeldete Auslastung; ohne Wert dunkel mit „–“.
private struct GPUBlock: View {
    @ObservedObject var metric: MetricValue
    @ObservedObject var store: GPUStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.aether) private var theme

    var body: some View {
        let reason = unavailableReason
        let value: Double? = reason == nil && metric.isAvailable ? metric.display(raw: settings.showRawValues) : nil
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.035))
                if let value {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LinearGradient(colors: [theme.gpu.opacity(0.35), theme.gpu.opacity(0.9)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, geo.size.width * CGFloat(min(1, max(0, value)))))
                }
                HStack(spacing: 5) {
                    Text("GPU")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                    if let cores = store.devices.first?.coreCount {
                        Text(tr("%ld cores", cores))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                    Spacer(minLength: 4)
                    Text(value.map { fmt.percent($0) } ?? "–")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(value == nil ? 0.4 : 0.9))
                }
                .padding(.horizontal, 7)
            }
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(value == nil ? Color.white.opacity(0.08) : theme.gpu.opacity(0.5), lineWidth: 0.6))
        }
        .help(reason?.explanation ?? tr("GPU utilization as reported by the graphics driver"))
        .aetherAnimation(Motion.easeOut(0.4), value: Int(((value ?? 0) * 100).rounded()))
    }

    /// nil = Wert vorhanden oder in Kürze (zweite Messung)
    private var unavailableReason: UnavailableReason? {
        guard let utilization = store.utilization else { return store.devicesLoaded ? .notProvidedByMacOS : nil }
        guard utilization.value == nil, let reason = utilization.reason, reason != .awaitingSecondSample else { return nil }
        return reason
    }
}

/// Anschlüsse rund um das Gehäuse (dekorativ).
private struct ChipPinsShape: Shape {
    let perSide: Int
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let side = min(rect.width, rect.height)
        let span = side * 0.72
        let start = (side - span) / 2
        let step = span / CGFloat(max(1, perSide - 1))
        let pinWidth = max(1.5, step * 0.38)
        for i in 0..<perSide {
            let offset = start + CGFloat(i) * step - pinWidth / 2
            path.addRoundedRect(in: CGRect(x: rect.minX + offset, y: rect.minY, width: pinWidth, height: length + 2),
                                cornerSize: CGSize(width: 0.8, height: 0.8))
            path.addRoundedRect(in: CGRect(x: rect.minX + offset, y: rect.minY + side - length - 2, width: pinWidth, height: length + 2),
                                cornerSize: CGSize(width: 0.8, height: 0.8))
            path.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY + offset, width: length + 2, height: pinWidth),
                                cornerSize: CGSize(width: 0.8, height: 0.8))
            path.addRoundedRect(in: CGRect(x: rect.minX + side - length - 2, y: rect.minY + offset, width: length + 2, height: pinWidth),
                                cornerSize: CGSize(width: 0.8, height: 0.8))
        }
        return path
    }
}

// MARK: - Aktivität

/// Prozesslandschaft: die größten CPU-Verbraucher als Lichtsäulen (Höhe = gemessene, geglättete CPU-Zeit,
/// Anteil eines Kerns), darunter der Speicher als feiner Balken. Klick wählt den Prozess im Inspektor.
struct ProcessLandscapeHero: View {
    @ObservedObject var store: ProcessStore
    @Environment(\.aether) private var theme
    let selected: Int32?
    let onSelect: (Int32) -> Void

    private let towerHeight: CGFloat = 104

    var body: some View {
        let top = store.top(by: \ProcessRow.cpuSort, limit: 12).filter { ($0.cpu ?? 0) >= 0.001 }
        let scale = max(1, top.compactMap(\.cpu).max() ?? 0)
        let maxMemory = Double(top.compactMap(\.memory).max() ?? 0)
        VStack(alignment: .leading, spacing: 10) {
            if !store.loaded {
                placeholder(tr("Measuring…"))
            } else if top.isEmpty {
                placeholder(tr("No process is using measurable CPU time right now."))
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(top) { row in
                        column(row, level: level(row, scale: scale),
                               memory: maxMemory > 0 ? row.memory.map { Double($0) / maxMemory } : nil)
                    }
                }
                .frame(maxWidth: .infinity)
                .aetherAnimation(Motion.easeOut(0.35), value: top.map { "\($0.pid):\(Int(level($0, scale: scale) * 100))" })
                HStack(spacing: 14) {
                    SeriesLegend(items: [(tr("CPU (share of one core, smoothed)"), theme.cpuUser), (tr("Memory"), theme.memory)])
                    Spacer(minLength: 8)
                    Text(tr("Full height = %@ of one core", fmt.percent(scale)))
                        .font(StudioType.caption)
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
    }

    /// Auf 1 % gerundet – die Säulen bewegen sich nur bei sichtbarer Änderung.
    private func level(_ row: ProcessRow, scale: Double) -> Double {
        (min(1, max(0, (row.cpu ?? 0) / scale)) * 100).rounded() / 100
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(Typo.callout)
            .foregroundStyle(theme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func column(_ row: ProcessRow, level: Double, memory: Double?) -> some View {
        let isSelected = selected == row.pid
        let cpu = row.cpu ?? 0
        return Button {
            onSelect(row.pid)
        } label: {
            VStack(spacing: 5) {
                Text(fmt.percent(cpu, fractionDigits: cpu < 0.1 ? 1 : 0))
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(theme.cpuUser.opacity(0.08))
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LinearGradient(colors: [theme.cpuUser.opacity(0.55 + 0.45 * level), theme.cpuUser.opacity(0.22)],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(alignment: .top) {
                            Capsule()
                                .fill(Color.white.opacity(0.45 * level))
                                .frame(height: 3)
                                .padding(.horizontal, 4)
                                .padding(.top, 2)
                        }
                        .frame(height: max(4, towerHeight * CGFloat(level)))
                }
                .frame(width: 26, height: towerHeight)
                Capsule()
                    .fill(theme.fieldFill)
                    .frame(width: 34, height: 3)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(theme.memory)
                            .frame(width: 34 * CGFloat(min(1, max(0, memory ?? 0))), height: 3)
                    }
                Image(nsImage: IconCache.icon(pid: row.pid, bundlePath: row.bundlePath))
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(row.name)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 74)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.selectionFill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tr("%@ – CPU %@, memory %@", row.name, fmt.percent(cpu, fractionDigits: 1),
                 row.memory.map { fmt.bytes($0, style: .memory) } ?? "–"))
        .accessibilityLabel(tr("%@ – CPU %@, memory %@", row.name, fmt.percent(cpu, fractionDigits: 1),
                               row.memory.map { fmt.bytes($0, style: .memory) } ?? "–"))
    }
}
