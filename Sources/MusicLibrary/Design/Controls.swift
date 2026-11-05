import SwiftUI
import AppKit

// Bedienelemente – Übertragung von ui/components/Controls.kt und Common.kt (Android).
// Auf dem Mac zusätzlich: Hover-Zustände, Tooltips (`help`), Tastaturbedienung.

/// Leichtes Verkleinern beim Drücken (Android: Symbol 0,86 / Glas 0,92 / Kapsel 0,96).
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.92

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.standardSpring, value: configuration.isPressed)
    }
}

/// Symbol-Schaltfläche ohne Hintergrund (Android `IconTap`): ruhig, präzise, mit Hover-Fläche auf dem Mac.
struct IconTap: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.isEnabled) private var enabled
    let icon: String
    let label: String
    var tint: Color? = nil
    var iconSize: CGFloat = 18
    var touch: CGFloat = 32
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Icon(icon, size: iconSize, color: (tint ?? colors.textPrimary).opacity(enabled ? 1 : 0.32))
                .frame(width: touch, height: touch)
                .background(Circle().fill(colors.textPrimary.opacity(hover && enabled ? 0.07 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.86))
        .onHover { hover = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Runde Glas-Schaltfläche (Android `GlassIconButton`). `active` färbt das Symbol rosé und hinterlegt es zart.
struct GlassIconButton: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.isEnabled) private var enabled
    let icon: String
    let label: String
    var size: CGFloat = 34
    var iconSize: CGFloat = 17
    var active: Bool = false
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(icon, size: iconSize, color: iconColor)
                .frame(width: size, height: size)
                .contentShape(Circle())
                .glassSurface(Circle(), tint: active ? colors.accentSoft : nil, interactive: true)
        }
        .buttonStyle(PressScaleStyle(scale: 0.92))
        .help(label)
        .accessibilityLabel(label)
    }

    private var iconColor: Color {
        if let tint { return tint }
        if !enabled { return colors.textPrimary.opacity(0.32) }
        return active ? colors.accentText : colors.textPrimary
    }
}

enum PillStyle { case filled, tonal, plain }

/// Kapselförmige Schaltfläche (Android `PillButton`): „Abspielen“, „Mischen“ …
struct PillButton: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.isEnabled) private var enabled
    let title: String
    var icon: String? = nil
    var style: PillStyle = .tonal
    var minWidth: CGFloat? = nil
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Icon(icon, size: 16, color: foreground) }
                Text(title)
                    .textStyle(Typo.labelLarge)
                    .foregroundColor(foreground)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .frame(minWidth: minWidth, minHeight: Metrics.pillHeight)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(background))
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Color.white.opacity(hover && enabled ? (colors.dark ? 0.05 : 0.12) : 0)))
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.96))
        .onHover { hover = $0 }
    }

    private var background: Color {
        switch style {
        case .filled: return enabled ? colors.accent : colors.accent.opacity(0.4)
        case .tonal: return colors.tonalFill
        case .plain: return .clear
        }
    }

    private var foreground: Color {
        let c: Color = style == .filled ? colors.onAccent : colors.accentText
        return enabled ? c : c.opacity(0.38)
    }
}

/// Herz (Android `HeartButton`): Umriss = kein Favorit, gefülltes Rosé-Herz = Favorit; kleine Feder beim Hinzufügen.
struct HeartButton: View {
    @Environment(\.musicColors) private var colors
    let favorite: Bool
    var iconSize: CGFloat = 16
    var touch: CGFloat = 30
    var inactiveTint: Color? = nil
    var subject: String = ""
    let toggle: () -> Void
    @State private var bump: CGFloat = 1

    var body: some View {
        IconTap(
            icon: favorite ? Icons.favorite : Icons.favoriteBorder,
            label: favorite ? "\(subject) aus Favoriten entfernen".trimmingCharacters(in: .whitespaces) : "\(subject) zu Favoriten hinzufügen".trimmingCharacters(in: .whitespaces),
            tint: favorite ? colors.heart : (inactiveTint ?? colors.textTertiary.opacity(0.75)),
            iconSize: iconSize,
            touch: touch,
            action: {
                if !favorite {
                    bump = 0.7
                    withAnimation(Motion.bouncySpring) { bump = 1 }
                }
                toggle()
            }
        )
        .scaleEffect(bump)
    }
}

