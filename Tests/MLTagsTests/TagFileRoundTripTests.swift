import Foundation
import MLCore
import XCTest
@testable import MLTags

/// Lesen und Schreiben aller Felder für jedes Fixture-Format.
final class TagFileRoundTripTests: TagTestCase {

    // MARK: - Read

    func testReadEveryFixture() throws {
        for fixture in Fixtures.all {
            let result = try TagFile.read(url: Fixtures.url(fixture.file))
            let v = result.values
            XCTAssertEqual(result.fileFormat, fixture.format, "\(fixture)")
            XCTAssertEqual(result.audio.codec, fixture.codec, "\(fixture)")
            XCTAssertEqual(result.audio.sampleRate, fixture.sampleRate, "\(fixture)")
            XCTAssertEqual(result.audio.channels, 1, "\(fixture)")
            for part in fixture.tagFormat {
                XCTAssertTrue(result.tagFormat.contains(part), "\(fixture): tag format \(result.tagFormat)")
            }
            XCTAssertTrue(result.supportsPictures, "\(fixture)")
            XCTAssertTrue(result.writable, "\(fixture)")
            XCTAssertEqual(v.title, "Fixture Title", "\(fixture)")
            XCTAssertEqual(v.artists, ["Fixture Artist"], "\(fixture)")
            XCTAssertEqual(v.album, "Fixture Album", "\(fixture)")
            XCTAssertEqual(v.genres, ["Rock"], "\(fixture)")
            XCTAssertEqual(v.trackNumber, 3, "\(fixture)")
            if !fixture.unsupported.contains(.trackTotal) { XCTAssertEqual(v.trackTotal, 12, "\(fixture)") }
            if fixture.hasYear {
                XCTAssertEqual(v.year, 2021, "\(fixture)")
                XCTAssertEqual(v.date, "2021-03-04", "\(fixture)")
            }
            if fixture.hasComment { XCTAssertEqual(v.comment, "Fixture comment", "\(fixture)") }
            XCTAssertFalse(v.pictures.isEmpty, "\(fixture): cover")
            for picture in v.pictures {
                XCTAssertTrue(picture.data == Fixtures.png || picture.data == Fixtures.jpg, "\(fixture): cover data")
                XCTAssertEqual(picture.mimeType, picture.data == Fixtures.png ? "image/png" : "image/jpeg", "\(fixture)")
            }
            if fixture.codec != "DSD" {
                XCTAssertGreaterThan(result.audio.durationMs, fixture.file == "oggflac.oga" ? -1 : 900, "\(fixture)")
            }
        }
    }

    func testLossyCodecsHaveNoBitDepth() throws {
        for name in ["id3v23.mp3", "aac.m4a", "vorbis.ogg", "opus.opus", "wma.wma"] {
            XCTAssertEqual(try TagFile.read(url: Fixtures.url(name)).audio.bitsPerSample, 0, name)
        }
        for name in ["alac.m4a", "flac.flac", "wave.wav", "aiff.aiff", "wavpack.wv"] {
            XCTAssertEqual(try TagFile.read(url: Fixtures.url(name)).audio.bitsPerSample, 16, name)
        }
    }

    // MARK: - Full round trip

