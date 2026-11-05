import XCTest
@testable import MLCore

/// Portierung von `library/LibraryLogicTest.kt`.
final class LibraryLogicTests: XCTestCase {

    private func track(
        _ title: String? = "Titel", _ artist: String? = nil, _ album: String? = nil, _ albumArtist: String? = nil,
        genre: String? = nil, year: Int? = nil, durationMs: Int64 = 180_000, uid: Int64? = nil,
        genres: [String]? = nil, artistSort: String? = nil
    ) -> Track {
        TestTracks.track(title, artist, album, albumArtist, genre: genre, year: year, durationMs: durationMs,
                         uid: uid, genres: genres, artistSort: artistSort)
    }

    // MARK: - Interpreten

    func testInterpreten_feat_wirdGetrennt_bandnamenNicht() {
        XCTAssertEqual(ArtistNames.split("Calvin Harris feat. Rihanna"), ArtistNames.Split(primary: "Calvin Harris", guests: ["Rihanna"]))
        XCTAssertEqual(ArtistNames.split("A (feat. B & C)"), ArtistNames.Split(primary: "A", guests: ["B", "C"]))
        XCTAssertEqual(ArtistNames.split("A ft. B"), ArtistNames.Split(primary: "A", guests: ["B"]))
        XCTAssertEqual(ArtistNames.split("Simon & Garfunkel").primary, "Simon & Garfunkel")
        XCTAssertEqual(ArtistNames.split("AC/DC").primary, "AC/DC")
        XCTAssertEqual(ArtistNames.split("Earth, Wind & Fire").primary, "Earth, Wind & Fire")
        XCTAssertEqual(ArtistNames.split("Featurette").primary, "Featurette")
        XCTAssertTrue(ArtistNames.isVarious("Various Artists"))
        XCTAssertTrue(ArtistNames.isVarious("Verschiedene Interpreten"))
        XCTAssertFalse(ArtistNames.isVarious("Queen"))
    }

    func testInterpreten_weitereSchreibweisen() {
        XCTAssertEqual(ArtistNames.split("A featuring B, C und D"), ArtistNames.Split(primary: "A", guests: ["B", "C", "D"]))
        XCTAssertEqual(ArtistNames.split("A [Feat. B and C]"), ArtistNames.Split(primary: "A", guests: ["B", "C"]))
        XCTAssertEqual(ArtistNames.split("A FT. Brandon"), ArtistNames.Split(primary: "A", guests: ["Brandon"]))
        XCTAssertEqual(ArtistNames.split("Defeat Machine").primary, "Defeat Machine")
        XCTAssertEqual(ArtistNames.split("feat. X"), ArtistNames.Split(primary: "feat. X", guests: []))
        XCTAssertEqual(ArtistNames.split("A feat.B").guests, []) // ohne Leerzeichen keine Gastnennung
        XCTAssertTrue(ArtistNames.isVarious("V.A."))
        XCTAssertTrue(ArtistNames.isVarious("Verschiedene Künstler"))
        XCTAssertFalse(ArtistNames.isVarious(nil))
    }

    func testInterpretenIndex_ohneDubletten_mitGaestenUndAlbumInterpret() {
        let tracks = [
            track("1", "Queen", "A", "Queen", uid: 1),
            track("2", "queen", "A", "Queen", uid: 2),
            track("3", "Calvin Harris feat. Rihanna", "B", uid: 3),
            track("4", "Elton John & Kiki Dee", "Duets", "Elton John", uid: 4),
            track("5", "X", "Sampler", "Various Artists", uid: 5),
        ]
        let index = LibraryIndex.build(tracks)
        let names = Set(index.artists.map(\.name))
        XCTAssertEqual(names, ["Queen", "Calvin Harris", "Rihanna", "Elton John & Kiki Dee", "Elton John", "X"])
        XCTAssertEqual(index.artistByKey["queen"]?.trackCount, 2)
        XCTAssertEqual(index.artistByKey["rihanna"]?.trackUids, [3])
        XCTAssertEqual(index.artistByKey["elton john"]?.trackUids, [4])
    }

