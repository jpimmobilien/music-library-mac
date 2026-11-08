import Foundation
import MLStudio
import MLTags

/// Ein einzelner Export (siehe `AudioExporter`).
final class ExportJob {
    let request: ExportRequest
    let control: JobControl
    let reporter: ProgressReporter
    /// Frames je Block beim Lesen und Kodieren.
    static let blockFrames = 32_768

    init(request: ExportRequest, control: JobControl, reporter: ProgressReporter) {
        self.request = request
        self.control = control
        self.reporter = reporter
    }

    func run() async throws -> ExportResult {
        let options = request.options.normalized()
        let format = options.format
        let input = request.input
        guard FileManager.default.fileExists(atPath: input.path) else {
            throw StudioError.decodeFailed("Die Quelldatei wurde nicht gefunden.")
        }
        reporter.report(0, force: true)
        try await control.checkpoint()
        let output = try AtomicOutput(final: request.output)
        defer { if !output.committed { output.discard() } }

        var passthrough = false
        if request.preferPassthrough && request.fadeIn <= 0 && request.fadeOut <= 0 {
            passthrough = try await lossyPassthrough(options: options, output: output)
        }
        if !passthrough {
            passthrough = try await encode(options: options, output: output)
        }
        try await control.checkpoint()
        reporter.report(0.97)
        let tagsWritten = try StudioTagWriter.write(to: output.temp, format: format, metadata: request.metadata, copyFrom: request.copyTagsFrom)
        try await control.checkpoint()
        try output.commit()
        let result = try ResultInspector.inspect(request.output, format: format, tagsWritten: tagsWritten, passthrough: passthrough)
        reporter.report(1, force: true)
        return result
    }

    // MARK: - Ohne Neukodierung (MP3, M4A)

    /// true, wenn die Datei ohne Neukodierung geschrieben wurde.
    private func lossyPassthrough(options: ExportOptions, output: AtomicOutput) async throws -> Bool {
        let ext = request.input.pathExtension.lowercased()
        let control = self.control
        let reporter = self.reporter
        switch options.format {
        case .mp3 where ext == "mp3":
            guard let info = try? MP3Stream.scan(url: request.input) else { return false }
            if let rate = options.sampleRate, rate != info.header.sampleRate { return false }
            let range = request.trim?.resolved(duration: info.duration) ?? (start: 0, end: nil)
            _ = try await MP3Stream.cut(source: request.input, info: info, start: range.start, end: range.end, to: output.temp,
                                        progress: { reporter.report($0 * 0.95) },
                                        check: { try await control.checkpoint() })
            return true
        case .m4a where ["m4a", "mp4", "m4b"].contains(ext):
            guard let src = await M4APassthrough.eligibleSource(request.input) else { return false }
            if let rate = options.sampleRate, rate != src.sampleRate { return false }
            let range = request.trim?.resolved(duration: src.duration) ?? (start: 0, end: nil)
            try await control.checkpoint()
            try await M4APassthrough.export(source: request.input, start: range.start, end: range.end, sampleRate: src.sampleRate,
                                            to: output.temp, progress: { reporter.report($0 * 0.95) })
            return true
        default:
            return false
        }
    }

    // MARK: - Dekodieren und Kodieren

