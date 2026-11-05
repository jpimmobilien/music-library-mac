import Foundation

/// Schnellfilter: Ein-/Aus-Bedingungen, die in jedem Bereich der Bibliothek gesetzt werden können.
///
/// Gespeichert wird der Name (`rawValue`); neue Fälle nur hinten anfügen.
public enum QuickFilter: String, CaseIterable, Codable, Hashable, Sendable {
    case favorites = "FAVORITES"
    case neverPlayed = "NEVER_PLAYED"
    case recentlyAdded = "RECENTLY_ADDED"
    case lossless = "LOSSLESS"
    case withLyrics = "WITH_LYRICS"
    case withoutCover = "WITHOUT_COVER"
    case highRating = "HIGH_RATING"

    public var label: String {
        switch self {
        case .favorites: return "Favoriten"
        case .neverPlayed: return "Nie gespielt"
        case .recentlyAdded: return "Neu (30 Tage)"
        case .lossless: return "Verlustfrei"
        case .withLyrics: return "Mit Liedtext"
        case .withoutCover: return "Ohne Cover"
        case .highRating: return "★ 4+"
        }
    }
}

/// Filter der Bibliothek (Facetten + Schnellfilter).
///
/// Innerhalb einer Facette genügt ein Treffer (ODER: „Rock“ oder „Pop“), zwischen den Facetten und
/// für jeden Schnellfilter müssen alle Bedingungen zutreffen (UND). Leere Mengen schränken nicht ein.
///
/// Gespeichert (Codable) mit sortierten Listen; Lesen ist tolerant (unbekannte Schnellfilter und
/// ungültige Werte werden ignoriert).
public struct LibraryFilter: Hashable, Codable, Sendable {
    /// `FacetValue.id` der Genres (= Schlüssel von `GenreIndex`, „#unbekannt“ = ohne Genre).
    public var genres: Set<String> = []
    /// Jahrzehnte (1970, 1980, …) aus plausiblen Jahren (`SmartPlaylists.plausibleYears`).
    public var decades: Set<Int> = []
    /// `FacetValue.id` der Interpreten (= Schlüssel von `ArtistIndex`).
    public var artists: Set<String> = []
    /// `FacetValue.id` der Formate (`AudioFormatFamily.of`, z. B. „MP3“, „FLAC“).
    public var formats: Set<String> = []
    public var quick: Set<QuickFilter> = []

    public init() {}

    /// Keine Bedingung gesetzt (alles wird angezeigt).
    public var isEmpty: Bool {
        genres.isEmpty && decades.isEmpty && artists.isEmpty && formats.isEmpty && quick.isEmpty
    }

    /// Anzahl gesetzter Bedingungen (jeder gewählte Wert zählt einzeln) – für das Abzeichen am Filterknopf.
    public var activeCount: Int { genres.count + decades.count + artists.count + formats.count + quick.count }

    private enum CodingKeys: String, CodingKey { case genres, decades, artists, formats, quick }

    public init(from decoder: Decoder) throws {
        self.init()
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        // Element für Element: ein ungültiger Eintrag verwirft nicht die ganze Liste.
        func list<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> [T] {
            (((try? c.decodeIfPresent([LenientElement<T>].self, forKey: key)) ?? nil) ?? []).compactMap(\.value)
        }
        genres = Set(list(String.self, .genres).filter { !$0.isEmpty })
        decades = Set(list(Int.self, .decades))
        artists = Set(list(String.self, .artists).filter { !$0.isEmpty })
        formats = Set(list(String.self, .formats).filter { !$0.isEmpty })
        quick = Set(list(String.self, .quick).compactMap(QuickFilter.init(rawValue:)))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(genres.sorted(), forKey: .genres)
        try c.encode(decades.sorted(), forKey: .decades)
        try c.encode(artists.sorted(), forKey: .artists)
        try c.encode(formats.sorted(), forKey: .formats)
        try c.encode(QuickFilter.allCases.filter(quick.contains).map(\.rawValue), forKey: .quick)
    }
}

