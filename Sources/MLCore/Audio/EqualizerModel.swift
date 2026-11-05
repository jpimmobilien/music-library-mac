import Foundation

/// Die zehn Frequenzbänder des Equalizers (Oktavabstände, ISO-Mittenfrequenzen).
public enum EqBands {
    public static let frequencies: [Float] = [31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
    public static let labels = ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    public static let count = 10
    public static let minDb: Float = -12
    public static let maxDb: Float = 12
    /// Güte je Band (≈ eine Oktave Bandbreite).
    public static let q: Double = 1.41

    public static func clamp(_ db: Float) -> Float { min(max(db, minDb), maxDb) }
}

/// Equalizer-Voreinstellung. Die Werte verändern den Klang tatsächlich (Verstärkung je Band in dB).
public struct EqPreset: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let gains: [Float]

    public init(id: String, name: String, gains: [Float]) {
        precondition(gains.count == EqBands.count, "Ein Preset braucht \(EqBands.count) Bänder")
        self.id = id
        self.name = name
        self.gains = gains
    }
}

public enum EqPresets {
    public static let flat = EqPreset(id: "flat", name: "Neutral", gains: Array(repeating: 0, count: 10))
    public static let bassBoost = EqPreset(id: "bass", name: "Bass Boost", gains: [6, 5.5, 4.5, 3, 1.5, 0, 0, 0, 0, 0])
    public static let rock = EqPreset(id: "rock", name: "Rock", gains: [4.5, 3.5, 2, 0.5, -1, -1, 0.5, 2, 3, 3.5])
    public static let pop = EqPreset(id: "pop", name: "Pop", gains: [-1, 0, 1.5, 3, 3.5, 2.5, 1, 0, -0.5, -1])
    public static let classical = EqPreset(id: "classical", name: "Klassik", gains: [3, 2.5, 1.5, 0.5, 0, 0, 0, 1, 2, 3])
    public static let jazz = EqPreset(id: "jazz", name: "Jazz", gains: [3, 2, 1, 1.5, -1, -1, 0, 1, 2, 2.5])
    public static let vocal = EqPreset(id: "vocal", name: "Gesang", gains: [-2, -1.5, -1, 0.5, 2.5, 3.5, 3, 1.5, 0, -1])
    public static let electronic = EqPreset(id: "electronic", name: "Elektronisch", gains: [5, 4, 1.5, 0, -1.5, 1, 0.5, 1.5, 4, 4.5])

    public static let all: [EqPreset] = [flat, bassBoost, rock, pop, classical, jazz, vocal, electronic]

    public static func byID(_ id: String?) -> EqPreset? { all.first { $0.id == id } }

    /// Passt `gains` exakt zu einer Voreinstellung? (sonst „Eigene Einstellung“)
    public static func matching(_ gains: [Float]) -> EqPreset? {
        all.first { p in gains.count >= p.gains.count && p.gains.indices.allSatisfy { p.gains[$0] == gains[$0] } }
    }
}

/// Biquad-Koeffizienten nach dem „Audio EQ Cookbook“ (R. Bristow-Johnson), normiert auf a0 = 1.
public struct BiquadCoefficients: Hashable, Sendable {
    public var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double

    public init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2
    }

    /// Durchgang (kein Filter).
    public static let identity = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

    /// Als Array [b0, b1, b2, a1, a2] (wie in Kotlin).
    public var array: [Double] { [b0, b1, b2, a1, a2] }

    /// Betrag des Frequenzgangs in dB bei `f` (Abtastrate `sampleRate`).
    public func magnitudeDb(at f: Double, sampleRate: Double) -> Double {
        let w = 2.0 * Double.pi * f / sampleRate
        let c1 = cos(w), s1 = sin(w), c2 = cos(2 * w), s2 = sin(2 * w)
        let nr = b0 + b1 * c1 + b2 * c2, ni = -(b1 * s1 + b2 * s2)
        let dr = 1.0 + a1 * c1 + a2 * c2, di = -(a1 * s1 + a2 * s2)
        return 10.0 * log10((nr * nr + ni * ni) / (dr * dr + di * di))
    }
}

