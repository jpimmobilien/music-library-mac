import Foundation
import MLCore

/// Dauerhafte Bearbeitung eines Titels („Titel bearbeiten“, 2.3): alle Einstellungen in Bedienwerten.
/// Die Verarbeitung übernimmt `EditChain` (MLCore) in der Reihenfolge Hochpass → Equalizer → Auto-Tune →
/// Tempo/Tonhöhe → Verstärkung/Lautheit → Begrenzer.
public struct TrackEdit: Codable, Hashable, Sendable {
    // Lautstärke
    /// Verstärkung in dB (−12 … +12); nicht wirksam, solange `normalize` an ist.
    public var gainDb: Double = 0

    // Tempo und Tonhöhe
    /// Tempofaktor (0,5 … 2,0).
    public var speed: Double = 1
    /// Tonhöhe beim Tempowechsel beibehalten (sonst „wie eine Schallplatte“: schneller = höher).
    public var keepPitch: Bool = true
    /// Tonhöhe in Halbtönen (−12 … +12).
    public var semitones: Int = 0
    /// Feinstimmung in Cent (−50 … +50).
    public var cents: Double = 0

    // Stimmung (Kammerton)
    /// Kammerton, auf dem der Titel steht (erkannt oder angenommen).
    public var tuningFrom: Double = 440
    /// Gewünschter Kammerton (z. B. 432).
    public var tuningTo: Double = 440

    // Equalizer
    public var bandGains: [Float] = EqPresets.flat.gains
    public var bassDb: Float = 0

    // Auto-Tune
    public var autoTune = false
    /// Grundton (0 = C … 11 = H).
    public var autoTuneKey = 0
    public var autoTuneScale: MusicScale = .chromatic
    /// 0 … 1 (1 = sofort, „Roboter“).
    public var autoTuneStrength = 0.8

    // Automatische Verbesserung
    public var enhance = false
    /// Rumpeln und Gleichanteil entfernen (Hochpass 25 Hz).
    public var removeRumble = true
    /// Lautheit angleichen (`targetLoudness` LUFS).
    public var normalize = true
    public var targetLoudness: Double = -14
    /// Übersteuerung verhindern (Begrenzer bei −1 dBFS).
    public var preventClipping = true
    /// Stille am Anfang und Ende entfernen.
    public var trimSilence = true

    public init() {}

