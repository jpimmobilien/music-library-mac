import Foundation

// Stimmenstudio – Stimmprofile und Einwilligungen (reine Logik, unter Linux getestet).
//
// Drei Arten, immer sichtbar gekennzeichnet:
// - entworfen: aus Einstellungen/Beschreibung erzeugte Stimme; der Referenzsatz ist synthetisch
// - Stilprofil: nur eine Beschreibung allgemeiner Merkmale aus einer analysierten Aufnahme – keine Stimme,
//   kein Stimmabdruck; daraus lässt sich eine eigenständige Stimme entwerfen
// - berechtigt: individuelle Stimme einer realen Person, nur mit dokumentierter und geprüfter Einwilligung
//   (gesprochene Einwilligung derselben Stimme + Text der Einwilligung)

public struct HSVoiceSettings: Codable, Hashable, Sendable {
    public enum Gender: String, Codable, CaseIterable, Sendable { case male, female, neutral }
    public enum Age: String, Codable, CaseIterable, Sendable { case child, teen, young, adult, middle, senior }
    public enum Timbre: String, Codable, CaseIterable, Sendable { case dark, warm, neutral, bright, raspy, breathy, nasal }
    public enum Articulation: String, Codable, CaseIterable, Sendable { case crisp, natural, relaxed, clipped }
    public enum Mood: String, Codable, CaseIterable, Sendable {
        case calm, friendly, serious, cheeky, nervous, cheerful, stern, mysterious, gruff
    }

    public var gender: Gender
    public var age: Age
    /// −2 (sehr tief) … +2 (sehr hoch)
    public var pitch: Int
    public var timbre: Timbre
    /// −2 (sehr langsam) … +2 (sehr schnell)
    public var tempo: Int
    public var articulation: Articulation
    public var mood: Mood
    /// Akzent/Färbung (frei, z. B. „leicht bairisch“) – vom Modell nur teilweise umgesetzt.
    public var accent: String
    /// Freie Ergänzung (deutsch).
    public var notes: String

    public init(gender: Gender = .male, age: Age = .adult, pitch: Int = 0, timbre: Timbre = .neutral, tempo: Int = 0,
                articulation: Articulation = .natural, mood: Mood = .calm, accent: String = "", notes: String = "") {
        self.gender = gender
        self.age = age
        self.pitch = max(-2, min(2, pitch))
        self.timbre = timbre
        self.tempo = max(-2, min(2, tempo))
        self.articulation = articulation
        self.mood = mood
        self.accent = accent
        self.notes = notes
    }

    // MARK: Beschreibungen

    static let genderDE: [Gender: String] = [.male: "männlich", .female: "weiblich", .neutral: "neutral"]
    static let ageDE: [Age: String] = [.child: "Kind (ca. 8–11)", .teen: "Jugendlich (ca. 13–16)", .young: "Junger Erwachsener",
                                       .adult: "Erwachsen", .middle: "Mittleres Alter", .senior: "Älter (60+)"]
    static let timbreDE: [Timbre: String] = [.dark: "dunkel", .warm: "warm", .neutral: "neutral", .bright: "hell",
                                             .raspy: "rau", .breathy: "hauchig", .nasal: "nasal"]
    static let articulationDE: [Articulation: String] = [.crisp: "sehr deutlich", .natural: "natürlich", .relaxed: "locker",
                                                         .clipped: "abgehackt"]
    static let moodDE: [Mood: String] = [.calm: "ruhig", .friendly: "freundlich", .serious: "ernst", .cheeky: "frech",
                                         .nervous: "nervös", .cheerful: "fröhlich", .stern: "streng",
                                         .mysterious: "geheimnisvoll", .gruff: "brummig"]
    static let pitchDE = ["sehr tief", "tief", "mittel", "hoch", "sehr hoch"]
    static let tempoDE = ["sehr langsam", "langsam", "normal", "schnell", "sehr schnell"]

