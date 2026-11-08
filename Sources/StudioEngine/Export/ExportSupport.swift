import Foundation
import MLStudio

/// Fortschritt höchstens ~10× pro Sekunde, nie rückwärts.
final class ProgressReporter: @unchecked Sendable {
    private let handler: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var lastTime: UInt64 = 0
    private var lastValue: Double = -1

    init(_ handler: @escaping @Sendable (Double) -> Void) {
        self.handler = handler
    }

    func report(_ value: Double, force: Bool = false) {
        let v = min(max(value.isFinite ? value : 0, 0), 1)
        let now = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        let due = force || now &- lastTime >= 100_000_000
        guard due, v >= lastValue, !(v == lastValue && !force) else { lock.unlock(); return }
        lastTime = now
        lastValue = v
        lock.unlock()
        handler(v)
    }
}

/// Abbruch und Anhalten zwischen zwei Blöcken.
struct JobControl {
    let pause: PauseGate?

    /// Wirft `StudioError.cancelled` bei Abbruch; wartet, solange angehalten ist.
    /// (Gewartet wird in kurzen Schritten statt mit `waitIfPaused()`, damit ein Abbruch auch im
    /// angehaltenen Zustand sofort greift.)
    func checkpoint() async throws {
        if Task.isCancelled { throw StudioError.cancelled }
        if let pause {
            while pause.isPaused {
                if Task.isCancelled { throw StudioError.cancelled }
                do {
                    try await Task.sleep(nanoseconds: 50_000_000)
                } catch {
                    throw StudioError.cancelled
                }
            }
        }
        if Task.isCancelled { throw StudioError.cancelled }
    }
}

/// Schreibt in eine versteckte temporäre Datei im Zielordner und benennt sie erst am Ende um.
/// Bei Fehler oder Abbruch bleibt nichts zurück.
final class AtomicOutput {
    let final: URL
    let temp: URL
    private(set) var committed = false

    init(final: URL) throws {
        self.final = final
        let dir = final.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw StudioError.encodeFailed("Der Zielordner kann nicht angelegt werden: \(error.localizedDescription)")
        }
        let base = String(final.deletingPathExtension().lastPathComponent.prefix(60))
        let ext = final.pathExtension.isEmpty ? "tmp" : final.pathExtension
        // Endung bleibt erhalten (TagLib erkennt das Format daran)
        temp = dir.appendingPathComponent(".\(base).studio-\(UUID().uuidString.prefix(8)).\(ext)")
    }

    deinit {
        if !committed { discard() }
    }

    /// Ersetzt die Zieldatei atomar (rename im selben Ordner).
    func commit() throws {
        if rename(temp.path, final.path) != 0 {
            let code = errno
            throw StudioError.encodeFailed("Die fertige Datei konnte nicht abgelegt werden: \(String(cString: strerror(code)))")
        }
        committed = true
    }

    func discard() {
        try? FileManager.default.removeItem(at: temp)
    }
}

extension TrimRange {
    /// Start/Ende in Sekunden für eine Datei mit `duration` (nil = unbekannt); Ende nil = Dateiende.
    func resolved(duration: Double?) -> (start: Double, end: Double?) {
        if let duration, duration > 0 {
            guard let t = clamped(to: duration) else { return (0, nil) }
            return (t.start, t.end >= duration - 0.0005 ? nil : t.end)
        }
        return (max(0, start), end > start ? end : nil)
    }
}
