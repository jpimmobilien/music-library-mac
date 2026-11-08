import SwiftUI
import AppKit
import AetherCore

// =============================================================================================
// Designsprache „Studio“ (docs/DESIGN_STUDIO.md): Überzeile → Aussage → große Visualisierung → präzise Zahlen →
// Details. Wenige große Elemente statt vieler kleiner Karten, viel Luft, Licht statt Rahmen.
// =============================================================================================

enum StudioType {
    static let eyebrow = Font.system(size: 13, weight: .semibold)
    static let headline = Font.system(size: 40, weight: .bold)
    static let headlineCompact = Font.system(size: 30, weight: .bold)
    static let lead = Font.system(size: 15)
    static let giant = Font.system(size: 64, weight: .semibold)
    static let giantUnit = Font.system(size: 24, weight: .semibold)
    static let figure = Font.system(size: 30, weight: .semibold)
    static let figureUnit = Font.system(size: 15, weight: .medium)
    static let small = Font.system(size: 20, weight: .semibold)
    static let label = Font.system(size: 12, weight: .medium)
    static let caption = Font.system(size: 11)
}

extension AppSection {
    /// Leitfarbe des Bereichs (Bühnenlicht, Überzeile, Visualisierung).
    func tint(_ theme: AetherTheme) -> Color {
        switch self {
        case .overview, .settings, .files: return theme.accent
        case .activity, .cpuGPU: return theme.cpuUser
        case .memory: return theme.memory
        case .thermal: return theme.thermal
        case .battery: return theme.battery
        case .hardware: return theme.gpu
        case .storage: return theme.storage
        case .network: return theme.networkDown
        }
    }
}

/// Bühnenlicht: weicher, statischer Lichtkegel in der Bereichsfarbe. Rein dekorativ – trägt keine Daten.
struct StageLight: View {
    @Environment(\.aether) private var theme
    let color: Color
    var strength = 1.0

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                RadialGradient(colors: [color.opacity((theme.isDark ? 0.26 : 0.16) * strength), .clear],
                               center: UnitPoint(x: 0.5, y: 0.55), startRadius: 0, endRadius: max(size.width, size.height) * 0.55)
                RadialGradient(colors: [Color.white.opacity((theme.isDark ? 0.05 : 0.35) * strength), .clear],
                               center: UnitPoint(x: 0.5, y: 0.1), startRadius: 0, endRadius: size.width * 0.45)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Seitenrahmen „Studio“.
struct StudioPage<Tools: View, Hero: View, Content: View>: View {
    @Environment(\.aether) private var theme
    let section: AppSection
    let eyebrow: String
    let headline: String
    var lead: String? = nil
    var heroHeight: CGFloat = 340
    @ViewBuilder var tools: () -> Tools
    @ViewBuilder var hero: () -> Hero
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .top, spacing: Spacing.xl) {
                    StudioHeadline(eyebrow: eyebrow, headline: headline, lead: lead, tint: section.tint(theme))
                    Spacer(minLength: Spacing.l)
                    tools()
                }
                .padding(.top, Metrics.headerTop + 6)
                ZStack {
                    StageLight(color: section.tint(theme))
                        .padding(.horizontal, -Spacing.gutter)
                        .padding(.vertical, -40)
                    hero()
                }
                .frame(height: heroHeight)
                content()
            }
            .padding(.horizontal, Spacing.gutter + 8)
            .padding(.bottom, 40)
        }
    }
}

extension StudioPage where Tools == EmptyView {
    init(section: AppSection, eyebrow: String, headline: String, lead: String? = nil, heroHeight: CGFloat = 340,
         @ViewBuilder hero: @escaping () -> Hero, @ViewBuilder content: @escaping () -> Content) {
        self.init(section: section, eyebrow: eyebrow, headline: headline, lead: lead, heroHeight: heroHeight,
                  tools: { EmptyView() }, hero: hero, content: content)
    }
}

