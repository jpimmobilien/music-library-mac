import Foundation

/// Tonhöhenänderung für einen Audio-Unit-Render-Block: je Aufruf genau so viele Frames heraus wie hinein,
/// mit fester Verzögerung (`latencyFrames`). Intern `TimePitchEngine` (Phase-Vocoder + Sinc-Resampler,
/// Portierung der Android-Verarbeitung) im Modus „Tonhöhe“: Tempo 1, Tonhöhe = `pitch`.
///
/// Zeitbezug: Ausgangs-Frame t entspricht exakt Eingangs-Frame t − `latencyFrames`. Am Anfang (und nach
/// `reset()`) kommen `latencyFrames` Frames Stille, danach das bearbeitete Signal.
///
/// Echtzeit-Sicherheit: Nach dem `init` fordern `process` und `reset` keinen Speicher an, sperren nicht und
/// machen keine Ein-/Ausgabe. Das `init` dagegen legt Tabellen und Puffer an (≈ 1–1,5 MB bei Stereo) – also
/// außerhalb des Audio-Threads erzeugen und die fertige Instanz übergeben. Nicht threadsicher: eine Instanz
/// wird nur von einem Thread (dem Audio-Thread) benutzt.
///
/// Neue Tonhöhe während der Wiedergabe: neue Instanz außerhalb des Audio-Threads anlegen und übergeben.
/// Wird sie einfach eingewechselt, beginnt sie mit `latencyFrames` Stille (kurze Lücke). Lückenlos geht es
/// mit `process(input:output:frames:crossfadingTo:)`: Die alte Instanz läuft weiter, bis die neue gültige Daten
/// liefert, dann wird über `crossfadeFrames` gleichleistungs-überblendet. Da die Verzögerung für alle Tonhöhen
/// zwischen −12 und +12 Halbtönen (bei gleicher Abtastrate) gleich ist, entsteht dabei kein Zeitsprung.
public final class TimePitchProcessor {
    public let sampleRate: Double
    public let channels: Int
    /// Immer 1 – dieser Prozessor ändert nur die Tonhöhe (gleich viele Frames hinein wie heraus).
    public let speed: Float
    /// Frequenzfaktor 2^(Halbtöne/12).
    public let pitch: Float
    /// Größte Blocklänge je interner Verarbeitung; größere `frames` werden intern geteilt.
    public let maxFramesPerCall: Int
    /// Konstante Verzögerung in Frames (für die Positionsanzeige / Latenzmeldung). 0 beim Durchreichen
    /// (außer mit `delaysWhenNeutral`).
    public let latencyFrames: Int
    /// Ohne Tonhöhenänderung: Die Daten werden bitgenau durchgereicht.
    public let isPassthrough: Bool
    /// Länge der Überblendung bei `process(…crossfadingTo:)` (≈ 50 ms).
    public let crossfadeFrames: Int

    private let engine: TimePitchEngine?
    private var silenceRemaining = 0
    /// Nach einem (nicht vorgesehenen) Unterlauf noch zu verwerfende Ausgangs-Frames, damit der Zeitbezug bleibt.
    private var owedFrames = 0
    /// Seit dem Anfang bzw. `reset()` verarbeitete Frames.
    public private(set) var processedFrames: Int64 = 0
    /// Diagnose: Frames, für die die Verarbeitung (unerwartet) noch nichts geliefert hatte. Bleibt 0.
    public private(set) var underrunFrames: Int = 0

    private let scratch: UnsafeMutablePointer<Float>
    private let scratchPointers: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private let fadeIn: UnsafeMutablePointer<Float>
    private let fadeOut: UnsafeMutablePointer<Float>

