import Foundation

/// Sortierfeld mit Anzeigenamen; `defaultDescending` = übliche Richtung beim ersten Wählen.
///
/// `rawValue` ist der Kotlin-Name (z. B. „TITLE“) und wird so gespeichert.
public protocol SortField: CaseIterable, Hashable, Sendable, RawRepresentable where RawValue == String {
    var label: String { get }
    var ascendingLabel: String { get }
    var descendingLabel: String { get }
    var defaultDescending: Bool { get }
}

extension SortField {
    /// Gespeicherter Name wie in Kotlin (`Enum.name`).
    public var name: String { rawValue }
}

public enum TrackSort: String, SortField, Codable {
    case title = "TITLE"
    case duration = "DURATION"
    case lastPlayed = "LAST_PLAYED"
    case playCount = "PLAY_COUNT"
    case genre = "GENRE"
    case artist = "ARTIST"
    case year = "YEAR"
    // Seit v2 (hinten angefügt, gespeicherte Namen bleiben gültig)
    case album = "ALBUM"
    case albumArtist = "ALBUM_ARTIST"
    case dateAdded = "DATE_ADDED"
    case rating = "RATING"
    case bpm = "BPM"

    public var label: String {
        switch self {
        case .title: return "Name"
        case .duration: return "Dauer"
        case .lastPlayed: return "Zuletzt abgespielt"
        case .playCount: return "Am häufigsten abgespielt"
        case .genre: return "Genre"
        case .artist: return "Interpret"
        case .year: return "Veröffentlichungsjahr"
        case .album: return "Album"
        case .albumArtist: return "Albuminterpret"
        case .dateAdded: return "Hinzugefügt"
        case .rating: return "Bewertung"
        case .bpm: return "Tempo (BPM)"
        }
    }

    public var ascendingLabel: String {
        switch self {
        case .title, .genre, .artist, .album, .albumArtist: return "A–Z"
        case .duration: return "kürzeste zuerst"
        case .lastPlayed: return "am längsten her zuerst"
        case .playCount: return "seltenste zuerst"
        case .year, .dateAdded: return "älteste zuerst"
        case .rating: return "niedrigste zuerst"
        case .bpm: return "langsamste zuerst"
        }
    }

    public var descendingLabel: String {
        switch self {
        case .title, .genre, .artist, .album, .albumArtist: return "Z–A"
        case .duration: return "längste zuerst"
        case .lastPlayed: return "neueste zuerst"
        case .playCount: return "häufigste zuerst"
        case .year, .dateAdded: return "neueste zuerst"
        case .rating: return "höchste zuerst"
        case .bpm: return "schnellste zuerst"
        }
    }

    public var defaultDescending: Bool {
        switch self {
        case .lastPlayed, .playCount, .year, .dateAdded, .rating: return true
        default: return false
        }
    }
}

public enum AlbumSort: String, SortField, Codable {
    case title = "TITLE"
    case duration = "DURATION"
    case lastPlayed = "LAST_PLAYED"
    case playCount = "PLAY_COUNT"
    case genre = "GENRE"
    case artist = "ARTIST"
    case year = "YEAR"
    // Seit v2 (hinten angefügt)
    case dateAdded = "DATE_ADDED"
    case trackCount = "TRACK_COUNT"

    public var label: String {
        switch self {
        case .title: return "Albumname"
        case .duration: return "Gesamtdauer"
        case .lastPlayed: return "Zuletzt abgespielt"
        case .playCount: return "Am häufigsten abgespielt"
        case .genre: return "Genre"
        case .artist: return "Interpret / Album-Interpret"
        case .year: return "Veröffentlichungsjahr"
        case .dateAdded: return "Hinzugefügt"
        case .trackCount: return "Anzahl der Titel"
        }
    }

    public var ascendingLabel: String {
        switch self {
        case .title, .genre, .artist: return "A–Z"
        case .duration: return "kürzeste zuerst"
        case .lastPlayed: return "am längsten her zuerst"
        case .playCount: return "seltenste zuerst"
        case .year, .dateAdded: return "älteste zuerst"
        case .trackCount: return "wenigste zuerst"
        }
    }

    public var descendingLabel: String {
        switch self {
        case .title, .genre, .artist: return "Z–A"
        case .duration: return "längste zuerst"
        case .lastPlayed: return "neueste zuerst"
        case .playCount: return "häufigste zuerst"
        case .year, .dateAdded: return "neueste zuerst"
        case .trackCount: return "meiste zuerst"
        }
    }

