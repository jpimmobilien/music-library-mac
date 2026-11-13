import Foundation
import AetherCore

// =============================================================================================
// Lokalisierung: Schlüssel = englischer Text, Übersetzungen in Resources/Localization/<Sprache>.lproj.
// Alle sichtbaren Texte laufen über `tr(…)`; tools/check_l10n.py prüft im Build, dass jeder Schlüssel übersetzt ist
// und die Platzhalter übereinstimmen.
// =============================================================================================

/// Lokalisierter Text.
func tr(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

/// Lokalisierter Text mit Platzhaltern (%@, %ld, %d).
func tr(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: tr(key), locale: Locale.current, arguments: arguments)
}

/// Formatierer in der Sprache der Oberfläche (nicht der Region), damit Zahl und Text zusammenpassen.
let fmt: ValueFormatter = {
    let language = Bundle.main.preferredLocalizations.first ?? "en"
    let region = Locale.current.region?.identifier ?? (language == "de" ? "DE" : "US")
    return ValueFormatter(locale: Locale(identifier: "\(language)_\(region)"))
}()

extension Provenance {
    var title: String {
        switch self {
        case .measured: return tr("Measured")
        case .computed: return tr("Computed")
        case .systemReported: return tr("Reported by macOS")
        case .estimated: return tr("Estimate")
        }
    }

    var explanation: String {
        switch self {
        case .measured: return tr("Read directly from a counter or sensor.")
        case .computed: return tr("Calculated by ORBIT from measured values.")
        case .systemReported: return tr("A classification or specification provided by macOS or the manufacturer.")
        case .estimated: return tr("An estimate by macOS that can change quickly.")
        }
    }
}

extension UnavailableReason {
    var explanation: String {
        switch self {
        case .awaitingSecondSample: return tr("Needs a second measurement – available in a moment.")
        case .notPresent: return tr("This Mac doesn’t have this component.")
        case .notProvidedByMacOS: return tr("macOS doesn’t provide this value to apps on this Mac.")
        case .requiresAdministrator: return tr("macOS only provides this value to programs with administrator rights. ORBIT deliberately doesn’t ask for them.")
        case .privateInterfaceOnly: return tr("Only available through private Apple interfaces, which ORBIT doesn’t use.")
        case .virtualMachine: return tr("This is a virtual Mac without physical sensors.")
        case .implausibleValue: return tr("The source answered, but the value wasn’t plausible, so it isn’t shown.")
        case .queryFailed: return tr("The query failed.")
        case .plannedLaterPhase: return tr("Coming in a later development phase.")
        case .disabledInSettings: return tr("Turned off in Settings.")
        }
    }
}

extension DataSource {
    /// Erklärung der Quelle in einem Satz.
    var explanation: String {
        switch id {
        case "cpu.ticks": return tr("Processing time counters of all cores; usage is the difference between two readings.")
        case "cpu.loadavg": return tr("Average number of runnable threads over 1, 5 and 15 minutes.")
        case "cpu.topology": return tr("Core counts and core types as reported by the kernel.")
        case "memory.vm": return tr("Kernel page counters, split the way Activity Monitor does.")
        case "memory.swap": return tr("Swap space used on the startup disk.")
        case "memory.pressure": return tr("The memory pressure level macOS itself reports.")
        case "thermal.state": return tr("The thermal state macOS reports. It’s a classification, not a temperature.")
        case "thermal.smc": return tr("Sensor values from the System Management Controller.")
        case "thermal.battery": return tr("Temperature reported by the battery’s own sensor.")
        case "thermal.fans": return tr("Fan speeds from the System Management Controller (read-only).")
        case "battery.profiler": return tr("Battery condition and maximum capacity as shown in System Information.")
        case "battery.iops": return tr("The power source information macOS provides to all apps.")
        case "battery.smart": return tr("Values reported by the battery controller.")
        case "battery.health": return tr("Full charge capacity divided by design capacity. Not identical to Apple’s “Maximum Capacity”.")
        case "battery.time": return tr("Remaining time estimated by macOS from the current consumption.")
        case "battery.power": return tr("Voltage multiplied by current.")
        case "storage.volumes": return tr("Capacity and free space of each volume, including space macOS can free up on demand.")
        case "storage.io": return tr("Read and write counters of all disks; the rate is the difference between two readings.")
        case "storage.smart": return tr("Health log the NVMe drive reports about itself (SMART), read through Apple’s public interface.")
        case "storage.purgeable": return tr("Space macOS can free up on demand: available for important use minus currently free.")
        case "storage.scan": return tr("Sum of the space the files of the analysed folder occupy on the disk.")
        case "storage.duplicates": return tr("Files with identical size and identical SHA-256 checksum. Hard links count once.")
        case "network.counters": return tr("Byte counters of the physical network interfaces (64 bit).")
        case "gpu.devices": return tr("Graphics processors as listed in System Information.")
        case "gpu.utilization": return tr("Utilization as reported by the graphics driver. Not every driver reports it.")
        case "hardware.sysctl": return tr("Hardware details reported by the kernel.")
        case "hardware.profiler": return tr("Hardware overview from System Information, without personal data.")
        case "software.os": return tr("macOS version and build number.")
        case "pulse": return tr("Fixed rules that only use measured values and system reports.")
        case "thermal.aggregate": return tr("Average and maximum of all sensors in an area, calculated by ORBIT.")
        case "battery.adapter": return tr("Details the connected power adapter reports to macOS.")
        case "hardware.displays": return tr("Connected displays as macOS reports them.")
        case "hardware.serial": return tr("The serial number stored in the Mac’s firmware. Only read when you ask for it.")
        case "software.uptime": return tr("Time since the last startup, from the kernel’s boot time.")
        case "network.interfaces": return tr("Network interfaces, their addresses and the interface of the default route as macOS reports them.")
        case "network.wifi": return tr("Signal, noise, channel and data rate of the Wi‑Fi interface. Passwords are never read.")
        case "network.wifi.snr": return tr("Signal-to-noise ratio: signal strength minus noise level.")
        case "network.connections": return tr("Open TCP and UDP sockets from the kernel’s tables, read via netstat. The process is the socket’s last owner.")
        case "history.local": return tr("One-minute averages ORBIT stores on this Mac only – only while history is turned on.")
        default: return ""
        }
    }
}
