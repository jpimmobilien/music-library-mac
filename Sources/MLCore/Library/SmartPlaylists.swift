import Foundation

/// Art einer automatisch gepflegten Playlist.
public enum SmartKind: String, Codable, Hashable, Sendable {
    case favorites = "FAVORITES"
    case mostPlayed = "MOST_PLAYED"
    case leastPlayed = "LEAST_PLAYED"
    case decade = "DECADE"
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

    public init(id: String, kind: SmartKind, name: String, description: String, trackUids: [Int64], decadeStart: Int? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.description = description
        self.trackUids = trackUids
        self.decadeStart = decadeStart
    }
}

/// Automatisch erzeugte Playlists (Portierung von `library/SmartPlaylists.kt`). Sie aktualisieren sich
/// von selbst, weil sie bei jeder Änderung von Bibliothek, Favoriten oder Statistik neu berechnet werden.
public enum SmartPlaylists {
    public static let favoritesID = "smart:favoriten"
    public static let mostPlayedID = "smart:meistgespielt"
    public static let leastPlayedID = "smart:wenigsten"
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

    /// 1970 → „1970er“, 2000 → „2000er“.
    public static func decadeLabel(_ start: Int) -> String { "\(start)er" }

    private static func floorDiv(_ a: Int, _ b: Int) -> Int { a / b } // Jahre sind hier immer positiv
}
