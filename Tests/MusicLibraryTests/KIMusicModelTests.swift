import XCTest
import MLStudio
import StudioEngine
@testable import MusicLibrary

/// Rechenprozess-Ersatz: schreibt kleine Dateien statt Musik zu erzeugen, kann festhalten und scheitern.
final class FakeKIEngine: KIEngineServing, @unchecked Sendable {
    private let lock = NSLock()
    private var running = false
    private(set) var prepared: [(dit: String, lm: String?)] = []
    private(set) var generated: [[String: KIValue]] = []
    private(set) var lyricsCalls = 0
    var fail: String?
    var hold = false
    var shutdowns = 0

    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    func prepare(dit: String, lm: String?, progress: @escaping @Sendable (Double, String) -> Void) async throws {
        lock.lock(); running = true; prepared.append((dit, lm)); lock.unlock()
        progress(1, "Bereit")
    }

    func writeLyrics(query: String, caption: String, lyrics: String, language: String?, instrumental: Bool,
                     progress: @escaping @Sendable (Double, String) -> Void) async throws -> KILyricsResult {
        lock.lock(); lyricsCalls += 1; lock.unlock()
        return KILyricsResult(caption: "German pop, female vocals", lyrics: "[Verse]\nDie Sonne sinkt am See", language: language)
    }

    func generate(params: [String: KIValue], variations: Int, seeds: [Int]?, saveDirectory: URL, usePlanning: Bool,
                  progress: @escaping @Sendable (Double, String) -> Void) async throws -> KIGenerationResult {
        lock.lock(); generated.append(params); lock.unlock()
        progress(0.5, "Generating …")
        while hold {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        if let fail { throw StudioError.other(fail) }
        try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        var files: [KIGeneratedFile] = []
        for i in 0..<variations {
            let url = saveDirectory.appendingPathComponent("\(UUID().uuidString).flac")
            try Data("FLAC\(i)".utf8).write(to: url)
            files.append(KIGeneratedFile(url: url, seed: (seeds?[i]) ?? 100 + i))
        }
        return KIGenerationResult(files: files, seconds: 12, planned: nil)
    }

    func shutdown() {
        lock.lock(); running = false; shutdowns += 1; lock.unlock()
    }
}

@MainActor
final class KIMusicModelTests: XCTestCase {
    private var temp: URL!

    override func setUp() async throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("KIMusicModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: temp)
    }

    /// Einrichtung nachbilden: Python, ACE-Step und Grundpaket „vorhanden“ (leere Platzhalter).
    private func readyInstaller() throws -> KIInstaller {
        let scripts = temp.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try Data("# engine".utf8).write(to: scripts.appendingPathComponent("engine.py"))
        try Data("# download".utf8).write(to: scripts.appendingPathComponent("download.py"))
        let inst = KIInstaller(base: temp.appendingPathComponent("KI", isDirectory: true), scripts: scripts)
        let fm = FileManager.default
        try fm.createDirectory(at: inst.paths.python.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: inst.paths.python.path, contents: Data(), attributes: [.posixPermissions: 0o755])
        try fm.createDirectory(at: inst.paths.aceRoot.appendingPathComponent("acestep"), withIntermediateDirectories: true)
        try Data().write(to: inst.paths.aceRoot.appendingPathComponent("acestep/inference.py"))
        for dir in ["acestep-v15-turbo", "vae", "Qwen3-Embedding-0.6B", "acestep-5Hz-lm-1.7B"] {
            let d = inst.paths.checkpoints.appendingPathComponent(dir)
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
            try Data().write(to: d.appendingPathComponent("model.safetensors"))
        }
        var state = KIInstaller.State()
        state.aceCommit = KIInstaller.aceCommit
        state.models[KIModel.core.id] = .init(revision: "abc1234", bytes: 1, date: Date())
        let enc = JSONEncoder()
        try fm.createDirectory(at: inst.paths.base, withIntermediateDirectories: true)
        try enc.encode(state).write(to: inst.paths.state)
        return inst
    }

