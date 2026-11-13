import Foundation

/// Auto-Tune: zieht eine einstimmige Melodie (Gesang) auf die Töne einer Tonleiter.
///
/// Verfahren: Grundfrequenz alle ≈ 10 ms nach McLeod (auf einer dezimierten Mittensumme), Zielton = nächster Ton der
/// Tonleiter, Korrektur geglättet je nach Stärke (100 % = sofort, „Roboter“; 0 % = sehr weich), dann
/// pitch-synchrones Überlappen und Addieren (TD-PSOLA): Ausschnitte von zwei Perioden um die Analysemarken werden im
/// Abstand der Zielperiode neu gesetzt. Das Tempo bleibt gleich, Ausgabe und Eingabe sind Frame für Frame
/// ausgerichtet (gleiche Länge). Stimmlose oder mehrstimmige Stellen (Klarheit < 0,8) bleiben unverändert.
///
/// Grenzen: Funktioniert für Einzelstimmen (A cappella, Sprachaufnahmen). In fertig gemischter Musik lässt sich die
/// Stimme nicht von den Instrumenten trennen – erkannt wird dort meist nichts oder nur die lauteste Linie, und
/// eine Korrektur verschiebt den ganzen Mix an dieser Stelle.
public final class AutoTuneProcessor {
    public struct Settings: Equatable, Sendable {
        /// Grundton der Tonart (0 = C … 11 = H).
        public var key: Int
        public var scale: MusicScale
        /// 0…1: Geschwindigkeit der Korrektur (1 = sofort).
        public var strength: Double
        /// Kammerton, auf den gestimmt wird (Hz).
        public var reference: Double

        public init(key: Int, scale: MusicScale, strength: Double, reference: Double = 440) {
            self.key = ((key % 12) + 12) % 12
            self.scale = scale
            self.strength = min(max(strength, 0), 1)
            self.reference = reference > 0 ? reference : 440
        }

        /// Zeitkonstante der Glättung in Sekunden (Stärke 1 → 0; Stärke 0 → 250 ms).
        public var smoothingSeconds: Double { (1 - strength) * 0.25 }
    }

    public let sampleRate: Double
    public let channels: Int
    public let settings: Settings
    // Analyse
    private let factor: Int
    private let decimator: Decimator
    private let detector: PitchDetector
    private let hop = 128
    private let analysisWindow = 1024
    private var dec: [Float] = []
    private var decBase = 0              // absoluter Index von dec[0] (dezimiert)
    private var nextFrame = 0            // nächstes Analysefenster (Nummer)
    private var smoothedCents = 0.0
    /// je Analysefenster: Periode (Frames, volle Rate; nil = stimmlos) und Faktor
    private var periods: [Double?] = []
    private var ratios: [Double] = []
    /// Diagnose: erkannte Grundfrequenzen (Hz) je Fenster (nil = stimmlos)
    public private(set) var detected: [Double?] = []
    // Synthese
    private var input: [[Float]]
    private var inputBase = 0            // absoluter Index von input[c][0]
    private var inputEnd: Int { inputBase + (input.first?.count ?? 0) }
    private var marks: [Int] = [0]       // Analysemarken (absolut), aufsteigend
    private var marksBase = 0            // Index des ersten gespeicherten Eintrags in der Gesamtfolge (nur intern)
    private var nextSynthesis = 0        // nächste Synthesemarke (absolut)
    private var acc: [[Float]]
    private var weight: [Float] = []
    private var accBase = 0
    private var finished = false
    private let maxPeriod: Int
    private let unvoicedPeriod: Int
    public private(set) var totalInput = 0
    public private(set) var totalOutput = 0

