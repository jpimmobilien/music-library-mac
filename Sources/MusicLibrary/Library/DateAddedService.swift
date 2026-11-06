import Foundation
import iTunesLibrary
import MLCore
import MLStore

/// Hinzufügedatum aus Dateisystem und Apple Musik (v2.1).
///
/// Quellen in dieser Rangfolge (siehe `DateAddedResolver`):
///  1. Apple Musik / iTunes: „Hinzugefügt“ aus der freigegebenen Mediathek-XML (ohne Rückfrage) oder – nur auf
///     ausdrücklichen Wunsch in den Einstellungen – über das iTunesLibrary-Framework (macOS fragt einmal nach).
///  2. Erstellungsdatum der Datei.
///  3. Zeitpunkt, zu dem die Datei in ihren Ordner gelegt wurde (Finder „Hinzugefügt“).
///  4. Erster Import in Music Library.
/// Das Änderungsdatum wird nie verwendet.
enum FileDates {
    static func candidates(path: String) -> (created: Int64?, addedToFolder: Int64?) {
        let url = URL(fileURLWithPath: path)
        guard let v = try? url.resourceValues(forKeys: [.creationDateKey, .addedToDirectoryDateKey]) else { return (nil, nil) }
        return (v.creationDate.map { Int64($0.timeIntervalSince1970) }, v.addedToDirectoryDate.map { Int64($0.timeIntervalSince1970) })
    }
}

/// Hinzufügedaten aus Apple Musik, nachschlagbar über den Dateipfad oder (falls die Datei woanders liegt)
/// eindeutig über Titel, Interpret, Album und Dauer.
struct AppleMusicDates: Sendable {
    private(set) var byPath: [String: Int64] = [:]
    private(set) var byMeta: [String: [(durationMs: Int64, date: Int64)]] = [:]
    var count: Int { byPath.count }

    static func pathKey(_ path: String) -> String {
        // APFS/HFS+ unterscheiden standardmäßig nicht nach Groß-/Kleinschreibung; Unicode-Normalform angleichen.
        URL(fileURLWithPath: path).standardizedFileURL.path.precomposedStringWithCanonicalMapping.lowercased()
    }

    static func metaKey(title: String?, artist: String?, album: String?) -> String? {
        guard let t = title?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        func n(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespaces).precomposedStringWithCanonicalMapping.lowercased() }
        return n(t) + "\u{1F}" + n(artist) + "\u{1F}" + n(album)
    }

    mutating func add(path: String?, title: String?, artist: String?, album: String?, durationMs: Int64, date: Date) {
        let d = Int64(date.timeIntervalSince1970)
        if let path { byPath[Self.pathKey(path)] = d }
        if let key = Self.metaKey(title: title, artist: artist, album: album) {
            byMeta[key, default: []].append((durationMs, d))
        }
    }

    /// Datum für einen Titel der Bibliothek: zuerst über den Pfad, sonst über Titel/Interpret/Album, wenn genau
    /// ein Eintrag mit ähnlicher Dauer (± 2 s) passt.
    func lookup(path: String, title: String?, artist: String?, album: String?, durationMs: Int64) -> Int64? {
        if let d = byPath[Self.pathKey(path)] { return d }
        guard let key = Self.metaKey(title: title, artist: artist, album: album), let list = byMeta[key] else { return nil }
        let matches = list.filter { durationMs <= 0 || $0.durationMs <= 0 || abs($0.durationMs - durationMs) <= 2000 }
        guard matches.count == 1 else { return nil }
        return matches[0].date
    }

    /// Mögliche Orte der von Apple Musik/iTunes freigegebenen Mediathek-XML („Mediathek-XML für andere Apps
    /// freigeben“ in den Einstellungen von Musik → Erweitert, bzw. ältere iTunes-Mediatheken).
    static var xmlCandidates: [URL] {
        let music = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music", isDirectory: true)
        return [
            music.appendingPathComponent("Music/Library.xml"),
            music.appendingPathComponent("Music/Music Library.xml"),
            music.appendingPathComponent("iTunes/iTunes Music Library.xml"),
            music.appendingPathComponent("iTunes/iTunes Library.xml"),
        ]
    }

    /// Liest alle gefundenen Mediathek-XML-Dateien (neueste Angabe gewinnt nicht: das **früheste** Datum je Titel
    /// zählt, weil ältere iTunes-Mediatheken das ursprüngliche Hinzufügedatum enthalten).
    static func loadXML() -> AppleMusicDates? {
        var result = AppleMusicDates()
        var found = false
        for url in xmlCandidates where FileManager.default.isReadableFile(atPath: url.path) {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                  let tracks = plist["Tracks"] as? [String: Any] else { continue }
            found = true
            for case let t as [String: Any] in tracks.values {
                guard let date = t["Date Added"] as? Date else { continue }
                var path: String?
                if let loc = t["Location"] as? String, let u = URL(string: loc), u.isFileURL { path = u.path }
                let duration = (t["Total Time"] as? Int).map(Int64.init) ?? 0
                result.addEarliest(path: path, title: t["Name"] as? String, artist: t["Artist"] as? String,
                                   album: t["Album"] as? String, durationMs: duration, date: date)
            }
        }
        return found ? result : nil
    }

    private mutating func addEarliest(path: String?, title: String?, artist: String?, album: String?, durationMs: Int64, date: Date) {
        let d = Int64(date.timeIntervalSince1970)
        if let path {
            let k = Self.pathKey(path)
            byPath[k] = min(byPath[k] ?? d, d)
        }
        if let key = Self.metaKey(title: title, artist: artist, album: album) {
            byMeta[key, default: []].append((durationMs, d))
        }
    }

    /// Apple-Musik-Mediathek über das iTunesLibrary-Framework (löst beim ersten Mal die Systemabfrage
    /// „Zugriff auf Apple Music und Mediathek“ aus).
    static func loadITLibrary() throws -> AppleMusicDates {
        let lib = try ITLibrary(apiVersion: "1.0")
        var result = AppleMusicDates()
        for item in lib.allMediaItems {
            guard let date = item.addedDate else { continue }
            result.add(path: item.location?.path, title: item.title, artist: item.artist?.name, album: item.album.title,
                       durationMs: Int64(item.totalTime), date: date)
        }
        return result
    }
}

