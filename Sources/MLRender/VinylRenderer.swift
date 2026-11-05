import Foundation

/**
 * Erzeugt die Grafikebenen des Plattenspielers (reine Swift-Logik, ohne Apple-Frameworks). Alle Ebenen
 * werden einmal pro Anzeigegröße berechnet (Hintergrund-Thread) und danach nur noch gezeichnet bzw.
 * gedreht; während der Animation entstehen keine neuen Bilder.
 *
 * Aufteilung nach physikalischem Verhalten:
 *  - [record]: Platte und Tellerrand – drehen sich. Enthält nur, was sich mitdreht (Material,
 *    Rillenstruktur, Auslaufgravur, wenige Staubpartikel).
 *  - [sheen]: Lichtreflexe – stehen still. Weil Rillen konzentrisch sind, bleibt das typische
 *    „Lichtkreuz“ (zwei gegenüberliegende Reflexkeile in Richtung der Lichtquelle) beim Drehen am selben
 *    Ort; deshalb ist eine feststehende Ebene physikalisch richtig.
 *  - [plinth]: Gehäuse, Teller-Schatten, Tonarmsockel, Armstütze, Bedienknöpfe – statisch.
 *  - [tonearm]: Tonarm mit Lager, Gegengewicht, Tonkopf und Tonabnehmer, plus weicher Schatten.
 *  - [fallbackLabel]: Label für Titel ohne Cover.
 *
 * Licht: großes Flächenlicht von links oben; Farben werden linear berechnet und zum Schluss nach sRGB
 * umgerechnet (natürlichere Glanzverläufe). Ergebnis bitgleich zur Android-Fassung (`VinylRenderer.kt`).
 */
public enum VinylRenderer {

    private typealias G = TurntableGeometry

    /** Richtung zur Lichtquelle (Bildschirm, y nach unten): links oben (≈ −129°). */
    static let LIGHT_AZIMUTH: Float = -2.25

    private static let TWO_PI_F: Float = Float(2 * Double.pi)

    // ------------------------------------------------------------------------------------------
    // Hilfsfunktionen
    // ------------------------------------------------------------------------------------------

    /** Kantenglättung: Anteil eines Pixels innerhalb eines Kreises (Abstand in Pixeln). */
    @inline(__always)
    private static func coverage(_ edgeDistancePx: Float) -> Float { clampf(edgeDistancePx + 0.5, 0, 1) }

    @inline(__always)
    private static func angleDiff(_ a: Float, _ b: Float) -> Float {
        var d = a - b
        while Double(d) > Double.pi { d -= TWO_PI_F }
        while Double(d) < -Double.pi { d += TWO_PI_F }
        return d
    }

    /**
     * Radialprofil der Rillen (rotationssymmetrisch, deshalb als Tabelle über den Radius):
     * Wert ≈ 1 = normale Rille; leicht schwankend (Lautstärke/Modulation), Titelpausen = glatt (≈ 0,15),
     * außerhalb des Rillenbereichs 0. Auflösung 4 Werte pro Pixel; abgefragt wird mit Pixelbreite
     * gemittelt (kein Moiré).
     */
    private final class GrooveProfile {
        private let scale: Float = 4
        private let prefix: UnsafeMutablePointer<Float>
        private let maxIndex: Int

        init(_ recordRadiusPx: Float) {
            let n = Int(kInt(recordRadiusPx * scale)) + 8
            maxIndex = n - 1
            var raw = [Float](repeating: 0, count: n)
            let gaps: [Float] = [0.885, 0.79, 0.705, 0.615, 0.535, 0.47]
            for i in 0..<n {
                let r = Float(i) / scale / recordRadiusPx
                if r < G.GROOVE_INNER || r > G.GROOVE_OUTER {
                    raw[i] = 0
                    continue
                }
                // Einzelne Rillenwindungen: ca. 1–1,5 Pixel breit (bei 1000 px Plattendurchmesser)
                let ring = kInt(Float(i) / (scale * 1.15))
                let fine: Float = 0.45 + 1.1 * RasterKit.hash(ring) * RasterKit.hash(ring &+ 50000)
                // Musik-Dynamik: unregelmäßige Abschnitte mit etwas breiteren bzw. schmaleren Rillen
                let section = kInt(r * 140)
                let loud: Float = 0.8 + 0.35 * (RasterKit.hash(section &+ 7000) - 0.5) + 0.12 * ksin(r * 211 + RasterKit.hash(section) * 6)
                var v = fine * loud
                for g in gaps {
                    let d = abs(r - g)
                    if d < 0.0042 { v = 0.12 + v * 0.15 * (d / 0.0042) }
                }
                // Weicher Übergang an Ein- und Auslauf
                v *= RasterKit.smoothstep(G.GROOVE_INNER, G.GROOVE_INNER + 0.006, r) * (1 - RasterKit.smoothstep(G.GROOVE_OUTER - 0.006, G.GROOVE_OUTER, r))
                raw[i] = v
            }
            prefix = .allocate(capacity: n + 1)
            prefix[0] = 0
            for i in 0..<n { prefix[i + 1] = prefix[i] + raw[i] }
        }

        deinit { prefix.deallocate() }

        /** Mittelwert über [rPx − 0.5, rPx + 0.5] Pixel. */
        @inline(__always)
        func at(_ rPx: Float) -> Float {
            let a = Swift.min(Swift.max(kIdx((rPx - 0.5) * scale), 0), maxIndex)
            let b = Swift.min(Swift.max(kIdx((rPx + 0.5) * scale), a + 1), maxIndex + 1)
            return (prefix[b] - prefix[a]) / Float(b - a)
        }
    }

    // ------------------------------------------------------------------------------------------
    // Platte (dreht sich)
    // ------------------------------------------------------------------------------------------

