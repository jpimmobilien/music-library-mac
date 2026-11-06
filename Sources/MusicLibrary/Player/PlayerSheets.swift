import SwiftUI
import AppKit
import MLCore
import MLTags

/// Rahmen der Player-Blätter (Spec 8.1): Grund backgroundGrouped, Titel headlineSmall, Karten mit Radius 18.
struct PlayerSheetHost: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    @Environment(\.dismiss) private var dismiss
    let sheet: PlayerSheet
    let theme: PlayerTheme
    @ObservedObject var artwork: NowPlayingArtwork

    var body: some View {
        let width: CGFloat = {
            switch sheet {
            case .equalizer: return 640
            case .design: return 600
            case .pitch, .sleep, .queue, .info: return 520
            }
        }()
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    switch sheet {
                    case .equalizer: EqualizerPanel()
                    case .pitch: PitchPanel()
                    case .sleep: SleepTimerPanel()
                    case .queue: QueueSheetContent()
                    case .info: SongInfoPanel()
                    case .design: DesignPanel()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 14)
            }
            HStack {
                Spacer()
                PillButton(title: "Fertig", style: .tonal) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
        }
        .frame(width: width)
        .frame(minHeight: 360, maxHeight: 760)
        .background(colors.backgroundGrouped)
        .foregroundColor(colors.textPrimary)
    }
}

/// Karte innerhalb der Blätter (`SheetCard`). In eigenen Fenstern mit atmosphärischem Hintergrund (Equalizer-
/// Fenster) als Glaskarte (`\.sheetCardGlass`) – gleicher Aufbau, Glas-Vokabular der App (Leistungsmodus inklusive).
struct SheetCard<Content: View>: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.sheetCardGlass) private var glassCard
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        if glassCard {
            VStack(alignment: .leading, spacing: 8) { content() }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(shape)
        } else {
            VStack(alignment: .leading, spacing: 8) { content() }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(shape.fill(colors.surface))
        }
    }
}

private struct SheetCardGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Karten der Player-Tafeln als Glaskarten zeichnen (eigene Fenster auf `AmbientBackground`).
    var sheetCardGlass: Bool {
        get { self[SheetCardGlassKey.self] }
        set { self[SheetCardGlassKey.self] = newValue }
    }
}

struct SheetTitle<Trailing: View>: View {
    @Environment(\.musicColors) private var colors
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Text(title).textStyle(Typo.headlineSmall).foregroundColor(colors.textPrimary)
            Spacer()
            trailing()
        }
        .padding(.bottom, 14)
    }
}

private struct Hint: View {
    @Environment(\.musicColors) private var colors
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// Zeilenumbrechende Anordnung (Preset-Chips).
struct PlayerFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Equalizer (Spec 8.2, v2: eigene Presets, Vorhören beim Ziehen)

/// Zugriff auf den Entwurf während des Ziehens: hörbar über `previewEffects`, gespeichert beim Loslassen.
struct EqEditor {
    let current: () -> AudioEffectsSettings
    let preview: (AudioEffectsSettings) -> Void
    let commit: () -> Void
}

/// Entwurf des Equalizers, solange ein Regler gezogen wird (v2.1, behebt „Schalter und Presets reagieren im
/// Equalizer-Fenster nicht“).
///
/// Ursache war ein liegengebliebener Entwurf: Kam das Ende einer Ziehbewegung nicht an, zeigte die Tafel weiter
/// den Entwurf – Schalter und Presets (die die gespeicherte Einstellung schreiben) blieben unsichtbar, und beim
/// Schließen wurde der alte Entwurf zurückgeschrieben. Regeln jetzt:
/// - Ein Entwurf lebt nur während des Ziehens. Kommt ≈ 0,6 s keine Vorschau mehr, wird er gesichert
///   (Sicherheitsnetz für ein verlorenes Ende der Geste).
/// - Jede einzelne Aktion (Schalter, Preset, eigenes Preset, Zurücksetzen, Bass auf 0, Aussteuerung) verwirft
///   zuerst den Entwurf und schreibt dann die Einstellung – sofort sichtbar und hörbar.
/// - Ändert sich die gespeicherte Einstellung anderswo (Mini-Player, Einstellungen), während nicht gezogen wird,
///   entfällt der Entwurf.
/// - Beim Verschwinden der Tafel wird nur ein laufendes Ziehen gesichert.
@MainActor
final class EqDraft: ObservableObject {
    @Published private(set) var value: AudioEffectsSettings?
    /// Gespeicherter Stand, auf dem der Entwurf beruht.
    private var base: AudioEffectsSettings?
    private var lastPreview = Date.distantPast
    private weak var model: AppModel?
    private var watcher: Task<Void, Never>?
    static let safetyDelay: TimeInterval = 0.6

    /// Angezeigte Werte: Entwurf (beim Ziehen) oder gespeicherte Einstellung.
    func shown(_ saved: AudioEffectsSettings) -> AudioEffectsSettings { value ?? saved }

    /// Wird gerade gezogen (letzte Vorschau jünger als die Sicherheitsfrist)?
    var isLive: Bool { value != nil && Date().timeIntervalSince(lastPreview) < EqDraft.safetyDelay }

    /// Vorschau beim Ziehen: hörbar, noch nicht gespeichert.
    func preview(_ e: AudioEffectsSettings, model: AppModel) {
        self.model = model
        if value == nil { base = model.settings.effects }
        value = e
        lastPreview = Date()
        model.previewEffects(e)
        startWatcher()
    }

    /// Ende des Ziehens: Entwurf speichern.
    func commit(model: AppModel) {
        guard let d = value else { return }
        clear()
        if model.settings.effects != d {
            model.settings.effects = d
        } else {
            model.previewEffects(d)
        }
    }

    /// Entwurf verwerfen; hörbar ist wieder die gespeicherte Einstellung.
    func discard(model: AppModel) {
        guard value != nil else { return }
        clear()
        model.previewEffects(model.settings.effects)
    }

    /// Tafel verschwindet: nur ein laufendes Ziehen sichern, einen alten Entwurf verwerfen.
    func finish(model: AppModel) {
        if isLive { commit(model: model) } else { discard(model: model) }
    }

    /// Gespeicherte Einstellung hat sich geändert. Von außen (nicht durch das eigene Sichern) und ohne laufendes
    /// Ziehen → Entwurf verwerfen, damit die Tafel die neue Einstellung zeigt.
    func savedChanged(_ saved: AudioEffectsSettings, model: AppModel) {
        guard value != nil, saved != base, !isLive else { return }
        discard(model: model)
    }

    private func clear() {
        value = nil
        base = nil
        watcher?.cancel()
        watcher = nil
    }

    /// Sicherheitsnetz: ohne neue Vorschau nach `safetyDelay` sichern. Eine einzige wartende Aufgabe je Entwurf
    /// (kein Zeitgeber je Bild).
    private func startWatcher() {
        guard watcher == nil else { return }
        watcher = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let wait = self?.remainingDelay ?? 0
                try? await Task.sleep(nanoseconds: UInt64(max(0.05, wait) * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                guard self.value != nil else {
                    self.watcher = nil
                    return
                }
                if self.remainingDelay <= 0.01 {
                    self.watcher = nil
                    if let model = self.model { self.commit(model: model) }
                    return
                }
            }
        }
    }

