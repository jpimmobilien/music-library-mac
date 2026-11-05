import XCTest
@testable import MLCore

/// v2: Filter (Schnellfilter, Facetten), Formatfamilien und neue automatische Playlists.
final class V2FilterTests: XCTestCase {

    private typealias T = V2Tracks
    private let now: Int64 = 1_000_000_000
    private let day: Int64 = 86_400

    /// Sechs Titel, die zusammen alle Filter abdecken.
    private func library() -> [Track] {
        [
            T.make(1, "Bohemian", artist: "Queen", genres: ["Rock"], year: 1975, rating: 100, dateAdded: now - 2 * day,
                   codec: "AAC", fileName: "a.m4a", hasPicture: true, hasLyrics: true),
            T.make(2, "Feat", artists: ["Calvin Harris feat. Rihanna"], genres: ["rock", "Pop"], year: 1984, rating: 60,
                   dateAdded: now - 40 * day, codec: "FLAC", fileName: "b.flac", hasPicture: false),
            T.make(3, "Sampler", artist: "Queen", albumArtist: "Various Artists", genres: [], year: nil, rating: nil,
                   dateAdded: 0, codec: "PCM", fileName: "c.wav", hasPicture: true),
            T.make(4, "Waterloo", artist: "ABBA", albumArtist: "ABBA", genres: ["Pop"], year: 1200, rating: 80, dateAdded: now,
                   codec: nil, fileName: "d.mp3", hasPicture: false, hasLyrics: true),
            T.make(5, "Leer", artist: nil, genres: ["  "], year: 1989, rating: 20, dateAdded: now - 30 * day,
                   codec: "ALAC", fileName: "e.m4a", hasPicture: true),
            T.make(6, "So What", artists: ["Miles Davis"], genres: ["Jazz"], year: 1959, dateAdded: now - 31 * day,
                   codec: "PCM", fileName: "f.aiff", hasPicture: true),
        ]
    }

    private var ctx: FilterContext {
        FilterContext(
            favorites: [1, 4],
            stats: [
                1: PlayStats(trackUid: 1, playCount: 3, lastPlayedAt: 1_000),
                2: PlayStats(trackUid: 2, playCount: 0, lastPlayedAt: nil),
                4: PlayStats(trackUid: 4, playCount: 1, lastPlayedAt: 2_000),
            ],
            nowSeconds: now
        )
    }

    private func ids(_ build: (inout LibraryFilter) -> Void) -> [Int64] {
        var f = LibraryFilter()
        build(&f)
        return LibraryFiltering.tracks(library(), f, ctx).map(\.uid)
    }

    // MARK: - Schnellfilter

    func testSchnellfilter_namenUndGespeicherteWerte() {
        XCTAssertEqual(QuickFilter.allCases.map(\.rawValue),
                       ["FAVORITES", "NEVER_PLAYED", "RECENTLY_ADDED", "LOSSLESS", "WITH_LYRICS", "WITHOUT_COVER", "HIGH_RATING"])
        XCTAssertEqual(QuickFilter.allCases.map(\.label),
                       ["Favoriten", "Nie gespielt", "Neu (30 Tage)", "Verlustfrei", "Mit Liedtext", "Ohne Cover", "★ 4+"])
    }

    func testSchnellfilter_jederEinzeln() {
        XCTAssertEqual(ids { $0.quick = [.favorites] }, [1, 4])
        XCTAssertEqual(ids { $0.quick = [.neverPlayed] }, [2, 3, 5, 6]) // ohne Statistik oder 0 Wiedergaben
        XCTAssertEqual(ids { $0.quick = [.recentlyAdded] }, [1, 4, 5]) // genau 30 Tage zählt noch, 0 = unbekannt nicht
        XCTAssertEqual(ids { $0.quick = [.lossless] }, [2, 3, 5, 6])
        XCTAssertEqual(ids { $0.quick = [.withLyrics] }, [1, 4])
        XCTAssertEqual(ids { $0.quick = [.withoutCover] }, [2, 4])
        XCTAssertEqual(ids { $0.quick = [.highRating] }, [1, 4]) // ≥ 80
    }

