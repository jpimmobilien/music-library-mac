import SwiftUI
import AppKit
import MLCore
import MLStudio

// KI-Musik – Hauptansicht: Einrichtung (falls nötig), große Prompt-Eingabe („Create your own sound.“),
// Einstellungen, Erzeugung mit Fortschritt, Ergebnisse und „Meine KI-Kreationen“.

struct KIMusicView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @ObservedObject var ki: KIMusicModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        GeometryReader { geo in
            let bottom = Chrome.contentBottom(miniPlayer: player.current != nil)
            ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    Color.clear.frame(height: 0).id("ki-top")
                    KIHeader(ki: ki)
                    switch ki.setup {
                    case .unsupported(let reason):
                        KIUnsupportedCard(reason: reason)
                    case .needsEnvironment, .needsModels:
                        KISetupCard(ki: ki)
                    case .ready:
                        // Laufende Erzeugung, Fehler und Ergebnisse stehen oben – dort, wo der Blick nach dem Klick ist
                        if ki.isWorking { KIProgressCard(ki: ki).transition(.opacity) }
                        if case .failed(let message) = ki.phase {
                            StudioNotice(icon: Icons.warning, title: "Erzeugen fehlgeschlagen", text: message, tint: colors.danger) {
                                PillButton(title: "Protokoll zeigen", style: .plain) { ki.revealLog() }
                                PillButton(title: "Schließen", style: .plain) { ki.dismissError() }
                            }
                        }
                        if !ki.results.isEmpty && !ki.isWorking { KIResultsCard(ki: ki) }
                        KIPromptCard(ki: ki, width: geo.size.width)
                    }
                    if !ki.creations.items.isEmpty || ki.setup == .ready {
                        KICreationsSection(ki: ki)
                    }
                }
                .padding(.top, Chrome.contentTop + 2)
                .padding(.bottom, bottom + 16)
                .padding(.horizontal, Spacing.gutter)
                .frame(maxWidth: 1240)
                .frame(maxWidth: .infinity)
                .animation(Motion.easeOut(Motion.medium), value: ki.isWorking)
                .animation(Motion.easeOut(Motion.medium), value: ki.results.map(\.id))
            }
            .onChange(of: ki.isWorking) { working in
                if working { withAnimation(Motion.easeOut()) { proxy.scrollTo("ki-top", anchor: .top) } }
            }
            }
        }
        .overlay(alignment: .top) {
            WindowDragArea()
                .frame(height: Chrome.topPadding + Metrics.navBarHeight)
                .frame(maxWidth: .infinity)
        }
        .onAppear { ki.refreshSetup() }
        .onDisappear { ki.stopPlayback() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("KI-Musik")
    }
}

// MARK: - Kopf

private struct KIHeader: View {
    @ObservedObject var ki: KIMusicModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("KI-Musik")
                    .textStyle(Typo.headlineLarge)
                    .foregroundColor(colors.textPrimary)
                Text("Musik aus einer Beschreibung erzeugen – vollständig auf deinem Mac, ohne Cloud und ohne Kosten.")
                    .textStyle(Typo.bodyMedium)
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            HStack(spacing: 7) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(statusText)
                    .font(Typo.inter(12, .semibold))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .glassSurface(Capsule(), strong: true)
            .help("Läuft lokal mit ACE-Step 1.5")
        }
        .padding(.horizontal, 4)
    }

    private var statusText: String {
        switch ki.setup {
        case .unsupported: return "Nicht verfügbar"
        case .needsEnvironment, .needsModels: return ki.installing ? "Wird eingerichtet" : "Einrichtung nötig"
        case .ready: return ki.isWorking ? "Erzeugt …" : "Bereit · lokal"
        }
    }

    private var statusColor: Color {
        switch ki.setup {
        case .ready: return ki.isWorking ? colors.accent : Color(argb: 0xFF34C759)
        case .unsupported: return colors.danger
        default: return Color(argb: 0xFFFF9F0A)
        }
    }
}

// MARK: - Nicht verfügbar / Einrichtung

