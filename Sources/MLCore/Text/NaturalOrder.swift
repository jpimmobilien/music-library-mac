import Foundation

/// Vergleiche für eine natürliche, deutsche Sortierung (Portierung von `core/NaturalOrder.kt`).
///
/// - Zahlen in Texten werden als Zahlen verglichen („2 Song“ vor „10 Song“).
/// - Textteile werden wie mit `java.text.Collator.getInstance(Locale.GERMAN)` in Stärke SECONDARY
///   verglichen: deutsches Alphabet, Groß-/Kleinschreibung egal, Akzente zweitrangig.
///
/// ## Nachbildung des Java-Collators (deterministisch, ohne ICU/Locale)
/// Android verwendet `java.text.Collator`. Auf macOS/Linux gibt es keinen gleichwertigen,
/// plattformunabhängigen Collator; deshalb wird er mit festen Regeln nachgebildet, die anhand der JVM
/// ermittelt wurden:
/// 1. **Erste Stufe (Grundbuchstaben):** Text wird kanonisch zerlegt (NFD), kombinierende Akzente
///    zählen hier nicht, Kleinschreibung, „ß“ = „ss“, „æ“ = „ae“, „œ“ = „oe“. Leerraum und Bindestriche
///    (- – — U+2010, U+2212, weiches Trennzeichen) werden auf dieser Stufe übersprungen; Steuer- und
///    Formatzeichen (z. B. U+200B) sind vollständig bedeutungslos.
///    Reihenfolge der Zeichenklassen: Satzzeichen/Symbole (in der Java-Reihenfolge
///    _ , ; : ! ¡ ? ¿ / . ´ Gravis ^ ~ · ' " « » ( ) [ ] { } § © ® @ ¢ $ € £ ¥ * \ & # % + ÷ × < = > | ° µ)
///    < Ziffern < Buchstaben (a–z, danach weitere lateinische/griechische/kyrillische Buchstaben nach
///    Codepunkt) < alle übrigen Zeichen nach Codepunkt (z. B. typografische Anführungszeichen, ™, CJK) –
///    wie bei Java, wo nicht geregelte Zeichen hinter allen Buchstaben stehen.
/// 2. **Zweite Stufe (nur bei Gleichstand):** Folge der Akzente und übersprungenen Zeichen in
///    Textreihenfolge; Grundbuchstabe < Leerzeichen < geschütztes Leerzeichen < Akzente
///    (´ < ` < ˘ < ^ < ˇ < ˚ < ¨ < ˝ < ~ < ˙, weitere nach Codepunkt) < Bindestriche.
///    „ab“ < „a b“ < „äb“ < „a-b“ – genau wie Java.
/// 3. Gleichstand auch dort (z. B. nur Groß-/Kleinschreibung verschieden): wie in Kotlin entscheidet
///    zuletzt der exakte Vergleich nach UTF-16-Code-Units (`String.compareTo`).
public enum NaturalOrder {

    /// Vergleich mit Zwischenspeicher für Schlüssel (nicht threadsicher → je Sortiervorgang neu anlegen,
    /// wie der Collator in Kotlin).
    public static func comparator() -> NaturalComparator { NaturalComparator() }

    /// Text-Vergleich nach deutschem Alphabet mit natürlicher Zahlenreihenfolge (-1/0/1-artig).
    public static func compareNatural(_ a: String, _ b: String) -> Int {
        compare(NaturalKey(a), NaturalKey(b))
    }

    public static func compare(_ a: NaturalKey, _ b: NaturalKey) -> Int {
        let n = min(a.parts.count, b.parts.count)
        for i in 0..<n {
            let pa = a.parts[i]
            let pb = b.parts[i]
            let result = (pa.isDigits && pb.isDigits) ? compareNumbers(pa, pb) : collate(pa, pb)
            if result != 0 { return result }
        }
        let bySize = a.parts.count.compareTo(b.parts.count)
        if bySize != 0 { return bySize }
        // Gleich nach Collator: für eine stabile Reihenfolge exakt vergleichen.
        return a.original.javaCompare(b.original).signum()
    }

    /// Nur der Collator-Teil (ohne Zahlen-Logik), z. B. für Tests: 0 = gleichwertig.
    public static func collate(_ a: String, _ b: String) -> Int {
        collate(NaturalKey.Part.make(text: a, isDigits: false), NaturalKey.Part.make(text: b, isDigits: false))
    }

    static func compareNumbers(_ a: NaturalKey.Part, _ b: NaturalKey.Part) -> Int {
        if a.trimmedDigits.count != b.trimmedDigits.count { return a.trimmedDigits.count.compareTo(b.trimmedDigits.count) }
        let byValue = lexicographic(a.trimmedDigits, b.trimmedDigits)
        if byValue != 0 { return byValue }
        return a.length.compareTo(b.length)
    }

    static func collate(_ a: NaturalKey.Part, _ b: NaturalKey.Part) -> Int {
        let p = lexicographic(a.primary, b.primary)
        if p != 0 { return p }
        return lexicographic(a.secondary, b.secondary)
    }

