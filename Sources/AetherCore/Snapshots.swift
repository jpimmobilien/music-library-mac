import Foundation

// Unveränderliche Messergebnisse, die von der Messmaschine an die Oberfläche gehen.

public struct CPUSnapshot: Sendable, Equatable {
    public var total: Reading<CPUUsage>
    public var perCore: [CPUUsage?]
    public var loadAverage: Reading<[Double]>

    public init(total: Reading<CPUUsage>, perCore: [CPUUsage?], loadAverage: Reading<[Double]>) {
        self.total = total
        self.perCore = perCore
        self.loadAverage = loadAverage
    }
}

public struct MemorySnapshot: Sendable, Equatable {
    public var breakdown: Reading<MemoryBreakdown>
    public var swap: Reading<SwapUsage>
    public var pressure: Reading<PressureLevel>

    public init(breakdown: Reading<MemoryBreakdown>, swap: Reading<SwapUsage>, pressure: Reading<PressureLevel>) {
        self.breakdown = breakdown
        self.swap = swap
        self.pressure = pressure
    }
}

public struct NetworkSnapshot: Sendable, Equatable {
    /// Bytes pro Sekunde über alle physischen Schnittstellen (ohne Loopback, VPN-Tunnel, AirDrop-Verbindungen –
    /// sonst würde Verkehr doppelt gezählt).
    public var download: Reading<Double>
    public var upload: Reading<Double>
    /// Seit Start von AETHER übertragen.
    public var sessionDownloaded: UInt64
    public var sessionUploaded: UInt64
    public var activeInterfaces: [String]

    public init(download: Reading<Double>, upload: Reading<Double>, sessionDownloaded: UInt64, sessionUploaded: UInt64,
                activeInterfaces: [String]) {
        self.download = download
        self.upload = upload
        self.sessionDownloaded = sessionDownloaded
        self.sessionUploaded = sessionUploaded
        self.activeInterfaces = activeInterfaces
    }
}

public struct VolumeInfo: Sendable, Equatable, Identifiable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var capacity: Int64
    public var available: Int64
    /// Verfügbar für wichtige Nutzung (inkl. löschbarem Platz, den macOS bei Bedarf freigibt).
    public var availableForImportantUsage: Int64?
    public var format: String?
    public var isInternal: Bool?
    public var isRemovable: Bool
    public var isRoot: Bool
    public var isReadOnly: Bool
    public var isEncrypted: Bool?
    public var isNetwork: Bool

    public init(name: String, path: String, capacity: Int64, available: Int64, availableForImportantUsage: Int64?,
                format: String?, isInternal: Bool?, isRemovable: Bool, isRoot: Bool, isReadOnly: Bool, isEncrypted: Bool?,
                isNetwork: Bool) {
        self.name = name
        self.path = path
        self.capacity = capacity
        self.available = available
        self.availableForImportantUsage = availableForImportantUsage
        self.format = format
        self.isInternal = isInternal
        self.isRemovable = isRemovable
        self.isRoot = isRoot
        self.isReadOnly = isReadOnly
        self.isEncrypted = isEncrypted
        self.isNetwork = isNetwork
    }

    /// Für Anzeige und Warnungen maßgeblich: „für wichtige Nutzung“, sonst „verfügbar“.
    public var effectiveAvailable: Int64 { availableForImportantUsage ?? available }
    public var used: Int64 { max(0, capacity - effectiveAvailable) }
    public var usedFraction: Double { capacity > 0 ? min(1, Double(used) / Double(capacity)) : 0 }
    /// Löschbarer Platz, den macOS bei Bedarf freigibt (Differenz der beiden Angaben).
    public var purgeable: Int64? {
        guard let important = availableForImportantUsage, important > available else { return nil }
        return important - available
    }
}

public struct StorageSnapshot: Sendable, Equatable {
    public var volumes: [VolumeInfo]
    public var readRate: Reading<Double>
    public var writeRate: Reading<Double>