    func testFullRoundTripEveryFormat() throws {
        for fixture in Fixtures.all {
            let url = try copyFixture(fixture.file)
            let before = try TagFile.inspect(url: url)
            let payload = try XCTUnwrap(try TagFile.audioPayloadChecksum(url: url), "\(fixture): payload checksum")
            let report = try TagFile.write(url: url, edit: SampleValues.fullEdit)
            XCTAssertEqual(try TagFile.audioPayloadChecksum(url: url), payload, "\(fixture): audio payload changed")
            XCTAssertEqual(Set(report.skippedFields), fixture.unsupported, "\(fixture): skipped fields")
            XCTAssertTrue(report.picturesWritten, "\(fixture)")

            let after = try TagFile.inspect(url: url)
            let v = after.result.values
            let s = SampleValues.full
            // explicit expectations (independent of the canonicalisation code)
            XCTAssertEqual(v.title, s.title, "\(fixture)")
            XCTAssertEqual(v.artists, s.artists, "\(fixture)")
            XCTAssertEqual(v.album, s.album, "\(fixture)")
            XCTAssertEqual(v.albumArtists, s.albumArtists, "\(fixture)")
            XCTAssertEqual(v.composers, s.composers, "\(fixture)")
            XCTAssertEqual(v.grouping, s.grouping, "\(fixture)")
            XCTAssertEqual(v.genres, s.genres, "\(fixture)")
            XCTAssertEqual(v.year, 1999, "\(fixture)")
            XCTAssertEqual(v.date, "1999", "\(fixture)")
            XCTAssertEqual(v.trackNumber, 7, "\(fixture)")
            XCTAssertEqual(v.discNumber, 2, "\(fixture)")
            XCTAssertEqual(v.discTotal, 3, "\(fixture)")
            XCTAssertEqual(v.bpm, 128, "\(fixture)")
            XCTAssertEqual(v.comment, s.comment, "\(fixture)")
            XCTAssertEqual(v.lyrics, s.lyrics, "\(fixture)")
            XCTAssertEqual(v.titleSort, s.titleSort, "\(fixture)")
            XCTAssertEqual(v.artistSort, s.artistSort, "\(fixture)")
            XCTAssertEqual(v.albumSort, s.albumSort, "\(fixture)")
            XCTAssertEqual(v.albumArtistSort, s.albumArtistSort, "\(fixture)")
            XCTAssertEqual(v.copyright, s.copyright, "\(fixture)")
            XCTAssertEqual(v.publisher, s.publisher, "\(fixture)")
            XCTAssertEqual(v.isrc, s.isrc, "\(fixture)")
            XCTAssertEqual(v.encodedBy, s.encodedBy, "\(fixture)")
            XCTAssertEqual(v.rating, fixture.file == "wma.wma" ? 80 : 70, "\(fixture): rating")
            if fixture.unsupported.contains(.work) {
                XCTAssertNil(v.work, "\(fixture)")
            } else {
                XCTAssertEqual(v.work, s.work, "\(fixture)")
            }
            if fixture.unsupported.contains(.trackTotal) {
                XCTAssertNil(v.trackTotal, "\(fixture)")
            } else {
                XCTAssertEqual(v.trackTotal, 15, "\(fixture)")
            }
            XCTAssertEqual(v.compilation, !fixture.unsupported.contains(.compilation), "\(fixture)")
            if fixture.unsupported.contains(.composerSort) {
                XCTAssertNil(v.composerSort, "\(fixture)")
            } else {
                XCTAssertEqual(v.composerSort, s.composerSort, "\(fixture)")
            }
            XCTAssertEqual(v.pictures.count, 2, "\(fixture): pictures")
            if fixture.file.hasSuffix(".m4a") {
                XCTAssertEqual(v.pictures.map(\.kind), [.frontCover, .frontCover], "\(fixture)")
                XCTAssertEqual(v.pictures.map(\.description), ["", ""], "\(fixture)")
            } else {
                XCTAssertEqual(Set(v.pictures.map(\.kind)), [.frontCover, .backCover], "\(fixture)")
                if !fixture.file.hasSuffix(".wma") {
                    XCTAssertEqual(v.pictures.map(\.description), ["Vorderseite 🎨", "Rückseite"], "\(fixture)")
                }
            }
            XCTAssertEqual(Set(v.pictures.map(\.data)), [Fixtures.png, Fixtures.jpg], "\(fixture)")
            XCTAssertEqual(Set(v.pictures.map(\.mimeType)), ["image/png", "image/jpeg"], "\(fixture)")

            // canonical expectation (all fields), audio unchanged, unknown data kept
            let expected = TagFile.expectedValues(before: before.result.values, edit: SampleValues.fullEdit,
                                                  traits: before.traits)
            for field in TagField.allCases {
                XCTAssertEqual(v.text(for: field), expected.text(for: field), "\(fixture): \(field)")
            }
            assertSameAudio(before.result.audio, after.result.audio, fixture.file)
            XCTAssertEqual(after.result.fileFormat, fixture.format)
            for part in fixture.tagFormat where !part.hasPrefix("ID3v1") {
                XCTAssertTrue(after.result.tagFormat.contains(part), "\(fixture): tag format \(after.result.tagFormat)")
            }
            try assertMarkers(fixture, in: url)
        }
    }

    func testClearAllFieldsEveryFormat() throws {
        for fixture in Fixtures.all {
            let url = try copyFixture(fixture.file)
            let before = try TagFile.read(url: url)
            let payload = try TagFile.audioPayloadChecksum(url: url)
            try TagFile.write(url: url, edit: SampleValues.fullEdit)
            try TagFile.write(url: url, edit: SampleValues.clearAll)
            XCTAssertEqual(try TagFile.audioPayloadChecksum(url: url), payload, "\(fixture): audio payload changed")
            let after = try TagFile.read(url: url)
            for field in TagField.allCases {
                let text = after.values.text(for: field)
                XCTAssertTrue(text.isEmpty || text == "0", "\(fixture): \(field) not cleared: \(text)")
            }
            XCTAssertTrue(after.values.pictures.isEmpty, "\(fixture): pictures not removed")
            assertSameAudio(before.audio, after.audio, fixture.file)
            try assertMarkers(fixture, in: url)
            // and writing again into the emptied file works
            try TagFile.write(url: url, edit: TagEdit(values: SampleValues.full, fields: [.title, .artists]))
            let again = try TagFile.read(url: url)
            XCTAssertEqual(again.values.title, SampleValues.full.title, "\(fixture)")
            XCTAssertEqual(again.values.artists, SampleValues.full.artists, "\(fixture)")
        }
    }

