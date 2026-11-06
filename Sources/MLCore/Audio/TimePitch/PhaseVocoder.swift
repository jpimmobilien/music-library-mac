import Foundation

/// Zeitdehnung ohne Tonhöhenänderung (Phase-Vocoder) für Musik – Portierung von `audio/PhaseVocoder.kt`
/// der Android-App (gleiches Verfahren, gleiche Parameter).
///
/// `stretch` > 1 verlängert das Signal, < 1 verkürzt es. Zusammen mit `SincResampler` ergibt das eine
/// Tonhöhenänderung bei gleichem Tempo (Modus „Tonhöhe“).
///
/// Verfahren (vgl. Laroche & Dolson 1999, „Improved phase vocoder time-scale modification of audio“):
/// - STFT mit Hann-Fenster, ca. 93 ms Fenster (4096 Samples bei 44,1/48 kHz), 4-fache Überlappung.
/// - **Identity Phase Locking**: Nur an Spektralspitzen wird die Phase fortgeschrieben; alle Bins im
///   Einflussbereich einer Spitze behalten ihre Phasenbeziehung zur Spitze. Das vermeidet den typischen
///   „verwaschenen“ Phase-Vocoder-Klang weitgehend.
/// - **Stereo-Kopplung**: Die Phasen werden aus der Summe aller Kanäle bestimmt und auf jeden Kanal als
///   gleiche Drehung angewendet → Phasenunterschiede zwischen den Kanälen (Stereobild) bleiben erhalten.
/// - **Anschläge**: Ein Detektor im Zeitbereich findet Anschläge (Schlagzeug, Klavier) im Voraus. Frames,
///   deren Fensterkern einen Anschlag enthält, übernehmen oberhalb von ca. 120 Hz die Originalphasen
///   („Phase Reset“) – der Anschlag bleibt scharf statt über das ganze Fenster verschmiert zu werden.
///
/// Der Ausgang ist zeitlich ausgerichtet: Ausgangs-Sample n entspricht der Eingangszeit n / stretch.
///
/// Unterschiede zu Android (Ergebnis unverändert, wo nicht anders genannt):
/// - Planare Kanäle statt verschachtelter Samples; alle Puffer fester Größe, im `init` angelegt
///   (echtzeit-sicher). Der Überlagerungspuffer braucht nur n Werte je Kanal: Jeder Frame wird genau an
///   dessen Anfang addiert (die Android-Fassung reserviert 2n, der Rest bleibt dort immer 0).
/// - Nicht endliche Eingangswerte (NaN/∞) werden als 0 übernommen; ein einzelnes NaN würde sonst die
///   Phasenfortschreibung bis zum nächsten `reset()` dauerhaft vergiften.
/// - Bei stretch < 0,25 (Analyse-Schritt größer als das Fenster) springt die Android-Fassung beim Verwerfen
///   ggf. weiter als Daten im Puffer liegen und verliert dann die zeitliche Ausrichtung. Hier werden die
///   fehlenden Frames beim nächsten `push` übersprungen. Für die App (|Halbtöne| ≤ 12, Tempo 0,5–2) tritt
///   dieser Fall nicht auf.
final class PhaseVocoder {
    /// Energieanstieg (Faktor gegenüber den letzten ~46 ms), ab dem ein Anschlag erkannt wird.
    static let onsetRatio = 8.0
    /// Mindestenergie eines Anschlags (≈ −60 dBFS, differenziert).
    static let onsetFloor = 1e-6
    /// Höchstzahl gleichzeitig vorgemerkter Anschläge (Mindestabstand 50 ms → real höchstens etwa 6).
    private static let onsetCapacity = 64

    let sampleRate: Int
    let channels: Int
    let stretch: Double
    let fftSize: Int

    private let n: Int
    private let bins: Int
    let synthesisHop: Int
    let analysisHop: Double
    private let fft: RealFFT
    private let window: UnsafeMutablePointer<Double>
    /// Hann² bei 4-facher Überlappung summiert sich zu 1,5.
    private let olaScale = 1.0 / 1.5
    private let resetBin: Int