extension LibraryService {
    /// Hinzufügedaten bestimmen.
    /// - Automatisch nach dem Start (`force == false`): nur Titel, deren Datum noch nicht rekonstruiert ist
    ///   (Import durch Version 1/2.0 oder Version 2.0 nach einem Zurückwechseln); Apple Musik nur über die XML.
    /// - Aus den Einstellungen (`force == true`): alle Titel erneut prüfen; mit `useAppleMusic` zusätzlich die
    ///   Mediathek über das iTunesLibrary-Framework.
    /// Ein Datum aus Apple Musik wird nie durch eine schwächere Quelle ersetzt, ein vorhandenes Datum nie auf einen
    /// späteren Zeitpunkt verschoben (`DateAddedResolver`).
    func reconstructDatesAdded(useAppleMusic: Bool, force: Bool) {
        guard let model, !model.demo, !model.datesAddedRunning else { return }
        let store = self.store
        model.datesAddedRunning = true
        if force { model.datesAddedStatus = "Hinzufügedaten werden bestimmt …" }
        Task.detached(priority: .utility) { [weak self] in
            let outcome = LibraryService.performDateReconstruction(store: store, useITLibrary: useAppleMusic, force: force)
            await MainActor.run { [weak self] in
                guard let self, let model = self.model else { return }
                model.datesAddedRunning = false
                if outcome.changed > 0 { model.reloadLibrary() }
                if force || outcome.changed > 0 {
                    model.datesAddedStatus = outcome.message
                }
            }
        }
    }

    struct DateReconstructionOutcome: Sendable {
        var changed = 0
        var appleMusic = 0
        var fileSystem = 0
        var message = ""
    }

