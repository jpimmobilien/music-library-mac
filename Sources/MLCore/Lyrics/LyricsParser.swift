import Foundation

/// Eine Zeile synchronisierter Liedtexte.
public struct LyricLine: Hashable, Codable, Sendable {
    /// Zeitpunkt in ms (Versatz `[offset:]` bereits eingerechnet).
    public var timeMs: Int64
    /// Text ohne Zeitmarken (leer = instrumentale Pause).
    public var text: String

    public init(timeMs: Int64, text: String) {
        self.timeMs = timeMs
        self.text = text
    }

    public var isGap: Bool { text.isEmpty }
}

/// Kennzeichnung im LRC-Kopf, z. B. `[ar:Interpret]`.
public struct LyricsTag: Hashable, Codable, Sendable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// Ergebnis des Einlesens eines Liedtexts.
public struct Lyrics: Hashable, Sendable {
    /// Synchronisierte Zeilen, nach Zeit sortiert (bei gleicher Zeit in Dateireihenfolge). Leer bei
    /// unsynchronisiertem Text.
    public var lines: [LyricLine]
    /// Kopf-Kennzeichnungen (`ar`, `ti`, `al`, `by`, `length` …) in Dateireihenfolge, ohne `offset`.
    /// Werden nicht angezeigt, aber beim Speichern wieder geschrieben.
    public var tags: [LyricsTag]
    /// Versatz aus `[offset:±ms]` (bereits in `lines` eingerechnet).
    public var offsetMs: Int64
    /// Unsynchronisierter Text – unverändert wie gelesen (`nil` bei synchronisierten Texten).
    public var plainText: String?

    public init(lines: [LyricLine], tags: [LyricsTag] = [], offsetMs: Int64 = 0, plainText: String? = nil) {
        self.lines = lines
        self.tags = tags
        self.offsetMs = offsetMs
        self.plainText = plainText
    }

    public var isSynced: Bool { plainText == nil }

    /// Index der Zeile, die zur Wiedergabeposition `timeMs` gehört (letzte Zeile mit Zeit ≤ `timeMs`);
    /// `nil` vor der ersten Zeile oder ohne synchronisierte Zeilen. Binäre Suche.
    public func lineIndex(at timeMs: Int64) -> Int? {
        LyricsParser.lineIndex(in: lines, at: timeMs)
    }

    /// Wert einer Kopf-Kennzeichnung (ohne Groß-/Kleinschreibung des Schlüssels).
    public func tag(_ key: String) -> String? {
        tags.first { $0.key.lowercased() == key.lowercased() }?.value
    }

    /// Text zum Speichern: synchronisiert als LRC, sonst der Originaltext.
    public func serialized() -> String {
        if let plainText { return plainText }
        return LyricsParser.serialize(lines, tags: tags)
    }
}

/// LRC-Liedtexte lesen und schreiben (neu gegenüber Android).
///
/// Unterstützt:
/// - Zeitmarken `[mm:ss.xx]`, `[mm:ss]`, `[mm:ss:xx]`, `[mm:ss.xxx]` (1 Nachkommastelle = Zehntel,
///   2 = Hundertstel, 3 = Millisekunden); Minuten auch dreistellig.
/// - mehrere Zeitmarken je Zeile (`[00:12.00][01:30.50]Refrain` → zwei Zeilen),
/// - `[offset:±ms]` (positiv = Text erscheint früher; wird in die Zeiten eingerechnet, nie unter 0),
/// - Kopf-Kennzeichnungen (`[ar:]`, `[ti:]`, `[al:]`, `[by:]`, `[length:]`, `[au:]`, `[re:]`, `[ve:]`, `[#:]`
///   …) – nicht angezeigt, aber gemerkt,
/// - erweiterte Wortmarken `<mm:ss.xx>` (A2/„Enhanced LRC“) – werden aus dem Text entfernt,
/// - leere Zeilen mit Zeitmarke = instrumentale Pause (bleiben erhalten),
/// - BOM, CRLF/CR-Zeilenenden.
///
/// Ein Text gilt als synchronisiert, wenn mindestens eine Zeile eine gültige Zeitmarke hat und
/// höchstens gleich viele Textzeilen OHNE Zeitmarke vorkommen (so bleibt z. B. ein normaler Liedtext,
/// der zufällig „[00:30]“ enthält, unsynchronisiert). Unsynchronisierter Text wird unverändert
/// durchgereicht.
public enum LyricsParser {