    private let input: FloatFifo
    /// Überlagerungspuffer, n Werte je Kanal (Kanal c ab `acc + c * n`).
    private let acc: UnsafeMutablePointer<Double>
    private var accStart = 0

    private var frameIndex = 0
    private var inputOffset = 0
    private var prevStart = Int.min
    private var first = true
    /// Noch zu überspringende Eingangs-Frames (nur bei stretch < 0,25, siehe oben).
    private var pendingSkip = 0

    private let frame: UnsafeMutablePointer<Double>
    /// Spektren je Kanal (Kanal c ab `re + c * bins`).
    private let re: UnsafeMutablePointer<Double>
    private let im: UnsafeMutablePointer<Double>
    private let mixRe: UnsafeMutablePointer<Double>
    private let mixIm: UnsafeMutablePointer<Double>
    private let prevMixRe: UnsafeMutablePointer<Double>
    private let prevMixIm: UnsafeMutablePointer<Double>
    private let power: UnsafeMutablePointer<Double>
    private let rotation: UnsafeMutablePointer<Double>
    private let prevRotation: UnsafeMutablePointer<Double>
    private let rotCos: UnsafeMutablePointer<Double>
    private let rotSin: UnsafeMutablePointer<Double>
    private let peaks: UnsafeMutablePointer<Int>
    private let out: UnsafeMutablePointer<Double>

    // ---- Anschlagerkennung im Zeitbereich (läuft auf dem eingehenden Signal) ----
    private let onsetBlock: Int
    private let history: UnsafeMutablePointer<Double>
    private let historySize = 8
    private var historyCount = 0
    private var blockEnergy = 0.0
    private var blockFill = 0
    private let lastSample: UnsafeMutablePointer<Double>
    /// Gepolsterte Eingangsposition des nächsten Samples für den Detektor.
    private var detectorPos = 0
    private var lastOnset = Int.min / 2
    /// Ringpuffer der vorgemerkten Anschläge (aufsteigend, gepolsterte Koordinaten).
    private let onsets: UnsafeMutablePointer<Int>
    private var onsetHead = 0
    private var onsetCount = 0

    /// FFT-Länge für eine Abtastrate (wie Android).
    static func fftSize(sampleRate: Int) -> Int {
        if sampleRate <= 24_000 { return 2048 }
        if sampleRate <= 50_000 { return 4096 }
        if sampleRate <= 100_000 { return 8192 }
        return 16384
    }

    /// - Parameter maxPushFrames: Höchstmenge je `push` (zwischen zwei `process`-Aufrufen).
    init(sampleRate: Int, channels: Int, stretch: Double, maxPushFrames: Int, fftSizeOverride: Int = 0) {
        precondition(channels >= 1 && stretch > 0)
        self.sampleRate = sampleRate
        self.channels = channels
        self.stretch = stretch
        let n = fftSizeOverride > 0 ? fftSizeOverride : PhaseVocoder.fftSize(sampleRate: sampleRate)
        fftSize = n
        self.n = n
        bins = n / 2 + 1
        synthesisHop = n / 4
        analysisHop = Double(n / 4) / stretch
        fft = RealFFT(n: n)
        window = .allocate(capacity: n)
        for i in 0..<n { (window + i).initialize(to: 0.5 - 0.5 * cos(2.0 * Double.pi * Double(i) / Double(n))) }
        resetBin = max(1, Int(120.0 * Double(n) / Double(sampleRate)))

        // Vor einem push liegen höchstens 2n Frames im Puffer (siehe process); bei sehr kleinem stretch
        // kann der Analyse-Schritt größer als n sein.
        let hop = Int(ceil(Double(n / 4) / stretch))
        input = FloatFifo(channels: channels, capacity: 2 * n + max(n, hop) + maxPushFrames + 64)
        acc = .allocate(capacity: channels * n)
        acc.initialize(repeating: 0, count: channels * n)

        func zeros(_ count: Int) -> UnsafeMutablePointer<Double> {
            let p = UnsafeMutablePointer<Double>.allocate(capacity: count)
            p.initialize(repeating: 0, count: count)
            return p
        }
        let bins = n / 2 + 1
        frame = zeros(n)
        re = zeros(channels * bins)
        im = zeros(channels * bins)
        mixRe = zeros(bins)
        mixIm = zeros(bins)
        prevMixRe = zeros(bins)
        prevMixIm = zeros(bins)
        power = zeros(bins)
        rotation = zeros(bins)
        prevRotation = zeros(bins)
        rotCos = zeros(bins)
        rotSin = zeros(bins)
        peaks = .allocate(capacity: bins)
        peaks.initialize(repeating: 0, count: bins)
        out = zeros(n)

        onsetBlock = max(64, sampleRate / 172) // ≈ 5,8 ms
        history = zeros(8)
        lastSample = zeros(channels)
        onsets = .allocate(capacity: PhaseVocoder.onsetCapacity)
        onsets.initialize(repeating: 0, count: PhaseVocoder.onsetCapacity)
        reset()
    }

