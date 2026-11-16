import SwiftUI
import AppKit
import PanoraCore

// =============================================================================================
// Bildschirmfotos im Build (`--snapshot <ordner>`) mit Vorführdaten – nur zur Sichtprüfung in der CI.
// Im Fotomodus wird nichts gespeichert und kein Modell geladen.
// =============================================================================================

private final class SnapshotWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
enum SnapshotRunner {
    struct Scenario {
        let name: String
        let section: AppSection
        let dark: Bool
        var size = CGSize(width: 1440, height: 940)
        var emptyChat = false
        var manualSuggestion = false
        var noModels = false
    }

    static let scenarios: [Scenario] = [
        Scenario(name: "01-chat-dunkel", section: .chat, dark: true),
        Scenario(name: "02-chat-hell", section: .chat, dark: false),
        Scenario(name: "03-start-dunkel", section: .chat, dark: true, emptyChat: true),
        Scenario(name: "04-verlauf-dunkel", section: .history, dark: true),
        Scenario(name: "05-modelle-dunkel", section: .models, dark: true),
        Scenario(name: "06-modelle-hell", section: .models, dark: false),
        Scenario(name: "07-entdecken-dunkel", section: .discover, dark: true),
        Scenario(name: "08-projekte-hell", section: .projects, dark: false),
        Scenario(name: "09-hardware-dunkel", section: .hardware, dark: true),
        Scenario(name: "10-speicher-dunkel", section: .storage, dark: true),
        Scenario(name: "11-einstellungen-dunkel", section: .settings, dark: true),
        Scenario(name: "12-chat-manuell-hell", section: .chat, dark: false, manualSuggestion: true),
        Scenario(name: "13-erster-start-hell", section: .chat, dark: false, emptyChat: true, noModels: true),
        Scenario(name: "14-chat-kompakt-dunkel", section: .chat, dark: true, size: CGSize(width: 1100, height: 720)),
    ]

    static func run(model: AppModel, output: URL) async {
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        model.hardware.sample()
        model.storage.refresh()
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        model.hardware.sample()
        for window in NSApp.windows { window.orderOut(nil) }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        var manifest: [[String: Any]] = []
        for scenario in scenarios {
            print("▸ \(scenario.name)")
            fflush(stdout)
            DemoData.install(into: model, emptyChat: scenario.emptyChat, manualSuggestion: scenario.manualSuggestion, noModels: scenario.noModels)
            model.section = scenario.section
            model.settings.appearance = scenario.dark ? .dark : .light
            let appearance = NSAppearance(named: scenario.dark ? .darkAqua : .aqua)
            NSApp.appearance = appearance

            let window = SnapshotWindow(contentRect: NSRect(origin: .zero, size: scenario.size),
                                        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                        backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.appearance = appearance
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: RootView(embedded: true)
                .environmentObject(model)
                .environmentObject(model.settings))
            window.setContentSize(scenario.size)
            if let screen = NSScreen.main?.visibleFrame { window.setFrameTopLeftPoint(NSPoint(x: screen.minX, y: screen.maxY)) }
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            let size = window.contentView?.bounds.size ?? .zero
            let file = output.appendingPathComponent("\(scenario.name)-\(Int(size.width))x\(Int(size.height)).png")
            let method = capture(window, to: file)
            manifest.append(["file": file.lastPathComponent, "section": scenario.section.rawValue, "dark": scenario.dark, "method": method])
            window.orderOut(nil)
            window.contentView = nil
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        let summary: [String: Any] = ["images": manifest, "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
                                      "liquidGlass": LiquidGlass.isAvailable, "data": "Vorführdaten (nur Fotomodus)"]
        SelfTest.write(summary, to: output.appendingPathComponent("manifest.json"))
    }

    private static func capture(_ window: NSWindow, to url: URL) -> String {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
            let function = unsafeBitCast(symbol, to: CreateImage.self)
            if let image = function(.null, 1 << 3, UInt32(window.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue(), image.width > 10 {
                let rep = NSBitmapImageRep(cgImage: image)
                if let data = rep.representation(using: .png, properties: [:]), (try? data.write(to: url)) != nil { return "window-server" }
            }
        }
        if let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: url)
                return "cache-display"
            }
        }
        return "failed"
    }
}

/// Vorführdaten für die Bildschirmfotos.
@MainActor
enum DemoData {
    static func installed(_ repo: String, available: Bool = true, directory: String = "/Volumes/Samsung T7/Panora/Modelle") -> InstalledModel? {
        guard let entry = ModelCatalog.entry(for: repo) else { return nil }
        var spec = entry.spec
        spec.localPath = directory + "/" + HuggingFaceAPI.folderName(for: repo)
        return InstalledModel(spec: spec, directory: directory, folder: spec.localPath, available: available,
                              unavailableReason: available ? nil : "Laufwerk nicht verbunden (Backup-SSD)", catalog: entry, installedAt: Date())
    }

