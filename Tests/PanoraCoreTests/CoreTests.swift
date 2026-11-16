import XCTest
@testable import PanoraCore

final class TaskAnalyzerTests: XCTestCase {
    func testCodingRequest() {
        let p = TaskAnalyzer.analyze("Implementiere bitte die Login-Funktion in Kotlin mit Jetpack Compose und einem ViewModel.")
        XCTAssertEqual(p.kind, .coding)
        XCTAssertGreaterThanOrEqual(p.difficulty, 2)
    }

    func testDebuggingWithStacktrace() {
        let text = """
        Die App stürzt ab:
        ```
        java.lang.NullPointerException at MainActivity.kt:42
        ```
        """
        XCTAssertEqual(TaskAnalyzer.analyze(text).kind, .debugging)
    }

    func testAndroidPhases() {
        XCTAssertEqual(TaskAnalyzer.analyze("Analysiere das Projekt und erkläre mir die Codebase").kind, .analysis)
        XCTAssertEqual(TaskAnalyzer.analyze("Entwirf die Architektur mit Modulen und Schichten für die App").kind, .planning)
        XCTAssertEqual(TaskAnalyzer.analyze("Überprüfe die Änderungen in LoginViewModel.kt").kind, .review)
    }

    func testSmallTalkAndContinuation() {
        XCTAssertEqual(TaskAnalyzer.analyze("Hallo!").kind, .smallTalk)
        XCTAssertEqual(TaskAnalyzer.analyze("mach weiter", previous: .coding).kind, .coding)
    }

    func testTranslationAndSummary() {
        XCTAssertEqual(TaskAnalyzer.analyze("Übersetze diesen Absatz ins Englische: Guten Tag").kind, .translation)
        XCTAssertEqual(TaskAnalyzer.analyze("Fasse den folgenden Text in fünf Stichpunkten zusammen").kind, .summarization)
    }

    func testMathExpression() {
        XCTAssertEqual(TaskAnalyzer.analyze("Was ist 17 * 23 + 4?").kind, .math)
    }

    func testLongDocument() {
        let text = "Bitte lies das: " + String(repeating: "Dies ist ein langer Absatz über Verträge. ", count: 1500)
        let p = TaskAnalyzer.analyze(text)
        XCTAssertEqual(p.kind, .longDocument)
        XCTAssertTrue(p.estimatedInputTokens > 12_000)
    }
}

final class RouterTests: XCTestCase {
    let gb: Int64 = 1_000_000_000

    func spec(_ name: String, size: Double, active: Double? = nil, params: Double, coding: Double, general: Double = 7,
              context: Int = 131_072) -> ModelSpec {
        ModelSpec(id: "mlx:\(name)", backend: .mlx, repo: name, displayName: name, family: "Test", parametersB: params,
                  activeParametersB: active, bits: 4, sizeBytes: Int64(size * 1e9), contextLength: context,
                  capabilities: [.chat, .coding], skills: Skills(general: general, coding: coding, reasoning: general, writing: general),
                  license: .apache2)
    }

    var hardware: HardwareSnapshot {
        HardwareSnapshot(totalMemory: 64 * gb, availableMemory: 50 * gb, modelBudget: 45 * gb)
    }

    func testAutoPicksCoder() {
        let coder = spec("coder", size: 20, active: 3, params: 35, coding: 9)
        let writer = spec("writer", size: 18, params: 31, coding: 6, general: 8.5)
        let profile = TaskAnalyzer.analyze("Implementiere die Funktion in Swift und schreibe Unit-Tests dazu")
        let d = ModelRouter.route(RoutingRequest(profile: profile, candidates: [ModelCandidate(spec: writer), ModelCandidate(spec: coder)],
                                                 hardware: hardware))
        XCTAssertEqual(d.chosen?.id, coder.id)
        XCTAssertFalse(d.reasons.isEmpty)
    }