    /**
     * Platte mit Tellerrand, quadratisch, Mittelpunkt in der Bildmitte. Seitenlänge [size] entspricht
     * dem Durchmesser des Plattentellers (App: `recordSizePx(S)`).
     */
    public static func record(_ size: Int) -> RasterImage {
        var out = RasterImage(width: size, height: size)
        let c = Float(size) / 2
        let platterR = Float(size) / 2
        let recordR = platterR / G.PLATTER_FACTOR
        let profile = GrooveProfile(recordR)
        let dust = Dust(recordR)
        let lut = RasterKit.lut
        out.pixels.withUnsafeMutableBufferPointer { buf in
            let px = buf.baseAddress!
            parallelFor(size) { y in
                let dy = Float(y) + 0.5 - c
                for x in 0..<size {
                    let dx = Float(x) + 0.5 - c
                    let d = (dx * dx + dy * dy).squareRoot()
                    let a = coverage(platterR - d)
                    if a <= 0 {
                        px[y * size + x] = 0
                        continue
                    }
                    let r = d / recordR
                    var lr: Float
                    var lg: Float
                    var lb: Float
                    if r >= 1.0 {
                        // Tellerrand: gebürstetes Aluminium (Struktur nur radial → dreht unsichtbar mit)
                        let brushed: Float = 0.85 + 0.3 * RasterKit.hash(kInt(d * 3) &+ 9000)
                        let inGap: Float = 1 - RasterKit.smoothstep(1.0, 1.006, r) // Schattenfuge zwischen Platte und Teller
                        let base: Float = 0.075 * brushed * (1 - 0.85 * inGap)
                        lr = base; lg = base * 1.01; lb = base * 1.04
                    } else {
                        // Vinyl: tiefschwarz, leicht warm; Rillen minimal heller als glatte Bereiche
                        let groove = profile.at(d)
                        var v: Float = 0.0075 + 0.0042 * groove
                        if r > 0.978 {
                            // Wulst am Rand
                            v = 0.011
                        } else if r >= 0.955 && r <= 0.978 {
                            v = 0.0068 // glatte Einlaufzone
                        } else if r < G.GROOVE_INNER && r > G.LABEL_FACTOR {
                            v = 0.0062 // glatte Auslaufzone
                            // Auslaufrille (Endlosrille) als feiner Ring
                            if abs(r - 0.36) < 0.0016 { v = 0.012 }
                            // Erhöhter Ring am Label
                            if r < G.LABEL_FACTOR + 0.012 { v = 0.0095 }
                        } else if r <= G.LABEL_FACTOR {
                            v = 0.018 // unter dem Cover (wird überdeckt)
                        }
                        lr = v * 1.02; lg = v; lb = v * 1.03
                        // Gravur in der Auslaufzone (Matrixnummer) – asymmetrisch, macht die Drehung sichtbar.
                        if r > 0.365 && r < 0.395 {
                            let e = etching(dx / recordR, dy / recordR)
                            if e > 0 {
                                lr += 0.011 * e; lg += 0.011 * e; lb += 0.012 * e
                            }
                        }
                        // Wenige Staubpartikel
                        let s = dust.at(dx, dy)
                        if s > 0 {
                            lr += 0.10 * s; lg += 0.10 * s; lb += 0.10 * s
                        }
                    }
                    px[y * size + x] = RasterKit.argb(lut, a, lr, lg, lb)
                }
            }
        }
        return out
    }

    /** Eingravierte Zeichen der Auslaufzone (stilisierte, handgeritzte Striche). */
    @inline(__always)
    private static func etching(_ nx: Float, _ ny: Float) -> Float {
        let r = (nx * nx + ny * ny).squareRoot()
        let theta = katan2(ny, nx)
        // Bereich von etwa 20° bis 75° (rechts unten)
        let start: Float = 0.35
        let end: Float = 1.3
        if theta < start || theta > end { return 0 }
        // Zeichen: kurze Striche entlang des Bogens
        let u = (theta - start) / (end - start) * 14 // Zeichenposition
        let cell = kInt(kfloor(u))
        let fu = u - Float(cell)
        if cell % 4 == 3 { return 0 } // Leerzeichen
        let v = (r - 0.368) / 0.024 // 0..1 Zeichenhöhe
        if v < 0 || v > 1 { return 0 }
        let h = RasterKit.hash(cell &+ 77)
        // senkrechter Strich, schräger Strich oder Bogen – je nach Zeichen
        let stroke: Bool
        if h < 0.33 {
            stroke = abs(fu - 0.5) < 0.09
        } else if h < 0.66 {
            stroke = abs(fu - (0.2 + 0.6 * v)) < 0.08
        } else {
            stroke = abs(fu - 0.5 - 0.3 * ksin(v * 3.1)) < 0.08 || (v > 0.85 && fu > 0.2 && fu < 0.8)
        }
        return stroke ? 0.7 + 0.3 * RasterKit.hash2(kInt(fu * 40), kInt(v * 40)) : 0
    }

    /** Sieben Staubpartikel (x, y, Radius in px relativ zur Plattenmitte). */
    private final class Dust {
        /** je Partikel x, y, r – fester Puffer (keine Array-Zugriffe in der Pixelschleife). */
        private let v: UnsafeMutablePointer<Float>

        init(_ recordR: Float) {
            v = .allocate(capacity: 21)
            for i in 0..<7 {
                let k = Int32(i)
                let rr: Float = 0.45 + 0.45 * RasterKit.hash(k * 3 + 1)
                // (hash · 2 · PI).toFloat(): Float · Int, dann · Double
                let t = Float(Double(RasterKit.hash(k * 3 + 2) * 2) * Double.pi)
                v[i * 3] = kcos(t) * rr * recordR
                v[i * 3 + 1] = ksin(t) * rr * recordR
                v[i * 3 + 2] = fmaxk(0.6, recordR * (0.0015 + 0.0015 * RasterKit.hash(k * 3 + 3)))
            }
        }

        deinit { v.deallocate() }