private struct KIUnsupportedCard: View {
    let reason: String
    var body: some View {
        StudioNotice(icon: Icons.info, title: "Auf diesem Mac nicht verfügbar", text: reason) { EmptyView() }
    }
}

private struct KISetupCard: View {
    @ObservedObject var ki: KIMusicModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(colors: [colors.accent.opacity(0.9), colors.accentStrong], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 64, height: 64)
                    Icon(Icons.autoAwesome, size: 32, color: .white)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("KI-Musik einrichten")
                        .textStyle(Typo.headlineSmall)
                        .foregroundColor(colors.textPrimary)
                    Text("Einmalig werden die Rechenumgebung (Python mit ACE-Step 1.5, ca. 1,2 GB) und das Grundpaket der Modelle (ca. 10,4 GB) geladen. Danach erzeugt der Mac Musik ohne Internet, ohne Konto und ohne Kosten.")
                        .textStyle(Typo.bodyMedium)
                        .foregroundColor(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                point(Icons.shield, "Quellen: Python-Pakete von PyPI, uv von Astral (geprüfte Prüfsumme), ACE-Step von GitHub, Modelle von Hugging Face – nur auf Knopfdruck.")
                point(Icons.lock, "Beschreibungen, Texte und deine Musik verlassen den Mac nicht.")
                point(Icons.info, "Lizenz: ACE-Step 1.5 – Quelltext und Modelle MIT; erzeugte Musik darf laut den Entwicklern auch kommerziell genutzt werden.")
                if let free = ki.freeSpace {
                    point("hard_drive", "Frei auf dem Laufwerk: \(KIFormat.bytes(free)) – gebraucht werden etwa 13 GB.")
                }
            }
            switch ki.installTask {
            case .running(let title, let p):
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(title).textStyle(Typo.titleSmall).foregroundColor(colors.textPrimary)
                        Spacer()
                        PillButton(title: "Abbrechen", style: .plain) { ki.cancelInstall() }
                    }
                    if let f = p.fraction {
                        ProgressView(value: f).tint(colors.accent)
                    } else {
                        ProgressView().progressViewStyle(.linear).tint(colors.accent)
                    }
                    Text(p.step)
                        .textStyle(Typo.bodySmall)
                        .foregroundColor(colors.textSecondary)
                        .lineLimit(2)
                }
            case .failed(let message):
                StudioNotice(icon: Icons.warning, title: "Einrichtung unterbrochen", text: message, tint: colors.danger) {
                    PillButton(title: "Erneut versuchen", icon: Icons.refresh, style: .filled) { ki.installEverything() }
                    PillButton(title: "Protokoll", style: .plain) { ki.revealLog() }
                }
            case .idle:
                HStack(spacing: 10) {
                    PillButton(title: ki.setup == .needsModels ? "Modelle laden (ca. 10,4 GB)" : "Jetzt einrichten (ca. 12 GB)",
                               icon: Icons.download, style: .filled) { ki.installEverything() }
                    Text("Ein Abbruch ist jederzeit möglich; ein neuer Versuch setzt fort.")
                        .textStyle(Typo.bodySmall)
                        .foregroundColor(colors.textTertiary)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous), strong: true)
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Icon(icon, size: 15, color: colors.accentText).padding(.top, 1)
            Text(text)
                .textStyle(Typo.bodySmall)
                .foregroundColor(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Prompt und Einstellungen

private struct KIPromptCard: View {
    @ObservedObject var ki: KIMusicModel
    @Environment(\.musicColors) private var colors
    let width: CGFloat
    @State private var advanced = false

    static let templates: [(String, String)] = [
        ("Synthwave", "Melancholischer Synthwave im Stil der 1980er-Jahre: warme analoge Synthesizer, tiefer Bass, atmosphärische Flächen, kraftvolle elektronische Drums und eine emotionale Melodie. Keine Vocals."),
        ("Deutscher Pop", "Emotionaler deutscher Popsong über eine verlorene Liebe. Warme männliche Stimme, Klavier, Streicher und ein großer Refrain. Moderne, hochwertige Popproduktion."),
        ("Lo-Fi", "Entspannter Lo-Fi-Hip-Hop mit warmen Klavierakkorden, leisem Vinylknistern und lässigem Schlagzeug. Zum Lernen und Arbeiten."),
        ("Akustik", "Ruhige Akustikgitarre und sanfter Gesang, Folk, intim und warm aufgenommen."),
        ("Orchester", "Epische Filmmusik mit großem Orchester, Chor, Pauken und steigender Spannung."),
        ("House", "Treibender Deep House mit 122 BPM, warme Bassline, Off-Beat-Hi-Hats und luftige Vocal-Chops."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Create your own sound.")
                    .font(Typo.inter(34, .bold))
                    .tracking(-0.8)
                    .foregroundStyle(LinearGradient(colors: [colors.textPrimary, colors.accentText], startPoint: .leading, endPoint: .trailing))
                Text("Beschreibe Stil, Stimmung, Instrumente, Gesang und Länge – so frei wie im Gespräch.")
                    .textStyle(Typo.bodyMedium)
                    .foregroundColor(colors.textSecondary)
            }
            ZStack(alignment: .topLeading) {
                if ki.request.prompt.isEmpty {
                    Text("z. B. „Ein sommerlicher deutscher Popsong mit Gitarre, fröhlicher Frauenstimme und eingängigem Refrain“")
                        .textStyle(Typo.bodyLarge)
                        .foregroundColor(colors.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $ki.request.prompt)
                    .font(Typo.inter(15, .regular))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 96, maxHeight: 180)
                    .accessibilityLabel("Beschreibung der Musik")
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(colors.fieldFill))
            StudioFlow(spacing: 8) {
                ForEach(Self.templates, id: \.0) { t in
                    Button { ki.usePrompt(t.1) } label: {
                        Text(t.0)
                            .textStyle(Typo.labelMedium)
                            .foregroundColor(colors.textPrimary)
                            .padding(.horizontal, 11)
                            .frame(height: 28)
                            .glassSurface(Capsule(), interactive: true)
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.96))
                    .help(t.1)
                }
                if !ki.history.isEmpty { historyMenu }
            }
            Hairline()
            vocals
            HStack(alignment: .top, spacing: 16) {
                durationPicker.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    label("Varianten")
                    Stepper(value: $ki.request.variations, in: 1...KIGenerationRequest.maxVariations) {
                        Text("\(ki.request.variations)").font(Typo.inter(13, .semibold)).monospacedDigit()
                    }
                    .fixedSize()
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                label("Qualität")
                SegmentedControl(options: KIQuality.allCases, selection: $ki.request.quality, label: { $0.label }, height: 30)
                    .frame(maxWidth: 420)
                Text(ki.request.quality.detail + (ki.request.quality == .high && !ki.isInstalled(.xlTurbo) ? " – noch nicht geladen" : ""))
                    .textStyle(Typo.bodySmall)
                    .foregroundColor(colors.textTertiary)
            }
            DisclosureGroup(isExpanded: $advanced) { advancedOptions.padding(.top, 8) } label: {
                Text("Erweitert: Tempo, Tonart, Taktart, Startwert").textStyle(Typo.labelLarge).foregroundColor(colors.textSecondary)
            }
            HStack(spacing: 12) {
                PillButton(title: "Musik erzeugen", icon: Icons.autoAwesome, style: .filled, minWidth: 180) { ki.generate() }
                    .disabled(ki.blocker != nil || ki.isWorking)
                    .keyboardShortcut(.return, modifiers: .command)
                Text(ki.blocker ?? "Dauer \(KIEstimate.text(ki.estimate)) (Schätzung)")
                    .textStyle(Typo.bodySmall)
                    .foregroundColor(ki.blocker == nil ? colors.textSecondary : colors.danger)
                    .lineLimit(2)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous), strong: true)
    }

    private func label(_ t: String) -> some View {
        Text(t.uppercased()).font(Typo.inter(10.5, .semibold)).tracking(0.6).foregroundColor(colors.textTertiary)
    }

    private var historyMenu: some View {
        GlassMenuButton(help: "Frühere Beschreibungen", width: 380) {
            HStack(spacing: 6) {
                Icon(Icons.history, size: 14, color: colors.textSecondary)
                Text("Verlauf").textStyle(Typo.labelMedium).foregroundColor(colors.textSecondary)
            }
            .padding(.horizontal, 11)
            .frame(height: 28)
            .glassSurface(Capsule(), interactive: true)
        } content: { menu in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(ki.history.prefix(20), id: \.self) { p in
                        GlassMenuItem(title: String(p.prefix(70)) + (p.count > 70 ? " …" : "")) {
                            ki.usePrompt(p)
                            menu.close()
                        }
                    }
                    GlassMenuDivider()
                    GlassMenuItem(title: "Verlauf leeren", icon: Icons.delete) {
                        ki.clearHistory()
                        menu.close()
                    }
                }
            }
            .frame(maxHeight: 360)
        }
    }

    @ViewBuilder private var vocals: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Gesang und Text")
            SegmentedControl(options: KILyricsMode.allCases, selection: $ki.request.lyricsMode, label: { $0.label }, height: 30)
            if !ki.request.instrumental {
                HStack(spacing: 10) {
                    Text("Sprache").textStyle(Typo.bodyMedium).foregroundColor(colors.textSecondary)
                    languageMenu
                    Text("Der Text wird in dieser Sprache gesungen – keine Übersetzung.")
                        .textStyle(Typo.bodySmall)
                        .foregroundColor(colors.textTertiary)
                }
            }
            if ki.request.lyricsMode == .own || ki.request.lyricsMode == .revise {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(["[Intro]", "[Verse]", "[Pre-Chorus]", "[Chorus]", "[Bridge]", "[Outro]"], id: \.self) { tag in
                            Button(tag) { ki.request.lyrics += (ki.request.lyrics.isEmpty || ki.request.lyrics.hasSuffix("\n") ? "" : "\n\n") + tag + "\n" }
                                .buttonStyle(.plain)
                                .font(Typo.inter(11.5, .medium))
                                .foregroundColor(colors.accentText)
                                .padding(.horizontal, 8)
                                .frame(height: 24)
                                .background(Capsule().fill(colors.accentSoft))
                        }
                    }
                    TextEditor(text: $ki.request.lyrics)
                        .font(Typo.inter(13.5, .regular))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120, maxHeight: 260)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(colors.fieldFill))
                        .accessibilityLabel("Songtext")
                }
            }
        }
    }

    private var languageMenu: some View {
        GlassMenuButton(help: "Sprache des Gesangs", width: 240) {
            HStack(spacing: 6) {
                Text(KILanguage.named(ki.request.language)?.name ?? "Sprache wählen")
                    .font(Typo.inter(13, .medium))
                    .foregroundColor(colors.textPrimary)
                Icon(Icons.unfoldMore, size: 13, color: colors.textTertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .glassSurface(Capsule(), strong: true, interactive: true)
        } content: { menu in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(KILanguage.all) { l in
                        if l.id == "ar" { GlassMenuDivider() }
                        GlassMenuItem(title: l.name, checked: l.id == ki.request.language) {
                            ki.request.language = l.id
                            menu.close()
                        }
                    }
                }
            }
            .frame(maxHeight: 380)
        }
    }

    private static let durations: [(String, Double)] = [("30 s", 30), ("1 min", 60), ("2 min", 120), ("3 min", 180),
                                                        ("4 min", 240), ("5 min", 300), ("6 min", 360)]

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Länge")
            StudioFlow(spacing: 6) {
                ForEach(Self.durations, id: \.1) { d in
                    let on = ki.request.duration == d.1
                    Button { ki.request.duration = d.1 } label: {
                        Text(d.0)
                            .font(Typo.inter(12, on ? .semibold : .medium))
                            .foregroundColor(on ? colors.accentText : colors.textPrimary)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(Capsule().fill(on ? colors.accentSoft : colors.textPrimary.opacity(0.05)))
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.96))
                }
                Stepper(value: Binding(get: { ki.request.duration ?? 120 }, set: { ki.request.duration = min(600, max(10, $0)) }),
                        in: KIGenerationRequest.minDuration...KIGenerationRequest.maxDuration, step: 10) {
                    Text(Formatting.duration(Int64((ki.request.duration ?? 120) * 1000)))
                        .font(Typo.inter(12.5, .semibold)).monospacedDigit()
                }
                .fixedSize()
                .help("Eigene Länge (10 Sekunden bis 10 Minuten – das Maximum von ACE-Step 1.5)")
            }
        }
    }

    private static let keys: [String] = ["", "C major", "G major", "D major", "A major", "E major", "F major", "Bb major", "Eb major",
                                         "A minor", "E minor", "B minor", "D minor", "G minor", "C minor", "F# minor"]

    private var advancedOptions: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                label("Tempo (BPM)")
                HStack(spacing: 8) {
                    Toggle("frei", isOn: Binding(get: { ki.request.bpm == nil }, set: { ki.request.bpm = $0 ? nil : 110 }))
                        .toggleStyle(.checkbox)
                    if let bpm = ki.request.bpm {
                        Stepper(value: Binding(get: { bpm }, set: { ki.request.bpm = $0 }), in: 30...300) {
                            Text("\(bpm)").font(Typo.inter(13, .semibold)).monospacedDigit()
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                label("Tonart")
                Picker("", selection: $ki.request.key) {
                    ForEach(Self.keys, id: \.self) { k in Text(k.isEmpty ? "frei" : k).tag(k) }
                }
                .labelsHidden()
                .frame(width: 130)
            }
            VStack(alignment: .leading, spacing: 6) {
                label("Taktart")
                Picker("", selection: $ki.request.timeSignature) {
                    Text("frei").tag("")
                    Text("4/4").tag("4")
                    Text("3/4").tag("3")
                    Text("6/8").tag("6")
                    Text("2/4").tag("2")
                }
                .labelsHidden()
                .frame(width: 90)
            }
            VStack(alignment: .leading, spacing: 6) {
                label("Startwert (Seed)")
                HStack(spacing: 8) {
                    Toggle("zufällig", isOn: Binding(get: { ki.request.seed == nil }, set: { ki.request.seed = $0 ? nil : Int.random(in: 1...999_999) }))
                        .toggleStyle(.checkbox)
                    if let seed = ki.request.seed {
                        TextField("", value: Binding(get: { seed }, set: { ki.request.seed = $0 }), format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                    }
                }
                Text("Gleicher Startwert + gleiche Einstellungen = gleiches Ergebnis.")
                    .textStyle(Typo.bodySmall)
                    .foregroundColor(colors.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Fortschritt

private struct KIProgressCard: View {
    @ObservedObject var ki: KIMusicModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        if case .working(let step, let progress, let started, let estimate) = ki.phase {
            VStack(alignment: .leading, spacing: 14) {
                KIWaveAnimation()
                    .frame(height: 64)
                    .frame(maxWidth: .infinity)
                HStack(alignment: .firstTextBaseline) {
                    Text(step).textStyle(Typo.titleMedium).foregroundColor(colors.textPrimary)
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let elapsed = ctx.date.timeIntervalSince(started)
                        Text("\(Formatting.duration(Int64(elapsed * 1000))) · geschätzt \(Formatting.duration(Int64(estimate * 1000)))")
                            .textStyle(Typo.labelMedium)
                            .monospacedDigit()
                            .foregroundColor(colors.textSecondary)
                    }
                }
                if let progress {
                    ProgressView(value: min(1, max(0, progress))).tint(colors.accent)
                } else {
                    ProgressView().progressViewStyle(.linear).tint(colors.accent)
                }
                HStack {
                    Text("Läuft lokal mit niedriger Priorität – die Wiedergabe bleibt ungestört.")
                        .textStyle(Typo.bodySmall)
                        .foregroundColor(colors.textTertiary)
                    Spacer()
                    PillButton(title: "Abbrechen", icon: Icons.close, style: .plain) { ki.cancelGeneration() }
                }
            }
            .padding(20)
            .glassSurface(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous), strong: true)
        }
    }
}

/// Bewegte Wellenform während des Erzeugens (läuft nur, solange sie sichtbar ist).
private struct KIWaveAnimation: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let bars = 64
                let w = size.width / CGFloat(bars)
                for i in 0..<bars {
                    let x: Double = Double(i) / Double(bars)
                    let wave: Double = sin(t * 2.1 + x * 9.0) * cos(t * 0.7 + x * 3.3)
                    let a: Double = 0.5 + 0.5 * wave
                    let envelope: Double = 0.6 + 0.4 * sin(x * Double.pi)
                    let level: Double = 0.15 + 0.8 * a * envelope
                    let h: CGFloat = max(3, size.height * CGFloat(level))
                    let rect = CGRect(x: CGFloat(i) * w + w * 0.2, y: (size.height - h) / 2, width: w * 0.6, height: h)
                    g.fill(Path(roundedRect: rect, cornerRadius: w * 0.3),
                           with: .linearGradient(Gradient(colors: [colors.accent.opacity(0.95), colors.accentStrong.opacity(0.6)]),
                                                 startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Ergebnisse

private struct KIResultsCard: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var ki: KIMusicModel
    @Environment(\.musicColors) private var colors
    @State private var showLyrics = false

    var body: some View {
        StudioCard(icon: Icons.autoAwesome, title: ki.results.count == 1 ? "Neu erzeugt" : "\(ki.results.count) Varianten",
                   subtitle: "Gespeichert in „Meine KI-Kreationen“ – nicht automatisch in der Bibliothek") {
            VStack(spacing: 6) {
                ForEach(ki.results) { c in KICreationRow(ki: ki, creation: c, compact: true) }
                if let lyrics = ki.lastLyrics, !lyrics.isEmpty {
                    DisclosureGroup(isExpanded: $showLyrics) {
                        Text(lyrics)
                            .textStyle(Typo.bodySmall)
                            .foregroundColor(colors.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    } label: {
                        Text("Von der KI geschriebener Text").textStyle(Typo.labelLarge).foregroundColor(colors.textSecondary)
                    }
                }
                Text("Die Klangqualität bewertet die App nicht automatisch – hör die Varianten an und behalte, was dir gefällt.")
                    .textStyle(Typo.bodySmall)
                    .foregroundColor(colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Kreationen

private struct KICreationsSection: View {
    @ObservedObject var ki: KIMusicModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Meine KI-Kreationen").textStyle(Typo.headlineSmall).foregroundColor(colors.textPrimary)
                Text(ki.creations.items.count == 1 ? "1 Stück" : "\(ki.creations.items.count) Stücke")
                    .textStyle(Typo.labelMedium).foregroundColor(colors.textTertiary)
                Spacer()
                IconTap(icon: Icons.folderOpen, label: "Ordner im Finder zeigen", tint: colors.textSecondary) {
                    try? FileManager.default.createDirectory(at: ki.creationsFolder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(ki.creationsFolder)
                }
            }
            HStack(spacing: 10) {
                SegmentedControl(options: KICreationFilter.allCases, selection: $ki.filter, label: { $0.label }, height: 30)
                    .frame(maxWidth: 560)
                SearchField(text: $ki.query, placeholder: "Kreationen durchsuchen")
                    .frame(maxWidth: 260)
            }
            let shown = ki.shownCreations
            if shown.isEmpty {
                StudioPanelEmpty(icon: Icons.autoAwesome, title: ki.creations.items.isEmpty ? "Noch keine Kreationen" : "Keine Treffer",
                                 text: ki.creations.items.isEmpty ? "Erzeugte Stücke erscheinen hier – mit Beschreibung, Modell, Sprache und Startwert."
                                                                  : "Kein Stück passt zu Filter und Suche.")
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(shown) { c in KICreationRow(ki: ki, creation: c, compact: false) }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.card + 4, style: .continuous))
    }
}

struct KICreationRow: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var ki: KIMusicModel
    @Environment(\.musicColors) private var colors
    let creation: KICreation
    let compact: Bool
    @State private var hover = false
    @State private var renaming = false
    @State private var newTitle = ""

    var body: some View {
        let playing = ki.playingID == creation.id
        HStack(spacing: 12) {
            Button { ki.togglePlay(creation) } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [colors.accent.opacity(0.85), colors.accentStrong.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Icon(playing ? Icons.pause : Icons.play, size: 18, color: .white)
                }
                .frame(width: 42, height: 42)
            }
            .buttonStyle(PressScaleStyle(scale: 0.94))
            .help(playing ? "Anhalten" : "Anhören")
            VStack(alignment: .leading, spacing: 2) {
                if renaming {
                    TextField("Titel", text: $newTitle, onCommit: {
                        ki.rename(creation, to: newTitle)
                        renaming = false
                    })
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                } else {
                    Text(creation.title)
                        .textStyle(Typo.bodyMedium).fontWeight(.medium)
                        .foregroundColor(playing ? colors.accentText : colors.textPrimary)
                        .lineLimit(1)
                }
                Text(meta)
                    .textStyle(Typo.bodySmall)
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(1)
                if !compact {
                    Text(creation.prompt)
                        .textStyle(Typo.bodySmall)
                        .foregroundColor(colors.textTertiary)
                        .lineLimit(1)
                        .help(creation.prompt)
                }
            }
            Spacer(minLength: 8)
            if creation.exportedPath != nil {
                StudioBadge(text: "In der Bibliothek", icon: Icons.libraryMusic)
            }
            IconTap(icon: creation.favorite ? Icons.favorite : Icons.favoriteBorder, label: creation.favorite ? "Kein Favorit" : "Favorit",
                    tint: creation.favorite ? colors.accentText : colors.textSecondary) { ki.toggleFavorite(creation) }
            if hover || compact {
                PillButton(title: "In Bibliothek", icon: Icons.libraryMusic, style: .plain) { ki.addToLibrary(creation, app: model) }
                    .help("Über „Hinzufügen“ im gewählten Format in die Musikbibliothek übernehmen")
            }
            GlassMenuButton(help: "Weitere Aktionen", width: 250) {
                Icon(Icons.moreHoriz, size: 18, color: colors.textSecondary).frame(width: 30, height: 30)
            } content: { menu in
                VStack(spacing: 0) {
                    GlassMenuItem(title: "Erneut erzeugen (gleicher Startwert)", icon: Icons.refresh) { ki.reuse(creation, newVariation: false); menu.close() }
                    GlassMenuItem(title: "Neue Variation", icon: Icons.autoAwesome) { ki.reuse(creation, newVariation: true); menu.close() }
                    GlassMenuItem(title: "Umbenennen …", icon: Icons.edit) { newTitle = creation.title; renaming = true; menu.close() }
                    GlassMenuItem(title: "Im Finder zeigen", icon: Icons.folderOpen) { ki.reveal(creation); menu.close() }
                    GlassMenuDivider()
                    GlassMenuItem(title: "In den Papierkorb", icon: Icons.delete) { ki.delete(creation); menu.close() }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hover ? colors.textPrimary.opacity(0.05) : .clear))
        .onHover { hover = $0 }
        .contextMenu {
            Button(playing ? "Anhalten" : "Anhören") { ki.togglePlay(creation) }
            Button("In die Musikbibliothek übernehmen") { ki.addToLibrary(creation, app: model) }
            Button("Erneut erzeugen") { ki.reuse(creation, newVariation: false) }
            Button("Neue Variation") { ki.reuse(creation, newVariation: true) }
            Button("Beschreibung kopieren") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(creation.prompt, forType: .string)
            }
            Divider()
            Button("In den Papierkorb") { ki.delete(creation) }
        }
    }

    private var meta: String {
        var parts = [creation.kind.label]
        if let d = creation.duration { parts.append(Formatting.duration(Int64(d * 1000))) }
        if let l = creation.language, let name = KILanguage.named(l)?.name { parts.append(name) }
        parts.append(creation.date.formatted(date: .abbreviated, time: .shortened))
        if let s = creation.seed { parts.append("Startwert \(s)") }
        return parts.joined(separator: " · ")
    }
}
