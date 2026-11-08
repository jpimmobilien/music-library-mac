#if canImport(AudioToolbox)
import AudioToolbox
import Foundation
import MLStudio

/// AAC-Encoder über ExtAudioFile (AudioToolbox): M4A (AAC im MPEG-4-Container, mit Angaben zur
/// Encoder-Verzögerung) oder roher ADTS-Datenstrom (.aac). Konstante Ziel-Bitrate, höchste Qualität.
final class AACEncoder: PCMEncoder {
    private var file: ExtAudioFileRef?
    private let spec: EncoderSpec
    private let bufferList: UnsafeMutableAudioBufferListPointer
    private var finished = false
    /// Tatsächlich eingestellte Bitrate (bit/s).
    private(set) var bitRate: UInt32 = 0

    init(url: URL, spec: EncoderSpec, bitrateKbps: Int, adts: Bool) throws {
        self.spec = spec
        var dst = AudioStreamBasicDescription()
        dst.mSampleRate = Float64(spec.sampleRate)
        dst.mFormatID = kAudioFormatMPEG4AAC
        dst.mChannelsPerFrame = UInt32(spec.channels)
        dst.mFramesPerPacket = 1024
        var ref: ExtAudioFileRef?
        var status = ExtAudioFileCreateWithURL(url as CFURL, adts ? kAudioFileAAC_ADTSType : kAudioFileM4AType, &dst, nil,
                                               AudioFileFlags.eraseFile.rawValue, &ref)
        guard status == noErr, let ref else {
            throw StudioError.encodeFailed("AAC-Datei konnte nicht angelegt werden (\(AACEncoder.describe(status))).")
        }
        file = ref
        bufferList = AudioBufferList.allocate(maximumBuffers: spec.channels)

        var client = AudioStreamBasicDescription(
            mSampleRate: Float64(spec.sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: UInt32(spec.channels),
            mBitsPerChannel: 32, mReserved: 0)
        status = ExtAudioFileSetProperty(ref, kExtAudioFileProperty_ClientDataFormat,
                                         UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &client)
        guard status == noErr else {
            dispose()
            throw StudioError.encodeFailed("AAC-Encoder: Eingangsformat nicht möglich (\(AACEncoder.describe(status))).")
        }

        var converter: AudioConverterRef?
        var size = UInt32(MemoryLayout<AudioConverterRef?>.size)
        status = ExtAudioFileGetProperty(ref, kExtAudioFileProperty_AudioConverter, &size, &converter)
        if status == noErr, let converter {
            var quality = UInt32(kAudioConverterQuality_Max)
            AudioConverterSetProperty(converter, kAudioConverterCodecQuality, UInt32(MemoryLayout<UInt32>.size), &quality)
            var mode = UInt32(kAudioCodecBitRateControlMode_Constant)
            AudioConverterSetProperty(converter, kAudioCodecPropertyBitRateControlMode, UInt32(MemoryLayout<UInt32>.size), &mode)
            var rate = AACEncoder.applicableBitRate(converter, wanted: UInt32(bitrateKbps * 1000))
            status = AudioConverterSetProperty(converter, kAudioConverterEncodeBitRate, UInt32(MemoryLayout<UInt32>.size), &rate)
            if status == noErr { bitRate = rate }
            // ExtAudioFile mitteilen, dass sich die Einstellungen des Konverters geändert haben
            var config: CFPropertyList? = nil
            ExtAudioFileSetProperty(ref, kExtAudioFileProperty_ConverterConfig, UInt32(MemoryLayout<CFPropertyList?>.size), &config)
        }
    }

    deinit {
        dispose()
        free(bufferList.unsafeMutablePointer)
    }

    private func dispose() {
        if let f = file {
            ExtAudioFileDispose(f)
            file = nil
        }
    }

    /// Nächstgelegene vom Encoder unterstützte Bitrate.
    static func applicableBitRate(_ converter: AudioConverterRef, wanted: UInt32) -> UInt32 {
        var size: UInt32 = 0
        guard AudioConverterGetPropertyInfo(converter, kAudioConverterApplicableEncodeBitRates, &size, nil) == noErr, size > 0 else {
            return wanted
        }
        let count = Int(size) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)
        guard AudioConverterGetProperty(converter, kAudioConverterApplicableEncodeBitRates, &size, &ranges) == noErr else { return wanted }
        let w = Double(wanted)
        var best = w
        var bestDistance = Double.greatestFiniteMagnitude
        for r in ranges {
            if w >= r.mMinimum && w <= r.mMaximum { return wanted }
            for candidate in [r.mMinimum, r.mMaximum] where abs(candidate - w) < bestDistance {
                bestDistance = abs(candidate - w)
                best = candidate
            }
        }
        return UInt32(best)
    }

    static func describe(_ status: OSStatus) -> String {
        let n = UInt32(bitPattern: status)
        let bytes = [24, 16, 8, 0].map { UInt8((n >> UInt32($0)) & 0xFF) }
        if bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) {
            return "Fehler '\(String(decoding: bytes, as: UTF8.self))'"
        }
        return "Fehler \(status)"
    }

    func write(_ block: FloatBlock) throws {
        guard let f = file, block.frames > 0 else { return }
        let bytes = UInt32(block.frames * MemoryLayout<Float>.size)
        for c in 0..<spec.channels {
            bufferList[c] = AudioBuffer(mNumberChannels: 1, mDataByteSize: bytes, mData: UnsafeMutableRawPointer(block.channels[c]))
        }
        let status = ExtAudioFileWrite(f, UInt32(block.frames), bufferList.unsafePointer)
        if status != noErr {
            throw StudioError.encodeFailed("AAC-Encoder: Schreiben fehlgeschlagen (\(AACEncoder.describe(status))).")
        }
    }

    func finish() throws {
        guard !finished, let f = file else { return }
        finished = true
        file = nil
        let status = ExtAudioFileDispose(f)
        if status != noErr {
            throw StudioError.encodeFailed("AAC-Encoder: Abschluss fehlgeschlagen (\(AACEncoder.describe(status))).")
        }
    }

    func abort() {
        finished = true
        dispose()
    }
}
#endif