    nonisolated static func performDateReconstruction(store: LibraryStore, useITLibrary: Bool, force: Bool) -> DateReconstructionOutcome {
        var outcome = DateReconstructionOutcome()
        guard let rows = try? store.dateAddedRows() else {
            outcome.message = "Die Bibliothek konnte nicht gelesen werden."
            return outcome
        }
        let todo = force ? rows : rows.filter { $0.source == .unknown }
        guard !todo.isEmpty else {
            outcome.message = "Alle Hinzufügedaten sind bereits bestimmt."
            return outcome
        }
        var apple: AppleMusicDates? = loadAppleMusicIndex()
        var appleError: String?
        if useITLibrary {
            do {
                let lib = try AppleMusicDates.loadITLibrary()
                apple = lib
                AppleMusicCache.shared.store(lib)
                UserDefaults.standard.set(true, forKey: AppleMusicCache.allowedKey)
            } catch {
                appleError = "Apple Musik ist nicht zugänglich (Zugriff in Systemeinstellungen → Datenschutz & Sicherheit → Medien & Apple Music erlauben)."
            }
        }
        let now = Int64(Date().timeIntervalSince1970)
        var changes: [(uid: Int64, date: Int64, source: DateAddedSource)] = []
        for row in todo {
            var c = DateAddedResolver.Candidates()
            c.appleMusic = apple?.lookup(path: row.path, title: row.title, artist: row.artist, album: row.album, durationMs: row.durationMs)
            // Bereits rekonstruierte Titel nur noch mit Apple-Musik-Daten verbessern
            if row.source == .unknown && row.available {
                let fs = FileDates.candidates(path: row.path)
                c.fileCreated = fs.created
                c.addedToFolder = fs.addedToFolder
            } else if row.source == .unknown {
                // Laufwerk nicht angeschlossen: später erneut versuchen, außer Apple Musik kennt den Titel
                guard c.appleMusic != nil else { continue }
            }
            guard let r = DateAddedResolver.reconstruct(current: row.dateAdded, source: row.source, c, now: now) else { continue }
            if r.date == row.dateAdded && r.source == row.source { continue }
            changes.append((row.uid, r.date, r.source))
            if r.source == .appleMusic { outcome.appleMusic += 1 }
            if r.source == .fileCreated || r.source == .addedToFolder { outcome.fileSystem += 1 }
        }
        do {
            try store.setDateAdded(changes)
            try? store.setMeta("dateAddedReconstructed", String(now))
            outcome.changed = changes.count
        } catch {
            outcome.message = "Die Hinzufügedaten konnten nicht gespeichert werden: \(error.localizedDescription)"
            return outcome
        }
        var parts: [String] = []
        if outcome.appleMusic > 0 { parts.append("\(outcome.appleMusic) aus Apple Musik") }
        if outcome.fileSystem > 0 { parts.append("\(outcome.fileSystem) aus dem Erstellungsdatum der Datei") }
        let rest = outcome.changed - outcome.appleMusic - outcome.fileSystem
        if rest > 0 { parts.append("\(rest) mit dem Importdatum") }
        outcome.message = outcome.changed == 0
            ? "Keine Änderungen – die Hinzufügedaten sind aktuell."
            : "\(outcome.changed) Hinzufügedaten bestimmt (" + parts.joined(separator: ", ") + ")."
        if let appleError { outcome.message += " " + appleError }
        if apple == nil && !useITLibrary && force {
            outcome.message += " Apple-Musik-Daten wurden nicht gefunden (Mediathek-XML nicht freigegeben)."
        }
        return outcome
    }

    nonisolated static func loadAppleMusicIndex() -> AppleMusicDates? { AppleMusicCache.shared.index() }

    /// Datum und Herkunft für eine neu gefundene Datei.
    nonisolated static func dateAddedForNewFile(_ record: TrackRecord, apple: AppleMusicDates?, now: Int64) -> (Int64, DateAddedSource) {
        let fs = FileDates.candidates(path: record.path)
        var c = DateAddedResolver.Candidates(fileCreated: fs.created, addedToFolder: fs.addedToFolder)
        c.appleMusic = apple?.lookup(path: record.path, title: record.tags?.title, artist: record.tags?.artists.first,
                                     album: record.tags?.album, durationMs: record.audio.durationMs)
        let r = DateAddedResolver.forNewTrack(c, now: now)
        return (r.date, r.source)
    }
}

/// Apple-Musik-Daten für neue Titel und die automatische Rekonstruktion: XML (ohne Rückfrage) bzw. – wenn der
/// Zugriff früher ausdrücklich erlaubt wurde – das iTunesLibrary-Framework. Einmal je Programmstart geladen.
final class AppleMusicCache: @unchecked Sendable {
    static let shared = AppleMusicCache()
    static let allowedKey = "appleMusicDatesAllowed"
    private let lock = NSLock()
    private var tried = false
    private var cached: AppleMusicDates?

    func index() -> AppleMusicDates? {
        lock.lock()
        defer { lock.unlock() }
        if tried { return cached }
        tried = true
        if UserDefaults.standard.bool(forKey: Self.allowedKey), let lib = try? AppleMusicDates.loadITLibrary() {
            cached = lib
        } else {
            cached = AppleMusicDates.loadXML()
        }
        return cached
    }

    func store(_ dates: AppleMusicDates) {
        lock.lock()
        cached = dates
        tried = true
        lock.unlock()
    }
}
