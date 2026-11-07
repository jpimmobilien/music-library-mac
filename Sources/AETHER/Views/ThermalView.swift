import SwiftUI
import AetherCore

/// Temperatur & Lüfter: Thermalstatus, Sensorbereiche (Mittel/Max, berechnet), alle Sensoren einzeln, Lüfter, Verläufe.
struct ThermalView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.aether) private var theme

    var body: some View {
        let power = model.engine.power
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: theme.density.cardSpacing + 4) {
                PageHeader(title: tr("Temperature & Fans"), subtitle: tr("Real sensor values only – unavailable values are named as such."))
                ThermalStatePanel(store: power, interval: settings.effectiveInterval.seconds)
                SensorGroupsPanel(store: power)
                FansPanel(store: power, interval: settings.effectiveInterval.seconds)
                SensorListPanel(store: power)
                SMCNote(enabled: settings.smcEnabled)
                HistoryTimelinePanel(metrics: [.temperature, .thermalState])
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.gutter)
        }
    }
}

func sensorGroupName(_ group: SensorGroup) -> String {
    switch group {
    case .cpu: return tr("CPU area")
    case .gpu: return tr("Graphics")
    case .memory: return tr("Memory and mainboard")
    case .storage: return tr("Storage")
    case .battery: return tr("Battery")
    case .wireless: return tr("Wireless")
    case .power: return tr("Power and ports")
    case .enclosure: return tr("Enclosure and ambient")
    case .other: return tr("Other sensors")
    }
}

func sensorGroupSymbol(_ group: SensorGroup) -> String {
    switch group {
    case .cpu: return "cpu"
    case .gpu: return SymbolName.gpu
    case .memory: return "memorychip"
    case .storage: return SymbolName.ssd
    case .battery: return SymbolName.battery
    case .wireless: return SymbolName.wifi
    case .power: return "bolt"
    case .enclosure: return "laptopcomputer"
    case .other: return SymbolName.sensor
    }
}

/// Bekannte Sensorbedeutungen (Schlüssel aus `SensorCatalog`) in der Sprache der Oberfläche.
func sensorMeaning(_ meaning: String) -> String {
    switch meaning {
    case "CPU proximity": return tr("CPU proximity")
    case "CPU die": return tr("CPU die")
    case "CPU heatsink": return tr("CPU heatsink")
    case "CPU PECI": return tr("CPU PECI")
    case "CPU system agent": return tr("CPU system agent")
    case "Integrated graphics": return tr("Integrated graphics")
    case "GPU proximity": return tr("GPU proximity")
    case "GPU die": return tr("GPU die")
    case "GPU heatsink": return tr("GPU heatsink")
    case "Battery": return tr("Battery")
    case "Memory proximity": return tr("Memory proximity")
    case "Mainboard": return tr("Mainboard")
    case "Drive proximity": return tr("Drive proximity")
    case "SSD": return tr("SSD")
    case "Wi‑Fi module": return tr("Wi‑Fi module")
    case "Platform controller hub": return tr("Platform controller hub")
    case "Palm rest": return tr("Palm rest")
    case "Ambient": return tr("Ambient")
    case "Airflow left": return tr("Airflow left")
    case "Airflow right": return tr("Airflow right")
    case "Thunderbolt": return tr("Thunderbolt")
    case "Power supply": return tr("Power supply")
    default: return meaning
    }
}

private struct ThermalStatePanel: View {
    @ObservedObject var store: PowerStore
    let interval: Double
    @Environment(\.aether) private var theme