    private var remainingDelay: TimeInterval {
        EqDraft.safetyDelay - Date().timeIntervalSince(lastPreview)
    }
}

/// Einzelne Equalizer-Aktionen schreiben (Schalter, Presets, Zurücksetzen …): erst einen etwaigen Entwurf
/// verwerfen, dann die gespeicherte Einstellung ändern. Gleich für Tafel, Blatt im Player, Fenster und Popover.
@MainActor
enum EqWrite {
    static func apply(_ model: AppModel, draft: EqDraft?, _ change: (inout AudioEffectsSettings) -> Void) {
        let hadDraft = draft?.value != nil
        if let draft, hadDraft { draft.discard(model: model) }
        var e = model.settings.effects
        change(&e)
        if e != model.settings.effects {
            model.settings.effects = e          // speichert und macht hörbar (AppModel → Klangkette)
        } else if hadDraft {
            model.previewEffects(e)
        }
    }
}

/// Texte zum Equalizer (Werkzeugleiste, Hilfen).
enum EqualizerText {
    static func summary(_ fx: AudioEffectsSettings, userPresets: [EqUserPreset]) -> String {
        let bass: String = fx.bassDb != 0 ? " · Bass \(Formatting.decibel(fx.bassDb))" : ""
        if !fx.eqEnabled { return "aus" + bass }
        if let u = fx.activeUserPreset(in: userPresets) { return u.name + bass }
        if let p = fx.activePreset { return (fx.isEqNeutral ? "neutral" : p.name) + bass }
        return "Eigene Einstellung" + bass
    }

    /// Kurzbeschriftung für die Werkzeugleiste.
    static func short(_ fx: AudioEffectsSettings, userPresets: [EqUserPreset]) -> String {
        if fx.eqEnabled && !fx.isEqNeutral {
            if let u = fx.activeUserPreset(in: userPresets) { return u.name }
            return fx.activePreset?.name ?? "Eigen"
        }
        if fx.bassDb != 0 { return "Bass " + PitchText.shortDb(fx.bassDb) }
        return "Equalizer"
    }
}

struct EqualizerPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    @StateObject private var draft = EqDraft()
    @State private var confirmDelete: EqUserPreset?

    var body: some View {
        let fx = draft.shown(model.settings.effects)
        let editor = EqEditor(
            current: { draft.shown(model.settings.effects) },
            preview: { e in draft.preview(e, model: model) },
            commit: { draft.commit(model: model) }
        )
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(title: "Equalizer") {
                MusicToggle(isOn: Binding(get: { fx.eqEnabled }, set: { on in EqWrite.apply(model, draft: draft) { $0.eqEnabled = on } }),
                            label: "Equalizer ein/aus")
            }
            EqPresetChips(fx: fx, confirmDelete: $confirmDelete, manage: true, draft: draft)
            Spacer().frame(height: 14)
            EqBassCard(fx: fx, editor: editor, draft: draft)
            Spacer().frame(height: 12)
            EqBandsCard(fx: fx, editor: editor)
            Spacer().frame(height: 12)
            EqUserPresetsCard(fx: fx, confirmDelete: $confirmDelete, draft: draft)
            Group {
                Spacer().frame(height: 12)
                SheetCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatische Aussteuerung").textStyle(Typo.bodyLarge)
                            Hint("Senkt den Pegel bei angehobenen Bändern etwas ab, damit nichts verzerrt.")
                        }
                        Spacer()
                        MusicToggle(isOn: Binding(get: { fx.autoHeadroom }, set: { on in EqWrite.apply(model, draft: draft) { $0.autoHeadroom = on } }),
                                    label: "Automatische Aussteuerung")
                    }
                }
                Spacer().frame(height: 12)
                HStack {
                    Hint("Wirkt nur auf die Musik dieser App · ±12 dB je Band · beim Ziehen sofort hörbar.")
                    Spacer()
                    PillButton(title: "Zurücksetzen", style: .plain) {
                        EqWrite.apply(model, draft: draft) { $0 = $0.withPreset(EqPresets.flat).withBass(0) }
                    }
                        .help("Alle Bänder und Bass auf 0 dB")
                }
            }
        }
        // Nur ein laufendes Ziehen sichern; Änderungen von außen (Mini-Player, Einstellungen) verwerfen den Entwurf
        .onDisappear { draft.finish(model: model) }
        .onChange(of: model.settings.effects) { saved in draft.savedChanged(saved, model: model) }
        .alert("Preset löschen?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), presenting: confirmDelete) { p in
            Button("Löschen", role: .destructive) {
                model.settings.deleteEqPreset(id: p.id)
                model.toast("Preset „\(p.name)“ gelöscht")
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { p in
            Text("„\(p.name)“ wird endgültig entfernt. Die aktuelle Klangeinstellung bleibt erhalten.")
        }
    }
}

/// Auswahl-Kapsel für Presets (eigene Presets mit Personensymbol).
private struct PresetChip: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.isEnabled) private var enabled
    let title: String
    let icon: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Icon(icon, size: 12, color: selected ? colors.accentText : colors.textSecondary) }
                Text(title)
                    .textStyle(Typo.labelMedium)
                    .foregroundColor(!enabled ? colors.textTertiary : selected ? colors.accentText : colors.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .frame(minHeight: 28)
            .background(Capsule().fill(selected ? colors.accentSoft : (colors.dark ? Color.white.opacity(0.07) : colors.surface)))
            .overlay(Capsule().strokeBorder(!selected && !colors.dark ? colors.hairline : .clear, lineWidth: 0.8))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle(scale: 0.95))
        .animation(Motion.easeOut(), value: selected)
        .accessibilityLabel(icon == nil ? "Preset \(title)" : "Eigenes Preset \(title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Eingebaute und eigene Presets als umbrechende Chips (eigene mit Kontextmenü).
struct EqPresetChips: View {
    @EnvironmentObject private var model: AppModel
    let fx: AudioEffectsSettings
    @Binding var confirmDelete: EqUserPreset?
    /// Kontextmenü (Überschreiben, Löschen) anbieten.
    var manage: Bool = false
    /// Entwurf der Tafel (wird vor jeder Auswahl verworfen); `nil` im Popover ohne Regler.
    var draft: EqDraft? = nil

    var body: some View {
        let users = model.settings.eqUserPresets
        let activeUser = fx.activeUserPreset(in: users)
        let builtIn = fx.activePreset
        PlayerFlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(EqPresets.all) { p in
                PresetChip(title: p.name, icon: nil, selected: fx.eqEnabled && activeUser == nil && builtIn?.id == p.id) {
                    EqWrite.apply(model, draft: draft) { $0 = $0.withPreset(p) }
                }
                .help("Preset „\(p.name)“")
            }
            ForEach(users) { p in
                PresetChip(title: p.name, icon: PlayerIcons.person, selected: fx.eqEnabled && activeUser?.id == p.id) {
                    EqWrite.apply(model, draft: draft) { $0 = $0.withUserPreset(p) }
                }
                .help("Eigenes Preset „\(p.name)“\(manage ? " – Rechtsklick für weitere Aktionen" : "")")
                .contextMenu {
                    if manage {
                        Button("Mit aktueller Einstellung überschreiben") {
                            draft?.commit(model: model)
                            model.settings.updateEqPreset(id: p.id)
                            model.toast("„\(p.name)“ überschrieben")
                        }
                        Button("Löschen …") { confirmDelete = p }
                    }
                }
            }
            if builtIn == nil && activeUser == nil {
                PresetChip(title: "Eigene Einstellung", icon: nil, selected: fx.eqEnabled) {}
                    .disabled(true)
            }
        }
    }
}

