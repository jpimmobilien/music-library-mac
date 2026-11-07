import SwiftUI
import AetherCore
import AetherSystem

/// Prozentwert getrennt in Zahl und Einheit.
func percentParts(_ fraction: Double) -> (value: String, unit: String) {
    (fmt.number(fraction * 100, fractionDigits: 0), "%")
}

// MARK: - CPU

struct CPUCard: View {
    @ObservedObject var store: CPUStore
    @ObservedObject var system: SystemStore
    @Environment(\.aether) private var theme
    let action: () -> Void

    var body: some View {
        let total = store.snapshot?.total
        let usage = total?.value
        Card(title: tr("CPU"), symbol: "cpu", tint: theme.cpuUser, action: action) {
            HStack(alignment: .center, spacing: Spacing.l) {
                MetricRing(segments: [(usage?.user ?? 0, theme.cpuUser), (usage?.system ?? 0, theme.cpuSystem)],
                           unavailable: usage == nil) {
                    if let usage {
                        let parts = percentParts(usage.busy)
                        ValueText(value: parts.value, unit: parts.unit, font: Typo.metric)
                    } else {
                        Text("–").font(Typo.metric).foregroundStyle(theme.textTertiary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    LegendItem(color: theme.cpuUser, label: tr("User"), value: usage.map { fmt.percent($0.user) } ?? "–")
                    LegendItem(color: theme.cpuSystem, label: tr("System"), value: usage.map { fmt.percent($0.system) } ?? "–")
                    LegendItem(color: theme.fieldFill, label: tr("Idle"), value: usage.map { fmt.percent($0.idle) } ?? "–")
                    if let peak = store.peak {
                        Text(tr("Peak since start: %@", fmt.percent(peak)))
                            .font(Typo.caption).foregroundStyle(theme.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            Sparkline(values: store.busyHistory.elements, color: theme.cpuUser, capacity: sparklineCapacity)
                .frame(height: 34)
            HStack(spacing: 6) {
                Text(coreSummary(system.hardware))
                    .font(Typo.caption).foregroundStyle(theme.textSecondary).lineLimit(1)
                Spacer(minLength: 0)
                if let load = store.snapshot?.loadAverage.value, load.count == 3 {
                    Text(tr("Load %@", load.map { fmt.number($0, fractionDigits: 2) }.joined(separator: " · ")))
                        .font(Typo.caption).monospacedDigit().foregroundStyle(theme.textTertiary).lineLimit(1)
                }
                if let total {
                    ProvenanceBadge(source: total.source, timestamp: total.timestamp, reason: total.reason)
                }
            }
        }
    }
}

func coreSummary(_ hw: HardwareSummary) -> String {
    let performance = hw.clusters.filter { $0.kind == .performance }.reduce(0) { $0 + $1.physicalCores }
    let efficiency = hw.clusters.filter { $0.kind == .efficiency }.reduce(0) { $0 + $1.physicalCores }
    if hw.isAppleSilicon, performance > 0, efficiency > 0 {
        return tr("%ld performance + %ld efficiency cores", performance, efficiency)
    }
    if let physical = hw.physicalCores, let logical = hw.logicalCores {
        if hw.hasHyperThreading { return tr("%ld cores · %ld threads (Hyper-Threading)", physical, logical) }
        return tr("%ld cores", physical)
    }
    return ""
}

// MARK: - Arbeitsspeicher

struct MemoryCard: View {
    @ObservedObject var store: MemoryStore
    @ObservedObject var system: SystemStore
    @Environment(\.aether) private var theme
    let action: () -> Void

    var body: some View {
        let breakdown = store.snapshot?.breakdown
        let pressure = store.snapshot?.pressure
        Card(title: tr("Memory"), symbol: "memorychip", tint: theme.memory, action: action) {
            if let b = breakdown?.value {
                let used = fmt.byteParts(Double(b.used), style: .memory)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    ValueText(value: used.value, unit: used.unit)
                    Text(tr("of %@", fmt.bytes(b.physical, style: .memory)))
                        .font(Typo.callout).foregroundStyle(theme.textSecondary)
                    Spacer(minLength: 0)
                    if let level = pressure?.value {
                        Chip(text: pressureName(level), color: theme.color(for: level))
                            .help(tr("Memory pressure as reported by macOS"))
                    }
                }
                let total = Double(max(b.physical, 1))
                SegmentedBar(segments: [(Double(b.app) / total, theme.memory),
                                        (Double(b.wired) / total, theme.memoryWired),
                                        (Double(b.compressed) / total, theme.memoryCompressed),
                                        (Double(b.cached) / total, theme.memoryCached)])
                Grid(alignment: .leading, horizontalSpacing: Spacing.l, verticalSpacing: 4) {
                    GridRow {
                        LegendItem(color: theme.memory, label: tr("App"), value: fmt.bytes(b.app, style: .memory))
                        LegendItem(color: theme.memoryWired, label: tr("Wired"), value: fmt.bytes(b.wired, style: .memory))
                    }
                    GridRow {
                        LegendItem(color: theme.memoryCompressed, label: tr("Compressed"), value: fmt.bytes(b.compressed, style: .memory))
                        LegendItem(color: theme.memoryCached, label: tr("Cached"), value: fmt.bytes(b.cached, style: .memory))
                    }
                }
            } else if let breakdown {
                UnavailableValue(reason: breakdown.reason ?? .queryFailed, source: breakdown.source)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if let swap = store.snapshot?.swap.value {
                    Text(tr("Swap used: %@", fmt.bytes(swap.used, style: .memory)))
                        .font(Typo.caption).foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 0)
                if system.hardware.isAppleSilicon {
                    Text(tr("Unified memory"))
                        .font(Typo.caption).foregroundStyle(theme.textTertiary)
                        .help(tr("Shared by CPU, GPU and Neural Engine – there is no separate graphics memory."))
                }
                if let breakdown {
                    ProvenanceBadge(source: breakdown.source, timestamp: breakdown.timestamp, reason: breakdown.reason)
                }
            }
        }
    }
}

// MARK: - Thermik

struct ThermalCard: View {
    @ObservedObject var store: PowerStore
    @Environment(\.aether) private var theme
    let action: () -> Void

    var body: some View {
        let state = store.thermal?.state
        Card(title: tr("Thermal"), symbol: "thermometer.medium", tint: theme.thermal, action: action) {
            HStack(alignment: .center, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: 3) {
                    if let level = state?.value {
                        Text(thermalShortName(level))
                            .font(Typo.metric)
                            .foregroundStyle(theme.color(for: level))
                    } else if let state {
                        UnavailableValue(reason: state.reason ?? .queryFailed, source: state.source)
                    } else {
                        Text("–").font(Typo.metric).foregroundStyle(theme.textTertiary)
                    }
                    Text(tr("Thermal state reported by macOS"))
                        .font(Typo.caption).foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 0)
                ThermalGauge(level: state?.value)
            }
            Divider().overlay(theme.hairline)
            if let battery = store.thermal?.batteryTemperature {
                if let celsius = battery.value {
                    InfoRow(label: tr("Battery"), value: fmt.celsius(celsius), source: battery.source, timestamp: battery.timestamp)
                } else {
                    HStack {
                        Text(tr("Battery")).font(Typo.callout).foregroundStyle(theme.textSecondary)
                        Spacer()
                        UnavailableValue(reason: battery.reason ?? .queryFailed, source: battery.source, compact: true)
                    }
                }
            }
            if let hottest = store.thermal?.hottest, let sensors = store.thermal?.sensors {
                InfoRow(label: tr("Hottest sensor (%@)", hottest.key), value: fmt.celsius(hottest.celsius),
                        source: sensors.source, timestamp: sensors.timestamp)
            }
            if let fans = store.thermal?.fans {
                if let list = fans.value {
                    InfoRow(label: tr("Fans"),
                            value: list.isEmpty ? tr("None (passively cooled)")
                                                : list.map { fmt.integer(Int($0.rpm.rounded())) }.joined(separator: " · ") + " " + tr("rpm"),
                            source: fans.source, timestamp: fans.timestamp)
                } else {
                    HStack {
                        Text(tr("Fans")).font(Typo.callout).foregroundStyle(theme.textSecondary)
                        Spacer()
                        UnavailableValue(reason: fans.reason ?? .queryFailed, source: fans.source, compact: true)
                    }
                }
            }
        }
    }
}

/// Vier Stufen des Thermalstatus als ruhige Skala.
private struct ThermalGauge: View {
    @Environment(\.aether) private var theme
    let level: ThermalLevel?

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(ThermalLevel.allCases, id: \.self) { step in
                let active = level.map { step <= $0 } ?? false
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(active ? theme.color(for: level ?? .nominal) : theme.fieldFill)
                    .frame(width: 8, height: 12 + CGFloat(step.rawValue) * 8)
            }
        }
        .accessibilityHidden(true)
        .aetherAnimation(Motion.easeOut(), value: level)
    }
}

// MARK: - Batterie

struct BatteryCard: View {
    @ObservedObject var store: PowerStore
    @Environment(\.aether) private var theme
    let action: () -> Void

    var body: some View {
        Card(title: tr("Battery"), symbol: SymbolName.battery, tint: theme.battery, action: action) {
            if let battery = store.battery {
                if battery.isPresent {
                    present(battery)
                } else {
                    noBattery(battery)
                }
            } else {
                Text(tr("Measuring…")).font(Typo.metricSmall).foregroundStyle(theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func present(_ b: BatterySnapshot) -> some View {
        HStack(alignment: .center, spacing: Spacing.l) {
            let percent = b.percent.value
            MetricRing(segments: [(Double(percent ?? 0) / 100, theme.batteryColor(percent: percent ?? 100))],
                       unavailable: percent == nil) {
                if let percent {
                    ValueText(value: fmt.number(Double(percent), fractionDigits: 0), unit: "%", font: Typo.metric)
                } else {
                    Text("–").font(Typo.metric).foregroundStyle(theme.textTertiary)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Label(chargeState(b), systemImage: b.powerSource == .ac ? "bolt.fill" : SymbolName.batteryLow)
                    .font(Typo.bodyMedium)
                    .foregroundStyle(theme.textPrimary)
                if let minutes = (b.isCharging == true ? b.minutesToFull : b.minutesToEmpty).value {
                    HStack(spacing: 4) {
                        Text(b.isCharging == true ? tr("Full in %@", fmt.duration(seconds: Double(minutes) * 60))
                                                  : tr("%@ remaining", fmt.duration(seconds: Double(minutes) * 60)))
                            .font(Typo.caption).foregroundStyle(theme.textSecondary)
                        ProvenanceBadge(source: .batteryTimeRemaining, timestamp: b.minutesToEmpty.timestamp)
                    }
                }
                if let watts = b.adapterWatts.value, b.powerSource == .ac {
                    Text(tr("Power adapter: %ld W", watts)).font(Typo.caption).foregroundStyle(theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        Divider().overlay(theme.hairline)
        VStack(spacing: 5) {
            if let cycles = b.cycleCount.value {
                InfoRow(label: tr("Charge cycles"), value: fmt.integer(cycles), source: b.cycleCount.source, timestamp: b.cycleCount.timestamp)
            }
            if let health = b.computedHealth.value {
                InfoRow(label: tr("Capacity (computed)"), value: fmt.percent(health, fractionDigits: 1),
                        source: b.computedHealth.source, timestamp: b.computedHealth.timestamp)
            }
            if let condition = b.systemCondition {
                InfoRow(label: tr("Condition (macOS)"), value: condition, source: .powerSources,
                        valueColor: b.serviceRecommended == true ? theme.statusElevated : nil)
            }
        }
    }

    @ViewBuilder
    private func noBattery(_ b: BatterySnapshot) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "powerplug")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(tr("No battery")).font(Typo.metricSmall)
                Text(tr("This Mac runs on mains power."))
                    .font(Typo.caption).foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 0)
            ProvenanceBadge(source: .powerSources, timestamp: b.percent.timestamp, reason: .notPresent)
        }
    }

    private func chargeState(_ b: BatterySnapshot) -> String { batteryChargeState(b) }
}

// MARK: - Netzwerk

struct NetworkCard: View {
    @ObservedObject var store: NetworkStore
    @Environment(\.aether) private var theme
    let action: () -> Void

    var body: some View {
        let snapshot = store.snapshot
        Card(title: tr("Network"), symbol: "network", tint: theme.networkDown, action: action) {
            HStack(spacing: Spacing.xl) {
                rate(symbol: "arrow.down", color: theme.networkDown, reading: snapshot?.download, label: tr("Download"))
                rate(symbol: "arrow.up", color: theme.networkUp, reading: snapshot?.upload, label: tr("Upload"))
                Spacer(minLength: 0)
            }
            let down = store.downHistory.elements
            let up = store.upHistory.elements
            let scale = max(down.max() ?? 0, up.max() ?? 0, 1_000)
            ZStack {
                Sparkline(values: down, color: theme.networkDown, capacity: sparklineCapacity, scaleMax: scale)
                Sparkline(values: up, color: theme.networkUp, capacity: sparklineCapacity, fill: false, lineWidth: 1.2, scaleMax: scale)
            }
            .frame(height: 34)
            HStack(spacing: 6) {
                if let snapshot {
                    Text(tr("Since start: ↓ %@ · ↑ %@", fmt.bytes(snapshot.sessionDownloaded), fmt.bytes(snapshot.sessionUploaded)))
                        .font(Typo.caption).monospacedDigit().foregroundStyle(theme.textSecondary).lineLimit(1)
                    Spacer(minLength: 0)
                    if !snapshot.activeInterfaces.isEmpty {
                        Text(snapshot.activeInterfaces.joined(separator: ", "))
                            .font(Typo.mono).foregroundStyle(theme.textTertiary).lineLimit(1)
                    }
                    ProvenanceBadge(source: snapshot.download.source, timestamp: snapshot.download.timestamp, reason: snapshot.download.reason)
                }
            }
        }
    }

    private func rate(symbol: String, color: Color, reading: Reading<Double>?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
                Text(label).font(Typo.caption).foregroundStyle(theme.textSecondary)
            }
            if let value = reading?.value {
                let parts = fmt.rateParts(value)
                ValueText(value: parts.value, unit: parts.unit, font: Typo.metric)
            } else {
                Text("–").font(Typo.metric).foregroundStyle(theme.textTertiary)
            }
        }
    }
}

// MARK: - Speicher

struct StorageCard: View {
    @ObservedObject var store: StorageStore
    @Environment(\.aether) private var theme
    let action: () -> Void

    var body: some View {
        let snapshot = store.snapshot
        Card(title: tr("Storage"), symbol: "internaldrive", tint: theme.storage, action: action) {
            if let startup = snapshot?.startup {
                volumeRow(startup, prominent: true)
            } else {
                Text(tr("Measuring…")).font(Typo.metricSmall).foregroundStyle(theme.textSecondary)
            }
            let others = (snapshot?.volumes ?? []).filter { !$0.isRoot }.prefix(3)
            if !others.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(others)) { volume in volumeRow(volume, prominent: false) }
                }
            }
            Spacer(minLength: 0)
            if let snapshot {
                HStack(spacing: Spacing.m) {
                    Label(snapshot.readRate.value.map { fmt.rate($0) } ?? "–", systemImage: "arrow.down.doc")
                    Label(snapshot.writeRate.value.map { fmt.rate($0) } ?? "–", systemImage: "arrow.up.doc")
                    Spacer(minLength: 0)
                    ProvenanceBadge(source: snapshot.readRate.source, timestamp: snapshot.readRate.timestamp, reason: snapshot.readRate.reason)
                }
                .font(Typo.caption)
                .monospacedDigit()
                .foregroundStyle(theme.textSecondary)
                .help(tr("Disk activity: read and write rate of all disks"))
            }
        }
    }

    @ViewBuilder
    private func volumeRow(_ v: VolumeInfo, prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: prominent ? 7 : 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: v.isNetwork ? "server.rack" : (v.isRemovable ? "externaldrive" : "internaldrive"))
                    .font(.system(size: prominent ? 12 : 10))
                    .foregroundStyle(theme.textSecondary)
                Text(v.name).font(prominent ? Typo.bodyMedium : Typo.callout).lineLimit(1)
                if let format = v.format, prominent {
                    Text(format).font(Typo.caption).foregroundStyle(theme.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(tr("%@ available", fmt.bytes(v.effectiveAvailable)))
                    .font(prominent ? Typo.callout.weight(.medium) : Typo.caption)
                    .monospacedDigit()
                    .foregroundStyle(prominent ? theme.textPrimary : theme.textSecondary)
                    .lineLimit(1)
            }
            FillBar(fraction: v.usedFraction, color: v.usedFraction > 0.9 ? theme.statusElevated : theme.storage,
                    height: prominent ? 9 : 5)
            if prominent {
                HStack(spacing: 6) {
                    Text(tr("%@ of %@ used", fmt.bytes(v.used), fmt.bytes(v.capacity)))
                    if let purgeable = v.purgeable, purgeable > 0 {
                        Text("·")
                        // Löschbarer Platz zählt zum verfügbaren, nicht zum belegten Platz.
                        Text(tr("available incl. %@ purgeable", fmt.bytes(purgeable)))
                            .help(tr("Space macOS frees up automatically when needed (e.g. caches, local snapshots)."))
                    }
                    Spacer(minLength: 0)
                    ProvenanceBadge(source: .volumes)
                }
                .font(Typo.caption).monospacedDigit().foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
        }
    }
}

// MARK: - GPU

struct GPUCard: View {
    @ObservedObject var store: GPUStore
    @Environment(\.aether) private var theme
    let action: () -> Void

    var body: some View {
        Card(title: tr("GPU"), symbol: "cube.transparent", tint: theme.gpu, action: action) {
            if let primary = store.devices.first {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(primary.name).font(Typo.bodyMedium).lineLimit(1)
                        Spacer(minLength: 0)
                        ProvenanceBadge(source: .gpuDevices)
                    }
                    Text(details(primary)).font(Typo.caption).foregroundStyle(theme.textSecondary).lineLimit(2)
                }
            } else if store.devicesLoaded {
                if store.devicesFailed {
                    UnavailableValue(reason: .queryFailed, source: .gpuDevices, compact: true)
                } else {
                    Text(tr("No graphics processor reported")).font(Typo.callout).foregroundStyle(theme.textSecondary)
                }
            } else {
                Text(tr("Measuring…")).font(Typo.callout).foregroundStyle(theme.textSecondary)
            }
            if let utilization = store.utilization {
                if let value = utilization.value {
                    HStack(alignment: .firstTextBaseline) {
                        let parts = percentParts(value)
                        ValueText(value: parts.value, unit: parts.unit, font: Typo.metric, color: theme.textPrimary)
                        Text(tr("utilization (driver)")).font(Typo.caption).foregroundStyle(theme.textSecondary)
                        Spacer(minLength: 0)
                        ProvenanceBadge(source: utilization.source, timestamp: utilization.timestamp)
                    }
                    Sparkline(values: store.history.elements, color: theme.gpu, capacity: sparklineCapacity)
                        .frame(height: 28)
                } else {
                    HStack(spacing: 6) {
                        Text(tr("Utilization")).font(Typo.callout).foregroundStyle(theme.textSecondary)
                        Spacer(minLength: 0)
                        UnavailableValue(reason: utilization.reason ?? .notProvidedByMacOS, source: utilization.source, compact: true)
                    }
                }
            }
            if store.devices.count > 1 {
                Text(tr("%ld graphics processors", store.devices.count))
                    .font(Typo.caption).foregroundStyle(theme.textTertiary)
            }
        }
    }

