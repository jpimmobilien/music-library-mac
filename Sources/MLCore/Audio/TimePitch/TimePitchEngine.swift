import Foundation

/// Tempo- und Tonhöhenänderung in hoher Qualität (reine Logik, ohne Apple-Frameworks) –
/// Portierung von `audio/TimePitchEngine.kt` der Android-App.
///
/// Geschwindigkeit (`speed`) und Tonhöhe (`pitch`) sind Faktoren (Tonhöhe: 2^(Halbtöne/12)). Zerlegung:
///  1. Zeitdehnung um α = pitch / speed mit `PhaseVocoder` (nur wenn α ≠ 1),
///  2. Abtastraten-Umrechnung mit `SincResampler` um Faktor pitch (nur wenn pitch ≠ 1).
/// Ergebnis: Tempo = speed, Tonhöhe = pitch.
///
///  - Modus „Schallplatte“ (speed = pitch): nur Schritt 2 – reines, hochwertiges Resampling, kein
///    Time-Stretching und damit keine Stretching-Artefakte.
///  - Modus „Tonhöhe“ (speed = 1): Schritt 1 + 2.
///
/// Die Ausgabe ist zeitlich ausgerichtet: Ausgangs-Frame j entspricht der Eingangsposition j·speed.
///
/// Unterschiede zu Android:
/// - Float32 ein und aus, planare Kanäle (je Kanal ein Zeiger). Keine 16-Bit-Wandlung, **kein Dither**.
/// - Der Ausgangsbegrenzer bleibt (Schwelle 0,989 ≈ −0,1 dBFS, sofortiger Einsatz, 80 ms Erholung, weiches
///   Knie ab 0,97): Phase-Vocoder und Sinc-Filter können Spitzen über den Eingangspegel heben; der Begrenzer
///   hält den Ausgang sicher unter 1,0 (höchstens ≈ 0,987). Unterhalb von 0,97 ist er wirkungslos (Faktor 1).
/// - Ohne Änderung (`isPassthrough`) werden die Daten bitgenau durchgereicht (auch ohne Begrenzer) – wie
///   der inaktive Audioprozessor unter Android.
/// - Alle Puffer haben eine feste, im `init` berechnete Größe: `queueInput`, `read`, `reset` fordern keinen
///   Speicher an, sperren nicht und machen keine Ein-/Ausgabe (echtzeit-sicher). Dafür gilt: je Aufruf von
///   `queueInput` werden intern höchstens `maxFramesPerCall` Frames auf einmal verarbeitet (größere Blöcke
///   werden geteilt), und die Ausgabe muss regelmäßig mit `read` abgeholt werden (spätestens nach Eingängen
///   von insgesamt `maxFramesPerCall` Frames). Überläufe würden in `overflowFrames` gezählt.
public final class TimePitchEngine {
    static let limit = 0.989
    static let knee = 0.97
    /// Blockgröße der Nullen beim Ausklingen (wie Android).
    static let endChunk = 4096

    public let sampleRate: Double
    public let channels: Int
    public let speed: Float
    public let pitch: Float
    /// Höchstmenge je interner Verarbeitung (größere Eingänge werden geteilt).
    public let maxFramesPerCall: Int

    let stretch: Double
    let vocoder: PhaseVocoder?
    let resampler: SincResampler?
    /// Fertige Ausgabe (nach dem Begrenzer).
    let output: FloatFifo

    private var inputFramesTotal: Int64 = 0
    private var outputFramesProduced: Int64 = 0
    private var endOfStream = false

    // Ausgangsbegrenzer (Phase-Vocoder und Sinc-Filter können Spitzen leicht anheben)
    private var limiterGain = 1.0
    private let releaseCoeff: Double

    private let zeros: UnsafeMutablePointer<Float>
    private let zeroPointers: UnsafeMutablePointer<UnsafePointer<Float>>

