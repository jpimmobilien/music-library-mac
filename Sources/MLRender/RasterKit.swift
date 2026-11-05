import Foundation

/** Pixelbereich (x0, y0, x1, y1), jeweils einschließlich – entspricht dem `IntArray` des Originals. */
struct PixelBox {
    var x0: Int
    var y0: Int
    var x1: Int
    var y1: Int

    init(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
        self.x0 = x0; self.y0 = y0; self.x1 = x1; self.y1 = y1
    }
}

/**
 * Kleiner Software-Zeichner für Kassette und CD-Player (deterministisch, ohne Apple-Frameworks):
 *  - Farben werden linear und vormultipliziert gemischt („over“), erst am Ende nach sRGB umgerechnet.
 *  - Formen sind vorzeichenbehaftete Abstandsfunktionen (in Pixeln) → saubere Kantenglättung.
 *  - Gezeichnet wird nur im umschließenden Rechteck einer Form, Zeilen parallel.
 *
 * Die vier Kanäle liegen in eigenen, manuell verwalteten Puffern (keine Kopien, keine Exklusivitäts-
 * prüfungen in den parallelen Schleifen).
 */
final class LinearCanvas {
    let width: Int
    let height: Int
    private let r: UnsafeMutablePointer<Float>
    private let g: UnsafeMutablePointer<Float>
    private let b: UnsafeMutablePointer<Float>
    private let a: UnsafeMutablePointer<Float>

    /** Farbe (linear, NICHT vormultipliziert) und Deckkraft. */
    struct Rgba {
        var r: Float = 0
        var g: Float = 0
        var b: Float = 0
        var a: Float = 0
    }

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        let n = max(1, width * height)
        r = .allocate(capacity: n); r.initialize(repeating: 0, count: n)
        g = .allocate(capacity: n); g.initialize(repeating: 0, count: n)
        b = .allocate(capacity: n); b.initialize(repeating: 0, count: n)
        a = .allocate(capacity: n); a.initialize(repeating: 0, count: n)
    }

    deinit {
        r.deallocate(); g.deallocate(); b.deallocate(); a.deallocate()
    }

    /** Ganze Fläche als Bereich (wird beim Zeichnen auf das Bild begrenzt). */
    var all: PixelBox { PixelBox(0, 0, width, height) }

    /**
     * Zeichnet eine Form. [sdf] liefert den Abstand zum Rand in Pixeln (< 0 = innen); [shade] die Farbe
     * am Punkt (darf den Farbwert überschreiben – er bleibt wie im Original innerhalb einer Zeile
     * erhalten). [bounds] = Pixelbereich (x0, y0, x1, y1), der berechnet wird.
     */
    @inline(__always)
    func fill(_ bounds: PixelBox, sdf: (Float, Float) -> Float, shade: (Float, Float, inout Rgba) -> Void) {
        let x0 = Swift.max(0, bounds.x0), y0 = Swift.max(0, bounds.y0)
        let x1 = Swift.min(width - 1, bounds.x1), y1 = Swift.min(height - 1, bounds.y1)
        if x0 > x1 || y0 > y1 { return }
        let r = self.r, g = self.g, b = self.b, a = self.a, w = width
        parallelFor(y1 - y0 + 1) { j in
            let y = y0 + j
            var c = Rgba()
            let py = Float(y) + 0.5
            let row = y * w
            for x in x0...x1 {
                let px = Float(x) + 0.5
                let d = sdf(px, py)
                let cov = clampf(0.5 - d, 0, 1)
                if cov <= 0 { continue }
                shade(px, py, &c)
                let ca = c.a * cov
                if ca <= 0 { continue }
                let i = row + x
                let k: Float = 1 - ca
                r[i] = c.r * ca + r[i] * k
                g[i] = c.g * ca + g[i] * k
                b[i] = c.b * ca + b[i] * k
                a[i] = ca + a[i] * k
            }
        }
    }

    /** Weichzeichnen nur der Deckkraft (für Schatten): drei Kastenfilter ≈ Gauß. */
    func blurAlpha(_ radius: Int) {
        if radius <= 0 { return }
        let n = width * height
        let tmp = UnsafeMutablePointer<Float>.allocate(capacity: Swift.max(1, n))
        defer { tmp.deallocate() }
        for _ in 0..<3 {
            boxBlurH(src: a, dst: tmp, width: width, height: height, radius: radius)
            boxBlurV(src: tmp, dst: a, width: width, height: height, radius: radius)
        }
    }

    /** Fertiges Bild (sRGB, nicht vormultipliziert). */
    func toRaster() -> RasterImage {
        var out = RasterImage(width: width, height: height)
        let r = self.r, g = self.g, b = self.b, a = self.a, w = width
        let lut = RasterKit.lut
        out.pixels.withUnsafeMutableBufferPointer { buf in
            let px = buf.baseAddress!
            parallelFor(height) { y in
                for x in 0..<w {
                    let i = y * w + x
                    let al = a[i]
                    if al <= 0.0005 { continue }
                    let inv: Float = 1 / al
                    px[i] = (kRound(clampf(al, 0, 1) * 255) << 24) |
                        (RasterKit.srgb(lut, r[i] * inv) << 16) | (RasterKit.srgb(lut, g[i] * inv) << 8) | RasterKit.srgb(lut, b[i] * inv)
                }
            }
        }
        return out
    }
}