    private func makeModel(engine: FakeKIEngine, installer: KIInstaller? = nil, support: KISupport = .supported(recommendedLM: "acestep-5Hz-lm-1.7B"))
        throws -> KIMusicModel {
        let defaults = UserDefaults(suiteName: "KIMusicModelTests-\(UUID().uuidString)")!
        return KIMusicModel(demo: false, support: support, installer: try installer ?? readyInstaller(), engine: engine,
                            creationsFolder: temp.appendingPathComponent("Kreationen", isDirectory: true), defaults: defaults)
    }

    private func waitUntil(_ what: String, timeout: TimeInterval = 10, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("Zeitüberschreitung: \(what)"); return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testSetupStates() throws {
        let engine = FakeKIEngine()
        let intel = try makeModel(engine: engine, support: .unsupported(reason: "Intel"))
        XCTAssertEqual(intel.setup, .unsupported("Intel"))

        let empty = KIInstaller(base: temp.appendingPathComponent("leer"), scripts: temp)
        let fresh = try makeModel(engine: engine, installer: empty)
        XCTAssertEqual(fresh.setup, .needsEnvironment)
        XCTAssertNotNil(fresh.blocker)

        let ready = try makeModel(engine: engine)
        XCTAssertEqual(ready.setup, .ready)
        XCTAssertTrue(ready.isInstalled(.core))
        XCTAssertTrue(ready.isInstalled(.lmMedium), "1.7B gehört zum Grundpaket")
        XCTAssertFalse(ready.isInstalled(.xlTurbo))
    }

    func testGenerateStoresCreationsOutsideLibrary() async throws {
        let engine = FakeKIEngine()
        let ki = try makeModel(engine: engine)
        ki.request = KIGenerationRequest(prompt: "Erstelle einen ruhigen Lo-Fi-Track mit Klavier", lyricsMode: .instrumental,
                                         duration: 60, seed: 7, variations: 2, quality: .balanced)
        XCTAssertNil(ki.blocker)
        ki.generate()
        await waitUntil("fertig") { !ki.isWorking && !ki.results.isEmpty }
        XCTAssertEqual(ki.results.count, 2)
        XCTAssertEqual(ki.results.map(\.title), ["Ruhigen Lo-Fi-Track mit Klavier (1)", "Ruhigen Lo-Fi-Track mit Klavier (2)"])
        XCTAssertEqual(ki.results.map(\.seed), [7, 8], "Startwerte für Varianten fortlaufend")
        XCTAssertEqual(ki.results.first?.kind, .instrumental)
        XCTAssertEqual(engine.prepared.first?.dit, "acestep-v15-turbo")
        XCTAssertEqual(engine.prepared.first?.lm, "acestep-5Hz-lm-1.7B")
        for c in ki.results { XCTAssertTrue(FileManager.default.fileExists(atPath: ki.url(of: c).path)) }
        // Arbeitsordner aufgeräumt, Index geschrieben, beim Neustart wieder da
        let items = try FileManager.default.contentsOfDirectory(atPath: ki.creationsFolder.path)
        XCTAssertFalse(items.contains { $0.hasPrefix(".arbeit-") })
        XCTAssertTrue(items.contains(".kreationen.json"))
        let again = try makeModel(engine: engine)
        XCTAssertEqual(again.creations.items.count, 2)
        XCTAssertEqual(ki.history.first, "Erstelle einen ruhigen Lo-Fi-Track mit Klavier")
    }

    func testAIWritesGermanLyricsWithoutTranslation() async throws {
        let engine = FakeKIEngine()
        let ki = try makeModel(engine: engine)
        ki.request = KIGenerationRequest(prompt: "Deutscher Popsong über einen Sommerabend", lyricsMode: .aiWrites, language: "de",
                                         duration: 120, quality: .balanced)
        ki.generate()
        await waitUntil("fertig") { !ki.isWorking && !ki.results.isEmpty }
        XCTAssertEqual(engine.lyricsCalls, 1)
        XCTAssertEqual(ki.lastLyrics, "[Verse]\nDie Sonne sinkt am See")
        let params = try XCTUnwrap(engine.generated.last)
        XCTAssertEqual(params["lyrics"], .string("[Verse]\nDie Sonne sinkt am See"))
        XCTAssertEqual(params["vocal_language"], .string("de"))
        XCTAssertEqual(ki.results.first?.kind, .song)
        XCTAssertEqual(ki.results.first?.language, "de")
    }

    func testFailureAndCancel() async throws {
        let engine = FakeKIEngine()
        let ki = try makeModel(engine: engine)
        ki.request = KIGenerationRequest(prompt: "Synthwave", lyricsMode: .instrumental, duration: 30, quality: .fast)
        engine.fail = "Das Musikmodell konnte nicht geladen werden."
        ki.generate()
        await waitUntil("Fehler") { if case .failed = ki.phase { return true }; return false }
        XCTAssertEqual(ki.phase, .failed("Das Musikmodell konnte nicht geladen werden."))
        XCTAssertTrue(ki.results.isEmpty)
        ki.dismissError()

        engine.fail = nil
        engine.hold = true
        ki.generate()
        await waitUntil("läuft") { !engine.generated.isEmpty && engine.generated.count == 2 }
        XCTAssertTrue(ki.isWorking)
        ki.cancelGeneration()
        XCTAssertEqual(ki.phase, .idle)
        XCTAssertGreaterThan(engine.shutdowns, 0, "Abbrechen beendet den Rechenprozess")
        engine.hold = false
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(ki.results.isEmpty)
    }

    func testBlockers() throws {
        let engine = FakeKIEngine()
        let ki = try makeModel(engine: engine)
        ki.request = KIGenerationRequest(prompt: "Orchester", lyricsMode: .instrumental, quality: .high)
        XCTAssertEqual(ki.blocker, "Für „Hohe Qualität“ das Musikmodell XL laden (Einstellungen → KI-Musik).")
        let small = try makeModel(engine: engine, support: .limited(recommendedLM: nil, reason: "8 GB"))
        small.request = KIGenerationRequest(prompt: "Orchester", lyricsMode: .aiWrites, quality: .fast)
        XCTAssertNotNil(small.blocker)
        small.request.lyricsMode = .instrumental
        XCTAssertNil(small.blocker, "Schnell + Instrumental geht ohne Sprachmodell")
    }

    func testCreationActions() async throws {
        let engine = FakeKIEngine()
        let ki = try makeModel(engine: engine)
        ki.request = KIGenerationRequest(prompt: "Akustikgitarre", lyricsMode: .instrumental, duration: 30, seed: 3, quality: .fast)
        ki.generate()
        await waitUntil("fertig") { !ki.results.isEmpty }
        let c = try XCTUnwrap(ki.results.first)
        ki.toggleFavorite(c)
        XCTAssertEqual(ki.creations.items.first?.favorite, true)
        XCTAssertEqual(ki.creations.filtered(.favorites).count, 1)
        ki.rename(c, to: "Mein Stück")
        XCTAssertEqual(ki.creations.items.first?.title, "Mein Stück")
        ki.request.prompt = "anders"
        ki.reuse(ki.creations.items[0], newVariation: false)
        XCTAssertEqual(ki.request.prompt, "Akustikgitarre")
        XCTAssertEqual(ki.request.seed, 3)
        ki.reuse(ki.creations.items[0], newVariation: true)
        XCTAssertNil(ki.request.seed)
        let file = ki.url(of: ki.creations.items[0])
        ki.delete(ki.creations.items[0])
        XCTAssertTrue(ki.creations.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "in den Papierkorb verschoben")
    }
}
