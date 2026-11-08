import Foundation
import MLStudio

/// Wählt den passenden Leser für eine Datei: Ogg Vorbis → AVAudioFile → AVAssetReader → (falls vorhanden)
/// System-FFmpeg über eine temporäre CAF-Datei. Sonst ein verständlicher Fehler.
enum SourceOpener {
    /// Videocontainer: gleich über AVAssetReader lesen.
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "qt", "3gp", "3g2"]
    static let oggExtensions: Set<String> = ["ogg", "oga"]
    /// Bekannte Audio-/Videoendungen (für die Fehlermeldung „beschädigt“ statt „nicht unterstützt“).
    static let knownExtensions: Set<String> = [
        "mp3", "m4a", "m4b", "aac", "adts", "wav", "wave", "aif", "aiff", "aifc", "flac", "caf", "alac", "ogg", "oga",
        "mp4", "mov", "m4v", "3gp", "3g2", "opus", "webm", "mkv", "mka", "wma", "asf",
    ]

    static func open(_ url: URL, downmixToStereo: Bool) async throws -> PCMReader {
        let path = url.path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
            throw StudioError.decodeFailed("Die Datei wurde nicht gefunden.")
        }
        guard FileManager.default.isReadableFile(atPath: path) else {
            throw StudioError.decodeFailed("Die Datei kann nicht gelesen werden (keine Berechtigung).")
        }
        let ext = url.pathExtension.lowercased()
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        if let size = attributes?[.size] as? NSNumber, size.int64Value == 0 {
            throw StudioError.decodeFailed("Die Datei ist leer.")
        }
        if oggExtensions.contains(ext), let r = try? OggPCMReader(url: url, downmixToStereo: downmixToStereo) {
            return r
        }
        try Task.checkCancellation()
        if !videoExtensions.contains(ext), let r = try? AVFileReader(url: url, downmixToStereo: downmixToStereo) {
            return r
        }
        try Task.checkCancellation()
        if let r = try? await AssetPCMReader.open(url: url, downmixToStereo: downmixToStereo) {
            return r
        }
        try Task.checkCancellation()
        if FFmpegTool.path != nil {
            let caf: URL
            do {
                caf = try await FFmpegTool.convertToCAF(url)
            } catch let e as StudioError where e == .cancelled {
                throw e
            } catch is CancellationError {
                throw StudioError.cancelled
            } catch {
                throw unreadable(ext)
            }
            do {
                return try AVFileReader(url: caf, downmixToStereo: downmixToStereo, ownedFile: caf)
            } catch {
                try? FileManager.default.removeItem(at: caf)
                throw unreadable(ext)
            }
        }
        throw unreadable(ext)
    }

    private static func unreadable(_ ext: String) -> StudioError {
        if ["ogg", "oga", "opus", "webm", "mkv", "mka", "wma", "asf"].contains(ext) && FFmpegTool.path == nil {
            return .unsupportedFile(ext)
        }
        if knownExtensions.contains(ext) {
            return .decodeFailed("Sie ist beschädigt oder enthält keine lesbaren Audiodaten.")
        }
        return .unsupportedFile(ext)
    }
}

/// Optionales System-FFmpeg (z. B. Homebrew) – nur für exotische lokale Formate (WebM, MKV, Opus, WMA).
enum FFmpegTool {
    static let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]

    static var path: String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Ordner für temporäre Umwandlungen.
    static var temporaryDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AudioStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Wandelt die erste Audiospur verlustfrei (Float32) in eine temporäre CAF-Datei. Abbrechbar.
    static func convertToCAF(_ input: URL) async throws -> URL {
        guard let ffmpeg = path else { throw StudioError.toolMissing("ffmpeg") }
        let out = temporaryDirectory.appendingPathComponent("ffmpeg-\(UUID().uuidString).caf")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = ["-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-i", input.path,
                             "-vn", "-sn", "-dn", "-map", "0:a:0", "-c:a", "pcm_f32le", "-f", "caf", out.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Int32, Error>) in
                process.terminationHandler = { p in c.resume(returning: p.terminationStatus) }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    c.resume(throwing: StudioError.decodeFailed("FFmpeg konnte nicht gestartet werden."))
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        let errText = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile().suffix(600), as: UTF8.self)
        if Task.isCancelled {
            try? FileManager.default.removeItem(at: out)
            throw StudioError.cancelled
        }
        guard status == 0, FileManager.default.fileExists(atPath: out.path) else {
            try? FileManager.default.removeItem(at: out)
            throw StudioError.decodeFailed("FFmpeg: \(errText.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return out
    }
}
