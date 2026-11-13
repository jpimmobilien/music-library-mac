import SwiftUI
import MLCore
import MLStudio

// „Titel bearbeiten“ (2.3): Werkzeuge im Studio-Modus „Bearbeiten“ – Vorhören (Original/Bearbeitet),
// Lautstärke & Verbesserung, Tempo & Tonhöhe, Stimmung, Auto-Tune, Equalizer. Beschneiden übernimmt die
// Wellenform-Karte darüber, Speichern die Exportleiste (Original ersetzen mit Sicherung oder neue Datei).

struct TrackEditTools: View {
    @ObservedObject var studio: StudioModel
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TrackEditPreviewRow(studio: studio)
            if width >= 900 {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        TrackEditLevelCard(studio: studio)
                        TrackEditTempoCard(studio: studio)
                    }
                    .frame(maxWidth: .infinity)
                    VStack(spacing: 16) {
                        TrackEditTuningCard(studio: studio)
                        TrackEditAutoTuneCard(studio: studio)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                TrackEditLevelCard(studio: studio)
                TrackEditTempoCard(studio: studio)
                TrackEditTuningCard(studio: studio)
                TrackEditAutoTuneCard(studio: studio)
            }
            TrackEditEqualizerCard(studio: studio, compact: width < 640)
        }
    }
}

// MARK: - Zahlen

enum EditText {
    static func number(_ v: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", v).replacingOccurrences(of: ".", with: ",")
    }

    static func signed(_ v: Double, digits: Int = 1) -> String {
        if abs(v) < pow(10, Double(-digits)) / 2 { return number(0, digits: digits) }
        return (v > 0 ? "+" : "−") + number(abs(v), digits: digits)
    }

    static func db(_ v: Double) -> String { signed(v) + " dB" }
    static func speed(_ v: Double) -> String { number(v, digits: 2) + "×" }
    static func hz(_ v: Double) -> String { number(v, digits: 1) + " Hz" }

    static func semitones(_ n: Int) -> String {
        n == 0 ? "Original" : "\(n > 0 ? "+" : "−")\(abs(n)) Halbt\(abs(n) == 1 ? "on" : "öne")"
    }
}

// MARK: - Vorhören

/// Original/Bearbeitet umschalten, Zusammenfassung, alles zurücksetzen.
struct TrackEditPreviewRow: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        let edit = studio.trackEdit
        HStack(spacing: 12) {
            SegmentedControl(options: [false, true], selection: $studio.previewEdited,
                             label: { $0 ? "Bearbeitet" : "Original" },
                             icon: { $0 ? Icons.tune : Icons.musicNote }, height: 32)
                .frame(width: 250)
                .help("Beim Vorhören (Leertaste) zwischen Original und bearbeiteter Fassung wechseln")
            VStack(alignment: .leading, spacing: 1) {
                Text(edit.isNeutral ? "Noch keine Klangänderungen" : edit.summary)
                    .textStyle(Typo.labelLarge)
                    .foregroundColor(edit.isNeutral ? colors.textSecondary : colors.textPrimary)
                    .lineLimit(2)
                Text(lengthText)
                    .textStyle(Typo.labelSmall)
                    .monospacedDigit()
                    .foregroundColor(colors.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            PillButton(title: "Zurücksetzen", icon: Icons.restart) { studio.resetTrackEdit() }
                .disabled(edit.isNeutral && !edit.autoTune && !edit.enhance)
                .help("Alle Klangänderungen zurücknehmen")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.card + 4, style: .continuous))
    }

    private var lengthText: String {
        let before = studio.effectiveTrim?.length ?? studio.duration
        let after = studio.editedDuration
        if abs(after - before) < 0.05 { return "Länge \(StudioTime.format(after, millis: false))" }
        return "Länge \(StudioTime.format(after, millis: false)) statt \(StudioTime.format(before, millis: false))"
    }
}

// MARK: - Bausteine

