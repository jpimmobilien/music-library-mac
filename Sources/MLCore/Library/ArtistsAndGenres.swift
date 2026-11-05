import Foundation

/// Ein Interpret der Übersicht.
public struct ArtistInfo: Hashable, Sendable, Identifiable {
    public var key: String
    /// Häufigste Schreibweise aus den Tags.
    public var name: String
    public var sortName: String
    /// Titel, an denen der Interpret beteiligt ist (Interpret, Gast oder Album-Interpret).
    public var trackUids: [Int64]
    /// Alben, deren Album-Interpret er ist bzw. auf denen er vorkommt.
    public var albumKeys: [String]

    public var trackCount: Int { trackUids.count }
    /// Anzahl der Alben (= `albumKeys.count`).
    public var albumCount: Int { albumKeys.count }
    public var id: String { key }

    public init(key: String, name: String, sortName: String, trackUids: [Int64], albumKeys: [String]) {
        self.key = key
        self.name = name
        self.sortName = sortName
        self.trackUids = trackUids
        self.albumKeys = albumKeys
    }
}

/// Ein Genre der Übersicht.
public struct GenreInfo: Hashable, Sendable, Identifiable {
    public var key: String
    public var name: String
    public var trackUids: [Int64]
    public var category: GenreCategory
    /// Sammelkategorie für Titel ohne Genre-Angabe (klar gekennzeichnet, nichts erfunden).
    public var isUnknown: Bool

    public var trackCount: Int { trackUids.count }
    public var id: String { key }

    public init(key: String, name: String, trackUids: [Int64], category: GenreCategory, isUnknown: Bool = false) {
        self.key = key
        self.name = name
        self.trackUids = trackUids
        self.category = category
        self.isUnknown = isUnknown
    }
}

/// Interpreten-Übersicht (Portierung von `ArtistIndex` aus `library/ArtistsAndGenres.kt`).
public enum ArtistIndex {

    /// Ordnet jeden Titel seinen Haupt-Interpreten, Gästen („feat.“) und dem Album-Interpreten zu.
    /// Gleiche Namen in anderer Schreibweise („queen“/„Queen“) ergeben einen Eintrag.
    /// Sammel-Bezeichnungen wie „Various Artists“ werden nicht als Interpret geführt.
    public static func build(_ tracks: [Track], albumKeyByTrack: [Int64: String]) -> [ArtistInfo] {
        struct Acc {
            var spellings = OrderedCounter<String>()
            var sortNames = OrderedCounter<String>()
            var tracks = OrderedSet<Int64>()
            var albums = OrderedSet<String>()
        }
        var order: [String] = []
        var acc: [String: Acc] = [:]

        func add(_ name: String, _ sortName: String?, _ t: Track) {
            let clean = name.kotlinTrimmed()
            if clean.isEmpty || ArtistNames.isVarious(clean) { return }
            let key = TextNorm.key(clean)
            if key.isEmpty { return }
            if acc[key] == nil {
                order.append(key)
                acc[key] = Acc()
            }
            acc[key]!.spellings.add(clean)
            if let sortName, !sortName.isKotlinBlank { acc[key]!.sortNames.add(sortName) }
            acc[key]!.tracks.insert(t.uid)
            if let album = albumKeyByTrack[t.uid] { acc[key]!.albums.insert(album) }
        }

        for t in tracks {
            let primaries = ArtistNames.primaries(t.artists)
            for (i, p) in primaries.enumerated() {
                add(p, (i == 0 && primaries.count == 1) ? t.artistSort : nil, t)
            }
            for g in ArtistNames.guests(t.artists) { add(g, nil, t) }
            for aa in t.albumArtists { add(aa, t.albumArtistSort, t) }
        }
        return order.map { key in
            let a = acc[key]!
            let name = a.spellings.mostCommon!
            return ArtistInfo(
                key: key,
                name: name,
                sortName: a.sortNames.mostCommon ?? name,
                trackUids: a.tracks.elements,
                albumKeys: a.albums.elements
            )
        }
    }
}