    // MARK: - Genres

    func testGenres_nachTags_mehrfachUndUnbekannt() {
        let tracks = [
            track("1", genre: "Rock", uid: 1),
            track("2", uid: 2, genres: ["Rock", "Pop"]),
            track("3", genre: "rock", uid: 3),
            track("4", genre: nil, uid: 4),
        ]
        let genres = GenreIndex.build(tracks)
        let rock = genres.first { $0.key == "rock" }!
        XCTAssertEqual(rock.name, "Rock")
        XCTAssertEqual(rock.trackUids, [1, 2, 3])
        XCTAssertEqual(genres.first { $0.key == "pop" }?.trackUids, [2])
        let unknown = genres.first(where: \.isUnknown)!
        XCTAssertEqual(unknown.name, GenreIndex.unknownName)
        XCTAssertEqual(unknown.trackUids, [4])
        XCTAssertEqual(unknown.category, .unknown)
    }

    func testGenreIcons_feste_zuordnung() {
        XCTAssertEqual(GenreCategories.of("Rock"), .rock)
        XCTAssertEqual(GenreCategories.of("Classic Rock"), .rock)
        XCTAssertEqual(GenreCategories.of("Klassik"), .classical)
        XCTAssertEqual(GenreCategories.of("Classical"), .classical)
        XCTAssertEqual(GenreCategories.of("Hip-Hop/Rap"), .hiphop)
        XCTAssertEqual(GenreCategories.of("Heavy Metal"), .metal)
        XCTAssertEqual(GenreCategories.of("Indie Rock"), .alternative)
        XCTAssertEqual(GenreCategories.of("Techno"), .electronic)
        XCTAssertEqual(GenreCategories.of("Soundtrack"), .soundtrack)
        XCTAssertEqual(GenreCategories.of("Hörbuch"), .spoken)
        XCTAssertEqual(GenreCategories.of("Volkstümliche Musik"), .schlager)
        XCTAssertEqual(GenreCategories.of("Jazz"), .jazz)
        XCTAssertEqual(GenreCategories.of("R&B/Soul"), .soulFunk)
        XCTAssertEqual(GenreCategories.of("Pop"), .pop)
        XCTAssertEqual(GenreCategories.of("Gregorianik"), .other)
        // Genres mit eigenem Titelbild – nur aus dem Genre-Text, als ganzes Wort
        XCTAssertEqual(GenreCategories.of("Darkwave"), .darkwave)
        XCTAssertEqual(GenreCategories.of("Dark Wave"), .darkwave)
        XCTAssertEqual(GenreCategories.of("Hardstyle"), .hardstyle)
        XCTAssertEqual(GenreCategories.of("Hardtekk"), .hardtekk)
        XCTAssertEqual(GenreCategories.of("Hard Tekk"), .hardtekk)
        XCTAssertEqual(GenreCategories.of("Hymnen"), .anthems)
        XCTAssertEqual(GenreCategories.of("Sounds"), .sounds)
        XCTAssertEqual(GenreCategories.of("Soundtrack"), .soundtrack) // nicht „Sounds“
        XCTAssertEqual(GenreCategories.of("Hard Rock"), .rock) // nicht Hardstyle
        XCTAssertEqual(GenreCategories.of("New Wave"), .alternative) // nicht Darkwave
        XCTAssertEqual(GenreCategories.of(nil), .unknown)
        XCTAssertEqual(GenreCategories.of("  "), .unknown)
    }

