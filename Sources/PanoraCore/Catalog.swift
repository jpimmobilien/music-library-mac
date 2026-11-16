import Foundation

// =============================================================================================
// Startkatalog: empfohlene Open-Weight-Modelle für einen Mac mit viel Unified Memory.
// Der Katalog ist nur ein Startpunkt – über „Entdecken“ lässt sich jedes MLX-Modell von Hugging Face
// installieren. Größen sind Richtwerte (4 Bit); nach dem Download zählt die echte Größe.
// Stand der Auswahl: 16.11.2026 – alle Repositories in der CI auf Hugging Face geprüft (Größen und Lizenzen).
// Panora prüft beim Download erneut, ob das Repository existiert, und sucht sonst über `searchHint`.
// =============================================================================================

public struct CatalogEntry: Sendable, Hashable, Identifiable {
    public var spec: ModelSpec
    /// Wofür das Modell im AUTO MODE vorgesehen ist (Anzeige).
    public var role: String
    /// Suchbegriff für Hugging Face, falls das Repository umbenannt wurde.
    public var searchHint: String
    /// Repository-Name ist in mlx-swift-lm hinterlegt (bekannt funktionierende Architektur).
    public var verified: Bool

    public var id: String { spec.id }
}

public enum ModelCatalog {
    private static func gb(_ v: Double) -> Int64 { Int64(v * 1_000_000_000) }

    private static func entry(_ repo: String, _ name: String, family: String, params: Double?, active: Double? = nil, bits: Double = 4,
                              size: Double, context: Int, caps: Set<Capability>, skills: Skills, license: LicenseInfo,
                              role: String, summary: String, hint: String, verified: Bool) -> CatalogEntry {
        CatalogEntry(spec: ModelSpec(id: ModelSpec.mlxID(repo), backend: .mlx, repo: repo, displayName: name, family: family,
                                     parametersB: params, activeParametersB: active, bits: bits, sizeBytes: gb(size),
                                     contextLength: context, capabilities: caps.union([.chat]), skills: skills, license: license,
                                     summary: summary),
                     role: role, searchHint: hint, verified: verified)
    }