    var body: some View {
        let thermal = store.thermal
        Panel {
            PanelTitle(title: tr("Thermal state"), symbol: SymbolName.thermometer)
            HStack(alignment: .center, spacing: Spacing.xxl) {
                VStack(alignment: .leading, spacing: 4) {
                    if let level = thermal?.state.value {
                        Text(thermalShortName(level)).font(Typo.metricLarge).foregroundStyle(theme.color(for: level))
                    } else {
                        Text("–").font(Typo.metricLarge).foregroundStyle(theme.textTertiary)
                    }
                    HStack(spacing: 6) {
                        Text(tr("Reported by macOS – a classification, not a temperature"))
                            .font(Typo.caption).foregroundStyle(theme.textSecondary)
                        ProvenanceBadge(source: .thermalState, timestamp: thermal?.state.timestamp)
                    }
                }
                Spacer()
                if let hottest = thermal?.hottest {
                    Stat(label: tr("Hottest sensor (%@)", hottest.key), value: fmt.number(hottest.celsius, fractionDigits: 1), unit: "°C",
                         color: theme.thermal)
                }
                if let battery = thermal?.batteryTemperature.value {
                    Stat(label: tr("Battery"), value: fmt.number(battery, fractionDigits: 1), unit: "°C")
                }
            }
            if !store.longHottest.isEmpty {
                HistoryChart(series: [.init(values: store.longHottest.elements, color: theme.thermal)], capacity: slowCapacity,
                             maxValue: max(100, store.longHottest.elements.max() ?? 0), height: 110, label: { fmt.celsius($0) },
                             spanLabel: mediumSpanLabel(interval))
            }
        }
    }
}

private struct SensorGroupsPanel: View {
    @ObservedObject var store: PowerStore
    @Environment(\.aether) private var theme

    var body: some View {
        let sensors = store.thermal?.sensors
        Panel {
            PanelTitle(title: tr("Sensor areas"), symbol: "square.grid.2x2",
                       trailing: sensors?.value.map { tr("%ld sensors", $0.count) })
            if let list = sensors?.value, !list.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: Spacing.m, alignment: .top)], spacing: Spacing.m) {
                    ForEach(SensorCatalog.aggregate(list)) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: sensorGroupSymbol(entry.group)).font(.system(size: 11)).foregroundStyle(theme.thermal)
                                Text(sensorGroupName(entry.group)).font(Typo.captionMedium).foregroundStyle(theme.textSecondary)
                                Spacer()
                                Text(tr("%ld sensors", entry.count)).font(.system(size: 10)).foregroundStyle(theme.textTertiary)
                            }
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                ValueText(value: fmt.number(entry.maximum, fractionDigits: 1), unit: tr("°C max"), font: Typo.metricSmall)
                                Text(tr("Ø %@", fmt.celsius(entry.average))).font(Typo.caption).foregroundStyle(theme.textSecondary)
                                ProvenanceBadge(source: .thermalAggregate)
                            }
                            Sparkline(values: store.groupHistory[entry.group]?.elements ?? [], color: theme.thermal,
                                      capacity: slowCapacity, scaleMax: 110)
                                .frame(height: 26)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).fill(theme.fieldFill))
                    }
                }
                Text(tr("Areas are assigned from sensor keys based on experience – Apple doesn’t document them. Averages and maxima are computed."))
                    .font(Typo.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            } else if let sensors {
                HStack {
                    Text(tr("No temperature sensors available")).font(Typo.bodyMedium)
                    Spacer()
                    UnavailableValue(reason: sensors.reason ?? .notProvidedByMacOS, source: sensors.source, compact: true)
                }
                Text(sensors.reason?.explanation ?? "").font(Typo.caption).foregroundStyle(theme.textSecondary)
            } else {
                Text(tr("Measuring…")).font(Typo.callout).foregroundStyle(theme.textSecondary)
            }
        }
    }
}

private struct FansPanel: View {
    @ObservedObject var store: PowerStore
    let interval: Double
    @Environment(\.aether) private var theme

