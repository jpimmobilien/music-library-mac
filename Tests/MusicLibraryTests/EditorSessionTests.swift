import XCTest
import MLCore
@testable import MusicLibrary

/// Mehrfachbearbeitung im Informationsfenster: gemischte Werte, nur geänderte Felder schreiben,
/// Bewertung, Bilder, Kopieren/Einfügen.
@MainActor
final class EditorSessionTests: XCTestCase {
    private func track(_ uid: Int64, title: String, album: String, year: Int?, rating: Int?) -> Track {
        Track(uid: uid, path: "/nicht/vorhanden/\(uid).m4a", fileName: "\(uid).m4a", title: title, artists: ["Lina Hafen"],
              album: album, year: year, rating: rating)
    }

    private func load(_ tracks: [Track], pictures: [Int64: [EmbeddedPicture]] = [:]) async -> EditorSession {
        EditorSession.demoResult = { t in
            var v = TagValues()
            v.title = t.title
            v.artists = t.artists
            v.album = t.album
            v.year = t.year
            v.rating = t.rating
            v.pictures = pictures[t.uid] ?? []
            return TagReadResult(values: v, audio: AudioProperties(), fileFormat: "MPEG-4 Audio", tagFormat: "MP4", supportsPictures: true, writable: true)
        }
        defer { EditorSession.demoResult = nil }
        let session = EditorSession(uids: tracks.map(\.uid))
        await session.load(tracks: tracks)
        return session
    }

    func testSingleTrackShowsValuesWithoutChanges() async {
        let s = await load([track(1, title: "Nordlicht", album: "Küste", year: 2021, rating: 80)])
        XCTAssertFalse(s.isMulti)
        XCTAssertEqual(s.value(.title), "Nordlicht")
        XCTAssertEqual(s.value(.year), "2021")
        XCTAssertEqual(s.stars, 4)
        XCTAssertTrue(s.mixed.isEmpty)
        XCTAssertFalse(s.hasChanges)
        XCTAssertTrue(s.makeEdit().isEmpty)
    }

    func testMultiSelectionMarksMixedFieldsAndWritesOnlyChanges() async {
        let s = await load([
            track(1, title: "Eins", album: "Küste", year: 2021, rating: 80),
            track(2, title: "Zwei", album: "Küste", year: 2019, rating: 80),
        ])
        XCTAssertTrue(s.isMulti)
        XCTAssertEqual(s.mixed, [.title, .year])
        XCTAssertEqual(s.value(.album), "Küste")
        XCTAssertEqual(s.value(.title), "", "gemischte Felder bleiben leer")

        s.set(.album, "Küste (Deluxe)")
        let edit = s.makeEdit()
        XCTAssertEqual(edit.fields, [.album])
        XCTAssertEqual(edit.values.album, "Küste (Deluxe)")
        XCTAssertEqual(s.summary, "1 Feld (Album)")

        // Zurück auf den Ausgangswert → keine Änderung mehr
        s.set(.album, "Küste")
        XCTAssertFalse(s.hasChanges)

        // Gemischtes Feld ausdrücklich leeren → wird geschrieben (alle Titel ohne Jahr)
        s.set(.year, "")
        XCTAssertEqual(s.makeEdit().fields, [.year])
        s.revert(.year)
        XCTAssertFalse(s.hasChanges)
        XCTAssertTrue(s.mixed.contains(.year))
    }

    func testStarsMapToRating() async {
        let s = await load([
            track(1, title: "Eins", album: "A", year: nil, rating: 20),
            track(2, title: "Zwei", album: "A", year: nil, rating: 100),
        ])
        XCTAssertNil(s.stars, "gemischte Bewertung")
        s.setStars(3)
        XCTAssertEqual(s.stars, 3)
        XCTAssertEqual(s.makeEdit().values.rating, 60)
        s.setStars(0)
        XCTAssertEqual(s.stars, 0)
        XCTAssertNil(s.makeEdit().values.rating)
    }

    func testPictureEditingReplacesAll() async {
        let front = EmbeddedPicture(kind: .frontCover, mimeType: "image/png", data: Data([1, 2, 3]))
        let back = EmbeddedPicture(kind: .backCover, mimeType: "image/png", data: Data([4, 5, 6]))
        let s = await load([track(1, title: "Eins", album: "A", year: nil, rating: nil)], pictures: [1: [front]])
        XCTAssertEqual(s.pictures.count, 1)
        guard case .keep = s.makeEdit().pictures else { return XCTFail("ohne Änderung bleiben Bilder unberührt") }

        s.addPicture(back)
        XCTAssertEqual(s.pictures.map(\.kind), [.frontCover, .backCover])
        XCTAssertEqual(s.selectedPicture, 1)
        s.removeSelectedPicture()
        XCTAssertEqual(s.pictures, [front])
        guard case .replaceAll(let pics) = s.makeEdit().pictures else { return XCTFail("geänderte Bilder werden ersetzt") }
        XCTAssertEqual(pics, [front])
        XCTAssertEqual(s.summary, "1 Bild")
    }

    func testMixedPicturesAreNotShown() async {
        let a = EmbeddedPicture(mimeType: "image/png", data: Data([1]))
        let b = EmbeddedPicture(mimeType: "image/png", data: Data([2]))
        let s = await load([
            track(1, title: "Eins", album: "A", year: nil, rating: nil),
            track(2, title: "Zwei", album: "A", year: nil, rating: nil),
        ], pictures: [1: [a], 2: [b]])
        XCTAssertTrue(s.picturesMixed)
        XCTAssertTrue(s.pictures.isEmpty)
    }

    func testCopyPasteSkipsTrackSpecificFields() async {
        let source = await load([track(1, title: "Eins", album: "Küste", year: 2021, rating: 80)])
        let (values, fields) = source.copyableValues()
        XCTAssertFalse(fields.contains(.title))
        XCTAssertTrue(fields.contains(.album))

        let target = await load([track(2, title: "Zwei", album: "Alt", year: nil, rating: nil)])
        target.paste(values, fields: fields)
        XCTAssertEqual(target.value(.title), "Zwei")
        XCTAssertEqual(target.value(.album), "Küste")
        XCTAssertEqual(target.value(.year), "2021")
        XCTAssertTrue(target.makeEdit().fields.isSuperset(of: [.album, .year, .rating]))
        XCTAssertFalse(target.makeEdit().fields.contains(.title))
    }
}