    private func details(_ d: GPUDevice) -> String {
        var parts: [String] = []
        if let cores = d.coreCount { parts.append(tr("%ld cores", cores)) }
        if d.hasUnifiedMemory {
            parts.append(tr("Unified memory"))
        } else {
            switch d.kind {
            case .integrated: parts.append(tr("Integrated"))
            case .discrete: parts.append(tr("Dedicated"))
            case .external: parts.append(tr("External"))
            case .unknown: break
            }
            if let vram = d.vram { parts.append(vram) }
        }
        if let metal = d.metalSupport { parts.append(metal) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Dieser Mac

struct ThisMacCard: View {
    @ObservedObject var system: SystemStore
    @Environment(\.aether) private var theme
    let action: () -> Void

    var body: some View {
        let hw = system.hardware
        Card(title: tr("This Mac"), symbol: deviceSymbol(hw.kind), action: action) {
            HStack(alignment: .center, spacing: Spacing.m) {
                Image(systemName: deviceSymbol(hw.kind))
                    .font(.system(size: 30, weight: .thin))
                    .foregroundStyle(theme.accent)
                    .frame(width: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hw.machineName ?? hw.modelIdentifier ?? "Mac").font(Typo.metricSmall).lineLimit(1)
                    Text(hw.modelIdentifier ?? "").font(Typo.mono).foregroundStyle(theme.textTertiary)
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 5) {
                InfoRow(label: tr("Chip"), value: system.profiler?.chip ?? hw.processor?.displayName ?? "–", source: .hardwareSysctl)
                if let memory = hw.physicalMemory {
                    InfoRow(label: tr("Memory"), value: fmt.bytes(memory, style: .memory))
                }
                InfoRow(label: tr("Architecture"), value: architecture(hw),
                        valueColor: hw.isTranslated ? theme.statusElevated : nil)
                if hw.isVirtualMachine {
                    InfoRow(label: tr("Environment"), value: tr("Virtual Mac"))
                }
                if let os = hw.osVersion {
                    InfoRow(label: "macOS", value: hw.osBuild.map { "\(os) (\($0))" } ?? os, source: .osVersion)
                }
                if let boot = hw.bootTime {
                    InfoRow(label: tr("Uptime"), value: fmt.duration(seconds: Uptime.seconds(bootTime: boot)))
                }
                if let own = system.ownUsage {
                    InfoRow(label: tr("AETHER itself"),
                            value: [own.cpu.map { fmt.percent($0, fractionDigits: 1) }, own.footprint.map { fmt.bytes($0, style: .memory) }]
                                .compactMap { $0 }.joined(separator: " · "))
                }
            }
        }
    }

    private func architecture(_ hw: HardwareSummary) -> String { architectureDescription(hw) }
}

func deviceSymbol(_ kind: DeviceKind) -> String {
    switch kind {
    case .macBookPro, .macBookAir, .macBook: return "laptopcomputer"
    case .iMac: return "desktopcomputer"
    case .macMini: return "macmini"
    case .macStudio: return "macstudio"
    case .macPro: return "macpro.gen3"
    case .virtualMachine: return "macwindow"
    case .unknown: return "desktopcomputer"
    }
}
