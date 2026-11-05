import XCTest
@testable import MLCore

final class DuplicateFinderTests: XCTestCase {

    private func t(
        _ uid: Int64, _ title: String?, _ artist: String? = "Queen", album: String? = nil, duration: Int64 = 180_000,
        size: Int64 = 0, bitrate: Int = 256, codec: String? = "AAC", cover: Bool = false, fileName: String? = nil,
        dateAdded: Int64 = 1_000, available: Bool = true, year: Int? = nil
    ) -> Track {
        TestTracks.track(title, artist, album, nil, year: year, fileName: fileName, durationMs: duration, uid: uid,
                         dateAdded: dateAdded, sizeBytes: size, bitrate: bitrate, codec: codec, hasPicture: cover, available: available)
    }

    func testGleichesLied_normalisierterTitelUndHauptinterpret() {
        let a = t(1, "Bohemian Rhapsody", "Queen", duration: 354_000)
        let b = t(2, "bohemian  rhapsody", "QUEEN feat. Somebody", duration: 355_900)
        let c = t(3, "Bohemian Rhapsody", "Queen", duration: 358_500) // Live-Fassung: > 2 s länger
        let d = t(4, "Bohemian Rhapsody", "Panic! at the Disco", duration: 354_000)
        let groups = DuplicateFinder.find([a, b, c, d])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].trackUids), [1, 2])
        XCTAssertEqual(groups[0].kind, .sameSong)
    }

    func testDauertoleranz_hoechstensZweiSekundenZumErsten_keineKetten() {
        let a = t(1, "Song", duration: 100_000)
        let b = t(2, "Song", duration: 101_900)
        let c = t(3, "Song", duration: 103_800) // zu b nur 1,9 s, zu a 3,8 s
        let groups = DuplicateFinder.find([a, b, c])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].trackUids), [1, 2])
    }

    func testAlbumOptional() {
        let a = t(1, "Song", album: "Album A")
        let b = t(2, "Song", album: "Best Of")
        XCTAssertEqual(DuplicateFinder.find([a, b]).count, 1)
        XCTAssertTrue(DuplicateFinder.find([a, b], options: .init(requireSameAlbum: true)).isEmpty)
    }

    func testIdentischeKopie_gleicheGroesseUndDauer() {
        let a = t(1, "Song", size: 7_000_000, fileName: "Song.m4a")
        let b = t(2, "Anderer Titel", "Anderer", size: 7_000_000, fileName: "Song 1.m4a") // Tags verschieden
        let c = t(3, "X", "Y", duration: 240_000, size: 7_000_000) // gleiche Größe, andere Dauer
        let groups = DuplicateFinder.find([a, b, c])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].kind, .identicalCopy)
        XCTAssertEqual(Set(groups[0].trackUids), [1, 2])
    }

    func testBeideKriterien_eineGruppe_jederTitelNurEinmal() {
        let a = t(1, "Song", size: 5_000_000)
        let b = t(2, "Song", size: 5_000_000) // Kopie von a
        let c = t(3, "Song", duration: 181_000, size: 9_000_000, codec: "FLAC") // gleiches Lied, verlustfrei
        let groups = DuplicateFinder.find([a, b, c])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].kind, .sameSong)
        XCTAssertEqual(groups[0].keepUid, 3)
        XCTAssertEqual(groups[0].trackUids.first, 3)
        XCTAssertEqual(Set(groups[0].others), [1, 2])
    }

    func testOhneTitelTag_nurBeiGleichemDateinamen() {
        let a = t(1, nil, nil, fileName: "Track 01.mp3")
        let b = t(2, nil, nil, fileName: "Track 01.m4a")
        let c = t(3, nil, nil, fileName: "Track 02.mp3")
        let d = t(4, "Track 01", nil, fileName: "x.mp3") // Titel-Tag ≠ Dateiname-Vergleich
        let groups = DuplicateFinder.find([a, b, c, d])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].trackUids), [1, 2])
    }

    func testNichtVerfuegbare_werdenStandardmaessigIgnoriert() {
        let a = t(1, "Song")
        let b = t(2, "Song", available: false)
        XCTAssertTrue(DuplicateFinder.find([a, b]).isEmpty)
        XCTAssertEqual(DuplicateFinder.find([a, b], options: .init(includeUnavailable: true)).count, 1)
    }

    func testVorzug_verlustfreiBitrateCoverTagsAlter() {
        let lossless = t(1, "S", bitrate: 900, codec: "ALAC")
        let high = t(2, "S", bitrate: 320, codec: "MP3")
        let low = t(3, "S", bitrate: 128, codec: "MP3")
        XCTAssertEqual(DuplicateFinder.preferredOrder([low, high, lossless]).map(\.uid), [1, 2, 3])
        // gleiche Bitrate: mit Cover vor ohne
        let withCover = t(4, "S", bitrate: 256, cover: true)
        let without = t(5, "S", bitrate: 256)
        XCTAssertEqual(DuplicateFinder.preferredOrder([without, withCover]).map(\.uid), [4, 5])
        // gleich bis auf Tags: mehr ausgefüllte Tags zuerst
        let moreTags = t(6, "S", album: "A", year: 1999)
        let fewer = t(7, "S")
        XCTAssertEqual(DuplicateFinder.preferredOrder([fewer, moreTags]).map(\.uid), [6, 7])
        // sonst: früher hinzugefügt; unbekanntes Datum zuletzt
        let older = t(8, "S", dateAdded: 100)
        let newer = t(9, "S", dateAdded: 200)
        let unknown = t(10, "S", dateAdded: 0)
        XCTAssertEqual(DuplicateFinder.preferredOrder([unknown, newer, older]).map(\.uid), [8, 9, 10])
    }

    func testVerlustfreiErkennung() {
        XCTAssertTrue(DuplicateFinder.isLossless(t(1, "S", codec: "FLAC")))
        XCTAssertTrue(DuplicateFinder.isLossless(t(1, "S", codec: "ALAC")))
        XCTAssertFalse(DuplicateFinder.isLossless(t(1, "S", codec: "AAC")))
        XCTAssertTrue(DuplicateFinder.isLossless(t(1, "S", codec: nil, fileName: "a.flac")))
        XCTAssertFalse(DuplicateFinder.isLossless(t(1, "S", codec: nil, fileName: "a.m4a"))) // ohne Codec unklar
    }

    func testStabileKennungUndReihenfolge() {
        let groups = DuplicateFinder.find([t(5, "Zebra"), t(6, "zebra"), t(1, "Apfel"), t(2, "Apfel")])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map(\.id), ["dup:1,2", "dup:5,6"])
        XCTAssertFalse(groups[0].reason.isEmpty)
        XCTAssertTrue(DuplicateFinder.find([]).isEmpty)
        XCTAssertTrue(DuplicateFinder.find([t(1, "A")]).isEmpty)
    }
}
