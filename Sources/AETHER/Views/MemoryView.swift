import SwiftUI
import AetherCore

/// Arbeitsspeicher: Aufteilung, Speicherdruck mit Verlauf, Swap, Ein-/Auslagerungen und Kompression, größte Verbraucher.
struct MemoryView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.aether) private var theme

    var body: some View {
        let engine = model.engine
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: theme.density.cardSpacing + 4) {
                PageHeader(title: tr("Memory"), subtitle: memorySubtitle(engine.system.hardware))
                MemoryBreakdownPanel(store: engine.memory, system: engine.system)
                MemoryHistoryPanel(store: engine.memory, interval: settings.effectiveInterval.seconds)
                HStack(alignment: .top, spacing: theme.density.cardSpacing) {
                    MemoryActivityPanel(store: engine.memory)
                    TopProcessesPanel(store: engine.processes, metric: .memory)
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.gutter)
        }
    }

    private func memorySubtitle(_ hw: HardwareSummary) -> String {
        guard let physical = hw.physicalMemory else { return "" }
        let size = fmt.bytes(physical, style: .memory)
        return hw.isAppleSilicon ? tr("%@ unified memory – shared by CPU, GPU and Neural Engine", size) : tr("%@ RAM", size)
    }
}

private struct MemoryBreakdownPanel: View {
    @ObservedObject var store: MemoryStore
    @ObservedObject var system: SystemStore
    @Environment(\.aether) private var theme

    var body: some View {
        let breakdown = store.snapshot?.breakdown
        let pressure = store.snapshot?.pressure
        Panel {
            PanelTitle(title: tr("Usage"), symbol: "memorychip")
            if let b = breakdown?.value {
                let used = fmt.byteParts(Double(b.used), style: .memory)
                HStack(alignment: .center, spacing: Spacing.xxl) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            ValueText(value: used.value, unit: used.unit, font: Typo.metricLarge)
                            Text(tr("of %@ used", fmt.bytes(b.physical, style: .memory)))
                                .font(Typo.callout).foregroundStyle(theme.textSecondary)
                        }
                        Text(tr("Used = app memory + wired + compressed"))
                            .font(Typo.caption).foregroundStyle(theme.textTertiary)
                    }
                    Spacer(minLength: 0)
                    if let pressure {
                        PressureGauge(pressure: pressure)
                    }
                }
                let total = Double(max(b.physical, 1))
                SegmentedBar(segments: [(Double(b.app) / total, theme.memory),
                                        (Double(b.wired) / total, theme.memoryWired),
                                        (Double(b.compressed) / total, theme.memoryCompressed),
                                        (Double(b.cached) / total, theme.memoryCached)], height: 14)
                Grid(alignment: .leading, horizontalSpacing: Spacing.xxl, verticalSpacing: 8) {
                    GridRow {
                        part(tr("App memory"), b.app, theme.memory, tr("Memory used by apps and processes."))
                        part(tr("Wired"), b.wired, theme.memoryWired, tr("Kernel memory that can’t be compressed or swapped out."))
                        part(tr("Compressed"), b.compressed, theme.memoryCompressed, tr("Memory macOS has compressed to free space."))
                    }
                    GridRow {
                        part(tr("Cached files"), b.cached, theme.memoryCached, tr("Recently used files; available immediately when needed."))
                        part(tr("Free"), b.free, theme.fieldFill, tr("Neither used nor cache."))
                        if let swap = store.snapshot?.swap.value {
                            part(tr("Swap used"), swap.used, theme.statusElevated,
                                 swap.total > 0 ? tr("of %@ swap space on the startup disk%@", fmt.bytes(swap.total, style: .memory),
                                                     swap.encrypted ? tr(", encrypted") : "")
                                                : tr("No swap file in use."))
                        }
                    }
                }
                HStack(spacing: 6) {
                    if let ratio = store.snapshot?.compressionRatio {
                        Text(tr("Compression ratio %@ : 1", fmt.number(ratio, fractionDigits: 1)))
                            .font(Typo.caption).foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    if let breakdown {
                        ProvenanceBadge(source: breakdown.source, timestamp: breakdown.timestamp)
                    }
                }
            } else if let breakdown {
                UnavailableValue(reason: breakdown.reason ?? .queryFailed, source: breakdown.source)
            } else {
                Text(tr("Measuring…")).font(Typo.callout).foregroundStyle(theme.textSecondary)
            }
        }
    }

    private func part(_ label: String, _ bytes: UInt64, _ color: Color, _ help: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label).font(Typo.caption).foregroundStyle(theme.textSecondary).lineLimit(1)
            }
            Text(fmt.bytes(bytes, style: .memory)).font(Typo.metricSmall).monospacedDigit()
            Text(help).font(.system(size: 10)).foregroundStyle(theme.textTertiary).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 150, alignment: .leading)
    }
}

