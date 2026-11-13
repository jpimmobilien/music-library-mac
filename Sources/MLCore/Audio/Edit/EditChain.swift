import Foundation

/// Einstellungen der Bearbeitungskette in technischen Größen (Bedienwerte → `TrackEdit` in MLStudio).
public struct EditChainParameters: Equatable, Sendable {
    /// Hochpass gegen Rumpeln/Gleichanteil (Hz), nil = aus.
    public var highPassHz: Double?
    /// Equalizer: 10 Bänder (dB) bei `EqBands.frequencies`, Bandbreite in Oktaven wie im Player.
    public var bandGains: [Float]
    public var bassDb: Float
    /// Auto-Tune (nil = aus).
    public var autoTune: AutoTuneProcessor.Settings?
    /// Tempofaktor (1 = Original).
    public var speed: Double
    /// Tonhöhenfaktor (Halbtöne, Cent und Umstimmung zusammen; 1 = Original).
    public var pitch: Double
    /// Verstärkung in dB (Lautstärke + Lautheitsangleich).
    public var gainDb: Double
    /// Höchstpegel (linear) für den Begrenzer, nil = kein Begrenzer.
    public var limiterCeiling: Float?

    public init(highPassHz: Double? = nil, bandGains: [Float] = Array(repeating: 0, count: EqBands.count), bassDb: Float = 0,
                autoTune: AutoTuneProcessor.Settings? = nil, speed: Double = 1, pitch: Double = 1, gainDb: Double = 0,
                limiterCeiling: Float? = nil) {
        self.highPassHz = highPassHz
        self.bandGains = bandGains
        self.bassDb = bassDb
        self.autoTune = autoTune
        self.speed = speed
        self.pitch = pitch
        self.gainDb = gainDb
        self.limiterCeiling = limiterCeiling
    }

    /// Ändert nichts am Signal.
    public var isNeutral: Bool {
        highPassHz == nil && bandGains.allSatisfy { $0 == 0 } && bassDb == 0 && autoTune == nil
            && abs(speed - 1) < 1e-6 && abs(pitch - 1) < 1e-6 && gainDb == 0 && limiterCeiling == nil
    }

    /// Filterstufen (Hochpass, 10 Bänder, Bass-Kuhschwanz) für eine Abtastrate.
    public func filterStages(sampleRate fs: Double) -> [BiquadCoefficients] {
        var stages: [BiquadCoefficients] = []
        if let hp = highPassHz, hp > 0 {
            stages.append(.highPass(frequency: hp, sampleRate: fs))
            stages.append(.highPass(frequency: hp, sampleRate: fs))   // 4. Ordnung (24 dB/Oktave)
        }
        // Dieselben Filter wie Equalizer und Bassregler des Players (Güte 1,41, Kuhschwanz bei 100 Hz)
        for (i, g) in bandGains.prefix(EqBands.count).enumerated() where g != 0 {
            if let k = PeakingFilter.coefficients(frequency: Double(EqBands.frequencies[i]), gainDb: Double(g), q: EqBands.q, sampleRate: fs) {
                stages.append(k)
            }
        }
        if bassDb != 0 {
            stages.append(LowShelfFilter.biquad(frequency: AudioEffectsSettings.bassFrequency, gainDb: Double(bassDb), sampleRate: fs))
        }
        return stages
    }

    /// Länge des Ergebnisses für `inputFrames` Eingangs-Frames.
    public func outputFrames(forInput inputFrames: Int64) -> Int64 {
        abs(speed - 1) < 1e-6 ? inputFrames : Int64((Double(inputFrames) / speed).rounded())
    }
}

/// Bearbeitungskette für ganze Dateien (offline): Hochpass → Equalizer → Auto-Tune → Tempo/Tonhöhe
/// (`TimePitchEngine`, Phase-Vocoder in Android-Qualität) → Verstärkung → Begrenzer.
///
/// Streaming: `push` beliebig große Blöcke, `finish` am Ende; fertige Blöcke kommen über `emit` (planar, je Kanal ein
/// Zeiger, gültig nur während des Aufrufs). Gesamtlänge = Eingang / Tempo (exakt gerundet).
public final class EditChain {
    public let sampleRate: Double
    public let channels: Int
    public let parameters: EditChainParameters
    private let filters: BiquadChain
    private let autoTune: AutoTuneProcessor?
    private let timePitch: TimePitchEngine?
    private let limiter: PeakLimiter?
    private let gain: Float
    private var limiterSkip: Int
    // Feste Arbeitspuffer je Kanal (im init angelegt, im deinit freigegeben)
    private let work: [UnsafeMutablePointer<Float>]
    private let stage: [UnsafeMutablePointer<Float>]
    private let tp: [UnsafeMutablePointer<Float>]
    private let tpCapacity = 4096 * 4 + 64
    private let inputPointers: UnsafeMutablePointer<UnsafePointer<Float>>
    private let outputPointers: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private static let chunk = 4096
    public private(set) var inputFrames: Int64 = 0
    public private(set) var outputFrames: Int64 = 0
    private var finished = false

