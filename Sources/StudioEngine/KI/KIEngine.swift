import Foundation
import MLStudio

/// `KIEngineServing` über den lokalen Python-Prozess (ACE-Step 1.5).
public final class KIEngine: KIEngineServing, @unchecked Sendable {
    private let client: KIEngineClient

    public init(installer: KIInstaller, denyNetwork: Bool = true) {
        let p = installer.paths
        client = KIEngineClient(.init(python: p.python, script: p.engineScript, aceRoot: p.aceRoot, checkpoints: p.checkpoints, log: p.log,
                                      denyNetwork: denyNetwork))
    }

    public var isRunning: Bool { client.isRunning }

    public func prepare(dit: String, lm: String?, progress: @escaping @Sendable (Double, String) -> Void) async throws {
        var payload: [String: Any] = ["dit": dit]
        if let lm { payload["lm"] = lm }
        _ = try await client.request("load", payload, progress: progress)
    }

    public func writeLyrics(query: String, caption: String, lyrics: String, language: String?, instrumental: Bool,
                            progress: @escaping @Sendable (Double, String) -> Void) async throws -> KILyricsResult {
        var payload: [String: Any] = ["query": query, "caption": caption, "lyrics": lyrics, "instrumental": instrumental]
        if let language { payload["language"] = language }
        let r = try await client.request("write_lyrics", payload, progress: progress)
        return Self.lyrics(from: r) ?? KILyricsResult(caption: caption, lyrics: lyrics)
    }

    public func generate(params: [String: KIValue], variations: Int, seeds: [Int]?, saveDirectory: URL, usePlanning: Bool,
                         progress: @escaping @Sendable (Double, String) -> Void) async throws -> KIGenerationResult {
        let data = try JSONEncoder().encode(params)
        let plain = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        var payload: [String: Any] = ["params": plain, "batch_size": max(1, variations), "save_dir": saveDirectory.path,
                                      "format": "flac", "use_lm": usePlanning]
        if let seeds, !seeds.isEmpty { payload["seeds"] = seeds }
        let r = try await client.request("generate", payload, progress: progress)
        let files = (r["files"] as? [[String: Any]] ?? []).compactMap { f -> KIGeneratedFile? in
            guard let path = f["path"] as? String else { return nil }
            return KIGeneratedFile(url: URL(fileURLWithPath: path), seed: (f["seed"] as? NSNumber)?.intValue)
        }
        guard !files.isEmpty else { throw StudioError.other("Das Modell hat keine Audiodatei geliefert.") }
        return KIGenerationResult(files: files, seconds: (r["seconds"] as? Double) ?? 0,
                                  planned: Self.lyrics(from: r["metadata"] as? [String: Any] ?? [:]))
    }

    public func shutdown() { client.stop() }

    static func lyrics(from r: [String: Any]) -> KILyricsResult? {
        let caption = r["caption"] as? String ?? ""
        let lyrics = r["lyrics"] as? String ?? ""
        if caption.isEmpty && lyrics.isEmpty { return nil }
        func int(_ v: Any?) -> Int? {
            if let n = v as? NSNumber { return n.intValue }
            if let s = v as? String { return Int(s) }
            return nil
        }
        func double(_ v: Any?) -> Double? {
            if let n = v as? NSNumber { return n.doubleValue }
            if let s = v as? String { return Double(s) }
            return nil
        }
        return KILyricsResult(caption: caption, lyrics: lyrics, bpm: int(r["bpm"]), duration: double(r["duration"]),
                              keyscale: r["keyscale"] as? String, language: r["language"] as? String)
    }
}