    func testSchnellfilter_kombiniert_alleMuessenZutreffen() {
        XCTAssertEqual(ids { $0.quick = [.favorites, .highRating] }, [1, 4])
        XCTAssertEqual(ids { $0.quick = [.favorites, .withoutCover] }, [4])
        XCTAssertEqual(ids { $0.quick = [.lossless, .recentlyAdded] }, [5])
        XCTAssertEqual(ids { $0.quick = [.neverPlayed, .favorites] }, [])
        XCTAssertEqual(ids { _ in }, [1, 2, 3, 4, 5, 6]) // leerer Filter: alles
    }

    func testNeu_relativZuJetzt() {
        let t = T.make(1, dateAdded: now - 30 * day)
        XCTAssertTrue(LibraryFiltering.matches(t, .recentlyAdded, ctx))
        var later = ctx
        later.nowSeconds += 1
        XCTAssertFalse(LibraryFiltering.matches(t, .recentlyAdded, later))
        // Zeitpunkt in der Zukunft (Uhr verstellt) gilt als neu
        XCTAssertTrue(LibraryFiltering.matches(T.make(2, dateAdded: now + day), .recentlyAdded, ctx))
    }

    // MARK: - Facetten-Filter

    func testFacetten_jahrzehnteFormateGenresInterpreten() {
        XCTAssertEqual(ids { $0.decades = [1980] }, [2, 5])
        XCTAssertEqual(ids { $0.decades = [1970, 1950] }, [1, 6])
        XCTAssertEqual(ids { $0.decades = [1200] }, []) // unplausibles Jahr gehört zu keinem Jahrzehnt
        XCTAssertEqual(ids { $0.formats = ["WAV", "AIFF"] }, [3, 6])
        XCTAssertEqual(ids { $0.formats = ["MP3"] }, [4]) // ohne Codec aus der Dateiendung
        XCTAssertEqual(ids { $0.genres = ["rock"] }, [1, 2]) // „Rock“ und „rock“
        XCTAssertEqual(ids { $0.genres = ["pop"] }, [2, 4])
        XCTAssertEqual(ids { $0.genres = [GenreIndex.unknownKey] }, [3, 5])
        XCTAssertEqual(ids { $0.genres = ["rock", "jazz"] }, [1, 2, 6]) // ODER innerhalb der Facette
        XCTAssertEqual(ids { $0.artists = ["queen"] }, [1, 3])
        XCTAssertEqual(ids { $0.artists = ["rihanna"] }, [2]) // Gast
        XCTAssertEqual(ids { $0.artists = ["abba"] }, [4])
        XCTAssertEqual(ids { $0.artists = ["various artists"] }, []) // Sammelbezeichnung ist kein Interpret
    }

    func testFacetten_kombiniert_UNDzwischenFacetten() {
        XCTAssertEqual(ids { $0.genres = ["pop"]; $0.decades = [1980] }, [2])
        XCTAssertEqual(ids { $0.genres = ["rock"]; $0.quick = [.favorites] }, [1])
        XCTAssertEqual(ids { $0.genres = ["pop", "jazz"]; $0.formats = ["MP3"] }, [4])
        XCTAssertEqual(ids { $0.artists = ["queen"]; $0.formats = ["WAV"]; $0.quick = [.lossless] }, [3])
        XCTAssertEqual(ids { $0.artists = ["queen"]; $0.genres = ["jazz"] }, [])
    }

    func testFilter_leerUndAnzahl() {
        var f = LibraryFilter()
        XCTAssertTrue(f.isEmpty)
        XCTAssertEqual(f.activeCount, 0)
        f.genres = ["rock", "pop"]
        f.decades = [1980]
        f.quick = [.favorites]
        XCTAssertFalse(f.isEmpty)
        XCTAssertEqual(f.activeCount, 4)
        f = LibraryFilter()
        f.formats = ["MP3"]
        XCTAssertFalse(f.isEmpty)
        XCTAssertEqual(f.activeCount, 1)
    }

