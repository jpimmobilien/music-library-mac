import Foundation

// Audio Studio (Version 2.2): Zielformate, Qualitätsstufen und ehrliche Hinweise.
// Reine Logik ohne Apple-Frameworks – auch unter Linux testbar.

/// Zielformat eines Exports.
public enum StudioFormat: String, CaseIterable, Codable, Hashable, Sendable {
    case mp3
    case wav
    case flac
    case aac
    case m4a
    case aiff

    public var label: String {
        switch self {
        case .mp3: return "MP3"
        case .wav: return "WAV"
        case .flac: return "FLAC"
        case .aac: return "AAC"
        case .m4a: return "M4A"
        case .aiff: return "AIFF"
        }
    }

    /// Dateiendung ohne Punkt.
    public var fileExtension: String {
        switch self {
        case .mp3: return "mp3"
        case .wav: return "wav"
        case .flac: return "flac"
        case .aac: return "aac"
        case .m4a: return "m4a"
        case .aiff: return "aiff"
        }
    }

    /// Kurzbeschreibung für die Auswahl.
    public var summary: String {
        switch self {
        case .mp3: return "Verlustbehaftet · überall abspielbar"
        case .wav: return "Unkomprimiert · PCM"
        case .flac: return "Verlustfrei komprimiert"
        case .aac: return "Verlustbehaftet · roher AAC-Datenstrom (ADTS)"
        case .m4a: return "AAC im MPEG-4-Container · mit Tags und Cover"
        case .aiff: return "Unkomprimiert · Apple-Format"
        }
    }

    public var isLossless: Bool {
        switch self {
        case .wav, .flac, .aiff: return true
        case .mp3, .aac, .m4a: return false
        }
    }

    /// Kann Tags (Titel, Interpret, …) und ein Cover tragen. Roher AAC-Datenstrom (ADTS) kann es nicht.
    public var supportsTags: Bool { self != .aac }

    /// Mögliche Abtastraten (nil = Original beibehalten, sofern das Format sie unterstützt).
    public var sampleRateChoices: [Int?] {
        switch self {
        case .mp3: return [nil, 44_100, 48_000]
        case .aac, .m4a: return [nil, 44_100, 48_000]
        case .wav, .aiff: return [nil, 44_100, 48_000, 96_000]
        case .flac: return [nil, 44_100, 48_000, 96_000]
        }
    }

    /// Abtastraten, die der Encoder direkt annimmt (andere werden auf die nächstpassende umgerechnet).
    public var encoderSampleRates: [Int]? {
        switch self {
        case .mp3: return [32_000, 44_100, 48_000]   // MPEG-1 Layer III
        case .aac, .m4a: return [8_000, 11_025, 12_000, 16_000, 22_050, 24_000, 32_000, 44_100, 48_000]
        case .wav, .aiff, .flac: return nil          // beliebig
        }
    }
}

/// Bittiefe für WAV und AIFF (und FLAC: 16/24).
public enum PCMDepth: String, CaseIterable, Codable, Hashable, Sendable {
    case int16
    case int24
    case float32

    public var label: String {
        switch self {
        case .int16: return "16 Bit"
        case .int24: return "24 Bit"
        case .float32: return "32 Bit Float"
        }
    }

    public var bits: Int {
        switch self {
        case .int16: return 16
        case .int24: return 24
        case .float32: return 32
        }
    }
}

/// Einstellungen eines Exports. Nicht passende Felder werden vom jeweiligen Format ignoriert.
public struct ExportOptions: Codable, Hashable, Sendable {
    public var format: StudioFormat
    /// MP3: konstante Bitrate in kbit/s (96…320).
    public var mp3Bitrate: Int
    /// AAC/M4A: Bitrate in kbit/s (96…320).
    public var aacBitrate: Int
    /// WAV/AIFF: Bittiefe. FLAC: nur 16 oder 24 Bit (float32 → 24 Bit).
    public var pcmDepth: PCMDepth
    /// FLAC: Bittiefe der Quelle beibehalten (16 bzw. 24 Bit), sonst `pcmDepth`.
    public var flacKeepSourceDepth: Bool
    /// Abtastrate in Hz; nil = Original (falls das Format sie nicht kann: nächstpassende).
    public var sampleRate: Int?
    /// FLAC-Kompressionsstufe 0 (schnell) … 8 (klein); Standard 5.
    public var flacLevel: Int
    /// Mono-Quellen bleiben mono; Mehrkanal (> 2) wird auf Stereo heruntergemischt.
    public var keepMono: Bool

    public static let mp3Bitrates = [96, 128, 160, 192, 224, 256, 320]
    public static let aacBitrates = [96, 128, 160, 192, 256, 320]
    public static let flacLevels = 0...8

    public init(format: StudioFormat, mp3Bitrate: Int = 320, aacBitrate: Int = 256, pcmDepth: PCMDepth = .int16,
                flacKeepSourceDepth: Bool = true, sampleRate: Int? = nil, flacLevel: Int = 5, keepMono: Bool = true) {
        self.format = format
        self.mp3Bitrate = mp3Bitrate
        self.aacBitrate = aacBitrate
        self.pcmDepth = pcmDepth
        self.flacKeepSourceDepth = flacKeepSourceDepth
        self.sampleRate = sampleRate
        self.flacLevel = flacLevel
        self.keepMono = keepMono
    }

    /// Sinnvolle Standardwerte je Format.
    public static func defaults(for format: StudioFormat) -> ExportOptions {
        switch format {
        case .mp3: return ExportOptions(format: .mp3, mp3Bitrate: 320)
        case .aac, .m4a: return ExportOptions(format: format, aacBitrate: 256)
        case .wav, .aiff: return ExportOptions(format: format, pcmDepth: .int16, sampleRate: nil)
        case .flac: return ExportOptions(format: .flac, pcmDepth: .int24, flacKeepSourceDepth: true, flacLevel: 5)
        }
    }

