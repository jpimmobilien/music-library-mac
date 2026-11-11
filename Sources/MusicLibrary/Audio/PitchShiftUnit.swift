import AVFoundation
import AudioToolbox
import MLCore

/// Tonhöhenverschiebung in Android-Qualität (v2.1) als eigene Audio-Unit in der Klangkette.
///
/// Apples `AVAudioUnitTimePitch` (Phasen-Vocoder mit kleiner Überlappung) klang bei Tonhöhenänderungen hörbar
/// verzerrt. Diese Unit nutzt die aus der Android-App portierte Verarbeitung `TimePitchProcessor` (MLCore):
/// Phasen-Vocoder mit 4096er-FFT, Phasenkopplung, Anschlagerkennung und anschließender Sinc-Umrechnung.
/// Sie verschiebt nur die Tonhöhe (Tempo bleibt 1, gleich viele Frames hinein wie heraus, feste Verzögerung);
/// eine Tempoänderung übernimmt weiterhin Apples Einheit dahinter.
///
/// Echtzeit-Regeln im Render-Block: keine Speicheranforderung, keine blockierende Sperre. Neue Einstellungen
/// werden im Hauptthread als neuer Prozessor angelegt und über einen Briefkasten übergeben (`os_unfair_lock_trylock`
/// im Audio-Thread – blockiert nie); der alte Prozessor wird im Hauptthread freigegeben.
final class PitchShiftAudioUnit: AUAudioUnit {
    static let componentDescription = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: 0x6D6C_7073,          // 'mlps'
        componentManufacturer: 0x4D4C_6962,     // 'MLib'
        componentFlags: 0,
        componentFlagsMask: 0
    )

    private static var registered = false

    /// Einmal je Programmlauf anmelden (danach mit `AVAudioUnitEffect(audioComponentDescription:)` erzeugbar).
    static func register() {
        guard !registered else { return }
        registered = true
        AUAudioUnit.registerSubclass(PitchShiftAudioUnit.self, as: componentDescription, name: "Music Library: Tonhöhe", version: 1)
    }

    private var inputBus: AUAudioUnitBus!
    private var outputBus: AUAudioUnitBus!
    private var _inputBusses: AUAudioUnitBusArray!
    private var _outputBusses: AUAudioUnitBusArray!
    private let state = RenderState()

    /// Gewünschter Tonhöhenfaktor (2^(Halbtöne/12)); 1 = unverändert (Durchreichen ohne Verzögerung).
    private(set) var pitchFactor: Float = 1

    override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        inputBus = try AUAudioUnitBus(format: format)
        outputBus = try AUAudioUnitBus(format: format)
        inputBus.maximumChannelCount = 2
        outputBus.maximumChannelCount = 2
        _inputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        _outputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        maximumFramesToRender = Self.renderCapacity
    }

    /// Mindestgröße der internen Puffer. Die Engine setzt `maximumFramesToRender` vor dem Mischer selbst passend
    /// (gemessen: 8928 Frames bei 96 kHz und 4096er Ausgabeblöcken); die Reserve verhindert nur, dass ungewöhnlich
    /// große Blöcke (z. B. 192 kHz) mit „zu viele Frames“ abgewiesen werden.
    static let renderCapacity: AUAudioFrameCount = 32_768

    override var inputBusses: AUAudioUnitBusArray { _inputBusses }
    override var outputBusses: AUAudioUnitBusArray { _outputBusses }
    override var canProcessInPlace: Bool { false }
    override var latency: TimeInterval {
        let rate = outputBus.format.sampleRate
        guard rate > 0 else { return 0 }
        return Double(state.latencyFrames) / rate
    }

    override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        let format = outputBus.format
        guard format.channelCount >= 1, format.channelCount <= 2 else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FormatNotSupported))
        }
        // Eingang und Ausgang können während einer Umverbindung kurz verschieden sein (z. B. Mono-Titel nach
        // Stereo-Titel). Kein Fehler werfen – AVAudioEngine würde daraus eine Ausnahme machen –, sondern bis zur
        // nächsten Vorbereitung Stille ausgeben.
        state.mismatch = inputBus.format.channelCount != format.channelCount || inputBus.format.sampleRate != format.sampleRate
        state.allocate(channels: Int(format.channelCount), maxFrames: Int(max(maximumFramesToRender, Self.renderCapacity)))
        state.sampleRate = format.sampleRate
        state.post(nil, latency: 0)
        delayedNeutral = false
        installProcessor()
    }

    override func deallocateRenderResources() {
        state.deallocate()
        super.deallocateRenderResources()
    }

    /// Tonhöhe setzen (Hauptthread). Legt bei Bedarf einen neuen Prozessor an.
    func setPitch(factor: Float) {
        let f = max(0.25, min(4, factor))
        guard f != pitchFactor else { return }
        pitchFactor = f
        if renderResourcesAllocated { installProcessor() }
    }

    /// Gepufferte Klänge verwerfen (nach Spulen, Titelwechsel, Stopp). Stand die Tonhöhe zuletzt auf „Original“
    /// mit verzögerter Überblendstufe, wird jetzt wieder verzögerungsfrei durchgereicht.
    func flush() {
        state.requestReset()
        if delayedNeutral && abs(pitchFactor - 1) <= 1e-5 && renderResourcesAllocated {
            delayedNeutral = false
            state.post(nil, latency: 0)
        }
    }

    /// Läuft gerade eine Verarbeitung mit Verzögerung (auch die neutrale Überblendstufe)?
    private var delayedNeutral = false

    override func reset() {
        super.reset()
        state.requestReset()
    }

    /// Neuen Prozessor übergeben. Zwischen zwei Tonhöhen blendet der Audio-Thread lückenlos über (gleiche Verzögerung
    /// für alle Tonhöhen). Zurück auf „Original“ wird zuerst eine neutrale Stufe **mit** Verzögerung eingeblendet –
    /// so entsteht weder Lücke noch Sprung; verzögerungsfrei wird erst beim nächsten Spulen/Titelwechsel (`flush`).
    /// Nur beim ersten Einschalten aus „Original“ entsteht einmalig eine kurze Pause (≈ 0,14 s), wie bei Android.
    private func installProcessor() {
        let neutral = abs(pitchFactor - 1) <= 1e-5
        if neutral && !state.hasProcessor && !delayedNeutral {
            state.post(nil, latency: 0)
            return
        }
        let p = TimePitchProcessor(sampleRate: state.sampleRate, channels: state.channels, speed: 1,
                                   pitch: neutral ? 1 : pitchFactor, maxFramesPerCall: state.capacity,
                                   delaysWhenNeutral: neutral)
        delayedNeutral = true
        state.post(p, latency: p.latencyFrames)
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        let state = self.state
        return { _, timestamp, frameCount, _, outputData, _, pullInputBlock in
            guard let pull = pullInputBlock else { return kAudioUnitErr_NoConnection }
            return state.render(timestamp: timestamp, frames: frameCount, output: outputData, pull: pull)
        }
    }
}

