import Foundation

// KI-Hörbücher & Hörspiele – reine Logik ohne Apple-Frameworks (unter Linux getestet):
// Datenmodell einer Produktion (Konzept, Figuren, Kapitel, Szenen, Drehbuch-Elemente), Stimmprofile mit
// klarer Kennzeichnung (entworfen / Stilprofil / berechtigte individuelle Stimme), Einwilligungen, Längenplanung
// und Hardware-Empfehlungen. Gerechnet wird im lokalen Python-Prozess (Resources/HoerspielEngine).

// MARK: - Produktion

public enum HSMode: String, Codable, CaseIterable, Sendable {
    /// Hörbuch: ein Erzähler liest, Figuren sprechen in wörtlicher Rede.
    case hoerbuch
    /// Hörspiel: Erzähler und eigene Stimmen je Figur, Musik, Geräusche, Atmosphäre.
    case hoerspiel

    public var title: String { self == .hoerbuch ? "Hörbuch" : "Hörspiel" }
}

/// Eine Figur der Geschichte.
public struct HSFigure: Codable, Hashable, Identifiable, Sendable {
    /// Kennung im Drehbuch (GROSSBUCHSTABEN, z. B. „LENA“); der Erzähler heißt „ERZÄHLER“.
    public var id: String
    public var name: String
    public var role: String
    public var age: Int?
    public var gender: String?
    public var description: String
    /// Stimmbeschreibung (deutsch, für den Nutzer).
    public var voice: String
    /// Dieselbe Beschreibung auf Englisch (für das Stimm-Design-Modell).
    public var voiceEN: String
    /// Zugewiesenes Stimmprofil aus dem Stimmenstudio (nil = eigene, aus der Beschreibung entworfene Stimme).
    public var voiceProfileID: UUID?
    /// Vom Sprachmodell während des Schreibens ergänzt (nicht im Konzept).
    public var addedByModel: Bool

    public static let narratorID = "ERZÄHLER"
    public var isNarrator: Bool { id == Self.narratorID }

    public init(id: String, name: String, role: String = "", age: Int? = nil, gender: String? = nil, description: String = "",
                voice: String = "", voiceEN: String = "", voiceProfileID: UUID? = nil, addedByModel: Bool = false) {
        self.id = HSFigure.normalizedID(id)
        self.name = name
        self.role = role
        self.age = age
        self.gender = gender
        self.description = description
        self.voice = voice
        self.voiceEN = voiceEN
        self.voiceProfileID = voiceProfileID
        self.addedByModel = addedByModel
    }

    /// Kennung vereinheitlichen: Großbuchstaben, nur Buchstaben/Ziffern (ß → SS).
    public static func normalizedID(_ raw: String) -> String {
        let up = raw.uppercased()
        let kept = up.unicodeScalars.filter { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }
        let s = String(String.UnicodeScalarView(kept))
        return s.isEmpty ? "FIGUR" : s
    }
}

/// Ein Element des Drehbuchs.
public struct HSScriptItem: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case line, sfx, atmo, music, pause }

    public var id: UUID
    public var kind: Kind
    /// Sprecher-Kennung (nur `line`).
    public var speaker: String?
    /// Regieanweisung zum Tonfall, z. B. „flüsternd“ (nur `line`).
    public var emotion: String?
    /// Sprechtext (`line`) bzw. deutsche Beschreibung (Hinweise).
    public var text: String
    /// Englische Beschreibung für Geräusch-/Musikmodelle (Hinweise).
    public var english: String?
    /// Länge in Sekunden (`pause`).
    public var seconds: Double?
    /// Erzeugte Audiodatei relativ zum Produktionsordner.
    public var audioFile: String?
    /// Fingerabdruck aus Text, Stimme und Einstellungen beim Erzeugen – ändert sich etwas, ist die Datei veraltet.
    public var audioFingerprint: String?

    public init(id: UUID = UUID(), kind: Kind, speaker: String? = nil, emotion: String? = nil, text: String,
                english: String? = nil, seconds: Double? = nil) {
        self.id = id
        self.kind = kind
        self.speaker = speaker
        self.emotion = emotion
        self.text = text
        self.english = english
        self.seconds = seconds
    }

    /// Wörter im Sprechtext (für die Längenplanung).
    public var spokenWords: Int {
        kind == .line ? text.split(whereSeparator: { $0 == " " || $0 == "\n" }).count : 0
    }
}

