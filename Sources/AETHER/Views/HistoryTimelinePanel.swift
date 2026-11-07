import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AetherCore
import AetherSystem

// =============================================================================================
// Lokaler Verlauf: Zeitachse über 1 h … 30 Tage aus den gespeicherten Minutenwerten (nur bei eingeschalteter
// Aufzeichnung) und der Einstellungsbereich „Verlauf“. Lücken (nicht gemessen) bleiben Lücken.
// =============================================================================================

extension HistoryMetric {
    var title: String {
        switch self {
        case .cpu: return tr("CPU usage")
        case .memory: return tr("Memory used")
        case .pressure: return tr("Memory pressure")
        case .swap: return tr("Swap used")
        case .download: return tr("Download")
        case .upload: return tr("Upload")
        case .batteryPercent: return tr("Battery charge")
        case .batteryPower: return tr("Battery power")
        case .temperature: return tr("Hottest sensor")
        case .thermalState: return tr("Thermal state")
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .cpu, .memory: return fmt.percent(value)
        case .pressure:
            guard value > 0 else { return "" }
            return PressureLevel(rawValue: Int(value.rounded())).map(pressureName) ?? ""
        case .swap: return fmt.bytes(value, style: .memory)
        case .download, .upload: return fmt.rate(value)
        case .batteryPercent: return fmt.integer(Int(value.rounded())) + " %"
        case .batteryPower: return fmt.number(value, fractionDigits: 1) + " W"
        case .temperature: return fmt.celsius(value)
        case .thermalState:
            guard value == value.rounded() else { return "" }
            return ThermalLevel(rawValue: Int(value)).map(thermalShortName) ?? ""
        }
    }

    func color(_ theme: AetherTheme) -> Color {
        switch self {
        case .cpu: return theme.cpuUser
        case .memory, .swap: return theme.memory
        case .pressure: return theme.memoryCompressed
        case .download: return theme.networkDown
        case .upload: return theme.networkUp
        case .batteryPercent, .batteryPower: return theme.battery
        case .temperature, .thermalState: return theme.thermal
        }
    }
}

func historyRangeName(_ range: HistoryRange) -> String {
    switch range {
    case .hour: return tr("1 h")
    case .day: return tr("24 h")
    case .week: return tr("7 d")
    case .month: return tr("30 d")
    }
}

/// Verlaufsfeld für eine Seite. `metrics` = wählbare Größen, die erste ist voreingestellt.
struct HistoryTimelinePanel: View {
    @EnvironmentObject private var model: AppModel
    let metrics: [HistoryMetric]

    var body: some View {
        HistoryTimelineContent(store: model.engine.history, metrics: metrics) {
            model.select(.settings)
        }
    }
}

private struct HistoryLoadKey: Equatable {
    var range: HistoryRange
    var revision: Int
    var recording: Bool
}

private struct HistoryTimelineContent: View {
    @ObservedObject var store: HistoryStore
    let metrics: [HistoryMetric]
    let openSettings: () -> Void
    @Environment(\.aether) private var theme
    @State private var range: HistoryRange = .day
    @State private var selected: HistoryMetric?
    @State private var samples: [HistorySample] = []
    @State private var loaded = false
    @State private var windowEnd = Date()

