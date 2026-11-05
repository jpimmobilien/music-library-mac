import Foundation

// Kleine Hilfsmittel, die das Verhalten der Kotlin-/JVM-Standardbibliothek nachbilden, damit die
// portierte Logik auf macOS und Linux exakt gleich rechnet (ohne Locale- oder ICU-Abhängigkeiten).

// MARK: - Vergleichsfunktionen

/// Vergleich wie `java.util.Comparator`: negativ, 0 oder positiv.
///
/// Absichtlich nicht „Comparator“ genannt (Foundation kennt bereits einen gleichnamigen Typ).
public struct Ordering<T> {
    public let compare: (T, T) -> Int

    public init(_ compare: @escaping (T, T) -> Int) {
        self.compare = compare
    }

    /// Aufsteigend nach einem vergleichbaren Schlüssel.
    public static func by<K: Comparable>(_ key: @escaping (T) -> K) -> Ordering<T> {
        Ordering { a, b in
            let ka = key(a), kb = key(b)
            return ka < kb ? -1 : (kb < ka ? 1 : 0)
        }
    }

    /// Umgekehrte Reihenfolge (wie `Comparator.reversed()`).
    public var reversed: Ordering<T> {
        let c = compare
        return Ordering { a, b in c(b, a) }
    }

    /// Bei Gleichstand `next` verwenden (wie `Comparator.then…`).
    public func then(_ next: Ordering<T>) -> Ordering<T> {
        let c = compare
        return Ordering { a, b in
            let r = c(a, b)
            return r != 0 ? r : next.compare(a, b)
        }
    }

    public func then(_ next: @escaping (T, T) -> Int) -> Ordering<T> { then(Ordering(next)) }

    public func then<K: Comparable>(by key: @escaping (T) -> K) -> Ordering<T> { then(Ordering.by(key)) }

    /// Stabil sortiert (wie Kotlin `sortedWith`): Gleichrangige behalten ihre Reihenfolge.
    /// Sortiert werden Indizes – große Elemente (z. B. `Track`) werden dabei nicht bewegt.
    public func sorted<S: Sequence>(_ items: S) -> [T] where S.Element == T {
        let array = Array(items)
        let c = compare
        return stableSortedIndices(array.count) { c(array[$0], array[$1]) }.map { array[$0] }
    }
}

/// Indizes 0..<count stabil sortiert nach `compare` (negativ/0/positiv).
func stableSortedIndices(_ count: Int, _ compare: (Int, Int) -> Int) -> [Int] {
    var indices = Array(0..<count)
    indices.sort { i, j in
        let r = compare(i, j)
        return r != 0 ? r < 0 : i < j
    }
    return indices
}

extension Comparable {
    /// -1/0/1 wie `compareTo`.
    @inline(__always)
    func compareTo(_ other: Self) -> Int { self < other ? -1 : (other < self ? 1 : 0) }
}

// MARK: - Zeichenklassen wie in Kotlin/Java

enum KotlinChars {
    /// `Char.isWhitespace()` in Kotlin (= `Character.isWhitespace || Character.isSpaceChar`).
    static func isWhitespace(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x09...0x0D, 0x1C...0x1F: return true
        default: break
        }
        switch s.properties.generalCategory {
        case .spaceSeparator, .lineSeparator, .paragraphSeparator: return true
        default: return false
        }
    }

    /// `\s` in Java-Regex ohne Unicode-Flag: nur [ \t\n\x0B\f\r].
    static func isRegexSpace(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D: return true
        default: return false
        }
    }

    /// `Char.isDigit()` (Unicode-Kategorie Nd, nur Basisebene wie ein Java-`char`).
    static func isDigit(_ s: Unicode.Scalar) -> Bool {
        s.value <= 0xFFFF && s.properties.generalCategory == .decimalNumber
    }

    /// Wortzeichen für `\b` in Java-Regex: Buchstabe, Ziffer oder „_“ (Kombinationszeichen hängen am Wort).
    static func isWordChar(_ s: Unicode.Scalar) -> Bool {
        if s == "_" { return true }
        switch s.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .nonspacingMark:
            return true
        default:
            return false
        }
    }
}

extension String {
    /// Kotlin `trim()`: entfernt Leerraum (Kotlin-Definition) an beiden Enden.
    func kotlinTrimmed() -> String {
        trimmingScalars(KotlinChars.isWhitespace)
    }

    /// Kotlin `isNullOrBlank()` für einen vorhandenen Text.
    var isKotlinBlank: Bool { unicodeScalars.allSatisfy(KotlinChars.isWhitespace) }

    /// Entfernt Zeichen, auf die `predicate` zutrifft, an beiden Enden.
    func trimmingScalars(_ predicate: (Unicode.Scalar) -> Bool) -> String {
        let scalars = unicodeScalars
        var start = scalars.startIndex
        var end = scalars.endIndex
        while start < end, predicate(scalars[start]) { start = scalars.index(after: start) }
        while end > start {
            let before = scalars.index(before: end)
            if predicate(scalars[before]) { end = before } else { break }
        }
        return String(scalars[start..<end])
    }

    /// Entfernt Zeichen, auf die `predicate` zutrifft, am Ende (Kotlin `trimEnd(…)`).
    func trimmingTrailingScalars(_ predicate: (Unicode.Scalar) -> Bool) -> String {
        let scalars = unicodeScalars
        var end = scalars.endIndex
        while end > scalars.startIndex {
            let before = scalars.index(before: end)
            if predicate(scalars[before]) { end = before } else { break }
        }
        return String(scalars[scalars.startIndex..<end])
    }