    public var defaultDescending: Bool {
        switch self {
        case .lastPlayed, .playCount, .year, .dateAdded, .trackCount: return true
        default: return false
        }
    }
}

public enum PlaylistSort: String, SortField, Codable {
    case name = "NAME"
    case trackCount = "TRACK_COUNT"
    // Seit v2 (hinten angefügt)
    case created = "CREATED"
    case modified = "MODIFIED"

    public var label: String {
        switch self {
        case .name: return "Playlistname"
        case .trackCount: return "Anzahl der Titel"
        case .created: return "Erstellt"
        case .modified: return "Zuletzt geändert"
        }
    }

    public var ascendingLabel: String {
        switch self {
        case .name: return "A–Z"
        case .trackCount: return "wenigste zuerst"
        case .created, .modified: return "älteste zuerst"
        }
    }

    public var descendingLabel: String {
        switch self {
        case .name: return "Z–A"
        case .trackCount: return "meiste zuerst"
        case .created, .modified: return "neueste zuerst"
        }
    }

    public var defaultDescending: Bool { self != .name }
}

public enum ArtistSort: String, SortField, Codable {
    case name = "NAME"
    case trackCount = "TRACK_COUNT"
    // Seit v2 (hinten angefügt)
    case albumCount = "ALBUM_COUNT"

    public var label: String {
        switch self {
        case .name: return "Alphabetisch"
        case .trackCount: return "Anzahl der Titel"
        case .albumCount: return "Anzahl der Alben"
        }
    }

    public var ascendingLabel: String { self == .name ? "A–Z" : "wenigste zuerst" }
    public var descendingLabel: String { self == .name ? "Z–A" : "meiste zuerst" }
    public var defaultDescending: Bool { self != .name }
}

public enum GenreSort: String, SortField, Codable {
    case name = "NAME"
    case trackCount = "TRACK_COUNT"

    public var label: String { self == .name ? "Alphabetisch" : "Anzahl der Titel" }
    public var ascendingLabel: String { self == .name ? "A–Z" : "wenigste zuerst" }
    public var descendingLabel: String { self == .name ? "Z–A" : "meiste zuerst" }
    public var defaultDescending: Bool { self == .trackCount }
}

public enum FavoriteTrackSort: String, SortField, Codable {
    case title = "TITLE"
    case artist = "ARTIST"
    case album = "ALBUM"
    case added = "ADDED"
    // Seit v2 (hinten angefügt)
    case dateAdded = "DATE_ADDED"
    case rating = "RATING"

    public var label: String {
        switch self {
        case .title: return "Titel"
        case .artist: return "Interpret"
        case .album: return "Album"
        case .added: return "Zuletzt favorisiert"
        case .dateAdded: return "Zur Bibliothek hinzugefügt"
        case .rating: return "Bewertung"
        }
    }

    public var ascendingLabel: String {
        switch self {
        case .title, .artist, .album: return "A–Z"
        case .added, .dateAdded: return "älteste zuerst"
        case .rating: return "niedrigste zuerst"
        }
    }

    public var descendingLabel: String {
        switch self {
        case .title, .artist, .album: return "Z–A"
        case .added, .dateAdded: return "neueste zuerst"
        case .rating: return "höchste zuerst"
        }
    }

    public var defaultDescending: Bool {
        switch self {
        case .added, .dateAdded, .rating: return true
        case .title, .artist, .album: return false
        }
    }
}

public enum FavoriteAlbumSort: String, SortField, Codable {
    case title = "TITLE"
    case artist = "ARTIST"
    case added = "ADDED"

    public var label: String {
        switch self {
        case .title: return "Albumname"
        case .artist: return "Interpret"
        case .added: return "Zuletzt favorisiert"
        }
    }

    public var ascendingLabel: String { self == .added ? "älteste zuerst" : "A–Z" }
    public var descendingLabel: String { self == .added ? "neueste zuerst" : "Z–A" }
    public var defaultDescending: Bool { self == .added }
}

/// Sortierung eines Bereichs: Feld und Richtung.
///
/// Gespeichert (Codable) als Text „FELD:asc“ bzw. „FELD:desc“ – dasselbe Format wie die Android-App.
public struct Sort<F: SortField>: Hashable, Sendable, Codable {
    public var field: F
    public var descending: Bool

    public init(_ field: F, descending: Bool) {
        self.field = field
        self.descending = descending
    }