    deinit {
        window.deallocate()
        acc.deallocate()
        frame.deallocate()
        re.deallocate()
        im.deallocate()
        mixRe.deallocate()
        mixIm.deallocate()
        prevMixRe.deallocate()
        prevMixIm.deallocate()
        power.deallocate()
        rotation.deallocate()
        prevRotation.deallocate()
        rotCos.deallocate()
        rotSin.deallocate()
        peaks.deallocate()
        out.deallocate()
        history.deallocate()
        lastSample.deallocate()
        onsets.deallocate()
    }

    /// Zurück in den Anfangszustand (z. B. nach dem Spulen); Tabellen und Puffer bleiben erhalten.
    func reset() {
        input.clear()
        // Vorlauf: Der erste Analyse-Frame ist auf Eingangs-Sample 0 zentriert.
        input.appendZeros(n / 2)
        acc.update(repeating: 0, count: channels * n)
        accStart = -(n / 2)
        frameIndex = 0
        inputOffset = 0
        prevStart = Int.min
        first = true
        pendingSkip = 0
        prevRotation.update(repeating: 0, count: bins)
        prevMixRe.update(repeating: 0, count: bins)
        prevMixIm.update(repeating: 0, count: bins)
        historyCount = 0
        blockEnergy = 0
        blockFill = 0
        lastSample.update(repeating: 0, count: channels)
        detectorPos = n / 2
        lastOnset = Int.min / 2
        onsetHead = 0
        onsetCount = 0
    }

    /// Überlauf-Diagnose des Eingangspuffers (soll 0 bleiben).
    var overflowFrames: Int { input.overflowFrames }

    func push(_ src: UnsafePointer<UnsafePointer<Float>>, offset: Int, frames: Int) {
        if frames <= 0 { return }
        detectOnsets(src, offset: offset, frames: frames)
        var skip = 0
        if pendingSkip > 0 {
            skip = min(pendingSkip, frames)
            pendingSkip -= skip
        }
        let count = frames - skip
        if count <= 0 { return }
        let before = input.frames
        input.append(src, offset: offset + skip, count: count)
        let added = input.frames - before
        for c in 0..<channels {
            let p = input.pointer(c, before)
            for i in 0..<added where !p[i].isFinite { p[i] = 0 }
        }
    }

    private func detectOnsets(_ src: UnsafePointer<UnsafePointer<Float>>, offset: Int, frames: Int) {
        let channels = self.channels
        for f in 0..<frames {
            // Hochpass (1. Differenz) betont Anschläge gegenüber tiefen Dauertönen
            var e = 0.0
            for c in 0..<channels {
                let v = src[c][offset + f]
                let x = v.isFinite ? Double(v) : 0
                let d = x - lastSample[c]
                lastSample[c] = x
                e += d * d
            }
            blockEnergy += e
            blockFill += 1
            if blockFill == onsetBlock {
                let energy = blockEnergy / Double(onsetBlock * channels)
                var mean = 0.0
                for i in 0..<historyCount { mean += history[i] }
                mean = historyCount > 0 ? mean / Double(historyCount) : 0
                let blockStart = detectorPos + f + 1 - onsetBlock
                if historyCount == historySize && energy > PhaseVocoder.onsetFloor && energy > mean * PhaseVocoder.onsetRatio &&
                    blockStart - lastOnset > sampleRate / 20 {
                    if onsetCount < PhaseVocoder.onsetCapacity {
                        onsets[(onsetHead + onsetCount) % PhaseVocoder.onsetCapacity] = blockStart
                        onsetCount += 1
                    }
                    lastOnset = blockStart
                }
                // gleitende Historie (älteste ersetzen)
                if historyCount < historySize {
                    history[historyCount] = energy
                    historyCount += 1
                } else {
                    history.update(from: history + 1, count: historySize - 1)
                    history[historySize - 1] = energy
                }
                blockEnergy = 0
                blockFill = 0
            }
        }
        detectorPos += frames
    }