/// Genre-Übersicht (Portierung von `GenreIndex`).
public enum GenreIndex {
    public static let unknownKey = "#unbekannt"
    public static let unknownName = "Unbekanntes Genre"

    /// Gruppiert nach den Genre-Tags (ein Titel mit „Rock; Pop“ erscheint in beiden Genres).
    /// Titel ohne Genre landen – klar gekennzeichnet – in „Unbekanntes Genre“; es wird kein Genre geraten.
    public static func build(_ tracks: [Track]) -> [GenreInfo] {
        var spellings: [String: OrderedCounter<String>] = [:]
        var members: [String: OrderedSet<Int64>] = [:]
        var order: [String] = []
        var unknown: [Int64] = []
        for t in tracks {
            let genres = t.genres.map { $0.kotlinTrimmed() }.filter { !$0.isEmpty }
            if genres.isEmpty {
                unknown.append(t.uid)
                continue
            }
            for g in genres {
                let key = TextNorm.key(g)
                if key.isEmpty { continue }
                if members[key] == nil {
                    order.append(key)
                    members[key] = OrderedSet()
                    spellings[key] = OrderedCounter()
                }
                spellings[key]!.add(g)
                members[key]!.insert(t.uid)
            }
        }
        var result = order.map { key -> GenreInfo in
            let name = spellings[key]!.mostCommon!
            return GenreInfo(key: key, name: name, trackUids: members[key]!.elements, category: GenreCategories.of(name))
        }
        if !unknown.isEmpty {
            result.append(GenreInfo(key: unknownKey, name: unknownName, trackUids: unknown, category: .unknown, isUnknown: true))
        }
        return result
    }
}

/// Feste, lokale Vektor-Icons je Genre-Familie (keine Fotos, keine Internetbilder).
///
/// Die Reihenfolge (= `rawValue`) entspricht der Kotlin-Ordinalzahl; davon hängt die Farbe ab
/// (`GenrePalette.forCategory`). Neue Fälle nur hinten anfügen.
public enum GenreCategory: Int, CaseIterable, Codable, Hashable, Sendable {
    case rock, metal, punk, alternative, pop, hiphop, soulFunk, jazz, blues, classical, electronic, dance,
         reggae, country, folk, latin, world, soundtrack, ambient, schlager, children, spoken, gospel,
         holiday, instrumental, other, unknown
    // Seit 1.2.0: Genres mit eigenem Titelbild (hinten angefügt, damit bestehende Farbzuordnungen bleiben).
    case darkwave, hardstyle, hardtekk, anthems, sounds

    /// Name wie in Kotlin (`ROCK`, `SOUL_FUNK` …), z. B. für Asset-Namen.
    public var kotlinName: String {
        switch self {
        case .rock: return "ROCK"
        case .metal: return "METAL"
        case .punk: return "PUNK"
        case .alternative: return "ALTERNATIVE"
        case .pop: return "POP"
        case .hiphop: return "HIPHOP"
        case .soulFunk: return "SOUL_FUNK"
        case .jazz: return "JAZZ"
        case .blues: return "BLUES"
        case .classical: return "CLASSICAL"
        case .electronic: return "ELECTRONIC"
        case .dance: return "DANCE"
        case .reggae: return "REGGAE"
        case .country: return "COUNTRY"
        case .folk: return "FOLK"
        case .latin: return "LATIN"
        case .world: return "WORLD"
        case .soundtrack: return "SOUNDTRACK"
        case .ambient: return "AMBIENT"
        case .schlager: return "SCHLAGER"
        case .children: return "CHILDREN"
        case .spoken: return "SPOKEN"
        case .gospel: return "GOSPEL"
        case .holiday: return "HOLIDAY"
        case .instrumental: return "INSTRUMENTAL"
        case .other: return "OTHER"
        case .unknown: return "UNKNOWN"
        case .darkwave: return "DARKWAVE"
        case .hardstyle: return "HARDSTYLE"
        case .hardtekk: return "HARDTEKK"
        case .anthems: return "ANTHEMS"
        case .sounds: return "SOUNDS"
        }
    }
}