/// Daten außerhalb der Titel, die einige Schnellfilter brauchen.
public struct FilterContext: Sendable {
    public var favorites: Set<Int64>
    public var stats: [Int64: PlayStats]
    /// Jetzt in Sekunden seit 1970 (wie `Track.dateAdded`).
    public var nowSeconds: Int64

    public init(favorites: Set<Int64>, stats: [Int64: PlayStats], nowSeconds: Int64) {
        self.favorites = favorites
        self.stats = stats
        self.nowSeconds = nowSeconds
    }
}

/// Ein auswählbarer Wert einer Facette mit Anzahl der Titel.
public struct FacetValue: Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var count: Int

    public init(id: String, label: String, count: Int) {
        self.id = id
        self.label = label
        self.count = count
    }
}

/// Alle Facetten der Bibliothek (Grundlage der Filterauswahl).
public struct FilterFacets: Hashable, Sendable {
    /// Nach Anzahl absteigend (bei Gleichstand nach Name); „Unbekanntes Genre“ immer am Ende.
    public var genres: [FacetValue]
    /// id = „1980“, label = „1980er“, aufsteigend.
    public var decades: [FacetValue]
    /// Nach Anzahl absteigend (bei Gleichstand nach Name), höchstens `LibraryFiltering.maxArtistFacets`.
    public var artists: [FacetValue]
    /// Nach Anzahl absteigend (bei Gleichstand nach Name).
    public var formats: [FacetValue]

    public init(genres: [FacetValue], decades: [FacetValue], artists: [FacetValue], formats: [FacetValue]) {
        self.genres = genres
        self.decades = decades
        self.artists = artists
        self.formats = formats
    }

    public static let empty = FilterFacets(genres: [], decades: [], artists: [], formats: [])
}

/// Formatfamilie eines Titels für Anzeige und Filter: aus dem Codec (wie ihn der Tag-Leser liefert,
/// z. B. „AAC“, „ALAC“, „PCM“, „Vorbis“), sonst aus der Dateiendung. PCM wird nach Container
/// unterschieden („WAV“, „AIFF“). Unbekannte Codecs erscheinen unter ihrem eigenen Namen.
public enum AudioFormatFamily {
    public static let mp3 = "MP3"
    public static let aac = "AAC"
    public static let alac = "ALAC"
    public static let flac = "FLAC"
    public static let wav = "WAV"
    public static let aiff = "AIFF"
    public static let vorbis = "Ogg Vorbis"
    public static let opus = "Opus"
    /// Weder Codec noch Dateiendung bekannt.
    public static let unknown = "Unbekannt"

    /// Familien, die ohne Verlust speichern.
    public static let losslessFamilies: Set<String> = [
        alac, flac, wav, aiff, "PCM", "WMA Lossless", "Monkey's Audio", "WavPack", "TTA", "Shorten", "DSD", "TrueHD", "TAK",
    ]

    public static func of(_ track: Track) -> String { of(codec: track.codec, fileExtension: track.fileExtension) }

