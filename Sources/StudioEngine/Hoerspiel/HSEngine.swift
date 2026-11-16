import Foundation
import MLStudio

/// Hörspiel-Rechenprozess (Resources/HoerspielEngine/engine.py) mit typisierten Aufrufen. Derselbe Verbindungsweg
/// wie KI-Musik: JSON-Zeilen über stdin/stdout, Sandbox ohne Netz, niedrige Priorität, beendbar zu jeder Zeit.
public final class HSEngine: @unchecked Sendable {
    public let installer: HSInstaller
    private let client: KIEngineClient

    public init(installer: HSInstaller, denyNetwork: Bool = true) {
        self.installer = installer
        let p = installer.paths
        self.client = KIEngineClient(.init(python: p.python, script: p.engineScript, aceRoot: p.engineDir, checkpoints: p.models,
                                           log: p.log, denyNetwork: denyNetwork,
                                           environment: ["HF_HOME": p.models.path, "HF_HUB_OFFLINE": "1"]))
    }

    public var isRunning: Bool { client.isRunning }

    /// Prozess beenden – laufende Anfragen enden mit „Abgebrochen“, der Speicher ist frei.
    public func shutdown() { client.stop() }

    public typealias Progress = KIEngineClient.Progress

    public func status() async throws -> [String: Any] { try await client.request("status") }

    // MARK: Geschichte

    public func loadLLM(_ model: HSModel, progress: Progress? = nil) async throws {
        _ = try await client.request("load_llm", ["model": model.repo], progress: progress)
    }

    public func concept(prompt: String, minutes: Double, mode: HSMode, characters: [String] = [], style: String? = nil,
                        progress: Progress? = nil) async throws -> [String: Any] {
        var payload: [String: Any] = ["prompt": prompt, "minutes": minutes, "mode": mode.rawValue, "characters": characters]
        if let style { payload["style"] = style }
        let r = try await client.request("concept", payload, progress: progress)
        guard let c = r["concept"] as? [String: Any] else { throw StudioError.other("Das Sprachmodell lieferte kein Konzept.") }
        return c
    }

    public func scene(concept: [String: Any], index: Int, summaries: [String], tail: String, targetWords: Int,
                      progress: Progress? = nil) async throws -> [String: Any] {
        let r = try await client.request("scene", ["concept": concept, "index": index, "summaries": summaries, "tail": tail,
                                                   "target_words": targetWords], progress: progress)
        guard let s = r["scene"] as? [String: Any] else { throw StudioError.other("Das Sprachmodell lieferte keine Szene.") }
        return s
    }

    public func unloadLLM() async throws { _ = try await client.request("unload_llm") }

    /// Eine einzelne Replik neu formulieren.
    public func rewriteLine(concept: [String: Any], sceneText: String, speaker: String, line: String, hint: String,
                            progress: Progress? = nil) async throws -> String {
        let r = try await client.request("rewrite_line", ["concept": concept, "scene_text": sceneText, "speaker": speaker,
                                                          "line": line, "hint": hint], progress: progress)
        return (r["text"] as? String) ?? line
    }

    public struct MusicPiece: Sendable {
        public let kind: String
        public let caption: String
        public let seconds: Double
    }

    /// Welche Musikstücke eine Produktion braucht (Titel, Übergang, Spannung, Finale, Abspann).
    public func musicPlan(story: [String: Any]) async throws -> [MusicPiece] {
        let r = try await client.request("music_plan", ["story": story])
        let pieces = r["pieces"] as? [String: [String: Any]] ?? [:]
        let order = ["titel", "uebergang", "spannung", "finale", "abspann"]
        return pieces.keys.sorted { (order.firstIndex(of: $0) ?? 9) < (order.firstIndex(of: $1) ?? 9) }.map {
            MusicPiece(kind: $0, caption: pieces[$0]?["caption"] as? String ?? "", seconds: (pieces[$0]?["seconds"] as? Double) ?? 15)
        }
    }

    // MARK: Stimmen

    public struct DesignedVoice: Sendable {
        public let path: String
        public let text: String
        public let duration: Double
    }

    public func designVoice(instruct: String, text: String? = nil, seed: Int, out: URL,
                            progress: Progress? = nil) async throws -> DesignedVoice {
        var payload: [String: Any] = ["instruct": instruct, "seed": seed, "out": out.path, "language": "de"]
        if let text { payload["text"] = text }
        let r = try await client.request("design_voice", payload, progress: progress)
        return DesignedVoice(path: r["path"] as? String ?? out.path, text: r["text"] as? String ?? text ?? "",
                             duration: (r["duration"] as? Double) ?? 0)
    }

