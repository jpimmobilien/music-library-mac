import AVFoundation
import Foundation
import MLStudio
import MLTags

/// Liest die Angaben für `ExportResult` aus der fertigen Datei (nicht aus den Einstellungen).
enum ResultInspector {
    static func inspect(_ url: URL, format: StudioFormat, tagsWritten: Bool, passthrough: Bool) throws -> ExportResult {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw StudioError.encodeFailed("Die fertige Datei ist nicht lesbar: \(error.localizedDescription)")
        }
        let rate = file.fileFormat.sampleRate
        let channels = Int(file.fileFormat.channelCount)
        let duration = rate > 0 ? Double(file.length) / rate : 0
        let props = try? TagFile.read(url: url).audio

        var bitDepth: Int?
        if format.isLossless {
            if let bits = props?.bitsPerSample, bits > 0 {
                bitDepth = bits
            } else {
                let asbd = file.fileFormat.streamDescription.pointee
                bitDepth = asbd.mBitsPerChannel > 0 ? Int(asbd.mBitsPerChannel) : nil
            }
        }

        var kbps = 0
        switch format {
        case .mp3:
            if let info = try? MP3Stream.scan(url: url) {
                // CBR: Bitrate aus dem Frame-Kopf; VBR: Audiodaten · 8 / Dauer
                kbps = info.isCBR ? info.header.bitrateKbps : Int(info.averageKbps.rounded())
            }
        case .aac, .m4a, .wav, .aiff, .flac:
            // Angabe des Formats (TagLib: Audiodaten ohne Tags bzw. PCM-Rate)
            if let br = props?.bitrate, br > 0 { kbps = br }
        }
        if kbps == 0, duration > 0 {
            kbps = Int((Double(size) * 8 / duration / 1000).rounded())
        }
        return ExportResult(output: url, duration: duration, sampleRate: Int(rate.rounded()), channels: channels, bitDepth: bitDepth,
                            bitrateKbps: kbps, fileSize: size, tagsWritten: tagsWritten, passthrough: passthrough)
    }
}
