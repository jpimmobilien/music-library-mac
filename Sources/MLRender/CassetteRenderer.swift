import Foundation

/**
 * Maße einer Compact Cassette in Millimetern (Vorderansicht, Ursprung oben links) und die Mechanik
 * der Wickel. Alles reine Rechnung – mit Unit-Tests.
 */
public enum CassetteGeometry {
    public static let WIDTH_MM: Float = 100.4
    public static let HEIGHT_MM: Float = 63.8
    public static let ASPECT: Float = WIDTH_MM / HEIGHT_MM

    /** Wickelkerne (Abstand der Antriebsdorne 42,6 mm). */
    public static let HUB_LEFT_X: Float = 28.9
    public static let HUB_RIGHT_X: Float = 71.5
    public static let HUB_Y: Float = 30.5

    /** Kern (Nabe + Vorspann) und voller Wickel. */
    public static let CORE_RADIUS: Float = 8.6
    public static let FULL_RADIUS: Float = 21.6
    public static let HUB_RADIUS: Float = 8.2

    /** Etikett oben. */
    public static let LABEL_LEFT: Float = 4.6
    public static let LABEL_TOP: Float = 3.6
    public static let LABEL_RIGHT: Float = 95.8
    public static let LABEL_BOTTOM: Float = 15.4

    /** Umlenkrollen unten; Band läuft auf [TAPE_Y]. */
    public static let ROLLER_LEFT_X: Float = 13.6
    public static let ROLLER_RIGHT_X: Float = 86.8
    public static let ROLLER_Y: Float = 53.2
    public static let ROLLER_RADIUS: Float = 2.3
    public static let TAPE_Y: Float = ROLLER_Y + ROLLER_RADIUS

    /** Bandgeschwindigkeit 4,76 cm/s. */
    public static let TAPE_SPEED_MM_S: Float = 47.6

    /**
     * Wickelradien in mm bei Fortschritt [progress] (0 = Anfang: links voll, rechts leer). Die Bandmenge
     * entspricht der Wickelfläche – deshalb Wurzelverlauf, nicht linear.
     */
    public static func packRadii(_ progress: Float) -> (left: Float, right: Float) {
        let p = clampf(progress, 0, 1)
        let core2 = CORE_RADIUS * CORE_RADIUS
        let span = FULL_RADIUS * FULL_RADIUS - core2
        return ((core2 + (1 - p) * span).squareRoot(), (core2 + p * span).squareRoot())
    }

    /**
     * Drehgeschwindigkeit eines Wickels in Grad pro Sekunde (bei gleicher Bandgeschwindigkeit dreht ein
     * kleiner Wickel schneller). [speedFactor] = Wiedergabegeschwindigkeit (Motorfaktor, 1 = normal).
     */
    public static func degreesPerSecond(_ radiusMm: Float, speedFactor: Float = 1) -> Float {
        TAPE_SPEED_MM_S * speedFactor / radiusMm * 180 / PI_F
    }
}

/**
 * Grafikebenen der Kassette (wie beim Plattenspieler: einmal pro Größe berechnet, danach nur gezeichnet
 * bzw. gedreht). Klar-transparentes, leicht rauchig-rosé getöntes Gehäuse, durch das man Wickel,
 * Naben, Umlenkrollen, Andruckfilz und Schrauben sieht; oben ein Papieretikett (Cover und Text legt die
 * Oberfläche darüber).
 *
 *  - [back]: Rückwand, Innenleben (Rollen, Filz, Führungen), weicher Schatten – statisch.
 *  - [pack]: Bandwickel in voller Größe; die Oberfläche schneidet ihn auf den aktuellen Radius zu.
 *  - [hub]: Nabe mit Zähnen und Bandklemme – dreht sich.
 *  - [front]: Vorderschale (Tönung, Glanz, Kanten, Schrauben, Kopföffnungen) und Etikettpapier – statisch.
 *
 * Alle Ebenen haben (außer [pack]/[hub]) die Größe `widthPx × heightFor(widthPx)`; 1 mm = [pxPerMm] px,
 * die Kassette beginnt bei ([MARGIN_MM], [MARGIN_MM]) mm. Ergebnis bitgleich zu `CassetteRenderer.kt`.
 */
public enum CassetteRenderer {

    private typealias G = CassetteGeometry

    /** Zusätzlicher Rand um die Kassette (für den Schatten), in mm. */
    public static let MARGIN_MM: Float = 4

