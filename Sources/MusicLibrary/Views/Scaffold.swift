import SwiftUI
import MLCore

/// Meldet die Scrollposition des Inhalts (für die kompakte Kopfleiste).
struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Breite des großen Titels (die feste Werkzeugleiste nimmt den Rest der Titelzeile ein).
struct LargeTitleWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Wie weit der große Titel unter die feste Werkzeugleiste gescrollt ist (0…1). Eigenes kleines
/// Beobachtungsobjekt: Beim Scrollen zeichnet sich nur der Verlauf hinter der Leiste neu, nie der Inhalt.
@MainActor
final class ScrollChromeState: ObservableObject {
    @Published private(set) var progress: CGFloat = 0

    func update(offset y: CGFloat) {
        let p = min(max(-y / 44, 0), 1)
        let stepped = (p * 20).rounded() / 20   // 5-%-Schritte: weniger Neuzeichnen
        if stepped != progress { progress = stepped }
    }
}

/// Gerüst aller Bibliotheksansichten (Android `LibraryScaffold`): Der Inhalt scrollt bis unter die Navigation;
/// sobald der große Titel verschwindet, blendet links eine kompakte Glas-Titelkapsel ein (Detailansichten
/// zusätzlich rechts ihre Aktionen). Detailansichten haben eine schwebende Zurück-Schaltfläche.
///
/// v2.1: Übersichten geben ihre Werkzeugleiste als `toolbar` an. Sie bleibt immer sichtbar – fest in der
/// Titelzeile unter der Navigation, rechtsbündig in ihrer Glaskapsel. Der große Titel scrollt darunter weg;
/// ein Verlauf hinter der Zeile blendet dabei ein, sodass Cover nicht unter der Leiste durchscheinen.
/// Gibt die sichtbare Größe als `libraryViewport` weiter (adaptive Spalten, Cover-Flow-Größe).
struct LibraryScaffold<Content: View, Actions: View, Toolbar: View>: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors

    let title: String
    let onBack: (() -> Void)?
    /// Inhalt beginnt ganz oben (Detailansichten mit randlosem Kopfbild).
    let edgeToEdgeTop: Bool
    let actions: () -> Actions
    let toolbar: () -> Toolbar
    let content: () -> Content
    private let hasActions: Bool
    private let pinsToolbar: Bool

    @State private var collapsed = false
    @State private var titleWidth: CGFloat = 0
    @State private var chrome = ScrollChromeState()

    init(title: String, onBack: (() -> Void)? = nil, edgeToEdgeTop: Bool = false,
         @ViewBuilder actions: @escaping () -> Actions, @ViewBuilder toolbar: @escaping () -> Toolbar,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.onBack = onBack
        self.edgeToEdgeTop = edgeToEdgeTop
        self.actions = actions
        self.toolbar = toolbar
        self.content = content
        self.hasActions = Actions.self != EmptyView.self
        self.pinsToolbar = Toolbar.self != EmptyView.self
    }

    var body: some View {
        GeometryReader { outer in
            ZStack(alignment: .top) {
                scroller
                if pinsToolbar {
                    ToolbarFadeBand(state: chrome)
                    toolbarRow(width: outer.size.width)
                }
                topRow
            }
            .environment(\.libraryViewport, Self.quantized(outer.size))
            .environment(\.libraryTopChrome, pinsToolbar ? Chrome.contentTop + Chrome.toolbarRow : Chrome.contentTop)
        }
    }

    /// Größe in 20-pt-Schritten: beim Ziehen am Fensterrand nicht bei jedem Pixel neu aufbauen.
    private static func quantized(_ size: CGSize) -> CGSize {
        CGSize(width: (size.width / 20).rounded(.down) * 20, height: (size.height / 20).rounded(.down) * 20)
    }

    private var scroller: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                GeometryReader { g in
                    Color.clear.preference(key: ScrollOffsetKey.self, value: g.frame(in: .named("scaffold")).minY)
                }
                .frame(height: 0)
                content()
                // Platz für die Auswahlleiste (nur sichtbar, solange etwas ausgewählt ist)
                SelectionBarSpacer()
            }
            .padding(.top, edgeToEdgeTop ? 0 : Chrome.contentTop)
            .padding(.bottom, Chrome.contentBottom(miniPlayer: player.current != nil) + 12)
            .background(LibraryScrollSeedReader().frame(width: 1, height: 1), alignment: .topLeading)
        }
        .coordinateSpace(name: "scaffold")
        .onPreferenceChange(ScrollOffsetKey.self) { y in
            let threshold: CGFloat = edgeToEdgeTop ? -260 : -52
            let c = y < threshold
            if c != collapsed { withAnimation(Motion.easeOut(0.22)) { collapsed = c } }
            if pinsToolbar { chrome.update(offset: y) }
        }
        .onPreferenceChange(LargeTitleWidthKey.self) { w in
            if abs(w - titleWidth) > 0.5 { titleWidth = w }
        }
    }

    /// Feste Werkzeugleiste: genau an der Stelle, an der sie in der Titelzeile stand (kein Springen beim
    /// Scrollen). Sie erhält die Breite neben dem großen Titel und wählt selbst ihre kompakte Form.
    private func toolbarRow(width: CGFloat) -> some View {
        let inset = Spacing.gutter + 4
        let available = max(140, width - inset * 2 - titleWidth - 16)
        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            toolbar()
                .frame(maxWidth: available, alignment: .trailing)
        }
        .frame(height: LargeTitleMetrics.rowHeight)
        .padding(.trailing, inset)
        .padding(.top, Chrome.contentTop + LargeTitleMetrics.topPadding)
        .frame(maxWidth: .infinity, alignment: .topTrailing)
    }

    /// Zeile der Navigation: links Zurück + kompakter Titel, rechts Aktionen (die Navigation liegt mittig darüber).
    private var topRow: some View {
        GeometryReader { geo in
            let side = max(0, (geo.size.width - 560) / 2 - 10)
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    Spacer().frame(width: Chrome.trafficLightsWidth)
                    if let onBack {
                        GlassIconButton(icon: Icons.back, label: "Zurück (⌘[)", size: 34, iconSize: 16, action: onBack)
                            .keyboardShortcut("[", modifiers: .command)
                    }
                    if collapsed {
                        Text(title)
                            .textStyle(Typo.titleMedium)
                            .foregroundColor(colors.textPrimary)
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .glassSurface(Capsule(), strong: true)
                            .layoutPriority(-1)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: side, alignment: .leading)
                .clipped()
                Spacer(minLength: 0)
                // Rechts erhalten die Aktionen genau die verfügbare Breite.
                HStack(spacing: 0) {
                    if collapsed && hasActions {
                        ActionCapsule { actions() }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    Spacer().frame(width: 14)
                }
                .frame(width: side, alignment: .trailing)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: Metrics.navBarHeight)
        .padding(.top, Chrome.topPadding)
        // Leere Stellen dieser Zeile (und darüber) verschieben das Fenster
        .background(WindowDragArea())
    }
}