    /// - Parameters:
    ///   - sampleRate: Abtastrate in Hz.
    ///   - channels: Anzahl Kanäle (1 oder 2; mehr funktioniert ebenfalls).
    ///   - speed: Muss 1 sein (Tempoänderungen brauchen ungleich viele Frames hinein/heraus →
    ///     `TimePitchEngine` mit `queueInput`/`read`). Andere Werte werden in Debug-Builds gemeldet und ignoriert.
    ///   - pitch: Frequenzfaktor 2^(Halbtöne/12); |pitch − 1| ≤ 0,0001 → Durchreichen.
    ///   - maxFramesPerCall: größte interne Blocklänge (Standard 4096).
    ///   - delaysWhenNeutral: Auch beim Durchreichen um die feste Verzögerung verzögern (bitgenau), damit
    ///     alle Instanzen einer Abtastrate denselben Zeitbezug haben (lückenloses Überblenden auch von/zu 0 Halbtönen).
    public init(sampleRate: Double, channels: Int, speed: Float = 1, pitch: Float,
                maxFramesPerCall: Int = 4096, delaysWhenNeutral: Bool = false) {
        precondition(channels >= 1, "Mindestens ein Kanal")
        precondition(sampleRate > 0 && pitch > 0 && pitch.isFinite, "Abtastrate und Tonhöhe müssen positiv sein")
        precondition(maxFramesPerCall >= 1)
        assert(abs(speed - 1) < 1e-6, "TimePitchProcessor ändert nur die Tonhöhe (speed muss 1 sein)")
        self.sampleRate = sampleRate
        self.channels = channels
        self.speed = 1
        self.pitch = pitch
        self.maxFramesPerCall = maxFramesPerCall
        let passthrough = abs(pitch - 1) <= 1e-4
        isPassthrough = passthrough
        let latency = TimePitchProcessor.fixedLatency(sampleRate: sampleRate, pitch: pitch)
        if passthrough && !delaysWhenNeutral {
            engine = nil
            latencyFrames = 0
        } else {
            latencyFrames = latency
            engine = TimePitchEngine(sampleRate: sampleRate, channels: channels, speed: 1,
                                     pitch: passthrough ? 1 : pitch, maxFramesPerCall: maxFramesPerCall,
                                     fftSizeOverride: 0, extraOutputCapacity: latency + maxFramesPerCall)
        }
        silenceRemaining = latencyFrames

        scratch = .allocate(capacity: channels * maxFramesPerCall)
        scratch.initialize(repeating: 0, count: channels * maxFramesPerCall)
        scratchPointers = .allocate(capacity: channels)
        for c in 0..<channels { (scratchPointers + c).initialize(to: scratch + c * maxFramesPerCall) }
        let fade = max(64, Int((sampleRate * 0.05).rounded()))
        crossfadeFrames = fade
        fadeIn = .allocate(capacity: fade)
        fadeOut = .allocate(capacity: fade)
        for i in 0..<fade {
            let x = Double.pi / 2 * (Double(i) + 0.5) / Double(fade)
            (fadeIn + i).initialize(to: Float(sin(x)))
            (fadeOut + i).initialize(to: Float(cos(x)))
        }
    }

    deinit {
        scratch.deallocate()
        scratchPointers.deallocate()
        fadeIn.deallocate()
        fadeOut.deallocate()
    }

    /// Feste Verzögerung (Frames), die ein Prozessor für diese Abtastrate und Tonhöhe meldet, wenn er nicht
    /// durchreicht. Für alle Tonhöhen ≥ −12 Halbtöne (Faktor ≥ 0,5) ist sie gleich – nämlich die nötige
    /// Verzögerung bei −12 Halbtönen (dort ist der Rückstand des Phase-Vocoders am größten); nur noch tiefere
    /// Tonhöhen brauchen mehr. 44,1 und 48 kHz: 6251 Frames.
    public static func fixedLatency(sampleRate: Double, pitch: Float) -> Int {
        let rate = Int(sampleRate.rounded())
        let worstInRange = TimePitchEngine.lagBound(sampleRate: rate, speed: 1, pitch: 0.5)
        let own = abs(pitch - 1) > 1e-4 ? TimePitchEngine.lagBound(sampleRate: rate, speed: 1, pitch: Double(pitch)) : 0
        // + 2 Frames Reserve für Rundungen (Analyse-Positionen, Resampler-Position)
        return Int(ceil(max(worstInRange, own))) + 2
    }

    /// Zurück auf den Anfangszustand (nach dem Spulen, Titelwechsel, Stopp): gepufferte Daten verwerfen,
    /// danach wieder `latencyFrames` Stille. Echtzeit-sicher.
    public func reset() {
        engine?.reset()
        silenceRemaining = latencyFrames
        owedFrames = 0
        processedFrames = 0
        underrunFrames = 0
    }

