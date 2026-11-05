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
        .frame(width: sheet == .equalizer ? 640 : 520)
        .frame(minHeight: 360, maxHeight: 720)
        .background(colors.backgroundGrouped)
        .foregroundColor(colors.textPrimary)
    }
}

/// Karte innerhalb der Blätter (`SheetCard`).
struct SheetCard<Content: View>: View {
    @Environment(\.musicColors) private var colors
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(colors.surface))
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

// MARK: - Equalizer (Spec 8.2)

struct EqualizerPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        let fx = model.settings.effects
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(title: "Equalizer") {
                MusicToggle(isOn: Binding(get: { fx.eqEnabled }, set: { model.settings.effects.eqEnabled = $0 }), label: "Equalizer ein/aus")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EqPresets.all) { p in
                        ChoiceChip(title: p.name, selected: fx.eqEnabled && fx.activePreset?.id == p.id) {
                            model.settings.effects = fx.withPreset(p)
                        }
                    }
                    if fx.activePreset == nil {
                        ChoiceChip(title: "Eigene Einstellung", selected: fx.eqEnabled) {}.disabled(true)
                    }
                }
                .padding(.vertical, 2)
            }
            Spacer().frame(height: 14)
            SheetCard {
                HStack {
                    Text("Bass").textStyle(Typo.titleMedium)
                    Spacer()
                    Text(fx.bassDb == 0 ? "0 dB" : Formatting.decibel(fx.bassDb))
                        .font(Typo.inter(15 * 0.875, .medium))
                        .monospacedDigit()
                        .foregroundColor(fx.bassDb != 0 ? colors.accentText : colors.textSecondary)
                    if fx.bassDb != 0 {
                        IconTap(icon: Icons.clear, label: "Bass auf 0 dB", tint: colors.textSecondary, iconSize: 16, touch: 30) { model.settings.effects = fx.withBass(0) }
                    }
                }
                MusicSlider(value: Binding(get: { Double(fx.bassDb) }, set: { v in
                    let snapped: Float = abs(v) < 0.6 ? 0 : Float((v * 2).rounded() / 2)
                    model.settings.effects = model.settings.effects.withBass(snapped)
                }), range: -12...12, marker: 0, bipolar: true, activeColor: colors.accent, label: "Bass", valueText: Formatting.decibel(fx.bassDb))
                HStack {
                    Text("weniger").textStyle(Typo.labelSmall).foregroundColor(colors.textTertiary)
                    Spacer()
                    Text("mehr").textStyle(Typo.labelSmall).foregroundColor(colors.textTertiary)
                }
                Hint(fx.bassLimited ? "Wirksam: \(Formatting.decibel(fx.effectiveBassDb)) – der Equalizer hebt die Bässe bereits an (zusammen höchstens +12 dB)." : "Tiefen unter ≈ 150 Hz · Mitten und Höhen bleiben unverändert.")
            }
            Spacer().frame(height: 12)
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
                            VerticalBandSlider(value: g, enabled: fx.eqEnabled) { v in
                                model.settings.effects = model.settings.effects.withBand(i, v)
                            }
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
            Spacer().frame(height: 12)
            SheetCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatische Aussteuerung").textStyle(Typo.bodyLarge)
                        Hint("Senkt den Pegel bei angehobenen Bändern etwas ab, damit nichts verzerrt.")
                    }
                    Spacer()
                    MusicToggle(isOn: Binding(get: { fx.autoHeadroom }, set: { model.settings.effects.autoHeadroom = $0 }), label: "Automatische Aussteuerung")
                }
            }
            Spacer().frame(height: 12)
            HStack {
                Hint("Wirkt nur auf die Musik dieser App · ±12 dB je Band.")
                Spacer()
                PillButton(title: "Zurücksetzen", style: .plain) { model.settings.effects = fx.withPreset(EqPresets.flat) }
            }
        }
    }
}

/// Senkrechter Regler eines Bands (Spec 8.2): Klick setzt (0,5-dB-Raster), Doppelklick = 0 dB.
struct VerticalBandSlider: View {
    @Environment(\.musicColors) private var colors
    let value: Float
    let enabled: Bool
    let onChange: (Float) -> Void

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
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                guard enabled else { return }
                let f = Float((bottom - min(max(g.location.y, top), bottom)) / (bottom - top))
                let db = ((f * 24 - 12) * 2).rounded() / 2
                if db != value { onChange(db) }
            })
            .simultaneousGesture(TapGesture(count: 2).onEnded { if enabled { onChange(0) } })
        }
        .accessibilityElement()
        .accessibilityLabel("Band")
        .accessibilityValue(Formatting.decibel(value))
        .accessibilityAdjustableAction { dir in
            guard enabled else { return }
            onChange(EqBands.clamp(value + (dir == .increment ? 0.5 : -0.5)))
        }
    }
}

/// Frequenzgang aus Equalizer und Bass (gleiche Formeln wie die Filter, `EqResponse`).
struct EqualizerCurve: View {
    @Environment(\.musicColors) private var colors
    let settings: AudioEffectsSettings