    func testGenrePalette_wieAndroid() {
        // Reihenfolge der Kategorien = Kotlin-Ordinalzahl
        XCTAssertEqual(GenreCategory.rock.rawValue, 0)
        XCTAssertEqual(GenreCategory.unknown.rawValue, 26)
        XCTAssertEqual(GenreCategory.sounds.rawValue, 31)
        XCTAssertEqual(GenrePalette.forCategory(.rock), 0xFFD4_566F)
        XCTAssertEqual(GenrePalette.forCategory(.soulFunk), 0xFF8C_5F9E) // Ordinalzahl 6
        XCTAssertEqual(GenrePalette.forCategory(.unknown), GenrePalette.unknownTone)
        // String.hashCode der JVM: "rock".hashCode() = 3506021, "hip-hop".hashCode() = 922041611
        XCTAssertEqual("rock".javaHashCode, 3_506_021)
        XCTAssertEqual("hip-hop".javaHashCode, 922_041_611)
        XCTAssertEqual(GenrePalette.forText("Rock"), GenrePalette.tones[3_506_021 % 10])
        XCTAssertEqual("".javaHashCode, 0)
        XCTAssertEqual("äöü".javaHashCode, 226_986)
    }

    // MARK: - Sortierung

    func testTitelSortierung_alleFelder_fehlendeWerteAmEnde() {
        let a = track("Bravo", "Zed", genre: "Rock", year: 1980, durationMs: 200_000, uid: 1)
        let b = track("alpha", "Abba", genre: nil, year: nil, durationMs: 100_000, uid: 2)
        let c = track("Ärger", "Mia", genre: "Pop", year: 2000, durationMs: 300_000, uid: 3)
        let items = [a, b, c]
        let stats: [Int64: PlayStats] = [1: PlayStats(trackUid: 1, playCount: 5, lastPlayedAt: 1000), 3: PlayStats(trackUid: 3, playCount: 2, lastPlayedAt: 5000)]
        func ids(_ field: TrackSort, _ desc: Bool) -> [Int64] { Sorting.tracks(items, sort: Sort(field, descending: desc), stats: stats).map(\.uid) }
        XCTAssertEqual(ids(.title, false), [2, 3, 1]) // alpha, Ärger, Bravo
        XCTAssertEqual(ids(.title, true), [1, 3, 2])
        XCTAssertEqual(ids(.duration, false), [2, 1, 3])
        XCTAssertEqual(ids(.lastPlayed, true), [3, 1, 2]) // nie gespielt am Ende
        XCTAssertEqual(ids(.lastPlayed, false), [1, 3, 2]) // auch aufsteigend am Ende
        XCTAssertEqual(ids(.playCount, true), [1, 3, 2])
        XCTAssertEqual(ids(.genre, false), [3, 1, 2]) // Pop, Rock, (ohne)
        XCTAssertEqual(ids(.genre, true), [1, 3, 2]) // Rock, Pop, (ohne)
        XCTAssertEqual(ids(.artist, false), [2, 3, 1])
        XCTAssertEqual(ids(.year, true), [3, 1, 2])
        XCTAssertEqual(ids(.year, false), [1, 3, 2])
    }

    func testSortierTagsVonItunesWerdenVerwendet() {
        let beatles = track("Help", "The Beatles", uid: 1, artistSort: "Beatles")
        let cure = track("Lullaby", "The Cure", uid: 2, artistSort: "Cure")
        let abba = track("Waterloo", "ABBA", uid: 3)
        let sorted = Sorting.tracks([cure, abba, beatles], sort: Sort(TrackSort.artist, descending: false), stats: [:])
        XCTAssertEqual(sorted.map(\.uid), [3, 1, 2])
    }

    func testAlbumSortierung_statistikAusTiteln() {
        let tracks = [
            track("1", "X", "Alpha", year: 1990, uid: 1),
            track("2", "X", "Alpha", year: 1990, uid: 2),
            track("3", "Y", "Beta", year: 2010, uid: 3),
        ]
        let index = LibraryIndex.build(tracks)
        let stats: [Int64: PlayStats] = [
            1: PlayStats(trackUid: 1, playCount: 1, lastPlayedAt: 100),
            2: PlayStats(trackUid: 2, playCount: 1, lastPlayedAt: 900),
            3: PlayStats(trackUid: 3, playCount: 3, lastPlayedAt: 500),
        ]
        let alpha = index.albums.first { $0.title == "Alpha" }!
        XCTAssertEqual(Sorting.albumLastPlayed(alpha, stats: stats), 900)
        XCTAssertEqual(Sorting.albumPlayCount(alpha, stats: stats), 2)
        XCTAssertEqual(Sorting.albums(index.albums, sort: Sort(AlbumSort.lastPlayed, descending: true), stats: stats).map(\.title), ["Alpha", "Beta"])
        XCTAssertEqual(Sorting.albums(index.albums, sort: Sort(AlbumSort.playCount, descending: true), stats: stats).map(\.title), ["Beta", "Alpha"])
        XCTAssertEqual(Sorting.albums(index.albums, sort: Sort(AlbumSort.year, descending: true), stats: stats).map(\.title), ["Beta", "Alpha"])
    }

