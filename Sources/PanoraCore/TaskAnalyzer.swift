import Foundation

// =============================================================================================
// Aufgabenerkennung für den AUTO MODE: feste, nachvollziehbare Regeln (Deutsch und Englisch).
// Ergebnis ist ein `TaskProfile` mit Aufgabenart, Schwierigkeit, Kontextgröße und den Belegen,
// die Panora dem Nutzer als Begründung anzeigt.
// =============================================================================================

public enum TaskKind: String, Codable, CaseIterable, Sendable, Hashable {
    case smallTalk
    case question
    case writing
    case summarization
    case translation
    case analysis
    case planning
    case coding
    case debugging
    case review
    case math
    case reasoning
    case longDocument

    public var label: String {
        switch self {
        case .smallTalk: return "Kurzer Austausch"
        case .question: return "Frage"
        case .writing: return "Text schreiben"
        case .summarization: return "Zusammenfassen"
        case .translation: return "Übersetzen"
        case .analysis: return "Analyse"
        case .planning: return "Planung und Architektur"
        case .coding: return "Code schreiben"
        case .debugging: return "Fehler finden"
        case .review: return "Überprüfen"
        case .math: return "Rechnen"
        case .reasoning: return "Logik und Begründung"
        case .longDocument: return "Langes Dokument"
        }
    }

    /// Gewichtung der Qualitätsachsen für diese Aufgabe.
    public var weights: (general: Double, coding: Double, reasoning: Double, writing: Double) {
        switch self {
        case .smallTalk, .question: return (0.7, 0.0, 0.15, 0.15)
        case .writing, .translation: return (0.25, 0.0, 0.05, 0.7)
        case .summarization, .longDocument: return (0.4, 0.0, 0.2, 0.4)
        case .analysis: return (0.3, 0.3, 0.4, 0.0)
        case .planning: return (0.25, 0.3, 0.45, 0.0)
        case .coding: return (0.05, 0.8, 0.15, 0.0)
        case .debugging: return (0.0, 0.7, 0.3, 0.0)
        case .review: return (0.0, 0.55, 0.45, 0.0)
        case .math, .reasoning: return (0.15, 0.0, 0.85, 0.0)
        }
    }

    /// Ist das ein Software-Arbeitsschritt (Analyse → Architektur → Implementierung → Review)?
    public var isSoftwareStep: Bool { [.analysis, .planning, .coding, .debugging, .review].contains(self) }
}

public struct TaskProfile: Sendable, Equatable {
    public var kind: TaskKind
    /// Weitere erkannte Anteile (absteigend).
    public var secondary: [TaskKind]
    /// Harte Anforderungen (z. B. Bilder lesen).
    public var required: Set<Capability>
    public var estimatedInputTokens: Int
    /// 1 (trivial) … 5 (sehr anspruchsvoll)
    public var difficulty: Int
    public var prefersSpeed: Bool
    /// Belege in Klartext („Code-Block erkannt“, „Swift-Schlüsselwörter“).
    public var signals: [String]
    public var language: String
    public var mentionsCode: Bool

    public init(kind: TaskKind, secondary: [TaskKind] = [], required: Set<Capability> = [], estimatedInputTokens: Int = 0,
                difficulty: Int = 2, prefersSpeed: Bool = false, signals: [String] = [], language: String = "de", mentionsCode: Bool = false) {
        self.kind = kind
        self.secondary = secondary
        self.required = required
        self.estimatedInputTokens = estimatedInputTokens
        self.difficulty = difficulty
        self.prefersSpeed = prefersSpeed
        self.signals = signals
        self.language = language
        self.mentionsCode = mentionsCode
    }
}

public enum TaskAnalyzer {
    private struct Rule {
        let kind: TaskKind
        let weight: Double
        let keywords: [String]
        let signal: String
    }

