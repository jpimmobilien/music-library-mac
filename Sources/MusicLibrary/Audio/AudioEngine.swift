import AVFoundation
import AudioToolbox
import Accelerate

/// Klangkette der Wiedergabe (AVAudioEngine):
///
///   Player → TimePitch (Tonhöhe/Tempo) → Varispeed („Schallplatte“) → EQ (10 Bänder + Bass-Kuhschwanz,
///   Aussteuerung) → Peak-Limiter (Verstärkung > 100 % ohne Übersteuern) → Mischer → Ausgabe
///
/// Entspricht der Android-Kette (EffectsEngine + TimePitchAudioProcessor), hier mit den Audio-Units von macOS.
/// Alle Einstellungen wirken live, ohne den Titel neu zu starten.
final class AudioEngine {
    struct Parameters: Equatable {
        /// Verstärkung der 10 Bänder in dB (bereits „effektiv“, d. h. 0 bei ausgeschaltetem EQ).
        var bandGains: [Float] = Array(repeating: 0, count: 10)
        var bandFrequencies: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
        /// Bandbreite in Oktaven (Android Q = 1,41 ≈ 1 Oktave).
        var bandwidth: Float = 1.0
        /// Wirksamer Bass (Kuhschwanz bei `bassFrequency`) in dB.
        var bassDb: Float = 0
        var bassFrequency: Float = 100
        /// Vorverstärkung durch automatische Aussteuerung (≤ 0 dB).
        var headroomDb: Float = 0
        /// Lautstärke 0 … 3 (1 = 100 %).
        var volume: Float = 1
        /// Tonhöhe in Cent (Modus „Tonhöhe“), 0 = original.
        var pitchCents: Float = 0
        /// Tempo (Modus „Tonhöhe“), 1 = original.
        var tempo: Float = 1
        /// Drehzahlfaktor (Modus „Schallplatte“: Tonhöhe und Tempo gemeinsam), 1 = original.
        var varispeed: Float = 1
    }

    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    /// v2.1: Tonhöhe in Android-Qualität (eigene Audio-Unit vor Apples TimePitch, das nur noch das Tempo übernimmt).
    /// `nil`, wenn die Unit nicht erzeugt werden konnte – dann wie bisher alles über `timePitch`.
    private let pitchUnit: AVAudioUnitEffect?
    private let pitchAU: PitchShiftAudioUnit?
    /// Für mehr als zwei Kanäle (z. B. 5.1-FLAC) bzw. ohne eigene Unit: Tonhöhe über Apples TimePitch.
    private var usesNativePitch = false
    private let varispeed = AVAudioUnitVarispeed()
    private let eq = AVAudioUnitEQ(numberOfBands: 11)
    private let limiter: AVAudioUnitEffect
    private(set) var parameters = Parameters()
    private var connectedFormat: AVAudioFormat?

    /// Pegel für die Visualisierung (wird auf dem Audio-Thread geschrieben).
    let levels = LevelMeter()

    /// `false`, wenn der Rechner kein Audio-Ausgabegerät hat (z. B. Build-Server). Die Kette läuft dann
    /// im Offline-Modus, damit nichts abstürzt; die Wiedergabe meldet einen verständlichen Fehler.
    private(set) var hasOutputDevice = true
    /// Offline-Modus (Tests oder fehlendes Ausgabegerät): Audio wird mit `renderOffline` abgeholt.
    private(set) var isOffline = false