    func testFilter_codable_tolerant() throws {
        var f = LibraryFilter()
        f.genres = ["rock", "pop"]
        f.decades = [1980, 1970]
        f.artists = ["queen"]
        f.formats = ["FLAC"]
        f.quick = [.highRating, .favorites]
        let data = try JSONEncoder().encode(f)
        XCTAssertEqual(try JSONDecoder().decode(LibraryFilter.self, from: data), f)
        let sorted = JSONEncoder()
        sorted.outputFormatting = [.sortedKeys]
        XCTAssertEqual(String(decoding: try sorted.encode(f), as: UTF8.self),
                       #"{"artists":["queen"],"decades":[1970,1980],"formats":["FLAC"],"genres":["pop","rock"],"quick":["FAVORITES","HIGH_RATING"]}"#)

        let garbage = #"{"quick":["FAVORITES","GIBTESNICHT",3],"decades":[1980,"x"],"genres":"kaputt","artists":["queen",""],"neu":1}"#
        let g = try JSONDecoder().decode(LibraryFilter.self, from: Data(garbage.utf8))
        XCTAssertEqual(g.quick, [.favorites])
        XCTAssertEqual(g.decades, [1980])
        XCTAssertEqual(g.genres, [])
        XCTAssertEqual(g.artists, ["queen"])
        XCTAssertEqual(try JSONDecoder().decode(LibraryFilter.self, from: Data("[1,2]".utf8)), LibraryFilter())
    }

    // MARK: - Facetten

    func testFacetten_anzahlenUndReihenfolge() {
        let facets = LibraryFiltering.facets(library())
        XCTAssertEqual(facets.genres.map(\.id), ["pop", "rock", "jazz", GenreIndex.unknownKey])
        XCTAssertEqual(facets.genres.map(\.label), ["Pop", "Rock", "Jazz", "Unbekanntes Genre"])
        XCTAssertEqual(facets.genres.map(\.count), [2, 2, 1, 2])
        XCTAssertEqual(facets.decades.map(\.id), ["1950", "1970", "1980"])
        XCTAssertEqual(facets.decades.map(\.label), ["1950er", "1970er", "1980er"])
        XCTAssertEqual(facets.decades.map(\.count), [1, 1, 2])
        XCTAssertEqual(facets.artists.map(\.label), ["Queen", "ABBA", "Calvin Harris", "Miles Davis", "Rihanna"])
        XCTAssertEqual(facets.artists.map(\.count), [2, 1, 1, 1, 1]) // ABBA als Interpret und Album-Interpret: 1 Titel
        XCTAssertEqual(facets.formats.map(\.id), ["AAC", "AIFF", "ALAC", "FLAC", "MP3", "WAV"])
        XCTAssertTrue(facets.formats.allSatisfy { $0.count == 1 && $0.label == $0.id })
        XCTAssertEqual(LibraryFiltering.facets([]), FilterFacets.empty)
    }

    func testFacetten_idsPassenZuIndexUndFilter() {
        let tracks = library()
        let index = LibraryIndex.build(tracks)
        let facets = LibraryFiltering.facets(tracks)
        for g in facets.genres {
            XCTAssertEqual(index.genreByKey[g.id]?.trackCount, g.count, g.id)
            var f = LibraryFilter()
            f.genres = [g.id]
            XCTAssertEqual(LibraryFiltering.tracks(tracks, f, ctx).count, g.count, g.id)
        }
        for a in facets.artists {
            XCTAssertEqual(index.artistByKey[a.id]?.trackCount, a.count, a.id)
            var f = LibraryFilter()
            f.artists = [a.id]
            XCTAssertEqual(LibraryFiltering.tracks(tracks, f, ctx).count, a.count, a.id)
        }
        for d in facets.decades {
            var f = LibraryFilter()
            f.decades = [Int(d.id)!]
            XCTAssertEqual(LibraryFiltering.tracks(tracks, f, ctx).count, d.count, d.id)
        }
        for fmt in facets.formats {
            var f = LibraryFilter()
            f.formats = [fmt.id]
            XCTAssertEqual(LibraryFiltering.tracks(tracks, f, ctx).count, fmt.count, fmt.id)
        }
    }

    func testFacetten_haeufigsteSchreibweise_undHoechstens200Interpreten() {
        let tracks = (1...250).map { i in T.make(Int64(i), artist: "Artist \(i)") }
            + [T.make(1001, artist: "artist 7"), T.make(1002, artist: "artist 7"), T.make(1003, artist: "Artist 9")]
        let facets = LibraryFiltering.facets(tracks)
        XCTAssertEqual(facets.artists.count, LibraryFiltering.maxArtistFacets)
        XCTAssertEqual(facets.artists[0], FacetValue(id: "artist 7", label: "artist 7", count: 3))
        XCTAssertEqual(facets.artists[1], FacetValue(id: "artist 9", label: "Artist 9", count: 2))
        XCTAssertEqual(facets.artists[2].label, "Artist 1") // dann natürliche Reihenfolge
        XCTAssertEqual(facets.artists[3].label, "Artist 2")
    }

    func testFacetten_titelMitDoppeltemGenreZaehltEinmal() {
        let facets = LibraryFiltering.facets([T.make(1, genres: ["Rock", "rock", " Rock "]), T.make(2, genres: ["Pop"])])
        XCTAssertEqual(facets.genres.map(\.count), [1, 1])
        XCTAssertEqual(facets.genres.map(\.label), ["Pop", "Rock"])
        XCTAssertEqual(LibraryFiltering.genreKeys(of: T.make(3, genres: ["Rock", "rock"])), ["rock"])
        XCTAssertEqual(LibraryFiltering.genreKeys(of: T.make(4)), [GenreIndex.unknownKey])
        XCTAssertEqual(LibraryFiltering.artistKeys(of: T.make(5, artists: ["A feat. B", "C"])), ["a", "c", "b"])
    }

    // MARK: - Gruppen (Alben, Interpreten, Genres)

    func testGruppen_bleibenWennEinTitelPasst() {
        let tracks = [
            T.make(11, "1", artist: "X", album: "Alpha", genres: ["Rock"], rating: 100),
            T.make(12, "2", artist: "X", album: "Alpha", genres: ["Pop"]),
            T.make(13, "3", artist: "Y", album: "Beta", genres: ["Pop"]),
        ]
        let index = LibraryIndex.build(tracks)
        var f = LibraryFilter()
        f.quick = [.highRating]
        XCTAssertEqual(LibraryFiltering.albums(index.albums, f, index: index, ctx).map(\.title), ["Alpha"])
        XCTAssertEqual(LibraryFiltering.artists(index.artists, f, index: index, ctx).map(\.name), ["X"])
        XCTAssertEqual(LibraryFiltering.genres(index.genres, f, index: index, ctx).map(\.name), ["Rock"])
        f = LibraryFilter()
        f.genres = ["pop"]
        XCTAssertEqual(LibraryFiltering.albums(index.albums, f, index: index, ctx).map(\.title), ["Alpha", "Beta"])
        XCTAssertEqual(LibraryFiltering.genres(index.genres, f, index: index, ctx).map(\.name), ["Pop"])
        XCTAssertEqual(LibraryFiltering.artists(index.artists, f, index: index, ctx).map(\.name), ["X", "Y"])
        // leerer Filter: unverändert
        XCTAssertEqual(LibraryFiltering.albums(index.albums, LibraryFilter(), index: index, ctx), index.albums)
        XCTAssertEqual(LibraryFiltering.genres(index.genres, LibraryFilter(), index: index, ctx), index.genres)
        // Titel, die es im Index nicht gibt, passen nie
        f = LibraryFilter()
        f.quick = [.withoutCover]
        let ghost = AlbumInfo(key: "g", title: "Geist", artist: nil, isVarious: false, year: nil, genre: nil, trackUids: [999],
                              discNumbers: [], totalDurationMs: 0, sortTitle: nil, sortArtist: nil)
        XCTAssertEqual(LibraryFiltering.albums([ghost], f, index: index, ctx), [])
    }

    // MARK: - Formatfamilien

    func testFormatfamilie_ausCodecUndEndung() {
        func fam(_ codec: String?, _ ext: String) -> String { AudioFormatFamily.of(codec: codec, fileExtension: ext) }
        XCTAssertEqual(fam("AAC", "m4a"), "AAC")
        XCTAssertEqual(fam("ALAC", "m4a"), "ALAC")
        XCTAssertEqual(fam("Vorbis", "ogg"), "Ogg Vorbis")
        XCTAssertEqual(fam("Opus", "opus"), "Opus")
        XCTAssertEqual(fam("FLAC", "ogg"), "FLAC")
        XCTAssertEqual(fam("PCM", "wav"), "WAV")
        XCTAssertEqual(fam("PCM", "AIFF"), "AIFF")
        XCTAssertEqual(fam("PCM Float", "wav"), "WAV")
        XCTAssertEqual(fam("mu-law", "wav"), "WAV")
        XCTAssertEqual(fam("PCM", "caf"), "CAF")
        XCTAssertEqual(fam("PCM/INT/LIT", "mka"), "PCM")
        XCTAssertEqual(fam("MPEG/L3", "mka"), "MP3")
        XCTAssertEqual(fam("MP3", "wav"), "MP3") // MP3 im WAV-Container
        XCTAssertEqual(fam("WMA Lossless", "wma"), "WMA Lossless")
        XCTAssertEqual(fam("WMA Pro", "wma"), "WMA")
        XCTAssertEqual(fam("Monkey's Audio", "ape"), "Monkey's Audio")
        XCTAssertEqual(fam("DSD", "dsf"), "DSD")
        XCTAssertEqual(fam("AC-3", "m4a"), "AC-3")
        XCTAssertEqual(fam("  aac ", ""), "AAC")
        XCTAssertEqual(fam("MPEG-4", "m4a"), "MPEG-4") // unbekannter Codec: eigener Name
        XCTAssertEqual(fam(nil, "MP3"), "MP3")
        XCTAssertEqual(fam("", "flac"), "FLAC")
        XCTAssertEqual(fam(nil, "aif"), "AIFF")
        XCTAssertEqual(fam(nil, "xyz"), "XYZ")
        XCTAssertEqual(fam(nil, ""), AudioFormatFamily.unknown)
        XCTAssertEqual(AudioFormatFamily.of(T.make(1, codec: nil, fileName: "Song.OGG")), "Ogg Vorbis")
    }

    func testVerlustfrei() {
        func lossless(_ codec: String?, _ file: String) -> Bool { AudioFormatFamily.isLossless(T.make(1, codec: codec, fileName: file)) }
        XCTAssertTrue(lossless("FLAC", "a.flac"))
        XCTAssertTrue(lossless("ALAC", "a.m4a"))
        XCTAssertTrue(lossless("PCM", "a.wav"))
        XCTAssertTrue(lossless("PCM", "a.aiff"))
        XCTAssertTrue(lossless("PCM Float", "a.wav"))
        XCTAssertTrue(lossless("PCM", "a.caf"))
        XCTAssertTrue(lossless("WMA Lossless", "a.wma"))
        XCTAssertTrue(lossless("WavPack", "a.wv"))
        XCTAssertTrue(lossless(nil, "a.flac"))
        XCTAssertTrue(lossless(nil, "a.wav"))
        XCTAssertFalse(lossless("AAC", "a.m4a"))
        XCTAssertFalse(lossless("MP3", "a.mp3"))
        XCTAssertFalse(lossless("Vorbis", "a.ogg"))
        XCTAssertFalse(lossless("Opus", "a.opus"))
        XCTAssertFalse(lossless("WMA", "a.wma"))
        XCTAssertFalse(lossless("mu-law", "a.wav"))
        XCTAssertFalse(lossless("A-law", "a.aiff"))
        XCTAssertFalse(lossless("ADPCM", "a.wav"))
        XCTAssertFalse(lossless("MP3", "a.wav"))
        XCTAssertFalse(lossless(nil, "a.mp3"))
        XCTAssertFalse(lossless(nil, "a.m4a")) // ohne Codec: AAC angenommen
    }

    // MARK: - Automatische Playlists

    private func smartLibrary() -> [Track] {
        [
            T.make(1, "Eins", album: "A", rating: 100, dateAdded: 100),
            T.make(2, "Beta", album: "B", number: 2, rating: 80, dateAdded: 300),
            T.make(3, "Drei", album: "B", number: 1, rating: 60, dateAdded: 300),
            T.make(4, "Vier", rating: nil, dateAdded: 0),
            T.make(5, "Alpha", rating: 80, dateAdded: 200),
            T.make(6, "Sechs", rating: 0, dateAdded: 50),
        ]
    }

    private let smartStats: [Int64: PlayStats] = [
        1: PlayStats(trackUid: 1, playCount: 1, lastPlayedAt: 500),
        2: PlayStats(trackUid: 2, playCount: 1, lastPlayedAt: 900),
        3: PlayStats(trackUid: 3, playCount: 5, lastPlayedAt: 500),
        5: PlayStats(trackUid: 5, playCount: 2, lastPlayedAt: nil),
        6: PlayStats(trackUid: 6, playCount: 0, lastPlayedAt: nil),
    ]

    func testZuletztHinzugefuegt() {
        let p = SmartPlaylists.recentlyAdded(smartLibrary())
        XCTAssertEqual(p.trackUids, [3, 2, 5, 1, 6]) // gleicher Zeitpunkt: Albumreihenfolge; ohne Zeitpunkt fehlt
        XCTAssertEqual(p.id, "smart:neu")
        XCTAssertEqual(p.kind, .recentlyAdded)
        XCTAssertEqual(p.name, "Zuletzt hinzugefügt")
        XCTAssertNil(p.genreKey)
        XCTAssertEqual(SmartPlaylists.recentlyAdded(smartLibrary(), limit: 2).trackUids, [3, 2])
        XCTAssertEqual(SmartPlaylists.recentlyAdded(smartLibrary(), limit: -1).trackUids, [])
    }

    func testZuletztGespielt() {
        let p = SmartPlaylists.recentlyPlayed(smartLibrary(), stats: smartStats)
        XCTAssertEqual(p.trackUids, [2, 3, 1]) // Gleichstand 1/3: häufiger gespielt zuerst
        XCTAssertEqual(p.id, "smart:zuletzt")
        XCTAssertEqual(p.kind, .recentlyPlayed)
        XCTAssertEqual(p.name, "Zuletzt gespielt")
        XCTAssertEqual(SmartPlaylists.recentlyPlayed(smartLibrary(), stats: smartStats, limit: 1).trackUids, [2])
    }

    func testNieGespielt() {
        let p = SmartPlaylists.neverPlayed(smartLibrary(), stats: smartStats)
        XCTAssertEqual(p.trackUids, [6, 4]) // zuletzt hinzugefügte zuerst
        XCTAssertEqual(p.id, "smart:nie")
        XCTAssertEqual(p.kind, .neverPlayed)
        XCTAssertEqual(p.name, "Nie gespielt")
        // gleiche Bedingung wie der Schnellfilter
        let filterCtx = FilterContext(favorites: [], stats: smartStats, nowSeconds: 0)
        XCTAssertEqual(Set(p.trackUids), Set(smartLibrary().filter { LibraryFiltering.matches($0, .neverPlayed, filterCtx) }.map(\.uid)))
    }

    func testAmBestenBewertet() {
        let p = SmartPlaylists.topRated(smartLibrary())
        XCTAssertEqual(p.trackUids, [1, 5, 2]) // höchste zuerst, Gleichstand nach Name
        XCTAssertEqual(p.id, "smart:bewertet")
        XCTAssertEqual(p.kind, .topRated)
        XCTAssertEqual(p.name, "Am besten bewertet")
        XCTAssertEqual(p.description, "Titel mit mindestens 4 Sternen")
        XCTAssertEqual(SmartPlaylists.topRated(smartLibrary(), minRating: 60).trackUids, [1, 5, 2, 3])
        XCTAssertEqual(SmartPlaylists.topRated(smartLibrary(), minRating: 0).trackUids, [1, 5, 2, 3]) // ohne Bewertung nie
        XCTAssertEqual(SmartPlaylists.topRated(smartLibrary(), minRating: 20).description, "Titel mit mindestens 1 Stern")
        XCTAssertEqual(SmartPlaylists.topRated(smartLibrary(), minRating: 70).description, "Titel mit einer Bewertung ab 70 von 100")
    }

    func testGenrePlaylists_nachAnzahlDannName_ohneUnbekannt() {
        var tracks: [Track] = []
        var uid: Int64 = 0
        func add(_ n: Int, _ genres: [String]) {
            for _ in 0..<n {
                uid += 1
                tracks.append(T.make(uid, "T\(uid)", genres: genres))
            }
        }
        add(7, ["Rock"])
        add(5, ["rock"])
        add(9, ["Pop"])
        add(1, ["Pop", "Rock"]) // zählt nur zum ersten Genre
        add(9, ["Jazz"])
        add(9, ["Blues"])
        add(20, []) // ohne Genre: nie eine Genre-Playlist
        add(3, ["  ", "Soul"]) // erstes nicht leeres Genre
        let lists = SmartPlaylists.byGenre(tracks)
        XCTAssertEqual(lists.map(\.name), ["Genre: Rock", "Genre: Pop"])
        XCTAssertEqual(lists.map(\.id), ["smart:genre:rock", "smart:genre:pop"])
        XCTAssertEqual(lists.map(\.genreKey), ["rock", "pop"])
        XCTAssertEqual(lists.map(\.trackUids.count), [12, 10])
        XCTAssertTrue(lists.allSatisfy { $0.kind == .genre })
        // gleiche Anzahl → nach Name; höchstens maxPlaylists
        XCTAssertEqual(SmartPlaylists.byGenre(tracks, minTracks: 9).map(\.name), ["Genre: Rock", "Genre: Pop", "Genre: Blues", "Genre: Jazz"])
        XCTAssertEqual(SmartPlaylists.byGenre(tracks, minTracks: 9, maxPlaylists: 3).count, 3)
        XCTAssertEqual(SmartPlaylists.byGenre(tracks, maxPlaylists: 0), [])
        let all = SmartPlaylists.byGenre(tracks, minTracks: 1, maxPlaylists: 100)
        XCTAssertEqual(all.last?.name, "Genre: Soul")
        XCTAssertFalse(all.contains { $0.genreKey == GenreIndex.unknownKey })
        // Schlüssel wie im Genre-Index
        let index = LibraryIndex.build(tracks)
        for list in all { XCTAssertNotNil(index.genreByKey[list.genreKey!]) }
    }

    func testGenrePlaylists_reihenfolgeInnerhalb_deterministisch() {
        let tracks = [
            T.make(1, "b2", artist: "B", album: "X", genres: ["Soul"], number: 2),
            T.make(2, "a1", artist: "A", album: "Y", genres: ["Soul"], number: 1),
            T.make(3, "b1", artist: "B", album: "X", genres: ["Soul"], number: 1),
        ]
        let list = SmartPlaylists.byGenre(tracks, minTracks: 3)
        XCTAssertEqual(list.map(\.trackUids), [[2, 3, 1]])
        XCTAssertEqual(SmartPlaylists.byGenre(tracks.reversed(), minTracks: 3), list)
        XCTAssertEqual(list.first?.description, "Titel im Genre „Soul“")
    }

    func testSmartPlaylist_initOhneGenre_bleibtQuellkompatibel() {
        let p = SmartPlaylist(id: "x", kind: .decade, name: "1980er", description: "", trackUids: [], decadeStart: 1980)
        XCTAssertNil(p.genreKey)
        XCTAssertEqual(SmartKind(rawValue: "TOP_RATED"), .topRated)
        XCTAssertEqual(SmartKind.genre.rawValue, "GENRE")
    }
}
