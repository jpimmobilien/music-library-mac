import SwiftUI
import AetherCore
import AetherSystem

/// CPU & GPU: Gesamtlast mit Verlauf, jeder Kern (nach Kerntyp gruppiert, wo verlässlich bekannt), größte Verbraucher,
/// Prozessorangaben und Grafikprozessoren.
struct CPUGPUView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.aether) private var theme

    var body: some View {
        let engine = model.engine
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: theme.density.cardSpacing + 4) {
                PageHeader(title: tr("CPU & GPU"), subtitle: processorSubtitle(engine.system.hardware, engine.system.profiler))
                CPUTotalPanel(store: engine.cpu, interval: settings.effectiveInterval.seconds)
                CoresPanel(store: engine.cpu, system: engine.system)
                HStack(alignment: .top, spacing: theme.density.cardSpacing) {
                    TopProcessesPanel(store: engine.processes, metric: .cpu)
                    ProcessorDetailsPanel(system: engine.system)
                }
                GPUPanel(store: engine.gpu, interval: settings.effectiveInterval.seconds)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.gutter)
        }
    }
}

func processorSubtitle(_ hw: HardwareSummary, _ profiler: ProfilerHardware?) -> String {
    var parts: [String] = []
    if let name = profiler?.chip ?? hw.processor?.displayName { parts.append(name) }
    let cores = coreSummary(hw)
    if !cores.isEmpty { parts.append(cores) }
    return parts.joined(separator: "  ·  ")
}

private struct CPUTotalPanel: View {
    @ObservedObject var store: CPUStore
    let interval: Double
    @Environment(\.aether) private var theme

