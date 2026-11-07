import SwiftUI
import AppKit
import AetherCore

/// Batterie: Ladestand, Zustand (berechnet vs. Apples Angabe getrennt), elektrische Werte, Netzteil, Verläufe.
struct BatteryView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.aether) private var theme

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: theme.density.cardSpacing + 4) {
                PageHeader(title: tr("Battery"), subtitle: tr("Charge, condition and power – measured values and macOS reports kept apart."))
                BatteryContent(store: model.engine.power, interval: settings.effectiveInterval.seconds) {
                    model.select(.thermal)
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.gutter)
        }
    }
}

/// Ladezustand in einem Satz (gemeinsam für Übersicht und Batterieseite).
func batteryChargeState(_ b: BatterySnapshot) -> String {
    if b.isFullyCharged == true { return tr("Fully charged") }
    if b.isCharging == true { return tr("Charging") }
    if b.powerSource == .ac { return tr("On power adapter, not charging") }
    return tr("On battery")
}

/// Verlaufsbeschriftung für Batterie und Temperatur (mittlerer Takt: alle 5 s oder seltener).
func mediumSpanLabel(_ interval: Double) -> String {
    historySpanLabel(samples: slowCapacity, interval: max(5, interval))
}

private struct BatteryContent: View {
    @ObservedObject var store: PowerStore
    let interval: Double
    let showThermal: () -> Void

    var body: some View {
        if let b = store.battery {
            if b.isPresent {
                ChargePanel(battery: b, history: store.longPercent.elements, interval: interval)
                HealthPanel(battery: b, profiler: store.profiler, profilerLoaded: store.profilerLoaded)
                ElectricalPanel(battery: b, history: store.longPower.elements, interval: interval)
                AdapterPanel(battery: b, profiler: store.profiler)
                if let profiler = store.profiler, profiler.manufacturer != nil || profiler.deviceName != nil || profiler.firmware != nil {
                    Panel {
                        PanelTitle(title: tr("Battery details"), symbol: "info.circle")
                        if let manufacturer = profiler.manufacturer {
                            InfoRow(label: tr("Manufacturer"), value: manufacturer, source: .powerProfiler)
                        }
                        if let device = profiler.deviceName {
                            InfoRow(label: tr("Cell model"), value: device, source: .powerProfiler)
                        }
                        if let firmware = profiler.firmware {
                            InfoRow(label: tr("Firmware"), value: firmware, source: .powerProfiler)
                        }
                    }
                }
                ChargingSettingsNote()
            } else {
                NoBatteryPanel(battery: b, showThermal: showThermal)
            }
        } else {
            Panel { Text(tr("Measuring…")).font(Typo.callout) }
        }
    }
}

private struct ChargePanel: View {
    @Environment(\.aether) private var theme
    let battery: BatterySnapshot
    let history: [Double]
    let interval: Double

    var body: some View {
        let b = battery
        let percent = b.percent.value
        Panel {
            PanelTitle(title: tr("Charge"), symbol: SymbolName.battery)
            HStack(alignment: .center, spacing: Spacing.xxl) {
                MetricRing(segments: [(Double(percent ?? 0) / 100, theme.batteryColor(percent: percent ?? 100))],
                           lineWidth: 12, size: 128, unavailable: percent == nil) {
                    if let percent {
                        ValueText(value: fmt.integer(percent), unit: "%", font: Typo.metricLarge)
                    } else {
                        Text("–").font(Typo.metricLarge).foregroundStyle(theme.textTertiary)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: b.powerSource == .ac ? "bolt.fill" : SymbolName.batteryLow)
                            .foregroundStyle(b.isCharging == true ? theme.battery : theme.textSecondary)
                        Text(batteryChargeState(b)).font(Typo.metricSmall)
                        ProvenanceBadge(source: .powerSources, timestamp: b.percent.timestamp)
                    }
                    timeRow(b)
                    InfoRow(label: tr("Power source"),
                            value: b.powerSource == .ac ? tr("Power adapter") : (b.powerSource == .battery ? tr("Battery") : tr("Unknown")),
                            source: .powerSources)
                        .frame(maxWidth: 360)
                }
                Spacer(minLength: 0)
            }
            if !history.isEmpty {
                HistoryChart(series: [.init(values: history, color: theme.battery)], capacity: slowCapacity, maxValue: 100,
                             height: 100, label: { fmt.integer(Int($0.rounded())) + " %" }, spanLabel: mediumSpanLabel(interval))
            }
        }
    }

    @ViewBuilder
    private func timeRow(_ b: BatterySnapshot) -> some View {
        if b.isFullyCharged == true {
            EmptyView()
        } else {
            let charging = b.isCharging == true
            let reading = charging ? b.minutesToFull : b.minutesToEmpty
            HStack(spacing: 6) {
                if let minutes = reading.value {
                    let text = fmt.duration(seconds: Double(minutes) * 60)
                    Text(charging ? tr("Full in %@", text) : tr("%@ remaining", text))
                        .font(Typo.bodyMedium)
                    ProvenanceBadge(source: reading.source, timestamp: reading.timestamp)
                } else if reading.reason == .awaitingSecondSample {
                    Text(tr("macOS is still calculating the remaining time"))
                        .font(Typo.callout).foregroundStyle(theme.textSecondary)
                    ProvenanceBadge(source: reading.source, reason: .awaitingSecondSample)
                } else if b.powerSource == .battery || charging {
                    Text(tr("Remaining time")).font(Typo.callout).foregroundStyle(theme.textSecondary)
                    UnavailableValue(reason: reading.reason ?? .notProvidedByMacOS, source: reading.source, compact: true)
                }
            }
        }
    }
}

