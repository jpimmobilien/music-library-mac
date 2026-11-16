import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MLCore
import MLStudio

// Stimmenstudio, Referenzanalyse und Sounddesign.

// MARK: - Stimmenstudio

struct HSVoicesView: View {
    @ObservedObject var hs: HoerspielModel
    @Environment(\.musicColors) private var colors
    @State private var name = ""
    @State private var settings = HSVoiceSettings()
    @State private var custom = ""
    @State private var editing: UUID?
    @State private var showAuthorized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            designer
            HStack {
                SectionTitle(text: "Gespeicherte Stimmen")
                Spacer()
                PillButton(title: "Berechtigte Stimme hinzufügen …", icon: Icons.lock, style: .plain) { showAuthorized = true }
            }
            if hs.voices.isEmpty {
                Text("Noch keine Stimmen. Entwirf oben eine Stimme oder lege aus einer analysierten Referenz Stilprofile an.")
                    .textStyle(Typo.bodySmall).foregroundColor(colors.textTertiary)
            }
            ForEach(hs.voices) { v in row(v) }
        }
        .sheet(isPresented: $showAuthorized) { HSAuthorizedVoiceSheet(hs: hs) }
    }

    private var designer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editing == nil ? "Stimme entwerfen" : "Stimme ändern").textStyle(Typo.headlineSmall).foregroundColor(colors.textPrimary)
            Text("Stimmen entstehen aus diesen Einstellungen – sie gehören keiner realen Person. Jede gespeicherte Stimme klingt in allen Kapiteln gleich, weil alle Zeilen aus ihrem Referenzsatz gesprochen werden.")
                .textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                TextField("Name der Stimme (z. B. „Kommissar Brandt“)", text: $name).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    picker("Geschlecht", $settings.gender, HSVoiceSettings.Gender.allCases) { ["männlich", "weiblich", "neutral"][HSVoiceSettings.Gender.allCases.firstIndex(of: $0)!] }
                    picker("Alter", $settings.age, HSVoiceSettings.Age.allCases) { ["Kind", "Jugendlich", "Junger Erwachsener", "Erwachsen", "Mittleres Alter", "Älter"][HSVoiceSettings.Age.allCases.firstIndex(of: $0)!] }
                    picker("Stimmfarbe", $settings.timbre, HSVoiceSettings.Timbre.allCases) { ["dunkel", "warm", "neutral", "hell", "rau", "hauchig", "nasal"][HSVoiceSettings.Timbre.allCases.firstIndex(of: $0)!] }
                }
                GridRow {
                    picker("Artikulation", $settings.articulation, HSVoiceSettings.Articulation.allCases) { ["sehr deutlich", "natürlich", "locker", "abgehackt"][HSVoiceSettings.Articulation.allCases.firstIndex(of: $0)!] }
                    picker("Grundstimmung", $settings.mood, HSVoiceSettings.Mood.allCases) { ["ruhig", "freundlich", "ernst", "frech", "nervös", "fröhlich", "streng", "geheimnisvoll", "brummig"][HSVoiceSettings.Mood.allCases.firstIndex(of: $0)!] }
                    VStack(alignment: .leading, spacing: 4) {
                        HSFormat.label("Akzent / Färbung", colors)
                        TextField("z. B. leicht hamburgisch", text: $settings.accent).textFieldStyle(.roundedBorder).frame(width: 200)
                    }
                }
                GridRow {
                    stepper("Tonhöhe", $settings.pitch, ["sehr tief", "tief", "mittel", "hoch", "sehr hoch"])
                    stepper("Sprechtempo", $settings.tempo, ["sehr langsam", "langsam", "normal", "schnell", "sehr schnell"])
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HSFormat.label("Beschreibung für das Modell", colors)
                TextField(settings.descriptionEN, text: $custom, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...4)
                Text("Leer lassen = aus den Einstellungen. Das Modell versteht Englisch am zuverlässigsten; Akzente setzt es nur teilweise um.")
                    .textStyle(Typo.bodySmall).foregroundColor(colors.textTertiary)
            }
            HStack(spacing: 10) {
                PillButton(title: editing == nil ? "Entwerfen und anhören" : "Neu entwerfen", icon: Icons.voice, style: .filled) {
                    hs.designVoice(name: name, settings: settings, custom: custom.isEmpty ? nil : custom, replacing: editing, newSeed: editing != nil)
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || hs.isWorking || hs.setup != .ready)
                if editing != nil { PillButton(title: "Neue Stimme", style: .plain) { editing = nil; name = ""; settings = HSVoiceSettings(); custom = "" } }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous), strong: true)
    }

    private func picker<T: Hashable>(_ title: String, _ sel: Binding<T>, _ all: [T], _ label: @escaping (T) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HSFormat.label(title, colors)
            Picker("", selection: sel) { ForEach(all, id: \.self) { Text(label($0)).tag($0) } }.labelsHidden().frame(width: 200)
        }
    }

    private func stepper(_ title: String, _ value: Binding<Int>, _ labels: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HSFormat.label(title, colors)
            Stepper(value: value, in: -2...2) { Text(labels[value.wrappedValue + 2]).font(Typo.inter(12.5, .medium)) }.fixedSize()
        }
    }

    private func row(_ v: HSVoiceProfile) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(v.name).textStyle(Typo.titleSmall).foregroundColor(colors.textPrimary)
                    Text(v.kind.label)
                        .font(Typo.inter(10.5, .semibold))
                        .foregroundColor(v.kind == .authorized ? (v.canSpeak ? Color(argb: 0xFF34C759) : colors.danger) : colors.accentText)
                        .padding(.horizontal, 8).frame(height: 20)
                        .background(Capsule().fill(colors.accentSoft))
                        .help(v.kind.explanation)
                }
                Text(v.kind == .styleOnly ? (v.settings.notes.isEmpty ? v.designDescription : v.settings.notes) : v.designDescription)
                    .textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).lineLimit(2)
                if let src = v.sourceReference { Text("Herkunft: Stilprofil aus „\(src)“ – nur allgemeine Merkmale").textStyle(Typo.bodySmall).foregroundColor(colors.textTertiary) }
                if let c = v.consent {
                    Text("Einwilligung von \(c.personName) für \(c.grantedTo) vom \(c.date.formatted(date: .abbreviated, time: .omitted)) – "
                         + (c.isVerified ? String(format: "geprüft (Ähnlichkeit %.2f)", c.similarity ?? 0) : "nicht bestanden"))
                        .textStyle(Typo.bodySmall).foregroundColor(c.isVerified ? colors.textTertiary : colors.danger)
                }
            }
            Spacer()
            if let f = v.referenceFile {
                GlassIconButton(icon: hs.playingKey == "voice-\(v.id)" ? Icons.pause : Icons.play, label: "Anhören", size: 32, iconSize: 15) {
                    hs.play(hs.store.voicesDir.appendingPathComponent(f), key: "voice-\(v.id)")
                }
            }
            GlassMenuButton(help: "Stimme", width: 280) {
                Icon(Icons.moreHoriz, size: 16, color: colors.textSecondary).frame(width: 30, height: 30)
            } content: { menu in
                if v.kind == .designed {
                    GlassMenuItem(title: "Ändern …", icon: Icons.edit) {
                        editing = v.id; name = v.name; settings = v.settings; custom = v.customDescriptionEN ?? ""
                        menu.close()
                    }
                }
                if v.kind == .styleOnly {
                    GlassMenuItem(title: "Eigenständige Stimme daraus entwerfen", icon: Icons.voice) { hs.designFromStyle(v); menu.close() }
                }
                GlassMenuDivider()
                GlassMenuItem(title: "In den Papierkorb", icon: Icons.delete) { hs.trashVoice(v); menu.close() }
            }
        }
        .padding(14)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