    static func install(into model: AppModel, emptyChat: Bool, manualSuggestion: Bool, noModels: Bool) {
        var items: [InstalledModel] = []
        if !noModels {
            items = [
                installed("mlx-community/Qwen3.6-35B-A3B-4bit"),
                installed("mlx-community/Qwen3.6-27B-4bit"),
                installed("mlx-community/gemma-4-26b-a4b-it-4bit"),
                installed("mlx-community/gpt-oss-20b-MXFP4-Q8"),
                installed("mlx-community/Qwen3-8B-4bit", directory: NSHomeDirectory() + "/Library/Application Support/Panora/Modelle"),
                installed("mlx-community/DeepSeek-R1-Distill-Qwen-7B-4bit"),
                installed("mlx-community/Qwen3-Coder-Next-4bit", available: false, directory: "/Volumes/Backup-SSD/Panora/Modelle"),
            ].compactMap { $0 }
            items.append(InstalledModel(spec: OllamaClient.spec(for: OllamaModel(name: "llama3.2:3b", size: 2_019_000_000, family: "llama",
                                                                                     parameterSize: "3.2B", quantization: "Q4_K_M")),
                                        directory: "Ollama", folder: nil, available: true, unavailableReason: nil, catalog: nil, installedAt: nil))
        }
        model.library.installDemo(items)
        let coder = items.first { $0.spec.repo.contains("Qwen3.6-35B") }?.spec
        let planner = items.first { $0.spec.repo.contains("Qwen3.6-27B") }?.spec
        if let coder, !noModels {
            model.engine.setDemoState(loaded: [LoadedInfo(id: coder.id, name: coder.displayName, family: coder.family, backend: .mlx,
                                                          bytes: MemoryPlanner.requiredBytes(for: coder, contextTokens: 16_384),
                                                          loadedAt: Date(), lastUsed: Date(), loadSeconds: 18)],
                                      activity: .idle, tps: 74)
        } else {
            model.engine.setDemoState(loaded: [], activity: .idle, tps: nil)
        }
        // Projekte
        let project = ProjectSummary(path: NSHomeDirectory() + "/Developer/RezeptApp", name: "RezeptApp", kind: "Android-App (Gradle)",
                                     fileCount: 412, totalBytes: 38_400_000,
                                     languages: [LanguageStat(name: "Kotlin", files: 186, bytes: 2_100_000), LanguageStat(name: "XML", files: 94, bytes: 900_000),
                                                 LanguageStat(name: "Kotlin Script", files: 6, bytes: 40_000), LanguageStat(name: "JSON", files: 12, bytes: 30_000)],
                                     keyFiles: ["settings.gradle.kts", "app/build.gradle.kts"], tree: [], files: [], readme: nil,
                                     scannedAt: Date(), truncated: false)
        let project2 = ProjectSummary(path: NSHomeDirectory() + "/Developer/Panora", name: "Panora", kind: "Xcode-Projekt (Swift)",
                                      fileCount: 64, totalBytes: 2_400_000,
                                      languages: [LanguageStat(name: "Swift", files: 41, bytes: 600_000), LanguageStat(name: "YAML", files: 3, bytes: 9_000),
                                                  LanguageStat(name: "Markdown", files: 4, bytes: 30_000)],
                                      keyFiles: ["project.yml"], tree: [], files: [], readme: nil, scannedAt: Date(), truncated: false)
        model.projects.setDemo([project, project2])

        // Unterhaltung mit Modellwechseln
        var c = Conversation(title: "RezeptApp: Offline-Sync", mode: manualSuggestion ? .manual : .auto,
                             pinnedModelID: manualSuggestion ? items.first { $0.spec.repo.contains("Qwen3-8B") }?.id : nil,
                             allowSwitchInManual: manualSuggestion, projectPath: project.path)
        if !emptyChat, let coder, let planner {
            let reasonsPlan = ["Aufgabe: Planung und Architektur (Planung oder Architektur)", "Erwartete Qualität für Planung und Architektur: 8,6 von 10",
                               "Tempo: ca. 23 Token/s", "Speicher: 18,7 GB von 44,8 GB Budget", "Ladezeit ca. 17 s"]
            let reasonsCode = ["Aufgabe: Code schreiben (Programmier-Begriffe, Datei .kt erwähnt)", "Erwartete Qualität für Code schreiben: 8,5 von 10",
                               "Tempo: ca. 127 Token/s", "Speicher: 23,3 GB von 44,8 GB Budget", "Entlädt dafür: Qwen3.6 27B (am längsten ungenutzt)"]
            c.messages = [
                ChatMessage(role: .user, text: "Analysiere mein Android-Projekt RezeptApp und entwirf eine Architektur für Offline-Sync."),
                ChatMessage(role: .assistant, text: """
                ## Befund
                Die App nutzt **Jetpack Compose**, ein einzelnes `app`-Modul und lädt Rezepte direkt im ViewModel aus dem Netz.

                ## Vorschlag
                - Module `core:data`, `core:database`, `feature:rezepte`
                - **Room** als lokale Quelle der Wahrheit, Sync über `WorkManager`
                - Repository entscheidet zwischen Cache und Netz

                Entscheidung: Wir nehmen Room und WorkManager.
                - [ ] RezeptRepository.kt anlegen
                - [ ] SyncWorker.kt implementieren
                """, modelID: planner.id, modelName: planner.displayName, backend: .mlx, routingSummary: "\(planner.displayName) übernimmt: Planung und Architektur.",
                     routingReasons: reasonsPlan, routingMode: .auto, taskKind: .planning, tokensPerSecond: 23),
                ChatMessage(role: .user, text: "Gut. Implementiere jetzt das RezeptRepository.kt in Kotlin."),
                ChatMessage(role: .event, text: "Wechsel von \(planner.displayName) zu \(coder.displayName): besser geeignet für Code schreiben.",
                            modelID: coder.id, modelName: coder.displayName, backend: .mlx, routingReasons: reasonsCode, routingMode: .auto, taskKind: .coding),
                ChatMessage(role: .assistant, text: """
                Hier ist das Repository mit Room als Quelle der Wahrheit:

                ```kotlin
                class RezeptRepository(
                    private val dao: RezeptDao,
                    private val api: RezeptApi,
                ) {
                    fun rezepte(): Flow<List<Rezept>> = dao.alle()

                    suspend fun synchronisieren() {
                        val neu = api.laden()
                        dao.speichern(neu)
                    }
                }
                ```

                Der `SyncWorker` ruft `synchronisieren()` periodisch auf – auch ohne geöffnete App.
                """, modelID: coder.id, modelName: coder.displayName, backend: .mlx, routingSummary: "Wechsel zu \(coder.displayName).",
                     routingReasons: reasonsCode, routingMode: .auto, taskKind: .coding, tokensPerSecond: 74),
                ChatMessage(role: .expert, text: "Solide Grundlage. Ergänze Konfliktbehandlung (Zeitstempel je Rezept) und einen Exponential-Backoff im SyncWorker.",
                            expertProvider: "ChatGPT · gpt-6.1-terra"),
            ]
            c.updated = Date()
        }
        model.chat.setDemo(c, decision: nil, generating: false)
        model.chat.pendingSuggestion = nil
        if manualSuggestion, !emptyChat {
            let candidates = items.map { ModelCandidate(spec: $0.spec, available: $0.available) }
            let hw = HardwareSnapshot(totalMemory: 64_000_000_000, availableMemory: 48_000_000_000, modelBudget: 44_800_000_000, memoryBandwidthGBs: 307)
            let d = ModelRouter.route(RoutingRequest(profile: TaskAnalyzer.analyze("Implementiere den SyncWorker in Kotlin mit WorkManager"),
                                                     candidates: candidates, hardware: hw, mode: .manual, pinnedModelID: c.pinnedModelID,
                                                     allowSwitchInManual: true))
            model.chat.pendingSuggestion = d.suggestion != nil ? d : nil
        }
        // Entscheidung für die Hardware-Seite
        if !items.isEmpty {
            let candidates = items.map { ModelCandidate(spec: $0.spec, available: $0.available, unavailableReason: $0.unavailableReason) }
            let hw = HardwareSnapshot(totalMemory: 64_000_000_000, availableMemory: 48_000_000_000, modelBudget: 44_800_000_000, memoryBandwidthGBs: 307)
            let d = ModelRouter.route(RoutingRequest(profile: TaskAnalyzer.analyze("Implementiere das RezeptRepository.kt in Kotlin"),
                                                     candidates: candidates, hardware: hw, currentModelID: planner?.id))
            model.chat.setDemo(c, decision: d, generating: false)
        }
        // Verlauf
        var older = Conversation(title: "Exposé für Altbauwohnung formulieren", mode: .auto)
        older.messages = [ChatMessage(role: .user, text: "Formuliere ein Exposé"),
                          ChatMessage(role: .assistant, text: "Gern …", modelID: "mlx:mlx-community/gemma-4-26b-a4b-it-4bit", modelName: "Gemma 4 26B A4B")]
        older.updated = Date().addingTimeInterval(-86_400 * 3)
        var oct = Conversation(title: "Kotlin-Coroutines erklärt", mode: .auto, favorite: true)
        oct.messages = [ChatMessage(role: .user, text: "Erkläre Coroutines"),
                        ChatMessage(role: .assistant, text: "…", modelID: "mlx:mlx-community/Qwen3-8B-4bit", modelName: "Qwen3 8B")]
        oct.updated = Date().addingTimeInterval(-86_400 * 35)
        model.chats.replaceAll(emptyChat ? [older, oct] : [c, older, oct])
    }
}
