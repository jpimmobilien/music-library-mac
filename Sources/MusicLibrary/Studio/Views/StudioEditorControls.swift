import SwiftUI
import AppKit
import MLStudio

// Audio Studio – Bedienleiste unter der Wellenform: Vorhören, Abspielposition, genaue Zeitfelder
// (Start/Ende/Länge, Pfeiltasten ±0,1 s, mit ⇧ ±1 s), „Ganze Datei“ sowie Ein- und Ausblenden.

struct StudioTransportBar: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 14) {
                transport
                Spacer(minLength: 6)
                times
                wholeFile
                fades
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    transport
                    Spacer(minLength: 6)
                    wholeFile
                    fades
                }
                times
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    transport
                    Spacer(minLength: 0)
                }
                times
                HStack(spacing: 8) {
                    wholeFile
                    fades
                }
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 10) {
            StudioPlayButton(playback: studio.playback) { studio.togglePreview() }
            IconTap(icon: Icons.previewSelection, label: "Auswahl von Anfang an vorhören", tint: colors.textPrimary, iconSize: 19, touch: 34) {
                studio.previewSelection()
            }
            StudioPlayheadLabel(playback: studio.playback, duration: studio.duration)
        }
        .fixedSize()
    }

    private var times: some View {
        let sel = studio.shownSelection
        let d = studio.duration
        return HStack(spacing: 8) {
            StudioLabeledField(label: "Start") {
                StudioTimeField(value: sel.start, label: "Start des Ausschnitts") { v in
                    studio.setSelection(start: min(max(0, v), d), end: sel.end)
                }
                .frame(width: 98, height: 30)
                .modifier(StudioTimeFieldChrome())
            }
            StudioLabeledField(label: "Ende") {
                StudioTimeField(value: sel.end, label: "Ende des Ausschnitts") { v in
                    studio.setSelection(start: sel.start, end: min(max(0, v), d))
                }
                .frame(width: 98, height: 30)
                .modifier(StudioTimeFieldChrome())
            }
            StudioLabeledField(label: "Länge") {
                StudioTimeField(value: sel.length, label: "Länge des Ausschnitts") { v in
                    studio.setSelection(start: sel.start, end: min(sel.start + max(0.01, v), d))
                }
                .frame(width: 98, height: 30)
                .modifier(StudioTimeFieldChrome())
            }
        }
        .fixedSize()
    }

    private var wholeFile: some View {
        ChoiceChip(title: "Ganze Datei", selected: studio.exportWholeFile) { studio.selectAll() }
            .help("Die ganze Datei exportieren (Auswahl aufheben)")
            .fixedSize()
    }

    private var fades: some View {
        HStack(spacing: 6) {
            StudioFadeMenu(studio: studio, fadeIn: true)
            StudioFadeMenu(studio: studio, fadeIn: false)
        }
        .fixedSize()
    }
}

/// Große runde Vorhör-Schaltfläche (beobachtet nur den Vorhör-Zustand).
struct StudioPlayButton: View {
    @ObservedObject var playback: StudioPlayback
    @Environment(\.musicColors) private var colors
    @Environment(\.isEnabled) private var enabled
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(playback.playing ? Icons.pause : Icons.play, size: 20, color: colors.onAccent)
                .frame(width: 42, height: 42)
                .background(Circle().fill(enabled ? colors.accent : colors.accent.opacity(0.4)))
                .shadow(color: colors.accent.opacity(enabled ? 0.35 : 0), radius: 8, y: 3)
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.9))
        .help(playback.playing ? "Pause (Leertaste)" : "Vorhören (Leertaste)")
        .accessibilityLabel(playback.playing ? "Vorhören anhalten" : "Vorhören")
    }
}

/// Abspielposition „1:23.400 / 3:32“ (beobachtet nur den Vorhör-Zustand).
struct StudioPlayheadLabel: View {
    @ObservedObject var playback: StudioPlayback
    @Environment(\.musicColors) private var colors
    let duration: Double

    var body: some View {
        HStack(spacing: 3) {
            Text(StudioTime.format(playback.playhead))
                .foregroundColor(colors.textPrimary)
            Text("/ \(StudioTime.format(duration, millis: false))")
                .foregroundColor(colors.textTertiary)
        }
        .font(Typo.inter(13, .medium))
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Abspielposition")
    }
}

/// Fläche um ein Zeitfeld (wie die übrigen Eingabefelder der App).
struct StudioTimeFieldChrome: ViewModifier {
    @Environment(\.musicColors) private var colors
    @Environment(\.isEnabled) private var enabled

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(colors.fieldFill.opacity(enabled ? 1 : 0.5)))
    }
}

