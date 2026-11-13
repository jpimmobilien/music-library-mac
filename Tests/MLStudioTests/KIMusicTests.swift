import XCTest
@testable import MLStudio

final class KIMusicTests: XCTestCase {
    func testHardwareSupport() {
        XCTAssertEqual(KIHardware.support(machine: "x86_64", translated: false, memoryGB: 16, macOSMajor: 15).isUsable, false)
        XCTAssertEqual(KIHardware.support(machine: "arm64", translated: false, memoryGB: 48, macOSMajor: 26),
                       .supported(recommendedLM: "acestep-5Hz-lm-4B"))
        XCTAssertEqual(KIHardware.support(machine: "arm64", translated: false, memoryGB: 32, macOSMajor: 15),
                       .supported(recommendedLM: "acestep-5Hz-lm-1.7B"))
        if case .limited(let lm, _) = KIHardware.support(machine: "arm64", translated: false, memoryGB: 16, macOSMajor: 15) {
            XCTAssertEqual(lm, "acestep-5Hz-lm-0.6B")
        } else { XCTFail("16 GB: eingeschränkt") }
        if case .limited(let lm, _) = KIHardware.support(machine: "arm64", translated: false, memoryGB: 8, macOSMajor: 15) {
            XCTAssertNil(lm)
        } else { XCTFail("8 GB: eingeschränkt ohne Sprachmodell") }
        XCTAssertFalse(KIHardware.support(machine: "arm64", translated: false, memoryGB: 48, macOSMajor: 13).isUsable)
        // Intel-Prozess unter Rosetta auf einem Apple-Chip: die Hardware kann es
        XCTAssertTrue(KIHardware.support(machine: "x86_64", translated: true, memoryGB: 48, macOSMajor: 26).isUsable)
    }

    func testLanguagesMatchACEStep() {
        let ids = KILanguage.all.map(\.id)
        XCTAssertEqual(ids.count, 50, "VALID_LANGUAGES von ACE-Step ohne „unknown“")
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Array(ids.prefix(7)), ["de", "en", "fr", "es", "it", "pt", "nl"])
        XCTAssertEqual(KILanguage.named("de")?.name, "Deutsch")
    }

    func testRequestValidationAndEngineParams() {
        var r = KIGenerationRequest(prompt: "  ", lyricsMode: .instrumental)
        XCTAssertNotNil(r.problem)
        r.prompt = "Melancholischer Synthwave, warme Synthesizer, keine Vocals"
        XCTAssertNil(r.problem)
        var p = r.engineParams()
        XCTAssertEqual(p["lyrics"], .string("[Instrumental]"))
        XCTAssertEqual(p["instrumental"], .bool(true))
        XCTAssertEqual(p["duration"], .double(120))
        XCTAssertEqual(p["thinking"], .bool(true))
        XCTAssertEqual(p["inference_steps"], .int(8))
        XCTAssertNil(p["bpm"])

        r.lyricsMode = .own
        XCTAssertNotNil(r.problem, "eigener Text fehlt")
        r.lyrics = "[Verse]\nDie Sonne sinkt"
        r.language = "de"
        r.bpm = 92
        r.key = "A minor"
        r.quality = .fast
        XCTAssertNil(r.problem)
        p = r.engineParams()
        XCTAssertEqual(p["vocal_language"], .string("de"), "deutscher Text bleibt deutsch – keine Übersetzung")
        XCTAssertEqual(p["lyrics"], .string("[Verse]\nDie Sonne sinkt"))
        XCTAssertEqual(p["bpm"], .int(92))
        XCTAssertEqual(p["keyscale"], .string("A minor"))
        XCTAssertEqual(p["thinking"], .bool(false))
        XCTAssertEqual(r.engineParams(lyricsOverride: "neu")["lyrics"], .string("neu"))

        r.duration = 601
        XCTAssertNotNil(r.problem)
        r.duration = 600
        r.variations = 5
        XCTAssertNotNil(r.problem)
        XCTAssertEqual(KIQuality.high.ditModel, "acestep-v15-xl-turbo")
        XCTAssertEqual(KIQuality.balanced.ditModel, "acestep-v15-turbo")
    }

    func testEngineParamsEncodeAsPlainJSON() throws {
        let p: [String: KIValue] = ["a": .int(3), "b": .bool(false), "c": .string("x"), "d": .double(1.5)]
        let data = try JSONEncoder().encode(p)
        let back = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(back?["a"] as? Int, 3)
        XCTAssertEqual(back?["b"] as? Bool, false)
        XCTAssertEqual(back?["c"] as? String, "x")
        XCTAssertEqual(back?["d"] as? Double, 1.5)
        XCTAssertEqual(try JSONDecoder().decode([String: KIValue].self, from: data), p)
    }

    func testCreationsIndexAndTitles() {
        XCTAssertEqual(KICreation.suggestedTitle(from: "Erstelle einen melancholischen Synthwave-Song im Stil der 1980er-Jahre. Warme Synthesizer"),
                       "Melancholischen Synthwave-Song im Stil der 1980er-Jahre")
        XCTAssertEqual(KICreation.suggestedTitle(from: "  "), "Neue Kreation")
        var index = KICreationIndex()
        let a = KICreation(title: "Nachtfahrt", kind: .instrumental, file: "a.flac", prompt: "Synthwave", genre: "Synthwave",
                           model: "acestep-v15-turbo", modelVersion: "1.5")
        var b = KICreation(title: "Sommerabend", kind: .song, file: "b.flac", prompt: "Deutscher Pop", model: "acestep-v15-turbo", modelVersion: "1.5")
        b.favorite = true
        index.add(a)
        index.add(b)
        XCTAssertEqual(index.items.map(\.title), ["Sommerabend", "Nachtfahrt"])
        XCTAssertEqual(index.filtered(.instrumentals).map(\.title), ["Nachtfahrt"])
        XCTAssertEqual(index.filtered(.favorites).map(\.title), ["Sommerabend"])
        XCTAssertEqual(index.filtered(.all, query: "synth").map(\.title), ["Nachtfahrt"])
        index.add(a)
        XCTAssertEqual(index.items.count, 2, "gleiche Kreation ersetzt den alten Eintrag")
        index.remove(a.id)
        XCTAssertEqual(index.items.map(\.title), ["Sommerabend"])
    }

    func testEstimate() {
        let r = KIGenerationRequest(prompt: "x", duration: 180, variations: 2, quality: .balanced)
        XCTAssertEqual(KIEstimate.seconds(for: r, secondsPerAudioSecond: 0.3, planningSeconds: 10), 10 + 180 * 0.3 * 2, accuracy: 0.001)
        XCTAssertEqual(KIEstimate.learn(nil, measured: 0.5), 0.5)
        XCTAssertEqual(KIEstimate.learn(1.0, measured: 0.0, weight: 0.25), 0.75, accuracy: 0.0001)
        XCTAssertEqual(KIEstimate.text(30), "unter einer Minute")
        XCTAssertEqual(KIEstimate.text(150), "etwa 3 Minuten")
    }
}
