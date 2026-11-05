import Foundation

/// Eine beim Durchsuchen eines Musikordners gefundene Datei (nur die für den Abgleich nötigen Angaben).
public struct ScannedFile: Hashable, Sendable {
    /// Musikordner (Bibliotheksordner), in dem die Datei gefunden wurde.
    public var folderID: Int64
    /// Vollständiger Dateipfad (POSIX).
    public var path: String
    public var sizeBytes: Int64
    /// Änderungsdatum in Sekunden seit 1970.
    public var dateModified: Int64
    /// Dateikennung des Dateisystems (Inode bzw. `fileResourceIdentifier`); `nil` = unbekannt.
    public var fileID: UInt64?
    /// Dauerhafte Kennung des Laufwerks (z. B. Volume-UUID); `nil` = unbekannt. Dateikennungen gelten nur
    /// innerhalb eines Laufwerks – ohne diese Angabe nur innerhalb desselben Musikordners.
    public var volumeID: String?

    public init(folderID: Int64, path: String, sizeBytes: Int64, dateModified: Int64, fileID: UInt64? = nil, volumeID: String? = nil) {
        self.folderID = folderID
        self.path = path
        self.sizeBytes = sizeBytes
        self.dateModified = dateModified
        self.fileID = fileID
        self.volumeID = volumeID
    }

    public var fileName: String { SyncPlanner.fileName(of: path) }
    public var pathKey: String { SyncPlanner.pathKey(path) }
}

/// Ein bereits bekannter Titel aus der App-Datenbank (nur Abgleich-Spalten).
public struct KnownFile: Hashable, Sendable {
    public var uid: Int64
    public var folderID: Int64
    public var path: String
    public var sizeBytes: Int64
    public var dateModified: Int64
    public var fileID: UInt64?
    public var volumeID: String?
    public var available: Bool
    /// Version des Tag-Lesers, mit der die Metadaten gelesen wurden.
    public var metaVersion: Int

    public init(
        uid: Int64, folderID: Int64, path: String, sizeBytes: Int64, dateModified: Int64,
        fileID: UInt64? = nil, volumeID: String? = nil, available: Bool = true, metaVersion: Int
    ) {
        self.uid = uid
        self.folderID = folderID
        self.path = path
        self.sizeBytes = sizeBytes
        self.dateModified = dateModified
        self.fileID = fileID
        self.volumeID = volumeID
        self.available = available
        self.metaVersion = metaVersion
    }

    public var fileName: String { SyncPlanner.fileName(of: path) }
    public var pathKey: String { SyncPlanner.pathKey(path) }
}

/// Was mit einer gefundenen Datei geschehen soll.
public struct SyncItem: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        /// Neue Datei → neuer Titel (neue Kennung).
        case new
        /// Verschoben oder umbenannt (Kennung bleibt).
        case moved
        /// War nicht verfügbar und ist wieder da (Kennung bleibt).
        case reappeared
        /// Inhalt geändert (Größe/Änderungsdatum) → Tags neu lesen.
        case changed
        /// Unverändert, aber mit älterer Tag-Leser-Version gelesen → Tags neu lesen.
        case refreshed
        /// Nur die Dateikennung/Laufwerkskennung hat sich geändert (z. B. Datei sicher ersetzt).
        case relinked
    }

    public var file: ScannedFile
    /// Bestehende Kennung (Favoriten/Playlists bleiben daran hängen) oder `nil` = neuer Titel.
    public var uid: Int64?
    /// Metadaten (Tags, Cover) neu lesen?
    public var readTags: Bool
    /// Wurde der Titel an einem neuen Ort bzw. mit neuer Dateikennung wiedererkannt? (Pfad, Ordner, Kennung aktualisieren)
    public var relinked: Bool
    /// Hat sich der Pfad geändert (verschoben/umbenannt)?
    public var moved: Bool
    /// Hat sich der Inhalt geändert (Größe oder Änderungsdatum)?
    public var contentChanged: Bool
    /// War der Titel als „nicht verfügbar“ markiert?
    public var reappeared: Bool

    public init(file: ScannedFile, uid: Int64?, readTags: Bool, relinked: Bool = false, moved: Bool = false, contentChanged: Bool = false, reappeared: Bool = false) {
        self.file = file
        self.uid = uid
        self.readTags = readTags
        self.relinked = relinked
        self.moved = moved
        self.contentChanged = contentChanged
        self.reappeared = reappeared
    }

    public var kind: Kind {
        if uid == nil { return .new }
        if moved { return .moved }
        if reappeared { return .reappeared }
        if contentChanged { return .changed }
        if readTags { return .refreshed }
        return .relinked
    }
}

