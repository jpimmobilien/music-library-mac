import Foundation

/// Ein Album der Übersicht (alle Discs zusammen).
public struct AlbumInfo: Hashable, Sendable, Identifiable {
    /// Dauerhafter Schlüssel (für Album-Favoriten), z. B. „a|a night at the opera|queen“.
    public var key: String
    /// Albumtitel aus den Tags; `nil` = Titel ohne Album-Tag („Unbekanntes Album“).
    public var title: String?
    /// Album-Interpret zur Anzeige (Tag „Album-Interpret“ bzw. einheitlicher Interpret); `nil` = unbekannt.
    public var artist: String?
    /// Mehrere Interpreten ohne Album-Interpret-Tag (bzw. als Compilation gekennzeichnet).
    public var isVarious: Bool
    /// Häufigstes Jahr der Titel (`nil` = kein Jahr in den Tags).
    public var year: Int?
    /// Häufigstes Genre der Titel (`nil` = kein Genre in den Tags).
    public var genre: String?
    /// Titel in Albumreihenfolge: Disc, dann Track, dann stabile Ausweichreihenfolge.
    public var trackUids: [Int64]
    /// Disc-Nummern laut Tags (leer, wenn keine Disc-Angaben vorhanden sind).
    public var discNumbers: [Int]
    public var totalDurationMs: Int64
    /// Sortiername (Tag „Album sortieren“) oder Titel.
    public var sortTitle: String?
    public var sortArtist: String?
    /// Jüngster Aufnahmezeitpunkt seiner Titel in die Bibliothek (Sekunden seit 1970; 0 = unbekannt).
    public var dateAdded: Int64

    public var trackCount: Int { trackUids.count }
    public var isMultiDisc: Bool { discNumbers.count > 1 }
    public var isUnknown: Bool { title == nil }
    public var id: String { key }

    public init(
        key: String, title: String?, artist: String?, isVarious: Bool, year: Int?, genre: String?,
        trackUids: [Int64], discNumbers: [Int], totalDurationMs: Int64, sortTitle: String?, sortArtist: String?,
        dateAdded: Int64 = 0
    ) {
        self.key = key
        self.title = title
        self.artist = artist
        self.isVarious = isVarious
        self.year = year
        self.genre = genre
        self.trackUids = trackUids
        self.discNumbers = discNumbers
        self.totalDurationMs = totalDurationMs
        self.sortTitle = sortTitle
        self.sortArtist = sortArtist
        self.dateAdded = dateAdded
    }
}

/// Bildet Alben aus Titeln (Portierung von `library/AlbumGrouping.kt`).
///
/// Regeln:
/// 1. Grundlage ist der Albumtitel (Groß-/Kleinschreibung und Akzente egal).
/// 2. Gleicher Titel allein genügt NICHT: Titel mit Album-Interpret-Tag werden nach Album-Interpret
///    getrennt („Greatest Hits“ von Queen ≠ „Greatest Hits“ von ABBA).
/// 3. Ohne Album-Interpret-Tag: als Compilation gekennzeichnete Titel bilden ein gemeinsames Album;
///    sonst wird je Ordner geprüft, ob alle Titel denselben Hauptinterpreten haben (dann gilt er als
///    Album-Interpret) oder ob es eine Zusammenstellung verschiedener Interpreten ist.
/// 4. Mehrere Discs (Disc-Tags oder Unterordner wie „CD1“/„CD2“) desselben Albums werden zu EINEM
///    Album zusammengeführt.
/// 5. Liegen gleichnamige Alben desselben Interpreten mit verschiedenen Jahren in getrennten Ordnern,
///    sind es verschiedene Alben (z. B. Neuaufnahme).
public enum AlbumGrouping {

    static let various = "#various"
    static let unknownArtist = "#unknown"

    private final class Candidate {
        let aaKey: String
        let various: Bool
        let explicitArtist: Bool
        var tracks: [Track] = []

        init(aaKey: String, various: Bool, explicitArtist: Bool) {
            self.aaKey = aaKey
            self.various = various
            self.explicitArtist = explicitArtist
        }

        var folders: Set<String> { Set(tracks.map(\.folderKey)) }
    }

    public struct Result: Sendable {
        public var albums: [AlbumInfo]
        public var albumKeyByTrack: [Int64: String]
    }

    public static func group(_ tracks: [Track]) -> Result {
        var albums: [AlbumInfo] = []
        var byTitle = OrderedGroups<String, Track>()
        var withoutAlbum: [Track] = []
        for t in tracks {
            let key = TextNorm.key(t.album)
            if key.isEmpty { withoutAlbum.append(t) } else { byTitle.append(t, to: key) }
        }
        for (titleKey, list) in byTitle.groups { albums += groupTitle(titleKey, list) }
        albums += groupUnknown(withoutAlbum)
        var keyByTrack: [Int64: String] = [:]
        keyByTrack.reserveCapacity(tracks.count)
        for album in albums {
            for uid in album.trackUids { keyByTrack[uid] = album.key }
        }
        return Result(albums: albums, albumKeyByTrack: keyByTrack)
    }

