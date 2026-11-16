import Foundation
import AppKit
import PanoraCore

// =============================================================================================
// Ablauf einer Anfrage: Aufgabe erkennen → Modell wählen (AUTO/MANUELL) → Speicher planen und laden →
// Kontext für das Zielmodell aufbereiten → Antwort streamen. Ein Modellwechsel erscheint als Hinweis
// im Verlauf; der Gesprächsfluss bleibt erhalten. Cloud wird hier nie benutzt.
// =============================================================================================

struct ExpertDraft: Identifiable, Equatable {
    let id = UUID()
    var provider: ExpertProvider
    var model: String
    var question: String
    var brief: String
    var tokens: Int
}

@MainActor
final class ExpertService: ObservableObject {
    @Published var draft: ExpertDraft?
    @Published private(set) var sending: ExpertProvider?
    @Published private(set) var keyState: [ExpertProvider: Bool] = [:]
    private let settings: AppSettings

    init(settings: AppSettings, readKeys: Bool = true) {
        self.settings = settings
        if readKeys {
            for p in ExpertProvider.allCases { keyState[p] = !(Keychain.read(p.rawValue) ?? "").isEmpty }
        }
    }

    func hasKey(_ p: ExpertProvider) -> Bool { keyState[p] ?? false }

    func setKey(_ p: ExpertProvider, _ value: String) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { Keychain.delete(p.rawValue) } else { Keychain.write(p.rawValue, value: clean) }
        keyState[p] = !clean.isEmpty
    }

    func prepare(_ provider: ExpertProvider, question: String, messages: [ChatMessage]) {
        let brief = ContextEngine.expertBrief(messages: messages, question: question)
        draft = ExpertDraft(provider: provider, model: settings.expertModel(provider), question: question, brief: brief,
                            tokens: TaskAnalyzer.estimateTokens(brief))
    }

    func send(_ draft: ExpertDraft) async throws -> ExpertReply {
        guard let key = Keychain.read(draft.provider.rawValue), !key.isEmpty else { throw ExpertError.missingKey(draft.provider) }
        sending = draft.provider
        defer { sending = nil }
        let req = try ExpertAPI.makeRequest(provider: draft.provider, apiKey: key, model: draft.model, user: draft.brief)
        var request = URLRequest(url: req.url)
        request.httpMethod = req.method
        for (k, v) in req.headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = req.body
        request.timeoutInterval = 180
        let (data, _) = try await URLSession.shared.data(for: request)
        return try ExpertAPI.parseReply(provider: draft.provider, data: data)
    }

    func fetchModels(_ provider: ExpertProvider) async throws -> [String] {
        guard let key = Keychain.read(provider.rawValue), !key.isEmpty else { throw ExpertError.missingKey(provider) }
        let req = try ExpertAPI.modelsRequest(provider: provider, apiKey: key)
        var request = URLRequest(url: req.url)
        for (k, v) in req.headers { request.setValue(v, forHTTPHeaderField: k) }
        request.timeoutInterval = 30
        let (data, _) = try await URLSession.shared.data(for: request)
        return try ExpertAPI.parseModels(data: data)
    }
}

@MainActor
final class ChatController: ObservableObject {
    @Published var conversation: Conversation
    @Published var draft = ""
    @Published private(set) var isGenerating = false
    @Published private(set) var lastDecision: RoutingDecision?
    @Published var pendingSuggestion: RoutingDecision?
    @Published var notice: String?

    private let settings: AppSettings
    private let library: ModelLibrary
    private let engine: InferenceCoordinator
    private let hardware: HardwareMonitor
    private let storage: StorageMonitor
    private let chats: ChatStore
    private let projects: ProjectStore
    private let network: NetworkMonitor
    let experts: ExpertService
    private var task: Task<Void, Never>?