/// Bassregler (live hörbar beim Ziehen).
private struct EqBassCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    let fx: AudioEffectsSettings
    let editor: EqEditor
    let draft: EqDraft

    var body: some View {
        SheetCard {
            HStack {
                Text("Bass").textStyle(Typo.titleMedium)
                Spacer()
                Text(fx.bassDb == 0 ? "0 dB" : Formatting.decibel(fx.bassDb))
                    .font(Typo.inter(15 * 0.875, .medium))
                    .monospacedDigit()
                    .foregroundColor(fx.bassDb != 0 ? colors.accentText : colors.textSecondary)
                if fx.bassDb != 0 {
                    IconTap(icon: Icons.clear, label: "Bass auf 0 dB", tint: colors.textSecondary, iconSize: 16, touch: 30) {
                        EqWrite.apply(model, draft: draft) { $0 = $0.withBass(0) }
                    }
                }
            }
            MusicSlider(value: Binding(get: { Double(fx.bassDb) }, set: { v in
                let snapped: Float = abs(v) < 0.6 ? 0 : Float((v * 2).rounded() / 2)
                editor.preview(editor.current().withBass(snapped))
            }), range: -12...12, marker: 0, bipolar: true, activeColor: colors.accent, label: "Bass", valueText: Formatting.decibel(fx.bassDb)) { editing in
                if !editing { editor.commit() }
            }
            HStack {
                Text("weniger").textStyle(Typo.labelSmall).foregroundColor(colors.textTertiary)
                Spacer()
                Text("mehr").textStyle(Typo.labelSmall).foregroundColor(colors.textTertiary)
            }
            Hint(fx.bassLimited ? "Wirksam: \(Formatting.decibel(fx.effectiveBassDb)) – der Equalizer hebt die Bässe bereits an (zusammen höchstens +12 dB)." : "Tiefen unter ≈ 150 Hz · Mitten und Höhen bleiben unverändert.")
        }
    }
}

/// Zehn Bänder mit Kurve (live hörbar beim Ziehen).
private struct EqBandsCard: View {
    @Environment(\.musicColors) private var colors
    let fx: AudioEffectsSettings
    let editor: EqEditor

    var body: some View {
        SheetCard {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<EqBands.count, id: \.self) { i in
                    VStack(spacing: 6) {
                        let g = fx.bandGains[i]
                        Text(g == 0 ? "0" : Formatting.decibel(g).replacingOccurrences(of: " dB", with: ""))
                            .font(Typo.inter(10.5, .medium))
                            .monospacedDigit()
                            .foregroundColor(g == 0 ? colors.textTertiary : colors.accentText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        VerticalBandSlider(value: g, enabled: fx.eqEnabled, label: "\(EqBands.labels[i]) Hz", onChange: { v in
                            editor.preview(editor.current().withBand(i, v))
                        }, onEnded: editor.commit)
                        .frame(height: 188)
                        Text(EqBands.labels[i])
                            .textStyle(Typo.labelSmall)
                            .foregroundColor(colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack {
                Text("Bass").frame(maxWidth: .infinity, alignment: .leading)
                Text("Mitten").frame(maxWidth: .infinity)
                Text("Höhen").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .textStyle(Typo.labelSmall)
            .foregroundColor(colors.textTertiary)
            .padding(.top, 6)
            EqualizerCurve(settings: fx)
                .frame(height: 54)
                .padding(.top, 8)
        }
    }
}

/// Eigene Presets: aktuelle Einstellung sichern, anwenden, umbenennen, überschreiben, löschen (mit Rückfrage).
private struct EqUserPresetsCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    let fx: AudioEffectsSettings
    @Binding var confirmDelete: EqUserPreset?
    let draft: EqDraft
    @State private var adding = false
    @State private var newName = ""
    @State private var renamingID: String?
    @State private var renameText = ""

    var body: some View {
        let presets = model.settings.eqUserPresets
        let active = fx.activeUserPreset(in: presets)
        SheetCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Eigene Presets").textStyle(Typo.titleMedium)
                    Hint("Aktuelle Einstellung (Bänder und Bass) als Preset sichern.")
                }
                Spacer()
                if !adding {
                    PillButton(title: "Sichern …", icon: PlayerIcons.save) {
                        newName = "Mein Preset \(presets.count + 1)"
                        renamingID = nil
                        adding = true
                    }
                    .help("Aktuelle Einstellung als eigenes Preset sichern")
                }
            }
            if adding {
                PresetNameField(text: $newName, placeholder: "Name des Presets", confirmTitle: "Sichern", onConfirm: save, onCancel: { adding = false })
            }
            if presets.isEmpty && !adding {
                Hint("Noch keine eigenen Presets. Sie erscheinen danach neben den eingebauten – auch im Mini-Player.")
            }
            ForEach(presets) { p in
                EqUserPresetRow(preset: p, active: active?.id == p.id, renaming: renamingID == p.id, renameText: $renameText,
                                apply: { EqWrite.apply(model, draft: draft) { $0 = $0.withUserPreset(p) } },
                                startRename: {
                                    adding = false
                                    renameText = p.name
                                    renamingID = p.id
                                },
                                commitRename: {
                                    let n = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !n.isEmpty { model.settings.renameEqPreset(id: p.id, to: n) }
                                    renamingID = nil
                                },
                                cancelRename: { renamingID = nil },
                                overwrite: {
                                    draft.commit(model: model)   // gesichert wird, was zu sehen und zu hören ist
                                    model.settings.updateEqPreset(id: p.id)
                                    model.toast("„\(p.name)“ mit der aktuellen Einstellung überschrieben")
                                },
                                delete: { confirmDelete = p })
            }
        }
    }

    private func save() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        draft.commit(model: model)
        let preset = model.settings.saveEqPreset(name: name)
        adding = false
        model.toast("Preset „\(preset.name)“ gesichert")
    }
}

/// Namensfeld mit Bestätigen/Abbrechen (Eingabe bestätigt, Esc bricht ab).
private struct PresetNameField: View {
    @Environment(\.musicColors) private var colors
    @Binding var text: String
    let placeholder: String
    let confirmTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(onConfirm)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(colors.fieldFill))
                .accessibilityLabel(placeholder)
            PillButton(title: confirmTitle, style: .filled, action: onConfirm)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            IconTap(icon: Icons.close, label: "Abbrechen (Esc)", tint: colors.textSecondary, iconSize: 14, touch: 28, action: onCancel)
        }
        .onExitCommand(perform: onCancel)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}