        @inline(__always)
        func at(_ dx: Float, _ dy: Float) -> Float {
            var best: Float = 0
            for i in 0..<7 {
                let ex = dx - v[i * 3]
                let ey = dy - v[i * 3 + 1]
                let dd = ex * ex + ey * ey
                let rr = v[i * 3 + 2] * v[i * 3 + 2]
                if dd < rr * 4 { best = fmaxk(best, kexp(-dd / rr)) }
            }
            return best
        }
    }

    // ------------------------------------------------------------------------------------------
    // Reflexe (stehen still)
    // ------------------------------------------------------------------------------------------

    /**
     * Feststehende Lichtreflexe über Platte und Teller (gleiche Größe wie [record]).
     * Enthält auch Glanz und Kantenschatten des Labels sowie die Spindel.
     */
    public static func sheen(_ size: Int) -> RasterImage {
        var out = RasterImage(width: size, height: size)
        let c = Float(size) / 2
        let platterR = Float(size) / 2
        let recordR = platterR / G.PLATTER_FACTOR
        let profile = GrooveProfile(recordR)
        let lightA = LIGHT_AZIMUTH
        let oppositeA = lightA + PI_F
        // Weiches Flächenlicht als Spiegelung (glatte Bereiche): Position links oben auf der Platte.
        let sbx = kcos(lightA) * 0.58
        let sby = ksin(lightA) * 0.58
        // Rosé-Schimmer der zweiten (schwächeren) Reflexion – sehr dezent.
        let roseR: Float = 1.0
        let roseG: Float = 0.62
        let roseB: Float = 0.70
        let LF = G.LABEL_FACTOR
        let lut = RasterKit.lut
        out.pixels.withUnsafeMutableBufferPointer { buf in
            let px = buf.baseAddress!
            parallelFor(size) { y in
                let dy = Float(y) + 0.5 - c
                for x in 0..<size {
                    let dx = Float(x) + 0.5 - c
                    let d = (dx * dx + dy * dy).squareRoot()
                    let a = coverage(platterR - d)
                    if a <= 0 {
                        px[y * size + x] = 0
                        continue
                    }
                    let r = d / recordR
                    let theta = katan2(dy, dx)
                    let d1 = angleDiff(theta, lightA)
                    let d2 = angleDiff(theta, oppositeA)
                    // Summen: Aufhellung (weiß/rosé, linear) und Abdunklung
                    var hr: Float = 0
                    var hg: Float = 0
                    var hb: Float = 0
                    var dark: Float = 0
                    if r >= 1.0 {
                        // Tellerrand: anisotroper Metallglanz + Kantenlicht
                        let lobe = kexp(-(d1 * d1) / (0.30 * 0.30)) + 0.7 * kexp(-(d2 * d2) / (0.26 * 0.26))
                        let rim = RasterKit.smoothstep(1.006, 1.012, r)
                        let v = (0.22 * lobe + 0.025) * rim
                        hr += v; hg += v; hb += v * 1.02
                        // Außenkante: oben links Licht, unten rechts Schatten
                        let edge = kexp(-((r - 1.03) * (r - 1.03)) / (0.004 * 0.004))
                        let facing = kcos(d1)
                        if facing > 0 {
                            hr += 0.35 * edge * facing; hg += 0.35 * edge * facing; hb += 0.35 * edge * facing
                        } else {
                            dark += 0.5 * edge * -facing
                        }
                        // Schattenfuge
                        dark += 0.6 * (1 - RasterKit.smoothstep(1.0, 1.007, r))
                    } else if r > LF {
                        let groove = profile.at(d)
                        // 1) Lichtkreuz (anisotrope Reflexion der Rillen), Hauptseite zur Lampe hin
                        let w1: Float = 0.085 + 0.07 * r
                        let w2: Float = 0.075 + 0.06 * r
                        let env1 = RasterKit.smoothstep(0.38, 0.58, r) * (1 - 0.35 * RasterKit.smoothstep(0.8, 1.0, r))
                        let env2 = RasterKit.smoothstep(0.40, 0.66, r) * (1 - 0.25 * RasterKit.smoothstep(0.85, 1.0, r))
                        let l1 = kexp(-(d1 * d1) / (w1 * w1)) * env1
                        let l2 = kexp(-(d2 * d2) / (w2 * w2)) * env2
                        // breiter, schwacher Lichthof um den Reflexkeil (ausgedehnte Lichtquelle)
                        let halo = kexp(-(d1 * d1) / (0.55 * 0.55)) * env1
                        let main = (0.50 * l1 + 0.045 * halo) * groove
                        let second = 0.20 * l2 * groove
                        hr += main + second * roseR
                        hg += main + second * roseG
                        hb += main * 1.02 + second * roseB
                        // 2) Feine Rillen überall leicht sichtbar (Umgebungslicht)
                        let ambient = 0.012 * groove * (0.6 + 0.4 * kcos(d1))
                        hr += ambient; hg += ambient; hb += ambient
                        // 3) Glatte Zonen (Ein-/Auslauf, Wulst): weiche Spiegelung des Flächenlichts
                        let smooth: Float
                        if r > 0.955 {
                            smooth = 1
                        } else if r < G.GROOVE_INNER {
                            smooth = 1
                        } else {
                            let ng = 1 - groove
                            smooth = 0.25 * (ng < 0 ? 0 : ng)
                        }
                        if smooth > 0 {
                            let ex = dx / recordR - sbx
                            let ey = dy / recordR - sby
                            let soft = kexp(-(ex * ex + ey * ey) / (0.20 * 0.20))
                            let v = 0.16 * soft * smooth
                            hr += v; hg += v; hb += v
                        }
                        // 4) Wulst am Rand: Licht oben links, Schatten unten rechts
                        let bead = kexp(-((r - 0.99) * (r - 0.99)) / (0.0075 * 0.0075))
                        let facing = kcos(d1)
                        if facing > 0 {
                            let v = 0.30 * bead * facing * facing
                            hr += v; hg += v; hb += v
                        } else {
                            dark += 0.35 * bead * facing * facing
                        }
                        // 5) Kante des Labels (leicht erhabener Ring)
                        let lrd = r - LF - 0.006
                        let labelRing = kexp(-(lrd * lrd) / (0.003 * 0.003))
                        if facing > 0 {
                            let v = 0.10 * labelRing * facing
                            hr += v; hg += v; hb += v
                        }
                        // 6) Großer, sehr weicher Glanz über die ganze Oberfläche (Lack-Optik)
                        let gx = dx / recordR + 0.35
                        let gy = dy / recordR + 0.42
                        let gloss = 0.022 * kexp(-(gx * gx + gy * gy) / 0.35)
                        hr += gloss; hg += gloss; hb += gloss
                    } else {
                        // Label: halbmatter Druck – sanfter Glanz von links oben, Rand leicht abgedunkelt
                        let lx = dx / recordR + 0.12
                        let ly = dy / recordR + 0.14
                        let g = 0.07 * kexp(-(lx * lx + ly * ly) / 0.05)
                        hr += g; hg += g; hb += g
                        let edge = RasterKit.smoothstep(LF - 0.03, LF, r)
                        dark += 0.28 * edge
                        // Spindel: Loch mit Metallstift
                        let hole: Float = 0.024
                        let pin: Float = 0.0165
                        if r < hole {
                            dark = fmaxk(dark, 0.85 * RasterKit.smoothstep(hole, hole - 0.004, r))
                            if r < pin {
                                // Kuppelförmiger Stift: Glanzpunkt oben links
                                let nx = dx / (pin * recordR)
                                let ny = dy / (pin * recordR)
                                let spec = kexp(-((nx + 0.35) * (nx + 0.35) + (ny + 0.4) * (ny + 0.4)) / 0.12)
                                let body = 0.32 * (1 - 0.5 * (nx * nx + ny * ny))
                                let v = body + 0.9 * spec
                                let ca = coverage((pin - r) * recordR)
                                px[y * size + x] = RasterKit.argb(lut, ca * a + (1 - ca) * 0.85, v * ca, v * ca, v * 1.03 * ca)
                                continue
                            }
                        }
                    }
                    // Kombinieren: Ergebnis = Farbe mit Deckkraft, die über das Bild darunter gelegt wird.
                    let ah = clampf(fmaxk(hr, fmaxk(hg, hb)), 0, 1)
                    let total = 1 - (1 - ah) * (1 - clampf(dark, 0, 1))
                    if total <= 0.0005 {
                        px[y * size + x] = 0
                        continue
                    }
                    let k: Float = ah > 0 ? 1 / ah : 0
                    let share = ah / total
                    px[y * size + x] = RasterKit.argb(lut, total * a, hr * k * share, hg * k * share, hb * k * share)
                }
            }
        }
        return out
    }

