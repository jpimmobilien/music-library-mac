import Foundation
import MLCore
import XCTest
@testable import MLTags

/// Format-spezifische Regeln aus MAPPING.md.
final class FormatSpecificTests: TagTestCase {

    private func write(_ url: URL, _ fields: Set<TagField>, _ build: (inout TagValues) -> Void) throws {
        var v = TagValues()
        build(&v)
        try TagFile.write(url: url, edit: TagEdit(values: v, fields: fields))
    }

    private func property(_ url: URL, _ key: String) throws -> [String] {
        try BridgeFile(path: url.path, readOnly: true).property(key)
    }

    // MARK: - ID3v2 versions and secondary tags

    func testID3v2VersionIsKept() throws {
        for (name, version) in [("id3v23.mp3", "ID3v2.3"), ("id3v24.mp3", "ID3v2.4"), ("wave.wav", "ID3v2.3"),
                                ("aiff.aiff", "ID3v2.4")] {
            let url = try copyFixture(name)
            try TagFile.write(url: url, edit: SampleValues.fullEdit)
            let tagFormat = try TagFile.read(url: url).tagFormat
            XCTAssertTrue(tagFormat.hasPrefix(version), "\(name): \(tagFormat)")
            let data = try bytes(url)
            let v3 = Data("ID3".utf8) + Data([3, 0])
            let v4 = Data("ID3".utf8) + Data([4, 0])
            XCTAssertNotNil(data.range(of: version == "ID3v2.3" ? v3 : v4), name)
            XCTAssertNil(data.range(of: version == "ID3v2.3" ? v4 : v3), name)
        }
    }

    func testNewID3v2TagIsVersion24AndID3v1IsKept() throws {
        // strip the ID3v2 tag of the v2.3 fixture by hand: MPEG frames + ID3v1 remain
        var data = try Data(contentsOf: Fixtures.url("id3v23.mp3"))
        let size = data[6..<10].reduce(0) { $0 << 7 | Int($1 & 0x7F) } + 10
        data.removeSubrange(0..<size)
        let url = tempDir.appendingPathComponent("plain.mp3")
        try data.write(to: url)
        let before = try TagFile.read(url: url)
        XCTAssertEqual(before.tagFormat, "ID3v1")
        XCTAssertEqual(before.values.title, "Fixture Title")  // read from ID3v1

        try write(url, [.album]) { $0.album = "Neues Album" }
        let after = try TagFile.read(url: url)
        XCTAssertEqual(after.tagFormat, "ID3v2.4, ID3v1")
        XCTAssertEqual(after.values.album, "Neues Album")
        XCTAssertEqual(after.values.title, "Fixture Title")  // still from ID3v1
        assertSameAudio(before.audio, after.audio, "plain.mp3")
    }

    func testID3v1IsUpdatedTogetherWithID3v2() throws {
        let url = try copyFixture("id3v23.mp3")
        try write(url, [.title, .artists]) {
            $0.title = "Neuer Titel"
            $0.artists = ["Eins", "Zwei"]
        }
        var data = try bytes(url)
        var v1 = data.suffix(128)
        XCTAssertEqual(Data(v1.prefix(3)), Data("TAG".utf8))
        XCTAssertNotNil(v1.range(of: Data("Neuer Titel".utf8)))
        XCTAssertNotNil(v1.range(of: Data("Eins; Zwei".utf8)))

        // clearing the title must clear ID3v1 too (no stale fallback)
        try write(url, [.title]) { $0.title = nil }
        XCTAssertNil(try TagFile.read(url: url).values.title)
        data = try bytes(url)
        v1 = data.suffix(128)
        XCTAssertNil(v1.range(of: Data("Neuer Titel".utf8)))
    }

    func testAPETagInMP3IsKeptAndUpdated() throws {
        let url = try copyFixture("id3v24.mp3")
        try write(url, [.title]) { $0.title = "APE Sync" }
        let result = try TagFile.read(url: url)
        XCTAssertTrue(result.tagFormat.contains("APEv2"))
        let data = try bytes(url)
        let ape = try XCTUnwrap(data.range(of: Data("APETAGEX".utf8)))
        XCTAssertNotNil(data[ape.lowerBound...].range(of: Data("APE Sync".utf8)) ?? data.range(of: Data("APE Sync".utf8)))
        XCTAssertTrue(containsMarker(data, "MLTEST-MARKER-mp3v24-APE"))
    }

