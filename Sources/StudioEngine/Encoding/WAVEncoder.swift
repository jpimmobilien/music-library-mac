import Foundation
import MLStudio

/// WAV-Encoder (RIFF): 16 Bit PCM (WAVE_FORMAT_PCM), 24 Bit PCM (WAVE_FORMAT_EXTENSIBLE, wie von
/// Microsoft für mehr als 16 Bit vorgesehen), 32 Bit Float (WAVE_FORMAT_IEEE_FLOAT mit „fact“-Block).
/// Kopfdaten werden am Ende mit den echten Längen überschrieben.
final class WAVEncoder: PCMEncoder {
    private let file: BinaryFile
    private let spec: EncoderSpec
    private var quantizer: Quantizer?
    private var scratch: [UInt8] = []
    private var dataBytes: Int64 = 0
    private var frames: Int64 = 0
    private var riffSizeOffset: Int64 = 4
    private var factOffset: Int64?
    private var dataSizeOffset: Int64 = 0
    private var finished = false

    /// Größte Datenmenge, die ein RIFF-Kopf beschreiben kann (4 GB abzüglich Kopf).
    static let maxDataBytes: Int64 = 0xFFFF_FFFF - 1024

    init(url: URL, spec: EncoderSpec) throws {
        self.spec = spec
        file = try BinaryFile(creating: url)
        if spec.depth != .float32 { quantizer = Quantizer(bits: spec.depth.bits, dither: spec.dither && spec.depth == .int16) }
        try writeHeader()
    }

    private var bytesPerSample: Int { spec.depth.bits / 8 }

    private func writeHeader() throws {
        let ch = spec.channels
        let rate = spec.sampleRate
        let bps = bytesPerSample
        let blockAlign = ch * bps
        var h: [UInt8] = []
        h += ByteWriter.ascii("RIFF") + ByteWriter.le32(0) + ByteWriter.ascii("WAVE")
        switch spec.depth {
        case .int16:
            h += ByteWriter.ascii("fmt ") + ByteWriter.le32(16)
            h += ByteWriter.le16(1) + ByteWriter.le16(ch) + ByteWriter.le32(rate) + ByteWriter.le32(rate * blockAlign)
            h += ByteWriter.le16(blockAlign) + ByteWriter.le16(16)
        case .int24:
            // WAVE_FORMAT_EXTENSIBLE mit KSDATAFORMAT_SUBTYPE_PCM
            h += ByteWriter.ascii("fmt ") + ByteWriter.le32(40)
            h += ByteWriter.le16(0xFFFE) + ByteWriter.le16(ch) + ByteWriter.le32(rate) + ByteWriter.le32(rate * blockAlign)
            h += ByteWriter.le16(blockAlign) + ByteWriter.le16(24)
            h += ByteWriter.le16(22) + ByteWriter.le16(24) + ByteWriter.le32(Self.channelMask(ch))
            h += Self.subFormatGUID(formatTag: 1)
        case .float32:
            // WAVE_FORMAT_IEEE_FLOAT (WAVEFORMATEX mit cbSize = 0) und „fact“-Block
            h += ByteWriter.ascii("fmt ") + ByteWriter.le32(18)
            h += ByteWriter.le16(3) + ByteWriter.le16(ch) + ByteWriter.le32(rate) + ByteWriter.le32(rate * blockAlign)
            h += ByteWriter.le16(blockAlign) + ByteWriter.le16(32) + ByteWriter.le16(0)
            h += ByteWriter.ascii("fact") + ByteWriter.le32(4)
            factOffset = Int64(h.count)
            h += ByteWriter.le32(0)
        }
        h += ByteWriter.ascii("data")
        dataSizeOffset = Int64(h.count)
        h += ByteWriter.le32(0)
        try file.write(h)
    }

    static func channelMask(_ channels: Int) -> Int {
        switch channels {
        case 1: return 0x4          // SPEAKER_FRONT_CENTER
        case 2: return 0x3          // SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT
        default: return (1 << channels) - 1
        }
    }

    /// GUID xxxxxxxx-0000-0010-8000-00AA00389B71 (Little Endian in den ersten drei Feldern).
    static func subFormatGUID(formatTag: Int) -> [UInt8] {
        ByteWriter.le32(formatTag) + [0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71]
    }

    func write(_ block: FloatBlock) throws {
        guard block.frames > 0 else { return }
        let n = PCMPacker.pack(block, bits: spec.depth.bits, float: spec.depth == .float32, bigEndian: false,
                               quantizer: &quantizer, into: &scratch)
        if dataBytes + Int64(n) > Self.maxDataBytes {
            throw StudioError.encodeFailed("WAV-Dateien können höchstens 4 GB groß sein. Bitte eine kürzere Auswahl, eine niedrigere Abtastrate oder FLAC wählen.")
        }
        try file.write(scratch, count: n)
        dataBytes += Int64(n)
        frames += Int64(block.frames)
    }

    func finish() throws {
        guard !finished else { return }
        finished = true
        if dataBytes % 2 == 1 { try file.write([0]) }   // RIFF-Blöcke haben gerade Länge
        let total = file.length
        try file.seek(to: riffSizeOffset)
        try file.write(ByteWriter.le32(Int(total - 8)))
        if let f = factOffset {
            try file.seek(to: f)
            try file.write(ByteWriter.le32(Int(frames)))
        }
        try file.seek(to: dataSizeOffset)
        try file.write(ByteWriter.le32(Int(dataBytes)))
        try file.close()
    }

    func abort() {
        finished = true
        file.abandon()
    }
}
