import Foundation
import MLStudio

/// Angaben zur Quelle, soweit beim Öffnen bekannt.
struct SourceFormat: Equatable {
    /// Kurzname des Codecs („MP3“, „AAC“, „ALAC“, „FLAC“, „PCM“, „Vorbis“ …).
    var codec: String
    /// Verlustfrei (PCM, FLAC, ALAC …).
    var isLossless: Bool
    /// Gleitkomma-PCM.
    var isFloat: Bool
    /// Ganzzahl-Bittiefe (nur verlustfreie Quellen), sonst nil.
    var bitsPerSample: Int?
}

/// Blockweise lesende Audioquelle (Float32, planar). Nie die ganze Datei im Speicher.
protocol PCMReader: AnyObject {
    /// Abtastrate der gelieferten Daten.
    var sampleRate: Double { get }
    /// Kanäle der gelieferten Daten (nach dem Heruntermischen höchstens 2, falls verlangt).
    var channelCount: Int { get }
    /// Kanäle der Quelle (vor dem Heruntermischen).
    var sourceChannelCount: Int { get }
    /// Länge in Frames (nil = unbekannt; bei komprimierten Formaten ggf. geschätzt).
    var lengthFrames: Int64? { get }
    var format: SourceFormat { get }
    /// Springt genau zu `frame` (0 = Anfang).
    func seek(to frame: Int64) throws
    /// Liest bis zu `maxFrames` (≤ `block.capacity`) Frames ab der aktuellen Position nach `block`
    /// (setzt `block.frames`). 0 = Ende.
    func read(into block: FloatBlock, maxFrames: Int) throws -> Int
    /// Gibt Ressourcen frei (auch temporäre Dateien).
    func close()
}

extension PCMReader {
    var durationSeconds: Double? { lengthFrames.map { Double($0) / sampleRate } }
}

/// Heruntermischen auf Stereo nach Kanalreihenfolge (für Quellen ohne Apple-Kanal-Layout, z. B. Vorbis).
enum StereoDownmix {
    /// Koeffizienten (links, rechts) je Quellkanal für Vorbis-Reihenfolge, normiert, damit nichts übersteuert.
    static func vorbisMatrix(channels: Int) -> [(Float, Float)] {
        let c: Float = 0.7071
        let raw: [(Float, Float)]
        switch channels {
        case 1: raw = [(1, 1)]
        case 2: raw = [(1, 0), (0, 1)]
        case 3: raw = [(1, 0), (c, c), (0, 1)]                                   // L C R
        case 4: raw = [(1, 0), (0, 1), (c, 0), (0, c)]                           // FL FR RL RR
        case 5: raw = [(1, 0), (c, c), (0, 1), (c, 0), (0, c)]                   // FL C FR RL RR
        case 6: raw = [(1, 0), (c, c), (0, 1), (c, 0), (0, c), (0, 0)]           // FL C FR RL RR LFE
        case 7: raw = [(1, 0), (c, c), (0, 1), (c, 0), (0, c), (0.5, 0.5), (0, 0)]   // FL C FR SL SR RC LFE
        default:
            // 8: FL C FR SL SR RL RR LFE; weitere Kanäle werden ignoriert
            var m: [(Float, Float)] = [(1, 0), (c, c), (0, 1), (c, 0), (0, c), (c, 0), (0, c), (0, 0)]
            while m.count < channels { m.append((0, 0)) }
            raw = Array(m.prefix(channels))
        }
        let sumL = raw.reduce(Float(0)) { $0 + $1.0 }
        let sumR = raw.reduce(Float(0)) { $0 + $1.1 }
        let norm = 1 / max(sumL, sumR, 1)
        return raw.map { ($0.0 * norm, $0.1 * norm) }
    }
}
