import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MLCore

// Sammlungen (Alben, Interpreten, Genres, Playlists) in allen fünf Ansichten: Raster, kompaktes Raster,
// Liste, Detailliste und Cover Flow. Kacheln und Zeilen sind schlanke `Equatable`-Werte ohne
// Umgebungsobjekte – wichtig für flüssiges Scrollen mit 1.600 Alben auf älteren Macs.

// MARK: - Wechsel der Ansicht, Zoom per Trackpad

/// Liest die gespeicherten Ansichtsoptionen eines Bereichs, blendet beim Wechsel weich über und
/// verändert die Covergröße per Zwei-Finger-Zoom (gespeichert beim Loslassen).
struct LibraryModeHost<Content: View>: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var live = LibraryLiveState.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let context: LibraryViewContext
    @ViewBuilder let content: (LibraryViewOptions) -> Content
    @State private var pinchBase: Double?

    var body: some View {
        let stored = model.viewOptions(context)
        let options = live.apply(stored, context)
        let level = model.settings.animationLevel
        ZStack(alignment: .top) {
            content(options)
                .id(options.mode)
                .transition(LibraryMotion.modeTransition(level, reduceMotion: reduceMotion))
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(LibraryMotion.modeAnimation(level, reduceMotion: reduceMotion), value: options.mode)
        .simultaneousGesture(pinch(stored))
    }

    private func pinch(_ stored: LibraryViewOptions) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard stored.mode.usesCoverSize else { return }
                let base = pinchBase ?? stored.coverSize
                if pinchBase == nil { pinchBase = base }
                live.coverSize[context] = LibraryLiveState.clampCover(base * Double(value))
            }
            .onEnded { value in
                guard let base = pinchBase else { return }
                pinchBase = nil
                var options = model.viewOptions(context)
                options.coverSize = LibraryLiveState.clampCover(base * Double(value)).rounded()
                model.setViewOptions(options, for: context)
                live.coverSize[context] = nil
            }
    }
}

// MARK: - Sammlung

