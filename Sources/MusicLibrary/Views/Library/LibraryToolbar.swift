import SwiftUI
import AppKit
import MLCore

// Werkzeugkapsel im Kopf jedes Bibliotheksbereichs: Ansicht (fünf Segmente mit gleitender Rosé-Linse),
// Sortierung (sichtbar mit Kriterium und Richtung), Filter (mit Zähler), Darstellung, Mischen, Einstellungen.
// Jede Schaltfläche hat eine Funktion; bei wenig Platz wird die Kapsel kompakter (ViewThatFits).

enum LibraryToolbarStyle {
    /// Im großen Kopf: eigene Glaskapsel, passt sich der Breite an.
    case full
    /// In der kompakten Kopfleiste beim Scrollen (die Kapsel liefert `LibraryScaffold`).
    case collapsed
}

struct LibraryToolbar<F: SortField, Extra: View>: View {
    @EnvironmentObject private var model: AppModel
    let context: LibraryViewContext
    let style: LibraryToolbarStyle
    let sort: Sort<F>
    let setSort: (Sort<F>) -> Void
    let shuffleLabel: String
    let shuffle: (() -> Void)?
    let extra: () -> Extra

    init(context: LibraryViewContext, style: LibraryToolbarStyle, sort: Sort<F>, setSort: @escaping (Sort<F>) -> Void,
         shuffleLabel: String = "Gemischt abspielen", shuffle: (() -> Void)? = nil,
         @ViewBuilder extra: @escaping () -> Extra) {
        self.context = context
        self.style = style
        self.sort = sort
        self.setSort = setSort
        self.shuffleLabel = shuffleLabel
        self.shuffle = shuffle
        self.extra = extra
    }

    var body: some View {
        let mode = model.viewOptions(context).mode
        switch style {
        case .full:
            ViewThatFits(in: .horizontal) {
                capsule(wide: true, mode: mode)
                capsule(wide: false, mode: mode)
            }
        case .collapsed:
            ViewThatFits(in: .horizontal) {
                items(wide: false, mode: mode, minimal: false)
                items(wide: false, mode: mode, minimal: true)
            }
        }
    }

    private func capsule(wide: Bool, mode: LibraryViewMode) -> some View {
        items(wide: wide, mode: mode, minimal: false)
            .padding(.horizontal, 4)
            .frame(height: 40)
            .glassSurface(Capsule(), strong: true)
    }

    private func items(wide: Bool, mode: LibraryViewMode, minimal: Bool) -> some View {
        HStack(spacing: 2) {
            Group {
                if wide {
                    ViewModeSwitcher(selection: mode) { setMode($0) }
                } else {
                    ModeMenuButton(selection: mode) { setMode($0) }
                }
                ToolbarSeparator()
                SortButton(sort: sort, setSort: setSort, labeled: wide)
            }
            if !minimal {
                Group {
                    if context.supportsFilter {
                        FilterButton(model: model, context: context)
                    }
                    ViewOptionsButton(model: model, context: context)
                    ToolbarSeparator()
                    if let shuffle {
                        BarAction(icon: Icons.shuffle, label: shuffleLabel, action: shuffle)
                    }
                    extra()
                }
            }
            SettingsAction()
        }
        .fixedSize()
    }

    private func setMode(_ mode: LibraryViewMode) {
        var options = model.viewOptions(context)
        guard options.mode != mode else { return }
        options.mode = mode
        model.setViewOptions(options, for: context)
    }
}

extension LibraryToolbar where Extra == EmptyView {
    init(context: LibraryViewContext, style: LibraryToolbarStyle, sort: Sort<F>, setSort: @escaping (Sort<F>) -> Void,
         shuffleLabel: String = "Gemischt abspielen", shuffle: (() -> Void)? = nil) {
        self.init(context: context, style: style, sort: sort, setSort: setSort, shuffleLabel: shuffleLabel, shuffle: shuffle,
                  extra: { EmptyView() })
    }
}

/// Feine senkrechte Trennlinie in der Kapsel.
struct ToolbarSeparator: View {
    @Environment(\.musicColors) private var colors

    var body: some View {
        Rectangle()
            .fill(colors.hairline)
            .frame(width: 1, height: 18)
            .padding(.horizontal, 4)
    }
}

// MARK: - Ansicht

/// Fünf Segmente mit gleitender Rosé-Linse (wie die Navigation).
struct ViewModeSwitcher: View {
    @Environment(\.musicColors) private var colors
    let selection: LibraryViewMode
    let onSelect: (LibraryViewMode) -> Void

    private let segment: CGFloat = 32

