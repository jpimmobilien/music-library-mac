import XCTest
@testable import MLCore

/// Die Nachbildung des deutschen Java-Collators (`NaturalOrder`) gegen Werte, die mit der JVM erzeugt
/// wurden (`Collator.getInstance(Locale.GERMAN)`, Stärke SECONDARY, plus Kotlin-`compareNatural`).
final class NaturalOrderJvmTests: XCTestCase {

    static let input: [String] = [
        "Track 10", "track 2", "Track 1", "\u{C4}pfel", "Zebra", "apfel", "Apfel", "\u{E4}pfel", "a b", "ab",
        "a-b", "\u{E4}b", "Ab", "(Intro)", "_hidden", "01 Song", "1 Song", "001 Song", "10 Song", "2 Song",
        "Song", "song 2b", "song 2a", "Stra\u{DF}e", "Strasse", "Stra", "\u{152}uvre", "Oeuvre",
        "\u{D8}rsted", "Zoo", "\u{395}\u{3BB}\u{3BB}\u{3AC}\u{3B4}\u{3B1}",
        "\u{41C}\u{43E}\u{441}\u{43A}\u{432}\u{430}", "\u{65E5}\u{672C}", "\u{201C}Quote\u{201D}",
        "\"Quote\"", "'Tis", "Don't", "Don\u{2019}t", "Dont", "#1 Hits", "!Bang", "~tilde", "\u{C9}t\u{E9}",
        "Ete", "ete", "Et\u{EB}", "Caf\u{E9} Del Mar", "Cafe del Mar", "", " ", "x", "X", "x1", "x01", "x 1",
        "x-1", "A/B", "A.B", "A,B", "A&B", "a+b", "\u{B5}", "\u{A9}2000", "\u{C4}rzte", "Arzte", "Aerzte",
        "\u{C6}ON", "aeon", "na\u{EF}ve", "naive", "Ninja 7", "Ninja 07", "Ninja 7.5", "Ninja 7,5", "  lead",
        "lead", "Tab\u{9}X", "TabX", "M\u{E4}dchen", "Madchen", "Maedchen",
    ]

    /// Ergebnis von `input.sortedWith(NaturalOrder.comparator())` auf der JVM.
    static let expected: [String] = [
        "", " ", "_hidden", "!Bang", "~tilde", "'Tis", "\"Quote\"", "(Intro)", "\u{A9}2000", "#1 Hits",
        "\u{B5}", "1 Song", "01 Song", "001 Song", "2 Song", "10 Song", "A,B", "A/B", "A.B", "A&B", "a+b",
        "Ab", "ab", "a b", "\u{E4}b", "a-b", "aeon", "\u{C6}ON", "Aerzte", "Apfel", "apfel", "\u{C4}pfel",
        "\u{E4}pfel", "Arzte", "\u{C4}rzte", "Cafe del Mar", "Caf\u{E9} Del Mar", "Don't", "Dont",
        "Don\u{2019}t", "Ete", "ete", "Et\u{EB}", "\u{C9}t\u{E9}", "lead", "  lead", "Madchen",
        "M\u{E4}dchen", "Maedchen", "naive", "na\u{EF}ve", "Ninja 7", "Ninja 7,5", "Ninja 7.5", "Ninja 07",
        "Oeuvre", "\u{152}uvre", "Song", "song 2a", "song 2b", "Stra", "Strasse", "Stra\u{DF}e", "TabX",
        "Tab\u{9}X", "Track 1", "track 2", "Track 10", "X", "x", "x1", "x01", "x 1", "x-1", "Zebra", "Zoo",
        "\u{D8}rsted", "\u{395}\u{3BB}\u{3BB}\u{3AC}\u{3B4}\u{3B1}",
        "\u{41C}\u{43E}\u{441}\u{43A}\u{432}\u{430}", "\u{201C}Quote\u{201D}", "\u{65E5}\u{672C}",
    ]

    func testSortierungWieAufDerJvm() {
        XCTAssertEqual(Self.input.count, Self.expected.count)
        let sorted = NaturalOrder.comparator().sorted(Self.input)
        for (i, (a, b)) in zip(sorted, Self.expected).enumerated() where !a.utf16.elementsEqual(b.utf16) {
            XCTFail("Position \(i): \(a.debugDescription) statt \(b.debugDescription)")
            break
        }
    }

    func testSortierungUnabhaengigVonEingabereihenfolge() {
        let sorted1 = NaturalOrder.comparator().sorted(Self.input.reversed())
        let sorted2 = NaturalOrder.comparator().sorted(Self.expected.shuffled())
        XCTAssertTrue(sorted1.elementsEqual(Self.expected) { $0.utf16.elementsEqual($1.utf16) })
        XCTAssertTrue(sorted2.elementsEqual(Self.expected) { $0.utf16.elementsEqual($1.utf16) })
    }

    func testStringHashCodeWieJvm() {
        // JVM: listOf(…).map { it.lowercase().hashCode() }
        let texts = ["rock", "hip-hop", "\u{E4}\u{F6}\u{FC}", "Pop", "", "Darkwave", "Schlager & Volksmusik", "\u{65E5}\u{672C}"]
        let expected: [Int32] = [3506021, 922041611, 226986, 111185, 0, 1742067567, 1073433765, 835047]
        XCTAssertEqual(texts.map { $0.lowercased().javaHashCode }, expected)
    }

    func testCollatorEinzelregeln() {
        XCTAssertEqual(NaturalOrder.collate("ab", "AB"), 0) // Groß/klein egal
        XCTAssertEqual(NaturalOrder.collate("\u{DF}", "ss"), 0) // ß = ss
        XCTAssertEqual(NaturalOrder.collate("\u{E6}", "ae"), 0) // æ = ae
        XCTAssertLessThan(NaturalOrder.collate("ab", "a b"), 0)
        XCTAssertLessThan(NaturalOrder.collate("a b", "\u{E4}b"), 0)
        XCTAssertLessThan(NaturalOrder.collate("\u{E4}b", "a-b"), 0)
        XCTAssertGreaterThan(NaturalOrder.collate("x", "(x"), 0)
        XCTAssertEqual(NaturalOrder.collate("a\u{200B}b", "ab"), 0) // Formatzeichen bedeutungslos
        // vorzerlegt und zusammengesetzt sind für den Collator gleich
        XCTAssertEqual(NaturalOrder.collate("Bjo\u{308}rk", "Bj\u{F6}rk"), 0)
    }
}
