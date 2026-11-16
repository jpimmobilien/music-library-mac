import Foundation
import PanoraCore

// =============================================================================================
// Ollama als zusätzliches lokales Rechenwerk: Modelle, die dort schon liegen, nutzt Panora mit.
// Kommunikation nur mit dem lokalen Dienst (127.0.0.1) – keine Cloud.
// =============================================================================================

struct OllamaModel: Sendable, Equatable {
    var name: String
    var size: Int64
    var family: String?
    var parameterSize: String?
    var quantization: String?
}

struct OllamaClient: Sendable {
    var baseURL: URL

    init(urlString: String) {
        baseURL = URL(string: urlString) ?? URL(string: "http://127.0.0.1:11434")!
    }

    private var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 600
        config.timeoutIntervalForResource = 3600
        return URLSession(configuration: config)
    }

    /// Ist Ollama erreichbar? (kurzer Zeitrahmen)
    func ping() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/version"))
        request.timeoutInterval = 1.5
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func models() async throws -> [OllamaModel] {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 3
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let root = (try JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = root["models"] as? [[String: Any]] else { return [] }
        return list.compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            let details = item["details"] as? [String: Any]
            let size = (item["size"] as? Int).map { Int64($0) } ?? 0
            return OllamaModel(name: name, size: size, family: details?["family"] as? String,
                               parameterSize: details?["parameter_size"] as? String,
                               quantization: details?["quantization_level"] as? String)
        }
    }

    /// Entlädt ein Modell aus dem Speicher von Ollama (keep_alive 0).
    func unload(name: String) async {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": name, "keep_alive": 0])
        request.timeoutInterval = 10
        _ = try? await URLSession.shared.data(for: request)
    }

    /// Lädt ein Modell vorab (leere Anfrage).
    func preload(name: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": name, "keep_alive": "30m"])
        request.timeoutInterval = 600
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw EngineError.ollama(Self.errorText(data) ?? "Status \(http.statusCode)")
        }
    }

    func stream(name: String, messages: [PromptMessage], maxTokens: Int, temperature: Double, contextTokens: Int,
                thinking: Bool?) -> AsyncThrowingStream<GenerationEvent, Error> {
        let session = self.session
        let url = baseURL.appendingPathComponent("api/chat")
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    var body: [String: Any] = [
                        "model": name,
                        "stream": true,
                        "keep_alive": "30m",
                        "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
                        "options": ["num_predict": maxTokens, "temperature": temperature, "num_ctx": contextTokens],
                    ]
                    if let thinking { body["think"] = thinking }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                        var data = Data()
                        for try await b in bytes { data.append(b); if data.count > 4096 { break } }
                        throw EngineError.ollama(Self.errorText(data) ?? "Status \(http.statusCode)")
                    }
                    var stats = GenerationStats(promptTokens: 0, generatedTokens: 0, tokensPerSecond: 0, promptTokensPerSecond: 0)
                    var thinkingOpen = false
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard let data = line.data(using: .utf8),
                              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
                        if let error = obj["error"] as? String { throw EngineError.ollama(error) }
                        if let message = obj["message"] as? [String: Any] {
                            // Denkmodelle liefern den Gedankengang getrennt – als <think> weiterreichen.
                            if let think = message["thinking"] as? String, !think.isEmpty {
                                if !thinkingOpen { continuation.yield(.chunk("<think>")); thinkingOpen = true }
                                continuation.yield(.chunk(think))
                            }
                            if let content = message["content"] as? String, !content.isEmpty {
                                if thinkingOpen { continuation.yield(.chunk("</think>")); thinkingOpen = false }
                                continuation.yield(.chunk(content))
                            }
                        }
                        if obj["done"] as? Bool == true {
                            let evalCount = obj["eval_count"] as? Int ?? 0
                            let evalNs = obj["eval_duration"] as? Double ?? Double(obj["eval_duration"] as? Int ?? 0)
                            let promptCount = obj["prompt_eval_count"] as? Int ?? 0
                            let promptNs = obj["prompt_eval_duration"] as? Double ?? Double(obj["prompt_eval_duration"] as? Int ?? 0)
                            stats = GenerationStats(promptTokens: promptCount, generatedTokens: evalCount,
                                                    tokensPerSecond: evalNs > 0 ? Double(evalCount) / (evalNs / 1e9) : 0,
                                                    promptTokensPerSecond: promptNs > 0 ? Double(promptCount) / (promptNs / 1e9) : 0)
                        }
                    }
                    if thinkingOpen { continuation.yield(.chunk("</think>")) }
                    continuation.yield(.finished(stats))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func errorText(_ data: Data) -> String? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        return obj["error"] as? String
    }

    /// ModelSpec für ein Ollama-Modell (Werte geschätzt, Lizenz siehe Modellkarte in Ollama).
    static func spec(for model: OllamaModel) -> ModelSpec {
        var parsed = ModelNameParser.parse(model.name)
        if parsed.parametersB == nil, let p = model.parameterSize {
            let digits = p.uppercased().replacingOccurrences(of: "B", with: "")
            if let v = Double(digits) { parsed.parametersB = v }
        }
        if let q = model.quantization?.uppercased() {
            if q.hasPrefix("Q4") { parsed.bits = 4.5 } else if q.hasPrefix("Q8") { parsed.bits = 8.5 } else if q.hasPrefix("Q6") { parsed.bits = 6.5 }
            else if q.hasPrefix("Q5") { parsed.bits = 5.5 } else if q.hasPrefix("F16") || q.hasPrefix("BF16") { parsed.bits = 16 }
            else if q.hasPrefix("MXFP4") { parsed.bits = 4.25 }
        }
        let family = parsed.family != "Weitere" ? parsed.family : (model.family.map { ModelNameParser.family(of: $0.lowercased()) } ?? "Weitere")
        let context = 32_768
        return ModelSpec(id: ModelSpec.ollamaID(model.name), backend: .ollama, repo: model.name, displayName: model.name,
                         family: family, parametersB: parsed.parametersB, activeParametersB: parsed.activeParametersB,
                         bits: parsed.bits ?? 4.5, sizeBytes: model.size, contextLength: context,
                         capabilities: ModelNameParser.estimatedCapabilities(for: parsed, contextLength: context),
                         skills: ModelNameParser.estimatedSkills(for: parsed),
                         license: LicenseInfo(id: "ollama", name: "siehe Ollama-Modellkarte", openness: .openWeight, terms: .unknown,
                                              note: "Lizenz in der Modellbibliothek von Ollama prüfen."),
                         summary: "Über Ollama installiert.")
    }
}
