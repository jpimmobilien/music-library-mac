import Foundation

/// Ausschnitt in Sekunden (Start < Ende).
public struct TrimRange: Codable, Hashable, Sendable {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    public var length: Double { max(0, end - start) }

    /// Auf eine Dauer begrenzen; nil, wenn der Ausschnitt die ganze Datei umfasst oder leer ist.
    public func clamped(to duration: Double) -> TrimRange? {
        let s = min(max(0, start), duration)
        let e = min(max(s, end), duration)
        if e - s < 0.01 { return nil }
        if s <= 0.0005 && e >= duration - 0.0005 { return nil }
        return TrimRange(start: s, end: e)
    }
}

/// Wohin eine fertige Datei geht.
public enum StudioDestination: Codable, Hashable, Sendable {
    /// In einen frei gewählten Ordner speichern (nicht in die Bibliothek).
    case folder(path: String)
    /// In einen Musikordner der Bibliothek speichern (Unterordner relativ, z. B. „Audio Studio“) und einlesen.
    case library(folderID: Int64, folderPath: String, subfolder: String)
    /// Schneiden vorhandener Songs: Original ersetzen. Vorher wird es gesichert (Rückgängig möglich);
    /// Titel-Kennung, Favoriten, Playlists und Statistik bleiben erhalten, weil der Pfad gleich bleibt.
    case replaceOriginal(uid: Int64, path: String)

    public var directoryPath: String {
        switch self {
        case .folder(let path): return path
        case .replaceOriginal(_, let path): return (path as NSString).deletingLastPathComponent
        case .library(_, let folderPath, let subfolder):
            let base = folderPath.hasSuffix("/") ? String(folderPath.dropLast()) : folderPath
            let sub = subfolder.split(separator: "/").map { FileNames.sanitize(String($0)) }.filter { !$0.isEmpty }.joined(separator: "/")
            return sub.isEmpty ? base : base + "/" + sub
        }
    }

    public var importsIntoLibrary: Bool {
        switch self {
        case .library, .replaceOriginal: return true
        case .folder: return false
        }
    }

    public var replacesOriginal: Bool {
        if case .replaceOriginal = self { return true }
        return false
    }
}

/// Arbeitsschritt eines Auftrags.
public enum JobPhase: String, Codable, Hashable, Sendable {
    case waiting
    case downloading
    case converting
    case tagging
    case importing
    case paused
    case done
    case failed
    case cancelled

    public var label: String {
        switch self {
        case .waiting: return "Wartet"
        case .downloading: return "Wird geladen"
        case .converting: return "Wird umgewandelt"
        case .tagging: return "Tags werden geschrieben"
        case .importing: return "Wird in die Bibliothek übernommen"
        case .paused: return "Angehalten"
        case .done: return "Fertig"
        case .failed: return "Fehler"
        case .cancelled: return "Abgebrochen"
        }
    }

    public var isActive: Bool { self == .downloading || self == .converting || self == .tagging || self == .importing }
    public var isFinished: Bool { self == .done || self == .failed || self == .cancelled }
}

/// Ein Auftrag in der Warteschlange.
public struct StudioJob: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var source: SourceInfo
    public var options: ExportOptions
    public var trim: TrimRange?
    public var metadata: StudioMetadata
    /// Dateiname ohne Endung (bereinigt).
    public var fileName: String
    public var destination: StudioDestination
    /// Ein-/Ausblenden in Sekunden (0 = aus).
    public var fadeIn: Double = 0
    public var fadeOut: Double = 0
    /// Ohne Neukodierung schneiden, wenn möglich (Schneiden vorhandener Songs im selben Format).
    public var preferPassthrough: Bool = false
    public var phase: JobPhase
    /// 0…1 innerhalb des aktuellen Schritts.
    public var progress: Double
    /// Zusatz zur Anzeige, z. B. „3,2 MB von 8,1 MB · 1,4 MB/s“.
    public var detail: String?
    public var error: String?
    /// Fertige Datei.
    public var outputPath: String?
    public var created: Date
    public var finished: Date?

    public init(id: UUID = UUID(), source: SourceInfo, options: ExportOptions, trim: TrimRange?, metadata: StudioMetadata,
                fileName: String, destination: StudioDestination, created: Date = Date()) {
        self.id = id
        self.source = source
        self.options = options
        self.trim = trim
        self.metadata = metadata
        self.fileName = fileName
        self.destination = destination
        self.phase = .waiting
        self.progress = 0
        self.created = created
    }

    /// Gesamtfortschritt 0…1 (Laden zählt bei Internet-Quellen zur Hälfte).
    public var overallProgress: Double {
        let needsDownload = source.kind != .localFile && source.localFile == nil
        switch phase {
        case .waiting, .paused, .cancelled: return needsDownload ? progress * 0.5 : 0
        case .downloading: return progress * 0.5
        case .converting: return (needsDownload ? 0.5 : 0) + progress * (needsDownload ? 0.45 : 0.9)
        case .tagging: return 0.96
        case .importing: return 0.98
        case .done: return 1
        case .failed: return progress
        }
    }
}

