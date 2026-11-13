import Foundation

// Tonhöhen-, Stimmungs- und Tonarterkennung für „Titel bearbeiten“ (reine Logik, auch unter Linux getestet).

/// Musikalische Hilfsrechnungen (gleichstufige Stimmung).
public enum MusicMath {
    public static let noteNames = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "H"]

    /// MIDI-Notennummer (gebrochen) einer Frequenz bei Kammerton `reference` (A4 = 69).
    public static func midi(_ frequency: Double, reference: Double = 440) -> Double {
        69 + 12 * log2(frequency / reference)
    }

    public static func frequency(midi: Double, reference: Double = 440) -> Double {
        reference * pow(2, (midi - 69) / 12)
    }

    /// Cent-Abstand zweier Frequenzen.
    public static func cents(_ f: Double, relativeTo g: Double) -> Double { 1200 * log2(f / g) }

    /// Faktor für die Umstimmung von Kammerton `from` auf `to` (z. B. 440 → 432: 0,98182).
    public static func retuneFactor(from: Double, to: Double) -> Double { to / from }
}

/// Tonleiter für Auto-Tune.
public enum MusicScale: String, Codable, CaseIterable, Sendable {
    case chromatic, major, minor

    public var label: String {
        switch self {
        case .chromatic: return "Chromatisch (alle Halbtöne)"
        case .major: return "Dur"
        case .minor: return "Moll"
        }
    }

    /// Stufen (Halbtöne über dem Grundton).
    public var degrees: [Int] {
        switch self {
        case .chromatic: return Array(0..<12)
        case .major: return [0, 2, 4, 5, 7, 9, 11]
        case .minor: return [0, 2, 3, 5, 7, 8, 10]
        }
    }

    /// Nächster Ton der Tonleiter (MIDI, ganzzahlig) zu einer gebrochenen MIDI-Zahl.
    public func nearestNote(to midi: Double, key: Int) -> Double {
        let allowed = Set(degrees)
        var best = midi.rounded()
        var bestDist = Double.infinity
        let center = Int(midi.rounded())
        for cand in (center - 3)...(center + 3) {
            let rel = ((cand - key) % 12 + 12) % 12
            guard allowed.contains(rel) else { continue }
            let dist = abs(Double(cand) - midi)
            if dist < bestDist { bestDist = dist; best = Double(cand) }
        }
        return best
    }
}

/// Grundfrequenz-Erkennung nach McLeod („MPM“, normierte Autokorrelation) für einstimmige Signale.
public final class PitchDetector {
    public let sampleRate: Double
    public let windowSize: Int
    public let minFrequency: Double
    public let maxFrequency: Double
    private let fft: RealFFT
    private var buf: [Double]
    private var re: [Double]
    private var im: [Double]
    private var acf: [Double]

    public init(sampleRate: Double, windowSize: Int = 1024, minFrequency: Double = 60, maxFrequency: Double = 1100) {
        self.sampleRate = sampleRate
        self.windowSize = windowSize
        self.minFrequency = minFrequency
        self.maxFrequency = maxFrequency
        var n = 1
        while n < windowSize * 2 { n <<= 1 }
        fft = RealFFT(n: n)
        buf = Array(repeating: 0, count: n)
        re = Array(repeating: 0, count: n / 2 + 1)
        im = Array(repeating: 0, count: n / 2 + 1)
        acf = Array(repeating: 0, count: n)
    }

