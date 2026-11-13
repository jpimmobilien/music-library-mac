import Foundation
import MLCore
import MLStudio
#if canImport(Darwin)
import Darwin
#endif

/// Einrichtung der KI-Umgebung – nur auf ausdrücklichen Wunsch in der App, alles unter
/// `~/Library/Application Support/Music Library/KI-Musik`:
///
/// 1. `uv` (Paketverwaltung für Python, offizielle Veröffentlichung von Astral, SHA-256 geprüft)
/// 2. ACE-Step 1.5 – Quelltext in einem festen, geprüften Stand (`aceCommit`)
/// 3. Python 3.12 und die Pakete von ACE-Step (`uv sync`, ca. 1,2 GB)
/// 4. Modelle von Hugging Face (Grundpaket ca. 10,4 GB, weitere einzeln) – jeweils eigener Knopf
///
/// Danach läuft die Erzeugung ohne Netz. Nichts davon wird in die Musikbibliothek geschrieben.
public final class KIInstaller: @unchecked Sendable {
    /// Stand von ACE-Step 1.5, mit dem die App geprüft wurde (KI-Probe, docs/KI_MUSIK_MACHBARKEIT.md).
    public static let aceCommit = "ca1e85fe9430179831e6bc6be790c332190a3866"
    public static let uvVersion = "0.13.8"
    public static let pythonVersion = "3.12"

    public struct Paths: Sendable {
        public let base: URL
        public var uv: URL { base.appendingPathComponent("uv/uv") }
        public var aceRoot: URL { base.appendingPathComponent("ACE-Step-1.5", isDirectory: true) }
        public var python: URL { aceRoot.appendingPathComponent(".venv/bin/python") }
        public var checkpoints: URL { base.appendingPathComponent("Modelle", isDirectory: true) }
        public var engineDir: URL { base.appendingPathComponent("Engine", isDirectory: true) }
        public var engineScript: URL { engineDir.appendingPathComponent("engine.py") }
        public var downloadScript: URL { engineDir.appendingPathComponent("download.py") }
        public var log: URL { base.appendingPathComponent("ki-musik.log") }
        public var state: URL { base.appendingPathComponent("installation.json") }
        var pythonInstalls: URL { base.appendingPathComponent("python", isDirectory: true) }
        var cache: URL { base.appendingPathComponent("cache", isDirectory: true) }

        public init(base: URL) { self.base = base }
    }

    /// Gespeicherter Stand der Einrichtung.
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
        public var aceCommit: String?
        public var uvVersion: String?
        public var environmentDate: Date?
        public var models: [String: Model] = [:]