    func testRIFFInfoIsUpdatedTogetherWithID3v2() throws {
        let url = try copyFixture("wave.wav")
        try write(url, [.title, .comment]) {
            $0.title = "WAV Titel Ü"
            $0.comment = nil
        }
        let data = try bytes(url)
        let inam = try XCTUnwrap(data.range(of: Data("INAM".utf8)))
        XCTAssertNotNil(data[inam.upperBound...].range(of: Data("WAV Titel Ü".utf8)))
        XCTAssertNil(data.range(of: Data("Fixture comment".utf8)))
        let read = try TagFile.read(url: url).values
        XCTAssertEqual(read.title, "WAV Titel Ü")
        XCTAssertNil(read.comment)
    }

    // MARK: - ID3v2 frames

    func testPOPMKeepsForeignFrameAndPlayCounter() throws {
        let url = try copyFixture("id3v23.mp3")
        let email = Data("player@example.org".utf8) + Data([0])
        func popm() throws -> (rating: UInt8, counter: Int) {
            let data = try bytes(url)
            let r = try XCTUnwrap(data.range(of: email))
            let counter = data[(r.upperBound + 1)..<(r.upperBound + 5)].reduce(0) { $0 << 8 | Int($1) }
            return (data[r.upperBound], counter)
        }
        XCTAssertEqual(try popm().rating, 196)
        XCTAssertEqual(try TagFile.read(url: url).values.rating, 80)

        try write(url, [.rating]) { $0.rating = 60 }
        XCTAssertEqual(try popm().rating, 128)
        XCTAssertEqual(try popm().counter, 7)
        XCTAssertNil(try bytes(url).range(of: Data("Windows Media Player 9 Series".utf8)), "no second POPM")

        try write(url, [.rating]) { $0.rating = nil }
        XCTAssertEqual(try popm().rating, 0)
        XCTAssertEqual(try popm().counter, 7, "frame with play counter is kept")
        XCTAssertNil(try TagFile.read(url: url).values.rating)
    }

    func testPOPMMappingTable() throws {
        let url = try copyFixture("tta.tta")  // no POPM yet
        let wmp = Data("Windows Media Player 9 Series".utf8) + Data([0])
        let table: [(Int, UInt8, Int)] = [
            (10, 13, 10), (20, 1, 20), (30, 54, 30), (40, 64, 40), (50, 118, 50), (60, 128, 60), (70, 186, 70),
            (80, 196, 80), (90, 242, 90), (100, 255, 100), (15, 1, 20), (33, 54, 30), (99, 255, 100), (1, 13, 10),
        ]
        for (rating, popm, readBack) in table {
            try write(url, [.rating]) { $0.rating = rating }
            let data = try bytes(url)
            let r = try XCTUnwrap(data.range(of: wmp), "rating \(rating)")
            XCTAssertEqual(data[r.upperBound], popm, "rating \(rating)")
            XCTAssertEqual(try TagFile.read(url: url).values.rating, readBack, "rating \(rating)")
            XCTAssertEqual(TagFile.canonicalRating(rating, step: 10), readBack)
        }
    }

    func testCommentKeepsITunesFramesAndLanguage() throws {
        let url = try copyFixture("id3v23.mp3")
        try write(url, [.comment, .lyrics]) {
            $0.comment = "Neuer Kommentar"
            $0.lyrics = "Neuer Text\nZeile 2"
        }
        let data = try bytes(url)
        XCTAssertTrue(containsMarker(data, "iTunNORM"))
        XCTAssertTrue(containsMarker(data, " 00000123 00000456 00000789"))
        let read = try TagFile.read(url: url).values
        XCTAssertEqual(read.comment, "Neuer Kommentar")
        XCTAssertEqual(read.lyrics, "Neuer Text\nZeile 2")
        // USLT: id(4) size(4) flags(2) encoding(1) language(3)
        let uslt = try XCTUnwrap(data.range(of: Data("USLT".utf8)))
        XCTAssertEqual(String(decoding: data[(uslt.lowerBound + 11)..<(uslt.lowerBound + 14)], as: UTF8.self), "deu")
        // the ffmpeg comment alias TXXX:comment is kept in sync
        XCTAssertFalse(containsMarker(data, "Fixture comment"))
    }