    /// Tolerant lesen: fehlende oder unlesbare Felder bekommen ihren Standardwert.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback }
        gainDb = v(.gainDb, gainDb)
        speed = v(.speed, speed)
        keepPitch = v(.keepPitch, keepPitch)
        semitones = v(.semitones, semitones)
        cents = v(.cents, cents)
        tuningFrom = v(.tuningFrom, tuningFrom)
        tuningTo = v(.tuningTo, tuningTo)
        bandGains = v(.bandGains, bandGains)
        bassDb = v(.bassDb, bassDb)
        autoTune = v(.autoTune, autoTune)
        autoTuneKey = v(.autoTuneKey, autoTuneKey)
        autoTuneScale = v(.autoTuneScale, autoTuneScale)
        autoTuneStrength = v(.autoTuneStrength, autoTuneStrength)
        enhance = v(.enhance, enhance)
        removeRumble = v(.removeRumble, removeRumble)
        normalize = v(.normalize, normalize)
        targetLoudness = v(.targetLoudness, targetLoudness)
        preventClipping = v(.preventClipping, preventClipping)
        trimSilence = v(.trimSilence, trimSilence)
        self = normalized()
    }

    public static let speedRange: ClosedRange<Double> = 0.5...2.0
    public static let gainRange: ClosedRange<Double> = -12...12
    public static let semitoneRange: ClosedRange<Int> = -12...12
    public static let centsRange: ClosedRange<Double> = -50...50
    public static let tuningRange: ClosedRange<Double> = 400...480
    public static let loudnessTargets: [Double] = [-23, -16, -14, -11]
    /// Höchstpegel des Begrenzers (−1 dBFS).
    public static let ceilingDb = -1.0
    public static let rumbleHz = 25.0

    /// Werte in gültigen Grenzen.
    public func normalized() -> TrackEdit {
        var e = self
        e.gainDb = Self.clamp(gainDb, Self.gainRange, fallback: 0)
        e.speed = Self.clamp(speed, Self.speedRange, fallback: 1)
        e.semitones = min(max(semitones, Self.semitoneRange.lowerBound), Self.semitoneRange.upperBound)
        e.cents = Self.clamp(cents, Self.centsRange, fallback: 0)
        e.tuningFrom = Self.clamp(tuningFrom, Self.tuningRange, fallback: 440)
        e.tuningTo = Self.clamp(tuningTo, Self.tuningRange, fallback: 440)
        var bands = bandGains.prefix(EqBands.count).map { $0.isFinite ? EqBands.clamp($0) : 0 }
        while bands.count < EqBands.count { bands.append(0) }
        e.bandGains = bands
        e.bassDb = bassDb.isFinite ? min(max(bassDb, AudioEffectsSettings.minBassDb), AudioEffectsSettings.maxBassDb) : 0
        e.autoTuneKey = ((autoTuneKey % 12) + 12) % 12
        e.autoTuneStrength = Self.clamp(autoTuneStrength, 0...1, fallback: 0.8)
        e.targetLoudness = Self.clamp(targetLoudness, -30...(-6), fallback: -14)
        return e
    }

    private static func clamp(_ v: Double, _ r: ClosedRange<Double>, fallback: Double) -> Double {
        v.isFinite ? min(max(v, r.lowerBound), r.upperBound) : fallback
    }

    // MARK: Ableitungen

    public var isEqNeutral: Bool { bandGains.allSatisfy { $0 == 0 } && bassDb == 0 }
    public var isTuningNeutral: Bool { abs(tuningTo - tuningFrom) < 0.01 }
    public var isSpeedNeutral: Bool { abs(speed - 1) < 1e-6 }
    public var isPitchNeutral: Bool { semitones == 0 && cents == 0 }
    /// Lautstärke wirkt (nicht durch die Lautheitsangleichung ersetzt).
    public var gainActive: Bool { gainDb != 0 && !(enhance && normalize) }

    /// Ändert nichts am Klang (Beschneiden und Blenden gehören nicht zu `TrackEdit`).
    public var isNeutral: Bool {
        !gainActive && isSpeedNeutral && isPitchNeutral && isTuningNeutral && isEqNeutral && !autoTune && !enhance
    }

    /// Gesamter Tonhöhenfaktor (Halbtöne, Cent, Umstimmung; ohne „Tonhöhe beibehalten“ zusätzlich das Tempo).
    public var pitchFactor: Double {
        var f = pow(2, (Double(semitones) + cents / 100) / 12)
        if !isTuningNeutral { f *= tuningTo / tuningFrom }
        if !keepPitch { f *= speed }
        return f
    }

    /// Länge nach der Bearbeitung.
    public func outputDuration(_ seconds: Double) -> Double { seconds / speed }

    /// Parameter der Bearbeitungskette. `normalizationGainDb`: aus der Messung (nur bei aktiver Lautheitsangleichung).
    public func chainParameters(normalizationGainDb: Double? = nil, forMeasurement: Bool = false) -> EditChainParameters {
        let e = normalized()
        var p = EditChainParameters()
        if e.enhance && e.removeRumble { p.highPassHz = Self.rumbleHz }
        p.bandGains = e.bandGains
        p.bassDb = e.bassDb
        if e.autoTune {
            // Auto-Tune stimmt auf den Kammerton der Quelle: Die Umstimmung folgt danach als Ganzes
            p.autoTune = AutoTuneProcessor.Settings(key: e.autoTuneKey, scale: e.autoTuneScale, strength: e.autoTuneStrength, reference: e.tuningFrom)
        }
        p.speed = e.speed
        p.pitch = e.pitchFactor
        if forMeasurement { return p }
        if e.enhance && e.normalize {
            p.gainDb = normalizationGainDb ?? 0
        } else {
            p.gainDb = e.gainDb
        }
        if e.enhance && e.preventClipping || p.gainDb > 0 || !e.isEqNeutral {
            p.limiterCeiling = Float(pow(10, Self.ceilingDb / 20))
        }
        return p
    }

    /// Braucht die Bearbeitung einen Messdurchgang vorab (Lautheit, Stille)?
    public var needsAnalysisPass: Bool { enhance && (normalize || trimSilence) }

    /// Verstärkung für die Lautheitsangleichung (begrenzt auf ±20 dB).
    public func normalizationGain(measured: Double?) -> Double {
        guard let m = measured, m.isFinite else { return 0 }
        return min(max(targetLoudness - m, -20), 20)
    }

    // MARK: Anzeige

    /// Kurzbeschreibung der wirksamen Änderungen, z. B. „Tempo 1,10× · +2 Halbtöne · 440 → 432 Hz · Equalizer“.
    public var summary: String {
        var parts: [String] = []
        if gainActive { parts.append(String(format: "%+.1f dB", gainDb).replacingOccurrences(of: ".", with: ",")) }
        if !isSpeedNeutral {
            parts.append("Tempo " + Self.decimal(speed, digits: 2) + "×" + (keepPitch ? "" : " (mit Tonhöhe)"))
        }
        if semitones != 0 { parts.append("\(semitones > 0 ? "+" : "−")\(abs(semitones)) Halbt\(abs(semitones) == 1 ? "on" : "öne")") }
        if cents != 0 { parts.append("\(cents > 0 ? "+" : "−")\(Int(abs(cents).rounded())) Cent") }
        if !isTuningNeutral { parts.append("\(Self.decimal(tuningFrom, digits: 1)) → \(Self.decimal(tuningTo, digits: 1)) Hz") }
        if !isEqNeutral { parts.append(EqPresets.matching(bandGains).map { "Equalizer „\($0.name)“" } ?? "Equalizer") }
        if autoTune { parts.append("Auto-Tune \(Self.keyName(autoTuneKey, autoTuneScale))") }
        if enhance {
            var e: [String] = []
            if normalize { e.append("\(Int(targetLoudness)) LUFS") }
            if removeRumble { e.append("Rumpelfilter") }
            if trimSilence { e.append("Stille entfernt") }
            parts.append("Verbessert" + (e.isEmpty ? "" : " (\(e.joined(separator: ", ")))"))
        }
        return parts.joined(separator: " · ")
    }

    /// „C-Dur“, „a-Moll“, „Chromatisch“.
    public static func keyName(_ key: Int, _ scale: MusicScale) -> String {
        let name = MusicMath.noteNames[((key % 12) + 12) % 12]
        switch scale {
        case .chromatic: return "chromatisch"
        case .major: return "\(name)-Dur"
        case .minor: return "\(name.lowercased())-Moll"
        }
    }

    static func decimal(_ v: Double, digits: Int) -> String {
        var s = String(format: "%.\(digits)f", v)
        while s.contains("."), s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s.replacingOccurrences(of: ".", with: ",")
    }
}