    /// Grundfrequenz (Hz) und Klarheit (0…1) des Fensters ab `start` (mindestens `windowSize` Werte); nil = stimmlos/zu leise.
    public func detect(_ x: UnsafePointer<Float>, minimumClarity: Double = 0.8) -> (frequency: Double, clarity: Double)? {
        let w = windowSize
        let n = buf.count
        var energy = 0.0
        for i in 0..<w { let v = Double(x[i]); buf[i] = v; energy += v * v }
        for i in w..<n { buf[i] = 0 }
        guard energy / Double(w) > 1e-7 else { return nil }   // ≈ −70 dBFS
        buf.withUnsafeBufferPointer { b in
            re.withUnsafeMutableBufferPointer { r in
                im.withUnsafeMutableBufferPointer { m in fft.forward(b.baseAddress!, r.baseAddress!, m.baseAddress!) }
            }
        }
        for k in 0..<re.count { re[k] = re[k] * re[k] + im[k] * im[k]; im[k] = 0 }
        re.withUnsafeBufferPointer { r in
            im.withUnsafeBufferPointer { m in
                acf.withUnsafeMutableBufferPointer { a in fft.inverse(r.baseAddress!, m.baseAddress!, a.baseAddress!) }
            }
        }
        // m(τ) = Σ x_j² + x_{j+τ}² über die Überlappung
        let minLag = max(2, Int(sampleRate / maxFrequency))
        let maxLag = min(w - 2, Int(sampleRate / minFrequency))
        guard maxLag > minLag + 2 else { return nil }
        var mTerm = 2 * acf[0]
        var nsdf = [Double](repeating: 0, count: maxLag + 2)
        for tau in 0...(maxLag + 1) {
            if tau > 0 {
                let a = buf[tau - 1], b = buf[w - tau]
                mTerm -= a * a + b * b
            }
            nsdf[tau] = mTerm > 1e-12 ? 2 * acf[tau] / mTerm : 0
        }
        // Schlüsselmaxima nach den positiven Nulldurchgängen
        var peaks: [(Int, Double)] = []
        var tau = minLag
        while tau < maxLag && nsdf[tau] > 0 { tau += 1 }   // ersten positiven Bereich überspringen
        while tau < maxLag {
            while tau < maxLag && nsdf[tau] <= 0 { tau += 1 }
            var best = tau, bestVal = -1.0
            while tau < maxLag && nsdf[tau] > 0 {
                if nsdf[tau] > bestVal { bestVal = nsdf[tau]; best = tau }
                tau += 1
            }
            if bestVal > 0 { peaks.append((best, bestVal)) }
        }
        guard let highest = peaks.map(\.1).max(), highest >= minimumClarity else { return nil }
        guard let chosen = peaks.first(where: { $0.1 >= 0.9 * highest }) else { return nil }
        // Parabel durch die drei Werte um das Maximum
        let t = chosen.0
        let y0 = nsdf[t - 1], y1 = nsdf[t], y2 = nsdf[t + 1]
        let denom = y0 - 2 * y1 + y2
        let shift = abs(denom) > 1e-12 ? 0.5 * (y0 - y2) / denom : 0
        let lag = Double(t) + max(-0.5, min(0.5, shift))
        let f = sampleRate / lag
        guard f >= minFrequency, f <= maxFrequency else { return nil }
        return (f, chosen.1)
    }
}

/// Einfache Dezimierung um Faktor `factor` mit zwei Tiefpässen (für die Tonhöhenerkennung).
public final class Decimator {
    public let factor: Int
    private let lowPass: BiquadChain
    private var phase = 0

    public init(sampleRate: Double, factor: Int) {
        self.factor = max(1, factor)
        let cutoff = sampleRate / Double(2 * max(1, factor)) * 0.8
        // zwei Butterworth-Tiefpässe (Hochpass-Formel gespiegelt über RBJ-Tiefpass)
        let lp = Decimator.lowPass(cutoff, fs: sampleRate)
        lowPass = BiquadChain(channels: 1, stages: [lp, lp])
    }

    static func lowPass(_ f: Double, fs: Double) -> BiquadCoefficients {
        let w0 = 2 * Double.pi * f / fs
        let c = cos(w0)
        let alpha = sin(w0) / (2 * 0.70710678)
        let a0 = 1 + alpha
        return BiquadCoefficients(b0: (1 - c) / 2 / a0, b1: (1 - c) / a0, b2: (1 - c) / 2 / a0, a1: -2 * c / a0, a2: (1 - alpha) / a0)
    }

    /// Filtert `mono` (wird verändert) und hängt jeden `factor`-ten Wert an `out`.
    public func process(_ mono: UnsafeMutablePointer<Float>, frames: Int, into out: inout [Float]) {
        lowPass.process([mono], frames: frames)
        for i in 0..<frames {
            if phase == 0 { out.append(mono[i]) }
            phase = (phase + 1) % factor
        }
    }
}