    /** Pixel je Millimeter bei einer Bildbreite von [widthPx]. */
    public static func pxPerMm(_ widthPx: Int) -> Float { Float(widthPx) / (G.WIDTH_MM + 2 * MARGIN_MM) }

    /** Bildhöhe zu einer Bildbreite (Ebenen [back]/[front]). */
    public static func heightFor(_ widthPx: Int) -> Int { Int(kInt((G.HEIGHT_MM + 2 * MARGIN_MM) * pxPerMm(widthPx))) }

    /** Seitenlänge der Nabe [hub] in px. */
    public static func hubSizePx(_ widthPx: Int) -> Int { Int(kInt(2 * G.HUB_RADIUS * pxPerMm(widthPx))) + 4 }

    /** Seitenlänge des Wickels [pack] in px. */
    public static func packSizePx(_ widthPx: Int) -> Int { Int(kInt(2 * G.FULL_RADIUS * pxPerMm(widthPx))) + 4 }

    private struct Scale {
        let k: Float
        @inline(__always) func x(_ mm: Float) -> Float { (mm + MARGIN_MM) * k }
        @inline(__always) func y(_ mm: Float) -> Float { (mm + MARGIN_MM) * k }
        @inline(__always) func l(_ mm: Float) -> Float { mm * k }
    }

    /** Umriss der Schale (abgerundetes Rechteck). */
    @inline(__always)
    private static func shellSdf(_ s: Scale, _ px: Float, _ py: Float, _ inset: Float = 0) -> Float {
        RasterKit.roundRect(px, py, s.x(G.WIDTH_MM / 2), s.y(G.HEIGHT_MM / 2), s.l(G.WIDTH_MM / 2 - inset), s.l(G.HEIGHT_MM / 2 - inset), s.l(3.2 - inset * 0.5))
    }

    private static func lin(_ c: Int) -> Float { RasterKit.lin(c) }

    // ---------------------------------------------------------------------------------------------

