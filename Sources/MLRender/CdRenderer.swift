import Foundation

/**
 * Maße des „Portable CD“-Players in Millimetern (Draufsicht, Ursprung oben links am Gehäuse) und der
 * Compact Disc nach Norm (IEC 60908: Ø 120 mm, Mittelloch Ø 15 mm, Klemmbereich bis Ø 33 mm, Einlauf ab
 * Ø 46 mm, Programmbereich ab Ø 50 mm, Spiegelschicht bis Ø 117 mm). Reine Rechnung – mit Unit-Tests.
 */
public enum CdGeometry {
    // ---- Compact Disc ------------------------------------------------------------------------
    public static let DISC_RADIUS: Float = 60
    public static let HOLE_RADIUS: Float = 7.5
    /** Durchsichtiger Klemmbereich (ohne Spiegelschicht) bis hier; der Stapelring liegt knapp außerhalb. */
    public static let CLEAR_RADIUS: Float = 16.5
    public static let STACK_RING_RADIUS: Float = 17.1

    /**
     * Bedrucktes Label (Albumcover) als Ring: innen wie bei „hub-printable“ Rohlingen ab Ø 23,5 mm, außen
     * bis Ø 82 mm – rundherum bleibt die spiegelnde Datenfläche sichtbar, innen der klare Ring und das
     * Mittelloch.
     */
    public static let LABEL_INNER: Float = 11.75
    public static let LABEL_OUTER: Float = 41

    /** Ende der Daten (ca. 50 min Musik) – danach glatter Spiegelbereich bis zum klaren Außenrand. */
    public static let DATA_END: Float = 52
    public static let MIRROR_END: Float = 58.5

    /** Teller/Spindel des Laufwerks (dreht sich mit der CD). */
    public static let SPINDLE_CAP: Float = 4.6
    public static let TURNTABLE_RADIUS: Float = 12.6

    // ---- Gerät -------------------------------------------------------------------------------
    public static let BODY_W: Float = 140
    public static let BODY_H: Float = 158
    public static let BODY_RADIUS: Float = 30
    public static let DISC_CX: Float = 70
    public static let DISC_CY: Float = 69
    /** Sichtfenster im Deckel und der rosé polierte Fensterring darum. */
    public static let WINDOW_RADIUS: Float = 63.6
    public static let RING_OUTER: Float = 65.8
    /** Anzeige (LCD) vorn: Mitte, Breite, Höhe. */
    public static let LCD_CX: Float = 70
    public static let LCD_CY: Float = 145.6
    public static let LCD_W: Float = 68
    public static let LCD_H: Float = 14.4
    /** Betriebsleuchte links neben der Anzeige. */
    public static let LED_X: Float = 23.5
    public static let LED_Y: Float = LCD_CY

    /** Rand um das Gehäuse (Schatten, seitlicher Schieber), in mm. */
    public static let MARGIN: Float = 6
    public static let TOTAL_W: Float = BODY_W + 2 * MARGIN
    public static let TOTAL_H: Float = BODY_H + 2 * MARGIN
    public static let ASPECT: Float = TOTAL_W / TOTAL_H

    /** Licht kommt von links oben (Winkel in Bildschirmkoordinaten, y nach unten): −135°. */
    public static let LIGHT_ANGLE: Float = Float(-135.0 * Double.pi / 180.0)

    /**
     * Sichtbare Drehzahl: 36 U/min (216°/s). Ein echtes Laufwerk dreht mit 200–500 U/min – das wäre nur
     * ein Flirren; so bleibt das Cover beim Drehen erkennbar.
     */
    public static let DEGREES_PER_SECOND: Float = 216

    /** Anteil des Labelinnenrands am Labelradius (für den Zuschnitt des Covers). */
    public static let LABEL_HOLE_FRACTION: Float = LABEL_INNER / LABEL_OUTER

    /** Pixel je Millimeter bei einer Gerätegrafik der Breite [widthPx]. */
    public static func pxPerMm(_ widthPx: Int) -> Float { Float(widthPx) / TOTAL_W }

    /** Höhe der Gerätegrafik ([CdRenderer.body]) zu einer Breite. */
    public static func heightFor(_ widthPx: Int) -> Int { Int(kInt(TOTAL_H * pxPerMm(widthPx))) }

    /** Breite der Grafik, die in eine Fläche passt (Seitenverhältnis bleibt). */
    public static func widthToFit(_ maxWidthPx: Int, _ maxHeightPx: Int) -> Int {
        Int(kInt(Swift.min(Float(maxWidthPx), Float(maxHeightPx) * ASPECT)))
    }

    /** Seitenlänge der Ebene [CdRenderer.disc]. */
    public static func discSizePx(_ widthPx: Int) -> Int { Int(kInt(2 * DISC_RADIUS * pxPerMm(widthPx))) + 4 }
    /** Seitenlänge der Ebene [CdRenderer.overlay]. */
    public static func overlaySizePx(_ widthPx: Int) -> Int { Int(kInt(2 * RING_OUTER * pxPerMm(widthPx))) + 4 }
    /** Seitenlänge des Labels (Cover-Ring bzw. [CdRenderer.fallbackLabel]). */
    public static func labelSizePx(_ widthPx: Int) -> Int { Int(kInt(2 * LABEL_OUTER * pxPerMm(widthPx))) }

