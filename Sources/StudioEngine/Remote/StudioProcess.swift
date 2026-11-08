import Foundation
import MLStudio
#if canImport(Darwin)
import Darwin
#endif

/// Ergebnis eines Hilfsprogramms (yt-dlp, Deno, ditto).
public struct StudioProcessResult: Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
    /// Das Zeitlimit wurde überschritten (Prozess wurde beendet).
    public var timedOut: Bool
}

/// Startet Hilfsprogramme ohne Shell, liest Ausgabe zeilenweise und beendet sie bei Abbruch zuverlässig:
/// erst SIGTERM an den ganzen Prozessbaum (yt-dlp_macos startet einen Python-Prozess, der wiederum FFmpeg
/// oder Deno starten kann), nach 2 s SIGKILL an alle, die noch laufen.
public enum StudioProcess {
    public enum Stream: Sendable { case stdout, stderr }

    /// Höchstmenge gesammelter Ausgabe je Datenstrom (Schutz vor unbegrenztem Speicherbedarf).
    static let maxCollected = 64 * 1024 * 1024

    /// Programm ausführen. Abbrechbar über Task-Abbruch (→ `StudioError.cancelled`).
    /// - Parameters:
    ///   - timeout: Zeitlimit in Sekunden (nil = keines); bei Überschreitung `timedOut = true`.
    ///   - onLine: jede vollständige Ausgabezeile (Hintergrund-Thread), z. B. für Fortschritt.
    public static func run(_ executable: String, _ arguments: [String], environment: [String: String]? = nil,
                           currentDirectory: URL? = nil, timeout: TimeInterval? = nil,
                           onLine: (@Sendable (String, Stream) -> Void)? = nil) async throws -> StudioProcessResult {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice
        let state = RunState(onLine: onLine)

        let eof = DispatchGroup()
        let exit = DispatchGroup()
        eof.enter()
        eof.enter()
        exit.enter()
        for (pipe, stream) in [(outPipe, Stream.stdout), (errPipe, Stream.stderr)] {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    if state.markEOF(stream) { eof.leave() }
                } else {
                    state.append(data, stream)
                }
            }
        }
        process.terminationHandler = { _ in exit.leave() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<StudioProcessResult, Error>) in
                do {
                    try process.run()
                } catch {
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    // Gruppen ausgleichen (eine „betretene“ DispatchGroup darf nicht freigegeben werden)
                    for s in [Stream.stdout, .stderr] where state.markEOF(s) { eof.leave() }
                    exit.leave()
                    let name = (executable as NSString).lastPathComponent
                    cont.resume(throwing: StudioError.other("„\(name)“ konnte nicht gestartet werden: \(error.localizedDescription)"))
                    return
                }
                ProcessRegistry.shared.add(process)
                if state.markStarted(process) {
                    // Abbruch kam vor dem Start an
                    ProcessKiller.terminate(process)
                }
                if let timeout {
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        if process.isRunning {
                            state.setTimedOut()
                            ProcessKiller.terminate(process)
                        }
                    }
                }
                let queue = DispatchQueue.global(qos: .utility)
                exit.notify(queue: queue) {
                    let finish: @Sendable () -> Void = {
                        guard state.claimFinish() else { return }
                        outPipe.fileHandleForReading.readabilityHandler = nil
                        errPipe.fileHandleForReading.readabilityHandler = nil
                        // Kam kein Dateiende (Enkelprozess hält die Ausgabe offen), die Gruppe trotzdem ausgleichen.
                        for s in [Stream.stdout, .stderr] where state.markEOF(s) { eof.leave() }
                        state.flush()
                        ProcessRegistry.shared.remove(process)
                        if state.isCancelled {
                            cont.resume(throwing: StudioError.cancelled)
                        } else {
                            cont.resume(returning: StudioProcessResult(status: process.terminationStatus, stdout: state.text(.stdout),
                                                                       stderr: state.text(.stderr), timedOut: state.isTimedOut))
                        }
                    }
                    // Enkelprozesse können die Ausgabe offen halten – höchstens 2 s auf das Ende warten.
                    eof.notify(queue: queue, execute: finish)
                    queue.asyncAfter(deadline: .now() + 2, execute: finish)
                }
            }
        } onCancel: {
            if let p = state.cancel() { ProcessKiller.terminate(p) }
        }
    }

    /// Umgebung für Hilfsprogramme: Apps aus dem Finder haben keinen sinnvollen PATH; UTF-8, keine Farben,
    /// keine Update-Prüfungen von Deno.
    public static func environment(extraPaths: [String] = []) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let existing = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        let all = (extraPaths + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"] + existing)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        env["PATH"] = all.joined(separator: ":")
        env["LC_ALL"] = "en_US.UTF-8"
        env["LANG"] = "en_US.UTF-8"
        env["PYTHONIOENCODING"] = "utf-8"
        env["PYTHONUTF8"] = "1"
        env["NO_COLOR"] = "1"
        env["DENO_NO_UPDATE_CHECK"] = "1"
        env["DENO_NO_PROMPT"] = "1"
        return env
    }

    /// Alle laufenden Hilfsprogramme beenden (beim Beenden der App).
    public static func terminateAll() {
        for p in ProcessRegistry.shared.all() { ProcessKiller.terminate(p, killAfter: 0.5) }
    }

    /// Anzahl laufender Hilfsprogramme (für Tests).
    public static var runningCount: Int { ProcessRegistry.shared.all().count }
}