    /** Rückwand mit Innenleben und Schatten. */
    public static func back(_ widthPx: Int) -> RasterImage {
        let k = pxPerMm(widthPx)
        let s = Scale(k: k)
        let c = LinearCanvas(width: widthPx, height: heightFor(widthPx))
        let all = PixelBox(0, 0, c.width, c.height)
        let fh = Float(c.height)
        // weicher Schatten (unten rechts versetzt)
        let so1 = s.l(0.6), so2 = s.l(1.6)
        c.fill(all, sdf: { px, py in shellSdf(s, px - so1, py - so2) }) { _, _, o in
            o.r = 0; o.g = 0; o.b = 0; o.a = 0.55
        }
        c.blurAlpha(Swift.max(Int(kInt(s.l(1.6))), 1))
        // Rückwand: rauchig, innen dunkel (man blickt in das Gehäuse)
        c.fill(all, sdf: { px, py in shellSdf(s, px, py) }) { _, py, o in
            let v = py / fh
            let base: Float = 0.020 + 0.012 * (1 - v)
            o.r = base * 1.08; o.g = base * 0.96; o.b = base * 1.02; o.a = 0.96
        }
        // Innenkanten der Rückwand (Rippen, die man durch die klare Schale sieht)
        let rib0 = lin(58), rib1 = lin(50), rib2 = lin(54)
        func rib(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ w: Float, _ alpha: Float) {
            let ax = s.x(x0), ay = s.y(y0), bx = s.x(x1), by = s.y(y1)
            let dx = bx - ax, dy = by - ay
            let len2 = dx * dx + dy * dy
            let hw = s.l(w) / 2
            c.fill(RasterKit.box(s.x(Swift.min(x0, x1)) - s.l(w), s.y(Swift.min(y0, y1)) - s.l(w), s.x(Swift.max(x0, x1)) + s.l(w), s.y(Swift.max(y0, y1)) + s.l(w)), sdf: { px, py in
                // Abstand zu einer Strecke
                let t = clampf(((px - ax) * dx + (py - ay) * dy) / len2, 0, 1)
                let qx = ax + t * dx - px, qy = ay + t * dy - py
                return (qx * qx + qy * qy).squareRoot() - hw
            }) { _, _, o in o.r = rib0; o.g = rib1; o.b = rib2; o.a = alpha }
        }
        // Fenster-Einfassung innen, Führungsstege
        rib(20, 18.6, 80.4, 18.6, 0.35, 0.55)
        rib(20, 42.4, 80.4, 42.4, 0.35, 0.55)
        rib(9, 47.5, 91.4, 47.5, 0.3, 0.35)
        // Wickelteller-Ringe (Gleitfolie) um die Naben
        let bush0 = lin(14), bush1 = lin(12)
        for hx in [G.HUB_LEFT_X, G.HUB_RIGHT_X] {
            let cx = s.x(hx), cy = s.y(G.HUB_Y)
            let ri = s.l(G.FULL_RADIUS + 0.7), ro = s.l(G.FULL_RADIUS + 1.0)
            c.fill(RasterKit.box(s.x(hx - 23), s.y(G.HUB_Y - 23), s.x(hx + 23), s.y(G.HUB_Y + 23)), sdf: { px, py in
                RasterKit.ring(px, py, cx, cy, ri, ro)
            }) { _, _, o in o.r = rib0; o.g = rib1; o.b = rib2; o.a = 0.35 }
            // Lagerbuchse unter der Nabe
            let rb = s.l(4.2)
            c.fill(RasterKit.box(s.x(hx - 5), s.y(G.HUB_Y - 5), s.x(hx + 5), s.y(G.HUB_Y + 5)), sdf: { px, py in
                RasterKit.circle(px, py, cx, cy, rb)
            }) { _, _, o in o.r = bush0; o.g = bush1; o.b = bush0; o.a = 1 }
        }
        // Umlenkrollen (weißer Kunststoff mit Achse)
        for rx in [G.ROLLER_LEFT_X, G.ROLLER_RIGHT_X] {
            let cx = s.x(rx), cy = s.y(G.ROLLER_Y), rr = s.l(G.ROLLER_RADIUS)
            c.fill(RasterKit.box(s.x(rx - 3), s.y(G.ROLLER_Y - 3), s.x(rx + 3), s.y(G.ROLLER_Y + 3)), sdf: { px, py in
                RasterKit.circle(px, py, cx, cy, rr)
            }) { px, py, o in
                let nx = (px - cx) / rr, ny = (py - cy) / rr
                let shadeV: Float = 0.55 + 0.45 * clampf(-(nx * 0.6 + ny * 0.8), -1, 1)
                o.r = 0.62 * shadeV; o.g = 0.58 * shadeV; o.b = 0.55 * shadeV; o.a = 1
            }
            let ra = s.l(0.7)
            c.fill(RasterKit.box(s.x(rx - 1), s.y(G.ROLLER_Y - 1), s.x(rx + 1), s.y(G.ROLLER_Y + 1)), sdf: { px, py in
                RasterKit.circle(px, py, cx, cy, ra)
            }) { _, _, o in o.r = 0.05; o.g = 0.05; o.b = 0.05; o.a = 1 }
        }
        // Andruckfilz auf Blattfeder (Mitte unten)
        do {
            let cx = s.x(50.2), cy = s.y(G.TAPE_Y + 1.1), hw = s.l(7.2), hh = s.l(0.45), rr = s.l(0.3)
            let c0 = lin(130), c1 = lin(126), c2 = lin(122)
            c.fill(RasterKit.box(s.x(42), s.y(G.TAPE_Y - 0.2), s.x(58.4), s.y(G.TAPE_Y + 2.2)), sdf: { px, py in
                RasterKit.roundRect(px, py, cx, cy, hw, hh, rr)
            }) { _, _, o in o.r = c0; o.g = c1; o.b = c2; o.a = 1 }
        }
        do {
            let cx = s.x(50.2), cy = s.y(G.TAPE_Y + 0.55), hw = s.l(2.6), hh = s.l(0.55), rr = s.l(0.2)
            let f0 = lin(214), f1 = lin(200), f2 = lin(186)
            c.fill(RasterKit.box(s.x(47), s.y(G.TAPE_Y), s.x(53.4), s.y(G.TAPE_Y + 1.4)), sdf: { px, py in
                RasterKit.roundRect(px, py, cx, cy, hw, hh, rr)
            }) { px, _, o in
                let n = RasterKit.hash(kInt(px * 3))
                o.r = f0 * (0.85 + 0.15 * n); o.g = f1 * (0.85 + 0.15 * n); o.b = f2 * (0.85 + 0.15 * n); o.a = 1
            }
        }
        return c.toRaster()
    }