public struct SyncPlan: Hashable, Sendable {
    /// Neue, geänderte, wiedergefundene oder verschobene Titel.
    public var items: [SyncItem]
    /// Unverändert und verfügbar – nichts zu tun.
    public var unchangedCount: Int
    /// Datei ist (in einem erreichbaren Musikordner) nicht mehr da → als nicht verfügbar markieren.
    public var missing: [Int64]
    /// Musikordner bzw. Laufwerk nicht erreichbar → nicht verfügbar, Daten bleiben unverändert.
    public var offline: [Int64]
    /// Musikordner, die als nicht erreichbar behandelt wurden (übergeben oder verdächtig leer).
    public var offlineFolders: Set<Int64>

    public var isEmpty: Bool { items.isEmpty && missing.isEmpty && offline.isEmpty }

    public var newItems: [SyncItem] { items.filter { $0.kind == .new } }
    public var movedItems: [SyncItem] { items.filter { $0.kind == .moved } }
    public var reappearedItems: [SyncItem] { items.filter { $0.reappeared } }
    public var tagReadItems: [SyncItem] { items.filter(\.readTags) }
}

/// Abgleich zwischen App-Datenbank und den Dateien der Musikordner (macOS-Fassung von
/// `library/SyncPlanner.kt`; dort wurde gegen die Android-Medienbibliothek abgeglichen).
///
/// Ziel: Favoriten, Playlists, Statistik und Verlauf bleiben am richtigen Titel, auch wenn
/// - eine Datei ersetzt wird (z. B. sicheres Schreiben der Tags: neue Dateikennung, gleicher Pfad),
/// - eine Datei verschoben oder umbenannt wird (gleiche Dateikennung; ohne gültige Kennung: gleicher
///   Name und gleiche Größe, bzw. gleiche Größe, gleiches Änderungsdatum und gleiche Endung),
/// - ein externes Laufwerk getrennt und wieder angeschlossen wird.
///
/// Regeln:
/// 1. Gleicher Pfad hat immer Vorrang (erst exakt, dann ohne Groß-/Kleinschreibung; Unicode-Normalform egal).
/// 2. Dann gleiche Dateikennung (Inode) auf demselben Laufwerk – nur für Ordner, deren Kennungen
///    verlässlich sind (`trustedFileIDFolders`; z. B. nicht FAT/exFAT oder Netzlaufwerke).
/// 3. Dann Wiedererkennung unter den verschwundenen Titeln erreichbarer Ordner – nur bei EINDEUTIGEM
///    Treffer, sonst wird nichts geraten (neuer Titel).
/// 4. Es wird nie etwas gelöscht: Nicht mehr gefundene Titel werden nur als „nicht verfügbar“ markiert.
///    Ist ein ganzer Ordner/ein Laufwerk nicht erreichbar, bleibt alles unverändert und seine Titel gelten
///    als „offline“ (ebenfalls nicht verfügbar). Ein erreichbarer Ordner, in dem plötzlich KEINE Datei
///    mehr gefunden wird, obwohl verfügbare Titel bekannt sind, wird vorsichtshalber genauso behandelt
///    (typisch: fehlende Zugriffsrechte, Laufwerk noch nicht bereit).
/// 5. Tauchen Titel wieder auf, werden sie mit allen Daten wiedererkannt.
public enum SyncPlanner {

    /// Vergleichsschlüssel eines Pfads: Unicode-NFC und Kleinschreibung (APFS/HFS+ sind
    /// standardmäßig unabhängig von Groß-/Kleinschreibung und Normalform).
    public static func pathKey(_ path: String) -> String {
        exactKey(path).lowercased()
    }

