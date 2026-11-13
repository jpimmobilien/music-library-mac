import Foundation
import MLStudio

/// Verbindung zum lokalen KI-Rechenprozess (`Resources/KIEngine/engine.py`): startet ihn bei Bedarf, schickt
/// Anfragen als JSON-Zeilen über stdin und liest Antworten und Fortschritt von stdout. Kein Netzwerk-Port.
///
/// Abbrechen bedeutet: Prozess beenden (ACE-Step hat keinen Abbruch mitten im Rechnen). Danach ist aller Speicher
/// frei; die nächste Anfrage startet den Prozess neu und lädt die Modelle erneut.
public final class KIEngineClient: @unchecked Sendable {
    public struct Configuration: Sendable {
        public var python: URL
        public var script: URL
        public var aceRoot: URL
        public var checkpoints: URL
        public var log: URL
        /// Prozess in einer Sandbox ohne Netzwerkzugriff starten (`sandbox-exec`): Die Erzeugung kann dann
        /// nachweislich nichts senden oder laden.
        public var denyNetwork: Bool

        public init(python: URL, script: URL, aceRoot: URL, checkpoints: URL, log: URL, denyNetwork: Bool = true) {
            self.python = python
            self.script = script
            self.aceRoot = aceRoot
            self.checkpoints = checkpoints
            self.log = log
            self.denyNetwork = denyNetwork
        }
    }

    public enum ClientError: LocalizedError, Equatable {
        case notRunning
        case crashed(String)
        case cancelled
        case engine(String)

        public var errorDescription: String? {
            switch self {
            case .notRunning: return "Der KI-Prozess läuft nicht."
            case .crashed(let detail): return "Der KI-Prozess wurde unerwartet beendet." + (detail.isEmpty ? "" : " (\(detail))")
            case .cancelled: return "Abgebrochen."
            case .engine(let message): return message
            }
        }
    }

    public typealias Progress = @Sendable (Double, String) -> Void

    static let sandboxExec = "/usr/bin/sandbox-exec"
    /// Alles erlaubt außer Verbindungen ins Netz (lokale Unix-Sockets, Dateien und Metal bleiben erlaubt).
    public static let noNetworkProfile = "(version 1)(allow default)(deny network-outbound (remote ip \"*:*\"))"

    private let config: Configuration
    private let lock = NSLock()
    private var process: Process?
    private var stdin: FileHandle?
    private var buffer = Data()
    private var pending: [String: (progress: Progress?, done: CheckedContinuation<[String: Any], Error>)] = [:]
    private var ready: CheckedContinuation<Void, Error>?
    private var cancelling = false
    private var lastStderr = ""
    private var logHandle: FileHandle?

    public init(_ config: Configuration) {
        self.config = config
    }

