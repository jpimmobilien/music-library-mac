import AVFoundation
import CoreMedia
import Foundation
import MLStudio

/// Liest die erste Audiospur über AVAssetReader – für Videocontainer (MP4/MOV/M4V) und alles, was
/// AVAudioFile nicht öffnet. Sprünge sind framegenau: der Leser startet etwas früher und verwirft
/// anhand der Zeitstempel alles vor dem Ziel.
final class AssetPCMReader: PCMReader {
    private let asset: AVURLAsset
    private let track: AVAssetTrack
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    /// Nächster auszuliefernder Frame (absolut).
    private var position: Int64 = 0
    /// Solange true, werden Frames vor `position` anhand der Zeitstempel verworfen.
    private var seeking = false
    /// Zwischenspeicher (verschachtelt) aus dem letzten Sample-Puffer.
    private var pending: UnsafeMutablePointer<Float>
    private var pendingCapacity: Int
    private var pendingFrames = 0
    private var pendingOffset = 0

    let sampleRate: Double
    let channelCount: Int
    let sourceChannelCount: Int
    let lengthFrames: Int64?
    let format: SourceFormat

    static func open(url: URL, downmixToStereo: Bool) async throws -> AssetPCMReader {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw StudioError.decodeFailed("AVAsset: \(error.localizedDescription)")
        }
        guard let track = tracks.first else { throw StudioError.decodeFailed("Die Datei enthält keine Audiospur.") }
        let descriptions = try await track.load(.formatDescriptions)
        guard let desc = descriptions.first, let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(desc) else {
            throw StudioError.decodeFailed("Unbekanntes Audioformat der Spur.")
        }
        let range = try await track.load(.timeRange)
        return try AssetPCMReader(asset: asset, track: track, asbd: asbdPointer.pointee, range: range, downmixToStereo: downmixToStereo)
    }

    private init(asset: AVURLAsset, track: AVAssetTrack, asbd: AudioStreamBasicDescription, range: CMTimeRange, downmixToStereo: Bool) throws {
        self.asset = asset
        self.track = track
        sampleRate = asbd.mSampleRate
        sourceChannelCount = Int(asbd.mChannelsPerFrame)
        guard sampleRate > 0, sourceChannelCount > 0 else { throw StudioError.decodeFailed("Ungültiges Audioformat der Spur.") }
        channelCount = downmixToStereo && sourceChannelCount > 2 ? 2 : sourceChannelCount
        let seconds = range.duration.seconds
        lengthFrames = seconds.isFinite && seconds > 0 ? Int64((seconds * sampleRate).rounded()) : nil
        format = AVFileReader.describe(asbd)
        pendingCapacity = 8192 * max(channelCount, 1)
        pending = UnsafeMutablePointer<Float>.allocate(capacity: pendingCapacity)
        try start(at: 0)
    }

    deinit {
        reader?.cancelReading()
        pending.deallocate()
    }

    private func start(at frame: Int64) throws {
        reader?.cancelReading()
        let r: AVAssetReader
        do {
            r = try AVAssetReader(asset: asset)
        } catch {
            throw StudioError.decodeFailed("AVAssetReader: \(error.localizedDescription)")
        }
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        if channelCount != sourceChannelCount {
            var layout = AudioChannelLayout()
            layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
            settings[AVNumberOfChannelsKey] = 2
            settings[AVChannelLayoutKey] = Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
        }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        out.alwaysCopiesSampleData = false
        guard r.canAdd(out) else { throw StudioError.decodeFailed("Die Audiospur kann nicht gelesen werden.") }
        r.add(out)
        // Eine Sekunde früher beginnen und genau ab `frame` ausliefern
        let begin = max(0, frame - Int64(sampleRate))
        if begin > 0 {
            r.timeRange = CMTimeRange(start: CMTime(value: begin, timescale: CMTimeScale(sampleRate.rounded())),
                                      duration: .positiveInfinity)
        }
        guard r.startReading() else {
            throw StudioError.decodeFailed(r.error?.localizedDescription ?? "Die Audiospur kann nicht gelesen werden.")
        }
        reader = r
        output = out
        position = frame
        seeking = true
        pendingFrames = 0
        pendingOffset = 0
    }

    func seek(to frame: Int64) throws {
        try start(at: max(0, frame))
    }

    /// Lädt den nächsten Sample-Puffer in `pending`. false = Ende.
    private func loadNext() throws -> Bool {
        guard let out = output, let r = reader else { return false }
        while true {
            guard let sb = out.copyNextSampleBuffer() else {
                if r.status == .failed {
                    throw StudioError.decodeFailed(r.error?.localizedDescription ?? "Lesefehler in der Audiospur.")
                }
                return false
            }
            let n = CMSampleBufferGetNumSamples(sb)
            guard n > 0, let bb = CMSampleBufferGetDataBuffer(sb) else { continue }
            let ch = channelCount
            if n * ch > pendingCapacity {
                pending.deallocate()
                pendingCapacity = n * ch
                pending = UnsafeMutablePointer<Float>.allocate(capacity: pendingCapacity)
            }
            let bytes = n * ch * MemoryLayout<Float>.size
            let status = CMBlockBufferCopyDataBytes(bb, atOffset: 0, dataLength: bytes, destination: pending)
            guard status == kCMBlockBufferNoErr else { throw StudioError.decodeFailed("Audiodaten konnten nicht kopiert werden (\(status)).") }
            pendingFrames = n
            pendingOffset = 0
            if seeking {
                let pts = CMSampleBufferGetPresentationTimeStamp(sb)
                if pts.isValid && pts.isNumeric {
                    let first = Int64((pts.seconds * sampleRate).rounded())
                    if first + Int64(n) <= position { continue }        // ganz vor dem Ziel
                    if first < position { pendingOffset = Int(position - first) }
                }
                seeking = false
            }
            return true
        }
    }

    func read(into block: FloatBlock, maxFrames: Int) throws -> Int {
        let limit = max(0, min(maxFrames, block.capacity))
        var filled = 0
        let ch = channelCount
        while filled < limit {
            if pendingOffset >= pendingFrames {
                if try !loadNext() { break }
                continue
            }
            let take = min(limit - filled, pendingFrames - pendingOffset)
            for c in 0..<ch {
                let dst = block.channels[c] + filled
                var src = pending + (pendingOffset * ch + c)
                for i in 0..<take {
                    dst[i] = src.pointee
                    src += ch
                }
            }
            pendingOffset += take
            filled += take
            position += Int64(take)
        }
        block.frames = filled
        return filled
    }

    func close() {
        reader?.cancelReading()
        reader = nil
        output = nil
    }
}
