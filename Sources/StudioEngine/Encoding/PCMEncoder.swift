import Foundation
import MLStudio

/// Parameter für einen Encoder (Ausgabeseite).
struct EncoderSpec {
    var sampleRate: Int
    var channels: Int
    /// Bittiefe (nur verlustfreie Formate; verlustbehaftete arbeiten mit Float).
    var depth: PCMDepth
    /// TPDF-Dither beim Verringern auf 16 Bit.
    var dither: Bool
    /// Erwartete Länge in Frames (für FLAC-Seektable, Schätzung genügt).
    var totalFramesEstimate: Int64?
}

/// Encoder: nimmt planare Float32-Blöcke an und schreibt eine Datei.
protocol PCMEncoder: AnyObject {
    /// Schreibt alle gültigen Frames von `block` (Kanalzahl = `spec.channels`).
    func write(_ block: FloatBlock) throws
    /// Schließt die Datei ordnungsgemäß ab (Kopfdaten, Längen, Infoframe …).
    func finish() throws
    /// Bricht ab und schließt die Datei ohne Abschluss (Datei wird vom Aufrufer gelöscht).
    func abort()
}

/// Erzeugt den passenden Encoder für ein Format.
enum EncoderFactory {
    static func make(format: StudioFormat, url: URL, spec: EncoderSpec, options: ExportOptions) throws -> PCMEncoder {
        switch format {
        case .wav: return try WAVEncoder(url: url, spec: spec)
        case .aiff: return try AIFFEncoder(url: url, spec: spec)
        case .flac: return try FLACEncoder(url: url, spec: spec, level: options.flacLevel)
        case .mp3: return try MP3Encoder(url: url, spec: spec, bitrateKbps: options.mp3Bitrate)
        case .aac, .m4a:
            #if canImport(AudioToolbox)
            return try AACEncoder(url: url, spec: spec, bitrateKbps: options.aacBitrate, adts: format == .aac)
            #else
            throw StudioError.encodeFailed("AAC ist nur unter macOS verfügbar.")
            #endif
        }
    }
}