/// Zeile eines eigenen Presets.
private struct EqUserPresetRow: View {
    @Environment(\.musicColors) private var colors
    let preset: EqUserPreset
    let active: Bool
    let renaming: Bool
    @Binding var renameText: String
    let apply: () -> Void
    let startRename: () -> Void
    let commitRename: () -> Void
    let cancelRename: () -> Void
    let overwrite: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if renaming {
                PresetNameField(text: $renameText, placeholder: "Neuer Name", confirmTitle: "Umbenennen", onConfirm: commitRename, onCancel: cancelRename)
            } else {
                Button(action: apply) {
                    HStack(spacing: 8) {
                        Icon(active ? Icons.check : PlayerIcons.person, size: 15, color: active ? colors.accentText : colors.textSecondary)
                        Text(preset.name)
                            .font(Typo.inter(13.5, active ? .semibold : .medium))
                            .foregroundColor(active ? colors.accentText : colors.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        GainsLine(gains: preset.gains)
                            .stroke(active ? colors.accent : colors.textSecondary.opacity(0.7), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                            .frame(width: 64, height: 18)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("„\(preset.name)“ anwenden")
                .accessibilityLabel("Eigenes Preset \(preset.name) anwenden")
                IconTap(icon: Icons.edit, label: "„\(preset.name)“ umbenennen", tint: colors.textSecondary, iconSize: 15, touch: 28, action: startRename)
                IconTap(icon: PlayerIcons.save, label: "„\(preset.name)“ mit der aktuellen Einstellung überschreiben", tint: colors.textSecondary, iconSize: 15, touch: 28, action: overwrite)
                IconTap(icon: Icons.delete, label: "„\(preset.name)“ löschen …", tint: colors.danger.opacity(0.85), iconSize: 15, touch: 28, action: delete)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(active && !renaming ? colors.accentSoft : colors.textPrimary.opacity(0.03)))
    }
}

/// Kleine Kurve der zehn Bänder (Vorschau eines Presets).
struct GainsLine: Shape {
    let gains: [Float]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let n = max(gains.count, 2)
        for (i, g) in gains.enumerated() {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(n - 1)
            let y = rect.midY - CGFloat(max(-12, min(12, g)) / 12) * rect.height / 2
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}

/// Senkrechter Regler eines Bands (Spec 8.2): Klick setzt (0,5-dB-Raster), Doppelklick = 0 dB.
/// Während des Ziehens `onChange` (Vorhören), beim Loslassen `onEnded` (Speichern).
struct VerticalBandSlider: View {
    @Environment(\.musicColors) private var colors
    let value: Float
    let enabled: Bool
    var label: String = "Band"
    let onChange: (Float) -> Void
    var onEnded: () -> Void = {}
    /// Fällt beim Ende **und** beim Abbruch der Geste zurück – das Ende kommt damit sicher an (v2.1).
    @GestureState private var pressing = false

    var body: some View {
        GeometryReader { geo in
            let top: CGFloat = 12
            let bottom = geo.size.height - 12
            let y: (Float) -> CGFloat = { db in bottom - CGFloat((db + 12) / 24) * (bottom - top) }
            let a: Double = enabled ? 1 : 0.38
            let cx = geo.size.width / 2
            ZStack {
                Capsule().fill(colors.textPrimary.opacity(0.10 * a)).frame(width: 4, height: bottom - top).position(x: cx, y: (top + bottom) / 2)
                Rectangle().fill(colors.textPrimary.opacity(0.25 * a)).frame(width: 16, height: 1).position(x: cx, y: y(0))
                let y0 = y(0), yv = y(value)
                Capsule().fill(colors.accent.opacity(a)).frame(width: 4, height: abs(yv - y0)).position(x: cx, y: (y0 + yv) / 2)
                Circle().fill(Color.black.opacity(0.14 * a)).frame(width: 21, height: 21).position(x: cx, y: yv + 1)
                Circle().fill(Color.white.opacity(enabled ? 1 : 0.7)).frame(width: 19, height: 19).position(x: cx, y: yv)
                Circle().fill(colors.accent.opacity(a)).frame(width: 6, height: 6).position(x: cx, y: yv)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .updating($pressing) { _, state, _ in state = true }
                .onChanged { g in
                    guard enabled else { return }
                    let f = Float((bottom - min(max(g.location.y, top), bottom)) / (bottom - top))
                    let db = ((f * 24 - 12) * 2).rounded() / 2
                    if db != value { onChange(db) }
                }
                .onEnded { _ in
                    guard enabled else { return }
                    onEnded()
                })
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                guard enabled else { return }
                onChange(0)
                onEnded()
            })
        }
        .onChange(of: pressing) { down in if !down { onEnded() } }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(Formatting.decibel(value))
        .accessibilityAdjustableAction { dir in
            guard enabled else { return }
            onChange(EqBands.clamp(value + (dir == .increment ? 0.5 : -0.5)))
            onEnded()
        }
    }
}

/// Frequenzgang aus Equalizer und Bass (gleiche Formeln wie die Filter, `EqResponse`).
struct EqualizerCurve: View {
    @Environment(\.musicColors) private var colors
    let settings: AudioEffectsSettings

    var body: some View {
        let bands = settings.effectiveBands
        let bass = Double(settings.effectiveBassDb)
        let accent = colors.accent
        let hairline = colors.hairline
        Canvas { ctx, size in
            var path = Path()
            let n = 120
            for i in 0...n {
                let f = 20 * pow(20000.0 / 20, Double(i) / Double(n))
                var db = EqResponse.equalizerDb(f, bands: bands) + EqResponse.lowShelfDb(f, f0: AudioEffectsSettings.bassFrequency, gainDb: bass)
                db = max(-15, min(15, db))
                let x = size.width * CGFloat(i) / CGFloat(n)
                let y = size.height / 2 - CGFloat(db / 15) * size.height / 2
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(Path(CGRect(x: 0, y: size.height / 2, width: size.width, height: 0.5)), with: .color(hairline))
            ctx.stroke(path, with: .color(accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Eigenes Equalizer-Fenster (⌥⌘E) – dieselbe Tafel wie im Player, hier mit Glaskarten auf dem
/// atmosphärischen App-Hintergrund. Der Inhalt beginnt unter der (verdeckten) Titelleiste; dort lässt sich das
/// Fenster verschieben.
struct EqualizerWindow: View {
    @Environment(\.musicColors) private var colors

    var body: some View {
        ZStack(alignment: .top) {
            AmbientBackground()
            ScrollView {
                EqualizerPanel()
                    .environment(\.sheetCardGlass, true)
                    .padding(.horizontal, 24)
                    .padding(.top, 40)
                    .padding(.bottom, 24)
            }
            EdgeFade(top: true, strength: 0.8)
                .frame(height: 34)
            WindowDragArea()
                .frame(height: 28)
        }
        .frame(width: 640, height: 720)
    }
}

/// Kurzform für das Mini-Player-Popover: Ein/Aus, Presets (auch eigene), Kurve, Weg zu allen Einstellungen.
struct EqualizerQuickPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    let close: () -> Void

    var body: some View {
        let fx = model.settings.effects
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Equalizer").textStyle(Typo.titleSmall).foregroundColor(colors.textPrimary)
                Spacer()
                MusicToggle(isOn: Binding(get: { fx.eqEnabled }, set: { on in EqWrite.apply(model, draft: nil) { $0.eqEnabled = on } }),
                            label: "Equalizer ein/aus")
            }
            EqPresetChips(fx: fx, confirmDelete: .constant(nil), manage: false)
            EqualizerCurve(settings: fx)
                .frame(height: 44)
                .padding(.horizontal, 2)
                .opacity(fx.eqEnabled || fx.bassDb != 0 ? 1 : 0.45)
            Text(EqualizerText.summary(fx, userPresets: model.settings.eqUserPresets))
                .textStyle(Typo.bodySmall)
                .foregroundColor(colors.textSecondary)
                .lineLimit(1)
            HStack {
                PillButton(title: "Neutral", style: .plain) { EqWrite.apply(model, draft: nil) { $0 = $0.withPreset(EqPresets.flat) } }
                    .help("Alle Bänder auf 0 dB")
                Spacer()
                PillButton(title: "Alle Einstellungen …", icon: Icons.tune, style: .tonal) {
                    close()
                    WindowRouter.shared.openEqualizer()
                }
                .help("Equalizer-Fenster mit allen Bändern, Bass und eigenen Presets öffnen (⌥⌘E)")
            }
        }
    }
}

// MARK: - Tonhöhe und Tempo (Spec 8.3, v2: Feinstufen 0,1, Cent, Vorhören beim Ziehen)

struct PitchPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let pitch = model.settings.pitch
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(title: "Tonhöhe") {
                PillButton(title: "Original") { model.settings.pitch = PitchSettings(mode: pitch.mode) }
                    .disabled(pitch.isOriginal)
                    .help("Tonhöhe und Tempo zurücksetzen")
            }
            PitchControls(compact: false)
        }
    }
}

/// Zugriff auf den Entwurf während des Ziehens: hörbar über `previewPitch`, gespeichert beim Loslassen.
struct PitchEditor {
    let current: () -> PitchSettings
    let preview: (PitchSettings) -> Void
    let commit: () -> Void
    /// Sofort setzen und speichern (Tasten).
    let set: (PitchSettings) -> Void
}

/// Tonhöhe und Tempo – gemeinsam für das Blatt im Player (`compact == false`) und das Popover im Mini-Player.
struct PitchControls: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    var compact: Bool = false
    @State private var draft: PitchSettings?

    var body: some View {
        let saved = model.settings.pitch
        let pitch = draft ?? saved
        let editor = PitchEditor(
            current: { draft ?? model.settings.pitch },
            preview: { p in
                draft = p
                model.previewPitch(p)
            },
            commit: {
                if let d = draft { model.settings.pitch = d }
                draft = nil
            },
            set: { p in
                draft = nil
                model.settings.pitch = p
            }
        )
        VStack(alignment: .leading, spacing: compact ? 10 : 0) {
            if compact {
                HStack {
                    Text("Tonhöhe").textStyle(Typo.titleSmall).foregroundColor(colors.textPrimary)
                    Spacer()
                    PillButton(title: "Original", icon: PlayerIcons.restart, style: .plain) { editor.set(PitchSettings(mode: saved.mode)) }
                        .disabled(saved.isOriginal)
                        .help("Tonhöhe und Tempo zurücksetzen")
                }
            }
            SegmentedControl(options: PitchMode.allCases, selection: Binding(get: { saved.mode }, set: { editor.set(model.settings.pitch.withMode($0)) }),
                             label: { $0.label }, icon: { $0 == .key ? Icons.musicNote : Icons.vinyl }, height: compact ? 28 : 30)
            Hint(saved.mode.description).padding(.top, compact ? 0 : 6)
            if compact {
                PitchValueBlock(pitch: pitch, compact: true, editor: editor)
            } else {
                SheetCard { PitchValueBlock(pitch: pitch, compact: false, editor: editor) }
                    .padding(.top, 14)
            }
            Group {
                if pitch.mode == .key {
                    if compact {
                        PitchTempoBlock(pitch: pitch, compact: true, editor: editor)
                    } else {
                        SheetCard { PitchTempoBlock(pitch: pitch, compact: false, editor: editor) }
                            .padding(.top, 12)
                    }
                } else {
                    PitchSpeedChips(pitch: pitch, compact: compact, editor: editor)
                        .padding(.top, compact ? 0 : 14)
                }
            }
            if !compact {
                Hint(saved.mode == .key
                     ? "Tonhöhe und Tempo werden getrennt verändert (Zeitstreckung von macOS). Bei starken Änderungen sind leichte Klangveränderungen möglich. Änderungen sind sofort hörbar; der Titel startet nicht neu."
                     : "Wie eine Schallplatte mit anderer Drehzahl: Tonhöhe und Tempo ändern sich gemeinsam (reines Resampling). Plattenteller, Naben und CD drehen entsprechend schneller oder langsamer.")
                    .padding(.top, 14)
            }
        }
        .onDisappear { editor.commit() }
    }
}

/// Wert (Halbtöne mit Zehnteln, Cent), Regler in 0,1-Schritten und Tasten −1 · −0,1 · +0,1 · +1.
private struct PitchValueBlock: View {
    @Environment(\.musicColors) private var colors
    let pitch: PitchSettings
    let compact: Bool
    let editor: PitchEditor