    /// Liest `frames` Frames je Kanal aus `input` und schreibt genau `frames` Frames je Kanal nach `output`
    /// (am Anfang Stille, bis die Verzögerung gefüllt ist). `input[c]`/`output[c]` zeigen auf Kanal c.
    /// Eingang und Ausgang dürfen derselbe Speicher sein (in-place). Beliebig große `frames`; intern in Blöcken
    /// zu höchstens `maxFramesPerCall`.
    public func process(input: UnsafePointer<UnsafePointer<Float>>, output: UnsafePointer<UnsafeMutablePointer<Float>>, frames: Int) {
        var done = 0
        while done < frames {
            let n = min(frames - done, maxFramesPerCall)
            render(input, inOffset: done, output, outOffset: done, frames: n)
            done += n
        }
    }

    /// Wie `process`, aber mit Übergang zu `next` (neue Tonhöhe, frisch angelegt oder zurückgesetzt): Beide
    /// Instanzen bekommen denselben Eingang; ausgegeben wird diese Instanz, bis `next` nach seiner Verzögerung
    /// gültige Daten liefert, dann wird über `next.crossfadeFrames` gleichleistungs-überblendet.
    ///
    /// - Returns: `true`, sobald der Übergang abgeschlossen ist – ab dann nur noch `next` benutzen und diese
    ///   Instanz außerhalb des Audio-Threads freigeben (nicht im Audio-Thread die letzte Referenz loslassen).
    @discardableResult
    public func process(input: UnsafePointer<UnsafePointer<Float>>, output: UnsafePointer<UnsafeMutablePointer<Float>>,
                        frames: Int, crossfadingTo next: TimePitchProcessor) -> Bool {
        precondition(next.channels == channels, "Überblenden nur bei gleicher Kanalzahl")
        if next === self {
            process(input: input, output: output, frames: frames)
            return true
        }
        let valid = Int64(next.latencyFrames)
        let fade = Int64(next.crossfadeFrames)
        var done = 0
        while done < frames {
            let n = min(min(frames - done, maxFramesPerCall), next.maxFramesPerCall)
            let nextStart = next.processedFrames
            // Zuerst `next` (liest den Eingang, schreibt in seinen Zwischenpuffer), dann diese Instanz
            // (darf in-place in den Eingang schreiben).
            next.render(input, inOffset: done, UnsafePointer(next.scratchPointers), outOffset: 0, frames: n)
            render(input, inOffset: done, output, outOffset: done, frames: n)
            for c in 0..<channels {
                let o = output[c] + done
                let s = next.scratch + c * next.maxFramesPerCall
                for t in 0..<n {
                    let g = nextStart + Int64(t) - valid // Position im gültigen Ausgang von `next`
                    if g < 0 { continue }
                    if g >= fade {
                        o[t] = s[t]
                    } else {
                        o[t] = o[t] * next.fadeOut[Int(g)] + s[t] * next.fadeIn[Int(g)]
                    }
                }
            }
            done += n
        }
        return next.processedFrames - valid >= fade
    }

    private func render(_ input: UnsafePointer<UnsafePointer<Float>>, inOffset: Int,
                        _ output: UnsafePointer<UnsafeMutablePointer<Float>>, outOffset: Int, frames n: Int) {
        guard let engine else {
            // Durchreichen (bitgenau, ohne Verzögerung)
            for c in 0..<channels {
                let src = input[c] + inOffset
                let dst = output[c] + outOffset
                if UnsafePointer(dst) != src { dst.update(from: src, count: n) }
            }
            processedFrames += Int64(n)
            return
        }
        // Erst den ganzen Eingang übernehmen, dann schreiben → in-place möglich.
        engine.queueInput(input, offset: inOffset, frames: n)
        if owedFrames > 0 { owedFrames -= engine.discardOutput(owedFrames) }
        var o = 0
        if silenceRemaining > 0 {
            let s = min(silenceRemaining, n)
            for c in 0..<channels { (output[c] + outOffset).update(repeating: 0, count: s) }
            silenceRemaining -= s
            o = s
        }
        if o < n {
            let got = engine.read(output, offset: outOffset + o, maxFrames: n - o)
            let missing = n - o - got
            if missing > 0 {
                for c in 0..<channels { (output[c] + outOffset + o + got).update(repeating: 0, count: missing) }
                underrunFrames += missing
                owedFrames += missing
            }
        }
        processedFrames += Int64(n)
    }

    /// Diagnose: Pufferüberläufe der Verarbeitung (bleibt 0).
    public var overflowFrames: Int { engine?.overflowFrames ?? 0 }
}