    func testSmallSpecialistBeatsLargeGeneralist() {
        let small = spec("small-coder", size: 8, params: 14, coding: 8.5, general: 6)
        let large = spec("large-general", size: 40, params: 70, coding: 7.0, general: 8.8)
        let profile = TaskAnalyzer.analyze("Schreibe eine Swift-Funktion, die ein Array sortiert")
        let d = ModelRouter.route(RoutingRequest(profile: profile, candidates: [ModelCandidate(spec: large), ModelCandidate(spec: small)],
                                                 hardware: hardware))
        XCTAssertEqual(d.chosen?.id, small.id)
    }

    func testMemoryExclusion() {
        let huge = spec("huge", size: 60, params: 120, coding: 9.5)
        let small = spec("small", size: 5, params: 8, coding: 6)
        let profile = TaskAnalyzer.analyze("Implementiere einen Parser in Swift")
        let d = ModelRouter.route(RoutingRequest(profile: profile, candidates: [ModelCandidate(spec: huge), ModelCandidate(spec: small)],
                                                 hardware: hardware))
        XCTAssertEqual(d.chosen?.id, small.id)
        XCTAssertNotNil(d.scores.first { $0.id == huge.id }?.excluded)
    }

    func testContextWindowExclusion() {
        let shortCtx = spec("short", size: 5, params: 8, coding: 9, context: 8_192)
        let longCtx = spec("long", size: 6, params: 8, coding: 6, context: 131_072)
        let profile = TaskAnalyzer.analyze("Implementiere das")
        let d = ModelRouter.route(RoutingRequest(profile: profile, candidates: [ModelCandidate(spec: shortCtx), ModelCandidate(spec: longCtx)],
                                                 hardware: hardware, neededContextTokens: 20_000))
        XCTAssertEqual(d.chosen?.id, longCtx.id)
    }

    func testManualIsNeverOverridden() {
        let weak = spec("weak", size: 3, params: 4, coding: 4)
        let strong = spec("strong", size: 20, params: 30, coding: 9)
        let profile = TaskAnalyzer.analyze("Implementiere einen Compiler in Swift")
        let d = ModelRouter.route(RoutingRequest(profile: profile, candidates: [ModelCandidate(spec: weak), ModelCandidate(spec: strong)],
                                                 hardware: hardware, mode: .manual, pinnedModelID: weak.id, allowSwitchInManual: false))
        XCTAssertEqual(d.chosen?.id, weak.id)
        XCTAssertNil(d.suggestion)
        // Mit erlaubtem Wechsel: nur ein Vorschlag, gewählt bleibt das manuelle Modell
        let d2 = ModelRouter.route(RoutingRequest(profile: profile, candidates: [ModelCandidate(spec: weak), ModelCandidate(spec: strong)],
                                                  hardware: hardware, mode: .manual, pinnedModelID: weak.id, allowSwitchInManual: true))
        XCTAssertEqual(d2.chosen?.id, weak.id)
        XCTAssertEqual(d2.suggestion?.id, strong.id)
    }

    func testManualUnavailableFailsInsteadOfReplacing() {
        let pinned = spec("pinned", size: 5, params: 8, coding: 7)
        let other = spec("other", size: 5, params: 8, coding: 7)
        let profile = TaskAnalyzer.analyze("Hallo")
        let d = ModelRouter.route(RoutingRequest(profile: profile,
                                                 candidates: [ModelCandidate(spec: pinned, available: false, unavailableReason: "Laufwerk fehlt"),
                                                              ModelCandidate(spec: other)],
                                                 hardware: hardware, mode: .manual, pinnedModelID: pinned.id))
        XCTAssertNil(d.chosen)
        XCTAssertEqual(d.suggestion?.id, other.id)
        XCTAssertNotNil(d.failure)
    }

    func testStickinessAvoidsNeedlessSwitch() {
        let a = spec("a", size: 10, params: 14, coding: 8.0)
        let b = spec("b", size: 10, params: 14, coding: 8.2)
        let profile = TaskAnalyzer.analyze("Implementiere die nächste Funktion in Kotlin")
        let loaded = [LoadedModel(id: a.id, bytes: 11 * gb, lastUsed: Date())]
        let d = ModelRouter.route(RoutingRequest(profile: profile, candidates: [ModelCandidate(spec: a), ModelCandidate(spec: b)],
                                                 hardware: hardware, loaded: loaded, currentModelID: a.id))
        XCTAssertEqual(d.chosen?.id, a.id)
        XCTAssertFalse(d.switched)
    }