/// Peaking-Filter eines Equalizer-Bands (Portierung von `PeakingFilter.set` aus `audio/EffectsEngine.kt`).
public enum PeakingFilter {
    /// Koeffizienten; `nil` = Filter inaktiv (0 dB, Frequenz ≥ 0,45 × Abtastrate oder ungültige Abtastrate).
    public static func coefficients(frequency: Double, gainDb: Double, q: Double, sampleRate: Double) -> BiquadCoefficients? {
        if gainDb == 0.0 || frequency >= 0.45 * sampleRate || sampleRate <= 0 { return nil }
        let a = pow(10.0, gainDb / 40.0)
        let w0 = 2.0 * Double.pi * frequency / sampleRate
        let alpha = sin(w0) / (2.0 * q)
        let cosW0 = cos(w0)
        let a0 = 1.0 + alpha / a
        return BiquadCoefficients(
            b0: (1.0 + alpha * a) / a0,
            b1: (-2.0 * cosW0) / a0,
            b2: (1.0 - alpha * a) / a0,
            a1: (-2.0 * cosW0) / a0,
            a2: (1.0 - alpha / a) / a0
        )
    }
}

/// Tiefen-Kuhschwanzfilter („Low Shelf“, Audio EQ Cookbook, Flankensteilheit S = 1) für den Bassregler
/// (Portierung von `LowShelfFilter.coefficients` aus `audio/EffectsEngine.kt`): hebt bzw. senkt alles
/// unterhalb von ~60 Hz um den vollen Wert, bei 100 Hz um die Hälfte; ab 500 Hz praktisch ohne Wirkung.
public enum LowShelfFilter {
    /// Normierte Koeffizienten [b0, b1, b2, a1, a2].
    public static func coefficients(frequency: Double, gainDb: Double, sampleRate: Double) -> [Double] {
        biquad(frequency: frequency, gainDb: gainDb, sampleRate: sampleRate).array
    }

    public static func biquad(frequency: Double, gainDb: Double, sampleRate: Double) -> BiquadCoefficients {
        let a = pow(10.0, gainDb / 40.0)
        let w0 = 2.0 * Double.pi * frequency / sampleRate
        let cosW0 = cos(w0)
        let alpha = sin(w0) / 2.0 * sqrt(2.0) // S = 1
        let sqrtA2alpha = 2.0 * sqrt(a) * alpha
        let a0 = (a + 1) + (a - 1) * cosW0 + sqrtA2alpha
        return BiquadCoefficients(
            b0: a * ((a + 1) - (a - 1) * cosW0 + sqrtA2alpha) / a0,
            b1: 2.0 * a * ((a - 1) - (a + 1) * cosW0) / a0,
            b2: a * ((a + 1) - (a - 1) * cosW0 - sqrtA2alpha) / a0,
            a1: -2.0 * ((a - 1) + (a + 1) * cosW0) / a0,
            a2: ((a + 1) + (a - 1) * cosW0 - sqrtA2alpha) / a0
        )
    }
}

/// Frequenzgänge der Filter (Betrag in dB) – für die Begrenzung der Bassanhebung und die Anzeige.
/// Gleiche Formeln wie die Filter selbst.
public enum EqResponse {
    /// Bezugsabtastrate für die Berechnung (bei tiefen Frequenzen praktisch unabhängig davon).
    static let fs = 48_000.0

    public static func peakingDb(_ f: Double, f0: Double, gainDb: Double, q: Double) -> Double {
        if gainDb == 0.0 { return 0.0 }
        // Wie Kotlin: ohne die 0,45-Grenze der Filter (Anzeige/Begrenzung).
        let a = pow(10.0, gainDb / 40.0)
        let w0 = 2.0 * Double.pi * f0 / fs
        let alpha = sin(w0) / (2.0 * q)
        let a0 = 1.0 + alpha / a
        return BiquadCoefficients(
            b0: (1.0 + alpha * a) / a0, b1: -2.0 * cos(w0) / a0, b2: (1.0 - alpha * a) / a0,
            a1: -2.0 * cos(w0) / a0, a2: (1.0 - alpha / a) / a0
        ).magnitudeDb(at: f, sampleRate: fs)
    }