    /// Verarbeitet alle vollständig verfügbaren Analyse-Frames und schreibt fertige Samples in `output`.
    func process(into output: FloatFifo) {
        let n = self.n
        while true {
            let start = Int((Double(frameIndex) * analysisHop).rounded()) // gepolsterte Eingangskoordinaten
            let local = start - inputOffset
            if local + n > input.frames { break }
            // Anschläge vor diesem Fenster sind erledigt
            while onsetCount > 0 && onsets[onsetHead] < start {
                onsetHead = (onsetHead + 1) % PhaseVocoder.onsetCapacity
                onsetCount -= 1
            }
            // Anschlag im Kern dieses Fensters? (Position in gepolsterten Koordinaten)
            var onset: Int? = nil
            var i = 0
            while i < onsetCount {
                let o = onsets[(onsetHead + i) % PhaseVocoder.onsetCapacity]
                if o >= start + n / 8 && o < start + n - n / 8 {
                    onset = o
                    break
                }
                i += 1
            }
            analyzeAndSynthesize(local: local, start: start, onset: onset)
            prevStart = start
            frameIndex += 1
            emitUntil(frameIndex * synthesisHop - n / 2, output)
            let nextStart = Int((Double(frameIndex) * analysisHop).rounded())
            let dropTo = nextStart - inputOffset
            if dropTo > n {
                let available = input.frames
                input.drop(dropTo)
                if dropTo > available { pendingSkip += dropTo - available }
                inputOffset += dropTo
            }
        }
    }