    var body: some View {
        let shown = pitch.semitones
        let factor = pitch.factor
        let tempoText: String = pitch.tempo == 1 ? "unverändert" : Formatting.percent(pitch.tempo)
        let detail: String = pitch.mode == .key
            ? "Tonhöhe \(Formatting.factor(factor)) · Tempo \(tempoText)"
            : "Tonhöhe und Tempo \(Formatting.factor(factor)) (\(Formatting.percent(factor)))"
        let align: HorizontalAlignment = compact ? .leading : .center
        VStack(alignment: align, spacing: compact ? 6 : 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Formatting.semitones(shown))
                    .textStyle(compact ? Typo.titleLarge : Typo.displaySmall)
                    .monospacedDigit()
                    .foregroundColor(shown != 0 ? colors.accentText : colors.textPrimary)
                Text(Formatting.cents(shown))
                    .textStyle(Typo.labelMedium)
                    .monospacedDigit()
                    .foregroundColor(colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: compact ? .leading : .center)
            Text(detail)
                .textStyle(compact ? Typo.bodySmall : Typo.bodyMedium)
                .foregroundColor(colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: compact ? .leading : .center)
            MusicSlider(value: Binding(get: { Double(shown) }, set: { v in
                editor.preview(editor.current().withSemitones(Float((v * 10).rounded() / 10)))
            }), range: -12...12, marker: 0, bipolar: true, activeColor: colors.accent, step: Double(PitchSettings.fineStep),
                        label: "Halbtöne", valueText: Formatting.semitones(shown)) { editing in
                if !editing { editor.commit() }
            }
            .padding(.top, 4)
            HStack {
                Text("−12").frame(maxWidth: .infinity, alignment: .leading)
                Text("0").frame(maxWidth: .infinity)
                Text("+12").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .textStyle(Typo.labelSmall)
            .foregroundColor(colors.textTertiary)
            HStack(spacing: 6) {
                StepChip(title: "−1", help: "Einen Halbton tiefer", enabled: shown > PitchSettings.minSemitones) { step(-PitchSettings.coarseStep) }
                StepChip(title: "−0,1", help: "Einen Zehntel-Halbton tiefer (−10 Cent)", enabled: shown > PitchSettings.minSemitones) { step(-PitchSettings.fineStep) }
                StepChip(title: "+0,1", help: "Einen Zehntel-Halbton höher (+10 Cent)", enabled: shown < PitchSettings.maxSemitones) { step(PitchSettings.fineStep) }
                StepChip(title: "+1", help: "Einen Halbton höher", enabled: shown < PitchSettings.maxSemitones) { step(PitchSettings.coarseStep) }
            }
            .frame(maxWidth: .infinity, alignment: compact ? .leading : .center)
        }
    }

    private func step(_ delta: Float) {
        let cur = editor.current()
        let next = ((cur.semitones + delta) * 10).rounded() / 10
        editor.set(cur.withSemitones(next))
    }
}

/// Kleine Stufentaste.
private struct StepChip: View {
    @Environment(\.musicColors) private var colors
    let title: String
    let help: String
    let enabled: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typo.inter(12, .semibold))
                .monospacedDigit()
                .foregroundColor(enabled ? colors.textPrimary : colors.textTertiary)
                .frame(minWidth: 46, minHeight: 28)
                .background(Capsule().fill(colors.textPrimary.opacity(hover && enabled ? 0.11 : 0.06)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle(scale: 0.94))
        .disabled(!enabled)
        .onHover { hover = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Tempo (Modus „Tonhöhe“): 50–200 %, beim Ziehen hörbar.
private struct PitchTempoBlock: View {
    @Environment(\.musicColors) private var colors
    let pitch: PitchSettings
    let compact: Bool
    let editor: PitchEditor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tempo").textStyle(compact ? Typo.titleSmall : Typo.titleMedium)
                Spacer()
                Text(Formatting.percent(pitch.tempo))
                    .font(Typo.inter(13, .medium))
                    .monospacedDigit()
                    .foregroundColor(pitch.tempo != 1 ? colors.accentText : colors.textSecondary)
                if pitch.tempo != 1 {
                    IconTap(icon: PlayerIcons.restart, label: "Tempo auf 100 %", tint: colors.textSecondary, iconSize: 14, touch: 26) {
                        editor.set(editor.current().withTempo(1))
                    }
                }
            }
            MusicSlider(value: Binding(get: { Double(pitch.tempo) }, set: { v in
                let snapped: Double = abs(v - 1) < 0.03 ? 1 : (v * 20).rounded() / 20
                editor.preview(editor.current().withTempo(Float(snapped)))
            }), range: Double(PitchSettings.minTempo)...Double(PitchSettings.maxTempo), marker: 1, bipolar: true, activeColor: colors.accent,
                        step: 0.05, label: "Tempo", valueText: Formatting.percent(pitch.tempo)) { editing in
                if !editing { editor.commit() }
            }
            if !compact {
                Hint(PitchSettings.tempoDescription + " · 50 % bis 200 %")
            }
        }
    }
}