    public static func lowShelfDb(_ f: Double, f0: Double, gainDb: Double) -> Double {
        if gainDb == 0.0 { return 0.0 }
        return LowShelfFilter.biquad(frequency: f0, gainDb: gainDb, sampleRate: fs).magnitudeDb(at: f, sampleRate: fs)
    }

    /// Gesamtanhebung des 10-Band-Equalizers bei `f` (Summe der Bänder in dB).
    public static func equalizerDb(_ f: Double, bands: [Float]) -> Double {
        var sum = 0.0
        for i in 0..<min(EqBands.count, bands.count) {
            sum += peakingDb(f, f0: Double(EqBands.frequencies[i]), gainDb: Double(bands[i]), q: EqBands.q)
        }
        return sum
    }

    /// Prüffrequenzen im Bassbereich (20–160 Hz, logarithmisch).
    public static let bassFrequencies: [Double] = (0..<16).map { 20.0 * pow(2.0, Double($0) * 3.0 / 15.0) }
}

/// Einstellungen der Audio-Kette (Portierung von `AudioEffectsSettings`). Werden live übernommen.
///
/// - `volume`: App-Lautstärke: 1,0 = 100 % (normaler Pegel), bis `maxVolume` = digitale Verstärkung.
/// - `autoHeadroom`: senkt bei angehobenen Bändern den Vorverstärker um die Hälfte der größten Anhebung,
///   damit der Limiter seltener eingreifen muss.
/// - `bassDb`: Bassregler (−12 … +12 dB, 0 = neutral). Eigener Tiefen-Kuhschwanzfilter bei 100 Hz,
///   unabhängig vom Schalter des 10-Band-Equalizers. Anhebungen werden zusammen mit den Bassbändern des
///   Equalizers auf insgesamt `maxBassTotalDb` begrenzt (keine doppelte Bassverstärkung).
public struct AudioEffectsSettings: Hashable, Sendable {
    public var eqEnabled: Bool
    public var bandGains: [Float]
    public var volume: Float
    public var autoHeadroom: Bool
    public var bassDb: Float

    public static let maxVolume: Float = 3
    public static let minVolume: Float = 0
    public static let minBassDb: Float = -12
    public static let maxBassDb: Float = 12
    /// Höchste gemeinsame Bassanhebung von Equalizer und Bassregler.
    public static let maxBassTotalDb: Float = 12
    /// Mittenfrequenz des Bass-Kuhschwanzfilters (halbe Wirkung).
    public static let bassFrequency: Double = 100.0

    public init(eqEnabled: Bool = true, bandGains: [Float] = EqPresets.flat.gains, volume: Float = 1, autoHeadroom: Bool = true, bassDb: Float = 0) {
        self.eqEnabled = eqEnabled
        self.bandGains = bandGains
        self.volume = volume
        self.autoHeadroom = autoHeadroom
        self.bassDb = bassDb
    }

    public var activePreset: EqPreset? { EqPresets.matching(bandGains) }
    public var effectiveBands: [Float] { eqEnabled ? bandGains : EqPresets.flat.gains }
    public var isEqNeutral: Bool { effectiveBands.allSatisfy { $0 == 0 } }

    /// Größte Anhebung des Equalizers im Bassbereich (20–160 Hz), in dB (≥ 0).
    public var equalizerBassBoostDb: Float {
        let bands = effectiveBands
        if bands.allSatisfy({ $0 == 0 }) { return 0 }
        let peak = EqResponse.bassFrequencies.map { EqResponse.equalizerDb($0, bands: bands) }.max() ?? 0
        return Float(max(0.0, peak))
    }

    /// Tatsächlich wirksamer Bass: Absenkungen immer voll; Anhebungen nur so weit, dass Equalizer und
    /// Bassregler zusammen höchstens `maxBassTotalDb` anheben (Spielraum auf 0,5 dB abgerundet).
    public var effectiveBassDb: Float {
        let b = min(max(bassDb, Self.minBassDb), Self.maxBassDb)
        if b <= 0 { return b }
        let room = (max(Self.maxBassTotalDb - equalizerBassBoostDb, 0) * 2).rounded(.down) / 2
        return min(b, room)
    }