    deinit { stop() }

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return process?.isRunning == true
    }

    // MARK: Starten und Beenden

    /// Startet den Prozess, falls er nicht läuft, und wartet auf „ready“.
    public func start() async throws {
        if isRunning { return }
        let p = Process()
        // -I: isoliert (keine Benutzer-Pfade, kein Arbeitsverzeichnis im Suchpfad), -u: ungepuffert
        let pythonArgs = ["-I", "-u", config.script.path]
        if config.denyNetwork, FileManager.default.isExecutableFile(atPath: Self.sandboxExec) {
            p.executableURL = URL(fileURLWithPath: Self.sandboxExec)
            p.arguments = ["-p", Self.noNetworkProfile, config.python.path] + pythonArgs
        } else {
            p.executableURL = config.python
            p.arguments = pythonArgs
        }
        var env = ProcessInfo.processInfo.environment.filter { !$0.key.lowercased().contains("proxy") }
        env["KI_ACE_ROOT"] = config.aceRoot.path
        env["KI_CHECKPOINTS"] = config.checkpoints.path
        env["ACESTEP_CHECKPOINTS_DIR"] = config.checkpoints.path
        env["HF_HUB_OFFLINE"] = "1"
        env["TRANSFORMERS_OFFLINE"] = "1"
        env["HF_HUB_DISABLE_TELEMETRY"] = "1"
        env["PYTHONNOUSERSITE"] = "1"
        env["PYTHONPATH"] = config.aceRoot.path
        p.environment = env
        p.currentDirectoryURL = config.aceRoot
        // Hintergrund-Priorität: die Wiedergabe darf nicht leiden
        p.qualityOfService = .utility
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe

        try? FileManager.default.createDirectory(at: config.log.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: config.log.path) {
            FileManager.default.createFile(atPath: config.log.path, contents: nil)
        }
        let log = try? FileHandle(forWritingTo: config.log)
        _ = try? log?.seekToEnd()
        log?.write(Data("\n--- \(Date()) KI-Prozess startet ---\n".utf8))

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil; return }
            self?.received(data)
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil; return }
            self?.stderr(data)
        }
        p.terminationHandler = { [weak self] proc in self?.terminated(proc.terminationStatus) }

        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            lock.lock()
            ready = c
            process = p
            stdin = inPipe.fileHandleForWriting
            logHandle = log
            cancelling = false
            buffer = Data()
            lastStderr = ""
            lock.unlock()
            do {
                try p.run()
            } catch {
                lock.lock()
                ready = nil
                process = nil
                lock.unlock()
                c.resume(throwing: ClientError.crashed("Start fehlgeschlagen: \(error.localizedDescription)"))
            }
        }
    }

    /// Beendet den Prozess (laufende Anfragen enden mit `.cancelled`).
    public func stop() {
        lock.lock()
        let p = process
        cancelling = true
        lock.unlock()
        guard let p, p.isRunning else { return }
        p.terminate()
        // Nach 3 s hart beenden, falls Python hängt
        let pid = p.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if p.isRunning { kill(pid, SIGKILL) }
        }
    }

    // MARK: Anfragen

    /// Schickt eine Anfrage und wartet auf das Ergebnis. Fortschritt kommt auf einem Hintergrund-Thread.
    public func request(_ cmd: String, _ payload: [String: Any] = [:], progress: Progress? = nil) async throws -> [String: Any] {
        try await start()
        let id = UUID().uuidString
        var message = payload
        message["id"] = id
        message["cmd"] = cmd
        let data = try JSONSerialization.data(withJSONObject: message, options: [])
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<[String: Any], Error>) in
                lock.lock()
                guard let stdin, process?.isRunning == true else {
                    lock.unlock()
                    c.resume(throwing: ClientError.notRunning)
                    return
                }
                pending[id] = (progress, c)
                lock.unlock()
                stdin.write(data + Data("\n".utf8))
            }
        } onCancel: { [weak self] in
            self?.stop()
        }
    }

    // MARK: Lesen

    private func received(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var lines: [Data] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            lines.append(buffer[buffer.startIndex..<nl])
            buffer.removeSubrange(buffer.startIndex...nl)
        }
        lock.unlock()
        for line in lines { handle(line) }
    }

    private func handle(_ line: Data) {
        guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], let event = obj["event"] as? String else { return }
        lock.lock()
        if event == "ready", let r = ready {
            ready = nil
            lock.unlock()
            r.resume()
            return
        }
        guard let id = obj["id"] as? String, let entry = pending[id] else { lock.unlock(); return }
        switch event {
        case "progress":
            lock.unlock()
            entry.progress?((obj["value"] as? Double) ?? 0, (obj["text"] as? String) ?? "")
        case "result":
            pending[id] = nil
            lock.unlock()
            entry.done.resume(returning: obj)
        case "error":
            pending[id] = nil
            lock.unlock()
            entry.done.resume(throwing: ClientError.engine((obj["message"] as? String) ?? "Unbekannter Fehler"))
        default:
            lock.unlock()
        }
    }

    private func stderr(_ data: Data) {
        lock.lock()
        logHandle?.write(data)
        let text = String(decoding: data, as: UTF8.self)
        lastStderr = String((lastStderr + text).suffix(600))
        lock.unlock()
    }

    private func terminated(_ status: Int32) {
        lock.lock()
        let wasCancelled = cancelling
        let waiting = pending
        pending = [:]
        let r = ready
        ready = nil
        process = nil
        stdin = nil
        let detail = lastStderr.split(separator: "\n").last.map(String.init) ?? "Status \(status)"
        logHandle?.write(Data("--- KI-Prozess beendet (Status \(status)) ---\n".utf8))
        try? logHandle?.close()
        logHandle = nil
        lock.unlock()
        let error: ClientError = wasCancelled ? .cancelled : .crashed(detail)
        r?.resume(throwing: error)
        for (_, entry) in waiting { entry.done.resume(throwing: error) }
    }
}