    public static let entries: [CatalogEntry] = [
        // ── Coding
        entry("mlx-community/Qwen3-Coder-Next-4bit", "Qwen3-Coder-Next", family: "Qwen", params: 80, active: 3,
              size: 44.8, context: 262_144, caps: [.coding, .reasoning, .toolUse, .longContext, .multilingual],
              skills: Skills(general: 7.6, coding: 9.3, reasoning: 8.0, writing: 7.0), license: .apache2,
              role: "Coding „Maximal“ für große Umbauten",
              summary: "Großes Coding-Modell (MoE, 3B aktiv) – stark bei Architektur und Implementierung über viele Dateien.",
              hint: "Qwen3-Coder-Next", verified: true),
        entry("mlx-community/Qwen3.6-35B-A3B-4bit", "Qwen3.6 35B A3B", family: "Qwen", params: 35, active: 3,
              size: 20.4, context: 262_144, caps: [.coding, .reasoning, .toolUse, .longContext, .multilingual],
              skills: Skills(general: 8.4, coding: 8.6, reasoning: 8.3, writing: 8.0), license: .apache2,
              role: "Coding-Agent, Standard",
              summary: "Schnelles Allround-Modell mit sehr guter Coding-Leistung (MoE, 3B aktiv).",
              hint: "Qwen3.6-35B-A3B", verified: true),
        entry("mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit", "Qwen3-Coder 30B A3B", family: "Qwen", params: 30, active: 3,
              size: 17.2, context: 262_144, caps: [.coding, .toolUse, .longContext, .multilingual],
              skills: Skills(general: 6.8, coding: 8.2, reasoning: 7.0, writing: 6.4), license: .apache2,
              role: "Code schreiben, schnell",
              summary: "Auf Code spezialisiert, schnell durch MoE.",
              hint: "Qwen3-Coder-30B-A3B-Instruct", verified: true),
        entry("mlx-community/Devstral-Small-2-24B-Instruct-2512-4bit", "Devstral Small 2", family: "Mistral", params: 24,
              size: 15.1, context: 262_144, caps: [.coding, .toolUse, .longContext, .multilingual],
              skills: Skills(general: 6.8, coding: 8.4, reasoning: 7.0, writing: 6.5), license: .apache2,
              role: "Agentisches Coding",
              summary: "Mistrals Coding-Modell für Agenten-Arbeit in Projekten.",
              hint: "Devstral-Small-2", verified: true),
        // ── Allgemein, Planung, Review
        entry("mlx-community/Qwen3.6-27B-4bit", "Qwen3.6 27B", family: "Qwen", params: 27,
              size: 16.1, context: 262_144, caps: [.coding, .reasoning, .toolUse, .longContext, .multilingual],
              skills: Skills(general: 8.6, coding: 8.5, reasoning: 8.6, writing: 8.3), license: .apache2,
              role: "Planung, Architektur, Review",
              summary: "Dichtes Modell mit hoher Qualität für Analyse, Architektur und Code-Review.",
              hint: "Qwen3.6-27B", verified: true),
        entry("mlx-community/gemma-4-31b-it-4bit", "Gemma 4 31B", family: "Gemma", params: 31,
              size: 18.4, context: 262_144, caps: [.reasoning, .coding, .longContext, .multilingual],
              skills: Skills(general: 8.5, coding: 7.8, reasoning: 8.2, writing: 8.8), license: .apache2,
              role: "Texte, Dokumente, Deutsch",
              summary: "Sehr gute deutsche Texte und Zusammenfassungen.",
              hint: "gemma-4-31b-it", verified: true),
        entry("mlx-community/gemma-4-26b-a4b-it-4bit", "Gemma 4 26B A4B", family: "Gemma", params: 26, active: 4,
              size: 15.3, context: 262_144, caps: [.reasoning, .coding, .longContext, .multilingual],
              skills: Skills(general: 8.2, coding: 7.5, reasoning: 7.8, writing: 8.5), license: .apache2,
              role: "Dokumente und Präsentationen",
              summary: "Schnelles Gemma-MoE für Texte, Gliederungen und Präsentationen.",
              hint: "gemma-4-26b-a4b-it", verified: true),
        entry("mlx-community/gpt-oss-20b-MXFP4-Q8", "gpt-oss 20B", family: "gpt-oss", params: 21, active: 3.6, bits: 4.25,
              size: 12.1, context: 131_072, caps: [.reasoning, .coding, .toolUse, .longContext, .multilingual],
              skills: Skills(general: 7.4, coding: 7.4, reasoning: 8.2, writing: 6.8), license: .apache2,
              role: "Kompaktes Reasoning",
              summary: "Offenes Reasoning-Modell von OpenAI, läuft komplett lokal.",
              hint: "gpt-oss-20b", verified: true),
        entry("mlx-community/Qwen3-30B-A3B-4bit", "Qwen3 30B A3B", family: "Qwen", params: 30, active: 3,
              size: 17.2, context: 40_960, caps: [.reasoning, .coding, .toolUse, .multilingual],
              skills: Skills(general: 7.6, coding: 7.4, reasoning: 7.8, writing: 7.2), license: .apache2,
              role: "Allround, schnell",
              summary: "Bewährtes MoE-Modell der Qwen3-Generation.",
              hint: "Qwen3-30B-A3B", verified: true),
        // ── Schnell und klein
        entry("mlx-community/Qwen3-8B-4bit", "Qwen3 8B", family: "Qwen", params: 8.2,
              size: 4.6, context: 40_960, caps: [.reasoning, .coding, .multilingual],
              skills: Skills(general: 6.6, coding: 6.4, reasoning: 6.9, writing: 6.4), license: .apache2,
              role: "Schnelle Antworten",
              summary: "Kleines, flinkes Modell für Alltagsfragen.",
              hint: "Qwen3-8B", verified: true),
        entry("mlx-community/gemma-4-e4b-it-4bit", "Gemma 4 E4B", family: "Gemma", params: 8, active: 4,
              size: 5.1, context: 131_072, caps: [.multilingual, .longContext],
              skills: Skills(general: 6.2, coding: 5.2, reasoning: 5.6, writing: 6.6), license: .gemmaTerms,
              role: "Schnelles Hilfsmodell",
              summary: "Sehr schnell, gut für kurze Texte und Titel.",
              hint: "gemma-4-e4b-it", verified: true),
        entry("mlx-community/Qwen3-4B-4bit", "Qwen3 4B", family: "Qwen", params: 4,
              size: 2.3, context: 40_960, caps: [.reasoning, .multilingual],
              skills: Skills(general: 5.8, coding: 5.6, reasoning: 6.2, writing: 5.6), license: .apache2,
              role: "Kleinstes Allround-Modell",
              summary: "Läuft auf jedem Apple-Silicon-Mac.",
              hint: "Qwen3-4B", verified: true),
        entry("mlx-community/DeepSeek-R1-Distill-Qwen-7B-4bit", "DeepSeek R1 Distill 7B", family: "DeepSeek", params: 7.6,
              size: 4.3, context: 131_072, caps: [.reasoning, .longContext],
              skills: Skills(general: 5.0, coding: 5.5, reasoning: 7.0, writing: 4.5), license: .mit,
              role: "Mathe und Logik",
              summary: "Denkt Schritt für Schritt – gut für Rechnungen und Logik.",
              hint: "DeepSeek-R1-Distill-Qwen-7B", verified: true),
        entry("mlx-community/Meta-Llama-3.1-8B-Instruct-4bit", "Llama 3.1 8B", family: "Llama", params: 8,
              size: 4.5, context: 131_072, caps: [.longContext, .multilingual, .toolUse],
              skills: Skills(general: 6.0, coding: 5.0, reasoning: 5.0, writing: 6.2), license: {
                  var l = LicenseInfo.llama; l.id = "llama3.1"; return l
              }(),
              role: "Bewährter Klassiker",
              summary: "Weit verbreitet, solide in vielen Sprachen.",
              hint: "Meta-Llama-3.1-8B-Instruct", verified: true),
        entry("mlx-community/Mistral-Nemo-Instruct-2407-4bit", "Mistral Nemo 12B", family: "Mistral", params: 12.2,
              size: 6.9, context: 131_072, caps: [.longContext, .multilingual],
              skills: Skills(general: 6.4, coding: 5.4, reasoning: 5.4, writing: 6.8), license: .apache2,
              role: "Europäische Sprachen",
              summary: "Gute Texte in Deutsch, Französisch und weiteren Sprachen.",
              hint: "Mistral-Nemo-Instruct", verified: true),
        entry("mlx-community/Ministral-3-3B-Instruct-2512-4bit", "Ministral 3 3B", family: "Mistral", params: 3.4,
              size: 2.7, context: 262_144, caps: [.multilingual, .longContext],
              skills: Skills(general: 5.2, coding: 4.6, reasoning: 4.8, writing: 5.6), license: .apache2,
              role: "Winzig und schnell",
              summary: "Sehr kleines Modell für einfache Aufgaben.",
              hint: "Ministral-3-3B-Instruct", verified: true),
    ]