    func testMultiValueRepresentationPerFormat() throws {
        let cases: [(String, [String])] = [
            ("id3v24.mp3", ["A", "B"]),      // NUL separated
            ("id3v23.mp3", ["A; B"]),        // joined (no multi values in v2.3)
            ("flac.flac", ["A", "B"]),       // repeated fields
            ("vorbis.ogg", ["A", "B"]),
            ("aac.m4a", ["A; B"]),           // single string
            ("wavpack.wv", ["A", "B"]),      // APE NUL separated
            ("wma.wma", ["A; B"]),           // one attribute
        ]
        for (name, expected) in cases {
            let url = try copyFixture(name)
            try write(url, [.artists, .genres]) {
                $0.artists = ["A", "B"]
                $0.genres = ["A", "B"]
            }
            XCTAssertEqual(try property(url, "ARTIST"), expected, name)
            XCTAssertEqual(try property(url, "GENRE"), expected, name)
            let read = try TagFile.read(url: url).values
            XCTAssertEqual(read.artists, ["A", "B"], name)
            XCTAssertEqual(read.genres, ["A", "B"], name)
        }
    }

    // MARK: - Grouping and work

    func testLegacyGroupingInTIT1() throws {
        let url = try copyFixture("id3v24.mp3")  // TIT1 "Legacy Grouping", no GRP1
        var read = try TagFile.read(url: url).values
        XCTAssertEqual(read.grouping, "Legacy Grouping")
        XCTAssertNil(read.work)

        try write(url, [.grouping]) { $0.grouping = "Neue Gruppe" }
        read = try TagFile.read(url: url).values
        XCTAssertEqual(read.grouping, "Neue Gruppe")
        XCTAssertNil(read.work)
        XCTAssertEqual(try property(url, "GROUPING"), ["Neue Gruppe"])  // GRP1 written
        XCTAssertEqual(try property(url, "WORK"), ["Neue Gruppe"])      // TIT1 (TagLib: WORK) updated

        try write(url, [.work]) { $0.work = "Opus 1" }
        read = try TagFile.read(url: url).values
        XCTAssertEqual(read.grouping, "Neue Gruppe")
        XCTAssertEqual(read.work, "Opus 1")
    }

    func testITunesGroupingAndWork() throws {
        let url = try copyFixture("tta.tta")
        try write(url, [.grouping, .work]) {
            $0.grouping = "G"
            $0.work = "W"
        }
        var read = try TagFile.read(url: url).values
        XCTAssertEqual(read.grouping, "G")
        XCTAssertEqual(read.work, "W")
        let data = try bytes(url)
        XCTAssertNotNil(data.range(of: Data("GRP1".utf8)))
        XCTAssertNotNil(data.range(of: Data("TIT1".utf8)))

        try write(url, [.grouping]) { $0.grouping = "G2" }
        read = try TagFile.read(url: url).values
        XCTAssertEqual(read.grouping, "G2")
        XCTAssertEqual(read.work, "W")

        try write(url, [.grouping]) { $0.grouping = "W" }  // grouping equal to work
        read = try TagFile.read(url: url).values
        XCTAssertEqual(read.grouping, "W")
        XCTAssertEqual(read.work, "W")

        try write(url, [.grouping]) { $0.grouping = nil }
        read = try TagFile.read(url: url).values
        XCTAssertNil(read.grouping)
        XCTAssertEqual(read.work, "W")

        try write(url, [.work]) { $0.work = nil }
        read = try TagFile.read(url: url).values
        XCTAssertNil(read.grouping)
        XCTAssertNil(read.work)

        try write(url, [.work]) { $0.work = "Nur Werk" }
        read = try TagFile.read(url: url).values
        XCTAssertNil(read.grouping)
        XCTAssertEqual(read.work, "Nur Werk")
    }

