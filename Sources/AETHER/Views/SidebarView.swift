import SwiftUI
import AetherCore

/// Schwebende Glas-Seitenleiste mit Gruppen, verschmelzender Auswahlkapsel und Mini-Status.
struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.aether) private var theme
    @Namespace private var selectionNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WindowDragArea().frame(height: Metrics.trafficLights)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    ForEach(AppSection.SidebarGroup.allCases, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            if let title = group.title {
                                SectionLabel(text: title)
                                    .padding(.horizontal, 10)
                                    .padding(.top, 4)
                                    .padding(.bottom, 3)
                            }
                            ForEach(group.sections) { section in
                                row(section)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, Spacing.m)
            }
            Spacer(minLength: 0)
            Divider().overlay(theme.hairline).padding(.horizontal, 12)
            VStack(alignment: .leading, spacing: Spacing.s) {
                row(.settings)
                MiniStatus(engine: model.engine)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, Spacing.s)
        }
        .frame(maxHeight: .infinity)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous), strong: false, elevated: true, floating: true)
    }

    private func row(_ section: AppSection) -> some View {
        SidebarRow(section: section, selected: model.selection == section, namespace: selectionNamespace) {
            model.select(section)
        }
    }
}

private struct SidebarRow: View {
    @Environment(\.aether) private var theme
    let section: AppSection
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selected ? section.tint(theme) : theme.textSecondary)
                    .frame(width: 20)
                Text(section.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected || hovering ? theme.textPrimary : theme.textPrimary.opacity(0.88))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: Metrics.sidebarRow)
            .background {
                if selected {
                    // Auswahl: weiches Licht in der Bereichsfarbe mit feiner Lichtkante links
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [section.tint(theme).opacity(theme.isDark ? 0.26 : 0.17),
                                                      section.tint(theme).opacity(theme.isDark ? 0.10 : 0.06)],
                                             startPoint: .leading, endPoint: .trailing))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(section.tint(theme))
                                .frame(width: 3, height: 14)
                                .padding(.leading, 2)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(theme.isDark ? 0.07 : 0.5), lineWidth: 0.5))
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.hoverFill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .aetherAnimation(Motion.spring, value: selected)
        .aetherAnimation(Motion.quick, value: hovering)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Drei Live-Werte am Fuß der Seitenleiste.
private struct MiniStatus: View {
    let engine: MonitorEngine

    var body: some View {
        HStack(spacing: Spacing.m) {
            MiniCPU(metric: engine.telemetry.value(.cpuTotal))
            MiniMemory(store: engine.memory)
            MiniThermal(store: engine.power)
        }
    }
}

/// Geglättet wie die großen Zahlen (bzw. roh, wenn eingestellt) – ändert sich nur bei sichtbarer Änderung.
private struct MiniCPU: View {
    @ObservedObject var metric: MetricValue
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.aether) private var theme

    var body: some View {
        let value = metric.isAvailable ? metric.display(raw: settings.showRawValues) : nil
        MiniValue(label: "CPU", value: value.map { fmt.percent($0) } ?? "–", color: theme.cpuUser)
    }
}

private struct MiniMemory: View {
    @ObservedObject var store: MemoryStore
    @Environment(\.aether) private var theme

    var body: some View {
        let pressure = store.snapshot?.pressure.value
        MiniValue(label: tr("RAM"), value: store.snapshot?.breakdown.value.map { fmt.percent($0.usedFraction) } ?? "–",
                  color: pressure.map { theme.color(for: $0) } ?? theme.memory)
    }
}

private struct MiniThermal: View {
    @ObservedObject var store: PowerStore
    @Environment(\.aether) private var theme

    var body: some View {
        let state = store.thermal?.state.value
        MiniValue(label: tr("Thermal"), value: state.map(thermalShortName) ?? "–",
                  color: state.map { theme.color(for: $0) } ?? theme.statusUnavailable)
    }
}

private struct MiniValue: View {
    @Environment(\.aether) private var theme
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(label).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(theme.textTertiary).lineLimit(1)
            }
            Text(value).font(.system(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(theme.textPrimary).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Kurzname des Thermalstatus.
func thermalShortName(_ level: ThermalLevel) -> String {
    switch level {
    case .nominal: return tr("Normal")
    case .fair: return tr("Fair")
    case .serious: return tr("Serious")
    case .critical: return tr("Critical")
    }
}