    /** Mitte der CD in Pixeln der Gerätegrafik. */
    public static func discCenterPx(_ widthPx: Int) -> (x: Float, y: Float) {
        let k = pxPerMm(widthPx)
        return ((DISC_CX + MARGIN) * k, (DISC_CY + MARGIN) * k)
    }
}

/**
 * Anlauf und Auslauf der CD (Drehgeschwindigkeit folgt dem Ziel mit Zeitkonstante). Die Drehung hängt
 * nur vom Wiedergabezustand ab, nie von der Position – Spulen erzeugt deshalb keinen Sprung.
 */
public enum CdSpin {
    /** Anlaufen ≈ 0,4 s; Auslaufen ≈ 1 s (der Motor bremst nicht hart). Zeitkonstanten in s. */
    public static let TAU_UP: Float = 0.14
    public static let TAU_DOWN: Float = 0.32

    /** Ziel-Winkelgeschwindigkeit (°/s): 216 · Tempo (begrenzt auf 0,5…2) bei Wiedergabe, sonst 0. */
    public static func targetSpeed(playing: Bool, speedFactor: Float) -> Float {
        playing ? CdGeometry.DEGREES_PER_SECOND * clampf(speedFactor, 0.5, 2) : 0
    }

    /** Neue Winkelgeschwindigkeit nach [dt] Sekunden. */
    public static func velocity(current: Float, target: Float, dt: Float) -> Float {
        let tau = target > current ? TAU_UP : TAU_DOWN
        let next = current + (target - current) * (1 - kexp(-(dt < 0 ? 0 : dt) / tau))
        return abs(target - next) < 0.5 ? target : next
    }

    /** Neuer Winkel (0…360). */
    public static func angle(current: Float, velocity: Float, dt: Float) -> Float {
        let a = (current + velocity * dt).truncatingRemainder(dividingBy: 360)
        return a < 0 ? a + 360 : a
    }
}

/**
 * Grafikebenen des Players (wie Plattenspieler und Kassette: einmal je Größe berechnet, danach nur
 * gezeichnet bzw. gedreht – keine Berechnung pro Bild):
 *
 *  - [body]: Gehäuse (Graphit, konzentrisch gebürstet), rosé polierter Fensterring, Laufwerksschacht,
 *    Anzeigefenster, Scharnier, Öffnungsschieber, weicher Schatten – statisch.
 *  - [disc]: die CD mit Spindel – dreht sich (das Cover-Label legt die Oberfläche darüber).
 *  - [overlay]: alles, was beim Drehen stillsteht: Lichtreflexe der Spiegelschicht (feiner
 *    Beugungs-Regenbogen nur auf der Datenfläche), Glanz über dem Label und die getönte Deckelscheibe.
 *    Bei konzentrischen Spuren bleiben Reflexe physikalisch richtig an ihrem Platz.
 *  - [fallbackLabel]: neutrales Label für Titel ohne Cover.
 *
 * Ergebnis bitgleich zu `CdRenderer.kt`.
 */
public enum CdRenderer {
    private typealias G = CdGeometry

    private struct Scale {
        let k: Float
        @inline(__always) func x(_ mm: Float) -> Float { (mm + G.MARGIN) * k }
        @inline(__always) func y(_ mm: Float) -> Float { (mm + G.MARGIN) * k }
        @inline(__always) func l(_ mm: Float) -> Float { mm * k }
    }

    @inline(__always)
    private static func bodySdf(_ s: Scale, _ px: Float, _ py: Float, _ inset: Float = 0) -> Float {
        RasterKit.roundRect(px, py, s.x(G.BODY_W / 2), s.y(G.BODY_H / 2), s.l(G.BODY_W / 2 - inset), s.l(G.BODY_H / 2 - inset), s.l(G.BODY_RADIUS - inset))
    }

    private static let TWO_PI_F: Float = 2 * PI_F

    /** Kleinster Winkelabstand (Bogenmaß, 0…π). */
    @inline(__always)
    private static func angDist(_ a: Float, _ b: Float) -> Float {
        // fmod(x, 2π) ist für x < 2π exakt x – den Bibliotheksaufruf nur dann, wenn er etwas ändert.
        var d = abs(a - b)
        if d >= TWO_PI_F { d = d.truncatingRemainder(dividingBy: TWO_PI_F) }
        if d > PI_F { d = TWO_PI_F - d }
        return d
    }

    private static func lin(_ c: Int) -> Float { RasterKit.lin(c) }
    @inline(__always) private static func gauss(_ x: Float, _ sigma: Float) -> Float { RasterKit.gauss(x, sigma) }
    @inline(__always) private static func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float { RasterKit.smoothstep(e0, e1, x) }

    // ---------------------------------------------------------------------------------------------
    // Gehäuse
    // ---------------------------------------------------------------------------------------------