    public struct LineRequest: Sendable {
        public let key: String
        public let text: String
        public let refAudio: String
        public let refText: String
        public let out: String
        public init(key: String, text: String, refAudio: String, refText: String, out: String) {
            self.key = key
            self.text = text
            self.refAudio = refAudio
            self.refText = refText
            self.out = out
        }
    }

    public struct LineResult: Sendable {
        public let key: String
        public let path: String?
        public let spoken: String?
        public let duration: Double
    }

    public func speak(_ lines: [LineRequest], progress: Progress? = nil) async throws -> [LineResult] {
        let payload: [[String: Any]] = lines.map { ["key": $0.key, "text": $0.text, "ref_audio": $0.refAudio, "ref_text": $0.refText,
                                                     "out": $0.out] }
        let r = try await client.request("speak", ["lines": payload, "language": "de"], progress: progress)
        return (r["results"] as? [[String: Any]] ?? []).map {
            LineResult(key: $0["key"] as? String ?? "", path: $0["path"] as? String, spoken: $0["spoken"] as? String,
                       duration: ($0["duration"] as? Double) ?? 0)
        }
    }

    public func unloadTTS() async throws { _ = try await client.request("unload_tts") }

    // MARK: Geräusche, Analyse, Prüfung, Mischung

    public func sfx(prompt: String, seconds: Double, library: URL, seed: Int = 7, progress: Progress? = nil) async throws -> String {
        let r = try await client.request("sfx", ["prompt": prompt, "seconds": seconds, "library": library.path, "seed": seed],
                                         progress: progress)
        guard let path = r["path"] as? String else { throw StudioError.other("Kein Geräusch erzeugt.") }
        return path
    }

    public func analyze(file: URL, name: String, out: URL, progress: Progress? = nil) async throws -> (result: [String: Any], profile: [String: Any]) {
        let r = try await client.request("analyze", ["path": file.path, "name": name, "out": out.path], progress: progress)
        return (r["result"] as? [String: Any] ?? [:], r["profile"] as? [String: Any] ?? [:])
    }

    public struct ConsentCheck: Sendable {
        public let similarity: Double
        public let transcript: String
        public let sampleTranscript: String
        public let sampleSeconds: Double
    }

    /// Einwilligung prüfen: Stimmähnlichkeit Einwilligung ↔ Stimmprobe und was in beiden gesagt wird.
    public func verifyConsent(recording: URL, sample: URL, progress: Progress? = nil) async throws -> ConsentCheck {
        let r = try await client.request("verify_consent", ["consent": recording.path, "sample": sample.path], progress: progress)
        return ConsentCheck(similarity: (r["similarity"] as? Double) ?? 0, transcript: r["transcript"] as? String ?? "",
                            sampleTranscript: r["sample_transcript"] as? String ?? "", sampleSeconds: (r["sample_seconds"] as? Double) ?? 0)
    }

    public struct MixResult: Sendable {
        public let master: String
        public let stems: [String: String]
        public let chapters: [(title: String, start: Double)]
        public let loudness: Double?
        public let speechToBackground: Double?
        public let duration: Double
    }

    public func mix(story: [String: Any], voiceFiles: [String: String], sfxFiles: [String: String], musicFiles: [String: String],
                    retro: Double, lufs: Double, outDir: URL, progress: Progress? = nil) async throws -> MixResult {
        let r = try await client.request("mix", ["story": story, "voice_files": voiceFiles, "sfx_files": sfxFiles,
                                                 "music_files": musicFiles, "retro": retro, "lufs": lufs, "out_dir": outDir.path],
                                         progress: progress)
        let metrics = r["metrics"] as? [String: Any] ?? [:]
        let chapters = (r["chapters"] as? [[String: Any]] ?? []).map { (title: $0["title"] as? String ?? "", start: ($0["start"] as? Double) ?? 0) }
        return MixResult(master: r["master"] as? String ?? "", stems: r["stems"] as? [String: String] ?? [:], chapters: chapters,
                         loudness: metrics["loudness_lufs"] as? Double, speechToBackground: metrics["speech_to_background_db"] as? Double,
                         duration: (metrics["duration_s"] as? Double) ?? 0)
    }

    public func unloadAll() async throws { _ = try await client.request("unload") }
}
