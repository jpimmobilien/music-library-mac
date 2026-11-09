import SwiftUI
import AppKit
import ABCore

// =============================================================================================
// Wiederkehrende Bausteine aller Seiten: Seitengerüst mit großem Titel und Werkzeugkapsel, Glasknöpfe,
// Suchfeld, Segmente, schwebende Aktionsleiste, Hinweise, Dialogkopf, Einstellungsabschnitte.
// =============================================================================================

/// Gerüst einer Seite: großer Titel mit Untertitel links, Werkzeugkapsel rechts.
/// Die Kopfzeile verschiebt das Fenster (verdeckte Titelleiste). Wird es eng, rücken die Werkzeuge unter den Titel –
/// nichts wird abgeschnitten.
struct PageScaffold<Toolbar: View, Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var toolbar: () -> Toolbar
    @ViewBuilder var content: () -> Content
    @State private var scrolled = false
    @Environment(\.animationsEnabled) private var animations

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: title, subtitle: subtitle, scrolled: scrolled, toolbar: toolbar)
                .zIndex(1)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .coordinateSpace(name: ScrollEdge.space)
        }
        // Scroll-Kante: Sobald Inhalt unter die Kopfleiste läuft, wird sie zur Glasleiste mit Lichtkante.
        .onPreferenceChange(ScrollEdgeKey.self) { offset in
            let now = offset < -3
            guard now != scrolled else { return }
            withAnimation(animations ? .easeOut(duration: 0.28) : nil) { scrolled = now }
        }
    }
}

/// Meldet, wie weit der Inhalt einer Seite gescrollt ist (für die Scroll-Kante der Kopfleiste).
enum ScrollEdge { static let space = "pageScroll" }

struct ScrollEdgeKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = min(value, nextValue()) }
}

extension View {
    /// Am obersten Inhalt innerhalb einer ScrollView anbringen.
    func reportsScrollEdge() -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: ScrollEdgeKey.self, value: geo.frame(in: .named(ScrollEdge.space)).minY)
        })
    }
}

extension PageScaffold where Toolbar == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, subtitle: subtitle, toolbar: { EmptyView() }, content: content)
    }
}

struct PageHeader<Toolbar: View>: View {
    let title: String
    var subtitle: String?
    var scrolled = false
    @ViewBuilder var toolbar: () -> Toolbar
    @Environment(\.glassEnabled) private var glass
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Spacing.l) {
                titles(singleLineSubtitle: true)
                Spacer(minLength: Spacing.m)
                toolbar()
            }
            VStack(alignment: .leading, spacing: Spacing.m) {
                titles(singleLineSubtitle: false)
                toolbar()
            }
            VStack(alignment: .leading, spacing: Spacing.m) {
                titles(singleLineSubtitle: false)
                ScrollView(.horizontal, showsIndicators: false) {
                    toolbar().padding(.vertical, 2)
                }
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.top, Metrics.headerTop)
        .padding(.bottom, Spacing.l)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .bottomLeading)
        .background {
            ZStack {
                WindowDragArea()
                if scrolled {
                    // Glasleiste: Unschärfe, Tönung, Lichtkante unten
                    ZStack(alignment: .bottom) {
                        if glass { BackdropBlur(material: scheme == .dark ? .hudWindow : .headerView) }
                        Palette.glassTint
                        LinearGradient(colors: [Palette.accent.opacity(0), Palette.accent.opacity(0.55), Palette.accent2.opacity(0.45), Palette.accent2.opacity(0)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(height: 1)
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
        }
        .overlay(alignment: .bottom) {
            // weicher Schatten auf die Inhaltskante
            LinearGradient(colors: [Palette.shadow.opacity(0.9), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 14)
                .offset(y: 14)
                .opacity(scrolled ? 1 : 0)
                .allowsHitTesting(false)
        }
    }

    private func titles(singleLineSubtitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Typo.largeTitle)
                .tracking(-0.4)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(Typo.callout)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(singleLineSubtitle ? 1 : 2)
                    .fixedSize(horizontal: singleLineSubtitle, vertical: !singleLineSubtitle)
            }
        }
    }
}

/// Glaskapsel für Werkzeugknöpfe.
struct ToolbarCapsule<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 2) { content() }
            .padding(.horizontal, 4)
            .frame(height: Metrics.toolbarHeight)
            .glassSurface(Capsule(), strong: true)
    }
}