    public var descriptionDE: String {
        var parts = ["\(Self.ageDE[age]!), \(Self.genderDE[gender]!)", "Tonlage \(Self.pitchDE[pitch + 2])",
                     Self.timbreDE[timbre]!, "Tempo \(Self.tempoDE[tempo + 2])", Self.articulationDE[articulation]!,
                     Self.moodDE[mood]!]
        if !accent.trimmingCharacters(in: .whitespaces).isEmpty { parts.append("Färbung: \(accent)") }
        if !notes.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(notes) }
        return parts.joined(separator: ", ")
    }

    /// Beschreibung für das Stimm-Design-Modell (englisch – so verstehen es die Modelle am zuverlässigsten).
    public var descriptionEN: String {
        let who: String
        switch (age, gender) {
        case (.child, .male): who = "A young boy, about 10 years old"
        case (.child, .female): who = "A young girl, about 10 years old"
        case (.child, .neutral): who = "A child, about 10 years old"
        case (.teen, .male): who = "A teenage boy, about 14 years old"
        case (.teen, .female): who = "A teenage girl, about 14 years old"
        case (.teen, .neutral): who = "A teenager, about 14 years old"
        case (.young, _): who = "A young \(gender == .female ? "woman" : gender == .male ? "man" : "adult") in their twenties"
        case (.adult, _): who = "An adult \(gender == .female ? "woman" : gender == .male ? "man" : "person") in their thirties"
        case (.middle, _): who = "A \(gender == .female ? "woman" : gender == .male ? "man" : "person") in their fifties"
        case (.senior, _): who = "An elderly \(gender == .female ? "woman" : gender == .male ? "man" : "person") in their seventies"
        }
        let pitchEN = ["very low", "low", "medium", "high", "very high"][pitch + 2]
        let timbreEN: [Timbre: String] = [.dark: "dark", .warm: "warm", .neutral: "neutral", .bright: "bright and clear",
                                          .raspy: "raspy", .breathy: "breathy", .nasal: "slightly nasal"]
        let tempoEN = ["very slow", "slow", "natural", "fast", "very fast"][tempo + 2]
        let artEN: [Articulation: String] = [.crisp: "very crisp articulation", .natural: "natural articulation",
                                             .relaxed: "relaxed, casual articulation", .clipped: "short, clipped phrasing"]
        let moodEN: [Mood: String] = [.calm: "calm", .friendly: "friendly", .serious: "serious", .cheeky: "cheeky and energetic",
                                      .nervous: "nervous", .cheerful: "cheerful", .stern: "stern", .mysterious: "mysterious",
                                      .gruff: "gruff"]
        var s = "\(who), with a \(pitchEN)-pitched, \(timbreEN[timbre]!) voice, \(tempoEN) pace, \(artEN[articulation]!), "
            + "\(moodEN[mood]!) tone. Speaks native German"
        let acc = accent.trimmingCharacters(in: .whitespaces)
        s += acc.isEmpty ? " (standard High German)." : " with a light regional colouring (\(acc))."
        return s
    }
}

/// Einwilligung einer realen Person zur Nachbildung ihrer Stimme.
public struct HSConsent: Codable, Hashable, Sendable {
    public var personName: String
    /// Wofür die Einwilligung gilt (frei, vom Nutzer).
    public var scope: String
    public var grantedTo: String
    public var date: Date
    /// Gesprochene Einwilligung (Datei relativ zum Stimmenordner).
    public var recordingFile: String
    /// Optional: unterschriebenes Dokument (Datei relativ zum Stimmenordner).
    public var documentFile: String?
    /// Ergebnis der Prüfung: Ähnlichkeit Einwilligung ↔ Stimmprobe (ECAPA, Kosinus).
    public var similarity: Double?
    public var similarityThreshold: Double?
    /// Von der Spracherkennung gehörter Text der Einwilligung.
    public var transcript: String?
    public var transcriptMatches: Bool?
    public var verified: Date?

    public init(personName: String, scope: String, grantedTo: String, date: Date = Date(), recordingFile: String,
                documentFile: String? = nil) {
        self.personName = personName
        self.scope = scope
        self.grantedTo = grantedTo
        self.date = date
        self.recordingFile = recordingFile
        self.documentFile = documentFile
    }

    /// Satz, den die Person selbst sprechen muss.
    public static func statement(person: String, grantedTo: String) -> String {
        "Ich, \(person), erlaube, dass meine Stimme in der Music Library von \(grantedTo) für eigene Hörspiele und Hörbücher nachgebildet wird."
    }

    /// Prüft, ob die Spracherkennung die wesentlichen Teile der Einwilligung gehört hat.
    public static func transcriptMatches(_ transcript: String, person: String) -> Bool {
        let heard = Set(HSText.words(transcript))
        let nameWords = HSText.words(person)
        let nameOK = !nameWords.isEmpty && nameWords.allSatisfy { heard.contains($0) }
        let required = ["erlaube", "stimme", "nachgebildet"]
        let keyOK = required.filter { heard.contains($0) }.count >= 2
        return nameOK && keyOK
    }

    /// Gültig nur, wenn beide Prüfungen bestanden sind.
    public var isVerified: Bool {
        guard let sim = similarity, let thr = similarityThreshold, transcriptMatches == true, verified != nil else { return false }
        return sim >= thr
    }
}

