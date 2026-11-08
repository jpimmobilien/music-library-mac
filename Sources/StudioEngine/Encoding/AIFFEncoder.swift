import Foundation
import MLStudio

/// AIFF-Encoder: 16/24 Bit PCM als AIFF, 32 Bit Float als AIFF-C mit Kompressionstyp „fl32“.
/// Daten in Big Endian; Längen werden am Ende eingetragen.
final class AIFFEncoder: PCMEncoder {
    private let file: BinaryFile
    private let spec: EncoderSpec
    private var quantizer: Quantizer?
    private var scratch: [UInt8] = []
    private var dataBytes: Int64 = 0
    private var frames: Int64 = 0
    private var numFramesOffset: Int64 = 0
    private var ssndSizeOffset: Int64 = 0
    private var finished = false

    static let maxDataBytes: Int64 = 0xFFFF_FFFF - 1024

    init(url: URL, spec: EncoderSpec) throws {
        self.spec = spec
        file = try BinaryFile(creating: url)
        if spec.depth != .float32 { quantizer = Quantizer(bits: spec.depth.bits, dither: spec.dither && spec.depth == .int16) }
        try writeHeader()
    }

    private var isFloat: Bool { spec.depth == .float32 }

    private func writeHeader() throws {
        var h: [UInt8] = []
        h += ByteWriter.ascii("FORM") + ByteWriter.be32(0) + ByteWriter.ascii(isFloat ? "AIFC" : "AIFF")
        if isFloat {
            // Versionsblock der AIFF-C-Spezifikation (Mai 1990)
            h += ByteWriter.ascii("FVER") + ByteWriter.be32(4) + ByteWriter.be32(0xA280_5140)
        }
        var comm: [UInt8] = []
        comm += ByteWriter.be16(spec.channels)
        numFramesOffset = Int64(h.count + 8 + comm.count)
        comm += ByteWriter.be32(0)
        comm += ByteWriter.be16(spec.depth.bits)
        comm += ByteWriter.extended80(Double(spec.sampleRate))
        if isFloat {
            comm += ByteWriter.ascii("fl32")
            let name = Array("32-bit floating point".utf8)
            comm += [UInt8(name.count)] + name
            if (name.count + 1) % 2 == 1 { comm += [0] }   // Pascal-String auf gerade Länge auffüllen
        }
        h += ByteWriter.ascii("COMM") + ByteWriter.be32(comm.count) + comm
        h += ByteWriter.ascii("SSND")
        ssndSizeOffset = Int64(h.count)
        h += ByteWriter.be32(0) + ByteWriter.be32(0) + ByteWriter.be32(0)   // Größe, Offset, Blockgröße
        try file.write(h)
    }

    func write(_ block: FloatBlock) throws {
        guard block.frames > 0 else { return }
        let n = PCMPacker.pack(block, bits: spec.depth.bits, float: isFloat, bigEndian: true, quantizer: &quantizer, into: &scratch)
        if dataBytes + Int64(n) > Self.maxDataBytes {
            throw StudioError.encodeFailed("AIFF-Dateien können höchstens 4 GB groß sein. Bitte eine kürzere Auswahl oder FLAC wählen.")
        }
        try file.write(scratch, count: n)
        dataBytes += Int64(n)
        frames += Int64(block.frames)
    }

    func finish() throws {
        guard !finished else { return }
        finished = true
        if dataBytes % 2 == 1 { try file.write([0]) }
        let total = file.length
        try file.seek(to: 4)
        try file.write(ByteWriter.be32(Int(total - 8)))
        try file.seek(to: numFramesOffset)
        try file.write(ByteWriter.be32(Int(frames)))
        try file.seek(to: ssndSizeOffset)
        try file.write(ByteWriter.be32(Int(dataBytes + 8)))
        try file.close()
    }

    func abort() {
        finished = true
        file.abandon()
    }
}