    /// - Parameters:
    ///   - sampleRate: Abtastrate in Hz (44 100, 48 000 …).
    ///   - channels: Anzahl Kanäle (≥ 1).
    ///   - speed: Tempofaktor (1 = Original).
    ///   - pitch: Tonhöhenfaktor 2^(Halbtöne/12) (1 = Original).
    ///   - maxFramesPerCall: Höchstmenge je interner Verarbeitung (Bemessung der Puffer).
    ///   - fftSizeOverride: Nur für Tests – feste FFT-Länge statt der Wahl nach Abtastrate.
    public convenience init(sampleRate: Double, channels: Int, speed: Float, pitch: Float,
                            maxFramesPerCall: Int = 4096, fftSizeOverride: Int = 0) {
        self.init(sampleRate: sampleRate, channels: channels, speed: speed, pitch: pitch,
                  maxFramesPerCall: maxFramesPerCall, fftSizeOverride: fftSizeOverride, extraOutputCapacity: 0)
    }

    /// - Parameter extraOutputCapacity: zusätzlicher Platz im Ausgang (für `TimePitchProcessor`, der dort
    ///   seine feste Verzögerung puffert).
    init(sampleRate: Double, channels: Int, speed: Float, pitch: Float,
         maxFramesPerCall: Int, fftSizeOverride: Int, extraOutputCapacity: Int) {
        precondition(channels >= 1, "Mindestens ein Kanal")
        precondition(sampleRate > 0 && speed > 0 && pitch > 0, "Abtastrate und Faktoren müssen positiv sein")
        precondition(maxFramesPerCall >= 1)
        self.sampleRate = sampleRate
        self.channels = channels
        self.speed = speed
        self.pitch = pitch
        self.maxFramesPerCall = maxFramesPerCall
        let rate = Int(sampleRate.rounded())
        let stretch = Double(pitch) / Double(speed)
        self.stretch = stretch
        let useVocoder = abs(stretch - 1.0) > 1e-4
        let useResampler = abs(pitch - 1) > 1e-4
        // Ein Block der Größe `chunk` ist das Größte, was auf einmal in die Kette geht (Ausklingen: 4096).
        let chunk = max(maxFramesPerCall, TimePitchEngine.endChunk)

        var stageOut = chunk // Höchstmenge, die Stufe 1 je Aufruf weitergibt
        if useVocoder {
            let v = PhaseVocoder(sampleRate: rate, channels: channels, stretch: stretch, maxPushFrames: chunk,
                                 fftSizeOverride: fftSizeOverride)
            vocoder = v
            // je verarbeitetem Analyse-Frame entstehen synthesisHop Samples; je Block höchstens chunk/Ha + 2 Frames
            stageOut = Int(ceil(Double(chunk) * stretch)) + 2 * v.synthesisHop + 16
        } else {
            vocoder = nil
        }
        var produced = stageOut
        if useResampler {
            let r = SincResampler(channels: channels, step: Double(pitch), maxPushFrames: stageOut)
            resampler = r
            produced = Int(ceil(Double(r.input.capacity) / Double(pitch))) + 16
        } else {
            resampler = nil
        }
        let lag = TimePitchEngine.lagBound(sampleRate: rate, speed: Double(speed), pitch: Double(pitch),
                                           fftSizeOverride: fftSizeOverride)
        let capacity = 2 * produced + Int(ceil((lag + Double(chunk)) / Double(speed))) + extraOutputCapacity + 64
        output = FloatFifo(channels: channels, capacity: capacity)
        releaseCoeff = 1.0 - exp(-1.0 / (0.080 * Double(rate)))

        zeros = .allocate(capacity: TimePitchEngine.endChunk)
        zeros.initialize(repeating: 0, count: TimePitchEngine.endChunk)
        zeroPointers = .allocate(capacity: channels)
        zeroPointers.initialize(repeating: UnsafePointer(zeros), count: channels)
    }

    deinit {
        zeros.deallocate()
        zeroPointers.deallocate()
    }

    /// Ohne Tempo- und Tonhöhenänderung: Daten werden bitgenau durchgereicht.
    public var isPassthrough: Bool { vocoder == nil && resampler == nil }

