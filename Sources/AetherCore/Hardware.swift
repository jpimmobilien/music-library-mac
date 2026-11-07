import Foundation

/// Gerätefamilie – bestimmt Symbol und Formulierungen („Dieser Mac hat keinen Lüfter“ usw. kommen aus Messungen,
/// nicht aus dieser Zuordnung).
public enum DeviceKind: String, Sendable, Codable, CaseIterable {
    case macBookPro, macBookAir, macBook, iMac, macMini, macStudio, macPro, virtualMachine, unknown

    /// Aus dem Modellnamen von `system_profiler` („MacBook Pro“) oder der Modellkennung (`hw.model`, z. B.
    /// „MacBookPro18,3“, „Macmini9,1“, „VirtualMac2,1“). Neuere Apple-Silicon-Kennungen („Mac14,9“) sagen nichts über
    /// die Familie – dann bleibt es `unknown`, bis der Modellname vorliegt.
    public static func from(machineName: String?, modelIdentifier: String?) -> DeviceKind {
        if let name = machineName?.lowercased() {
            if name.contains("virtual") || name.contains("vmware") { return .virtualMachine }
            if name.contains("macbook pro") { return .macBookPro }
            if name.contains("macbook air") { return .macBookAir }
            if name.contains("macbook") { return .macBook }
            if name.contains("imac") { return .iMac }
            if name.contains("mac mini") { return .macMini }
            if name.contains("mac studio") { return .macStudio }
            if name.contains("mac pro") { return .macPro }
        }
        if let model = modelIdentifier?.lowercased() {
            if model.hasPrefix("virtualmac") || model.hasPrefix("vmware") { return .virtualMachine }
            if model.hasPrefix("macbookpro") { return .macBookPro }
            if model.hasPrefix("macbookair") { return .macBookAir }
            if model.hasPrefix("macbook") { return .macBook }
            if model.hasPrefix("imac") { return .iMac }
            if model.hasPrefix("macmini") { return .macMini }
            if model.hasPrefix("macpro") { return .macPro }
        }
        return .unknown
    }

    public var isPortable: Bool { self == .macBookPro || self == .macBookAir || self == .macBook }
}

/// Prozessorbezeichnung aus `machdep.cpu.brand_string`.
public struct ProcessorName: Equatable, Sendable {
    public enum Vendor: String, Sendable { case apple, intel, other }

    public var vendor: Vendor
    /// Bereinigt: „Apple M3 Pro“, „Intel Core i7-9750H“.
    public var displayName: String
    /// Apple Silicon: Familie („M3“) und Stufe („Pro“, „Max“, „Ultra“ oder leer).
    public var appleFamily: String?
    public var appleTier: String?
    /// Intel: Nenntakt aus der Bezeichnung („2.60GHz“), sofern enthalten.
    public var nominalClock: String?
    /// Die Bezeichnung weist auf einen virtuellen Prozessor hin („(Virtual)“).
    public var isVirtual: Bool

    public static func parse(_ brand: String) -> ProcessorName {
        var text = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let isVirtual = text.lowercased().contains("virtual")
        text = text.replacingOccurrences(of: "(R)", with: "").replacingOccurrences(of: "(TM)", with: "")
        text = text.replacingOccurrences(of: "(Virtual)", with: "")
        var clock: String?
        if let at = text.range(of: " @ ") {
            clock = String(text[at.upperBound...]).trimmingCharacters(in: .whitespaces)
            text = String(text[..<at.lowerBound])
        }
        text = text.replacingOccurrences(of: " CPU", with: "")
        while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
        text = text.trimmingCharacters(in: .whitespaces)

        if text.hasPrefix("Apple ") {
            let parts = text.dropFirst("Apple ".count).split(separator: " ").map(String.init)
            let family = parts.first
            let tier = parts.count > 1 ? parts[1] : nil
            return ProcessorName(vendor: .apple, displayName: text, appleFamily: family, appleTier: tier,
                                 nominalClock: nil, isVirtual: isVirtual)
        }
        if text.lowercased().contains("intel") {
            return ProcessorName(vendor: .intel, displayName: text, appleFamily: nil, appleTier: nil,
                                 nominalClock: clock, isVirtual: isVirtual)
        }
        return ProcessorName(vendor: .other, displayName: text, appleFamily: nil, appleTier: nil,
                             nominalClock: clock, isVirtual: isVirtual)
    }
}

/// Ausgewählte Felder aus `system_profiler SPHardwareDataType -json`. Die Seriennummer wird bewusst nicht gelesen.
public struct ProfilerHardware: Equatable, Sendable {
    public var machineName: String?
    public var machineModel: String?
    public var chip: String?
    public var processorSpeed: String?
    public var totalCores: Int?
    public var performanceCores: Int?
    public var efficiencyCores: Int?
    public var memory: String?
    public var modelNumber: String?

    public init(machineName: String? = nil, machineModel: String? = nil, chip: String? = nil, processorSpeed: String? = nil,
                totalCores: Int? = nil, performanceCores: Int? = nil, efficiencyCores: Int? = nil, memory: String? = nil,
                modelNumber: String? = nil) {
        self.machineName = machineName
        self.machineModel = machineModel
        self.chip = chip
        self.processorSpeed = processorSpeed
        self.totalCores = totalCores
        self.performanceCores = performanceCores
        self.efficiencyCores = efficiencyCores
        self.memory = memory
        self.modelNumber = modelNumber
    }
}

public enum ProfilerParser {
    /// Liest den ersten Eintrag von `SPHardwareDataType`. Unbekannte oder fehlende Felder bleiben `nil`.
    public static func hardware(fromJSON data: Data) -> ProfilerHardware? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["SPHardwareDataType"] as? [[String: Any]],
              let item = list.first else { return nil }
        func string(_ key: String) -> String? {
            guard let value = item[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        var result = ProfilerHardware()
        result.machineName = string("machine_name")
        result.machineModel = string("machine_model")
        result.chip = string("chip_type") ?? string("cpu_type")
        result.processorSpeed = string("current_processor_speed")
        result.memory = string("physical_memory")
        result.modelNumber = string("model_number")
        // Apple Silicon: "proc 10:6:4" (gesamt:Leistung:Effizienz). Intel: Zahl.
        if let procs = string("number_processors") {
            let numbers = procs.replacingOccurrences(of: "proc", with: "")
                .split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if numbers.count >= 1 { result.totalCores = numbers[0] }
            if numbers.count >= 3 {
                result.performanceCores = numbers[1]
                result.efficiencyCores = numbers[2]
            }
        } else if let n = item["number_processors"] as? Int {
            result.totalCores = n
        }
        return result
    }
}

/// Betriebszeit aus Bootzeitpunkt und jetzt.
public enum Uptime {
    public static func seconds(bootTime: Date, now: Date = Date()) -> Double {
        max(0, now.timeIntervalSince(bootTime))
    }
}
