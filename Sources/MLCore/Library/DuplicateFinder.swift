import Foundation

/// Eine Gruppe wahrscheinlich doppelter Titel.
public struct DuplicateGroup: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Codable, Sendable {
        /// Gleiche Dateigröße und Dauer: Kopie derselben Datei.
        case identicalCopy
        /// Gleicher Titel, gleicher Hauptinterpret, fast gleiche Dauer (z. B. anderes Format/andere Quelle).
        case sameSong
    }

    public var kind: Kind
    /// Titel der Gruppe: der vorgeschlagene zuerst, dann nach Vorzug.
    public var trackUids: [Int64]
    /// Vorgeschlagen zum Behalten.
    public var keepUid: Int64

    public init(kind: Kind, trackUids: [Int64], keepUid: Int64) {
        self.kind = kind
        self.trackUids = trackUids
        self.keepUid = keepUid
    }

    /// Stabile Kennung (aus den sortierten Kennungen).
    public var id: String { "dup:" + trackUids.sorted().map(String.init).joined(separator: ",") }

    /// Die übrigen Titel (Kandidaten zum Entfernen).
    public var others: [Int64] { trackUids.filter { $0 != keepUid } }

    public var reason: String {
        switch kind {
        case .identicalCopy: return "Identische Kopie (gleiche Dateigröße und Dauer)"
        case .sameSong: return "Gleicher Titel und Interpret, fast gleiche Dauer"
        }
    }
}

/// Findet wahrscheinlich doppelte Titel (neu gegenüber Android).
///
/// Zwei Kriterien:
/// - **Gleiches Lied**: gleicher normalisierter Titel (`TextNorm.key`), gleicher Hauptinterpret
///   (`ArtistNames.primaries`, normalisiert) und Dauerunterschied ≤ 2 s (wahlweise zusätzlich gleiches
///   Album). Titel ohne Titel-Tag werden nur über den Dateinamen (ohne Endung) verglichen – sie passen
///   also nur zu Titeln mit gleichem Dateinamen.
/// - **Identische Kopie**: gleiche Dateigröße (> 0) und gleiche Dauer (± 1 s).
///
/// Innerhalb eines Schlüssels wird nach Dauer geordnet und von der kürzesten aus gruppiert: alle Titel
/// einer Gruppe liegen höchstens die Toleranz von deren erstem Titel entfernt (keine Ketten über mehrere
/// Sekunden). Titel aus beiden Kriterien werden zu einer Gruppe verbunden; jeder Titel steht in höchstens
/// einer Gruppe. Die Gruppe ist eine „identische Kopie“, wenn alle Titel gleich groß und gleich lang sind.
///
/// Vorschlag zum Behalten: verlustfrei > höhere Bitrate > mit Cover > mehr ausgefüllte Tags >
/// früher hinzugefügt > kleinere Kennung.
public enum DuplicateFinder {

    public struct Options: Hashable, Sendable {
        /// Größter Dauerunterschied für „gleiches Lied“.
        public var durationToleranceMs: Int64 = 2_000
        /// Größter Dauerunterschied für „identische Kopie“.
        public var identicalDurationToleranceMs: Int64 = 1_000
        /// Zusätzlich gleiches Album verlangen.
        public var requireSameAlbum = false
        /// Auch nicht verfügbare Titel (z. B. Laufwerk getrennt) einbeziehen.
        public var includeUnavailable = false

        public init(durationToleranceMs: Int64 = 2_000, identicalDurationToleranceMs: Int64 = 1_000, requireSameAlbum: Bool = false, includeUnavailable: Bool = false) {
            self.durationToleranceMs = durationToleranceMs
            self.identicalDurationToleranceMs = identicalDurationToleranceMs
            self.requireSameAlbum = requireSameAlbum
            self.includeUnavailable = includeUnavailable
        }
    }

