import Foundation
import MLCore
import MLStudio
import StudioEngine

/// Produktionsablauf: Geschichte → Kapitel → Sprecher → Stimmen → Geräusche → Musik → Mischung.
/// Jeder Schritt überspringt, was schon fertig und aktuell ist, und speichert nach jedem Teilschritt.
extension HoerspielModel {
    // MARK: Neue Produktion

    func create(_ mode: HSMode) {
        let d = draft(mode)
        let prompt = d.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isWorking else { return }
        var p = HSProduction(mode: mode, prompt: prompt, targetMinutes: max(2, min(180, d.minutes)))
        p.narration = d.narration
        p.retroAmount = mode == .hoerspiel ? d.retro : 0
        p.styleProfileID = d.referenceID
        p.useMusic = d.useMusic
        p.useSFX = mode == .hoerspiel && d.useSFX
        add(p)
        produce(p.id)
    }

    /// Ganze Produktion (fortsetzen, wo sie stehen geblieben ist).
    func produce(_ id: UUID) {
        run("Produktion") { m, e in
            try await m.stepStory(id, e)
            try await m.stepCasting(id, e)
            try await m.stepVoices(id, e)
            guard let p = m.production(id) else { return }
            if p.useSFX { try await m.stepSFX(id, e) }
            if p.useMusic { try await m.stepMusic(id, e) }
            try await m.stepMix(id, e)
        }
    }

    /// Nur einen Schritt ausführen (aus dem Editor oder der Produktionsübersicht).
    func runStep(_ step: HSStep, _ id: UUID) {
        run(step.title) { m, e in
            switch step {
            case .story, .chapters: try await m.stepStory(id, e)
            case .casting: try await m.stepCasting(id, e)
            case .voices: try await m.stepCasting(id, e); try await m.stepVoices(id, e)
            case .sfx: try await m.stepSFX(id, e)
            case .music: try await m.stepMusic(id, e)
            case .mix: try await m.stepMix(id, e)
            case .export: break
            }
        }
    }

    func production(_ id: UUID) -> HSProduction? { productions.first { $0.id == id } }

    // MARK: 1. Geschichte

    func stepStory(_ id: UUID, _ e: HSEngine) async throws {
        guard var p = production(id) else { return }
        if p.state(.story) == .done && p.scenes.allSatisfy({ !$0.items.isEmpty }) { return }
        guard let model = storyModel else { throw StudioError.other("Auf diesem Mac läuft kein Sprachmodell für Geschichten.") }
        update(id) { $0.set(.story, .running) }
        report("Sprachmodell wird geladen …", 0.01)
        try await e.loadLLM(model, progress: reporter(range: 0...0.05))
        if p.figures.isEmpty || p.scenes.isEmpty {
            report("Konzept, Figuren und Szenenplan …", 0.05)
            let style = p.styleProfileID.flatMap { rid in references.first { $0.id == rid } }.map { "\($0.name): \($0.styleHint)" }
            let concept = try await e.concept(prompt: p.prompt, minutes: p.targetMinutes, mode: p.mode,
                                              characters: draft(p.mode).characters, style: style, progress: reporter(range: 0.05...0.12))
            update(id) { HSJSON.apply(concept: concept, to: &$0) }
            p = production(id) ?? p
        }
        let total = p.scenes.count
        let perScene = max(80, HSPlan.targetWords(minutes: p.targetMinutes) / max(1, total))
        for index in 0..<total {
            try Task.checkCancellation()
            guard let cur = production(id), cur.scenes.indices.contains(index) else { break }
            if !cur.scenes[index].items.isEmpty { continue }
            let summaries = cur.scenes[..<index].enumerated().map { "Szene \($0.offset + 1): \($0.element.summary)" }
            let tail = index > 0 ? cur.scenes[index - 1].scriptText.split(separator: "\n").suffix(6).joined(separator: "\n") : ""
            let base = 0.12 + 0.86 * Double(index) / Double(total)
            report("Szene \(index + 1) von \(total): \(cur.scenes[index].title)", base)
            let scene = try await e.scene(concept: HSJSON.concept(cur), index: index, summaries: summaries, tail: tail,
                                          targetWords: perScene,
                                          progress: reporter(prefix: "Szene \(index + 1) von \(total): ",
                                                             range: base...(base + 0.86 / Double(total))))
            update(id) { HSJSON.apply(scene: scene, at: index, to: &$0) }
        }
        update(id) {
            $0.set(.story, .done)
            $0.set(.chapters, .done)
        }
        try await e.unloadLLM()
    }