    public init(volumes: [VolumeInfo], readRate: Reading<Double>, writeRate: Reading<Double>) {
        self.volumes = volumes
        self.readRate = readRate
        self.writeRate = writeRate
    }

    public var startup: VolumeInfo? { volumes.first(where: \.isRoot) }
}

public enum PowerSourceState: String, Sendable, Codable {
    case ac, battery, unknown
}

public struct BatterySnapshot: Sendable, Equatable {
    public var isPresent: Bool
    public var percent: Reading<Int>
    public var isCharging: Bool?
    public var isFullyCharged: Bool?
    public var powerSource: PowerSourceState
    public var minutesToEmpty: Reading<Int>
    public var minutesToFull: Reading<Int>
    public var cycleCount: Reading<Int>
    public var designCapacity: Reading<Int>
    public var fullChargeCapacity: Reading<Int>
    /// Volle Ladekapazität ÷ Designkapazität (berechnet, nicht Apples Angabe).
    public var computedHealth: Reading<Double>
    public var voltage: Reading<Double>
    public var amperage: Reading<Double>
    public var temperature: Reading<Double>
    public var adapterWatts: Reading<Int>
    /// Zustandsangabe von macOS (IOPS „BatteryHealth“), unverändert.
    public var systemCondition: String?

    public init(isPresent: Bool, percent: Reading<Int>, isCharging: Bool?, isFullyCharged: Bool?, powerSource: PowerSourceState,
                minutesToEmpty: Reading<Int>, minutesToFull: Reading<Int>, cycleCount: Reading<Int>,
                designCapacity: Reading<Int>, fullChargeCapacity: Reading<Int>, computedHealth: Reading<Double>,
                voltage: Reading<Double>, amperage: Reading<Double>, temperature: Reading<Double>, adapterWatts: Reading<Int>,
                systemCondition: String?) {
        self.isPresent = isPresent
        self.percent = percent
        self.isCharging = isCharging
        self.isFullyCharged = isFullyCharged
        self.powerSource = powerSource
        self.minutesToEmpty = minutesToEmpty
        self.minutesToFull = minutesToFull
        self.cycleCount = cycleCount
        self.designCapacity = designCapacity
        self.fullChargeCapacity = fullChargeCapacity
        self.computedHealth = computedHealth
        self.voltage = voltage
        self.amperage = amperage
        self.temperature = temperature
        self.adapterWatts = adapterWatts
        self.systemCondition = systemCondition
    }

    /// Leistung in Watt aus Spannung × Strom (berechnet; negativ = Entladen).
    public var power: Reading<Double> {
        guard let v = voltage.value, let a = amperage.value else {
            return Reading(unavailable: voltage.reason ?? amperage.reason ?? .queryFailed, source: .smartBattery)
        }
        return Reading(v * a / 1_000_000, source: DataSource(id: "battery.power", api: "Voltage × Amperage", provenance: .computed),
                       at: voltage.timestamp)
    }

    /// „Service empfohlen“ laut macOS (nicht aus dem berechneten Wert abgeleitet).
    public var serviceRecommended: Bool? {
        guard let c = systemCondition?.lowercased() else { return nil }
        if c.contains("service") || c.contains("check") || c.contains("poor") { return true }
        return false
    }
}

public enum BatteryMath {
    /// Kapazitätsgesundheit in Prozent, nur bei plausiblen Werten (Design > 0, Verhältnis 1…150 %).
    public static func health(fullCharge: Int, design: Int) -> Double? {
        guard design > 0, fullCharge > 0 else { return nil }
        let ratio = Double(fullCharge) / Double(design)
        guard ratio >= 0.01, ratio <= 1.5 else { return nil }
        return ratio
    }

    /// AppleSmartBattery meldet die Temperatur in Hundertstel °C (z. B. 3050 = 30,5 °C). Unplausibles → nil.
    public static func celsius(fromCentidegrees raw: Int) -> Double? {
        let value = Double(raw) / 100
        return (-20...90).contains(value) ? value : nil
    }

