import Foundation

/// Ruhige Hintergrundfarben aus einem Cover – für das Design „Classic Music“
/// (Portierung von `cover/CoverPalette.kt`). Farben als ARGB `0xAARRGGBB`.
///
/// Gewählt werden der vorherrschende und ein zweiter, deutlich anderer Farbton (gewichtet nach Sättigung
/// und Helligkeit; Grau, Schwarz und Weiß zählen kaum). Beide werden stark abgedunkelt und in der
/// Sättigung begrenzt: Der Hintergrund soll an das Cover erinnern, aber ruhig bleiben, und weiße Schrift
/// muss darauf gut lesbar sein (Kontrast ≥ 7:1).
public struct CoverPalette: Hashable, Codable, Sendable {
    public var top: UInt32
    public var bottom: UInt32
    public var glow: UInt32

    public init(top: UInt32, bottom: UInt32, glow: UInt32) {
        self.top = top
        self.bottom = bottom
        self.glow = glow
    }

    /// Neutral (Cover ohne Farbe bzw. kein Cover): warmes Anthrazit mit Hauch Rosé.
    public static let neutral = CoverPalette(top: hsl(345, 0.16, 0.17), bottom: hsl(340, 0.12, 0.07), glow: hsl(345, 0.45, 0.42))

    static let bins = 24

    /// Palette aus Pixeln (ARGB `0xAARRGGBB`, Zeile für Zeile), z. B. ein auf 32 × 32 verkleinertes Cover.
    /// Nur die ersten `width × height` Pixel werden verwendet (sind es weniger, alle vorhandenen).
    public static func from(pixels: [UInt32], width: Int, height: Int) -> CoverPalette {
        let n = width > 0 && height > 0 ? min(pixels.count, width * height) : pixels.count
        return from(pixels: pixels.prefix(n))
    }

    public static func from<C: Collection>(pixels: C) -> CoverPalette where C.Element == UInt32 {
        var weight = [Float](repeating: 0, count: bins)
        var sumS = [Float](repeating: 0, count: bins)
        var total: Float = 0
        for p in pixels {
            if (p >> 24) < 128 { continue }
            let (h, s, l) = toHsl(p)
            // Farbanteil: gesättigt und nicht zu dunkel/hell
            let w = s * max(1 - abs(2 * l - 1), 0)
            if w < 0.08 { continue }
            let bin = min(max(JvmMath.toInt((h / 360) * Float(bins)), 0), bins - 1)
            weight[bin] += w
            sumS[bin] += s * w
            total += w
        }
        // Kein Bild (leere Pixelliste) → neutral (Kotlin hätte hier aus „nichts“ einen Rotton berechnet).
        if pixels.isEmpty || total < Float(pixels.count) * 0.04 { return neutral }
        // Nachbar-Bins zusammenfassen (Farbtöne an Bin-Grenzen)
        var smooth = [Float](repeating: 0, count: bins)
        for i in 0..<bins {
            let neighbours: Float = weight[(i + 1) % bins] + weight[(i + bins - 1) % bins]
            smooth[i] = weight[i] + 0.5 * neighbours
        }
        var first = 0
        for i in 0..<bins where smooth[i] > smooth[first] { first = i }
        var second: Int?
        for i in 0..<bins where hueDistance(i, first) >= 3 { // ≥ 45°
            if second == nil || smooth[i] > smooth[second!] { second = i }
        }
        if let s = second, !(smooth[s] > smooth[first] * 0.18) { second = nil }
        let h1 = (Float(first) + 0.5) * 360 / Float(bins)
        let s1 = min(max(sumS[first] / max(weight[first], 1e-6), 0.2), 1)
        let h2 = second.map { (Float($0) + 0.5) * 360 / Float(bins) } ?? h1
        let s2 = second.map { min(max(sumS[$0] / max(weight[$0], 1e-6), 0.2), 1) } ?? s1
        let top = readable(hsl(h1, min(s1, 0.55), 0.22))
        let bottom = readable(hsl(h2, min(s2, 0.5), second == nil ? 0.08 : 0.10))
        let glow = hsl(h1, min(s1, 0.7), 0.46)
        return CoverPalette(top: top, bottom: bottom, glow: glow)
    }

    private static func hueDistance(_ a: Int, _ b: Int) -> Int {
        let d = abs(a - b) % bins
        return min(d, bins - d)
    }

    /// Relative Leuchtdichte nach WCAG.
    public static func luminance(_ c: UInt32) -> Double {
        func ch(_ v: UInt32) -> Double {
            let x = Double(v) / 255.0
            return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * ch(c >> 16 & 0xFF) + 0.7152 * ch(c >> 8 & 0xFF) + 0.0722 * ch(c & 0xFF)
    }

    /// Kontrast weißer Schrift auf `c`.
    public static func contrastWithWhite(_ c: UInt32) -> Double { 1.05 / (luminance(c) + 0.05) }

    /// So weit abdunkeln, dass weiße Schrift einen Kontrast von mindestens 7:1 hat.
    private static func readable(_ c: UInt32) -> UInt32 {
        var color = c
        var guardCount = 0
        while contrastWithWhite(color) < 7.0 && guardCount < 40 {
            guardCount += 1
            color = scale(color, 0.92)
        }
        return color
    }

    private static func scale(_ c: UInt32, _ f: Float) -> UInt32 {
        let r = UInt32(JvmMath.toInt(Float(c >> 16 & 0xFF) * f))
        let g = UInt32(JvmMath.toInt(Float(c >> 8 & 0xFF) * f))
        let b = UInt32(JvmMath.toInt(Float(c & 0xFF) * f))
        return 0xFF00_0000 | r << 16 | g << 8 | b
    }

    /// Farbton (0…360), Sättigung und Helligkeit (0…1).
    static func toHsl(_ c: UInt32) -> (Float, Float, Float) {
        let r = Float(c >> 16 & 0xFF) / 255
        let g = Float(c >> 8 & 0xFF) / 255
        let b = Float(c & 0xFF) / 255
        let mx = max(r, max(g, b))
        let mn = min(r, min(g, b))
        let l = (mx + mn) / 2
        if mx == mn { return (0, 0, l) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        let h: Float
        if mx == r {
            h = (g - b) / d + (g < b ? 6 : 0)
        } else if mx == g {
            h = (b - r) / d + 2
        } else {
            h = (r - g) / d + 4
        }
        return (h * 60, s, l)
    }

    /// Farbe aus Farbton (Grad), Sättigung und Helligkeit (0…1), deckend.
    public static func hsl(_ h: Float, _ s: Float, _ l: Float) -> UInt32 {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (Float, Float, Float)
        switch JvmMath.toInt(hp) {
        case 0: (r1, g1, b1) = (c, x, 0)
        case 1: (r1, g1, b1) = (x, c, 0)
        case 2: (r1, g1, b1) = (0, c, x)
        case 3: (r1, g1, b1) = (0, x, c)
        case 4: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        let m = l - c / 2
        func ch(_ v: Float) -> UInt32 { UInt32(min(max(JvmMath.toInt((v + m) * 255), 0), 255)) }
        return 0xFF00_0000 | ch(r1) << 16 | ch(g1) << 8 | ch(b1)
    }
}
