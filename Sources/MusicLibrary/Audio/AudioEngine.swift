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
    init(offlineFormat: AVAudioFormat? = nil) {
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
        installTap()
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
        if wasRunning { engine.pause() }
        engine.disconnectNodeOutput(player)
        engine.disconnectNodeOutput(timePitch)
        engine.disconnectNodeOutput(varispeed)
        engine.disconnectNodeOutput(eq)
        engine.disconnectNodeOutput(limiter)
        engine.connect(player, to: timePitch, format: f)
        engine.connect(timePitch, to: varispeed, format: f)
        engine.connect(varispeed, to: eq, format: f)
        engine.connect(eq, to: limiter, format: f)
        engine.connect(limiter, to: engine.mainMixerNode, format: f)
        connectedFormat = f
        if wasRunning { try? engine.start() }
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
        timePitch.pitch = max(-2400, min(2400, p.pitchCents))
        timePitch.rate = max(0.25, min(4, p.tempo))
        timePitch.bypass = p.pitchCents == 0 && p.tempo == 1
        varispeed.rate = max(0.25, min(4, p.varispeed))
        varispeed.bypass = p.varispeed == 1
    }

    /// Wirksames Wiedergabetempo (für die Umrechnung Datei-Zeit ↔ echte Zeit, z. B. Sleep-Timer).
    var effectiveRate: Double {
        Double((timePitch.bypass ? 1 : timePitch.rate) * (varispeed.bypass ? 1 : varispeed.rate))
    }

    private func installTap() {
        let meter = levels
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 2048, format: nil) { buffer, _ in
            meter.process(buffer)
        }
    }
}

/// Pegel und Spektrum für die optionale Klangvisualisierung (Android: LevelAnalyzer):
/// 16 logarithmische Bänder 50 Hz – 14 kHz und Pegel links/rechts, jeweils 0…1 über −60…0 dBFS.
/// Rechnet nur, wenn `enabled` gesetzt ist.
final class LevelMeter: @unchecked Sendable {
    static let bandCount = 16
    private let lock = NSLock()
    private var latest: [Float]?
    private var fresh = false
    var enabled = false

    private let fftSize = 2048
    private lazy var log2n = vDSP_Length(log2(Float(fftSize)))
    private lazy var fftSetup: FFTSetup? = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    private lazy var window: [Float] = {
        var w = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&w, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        return w
    }()

    func reset() {
        lock.lock()
        latest = nil
        fresh = false
        lock.unlock()
    }

    /// Frische Werte (16 Bänder + L + R) oder `nil`, wenn seit dem letzten Abruf nichts Neues kam.
    func take() -> [Float]? {
        lock.lock()
        defer { lock.unlock() }
        guard fresh else { return nil }
        fresh = false
        return latest
    }

    private static func level(_ rms: Float) -> Float {
        let db = 20 * log10(max(rms, 1e-7))
        return max(0, min(1, (db + 60) / 60))
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard enabled, let data = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let n = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        let count = min(n, fftSize)
        var rmsL: Float = 0, rmsR: Float = 0
        vDSP_rmsqv(data[0], 1, &rmsL, vDSP_Length(count))
        if channels > 1 { vDSP_rmsqv(data[1], 1, &rmsR, vDSP_Length(count)) } else { rmsR = rmsL }
        var mono = [Float](repeating: 0, count: fftSize)
        var scale = 1 / Float(max(channels, 1))
        mono.withUnsafeMutableBufferPointer { mp in
            guard let m = mp.baseAddress else { return }
            for c in 0..<channels { vDSP_vadd(m, 1, data[c], 1, m, 1, vDSP_Length(count)) }
            vDSP_vsmul(m, 1, &scale, m, 1, vDSP_Length(count))
        }
        var bands = [Float](repeating: 0, count: Self.bandCount)
        if let setup = fftSetup, buffer.format.sampleRate > 0 {
            var windowed = [Float](repeating: 0, count: fftSize)
            vDSP_vmul(mono, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))
            var real = [Float](repeating: 0, count: fftSize / 2)
            var imag = [Float](repeating: 0, count: fftSize / 2)
            var mags = [Float](repeating: 0, count: fftSize / 2)
            real.withUnsafeMutableBufferPointer { rp in
                imag.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    windowed.withUnsafeBufferPointer { wp in
                        wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { cp in
                            vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(fftSize / 2))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    mags.withUnsafeMutableBufferPointer { mp in
                        vDSP_zvabs(&split, 1, mp.baseAddress!, 1, vDSP_Length(fftSize / 2))
                    }
                }
            }
            let sr = Float(buffer.format.sampleRate)
            for b in 0..<Self.bandCount {
                let f0 = 50 * pow(14000 / 50, Float(b) / Float(Self.bandCount))
                let f1 = 50 * pow(14000 / 50, Float(b + 1) / Float(Self.bandCount))
                // Begrenzt auf die vorhandenen Bins (bei niedriger Abtastrate, z. B. Bluetooth-Headset mit 16/24 kHz,
                // liegen die oberen Bänder sonst jenseits von Nyquist → Index außerhalb des Bereichs)
                let half = fftSize / 2
                let i0 = min(half - 1, max(1, Int(f0 / sr * Float(fftSize))))
                let i1 = min(half, max(i0 + 1, Int(f1 / sr * Float(fftSize))))
                var peak: Float = 0
                for i in i0..<i1 { peak = max(peak, mags[i]) }
                bands[b] = Self.level(peak / Float(fftSize) * 4)
            }
        }
        let values = bands + [Self.level(rmsL * 1.414), Self.level(rmsR * 1.414)]
        lock.lock()
        latest = values
        fresh = true
        lock.unlock()
    }
}
