import XCTest
@testable import MLCore

/// Testtitel mit allen v2-relevanten Feldern (Bewertung, BPM, Hinzugefügt, Codec, Liedtext, Cover …).
enum V2Tracks {
    static func make(
        _ uid: Int64,
        _ title: String? = "Titel",
        artist: String? = nil,
        artists: [String]? = nil,
        album: String? = nil,
        albumArtist: String? = nil,
        genres: [String] = [],
        year: Int? = nil,
        disc: Int? = nil,
        number: Int? = nil,
        rating: Int? = nil,
        bpm: Int? = nil,
        dateAdded: Int64 = 0,
        codec: String? = nil,
        fileName: String? = nil,
        folder: String = "Music/",
        hasPicture: Bool = true,
        hasLyrics: Bool = false,
        albumSort: String? = nil,
        albumArtistSort: String? = nil,
        titleSort: String? = nil
    ) -> Track {
        let name = fileName ?? "\(title ?? "unbenannt")-\(uid).mp3"
        return Track(
            uid: uid, folderID: 0, path: "/Musik/\(folder)\(name)", relativePath: folder, fileName: name,
            title: title, artists: artists ?? [artist].compactMap { $0 }, album: album,
            albumArtists: [albumArtist].compactMap { $0 }, genres: genres, year: year, trackNumber: number,
            discNumber: disc, bpm: bpm, rating: rating, durationMs: 180_000, dateAdded: dateAdded, codec: codec,
            titleSort: titleSort, albumSort: albumSort, albumArtistSort: albumArtistSort,
            hasPicture: hasPicture, hasLyrics: hasLyrics
        )
    }
}

/// v2: neue Sortierfelder (Album, Albuminterpret, Hinzugefügt, Bewertung, BPM; Alben nach Hinzugefügt und
/// Titelanzahl; Interpreten nach Albenanzahl; Playlists nach Erstellt/Geändert; Favoriten).
final class V2SortingTests: XCTestCase {

    private typealias T = V2Tracks

    // MARK: - Felder, Namen, Speicherformat

    func testNeueFelder_hintenAngefuegt_gespeicherteNamenBleibenGueltig() {
        XCTAssertEqual(TrackSort.allCases.map(\.rawValue),
                       ["TITLE", "DURATION", "LAST_PLAYED", "PLAY_COUNT", "GENRE", "ARTIST", "YEAR",
                        "ALBUM", "ALBUM_ARTIST", "DATE_ADDED", "RATING", "BPM"])
        XCTAssertEqual(AlbumSort.allCases.map(\.rawValue),
                       ["TITLE", "DURATION", "LAST_PLAYED", "PLAY_COUNT", "GENRE", "ARTIST", "YEAR", "DATE_ADDED", "TRACK_COUNT"])
        XCTAssertEqual(ArtistSort.allCases.map(\.rawValue), ["NAME", "TRACK_COUNT", "ALBUM_COUNT"])
        XCTAssertEqual(PlaylistSort.allCases.map(\.rawValue), ["NAME", "TRACK_COUNT", "CREATED", "MODIFIED"])
        XCTAssertEqual(FavoriteTrackSort.allCases.map(\.rawValue), ["TITLE", "ARTIST", "ALBUM", "ADDED", "DATE_ADDED", "RATING"])
        XCTAssertEqual(GenreSort.allCases.map(\.rawValue), ["NAME", "TRACK_COUNT"])

        XCTAssertEqual(Sort<TrackSort>(storageValue: "ALBUM_ARTIST:desc"), Sort(TrackSort.albumArtist, descending: true))
        XCTAssertEqual(Sort<AlbumSort>(storageValue: "TRACK_COUNT:asc"), Sort(AlbumSort.trackCount, descending: false))
        XCTAssertEqual(Sort<PlaylistSort>(storageValue: "MODIFIED:desc")?.field, .modified)
        XCTAssertEqual(Sort(TrackSort.rating, descending: true).storageValue, "RATING:desc")
    }