extension LibraryScaffold where Toolbar == EmptyView {
    /// Detailansichten: Aktionen erscheinen beim Scrollen rechts oben.
    init(title: String, onBack: (() -> Void)? = nil, edgeToEdgeTop: Bool = false,
         @ViewBuilder actions: @escaping () -> Actions, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, onBack: onBack, edgeToEdgeTop: edgeToEdgeTop, actions: actions, toolbar: { EmptyView() }, content: content)
    }
}

extension LibraryScaffold where Actions == EmptyView, Toolbar == EmptyView {
    init(title: String, onBack: (() -> Void)? = nil, edgeToEdgeTop: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, onBack: onBack, edgeToEdgeTop: edgeToEdgeTop, actions: { EmptyView() }, toolbar: { EmptyView() }, content: content)
    }
}

extension LibraryScaffold where Actions == EmptyView {
    /// Übersichten der Bereiche: Werkzeugleiste fest sichtbar in der Titelzeile.
    init(title: String, @ViewBuilder toolbar: @escaping () -> Toolbar, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, onBack: nil, edgeToEdgeTop: false, actions: { EmptyView() }, toolbar: toolbar, content: content)
    }
}

/// Verlauf hinter der festen Werkzeugleiste: blendet ein, sobald der große Titel darunter scrollt – Cover
/// laufen dann weich unter Navigation und Werkzeugleiste aus, statt hart darunter sichtbar zu bleiben.
private struct ToolbarFadeBand: View {
    @Environment(\.musicColors) private var colors
    @ObservedObject var state: ScrollChromeState

