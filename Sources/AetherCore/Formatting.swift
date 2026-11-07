import Foundation

/// Zahlen und Einheiten wie im System: Speicherplatz dezimal (1 GB = 10⁹ B, wie der Finder), Arbeitsspeicher binär
/// mit den Einheiten der Aktivitätsanzeige (1 GB = 2³⁰ B), Raten dezimal (MB/s). Drei signifikante Stellen,
/// überflüssige Nullen entfallen. Dezimaltrennzeichen und Leerzeichen vor % je Sprache.
public struct ValueFormatter: Sendable {
    public let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    private var decimalSeparator: String { locale.decimalSeparator ?? "." }
    private var isGerman: Bool { locale.identifier.lowercased().hasPrefix("de") }
    /// Geschütztes Leerzeichen zwischen Zahl und Einheit.
    public static let unitSpace = "\u{00A0}"

    /// Zahl mit fester Nachkommastellenzahl (ohne Tausendertrennung).
    public func number(_ value: Double, fractionDigits: Int) -> String {
        let digits = max(0, min(6, fractionDigits))
        var text = String(format: "%.\(digits)f", value)
        if text.hasPrefix("-"), Double(text) == 0 { text.removeFirst() } // „-0“ vermeiden
        return decimalSeparator == "." ? text : text.replacingOccurrences(of: ".", with: decimalSeparator)
    }

    /// Drei signifikante Stellen, abschließende Nullen entfernt: 2,4 · 12,3 · 412 · 0,05.
    public func significant(_ value: Double) -> String {
        let magnitude = abs(value)
        let digits: Int
        if magnitude >= 100 || magnitude == 0 { digits = 0 }
        else if magnitude >= 10 { digits = 1 }
        else if magnitude >= 1 { digits = 2 }
        else { digits = 2 }
        var text = number(value, fractionDigits: digits)
        if digits > 0 {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(decimalSeparator) { text.removeLast(decimalSeparator.count) }
        }
        return text
    }

    /// Ganze Zahl mit Tausendertrennung (1 850 U/min bzw. 1,850 rpm).
    public func integer(_ value: Int) -> String {
        let negative = value < 0
        let digits = String(abs(value))
        let separator = isGerman ? "." : ","
        var groups: [String] = []
        var end = digits.endIndex
        while end > digits.startIndex {
            let start = digits.index(end, offsetBy: -3, limitedBy: digits.startIndex) ?? digits.startIndex
            groups.insert(String(digits[start..<end]), at: 0)
            end = start
        }
        return (negative ? "-" : "") + groups.joined(separator: separator)
    }

    /// Prozent aus einem Anteil 0…1: „12 %“ (Deutsch) bzw. „12%“ (Englisch).
    public func percent(_ fraction: Double, fractionDigits: Int = 0) -> String {
        let value = number(fraction * 100, fractionDigits: fractionDigits)
        return isGerman ? value + ValueFormatter.unitSpace + "%" : value + "%"
    }

    public enum ByteStyle: Sendable {
        /// Speicherplatz, Dateien, Datenmengen: 1 KB = 1 000 B.
        case decimal
        /// Arbeitsspeicher: 1 KB = 1 024 B (Einheitenbezeichnung wie in der Aktivitätsanzeige).
        case memory
    }

    /// Bytes mit Einheit, getrennt zurückgegeben (Zahl groß, Einheit klein darstellbar).
    public func byteParts(_ bytes: Double, style: ByteStyle = .decimal) -> (value: String, unit: String) {
        let base: Double = style == .decimal ? 1000 : 1024
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = abs(bytes)
        var index = 0
        while value >= base * 0.9995 && index < units.count - 1 {
            value /= base
            index += 1
        }
        let signed = bytes < 0 ? -value : value
        let text = index == 0 ? number(signed.rounded(), fractionDigits: 0) : significant(signed)
        return (text, units[index])
    }

    public func bytes(_ bytes: Double, style: ByteStyle = .decimal) -> String {
        let parts = byteParts(bytes, style: style)
        return parts.value + ValueFormatter.unitSpace + parts.unit
    }

    public func bytes(_ bytes: UInt64, style: ByteStyle = .decimal) -> String {
        self.bytes(Double(bytes), style: style)
    }

    public func bytes(_ bytes: Int64, style: ByteStyle = .decimal) -> String {
        self.bytes(Double(bytes), style: style)
    }

    /// Datenrate: „2,4 MB/s“.
    public func rateParts(_ bytesPerSecond: Double) -> (value: String, unit: String) {
        let parts = byteParts(max(0, bytesPerSecond), style: .decimal)
        return (parts.value, parts.unit + "/s")
    }

    public func rate(_ bytesPerSecond: Double) -> String {
        let parts = rateParts(bytesPerSecond)
        return parts.value + ValueFormatter.unitSpace + parts.unit
    }

    /// Temperatur in °C mit einer Nachkommastelle unter 100 °C.
    public func celsius(_ value: Double) -> String {
        number(value, fractionDigits: abs(value) < 100 ? 1 : 0) + ValueFormatter.unitSpace + "°C"
    }

    /// Dauer kompakt: „3 h 12 min“, „45 min“, „2 T 4 h“ (Deutsch) bzw. „2 d 4 h“.
    public func duration(seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let s = ValueFormatter.unitSpace
        let dayUnit = isGerman ? "T" : "d"
        if days > 0 { return "\(days)\(s)\(dayUnit) \(hours)\(s)h" }
        if hours > 0 { return "\(hours)\(s)h \(minutes)\(s)min" }
        if minutes > 0 { return "\(minutes)\(s)min" }
        return "\(total)\(s)s"
    }
}
