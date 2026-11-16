import Foundation

// Ablage der KI-Hörspiele (reine Logik, unter Linux getestet). Alles liegt in einem eigenen Ordner außerhalb der
// Musikbibliothek – die Bibliothek und ihre Datenbank bleiben unberührt:
//
//   ~/Music/KI-Hörspiele/
//     <Produktion>/produktion.json   Konzept, Figuren, Szenen, Drehbuch, Stand der Schritte
//     <Produktion>/stimmen/…          entworfene Referenzsätze der Figuren
//     <Produktion>/zeilen/…           gesprochene Zeilen
//     <Produktion>/musik/…, mix/…     Musik, Spuren, fertige Mischung, Exporte
//     Stimmen/stimmen.json + *.wav    Stimmenstudio (wiederverwendbare Stimmprofile, Einwilligungen)
//     Referenzen/*.json               analysierte Referenzen (nur Merkmale, keine Audiokopie)
//     Geräusche/                      Geräuschbibliothek (erzeugt oder importiert, mit Herkunft)

public struct HSSFXEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var prompt: String
    public var file: String
    public var seconds: Double
    /// „erzeugt“ (Modell) oder „importiert“ (eigene Datei).
    public var origin: String
    /// Lizenz bzw. Herkunft, z. B. „erzeugt mit Stable Audio 3 small“ oder „eigene Aufnahme“, „CC0 (Quelle …)“.
    public var license: String
    public var created: Date

    public init(id: UUID = UUID(), name: String, prompt: String, file: String, seconds: Double, origin: String, license: String,
                created: Date = Date()) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.file = file
        self.seconds = seconds
        self.origin = origin
        self.license = license
        self.created = created
    }
}

public struct HSReference: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// Dateinamen der analysierten Aufnahmen (nur Namen – die Aufnahmen selbst werden nicht kopiert).
    public var sources: [String]
    public var analyzed: Date
    /// Zusammenfassung (deutsch).
    public var summary: String
    /// Stilbeschreibung für das Schreiben (Epoche, Dialogtempo, Erzählweise, Klang) – nur allgemeine Merkmale.
    public var styleHint: String
    /// Erkannte Sprecher: Rolle (geschätzt), Anteil, Beschreibung.
    public var speakers: [Speaker]
    public var retroSuggested: Double

    public struct Speaker: Codable, Hashable, Sendable {
        public var id: String
        public var role: String
        public var share: Double
        public var descriptionDE: String
        public var voiceEN: String
        /// Gemessene Tonhöhe (Hz) und Sprechtempo (Silben/s); optional (ältere Referenzen haben sie nicht).
        public var f0: Double?
        public var syllablesPerSecond: Double?
    }

    public init(id: UUID = UUID(), name: String, sources: [String], analyzed: Date = Date(), summary: String, styleHint: String,
                speakers: [Speaker], retroSuggested: Double) {
        self.id = id
        self.name = name
        self.sources = sources
        self.analyzed = analyzed
        self.summary = summary
        self.styleHint = styleHint
        self.speakers = speakers
        self.retroSuggested = retroSuggested
    }

    /// Aus dem Stilprofil des Prozesses (hs_analyze.style_profile) übernehmen.
    public static func from(profile p: [String: Any], name: String, sources: [String]) -> HSReference {
        let speakers = (p["speakers"] as? [[String: Any]] ?? []).map {
            Speaker(id: HSJSON.str($0["id"]), role: HSJSON.str($0["role_guess"]), share: HSJSON.double($0["share"]) ?? 0,
                    descriptionDE: HSJSON.str($0["description_de"]), voiceEN: HSJSON.str($0["voice_en"]),
                    f0: HSJSON.double($0["f0_median_hz"]), syllablesPerSecond: HSJSON.double($0["syllables_per_second"]))
        }
        let rec = p["recording"] as? [String: Any] ?? [:]
        let dialog = p["dialog"] as? [String: Any] ?? [:]
        let bandwidth = HSJSON.double(rec["bandwidth_hz"]) ?? 20000
        // begrenzte Bandbreite und hörbares Rauschen sprechen für Kassetten-/Bandklang
        let noise = HSJSON.double(rec["noise_floor_dbfs"]) ?? -90
        let retro = min(1, max(0, (16000 - bandwidth) / 5000 + (noise > -60 ? 0.3 : 0)))
        var hint: [String] = []
        if let tpm = HSJSON.double(dialog["turns_per_minute"]) {
            hint.append(tpm > 12 ? "schnelle Wortwechsel" : tpm < 6 ? "ruhiges Erzähltempo mit längeren Passagen" : "ausgewogenes Dialogtempo")
        }
        if let narrator = speakers.first(where: { $0.role.hasPrefix("Erzähler") }) {
            hint.append("Erzähler mit etwa \(Int((narrator.share * 100).rounded())) % Anteil")
        }
        if let bridges = HSJSON.int(p["music_bridges"]), bridges > 0 { hint.append("kurze Musikbrücken zwischen den Szenen") }
        return HSReference(name: name, sources: sources, summary: HSJSON.str(p["summary_de"]), styleHint: hint.joined(separator: ", "),
                           speakers: speakers, retroSuggested: (retro * 10).rounded() / 10)
    }
}