/// Schlanker Regler im Apple-Stil (Android `MusicSlider`): dünne Spur, beim Ziehen/Überfahren kräftiger,
/// Klicken springt an die Stelle. `marker` = Markierung (z. B. 100 % Lautstärke), darüber `overColor`.
struct MusicSlider: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.isEnabled) private var enabled
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var marker: Double? = nil
    var bipolar: Bool = false
    var activeColor: Color? = nil
    var inactiveColor: Color? = nil
    var overColor: Color? = nil
    var showsKnob: Bool = false
    var step: Double? = nil
    var label: String
    var valueText: String = ""
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var dragging = false
    @State private var hover = false

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let h: CGFloat = (dragging || hover) && enabled ? 7 : 4.5
            let span = max(range.upperBound - range.lowerBound, 1e-9)
            let fraction = CGFloat(min(max((value - range.lowerBound) / span, 0), 1))
            let x = width * fraction
            let markerX = marker.map { width * CGFloat(min(max(($0 - range.lowerBound) / span, 0), 1)) }
            let active = (activeColor ?? colors.textPrimary.opacity(0.85)).opacity(enabled ? 1 : 0.4)
            let inactive = (inactiveColor ?? colors.textPrimary.opacity(0.14)).opacity(enabled ? 1 : 0.4)
            let over = (overColor ?? colors.accent).opacity(enabled ? 1 : 0.4)
            ZStack(alignment: .leading) {
                Capsule().fill(inactive).frame(height: h)
                if bipolar, let mx = markerX {
                    let left = min(x, mx)
                    let right = max(x, mx)
                    if right - left > 0.5 {
                        Capsule().fill(active).frame(width: right - left, height: h).offset(x: left)
                    }
                } else if let mx = markerX, x > mx {
                    Capsule().fill(active).frame(width: mx, height: h)
                    Capsule().fill(over).frame(width: x - mx + h, height: h).offset(x: mx - h)
                } else if x > 0 {
                    Capsule().fill(active).frame(width: max(x, h), height: h)
                }
                if let mx = markerX, !bipolar {
                    Rectangle().fill(inactive.opacity(3)).frame(width: 1.2, height: h + 6).offset(x: mx - 0.6)
                }
                if showsKnob || bipolar || ((dragging || hover) && enabled) {
                    Circle()
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.18), radius: 1.5, y: 0.5)
                        .frame(width: bipolar || showsKnob ? 16 : 12, height: bipolar || showsKnob ? 16 : 12)
                        .offset(x: x - (bipolar || showsKnob ? 8 : 6))
                }
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard enabled else { return }
                        if !dragging {
                            dragging = true
                            onEditingChanged(true)
                        }
                        value = valueAt(g.location.x, width: width)
                    }
                    .onEnded { g in
                        guard enabled else { return }
                        value = valueAt(g.location.x, width: width)
                        dragging = false
                        onEditingChanged(false)
                    }
            )
            .animation(Motion.standardSpring, value: h)
        }
        .frame(height: 22)
        .onHover { hover = $0 }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { dir in
            let delta = step ?? (range.upperBound - range.lowerBound) / 20
            switch dir {
            case .increment: value = min(range.upperBound, value + delta)
            case .decrement: value = max(range.lowerBound, value - delta)
            @unknown default: break
            }
            onEditingChanged(false)
        }
    }

    private func valueAt(_ x: CGFloat, width: CGFloat) -> Double {
        let f = Double(min(max(x / width, 0), 1))
        var v = range.lowerBound + f * (range.upperBound - range.lowerBound)
        if let step, step > 0 { v = (v / step).rounded() * step }
        return min(max(v, range.lowerBound), range.upperBound)
    }
}

/// Segment-Umschalter (Android `SegmentedControl`): Kapsel mit weich gleitender Markierung.
struct SegmentedControl<T: Hashable>: View {
    @Environment(\.musicColors) private var colors
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String
    var icon: ((T) -> String?)? = nil
    var height: CGFloat = 30

