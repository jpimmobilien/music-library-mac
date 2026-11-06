import Foundation

/// Resampler mit gefensterter Sinc-Funktion (Kaiser-Fenster) für ein festes Verhältnis –
/// Portierung von `audio/SincResampler.kt` der Android-App.
///
/// `step` = Eingangs-Samples pro Ausgangs-Sample. step > 1 bedeutet: das Signal wird „schneller“
/// abgespielt (höher), step < 1 „langsamer“ (tiefer) – wie eine Schallplatte mit anderer Drehzahl.
///
/// Qualität: Die Grenzfrequenz wird bei step > 1 mit abgesenkt (Anti-Aliasing), damit keine
/// Spiegelfrequenzen entstehen. Mit `zeroCrossings` Nulldurchgängen je Seite und Kaiser-β 9,5 liegt
/// die Sperrdämpfung bei rund 90 dB, der Durchlassbereich reicht bis ca. 90 % der (Ausgangs-)
/// Nyquistfrequenz. Der Ausgang ist zeitlich am Eingang ausgerichtet (Ausgangs-Sample j entspricht der
/// Eingangsposition j·step); die Latenz wird intern durch Vorlauf-Nullen ausgeglichen.
///
/// Rechenaufwand: Die Filterkoeffizienten liegen als Polyphasen-Tabelle vor (`phases` Teilpositionen
/// zwischen zwei Eingangs-Samples); zwischen benachbarten Teilpositionen wird linear interpoliert.
/// Je Ausgangs-Sample und Kanal bleiben damit zwei Skalarprodukte – keine Winkelfunktionen zur Laufzeit.
///
/// Abweichung von Android (bewusst): Die Leseposition wird als ganzzahliger Teil + Bruchteil geführt statt als
/// eine Double-Zahl, die beim Verwerfen alter Samples um ganze Zahlen verkleinert wird. Dadurch ist das
/// Ergebnis bitgleich unabhängig davon, wann verworfen wird (also von den Blockgrößen), und etwas genauer.
///
/// Echtzeit-sicher nach dem `init`: `push`/`process`/`reset` fordern keinen Speicher an.
final class SincResampler {
    /// Teilpositionen der Polyphasen-Tabelle (zwischen ihnen wird linear interpoliert).
    static let phases = 256

    let channels: Int
    let step: Double
    /// Halbe Filterlänge in Eingangs-Samples.
    let halfTaps: Int
    private let taps: Int
    /// Grenzfrequenz relativ zur Eingangs-Nyquistfrequenz.
    private let cutoff: Double

    /// Polyphasen-Tabelle: Zeile ph (0…phases) enthält die `taps` Koeffizienten für den Bruchteil
    /// frac = ph / phases, für die Eingangs-Samples center-halfTaps+1 … center+halfTaps.
    private let bank: UnsafeMutablePointer<Float>
    /// Eingangspuffer (öffentlich innerhalb des Moduls, damit der Phase-Vocoder direkt hineinschreiben kann).
    let input: FloatFifo
    /// Position des nächsten Ausgangs-Samples relativ zu `input.start`: ganzzahliger Teil …
    private var positionInt: Int
    /// … und Bruchteil in [0, 1).
    private var positionFrac: Double

    /// Halbe Filterlänge für ein Verhältnis (für Kapazitäts- und Latenzberechnungen).
    static func halfTaps(step: Double, zeroCrossings: Int = 48) -> Int {
        let cutoff = 0.955 * min(1.0, 1.0 / step)
        return Int(ceil(Double(zeroCrossings) / cutoff))
    }

    /// - Parameter maxPushFrames: Höchstmenge, die zwischen zwei `process`-Aufrufen angehängt wird.
    init(channels: Int, step: Double, maxPushFrames: Int, zeroCrossings: Int = 48, beta: Double = 9.5) {
        precondition(step > 0)
        let cutoff = 0.955 * min(1.0, 1.0 / step)
        let halfTaps = Int(ceil(Double(zeroCrossings) / cutoff))
        let taps = 2 * halfTaps
        self.channels = channels
        self.step = step
        self.cutoff = cutoff
        self.halfTaps = halfTaps
        self.taps = taps

        let phases = SincResampler.phases
        let bank = UnsafeMutablePointer<Float>.allocate(capacity: (phases + 1) * taps)
        let i0Beta = SincResampler.besselI0(beta)
        let support = Double(halfTaps)
        for ph in 0...phases {
            let frac = Double(ph) / Double(phases)
            var sum = 0.0
            let row = ph * taps
            for k in 0..<taps {
                // Abstand zwischen Ausgangsposition und Eingangs-Sample (center - halfTaps + 1 + k)
                let d = frac + Double(halfTaps - 1 - k)
                let x = d * cutoff
                let sinc = x == 0 ? 1.0 : sin(Double.pi * x) / (Double.pi * x)
                let r = d / support
                let window = abs(r) >= 1.0 ? 0.0 : SincResampler.besselI0(beta * (1.0 - r * r).squareRoot()) / i0Beta
                let c = cutoff * sinc * window
                (bank + row + k).initialize(to: Float(c))
                sum += c
            }
            // Gleichanteil exakt 1 (keine Pegelwelligkeit zwischen den Teilpositionen)
            if sum != 0 {
                for k in 0..<taps { bank[row + k] = Float(Double(bank[row + k]) / sum) }
            }
        }
        self.bank = bank

        // Kapazität: Nach `process` bleiben höchstens 4096 + 2·halfTaps (+ Rundungsreserve) Frames liegen,
        // dazu kommt der nächste Block.
        let input = FloatFifo(channels: channels, capacity: 4096 + 2 * halfTaps + maxPushFrames + 64)
        // Vorlauf: negative Eingangspositionen sind Stille → Ausgang beginnt zeitgleich mit dem Eingang.
        input.appendZeros(halfTaps)
        self.input = input
        positionInt = halfTaps
        positionFrac = 0
    }