    func testSwitchWhenTaskChanges() {
        let coder = spec("coder", size: 10, params: 14, coding: 9, general: 5)
        let writer = ModelSpec(id: "mlx:writer", backend: .mlx, repo: "writer", displayName: "writer", family: "T", parametersB: 14,
                               bits: 4, sizeBytes: 10_000_000_000, contextLength: 131_072, capabilities: [.chat],
                               skills: Skills(general: 8.5, coding: 4, reasoning: 7, writing: 9.2), license: .apache2)
        let profile = TaskAnalyzer.analyze("Schreibe eine freundliche E-Mail an meine Kunden über die neue Version")
        let d = ModelRouter.route(RoutingRequest(profile: profile, candidates: [ModelCandidate(spec: coder), ModelCandidate(spec: writer)],
                                                 hardware: hardware, currentModelID: coder.id))
        XCTAssertEqual(d.chosen?.id, writer.id)
        XCTAssertTrue(d.switched)
        XCTAssertTrue(d.summary.contains("Wechsel"))
    }

    func testPlannerUnloadsLeastRecentlyUsed() {
        let target = spec("target", size: 20, params: 30, coding: 8)
        let now = Date()
        let loaded = [LoadedModel(id: "old", bytes: 18 * gb, lastUsed: now.addingTimeInterval(-600)),
                      LoadedModel(id: "recent", bytes: 18 * gb, lastUsed: now)]
        let plan = MemoryPlanner.plan(for: target, contextTokens: 8192, loaded: loaded, hardware: hardware)
        XCTAssertTrue(plan.fits)
        XCTAssertEqual(plan.unload, ["old"])
    }
}

final class ContextEngineTests: XCTestCase {
    let target = ModelSpec(id: "mlx:t", backend: .mlx, repo: "t", displayName: "Ziel", family: "T", parametersB: 8, bits: 4,
                           sizeBytes: 4_000_000_000, contextLength: 32_768, capabilities: [.chat], skills: .neutral, license: .apache2)
    let previous = ModelSpec(id: "mlx:p", backend: .mlx, repo: "p", displayName: "Vorher", family: "T", parametersB: 8, bits: 4,
                             sizeBytes: 4_000_000_000, contextLength: 32_768, capabilities: [.chat], skills: .neutral, license: .apache2)

    func testHandoffAndStateOnSwitch() {
        let messages = [
            ChatMessage(role: .user, text: "Wir bauen eine Android-App. Entscheidung: Wir nehmen Jetpack Compose."),
            ChatMessage(role: .assistant, text: "Gut.\n- [ ] Datenmodell entwerfen\n- [ ] LoginScreen.kt anlegen", modelName: "Vorher"),
            ChatMessage(role: .event, text: "Wechsel"),
            ChatMessage(role: .user, text: "Implementiere jetzt den LoginScreen."),
        ]
        let pkg = ContextEngine.build(messages: messages, target: target, previousModel: previous, switchReason: "Code schreiben",
                                      projectContext: nil, budgetTokens: 8000)
        XCTAssertEqual(pkg.messages.first?.role, .system)
        XCTAssertNotNil(pkg.handoff)
        let system = pkg.messages.first!.content
        XCTAssertTrue(system.contains("Vorher"))
        XCTAssertTrue(system.contains("Jetpack Compose"))
        XCTAssertTrue(system.contains("Datenmodell entwerfen"))
        XCTAssertTrue(pkg.state.files.contains("LoginScreen.kt"))
        XCTAssertEqual(pkg.messages.last?.content, "Implementiere jetzt den LoginScreen.")
        XCTAssertFalse(pkg.messages.contains { $0.content == "Wechsel" })
    }

