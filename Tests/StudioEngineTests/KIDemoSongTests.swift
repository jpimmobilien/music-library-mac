import XCTest
import MLStudio
@testable import StudioEngine

/// Ein Teststück mit dem Code von Version 2.5.0 erzeugen, so wie die App es tut: Einrichtung (`KIInstaller`),
/// Songtext (`KIEngine.writeLyrics`), Erzeugen (`KIEngine.generate`, Sandbox ohne Netz) und Umwandlung in MP3
/// mit dem Exporter der App (wie „In Bibliothek übernehmen“). Läuft nur mit `KI_SONG=1` (Prüfstand KI-Song).
///
/// Umgebung: `KI_E2E_BASE` (Umgebung/Modelle), `KI_E2E_OUT` (Ergebnisse), `KI_SONG_PROMPT`, `KI_SONG_LANG`,
/// `KI_SONG_DURATION`, `KI_SONG_LYRICS_FILE` (eigener Text; fehlt = nur KI-Text).
final class KIDemoSongTests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private var base: URL { URL(fileURLWithPath: env["KI_E2E_BASE"] ?? NSTemporaryDirectory() + "ki-e2e", isDirectory: true) }
    private var out: URL { URL(fileURLWithPath: env["KI_E2E_OUT"] ?? NSTemporaryDirectory() + "ki-song", isDirectory: true) }
    private var scripts: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/KIEngine", isDirectory: true)
    }

    private func log(_ text: String) { print("[KI-Song] \(text)") }

    func testCreateSong() async throws {
        try XCTSkipUnless(env["KI_SONG"] == "1", "nur im Prüfstand KI-Song")
        let prompt = env["KI_SONG_PROMPT"] ?? "Fröhlicher chinesischer Popsong (Mandopop) mit heller Frauenstimme und eingängigem Refrain"
        let language = env["KI_SONG_LANG"] ?? "zh"
        let duration = Double(env["KI_SONG_DURATION"] ?? "90") ?? 90
        let ownLyrics = env["KI_SONG_LYRICS_FILE"].flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } ?? ""

        // 1. Einrichtung wie „Jetzt einrichten“
        let inst = KIInstaller(base: base, scripts: scripts)
        var t = Date()
        try await inst.installEnvironment { _ in }
        try await inst.download(.core) { _ in }
        try await inst.download(.lmSmall) { _ in }
        log("Einrichtung: \(Int(Date().timeIntervalSince(t))) s")
        XCTAssertTrue(inst.environmentReady && inst.isInstalled(.core) && inst.isInstalled(.lmSmall))
        try inst.installScripts()
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let engine = KIEngine(installer: inst)
        defer { engine.shutdown() }
        t = Date()
        try await engine.prepare(dit: KIQuality.balanced.ditModel, lm: KIModel.lmSmall.id) { _, _ in }
        log("Modelle geladen: \(Int(Date().timeIntervalSince(t))) s")

        // 2. „KI schreibt den Text“ – Ablauf wie KIMusicModel.generate
        t = Date()
        let written = try await engine.writeLyrics(query: prompt, caption: prompt, lyrics: "", language: language, instrumental: false) { _, _ in }
        log("KI-Text (\(Int(Date().timeIntervalSince(t))) s), Beschreibung: \(written.caption)")
        log("KI-Text: " + written.lyrics.replacingOccurrences(of: "\n", with: " / "))
        XCTAssertFalse(written.lyrics.isEmpty)
        let a = KIGenerationRequest(prompt: prompt, lyricsMode: .aiWrites, language: language, duration: duration, seed: 2026, quality: .balanced)
        try await make("A-ki-text-gesang", request: a, lyrics: written.lyrics, caption: written.caption.isEmpty ? nil : written.caption,
                       engine: engine, title: "Teststück – KI-Text")

        // 3. „Eigener Text“ (optional)
        if !ownLyrics.isEmpty {
            let b = KIGenerationRequest(prompt: prompt, lyricsMode: .own, lyrics: ownLyrics, language: language, duration: duration,
                                        seed: 2026, quality: .balanced)
            try await make("B-eigener-text-gesang", request: b, lyrics: ownLyrics, caption: nil, engine: engine, title: "Teststück – eigener Text")
        }
    }

    private func make(_ name: String, request: KIGenerationRequest, lyrics: String, caption: String?, engine: KIEngine, title: String) async throws {
        XCTAssertNil(request.problem)
        let dir = out.appendingPathComponent(name, isDirectory: true)
        let t = Date()
        let r = try await engine.generate(params: request.engineParams(lyricsOverride: lyrics, captionOverride: caption), variations: 1,
                                          seeds: request.seed.map { [$0] }, saveDirectory: dir, usePlanning: true) { _, _ in }
        let flac = try XCTUnwrap(r.files.first?.url)
        log("\(name): \(Int(Date().timeIntervalSince(t))) s für \(Int(request.duration ?? 0)) s Musik, Startwert \(r.files.first?.seed ?? -1)")
        try lyrics.write(to: out.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)

        // MP3 mit dem Exporter der App (wie „In Bibliothek übernehmen“ in „Hinzufügen“)
        var meta = StudioMetadata(title: title, artist: "KI-Musik", genre: "Pop")
        meta.year = Calendar.current.component(.year, from: Date())
        let mp3 = out.appendingPathComponent(name + ".mp3")
        let result = try await AudioExporter().export(ExportRequest(input: flac, trim: nil, options: .defaults(for: .mp3), metadata: meta, output: mp3),
                                                      pause: nil) { _ in }
        log("\(name): MP3 \(result.output.lastPathComponent), \(ByteCountFormatter.string(fromByteCount: Int64((try? Data(contentsOf: mp3).count) ?? 0), countStyle: .file))")
        XCTAssertTrue(FileManager.default.fileExists(atPath: mp3.path))
    }
}
