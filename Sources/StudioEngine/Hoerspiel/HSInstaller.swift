import Foundation
import MLCore
import MLStudio

/// Einrichtung der Umgebung für „KI-Hörbücher“ – nur auf ausdrücklichen Wunsch, alles unter
/// `~/Library/Application Support/Music Library/KI-Hoerspiel`:
///
/// 1. `uv` (offizielle Veröffentlichung von Astral, SHA-256 geprüft)
/// 2. Python 3.12 und feste Paketstände aus `requirements.txt` (mlx-audio, mlx-lm, mlx-whisper …)
/// 3. Modelle von Hugging Face einzeln per Knopf (Zwischenspeicher unter `Modelle/`)
///
/// Danach läuft alles ohne Netz in einer Sandbox. Nichts davon wird in die Musikbibliothek geschrieben.
public final class HSInstaller: @unchecked Sendable {
    public static let uvVersion = KIInstaller.uvVersion
    public static let pythonVersion = "3.12"

    public struct Paths: Sendable {
        public let base: URL
        public var uv: URL { base.appendingPathComponent("uv/uv") }
        public var venv: URL { base.appendingPathComponent("Umgebung", isDirectory: true) }
        public var python: URL { venv.appendingPathComponent("bin/python") }
        /// Hugging-Face-Zwischenspeicher (HF_HOME).
        public var models: URL { base.appendingPathComponent("Modelle", isDirectory: true) }
        public var engineDir: URL { base.appendingPathComponent("Engine", isDirectory: true) }
        public var engineScript: URL { engineDir.appendingPathComponent("engine.py") }
        public var downloadScript: URL { engineDir.appendingPathComponent("download.py") }
        public var requirements: URL { engineDir.appendingPathComponent("requirements.txt") }
        public var log: URL { base.appendingPathComponent("ki-hoerspiel.log") }
        public var state: URL { base.appendingPathComponent("installation.json") }
        var pythonInstalls: URL { base.appendingPathComponent("python", isDirectory: true) }
        var cache: URL { base.appendingPathComponent("cache", isDirectory: true) }

        public init(base: URL) { self.base = base }

        /// Ordner eines Modells im Zwischenspeicher.
        public func modelFolder(_ repo: String) -> URL {
            models.appendingPathComponent("hub/models--" + repo.replacingOccurrences(of: "/", with: "--"), isDirectory: true)
        }
    }

    public struct State: Codable, Equatable, Sendable {
        public struct Model: Codable, Equatable, Sendable {
            public var revision: String
            public var bytes: Int64
            public var date: Date
            public init(revision: String, bytes: Int64, date: Date) {
                self.revision = revision
                self.bytes = bytes
                self.date = date
            }
        }
        /// Prüfsumme der installierten requirements.txt – ändert sie sich mit einer App-Version, wird neu eingerichtet.
        public var requirementsHash: String?
        public var uvVersion: String?
        public var environmentDate: Date?
        public var models: [String: Model] = [:]
        public init() {}
    }

    public typealias Progress = KIInstaller.Progress

    public let paths: Paths
    /// Ordner mit den Python-Skripten (im App-Paket unter Resources/HoerspielEngine).
    let scripts: URL
    private let lock = NSLock()
    private var busy = false

    public init(base: URL, scripts: URL) {
        self.paths = Paths(base: base)
        self.scripts = scripts
    }

    // MARK: Zustand

    public func loadState() -> State {
        guard let data = try? Data(contentsOf: paths.state), let s = try? JSONDecoder().decode(State.self, from: data) else { return State() }
        return s
    }

