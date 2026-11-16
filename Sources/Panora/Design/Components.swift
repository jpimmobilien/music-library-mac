import SwiftUI
import AppKit
import PanoraCore

// =============================================================================================
// Bausteine der Oberfläche im Aufbau der Musik-App: großer Seitentitel, Suchfeld, Anzahl,
// Werkzeugleiste rechts in einer Glaskapsel, Abschnittsüberschriften mit Linie, Karten mit „Cover“.
// =============================================================================================

struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// Seite mit großem Titel, Suchfeld und Werkzeugleiste – Inhalte laufen unter die Navigation.
struct PageScaffold<Toolbar: View, Content: View>: View {
    @Environment(\.panora) private var colors
    let title: String
    var subtitle: String? = nil
    var search: Binding<String>? = nil
    var searchPrompt: String = "Suchen"
    var bottomInset: CGFloat = 40
    @ViewBuilder var toolbar: () -> Toolbar
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 16) {
                    Text(title)
                        .font(Typo.title())
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 12)
                    toolbar()
                }
                .padding(.bottom, 14)
                if let search {
                    SearchField(text: search, prompt: searchPrompt)
                        .frame(maxWidth: 820)
                        .padding(.bottom, 10)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(Typo.label(13))
                        .foregroundStyle(colors.textSecondary)
                        .padding(.bottom, 18)
                        .padding(.leading, 2)
                }
                content()
            }
            .padding(.horizontal, Metrics.pageInset)
            .padding(.top, Metrics.contentTop)
            .padding(.bottom, bottomInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
    }
}

struct SearchField: View {
    @Environment(\.panora) private var colors
    @Binding var text: String
    var prompt: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(colors.textTertiary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(Typo.body(15))
                .foregroundStyle(colors.textPrimary)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(colors.dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05)))
    }
}

/// Werkzeugleiste rechts: Symbole in einer Glaskapsel.
struct ToolbarCapsule<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 2) { content() }
            .padding(.horizontal, 6)
            .frame(height: 44)
            .glassSurface(Capsule(), strong: false, elevated: false)
    }
}

struct ToolbarIcon: View {
    @Environment(\.panora) private var colors
    let systemName: String
    var label: String? = nil
    var selected = false
    var help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .semibold))
                if let label { Text(label).font(Typo.label(13, .semibold)) }
            }
            .foregroundStyle(selected ? colors.accentText : colors.textPrimary.opacity(hover ? 0.95 : 0.78))
            .padding(.horizontal, label == nil ? 0 : 10)
            .frame(minWidth: 34, minHeight: 32)
            .background(Capsule().fill(selected ? colors.accentSoft : (hover ? colors.hairline : .clear)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hover = $0 }
        .help(help)
    }
}

struct ToolbarDivider: View {
    @Environment(\.panora) private var colors
    var body: some View {
        Rectangle().fill(colors.textPrimary.opacity(0.14)).frame(width: 1, height: 20).padding(.horizontal, 4)
    }
}

/// Abschnitt wie „November 2026 · 2 Alben ———“
struct SectionHeader: View {
    @Environment(\.panora) private var colors
    let title: String
    var count: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(Typo.section(24)).foregroundStyle(colors.textPrimary)
            if let count { Text(count).font(Typo.label(14)).foregroundStyle(colors.textSecondary) }
            Rectangle().fill(colors.hairline).frame(height: 1).alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 8 }
        }
        .padding(.top, 10)
        .padding(.bottom, 14)
    }
}

struct Badge: View {
    @Environment(\.panora) private var colors
    let text: String
    var color: Color? = nil
    var systemImage: String? = nil

    var body: some View {
        let c = color ?? colors.textSecondary
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 9, weight: .bold)) }
            Text(text).font(Typo.label(11, .semibold)).lineLimit(1)
        }
        .foregroundStyle(c)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(c.opacity(0.13)))
    }
}

/// Primäre und sekundäre Schaltfläche.
struct ActionButton: View {
    @Environment(\.panora) private var colors
    let title: String
    var systemImage: String? = nil
    var prominent = false
    var destructive = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(Typo.label(13, .semibold)).lineLimit(1)
            }
            .foregroundStyle(prominent ? Color.white : (destructive ? colors.danger : colors.textPrimary))
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Capsule().fill(prominent ? (destructive ? colors.danger : colors.accent) : (colors.dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))))
            .opacity(disabled ? 0.45 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(disabled)
    }
}

/// „Cover“ eines Modells: Verlauf der Familie, Monogramm, Größe – wie ein Albumcover.
struct ModelCover: View {
    @Environment(\.panora) private var colors
    let family: String
    let name: String
    var detail: String? = nil
    var corner: CGFloat = 12
    var dimmed = false