/// Zeitfeld (AppKit), damit ↑/↓ den Wert in Schritten von 0,1 s ändern (⇧: 1 s) – auch unter macOS 13.
/// Eingaben wie „65“, „1:05“, „1:05,25“ werden mit `StudioTime.parse` gelesen; ungültige Eingaben werden verworfen.
struct StudioTimeField: NSViewRepresentable {
    @Environment(\.musicColors) private var colors
    @Environment(\.isEnabled) private var enabled
    let value: Double
    let label: String
    let commit: (Double) -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .center
        field.lineBreakMode = .byClipping
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.font = Self.font
        field.delegate = context.coordinator
        field.setAccessibilityLabel(label)
        field.toolTip = "\(label) – ↑/↓ ändert um 0,1 s, mit ⇧ um 1 s"
        field.stringValue = StudioTime.format(value)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.isEnabled = enabled
        field.textColor = NSColor(enabled ? colors.textPrimary : colors.textTertiary)
        if field.currentEditor() == nil {
            let text = StudioTime.format(value)
            if field.stringValue != text { field.stringValue = text }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Inter mit gleich breiten Ziffern.
    static var font: NSFont {
        let base = Typo.nsInter(13, .medium)
        // kNumberSpacingType = 6, kMonospacedNumbersSelector = 0 (CoreText)
        let desc = base.fontDescriptor.addingAttributes([
            .featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: 6, NSFontDescriptor.FeatureKey.selectorIdentifier: 0]],
        ])
        return NSFont(descriptor: desc, size: 13) ?? base
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: StudioTimeField

        init(_ parent: StudioTimeField) { self.parent = parent }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                step(+1, textView)
                return true
            case #selector(NSResponder.moveDown(_:)):
                step(-1, textView)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                apply(textView.string, textView)
                control.window?.makeFirstResponder(nil)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                textView.string = StudioTime.format(parent.value)
                control.window?.makeFirstResponder(nil)
                return true
            default:
                return false
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            if let v = StudioTime.parse(field.stringValue), abs(v - parent.value) > 0.0005 {
                parent.commit(v)
            } else {
                field.stringValue = StudioTime.format(parent.value)
            }
        }

        private func step(_ direction: Double, _ textView: NSTextView) {
            let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
            let current = StudioTime.parse(textView.string) ?? parent.value
            let next = max(0, current + direction * (shift ? 1 : 0.1))
            parent.commit(next)
            textView.string = StudioTime.format(next)
            textView.selectAll(nil)
        }

        private func apply(_ text: String, _ textView: NSTextView) {
            if let v = StudioTime.parse(text) {
                parent.commit(v)
                textView.string = StudioTime.format(v)
            } else {
                textView.string = StudioTime.format(parent.value)
                NSSound.beep()
            }
        }
    }
}

/// Ein- bzw. Ausblenden: kleine Kapsel mit Glas-Menü (Aus, 0,5 s … 8 s).
struct StudioFadeMenu: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    let fadeIn: Bool

    static let choices: [Double] = [0, 0.5, 1, 2, 3, 5, 8]

    var body: some View {
        let value = fadeIn ? studio.fadeIn : studio.fadeOut
        let title = fadeIn ? "Einblenden" : "Ausblenden"
        GlassMenuButton(help: "\(title): \(value > 0 ? Self.seconds(value) : "aus")", width: 220) {
            HStack(spacing: 5) {
                Icon(fadeIn ? Icons.fadeIn : Icons.fadeOut, size: 15, color: value > 0 ? colors.accentText : colors.textSecondary)
                Text(value > 0 ? Self.seconds(value) : (fadeIn ? "Ein" : "Aus"))
                    .font(Typo.inter(12, .semibold))
                    .monospacedDigit()
                    .foregroundColor(value > 0 ? colors.accentText : colors.textPrimary)
                Icon(Icons.expandMore, size: 12, color: colors.textTertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule().fill(value > 0 ? colors.accentSoft : colors.fieldFill))
            .contentShape(Capsule())
        } content: { menu in
            GlassMenuHeader(title: title)
            ForEach(Self.choices, id: \.self) { c in
                GlassMenuItem(title: c == 0 ? "Aus" : Self.seconds(c), checked: abs(value - c) < 0.001) {
                    if fadeIn { studio.fadeIn = c } else { studio.fadeOut = c }
                    menu.close()
                }
            }
            if studio.isLibraryTrack {
                GlassMenuDivider()
                Text("Blenden erfordern eine Neukodierung.")
                    .textStyle(Typo.labelSmall)
                    .foregroundColor(colors.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
            }
        }
    }

    static func seconds(_ v: Double) -> String {
        let text = v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
        return "\(text) s"
    }
}