/// Regeln der Warteschlange (rein, testbar): immer genau ein aktiver Auftrag, Reihenfolge wie hinzugefügt,
/// nach einem Fehler geht es mit dem nächsten weiter.
public enum StudioQueueLogic {
    /// Nächster startbarer Auftrag – nur wenn keiner aktiv ist.
    public static func nextRunnable(_ jobs: [StudioJob]) -> UUID? {
        if jobs.contains(where: { $0.phase.isActive }) { return nil }
        return jobs.first(where: { $0.phase == .waiting })?.id
    }

    public static func canPause(_ job: StudioJob) -> Bool { job.phase == .waiting || job.phase.isActive && job.phase != .importing }
    public static func canResume(_ job: StudioJob) -> Bool { job.phase == .paused }
    public static func canCancel(_ job: StudioJob) -> Bool { !job.phase.isFinished }
    public static func canRetry(_ job: StudioJob) -> Bool { job.phase == .failed || job.phase == .cancelled }
    public static func canRemove(_ job: StudioJob) -> Bool { !job.phase.isActive }

    /// Zusammenfassung für die Kopfzeile, z. B. „2 von 5 fertig · 1 Fehler“.
    public static func summary(_ jobs: [StudioJob]) -> String {
        if jobs.isEmpty { return "Keine Aufträge" }
        let done = jobs.filter { $0.phase == .done }.count
        let failed = jobs.filter { $0.phase == .failed }.count
        var s = "\(done) von \(jobs.count) fertig"
        if failed > 0 { s += failed == 1 ? " · 1 Fehler" : " · \(failed) Fehler" }
        return s
    }
}

/// Eintrag im Exportverlauf (gespeichert als JSON).
public struct StudioHistoryEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var sourceKind: SourceKind
    /// Adresse oder Dateipfad der Quelle.
    public var source: String
    public var title: String
    public var artist: String
    public var outputPath: String
    public var formatSummary: String
    public var duration: Double?
    public var imported: Bool
    public var succeeded: Bool
    public var error: String?
    /// Original ersetzt: Pfad der Sicherung (für „Rückgängig“); nil, wenn nichts ersetzt wurde.
    public var backupPath: String?
    /// „Rückgängig“ wurde ausgeführt.
    public var undone: Bool = false

    public init(id: UUID = UUID(), date: Date = Date(), sourceKind: SourceKind, source: String, title: String, artist: String,
                outputPath: String, formatSummary: String, duration: Double?, imported: Bool, succeeded: Bool, error: String? = nil,
                backupPath: String? = nil) {
        self.backupPath = backupPath
        self.id = id
        self.date = date
        self.sourceKind = sourceKind
        self.source = source
        self.title = title
        self.artist = artist
        self.outputPath = outputPath
        self.formatSummary = formatSummary
        self.duration = duration
        self.imported = imported
        self.succeeded = succeeded
        self.error = error
    }
}

/// Verlauf: neueste zuerst, höchstens `limit` Einträge.
public struct StudioHistory: Codable, Hashable, Sendable {
    public var entries: [StudioHistoryEntry] = []
    public static let limit = 500

    public init(entries: [StudioHistoryEntry] = []) { self.entries = entries }

    public mutating func add(_ entry: StudioHistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }

    /// Wurde diese Quelle schon einmal erfolgreich exportiert? (für die Doppel-Warnung)
    public func previousExport(of source: String) -> StudioHistoryEntry? {
        entries.first(where: { $0.succeeded && $0.source == source })
    }
}

/// Erkennung doppelter Importe (rein, testbar).
public enum DuplicateCheck {
    public struct Candidate: Hashable, Sendable {
        public var uid: Int64
        public var title: String
        public var artist: String
        public var durationSeconds: Double
        public var path: String

        public init(uid: Int64, title: String, artist: String, durationSeconds: Double, path: String) {
            self.uid = uid
            self.title = title
            self.artist = artist
            self.durationSeconds = durationSeconds
            self.path = path
        }
    }

    /// Titel der Bibliothek, die mit großer Wahrscheinlichkeit dieselbe Aufnahme sind: gleicher Titel und
    /// Interpret (ohne Groß-/Kleinschreibung, Akzente, Satzzeichen) und Dauer ±2 s, oder derselbe Zielpfad.
    public static func matches(title: String, artist: String, duration: Double?, targetPath: String?, in library: [Candidate]) -> [Candidate] {
        let t = normalize(title)
        let a = normalize(artist)
        return library.filter { c in
            if let targetPath, c.path == targetPath { return true }
            guard !t.isEmpty, normalize(c.title) == t else { return false }
            if !a.isEmpty, !normalize(c.artist).isEmpty, normalize(c.artist) != a { return false }
            if let duration, duration > 0, c.durationSeconds > 0 { return abs(c.durationSeconds - duration) <= 2 }
            return true
        }
    }

    public static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