    /// Eine Szene neu schreiben (die bisherige Fassung bleibt als Version erhalten).
    func rewriteScene(_ id: UUID, index: Int) {
        run("Szene neu schreiben") { m, e in
            guard let model = m.storyModel, let p = m.production(id), p.scenes.indices.contains(index) else { return }
            try await e.loadLLM(model, progress: m.reporter(range: 0...0.2))
            let summaries = p.scenes[..<index].enumerated().map { "Szene \($0.offset + 1): \($0.element.summary)" }
            let tail = index > 0 ? p.scenes[index - 1].scriptText.split(separator: "\n").suffix(6).joined(separator: "\n") : ""
            let words = max(80, HSPlan.targetWords(minutes: p.targetMinutes) / max(1, p.scenes.count))
            let scene = try await e.scene(concept: HSJSON.concept(p), index: index, summaries: summaries, tail: tail,
                                          targetWords: words, progress: m.reporter(range: 0.2...1))
            m.update(id) { HSJSON.apply(scene: scene, at: index, to: &$0) }
        }
    }

    /// Eine Replik vom Sprachmodell neu formulieren lassen (die Stimme wird danach neu erzeugt).
    func rewriteLine(_ id: UUID, scene si: Int, item ii: Int, hint: String) {
        run("Replik neu formulieren") { m, e in
            guard let model = m.storyModel, let p = m.production(id), p.scenes.indices.contains(si),
                  p.scenes[si].items.indices.contains(ii), let sp = p.scenes[si].items[ii].speaker else { return }
            try await e.loadLLM(model, progress: m.reporter(range: 0...0.5))
            let text = try await e.rewriteLine(concept: HSJSON.concept(p), sceneText: p.scenes[si].scriptText, speaker: sp,
                                               line: p.scenes[si].items[ii].text, hint: hint, progress: m.reporter(range: 0.5...1))
            m.update(id) { pr in
                let old = pr.scenes[si].items
                var items = old
                items[ii].text = text
                items[ii].audioFingerprint = nil
                pr.scenes[si].replaceItems(items, note: "Replik neu formuliert")
                pr.markChanged(scene: pr.scenes[si].id)
            }
        }
    }

    // MARK: 3. Sprecher zuweisen

    func stepCasting(_ id: UUID, _ e: HSEngine) async throws {
        guard let p = production(id) else { return }
        update(id) { $0.set(.casting, .running) }
        let figures = p.speakingFigures
        let fm = FileManager.default
        for (n, f) in figures.enumerated() {
            try Task.checkCancellation()
            if let c = p.cast[f.id], fm.fileExists(atPath: file(c.referenceFile, in: p).path) { continue }
            if let pid = f.voiceProfileID, let profile = voices.first(where: { $0.id == pid }) {
                guard profile.canSpeak, let ref = profile.referenceFile else {
                    throw StudioError.other("Die Stimme „\(profile.name)“ kann nicht sprechen (\(profile.kind.label)).")
                }
                let cast = HSCast(referenceFile: store.voicesDir.appendingPathComponent(ref).path,
                                  referenceText: profile.referenceText ?? HSVoiceDesign.referenceText,
                                  instruct: profile.designDescription, seed: profile.seed, profileID: profile.id, kind: profile.kind)
                update(id) { $0.cast[f.id] = cast }
                continue
            }
            let instruct = (p.mode == .hoerbuch && f.isNarrator) ? HSVoiceDesign.narratorInstruct(style: p.narration, base: f.voiceEN)
                : HSVoiceDesign.instruct(for: f)
            let seed = HSVoiceDesign.seed(production: p.id, figure: f.id)
            report("Stimme für \(f.name.isEmpty ? f.id : f.name) wird entworfen …", Double(n) / Double(max(1, figures.count)))
            let out = folder(p).appendingPathComponent("stimmen/\(f.id).wav")
            try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
            let v = try await e.designVoice(instruct: instruct, seed: seed, out: out)
            update(id) { $0.cast[f.id] = HSCast(referenceFile: "stimmen/\(f.id).wav", referenceText: v.text, instruct: instruct, seed: seed) }
        }
        update(id) { $0.set(.casting, .done) }
    }

