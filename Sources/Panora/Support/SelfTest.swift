import Foundation
import AppKit
import PanoraCore

// =============================================================================================
// Selbsttest im Build (`--selftest <datei.json>`) und Ende-zu-Ende-Test mit echtem MLX-Modell
// (`--e2e <modellordner> <datei.json>`). Ergebnisse als JSON für die CI.
// =============================================================================================

@MainActor
enum SelfTest {
    struct Check {
        let name: String
        let ok: Bool
        let detail: String
    }

    static func run(model: AppModel, output: URL) async {
        var checks: [Check] = []
        func add(_ name: String, _ ok: Bool, _ detail: String) {
            NSLog("Panora-Selbsttest: %@ – %@ (%@)", name, ok ? "ok" : "FEHLER", detail)
            checks.append(Check(name: name, ok: ok, detail: detail))
        }

        // Bundle und Ressourcen
        let bundle = Bundle.main
        add("Bundle-ID", bundle.bundleIdentifier == "de.panora.app", bundle.bundleIdentifier ?? "–")
        add("App-Symbol", NSApp.applicationIconImage != nil, "vorhanden")
        #if PANORA_NO_MLX
        add("MLX-Metal-Shader im Bundle", true, "Vorschau-Build ohne MLX (Intel)")
        #else
        let metallibs = findFiles(in: bundle.bundleURL, suffix: ".metallib")
        add("MLX-Metal-Shader im Bundle", !metallibs.isEmpty, metallibs.map { $0.lastPathComponent }.joined(separator: ", "))
        #endif

        // Hardware
        model.hardware.sample()
        add("Arbeitsspeicher erkannt", model.hardware.totalMemory > 1_000_000_000, Formatting.bytes(model.hardware.totalMemory))
        add("Prozessor erkannt", !model.hardware.chipName.isEmpty, model.hardware.chipName)
        add("Verfügbarer Speicher", model.hardware.availableMemory > 0, Formatting.bytes(model.hardware.availableMemory))

        // Laufwerke
        model.storage.refresh()
        add("Laufwerke erkannt", !model.storage.volumes.isEmpty, model.storage.volumes.map { "\($0.name) (\($0.kindLabel))" }.joined(separator: ", "))

        // Modellbibliothek mit einem Testordner
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("panora-selftest-\(UUID().uuidString)")
        let folder = temp.appendingPathComponent("mlx-community__Qwen3-8B-4bit")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let config = #"{"model_type":"qwen3","num_hidden_layers":36,"num_attention_heads":32,"num_key_value_heads":8,"head_dim":128,"max_position_embeddings":40960,"quantization":{"bits":4,"group_size":64}}"#
        try? config.write(to: folder.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: folder.appendingPathComponent("model.safetensors").path, contents: Data(count: 1024))
        let scanned = ModelLibrary.scan(directories: [temp.path])
        let found = scanned.first
        add("Modellordner erkannt", found?.spec.repo == "mlx-community/Qwen3-8B-4bit" && found?.spec.contextLength == 40960,
            found.map { "\($0.spec.displayName), \(Formatting.context($0.spec.contextLength)), KV \($0.spec.kvBytesPerToken ?? 0) B/Token" } ?? "nichts gefunden")
        try? FileManager.default.removeItem(at: temp)

        // Router und Kontext
        let entries = ModelCatalog.entries
        let candidates = entries.prefix(8).map { ModelCandidate(spec: $0.spec) }
        let hw = model.hardware.snapshot(settings: model.settings, diskReadGBs: 1.0)
        let fakeHW = HardwareSnapshot(totalMemory: 64_000_000_000, availableMemory: 50_000_000_000, modelBudget: 45_000_000_000,
                                      memoryBandwidthGBs: hw.memoryBandwidthGBs, diskReadGBs: 1.0)
        let coding = ModelRouter.route(RoutingRequest(profile: TaskAnalyzer.analyze("Implementiere ein Repository in Kotlin mit Room"),
                                                      candidates: candidates, hardware: fakeHW))
        add("AUTO: Coding-Aufgabe", coding.chosen != nil && (coding.chosen?.skills.coding ?? 0) >= 8, coding.summary)
        let writing = ModelRouter.route(RoutingRequest(profile: TaskAnalyzer.analyze("Schreibe einen freundlichen Brief an meine Mieter"),
                                                       candidates: candidates, hardware: fakeHW, currentModelID: coding.chosen?.id))
        add("AUTO: Wechsel bei Textaufgabe", writing.chosen != nil, writing.summary)
        let manual = ModelRouter.route(RoutingRequest(profile: TaskAnalyzer.analyze("Implementiere einen Compiler"), candidates: candidates,
                                                      hardware: fakeHW, mode: .manual, pinnedModelID: entries.last?.id))
        add("MANUELL wird nicht überschrieben", manual.chosen?.id == entries.last?.id, manual.summary)
        let messages = [ChatMessage(role: .user, text: "Entscheidung: Wir nehmen Jetpack Compose."),
                        ChatMessage(role: .assistant, text: "- [ ] LoginScreen.kt anlegen", modelName: "Qwen3.6 27B"),
                        ChatMessage(role: .user, text: "Implementiere den LoginScreen")]
        if let target = coding.chosen {
            let pkg = ContextEngine.build(messages: messages, target: target, previousModel: entries.first?.spec, switchReason: "Code schreiben",
                                          projectContext: nil, budgetTokens: 8000)
            add("Kontextübergabe beim Wechsel", pkg.handoff != nil && pkg.messages.first?.content.contains("Jetpack Compose") == true,
                "\(pkg.messages.count) Nachrichten, ca. \(pkg.estimatedTokens) Tokens")
        }

        // Netzwerk und Ollama (nur Information)
        add("Netzwerkstatus", true, model.network.online ? "online" : "offline")
        let ollama = await OllamaClient(urlString: model.settings.ollamaURL).ping()
        add("Ollama (optional)", true, ollama ? "läuft" : "nicht installiert")

        let ok = checks.allSatisfy(\.ok)
        let result: [String: Any] = [
            "ok": ok,
            "checks": checks.map { ["name": $0.name, "ok": $0.ok, "detail": $0.detail] },
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "process": ProcessInfo.processInfo.processName,
            "translated": false,
            "liquidGlass": LiquidGlass.isAvailable,
        ]
        write(result, to: output)
    }