/// Alben, Interpreten, Genres oder Playlists in der gewählten Ansicht.
///
/// Auswahl (v2.1): ⌘-Klick wählt einzeln, ⇧-Klick einen Bereich, Aufziehen eines Rahmens (auf freier Fläche
/// sofort, auf einem Eintrag nach kurzem Halten) wählt mehrere. Kontextmenü, Ziehen & Ablegen und die
/// Auswahlleiste wirken dann auf die ganze Auswahl. Ein einfacher Klick öffnet wie bisher.
struct LibraryCollection<Element: Identifiable, MenuContent: View>: View where Element.ID == String {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.libraryViewport) private var viewport
    @Environment(\.libraryTopChrome) private var topChrome
    @Environment(\.libraryMarqueeTail) private var marqueeTail
    @Environment(\.displayScale) private var displayScale
    let context: LibraryViewContext
    let elements: [Element]
    let options: LibraryViewOptions
    let makeItem: (Element) -> LibraryItem
    let actions: CollectionActions
    var table: CollectionTable<Element>? = nil
    @ViewBuilder let menu: (CollectionMenuTarget) -> MenuContent
    @State private var selection: Set<String> = []
    @State private var anchor: Int?
    @State private var dropTarget: String?
    @State private var owner = UUID()
    @StateObject private var marquee = MarqueeController<String>()

    var body: some View {
        let generation = configureMarquee(layoutGeneration())
        Group {
            switch options.mode {
            case .grid, .compactGrid: grid(generation)
            case .list: list(generation)
            case .detailedList: detailed(generation)
            case .coverFlow: coverFlow
            }
        }
        .onChange(of: selection) { ids in publishSelection(ids) }
        .onChange(of: elements.map(\.id)) { ids in
            // nach Suche/Filter/Neueinlesen: nur noch vorhandene Einträge bleiben gewählt
            let valid = selection.intersection(ids)
            if valid != selection { selection = valid } else if !selection.isEmpty { publishSelection(selection) }
        }
        .onAppear { applySeed() }
        .onDisappear { LibrarySelectionStore.shared.withdraw(owner: owner) }
    }

    // MARK: Raster

    private func grid(_ generation: Int) -> some View {
        let metrics = TileMetrics(options: options, available: TileMetrics.available(viewport), scale: displayScale)
        return LazyVGrid(columns: metrics.columns, alignment: .leading, spacing: metrics.rowSpacing) {
            ForEach(Array(elements.enumerated()), id: \.element.id) { index, element in
                tile(index, element, metrics.style, generation)
            }
        }
        .marqueeContainer(marquee)
        .padding(.top, 8)
    }

    private func tile(_ index: Int, _ element: Element, _ style: TileStyle, _ generation: Int) -> some View {
        let item = makeItem(element)
        let favoriteAction: (() -> Void)? = item.favorite == nil ? nil : { actions.toggleFavorite?(item) }
        let view = CollectionTile(
            item: item,
            style: style,
            selected: selection.contains(item.id),
            dropTargeted: dropTarget == item.id,
            playing: item.current && player.isPlaying,
            onPlay: { actions.play(item, false) },
            onFavorite: favoriteAction
        )
        return interactive(view.equatable(), index: index, item: item, generation: generation)
    }

    // MARK: Liste

    private func list(_ generation: Int) -> some View {
        let columns = [GridItem(.adaptive(minimum: 330), spacing: 18, alignment: .top)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
            ForEach(Array(elements.enumerated()), id: \.element.id) { index, element in
                row(index, element, generation)
            }
        }
        .marqueeContainer(marquee)
        .padding(.top, 4)
    }

    private func row(_ index: Int, _ element: Element, _ generation: Int) -> some View {
        let item = makeItem(element)
        let favoriteAction: (() -> Void)? = item.favorite == nil ? nil : { actions.toggleFavorite?(item) }
        let view = CollectionRow(
            item: item,
            selected: selection.contains(item.id),
            showDetails: options.showDetails,
            dropTargeted: dropTarget == item.id,
            playing: item.current && player.isPlaying,
            onPlay: { actions.play(item, false) },
            onFavorite: favoriteAction
        )
        return interactive(view.equatable(), index: index, item: item, generation: generation)
    }

    // MARK: Detailliste

    private func detailed(_ generation: Int) -> some View {
        let wanted = options.columns.filter { $0 != context.primaryColumn }
        let columns = TableLayout.fit(wanted, available: TableLayout.available(viewport))
        let widths: [CGFloat] = columns.map { CGFloat($0.defaultWidth) }
        return VStack(spacing: 0) {
            DetailTableHeader(context: context, columns: columns, widths: widths, sort: table?.sort ?? TableSortSpec.unsorted)
            LazyVStack(spacing: 0) {
                ForEach(Array(elements.enumerated()), id: \.element.id) { index, element in
                    tableRow(index, element, columns, widths, generation)
                }
            }
            .marqueeContainer(marquee)
        }
        .padding(.top, 4)
    }

    private func tableRow(_ index: Int, _ element: Element, _ columns: [DetailColumn], _ widths: [CGFloat], _ generation: Int) -> some View {
        let item = makeItem(element)
        let cells: [String] = columns.map { column in table?.cell(element, column) ?? "–" }
        let favoriteAction: (() -> Void)? = item.favorite == nil ? nil : { actions.toggleFavorite?(item) }
        let view = DetailTableRow(
            item: item,
            cells: cells,
            columns: columns,
            widths: widths,
            selected: selection.contains(item.id),
            dropTargeted: dropTarget == item.id,
            playing: item.current && player.isPlaying,
            onFavorite: favoriteAction
        )
        return interactive(view.equatable(), index: index, item: item, generation: generation)
    }

    // MARK: Cover Flow

    private var coverFlow: some View {
        let list = elements
        let make = makeItem
        let acts = actions
        return CoverFlowView(
            count: list.count,
            memoryKey: context.rawValue,
            options: options,
            item: { i in make(list[i]) },
            activate: { i in acts.open(make(list[i])) },
            play: { i, shuffle in acts.play(make(list[i]), shuffle) },
            openLabel: acts.openLabel,
            open: { i in acts.open(make(list[i])) },
            menu: { i in menuFor(make(list[i])) }
        )
    }

    private func menuFor(_ item: LibraryItem) -> MenuContent {
        menu(CollectionMenuTarget(item: item, uids: item.trackUids, groups: [item.trackUids], names: [item.title]))
    }

    // MARK: Bedienung

    @ViewBuilder
    private func interactive<V: View>(_ view: V, index: Int, item: LibraryItem, generation: Int) -> some View {
        let base = view
            .background(frameReporter(item, generation))
            .contentShape(Rectangle())
            .onTapGesture { click(index, item) }
            .contextMenu { menu(menuTarget(item)) }
            .onDrag { TrackDrag.provider(uids: targetUids(item), entryIds: []) }
        if actions.drop != nil && item.acceptsDrop {
            base.onDrop(of: [UTType.plainText], isTargeted: dropBinding(item.id)) { providers in
                let drop = actions.drop
                TrackDrag.load(providers) { uids, _ in drop?(item, uids) }
                return true
            }
        } else {
            base
        }
    }

    /// Rahmen für den Auswahlrahmen melden (nur auswählbare Einträge).
    @ViewBuilder
    private func frameReporter(_ item: LibraryItem, _ generation: Int) -> some View {
        if item.selectable {
            MarqueeFrameReporter(id: item.id, generation: generation, controller: marquee)
        }
    }

    private func dropBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { dropTarget == id },
            set: { on in dropTarget = on ? id : (dropTarget == id ? nil : dropTarget) }
        )
    }

    /// Klick öffnet; ⌘-Klick wählt einzeln, ⇧-Klick einen Bereich (Kontextmenü und Ziehen wirken dann auf alle).
    private func click(_ index: Int, _ item: LibraryItem) {
        if MarqueeRouter.shared.justFinishedMarquee { return }
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) && item.selectable {
            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
            anchor = index
            registerKeyboard()
        } else if flags.contains(.shift) && item.selectable {
            let start = min(anchor ?? index, elements.count - 1)
            let lower = max(0, min(start, index))
            let upper = min(max(start, index), elements.count - 1)
            if lower <= upper {
                selection = Set(elements[lower...upper].map(makeItem).filter(\.selectable).map(\.id))
            }
            anchor = start
            registerKeyboard()
        } else {
            selection = []
            anchor = index
            actions.open(item)
        }
    }

    /// Auswahlrahmen: Auswahl lesen und setzen (bei jedem Aufbau neu, damit die Funktionen aktuell sind).
    private func configureMarquee(_ generation: Int) -> Int {
        marquee.prepare(generation: generation)
        marquee.topChrome = topChrome
        marquee.bottomSlack = marqueeTail
        marquee.selection = { selection }
        marquee.apply = { ids in
            selection = ids
            registerKeyboard()
        }
        return generation
    }

    /// Ändert sich etwas an Einträgen, Reihenfolge, Größe oder Ansicht, werden die Rahmen neu gemeldet.
    private func layoutGeneration() -> Int {
        var h = Hasher()
        h.combine(options)
        h.combine(viewport.width)
        h.combine(elements.count)
        for element in elements { h.combine(element.id) }
        return h.finalize()
    }

    private var selectionKind: LibrarySelectionKind {
        switch context {
        case .albums, .favoriteAlbums: return .albums
        case .artists: return .artists
        case .genres: return .genres
        case .playlists: return .playlists
        case .tracks, .favoriteTracks: return .tracks
        }
    }

    /// Gewählte Einträge in angezeigter Reihenfolge.
    private func selectedItems() -> [LibraryItem] {
        var out: [LibraryItem] = []
        for element in elements where selection.contains(element.id) { out.append(makeItem(element)) }
        return out
    }

    private func targetUids(_ item: LibraryItem) -> [Int64] {
        guard selection.count > 1, selection.contains(item.id) else { return item.trackUids }
        return selectedUids()
    }

    private func selectedUids() -> [Int64] {
        TrackUids.union(selectedItems().map(\.trackUids))
    }

    /// Kontextmenü: gehört der Eintrag zur Auswahl, wirkt es auf die ganze Auswahl.
    private func menuTarget(_ item: LibraryItem) -> CollectionMenuTarget {
        guard selection.count > 1, selection.contains(item.id) else {
            return CollectionMenuTarget(item: item, uids: item.trackUids, groups: [item.trackUids], names: [item.title])
        }
        let picked = selectedItems()
        let groups = picked.map(\.trackUids)
        return CollectionMenuTarget(item: item, uids: TrackUids.union(groups), groups: groups, names: picked.prefix(3).map(\.title))
    }

    /// Auswahl an die Auswahlleiste melden.
    private func publishSelection(_ ids: Set<String>) {
        let store = LibrarySelectionStore.shared
        guard !ids.isEmpty else {
            store.withdraw(owner: owner)
            return
        }
        let picked = elements.filter { ids.contains($0.id) }.map(makeItem)
        guard let first = picked.first else {
            store.withdraw(owner: owner)
            return
        }
        let groups = picked.map(\.trackUids)
        let source: PlaybackSource = picked.count == 1
            ? (actions.source?(first) ?? PlaybackSource(kind: .list, label: first.title))
            : PlaybackSource(kind: .list, label: "Auswahl")
        store.publish(LibrarySelectionInfo(
            owner: owner,
            kind: selectionKind,
            count: picked.count,
            uids: TrackUids.union(groups),
            groups: groups,
            names: picked.prefix(3).map(\.title),
            source: source,
            clear: { selection = [] }
        ))
    }

    /// Vorschaubilder: erste Einträge auswählen.
    private func applySeed() {
        guard let count = LibrarySelectionSeed.take(selectionKind) else { return }
        let ids = elements.lazy.map(makeItem).filter(\.selectable).prefix(count).map(\.id)
        selection = Set(ids)
    }

    private func registerKeyboard() {
        KeyboardFocus.shared.activeList = KeyboardFocus.ListHandle(
            moveSelection: { delta, extend in moveSelection(delta, extend: extend) },
            playSelection: { playSelection() },
            deleteSelection: { deleteSelection() },
            selectAll: { selection = Set(elements.map(makeItem).filter(\.selectable).map(\.id)) },
            selectedUids: { selectedUids() }
        )
    }

    /// Eingabetaste: ein Eintrag spielt wie seine Abspielen-Schaltfläche (Alben mit den Alben der Ansicht),
    /// mehrere nacheinander (Alben je in Titelreihenfolge).
    private func playSelection() {
        let picked = selectedItems()
        guard let first = picked.first else { return }
        if picked.count == 1 {
            actions.play(first, false)
            return
        }
        let groups = picked.map(\.trackUids)
        let source = PlaybackSource(kind: .list, label: "Auswahl")
        if actions.albumContext != nil {
            player.play(uids: TrackUids.union(groups), startIndex: 0, shuffle: .off, source: source, albumContext: groups)
        } else {
            player.play(uids: TrackUids.union(groups), startIndex: 0, shuffle: .off, source: source)
        }
    }

    /// Entf-Taste: Löschdialog für die Titel der Auswahl (nicht in der Playlist-Übersicht).
    private func deleteSelection() {
        guard context != .playlists else { return }
        let picked = selectedItems()
        guard let first = picked.first else { return }
        let subject = DeleteSubject.groups(selectionKind, count: picked.count, firstName: first.title)
        RemoveTracksDialog.present(model: model, uids: TrackUids.union(picked.map(\.trackUids)), subject: subject)
    }

    private func moveSelection(_ delta: Int, extend: Bool) {
        guard !elements.isEmpty else { return }
        let current = anchor ?? -1
        let next = min(max(current + delta, 0), elements.count - 1)
        if extend { selection.insert(elements[next].id) } else { selection = [elements[next].id] }
        anchor = next
    }
}