    func saveState(_ s: State) throws {
        try FileManager.default.createDirectory(at: paths.base, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(s).write(to: paths.state, options: .atomic)
    }

    /// Prüfsumme der mitgelieferten requirements.txt.
    public var bundledRequirementsHash: String? {
        try? ToolChecksum.sha256(of: scripts.appendingPathComponent("requirements.txt"))
    }

    public var environmentReady: Bool {
        let s = loadState()
        return s.environmentDate != nil && s.requirementsHash == bundledRequirementsHash
            && FileManager.default.isExecutableFile(atPath: paths.python.path)
    }

    public func isInstalled(_ model: HSModel) -> Bool {
        loadState().models[model.repo] != nil && FileManager.default.fileExists(atPath: paths.modelFolder(model.repo).path)
    }

    public func freeSpace() -> Int64? {
        let probe = FileManager.default.fileExists(atPath: paths.base.path) ? paths.base : paths.base.deletingLastPathComponent()
        let v = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage
    }

    // MARK: Umgebung

    public static let environmentBytes: Int64 = 2_000_000_000

    public func installEnvironment(progress: @escaping @Sendable (Progress) -> Void) async throws {
        try begin()
        defer { end() }
        let fm = FileManager.default
        try fm.createDirectory(at: paths.base, withIntermediateDirectories: true)
        if let free = freeSpace(), free < Self.environmentBytes {
            throw StudioError.other("Zu wenig freier Speicher: gebraucht etwa \(KIFormat.bytes(Self.environmentBytes)), frei \(KIFormat.bytes(free)).")
        }
        try installScripts()
        let staging = paths.base.appendingPathComponent(".install-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        if !(fm.isExecutableFile(atPath: paths.uv.path) && loadState().uvVersion == Self.uvVersion) {
            try await installUV(staging: staging, progress: progress)
        }
        try Task.checkCancellation()

        progress(Progress(step: "Python \(Self.pythonVersion) wird eingerichtet …", fraction: 0.15))
        if fm.fileExists(atPath: paths.venv.path) { try fm.removeItem(at: paths.venv) }
        let venv = try await StudioProcess.run(paths.uv.path, ["venv", "--python", Self.pythonVersion, "--no-progress", paths.venv.path],
                                               environment: uvEnvironment(), currentDirectory: paths.base, timeout: 1800)
        guard venv.status == 0 else {
            throw StudioError.other("Python konnte nicht eingerichtet werden. \(venv.stderr.split(separator: "\n").suffix(2).joined(separator: " · "))")
        }
        try Task.checkCancellation()

        progress(Progress(step: "Pakete werden eingerichtet … (ca. 1 GB, einige Minuten)", fraction: 0.25))
        let lines = KIInstallerLineCounter()
        let install = try await StudioProcess.run(paths.uv.path, ["pip", "install", "--python", paths.python.path, "--no-progress",
                                                                  "-r", paths.requirements.path],
                                                  environment: uvEnvironment(), currentDirectory: paths.base, timeout: 3600) { line, _ in
            let n = lines.increment()
            let text = line.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { progress(Progress(step: "Pakete: \(text.prefix(90))", fraction: min(0.95, 0.25 + Double(n) * 0.005))) }
        }
        guard install.status == 0, !install.timedOut else {
            let tail = (install.stderr + install.stdout).split(separator: "\n").suffix(3).joined(separator: " · ")
            throw StudioError.other("Die Python-Pakete konnten nicht eingerichtet werden. \(tail)")
        }

        progress(Progress(step: "Umgebung wird geprüft …", fraction: 0.97))
        let check = try await StudioProcess.run(paths.python.path, ["-I", "-c", "import mlx.core, mlx_audio, mlx_lm, mlx_whisper, scipy, soundfile; print(mlx.core.__version__)"],
                                                environment: pythonEnvironment(), currentDirectory: paths.engineDir, timeout: 600)
        guard check.status == 0 else {
            throw StudioError.other("Die Hörspiel-Umgebung ließ sich nicht starten. \(check.stderr.split(separator: "\n").suffix(2).joined(separator: " · "))")
        }
        var s = loadState()
        s.environmentDate = Date()
        s.requirementsHash = bundledRequirementsHash
        try saveState(s)
        try? fm.removeItem(at: paths.cache)
        progress(Progress(step: "Umgebung bereit", fraction: 1))
    }

    private func installUV(staging: URL, progress: @escaping @Sendable (Progress) -> Void) async throws {
        let asset = "uv-aarch64-apple-darwin.tar.gz"
        let base = "https://github.com/astral-sh/uv/releases/download/\(Self.uvVersion)/"
        progress(Progress(step: "uv \(Self.uvVersion): Prüfsumme wird geladen …", fraction: 0.01))
        let sums = try await StudioHTTP.data(from: URL(string: base + asset + ".sha256")!, maxBytes: 64 * 1024, timeout: 30)
        guard let expected = ToolChecksum.expected(in: String(decoding: sums, as: UTF8.self), for: asset) else {
            throw StudioError.other("Für uv wurde keine Prüfsumme gefunden. Aus Sicherheitsgründen wurde nichts installiert.")
        }
        let file = staging.appendingPathComponent(asset)
        try await StudioHTTP.download(from: URL(string: base + asset)!, to: file, maxBytes: 200 * 1024 * 1024, timeout: 120) { done, total in
            let f = total.map { Double(done) / Double(max($0, 1)) } ?? 0
            progress(Progress(step: "uv wird geladen … \(KIFormat.bytes(done))", fraction: 0.01 + 0.1 * min(1, f)))
        }
        try ToolChecksum.verify(file: file, expected: expected, name: "uv")
        let out = staging.appendingPathComponent("uv-out", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let r = try await StudioProcess.run("/usr/bin/tar", ["-xzf", file.path, "-C", out.path], timeout: 300)
        guard r.status == 0, let binary = StudioToolManager.findFile(named: "uv", in: out) else {
            throw StudioError.other("uv konnte nicht entpackt werden.")
        }
        try FileManager.default.createDirectory(at: paths.uv.deletingLastPathComponent(), withIntermediateDirectories: true)
        try StudioToolManager.replace(paths.uv, with: binary)
        var s = loadState()
        s.uvVersion = Self.uvVersion
        try saveState(s)
    }

    /// Skripte aus dem App-Paket in die Umgebung kopieren (bei jedem Start, damit Aktualisierungen greifen).
    public func installScripts() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: paths.engineDir, withIntermediateDirectories: true)
        let files = try fm.contentsOfDirectory(atPath: scripts.path).filter { $0.hasSuffix(".py") || $0 == "requirements.txt" }
        guard files.contains("engine.py"), files.contains("requirements.txt") else {
            throw StudioError.other("Die Hörspiel-Skripte fehlen im App-Paket.")
        }
        for name in files {
            let dst = paths.engineDir.appendingPathComponent(name)
            if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
            try fm.copyItem(at: scripts.appendingPathComponent(name), to: dst)
        }
    }

