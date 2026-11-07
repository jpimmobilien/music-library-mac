import Foundation

// =============================================================================================
// SMC-Sensoren: Werte dekodieren und Sensoren Bereichen zuordnen. Die Zuordnung beruht auf öffentlich bekannten
// Erfahrungswerten (Apple dokumentiert die Schlüssel nicht) und wird in der App so gekennzeichnet.
// =============================================================================================

public enum SMCDecoder {
    /// Dekodiert einen SMC-Wert anhand seines Datentyps. Unbekannte Typen → `nil`.
    ///  - `flt `: 32-Bit-Gleitkomma, Little Endian (Apple Silicon)
    ///  - `spXY`: vorzeichenbehaftete Festkommazahl, Big Endian, Y (hex) Nachkommabits (z. B. sp78)
    ///  - `fpXY`: vorzeichenlose Festkommazahl, Big Endian, Y (hex) Nachkommabits (z. B. fpe2 bei Intel-Lüftern)
    ///  - `ui8 `, `ui16`, `ui32`, `si8 `, `si16`: ganze Zahlen, Big Endian
    public static func value(type: String, bytes: [UInt8]) -> Double? {
        let t = type.lowercased()
        if t.hasPrefix("flt"), bytes.count >= 4 {
            let bits = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
            let value = Double(Float(bitPattern: bits))
            return value.isFinite ? value : nil
        }
        if (t.hasPrefix("sp") || t.hasPrefix("fp")), t.count == 4, bytes.count >= 2 {
            let chars = Array(t)
            guard let fraction = Int(String(chars[3]), radix: 16) else { return nil }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            let divisor = Double(1 << fraction)
            return t.hasPrefix("sp") ? Double(Int16(bitPattern: raw)) / divisor : Double(raw) / divisor
        }
        switch t {
        case "ui8 ", "ui8": return bytes.first.map(Double.init)
        case "si8 ", "si8": return bytes.first.map { Double(Int8(bitPattern: $0)) }
        case "ui16": return bytes.count >= 2 ? Double((UInt16(bytes[0]) << 8) | UInt16(bytes[1])) : nil
        case "si16": return bytes.count >= 2 ? Double(Int16(bitPattern: (UInt16(bytes[0]) << 8) | UInt16(bytes[1]))) : nil
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double((UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3]))
        default: return nil
        }
    }

    /// Plausible Temperatur für einen echten Sensor (0 und negative Werte melden unbenutzte Sensoren).
    public static func plausibleTemperature(_ celsius: Double) -> Bool {
        celsius >= 5 && celsius <= 130
    }

    /// Typen, die als Temperatur infrage kommen.
    public static func isTemperatureType(_ type: String) -> Bool {
        let t = type.lowercased()
        return t.hasPrefix("sp") || t.hasPrefix("flt") || t == "fp88" || t == "fp79" || t == "fp6a"
    }
}

/// Bereich eines Sensors.
public enum SensorGroup: String, CaseIterable, Sendable, Codable {
    case cpu, gpu, memory, storage, battery, wireless, power, enclosure, other
}

public struct ThermalSensor: Sendable, Equatable, Identifiable {
    public var id: String { key }
    public var key: String
    public var group: SensorGroup
    /// Bekannte Bedeutung (Erfahrungswert) als Schlüssel für die Lokalisierung, sonst `nil`.
    public var meaning: String?
    public var celsius: Double

    public init(key: String, group: SensorGroup, meaning: String?, celsius: Double) {
        self.key = key
        self.group = group
        self.meaning = meaning
        self.celsius = celsius
    }
}

public struct FanReading: Sendable, Equatable, Identifiable {
    public var id: Int { index }
    public var index: Int
    public var rpm: Double
    public var minimum: Double?
    public var maximum: Double?
    public var target: Double?

    public init(index: Int, rpm: Double, minimum: Double?, maximum: Double?, target: Double?) {
        self.index = index
        self.rpm = rpm
        self.minimum = minimum
        self.maximum = maximum
        self.target = target
    }

    /// Anteil zwischen Minimum und Maximum (0…1), falls beide bekannt.
    public var fraction: Double? {
        guard let minimum, let maximum, maximum > minimum else { return nil }
        return min(1, max(0, (rpm - minimum) / (maximum - minimum)))
    }
}

public enum SensorCatalog {
    /// Bekannte Bedeutungen (Intel-Macs, seit Jahren stabil) – Schlüssel für die Lokalisierung.
    private static let known: [String: (SensorGroup, String)] = [
        "TC0P": (.cpu, "CPU proximity"), "TC0D": (.cpu, "CPU die"), "TC0E": (.cpu, "CPU die"), "TC0F": (.cpu, "CPU die"),
        "TC0H": (.cpu, "CPU heatsink"), "TCXC": (.cpu, "CPU PECI"), "TCSA": (.cpu, "CPU system agent"),
        "TCGC": (.gpu, "Integrated graphics"), "TG0P": (.gpu, "GPU proximity"), "TG0D": (.gpu, "GPU die"),
        "TG0H": (.gpu, "GPU heatsink"), "TB0T": (.battery, "Battery"), "TB1T": (.battery, "Battery"),
        "TB2T": (.battery, "Battery"), "TM0P": (.memory, "Memory proximity"), "Tm0P": (.memory, "Mainboard"),
        "TH0P": (.storage, "Drive proximity"), "TH0A": (.storage, "SSD"), "TH0B": (.storage, "SSD"),
        "TH0a": (.storage, "SSD"), "TH0b": (.storage, "SSD"), "TW0P": (.wireless, "Wi‑Fi module"),
        "TPCD": (.power, "Platform controller hub"), "Ts0P": (.enclosure, "Palm rest"), "Ts1P": (.enclosure, "Palm rest"),
        "TA0P": (.enclosure, "Ambient"), "TA0V": (.enclosure, "Ambient"), "TaLC": (.enclosure, "Airflow left"),
        "TaRC": (.enclosure, "Airflow right"), "TI0P": (.power, "Thunderbolt"), "TI1P": (.power, "Thunderbolt"),
        "TPMP": (.power, "Power supply"), "Tp0C": (.power, "Power supply"),
    ]