    /// `Amperage` kommt als vorzeichenbehaftete 16- oder 64-Bit-Zahl; als UInt gelesene Werte zurückwandeln.
    public static func signedMilliamps(_ raw: Int64) -> Int64 {
        if raw > Int64(Int16.max) && raw <= Int64(UInt16.max) { return raw - 65_536 }
        if raw > Int64(Int32.max) && raw <= Int64(UInt32.max) { return raw - 4_294_967_296 }
        return raw
    }
}

public struct GPUDevice: Sendable, Equatable, Identifiable {
    public var id: UInt64
    public var name: String
    public var hasUnifiedMemory: Bool
    public var isLowPower: Bool
    public var isRemovable: Bool
    /// Empfohlenes Arbeitsbudget laut Metal (keine Belegung!).
    public var recommendedWorkingSet: UInt64
    public var coreCount: Int?

    public init(id: UInt64, name: String, hasUnifiedMemory: Bool, isLowPower: Bool, isRemovable: Bool,
                recommendedWorkingSet: UInt64, coreCount: Int?) {
        self.id = id
        self.name = name
        self.hasUnifiedMemory = hasUnifiedMemory
        self.isLowPower = isLowPower
        self.isRemovable = isRemovable
        self.recommendedWorkingSet = recommendedWorkingSet
        self.coreCount = coreCount
    }
}

public struct GPUSnapshot: Sendable, Equatable {
    public var devices: [GPUDevice]
    /// Auslastung laut Grafiktreiber (0…1), falls der Treiber sie meldet.
    public var utilization: Reading<Double>

    public init(devices: [GPUDevice], utilization: Reading<Double>) {
        self.devices = devices
        self.utilization = utilization
    }
}

public struct ThermalSnapshot: Sendable, Equatable {
    public var state: Reading<ThermalLevel>
    public var batteryTemperature: Reading<Double>
    /// Sensorwerte (SMC) – ab Phase 5.
    public var sensors: Reading<Double>

    public init(state: Reading<ThermalLevel>, batteryTemperature: Reading<Double>, sensors: Reading<Double>) {
        self.state = state
        self.batteryTemperature = batteryTemperature
        self.sensors = sensors
    }
}

/// Statische Hardware- und Systemangaben (einmal ermittelt).
public struct HardwareSummary: Sendable, Equatable {
    public var modelIdentifier: String?
    public var machineName: String?
    public var kind: DeviceKind
    public var processor: ProcessorName?
    public var isAppleSilicon: Bool
    public var isTranslated: Bool
    public var physicalCores: Int?
    public var logicalCores: Int?
    public var clusters: [CoreCluster]
    public var physicalMemory: UInt64?
    public var osVersion: String?
    public var osBuild: String?
    public var bootTime: Date?

    public init(modelIdentifier: String? = nil, machineName: String? = nil, kind: DeviceKind = .unknown,
                processor: ProcessorName? = nil, isAppleSilicon: Bool = false, isTranslated: Bool = false,
                physicalCores: Int? = nil, logicalCores: Int? = nil, clusters: [CoreCluster] = [],
                physicalMemory: UInt64? = nil, osVersion: String? = nil, osBuild: String? = nil, bootTime: Date? = nil) {
        self.modelIdentifier = modelIdentifier
        self.machineName = machineName
        self.kind = kind
        self.processor = processor
        self.isAppleSilicon = isAppleSilicon
        self.isTranslated = isTranslated
        self.physicalCores = physicalCores
        self.logicalCores = logicalCores
        self.clusters = clusters
        self.physicalMemory = physicalMemory
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.bootTime = bootTime
    }

    /// Intel mit Hyper-Threading: mehr logische als physische Kerne.
    public var hasHyperThreading: Bool {
        guard !isAppleSilicon, let p = physicalCores, let l = logicalCores else { return false }
        return l > p
    }
}
