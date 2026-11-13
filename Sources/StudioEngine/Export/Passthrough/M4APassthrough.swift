import AVFoundation
import Foundation
import MLStudio

/// M4A/AAC-in-MP4 ohne Neukodierung schneiden: AVAssetExportSession mit
/// `AVAssetExportPresetPassthrough` und `timeRange`.
enum M4APassthrough {
    /// Prüft, ob die Quelle AAC in einem MPEG-4-Container ohne Videospur ist; liefert Abtastrate und Dauer.
    static func eligibleSource(_ url: URL) async -> (sampleRate: Int, duration: Double)? {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let video = try? await asset.loadTracks(withMediaType: .video), video.isEmpty,
              let audio = try? await asset.loadTracks(withMediaType: .audio), audio.count == 1,
              let descs = try? await audio[0].load(.formatDescriptions), let desc = descs.first,
              let asbd = AudioTrackFormat.decoded(desc),   // HE-AAC: Rate des dekodierten Tons
              AVFileReader.codecName(asbd.mFormatID) == "AAC",
              let duration = try? await asset.load(.duration), duration.seconds.isFinite, duration.seconds > 0 else { return nil }
        return (Int(asbd.mSampleRate.rounded()), duration.seconds)
    }

    /// Schreibt `[start, end)` nach `dest` (Datei darf noch nicht existieren).
    static func export(source: URL, start: Double, end: Double?, sampleRate: Int, to dest: URL,
                       progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: source, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw StudioError.encodeFailed("Schneiden ohne Neukodierung ist für diese Datei nicht möglich.")
        }
        let scale = CMTimeScale(max(sampleRate, 1))
        let startTime = CMTime(value: CMTimeValue((start * Double(scale)).rounded()), timescale: scale)
        let duration: CMTime = end.map { CMTime(value: CMTimeValue((($0 - start) * Double(scale)).rounded()), timescale: scale) } ?? .positiveInfinity
        session.timeRange = CMTimeRange(start: startTime, duration: duration)
        session.shouldOptimizeForNetworkUse = false
        try? FileManager.default.removeItem(at: dest)

        if #available(macOS 15, *) {
            let monitor = Task {
                for await state in session.states(updateInterval: 0.1) {
                    if case .exporting(let p) = state { progress(p.fractionCompleted) }
                }
            }
            defer { monitor.cancel() }
            do {
                try await session.export(to: dest, as: .m4a)
            } catch is CancellationError {
                throw StudioError.cancelled
            } catch {
                if Task.isCancelled { throw StudioError.cancelled }
                throw StudioError.encodeFailed("Schneiden ohne Neukodierung fehlgeschlagen: \(error.localizedDescription)")
            }
        } else {
            session.outputURL = dest
            session.outputFileType = .m4a
            let box = SessionBox(session)
            let poll = Task {
                while !Task.isCancelled {
                    progress(Double(box.session.progress))
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            defer { poll.cancel() }
            await withTaskCancellationHandler {
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    box.session.exportAsynchronously { c.resume() }
                }
            } onCancel: {
                box.session.cancelExport()
            }
            if Task.isCancelled || session.status == .cancelled { throw StudioError.cancelled }
            guard session.status == .completed else {
                throw StudioError.encodeFailed("Schneiden ohne Neukodierung fehlgeschlagen: \(session.error?.localizedDescription ?? "unbekannter Fehler")")
            }
        }
    }
}

/// AVAssetExportSession über Task-Grenzen reichen (die Sitzung ist intern threadsicher).
private final class SessionBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}