    /// Obergrenze (in Eingangs-Frames) für den Rückstand der Ausgabe gegenüber dem Eingang:
    /// nach jedem `queueInput` gilt inputFrames − outputFrames·speed < lagBound.
    ///
    /// Herleitung: Der Phase-Vocoder verarbeitet Frame k, sobald round(k·Ha) + n ≤ n/2 + P Eingangs-Frames
    /// vorliegen, und gibt danach alles vor k·Hs − n/2 aus; der Resampler braucht halfTaps Samples Vorschau.
    /// Daraus folgt Rückstand < n/2 + 0,5 + (n/2 + halfTaps + 1)/α (beide Stufen).
    static func lagBound(sampleRate: Int, speed: Double, pitch: Double, fftSizeOverride: Int = 0) -> Double {
        let stretch = pitch / speed
        let useVocoder = abs(stretch - 1.0) > 1e-4
        let useResampler = abs(Float(pitch) - 1) > 1e-4
        let n = Double(fftSizeOverride > 0 ? fftSizeOverride : PhaseVocoder.fftSize(sampleRate: sampleRate))
        let h = useResampler ? Double(SincResampler.halfTaps(step: pitch)) : 0
        switch (useVocoder, useResampler) {
        case (true, true): return n / 2 + 0.5 + (n / 2 + h + 1) / stretch
        case (true, false): return n / 2 + 0.5 + (n / 2 + 1) / stretch
        case (false, true): return h + 1
        case (false, false): return 0
        }
    }

    /// Verwirft alle gepufferten Daten und beginnt neu (z. B. nach dem Spulen oder am Titelanfang).
    /// Filtertabellen und Puffer werden wiederverwendet – keine neuen Speicheranforderungen.
    public func reset() {
        vocoder?.reset()
        resampler?.reset()
        output.clear()
        inputFramesTotal = 0
        outputFramesProduced = 0
        endOfStream = false
        limiterGain = 1.0
    }

    /// Eingang: `frames` Frames je Kanal; `input[c]` zeigt auf Kanal c. Größere Blöcke als
    /// `maxFramesPerCall` werden intern geteilt.
    public func queueInput(_ input: UnsafePointer<UnsafePointer<Float>>, frames: Int) {
        queueInput(input, offset: 0, frames: frames)
    }

    /// Wie `queueInput(_:frames:)`, gelesen ab Frame `offset` jedes Kanals.
    public func queueInput(_ input: UnsafePointer<UnsafePointer<Float>>, offset: Int, frames: Int) {
        var done = 0
        while done < frames {
            let n = min(frames - done, maxFramesPerCall)
            inputFramesTotal += Int64(n)
            feed(input, offset: offset + done, frames: n)
            done += n
        }
    }

    private func feed(_ src: UnsafePointer<UnsafePointer<Float>>, offset: Int, frames: Int) {
        let before = output.frames
        if let v = vocoder {
            v.push(src, offset: offset, frames: frames)
            if let r = resampler {
                v.process(into: r.input)
                r.process(into: output)
            } else {
                v.process(into: output)
            }
        } else if let r = resampler {
            r.push(src, offset: offset, frames: frames)
            r.process(into: output)
        } else {
            // Durchreichen: bitgenau, ohne Begrenzer
            output.append(src, offset: offset, count: frames)
            outputFramesProduced += Int64(output.frames - before)
            return
        }
        let added = output.frames - before
        if added > 0 { limit(from: before, count: added) }
        outputFramesProduced += Int64(added)
    }

    /// Spitzenbegrenzer mit weichem Knie (wie Android, ohne 16-Bit-Wandlung und Dither), in-place auf den
    /// neu angehängten Frames.
    private func limit(from first: Int, count: Int) {
        let threshold = TimePitchEngine.limit
        let knee = TimePitchEngine.knee
        let channels = self.channels
        var gain = limiterGain
        for f in first..<(first + count) {
            var peak = 0.0
            for c in 0..<channels {
                let a = abs(Double(output.pointer(c, f).pointee))
                if a > peak { peak = a }
            }
            let desired = peak > threshold ? threshold / peak : 1.0
            gain = desired < gain ? desired : gain + (desired - gain) * releaseCoeff
            for c in 0..<channels {
                let p = output.pointer(c, f)
                var x = Double(p.pointee) * gain
                if x > knee || x < -knee { x = TimePitchEngine.softClip(x) }
                p.pointee = Float(x)
            }
        }
        limiterGain = gain
    }

    @inline(__always) static func softClip(_ x: Double) -> Double {
        let a = abs(x)
        let shaped = knee + (1.0 - knee) * tanh((a - knee) / (1.0 - knee))
        return x < 0 ? -shaped : shaped
    }