/// Kopf einer Detailseite: Überzeile, Aussage, Erklärung und Werkzeuge – darunter die Hero-Visualisierung auf
/// Bühnenlicht. Ersetzt `PageHeader` am Anfang der Seite; die Tafeln mit allen Funktionen folgen darunter.
struct StudioHero<Tools: View, Hero: View>: View {
    @Environment(\.aether) private var theme
    let section: AppSection
    let eyebrow: String
    let headline: String
    var lead: String? = nil
    var height: CGFloat = 300
    @ViewBuilder var tools: () -> Tools
    @ViewBuilder var hero: () -> Hero

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .top, spacing: Spacing.xl) {
                StudioHeadline(eyebrow: eyebrow, headline: headline, lead: lead, tint: section.tint(theme))
                Spacer(minLength: Spacing.l)
                tools()
            }
            .padding(.top, Metrics.headerTop + 6)
            ZStack {
                StageLight(color: section.tint(theme))
                    .padding(.horizontal, -Spacing.gutter)
                    .padding(.vertical, -30)
                hero()
            }
            .frame(height: height)
            .padding(.bottom, 8)
        }
    }
}

extension StudioHero where Tools == EmptyView {
    init(section: AppSection, eyebrow: String, headline: String, lead: String? = nil, height: CGFloat = 300,
         @ViewBuilder hero: @escaping () -> Hero) {
        self.init(section: section, eyebrow: eyebrow, headline: headline, lead: lead, height: height,
                  tools: { EmptyView() }, hero: hero)
    }
}

/// Überzeile, Aussage und Erklärung.
struct StudioHeadline: View {
    @Environment(\.aether) private var theme
    let eyebrow: String
    let headline: String
    var lead: String? = nil
    var tint: Color? = nil
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .font(StudioType.eyebrow)
                .tracking(0.4)
                .foregroundStyle(tint ?? theme.accent)
            Text(headline)
                .font(compact ? StudioType.headlineCompact : StudioType.headline)
                .tracking(-0.5)
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let lead {
                Text(lead)
                    .font(StudioType.lead)
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: 620, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Große Zahl mit Einheit, Beschriftung und optionaler Zusatzzeile.
struct BigFigure: View {
    @Environment(\.aether) private var theme
    let label: String
    let value: String
    var unit: String = ""
    var detail: String? = nil
    var color: Color? = nil
    var size: FigureSize = .figure
    var source: DataSource? = nil
    var reason: UnavailableReason? = nil

    enum FigureSize { case giant, figure, small }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(label).font(StudioType.label).foregroundStyle(theme.textSecondary).lineLimit(1)
                if let source { ProvenanceBadge(source: source, reason: reason) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(valueFont)
                    .monospacedDigit()
                    .foregroundStyle(reason != nil ? theme.textTertiary : (color ?? theme.textPrimary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit).font(unitFont).foregroundStyle(theme.textSecondary)
                }
            }
            if let detail {
                Text(detail).font(StudioType.caption).foregroundStyle(theme.textTertiary).lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var valueFont: Font {
        switch size {
        case .giant: return StudioType.giant
        case .figure: return StudioType.figure
        case .small: return StudioType.small
        }
    }

    private var unitFont: Font {
        switch size {
        case .giant: return StudioType.giantUnit
        case .figure: return StudioType.figureUnit
        case .small: return Typo.callout
        }
    }
}

/// Zahlenreihe ohne Kästen, getrennt durch Haarlinien.
struct FigureRow<Content: View>: View {
    @Environment(\.aether) private var theme
    var spacing: CGFloat = 28
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            content()
        }
        .padding(.vertical, 4)
    }
}

/// Senkrechte Haarlinie zwischen Zahlen.
struct FigureDivider: View {
    @Environment(\.aether) private var theme
    var body: some View {
        Rectangle().fill(theme.hairline).frame(width: 1, height: 44)
    }
}

/// Abschnitt ohne Kasten: Haarlinie, Überschrift, Inhalt.
struct StudioSection<Trailing: View, Content: View>: View {
    @Environment(\.aether) private var theme
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Rectangle().fill(theme.hairline).frame(height: 1)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 20, weight: .semibold)).foregroundStyle(theme.textPrimary)
                    if let subtitle {
                        Text(subtitle).font(Typo.callout).foregroundStyle(theme.textSecondary)
                    }
                }
                Spacer()
                trailing()
            }
            content()
        }
    }
}

extension StudioSection where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

/// Anklickbare Visualisierung: Licht beim Überfahren, Hinweis „Details“, öffnet den zugehörigen Bereich.
struct InteractiveVisual<Content: View>: View {
    @Environment(\.aether) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var hint: String = tr("Details")
    let action: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content()
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 4) {
                        Text(hint)
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(theme.fieldFill))
                    .opacity(hovering ? 1 : 0)
                    .padding(10)
                }
                // Kein Farbfilter (brightness): eingebettete Ebenen (z. B. Datenströme) müssten sonst gefiltert
                // neu zusammengesetzt werden. Rückmeldung: Hinweis „Details“ und leichte Vergrößerung.
                .scaleEffect(hovering && !reduceMotion && theme.motion == .full ? 1.008 : 1)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .aetherAnimation(Motion.easeOut(0.25), value: hovering)
    }
}