/// Zuordnung eines Genre-Namens zu einer Icon-Familie (Stichwortregeln, Reihenfolge wichtig).
public enum GenreCategories {

    static let rules: [(GenreCategory, [String])] = [
        (.holiday, ["christmas", "weihnacht", "xmas", "holiday", "advent"]),
        (.children, ["kinder", "children", "kids", "kindermusik"]),
        (.spoken, ["horbuch", "audiobook", "podcast", "speech", "horspiel", "spoken", "comedy", "kabarett", "lesung", "audio theatre"]),
        (.soundtrack, ["soundtrack", "filmmusik", "film score", "score", "musical", "showtunes", "game", "anime", "ost"]),
        (.metal, ["metal", "metalcore", "grindcore", "deathcore"]),
        (.punk, ["punk", "hardcore", "oi!"]),
        (.hiphop, ["hip-hop", "hip hop", "hiphop", "rap", "trap", "grime", "g-funk", "drill"]),
        (.soulFunk, ["r&b", "rnb", "r'n'b", "soul", "motown", "funk", "neo soul"]),
        (.gospel, ["gospel", "christian", "christlich", "worship", "geistlich", "spiritual"]),
        (.jazz, ["jazz", "swing", "bebop", "big band", "bossa", "dixieland"]),
        (.blues, ["blues"]),
        (.rock, ["classic rock", "hard rock", "rock & roll", "rock'n'roll", "rock n roll", "rockabilly"]),
        (.classical, ["classical", "klassik", "classic", "orchest", "symphon", "sinfon", "opera", "oper", "baroque", "barock", "chamber", "kammermusik", "romantik", "neoclassical", "choral"]),
        (.dance, ["dance", "disco", "eurodance", "club"]),
        (.electronic, ["electro", "elektro", "electronic", "techno", "house", "trance", "edm", "dubstep", "drum & bass", "drum and bass", "drum'n'bass", "dnb", "idm", "synth", "breakbeat", "jungle", "electronica", "ebm"]),
        (.reggae, ["reggae", "ska", "dancehall", "dub", "rocksteady"]),
        (.country, ["country", "bluegrass", "americana", "western"]),
        (.latin, ["latin", "salsa", "samba", "tango", "reggaeton", "bachata", "cumbia", "flamenco", "merengue"]),
        (.world, ["world", "weltmusik", "afro", "celtic", "ethnic", "k-pop", "j-pop", "bhangra"]),
        (.ambient, ["ambient", "new age", "chill", "lounge", "meditat", "downtempo", "easy listening", "entspann"]),
        (.schlager, ["schlager", "volksmusik", "volkstuml", "polka", "oktoberfest", "neue deutsche welle", "liedermacher"]),
        (.folk, ["folk", "singer", "songwriter", "acoustic", "akustik", "chanson", "country folk"]),
        (.alternative, ["indie", "alternative", "alternativ", "grunge", "shoegaze", "emo", "post-rock", "britpop", "new wave", "post-punk"]),
        (.rock, ["rock"]),
        (.pop, ["pop", "top 40", "charts", "oldies"]),
        (.instrumental, ["instrumental", "piano", "klavier", "guitar"]),
    ]