public struct HSScene: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var chapter: Int
    public var number: Int
    public var title: String
    public var location: String
    /// Raumklang (z. B. „zimmer“, „halle“, „draußen“ – siehe `HSRoom`).
    public var room: String
    public var atmoEN: String
    /// Inhalt laut Szenenplan (vor dem Schreiben).
    public var outline: String
    /// Beteiligte Figuren laut Szenenplan.
    public var participants: [String]
    /// Kurzfassung nach dem Schreiben (für den Zusammenhang der folgenden Szenen).
    public var summary: String
    public var items: [HSScriptItem]
    /// Frühere oder alternative Fassungen – neu erzeugen überschreibt nie ohne Sicherung.
    public var versions: [HSSceneVersion]

    public init(id: UUID = UUID(), chapter: Int, number: Int, title: String, location: String = "", room: String = "zimmer",
                atmoEN: String = "", outline: String = "", participants: [String] = [], summary: String = "",
                items: [HSScriptItem] = [], versions: [HSSceneVersion] = []) {
        self.id = id
        self.chapter = chapter
        self.number = number
        self.title = title
        self.location = location
        self.room = room
        self.atmoEN = atmoEN
        self.outline = outline
        self.participants = participants
        self.summary = summary
        self.items = items
        self.versions = versions
    }

    public var spokenWords: Int { items.reduce(0) { $0 + $1.spokenWords } }

    /// Drehbuch im Zeilenformat (wie es das Sprachmodell schreibt) – für Zusammenhang und Anzeige.
    public var scriptText: String {
        items.map { i -> String in
            switch i.kind {
            case .line:
                let e = (i.emotion ?? "").isEmpty ? "" : " (\(i.emotion!))"
                return "\(i.speaker ?? HSFigure.narratorID)\(e): \(i.text)"
            case .pause: return "[PAUSE: \(i.seconds ?? 1.5)]"
            case .sfx: return "[GERÄUSCH: \(i.text) | \(i.english ?? "")]"
            case .atmo: return "[ATMO: \(i.text) | \(i.english ?? "")]"
            case .music: return "[MUSIK: \(i.text) | \(i.english ?? "")]"
            }
        }.joined(separator: "\n")
    }

    public var speakers: [String] {
        var seen: [String] = []
        for i in items where i.kind == .line { if let s = i.speaker, !seen.contains(s) { seen.append(s) } }
        return seen
    }

    /// Aktuelle Fassung sichern und durch neue Elemente ersetzen (Szene neu schreiben / Alternative übernehmen).
    public mutating func replaceItems(_ newItems: [HSScriptItem], note: String, date: Date = Date()) {
        versions.append(HSSceneVersion(date: date, note: note, items: items, summary: summary))
        items = newItems
    }

    /// Eine gesicherte Fassung wiederherstellen (die aktuelle wird dabei ebenfalls gesichert).
    public mutating func restore(versionAt index: Int, date: Date = Date()) {
        guard versions.indices.contains(index) else { return }
        let v = versions[index]
        replaceItems(v.items, note: "vor Wiederherstellung", date: date)
        summary = v.summary
    }
}

public struct HSSceneVersion: Codable, Hashable, Sendable {
    public var date: Date
    public var note: String
    public var items: [HSScriptItem]
    public var summary: String
}

public struct HSChapter: Codable, Hashable, Sendable {
    public var number: Int
    public var title: String
    public init(number: Int, title: String) { self.number = number; self.title = title }
}

/// Arbeitsschritte einer Produktion (für Fortschritt und Fortsetzen nach Unterbrechung).
public enum HSStep: String, Codable, CaseIterable, Sendable {
    case story, chapters, casting, voices, sfx, music, mix, export

