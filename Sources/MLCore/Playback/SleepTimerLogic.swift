import Foundation

/// Zustand des Sleep-Timers. `endsAt` ist eine monotone Uhrzeit in Millisekunden (z. B. Systemlaufzeit).
/// `endOfTrack` = „Am Ende des Titels“ anhalten (dann gilt keine Uhrzeit).
public struct SleepTimerState: Hashable, Codable, Sendable {
    public var endsAt: Int64
    public var totalMs: Int64
    public var endOfTrack: Bool

    public init(endsAt: Int64, totalMs: Int64, endOfTrack: Bool = false) {
        self.endsAt = endsAt
        self.totalMs = totalMs
        self.endOfTrack = endOfTrack
    }
}

/// Sleep-Timer (Portierung von `playback/SleepTimerLogic.kt`). In den letzten `fadeMs` Millisekunden
/// wird die Lautstärke sanft ausgeblendet, dann stoppt die Wiedergabe.
public enum SleepTimerLogic {
    public static let presetMinutes = [15, 30, 45, 60, 90]
    public static let minMinutes = 1
    public static let maxMinutes = 12 * 60
    public static let fadeMs: Int64 = 10_000

    public static func start(nowElapsed: Int64, minutes: Int) -> SleepTimerState {
        let m = min(max(minutes, minMinutes), maxMinutes)
        let total = Int64(m) * 60_000
        return SleepTimerState(endsAt: nowElapsed + total, totalMs: total)
    }

    /// Sleep-Timer „Am Ende des Titels“.
    public static func endOfTrack() -> SleepTimerState {
        SleepTimerState(endsAt: Int64.max, totalMs: 0, endOfTrack: true)
    }

    /// Restzeit in ms; `nil` ohne Timer oder bei „Am Ende des Titels“.
    public static func remainingMs(_ state: SleepTimerState?, nowElapsed: Int64) -> Int64? {
        guard let state, !state.endOfTrack else { return nil }
        return max(state.endsAt - nowElapsed, 0)
    }

    public static func isExpired(_ state: SleepTimerState?, nowElapsed: Int64) -> Bool {
        guard let state else { return false }
        return !state.endOfTrack && nowElapsed >= state.endsAt
    }

    /// Lautstärkefaktor 1 → 0 in den letzten Sekunden (gleichmäßig wahrgenommen: quadratisch).
    public static func fadeFactor(_ state: SleepTimerState?, nowElapsed: Int64) -> Float {
        guard let remaining = remainingMs(state, nowElapsed: nowElapsed) else { return 1 }
        if remaining >= fadeMs { return 1 }
        let x = Float(remaining) / Float(fadeMs)
        return min(max(x * x, 0), 1)
    }

    /// Zeit bis zur nächsten Prüfung: im Ausblendbereich häufiger, sonst sekündlich.
    public static func nextCheckDelayMs(_ state: SleepTimerState?, nowElapsed: Int64) -> Int64 {
        guard let remaining = remainingMs(state, nowElapsed: nowElapsed) else { return 1_000 }
        if remaining <= 0 { return 0 }
        if remaining <= fadeMs { return 100 }
        return max(min(1_000, remaining - fadeMs), 50)
    }
}

/// Pitch-Changer: zwei Modi.
public enum PitchMode: String, CaseIterable, Codable, Hashable, Sendable {
    /// Modus A: Tonhöhe ändern, Tempo bleibt (auf dem Mac: `AVAudioUnitTimePitch`). Zusätzlich lässt sich
    /// das Tempo unabhängig ändern (Tonhöhe bleibt).
    case key = "KEY"
    /// Modus B: Tonhöhe und Tempo gemeinsam – wie eine Schallplatte mit anderer Drehzahl (reines Resampling,
    /// auf dem Mac: `AVAudioUnitVarispeed`).
    case varispeed = "VARISPEED"

    public var label: String {
        switch self {
        case .key: return "Tonhöhe"
        case .varispeed: return "Schallplatte"
        }
    }