    /// Stimme einer Figur neu entwerfen (anderer Startwert) – betroffene Zeilen werden danach neu gesprochen.
    func recast(_ id: UUID, figure: String, profile: UUID?) {
        update(id) { p in
            p.cast[figure] = nil
            if let i = p.figures.firstIndex(where: { $0.id == figure }) { p.figures[i].voiceProfileID = profile }
            if p.state(.voices) == .done { p.set(.voices, .outdated) }
        }
    }

    // MARK: 4. Stimmen erzeugen

    func stepVoices(_ id: UUID, _ e: HSEngine) async throws {
        guard let p = production(id) else { return }
        let todo = p.linesNeedingVoice
        if todo.isEmpty {
            update(id) { $0.set(.voices, .done) }
            return
        }
        update(id) { $0.set(.voices, .running) }
        let fm = FileManager.default
        try fm.createDirectory(at: folder(p).appendingPathComponent("zeilen"), withIntermediateDirectories: true)
        let byScene = Dictionary(grouping: todo, by: { $0.scene })
        var done = 0
        for si in byScene.keys.sorted() {
            try Task.checkCancellation()
            guard let cur = production(id) else { return }
            let requests: [HSEngine.LineRequest] = byScene[si]!.compactMap { pos in
                let item = cur.scenes[pos.scene].items[pos.item]
                guard let sp = item.speaker, let c = cur.cast[sp] else { return nil }
                return HSEngine.LineRequest(key: item.id.uuidString, text: cur.spokenText(item.text),
                                            refAudio: file(c.referenceFile, in: cur).path, refText: c.referenceText,
                                            out: folder(cur).appendingPathComponent("zeilen/\(item.id.uuidString).wav").path)
            }
            let start = Double(done) / Double(todo.count)
            let span = Double(requests.count) / Double(todo.count)
            let results = try await e.speak(requests, progress: reporter(prefix: "Szene \(si + 1): ", range: start...(start + span)))
            done += requests.count
            update(id) { p in
                for r in results {
                    guard let path = r.path, let uuid = UUID(uuidString: r.key) else { continue }
                    for (sj, s) in p.scenes.enumerated() {
                        if let ii = s.items.firstIndex(where: { $0.id == uuid }) {
                            p.scenes[sj].items[ii].audioFile = "zeilen/" + (path as NSString).lastPathComponent
                            p.scenes[sj].items[ii].audioFingerprint = p.fingerprint(of: p.scenes[sj].items[ii])
                        }
                    }
                }
            }
        }
        update(id) {
            $0.set(.voices, $0.linesNeedingVoice.isEmpty ? .done : .failed)
            if $0.state(.mix) == .done { $0.set(.mix, .outdated) }
        }
        try await e.unloadTTS()
    }

    /// Eine einzelne Zeile neu sprechen.
    func regenerateLine(_ id: UUID, scene si: Int, item ii: Int) {
        update(id) { $0.scenes[si].items[ii].audioFingerprint = nil }
        run("Zeile neu sprechen") { m, e in
            try await m.stepCasting(id, e)
            try await m.stepVoices(id, e)
        }
    }

    // MARK: 5. Geräusche