/// Zeile: Beschriftung links, Wert rechts, darunter ein Regler.
struct EditSliderRow: View {
    @Environment(\.musicColors) private var colors
    let title: String
    let value: String
    @Binding var amount: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var marker: Double? = nil
    var bipolar = false
    var reset: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .textStyle(Typo.labelLarge)
                    .foregroundColor(colors.textPrimary)
                Spacer(minLength: 6)
                Text(value)
                    .font(Typo.inter(13, .semibold))
                    .monospacedDigit()
                    .foregroundColor(colors.accentText)
                if let reset {
                    Button { amount = reset } label: { Icon(Icons.restart, size: 14, color: colors.textTertiary) }
                        .buttonStyle(.plain)
                        .opacity(abs(amount - reset) > 1e-9 ? 1 : 0)
                        .help("Zurücksetzen")
                        .accessibilityLabel("\(title) zurücksetzen")
                }
            }
            MusicSlider(value: $amount, range: range, marker: marker, bipolar: bipolar, activeColor: colors.accent,
                        showsKnob: true, step: step, label: title, valueText: value)
        }
    }
}

/// Ein-/Aus-Zeile mit Erklärung.
struct EditToggleRow: View {
    @Environment(\.musicColors) private var colors
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .textStyle(Typo.labelLarge)
                    .foregroundColor(colors.textPrimary)
                if let detail {
                    Text(detail)
                        .textStyle(Typo.bodySmall)
                        .foregroundColor(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            MusicToggle(isOn: $isOn, label: title)
                .controlSize(.small)
        }
    }
}

/// Hinweiszeile (Symbol + Text).
struct EditHint: View {
    @Environment(\.musicColors) private var colors
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Icon(icon, size: 14, color: colors.textTertiary)
                .padding(.top, 1)
            Text(text)
                .textStyle(Typo.bodySmall)
                .foregroundColor(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Lautstärke & Verbesserung

struct TrackEditLevelCard: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        let e = studio.trackEdit
        StudioCard(icon: Icons.volumeUp, title: "Lautstärke & Verbesserung", subtitle: analysisLine) {
            VStack(alignment: .leading, spacing: 14) {
                EditSliderRow(title: "Lautstärke", value: e.enhance && e.normalize ? "automatisch" : EditText.db(e.gainDb),
                              amount: $studio.trackEdit.gainDb, range: TrackEdit.gainRange, step: 0.5, marker: 0, bipolar: true, reset: 0)
                    .disabled(e.enhance && e.normalize)
                Hairline()
                EditToggleRow(title: "Automatisch verbessern",
                              detail: "Lautheit angleichen, Rumpeln entfernen, Übersteuerung verhindern, Stille kürzen. Verlorene Qualität (z. B. einer schwachen MP3) lässt sich damit nicht zurückholen.",
                              isOn: $studio.trackEdit.enhance)
                if e.enhance {
                    VStack(alignment: .leading, spacing: 12) {
                        EditToggleRow(title: "Lautheit angleichen", detail: loudnessDetail, isOn: $studio.trackEdit.normalize)
                        if e.normalize {
                            HStack(spacing: 6) {
                                ForEach(TrackEdit.loudnessTargets, id: \.self) { t in
                                    ChoiceChip(title: targetLabel(t), selected: abs(e.targetLoudness - t) < 0.01) { studio.trackEdit.targetLoudness = t }
                                }
                            }
                        }
                        EditToggleRow(title: "Rumpeln entfernen", detail: "Trittschall, Brummen und Gleichanteil unter 25 Hz.", isOn: $studio.trackEdit.removeRumble)
                        EditToggleRow(title: "Übersteuerung verhindern", detail: "Spitzen werden weich auf −1 dB begrenzt.", isOn: $studio.trackEdit.preventClipping)
                        EditToggleRow(title: "Stille am Anfang und Ende entfernen", detail: silenceDetail, isOn: $studio.trackEdit.trimSilence)
                    }
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) { Rectangle().fill(colors.accent.opacity(0.35)).frame(width: 2) }
                    .transition(.opacity)
                }
            }
            .animation(Motion.easeOut(Motion.short), value: e.enhance)
        }
    }

    private func targetLabel(_ t: Double) -> String {
        switch t {
        case -23: return "−23 LUFS · Rundfunk"
        case -16: return "−16 · leise"
        case -14: return "−14 · Streaming"
        case -11: return "−11 · laut"
        default: return "\(Int(t)) LUFS"
        }
    }

    private var analysisLine: String {
        if let p = studio.trackAnalysisProgress { return "Titel wird analysiert … \(Int(p * 100)) %" }
        guard let a = studio.trackAnalysis, let l = a.loudness else { return "Lautheit wird nach dem Laden gemessen" }
        var parts = ["Original \(EditText.number(l)) LUFS"]
        if let p = a.peakDb { parts.append("Spitze \(EditText.db(p))") }
        return parts.joined(separator: " · ")
    }

    private var loudnessDetail: String {
        let e = studio.trackEdit
        guard let l = studio.trackAnalysis?.loudness else { return "Auf eine einheitliche Lautheit (EBU R 128) – gemessen nach allen anderen Änderungen." }
        let g = e.normalizationGain(measured: l)
        return "Etwa \(EditText.db(g)) bis \(Int(e.targetLoudness)) LUFS (genau gemessen beim Speichern, nach allen anderen Änderungen)."
    }

    private var silenceDetail: String {
        guard let a = studio.trackAnalysis else { return "Unter −60 dB; kurze Ränder bleiben stehen." }
        if a.leadingSilence < 0.05 && a.trailingSilence < 0.05 { return "Keine nennenswerte Stille gefunden." }
        return "Anfang \(EditText.number(a.leadingSilence)) s, Ende \(EditText.number(a.trailingSilence)) s (unter −60 dB)."
    }
}