/// Plattenspieler-Drehzahl (Modus „Schallplatte“): 33⅓ ↔ 45 U/min.
private struct PitchSpeedChips: View {
    let pitch: PitchSettings
    let compact: Bool
    let editor: PitchEditor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plattenspieler-Drehzahl").textStyle(compact ? Typo.labelLarge : Typo.titleSmall)
            HStack(spacing: 8) {
                ChoiceChip(title: "33⅓ → 45 U/min", selected: abs(pitch.semitones - PitchSettings.rpm33To45) < 0.06) {
                    editor.set(editor.current().withSemitones((PitchSettings.rpm33To45 * 10).rounded() / 10))
                }
                .help("Eine 33er-Platte mit 45 U/min abspielen (+5,2 Halbtöne)")
                ChoiceChip(title: "45 → 33⅓ U/min", selected: abs(pitch.semitones - PitchSettings.rpm45To33) < 0.06) {
                    editor.set(editor.current().withSemitones((PitchSettings.rpm45To33 * 10).rounded() / 10))
                }
                .help("Eine 45er-Platte mit 33⅓ U/min abspielen (−5,2 Halbtöne)")
            }
        }
    }
}

// MARK: - Sleep-Timer (Spec 8.4)

struct SleepTimerPanel: View {
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    @State private var custom = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(title: "Sleep-Timer") { EmptyView() }
            if let t = player.sleepTimer {
                SheetCard {
                    if t.endOfTrack {
                        Text("Am Ende des Titels").textStyle(Typo.titleLarge).foregroundColor(colors.accentText)
                        Hint("Die Wiedergabe hält nach dem laufenden Titel an.")
                        PillButton(title: "Beenden", icon: Icons.clear) { player.cancelSleepTimer() }
                    } else {
                        SleepCountdownText(clock: player.clock)
                            .textStyle(Typo.displayMedium)
                            .monospacedDigit()
                            .foregroundColor(colors.accentText)
                            .frame(maxWidth: .infinity)
                        Hint("Danach wird die Musik sanft ausgeblendet und angehalten.")
                        HStack(spacing: 10) {
                            PillButton(title: "+15 Minuten", icon: Icons.add) {
                                let rest = Int(((player.clock.sleepRemainingMs ?? 0) + 59_999) / 60_000)
                                player.startSleepTimer(minutes: min(SleepTimerLogic.maxMinutes, rest + 15))
                            }
                            PillButton(title: "Beenden", icon: Icons.clear) { player.cancelSleepTimer() }
                        }
                    }
                }
                Text(t.endOfTrack ? "Stattdessen" : "Neu stellen").textStyle(Typo.titleSmall).padding(.top, 16)
            } else {
                Hint("Die Wiedergabe stoppt nach der gewählten Zeit – auch wenn der Mac gesperrt ist.")
            }
            HStack(spacing: 8) {
                ForEach(SleepTimerLogic.presetMinutes, id: \.self) { m in
                    ChoiceChip(title: "\(m) Min.", selected: false) { player.startSleepTimer(minutes: m) }
                }
                ChoiceChip(title: "Ende des Titels", selected: player.sleepTimer?.endOfTrack == true) { player.sleepAtEndOfTrack() }
            }
            .padding(.top, 10)
            HStack(spacing: 10) {
                TextField("Eigene Dauer (Minuten)", text: $custom)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors.fieldFill))
                    .onChange(of: custom) { v in custom = String(v.filter(\.isNumber).prefix(3)) }
                PillButton(title: "Starten", style: .filled) {
                    if let m = Int(custom), (1...SleepTimerLogic.maxMinutes).contains(m) { player.startSleepTimer(minutes: m) }
                }
                .disabled(!(Int(custom).map { (1...SleepTimerLogic.maxMinutes).contains($0) } ?? false))
            }
            .padding(.top, 14)
            Hint("1 bis \(SleepTimerLogic.maxMinutes) Minuten").padding(.top, 4)
        }
    }
}

// MARK: - Wiedergabeliste (Spec 8.5)

struct QueueSheetContent: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors

    var body: some View {
        let order = player.queue.upcoming(limit: 500)
        let repeatText: String? = player.repeatMode == .all ? "Quelle wiederholen" : (player.repeatMode == .one ? "Titel wiederholen" : nil)
        let shuffleText: String? = player.shuffleEnabled ? "Zufall" : nil
        let infoParts: [String?] = [player.queue.source?.label, Formatting.tracks(player.queue.count), shuffleText, repeatText]
        let info: String = infoParts.compactMap { $0 }.joined(separator: " · ")
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(title: "Wiedergabeliste") { EmptyView() }
            Hint(info)
            Spacer().frame(height: 12)
            if order.isEmpty {
                Hint("Keine Titel in der Warteschlange.")
            }
            ForEach(Array(order.enumerated()), id: \.element.id) { i, item in
                if i == 1 {
                    Text("ALS NÄCHSTES").textStyle(Typo.sectionLabel).foregroundColor(colors.textSecondary).padding(.top, 14).padding(.bottom, 6)
                }
                if let t = model.track(item.trackUid) {
                    let current = item.id == player.queue.current?.id
                    HStack(spacing: 12) {
                        ZStack {
                            TrackArtwork(track: t, size: .small)
                            if current {
                                RoundedRectangle(cornerRadius: Radius.artworkSmall).fill(Color.black.opacity(0.38))
                                NowPlayingBars(playing: player.isPlaying, color: colors.onAccent, size: 16)
                            }
                        }
                        .frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.displayTitle).font(Typo.inter(Typo.bodyLarge.size, current ? .semibold : .medium))
                                .foregroundColor(current ? colors.accentText : colors.textPrimary).lineLimit(1)
                            Text(t.artistText ?? "Unbekannter Interpret").textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).lineLimit(1)
                        }
                        Spacer()
                        Text(Formatting.duration(t.durationMs)).textStyle(Typo.duration).monospacedDigit().foregroundColor(colors.textTertiary)
                        if current {
                            Spacer().frame(width: 30)
                        } else {
                            IconTap(icon: Icons.clear, label: "Aus der Wiedergabeliste nehmen", tint: colors.textSecondary, iconSize: 15, touch: 30) { player.removeFromQueue(item: item) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(current ? colors.accentSoft : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { if !current { player.jump(to: item) } }
                }
            }
        }
    }
}

// MARK: - Songinformationen (Spec 8.6)

