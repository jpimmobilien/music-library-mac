import Foundation

// KI-Hörspiel – Modellkatalog und Eignung des Macs (reine Logik, unter Linux getestet).
// Größen und Stände: gemessen am 16.11.2026 mit scripts/hoerspiel/catalog_check.py (Hugging-Face-API, alle Dateien
// des Repos; alle Repos frei zugänglich, nicht „gated“) – siehe docs/KI_HOERSPIEL_MACHBARKEIT.md.

public struct HSModel: Hashable, Sendable, Identifiable {
    public enum Purpose: String, Sendable { case story, voiceDesign, voiceClone, analysis, sfx }

    public var id: String { repo }
    public let repo: String
    public let title: String
    public let purpose: Purpose
    public let detail: String
    /// Ungefähre Größe auf der Platte in Bytes.
    public let bytes: Int64
    /// Lizenz der Gewichte (Kurzname).
    public let license: String
    /// Mindest-Arbeitsspeicher, ab dem das Modell sinnvoll ist (GB).
    public let minMemoryGB: Double
    /// Geprüfter Stand (Commit auf Hugging Face). Geladen wird genau dieser Stand, nicht der jeweils neueste.
    public let revision: String

    // Geschichten (mlx-lm)
    public static let storyLarge = HSModel(repo: "mlx-community/gemma-4-26b-a4b-it-4bit", title: "Gemma 4 26B-A4B (4 bit)",
                                           purpose: .story, detail: "Geschichten und Dialoge – empfohlen ab 32 GB (MoE, 3,8B aktiv)",
                                           bytes: 15_373_588_575, license: "Apache-2.0", minMemoryGB: 32,
                                           revision: "0d77464eeb233a2da68ebf9d7dc4edaac7db956d")
    public static let storyMedium = HSModel(repo: "mlx-community/Qwen3.5-9B-MLX-4bit", title: "Qwen3.5 9B (4 bit)",
                                            purpose: .story, detail: "Geschichten – für Macs mit 16–32 GB",
                                            bytes: 5_977_074_591, license: "Apache-2.0", minMemoryGB: 16,
                                            revision: "938d8919941c6e7efd3c7150eff7fe9d12afa631")
    public static let storySmall = HSModel(repo: "mlx-community/Qwen3.5-4B-MLX-4bit", title: "Qwen3.5 4B (4 bit)",
                                           purpose: .story, detail: "Geschichten – nur für kleine Macs, deutlich schwächer",
                                           bytes: 3_061_132_920, license: "Apache-2.0", minMemoryGB: 8,
                                           revision: "32f3e8ecf65426fc3306969496342d504bfa13f3")
    // Stimmen (mlx-audio, Qwen3-TTS)
    public static let voiceDesign = HSModel(repo: "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16",
                                            title: "Qwen3-TTS 1.7B VoiceDesign", purpose: .voiceDesign,
                                            detail: "Stimmen aus einer Beschreibung entwerfen", bytes: 4_520_194_992,
                                            license: "Apache-2.0", minMemoryGB: 8,
                                            revision: "7d3824abff87e49756bb0f83fb5411de75d160c4")
    public static let voiceClone = HSModel(repo: "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16", title: "Qwen3-TTS 1.7B Base",
                                           purpose: .voiceClone, detail: "Alle Zeilen in der entworfenen Stimme sprechen",
                                           bytes: 4_544_212_739, license: "Apache-2.0", minMemoryGB: 8,
                                           revision: "a6eb4f68e4b056f1215157bb696209bc82a6db48")
    // Analyse
    public static let whisper = HSModel(repo: "mlx-community/whisper-large-v3-turbo", title: "Whisper large-v3-turbo",
                                        purpose: .analysis, detail: "Text und Wortzeiten einer Referenz", bytes: 1_613_979_758,
                                        license: "MIT", minMemoryGB: 8,
                                        revision: "a4aaeec0636e6fef84abdcbe3544cb2bf7e9f6fb")
    public static let vad = HSModel(repo: "mlx-community/silero-vad", title: "Silero VAD", purpose: .analysis,
                                    detail: "Sprache erkennen", bytes: 2_182_124, license: "MIT", minMemoryGB: 8,
                                    revision: "7bc17f22d3c0451bd3a6cd71e759b009271ff49a")
    public static let speaker = HSModel(repo: "aufklarer/SpeechBrain-ECAPA-VoxCeleb-20M-MLX", title: "SpeechBrain ECAPA",
                                        purpose: .analysis, detail: "Sprecher unterscheiden, Stimmen vergleichen",
                                        bytes: 41_669_792, license: "Apache-2.0", minMemoryGB: 8,
                                        revision: "e749e6e08557f4a3ceb6ce3bf6f0b79efe592a77")
    // Geräusche
    public static let sfx = HSModel(repo: "mlx-community/stable-audio-3-small-sfx", title: "Stable Audio 3 small (Geräusche)",
                                    purpose: .sfx, detail: "Geräusche und Atmosphären aus einer Beschreibung",
                                    bytes: 3_492_142_228, license: "Stability AI Community License", minMemoryGB: 8,
                                    revision: "ca6c38718d27cd2b446a4661c8851f1f3d0a3870")

    public static let story: [HSModel] = [storyLarge, storyMedium, storySmall]
    public static let voices: [HSModel] = [voiceDesign, voiceClone]
    public static let analysis: [HSModel] = [whisper, vad, speaker]
    public static let all: [HSModel] = story + voices + analysis + [sfx]
}

public enum HSHardware {
    /// Empfohlenes Geschichtenmodell für den Arbeitsspeicher; nil = Hörspiele hier nicht möglich.
    public static func storyModel(memoryGB: Double) -> HSModel? {
        if memoryGB >= HSModel.storyLarge.minMemoryGB { return .storyLarge }
        if memoryGB >= HSModel.storyMedium.minMemoryGB { return .storyMedium }
        if memoryGB >= HSModel.storySmall.minMemoryGB { return .storySmall }
        return nil
    }

    /// Gleiche Bedingungen wie KI-Musik: Apple-Chip, macOS 14+.
    public static func support(machine: String, translated: Bool, memoryGB: Double, macOSMajor: Int) -> KISupport {
        if machine != "arm64" && !translated {
            return .unsupported(reason: "KI-Hörbücher brauchen einen Mac mit Apple-Chip (M1 oder neuer). Die übrige Musikbibliothek "
                                + "funktioniert wie gewohnt.")
        }
        if macOSMajor < 14 { return .unsupported(reason: "KI-Hörbücher brauchen macOS 14 Sonoma oder neuer.") }
        guard let model = storyModel(memoryGB: memoryGB) else {
            return .unsupported(reason: "Für Geschichten und Stimmen werden mindestens 8 GB Arbeitsspeicher gebraucht.")
        }
        if model != .storyLarge {
            return .limited(recommendedLM: model.repo, reason: "Mit \(Int(memoryGB.rounded())) GB Arbeitsspeicher wird das "
                            + "kleinere Sprachmodell „\(model.title)“ verwendet – die Geschichten sind einfacher.")
        }
        return .supported(recommendedLM: model.repo)
    }

    /// Benötigter Platz für alles, was für ein Hörspiel nötig ist (Umgebung, Geschichtenmodell, Stimmen, Analyse,
    /// Geräusche) – grobe Angabe für die Anzeige.
    public static func requiredBytes(story: HSModel) -> Int64 {
        2_000_000_000 + story.bytes + HSModel.voices.reduce(0) { $0 + $1.bytes } + HSModel.analysis.reduce(0) { $0 + $1.bytes }
            + HSModel.sfx.bytes
    }
}
