import Foundation
import IOKit
import IOKit.ps
import AetherCore

/// Batterie: IOPowerSources (öffentlich, dokumentiert) und AppleSmartBattery (IORegistry, Schlüssel undokumentiert –
/// jeder Wert wird auf Typ und Plausibilität geprüft, sonst „nicht verfügbar“).
public enum BatterySource {
    public static func sample(at date: Date = Date()) -> BatterySnapshot {
        var percent: Reading<Int> = Reading(unavailable: .notPresent, source: .powerSources, at: date)
        var isCharging: Bool?
        var isCharged: Bool?
        var toEmpty: Reading<Int> = Reading(unavailable: .notPresent, source: .batteryTimeRemaining, at: date)
        var toFull: Reading<Int> = Reading(unavailable: .notPresent, source: .batteryTimeRemaining, at: date)
        var condition: String?
        var present = false
        var source: PowerSourceState = .unknown

        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() {
            if let providing = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String? {
                source = providing == "AC Power" ? .ac : (providing == "Battery Power" ? .battery : .unknown)
            }
            let list = (IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]) ?? []
            for item in list {
                guard let description = IOPSGetPowerSourceDescription(blob, item)?.takeUnretainedValue() as? [String: Any],
                      description["Type"] as? String == "InternalBattery" else { continue }
                present = (description["Is Present"] as? Bool) ?? true
                if let current = description["Current Capacity"] as? Int, let max = description["Max Capacity"] as? Int, max > 0 {
                    let value = Int((Double(current) / Double(max) * 100).rounded())
                    percent = (0...100).contains(value) ? Reading(value, source: .powerSources, at: date)
                                                         : Reading(unavailable: .implausibleValue, source: .powerSources, at: date)
                }
                isCharging = description["Is Charging"] as? Bool
                isCharged = description["Is Charged"] as? Bool
                condition = description["BatteryHealth"] as? String
                if let minutes = description["Time to Empty"] as? Int {
                    toEmpty = minutes >= 0 ? Reading(minutes, source: .batteryTimeRemaining, at: date)
                                           : Reading(unavailable: .awaitingSecondSample, source: .batteryTimeRemaining, at: date)
                }
                if let minutes = description["Time to Full Charge"] as? Int {
                    toFull = minutes >= 0 ? Reading(minutes, source: .batteryTimeRemaining, at: date)
                                          : Reading(unavailable: .awaitingSecondSample, source: .batteryTimeRemaining, at: date)
                }
                if let state = description["Power Source State"] as? String {
                    source = state == "AC Power" ? .ac : (state == "Battery Power" ? .battery : source)
                }
            }
        }

        var adapter: Reading<Int> = Reading(unavailable: .notPresent, source: .powerSources, at: date)
        if let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
           let watts = (details["Watts"] as? NSNumber)?.intValue, watts > 0 {
            adapter = Reading(watts, source: .powerSources, at: date)
        }

        // AppleSmartBattery: Zyklen, Kapazitäten (mAh), Spannung (mV), Strom (mA), Temperatur (1/100 °C)
        let unavailableReason: UnavailableReason = present ? .notProvidedByMacOS : .notPresent
        var cycles: Reading<Int> = Reading(unavailable: unavailableReason, source: .smartBattery, at: date)
        var design: Reading<Int> = Reading(unavailable: unavailableReason, source: .smartBattery, at: date)
        var full: Reading<Int> = Reading(unavailable: unavailableReason, source: .smartBattery, at: date)
        var health: Reading<Double> = Reading(unavailable: unavailableReason, source: .batteryHealth, at: date)
        var voltage: Reading<Double> = Reading(unavailable: unavailableReason, source: .smartBattery, at: date)
        var amperage: Reading<Double> = Reading(unavailable: unavailableReason, source: .smartBattery, at: date)
        var temperature: Reading<Double> = Reading(unavailable: unavailableReason, source: .batteryTemperature, at: date)