    static func exactKey(_ path: String) -> String {
        path.utf8.allSatisfy { $0 < 0x80 } ? path : path.precomposedStringWithCanonicalMapping
    }

    /// Letzte Pfadkomponente.
    public static func fileName(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }

    /// Endung in Kleinschreibung (wie Kotlin `substringAfterLast('.', "")`).
    static func extensionKey(_ fileName: String) -> String {
        guard let dot = fileName.lastIndex(of: ".") else { return "" }
        return String(fileName[fileName.index(after: dot)...]).lowercased()
    }

    /// - Parameters:
    ///   - known: alle bekannten Titel der Datenbank.
    ///   - scanned: alle gefundenen Dateien der erreichbaren Musikordner.
    ///   - onlineFolders: Musikordner, die erreichbar waren und vollständig durchsucht wurden. Ordner, aus
    ///     denen Dateien in `scanned` stammen, gelten ebenfalls als erreichbar.
    ///   - tagReaderVersion: aktuelle Version des Tag-Lesers (ältere Einträge werden neu gelesen).
    ///   - trustedFileIDFolders: Ordner mit verlässlichen Dateikennungen (`nil` = alle).
    public static func plan(
        known: [KnownFile],
        scanned: [ScannedFile],
        onlineFolders: Set<Int64>,
        tagReaderVersion: Int,
        trustedFileIDFolders: Set<Int64>? = nil
    ) -> SyncPlan {
        // Erreichbare Ordner; verdächtig leere Ordner zählen als nicht erreichbar.
        var online = onlineFolders.union(scanned.map(\.folderID))
        let scannedFolders = Set(scanned.map(\.folderID))
        var suspicious = Set<Int64>()
        for k in known where k.available && online.contains(k.folderID) && !scannedFolders.contains(k.folderID) {
            suspicious.insert(k.folderID)
        }
        online.subtract(suspicious)
        let knownFolders = Set(known.map(\.folderID))
        // Dateikennungen gelten je Laufwerk (bzw. je Ordner); auch Titel nicht erreichbarer Ordner dürfen
        // per Kennung wiedergefunden werden (z. B. alle Dateien in einen anderen Musikordner verschoben).
        let trusted = trustedFileIDFolders ?? knownFolders.union(online)
        let offlineFolders = knownFolders.subtracting(online)

        var byExact: [String: [KnownFile]] = [:]
        var byKey: [String: [KnownFile]] = [:]
        var byFileID: [String: [KnownFile]] = [:]
        for k in known {
            byExact[exactKey(k.path), default: []].append(k)
            byKey[pathKey(k.path), default: []].append(k)
            if let id = fileIDKey(fileID: k.fileID, volumeID: k.volumeID, folderID: k.folderID), trusted.contains(k.folderID) {
                byFileID[id, default: []].append(k)
            }
        }

        var used = Set<Int64>()
        var items: [SyncItem] = []
        var unchanged = 0
        // Ergebnis je gefundener Datei (Index in `scanned`), damit die Reihenfolge der Liste erhalten bleibt.
        var resultByIndex: [Int: SyncItem] = [:]

        func accept(_ index: Int, _ file: ScannedFile, _ match: KnownFile) {
            used.insert(match.uid)
            let contentChanged = match.sizeBytes != file.sizeBytes || match.dateModified != file.dateModified
            let moved = match.path != file.path || match.folderID != file.folderID
            let idChanged = (file.fileID != nil && file.fileID != match.fileID) || (file.volumeID != nil && file.volumeID != match.volumeID)
            let relinked = moved || idChanged
            let needsTags = contentChanged || match.metaVersion < tagReaderVersion
            if !contentChanged && !relinked && !needsTags && match.available {
                unchanged += 1
            } else {
                resultByIndex[index] = SyncItem(
                    file: file, uid: match.uid, readTags: needsTags, relinked: relinked, moved: moved,
                    contentChanged: contentChanged, reappeared: !match.available
                )
            }
        }

        // 1a. Gleicher Pfad (exakt, Normalform egal).
        var remaining: [Int] = []
        for (i, file) in scanned.enumerated() {
            if let match = byExact[exactKey(file.path)]?.first(where: { !used.contains($0.uid) }) {
                accept(i, file, match)
            } else {
                remaining.append(i)
            }
        }
        // 1b. Gleicher Pfad ohne Groß-/Kleinschreibung (z. B. nur Schreibweise des Namens geändert).
        var afterPath: [Int] = []
        for i in remaining {
            let file = scanned[i]
            if let match = byKey[file.pathKey]?.first(where: { !used.contains($0.uid) }) {
                accept(i, file, match)
            } else {
                afterPath.append(i)
            }
        }

        // 2. Gleiche, verlässliche Dateikennung an anderem Ort = verschoben/umbenannt (ggf. mit geänderten Tags).
        var unmatched: [Int] = []
        for i in afterPath {
            let file = scanned[i]
            var match: KnownFile?
            if trusted.contains(file.folderID), let id = fileIDKey(fileID: file.fileID, volumeID: file.volumeID, folderID: file.folderID) {
                match = byFileID[id]?.first { !used.contains($0.uid) }
            }
            if let match { accept(i, file, match) } else { unmatched.append(i) }
        }

        // 3. Verschwundene Titel erreichbarer Ordner: Kandidaten für eine Wiedererkennung.
        var vanished = known.filter { !used.contains($0.uid) && online.contains($0.folderID) }
        for i in unmatched {
            let file = scanned[i]
            if let candidate = findMovedCandidate(file, vanished) {
                vanished.removeAll { $0.uid == candidate.uid }
                used.insert(candidate.uid)
                let contentChanged = candidate.sizeBytes != file.sizeBytes || candidate.dateModified != file.dateModified
                resultByIndex[i] = SyncItem(
                    file: file, uid: candidate.uid,
                    readTags: contentChanged || candidate.metaVersion < tagReaderVersion,
                    relinked: true, moved: true, contentChanged: contentChanged, reappeared: !candidate.available
                )
            } else {
                resultByIndex[i] = SyncItem(file: file, uid: nil, readTags: true)
            }
        }
        for i in scanned.indices { if let item = resultByIndex[i] { items.append(item) } }

        var missing: [Int64] = []
        var offline: [Int64] = []
        for k in known where !used.contains(k.uid) && k.available {
            if online.contains(k.folderID) { missing.append(k.uid) } else { offline.append(k.uid) }
        }
        return SyncPlan(items: items, unchangedCount: unchanged, missing: missing, offline: offline, offlineFolders: offlineFolders)
    }

