import XCTest
import MLStudio
@testable import StudioEngine

/// Ende-zu-Ende-Prüfung der KI-Musik mit echtem ACE-Step 1.5: Einrichtung über `KIInstaller` (uv, ACE-Step,
/// Python-Pakete, Modelle von Hugging Face), dann Erzeugen über `KIEngine` in einer Sandbox ohne Netzwerk.
/// Läuft nur mit `KI_E2E=1` (Prüfstand „KI-E2E“ auf einem Apple-Silicon-Rechner; lädt rund 12 GB).
/// `KI_E2E_BASE`: Ordner für Umgebung und Modelle, `KI_E2E_OUT`: Ordner für die erzeugten Dateien.
final class KIEngineE2ETests: XCTestCase {
    private var enabled: Bool { ProcessInfo.processInfo.environment["KI_E2E"] == "1" }
    private var base: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["KI_E2E_BASE"] ?? NSTemporaryDirectory() + "ki-e2e", isDirectory: true)
    }
    private var out: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["KI_E2E_OUT"] ?? NSTemporaryDirectory() + "ki-e2e-out", isDirectory: true)
    }
    private var scripts: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/KIEngine", isDirectory: true)
    }
    /// Sprachmodell für den Prüfstand (virtuelle Rechner haben 7 GB Arbeitsspeicher).
    private var lm: String { ProcessInfo.processInfo.environment["KI_E2E_LM"] ?? KIModel.lmSmall.id }

    private func log(_ text: String) {
        print("[KI-E2E] \(text)")
    }

    private func installer() -> KIInstaller { KIInstaller(base: base, scripts: scripts) }

    func test1_InstallEnvironmentAndModels() async throws {
        try XCTSkipUnless(enabled, "nur im Prüfstand KI-E2E")
        let inst = installer()
        let t0 = Date()
        let last = Last()
        try await inst.installEnvironment { p in last.set(p.step) }
        log("Umgebung: \(Int(Date().timeIntervalSince(t0))) s – \(last.value)")
        XCTAssertTrue(inst.environmentReady)
        XCTAssertEqual(inst.loadState().aceCommit, KIInstaller.aceCommit)

        // Zweiter Aufruf: nichts mehr zu laden, Umgebung bleibt
        let t1 = Date()
        try await inst.installEnvironment { _ in }
        log("Umgebung erneut (sollte schnell sein): \(Int(Date().timeIntervalSince(t1))) s")

        let t2 = Date()
        let fractions = Fractions()
        try await inst.download(.core) { p in if let f = p.fraction { fractions.add(f) } }
        log("Grundpaket: \(Int(Date().timeIntervalSince(t2))) s, Fortschritt bis \(fractions.max)")
        XCTAssertTrue(inst.isInstalled(.core))
        XCTAssertGreaterThan(fractions.max, 0.9)
        if lm == KIModel.lmSmall.id {
            try await inst.download(.lmSmall) { _ in }
            XCTAssertTrue(inst.isInstalled(.lmSmall))
        }
        let state = inst.loadState()
        log("Modelle: " + state.models.map { "\($0.key) \(ByteCountFormatter.string(fromByteCount: $0.value.bytes, countStyle: .file)) @\($0.value.revision.prefix(7))" }.joined(separator: ", "))
    }

    func test2_SandboxBlocksNetwork() async throws {
        try XCTSkipUnless(enabled, "nur im Prüfstand KI-E2E")
        let inst = installer()
        try XCTSkipUnless(inst.environmentReady, "Umgebung fehlt (test1)")
        let code = "import urllib.request\ntry:\n    urllib.request.urlopen('https://huggingface.co', timeout=10)\n    print('NETZ')\nexcept Exception as e:\n    print('GESPERRT', type(e).__name__)"
        let r = try await StudioProcess.run("/usr/bin/sandbox-exec", ["-p", KIEngineClient.noNetworkProfile, inst.paths.python.path, "-I", "-c", code],
                                            environment: inst.pythonEnvironment(), timeout: 60)
        log("Sandbox: \(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
        XCTAssertTrue(r.stdout.contains("GESPERRT"), "In der Sandbox darf keine Verbindung ins Netz gelingen")
    }

    func test3_GenerateOfflineInSandbox() async throws {
        try XCTSkipUnless(enabled, "nur im Prüfstand KI-E2E")
        let inst = installer()
        try XCTSkipUnless(inst.environmentReady && inst.isInstalled(.core), "Umgebung oder Modelle fehlen (test1)")
        try inst.installScripts()
        let engine = KIEngine(installer: inst, denyNetwork: true)
        defer { engine.shutdown() }
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        var t = Date()
        try await engine.prepare(dit: "acestep-v15-turbo", lm: lm) { _, _ in }
        log("Laden: \(Int(Date().timeIntervalSince(t))) s")

        // 1. Instrumental, englische Beschreibung, ohne Planung (schnell)
        var req = KIGenerationRequest(prompt: "Calm lo-fi hip hop with warm piano chords and a relaxed drum groove", lyricsMode: .instrumental,
                                      duration: 20, bpm: 80, seed: 1234, quality: .fast)
        t = Date()
        var r = try await engine.generate(params: req.engineParams(), variations: 1, seeds: [1234],
                                          saveDirectory: out.appendingPathComponent("01-instrumental-en"), usePlanning: false) { _, _ in }
        log("01 Instrumental (20 s Musik): \(Int(Date().timeIntervalSince(t))) s, Datei \(r.files.first?.url.lastPathComponent ?? "-")")
        XCTAssertEqual(r.files.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: r.files[0].url.path))

        // 2. Deutsche Beschreibung, mit Planung durch das Sprachmodell, zwei Varianten
        req = KIGenerationRequest(prompt: "Ruhiges Lo-Fi-Stück mit warmem Klavier und entspanntem Schlagzeug", lyricsMode: .instrumental,
                                  duration: 20, seed: 77, variations: 2, quality: .balanced)
        t = Date()
        r = try await engine.generate(params: req.engineParams(), variations: 2, seeds: [77, 78],
                                      saveDirectory: out.appendingPathComponent("02-instrumental-de-varianten"), usePlanning: true) { _, _ in }
        log("02 Deutsch, 2 Varianten: \(Int(Date().timeIntervalSince(t))) s")
        XCTAssertEqual(r.files.count, 2)

        // 3. KI schreibt deutschen Text, dann Gesang auf Deutsch
        t = Date()
        let written = try await engine.writeLyrics(query: "Ein fröhlicher deutscher Popsong über einen Sommerabend am See", caption: "",
                                                   lyrics: "", language: "de", instrumental: false) { _, _ in }
        log("03 Text (\(Int(Date().timeIntervalSince(t))) s): \(written.lyrics.prefix(240).replacingOccurrences(of: "\n", with: " / "))")
        XCTAssertFalse(written.lyrics.isEmpty)
        try written.lyrics.write(to: out.appendingPathComponent("03-text-de.txt"), atomically: true, encoding: .utf8)
        req = KIGenerationRequest(prompt: written.caption.isEmpty ? "German pop song, female vocals, acoustic guitar" : written.caption,
                                  lyricsMode: .own, lyrics: written.lyrics, language: "de", duration: 30, seed: 42, quality: .balanced)
        t = Date()
        r = try await engine.generate(params: req.engineParams(), variations: 1, seeds: [42],
                                      saveDirectory: out.appendingPathComponent("03-gesang-de"), usePlanning: true) { _, _ in }
        log("03 Gesang Deutsch (30 s): \(Int(Date().timeIntervalSince(t))) s")
        XCTAssertEqual(r.files.count, 1)
    }

    func test4_CancelAndRecover() async throws {
        try XCTSkipUnless(enabled, "nur im Prüfstand KI-E2E")
        let inst = installer()
        try XCTSkipUnless(inst.environmentReady && inst.isInstalled(.core), "Umgebung oder Modelle fehlen (test1)")
        try inst.installScripts()
        let engine = KIEngine(installer: inst)
        defer { engine.shutdown() }
        try await engine.prepare(dit: "acestep-v15-turbo", lm: nil) { _, _ in }
        XCTAssertTrue(engine.isRunning)
        let req = KIGenerationRequest(prompt: "Energetic synthwave", lyricsMode: .instrumental, duration: 120, quality: .fast)
        let task = Task {
            try await engine.generate(params: req.engineParams(), variations: 1, seeds: nil,
                                      saveDirectory: out.appendingPathComponent("04-abbruch"), usePlanning: false) { _, _ in }
        }
        try await Task.sleep(nanoseconds: 8_000_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Abbruch erwartet")
        } catch {
            log("Abbruch: \(error.localizedDescription)")
            XCTAssertEqual(error as? KIEngineClient.ClientError, .cancelled)
        }
        try await Task.sleep(nanoseconds: 4_000_000_000)
        XCTAssertFalse(engine.isRunning, "Prozess ist nach dem Abbruch beendet")
        // Danach läuft eine neue Anfrage (Prozess startet neu)
        try await engine.prepare(dit: "acestep-v15-turbo", lm: nil) { _, _ in }
        let ok = try await engine.generate(params: KIGenerationRequest(prompt: "Short piano motif", lyricsMode: .instrumental, duration: 10,
                                                                     seed: 5, quality: .fast).engineParams(),
                                           variations: 1, seeds: [5], saveDirectory: out.appendingPathComponent("04-danach"),
                                           usePlanning: false) { _, _ in }
        XCTAssertEqual(ok.files.count, 1)
    }

    func test5_ErrorsAreReported() async throws {
        try XCTSkipUnless(enabled, "nur im Prüfstand KI-E2E")
        let inst = installer()
        try XCTSkipUnless(inst.environmentReady, "Umgebung fehlt (test1)")
        try inst.installScripts()
        let engine = KIEngine(installer: inst)
        defer { engine.shutdown() }
        do {
            try await engine.prepare(dit: "gibt-es-nicht", lm: nil) { _, _ in }
            XCTFail("Fehler erwartet")
        } catch {
            log("Fehlermeldung: \(error.localizedDescription.prefix(200))")
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    private final class Last: @unchecked Sendable {
        private let lock = NSLock()
        private var v = ""
        var value: String { lock.lock(); defer { lock.unlock() }; return v }
        func set(_ s: String) { lock.lock(); v = s; lock.unlock() }
    }

    private final class Fractions: @unchecked Sendable {
        private let lock = NSLock()
        private var m = 0.0
        var max: Double { lock.lock(); defer { lock.unlock() }; return m }
        func add(_ f: Double) { lock.lock(); m = Swift.max(m, f); lock.unlock() }
    }
}
