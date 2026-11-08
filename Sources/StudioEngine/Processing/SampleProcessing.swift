import Foundation

// Bearbeitung der Samples zwischen Lesen und Kodieren: Blenden, weiche Begrenzung (keine Übersteuerung),
// Umwandlung in Ganzzahlen mit TPDF-Dither. Reines Swift – auch unter Linux testbar.

/// Ein-/Ausblenden über einen Ausschnitt mit bekannter Länge (in Frames der Quelle).
struct FadePlan {
    /// Länge des Ausschnitts in Frames.
    let totalFrames: Int64
    let fadeInFrames: Int64
    let fadeOutFrames: Int64

    init(totalFrames: Int64, sampleRate: Double, fadeIn: Double, fadeOut: Double) {
        self.totalFrames = max(0, totalFrames)
        var fi = Int64((max(0, fadeIn.isFinite ? fadeIn : 0) * sampleRate).rounded())
        var fo = Int64((max(0, fadeOut.isFinite ? fadeOut : 0) * sampleRate).rounded())
        // Zusammen nie länger als der Ausschnitt (anteilig kürzen)
        if fi + fo > self.totalFrames, fi + fo > 0 {
            let sum = Double(fi + fo)
            fi = Int64((Double(self.totalFrames) * Double(fi) / sum).rounded(.down))
            fo = self.totalFrames - fi
            if fo < 0 { fo = 0 }
        }
        fadeInFrames = fi
        fadeOutFrames = fo
    }

    var isActive: Bool { fadeInFrames > 0 || fadeOutFrames > 0 }

    /// Weiche S-Kurve (Halbkosinus) von 0 nach 1 – ohne Knick am Anfang und am Ende.
    @inline(__always)
    static func curve(_ x: Double) -> Float {
        let t = min(max(x, 0), 1)
        return Float(0.5 - 0.5 * cos(Double.pi * t))
    }

    /// Verstärkung für den Frame `index` (0 = erster Frame des Ausschnitts).
    func gain(at index: Int64) -> Float {
        var g: Float = 1
        if fadeInFrames > 0, index < fadeInFrames {
            g *= Self.curve(Double(index) / Double(fadeInFrames))
        }
        if fadeOutFrames > 0 {
            let remaining = totalFrames - 1 - index
            if remaining < fadeOutFrames {
                g *= Self.curve(Double(max(remaining, 0)) / Double(fadeOutFrames))
            }
        }
        return g
    }

    /// Wendet die Blenden auf `block` an; `startIndex` ist die Position des ersten Frames im Ausschnitt.
    func apply(to block: FloatBlock, startIndex: Int64) {
        guard isActive, block.frames > 0 else { return }
        let n = Int64(block.frames)
        let fadeOutStart = totalFrames - fadeOutFrames
        // Nur Blöcke bearbeiten, die eine Blende berühren
        let touchesIn = fadeInFrames > 0 && startIndex < fadeInFrames
        let touchesOut = fadeOutFrames > 0 && startIndex + n > fadeOutStart
        guard touchesIn || touchesOut else { return }
        for i in 0..<block.frames {
            let idx = startIndex + Int64(i)
            if idx >= fadeInFrames && idx < fadeOutStart { continue }
            let g = gain(at: idx)
            for p in block.channels { p[i] *= g }
        }
    }
}

/// Weiche Begrenzung: Werte bis zur Schwelle bleiben unverändert, darüber werden sie stetig
/// (tanh-Knie) gegen ±1 geführt. Verhindert Übersteuerung nach Umrechnung, Blenden oder Heruntermischen.
enum SoftLimiter {
    static let threshold: Float = 0.96
    /// Größter Ausgabewert: knapp unter Vollaussteuerung (entspricht 32767 bei 16 Bit).
    static let ceiling: Float = 32_767 / 32_768

    /// Gibt `true` zurück, wenn mindestens ein Wert begrenzt wurde.
    @discardableResult
    static func apply(_ p: UnsafeMutablePointer<Float>, count: Int) -> Bool {
        let t = threshold
        let range = ceiling - t
        var touched = false
        for i in 0..<count {
            let x = p[i]
            if x.isNaN { p[i] = 0; touched = true; continue }
            let a = abs(x)
            if a > t {
                let y = min(t + range * tanhf((a - t) / range), ceiling)
                p[i] = x < 0 ? -y : y
                touched = true
            }
        }
        return touched
    }

    @discardableResult
    static func apply(to block: FloatBlock) -> Bool {
        var touched = false
        for p in block.channels where apply(p, count: block.frames) { touched = true }
        return touched
    }
}

/// Schneller Zufallsgenerator (xorshift64*) für den Dither – reproduzierbar, ohne Sperren.
struct DitherNoise {
    private var state: UInt64

    init(seed: UInt64 = 0x9E37_79B9_7F4A_7C15) {
        state = seed == 0 ? 0x2545_F491_4F6C_DD1D : seed
    }

    /// Gleichverteilt in [0, 1).
    @inline(__always)
    mutating func uniform() -> Float {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let r = state &* 0x2545_F491_4F6C_DD1D
        return Float(r >> 40) * (1.0 / 16_777_216.0)
    }

    /// Dreieckförmig verteilt in (−1, 1) – TPDF-Dither mit ±1 LSB.
    @inline(__always)
    mutating func tpdf() -> Float { uniform() - uniform() }
}

