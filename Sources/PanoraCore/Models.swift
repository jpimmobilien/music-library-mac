import Foundation

// =============================================================================================
// Grundbegriffe von Panora: Fähigkeiten, Aufgabenarten, Lizenzen und die Beschreibung eines lokal
// nutzbaren Modells (`ModelSpec`). Alles hier ist reine Logik ohne Apple-Frameworks.
// =============================================================================================

/// Was ein Modell kann.
public enum Capability: String, Codable, CaseIterable, Sendable, Hashable {
    case chat
    case coding
    case reasoning
    case vision
    case longContext
    case toolUse
    case multilingual

    public var label: String {
        switch self {
        case .chat: return "Chat"
        case .coding: return "Coding"
        case .reasoning: return "Reasoning"
        case .vision: return "Bilder lesen"
        case .longContext: return "Langer Kontext"
        case .toolUse: return "Werkzeuge"
        case .multilingual: return "Mehrsprachig"
        }
    }
}

/// Wo ein Modell läuft.
public enum BackendKind: String, Codable, CaseIterable, Sendable, Hashable {
    case mlx
    case ollama

    public var label: String {
        switch self {
        case .mlx: return "MLX"
        case .ollama: return "Ollama"
        }
    }
}

/// Offenheit: „Open Source“ nur bei OSI-konformen Modellen (Gewichte, Daten und Code offen), sonst „Open Weight“.
public enum Openness: String, Codable, Sendable, Hashable {
    case openSource
    case openWeight
    case unknown

    public var label: String {
        switch self {
        case .openSource: return "Open Source"
        case .openWeight: return "Open Weight"
        case .unknown: return "Offenheit unbekannt"
        }
    }
}

/// Lizenzbedingungen in drei Stufen.
public enum LicenseTerms: String, Codable, Sendable, Hashable {
    case permissive
    case restricted
    case nonCommercial
    case unknown

    public var label: String {
        switch self {
        case .permissive: return "frei nutzbar"
        case .restricted: return "mit Auflagen"
        case .nonCommercial: return "nicht kommerziell"
        case .unknown: return "Lizenz prüfen"
        }
    }
}

public struct LicenseInfo: Codable, Sendable, Hashable {
    /// Kennung wie auf Hugging Face („apache-2.0“, „mit“, „llama3.1“, „gemma“ …).
    public var id: String
    public var name: String
    public var openness: Openness
    public var terms: LicenseTerms
    public var note: String?
    public var url: String?
    /// Regionssperre (z. B. Llama 4 multimodal in der EU) – sperrt die Installation.
    public var regionBlock: String?

    public init(id: String, name: String, openness: Openness, terms: LicenseTerms, note: String? = nil, url: String? = nil, regionBlock: String? = nil) {
        self.id = id
        self.name = name
        self.openness = openness
        self.terms = terms
        self.note = note
        self.url = url
        self.regionBlock = regionBlock
    }

    public static let apache2 = LicenseInfo(id: "apache-2.0", name: "Apache 2.0", openness: .openWeight, terms: .permissive,
                                            note: "Gewichte frei nutzbar, auch kommerziell. Trainingsdaten sind nicht offen.",
                                            url: "https://www.apache.org/licenses/LICENSE-2.0")
    public static let mit = LicenseInfo(id: "mit", name: "MIT", openness: .openWeight, terms: .permissive,
                                        note: "Gewichte frei nutzbar, auch kommerziell. Trainingsdaten sind nicht offen.",
                                        url: "https://opensource.org/license/mit")
    public static let llama = LicenseInfo(id: "llama", name: "Llama Community License", openness: .openWeight, terms: .restricted,
                                          note: "Sondergenehmigung ab 700 Mio. Nutzern, Hinweis „Built with Llama“ nötig.",
                                          url: "https://www.llama.com/license/")
    public static let gemmaTerms = LicenseInfo(id: "gemma", name: "Gemma Terms of Use", openness: .openWeight, terms: .restricted,
                                               note: "Nutzungsrichtlinie von Google gilt (ältere Gemma-Generationen).",
                                               url: "https://ai.google.dev/gemma/terms")
    public static let unknown = LicenseInfo(id: "unknown", name: "Unbekannt", openness: .unknown, terms: .unknown,
                                            note: "Keine Lizenzangabe gefunden – bitte Modellkarte prüfen.")