    public var title: String {
        switch self {
        case .story: return "Geschichte schreiben"
        case .chapters: return "Kapitel strukturieren"
        case .casting: return "Sprecher zuweisen"
        case .voices: return "Stimmen erzeugen"
        case .sfx: return "Geräusche hinzufügen"
        case .music: return "Musik erzeugen"
        case .mix: return "Audio abmischen"
        case .export: return "Exportieren"
        }
    }
}

public enum HSStepState: String, Codable, Sendable { case pending, running, done, failed, outdated }

public struct HSProduction: Codable, Identifiable, Sendable {
    public var id: UUID
    public var mode: HSMode
    public var title: String
    public var subtitle: String
    public var logline: String
    public var era: String
    public var tone: String
    public var resolution: String
    public var prompt: String
    public var language: String
    public var targetMinutes: Double
    public var figures: [HSFigure]
    public var chapters: [HSChapter]
    public var scenes: [HSScene]
    /// Analysiertes Stilprofil, an dem sich die Produktion orientiert (nur allgemeine Merkmale).
    public var styleProfileID: UUID?
    /// Kassettenklang der 1980er (0 = aus, 1 = deutlich).
    public var retroAmount: Double
    /// Stand je Arbeitsschritt (Schlüssel: `HSStep.rawValue`).
    public var steps: [String: HSStepState]
    /// Stimmen der Figuren in dieser Produktion (Kennung → Referenzsatz).
    public var cast: [String: HSCast]
    /// Erzählstil (Hörbuch): klassisch, spannend, humorvoll, märchenhaft, sachlich.
    public var narration: String
    /// Eigene Aussprache: Schreibweise → gesprochene Form (z. B. „TKKG“ → „Te Ka Ka Ge“).
    public var pronunciations: [String: String]
    /// Erzeugte Geräusche/Atmo (englische Beschreibung → Datei) und Musik (Art → Datei), relativ oder absolut.
    public var sfxFiles: [String: String]
    public var musicFiles: [String: String]
    /// Ergebnis der letzten Mischung.
    public var mix: HSMixInfo?
    public var useMusic: Bool
    public var useSFX: Bool
    /// Geplante Spuren/Hinweise aus dem Konzept (optional: ältere Produktionen haben keine).
    public var clues: [HSClue]?
    /// Ergebnis des Lektorats (Widersprüche, überarbeitete Szenen); nil = noch nicht geprüft.
    public var review: HSReview?
    public var created: Date
    public var modified: Date

    public init(id: UUID = UUID(), mode: HSMode, title: String = "", prompt: String, language: String = "de",
                targetMinutes: Double = 10, created: Date = Date()) {
        self.id = id
        self.mode = mode
        self.title = title
        self.subtitle = ""
        self.logline = ""
        self.era = ""
        self.tone = ""
        self.resolution = ""
        self.prompt = prompt
        self.language = language
        self.targetMinutes = targetMinutes
        self.figures = []
        self.chapters = []
        self.scenes = []
        self.styleProfileID = nil
        self.retroAmount = 0
        self.steps = [:]
        self.cast = [:]
        self.narration = "spannend"
        self.pronunciations = [:]
        self.sfxFiles = [:]
        self.musicFiles = [:]
        self.mix = nil
        self.useMusic = true
        self.useSFX = mode == .hoerspiel
        self.created = created
        self.modified = created
    }

    public func state(_ step: HSStep) -> HSStepState { steps[step.rawValue] ?? .pending }
    public mutating func set(_ step: HSStep, _ state: HSStepState) { steps[step.rawValue] = state; modified = Date() }

    /// Nach Abbruch, Fehler oder Neustart läuft kein Schritt mehr: „Läuft“ wird zu `state` („Offen“ bzw. „Fehler“).
    /// „Fortsetzen“ macht dort weiter – fertige Schritte und schon gesprochene Zeilen bleiben erhalten.
    @discardableResult
    public mutating func settleInterrupted(as state: HSStepState = .pending) -> Bool {
        let running = steps.filter { $0.value == .running }.map(\.key)
        for k in running { steps[k] = state }
        return !running.isEmpty
    }

