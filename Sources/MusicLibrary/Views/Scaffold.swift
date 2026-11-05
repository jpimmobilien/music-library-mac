import SwiftUI
import MLCore

/// Meldet die Scrollposition des Inhalts (für die kompakte Kopfleiste).
struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Gerüst aller Bibliotheksansichten (Android `LibraryScaffold`): Der Inhalt scrollt bis unter die Navigation;
/// sobald der große Titel verschwindet, blenden links eine kompakte Glas-Titelkapsel und rechts die Aktionen ein.
/// Detailansichten haben eine schwebende Zurück-Schaltfläche.
struct LibraryScaffold<Content: View, Actions: View>: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors

    let title: String
    var onBack: (() -> Void)? = nil
    /// Inhalt beginnt ganz oben (Detailansichten mit randlosem Kopfbild).
    var edgeToEdgeTop: Bool = false
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var content: () -> Content

    @State private var collapsed = false

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    GeometryReader { g in
                        Color.clear.preference(key: ScrollOffsetKey.self, value: g.frame(in: .named("scaffold")).minY)
                    }
                    .frame(height: 0)
                    content()
                }
                .padding(.top, edgeToEdgeTop ? 0 : Chrome.contentTop)
                .padding(.bottom, Chrome.contentBottom(miniPlayer: player.current != nil) + 12)
            }
            .coordinateSpace(name: "scaffold")
            .onPreferenceChange(ScrollOffsetKey.self) { y in
                let threshold: CGFloat = edgeToEdgeTop ? -260 : -52
                let c = y < threshold
                if c != collapsed { withAnimation(Motion.easeOut(0.22)) { collapsed = c } }
            }

            // Zeile der Navigation: links Zurück + kompakter Titel, rechts Aktionen (die Navigation liegt mittig darüber)
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
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if collapsed {
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
        }
    }
}

extension LibraryScaffold where Actions == EmptyView {
    init(title: String, onBack: (() -> Void)? = nil, edgeToEdgeTop: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, onBack: onBack, edgeToEdgeTop: edgeToEdgeTop, actions: { EmptyView() }, content: content)
    }
}

/// Großer Titel eines Hauptbereichs (Android `LargeTitleHeader`): Titel, Aktionen in einer Glaskapsel,
/// eigenes Suchfeld des Bereichs und eine leise Zusammenfassung.
struct LargeTitleHeader<Actions: View, Below: View>: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    let title: String
    let section: LibrarySection
    let placeholder: String
    var summary: String? = nil
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var below: () -> Below
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(title)
                    .textStyle(Typo.headlineLarge)
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                Spacer()
                ActionCapsule { actions() }
            }
            Spacer().frame(height: 12)
            SearchField(
                text: Binding(get: { model.query(section) }, set: { model.setQuery(section, $0) }),
                placeholder: placeholder,
                focus: $searchFocused
            )
            .frame(maxWidth: 560)
            if let summary {
                Text(summary)
                    .textStyle(Typo.labelMedium)
                    .foregroundColor(colors.textTertiary)
                    .lineLimit(1)
                    .padding(.top, 9)
                    .padding(.leading, 2)
            }
            below()
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .onChange(of: model.searchFocusRequest) { _ in
            if model.section == section { searchFocused = true }
        }
    }
}

extension LargeTitleHeader where Below == EmptyView {
    init(title: String, section: LibrarySection, placeholder: String, summary: String? = nil, @ViewBuilder actions: @escaping () -> Actions) {
        self.init(title: title, section: section, placeholder: placeholder, summary: summary, actions: actions, below: { EmptyView() })
    }
}

/// Zusammenfassung unter dem Titel („1.234 Titel“ bzw. „12 von 1.234 Titeln“).
func librarySummary(_ shown: Int, _ total: Int, searching: Bool, _ format: (Int) -> String) -> String {
    if searching { return "\(Formatting.hits(shown)) von \(format(total))" }
    return format(total)
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