    /// Familie aus Codec bzw. (ohne Codec) Dateiendung (ohne Punkt, Groß-/Kleinschreibung egal).
    public static func of(codec: String?, fileExtension: String) -> String {
        let ext = fileExtension.lowercased()
        let trimmed = codec?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return family(codec: trimmed.uppercased(), ext: ext) ?? trimmed
        }
        if let family = extensionFamilies[ext] { return family }
        return ext.isEmpty ? unknown : ext.uppercased()
    }

    /// Verlustfrei: ALAC, FLAC, WAV/AIFF (PCM) und weitere verlustfreie Codecs. PCM-Container mit
    /// verlustbehafteter Kodierung (A-law, µ-law, ADPCM) zählen nicht dazu.
    public static func isLossless(_ track: Track) -> Bool {
        if let c = normalizedCodec(track.codec) {
            if lossyPCMMarkers.contains(where: { c.contains($0) }) { return false }
            if isPCM(c) { return true }
        }
        return losslessFamilies.contains(of(track))
    }

    // MARK: - Zuordnung

    private static func normalizedCodec(_ codec: String?) -> String? {
        guard let codec else { return nil }
        let c = codec.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return c.isEmpty ? nil : c
    }

    private static let lossyPCMMarkers = ["A-LAW", "ALAW", "MU-LAW", "ULAW", "µ-LAW", "Μ-LAW", "ADPCM", "IMA4", "GSM"]

    private static func isPCM(_ c: String) -> Bool {
        c.hasPrefix("PCM") || c == "LPCM" || c == "LINEAR PCM"
    }

    private static let wavExtensions: Set<String> = ["wav", "wave", "bwf", "rf64", "w64"]
    private static let aiffExtensions: Set<String> = ["aif", "aiff", "aifc"]

    /// `c` ist bereits in Großbuchstaben.
    private static func family(codec c: String, ext: String) -> String? {
        if c.contains("ALAC") || c.contains("APPLE LOSSLESS") { return alac }
        if c.contains("FLAC") { return flac }
        if c == "WMA LOSSLESS" { return "WMA Lossless" }
        if c.hasPrefix("WMA") || c.contains("WINDOWS MEDIA") { return "WMA" }
        if c.contains("AAC") { return aac }
        if c == "MP3" || c == "MPEG/L3" || c.contains("LAYER 3") || c.contains("LAYER III") { return mp3 }
        if c == "MP2" || c == "MPEG/L2" || c.contains("LAYER 2") || c.contains("LAYER II") { return "MP2" }
        if c == "MP1" || c == "MPEG/L1" { return "MP1" }
        if c.contains("VORBIS") { return vorbis }
        if c.contains("OPUS") { return opus }
        if c.contains("SPEEX") { return "Speex" }
        if isPCM(c) || c == "WAV" || c == "WAVE" || c.hasPrefix("AIFF") || lossyPCMMarkers.contains(where: { c.hasPrefix($0) }) {
            if aiffExtensions.contains(ext) || c.hasPrefix("AIFF") { return aiff }
            if wavExtensions.contains(ext) || c == "WAV" || c == "WAVE" { return wav }
            if ext == "caf" { return "CAF" }
            return "PCM"
        }
        switch c {
        case "MONKEY'S AUDIO", "APE": return "Monkey's Audio"
        case "WAVPACK": return "WavPack"
        case "MUSEPACK", "MPC": return "Musepack"
        case "TTA", "TRUE AUDIO": return "TTA"
        case "SHORTEN": return "Shorten"
        case "TAK": return "TAK"
        case "AC-3", "AC3": return "AC-3"
        case "E-AC-3", "EAC3": return "E-AC-3"
        case "TRUEHD", "MLP": return "TrueHD"
        default: break
        }
        if c.hasPrefix("DSD") { return "DSD" }
        return nil
    }

    private static let extensionFamilies: [String: String] = [
        "mp3": mp3, "mp2": "MP2", "mpa": "MP2", "mp1": "MP1",
        "aac": aac, "adts": aac, "m4a": aac, "m4b": aac, "m4p": aac, "mp4": aac,
        "alac": alac, "flac": flac, "fla": flac,
        "wav": wav, "wave": wav, "bwf": wav, "rf64": wav, "w64": wav,
        "aif": aiff, "aiff": aiff, "aifc": aiff,
        "ogg": vorbis, "oga": vorbis, "opus": opus, "spx": "Speex",
        "wma": "WMA", "ape": "Monkey's Audio", "wv": "WavPack", "mpc": "Musepack", "tta": "TTA",
        "shn": "Shorten", "tak": "TAK", "dsf": "DSD", "dff": "DSD", "caf": "CAF", "ac3": "AC-3",
    ]
}

/// Merkt sich während eines Durchgangs die normalisierten Schlüssel gleicher Texte – Genres, Interpreten
/// und Formate wiederholen sich in einer Bibliothek ständig. Ergebnisse sind identisch mit der direkten
/// Berechnung (`GenreIndex`/`ArtistIndex`-Regeln). Nicht threadsicher: je Aufruf eine eigene Instanz.
final class TrackKeyCache {
    /// Bereinigter Name (für die Anzeige) und Vergleichsschlüssel.
    struct Name {
        let clean: String
        let key: String
    }

    private struct ArtistParts {
        let primary: Name?
        let guests: [Name]
    }

    private struct Format {
        let family: String
        let lossless: Bool
    }

