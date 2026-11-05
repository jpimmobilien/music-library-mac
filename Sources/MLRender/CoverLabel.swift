import Foundation

/**
 * Label aus dem Albumcover – entspricht `circularLabel()` (Turntable.kt) und `cdLabel()` (PortableCd.kt)
 * der Android-App, dort mit `android.graphics.Canvas` gezeichnet, hier als reine Rechnung:
 *
 *  - mittig quadratisch zugeschnitten (Seitenverhältnis bleibt, keine Verzerrung),
 *  - genau auf die Anzeigegröße skaliert (Verkleinern: Flächenmittel; Vergrößern: bilinear – in
 *    vormultiplizierten Farben, damit transparente Cover keine dunklen Säume bekommen),
 *  - runder Rand mit Kantenglättung (½ Pixel, wie Skias Kreis mit ANTI_ALIAS_FLAG),
 *  - für die CD zusätzlich das Mittelloch (Radius = `LABEL_HOLE_FRACTION` · Labelradius) ausgespart.
 *
 * Erzeugt wird nur beim Titelwechsel (Hintergrund-Thread); gezeichnet wird das Ergebnis dann wie die
 * übrigen Ebenen nur noch gedreht – so flimmert der Rand beim Drehen nicht.
 */
public enum CoverLabel {

    /** Rundes Plattenlabel ([size] = `VinylRenderer.labelSizePx(S)`). */
    public static func circular(_ cover: RasterImage, size: Int) -> RasterImage {
        render(cover, size: size, holeFraction: 0)
    }

    /** Ringförmiger CD-Druck ([size] = `CdGeometry.labelSizePx(widthPx)`), Mitte frei. */
    public static func cdRing(_ cover: RasterImage, size: Int) -> RasterImage {
        render(cover, size: size, holeFraction: CdGeometry.LABEL_HOLE_FRACTION)
    }

    /** Quadratischer Ausschnitt (Mitte) auf [size] × [size] skaliert, ohne Maske. */
    public static func squareCrop(_ cover: RasterImage, size: Int) -> RasterImage {
        render(cover, size: size, holeFraction: -1)
    }

    /**
     * Ganzes Bild (ohne Zuschnitt, Seitenverhältnis wird angepasst) auf [width] × [height] – für die
     * Coverfarben: Android rechnet `CoverPalette.from` auf `createScaledBitmap(cover, 32, 32, true)`.
     * (Hier Flächenmittel statt bilinear; für die Farbstatistik gleichwertig.)
     */
    public static func scaled(_ image: RasterImage, width: Int, height: Int) -> RasterImage {
        resample(image, ox: 0, oy: 0, sw: image.width, sh: image.height, dw: width, dh: height, holeFraction: -1)
    }

    // ---------------------------------------------------------------------------------------------

    /** Gewichte einer 1-D-Neuabtastung: je Zielpixel Startindex und Gewichte (Summe 1). */
    private struct Weights {
        var start: [Int] = []
        var count: [Int] = []
        var offset: [Int] = []
        var w: [Float] = []
    }

    /** [n] Quellpixel ab [origin] → [size] Zielpixel. */
    private static func weights(origin: Int, n: Int, size: Int) -> Weights {
        var res = Weights()
        let scale = Double(size) / Double(n)
        for i in 0..<size {
            res.offset.append(res.w.count)
            if scale < 1 {
                // Verkleinern: Fläche des Zielpixels in Quellkoordinaten, Anteile der überdeckten Pixel
                let a = Double(i) / scale, b = Double(i + 1) / scale
                let j0 = Int(a.rounded(.down)), j1 = Swift.min(n - 1, Int((b - 1e-9).rounded(.down)))
                var sum = 0.0
                var ws: [Double] = []
                for j in j0...Swift.max(j0, j1) {
                    let lo = Swift.max(a, Double(j)), hi = Swift.min(b, Double(j + 1))
                    let wgt = Swift.max(0, hi - lo)
                    ws.append(wgt); sum += wgt
                }
                res.start.append(origin + j0)
                res.count.append(ws.count)
                for wgt in ws { res.w.append(Float(wgt / sum)) }
            } else {
                // Vergrößern (oder 1:1): bilinear, Ränder wiederholt
                let c = (Double(i) + 0.5) / scale - 0.5
                var j0 = Int(c.rounded(.down))
                var t = Float(c - Double(j0))
                if j0 < 0 { j0 = 0; t = 0 }
                if j0 >= n - 1 { j0 = n - 1; t = 0 }
                res.start.append(origin + j0)
                if t == 0 {
                    res.count.append(1); res.w.append(1)
                } else {
                    res.count.append(2); res.w.append(1 - t); res.w.append(t)
                }
            }
        }
        return res
    }

