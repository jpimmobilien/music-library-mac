import Foundation
import AetherC
import AetherCore

/// SSD-Gesundheit über die öffentliche NVMe-SMART-Schnittstelle von IOKit (nur lesend, ohne Administratorrechte).
/// Externe Laufwerke über USB und SATA-SSDs haben diese Schnittstelle nicht – dann „nicht verfügbar“ mit Grund.
public enum SMARTSource {
    /// War die Schnittstelle im SDK beim Bauen vorhanden?
    public static var isSupportedByBuild: Bool { aether_nvme_supported() }

    /// Liest alle NVMe-Laufwerke (dauert wenige Millisekunden; nie im Hauptthread aufrufen).
    public static func read(at date: Date = Date(), isVirtualMachine: Bool) -> Reading<[NVMeDrive]> {
        guard aether_nvme_supported() else {
            return Reading(unavailable: .notProvidedByMacOS, source: .smartHealth, at: date)
        }
        let capacity: Int32 = 8
        var buffer = [AetherNVMeDrive](repeating: AetherNVMeDrive(), count: Int(capacity))
        let count = buffer.withUnsafeMutableBufferPointer { pointer -> Int in
            guard let base = pointer.baseAddress else { return 0 }
            return Int(aether_nvme_read_all(base, capacity))
        }
        guard count > 0 else {
            return Reading(unavailable: isVirtualMachine ? .virtualMachine : .notProvidedByMacOS, source: .smartHealth, at: date)
        }
        var drives: [NVMeDrive] = []
        for index in 0..<min(count, buffer.count) {
            var raw = buffer[index]
            let model = text(&raw.model)
            let firmware = text(&raw.firmware)
            let health: Reading<NVMeHealth>
            // Statuswerte siehe AetherC.h (AETHER_NVME_…)
            switch raw.status {
            case 0: // AETHER_NVME_OK
                let bytes = withUnsafeBytes(of: &raw.raw) { Array($0) }
                if let decoded = NVMeHealth.decode(bytes) {
                    health = Reading(decoded, source: .smartHealth, at: date)
                } else {
                    health = Reading(unavailable: .implausibleValue, source: .smartHealth, at: date)
                }
            case 4: // AETHER_NVME_NOT_PERMITTED
                health = Reading(unavailable: .requiresAdministrator, source: .smartHealth, at: date)
            case 1, 2: // AETHER_NVME_PLUGIN_FAILED, AETHER_NVME_INTERFACE_FAILED
                health = Reading(unavailable: .notProvidedByMacOS, source: .smartHealth, at: date)
            default:
                health = Reading(unavailable: .queryFailed, source: .smartHealth, at: date)
            }
            drives.append(NVMeDrive(index: index, model: model, firmware: firmware, health: health))
        }
        return Reading(drives, source: .smartHealth, at: date)
    }

    /// Nullterminierter C-Text aus einem Feld fester Länge.
    private static func text<T>(_ field: inout T) -> String? {
        let bytes = withUnsafeBytes(of: &field) { Array($0) }
        let end = bytes.firstIndex(of: 0) ?? bytes.count
        let value = String(decoding: bytes[..<end], as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}