// MARK: - Tempo & Tonhöhe

struct TrackEditTempoCard: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        let e = studio.trackEdit
        StudioCard(icon: Icons.speed, title: "Tempo & Tonhöhe", subtitle: subtitle) {
            VStack(alignment: .leading, spacing: 14) {
                EditSliderRow(title: "Tempo", value: EditText.speed(e.speed), amount: $studio.trackEdit.speed,
                              range: TrackEdit.speedRange, step: 0.01, marker: 1, bipolar: true, reset: 1)
                HStack(spacing: 6) {
                    ForEach([0.75, 0.9, 1.0, 1.1, 1.25, 1.5], id: \.self) { v in
                        ChoiceChip(title: EditText.speed(v), selected: abs(e.speed - v) < 0.001) { studio.trackEdit.speed = v }
                    }
                }
                EditToggleRow(title: "Tonhöhe beibehalten",
                              detail: e.keepPitch ? "Nur das Tempo ändert sich (Zeitdehnung in hoher Qualität)."
                                                  : "Wie eine Schallplatte: schneller klingt höher, langsamer tiefer.",
                              isOn: $studio.trackEdit.keepPitch)
                Hairline()
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Tonhöhe")
                            .textStyle(Typo.labelLarge)
                            .foregroundColor(colors.textPrimary)
                        Spacer()
                        Text(EditText.semitones(e.semitones))
                            .font(Typo.inter(13, .semibold))
                            .monospacedDigit()
                            .foregroundColor(colors.accentText)
                    }
                    HStack(spacing: 8) {
                        GlassIconButton(icon: Icons.remove, label: "Einen Halbton tiefer", size: 30, iconSize: 15) { step(-1) }
                            .disabled(e.semitones <= TrackEdit.semitoneRange.lowerBound)
                        MusicSlider(value: semitoneBinding, range: -12...12, marker: 0, bipolar: true, activeColor: colors.accent,
                                    showsKnob: true, step: 1, label: "Tonhöhe", valueText: EditText.semitones(e.semitones))
                        GlassIconButton(icon: Icons.add, label: "Einen Halbton höher", size: 30, iconSize: 15) { step(1) }
                            .disabled(e.semitones >= TrackEdit.semitoneRange.upperBound)
                    }
                }
                EditSliderRow(title: "Feinstimmung", value: EditText.signed(e.cents, digits: 0) + " Cent", amount: $studio.trackEdit.cents,
                              range: TrackEdit.centsRange, step: 1, marker: 0, bipolar: true, reset: 0)
            }
        }
    }

    private var semitoneBinding: Binding<Double> {
        Binding(get: { Double(studio.trackEdit.semitones) }, set: { studio.trackEdit.semitones = Int($0.rounded()) })
    }

    private func step(_ d: Int) {
        studio.trackEdit.semitones = min(max(studio.trackEdit.semitones + d, -12), 12)
    }

    private var subtitle: String {
        let e = studio.trackEdit
        if e.isSpeedNeutral && e.isPitchNeutral { return "Unverändert" }
        var parts: [String] = []
        if !e.isSpeedNeutral { parts.append(EditText.speed(e.speed)) }
        if !e.isPitchNeutral || (!e.keepPitch && !e.isSpeedNeutral) {
            let cents = 1200 * log2(e.pitchFactor / (e.isTuningNeutral ? 1 : e.tuningTo / e.tuningFrom))
            parts.append(EditText.signed(cents / 100, digits: 2) + " Halbtöne")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Stimmung

struct TrackEditTuningCard: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    static let targets: [Double] = [432, 440, 442, 444]

    var body: some View {
        let e = studio.trackEdit
        StudioCard(icon: Icons.tune, title: "Stimmung (Kammerton)", subtitle: detected) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    field(title: "Steht auf", value: e.tuningFrom, minus: { studio.setTuningSource(e.tuningFrom - 0.1) },
                          plus: { studio.setTuningSource(e.tuningFrom + 0.1) })
                    Icon(Icons.chevronRight, size: 16, color: colors.textTertiary)
                    field(title: "Umstimmen auf", value: e.tuningTo, minus: { studio.setTuningTarget(e.tuningTo - 0.5) },
                          plus: { studio.setTuningTarget(e.tuningTo + 0.5) })
                }
                HStack(spacing: 6) {
                    ChoiceChip(title: "Unverändert", selected: e.isTuningNeutral) { studio.setTuningTarget(e.tuningFrom) }
                    ForEach(Self.targets, id: \.self) { t in
                        ChoiceChip(title: "\(Int(t)) Hz", selected: abs(e.tuningTo - t) < 0.01 && !e.isTuningNeutral) { studio.setTuningTarget(t) }
                    }
                }
                EditHint(icon: Icons.info, text: resultText)
            }
        }
    }

    private func field(title: String, value: Double, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .textStyle(Typo.labelSmall)
                .foregroundColor(colors.textSecondary)
            HStack(spacing: 4) {
                GlassIconButton(icon: Icons.remove, label: "\(title): weniger", size: 26, iconSize: 14, action: minus)
                Text(EditText.hz(value))
                    .font(Typo.inter(14, .semibold))
                    .monospacedDigit()
                    .foregroundColor(colors.textPrimary)
                    .frame(minWidth: 80)
                GlassIconButton(icon: Icons.add, label: "\(title): mehr", size: 26, iconSize: 14, action: plus)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detected: String {
        if studio.trackAnalysisProgress != nil { return "Stimmung wird erkannt …" }
        guard let a = studio.trackAnalysis else { return "Wird nach dem Laden erkannt" }
        if let text = a.referenceText { return "Erkannt: A4 \(text)" + (a.referenceConfidence < 0.5 ? " (unsicher)" : "") }
        return "Nicht eindeutig erkannt – 440 Hz angenommen"
    }

    private var resultText: String {
        let e = studio.trackEdit
        if e.isTuningNeutral {
            return "432 Hz ist eine beliebte alternative Stimmung (≈ ein Drittel Halbton tiefer als 440 Hz). Tempo und Länge bleiben gleich."
        }
        let cents = MusicMath.cents(e.tuningTo, relativeTo: e.tuningFrom)
        return "Alles wird um \(EditText.signed(cents, digits: 1)) Cent verschoben – Tempo und Länge bleiben gleich."
    }
}

// MARK: - Auto-Tune

struct TrackEditAutoTuneCard: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        let e = studio.trackEdit
        StudioCard(icon: Icons.pitch, title: "Auto-Tune", subtitle: e.autoTune ? TrackEdit.keyName(e.autoTuneKey, e.autoTuneScale) : "Aus") {
            MusicToggle(isOn: $studio.trackEdit.autoTune, label: "Auto-Tune")
                .controlSize(.small)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                EditHint(icon: Icons.info,
                         text: "Zieht Gesang auf die Töne der Tonart. Am besten bei Einzelstimmen (A cappella, Sprachaufnahmen). In fertig gemischten Songs lässt sich die Stimme nicht von den Instrumenten trennen – dort wirkt es eher als Effekt.")
                if e.autoTune {
                    HStack(spacing: 10) {
                        keyMenu
                        if let k = studio.trackAnalysis?.keyText {
                            PillButton(title: "Erkannt: \(k)", icon: Icons.autoAwesome) { studio.applyDetectedKey() }
                                .help("Erkannte Tonart übernehmen")
                        }
                        Spacer(minLength: 0)
                    }
                    EditSliderRow(title: "Stärke", value: strengthText(e.autoTuneStrength), amount: $studio.trackEdit.autoTuneStrength,
                                  range: 0...1, step: 0.05)
                    HStack {
                        Text("Natürlich").textStyle(Typo.labelSmall).foregroundColor(colors.textTertiary)
                        Spacer()
                        Text("Roboter").textStyle(Typo.labelSmall).foregroundColor(colors.textTertiary)
                    }
                    .padding(.top, -10)
                }
            }
            .animation(Motion.easeOut(Motion.short), value: e.autoTune)
        }
    }

    private func strengthText(_ v: Double) -> String { "\(Int((v * 100).rounded())) %" }

    private var keyMenu: some View {
        let e = studio.trackEdit
        return GlassMenuButton(help: "Tonart wählen", width: 260) {
            HStack(spacing: 7) {
                Icon(Icons.musicNote, size: 15, color: colors.accentText)
                Text(TrackEdit.keyName(e.autoTuneKey, e.autoTuneScale))
                    .font(Typo.inter(13, .medium))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                Icon(Icons.unfoldMore, size: 14, color: colors.textTertiary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .glassSurface(Capsule(), strong: true, interactive: true)
        } content: { menu in
            ScrollView {
                VStack(spacing: 0) {
                    GlassMenuItem(title: "Chromatisch (alle Halbtöne)", checked: e.autoTuneScale == .chromatic) {
                        studio.setAutoTuneKey(e.autoTuneKey, scale: .chromatic)
                        menu.close()
                    }
                    GlassMenuDivider()
                    ForEach([MusicScale.major, .minor], id: \.self) { scale in
                        GlassMenuHeader(title: scale == .major ? "Dur" : "Moll")
                        ForEach(0..<12, id: \.self) { k in
                            GlassMenuItem(title: TrackEdit.keyName(k, scale), checked: e.autoTuneScale == scale && e.autoTuneKey == k) {
                                studio.setAutoTuneKey(k, scale: scale)
                                menu.close()
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
        }
    }
}

// MARK: - Equalizer

struct TrackEditEqualizerCard: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    let compact: Bool

    var body: some View {
        let e = studio.trackEdit
        let fx = AudioEffectsSettings(eqEnabled: true, bandGains: e.bandGains, volume: 1, autoHeadroom: false, bassDb: e.bassDb)
        StudioCard(icon: Icons.equalizer, title: "Equalizer", subtitle: presetName) {
            if studio.playerEqualizerAvailable {
                PillButton(title: "Wie im Player", icon: Icons.equalizerBars) { studio.copyPlayerEqualizer() }
                    .help("Equalizer und Bass des Players übernehmen")
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(EqPresets.all) { p in
                            ChoiceChip(title: p.name, selected: e.bandGains == p.gains && (p.id != "flat" || e.bassDb == 0)) {
                                studio.applyEqualizer(gains: p.gains, bassDb: p.id == "flat" ? 0 : nil)
                            }
                        }
                        ForEach(studio.eqUserPresets) { p in
                            ChoiceChip(title: p.name, selected: e.bandGains == p.gains) {
                                studio.applyEqualizer(gains: p.gains, bassDb: p.bassDb)
                            }
                        }
                    }
                }
                EqualizerCurve(settings: fx)
                    .frame(height: 46)
                HStack(alignment: .bottom, spacing: compact ? 2 : 8) {
                    ForEach(0..<EqBands.count, id: \.self) { i in
                        VStack(spacing: 4) {
                            VerticalBandSlider(value: e.bandGains[i], enabled: true, label: "\(EqBands.labels[i]) Hz",
                                               onChange: { v in studio.trackEdit.bandGains[i] = v })
                                .frame(height: compact ? 120 : 140)
                            Text(EqBands.labels[i])
                                .textStyle(Typo.labelSmall)
                                .foregroundColor(colors.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                EditSliderRow(title: "Bass", value: EditText.db(Double(e.bassDb)), amount: bassBinding,
                              range: Double(AudioEffectsSettings.minBassDb)...Double(AudioEffectsSettings.maxBassDb), step: 0.5, marker: 0, bipolar: true, reset: 0)
            }
        }
    }

    private var bassBinding: Binding<Double> {
        Binding(get: { Double(studio.trackEdit.bassDb) }, set: { studio.trackEdit.bassDb = Float($0) })
    }

    private var presetName: String {
        let e = studio.trackEdit
        if e.isEqNeutral { return "Neutral" }
        if let p = EqPresets.matching(e.bandGains) { return p.name + (e.bassDb != 0 ? " · Bass \(EditText.db(Double(e.bassDb)))" : "") }
        if let u = studio.eqUserPresets.first(where: { $0.gains == e.bandGains }) { return u.name }
        return "Eigene Einstellung"
    }
}