    public struct FamilyInfo: Sendable, Hashable {
        public let name: String
        public let license: String
        public let note: String
    }

    /// Modellfamilien, die Panora im Blick behält (Anzeige in „Entdecken“).
    public static let families: [FamilyInfo] = [
        FamilyInfo(name: "Qwen", license: "Apache 2.0", note: "Starke Coding- und Reasoning-Modelle in vielen Größen."),
        FamilyInfo(name: "Gemma", license: "Apache 2.0 (ab Gemma 4)", note: "Ältere Generationen: Gemma Terms of Use."),
        FamilyInfo(name: "DeepSeek", license: "MIT", note: "Große V-Modelle passen nicht in 64 GB; Distill-Varianten schon."),
        FamilyInfo(name: "Llama", license: "Llama Community License", note: "Llama 4 multimodal: Nutzung in der EU ausgeschlossen."),
        FamilyInfo(name: "Mistral", license: "Apache 2.0 (Small, Devstral Small)", note: "Große Devstral- und Research-Modelle mit Auflagen."),
        FamilyInfo(name: "gpt-oss", license: "Apache 2.0", note: "Offene Reasoning-Modelle von OpenAI."),
    ]

    public static func entry(for repo: String) -> CatalogEntry? {
        entries.first { $0.spec.repo.caseInsensitiveCompare(repo) == .orderedSame }
    }
}

/// Liest Eckdaten aus einem Repository- oder Ollama-Namen („Qwen3-30B-A3B-4bit“, „qwen3:8b“).
public enum ModelNameParser {
    public struct Parsed: Equatable, Sendable {
        public var parametersB: Double?
        public var activeParametersB: Double?
        public var bits: Double?
        public var family: String
        public var isCoder: Bool
        public var isReasoning: Bool
        public var isVision: Bool
        public var isInstruct: Bool
    }

