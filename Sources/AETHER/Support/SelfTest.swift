import SwiftUI
import AppKit
import AetherCore
import AetherSystem

/// Selbsttest beim Start (`--selftest <Datei>`, nur Build-Pipeline): misst echte Werte auf dem Build-Rechner und
/// prüft, dass sie aus den angegebenen Quellen stammen und plausibel sind. Nicht verfügbare Werte sind kein Fehler,
/// solange sie mit Grund gemeldet werden – erfundene Ersatzwerte wären einer.
@MainActor
enum SelfTest {
    static func run(model: AppModel, output: URL) async {
        let started = Date()
        model.engine.loadStaticInfo()
        await model.engine.sampleNow(count: 3, spacing: 1.0)
        // system_profiler läuft im Hintergrund – kurz warten
        for _ in 0..<40 where !model.engine.system.profilerFinished {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        try? await Task.sleep(nanoseconds: 600_000_000)

        let engine = model.engine
        var checks: [[String: Any]] = []
        func check(_ name: String, _ passed: Bool, _ detail: String) {
            checks.append(["name": name, "ok": passed, "detail": detail])
        }

        // CPU
        let cpu = engine.cpu.snapshot
        if let usage = cpu?.total.value {
            check("cpu.total", (0...1).contains(usage.busy) && abs(usage.user + usage.system + usage.idle - 1) < 0.001,
                  "busy=\(usage.busy) user=\(usage.user) system=\(usage.system)")
        } else {
            check("cpu.total", false, "keine CPU-Auslastung nach 3 Messungen: \(cpu?.total.reason?.rawValue ?? "nil")")
        }
        check("cpu.cores", (cpu?.perCore.count ?? 0) == (engine.system.hardware.logicalCores ?? -1),
              "Kerne gemessen=\(cpu?.perCore.count ?? 0) logisch=\(engine.system.hardware.logicalCores ?? -1)")

        // Arbeitsspeicher
        let memory = engine.memory.snapshot
        if let b = memory?.breakdown.value {
            check("memory.breakdown", b.physical > 0 && b.used <= b.physical && b.used > 0,
                  "physisch=\(b.physical) belegt=\(b.used) app=\(b.app) fest=\(b.wired) komprimiert=\(b.compressed) cache=\(b.cached)")
        } else {
            check("memory.breakdown", false, "nicht verfügbar")
        }
        check("memory.pressure", memory?.pressure.value != nil || memory?.pressure.reason != nil,
              "Druck=\(memory?.pressure.value.map { "\($0.rawValue)" } ?? "n. v. (\(memory?.pressure.reason?.rawValue ?? "-"))")")
        check("memory.swap", memory?.swap.value != nil, "swap=\(memory?.swap.value.map { "\($0.used)/\($0.total)" } ?? "n. v.")")

        // Speicher
        let storage = engine.storage.snapshot
        let startup = storage?.startup
        check("storage.startup", startup != nil && (startup?.capacity ?? 0) > 0 && (startup?.effectiveAvailable ?? -1) >= 0,
              "Startvolume=\(startup?.name ?? "fehlt") Kapazität=\(startup?.capacity ?? 0) verfügbar=\(startup?.effectiveAvailable ?? 0) Volumes=\(storage?.volumes.count ?? 0)")
        check("storage.io", storage?.readRate.value != nil || storage?.readRate.reason != nil,
              "lesen=\(storage?.readRate.value.map { "\($0)" } ?? "n. v. (\(storage?.readRate.reason?.rawValue ?? "-"))")")

        // Netzwerk
        let network = engine.network.snapshot
        check("network.rates", network?.download.value != nil,
              "↓=\(network?.download.value.map { "\($0)" } ?? "n. v.") Schnittstellen=\(network?.activeInterfaces.joined(separator: ",") ?? "")")

        // Energie und Thermik – auf virtuellen Macs ohne Akku: sauber „nicht vorhanden“
        let battery = engine.power.battery
        let thermal = engine.power.thermal
        check("thermal.state", thermal?.state.value != nil, "Thermalstatus=\(thermal?.state.value.map { "\($0.rawValue)" } ?? "n. v.")")
        if let battery {
            if battery.isPresent {
                check("battery.present", battery.percent.value.map { (0...100).contains($0) } ?? false, "Ladestand=\(battery.percent.value ?? -1)")
            } else {
                check("battery.absent", battery.percent.value == nil && battery.cycleCount.value == nil,
                      "kein Akku – keine Ersatzwerte gemeldet")
            }
        } else {
            check("battery", false, "keine Batteriemessung")
        }

        // GPU
        let gpu = engine.gpu
        for _ in 0..<60 where !gpu.devicesLoaded {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        let isVirtual = engine.system.hardware.kind == .virtualMachine
        check("gpu.devices", gpu.devicesLoaded && !gpu.devicesFailed && (!gpu.devices.isEmpty || isVirtual),
              gpu.devices.isEmpty ? "keine GPU gemeldet (virtueller Mac: \(isVirtual), Abfrage fehlgeschlagen: \(gpu.devicesFailed))"
                                  : gpu.devices.map { "\($0.name) [\($0.kind.rawValue), \($0.metalSupport ?? "-"), Kerne \($0.coreCount.map { "\($0)" } ?? "-")]" }.joined(separator: ", "))
        check("gpu.utilization", gpu.utilization?.value != nil || gpu.utilization?.reason != nil,
              "Auslastung=\(gpu.utilization?.value.map { "\($0)" } ?? "n. v. (\(gpu.utilization?.reason?.rawValue ?? "-"))")")

        // Hardware
        let hw = engine.system.hardware
        check("hardware.model", hw.modelIdentifier != nil, "Modell=\(hw.modelIdentifier ?? "-") Name=\(hw.machineName ?? "-") Art=\(hw.kind.rawValue)")
        check("hardware.processor", hw.processor != nil, "Prozessor=\(hw.processor?.displayName ?? "-") AppleSilicon=\(hw.isAppleSilicon) Rosetta=\(hw.isTranslated)")
        #if arch(arm64)
        let processArch = "arm64"
        #else
        let processArch = "x86_64"
        #endif
        check("hardware.architecture", hw.isAppleSilicon || processArch == "x86_64",
              "Prozess=\(processArch) Mac=\(hw.isAppleSilicon ? "Apple Silicon" : "Intel")")

        // Lokalisierung
        let localizations = Bundle.main.localizations
        check("localization", localizations.contains("de") && localizations.contains("en"), localizations.sorted().joined(separator: ","))
        let germanBundle = Bundle.main.path(forResource: "de", ofType: "lproj").flatMap(Bundle.init(path:))
        let germanOverview = germanBundle?.localizedString(forKey: "Overview", value: nil, table: nil)
        check("localization.de", germanOverview == "Übersicht", "Overview → \(germanOverview ?? "fehlt")")

        // Fenster und Eigenverbrauch
        let windows = NSApp.windows.filter { $0.isVisible }
        check("window", !windows.isEmpty, "sichtbare Fenster=\(windows.count)")
        let own = engine.system.ownUsage

        let info = Bundle.main.infoDictionary ?? [:]
        let ok = checks.allSatisfy { ($0["ok"] as? Bool) == true }
        let result: [String: Any] = [
            "ok": ok,
            "version": info["CFBundleShortVersionString"] as? String ?? "",
            "build": info["CFBundleVersion"] as? String ?? "",
            "process": processArch,
            "translated": hw.isTranslated,
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "liquidGlass": LiquidGlass.isAvailable,
            "profiler": [
                "machineName": jsonValue(engine.system.profiler?.machineName),
                "chip": jsonValue(engine.system.profiler?.chip),
                "cores": jsonValue(engine.system.profiler?.totalCores),
            ] as [String: Any],
            "clusters": hw.clusters.map { "\($0.systemName):\($0.physicalCores)/\($0.logicalCores)" },
            "ownCPU": jsonValue(own?.cpu),
            "ownFootprint": jsonValue(own?.footprint),
            "seconds": Date().timeIntervalSince(started),
            "checks": checks,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: output)
        }
        for c in checks {
            print("\((c["ok"] as? Bool) == true ? "✓" : "✗") \(c["name"] ?? "") – \(c["detail"] ?? "")")
        }
    }
}

/// Optionaler Wert für JSON (`nil` → `null`).
func jsonValue(_ value: Any?) -> Any {
    value ?? NSNull()
}