        public init() {}
    }

    public struct Progress: Sendable, Equatable {
        public var step: String
        /// 0 … 1, nil = unbestimmt
        public var fraction: Double?
        public init(step: String, fraction: Double?) {
            self.step = step
            self.fraction = fraction
        }
    }

    public let paths: Paths
    /// Ordner mit `engine.py` und `download.py` (im App-Paket unter Resources/KIEngine).
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

    /// Python-Umgebung mit ACE-Step vorhanden (geprüfter Stand).
    public var environmentReady: Bool {
        let s = loadState()
        return s.aceCommit == Self.aceCommit && FileManager.default.isExecutableFile(atPath: paths.python.path)
            && FileManager.default.fileExists(atPath: paths.aceRoot.appendingPathComponent("acestep/inference.py").path)
    }

    /// Modell vollständig vorhanden (Gewichte in allen Teilen).
    public func isInstalled(_ model: KIModel) -> Bool {
        let fm = FileManager.default
        func hasWeights(_ dir: URL) -> Bool {
            guard let items = try? fm.contentsOfDirectory(atPath: dir.path) else { return false }
            return items.contains { $0.hasSuffix(".safetensors") || $0.hasSuffix(".bin") }
        }
        if model.id == KIModel.core.id {
            return ["acestep-v15-turbo", "vae", "Qwen3-Embedding-0.6B", "acestep-5Hz-lm-1.7B"].allSatisfy {
                hasWeights(paths.checkpoints.appendingPathComponent($0))
            } && loadState().models[model.id] != nil
        }
        if model.id == KIModel.lmMedium.id { return isInstalled(.core) }
        return hasWeights(paths.checkpoints.appendingPathComponent(model.id)) && loadState().models[model.id] != nil
    }

    /// Freier Platz auf dem Laufwerk der KI-Umgebung in Bytes.
    public func freeSpace() -> Int64? {
        let probe = FileManager.default.fileExists(atPath: paths.base.path) ? paths.base : paths.base.deletingLastPathComponent()
        let v = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage
    }

    /// Belegter Platz (Umgebung bzw. Modelle) in Bytes.
    public static func size(of dir: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in e {
            let v = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if v?.isRegularFile == true { total += Int64(v?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }

    // MARK: Umgebung einrichten

    /// Benötigter freier Platz für die Umgebung (Python, Pakete, Zwischenspeicher).
    public static let environmentBytes: Int64 = 2_500_000_000

    public func installEnvironment(progress: @escaping @Sendable (Progress) -> Void) async throws {
        try begin()
        defer { end() }
        let fm = FileManager.default
        try fm.createDirectory(at: paths.base, withIntermediateDirectories: true)
        if let free = freeSpace(), free < Self.environmentBytes {
            throw StudioError.other("Zu wenig freier Speicher: Für die KI-Umgebung werden etwa \(KIFormat.bytes(Self.environmentBytes)) gebraucht, frei sind \(KIFormat.bytes(free)).")
        }
        try installScripts()
        let staging = paths.base.appendingPathComponent(".install-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        // 1. uv
        if !(fm.isExecutableFile(atPath: paths.uv.path) && loadState().uvVersion == Self.uvVersion) {
            try await installUV(staging: staging, progress: progress)
        }
        try Task.checkCancellation()

        // 2. ACE-Step (fester Stand)
        if !(loadState().aceCommit == Self.aceCommit && fm.fileExists(atPath: paths.aceRoot.appendingPathComponent("pyproject.toml").path)) {
            try await installACE(staging: staging, progress: progress)
        }
        try Task.checkCancellation()

        // 3. Python und Pakete
        progress(Progress(step: "Python \(Self.pythonVersion) und Pakete werden eingerichtet … (ca. 1,2 GB, einige Minuten)", fraction: 0.3))
        let lines = LineCounter()
        let sync = try await StudioProcess.run(paths.uv.path, ["sync", "--python", Self.pythonVersion, "--no-progress"],
                                               environment: uvEnvironment(), currentDirectory: paths.aceRoot, timeout: 3600) { line, _ in
            let n = lines.increment()
            let text = line.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { progress(Progress(step: "Pakete: \(text.prefix(90))", fraction: min(0.95, 0.3 + Double(n) * 0.004))) }
        }
        guard sync.status == 0, !sync.timedOut else {
            let tail = (sync.stderr + sync.stdout).split(separator: "\n").suffix(3).joined(separator: " · ")
            throw StudioError.other("Die Python-Pakete konnten nicht eingerichtet werden. \(tail)")
        }

        // 4. Prüfen: lässt sich ACE-Step laden?
        progress(Progress(step: "Umgebung wird geprüft …", fraction: 0.97))
        let check = try await StudioProcess.run(paths.python.path, ["-I", "-c", "import torch, mlx.core, acestep.inference; print(torch.__version__)"],
                                                environment: pythonEnvironment(), currentDirectory: paths.aceRoot, timeout: 600)
        guard check.status == 0 else {
            let tail = check.stderr.split(separator: "\n").suffix(2).joined(separator: " · ")
            throw StudioError.other("Die KI-Umgebung ließ sich nicht starten. \(tail)")
        }
        var s = loadState()
        s.environmentDate = Date()
        try saveState(s)
        progress(Progress(step: "KI-Umgebung bereit", fraction: 1))
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
            progress(Progress(step: "uv wird geladen … \(KIFormat.bytes(done))", fraction: 0.01 + 0.08 * min(1, f)))
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

    private func installACE(staging: URL, progress: @escaping @Sendable (Progress) -> Void) async throws {
        progress(Progress(step: "ACE-Step 1.5 wird geladen …", fraction: 0.1))
        let url = URL(string: "https://codeload.github.com/ace-step/ACE-Step-1.5/tar.gz/\(Self.aceCommit)")!
        let file = staging.appendingPathComponent("ace.tar.gz")
        try await StudioHTTP.download(from: url, to: file, maxBytes: 600 * 1024 * 1024, timeout: 180) { done, _ in
            progress(Progress(step: "ACE-Step 1.5 wird geladen … \(KIFormat.bytes(done))", fraction: 0.12))
        }
        let out = staging.appendingPathComponent("ace-out", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let r = try await StudioProcess.run("/usr/bin/tar", ["-xzf", file.path, "-C", out.path], timeout: 600)
        guard r.status == 0 else { throw StudioError.other("ACE-Step konnte nicht entpackt werden.") }
        let items = try FileManager.default.contentsOfDirectory(at: out, includingPropertiesForKeys: nil)
        guard let root = items.first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("pyproject.toml").path) }) else {
            throw StudioError.other("Im Archiv von ACE-Step fehlt pyproject.toml.")
        }
        let fm = FileManager.default
        // Alte Umgebung (anderer Stand) ersetzen; Modelle liegen getrennt und bleiben.
        if fm.fileExists(atPath: paths.aceRoot.path) { try fm.removeItem(at: paths.aceRoot) }
        try fm.moveItem(at: root, to: paths.aceRoot)
        var s = loadState()
        s.aceCommit = Self.aceCommit
        s.environmentDate = nil
        try saveState(s)
        progress(Progress(step: "ACE-Step 1.5 entpackt", fraction: 0.28))
    }

    /// Skripte aus dem App-Paket in die Umgebung kopieren (bei jedem Start, damit Aktualisierungen der App greifen).
    public func installScripts() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: paths.engineDir, withIntermediateDirectories: true)
        for name in ["engine.py", "download.py"] {
            let src = scripts.appendingPathComponent(name)
            let dst = paths.engineDir.appendingPathComponent(name)
            guard fm.fileExists(atPath: src.path) else { throw StudioError.other("\(name) fehlt im App-Paket.") }
            if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
            try fm.copyItem(at: src, to: dst)
        }
    }

    // MARK: Modelle

    public func download(_ model: KIModel, progress: @escaping @Sendable (Progress) -> Void) async throws {
        try begin()
        defer { end() }
        guard environmentReady else { throw StudioError.other("Zuerst die KI-Umgebung einrichten.") }
        try installScripts()
        let dest = model.core ? paths.checkpoints : paths.checkpoints.appendingPathComponent(model.id, isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        if let need = model.bytes, let free = freeSpace(), free < need + 1_000_000_000 {
            throw StudioError.other("Zu wenig freier Speicher für „\(model.title)“: gebraucht etwa \(KIFormat.bytes(need)), frei \(KIFormat.bytes(free)).")
        }
        let total = Counter()
        let existing = Counter()
        let revision = Box<String>()
        let failure = Box<String>()
        progress(Progress(step: "\(model.title): Dateiliste wird geladen …", fraction: nil))
        var env = pythonEnvironment()
        env.removeValue(forKey: "HF_HUB_OFFLINE")
        let r = try await StudioProcess.run(paths.python.path, ["-I", paths.downloadScript.path, model.repo, dest.path],
                                            environment: env, currentDirectory: paths.base, timeout: 6 * 3600) { line, stream in
            guard stream == .stdout, let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { return }
            switch obj["event"] as? String {
            case "total":
                total.set((obj["bytes"] as? NSNumber)?.int64Value ?? 0)
                revision.set(obj["revision"] as? String ?? "")
            case "progress":
                let done = (obj["bytes"] as? NSNumber)?.int64Value ?? 0
                existing.set((obj["existing"] as? NSNumber)?.int64Value ?? 0)
                let t = total.value
                let have = min(t, done + existing.value)
                let fraction = t > 0 ? Double(have) / Double(t) : nil
                progress(Progress(step: "\(model.title): \(KIFormat.bytes(have)) von \(KIFormat.bytes(t))", fraction: fraction))
            case "error":
                failure.set(obj["message"] as? String ?? "")
            default:
                break
            }
        }
        guard r.status == 0, !r.timedOut else {
            let message = failure.value ?? r.stderr.split(separator: "\n").suffix(2).joined(separator: " · ")
            throw StudioError.other("„\(model.title)“ konnte nicht geladen werden. Ein erneuter Versuch setzt den Download fort. \(message)")
        }
        var s = loadState()
        s.models[model.id] = State.Model(revision: revision.value ?? "", bytes: Self.size(of: dest), date: Date())
        try saveState(s)
        progress(Progress(step: "\(model.title) geladen", fraction: 1))
    }

    /// Modell entfernen (das Grundpaket entfernt alle Modelle des Grundpakets, weitere Modelle bleiben).
    public func remove(_ model: KIModel) throws {
        let fm = FileManager.default
        if model.core {
            for name in ["acestep-v15-turbo", "vae", "Qwen3-Embedding-0.6B", "acestep-5Hz-lm-1.7B", ".cache", "README.md", "config.json"] {
                let p = paths.checkpoints.appendingPathComponent(name)
                if fm.fileExists(atPath: p.path) { try fm.removeItem(at: p) }
            }
        } else {
            let p = paths.checkpoints.appendingPathComponent(model.id)
            if fm.fileExists(atPath: p.path) { try fm.removeItem(at: p) }
        }
        var s = loadState()
        s.models[model.id] = nil
        try saveState(s)
    }

    /// Alles entfernen (Umgebung und Modelle). Kreationen liegen woanders und bleiben.
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
        env["PYTHONPATH"] = paths.aceRoot.path
        env["HF_HUB_OFFLINE"] = "1"
        env["HF_HUB_DISABLE_TELEMETRY"] = "1"
        env["ACESTEP_CHECKPOINTS_DIR"] = paths.checkpoints.path
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

    private final class LineCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func increment() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var v: Int64 = 0
        var value: Int64 { lock.lock(); defer { lock.unlock() }; return v }
        func set(_ x: Int64) { lock.lock(); v = x; lock.unlock() }
    }

    private final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var v: T?
        var value: T? { lock.lock(); defer { lock.unlock() }; return v }
        func set(_ x: T) { lock.lock(); v = x; lock.unlock() }
    }
}
