import SwiftUI
import AetherCore

// =============================================================================================
// Verlaufsdiagramm (Monitoring 2.0): zeitbasiert, 1 min / 5 min / 15 min / 1 h.
// – Ruhige Linie aus den geglätteten Werten, dahinter ein feines Band Min…Max der Rohwerte je Abschnitt:
//   Spitzen bleiben sichtbar, auch wenn 3 600 Messungen auf 240 Stützstellen gebündelt werden.
// – Nur Vektorformen (keine Shader); keine Animation beim Nachrücken – das Diagramm wird nicht „neu aufgebaut“,
//   sondern rückt einmal je Messung um eine Stützstelle weiter.
// – Lücken (nicht gemessen, Fenster geschlossen) bleiben Lücken.
// =============================================================================================

enum ChartScale {
    /// 0…1 (Anteile)
    case fraction
    /// automatische „schöne“ Obergrenze, mindestens `minimum`
    case auto(minimum: Double)
    case fixed(Double)
}

struct LiveChart: View {
    @ObservedObject var series: MetricSeries
    @ObservedObject var secondary: MetricSeries
    @Environment(\.aether) private var theme
    let range: ChartRange
    var color: Color
    var secondaryColor: Color = .clear
    var scale: ChartScale = .fraction
    var height: CGFloat = 160
    var showsBand = true
    var showsAxis = true
    var label: (Double) -> String = { fmt.percent($0) }

    /// Eine Reihe.
    init(series: MetricSeries, range: ChartRange, color: Color, scale: ChartScale = .fraction, height: CGFloat = 160,
         showsBand: Bool = true, showsAxis: Bool = true, label: @escaping (Double) -> String = { fmt.percent($0) }) {
        self.series = series
        self.secondary = series
        self.range = range
        self.color = color
        self.scale = scale
        self.height = height
        self.showsBand = showsBand
        self.showsAxis = showsAxis
        self.label = label
        self.hasSecondary = false
    }

    /// Zwei Reihen (z. B. Netz ↓/↑).
    init(series: MetricSeries, secondary: MetricSeries, range: ChartRange, color: Color, secondaryColor: Color,
         scale: ChartScale, height: CGFloat = 160, showsBand: Bool = true, showsAxis: Bool = true,
         label: @escaping (Double) -> String) {
        self.series = series
        self.secondary = secondary
        self.range = range
        self.color = color
        self.secondaryColor = secondaryColor
        self.scale = scale
        self.height = height
        self.showsBand = showsBand
        self.showsAxis = showsAxis
        self.label = label
        self.hasSecondary = true
    }

    private let hasSecondary: Bool

    var body: some View {
        let now = max(series.now, secondary.now)
        let primaryRaw = series.raw.buckets(window: range.seconds, now: now, count: range.buckets)
        let primarySmooth = series.smooth.buckets(window: range.seconds, now: now, count: range.buckets)
        let secondaryRaw = hasSecondary ? secondary.raw.buckets(window: range.seconds, now: now, count: range.buckets) : []
        let secondarySmooth = hasSecondary ? secondary.smooth.buckets(window: range.seconds, now: now, count: range.buckets) : []
        let top = upperBound(primaryRaw + secondaryRaw)
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let size = geo.size
                ZStack(alignment: .topLeading) {
                    // Raster
                    ForEach(1..<4) { line in
                        Rectangle()
                            .fill(theme.hairline.opacity(line == 3 ? 0 : 0.7))
                            .frame(height: 1)
                            .offset(y: size.height * CGFloat(line) / 3)
                    }
                    if hasSecondary {
                        layers(raw: secondaryRaw, smooth: secondarySmooth, top: top, size: size, color: secondaryColor)
                    }
                    layers(raw: primaryRaw, smooth: primarySmooth, top: top, size: size, color: color)
                    if showsAxis {
                        Text(label(top))
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(theme.textTertiary)
                            .padding(.horizontal, 5)
                            .background(Capsule().fill(theme.backgroundTop.opacity(0.6)))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .offset(y: -7)
                    }
                }
            }
            .frame(height: height)
            .transaction { $0.animation = nil }
            if showsAxis {
                HStack {
                    Text(tr("−%@", rangeName(range)))
                    Spacer()
                    Text(tr("now"))
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.textTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(primaryRaw))
    }

