import Foundation

/// Art einer automatisch gepflegten Playlist.
public enum SmartKind: String, Codable, Hashable, Sendable {
    case favorites = "FAVORITES"
    case mostPlayed = "MOST_PLAYED"
    case leastPlayed = "LEAST_PLAYED"
    case decade = "DECADE"
    // Seit v2 (hinten angefügt)
    case recentlyAdded = "RECENTLY_ADDED"
    case recentlyPlayed = "RECENTLY_PLAYED"
    case neverPlayed = "NEVER_PLAYED"
    case genre = "GENRE"
    case topRated = "TOP_RATED"
}

/// Automatisch gepflegte Playlist (vom System erzeugt, nicht bearbeitbar).
public struct SmartPlaylist: Hashable, Sendable, Identifiable {
    /// Stabile Kennung, z. B. „smart:favoriten“ oder „smart:decade:1980“.
    public var id: String
    public var kind: SmartKind
    public var name: String
    public var description: String
    public var trackUids: [Int64]
    public var decadeStart: Int?
    /// Genre-Schlüssel (wie `GenreInfo.key`) bei `.genre`.
    public var genreKey: String?

    public init(
        id: String, kind: SmartKind, name: String, description: String, trackUids: [Int64], decadeStart: Int? = nil,
        genreKey: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.description = description
        self.trackUids = trackUids
        self.decadeStart = decadeStart
        self.genreKey = genreKey
    }
}

/// Automatisch erzeugte Playlists (Portierung von `library/SmartPlaylists.kt`). Sie aktualisieren sich
/// von selbst, weil sie bei jeder Änderung von Bibliothek, Favoriten oder Statistik neu berechnet werden.
public enum SmartPlaylists {
    public static let favoritesID = "smart:favoriten"
    public static let mostPlayedID = "smart:meistgespielt"
    public static let leastPlayedID = "smart:wenigsten"
    public static let recentlyAddedID = "smart:neu"
    public static let recentlyPlayedID = "smart:zuletzt"
    public static let neverPlayedID = "smart:nie"
    public static let topRatedID = "smart:bewertet"
    /// Präfix der Genre-Playlists („smart:genre:rock“).
    public static let genrePrefix = "smart:genre:"
    public static let limit = 100

    /// Gültige Jahre für die Jahrzehnt-Zuordnung (außerhalb: als unbekannt behandelt).
    public static let plausibleYears = 1800...2100

    /// Favoriten-Playlist: alle favorisierten Titel, in der Reihenfolge, in der sie favorisiert wurden
    /// (älteste zuerst; bei gleichem Zeitpunkt nach Kennung). Nicht verfügbare Titel werden ausgelassen,
    /// bleiben aber Favorit.
    public static func favorites(_ favorites: [FavoriteTrack], available: [Int64: Track]) -> SmartPlaylist {
        let uids = Ordering<FavoriteTrack>.by(\.addedAt).then(by: \.trackUid).sorted(favorites)
            .map(\.trackUid)
            .filter { available[$0] != nil }
        return SmartPlaylist(id: favoritesID, kind: .favorites, name: "Favoriten", description: "Alle als Favorit markierten Titel", trackUids: uids)
    }

    /// Meistgespielt: Titel mit mindestens einer Wiedergabe, häufigste zuerst (höchstens `limit`).
    public static func mostPlayed(_ tracks: [Track], stats: [Int64: PlayStats], limit: Int = limit) -> SmartPlaylist {
        let natural = NaturalOrder.comparator()
        let ordering = Ordering<Track>.by { stats[$0.uid]?.playCount ?? 0 }.reversed
            .then(Ordering<Track>.by { stats[$0.uid]?.lastPlayedAt ?? 0 }.reversed)
            .then { natural.compare($0.displayTitle, $1.displayTitle) }
            .then(by: \.uid)
        let uids = ordering.sorted(tracks.filter { (stats[$0.uid]?.playCount ?? 0) > 0 })
            .prefix(max(limit, 0))
            .map(\.uid)
        return SmartPlaylist(
            id: mostPlayedID, kind: .mostPlayed, name: "Meistgespielt",
            description: "Die bis zu \(limit) am häufigsten gespielten Titel", trackUids: uids
        )
    }

