import SwiftUI
import AetherCore

/// Übersicht – die Systemzentrale: Identität, Puls, Karten.
struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.aether) private var theme

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: theme.density.cardSpacing + 4) {
                OverviewHeader(system: model.engine.system)
                PulseBanner(system: model.engine.system, cpu: model.engine.cpu, storage: model.engine.storage)
                if model.editingDashboard {
                    DashboardEditor()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 268, maximum: 560), spacing: theme.density.cardSpacing,
                                             alignment: .top)],
                          alignment: .leading, spacing: theme.density.cardSpacing) {
                    ForEach(settings.dashboard.visible) { card in
                        cardView(card)
                    }
                }
                .aetherAnimation(Motion.spring, value: settings.dashboard)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.gutter)
            .aetherAnimation(Motion.spring, value: model.editingDashboard)
        }
        .scrollIndicators(.automatic)
    }

    @ViewBuilder
    private func cardView(_ card: DashboardCard) -> some View {
        let engine = model.engine
        switch card {
        case .cpu: CPUCard(store: engine.cpu, system: engine.system) { model.select(.cpuGPU) }
        case .memory: MemoryCard(store: engine.memory, system: engine.system) { model.select(.memory) }
        case .thermal: ThermalCard(store: engine.power) { model.select(.thermal) }
        case .battery: BatteryCard(store: engine.power) { model.select(.battery) }
        case .network: NetworkCard(store: engine.network) { model.select(.network) }
        case .storage: StorageCard(store: engine.storage) { model.select(.storage) }
        case .gpu: GPUCard(store: engine.gpu) { model.select(.cpuGPU) }
        case .thisMac: ThisMacCard(system: engine.system) { model.select(.hardware) }
        }
    }
}

// MARK: - Kopf

private struct OverviewHeader: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var system: SystemStore
    @Environment(\.aether) private var theme

    var body: some View {
        let hw = system.hardware
        PageHeader(title: hw.machineName ?? tr("This Mac"), subtitle: subtitle(hw)) {
            GlassGroup {
                HStack(spacing: 2) {
                    Menu {
                        Picker(tr("Update interval"), selection: $settings.refreshInterval) {
                            ForEach(RefreshInterval.allCases) { interval in
                                Text(intervalName(interval)).tag(interval)
                            }
                        }
                        .pickerStyle(.inline)
                        Toggle(tr("Low-impact mode"), isOn: $settings.lowImpact)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "timer").font(.system(size: 12, weight: .medium))
                            Text(intervalName(settings.effectiveInterval)).font(.system(size: 12, weight: .medium)).monospacedDigit()
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(tr("Update interval"))
                    ToolbarIconButton(symbol: "square.grid.2x2", help: tr("Customize Overview"), active: model.editingDashboard) {
                        model.editingDashboard.toggle()
                    }
                }
                .padding(.horizontal, 4)
                .glassSurface(Capsule(), interactive: true)
            }
        }
    }

    private func subtitle(_ hw: HardwareSummary) -> String {
        var parts: [String] = []
        if let chip = system.profiler?.chip ?? hw.processor?.displayName { parts.append(chip) }
        if let os = hw.osVersion {
            parts.append(hw.osBuild.map { "macOS \(os) (\($0))" } ?? "macOS \(os)")
        }
        if hw.kind == .virtualMachine || hw.isVirtualMachine { parts.append(tr("Virtual Mac")) }
        return parts.joined(separator: "  ·  ")
    }
}

func intervalName(_ interval: RefreshInterval) -> String {
    tr("%ld s", interval.rawValue)
}

// MARK: - Puls

private struct PulseBanner: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var system: SystemStore
    @ObservedObject var cpu: CPUStore
    @ObservedObject var storage: StorageStore
    @Environment(\.aether) private var theme
    @State private var showingRules = false

    var body: some View {
        let pulse = system.pulse
        let measuring = system.lastUpdate == nil || cpu.snapshot?.total.value == nil
        HStack(alignment: .center, spacing: Spacing.l) {
            ZStack {
                Circle().fill(statusColor(pulse, measuring).opacity(0.18)).frame(width: 34, height: 34)
                StatusDot(color: statusColor(pulse, measuring), size: 11)
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(measuring ? tr("Measuring…") : sentence(pulse))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    if pulse.findings.count > 1 {
                        Text(tr("+%ld more", pulse.findings.count - 1))
                            .font(Typo.captionMedium)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                evidence
            }
            Spacer(minLength: Spacing.s)
            Button {
                showingRules.toggle()
            } label: {
                Label(tr("Why?"), systemImage: "info.circle")
            }
            .buttonStyle(CapsuleButtonStyle())
            .popover(isPresented: $showingRules, arrowEdge: .bottom) {
                PulseRules(pulse: pulse)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.card, style: .continuous), strong: true)
        .aetherAnimation(Motion.easeOut(), value: pulse)
        .accessibilityElement(children: .combine)
    }

    private var evidence: some View {
        let input = system.pulseInput
        return HStack(spacing: 6) {
            if let busy = input.cpuBusy {
                Chip(text: "CPU \(fmt.percent(busy))", color: theme.cpuUser)
                    .onTapGesture { model.select(.cpuGPU) }
            }
            if let pressure = input.pressure {
                Chip(text: tr("Memory pressure: %@", pressureName(pressure)), color: theme.color(for: pressure))
                    .onTapGesture { model.select(.memory) }
            }
            if let thermal = input.thermal {
                Chip(text: tr("Thermal: %@", thermalShortName(thermal)), color: theme.color(for: thermal))
                    .onTapGesture { model.select(.thermal) }
            }
            if let available = input.startupAvailable {
                Chip(text: tr("%@ free", fmt.bytes(available)), color: theme.storage)
                    .onTapGesture { model.select(.storage) }
            }
        }
    }

    private func statusColor(_ pulse: Pulse, _ measuring: Bool) -> Color {
        measuring ? theme.statusUnavailable : theme.color(for: pulse.level)
    }

    private func sentence(_ pulse: Pulse) -> String {
        guard let first = pulse.findings.first else { return tr("Your Mac is running smoothly.") }
        return findingSentence(first)
    }
}

