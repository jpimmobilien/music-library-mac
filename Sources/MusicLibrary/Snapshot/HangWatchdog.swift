import Foundation

/// Fehlersuche in der Build-Pipeline (nur Vorschau- und Messmodus): Reagiert der Hauptthread länger nicht,
/// nimmt das Systemwerkzeug `sample` den eigenen Prozess auf. So zeigt ein Lauf, der hängen bleibt oder stark
/// ruckelt, in den Ergebnissen, *wo* die Zeit verloren geht.
enum HangWatchdog {
    static func start(outputDirectory: URL, threshold: TimeInterval = 6, maxSamples: Int = 3) {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let thread = Thread {
            var taken = 0
            while taken < maxSamples {
                let pong = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { pong.signal() }
                if pong.wait(timeout: .now() + threshold) == .success {
                    Thread.sleep(forTimeInterval: 1)
                    continue
                }
                // Hauptthread blockiert: aufnehmen, solange er nicht antwortet (höchstens `maxSamples` Mal)
                repeat {
                    taken += 1
                    let file = outputDirectory.appendingPathComponent("haenger-\(taken).txt")
                    print("[Wächter] Hauptthread reagiert seit über \(Int(threshold)) s nicht – Aufnahme \(file.lastPathComponent)")
                    fflush(stdout)
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
                    p.arguments = [String(ProcessInfo.processInfo.processIdentifier), "3", "-mayDie", "-file", file.path]
                    p.standardOutput = FileHandle.nullDevice
                    p.standardError = FileHandle.nullDevice
                    do {
                        try p.run()
                        p.waitUntilExit()
                    } catch {
                        print("[Wächter] sample nicht verfügbar: \(error)")
                        return
                    }
                } while taken < maxSamples && pong.wait(timeout: .now() + threshold) == .timedOut
            }
        }
        thread.name = "Hänger-Wächter"
        thread.qualityOfService = .utility
        thread.start()
    }
}
