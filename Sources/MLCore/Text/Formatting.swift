import Foundation

/// Deutsche Anzeigeformate (Portierung von `core/Formatting.kt`).
///
/// Alle Zahlenformate werden ohne `NumberFormatter`/Locale selbst erzeugt, damit macOS und Linux
/// zeichengenau dasselbe liefern (Tausenderpunkt, Dezimalkomma, Rundung „halb auf“ wie Java).
public enum Formatting {

    /// Ganze Zahl mit Tausenderpunkt, z. B. „1.234“.
    public static func integer(_ value: Int) -> String { integer(Int64(value)) }

    public static func integer(_ value: Int64) -> String {
        let negative = value < 0
        let digits = String(value.magnitude)
        var out = ""
        for (i, c) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(".") }
            out.append(c)
        }
        return negative ? "-" + out : out
    }

    /// „3:07“ bzw. „1:02:03“. Negative Werte werden als 0 angezeigt.
    public static func duration(_ ms: Int64) -> String {
        let totalSeconds = max(ms, 0) / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return "\(hours):\(pad2(minutes)):\(pad2(seconds))"
        }
        return "\(minutes):\(pad2(seconds))"
    }

    /// Gesamtdauer kompakt: „42 Min.“ bzw. „1 Std. 12 Min.“.
    public static func longDuration(_ ms: Int64) -> String {
        let totalMinutes = (max(ms, 0) + 30_000) / 60_000
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) Min." }
        if minutes == 0 { return "\(hours) Std." }
        return "\(hours) Std. \(minutes) Min."
    }

    /// Countdown für den Sleep-Timer: „14:59“ bzw. „1:29:59“. Rundet auf volle Sekunden auf.
    public static func countdown(_ remainingMs: Int64) -> String {
        duration(((max(remainingMs, 0) + 999) / 1000) * 1000)
    }

    public static func tracks(_ count: Int) -> String { count == 1 ? "1 Titel" : "\(integer(count)) Titel" }
    public static func albums(_ count: Int) -> String { count == 1 ? "1 Album" : "\(integer(count)) Alben" }
    public static func artists(_ count: Int) -> String { count == 1 ? "1 Interpret" : "\(integer(count)) Interpreten" }
    public static func genres(_ count: Int) -> String { count == 1 ? "1 Genre" : "\(integer(count)) Genres" }
    public static func playlists(_ count: Int) -> String { count == 1 ? "1 Playlist" : "\(integer(count)) Playlists" }
    public static func plays(_ count: Int) -> String { count == 1 ? "1 Wiedergabe" : "\(integer(count)) Wiedergaben" }
    public static func hits(_ count: Int) -> String { count == 1 ? "1 Treffer" : "\(integer(count)) Treffer" }

    /// Bitrate aus Bit/s, z. B. „256 kbit/s“.
    public static func bitrate(bitsPerSecond: Int) -> String {
        "\(integer(JvmMath.roundToInt(Double(bitsPerSecond) / 1000.0))) kbit/s"
    }

    /// Bitrate aus kbit/s (so speichert `Track.bitrate` sie), z. B. „256 kbit/s“.
    public static func bitrate(kbps: Int) -> String { "\(integer(kbps)) kbit/s" }

    /// Abtastrate, z. B. „44,1 kHz“ bzw. „48 kHz“.
    public static func sampleRate(_ hz: Int) -> String {
        let khz = Double(hz) / 1000.0
        let rounded = Double(JvmMath.roundToInt(khz * 10)) / 10.0
        let text: String
        if rounded == rounded.rounded(.towardZero) {
            text = String(Int64(rounded))
        } else {
            text = rounded.description.replacingOccurrences(of: ".", with: ",")
        }
        return "\(text) kHz"
    }

    public static func channels(_ count: Int) -> String {
        switch count {
        case 1: return "Mono (1 Kanal)"
        case 2: return "Stereo (2 Kanäle)"
        default: return "\(count) Kanäle"
        }
    }

    public static func fileSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024.0 * 1024.0)
        if mb >= 1.0 {
            return germanFixed(mb, digits: 1) + " MB"
        }
        return germanFixed(Double(bytes) / 1024.0, digits: 0) + " KB"
    }

    /// Prozentwert ohne Nachkommastellen, z. B. „150 %“.
    public static func percent(_ fraction: Float) -> String { "\(JvmMath.roundToInt(fraction * 100)) %" }

    /// Dezibel mit Vorzeichen, z. B. „+3,5 dB“, „−2 dB“, „0 dB“.
    public static func decibel(_ db: Float) -> String {
        let rounded = Float(JvmMath.roundToInt(db * 2)) / 2
        if rounded == 0 { return "0 dB" }
        let sign = rounded > 0 ? "+" : "−"
        return "\(sign)\(compactNumber(abs(rounded))) dB"
    }

    /// Halbtöne mit Vorzeichen, auf Zehntel gerundet, z. B. „+2 Halbtöne“, „+1,5 Halbtöne“, „−0,3 Halbtöne“,
    /// „−1 Halbton“, „Original“.
    public static func semitones(_ value: Float) -> String {
        let tenths = JvmMath.roundToInt(value * 10)
        if tenths == 0 { return "Original" }
        let sign = tenths > 0 ? "+" : "−"
        let v = tenths.magnitude
        let number = v % 10 == 0 ? "\(v / 10)" : "\(v / 10),\(v % 10)"
        let unit = v == 10 ? "Halbton" : "Halbtöne"
        return "\(sign)\(number) \(unit)"
    }

    /// Halbtöne als Cent mit Vorzeichen (1 Halbton = 100 Cent), z. B. „+150 Cent“, „−30 Cent“, „0 Cent“.
    public static func cents(_ semitones: Float) -> String {
        let cents = JvmMath.roundToInt(semitones * 100)
        if cents == 0 { return "0 Cent" }
        return "\(cents > 0 ? "+" : "−")\(cents.magnitude) Cent"
    }

    /// Datum und Uhrzeit, z. B. „25.10.2026, 14:03“.
    public static func dateTime(_ epochMs: Int64, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let seconds = Double(epochMs) / 1000.0
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: Date(timeIntervalSince1970: seconds))
        let year = c.year ?? 1970
        let yearText = year >= 0 && year < 1000 ? String(repeating: "0", count: 4 - String(year).count) + String(year) : String(year)
        return "\(pad2(c.day ?? 1)).\(pad2(c.month ?? 1)).\(yearText), \(pad2(c.hour ?? 0)):\(pad2(c.minute ?? 0))"
    }

    /// Geschwindigkeitsfaktor, z. B. „1,12×“.
    public static func factor(_ value: Float) -> String {
        let rounded = Float(JvmMath.roundToInt(value * 100)) / 100
        return germanFixed(Double(rounded), digits: 2) + "×"
    }

    // MARK: - Hilfen

    private static func pad2<I: BinaryInteger>(_ v: I) -> String {
        let s = String(v)
        return s.count < 2 ? "0" + s : s
    }

    /// Ganze Zahl ohne Nachkommastellen, sonst kürzeste Darstellung mit Komma (wie Kotlin `Float.toString`).
    private static func compactNumber(_ v: Float) -> String {
        if v == v.rounded(.towardZero), abs(v) < 1e9 { return String(Int(v)) }
        return v.description.replacingOccurrences(of: ".", with: ",")
    }

    /// Wie `String.format(Locale.GERMANY, "%.nf", value)` der JVM: kürzeste Dezimaldarstellung,
    /// dann „halb auf“ gerundet; Dezimalkomma, ohne Tausenderpunkt.
    static func germanFixed(_ value: Double, digits: Int) -> String {
        fixed(value, digits: digits).replacingOccurrences(of: ".", with: ",")
    }

    /// Festkomma mit Rundung HALF_UP auf der kürzesten Dezimaldarstellung (Dezimalpunkt).
    static func fixed(_ value: Double, digits: Int) -> String {
        guard value.isFinite else { return value.isNaN ? "NaN" : (value > 0 ? "Infinity" : "-Infinity") }
        let negative = value.sign == .minus && value != 0
        var (mantissa, exponent) = decimalDigits(abs(value))
        // Wert = 0.mantissa × 10^exponent
        // Stellen vor dem Komma: exponent; benötigte Stellen insgesamt: exponent + digits
        let keep = exponent + digits
        if keep < 0 {
            mantissa = [0]
            exponent = 1
        } else if keep < mantissa.count {
            let roundUp = mantissa[keep] >= 5
            mantissa = Array(mantissa[0..<keep])
            if roundUp {
                var i = mantissa.count - 1
                var carry = true
                while carry && i >= 0 {
                    if mantissa[i] == 9 {
                        mantissa[i] = 0
                        i -= 1
                    } else {
                        mantissa[i] += 1
                        carry = false
                    }
                }
                if carry {
                    mantissa.insert(1, at: 0)
                    exponent += 1
                }
            }
            if mantissa.isEmpty {
                mantissa = [0]
                exponent = 1
            }
        }
        var intPart = ""
        var fracPart = ""
        if exponent <= 0 {
            intPart = "0"
            fracPart = String(repeating: "0", count: -exponent) + mantissa.map(String.init).joined()
        } else {
            for i in 0..<exponent { intPart += i < mantissa.count ? String(mantissa[i]) : "0" }
            if exponent < mantissa.count { fracPart = mantissa[exponent...].map(String.init).joined() }
        }
        while intPart.count > 1 && intPart.hasPrefix("0") { intPart.removeFirst() }
        if fracPart.count < digits { fracPart += String(repeating: "0", count: digits - fracPart.count) }
        if fracPart.count > digits { fracPart = String(fracPart.prefix(digits)) }
        let isZero = intPart == "0" && fracPart.allSatisfy { $0 == "0" }
        let body = digits > 0 ? intPart + "." + fracPart : intPart
        return negative && !isZero ? "-" + body : body
    }

    /// Ziffern der kürzesten Darstellung: Wert = 0.d1d2d3… × 10^exponent.
    private static func decimalDigits(_ value: Double) -> ([Int], Int) {
        if value == 0 { return ([0], 1) }
        let text = value.description // kürzeste, eindeutige Darstellung
        var mantissaText = text
        var exp10 = 0
        if let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            mantissaText = String(text[..<e])
            exp10 = Int(text[text.index(after: e)...]) ?? 0
        }
        var intDigits = mantissaText
        var fracDigits = ""
        if let dot = mantissaText.firstIndex(of: ".") {
            intDigits = String(mantissaText[..<dot])
            fracDigits = String(mantissaText[mantissaText.index(after: dot)...])
        }
        var all = (intDigits + fracDigits).compactMap { $0.wholeNumberValue }
        var exponent = intDigits.count + exp10
        while all.count > 1 && all.first == 0 {
            all.removeFirst()
            exponent -= 1
        }
        while all.count > 1 && all.last == 0 { all.removeLast() }
        return (all, exponent)
    }
}