    func testBudgetSummarizesOlderMessages() {
        var messages: [ChatMessage] = []
        for i in 0..<60 {
            messages.append(ChatMessage(role: .user, text: "Frage \(i): " + String(repeating: "Inhalt ", count: 120)))
            messages.append(ChatMessage(role: .assistant, text: "Antwort \(i): " + String(repeating: "Ergebnis ", count: 160), modelName: "Vorher"))
        }
        messages.append(ChatMessage(role: .user, text: "Letzte Frage"))
        let pkg = ContextEngine.build(messages: messages, target: target, previousModel: nil, switchReason: nil, projectContext: nil,
                                      budgetTokens: 6000)
        XCTAssertLessThanOrEqual(pkg.estimatedTokens, 6000 + 400)
        XCTAssertGreaterThan(pkg.summarizedMessages, 0)
        XCTAssertEqual(pkg.messages.last?.content, "Letzte Frage")
        XCTAssertTrue(pkg.messages.first!.content.contains("Zusammenfassung des früheren Verlaufs"))
        // Abwechselnde Rollen nach der Systemanweisung, erst der Nutzer
        XCTAssertEqual(pkg.messages.dropFirst().first?.role, .user)
    }

    func testCompletedTasksAreRemoved() {
        let messages = [
            ChatMessage(role: .assistant, text: "- [ ] Tests schreiben\n- [ ] Doku ergänzen"),
            ChatMessage(role: .assistant, text: "- [x] Tests schreiben"),
        ]
        let state = ContextEngine.extractState(from: messages)
        XCTAssertEqual(state.openTasks, ["Doku ergänzen"])
    }

    func testExpertBriefContainsQuestion() {
        let messages = [ChatMessage(role: .user, text: "Architektur für die App?"),
                        ChatMessage(role: .assistant, text: "Vorschlag: MVVM mit Repository.", modelName: "Qwen")]
        let brief = ContextEngine.expertBrief(messages: messages, question: "Ist MVVM hier sinnvoll?")
        XCTAssertTrue(brief.contains("Ist MVVM hier sinnvoll?"))
        XCTAssertTrue(brief.contains("MVVM mit Repository"))
    }
}

final class SupportTests: XCTestCase {
    func testNameParser() {
        let p = ModelNameParser.parse("mlx-community/Qwen3-30B-A3B-4bit")
        XCTAssertEqual(p.parametersB, 30)
        XCTAssertEqual(p.activeParametersB, 3)
        XCTAssertEqual(p.bits, 4)
        XCTAssertEqual(p.family, "Qwen")
        XCTAssertEqual(ModelNameParser.parse("mlx-community/DeepSeek-R1-Distill-Qwen-7B-4bit").family, "DeepSeek")
        XCTAssertEqual(ModelNameParser.parse("qwen3:8b").parametersB, 8)
        XCTAssertEqual(ModelNameParser.parse("mlx-community/gpt-oss-20b-MXFP4-Q8").bits, 4.25)
    }

    func testReasoningSplitter() {
        let (r, a) = ReasoningSplitter.split("<think>Ich überlege.</think>Die Antwort ist 42.")
        XCTAssertEqual(r, "Ich überlege.")
        XCTAssertEqual(a, "Die Antwort ist 42.")
        let (r2, a2) = ReasoningSplitter.split("Vorlage hat geöffnet</think>\n\nAntwort")
        XCTAssertEqual(r2, "Vorlage hat geöffnet")
        XCTAssertEqual(a2, "Antwort")
        let (_, a3) = ReasoningSplitter.split("<|channel|>analysis<|message|>denken<|end|><|start|>assistant<|channel|>final<|message|>Fertig.<|return|>")
        XCTAssertEqual(a3, "Fertig.")
    }

    func testFormatting() {
        XCTAssertEqual(Formatting.bytes(21_300_000_000), "21,3 GB")
        XCTAssertEqual(Formatting.bytes(4_000_000_000_000), "4,00 TB")
        XCTAssertEqual(Formatting.decimal(1234567.891, digits: 2), "1.234.567,89")
        XCTAssertEqual(Formatting.context(262_144), "256K")
        XCTAssertEqual(Formatting.params(0.6), "0,6B")
    }

    func testLicenses() {
        XCTAssertEqual(LicenseInfo.fromIdentifier("apache-2.0").terms, .permissive)
        XCTAssertEqual(LicenseInfo.fromIdentifier("llama3.1").terms, .restricted)
        XCTAssertNotNil(LicenseInfo.fromIdentifier("llama4").regionBlock)
        XCTAssertEqual(LicenseInfo.fromIdentifier("cc-by-nc-4.0").terms, .nonCommercial)
        XCTAssertEqual(LicenseInfo.fromIdentifier(nil).terms, .unknown)
    }