    /// Genre-Text → getrimmter Text und Schlüssel; `nil` = leer (zählt nicht als Genre-Angabe).
    private var genres: [String: Name?] = [:]
    private var artists: [String: ArtistParts] = [:]
    private var names: [String: Name?] = [:]
    private var formats: [String: [String: Format]] = [:]

    /// Wie `GenreIndex`: `nil` = leerer Eintrag; ein Schlüssel kann leer sein (z. B. nur Satzzeichen).
    func genre(_ raw: String) -> Name? {
        if let cached = genres[raw] { return cached }
        let g = raw.kotlinTrimmed()
        let value: Name? = g.isEmpty ? nil : Name(clean: g, key: TextNorm.key(g))
        genres[raw] = value
        return value
    }

    /// Wie `ArtistIndex`: Haupt-Interpreten, dann Gäste, dann Album-Interpreten; Sammelbezeichnungen und
    /// leere Namen entfallen.
    func forEachArtist(of t: Track, _ body: (Name) -> Void) {
        if t.artists.count == 1 {
            let parts = artistParts(t.artists[0])
            if let p = parts.primary { body(p) }
            for g in parts.guests { body(g) }
        } else if !t.artists.isEmpty {
            let all = t.artists.map(artistParts)
            for parts in all {
                if let p = parts.primary { body(p) }
            }
            for parts in all {
                for g in parts.guests { body(g) }
            }
        }
        for aa in t.albumArtists {
            if let n = name(aa) { body(n) }
        }
    }

    private func artistParts(_ raw: String) -> ArtistParts {
        if let cached = artists[raw] { return cached }
        let split = ArtistNames.split(raw)
        let parts = ArtistParts(primary: split.primary.isEmpty ? nil : name(split.primary), guests: split.guests.compactMap(name))
        artists[raw] = parts
        return parts
    }

    private func name(_ raw: String) -> Name? {
        if let cached = names[raw] { return cached }
        let clean = raw.kotlinTrimmed()
        var value: Name?
        if !clean.isEmpty && !ArtistNames.isVarious(clean) {
            let key = TextNorm.key(clean)
            if !key.isEmpty { value = Name(clean: clean, key: key) }
        }
        names[raw] = value
        return value
    }

    func family(_ t: Track) -> String { format(t).family }

    func isLossless(_ t: Track) -> Bool { format(t).lossless }

    private func format(_ t: Track) -> Format {
        let codec = t.codec ?? ""
        let ext = t.fileExtension
        if let cached = formats[codec]?[ext] { return cached }
        let value = Format(family: AudioFormatFamily.of(t), lossless: AudioFormatFamily.isLossless(t))
        formats[codec, default: [:]][ext] = value
        return value
    }
}

/// Filtern und Facetten der Bibliothek. Alle Funktionen arbeiten in einem Durchgang über die Titel
/// (auch bei 30.000 Titeln schnell) und verwenden dieselbe Normalisierung wie `GenreIndex` und
/// `ArtistIndex` – Facetten-IDs passen daher zu `GenreInfo.key` bzw. `ArtistInfo.key`.
public enum LibraryFiltering {
    /// „Neu“: höchstens so viele Tage seit der Aufnahme in die Bibliothek.
    public static let recentlyAddedDays = 30
    /// „★ 4+“: Bewertung ab diesem Wert (0…100, 20 je Stern).
    public static let highRatingMin = 80
    /// Höchstzahl der Interpreten in den Facetten.
    public static let maxArtistFacets = 200

    // MARK: - Facetten