    /// Am wenigsten gespielt: nie gespielte Titel zuerst, dann die mit den wenigsten Wiedergaben;
    /// bei Gleichstand die am längsten nicht gespielten, dann nach Name (höchstens `limit`).
    public static func leastPlayed(_ tracks: [Track], stats: [Int64: PlayStats], limit: Int = limit) -> SmartPlaylist {
        let natural = NaturalOrder.comparator()
        let ordering = Ordering<Track>.by { stats[$0.uid]?.playCount ?? 0 }
            .then(by: { stats[$0.uid]?.lastPlayedAt ?? 0 })
            .then { natural.compare($0.displayTitle, $1.displayTitle) }
            .then(by: \.uid)
        let uids = ordering.sorted(tracks).prefix(max(limit, 0)).map(\.uid)
        return SmartPlaylist(
            id: leastPlayedID, kind: .leastPlayed, name: "Am wenigsten gespielt",
            description: "Bis zu \(limit) Titel mit den wenigsten Wiedergaben – nie gespielte zuerst", trackUids: uids
        )
    }

    /// Jahrzehnte anhand des Veröffentlichungsjahres aus den Tags. Titel ohne (plausibles) Jahr
    /// werden keinem Jahrzehnt zugeordnet. Reihenfolge innerhalb: Jahr, dann Album, Disc, Track.
    public static func decades(_ tracks: [Track]) -> [SmartPlaylist] {
        let natural = NaturalOrder.comparator()
        let missingAlbum = "\u{FFFF}"
        let ordering = Ordering<Track>.by { $0.year ?? 0 }
            .then { natural.compare($0.album ?? missingAlbum, $1.album ?? missingAlbum) }
            .then(by: { $0.discNumber ?? 1 })
            .then(by: { $0.trackNumber ?? Int.max })
            .then { natural.compare($0.displayTitle, $1.displayTitle) }
            .then(by: \.uid)
        let groups = OrderedGroups(
            tracks.filter { $0.year.map(plausibleYears.contains) ?? false },
            by: { floorDiv($0.year!, 10) * 10 }
        )
        return groups.keys.sorted().map { start in
            SmartPlaylist(
                id: "smart:decade:\(start)",
                kind: .decade,
                name: decadeLabel(start),
                description: "Titel aus den Jahren \(start)–\(start + 9) (laut Tags)",
                trackUids: ordering.sorted(groups[start]!).map(\.uid),
                decadeStart: start
            )
        }
    }

    /// Reihenfolge wie im Album (Album – ohne Album zuletzt –, Disc, Track, Name, Kennung) über einmal
    /// berechnete Schlüssel (erst beim ersten Gleichstand); verglichen werden Indizes in `tracks`.
    /// Nur innerhalb eines Aufrufs verwendet.
    private final class AlbumOrderKeys {
        let tracks: [Track]
        let natural = NaturalOrder.comparator()
        private(set) lazy var albums: [Int] = Sorting.naturalRanks(tracks.map { $0.album ?? "\u{FFFF}" }).map { $0! }
        private(set) lazy var discs: [Int] = tracks.map { $0.discNumber ?? 1 }
        private(set) lazy var numbers: [Int] = tracks.map { $0.trackNumber ?? Int.max }

        init(_ tracks: [Track]) {
            self.tracks = tracks
        }

        func compare(_ a: Int, _ b: Int) -> Int {
            if albums[a] != albums[b] { return albums[a] < albums[b] ? -1 : 1 }
            if discs[a] != discs[b] { return discs[a] < discs[b] ? -1 : 1 }
            if numbers[a] != numbers[b] { return numbers[a] < numbers[b] ? -1 : 1 }
            return titleThenUid(a, b)
        }