/// Speicherdruck als dreistufige Anzeige (Systemmeldung).
private struct PressureGauge: View {
    let pressure: Reading<PressureLevel>
    @Environment(\.aether) private var theme

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 6) {
                Text(tr("Memory pressure")).font(Typo.caption).foregroundStyle(theme.textSecondary)
                ProvenanceBadge(source: pressure.source, timestamp: pressure.timestamp, reason: pressure.reason)
            }
            if let level = pressure.value {
                HStack(spacing: 4) {
                    ForEach(PressureLevel.allCases, id: \.self) { step in
                        Capsule()
                            .fill(step <= level ? theme.color(for: level) : theme.fieldFill)
                            .frame(width: 34, height: 8)
                    }
                }
                Text(pressureName(level)).font(Typo.metricSmall).foregroundStyle(theme.color(for: level))
            } else {
                Text(tr("Not available")).font(Typo.callout).foregroundStyle(theme.textSecondary)
            }
        }
    }
}

private struct MemoryHistoryPanel: View {
    @ObservedObject var store: MemoryStore
    let interval: Double
    @Environment(\.aether) private var theme

    var body: some View {
        Panel {
            PanelTitle(title: tr("History"), symbol: SymbolName.chart)
            HistoryChart(series: [.init(values: store.longUsed.elements, color: theme.memory),
                                  .init(values: store.longCompressed.elements, color: theme.memoryCompressed)],
                         capacity: detailCapacity, maxValue: 1, height: 120, label: { fmt.percent($0) },
                         spanLabel: historySpanLabel(samples: detailCapacity, interval: interval))
            // Speicherdruck als Farbband
            GeometryReader { geo in
                let values = store.longPressure.elements
                let step = geo.size.width / CGFloat(max(detailCapacity, 1))
                let offset = CGFloat(max(detailCapacity - values.count, 0)) * step
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.fieldFill)
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        Rectangle()
                            .fill(color(value))
                            .frame(width: max(step, 1), height: 6)
                            .offset(x: offset + CGFloat(index) * step)
                    }
                }
            }
            .frame(height: 6)
            .padding(.trailing, 66)
            HStack(spacing: Spacing.l) {
                LegendItem(color: theme.memory, label: tr("Used"), value: "")
                LegendItem(color: theme.memoryCompressed, label: tr("Compressed"), value: "")
                LegendItem(color: theme.statusNormal, label: tr("Memory pressure (band)"), value: "")
            }
        }
    }

    private func color(_ value: Double) -> Color {
        switch Int(value) {
        case 1: return theme.statusNormal
        case 2: return theme.statusElevated
        case 4: return theme.statusCritical
        default: return theme.fieldFill
        }
    }
}

private struct MemoryActivityPanel: View {
    @ObservedObject var store: MemoryStore
    @Environment(\.aether) private var theme

    var body: some View {
        let activity = store.snapshot?.activity
        let page = Double(store.snapshot?.pageSize ?? 4_096)
        Panel {
            PanelTitle(title: tr("Paging and compression"), symbol: "arrow.left.arrow.right")
            if let a = activity?.value {
                VStack(spacing: 6) {
                    InfoRow(label: tr("Page-ins"), value: fmt.rate(a.pageIns * page))
                    InfoRow(label: tr("Page-outs"), value: fmt.rate(a.pageOuts * page))
                    InfoRow(label: tr("Swap-ins"), value: fmt.rate(a.swapIns * page))
                    InfoRow(label: tr("Swap-outs"), value: fmt.rate(a.swapOuts * page),
                            valueColor: a.swapOuts > 0 ? theme.statusElevated : nil)
                    InfoRow(label: tr("Compressions"), value: fmt.rate(a.compressions * page))
                    InfoRow(label: tr("Decompressions"), value: fmt.rate(a.decompressions * page),
                            source: activity?.source, timestamp: activity?.timestamp)
                }
                Text(tr("Pages per second × page size (%@). Constant swap-outs mean memory is short.",
                        fmt.bytes(UInt64(page), style: .memory)))
                    .font(Typo.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(tr("Measuring…")).font(Typo.callout).foregroundStyle(theme.textSecondary)
            }
        }
    }
}