    var body: some View {
        GeometryReader { geo in
            let count = max(options.count, 1)
            let segment = max(0, geo.size.width - 6) / CGFloat(max(count, 1))
            let index = CGFloat(options.firstIndex(of: selection) ?? 0)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(colors.dark ? Color.white.opacity(0.16) : colors.surface)
                    .shadow(color: colors.dark ? .clear : colors.glassShadow, radius: 2.5, y: 1)
                    .frame(width: segment, height: height - 6)
                    .offset(x: 3 + segment * index)
                    .animation(Motion.standardSpring, value: index)
                HStack(spacing: 0) {
                    ForEach(options, id: \.self) { option in
                        let active = option == selection
                        Button {
                            selection = option
                        } label: {
                            HStack(spacing: 5) {
                                if let name = icon?(option) {
                                    Icon(name, size: 14, color: active ? colors.accentText : colors.textSecondary)
                                }
                                Text(label(option))
                                    .textStyle(Typo.labelMedium)
                                    .foregroundColor(active ? colors.textPrimary : colors.textSecondary)
                                    .lineLimit(1)
                            }
                            .frame(width: segment, height: height - 6)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(active ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 3)
            }
            .frame(width: geo.size.width, height: height)
            .background(Capsule().fill(colors.dark ? Color.white.opacity(0.08) : colors.textPrimary.opacity(0.06)))
        }
        .frame(height: height)
    }
}

/// Drei feine Pegelbalken (Android `NowPlayingBars`); bewegen sich nur bei laufender Wiedergabe.
struct NowPlayingBars: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.continuousMotion) private var motion
    let playing: Bool
    var color: Color? = nil
    var size: CGFloat = 14

    var body: some View {
        let playing = self.playing && motion   // „Animationen: Aus“ → ruhende Balken
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, area in
                let periods: [Double] = [0.52, 0.38, 0.61]
                let still: [Double] = [0.45, 0.75, 0.35]
                let barWidth = area.width / 5
                for i in 0..<3 {
                    var f = still[i]
                    if playing {
                        // Dreieckswelle zwischen Startwert und 1 (wie RepeatMode.Reverse)
                        let start = 0.25 + 0.15 * Double(i)
                        let phase = (t / periods[i]).truncatingRemainder(dividingBy: 2)
                        let tri = phase < 1 ? phase : 2 - phase
                        f = start + (1 - start) * tri
                    }
                    let h = area.height * CGFloat(min(max(f, 0.15), 1))
                    let rect = CGRect(x: barWidth * CGFloat(2 * i), y: area.height - h, width: barWidth, height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color ?? colors.accent))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Kleine Auswahl-Kapsel (Android `ChoiceChip`).
struct ChoiceChip: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.isEnabled) private var enabled
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .textStyle(Typo.labelMedium)
                .foregroundColor(!enabled ? colors.textTertiary : selected ? colors.accentText : colors.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 28)
                .background(Capsule().fill(selected ? colors.accentSoft : (colors.dark ? Color.white.opacity(0.07) : colors.surface)))
                .overlay(Capsule().strokeBorder(!selected && !colors.dark ? colors.hairline : .clear, lineWidth: 0.8))
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle(scale: 0.95))
        .animation(Motion.easeOut(), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Suchfeld (Android `SearchField`): zarte Fläche, Lupe, „×“ zum Leeren; filtert während der Eingabe.
/// Der getippte Text wird lokal gehalten (nur das Feld zeichnet sich neu); die Bindung bekommt jede Änderung,
/// das Modell übernimmt sie gebündelt.
struct SearchField: View {
    @Environment(\.musicColors) private var colors
    @Binding var text: String
    let placeholder: String
    var focus: FocusState<Bool>.Binding? = nil
    @FocusState private var ownFocus: Bool
    @State private var local: String?

    private var shown: String { local ?? text }

    private var editing: Binding<String> {
        Binding(get: { shown }, set: { value in
            local = value
            text = value
        })
    }

    var body: some View {
        HStack(spacing: 7) {
            Icon(Icons.search, size: 16, color: colors.textSecondary)
            ZStack(alignment: .leading) {
                if shown.isEmpty {
                    Text(placeholder)
                        .textStyle(Typo.bodyLarge)
                        .foregroundColor(colors.textTertiary)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }
                field
            }
            if !shown.isEmpty {
                IconTap(icon: Icons.clear, label: "Suche löschen", tint: colors.textSecondary, iconSize: 14, touch: 24) {
                    local = ""
                    text = ""
                }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: Metrics.searchFieldHeight)
        .background(RoundedRectangle(cornerRadius: Radius.control - 2, style: .continuous).fill(colors.fieldFill))
        // Von außen geändert (z. B. Bereich gewechselt, Suche zurückgesetzt) → lokale Kopie verwerfen
        .onChange(of: text) { value in
            if let local, local != value { self.local = nil }
        }
    }

    @ViewBuilder private var field: some View {
        if let focus {
            TextField("", text: editing)
                .textFieldStyle(.plain)
                .textStyle(Typo.bodyLarge)
                .foregroundColor(colors.textPrimary)
                .focused(focus)
                .accessibilityLabel(placeholder)
        } else {
            TextField("", text: editing)
                .textFieldStyle(.plain)
                .textStyle(Typo.bodyLarge)
                .foregroundColor(colors.textPrimary)
                .focused($ownFocus)
                .accessibilityLabel(placeholder)
        }
    }
}

/// Mehrere kleine Symbol-Schaltflächen in einer gemeinsamen Glaskapsel (Android `ActionCapsule`).
struct ActionCapsule<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 0) { content() }
            .padding(.horizontal, 2)
            .frame(height: 34)
            .glassSurface(Capsule(), strong: true)
    }
}