    /// Genres mit eigenem Titelbild. Erkannt wird nur der Genre-Text aus den Tags, als ganzes Wort
    /// (z. B. „Sounds“, nicht „Soundtrack“) – es wird nichts zugeordnet, was nicht so in der Datei steht.
    static let artworkRules: [(GenreCategory, [String])] = [
        (.hardtekk, ["hardtekk", "hard tekk", "hard-tekk", "hardtek", "tekk"]),
        (.hardstyle, ["hardstyle", "hard style", "hard-style"]),
        (.darkwave, ["darkwave", "dark wave", "dark-wave"]),
        (.anthems, ["hymnen", "hymne", "hymns", "hymn", "anthems", "anthem"]),
        (.sounds, ["sounds", "sound"]),
    ]

    /// Ergebnisse merken: wird beim Scrollen für jede sichtbare Zeile abgefragt.
    private static let cache = GenreCategoryCache()

    public static func of(_ name: String?) -> GenreCategory {
        let key = TextNorm.key(name)
        if key.isEmpty { return .unknown }
        if let cached = cache.get(key) { return cached }
        let category = classify(key)
        cache.set(key, category)
        return category
    }

    static func classify(_ key: String) -> GenreCategory {
        for (category, words) in artworkRules where words.contains(where: { wholeWord(key, $0) }) {
            return category
        }
        for (category, words) in rules where words.contains(where: { matches(key, $0) }) {
            return category
        }
        return .other
    }

    /// Kurze Stichwörter (≤ 3 Zeichen, z. B. „ost“, „dub“) nur als ganzes Wort, sonst als Teilwort.
    private static func matches(_ key: String, _ word: String) -> Bool {
        word.utf16.count <= 3 ? wholeWord(key, word) : key.range(of: word, options: .literal) != nil
    }

    /// Wie Regex `(^|[^a-z])word([^a-z]|$)`.
    static func wholeWord(_ key: String, _ word: String) -> Bool {
        let k = Array(key.unicodeScalars)
        let w = Array(word.unicodeScalars)
        guard !w.isEmpty, w.count <= k.count else { return false }
        func isAZ(_ s: Unicode.Scalar) -> Bool { s.value >= 0x61 && s.value <= 0x7A }
        for start in 0...(k.count - w.count) {
            var equal = true
            for i in 0..<w.count where k[start + i] != w[i] {
                equal = false
                break
            }
            guard equal else { continue }
            let beforeOK = start == 0 || !isAZ(k[start - 1])
            let end = start + w.count
            let afterOK = end == k.count || !isAZ(k[end])
            if beforeOK && afterOK { return true }
        }
        return false
    }
}

/// Threadsicherer Zwischenspeicher der Genre-Zuordnung.
private final class GenreCategoryCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: GenreCategory] = [:]

    func get(_ key: String) -> GenreCategory? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func set(_ key: String, _ value: GenreCategory) {
        lock.lock()
        defer { lock.unlock() }
        if values.count > 10_000 { values.removeAll() }
        values[key] = value
    }
}

/// Gedeckte Farbtöne je Genre-Familie (ARGB 0xAARRGGBB) – gemeinsam für Oberfläche, Ersatz-Cover und Widget.
public enum GenrePalette {
    public static let tones: [UInt32] = [
        0xFFD4_566F, // Rosé
        0xFFD9_765F, // Koralle
        0xFFC9_9A45, // Bernstein
        0xFF7E_9F78, // Salbei
        0xFF4F_9592, // Petrol
        0xFF5E_7DB0, // Schieferblau
        0xFF8C_5F9E, // Pflaume
        0xFFB2_7390, // Malve
        0xFFAA_916E, // Sand
        0xFF6E_6869, // Graphit
    ]
    public static let unknownTone: UInt32 = 0xFF8E_8689

    public static func forCategory(_ category: GenreCategory) -> UInt32 {
        category == .unknown ? unknownTone : tones[category.rawValue % tones.count]
    }

    /// Farbe zu einem beliebigen Text (gleiches Ergebnis wie auf Android: `String.hashCode` der JVM).
    public static func forText(_ text: String) -> UInt32 {
        let h = Int(text.lowercased().javaHashCode & 0x7fff_ffff)
        return tones[h % tones.count]
    }
}
