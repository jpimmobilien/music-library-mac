import XCTest
@testable import MLCore

final class LyricsParserTests: XCTestCase {

    func testZeitmarkenFormate() {
        XCTAssertEqual(LyricsParser.parseTime("01:02.34"), 62_340)
        XCTAssertEqual(LyricsParser.parseTime("01:02"), 62_000)
        XCTAssertEqual(LyricsParser.parseTime("01:02:34"), 62_340) // [mm:ss:xx]
        XCTAssertEqual(LyricsParser.parseTime("00:05.5"), 5_500) // Zehntel
        XCTAssertEqual(LyricsParser.parseTime("00:05.123"), 5_123) // Millisekunden
        XCTAssertEqual(LyricsParser.parseTime("123:00.00"), 7_380_000) // lange Titel
        XCTAssertEqual(LyricsParser.parseTime("1:2"), 62_000)
        XCTAssertNil(LyricsParser.parseTime("00:75.00"))
        XCTAssertNil(LyricsParser.parseTime("ar:Queen"))
        XCTAssertNil(LyricsParser.parseTime("00:12.3456"))
        XCTAssertNil(LyricsParser.parseTime("00:12."))
        XCTAssertNil(LyricsParser.parseTime(""))
    }

    func testSynchronisiert_mitKopfOffsetUndMehrerenMarken() {
        let lrc = """
        [ar:Queen]
        [ti:Bohemian Rhapsody]
        [al:A Night at the Opera]
        [by:Jemand]
        [length:05:55]
        [offset:+500]
        [00:01.00]Is this the real life?
        [00:05.50][01:30.00]Is this just fantasy?
        [00:10.00]
        [00:12.00]<00:12.00>Caught <00:12.50>in a <00:13.00>landslide
        """
        let l = LyricsParser.parse(lrc)
        XCTAssertTrue(l.isSynced)
        XCTAssertNil(l.plainText)
        XCTAssertEqual(l.offsetMs, 500)
        XCTAssertEqual(l.tag("ar"), "Queen")
        XCTAssertEqual(l.tag("TI"), "Bohemian Rhapsody")
        XCTAssertEqual(l.tags.map(\.key), ["ar", "ti", "al", "by", "length"])
        XCTAssertEqual(l.lines, [
            LyricLine(timeMs: 500, text: "Is this the real life?"),
            LyricLine(timeMs: 5_000, text: "Is this just fantasy?"),
            LyricLine(timeMs: 9_500, text: ""), // instrumentale Pause
            LyricLine(timeMs: 11_500, text: "Caught in a landslide"),
            LyricLine(timeMs: 89_500, text: "Is this just fantasy?"),
        ])
        XCTAssertTrue(l.lines[2].isGap)
    }

    func testNegativerOffset_spaeter_undNieUnterNull() {
        let later = LyricsParser.parse("[offset:-250]\n[00:01.00]A")
        XCTAssertEqual(later.lines.first?.timeMs, 1_250)
        let clamped = LyricsParser.parse("[offset:2000]\n[00:01.00]A")
        XCTAssertEqual(clamped.lines.first?.timeMs, 0)
    }

    func testSortierungNachZeit_stabilBeiGleicherZeit() {
        let l = LyricsParser.parse("[00:20.00]C\n[00:10.00]A\n[00:10.00]B\n[00:05.00]Start")
        XCTAssertEqual(l.lines.map(\.text), ["Start", "A", "B", "C"])
    }

    func testZeilenendenUndBOM() {
        let l = LyricsParser.parse("\u{FEFF}[00:01.00]Eins\r\n[00:02.00]Zwei\r[00:03.00]Drei")
        XCTAssertEqual(l.lines.map(\.text), ["Eins", "Zwei", "Drei"])
    }