    // ------------------------------------------------------------------------------------------
    // Gehäuse (statisch)
    // ------------------------------------------------------------------------------------------

    /**
     * Gehäuse in Anthrazit/Schwarz (gebürstet), mit abgerundeten Ecken, Fase, Teller-Schatten,
     * Tonarmsockel, Armstütze und zwei Bedienknöpfen. Quadratisch, Seitenlänge [size] = S.
     */
    public static func plinth(_ size: Int) -> RasterImage {
        var out = RasterImage(width: size, height: size)
        let s = Float(size)
        let corner: Float = 0.07 * s
        let cx = G.CENTER_X * s
        let cy = G.CENTER_Y * s
        let platterR = G.RECORD_RADIUS * G.PLATTER_FACTOR * s
        let pivotX = G.PIVOT_X * s
        let pivotY = G.PIVOT_Y * s
        let baseR: Float = 0.078 * s
        let restA = G.REST_ANGLE_DEG * PI_F / 180
        let postX = pivotX + kcos(restA) * G.REST_POST_DISTANCE * s
        let postY = pivotY + ksin(restA) * G.REST_POST_DISTANCE * s
        let postR: Float = 0.017 * s
        let b = G.SPEED_BUTTONS
        let btnX0 = b[0], btnY0 = b[1], btnX1 = b[2], btnY1 = b[3]
        let btnR = G.SPEED_BUTTON_RADIUS * s
        let half = s / 2
        let lightOpp = LIGHT_AZIMUTH + PI_F
        let lut = RasterKit.lut
        out.pixels.withUnsafeMutableBufferPointer { buf in
            let px = buf.baseAddress!
            parallelFor(size) { y in
                let fy = Float(y) + 0.5
                for x in 0..<size {
                    let fx = Float(x) + 0.5
                    // Abgerundetes Rechteck (Abstand zum Rand, negativ = innen)
                    let qx = fmaxk(abs(fx - half) - (half - corner), 0)
                    let qy = fmaxk(abs(fy - half) - (half - corner), 0)
                    let outside = (qx * qx + qy * qy).squareRoot() - corner
                    let a = coverage(-outside)
                    if a <= 0 {
                        px[y * size + x] = 0
                        continue
                    }
                    // Abstand zur Kante (innen positiv) für die Fase
                    let inner = -outside
                    // Grundton: Anthrazit, oben etwas heller, feine waagerechte Bürstung
                    let vert = 1 - fy / s
                    let brush: Float = 0.92 + 0.16 * RasterKit.hash(kInt(fy * 2.3)) * (0.6 + 0.4 * RasterKit.hash2(kInt(fx / 37), kInt(fy * 2.3)))
                    var v: Float = (0.016 + 0.012 * vert) * brush
                    // leichte Vignette
                    let vx = fx / s - 0.45
                    let vy = fy / s - 0.5
                    v *= 1 - 0.35 * (vx * vx + vy * vy)
                    var lr = v * 1.02
                    var lg = v
                    var lb = v * 1.04
                    // Fase: Lichtkante oben/links, dunkle Kante unten/rechts
                    let bevel: Float = 0.012 * s
                    if inner < bevel {
                        let t = 1 - inner / bevel
                        let nx: Float = fx < s / 2 ? -1 : 1
                        let ny: Float = fy < s / 2 ? -1 : 1
                        // Lichtrichtung links oben: oben/links hell
                        let lit = ((qy > 0 || abs(fy - half) > abs(fx - half)) ? -ny : -nx) * 0.5 + 0.5
                        let hl = 0.11 * t * t * lit
                        lr += hl; lg += hl; lb += hl
                        let sh = 0.6 * t * (1 - lit)
                        lr *= 1 - sh; lg *= 1 - sh; lb *= 1 - sh
                    }
                    // Schatten des Plattentellers (nach rechts unten versetzt)
                    let sdx = fx - cx - 0.010 * s
                    let sdy = fy - cy - 0.014 * s
                    let sd = (sdx * sdx + sdy * sdy).squareRoot() - platterR
                    if sd > -0.05 * s {
                        let shadow = kexp(-fmaxk(sd, 0) / (0.022 * s)) * 0.75
                        lr *= 1 - shadow; lg *= 1 - shadow; lb *= 1 - shadow
                    }
                    // Mulde/Ring um den Teller (feiner dunkler Spalt)
                    let ring = ((fx - cx) * (fx - cx) + (fy - cy) * (fy - cy)).squareRoot() - platterR
                    if ring > 0 && ring < 0.006 * s {
                        let k = 1 - ring / (0.006 * s)
                        lr *= 1 - 0.5 * k; lg *= 1 - 0.5 * k; lb *= 1 - 0.5 * k
                    }
                    // Tonarmsockel: gedrehte Metallscheibe mit konzentrischen Bearbeitungsspuren
                    let bdx = fx - pivotX
                    let bdy = fy - pivotY
                    let bd = (bdx * bdx + bdy * bdy).squareRoot()
                    // Schatten des Sockels
                    let bsx = bdx - 0.008 * s, bsy = bdy - 0.011 * s
                    let bsd = (bsx * bsx + bsy * bsy).squareRoot() - baseR
                    if bsd > 0 && bsd < 0.04 * s {
                        let sh = 0.6 * kexp(-bsd / (0.012 * s))
                        lr *= 1 - sh; lg *= 1 - sh; lb *= 1 - sh
                    }
                    let baseA = coverage(baseR - bd)
                    if baseA > 0 {
                        let rr = bd / baseR
                        let th = katan2(bdy, bdx)
                        let turned: Float = 0.85 + 0.3 * RasterKit.hash(kInt(bd * 2.5) &+ 5000)
                        let dl = angleDiff(th, LIGHT_AZIMUTH)
                        let dl2 = angleDiff(th, lightOpp)
                        let aniso = 0.16 * (kexp(-(dl * dl) / 0.12) + 0.6 * kexp(-(dl2 * dl2) / 0.1)) * turned
                        var m = 0.045 * turned + aniso
                        // Fase am Rand
                        if rr > 0.9 {
                            let f = kcos(dl)
                            m += f > 0 ? 0.25 * f * RasterKit.smoothstep(0.9, 0.98, rr) : -0.03
                        }
                        // Vertiefung in der Mitte (Lagerschacht)
                        if rr < 0.62 { m *= 0.45 }
                        if m < 0.004 { m = 0.004 }
                        lr = lr * (1 - baseA) + m * baseA
                        lg = lg * (1 - baseA) + m * baseA
                        lb = lb * (1 - baseA) + m * 1.03 * baseA
                    }
                    // Armstütze (kleiner Pfosten mit Gummiauflage) + Schatten
                    let pdx = fx - postX
                    let pdy = fy - postY
                    let psx = pdx - 0.007 * s, psy = pdy - 0.010 * s
                    let psd = (psx * psx + psy * psy).squareRoot() - postR
                    if psd > 0 && psd < 0.03 * s {
                        let sh = 0.55 * kexp(-psd / (0.008 * s))
                        lr *= 1 - sh; lg *= 1 - sh; lb *= 1 - sh
                    }
                    let pd = (pdx * pdx + pdy * pdy).squareRoot()
                    let postA = coverage(postR - pd)
                    if postA > 0 {
                        let nx = pdx / postR
                        let ny = pdy / postR
                        let spec = kexp(-((nx + 0.4) * (nx + 0.4) + (ny + 0.45) * (ny + 0.45)) / 0.18)
                        var m = 0.05 + 0.35 * spec
                        // Gummiauflage (mattschwarz) in der Mitte
                        if abs(nx) < 0.75 && pd < postR * 0.8 { m = 0.012 + 0.02 * spec }
                        lr = lr * (1 - postA) + m * postA
                        lg = lg * (1 - postA) + m * postA
                        lb = lb * (1 - postA) + m * postA
                    }
                    // Bedienknöpfe 33/45
                    for i in 0..<2 {
                        let kx = fx - (i == 0 ? btnX0 : btnX1) * s
                        let ky = fy - (i == 0 ? btnY0 : btnY1) * s
                        let kd = (kx * kx + ky * ky).squareRoot()
                        // Ring-Aussparung
                        let ringD = kd - btnR * 1.22
                        if ringD < 0 && kd > btnR {
                            lr *= 0.55; lg *= 0.55; lb *= 0.55
                        }
                        let ka = coverage(btnR - kd)
                        if ka > 0 {
                            let nx = kx / btnR
                            let ny = ky / btnR
                            let turned: Float = 0.9 + 0.2 * RasterKit.hash(kInt(kd * 3) &+ Int32(300 * i))
                            let spec = kexp(-((nx + 0.45) * (nx + 0.45) + (ny + 0.5) * (ny + 0.5)) / 0.25)
                            let m = (0.06 + 0.30 * spec) * turned
                            lr = lr * (1 - ka) + m * ka
                            lg = lg * (1 - ka) + m * ka
                            lb = lb * (1 - ka) + m * 1.02 * ka
                        }
                    }
                    // Feinkörnung gegen Farbstufen
                    let grain = (RasterKit.hash2(Int32(x), Int32(y)) - 0.5) * 0.0016
                    px[y * size + x] = RasterKit.argb(lut, a, lr + grain, lg + grain, lb + grain)
                }
            }
        }
        return out
    }