    /// Ende des Datenstroms: Rest ausgeben, so dass insgesamt genau inputFrames / speed Frames
    /// entstehen (wichtig für die korrekte Positionsanzeige). Vorher sollte die bisherige Ausgabe gelesen sein.
    public func queueEndOfStream() {
        if endOfStream { return }
        endOfStream = true
        let expected = Int64((Double(inputFramesTotal) / Double(speed)).rounded())
        var guardCount = 0
        while outputFramesProduced < expected && guardCount < 10_000 {
            feed(zeroPointers, offset: 0, frames: TimePitchEngine.endChunk)
            guardCount += 1
        }
        // Überschuss (Nachlauf aus den Nullen) abschneiden
        let excess = outputFramesProduced - expected
        if excess > 0 {
            output.truncate(max(0, output.frames - Int(excess)))
            outputFramesProduced = expected
        }
    }

    /// Verfügbare Ausgangs-Frames.
    public var availableFrames: Int { output.frames }

    /// Liest bis zu `maxFrames` Frames nach `dest` (`dest[c]` = Kanal c) und gibt die Anzahl zurück.
    public func read(_ dest: UnsafePointer<UnsafeMutablePointer<Float>>, maxFrames: Int) -> Int {
        output.read(into: dest, offset: 0, maxFrames: maxFrames)
    }

    /// Wie `read(_:maxFrames:)`, geschrieben ab Frame `offset` jedes Kanals.
    public func read(_ dest: UnsafePointer<UnsafeMutablePointer<Float>>, offset: Int, maxFrames: Int) -> Int {
        output.read(into: dest, offset: offset, maxFrames: maxFrames)
    }

    /// Verwirft bis zu `frames` Ausgangs-Frames ungelesen.
    func discardOutput(_ frames: Int) -> Int {
        let n = min(frames, output.frames)
        output.drop(n)
        return n
    }

    public var isEnded: Bool { endOfStream && output.frames == 0 }

    /// Bisher übergebene Eingangs-Frames.
    public var inputFrames: Int64 { inputFramesTotal }

    /// Bisher erzeugte Ausgangs-Frames (inkl. noch nicht gelesener).
    public var outputFrames: Int64 { outputFramesProduced }

    /// Diagnose: wegen zu kleiner Puffer verworfene Frames (bleibt bei bestimmungsgemäßem Gebrauch 0).
    public var overflowFrames: Int {
        output.overflowFrames + (vocoder?.overflowFrames ?? 0) + (resampler?.input.overflowFrames ?? 0)
    }

    /// Bequeme Offline-Verarbeitung eines ganzen Signals inklusive Ausklingen (fordert Speicher an – nicht für
    /// den Audio-Thread). `input[c]` ist Kanal c; das Ergebnis hat genau round(Länge / speed) Frames je Kanal.
    public func processAll(_ input: [[Float]], blockSize: Int = 4096) -> [[Float]] {
        precondition(input.count == channels, "Kanalzahl passt nicht")
        let frames = input.first?.count ?? 0
        let inPlanes = input.map { ch -> UnsafeMutablePointer<Float> in
            let p = UnsafeMutablePointer<Float>.allocate(capacity: max(1, ch.count))
            p.initialize(from: ch, count: ch.count)
            return p
        }
        let inPtrs = UnsafeMutablePointer<UnsafePointer<Float>>.allocate(capacity: channels)
        for c in 0..<channels { inPtrs[c] = UnsafePointer(inPlanes[c]) }
        let chunkOut = max(4096, blockSize)
        let outPlanes = (0..<channels).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: chunkOut) }
        let outPtrs = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: channels)
        for c in 0..<channels { outPtrs[c] = outPlanes[c] }
        defer {
            inPlanes.forEach { $0.deallocate() }
            outPlanes.forEach { $0.deallocate() }
            inPtrs.deallocate()
            outPtrs.deallocate()
        }
        var result = [[Float]](repeating: [], count: channels)
        func drain() {
            while true {
                let got = read(outPtrs, maxFrames: chunkOut)
                if got == 0 { break }
                for c in 0..<channels { result[c].append(contentsOf: UnsafeBufferPointer(start: outPlanes[c], count: got)) }
            }
        }
        var pos = 0
        while pos < frames {
            let n = min(blockSize, maxFramesPerCall, frames - pos)
            queueInput(UnsafePointer(inPtrs), offset: pos, frames: n)
            pos += n
            drain()
        }
        queueEndOfStream()
        drain()
        return result
    }
}