    var body: some View {
        let metric = selected ?? metrics.first ?? .cpu
        Panel {
            HStack(spacing: Spacing.m) {
                PanelTitle(title: tr("Long-term history"), symbol: "clock.arrow.circlepath")
                if store.isRecording {
                    if metrics.count > 1 {
                        Picker("", selection: Binding(get: { metric }, set: { selected = $0 })) {
                            ForEach(metrics) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                    Picker("", selection: $range) {
                        ForEach(HistoryRange.allCases) { item in
                            Text(historyRangeName(item)).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 210)
                }
            }
            if !store.isRecording {
                HStack(alignment: .center, spacing: Spacing.m) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(theme.textSecondary)
                    Text(tr("Long-term history is off. When you turn it on, AETHER stores one average value per minute on this Mac only – nothing is sent."))
                        .font(Typo.callout)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Spacing.s)
                    Button(tr("Turn On in Settings…")) { openSettings() }
                        .buttonStyle(CapsuleButtonStyle())
                }
            } else {
                let start = windowEnd.addingTimeInterval(-range.seconds)
                let points = HistoryBucketing.points(samples, metric: metric, start: start, end: windowEnd, buckets: 180)
                if let summary = HistoryBucketing.summary(samples, metric: metric) {
                    let maximum = metric.fixedMaximum ?? max(points.compactMap(\.value).max() ?? summary.maximum, 0.000_1)
                    TimelineChart(points: points, maximum: maximum, color: metric.color(theme), start: start, end: windowEnd,
                                  range: range, label: { metric.format($0) })
                    HStack(spacing: Spacing.l) {
                        summaryItem(tr("Minimum"), metric.format(summary.minimum))
                        if !metric.usesMaximum { summaryItem(tr("Average"), metric.format(summary.average)) }
                        summaryItem(tr("Maximum"), metric.format(summary.maximum))
                        Spacer(minLength: 0)
                        Text(tr("%ld minutes recorded", summary.count))
                            .font(Typo.caption).foregroundStyle(theme.textTertiary)
                        ProvenanceBadge(source: .localHistory, timestamp: samples.last?.time)
                    }
                } else {
                    Text(loaded ? tr("No values in this period yet. AETHER records one value per minute while it is measuring.")
                                : tr("Loading…"))
                        .font(Typo.callout)
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                }
            }
        }
        .task(id: HistoryLoadKey(range: range, revision: store.revision, recording: store.isRecording)) {
            guard store.isRecording else {
                samples = []
                return
            }
            let result = await store.load(range: range)
            samples = result
            windowEnd = Date()
            loaded = true
        }
    }

    private func summaryItem(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label).font(Typo.caption).foregroundStyle(theme.textSecondary)
            Text(value).font(Typo.captionMedium).monospacedDigit()
        }
    }
}

/// Zeitachse mit Rasterlinien, Werten rechts und Zeitpunkten unten. Lücken werden nicht überbrückt.
private struct TimelineChart: View {
    @Environment(\.aether) private var theme
    let points: [TimelinePoint]
    let maximum: Double
    let color: Color
    let start: Date
    let end: Date
    let range: HistoryRange
    let label: (Double) -> String
    var height: CGFloat = 130

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    VStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { index in
                            Rectangle().fill(theme.hairline).frame(height: 1)
                            if index < 3 { Spacer(minLength: 0) }
                        }
                    }
                    TimelineShape(points: points, maximum: maximum, closed: true)
                        .fill(LinearGradient(colors: [color.opacity(0.26), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    TimelineShape(points: points, maximum: maximum, closed: false)
                        .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
                VStack(alignment: .trailing, spacing: 0) {
                    Text(label(maximum))
                    Spacer(minLength: 0)
                    Text(label(maximum / 2))
                    Spacer(minLength: 0)
                    Text(label(0))
                }
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(theme.textTertiary)
                .frame(width: 70, alignment: .trailing)
            }
            .frame(height: height)
            HStack {
                Text(timeLabel(start))
                Spacer()
                Text(timeLabel(start.addingTimeInterval(end.timeIntervalSince(start) / 2)))
                Spacer()
                Text(tr("now"))
            }
            .font(.system(size: 10))
            .foregroundStyle(theme.textTertiary)
            .padding(.trailing, 78)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(points.last(where: { $0.value != nil })?.value.map(label) ?? tr("No data yet"))
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        switch range {
        case .hour, .day: formatter.setLocalizedDateFormatFromTemplate("jm")
        case .week: formatter.setLocalizedDateFormatFromTemplate("EEEjm")
        case .month: formatter.setLocalizedDateFormatFromTemplate("dMMM")
        }
        return formatter.string(from: date)
    }
}

/// Linienzug je zusammenhängendem Abschnitt; einzelne Werte als kurzer Strich.
private struct TimelineShape: Shape {
    var points: [TimelinePoint]
    var maximum: Double
    var closed: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var segment: [CGPoint] = []
        let stub = max(1.5, rect.width / CGFloat(max(points.count, 1)) / 2)

