#if !PANORA_NO_MLX
import Foundation
import MLX
import MLXLLM
import MLXVLM
import MLXLMCommon
import Tokenizers
import PanoraCore

// =============================================================================================
// MLX-Rechenwerk: lädt Modelle aus einem lokalen Ordner (kein Netz), erzeugt Antworten als Stream
// und gibt den Speicher beim Entladen wieder frei. MLX ist für Apple Silicon optimiert und nutzt den
// Unified Memory direkt über Metal.
// =============================================================================================

/// Brücke zwischen swift-transformers und mlx-swift-lm (entspricht dem Makro #huggingFaceTokenizerLoader).
struct PanoraTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
        return TokenizerBridge(upstream)
    }
}

struct TokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
                           additionalContext: [String: any Sendable]?) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

actor MLXEngine {
    private var containers: [String: ModelContainer] = [:]
    private var configured = false

    /// MLX erst beim ersten Laden berühren (Metal wird dann initialisiert).
    private func configureOnce() {
        guard !configured else { return }
        configured = true
        // Zwischenspeicher von MLX begrenzen – Modelle selbst bleiben unberührt.
        MLX.Memory.cacheLimit = 2 * 1024 * 1024 * 1024
    }

    func isLoaded(_ id: String) -> Bool { containers[id] != nil }

    var loadedIDs: [String] { Array(containers.keys) }

    func load(id: String, directory: URL) async throws {
        if containers[id] != nil { return }
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.json").path) else {
            throw EngineError.folderMissing(directory.path)
        }
        configureOnce()
        let loader = PanoraTokenizerLoader()
        do {
            let container = try await LLMModelFactory.shared.loadContainer(from: directory, using: loader)
            containers[id] = container
        } catch let llmError {
            // Multimodale Architekturen (z. B. manche Gemma- und Qwen-VL-Modelle) über die VLM-Fabrik versuchen
            do {
                let container = try await VLMModelFactory.shared.loadContainer(from: directory, using: loader)
                containers[id] = container
            } catch {
                throw EngineError.unsupported("Das Modell konnte nicht geladen werden: \(llmError.localizedDescription)")
            }
        }
    }

    func unload(id: String) {
        containers[id] = nil
        MLX.Memory.clearCache()
    }

    func unloadAll() {
        containers.removeAll()
        MLX.Memory.clearCache()
    }

    func activeMemory() -> Int { MLX.Memory.activeMemory }

    /// Antwort als Stream. Der Abbruch des Verbrauchers beendet die Erzeugung.
    nonisolated func stream(id: String, messages: [PromptMessage], maxTokens: Int, temperature: Double,
                            thinking: Bool?) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(id: id, messages: messages, maxTokens: maxTokens, temperature: temperature,
                                       thinking: thinking, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(id: String, messages: [PromptMessage], maxTokens: Int, temperature: Double, thinking: Bool?,
                     continuation: AsyncThrowingStream<GenerationEvent, Error>.Continuation) async throws {
        guard let container = containers[id] else { throw EngineError.notLoaded(id) }
        let chat: [MLXLMCommon.Chat.Message] = messages.map { m in
            switch m.role {
            case .system: return .system(m.content)
            case .user: return .user(m.content)
            case .assistant: return .assistant(m.content)
            }
        }
        var context: [String: any Sendable]? = nil
        if let thinking { context = ["enable_thinking": thinking] }
        let input = UserInput(chat: chat, additionalContext: context)
        let prepared = try await container.prepare(input: input)
        let parameters = GenerateParameters(maxTokens: maxTokens, temperature: Float(temperature), topP: 0.95)
        let generation = try await container.generate(input: prepared, parameters: parameters)
        var stats = GenerationStats(promptTokens: 0, generatedTokens: 0, tokensPerSecond: 0, promptTokensPerSecond: 0)
        for await item in generation {
            if Task.isCancelled { break }
            if let text = item.chunk {
                continuation.yield(.chunk(text))
            } else if case .info(let info) = item {
                stats = GenerationStats(promptTokens: info.promptTokenCount, generatedTokens: info.generationTokenCount,
                                        tokensPerSecond: info.tokensPerSecond, promptTokensPerSecond: info.promptTokensPerSecond)
            }
        }
        continuation.yield(.finished(stats))
    }
}

#else
import Foundation
import PanoraCore

/// Vorschau-Build ohne MLX (z. B. Intel-Mac in der CI): gleiche Schnittstelle, lädt aber keine Modelle.
actor MLXEngine {
    func isLoaded(_ id: String) -> Bool { false }
    var loadedIDs: [String] { [] }
    func load(id: String, directory: URL) async throws {
        throw EngineError.unsupported("MLX ist in diesem Vorschau-Build nicht enthalten (nur Apple Silicon).")
    }
    func unload(id: String) {}
    func unloadAll() {}
    func activeMemory() -> Int { 0 }
    nonisolated func stream(id: String, messages: [PromptMessage], maxTokens: Int, temperature: Double,
                            thinking: Bool?) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: EngineError.notLoaded(id)) }
    }
}
#endif
