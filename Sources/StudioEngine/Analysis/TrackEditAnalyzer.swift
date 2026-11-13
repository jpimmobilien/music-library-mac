import Foundation
import MLCore
import MLStudio

/// Analyse eines Titels für „Titel bearbeiten“: Lautheit (BS.1770) und Spitzenpegel über die ganze Datei,
/// Stille am Anfang und Ende, Stimmung (Kammerton) und Tonart aus den ersten zehn Minuten.
public struct TrackEditAnalyzer: TrackEditAnalyzing {
    public init() {}

    public func analyze(_ file: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> TrackAnalysis {
        try await Task.detached(priority: .utility) {
            try await Self.run(file, progress: progress)
        }.value
    }

    static func run(_ file: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> TrackAnalysis {
        let reader = try await SourceOpener.open(file, downmixToStereo: true)
        defer { reader.close() }
        let rate = reader.sampleRate
        let channels = reader.channelCount
        let meter = LoudnessMeter(sampleRate: rate, channels: channels)
        let music = MusicAnalyzer(sampleRate: rate)
        let frameSize = music.frameSize
        let musicLimit = Int64(rate * 600)
        var mono: [Float] = []
        mono.reserveCapacity(frameSize * 2)
        var monoPos = 0
        let block = FloatBlock(channels: channels, capacity: 32_768)
        var position: Int64 = 0
        var first: Int64?
        var last: Int64?
        let threshold: Float = 0.001
        let total = reader.lengthFrames
        while true {
            try Task.checkCancellation()
            let n = try reader.read(into: block, maxFrames: block.capacity)
            if n == 0 { break }
            meter.add(block.channels.map { UnsafePointer($0) }, frames: n)
            for i in 0..<n {
                var loud = false
                for c in 0..<channels where abs(block.channels[c][i]) > threshold { loud = true; break }
                if loud {
                    if first == nil { first = position + Int64(i) }
                    last = position + Int64(i)
                }
            }
            if position < musicLimit {
                let scale = 1 / Float(channels)
                for i in 0..<n {
                    var v: Float = 0
                    for c in 0..<channels { v += block.channels[c][i] }
                    mono.append(v * scale)
                }
                // Fenster mit halber Überlappung
                while mono.count - monoPos >= frameSize {
                    mono.withUnsafeBufferPointer { music.analyze($0.baseAddress! + monoPos) }
                    monoPos += frameSize / 2
                }
                if monoPos > frameSize * 4 {
                    mono.removeFirst(monoPos)
                    monoPos = 0
                }
            }
            position += Int64(n)
            if let t = total, t > 0 { progress(min(1, Double(position) / Double(t))) }
        }
        var result = TrackAnalysis()
        if let t = music.tuningOffsetCents {
            result.reference = 440 * pow(2, t.cents / 1200)
            result.referenceConfidence = t.confidence
        }
        if let k = music.key {
            result.keyTonic = k.tonic
            result.keyScale = k.scale
            result.keyCorrelation = k.correlation
        }
        result.loudness = meter.integratedLoudness
        result.peakDb = meter.samplePeak > 0 ? meter.samplePeakDb : nil
        if let f = first, let l = last {
            result.leadingSilence = Double(f) / rate
            result.trailingSilence = Double(max(0, position - 1 - l)) / rate
        }
        progress(1)
        return result
    }
}