        /// Name (natürliche Reihenfolge), dann Kennung.
        func titleThenUid(_ a: Int, _ b: Int) -> Int {
            let t = natural.compare(tracks[a].displayTitle, tracks[b].displayTitle)
            if t != 0 { return t }
            return tracks[a].uid == tracks[b].uid ? 0 : (tracks[a].uid < tracks[b].uid ? -1 : 1)
        }
    }

    /// Jüngste zuerst (`dateAdded`), gleichzeitig hinzugefügte in Albumreihenfolge.
    private static func newestFirst(_ tracks: [Track]) -> [Track] {
        let keys = AlbumOrderKeys(tracks)
        let added = tracks.map { $0.dateAdded }
        return stableSortedIndices(tracks.count) { a, b in
            if added[a] != added[b] { return added[a] > added[b] ? -1 : 1 }
            return keys.compare(a, b)
        }.map { tracks[$0] }
    }

    /// Zuletzt hinzugefügt: die jüngsten Titel zuerst (höchstens `limit`); gleichzeitig hinzugefügte in
    /// Albumreihenfolge. Titel ohne bekannten Zeitpunkt (0) fehlen.
    public static func recentlyAdded(_ tracks: [Track], limit: Int = limit) -> SmartPlaylist {
        let uids = newestFirst(tracks.filter { $0.dateAdded > 0 }).prefix(max(limit, 0)).map(\.uid)
        return SmartPlaylist(
            id: recentlyAddedID, kind: .recentlyAdded, name: "Zuletzt hinzugefügt",
            description: "Die bis zu \(limit) zuletzt hinzugefügten Titel", trackUids: uids
        )
    }

    /// Zuletzt gespielt: nach letzter gezählter Wiedergabe, jüngste zuerst (höchstens `limit`);
    /// bei Gleichstand häufiger gespielte, dann nach Name.
    public static func recentlyPlayed(_ tracks: [Track], stats: [Int64: PlayStats], limit: Int = limit) -> SmartPlaylist {
        var played: [Track] = []
        var last: [Int64] = []
        var counts: [Int] = []
        for t in tracks {
            guard let s = stats[t.uid], let at = s.lastPlayedAt else { continue }
            played.append(t)
            last.append(at)
            counts.append(s.playCount)
        }
        let keys = AlbumOrderKeys(played)
        let uids = stableSortedIndices(played.count) { a, b in
            if last[a] != last[b] { return last[a] > last[b] ? -1 : 1 }
            if counts[a] != counts[b] { return counts[a] > counts[b] ? -1 : 1 }
            return keys.titleThenUid(a, b)
        }.prefix(max(limit, 0)).map { played[$0].uid }
        return SmartPlaylist(
            id: recentlyPlayedID, kind: .recentlyPlayed, name: "Zuletzt gespielt",
            description: "Die bis zu \(limit) zuletzt gespielten Titel", trackUids: uids
        )
    }

    /// Nie gespielt: alle Titel ohne gezählte Wiedergabe – zuletzt hinzugefügte zuerst, sonst in
    /// Albumreihenfolge.
    public static func neverPlayed(_ tracks: [Track], stats: [Int64: PlayStats]) -> SmartPlaylist {
        let uids = newestFirst(tracks.filter { (stats[$0.uid]?.playCount ?? 0) <= 0 }).map(\.uid)
        return SmartPlaylist(
            id: neverPlayedID, kind: .neverPlayed, name: "Nie gespielt",
            description: "Titel, die noch nie gespielt wurden", trackUids: uids
        )
    }

