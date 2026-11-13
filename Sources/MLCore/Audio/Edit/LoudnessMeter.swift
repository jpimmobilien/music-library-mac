import Foundation

/// Lautheit nach ITU-R BS.1770-4 / EBU R 128 (integriert, mit absolutem und relativem Gate) und Spitzenpegel.
///
/// K-Bewertung für jede Abtastrate wie in libebur128 (bei 48 kHz exakt die Koeffizienten der Norm),
/// Blöcke von 400 ms mit 75 % Überlappung, absolutes Gate −70 LUFS, relatives Gate −10 LU.
/// Kanalgewichte 1,0 (Mono, Stereo). Streaming: beliebig große Blöcke nacheinander übergeben.
public final class LoudnessMeter {
    public let sampleRate: Double
    public let channels: Int
    private let filter: BiquadChain
    /// Quadratsummen je 100-ms-Teilblock (Summe über die Kanäle).
    private var subBlocks: [Double] = []
    private var currentSum = 0.0
    private var currentFrames = 0
    private let subBlockFrames: Int
    private var scratch: [UnsafeMutablePointer<Float>] = []
    private var scratchCapacity = 0
    public private(set) var samplePeak: Float = 0
    public private(set) var frames: Int64 = 0

    public init(sampleRate: Double, channels: Int) {
        precondition(sampleRate > 0 && channels >= 1)
        self.sampleRate = sampleRate
        self.channels = channels
        filter = BiquadChain(channels: channels, stages: LoudnessMeter.kWeighting(sampleRate: sampleRate))
        subBlockFrames = max(1, Int((sampleRate * 0.1).rounded()))
    }

    deinit { for p in scratch { p.deallocate() } }

    /// K-Bewertung: Kuhschwanz (+4 dB ab ≈ 1,7 kHz) und Hochpass (≈ 38 Hz), Formeln aus libebur128.
    public static func kWeighting(sampleRate fs: Double) -> [BiquadCoefficients] {
        var f0 = 1681.974450955533
        let g = 3.999843853973347
        var q = 0.7071752369554196
        var k = tan(Double.pi * f0 / fs)
        let vh = pow(10, g / 20)
        let vb = pow(vh, 0.4996667741545416)
        var a0 = 1 + k / q + k * k
        let shelf = BiquadCoefficients(b0: (vh + vb * k / q + k * k) / a0, b1: 2 * (k * k - vh) / a0, b2: (vh - vb * k / q + k * k) / a0,
                                       a1: 2 * (k * k - 1) / a0, a2: (1 - k / q + k * k) / a0)
        f0 = 38.13547087602444
        q = 0.5003270373238773
        k = tan(Double.pi * f0 / fs)
        a0 = 1 + k / q + k * k
        let highPass = BiquadCoefficients(b0: 1, b1: -2, b2: 1, a1: 2 * (k * k - 1) / a0, a2: (1 - k / q + k * k) / a0)
        return [shelf, highPass]
    }

    /// Nimmt `frames` Frames entgegen (unverändert; intern gefiltert).
    public func add(_ data: [UnsafePointer<Float>], frames n: Int) {
        guard n > 0 else { return }
        if n > scratchCapacity {
            for p in scratch { p.deallocate() }
            scratch = (0..<channels).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: n) }
            scratchCapacity = n
        }
        for c in 0..<channels {
            let src = data[min(c, data.count - 1)]
            var peak = samplePeak
            for i in 0..<n { peak = max(peak, abs(src[i])) }
            samplePeak = peak
            scratch[c].update(from: src, count: n)
        }
        let ptrs = scratch
        filter.process(ptrs, frames: n)
        var i = 0
        while i < n {
            let take = min(n - i, subBlockFrames - currentFrames)
            var sum = currentSum
            for c in 0..<channels {
                let p = ptrs[c] + i
                for j in 0..<take { let v = Double(p[j]); sum += v * v }
            }
            currentSum = sum
            currentFrames += take
            i += take
            if currentFrames == subBlockFrames {
                subBlocks.append(currentSum)
                currentSum = 0
                currentFrames = 0
            }
        }
        frames += Int64(n)
    }

    /// Lautheit je 400-ms-Block (LUFS).
    private func blockLoudness() -> [Double] {
        guard subBlocks.count >= 4 else { return [] }
        let blockFrames = Double(subBlockFrames * 4)
        var out: [Double] = []
        out.reserveCapacity(subBlocks.count - 3)
        var running = subBlocks[0] + subBlocks[1] + subBlocks[2]
        for j in 3..<subBlocks.count {
            running += subBlocks[j]
            let z = running / blockFrames
            out.append(-0.691 + 10 * log10(max(z, 1e-30)))
            running -= subBlocks[j - 3]
        }
        return out
    }

    /// Integrierte Lautheit in LUFS (nil, wenn kürzer als 400 ms oder alles unter dem absoluten Gate).
    public var integratedLoudness: Double? {
        let blocks = blockLoudness()
        func energy(_ l: Double) -> Double { pow(10, (l + 0.691) / 10) }
        let absGated = blocks.filter { $0 > -70 }
        guard !absGated.isEmpty else { return nil }
        let meanAbs = absGated.map(energy).reduce(0, +) / Double(absGated.count)
        let relGate = -0.691 + 10 * log10(meanAbs) - 10
        let gated = absGated.filter { $0 > relGate }
        guard !gated.isEmpty else { return nil }
        let mean = gated.map(energy).reduce(0, +) / Double(gated.count)
        return -0.691 + 10 * log10(mean)
    }

    /// Spitzenpegel in dBFS (Abtastwerte).
    public var samplePeakDb: Double { 20 * log10(max(Double(samplePeak), 1e-12)) }
}