    // ------------------------------------------------------------------------------------------
    // Tonarm
    // ------------------------------------------------------------------------------------------

    /** Schichtweises Überlagern (wie die lokale Funktion `layer` im Original). */
    private struct ArmLayers {
        var cov: Float = 0
        var r: Float = 0
        var g: Float = 0
        var b: Float = 0

        @inline(__always)
        mutating func layer(_ c: Float, _ lr: Float, _ lg: Float, _ lb: Float) {
            if c <= 0 { return }
            r = r * (1 - c) + lr * c
            g = g * (1 - c) + lg * c
            b = b * (1 - c) + lb * c
            cov = cov + c * (1 - cov)
        }
    }

    /**
     * Tonarm in Grundstellung (Rohr zeigt nach rechts, Drehpunkt links). [s] = Kantenlänge der
     * Plattenspieler-Fläche in Pixeln. Die Beleuchtung ist für die typische Spielposition berechnet.
     * Bildgröße: `Int((ARM_BACK + ARM_FRONT) · s) + 2` × `Int(2 · ARM_HALF_HEIGHT · s) + 2`.
     */
    public static func tonearm(_ s: Int) -> ArmRaster {
        let sf = Float(s)
        let w = Int(kInt((G.ARM_BACK + G.ARM_FRONT) * sf)) + 2
        let h = Int(kInt(2 * G.ARM_HALF_HEIGHT * sf)) + 2
        let pivotX = G.ARM_BACK * sf
        let pivotY = Float(h) / 2
        var arm = RasterImage(width: w, height: h)
        let alphaMask = UnsafeMutablePointer<Float>.allocate(capacity: w * h)
        alphaMask.initialize(repeating: 0, count: w * h)
        defer { alphaMask.deallocate() }
        // Beleuchtung im Armkoordinatensystem: Arm steht beim Spielen bei etwa 125° → Licht entsprechend drehen.
        let playAngle = G.armAngleForProgress(0.4) * PI_F / 180
        let lightScreen = LIGHT_AZIMUTH
        let lightLocal = lightScreen - playAngle
        let lightLocalOpp = lightLocal + PI_F
        let lx = kcos(lightLocal)
        let ly = ksin(lightLocal)
        let bend = G.bendRad
        let cb = kcos(bend)
        let sb = ksin(bend)
        let tubeEnd = G.TUBE_LENGTH * sf
        let tubeR0: Float = 0.0115 * sf
        let tubeR1: Float = 0.0095 * sf
        let cwStart: Float = -0.168 * sf
        let cwEnd: Float = -0.080 * sf
        let cwR: Float = 0.036 * sf
        let shaftR: Float = 0.0095 * sf
        let gimbalR: Float = 0.045 * sf
        // Maße von Tonabnehmer, Tonkopf und Fingerlift (im Original je Pixel berechnet – gleiche Werte)
        let cartX0: Float = 0.030 * sf, cartX1: Float = 0.093 * sf, cartHalf: Float = 0.0155 * sf, cartR: Float = 0.004 * sf
        let shellX0: Float = -0.010 * sf, shellX1: Float = 0.080 * sf
        let halfBack: Float = 0.012 * sf, halfFront: Float = 0.022 * sf, shellR: Float = 0.006 * sf
        let screw0: Float = 0.040 * sf, screw1: Float = 0.058 * sf
        let screwRx: Float = 0.006 * sf, screwRy: Float = 0.0025 * sf
        let facetW: Float = 0.0018 * sf, frontEdge: Float = 0.0025 * sf
        let liftX: Float = 0.052 * sf, liftLen: Float = 0.030 * sf
        let liftA: Float = -0.021 * sf, liftB: Float = 0.011 * sf
        let liftW: Float = 0.0021 * sf, liftOff: Float = 0.001 * sf
        let liftSigma: Float = 0.0012 * sf * 0.0012 * sf
        let knurlStep: Float = 0.0045 * sf, endRingW: Float = 0.008 * sf
        let gimbalIn: Float = 0.55 * gimbalR
        let lut = RasterKit.lut
        arm.pixels.withUnsafeMutableBufferPointer { buf in
            let out = buf.baseAddress!
            parallelFor(h) { y in
                let fy = Float(y) + 0.5 - pivotY
                for x in 0..<w {
                    let fx = Float(x) + 0.5 - pivotX
                    var L = ArmLayers()
                    // --- Gegengewicht (Zylinder quer gesehen: Rechteck mit Zylinderschattierung) ---
                    if fx >= cwStart - 1 && fx <= cwEnd + 1 {
                        let edge = fmink(fx - cwStart, cwEnd - fx)
                        let c = coverage(fmink(edge, cwR - abs(fy)))
                        if c > 0 {
                            let t = clampf(fy / cwR, -1, 1)
                            let shade = cylinder(t, lx, ly, metal: false)
                            // Rändelung: feine Rillen quer
                            let knurl: Float = kInt((fx - cwStart) / knurlStep) % 2 == 0 ? 0.85 : 1
                            let endRing: Float = edge < endRingW ? 2.2 : 1 // silberne Ringe an den Enden
                            let v = shade * knurl * endRing
                            L.layer(c, v * 0.9, v * 0.9, v)
                        }
                    }
                    // --- Welle zum Lager ---
                    if fx >= cwEnd - 1 && fx <= 0 {
                        let c = coverage(fmink(shaftR - abs(fy), -fx + 1))
                        if c > 0 {
                            let v = cylinder(clampf(fy / shaftR, -1, 1), lx, ly, metal: true)
                            L.layer(c, v, v, v * 1.02)
                        }
                    }
                    // --- Rohr (leicht verjüngt) ---
                    if fx >= -1 && fx <= tubeEnd + 1 {
                        let tr = tubeR0 + (tubeR1 - tubeR0) * clampf(fx / tubeEnd, 0, 1)
                        let c = coverage(fmink(tr - abs(fy), tubeEnd - fx)) * coverage(fx + 1)
                        if c > 0 {
                            let v = cylinder(clampf(fy / tr, -1, 1), lx, ly, metal: true)
                            // feine Längsbürstung
                            let brushed: Float = 0.96 + 0.06 * RasterKit.hash(kInt(fy * 7) &+ 1234)
                            L.layer(c, v * brushed, v * brushed, v * brushed * 1.02)
                        }
                    }
                    // --- Tonkopf (abgewinkelt) mit Tonabnehmer und Fingerlift ---
                    let hx = (fx - tubeEnd) * cb + fy * sb // entlang des Tonkopfs
                    let hy = -(fx - tubeEnd) * sb + fy * cb
                    // Tonabnehmer (unter dem Tonkopf, vorn sichtbar): Rosé eloxiert
                    do {
                        let c = roundedRect(hx, hy, cartX0, cartX1, cartHalf, cartR)
                        if c > 0 {
                            let t = clampf(hy / cartHalf, -1, 1)
                            let base = cylinderFlat(t, lx, ly)
                            // Rosé eloxiert, leicht metallisch (einziges farbiges Detail des Plattenspielers)
                            L.layer(c, 0.26 * base + 0.015, 0.055 * base + 0.006, 0.085 * base + 0.008)
                        }
                    }
                    // Tonkopf-Platte (Graphit, gebürstet)
                    do {
                        let half = halfBack + (halfFront - halfBack) * clampf((hx - shellX0) / (shellX1 - shellX0), 0, 1)
                        let c = roundedRect(hx, hy, shellX0, shellX1, half, shellR)
                        if c > 0 {
                            let t = clampf(hy / half, -1, 1)
                            let base = cylinderFlat(t, lx, ly)
                            let brushed: Float = 0.9 + 0.15 * RasterKit.hash(kInt(hy * 3) &+ 999)
                            // Schraublöcher (Langlöcher)
                            var hole: Float = 1
                            let ey = hy / screwRy
                            let ex0 = (hx - screw0) / screwRx
                            if ex0 * ex0 + ey * ey < 1 { hole = 0.25 }
                            let ex1 = (hx - screw1) / screwRx
                            if ex1 * ex1 + ey * ey < 1 { hole = 0.25 }
                            let v = (0.016 * base + 0.008) * brushed * hole
                            L.layer(c, v, v, v * 1.06)
                            // Facettenkanten als feine Lichtlinien (zur Lampe hin heller)
                            let edgeDist = half - abs(hy)
                            if edgeDist < facetW {
                                let facing: Float = hy * ly < 0 ? 0.32 : 0.08
                                L.layer(c * (1 - edgeDist / facetW), facing, facing, facing * 1.02)
                            }
                            if shellX1 - hx < frontEdge && hx < shellX1 { L.layer(0.6 * c, 0.22, 0.22, 0.23) }
                        }
                    }
                    // Fingerlift: dünner, gebogener Draht seitlich
                    do {
                        let t = (hx - liftX) / liftLen
                        if t >= 0 && t <= 1 {
                            let curve = liftA - liftB * t * t
                            let dist = abs(hy - curve)
                            let c = coverage(liftW - dist)
                            if c > 0 {
                                let q = hy - curve + liftOff
                                let v = 0.25 + 0.55 * kexp(-(q * q) / liftSigma)
                                L.layer(c, v, v, v)
                            }
                        }
                    }
                    // --- Kardanlager (über allem) ---
                    do {
                        let d = (fx * fx + fy * fy).squareRoot()
                        let c = coverage(gimbalR - d)
                        if c > 0 {
                            let rr = d / gimbalR
                            let th = katan2(fy, fx)
                            let dl = angleDiff(th, lightLocal)
                            let dl2 = angleDiff(th, lightLocalOpp)
                            let turned: Float = 0.85 + 0.3 * RasterKit.hash(kInt(d * 2.5) &+ 4242)
                            var v = 0.06 + 0.22 * (kexp(-(dl * dl) / 0.15) + 0.5 * kexp(-(dl2 * dl2) / 0.12)) * turned
                            // äußerer Ring hell, innen schwarze Lagerkappe mit Glanzpunkt
                            if rr < 0.55 {
                                let nx = fx / gimbalIn
                                let ny = fy / gimbalIn
                                let sx = nx - lx * 0.4, sy = ny - ly * 0.4
                                let spec = kexp(-(sx * sx + sy * sy) / 0.08)
                                v = 0.012 + 0.30 * spec
                            } else if rr < 0.62 {
                                v *= 0.3
                            }
                            if rr > 0.93 { v *= 0.55 }
                            L.layer(c, v, v, v * 1.03)
                        }
                    }
                    let idx = y * w + x
                    alphaMask[idx] = L.cov
                    out[idx] = L.cov <= 0 ? 0 : RasterKit.argb(lut, L.cov, L.r, L.g, L.b)
                }
            }
        }
        let shadow = blurShadow(alphaMask, w, h, radius: Swift.max(2, Int(kInt(0.009 * sf))), opacity: 0.72)
        return ArmRaster(arm: arm, shadow: shadow, pivotX: pivotX, pivotY: pivotY)
    }

