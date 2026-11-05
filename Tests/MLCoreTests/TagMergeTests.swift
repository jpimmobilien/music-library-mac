import XCTest
@testable import MLCore

final class TagMergeTests: XCTestCase {

    private func values(title: String, artist: String, album: String?, year: Int?, genres: [String] = []) -> TagValues {
        var v = TagValues()
        v.title = title
        v.artists = [artist]
        v.album = album
        v.year = year
        v.genres = genres
        return v
    }

    func testGemischteWerteJeFeld() {
        let a = values(title: "Eins", artist: "Queen", album: "Jazz", year: 1978, genres: ["Rock"])
        let b = values(title: "Zwei", artist: "Queen", album: "Jazz", year: nil, genres: ["Rock"])
        let mixed = TagMerge.mixedValues([a, b])
        XCTAssertEqual(mixed[.title], .mixed)
        XCTAssertEqual(mixed[.artists], .same("Queen"))
        XCTAssertEqual(mixed[.album], .same("Jazz"))
        XCTAssertEqual(mixed[.year], .mixed)
        XCTAssertEqual(mixed[.genres], .same("Rock"))
        XCTAssertEqual(mixed[.composers], .same(""))
        XCTAssertTrue(TagMerge.mixedValues([]).isEmpty)
    }

    func testGemeinsameWerte_alsFormularStart() {
        let a = values(title: "Eins", artist: "Queen", album: "Jazz", year: 1978)
        let b = values(title: "Zwei", artist: "Queen", album: "Jazz", year: 1978)
        let common = TagMerge.commonValues([a, b])
        XCTAssertNil(common.title)
        XCTAssertEqual(common.artists, ["Queen"])
        XCTAssertEqual(common.year, 1978)
    }

    func testBearbeitung_nurGeaenderteFelder() {
        let a = values(title: "Eins", artist: "Queen", album: "Jazz", year: 1978)
        let b = values(title: "Zwei", artist: "Queen", album: "Jazz", year: nil)
        let original = TagMerge.mixedValues([a, b])
        let edit = TagMerge.edit(
            original: original,
            edited: [.album: "Jazz", .artists: "Queen; David Bowie", .year: nil, .title: "Neu", .genres: "Rock"],
            multipleTracks: true
        )
        // Album unverändert, Jahr nicht angefasst, Titel bei mehreren Titeln nie gemeinsam
        XCTAssertEqual(edit.fields, [.artists, .genres])
        XCTAssertEqual(edit.values.artists, ["Queen", "David Bowie"])
        let applied = edit.applied(to: b)
        XCTAssertEqual(applied.title, "Zwei")
        XCTAssertEqual(applied.year, nil)
        XCTAssertEqual(applied.genres, ["Rock"])
    }

    func testGemischtesFeldAusdruecklichLeeren() {
        let a = values(title: "A", artist: "X", album: "Eins", year: nil)
        let b = values(title: "B", artist: "X", album: "Zwei", year: nil)
        let edit = TagMerge.edit(original: TagMerge.mixedValues([a, b]), edited: [.album: ""], multipleTracks: true)
        XCTAssertEqual(edit.fields, [.album])
        XCTAssertNil(edit.applied(to: a).album)
    }

    func testEinzelbearbeitung_titelErlaubt() {
        let a = values(title: "A", artist: "X", album: nil, year: nil)
        let edit = TagMerge.edit(original: TagMerge.mixedValues([a]), edited: [.title: "Neu"], multipleTracks: false)
        XCTAssertEqual(edit.fields, [.title])
    }

    func testKopierenUndEinfuegen() throws {
        var source = values(title: "Titel", artist: "Queen", album: "Jazz", year: 1978, genres: ["Rock", "Pop"])
        source.isrc = "GBUM71029604"
        source.pictures = [EmbeddedPicture(kind: .frontCover, mimeType: "image/png", data: Data([1, 2, 3]))]
        let clip = TagMerge.copy(source, includePictures: true)
        XCTAssertFalse(clip.fields.contains(.title)) // je Titel verschieden: nicht kopiert
        XCTAssertFalse(clip.fields.contains(.isrc))
        XCTAssertTrue(clip.fields.contains(.album))
        // Zwischenablage ist speicherbar
        let restored = try JSONDecoder().decode(TagMerge.Clipboard.self, from: JSONEncoder().encode(clip))
        XCTAssertEqual(restored, clip)
        let edit = TagMerge.paste(restored, multipleTracks: true)
        var target = values(title: "Anders", artist: "ABBA", album: nil, year: nil)
        target = edit.applied(to: target)
        XCTAssertEqual(target.title, "Anders")
        XCTAssertEqual(target.artists, ["Queen"])
        XCTAssertEqual(target.album, "Jazz")
        XCTAssertEqual(target.year, 1978)
        XCTAssertEqual(target.genres, ["Rock", "Pop"])
        XCTAssertEqual(target.pictures.first?.data, Data([1, 2, 3]))
        // ausgewählte Felder, Titel bei Einzelziel erlaubt
        let only = TagMerge.copy(source, fields: [.title, .year])
        let single = TagMerge.paste(only, multipleTracks: false)
        XCTAssertEqual(single.fields, [.title, .year])
        if case .keep = single.pictures {} else { XCTFail("Bilder sollten unverändert bleiben") }
        XCTAssertEqual(TagMerge.paste(only, multipleTracks: true).fields, [.year])
    }

    func testGemischteBilder() {
        var a = TagValues()
        var b = TagValues()
        XCTAssertEqual(TagMerge.mixedPictures([a, b]), .same([]))
        a.pictures = [EmbeddedPicture(mimeType: "image/jpeg", data: Data([1]))]
        XCTAssertEqual(TagMerge.mixedPictures([a, b]), .mixed)
        b.pictures = a.pictures
        XCTAssertEqual(TagMerge.mixedPictures([a, b]), .same(a.pictures))
        XCTAssertNil(TagMerge.mixedPictures([]))
    }
}