    // MARK: - Untouched data

    func testUntouchedFieldsAndUnknownDataPreserved() throws {
        for fixture in Fixtures.all {
            let url = try copyFixture(fixture.file)
            let file = try BridgeFile(path: url.path, readOnly: true)
            let unsupportedBefore = Set(try file.unsupportedProperties())
            let keysBefore = Set(try file.propertyKeys())
            let before = try TagFile.read(url: url)

            var v = TagValues()
            v.title = "Nur der Titel ✓"
            try TagFile.write(url: url, edit: TagEdit(values: v, fields: [.title]))

            let after = try TagFile.read(url: url)
            XCTAssertEqual(after.values.title, "Nur der Titel ✓", "\(fixture)")
            for field in TagField.allCases where field != .title {
                XCTAssertEqual(after.values.text(for: field), before.values.text(for: field), "\(fixture): \(field)")
            }
            XCTAssertEqual(after.values.date, before.values.date, "\(fixture): date")
            if fixture.file.hasSuffix(".wma") {
                XCTAssertEqual(Set(after.values.pictures), Set(before.values.pictures), "\(fixture): pictures")
            } else {
                XCTAssertEqual(after.values.pictures, before.values.pictures, "\(fixture): pictures")
            }
            let reopened = try BridgeFile(path: url.path, readOnly: true)
            let unsupportedAfter = Set(try reopened.unsupportedProperties())
            // TDAT is merged into the date by TagLib and written again as TDAT
            XCTAssertTrue(unsupportedBefore.subtracting(["UNKNOWN/TDAT"]).isSubset(of: unsupportedAfter),
                          "\(fixture): \(unsupportedBefore) -> \(unsupportedAfter)")
            XCTAssertTrue(keysBefore.isSubset(of: Set(try reopened.propertyKeys())), "\(fixture): property keys lost")
            assertSameAudio(before.audio, after.audio, fixture.file)
            try assertMarkers(fixture, in: url)
        }
    }

    func testCustomPropertyValuePreserved() throws {
        for fixture in Fixtures.all where fixture.file != "wma.wma" {
            let url = try copyFixture(fixture.file)
            try TagFile.write(url: url, edit: SampleValues.fullEdit)
            let values = try BridgeFile(path: url.path, readOnly: true).property("MLTEST_CUSTOM")
            XCTAssertTrue(values.contains("MLTEST-MARKER-\(fixture.tag)-CUSTOM"), "\(fixture): \(values)")
        }
    }

    // MARK: - Pictures

    func testPicturesReplaceRemoveMultipleEveryFormat() throws {
        for fixture in Fixtures.all {
            let url = try copyFixture(fixture.file)
            let traits = try TagFile.inspect(url: url).traits

            // replace by a single JPEG
            let single = [EmbeddedPicture(kind: .frontCover, mimeType: "image/jpeg", description: "Neu", data: Fixtures.jpg)]
            try TagFile.write(url: url, edit: TagEdit(pictures: .replaceAll(single)))
            var read = try TagFile.read(url: url).values.pictures
            XCTAssertEqual(read, TagFile.canonicalPictures(single, traits: traits), "\(fixture)")
            XCTAssertEqual(read.first?.data, Fixtures.jpg, "\(fixture)")

            // three pictures of different kinds
            let three = [
                EmbeddedPicture(kind: .frontCover, mimeType: "image/png", description: "A", data: Fixtures.png),
                EmbeddedPicture(kind: .backCover, mimeType: "image/jpeg", description: "B", data: Fixtures.jpg),
                EmbeddedPicture(kind: .artist, mimeType: "image/png", description: "Künstlerin", data: Fixtures.png),
            ]
            try TagFile.write(url: url, edit: TagEdit(pictures: .replaceAll(three)))
            read = try TagFile.read(url: url).values.pictures
            let expected = TagFile.canonicalPictures(three, traits: traits)
            if fixture.file.hasSuffix(".wma") {
                XCTAssertEqual(Set(read), Set(expected), "\(fixture)")
            } else {
                XCTAssertEqual(read, expected, "\(fixture)")
            }
            XCTAssertEqual(read.count, 3, "\(fixture)")

            // remove all
            let payload = try TagFile.audioPayloadChecksum(url: url)
            try TagFile.write(url: url, edit: TagEdit(pictures: .replaceAll([])))
            XCTAssertEqual(try TagFile.audioPayloadChecksum(url: url), payload, "\(fixture)")
            XCTAssertTrue(try TagFile.read(url: url).values.pictures.isEmpty, "\(fixture)")
            try assertMarkers(fixture, in: url)
        }
    }