    @ViewBuilder
    private func layers(raw: [SeriesBucket], smooth: [SeriesBucket], top: Double, size: CGSize, color: Color) -> some View {
        let count = raw.count
        let x: (Int) -> CGFloat = { index in count <= 1 ? 0 : size.width * CGFloat(index) / CGFloat(count - 1) }
        let y: (Double) -> CGFloat = { value in size.height * (1 - CGFloat(min(1, max(0, value / top)))) }
        // Quellen, die seltener messen als ein Abschnitt breit ist, hinterlassen leere Abschnitte – sie werden
        // überbrückt (bis 25 s); echte Lücken bleiben Lücken.
        let bucketSeconds = range.seconds / Double(max(1, count))
        let order = SeriesBucket.drawOrder(raw, bridge: max(1, Int(25 / bucketSeconds)))
        let line: [CGPoint?] = order.map { slot in
            slot.flatMap { i in (smooth.indices.contains(i) ? smooth[i].mean : nil).map { CGPoint(x: x(i), y: y($0)) } }
        }
        ZStack {
            ChartAreaShape(points: line, baseline: size.height)
                .fill(LinearGradient(colors: [color.opacity(theme.isDark ? 0.28 : 0.2), color.opacity(0)],
                                     startPoint: .top, endPoint: .bottom))
            if showsBand {
                ChartBandShape(top: order.map { slot in slot.map { CGPoint(x: x($0), y: y(raw[$0].maximum)) } },
                               bottom: order.map { slot in slot.map { CGPoint(x: x($0), y: y(raw[$0].minimum)) } })
                    .fill(color.opacity(0.16))
            }
            ChartLineShape(points: line)
                .stroke(color, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
        }
    }

    private func upperBound(_ buckets: [SeriesBucket]) -> Double {
        switch scale {
        case .fraction: return 1
        case .fixed(let value): return max(value, 0.000_1)
        case .auto(let minimum):
            let maximum = buckets.filter(\.hasData).map(\.maximum).max() ?? 0
            return NiceScale.upperBound(for: maximum * 1.08, minimum: minimum)
        }
    }

    private func accessibilitySummary(_ buckets: [SeriesBucket]) -> String {
        let values = buckets.filter(\.hasData)
        guard let latest = values.last?.mean, let maximum = values.map(\.maximum).max() else {
            return tr("History: no data yet")
        }
        return tr("History of the last %@: now %@, maximum %@", rangeName(range), label(latest), label(maximum))
    }
}

/// Linie durch die Stützstellen, mit Lücken; weich verbunden (Catmull-Rom → kubische Bézier, ohne Überschwingen
/// über die Nachbarwerte hinaus).
struct ChartLineShape: Shape {
    let points: [CGPoint?]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for run in runs(points) {
            guard let first = run.first else { continue }
            path.move(to: first)
            if run.count == 1 {
                path.addLine(to: CGPoint(x: first.x + 0.5, y: first.y))
                continue
            }
            for i in 1..<run.count {
                let p0 = run[max(0, i - 2)], p1 = run[i - 1], p2 = run[i], p3 = run[min(run.count - 1, i + 1)]
                let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: clamp(p1.y + (p2.y - p0.y) / 6, p1.y, p2.y))
                let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: clamp(p2.y - (p3.y - p1.y) / 6, p1.y, p2.y))
                path.addCurve(to: p2, control1: c1, control2: c2)
            }
        }
        return path
    }
}

/// Fläche unter der Linie (je zusammenhängendem Abschnitt).
struct ChartAreaShape: Shape {
    let points: [CGPoint?]
    let baseline: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for run in runs(points) where run.count > 1 {
            let line = ChartLineShape(points: run.map { Optional($0) }).path(in: rect)
            path.move(to: CGPoint(x: run[0].x, y: baseline))
            path.addLine(to: run[0])
            path.addPath(line)
            path.addLine(to: CGPoint(x: run[run.count - 1].x, y: baseline))
            path.closeSubpath()
        }
        return path
    }
}

/// Band zwischen Höchst- und Tiefstwerten je Abschnitt.
struct ChartBandShape: Shape {
    let top: [CGPoint?]
    let bottom: [CGPoint?]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var index = 0
        while index < top.count {
            guard top[index] != nil else { index += 1; continue }
            var upper: [CGPoint] = []
            var lower: [CGPoint] = []
            while index < top.count, let t = top[index], let b = bottom[index] {
                upper.append(t)
                lower.append(b)
                index += 1
            }
            guard upper.count > 1 else { continue }
            path.move(to: upper[0])
            for point in upper.dropFirst() { path.addLine(to: point) }
            for point in lower.reversed() { path.addLine(to: point) }
            path.closeSubpath()
        }
        return path
    }
}

/// Zusammenhängende Abschnitte ohne Lücken.
private func runs(_ points: [CGPoint?]) -> [[CGPoint]] {
    var result: [[CGPoint]] = []
    var current: [CGPoint] = []
    for point in points {
        if let point {
            current.append(point)
        } else if !current.isEmpty {
            result.append(current)
            current = []
        }
    }
    if !current.isEmpty { result.append(current) }
    return result
}

private func clamp(_ value: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
    min(max(value, min(a, b)), max(a, b))
}
