import XCTest
import MLCore
@testable import MLTags

/// Kapitelmarken (KI-Hörbücher): MP3 mit ID3v2 CHAP/CTOC, M4A mit Nero- und QuickTime-Kapiteln.
final class ChapterWriterTests: TagTestCase {
    let chapters = [ChapterWriter.Chapter(title: "Kapitel 2: Das Stellwerk", start: 0.5),
                    ChapterWriter.Chapter(title: "Kapitel 1: Ankunft", start: 0),
                    ChapterWriter.Chapter(title: "Kapitel 3: Auflösung", start: 0.8)]

    func testMP3ChaptersKeepTagsVersionAndAudio() throws {
        for (name, version) in [("id3v23.mp3", "ID3v2.3"), ("id3v24.mp3", "ID3v2.4")] {
            let url = try copyFixture(name)
            let before = try TagFile.read(url: url)
            try ChapterWriter.write(chapters, total: 1.0, to: url)
            try ChapterWriter.write(chapters, total: 1.0, to: url)  // zweimal: ersetzt statt verdoppelt
            let after = try TagFile.read(url: url)
            XCTAssertEqual(after.values.title, before.values.title, name)
            XCTAssertTrue(after.tagFormat.hasPrefix(version), "\(name): \(after.tagFormat)")
            assertSameAudio(before.audio, after.audio, name)
            let data = try bytes(url)
            XCTAssertEqual(count(Data("CHAP".utf8), in: data), 3, name)
            XCTAssertEqual(count(Data("CTOC".utf8), in: data), 1, name)
            XCTAssertNotNil(data.range(of: Data("Kapitel 3: Auflösung".utf8)) ?? data.range(of: Data("Kapitel 3: Aufl".utf8)), name)
            try assertMarkers(Fixtures.named(name), in: url)
        }
    }

    func testM4AChapters() throws {
        for name in ["aac.m4a", "alac.m4a"] {
            let url = try copyFixture(name)
            let before = try TagFile.read(url: url)
            try ChapterWriter.write(chapters, total: 1.0, to: url)
            let after = try TagFile.read(url: url)
            XCTAssertEqual(after.values.title, before.values.title, name)
            assertSameAudio(before.audio, after.audio, name)
            let data = try bytes(url)
            XCTAssertNotNil(data.range(of: Data("chpl".utf8)), "\(name): Nero-Kapitel")
            XCTAssertNotNil(data.range(of: Data("Kapitel 2: Das Stellwerk".utf8)), name)
        }
    }

    func testUnsupportedFormat() throws {
        let url = try copyFixture("flac.flac")
        XCTAssertThrowsError(try ChapterWriter.write(chapters, total: 1, to: url))
    }

    private func count(_ needle: Data, in data: Data) -> Int {
        var n = 0
        var range = data.startIndex..<data.endIndex
        while let r = data.range(of: needle, in: range) {
            n += 1
            range = r.upperBound..<data.endIndex
        }
        return n
    }
}