    /** Schattierung eines Zylinders quer zur Blickrichtung; t = −1…1 über den Querschnitt. */
    @inline(__always)
    private static func cylinder(_ t: Float, _ lx: Float, _ ly: Float, metal: Bool) -> Float {
        let q = 1 - t * t
        let nz = (q < 0 ? 0 : q).squareRoot()
        let ny = t
        // Licht kommt von schräg oben (Höhe ~ 55°)
        let lz: Float = 0.82
        let lyy = ly * 0.57
        let diffuse = fmaxk(0, ny * lyy + nz * lz)
        // Spiegelnde Studio-Reflexion: helles Band nahe der lichtzugewandten Seite, dunkles Band gegenüber
        let reflectY = 2 * nz * ny // Reflexionsrichtung (y-Anteil)
        let sb = reflectY - lyy * 0.9
        let softbox = kexp(-(sb * sb) / 0.06)
        let db = reflectY + 0.75
        let darkband = kexp(-(db * db) / 0.05)
        if metal {
            return clampf(0.05 + 0.20 * diffuse + 0.85 * softbox - 0.04 * darkband, 0.01, 1)
        } else {
            return clampf(0.012 + 0.03 * diffuse + 0.22 * softbox, 0.004, 1)
        }
    }

    /** Flache Platte mit leicht gerundeten Kanten. */
    @inline(__always)
    private static func cylinderFlat(_ t: Float, _ lx: Float, _ ly: Float) -> Float {
        let edge = abs(t)
        let sign: Float = t > 0 ? 1 : (t < 0 ? -1 : 0)
        let tilt: Float = edge > 0.8 ? (edge - 0.8) / 0.2 * sign : 0
        return clampf(0.8 + 0.6 * (-tilt * ly), 0.3, 1.6) + 0 * lx
    }

