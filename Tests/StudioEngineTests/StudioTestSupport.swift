import Accelerate
import AVFoundation
import Foundation
import ImageIO
import XCTest
import MLCore
import MLStudio
import MLTags
@testable import StudioEngine

/// Hilfen für die Engine-Tests: Testsignale erzeugen, Dateien zurücklesen, Störabstand messen,
/// ffprobe abfragen. Ausgaben mit „[Studio] …“ sammelt der Workflow.
enum TS {
    static func log(_ text: String) { print("[Studio] \(text)") }

    /// Neuer leerer Ordner für einen Test.
    static func makeDir(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudioEngineTests-\(name)-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Signale

    enum Signal {
        /// Gleitsinus (logarithmisch): links aufwärts 30 Hz → 16 kHz, rechts abwärts 12 kHz → 40 Hz.
        case sweep
        /// Stille mit Einzelklicks (0,9) an `clickFrames`.
        case clicks([Int])
        /// Sinus mit fester Frequenz und Amplitude (alle Kanäle).
        case sine(Double, Float)
    }

    /// Wert des Signals zur Zeit `t` (Sekunden) in Kanal `ch` bei Gesamtlänge `length` (Sekunden).
    static func sample(_ s: Signal, t: Double, frame: Int, ch: Int, length: Double) -> Float {
        switch s {
        case .sweep:
            let (f0, f1, amp): (Double, Double, Double) = ch % 2 == 0 ? (30, 16_000, 0.5) : (12_000, 40, 0.35)
            let k = Foundation.log(f1 / f0) / length
            let phase = 2 * Double.pi * f0 * (exp(k * t) - 1) / k
            return Float(amp * sin(phase + Double(ch) * 0.3))
        case .clicks(let frames):
            return frames.contains(frame) ? (ch % 2 == 0 ? 0.9 : -0.9) : 0
        case .sine(let f, let a):
            return a * Float(sin(2 * Double.pi * f * t))
        }
    }

    /// Schreibt eine PCM-Datei (WAV/AIFF/CAF nach Endung) über AVAudioFile (unabhängig von den Encodern).
    @discardableResult
    static func writePCM(_ url: URL, rate: Double, channels: Int, bits: Int, seconds: Double, signal: Signal) throws -> URL {
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: bits,
            AVLinearPCMIsFloatKey: bits == 32,
            AVLinearPCMIsBigEndianKey: ["aif", "aiff"].contains(url.pathExtension.lowercased()),
            AVLinearPCMIsNonInterleaved: false,
        ]
        if channels > 2 {
            var layout = AudioChannelLayout()
            layout.mChannelLayoutTag = channels == 6 ? kAudioChannelLayoutTag_MPEG_5_1_A : (kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels))
            settings[AVChannelLayoutKey] = Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
        }
        let total = Int((seconds * rate).rounded())
        try autoreleasepool {
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let chunk = 65_536
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(chunk))!
            var pos = 0
            while pos < total {
                let n = min(chunk, total - pos)
                for c in 0..<channels {
                    let p = buffer.floatChannelData![c]
                    for i in 0..<n {
                        let f = pos + i
                        p[i] = sample(signal, t: Double(f) / rate, frame: f, ch: c, length: seconds)
                    }
                }
                buffer.frameLength = AVAudioFrameCount(n)
                try file.write(from: buffer)
                pos += n
            }
        }
        return url
    }

    /// Lange 16-Bit-WAV-Datei schnell schreiben (eine Sekunde Sinus wird wiederholt) – über den eigenen WAV-Encoder.
    static func writeLongWAV(_ url: URL, rate: Int, seconds: Int) throws {
        let spec = EncoderSpec(sampleRate: rate, channels: 2, depth: .int16, dither: false, totalFramesEstimate: nil)
        let enc = try WAVEncoder(url: url, spec: spec)
        let block = FloatBlock(channels: 2, capacity: rate)
        for i in 0..<rate {
            let t = Double(i) / Double(rate)
            block.channels[0][i] = Float(0.5 * sin(2 * Double.pi * 441 * t))
            block.channels[1][i] = Float(0.3 * sin(2 * Double.pi * 882 * t))
        }
        block.frames = rate
        for _ in 0..<seconds { try enc.write(block) }
        try enc.finish()
    }

    // MARK: - Zurücklesen

    struct Audio {
        var rate: Double
        var channels: [[Float]]
        var frames: Int { channels.first?.count ?? 0 }
        var duration: Double { rate > 0 ? Double(frames) / rate : 0 }
    }

    /// Liest eine (kurze) Datei vollständig über AVAudioFile.
    static func readAll(_ url: URL) throws -> Audio {
        let f = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let ch = Int(f.processingFormat.channelCount)
        var out = [[Float]](repeating: [], count: ch)
        let chunk: AVAudioFrameCount = 65_536
        let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: chunk)!
        while true {
            buf.frameLength = 0
            do { try f.read(into: buf, frameCount: chunk) } catch { break }
            let n = Int(buf.frameLength)
            if n == 0 { break }
            for c in 0..<ch { out[c].append(contentsOf: UnsafeBufferPointer(start: buf.floatChannelData![c], count: n)) }
        }
        return Audio(rate: f.processingFormat.sampleRate, channels: out)
    }

    /// Analytische Referenz eines Signals bei `rate` ab Sekunde `start` mit `frames` Frames.
    static func reference(_ s: Signal, rate: Double, start: Double, frames: Int, channels: Int, length: Double) -> [[Float]] {
        (0..<channels).map { c in
            (0..<frames).map { i in
                let t = start + Double(i) / rate
                return sample(s, t: t, frame: Int((t * rate).rounded()), ch: c, length: length)
            }
        }
    }

    // MARK: - Messungen

    /// Störabstand nach Zeitausrichtung (Kreuzkorrelation über ±maxLag). Ränder werden nicht gewertet.
    static func alignedSNR(reference: [[Float]], test: [[Float]], maxLag: Int = 3000, edge: Int = 4096) -> (lag: Int, snr: Double) {
        guard let r0 = reference.first, let t0 = test.first, r0.count > 4 * edge, t0.count > 4 * edge else { return (0, 0) }
        let window = min(16_384, r0.count - 2 * edge - 2 * maxLag)
        guard window > 1024 else { return (0, 0) }
        let rOff = max(edge + maxLag, r0.count / 2 - window / 2)
        // test[rOff + lag + k] ≈ ref[rOff + k]
        let sigStart = rOff - maxLag
        let sigLen = window + 2 * maxLag
        guard sigStart >= 0, sigStart + sigLen <= t0.count else { return (0, 0) }
        var result = [Float](repeating: 0, count: 2 * maxLag + 1)
        t0.withUnsafeBufferPointer { tb in
            r0.withUnsafeBufferPointer { rb in
                vDSP_conv(tb.baseAddress! + sigStart, 1, rb.baseAddress! + rOff, 1, &result, 1,
                          vDSP_Length(2 * maxLag + 1), vDSP_Length(window))
            }
        }
        var best: Float = 0
        var idx: vDSP_Length = 0
        vDSP_maxvi(result, 1, &best, &idx, vDSP_Length(result.count))
        let lag = Int(idx) - maxLag
        var signal = 0.0, noise = 0.0
        for c in 0..<min(reference.count, test.count) {
            let r = reference[c], t = test[c]
            let from = edge, to = min(r.count, t.count - lag) - edge
            guard to > from else { continue }
            for i in from..<to where i + lag >= 0 {
                let d = Double(t[i + lag]) - Double(r[i])
                signal += Double(r[i]) * Double(r[i])
                noise += d * d
            }
        }
        let snr = noise > 0 ? 10 * log10(signal / noise) : 999
        return (lag, snr)
    }

    /// Positionen (Frames) aller Werte mit Betrag > `threshold` in Kanal 0.
    static func clickPositions(_ a: Audio, threshold: Float = 0.5) -> [Int] {
        guard let ch = a.channels.first else { return [] }
        var out: [Int] = []
        for (i, v) in ch.enumerated() where abs(v) > threshold { out.append(i) }
        return out
    }

    // MARK: - Bilder

    static func makeImage(_ type: String, width: Int = 64, height: Int = 48) -> Data {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.85, green: 0.2, blue: 0.3, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 8, y: 8, width: width / 2, height: height / 2))
        let image = ctx.makeImage()!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data as CFMutableData, type as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    static var png: Data { makeImage("public.png") }
    static var jpeg: Data { makeImage("public.jpeg") }
    /// 16 × 16 WebP (mit Pillow erzeugt).
    static let webp = Data(base64Encoded: "UklGRkYAAABXRUJQVlA4IDoAAADwAQCdASoQABAAAUAmJaACdLoB+AAFIQAA/qJ//wv3/4Uv//whW//DlPIM+QZ+ql/8s/4Hsvw5gAAA")!

    static func metadata(cover: Data?) -> StudioMetadata {
        StudioMetadata(title: "Testtitel äöü", artist: "Test-Interpret", album: "Studio-Album", albumArtist: "Album-Interpret",
                       year: 2024, genre: "Elektronik", trackNumber: 7, cover: cover)
    }

    /// Prüft Tags und Cover einer Datei; Rückgabe: Liste der Abweichungen (leer = alles gleich).
    static func tagProblems(_ url: URL, expected m: StudioMetadata) -> [String] {
        guard let r = try? TagFile.read(url: url) else { return ["Tags nicht lesbar"] }
        let v = r.values
        var p: [String] = []
        if v.title != m.title { p.append("Titel \(v.title ?? "nil")") }
        if v.artists != [m.artist] { p.append("Interpret \(v.artists)") }
        if v.album != m.album { p.append("Album \(v.album ?? "nil")") }
        if v.albumArtists != [m.albumArtist] { p.append("Albuminterpret \(v.albumArtists)") }
        if v.year != m.year { p.append("Jahr \(String(describing: v.year))") }
        if v.genres != [m.genre] { p.append("Genre \(v.genres)") }
        if v.trackNumber != m.trackNumber { p.append("Nr. \(String(describing: v.trackNumber))") }
        if let cover = m.cover {
            if let pic = v.frontCover {
                if pic.data != cover { p.append("Cover abweichend (\(pic.data.count) statt \(cover.count) Bytes)") }
            } else {
                p.append("Cover fehlt")
            }
        }
        return p
    }

    // MARK: - ffprobe / ffmpeg

    static var ffprobePath: String? {
        ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var ffmpegPath: String? { FFmpegTool.path }

    @discardableResult
    static func run(_ tool: String, _ args: [String], timeout: Double = 600) -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        do { try p.run() } catch { return (-1, "", "\(error)") }
        // Ausgaben nebenläufig lesen (große Ausgaben würden sonst blockieren)
        let outBox = DataBox(), errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { outBox.data = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if p.isRunning { p.terminate() }
        group.wait()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: outBox.data, as: UTF8.self), String(decoding: errBox.data, as: UTF8.self))
    }

    /// ffprobe-JSON (format + streams) oder nil.
    static func probe(_ url: URL) -> [String: Any]? {
        guard let tool = ffprobePath else { return nil }
        let r = run(tool, ["-v", "error", "-show_format", "-show_streams", "-of", "json", url.path], timeout: 60)
        guard r.status == 0, let data = r.out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json
    }

    /// Anzahl der von FFmpeg dekodierten Frames (berücksichtigt Encoder-Verzögerung/Auffüllung).
    static func ffmpegDecodedFrames(_ url: URL, channels: Int) -> Int? {
        guard let tool = ffmpegPath else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ffdec-\(UUID().uuidString).raw")
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = run(tool, ["-v", "error", "-y", "-i", url.path, "-f", "s16le", "-acodec", "pcm_s16le", dir.path], timeout: 120)
        guard r.status == 0, let size = (try? FileManager.default.attributesOfItem(atPath: dir.path)[.size] as? NSNumber)?.intValue else { return nil }
        return size / (2 * channels)
    }

    static func fileSize(_ url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    // MARK: - Speicher

    /// Physischer Speicherbedarf des Prozesses (phys_footprint) in Bytes.
    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? info.phys_footprint : 0
    }

    static func mb(_ bytes: UInt64) -> String { String(format: "%.1f MB", Double(bytes) / 1_048_576) }

    /// Export mit gesammeltem Fortschritt.
    static func export(_ request: ExportRequest, pause: PauseGate? = nil) async throws -> (ExportResult, [Double]) {
        let log = ProgressLog()
        let result = try await AudioExporter().export(request, pause: pause) { log.add($0) }
        return (result, log.values)
    }
}

/// Puffer für nebenläufig gelesene Prozessausgaben.
final class DataBox: @unchecked Sendable {
    var data = Data()
}

/// Fortschrittswerte sammeln (Rückruf kommt aus einem Hintergrund-Task).
final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(Double, Date)] = []
    func add(_ v: Double) { lock.lock(); items.append((v, Date())); lock.unlock() }
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return items.map { $0.0 } }
    var last: Double { lock.lock(); defer { lock.unlock() }; return items.last?.0 ?? 0 }
    var count: Int { lock.lock(); defer { lock.unlock() }; return items.count }
    /// Größte Anzahl Rückrufe innerhalb einer Sekunde.
    var maxPerSecond: Int {
        lock.lock(); defer { lock.unlock() }
        var best = 0
        var j = 0
        for i in 0..<items.count {
            while items[i].1.timeIntervalSince(items[j].1) > 1 { j += 1 }
            best = max(best, i - j + 1)
        }
        return best
    }
}
