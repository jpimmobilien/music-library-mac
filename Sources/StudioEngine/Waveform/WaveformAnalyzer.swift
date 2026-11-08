import Accelerate
import Foundation
import MLStudio

/// Hüllkurve einer Datei für die Wellenform: je 256 Frames kleinster und größter Wert über alle Kanäle,
/// blockweise gelesen und mit vDSP berechnet; Fortschritt höchstens ~10×/s, abbrechbar.
public struct WaveformAnalyzer: WaveformProviding {
    public static let framesPerBucket = 256
    /// Frames je Leseblock (Vielfaches von `framesPerBucket`).
    static let blockFrames = 256 * 512

    public init() {}

    public func waveform(for file: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> WaveformData {
        do {
            return try await analyze(file, progress: ProgressReporter(progress))
        } catch let error as StudioError {
            throw error
        } catch is CancellationError {
            throw StudioError.cancelled
        } catch {
            throw StudioError.decodeFailed(error.localizedDescription)
        }
    }

    private func analyze(_ file: URL, progress: ProgressReporter) async throws -> WaveformData {
        progress.report(0, force: true)
        let reader = try await SourceOpener.open(file, downmixToStereo: false)
        defer { reader.close() }
        let fpb = Self.framesPerBucket
        let channels = reader.channelCount
        let total = reader.lengthFrames
        var mins: [Float] = []
        var maxs: [Float] = []
        if let total { mins.reserveCapacity(Int(total) / fpb + 2); maxs.reserveCapacity(Int(total) / fpb + 2) }

        let block = FloatBlock(channels: channels, capacity: Self.blockFrames)
        let rowMin = UnsafeMutablePointer<Float>.allocate(capacity: Self.blockFrames)
        let rowMax = UnsafeMutablePointer<Float>.allocate(capacity: Self.blockFrames)
        defer { rowMin.deallocate(); rowMax.deallocate() }
        // Angefangener Block über Lesegrenzen hinweg
        var carryCount = 0
        var carryMin: Float = .greatestFiniteMagnitude
        var carryMax: Float = -.greatestFiniteMagnitude
        var framesRead: Int64 = 0

        while true {
            if Task.isCancelled { throw StudioError.cancelled }
            let n = try reader.read(into: block, maxFrames: Self.blockFrames)
            if n == 0 { break }
            // Kanäle zu einer Min- und einer Max-Zeile zusammenfassen
            rowMin.update(from: block.channels[0], count: n)
            rowMax.update(from: block.channels[0], count: n)
            for c in 1..<max(channels, 1) where c < channels {
                vDSP_vmin(rowMin, 1, block.channels[c], 1, rowMin, 1, vDSP_Length(n))
                vDSP_vmax(rowMax, 1, block.channels[c], 1, rowMax, 1, vDSP_Length(n))
            }
            var i = 0
            // Erst den angefangenen Block auffüllen
            if carryCount > 0 {
                let take = min(fpb - carryCount, n)
                var lo: Float = 0, hi: Float = 0
                vDSP_minv(rowMin, 1, &lo, vDSP_Length(take))
                vDSP_maxv(rowMax, 1, &hi, vDSP_Length(take))
                carryMin = min(carryMin, lo)
                carryMax = max(carryMax, hi)
                carryCount += take
                i = take
                if carryCount == fpb {
                    mins.append(carryMin); maxs.append(carryMax)
                    carryCount = 0; carryMin = .greatestFiniteMagnitude; carryMax = -.greatestFiniteMagnitude
                }
            }
            while i + fpb <= n {
                var lo: Float = 0, hi: Float = 0
                vDSP_minv(rowMin + i, 1, &lo, vDSP_Length(fpb))
                vDSP_maxv(rowMax + i, 1, &hi, vDSP_Length(fpb))
                mins.append(lo); maxs.append(hi)
                i += fpb
            }
            if i < n {
                var lo: Float = 0, hi: Float = 0
                vDSP_minv(rowMin + i, 1, &lo, vDSP_Length(n - i))
                vDSP_maxv(rowMax + i, 1, &hi, vDSP_Length(n - i))
                carryMin = min(carryMin, lo)
                carryMax = max(carryMax, hi)
                carryCount += n - i
            }
            framesRead += Int64(n)
            if let total, total > 0 { progress.report(Double(framesRead) / Double(total)) }
            await Task.yield()
        }
        if carryCount > 0 { mins.append(carryMin); maxs.append(carryMax) }
        guard framesRead > 0 else { throw StudioError.decodeFailed("Keine Audiodaten gefunden.") }
        let duration = Double(framesRead) / reader.sampleRate
        let data = WaveformData(base: mins, maxs: maxs, framesPerBucket: fpb, sampleRate: reader.sampleRate, duration: duration)
        progress.report(1, force: true)
        return data
    }
}