    var body: some View {
        let fans = store.thermal?.fans
        Panel {
            PanelTitle(title: tr("Fans"), symbol: SymbolName.fan)
            if let list = fans?.value {
                if list.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: SymbolName.fan).font(.system(size: 22, weight: .light)).foregroundStyle(theme.textSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("This Mac has no fan")).font(Typo.bodyMedium)
                            Text(tr("The System Management Controller reports no fans – the Mac is cooled passively."))
                                .font(Typo.caption).foregroundStyle(theme.textSecondary)
                        }
                        Spacer()
                        ProvenanceBadge(source: .smcFans, timestamp: fans?.timestamp)
                    }
                } else {
                    ForEach(list) { fan in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(tr("Fan %ld", fan.index + 1)).font(Typo.bodyMedium)
                                Spacer()
                                ValueText(value: fmt.integer(Int(fan.rpm.rounded())), unit: tr("rpm"), font: Typo.metricSmall)
                                ProvenanceBadge(source: .smcFans, timestamp: fans?.timestamp)
                            }
                            if let fraction = fan.fraction {
                                FillBar(fraction: fraction, color: theme.networkDown, height: 7)
                            }
                            HStack(spacing: Spacing.l) {
                                if let min = fan.minimum { Text(tr("Min %@", fmt.integer(Int(min.rounded())))) }
                                if let max = fan.maximum { Text(tr("Max %@", fmt.integer(Int(max.rounded())))) }
                                if let target = fan.target { Text(tr("Target %@", fmt.integer(Int(target.rounded())))) }
                            }
                            .font(Typo.caption).foregroundStyle(theme.textSecondary).monospacedDigit()
                        }
                    }
                    if !store.longFan.isEmpty {
                        HistoryChart(series: [.init(values: store.longFan.elements, color: theme.networkDown)], capacity: slowCapacity,
                                     maxValue: nil, height: 80, label: { fmt.integer(Int($0.rounded())) },
                                     spanLabel: mediumSpanLabel(interval))
                    }
                    Text(tr("Read-only – AETHER never changes fan speeds."))
                        .font(Typo.caption).foregroundStyle(theme.textTertiary)
                }
            } else if let fans {
                HStack {
                    Text(tr("Fan speeds")).font(Typo.callout).foregroundStyle(theme.textSecondary)
                    Spacer()
                    UnavailableValue(reason: fans.reason ?? .notProvidedByMacOS, source: fans.source, compact: true)
                }
            } else {
                Text(tr("Measuring…")).font(Typo.callout).foregroundStyle(theme.textSecondary)
            }
        }
    }
}

private struct SensorListPanel: View {
    @ObservedObject var store: PowerStore
    @Environment(\.aether) private var theme
    @State private var expanded = false

    var body: some View {
        if let list = store.thermal?.sensors.value, !list.isEmpty {
            Panel {
                HStack {
                    PanelTitle(title: tr("All sensors"), symbol: "list.bullet")
                    Button(expanded ? tr("Hide") : tr("Show all %ld", list.count)) {
                        expanded.toggle()
                    }
                    .buttonStyle(CapsuleButtonStyle())
                }
                if expanded {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: Spacing.l, alignment: .top)], spacing: 6) {
                        ForEach(list.sorted { $0.celsius > $1.celsius }) { sensor in
                            HStack(spacing: 8) {
                                Text(sensor.key).font(Typo.mono).foregroundStyle(theme.textSecondary).frame(width: 40, alignment: .leading)
                                Text(sensor.meaning.map(sensorMeaning) ?? sensorGroupName(sensor.group))
                                    .font(Typo.caption).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(fmt.celsius(sensor.celsius)).font(Typo.captionMedium).monospacedDigit()
                            }
                        }
                    }
                    Text(tr("Keys as reported by the SMC. Names in the list are only shown where the meaning is well established."))
                        .font(Typo.caption).foregroundStyle(theme.textTertiary)
                }
            }
        }
    }
}

private struct SMCNote: View {
    let enabled: Bool

    var body: some View {
        NoticeBar(text: enabled
                  ? tr("Temperatures and fans come from the System Management Controller via public IOKit functions. Apple doesn’t document the keys; AETHER only reads and checks every value for plausibility. You can turn this off in Settings.")
                  : tr("Reading sensors via the SMC is turned off in Settings. The thermal state and battery temperature remain available."),
                  symbol: "info.circle")
    }
}