    var body: some View {
        Canvas { ctx, size in
            let bands = settings.effectiveBands
            let bass = Double(settings.effectiveBassDb)
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
            ctx.stroke(Path(CGRect(x: 0, y: size.height / 2, width: size.width, height: 0.5)), with: .color(colors.hairline))
            ctx.stroke(path, with: .color(colors.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Eigenes Equalizer-Fenster (⌥⌘E) – dieselbe Tafel wie im Player.
struct EqualizerWindow: View {
    @Environment(\.musicColors) private var colors

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                EqualizerPanel()
                    .padding(24)
            }
        }
        .frame(width: 640, height: 720)
    }
}

// MARK: - Tonhöhe und Tempo (Spec 8.3, ergänzt um Tempo)

struct PitchPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    @State private var drag: Double?

    var body: some View {
        let pitch = model.settings.pitch
        let shown = drag.map { Float($0) } ?? pitch.semitones
        let factor = Float(pow(2.0, Double(shown) / 12))
        let tempoText: String = pitch.tempo == 1 ? "unverändert" : Formatting.percent(pitch.tempo)
        let detail: String = pitch.mode == .key
            ? "Tonhöhe \(Formatting.factor(factor)) · Tempo \(tempoText)"
            : "Tonhöhe und Tempo \(Formatting.factor(factor)) (\(Formatting.percent(factor)))"
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(title: "Tonhöhe") {
                PillButton(title: "Original") { model.settings.pitch = PitchSettings(mode: pitch.mode) }
                    .disabled(pitch.isOriginal)
            }
            SegmentedControl(options: PitchMode.allCases, selection: Binding(get: { pitch.mode }, set: { model.settings.pitch = pitch.withMode($0) }),
                             label: { $0.label }, icon: { $0 == .key ? Icons.musicNote : Icons.vinyl })
            Hint(pitch.mode.description).padding(.top, 6)
            Spacer().frame(height: 14)
            SheetCard {
                Text(Formatting.semitones(shown))
                    .textStyle(Typo.displaySmall)
                    .foregroundColor(shown != 0 ? colors.accentText : colors.textPrimary)
                    .frame(maxWidth: .infinity)
                Text(detail)
                    .textStyle(Typo.bodyMedium)
                    .foregroundColor(colors.textSecondary)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 10) {
                    GlassIconButton(icon: "arrow_downward", label: "Einen Halbton tiefer", size: 34, iconSize: 16) {
                        model.settings.pitch = pitch.withSemitones(pitch.semitones - 1)
                    }
                    .disabled(pitch.semitones <= PitchSettings.minSemitones)
                    MusicSlider(value: Binding(get: { Double(shown) }, set: { drag = ($0 * 10).rounded() / 10 }), range: -12...12, marker: 0, bipolar: true,
                                activeColor: colors.accent, label: "Halbtöne", valueText: Formatting.semitones(shown)) { editing in
                        if !editing, let d = drag {
                            model.settings.pitch = pitch.withSemitones(Float(d))
                            drag = nil
                        }
                    }
                    GlassIconButton(icon: "arrow_upward", label: "Einen Halbton höher", size: 34, iconSize: 16) {
                        model.settings.pitch = pitch.withSemitones(pitch.semitones + 1)
                    }
                    .disabled(pitch.semitones >= PitchSettings.maxSemitones)
                }
                .padding(.top, 10)
                HStack {
                    Text("−12").frame(maxWidth: .infinity, alignment: .leading)
                    Text("0").frame(maxWidth: .infinity)
                    Text("+12").frame(maxWidth: .infinity, alignment: .trailing)
                }
                .textStyle(Typo.labelSmall)
                .foregroundColor(colors.textTertiary)
                .padding(.horizontal, 48)
            }
            if pitch.mode == .key {
                Spacer().frame(height: 12)
                SheetCard {
                    HStack {
                        Text("Tempo").textStyle(Typo.titleMedium)
                        Spacer()
                        Text(Formatting.percent(pitch.tempo)).font(Typo.inter(13, .medium)).monospacedDigit()
                            .foregroundColor(pitch.tempo != 1 ? colors.accentText : colors.textSecondary)
                    }
                    MusicSlider(value: Binding(get: { Double(pitch.tempo) }, set: { v in
                        let snapped = abs(v - 1) < 0.03 ? 1 : (v * 20).rounded() / 20
                        model.settings.pitch = pitch.withTempo(Float(snapped))
                    }), range: Double(PitchSettings.minTempo)...Double(PitchSettings.maxTempo), marker: 1, bipolar: true, activeColor: colors.accent,
                                label: "Tempo", valueText: Formatting.percent(pitch.tempo))
                    Hint(PitchSettings.tempoDescription + " · 50 % bis 200 %")
                }
            } else {
                Spacer().frame(height: 14)
                Text("Plattenspieler-Drehzahl").textStyle(Typo.titleSmall)
                HStack(spacing: 8) {
                    ChoiceChip(title: "33⅓ → 45 U/min", selected: abs(pitch.semitones - PitchSettings.rpm33To45) < 0.06) {
                        model.settings.pitch = pitch.withSemitones((PitchSettings.rpm33To45 * 10).rounded() / 10)
                    }
                    ChoiceChip(title: "45 → 33⅓ U/min", selected: abs(pitch.semitones - PitchSettings.rpm45To33) < 0.06) {
                        model.settings.pitch = pitch.withSemitones((PitchSettings.rpm45To33 * 10).rounded() / 10)
                    }
                }
                .padding(.top, 8)
            }
            Spacer().frame(height: 14)
            Hint(pitch.mode == .key
                 ? "Tonhöhe und Tempo werden getrennt verändert (Zeitstreckung von macOS). Bei starken Änderungen sind leichte Klangveränderungen möglich. Änderungen sind sofort hörbar; der Titel startet nicht neu."
                 : "Wie eine Schallplatte mit anderer Drehzahl: Tonhöhe und Tempo ändern sich gemeinsam (reines Resampling). Plattenteller, Naben und CD drehen entsprechend schneller oder langsamer.")
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
                        Text(Formatting.countdown(player.sleepRemainingMs ?? 0))
                            .textStyle(Typo.displayMedium)
                            .monospacedDigit()
                            .foregroundColor(colors.accentText)
                            .frame(maxWidth: .infinity)
                        Hint("Danach wird die Musik sanft ausgeblendet und angehalten.")
                        HStack(spacing: 10) {
                            PillButton(title: "+15 Minuten", icon: Icons.add) {
                                let rest = Int(((player.sleepRemainingMs ?? 0) + 59_999) / 60_000)
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

// MARK: - Player-Design (Spec 8.7)

struct DesignPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Player-Design").textStyle(Typo.headlineSmall)
            Hint("Gleiche Bedienung in allen Designs – der Wechsel unterbricht die Wiedergabe nicht.").padding(.top, 4)
            Spacer().frame(height: 14)
            PlayerThemePicker()
            Spacer().frame(height: 14)
            SheetCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Klangvisualisierung").textStyle(Typo.bodyLarge)
                        Hint("Dezente Frequenzbalken bzw. Pegelanzeigen. Nur aktiv, solange der Player sichtbar ist; aus bei „Bewegung reduzieren“.")
                    }
                    Spacer()
                    MusicToggle(isOn: Binding(get: { model.settings.visualizer }, set: { model.settings.visualizer = $0 }), label: "Klangvisualisierung")
                }
            }
        }
    }
}

