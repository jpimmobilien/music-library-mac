import Foundation
import CLame
import MLStudio

/// MP3-Encoder über LAME 3.100: konstante Bitrate (CBR), Joint Stereo (bzw. Mono), Qualitätsstufe 2
/// („hohe Qualität“), LAME/Xing-Infoframe („Info“) mit Frameanzahl, Encoder-Verzögerung und Auffüllung,
/// damit Wiedergabeprogramme die Dauer exakt kennen. Keine ID3-Tags durch LAME (Tags schreibt MLTags).
final class MP3Encoder: PCMEncoder {
    private var gf: OpaquePointer?
    private let file: BinaryFile
    private let spec: EncoderSpec
    private var buffer: [UInt8] = []
    private var finished = false

    init(url: URL, spec: EncoderSpec, bitrateKbps: Int) throws {
        self.spec = spec
        guard spec.channels == 1 || spec.channels == 2 else { throw StudioError.encodeFailed("MP3 kann nur Mono oder Stereo speichern.") }
        guard let g = lame_init() else { throw StudioError.encodeFailed("MP3-Encoder konnte nicht angelegt werden.") }
        gf = g
        // Meldungen von LAME nicht auf stderr ausgeben
        lame_set_errorf(g) { _, _ in }
        lame_set_debugf(g) { _, _ in }
        lame_set_msgf(g) { _, _ in }
        lame_set_in_samplerate(g, Int32(spec.sampleRate))
        lame_set_out_samplerate(g, Int32(spec.sampleRate))
        lame_set_num_channels(g, Int32(spec.channels))
        lame_set_mode(g, spec.channels == 1 ? MONO : JOINT_STEREO)
        lame_set_VBR(g, vbr_off)
        lame_set_brate(g, Int32(bitrateKbps))
        lame_set_quality(g, 2)
        lame_set_bWriteVbrTag(g, 1)
        lame_set_write_id3tag_automatic(g, 0)
        if lame_init_params(g) < 0 {
            lame_close(g)
            gf = nil
            throw StudioError.encodeFailed("MP3-Encoder: ungültige Einstellungen (\(bitrateKbps) kbit/s, \(spec.sampleRate) Hz, \(spec.channels) Kanäle).")
        }
        do {
            file = try BinaryFile(creating: url)
        } catch {
            lame_close(g)
            gf = nil
            throw error
        }
    }

    deinit {
        if let g = gf { lame_close(g) }
    }

    /// Encoder-Verzögerung in Samples (laut LAME), z. B. 576.
    var encoderDelay: Int { gf.map { Int(lame_get_encoder_delay($0)) } ?? 0 }

    private func ensureBuffer(frames: Int) {
        let needed = frames + frames / 4 + 7200
        if buffer.count < needed { buffer = [UInt8](repeating: 0, count: needed) }
    }

    func write(_ block: FloatBlock) throws {
        guard let g = gf, block.frames > 0 else { return }
        let n = block.frames
        ensureBuffer(frames: n)
        let left = UnsafePointer(block.channels[0])
        let right = UnsafePointer(block.channels[min(1, block.channelCount - 1)])
        let capacity = Int32(buffer.count)
        let produced = buffer.withUnsafeMutableBufferPointer { out in
            lame_encode_buffer_ieee_float(g, left, right, Int32(n), out.baseAddress, capacity)
        }
        if produced < 0 { throw StudioError.encodeFailed("MP3-Encoder: Fehler \(produced) beim Kodieren.") }
        try file.write(buffer, count: Int(produced))
    }

    func finish() throws {
        guard !finished, let g = gf else { return }
        finished = true
        ensureBuffer(frames: 8192)
        let capacity = Int32(buffer.count)
        let produced = buffer.withUnsafeMutableBufferPointer { out in
            lame_encode_flush(g, out.baseAddress, capacity)
        }
        if produced < 0 { throw StudioError.encodeFailed("MP3-Encoder: Fehler \(produced) beim Abschließen.") }
        try file.write(buffer, count: Int(produced))
        // LAME/Xing-Infoframe an den Anfang (ersetzt den Platzhalter-Frame gleicher Größe)
        var tag = [UInt8](repeating: 0, count: 2880)
        let tagSize = tag.withUnsafeMutableBufferPointer { buf in
            lame_get_lametag_frame(g, buf.baseAddress, buf.count)
        }
        if tagSize > 0 && tagSize <= tag.count {
            try file.seek(to: 0)
            try file.write(tag, count: Int(tagSize))
        }
        try file.close()
        lame_close(g)
        gf = nil
    }

    func abort() {
        finished = true
        file.abandon()
        if let g = gf { lame_close(g) }
        gf = nil
    }
}