    /// Lizenz aus einer Hugging-Face-Kennung ableiten (Tag „license:…“ oder `cardData.license`).
    public static func fromIdentifier(_ raw: String?) -> LicenseInfo {
        guard let raw = raw?.lowercased().trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return .unknown }
        switch raw {
        case "apache-2.0", "apache2", "apache 2.0": return .apache2
        case "mit": return .mit
        case "bsd-3-clause", "bsd-2-clause":
            return LicenseInfo(id: raw, name: raw.uppercased(), openness: .openWeight, terms: .permissive)
        case "gemma": return .gemmaTerms
        case "cc-by-nc-4.0", "cc-by-nc-sa-4.0", "cc-by-nc-nd-4.0":
            return LicenseInfo(id: raw, name: raw.uppercased(), openness: .openWeight, terms: .nonCommercial,
                               note: "Nur nicht kommerzielle Nutzung erlaubt.")
        case "cc-by-4.0", "cc-by-sa-4.0":
            return LicenseInfo(id: raw, name: raw.uppercased(), openness: .openWeight, terms: .permissive)
        default:
            if raw.hasPrefix("llama") {
                var info = LicenseInfo.llama
                info.id = raw
                if raw.hasPrefix("llama4") {
                    info.name = "Llama 4 Community License"
                    info.regionBlock = "Die Llama-4-Lizenz schließt Personen und Unternehmen mit Sitz in der EU von den multimodalen Modellen aus."
                }
                return info
            }
            if raw.contains("deepseek") {
                return LicenseInfo(id: raw, name: "DeepSeek License", openness: .openWeight, terms: .restricted,
                                   note: "Eigene Lizenz mit Nutzungsbeschränkungen.")
            }
            if raw.contains("qwen") || raw.contains("tongyi") {
                return LicenseInfo(id: raw, name: "Qwen License", openness: .openWeight, terms: .restricted,
                                   note: "Eigene Lizenz von Alibaba – Bedingungen in der Modellkarte.")
            }
            if raw.contains("mrl") || raw.contains("mistral") || raw.contains("mnpl") {
                return LicenseInfo(id: raw, name: "Mistral Research License", openness: .openWeight, terms: .nonCommercial,
                                   note: "Nur Forschung und nicht kommerzielle Nutzung.")
            }
            if raw == "other" {
                return LicenseInfo(id: raw, name: "Eigene Lizenz", openness: .openWeight, terms: .unknown,
                                   note: "Eigene Lizenz – Bedingungen in der Modellkarte prüfen.")
            }
            return LicenseInfo(id: raw, name: raw, openness: .openWeight, terms: .unknown,
                               note: "Bedingungen in der Modellkarte prüfen.")
        }
    }
}

/// Qualität eines Modells auf vier Achsen (0…10). Werte des Katalogs sind redaktionelle Startwerte;
/// Panora passt sie mit eigenen Messungen (Antwortrate, Abbrüche) an.
public struct Skills: Codable, Sendable, Hashable {
    public var general: Double
    public var coding: Double
    public var reasoning: Double
    public var writing: Double

    public init(general: Double, coding: Double, reasoning: Double, writing: Double) {
        self.general = general
        self.coding = coding
        self.reasoning = reasoning
        self.writing = writing
    }

    public static let neutral = Skills(general: 5, coding: 5, reasoning: 5, writing: 5)
}

/// Ein lokal nutzbares Modell (installiert, im Katalog oder bei Ollama vorhanden).
public struct ModelSpec: Codable, Sendable, Hashable, Identifiable {
    /// Eindeutig: „mlx:mlx-community/Qwen3-8B-4bit“ bzw. „ollama:qwen3:8b“.
    public var id: String
    public var backend: BackendKind
    /// Hugging-Face-Repository bzw. Ollama-Name.
    public var repo: String
    public var displayName: String
    public var family: String
    /// Gesamtparameter in Milliarden.
    public var parametersB: Double?
    /// Aktive Parameter je Token (Mixture of Experts) in Milliarden.
    public var activeParametersB: Double?
    /// Bits je Gewicht (Quantisierung).
    public var bits: Double?
    /// Größe der Gewichte auf dem Datenträger in Bytes.
    public var sizeBytes: Int64
    public var contextLength: Int
    public var capabilities: Set<Capability>
    public var skills: Skills
    public var license: LicenseInfo
    /// Speicher je Token im KV-Cache (aus config.json, sonst geschätzt).
    public var kvBytesPerToken: Int?
    /// Ordner auf dem Datenträger (nur MLX).
    public var localPath: String?
    /// Kurzbeschreibung für die Oberfläche.
    public var summary: String?