    func testConfigParse() {
        let json = #"{"model_type":"qwen3","num_hidden_layers":36,"num_attention_heads":32,"num_key_value_heads":8,"head_dim":128,"max_position_embeddings":40960,"quantization":{"bits":4,"group_size":64}}"#
        let info = ModelConfigInfo.parse(Data(json.utf8))
        XCTAssertEqual(info.contextLength, 40960)
        XCTAssertEqual(info.kvBytesPerToken, 36 * 8 * 128 * 4)
        XCTAssertEqual(info.quantBits, 4)
    }

    func testExpertRequests() throws {
        let r = try ExpertAPI.makeRequest(provider: .anthropic, apiKey: "k", model: "", user: "Hallo")
        XCTAssertEqual(r.url.host, "api.anthropic.com")
        XCTAssertEqual(r.headers["anthropic-version"], "2023-06-01")
        let body = try JSONSerialization.jsonObject(with: r.body!) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, ExpertProvider.anthropic.defaultModel)
        XCTAssertThrowsError(try ExpertAPI.makeRequest(provider: .openAI, apiKey: " ", model: "x", user: "Hallo"))
        let reply = try ExpertAPI.parseReply(provider: .openAI, data: Data(#"{"model":"m","choices":[{"message":{"content":"Gut so."}}],"usage":{"prompt_tokens":10,"completion_tokens":3}}"#.utf8))
        XCTAssertEqual(reply.text, "Gut so.")
        XCTAssertThrowsError(try ExpertAPI.parseReply(provider: .anthropic, data: Data(#"{"type":"error","error":{"message":"invalid x-api-key"}}"#.utf8)))
    }

    func testHuggingFaceParsing() throws {
        let info = try HuggingFaceAPI.parseInfo(Data(#"{"id":"mlx-community/Qwen3-8B-4bit","tags":["mlx","license:apache-2.0"],"siblings":[{"rfilename":"config.json","size":1000},{"rfilename":"model.safetensors","size":4600000000},{"rfilename":".gitattributes","size":10},{"rfilename":"README.md","size":200}]}"#.utf8))
        XCTAssertEqual(info.license.id, "apache-2.0")
        let files = HuggingFaceAPI.filesToDownload(info.files).map(\.path)
        XCTAssertEqual(Set(files), ["config.json", "model.safetensors", "README.md"])
        XCTAssertEqual(HuggingFaceAPI.repo(fromFolderName: HuggingFaceAPI.folderName(for: "a/b")), "a/b")
    }

    func testCatalogIsConsistent() {
        let ids = ModelCatalog.entries.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        for e in ModelCatalog.entries {
            XCTAssertTrue(e.spec.capabilities.contains(.chat))
            XCTAssertTrue(e.spec.repo.hasPrefix("mlx-community/"))
            XCTAssertGreaterThan(e.spec.sizeBytes, 0)
        }
    }

    func testProjectScanner() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("panora-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("app/src/main"), withIntermediateDirectories: true)
        try "include(\":app\")".write(to: dir.appendingPathComponent("settings.gradle.kts"), atomically: true, encoding: .utf8)
        try "<manifest/>".write(to: dir.appendingPathComponent("app/src/main/AndroidManifest.xml"), atomically: true, encoding: .utf8)
        try "fun main() {}".write(to: dir.appendingPathComponent("app/src/main/Main.kt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("build"), withIntermediateDirectories: true)
        try "x".write(to: dir.appendingPathComponent("build/ignored.kt"), atomically: true, encoding: .utf8)
        let summary = ProjectScanner.scan(at: dir)
        XCTAssertEqual(summary.kind, "Android-App (Gradle)")
        XCTAssertEqual(summary.fileCount, 3)
        XCTAssertTrue(summary.languages.contains { $0.name == "Kotlin" })
        let text = ProjectScanner.contextText(summary, focus: ["Main.kt"], budgetTokens: 2000)
        XCTAssertTrue(text.contains("fun main()"))
        try? FileManager.default.removeItem(at: dir)
    }
}