    func testNeueFelder_beschriftungUndUeblicheRichtung() {
        XCTAssertEqual(Sort(TrackSort.dateAdded).label, "Hinzugefügt · neueste zuerst")
        XCTAssertEqual(Sort(TrackSort.rating).label, "Bewertung · höchste zuerst")
        XCTAssertEqual(Sort(TrackSort.bpm).label, "Tempo (BPM) · langsamste zuerst")
        XCTAssertEqual(Sort(TrackSort.album).label, "Album · A–Z")
        XCTAssertEqual(Sort(TrackSort.albumArtist, descending: true).label, "Albuminterpret · Z–A")
        XCTAssertEqual(Sort(AlbumSort.trackCount).label, "Anzahl der Titel · meiste zuerst")
        XCTAssertEqual(Sort(AlbumSort.dateAdded, descending: false).label, "Hinzugefügt · älteste zuerst")
        XCTAssertEqual(Sort(ArtistSort.albumCount).label, "Anzahl der Alben · meiste zuerst")
        XCTAssertEqual(Sort(PlaylistSort.created).label, "Erstellt · neueste zuerst")
        XCTAssertEqual(Sort(PlaylistSort.modified, descending: false).label, "Zuletzt geändert · älteste zuerst")
        XCTAssertEqual(Sort(FavoriteTrackSort.dateAdded).label, "Zur Bibliothek hinzugefügt · neueste zuerst")
        XCTAssertEqual(Sort(FavoriteTrackSort.rating).label, "Bewertung · höchste zuerst")
        // bestehende Felder unverändert
        XCTAssertFalse(PlaylistSort.name.defaultDescending)
        XCTAssertTrue(PlaylistSort.trackCount.defaultDescending)
        XCTAssertFalse(ArtistSort.name.defaultDescending)
        XCTAssertEqual(Sort(PlaylistSort.name).label, "Playlistname · A–Z")
        XCTAssertEqual(Sort(ArtistSort.trackCount).label, "Anzahl der Titel · meiste zuerst")
        for field in TrackSort.allCases {
            XCTAssertFalse(field.label.isEmpty)
            XCTAssertFalse(field.ascendingLabel.isEmpty)
            XCTAssertFalse(field.descendingLabel.isEmpty)
        }
    }

    // MARK: - Titel

    private func ids(_ items: [Track], _ field: TrackSort, _ desc: Bool) -> [Int64] {
        Sorting.tracks(items, sort: Sort(field, descending: desc), stats: [:]).map(\.uid)
    }

    func testTitel_nachAlbum_inAlbumreihenfolge_ohneAlbumAmEnde() {
        let items = [
            T.make(1, "Zeta", album: "Beta", number: 1),
            T.make(2, "Alpha", album: "Beta", number: 2),
            T.make(3, "Song", album: "alpha", number: 1),
            T.make(4, "Ohne Album"),
            T.make(5, "Aaa", album: "Beta", disc: 2, number: 1),
            T.make(6, "Leer", album: "   "),
        ]
        // innerhalb des Albums Disc → Track (nicht Titelname); ohne Album in beiden Richtungen am Ende
        XCTAssertEqual(ids(items, .album, false), [3, 1, 2, 5, 6, 4])
        XCTAssertEqual(ids(items, .album, true), [1, 2, 5, 3, 6, 4])
    }

    func testTitel_nachAlbum_sortierTagUndGleichnamigeAlbenGetrennt() {
        let items = [
            T.make(1, "Q1", artist: "Queen", album: "Greatest Hits", albumArtist: "Queen", number: 1),
            T.make(2, "A2", artist: "ABBA", album: "Greatest Hits", albumArtist: "ABBA", number: 2),
            T.make(3, "A1", artist: "ABBA", album: "Greatest Hits", albumArtist: "ABBA", number: 1),
            T.make(4, "Q2", artist: "Queen", album: "Greatest Hits", albumArtist: "Queen", number: 2),
            T.make(5, "G", album: "The Gamma", albumSort: "Gamma"),
            T.make(6, "H", album: "Hotel"),
        ]
        // gleicher Albumname: nach Album-Interpret getrennt, jeweils in Trackreihenfolge; „The Gamma“ unter G
        XCTAssertEqual(ids(items, .album, false), [5, 3, 2, 1, 4, 6])
    }

    func testTitel_nachAlbuminterpret_ersatzweiseInterpret() {
        let items = [
            T.make(1, "x", artist: "Freddie", album: "B", albumArtist: "Queen", number: 1),
            T.make(2, "y", artist: "ABBA", album: "X"),
            T.make(3, "z", artist: "Brian", album: "A", albumArtist: "Queen", number: 2),
            T.make(4, "ohne", album: "C"),
            T.make(5, "w", artist: "Roger", album: "A", albumArtist: "Queen", number: 1),
            T.make(6, "v", artist: "Beatles", album: "Help", albumArtist: "The Beatles", albumArtistSort: "Beatles"),
        ]
        // ABBA (Interpret, kein Album-Interpret-Tag), Beatles (Sortier-Tag), Queen: Album A (1, 2), Album B; ohne zuletzt
        XCTAssertEqual(ids(items, .albumArtist, false), [2, 6, 5, 3, 1, 4])
        XCTAssertEqual(ids(items, .albumArtist, true), [5, 3, 1, 6, 2, 4])
    }

