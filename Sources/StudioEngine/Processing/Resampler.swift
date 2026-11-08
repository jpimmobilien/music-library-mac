import AVFoundation
import Foundation
import MLStudio

/// Abtastratenwandlung über AVAudioConverter in höchster Qualität (Algorithmus „Mastering“,
/// Qualität „max“, ohne Latenz durch `primeMethod = .normal`). Arbeitet blockweise (Streaming).
final class Resampler {
    private let converter: AVAudioConverter
    private let inBuffer: AVAudioPCMBuffer
    private let outBuffer: AVAudioPCMBuffer
    private let outBlock: FloatBlock
    private let channels: Int
    let inputRate: Double
    let outputRate: Double

    init(channels: Int, from inputRate: Double, to outputRate: Double, maxInputFrames: Int) throws {
        self.channels = channels
        self.inputRate = inputRate
        self.outputRate = outputRate
        guard let inFormat = AVAudioFormat(standardFormatWithSampleRate: inputRate, channels: AVAudioChannelCount(channels)),
              let outFormat = AVAudioFormat(standardFormatWithSampleRate: outputRate, channels: AVAudioChannelCount(channels)),
              let conv = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw StudioError.encodeFailed("Abtastratenwandlung \(Int(inputRate)) → \(Int(outputRate)) Hz nicht möglich.")
        }
        conv.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering
        conv.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        conv.primeMethod = .normal
        converter = conv
        let outCapacity = Int((Double(maxInputFrames) * outputRate / inputRate).rounded(.up)) + 4096
        guard let ib = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(maxInputFrames)),
              let ob = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(outCapacity)) else {
            throw StudioError.encodeFailed("Puffer für die Abtastratenwandlung konnten nicht angelegt werden.")
        }
        inBuffer = ib
        outBuffer = ob
        outBlock = FloatBlock(channels: channels, capacity: outCapacity)
    }

    /// Wandelt `block` (nil = Ende, Rest ausgeben) und ruft `emit` für jeden fertigen Ausgabeblock auf.
    func process(_ block: FloatBlock?, emit: (FloatBlock) throws -> Void) throws {
        let isEnd = block == nil
        var provided = false
        if let block {
            guard block.frames <= Int(inBuffer.frameCapacity), let dst = inBuffer.floatChannelData else {
                throw StudioError.encodeFailed("Block zu groß für die Abtastratenwandlung.")
            }
            for c in 0..<channels { dst[c].update(from: block.channels[c], count: block.frames) }
            inBuffer.frameLength = AVAudioFrameCount(block.frames)
            if block.frames == 0 { return }
        }
        let input = inBuffer
        while true {
            outBuffer.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
                if !isEnd && !provided {
                    provided = true
                    outStatus.pointee = .haveData
                    return input
                }
                outStatus.pointee = isEnd ? .endOfStream : .noDataNow
                return nil
            }
            if status == .error {
                throw StudioError.encodeFailed("Abtastratenwandlung: \(error?.localizedDescription ?? "unbekannter Fehler")")
            }
            let n = Int(outBuffer.frameLength)
            if n > 0, let src = outBuffer.floatChannelData {
                for c in 0..<channels { outBlock.channels[c].update(from: src[c], count: n) }
                outBlock.frames = n
                try emit(outBlock)
            }
            switch status {
            case .haveData:
                if n == 0 { return }
                continue
            case .inputRanDry, .endOfStream:
                return
            case .error:
                return
            @unknown default:
                return
            }
        }
    }
}