    /// - Parameter offlineFormat: Für Tests – rendert ohne Audiogerät in diesem Format (`renderOffline`).
    /// - Parameter nativePitch: Für Vergleichsmessungen – Tonhöhe wie bis Version 2.0 über Apples TimePitch
    ///   (auch per Umgebungsvariable `ML_NATIVE_PITCH=1`).
    init(offlineFormat: AVAudioFormat? = nil, nativePitch: Bool = ProcessInfo.processInfo.environment["ML_NATIVE_PITCH"] == "1") {
        if nativePitch {
            pitchUnit = nil
            pitchAU = nil
        } else {
            PitchShiftAudioUnit.register()
            let unit = AVAudioUnitEffect(audioComponentDescription: PitchShiftAudioUnit.componentDescription)
            let au = unit.auAudioUnit as? PitchShiftAudioUnit
            pitchUnit = au != nil ? unit : nil
            pitchAU = au
        }
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        limiter = AVAudioUnitEffect(audioComponentDescription: desc)
        var manualFormat = offlineFormat
        if manualFormat == nil {
            let hw = engine.outputNode.outputFormat(forBus: 0)
            if hw.sampleRate <= 0 || hw.channelCount == 0 {
                hasOutputDevice = false
                manualFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)
            }
        }
        if let manualFormat {
            // Muss vor dem ersten Zugriff auf mainMixerNode geschehen (sonst Verbindung zum fehlenden Gerät).
            do {
                try engine.enableManualRenderingMode(.offline, format: manualFormat, maximumFrameCount: 4096)
                isOffline = true
            } catch {
                hasOutputDevice = false
            }
        }
        engine.attach(player)
        if let pitchUnit { engine.attach(pitchUnit) }
        engine.attach(timePitch)
        engine.attach(varispeed)
        engine.attach(eq)
        engine.attach(limiter)
        for i in 0..<10 {
            let band = eq.bands[i]
            band.filterType = .parametric
            band.frequency = parameters.bandFrequencies[i]
            band.bandwidth = parameters.bandwidth
            band.gain = 0
            band.bypass = false
        }
        let bass = eq.bands[10]
        bass.filterType = .lowShelf
        bass.frequency = parameters.bassFrequency
        bass.gain = 0
        bass.bypass = false
        // Limiter: kurze Ansprechzeit, weiches Ausklingen
        setLimiterParameter(0, 0.002)   // Attack (s)
        setLimiterParameter(1, 0.06)    // Decay (s)
        setLimiterParameter(2, 0)       // Pre-Gain (dB)
        connect(format: nil)
        installLevelProbe()
        apply(parameters, force: true)
    }

    private func setLimiterParameter(_ id: AudioUnitParameterID, _ value: Float) {
        AudioUnitSetParameter(limiter.audioUnit, id, kAudioUnitScope_Global, 0, value, 0)
    }

    /// Verbindet die Kette für das Format der aktuellen Datei (Abtastrate/Kanäle können je Titel wechseln).
    func connect(format: AVAudioFormat?) {
        if let format, let current = connectedFormat,
           current.sampleRate == format.sampleRate, current.channelCount == format.channelCount { return }
        let f = format ?? AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let wasRunning = engine.isRunning
        // Neues Format (Abtastrate/Kanäle): Engine ganz anhalten, nicht nur pausieren. Bei einer pausierten Engine
        // initialisiert AVAudioEngine jeden Knoten schon nach dem ersten `connect` neu – die eigene Tonhöhen-Unit
        // hätte dann kurz Eingang und Ausgang in verschiedenen Formaten, und AVAudioEngine bricht mit einer Ausnahme
        // ab (Fehler −10868: Absturz beim Titelwechsel zwischen Mono und Stereo, 2.1/2.2.0). Angehalten werden alle
        // Verbindungen gesetzt und erst beim nächsten Start gemeinsam vorbereitet. Der Player steht hier ohnehin.
        engine.stop()
        engine.disconnectNodeOutput(player)
        if let pitchUnit { engine.disconnectNodeOutput(pitchUnit) }
        engine.disconnectNodeOutput(timePitch)
        engine.disconnectNodeOutput(varispeed)
        engine.disconnectNodeOutput(eq)
        engine.disconnectNodeOutput(limiter)
        // Eigene Tonhöhen-Unit für Mono/Stereo; mehr Kanäle → Apples TimePitch übernimmt auch die Tonhöhe
        if let pitchUnit, f.channelCount <= 2 {
            engine.connect(player, to: pitchUnit, format: f)
            engine.connect(pitchUnit, to: timePitch, format: f)
            usesNativePitch = false
        } else {
            engine.connect(player, to: timePitch, format: f)
            usesNativePitch = true
        }
        engine.connect(timePitch, to: varispeed, format: f)
        engine.connect(varispeed, to: eq, format: f)
        engine.connect(eq, to: limiter, format: f)
        engine.connect(limiter, to: engine.mainMixerNode, format: f)
        connectedFormat = f
        levels.sampleRate = f.sampleRate
        // Weg der Tonhöhe kann sich geändert haben (eigene Unit ↔ Apples TimePitch)
        apply(parameters, force: true)
        if wasRunning {
            engine.prepare()
            try? engine.start()
        }
    }

    func start() throws {
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    func stopEngine() {
        engine.stop()
    }

    /// Player anhalten und gepufferten Klang der Tonhöhen-Unit verwerfen (Spulen, Titelwechsel).
    func stopPlayer() {
        player.stop()
        pitchAU?.flush()
    }

    /// Verzögerung der Tonhöhen-Unit in Sekunden (0, wenn sie nicht rechnet).
    var pitchLatency: TimeInterval { usesNativePitch ? 0 : (pitchAU?.latency ?? 0) }

    /// Übernimmt neue Klangeinstellungen (nur geänderte Werte werden gesetzt).
    func apply(_ p: Parameters, force: Bool = false) {
        let old = parameters
        parameters = p
        if force || old.bandGains != p.bandGains || old.bandwidth != p.bandwidth {
            for i in 0..<min(10, p.bandGains.count) {
                eq.bands[i].gain = p.bandGains[i]
                eq.bands[i].bandwidth = p.bandwidth
            }
        }
        if force || old.bassDb != p.bassDb || old.bassFrequency != p.bassFrequency {
            eq.bands[10].gain = p.bassDb
            eq.bands[10].frequency = p.bassFrequency
        }
        let toneNeutral = p.bandGains.allSatisfy { $0 == 0 } && p.bassDb == 0 && p.headroomDb == 0
        eq.globalGain = p.headroomDb
        eq.bypass = toneNeutral

        // Lautstärke bis 100 % im Mischer, darüber digitale Verstärkung vor dem Limiter.
        let volume = max(0, min(3, p.volume))
        engine.mainMixerNode.outputVolume = min(volume, 1)
        let boostDb = volume > 1 ? 20 * log10(volume) : 0
        setLimiterParameter(2, boostDb)
        limiter.bypass = false

        // Tonhöhe/Tempo
        let cents = max(-2400, min(2400, p.pitchCents))
        if usesNativePitch {
            timePitch.pitch = cents
            timePitch.bypass = cents == 0 && p.tempo == 1
            pitchAU?.setPitch(factor: 1)
        } else {
            // Kein `bypass` an der eigenen Unit: sie reicht bei „Original“ selbst durch bzw. blendet lückenlos über
            pitchAU?.setPitch(factor: Float(pow(2, Double(cents) / 1200)))
            timePitch.pitch = 0
            timePitch.bypass = p.tempo == 1
        }
        timePitch.rate = max(0.25, min(4, p.tempo))
        varispeed.rate = max(0.25, min(4, p.varispeed))
        varispeed.bypass = p.varispeed == 1
    }

    /// Wirksames Wiedergabetempo (für die Umrechnung Datei-Zeit ↔ echte Zeit, z. B. Sleep-Timer).
    var effectiveRate: Double {
        Double((timePitch.bypass ? 1 : timePitch.rate) * (varispeed.bypass ? 1 : varispeed.rate))
    }

    /// Pegelabgriff hinter dem Limiter: wird in **jedem** Renderzyklus aufgerufen (≈ 11 ms bei 512 Frames),
    /// statt alle ≈ 100 ms wie ein Tap des Mischers – dadurch laufen die Balken flüssig und synchron.
    private func installLevelProbe() {
        let refCon = Unmanaged.passUnretained(levels).toOpaque()
        AudioUnitAddRenderNotify(limiter.audioUnit, { refCon, flags, _, _, frames, ioData in
            guard flags.pointee.contains(.unitRenderAction_PostRender),
                  !flags.pointee.contains(.unitRenderAction_PostRenderError),
                  let ioData else { return noErr }
            Unmanaged<LevelMeter>.fromOpaque(refCon).takeUnretainedValue().capture(ioData, frames: Int(frames))
            return noErr
        }, refCon)
    }
}

