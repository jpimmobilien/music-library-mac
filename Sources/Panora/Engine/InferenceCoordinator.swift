import Foundation
import PanoraCore

// =============================================================================================
// Koordination der Rechenwerke: welches Modell ist geladen, was wird entladen (Planer des Routers),
// Leerlauf-Entladen, gemessene Token-Raten. Nie werden zwei große Modelle unnötig gleichzeitig gehalten.
// =============================================================================================

struct LoadedInfo: Identifiable, Equatable {
    var id: String
    var name: String
    var family: String
    var backend: BackendKind
    var bytes: Int64
    var loadedAt: Date
    var lastUsed: Date
    var loadSeconds: Double
}

enum EngineActivity: Equatable {
    case idle
    case loading(String)
    case generating(String)

    var label: String {
        switch self {
        case .idle: return "Bereit"
        case .loading(let n): return "Lade \(n) …"
        case .generating(let n): return "\(n) schreibt …"
        }
    }

    var isBusy: Bool { self != .idle }
}

@MainActor
final class InferenceCoordinator: ObservableObject {
    @Published private(set) var loaded: [LoadedInfo] = []
    @Published private(set) var activity: EngineActivity = .idle
    @Published private(set) var lastTokensPerSecond: Double?

    let mlx = MLXEngine()
    private let settings: AppSettings
    private var idleTimer: Timer?
    private var lastActivity = Date()

    init(settings: AppSettings) {
        self.settings = settings
    }

    var loadedModels: [LoadedModel] {
        loaded.map { LoadedModel(id: $0.id, bytes: $0.bytes, lastUsed: $0.lastUsed) }
    }

    var loadedBytes: Int64 { loaded.reduce(0) { $0 + $1.bytes } }

    func isLoaded(_ id: String) -> Bool { loaded.contains { $0.id == id } }

    func startIdleWatch() {
        guard idleTimer == nil else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkIdle() }
        }
    }

    private func checkIdle() async {
        let minutes = settings.idleUnloadMinutes
        guard minutes > 0, activity == .idle, !loaded.isEmpty else { return }
        if Date().timeIntervalSince(lastActivity) > Double(minutes) * 60 {
            await unloadAll()
        }
    }

    func ensureLoaded(_ spec: ModelSpec, unloadFirst: [String], contextTokens: Int) async throws {
        lastActivity = Date()
        for id in unloadFirst where id != spec.id { await unload(id) }
        if let i = loaded.firstIndex(where: { $0.id == spec.id }) {
            loaded[i].lastUsed = Date()
            return
        }
        activity = .loading(spec.displayName)
        let start = Date()
        do {
            switch spec.backend {
            case .mlx:
                guard let path = spec.localPath else { throw EngineError.folderMissing(spec.displayName) }
                try await mlx.load(id: spec.id, directory: URL(fileURLWithPath: path))
            case .ollama:
                try await OllamaClient(urlString: settings.ollamaURL).preload(name: spec.repo)
            }
        } catch {
            activity = .idle
            throw error
        }
        let bytes = MemoryPlanner.requiredBytes(for: spec, contextTokens: contextTokens)
        loaded.append(LoadedInfo(id: spec.id, name: spec.displayName, family: spec.family, backend: spec.backend, bytes: bytes,
                                 loadedAt: Date(), lastUsed: Date(), loadSeconds: Date().timeIntervalSince(start)))
        activity = .idle
    }

    func unload(_ id: String) async {
        guard let info = loaded.first(where: { $0.id == id }) else { return }
        switch info.backend {
        case .mlx: await mlx.unload(id: id)
        case .ollama: await OllamaClient(urlString: settings.ollamaURL).unload(name: String(id.dropFirst("ollama:".count)))
        }
        loaded.removeAll { $0.id == id }
    }

    func unloadAll() async {
        for info in loaded { await unload(info.id) }
    }

    func generate(_ spec: ModelSpec, messages: [PromptMessage], maxTokens: Int, temperature: Double, thinking: Bool?,
                  contextTokens: Int) -> AsyncThrowingStream<GenerationEvent, Error> {
        lastActivity = Date()
        if let i = loaded.firstIndex(where: { $0.id == spec.id }) { loaded[i].lastUsed = Date() }
        activity = .generating(spec.displayName)
        switch spec.backend {
        case .mlx:
            return mlx.stream(id: spec.id, messages: messages, maxTokens: maxTokens, temperature: temperature, thinking: thinking)
        case .ollama:
            return OllamaClient(urlString: settings.ollamaURL).stream(name: spec.repo, messages: messages, maxTokens: maxTokens,
                                                                      temperature: temperature, contextTokens: contextTokens,
                                                                      thinking: thinking)
        }
    }

    func finishedGenerating(_ spec: ModelSpec, stats: GenerationStats?) {
        activity = .idle
        lastActivity = Date()
        guard let stats, stats.tokensPerSecond.isFinite, stats.tokensPerSecond > 0, stats.generatedTokens >= 16 else { return }
        lastTokensPerSecond = stats.tokensPerSecond
        let previous = settings.measuredTokensPerSecond[spec.id]
        settings.measuredTokensPerSecond[spec.id] = previous.map { $0 * 0.6 + stats.tokensPerSecond * 0.4 } ?? stats.tokensPerSecond
    }

    // MARK: Fotomodus

    func setDemoState(loaded: [LoadedInfo], activity: EngineActivity, tps: Double?) {
        self.loaded = loaded
        self.activity = activity
        self.lastTokensPerSecond = tps
    }
}