/**
 * Waagerechter Kastenfilter (Zeile für Zeile wie im Original, Ränder wiederholt; Ergebnis in [dst]).
 * Gemeinsam für den Schatten der Kassette/des CD-Players und den Tonarm-Schatten.
 */
func boxBlurH(src: UnsafeMutablePointer<Float>, dst: UnsafeMutablePointer<Float>, width w: Int, height: Int, radius rad: Int) {
    let nf = Float(2 * rad + 1)
    parallelFor(height) { y in
        let o = y * w
        var sum: Float = 0
        for x in -rad...rad { sum += src[o + Swift.min(Swift.max(x, 0), w - 1)] }
        for x in 0..<w {
            dst[o + x] = sum / nf
            sum += src[o + Swift.min(x + rad + 1, w - 1)] - src[o + Swift.max(x - rad, 0)]
        }
    }
}

/**
 * Senkrechter Kastenfilter. Das Original läuft Spalte für Spalte; hier laufen Gruppen von Spalten
 * gemeinsam Zeile für Zeile (cache-freundlich) – je Spalte in exakt derselben Rechenreihenfolge,
 * daher bitgleiche Ergebnisse.
 */
func boxBlurV(src: UnsafeMutablePointer<Float>, dst: UnsafeMutablePointer<Float>, width w: Int, height h: Int, radius rad: Int) {
    let nf = Float(2 * rad + 1)
    let chunk = 64
    let chunks = (w + chunk - 1) / chunk
    parallelFor(chunks) { ci in
        let xs = ci * chunk
        let cw = Swift.min(w, xs + chunk) - xs
        let s = UnsafeMutablePointer<Float>.allocate(capacity: cw)
        s.initialize(repeating: 0, count: cw)
        defer { s.deallocate() }
        for y in -rad...rad {
            let o = Swift.min(Swift.max(y, 0), h - 1) * w + xs
            for j in 0..<cw { s[j] += src[o + j] }
        }
        for y in 0..<h {
            let o = y * w + xs
            let on = Swift.min(y + rad + 1, h - 1) * w + xs
            let op = Swift.max(y - rad, 0) * w + xs
            for j in 0..<cw {
                dst[o + j] = s[j] / nf
                s[j] += src[on + j] - src[op + j]
            }
        }
    }
}

/** Abstandsfunktionen und Hilfen (alle Längen in Pixeln). */
enum RasterKit {
    /**
     * Linear → sRGB (0…255), Tabelle mit 4097 Stützstellen wie im Original. Als roher Zeiger (einmal
     * angelegt, nie freigegeben), damit die heißen Schleifen ihn vorab übernehmen können – der Zugriff
     * über eine `static let`-Eigenschaft kostet je Pixel eine Initialisierungsprüfung.
     */
    static let lut: UnsafePointer<UInt32> = {
        let p = UnsafeMutablePointer<UInt32>.allocate(capacity: 4097)
        for i in 0...4096 {
            let v = Double(i) / 4096.0
            let s = v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
            p[i] = UInt32(Swift.min(Swift.max((s * 255.0).rounded(.toNearestOrAwayFromZero), 0), 255))
        }
        return UnsafePointer(p)
    }()