private struct HealthPanel: View {
    @Environment(\.aether) private var theme
    let battery: BatterySnapshot
    let profiler: PowerProfilerInfo?
    let profilerLoaded: Bool

    var body: some View {
        let b = battery
        Panel {
            PanelTitle(title: tr("Condition"), symbol: "heart.text.square")
            HStack(alignment: .top, spacing: Spacing.xxl) {
                // Berechnet: volle Ladekapazität ÷ Designkapazität
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Capacity (computed)")).font(Typo.captionMedium).foregroundStyle(theme.textSecondary)
                    if let health = b.computedHealth.value {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            ValueText(value: fmt.number(health * 100, fractionDigits: 1), unit: "%", font: Typo.metric,
                                      color: health < 0.8 ? theme.statusElevated : nil)
                            ProvenanceBadge(source: b.computedHealth.source, timestamp: b.computedHealth.timestamp)
                        }
                        FillBar(fraction: health, color: health < 0.8 ? theme.statusElevated : theme.battery, height: 7)
                            .frame(maxWidth: 220)
                    } else {
                        UnavailableValue(reason: b.computedHealth.reason ?? .notProvidedByMacOS, source: b.computedHealth.source)
                    }
                }
                // Apples Angabe aus den Systeminformationen
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Maximum capacity (Apple)")).font(Typo.captionMedium).foregroundStyle(theme.textSecondary)
                    if let maximum = profiler?.maximumCapacity {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(maximum).font(Typo.metric).monospacedDigit()
                            ProvenanceBadge(source: .powerProfiler)
                        }
                    } else if !profilerLoaded {
                        Text(tr("Loading…")).font(Typo.callout).foregroundStyle(theme.textSecondary)
                    } else {
                        UnavailableValue(reason: .notProvidedByMacOS, source: .powerProfiler)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Condition (macOS)")).font(Typo.captionMedium).foregroundStyle(theme.textSecondary)
                    if let condition = profiler?.condition ?? b.systemCondition {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(conditionName(condition)).font(Typo.metricSmall)
                                .foregroundStyle(b.serviceRecommended == true ? theme.statusElevated : theme.textPrimary)
                            ProvenanceBadge(source: profiler?.condition != nil ? .powerProfiler : .powerSources)
                        }
                    } else {
                        UnavailableValue(reason: .notProvidedByMacOS, source: .powerSources, compact: true)
                    }
                }
                Spacer(minLength: 0)
            }
            Divider().overlay(theme.hairline)
            cycles(b)
            if let design = b.designCapacity.value {
                InfoRow(label: tr("Design capacity"), value: "\(fmt.integer(design)) mAh", source: b.designCapacity.source,
                        timestamp: b.designCapacity.timestamp)
            }
            if let full = b.fullChargeCapacity.value {
                InfoRow(label: tr("Full charge capacity"), value: "\(fmt.integer(full)) mAh", source: b.fullChargeCapacity.source,
                        timestamp: b.fullChargeCapacity.timestamp)
            }
            Text(tr("AETHER computes the capacity as full charge capacity ÷ design capacity. Apple’s “Maximum capacity” uses its own method and can differ by a few percent – both are shown unchanged."))
                .font(Typo.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func cycles(_ b: BatterySnapshot) -> some View {
        if let count = b.cycleCount.value {
            VStack(alignment: .leading, spacing: 5) {
                if let design = b.designCycleCount {
                    InfoRow(label: tr("Charge cycles"), value: tr("%@ of %@ designed", fmt.integer(count), fmt.integer(design)),
                            source: b.cycleCount.source, timestamp: b.cycleCount.timestamp)
                    FillBar(fraction: Double(count) / Double(design), color: theme.battery, height: 5)
                } else {
                    InfoRow(label: tr("Charge cycles"), value: fmt.integer(count), source: b.cycleCount.source, timestamp: b.cycleCount.timestamp)
                }
            }
        } else if let count = profiler?.cycleCount {
            InfoRow(label: tr("Charge cycles"), value: fmt.integer(count), source: .powerProfiler)
        } else {
            HStack {
                Text(tr("Charge cycles")).font(Typo.callout).foregroundStyle(theme.textSecondary)
                Spacer()
                UnavailableValue(reason: b.cycleCount.reason ?? .notProvidedByMacOS, source: b.cycleCount.source, compact: true)
            }
        }
    }

    /// Bekannte Zustandsangaben übersetzen; Unbekanntes unverändert lassen.
    private func conditionName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "good", "normal": return tr("Normal")
        case "fair": return tr("Fair")
        case "poor": return tr("Poor")
        case "check battery": return tr("Check battery")
        case "service recommended", "service battery": return tr("Service recommended")
        default: return raw
        }
    }
}