    deinit {
        bank.deallocate()
    }

    /// Verwirft alle gepufferten Daten (z. B. nach dem Spulen); die Filtertabelle bleibt erhalten.
    func reset() {
        input.clear()
        input.appendZeros(halfTaps)
        positionInt = halfTaps
        positionFrac = 0
    }

    func push(_ src: UnsafePointer<UnsafePointer<Float>>, offset: Int, frames: Int) {
        input.append(src, offset: offset, count: frames)
    }

    func pushZeros(_ frames: Int) {
        input.appendZeros(frames)
    }

    /// Erzeugt so viele Ausgangs-Frames wie möglich in `out`.
    func process(into out: FloatFifo) {
        let available = input.frames
        // Anzahl erzeugbarer Ausgangs-Samples: floor(position + j·step) + halfTaps < available
        let maxCenter = available - halfTaps - 1
        if positionInt > maxCenter { return }
        let estimate = Int(floor((Double(maxCenter + 1 - positionInt) - positionFrac) / step)) + 1
        if estimate <= 0 { return }
        let space = out.appendSpace(estimate)
        let count = space.count
        if count == 0 { return }
        let taps = self.taps
        let bank = self.bank
        let step = self.step
        let phases = Double(SincResampler.phases)
        let base = input.start
        var o = space.index
        var center = positionInt
        var frac = positionFrac
        var produced = 0
        while produced < count {
            if center > maxCenter { break } // Rundungsreserve: nicht genug Eingang
            let f = frac * phases
            let ph = Int(f)
            let w = Float(f - Double(ph))
            let row0 = bank + ph * taps
            let row1 = row0 + taps
            let first = base + center - halfTaps + 1
            if channels == 2 {
                // Stereo: beide Kanäle in einem Durchlauf (halb so viele Tabellenzugriffe)
                let xl = input.plane(0) + first
                let xr = input.plane(1) + first
                var l0: Float = 0
                var l1: Float = 0
                var r0: Float = 0
                var r1: Float = 0
                var k = 0
                while k < taps {
                    let a = xl[k]
                    let b = xr[k]
                    let c0 = row0[k]
                    let c1 = row1[k]
                    l0 += a * c0
                    l1 += a * c1
                    r0 += b * c0
                    r1 += b * c1
                    k += 1
                }
                out.plane(0)[o] = l0 + (l1 - l0) * w
                out.plane(1)[o] = r0 + (r1 - r0) * w
            } else {
                for c in 0..<channels {
                    let x = input.plane(c) + first
                    var a0: Float = 0
                    var a1: Float = 0
                    var k = 0
                    while k < taps {
                        let v = x[k]
                        a0 += v * row0[k]
                        a1 += v * row1[k]
                        k += 1
                    }
                    out.plane(c)[o] = a0 + (a1 - a0) * w
                }
            }
            o += 1
            produced += 1
            frac += step
            let whole = floor(frac)
            center += Int(whole)
            frac -= whole
        }
        if produced < count {
            // nicht benötigten Platz wieder freigeben
            out.truncate(out.frames - (count - produced))
        }
        positionInt = center
        positionFrac = frac
        // Nicht mehr benötigte Eingangs-Samples verwerfen.
        let keepFrom = positionInt - halfTaps
        if keepFrom > 4096 {
            input.drop(keepFrom)
            positionInt -= keepFrom
        }
    }

    /// Modifizierte Bessel-Funktion erster Art, Ordnung 0 (für das Kaiser-Fenster).
    static func besselI0(_ x: Double) -> Double {
        var sum = 1.0
        var term = 1.0
        let q = x * x / 4.0
        var k = 1
        while k < 200 {
            term *= q / (Double(k) * Double(k))
            sum += term
            if term < sum * 1e-17 { break }
            k += 1
        }
        return sum
    }
}
