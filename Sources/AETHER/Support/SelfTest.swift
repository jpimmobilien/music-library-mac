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
        // Nicht jede macOS-Version meldet die Verschlüsselung – „nicht gemeldet“ ist ehrlich und kein Fehler.
        check("storage.encryption", startup != nil,
              "Verschlüsselung des Startvolumes gelesen: \(startup?.isEncrypted.map { $0 ? "ja" : "nein" } ?? "nicht gelesen")")
        // SSD-Gesundheit: entweder plausible SMART-Werte oder „nicht verfügbar“ mit Grund – nie Ersatzwerte.
        let smart = SMARTSource.read(isVirtualMachine: engine.system.hardware.isVirtualMachine)
        if let drives = smart.value {
            let ok = !drives.isEmpty && drives.allSatisfy { drive in
                drive.health.value.map { $0.isPlausible } ?? (drive.health.reason != nil)
            }
            var parts: [String] = []
            for drive in drives {
                let name = drive.model ?? "NVMe"
                if let h = drive.health.value {
                    let temperature = h.temperatureCelsius.map { String(Int($0)) } ?? "-"
                    parts.append("\(name): Abnutzung \(h.percentageUsed) %, Reserve \(h.availableSpare) %, Temperatur \(temperature) °C")
                } else {
                    parts.append("\(name): n. v. (\(drive.health.reason?.rawValue ?? "-"))")
                }
            }
            check("storage.smart", ok, parts.joined(separator: "; "))
        } else {
            check("storage.smart", smart.reason != nil,
                  "nicht verfügbar mit Grund: \(smart.reason?.rawValue ?? "fehlt") (SDK-Schnittstelle: \(SMARTSource.isSupportedByBuild ? "ja" : "nein"))")
        }

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

        // SMC-Sensoren und Lüfter: echte Werte müssen plausibel sein; sonst ein benannter Grund (virtueller Mac).
        if let thermal {
            if let sensors = thermal.sensors.value {
                let plausible = sensors.allSatisfy { SMCDecoder.plausibleTemperature($0.celsius) }
                check("thermal.smc", !sensors.isEmpty && plausible,
                      "Sensoren=\(sensors.count) heißester=\(thermal.hottest.map { "\($0.key) \($0.celsius)" } ?? "-")")
            } else {
                check("thermal.smc", thermal.sensors.reason != nil,
                      "nicht verfügbar mit Grund: \(thermal.sensors.reason?.rawValue ?? "fehlt")")
            }
            if let fans = thermal.fans.value {
                check("thermal.fans", fans.allSatisfy { $0.rpm >= 0 && $0.rpm < 20_000 },
                      "Lüfter=\(fans.count) " + fans.map { "\(Int($0.rpm)) U/min" }.joined(separator: ", "))
            } else {
                check("thermal.fans", thermal.fans.reason != nil, "nicht verfügbar mit Grund: \(thermal.fans.reason?.rawValue ?? "fehlt")")
            }
        }

        // Netzwerkdetails: Schnittstellen mit Adressen, Verbindungen aus netstat, WLAN plausibel oder nicht vorhanden
        let (interfaces, wifi, connections) = await Task.detached(priority: .utility) {
            (InterfaceInventory.read(), WiFiSource.sample(), ConnectionSource.sample())
        }.value
        check("network.interfaces", interfaces.contains { !$0.addresses.isEmpty },
              interfaces.filter(\.isConnected).map { "\($0.bsdName)(\($0.kind.rawValue)\($0.isPrimary ? ",primär" : ""))" }
                .joined(separator: " ") + " · gesamt=\(interfaces.count)")
        if let result = connections.value {
            var detail = "Sockets=\(result.connections.count) Prozessspalte=\(result.hasProcessColumn) mitProzess=\(result.connections.filter { $0.processName != nil }.count) "
                + result.connections.prefix(2).map { "\($0.proto) \($0.local.display) → \($0.remote.display) \($0.state?.rawValue ?? "-") \($0.processName ?? "?")" }
                    .joined(separator: "; ")
            if result.connections.isEmpty, let raw = HardwareSource.run("/usr/sbin/netstat", ["-anv", "-p", "tcp"], timeout: 8) {
                detail += " Rohausgabe: " + String(String(decoding: raw, as: UTF8.self).prefix(400))
            }
            check("network.connections", !result.connections.isEmpty, detail)
        } else {
            check("network.connections", false, "netstat nicht lesbar: \(connections.reason?.rawValue ?? "-")")
        }
        if let wifi {
            let plausible = !wifi.isAssociated || (wifi.rssi.map(WiFiNames.plausibleSignal) ?? false)
            check("network.wifi", plausible,
                  "an=\(wifi.isPoweredOn) verbunden=\(wifi.isAssociated) RSSI=\(wifi.rssi.map { String($0) } ?? "-") Rauschen=\(wifi.noise.map { String($0) } ?? "-") Kanal=\(wifi.channel.map { String($0) } ?? "-") Name=\(wifi.ssid == nil ? "nicht freigegeben" : "vorhanden")")
        } else {
            check("network.wifi", true, "keine WLAN-Schnittstelle (z. B. virtueller Mac) – als „nicht vorhanden“ gemeldet")
        }

        // Lokaler Verlauf: in einem Temp-Ordner schreiben, zurücklesen, löschen – der echte Verlauf bleibt unberührt.
        let historyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("aether-selftest-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("history.sqlite")
        do {
            let database = try HistoryDatabase(url: historyURL)
            let minute = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 / 60).rounded(.down) * 60)
            let sample = HistorySample(time: minute, cpuBusy: 0.25, memoryUsed: 0.5, pressure: 1, download: 1_234, upload: nil)
            let wrote = database.insertNow(sample)
            let back = database.samples(from: minute.addingTimeInterval(-60), to: minute.addingTimeInterval(60))
            database.close()
            let removed = HistoryDatabase.removeFiles(at: historyURL)
            try? FileManager.default.removeItem(at: historyURL.deletingLastPathComponent())
            check("history.database", wrote && back.count == 1 && back.first == sample && removed,
                  "geschrieben=\(wrote) gelesen=\(back.count) gleich=\(back.first == sample) entfernt=\(removed)")
        } catch {
            check("history.database", false, "Öffnen fehlgeschlagen: \(error)")
        }
        check("history.default-off", !engine.history.isRecording && !model.settings.historyEnabled,
              "Verlauf im Selbsttest aus (Standard: aus, nichts gespeichert)")

        // SMC-Lesepfad (auch auf virtuellen Macs, dort ohne Anzeige der nachgebildeten Werte)
        let smc = SMCSource().diagnostics()
        check("thermal.smc.path", !smc.opened || smc.keys > 0,
              "geöffnet=\(smc.opened) Schlüssel=\(smc.keys) Temperaturschlüssel=\(smc.temperatureKeys) Lüfter=\(smc.fans.map(String.init) ?? "-") virtuell=\(engine.system.hardware.isVirtualMachine)")

        // Systembericht: Abschnitte aus echten Werten, ohne Seriennummer
        let sections = HardwareReport.sections(system: engine.system, gpu: engine.gpu, storage: engine.storage, power: engine.power,
                                               displays: DisplayCatalog.current())
        let markdown = ReportFormatter.markdown(title: "AETHER", subtitle: "Selbsttest", columns: ("a", "b", "c"), sections: sections,
                                                includeSensitive: false, describe: { $0.provenance.rawValue })
        check("hardware.report", sections.contains { !$0.rows.isEmpty } && !sections.flatMap(\.rows).contains { $0.isSensitive },
              "Abschnitte=\(sections.filter { !$0.rows.isEmpty }.count) Zeichen=\(markdown.count) Bildschirme=\(DisplayCatalog.current().count)")

        // GPU
        let gpu = engine.gpu
        for _ in 0..<60 where !gpu.devicesLoaded {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        let isVirtual = engine.system.hardware.kind == .virtualMachine || engine.system.hardware.isVirtualMachine
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
            "systemReduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            "systemReduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            "virtualMachine": hw.isVirtualMachine,
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