    static func runE2E(model: AppModel, modelFolder: URL, output: URL) async {
        var result: [String: Any] = ["model": modelFolder.lastPathComponent]
        let start = Date()
        guard let installed = ModelLibrary.inspect(folder: modelFolder.path, directory: modelFolder.deletingLastPathComponent().path) else {
            result["ok"] = false
            result["error"] = "Modellordner nicht erkannt"
            write(result, to: output)
            return
        }
        let spec = installed.spec
        do {
            try await model.engine.ensureLoaded(spec, unloadFirst: [], contextTokens: 4096)
            result["loadSeconds"] = Date().timeIntervalSince(start)
            let messages = [ChatMessage(role: .user, text: "Antworte in einem kurzen Satz: Was ist die Hauptstadt von Frankreich?")]
            let pkg = ContextEngine.build(messages: messages, target: spec, previousModel: nil, switchReason: nil, projectContext: nil, budgetTokens: 2048)
            var raw = ""
            var stats: GenerationStats?
            for try await event in model.engine.generate(spec, messages: pkg.messages, maxTokens: 120, temperature: 0.2, thinking: false, contextTokens: 4096) {
                switch event {
                case .chunk(let c): raw += c
                case .finished(let s): stats = s
                }
            }
            model.engine.finishedGenerating(spec, stats: stats)
            let (reasoning, answer) = ReasoningSplitter.split(raw)
            result["raw"] = raw
            result["answer"] = answer
            result["reasoning"] = reasoning ?? ""
            result["tokensPerSecond"] = stats?.tokensPerSecond ?? 0
            result["generatedTokens"] = stats?.generatedTokens ?? 0
            result["ok"] = !answer.isEmpty
            await model.engine.unloadAll()
        } catch {
            result["ok"] = false
            result["error"] = String(describing: error)
        }
        write(result, to: output)
    }

    private static func findFiles(in url: URL, suffix: String) -> [URL] {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { return [] }
        var found: [URL] = []
        while let item = e.nextObject() as? URL {
            if item.lastPathComponent.hasSuffix(suffix) { found.append(item) }
        }
        return found
    }

    static func write(_ dict: [String: Any], to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
    }
}
