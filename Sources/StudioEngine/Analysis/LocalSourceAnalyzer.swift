import AVFoundation
import Foundation
import MLCore
import MLStudio
import MLTags

/// Lokale Audio-/Videodatei untersuchen: Tags und Cover (MLTags/TagLib), technische Angaben (TagLib,
/// sonst AVFoundation), bei Videodateien die Audiospur und ein Standbild als Vorschaubild.
public struct LocalSourceAnalyzer: LocalSourceAnalyzing {
    public init() {}

    static let losslessCodecs: Set<String> = ["FLAC", "ALAC", "PCM", "PCM Float", "WavPack", "Monkey's Audio", "TTA", "WMA Lossless", "DSD"]

    public func analyze(file: URL) async throws -> SourceInfo {
        let url = file.standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            throw StudioError.decodeFailed("Die Datei wurde nicht gefunden.")
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw StudioError.decodeFailed("Die Datei kann nicht gelesen werden (keine Berechtigung).")
        }
        let ext = url.pathExtension.lowercased()
        let isVideo = SourceOpener.videoExtensions.contains(ext)
        var info = SourceInfo(id: url.path, kind: .localFile, url: url, title: url.deletingPathExtension().lastPathComponent,
                              localFile: url)
        info.fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        var meta = StudioMetadata()
        var known = false

        // 1. Tags und Eigenschaften über TagLib
        if let tags = try? TagFile.read(url: url) {
            let v = tags.values
            meta.title = v.title ?? ""
            meta.artist = v.artists.joined(separator: "; ")
            meta.album = v.album ?? ""
            meta.albumArtist = v.albumArtists.joined(separator: "; ")
            meta.year = v.year
            meta.genre = v.genres.first ?? ""
            meta.trackNumber = v.trackNumber
            if let pic = v.frontCover, let cover = CoverImage.embeddable(pic.data) {
                meta.cover = cover.data
            }
            let a = tags.audio
            if a.durationMs > 0 || a.sampleRate > 0 {
                known = true
                if a.durationMs > 0 { info.duration = Double(a.durationMs) / 1000 }
                if !a.codec.isEmpty { info.codec = a.codec }
                if a.bitrate > 0 { info.bitrateKbps = a.bitrate }
                if a.sampleRate > 0 { info.sampleRate = a.sampleRate }
                if a.channels > 0 { info.channels = a.channels }
                let lossless = Self.losslessCodecs.contains(a.codec)
                info.isLossless = a.codec.isEmpty ? nil : lossless
                if lossless, a.bitsPerSample > 0 { info.bitDepth = a.bitsPerSample }
            }
        }
        // MP3: samplegenaue Dauer aus Frameanzahl und LAME-Angaben (TagLib rechnet ohne Verzögerung/Auffüllung)
        if ext == "mp3", let mp3 = try? MP3Stream.scan(url: url), mp3.frameCount > 0 {
            info.duration = mp3.duration
        }
        try Task.checkCancellation()

        // 2. AVFoundation: Videodateien, Formate ohne TagLib-Unterstützung, genauere Dauer
        // (MPEG-4-Audio ebenfalls: AVFoundation berücksichtigt die Encoder-Verzögerung, TagLib nicht)
        let mpeg4Audio = ["m4a", "m4b", "m4r"].contains(ext)
        if isVideo || mpeg4Audio || !known || info.duration == nil {
            if let av = await Self.avDetails(url) {
                known = true
                if isVideo || mpeg4Audio || info.duration == nil { info.duration = av.duration ?? info.duration }
                if isVideo || info.codec == nil { info.codec = av.codec }
                if info.sampleRate == nil || isVideo { info.sampleRate = av.sampleRate }
                if info.channels == nil || isVideo { info.channels = av.channels }
                if info.bitrateKbps == nil || isVideo, let br = av.bitrateKbps { info.bitrateKbps = br }
                if info.isLossless == nil || isVideo { info.isLossless = av.lossless }
                if av.lossless, info.bitDepth == nil { info.bitDepth = av.bitDepth }
                if meta.title.isEmpty, let t = av.title { meta.title = t }
                if meta.artist.isEmpty, let a = av.artist { meta.artist = a }
                if meta.album.isEmpty, let a = av.album { meta.album = a }
                if meta.cover == nil, let art = av.artwork, let cover = CoverImage.embeddable(art) { meta.cover = cover.data }
                if isVideo, meta.cover == nil { info.thumbnail = av.frame }
            }
        }
        try Task.checkCancellation()