/// Berechtigte individuelle Stimme: nur mit Stimmprobe UND gesprochener Einwilligung derselben Person.
private struct HSAuthorizedVoiceSheet: View {
    @ObservedObject var hs: HoerspielModel
    @Environment(\.musicColors) private var colors
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var person = ""
    @State private var grantedTo = NSFullUserName()
    @State private var scope = "Private Hörspiele und Hörbücher in der Music Library"
    @State private var sample: URL?
    @State private var consent: URL?
    @State private var document: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Berechtigte Stimme").textStyle(Typo.headlineSmall).foregroundColor(colors.textPrimary)
            Text("Die Stimme einer realen Person darf nur mit ihrer ausdrücklichen Einwilligung nachgebildet werden. Die Person spricht dafür den folgenden Satz selbst ein; die App prüft, ob es dieselbe Stimme wie in der Stimmprobe ist und ob der Satz gesagt wurde. Aufnahmen aus Hörspielen, Filmen oder dem Internet sind keine Einwilligung.")
                .textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow { Text("Name der Stimme"); TextField("z. B. Opa Heinz", text: $name) }
                GridRow { Text("Person"); TextField("Vor- und Nachname", text: $person) }
                GridRow { Text("Erlaubt für"); TextField("dein Name", text: $grantedTo) }
                GridRow { Text("Umfang"); TextField("wofür die Einwilligung gilt", text: $scope) }
            }
            .textFieldStyle(.roundedBorder)
            .font(Typo.inter(12.5, .medium))
            Text("Einwilligungssatz: „\(HSConsent.statement(person: person.isEmpty ? "[Name]" : person, grantedTo: grantedTo.isEmpty ? "[Name]" : grantedTo))“")
                .textStyle(Typo.bodySmall).foregroundColor(colors.textPrimary)
                .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(colors.fieldFill))
            fileRow("Stimmprobe (8–15 s, nur diese Person, ohne Musik)", $sample)
            fileRow("Gesprochene Einwilligung (Aufnahme des Satzes)", $consent)
            fileRow("Optional: unterschriebenes Dokument (PDF/Bild)", $document, types: [.pdf, .image])
            HStack {
                Spacer()
                PillButton(title: "Abbrechen", style: .plain) { dismiss() }
                PillButton(title: "Prüfen und speichern", icon: Icons.lock, style: .filled) {
                    guard let s = sample, let c = consent else { return }
                    hs.addAuthorizedVoice(name: name, person: person, grantedTo: grantedTo, scope: scope, sample: s, consent: c, document: document)
                    dismiss()
                }
                .disabled(name.isEmpty || person.isEmpty || grantedTo.isEmpty || sample == nil || consent == nil || hs.isWorking
                          || hs.setup != .ready || !HSModel.analysis.allSatisfy { hs.isInstalled($0) })
            }
            if !HSModel.analysis.allSatisfy({ hs.isInstalled($0) }) {
                Text("Für die Prüfung werden Whisper, Silero VAD und SpeechBrain-ECAPA gebraucht (ca. 1,7 GB) – laden unter Einstellungen → KI-Hörbücher.")
                    .textStyle(Typo.bodySmall).foregroundColor(colors.danger)
            }
        }
        .padding(22)
        .frame(width: 600)
    }

    private func fileRow(_ title: String, _ url: Binding<URL?>, types: [UTType] = [.audio]) -> some View {
        HStack {
            Text(title).font(Typo.inter(12.5, .medium))
            Spacer()
            Text(url.wrappedValue?.lastPathComponent ?? "–").font(Typo.inter(12, .regular)).foregroundColor(colors.textSecondary).lineLimit(1)
            PillButton(title: "Wählen …", style: .tonal) {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = types
                if panel.runModal() == .OK { url.wrappedValue = panel.url }
            }
        }
    }
}