    /** Bandwickel bei vollem Radius (konzentrische Lagen, satiniertes Braunschwarz, stillstehender Glanz). */
    public static func pack(_ widthPx: Int) -> RasterImage {
        let k = pxPerMm(widthPx)
        let r = G.FULL_RADIUS * k
        let size = Int(kInt(2 * r)) + 4
        let c = LinearCanvas(width: size, height: size)
        let cx = Float(size) / 2, cy = Float(size) / 2
        let all = PixelBox(0, 0, size, size)
        c.fill(all, sdf: { px, py in RasterKit.circle(px, py, cx, cy, r) }) { px, py, o in
            let dx = px - cx, dy = py - cy
            let d = (dx * dx + dy * dy).squareRoot()
            let layer = RasterKit.hash(kInt(d * 1.7)) * 0.5 + RasterKit.hash(kInt(d * 0.45) &+ 999) * 0.5
            let ang = katan2(dy, dx)
            // Satinglanz quer zur Lichtrichtung (links oben), wie bei Bandwickeln
            let sheen: Float = 0.5 + 0.5 * kcos(2 * (ang + 2.2))
            let base: Float = 0.012 + 0.008 * layer
            let gloss: Float = 0.045 * sheen * sheen * (0.4 + 0.6 * (d / r))
            o.r = base * 1.25 + gloss * 1.0
            o.g = base * 0.92 + gloss * 0.92
            o.b = base * 0.78 + gloss * 0.95
            o.a = 1
        }
        // Stirnkante des Wickels etwas heller
        let ri = r - k * 0.35
        c.fill(all, sdf: { px, py in RasterKit.ring(px, py, cx, cy, ri, r) }) { _, _, o in
            o.r = 0.09; o.g = 0.075; o.b = 0.07; o.a = 0.55
        }
        return c.toRaster()
    }

    /** Nabe: cremeweißer Kunststoff mit sechs Mitnehmerzähnen innen und Bandklemme – dreht sich. */
    public static func hub(_ widthPx: Int) -> RasterImage {
        let k = pxPerMm(widthPx)
        let r = G.HUB_RADIUS * k
        let size = Int(kInt(2 * r)) + 4
        let c = LinearCanvas(width: size, height: size)
        let cx = Float(size) / 2, cy = Float(size) / 2
        let all = PixelBox(0, 0, size, size)
        let inner: Float = 4.1 * k
        // Ring
        let h0 = lin(236), h1 = lin(226), h2 = lin(216)
        c.fill(all, sdf: { px, py in RasterKit.ring(px, py, cx, cy, inner, r) }) { px, py, o in
            let nx = (px - cx) / r, ny = (py - cy) / r
            let l: Float = 0.78 + 0.22 * (-(nx * 0.55 + ny * 0.83))
            let d = ((px - cx) * (px - cx) + (py - cy) * (py - cy)).squareRoot() / r
            let bevel = RasterKit.smoothstep(0.86, 1, d) * 0.25
            o.r = h0 * (l - bevel); o.g = h1 * (l - bevel); o.b = h2 * (l - bevel); o.a = 1
        }
        // Mitnehmerzähne (6) nach innen
        let t0 = lin(214), t1 = lin(204), t2 = lin(194)
        for t in 0..<6 {
            let a = Float(t) * PI_F / 3
            let ca = kcos(a), sa = ksin(a)
            let tx = cx + ca * (inner - k * 0.7), ty = cy + sa * (inner - k * 0.7)
            let hl = k * 0.85, hc = k * 0.45
            c.fill(RasterKit.box(tx - k * 1.2, ty - k * 1.2, tx + k * 1.2, ty + k * 1.2), sdf: { px, py in
                // Rechteck entlang der Radialrichtung
                let dx = px - tx, dy = py - ty
                let along = dx * ca + dy * sa, across = -dx * sa + dy * ca
                return fmaxk(abs(along) - hl, abs(across) - hc)
            }) { _, _, o in o.r = t0; o.g = t1; o.b = t2; o.a = 1 }
        }
        // Bandklemme (Aussparung am Rand) – macht die Drehung sichtbar
        let clampY = cy - r + k * 1.0
        let k0 = lin(60), k1 = lin(52), k2 = lin(50)
        c.fill(all, sdf: { px, py in
            RasterKit.roundRect(px, py, cx, clampY, k * 1.6, k * 1.05, k * 0.3)
        }) { _, _, o in o.r = k0; o.g = k1; o.b = k2; o.a = 1 }
        // feiner Schatten innen
        let si = inner - k * 0.25, so = inner + k * 0.35
        c.fill(all, sdf: { px, py in RasterKit.ring(px, py, cx, cy, si, so) }) { _, _, o in
            o.r = 0; o.g = 0; o.b = 0; o.a = 0.35
        }
        return c.toRaster()
    }