    public var spokenWords: Int { scenes.reduce(0) { $0 + $1.spokenWords } }
    /// Geschätzte Länge aus dem Text (Sprechtempo + Anteil Musik/Geräusche).
    public var estimatedMinutes: Double { Double(spokenWords) / (HSPlan.wordsPerMinute * HSPlan.speechShare) }

    public func figure(_ id: String) -> HSFigure? { figures.first { $0.id == id } }

    /// Figuren, die tatsächlich sprechen (in Reihenfolge des ersten Auftritts, Erzähler zuerst).
    public var speakingFigures: [HSFigure] {
        var ids: [String] = []
        for s in scenes { for sp in s.speakers where !ids.contains(sp) { ids.append(sp) } }
        let ordered = ids.filter { $0 == HSFigure.narratorID } + ids.filter { $0 != HSFigure.narratorID }
        return ordered.compactMap { figure($0) }
    }

    /// Szenen- und Zeilenänderung macht abhängige Schritte veraltet (nicht die übrige Geschichte).
    public mutating func markChanged(scene sceneID: UUID) {
        modified = Date()
        for step in [HSStep.voices, .sfx, .mix, .export] where state(step) == .done { steps[step.rawValue] = .outdated }
        _ = sceneID
    }
}

/// Stimme einer Figur in einer Produktion.
public struct HSCast: Codable, Hashable, Sendable {
    /// Referenzsatz (Datei relativ zum Produktionsordner oder absolut im Stimmenstudio).
    public var referenceFile: String
    public var referenceText: String
    /// Beschreibung, aus der die Stimme entworfen wurde.
    public var instruct: String
    public var seed: Int
    /// Stimmprofil aus dem Stimmenstudio (nil = für diese Produktion entworfen).
    public var profileID: UUID?
    public var kind: HSVoiceProfile.Kind

    public init(referenceFile: String, referenceText: String, instruct: String, seed: Int, profileID: UUID? = nil,
                kind: HSVoiceProfile.Kind = .designed) {
        self.referenceFile = referenceFile
        self.referenceText = referenceText
        self.instruct = instruct
        self.seed = seed
        self.profileID = profileID
        self.kind = kind
    }

    /// Fingerabdruck der Stimme (ändert sich die Stimme, sind die gesprochenen Zeilen veraltet).
    public var fingerprint: String { HSHash.string("\(referenceFile)|\(referenceText)|\(seed)|\(profileID?.uuidString ?? "")") }
}

/// Eine geplante Spur (Hinweis, Gegenstand, falsche Fährte) und die Szene, in der sie zuerst vorkommt (ab 1).
public struct HSClue: Codable, Hashable, Sendable {
    public var clue: String
    public var scene: Int
    public var meaning: String
    public init(clue: String, scene: Int, meaning: String = "") {
        self.clue = clue
        self.scene = scene
        self.meaning = meaning
    }
}

/// Ein Fund des Lektorats.
public struct HSReviewProblem: Codable, Hashable, Sendable {
    /// Szene ab 1.
    public var scene: Int
    public var problem: String
    public var fix: String
    public init(scene: Int, problem: String, fix: String = "") {
        self.scene = scene
        self.problem = problem
        self.fix = fix
    }
}

public struct HSReview: Codable, Hashable, Sendable {
    public var problems: [HSReviewProblem]
    /// Szenen (ab 1), die das Lektorat überarbeitet hat; die vorige Fassung liegt in den Versionen der Szene.
    public var revised: [Int]
    public var date: Date
    public init(problems: [HSReviewProblem], revised: [Int], date: Date = Date()) {
        self.problems = problems
        self.revised = revised
        self.date = date
    }
    /// Hinweise, die nach dem Lektorat noch offen sind (Szene nicht überarbeitet).
    public var open: [HSReviewProblem] { problems.filter { !revised.contains($0.scene) } }
}

