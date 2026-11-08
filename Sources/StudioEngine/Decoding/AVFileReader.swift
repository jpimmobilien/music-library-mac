import AVFoundation
import Foundation
import MLStudio

/// Liest Audiodateien über AVAudioFile (MP3, AAC/M4A, ALAC, WAV, AIFF, FLAC, CAF …) blockweise als
/// Float32. Mehr als zwei Kanäle werden auf Wunsch über AVAudioConverter (Apple-Kanal-Layout) bzw.
/// nach WAV-Kanalreihenfolge auf Stereo heruntergemischt.
final class AVFileReader: PCMReader {
    private let file: AVAudioFile
    private let capacity: AVAudioFrameCount
    private let readBuffer: AVAudioPCMBuffer
    private var mixer: AVAudioConverter?
    private var mixBuffer: AVAudioPCMBuffer?
    private var matrix: [(Float, Float)]?
    /// Temporäre Datei (z. B. von FFmpeg), die beim Schließen gelöscht wird.
    private var ownedFile: URL?

    let sampleRate: Double
    let channelCount: Int
    let sourceChannelCount: Int
    let lengthFrames: Int64?
    let format: SourceFormat

    init(url: URL, downmixToStereo: Bool, capacity: Int = 32_768, ownedFile: URL? = nil) throws {
        do {
            file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw StudioError.decodeFailed("AVAudioFile: \(error.localizedDescription)")
        }
        self.ownedFile = ownedFile
        let pf = file.processingFormat
        sampleRate = pf.sampleRate
        sourceChannelCount = Int(pf.channelCount)
        guard sampleRate > 0, sourceChannelCount > 0 else { throw StudioError.decodeFailed("Ungültiges Audioformat.") }
        self.capacity = AVAudioFrameCount(capacity)
        guard let buf = AVAudioPCMBuffer(pcmFormat: pf, frameCapacity: self.capacity) else {
            throw StudioError.decodeFailed("Lesepuffer konnte nicht angelegt werden.")
        }
        readBuffer = buf
        let len = file.length
        lengthFrames = len > 0 ? len : nil
        format = AVFileReader.describe(file.fileFormat.streamDescription.pointee)
        if downmixToStereo && sourceChannelCount > 2 {
            channelCount = 2
            if let stereo = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
               pf.channelLayout != nil,
               let conv = AVAudioConverter(from: pf, to: stereo),
               let out = AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: self.capacity) {
                conv.downmix = true
                mixer = conv
                mixBuffer = out
            } else {
                matrix = StereoDownmix.wavMatrix(channels: sourceChannelCount)
            }
        } else {
            channelCount = sourceChannelCount
        }
    }

    deinit { removeOwnedFile() }

    private func removeOwnedFile() {
        if let f = ownedFile {
            try? FileManager.default.removeItem(at: f)
            ownedFile = nil
        }
    }

    func seek(to frame: Int64) throws {
        file.framePosition = max(0, frame)
    }

    func read(into block: FloatBlock, maxFrames: Int) throws -> Int {
        let want = AVAudioFrameCount(max(0, min(maxFrames, block.capacity, Int(capacity))))
        block.frames = 0
        guard want > 0 else { return 0 }
        if file.length > 0 && file.framePosition >= file.length { return 0 }
        readBuffer.frameLength = 0
        do {
            try file.read(into: readBuffer, frameCount: want)
        } catch {
            // Am Dateiende melden manche Formate einen Fehler statt 0 Frames
            if file.length > 0 && file.framePosition >= file.length { return 0 }
            throw StudioError.decodeFailed("Lesefehler bei Frame \(file.framePosition): \(error.localizedDescription)")
        }
        let n = Int(readBuffer.frameLength)
        guard n > 0, let src = readBuffer.floatChannelData else { return 0 }
        if let mixer, let mixBuffer {
            mixBuffer.frameLength = 0
            do {
                try mixer.convert(to: mixBuffer, from: readBuffer)
            } catch {
                throw StudioError.decodeFailed("Heruntermischen fehlgeschlagen: \(error.localizedDescription)")
            }
            guard let mixed = mixBuffer.floatChannelData else { return 0 }
            let m = min(Int(mixBuffer.frameLength), block.capacity)
            for c in 0..<2 { block.channels[c].update(from: mixed[c], count: m) }
            block.frames = m
            return m
        }
        if let matrix {
            let l = block.channels[0], r = block.channels[1]
            l.update(repeating: 0, count: n)
            r.update(repeating: 0, count: n)
            for (c, coeff) in matrix.enumerated() where c < sourceChannelCount {
                let s = src[c]
                if coeff.0 != 0 { for i in 0..<n { l[i] += s[i] * coeff.0 } }
                if coeff.1 != 0 { for i in 0..<n { r[i] += s[i] * coeff.1 } }
            }
            block.frames = n
            return n
        }
        for c in 0..<channelCount { block.channels[c].update(from: src[c], count: n) }
        block.frames = n
        return n
    }

    func close() { removeOwnedFile() }

    /// Codec, Verlustfreiheit und Bittiefe aus der Formatbeschreibung der Datei.
    static func describe(_ asbd: AudioStreamBasicDescription) -> SourceFormat {
        let id = asbd.mFormatID
        func losslessBits(_ flags: AudioFormatFlags) -> Int? {
            switch flags {
            case 1: return 16
            case 2: return 20
            case 3: return 24
            case 4: return 32
            default: return nil
            }
        }
        switch id {
        case kAudioFormatLinearPCM:
            let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
            return SourceFormat(codec: "PCM", isLossless: true, isFloat: isFloat,
                                bitsPerSample: isFloat ? nil : Int(asbd.mBitsPerChannel))
        case kAudioFormatAppleLossless:
            return SourceFormat(codec: "ALAC", isLossless: true, isFloat: false, bitsPerSample: losslessBits(asbd.mFormatFlags))
        case kAudioFormatFLAC:
            return SourceFormat(codec: "FLAC", isLossless: true, isFloat: false, bitsPerSample: losslessBits(asbd.mFormatFlags))
        default:
            return SourceFormat(codec: codecName(id), isLossless: false, isFloat: false, bitsPerSample: nil)
        }
    }

    static func codecName(_ id: AudioFormatID) -> String {
        switch id {
        case kAudioFormatMPEGLayer3: return "MP3"
        case kAudioFormatMPEGLayer2: return "MP2"
        case kAudioFormatMPEGLayer1: return "MP1"
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2, kAudioFormatMPEG4AAC_LD,
             kAudioFormatMPEG4AAC_ELD, kAudioFormatMPEG4AAC_ELD_SBR, kAudioFormatMPEG4AAC_ELD_V2:
            return "AAC"
        case kAudioFormatAppleLossless: return "ALAC"
        case kAudioFormatFLAC: return "FLAC"
        case kAudioFormatLinearPCM: return "PCM"
        case kAudioFormatOpus: return "Opus"
        case kAudioFormatAC3: return "AC-3"
        case kAudioFormatEnhancedAC3: return "E-AC-3"
        case kAudioFormatAppleIMA4: return "IMA4"
        case kAudioFormatULaw: return "µ-law"
        case kAudioFormatALaw: return "A-law"
        case kAudioFormatAMR: return "AMR"
        default:
            // Vierzeichen-Kennung lesbar machen
            let chars = [24, 16, 8, 0].map { Character(UnicodeScalar(UInt8((id >> UInt32($0)) & 0xFF))) }
            return String(chars).trimmingCharacters(in: .whitespaces)
        }
    }
}

extension StereoDownmix {
    /// Koeffizienten für WAV/SMPTE-Reihenfolge (FL FR FC LFE BL BR SL SR …), normiert.
    static func wavMatrix(channels: Int) -> [(Float, Float)] {
        let c: Float = 0.7071
        let order: [(Float, Float)] = [(1, 0), (0, 1), (c, c), (0, 0), (c, 0), (0, c), (c, 0), (0, c)]
        var raw = Array(order.prefix(channels))
        while raw.count < channels { raw.append((0, 0)) }
        let sumL = raw.reduce(Float(0)) { $0 + $1.0 }
        let sumR = raw.reduce(Float(0)) { $0 + $1.1 }
        let norm = 1 / max(sumL, sumR, 1)
        return raw.map { ($0.0 * norm, $0.1 * norm) }
    }
}
