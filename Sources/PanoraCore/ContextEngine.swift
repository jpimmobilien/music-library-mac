import Foundation

// =============================================================================================
// Context Engine: modellunabhängige Aufbereitung des Gesprächs für das jeweils arbeitende Modell.
//
// Bei jedem Aufruf – und besonders bei einem Modellwechsel – bekommt das Modell:
//   • Systemanweisung von Panora (+ Übergabehinweis beim Wechsel),
//   • den Arbeitsstand: Entscheidungen, offene Aufgaben, Ergebnisse, erwähnte Dateien,
//   • den Projektkontext (gekürzt),
//   • eine Zusammenfassung älterer Nachrichten, die nicht mehr ins Kontextfenster passen,
//   • die jüngsten Nachrichten im Wortlaut.
// Alles wird an das Kontextfenster des Zielmodells angepasst; riesige Verläufe werden nicht übertragen.
// =============================================================================================

public struct PromptMessage: Equatable, Sendable {
    public enum Role: String, Sendable { case system, user, assistant }
    public var role: Role
    public var content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

public struct ConversationState: Equatable, Sendable {
    public var decisions: [String] = []
    public var openTasks: [String] = []
    public var results: [String] = []
    public var files: [String] = []

    public var isEmpty: Bool { decisions.isEmpty && openTasks.isEmpty && results.isEmpty && files.isEmpty }

    public init(decisions: [String] = [], openTasks: [String] = [], results: [String] = [], files: [String] = []) {
        self.decisions = decisions
        self.openTasks = openTasks
        self.results = results
        self.files = files
    }

    /// Als Textblock für die Systemanweisung.
    public var promptBlock: String {
        var lines: [String] = []
        if !decisions.isEmpty { lines.append("Getroffene Entscheidungen:"); lines += decisions.map { "- \($0)" } }
        if !openTasks.isEmpty { lines.append("Offene Aufgaben:"); lines += openTasks.map { "- \($0)" } }
        if !results.isEmpty { lines.append("Bisherige Ergebnisse:"); lines += results.map { "- \($0)" } }
        if !files.isEmpty { lines.append("Relevante Dateien: " + files.joined(separator: ", ")) }
        return lines.joined(separator: "\n")
    }
}

public struct ContextPackage: Equatable, Sendable {
    public var messages: [PromptMessage]
    public var estimatedTokens: Int
    /// Nachrichten, die nur noch zusammengefasst übergeben wurden.
    public var summarizedMessages: Int
    public var includedMessages: Int
    public var handoff: String?
    public var state: ConversationState
}

public enum ContextEngine {
    public static let defaultSystemPrompt = """
    Du bist Panora, ein lokaler KI-Assistent, der vollständig auf dem Mac des Nutzers läuft. \
    Antworte in der Sprache des Nutzers (meist Deutsch), klar und konkret. \
    Bei Code: vollständige, lauffähige Abschnitte mit kurzer Erklärung. \
    Wenn dir Informationen fehlen, sag es offen, statt zu raten.
    """

    // MARK: Arbeitsstand

