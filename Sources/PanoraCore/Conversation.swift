import Foundation

public enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    /// Antwort eines externen Experten (OpenAI, Anthropic) – nur auf ausdrücklichen Wunsch.
    case expert
    /// Hinweis im Verlauf, z. B. Modellwechsel („Wechsel zu …: …“).
    case event
}

public struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var role: MessageRole
    public var text: String
    /// Gedankengang des Modells (<think> …), getrennt von der Antwort.
    public var reasoning: String?
    public var date: Date
    public var modelID: String?
    public var modelName: String?
    public var backend: BackendKind?
    public var routingSummary: String?
    public var routingReasons: [String]?
    public var routingMode: RoutingMode?
    public var taskKind: TaskKind?
    /// „ChatGPT · gpt-6.1-terra“
    public var expertProvider: String?
    public var tokensPerSecond: Double?
    public var tokenCount: Int?
    public var isError: Bool

    public init(id: UUID = UUID(), role: MessageRole, text: String, reasoning: String? = nil, date: Date = Date(),
                modelID: String? = nil, modelName: String? = nil, backend: BackendKind? = nil, routingSummary: String? = nil,
                routingReasons: [String]? = nil, routingMode: RoutingMode? = nil, taskKind: TaskKind? = nil,
                expertProvider: String? = nil, tokensPerSecond: Double? = nil, tokenCount: Int? = nil, isError: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.reasoning = reasoning
        self.date = date
        self.modelID = modelID
        self.modelName = modelName
        self.backend = backend
        self.routingSummary = routingSummary
        self.routingReasons = routingReasons
        self.routingMode = routingMode
        self.taskKind = taskKind
        self.expertProvider = expertProvider
        self.tokensPerSecond = tokensPerSecond
        self.tokenCount = tokenCount
        self.isError = isError
    }
}

public struct Conversation: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var created: Date
    public var updated: Date
    public var mode: RoutingMode
    /// MANUELL: gewähltes Modell für den ganzen Chat.
    public var pinnedModelID: String?
    /// MANUELL: Wechsel nach Rückfrage erlauben (Standard aus).
    public var allowSwitchInManual: Bool
    public var messages: [ChatMessage]
    /// Angehängtes Projekt (Ordner) für Projektkontext.
    public var projectPath: String?
    public var favorite: Bool

    public init(id: UUID = UUID(), title: String = "Neuer Chat", created: Date = Date(), updated: Date = Date(),
                mode: RoutingMode = .auto, pinnedModelID: String? = nil, allowSwitchInManual: Bool = false,
                messages: [ChatMessage] = [], projectPath: String? = nil, favorite: Bool = false) {
        self.id = id
        self.title = title
        self.created = created
        self.updated = updated
        self.mode = mode
        self.pinnedModelID = pinnedModelID
        self.allowSwitchInManual = allowSwitchInManual
        self.messages = messages
        self.projectPath = projectPath
        self.favorite = favorite
    }

    /// Modell der letzten lokalen Antwort.
    public var lastModelID: String? {
        messages.last { $0.role == .assistant && $0.modelID != nil && !$0.isError }?.modelID
    }

    /// Aufgabenart der letzten Anfrage.
    public var lastTaskKind: TaskKind? {
        messages.last { $0.role == .assistant && $0.taskKind != nil }?.taskKind
    }

    /// Alle Modelle, die in diesem Chat gearbeitet haben (in Reihenfolge des ersten Auftretens).
    public var modelsUsed: [String] {
        var names: [String] = []
        for m in messages where m.role == .assistant {
            if let n = m.modelName, !names.contains(n) { names.append(n) }
        }
        return names
    }

    public var switchCount: Int { messages.filter { $0.role == .event }.count }

    /// Titel aus der ersten Anfrage (bis 48 Zeichen, an einer Wortgrenze).
    public static func title(from text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let clean = firstLine.replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return "Neuer Chat" }
        if clean.count <= 48 { return clean }
        let cut = clean.prefix(48)
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > 20 {
            return String(cut[..<space]) + " …"
        }
        return String(cut) + " …"
    }
}

/// Trennt Gedankengang und Antwort (<think> … </think> und das „Harmony“-Format von gpt-oss).
public enum ReasoningSplitter {
    public static func split(_ raw: String) -> (reasoning: String?, answer: String) {
        var text = raw
        // gpt-oss (Harmony): <|channel|>analysis<|message|>…<|end|>…<|channel|>final<|message|>…
        if text.contains("<|channel|>") {
            var reasoning: String?
            if let a = text.range(of: "<|channel|>analysis<|message|>") {
                let rest = text[a.upperBound...]
                let end = rest.range(of: "<|end|>")?.lowerBound ?? rest.range(of: "<|start|>")?.lowerBound ?? rest.endIndex
                reasoning = String(rest[..<end])
            }
            if let f = text.range(of: "<|channel|>final<|message|>") {
                text = String(text[f.upperBound...])
            } else {
                text = ""
            }
            for token in ["<|return|>", "<|end|>", "<|start|>assistant", "<|start|>", "<|message|>"] {
                text = text.replacingOccurrences(of: token, with: "")
            }
            return (reasoning?.trimmingCharacters(in: .whitespacesAndNewlines), text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let open = "<think>"
        let close = "</think>"
        if let o = text.range(of: open) {
            let before = String(text[..<o.lowerBound])
            let after = text[o.upperBound...]
            if let c = after.range(of: close) {
                let reasoning = String(after[..<c.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let answer = (before + String(after[c.upperBound...])).trimmingCharacters(in: .whitespacesAndNewlines)
                return (reasoning.isEmpty ? nil : reasoning, answer)
            }
            // Noch am Denken (Streaming)
            return (String(after).trimmingCharacters(in: .whitespacesAndNewlines), before.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let c = text.range(of: close) {
            // Die Vorlage hat <think> schon in den Prompt geschrieben.
            let reasoning = String(text[..<c.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = String(text[c.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (reasoning.isEmpty ? nil : reasoning, answer)
        }
        return (nil, text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
