import SwiftUI
import AppKit
import AetherCore

// MARK: - Karte

/// Karte der Übersicht: getöntes Glas, Kopfzeile mit Symbol, Titel und Herkunft. Ein Klick führt in den Bereich.
struct Card<Content: View>: View {
    @Environment(\.aether) private var theme
    let title: String
    let symbol: String
    var tint: Color? = nil
    var action: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: theme.density == .compact ? Spacing.s : Spacing.m) {
            HStack(spacing: Spacing.s) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint ?? theme.accent)
                    .frame(width: 16)
                Text(title.uppercased())
                    .font(Typo.cardTitle)
                    .tracking(0.6)
                    .foregroundStyle(theme.textSecondary)
                Spacer(minLength: 0)
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                        .opacity(hovering ? 1 : 0.55)
                }
            }
            content()
        }
        .padding(theme.density.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard()
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(theme.accent.opacity(hovering && action != nil ? 0.35 : 0), lineWidth: 1)
        )
        .scaleEffect(hovering && action != nil ? 1.006 : 1)
        .aetherAnimation(Motion.quick, value: hovering)
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture { action?() }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(action != nil ? .isButton : [])
    }
}

// MARK: - Zahlen

/// Zahl groß, Einheit klein und sekundär – mit festen Ziffernbreiten, damit Live-Werte nicht springen.
struct ValueText: View {
    @Environment(\.aether) private var theme
    let value: String
    var unit: String = ""
    var font: Font = Typo.metricLarge
    var color: Color? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(font)
                .monospacedDigit()
                .foregroundStyle(color ?? theme.textPrimary)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// Beschriftete Zeile „Name …… Wert“ mit optionaler Herkunft.
struct InfoRow: View {
    @Environment(\.aether) private var theme
    let label: String
    let value: String
    var source: DataSource? = nil
    var timestamp: Date? = nil
    var valueColor: Color? = nil

    var body: some View {
        HStack(spacing: Spacing.s) {
            Text(label)
                .font(Typo.callout)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: Spacing.s)
            Text(value)
                .font(Typo.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(valueColor ?? theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let source {
                ProvenanceBadge(source: source, timestamp: timestamp)
            }
        }
    }
}

// MARK: - Ring

/// Ring mit bis zu zwei Segmenten (z. B. CPU Benutzer + System). Läuft bei Änderung weich nach.
struct MetricRing<Center: View>: View {
    @Environment(\.aether) private var theme
    var segments: [(value: Double, color: Color)]
    var lineWidth: CGFloat = 9
    var size: CGFloat = 92
    var unavailable = false
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(theme.fieldFill, style: StrokeStyle(lineWidth: lineWidth))
            if unavailable {
                Circle()
                    .stroke(theme.statusUnavailable.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
                    .padding(lineWidth / 2)
            } else {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    let start = segments.prefix(index).reduce(0) { $0 + $1.value }
                    Circle()
                        .trim(from: clamp(start), to: clamp(start + segment.value))
                        .stroke(segment.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: index == segments.count - 1 ? .round : .butt))
                        .rotationEffect(.degrees(-90))
                }
            }
            center()
        }
        .frame(width: size, height: size)
        .aetherAnimation(Motion.easeOut(0.45), value: segments.map { $0.value })
    }

    private func clamp(_ v: Double) -> CGFloat { CGFloat(min(1, max(0, v))) }
}

// MARK: - Diagramme

/// Mini-Verlauf aus einfachen Formen (Pfad + Verlaufsfüllung). Bewusst kein `Canvas` und keine Shader-Effekte:
/// Auf manchen virtuellen Intel-Macs bricht das Laden von Metal-Shadern mit einer Assertion ab. Werte 0…1.
struct Sparkline: View {
    var values: [Double]
    var color: Color
    var capacity: Int = 60
    var fill = true
    var lineWidth: CGFloat = 1.6
    /// Fester Maßstab (z. B. 1 für Anteile); `nil` = am Maximum ausrichten.
    var scaleMax: Double? = 1