    func testGroupingAndWorkAreIndependentInOtherFormats() throws {
        for name in ["aac.m4a", "flac.flac", "wavpack.wv"] {
            let url = try copyFixture(name)
            try write(url, [.grouping, .work]) {
                $0.grouping = "Gruppe"
                $0.work = "Gruppe"
            }
            let read = try TagFile.read(url: url).values
            XCTAssertEqual(read.grouping, "Gruppe", name)
            XCTAssertEqual(read.work, "Gruppe", name)
        }
    }

    // MARK: - MP4, Vorbis, WMA, APE specifics

    func testMP4RatingAtomAndCoverWithoutTypes() throws {
        let url = try copyFixture("aac.m4a")
        try write(url, [.rating]) { $0.rating = 55 }
        XCTAssertEqual(try TagFile.read(url: url).values.rating, 55)
        XCTAssertTrue(containsMarker(try bytes(url), "com.apple.iTunes"))
        XCTAssertEqual(try property(url, "RATING"), ["55"])
        XCTAssertNil(try bytes(url).range(of: Data("rtng".utf8)))

        let back = EmbeddedPicture(kind: .backCover, mimeType: "image/png", description: "Rückseite", data: Fixtures.png)
        try TagFile.write(url: url, edit: TagEdit(pictures: .replaceAll([back])))
        let read = try TagFile.read(url: url).values.pictures
        XCTAssertEqual(read, [EmbeddedPicture(kind: .frontCover, mimeType: "image/png", description: "", data: Fixtures.png)])
    }

    func testVorbisTrackNumberWithTotalIsSplit() throws {
        let url = try copyFixture("flac.flac")
        XCTAssertEqual(try property(url, "TRACKNUMBER"), ["3/12"])  // as written by ffmpeg
        try write(url, [.trackNumber]) { $0.trackNumber = 4 }
        XCTAssertEqual(try property(url, "TRACKNUMBER"), ["4"])
        XCTAssertEqual(try property(url, "TRACKTOTAL"), ["12"])
        XCTAssertEqual(try TagFile.read(url: url).values.trackTotal, 12)
    }

    func testVorbisDescriptionIsCommentAlias() throws {
        let url = try copyFixture("vorbis.ogg")
        XCTAssertEqual(try property(url, "DESCRIPTION"), ["Fixture comment"])
        try write(url, [.comment]) { $0.comment = "Neu" }
        XCTAssertEqual(try property(url, "COMMENT"), ["Neu"])
        XCTAssertEqual(try property(url, "DESCRIPTION"), ["Neu"])
        try write(url, [.comment]) { $0.comment = nil }
        XCTAssertTrue(try property(url, "DESCRIPTION").isEmpty)
        XCTAssertNil(try TagFile.read(url: url).values.comment)
    }

    func testWMARatingUsesFullStarsAndSkipsUnsupportedFields() throws {
        let url = try copyFixture("wma.wma")
        var v = TagValues()
        v.rating = 50
        v.work = "Werk"
        let report = try TagFile.write(url: url, edit: TagEdit(values: v, fields: [.rating, .work]))
        XCTAssertEqual(report.writtenFields, [.rating])
        XCTAssertEqual(report.skippedFields, [.work])
        XCTAssertEqual(try TagFile.read(url: url).values.rating, 60)
        XCTAssertEqual(TagFile.canonicalRating(50, step: 20), 60)
        XCTAssertEqual(try TagFile.supportedFields(url: url), Set(TagField.allCases).subtracting(Fixtures.named("wma.wma").unsupported))
    }

    func testAPEKeepsOnePicturePerKind() throws {
        let url = try copyFixture("wavpack.wv")
        let pictures = [
            EmbeddedPicture(kind: .backCover, mimeType: "image/png", description: "b", data: Fixtures.png),
            EmbeddedPicture(kind: .frontCover, mimeType: "image/png", description: "f1", data: Fixtures.png),
            EmbeddedPicture(kind: .frontCover, mimeType: "image/jpeg", description: "f2", data: Fixtures.jpg),
        ]
        try TagFile.write(url: url, edit: TagEdit(pictures: .replaceAll(pictures)))
        let read = try TagFile.read(url: url).values.pictures
        XCTAssertEqual(read.map(\.kind), [.frontCover, .backCover])
        XCTAssertEqual(read.map(\.description), ["f1", "b"])
    }