    /// Am besten bewertet: Titel mit Bewertung ≥ `minRating` (0…100, 20 je Stern), höchste zuerst,
    /// bei Gleichstand nach Name.
    public static func topRated(_ tracks: [Track], minRating: Int = 80) -> SmartPlaylist {
        let threshold = max(minRating, 1) // „keine Bewertung“ nie aufnehmen
        let rated = tracks.filter { ($0.rating ?? 0) >= threshold }
        let ratings = rated.map { $0.rating ?? 0 }
        let keys = AlbumOrderKeys(rated)
        let uids = stableSortedIndices(rated.count) { a, b in
            if ratings[a] != ratings[b] { return ratings[a] > ratings[b] ? -1 : 1 }
            return keys.titleThenUid(a, b)
        }.map { rated[$0].uid }
        let description: String
        if threshold % 20 == 0 {
            let stars = threshold / 20
            description = stars == 1 ? "Titel mit mindestens 1 Stern" : "Titel mit mindestens \(stars) Sternen"
        } else {
            description = "Titel mit einer Bewertung ab \(threshold) von 100"
        }
        return SmartPlaylist(id: topRatedID, kind: .topRated, name: "Am besten bewertet", description: description, trackUids: uids)
    }

    /// Genre-Playlists: je (erstem) Genre eines Titels, gleiche Normalisierung wie `GenreIndex`
    /// (Schreibweise = häufigste). Titel ohne Genre gehören zu keiner. Nur Genres mit mindestens
    /// `minTracks` Titeln, die größten zuerst (bei Gleichstand nach Name), höchstens `maxPlaylists`.
    /// Reihenfolge innerhalb: Interpret (ohne Interpret zuletzt), Album, Disc, Track, Name.
    public static func byGenre(_ tracks: [Track], minTracks: Int = 10, maxPlaylists: Int = 12) -> [SmartPlaylist] {
        if maxPlaylists <= 0 { return [] }
        var groups = OrderedGroups<String, Track>()
        var spellings: [String: OrderedCounter<String>] = [:]
        var keyOf: [String: (clean: String, key: String)?] = [:] // gleiche Genre-Texte nur einmal normalisieren
        for t in tracks {
            var first: (clean: String, key: String)?
            for raw in t.genres {
                let entry: (clean: String, key: String)?
                if let cached = keyOf[raw] {
                    entry = cached
                } else {
                    let g = raw.kotlinTrimmed()
                    entry = g.isEmpty ? nil : (g, TextNorm.key(g))
                    keyOf[raw] = entry
                }
                if let entry {
                    first = entry
                    break
                }
            }
            guard let genre = first, !genre.key.isEmpty else { continue }
            groups.append(t, to: genre.key)
            spellings[genre.key, default: OrderedCounter()].add(genre.clean)
        }
        let needed = max(minTracks, 1)
        let candidates = groups.keys
            .filter { groups[$0]!.count >= needed }
            .map { (key: $0, name: spellings[$0]!.mostCommon!, count: groups[$0]!.count) }
        let nameKeys = candidates.map { NaturalKey($0.name) }
        let chosen = stableSortedIndices(candidates.count) { a, b in
            if candidates[a].count != candidates[b].count { return candidates[a].count > candidates[b].count ? -1 : 1 }
            let r = NaturalOrder.compare(nameKeys[a], nameKeys[b])
            return r != 0 ? r : candidates[a].key.javaCompare(candidates[b].key).signum()
        }.prefix(maxPlaylists).map { candidates[$0] }

        return chosen.map { c in
            let members = groups[c.key]!
            let keys = AlbumOrderKeys(members)
            let artists = Sorting.naturalRanks(members.map { $0.artistSort ?? $0.artistText ?? "\u{FFFF}" }).map { $0! }
            let ordered = stableSortedIndices(members.count) { a, b in
                if artists[a] != artists[b] { return artists[a] < artists[b] ? -1 : 1 }
                return keys.compare(a, b)
            }.map { members[$0].uid }
            return SmartPlaylist(
                id: genrePrefix + c.key,
                kind: .genre,
                name: "Genre: \(c.name)",
                description: "Titel im Genre „\(c.name)“",
                trackUids: ordered,
                genreKey: c.key
            )
        }
    }

    /// 1970 → „1970er“, 2000 → „2000er“.
    public static func decadeLabel(_ start: Int) -> String { "\(start)er" }

    private static func floorDiv(_ a: Int, _ b: Int) -> Int { a / b } // Jahre sind hier immer positiv
}
