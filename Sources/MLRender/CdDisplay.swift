import Foundation

/**
 * Anzeige des „Portable CD“-Players: Sieben-Segment-Ziffern wie bei den Geräten der 2000er (mit schwach
 * sichtbaren, unbeleuchteten Segmenten) – reine Rechnung, mit Unit-Tests. Gezeichnet wird die Anzeige
 * von der Oberfläche (siehe docs/PLAYER_SPEC.md, „Portable CD › Anzeige“).
 */
public enum CdDisplay {

    /** Segmente a–g als Bits (a = oben, b = oben rechts, c = unten rechts, d = unten, e = unten links, f = oben links, g = Mitte). */
    public static let A = 1, B = 2, C = 4, D = 8, E = 16, F = 32, G = 64
    public static let ALL = A | B | C | D | E | F | G

    /** Leuchtende Segmente eines Zeichens (Ziffer, '-' oder Leerzeichen). */
    public static func segments(_ ch: Character) -> Int {
        switch ch {
        case "0": return A | B | C | D | E | F
        case "1": return B | C
        case "2": return A | B | G | E | D
        case "3": return A | B | G | C | D
        case "4": return F | G | B | C
        case "5": return A | F | G | C | D
        case "6": return A | F | G | E | D | C
        case "7": return A | B | C
        case "8": return ALL
        case "9": return A | B | C | D | F | G
        case "-": return G
        default: return 0
        }
    }

    /** Titelnummer (Position in der Wiedergabeliste, ab 1) – mindestens zwei Stellen wie bei einer CD. */
    public static func trackText(_ number: Int) -> String {
        if number <= 0 { return "--" }
        if number > 9999 { return "----" }
        return leftPad(String(number), 2, "0")
    }

    /**
     * Laufzeit m:ss; Minuten ohne führende Null, aber mit fester Stellenzahl (Leerstelle), damit die
     * Anzeige beim Übergang 9:59 → 10:00 nicht springt. Ab 100 Minuten dreistellig.
     * Rückgabe: (Minuten, Sekunden), z. B. (" 1", "23").
     */
    public static func timeText(_ positionMs: Int64) -> (minutes: String, seconds: String) {
        let total = Swift.max(positionMs, 0) / 1000
        let minutes = Swift.min(total / 60, 999)
        let seconds = total % 60
        let m = leftPad(String(minutes), minutes >= 100 ? 3 : 2, " ")
        return (m, leftPad(String(seconds), 2, "0"))
    }

    /**
     * Rechtecke der sieben Segmente einer Ziffer in einem Feld der Breite [w] und Höhe [h] (Ursprung oben
     * links), Strichstärke [t]. Rückgabe: je Segment (a–g) x, y, Breite, Höhe – 28 Werte.
     */
    public static func segmentRects(_ w: Float, _ h: Float, _ t: Float) -> [Float] {
        let half = h / 2
        let inset = t * 0.62                       // Abstand der waagrechten Segmente zu den Ecken
        let horizontal = w - 2 * inset
        let vertical = half - inset - t * 0.12     // senkrechte Segmente: kleiner Spalt zur Mitte
        var out = [Float](repeating: 0, count: 28)
        func put(_ i: Int, _ x: Float, _ y: Float, _ ww: Float, _ hh: Float) {
            out[i * 4] = x; out[i * 4 + 1] = y; out[i * 4 + 2] = ww; out[i * 4 + 3] = hh
        }
        put(0, inset, 0, horizontal, t)                     // a
        put(1, w - t, inset, t, vertical)                   // b
        put(2, w - t, half + t * 0.12, t, vertical)         // c
        put(3, inset, h - t, horizontal, t)                 // d
        put(4, 0, half + t * 0.12, t, vertical)             // e
        put(5, 0, inset, t, vertical)                       // f
        put(6, inset, half - t / 2, horizontal, t)          // g
        return out
    }

    private static func leftPad(_ s: String, _ length: Int, _ pad: Character) -> String {
        s.count >= length ? s : String(repeating: pad, count: length - s.count) + s
    }
}
