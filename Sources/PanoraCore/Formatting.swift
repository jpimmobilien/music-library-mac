import Foundation

/// Deutsche Formatierung ohne Abhängigkeit vom Gebietsschema des Rechners (gleiche Ausgabe in der CI).
public enum Formatting {
    /// Dezimal wie im Finder: 1 GB = 1.000.000.000 Bytes. „21,3 GB“, „840 MB“.
    public static func bytes(_ value: Int64) -> String {
        let v = Double(value)
        if v >= 1_000_000_000_000 { return decimal(v / 1_000_000_000_000, digits: 2) + " TB" }
        if v >= 1_000_000_000 { return decimal(v / 1_000_000_000, digits: v >= 100_000_000_000 ? 0 : 1) + " GB" }
        if v >= 1_000_000 { return decimal(v / 1_000_000, digits: 0) + " MB" }
        if v >= 1_000 { return decimal(v / 1_000, digits: 0) + " KB" }
        return "\(value) Bytes"
    }

    /// Zahl mit Komma als Dezimaltrennzeichen und Punkt als Tausendertrennzeichen.
    public static func decimal(_ value: Double, digits: Int) -> String {
        let s = String(format: "%.\(max(0, digits))f", value)
        var parts = s.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let intPart = parts.removeFirst()
        let negative = intPart.hasPrefix("-")
        let digitsOnly = negative ? String(intPart.dropFirst()) : intPart
        var grouped = ""
        for (i, ch) in digitsOnly.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { grouped.append(".") }
            grouped.append(ch)
        }
        var result = (negative ? "-" : "") + String(grouped.reversed())
        if let frac = parts.first, !frac.isEmpty { result += "," + frac }
        return result
    }

    public static func integer(_ value: Int) -> String { decimal(Double(value), digits: 0) }

    /// „8B“, „0,6B“, „235B“
    public static func params(_ billions: Double) -> String {
        if billions >= 10 || billions == billions.rounded() { return "\(Int(billions.rounded()))B" }
        return decimal(billions, digits: 1) + "B"
    }

    /// „4 Bit“, „6,5 Bit“
    public static func bits(_ bits: Double) -> String {
        bits == bits.rounded() ? "\(Int(bits)) Bit" : decimal(bits, digits: 1) + " Bit"
    }

    /// „32K“, „256K“, „1M“
    public static func context(_ tokens: Int) -> String {
        if tokens >= 1_000_000 { return decimal(Double(tokens) / 1_048_576, digits: tokens % 1_048_576 == 0 ? 0 : 1) + "M" }
        if tokens >= 1024 { return "\(Int((Double(tokens) / 1024).rounded()))K" }
        return "\(tokens)"
    }

    /// „12 s“, „2 min“, „1 h 5 min“
    public static func duration(_ seconds: Double) -> String {
        if seconds < 1 { return "unter 1 s" }
        if seconds < 60 { return "\(Int(seconds.rounded())) s" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }

    /// „42 %“
    public static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded())) %" }

    /// „1 Modell“ / „3 Modelle“
    public static func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(integer(n)) \(n == 1 ? singular : plural)"
    }

    private static let monthNames = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August",
                                     "September", "Oktober", "November", "Dezember"]

    /// „November 2026“ (UTC-unabhängig über den übergebenen Kalender).
    public static func monthYear(_ date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        let m = max(1, min(12, c.month ?? 1))
        return "\(monthNames[m - 1]) \(c.year ?? 2026)"
    }

    /// „16.11.2026, 20:39“
    public static func dateTime(_ date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%02d.%02d.%04d, %02d:%02d", c.day ?? 1, c.month ?? 1, c.year ?? 2026, c.hour ?? 0, c.minute ?? 0)
    }
}