/// Zeitraumwahl der Verlaufsdiagramme.
struct RangePicker: View {
    @Binding var range: ChartRange

    var body: some View {
        Picker("", selection: $range) {
            ForEach(ChartRange.allCases) { r in
                Text(rangeName(r)).tag(r)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 260)
    }
}

func rangeName(_ range: ChartRange) -> String {
    switch range {
    case .oneMinute: return tr("1 min")
    case .fiveMinutes: return tr("5 min")
    case .fifteenMinutes: return tr("15 min")
    case .oneHour: return tr("1 h")
    }
}

/// Schriftzug „schematisch“: kennzeichnet Visualisierungen, deren Anordnung nicht der echten Lage entspricht.
struct SchematicNote: View {
    @Environment(\.aether) private var theme
    var text: String = tr("Schematic illustration – values are measured, positions are not.")

    var body: some View {
        Label(text, systemImage: "square.dashed")
            .font(StudioType.caption)
            .foregroundStyle(theme.textTertiary)
    }
}

/// Geglätteter Anzeigewert einer Messgröße als große Zahl (veröffentlicht nur bei sichtbarer Änderung).
struct LiveFigure: View {
    @ObservedObject var metric: MetricValue
    @EnvironmentObject private var settings: AppSettings
    let label: String
    let format: (Double) -> (value: String, unit: String)
    var color: Color? = nil
    var size: BigFigure.FigureSize = .figure
    var source: DataSource? = nil
    var showPeak = false
    var unavailable: UnavailableReason = .awaitingSecondSample

    var body: some View {
        if let display = metric.display(raw: settings.showRawValues), metric.isAvailable {
            let parts = format(display)
            BigFigure(label: label, value: parts.value, unit: parts.unit, detail: detailText, color: color, size: size,
                      source: source)
        } else {
            BigFigure(label: label, value: "–", detail: unavailable.explanation, size: size, source: source, reason: unavailable)
        }
    }

    private var detailText: String? {
        guard showPeak, let peak = metric.value?.peak, let smoothed = metric.value?.smoothed, peak > smoothed * 1.15 else { return nil }
        let parts = format(peak)
        return tr("Peak (10 s): %@", [parts.value, parts.unit].filter { !$0.isEmpty }.joined(separator: " "))
    }
}

/// Aktueller Rohwert („jetzt …“) bzw. geglätteter Wert im Rohwert-Modus – klein unter großen Zahlen.
struct RawReadout: View {
    @ObservedObject var series: MetricSeries
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.aether) private var theme
    let format: (Double) -> String

    var body: some View {
        if let latest = series.latest {
            Text(settings.showRawValues ? tr("smoothed %@", format(latest.smoothed)) : tr("now %@", format(latest.raw)))
                .font(StudioType.caption)
                .monospacedDigit()
                .foregroundStyle(theme.textTertiary)
                .help(tr("Large numbers are smoothed so they don’t flicker; peaks stay visible. This is the value of the latest measurement. Settings → Monitoring switches to raw values."))
        }
    }
}

// MARK: - Formatierung für große Zahlen

enum FigureFormat {
    static func percent(_ value: Double) -> (value: String, unit: String) {
        (fmt.integer(Int((value * 100).rounded())), "%")
    }

    static func rate(_ value: Double) -> (value: String, unit: String) {
        let parts = fmt.rateParts(value)
        return (parts.value, parts.unit)
    }

    static func bytes(_ value: Double) -> (value: String, unit: String) {
        let parts = fmt.byteParts(value, style: .memory)
        return (parts.value, parts.unit)
    }

    /// Werte 0…100 (z. B. Ladestand)
    static func percentInteger(_ value: Double) -> (value: String, unit: String) {
        (fmt.integer(Int(value.rounded())), "%")
    }

    static func celsius(_ value: Double) -> (value: String, unit: String) {
        (fmt.number(value, fractionDigits: 0), "°C")
    }

    static func rpm(_ value: Double) -> (value: String, unit: String) {
        (fmt.integer(Int((value / 10).rounded()) * 10), tr("rpm"))
    }

    static func watts(_ value: Double) -> (value: String, unit: String) {
        (fmt.number(value, fractionDigits: 1), "W")
    }
}
