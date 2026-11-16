import Foundation
import AppKit
import MLCore
import MLStore
import MLStudio
import StudioEngine

/// Abnahmeprüfung der KI-Hörbücher mit dem echten Ablauf der App (nur mit `--hoerspiel-e2e <ordner>`, Prüfstand):
/// Einrichtung wie „Jetzt einrichten“, Hörspiel erstellen (Geschichte → Lektorat → Sprecher → Stimmen → Geräusche →
/// Mischung), Editor-Funktionen (Replik neu formulieren und neu sprechen, Mehrspur ändern und neu abmischen), Export
/// (MP3 mit Kapiteln, Kapitel einzeln), Hörbuch, Stimmenstudio, Referenzanalyse. Alles in eigenen Ordnern unter
/// dem Ausgabeordner – Bibliothek und Nutzerdaten bleiben unberührt. Ergebnis: `e2e.json` und `e2e.log`.
///
/// Umgebung: `HS_E2E_STORY` (Repo des Geschichtenmodells, Standard Qwen3.5 4B für kleine Prüfrechner),
/// `HS_E2E_MINUTES` (Länge, Standard 3), `HS_E2E_ANALYSIS` (1 = Referenzanalyse prüfen, Standard 1).
@MainActor
enum HoerspielE2E {
    static var isRequested: Bool { CommandLine.arguments.contains("--hoerspiel-e2e") }

