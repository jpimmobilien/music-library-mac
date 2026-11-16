import XCTest
@testable import MLStudio

final class HoerspielTests: XCTestCase {
    func testFigureIDNormalization() {
        XCTAssertEqual(HSFigure.normalizedID("Lena"), "LENA")
        XCTAssertEqual(HSFigure.normalizedID("Erzähler"), "ERZÄHLER")
        XCTAssertEqual(HSFigure.normalizedID("Herr Groß"), "HERRGROSS")
        XCTAssertEqual(HSFigure.normalizedID("  "), "FIGUR")
        XCTAssertTrue(HSFigure(id: "erzähler", name: "Erzähler").isNarrator)
    }

    func testPlanMatchesEngine() {
        // muss zu plan_size() in hs_story.py passen
        XCTAssertEqual(HSPlan.size(minutes: 10).chapters, 1)
        XCTAssertEqual(HSPlan.size(minutes: 10).scenesPerChapter, 6)
        XCTAssertEqual(HSPlan.size(minutes: 60).chapters, 5)
        XCTAssertEqual(HSPlan.size(minutes: 60).scenesPerChapter, 7)
        XCTAssertEqual(HSPlan.size(minutes: 5).chapters, 1)
        XCTAssertEqual(HSPlan.size(minutes: 5).scenesPerChapter, 3)
        XCTAssertEqual(HSPlan.targetWords(minutes: 10), 1190)
    }

    func testSceneVersionsKeepOldText() {
        var scene = HSScene(chapter: 1, number: 1, title: "Bahnhof",
                            items: [HSScriptItem(kind: .line, speaker: "LENA", text: "Hörst du das?")])
        scene.summary = "alt"
        scene.replaceItems([HSScriptItem(kind: .line, speaker: "MAX", text: "Nein, gar nichts.")], note: "neu geschrieben")
        XCTAssertEqual(scene.items.first?.speaker, "MAX")
        XCTAssertEqual(scene.versions.count, 1)
        XCTAssertEqual(scene.versions[0].items.first?.text, "Hörst du das?")
        scene.restore(versionAt: 0)
        XCTAssertEqual(scene.items.first?.speaker, "LENA")
        XCTAssertEqual(scene.versions.count, 2, "Wiederherstellen sichert die bisherige Fassung")
        XCTAssertEqual(scene.summary, "alt")
    }

    func testProductionWordsAndSpeakers() {
        var p = HSProduction(mode: .hoerspiel, prompt: "Krimi", targetMinutes: 10)
        p.figures = [HSFigure(id: "LENA", name: "Lena"), HSFigure(id: "ERZÄHLER", name: "Erzähler"), HSFigure(id: "MAX", name: "Max")]
        p.scenes = [HSScene(chapter: 1, number: 1, title: "A", items: [
            HSScriptItem(kind: .atmo, text: "Wind", english: "wind"),
            HSScriptItem(kind: .line, speaker: "LENA", text: "Hörst du das da drüben?"),
            HSScriptItem(kind: .line, speaker: "ERZÄHLER", text: "Es war still."),
            HSScriptItem(kind: .line, speaker: "MAX", text: "Nein."),
        ])]
        XCTAssertEqual(p.spokenWords, 9)
        XCTAssertEqual(p.speakingFigures.map(\.id), ["ERZÄHLER", "LENA", "MAX"])
        p.set(.voices, .done)
        p.set(.story, .done)
        p.markChanged(scene: p.scenes[0].id)
        XCTAssertEqual(p.state(.voices), .outdated)
        XCTAssertEqual(p.state(.story), .done, "Eine Szenenänderung macht die Geschichte nicht ungültig")
    }

    func testProductionCodableRoundTrip() throws {
        var p = HSProduction(mode: .hoerbuch, prompt: "Märchen", targetMinutes: 5)
        p.set(.story, .done)
        p.figures = [HSFigure(id: "ERZÄHLER", name: "Erzähler", voiceEN: "calm narrator")]
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(HSProduction.self, from: data)
        XCTAssertEqual(back.state(.story), .done)
        XCTAssertEqual(back.figures.first?.voiceEN, "calm narrator")
        XCTAssertEqual(back.mode, .hoerbuch)
    }