    var body: some View {
        let rowEnd = Chrome.contentTop + Chrome.toolbarRow
        let height = rowEnd + 26
        LinearGradient(stops: [
            .init(color: colors.background.opacity(0.9), location: 0),
            .init(color: colors.background.opacity(0.84), location: rowEnd / height),
            .init(color: colors.background.opacity(0), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .opacity(Double(state.progress))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Maße der Titelzeile (gemeinsam für den großen Titel und die feste Werkzeugleiste).
enum LargeTitleMetrics {
    static let topPadding: CGFloat = 4
    static let rowHeight: CGFloat = 40
}

/// Großer Titel eines Hauptbereichs (Android `LargeTitleHeader`): links der Titel (rechts daneben liegt die
/// feste Werkzeugleiste des Gerüsts), darunter das Suchfeld des Bereichs, eine leise Zusammenfassung
/// („12 von 340 Titel“) und die aktiven Filter als entfernbare Chips.
struct LargeTitleHeader<Below: View>: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    let title: String
    let section: LibrarySection
    let placeholder: String
    let summary: String?
    let filterContext: LibraryViewContext?
    let below: () -> Below
    @FocusState private var searchFocused: Bool

    init(title: String, section: LibrarySection, placeholder: String, summary: String? = nil, filterContext: LibraryViewContext? = nil,
         @ViewBuilder below: @escaping () -> Below) {
        self.title = title
        self.section = section
        self.placeholder = placeholder
        self.summary = summary
        self.filterContext = filterContext
        self.below = below
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Text(title)
                    .textStyle(Typo.headlineLarge)
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                    .background(GeometryReader { g in
                        Color.clear.preference(key: LargeTitleWidthKey.self, value: g.size.width)
                    })
                Spacer(minLength: 16)
            }
            // gleiche Höhe wie die feste Werkzeugleiste daneben
            .frame(height: LargeTitleMetrics.rowHeight)
            Spacer().frame(height: 12)
            SearchField(
                text: Binding(get: { model.liveQuery(section) }, set: { model.setQuery(section, $0) }),
                placeholder: placeholder,
                focus: $searchFocused
            )
            .frame(maxWidth: 560)
            summaryRow
            below()
        }
        .padding(.horizontal, 4)
        .padding(.top, LargeTitleMetrics.topPadding)
        .padding(.bottom, 8)
        .onChange(of: model.searchFocusRequest) { _ in
            if model.section == section { searchFocused = true }
        }
    }

    @ViewBuilder
    private var summaryRow: some View {
        if summary != nil || filterContext != nil {
            HStack(alignment: .center, spacing: 10) {
                if let summary {
                    Text(summary)
                        .textStyle(Typo.labelMedium)
                        .foregroundColor(colors.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
                if let filterContext {
                    ActiveFilterChips(context: filterContext)
                }
            }
            .padding(.top, 9)
            .padding(.leading, 2)
        }
    }
}

extension LargeTitleHeader where Below == EmptyView {
    init(title: String, section: LibrarySection, placeholder: String, summary: String? = nil, filterContext: LibraryViewContext? = nil) {
        self.init(title: title, section: section, placeholder: placeholder, summary: summary, filterContext: filterContext,
                  below: { EmptyView() })
    }
}

/// Kopf einer Detailansicht mit fester Höhe (Hero liegt hinter dem Inhalt, Inhalt folgt darunter).
struct DetailHeader<Artwork: View, Buttons: View>: View {
    @Environment(\.musicColors) private var colors
    let backdrop: NSImage?
    var tint: Color? = nil
    let title: String
    var eyebrow: String? = nil
    var subtitle: String? = nil
    var onSubtitle: (() -> Void)? = nil
    var meta: String? = nil
    @ViewBuilder var artwork: () -> Artwork
    @ViewBuilder var buttons: () -> Buttons
    @State private var width: CGFloat = 1000

    var body: some View {
        let wide = width > 760
        ZStack(alignment: .top) {
            HeroBackdrop(image: backdrop, tint: tint)
                .frame(height: wide ? 430 : 560)
                .frame(maxWidth: .infinity)
                .clipped()
            Group {
                if wide {
                    HStack(alignment: .bottom, spacing: 30) {
                        artwork()
                        texts(alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Spacing.gutter + 8)
                } else {
                    VStack(spacing: 0) {
                        artwork()
                        Spacer().frame(height: 18)
                        texts(alignment: .center)
                    }
                    .padding(.horizontal, Spacing.gutter)
                }
            }
            .padding(.top, Chrome.contentTop + (wide ? 22 : 8))
            .padding(.bottom, 18)
        }
        .background(GeometryReader { g in Color.clear.onAppear { width = g.size.width }.onChange(of: g.size.width) { width = $0 } })
    }

    @ViewBuilder
    private func texts(alignment: HorizontalAlignment) -> some View {
        let text: TextAlignment = alignment == .center ? .center : .leading
        VStack(alignment: alignment, spacing: 0) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .textStyle(Typo.sectionLabel)
                    .foregroundColor(colors.accentText)
                Spacer().frame(height: 4)
            }
            Text(title)
                .textStyle(Typo.displaySmall)
                .foregroundColor(colors.textPrimary)
                .multilineTextAlignment(text)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Button { onSubtitle?() } label: {
                    Text(subtitle)
                        .textStyle(Typo.titleLarge)
                        .foregroundColor(colors.accentText)
                        .multilineTextAlignment(text)
                        .lineLimit(2)
                }
                .buttonStyle(.plain)
                .disabled(onSubtitle == nil)
                .padding(.top, 2)
            }
            if let meta {
                Text(meta)
                    .textStyle(Typo.bodySmall)
                    .foregroundColor(colors.textSecondary)
                    .multilineTextAlignment(text)
                    .padding(.top, 5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer().frame(height: 16)
            HStack(spacing: 10) { buttons() }
        }
    }
}
