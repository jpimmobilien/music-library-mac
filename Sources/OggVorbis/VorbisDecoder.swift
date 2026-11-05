import Foundation
import CVorbis

/// Ogg-Vorbis-Decoder (stb_vorbis). macOS selbst kann Ogg nicht abspielen; die App wandelt
/// Vorbis-Dateien damit vor der Wiedergabe in PCM um.
public final class VorbisDecoder {
    public enum DecodeError: Error, Equatable {
        case cannotOpen(code: Int32)
    }

    private let handle: OpaquePointer
    public let channels: Int
    public let sampleRate: Int
    /// Länge in Frames (Samples je Kanal); 0, wenn unbekannt.
    public let totalFrames: UInt64

    public init(path: String) throws {
        var error: Int32 = 0
        guard let h = path.withCString({ cvorbis_open($0, &error) }) else {
            throw DecodeError.cannotOpen(code: error)
        }
        handle = h
        channels = Int(cvorbis_channels(h))
        sampleRate = Int(cvorbis_sample_rate(h))
        totalFrames = cvorbis_total_frames(h)
    }

    deinit {
        cvorbis_close(handle)
    }

    public var durationMs: Int64 {
        sampleRate > 0 ? Int64(Double(totalFrames) / Double(sampleRate) * 1000) : 0
    }

    /// Liest bis zu `maxFrames` Frames verschachtelt in `buffer` (Größe ≥ maxFrames × channels). 0 = Ende.
    public func read(into buffer: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int {
        Int(cvorbis_read_interleaved(handle, buffer, Int32(maxFrames)))
    }

    /// Liest die nächsten Frames als Array (verschachtelt). Leer = Ende.
    public func read(frames: Int) -> [Float] {
        var out = [Float](repeating: 0, count: frames * channels)
        let n = out.withUnsafeMutableBufferPointer { read(into: $0.baseAddress!, maxFrames: frames) }
        out.removeSubrange((n * channels)...)
        return out
    }

    @discardableResult
    public func seek(toFrame frame: UInt64) -> Bool {
        cvorbis_seek(handle, frame) != 0
    }
}