    private func analyzeAndSynthesize(local: Int, start: Int, onset: Int?) {
        let n = self.n
        let bins = self.bins
        mixRe.update(repeating: 0, count: bins)
        mixIm.update(repeating: 0, count: bins)
        for c in 0..<channels {
            let src = input.pointer(c, local)
            for i in 0..<n { frame[i] = Double(src[i]) * window[i] }
            let r = re + c * bins
            let m = im + c * bins
            fft.forward(frame, r, m)
            for k in 0..<bins {
                mixRe[k] += r[k]
                mixIm[k] += m[k]
            }
        }
        for k in 0..<bins { power[k] = mixRe[k] * mixRe[k] + mixIm[k] * mixIm[k] }

        if first {
            rotation.update(repeating: 0, count: bins)
        } else {
            let hopA = Double(start - prevStart)
            var maxPower = 0.0
            for k in 0..<bins where power[k] > maxPower { maxPower = power[k] }
            let floorPower = maxPower * 1e-14
            var peakCount = 0
            for k in 0..<bins {
                let a = power[k]
                if a <= floorPower { continue }
                if k >= 1 && a < power[k - 1] { continue }
                if k >= 2 && a < power[k - 2] { continue }
                if k + 1 < bins && a <= power[k + 1] { continue }
                if k + 2 < bins && a <= power[k + 2] { continue }
                peaks[peakCount] = k
                peakCount += 1
            }
            if peakCount == 0 {
                rotation.update(repeating: 0, count: bins)
            } else {
                var regionStart = 0
                for p in 0..<peakCount {
                    let k = peaks[p]
                    // Phasenfortschreibung an der Spitze: ψ = ψ_vorher + Hs · Momentanfrequenz
                    let phase = atan2(mixIm[k], mixRe[k])
                    let prevPhase = atan2(prevMixIm[k], prevMixRe[k])
                    let omega = 2.0 * Double.pi * Double(k) / Double(n)
                    let deviation = PhaseVocoder.princarg(phase - prevPhase - omega * hopA)
                    let instFreq = omega + (hopA > 0 ? deviation / hopA : 0.0)
                    let synth = prevPhase + prevRotation[k] + Double(synthesisHop) * instFreq
                    let rot = PhaseVocoder.princarg(synth - phase)
                    var regionEnd = bins - 1
                    if p + 1 < peakCount {
                        // Grenze zur nächsten Spitze: das Minimum dazwischen
                        var lowest = k
                        var lowestPower = Double.greatestFiniteMagnitude
                        var j = k
                        let next = peaks[p + 1]
                        while j <= next {
                            if power[j] < lowestPower {
                                lowestPower = power[j]
                                lowest = j
                            }
                            j += 1
                        }
                        regionEnd = lowest
                    }
                    var j = regionStart
                    while j <= regionEnd {
                        rotation[j] = rot
                        j += 1
                    }
                    regionStart = regionEnd + 1
                }
            }
            if let onset {
                // Anschlag: oberhalb ~120 Hz Originalphasen übernehmen (Bass bleibt phasenkontinuierlich)
                // und den Frame-Inhalt so verschieben, dass der Anschlag in JEDEM betroffenen Frame an
                // derselben Ausgangsposition landet (sonst entstehen versetzte Kopien = Vorecho).
                let onsetOriginal = Double(onset - n / 2)
                let tau = onsetOriginal - Double(start) // Abstand des Anschlags zur Fenstermitte (Eingang)
                let target = onsetOriginal * stretch // Soll-Ausgangsposition
                let limit = Double(n) / 8.0
                let delta = min(max(target - (Double(frameIndex * synthesisHop) + tau), -limit), limit)
                let w = -2.0 * Double.pi * delta / Double(n)
                for k in resetBin..<bins { rotation[k] = PhaseVocoder.princarg(w * Double(k)) }
            }
        }
        first = false
        prevMixRe.update(from: mixRe, count: bins)
        prevMixIm.update(from: mixIm, count: bins)
        prevRotation.update(from: rotation, count: bins)

        // Drehung je Bin (innerhalb einer Region konstant → Winkelfunktionen nur bei Wechsel)
        var lastRot = Double.nan
        var cr = 1.0
        var sr = 0.0
        for k in 0..<bins {
            let rot = rotation[k]
            if rot != lastRot {
                cr = cos(rot)
                sr = sin(rot)
                lastRot = rot
            }
            rotCos[k] = cr
            rotSin[k] = sr
        }

        // Der Frame beginnt immer am Anfang des Überlagerungspuffers (accStart == outPos, siehe emitUntil).
        let outPos = frameIndex * synthesisHop - n / 2
        let offset = outPos - accStart
        assert(offset == 0, "Überlagerungspuffer nicht ausgerichtet")
        for c in 0..<channels {
            let r = re + c * bins
            let m = im + c * bins
            for k in 0..<bins {
                let a = r[k]
                let b = m[k]
                r[k] = a * rotCos[k] - b * rotSin[k]
                m[k] = a * rotSin[k] + b * rotCos[k]
            }
            fft.inverse(r, m, out)
            let a = acc + c * n
            for i in 0..<n { a[i] += out[i] * window[i] * olaScale }
        }
    }

    /// Gibt Ausgangs-Samples mit Position < `until` aus (Positionen < 0 sind Vorlauf und entfallen).
    private func emitUntil(_ until: Int, _ output: FloatFifo) {
        let n = self.n
        let count = min(until - accStart, n)
        if count <= 0 { return }
        let skip = accStart < 0 ? min(count, -accStart) : 0
        let emit = count - skip
        if emit > 0 {
            let space = output.appendSpace(emit)
            if space.count > 0 {
                for c in 0..<channels {
                    let a = acc + c * n + skip
                    let o = output.plane(c) + space.index
                    for i in 0..<space.count { o[i] = Float(a[i]) }
                }
            }
        }
        for c in 0..<channels {
            let a = acc + c * n
            a.update(from: a + count, count: n - count)
            (a + n - count).update(repeating: 0, count: count)
        }
        accStart += count
    }

    static func princarg(_ x: Double) -> Double {
        x - 2.0 * Double.pi * floor((x + Double.pi) / (2.0 * Double.pi))
    }
}