    public static func extractState(from messages: [ChatMessage]) -> ConversationState {
        var state = ConversationState()
        var done: Set<String> = []
        let decisionMarkers = ["entscheidung:", "beschluss:", "entschieden:", "festgelegt:", "decision:"]
        let decisionPrefixes = ["wir nehmen ", "wir verwenden ", "wir nutzen ", "wir bleiben bei ", "nehmen wir ", "machen wir so"]
        let taskPrefixes = ["- [ ]", "* [ ]", "todo", "offen:", "nächster schritt", "naechster schritt", "next step",
                            "noch zu tun", "als nächstes", "als naechstes"]
        for message in messages where message.role == .user || message.role == .assistant || message.role == .expert {
            let text = stripCode(message.text)
            for rawLine in text.split(whereSeparator: \.isNewline) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard line.count >= 6 else { continue }
                let lower = line.lowercased()
                if lower.hasPrefix("- [x]") || lower.hasPrefix("* [x]") {
                    done.insert(normalizeTask(line))
                    continue
                }
                let plain = lower.trimmingCharacters(in: CharacterSet(charactersIn: "-*•# "))
                if let marker = decisionMarkers.first(where: { lower.contains($0) }), let r = lower.range(of: marker) {
                    // Ab der Markierung übernehmen (gleiche Position im Original)
                    let offset = lower.distance(from: lower.startIndex, to: r.lowerBound)
                    let start = line.index(line.startIndex, offsetBy: min(offset, line.count))
                    append(&state.decisions, clean(String(line[start...])), limit: 8)
                } else if decisionPrefixes.contains(where: { plain.hasPrefix($0) }) {
                    append(&state.decisions, clean(line), limit: 8)
                } else if taskPrefixes.contains(where: { lower.hasPrefix($0) || plain.hasPrefix($0) }) {
                    append(&state.openTasks, clean(line), limit: 10)
                }
            }
            // Dateien
            for file in filePaths(in: message.text) { append(&state.files, file, limit: 14) }
        }
        state.openTasks.removeAll { done.contains(normalizeTask($0)) }
        // Ergebnisse: Kernsatz der letzten größeren Antworten (mit Modell)
        let substantial = messages.filter { $0.role == .assistant && !$0.isError && $0.text.count > 280 }.suffix(4)
        for m in substantial {
            let sentence = firstSentence(stripCode(m.text), max: 160)
            guard !sentence.isEmpty else { continue }
            let who = m.modelName.map { "\($0)" } ?? "Antwort"
            let what = m.taskKind?.label ?? "Antwort"
            state.results.append("\(what) (\(who)): \(sentence)")
        }
        return state
    }

    private static func append(_ list: inout [String], _ item: String, limit: Int) {
        guard !item.isEmpty else { return }
        list.removeAll { $0.lowercased() == item.lowercased() }
        list.append(item)
        if list.count > limit { list.removeFirst(list.count - limit) }
    }

    private static func clean(_ line: String) -> String {
        var s = line.trimmingCharacters(in: CharacterSet(charactersIn: "-*•# ").union(.whitespaces))
        if s.lowercased().hasPrefix("[ ]") { s = String(s.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
        return String(s.prefix(220))
    }

    private static func normalizeTask(_ line: String) -> String {
        var s = line.lowercased()
        for p in ["- [x]", "* [x]", "- [ ]", "* [ ]"] { s = s.replacingOccurrences(of: p, with: "") }
        return s.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "-*•# "))
    }

