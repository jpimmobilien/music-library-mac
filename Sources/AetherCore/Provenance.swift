import Foundation

// =============================================================================================
// Herkunft jeder Zahl – das Markenzeichen von AETHER.
//
// Jeder angezeigte Wert gehört zu einer Datenquelle mit einer Herkunftsart. Die Oberfläche zeigt sie als kleines
// Symbol (● gemessen, ◐ berechnet, ◇ Systemangabe, ○ Schätzung, ⊘ nicht verfügbar) und erklärt sie auf Klick.
// =============================================================================================

/// Art eines Werts.
public enum Provenance: String, Codable, Sendable, CaseIterable {
    /// Direkt gemessen (Zähler, Sensor, Kernelwert).
    case measured
    /// Aus Messwerten berechnet (z. B. Auslastung aus zwei Zählerständen, Akkuzustand aus zwei Kapazitäten).
    case computed
    /// Vom System oder Hersteller angegeben (Einstufung, Spezifikation, Treiberangabe).
    case systemReported
    /// Schätzung des Systems (z. B. Restlaufzeit).
    case estimated
}

/// Warum ein Wert nicht angezeigt werden kann. Jeder Fall hat in der App eine verständliche Erklärung.
public enum UnavailableReason: String, Codable, Sendable, CaseIterable {
    /// Erst nach der zweiten Messung berechenbar.
    case awaitingSecondSample
    /// Diese Hardware hat das nicht (z. B. kein Akku, keine Lüfter).
    case notPresent
    /// macOS stellt den Wert Drittanbieter-Apps nicht bereit.
    case notProvidedByMacOS
    /// Nur mit Administratorrechten erhältlich – AETHER fordert sie bewusst nicht an.
    case requiresAdministrator
    /// Nur über private Schnittstellen von Apple erhältlich – AETHER nutzt sie nicht.
    case privateInterfaceOnly
    /// Virtueller Mac: keine physischen Sensoren.
    case virtualMachine
    /// Die Quelle hat geantwortet, aber keinen plausiblen Wert geliefert.
    case implausibleValue
    /// Die Abfrage ist fehlgeschlagen.
    case queryFailed
    /// Wird in einer späteren Phase umgesetzt (nur in Zwischenversionen).
    case plannedLaterPhase
}

/// Eine technische Datenquelle. `id` dient als Schlüssel für die lokalisierte Erklärung.
public struct DataSource: Hashable, Sendable, Identifiable {
    public let id: String
    /// Technische Bezeichnung, unverändert angezeigt (z. B. „host_processor_info · PROCESSOR_CPU_LOAD_INFO“).
    public let api: String
    public let provenance: Provenance

    public init(id: String, api: String, provenance: Provenance) {
        self.id = id
        self.api = api
        self.provenance = provenance
    }
}