/// Erkennt Stimmung (Kammerton) und Tonart eines (mehrstimmigen) Musikstücks aus Spektralspitzen.
///
/// Stimmung: Abweichung jeder deutlichen Spitze (100 Hz–4 kHz) vom nächsten Halbton, als Kreismittel über alle
/// Spitzen (gewichtet mit der Stärke) → z. B. +7,9 Cent ≙ A4 = 442 Hz.
/// Tonart: Chroma (Tonklassen-Energie) mit den Profilen von Krumhansl und Kessler verglichen.
public final class MusicAnalyzer {
    public let sampleRate: Double
    private let n: Int
    private let fft: RealFFT
    private var window: [Double]
    private var frame: [Double]
    private var re: [Double]
    private var im: [Double]
    private var mag: [Double]
    // Kreismittel der Abweichungen
    private var sumCos = 0.0
    private var sumSin = 0.0
    private var sumWeight = 0.0
    /// Spitzen: (Frequenz, Stärke) für das Chroma nach Kenntnis der Stimmung.
    private var peaks: [(Double, Double)] = []
    public private(set) var framesAnalyzed = 0

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        var size = 8192
        if sampleRate > 60_000 { size = 16_384 }
        n = size
        fft = RealFFT(n: size)
        window = (0..<size).map { 0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(size)) }
        frame = Array(repeating: 0, count: size)
        re = Array(repeating: 0, count: size / 2 + 1)
        im = Array(repeating: 0, count: size / 2 + 1)
        mag = Array(repeating: 0, count: size / 2 + 1)
    }

    /// Fensterlänge in Frames (so viele Werte braucht `analyze`).
    public var frameSize: Int { n }

    /// Analysiert ein Fenster (Mono, `frameSize` Werte).
    public func analyze(_ x: UnsafePointer<Float>) {
        for i in 0..<n { frame[i] = Double(x[i]) * window[i] }
        frame.withUnsafeBufferPointer { b in
            re.withUnsafeMutableBufferPointer { r in
                im.withUnsafeMutableBufferPointer { m in fft.forward(b.baseAddress!, r.baseAddress!, m.baseAddress!) }
            }
        }
        var maxMag = 0.0
        for k in 0..<mag.count {
            let v = (re[k] * re[k] + im[k] * im[k]).squareRoot()
            mag[k] = v
            if v > maxMag { maxMag = v }
        }
        guard maxMag > 1e-6 else { return }
        framesAnalyzed += 1
        let binHz = sampleRate / Double(n)
        let lo = max(2, Int(100 / binHz)), hi = min(mag.count - 2, Int(4000 / binHz))
        let threshold = maxMag * 0.05
        var k = lo
        var local: [(Double, Double)] = []
        while k <= hi {
            let v = mag[k]
            if v > threshold && v > mag[k - 1] && v >= mag[k + 1] && v > mag[k - 2] && v >= mag[k + 2] {
                // Parabel in dB für die genaue Frequenz
                let a = log(max(mag[k - 1], 1e-12)), b = log(v), c = log(max(mag[k + 1], 1e-12))
                let d = a - 2 * b + c
                let p = abs(d) > 1e-12 ? 0.5 * (a - c) / d : 0
                let f = (Double(k) + max(-0.5, min(0.5, p))) * binHz
                local.append((f, v / maxMag))
            }
            k += 1
        }
        // höchstens die 20 stärksten Spitzen je Fenster
        local.sort { $0.1 > $1.1 }
        for (f, w) in local.prefix(20) {
            let dev = MusicMath.midi(f) - MusicMath.midi(f).rounded()   // −0,5 … 0,5 Halbton
            let angle = 2 * Double.pi * dev
            sumCos += w * cos(angle)
            sumSin += w * sin(angle)
            sumWeight += w
            peaks.append((f, w))
        }
    }

    /// Abweichung der Stimmung in Cent gegenüber A4 = 440 Hz und Verlässlichkeit (0…1).
    public var tuningOffsetCents: (cents: Double, confidence: Double)? {
        guard sumWeight > 0 else { return nil }
        let angle = atan2(sumSin, sumCos)
        let r = (sumCos * sumCos + sumSin * sumSin).squareRoot() / sumWeight
        return (angle / (2 * Double.pi) * 100, r)
    }

    /// Erkannter Kammerton (Hz) oder nil.
    public var referenceFrequency: Double? {
        guard let t = tuningOffsetCents, t.confidence > 0.2 else { return nil }
        return 440 * pow(2, t.cents / 1200)
    }

    // Krumhansl-Kessler-Profile
    static let majorProfile = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    static let minorProfile = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    /// Tonart: Grundton (0 = C … 11 = H), Dur/Moll und Korrelation (−1…1).
    public var key: (tonic: Int, scale: MusicScale, correlation: Double)? {
        guard !peaks.isEmpty else { return nil }
        let reference = referenceFrequency ?? 440
        var chroma = [Double](repeating: 0, count: 12)
        for (f, w) in peaks {
            let m = MusicMath.midi(f, reference: reference).rounded()
            let pc = ((Int(m) % 12) + 12) % 12
            chroma[pc] += w
        }
        func corr(_ a: [Double], _ b: [Double]) -> Double {
            let ma = a.reduce(0, +) / 12, mb = b.reduce(0, +) / 12
            var num = 0.0, da = 0.0, db = 0.0
            for i in 0..<12 { num += (a[i] - ma) * (b[i] - mb); da += (a[i] - ma) * (a[i] - ma); db += (b[i] - mb) * (b[i] - mb) }
            return da > 0 && db > 0 ? num / (da * db).squareRoot() : 0
        }
        var best: (Int, MusicScale, Double) = (0, .major, -2)
        for tonic in 0..<12 {
            let rotated = (0..<12).map { chroma[($0 + tonic) % 12] }
            let cMaj = corr(rotated, Self.majorProfile)
            let cMin = corr(rotated, Self.minorProfile)
            if cMaj > best.2 { best = (tonic, .major, cMaj) }
            if cMin > best.2 { best = (tonic, .minor, cMin) }
        }
        return best
    }
}