/// Zustand eines Laufs (Ausgabe sammeln, Zeilen zerlegen, Abbruch) – von mehreren Threads benutzt.
private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private let onLine: (@Sendable (String, StudioProcess.Stream) -> Void)?
    private var data: [StudioProcess.Stream: Data] = [.stdout: Data(), .stderr: Data()]
    private var partial: [StudioProcess.Stream: Data] = [.stdout: Data(), .stderr: Data()]
    private var eofSeen: Set<StudioProcess.Stream> = []
    private var process: Process?
    private var cancelled = false
    private var timedOut = false
    private var finished = false

    init(onLine: (@Sendable (String, StudioProcess.Stream) -> Void)?) {
        self.onLine = onLine
    }

    func append(_ chunk: Data, _ stream: StudioProcess.Stream) {
        var lines: [String] = []
        lock.lock()
        if (data[stream]?.count ?? 0) < StudioProcess.maxCollected { data[stream]?.append(chunk) }
        if onLine != nil {
            var buffer = partial[stream] ?? Data()
            buffer.append(chunk)
            while let idx = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                let line = buffer[buffer.startIndex..<idx]
                if !line.isEmpty { lines.append(String(decoding: line, as: UTF8.self)) }
                buffer.removeSubrange(buffer.startIndex...idx)
            }
            partial[stream] = buffer
        }
        lock.unlock()
        if let onLine { lines.forEach { onLine($0, stream) } }
    }

    func flush() {
        var rest: [(String, StudioProcess.Stream)] = []
        lock.lock()
        for s in [StudioProcess.Stream.stdout, .stderr] {
            if let p = partial[s], !p.isEmpty { rest.append((String(decoding: p, as: UTF8.self), s)) }
            partial[s] = Data()
        }
        lock.unlock()
        if let onLine { rest.forEach { onLine($0.0, $0.1) } }
    }

    /// true beim ersten Ende eines Datenstroms.
    func markEOF(_ stream: StudioProcess.Stream) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return eofSeen.insert(stream).inserted
    }

    /// Prozess gestartet; true, wenn vorher schon abgebrochen wurde.
    func markStarted(_ p: Process) -> Bool {
        lock.lock(); defer { lock.unlock() }
        process = p
        return cancelled
    }

    /// Abbruch vormerken; liefert den laufenden Prozess (falls schon gestartet).
    func cancel() -> Process? {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        return process
    }

    func setTimedOut() { lock.lock(); timedOut = true; lock.unlock() }

    func claimFinish() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if finished { return false }
        finished = true
        return true
    }

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    var isTimedOut: Bool { lock.lock(); defer { lock.unlock() }; return timedOut }

    func text(_ stream: StudioProcess.Stream) -> String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data[stream] ?? Data(), as: UTF8.self)
    }
}

/// Laufende Prozesse (zum Beenden beim Schließen der App).
final class ProcessRegistry: @unchecked Sendable {
    static let shared = ProcessRegistry()
    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]

    func add(_ p: Process) { lock.lock(); processes[ObjectIdentifier(p)] = p; lock.unlock() }
    func remove(_ p: Process) { lock.lock(); processes[ObjectIdentifier(p)] = nil; lock.unlock() }
    func all() -> [Process] { lock.lock(); defer { lock.unlock() }; return Array(processes.values) }
}

/// Beendet einen Prozess samt Nachfahren: SIGTERM, nach `killAfter` Sekunden SIGKILL.
enum ProcessKiller {
    static func terminate(_ process: Process, killAfter: TimeInterval = 2) {
        let pid = process.processIdentifier
        guard pid > 0 else { return }
        // Nachfahren jetzt erfassen: nach dem Ende des Elternprozesses hängen sie an launchd.
        let tree = descendants(of: pid)
        let ownGroup = getpgid(pid) == pid
        signal(pid: pid, tree: tree, ownGroup: ownGroup, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + killAfter) {
            let alive = ([pid] + tree).filter { kill($0, 0) == 0 }
            guard !alive.isEmpty else { return }
            signal(pid: pid, tree: tree, ownGroup: ownGroup, SIGKILL)
        }
    }

    private static func signal(pid: pid_t, tree: [pid_t], ownGroup: Bool, _ sig: Int32) {
        for child in tree.reversed() { kill(child, sig) }
        if ownGroup { kill(-pid, sig) }
        kill(pid, sig)
    }

    /// Alle Nachfahren eines Prozesses (Breitensuche über die Prozesstabelle).
    static func descendants(of root: pid_t) -> [pid_t] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let stride = MemoryLayout<kinfo_proc>.stride
        let capacity = size / stride + 32
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
        size = capacity * stride
        let ok = procs.withUnsafeMutableBytes { buf in
            sysctl(&mib, u_int(mib.count), buf.baseAddress, &size, nil, 0) == 0
        }
        guard ok else { return [] }
        let count = min(size / stride, capacity)
        var children: [pid_t: [pid_t]] = [:]
        for i in 0..<count {
            let p = procs[i]
            children[p.kp_eproc.e_ppid, default: []].append(p.kp_proc.p_pid)
        }
        var result: [pid_t] = []
        var queue = [root]
        var seen: Set<pid_t> = [root]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            for c in children[current] ?? [] where c > 1 && seen.insert(c).inserted {
                result.append(c)
                queue.append(c)
            }
        }
        return result
    }
}