    /** Gehäuse in der Größe `widthPx × CdGeometry.heightFor(widthPx)`. */
    public static func body(_ widthPx: Int) -> RasterImage {
        let k = G.pxPerMm(widthPx)
        let s = Scale(k: k)
        let c = LinearCanvas(width: widthPx, height: G.heightFor(widthPx))
        let all = PixelBox(0, 0, c.width, c.height)
        let fw = Float(c.width), fh = Float(c.height)
        let dcx = s.x(G.DISC_CX), dcy = s.y(G.DISC_CY)

        // weicher Schatten unter dem Gerät
        let so1 = s.l(0.4), so2 = s.l(2.4)
        c.fill(all, sdf: { px, py in bodySdf(s, px - so1, py - so2, 0.6) }) { _, _, o in
            o.r = 0; o.g = 0; o.b = 0; o.a = 0.62
        }
        c.blurAlpha(Swift.max(Int(kInt(s.l(2.6))), 1))

        // Öffnungsschieber (rosé, ragt rechts etwas aus dem Gehäuse)
        do {
            let cx = s.x(G.BODY_W - 0.2), cy = s.y(102), hw = s.l(2.2), hh = s.l(9.2), rr = s.l(1.6)
            let y93 = s.y(93), l18 = s.l(18)
            let r0 = lin(214), r1 = lin(122), r2 = lin(140)
            c.fill(RasterKit.box(s.x(G.BODY_W - 3), s.y(92), s.x(G.BODY_W + 2.2), s.y(112)), sdf: { px, py in
                RasterKit.roundRect(px, py, cx, cy, hw, hh, rr)
            }) { _, py, o in
                let v = (py - y93) / l18
                let l: Float = 0.75 + 0.35 * (1 - v) + 0.25 * gauss(v - 0.25, 0.08)
                o.r = r0 * l; o.g = r1 * l; o.b = r2 * l; o.a = 1
            }
        }

        // Gehäuse: Graphit, konzentrisch gebürstet (um die CD-Mitte), Licht von links oben
        let la = G.LIGHT_ANGLE
        let laOpp = la + PI_F
        c.fill(all, sdf: { px, py in bodySdf(s, px, py) }) { px, py, o in
            let dx = px - dcx, dy = py - dcy
            let r = (dx * dx + dy * dy).squareRoot()
            let ang = katan2(dy, dx)
            // gebürstete Kreise: feine, unregelmäßige Helligkeitsstufen je Radius
            let brushed = (RasterKit.hash(kInt(r * 2.3)) - 0.5) * 0.14 + (RasterKit.hash(kInt(r * 0.6) &+ 77) - 0.5) * 0.06
            // anisotroper Glanz (Bürstung streut quer zur Bürstrichtung → radiale Lichtbahn zum Licht hin)
            let streak = gauss(angDist(ang, la), 0.34) * 0.85 + gauss(angDist(ang, laOpp), 0.30) * 0.30
            let v = py / fh
            let base: Float = 0.019 + 0.012 * (1 - v)
            let l = base * (1 + brushed + streak)
            o.r = l * 1.04; o.g = l * 0.97; o.b = l * 1.02; o.a = 1
        }

        // Kante: Licht oben/links, Schatten unten/rechts
        let e11 = s.l(1.1)
        c.fill(all, sdf: { px, py in
            let d = bodySdf(s, px, py)
            return fmaxk(d, -(d + e11))
        }) { px, py, o in
            let d = -bodySdf(s, px, py) / e11
            let nx = px / fw - 0.5, ny = py / fh - 0.5
            let light = clampf(-(nx * 0.55 + ny * 0.84), -1, 1)
            let v: Float = 0.05 + 0.30 * (light + 1) / 2 * (1 - d)
            o.r = v * 1.05; o.g = v * 0.97; o.b = v; o.a = 0.85
        }

        // Scharnier hinten: zwei eingelassene Gelenkschlitze mit Achse (Lichtkante unten)
        for hx: Float in [40, 100] {
            let cx = s.x(hx), cy = s.y(2.3), hw = s.l(10), hh = s.l(1.15)
            c.fill(RasterKit.box(s.x(hx - 11), s.y(0.6), s.x(hx + 11), s.y(4.2)), sdf: { px, py in
                RasterKit.roundRect(px, py, cx, cy, hw, hh, hh)
            }) { _, py, o in
                let ny = (py - cy) / hh
                let l: Float = 0.006 + 0.07 * smoothstep(0.35, 1, ny) + 0.035 * gauss(ny + 0.1, 0.18)
                o.r = l; o.g = l * 0.97; o.b = l * 0.99; o.a = 1
            }
        }

        // Laufwerksschacht im Fenster: tief, nach außen abgeschattet
        do {
            let wr = s.l(G.WINDOW_RADIUS)
            c.fill(RasterKit.box(dcx - wr - 2, dcy - wr - 2, dcx + wr + 2, dcy + wr + 2), sdf: { px, py in
                RasterKit.circle(px, py, dcx, dcy, wr)
            }) { px, py, o in
                let r = ((px - dcx) * (px - dcx) + (py - dcy) * (py - dcy)).squareRoot() / wr
                let l: Float = 0.010 + 0.010 * (1 - smoothstep(0.80, 1, r))
                o.r = l * 1.05; o.g = l; o.b = l * 1.03; o.a = 1
            }
        }

        // Fensterring: polierte Fase in Rosé-Metall (Licht von links oben)
        do {
            let ro = s.l(G.RING_OUTER), ri = s.l(G.WINDOW_RADIUS - 0.2)
            let wr = s.l(G.WINDOW_RADIUS), span = s.l(G.RING_OUTER - G.WINDOW_RADIUS)
            let laSpec = la + 2.6
            let r0 = lin(206), r1 = lin(128), r2 = lin(142)
            c.fill(RasterKit.box(dcx - ro - 2, dcy - ro - 2, dcx + ro + 2, dcy + ro + 2), sdf: { px, py in
                RasterKit.ring(px, py, dcx, dcy, ri, ro)
            }) { px, py, o in
                let dx = px - dcx, dy = py - dcy
                let r = (dx * dx + dy * dy).squareRoot()
                let t = clampf((r - wr) / span, 0, 1)
                let ang = katan2(dy, dx)
                // Fase neigt sich nach innen: Seite zum Licht hell, gegenüber dunkler
                let facing = kcos(angDist(ang, la)) // 1 = zum Licht
                let l: Float = 0.40 + 0.38 * facing * (1 - t * 0.5)
                let spec = gauss(angDist(ang, la), 0.20) * 0.9 * gauss(t - 0.55, 0.22) + gauss(angDist(ang, laSpec), 0.12) * 0.25
                o.r = r0 * l + spec * 0.95
                o.g = r1 * l + spec * 0.80
                o.b = r2 * l + spec * 0.82
                o.a = 1
            }
        }

        // Anzeigefenster (vertieft) mit Lichtkante unten
        let lcx = s.x(G.LCD_CX), lcy = s.y(G.LCD_CY)
        do {
            let hw = s.l(G.LCD_W / 2 + 0.9), hh = s.l(G.LCD_H / 2 + 0.9), rr = s.l(3.6)
            c.fill(RasterKit.box(lcx - s.l(G.LCD_W / 2 + 1.4), lcy - s.l(G.LCD_H / 2 + 1.4), lcx + s.l(G.LCD_W / 2 + 1.4), lcy + s.l(G.LCD_H / 2 + 1.4)), sdf: { px, py in
                RasterKit.roundRect(px, py, lcx, lcy, hw, hh, rr)
            }) { _, py, o in
                let ny = (py - lcy) / hh
                let l: Float = 0.015 + 0.05 * smoothstep(0.55, 1, ny)
                o.r = l; o.g = l * 0.95; o.b = l * 0.98; o.a = 1
            }
        }
        do {
            let hw = s.l(G.LCD_W / 2), hh = s.l(G.LCD_H / 2), rr = s.l(2.9)
            let g0 = lin(22), g1 = lin(16), g2 = lin(19)
            c.fill(RasterKit.box(lcx - s.l(G.LCD_W / 2 + 1), lcy - s.l(G.LCD_H / 2 + 1), lcx + s.l(G.LCD_W / 2 + 1), lcy + s.l(G.LCD_H / 2 + 1)), sdf: { px, py in
                RasterKit.roundRect(px, py, lcx, lcy, hw, hh, rr)
            }) { _, py, o in
                // dunkles Glas über der Anzeige (die Ziffern zeichnet die Oberfläche)
                let ny = (py - lcy) / hh
                o.r = g0 * (1 - 0.2 * ny); o.g = g1 * (1 - 0.2 * ny); o.b = g2 * (1 - 0.2 * ny); o.a = 1
            }
        }

        // Fassung der Betriebsleuchte
        do {
            let cx = s.x(G.LED_X), cy = s.y(G.LED_Y), rr = s.l(1.9)
            c.fill(RasterKit.box(s.x(G.LED_X - 2.6), s.y(G.LED_Y - 2.6), s.x(G.LED_X + 2.6), s.y(G.LED_Y + 2.6)), sdf: { px, py in
                RasterKit.circle(px, py, cx, cy, rr)
            }) { _, py, o in
                let ny = (py - cy) / rr
                let l: Float = 0.012 + 0.05 * smoothstep(0.3, 1, ny)
                o.r = l; o.g = l; o.b = l; o.a = 1
            }
        }
        // Lautsprechergitter-Andeutung rechts neben der Anzeige: drei feine Schlitze (Kopfhörer-Ausgang)
        for i in 0..<3 {
            let yy = G.LCD_CY - 3.2 + Float(i) * 3.2
            let cx = s.x(115), cy = s.y(yy), hw = s.l(4.6), hh = s.l(0.42)
            c.fill(RasterKit.box(s.x(110), s.y(yy - 1), s.x(120), s.y(yy + 1)), sdf: { px, py in
                RasterKit.roundRect(px, py, cx, cy, hw, hh, hh)
            }) { _, py, o in
                let ny = (py - cy) / hh
                let l: Float = ny > 0.3 ? 0.11 : 0.006
                o.r = l; o.g = l; o.b = l; o.a = 0.95
            }
        }
        return c.toRaster()
    }