/// Ergebnis der Analyse eines Titels für „Titel bearbeiten“.
public struct TrackAnalysis: Hashable, Sendable {
    /// Erkannter Kammerton (Hz) und Verlässlichkeit (0…1).
    public var reference: Double?
    public var referenceConfidence: Double
    /// Tonart (Grundton 0…11, Dur/Moll) und Übereinstimmung (−1…1).
    public var keyTonic: Int?
    public var keyScale: MusicScale?
    public var keyCorrelation: Double
    /// Integrierte Lautheit (LUFS) und Spitzenpegel (dBFS) des Originals.
    public var loudness: Double?
    public var peakDb: Double?
    /// Stille am Anfang und Ende (Sekunden).
    public var leadingSilence: Double
    public var trailingSilence: Double

    public init(reference: Double? = nil, referenceConfidence: Double = 0, keyTonic: Int? = nil, keyScale: MusicScale? = nil,
                keyCorrelation: Double = 0, loudness: Double? = nil, peakDb: Double? = nil, leadingSilence: Double = 0, trailingSilence: Double = 0) {
        self.reference = reference
        self.referenceConfidence = referenceConfidence
        self.keyTonic = keyTonic
        self.keyScale = keyScale
        self.keyCorrelation = keyCorrelation
        self.loudness = loudness
        self.peakDb = peakDb
        self.leadingSilence = leadingSilence
        self.trailingSilence = trailingSilence
    }

    /// „A4 ≈ 442 Hz“ bzw. nil bei unsicherer Erkennung.
    public var referenceText: String? {
        guard let r = reference, referenceConfidence >= 0.3 else { return nil }
        return "≈ \(TrackEdit.decimal(r, digits: 1)) Hz"
    }

    public var keyText: String? {
        guard let t = keyTonic, let s = keyScale, keyCorrelation >= 0.5 else { return nil }
        return TrackEdit.keyName(t, s)
    }
}