    public static func parse(_ text: String) -> Lyrics {
        var tags: [LyricsTag] = []
        var offset: Int64 = 0
        var timed: [(time: Int64, text: String, order: Int)] = []
        var timedLineCount = 0
        var untimedTextLines = 0

        var body = text
        if body.hasPrefix("\u{FEFF}") { body.removeFirst() }
        let rawLines = body.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)

        for raw in rawLines {
            let line = String(raw)
            let parsed = parseLine(line)
            switch parsed {
            case .timed(let times, let content):
                timedLineCount += 1
                for t in times {
                    timed.append((t, content, timed.count))
                }
            case .tag(let key, let value):
                if key.lowercased() == "offset" {
                    if let v = parseOffset(value) { offset = v }
                } else {
                    tags.append(LyricsTag(key: key, value: value))
                }
            case .text(let content):
                if !content.isEmpty { untimedTextLines += 1 }
            }
        }

        guard timedLineCount > 0, untimedTextLines <= timedLineCount else {
            return Lyrics(lines: [], tags: [], offsetMs: 0, plainText: text)
        }
        let lines = timed
            .map { (time: max($0.time - offset, 0), text: $0.text, order: $0.order) }
            .sorted { $0.time != $1.time ? $0.time < $1.time : $0.order < $1.order }
            .map { LyricLine(timeMs: $0.time, text: $0.text) }
        return Lyrics(lines: lines, tags: tags, offsetMs: offset, plainText: nil)
    }

    /// Enthält der Text synchronisierte Zeilen?
    public static func isSynced(_ text: String) -> Bool { parse(text).isSynced }

    /// Index der letzten Zeile mit Zeit ≤ `timeMs` (binäre Suche); `lines` muss nach Zeit sortiert sein.
    public static func lineIndex(in lines: [LyricLine], at timeMs: Int64) -> Int? {
        var lo = 0
        var hi = lines.count - 1
        var result: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].timeMs <= timeMs {
                result = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return result
    }

    /// Schreibt synchronisierte Zeilen als LRC: zuerst die Kopf-Kennzeichnungen, dann je Zeile
    /// `[mm:ss.xx]Text`. Der Versatz ist bereits in den Zeiten enthalten und wird nicht geschrieben.
    public static func serialize(_ lines: [LyricLine], tags: [LyricsTag] = []) -> String {
        var out: [String] = []
        for tag in tags where tag.key.lowercased() != "offset" {
            out.append("[\(tag.key):\(tag.value)]")
        }
        let sorted = lines.enumerated()
            .sorted { $0.element.timeMs != $1.element.timeMs ? $0.element.timeMs < $1.element.timeMs : $0.offset < $1.offset }
            .map(\.element)
        for line in sorted {
            out.append("[\(formatTimestamp(line.timeMs))]\(line.text)")
        }
        return out.joined(separator: "\n")
    }

    /// „mm:ss.xx“ (Hundertstel, gerundet; Minuten mindestens zweistellig).
    public static func formatTimestamp(_ ms: Int64) -> String {
        let cs = (max(ms, 0) + 5) / 10
        let minutes = cs / 6000
        let seconds = (cs / 100) % 60
        let hundredths = cs % 100
        func pad(_ v: Int64) -> String { v < 10 ? "0\(v)" : "\(v)" }
        return "\(pad(minutes)):\(pad(seconds)).\(pad(hundredths))"
    }

    // MARK: - Zeilen

    enum ParsedLine: Equatable {
        case timed([Int64], String)
        case tag(String, String)
        case text(String)
    }

    static func parseLine(_ line: String) -> ParsedLine {
        let scalars = Array(line.unicodeScalars)
        var i = 0
        // führender Leerraum vor der ersten Marke
        while i < scalars.count && (scalars[i] == " " || scalars[i] == "\t") { i += 1 }
        var times: [Int64] = []
        while i < scalars.count && scalars[i] == "[" {
            guard let close = scalars[(i + 1)...].firstIndex(of: "]") else { break }
            let inner = String(String.UnicodeScalarView(scalars[(i + 1)..<close]))
            if let t = parseTime(inner) {
                times.append(t)
                i = close + 1
                continue
            }
            if times.isEmpty, let tag = parseTag(inner) {
                // Kopfzeile: nur gültig, wenn danach nichts mehr folgt
                let rest = String(String.UnicodeScalarView(scalars[(close + 1)...])).trimmingCharacters(in: .whitespaces)
                if rest.isEmpty { return .tag(tag.0, tag.1) }
            }
            break
        }
        let rest = String(String.UnicodeScalarView(scalars[i...]))
        if times.isEmpty {
            return .text(line.trimmingCharacters(in: .whitespaces))
        }
        return .timed(times, cleanText(rest))
    }

    /// Entfernt Wortmarken `<mm:ss.xx>` und Ränder.
    static func cleanText(_ text: String) -> String {
        guard text.contains("<") else { return text.trimmingCharacters(in: .whitespaces) }
        let scalars = Array(text.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        while i < scalars.count {
            if scalars[i] == "<", let close = scalars[(i + 1)...].firstIndex(of: ">"),
               parseTime(String(String.UnicodeScalarView(scalars[(i + 1)..<close]))) != nil {
                i = close + 1
                continue
            }
            out.append(scalars[i])
            i += 1
        }
        // Doppelte Leerzeichen, die durch entfernte Marken entstehen, zusammenfassen.
        var collapsed = String.UnicodeScalarView()
        var lastSpace = false
        for s in out {
            if s == " " {
                if lastSpace { continue }
                lastSpace = true
            } else {
                lastSpace = false
            }
            collapsed.append(s)
        }
        return String(collapsed).trimmingCharacters(in: .whitespaces)
    }

    /// „mm:ss“, „mm:ss.x(x(x))“, „mm:ss:xx“ → ms; sonst `nil`.
    static func parseTime(_ s: String) -> Int64? {
        let scalars = Array(s.unicodeScalars)
        var i = 0
        func digits(max: Int) -> (Int64, Int)? {
            var value: Int64 = 0
            var n = 0
            while i < scalars.count, n < max, let d = asciiDigit(scalars[i]) {
                value = value * 10 + Int64(d)
                n += 1
                i += 1
            }
            return n > 0 ? (value, n) : nil
        }
        guard let (minutes, _) = digits(max: 4) else { return nil }
        guard i < scalars.count, scalars[i] == ":" else { return nil }
        i += 1
        guard let (seconds, secDigits) = digits(max: 2), secDigits == 2 || secDigits == 1 else { return nil }
        var fraction: Int64 = 0
        if i < scalars.count {
            guard scalars[i] == "." || scalars[i] == ":" else { return nil }
            i += 1
            guard let (f, n) = digits(max: 3) else { return nil }
            switch n {
            case 1: fraction = f * 100
            case 2: fraction = f * 10
            default: fraction = f
            }
        }
        guard i == scalars.count, seconds < 60 else { return nil }
        return (minutes * 60 + seconds) * 1000 + fraction
    }

    /// `key:value` mit Schlüssel aus Buchstaben (oder „#“) – sonst `nil`.
    static func parseTag(_ inner: String) -> (String, String)? {
        guard let colon = inner.firstIndex(of: ":") else { return nil }
        let key = String(inner[..<colon])
        guard !key.isEmpty, key.count <= 16,
              key == "#" || key.unicodeScalars.allSatisfy({ ($0.value >= 0x41 && $0.value <= 0x5A) || ($0.value >= 0x61 && $0.value <= 0x7A) })
        else { return nil }
        let value = String(inner[inner.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    static func parseOffset(_ value: String) -> Int64? {
        let v = value.trimmingCharacters(in: .whitespaces)
        if v.hasPrefix("+") { return Int64(v.dropFirst()) }
        return Int64(v)
    }

    private static func asciiDigit(_ s: Unicode.Scalar) -> Int? {
        s.value >= 0x30 && s.value <= 0x39 ? Int(s.value - 0x30) : nil
    }
}