    func testUnsynchronisiert_unveraendertDurchgereicht() {
        let plain = "Strophe 1\n[Refrain]\n  eingerückt\n\nLetzte Zeile\n"
        let l = LyricsParser.parse(plain)
        XCTAssertFalse(l.isSynced)
        XCTAssertEqual(l.plainText, plain)
        XCTAssertEqual(l.serialized(), plain)
        XCTAssertTrue(l.lines.isEmpty)
        XCTAssertNil(l.lineIndex(at: 1_000))
        XCTAssertFalse(LyricsParser.isSynced(""))
        XCTAssertEqual(LyricsParser.parse("").plainText, "")
    }

    func testEinzelneZeitangabeImNormalenText_bleibtUnsynchronisiert() {
        let text = "Zeile eins\nZeile zwei\n[00:30] Gitarrensolo\nZeile drei\nZeile vier"
        XCTAssertFalse(LyricsParser.isSynced(text))
    }

    func testSynchronisiert_mitEinzelnenZeilenOhneMarke() {
        let text = "Liedtext von Jemand\n[00:01.00]A\n[00:02.00]B\n[00:03.00]C"
        let l = LyricsParser.parse(text)
        XCTAssertTrue(l.isSynced)
        XCTAssertEqual(l.lines.count, 3)
    }

    func testNurKopfzeilen_nichtSynchronisiert() {
        XCTAssertFalse(LyricsParser.isSynced("[ar:Queen]\n[ti:Song]"))
        // Kopfzeile mit Text danach ist keine Kopfzeile
        let l = LyricsParser.parse("[ar:Queen] Text\n[00:01.00]A")
        XCTAssertTrue(l.tags.isEmpty)
    }

    func testZeilenindex_binaereSuche() {
        let l = LyricsParser.parse("[00:10.00]A\n[00:20.00]B\n[00:30.00]C")
        XCTAssertNil(l.lineIndex(at: 9_999))
        XCTAssertEqual(l.lineIndex(at: 10_000), 0)
        XCTAssertEqual(l.lineIndex(at: 19_999), 0)
        XCTAssertEqual(l.lineIndex(at: 20_000), 1)
        XCTAssertEqual(l.lineIndex(at: 999_999), 2)
        XCTAssertNil(LyricsParser.lineIndex(in: [], at: 5))
        let dup = [LyricLine(timeMs: 5, text: "a"), LyricLine(timeMs: 5, text: "b"), LyricLine(timeMs: 9, text: "c")]
        XCTAssertEqual(LyricsParser.lineIndex(in: dup, at: 5), 1) // letzte Zeile mit dieser Zeit
    }

    func testSchreiben_undWiederLesen() {
        let lines = [LyricLine(timeMs: 62_345, text: "B"), LyricLine(timeMs: 1_000, text: "A"), LyricLine(timeMs: 70_000, text: "")]
        let text = LyricsParser.serialize(lines, tags: [LyricsTag(key: "ar", value: "Queen"), LyricsTag(key: "offset", value: "100")])
        XCTAssertEqual(text, "[ar:Queen]\n[00:01.00]A\n[01:02.35]B\n[01:10.00]")
        let back = LyricsParser.parse(text)
        XCTAssertEqual(back.lines.map(\.text), ["A", "B", ""])
        XCTAssertEqual(back.lines.map(\.timeMs), [1_000, 62_350, 70_000])
        XCTAssertEqual(back.tag("ar"), "Queen")
        // Roundtrip eines geparsten Texts ist stabil
        XCTAssertEqual(LyricsParser.parse(back.serialized()), back)
    }

    func testZeitFormat() {
        XCTAssertEqual(LyricsParser.formatTimestamp(0), "00:00.00")
        XCTAssertEqual(LyricsParser.formatTimestamp(59_995), "01:00.00") // Rundung mit Übertrag
        XCTAssertEqual(LyricsParser.formatTimestamp(7_380_000), "123:00.00")
        XCTAssertEqual(LyricsParser.formatTimestamp(-5), "00:00.00")
    }

    func testOffsetWirdBeimSchreibenEingerechnet() {
        let l = LyricsParser.parse("[offset:+1000]\n[00:05.00]A")
        XCTAssertEqual(l.serialized(), "[00:04.00]A")
    }
}