struct SongInfoPanel: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var result: TagReadResult?
    @State private var loading = true

    var body: some View {
        if let t = player.current {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    TrackArtwork(track: t, size: .medium, cornerRadius: Radius.artwork)
                        .frame(width: 64, height: 64)
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.displayTitle).textStyle(Typo.titleMedium).lineLimit(2)
                        Text(t.artistText ?? "Unbekannter Interpret").textStyle(Typo.bodyMedium).foregroundColor(colors.accentText)
                    }
                    Spacer()
                    PillButton(title: "Bearbeiten …", icon: Icons.edit) {
                        dismiss()
                        model.showInfo([t.uid])
                    }
                }
                SegmentedControl(options: [0, 1], selection: $tab, label: { $0 == 0 ? "Details" : "Songtext" })
                    .padding(.top, 14)
                if loading {
                    ProgressView().progressViewStyle(.linear).tint(colors.accent).padding(.top, 8)
                }
                if tab == 0 {
                    ForEach(groups(t)) { group in
                        Text(group.title).textStyle(Typo.sectionLabel).foregroundColor(colors.textSecondary).padding(.top, 16).padding(.bottom, 6)
                        VStack(spacing: 0) {
                            ForEach(Array(group.rows.enumerated()), id: \.offset) { i, row in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text(row.label).textStyle(Typo.bodyMedium).foregroundColor(colors.textSecondary).frame(width: 124, alignment: .leading)
                                    Text(row.value).textStyle(Typo.bodyMedium).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 10)
                                if i < group.rows.count - 1 { Hairline() }
                            }
                        }
                        .padding(.horizontal, 14)
                        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(colors.surface))
                    }
                } else {
                    if let lyrics = result?.values.lyrics, !lyrics.isEmpty {
                        Text(LyricsParser.parse(lyrics).isSynced ? LyricsParser.parse(lyrics).lines.map(\.text).joined(separator: "\n") : lyrics)
                            .textStyle(Typo.bodyLarge)
                            .lineSpacing(6)
                            .textSelection(.enabled)
                            .padding(.top, 14)
                    } else {
                        Hint("In dieser Datei ist kein Songtext gespeichert. Über „Bearbeiten …“ → „Liedtext“ kannst du ihn hinzufügen.").padding(.top, 14)
                    }
                }
            }
            .task(id: t.uid) {
                loading = true
                result = await Task.detached { try? TagFile.read(url: URL(fileURLWithPath: t.path)) }.value
                loading = false
            }
        }
    }

    struct InfoRow {
        let label: String
        let value: String
    }

    struct InfoGroup: Identifiable {
        let title: String
        let rows: [InfoRow]
        var id: String { title }
    }

    private func groups(_ t: Track) -> [InfoGroup] {
        var music: [InfoRow] = []
        func add(_ list: inout [InfoRow], _ label: String, _ value: String?) {
            if let value, !value.isEmpty { list.append(InfoRow(label: label, value: value)) }
        }
        add(&music, "Titel", t.displayTitle)
        add(&music, "Interpret", t.artistText)
        add(&music, "Album", t.album)
        add(&music, "Albuminterpret", t.albumArtistText)
        add(&music, "Komponist", t.composerText)
        add(&music, "Genre", t.genreText)
        add(&music, "Jahr", t.year.map(String.init))
        add(&music, "Titelnummer", t.trackNumber.map { n in t.trackTotal.map { "\(n) von \($0)" } ?? "\(n)" })
        add(&music, "Disc", t.discNumber.map { n in t.discTotal.map { "\(n) von \($0)" } ?? "\(n)" })
        if t.compilation { music.append(InfoRow(label: "Compilation", value: "Ja")) }
        add(&music, "BPM", t.bpm.map(String.init))
        var playback: [InfoRow] = []
        let s = model.stats[t.uid]
        playback.append(InfoRow(label: "Wiedergaben", value: Formatting.plays(s?.playCount ?? 0)))
        add(&playback, "Zuletzt gespielt", s?.lastPlayedAt.map { Formatting.dateTime($0) })
        add(&playback, "Bewertung", t.rating.map { r -> String in
            let stars = min(5, max(0, r / 20))
            return String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - stars)
        })
        playback.append(InfoRow(label: "Favorit", value: model.isFavorite(t.uid) ? "Ja" : "Nein"))
        var file: [InfoRow] = []
        add(&file, "Format", [result?.fileFormat, t.codec].compactMap { $0 }.joined(separator: " · "))
        add(&file, "Dauer", Formatting.duration(t.durationMs))
        add(&file, "Bitrate", t.bitrate > 0 ? "\(t.bitrate) kbit/s" : nil)
        add(&file, "Abtastrate", t.sampleRate > 0 ? Formatting.sampleRate(t.sampleRate) : nil)
        add(&file, "Kanäle", t.channels > 0 ? Formatting.channels(t.channels) : nil)
        add(&file, "Größe", Formatting.fileSize(t.sizeBytes))
        add(&file, "Ort", t.path)
        return [InfoGroup(title: "MUSIK", rows: music), InfoGroup(title: "WIEDERGABE", rows: playback), InfoGroup(title: "DATEI", rows: file)]
    }
}

// MARK: - Player-Design (Spec 8.7, v2: sieben Designs, Kassettenfarbe, Mini-Player)

struct DesignPanel: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    @StateObject private var artwork = NowPlayingArtwork(size: .medium)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Player-Design").textStyle(Typo.headlineSmall)
            Hint("Gleiche Bedienung in allen Designs – der Wechsel unterbricht die Wiedergabe nicht und wird gespeichert.").padding(.top, 4)
            Spacer().frame(height: 14)
            PlayerThemePicker(columns: 4)
            if model.settings.playerTheme == .cassette {
                SheetCard { CassetteColorPicker(palette: artwork.palette) }
                    .padding(.top, 14)
                    .transition(.opacity)
            }
            Spacer().frame(height: 12)
            SheetCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Klangvisualisierung").textStyle(Typo.bodyLarge)
                        Hint("Frequenzbalken, Lichtring (Aurora) bzw. Pegelanzeigen (Kassette, Studio Reel) folgen der Musik. Nur aktiv, solange der Player sichtbar ist; aus bei reduzierter Bewegung.")
                    }
                    Spacer()
                    MusicToggle(isOn: Binding(get: { model.settings.visualizer }, set: { model.settings.visualizer = $0 }), label: "Klangvisualisierung")
                }
            }
            // Group: höchstens 10 direkte Elemente je ViewBuilder unter macOS 13
            Group {
                Spacer().frame(height: 12)
                SheetCard { PlayerBackgroundPicker() }
                Spacer().frame(height: 12)
                SheetCard { MiniPlayerOptions() }
            }
        }
        .animation(Motion.easeOut(), value: model.settings.playerTheme)
        .task(id: player.current?.coverKey) { await artwork.update(for: player.current) }
    }
}

/// Mini-Player: Größe und Design-Anzeige.
private struct MiniPlayerOptions: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mini-Player").textStyle(Typo.titleMedium)
            // v2.1: fünf Größen; „Sehr groß“ und „Riesig“ mit eigenem, großzügigem Aufbau
            SegmentedControl(options: MiniPlayerSize.allCases, selection: Binding(get: { model.settings.miniPlayerSize },
                                                                                  set: { s in withAnimation(Motion.easeOut(Motion.medium)) { model.settings.miniPlayerSize = s } }),
                             label: { $0.label })
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Player-Design im Mini-Player").textStyle(Typo.bodyLarge)
                    Hint("Platte, Kassette, CD, Spulen oder Lichtring im Kleinen – bewegt sich nur während der Wiedergabe.")
                }
                Spacer()
                MusicToggle(isOn: Binding(get: { model.settings.miniPlayerShowsDesign }, set: { model.settings.miniPlayerShowsDesign = $0 }),
                            label: "Player-Design im Mini-Player")
            }
        }
    }
}

