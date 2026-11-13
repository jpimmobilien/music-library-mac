import Foundation

/// Weitere Filterformen (Audio EQ Cookbook) zu `BiquadCoefficients` (siehe EqualizerModel.swift).
extension BiquadCoefficients {
    private static func normalized(_ b0: Double, _ b1: Double, _ b2: Double, _ a0: Double, _ a1: Double, _ a2: Double) -> BiquadCoefficients {
        BiquadCoefficients(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    /// Glockenfilter mit Bandbreite in Oktaven (wie `AVAudioUnitEQFilterParameters.bandwidth`).
    public static func peaking(frequency f: Double, gainDb: Double, bandwidthOctaves bw: Double, sampleRate fs: Double) -> BiquadCoefficients {
        guard gainDb != 0, f > 0, f < fs / 2 else { return .identity }
        let a = pow(10, gainDb / 40)
        let w0 = 2 * Double.pi * f / fs
        let alpha = sin(w0) * sinh(log(2) / 2 * bw * w0 / sin(w0))
        let c = cos(w0)
        return normalized(1 + alpha * a, -2 * c, 1 - alpha * a, 1 + alpha / a, -2 * c, 1 - alpha / a)
    }

    /// Kuhschwanz unten (Steilheit S = 1).
    public static func lowShelf(frequency f: Double, gainDb: Double, sampleRate fs: Double) -> BiquadCoefficients {
        guard gainDb != 0, f > 0, f < fs / 2 else { return .identity }
        let a = pow(10, gainDb / 40)
        let w0 = 2 * Double.pi * f / fs
        let c = cos(w0)
        let alpha = sin(w0) / 2 * sqrt(2)   // S = 1
        let sq = 2 * sqrt(a) * alpha
        return normalized(a * ((a + 1) - (a - 1) * c + sq), 2 * a * ((a - 1) - (a + 1) * c), a * ((a + 1) - (a - 1) * c - sq),
                          (a + 1) + (a - 1) * c + sq, -2 * ((a - 1) + (a + 1) * c), (a + 1) + (a - 1) * c - sq)
    }

    /// Kuhschwanz oben mit Güte Q (für die K-Bewertung).
    public static func highShelf(frequency f: Double, gainDb: Double, q: Double, sampleRate fs: Double) -> BiquadCoefficients {
        let a = pow(10, gainDb / 40)
        let w0 = 2 * Double.pi * f / fs
        let c = cos(w0)
        let alpha = sin(w0) / (2 * q)
        let sq = 2 * sqrt(a) * alpha
        return normalized(a * ((a + 1) + (a - 1) * c + sq), -2 * a * ((a - 1) + (a + 1) * c), a * ((a + 1) + (a - 1) * c - sq),
                          (a + 1) - (a - 1) * c + sq, 2 * ((a - 1) - (a + 1) * c), (a + 1) - (a - 1) * c - sq)
    }

    /// Hochpass 2. Ordnung (Q = 0,7071 → Butterworth).
    public static func highPass(frequency f: Double, q: Double = 0.70710678, sampleRate fs: Double) -> BiquadCoefficients {
        let w0 = 2 * Double.pi * f / fs
        let c = cos(w0)
        let alpha = sin(w0) / (2 * q)
        return normalized((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + alpha, -2 * c, 1 - alpha)
    }
}

/// Biquad-Kette für planare Float-Kanäle (Transponierte Direktform II, Zustand in Double). Nicht threadsicher.
public final class BiquadChain {
    public let channels: Int
    public private(set) var stages: [BiquadCoefficients]
    /// Zustand je Stufe und Kanal: (z1, z2).
    private var z1: [Double]
    private var z2: [Double]

    public init(channels: Int, stages: [BiquadCoefficients]) {
        precondition(channels >= 1)
        self.channels = channels
        self.stages = stages.filter { $0 != .identity }
        z1 = Array(repeating: 0, count: self.stages.count * channels)
        z2 = Array(repeating: 0, count: self.stages.count * channels)
    }

    public var isEmpty: Bool { stages.isEmpty }

    public func reset() {
        for i in z1.indices { z1[i] = 0; z2[i] = 0 }
    }

    /// Filtert `frames` Frames in-place (`data[c]` = Kanal c).
    public func process(_ data: [UnsafeMutablePointer<Float>], frames: Int) {
        guard !stages.isEmpty, frames > 0 else { return }
        for c in 0..<min(channels, data.count) {
            let p = data[c]
            for (s, k) in stages.enumerated() {
                let idx = s * channels + c
                var s1 = z1[idx], s2 = z2[idx]
                let b0 = k.b0, b1 = k.b1, b2 = k.b2, a1 = k.a1, a2 = k.a2
                for i in 0..<frames {
                    let x = Double(p[i])
                    let y = b0 * x + s1
                    s1 = b1 * x - a1 * y + s2
                    s2 = b2 * x - a2 * y
                    p[i] = Float(y)
                }
                z1[idx] = s1
                z2[idx] = s2
            }
        }
    }
}