// MARK: - Referenz analysieren

struct HSReferenceView: View {
    @ObservedObject var hs: HoerspielModel
    @Environment(\.musicColors) private var colors
    @State private var name = ""
    @State private var files: [URL] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Referenz analysieren").textStyle(Typo.headlineSmall).foregroundColor(colors.textPrimary)
                Text("Importiere eine oder mehrere eigene Aufnahmen (MP3, WAV, M4A …), z. B. ein altes Hörspiel. Ausgewertet werden Sprecherzahl und Redeanteile, Tonhöhe, Tempo, Klangfarbe, Pausen, Dialogtempo, Erzählanteil, Bandbreite, Rauschen, Nachhall und Musikbrücken. Gespeichert werden nur diese allgemeinen Merkmale – keine Kopie der Aufnahme, keine Stimmabdrücke.")
                    .textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    TextField("Name der Referenz (z. B. „Kassetten-Krimi 1985“)", text: $name).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                    PillButton(title: files.isEmpty ? "Aufnahmen wählen …" : "\(files.count) Datei(en)", icon: Icons.audioFile, style: .tonal) { pick() }
                    PillButton(title: "Analysieren", icon: Icons.equalizer, style: .filled) {
                        hs.analyzeReference(files: files, name: name)
                        files = []
                    }
                    .disabled(files.isEmpty || hs.isWorking || hs.setup != .ready || !analysisReady)
                }
                if !analysisReady {
                    Text("Für die Analyse werden Whisper, Silero VAD und SpeechBrain-ECAPA gebraucht (ca. 1,7 GB) – laden unter Einstellungen → KI-Hörbücher.")
                        .textStyle(Typo.bodySmall).foregroundColor(colors.danger)
                }
                Text("Ergebnisse sind Messungen und Schätzungen: Sprechererkennung kann Stimmen zusammenlegen oder trennen; Alter und Geschlecht werden nur aus der Tonhöhe geschätzt.")
                    .textStyle(Typo.bodySmall).foregroundColor(colors.textTertiary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous), strong: true)
            ForEach(hs.references) { r in card(r) }
        }
    }

    private var analysisReady: Bool { HSModel.analysis.allSatisfy { hs.isInstalled($0) } }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { files = panel.urls }
    }

    private func card(_ r: HSReference) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(r.name).textStyle(Typo.titleMedium).foregroundColor(colors.textPrimary)
                Text(r.analyzed.formatted(date: .abbreviated, time: .shortened)).textStyle(Typo.bodySmall).foregroundColor(colors.textTertiary)
                Spacer()
                PillButton(title: "Stilprofile anlegen", icon: Icons.voice, style: .tonal) { hs.createStyleProfiles(from: r) }
                GlassMenuButton(help: "Referenz", width: 220) {
                    Icon(Icons.moreHoriz, size: 16, color: colors.textSecondary).frame(width: 30, height: 30)
                } content: { menu in
                    GlassMenuItem(title: "In den Papierkorb", icon: Icons.delete) { hs.trashReference(r); menu.close() }
                }
            }
            Text(r.summary).textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).fixedSize(horizontal: false, vertical: true)
            if !r.styleHint.isEmpty {
                Text("Für neue Geschichten: \(r.styleHint)" + (r.retroSuggested > 0 ? String(format: " · Klang: Retro %d %%", Int(r.retroSuggested * 100)) : ""))
                    .textStyle(Typo.bodySmall).foregroundColor(colors.textTertiary)
            }
            Text("Quellen: " + r.sources.joined(separator: ", ")).textStyle(Typo.bodySmall).foregroundColor(colors.textTertiary)
        }
        .padding(16)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