    public static func facets(_ tracks: [Track]) -> FilterFacets {
        let cache = TrackKeyCache()
        var genreCounts: [String: Int] = [:]
        var genreSpellings: [String: OrderedCounter<String>] = [:]
        var unknownGenre = 0
        var decadeCounts: [Int: Int] = [:]
        var artistCounts: [String: Int] = [:]
        var artistSpellings: [String: OrderedCounter<String>] = [:]
        var formatCounts: [String: Int] = [:]
        var seen: [String] = []
        seen.reserveCapacity(8)

        for t in tracks {
            // Genres (wie GenreIndex; ein Titel zählt je Genre einmal)
            seen.removeAll(keepingCapacity: true)
            var hasGenre = false
            for raw in t.genres {
                guard let g = cache.genre(raw) else { continue }
                hasGenre = true
                if g.key.isEmpty { continue }
                genreSpellings[g.key, default: OrderedCounter()].add(g.clean) // Schreibweise wie GenreIndex
                if seen.contains(g.key) { continue }
                seen.append(g.key)
                genreCounts[g.key, default: 0] += 1
            }
            if !hasGenre { unknownGenre += 1 }

            if let d = decade(of: t) { decadeCounts[d, default: 0] += 1 }

            // Interpreten (wie ArtistIndex: Haupt-Interpreten, Gäste, Album-Interpreten)
            seen.removeAll(keepingCapacity: true)
            cache.forEachArtist(of: t) { a in
                artistSpellings[a.key, default: OrderedCounter()].add(a.clean)
                if seen.contains(a.key) { return }
                seen.append(a.key)
                artistCounts[a.key, default: 0] += 1
            }

            formatCounts[cache.family(t), default: 0] += 1
        }

        var genres = byCountThenLabel(genreCounts.map { FacetValue(id: $0.key, label: genreSpellings[$0.key]!.mostCommon!, count: $0.value) })
        if unknownGenre > 0 {
            genres.append(FacetValue(id: GenreIndex.unknownKey, label: GenreIndex.unknownName, count: unknownGenre))
        }
        let decades = decadeCounts.keys.sorted().map {
            FacetValue(id: String($0), label: SmartPlaylists.decadeLabel($0), count: decadeCounts[$0]!)
        }
        let artists = byCountThenLabel(artistCounts.map { FacetValue(id: $0.key, label: artistSpellings[$0.key]!.mostCommon!, count: $0.value) })
        let formats = byCountThenLabel(formatCounts.map { FacetValue(id: $0.key, label: $0.key, count: $0.value) })
        return FilterFacets(genres: genres, decades: decades, artists: Array(artists.prefix(maxArtistFacets)), formats: formats)
    }

    /// Anzahl absteigend, dann Name (natürliche Reihenfolge), dann id – stabil und eindeutig.
    private static func byCountThenLabel(_ values: [FacetValue]) -> [FacetValue] {
        let keys = values.map { NaturalKey($0.label) }
        return stableSortedIndices(values.count) { a, b in
            if values[a].count != values[b].count { return values[a].count > values[b].count ? -1 : 1 }
            let r = NaturalOrder.compare(keys[a], keys[b])
            if r != 0 { return r }
            return values[a].id.javaCompare(values[b].id).signum()
        }.map { values[$0] }
    }

    // MARK: - Schlüssel eines Titels (dieselben wie in den Facetten)

    /// Jahrzehnt (1980 …) aus einem plausiblen Jahr, sonst `nil`.
    public static func decade(of track: Track) -> Int? {
        guard let y = track.year, SmartPlaylists.plausibleYears.contains(y) else { return nil }
        return y / 10 * 10
    }

    /// Genre-Schlüssel eines Titels (wie `GenreIndex`); ohne Genre-Angabe `GenreIndex.unknownKey`.
    public static func genreKeys(of track: Track) -> [String] { genreKeys(of: track, TrackKeyCache()) }

    static func genreKeys(of track: Track, _ cache: TrackKeyCache) -> [String] {
        var keys: [String] = []
        var hasGenre = false
        for raw in track.genres {
            guard let g = cache.genre(raw) else { continue }
            hasGenre = true
            if !g.key.isEmpty && !keys.contains(g.key) { keys.append(g.key) }
        }
        return hasGenre ? keys : [GenreIndex.unknownKey]
    }

    /// Interpreten-Schlüssel eines Titels (wie `ArtistIndex`: Haupt-Interpreten, Gäste, Album-Interpreten;
    /// Sammelbezeichnungen wie „Various Artists“ zählen nicht).
    public static func artistKeys(of track: Track) -> [String] {
        var keys: [String] = []
        TrackKeyCache().forEachArtist(of: track) { a in
            if !keys.contains(a.key) { keys.append(a.key) }
        }
        return keys
    }