    public static func parse(_ raw: String) -> Parsed {
        let name = raw.split(separator: "/").last.map(String.init) ?? raw
        let lower = name.lowercased()
        var parsed = Parsed(parametersB: nil, activeParametersB: nil, bits: nil, family: family(of: lower),
                            isCoder: lower.contains("coder") || lower.contains("devstral") || lower.contains("codestral") || lower.contains("code"),
                            isReasoning: lower.contains("r1") || lower.contains("think") || lower.contains("reason") || lower.contains("qwq") || lower.contains("gpt-oss"),
                            isVision: lower.contains("-vl") || lower.contains("vision") || lower.contains("llava") || lower.contains("pixtral"),
                            isInstruct: lower.contains("instruct") || lower.contains("-it") || lower.contains("chat"))
        // Token für Token: „30b“, „a3b“, „e4b“, „0.6b“, „4bit“, „q4“, „mxfp4“, „8x7b“
        let tokens = lower.replacingOccurrences(of: ":", with: "-").split(whereSeparator: { "-_ ".contains($0) }).map(String.init)
        for token in tokens {
            if let b = bitsToken(token) { parsed.bits = parsed.bits ?? b; continue }
            if token.hasPrefix("a"), token.hasSuffix("b"), let v = Double(token.dropFirst().dropLast()) {
                parsed.activeParametersB = v; continue
            }
            if token.hasPrefix("e"), token.hasSuffix("b"), let v = Double(token.dropFirst().dropLast()) {
                // Gemma „E4B“: effektiv 4B
                parsed.activeParametersB = v
                parsed.parametersB = parsed.parametersB ?? v * 2
                continue
            }
            if token.contains("x"), token.hasSuffix("b") {
                let parts = token.dropLast().split(separator: "x")
                if parts.count == 2, let n = Double(parts[0]), let s = Double(parts[1]) { parsed.parametersB = n * s; continue }
            }
            if token.hasSuffix("b"), let v = Double(token.dropLast()), v > 0, v < 3000 {
                if parsed.parametersB == nil { parsed.parametersB = v }
                continue
            }
            if token.hasSuffix("m"), let v = Double(token.dropLast()), v >= 100, v < 1000 {
                parsed.parametersB = parsed.parametersB ?? v / 1000
            }
        }
        return parsed
    }

    private static func bitsToken(_ t: String) -> Double? {
        if t.hasSuffix("bit"), let v = Double(t.dropLast(3)) { return v }
        if t == "mxfp4" || t == "fp4" || t == "nvfp4" { return 4.25 }
        if t == "bf16" || t == "fp16" || t == "f16" { return 16 }
        if t == "fp8" || t == "q8" || t == "q8_0" { return 8 }
        if t.hasPrefix("q"), t.count >= 2 {
            let digits = t.dropFirst().prefix(while: { $0.isNumber })
            if let v = Double(digits), v >= 2, v <= 8 { return v }
        }
        return nil
    }

    public static func family(of lower: String) -> String {
        // Spezifische Namen zuerst („DeepSeek-R1-Distill-Qwen“ ist DeepSeek, nicht Qwen).
        let table: [(String, String)] = [("deepseek", "DeepSeek"), ("gpt-oss", "gpt-oss"), ("devstral", "Mistral"),
                                         ("codestral", "Mistral"), ("ministral", "Mistral"), ("mixtral", "Mistral"),
                                         ("pixtral", "Mistral"), ("magistral", "Mistral"), ("mistral", "Mistral"),
                                         ("qwq", "Qwen"), ("qwen", "Qwen"), ("gemma", "Gemma"), ("llama", "Llama"),
                                         ("phi", "Phi"), ("glm", "GLM"), ("granite", "Granite"), ("olmo", "OLMo"),
                                         ("smollm", "SmolLM"), ("lfm", "LFM"), ("nemotron", "Nemotron"), ("kimi", "Kimi"),
                                         ("minimax", "MiniMax"), ("ernie", "ERNIE"), ("hunyuan", "Hunyuan"), ("exaone", "EXAONE")]
        for (key, value) in table where lower.contains(key) { return value }
        return "Weitere"
    }

    /// Fähigkeiten und Startwerte für Modelle außerhalb des Katalogs (heuristisch, transparent als Schätzung).
    public static func estimatedSkills(for parsed: Parsed) -> Skills {
        let active = parsed.activeParametersB ?? parsed.parametersB ?? 7
        let total = parsed.parametersB ?? active
        // Größe treibt die Qualität, logarithmisch; MoE zählt zwischen aktiv und gesamt.
        let effective = parsed.activeParametersB != nil ? sqrt(active * total) : total
        let base = min(8.6, max(3.5, 3.2 + 1.6 * log2(max(effective, 0.5) + 1)))
        var s = Skills(general: base, coding: base - 0.3, reasoning: base - 0.2, writing: base)
        if parsed.isCoder { s.coding += 1.2; s.writing -= 0.6; s.general -= 0.3 }
        if parsed.isReasoning { s.reasoning += 1.0; s.writing -= 0.4 }
        s.general = min(10, s.general); s.coding = min(10, s.coding); s.reasoning = min(10, s.reasoning); s.writing = min(10, s.writing)
        return s
    }

    public static func estimatedCapabilities(for parsed: Parsed, contextLength: Int) -> Set<Capability> {
        var caps: Set<Capability> = [.chat, .multilingual]
        if parsed.isCoder { caps.insert(.coding) }
        if parsed.isReasoning { caps.insert(.reasoning) }
        if parsed.isVision { caps.insert(.vision) }
        if contextLength >= 65_536 { caps.insert(.longContext) }
        if (parsed.parametersB ?? 0) >= 7 { caps.insert(.coding); caps.insert(.reasoning) }
        return caps
    }
}