    // ---------------------------------------------------------------------------------------------
    // CD (dreht sich)
    // ---------------------------------------------------------------------------------------------

    /** Die CD mit Laufwerksteller und Spindel, quadratisch `discSizePx(widthPx)`, Mitte = Bildmitte. */
    public static func disc(_ widthPx: Int) -> RasterImage {
        let k = G.pxPerMm(widthPx)
        let size = G.discSizePx(widthPx)
        let c = LinearCanvas(width: size, height: size)
        let cx = Float(size) / 2, cy = Float(size) / 2
        let all = PixelBox(0, 0, size, size)
        @inline(__always) func mm(_ px: Float, _ py: Float) -> Float { ((px - cx) * (px - cx) + (py - cy) * (py - cy)).squareRoot() / k }

        // Teller des Laufwerks (unter dem klaren Innenring sichtbar): Graphit, fein abgedreht
        let ttR = G.TURNTABLE_RADIUS * k
        c.fill(all, sdf: { px, py in RasterKit.circle(px, py, cx, cy, ttR) }) { px, py, o in
            let r = mm(px, py)
            let turned = (RasterKit.hash(kInt(r * 9) &+ 5) - 0.5) * 0.012
            let l: Float = 0.020 + 0.012 * smoothstep(G.TURNTABLE_RADIUS, 5, r) + turned
            o.r = l * 1.03; o.g = l; o.b = l * 1.04; o.a = 1
        }

        // CD-Körper (Polycarbonat mit Spiegelschicht) als Ring: Mittelloch bleibt offen
        let holeR = G.HOLE_RADIUS * k, discR = G.DISC_RADIUS * k
        c.fill(all, sdf: { px, py in RasterKit.ring(px, py, cx, cy, holeR, discR) }) { px, py, o in
            let r = mm(px, py)
            if r < G.CLEAR_RADIUS {
                // klarer Innenring: man sieht den dunklen Teller, leicht aufgehellt durch den Kunststoff
                o.r = 0.10; o.g = 0.10; o.b = 0.11; o.a = 0.10
            } else if r < G.MIRROR_END {
                // Spiegelschicht: neutrales Silber; im Datenbereich feine Spurstruktur
                let inData = r >= 23 && r <= G.DATA_END
                let micro: Float = inData
                    ? (RasterKit.hash(kInt(r * 22)) - 0.5) * 0.010 + (RasterKit.hash(kInt(r * 0.9) &+ 31) - 0.5) * 0.018
                    : (RasterKit.hash(kInt(r * 3) &+ 9) - 0.5) * 0.005
                let base: Float = inData ? 0.165 : 0.205
                let l = base * (1 + micro)
                o.r = l * 0.985; o.g = l * 0.995; o.b = l * 1.03; o.a = 1
            } else {
                // klarer Außenrand
                o.r = 0.12; o.g = 0.12; o.b = 0.13; o.a = 0.42
            }
        }
        // Übergänge zwischen Titeln (Pausen zwischen den Spuren erscheinen als feine Ringe)
        for tr: Float in [43.4, 46.9, 48.2, 50.7] {
            let ri = (tr - 0.07) * k, ro = (tr + 0.07) * k
            c.fill(all, sdf: { px, py in RasterKit.ring(px, py, cx, cy, ri, ro) }) { _, _, o in
                o.r = 0.11; o.g = 0.115; o.b = 0.13; o.a = 0.35
            }
        }
        // Ende der Daten: weiche Stufe zum glatten Spiegelbereich
        do {
            let ri = (G.DATA_END - 0.25) * k, ro = (G.DATA_END + 0.15) * k
            c.fill(all, sdf: { px, py in RasterKit.ring(px, py, cx, cy, ri, ro) }) { _, _, o in
                o.r = 0.17; o.g = 0.175; o.b = 0.19; o.a = 0.7
            }
        }
        // Außenkante (präzise, leicht hell) und Kante des Mittellochs
        do {
            let ri = (G.DISC_RADIUS - 0.35) * k
            c.fill(all, sdf: { px, py in RasterKit.ring(px, py, cx, cy, ri, discR) }) { _, _, o in
                o.r = 0.42; o.g = 0.42; o.b = 0.45; o.a = 0.55
            }
            let ro = (G.HOLE_RADIUS + 0.3) * k
            c.fill(all, sdf: { px, py in RasterKit.ring(px, py, cx, cy, holeR, ro) }) { _, _, o in
                o.r = 0.36; o.g = 0.36; o.b = 0.39; o.a = 0.6
            }
        }
        // Stapelring (im klaren Bereich leicht erhaben)
        do {
            let ri = (G.STACK_RING_RADIUS - 0.35) * k, ro = (G.STACK_RING_RADIUS + 0.35) * k
            c.fill(all, sdf: { px, py in RasterKit.ring(px, py, cx, cy, ri, ro) }) { _, _, o in
                o.r = 0.30; o.g = 0.30; o.b = 0.33; o.a = 0.35
            }
        }

        // Spindel: drei Halteklauen am Lochrand, Mittelkappe aus gebürstetem Metall
        for i in 0..<3 {
            let a = Float(i) * 2 * PI_F / 3 + 0.4
            let ca = kcos(a), sa = ksin(a)
            let tx = cx + ca * 6.3 * k, ty = cy + sa * 6.3 * k
            let hw = 1.35 * k, hh = 1.0 * k, rr = 0.6 * k, nk = 1.2 * k
            c.fill(RasterKit.box(tx - 2.2 * k, ty - 2.2 * k, tx + 2.2 * k, ty + 2.2 * k), sdf: { px, py in
                let dx = px - tx, dy = py - ty
                let along = dx * ca + dy * sa, across = -dx * sa + dy * ca
                return RasterKit.roundRect(along, across, 0, 0, hw, hh, rr)
            }) { px, py, o in
                let dx = (px - tx) / nk, dy = (py - ty) / nk
                let l: Float = 0.18 + 0.22 * clampf(-(dx * 0.6 + dy * 0.8), -1, 1)
                o.r = l; o.g = l * 0.98; o.b = l * 1.02; o.a = 1
            }
        }
        do {
            let capR = G.SPINDLE_CAP * k
            let la = G.LIGHT_ANGLE, laOpp = G.LIGHT_ANGLE + PI_F
            c.fill(all, sdf: { px, py in RasterKit.circle(px, py, cx, cy, capR) }) { px, py, o in
                let dx = px - cx, dy = py - cy
                let r = (dx * dx + dy * dy).squareRoot() / capR
                let ang = katan2(dy, dx)
                let brushed = (RasterKit.hash(kInt(r * 60) &+ 3) - 0.5) * 0.05
                let streak = gauss(angDist(ang, la), 0.35) * 0.35 + gauss(angDist(ang, laOpp), 0.35) * 0.18
                let bevel = smoothstep(0.82, 1, r) * 0.35
                let l = (0.30 + streak + brushed) * (1 - bevel)
                o.r = l; o.g = l * 0.99; o.b = l * 1.03; o.a = 1
            }
        }
        // Mittelpunkt (Achse)
        let axR = 0.9 * k
        c.fill(all, sdf: { px, py in RasterKit.circle(px, py, cx, cy, axR) }) { _, _, o in
            o.r = 0.05; o.g = 0.05; o.b = 0.055; o.a = 1
        }
        return c.toRaster()
    }