public struct HSMixInfo: Codable, Hashable, Sendable {
    public var master: String
    public var stems: [String: String]
    /// Bearbeitbare Zeitleiste (zeitleiste.json im Ordner der Mischung) für den Mehrspur-Editor.
    public var timeline: String?
    public var chapters: [HSChapterMark]
    public var duration: Double
    public var loudness: Double?
    public var speechToBackground: Double?
    public var date: Date

    public init(master: String, stems: [String: String], chapters: [HSChapterMark], duration: Double, loudness: Double?,
                speechToBackground: Double?, timeline: String? = nil, date: Date = Date()) {
        self.master = master
        self.stems = stems
        self.timeline = timeline
        self.chapters = chapters
        self.duration = duration
        self.loudness = loudness
        self.speechToBackground = speechToBackground
        self.date = date
    }
}

public struct HSChapterMark: Codable, Hashable, Sendable {
    public var title: String
    public var start: Double
    public init(title: String, start: Double) { self.title = title; self.start = start }
}

/// Stabiler, kurzer Hash (FNV-1a, 64 bit) – für Fingerabdrücke, nicht für Sicherheit.
public enum HSHash {
    public static func string(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        let hex = String(h, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}

extension HSProduction {
    /// Sprechtext einer Zeile mit eigener Aussprache (ganze Wörter, Groß-/Kleinschreibung beachtet).
    public func spokenText(_ text: String) -> String {
        var out = text
        for (written, spoken) in pronunciations.sorted(by: { $0.key.count > $1.key.count }) where !written.isEmpty {
            out = HSText.replaceWord(written, with: spoken, in: out)
        }
        return out
    }

    /// Fingerabdruck einer gesprochenen Zeile (Text, Aussprache, Stimme).
    public func fingerprint(of item: HSScriptItem) -> String? {
        guard item.kind == .line, let sp = item.speaker, let c = cast[sp] else { return nil }
        return HSHash.string("\(spokenText(item.text))|\(c.fingerprint)")
    }

    /// Zeilen, die (neu) gesprochen werden müssen.
    public var linesNeedingVoice: [(scene: Int, item: Int)] {
        var out: [(Int, Int)] = []
        for (si, s) in scenes.enumerated() {
            for (ii, it) in s.items.enumerated() where it.kind == .line {
                if it.audioFile == nil || it.audioFingerprint != fingerprint(of: it) { out.append((si, ii)) }
            }
        }
        return out
    }
}

// MARK: - Längenplanung

public enum HSPlan {
    /// Gesprochene Wörter pro Minute im Hörspiel (inkl. kurzer Pausen) – wie in hs_story.py.
    public static let wordsPerMinute = 140.0
    /// Anteil Sprache an der Gesamtlänge (Rest: Musik, Geräusche, Übergänge).
    public static let speechShare = 0.85

    public static let presets: [Double] = [5, 10, 15, 30, 45, 60, 90, 120]

    /// Kapitel und Szenen je Kapitel für eine Ziel-Länge (wie `plan_size` in hs_story.py).
    public static func size(minutes: Double) -> (chapters: Int, scenesPerChapter: Int) {
        let scenesTotal = max(3, Int((minutes / 1.7).rounded()))
        let chapters = max(1, Int((minutes / 12).rounded()))
        let perChapter = max(3, Int((Double(scenesTotal) / Double(chapters)).rounded()))
        return (chapters, perChapter)
    }

    public static func targetWords(minutes: Double) -> Int { Int(minutes * wordsPerMinute * speechShare) }
}

// MARK: - Raumklang

public enum HSRoom {
    /// Räume des Mischers (hs_audio.ROOMS) mit deutschem Namen.
    public static let all: [(id: String, name: String)] = [
        ("trocken", "Trocken (Studio)"), ("zimmer", "Zimmer"), ("küche", "Küche"), ("büro", "Büro"), ("auto", "Auto"),
        ("keller", "Keller"), ("treppenhaus", "Treppenhaus"), ("halle", "Halle"), ("bahnhofshalle", "Bahnhofshalle"),
        ("kirche", "Kirche"), ("draußen", "Draußen"), ("wald", "Wald"), ("telefon", "Telefon"),
    ]
}