    public init(sampleRate: Double, channels: Int, settings: Settings) {
        precondition(sampleRate > 0 && channels >= 1)
        self.sampleRate = sampleRate
        self.channels = channels
        self.settings = settings
        factor = max(1, Int((sampleRate / 12_000).rounded()))
        decimator = Decimator(sampleRate: sampleRate, factor: factor)
        detector = PitchDetector(sampleRate: sampleRate / Double(factor), windowSize: analysisWindow, minFrequency: 70, maxFrequency: 1000)
        maxPeriod = Int((sampleRate / 70).rounded(.up))
        unvoicedPeriod = max(32, Int((sampleRate * 0.005).rounded()))
        input = Array(repeating: [], count: channels)
        acc = Array(repeating: [], count: channels)
    }

    // MARK: Eingang

    public func push(_ data: [UnsafePointer<Float>], frames n: Int) {
        guard n > 0, !finished else { return }
        precondition(data.count >= channels)
        var mid = [Float](repeating: 0, count: n)
        for c in 0..<channels {
            input[c].append(contentsOf: UnsafeBufferPointer(start: data[c], count: n))
            for i in 0..<n { mid[i] += data[c][i] }
        }
        let scale = 1 / Float(channels)
        for i in 0..<n { mid[i] *= scale }
        mid.withUnsafeMutableBufferPointer { decimator.process($0.baseAddress!, frames: n, into: &dec) }
        totalInput += n
        analyzeAvailable()
        synthesize()
    }

    public func finish() {
        guard !finished else { return }
        finished = true
        // Restliche Analysefenster mit Stille auffüllen
        dec.append(contentsOf: [Float](repeating: 0, count: analysisWindow))
        analyzeAvailable()
        synthesize()
    }

    // MARK: Analyse

    private func analyzeAvailable() {
        while (nextFrame * hop + analysisWindow) <= decBase + dec.count {
            let start = nextFrame * hop - decBase
            let result: (frequency: Double, clarity: Double)? = dec.withUnsafeBufferPointer { b in
                detector.detect(b.baseAddress! + start)
            }
            let dt = Double(hop * factor) / sampleRate
            var target = 0.0       // Korrektur in Cent
            var period: Double?
            if let r = result {
                period = sampleRate / r.frequency
                let midi = MusicMath.midi(r.frequency, reference: settings.reference)
                let note = settings.scale.nearestNote(to: midi, key: settings.key)
                target = (note - midi) * 100
                detected.append(r.frequency)
            } else {
                detected.append(nil)
            }
            // Glättung: auf Zielwert zu (stimmlos: schnell zurück auf 0)
            let tau = result == nil ? 0.03 : settings.smoothingSeconds
            let a = tau <= 0 ? 1 : 1 - exp(-dt / tau)
            smoothedCents += (target - smoothedCents) * a
            periods.append(period)
            ratios.append(pow(2, smoothedCents / 1200))
            nextFrame += 1
        }
        // Verbrauchte dezimierte Werte entfernen
        let keepFrom = nextFrame * hop - decBase
        if keepFrom > 4096 {
            dec.removeFirst(keepFrom)
            decBase += keepFrom
        }
    }

    /// Analysefenster, dessen Mitte `t` (volle Rate) am nächsten liegt.
    private func frameIndex(at t: Int) -> Int {
        let center = Double(analysisWindow / 2 * factor)
        let j = Int(((Double(t) - center) / Double(hop * factor)).rounded())
        return max(0, min(j, periods.count - 1))
    }

    /// Bis zu welcher Stelle (volle Rate) liegen Analyseergebnisse vor?
    private var analyzedUntil: Int {
        guard !periods.isEmpty else { return 0 }
        return (periods.count - 1) * hop * factor + analysisWindow / 2 * factor
    }

    private func period(at t: Int) -> Int {
        guard !periods.isEmpty, let p = periods[frameIndex(at: t)] else { return unvoicedPeriod }
        return max(16, min(maxPeriod, Int(p.rounded())))
    }

    private func ratio(at t: Int) -> Double {
        guard !ratios.isEmpty else { return 1 }
        return ratios[frameIndex(at: t)]
    }

    // MARK: Synthese

