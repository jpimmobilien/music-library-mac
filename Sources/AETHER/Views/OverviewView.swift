import SwiftUI
import AetherCore

// =============================================================================================
// Übersicht „Studio“: Aussage (Puls) → Gerätebühne mit Live-Daten → Live-Leiste → große Module.
// Jede Visualisierung zeigt Messwerte; Gerätesilhouette und Bühnenlicht sind als Illustration gekennzeichnet.
// Jede Ansicht beobachtet nur, was sie zeigt (Monitoring 2.0) – große Zahlen ändern sich nur bei sichtbarer Änderung.
// =============================================================================================

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.aether) private var theme
    @AppStorage("aether.overview.range") private var range: ChartRange = .fiveMinutes

    var body: some View {
        let engine = model.engine
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 34) {
                OverviewIntro(system: engine.system)
                    .padding(.top, Metrics.headerTop + 6)
                if model.editingDashboard {
                    DashboardEditor()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                OverviewStage(system: engine.system, telemetry: engine.telemetry, gpu: engine.gpu)
                OrbitCorePanel(system: engine.system, telemetry: engine.telemetry, storage: engine.storage, gpu: engine.gpu)
                LiveStrip(power: engine.power, gpu: engine.gpu, system: engine.system, telemetry: engine.telemetry)
                OverviewModules(range: $range)
            }
            .padding(.horizontal, Spacing.gutter + 8)
            .padding(.bottom, 44)
            .aetherAnimation(Motion.spring, value: model.editingDashboard)
        }
        .scrollIndicators(.automatic)
    }
}

// MARK: - Aussage

/// Überzeile (Gerät), Aussage (Puls), Erklärung (System) und Werkzeuge.
private struct OverviewIntro: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var system: SystemStore
    @Environment(\.aether) private var theme
    @State private var showingRules = false

    var body: some View {
        let hw = system.hardware
        let pulse = system.pulse
        let measuring = system.lastUpdate == nil || system.pulseInput.cpuBusy == nil
        HStack(alignment: .top, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: 10) {
                Text(eyebrow(hw))
                    .font(StudioType.eyebrow)
                    .tracking(0.4)
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    // ORBIT: animierter Symbolwechsel bei echtem Zustandswechsel (Form trägt die Aussage, nicht nur die Farbe)
                    OrbitStatusSymbol(symbol: statusSymbol(measuring: measuring, level: pulse.level),
                                      color: measuring ? theme.statusUnavailable : theme.color(for: pulse.level), size: 18)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                    Text(measuring ? tr("Measuring…") : headline(pulse))
                        .font(StudioType.headline)
                        .tracking(-0.5)
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(lead(hw))
                    .font(StudioType.lead)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    ForEach(pulse.findings) { finding in
                        Button {
                            model.select(section(for: finding.kind))
                        } label: {
                            Chip(text: findingSentence(finding), color: theme.color(for: finding.severity), symbol: "arrow.up.right")
                        }
                        .buttonStyle(.plain)
                        .help(tr("Show details"))
                    }
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
                .padding(.top, 4)
            }
            Spacer(minLength: Spacing.l)
            tools
        }
        .aetherAnimation(Motion.easeOut(), value: pulse)
    }

    private var tools: some View {
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

    private func statusSymbol(measuring: Bool, level: PulseSeverity?) -> String {
        if measuring { return "hourglass" }
        switch level {
        case .none, .some(.info): return "checkmark.circle.fill"
        case .some(.elevated): return "exclamationmark.circle.fill"
        case .some(.critical): return "exclamationmark.triangle.fill"
        }
    }

    private func eyebrow(_ hw: HardwareSummary) -> String {
        var parts = [hw.macModel?.displayName ?? hw.machineName ?? hw.modelIdentifier ?? tr("This Mac")]
        if let chip = system.profiler?.chip ?? hw.processor?.displayName { parts.append(chip) }
        return parts.joined(separator: "  ·  ")
    }

    private func headline(_ pulse: Pulse) -> String {
        guard let first = pulse.findings.first else { return tr("Your Mac is running smoothly.") }
        return findingSentence(first)
    }

    private func lead(_ hw: HardwareSummary) -> String {
        var parts: [String] = []
        if let os = hw.osVersion {
            parts.append(hw.osBuild.map { "macOS \(os) (\($0))" } ?? "macOS \(os)")
        }
        if let memory = hw.physicalMemory {
            parts.append(hw.isAppleSilicon ? tr("%@ unified memory", fmt.bytes(memory, style: .memory))
                                           : tr("%@ memory", fmt.bytes(memory, style: .memory)))
        }
        if let boot = hw.bootTime {
            parts.append(tr("up %@", fmt.duration(seconds: Uptime.seconds(bootTime: boot))))
        }
        if hw.kind == .virtualMachine || hw.isVirtualMachine { parts.append(tr("Virtual Mac")) }
        return parts.joined(separator: "  ·  ")
    }

    private func section(for kind: PulseFindingKind) -> AppSection {
        switch kind {
        case .highCPU: return .cpuGPU
        case .memoryPressure, .highSwap: return .memory
        case .thermal: return .thermal
        case .lowDiskSpace: return .storage
        case .highNetwork: return .network
        case .batteryService: return .battery
        }
    }
}

func intervalName(_ interval: RefreshInterval) -> String {
    tr("%ld s", interval.rawValue)
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
            Text(tr("ORBIT only uses measured values and what macOS itself reports, with fixed thresholds. It doesn’t diagnose anything."))
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
