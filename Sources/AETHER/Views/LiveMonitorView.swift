import SwiftUI
import AppKit
import AetherCore

/// Live-Monitor (⌥⌘M): kleines Fenster mit den wichtigsten Live-Werten, auf Wunsch immer im Vordergrund.
/// Gleicher Inhalt (kompakt) im Menüleisten-Fenster.
struct LiveMonitorView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// Für Bildschirmfotos im Build: ohne Fensterkonfiguration.
    var embedded = false

    var body: some View {
        let theme = AetherTheme.resolve(settings: settings, systemIsDark: colorScheme == .dark,
                                        reduceTransparency: reduceTransparency && !model.launchMode.isSnapshot)
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "waveform.path.ecg").foregroundStyle(theme.accent)
                Text(tr("Live Monitor")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    settings.liveMonitorOnTop.toggle()
                } label: {
                    Image(systemName: settings.liveMonitorOnTop ? "pin.fill" : "pin")
                        .foregroundStyle(settings.liveMonitorOnTop ? theme.accent : theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help(settings.liveMonitorOnTop ? tr("Don’t keep on top") : tr("Keep on top of other windows"))
            }
            .padding(.top, embedded ? 0 : 14)
            LiveMetrics(engine: model.engine)
        }
        .padding(Spacing.l)
        .frame(width: 340)
        .background {
            ZStack {
                AmbientBackground()
                if !embedded {
                    FloatingWindowConfigurator(onTop: settings.liveMonitorOnTop) { visible in
                        model.setLiveMonitorVisible(visible)
                    }
                }
            }
        }
        .environment(\.aether, theme)
        .tint(theme.accent)
        .foregroundStyle(theme.textPrimary)
        .onDisappear { model.setLiveMonitorVisible(false) }
    }
}

/// Die Live-Werte als Zeilen mit Mini-Verlauf (gemeinsam für Live-Monitor und Menüleiste).
struct LiveMetrics: View {
    let engine: MonitorEngine
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 8 : 10) {
            CPULiveRow(store: engine.cpu, compact: compact)
            MemoryLiveRow(store: engine.memory, compact: compact)
            NetworkLiveRow(store: engine.network, compact: compact)
            GPULiveRow(store: engine.gpu, compact: compact)
            PowerLiveRow(store: engine.power, compact: compact)
        }
    }
}

private struct LiveRow<Trailing: View>: View {
    @Environment(\.aether) private var theme
    let symbol: String
    let title: String
    let value: String
    let tint: Color
    let history: [Double]
    var scaleMax: Double? = 1
    var compact = false
    var source: DataSource?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(tint).frame(width: 16)
                Text(title).font(Typo.captionMedium).foregroundStyle(theme.textSecondary)
                Spacer(minLength: 4)
                Text(value).font(compact ? Typo.callout.weight(.semibold) : Typo.metricSmall).monospacedDigit().lineLimit(1)
                if let source { ProvenanceBadge(source: source) }
            }
            if !history.isEmpty && !compact {
                Sparkline(values: history, color: tint, capacity: sparklineCapacity, scaleMax: scaleMax)
                    .frame(height: 24)
            }
            trailing()
        }
        .padding(compact ? 8 : 10)
        .background(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).fill(theme.fieldFill))
    }
}

private struct CPULiveRow: View {
    @ObservedObject var store: CPUStore
    let compact: Bool
    @Environment(\.aether) private var theme

    var body: some View {
        let busy = store.snapshot?.total.value?.busy
        LiveRow(symbol: "cpu", title: "CPU", value: busy.map { fmt.percent($0) } ?? "–", tint: theme.cpuUser,
                history: store.busyHistory.elements, compact: compact, source: .cpuTicks) { EmptyView() }
    }
}

private struct MemoryLiveRow: View {
    @ObservedObject var store: MemoryStore
    let compact: Bool
    @Environment(\.aether) private var theme

    var body: some View {
        let breakdown = store.snapshot?.breakdown.value
        let value = breakdown.map { "\(fmt.bytes($0.used, style: .memory)) / \(fmt.bytes($0.physical, style: .memory))" } ?? "–"
        LiveRow(symbol: "memorychip", title: tr("Memory"), value: value, tint: theme.memory,
                history: store.usedHistory.elements, compact: compact, source: .vmStatistics) {
            if let pressure = store.snapshot?.pressure.value {
                Text(tr("Pressure: %@", pressureName(pressure))).font(Typo.caption).foregroundStyle(theme.color(for: pressure))
            }
        }
    }
}

private struct NetworkLiveRow: View {
    @ObservedObject var store: NetworkStore
    let compact: Bool
    @Environment(\.aether) private var theme

    var body: some View {
        let down = store.snapshot?.download.value
        let up = store.snapshot?.upload.value
        let value = down.map { "↓ \(fmt.rate($0))  ↑ \(up.map { fmt.rate($0) } ?? "–")" } ?? tr("Measuring…")
        let scale = max(store.downHistory.elements.max() ?? 0, store.upHistory.elements.max() ?? 0, 1_000)
        LiveRow(symbol: "network", title: tr("Network"), value: value, tint: theme.networkDown,
                history: store.downHistory.elements, scaleMax: scale, compact: compact, source: .interfaceCounters) { EmptyView() }
    }
}