/// Pegel und Spektrum für die Klangvisualisierung (Android: LevelAnalyzer):
/// 16 logarithmische Bänder 50 Hz – 14 kHz und Pegel links/rechts, jeweils 0…1 über −60…0 dBFS.
///
/// v2.1: Der Audio-Thread kopiert nur die Abtastwerte in einen Ringpuffer (keine Speicheranforderung, keine
/// Sperre); die FFT rechnet `take()` auf Abruf (höchstens 30-mal je Sekunde im Hauptthread, ≈ 20 µs). Kommen
/// keine neuen Abtastwerte mehr (Pause, Stopp), liefert `take()` nach kurzer Zeit Nullen – die Anzeige klingt aus.
final class LevelMeter: @unchecked Sendable {
    static let bandCount = 16
    private static let capacity = 8192                   // Zweierpotenz
    private static let mask = capacity - 1
    private let fftSize = 2048

    // Gemeinsam mit dem Audio-Thread (feste Speicherbereiche, nie neu angelegt)
    private let ringL = UnsafeMutablePointer<Float>.allocate(capacity: LevelMeter.capacity)
    private let ringR = UnsafeMutablePointer<Float>.allocate(capacity: LevelMeter.capacity)
    private let written = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    private let active = UnsafeMutablePointer<Int>.allocate(capacity: 1)

