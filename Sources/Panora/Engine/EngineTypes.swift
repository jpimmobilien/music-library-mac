import Foundation

// Gemeinsame Typen der Rechenwerke (MLX, Ollama).

enum GenerationEvent: Sendable {
    case chunk(String)
    case finished(GenerationStats)
}

struct GenerationStats: Sendable {
    var promptTokens: Int
    var generatedTokens: Int
    var tokensPerSecond: Double
    var promptTokensPerSecond: Double
}

enum EngineError: Error, LocalizedError {
    case notLoaded(String)
    case folderMissing(String)
    case unsupported(String)
    case ollama(String)

    var errorDescription: String? {
        switch self {
        case .notLoaded(let name): return "\(name) ist nicht geladen."
        case .folderMissing(let path): return "Der Modellordner fehlt: \(path). Ist das Laufwerk angeschlossen?"
        case .unsupported(let message): return message
        case .ollama(let message): return "Ollama: \(message)"
        }
    }
}