    init(settings: AppSettings, library: ModelLibrary, engine: InferenceCoordinator, hardware: HardwareMonitor, storage: StorageMonitor,
         chats: ChatStore, projects: ProjectStore, network: NetworkMonitor, experts: ExpertService) {
        self.settings = settings
        self.library = library
        self.engine = engine
        self.hardware = hardware
        self.storage = storage
        self.chats = chats
        self.projects = projects
        self.network = network
        self.experts = experts
        conversation = Conversation(mode: settings.defaultMode, allowSwitchInManual: settings.allowSwitchInManual)
    }

    // MARK: Chats

    func newChat() {
        stop()
        conversation = Conversation(mode: settings.defaultMode, allowSwitchInManual: settings.allowSwitchInManual)
        pendingSuggestion = nil
        lastDecision = nil
        notice = nil
    }

    func open(_ id: UUID) {
        guard let c = chats.conversation(id) else { return }
        stop()
        conversation = c
        pendingSuggestion = nil
        notice = nil
    }

    private func save() {
        conversation.updated = Date()
        chats.upsert(conversation)
    }

    func setMode(_ mode: RoutingMode) {
        conversation.mode = mode
        if mode == .manual && conversation.pinnedModelID == nil {
            conversation.pinnedModelID = conversation.lastModelID ?? library.availableModels.first?.id
        }
        pendingSuggestion = nil
        if !conversation.messages.isEmpty { save() }
    }

    func pin(_ modelID: String) {
        conversation.mode = .manual
        conversation.pinnedModelID = modelID
        pendingSuggestion = nil
        if !conversation.messages.isEmpty { save() }
    }

    func setAllowSwitch(_ allow: Bool) {
        conversation.allowSwitchInManual = allow
        if !conversation.messages.isEmpty { save() }
    }

    func attachProject(_ path: String?) {
        conversation.projectPath = path
        if !conversation.messages.isEmpty { save() }
    }

    /// MANUELL: vorgeschlagenen Wechsel annehmen (nur auf Klick).
    func acceptSuggestion() {
        guard let s = pendingSuggestion?.suggestion else { return }
        pin(s.id)
        conversation.messages.append(ChatMessage(role: .event, text: "Auf Wunsch gewechselt zu \(s.displayName) (manuell).",
                                                 modelID: s.id, modelName: s.displayName, routingMode: .manual))
        save()
    }

