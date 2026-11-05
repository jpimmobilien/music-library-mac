import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import MLCore
import XCTest
@testable import MLTags

/// Beschreibung einer Test-Datei aus `Fixtures/` (erzeugt mit `Fixtures/_generator/generate.sh`).
struct Fixture: CustomStringConvertible {
    let file: String
    let format: String
    let codec: String
    let sampleRate: Int
    let tagFormat: [String]
    /// Kennung in den Markierungen „MLTEST-MARKER-<tag>-…“.
    let tag: String
    /// Markierungen in unbekannten Frames/Atomen/Feldern/Chunks, die jedes Schreiben überleben müssen.
    let markers: [String]
    var hasYear = true
    var hasComment = true
    var unsupported: Set<TagField> = []

    var description: String { file }
    var markerStrings: [String] { markers.map { "MLTEST-MARKER-\(tag)-\($0)" } }
}

enum Fixtures {
    static let id3Markers = ["PRIV", "XTST", "CUSTOM"]

    static let all: [Fixture] = [
        Fixture(file: "id3v23.mp3", format: "MP3", codec: "MP3", sampleRate: 8000, tagFormat: ["ID3v2.3", "ID3v1"],
                tag: "mp3v23", markers: id3Markers),
        Fixture(file: "id3v24.mp3", format: "MP3", codec: "MP3", sampleRate: 8000, tagFormat: ["ID3v2.4", "APEv2"],
                tag: "mp3v24", markers: id3Markers + ["APE"]),
        Fixture(file: "aac.m4a", format: "MPEG-4 Audio", codec: "AAC", sampleRate: 22050, tagFormat: ["MP4"],
                tag: "aac", markers: ["XYZ", "CUSTOM"]),
        Fixture(file: "alac.m4a", format: "MPEG-4 Audio", codec: "ALAC", sampleRate: 8000, tagFormat: ["MP4"],
                tag: "alac", markers: ["XYZ", "CUSTOM"]),
        Fixture(file: "flac.flac", format: "FLAC", codec: "FLAC", sampleRate: 8000, tagFormat: ["Vorbis Comment"],
                tag: "flac", markers: ["CUSTOM", "APPLICATION"]),
        Fixture(file: "vorbis.ogg", format: "Ogg Vorbis", codec: "Vorbis", sampleRate: 22050,
                tagFormat: ["Vorbis Comment"], tag: "ogg", markers: ["CUSTOM"]),
        Fixture(file: "opus.opus", format: "Ogg Opus", codec: "Opus", sampleRate: 48000, tagFormat: ["Vorbis Comment"],
                tag: "opus", markers: ["CUSTOM"]),
        Fixture(file: "speex.spx", format: "Ogg Speex", codec: "Speex", sampleRate: 8000, tagFormat: ["Vorbis Comment"],
                tag: "spx", markers: ["CUSTOM"]),
        Fixture(file: "oggflac.oga", format: "Ogg FLAC", codec: "FLAC", sampleRate: 8000, tagFormat: ["Vorbis Comment"],
                tag: "oga", markers: ["CUSTOM"]),
        Fixture(file: "wave.wav", format: "WAV", codec: "PCM", sampleRate: 8000, tagFormat: ["ID3v2.3", "RIFF INFO"],
                tag: "wav", markers: id3Markers + ["CHUNK"]),
        Fixture(file: "aiff.aiff", format: "AIFF", codec: "PCM", sampleRate: 8000, tagFormat: ["ID3v2.4"],
                tag: "aiff", markers: id3Markers + ["CHUNK"]),
        Fixture(file: "wma.wma", format: "Windows Media Audio", codec: "WMA", sampleRate: 8000, tagFormat: ["ASF"],
                tag: "wma", markers: ["CUSTOM"], hasYear: false,
                unsupported: [.work, .trackTotal, .compilation, .composerSort]),
        Fixture(file: "wavpack.wv", format: "WavPack", codec: "WavPack", sampleRate: 8000, tagFormat: ["APEv2"],
                tag: "wv", markers: ["CUSTOM"]),
        Fixture(file: "tta.tta", format: "TrueAudio", codec: "TTA", sampleRate: 8000, tagFormat: ["ID3v2.4"],
                tag: "tta", markers: id3Markers, hasComment: false),
        Fixture(file: "dsd.dsf", format: "DSF", codec: "DSD", sampleRate: 2_822_400, tagFormat: ["ID3v2.4"],
                tag: "dsf", markers: id3Markers, hasComment: false),
        Fixture(file: "dsd.dff", format: "DSDIFF", codec: "DSD", sampleRate: 2_822_400, tagFormat: ["ID3v2.4"],
                tag: "dff", markers: id3Markers, hasComment: false),
    ]

    static func named(_ file: String) -> Fixture { all.first { $0.file == file }! }

    static var directory: URL {
        Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
    }

    static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    static var png: Data { try! Data(contentsOf: url("cover.png")) }
    static var jpg: Data { try! Data(contentsOf: url("cover.jpg")) }
}