    private static func groupTitle(_ titleKey: String, _ tracks: [Track]) -> [AlbumInfo] {
        var order: [String] = []
        var candidates: [String: Candidate] = [:]
        func candidate(_ aaKey: String, various: Bool, explicit: Bool) -> Candidate {
            if let c = candidates[aaKey] { return c }
            let c = Candidate(aaKey: aaKey, various: various, explicitArtist: explicit)
            candidates[aaKey] = c
            order.append(aaKey)
            return c
        }

        var rest: [Track] = []
        for t in tracks {
            if let aa = t.albumArtists.first {
                let isVarious = ArtistNames.isVarious(aa)
                let key = isVarious ? various : TextNorm.key(t.albumArtists.joined(separator: ", "))
                candidate(key, various: isVarious, explicit: true).tracks.append(t)
            } else if t.compilation {
                candidate(various, various: true, explicit: true).tracks.append(t)
            } else {
                rest.append(t)
            }
        }
        // Titel ohne Album-Interpret: je Ordner auswerten.
        for (folder, inFolder) in OrderedGroups(rest, by: { $0.folderKey }).groups {
            let primaryKeys = OrderedSet(inFolder.map(primaryKey))
            if primaryKeys.count == 1 {
                candidate(primaryKeys.elements[0], various: false, explicit: false).tracks += inFolder
            } else {
                // Verschiedene Interpreten im selben Ordner: Zusammenstellung (gehört ggf. zur Compilation).
                if let existing = candidates[various], existing.folders.contains(where: { sameAlbumFolder($0, folder) }) {
                    existing.tracks += inFolder
                } else {
                    candidate("\(various)@\(folder)", various: true, explicit: false).tracks += inFolder
                }
            }
        }
        // Zusammenstellungen in benachbarten Ordnern (CD1/CD2) zusammenführen.
        let removed = mergeVariousByParent(order.map { candidates[$0]! })
        order.removeAll { removed.contains($0) }

        var result: [AlbumInfo] = []
        let ordered = order.map { candidates[$0]! }
        let variousCount = ordered.filter(\.various).count
        let localPrefix = "\(various)@"
        for c in ordered {
            for (yearSuffix, part) in splitByYear(c.tracks) {
                let aaPart: String
                if c.aaKey.hasPrefix(localPrefix) && variousCount > 1 {
                    aaPart = c.aaKey
                } else if c.aaKey.hasPrefix(localPrefix) {
                    aaPart = various
                } else {
                    aaPart = c.aaKey
                }
                var key = "a|\(titleKey)|\(aaPart)"
                if let yearSuffix { key += "|y\(yearSuffix)" }
                result.append(buildAlbum(key, part, c))
            }
        }
        return result
    }

    private static func primaryKey(_ t: Track) -> String {
        guard let primary = ArtistNames.primaries(t.artists).first else { return unknownArtist }
        return TextNorm.key(primary)
    }

    /// Ordner gelten als „dasselbe Album“, wenn sie gleich sind oder denselben Elternordner haben.
    static func sameAlbumFolder(_ a: String, _ b: String) -> Bool { a == b || parentOf(a) == parentOf(b) }

    static func parentOf(_ folder: String) -> String {
        let trimmed = folder.trimmingTrailingScalars { $0 == "/" }
        guard let i = trimmed.lastIndex(of: "/"), i != trimmed.startIndex else { return "" }
        return String(trimmed[..<i])
    }

    /// Liefert die Schlüssel der in andere Kandidaten aufgegangenen Kandidaten.
    private static func mergeVariousByParent(_ all: [Candidate]) -> Set<String> {
        let local = all.filter { $0.aaKey.hasPrefix("\(various)@") }
        if local.count < 2 { return [] }
        var merged = Set<String>()
        for i in local.indices {
            let a = local[i]
            if merged.contains(a.aaKey) { continue }
            for j in (i + 1)..<local.count {
                let b = local[j]
                if merged.contains(b.aaKey) { continue }
                let bFolders = b.folders
                let near = a.folders.contains { fa in bFolders.contains { fb in sameAlbumFolder(fa, fb) } }
                if near && yearsCompatible(a.tracks, b.tracks) {
                    a.tracks += b.tracks
                    merged.insert(b.aaKey)
                }
            }
        }
        return merged
    }

    private static func yearsCompatible(_ a: [Track], _ b: [Track]) -> Bool {
        let ya = Set(a.compactMap(\.year))
        let yb = Set(b.compactMap(\.year))
        return ya.isEmpty || yb.isEmpty || !ya.isDisjoint(with: yb)
    }

