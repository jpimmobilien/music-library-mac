import Foundation
import MLStudio
import OggVorbis

/// Liest Ogg-Vorbis-Dateien (.ogg/.oga) über den vorhandenen Decoder (stb_vorbis).
final class OggPCMReader: PCMReader {
    private let decoder: VorbisDecoder
    private var scratch: UnsafeMutablePointer<Float>
    private var scratchFrames: Int
    private let matrix: [(Float, Float)]?

    let sampleRate: Double
    let channelCount: Int
    let sourceChannelCount: Int
    let lengthFrames: Int64?
    let format = SourceFormat(codec: "Vorbis", isLossless: false, isFloat: false, bitsPerSample: nil)

    init(url: URL, downmixToStereo: Bool) throws {
        do {
            decoder = try VorbisDecoder(path: url.path)
        } catch {
            throw StudioError.decodeFailed("Ogg Vorbis: \(error)")
        }
        sampleRate = Double(decoder.sampleRate)
        sourceChannelCount = decoder.channels
        guard sampleRate > 0, sourceChannelCount > 0 else { throw StudioError.decodeFailed("Ungültige Ogg-Vorbis-Datei.") }
        if downmixToStereo && sourceChannelCount > 2 {
            channelCount = 2
            matrix = StereoDownmix.vorbisMatrix(channels: sourceChannelCount)
        } else {
            channelCount = sourceChannelCount
            matrix = nil
        }
        lengthFrames = decoder.totalFrames > 0 ? Int64(decoder.totalFrames) : nil
        scratchFrames = 8192
        scratch = UnsafeMutablePointer<Float>.allocate(capacity: scratchFrames * sourceChannelCount)
    }

    deinit { scratch.deallocate() }

    func seek(to frame: Int64) throws {
        if !decoder.seek(toFrame: UInt64(max(0, frame))) {
            throw StudioError.decodeFailed("Sprung in der Ogg-Datei fehlgeschlagen.")
        }
    }

    func read(into block: FloatBlock, maxFrames: Int) throws -> Int {
        let limit = max(0, min(maxFrames, block.capacity))
        let src = sourceChannelCount
        var filled = 0
        while filled < limit {
            let want = min(limit - filled, scratchFrames)
            let n = decoder.read(into: scratch, maxFrames: want)
            if n <= 0 { break }
            if let matrix {
                let l = block.channels[0] + filled, r = block.channels[1] + filled
                for i in 0..<n {
                    var a: Float = 0, b: Float = 0
                    let frame = scratch + i * src
                    for c in 0..<src {
                        a += frame[c] * matrix[c].0
                        b += frame[c] * matrix[c].1
                    }
                    l[i] = a
                    r[i] = b
                }
            } else {
                for c in 0..<channelCount {
                    let dst = block.channels[c] + filled
                    for i in 0..<n { dst[i] = scratch[i * src + c] }
                }
            }
            filled += n
        }
        block.frames = filled
        return filled
    }

    func close() {}
}