    /// Normaler Weg. Rückgabe: true, wenn eine verlustfreie Quelle bitgenau im selben Format neu geschrieben wurde.
    private func encode(options: ExportOptions, output: AtomicOutput) async throws -> Bool {
        let format = options.format
        let reader = try await SourceOpener.open(request.input, downmixToStereo: true)
        defer { reader.close() }
        try await control.checkpoint()

        let srcRate = reader.sampleRate
        let srcRateInt = Int(srcRate.rounded())
        // Bittiefe der Quelle: aus der Formatbeschreibung, bei FLAC/ALAC notfalls über TagLib
        var srcFormat = reader.format
        if srcFormat.isLossless, !srcFormat.isFloat, srcFormat.bitsPerSample == nil,
           let bits = (try? TagFile.read(url: request.input))?.audio.bitsPerSample, bits > 0 {
            srcFormat.bitsPerSample = bits
        }

        // Ausschnitt in Frames der Quelle
        var startFrame: Int64 = 0
        var endFrame: Int64? = reader.lengthFrames
        if let trim = request.trim {
            let r = trim.resolved(duration: reader.durationSeconds)
            startFrame = Int64((r.start * srcRate).rounded())
            if let e = r.end { endFrame = Int64((e * srcRate).rounded()) }
        }
        if let e = endFrame, let len = reader.lengthFrames { endFrame = min(e, len) }
        if startFrame > 0 { try reader.seek(to: startFrame) }
        let inFrames: Int64? = endFrame.map { max(0, $0 - startFrame) }

        // Gleiches verlustfreies Format: Bittiefe, Abtastrate und Kanäle der Quelle beibehalten
        let srcExt = request.input.pathExtension.lowercased()
        let sameLossless = request.preferPassthrough && request.fadeIn <= 0 && request.fadeOut <= 0 && srcFormat.isLossless && (
            (format == .wav && ["wav", "wave"].contains(srcExt)) ||
            (format == .flac && srcExt == "flac") ||
            (format == .aiff && ["aif", "aiff", "aifc"].contains(srcExt)))

        let outChannels: Int
        let outRate: Int
        var depth: PCMDepth
        if sameLossless {
            outChannels = reader.channelCount
            outRate = srcRateInt
            if srcFormat.isFloat {
                depth = format == .flac ? .int24 : .float32
            } else {
                depth = (srcFormat.bitsPerSample ?? 24) <= 16 ? .int16 : .int24
            }
        } else {
            outChannels = reader.channelCount == 1 ? (options.keepMono ? 1 : 2) : 2
            outRate = options.outputSampleRate(sourceRate: srcRateInt)
            depth = options.outputDepth(sourceBits: srcFormat.isLossless ? srcFormat.bitsPerSample : nil)
        }
        if format == .flac && depth == .float32 { depth = .int24 }

        let needsResample = outRate != srcRateInt || abs(srcRate - Double(srcRateInt)) > 0.001
        let fades = FadePlan(totalFrames: inFrames ?? 0, sampleRate: srcRate, fadeIn: request.fadeIn, fadeOut: request.fadeOut)
        let downmixed = reader.sourceChannelCount > 2
        // Werte verändert (nicht mehr exakt die Ganzzahlen der Quelle)?
        let modified = needsResample || fades.isActive || downmixed || !srcFormat.isLossless
        let srcBits = srcFormat.isFloat ? 32 : (srcFormat.bitsPerSample ?? 32)
        // TPDF-Dither nur beim Verringern auf 16 Bit
        let dither = depth == .int16 && (modified || srcFormat.isFloat || srcBits > 16)
        // Weiche Begrenzung nur, wenn Werte verändert wurden (bitgenaue Kopien bleiben unberührt)
        let limit = modified || (srcFormat.isFloat && depth != .float32)
        let exactCopy = sameLossless && !modified && (srcFormat.isFloat ? depth == .float32 : srcBits == depth.bits)

        let expectedOut: Int64? = inFrames.map { Int64((Double($0) * Double(outRate) / srcRate).rounded()) }
        let spec = EncoderSpec(sampleRate: outRate, channels: outChannels, depth: depth, dither: dither, totalFramesEstimate: expectedOut)
        let encoder = try EncoderFactory.make(format: format, url: output.temp, spec: spec, options: options)
        var finished = false
        defer { if !finished { encoder.abort() } }

        var resampler: Resampler?
        if needsResample {
            resampler = try Resampler(channels: outChannels, from: srcRate, to: Double(outRate), maxInputFrames: Self.blockFrames)
        }
        let block = FloatBlock(channels: reader.channelCount, capacity: Self.blockFrames)
        var adaptScratch: FloatBlock?
        var position: Int64 = 0
        var written: Int64 = 0
        var finalLimit: Int64?

        func emit(_ b: FloatBlock) throws {
            if let cap = finalLimit {
                let room = cap - written
                if room <= 0 { return }
                if Int64(b.frames) > room { b.frames = Int(room) }
            }
            if limit { SoftLimiter.apply(to: b) }
            try encoder.write(b)
            written += Int64(b.frames)
        }

        while true {
            try await control.checkpoint()
            var want = Self.blockFrames
            if let total = inFrames { want = Int(min(Int64(want), total - position)) }
            if want <= 0 { break }
            let n = try reader.read(into: block, maxFrames: want)
            if n == 0 { break }
            let work = ChannelAdapter.adapt(block, to: outChannels, scratch: &adaptScratch)
            fades.apply(to: work, startIndex: position)
            position += Int64(n)
            if let resampler {
                try resampler.process(work) { try emit($0) }
            } else {
                try emit(work)
            }
            if let total = inFrames, total > 0 { reporter.report(Double(position) / Double(total) * 0.95) }
        }
        guard position > 0 else { throw StudioError.decodeFailed("Keine Audiodaten gefunden.") }

        if let resampler {
            // Ausgabelänge exakt: Eingabe · Verhältnis (Rest abschneiden bzw. mit Stille auffüllen)
            let target = Int64((Double(position) * Double(outRate) / srcRate).rounded())
            finalLimit = target
            try resampler.process(nil) { try emit($0) }
            if written < target {
                let pad = FloatBlock(channels: outChannels, capacity: Self.blockFrames)
                while written < target {
                    pad.frames = Int(min(Int64(pad.capacity), target - written))
                    try emit(pad)
                }
            }
        }
        try await control.checkpoint()
        try encoder.finish()
        finished = true
        return exactCopy
    }
}