    // MARK: Modelle

    public func download(_ model: HSModel, progress: @escaping @Sendable (Progress) -> Void) async throws {
        try begin()
        defer { end() }
        guard environmentReady else { throw StudioError.other("Zuerst die Hörspiel-Umgebung einrichten.") }
        try installScripts()
        if let free = freeSpace(), free < model.bytes + 1_000_000_000 {
            throw StudioError.other("Zu wenig freier Speicher für „\(model.title)“: gebraucht etwa \(KIFormat.bytes(model.bytes)), frei \(KIFormat.bytes(free)).")
        }
        let total = HSBox<Int64>()
        let revision = HSBox<String>()
        let failure = HSBox<String>()
        progress(Progress(step: "\(model.title): Dateiliste wird geladen …", fraction: nil))
        var env = pythonEnvironment()
        env.removeValue(forKey: "HF_HUB_OFFLINE")
        let r = try await StudioProcess.run(paths.python.path, ["-I", paths.downloadScript.path, model.repo],
                                            environment: env, currentDirectory: paths.base, timeout: 6 * 3600) { line, stream in
            guard stream == .stdout, let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { return }
            switch obj["event"] as? String {
            case "total":
                total.set((obj["bytes"] as? NSNumber)?.int64Value ?? 0)
                revision.set(obj["revision"] as? String ?? "")
            case "progress":
                let done = (obj["bytes"] as? NSNumber)?.int64Value ?? 0
                let existing = (obj["existing"] as? NSNumber)?.int64Value ?? 0
                let t = total.value ?? 0
                let have = min(t, done + existing)
                progress(Progress(step: "\(model.title): \(KIFormat.bytes(have)) von \(KIFormat.bytes(t))",
                                  fraction: t > 0 ? Double(have) / Double(t) : nil))
            case "error":
                failure.set(obj["message"] as? String ?? "")
            default:
                break
            }
        }
        guard r.status == 0, !r.timedOut else {
            let message = failure.value ?? r.stderr.split(separator: "\n").suffix(2).joined(separator: " · ")
            throw StudioError.other("„\(model.title)“ konnte nicht geladen werden. Ein erneuter Versuch setzt fort. \(message)")
        }
        var s = loadState()
        s.models[model.repo] = State.Model(revision: revision.value ?? "", bytes: KIInstaller.size(of: paths.modelFolder(model.repo)), date: Date())
        try saveState(s)
        progress(Progress(step: "\(model.title) geladen", fraction: 1))
    }

    public func remove(_ model: HSModel) throws {
        let folder = paths.modelFolder(model.repo)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
        var s = loadState()
        s.models[model.repo] = nil
        try saveState(s)
    }

    /// Alles entfernen (Umgebung, Modelle). Produktionen und Stimmen liegen woanders und bleiben.
    public func removeEverything() throws {
        if FileManager.default.fileExists(atPath: paths.base.path) { try FileManager.default.removeItem(at: paths.base) }
    }

    // MARK: Hilfen

    func uvEnvironment() -> [String: String] {
        var env = StudioProcess.environment()
        env["UV_CACHE_DIR"] = paths.cache.path
        env["UV_PYTHON_INSTALL_DIR"] = paths.pythonInstalls.path
        env["UV_PYTHON_PREFERENCE"] = "only-managed"
        env["UV_NO_CONFIG"] = "1"
        env["UV_LINK_MODE"] = "copy"
        return env
    }

    public func pythonEnvironment() -> [String: String] {
        var env = StudioProcess.environment()
        env["PYTHONNOUSERSITE"] = "1"
        env["PYTHONPATH"] = paths.engineDir.path
        env["HF_HOME"] = paths.models.path
        env["HF_HUB_OFFLINE"] = "1"
        env["HF_HUB_DISABLE_TELEMETRY"] = "1"
        return env
    }

    private func begin() throws {
        lock.lock(); defer { lock.unlock() }
        if busy { throw StudioError.other("Es läuft bereits eine Einrichtung.") }
        busy = true
    }

    private func end() {
        lock.lock(); busy = false; lock.unlock()
    }
}

final class KIInstallerLineCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func increment() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
}

final class HSBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var v: T?
    var value: T? { lock.lock(); defer { lock.unlock() }; return v }
    func set(_ x: T) { lock.lock(); v = x; lock.unlock() }
}