    private static func render(_ cover: RasterImage, size: Int, holeFraction: Float) -> RasterImage {
        let side = Swift.min(cover.width, cover.height)
        let ox = (cover.width - side) / 2, oy = (cover.height - side) / 2
        return resample(cover, ox: ox, oy: oy, sw: side, sh: side, dw: size, dh: size, holeFraction: holeFraction)
    }

    /**
     * Quellrechteck (ox, oy, sw × sh) → dw × dh. [holeFraction] < 0: ohne Maske; 0: Kreis; > 0: Ring
     * (nur für quadratische Ziele sinnvoll).
     */
    private static func resample(_ cover: RasterImage, ox: Int, oy: Int, sw: Int, sh: Int, dw: Int, dh: Int, holeFraction: Float) -> RasterImage {
        var out = RasterImage(width: Swift.max(0, dw), height: Swift.max(0, dh))
        if dw <= 0 || dh <= 0 || sw <= 0 || sh <= 0 { return out }
        let size = dw
        let wx = weights(origin: ox, n: sw, size: dw)
        let wy = weights(origin: oy, n: sh, size: dh)
        let srcW = cover.width
        // 1) waagerecht: alle benötigten Quellzeilen → dw Spalten (vormultipliziert, Float)
        let rows = sh
        let tmp = UnsafeMutablePointer<Float>.allocate(capacity: rows * size * 4)
        defer { tmp.deallocate() }
        cover.pixels.withUnsafeBufferPointer { src in
            wx.start.withUnsafeBufferPointer { st in
            wx.count.withUnsafeBufferPointer { ct in
            wx.offset.withUnsafeBufferPointer { of in
            wx.w.withUnsafeBufferPointer { ww in
                parallelFor(rows) { r in
                    let srow = (oy + r) * srcW
                    let trow = r * size * 4
                    for i in 0..<size {
                        var a: Float = 0, rr: Float = 0, g: Float = 0, b: Float = 0
                        for k in 0..<ct[i] {
                            let p = src[srow + st[i] + k]
                            let wgt = ww[of[i] + k]
                            let pa = Float(p >> 24) / 255
                            a += pa * wgt
                            rr += Float(p >> 16 & 255) * pa * wgt
                            g += Float(p >> 8 & 255) * pa * wgt
                            b += Float(p & 255) * pa * wgt
                        }
                        tmp[trow + i * 4] = a; tmp[trow + i * 4 + 1] = rr
                        tmp[trow + i * 4 + 2] = g; tmp[trow + i * 4 + 3] = b
                    }
                }
            }}}}
        }
        // 2) senkrecht + Kreis-/Ringmaske, zurück in nicht vormultipliziertes ARGB
        let c = Float(size) / 2
        let rows2 = dh
        let rOut = c
        let rIn = holeFraction > 0 ? c * holeFraction : 0
        let mask = holeFraction >= 0
        out.pixels.withUnsafeMutableBufferPointer { dst in
            let px = dst.baseAddress!
            wy.start.withUnsafeBufferPointer { st in
            wy.count.withUnsafeBufferPointer { ct in
            wy.offset.withUnsafeBufferPointer { of in
            wy.w.withUnsafeBufferPointer { ww in
                parallelFor(rows2) { y in
                    let dy = Float(y) + 0.5 - c
                    for x in 0..<size {
                        var cov: Float = 1
                        if mask {
                            let dx = Float(x) + 0.5 - c
                            let d = (dx * dx + dy * dy).squareRoot()
                            var e = rOut - d
                            if rIn > 0 { e = Swift.min(e, d - rIn) }
                            cov = clampf(e + 0.5, 0, 1)
                            if cov <= 0 { px[y * size + x] = 0; continue }
                        }
                        var a: Float = 0, rr: Float = 0, g: Float = 0, b: Float = 0
                        for k in 0..<ct[y] {
                            let t = ((st[y] - oy + k) * size + x) * 4
                            let wgt = ww[of[y] + k]
                            a += tmp[t] * wgt; rr += tmp[t + 1] * wgt; g += tmp[t + 2] * wgt; b += tmp[t + 3] * wgt
                        }
                        if a <= 0.0005 { px[y * size + x] = 0; continue }
                        let inv = 1 / a
                        let alpha = kRound(clampf(a * cov, 0, 1) * 255)
                        if alpha == 0 { px[y * size + x] = 0; continue }
                        px[y * size + x] = (alpha << 24) | (kRound(Swift.min(rr * inv, 255)) << 16) |
                            (kRound(Swift.min(g * inv, 255)) << 8) | kRound(Swift.min(b * inv, 255))
                    }
                }
            }}}}
        }
        return out
    }
}