    /// Ordnet einen Temperaturschlüssel einem Bereich zu. Apple Silicon: über Präfixe (Tp/Te/Tf CPU-Cluster,
    /// Tg GPU, TB Akku, TH/TN Speicher, TW WLAN, Ts/TA Gehäuse, Tm Speicher/Hauptplatine).
    public static func classify(_ key: String) -> (group: SensorGroup, meaning: String?) {
        if let entry = known[key] { return (entry.0, entry.1) }
        let prefix = String(key.prefix(2))
        switch prefix {
        case "TC", "Tp", "Te", "Tf", "TP": return (.cpu, nil)
        case "TG", "Tg": return (.gpu, nil)
        case "TM", "Tm": return (.memory, nil)
        case "TH", "TN": return (.storage, nil)
        case "TB": return (.battery, nil)
        case "TW": return (.wireless, nil)
        case "TI", "TV", "TD": return (.power, nil)
        case "Ts", "TA", "Ta": return (.enclosure, nil)
        default: return (.other, nil)
        }
    }

    /// Mittel und Maximum je Bereich (berechnet).
    public static func aggregate(_ sensors: [ThermalSensor]) -> [SensorGroupSummary] {
        SensorGroup.allCases.compactMap { group in
            let values = sensors.filter { $0.group == group }.map(\.celsius)
            guard !values.isEmpty else { return nil }
            return SensorGroupSummary(group: group, average: values.reduce(0, +) / Double(values.count),
                                      maximum: values.max() ?? 0, count: values.count)
        }
    }

    /// Alle bekannten Bedeutungen (für die Lokalisierung und Tests).
    public static var knownMeanings: Set<String> { Set(known.values.map(\.1)) }
}

/// Zusammenfassung eines Sensorbereichs (berechnet).
public struct SensorGroupSummary: Sendable, Equatable, Identifiable {
    public var id: SensorGroup { group }
    public var group: SensorGroup
    public var average: Double
    public var maximum: Double
    public var count: Int

    public init(group: SensorGroup, average: Double, maximum: Double, count: Int) {
        self.group = group
        self.average = average
        self.maximum = maximum
        self.count = count
    }
}

// MARK: - Batterie-Angaben von macOS (system_profiler SPPowerDataType)

public struct PowerProfilerInfo: Sendable, Equatable {
    /// „Good“, „Fair“, „Poor“, „Service Recommended“ – unverändert.
    public var condition: String?
    /// Apples „Maximale Kapazität“ („87%“).
    public var maximumCapacity: String?
    public var cycleCount: Int?
    public var manufacturer: String?
    public var deviceName: String?
    public var firmware: String?
    public var chargerWatts: Int?
    public var chargerName: String?

    public init(condition: String? = nil, maximumCapacity: String? = nil, cycleCount: Int? = nil, manufacturer: String? = nil,
                deviceName: String? = nil, firmware: String? = nil, chargerWatts: Int? = nil, chargerName: String? = nil) {
        self.condition = condition
        self.maximumCapacity = maximumCapacity
        self.cycleCount = cycleCount
        self.manufacturer = manufacturer
        self.deviceName = deviceName
        self.firmware = firmware
        self.chargerWatts = chargerWatts
        self.chargerName = chargerName
    }
}

public enum PowerProfilerParser {
    /// Durchsucht die JSON-Ausgabe tolerant nach den bekannten Schlüsseln (die Verschachtelung variiert je Version).
    /// Seriennummern werden nicht gelesen.
    public static func parse(_ data: Data) -> PowerProfilerInfo? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var info = PowerProfilerInfo()
        var found = false
        func string(_ value: Any?) -> String? {
            if let s = value as? String { return s.trimmingCharacters(in: .whitespaces).isEmpty ? nil : s }
            if let n = value as? NSNumber { return n.stringValue }
            return nil
        }
        func int(_ value: Any?) -> Int? {
            if let n = value as? Int { return n }
            if let s = value as? String { return Int(s.filter(\.isNumber)) }
            return nil
        }
        func visit(_ node: Any) {
            if let dict = node as? [String: Any] {
                for (key, value) in dict {
                    switch key {
                    case "sppower_battery_health": info.condition = string(value) ?? info.condition; found = true
                    case "sppower_battery_health_maximum_capacity": info.maximumCapacity = string(value); found = true
                    case "sppower_battery_cycle_count": info.cycleCount = int(value); found = true
                    case "sppower_battery_manufacturer": info.manufacturer = string(value)
                    case "sppower_battery_device_name": info.deviceName = string(value)
                    case "sppower_battery_firmware_version": info.firmware = string(value)
                    case "sppower_ac_charger_watts": info.chargerWatts = int(value)
                    case "sppower_ac_charger_name": info.chargerName = string(value)
                    default: visit(value)
                    }
                }
            } else if let list = node as? [Any] {
                list.forEach(visit)
            }
        }
        visit(root)
        return found ? info : nil
    }
}