private struct ElectricalPanel: View {
    @Environment(\.aether) private var theme
    let battery: BatterySnapshot
    let history: [Double]
    let interval: Double

    var body: some View {
        let b = battery
        Panel {
            PanelTitle(title: tr("Voltage, current and power"), symbol: "bolt")
            HStack(alignment: .top, spacing: Spacing.xxl) {
                electrical(tr("Voltage"), b.voltage, unit: "V") { fmt.number($0 / 1000, fractionDigits: 2) }
                electrical(b.amperage.value.map { $0 >= 0 ? tr("Charging current") : tr("Discharge current") } ?? tr("Current"),
                           b.amperage, unit: "A") { fmt.number(abs($0) / 1000, fractionDigits: 2) }
                electrical(tr("Power"), b.power, unit: "W") { fmt.number(abs($0), fractionDigits: 1) }
                electrical(tr("Temperature"), b.temperature, unit: "°C") { fmt.number($0, fractionDigits: 1) }
                Spacer(minLength: 0)
            }
            if !history.isEmpty {
                HistoryChart(series: [.init(values: history, color: theme.battery)], capacity: slowCapacity, maxValue: nil,
                             height: 90, label: { fmt.number($0, fractionDigits: 1) + " W" }, spanLabel: mediumSpanLabel(interval))
            }
            Text(tr("Power is voltage × current of the battery. While charging it shows how much flows into the battery, not the total consumption of the Mac."))
                .font(Typo.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func electrical(_ label: String, _ reading: Reading<Double>, unit: String, _ format: (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Typo.captionMedium).foregroundStyle(theme.textSecondary)
            if let value = reading.value {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    ValueText(value: format(value), unit: unit, font: Typo.metricSmall)
                    ProvenanceBadge(source: reading.source, timestamp: reading.timestamp)
                }
            } else {
                UnavailableValue(reason: reading.reason ?? .notProvidedByMacOS, source: reading.source, compact: true)
            }
        }
    }
}

private struct AdapterPanel: View {
    @Environment(\.aether) private var theme
    let battery: BatterySnapshot
    let profiler: PowerProfilerInfo?

    var body: some View {
        let b = battery
        Panel {
            PanelTitle(title: tr("Power adapter"), symbol: "powerplug")
            if b.powerSource == .ac || b.adapterWatts.value != nil {
                if let watts = b.adapterWatts.value ?? profiler?.chargerWatts {
                    InfoRow(label: tr("Rated power"), value: "\(fmt.integer(watts)) W", source: .adapterDetails)
                }
                if let name = b.adapterName ?? profiler?.chargerName {
                    InfoRow(label: tr("Name"), value: name, source: .adapterDetails)
                }
                if let volts = AdapterUnits.volts(b.adapterVoltage) {
                    InfoRow(label: tr("Voltage"), value: fmt.number(volts, fractionDigits: 1) + " V", source: .adapterDetails)
                }
                if let amps = AdapterUnits.amperes(b.adapterCurrent) {
                    InfoRow(label: tr("Current"), value: fmt.number(amps, fractionDigits: 2) + " A", source: .adapterDetails)
                }
            } else {
                Text(tr("No power adapter connected")).font(Typo.callout).foregroundStyle(theme.textSecondary)
            }
        }
    }
}

private struct ChargingSettingsNote: View {
    @Environment(\.aether) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            NoticeBar(text: tr("AETHER only reads battery values and never changes how the Mac charges. Optimised charging and the charge limit are set in System Settings."),
                      symbol: "info.circle")
            Button(tr("Battery Settings…")) { openBatterySettings() }
                .buttonStyle(CapsuleButtonStyle())
        }
    }

    private func openBatterySettings() {
        // macOS 13+: Erweiterung „Batterie“; ältere Kennung als Rückfall.
        for link in ["x-apple.systempreferences:com.apple.Battery-Settings.extension",
                     "x-apple.systempreferences:com.apple.preference.battery"] {
            if let url = URL(string: link), NSWorkspace.shared.open(url) { return }
        }
    }
}

private struct NoBatteryPanel: View {
    @Environment(\.aether) private var theme
    let battery: BatterySnapshot
    let showThermal: () -> Void

    var body: some View {
        Panel {
            HStack(alignment: .center, spacing: Spacing.l) {
                Image(systemName: "powerplug")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("This Mac has no built-in battery")).font(Typo.metricSmall)
                    Text(tr("It runs on mains power. Temperatures and fans are shown on the Temperature & Fans page."))
                        .font(Typo.callout).foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                ProvenanceBadge(source: .powerSources, timestamp: battery.percent.timestamp, reason: .notPresent)
            }
            Button(tr("Open Temperature & Fans")) { showThermal() }
                .buttonStyle(CapsuleButtonStyle())
        }
    }
}