    /** Vorderschale (Tönung, Kopfbereich, Fenster, Kanten, Glanz, Schrauben) und Etikettpapier. */
    public static func front(_ widthPx: Int) -> RasterImage {
        let k = pxPerMm(widthPx)
        let s = Scale(k: k)
        let c = LinearCanvas(width: widthPx, height: heightFor(widthPx))
        let all = PixelBox(0, 0, c.width, c.height)
        let fw = Float(c.width), fh = Float(c.height)
        // klare, leicht rauchig-rosé getönte Vorderschale
        let sh0 = lin(62), sh1 = lin(44), sh2 = lin(52)
        c.fill(all, sdf: { px, py in shellSdf(s, px, py) }) { _, _, o in
            o.r = sh0; o.g = sh1; o.b = sh2; o.a = 0.11
        }
        // unterer Kopfbereich (trapezförmig, dichter)
        let tx: [Float] = [s.x(17.6), s.x(21.6), s.x(78.8), s.x(82.8)]
        let ty: [Float] = [s.y(G.HEIGHT_MM), s.y(50.6), s.y(50.6), s.y(G.HEIGHT_MM)]
        let ty0 = ty[0], ty1 = ty[1]
        let hd0 = lin(30), hd1 = lin(26), hd2 = lin(29)
        c.fill(RasterKit.box(tx[0], ty[1], tx[3], ty[0]), sdf: { px, py in
            fmaxk(RasterKit.convex(px, py, tx, ty), shellSdf(s, px, py))
        }) { _, py, o in
            let v = (py - ty1) / (ty0 - ty1)
            o.r = hd0 + 0.01 * v; o.g = hd1; o.b = hd2; o.a = 0.88
        }
        // Lichtkante oben am Trapez
        let k12 = k * 0.12
        c.fill(RasterKit.box(tx[1], ty[1] - 2, tx[2], ty[1] + 2), sdf: { _, py in abs(py - ty1 - k12) - k12 }) { _, _, o in
            o.r = 0.30; o.g = 0.26; o.b = 0.28; o.a = 0.6
        }
        // Öffnungen: Tonwelle (groß), Führungsstifte (klein), Kopffenster
        let holes: [(Float, Float, Float)] = [(25.6, 58.4, 1.75), (74.8, 58.4, 1.75), (35.6, 58.9, 1.15), (64.8, 58.9, 1.15)]
        for (hx, hy, hr) in holes {
            let cx = s.x(hx), cy = s.y(hy), rr = s.l(hr)
            c.fill(RasterKit.box(s.x(hx - hr - 1), s.y(hy - hr - 1), s.x(hx + hr + 1), s.y(hy + hr + 1)), sdf: { px, py in
                RasterKit.circle(px, py, cx, cy, rr)
            }) { _, py, o in
                let ny = (py - cy) / rr
                o.r = 0.004; o.g = 0.004; o.b = 0.005; o.a = 1
                if ny > 0.55 { o.r = 0.06; o.g = 0.055; o.b = 0.06 }
            }
        }
        do {
            let cx = s.x(50.2), cy = s.y(61.6), hw = s.l(6.0), hh = s.l(2.0), rr = s.l(0.4)
            c.fill(RasterKit.box(s.x(43), s.y(59), s.x(57.4), s.y(G.HEIGHT_MM)), sdf: { px, py in
                fmaxk(RasterKit.roundRect(px, py, cx, cy, hw, hh, rr), shellSdf(s, px, py))
            }) { _, _, o in o.r = 0.003; o.g = 0.003; o.b = 0.004; o.a = 1 }
        }
        // Fenster (erhöhter, glasklarer Rahmen um die Wickel)
        do {
            let cx = s.x(50.2), cy = s.y(30.5), hw = s.l(30.6), hh = s.l(12.2), rr = s.l(2.2), wd = s.l(0.45)
            c.fill(RasterKit.box(s.x(19), s.y(17.5), s.x(81.4), s.y(43.6)), sdf: { px, py in
                let outer = RasterKit.roundRect(px, py, cx, cy, hw, hh, rr)
                return fmaxk(outer, -(outer + wd))
            }) { _, py, o in
                let top = py < cy
                o.r = top ? 0.42 : 0.08; o.g = top ? 0.36 : 0.07; o.b = top ? 0.39 : 0.075; o.a = top ? 0.26 : 0.32
            }
        }
        // Kante der Schale: oben/links Licht, unten/rechts Schatten
        let e07 = s.l(0.7)
        c.fill(all, sdf: { px, py in
            let d = shellSdf(s, px, py)
            return fmaxk(d, -(d + e07))
        }) { px, py, o in
            let nx = (px / fw - 0.5), ny = (py / fh - 0.5)
            let light = clampf(-(nx * 0.5 + ny * 0.86), -1, 1)
            let v: Float = 0.07 + 0.24 * (light + 1) / 2
            o.r = v * 1.08; o.g = v * 0.95; o.b = v; o.a = 0.8
        }
        // Glanzreflex der Kunststoffoberfläche (breites, weiches Band von links oben)
        c.fill(all, sdf: { px, py in shellSdf(s, px, py, 0.6) }) { px, py, o in
            let u = (px / fw) * 0.62 + (py / fh) * 0.38
            let band = RasterKit.gauss(u - 0.30, 0.045) * 0.12 + RasterKit.gauss(u - 0.40, 0.010) * 0.10
            o.r = 1; o.g = 0.94; o.b = 0.96; o.a = band
        }
        // Schrauben
        let screws: [(Float, Float)] = [(5.2, 5.0), (95.2, 5.0), (5.2, 58.6), (95.2, 58.6), (50.2, 47.6)]
        for (sx, sy) in screws { screw(c, s, sx, sy, k) }
        // Etikett (Papier mit feiner Struktur, rosé Streifen)
        let lx = s.x(G.LABEL_LEFT), ly = s.y(G.LABEL_TOP), lr = s.x(G.LABEL_RIGHT), lb = s.y(G.LABEL_BOTTOM)
        do {
            let p0 = lin(242), p1 = lin(234), p2 = lin(228)
            let r0 = lin(212), r1 = lin(86), r2 = lin(111)
            let yb = lb - s.l(1.6)
            let yl0 = yb - s.l(0.55), yl1 = yb - s.l(0.3)
            let rad = s.l(0.9)
            c.fill(RasterKit.box(lx, ly, lr, lb), sdf: { px, py in
                RasterKit.roundRect(px, py, (lx + lr) / 2, (ly + lb) / 2, (lr - lx) / 2, (lb - ly) / 2, rad)
            }) { px, py, o in
                let fiber = (RasterKit.hash2(kInt(px * 0.9), kInt(py * 0.35)) - 0.5) * 0.03
                let v = (py - ly) / (lb - ly)
                o.r = p0 * (0.96 + fiber) - 0.02 * v
                o.g = p1 * (0.96 + fiber) - 0.02 * v
                o.b = p2 * (0.96 + fiber) - 0.02 * v
                o.a = 1
                // rosé Streifen unten, darüber feine Linie
                if py > yb {
                    o.r = r0; o.g = r1; o.b = r2
                } else if py > yl0 && py < yl1 {
                    o.r = r0; o.g = r1; o.b = r2
                }
            }
        }
        // Etikettkante: feiner Schatten
        let e18 = s.l(0.18)
        c.fill(RasterKit.box(lx, lb - 1, lr, lb + s.l(0.6)), sdf: { _, py in abs(py - lb - e18) - e18 }) { _, _, o in
            o.r = 0; o.g = 0; o.b = 0; o.a = 0.25
        }
        return c.toRaster()
    }