/// Trennstrich innerhalb einer Werkzeugkapsel.
struct ToolbarDivider: View {
    var body: some View {
        Rectangle().fill(Palette.hairline).frame(width: 1, height: 18).padding(.horizontal, 3)
    }
}

/// Runder Symbolknopf für Werkzeugkapseln.
struct ToolbarIconButton: View {
    let symbol: String
    let help: String
    var tint: Color?
    var isOn = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.ui(14, .medium))
                .foregroundStyle(isOn ? Palette.accent : (tint ?? Palette.textPrimary))
                .frame(width: Metrics.toolbarButton, height: Metrics.toolbarButton)
                .background(Circle().fill(isOn ? Palette.selectionFill : (hovering && isEnabled ? Palette.hoverFill : .clear)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering = $0 }
        .animation(.bridgeQuick, value: hovering)
    }
}

/// Menü mit Symbol (für Werkzeugkapseln).
struct ToolbarMenu<Items: View>: View {
    let symbol: String
    let help: String
    @ViewBuilder var items: () -> Items

    var body: some View {
        Menu {
            items()
        } label: {
            Image(systemName: symbol)
                .font(.ui(14, .medium))
                .frame(width: Metrics.toolbarButton, height: Metrics.toolbarButton)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: Metrics.toolbarButton, height: Metrics.toolbarButton)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Rundes Suchfeld in Glas.
struct GlassSearchField: View {
    @Binding var text: String
    var prompt = "Suchen"
    var width: CGFloat = 220
    var focusToken: UUID?
    var focusEnabled = true
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.ui(12.5, .medium))
                .foregroundStyle(Palette.textSecondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(Typo.body)
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Suche leeren")
            }
        }
        .padding(.horizontal, 12)
        .frame(width: width, height: Metrics.searchHeight)
        .glassSurface(Capsule(), strong: true)
        .overlay(Capsule().strokeBorder(Palette.accent.opacity(focused ? 0.55 : 0), lineWidth: 1.5))
        .animation(.bridgeQuick, value: focused)
        .onChange(of: focusToken) { _ in if focusEnabled { focused = true } }
    }
}

/// Eintrag eines Segmentschalters.
struct SegmentOption<Value: Hashable>: Identifiable {
    var id: Value { value }
    let value: Value
    var title: String?
    var symbol: String?
    var help: String?
}

/// Segmentschalter mit gleitender Auswahl.
struct GlassSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [SegmentOption<Value>]
    @Namespace private var ns
    @Environment(\.animationsEnabled) private var animations

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let selected = option.value == selection
                Button {
                    withAnimation(animations ? Motion.lens : nil) { selection = option.value }
                } label: {
                    HStack(spacing: 5) {
                        if let symbol = option.symbol { Image(systemName: symbol).font(.ui(12.5, .medium)) }
                        if let title = option.title { Text(title).font(.ui(12.5, selected ? .semibold : .medium)) }
                    }
                    .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
                    .padding(.horizontal, option.title == nil ? 9 : 12)
                    .frame(height: 26)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Palette.surface)
                                .shadow(color: Palette.shadow, radius: 3, y: 1)
                                .matchedGeometryEffect(id: "selection", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(option.help ?? option.title ?? "")
            }
        }
        .padding(3)
        .background(Capsule().fill(Palette.fieldFill))
    }
}