    /// Mit der üblichen Richtung des Feldes.
    public init(_ field: F) {
        self.init(field, descending: field.defaultDescending)
    }

    public var label: String { field.label + " · " + (descending ? field.descendingLabel : field.ascendingLabel) }

    /// „TITLE:asc“ / „YEAR:desc“.
    public var storageValue: String { field.rawValue + ":" + (descending ? "desc" : "asc") }

    /// Liest „FELD:richtung“; unbekanntes Feld → `nil`. Fehlt die Richtung, gilt aufsteigend (wie Kotlin).
    public init?(storageValue raw: String) {
        let parts = raw.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, let field = F(rawValue: String(first)) else { return nil }
        self.init(field, descending: parts.count > 1 && parts[1] == "desc")
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        guard let value = Sort(storageValue: raw) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unbekannte Sortierung: \(raw)")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(storageValue)
    }
}

/// Sortierung aller Bereiche (Portierung von `library/Sorting.kt`). Grundsätze:
/// - Fehlende Werte (kein Jahr, kein Genre, nie gespielt) stehen in BEIDEN Richtungen am Ende.
/// - Gleichstand: nach Name (natürliche deutsche Reihenfolge), dann nach Kennung – damit ist die
///   Reihenfolge immer stabil.
/// - Ist ein Sortier-Tag vorhanden (z. B. iTunes „Interpret sortieren“: „Beatles“), wird er verwendet.
public enum Sorting {

    // Für große Listen werden alle Sortierschlüssel (natürliche Reihenfolge) vorab je Eintrag berechnet;
    // verglichen werden dann nur noch die fertigen Schlüssel.

    /// Gleichstand-Schlüssel: Namen (natürliche Reihenfolge) nacheinander, dann Kennung.
    struct Tie {
        var names: [NaturalKey]
        var number: Int64 = 0
        var text: String = ""

        static func compare(_ a: Tie, _ b: Tie) -> Int {
            for (x, y) in zip(a.names, b.names) {
                let r = NaturalOrder.compare(x, y)
                if r != 0 { return r }
            }
            if a.number != b.number { return a.number < b.number ? -1 : 1 }
            return a.text.javaCompare(b.text).signum()
        }
    }

    private static func byTie<T>(_ items: [T], descending: Bool, tie: (T) -> Tie) -> [T] {
        let ties = items.map(tie)
        let sign = descending ? -1 : 1
        return stableSortedIndices(items.count) { sign * Tie.compare(ties[$0], ties[$1]) }.map { items[$0] }
    }

    private static func nullsLast<T, K: Comparable>(
        _ items: [T], descending: Bool, key: (T) -> K?, tie: (T) -> Tie
    ) -> [T] {
        let keys = items.map(key)
        let ties = items.map(tie)
        let present = items.indices.filter { keys[$0] != nil }
        let missing = items.indices.filter { keys[$0] == nil }
        let sign = descending ? -1 : 1
        let p = stableSortedIndices(present.count) { a, b in
            let ka = keys[present[a]]!, kb = keys[present[b]]!
            if ka != kb { return ka < kb ? -sign : sign }
            return Tie.compare(ties[present[a]], ties[present[b]])
        }
        let m = stableSortedIndices(missing.count) { Tie.compare(ties[missing[$0]], ties[missing[$1]]) }
        return p.map { items[present[$0]] } + m.map { items[missing[$0]] }
    }

    private static func byText<T>(
        _ items: [T], descending: Bool, text: (T) -> String?, tie: (T) -> Tie
    ) -> [T] {
        let keys: [NaturalKey?] = items.map { item in
            guard let t = text(item), !t.isKotlinBlank else { return nil }
            return NaturalKey(t)
        }
        let ties = items.map(tie)
        let present = items.indices.filter { keys[$0] != nil }
        let missing = items.indices.filter { keys[$0] == nil }
        let sign = descending ? -1 : 1
        let p = stableSortedIndices(present.count) { a, b in
            let r = NaturalOrder.compare(keys[present[a]]!, keys[present[b]]!)
            if r != 0 { return sign * r }
            return Tie.compare(ties[present[a]], ties[present[b]])
        }
        let m = stableSortedIndices(missing.count) { Tie.compare(ties[missing[$0]], ties[missing[$1]]) }
        return p.map { items[present[$0]] } + m.map { items[missing[$0]] }
    }