    /// Ist der Bassregler durch die Bassanhebung des Equalizers begrenzt?
    public var bassLimited: Bool { bassDb > 0 && effectiveBassDb < bassDb }

    public var isToneNeutral: Bool { isEqNeutral && effectiveBassDb == 0 }

    /// Vorverstärkung in dB durch die automatische Aussteuerung (≤ 0).
    public var headroomDb: Float {
        let bands = effectiveBands
        var boost = max(0, bands.max() ?? 0)
        let bass = effectiveBassDb
        if bass > 0 {
            // Bassregler: Gesamtanhebung im Bassbereich berücksichtigen (Equalizer + Kuhschwanz)
            let low = EqResponse.bassFrequencies.map { f in
                EqResponse.equalizerDb(f, bands: bands) + EqResponse.lowShelfDb(f, f0: Self.bassFrequency, gainDb: Double(bass))
            }.max() ?? 0
            boost = max(boost, Float(low))
        }
        return (autoHeadroom && boost > 0) ? -0.5 * boost : 0
    }

    /// Lineare Gesamtverstärkung vor dem Limiter.
    public var linearGain: Double { Double(volume) * pow(10.0, Double(headroomDb) / 20.0) }

    /// Band setzen (begrenzt, auf 0,5 dB gerundet).
    public func withBand(_ index: Int, _ db: Float) -> AudioEffectsSettings {
        guard bandGains.indices.contains(index) else { return self }
        var copy = self
        copy.bandGains[index] = Float(JvmMath.roundToInt(EqBands.clamp(db) * 2)) / 2
        return copy
    }

    public func withPreset(_ preset: EqPreset) -> AudioEffectsSettings {
        var copy = self
        copy.bandGains = preset.gains
        copy.eqEnabled = true
        return copy
    }

    /// Bassregler setzen (begrenzt, auf 0,5 dB gerundet).
    public func withBass(_ db: Float) -> AudioEffectsSettings {
        var copy = self
        copy.bassDb = Float(JvmMath.roundToInt(min(max(db, Self.minBassDb), Self.maxBassDb) * 2)) / 2
        return copy
    }
}

extension AudioEffectsSettings: Codable {
    private enum CodingKeys: String, CodingKey { case eqEnabled, bandGains, volume, autoHeadroom, bassDb }

    /// Tolerant wie `SettingsStore.load` der Android-App: falsche Bandanzahl → neutral, Werte begrenzt.
    public init(from decoder: Decoder) throws {
        let d = AudioEffectsSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eqEnabled = ((try? c.decodeIfPresent(Bool.self, forKey: .eqEnabled)) ?? nil) ?? d.eqEnabled
        if let bands = (try? c.decodeIfPresent([Float].self, forKey: .bandGains)) ?? nil,
           bands.count == EqBands.count, bands.allSatisfy(\.isFinite) {
            bandGains = bands.map(EqBands.clamp)
        } else {
            bandGains = d.bandGains
        }
        let v = ((try? c.decodeIfPresent(Float.self, forKey: .volume)) ?? nil) ?? d.volume
        volume = v.isFinite ? min(max(v, Self.minVolume), Self.maxVolume) : d.volume
        autoHeadroom = ((try? c.decodeIfPresent(Bool.self, forKey: .autoHeadroom)) ?? nil) ?? d.autoHeadroom
        let b = ((try? c.decodeIfPresent(Float.self, forKey: .bassDb)) ?? nil) ?? d.bassDb
        bassDb = b.isFinite ? min(max(b, Self.minBassDb), Self.maxBassDb) : d.bassDb
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(eqEnabled, forKey: .eqEnabled)
        try c.encode(bandGains, forKey: .bandGains)
        try c.encode(volume, forKey: .volume)
        try c.encode(autoHeadroom, forKey: .autoHeadroom)
        try c.encode(bassDb, forKey: .bassDb)
    }
}