    func testInterpretenUndGenres_nachAnzahl() {
        let tracks = [track("1", "A", genre: "Jazz"), track("2", "B", genre: "Rock"), track("3", "B", genre: "Rock"), track("4", "C", genre: nil)]
        let index = LibraryIndex.build(tracks)
        XCTAssertEqual(Sorting.artists(index.artists, sort: Sort(ArtistSort.trackCount, descending: true)).first?.name, "B")
        let genres = Sorting.genres(index.genres, sort: Sort(GenreSort.trackCount, descending: true))
        XCTAssertEqual(genres.first?.name, "Rock")
        XCTAssertTrue(genres.last!.isUnknown) // „Unbekanntes Genre“ immer am Ende
        XCTAssertTrue(Sorting.genres(index.genres, sort: Sort(GenreSort.name, descending: true)).last!.isUnknown)
    }

    func testFavoritenSortierung() {
        let a = track("B-Titel", "Z", "Album 1", uid: 1)
        let b = track("A-Titel", "Y", "Album 2", uid: 2)
        let added: [Int64: Int64] = [1: 200, 2: 100]
        XCTAssertEqual(Sorting.favoriteTracks([a, b], sort: Sort(FavoriteTrackSort.title, descending: false), addedAt: added).map(\.uid), [2, 1])
        XCTAssertEqual(Sorting.favoriteTracks([a, b], sort: Sort(FavoriteTrackSort.added, descending: true), addedAt: added).map(\.uid), [1, 2])
        XCTAssertEqual(Sorting.favoriteTracks([a, b], sort: Sort(FavoriteTrackSort.artist, descending: false), addedAt: added).map(\.uid), [2, 1])
        let index = LibraryIndex.build([a, b])
        var favs: [String: FavoriteAlbum] = [:]
        for album in index.albums {
            favs[album.key] = FavoriteAlbum(albumKey: album.key, title: album.title, artist: album.artist, addedAt: album.title == "Album 1" ? 5 : 9)
        }
        XCTAssertEqual(Sorting.favoriteAlbums(index.albums, sort: Sort(FavoriteAlbumSort.added, descending: true), favorites: favs).map(\.title), ["Album 2", "Album 1"])
    }

    func testPlaylistSortierung() {
        struct P { let name: String; let count: Int }
        let items = [P(name: "Zug", count: 3), P(name: "auto", count: 10), P(name: "Bahn", count: 1)]
        XCTAssertEqual(Sorting.playlists(items, sort: Sort(PlaylistSort.name, descending: false), name: { $0.name }, count: { $0.count }).map(\.name), ["auto", "Bahn", "Zug"])
        XCTAssertEqual(Sorting.playlists(items, sort: Sort(PlaylistSort.trackCount, descending: true), name: { $0.name }, count: { $0.count }).map(\.name), ["auto", "Zug", "Bahn"])
    }

    func testSortLabelUndSpeicherformat() {
        let s = Sort(TrackSort.year, descending: true)
        XCTAssertEqual(s.label, "Veröffentlichungsjahr · neueste zuerst")
        XCTAssertEqual(s.storageValue, "YEAR:desc")
        XCTAssertEqual(Sort<TrackSort>(storageValue: "YEAR:desc"), s)
        XCTAssertEqual(Sort<TrackSort>(storageValue: "TITLE"), Sort(TrackSort.title, descending: false))
        XCTAssertNil(Sort<TrackSort>(storageValue: "GIBTESNICHT:desc"))
        XCTAssertEqual(Sort(TrackSort.playCount), Sort(TrackSort.playCount, descending: true))
    }