    var body: some View {
        let modes = LibraryViewMode.allCases
        let index = CGFloat(modes.firstIndex(of: selection) ?? 0)
        ZStack(alignment: .leading) {
            Capsule()
                .fill(colors.accentSoft)
                .overlay(Capsule().strokeBorder(LinearGradient(colors: [colors.glassEdgeLight.opacity(0.6), Color.clear],
                                                               startPoint: .top, endPoint: .bottom), lineWidth: 0.7))
                .frame(width: segment, height: 28)
                .offset(x: segment * index)
                .animation(Motion.lensSpring, value: index)
            HStack(spacing: 0) {
                ForEach(modes, id: \.self) { mode in
                    ModeSegment(mode: mode, selected: mode == selection) { onSelect(mode) }
                        .frame(width: segment, height: 28)
                }
            }
        }
        .padding(2)
        .background(Capsule().fill(colors.textPrimary.opacity(colors.dark ? 0.07 : 0.045)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ansicht")
    }
}

private struct ModeSegment: View {
    @Environment(\.musicColors) private var colors
    let mode: LibraryViewMode
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Icon(mode.libIcon, size: 16, color: selected ? colors.accentText : colors.textPrimary.opacity(hover ? 0.92 : 0.66))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle(scale: 0.88))
        .onHover { hover = $0 }
        .help("Ansicht: \(mode.label)")
        .accessibilityLabel("Ansicht: \(mode.label)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Kompakte Form: ein Symbol, das die fünf Ansichten als Menü zeigt.
struct ModeMenuButton: View {
    let selection: LibraryViewMode
    let onSelect: (LibraryViewMode) -> Void

    var body: some View {
        GlassMenuButton(icon: selection.libIcon, help: "Ansicht: \(selection.label)", width: 230) { menu in
            GlassMenuHeader(title: "Ansicht")
            ForEach(LibraryViewMode.allCases, id: \.self) { mode in
                GlassMenuItem(title: mode.label, icon: mode.libIcon, checked: mode == selection) {
                    onSelect(mode)
                    menu.close()
                }
            }
        }
    }
}

// MARK: - Sortierung

/// Sortierung mit sichtbarem Kriterium und Richtung; Menü mit allen Feldern des Bereichs.
struct SortButton<F: SortField>: View {
    let sort: Sort<F>
    let setSort: (Sort<F>) -> Void
    var labeled: Bool = true

    var body: some View {
        GlassMenuButton(help: "Sortierung: \(sort.label)", width: 280, label: {
            SortButtonLabel(title: sort.field.label, descending: sort.descending, labeled: labeled)
        }) { menu in
            GlassMenuHeader(title: "Sortieren nach")
            ForEach(Array(F.allCases), id: \.self) { field in
                GlassMenuItem(title: field.label, checked: field == sort.field,
                              detail: field == sort.field ? (sort.descending ? "↓" : "↑") : nil) {
                    setSort(field == sort.field ? sort : Sort(field))
                    menu.close()
                }
            }
            GlassMenuDivider()
            GlassMenuHeader(title: "Reihenfolge")
            GlassMenuItem(title: "Aufsteigend · " + sort.field.ascendingLabel, icon: LibIcon.ascending, checked: !sort.descending) {
                setSort(Sort(sort.field, descending: false))
                menu.close()
            }
            GlassMenuItem(title: "Absteigend · " + sort.field.descendingLabel, icon: LibIcon.descending, checked: sort.descending) {
                setSort(Sort(sort.field, descending: true))
                menu.close()
            }
        }
    }
}

struct SortButtonLabel: View {
    @Environment(\.musicColors) private var colors
    let title: String
    let descending: Bool
    let labeled: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 5) {
            Icon(LibIcon.sort, size: 16, color: colors.textPrimary)
            if labeled {
                Text(title)
                    .font(Typo.inter(12, .semibold))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: 132, alignment: .leading)
                Icon(descending ? LibIcon.descending : LibIcon.ascending, size: 12, color: colors.accentText)
            }
        }
        .padding(.horizontal, labeled ? 9 : 0)
        .frame(minWidth: 32, minHeight: 32)
        .background(Capsule().fill(colors.textPrimary.opacity(hover ? 0.07 : 0)))
        .contentShape(Capsule())
        .onHover { hover = $0 }
    }
}

// MARK: - Filter und Darstellung

struct FilterButton: View {
    @ObservedObject var model: AppModel
    let context: LibraryViewContext

    var body: some View {
        let count = model.filter(context).activeCount
        GlassMenuButton(help: count > 0 ? "Filter (\(count) aktiv)" : "Filter", width: 340, label: {
            FilterButtonLabel(count: count)
        }) { menu in
            FilterPanel(model: model, context: context, close: menu.close)
        }
    }
}

struct FilterButtonLabel: View {
    @Environment(\.musicColors) private var colors
    let count: Int
    @State private var hover = false

    var body: some View {
        let active = count > 0
        Icon(LibIcon.filter, size: 17, color: active ? colors.accentText : colors.textPrimary)
            .frame(width: 32, height: 32)
            .background(Circle().fill(active ? colors.accentSoft : colors.textPrimary.opacity(hover ? 0.07 : 0)))
            .overlay(alignment: .topTrailing) {
                if active {
                    Text(verbatim: String(count))
                        .font(Typo.inter(9.5, .bold))
                        .foregroundColor(colors.onAccent)
                        .padding(.horizontal, 3)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(Capsule().fill(colors.accent))
                        .offset(x: 3, y: -1)
                }
            }
            .contentShape(Circle())
            .onHover { hover = $0 }
    }
}

struct ViewOptionsButton: View {
    @ObservedObject var model: AppModel
    let context: LibraryViewContext

    var body: some View {
        GlassMenuButton(icon: LibIcon.options, help: "Darstellung anpassen", width: 300) { _ in
            ViewOptionsPanel(model: model, context: context)
        }
    }
}