    // MARK: - Filtern

    public static func matches(_ track: Track, _ filter: LibraryFilter, _ ctx: FilterContext) -> Bool {
        matches(track, filter, ctx, TrackKeyCache())
    }

    /// Prüfung mit gemeinsamem Zwischenspeicher; billige Bedingungen zuerst.
    static func matches(_ track: Track, _ filter: LibraryFilter, _ ctx: FilterContext, _ cache: TrackKeyCache) -> Bool {
        for q in filter.quick where !matches(track, q, ctx, cache) { return false }
        if !filter.decades.isEmpty {
            guard let d = decade(of: track), filter.decades.contains(d) else { return false }
        }
        if !filter.formats.isEmpty && !filter.formats.contains(cache.family(track)) { return false }
        if !filter.genres.isEmpty && !genreKeys(of: track, cache).contains(where: filter.genres.contains) { return false }
        if !filter.artists.isEmpty {
            var hit = false
            cache.forEachArtist(of: track) { a in
                if !hit && filter.artists.contains(a.key) { hit = true }
            }
            if !hit { return false }
        }
        return true
    }

    /// Trifft ein einzelner Schnellfilter zu?
    public static func matches(_ track: Track, _ quick: QuickFilter, _ ctx: FilterContext) -> Bool {
        matches(track, quick, ctx, nil)
    }

    private static func matches(_ track: Track, _ quick: QuickFilter, _ ctx: FilterContext, _ cache: TrackKeyCache?) -> Bool {
        switch quick {
        case .favorites: return ctx.favorites.contains(track.uid)
        case .neverPlayed: return (ctx.stats[track.uid]?.playCount ?? 0) <= 0
        case .recentlyAdded:
            return track.dateAdded > 0 && ctx.nowSeconds - track.dateAdded <= Int64(recentlyAddedDays) * 86_400
        case .lossless: return cache?.isLossless(track) ?? AudioFormatFamily.isLossless(track)
        case .withLyrics: return track.hasLyrics
        case .withoutCover: return !track.hasPicture
        case .highRating: return (track.rating ?? 0) >= highRatingMin
        }
    }

    /// Passende Titel in der gegebenen Reihenfolge (leerer Filter → unverändert).
    public static func tracks(_ tracks: [Track], _ filter: LibraryFilter, _ ctx: FilterContext) -> [Track] {
        if filter.isEmpty { return tracks }
        let cache = TrackKeyCache()
        return tracks.filter { matches($0, filter, ctx, cache) }
    }

    /// Album/Interpret/Genre bleibt, wenn mindestens einer seiner Titel passt.
    public static func albums(_ albums: [AlbumInfo], _ filter: LibraryFilter, index: LibraryIndex, _ ctx: FilterContext) -> [AlbumInfo] {
        groups(albums, members: { $0.trackUids }, filter, index, ctx)
    }

    public static func artists(_ artists: [ArtistInfo], _ filter: LibraryFilter, index: LibraryIndex, _ ctx: FilterContext) -> [ArtistInfo] {
        groups(artists, members: { $0.trackUids }, filter, index, ctx)
    }

    public static func genres(_ genres: [GenreInfo], _ filter: LibraryFilter, index: LibraryIndex, _ ctx: FilterContext) -> [GenreInfo] {
        groups(genres, members: { $0.trackUids }, filter, index, ctx)
    }

    /// Jeder Titel wird höchstens einmal geprüft (Ergebnis gemerkt), Gruppen brechen beim ersten Treffer ab.
    private static func groups<G>(
        _ items: [G], members: (G) -> [Int64], _ filter: LibraryFilter, _ index: LibraryIndex, _ ctx: FilterContext
    ) -> [G] {
        if filter.isEmpty { return items }
        let cache = TrackKeyCache()
        var memo: [Int64: Bool] = [:]
        func hit(_ uid: Int64) -> Bool {
            if let known = memo[uid] { return known }
            let result = index.trackByUid[uid].map { matches($0, filter, ctx, cache) } ?? false
            memo[uid] = result
            return result
        }
        return items.filter { members($0).contains(where: hit) }
    }
}