    // MARK: - Suche

    func testSuche_titelInterpretAlbumGenre_undAkzente() {
        let tracks = [
            track("Hey Jude", "The Beatles", "1", genre: "Pop", uid: 1),
            track("Jóga", "Björk", "Homogenic", genre: "Electronic", uid: 2),
        ]
        let index = LibraryIndex.build(tracks)
        func hits(_ q: String) -> [Int64] {
            tracks.filter { TextNorm.matchesAll(TextNorm.searchTerms(q), index.trackSearchText[$0.uid]!) }.map(\.uid)
        }
        XCTAssertEqual(hits("jude"), [1])
        XCTAssertEqual(hits("beatles hey"), [1])
        XCTAssertEqual(hits("bjork"), [2])
        XCTAssertEqual(hits("JOGA"), [2])
        XCTAssertEqual(hits("electronic"), [2])
        XCTAssertEqual(hits("homogenic"), [2])
        XCTAssertEqual(hits(""), [1, 2])
        XCTAssertEqual(hits("beatles electronic"), [])
        XCTAssertEqual(index.searchTracks("björk joga").map(\.uid), [2])
    }

    func testAlbumSuche_auchNachTrackInterpretUndGenre() {
        let tracks = [
            track("1", "Artist A", "Sampler", "Various Artists", genre: "Dance"),
            track("2", "Artist B", "Sampler", "Various Artists", genre: "Dance"),
        ]
        let index = LibraryIndex.build(tracks)
        XCTAssertEqual(index.albumSearchText.count, 1)
        let text = index.albumSearchText.values.first!
        XCTAssertTrue(TextNorm.matchesAll(TextNorm.searchTerms("artist b"), text))
        XCTAssertTrue(TextNorm.matchesAll(TextNorm.searchTerms("dance sampler"), text))
    }

    // MARK: - Dynamische Playlists

    func testFavoritenPlaylist_stabileReihenfolge_nurVerfuegbare() {
        let list = [track("a", uid: 1), track("b", uid: 2), track("c", uid: 3)]
        let tracks = Dictionary(uniqueKeysWithValues: list.map { ($0.uid, $0) })
        let favs = [FavoriteTrack(trackUid: 3, addedAt: 100), FavoriteTrack(trackUid: 1, addedAt: 50), FavoriteTrack(trackUid: 2, addedAt: 100), FavoriteTrack(trackUid: 99, addedAt: 10)]
        let p = SmartPlaylists.favorites(favs, available: tracks)
        XCTAssertEqual(p.trackUids, [1, 2, 3]) // nach Favorisierungszeit, bei Gleichstand nach Kennung
        XCTAssertEqual(p.kind, .favorites)
    }

    func testMeistUndWenigstGespielt() {
        let tracks = (1...5).map { track("T\($0)", uid: Int64($0)) }
        let stats: [Int64: PlayStats] = [
            1: PlayStats(trackUid: 1, playCount: 10, lastPlayedAt: 100),
            2: PlayStats(trackUid: 2, playCount: 3, lastPlayedAt: 900),
            3: PlayStats(trackUid: 3, playCount: 3, lastPlayedAt: 500),
        ]
        XCTAssertEqual(SmartPlaylists.mostPlayed(tracks, stats: stats).trackUids, [1, 2, 3])
        // nie gespielt (4, 5) zuerst, dann wenigste Wiedergaben; Gleichstand: länger nicht gespielt zuerst
        XCTAssertEqual(SmartPlaylists.leastPlayed(tracks, stats: stats).trackUids, [4, 5, 3, 2, 1])
        XCTAssertEqual(SmartPlaylists.mostPlayed(tracks, stats: stats, limit: 2).trackUids.count, 2)
    }