    public init(id: String, backend: BackendKind, repo: String, displayName: String, family: String,
                parametersB: Double?, activeParametersB: Double? = nil, bits: Double?, sizeBytes: Int64,
                contextLength: Int, capabilities: Set<Capability>, skills: Skills, license: LicenseInfo,
                kvBytesPerToken: Int? = nil, localPath: String? = nil, summary: String? = nil) {
        self.id = id
        self.backend = backend
        self.repo = repo
        self.displayName = displayName
        self.family = family
        self.parametersB = parametersB
        self.activeParametersB = activeParametersB
        self.bits = bits
        self.sizeBytes = sizeBytes
        self.contextLength = contextLength
        self.capabilities = capabilities
        self.skills = skills
        self.license = license
        self.kvBytesPerToken = kvBytesPerToken
        self.localPath = localPath
        self.summary = summary
    }

    public static func mlxID(_ repo: String) -> String { "mlx:\(repo)" }
    public static func ollamaID(_ name: String) -> String { "ollama:\(name)" }

    /// Parameter, die je Token gerechnet werden (bestimmt das Tempo).
    public var effectiveActiveB: Double {
        activeParametersB ?? parametersB ?? max(0.5, Double(sizeBytes) / 1_000_000_000 * 8 / max(bits ?? 4, 1))
    }

    /// „35B · 3B aktiv · 4 Bit“
    public var shapeLabel: String {
        var parts: [String] = []
        if let p = parametersB { parts.append(Formatting.params(p)) }
        if let a = activeParametersB { parts.append("\(Formatting.params(a)) aktiv") }
        if let b = bits { parts.append(Formatting.bits(b)) }
        return parts.joined(separator: " · ")
    }

    /// Kurzer Name für Chips: „Qwen3.6 35B“
    public var shortName: String { displayName }

    /// Geschätzter KV-Cache je Token, falls nicht aus der Konfiguration bekannt.
    public var kvBytesPerTokenEstimate: Int {
        if let kv = kvBytesPerToken, kv > 0 { return kv }
        // Grobe Schätzung: moderne GQA-Modelle ~ 0,02 MB je Milliarde aktiver Parameter und Token (fp16)
        let active = activeParametersB ?? parametersB ?? 7
        return Int(max(24_000, min(400_000, active * 20_000)))
    }
}

/// Konfiguration eines Modellordners (Auszug aus config.json).
public struct ModelConfigInfo: Sendable, Equatable {
    public var modelType: String?
    public var contextLength: Int?
    public var kvBytesPerToken: Int?
    public var quantBits: Double?
    public var hasVision: Bool

    public init(modelType: String? = nil, contextLength: Int? = nil, kvBytesPerToken: Int? = nil, quantBits: Double? = nil, hasVision: Bool = false) {
        self.modelType = modelType
        self.contextLength = contextLength
        self.kvBytesPerToken = kvBytesPerToken
        self.quantBits = quantBits
        self.hasVision = hasVision
    }

    /// Liest die wichtigsten Werte aus den Bytes einer config.json.
    public static func parse(_ data: Data) -> ModelConfigInfo {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return ModelConfigInfo() }
        // Viele multimodale Modelle legen die Textwerte unter „text_config“ ab.
        let text = (root["text_config"] as? [String: Any]) ?? root
        func int(_ key: String, _ dict: [String: Any]) -> Int? {
            if let v = dict[key] as? Int { return v }
            if let v = dict[key] as? Double { return Int(v) }
            if let v = dict[key] as? NSNumber { return v.intValue }
            return nil
        }
        var info = ModelConfigInfo()
        info.modelType = (root["model_type"] as? String) ?? (text["model_type"] as? String)
        info.contextLength = int("max_position_embeddings", text) ?? int("max_position_embeddings", root)
            ?? int("max_sequence_length", text) ?? int("seq_length", text)
        let layers = int("num_hidden_layers", text)
        let heads = int("num_attention_heads", text)
        let kvHeads = int("num_key_value_heads", text) ?? heads
        let hidden = int("hidden_size", text)
        let headDim = int("head_dim", text) ?? ((hidden != nil && heads != nil && heads! > 0) ? hidden! / heads! : nil)
        if let layers, let kvHeads, let headDim {
            // K und V, je 2 Bytes (fp16)
            info.kvBytesPerToken = layers * kvHeads * headDim * 2 * 2
        }
        if let q = (root["quantization"] as? [String: Any]) ?? (root["quantization_config"] as? [String: Any]),
           let bits = int("bits", q) {
            info.quantBits = Double(bits)
        }
        info.hasVision = root["vision_config"] != nil || root["vision_tower"] != nil
        return info
    }
}
