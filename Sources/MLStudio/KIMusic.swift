import Foundation

// KI-Musik (lokal, ACE-Step 1.5) – reine Logik: Hardwareprüfung, Modellkatalog, Sprachen, Qualitätsstufen,
// Aufbau einer Anfrage an den lokalen Rechenprozess, Schätzung der Dauer und die Kreationen-Bibliothek.
// Ohne Apple-Frameworks, unter Linux getestet. Die Werte stammen aus dem Quelltext von ACE-Step 1.5
// (Stand ca1e85f) und den Messungen der KI-Probe (docs/KI_MUSIK_MACHBARKEIT.md).

// MARK: - Hardware

public enum KISupport: Equatable, Sendable {
    /// Läuft; empfohlenes Sprachmodell für diesen Rechner.
    case supported(recommendedLM: String)
    /// Läuft eingeschränkt (wenig Arbeitsspeicher).
    case limited(recommendedLM: String?, reason: String)
    /// Läuft nicht (z. B. Intel-Mac).
    case unsupported(reason: String)

    public var isUsable: Bool {
        if case .unsupported = self { return false }
        return true
    }
}

public enum KIHardware {
    /// - Parameters:
    ///   - machine: `uname -m` bzw. `hw.machine` (arm64 / x86_64)
    ///   - translated: läuft die App unter Rosetta (sysctl.proc_translated)
    ///   - memoryGB: Arbeitsspeicher in GB
    ///   - macOSMajor: Hauptversion von macOS
    public static func support(machine: String, translated: Bool, memoryGB: Double, macOSMajor: Int) -> KISupport {
        if machine != "arm64" && !translated {
            return .unsupported(reason: "KI-Musik braucht einen Mac mit Apple-Chip (M1 oder neuer). Auf Intel-Macs gibt es "
                                + "die nötigen Bausteine (PyTorch, MLX) nicht mehr – die übrige Musikbibliothek funktioniert wie gewohnt.")
        }
        if macOSMajor < 14 {
            return .unsupported(reason: "KI-Musik braucht macOS 14 Sonoma oder neuer (für MLX und PyTorch auf Apple-Chips).")
        }
        if memoryGB < 12 {
            return .limited(recommendedLM: nil, reason: "Mit \(Int(memoryGB.rounded())) GB Arbeitsspeicher läuft nur das Musikmodell ohne "
                            + "Sprachmodell – Songtexte schreibt die KI dann nicht selbst, und es ist langsam.")
        }
        if memoryGB < 24 {
            return .limited(recommendedLM: KIModel.lmSmall.id, reason: "Mit \(Int(memoryGB.rounded())) GB Arbeitsspeicher wird das kleine "
                            + "Sprachmodell verwendet.")
        }
        return .supported(recommendedLM: memoryGB >= 40 ? KIModel.lmLarge.id : KIModel.lmMedium.id)
    }
}

// MARK: - Modelle

/// Ein herunterladbares Modell (Hugging Face, Organisation „ACE-Step“).
public struct KIModel: Hashable, Sendable, Identifiable {
    /// Ordnername unter `checkpoints/` (wie in ACE-Step).
    public let id: String
    public let repo: String
    public let title: String
    public let purpose: String
    /// Größe auf der Platte in Bytes (nil = vor dem Laden unbekannt).
    public let bytes: Int64?
    /// `bytes` ist eine Angabe der Entwickler, nicht selbst gemessen.
    public var approximate: Bool = false
    /// Teil des Grundpakets (`ACE-Step/Ace-Step1.5`).
    public let core: Bool
    public let license: String