/// Umwandlung Float → Ganzzahl (16/24 Bit) mit optionalem TPDF-Dither.
///
/// Skalierung wie Core Audio (Int16 = x · 32768, Int24 = x · 8388608): Werte, die aus 16- oder
/// 24-Bit-Quellen stammen, ergeben ohne Dither wieder genau dieselbe Ganzzahl (bitgenaue Kopie).
struct Quantizer {
    let bits: Int
    let dither: Bool
    private var noise = DitherNoise()
    private let scale: Float
    private let maxValue: Float
    private let minValue: Float

    init(bits: Int, dither: Bool) {
        precondition(bits == 16 || bits == 24, "Nur 16 oder 24 Bit")
        self.bits = bits
        self.dither = dither
        scale = bits == 16 ? 32768 : 8_388_608
        maxValue = scale - 1
        minValue = -scale
    }

    @inline(__always)
    mutating func quantize(_ x: Float) -> Int32 {
        var v = x * scale
        if v.isNaN { v = 0 }
        if dither { v += noise.tpdf() }
        v = v.rounded(.toNearestOrEven)
        if v > maxValue { v = maxValue } else if v < minValue { v = minValue }
        return Int32(v)
    }
}

/// Bytes für unkomprimiertes PCM (WAV: Little Endian, AIFF: Big Endian).
enum PCMPacker {
    /// Schreibt `block` verschachtelt in `out` (wird bei Bedarf vergrößert). Rückgabe: Anzahl Bytes.
    static func pack(_ block: FloatBlock, bits: Int, float: Bool, bigEndian: Bool, quantizer: inout Quantizer?,
                     into out: inout [UInt8]) -> Int {
        let ch = block.channelCount
        let n = block.frames
        let bytesPerSample = bits / 8
        let total = n * ch * bytesPerSample
        if out.count < total { out = [UInt8](repeating: 0, count: total) }
        out.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            var o = 0
            if float {
                for i in 0..<n {
                    for c in 0..<ch {
                        var x = block.channels[c][i]
                        if x.isNaN { x = 0 }
                        let u = x.bitPattern
                        if bigEndian {
                            base[o] = UInt8(truncatingIfNeeded: u >> 24); base[o + 1] = UInt8(truncatingIfNeeded: u >> 16)
                            base[o + 2] = UInt8(truncatingIfNeeded: u >> 8); base[o + 3] = UInt8(truncatingIfNeeded: u)
                        } else {
                            base[o] = UInt8(truncatingIfNeeded: u); base[o + 1] = UInt8(truncatingIfNeeded: u >> 8)
                            base[o + 2] = UInt8(truncatingIfNeeded: u >> 16); base[o + 3] = UInt8(truncatingIfNeeded: u >> 24)
                        }
                        o += 4
                    }
                }
                return
            }
            guard var q = quantizer else { return }
            for i in 0..<n {
                for c in 0..<ch {
                    let v = q.quantize(block.channels[c][i])
                    let u = UInt32(bitPattern: v)
                    if bits == 16 {
                        if bigEndian {
                            base[o] = UInt8(truncatingIfNeeded: u >> 8); base[o + 1] = UInt8(truncatingIfNeeded: u)
                        } else {
                            base[o] = UInt8(truncatingIfNeeded: u); base[o + 1] = UInt8(truncatingIfNeeded: u >> 8)
                        }
                        o += 2
                    } else {
                        if bigEndian {
                            base[o] = UInt8(truncatingIfNeeded: u >> 16); base[o + 1] = UInt8(truncatingIfNeeded: u >> 8)
                            base[o + 2] = UInt8(truncatingIfNeeded: u)
                        } else {
                            base[o] = UInt8(truncatingIfNeeded: u); base[o + 1] = UInt8(truncatingIfNeeded: u >> 8)
                            base[o + 2] = UInt8(truncatingIfNeeded: u >> 16)
                        }
                        o += 3
                    }
                }
            }
            quantizer = q
        }
        return total
    }
}

/// Mono → Stereo (gleiches Signal auf beiden Seiten), sonst unverändert.
enum ChannelAdapter {
    /// Liefert einen Block mit `outChannels` Kanälen. `scratch` wird bei Bedarf wiederverwendet.
    static func adapt(_ block: FloatBlock, to outChannels: Int, scratch: inout FloatBlock?) -> FloatBlock {
        if block.channelCount == outChannels { return block }
        let target: FloatBlock
        if let s = scratch, s.channelCount == outChannels, s.capacity >= block.frames {
            target = s
        } else {
            target = FloatBlock(channels: outChannels, capacity: max(block.capacity, block.frames))
            scratch = target
        }
        let n = block.frames
        if block.channelCount == 1 {
            for c in 0..<outChannels { target.channels[c].update(from: block.channels[0], count: n) }
        } else if outChannels == 1 {
            // Stereo → Mono (wird nur bei ausdrücklichem Wunsch verwendet)
            let scale = 1 / Float(block.channelCount)
            for i in 0..<n {
                var s: Float = 0
                for c in 0..<block.channelCount { s += block.channels[c][i] }
                target.channels[0][i] = s * scale
            }
        } else {
            for c in 0..<outChannels { target.channels[c].update(from: block.channels[min(c, block.channelCount - 1)], count: n) }
        }
        target.frames = n
        return target
    }
}