    private static let rules: [Rule] = [
        Rule(kind: .coding, weight: 2.2, keywords: ["implementier", "programmier", "schreib den code", "schreibe code", "code für",
                                                    "funktion", "methode", "klasse ", "refactor", "refaktor", "unit-test", "unittest",
                                                    "write a function", "implement", "swiftui", "jetpack compose", "kotlin", "swift ",
                                                    "gradle", "xcode", "android", "api-", "endpoint", "regex", "sql", "skript", "script",
                                                    "baue die", "baue eine app", "code", "compose", "viewmodel", "repository-klasse"],
             signal: "Programmier-Begriffe"),
        Rule(kind: .debugging, weight: 2.6, keywords: ["fehler", "error", "exception", "crash", "stacktrace", "stack trace", "absturz",
                                                       "stürzt ab", "bug", "funktioniert nicht", "geht nicht", "build failed",
                                                       "kompiliert nicht", "compile error", "warnung", "warning:", "nullpointer", "fatal"],
             signal: "Fehlermeldung oder Problem"),
        Rule(kind: .review, weight: 2.4, keywords: ["überprüf", "ueberpruef", "review", "prüfe", "pruefe", "code-review", "kontrollier",
                                                    "schau dir", "verbesserungsvorschl", "was ist falsch", "check the", "audit"],
             signal: "Prüfauftrag"),
        Rule(kind: .planning, weight: 2.3, keywords: ["architektur", "architecture", "konzept", "struktur", "entwirf", "entwurf",
                                                      "design", "roadmap", "plan ", "planung", "vorgehen", "strategie", "schritte",
                                                      "aufbau", "modul", "datenmodell", "schichten", "meilenstein"],
             signal: "Planung oder Architektur"),
        Rule(kind: .analysis, weight: 2.0, keywords: ["analysier", "analyse", "untersuch", "bewerte", "vergleich", "erklär mir das projekt",
                                                      "verstehe das projekt", "projekt an", "codebase", "was macht", "wie funktioniert",
                                                      "analyze", "explain this"],
             signal: "Analyseauftrag"),
        Rule(kind: .summarization, weight: 2.5, keywords: ["fasse", "zusammenfass", "zusammen.", "tl;dr", "kurzfassung", "summar",
                                                           "die wichtigsten punkte", "kernaussagen", "stichpunkte"],
             signal: "Zusammenfassung gewünscht"),
        Rule(kind: .translation, weight: 2.8, keywords: ["übersetz", "uebersetz", "translate", "auf englisch", "ins englische",
                                                         "ins deutsche", "auf deutsch", "auf französisch", "auf spanisch", "in english"],
             signal: "Übersetzung"),
        Rule(kind: .writing, weight: 1.8, keywords: ["schreib", "formulier", "e-mail", "email", "brief", "anschreiben", "artikel",
                                                     "blogpost", "beitrag", "text für", "präsentation", "praesentation", "folien",
                                                     "dokument", "bericht", "angebot", "exposé", "expose", "write a", "draft"],
             signal: "Textauftrag"),
        Rule(kind: .math, weight: 2.4, keywords: ["berechne", "rechne", "ausrechnen", "gleichung", "integral", "ableitung",
                                                  "wahrscheinlichkeit", "prozent", "zinsen", "rendite", "summe von", "mittelwert",
                                                  "calculate", "solve"],
             signal: "Rechenaufgabe"),
        Rule(kind: .reasoning, weight: 1.6, keywords: ["warum", "begründ", "logik", "beweis", "rätsel", "raetsel",
                                                       "schritt für schritt", "abwägen", "vor- und nachteile", "pro und contra",
                                                       "entscheidung", "why", "reason", "trade-off"],
             signal: "Begründung gefragt"),
    ]

    private static let smallTalkWords = ["hallo", "hi", "hey", "moin", "servus", "danke", "dankeschön", "super", "ok", "okay",
                                         "guten morgen", "guten abend", "wie geht", "tschüss", "bis später", "hello", "thanks"]

    private static let continuationWords = ["weiter", "mach weiter", "fortfahren", "continue", "und jetzt", "nächster schritt",
                                            "naechster schritt", "ja, bitte", "ja bitte", "mach das", "los", "go on", "genau so"]

    private static let codeMarkers = ["```", "func ", "fun ", "class ", "struct ", "import ", "val ", "var ", "let ", "def ",
                                      "public ", "private ", "return ", "=> ", "->", "};", "@Composable", "@State", "#include"]

    private static let fileExtensions = [".swift", ".kt", ".kts", ".java", ".py", ".js", ".ts", ".tsx", ".gradle", ".xml",
                                         ".json", ".yml", ".yaml", ".cpp", ".c", ".h", ".rs", ".go", ".sql", ".sh", ".md"]

    /// Grobe Tokenzahl (≈ 3,6 Zeichen je Token für Deutsch/Englisch/Code).
    public static func estimateTokens(_ text: String) -> Int {
        max(1, Int((Double(text.utf8.count) / 3.6).rounded(.up)))
    }