    /// Grundpaket: Musikmodell „turbo“, Text-Encoder, VAE und Sprachmodell 1.7B (gemessen: 10,4 GB).
    public static let core = KIModel(id: "Ace-Step1.5", repo: "ACE-Step/Ace-Step1.5", title: "ACE-Step 1.5 – Grundpaket",
                                     purpose: "Musikmodell (turbo), Text-Encoder, VAE und Sprachmodell 1.7B",
                                     bytes: 10_420_000_000, core: true, license: "MIT")
    public static let lmSmall = KIModel(id: "acestep-5Hz-lm-0.6B", repo: "ACE-Step/acestep-5Hz-lm-0.6B", title: "Sprachmodell klein (0.6B)",
                                        purpose: "Songtexte und Planung – für Macs mit wenig Arbeitsspeicher",
                                        bytes: 1_300_000_000, core: false, license: "MIT")
    public static let lmMedium = KIModel(id: "acestep-5Hz-lm-1.7B", repo: "ACE-Step/Ace-Step1.5", title: "Sprachmodell 1.7B",
                                         purpose: "Songtexte und Planung (im Grundpaket)", bytes: nil, core: true, license: "MIT")
    public static let lmLarge = KIModel(id: "acestep-5Hz-lm-4B", repo: "ACE-Step/acestep-5Hz-lm-4B", title: "Sprachmodell groß (4B)",
                                        purpose: "Beste Songtexte und Planung – empfohlen ab 32 GB Arbeitsspeicher",
                                        bytes: nil, core: false, license: "MIT")

    /// Größeres Musikmodell (4B statt 2B) – laut ACE-Step höhere Klangqualität, ca. 9 GB (Angabe der Entwickler).
    public static let xlTurbo = KIModel(id: "acestep-v15-xl-turbo", repo: "ACE-Step/acestep-v15-xl-turbo", title: "Musikmodell XL (4B)",
                                        purpose: "Höhere Klangqualität – für die Stufe „Hohe Qualität“, ab 24 GB Arbeitsspeicher",
                                        bytes: 9_000_000_000, approximate: true, core: false, license: "MIT")

    public static let optional: [KIModel] = [xlTurbo, lmLarge, lmSmall]
}

// MARK: - Sprachen

public struct KILanguage: Hashable, Sendable, Identifiable {
    /// ISO-639-1-Code wie in ACE-Step (`vocal_language`).
    public let id: String
    public let name: String
    /// Hervorgehoben (oben in der Auswahl).
    public let featured: Bool

    /// Von ACE-Step 1.5 angenommene Sprachen (acestep/constants.py, VALID_LANGUAGES), deutsche Namen.
    public static let all: [KILanguage] = {
        let featured: [(String, String)] = [("de", "Deutsch"), ("en", "Englisch"), ("fr", "Französisch"), ("es", "Spanisch"),
                                            ("it", "Italienisch"), ("pt", "Portugiesisch"), ("nl", "Niederländisch")]
        let others: [(String, String)] = [
            ("ar", "Arabisch"), ("az", "Aserbaidschanisch"), ("bg", "Bulgarisch"), ("bn", "Bengalisch"), ("ca", "Katalanisch"),
            ("cs", "Tschechisch"), ("da", "Dänisch"), ("el", "Griechisch"), ("fa", "Persisch"), ("fi", "Finnisch"),
            ("he", "Hebräisch"), ("hi", "Hindi"), ("hr", "Kroatisch"), ("ht", "Haitianisch"), ("hu", "Ungarisch"),
            ("id", "Indonesisch"), ("is", "Isländisch"), ("ja", "Japanisch"), ("ko", "Koreanisch"), ("la", "Latein"),
            ("lt", "Litauisch"), ("ms", "Malaiisch"), ("ne", "Nepali"), ("no", "Norwegisch"), ("pa", "Panjabi"),
            ("pl", "Polnisch"), ("ro", "Rumänisch"), ("ru", "Russisch"), ("sa", "Sanskrit"), ("sk", "Slowakisch"),
            ("sr", "Serbisch"), ("sv", "Schwedisch"), ("sw", "Suaheli"), ("ta", "Tamil"), ("te", "Telugu"), ("th", "Thai"),
            ("tl", "Tagalog"), ("tr", "Türkisch"), ("uk", "Ukrainisch"), ("ur", "Urdu"), ("vi", "Vietnamesisch"),
            ("yue", "Kantonesisch"), ("zh", "Chinesisch"),
        ]
        return featured.map { KILanguage(id: $0.0, name: $0.1, featured: true) }
            + others.sorted { $0.1 < $1.1 }.map { KILanguage(id: $0.0, name: $0.1, featured: false) }
    }()