/// Auswahl der vier Designs mit ruhenden Vorschauen (auch in den Einstellungen).
struct PlayerThemePicker: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var appColors
    @StateObject private var artwork = NowPlayingArtwork()
    var columns = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
                ForEach(PlayerTheme.allCases, id: \.self) { theme in
                    let selected = model.settings.playerTheme == theme
                    Button {
                        model.settings.playerTheme = theme
                    } label: {
                        VStack(spacing: 8) {
                            ThemePreview(theme: theme, artwork: artwork)
                                .aspectRatio(0.8, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? appColors.accent : appColors.hairline, lineWidth: selected ? 2.5 : 1))
                            HStack(spacing: 3) {
                                if selected { Icon(Icons.check, size: 15, color: appColors.accentText) }
                                Text(theme.label)
                                    .font(Typo.inter(Typo.labelLarge.size, selected ? .semibold : .medium))
                                    .foregroundColor(selected ? appColors.accentText : appColors.textPrimary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(4)
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.97))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Text(model.settings.playerTheme.description).textStyle(Typo.bodySmall).foregroundColor(appColors.textSecondary)
        }
        .task(id: player.current?.coverKey) { await artwork.update(for: player.current) }
    }
}

/// Ruhende Vorschau eines Designs.
struct ThemePreview: View {
    @Environment(\.musicColors) private var appColors
    let theme: PlayerTheme
    @ObservedObject var artwork: NowPlayingArtwork

    var body: some View {
        let colors = MusicColors.forPlayer(theme, app: appColors)
        GeometryReader { geo in
            ZStack {
                if theme == .vinylStudio && appColors.dark {
                    LinearGradient(colors: [Color(argb: 0xFF2B2427), Color(argb: 0xFF141112)], startPoint: .top, endPoint: .bottom)
                } else {
                    PlayerBackground(theme: theme, artwork: artwork)
                }
                VStack(spacing: 8) {
                    let side = max(40, min(geo.size.width - 20, geo.size.height - 50))
                    Group {
                        switch theme {
                        case .vinylStudio: VinylHero(side: side, artwork: artwork, still: true)
                        case .classic:
                            ArtworkBox(image: artwork.image, category: .unknown, cornerRadius: 8)
                                .frame(width: side * 0.86, height: side * 0.86)
                                .shadow(color: .black.opacity(0.3), radius: 6, y: 4)
                                .frame(width: side, height: side)
                        case .cassette: CassetteHero(side: side, artwork: artwork, showStatus: false, still: true)
                        case .portableCD: CDHero(side: side, artwork: artwork, still: true)
                        }
                    }
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
        }
        .allowsHitTesting(false)
    }
}