    /// Abtastrate der Kette (gesetzt beim Verbinden).
    var sampleRate: Double = 44_100
    /// Nur Vorschaubilder (ohne Audio): feste Werte, damit die Anzeige im Bild sichtbar ist.
    var demoValues: [Float]?

    var enabled: Bool {
        get { active.pointee != 0 }
        set {
            if newValue && active.pointee == 0 { reset() }
            active.pointee = newValue ? 1 : 0
        }
    }

    // Nur Hauptthread (take)
    private var lastWritten = 0
    private var lastFresh = Date.distantPast
    private var lastValues: [Float]?
    private lazy var log2n = vDSP_Length(log2(Float(fftSize)))
    private lazy var fftSetup: FFTSetup? = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    private lazy var window: [Float] = {
        var w = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&w, vDSP_Length(fftSize), Int32(vDSP_HANN_DENORM))
        return w
    }()
    private lazy var windowSum: Float = window.reduce(0, +)
    private var mono = [Float](repeating: 0, count: 2048)
    private var windowed = [Float](repeating: 0, count: 2048)
    private var real = [Float](repeating: 0, count: 1024)
    private var imag = [Float](repeating: 0, count: 1024)
    private var power = [Float](repeating: 0, count: 1024)

    init() {
        ringL.initialize(repeating: 0, count: Self.capacity)
        ringR.initialize(repeating: 0, count: Self.capacity)
        written.initialize(to: 0)
        active.initialize(to: 0)
    }

    deinit {
        ringL.deallocate()
        ringR.deallocate()
        written.deallocate()
        active.deallocate()
        if let fftSetup { vDSP_destroy_fftsetup(fftSetup) }
    }

    func reset() {
        lastValues = nil
        lastFresh = .distantPast
        lastWritten = written.pointee
    }

    /// Audio-Thread: Ausgabe eines Renderzyklus übernehmen (Float32, getrennte oder verschachtelte Kanäle).
    func capture(_ ioData: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard active.pointee != 0, frames > 0 else { return }
        let abl = UnsafeMutableAudioBufferListPointer(ioData)
        guard abl.count > 0, let d0 = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        let w = written.pointee
        let interleaved = abl[0].mNumberChannels > 1
        if interleaved {
            let ch = Int(abl[0].mNumberChannels)
            for i in 0..<frames {
                ringL[(w + i) & Self.mask] = d0[i * ch]
                ringR[(w + i) & Self.mask] = d0[i * ch + 1]
            }
        } else {
            let d1 = abl.count > 1 ? (abl[1].mData?.assumingMemoryBound(to: Float.self) ?? d0) : d0
            for i in 0..<frames {
                let j = (w + i) & Self.mask
                ringL[j] = d0[i]
                ringR[j] = d1[i]
            }
        }
        OSMemoryBarrier()
        written.pointee = w + frames
    }

    private static func level(_ amplitude: Float) -> Float {
        let db = 20 * log10(max(amplitude, 1e-7))
        return max(0, min(1, (db + 60) / 60))
    }

    /// Aktuelle Werte (16 Bänder + L + R). Während der Wiedergabe immer frisch; ohne neue Abtastwerte
    /// noch ≈ 0,15 s der letzte Stand (große Audiopuffer), danach Nullen. `nil`, wenn ausgeschaltet.
    func take() -> [Float]? {
        if let demoValues { return demoValues }
        guard enabled else { return nil }
        let w = written.pointee
        OSMemoryBarrier()
        let now = Date()
        if w == lastWritten {
            if now.timeIntervalSince(lastFresh) < 0.15, let lastValues { return lastValues }
            return [Float](repeating: 0, count: Self.bandCount + 2)
        }
        lastWritten = w
        lastFresh = now
        let n = fftSize
        // Die jüngsten n Abtastwerte (Mono) und RMS der jüngsten 1024 je Kanal
        var sumL: Float = 0, sumR: Float = 0
        for i in 0..<n {
            let j = (w - n + i) & Self.mask
            let l = ringL[j], r = ringR[j]
            mono[i] = 0.5 * (l + r)
            if i >= n - 1024 {
                sumL += l * l
                sumR += r * r
            }
        }
        let rmsL = (sumL / 1024).squareRoot(), rmsR = (sumR / 1024).squareRoot()
        var bands = [Float](repeating: 0, count: Self.bandCount)
        if let setup = fftSetup {
            vDSP_vmul(mono, 1, window, 1, &windowed, 1, vDSP_Length(n))
            real.withUnsafeMutableBufferPointer { rp in
                imag.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    windowed.withUnsafeBufferPointer { wp in
                        wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { cp in
                            vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(n / 2))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    power.withUnsafeMutableBufferPointer { pp in
                        vDSP_zvmags(&split, 1, pp.baseAddress!, 1, vDSP_Length(n / 2))
                    }
                }
            }
            power[0] = 0 // Gleichanteil (zrip legt hier zusätzlich Nyquist ab)
            let sr = Float(sampleRate > 0 ? sampleRate : 44_100)
            let half = n / 2
            // vDSP_fft_zrip liefert das Zweifache der DFT; eine Sinusschwingung der Amplitude A ergibt im Maximum
            // |X| = A · Σw. Bandwert = Energie aller Bins im Band (Hann: 1,5 Bins je Ton) → Amplitude in dBFS.
            let norm = 1 / (windowSum * windowSum * 1.5)
            for b in 0..<Self.bandCount {
                let f0 = 50 * pow(14000 / 50, Float(b) / Float(Self.bandCount))
                let f1 = 50 * pow(14000 / 50, Float(b + 1) / Float(Self.bandCount))
                let i0 = min(half - 1, max(1, Int(f0 / sr * Float(n))))
                let i1 = min(half, max(i0 + 1, Int(f1 / sr * Float(n))))
                var e: Float = 0
                for i in i0..<i1 { e += power[i] }
                bands[b] = Self.level((e * norm).squareRoot())
            }
        }
        let values = bands + [Self.level(rmsL * 1.414), Self.level(rmsR * 1.414)]
        lastValues = values
        return values
    }
}