    /** Linear (0…1) → sRGB-Wert 0…255 (NaN → 0 wie `NaN.toInt()` im Original). */
    @inline(__always)
    static func srgb(_ lut: UnsafePointer<UInt32>, _ linear: Float) -> UInt32 {
        let v: Float = linear > 0 ? (linear < 1 ? linear : 1) : 0
        return lut[Int(v * 4096)]
    }

    /** Linear → ARGB (Deckkraft 0…1). */
    @inline(__always)
    static func argb(_ lut: UnsafePointer<UInt32>, _ a: Float, _ rLin: Float, _ gLin: Float, _ bLin: Float) -> UInt32 {
        let alpha = kRound(clampf(a, 0, 1) * 255)
        return (alpha << 24) | (srgb(lut, rLin) << 16) | (srgb(lut, gLin) << 8) | srgb(lut, bLin)
    }

    /** sRGB-Farbwert (0…255) → linear. */
    static func lin(_ c: Int) -> Float {
        let v = Double(c) / 255.0
        return Float(v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4))
    }

    @inline(__always)
    static func circle(_ px: Float, _ py: Float, _ cx: Float, _ cy: Float, _ radius: Float) -> Float {
        let dx = px - cx, dy = py - cy
        return (dx * dx + dy * dy).squareRoot() - radius
    }

    @inline(__always)
    static func ring(_ px: Float, _ py: Float, _ cx: Float, _ cy: Float, _ inner: Float, _ outer: Float) -> Float {
        let d = ((px - cx) * (px - cx) + (py - cy) * (py - cy)).squareRoot()
        return fmaxk(d - outer, inner - d)
    }

    /** Abgerundetes Rechteck: Mitte (cx, cy), halbe Breite/Höhe, Eckenradius. */
    @inline(__always)
    static func roundRect(_ px: Float, _ py: Float, _ cx: Float, _ cy: Float, _ hw: Float, _ hh: Float, _ radius: Float) -> Float {
        let qx = abs(px - cx) - hw + radius
        let qy = abs(py - cy) - hh + radius
        let ox = fmaxk(qx, 0), oy = fmaxk(qy, 0)
        return (ox * ox + oy * oy).squareRoot() + fmink(fmaxk(qx, qy), 0) - radius
    }

    /** Konvexes Polygon (Punkte im Uhrzeigersinn, Bildschirmkoordinaten). */
    @inline(__always)
    static func convex(_ px: Float, _ py: Float, _ xs: [Float], _ ys: [Float]) -> Float {
        var d = -Float.greatestFiniteMagnitude
        let n = xs.count
        for i in 0..<n {
            let j = (i + 1) % n
            let ex = xs[j] - xs[i], ey = ys[j] - ys[i]
            let len = (ex * ex + ey * ey).squareRoot()
            // Außennormale bei Uhrzeigersinn (y nach unten): (ey, −ex)
            let nx = ey / len, ny = -ex / len
            d = fmaxk(d, (px - xs[i]) * nx + (py - ys[i]) * ny)
        }
        return d
    }

    @inline(__always)
    static func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = clampf((x - e0) / (e1 - e0), 0, 1)
        return t * t * (3 - 2 * t)
    }

    /** Deterministisches Rauschen 0…1 aus einer Ganzzahl (32-Bit-Arithmetik wie im Original). */
    @inline(__always)
    static func hash(_ i: Int32) -> Float {
        var x = UInt32(bitPattern: i) &* 0x27d4eb2d
        x ^= x >> 15
        x = x &* 0x2c1b3c6d
        x ^= x >> 12
        x = x &* 0x297a2d39
        x ^= x >> 15
        return Float(x >> 8) / 16777216
    }

    @inline(__always)
    static func hash2(_ x: Int32, _ y: Int32) -> Float { hash((x &* 73856093) ^ (y &* 19349663)) }

    @inline(__always)
    static func gauss(_ x: Float, _ sigma: Float) -> Float { kexp(-(x * x) / (2 * sigma * sigma)) }

    static func box(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float) -> PixelBox {
        PixelBox(Int(kInt(x0)) - 2, Int(kInt(y0)) - 2, Int(kInt(x1)) + 2, Int(kInt(y1)) + 2)
    }
}
