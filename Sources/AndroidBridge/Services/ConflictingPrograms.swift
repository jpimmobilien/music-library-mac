import Foundation
import AppKit

/// Programme, die Android-Telefone per MTP beanspruchen und Android Bridge damit blockieren können.
enum ConflictingPrograms {
    struct Program: Hashable {
        let name: String
        let pid: pid_t
        let bundleID: String?
    }

    /// Erkennung über Bundle-ID bzw. Namen (u. a. der unsichtbare „Android File Transfer Agent“,
    /// der jedes angeschlossene Telefon sofort übernimmt).
    private static let markers: [String] = [
        "android file transfer", "mtpagent", "mtpviewer", "openmtp", "macdroid", "handshaker",
        "smart switch", "smartswitch", "syncmate", "commander one", "dr.fone", "anytrans", "droid transfer",
    ]

    static func running() -> [Program] {
        let own = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.bundleIdentifier != own else { return nil }
            let name = app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? ""
            let haystack = (name + " " + (app.bundleIdentifier ?? "")).lowercased()
            guard markers.contains(where: { haystack.contains($0) }) else { return nil }
            return Program(name: name, pid: app.processIdentifier, bundleID: app.bundleIdentifier)
        }
    }

    /// Beendet die Programme (erst regulär, dann erzwungen) und den macOS-Fotodienst ptpcamerad.
    /// Gibt die Namen der beendeten Programme zurück.
    static func releaseAll() async -> [String] {
        let programs = running()
        for p in programs {
            NSRunningApplication(processIdentifier: p.pid)?.terminate()
        }
        if !programs.isEmpty { try? await Task.sleep(nanoseconds: 1_200_000_000) }
        for p in programs {
            if let app = NSRunningApplication(processIdentifier: p.pid), !app.isTerminated { app.forceTerminate() }
        }
        // macOS-Fotodienst (startet bei Bedarf selbst neu)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["-q", "ptpcamerad"]
        try? process.run()
        process.waitUntilExit()
        try? await Task.sleep(nanoseconds: 700_000_000)
        Diagnostics.shared.log(.usb, "Freigegeben: macOS-Fotodienst\(programs.isEmpty ? "" : " und " + programs.map(\.name).joined(separator: ", "))")
        return programs.map(\.name)
    }
}
