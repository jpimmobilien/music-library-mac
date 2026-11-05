import XCTest
@testable import MLCore

/// Portierung von `library/AlbumGroupingTest.kt`.
final class AlbumGroupingTests: XCTestCase {

    private func track(
        _ title: String? = "Titel", _ artist: String? = nil, _ album: String? = nil, _ albumArtist: String? = nil,
        genre: String? = nil, year: Int? = nil, track: Int? = nil, disc: Int? = nil, folder: String = "Music/",
        fileName: String? = nil, compilation: Bool = false, uid: Int64? = nil
    ) -> Track {
        TestTracks.track(title, artist, album, albumArtist, genre: genre, year: year, track: track, disc: disc,
                         folder: folder, fileName: fileName, compilation: compilation, uid: uid)
    }

    private func group(_ tracks: Track...) -> [AlbumInfo] { AlbumGrouping.group(tracks).albums }

    func testMultiDisc_istEinAlbum_sortiertNachDiscUndTrack() {
        let a = track("D2 T1", "Pink Floyd", "The Wall", "Pink Floyd", track: 1, disc: 2, uid: 1)
        let b = track("D1 T2", "Pink Floyd", "The Wall", "Pink Floyd", track: 2, disc: 1, uid: 2)
        let c = track("D1 T1", "Pink Floyd", "The Wall", "Pink Floyd", track: 1, disc: 1, uid: 3)
        let d = track("D2 T2", "Pink Floyd", "The Wall", "Pink Floyd", track: 2, disc: 2, uid: 4)
        let albums = group(a, b, c, d)
        XCTAssertEqual(albums.count, 1)
        XCTAssertEqual(albums[0].trackUids, [3, 2, 1, 4])
        XCTAssertEqual(albums[0].discNumbers, [1, 2])
        XCTAssertTrue(albums[0].isMultiDisc)
    }

    func testMultiDisc_inUnterordnernOhneDiscTags() {
        let tracks = [
            track("CD2-1", "Band", "Doppel", track: 1, folder: "Music/Band/Doppel/CD2/", uid: 10),
            track("CD1-1", "Band", "Doppel", track: 1, folder: "Music/Band/Doppel/CD1/", uid: 11),
            track("CD1-2", "Band", "Doppel", track: 2, folder: "Music/Band/Doppel/CD1/", uid: 12),
        ]
        let albums = AlbumGrouping.group(tracks).albums
        XCTAssertEqual(albums.count, 1)
        XCTAssertEqual(albums[0].trackUids, [11, 12, 10])
        // Disc-Nummern werden nicht erfunden
        XCTAssertTrue(albums[0].discNumbers.isEmpty)
    }

    func testGleicherTitel_verschiedeneInterpreten_werdenNichtZusammengefuehrt() {
        let albums = group(
            track("We Will Rock You", "Queen", "Greatest Hits", "Queen", folder: "Music/Queen/Greatest Hits/"),
            track("Waterloo", "ABBA", "Greatest Hits", "ABBA", folder: "Music/ABBA/Greatest Hits/")
        )
        XCTAssertEqual(albums.count, 2)
        XCTAssertEqual(Set(albums.compactMap(\.artist)), ["Queen", "ABBA"])
    }

    func testGleicherTitel_ohneAlbumInterpret_verschiedeneOrdnerUndInterpreten_getrennt() {
        let albums = group(
            track("A", "Queen", "Live", folder: "Music/Queen/Live/"),
            track("B", "Queen", "Live", folder: "Music/Queen/Live/"),
            track("C", "Nirvana", "Live", folder: "Music/Nirvana/Live/")
        )
        XCTAssertEqual(albums.count, 2)
    }

    func testCompilationMitFlag_bleibtEinAlbum() {
        let albums = group(
            track("Song 1", "Artist A", "Bravo Hits 50", track: 1, folder: "Music/Compilations/Bravo Hits 50/", compilation: true),
            track("Song 2", "Artist B", "Bravo Hits 50", track: 2, folder: "Music/Compilations/Bravo Hits 50/", compilation: true),
            track("Song 3", "Artist C", "Bravo Hits 50", track: 3, folder: "Music/Compilations/Bravo Hits 50/", compilation: true)
        )
        XCTAssertEqual(albums.count, 1)
        XCTAssertTrue(albums[0].isVarious)
        XCTAssertNil(albums[0].artist)
        XCTAssertEqual(albums[0].trackCount, 3)
    }

    func testZusammenstellungOhneFlag_imSelbenOrdner_bleibtEinAlbum() {
        let albums = group(
            track("S1", "A", "Kuschelrock 12", track: 1, folder: "Music/Kuschelrock 12/"),
            track("S2", "B", "Kuschelrock 12", track: 2, folder: "Music/Kuschelrock 12/")
        )
        XCTAssertEqual(albums.count, 1)
        XCTAssertTrue(albums[0].isVarious)
    }

    func testZusammenstellung_cd1cd2_ohneFlag_wirdZusammengefuehrt() {
        let albums = group(
            track("S1", "A", "Hits", track: 1, folder: "Music/Hits/CD1/"),
            track("S2", "B", "Hits", track: 2, folder: "Music/Hits/CD1/"),
            track("S3", "C", "Hits", track: 1, folder: "Music/Hits/CD2/"),
            track("S4", "D", "Hits", track: 2, folder: "Music/Hits/CD2/")
        )
        XCTAssertEqual(albums.count, 1)
        XCTAssertEqual(albums[0].trackCount, 4)
    }