    /// Ersetzt Folgen von Java-`\s` (ASCII-Leerraum) durch ein Leerzeichen (wie `replace(Regex("\\s+"), " ")`).
    func collapsingRegexWhitespace() -> String {
        var out = String.UnicodeScalarView()
        var inSpace = false
        for s in unicodeScalars {
            if KotlinChars.isRegexSpace(s) {
                if !inSpace { out.append(" ") }
                inSpace = true
            } else {
                out.append(s)
                inSpace = false
            }
        }
        return String(out)
    }

    /// `String.hashCode()` der JVM (UTF-16, 32-Bit-Überlauf).
    var javaHashCode: Int32 {
        var h: Int32 = 0
        for unit in utf16 { h = h &* 31 &+ Int32(unit) }
        return h
    }

    /// `String.compareTo` der JVM: lexikografisch nach UTF-16-Code-Units.
    func javaCompare(_ other: String) -> Int {
        var a = utf16.makeIterator()
        var b = other.utf16.makeIterator()
        while true {
            switch (a.next(), b.next()) {
            case let (x?, y?):
                if x != y { return Int(x) - Int(y) }
            case (nil, nil): return 0
            case (nil, _): return -1
            case (_, nil): return 1
            }
        }
    }
}

// MARK: - Runden wie auf der JVM

enum JvmMath {
    /// `Math.round(double)` / Kotlin `roundToInt()`: halbe Werte zur positiven Seite.
    static func roundToInt(_ x: Double) -> Int {
        guard x.isFinite else { return x.isNaN ? 0 : (x > 0 ? Int.max : Int.min) }
        return Int((x + 0.5).rounded(.down))
    }

    /// `Math.round(float)`.
    static func roundToInt(_ x: Float) -> Int {
        guard x.isFinite else { return x.isNaN ? 0 : (x > 0 ? Int.max : Int.min) }
        return Int((x + 0.5).rounded(.down))
    }

    /// Kotlin `Float.toInt()` / `Double.toInt()`: Richtung null, NaN → 0, Sättigung statt Absturz.
    static func toInt(_ x: Float) -> Int {
        if x.isNaN { return 0 }
        if x >= Float(Int32.max) { return Int(Int32.max) }
        if x <= Float(Int32.min) { return Int(Int32.min) }
        return Int(x.rounded(.towardZero))
    }

    static func toInt(_ x: Double) -> Int {
        if x.isNaN { return 0 }
        if x >= Double(Int32.max) { return Int(Int32.max) }
        if x <= Double(Int32.min) { return Int(Int32.min) }
        return Int(x.rounded(.towardZero))
    }
}

// MARK: - Gruppieren mit fester Reihenfolge (wie Kotlin `groupBy` / `LinkedHashMap`)

struct OrderedGroups<Key: Hashable, Value> {
    private(set) var keys: [Key] = []
    private var storage: [Key: [Value]] = [:]

    init() {}

    init<S: Sequence>(_ items: S, by key: (Value) -> Key) where S.Element == Value {
        for item in items { append(item, to: key(item)) }
    }

    mutating func append(_ value: Value, to key: Key) {
        if storage[key] == nil {
            keys.append(key)
            storage[key] = [value]
        } else {
            storage[key]!.append(value)
        }
    }

    subscript(key: Key) -> [Value]? { storage[key] }

    var groups: [(key: Key, values: [Value])] { keys.map { ($0, storage[$0]!) } }
    var count: Int { keys.count }
}

/// Zählt Werte in Einfügereihenfolge; liefert den häufigsten (bei Gleichstand den zuerst gesehenen).
struct OrderedCounter<Key: Hashable> {
    private(set) var keys: [Key] = []
    private var counts: [Key: Int] = [:]

    mutating func add(_ key: Key) {
        if let c = counts[key] {
            counts[key] = c + 1
        } else {
            keys.append(key)
            counts[key] = 1
        }
    }

    var isEmpty: Bool { keys.isEmpty }

    /// Wie Kotlin `maxByOrNull { it.value }?.key`.
    var mostCommon: Key? {
        var best: Key?
        var bestCount = Int.min
        for k in keys {
            let c = counts[k]!
            if best == nil || c > bestCount {
                best = k
                bestCount = c
            }
        }
        return best
    }
}

/// Menge mit Einfügereihenfolge (wie `LinkedHashSet`).
struct OrderedSet<Element: Hashable> {
    private(set) var elements: [Element] = []
    private var seen: Set<Element> = []

    init() {}

    init<S: Sequence>(_ items: S) where S.Element == Element {
        for item in items { insert(item) }
    }

    @discardableResult
    mutating func insert(_ e: Element) -> Bool {
        guard seen.insert(e).inserted else { return false }
        elements.append(e)
        return true
    }

    func contains(_ e: Element) -> Bool { seen.contains(e) }
    var count: Int { elements.count }
}

extension Sequence where Element: Hashable {
    /// Kotlin `distinct()`: Duplikate entfernen, erste Fundstelle behalten.
    func distinctInOrder() -> [Element] { OrderedSet(self).elements }
}

// MARK: - Zufall

/// Reproduzierbarer Zufallsgenerator (SplitMix64) – für Tests und für gespeicherte Zufallsreihenfolgen.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