    public static func named(_ id: String) -> KILanguage? { all.first { $0.id == id } }
}

// MARK: - Anfrage

/// Qualitätsstufen nach den Modellen von ACE-Step 1.5 (README „Model Zoo“): turbo (2B) und XL-turbo (4B) mit je
/// 8 Schritten; „Planung“ = Sprachmodell erzeugt Metadaten und Klangcodes vor dem Musikmodell.
public enum KIQuality: String, CaseIterable, Codable, Sendable {
    /// Musikmodell turbo (2B), ohne Planung durch das Sprachmodell.
    case fast
    /// Musikmodell turbo (2B) mit Planung – Standard.
    case balanced
    /// Musikmodell XL-turbo (4B) mit Planung – braucht das XL-Modell (zusätzlicher Download).
    case high

    public var label: String {
        switch self {
        case .fast: return "Schnell"
        case .balanced: return "Ausgewogen"
        case .high: return "Hohe Qualität"
        }
    }

    public var usesPlanning: Bool { self != .fast }

    /// Ordnername des Musikmodells.
    public var ditModel: String { self == .high ? KIModel.xlTurbo.id : "acestep-v15-turbo" }

    public var detail: String {
        switch self {
        case .fast: return "Musikmodell 2B ohne Planung – am schnellsten, Songtexte nur vorgegeben"
        case .balanced: return "Musikmodell 2B mit Planung durch das Sprachmodell"
        case .high: return "Musikmodell XL (4B) mit Planung – höhere Klangqualität, langsamer, ca. 9 GB zusätzlich"
        }
    }
}

/// Wie der Songtext entsteht (Master-Prompt, Abschnitt 6).
public enum KILyricsMode: String, CaseIterable, Codable, Sendable {
    /// Ohne Gesang.
    case instrumental
    /// Die KI schreibt den Text aus der Beschreibung.
    case aiWrites
    /// Eigener Text, unverändert gesungen.
    case own
    /// Eigener Text wird von der KI überarbeitet (Struktur, Reime).
    case revise

    public var label: String {
        switch self {
        case .instrumental: return "Instrumental"
        case .aiWrites: return "KI schreibt den Text"
        case .own: return "Eigener Text"
        case .revise: return "Text überarbeiten lassen"
        }
    }
}

public struct KIGenerationRequest: Codable, Hashable, Sendable {
    public var prompt: String
    public var lyricsMode: KILyricsMode
    public var lyrics: String
    /// ISO-Code; Pflicht bei Gesang.
    public var language: String
    /// Sekunden (10 … 600); nil = das Modell wählt.
    public var duration: Double?
    public var bpm: Int?
    /// z. B. „A minor“, „C# major“ (leer = frei)
    public var key: String
    /// „2“, „3“, „4“, „6“ (leer = frei)
    public var timeSignature: String
    public var seed: Int?
    public var variations: Int
    public var quality: KIQuality

    public init(prompt: String = "", lyricsMode: KILyricsMode = .instrumental, lyrics: String = "", language: String = "de",
                duration: Double? = 120, bpm: Int? = nil, key: String = "", timeSignature: String = "", seed: Int? = nil,
                variations: Int = 1, quality: KIQuality = .balanced) {
        self.prompt = prompt
        self.lyricsMode = lyricsMode
        self.lyrics = lyrics
        self.language = language
        self.duration = duration
        self.bpm = bpm
        self.key = key
        self.timeSignature = timeSignature
        self.seed = seed
        self.variations = variations
        self.quality = quality
    }