    func stepSFX(_ id: UUID, _ e: HSEngine) async throws {
        guard let p = production(id), p.mode == .hoerspiel else { return }
        var wanted: [(String, Double, String)] = []
        for s in p.scenes {
            if let a = s.items.first(where: { $0.kind == .atmo }) {
                wanted.append((a.english ?? a.text, 20, a.text))
            } else if !s.atmoEN.isEmpty {
                wanted.append((s.atmoEN, 20, s.location))
            }
            for i in s.items where i.kind == .sfx { wanted.append((i.english ?? i.text, 4, i.text)) }
        }
        let fm = FileManager.default
        var seen = Set<String>()
        wanted = wanted.filter { seen.insert($0.0).inserted }
        let missing = wanted.filter { w in p.sfxFiles[w.0].map { !fm.fileExists(atPath: $0) } ?? true }
        if missing.isEmpty {
            update(id) { $0.set(.sfx, .done) }
            return
        }
        update(id) { $0.set(.sfx, .running) }
        let lib = store.sfxDir.appendingPathComponent("erzeugt", isDirectory: true)
        for (n, w) in missing.enumerated() {
            try Task.checkCancellation()
            report("Geräusch \(n + 1) von \(missing.count): \(w.2)", Double(n) / Double(missing.count))
            let path = try await e.sfx(prompt: w.0, seconds: w.1, library: lib)
            update(id) { $0.sfxFiles[w.0] = path }
            if !sfxLibrary.contains(where: { $0.file == path }) {
                setSFX(sfxLibrary + [HSSFXEntry(name: w.2.isEmpty ? w.0 : w.2, prompt: w.0, file: path, seconds: w.1, origin: "erzeugt",
                                                license: "Erzeugt mit Stable Audio 3 small (Stability AI Community License)")])
            }
        }
        update(id) {
            $0.set(.sfx, .done)
            if $0.state(.mix) == .done { $0.set(.mix, .outdated) }
        }
    }

    // MARK: 6. Musik (über KI-Musik)

    func stepMusic(_ id: UUID, _ e: HSEngine) async throws {
        guard let p = production(id) else { return }
        guard let ki, ki.setup == .ready else {
            setNotice("Musik übersprungen: KI-Musik ist nicht eingerichtet (Einstellungen → KI-Musik). Die Mischung entsteht ohne Musik.")
            return
        }
        let plan = try await e.musicPlan(story: HSJSON.story(p))
        let fm = FileManager.default
        let missing = plan.filter { piece in p.musicFiles[piece.kind].map { !fm.fileExists(atPath: $0) } ?? true }
        if missing.isEmpty {
            update(id) { $0.set(.music, .done) }
            return
        }
        update(id) { $0.set(.music, .running) }
        // Speicher für ACE-Step frei machen
        try await e.unloadAll()
        for (n, piece) in missing.enumerated() {
            try Task.checkCancellation()
            let start = Double(n) / Double(missing.count)
            report("Musik „\(piece.kind)“ (\(Int(piece.seconds)) s) – KI-Musik …", start)
            let dir = folder(p).appendingPathComponent("musik/\(piece.kind)", isDirectory: true)
            let url = try await ki.instrumental(caption: piece.caption, seconds: piece.seconds,
                                                seed: HSVoiceDesign.seed(production: p.id, figure: piece.kind), into: dir,
                                                progress: reporter(prefix: "Musik „\(piece.kind)“: ", range: start...(start + 1 / Double(missing.count))))
            update(id) { $0.musicFiles[piece.kind] = url.path }
        }
        update(id) {
            $0.set(.music, .done)
            if $0.state(.mix) == .done { $0.set(.mix, .outdated) }
        }
    }

    // MARK: 7. Mischung

    func stepMix(_ id: UUID, _ e: HSEngine) async throws {
        guard let p = production(id) else { return }
        guard p.linesNeedingVoice.isEmpty else { throw StudioError.other("Es fehlen noch gesprochene Zeilen – zuerst „Stimmen erzeugen“.") }
        update(id) { $0.set(.mix, .running) }
        var voiceFiles: [String: String] = [:]
        for (si, s) in p.scenes.enumerated() {
            for (ii, it) in s.items.enumerated() where it.kind == .line {
                if let f = it.audioFile { voiceFiles[HSJSON.lineKey(scene: si, item: ii)] = file(f, in: p).path }
            }
        }
        report("Mischung wird erstellt …", 0.05)
        let out = folder(p).appendingPathComponent("mix", isDirectory: true)
        let r = try await e.mix(story: HSJSON.story(p), voiceFiles: voiceFiles, sfxFiles: p.useSFX ? p.sfxFiles : [:],
                                musicFiles: p.useMusic ? p.musicFiles : [:], retro: p.retroAmount, lufs: -16, outDir: out,
                                progress: reporter(range: 0.05...1))
        update(id) {
            $0.mix = HSMixInfo(master: r.master, stems: r.stems, chapters: r.chapters.map { HSChapterMark(title: $0.title, start: $0.start) },
                               duration: r.duration, loudness: r.loudness, speechToBackground: r.speechToBackground)
            $0.set(.mix, .done)
        }
    }
}