    // MARK: - File type detection and refusal

    func testMisnamedFileIsDetectedByContent() throws {
        let url = try copyFixture("aac.m4a", as: "really-m4a.mp3")
        let result = try TagFile.read(url: url)
        XCTAssertEqual(result.fileFormat, "MPEG-4 Audio")
        try write(url, [.title]) { $0.title = "Inhalt zählt" }
        let after = try TagFile.read(url: url)
        XCTAssertEqual(after.values.title, "Inhalt zählt")
        XCTAssertEqual(after.audio.codec, "AAC")
        XCTAssertFalse(try bytes(url).starts(with: Data("ID3".utf8)), "no ID3v2 tag prepended to the MP4 file")
    }

    func testGarbageAndMissingFilesThrow() throws {
        let garbage = tempDir.appendingPathComponent("garbage.mp3")
        try Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 3) & 0x7F }).write(to: garbage)
        XCTAssertThrowsError(try TagFile.read(url: garbage)) { error in
            guard let e = error as? TagError else { return XCTFail("\(error)") }
            switch e {
            case .unsupportedFormat, .invalidFile: break
            default: XCTFail("\(e)")
            }
        }
        let text = tempDir.appendingPathComponent("text.flac")
        try Data("not audio at all".utf8).write(to: text)
        XCTAssertThrowsError(try TagFile.read(url: text))
        XCTAssertThrowsError(try TagFile.read(url: tempDir.appendingPathComponent("missing.mp3"))) { error in
            XCTAssertEqual(error as? TagError, .fileNotFound(path: self.tempDir.appendingPathComponent("missing.mp3").path))
        }
        XCTAssertThrowsError(try TagFile.read(url: tempDir)) { error in
            XCTAssertEqual(error as? TagError, .cannotOpen(path: self.tempDir.path))
        }
        XCTAssertTrue(TagError.fileNotFound(path: "/a/b.mp3").localizedDescription.contains("b.mp3"))
    }

    func testMP4WithUnpreservableAtomIsNotWritable() throws {
        let url = try copyFixture("aac.m4a")
        var data = try bytes(url)
        // change the data type of the "©xyz" atom from UTF-8 (1) to an unknown type (99)
        let xyz = try XCTUnwrap(data.range(of: Data([0xA9]) + Data("xyz".utf8)))
        let dataAtom = try XCTUnwrap(data[xyz.upperBound...].range(of: Data("data".utf8)))
        data[dataAtom.upperBound + 3] = 99
        try data.write(to: url)

        let result = try TagFile.read(url: url)
        XCTAssertFalse(result.writable)
        XCTAssertEqual(result.values.title, "Fixture Title")
        XCTAssertThrowsError(try write(url, [.title]) { $0.title = "x" }) { error in
            guard case .formatNotWritable(_, let reason)? = error as? TagError else { return XCTFail("\(error)") }
            XCTAssertTrue(reason.contains("xyz"), reason)
        }
        XCTAssertEqual(try bytes(url), data, "file untouched")
    }

    func testID3v23WithV24OnlyFrameIsNotWritable() throws {
        let url = try copyFixture("id3v23.mp3")
        var data = try bytes(url)
        // append a "TMOO" frame (ID3v2.4 only) into the padding of the v2.3 tag
        var pos = 10
        while pos + 10 <= data.count, data[pos] != 0 {
            let size = data[(pos + 4)..<(pos + 8)].reduce(0) { $0 << 8 | Int($1) }
            pos += 10 + size
        }
        let payload = Data([0]) + Data("Happy".utf8)
        let frame = Data("TMOO".utf8) + Data([0, 0, 0, UInt8(payload.count), 0, 0]) + payload
        data.replaceSubrange(pos..<(pos + frame.count), with: frame)
        try data.write(to: url)

        let result = try TagFile.read(url: url)
        XCTAssertFalse(result.writable)
        XCTAssertThrowsError(try write(url, [.title]) { $0.title = "x" }) { error in
            guard case .formatNotWritable(_, let reason)? = error as? TagError else { return XCTFail("\(error)") }
            XCTAssertTrue(reason.contains("TMOO"), reason)
        }
    }
}