    public static let minDuration: Double = 10
    public static let maxDuration: Double = 600
    public static let maxVariations = 4

    public var instrumental: Bool { lyricsMode == .instrumental }

    /// Fehler, die vor dem Start gemeldet werden (nil = in Ordnung).
    public var problem: String? {
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Beschreibe zuerst die Musik." }
        if prompt.count > 2000 { return "Die Beschreibung ist zu lang (höchstens 2000 Zeichen)." }
        if (lyricsMode == .own || lyricsMode == .revise) && lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Gib einen Songtext ein – oder lass die KI ihn schreiben."
        }
        if !instrumental && KILanguage.named(language) == nil { return "Wähle die Sprache des Gesangs." }
        if let d = duration, d < Self.minDuration || d > Self.maxDuration { return "Die Länge muss zwischen 10 Sekunden und 10 Minuten liegen." }
        if let b = bpm, b < 30 || b > 300 { return "Das Tempo muss zwischen 30 und 300 BPM liegen." }
        if variations < 1 || variations > Self.maxVariations { return "1 bis \(Self.maxVariations) Varianten." }
        return nil
    }

    /// Parameter für `GenerationParams` von ACE-Step (Namen wie dort). `lyricsOverride`: vom Sprachmodell geschriebener
    /// bzw. überarbeiteter Text.
    public func engineParams(lyricsOverride: String? = nil, captionOverride: String? = nil) -> [String: KIValue] {
        var p: [String: KIValue] = [
            "task_type": .string("text2music"),
            "caption": .string(captionOverride ?? prompt.trimmingCharacters(in: .whitespacesAndNewlines)),
            "instrumental": .bool(instrumental),
            "inference_steps": .int(8),
            "guidance_scale": .double(1.0),
            "thinking": .bool(quality.usesPlanning),
            "seed": .int(seed ?? -1),
        ]
        if instrumental {
            p["lyrics"] = .string("[Instrumental]")
            p["vocal_language"] = .string("unknown")
        } else {
            p["lyrics"] = .string(lyricsOverride ?? lyrics)
            p["vocal_language"] = .string(language)
        }
        if let duration { p["duration"] = .double(duration.rounded()) }
        if let bpm { p["bpm"] = .int(bpm) }
        if !key.isEmpty { p["keyscale"] = .string(key) }
        if !timeSignature.isEmpty { p["timesignature"] = .string(timeSignature) }
        return p
    }
}

/// JSON-Wert für die Anfrage an den Rechenprozess.
public enum KIValue: Codable, Hashable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else { self = .string(try c.decode(String.self)) }
    }
}

// MARK: - Kreationen

public struct KICreation: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case song, instrumental, remix, vocal
        public var label: String {
            switch self {
            case .song: return "Song"
            case .instrumental: return "Instrumental"
            case .remix: return "Remix"
            case .vocal: return "Gesang bearbeitet"
            }
        }
    }

    public var id: UUID
    public var title: String
    public var kind: Kind
    public var date: Date
    /// Datei relativ zum Kreationen-Ordner.
    public var file: String
    public var duration: Double?
    public var prompt: String
    public var lyrics: String
    public var language: String?
    public var genre: String
    public var seed: Int?
    public var model: String
    public var modelVersion: String
    public var request: KIGenerationRequest?
    public var favorite: Bool
    /// In die Musikbibliothek übernommen (Pfad der Kopie).
    public var exportedPath: String?

    public init(id: UUID = UUID(), title: String, kind: Kind, date: Date = Date(), file: String, duration: Double? = nil,
                prompt: String, lyrics: String = "", language: String? = nil, genre: String = "", seed: Int? = nil,
                model: String, modelVersion: String, request: KIGenerationRequest? = nil, favorite: Bool = false,
                exportedPath: String? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.date = date
        self.file = file
        self.duration = duration
        self.prompt = prompt
        self.lyrics = lyrics
        self.language = language
        self.genre = genre
        self.seed = seed
        self.model = model
        self.modelVersion = modelVersion
        self.request = request
        self.favorite = favorite
        self.exportedPath = exportedPath
    }

    /// Titel aus der Beschreibung: die ersten Wörter, ohne Füllwörter wie „Erstelle einen“.
    public static func suggestedTitle(from prompt: String) -> String {
        var words = prompt.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
        let fillers: Set<String> = ["erstelle", "erzeuge", "generiere", "mach", "mache", "schreibe", "bitte", "einen", "eine", "ein",
                                    "create", "make", "generate", "write", "a", "an", "the", "please"]
        while let first = words.first, fillers.contains(first.lowercased().trimmingCharacters(in: .punctuationCharacters)) {
            words.removeFirst()
        }
        let picked = words.prefix(6).joined(separator: " ").trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        guard !picked.isEmpty else { return "Neue Kreation" }
        return picked.prefix(1).uppercased() + picked.dropFirst()
    }
}