public final class HSStore: @unchecked Sendable {
    public let root: URL
    private let fm = FileManager.default

    public init(root: URL) { self.root = root }

    public var voicesDir: URL { root.appendingPathComponent("Stimmen", isDirectory: true) }
    public var referencesDir: URL { root.appendingPathComponent("Referenzen", isDirectory: true) }
    public var sfxDir: URL { root.appendingPathComponent("Geräusche", isDirectory: true) }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: Produktionen

    public func folder(for p: HSProduction) -> URL {
        root.appendingPathComponent("Produktion-" + p.id.uuidString.prefix(8).lowercased(), isDirectory: true)
    }

    public func save(_ p: HSProduction) throws {
        let dir = folder(for: p)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("produktion.json")
        // vorige Fassung als Sicherung behalten (versehentliches Überschreiben rückgängig machen)
        if fm.fileExists(atPath: file.path) {
            let backup = dir.appendingPathComponent("produktion.vorher.json")
            try? fm.removeItem(at: backup)
            try? fm.copyItem(at: file, to: backup)
        }
        try Self.encoder.encode(p).write(to: file, options: .atomic)
    }

    public func loadProductions() -> [HSProduction] {
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return dirs.compactMap { d -> HSProduction? in
            guard d.lastPathComponent.hasPrefix("Produktion-"),
                  let data = try? Data(contentsOf: d.appendingPathComponent("produktion.json")) else { return nil }
            return try? Self.decoder.decode(HSProduction.self, from: data)
        }.sorted { $0.modified > $1.modified }
    }

    // MARK: Stimmen

    public func loadVoices() -> [HSVoiceProfile] {
        guard let data = try? Data(contentsOf: voicesDir.appendingPathComponent("stimmen.json")),
              let v = try? Self.decoder.decode([HSVoiceProfile].self, from: data) else { return [] }
        return v
    }

    public func saveVoices(_ v: [HSVoiceProfile]) throws {
        try fm.createDirectory(at: voicesDir, withIntermediateDirectories: true)
        try Self.encoder.encode(v).write(to: voicesDir.appendingPathComponent("stimmen.json"), options: .atomic)
    }

    // MARK: Referenzen

    public func loadReferences() -> [HSReference] {
        guard let files = try? fm.contentsOfDirectory(at: referencesDir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasSuffix(".analyse.json") }
            .compactMap { try? Self.decoder.decode(HSReference.self, from: Data(contentsOf: $0)) }
            .sorted { $0.analyzed > $1.analyzed }
    }