    func testPictureGeometryStoredInFLACBlocks() throws {
        let url = try copyFixture("flac.flac")
        let pictures = [EmbeddedPicture(kind: .frontCover, mimeType: "image/png", data: Fixtures.png)]
        try TagFile.write(url: url, edit: TagEdit(pictures: .replaceAll(pictures)))
        // PICTURE block: type(4) mime len(4) mime desc len(4) desc width(4) height(4) depth(4) colors(4)
        let data = try bytes(url)
        let mime = Data("image/png".utf8)
        let range = try XCTUnwrap(data.range(of: mime))
        let i = range.upperBound + 4  // empty description
        let width = data[i..<(i + 4)].reduce(0) { $0 << 8 | Int($1) }
        let height = data[(i + 4)..<(i + 8)].reduce(0) { $0 << 8 | Int($1) }
        XCTAssertEqual(width, 16)
        XCTAssertEqual(height, 16)
    }

    // MARK: - Individual field behaviour (all formats)

    func testCompilationAndRatingToggleEveryFormat() throws {
        for fixture in Fixtures.all {
            let url = try copyFixture(fixture.file)
            var v = TagValues()
            v.compilation = true
            v.rating = 100
            try TagFile.write(url: url, edit: TagEdit(values: v, fields: [.compilation, .rating]))
            var read = try TagFile.read(url: url).values
            XCTAssertEqual(read.compilation, !fixture.unsupported.contains(.compilation), "\(fixture)")
            XCTAssertEqual(read.rating, 100, "\(fixture)")
            v.compilation = false
            v.rating = nil
            try TagFile.write(url: url, edit: TagEdit(values: v, fields: [.compilation, .rating]))
            read = try TagFile.read(url: url).values
            XCTAssertFalse(read.compilation, "\(fixture)")
            XCTAssertNil(read.rating, "\(fixture)")
        }
    }

    func testTrackNumberKeepsTotalEveryFormat() throws {
        for fixture in Fixtures.all {
            let url = try copyFixture(fixture.file)
            var v = TagValues()
            v.trackNumber = 5
            v.discNumber = 9
            try TagFile.write(url: url, edit: TagEdit(values: v, fields: [.trackNumber, .discNumber]))
            let read = try TagFile.read(url: url).values
            XCTAssertEqual(read.trackNumber, 5, "\(fixture)")
            XCTAssertEqual(read.discNumber, 9, "\(fixture)")
            if !fixture.unsupported.contains(.trackTotal) { XCTAssertEqual(read.trackTotal, 12, "\(fixture)") }
            XCTAssertEqual(read.discTotal, 2, "\(fixture)")
        }
    }

    func testYearKeepsFullDateIfYearUnchanged() throws {
        for fixture in Fixtures.all where fixture.hasYear {
            let url = try copyFixture(fixture.file)
            var v = TagValues()
            v.year = 2021
            try TagFile.write(url: url, edit: TagEdit(values: v, fields: [.year]))
            XCTAssertEqual(try TagFile.read(url: url).values.date, "2021-03-04", "\(fixture)")
            v.year = 2022
            try TagFile.write(url: url, edit: TagEdit(values: v, fields: [.year]))
            let read = try TagFile.read(url: url).values
            XCTAssertEqual(read.year, 2022, "\(fixture)")
            XCTAssertEqual(read.date, "2022", "\(fixture)")
        }
    }

    func testLyricsLineEndingsPreserved() throws {
        let lyrics = "[ti:Test]\r\n[00:00.50]Zeile eins\r\n[00:01.00]Zeile zwei  \n\n  eingerückt\n"
        for fixture in Fixtures.all {
            let url = try copyFixture(fixture.file)
            var v = TagValues()
            v.lyrics = lyrics
            try TagFile.write(url: url, edit: TagEdit(values: v, fields: [.lyrics]))
            XCTAssertEqual(try TagFile.read(url: url).values.lyrics, lyrics, "\(fixture)")
        }
    }

    func testMultiValuesWithSemicolonInputAreSplit() throws {
        let url = try copyFixture("flac.flac")
        var v = TagValues()
        v.genres = ["Rock; Pop", "  Jazz  ", ""]
        try TagFile.write(url: url, edit: TagEdit(values: v, fields: [.genres]))
        XCTAssertEqual(try TagFile.read(url: url).values.genres, ["Rock", "Pop", "Jazz"])
        XCTAssertEqual(try BridgeFile(path: url.path, readOnly: true).property("GENRE"), ["Rock", "Pop", "Jazz"])
    }
}