func findingSentence(_ finding: PulseFinding) -> String {
    switch finding.kind {
    case .highCPU: return tr("High CPU usage detected.")
    case .memoryPressure:
        return finding.severity == .critical ? tr("Memory pressure is critical.") : tr("Memory is under heavy pressure.")
    case .highSwap: return tr("High swap usage.")
    case .thermal:
        return finding.severity == .critical ? tr("macOS reports a critical thermal state.") : tr("macOS reports an elevated thermal state.")
    case .lowDiskSpace: return tr("Little free space on the startup disk.")
    case .highNetwork: return tr("High network activity.")
    case .batteryService: return tr("macOS recommends servicing the battery.")
    }
}

func pressureName(_ level: PressureLevel) -> String {
    switch level {
    case .normal: return tr("Normal")
    case .warning: return tr("Warning")
    case .critical: return tr("Critical")
    }
}

/// Erklärung der Puls-Regeln mit den Schwellen im Klartext.
private struct PulseRules: View {
    let pulse: Pulse

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("How the status is determined"))
                .font(.system(size: 13, weight: .semibold))
            Text(tr("AETHER only uses measured values and what macOS itself reports, with fixed thresholds. It doesn’t diagnose anything."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !pulse.findings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Currently active")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(pulse.findings) { finding in
                        Label(findingSentence(finding), systemImage: "exclamationmark.circle").font(.system(size: 12))
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                rule("cpu", tr("CPU: at least %@ for %ld seconds", fmt.percent(PulseThresholds.highCPU), Int(PulseThresholds.highCPUSeconds)))
                rule("memorychip", tr("Memory: pressure “warning” or “critical” as reported by macOS"))
                rule("arrow.left.arrow.right", tr("Swap: at least %@ of RAM while memory pressure is elevated", fmt.percent(PulseThresholds.swapFractionOfRAM)))
                rule("thermometer.medium", tr("Thermal: state “serious” or “critical” as reported by macOS. Sensor temperatures alone never trigger a warning – Apple doesn’t publish limits."))
                rule("internaldrive", tr("Startup disk: less than %@ or %@ available", fmt.percent(PulseThresholds.lowDiskFraction), fmt.bytes(PulseThresholds.lowDiskBytes)))
                rule("network", tr("Network: more than %@ for %ld seconds (information only)", fmt.rate(PulseThresholds.highNetworkBytesPerSecond), Int(PulseThresholds.highNetworkSeconds)))
                rule(SymbolName.batteryLow, tr("Battery: only macOS’s own condition (“Service recommended”)"))
            }
        }
        .padding(16)
        .frame(width: 420, alignment: .leading)
    }

    private func rule(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 11)).frame(width: 16).foregroundStyle(.secondary)
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Anpassen

private struct DashboardEditor: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var model: AppModel
    @Environment(\.aether) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Text(tr("Customize Overview")).font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(tr("Reset")) { settings.dashboard = DashboardLayout() }
                    .buttonStyle(CapsuleButtonStyle())
                Button(tr("Done")) { model.editingDashboard = false }
                    .buttonStyle(CapsuleButtonStyle(prominent: true))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: Spacing.s)], spacing: Spacing.s) {
                ForEach(settings.dashboard.order) { card in
                    HStack(spacing: Spacing.s) {
                        Toggle(isOn: Binding(get: { !settings.dashboard.hidden.contains(card) },
                                             set: { settings.dashboard.setVisible(card, $0) })) {
                            Label(cardTitle(card), systemImage: cardSymbol(card))
                                .font(.system(size: 12.5))
                        }
                        .toggleStyle(.checkbox)
                        Spacer(minLength: 0)
                        Button { move(card, by: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless)
                            .disabled(settings.dashboard.order.first == card)
                            .help(tr("Move up"))
                        Button { move(card, by: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless)
                            .disabled(settings.dashboard.order.last == card)
                            .help(tr("Move down"))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(theme.fieldFill))
                }
            }
        }
        .padding(16)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.card, style: .continuous), strong: true)
    }

    private func move(_ card: DashboardCard, by offset: Int) {
        var layout = settings.dashboard
        guard let index = layout.order.firstIndex(of: card) else { return }
        let target = index + offset
        guard layout.order.indices.contains(target) else { return }
        layout.order.swapAt(index, target)
        settings.dashboard = layout
    }
}

func cardTitle(_ card: DashboardCard) -> String {
    switch card {
    case .cpu: return tr("CPU")
    case .memory: return tr("Memory")
    case .thermal: return tr("Thermal")
    case .battery: return tr("Battery")
    case .network: return tr("Network")
    case .storage: return tr("Storage")
    case .gpu: return tr("GPU")
    case .thisMac: return tr("This Mac")
    }
}

func cardSymbol(_ card: DashboardCard) -> String {
    switch card {
    case .cpu: return "cpu"
    case .memory: return "memorychip"
    case .thermal: return "thermometer.medium"
    case .battery: return SymbolName.battery
    case .network: return "network"
    case .storage: return "internaldrive"
    case .gpu: return "cube.transparent"
    case .thisMac: return "laptopcomputer"
    }
}