    private static func lexicographic(_ a: [UInt32], _ b: [UInt32]) -> Int {
        let n = min(a.count, b.count)
        for i in 0..<n where a[i] != b[i] { return a[i] < b[i] ? -1 : 1 }
        return a.count.compareTo(b.count)
    }

    // MARK: - Gewichte

    /// Satzzeichen/Symbole in der Reihenfolge des deutschen Java-Collators (auf der JVM ermittelt).
    static let punctuationRank: [UInt32: UInt32] = {
        let order: [UInt32] = [
            0x5F, 0x2C, 0x3B, 0x3A, 0x21, 0xA1, 0x3F, 0xBF, 0x2F, 0x2E, 0xB4, 0x60, 0x5E, 0x7E, 0xB7, 0x27,
            0x22, 0xAB, 0xBB, 0x28, 0x29, 0x5B, 0x5D, 0x7B, 0x7D, 0xA7, 0xA9, 0xAE, 0x40, 0xA2, 0x24, 0x20AC,
            0xA3, 0xA5, 0x2A, 0x5C, 0x26, 0x23, 0x25, 0x2B, 0xF7, 0xD7, 0x3C, 0x3D, 0x3E, 0x7C, 0xB0, 0xB5,
        ]
        var map: [UInt32: UInt32] = [:]
        for (i, v) in order.enumerated() { map[v] = UInt32(i + 1) }
        return map
    }()

    /// Akzente (zweite Stufe) in Java-Reihenfolge.
    static let markRank: [UInt32: UInt32] = {
        let order: [UInt32] = [0x301, 0x300, 0x306, 0x302, 0x30C, 0x30A, 0x30D, 0x308, 0x30B, 0x303, 0x307]
        var map: [UInt32: UInt32] = [:]
        for (i, v) in order.enumerated() { map[v] = UInt32(i + 1) }
        return map
    }()

    /// Bindestriche: auf der ersten Stufe übersprungen, auf der zweiten nach den Akzenten.
    static let hyphenRank: [UInt32: UInt32] = [0x2D: 1, 0xAD: 2, 0x2010: 3, 0x2011: 4, 0x2012: 5, 0x2013: 6, 0x2014: 7, 0x2015: 8, 0x2212: 9]

    static let classPunctuation: UInt32 = 1 << 24
    static let classDigit: UInt32 = 2 << 24
    static let classLetter: UInt32 = 3 << 24
    static let classOther: UInt32 = 4 << 24

    struct AsciiWeight {
        enum Kind { case ignore, secondaryOnly, base }
        let kind: Kind
        let primary: UInt32
        let secondary: UInt32
    }

    /// Gewichte aller ASCII-Zeichen (dieselben Regeln wie für beliebige Zeichen, vorab berechnet).
    static let asciiTable: [AsciiWeight] = (0..<128).map { v -> AsciiWeight in
        let s = Unicode.Scalar(UInt8(v))
        if let rank = hyphenRank[UInt32(v)] { return AsciiWeight(kind: .secondaryOnly, primary: 0, secondary: 1000 + rank) }
        if KotlinChars.isWhitespace(s) { return AsciiWeight(kind: .secondaryOnly, primary: 0, secondary: v == 0x20 ? 1 : 2) }
        if s.properties.generalCategory == .control { return AsciiWeight(kind: .ignore, primary: 0, secondary: 0) }
        let lower = (v >= 0x41 && v <= 0x5A) ? Unicode.Scalar(UInt8(v + 0x20)) : s
        return AsciiWeight(kind: .base, primary: primaryWeight(lower), secondary: 0)
    }

    static func primaryWeight(_ s: Unicode.Scalar) -> UInt32 {
        let v = s.value
        if let rank = punctuationRank[v] { return classPunctuation | rank }
        if v >= 0x30 && v <= 0x39 { return classDigit | v }
        if v < 0x0530 {
            switch s.properties.generalCategory {
            case .lowercaseLetter, .uppercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
                return classLetter | v
            default:
                break
            }
        }
        return classOther | v
    }
}

/// Vorberechneter Sortierschlüssel eines Textes für `NaturalOrder`.
public struct NaturalKey: Comparable, Hashable, Sendable {
    struct Part: Hashable, Sendable {
        let isDigits: Bool
        /// Länge in UTF-16-Code-Units (wie `String.length` in Kotlin).
        let length: Int
        /// Ziffern ohne führende Nullen (nur bei Ziffernteilen).
        let trimmedDigits: [UInt32]
        let primary: [UInt32]
        let secondary: [UInt32]

        /// Schneller Weg für ASCII-Teile (Bytes); gleiche Regeln wie unten.
        init(ascii bytes: ArraySlice<UInt8>, isDigits: Bool) {
            self.isDigits = isDigits
            length = bytes.count
            trimmedDigits = isDigits ? bytes.drop(while: { $0 == 0x30 }).map { UInt32($0) } : []
            var primary: [UInt32] = []
            var secondary: [UInt32] = []
            primary.reserveCapacity(bytes.count)
            secondary.reserveCapacity(bytes.count)
            for b in bytes {
                let w = NaturalOrder.asciiTable[Int(b)]
                switch w.kind {
                case .ignore: continue
                case .secondaryOnly: secondary.append(w.secondary)
                case .base:
                    primary.append(w.primary)
                    secondary.append(0)
                }
            }
            self.primary = primary
            self.secondary = secondary
        }