    public var description: String {
        switch self {
        case .key: return "Tonhöhe ändern, Tempo bleibt erhalten"
        case .varispeed: return "Tonhöhe und Tempo ändern sich gemeinsam"
        }
    }
}

/// Pitch-Einstellung (Portierung von `PitchSettings`, erweitert um ein unabhängiges Tempo).
///
/// - `semitones` im Bereich ±12.
/// - `tempo` (0,5 … 2,0; Standard 1,0) gilt nur im Modus „Tonhöhe“: „Tempo ändern, Tonhöhe bleibt“.
///   Im Modus „Schallplatte“ ergibt sich das Tempo wie bisher aus den Halbtönen (`tempo` wird ignoriert,
///   bleibt aber gespeichert).
public struct PitchSettings: Hashable, Sendable {
    public var mode: PitchMode
    public var semitones: Float
    public var tempo: Float

    public static let minSemitones: Float = -12
    public static let maxSemitones: Float = 12
    public static let minTempo: Float = 0.5
    public static let maxTempo: Float = 2.0
    /// Beschreibung des Tempo-Reglers.
    public static let tempoDescription = "Tempo ändern, Tonhöhe bleibt"
    /// 33⅓ → 45 U/min (Faktor 1,35) bzw. umgekehrt, in Halbtönen.
    public static let rpm33To45: Float = Float(12.0 * log(45.0 / (100.0 / 3.0)) / log(2.0))
    public static let rpm45To33: Float = -rpm33To45

    public init(mode: PitchMode = .key, semitones: Float = 0, tempo: Float = 1) {
        self.mode = mode
        self.semitones = semitones
        self.tempo = tempo
    }

    /// Frequenzfaktor der Halbtöne: 2^(Halbtöne/12).
    public var factor: Float { Float(pow(2.0, Double(semitones) / 12.0)) }

    /// Wiedergabegeschwindigkeit (Media3 `PlaybackParameters.speed`; Mac: `rate`).
    /// Schallplatte: aus den Halbtönen; Tonhöhe: unabhängiges Tempo.
    public var speed: Float { mode == .varispeed ? factor : tempo }

    /// Tonhöhenfaktor (Media3 `PlaybackParameters.pitch`).
    public var pitch: Float { factor }

    /// Tonhöhe in Cent (für `AVAudioUnitTimePitch.pitch`, nur Modus „Tonhöhe“).
    public var pitchCents: Float { semitones * 100 }

    /// Wirksames Tempo (1 = Original).
    public var effectiveTempo: Float { speed }

    /// Klingt der Titel wie das Original (keine Tonhöhen- und keine Tempoänderung)?
    public var isOriginal: Bool { semitones == 0 && (mode == .varispeed || tempo == 1) }

    public func withSemitones(_ value: Float) -> PitchSettings {
        var copy = self
        copy.semitones = min(max(value, PitchSettings.minSemitones), PitchSettings.maxSemitones)
        return copy
    }

    public func withTempo(_ value: Float) -> PitchSettings {
        var copy = self
        copy.tempo = min(max(value, PitchSettings.minTempo), PitchSettings.maxTempo)
        return copy
    }

    public func withMode(_ mode: PitchMode) -> PitchSettings {
        var copy = self
        copy.mode = mode
        return copy
    }
}

extension PitchSettings: Codable {
    private enum CodingKeys: String, CodingKey { case mode, semitones, tempo }

    /// Tolerant: unbekannte/fehlende Werte → Standard, Bereiche werden begrenzt.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let mode = ((try? c.decodeIfPresent(PitchMode.self, forKey: .mode)) ?? nil) ?? .key
        let semitones = ((try? c.decodeIfPresent(Float.self, forKey: .semitones)) ?? nil) ?? 0
        let tempo = ((try? c.decodeIfPresent(Float.self, forKey: .tempo)) ?? nil) ?? 1
        self = PitchSettings(mode: mode)
            .withSemitones(semitones.isFinite ? semitones : 0)
            .withTempo(tempo.isFinite ? tempo : 1)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        try c.encode(semitones, forKey: .semitones)
        try c.encode(tempo, forKey: .tempo)
    }
}