public extension DataSource {
    static let cpuTicks = DataSource(id: "cpu.ticks", api: "host_processor_info · PROCESSOR_CPU_LOAD_INFO", provenance: .computed)
    static let loadAverage = DataSource(id: "cpu.loadavg", api: "getloadavg", provenance: .measured)
    static let cpuTopology = DataSource(id: "cpu.topology", api: "sysctl hw.perflevel* · hw.physicalcpu · hw.logicalcpu", provenance: .systemReported)
    static let vmStatistics = DataSource(id: "memory.vm", api: "host_statistics64 · HOST_VM_INFO64 × vm_kernel_page_size", provenance: .computed)
    static let swapUsage = DataSource(id: "memory.swap", api: "sysctl vm.swapusage", provenance: .measured)
    static let memoryPressure = DataSource(id: "memory.pressure", api: "sysctl kern.memorystatus_vm_pressure_level", provenance: .systemReported)
    static let thermalState = DataSource(id: "thermal.state", api: "ProcessInfo.thermalState", provenance: .systemReported)
    static let smcSensors = DataSource(id: "thermal.smc", api: "SMC · AppleSMC · IOConnectCallStructMethod", provenance: .measured)
    static let batteryTemperature = DataSource(id: "thermal.battery", api: "IORegistry · AppleSmartBattery · Temperature", provenance: .measured)
    static let powerSources = DataSource(id: "battery.iops", api: "IOPSCopyPowerSourcesInfo", provenance: .measured)
    static let smartBattery = DataSource(id: "battery.smart", api: "IORegistry · AppleSmartBattery", provenance: .measured)
    static let batteryHealth = DataSource(id: "battery.health", api: "AppleRawMaxCapacity ÷ DesignCapacity × 100", provenance: .computed)
    static let batteryTimeRemaining = DataSource(id: "battery.time", api: "IOPSCopyPowerSourcesInfo · Time to Empty/Full", provenance: .estimated)
    static let volumes = DataSource(id: "storage.volumes", api: "URLResourceValues · volumeAvailableCapacityForImportantUsage", provenance: .measured)
    static let blockStorage = DataSource(id: "storage.io", api: "IORegistry · IOBlockStorageDriver · Statistics", provenance: .computed)
    static let interfaceCounters = DataSource(id: "network.counters", api: "sysctl NET_RT_IFLIST2 · if_data64", provenance: .computed)
    static let gpuDevices = DataSource(id: "gpu.devices", api: "system_profiler SPDisplaysDataType -json · IORegistry AGXAccelerator", provenance: .systemReported)
    static let gpuStatistics = DataSource(id: "gpu.utilization", api: "IORegistry · IOAccelerator · PerformanceStatistics", provenance: .systemReported)
    static let hardwareSysctl = DataSource(id: "hardware.sysctl", api: "sysctl hw.model · machdep.cpu.brand_string · hw.memsize", provenance: .systemReported)
    static let systemProfiler = DataSource(id: "hardware.profiler", api: "system_profiler SPHardwareDataType -json", provenance: .systemReported)
    static let osVersion = DataSource(id: "software.os", api: "sysctl kern.osproductversion · kern.osversion", provenance: .systemReported)
    static let pulse = DataSource(id: "pulse", api: "AETHER · Puls-Regeln (AetherCore/Pulse.swift)", provenance: .computed)

    /// Alle Quellen (für die Datenschutz-/Quellenübersicht und Tests der Lokalisierung).
    static let all: [DataSource] = [
        .cpuTicks, .loadAverage, .cpuTopology, .vmStatistics, .swapUsage, .memoryPressure, .thermalState,
        .smcSensors, .batteryTemperature, .powerSources, .smartBattery, .batteryHealth, .batteryTimeRemaining, .volumes,
        .blockStorage, .interfaceCounters, .gpuDevices, .gpuStatistics, .hardwareSysctl, .systemProfiler, .osVersion, .pulse,
    ]
}

/// Ein Wert mit Herkunft – oder der Grund, warum es ihn nicht gibt.
public struct Reading<Value: Sendable>: Sendable {
    public var value: Value?
    public var source: DataSource
    public var reason: UnavailableReason?
    public var timestamp: Date

    public init(_ value: Value, source: DataSource, at timestamp: Date = Date()) {
        self.value = value
        self.source = source
        self.reason = nil
        self.timestamp = timestamp
    }

    public init(unavailable reason: UnavailableReason, source: DataSource, at timestamp: Date = Date()) {
        self.value = nil
        self.source = source
        self.reason = reason
        self.timestamp = timestamp
    }

    public var isAvailable: Bool { value != nil }

    public func map<T: Sendable>(_ transform: (Value) -> T) -> Reading<T> {
        if let value { return Reading<T>(transform(value), source: source, at: timestamp) }
        return Reading<T>(unavailable: reason ?? .queryFailed, source: source, at: timestamp)
    }
}

extension Reading: Equatable where Value: Equatable {}