    static func trackTie(_ t: Track) -> Tie { Tie(names: [NaturalKey(t.titleSort ?? t.displayTitle)], number: t.uid) }

    /// Rang je Text in natürlicher Reihenfolge (gleiche Texte → gleicher Rang, `nil` bleibt `nil`).
    /// Jeder verschiedene Text wird nur einmal zerlegt und einmal einsortiert – danach werden nur noch
    /// Zahlen verglichen (Alben, Interpreten wiederholen sich ständig).
    static func naturalRanks(_ texts: [String?]) -> [Int?] {
        var distinct: [String] = []
        var slot: [String: Int] = [:]
        let slots: [Int?] = texts.map { text in
            guard let text else { return nil }
            if let i = slot[text] { return i }
            slot[text] = distinct.count
            distinct.append(text)
            return distinct.count - 1
        }
        let keys = distinct.map { NaturalKey($0) }
        var rankOfSlot = [Int](repeating: 0, count: distinct.count)
        for (rank, i) in stableSortedIndices(distinct.count, { NaturalOrder.compare(keys[$0], keys[$1]) }).enumerated() {
            rankOfSlot[i] = rank
        }
        return slots.map { $0.map { rankOfSlot[$0] } }
    }

    /// Titel nach einem Gruppentext (Album bzw. Album-Interpret; fehlend in beiden Richtungen am Ende),
    /// innerhalb der Gruppe immer aufsteigend nach `lead` (Album-Interpret bzw. Album), Disc, Track,
    /// Name und Kennung – so stehen die Titel eines Albums in Albumreihenfolge.
    private static func tracksInGroupOrder(
        _ items: [Track], descending: Bool, group: (Track) -> String?, lead: (Track) -> String
    ) -> [Track] {
        let groupRank = naturalRanks(items.map { t in group(t).flatMap { $0.isKotlinBlank ? nil : $0 } })
        let leadRank = naturalRanks(items.map { lead($0) }).map { $0! }
        let discs = items.map { $0.discNumber ?? 1 }
        let numbers = items.map { $0.trackNumber ?? Int.max }
        let natural = NaturalOrder.comparator()
        func tie(_ a: Int, _ b: Int) -> Int {
            if leadRank[a] != leadRank[b] { return leadRank[a] < leadRank[b] ? -1 : 1 }
            if discs[a] != discs[b] { return discs[a] < discs[b] ? -1 : 1 }
            if numbers[a] != numbers[b] { return numbers[a] < numbers[b] ? -1 : 1 }
            let r = natural.compare(items[a].titleSort ?? items[a].displayTitle, items[b].titleSort ?? items[b].displayTitle)
            if r != 0 { return r }
            return items[a].uid == items[b].uid ? 0 : (items[a].uid < items[b].uid ? -1 : 1)
        }
        let present = items.indices.filter { groupRank[$0] != nil }
        let missing = items.indices.filter { groupRank[$0] == nil }
        let sign = descending ? -1 : 1
        let p = stableSortedIndices(present.count) { a, b in
            let ra = groupRank[present[a]]!, rb = groupRank[present[b]]!
            if ra != rb { return ra < rb ? -sign : sign }
            return tie(present[a], present[b])
        }
        let m = stableSortedIndices(missing.count) { tie(missing[$0], missing[$1]) }
        return p.map { items[present[$0]] } + m.map { items[missing[$0]] }
    }

    private static func nonBlank(_ text: String?) -> String? {
        guard let text, !text.isKotlinBlank else { return nil }
        return text
    }

    /// Albumname zum Sortieren eines Titels: Sortier-Tag oder Album-Tag.
    static func trackAlbumName(_ t: Track) -> String? { nonBlank(t.albumSort) ?? t.album }

    /// Album-Interpret zum Sortieren eines Titels: Sortier-Tag, Album-Interpret, sonst (wie iTunes)
    /// der Interpret des Titels.
    static func trackAlbumArtistName(_ t: Track) -> String? {
        nonBlank(t.albumArtistSort) ?? nonBlank(t.albumArtistText) ?? nonBlank(t.artistSort) ?? t.artistText
    }

    /// Nur positive Werte gelten als vorhanden (0 = unbekannt, z. B. Bewertung, BPM, Hinzugefügt).
    @inline(__always)
    static func positive<N: BinaryInteger>(_ value: N?) -> N? {
        guard let value, value > 0 else { return nil }
        return value
    }