    // MARK: Senden

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }
        draft = ""
        submit(text)
    }

    func submit(_ text: String) {
        if conversation.messages.isEmpty { conversation.title = Conversation.title(from: text) }
        conversation.messages.append(ChatMessage(role: .user, text: text))
        save()
        pendingSuggestion = nil
        notice = nil
        task = Task { [weak self] in await self?.run(text) }
    }

    func retryLast() {
        guard !isGenerating, let lastUser = conversation.messages.last(where: { $0.role == .user }) else { return }
        // Fehlerhafte Antworten nach der letzten Anfrage entfernen
        if let idx = conversation.messages.lastIndex(where: { $0.id == lastUser.id }) {
            conversation.messages.removeSubrange((idx + 1)...)
        }
        task = Task { [weak self] in await self?.run(lastUser.text) }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private var diskReadGBs: Double {
        // Lesegeschwindigkeit des Laufwerks mit den Modellen: gemessen, sonst Erfahrungswert
        if let vol = storage.volume(containing: settings.downloadDirectory) {
            if let measured = storage.speedResults[vol.path] { return measured.readMBs / 1000 }
            if let stored = settings.diskReadGBs[vol.name] { return stored }
            return vol.isInternal ? 5.0 : 0.9
        }
        return 2.0
    }

    private func run(_ text: String) async {
        isGenerating = true
        defer { isGenerating = false }

        // 1. Projektkontext und Aufgabe
        let state = ContextEngine.extractState(from: conversation.messages)
        let focusFiles = ContextEngine.filePaths(in: text) + state.files.suffix(4)
        var projectText: String?
        if conversation.projectPath != nil {
            projectText = await projects.contextText(for: conversation.projectPath, focus: focusFiles,
                                                    budgetTokens: max(2000, settings.maxContextTokens / 4))
        }
        let projectTokens = projectText.map { TaskAnalyzer.estimateTokens($0) } ?? 0
        let profile = TaskAnalyzer.analyze(text, previous: conversation.lastTaskKind, attachedContextTokens: projectTokens)

        // 2. Modell wählen
        let historyTokens = conversation.messages.reduce(0) { $0 + TaskAnalyzer.estimateTokens($1.text) }
        let needed = min(historyTokens + projectTokens, settings.maxContextTokens) + min(2048, settings.maxAnswerTokens)
        hardware.sample()
        let request = RoutingRequest(profile: profile, candidates: library.candidates(measured: settings.measuredTokensPerSecond),
                                     hardware: hardware.snapshot(settings: settings, diskReadGBs: diskReadGBs),
                                     loaded: engine.loadedModels, currentModelID: conversation.lastModelID,
                                     mode: conversation.mode, pinnedModelID: conversation.pinnedModelID,
                                     allowSwitchInManual: conversation.allowSwitchInManual, neededContextTokens: needed,
                                     stickiness: settings.stickiness)
        let decision = ModelRouter.route(request)
        lastDecision = decision

        guard let model = decision.chosen else {
            var message = ChatMessage(role: .assistant, text: decision.summary, routingSummary: decision.failure,
                                      routingReasons: decision.reasons, routingMode: decision.mode, taskKind: profile.kind, isError: true)
            if library.models.isEmpty {
                message.text = "Es ist noch kein lokales Modell installiert. Unter „Entdecken“ kannst du eines laden – danach funktioniert Panora auch ohne Internet."
            }
            conversation.messages.append(message)
            if decision.suggestion != nil { pendingSuggestion = decision }
            save()
            return
        }
        if decision.mode == .manual && decision.suggestion != nil { pendingSuggestion = decision }

        let previousModel = library.spec(conversation.lastModelID)
        if decision.switched {
            conversation.messages.append(ChatMessage(role: .event, text: decision.summary, modelID: model.id, modelName: model.displayName,
                                                     backend: model.backend, routingSummary: decision.summary,
                                                     routingReasons: decision.reasons, routingMode: decision.mode, taskKind: profile.kind))
        }

        // 3. Laden (inkl. Entladen nach Plan)
        let contextForMemory = max(8192, needed)
        do {
            try await engine.ensureLoaded(model, unloadFirst: decision.plan?.unload ?? [], contextTokens: contextForMemory)
        } catch {
            conversation.messages.append(ChatMessage(role: .assistant, text: "\(model.displayName) konnte nicht geladen werden: \(error.localizedDescription)",
                                                     modelID: model.id, modelName: model.displayName, backend: model.backend,
                                                     taskKind: profile.kind, isError: true))
            save()
            return
        }
        if Task.isCancelled { return }

        // 4. Kontext für das Zielmodell
        let window = min(model.contextLength, settings.maxContextTokens)
        let budget = max(2048, window - settings.maxAnswerTokens)
        let package = ContextEngine.build(messages: conversation.messages.filter { !$0.isError }, target: model,
                                          previousModel: decision.switched ? previousModel : nil, switchReason: profile.kind.label,
                                          projectContext: projectText, budgetTokens: budget)

        // 5. Antwort streamen
        var reply = ChatMessage(role: .assistant, text: "", modelID: model.id, modelName: model.displayName, backend: model.backend,
                                routingSummary: decision.summary, routingReasons: decision.reasons, routingMode: decision.mode,
                                taskKind: profile.kind)
        conversation.messages.append(reply)
        let index = conversation.messages.count - 1
        let thinking: Bool?
        if model.backend == .ollama {
            thinking = nil
        } else if [.smallTalk, .question, .writing, .translation, .summarization].contains(profile.kind) && profile.difficulty <= 2 {
            thinking = false
        } else {
            thinking = true
        }
        let stream = engine.generate(model, messages: package.messages, maxTokens: settings.maxAnswerTokens,
                                     temperature: settings.temperature, thinking: thinking, contextTokens: window)
        var raw = ""
        var stats: GenerationStats?
        var lastUpdate = Date.distantPast
        do {
            for try await event in stream {
                if Task.isCancelled { break }
                switch event {
                case .chunk(let c):
                    raw += c
                    if Date().timeIntervalSince(lastUpdate) > 0.05 {
                        lastUpdate = Date()
                        apply(raw, to: index)
                    }
                case .finished(let s):
                    stats = s
                }
            }
        } catch {
            if !Task.isCancelled {
                apply(raw, to: index)
                if index < conversation.messages.count {
                    conversation.messages[index].isError = raw.isEmpty
                    let note = "\n\n_(Abgebrochen: \(error.localizedDescription))_"
                    conversation.messages[index].text = (conversation.messages[index].text.isEmpty
                        ? "Fehler bei der Antwort: \(error.localizedDescription)" : conversation.messages[index].text + note)
                }
            }
        }
        apply(raw, to: index)
        engine.finishedGenerating(model, stats: stats)
        if index < conversation.messages.count {
            reply = conversation.messages[index]
            reply.tokensPerSecond = stats?.tokensPerSecond
            reply.tokenCount = stats?.generatedTokens
            if Task.isCancelled && !reply.text.contains("Abgebrochen") {
                reply.text += reply.text.isEmpty ? "_(Abgebrochen)_" : "\n\n_(Abgebrochen)_"
            }
            conversation.messages[index] = reply
        }
        save()
    }

    private func apply(_ raw: String, to index: Int) {
        guard index < conversation.messages.count else { return }
        let (reasoning, answer) = ReasoningSplitter.split(raw)
        conversation.messages[index].reasoning = reasoning
        conversation.messages[index].text = answer
    }

    // MARK: Externe Experten (nur auf Klick)

    func askExpert(_ provider: ExpertProvider, question: String? = nil) {
        guard settings.expertsEnabled else {
            notice = "Externe Experten sind ausgeschaltet (Einstellungen → Externe Experten)."
            return
        }
        guard network.online && !settings.forceOffline else {
            notice = "Offline – externe Experten sind nicht verfügbar. Panora arbeitet lokal weiter."
            return
        }
        guard experts.hasKey(provider) else {
            notice = "Für \(provider.shortName) ist kein API-Schlüssel hinterlegt (Einstellungen → Externe Experten)."
            return
        }
        let lastUser = conversation.messages.last { $0.role == .user }?.text ?? ""
        let q = question ?? (lastUser.isEmpty ? "Wie schätzt du den bisherigen Stand ein?" : "Bitte prüfe die letzte Antwort zu: \(lastUser)")
        experts.prepare(provider, question: q, messages: conversation.messages)
    }

    func confirmExpert(_ draft: ExpertDraft) {
        experts.draft = nil
        Task {
            do {
                let reply = try await experts.send(draft)
                conversation.messages.append(ChatMessage(role: .expert, text: reply.text,
                                                         expertProvider: "\(draft.provider.shortName) · \(reply.model ?? draft.model)",
                                                         tokenCount: reply.outputTokens))
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                conversation.messages.append(ChatMessage(role: .expert, text: "Die Zweitmeinung konnte nicht abgerufen werden: \(message)",
                                                         expertProvider: draft.provider.shortName, isError: true))
            }
            save()
        }
    }

    /// Die lokale KI bewertet die Zweitmeinung (läuft wieder lokal).
    func evaluateExpert(_ message: ChatMessage) {
        guard !isGenerating else { return }
        submit("Bewerte die Zweitmeinung von \(message.expertProvider ?? "extern") kritisch: Wo hat sie recht, wo nicht, und was übernehmen wir für die weitere Arbeit?")
    }

    // MARK: Fotomodus

    func setDemo(_ c: Conversation, decision: RoutingDecision?, generating: Bool) {
        conversation = c
        lastDecision = decision
        isGenerating = generating
    }
}