    // ---------------------------------------------------------------------------------------------
    // Stillstehende Reflexe + Deckelscheibe
    // ---------------------------------------------------------------------------------------------

    /** Stützpunkte der Spektralfarben (linear): violett, blau, cyan, grün, gelb, orange, rot. */
    private static let SPECTRUM: [Float] = [
        0.42, 0.18, 0.80, 0.20, 0.35, 0.95, 0.15, 0.75, 0.90,
        0.30, 0.88, 0.45, 0.95, 0.88, 0.30, 1.00, 0.55, 0.25,
        0.95, 0.30, 0.38,
    ]

    /** Kanal [ch] der Spektralfarbe für t = 0 (Violett) … 1 (Rot). */
    @inline(__always)
    private static func spectrum(_ spec: UnsafePointer<Float>, _ t: Float, _ ch: Int) -> Float {
        let f = clampf(t, 0, 1) * 6
        let i = Swift.min(5, Int(kInt(f)))
        let u = f - Float(i)
        return spec[i * 3 + ch] * (1 - u) + spec[(i + 1) * 3 + ch] * u
    }

    /**
     * Stillstehende Reflexe und Deckelscheibe, quadratisch `overlaySizePx(widthPx)`, Mitte = CD-Mitte.
     */
    public static func overlay(_ widthPx: Int) -> RasterImage {
        let k = G.pxPerMm(widthPx)
        let size = G.overlaySizePx(widthPx)
        let c = LinearCanvas(width: size, height: size)
        let cx = Float(size) / 2, cy = Float(size) / 2
        let all = PixelBox(0, 0, size, size)
        let la = G.LIGHT_ANGLE
        let pi = PI_F
        let laOpp = la + pi
        let specBuf = UnsafeMutablePointer<Float>.allocate(capacity: SPECTRUM.count)
        specBuf.initialize(from: SPECTRUM, count: SPECTRUM.count)
        defer { specBuf.deallocate() }
        let spec = UnsafePointer(specBuf)

        // 1) Spiegelschicht außerhalb des Labels: Umgebungslicht, heller Glanzstreifen zum Licht hin
        //    (radial, wie bei konzentrischen Spuren) und – nur auf der Datenfläche – ein feiner Regenbogen.
        do {
            let ri = G.LABEL_OUTER * k, ro = G.MIRROR_END * k
            c.fill(all, sdf: { px, py in RasterKit.ring(px, py, cx, cy, ri, ro) }) { px, py, o in
                let dx = px - cx, dy = py - cy
                let r = (dx * dx + dy * dy).squareRoot() / k
                let ang = katan2(dy, dx)
                let dA = angDist(ang, la)
                let dB = angDist(ang, laOpp)
                // Umgebung: breite helle Zone zum Licht hin, gegenüber dunkler (Spiegel zeigt den dunklen Deckel)
                let env = gauss(dA, 0.85) * 0.30 + gauss(dB, 0.75) * 0.12
                let shade = clampf(1 - gauss(dA, 1.1) - gauss(dB, 0.9) * 0.6, 0, 1) * 0.22
                var rr = env, gg = env, bb = env * 1.04, aa = env + shade
                // Glanzstreifen: schmaler, heller Kern mit weichem Hof (zum Licht hin kräftig, gegenüber schwächer)
                let streakRadial: Float = 0.55 + 0.45 * gauss(r - 49, 6)
                let streak = (gauss(dA, 0.040) * 0.95 + gauss(dA, 0.12) * 0.32 + gauss(dB, 0.035) * 0.55 + gauss(dB, 0.10) * 0.18) * streakRadial
                // Regenbogen: erste Beugungsordnung seitlich neben dem Streifen (Farbe wandert mit dem Winkel)
                let dataFade = smoothstep(G.LABEL_OUTER + 0.2, G.LABEL_OUTER + 4.5, r) * (1 - smoothstep(G.DATA_END - 4.5, G.DATA_END - 0.2, r))
                // Farbbänder leicht gekrümmt: der Farbton wandert auch mit dem Radius
                let bend = (r - 46) * 0.006
                // Winkel mit Vorzeichen relativ zur Lichtrichtung bzw. zur Gegenseite
                var sA = ang - la
                while sA > pi { sA -= 2 * pi }
                while sA < -pi { sA += 2 * pi }
                var sB = ang - laOpp
                while sB > pi { sB -= 2 * pi }
                while sB < -pi { sB += 2 * pi }
                for side in 0...1 {
                    let signed = side == 0 ? sA : -sB
                    let strength: Float = side == 0 ? 0.50 : 0.32
                    // Band von etwa 0,09 bis 0,47 (Bogenmaß)
                    let t = (signed - 0.09 - bend) / 0.38
                    if t <= 0 || t >= 1 { continue }
                    let w = smoothstep(0, 0.12, t) * (1 - smoothstep(0.85, 1, t)) * strength * dataFade
                    // gedämpft: Richtung Silber gemischt
                    let mix: Float = 0.72
                    rr += (spectrum(spec, t, 0) * mix + 0.5 * (1 - mix)) * w
                    gg += (spectrum(spec, t, 1) * mix + 0.5 * (1 - mix)) * w
                    bb += (spectrum(spec, t, 2) * mix + 0.5 * (1 - mix)) * w
                    aa += w * 0.9
                }
                rr += streak * 0.9; gg += streak * 0.9; bb += streak * 0.95; aa += streak * 0.75
                // Ausblenden zum Rand der Spiegelschicht hin
                let edge = 1 - smoothstep(G.MIRROR_END - 0.6, G.MIRROR_END, r)
                let a = clampf(aa * edge, 0, 0.95)
                if a > 0 {
                    // Farbe so wählen, dass die Summe der Anteile stimmt (vormultipliziert → unvormultipliziert)
                    o.r = clampf(rr * edge / a, 0, 1); o.g = clampf(gg * edge / a, 0, 1); o.b = clampf(bb * edge / a, 0, 1)
                }
                o.a = a
            }
        }

        // 2) Glanz über dem Label (Lackschicht, ohne Regenbogen) – sehr dezent
        do {
            let ri = G.LABEL_INNER * k, ro = G.LABEL_OUTER * k
            c.fill(all, sdf: { px, py in RasterKit.ring(px, py, cx, cy, ri, ro) }) { px, py, o in
                let dx = px - cx, dy = py - cy
                let ang = katan2(dy, dx)
                let r = (dx * dx + dy * dy).squareRoot() / k
                let w = gauss(angDist(ang, la), 0.16) * 0.11 + gauss(angDist(ang, laOpp), 0.13) * 0.04
                let radial = smoothstep(G.LABEL_INNER, G.LABEL_INNER + 4, r) * (1 - smoothstep(G.LABEL_OUTER - 2, G.LABEL_OUTER, r) * 0.5)
                o.r = 1; o.g = 0.98; o.b = 0.98; o.a = w * radial
            }
        }

        // Stapelring (unter dem Druck leicht erhaben) und Druckkante des Labels
        do {
            let ri = (G.STACK_RING_RADIUS - 0.45) * k, ro = (G.STACK_RING_RADIUS + 0.45) * k
            c.fill(all, sdf: { px, py in RasterKit.ring(px, py, cx, cy, ri, ro) }) { px, py, o in
                let ang = katan2(py - cy, px - cx)
                let r = ((px - cx) * (px - cx) + (py - cy) * (py - cy)).squareRoot() / k
                let facing = kcos(angDist(ang, la))
                // innere Hälfte der Wölbung zum Licht hell, äußere dunkel (und umgekehrt auf der Gegenseite)
                let side: Float = r < G.STACK_RING_RADIUS ? 1 : -1
                let v = facing * side
                if v > 0 { o.r = 1; o.g = 1; o.b = 1; o.a = 0.10 * v } else { o.r = 0; o.g = 0; o.b = 0; o.a = -0.14 * v }
            }
        }
        do {
            let ri = (G.LABEL_OUTER - 0.35) * k, ro = G.LABEL_OUTER * k
            c.fill(all, sdf: { px, py in RasterKit.ring(px, py, cx, cy, ri, ro) }) { _, _, o in
                o.r = 0; o.g = 0; o.b = 0; o.a = 0.22
            }
        }
        do {
            let ri = G.LABEL_INNER * k, ro = (G.LABEL_INNER + 0.3) * k
            c.fill(all, sdf: { px, py in RasterKit.ring(px, py, cx, cy, ri, ro) }) { _, _, o in
                o.r = 0; o.g = 0; o.b = 0; o.a = 0.25
            }
        }

        // 3) Glanzlichter am klaren Innenring und an der Außenkante
        do {
            let ri = (G.HOLE_RADIUS - 0.1) * k, ro = G.LABEL_INNER * k
            c.fill(all, sdf: { px, py in RasterKit.ring(px, py, cx, cy, ri, ro) }) { px, py, o in
                let ang = katan2(py - cy, px - cx)
                let w = gauss(angDist(ang, la), 0.22) * 0.22 + gauss(angDist(ang, laOpp), 0.18) * 0.10
                o.r = 0.9; o.g = 0.92; o.b = 1; o.a = w
            }
        }
        do {
            let ri = (G.DISC_RADIUS - 0.7) * k, ro = G.DISC_RADIUS * k
            c.fill(all, sdf: { px, py in RasterKit.ring(px, py, cx, cy, ri, ro) }) { px, py, o in
                let ang = katan2(py - cy, px - cx)
                let w = gauss(angDist(ang, la), 0.30) * 0.75 + gauss(angDist(ang, laOpp), 0.2) * 0.25
                o.r = 1; o.g = 1; o.b = 1; o.a = w
            }
        }

        // 4) Deckelscheibe: getöntes Polycarbonat, breiter weicher Reflex und feine Lichtkante
        do {
            let wr = G.WINDOW_RADIUS * k
            let t0 = lin(60), t1 = lin(52), t2 = lin(58)
            c.fill(all, sdf: { px, py in RasterKit.circle(px, py, cx, cy, wr) }) { px, py, o in
                let u = (px - cx) / wr, v = (py - cy) / wr
                // diagonal von links oben
                let d = (u + v) * 0.7071
                let band = gauss(d + 0.55, 0.16) * 0.085 + gauss(d + 0.18, 0.035) * 0.05
                let tint: Float = 0.07
                let aTot = tint + band
                o.r = (t0 * tint + 1 * band) / aTot
                o.g = (t1 * tint + 0.97 * band) / aTot
                o.b = (t2 * tint + 0.98 * band) / aTot
                o.a = aTot
            }
        }
        // Kante der Scheibe: oben links Licht, unten rechts Schatten (die Scheibe sitzt im Ring)
        do {
            let ri = (G.WINDOW_RADIUS - 0.9) * k, ro = G.WINDOW_RADIUS * k
            c.fill(all, sdf: { px, py in RasterKit.ring(px, py, cx, cy, ri, ro) }) { px, py, o in
                let ang = katan2(py - cy, px - cx)
                let facing = kcos(angDist(ang, la))
                if facing > 0 {
                    o.r = 1; o.g = 0.96; o.b = 0.96; o.a = 0.22 * facing
                } else {
                    o.r = 0; o.g = 0; o.b = 0; o.a = -0.45 * facing
                }
            }
        }
        return c.toRaster()
    }