    /// Werte auf zulässige Bereiche bringen (z. B. nach dem Laden alter Einstellungen).
    public func normalized() -> ExportOptions {
        var o = self
        if !Self.mp3Bitrates.contains(o.mp3Bitrate) { o.mp3Bitrate = Self.nearest(o.mp3Bitrate, in: Self.mp3Bitrates) }
        if !Self.aacBitrates.contains(o.aacBitrate) { o.aacBitrate = Self.nearest(o.aacBitrate, in: Self.aacBitrates) }
        o.flacLevel = min(max(o.flacLevel, Self.flacLevels.lowerBound), Self.flacLevels.upperBound)
        if let sr = o.sampleRate, !o.format.sampleRateChoices.contains(sr) { o.sampleRate = nil }
        return o
    }

    /// Tatsächliche Abtastrate der Ausgabe für eine Quelle mit `sourceRate`.
    public func outputSampleRate(sourceRate: Int) -> Int {
        let wanted = sampleRate ?? sourceRate
        guard let allowed = format.encoderSampleRates else { return max(wanted, 1) }
        if allowed.contains(wanted) { return wanted }
        // nächsthöhere zulässige Rate (kein unnötiger Verlust), sonst die höchste
        return allowed.first(where: { $0 >= wanted }) ?? allowed.last ?? 44_100
    }

    /// Tatsächliche Bittiefe der Ausgabe (nur verlustfreie Formate).
    public func outputDepth(sourceBits: Int?) -> PCMDepth {
        switch format {
        case .flac:
            if flacKeepSourceDepth, let bits = sourceBits {
                return bits <= 16 ? .int16 : .int24
            }
            return pcmDepth == .int16 ? .int16 : .int24
        case .wav, .aiff:
            return pcmDepth
        case .mp3, .aac, .m4a:
            return .float32
        }
    }

    /// Kurzbeschreibung, z. B. „MP3 · 320 kbit/s“ oder „WAV · 24 Bit · 48 kHz“.
    public func summary(sourceRate: Int? = nil) -> String {
        var parts = [format.label]
        switch format {
        case .mp3: parts.append("\(mp3Bitrate) kbit/s")
        case .aac, .m4a: parts.append("\(aacBitrate) kbit/s")
        case .wav, .aiff: parts.append(pcmDepth.label)
        case .flac: parts.append(flacKeepSourceDepth ? "Bittiefe wie Quelle" : (pcmDepth == .int16 ? "16 Bit" : "24 Bit")); parts.append("Stufe \(flacLevel)")
        }
        if let sr = sampleRate { parts.append(Self.rateLabel(sr)) } else if let src = sourceRate { parts.append(Self.rateLabel(outputSampleRate(sourceRate: src))) }
        return parts.joined(separator: " · ")
    }

    public static func rateLabel(_ hz: Int) -> String {
        let khz = Double(hz) / 1000
        let text = khz == khz.rounded() ? String(Int(khz)) : String(format: "%.1f", khz).replacingOccurrences(of: ".", with: ",")
        return "\(text) kHz"
    }

    private static func nearest(_ value: Int, in list: [Int]) -> Int {
        list.min(by: { abs($0 - value) < abs($1 - value) }) ?? list[0]
    }
}

/// Ehrliche Hinweise zur Qualität – die App verspricht keine Verbesserung, die es nicht gibt.
public enum QualityAdvice {
    /// Hinweise für Quelle → Ziel. `sourceLossless` = Quelle ist verlustfrei (WAV, FLAC, ALAC, AIFF).
    public static func notes(options: ExportOptions, sourceLossless: Bool?, sourceBitrate: Int?, sourceRate: Int?, sourceBits: Int?) -> [String] {
        var notes: [String] = []
        let target = options.format
        if target.isLossless, sourceLossless == false {
            notes.append("Die Quelle ist verlustbehaftet komprimiert. \(target.label) speichert sie ohne weiteren Verlust, macht sie aber nicht besser – die Datei wird nur größer.")
        }
        if !target.isLossless, let kbps = sourceBitrate, kbps > 0, sourceLossless == false {
            let targetKbps = target == .mp3 ? options.mp3Bitrate : options.aacBitrate
            if targetKbps > kbps + 8 {
                notes.append("Die Quelle hat nur etwa \(kbps) kbit/s. \(targetKbps) kbit/s erhöhen die Dateigröße, nicht die Qualität.")
            }
        }
        if !target.isLossless, sourceLossless == false {
            notes.append("Erneutes verlustbehaftetes Komprimieren kostet etwas Qualität. Für die Bibliothek ist M4A oder MP3 mit hoher Bitrate ein guter Kompromiss.")
        }
        if let sr = options.sampleRate, let src = sourceRate, sr > src {
            notes.append("Eine höhere Abtastrate (\(ExportOptions.rateLabel(sr))) als die Quelle (\(ExportOptions.rateLabel(src))) fügt keine Information hinzu.")
        }
        if target.isLossless, let bits = sourceBits, options.outputDepth(sourceBits: bits).bits > bits, target != .flac || !options.flacKeepSourceDepth {
            if options.outputDepth(sourceBits: bits) != .float32 {
                notes.append("Mehr Bittiefe als die Quelle (\(bits) Bit) fügt keine Information hinzu.")
            }
        }
        if target == .aac {
            notes.append("Roher AAC-Datenstrom kann keine Tags und kein Cover speichern. Für die Bibliothek ist M4A besser geeignet.")
        }
        return notes
    }
}