    func testVoiceSettingsDescriptions() {
        let s = HSVoiceSettings(gender: .male, age: .teen, pitch: 1, timbre: .bright, tempo: 1, articulation: .natural, mood: .cheeky)
        XCTAssertTrue(s.descriptionEN.hasPrefix("A teenage boy, about 14 years old"))
        XCTAssertTrue(s.descriptionEN.contains("high-pitched"))
        XCTAssertTrue(s.descriptionEN.contains("native German"))
        XCTAssertTrue(s.descriptionDE.contains("Jugendlich"))
        let clamped = HSVoiceSettings(pitch: 9, tempo: -7)
        XCTAssertEqual(clamped.pitch, 2)
        XCTAssertEqual(clamped.tempo, -2)
        let accent = HSVoiceSettings(accent: "leicht bairisch")
        XCTAssertTrue(accent.descriptionEN.contains("leicht bairisch"))
    }

    func testStyleProfileNeverSpeaks() {
        var v = HSVoiceProfile(name: "Stil S1", kind: .styleOnly)
        v.referenceFile = "irgendwas.wav"
        XCTAssertFalse(v.canSpeak, "Ein Stilprofil ist nur eine Beschreibung")
        var d = HSVoiceProfile(name: "Lena", kind: .designed)
        XCTAssertFalse(d.canSpeak)
        d.referenceFile = "lena.wav"
        XCTAssertTrue(d.canSpeak)
    }

    func testAuthorizedVoiceNeedsVerifiedConsent() {
        var v = HSVoiceProfile(name: "Opa Heinz", kind: .authorized)
        v.referenceFile = "heinz.wav"
        XCTAssertFalse(v.canSpeak, "ohne Einwilligung keine Nachbildung")
        var c = HSConsent(personName: "Heinz Berger", scope: "Familienhörspiel", grantedTo: "Jan", recordingFile: "einwilligung.wav")
        c.similarity = 0.71
        c.similarityThreshold = 0.6
        c.transcript = "Ich, Heinz Berger, erlaube, dass meine Stimme in der Music Library von Jan nachgebildet wird."
        c.transcriptMatches = HSConsent.transcriptMatches(c.transcript!, person: c.personName)
        v.consent = c
        XCTAssertFalse(v.canSpeak, "noch nicht als geprüft markiert")
        v.consent?.verified = Date()
        XCTAssertTrue(v.canSpeak)
        v.consent?.similarity = 0.3
        XCTAssertFalse(v.canSpeak, "andere Stimme in der Einwilligung")
    }

    func testConsentTranscriptCheck() {
        XCTAssertTrue(HSConsent.transcriptMatches("ich heinz berger erlaube dass meine stimme nachgebildet wird", person: "Heinz Berger"))
        XCTAssertFalse(HSConsent.transcriptMatches("ich erlaube dass meine stimme nachgebildet wird", person: "Heinz Berger"),
                       "Name fehlt")
        XCTAssertFalse(HSConsent.transcriptMatches("Heinz Berger sagt hallo", person: "Heinz Berger"), "keine Einwilligung")
        XCTAssertTrue(HSConsent.statement(person: "A", grantedTo: "B").contains("erlaube"))
    }

