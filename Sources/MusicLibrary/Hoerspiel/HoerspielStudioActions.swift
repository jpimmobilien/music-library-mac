import Foundation
import AppKit
import MLCore
import MLStudio
import StudioEngine

/// Stimmenstudio, Referenzanalyse und Geräuschbibliothek.
extension HoerspielModel {
    /// Mindest-Ähnlichkeit zwischen gesprochener Einwilligung und Stimmprobe (ECAPA, Kosinus). Kalibriert im
    /// Prüfstand an echten deutschen Sprechern (docs/KI_HOERSPIEL_MACHBARKEIT.md, Prüfung E).
    static let consentThreshold = 0.5

    // MARK: Stimmen entwerfen

    /// Neue entworfene Stimme anlegen und sofort den Referenzsatz erzeugen.
    func designVoice(name: String, settings: HSVoiceSettings, custom: String?, replacing: UUID? = nil, newSeed: Bool = false) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        var profile = replacing.flatMap { id in voices.first { $0.id == id } } ?? HSVoiceProfile(name: n, kind: .designed)
        profile.name = n
        profile.settings = settings
        profile.customDescriptionEN = custom
        if newSeed { profile.seed = Int.random(in: 1...999_999) }
        let target = profile
        run("Stimme entwerfen") { m, e in
            let file = "\(target.id.uuidString)-\(target.seed).wav"
            let out = m.store.voicesDir.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: m.store.voicesDir, withIntermediateDirectories: true)
            m.report("„\(target.name)“ wird entworfen …", 0.2)
            let v = try await e.designVoice(instruct: target.designDescription, seed: target.seed, out: out, progress: m.reporter(range: 0.2...1))
            var saved = target
            saved.referenceFile = file
            saved.referenceText = v.text
            var list = m.voices.filter { $0.id != saved.id }
            list.insert(saved, at: 0)
            m.setVoices(list)
            m.play(out, key: "voice-\(saved.id)")
        }
    }

    /// Stilprofile aus einer analysierten Referenz anlegen (nur Beschreibungen, keine Stimme).
    func createStyleProfiles(from ref: HSReference) {
        var list = voices
        for s in ref.speakers {
            var v = HSVoiceProfile(name: "\(ref.name) – \(s.id) \(s.role.replacingOccurrences(of: " (geschätzt)", with: ""))", kind: .styleOnly,
                                   customDescriptionEN: s.voiceEN)
            v.sourceReference = ref.name
            v.settings.notes = s.descriptionDE
            list.append(v)
        }
        setVoices(list)
        section = .voices
    }

    /// Aus einem Stilprofil eine eigenständige Stimme entwerfen (keine Nachbildung der Person in der Referenz).
    func designFromStyle(_ style: HSVoiceProfile) {
        guard style.kind == .styleOnly else { return }
        var v = HSVoiceProfile(name: style.name.replacingOccurrences(of: " – ", with: " · ") + " (entworfen)", kind: .designed,
                               settings: style.settings, customDescriptionEN: style.customDescriptionEN)
        v.sourceReference = style.sourceReference
        setVoices([v] + voices)
        designVoice(name: v.name, settings: v.settings, custom: v.customDescriptionEN, replacing: v.id)
    }

    func renameVoice(_ v: HSVoiceProfile, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        var list = voices
        if let i = list.firstIndex(where: { $0.id == v.id }) { list[i].name = n }
        setVoices(list)
    }

    /// Stimme in den Papierkorb (Dateien) und aus der Liste. Produktionen, die sie nutzen, behalten ihre
    /// gesprochenen Zeilen; neu sprechen geht danach nur mit einer anderen Stimme.
    func trashVoice(_ v: HSVoiceProfile) {
        for f in [v.referenceFile, v.consent?.recordingFile, v.consent?.documentFile].compactMap({ $0 }) {
            let url = store.voicesDir.appendingPathComponent(f)
            if FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        }
        setVoices(voices.filter { $0.id != v.id })
    }

    // MARK: Berechtigte Stimme

    /// Berechtigte individuelle Stimme anlegen: Stimmprobe und gesprochene Einwilligung derselben Person werden
    /// kopiert und geprüft (gleiche Stimme? Einwilligung mit Namen gesagt?). Ohne bestandene Prüfung kann die Stimme
    /// nicht sprechen.
    func addAuthorizedVoice(name: String, person: String, grantedTo: String, scope: String, sample: URL, consent: URL, document: URL?) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines), who = person.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !who.isEmpty else { return }
        guard HSModel.analysis.allSatisfy({ isInstalled($0) }) else {
            setNotice("Für die Prüfung der Einwilligung werden Whisper, Silero VAD und SpeechBrain-ECAPA gebraucht (ca. 1,7 GB) – "
                      + "laden unter Einstellungen → KI-Hörbücher.")
            return
        }
        run("Einwilligung prüfen") { m, e in
            let fm = FileManager.default
            try fm.createDirectory(at: m.store.voicesDir, withIntermediateDirectories: true)
            var v = HSVoiceProfile(name: n, kind: .authorized)
            func copy(_ src: URL, _ suffix: String) throws -> String {
                let name = "\(v.id.uuidString)-\(suffix).\(src.pathExtension.isEmpty ? "wav" : src.pathExtension)"
                try fm.copyItem(at: src, to: m.store.voicesDir.appendingPathComponent(name))
                return name
            }
            let sampleFile = try copy(sample, "probe")
            let consentFile = try copy(consent, "einwilligung")
            let docFile = try document.map { try copy($0, "dokument") }
            m.report("Stimmen werden verglichen …", 0.2)
            let check = try await e.verifyConsent(recording: m.store.voicesDir.appendingPathComponent(consentFile),
                                                  sample: m.store.voicesDir.appendingPathComponent(sampleFile),
                                                  progress: m.reporter(range: 0.2...1))
            var c = HSConsent(personName: who, scope: scope, grantedTo: grantedTo, recordingFile: consentFile, documentFile: docFile)
            c.similarity = check.similarity
            c.similarityThreshold = Self.consentThreshold
            c.transcript = check.transcript
            c.transcriptMatches = HSConsent.transcriptMatches(check.transcript, person: who)
            if c.transcriptMatches == true && check.similarity >= Self.consentThreshold { c.verified = Date() }
            v.consent = c
            v.referenceFile = sampleFile
            v.referenceText = check.sampleTranscript
            m.setVoices([v] + m.voices)
            if !v.canSpeak {
                var reasons: [String] = []
                if c.transcriptMatches != true { reasons.append("In der Einwilligung wurden Name und Einwilligungssatz nicht erkannt (gehört: „\(check.transcript.prefix(160))“).") }
                if check.similarity < Self.consentThreshold {
                    reasons.append(String(format: "Die Stimme in der Einwilligung passt nicht zur Stimmprobe (Ähnlichkeit %.2f, nötig %.2f).", check.similarity, Self.consentThreshold))
                }
                if check.sampleSeconds < 4 { reasons.append("Die Stimmprobe ist sehr kurz (\(check.sampleSeconds) s) – 8 bis 15 Sekunden sind besser.") }
                m.setNotice("„\(n)“ wurde gespeichert, ist aber nicht freigegeben: " + reasons.joined(separator: " "))
            }
        }
    }

    // MARK: Referenzanalyse

    func analyzeReference(files: [URL], name: String) {
        guard !files.isEmpty else { return }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? files[0].deletingPathExtension().lastPathComponent : name
        run("Referenz analysieren") { m, e in
            var merged: HSReference?
            for (i, f) in files.enumerated() {
                let span = 1.0 / Double(files.count)
                m.report("„\(f.lastPathComponent)“ wird analysiert (Sprecher, Text, Klang) …", Double(i) * span)
                let ref0 = HSReference(name: title, sources: [], summary: "", styleHint: "", speakers: [], retroSuggested: 0)
                try FileManager.default.createDirectory(at: m.store.referencesDir, withIntermediateDirectories: true)
                let out = m.store.analysisFile(for: ref0).deletingLastPathComponent()
                    .appendingPathComponent("\(ref0.id.uuidString)-\(i).analyse.json")
                let r = try await e.analyze(file: f, name: title, out: out,
                                            progress: m.reporter(prefix: "\(f.lastPathComponent): ", range: (Double(i) * span)...(Double(i + 1) * span)))
                let ref = HSReference.from(profile: r.profile, name: title, sources: [f.lastPathComponent])
                if var mm = merged {
                    // mehrere Aufnahmen: Sprecher und Zusammenfassungen sammeln (Stimmen werden nicht über Dateien hinweg gleichgesetzt)
                    mm.sources += ref.sources
                    mm.summary += "\n\n" + f.lastPathComponent + ":\n" + ref.summary
                    mm.speakers += ref.speakers.map { var s = $0; s.id = "\(i + 1)-\(s.id)"; return s }
                    mm.retroSuggested = max(mm.retroSuggested, ref.retroSuggested)
                    merged = mm
                } else {
                    merged = ref
                }
            }
            guard let ref = merged else { return }
            try m.store.save(ref)
            m.setReferences([ref] + m.references)
        }
    }

    func trashReference(_ r: HSReference) {
        let dir = store.referencesDir
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.lastPathComponent.hasPrefix(r.id.uuidString) {
            try? FileManager.default.trashItem(at: f, resultingItemURL: nil)
        }
        setReferences(references.filter { $0.id != r.id })
    }

    // MARK: Geräusche

    func generateSFX(prompt: String, name: String, seconds: Double) {
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        run("Geräusch erzeugen") { m, e in
            let path = try await e.sfx(prompt: p, seconds: seconds, library: m.store.sfxDir.appendingPathComponent("erzeugt", isDirectory: true),
                                       seed: Int.random(in: 1...99_999), progress: m.reporter(range: 0...1))
            let entry = HSSFXEntry(name: name.isEmpty ? p : name, prompt: p, file: path, seconds: seconds, origin: "erzeugt",
                                   license: "Erzeugt mit Stable Audio 3 small (Stability AI Community License)")
            m.setSFX([entry] + m.sfxLibrary.filter { $0.file != path })
            m.play(URL(fileURLWithPath: path), key: "sfx-\(entry.id)")
        }
    }

    /// Eigene Geräuschdatei aufnehmen (wird kopiert; Herkunft/Lizenz dokumentiert der Nutzer).
    func importSFX(_ url: URL, name: String, license: String) {
        do {
            let dir = store.sfxDir.appendingPathComponent("importiert", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(String(UUID().uuidString.prefix(8)) + "-" + url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: dest)
            let entry = HSSFXEntry(name: name.isEmpty ? url.deletingPathExtension().lastPathComponent : name, prompt: "", file: dest.path,
                                   seconds: 0, origin: "importiert", license: license.isEmpty ? "eigene Datei (Lizenz nicht angegeben)" : license)
            setSFX([entry] + sfxLibrary)
        } catch {
            setNotice("Import fehlgeschlagen: \(StudioModel.message(error))")
        }
    }

    func trashSFX(_ s: HSSFXEntry) {
        let url = URL(fileURLWithPath: s.file)
        if FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        setSFX(sfxLibrary.filter { $0.id != s.id })
    }
}
