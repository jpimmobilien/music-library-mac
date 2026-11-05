import SwiftUI
import AppKit
import MLCore

// Darstellung eines Bereichs: Ansicht, Covergröße und Abstand (live, gespeichert beim Loslassen),
// Untertitel/Zusatzinfos und – in der Detailliste – die sichtbaren Spalten.

struct ViewOptionsPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var live = LibraryLiveState.shared
    @Environment(\.musicColors) private var colors
    let context: LibraryViewContext

    var body: some View {
        let options = model.viewOptions(context)
        VStack(alignment: .leading, spacing: 0) {
            GlassMenuHeader(title: "Ansicht")
            modeRow(options)
            if options.mode.usesCoverSize {
                coverSlider(options)
            }
            if options.mode.isGrid {
                spacingSlider(options)
            }
            GlassMenuDivider()
            if options.mode == .detailedList {
                columnsSection(options)
            } else {
                infoSection(options)
            }
            GlassMenuDivider()
            GlassMenuItem(title: "Standard wiederherstellen", icon: LibIcon.restart) {
                var defaults = LibraryViewOptions.defaults(for: context)
                defaults.mode = options.mode
                model.setViewOptions(defaults, for: context)
            }
        }
    }

    // MARK: Ansicht

    private func modeRow(_ options: LibraryViewOptions) -> some View {
        HStack(spacing: 4) {
            ForEach(LibraryViewMode.allCases, id: \.self) { mode in
                ModeChoice(mode: mode, selected: mode == options.mode) {
                    var next = model.viewOptions(context)
                    next.mode = mode
                    model.setViewOptions(next, for: context)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
    }

    // MARK: Regler

    private func coverSlider(_ options: LibraryViewOptions) -> some View {
        let range = LibraryViewOptions.coverSizeRange
        let value = live.coverSize[context] ?? options.coverSize
        return sliderBlock(
            title: "Covergröße",
            valueText: "\(Int(value.rounded())) pt",
            lowIcon: LibIcon.zoomOut,
            highIcon: LibIcon.zoomIn,
            onLow: { commitCover(value - 20) },
            onHigh: { commitCover(value + 20) }
        ) {
            MusicSlider(
                value: Binding(get: { live.coverSize[context] ?? model.viewOptions(context).coverSize },
                               set: { live.coverSize[context] = LibraryLiveState.clampCover($0) }),
                range: range,
                activeColor: colors.accent,
                showsKnob: true,
                label: "Covergröße",
                valueText: "\(Int(value.rounded())) Punkt",
                onEditingChanged: { editing in
                    if !editing, let v = live.coverSize[context] { commitCover(v) }
                }
            )
        }
    }

    private func spacingSlider(_ options: LibraryViewOptions) -> some View {
        let range = LibraryViewOptions.spacingRange
        let value = live.spacing[context] ?? options.spacing
        return sliderBlock(
            title: "Abstand",
            valueText: "\(Int(value.rounded())) pt",
            lowIcon: LibIcon.minus,
            highIcon: Icons.add,
            onLow: { commitSpacing(value - 4) },
            onHigh: { commitSpacing(value + 4) }
        ) {
            MusicSlider(
                value: Binding(get: { live.spacing[context] ?? model.viewOptions(context).spacing },
                               set: { live.spacing[context] = LibraryLiveState.clampSpacing($0) }),
                range: range,
                activeColor: colors.accent,
                showsKnob: true,
                label: "Abstand zwischen den Kacheln",
                valueText: "\(Int(value.rounded())) Punkt",
                onEditingChanged: { editing in
                    if !editing, let v = live.spacing[context] { commitSpacing(v) }
                }
            )
        }
    }

    private func sliderBlock<S: View>(title: String, valueText: String, lowIcon: String, highIcon: String,
                                      onLow: @escaping () -> Void, onHigh: @escaping () -> Void,
                                      @ViewBuilder slider: () -> S) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(Typo.inter(12.5, .medium))
                    .foregroundColor(colors.textPrimary)
                Spacer()
                Text(verbatim: valueText)
                    .font(Typo.inter(11.5, .medium))
                    .monospacedDigit()
                    .foregroundColor(colors.textTertiary)
            }
            HStack(spacing: 6) {
                IconTap(icon: lowIcon, label: "\(title) verringern", tint: colors.textSecondary, iconSize: 14, touch: 24, action: onLow)
                slider()
                IconTap(icon: highIcon, label: "\(title) erhöhen", tint: colors.textSecondary, iconSize: 14, touch: 24, action: onHigh)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func commitCover(_ value: Double) {
        var options = model.viewOptions(context)
        options.coverSize = LibraryLiveState.clampCover(value).rounded()
        model.setViewOptions(options, for: context)
        live.coverSize[context] = nil
    }

    private func commitSpacing(_ value: Double) {
        var options = model.viewOptions(context)
        options.spacing = LibraryLiveState.clampSpacing(value).rounded()
        model.setViewOptions(options, for: context)
        live.spacing[context] = nil
    }

    // MARK: Angaben

    @ViewBuilder
    private func infoSection(_ options: LibraryViewOptions) -> some View {
        GlassMenuHeader(title: "Angaben")
        if options.mode != .list {
            GlassMenuItem(title: "Untertitel anzeigen", checked: options.showSecondaryText) {
                var next = model.viewOptions(context)
                next.showSecondaryText.toggle()
                model.setViewOptions(next, for: context)
            }
        }
        GlassMenuItem(title: "Zusatzinfos anzeigen", checked: options.showDetails) {
            var next = model.viewOptions(context)
            next.showDetails.toggle()
            model.setViewOptions(next, for: context)
        }
    }

    // MARK: Spalten

    @ViewBuilder
    private func columnsSection(_ options: LibraryViewOptions) -> some View {
        GlassMenuHeader(title: "Spalten")
        GlassMenuItem(title: context.columnLabel(context.primaryColumn), checked: true) {}
            .disabled(true)
        ForEach(context.optionalColumns, id: \.self) { column in
            GlassMenuItem(title: context.columnLabel(column), checked: options.columns.contains(column)) {
                toggleColumn(column)
            }
        }
    }

    private func toggleColumn(_ column: DetailColumn) {
        var next = model.viewOptions(context)
        var visible = Set(next.columns)
        if visible.contains(column) { visible.remove(column) } else { visible.insert(column) }
        let available = LibraryViewOptions.availableColumns(for: context)
        // Reihenfolge wie vorgesehen; bisher sichtbare, aber nicht (mehr) vorgesehene Spalten bleiben hinten.
        var ordered = available.filter { visible.contains($0) }
        ordered += next.columns.filter { visible.contains($0) && !available.contains($0) }
        next.columns = ordered
        model.setViewOptions(next, for: context)
    }
}

/// Ansicht als Symbol-Schaltfläche im Darstellungs-Popover.
private struct ModeChoice: View {
    @Environment(\.musicColors) private var colors
    let mode: LibraryViewMode
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Icon(mode.libIcon, size: 18, color: selected ? colors.accentText : colors.textSecondary)
                Text(mode.label)
                    .font(Typo.inter(9.5, selected ? .semibold : .medium))
                    .foregroundColor(selected ? colors.accentText : colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? colors.accentSoft : colors.textPrimary.opacity(hover ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(mode.label)
        .accessibilityLabel("Ansicht: \(mode.label)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
