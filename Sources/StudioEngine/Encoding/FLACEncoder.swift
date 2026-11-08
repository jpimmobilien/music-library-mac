import Foundation
import CFLAC
import MLStudio

/// FLAC-Encoder über libFLAC 1.5.0: Kompressionsstufe 0–8, 16 oder 24 Bit, MD5-Prüfsumme (Standard
/// von libFLAC), Seektable (ein Punkt je 10 Sekunden) und 8 KB Platz für Tags.
final class FLACEncoder: PCMEncoder {
    private var encoder: UnsafeMutablePointer<FLAC__StreamEncoder>?
    private var seekTable: UnsafeMutablePointer<FLAC__StreamMetadata>?
    private var padding: UnsafeMutablePointer<FLAC__StreamMetadata>?
    private var metadataList: UnsafeMutablePointer<UnsafeMutablePointer<FLAC__StreamMetadata>?>?
    private let spec: EncoderSpec
    private let bits: Int
    private var quantizer: Quantizer
    private var interleaved: [Int32] = []
    private var finished = false

    init(url: URL, spec: EncoderSpec, level: Int) throws {
        self.spec = spec
        bits = spec.depth == .int16 ? 16 : 24
        quantizer = Quantizer(bits: bits, dither: spec.dither && bits == 16)
        guard let enc = FLAC__stream_encoder_new() else { throw StudioError.encodeFailed("FLAC-Encoder konnte nicht angelegt werden.") }
        encoder = enc
        FLAC__stream_encoder_set_verify(enc, 0)
        FLAC__stream_encoder_set_compression_level(enc, UInt32(min(max(level, 0), 8)))
        FLAC__stream_encoder_set_channels(enc, UInt32(spec.channels))
        FLAC__stream_encoder_set_bits_per_sample(enc, UInt32(bits))
        FLAC__stream_encoder_set_sample_rate(enc, UInt32(spec.sampleRate))

        var blocks: [UnsafeMutablePointer<FLAC__StreamMetadata>] = []
        if let total = spec.totalFramesEstimate, total > 0 {
            FLAC__stream_encoder_set_total_samples_estimate(enc, UInt64(total))
            if let st = FLAC__metadata_object_new(FLAC__METADATA_TYPE_SEEKTABLE) {
                let spacing = UInt32(max(spec.sampleRate * 10, 1))
                if FLAC__metadata_object_seektable_template_append_spaced_points_by_samples(st, spacing, UInt64(total)) != 0,
                   FLAC__metadata_object_seektable_template_sort(st, 1) != 0 {
                    seekTable = st
                    blocks.append(st)
                } else {
                    FLAC__metadata_object_delete(st)
                }
            }
        }
        if let pad = FLAC__metadata_object_new(FLAC__METADATA_TYPE_PADDING) {
            pad.pointee.length = 8192
            padding = pad
            blocks.append(pad)
        }
        if !blocks.isEmpty {
            let list = UnsafeMutablePointer<UnsafeMutablePointer<FLAC__StreamMetadata>?>.allocate(capacity: blocks.count)
            for (i, b) in blocks.enumerated() { list[i] = b }
            metadataList = list
            FLAC__stream_encoder_set_metadata(enc, list, UInt32(blocks.count))
        }

        guard let fp = fopen(url.path, "w+b") else {
            let err = BinaryFile.error(errno, action: "Die Zieldatei konnte nicht angelegt werden")
            cleanup()
            throw err
        }
        // libFLAC übernimmt die Datei und schließt sie in FLAC__stream_encoder_finish().
        let status = FLAC__stream_encoder_init_FILE(enc, fp, nil, nil)
        if status != FLAC__STREAM_ENCODER_INIT_STATUS_OK {
            fclose(fp)
            let text = String(cString: FLAC__stream_encoder_get_resolved_state_string(enc))
            cleanup()
            throw StudioError.encodeFailed("FLAC-Encoder: \(text) (Init-Status \(status.rawValue))")
        }
    }

    deinit { cleanup() }

    private func cleanup() {
        if let enc = encoder {
            FLAC__stream_encoder_delete(enc)   // schließt die Datei, falls noch offen
            encoder = nil
        }
        if let st = seekTable { FLAC__metadata_object_delete(st); seekTable = nil }
        if let pad = padding { FLAC__metadata_object_delete(pad); padding = nil }
        if let list = metadataList { list.deallocate(); metadataList = nil }
    }

    func write(_ block: FloatBlock) throws {
        guard let enc = encoder, block.frames > 0 else { return }
        let ch = spec.channels
        let n = block.frames
        if interleaved.count < n * ch { interleaved = [Int32](repeating: 0, count: n * ch) }
        var q = quantizer
        interleaved.withUnsafeMutableBufferPointer { buf in
            var o = 0
            for i in 0..<n {
                for c in 0..<ch {
                    buf[o] = q.quantize(block.channels[c][i])
                    o += 1
                }
            }
        }
        quantizer = q
        let ok = interleaved.withUnsafeBufferPointer { buf in
            FLAC__stream_encoder_process_interleaved(enc, buf.baseAddress, UInt32(n))
        }
        if ok == 0 { throw failure(errno) }
    }

    private func failure(_ code: Int32) -> StudioError {
        if code == ENOSPC || code == EDQUOT { return .diskFull }
        guard let enc = encoder else { return .encodeFailed("FLAC-Encoder") }
        return .encodeFailed("FLAC-Encoder: \(String(cString: FLAC__stream_encoder_get_resolved_state_string(enc)))")
    }

    func finish() throws {
        guard !finished, let enc = encoder else { return }
        finished = true
        let ok = FLAC__stream_encoder_finish(enc)
        let code = errno
        if ok == 0 {
            let err = failure(code)
            cleanup()
            throw err
        }
        cleanup()
    }

    func abort() {
        finished = true
        cleanup()
    }
}