    func testAlbumInterpretWeichtVomTrackInterpretAb() {
        let albums = group(
            track("Duett", "Elton John & Kiki Dee", "Duets", "Elton John", track: 1),
            track("Solo", "Elton John", "Duets", "Elton John", track: 2)
        )
        XCTAssertEqual(albums.count, 1)
        XCTAssertEqual(albums[0].artist, "Elton John")
    }

    func testTeilweiseGetaggterAlbumInterpret_wirdZusammengefuehrt() {
        let albums = group(
            track("1", "Queen", "Jazz", "Queen", track: 1, disc: 1, folder: "Music/Queen/Jazz/"),
            track("2", "Queen", "Jazz", nil, track: 2, disc: 1, folder: "Music/Queen/Jazz/")
        )
        XCTAssertEqual(albums.count, 1)
    }

    func testGleichnamigesAlbum_andereJahre_andereOrdner_getrennt() {
        let albums = group(
            track("A", "Band", "Live", "Band", year: 1990, folder: "Music/Band/Live (1990)/"),
            track("B", "Band", "Live", "Band", year: 2005, folder: "Music/Band/Live (2005)/")
        )
        XCTAssertEqual(albums.count, 2)
        XCTAssertEqual(Set(albums.compactMap(\.year)), [1990, 2005])
    }

    func testGemischteJahreImSelbenOrdner_bleibenEinAlbum() {
        let albums = group(
            track("A", "Band", "Best Of", "Band", year: 1990, folder: "Music/Band/Best Of/"),
            track("B", "Band", "Best Of", "Band", year: 1995, folder: "Music/Band/Best Of/")
        )
        XCTAssertEqual(albums.count, 1)
    }

    func testFehlendeTracknummern_stabileReihenfolgeNachDateiname() {
        let albums = group(
            track("Zehn", "X", "Album", fileName: "10 Zehn.mp3", uid: 100),
            track("Zwei", "X", "Album", fileName: "2 Zwei.mp3", uid: 101),
            track("Eins", "X", "Album", fileName: "1 Eins.mp3", uid: 102),
            track("Nummer", "X", "Album", track: 1, fileName: "z.mp3", uid: 103)
        )
        // Mit Tracknummer zuerst, dann natürliche Dateinamen-Reihenfolge
        XCTAssertEqual(albums[0].trackUids, [103, 102, 101, 100])
    }

    func testOhneAlbumTag_unbekanntesAlbumJeInterpret() {
        let albums = group(track("A", "X", nil), track("B", "X", nil), track("C", "Y", nil), track("D", nil, nil))
        XCTAssertEqual(albums.count, 3)
        XCTAssertTrue(albums.allSatisfy(\.isUnknown))
        XCTAssertEqual(Set(albums.map(\.artist)), ["X", "Y", nil])
    }

    func testSchreibweisenVarianten_werdenZusammengefuehrt() {
        let albums = group(
            track("A", "Björk", "Homogenic", "Björk"),
            track("B", "Bjork", "HOMOGENIC", "bjork")
        )
        XCTAssertEqual(albums.count, 1)
    }

    func testAlbumSchluesselIstStabil() {
        let t1 = track("A", "Queen", "Jazz", "Queen")
        let k1 = AlbumGrouping.group([t1]).albums.first!.key
        let both = AlbumGrouping.group([t1.with(uid: 999), track("B", "Queen", "Jazz")]).albums
        XCTAssertEqual(both.count, 1)
        XCTAssertEqual(both[0].key, k1)
        XCTAssertEqual(k1, "a|jazz|queen")
    }

    func testJahrUndGenre_haeufigsterWert_ohneErfinden() {
        let albums = group(
            track("A", "X", "Al", genre: "Rock", year: 2001),
            track("B", "X", "Al", genre: "Rock", year: 2001),
            track("C", "X", "Al", genre: nil, year: nil)
        )
        XCTAssertEqual(albums[0].genre, "Rock")
        XCTAssertEqual(albums[0].year, 2001)
        let noMeta = group(track("A", "X", "Ohne"))
        XCTAssertNil(noMeta[0].genre)
        XCTAssertNil(noMeta[0].year)
    }

    func testVariousArtistsAlsAlbumInterpretTag() {
        let albums = group(
            track("1", "A", "Sampler", "Various Artists"),
            track("2", "B", "Sampler", "Various Artists")
        )
        XCTAssertEqual(albums.count, 1)
        XCTAssertTrue(albums[0].isVarious)
        XCTAssertEqual(albums[0].artist, "Various Artists")
        XCTAssertFalse(albums[0].isUnknown)
    }

    // MARK: - Ergänzend (Mac)

    func testAlbumKeyByTrack_undSchluesselFuerUnbekannt() {
        let a = track("A", "X", nil, uid: 1)
        let b = track("B", "Queen", "Jazz", "Queen", uid: 2)
        let result = AlbumGrouping.group([a, b])
        XCTAssertEqual(result.albumKeyByTrack[1], "u|x")
        XCTAssertEqual(result.albumKeyByTrack[2], "a|jazz|queen")
    }

    func testZweiZusammenstellungenGleichenNamens_bekommenOrtsschluessel() {
        let albums = group(
            track("S1", "A", "Hits", folder: "Music/2020/Hits/"),
            track("S2", "B", "Hits", folder: "Music/2020/Hits/"),
            track("S3", "C", "Hits", year: 1999, folder: "Other/Hits/"),
            track("S4", "D", "Hits", year: 2000, folder: "Other/Hits/")
        )
        // verschiedene Elternordner → zwei Zusammenstellungen mit Ordner im Schlüssel
        XCTAssertEqual(albums.count, 2)
        XCTAssertTrue(albums.allSatisfy { $0.key.contains("#various@") })
    }
}