    /// Analysiert eine Anfrage. `previous` ist die Aufgabenart der letzten Anfrage im selben Chat
    /// (Fortsetzungen wie „mach weiter“ behalten sie), `contextTokens` der bisherige Verlauf.
    public static func analyze(_ text: String, previous: TaskKind? = nil, attachedContextTokens: Int = 0) -> TaskProfile {
        let lower = text.lowercased()
        let trimmed = lower.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let tokens = estimateTokens(text) + attachedContextTokens
        var scores: [TaskKind: Double] = [:]
        var signals: [String] = []

        // Code im Text
        let codeHits = codeMarkers.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
        let braces = text.filter { $0 == "{" || $0 == "}" }.count
        let fileHits = fileExtensions.filter { lower.contains($0) }
        let mentionsCode = text.contains("```") || codeHits >= 2 || braces >= 4 || !fileHits.isEmpty
        if text.contains("```") { signals.append("Code-Block erkannt") }
        else if codeHits >= 2 || braces >= 4 { signals.append("Quelltext erkannt") }
        if let ext = fileHits.first { signals.append("Datei \(ext) erwähnt") }
        if mentionsCode { scores[.coding, default: 0] += 1.5 }

        for rule in rules {
            let hits = rule.keywords.filter { lower.contains($0) }.count
            if hits > 0 {
                scores[rule.kind, default: 0] += rule.weight + Double(hits - 1) * 0.5
                signals.append(rule.signal)
            }
        }

        // Prüf- und Fehleraufträge mit Code-Bezug haben Vorrang vor „Code schreiben“
        if mentionsCode {
            for k in [TaskKind.review, .debugging] where scores[k] != nil { scores[k]! += 1.6 }
        }

        // Rechenausdrücke wie „17 * 23“ oder „12 % von 400“
        if lower.range(of: #"\d+\s*[\+\-\*/×÷^]\s*\d+"#, options: .regularExpression) != nil {
            scores[.math, default: 0] += 2.0
            signals.append("Rechenausdruck")
        }

        // Fehlersuche und Review gibt es nur mit Code-Bezug in voller Stärke
        if !mentionsCode && (scores[.coding] ?? 0) == 0 {
            if let d = scores[.debugging] { scores[.debugging] = d * 0.5; scores[.question, default: 0] += d * 0.4 }
            if let r = scores[.review] { scores[.review] = r * 0.6; scores[.writing, default: 0] += r * 0.3 }
        }

        let isSmallTalk = words <= 6 && smallTalkWords.contains { trimmed.hasPrefix($0) } && !mentionsCode
        let isContinuation = words <= 8 && continuationWords.contains { trimmed.hasPrefix($0) || trimmed == $0 }

        var kind: TaskKind
        let ranked = scores.sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }
        if isContinuation, let previous {
            kind = previous
            signals.insert("Fortsetzung der vorherigen Aufgabe", at: 0)
        } else if isSmallTalk && (ranked.first?.value ?? 0) < 1.7 {
            kind = .smallTalk
            signals = ["Kurze Nachricht"]
        } else if let top = ranked.first {
            kind = top.key
        } else {
            kind = .question
        }

        // Sehr lange Eingaben: langes Dokument (außer bei klaren Code-Aufgaben)
        if tokens > 12_000 && !kind.isSoftwareStep {
            kind = .longDocument
            signals.append("Sehr lange Eingabe")
        }

        let secondary = ranked.map { $0.key }.filter { $0 != kind }.prefix(2)

        // Schwierigkeit
        var difficulty = 2
        if kind == .smallTalk { difficulty = 1 }
        else {
            if words > 40 { difficulty += 1 }
            if words > 160 || tokens > 4_000 { difficulty += 1 }
            if [.planning, .review, .debugging].contains(kind) { difficulty += 1 }
            let hardWords = ["komplex", "ganze projekt", "gesamte", "alle dateien", "architektur", "skalierbar", "produktionsreif",
                             "sicherheit", "performance", "optimier", "mehrere", "vollständig", "detailliert", "gründlich"]
            if hardWords.contains(where: { lower.contains($0) }) { difficulty += 1 }
            if words <= 10 && !mentionsCode && !kind.isSoftwareStep { difficulty -= 1 }
        }
        difficulty = max(1, min(5, difficulty))

        let speedWords = ["kurz", "schnell", "knapp", "in einem satz", "ein wort", "quick", "brief"]
        let prefersSpeed = difficulty <= 2 || speedWords.contains { lower.contains($0) }

        var required: Set<Capability> = []
        if tokens > 24_000 { required.insert(.longContext) }

        let germanHints = [" der ", " die ", " und ", " ist ", " nicht ", " ich ", " bitte", "ä", "ö", "ü", "ß"]
        let language = germanHints.contains { lower.contains($0) } || words <= 3 ? "de" : "en"

        var uniqueSignals: [String] = []
        for s in signals where !uniqueSignals.contains(s) { uniqueSignals.append(s) }

        return TaskProfile(kind: kind, secondary: Array(secondary), required: required, estimatedInputTokens: tokens,
                           difficulty: difficulty, prefersSpeed: prefersSpeed, signals: uniqueSignals, language: language,
                           mentionsCode: mentionsCode)
    }
}
