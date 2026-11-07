import Darwin
import Foundation
import AetherCore

/// Statische Hardware- und Systemangaben.
public enum HardwareSource {
    /// Schnell (nur sysctl) – sofort beim Start verfügbar.
    public static func basic() -> HardwareSummary {
        var summary = HardwareSummary()
        summary.modelIdentifier = Sysctl.string("hw.model")
        if let brand = Sysctl.string("machdep.cpu.brand_string") {
            summary.processor = ProcessorName.parse(brand)
        }
        // Läuft dieser Mac auf Apple Silicon – auch wenn dieser Prozess über Rosetta übersetzt wird?
        summary.isAppleSilicon = (Sysctl.int("hw.optional.arm64") ?? 0) == 1
        summary.isTranslated = (Sysctl.int("sysctl.proc_translated") ?? 0) == 1
        summary.physicalCores = Sysctl.int("hw.physicalcpu")
        summary.logicalCores = Sysctl.int("hw.logicalcpu")
        summary.physicalMemory = Sysctl.uint64("hw.memsize")
        summary.osVersion = Sysctl.string("kern.osproductversion") ?? {
            let v = ProcessInfo.processInfo.operatingSystemVersion
            return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        }()
        summary.osBuild = Sysctl.string("kern.osversion")
        if let boot = Sysctl.value("kern.boottime", initial: timeval()), boot.tv_sec > 0 {
            summary.bootTime = Date(timeIntervalSince1970: Double(boot.tv_sec) + Double(boot.tv_usec) / 1_000_000)
        }
        summary.clusters = clusters()
        summary.kind = DeviceKind.from(machineName: nil, modelIdentifier: summary.modelIdentifier)
        return summary
    }

    /// Kerncluster aus `hw.perflevelN` (Apple Silicon, macOS 12+). Intel: ein einheitlicher Cluster.
    public static func clusters() -> [CoreCluster] {
        if let levels = Sysctl.int("hw.nperflevels"), levels > 0 {
            var result: [CoreCluster] = []
            for index in 0..<levels {
                let prefix = "hw.perflevel\(index)."
                let name = Sysctl.string(prefix + "name") ?? ""
                guard let physical = Sysctl.int(prefix + "physicalcpu"), physical > 0 else { continue }
                result.append(CoreCluster(kind: CoreCluster.kind(forSystemName: name), systemName: name,
                                          physicalCores: physical, logicalCores: Sysctl.int(prefix + "logicalcpu") ?? physical))
            }
            if !result.isEmpty { return result }
        }
        if let physical = Sysctl.int("hw.physicalcpu"), physical > 0 {
            return [CoreCluster(kind: .uniform, systemName: "", physicalCores: physical,
                                logicalCores: Sysctl.int("hw.logicalcpu") ?? physical)]
        }
        return []
    }

    /// `system_profiler SPHardwareDataType -json -detailLevel mini` – „mini“ lässt persönliche Angaben wie die
    /// Seriennummer weg. Dauert etwa eine Sekunde; nie im Hauptthread aufrufen.
    public static func profiler(timeout: TimeInterval = 20) -> ProfilerHardware? {
        guard let data = run("/usr/sbin/system_profiler", ["SPHardwareDataType", "-json", "-detailLevel", "mini"], timeout: timeout) else {
            return nil
        }
        return ProfilerParser.hardware(fromJSON: data)
    }

    /// Startet ein Systemwerkzeug und liefert dessen Ausgabe (oder `nil` bei Fehler/Zeitüberschreitung).
    public static func run(_ path: String, _ arguments: [String], timeout: TimeInterval) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // Zeitüberschreitung: das Programm beenden, dann endet auch das Lesen der Ausgabe
        let watchdog = DispatchWorkItem { [process] in
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        guard process.terminationReason == .exit else { return nil }
        return process.terminationStatus == 0 ? data : nil
    }
}