    // ---------------------------------------------------------------------------------------------
    // Ersatzlabel (ohne Cover): Satin-Silber mit feinen Ringen und rosé Linie – Titel legt die Oberfläche darüber
    // ---------------------------------------------------------------------------------------------

    /** Ersatzlabel als Ring (Innenrand = `LABEL_HOLE_FRACTION` · Radius), Seitenlänge [sizePx]. */
    public static func fallbackLabel(_ sizePx: Int) -> RasterImage {
        let c = LinearCanvas(width: sizePx, height: sizePx)
        let cx = Float(sizePx) / 2, cy = Float(sizePx) / 2
        let rOut = Float(sizePx) / 2
        let rIn = rOut * G.LABEL_HOLE_FRACTION
        let fs = Float(sizePx)
        let all = PixelBox(0, 0, sizePx, sizePx)
        c.fill(all, sdf: { px, py in RasterKit.ring(px, py, cx, cy, rIn, rOut) }) { px, py, o in
            let dx = px - cx, dy = py - cy
            let r = (dx * dx + dy * dy).squareRoot() / rOut
            let v = py / fs
            let grain = (RasterKit.hash2(kInt(px * 0.7), kInt(py * 0.7)) - 0.5) * 0.012
            // warmes Perlgrau, oben etwas heller
            let l: Float = 0.48 + 0.08 * (1 - v) + grain
            o.r = l * 1.02; o.g = l * 0.97; o.b = l * 0.97; o.a = 1
            // feine konzentrische Linien (Siebdruck)
            let lines = abs((r * 60).truncatingRemainder(dividingBy: 1) - 0.5)
            if r > 0.42 && r < 0.86 && lines < 0.06 { o.r *= 0.94; o.g *= 0.94; o.b *= 0.94 }
        }
        // rosé Doppellinie nahe dem Außenrand
        let p0 = lin(212), p1 = lin(86), p2 = lin(111)
        for (rr, w) in [(Float(0.93), Float(0.012)), (Float(0.955), Float(0.004))] {
            let ri = rOut * (rr - w), ro = rOut * (rr + w)
            c.fill(all, sdf: { px, py in RasterKit.ring(px, py, cx, cy, ri, ro) }) { _, _, o in
                o.r = p0; o.g = p1; o.b = p2; o.a = 1
            }
        }
        // innerer Ring (Abschluss zum Klarbereich)
        let ro = rIn + rOut * 0.012
        c.fill(all, sdf: { px, py in RasterKit.ring(px, py, cx, cy, rIn, ro) }) { _, _, o in
            o.r = 0.22; o.g = 0.21; o.b = 0.21; o.a = 0.8
        }
        return c.toRaster()
    }
}
