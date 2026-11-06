import Foundation

/// Herkunft des Hinzufügedatums eines Titels (v2.1). Gespeichert als Zahl in `tracks.dateAddedSource`.
///
/// Rangfolge der Rekonstruktion (beste zuerst): Apple Musik/iTunes → Erstellungsdatum der Datei →
/// „Hinzugefügt“-Datum des Ordners (Finder) → erster Import in Music Library. Das Änderungsdatum der Datei
/// wird bewusst **nie** verwendet (es ändert sich z. B. beim Bearbeiten der Tags).
public enum DateAddedSource: Int, CaseIterable, Codable, Hashable, Sendable {
    /// Noch nicht rekonstruiert (Datum = erster Import durch Version 1/2.0, oft für alle Titel gleich).
    case unknown = 0
    /// „Hinzugefügt“ aus der Apple-Musik-/iTunes-Mediathek.
    case appleMusic = 1
    /// Erstellungsdatum der Datei.
    case fileCreated = 2
    /// Zeitpunkt, zu dem die Datei in ihren Ordner gelegt wurde (Finder „Hinzugefügt“).
    case addedToFolder = 3
    /// Erster Import in Music Library (kein besseres Datum verfügbar).
    case firstImport = 4

    public var label: String {
        switch self {
        case .unknown: return "Import in Music Library"
        case .appleMusic: return "laut Apple Musik"
        case .fileCreated: return "Datei erstellt"
        case .addedToFolder: return "in den Ordner gelegt"
        case .firstImport: return "Import in Music Library"
        }
    }

    /// Ein Datum aus dieser Quelle wird nie durch eine schwächere ersetzt.
    public var rank: Int {
        switch self {
        case .appleMusic: return 4
        case .fileCreated: return 3
        case .addedToFolder: return 2
        case .firstImport: return 1
        case .unknown: return 0
        }
    }
}

/// Auswahl des Hinzufügedatums aus den verfügbaren Quellen (reine Logik, getestet).
public enum DateAddedResolver {
    /// Frühestes plausibles Datum: 1. Januar 1995 (vorher gab es keine digitalen Musiksammlungen dieser Art;
    /// FAT-Laufwerke und defekte Kopien liefern oft 1970/1980).
    public static let earliestPlausible: Int64 = 788_918_400

    public struct Candidates: Hashable, Sendable {
        public var appleMusic: Int64?
        public var fileCreated: Int64?
        public var addedToFolder: Int64?
        public init(appleMusic: Int64? = nil, fileCreated: Int64? = nil, addedToFolder: Int64? = nil) {
            self.appleMusic = appleMusic
            self.fileCreated = fileCreated
            self.addedToFolder = addedToFolder
        }
    }

    static func plausible(_ v: Int64?, now: Int64) -> Int64? {
        guard let v, v >= earliestPlausible, v <= now + 86_400 else { return nil }
        return v
    }

    /// Bestes Datum für einen **neu gefundenen** Titel. Ohne Kandidaten: `now` als erster Import.
    public static func forNewTrack(_ c: Candidates, now: Int64) -> (date: Int64, source: DateAddedSource) {
        if let a = plausible(c.appleMusic, now: now) { return (a, .appleMusic) }
        if let f = plausible(c.fileCreated, now: now) { return (min(f, now), .fileCreated) }
        if let d = plausible(c.addedToFolder, now: now) { return (min(d, now), .addedToFolder) }
        return (now, .firstImport)
    }

    /// Rekonstruktion für einen **vorhandenen** Titel. Liefert `nil`, wenn nichts geändert werden soll.
    ///
    /// - Ein Datum aus Apple Musik ersetzt alles außer einem bereits übernommenen Apple-Musik-Datum.
    /// - Dateisystem-Daten ersetzen nur ein noch nicht rekonstruiertes Datum (`unknown`) und nur, wenn sie
    ///   **früher** liegen als das gespeicherte Importdatum (ein Titel kann nicht nach dem Import auf den Mac
    ///   gekommen sein). Sonst bleibt das Importdatum (`firstImport`).
    public static func reconstruct(current: Int64, source: DateAddedSource, _ c: Candidates, now: Int64) -> (date: Int64, source: DateAddedSource)? {
        if let a = plausible(c.appleMusic, now: now), source != .appleMusic { return (a, .appleMusic) }
        guard source == .unknown else { return nil }
        let limit = current > 0 ? current : now
        if let f = plausible(c.fileCreated, now: now), f <= limit { return (f, .fileCreated) }
        if let d = plausible(c.addedToFolder, now: now), d <= limit { return (d, .addedToFolder) }
        return (current > 0 ? current : now, .firstImport)
    }
}

public extension Track {
    /// Kopie mit gesetzter Herkunft des Hinzufügedatums.
    func withDateAddedSource(_ source: DateAddedSource) -> Track {
        var copy = self
        copy.dateAddedSource = source
        return copy
    }
}