    /// Trennt nach Jahr, wenn die Jahrgänge in verschiedenen Ordnern liegen. Liefert (Jahr, Titel);
    /// Jahr ist `nil`, wenn nicht getrennt wurde.
    private static func splitByYear(_ tracks: [Track]) -> [(Int?, [Track])] {
        let years = Set(tracks.compactMap(\.year))
        if years.count < 2 { return [(nil, tracks)] }
        let byYear = OrderedGroups(tracks.filter { $0.year != nil }, by: { $0.year! })
        var folderSets: [Int: Set<String>] = [:]
        for (y, list) in byYear.groups { folderSets[y] = Set(list.map(\.folderKey)) }
        let years2 = byYear.keys
        for i in years2.indices {
            for j in (i + 1)..<years2.count where !folderSets[years2[i]]!.isDisjoint(with: folderSets[years2[j]]!) {
                return [(nil, tracks)] // gemischte Jahre im selben Ordner → ein Album
            }
        }
        // Titel ohne Jahr dem Jahrgang mit demselben Ordner zuordnen (sonst dem größten).
        var parts: [Int: [Track]] = [:]
        for (y, list) in byYear.groups { parts[y] = list }
        var largest = years2[0]
        for y in years2 where byYear[y]!.count > byYear[largest]!.count { largest = y }
        for t in tracks where t.year == nil {
            let target = years2.first { folderSets[$0]!.contains(t.folderKey) } ?? largest
            parts[target]!.append(t)
        }
        return parts.keys.sorted().map { ($0, parts[$0]!) }
    }

    private static func groupUnknown(_ tracks: [Track]) -> [AlbumInfo] {
        if tracks.isEmpty { return [] }
        return OrderedGroups(tracks, by: primaryKey).groups.map { artistKey, list in
            buildAlbum("u|\(artistKey)", list, Candidate(aaKey: artistKey, various: false, explicitArtist: false))
        }
    }

    private static func buildAlbum(_ key: String, _ tracks: [Track], _ c: Candidate) -> AlbumInfo {
        let ordered = orderTracks(tracks)
        let title = mostCommon(tracks.compactMap(\.album))
        let artist: String?
        if c.explicitArtist {
            // bei „Various Artists“ wie im Tag
            artist = mostCommon(tracks.compactMap(\.albumArtistText))
        } else if c.various {
            artist = nil
        } else {
            artist = mostCommon(tracks.compactMap { ArtistNames.primaries($0.artists).first })
        }
        let discs = Array(Set(tracks.compactMap(\.discNumber))).sorted()
        return AlbumInfo(
            key: key,
            title: title,
            artist: artist,
            isVarious: c.various,
            year: mostCommon(tracks.compactMap(\.year)),
            genre: mostCommon(tracks.flatMap(\.genres)),
            trackUids: ordered.map(\.uid),
            discNumbers: discs,
            totalDurationMs: tracks.reduce(0) { $0 + max($1.durationMs, 0) },
            sortTitle: mostCommon(tracks.compactMap(\.albumSort)) ?? title,
            sortArtist: mostCommon(tracks.compactMap(\.albumArtistSort)) ?? artist,
            dateAdded: tracks.reduce(0) { max($0, $1.dateAdded) }
        )
    }

    /// Reihenfolge innerhalb eines Albums: Disc → Track → (bei fehlenden Nummern) Ordner, Dateiname
    /// in natürlicher Reihenfolge, Titel, Kennung. Fehlt die Disc-Nummer, wird bei mehreren Ordnern
    /// die Ordner-Reihenfolge verwendet (CD1 vor CD2), ohne eine Disc-Nummer zu erfinden.
    public static func orderTracks(_ tracks: [Track]) -> [Track] {
        let natural = NaturalOrder.comparator()
        let folders = natural.sorted(tracks.map(\.folderKey).distinctInOrder())
        var folderRank: [String: Int] = [:]
        for (i, f) in folders.enumerated() { folderRank[f] = i + 1 }
        let multiFolder = folders.count > 1
        let ordering = Ordering<Track>.by { $0.discNumber ?? (multiFolder ? folderRank[$0.folderKey]! : 1) }
            .then(by: { $0.trackNumber ?? Int.max })
            .then { natural.compare($0.folderKey, $1.folderKey) }
            .then { natural.compare($0.fileName, $1.fileName) }
            .then { natural.compare($0.displayTitle, $1.displayTitle) }
            .then(by: { $0.uid })
        return ordering.sorted(tracks)
    }

    /// Häufigster Wert; bei Gleichstand der zuerst gesehene.
    public static func mostCommon<T: Hashable>(_ values: [T]) -> T? {
        var counter = OrderedCounter<T>()
        for v in values { counter.add(v) }
        return counter.mostCommon
    }
}