        // 3. Ogg Vorbis ohne Tags oder exotische Formate über die Leser (Ogg, FFmpeg)
        if !known {
            // wirft `unsupportedFile` bzw. `decodeFailed` mit verständlicher Meldung
            let reader = try await SourceOpener.open(url, downmixToStereo: false)
            defer { reader.close() }
            known = true
            info.duration = reader.durationSeconds
            info.sampleRate = Int(reader.sampleRate.rounded())
            info.channels = reader.sourceChannelCount
            info.codec = reader.format.codec
            info.isLossless = reader.format.isLossless
            if reader.format.isLossless { info.bitDepth = reader.format.bitsPerSample }
        }
        guard known else { throw StudioError.unsupportedFile(ext) }

        if info.bitrateKbps == nil, let size = info.fileSize, let d = info.duration, d > 0 {
            info.bitrateKbps = Int((Double(size) * 8 / d / 1000).rounded())
        }
        if !meta.title.trimmingCharacters(in: .whitespaces).isEmpty { info.title = meta.title } else { meta.title = info.title }
        if !meta.artist.isEmpty { info.uploader = meta.artist }
        if let cover = meta.cover { info.thumbnail = cover }
        info.suggested = meta
        return info
    }

    struct AVDetails {
        var duration: Double?
        var codec: String
        var sampleRate: Int?
        var channels: Int?
        var bitrateKbps: Int?
        var lossless: Bool
        var bitDepth: Int?
        var title: String?
        var artist: String?
        var album: String?
        var artwork: Data?
        var frame: Data?
    }

    /// Angaben der ersten Audiospur über AVFoundation (nil, wenn keine Audiospur lesbar ist).
    static func avDetails(_ url: URL) async -> AVDetails? {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio), let track = tracks.first,
              let descs = try? await track.load(.formatDescriptions), let desc = descs.first,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee else { return nil }
        let format = AVFileReader.describe(asbd)
        var d = AVDetails(codec: format.codec, lossless: format.isLossless)
        if let range = try? await track.load(.timeRange), range.duration.seconds.isFinite, range.duration.seconds > 0 {
            d.duration = range.duration.seconds
        } else if let dur = try? await asset.load(.duration), dur.seconds.isFinite, dur.seconds > 0 {
            d.duration = dur.seconds
        }
        d.sampleRate = asbd.mSampleRate > 0 ? Int(asbd.mSampleRate.rounded()) : nil
        d.channels = asbd.mChannelsPerFrame > 0 ? Int(asbd.mChannelsPerFrame) : nil
        if let rate = try? await track.load(.estimatedDataRate), rate > 0 { d.bitrateKbps = Int((Double(rate) / 1000).rounded()) }
        d.bitDepth = format.bitsPerSample
        if let items = try? await asset.load(.commonMetadata) {
            for item in items {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle: d.title = try? await item.load(.stringValue)
                case .commonKeyArtist: d.artist = try? await item.load(.stringValue)
                case .commonKeyAlbumName: d.album = try? await item.load(.stringValue)
                case .commonKeyArtwork: d.artwork = try? await item.load(.dataValue)
                default: break
                }
            }
        }
        // Standbild aus Videodateien als Vorschaubild
        if let video = try? await asset.loadTracks(withMediaType: .video), !video.isEmpty {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)
            let seconds = min(1.0, (d.duration ?? 0) / 3)
            if let image = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image {
                d.frame = CoverImage.jpegData(from: image)
            }
        }
        return d
    }
}