    private func synthesize() {
        let limit: Int
        if finished {
            limit = totalInput
        } else {
            // genug Eingang und Analyse für zwei Perioden um die nächste Marke
            limit = min(inputEnd, analyzedUntil) - 3 * maxPeriod
        }
        guard limit > 0 else { return }
        // Analysemarken bis über die Grenze hinaus fortschreiben
        while let last = marks.last, last < min(limit + 2 * maxPeriod, finished ? totalInput : Int.max) {
            marks.append(last + period(at: last))
        }
        while nextSynthesis < limit {
            let ts = nextSynthesis
            let pa = period(at: ts)
            let r = ratio(at: ts)
            // nächstgelegene Analysemarke
            var idx = marks.firstIndex { $0 >= ts } ?? (marks.count - 1)
            if idx > 0, abs(marks[idx - 1] - ts) <= abs(marks[idx] - ts) { idx -= 1 }
            let center = marks[idx]
            let half = period(at: center)
            addGrain(center: center, at: ts, half: half)
            let step = max(8, Int((Double(pa) / r).rounded()))
            nextSynthesis = ts + step
            // alte Marken entfernen
            if idx > 64 { marks.removeFirst(idx - 8) }
        }
        trimInput()
    }

    private func addGrain(center: Int, at ts: Int, half: Int) {
        let end = ts + half
        ensureAccumulator(until: end + 1)
        let L = Double(half)
        for k in -half...half {
            let out = ts + k
            guard out >= accBase, out >= 0, out < totalInput || !finished else { continue }
            let src = center + k
            let w = Float(0.5 + 0.5 * cos(Double.pi * Double(k) / L))
            let oi = out - accBase
            guard oi >= 0, oi < weight.count else { continue }
            weight[oi] += w
            if src >= inputBase && src < inputEnd {
                let si = src - inputBase
                for c in 0..<channels { acc[c][oi] += input[c][si] * w }
            }
        }
    }

    private func ensureAccumulator(until end: Int) {
        let need = end - accBase
        if need > weight.count {
            let extra = need - weight.count
            weight.append(contentsOf: [Float](repeating: 0, count: extra))
            for c in 0..<channels { acc[c].append(contentsOf: [Float](repeating: 0, count: extra)) }
        }
    }

    private func trimInput() {
        // Eingang wird noch für Ausschnitte um künftige Marken und als Ersatz für unbelegte Stellen gebraucht
        let keepFrom = min(accBase, (marks.first ?? 0)) - 2 * maxPeriod
        let drop = keepFrom - inputBase
        if drop > 16_384 {
            for c in 0..<channels { input[c].removeFirst(drop) }
            inputBase += drop
        }
    }

    // MARK: Ausgang

    /// Fertige Frames (für keinen künftigen Ausschnitt mehr nötig).
    public var availableFrames: Int {
        let final = finished && nextSynthesis >= totalInput ? totalInput : min(totalInput, nextSynthesis - maxPeriod - 1)
        return max(0, final - accBase)
    }

    /// Liest bis zu `maxFrames` fertige Frames.
    public func pull(into dest: [UnsafeMutablePointer<Float>], maxFrames: Int) -> Int {
        let n = min(maxFrames, availableFrames)
        guard n > 0 else { return 0 }
        ensureAccumulator(until: accBase + n)
        for i in 0..<n {
            let w = weight[i]
            let abs = accBase + i
            for c in 0..<channels {
                if w > 0.05 {
                    dest[c][i] = acc[c][i] / w
                } else if abs >= inputBase && abs < inputEnd {
                    dest[c][i] = input[c][abs - inputBase]     // unbelegt: Original
                } else {
                    dest[c][i] = 0
                }
            }
        }
        weight.removeFirst(n)
        for c in 0..<channels { acc[c].removeFirst(n) }
        accBase += n
        totalOutput += n
        trimInput()
        return n
    }

    /// Ende erreicht und alles gelesen.
    public var isDrained: Bool { finished && totalOutput >= totalInput }
}