public struct HSVoiceProfile: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case designed, styleOnly, authorized

        public var label: String {
            switch self {
            case .designed: return "Entworfene Stimme"
            case .styleOnly: return "Stilprofil (nur Beschreibung)"
            case .authorized: return "Berechtigte individuelle Stimme"
            }
        }

        public var explanation: String {
            switch self {
            case .designed:
                return "Aus Einstellungen und Beschreibung erzeugt. Der Referenzsatz ist synthetisch – keine reale Person."
            case .styleOnly:
                return "Allgemeine Merkmale aus einer analysierten Aufnahme (Tonlage, Tempo, Klangfarbe). Enthält keine "
                    + "Stimme und keinen Stimmabdruck. Daraus kann eine eigenständige Stimme entworfen werden."
            case .authorized:
                return "Nachbildung der Stimme einer realen Person – nur mit dokumentierter, geprüfter Einwilligung."
            }
        }
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    public var settings: HSVoiceSettings
    /// Freie Beschreibung (überschreibt die Einstellungen, wenn gesetzt).
    public var customDescriptionEN: String?
    /// Referenzsatz (synthetisch bei `designed`, Aufnahme der Person bei `authorized`) relativ zum Stimmenordner.
    public var referenceFile: String?
    public var referenceText: String?
    public var seed: Int
    /// Herkunft eines Stilprofils (Name der analysierten Referenz).
    public var sourceReference: String?
    public var consent: HSConsent?
    public var created: Date

    public init(id: UUID = UUID(), name: String, kind: Kind, settings: HSVoiceSettings = HSVoiceSettings(),
                customDescriptionEN: String? = nil, seed: Int = Int.random(in: 1...999_999), created: Date = Date()) {
        self.id = id
        self.name = name
        self.kind = kind
        self.settings = settings
        self.customDescriptionEN = customDescriptionEN
        self.seed = seed
        self.created = created
    }

    public var designDescription: String {
        if let c = customDescriptionEN?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty { return c }
        return settings.descriptionEN
    }

    /// Kann diese Stimme sprechen? Stilprofile nie direkt, berechtigte nur mit geprüfter Einwilligung.
    public var canSpeak: Bool {
        switch kind {
        case .designed: return referenceFile != nil
        case .styleOnly: return false
        case .authorized: return referenceFile != nil && (consent?.isVerified ?? false)
        }
    }
}

// MARK: - Stimm-Design

public enum HSVoiceDesign {
    /// Referenzsatz für entworfene Stimmen (wie hs_voice.REFERENCE_TEXT).
    public static let referenceText = "Ich weiß nicht genau, was hier los ist. Aber eins ist sicher: Wir sollten vorsichtig sein und ganz genau hinschauen."

    /// Beschreibung einer Figur für das Design-Modell (wie hs_voice.design_instruct).
    public static func instruct(for f: HSFigure) -> String {
        var base = f.voiceEN.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = f.voice.trimmingCharacters(in: .whitespacesAndNewlines) }
        if base.isEmpty {
            let g = (f.gender ?? "").lowercased().hasPrefix("w") || (f.gender ?? "").lowercased().hasPrefix("f") ? "female" : "male"
            base = "A natural \(g) voice, about \(f.age ?? 40) years old"
        }
        while base.hasSuffix(".") { base.removeLast() }
        return base + ". Speaks native German with clear, natural pronunciation."
    }

    /// Erzählerstimme für ein Hörbuch je nach Erzählstil.
    public static func narratorInstruct(style: String, base: String) -> String {
        let styleEN: [String: String] = ["klassisch": "calm and classic", "spannend": "suspenseful, with dramatic pauses",
                                         "humorvoll": "warm and humorous", "märchenhaft": "gentle and fairy-tale like",
                                         "sachlich": "clear and matter-of-fact"]
        let b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = b.isEmpty ? "A warm, expressive audiobook narrator in their forties, rich and clear voice" : b
        return head.trimmingCharacters(in: CharacterSet(charactersIn: ".")) + ", reading in a \(styleEN[style] ?? "lively") style. "
            + "Speaks native German with clear, natural pronunciation."
    }

    /// Stabiler Startwert je Produktion und Figur (gleiche Stimme bei erneutem Entwurf).
    public static func seed(production: UUID, figure: String) -> Int {
        Int(UInt64(HSHash.string(production.uuidString + figure), radix: 16)! % 900_000) + 100
    }
}

// MARK: - Text

public enum HSText {
    /// Kleingeschriebene Wörter ohne Satzzeichen (für Vergleiche).
    public static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
    }

    /// Ganzes Wort ersetzen (nicht innerhalb anderer Wörter).
    public static func replaceWord(_ word: String, with replacement: String, in text: String) -> String {
        var result = ""
        var rest = Substring(text)
        while let r = rest.range(of: word) {
            let before = rest[..<r.lowerBound]
            let prevOK = (before.last.map { !($0.isLetter || $0.isNumber) } ?? true) && (before.isEmpty ? result.last.map { !($0.isLetter || $0.isNumber) } ?? true : true)
            let next = rest[r.upperBound...].first
            let nextOK = next.map { !($0.isLetter || $0.isNumber) } ?? true
            result += before
            result += (prevOK && nextOK) ? replacement : String(rest[r])
            rest = rest[r.upperBound...]
        }
        return result + rest
    }
}