    var body: some View {
        let maximum = max(scaleMax ?? (values.max() ?? 1), 0.000_001)
        ZStack {
            if fill {
                SparklineShape(values: values, capacity: capacity, maximum: maximum, inset: lineWidth / 2, closed: true)
                    .fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            }
            SparklineShape(values: values, capacity: capacity, maximum: maximum, inset: lineWidth / 2, closed: false)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

struct SparklineShape: Shape {
    var values: [Double]
    var capacity: Int
    var maximum: Double
    var inset: CGFloat
    var closed: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let step = rect.width / CGFloat(max(capacity - 1, 1))
        let offset = CGFloat(max(capacity - values.count, 0)) * step
        for (index, value) in values.enumerated() {
            let x = rect.minX + offset + CGFloat(index) * step
            let fraction = CGFloat(min(1, max(0, value / maximum)))
            let y = rect.maxY - fraction * (rect.height - 2 * inset) - inset
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        if closed {
            path.addLine(to: CGPoint(x: rect.minX + offset + CGFloat(values.count - 1) * step, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + offset, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

/// Gestapelter Balken (z. B. Speicheraufteilung).
struct SegmentedBar: View {
    @Environment(\.aether) private var theme
    var segments: [(value: Double, color: Color)]
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1.5) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    if segment.value > 0.001 {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(segment.color)
                            .frame(width: max(2, geo.size.width * CGFloat(min(1, segment.value))))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background(Capsule().fill(theme.fieldFill))
        .clipShape(Capsule())
        .aetherAnimation(Motion.easeOut(0.4), value: segments.map { $0.value })
    }
}

/// Einfacher Füllbalken.
struct FillBar: View {
    @Environment(\.aether) private var theme
    var fraction: Double
    var color: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.fieldFill)
                Capsule().fill(color).frame(width: max(height, geo.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: height)
        .aetherAnimation(Motion.easeOut(0.4), value: fraction)
    }
}

/// Legendenpunkt mit Text.
struct LegendItem: View {
    @Environment(\.aether) private var theme
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(Typo.caption).foregroundStyle(theme.textSecondary).lineLimit(1)
            Text(value).font(Typo.captionMedium).monospacedDigit().foregroundStyle(theme.textPrimary).lineLimit(1)
        }
    }
}

// MARK: - Status und Herkunft

struct StatusDot: View {
    var color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.6), radius: size / 2)
    }
}

/// Herkunftssymbol (● gemessen, ◐ berechnet, ◇ Systemangabe, ○ Schätzung, ⊘ nicht verfügbar) mit Erklärung auf Klick.
struct ProvenanceBadge: View {
    @Environment(\.aether) private var theme
    let source: DataSource
    var timestamp: Date? = nil
    var reason: UnavailableReason? = nil
    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            glyph
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(reason == nil ? source.provenance.title : tr("Not available"))
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            ProvenanceDetail(source: source, timestamp: timestamp, reason: reason)
        }
        .accessibilityLabel(reason == nil ? source.provenance.title : tr("Not available"))
    }

    @ViewBuilder
    private var glyph: some View {
        let color = theme.textTertiary
        if reason != nil {
            Image(systemName: "nosign").font(.system(size: 9, weight: .semibold)).foregroundStyle(color)
        } else {
            switch source.provenance {
            case .measured:
                Circle().fill(color).frame(width: 6, height: 6)
            case .computed:
                ZStack {
                    Circle().stroke(color, lineWidth: 1).frame(width: 7, height: 7)
                    Circle().trim(from: 0, to: 0.5).fill(color).frame(width: 7, height: 7).rotationEffect(.degrees(90))
                }
            case .systemReported:
                Rectangle().stroke(color, lineWidth: 1).frame(width: 5.5, height: 5.5).rotationEffect(.degrees(45))
            case .estimated:
                Circle().stroke(color, lineWidth: 1).frame(width: 7, height: 7)
            }
        }
    }
}

struct ProvenanceDetail: View {
    let source: DataSource
    var timestamp: Date?
    var reason: UnavailableReason?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reason == nil ? source.provenance.title : tr("Not available"))
                .font(.system(size: 13, weight: .semibold))
            Text(reason?.explanation ?? source.provenance.explanation)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Text(source.explanation)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Text(source.api)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if let timestamp {
                Text(tr("Measured at %@", timestamp.formatted(date: .omitted, time: .standard)))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
    }
}

/// Hinweis anstelle eines Werts: „Nicht verfügbar“ mit kurzer Begründung.
struct UnavailableValue: View {
    @Environment(\.aether) private var theme
    let reason: UnavailableReason
    let source: DataSource
    var compact = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(reason == .awaitingSecondSample ? tr("Measuring…") : tr("Not available"))
                .font(compact ? Typo.callout.weight(.medium) : Typo.metricSmall)
                .foregroundStyle(theme.textSecondary)
            ProvenanceBadge(source: source, reason: reason)
        }
    }
}

/// Kapsel mit Text (Belege im Puls, Zustände).
struct Chip: View {
    @Environment(\.aether) private var theme
    let text: String
    var color: Color? = nil
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            } else if let color {
                Circle().fill(color).frame(width: 6, height: 6)
            }
            Text(text).font(Typo.captionMedium).monospacedDigit().lineLimit(1)
        }
        .foregroundStyle(theme.textPrimary)
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Capsule().fill(theme.fieldFill))
    }
}

/// Abschnittsbeschriftung („LEISTUNG“).
struct SectionLabel: View {
    @Environment(\.aether) private var theme
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Typo.sectionLabel)
            .tracking(0.8)
            .foregroundStyle(theme.textTertiary)
    }
}

// MARK: - Knöpfe

/// Kapselknopf: `prominent` = Akzentfläche, sonst tonales Glas.
struct CapsuleButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        CapsuleButtonBody(configuration: configuration, prominent: prominent)
    }
}

private struct CapsuleButtonBody: View {
    @Environment(\.aether) private var theme
    @Environment(\.isEnabled) private var isEnabled
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 13)
            .frame(height: 28)
            .foregroundStyle(prominent ? theme.onAccent : theme.textPrimary)
            .background {
                if prominent {
                    Capsule().fill(theme.accent)
                    Capsule().fill(Color.white.opacity(hovering && isEnabled ? 0.12 : 0))
                } else {
                    Capsule().fill(theme.fieldFill)
                    Capsule().fill(hovering && isEnabled ? theme.hoverFill : Color.clear)
                }
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
            .animation(Motion.quick, value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Runder Symbolknopf in einer Glaskapsel (Werkzeugleiste).
struct ToolbarIconButton: View {
    @Environment(\.aether) private var theme
    let symbol: String
    let help: String
    var active = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? theme.accent : theme.textPrimary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(hovering ? theme.hoverFill : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering = $0 }
    }
}