    private static func screw(_ c: LinearCanvas, _ s: Scale, _ mmX: Float, _ mmY: Float, _ k: Float) {
        let cx = s.x(mmX), cy = s.y(mmY), r = s.l(1.55)
        c.fill(RasterKit.box(cx - r - 2, cy - r - 2, cx + r + 2, cy + r + 2), sdf: { px, py in RasterKit.circle(px, py, cx, cy, r) }) { px, py, o in
            let nx = (px - cx) / r, ny = (py - cy) / r
            let l: Float = 0.45 + 0.55 * clampf(-(nx * 0.55 + ny * 0.83), -1, 1)
            let spec = RasterKit.gauss(nx + 0.35, 0.25) * RasterKit.gauss(ny + 0.45, 0.25) * 0.6
            o.r = 0.30 * l + spec; o.g = 0.29 * l + spec; o.b = 0.30 * l + spec; o.a = 1
        }
        // Kreuzschlitz
        let a = k * 0.85, b = k * 0.18
        c.fill(RasterKit.box(cx - r, cy - r, cx + r, cy + r), sdf: { px, py in
            let dx = abs(px - cx), dy = abs(py - cy)
            return fmink(fmaxk(dx - a, dy - b), fmaxk(dx - b, dy - a))
        }) { _, _, o in o.r = 0.02; o.g = 0.02; o.b = 0.02; o.a = 0.9 }
    }
}