/// Basisklasse mit eigenem temporärem Ordner je Test.
class TagTestCase: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mltags-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            // restore write permissions so that everything can be removed
            if let enumerator = FileManager.default.enumerator(atPath: tempDir.path) {
                _ = chmod(tempDir.path, 0o755)
                for case let item as String in enumerator {
                    let path = tempDir.appendingPathComponent(item).path
                    var isDir: ObjCBool = false
                    _ = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
                    _ = chmod(path, isDir.boolValue ? 0o755 : 0o644)
                }
            }
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    /// Kopiert eine Test-Datei in den temporären Ordner.
    @discardableResult
    func copyFixture(_ name: String, as newName: String? = nil, into folder: URL? = nil) throws -> URL {
        let dir = folder ?? tempDir!
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent(newName ?? name)
        try FileManager.default.copyItem(at: Fixtures.url(name), to: target)
        _ = chmod(target.path, 0o644)
        return target
    }

    func bytes(_ url: URL) throws -> Data { try Data(contentsOf: url) }

    /// Enthält die Datei die Markierung (UTF-8, UTF-16LE oder UTF-16BE)?
    func containsMarker(_ data: Data, _ marker: String) -> Bool {
        let utf8 = Data(marker.utf8)
        var le = Data()
        var be = Data()
        for unit in marker.utf16 {
            le.append(UInt8(unit & 0xFF)); le.append(UInt8(unit >> 8))
            be.append(UInt8(unit >> 8)); be.append(UInt8(unit & 0xFF))
        }
        return data.range(of: utf8) != nil || data.range(of: le) != nil || data.range(of: be) != nil
    }

    func assertMarkers(_ fixture: Fixture, in url: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try bytes(url)
        for marker in fixture.markerStrings {
            XCTAssertTrue(containsMarker(data, marker), "\(fixture): marker \(marker) lost", file: file, line: line)
        }
    }

    /// Audio-Eigenschaften gleich (Dauer ±50 ms)?
    func assertSameAudio(_ a: AudioProperties, _ b: AudioProperties, _ context: String,
                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(abs(a.durationMs - b.durationMs), 50, "\(context): duration", file: file, line: line)
        XCTAssertEqual(a.sampleRate, b.sampleRate, "\(context): sample rate", file: file, line: line)
        XCTAssertEqual(a.channels, b.channels, "\(context): channels", file: file, line: line)
        XCTAssertEqual(a.codec, b.codec, "\(context): codec", file: file, line: line)
        XCTAssertEqual(a.bitsPerSample, b.bitsPerSample, "\(context): bits per sample", file: file, line: line)
    }

    func sha256(_ url: URL) throws -> String { try FileSystem.sha256(path: url.path) }

    func leftoverTempFiles(in dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix(".mltags-") }
    }
}

/// Werte mit Umlauten, Kyrillisch, Japanisch, Emoji, LRC-Liedtext – für alle Felder.
enum SampleValues {
    static var full: TagValues {
        var v = TagValues()
        v.title = "Grüße aus Köln – Привет – 日本語 – 🎵"
        v.artists = ["Ärzte", "Мумий Тролль", "宇多田ヒカル"]
        v.album = "Album ÄÖÜ ß 🎶"
        v.albumArtists = ["Various Ärtists", "Сборник"]
        v.composers = ["Комозитор", "作曲家"]
        v.grouping = "Gruppe 🎸"
        v.work = "Werk Nr. 1 – Allegro"
        v.genres = ["Kraut-Rock", "Электроника"]
        v.year = 1999
        v.trackNumber = 7
        v.trackTotal = 15
        v.discNumber = 2
        v.discTotal = 3
        v.compilation = true
        v.rating = 70
        v.bpm = 128
        v.comment = "Kommentar\nmit Zeilenumbruch 😀"
        v.lyrics = "[00:01.00]Erste Zeile mit Ümlaut\n[00:02.50]Вторая строка\n[00:04.00]三行目 🎤\n\n[00:06.00]Ende"
        v.titleSort = "Gruesse aus Koeln"
        v.artistSort = "Aerzte, Die"
        v.albumSort = "Album AOU"
        v.albumArtistSort = "Various Artists"
        v.composerSort = "Komponist"
        v.copyright = "℗ 2024 Ä Records"
        v.publisher = "Label ÄÖÜ"
        v.isrc = "DEA123456789"
        v.encodedBy = "Tester Ü"
        v.pictures = [
            EmbeddedPicture(kind: .frontCover, mimeType: "image/png", description: "Vorderseite 🎨", data: Fixtures.png),
            EmbeddedPicture(kind: .backCover, mimeType: "image/jpeg", description: "Rückseite", data: Fixtures.jpg),
        ]
        return v
    }

    static var fullEdit: TagEdit {
        let v = full
        return TagEdit(values: v, fields: Set(TagField.allCases), pictures: .replaceAll(v.pictures))
    }

    static var clearAll: TagEdit {
        TagEdit(values: TagValues(), fields: Set(TagField.allCases), pictures: .replaceAll([]))
    }
}