        static func make(text: String, isDigits: Bool) -> Part {
            if text.utf8.allSatisfy({ $0 < 0x80 }) {
                return Part(ascii: Array(text.utf8)[...], isDigits: isDigits)
            }
            return Part(unicode: Array(text.unicodeScalars)[...], isDigits: isDigits)
        }

        init(unicode scalars: ArraySlice<Unicode.Scalar>, isDigits: Bool) {
            self.isDigits = isDigits
            length = scalars.reduce(0) { $0 + UTF16.width($1) }
            if isDigits {
                trimmedDigits = Array(scalars.drop(while: { $0 == "0" }).map(\.value))
            } else {
                trimmedDigits = []
            }
            var primary: [UInt32] = []
            var secondary: [UInt32] = []
            func base(_ e: Unicode.Scalar) {
                primary.append(NaturalOrder.primaryWeight(e))
                secondary.append(0)
            }
            for s in TextNorm.decomposedScalars(scalars) {
                let v = s.value
                if v < 0x80 {
                    let w = NaturalOrder.asciiTable[Int(v)]
                    switch w.kind {
                    case .ignore: break
                    case .secondaryOnly: secondary.append(w.secondary)
                    case .base:
                        primary.append(w.primary)
                        secondary.append(0)
                    }
                    continue
                }
                if let rank = NaturalOrder.hyphenRank[v] {
                    secondary.append(1000 + rank)
                    continue
                }
                if KotlinChars.isWhitespace(s) {
                    secondary.append(2)
                    continue
                }
                let props = s.properties
                let category = props.generalCategory
                if category == .control || category == .format { continue }
                if category == .nonspacingMark {
                    secondary.append(100 + (NaturalOrder.markRank[v] ?? (100 + (v & 0xFFFF))))
                    continue
                }
                func expand(_ lower: Unicode.Scalar) {
                    switch lower {
                    case "ß": base("s"); base("s")
                    case "æ": base("a"); base("e")
                    case "œ": base("o"); base("e")
                    default: base(lower)
                    }
                }
                if props.changesWhenLowercased {
                    for lower in props.lowercaseMapping.unicodeScalars { expand(lower) }
                } else {
                    expand(s)
                }
            }
            self.primary = primary
            self.secondary = secondary
        }
    }

    let parts: [Part]
    public let original: String

    public init(_ text: String) {
        original = text
        if text.utf8.allSatisfy({ $0 < 0x80 }) {
            // Schneller Weg: ASCII-Bytes direkt zerlegen
            let bytes = Array(text.utf8)
            var parts: [Part] = []
            var start = 0
            while start < bytes.count {
                let digits = bytes[start] >= 0x30 && bytes[start] <= 0x39
                var end = start + 1
                while end < bytes.count && (bytes[end] >= 0x30 && bytes[end] <= 0x39) == digits { end += 1 }
                parts.append(Part(ascii: bytes[start..<end], isDigits: digits))
                start = end
            }
            self.parts = parts
            return
        }
        let scalars = Array(text.unicodeScalars)
        var parts: [Part] = []
        var start = 0
        while start < scalars.count {
            let digits = KotlinChars.isDigit(scalars[start])
            var end = start + 1
            while end < scalars.count && KotlinChars.isDigit(scalars[end]) == digits { end += 1 }
            parts.append(Part(unicode: scalars[start..<end], isDigits: digits))
            start = end
        }
        self.parts = parts
    }

    public static func < (lhs: NaturalKey, rhs: NaturalKey) -> Bool { NaturalOrder.compare(lhs, rhs) < 0 }

    public static func == (lhs: NaturalKey, rhs: NaturalKey) -> Bool { lhs.original == rhs.original }

    public func hash(into hasher: inout Hasher) { hasher.combine(original) }
}

/// Natürlicher Vergleich mit Schlüssel-Zwischenspeicher (wie ein Kotlin-`Comparator<String>`).
/// Nicht threadsicher: je Sortiervorgang eine eigene Instanz verwenden.
public final class NaturalComparator {
    private var cache: [String: NaturalKey] = [:]

    public init() {}

    public func key(_ text: String) -> NaturalKey {
        if let k = cache[text] { return k }
        let k = NaturalKey(text)
        cache[text] = k
        return k
    }

    public func compare(_ a: String, _ b: String) -> Int {
        if a == b && a.utf16.elementsEqual(b.utf16) { return 0 }
        return NaturalOrder.compare(key(a), key(b))
    }

    /// Als `Ordering` für Texte.
    public var ordering: Ordering<String> { Ordering { [self] a, b in compare(a, b) } }

    /// Sortiert Texte natürlich (stabil).
    public func sorted<S: Sequence>(_ items: S) -> [String] where S.Element == String { ordering.sorted(items) }
}