/// Kleine Symbol-Schaltfläche für Kopfleisten und Kapseln (Android `BarAction`).
struct BarAction: View {
    @Environment(\.musicColors) private var colors
    let icon: String
    let label: String
    var active: Bool = false
    let action: () -> Void

    var body: some View {
        IconTap(icon: icon, label: label, tint: active ? colors.accentText : colors.textPrimary, iconSize: 17, touch: 32, action: action)
    }
}

/// Leerer Zustand mit Symbol in einer zarten Rosé-Fläche (Android `EmptyState`).
struct EmptyStateView<Action: View>: View {
    @Environment(\.musicColors) private var colors
    let icon: String
    let title: String
    let text: String
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(colors.accentSoft)
                .frame(width: 66, height: 66)
                .overlay(Icon(icon, size: 31, color: colors.accentText))
            Spacer().frame(height: 14)
            Text(title)
                .textStyle(Typo.titleLarge)
                .foregroundColor(colors.textPrimary)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 6)
            Text(text)
                .textStyle(Typo.bodyMedium)
                .foregroundColor(colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)
            Spacer().frame(height: 16)
            action()
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}

extension EmptyStateView where Action == EmptyView {
    init(icon: String, title: String, text: String) {
        self.init(icon: icon, title: title, text: text) { EmptyView() }
    }
}

/// Zwischenüberschrift in Listen (Android `ListLabel`): kleine Versalien, zurückhaltend.
struct ListLabel<Trailing: View>: View {
    @Environment(\.musicColors) private var colors
    let text: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Text(text.uppercased())
                .textStyle(Typo.sectionLabel)
                .foregroundColor(colors.textSecondary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 4)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }
}

extension ListLabel where Trailing == EmptyView {
    init(_ text: String) {
        self.init(text: text) { EmptyView() }
    }
}

/// Abschnittstitel in Detailansichten (Android `SectionTitle`).
struct SectionTitle: View {
    @Environment(\.musicColors) private var colors
    let text: String

    var body: some View {
        Text(text)
            .textStyle(Typo.titleLarge)
            .foregroundColor(colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }
}

/// Haarlinie (Trennlinie unter Listenzeilen).
struct Hairline: View {
    @Environment(\.musicColors) private var colors
    var leading: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(colors.hairline)
            .frame(height: 0.7)
            .padding(.leading, leading)
    }
}

/// Glas-Gruppe für Einstellungen und Bearbeitungsfenster (Android: Karten mit Radius 18).
struct GlassCard<Content: View>: View {
    @Environment(\.musicColors) private var colors
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

/// Einfache Ein/Aus-Schaltfläche in Rosé (Android Material-Switch mit App-Farben).
struct MusicToggle: View {
    @Environment(\.musicColors) private var colors
    @Binding var isOn: Bool
    let label: String

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(.switch)
            .tint(colors.accent)
            .labelsHidden()
            .accessibilityLabel(label)
    }
}