// MARK: - Sounddesign

struct HSSoundView: View {
    @ObservedObject var hs: HoerspielModel
    @Environment(\.musicColors) private var colors
    @State private var prompt = ""
    @State private var name = ""
    @State private var seconds = 6.0
    @State private var license = ""
    @State private var query = ""

    static let ideas = ["footsteps on gravel", "creaking wooden door", "old car engine starting", "telephone ringing, 1980s",
                        "heavy rain on a window", "wind over an empty field", "thunderstorm", "forest at night, crickets",
                        "busy city street, 1980s", "crowd murmuring in a hall", "footsteps on a wooden staircase", "steam train passing"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Geräusch erzeugen").textStyle(Typo.headlineSmall).foregroundColor(colors.textPrimary)
                Text("Beschreibe das Geräusch auf Englisch (so versteht es das Modell am besten). Erzeugte Geräusche landen in deiner lokalen Bibliothek und werden in Hörspielen automatisch an die passenden Stellen gesetzt – unter der Sprache leiser geregelt.")
                    .textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    TextField("z. B. footsteps on a wooden staircase", text: $prompt).textFieldStyle(.roundedBorder)
                    TextField("Name (deutsch)", text: $name).textFieldStyle(.roundedBorder).frame(width: 180)
                    Stepper(value: $seconds, in: 1...30, step: 1) { Text("\(Int(seconds)) s").font(Typo.inter(12.5, .medium)).monospacedDigit() }.fixedSize()
                    PillButton(title: "Erzeugen", icon: Icons.sfx, style: .filled) { hs.generateSFX(prompt: prompt, name: name, seconds: seconds) }
                        .disabled(prompt.isEmpty || hs.isWorking || hs.setup != .ready || !hs.isInstalled(.sfx))
                }
                StudioFlow(spacing: 6) { ForEach(Self.ideas, id: \.self) { i in ChoiceChip(title: i, selected: prompt == i) { prompt = i } } }
                if !hs.isInstalled(.sfx) {
                    Text("Das Geräuschmodell (Stable Audio 3 small) ist noch nicht geladen – Einstellungen → KI-Hörbücher.")
                        .textStyle(Typo.bodySmall).foregroundColor(colors.danger)
                }
                Hairline()
                HStack(spacing: 10) {
                    TextField("Herkunft/Lizenz für eigene Dateien (z. B. „eigene Aufnahme“, „CC0 – freesound.org/…“)", text: $license).textFieldStyle(.roundedBorder)
                    PillButton(title: "Eigene Datei importieren …", icon: Icons.audioFile, style: .tonal) {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.audio]
                        if panel.runModal() == .OK, let url = panel.url { hs.importSFX(url, name: "", license: license) }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous), strong: true)
            HStack {
                SectionTitle(text: "Geräuschbibliothek (\(hs.sfxLibrary.count))")
                Spacer()
                SearchField(text: $query, placeholder: "Geräusche durchsuchen").frame(width: 240)
            }
            ForEach(hs.sfxLibrary.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.prompt.localizedCaseInsensitiveContains(query) }) { s in
                HStack(spacing: 12) {
                    GlassIconButton(icon: hs.playingKey == "sfx-\(s.id)" ? Icons.pause : Icons.play, label: "Anhören", size: 30, iconSize: 14) {
                        hs.play(URL(fileURLWithPath: s.file), key: "sfx-\(s.id)")
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name).textStyle(Typo.titleSmall).foregroundColor(colors.textPrimary).lineLimit(1)
                        Text([s.prompt, s.origin, s.license].filter { !$0.isEmpty }.joined(separator: " · "))
                            .textStyle(Typo.bodySmall).foregroundColor(colors.textTertiary).lineLimit(1)
                    }
                    Spacer()
                    Button { hs.trashSFX(s) } label: { Icon(Icons.delete, size: 15, color: colors.textSecondary) }
                        .buttonStyle(.plain).help("In den Papierkorb")
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .glassSurface(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}