public enum KICreationFilter: String, CaseIterable, Sendable {
    case all, songs, instrumentals, remixes, vocal, favorites

    public var label: String {
        switch self {
        case .all: return "Alle"
        case .songs: return "Songs"
        case .instrumentals: return "Instrumentals"
        case .remixes: return "Remixes"
        case .vocal: return "Gesang"
        case .favorites: return "Favoriten"
        }
    }

    public func includes(_ c: KICreation) -> Bool {
        switch self {
        case .all: return true
        case .songs: return c.kind == .song
        case .instrumentals: return c.kind == .instrumental
        case .remixes: return c.kind == .remix
        case .vocal: return c.kind == .vocal
        case .favorites: return c.favorite
        }
    }
}

/// Index der Kreationen (JSON im Kreationen-Ordner), neueste zuerst.
public struct KICreationIndex: Codable, Hashable, Sendable {
    public var version = 1
    public var items: [KICreation] = []

    public init(items: [KICreation] = []) { self.items = items }

    public mutating func add(_ c: KICreation) {
        items.removeAll { $0.id == c.id }
        items.insert(c, at: 0)
    }

    public mutating func remove(_ id: UUID) { items.removeAll { $0.id == id } }

    public func filtered(_ filter: KICreationFilter, query: String = "") -> [KICreation] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { c in
            filter.includes(c) && (q.isEmpty || c.title.lowercased().contains(q) || c.prompt.lowercased().contains(q)
                                   || c.genre.lowercased().contains(q))
        }
    }
}

// MARK: - Dauer schätzen

public enum KIEstimate {
    /// Geschätzte Rechenzeit in Sekunden. `secondsPerAudioSecond` wird aus eigenen Messungen gelernt (gleitender
    /// Mittelwert); ohne Messung gilt ein vorsichtiger Wert für Apple-Chips der M-Reihe.
    public static func seconds(for request: KIGenerationRequest, secondsPerAudioSecond: Double?, planningSeconds: Double?) -> Double {
        let audio = request.duration ?? 120
        let perSecond = secondsPerAudioSecond ?? 0.35
        let planning = request.quality.usesPlanning ? (planningSeconds ?? 20) : 0
        let lyrics: Double = request.lyricsMode == .aiWrites || request.lyricsMode == .revise ? (planningSeconds ?? 20) : 0
        return planning + lyrics + audio * perSecond * Double(max(1, request.variations))
    }

    /// Gleitender Mittelwert einer neuen Messung.
    public static func learn(_ old: Double?, measured: Double, weight: Double = 0.3) -> Double {
        guard let old, old > 0 else { return measured }
        return old * (1 - weight) + measured * weight
    }

    /// „etwa 2 Minuten“
    public static func text(_ seconds: Double) -> String {
        if seconds < 50 { return "unter einer Minute" }
        let minutes = Int((seconds / 60).rounded())
        return minutes <= 1 ? "etwa eine Minute" : "etwa \(minutes) Minuten"
    }
}