    public init(sampleRate: Double, channels: Int, parameters: EditChainParameters) {
        precondition(sampleRate > 0 && channels >= 1)
        self.sampleRate = sampleRate
        self.channels = channels
        self.parameters = parameters
        filters = BiquadChain(channels: channels, stages: parameters.filterStages(sampleRate: sampleRate))
        autoTune = parameters.autoTune.map { AutoTuneProcessor(sampleRate: sampleRate, channels: channels, settings: $0) }
        let speed = parameters.speed, pitch = parameters.pitch
        if abs(speed - 1) > 1e-6 || abs(pitch - 1) > 1e-6 {
            timePitch = TimePitchEngine(sampleRate: sampleRate, channels: channels, speed: Float(speed), pitch: Float(pitch),
                                        maxFramesPerCall: Self.chunk)
        } else {
            timePitch = nil
        }
        limiter = parameters.limiterCeiling.map { PeakLimiter(sampleRate: sampleRate, channels: channels, ceiling: $0) }
        limiterSkip = limiter?.latency ?? 0
        gain = Float(pow(10, parameters.gainDb / 20))
        func buffers(_ n: Int) -> [UnsafeMutablePointer<Float>] {
            (0..<channels).map { _ in
                let p = UnsafeMutablePointer<Float>.allocate(capacity: n)
                p.initialize(repeating: 0, count: n)
                return p
            }
        }
        work = buffers(Self.chunk)
        stage = buffers(Self.chunk)
        tp = buffers(tpCapacity)
        inputPointers = .allocate(capacity: channels)
        outputPointers = .allocate(capacity: channels)
    }

    deinit {
        for p in work + stage + tp { p.deallocate() }
        inputPointers.deallocate()
        outputPointers.deallocate()
    }

    public typealias Emit = ([UnsafeMutablePointer<Float>], Int) throws -> Void

    /// Nimmt `frames` Frames entgegen (`data[c]` = Kanal c; bei weniger Zeigern als Kanälen wird der letzte wiederholt).
    public func push(_ data: [UnsafePointer<Float>], frames: Int, emit: Emit) throws {
        precondition(!finished, "push nach finish")
        var offset = 0
        while offset < frames {
            let n = min(Self.chunk, frames - offset)
            for c in 0..<channels {
                (work[c]).update(from: data[min(c, data.count - 1)] + offset, count: n)
            }
            inputFrames += Int64(n)
            filters.process(work, frames: n)
            try afterFilters(work, frames: n, emit: emit)
            offset += n
        }
    }

    /// Ende: Rest ausgeben.
    public func finish(emit: Emit) throws {
        guard !finished else { return }
        finished = true
        if let autoTune {
            autoTune.finish()
            try drainAutoTune(autoTune, emit: emit)
        }
        if let timePitch {
            timePitch.queueEndOfStream()
            try drainTimePitch(timePitch, emit: emit)
        }
        if let limiter {
            // Verzögerung des Begrenzers mit Stille ausspülen
            var remaining = limiter.latency
            while remaining > 0 {
                let n = min(remaining, Self.chunk)
                for c in 0..<channels { stage[c].update(repeating: 0, count: n) }
                try finalStage(stage, frames: n, emit: emit, flushing: true)
                remaining -= n
            }
        }
    }

    // MARK: Stufen

    private func afterFilters(_ ptrs: [UnsafeMutablePointer<Float>], frames n: Int, emit: Emit) throws {
        if let autoTune {
            autoTune.push(ptrs.map { UnsafePointer($0) }, frames: n)
            try drainAutoTune(autoTune, emit: emit)
        } else {
            try afterAutoTune(ptrs, frames: n, emit: emit)
        }
    }

    private func drainAutoTune(_ at: AutoTuneProcessor, emit: Emit) throws {
        while true {
            let k = at.pull(into: stage, maxFrames: Self.chunk)
            if k == 0 { break }
            try afterAutoTune(stage, frames: k, emit: emit)
        }
    }

    private func afterAutoTune(_ ptrs: [UnsafeMutablePointer<Float>], frames n: Int, emit: Emit) throws {
        if let timePitch {
            for c in 0..<channels { inputPointers[c] = UnsafePointer(ptrs[c]) }
            timePitch.queueInput(inputPointers, frames: n)
            try drainTimePitch(timePitch, emit: emit)
        } else {
            try finalStage(ptrs, frames: n, emit: emit, flushing: false)
        }
    }

    private func drainTimePitch(_ engine: TimePitchEngine, emit: Emit) throws {
        for c in 0..<channels { outputPointers[c] = tp[c] }
        while engine.availableFrames > 0 {
            let k = engine.read(outputPointers, maxFrames: min(tpCapacity, engine.availableFrames))
            if k == 0 { break }
            try finalStage(tp, frames: k, emit: emit, flushing: false)
        }
    }

    private func finalStage(_ ptrs: [UnsafeMutablePointer<Float>], frames n: Int, emit: Emit, flushing: Bool) throws {
        guard n > 0 else { return }
        if gain != 1 && !flushing {
            for c in 0..<channels { let p = ptrs[c]; for i in 0..<n { p[i] *= gain } }
        }
        var start = 0
        if let limiter {
            limiter.process(ptrs, frames: n)
            if limiterSkip > 0 {
                start = min(limiterSkip, n)
                limiterSkip -= start
            }
        }
        let count = n - start
        guard count > 0 else { return }
        let out = start == 0 ? ptrs : ptrs.map { $0 + start }
        outputFrames += Int64(count)
        try emit(out, count)
    }
}