/// Schwebende Aktionsleiste unten (Auswahl).
struct FloatingActionBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassGroup {
            HStack(spacing: Spacing.m) { content() }
                .padding(.leading, 18)
                .padding(.trailing, 8)
                .frame(height: 50)
                .glassSurface(Capsule(), strong: true, elevated: true)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Zählertext in der Aktionsleiste („12 ausgewählt · 48 MB“).
struct SelectionSummary: View {
    let count: Int
    let bytes: UInt64?

    var body: some View {
        HStack(spacing: 6) {
            Text("\(count)")
                .font(.ui(13, .bold))
                .foregroundStyle(Palette.onAccent)
                .padding(.horizontal, 8)
                .frame(minWidth: 24, minHeight: 22)
                .background(Capsule().fill(Palette.accent))
            Text("ausgewählt").font(Typo.bodyMedium)
            if let bytes {
                Text("· \(ByteFormat.string(bytes))").font(Typo.body).foregroundStyle(Palette.textSecondary).monospacedDigit()
            }
        }
        .fixedSize()
    }
}

/// Kurzer Hinweis unten (verschwindet von selbst).
struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    var symbol: String
    var tint: Color
    var title: String
    var detail: String?
}

struct ToastView: View {
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol)
                .font(.ui(16, .semibold))
                .foregroundStyle(toast.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.title).font(Typo.headline).foregroundStyle(Palette.textPrimary)
                if let d = toast.detail { Text(d).font(Typo.caption).foregroundStyle(Palette.textSecondary) }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .glassSurface(Capsule(), strong: true, elevated: true)
    }
}

/// Kopf eines Dialogs.
struct SheetHeader: View {
    let symbol: String
    var tint: Color = Palette.accent
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            IconTile(symbol: symbol, tint: tint, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Typo.title).foregroundStyle(Palette.textPrimary)
                if let subtitle {
                    Text(subtitle).font(Typo.callout).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Hintergrund eines Dialogs (Glas über der Atmosphäre).
struct SheetChrome: ViewModifier {
    var width: CGFloat?

    func body(content: Content) -> some View {
        content
            .padding(Spacing.xxl)
            .frame(width: width)
            .background(
                ZStack {
                    Palette.background
                    AmbientBackground().opacity(0.6)
                }
            )
    }
}

extension View {
    func sheetChrome(width: CGFloat? = nil) -> some View { modifier(SheetChrome(width: width)) }
}

/// Abschnitt (Einstellungen, Details): Überschrift + Glaskarte.
struct GlassSection<Content: View>: View {
    let title: String
    var symbol: String?
    var footer: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.ui(11.5, .semibold)) }
                Text(title.uppercased()).font(Typo.sectionLabel).tracking(0.7)
            }
            .foregroundStyle(Palette.textSecondary)
            .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 14) { content() }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: Radius.card)
            if let footer {
                Text(footer).font(Typo.caption).foregroundStyle(Palette.textTertiary).padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Zeile „Bezeichnung … Bedienelement“.
struct LabeledRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.bodyMedium).foregroundStyle(Palette.textPrimary)
                if let detail {
                    Text(detail).font(Typo.caption).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Spacing.m)
            control()
        }
    }
}

/// Kennzahl-Kachel.
struct StatTile: View {
    let value: String
    let label: String
    let symbol: String
    var tint: Color = Palette.accent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.ui(15, .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.display(19, .bold)).foregroundStyle(Palette.textPrimary).monospacedDigit().lineLimit(1)
                Text(label).font(Typo.caption).foregroundStyle(Palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Radius.card)
    }
}

/// Kleines Etikett (z. B. „Identisch“, „Ähnlich“, „Vorschlag“).
struct TagLabel: View {
    let text: String
    var symbol: String?
    var tint: Color = Palette.accent

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.ui(9.5, .bold)) }
            Text(text).font(.ui(10.5, .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .frame(height: 19)
        .background(Capsule().fill(tint.opacity(0.13)))
    }
}