    func testTitel_nachHinzugefuegtBewertungBpm_fehlendeWerteInBeidenRichtungenAmEnde() {
        let items = [
            T.make(1, "C", rating: 60, bpm: 120, dateAdded: 300),
            T.make(2, "A", rating: nil, bpm: nil, dateAdded: 0),
            T.make(3, "B", rating: 100, bpm: 90, dateAdded: 100),
            T.make(4, "A2", rating: 60, bpm: 0, dateAdded: 300),
            T.make(5, "D", rating: 0, bpm: 200, dateAdded: -5),
        ]
        // Gleichstand (1 und 4: gleicher Zeitpunkt/gleiche Bewertung) immer nach Name aufsteigend
        XCTAssertEqual(ids(items, .dateAdded, false), [3, 4, 1, 2, 5])
        XCTAssertEqual(ids(items, .dateAdded, true), [4, 1, 3, 2, 5])
        // Bewertung 0 = keine Bewertung (wie beim Lesen der Tags)
        XCTAssertEqual(ids(items, .rating, true), [3, 4, 1, 2, 5])
        XCTAssertEqual(ids(items, .rating, false), [4, 1, 3, 2, 5])
        // BPM 0 = unbekannt
        XCTAssertEqual(ids(items, .bpm, false), [3, 1, 5, 2, 4])
        XCTAssertEqual(ids(items, .bpm, true), [5, 1, 3, 2, 4])
    }

    func testTitel_gleicheWerte_stabilNachNameDannKennung() {
        let items = [
            T.make(9, "Gleich", rating: 80),
            T.make(3, "Gleich", rating: 80),
            T.make(5, "Anders", rating: 80),
        ]
        XCTAssertEqual(ids(items, .rating, true), [5, 3, 9])
        XCTAssertEqual(ids(items, .rating, false), [5, 3, 9])
        XCTAssertEqual(ids([], .album, false), [])
    }

    func testBestehendeTitelSortierung_unveraendert() {
        let a = T.make(1, "Bravo", artist: "Zed", genres: ["Rock"], year: 1980)
        let b = T.make(2, "alpha", artist: "Abba", year: nil)
        let c = T.make(3, "Ärger", artist: "Mia", genres: ["Pop"], year: 2000)
        XCTAssertEqual(ids([a, b, c], .title, false), [2, 3, 1])
        XCTAssertEqual(ids([a, b, c], .year, false), [1, 3, 2])
        XCTAssertEqual(ids([a, b, c], .genre, true), [1, 3, 2])
    }

    // MARK: - Alben

    func testAlben_hinzugefuegtIstJuengsterTitel_undSortierungNachHinzugefuegtUndAnzahl() {
        let tracks = [
            T.make(1, "a", artist: "X", album: "Alt", dateAdded: 100),
            T.make(2, "b", artist: "X", album: "Alt", dateAdded: 500),
            T.make(3, "c", artist: "X", album: "Neu", dateAdded: 900),
            T.make(4, "d", artist: "X", album: "Ohne", dateAdded: 0),
            T.make(5, "e", artist: "X", album: "Ohne", dateAdded: 0),
            T.make(6, "f", artist: "X", album: "Ohne", dateAdded: 0),
        ]
        let index = LibraryIndex.build(tracks)
        let byTitle = Dictionary(uniqueKeysWithValues: index.albums.map { ($0.title ?? "", $0) })
        XCTAssertEqual(byTitle["Alt"]?.dateAdded, 500)
        XCTAssertEqual(byTitle["Neu"]?.dateAdded, 900)
        XCTAssertEqual(byTitle["Ohne"]?.dateAdded, 0)
        func titles(_ field: AlbumSort, _ desc: Bool) -> [String?] {
            Sorting.albums(index.albums, sort: Sort(field, descending: desc), stats: [:]).map(\.title)
        }
        XCTAssertEqual(titles(.dateAdded, true), ["Neu", "Alt", "Ohne"])
        XCTAssertEqual(titles(.dateAdded, false), ["Alt", "Neu", "Ohne"]) // unbekannt auch aufsteigend am Ende
        XCTAssertEqual(titles(.trackCount, true), ["Ohne", "Alt", "Neu"])
        XCTAssertEqual(titles(.trackCount, false), ["Neu", "Alt", "Ohne"])
    }

    func testAlbumInfo_initOhneHinzugefuegt_bleibtQuellkompatibel() {
        let a = AlbumInfo(key: "k", title: "T", artist: nil, isVarious: false, year: nil, genre: nil, trackUids: [1],
                          discNumbers: [], totalDurationMs: 0, sortTitle: nil, sortArtist: nil)
        XCTAssertEqual(a.dateAdded, 0)
        let b = AlbumInfo(key: "k", title: "T", artist: nil, isVarious: false, year: nil, genre: nil, trackUids: [1],
                          discNumbers: [], totalDurationMs: 0, sortTitle: nil, sortArtist: nil, dateAdded: 42)
        XCTAssertEqual(b.dateAdded, 42)
    }