    /** Abgerundetes Rechteck in lokalen Koordinaten: Deckung 0…1. */
    @inline(__always)
    private static func roundedRect(_ x: Float, _ y: Float, _ x0: Float, _ x1: Float, _ half: Float, _ radius: Float) -> Float {
        let cx = (x0 + x1) / 2
        let hw = (x1 - x0) / 2
        let qx = abs(x - cx) - (hw - radius)
        let qy = abs(y) - (half - radius)
        let mx = fmaxk(qx, 0), my = fmaxk(qy, 0)
        let outside = (mx * mx + my * my).squareRoot() + fmink(fmaxk(qx, qy), 0) - radius
        return coverage(-outside)
    }

    /** Weicher Schatten aus einer Deckungsmaske (zweifacher Kastenfilter ≈ Gauß). */
    private static func blurShadow(_ mask: UnsafeMutablePointer<Float>, _ w: Int, _ h: Int, radius: Int, opacity: Float) -> RasterImage {
        let n = w * h
        let a = UnsafeMutablePointer<Float>.allocate(capacity: n)
        a.initialize(from: mask, count: n)
        let tmp = UnsafeMutablePointer<Float>.allocate(capacity: n)
        tmp.initialize(repeating: 0, count: n)
        defer { a.deallocate(); tmp.deallocate() }
        for _ in 0..<2 {
            boxBlurH(src: a, dst: tmp, width: w, height: h, radius: radius) // waagerecht
            boxBlurV(src: tmp, dst: a, width: w, height: h, radius: radius) // senkrecht
        }
        var out = RasterImage(width: w, height: h)
        out.pixels.withUnsafeMutableBufferPointer { buf in
            for i in 0..<n {
                let v = clampf(a[i] * opacity, 0, 1)
                buf[i] = kRound(v * 255) << 24
            }
        }
        return out
    }