        func flush() {
            guard !segment.isEmpty else { return }
            if segment.count == 1 {
                let point = segment[0]
                segment = [CGPoint(x: point.x - stub, y: point.y), CGPoint(x: point.x + stub, y: point.y)]
            }
            if closed {
                path.move(to: CGPoint(x: segment[0].x, y: rect.maxY))
                for point in segment { path.addLine(to: point) }
                path.addLine(to: CGPoint(x: segment[segment.count - 1].x, y: rect.maxY))
                path.closeSubpath()
            } else {
                path.move(to: segment[0])
                for point in segment.dropFirst() { path.addLine(to: point) }
            }
            segment = []
        }

        let scale = max(maximum, 0.000_001)
        for point in points {
            if let value = point.value {
                let fraction = CGFloat(min(1, max(0, value / scale)))
                segment.append(CGPoint(x: rect.minX + CGFloat(point.x) * rect.width, y: rect.maxY - fraction * (rect.height - 2) - 1))
            } else {
                flush()
            }
        }
        flush()
        return path
    }
}

// MARK: - Einstellungen

/// Einstellungsbereich „Verlauf“: an/aus, Aufbewahrung, Größe, Export, Löschen (mit Bestätigung).
struct HistorySettingsPanel: View {
    @ObservedObject var store: HistoryStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.aether) private var theme
    @State private var confirmDelete = false
    @State private var message: String?

    var body: some View {
        SettingsPanel(title: tr("History"), symbol: "clock.arrow.circlepath") {
            SettingsRow(title: tr("Record long-term history"),
                        detail: tr("Stores one average value per minute (CPU, memory, network, battery, temperature) in a database on this Mac. Off by default; nothing is ever transmitted.")) {
                Toggle("", isOn: $settings.historyEnabled).toggleStyle(.switch).labelsHidden()
            }
            SettingsRow(title: tr("Keep values for"), detail: tr("Older values are deleted automatically.")) {
                Picker("", selection: $settings.historyRetentionDays) {
                    ForEach(AppSettings.historyRetentionChoices, id: \.self) { days in
                        Text(days == 1 ? tr("1 day") : tr("%ld days", days)).tag(days)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }
            SettingsRow(title: tr("Stored data"), detail: "~/Library/Application Support/AETHER/history.sqlite") {
                Text(store.databaseSize > 0 ? fmt.bytes(store.databaseSize) : tr("None"))
                    .font(Typo.callout)
                    .monospacedDigit()
                    .foregroundStyle(theme.textSecondary)
            }
            HStack(spacing: Spacing.m) {
                if let message {
                    Text(message).font(Typo.caption).foregroundStyle(theme.textSecondary)
                }
                if let error = store.lastError {
                    Text(error).font(Typo.caption).foregroundStyle(theme.statusElevated)
                }
                Spacer()
                Button(tr("Export CSV…")) { export() }
                    .buttonStyle(CapsuleButtonStyle())
                    .disabled(!store.hasStoredData)
                Button(tr("Delete History…")) { confirmDelete = true }
                    .buttonStyle(CapsuleButtonStyle())
                    .disabled(!store.hasStoredData)
            }
        }
        .confirmationDialog(tr("Delete the entire history?"), isPresented: $confirmDelete) {
            Button(tr("Delete History"), role: .destructive) {
                store.deleteAll()
                message = tr("History deleted.")
            }
            Button(tr("Cancel"), role: .cancel) {}
        } message: {
            Text(tr("All stored minute values are removed from this Mac. This can’t be undone."))
        }
        .onAppear { store.refreshSize() }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.title = tr("Export History")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        panel.nameFieldStringValue = "AETHER-History_\(formatter.string(from: Date())).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            do {
                try await store.exportCSV(to: url)
                message = tr("Exported: %@", url.lastPathComponent)
            } catch {
                message = tr("Export failed: %@", error.localizedDescription)
            }
        }
    }
}