        if present, let smart = IORegistry.properties(ofFirst: "AppleSmartBattery") {
            if let value = IORegistry.int(smart, "CycleCount"), (0...20_000).contains(value) {
                cycles = Reading(value, source: .smartBattery, at: date)
            }
            let designValue = IORegistry.int(smart, "DesignCapacity").flatMap { (100...30_000).contains($0) ? $0 : nil }
            // Apple Silicon: „MaxCapacity“ ist ein Prozentwert, die mAh stehen in „AppleRawMaxCapacity“.
            let fullValue = (IORegistry.int(smart, "AppleRawMaxCapacity") ?? IORegistry.int(smart, "NominalChargeCapacity")
                             ?? IORegistry.int(smart, "MaxCapacity").flatMap { $0 > 200 ? $0 : nil })
                .flatMap { (50...30_000).contains($0) ? $0 : nil }
            if let designValue { design = Reading(designValue, source: .smartBattery, at: date) }
            if let fullValue { full = Reading(fullValue, source: .smartBattery, at: date) }
            if let designValue, let fullValue, let ratio = BatteryMath.health(fullCharge: fullValue, design: designValue) {
                health = Reading(ratio, source: .batteryHealth, at: date)
            }
            if let mv = IORegistry.int(smart, "Voltage"), (3_000...30_000).contains(mv) {
                voltage = Reading(Double(mv), source: .smartBattery, at: date)
            }
            if let raw = IORegistry.int64(smart, "InstantAmperage") ?? IORegistry.int64(smart, "Amperage") {
                let ma = BatteryMath.signedMilliamps(raw)
                if abs(ma) <= 20_000 { amperage = Reading(Double(ma), source: .smartBattery, at: date) }
            }
            if let raw = IORegistry.int(smart, "Temperature"), let celsius = BatteryMath.celsius(fromCentidegrees: raw) {
                temperature = Reading(celsius, source: .batteryTemperature, at: date)
            }
        }

        return BatterySnapshot(isPresent: present, percent: percent, isCharging: isCharging, isFullyCharged: isCharged,
                               powerSource: source, minutesToEmpty: toEmpty, minutesToFull: toFull, cycleCount: cycles,
                               designCapacity: design, fullChargeCapacity: full, computedHealth: health, voltage: voltage,
                               amperage: amperage, temperature: temperature, adapterWatts: adapter, systemCondition: condition)
    }
}

/// Grafikprozessoren: Systeminformationen (`system_profiler`, eigener Prozess) und Auslastung laut Grafiktreiber
/// (IORegistry „PerformanceStatistics“). Metal wird bewusst nicht befragt – siehe `DisplaysParser`.
public enum GPUSource {
    /// Einmal ermitteln (dauert etwa eine Sekunde; nie im Hauptthread).
    public static func devices(appleSilicon: Bool, timeout: TimeInterval = 25) -> [GPUDevice]? {
        guard let data = HardwareSource.run("/usr/sbin/system_profiler", ["SPDisplaysDataType", "-json", "-detailLevel", "mini"],
                                            timeout: timeout),
              var devices = DisplaysParser.gpus(fromJSON: data, appleSilicon: appleSilicon) else { return nil }
        // Apple Silicon: Kernzahl zusätzlich aus der IORegistry, falls die Systeminformationen sie nicht nennen
        if appleSilicon, let cores = IORegistry.property("gpu-core-count", ofAll: "AGXAccelerator")
            .compactMap({ ($0 as? NSNumber)?.intValue }).first(where: { $0 > 0 && $0 < 1_000 }) {
            for index in devices.indices where devices[index].hasUnifiedMemory && devices[index].coreCount == nil {
                devices[index].coreCount = cores
            }
        }
        return devices
    }

    /// Höchste vom Treiber gemeldete Geräteauslastung (0…1) – oder „nicht verfügbar“, wenn kein Treiber sie meldet.
    public static func utilization(at date: Date = Date()) -> Reading<Double> {
        let stats = IORegistry.property("PerformanceStatistics", ofAll: "IOAccelerator")
        var best: Int?
        for case let dictionary as [String: Any] in stats {
            for key in ["Device Utilization %", "GPU Activity(%)"] {
                if let value = (dictionary[key] as? NSNumber)?.intValue, (0...100).contains(value) {
                    best = max(best ?? 0, value)
                }
            }
        }
        guard let best else { return Reading(unavailable: .notProvidedByMacOS, source: .gpuStatistics, at: date) }
        return Reading(Double(best) / 100, source: .gpuStatistics, at: date)
    }
}