    private static func fileIDKey(fileID: UInt64?, volumeID: String?, folderID: Int64) -> String? {
        guard let fileID, fileID != 0 else { return nil }
        if let volumeID, !volumeID.isEmpty { return "v:\(volumeID):\(fileID)" }
        return "f:\(folderID):\(fileID)"
    }

    /// Wiedererkennung einer verschobenen/neu kopierten Datei – nur bei EINDEUTIGEM Treffer:
    /// 1. gleicher Dateiname (ohne Groß-/Kleinschreibung) und gleiche Größe; bei mehreren zusätzlich
    ///    gleiches Änderungsdatum;
    /// 2. sonst gleiche Größe, gleiches Änderungsdatum und gleiche Endung (umbenannt).
    ///    (Android verglich hier die Dauer; vor dem Lesen der Tags ist auf dem Mac nur das Änderungsdatum bekannt.)
    static func findMovedCandidate(_ file: ScannedFile, _ vanished: [KnownFile]) -> KnownFile? {
        let name = pathKey(file.fileName)
        let byNameAndSize = vanished.filter { $0.sizeBytes == file.sizeBytes && pathKey($0.fileName) == name }
        if byNameAndSize.count == 1 { return byNameAndSize[0] }
        if byNameAndSize.count > 1 {
            let sameTime = byNameAndSize.filter { $0.dateModified == file.dateModified }
            return sameTime.count == 1 ? sameTime[0] : nil
        }
        let ext = extensionKey(file.fileName)
        let bySizeAndTime = vanished.filter {
            $0.sizeBytes == file.sizeBytes && file.sizeBytes > 0 &&
                $0.dateModified == file.dateModified &&
                extensionKey($0.fileName) == ext
        }
        return bySizeAndTime.count == 1 ? bySizeAndTime[0] : nil
    }
}
