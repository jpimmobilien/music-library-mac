import Foundation

/// Regeln für Interpretennamen (Portierung von `library/ArtistNames.kt`).
///
/// - Namen werden NICHT an „&“, „/“ oder „,“ getrennt („Simon & Garfunkel“, „AC/DC“,
///   „Earth, Wind & Fire“ bleiben eins).
/// - Getrennt wird nur an ausdrücklichen Gastnennungen („feat.“, „ft.“, „featuring“): „A feat. B“
///   → Hauptinterpret „A“, Gast „B“. Erst innerhalb der Gastliste werden „,“, „&“, „und“, „and“ getrennt.
/// - „Various Artists“ und Varianten gelten als Sammel-Bezeichnung, nicht als Interpret.
///
/// Die Kotlin-Regex (`\s*[(\[]?\s*\b(?:feat\.?|ft\.|featuring)\s+`, ohne Groß-/Kleinschreibung) ist hier
/// als kleiner Zeichen-Scanner mit identischer Semantik nachgebaut (Java-`\s` = ASCII-Leerraum,
/// `\b` = Grenze zu Buchstabe/Ziffer/„_“) – unabhängig von ICU und daher auf allen Plattformen gleich.
public enum ArtistNames {

    static let variousKeys: Set<String> = [
        "various artists", "various", "va", "v.a.", "v. a.", "verschiedene interpreten", "verschiedene kunstler",
        "diverse", "diverse interpreten", "div. interpreten", "compilation", "sampler",
    ]

    public struct Split: Hashable, Sendable {
        public var primary: String
        public var guests: [String]

        public init(primary: String, guests: [String]) {
            self.primary = primary
            self.guests = guests
        }
    }

    public static func split(_ name: String) -> Split {
        // Schneller Weg: ohne „fe“/„ft“ (beliebige Schreibweise) kann keine Gastnennung vorkommen.
        if !mayContainFeat(name) { return Split(primary: name.kotlinTrimmed(), guests: []) }
        let scalars = Array(name.unicodeScalars)
        guard let match = findFeat(scalars) else { return Split(primary: name.kotlinTrimmed(), guests: []) }
        let primary = String(String.UnicodeScalarView(scalars[0..<match.lowerBound]))
            .kotlinTrimmed()
            .trimmingTrailingScalars { $0 == "(" || $0 == "[" }
            .kotlinTrimmed()
        let rest = String(String.UnicodeScalarView(scalars[match.upperBound...]))
            .kotlinTrimmed()
            .trimmingTrailingScalars { $0 == ")" || $0 == "]" }
            .kotlinTrimmed()
        let guests = splitGuests(rest)
            .map { $0.kotlinTrimmed().trimmingScalars { "()[]".unicodeScalars.contains($0) }.kotlinTrimmed() }
            .filter { !$0.isEmpty }
        if primary.isEmpty { return Split(primary: name.kotlinTrimmed(), guests: []) }
        return Split(primary: primary, guests: guests)
    }

    /// Hauptinterpret(en) eines Titels (ohne Gäste).
    public static func primaries(_ artists: [String]) -> [String] {
        artists.map { split($0).primary }.filter { !$0.isEmpty }
    }

    /// Gäste eines Titels.
    public static func guests(_ artists: [String]) -> [String] {
        artists.flatMap { split($0).guests }
    }

    public static func isVarious(_ name: String?) -> Bool {
        guard let name else { return false }
        return variousKeys.contains(TextNorm.key(name))
    }

    public static func key(_ name: String) -> String { TextNorm.key(name) }

    // MARK: - Scanner

    private static func mayContainFeat(_ name: String) -> Bool {
        var previousF = false
        for b in name.utf8 {
            let lower = b | 0x20
            if previousF && (lower == 0x65 || lower == 0x74) { return true } // e, t
            previousF = lower == 0x66 // f
        }
        return false
    }

    private static let featWords: [[Unicode.Scalar]] = ["feat.", "feat", "ft.", "featuring"].map { Array($0.unicodeScalars) }
    private static let guestWords: [[Unicode.Scalar]] = ["und", "and"].map { Array($0.unicodeScalars) }

    private static func isSpace(_ s: Unicode.Scalar) -> Bool { KotlinChars.isRegexSpace(s) }

    /// Wortgrenze vor Position `i` (zwischen `i-1` und `i`).
    private static func isBoundary(_ scalars: [Unicode.Scalar], _ i: Int) -> Bool {
        let before = i > 0 && KotlinChars.isWordChar(scalars[i - 1])
        let after = i < scalars.count && KotlinChars.isWordChar(scalars[i])
        return before != after
    }

    /// Passt `word` (ASCII, ohne Groß-/Kleinschreibung) an Position `i`?
    private static func matchesWord(_ scalars: [Unicode.Scalar], _ i: Int, _ w: [Unicode.Scalar]) -> Bool {
        guard i + w.count <= scalars.count else { return false }
        for k in 0..<w.count {
            let s = scalars[i + k]
            let lower = (s.value >= 0x41 && s.value <= 0x5A) ? s.value + 0x20 : s.value
            if lower != w[k].value { return false }
        }
        return true
    }

    /// Erste Fundstelle der Gastnennung als Bereich [Beginn, Ende) in Unicode-Skalaren.
    static func findFeat(_ scalars: [Unicode.Scalar]) -> Range<Int>? {
        let n = scalars.count
        for start in 0...n {
            var i = start
            while i < n && isSpace(scalars[i]) { i += 1 }
            if i < n && (scalars[i] == "(" || scalars[i] == "[") { i += 1 }
            while i < n && isSpace(scalars[i]) { i += 1 }
            guard isBoundary(scalars, i) else { continue }
            // Alternativen in Regex-Reihenfolge: „feat.“, „feat“, „ft.“, „featuring“ – jeweils gefolgt von Leerraum.
            for word in featWords where matchesWord(scalars, i, word) {
                var j = i + word.count
                guard j < n && isSpace(scalars[j]) else { continue }
                while j < n && isSpace(scalars[j]) { j += 1 }
                return start..<j
            }
        }
        return nil
    }

    /// Trennt die Gastliste an „,“, „&“, „und“, „and“ (als ganze Wörter) – wie Kotlin `split(Regex)`.
    static func splitGuests(_ text: String) -> [String] {
        let scalars = Array(text.unicodeScalars)
        let n = scalars.count
        var pieces: [String] = []
        var pieceStart = 0
        var start = 0
        while start < n {
            var matchedEnd: Int?
            var i = start
            while i < n && isSpace(scalars[i]) { i += 1 }
            if i < n {
                if scalars[i] == "," || scalars[i] == "&" {
                    matchedEnd = i + 1
                } else {
                    for word in guestWords where isBoundary(scalars, i) && matchesWord(scalars, i, word) {
                        let end = i + 3
                        if isBoundary(scalars, end) {
                            matchedEnd = end
                            break
                        }
                    }
                }
            }
            if var end = matchedEnd {
                while end < n && isSpace(scalars[end]) { end += 1 }
                pieces.append(String(String.UnicodeScalarView(scalars[pieceStart..<start])))
                pieceStart = end
                start = end
            } else {
                start += 1
            }
        }
        pieces.append(String(String.UnicodeScalarView(scalars[pieceStart..<n])))
        return pieces
    }
}