    public func save(_ r: HSReference) throws {
        try fm.createDirectory(at: referencesDir, withIntermediateDirectories: true)
        try Self.encoder.encode(r).write(to: referencesDir.appendingPathComponent("\(r.id.uuidString).json"), options: .atomic)
    }

    public func analysisFile(for r: HSReference) -> URL { referencesDir.appendingPathComponent("\(r.id.uuidString).analyse.json") }

    // MARK: Geräusche

    public func loadSFX() -> [HSSFXEntry] {
        guard let data = try? Data(contentsOf: sfxDir.appendingPathComponent("geraeusche.json")),
              let v = try? Self.decoder.decode([HSSFXEntry].self, from: data) else { return [] }
        return v
    }

    public func saveSFX(_ v: [HSSFXEntry]) throws {
        try fm.createDirectory(at: sfxDir, withIntermediateDirectories: true)
        try Self.encoder.encode(v).write(to: sfxDir.appendingPathComponent("geraeusche.json"), options: .atomic)
    }
}

// MARK: - Export

public enum HSExportScope: String, CaseIterable, Codable, Sendable {
    case whole, chapters, scenes, stems

    public var label: String {
        switch self {
        case .whole: return "Gesamte Produktion"
        case .chapters: return "Einzelne Kapitel"
        case .scenes: return "Einzelne Szenen"
        case .stems: return "Einzelne Spuren"
        }
    }
}

public struct HSExportItem: Hashable, Sendable {
    /// Quelle relativ zum Produktionsordner oder absolut.
    public var source: String
    public var trim: TrimRange?
    public var title: String
    public var fileName: String
    public var trackNumber: Int?
}

public enum HSExportPlan {
    /// Welche Dateien ein Export erzeugt. Kapitel/Szenen werden aus der fertigen Mischung geschnitten.
    public static func items(for p: HSProduction, scope: HSExportScope) -> [HSExportItem] {
        guard let mix = p.mix else { return [] }
        let base = safe(p.title.isEmpty ? "KI-Hörspiel" : p.title)
        switch scope {
        case .whole:
            return [HSExportItem(source: mix.master, trim: nil, title: p.title, fileName: base, trackNumber: nil)]
        case .scenes:
            return mix.chapters.enumerated().map { i, c in
                let end = i + 1 < mix.chapters.count ? mix.chapters[i + 1].start : mix.duration
                return HSExportItem(source: mix.master, trim: TrimRange(start: c.start, end: end), title: c.title,
                                    fileName: "\(base) – \(pad(i + 1)) \(safe(c.title))", trackNumber: i + 1)
            }
        case .chapters:
            var out: [HSExportItem] = []
            for (n, ch) in p.chapters.enumerated() {
                let idx = p.scenes.indices.filter { p.scenes[$0].chapter == ch.number && $0 < mix.chapters.count }
                guard let first = idx.first, let last = idx.last else { continue }
                let start = mix.chapters[first].start
                let end = last + 1 < mix.chapters.count ? mix.chapters[last + 1].start : mix.duration
                let title = "Kapitel \(ch.number)" + (ch.title.isEmpty ? "" : ": \(ch.title)")
                out.append(HSExportItem(source: mix.master, trim: TrimRange(start: start, end: end), title: title,
                                        fileName: "\(base) – \(pad(n + 1)) \(safe(title))", trackNumber: n + 1))
            }
            return out
        case .stems:
            return mix.stems.keys.sorted().map { name in
                HSExportItem(source: mix.stems[name]!, trim: nil, title: "\(p.title) – \(name)", fileName: "\(base) – Spur \(safe(name))",
                             trackNumber: nil)
            }
        }
    }

    static func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    /// Dateiname ohne verbotene Zeichen.
    public static func safe(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let cleaned = s.unicodeScalars.map { bad.contains($0) ? "-" : String($0) }.joined()
        return String(cleaned.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    }
}