    var body: some View {
        let c = colors.family(family)
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: c, startPoint: .topLeading, endPoint: .bottomTrailing)
            // Feine Linien wie ein Display (Anlehnung an das App-Symbol)
            HStack(spacing: 6) {
                ForEach(0..<9, id: \.self) { i in
                    Capsule().fill(Color.white.opacity(0.05 + Double(i % 3) * 0.035))
                        .frame(width: 3)
                }
            }
            .padding(.horizontal, 10)
            .rotationEffect(.degrees(0))
            .opacity(0.9)
            VStack(alignment: .leading, spacing: 2) {
                Spacer()
                Text(monogram)
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                if let detail {
                    Text(detail).font(Typo.label(12, .semibold)).foregroundStyle(Color.white.opacity(0.85)).lineLimit(1)
                }
            }
            .padding(14)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .saturation(dimmed ? 0.1 : 1)
        .opacity(dimmed ? 0.55 : 1)
    }

    private var monogram: String {
        switch family {
        case "gpt-oss": return "oss"
        case "Weitere": return String(name.prefix(2))
        default: return family
        }
    }
}

/// Runde „Scheibe“ des arbeitenden Modells – das Gegenstück zur CD im Player der Musik-App.
struct ModelDisc: View {
    @Environment(\.panora) private var colors
    let family: String?
    var active = false
    var size: CGFloat = 92
    @State private var angle: Double = 0

    var body: some View {
        let c = colors.family(family ?? "Weitere")
        ZStack {
            Circle().fill(AngularGradient(colors: [Color(hex: 0xE5E7EB), Color(hex: 0x9CA3AF), Color(hex: 0xF9FAFB), Color(hex: 0xA5B4C4), Color(hex: 0xE5E7EB)],
                                          center: .center))
            Circle().fill(LinearGradient(colors: c, startPoint: .topLeading, endPoint: .bottomTrailing)).padding(size * 0.17)
                .opacity(family == nil ? 0.25 : 1)
            Circle().fill(Color.white.opacity(0.85)).frame(width: size * 0.2, height: size * 0.2)
            Circle().fill(colors.background).frame(width: size * 0.07, height: size * 0.07)
            Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(angle))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .onAppear { if active { spin() } }
        .onChange(of: active) { _, now in
            if now { spin() } else { withAnimation(.easeOut(duration: 0.6)) { angle = angle.rounded() } }
        }
    }

    private func spin() {
        withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { angle += 360 }
    }
}

struct MeterBar: View {
    @Environment(\.panora) private var colors
    let fraction: Double
    var color: Color? = nil
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(colors.hairline)
                Capsule().fill(color ?? colors.accent)
                    .frame(width: max(height, geo.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: height)
    }
}

struct EmptyStateView: View {
    @Environment(\.panora) private var colors
    let systemImage: String
    let title: String
    let text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(colors.accent)
            Text(title).font(Typo.body(18, .semibold)).foregroundStyle(colors.textPrimary)
            Text(text).font(Typo.body(13)).foregroundStyle(colors.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 460)
            if let actionTitle, let action {
                ActionButton(title: actionTitle, prominent: true, action: action).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

/// Info-Zeile „Bezeichnung … Wert“ in Detailkarten.
struct InfoRow: View {
    @Environment(\.panora) private var colors
    let label: String
    let value: String
    var valueColor: Color? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(Typo.label(13)).foregroundStyle(colors.textSecondary)
            Spacer(minLength: 12)
            Text(value).font(Typo.label(13, .semibold)).foregroundStyle(valueColor ?? colors.textPrimary)
                .multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }
}

/// Karte mit Titel für Hardware, Speicher und Einstellungen.
struct PanelCard<Content: View>: View {
    @Environment(\.panora) private var colors
    let title: String
    var systemImage: String? = nil
    var trailing: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 13, weight: .semibold)).foregroundStyle(colors.accent)
                }
                Text(title).font(Typo.body(15, .semibold)).foregroundStyle(colors.textPrimary)
                Spacer()
                if let trailing { Text(trailing).font(Typo.label(12)).foregroundStyle(colors.textTertiary) }
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(colors, radius: 16)
    }
}

extension LicenseTerms {
    func color(_ colors: PanoraColors) -> Color {
        switch self {
        case .permissive: return colors.success
        case .restricted: return colors.warning
        case .nonCommercial: return colors.danger
        case .unknown: return colors.textTertiary
        }
    }
}

/// Lizenz transparent: Offenheit und Bedingungen getrennt.
struct LicenseBadges: View {
    @Environment(\.panora) private var colors
    let license: LicenseInfo

    var body: some View {
        HStack(spacing: 6) {
            Badge(text: license.openness.label, color: license.openness == .openSource ? colors.success : colors.textSecondary)
            Badge(text: "\(license.name) · \(license.terms.label)", color: license.terms.color(colors))
            if license.regionBlock != nil {
                Badge(text: "Regionssperre", color: colors.danger, systemImage: "exclamationmark.triangle.fill")
            }
        }
        .help([license.note, license.regionBlock].compactMap { $0 }.joined(separator: "\n"))
    }
}