    // ------------------------------------------------------------------------------------------
    // Ersatz-Label
    // ------------------------------------------------------------------------------------------

    /**
     * Label für Titel ohne Cover: gedämpftes Rosé mit feinem Papier-Korn, Druckringen und einem
     * cremefarbenen Außenring. Titel/Interpret werden in der App darübergeschrieben.
     * Seitenlänge [size] = App: `labelSizePx(S)`.
     */
    public static func fallbackLabel(_ size: Int) -> RasterImage {
        var out = RasterImage(width: size, height: size)
        let c = Float(size) / 2
        let r0 = Float(size) / 2
        let lut = RasterKit.lut
        out.pixels.withUnsafeMutableBufferPointer { buf in
            let px = buf.baseAddress!
            parallelFor(size) { y in
                let dy = Float(y) + 0.5 - c
                for x in 0..<size {
                    let dx = Float(x) + 0.5 - c
                    let d = (dx * dx + dy * dy).squareRoot()
                    let a = coverage(r0 - d)
                    if a <= 0 {
                        px[y * size + x] = 0
                        continue
                    }
                    let r = d / r0
                    // Grundfarbe: gedecktes Rosé (linear), zur Mitte minimal heller
                    var lr: Float = 0.36
                    var lg: Float = 0.085
                    var lb: Float = 0.12
                    let center: Float = 1 + 0.12 * (1 - r)
                    lr *= center; lg *= center; lb *= center
                    // Cremefarbener Außenring + feiner Druckring
                    if r > 0.86 && r < 0.92 {
                        lr = 0.78; lg = 0.66; lb = 0.60
                    }
                    if abs(r - 0.80) < 0.006 || abs(r - 0.30) < 0.005 {
                        lr = 0.70; lg = 0.55; lb = 0.52
                    }
                    // Papierkorn
                    let grain: Float = 0.94 + 0.12 * RasterKit.hash2(Int32(x), Int32(y))
                    lr *= grain; lg *= grain; lb *= grain
                    px[y * size + x] = RasterKit.argb(lut, a, lr, lg, lb)
                }
            }
        }
        return out
    }

    // ------------------------------------------------------------------------------------------
    // Größen (wie `TurntableAssetCache` der Android-App)
    // ------------------------------------------------------------------------------------------

    /** Seitenlänge der Ebenen [record]/[sheen] für eine Plattenspieler-Fläche von [size] px (gerundet). */
    public static func recordSizePx(_ size: Int) -> Int {
        Int((2 * G.RECORD_RADIUS * G.PLATTER_FACTOR * Float(size)).rounded(.toNearestOrAwayFromZero))
    }

    /** Seitenlänge des Labels (Cover bzw. [fallbackLabel]) für eine Fläche von [size] px (gerundet). */
    public static func labelSizePx(_ size: Int) -> Int {
        Int((2 * G.LABEL_FACTOR * G.RECORD_RADIUS * Float(size)).rounded(.toNearestOrAwayFromZero))
    }
}
