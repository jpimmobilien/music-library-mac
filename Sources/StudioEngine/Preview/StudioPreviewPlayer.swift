import AVFoundation
import Foundation
import MLStudio

/// Vorhören im Editor über einen eigenen AVAudioEngine + AVAudioPlayerNode – völlig getrennt vom
/// Hauptplayer (Hauptplayer, EQ und Tonhöhe bleiben unberührt).
///
/// Dateien, die AVAudioFile öffnet, werden mit `scheduleSegment` abgespielt; andere (Ogg, Video,
/// FFmpeg-Formate) werden im Hintergrund blockweise dekodiert und als Puffer eingeplant.
@MainActor
public final class StudioPreviewPlayer: StudioPreviewing {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var file: AVAudioFile?
    private var streamURL: URL?
    private var format: AVAudioFormat?
    private var fileDuration: Double = 0
    /// Startversatz der laufenden bzw. letzten Wiedergabe (Sekunden).
    private var startOffset: Double = 0
    private var endTime: Double?
    /// Position beim Anhalten (nil = nicht angehalten).
    private var pausedAt: Double?
    /// Zählt Wiedergaben; Rückmeldungen älterer Wiedergaben werden ignoriert.
    private var generation = 0
    private var playing = false
    /// Hintergrund-Dekodierung (nur für Formate ohne AVAudioFile); auch im deinit abbrechbar.
    nonisolated(unsafe) private var streamTask: Task<Void, Never>?
    private var attached = false

    public var onFinish: (() -> Void)?

    public init() {}

    deinit {
        streamTask?.cancel()
    }

    public var isPlaying: Bool { playing }

    public var position: Double {
        if let pausedAt { return pausedAt }
        guard playing, let rate = format?.sampleRate, rate > 0,
              let nodeTime = node.lastRenderTime, nodeTime.isSampleTimeValid,
              let playerTime = node.playerTime(forNodeTime: nodeTime) else { return startOffset }
        let t = startOffset + max(0, Double(playerTime.sampleTime)) / rate
        return min(t, endTime ?? fileDuration)
    }

    public func load(_ url: URL) throws {
        stop()
        file = nil
        streamURL = nil
        startOffset = 0
        pausedAt = nil
        let newFormat: AVAudioFormat
        if let f = try? AVAudioFile(forReading: url) {
            file = f
            newFormat = f.processingFormat
            fileDuration = f.processingFormat.sampleRate > 0 ? Double(f.length) / f.processingFormat.sampleRate : 0
        } else {
            // Format über die Leser prüfen (Ogg, Video, FFmpeg) – kurz und synchron nur für die Kopfdaten
            let probe = try Self.probeStream(url)
            guard let fmt = AVAudioFormat(standardFormatWithSampleRate: probe.rate, channels: AVAudioChannelCount(probe.channels)) else {
                throw StudioError.unsupportedFile(url.pathExtension.lowercased())
            }
            streamURL = url
            newFormat = fmt
            fileDuration = probe.duration
        }
        if !attached {
            engine.attach(node)
            attached = true
        }
        if format != newFormat {
            engine.disconnectNodeOutput(node)
            engine.connect(node, to: engine.mainMixerNode, format: newFormat)
        }
        format = newFormat
        engine.prepare()
    }

    /// Kopfdaten einer Datei, die AVAudioFile nicht öffnet.
    private static func probeStream(_ url: URL) throws -> (rate: Double, channels: Int, duration: Double) {
        let ext = url.pathExtension.lowercased()
        if SourceOpener.oggExtensions.contains(ext), let r = try? OggPCMReader(url: url, downmixToStereo: true) {
            return (r.sampleRate, r.channelCount, r.durationSeconds ?? 0)
        }
        // AVAsset-Angaben synchron abzufragen ist nicht vorgesehen; Abtastrate und Kanäle beim
        // Abspielen ermitteln – hier Standardwerte, die beim ersten Abspielen angepasst werden.
        let supported = SourceOpener.videoExtensions.contains(ext) || FFmpegTool.path != nil
        guard supported else { throw StudioError.unsupportedFile(ext) }
        return (44_100, 2, 0)
    }

