import XCTest
@testable import MLCore

/// TextNorm und Formatting (Sollwerte der Formate mit der Kotlin-Fassung auf der JVM berechnet).
final class TextTests: XCTestCase {

    func testSchluessel() {
        XCTAssertEqual(TextNorm.key("  Björk   GUÐMUNDSDÓTTIR "), "bjork guðmundsdottir")
        XCTAssertEqual(TextNorm.key("Straße"), "strasse")
        XCTAssertEqual(TextNorm.key("Ærøskøbing Œuvre"), "aeroskobing oeuvre")
        XCTAssertEqual(TextNorm.key("Bjo\u{308}rk"), TextNorm.key("Bj\u{F6}rk"))
        XCTAssertEqual(TextNorm.key("a\tb\nc"), "a b c")
        XCTAssertEqual(TextNorm.key(nil), "")
        XCTAssertEqual(TextNorm.key(""), "")
        XCTAssertEqual(TextNorm.searchTerms("  Hey   JUDE "), ["hey", "jude"])
        XCTAssertTrue(TextNorm.matchesAll([], "x"))
    }

    func testTagBereinigen() {
        XCTAssertNil(TextNorm.cleanTag(nil))
        XCTAssertNil(TextNorm.cleanTag("   "))
        XCTAssertNil(TextNorm.cleanTag("<unknown>"))
        XCTAssertNil(TextNorm.cleanTag("Unknown"))
        XCTAssertNil(TextNorm.cleanTag("<Unbekannt>"))
        XCTAssertEqual(TextNorm.cleanTag(" Queen\u{0}\u{1} "), "Queen")
        XCTAssertEqual(TextNorm.cleanTag("Unknown Pleasures"), "Unknown Pleasures")
        XCTAssertEqual(TextNorm.cleanTag("Zeile 1\nZeile 2"), "Zeile 1\nZeile 2")
    }

    func testDateinamen() {
        XCTAssertEqual(TextNorm.fileNameWithoutExtension("Song.mp3"), "Song")
        XCTAssertEqual(TextNorm.fileNameWithoutExtension(".hidden"), ".hidden")
        XCTAssertEqual(TextNorm.fileNameWithoutExtension("a.b.flac"), "a.b")
        XCTAssertEqual(TextNorm.fileExtension("Song.m4a"), "M4A")
        XCTAssertEqual(TextNorm.fileExtension("Song"), "")
        XCTAssertEqual(TextNorm.fileExtension("Song."), "")
        XCTAssertEqual(TextNorm.fileExtension(".flac"), "FLAC")
    }

    func testFormate_wieKotlin() {
        let actual = [
            Formatting.fileSize(3_565_158), Formatting.fileSize(512_000), Formatting.fileSize(1_048_576),
            Formatting.fileSize(1_101_004), Formatting.fileSize(1_153_434), Formatting.fileSize(0),
            Formatting.bitrate(bitsPerSecond: 256_000), Formatting.bitrate(bitsPerSecond: 127_500),
            Formatting.percent(1.5), Formatting.percent(0.005),
            Formatting.decibel(0.24), Formatting.decibel(0.25), Formatting.decibel(-0.75),
            Formatting.semitones(1.25), Formatting.semitones(-0.04), Formatting.semitones(2),
            Formatting.factor(0.5), Formatting.factor(2), Formatting.factor(1.005),
            Formatting.sampleRate(22050), Formatting.sampleRate(88200), Formatting.sampleRate(0),
            Formatting.longDuration(29_999), Formatting.longDuration(30_000), Formatting.longDuration(3_600_000),
            Formatting.duration(-5), Formatting.countdown(1), Formatting.integer(-1_234_567), Formatting.integer(999),
            Formatting.channels(6),
        ]
        let expected = "3,4 MB|500 KB|1,0 MB|1,0 MB|1,1 MB|0 KB|256 kbit/s|128 kbit/s|150 %|1 %|0 dB|+0,5 dB|−0,5 dB|+1,3 Halbtöne|Original|+2 Halbtöne|0,50×|2,00×|1,01×|22,1 kHz|88,2 kHz|0 kHz|0 Min.|1 Min.|1 Std.|0:00|0:01|-1.234.567|999|6 Kanäle"
        XCTAssertEqual(actual.joined(separator: "|"), expected)
    }

    func testFormate_weitere() {
        XCTAssertEqual(Formatting.bitrate(kbps: 1411), "1.411 kbit/s")
        XCTAssertEqual(Formatting.channels(1), "Mono (1 Kanal)")
        XCTAssertEqual(Formatting.albums(2), "2 Alben")
        XCTAssertEqual(Formatting.plays(1), "1 Wiedergabe")
        XCTAssertEqual(Formatting.hits(10_000), "10.000 Treffer")
        XCTAssertEqual(Formatting.duration(36_000_000), "10:00:00")
        XCTAssertEqual(Formatting.fixed(0.25, digits: 1), "0.3") // „halb auf“ wie Java
        XCTAssertEqual(Formatting.fixed(9.96, digits: 1), "10.0")
        XCTAssertEqual(Formatting.fixed(-1.25, digits: 1), "-1.3")
        XCTAssertEqual(Formatting.fixed(1e-7, digits: 2), "0.00")
        XCTAssertEqual(Formatting.fixed(123456789.0, digits: 0), "123456789")
        XCTAssertEqual(Formatting.dateTime(0, timeZone: TimeZone(identifier: "UTC")!), "01.01.1970, 00:00")
    }

    func testStabilesSortieren() {
        struct X { let k: Int; let tag: String }
        let items = [X(k: 1, tag: "a"), X(k: 0, tag: "b"), X(k: 1, tag: "c"), X(k: 0, tag: "d")]
        XCTAssertEqual(Ordering<X>.by(\.k).sorted(items).map(\.tag), ["b", "d", "a", "c"])
        XCTAssertEqual(Ordering<X>.by(\.k).reversed.sorted(items).map(\.tag), ["a", "c", "b", "d"])
    }
}