    func testConceptAndSceneFromEngineJSON() throws {
        let conceptJSON = """
        {"titel": "Der Nachtzug", "logline": "Vier Freunde und ein Geisterzug", "epoche_ort": "Sommer 1984",
         "figuren": [{"id": "ERZÄHLER", "name": "Erzähler", "rolle": "Erzähler", "voice_en": "calm"},
                     {"id": "Lena", "name": "Lena", "rolle": "Hauptfigur", "alter": 14, "geschlecht": "w", "voice_en": "girl"}],
         "kapitel": [{"nr": 1, "titel": "Der Bahnhof", "szenen": [
            {"nr": 1, "titel": "Ankunft", "ort": "Bahnsteig", "raum": "Draußen", "figuren": ["LENA"], "inhalt": "x", "atmo_en": "wind"},
            {"nr": 2, "titel": "Stellwerk", "raum": "", "inhalt": "y"}]}]}
        """
        let c = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(conceptJSON.utf8)) as? [String: Any])
        var p = HSProduction(mode: .hoerspiel, prompt: "Krimi")
        HSJSON.apply(concept: c, to: &p)
        XCTAssertEqual(p.title, "Der Nachtzug")
        XCTAssertEqual(p.figures.map(\.id), ["ERZÄHLER", "LENA"])
        XCTAssertEqual(p.figures[1].age, 14)
        XCTAssertEqual(p.scenes.count, 2)
        XCTAssertEqual(p.scenes[0].room, "draußen")
        XCTAssertEqual(p.scenes[1].room, "zimmer", "fehlender Raum → Zimmer")

        let sceneJSON = """
        {"items": [{"type": "atmo", "de": "Wind", "en": "wind"},
                   {"type": "line", "speaker": "LENA", "emotion": "flüsternd", "text": "Hörst du das?"},
                   {"type": "line", "speaker": "PETRA", "emotion": "", "text": "Ich bin neu."},
                   {"type": "pause", "seconds": 2},
                   {"type": "sfx", "de": "Tür", "en": "door"}], "summary": "Lena hört etwas."}
        """
        let sc = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(sceneJSON.utf8)) as? [String: Any])
        HSJSON.apply(scene: sc, at: 0, to: &p)
        XCTAssertEqual(p.scenes[0].items.count, 5)
        XCTAssertEqual(p.scenes[0].items[1].emotion, "flüsternd")
        XCTAssertNil(p.scenes[0].items[2].emotion)
        XCTAssertEqual(p.scenes[0].items[3].seconds, 2)
        XCTAssertEqual(p.scenes[0].summary, "Lena hört etwas.")
        XCTAssertTrue(p.figure("PETRA")?.addedByModel ?? false, "neue Nebenfigur wird ergänzt und gekennzeichnet")
        XCTAssertTrue(p.scenes[0].versions.isEmpty, "erste Fassung braucht keine Sicherung")
        HSJSON.apply(scene: sc, at: 0, to: &p)
        XCTAssertEqual(p.scenes[0].versions.count, 1, "Neuschreiben sichert die vorige Fassung")

        let story = HSJSON.story(p)
        let scenes = try XCTUnwrap(story["scenes"] as? [[String: Any]])
        let first = try XCTUnwrap(scenes[0]["items"] as? [[String: Any]])
        XCTAssertEqual(first[1]["type"] as? String, "line")
        XCTAssertEqual(first[4]["en"] as? String, "door")
        XCTAssertEqual(HSJSON.lineKey(scene: 0, item: 1), "s01_001")
        XCTAssertEqual(HSJSON.lineKey(scene: 11, item: 123), "s12_123")
        // Rundreise Konzept: Szenen behalten ihre Kapitelzuordnung
        let back = HSJSON.concept(p)
        let chapters = try XCTUnwrap(back["kapitel"] as? [[String: Any]])
        XCTAssertEqual((chapters[0]["szenen"] as? [[String: Any]])?.count, 2)
    }

    func testHardwareRecommendation() {
        XCTAssertEqual(HSHardware.storyModel(memoryGB: 48), HSModel.storyLarge)
        XCTAssertEqual(HSHardware.storyModel(memoryGB: 24), HSModel.storyMedium)
        XCTAssertEqual(HSHardware.storyModel(memoryGB: 8), HSModel.storySmall)
        XCTAssertNil(HSHardware.storyModel(memoryGB: 4))
        XCTAssertFalse(HSHardware.support(machine: "x86_64", translated: false, memoryGB: 64, macOSMajor: 15).isUsable)
        if case .supported = HSHardware.support(machine: "arm64", translated: false, memoryGB: 48, macOSMajor: 26) {} else {
            XCTFail("M5 Pro mit 48 GB muss voll unterstützt sein")
        }
    }

    func testStoreRoundTripAndBackup() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HSStore(root: dir)
        var p = HSProduction(mode: .hoerspiel, title: "Der Nachtzug", prompt: "Krimi")
        try store.save(p)
        p.title = "Der Nachtzug (neu)"
        try store.save(p)
        let loaded = store.loadProductions()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].title, "Der Nachtzug (neu)")
        let backup = store.folder(for: p).appendingPathComponent("produktion.vorher.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path), "vorige Fassung bleibt als Sicherung")

        var v = HSVoiceProfile(name: "Lena", kind: .designed, settings: HSVoiceSettings(gender: .female, age: .teen))
        v.referenceFile = "lena.wav"
        try store.saveVoices([v])
        XCTAssertEqual(store.loadVoices().first?.settings.age, .teen)

        let profile: [String: Any] = [
            "speakers": [["id": "S1", "role_guess": "Erzähler (geschätzt)", "share": 0.3, "description_de": "männlich", "voice_en": "A male voice"],
                         ["id": "S2", "role_guess": "Hauptfigur (geschätzt)", "share": 0.25, "description_de": "hoch", "voice_en": "A teen"]],
            "recording": ["bandwidth_hz": 12000, "noise_floor_dbfs": -55],
            "dialog": ["turns_per_minute": 14.0], "music_bridges": 6, "summary_de": "Zusammenfassung"]
        let ref = HSReference.from(profile: profile, name: "Kassette 1", sources: ["folge1.mp3"])
        XCTAssertEqual(ref.speakers.count, 2)
        XCTAssertEqual(ref.retroSuggested, 1.0)
        XCTAssertTrue(ref.styleHint.contains("schnelle Wortwechsel"))
        XCTAssertTrue(ref.styleHint.contains("Musikbrücken"))
        try store.save(ref)
        XCTAssertEqual(store.loadReferences().first?.name, "Kassette 1")
    }

    func testPronunciationAndFingerprints() {
        XCTAssertEqual(HSText.replaceWord("TKKG", with: "Te Ka Ka Ge", in: "Die TKKG-Bande und TKKGs Freunde"),
                       "Die Te Ka Ka Ge-Bande und TKKGs Freunde")
        XCTAssertEqual(HSText.replaceWord("Max", with: "Maks", in: "Max und Maxi sehen Max."), "Maks und Maxi sehen Maks.")
        var p = HSProduction(mode: .hoerspiel, prompt: "x")
        p.figures = [HSFigure(id: "LENA", name: "Lena")]
        p.scenes = [HSScene(chapter: 1, number: 1, title: "A", items: [HSScriptItem(kind: .line, speaker: "LENA", text: "Hallo Kai!")])]
        XCTAssertNil(p.fingerprint(of: p.scenes[0].items[0]), "ohne Stimme kein Fingerabdruck")
        p.cast["LENA"] = HSCast(referenceFile: "stimmen/LENA.wav", referenceText: "Referenz", instruct: "girl", seed: 1)
        let f1 = p.fingerprint(of: p.scenes[0].items[0])
        XCTAssertNotNil(f1)
        XCTAssertEqual(p.linesNeedingVoice.count, 1)
        p.scenes[0].items[0].audioFile = "zeilen/a.wav"
        p.scenes[0].items[0].audioFingerprint = f1
        XCTAssertTrue(p.linesNeedingVoice.isEmpty)
        p.pronunciations["Kai"] = "Kei"
        XCTAssertEqual(p.spokenText("Hallo Kai!"), "Hallo Kei!")
        XCTAssertEqual(p.linesNeedingVoice.count, 1, "neue Aussprache → Zeile neu sprechen")
        p.pronunciations = [:]
        XCTAssertTrue(p.linesNeedingVoice.isEmpty)
        p.cast["LENA"]?.seed = 2
        XCTAssertEqual(p.linesNeedingVoice.count, 1, "andere Stimme → Zeile neu sprechen")
        XCTAssertEqual(HSHash.string("abc"), HSHash.string("abc"))
        XCTAssertEqual(HSHash.string("abc").count, 16)
    }

    func testExportPlan() {
        var p = HSProduction(mode: .hoerspiel, title: "Der Nachtzug: Teil 1", prompt: "x")
        p.chapters = [HSChapter(number: 1, title: "Ankunft"), HSChapter(number: 2, title: "Finale")]
        p.scenes = [HSScene(chapter: 1, number: 1, title: "A"), HSScene(chapter: 1, number: 2, title: "B"), HSScene(chapter: 2, number: 1, title: "C")]
        XCTAssertTrue(HSExportPlan.items(for: p, scope: .whole).isEmpty, "ohne Mischung nichts zu exportieren")
        p.mix = HSMixInfo(master: "mix/master.wav", stems: ["Musik": "mix/spuren/Musik.wav", "Erzähler": "mix/spuren/Erzähler.wav"],
                          chapters: [HSChapterMark(title: "Szene 1: A", start: 0), HSChapterMark(title: "Szene 2: B", start: 100),
                                     HSChapterMark(title: "Szene 3: C", start: 250)], duration: 400, loudness: -16, speechToBackground: 14)
        let whole = HSExportPlan.items(for: p, scope: .whole)
        XCTAssertEqual(whole.first?.fileName, "Der Nachtzug- Teil 1")
        let chapters = HSExportPlan.items(for: p, scope: .chapters)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].trim, TrimRange(start: 0, end: 250))
        XCTAssertEqual(chapters[1].trim, TrimRange(start: 250, end: 400))
        XCTAssertEqual(chapters[1].title, "Kapitel 2: Finale")
        let scenes = HSExportPlan.items(for: p, scope: .scenes)
        XCTAssertEqual(scenes.map(\.trim?.end), [100, 250, 400])
        XCTAssertEqual(scenes[2].trackNumber, 3)
        XCTAssertEqual(HSExportPlan.items(for: p, scope: .stems).count, 2)
    }
}