    func testJahrzehnte_nurMitBekanntemJahr() {
        let tracks = [
            track("a", year: 1975, uid: 1),
            track("b", year: 1979, uid: 2),
            track("c", year: 1980, uid: 3),
            track("d", year: 2015, uid: 4),
            track("e", year: nil, uid: 5),
            track("f", year: 1200, uid: 6),
        ]
        let decades = SmartPlaylists.decades(tracks)
        XCTAssertEqual(decades.map(\.name), ["1970er", "1980er", "2010er"])
        XCTAssertEqual(decades[0].trackUids, [1, 2])
        XCTAssertFalse(decades.contains { $0.trackUids.contains(5) || $0.trackUids.contains(6) })
        XCTAssertEqual(decades[0].id, "smart:decade:1970")
        XCTAssertEqual(decades[0].decadeStart, 1970)
    }

    // MARK: - Playlist-Reihenfolge

    func testPlaylistVerschieben() {
        let list = ["a", "b", "c", "d"]
        XCTAssertEqual(PlaylistOrdering.move(list, from: 0, to: 2), ["b", "c", "a", "d"])
        XCTAssertEqual(PlaylistOrdering.move(list, from: 3, to: 0), ["d", "a", "b", "c"])
        XCTAssertEqual(PlaylistOrdering.move(list, from: 1, to: 1), list)
        XCTAssertEqual(PlaylistOrdering.move(list, from: 5, to: 0), list)
        XCTAssertEqual(PlaylistOrdering.uniqueName("Neue Playlist", existing: ["neue playlist"]), "Neue Playlist 2")
        XCTAssertNil(PlaylistOrdering.cleanName("   "))
        XCTAssertEqual(PlaylistOrdering.cleanName("  Mein   Mix "), "Mein Mix")
        XCTAssertEqual(PlaylistOrdering.uniqueName("Mix", existing: ["Mix", "mix 2"]), "Mix 3")
        XCTAssertEqual(PlaylistOrdering.renumber(["x", "y"]).map(\.1), [0, 1])
        XCTAssertEqual(PlaylistOrdering.cleanName(String(repeating: "ä", count: 250))?.count, 200)
    }

    // MARK: - Hilfsfunktionen

    func testNatuerlicheSortierung() {
        let sorted = NaturalOrder.comparator().sorted(["Track 10", "track 2", "Track 1", "Äpfel", "Zebra"])
        XCTAssertEqual(sorted, ["Äpfel", "Track 1", "track 2", "Track 10", "Zebra"])
    }

    func testListCodec_mehrfachwerteMitKommas() {
        let values = ["Earth, Wind & Fire", "Simon & Garfunkel"]
        XCTAssertEqual(ListCodec.decode(ListCodec.encode(values)), values)
        XCTAssertEqual(ListCodec.decode(ListCodec.encode([])), [])
    }

    func testFormatierung() {
        XCTAssertEqual(Formatting.duration(187_000), "3:07")
        XCTAssertEqual(Formatting.duration(3_723_000), "1:02:03")
        XCTAssertEqual(Formatting.longDuration(72 * 60_000), "1 Std. 12 Min.")
        XCTAssertEqual(Formatting.sampleRate(44100), "44,1 kHz")
        XCTAssertEqual(Formatting.sampleRate(48000), "48 kHz")
        XCTAssertEqual(Formatting.decibel(3.5), "+3,5 dB")
        XCTAssertEqual(Formatting.decibel(-2), "−2 dB")
        XCTAssertEqual(Formatting.semitones(0), "Original")
        XCTAssertEqual(Formatting.semitones(-1), "−1 Halbton")
        XCTAssertEqual(Formatting.tracks(1), "1 Titel")
        XCTAssertEqual(Formatting.tracks(1234), "1.234 Titel")
        XCTAssertEqual(Formatting.dateTime(1_709_647_620_000, timeZone: TimeZone(identifier: "Europe/Berlin")!), "05.03.2024, 15:07")
        XCTAssertEqual(Formatting.factor(1.35), "1,35×")
    }
}