    var body: some View {
        let total = store.snapshot?.total
        let usage = total?.value
        Panel {
            PanelTitle(title: tr("Total load"), symbol: "cpu",
                       trailing: store.peak.map { tr("Peak since start: %@", fmt.percent($0)) })
            HStack(alignment: .center, spacing: Spacing.xxl) {
                MetricRing(segments: [(usage?.user ?? 0, theme.cpuUser), (usage?.system ?? 0, theme.cpuSystem)],
                           lineWidth: 11, size: 116, unavailable: usage == nil) {
                    if let usage {
                        let parts = percentParts(usage.busy)
                        ValueText(value: parts.value, unit: parts.unit, font: Typo.metricLarge)
                    } else {
                        Text("–").font(Typo.metricLarge).foregroundStyle(theme.textTertiary)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    LegendItem(color: theme.cpuUser, label: tr("User"), value: usage.map { fmt.percent($0.user, fractionDigits: 1) } ?? "–")
                    LegendItem(color: theme.cpuSystem, label: tr("System"), value: usage.map { fmt.percent($0.system, fractionDigits: 1) } ?? "–")
                    LegendItem(color: theme.fieldFill, label: tr("Idle"), value: usage.map { fmt.percent($0.idle, fractionDigits: 1) } ?? "–")
                    if let load = store.snapshot?.loadAverage.value, load.count == 3 {
                        HStack(spacing: 6) {
                            Text(tr("Load average")).font(Typo.caption).foregroundStyle(theme.textSecondary)
                            Text(load.map { fmt.number($0, fractionDigits: 2) }.joined(separator: " · "))
                                .font(Typo.captionMedium).monospacedDigit()
                            ProvenanceBadge(source: .loadAverage)
                        }
                        .help(tr("Average number of runnable threads over 1, 5 and 15 minutes."))
                    }
                    if let total {
                        HStack(spacing: 6) {
                            Text(tr("Source")).font(Typo.caption).foregroundStyle(theme.textSecondary)
                            ProvenanceBadge(source: total.source, timestamp: total.timestamp, reason: total.reason)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            HistoryChart(series: [.init(values: store.longBusy.elements, color: theme.cpuUser),
                                  .init(values: store.longSystem.elements, color: theme.cpuSystem)],
                         capacity: detailCapacity, maxValue: 1, height: 130,
                         label: { fmt.percent($0) },
                         spanLabel: historySpanLabel(samples: detailCapacity, interval: interval))
        }
    }
}

private struct CoresPanel: View {
    @ObservedObject var store: CPUStore
    @ObservedObject var system: SystemStore
    @Environment(\.aether) private var theme

    var body: some View {
        let perCore = store.snapshot?.perCore ?? []
        let kinds = system.hardware.coreKinds
        Panel {
            PanelTitle(title: tr("Cores"), symbol: "square.grid.3x3",
                       trailing: perCore.isEmpty ? nil : tr("%ld logical cores", perCore.count))
            if perCore.isEmpty {
                Text(tr("Measuring…")).font(Typo.callout).foregroundStyle(theme.textSecondary)
            } else if let kinds, kinds.count == perCore.count {
                ForEach(coreGroups(kinds)) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Circle().fill(group.isPerformance ? theme.cpuUser : theme.memory).frame(width: 7, height: 7)
                            Text(group.isPerformance ? tr("Performance cores") : tr("Efficiency cores"))
                                .font(Typo.captionMedium).foregroundStyle(theme.textSecondary)
                            Text(average(group.indices, perCore)).font(Typo.caption).foregroundStyle(theme.textTertiary).monospacedDigit()
                        }
                        coreRow(group.indices, perCore, tint: group.isPerformance ? theme.cpuUser : theme.memory)
                    }
                }
                Text(tr("Core types from the device tree (IORegistry). Red share: system."))
                    .font(Typo.caption).foregroundStyle(theme.textTertiary)
            } else {
                coreRow(Array(perCore.indices), perCore, tint: theme.cpuUser)
                Text(system.hardware.hasHyperThreading
                     ? tr("Logical cores: each physical core runs two threads (Hyper-Threading). Red share: system.")
                     : (system.hardware.isAppleSilicon
                        ? tr("macOS doesn’t reveal which logical core is a performance or efficiency core on this Mac. Red share: system.")
                        : tr("Red share: system.")))
                    .font(Typo.caption).foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private struct CoreGroup: Identifiable {
        let isPerformance: Bool
        let indices: [Int]
        var id: Bool { isPerformance }
    }

    private func coreGroups(_ kinds: [CoreCluster.Kind]) -> [CoreGroup] {
        let performance = kinds.indices.filter { kinds[$0] == CoreCluster.Kind.performance }
        let efficiency = kinds.indices.filter { kinds[$0] == CoreCluster.Kind.efficiency }
        var groups: [CoreGroup] = []
        if !performance.isEmpty { groups.append(CoreGroup(isPerformance: true, indices: performance)) }
        if !efficiency.isEmpty { groups.append(CoreGroup(isPerformance: false, indices: efficiency)) }
        return groups
    }

    private func coreRow(_ indices: [Int], _ perCore: [CPUUsage?], tint: Color) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(indices, id: \.self) { index in
                    CoreBar(index: index, usage: index < perCore.count ? perCore[index] : nil, tint: tint)
                }
            }
        }
    }

    private func average(_ indices: [Int], _ perCore: [CPUUsage?]) -> String {
        let values = indices.compactMap { $0 < perCore.count ? perCore[$0]?.busy : nil }
        guard !values.isEmpty else { return "" }
        return tr("Ø %@", fmt.percent(values.reduce(0, +) / Double(values.count)))
    }
}

/// Größte Verbraucher (CPU oder Speicher) aus der Prozessliste.
struct TopProcessesPanel: View {
    enum Metric { case cpu, memory }
    @ObservedObject var store: ProcessStore
    let metric: Metric
    @EnvironmentObject private var model: AppModel
    @Environment(\.aether) private var theme

    var body: some View {
        let top = store.top(by: metric == .cpu ? \ProcessRow.cpuSort : \ProcessRow.memorySort, limit: 8)
        Panel {
            PanelTitle(title: metric == .cpu ? tr("Top processes by CPU") : tr("Top processes by memory"), symbol: SymbolName.process)
            if !store.loaded {
                Text(tr("Measuring…")).font(Typo.callout).foregroundStyle(theme.textSecondary)
            } else if top.isEmpty {
                Text(tr("No values available")).font(Typo.callout).foregroundStyle(theme.textSecondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(top) { row in
                        Button {
                            model.focusProcess(row.pid)
                        } label: {
                            HStack(spacing: 8) {
                                Image(nsImage: IconCache.icon(pid: row.pid, bundlePath: row.bundlePath))
                                    .resizable().frame(width: 18, height: 18)
                                Text(row.name).font(Typo.callout).lineLimit(1)
                                Spacer(minLength: 6)
                                Text(value(row)).font(Typo.callout.weight(.medium)).monospacedDigit()
                                    .foregroundStyle(metric == .memory && row.source == .ps ? theme.textSecondary : theme.textPrimary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(row.path ?? row.name)
                    }
                }
                if metric == .memory {
                    Text(tr("Memory of your own processes as in Activity Monitor; for other users’ processes the resident memory (RSS)."))
                        .font(Typo.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(tr("Share of one core – a process can use more than 100 %."))
                        .font(Typo.caption).foregroundStyle(theme.textTertiary)
                }
            }
        }
    }

    private func value(_ row: ProcessRow) -> String {
        switch metric {
        case .cpu: return row.cpu.map { fmt.percent($0, fractionDigits: 1) } ?? "–"
        case .memory: return row.memory.map { fmt.bytes($0, style: .memory) } ?? "–"
        }
    }
}

private struct ProcessorDetailsPanel: View {
    @ObservedObject var system: SystemStore
    @Environment(\.aether) private var theme

    var body: some View {
        let hw = system.hardware
        Panel {
            PanelTitle(title: tr("Processor"), symbol: "info.circle")
            VStack(spacing: 6) {
                InfoRow(label: tr("Model"), value: system.profiler?.chip ?? hw.processor?.displayName ?? "–", source: .hardwareSysctl)
                InfoRow(label: tr("Architecture"), value: hw.isAppleSilicon ? tr("Apple Silicon (arm64)") : tr("Intel (x86_64)"))
                if let p = hw.physicalCores { InfoRow(label: tr("Physical cores"), value: "\(p)") }
                if let l = hw.logicalCores { InfoRow(label: tr("Logical cores"), value: "\(l)") }
                ForEach(Array(hw.clusters.enumerated()), id: \.offset) { _, cluster in
                    if cluster.kind != .uniform {
                        InfoRow(label: cluster.kind == .performance ? tr("Performance cores") : tr("Efficiency cores"),
                                value: "\(cluster.physicalCores)", source: .cpuTopology)
                    }
                }
                if hw.hasHyperThreading { InfoRow(label: "Hyper-Threading", value: tr("On")) }
                if let l1 = hw.cacheL1Data { InfoRow(label: tr("L1 data cache"), value: fmt.bytes(UInt64(l1), style: .memory)) }
                if let l1i = hw.cacheL1Instruction { InfoRow(label: tr("L1 instruction cache"), value: fmt.bytes(UInt64(l1i), style: .memory)) }
                if let l2 = hw.cacheL2 { InfoRow(label: tr("L2 cache"), value: fmt.bytes(UInt64(l2), style: .memory)) }
                if let l3 = hw.cacheL3 { InfoRow(label: tr("L3 cache"), value: fmt.bytes(UInt64(l3), style: .memory)) }
                if let hz = hw.nominalFrequency {
                    InfoRow(label: tr("Nominal clock"), value: fmt.number(Double(hz) / 1_000_000_000, fractionDigits: 2) + ValueFormatter.unitSpace + "GHz",
                            source: .hardwareSysctl)
                }
                HStack {
                    Text(tr("Current clock")).font(Typo.callout).foregroundStyle(theme.textSecondary)
                    Spacer()
                    UnavailableValue(reason: .requiresAdministrator, source: DataSource(id: "cpu.clock", api: "powermetrics (Root)", provenance: .measured), compact: true)
                }
            }
        }
    }
}

private struct GPUPanel: View {
    @ObservedObject var store: GPUStore
    let interval: Double
    @Environment(\.aether) private var theme

    var body: some View {
        Panel {
            PanelTitle(title: tr("Graphics"), symbol: SymbolName.gpu,
                       trailing: store.devices.count > 1 ? tr("%ld graphics processors", store.devices.count) : nil)
            if !store.devicesLoaded {
                Text(tr("Measuring…")).font(Typo.callout).foregroundStyle(theme.textSecondary)
            } else if store.devices.isEmpty {
                HStack {
                    Text(store.devicesFailed ? tr("System Information couldn’t be read.") : tr("No graphics processor reported"))
                        .font(Typo.callout).foregroundStyle(theme.textSecondary)
                    Spacer()
                    ProvenanceBadge(source: .gpuDevices, reason: store.devicesFailed ? .queryFailed : .notPresent)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: Spacing.m, alignment: .top)], spacing: Spacing.m) {
                    ForEach(store.devices) { device in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(device.name).font(Typo.bodyMedium).lineLimit(1)
                            if let vendor = device.vendor { InfoRow(label: tr("Vendor"), value: vendor) }
                            InfoRow(label: tr("Type"), value: kindName(device))
                            if let cores = device.coreCount { InfoRow(label: tr("GPU cores"), value: "\(cores)") }
                            if let vram = device.vram { InfoRow(label: tr("Graphics memory"), value: vram) }
                            if device.hasUnifiedMemory {
                                InfoRow(label: tr("Memory"), value: tr("Unified memory"))
                            }
                            if let metal = device.metalSupport { InfoRow(label: "Metal", value: metal) }
                            InfoRow(label: tr("Connected displays"), value: "\(device.displayCount)", source: .gpuDevices)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).fill(theme.fieldFill))
                    }
                }
            }
            Divider().overlay(theme.hairline)
            if let utilization = store.utilization, let value = utilization.value {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    let parts = percentParts(value)
                    ValueText(value: parts.value, unit: parts.unit, font: Typo.metric)
                    Text(tr("utilization (driver)")).font(Typo.caption).foregroundStyle(theme.textSecondary)
                    Spacer()
                    ProvenanceBadge(source: utilization.source, timestamp: utilization.timestamp)
                }
                HistoryChart(series: [.init(values: store.longHistory.elements, color: theme.gpu)], capacity: detailCapacity,
                             maxValue: 1, height: 90, label: { fmt.percent($0) },
                             spanLabel: historySpanLabel(samples: detailCapacity, interval: interval))
            } else {
                HStack {
                    Text(tr("Utilization")).font(Typo.callout).foregroundStyle(theme.textSecondary)
                    Spacer()
                    UnavailableValue(reason: store.utilization?.reason ?? .notProvidedByMacOS, source: .gpuStatistics, compact: true)
                }
                Text(tr("The utilization comes from the graphics driver. Not every driver reports it – AETHER never estimates it."))
                    .font(Typo.caption).foregroundStyle(theme.textTertiary)
            }
        }
    }

    private func kindName(_ d: GPUDevice) -> String {
        if d.hasUnifiedMemory { return tr("Integrated (system on a chip)") }
        switch d.kind {
        case .integrated: return tr("Integrated")
        case .discrete: return tr("Dedicated")
        case .external: return tr("External")
        case .unknown: return tr("Unknown")
        }
    }
}