    static var outputDirectory: URL {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--hoerspiel-e2e"), i + 1 < args.count {
            return URL(fileURLWithPath: args[i + 1], isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("hoerspiel-e2e", isDirectory: true)
    }

    static func makeModel() -> AppModel {
        AppModel(store: try! LibraryStore.inMemory())
    }

    private struct Check: Codable {
        let name: String
        let ok: Bool
        let detail: String
        let seconds: Double
    }

    private static var checks: [Check] = []
    private static var logHandle: FileHandle?
    private static var started = Date()

    static func run(model: AppModel) {
        Task { @MainActor in
            let code = await perform()
            log("Fertig: \(checks.filter(\.ok).count) von \(checks.count) Prüfungen bestanden")
            exit(code)
        }
    }

    // MARK: Ablauf

    private static func perform() async -> Int32 {
        let env = ProcessInfo.processInfo.environment
        let out = outputDirectory
        let fm = FileManager.default
        try? fm.createDirectory(at: out, withIntermediateDirectories: true)
        fm.createFile(atPath: out.appendingPathComponent("e2e.log").path, contents: nil)
        logHandle = try? FileHandle(forWritingTo: out.appendingPathComponent("e2e.log"))
        defer { save(out) }

        let storyRepo = env["HS_E2E_STORY"] ?? HSModel.storySmall.repo
        let minutes = Double(env["HS_E2E_MINUTES"] ?? "3") ?? 3
        let scripts = Bundle.main.resourceURL?.appendingPathComponent("HoerspielEngine", isDirectory: true)
            ?? URL(fileURLWithPath: "/nonexistent")
        let installer = HSInstaller(base: out.appendingPathComponent("Umgebung", isDirectory: true), scripts: scripts)
        let defaults = UserDefaults(suiteName: "hoerspiel-e2e-\(UUID().uuidString)") ?? .standard
        let hs = HoerspielModel(demo: false, support: .limited(recommendedLM: storyRepo, reason: "Prüfstand"), installer: installer,
                                root: out.appendingPathComponent("KI-Hörspiele", isDirectory: true), defaults: defaults)
        log("Geschichtenmodell: \(storyRepo), Länge \(minutes) min, Skripte: \(scripts.path)")

        // 1. Einrichtung wie „Jetzt einrichten“ + Geräusch- und Analysemodelle wie in den Einstellungen
        var t = Date()
        hs.installEverything()
        await waitUntil(timeout: 3 * 3600) { !hs.installing }
        check("Einrichtung (Umgebung, Geschichte, Stimmen)", hs.setup == .ready, "\(hs.setup) \(hs.installTask)", since: t)
        guard hs.setup == .ready else { return 1 }
        for m in [HSModel.sfx] + (env["HS_E2E_ANALYSIS"] == "0" ? [] : HSModel.analysis) {
            t = Date()
            hs.download(m)
            await waitUntil(timeout: 3600) { !hs.installing }
            check("Modell geladen: \(m.title)", hs.isInstalled(m), "\(hs.installTask)", since: t)
        }

        // 2. Hörspiel erstellen (Musik nur, wenn KI-Musik eingerichtet ist – hier nicht)
        t = Date()
        hs.drafts[.hoerspiel] = HoerspielModel.Draft(
            prompt: "Ein Jugendkrimi im Sommer 1984: Drei Freunde entdecken nachts Licht in einem stillgelegten Stellwerk am Bahnhof. "
                + "Spannend, mit Humor und einer überraschenden, aber logischen Auflösung.",
            minutes: minutes, characters: [], retro: 0.6, useMusic: false, useSFX: true)
        hs.create(.hoerspiel)
        await waitUntil(timeout: 4 * 3600) { !hs.isWorking }
        guard var p = hs.productions.first(where: { $0.mode == .hoerspiel }) else {
            check("Hörspiel erstellt", false, "keine Produktion, Phase \(hs.phase)", since: t)
            return 1
        }
        let failed: String? = { if case .failed(let m) = hs.phase { return m } else { return nil } }()
        check("Hörspiel erstellt", failed == nil && p.mix != nil, failed ?? "Notiz: \(hs.notice ?? "–")", since: t)
        check("Geschichte geschrieben", p.state(.story) == .done && p.scenes.count > 1 && p.scenes.allSatisfy { !$0.items.isEmpty },
              "\(p.title): \(p.scenes.count) Szenen, \(p.spokenWords) Wörter, \(p.figures.count) Figuren", since: t)
        check("Lektorat ausgeführt", p.review != nil,
              "\(p.review?.problems.count ?? -1) Hinweise, überarbeitet: \(p.review?.revised ?? [])", since: t)
        check("Alle Zeilen gesprochen", p.linesNeedingVoice.isEmpty, "fehlend: \(p.linesNeedingVoice.count)", since: t)
        check("Geräusche erzeugt", !p.sfxFiles.isEmpty && p.sfxFiles.values.allSatisfy { fm.fileExists(atPath: $0) },
              "\(p.sfxFiles.count) Geräusche/Atmosphären", since: t)
        if let mix = p.mix {
            let master = hs.file(mix.master, in: p)
            check("Mischung", fm.fileExists(atPath: master.path) && mix.duration > 30 && abs((mix.loudness ?? 0) + 16) < 1.5,
                  String(format: "%.1f s, %.1f LUFS, Sprache/Hintergrund %.1f dB, ", mix.duration, mix.loudness ?? .nan,
                         mix.speechToBackground ?? .nan) + "\(mix.chapters.count) Kapitel", since: t)
        }
        try? fm.copyItem(at: hs.folder(p).appendingPathComponent("produktion.json"), to: out.appendingPathComponent("hoerspiel-produktion.json"))

        // 3. Editor: eine Replik neu formulieren und neu sprechen
        if let pos = firstLine(p, notNarrator: true) {
            let (si, ii) = pos
            t = Date()
            let before = p.scenes[si].items[ii].text
            hs.rewriteLine(p.id, scene: si, item: ii, hint: "kürzer und frecher")
            await waitUntil(timeout: 1800) { !hs.isWorking }
            p = hs.production(p.id) ?? p
            let after = p.scenes[si].items[ii].text
            check("Replik neu formuliert", after != before && !after.isEmpty, "„\(before)“ → „\(after)“", since: t)
            t = Date()
            hs.regenerateLine(p.id, scene: si, item: ii)
            await waitUntil(timeout: 1800) { !hs.isWorking }
            p = hs.production(p.id) ?? p
            let item = p.scenes[si].items[ii]
            check("Replik neu gesprochen", item.audioFile != nil && item.audioFingerprint == p.fingerprint(of: item),
                  item.audioFile ?? "keine Datei", since: t)
            t = Date()
            hs.runStep(.mix, p.id)
            await waitUntil(timeout: 1800) { !hs.isWorking }
            p = hs.production(p.id) ?? p
            check("Neu abgemischt nach Änderung", p.state(.mix) == .done, "\(p.mix?.duration ?? 0) s", since: t)
        }

        // 4. Mehrspur: Atmo stumm, ersten Sprecher-Clip um 0,5 s verschieben, neu abmischen
        if var tl = hs.loadTimeline(p) {
            t = Date()
            let oldDate = p.mix?.date
            tl.setTrack("Atmo") { $0.mute = true }
            if let c = tl.clips.first(where: { $0.track.hasPrefix("Sprecher") }) { tl.move(c.id, to: c.start + 0.5) }
            hs.renderTimeline(p.id, tl)
            await waitUntil(timeout: 1800) { !hs.isWorking }
            p = hs.production(p.id) ?? p
            check("Mehrspur bearbeitet und neu abgemischt", p.mix?.date != oldDate && hs.loadTimeline(p)?.tracks.first { $0.name == "Atmo" }?.mute == true,
                  "\(tl.clips.count) Clips, \(tl.tracks.count) Spuren", since: t)
        } else {
            check("Mehrspur: Zeitleiste vorhanden", false, "keine zeitleiste.json", since: Date())
        }

        // 5. Export: ganze Produktion als MP3 mit Kapiteln, Kapitel einzeln als M4A
        let exportDir = out.appendingPathComponent("Export", isDirectory: true)
        try? fm.createDirectory(at: exportDir, withIntermediateDirectories: true)
        for (scope, format) in [(HSExportScope.whole, StudioFormat.mp3), (.chapters, .m4a)] {
            t = Date()
            do {
                let files = try await hs.export(p, scope: scope, format: format, bitrate: 192,
                                                metadata: StudioMetadata(title: p.title, artist: "KI-Hörspiel"), to: exportDir) { _ in }
                let sizes = files.map { (try? Data(contentsOf: $0).count) ?? 0 }
                check("Export \(scope) als \(format.fileExtension)", !files.isEmpty && sizes.allSatisfy { $0 > 10_000 },
                      files.map(\.lastPathComponent).joined(separator: ", "), since: t)
            } catch {
                check("Export \(scope) als \(format.fileExtension)", false, StudioModel.message(error), since: t)
            }
        }

        // 6. Hörbuch (Erzähler, ohne Geräusche und Musik)
        t = Date()
        hs.drafts[.hoerbuch] = HoerspielModel.Draft(prompt: "Ein kurzes Märchen über eine Uhrmacherin, deren Uhren die Zeit anhalten können.",
                                                    minutes: 2, narration: "märchenhaft", useMusic: false, useSFX: false)
        hs.create(.hoerbuch)
        await waitUntil(timeout: 3 * 3600) { !hs.isWorking }
        if let b = hs.productions.first(where: { $0.mode == .hoerbuch }) {
            check("Hörbuch erstellt", b.mix != nil && b.linesNeedingVoice.isEmpty,
                  "\(b.title): \(b.spokenWords) Wörter, \(String(format: "%.0f", b.mix?.duration ?? 0)) s", since: t)
        } else {
            check("Hörbuch erstellt", false, "\(hs.phase)", since: t)
        }

        // 7. Stimmenstudio: Stimme aus Einstellungen entwerfen
        t = Date()
        let voicesBefore = hs.voices.count
        hs.designVoice(name: "Prüfstimme", settings: HSVoiceSettings(gender: .female, age: .senior, pitch: 0, timbre: .warm, tempo: 0, mood: .mysterious),
                       custom: nil)
        await waitUntil(timeout: 1800) { !hs.isWorking }
        let v = hs.voices.first
        check("Stimme entworfen", hs.voices.count == voicesBefore + 1 && v?.referenceFile.map { fm.fileExists(atPath: hs.store.voicesDir.appendingPathComponent($0).path) } == true,
              v?.referenceText ?? "–", since: t)

        // 8. Referenzanalyse der eigenen Mischung (Sprecher, Text, Klang → Stilprofile)
        if env["HS_E2E_ANALYSIS"] != "0", let mix = p.mix {
            t = Date()
            hs.analyzeReference(files: [hs.file(mix.master, in: p)], name: "Eigene Produktion")
            await waitUntil(timeout: 3600) { !hs.isWorking }
            if let r = hs.references.first {
                check("Referenz analysiert", r.speakers.count >= 2 && !r.summary.isEmpty, r.summary.prefix(600).description, since: t)
                hs.createStyleProfiles(from: r)
                await waitUntil(timeout: 60) { !hs.isWorking }
                let styles = hs.voices.filter { $0.kind == .styleOnly }
                check("Stilprofile angelegt (können nicht sprechen)", !styles.isEmpty && styles.allSatisfy { !$0.canSpeak },
                      "\(styles.count) Profile", since: t)
            } else {
                check("Referenz analysiert", false, "\(hs.phase)", since: t)
            }
        }
        hs.engine?.shutdown()
        return checks.allSatisfy(\.ok) ? 0 : 1
    }

    // MARK: Hilfen

    private static func firstLine(_ p: HSProduction, notNarrator: Bool) -> (Int, Int)? {
        for (si, s) in p.scenes.enumerated() {
            for (ii, it) in s.items.enumerated() where it.kind == .line && (!notNarrator || it.speaker != HSFigure.narratorID) {
                return (si, ii)
            }
        }
        return nil
    }

    private static func waitUntil(timeout: TimeInterval, _ done: @MainActor () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !done() && Date() < end {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String, since: Date) {
        let c = Check(name: name, ok: ok, detail: detail, seconds: (Date().timeIntervalSince(since) * 10).rounded() / 10)
        checks.append(c)
        log("\(ok ? "OK  " : "FEHLER") \(name) (\(Int(c.seconds)) s): \(detail)")
        save(outputDirectory)
    }

    private static func log(_ text: String) {
        let line = "[Hörspiel-E2E +\(Int(Date().timeIntervalSince(started))) s] \(text)\n"
        FileHandle.standardError.write(Data(line.utf8))
        logHandle?.write(Data(line.utf8))
    }

    private static func save(_ out: URL) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(checks) { try? data.write(to: out.appendingPathComponent("e2e.json")) }
    }
}