    public static func filePaths(in text: String) -> [String] {
        let pattern = #"(?<![\w/])([\w\-]+/)*[\w\-]+\.(swift|kt|kts|java|gradle|xml|json|md|py|js|ts|tsx|yml|yaml|plist|sh|c|h|cpp|rs|go|sql|toml|txt)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var result: [String] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let path = ns.substring(with: match.range)
            if !result.contains(path) { result.append(path) }
        }
        return result
    }

    /// Ersetzt Codeblöcke durch „[Code: n Zeilen]“.
    public static func stripCode(_ text: String) -> String {
        guard text.contains("```") else { return text }
        var out = ""
        var inCode = false
        var codeLines = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCode { out += "[Code: \(codeLines) Zeilen]\n"; codeLines = 0 }
                inCode.toggle()
                continue
            }
            if inCode { codeLines += 1 } else { out += line + "\n" }
        }
        if inCode { out += "[Code: \(codeLines) Zeilen]\n" }
        return out
    }

    public static func firstSentence(_ text: String, max: Int) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#*- "))
        var sentence = flat
        for terminator in [". ", "! ", "? ", ": "] {
            if let r = flat.range(of: terminator), flat.distance(from: flat.startIndex, to: r.lowerBound) >= 20 {
                let candidate = String(flat[..<r.lowerBound]) + String(terminator.first!)
                if candidate.count < sentence.count { sentence = candidate }
            }
        }
        return truncate(sentence, max: max)
    }

    public static func truncate(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        return String(text.prefix(max - 1)) + "…"
    }

    /// Kürzt auf ein Tokenbudget: Anfang und Ende bleiben erhalten.
    public static func truncateToTokens(_ text: String, tokens: Int) -> String {
        let maxChars = Int(Double(max(32, tokens)) * 3.6)
        guard text.utf8.count > maxChars else { return text }
        let head = Int(Double(maxChars) * 0.62)
        let tail = maxChars - head - 40
        let start = text.prefix(head)
        let end = text.suffix(max(0, tail))
        return String(start) + "\n[… gekürzt …]\n" + String(end)
    }

    // MARK: Paket für das Zielmodell

    /// - Parameters:
    ///   - messages: Verlauf inkl. der neuen Nutzernachricht (die laufende Antwort nicht).
    ///   - budgetTokens: nutzbares Kontextfenster abzüglich Platz für die Antwort.
    public static func build(messages: [ChatMessage], target: ModelSpec, previousModel: ModelSpec?, switchReason: String?,
                             projectContext: String?, budgetTokens: Int, systemPrompt: String = defaultSystemPrompt) -> ContextPackage {
        let budget = max(1024, budgetTokens)
        let state = extractState(from: messages)
        var system = systemPrompt

        var handoff: String?
        if let previousModel, previousModel.id != target.id {
            handoff = "Du übernimmst diese Unterhaltung von \(previousModel.displayName)" +
                (switchReason.map { " (Grund: \($0))" } ?? "") +
                ". Führe die Arbeit nahtlos fort; der Nutzer soll keinen Bruch bemerken."
            system += "\n\n" + handoff!
        }
        if !state.isEmpty {
            let block = truncateToTokens(state.promptBlock, tokens: budget / 8)
            system += "\n\nArbeitsstand dieser Unterhaltung:\n" + block
        }
        if let projectContext, !projectContext.isEmpty {
            system += "\n\nProjektkontext:\n" + truncateToTokens(projectContext, tokens: budget / 4)
        }

        // Relevante Nachrichten (Hinweise und Fehlermeldungen gehören nicht zum Gespräch)
        let relevant = messages.filter { m in
            switch m.role {
            case .user, .assistant: return !m.isError && !m.text.isEmpty
            case .expert: return !m.isError && !m.text.isEmpty
            case .event: return false
            }
        }
        var systemTokens = TaskAnalyzer.estimateTokens(system)
        let hasOlder = relevant.count > 6
        let summaryReserve = hasOlder ? budget * 15 / 100 : 0
        var remaining = budget - systemTokens - summaryReserve

        var included: [PromptMessage] = []
        var includedCount = 0
        var cutIndex = relevant.count
        for (offset, message) in relevant.enumerated().reversed() {
            let content = promptText(for: message)
            let tokens = TaskAnalyzer.estimateTokens(content) + 6
            let isLatest = offset == relevant.count - 1
            if tokens <= remaining {
                included.insert(PromptMessage(role: promptRole(message), content: content), at: 0)
                remaining -= tokens
                includedCount += 1
                cutIndex = offset
            } else if isLatest {
                // Die aktuelle Anfrage kommt immer mit – notfalls gekürzt.
                let fitted = truncateToTokens(content, tokens: max(256, remaining))
                included.insert(PromptMessage(role: promptRole(message), content: fitted), at: 0)
                remaining -= TaskAnalyzer.estimateTokens(fitted)
                includedCount += 1
                cutIndex = offset
                break
            } else {
                break
            }
        }

        // Ältere Nachrichten zusammenfassen
        let older = Array(relevant.prefix(cutIndex))
        if !older.isEmpty {
            let summary = extractiveSummary(older, tokens: max(summaryReserve, 200))
            system += "\n\nZusammenfassung des früheren Verlaufs (\(older.count) Nachrichten):\n" + summary
            systemTokens = TaskAnalyzer.estimateTokens(system)
        }

        // Vorlagen verlangen meist: erst Nutzer, dann abwechselnd. Gleiche Rollen zusammenführen.
        var merged: [PromptMessage] = []
        for m in included {
            if let last = merged.last, last.role == m.role {
                merged[merged.count - 1].content = last.content + "\n\n" + m.content
            } else {
                merged.append(m)
            }
        }
        while let first = merged.first, first.role == .assistant {
            merged.removeFirst()
        }
        let all = [PromptMessage(role: .system, content: system)] + merged
        let total = all.reduce(0) { $0 + TaskAnalyzer.estimateTokens($1.content) + 6 }
        return ContextPackage(messages: all, estimatedTokens: total, summarizedMessages: older.count,
                              includedMessages: includedCount, handoff: handoff, state: state)
    }

    static func promptRole(_ m: ChatMessage) -> PromptMessage.Role {
        m.role == .assistant ? .assistant : .user
    }

    static func promptText(for m: ChatMessage) -> String {
        switch m.role {
        case .expert:
            return "Externe Zweitmeinung (\(m.expertProvider ?? "Experte")) – bitte kritisch bewerten:\n\(m.text)"
        default:
            return m.text
        }
    }

    public static func extractiveSummary(_ messages: [ChatMessage], tokens: Int) -> String {
        var lines: [String] = []
        for m in messages {
            let text = firstSentence(stripCode(m.text), max: m.role == .user ? 180 : 220)
            guard !text.isEmpty else { continue }
            switch m.role {
            case .user: lines.append("- Nutzer: \(text)")
            case .assistant: lines.append("- \(m.modelName ?? "Panora"): \(text)")
            case .expert: lines.append("- Zweitmeinung \(m.expertProvider ?? ""): \(text)")
            case .event: break
            }
        }
        // Bei Überlänge: älteste Zeilen weglassen
        var result = lines
        while TaskAnalyzer.estimateTokens(result.joined(separator: "\n")) > tokens && result.count > 2 {
            result.removeFirst()
        }
        let text = result.joined(separator: "\n")
        return result.count < lines.count ? "- (\(lines.count - result.count) frühere Punkte ausgelassen)\n" + text : text
    }

    // MARK: Zweitmeinung

    /// Text, der an einen externen Experten geht. Wird vor dem Senden vollständig angezeigt.
    public static func expertBrief(messages: [ChatMessage], question: String, maxTokens: Int = 6000) -> String {
        let state = extractState(from: messages)
        var parts: [String] = []
        parts.append("Ich arbeite mit einem lokalen KI-Assistenten an folgender Aufgabe und bitte um eine unabhängige Zweitmeinung.")
        if !state.isEmpty { parts.append("Arbeitsstand:\n" + state.promptBlock) }
        let recent = messages.filter { ($0.role == .user || $0.role == .assistant) && !$0.isError }.suffix(6)
        if !recent.isEmpty {
            var dialog: [String] = []
            for m in recent {
                let who = m.role == .user ? "Nutzer" : "Lokales Modell (\(m.modelName ?? "Panora"))"
                dialog.append("\(who):\n\(m.text)")
            }
            let dialogText = truncateToTokens(dialog.joined(separator: "\n\n"), tokens: Int(Double(maxTokens) * 0.75))
            parts.append("Letzter Verlauf:\n" + dialogText)
        }
        parts.append("Konkrete Frage:\n" + question)
        parts.append("Bitte antworte strukturiert: Einschätzung, Risiken oder Fehler, konkrete Verbesserungen.")
        return truncateToTokens(parts.joined(separator: "\n\n"), tokens: maxTokens)
    }
}