    public static func find(_ tracks: [Track], options: Options = Options()) -> [DuplicateGroup] {
        let candidates = options.includeUnavailable ? tracks : tracks.filter(\.available)
        // Doppelte Kennungen (sollte nie vorkommen) nur einmal betrachten.
        var seenUids = Set<Int64>()
        let list = candidates.filter { seenUids.insert($0.uid).inserted }
        guard list.count > 1 else { return [] }

        var union = UnionFind(count: list.count)

        // 1. Gleiches Lied
        var bySong: [String: [Int]] = [:]
        for (i, t) in list.enumerated() {
            bySong[songKey(t, requireSameAlbum: options.requireSameAlbum), default: []].append(i)
        }
        for (_, members) in bySong where members.count > 1 {
            for cluster in clusters(members, list, tolerance: options.durationToleranceMs) {
                for m in cluster.dropFirst() { union.union(cluster[0], m) }
            }
        }
        // 2. Identische Kopie
        var bySize: [Int64: [Int]] = [:]
        for (i, t) in list.enumerated() where t.sizeBytes > 0 { bySize[t.sizeBytes, default: []].append(i) }
        for (_, members) in bySize where members.count > 1 {
            for cluster in clusters(members, list, tolerance: options.identicalDurationToleranceMs) {
                for m in cluster.dropFirst() {
                    union.union(cluster[0], m)
                }
            }
        }

        // Gruppen bilden
        var groups: [Int: [Int]] = [:]
        for i in list.indices { groups[union.find(i), default: []].append(i) }
        var result: [DuplicateGroup] = []
        for (_, members) in groups where members.count > 1 {
            let tracksInGroup = members.map { list[$0] }
            let ordered = preferredOrder(tracksInGroup)
            let identical = tracksInGroup.allSatisfy { $0.sizeBytes == tracksInGroup[0].sizeBytes && $0.sizeBytes > 0 }
                && (tracksInGroup.map(\.durationMs).max()! - tracksInGroup.map(\.durationMs).min()!) <= options.identicalDurationToleranceMs
            result.append(DuplicateGroup(
                kind: identical ? .identicalCopy : .sameSong,
                trackUids: ordered.map(\.uid),
                keepUid: ordered[0].uid
            ))
        }
        // Stabile Reihenfolge: nach Titel des behaltenen Titels, dann Kennung.
        let natural = NaturalOrder.comparator()
        let byUid = Dictionary(list.map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
        return Ordering<DuplicateGroup> { natural.compare(byUid[$0.keepUid]!.displayTitle, byUid[$1.keepUid]!.displayTitle) }
            .then(by: \.id)
            .sorted(result)
    }

    /// Vergleichsschlüssel „gleiches Lied“.
    static func songKey(_ t: Track, requireSameAlbum: Bool) -> String {
        let title: String
        if let tagTitle = t.title, !TextNorm.key(tagTitle).isEmpty {
            title = "t|" + TextNorm.key(tagTitle)
        } else {
            // Ohne Titel-Tag nur über den Dateinamen (passt dann nur zu gleichem Dateinamen).
            title = "f|" + TextNorm.key(Track.fileNameWithoutExtension(t.fileName))
        }
        let artist = ArtistNames.primaries(t.artists).first.map(TextNorm.key) ?? ""
        var key = title + "\u{1}" + artist
        if requireSameAlbum { key += "\u{1}" + TextNorm.key(t.album) }
        return key
    }

    /// Nach Dauer geordnet; jede Gruppe beginnt mit ihrem kürzesten Titel und enthält alle Titel bis
    /// höchstens `tolerance` länger. Nur Gruppen mit mindestens zwei Titeln.
    private static func clusters(_ members: [Int], _ list: [Track], tolerance: Int64) -> [[Int]] {
        let sorted = members.sorted { list[$0].durationMs != list[$1].durationMs ? list[$0].durationMs < list[$1].durationMs : list[$0].uid < list[$1].uid }
        var result: [[Int]] = []
        var current: [Int] = []
        for i in sorted {
            if let anchor = current.first, list[i].durationMs - list[anchor].durationMs <= tolerance {
                current.append(i)
            } else {
                if current.count > 1 { result.append(current) }
                current = [i]
            }
        }
        if current.count > 1 { result.append(current) }
        return result
    }

    // MARK: - Vorzug

    static let losslessCodecs: Set<String> = ["flac", "alac", "pcm", "wav", "aiff", "aif", "ape", "monkey's audio", "wavpack", "wv", "tta", "true audio", "dsd", "dsf", "dff", "shorten", "lpcm"]
    static let losslessExtensions: Set<String> = ["flac", "wav", "aif", "aiff", "aifc", "ape", "wv", "tta", "dsf", "dff", "shn"]

    /// Verlustfreies Format? (Codec, sonst eindeutige Dateiendung; `.m4a` nur mit Codec ALAC)
    public static func isLossless(_ t: Track) -> Bool {
        if let codec = t.codec?.lowercased(), !codec.isEmpty {
            if losslessCodecs.contains(codec) { return true }
            if codec.hasPrefix("pcm") || codec.contains("lossless") { return true }
            return false
        }
        return losslessExtensions.contains(t.fileExtension)
    }

    /// Anzahl ausgefüllter Tag-Felder (für den Vorzug).
    public static func filledTagCount(_ t: Track) -> Int {
        var n = 0
        let texts: [String?] = [t.title, t.album, t.grouping, t.comment, t.titleSort, t.artistSort, t.albumSort, t.albumArtistSort, t.composerSort]
        for s in texts { if let s, !s.isKotlinBlank { n += 1 } }
        let numbers: [Int?] = [t.year, t.trackNumber, t.trackTotal, t.discNumber, t.discTotal, t.bpm, t.rating]
        n += numbers.filter { $0 != nil }.count
        for list in [t.artists, t.albumArtists, t.genres, t.composers] where !list.isEmpty { n += 1 }
        if t.hasLyrics { n += 1 }
        return n
    }

    /// Reihenfolge des Vorzugs (der erste wird zum Behalten vorgeschlagen).
    public static func preferredOrder(_ tracks: [Track]) -> [Track] {
        let ordering = Ordering<Track>.by { isLossless($0) ? 0 : 1 }
            .then(Ordering<Track>.by(\.bitrate).reversed)
            .then(by: { $0.hasPicture ? 0 : 1 })
            .then(Ordering<Track>.by(filledTagCount).reversed)
            .then(by: { $0.dateAdded > 0 ? $0.dateAdded : Int64.max }) // unbekannt = zuletzt
            .then(by: \.uid)
        return ordering.sorted(tracks)
    }
}

/// Union-Find (Disjunkte Mengen) mit Pfadkompression.
private struct UnionFind {
    private var parent: [Int]

    init(count: Int) { parent = Array(0..<count) }

    mutating func find(_ x: Int) -> Int {
        var root = x
        while parent[root] != root { root = parent[root] }
        var node = x
        while parent[node] != root {
            let next = parent[node]
            parent[node] = root
            node = next
        }
        return root
    }

    mutating func union(_ a: Int, _ b: Int) {
        let ra = find(a), rb = find(b)
        if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
    }
}
