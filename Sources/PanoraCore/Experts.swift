import Foundation

// =============================================================================================
// Externe Experten (optional): OpenAI und Anthropic als „Zweitmeinung“ – nur auf ausdrücklichen Klick,
// nie automatisch, nie ohne Vorschau der Daten, die das Gerät verlassen. Hier nur der reine Aufbau der
// Anfragen und das Lesen der Antworten (testbar ohne Netz).
// =============================================================================================

public enum ExpertProvider: String, Codable, CaseIterable, Sendable, Identifiable {
    case openAI
    case anthropic

    public var id: String { rawValue }

    public var label: String { self == .openAI ? "ChatGPT (OpenAI)" : "Claude (Anthropic)" }
    public var shortName: String { self == .openAI ? "ChatGPT" : "Claude" }
    public var company: String { self == .openAI ? "OpenAI" : "Anthropic" }
    /// Vorgabe – in den Einstellungen änderbar; „Modelle abrufen“ listet die tatsächlich verfügbaren.
    public var defaultModel: String { self == .openAI ? "gpt-6.1-terra" : "claude-sonnet-5-5" }
    public var keyHint: String { self == .openAI ? "sk-…" : "sk-ant-…" }
    public var consoleURL: String { self == .openAI ? "https://platform.openai.com/api-keys" : "https://console.anthropic.com/settings/keys" }
    public var host: String { self == .openAI ? "api.openai.com" : "api.anthropic.com" }
}

public struct ExpertHTTPRequest: Sendable, Equatable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data?
}

public struct ExpertReply: Sendable, Equatable {
    public var text: String
    public var model: String?
    public var inputTokens: Int?
    public var outputTokens: Int?
}

public enum ExpertError: Error, LocalizedError, Equatable {
    case missingKey(ExpertProvider)
    case api(String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .missingKey(let p): return "Für \(p.shortName) ist kein API-Schlüssel hinterlegt (Einstellungen → Externe Experten)."
        case .api(let message): return message
        case .badResponse: return "Die Antwort des Dienstes konnte nicht gelesen werden."
        }
    }
}

public enum ExpertAPI {
    public static let systemPrompt = """
    Du bist ein unabhängiger externer Experte. Ein lokaler KI-Assistent arbeitet mit dem Nutzer an einer Aufgabe \
    und bittet dich um eine Zweitmeinung. Sei ehrlich, konkret und kritisch. Antworte in der Sprache der Anfrage.
    """

    public static func makeRequest(provider: ExpertProvider, apiKey: String, model: String, system: String = systemPrompt,
                                   user: String, maxTokens: Int = 4096) throws -> ExpertHTTPRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ExpertError.missingKey(provider) }
        let modelName = model.trimmingCharacters(in: .whitespaces).isEmpty ? provider.defaultModel : model
        switch provider {
        case .openAI:
            let body: [String: Any] = [
                "model": modelName,
                "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            ]
            return ExpertHTTPRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!, method: "POST",
                                     headers: ["Authorization": "Bearer \(key)", "Content-Type": "application/json"],
                                     body: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]))
        case .anthropic:
            let body: [String: Any] = [
                "model": modelName,
                "max_tokens": maxTokens,
                "system": system,
                "messages": [["role": "user", "content": user]],
            ]
            return ExpertHTTPRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, method: "POST",
                                     headers: ["x-api-key": key, "anthropic-version": "2023-06-01", "Content-Type": "application/json"],
                                     body: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]))
        }
    }

    public static func modelsRequest(provider: ExpertProvider, apiKey: String) throws -> ExpertHTTPRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ExpertError.missingKey(provider) }
        switch provider {
        case .openAI:
            return ExpertHTTPRequest(url: URL(string: "https://api.openai.com/v1/models")!, method: "GET",
                                     headers: ["Authorization": "Bearer \(key)"], body: nil)
        case .anthropic:
            return ExpertHTTPRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=100")!, method: "GET",
                                     headers: ["x-api-key": key, "anthropic-version": "2023-06-01"], body: nil)
        }
    }

    public static func parseReply(provider: ExpertProvider, data: Data) throws -> ExpertReply {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw ExpertError.badResponse }
        if let message = errorMessage(root) { throw ExpertError.api(message) }
        switch provider {
        case .openAI:
            guard let choices = root["choices"] as? [[String: Any]], let first = choices.first,
                  let message = first["message"] as? [String: Any] else { throw ExpertError.badResponse }
            var text = message["content"] as? String ?? ""
            if text.isEmpty, let parts = message["content"] as? [[String: Any]] {
                text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
            }
            let usage = root["usage"] as? [String: Any]
            return ExpertReply(text: text, model: root["model"] as? String,
                               inputTokens: usage?["prompt_tokens"] as? Int, outputTokens: usage?["completion_tokens"] as? Int)
        case .anthropic:
            guard let content = root["content"] as? [[String: Any]] else { throw ExpertError.badResponse }
            let text = content.filter { ($0["type"] as? String) == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
            let usage = root["usage"] as? [String: Any]
            return ExpertReply(text: text, model: root["model"] as? String,
                               inputTokens: usage?["input_tokens"] as? Int, outputTokens: usage?["output_tokens"] as? Int)
        }
    }

    public static func parseModels(data: Data) throws -> [String] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw ExpertError.badResponse }
        if let message = errorMessage(root) { throw ExpertError.api(message) }
        let list = (root["data"] as? [[String: Any]]) ?? []
        return list.compactMap { $0["id"] as? String }.sorted()
    }

    static func errorMessage(_ root: [String: Any]) -> String? {
        if let error = root["error"] as? [String: Any] {
            return (error["message"] as? String) ?? (error["type"] as? String) ?? "Unbekannter Fehler"
        }
        if let type = root["type"] as? String, type == "error" { return "Unbekannter Fehler" }
        return nil
    }
}
