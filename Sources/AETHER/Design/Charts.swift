import SwiftUI
import AppKit
import AetherCore

/// SF-Symbole mit Rückfall: ältere macOS-Versionen kennen manche neueren Namen nicht (z. B. „battery.75percent“
/// auf macOS 13). Der erste vorhandene Name wird verwendet.
enum SymbolName {
    static func pick(_ candidates: String...) -> String {
        for name in candidates where NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
            return name
        }
        return candidates.last ?? "questionmark"
    }

    static let battery = pick("battery.75percent", "battery.100", "bolt")
    static let batteryLow = pick("battery.25percent", "battery.25", "bolt")
    static let fan = pick("fan", "wind", "tornado")
    static let thermometer = pick("thermometer.medium", "thermometer")
    static let wifi = pick("wifi", "antenna.radiowaves.left.and.right")
    static let ethernet = pick("cable.connector", "network")
    static let vpn = pick("lock.shield", "lock")
    static let display = pick("display", "desktopcomputer")
    static let ssd = pick("internaldrive", "externaldrive")
    static let sensor = pick("sensor", "thermometer")
    static let gpu = pick("cube.transparent", "square.stack.3d.up")
    static let process = pick("gearshape.2", "gearshape")
    static let chart = pick("chart.xyaxis.line", "waveform.path.ecg")
}

/// Verlaufsdiagramm mit Rasterlinien und Achsenbeschriftung rechts. Aus einfachen Formen gezeichnet (keine Shader –
/// siehe `Sparkline`). Mehrere Reihen übereinander; gefüllte Reihen wirken bei passender Reihenfolge gestapelt.
struct HistoryChart: View {
    struct Series {
        var values: [Double]
        var color: Color
        var fill: Bool = true
        var lineWidth: CGFloat = 1.6
    }

    @Environment(\.aether) private var theme
    var series: [Series]
    var capacity: Int
    /// Fester Maßstab (z. B. 1 für Anteile); `nil` = am Maximum aller Reihen.
    var maxValue: Double?
    var height: CGFloat = 150
    var label: (Double) -> String
    /// Zeitspanne für die Beschriftung unten („vor 2 min“ … „jetzt“).
    var spanLabel: String?

    var body: some View {
        let maximum = max(maxValue ?? (series.flatMap(\.values).max() ?? 1), 0.000_001)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    // Raster
                    VStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { index in
                            Rectangle().fill(theme.hairline).frame(height: 1)
                            if index < 3 { Spacer(minLength: 0) }
                        }
                    }
                    ForEach(Array(series.enumerated()), id: \.offset) { _, s in
                        Sparkline(values: s.values, color: s.color, capacity: capacity, fill: s.fill, lineWidth: s.lineWidth,
                                  scaleMax: maximum)
                    }
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
                .frame(width: 58, alignment: .trailing)
            }
            .frame(height: height)
            if let spanLabel {
                HStack {
                    Text(spanLabel)
                    Spacer()
                    Text(tr("now"))
                }
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
                .padding(.trailing, 66)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(series.first?.values.last.map { label($0) } ?? tr("No data yet"))
    }
}

/// Senkrechter Balken je Kern.
struct CoreBar: View {
    @Environment(\.aether) private var theme
    let index: Int
    let usage: CPUUsage?
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(theme.fieldFill)
                    if let usage {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Rectangle().fill(tint).frame(height: geo.size.height * CGFloat(min(1, usage.user)))
                            Rectangle().fill(theme.cpuSystem).frame(height: geo.size.height * CGFloat(min(1, usage.system)))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
            }
            .frame(height: 64)
            Text(usage.map { fmt.number($0.busy * 100, fractionDigits: 0) } ?? "–")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text("\(index + 1)")
                .font(.system(size: 9))
                .foregroundStyle(theme.textTertiary)
        }
        .frame(width: 30)
        .aetherAnimation(Motion.easeOut(0.35), value: usage?.busy ?? -1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Core %ld: %@", index + 1, usage.map { fmt.percent($0.busy) } ?? tr("Not available")))
    }
}

/// Kopf eines Abschnitts innerhalb einer Detailseite.
struct PanelTitle: View {
    @Environment(\.aether) private var theme
    let title: String
    var symbol: String? = nil
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.accent)
            }
            Text(title).font(.system(size: 14, weight: .semibold))
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing).font(Typo.caption).foregroundStyle(theme.textSecondary).monospacedDigit()
            }
        }
    }
}

/// Glasfläche für Abschnitte einer Detailseite.
struct Panel<Content: View>: View {
    @Environment(\.aether) private var theme
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            content()
        }
        .padding(theme.density.cardPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassCard()
    }
}

/// Großer Kennwert mit Beschriftung darunter.
struct Stat: View {
    @Environment(\.aether) private var theme
    let label: String
    let value: String
    var unit: String = ""
    var color: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ValueText(value: value, unit: unit, font: Typo.metricSmall, color: color)
            Text(label).font(Typo.caption).foregroundStyle(theme.textSecondary).lineLimit(1)
        }
    }
}

/// Hinweisleiste (Information, keine Warnung).
struct NoticeBar: View {
    @Environment(\.aether) private var theme
    let text: String
    var symbol: String = "info.circle"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(theme.accent)
            Text(text).font(Typo.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(theme.accent.opacity(0.10)))
    }
}

/// Spanne einer Verlaufsanzeige in Worten („letzte 2 min“).
func historySpanLabel(samples: Int, interval: Double) -> String {
    tr("last %@", fmt.duration(seconds: Double(samples) * interval))
}
