import Foundation
import AVFoundation
import OggVorbis

/// macOS kann Ogg Vorbis nicht selbst lesen. Vor der Wiedergabe wird eine Vorbis-Datei deshalb einmalig in
/// unkomprimiertes PCM (CAF, 16 Bit) umgewandelt und zwischengespeichert. Danach läuft sie wie jedes andere
/// Format über `AVAudioFile` (Spulen, Position, Effekte, Ende-Erkennung). Die Originaldatei bleibt unberührt.
///
/// Ogg Opus und Ogg FLAC werden (noch) nicht unterstützt.
enum OggTranscoder {
    enum Failure: Error {
        case unsupportedChannelCount(Int)
        case decoder
    }

    /// Größe des Zwischenspeichers, ältere Umwandlungen werden darüber hinaus gelöscht.
    static let maxCacheBytes: Int64 = 2_000_000_000

    static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Music Library/Ogg", isDirectory: true)
    }

    static func isOgg(_ url: URL) -> Bool {
        ["ogg", "oga"].contains(url.pathExtension.lowercased())
    }

    /// Stabiler Schlüssel aus Pfad, Größe und Änderungsdatum (FNV-1a, unabhängig vom Prozess).
    private static func cacheURL(for source: URL) -> URL? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: source.path) else { return nil }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(source.path)|\(size)|\(Int64(modified * 1000))".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return cacheDirectory.appendingPathComponent(String(format: "%016llx.caf", hash))
    }

    /// Bereits umgewandelte Datei (oder `nil`).
    static func cached(for source: URL) -> URL? {
        guard let url = cacheURL(for: source), FileManager.default.fileExists(atPath: url.path) else { return nil }
        // „Zuletzt benutzt“ für das Aufräumen
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return url
    }

    /// Wandelt um (blockierend – nicht auf dem Hauptthread aufrufen) und liefert die abspielbare Datei.
    static func decode(_ source: URL) throws -> URL {
        if let done = cached(for: source) { return done }
        guard let target = cacheURL(for: source) else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let partial = cacheDirectory.appendingPathComponent(UUID().uuidString + "-teil.caf")
        defer { try? FileManager.default.removeItem(at: partial) }
        try write(source, to: partial)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: partial, to: target)
        prune(keeping: target)
        return target
    }

    private static func write(_ source: URL, to destination: URL) throws {
        let decoder = try VorbisDecoder(path: source.path)
        let channels = decoder.channels
        guard (1...2).contains(channels) else { throw Failure.unsupportedChannelCount(channels) }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(decoder.sampleRate), channels: AVAudioChannelCount(channels)) else {
            throw Failure.decoder
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Double(decoder.sampleRate),
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        // Die Datei wird beim Freigeben von `out` abgeschlossen (Ende dieser Funktion).
        let out = try AVAudioFile(forWriting: destination, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let chunk = 16_384
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk)),
              let planes = buffer.floatChannelData else { throw Failure.decoder }
        var interleaved = [Float](repeating: 0, count: chunk * channels)
        while true {
            let frames = interleaved.withUnsafeMutableBufferPointer { decoder.read(into: $0.baseAddress!, maxFrames: chunk) }
            if frames == 0 { break }
            interleaved.withUnsafeBufferPointer { src in
                for c in 0..<channels {
                    let dst = planes[c]
                    for i in 0..<frames { dst[i] = src[i * channels + c] }
                }
            }
            buffer.frameLength = AVAudioFrameCount(frames)
            try out.write(from: buffer)
        }
    }

    /// Hält den Zwischenspeicher unter `maxCacheBytes` (zuletzt benutzte Dateien bleiben).
    private static func prune(keeping keep: URL) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: keys) else { return }
        var entries = files.compactMap { url -> (URL, Int64, Date)? in
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, Int64(v.fileSize ?? 0), v.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.1 }
        entries.sort { $0.2 < $1.2 }
        for (url, size, _) in entries where total > maxCacheBytes && url != keep {
            try? fm.removeItem(at: url)
            total -= size
        }
    }

    /// Zwischenspeicher leeren (Einstellungen → Bibliothek).
    static func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
    }
}
