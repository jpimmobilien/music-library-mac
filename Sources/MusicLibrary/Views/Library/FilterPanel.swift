import SwiftUI
import AppKit
import MLCore

// Filter je Bereich: Schnellfilter, Genres, Jahrzehnte, Formate und Interpreten (durchsuchbar) als Glas-Popover;
// aktive Filter erscheinen zusätzlich als entfernbare Chips unter dem Titel.

struct FilterPanel: View {
    @ObservedObject var model: AppModel
    @Environment(\.musicColors) private var colors
    let context: LibraryViewContext
    let close: () -> Void
    @State private var artistQuery = ""
    @State private var allGenres = false

    var body: some View {
        let filter = model.filter(context)
        let facets = model.facets
        VStack(alignment: .leading, spacing: 0) {
            header(filter)
            quickSection(filter)
            if !facets.genres.isEmpty { genreSection(filter, facets.genres) }
            if !facets.decades.isEmpty { decadeSection(filter, facets.decades) }
            if facets.formats.count > 1 || !filter.formats.isEmpty { formatSection(filter, facets.formats) }
            if !facets.artists.isEmpty { artistSection(filter, facets.artists) }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }

    private func header(_ filter: LibraryFilter) -> some View {
        HStack(spacing: 8) {
            Text("Filter")
                .textStyle(Typo.titleMedium)
                .foregroundColor(colors.textPrimary)
            if filter.activeCount > 0 {
                Text(verbatim: "\(filter.activeCount) aktiv")
                    .textStyle(Typo.labelSmall)
                    .foregroundColor(colors.accentText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(colors.accentSoft))
            }
            Spacer()
            Button {
                model.setFilter(LibraryFilter(), for: context)
            } label: {
                HStack(spacing: 4) {
                    Icon(LibIcon.filterOff, size: 14, color: filter.isEmpty ? colors.textTertiary : colors.accentText)
                    Text("Zurücksetzen")
                        .font(Typo.inter(12, .semibold))
                        .foregroundColor(filter.isEmpty ? colors.textTertiary : colors.accentText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(filter.isEmpty)
            .help("Alle Filter dieses Bereichs entfernen")
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func quickSection(_ filter: LibraryFilter) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GlassMenuHeader(title: "Schnellfilter")
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(QuickFilter.allCases, id: \.self) { quick in
                    ChoiceChip(title: quick.label, selected: filter.quick.contains(quick)) {
                        update { $0.quick = toggled($0.quick, quick) }
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private func genreSection(_ filter: LibraryFilter, _ genres: [FacetValue]) -> some View {
        let limit = 18
        let shown: [FacetValue] = allGenres ? genres : genres.enumerated().filter { $0.offset < limit || filter.genres.contains($0.element.id) }.map(\.element)
        return VStack(alignment: .leading, spacing: 0) {
            GlassMenuHeader(title: "Genres")
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(shown) { genre in
                    ChoiceChip(title: genre.label, selected: filter.genres.contains(genre.id)) {
                        update { $0.genres = toggled($0.genres, genre.id) }
                    }
                }
                if genres.count > limit {
                    ChoiceChip(title: allGenres ? "Weniger" : "Alle \(genres.count) …", selected: false) {
                        withAnimation(Motion.easeOut(Motion.short)) { allGenres.toggle() }
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private func decadeSection(_ filter: LibraryFilter, _ decades: [FacetValue]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GlassMenuHeader(title: "Jahrzehnte")
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(decades) { decade in
                    let value = Int(decade.id) ?? -1
                    ChoiceChip(title: decade.label, selected: filter.decades.contains(value)) {
                        update { $0.decades = toggled($0.decades, value) }
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private func formatSection(_ filter: LibraryFilter, _ formats: [FacetValue]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GlassMenuHeader(title: "Formate")
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(formats) { format in
                    ChoiceChip(title: format.label, selected: filter.formats.contains(format.id)) {
                        update { $0.formats = toggled($0.formats, format.id) }
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private func artistSection(_ filter: LibraryFilter, _ artists: [FacetValue]) -> some View {
        let query = TextNorm.key(artistQuery)
        let matching: [FacetValue] = query.isEmpty ? artists : artists.filter { TextNorm.key($0.label).contains(query) }
        return VStack(alignment: .leading, spacing: 0) {
            GlassMenuHeader(title: "Interpreten")
            SearchField(text: $artistQuery, placeholder: "Interpret suchen")
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(matching) { artist in
                        FilterCheckRow(title: artist.label, count: artist.count, checked: filter.artists.contains(artist.id)) {
                            update { $0.artists = toggled($0.artists, artist.id) }
                        }
                    }
                }
            }
            .frame(height: 168)
            .overlay(alignment: .top) {
                if matching.isEmpty {
                    Text("Kein Interpret gefunden")
                        .textStyle(Typo.labelMedium)
                        .foregroundColor(colors.textTertiary)
                        .padding(.top, 12)
                }
            }
        }
    }

    private func update(_ change: (inout LibraryFilter) -> Void) {
        var filter = model.filter(context)
        change(&filter)
        model.setFilter(filter, for: context)
    }

    private func toggled<T: Hashable>(_ set: Set<T>, _ value: T) -> Set<T> {
        var copy = set
        if copy.contains(value) { copy.remove(value) } else { copy.insert(value) }
        return copy
    }
}

/// Zeile mit Häkchen (Interpretenliste im Filter).
private struct FilterCheckRow: View {
    @Environment(\.musicColors) private var colors
    let title: String
    let count: Int
    let checked: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(checked ? Color.clear : colors.textTertiary.opacity(0.6), lineWidth: 1.2)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(checked ? colors.accent : Color.clear))
                    if checked { Icon(Icons.check, size: 11, color: colors.onAccent) }
                }
                .frame(width: 15, height: 15)
                Text(title)
                    .font(Typo.inter(12.5, checked ? .semibold : .regular))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(verbatim: Formatting.integer(count))
                    .font(Typo.inter(11, .medium))
                    .monospacedDigit()
                    .foregroundColor(colors.textTertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hover ? colors.accent.opacity(colors.dark ? 0.2 : 0.1) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

// MARK: - Aktive Filter unter dem Titel

/// Ein aktiver Filter als entfernbarer Chip.
private struct FilterChipValue: Identifiable {
    let id: String
    let title: String
    let remove: (inout LibraryFilter) -> Void
}

struct ActiveFilterChips: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    let context: LibraryViewContext

    var body: some View {
        let filter = model.filter(context)
        if !filter.isEmpty {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(chips(filter)) { chip in
                    RemovableChip(title: chip.title) {
                        var f = model.filter(context)
                        chip.remove(&f)
                        model.setFilter(f, for: context)
                    }
                }
                Button {
                    model.setFilter(LibraryFilter(), for: context)
                } label: {
                    Text("Alle entfernen")
                        .font(Typo.inter(11.5, .semibold))
                        .foregroundColor(colors.accentText)
                        .frame(height: 24)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Alle Filter dieses Bereichs entfernen")
            }
        }
    }

    private func chips(_ f: LibraryFilter) -> [FilterChipValue] {
        let facets = model.facets
        func label(_ list: [FacetValue], _ id: String) -> String { list.first(where: { $0.id == id })?.label ?? id }
        var out: [FilterChipValue] = []
        for quick in QuickFilter.allCases where f.quick.contains(quick) {
            out.append(FilterChipValue(id: "q:" + quick.rawValue, title: quick.label, remove: { $0.quick.remove(quick) }))
        }
        for id in f.genres.sorted() {
            out.append(FilterChipValue(id: "g:" + id, title: label(facets.genres, id), remove: { $0.genres.remove(id) }))
        }
        for decade in f.decades.sorted() {
            out.append(FilterChipValue(id: "d:" + String(decade), title: String(decade) + "er", remove: { $0.decades.remove(decade) }))
        }
        for id in f.artists.sorted() {
            out.append(FilterChipValue(id: "a:" + id, title: label(facets.artists, id), remove: { $0.artists.remove(id) }))
        }
        for id in f.formats.sorted() {
            out.append(FilterChipValue(id: "f:" + id, title: label(facets.formats, id), remove: { $0.formats.remove(id) }))
        }
        return out
    }
}

private struct RemovableChip: View {
    @Environment(\.musicColors) private var colors
    let title: String
    let remove: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: remove) {
            HStack(spacing: 4) {
                Text(title)
                    .font(Typo.inter(11.5, .medium))
                    .foregroundColor(colors.accentText)
                    .lineLimit(1)
                Icon(Icons.clear, size: 11, color: colors.accentText.opacity(hover ? 1 : 0.7))
            }
            .padding(.leading, 10)
            .padding(.trailing, 7)
            .frame(height: 24)
            .background(Capsule().fill(colors.accentSoft))
            .overlay(Capsule().strokeBorder(colors.accent.opacity(hover ? 0.5 : 0), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle(scale: 0.95))
        .onHover { hover = $0 }
        .help("Filter „\(title)“ entfernen")
        .accessibilityLabel("Filter \(title) entfernen")
    }
}

// MARK: - Keine Treffer

/// Leerer Zustand bei Suche/Filter ohne Ergebnis – mit „Filter zurücksetzen“, wenn ein Filter aktiv ist.
struct NoMatchesView: View {
    @EnvironmentObject private var model: AppModel
    let context: LibraryViewContext
    let query: String
    /// z. B. „Kein Titel“, „Kein Album“.
    let noun: String

    var body: some View {
        let filtered = !model.filter(context).isEmpty
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let searchPart: String = trimmed.isEmpty ? "" : " zu „\(trimmed)“"
        if filtered {
            EmptyStateView(icon: LibIcon.filterOff, title: "Keine Treffer",
                           text: "\(noun) passt\(searchPart) mit den gewählten Filtern.") {
                PillButton(title: "Filter zurücksetzen", icon: LibIcon.filterOff) {
                    model.setFilter(LibraryFilter(), for: context)
                }
            }
        } else {
            EmptyStateView(icon: Icons.search, title: "Keine Treffer", text: "\(noun) passt\(searchPart).")
        }
    }
}
