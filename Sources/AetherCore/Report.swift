import Foundation

// =============================================================================================
// Systembericht: dieselben Zeilen, die die Hardware-Seite anzeigt, als Markdown-Datei.
// Der Bericht wird nur lokal gespeichert (Sichern-Dialog). Die Seriennummer steht nur darin, wenn der Nutzer
// es beim Export ausdrücklich ankreuzt.
// =============================================================================================

public struct ReportRow: Sendable, Equatable, Identifiable {
    public var id: String { label }
    public var label: String
    public var value: String
    public var source: DataSource?
    /// Persönliche Angabe (Seriennummer): nur auf ausdrücklichen Wunsch anzeigen oder exportieren.
    public var isSensitive: Bool

    public init(_ label: String, _ value: String, source: DataSource? = nil, isSensitive: Bool = false) {
        self.label = label
        self.value = value
        self.source = source
        self.isSensitive = isSensitive
    }
}

public struct ReportSection: Sendable, Equatable, Identifiable {
    public var id: String { title }
    public var title: String
    public var symbol: String
    public var rows: [ReportRow]

    public init(title: String, symbol: String, rows: [ReportRow]) {
        self.title = title
        self.symbol = symbol
        self.rows = rows
    }
}

public enum ReportFormatter {
    /// Markdown mit einer Tabelle je Abschnitt (Angabe, Wert, Art der Quelle). Leere Abschnitte entfallen;
    /// sensible Zeilen nur mit `includeSensitive`.
    public static func markdown(title: String, subtitle: String, columns: (label: String, value: String, source: String),
                                sections: [ReportSection], includeSensitive: Bool, footer: String? = nil,
                                describe: (DataSource) -> String) -> String {
        var lines: [String] = ["# \(inline(title))", "", inline(subtitle), ""]
        for section in sections {
            let rows = section.rows.filter { includeSensitive || !$0.isSensitive }
            guard !rows.isEmpty else { continue }
            lines.append("## \(inline(section.title))")
            lines.append("")
            lines.append("| \(cell(columns.label)) | \(cell(columns.value)) | \(cell(columns.source)) |")
            lines.append("|---|---|---|")
            for row in rows {
                lines.append("| \(cell(row.label)) | \(cell(row.value)) | \(cell(row.source.map(describe) ?? "–")) |")
            }
            lines.append("")
        }
        if let footer {
            lines.append("---")
            lines.append("")
            lines.append(inline(footer))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Tabellenzelle: senkrechte Striche maskieren, Zeilenumbrüche entfernen.
    static func cell(_ text: String) -> String {
        inline(text).replacingOccurrences(of: "|", with: "\\|")
    }

    static func inline(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Dateiname ohne problematische Zeichen.
    public static func fileName(prefix: String, date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        var calendar = calendar
        calendar.timeZone = TimeZone.current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let stamp = String(format: "%04d-%02d-%02d_%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
        let safe = prefix.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" ? String($0) : "-" }.joined()
        return "\(safe)_\(stamp).md"
    }
}