    public func play(from start: Double, to end: Double?) {
        guard let format, format.sampleRate > 0 else { return }
        haltNode()
        generation += 1
        let gen = generation
        let begin = max(0, min(start, fileDuration > 0 ? fileDuration : start))
        startOffset = begin
        endTime = end.map { max(begin, $0) }
        pausedAt = nil
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        if let file {
            let rate = format.sampleRate
            let first = AVAudioFramePosition((begin * rate).rounded())
            let last = end.map { AVAudioFramePosition(($0 * rate).rounded()) } ?? file.length
            let count = AVAudioFrameCount(max(0, min(last, file.length) - first))
            guard count > 0, first < file.length else { finish(gen); return }
            node.scheduleSegment(file, startingFrame: first, frameCount: count, at: nil,
                                 completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor [weak self] in self?.finish(gen) }
            }
            node.play()
            playing = true
        } else if let url = streamURL {
            playing = true
            node.play()
            startStreaming(url: url, start: begin, end: end, generation: gen)
        }
    }

    /// Dekodiert im Hintergrund und plant Puffer ein (höchstens ~2 Sekunden im Voraus).
    private func startStreaming(url: URL, start: Double, end: Double?, generation gen: Int) {
        let node = self.node
        guard let format else { return }
        streamTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let reader = try await SourceOpener.open(url, downmixToStereo: true)
                defer { reader.close() }
                guard Int(reader.sampleRate.rounded()) == Int(format.sampleRate.rounded()), reader.channelCount == Int(format.channelCount) else {
                    // Format weicht ab: Verbindung auf dem Hauptthread anpassen und neu starten
                    let rate = reader.sampleRate, ch = reader.channelCount, dur = reader.durationSeconds ?? 0
                    await MainActor.run { [weak self] in self?.reconnect(rate: rate, channels: ch, duration: dur, restartFrom: start, to: end, generation: gen) }
                    return
                }
                let rate = reader.sampleRate
                let first = Int64((start * rate).rounded())
                if first > 0 { try reader.seek(to: first) }
                var remaining: Int64? = end.map { max(0, Int64(($0 * rate).rounded()) - first) }
                let pending = PendingCounter()
                let chunk = Int(rate / 4)
                while !Task.isCancelled {
                    if self == nil { return }
                    if let r = remaining, r <= 0 { break }
                    while pending.value >= 8 && !Task.isCancelled { try await Task.sleep(nanoseconds: 20_000_000) }
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk)) else { break }
                    let block = FloatBlock(channels: reader.channelCount, capacity: chunk)
                    let want = remaining.map { Int(min(Int64(chunk), $0)) } ?? chunk
                    let n = try reader.read(into: block, maxFrames: want)
                    if n == 0 { break }
                    if let dst = buffer.floatChannelData {
                        for c in 0..<reader.channelCount { dst[c].update(from: block.channels[c], count: n) }
                    }
                    buffer.frameLength = AVAudioFrameCount(n)
                    remaining = remaining.map { $0 - Int64(n) }
                    pending.increment()
                    node.scheduleBuffer(buffer) { pending.decrement() }
                }
                if Task.isCancelled { return }
                // Ende: nach dem letzten Puffer melden
                guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1) else { return }
                silence.frameLength = 1
                node.scheduleBuffer(silence, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.finish(gen) }
                }
            } catch {
                await MainActor.run { [weak self] in self?.finish(gen) }
            }
        }
    }

    private func reconnect(rate: Double, channels: Int, duration: Double, restartFrom start: Double, to end: Double?, generation gen: Int) {
        guard gen == generation, let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: AVAudioChannelCount(channels)) else { return }
        haltNode()
        engine.disconnectNodeOutput(node)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        format = fmt
        fileDuration = duration
        play(from: start, to: end)
    }

    private func finish(_ gen: Int) {
        guard gen == generation, playing else { return }
        playing = false
        pausedAt = nil
        startOffset = endTime ?? fileDuration
        node.stop()
        onFinish?()
    }

    /// Hält den Knoten an, ohne `onFinish` auszulösen.
    private func haltNode() {
        generation += 1
        streamTask?.cancel()
        streamTask = nil
        node.stop()
    }

    public func pause() {
        guard playing else { return }
        let p = position
        haltNode()
        playing = false
        pausedAt = p
        startOffset = p
    }

    public func stop() {
        haltNode()
        playing = false
        pausedAt = nil
        // Abspielkopf zurück an den Anfang der letzten Wiedergabe
        if engine.isRunning { engine.pause() }
    }

    /// Engine vollständig freigeben (z. B. beim Schließen des Studios).
    public func shutdown() {
        stop()
        engine.stop()
        if attached {
            engine.detach(node)
            attached = false
        }
        file = nil
        streamURL = nil
        format = nil
    }
}

/// Zähler für eingeplante Puffer (Rückmeldungen kommen auf einem Audio-Thread).
private final class PendingCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
    func decrement() { lock.lock(); count -= 1; lock.unlock() }
}