    static func albumTie(_ a: AlbumInfo) -> Tie {
        Tie(names: [NaturalKey(a.sortTitle ?? a.title ?? "\u{FFFF}"), NaturalKey(a.sortArtist ?? a.artist ?? "")], text: a.key)
    }

    /// Name (Sortier-Tag oder angezeigter Titel), dann Kennung.
    public static func trackNameOrder() -> Ordering<Track> {
        let natural = NaturalOrder.comparator()
        return Ordering<Track> { natural.compare($0.titleSort ?? $0.displayTitle, $1.titleSort ?? $1.displayTitle) }
            .then(by: \.uid)
    }

    public static func tracks(_ items: [Track], sort: Sort<TrackSort>, stats: [Int64: PlayStats]) -> [Track] {
        let tie = trackTie
        let d = sort.descending
        switch sort.field {
        case .title: return byTie(items, descending: d, tie: tie)
        case .duration: return nullsLast(items, descending: d, key: { $0.durationMs > 0 ? $0.durationMs : nil }, tie: tie)
        case .lastPlayed: return nullsLast(items, descending: d, key: { stats[$0.uid]?.lastPlayedAt }, tie: tie)
        case .playCount: return nullsLast(items, descending: d, key: { stats[$0.uid]?.playCount ?? 0 }, tie: tie)
        case .genre: return byText(items, descending: d, text: { $0.genres.first }, tie: tie)
        case .artist: return byText(items, descending: d, text: { $0.artistSort ?? $0.artistText }, tie: tie)
        case .year: return nullsLast(items, descending: d, key: { $0.year }, tie: tie)
        case .album:
            return tracksInGroupOrder(items, descending: d, group: trackAlbumName,
                                      lead: { nonBlank($0.albumArtistSort) ?? $0.albumArtistText ?? "" })
        case .albumArtist:
            return tracksInGroupOrder(items, descending: d, group: trackAlbumArtistName,
                                      lead: { nonBlank($0.albumSort) ?? nonBlank($0.album) ?? "\u{FFFF}" })
        case .dateAdded: return nullsLast(items, descending: d, key: { positive($0.dateAdded) }, tie: tie)
        case .rating: return nullsLast(items, descending: d, key: { positive($0.rating) }, tie: tie)
        case .bpm: return nullsLast(items, descending: d, key: { positive($0.bpm) }, tie: tie)
        }
    }

    /// Album-Statistik aus den Titeln: letzte Wiedergabe = jüngste.
    public static func albumLastPlayed(_ album: AlbumInfo, stats: [Int64: PlayStats]) -> Int64? {
        album.trackUids.compactMap { stats[$0]?.lastPlayedAt }.max()
    }

    /// Album-Statistik aus den Titeln: Anzahl = Summe aller Titel.
    public static func albumPlayCount(_ album: AlbumInfo, stats: [Int64: PlayStats]) -> Int {
        album.trackUids.reduce(0) { $0 + (stats[$1]?.playCount ?? 0) }
    }

    /// Albumname (Sortier-Tag oder Titel; unbekannt zuletzt), dann Interpret, dann Schlüssel.
    public static func albumNameOrder() -> Ordering<AlbumInfo> {
        let natural = NaturalOrder.comparator()
        let missing = "\u{FFFF}"
        return Ordering<AlbumInfo> { natural.compare($0.sortTitle ?? $0.title ?? missing, $1.sortTitle ?? $1.title ?? missing) }
            .then { natural.compare($0.sortArtist ?? $0.artist ?? "", $1.sortArtist ?? $1.artist ?? "") }
            .then { $0.key.javaCompare($1.key).signum() }
    }

    public static func albums(_ items: [AlbumInfo], sort: Sort<AlbumSort>, stats: [Int64: PlayStats]) -> [AlbumInfo] {
        let tie = albumTie
        let d = sort.descending
        switch sort.field {
        case .title:
            // Unbekannte Alben immer am Ende
            let known = items.filter { !$0.isUnknown }
            let unknown = items.filter(\.isUnknown)
            return byTie(known, descending: d, tie: tie) + byTie(unknown, descending: false, tie: tie)
        case .duration: return nullsLast(items, descending: d, key: { $0.totalDurationMs > 0 ? $0.totalDurationMs : nil }, tie: tie)
        case .lastPlayed: return nullsLast(items, descending: d, key: { albumLastPlayed($0, stats: stats) }, tie: tie)
        case .playCount: return nullsLast(items, descending: d, key: { albumPlayCount($0, stats: stats) }, tie: tie)
        case .genre: return byText(items, descending: d, text: { $0.genre }, tie: tie)
        case .artist:
            return byText(items, descending: d, text: { $0.sortArtist ?? $0.artist ?? ($0.isVarious ? "Verschiedene Interpreten" : nil) }, tie: tie)
        case .year: return nullsLast(items, descending: d, key: { $0.year }, tie: tie)
        case .dateAdded: return nullsLast(items, descending: d, key: { positive($0.dateAdded) }, tie: tie)
        case .trackCount: return nullsLast(items, descending: d, key: { $0.trackCount }, tie: tie)
        }
    }

