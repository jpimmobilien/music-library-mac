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
        .glassSurface(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous), strong: false, elevated: true)
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
                    .font(.system(size: 13, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selected ? theme.accent : theme.textSecondary)
                    .frame(width: 20)
                Text(section.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let phase = section.plannedPhase {
                    // Dezenter Hinweis „in Entwicklung“ – Einzelheiten im Tooltip und auf der Seite selbst
                    Circle()
                        .strokeBorder(theme.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [1.5, 1.5]))
                        .frame(width: 7, height: 7)
                        .opacity(hovering || selected ? 1 : 0.6)
                        .help(tr("In development · Phase %ld", phase))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: Metrics.sidebarRow)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(theme.selectionFill)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(theme.hoverFill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .aetherAnimation(Motion.spring, value: selected)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Drei Live-Werte am Fuß der Seitenleiste.
private struct MiniStatus: View {
    let engine: MonitorEngine

    var body: some View {
        HStack(spacing: Spacing.m) {
            MiniCPU(store: engine.cpu)
            MiniMemory(store: engine.memory)
            MiniThermal(store: engine.power)
        }
    }
}

private struct MiniCPU: View {
    @ObservedObject var store: CPUStore
    @Environment(\.aether) private var theme

    var body: some View {
        MiniValue(label: "CPU", value: store.snapshot?.total.value.map { fmt.percent($0.busy) } ?? "–", color: theme.cpuUser)
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