private struct GPULiveRow: View {
    @ObservedObject var store: GPUStore
    let compact: Bool
    @Environment(\.aether) private var theme

    var body: some View {
        if let utilization = store.utilization?.value {
            LiveRow(symbol: SymbolName.gpu, title: "GPU", value: fmt.percent(utilization), tint: theme.gpu,
                    history: store.history.elements, compact: compact, source: .gpuStatistics) { EmptyView() }
        }
    }
}

private struct PowerLiveRow: View {
    @ObservedObject var store: PowerStore
    let compact: Bool
    @Environment(\.aether) private var theme

    var body: some View {
        let thermal = store.thermal
        let hottest = thermal?.hottest
        let stateText = thermal?.state.value.map(thermalShortName) ?? "–"
        let value = hottest.map { fmt.celsius($0.celsius) } ?? stateText
        LiveRow(symbol: SymbolName.thermometer, title: hottest != nil ? tr("Hottest sensor (%@)", hottest?.key ?? "") : tr("Thermal state"),
                value: value, tint: theme.thermal, history: compact ? [] : Array(store.longHottest.elements.suffix(sparklineCapacity)),
                scaleMax: 110, compact: compact, source: hottest != nil ? DataSource.smcSensors : DataSource.thermalState) {
            if let battery = store.battery, battery.isPresent, let percent = battery.percent.value {
                HStack(spacing: 6) {
                    Image(systemName: battery.powerSource == .ac ? "bolt.fill" : SymbolName.batteryLow)
                        .font(.system(size: 10)).foregroundStyle(theme.battery)
                    Text("\(percent) % · \(batteryChargeState(battery))").font(Typo.caption).foregroundStyle(theme.textSecondary)
                    if let watts = battery.power.value {
                        Text(fmt.number(abs(watts), fractionDigits: 1) + " W").font(Typo.caption).foregroundStyle(theme.textSecondary)
                    }
                }
            }
        }
    }
}

/// Fenster des Live-Monitors: durchsichtige Titelleiste, auf Wunsch schwebend, Sichtbarkeit melden.
private struct FloatingWindowConfigurator: NSViewRepresentable {
    let onTop: Bool
    let onVisibility: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(view) }
    }

    private func configure(_ view: NSView) {
        guard let window = view.window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.level = onTop ? .floating : .normal
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        onVisibility(window.isVisible)
    }
}

// MARK: - Menüleiste

/// Anzeige in der Menüleiste: CPU-Auslastung (nur wenn in den Einstellungen eingeschaltet).
struct MenuBarLabel: View {
    @ObservedObject var cpu: CPUStore

    var body: some View {
        let busy = cpu.snapshot?.total.value?.busy
        HStack(spacing: 3) {
            Image(systemName: "waveform.path.ecg")
            Text(busy.map { fmt.percent($0) } ?? "–").monospacedDigit()
        }
    }
}

/// Fenster unter dem Menüleistensymbol.
struct MenuBarPanel: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let theme = AetherTheme.resolve(settings: settings, systemIsDark: colorScheme == .dark, reduceTransparency: false)
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Text("AETHER").font(.system(size: 13, weight: .bold))
                Spacer()
                Text(tr("every %@", fmt.duration(seconds: model.menuBarInterval.seconds)))
                    .font(Typo.caption).foregroundStyle(theme.textTertiary)
            }
            LiveMetrics(engine: model.engine, compact: true)
            Divider()
            HStack(spacing: Spacing.s) {
                Button(tr("Open AETHER")) {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(CapsuleButtonStyle(prominent: true))
                Button(tr("Live Monitor")) {
                    openWindow(id: "live-monitor")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(CapsuleButtonStyle())
                Spacer()
                Button(tr("Quit")) { NSApp.terminate(nil) }
                    .buttonStyle(CapsuleButtonStyle())
            }
        }
        .padding(Spacing.l)
        .frame(width: 320)
        .environment(\.aether, theme)
        .tint(theme.accent)
        .foregroundStyle(theme.textPrimary)
        .onAppear { model.setMenuBarPanelVisible(true) }
        .onDisappear { model.setMenuBarPanelVisible(false) }
    }
}

/// Menübefehl „Live-Monitor“ (⌥⌘M).
struct OpenLiveMonitorButton: View {
    @Environment(\.openWindow) private var openWindow
    /// Nur der Menübefehl trägt den Kurzbefehl (sonst wäre er doppelt belegt).
    var withShortcut = true

    var body: some View {
        if withShortcut {
            Button(tr("Live Monitor")) { openWindow(id: "live-monitor") }
                .keyboardShortcut("m", modifiers: [.command, .option])
        } else {
            Button(tr("Open Live Monitor")) { openWindow(id: "live-monitor") }
        }
    }
}