// MARK: - Kachel

/// Kachel mit Cover (Raster und kompaktes Raster): beim Überfahren hebt sie sich leicht an, zeigt
/// „Abspielen“ und das Herz; Schatten nur beim Überfahren.
struct CollectionTile: View, Equatable {
    @Environment(\.musicColors) private var colors
    let item: LibraryItem
    let style: TileStyle
    let selected: Bool
    var dropTargeted: Bool = false
    let playing: Bool
    let onPlay: () -> Void
    var onFavorite: (() -> Void)? = nil
    @State private var hover = false

    static func == (a: CollectionTile, b: CollectionTile) -> Bool {
        a.item == b.item && a.style == b.style && a.selected == b.selected && a.dropTargeted == b.dropTargeted && a.playing == b.playing
    }

    var body: some View {
        VStack(alignment: item.circle ? .center : .leading, spacing: 0) {
            cover
            if !item.titleInside { captions }
        }
        .contentShape(Rectangle())
        .onHover { inside in hover = inside }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var radius: CGFloat { style.compact ? Radius.artwork - 2 : Radius.artwork }
    private var pad: CGFloat { style.compact ? 5 : 9 }

    private var cover: some View {
        let ring = RoundedRectangle(cornerRadius: item.circle ? 9999 : radius, style: .continuous)
        let lifted = hover && !style.compact
        return ZStack {
            LibraryArtView(art: item.art, size: style.artworkSize, cornerRadius: radius, circle: item.circle, iconFraction: 0.42)
            if item.titleInside { insideTitle }
            overlays
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(ring.strokeBorder(selected || dropTargeted ? colors.accent : Color.clear, lineWidth: 3))
        .scaleEffect(hover ? (style.compact ? 1.04 : 1.03) : 1)
        .offset(y: lifted ? -3 : 0)
        .shadow(color: Color.black.opacity(hover ? (colors.dark ? 0.5 : 0.22) : 0), radius: hover ? 14 : 0, x: 0, y: hover ? 9 : 0)
        .animation(Motion.easeOut(Motion.short), value: hover)
    }

    @ViewBuilder
    private var overlays: some View {
        if item.current {
            Circle()
                .fill(Color.black.opacity(0.5))
                .frame(width: style.compact ? 22 : 28, height: style.compact ? 22 : 28)
                .overlay(NowPlayingBars(playing: playing, color: .white, size: style.compact ? 11 : 13))
                .padding(pad)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: item.circle ? .top : .topLeading)
        }
        if hover && !item.trackUids.isEmpty {
            playButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: item.circle ? .center : .bottomLeading)
                .transition(.opacity)
        }
        favoriteControl
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private var playButton: some View {
        let size: CGFloat = style.compact ? 28 : 38
        return Button(action: onPlay) {
            Icon(Icons.play, size: size * 0.46, color: colors.onAccent)
                .frame(width: size, height: size)
                .background(Circle().fill(colors.accent))
                .shadow(color: Color.black.opacity(0.28), radius: 5, y: 2)
        }
        .buttonStyle(PressScaleStyle(scale: 0.9))
        .padding(pad)
        .help("Abspielen")
        .accessibilityLabel("„\(item.title)“ abspielen")
    }

    @ViewBuilder
    private var favoriteControl: some View {
        if let favorite = item.favorite {
            if hover, let onFavorite {
                HeartButton(favorite: favorite, iconSize: style.compact ? 12 : 14, touch: style.compact ? 24 : 28,
                            inactiveTint: Color.white, subject: "„\(item.title)“", toggle: onFavorite)
                    .background(Circle().fill(Color.black.opacity(0.42)))
                    .padding(pad)
            } else if favorite {
                Circle()
                    .fill(Color.black.opacity(0.42))
                    .frame(width: style.compact ? 20 : 24, height: style.compact ? 20 : 24)
                    .overlay(Icon(Icons.favorite, size: style.compact ? 11 : 13, color: Color(argb: 0xFFFF8FA6)))
                    .padding(pad)
            }
        }
    }

    /// Name auf dem Bild (Genre-Karten).
    private var insideTitle: some View {
        VStack(alignment: .leading, spacing: 1) {
            Spacer(minLength: 0)
            Text(item.title)
                .font(Typo.inter(style.compact ? 12 : 15.5, .bold, display: !style.compact))
                .foregroundColor(.white)
                .lineLimit(2)
            if style.showSecondary, let subtitle = item.subtitle {
                Text(subtitle)
                    .font(Typo.inter(style.compact ? 10 : 11.5, .medium))
                    .foregroundColor(Color.white.opacity(0.86))
                    .lineLimit(1)
            }
        }
        .padding(style.compact ? 8 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(LinearGradient(colors: [Color.clear, Color.black.opacity(0.32)], startPoint: .center, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    private var captions: some View {
        let align: HorizontalAlignment = item.circle ? .center : .leading
        let frameAlign: Alignment = item.circle ? .center : .leading
        return VStack(alignment: align, spacing: 1) {
            HStack(spacing: 4) {
                Text(item.title)
                    .font(style.compact ? Typo.inter(12, .semibold) : Typo.titleSmall.font)
                    .tracking(style.compact ? 0 : Typo.titleSmall.tracking)
                    .foregroundColor(item.current ? colors.accentText : colors.textPrimary)
                    .lineLimit(1)
                if item.automatic { Icon(Icons.autoAwesome, size: 11, color: colors.accent) }
            }
            if style.showSecondary, let subtitle = item.subtitle {
                Text(subtitle)
                    .font(Typo.inter(style.compact ? 10.5 : 11.5, .regular))
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(1)
            }
            if style.showDetails, let detail = item.detail {
                Text(detail)
                    .textStyle(Typo.labelSmall)
                    .foregroundColor(colors.textTertiary)
                    .lineLimit(1)
            }
        }
        .multilineTextAlignment(item.circle ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: frameAlign)
        .padding(.top, style.compact ? 5 : 8)
    }

    private var accessibilityText: String {
        let parts: [String?] = [item.title, item.subtitle, item.current ? "läuft gerade" : nil]
        return parts.compactMap { $0 }.joined(separator: ", ")
    }
}

// MARK: - Listenzeile

struct CollectionRow: View, Equatable {
    @Environment(\.musicColors) private var colors
    let item: LibraryItem
    let selected: Bool
    let showDetails: Bool
    var dropTargeted: Bool = false
    let playing: Bool
    let onPlay: () -> Void
    var onFavorite: (() -> Void)? = nil
    @State private var hover = false

    static func == (a: CollectionRow, b: CollectionRow) -> Bool {
        a.item == b.item && a.selected == b.selected && a.showDetails == b.showDetails && a.dropTargeted == b.dropTargeted && a.playing == b.playing
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 12) {
            artwork
            texts
            Spacer(minLength: 6)
            trailing
        }
        .padding(.horizontal, 8)
        .frame(height: 62)
        .background(shape.fill(fill))
        .overlay(shape.strokeBorder(dropTargeted ? colors.accent : Color.clear, lineWidth: 1.5))
        .overlay(alignment: .bottom) {
            if !selected && !dropTargeted { Hairline(leading: 66) }
        }
        .onHover { inside in hover = inside }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.subtitle.map { "\(item.title), \($0)" } ?? item.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var fill: Color {
        if selected { return colors.selectionFill }
        if dropTargeted { return colors.accentSoft }
        return hover ? colors.textPrimary.opacity(colors.dark ? 0.05 : 0.04) : Color.clear
    }

    private var artwork: some View {
        ZStack {
            LibraryArtView(art: item.art, size: .small, cornerRadius: Radius.artworkSmall, circle: item.circle, iconFraction: 0.48)
            if item.current {
                Circle().fill(Color.black.opacity(0.42)).frame(width: 26, height: 26)
                NowPlayingBars(playing: playing, color: .white, size: 12)
            }
        }
        .frame(width: 46, height: 46)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(item.title)
                    .font(Typo.inter(Typo.bodyLarge.size, item.current ? .semibold : .medium))
                    .foregroundColor(item.current ? colors.accentText : colors.textPrimary)
                    .lineLimit(1)
                if item.automatic { Icon(Icons.autoAwesome, size: 12, color: colors.accent) }
            }
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .textStyle(Typo.bodySmall)
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if showDetails, let detail = item.detail {
            Text(detail)
                .textStyle(Typo.labelMedium)
                .foregroundColor(colors.textTertiary)
                .lineLimit(1)
                .frame(maxWidth: 220, alignment: .trailing)
        }
        if hover && !item.trackUids.isEmpty {
            IconTap(icon: Icons.play, label: "„\(item.title)“ abspielen", tint: colors.accentText, iconSize: 15, touch: 30, action: onPlay)
        }
        if let favorite = item.favorite, let onFavorite {
            HeartButton(favorite: favorite, iconSize: 15, touch: 30, subject: "„\(item.title)“", toggle: onFavorite)
                .opacity(favorite || hover || selected ? 1 : 0.55)
        }
        Icon(Icons.chevronRight, size: 17, color: colors.textTertiary.opacity(0.7))
            .padding(.trailing, 4)
    }
}

// MARK: - Detailliste

/// Kopf der Detailliste: kleine Versalien, Klick sortiert (aktive Spalte rosé mit Pfeil). Keine Linien
/// zwischen den Spalten – bewusst keine graue Tabelle.
struct DetailTableHeader: View {
    @Environment(\.musicColors) private var colors
    let context: LibraryViewContext
    let columns: [DetailColumn]
    let widths: [CGFloat]
    let sort: TableSortSpec
    var artworkWidth: CGFloat = 32

    var body: some View {
        let primary = context.primaryColumn
        let active: DetailColumn? = sort.isActive(primary) ? primary : columns.first(where: { sort.isActive($0) })
        HStack(spacing: 0) {
            Spacer().frame(width: artworkWidth + 12)
            headerCell(primary, active: active == primary, numeric: false)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(columns.enumerated()), id: \.element) { i, column in
                headerCell(column, active: active == column, numeric: column.numeric)
                    .frame(width: widths[i], alignment: column.numeric ? .trailing : .leading)
                    .padding(.leading, 14)
            }
            Spacer().frame(width: 40)
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func headerCell(_ column: DetailColumn, active: Bool, numeric: Bool) -> some View {
        let label = context.columnLabel(column)
        let sortable = sort.sortable.contains(column)
        return Button { sort.onSort(column) } label: {
            HStack(spacing: 3) {
                Text(label.uppercased())
                    .font(Typo.inter(10.5, .semibold))
                    .tracking(0.5)
                    .foregroundColor(active ? colors.accentText : colors.textTertiary)
                    .lineLimit(1)
                if active {
                    Icon(sort.descending ? LibIcon.descending : LibIcon.ascending, size: 11, color: colors.accentText)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!sortable)
        .help(sortable ? "Nach „\(label)“ sortieren" : label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Zeile der Detailliste (Sammlungen und Titel).
struct DetailTableRow: View, Equatable {
    @Environment(\.musicColors) private var colors
    let item: LibraryItem
    let cells: [String]
    let columns: [DetailColumn]
    let widths: [CGFloat]
    let selected: Bool
    var dropTargeted: Bool = false
    var unavailable: Bool = false
    var dropAbove: Bool = false
    let playing: Bool
    var onFavorite: (() -> Void)? = nil
    @State private var hover = false

    static func == (a: DetailTableRow, b: DetailTableRow) -> Bool {
        a.item == b.item && a.cells == b.cells && a.columns == b.columns && a.widths == b.widths && a.selected == b.selected
            && a.dropTargeted == b.dropTargeted && a.unavailable == b.unavailable && a.dropAbove == b.dropAbove && a.playing == b.playing
    }

    var body: some View {
        HStack(spacing: 0) {
            artwork
            Spacer().frame(width: 12)
            title
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(columns.indices, id: \.self) { i in
                Text(i < cells.count ? cells[i] : "–")
                    .font(Typo.inter(12.5, .regular))
                    .monospacedDigit()
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(1)
                    .frame(width: widths[i], alignment: columns[i].numeric ? .trailing : .leading)
                    .padding(.leading, 14)
            }
            heart
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(fill))
        .overlay(alignment: .bottom) {
            if !selected { Hairline(leading: 52) }
        }
        .overlay(alignment: .top) {
            if dropAbove { Capsule().fill(colors.accent).frame(height: 2.5).padding(.horizontal, 4) }
        }
        .onHover { inside in hover = inside }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(([item.title] + cells).joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var fill: Color {
        if selected { return colors.selectionFill }
        if dropTargeted { return colors.accentSoft }
        return hover ? colors.textPrimary.opacity(colors.dark ? 0.05 : 0.035) : Color.clear
    }

    private var artwork: some View {
        ZStack {
            LibraryArtView(art: item.art, size: .small, cornerRadius: 6, circle: item.circle, iconFraction: 0.5)
            if item.current {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.4))
                NowPlayingBars(playing: playing, color: .white, size: 11)
            }
        }
        .frame(width: 32, height: 32)
    }

    private var title: some View {
        HStack(spacing: 6) {
            Text(item.title)
                .font(Typo.inter(13.5, item.current ? .semibold : .medium))
                .foregroundColor(item.current ? colors.accentText : (unavailable ? colors.textTertiary : colors.textPrimary))
                .lineLimit(1)
            if item.automatic { Icon(Icons.autoAwesome, size: 11, color: colors.accent) }
            if unavailable {
                Text("nicht verfügbar")
                    .textStyle(Typo.labelSmall)
                    .foregroundColor(colors.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(colors.fieldFill))
            }
        }
    }

    @ViewBuilder
    private var heart: some View {
        if let favorite = item.favorite, let onFavorite {
            HeartButton(favorite: favorite, iconSize: 14, touch: 28, subject: "„\(item.title)“", toggle: onFavorite)
                .opacity(favorite || hover || selected ? 1 : 0.5)
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }
}
