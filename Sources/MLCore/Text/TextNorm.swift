import Foundation

/// Normalisierung von Texten für Gruppierung, Suche und Vergleiche (Portierung von `core/TextNorm.kt`).
///
/// - `key` ist ein Vergleichsschlüssel: Groß-/Kleinschreibung, Akzente (é → e, ü → u), „ß“ → „ss“
///   und mehrfache Leerzeichen spielen keine Rolle. Er wird NUR für Vergleiche verwendet – angezeigt
///   wird immer der Originaltext aus den Metadaten.
/// - `cleanTag` entfernt Steuerzeichen und erkennt Platzhalter, die manche Programme statt echter Werte
///   eintragen (z. B. „<unknown>“). Fehlende Werte bleiben fehlend (`nil`) – es wird nichts erfunden.
public enum TextNorm {

    /// Platzhalter, die manche Programme anstelle eines fehlenden Werts eintragen.
    static let placeholders: Set<String> = ["<unknown>", "unknown", "<unbekannt>"]

    public static func key(_ text: String?) -> String {
        guard let text, !text.isEmpty else { return "" }
        if let ascii = asciiKey(text) { return ascii }
        var out: [Unicode.Scalar] = []
        out.reserveCapacity(text.utf8.count)
        var pendingSpace = false
        func emit(_ l: Unicode.Scalar) {
            // Leerraum wie Java-`\s` zusammenfassen
            if KotlinChars.isRegexSpace(l) {
                pendingSpace = true
                return
            }
            if pendingSpace {
                out.append(" ")
                pendingSpace = false
            }
            // Ersetzungen wie in Kotlin (nach dem Kleinschreiben)
            switch l {
            case "ß": out.append("s"); out.append("s")
            case "æ": out.append("a"); out.append("e")
            case "ø": out.append("o")
            case "œ": out.append("o"); out.append("e")
            default: out.append(l)
            }
        }
        for s in decomposedScalars(text) {
            let v = s.value
            if v < 0x80 {
                emit(v >= 0x41 && v <= 0x5A ? Unicode.Scalar(UInt8(v + 0x20)) : s)
                continue
            }
            let props = s.properties
            // Kombinierende Zeichen (Kategorie Mn) entfernen: é → e
            if props.generalCategory == .nonspacingMark { continue }
            if props.changesWhenLowercased {
                for l in props.lowercaseMapping.unicodeScalars { emit(l) }
            } else {
                emit(s)
            }
        }
        // Kotlin `trim()`
        var lo = 0
        var hi = out.count
        while lo < hi && KotlinChars.isWhitespace(out[lo]) { lo += 1 }
        while hi > lo && KotlinChars.isWhitespace(out[hi - 1]) { hi -= 1 }
        return string(from: out[lo..<hi])
    }

    /// Text aus Unicode-Skalaren (über UTF-8 – deutlich schneller als einzelnes Anhängen).
    static func string<C: Collection>(from scalars: C) -> String where C.Element == Unicode.Scalar {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(scalars.count + 8)
        for s in scalars { UTF8.encode(s) { bytes.append($0) } }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Schneller Weg für reinen ASCII-Text (der weitaus häufigste Fall).
    private static func asciiKey(_ text: String) -> String? {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.utf8.count)
        var pendingSpace = false
        for b in text.utf8 {
            if b >= 0x80 { return nil }
            switch b {
            case 0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D:
                pendingSpace = true
                continue
            default:
                break
            }
            if pendingSpace {
                bytes.append(0x20)
                pendingSpace = false
            }
            bytes.append(b >= 0x41 && b <= 0x5A ? b + 0x20 : b)
        }
        // Kotlin `trim()`: zusätzlich Steuerzeichen 0x1C–0x1F an den Rändern
        var start = 0
        var end = bytes.count
        while start < end && isAsciiTrim(bytes[start]) { start += 1 }
        while end > start && isAsciiTrim(bytes[end - 1]) { end -= 1 }
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    private static func isAsciiTrim(_ b: UInt8) -> Bool { b == 0x20 || (b >= 0x09 && b <= 0x0D) || (b >= 0x1C && b <= 0x1F) }

    /// Kanonische Zerlegung (NFD). Reiner ASCII-Text ist bereits zerlegt; lateinische Buchstaben
    /// (bis U+024F, z. B. ä, é, ß, ł) werden über eine einmal mit Foundation berechnete Tabelle zerlegt;
    /// alles andere (andere Schriften, bereits zerlegte Akzente, Hangul …) direkt mit Foundation.
    static func decomposedScalars(_ text: String) -> [Unicode.Scalar] {
        decomposedScalars(text.unicodeScalars)
    }

    static func decomposedScalars<C: Collection>(_ scalars: C) -> [Unicode.Scalar] where C.Element == Unicode.Scalar {
        var out: [Unicode.Scalar] = []
        out.reserveCapacity(scalars.count + 4)
        for s in scalars {
            let v = s.value
            if v < 0xC0 {
                out.append(s)
            } else if v < latinTableEnd {
                out.append(contentsOf: latinDecomposition[Int(v - 0xC0)])
            } else {
                // andere Schriften oder bereits zerlegte Akzente (Reihenfolge!) → Foundation
                return Array(string(from: scalars).decomposedStringWithCanonicalMapping.unicodeScalars)
            }
        }
        return out
    }

    private static let latinTableEnd: UInt32 = 0x250

    /// NFD-Zerlegung von U+00C0 … U+024F (einmalig über Foundation berechnet).
    private static let latinDecomposition: [[Unicode.Scalar]] = (UInt32(0xC0)..<latinTableEnd).map { v in
        guard let scalar = Unicode.Scalar(v) else { return [] }
        return Array(String(Character(scalar)).decomposedStringWithCanonicalMapping.unicodeScalars)
    }

    /// Suchbegriffe: alle müssen vorkommen (UND-Suche, Reihenfolge egal).
    public static func searchTerms(_ query: String) -> [String] {
        key(query).split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }

    /// Trifft jeder Begriff auf den (bereits normalisierten) Text zu?
    public static func matchesAll(_ terms: [String], _ haystack: String) -> Bool {
        terms.allSatisfy { haystack.range(of: $0, options: .literal) != nil }
    }

    /// Bereinigt einen Metadatenwert: Steuerzeichen raus, Ränder trimmen. Leere Werte und bekannte
    /// Platzhalter ergeben `nil` (= „nicht vorhanden“).
    public static func cleanTag(_ value: String?) -> String? {
        guard let value else { return nil }
        var scalars = String.UnicodeScalarView()
        for s in value.unicodeScalars {
            switch s.value {
            case 0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F, 0x7F: continue
            default: scalars.append(s)
            }
        }
        let cleaned = String(scalars).kotlinTrimmed()
        if cleaned.isEmpty { return nil }
        if placeholders.contains(cleaned.lowercased()) { return nil }
        return cleaned
    }

    /// Dateiname ohne Endung (nur zur ANZEIGE, falls ein Titel-Tag fehlt).
    public static func fileNameWithoutExtension(_ fileName: String) -> String {
        guard let dot = fileName.lastIndex(of: "."), dot != fileName.startIndex else { return fileName }
        return String(fileName[..<dot])
    }

    /// Endung in Großbuchstaben, z. B. „M4A“ (leer, wenn keine vorhanden).
    public static func fileExtension(_ fileName: String) -> String {
        guard let dot = fileName.lastIndex(of: ".") else { return "" }
        let after = fileName.index(after: dot)
        guard after < fileName.endIndex else { return "" }
        return String(fileName[after...]).uppercased()
    }
}