    // MARK: - Interpreten

    func testInterpreten_nachAlbenanzahl() {
        let tracks = [
            T.make(1, "1", artist: "A", album: "A1"),
            T.make(2, "2", artist: "A", album: "A2"),
            T.make(3, "3", artist: "A", album: "A2"),
            T.make(4, "4", artist: "B", album: "B1"),
            T.make(5, "5", artist: "B", album: "B1"),
            T.make(6, "6", artist: "B", album: "B1"),
            T.make(7, "7", artist: "B", album: "B1"),
            T.make(8, "8", artist: "C", album: "C1"),
        ]
        let index = LibraryIndex.build(tracks)
        XCTAssertEqual(index.artistByKey["a"]?.albumCount, 2)
        XCTAssertEqual(index.artistByKey["b"]?.albumCount, 1)
        func names(_ field: ArtistSort, _ desc: Bool) -> [String] {
            Sorting.artists(index.artists, sort: Sort(field, descending: desc)).map(\.name)
        }
        XCTAssertEqual(names(.albumCount, true), ["A", "B", "C"]) // Gleichstand B/C nach Name
        XCTAssertEqual(names(.albumCount, false), ["B", "C", "A"])
        XCTAssertEqual(names(.trackCount, true), ["B", "A", "C"])
    }

    // MARK: - Playlists

    func testPlaylists_nachErstelltUndGeaendert_unbekanntAmEnde() {
        struct P { let name: String; let count: Int; let created: Int64; let modified: Int64 }
        let items = [
            P(name: "Zug", count: 3, created: 300, modified: 400),
            P(name: "auto", count: 10, created: 100, modified: 900),
            P(name: "Bahn", count: 1, created: 0, modified: 500),
        ]
        func names(_ field: PlaylistSort, _ desc: Bool) -> [String] {
            Sorting.playlists(items, sort: Sort(field, descending: desc), name: { $0.name }, count: { $0.count },
                              created: { $0.created }, modified: { $0.modified }).map(\.name)
        }
        XCTAssertEqual(names(.created, true), ["Zug", "auto", "Bahn"])
        XCTAssertEqual(names(.created, false), ["auto", "Zug", "Bahn"])
        XCTAssertEqual(names(.modified, true), ["auto", "Bahn", "Zug"])
        XCTAssertEqual(names(.modified, false), ["Zug", "Bahn", "auto"])
        XCTAssertEqual(names(.trackCount, true), ["auto", "Zug", "Bahn"])
        // ohne Zeitpunkte (Standardwerte der Parameter): nach Name, in beiden Richtungen
        for desc in [false, true] {
            XCTAssertEqual(Sorting.playlists(items, sort: Sort(PlaylistSort.created, descending: desc), name: { $0.name }, count: { $0.count }).map(\.name),
                           ["auto", "Bahn", "Zug"])
        }
    }

    // MARK: - Favoriten

    func testFavoritenTitel_nachHinzugefuegtUndBewertung() {
        let items = [
            T.make(1, "B", rating: 40, dateAdded: 50),
            T.make(2, "A", rating: nil, dateAdded: 0),
            T.make(3, "C", rating: 100, dateAdded: 700),
        ]
        func ids(_ field: FavoriteTrackSort, _ desc: Bool) -> [Int64] {
            Sorting.favoriteTracks(items, sort: Sort(field, descending: desc), addedAt: [:]).map(\.uid)
        }
        XCTAssertEqual(ids(.dateAdded, true), [3, 1, 2])
        XCTAssertEqual(ids(.dateAdded, false), [1, 3, 2])
        XCTAssertEqual(ids(.rating, true), [3, 1, 2])
        XCTAssertEqual(ids(.rating, false), [1, 3, 2])
    }

    func testEinstellungen_speichernNeueSortierungen() {
        var s = AppSettings()
        s.trackSort = Sort(.bpm, descending: true)
        s.albumSort = Sort(.trackCount, descending: false)
        s.artistSort = Sort(.albumCount, descending: true)
        s.playlistSort = Sort(.modified, descending: true)
        s.favoriteTrackSort = Sort(.rating, descending: false)
        let reloaded = AppSettings.decode(from: s.encoded())
        XCTAssertEqual(reloaded, s)
        let json = String(decoding: s.encoded(), as: UTF8.self)
        XCTAssertTrue(json.contains(#""trackSort" : "BPM:desc""#))
        XCTAssertTrue(json.contains(#""artistSort" : "ALBUM_COUNT:desc""#))
    }
}