/// Gehäusefarben der Kassette (inkl. „Cover“ = aus den Farben des Covers).
struct CassetteColorPicker: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    let palette: CoverPalette
    var compact: Bool = false

    var body: some View {
        let current = model.settings.cassetteColor
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            HStack {
                Text("Kassettenfarbe").textStyle(compact ? Typo.labelLarge : Typo.titleMedium)
                Spacer()
                Text(current.label).textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary)
            }
            HStack(spacing: compact ? 6 : 10) {
                ForEach(CassetteColor.allCases, id: \.self) { c in
                    CassetteSwatch(color: CassetteShell.swatch(c, palette: palette), isCover: c == .cover, selected: c == current,
                                   label: c.label, diameter: compact ? 22 : 28) {
                        model.settings.cassetteColor = c
                    }
                }
            }
        }
    }
}

private struct CassetteSwatch: View {
    @Environment(\.musicColors) private var colors
    let color: Color
    let isCover: Bool
    let selected: Bool
    let label: String
    let diameter: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom))
                Circle().fill(LinearGradient(colors: [Color.white.opacity(0.3), .clear], startPoint: .topLeading, endPoint: .center))
                if isCover {
                    Icon(PlayerIcons.image, size: diameter * 0.46, color: Color.white.opacity(0.92))
                }
                Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8)
            }
            .frame(width: diameter, height: diameter)
            .padding(3)
            .overlay(Circle().strokeBorder(selected ? colors.accent : .clear, lineWidth: 2))
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.9))
        .help(isCover ? "Kassettenfarbe aus dem Cover" : "Kassettenfarbe \(label)")
        .accessibilityLabel("Kassettenfarbe \(label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Auswahl der Designs mit ruhenden Vorschauen (Blatt, Popover und Einstellungen).
struct PlayerThemePicker: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var appColors
    @StateObject private var artwork = NowPlayingArtwork(size: .medium)
    var columns = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
                ForEach(PlayerTheme.allCases, id: \.self) { theme in
                    ThemeTile(theme: theme, selected: model.settings.playerTheme == theme, artwork: artwork, compact: columns >= 4) {
                        withAnimation(PlayerMotionPolicy.transition(model.settings)) { model.settings.playerTheme = theme }
                    }
                }
            }
            Text(model.settings.playerTheme.description).textStyle(Typo.bodySmall).foregroundColor(appColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: player.current?.coverKey) { await artwork.update(for: player.current) }
    }
}

/// Kachel eines Designs mit Vorschau und Namen.
struct ThemeTile: View {
    @Environment(\.musicColors) private var appColors
    let theme: PlayerTheme
    let selected: Bool
    @ObservedObject var artwork: NowPlayingArtwork
    var compact: Bool = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let radius: CGFloat = compact ? 12 : 16
        Button(action: action) {
            VStack(spacing: compact ? 5 : 8) {
                ThemePreview(theme: theme, artwork: artwork)
                    .aspectRatio(0.8, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(selected ? appColors.accent : appColors.hairline, lineWidth: selected ? 2.5 : 1))
                    .scaleEffect(hover && !selected ? 1.025 : 1)
                HStack(spacing: 3) {
                    if selected { Icon(Icons.check, size: compact ? 12 : 15, color: appColors.accentText) }
                    Text(theme.label)
                        .font(Typo.inter(compact ? 11 : Typo.labelLarge.size, selected ? .semibold : .medium))
                        .foregroundColor(selected ? appColors.accentText : appColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(compact ? 2 : 4)
            .contentShape(RoundedRectangle(cornerRadius: radius + 2, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
        .onHover { hover = $0 }
        .animation(Motion.easeOut(), value: hover)
        .help(theme.description)
        .accessibilityLabel("Player-Design \(theme.label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Ruhende Vorschau eines Designs (mit dem aktuellen Cover und – v2.1 – dem gewählten Player-Hintergrund).
struct ThemePreview: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var appColors
    let theme: PlayerTheme
    @ObservedObject var artwork: NowPlayingArtwork

    var body: some View {
        let background = model.settings.playerBackground
        let custom = model.settings.playerBackgroundCustom
        let colors = MusicColors.forPlayer(theme, app: appColors, background: background, custom: custom)
        GeometryReader { geo in
            ZStack {
                if theme == .vinylStudio && appColors.dark && background == .auto {
                    LinearGradient(colors: [Color(argb: 0xFF2B2427), Color(argb: 0xFF141112)], startPoint: .top, endPoint: .bottom)
                } else {
                    PlayerBackground(theme: theme, artwork: artwork, style: background, custom: custom)
                }
                VStack(spacing: 8) {
                    let side = max(40, min(geo.size.width - 20, geo.size.height - 50))
                    ThemePreviewHero(theme: theme, side: side, artwork: artwork)
                        .frame(width: side, height: side)
                    ZStack(alignment: .leading) {
                        Capsule().fill(colors.textPrimary.opacity(0.18))
                        Capsule().fill(colors.accent).frame(width: geo.size.width * 0.78 * 0.35)
                    }
                    .frame(width: geo.size.width * 0.78, height: 3)
                    HStack(spacing: 10) {
                        Icon(Icons.previous, size: 13, color: colors.textPrimary)
                        Icon(Icons.play, size: 18, color: colors.textPrimary)
                        Icon(Icons.next, size: 13, color: colors.textPrimary)
                    }
                }
                .padding(10)
            }
            .environment(\.musicColors, colors)
            .environment(\.colorScheme, colors.dark ? .dark : .light)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Ruhendes Mittelstück für Vorschauen.
private struct ThemePreviewHero: View {
    let theme: PlayerTheme
    let side: CGFloat
    @ObservedObject var artwork: NowPlayingArtwork

    var body: some View {
        switch theme {
        case .vinylStudio: VinylHero(side: side, artwork: artwork, still: true)
        case .classic:
            ArtworkBox(image: artwork.image, category: .unknown, cornerRadius: 8)
                .frame(width: side * 0.86, height: side * 0.86)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 4)
                .frame(width: side, height: side)
        case .cassette: CassetteHero(side: side, artwork: artwork, showStatus: false, still: true)
        case .portableCD: CDHero(side: side, artwork: artwork, still: true)
        case .modernGlass: ModernGlassHero(side: side, artwork: artwork, still: true)
        case .aurora: AuroraHero(side: side, artwork: artwork, still: true)
        case .reelToReel: ReelToReelHero(side: side, artwork: artwork, still: true)
        }
    }
}

/// Popover der Design-Schaltfläche im großen Player: alle Designs mit Vorschau, Kassettenfarbe,
/// Klangvisualisierung und Weg zu weiteren Optionen.
struct DesignQuickPicker: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    @ObservedObject var artwork: NowPlayingArtwork
    let more: () -> Void

    var body: some View {
        let current = model.settings.playerTheme
        VStack(alignment: .leading, spacing: 6) {
            GlassMenuHeader(title: "Player-Design")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(PlayerTheme.allCases, id: \.self) { theme in
                    ThemeTile(theme: theme, selected: current == theme, artwork: artwork, compact: true) {
                        withAnimation(PlayerMotionPolicy.transition(model.settings)) { model.settings.playerTheme = theme }
                    }
                }
            }
            .padding(.horizontal, 6)
            Text(current.description)
                .textStyle(Typo.bodySmall)
                .foregroundColor(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
            if current == .cassette {
                CassetteColorPicker(palette: artwork.palette, compact: true)
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
            }
            GlassMenuDivider()
            GlassMenuItem(title: "Klangvisualisierung", icon: Icons.equalizer, checked: model.settings.visualizer) {
                model.settings.visualizer.toggle()
            }
            GlassMenuItem(title: "Weitere Optionen …", icon: Icons.settings, action: more)
        }
        .animation(Motion.easeOut(), value: current)
    }
}