    public static func artists(_ items: [ArtistInfo], sort: Sort<ArtistSort>) -> [ArtistInfo] {
        let tie: (ArtistInfo) -> Tie = { Tie(names: [NaturalKey($0.sortName)], text: $0.key) }
        switch sort.field {
        case .name: return byTie(items, descending: sort.descending, tie: tie)
        case .trackCount: return nullsLast(items, descending: sort.descending, key: { $0.trackCount }, tie: tie)
        case .albumCount: return nullsLast(items, descending: sort.descending, key: { $0.albumCount }, tie: tie)
        }
    }

    public static func genres(_ items: [GenreInfo], sort: Sort<GenreSort>) -> [GenreInfo] {
        let tie: (GenreInfo) -> Tie = { Tie(names: [NaturalKey($0.name)], text: $0.key) }
        let known = items.filter { !$0.isUnknown }
        let unknown = items.filter(\.isUnknown)
        let sorted: [GenreInfo]
        switch sort.field {
        case .name: sorted = byTie(known, descending: sort.descending, tie: tie)
        case .trackCount: sorted = nullsLast(known, descending: sort.descending, key: { $0.trackCount }, tie: tie)
        }
        // „Unbekanntes Genre“ steht immer am Ende.
        return sorted + unknown
    }

    /// Playlists: nach Name, Anzahl, Erstellungs- bzw. Änderungszeitpunkt (bei Gleichstand nach Name,
    /// gleiche Namen behalten ihre Reihenfolge). Zeitpunkte ≤ 0 gelten als unbekannt und stehen am Ende.
    public static func playlists<T>(
        _ items: [T], sort: Sort<PlaylistSort>, name: (T) -> String, count: (T) -> Int,
        created: (T) -> Int64 = { _ in 0 }, modified: (T) -> Int64 = { _ in 0 }
    ) -> [T] {
        let tie: (T) -> Tie = { Tie(names: [NaturalKey(name($0))]) }
        switch sort.field {
        case .name: return byTie(items, descending: sort.descending, tie: tie)
        case .trackCount: return nullsLast(items, descending: sort.descending, key: { count($0) }, tie: tie)
        case .created: return nullsLast(items, descending: sort.descending, key: { positive(created($0)) }, tie: tie)
        case .modified: return nullsLast(items, descending: sort.descending, key: { positive(modified($0)) }, tie: tie)
        }
    }

    public static func favoriteTracks(_ items: [Track], sort: Sort<FavoriteTrackSort>, addedAt: [Int64: Int64]) -> [Track] {
        let tie = trackTie
        let d = sort.descending
        switch sort.field {
        case .title: return byTie(items, descending: d, tie: tie)
        case .artist: return byText(items, descending: d, text: { $0.artistSort ?? $0.artistText }, tie: tie)
        case .album: return byText(items, descending: d, text: { $0.albumSort ?? $0.album }, tie: tie)
        case .added: return nullsLast(items, descending: d, key: { addedAt[$0.uid] }, tie: tie)
        case .dateAdded: return nullsLast(items, descending: d, key: { positive($0.dateAdded) }, tie: tie)
        case .rating: return nullsLast(items, descending: d, key: { positive($0.rating) }, tie: tie)
        }
    }

    public static func favoriteAlbums(_ items: [AlbumInfo], sort: Sort<FavoriteAlbumSort>, favorites: [String: FavoriteAlbum]) -> [AlbumInfo] {
        let tie = albumTie
        let d = sort.descending
        switch sort.field {
        case .title: return byTie(items, descending: d, tie: tie)
        case .artist: return byText(items, descending: d, text: { $0.sortArtist ?? $0.artist }, tie: tie)
        case .added: return nullsLast(items, descending: d, key: { favorites[$0.key]?.addedAt }, tie: tie)
        }
    }
}