/// Zustand des Render-Blocks (feste Puffer, Briefkasten für den Prozessor).
private final class RenderState: @unchecked Sendable {
    var channels = 2
    /// Eingang ≠ Ausgang (nur kurz während einer Umverbindung): Stille ausgeben, nichts anfordern.
    var mismatch = false
    var sampleRate: Double = 44_100
    private(set) var latencyFrames = 0
    private var maxFrames = 0
    /// Größte Blockgröße der zugeteilten Puffer.
    var capacity: Int { maxFrames }
    private var inputList: UnsafeMutableAudioBufferListPointer?
    private var inputMemory: [UnsafeMutablePointer<Float>] = []
    private var outputMemory: [UnsafeMutablePointer<Float>] = []
    private let inPointers = UnsafeMutablePointer<UnsafePointer<Float>>.allocate(capacity: 2)
    private let outPointers = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: 2)

    // Briefkasten: `pending` nur unter `lock` (Audio-Thread nur mit trylock). `current`, `incoming` gehören dem
    // Audio-Thread; abgelegte Prozessoren landen in `retired` (feste Plätze) und werden im Hauptthread freigegeben.
    private let lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    private var current: Unmanaged<TimePitchProcessor>?
    private var incoming: Unmanaged<TimePitchProcessor>?
    private var incomingIsNil = false
    private var pending: Unmanaged<TimePitchProcessor>?
    private var hasPending = false
    private static let retiredSlots = 4
    private let retired = UnsafeMutablePointer<Unmanaged<TimePitchProcessor>?>.allocate(capacity: RenderState.retiredSlots)
    private let resetFlag = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    /// Hauptthread: Wurde zuletzt ein Prozessor (statt Durchreichen) übergeben?
    private(set) var hasProcessor = false

    init() {
        lock.initialize(to: os_unfair_lock())
        resetFlag.initialize(to: 0)
        retired.initialize(repeating: nil, count: Self.retiredSlots)
    }

    deinit {
        deallocate()
        os_unfair_lock_lock(lock)
        current?.release()
        incoming?.release()
        pending?.release()
        for i in 0..<Self.retiredSlots { retired[i]?.release() }
        os_unfair_lock_unlock(lock)
        retired.deallocate()
        lock.deallocate()
        resetFlag.deallocate()
        inPointers.deallocate()
        outPointers.deallocate()
    }

    func allocate(channels: Int, maxFrames: Int) {
        deallocate()
        self.channels = channels
        self.maxFrames = maxFrames
        let list = AudioBufferList.allocate(maximumBuffers: channels)
        for c in 0..<channels {
            let mem = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
            mem.initialize(repeating: 0, count: maxFrames)
            inputMemory.append(mem)
            let out = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
            out.initialize(repeating: 0, count: maxFrames)
            outputMemory.append(out)
            list[c] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(maxFrames * 4), mData: mem)
        }
        inputList = list
    }

    func deallocate() {
        if let inputList { free(inputList.unsafeMutablePointer) }
        inputList = nil
        for m in inputMemory { m.deallocate() }
        for m in outputMemory { m.deallocate() }
        inputMemory = []
        outputMemory = []
    }

    /// Hauptthread: neuen Prozessor (oder `nil` = durchreichen) übergeben; Abgelegtes freigeben.
    func post(_ processor: TimePitchProcessor?, latency: Int) {
        let new = processor.map { Unmanaged.passRetained($0) }
        var free: [Unmanaged<TimePitchProcessor>] = []
        os_unfair_lock_lock(lock)
        if let p = pending { free.append(p) }    // noch nicht übernommen → verwerfen
        pending = new
        hasPending = true
        for i in 0..<Self.retiredSlots {
            if let r = retired[i] { free.append(r) }
            retired[i] = nil
        }
        os_unfair_lock_unlock(lock)
        for r in free { r.release() }
        hasProcessor = processor != nil
        latencyFrames = latency
    }

    /// Audio-Thread: alten Prozessor ablegen. `false`, wenn kein Platz frei ist (dann später erneut).
    private func retire(_ p: Unmanaged<TimePitchProcessor>?) -> Bool {
        guard let p else { return true }
        for i in 0..<Self.retiredSlots where retired[i] == nil {
            retired[i] = p
            return true
        }
        return false
    }

    func requestReset() { resetFlag.pointee = 1 }

    /// Audio-Thread.
    func render(timestamp: UnsafePointer<AudioTimeStamp>, frames frameCount: AUAudioFrameCount,
                output: UnsafeMutablePointer<AudioBufferList>, pull: AURenderPullInputBlock) -> AUAudioUnitStatus {
        let frames = Int(frameCount)
        guard let inputList, frames <= maxFrames else { return kAudioUnitErr_TooManyFramesToProcess }
        if mismatch {
            let out = UnsafeMutableAudioBufferListPointer(output)
            for c in 0..<min(out.count, channels) {
                if out[c].mData == nil { out[c].mData = UnsafeMutableRawPointer(outputMemory[c]) }
                if let data = out[c].mData { memset(data, 0, frames * 4) }
                out[c].mDataByteSize = UInt32(frames * 4)
            }
            return noErr
        }
        for c in 0..<channels {
            inputList[c].mData = UnsafeMutableRawPointer(inputMemory[c])
            inputList[c].mDataByteSize = UInt32(frames * 4)
        }
        var pullFlags = AudioUnitRenderActionFlags()
        let status = pull(&pullFlags, timestamp, frameCount, 0, inputList.unsafeMutablePointer)
        if status != noErr { return status }

        // Neuen Prozessor abholen (nie blockieren: ist die Sperre belegt, im nächsten Zyklus)
        if incoming == nil && !incomingIsNil && os_unfair_lock_trylock(lock) {
            if hasPending {
                incoming = pending
                incomingIsNil = pending == nil
                pending = nil
                hasPending = false
            }
            os_unfair_lock_unlock(lock)
        }

        let out = UnsafeMutableAudioBufferListPointer(output)
        for c in 0..<min(out.count, channels) {
            if out[c].mData == nil { out[c].mData = UnsafeMutableRawPointer(outputMemory[c]) }
            out[c].mDataByteSize = UInt32(frames * 4)
            if let src = inputList[c].mData?.assumingMemoryBound(to: Float.self) { inPointers[c] = UnsafePointer(src) }
            if let dst = out[c].mData?.assumingMemoryBound(to: Float.self) { outPointers[c] = dst }
        }

        let reset = resetFlag.pointee != 0
        if reset { resetFlag.pointee = 0 }

        // Wechsel: ohne laufenden Prozessor bzw. zu „durchreichen“ sofort, sonst lückenlos überblenden
        if incoming != nil || incomingIsNil {
            if current == nil || incomingIsNil || reset {
                if os_unfair_lock_trylock(lock) {
                    if retire(current) {
                        current = incoming
                        incoming = nil
                        incomingIsNil = false
                    }
                    os_unfair_lock_unlock(lock)
                }
            } else if let cur = current, let next = incoming {
                var finished = false
                cur._withUnsafeGuaranteedRef { c in
                    next._withUnsafeGuaranteedRef { n in
                        finished = c.process(input: UnsafePointer(inPointers), output: UnsafePointer(outPointers), frames: frames, crossfadingTo: n)
                    }
                }
                if finished, os_unfair_lock_trylock(lock) {
                    if retire(current) {
                        current = incoming
                        incoming = nil
                    }
                    os_unfair_lock_unlock(lock)
                }
                return noErr
            }
        }

        guard let current else {
            // Durchreichen
            for c in 0..<min(out.count, channels) where outPointers[c] != UnsafeMutablePointer(mutating: inPointers[c]) {
                outPointers[c].update(from: inPointers[c], count: frames)
            }
            return noErr
        }
        current._withUnsafeGuaranteedRef { p in
            if reset { p.reset() }
            p.process(input: UnsafePointer(inPointers), output: UnsafePointer(outPointers), frames: frames)
        }
        return noErr
    }
}
