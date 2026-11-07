import Foundation

// =============================================================================================
// Puls – der Systemstatus als Satz. Jeder Hinweis beruht ausschließlich auf Messwerten oder Systemmeldungen,
// mit der Schwelle im Klartext. Haltezeiten verhindern Flackern. Keine Diagnosen, keine erfundenen Warnungen.
// =============================================================================================

public enum PulseSeverity: Int, Comparable, Sendable, Codable {
    /// Nur zur Kenntnis (keine Warnfarbe).
    case info = 0
    /// Erhöht (Bernstein).
    case elevated = 1
    /// Kritische Systemmeldung (Rot).
    case critical = 2

    public static func < (lhs: PulseSeverity, rhs: PulseSeverity) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum PulseFindingKind: String, Sendable, Codable, CaseIterable {
    case highCPU
    case memoryPressure
    case highSwap
    case thermal
    case lowDiskSpace
    case highNetwork
    case batteryService
}

public struct PulseFinding: Equatable, Sendable, Identifiable {
    public var kind: PulseFindingKind
    public var severity: PulseSeverity
    public var id: PulseFindingKind { kind }

    public init(kind: PulseFindingKind, severity: PulseSeverity) {
        self.kind = kind
        self.severity = severity
    }
}

/// Eingaben – `nil` heißt „nicht verfügbar“ und löst nie einen Hinweis aus.
public struct PulseInput: Sendable {
    public var cpuBusy: Double?
    public var pressure: PressureLevel?
    public var swapUsed: UInt64?
    public var physicalMemory: UInt64?
    public var thermal: ThermalLevel?
    /// Startvolume: verfügbar für wichtige Nutzung (inkl. löschbarem Platz) und Gesamtkapazität.
    public var startupAvailable: Int64?
    public var startupCapacity: Int64?
    public var networkBytesPerSecond: Double?
    /// Zustandsangabe von macOS („Service empfohlen“) – nicht der berechnete Wert.
    public var batteryServiceRecommended: Bool?

    public init(cpuBusy: Double? = nil, pressure: PressureLevel? = nil, swapUsed: UInt64? = nil, physicalMemory: UInt64? = nil,
                thermal: ThermalLevel? = nil, startupAvailable: Int64? = nil, startupCapacity: Int64? = nil,
                networkBytesPerSecond: Double? = nil, batteryServiceRecommended: Bool? = nil) {
        self.cpuBusy = cpuBusy
        self.pressure = pressure
        self.swapUsed = swapUsed
        self.physicalMemory = physicalMemory
        self.thermal = thermal
        self.startupAvailable = startupAvailable
        self.startupCapacity = startupCapacity
        self.networkBytesPerSecond = networkBytesPerSecond
        self.batteryServiceRecommended = batteryServiceRecommended
    }
}

public struct Pulse: Equatable, Sendable {
    /// Nach Schwere sortiert (schwerste zuerst).
    public var findings: [PulseFinding]
    /// Höchste Schwere unter den Hinweisen mit Warnfarbe; `nil` = ruhig.
    public var level: PulseSeverity? {
        findings.map(\.severity).filter { $0 > .info }.max()
    }

    public init(findings: [PulseFinding]) {
        self.findings = findings.sorted { $0.severity > $1.severity }
    }

    public static let calm = Pulse(findings: [])
}

/// Schwellen – öffentlich, damit die App sie im Klartext zeigen kann („ab 85 % über 10 s“).
public enum PulseThresholds {
    public static let highCPU = 0.85
    public static let highCPUSeconds = 10.0
    public static let swapFractionOfRAM = 0.25
    public static let lowDiskFraction = 0.10
    public static let lowDiskBytes: Int64 = 10_000_000_000
    public static let criticalDiskBytes: Int64 = 1_000_000_000
    public static let highNetworkBytesPerSecond = 50_000_000.0
    public static let highNetworkSeconds = 10.0
    /// Mindestanzahl aufeinanderfolgender Messungen, bevor ein Hinweis erscheint.
    public static let minimumStreak = 2
}

/// Wertet Messungen aus und merkt sich, wie lange ein Zustand schon anhält.
public struct PulseEvaluator: Sendable {
    public var sampleInterval: Double
    private var streaks: [PulseFindingKind: Int] = [:]

    public init(sampleInterval: Double) {
        self.sampleInterval = max(0.5, sampleInterval)
    }

    private func samples(forSeconds seconds: Double) -> Int {
        max(PulseThresholds.minimumStreak, Int((seconds / sampleInterval).rounded(.up)))
    }

    public mutating func evaluate(_ input: PulseInput) -> Pulse {
        var raw: [PulseFindingKind: PulseSeverity] = [:]

        if let cpu = input.cpuBusy, cpu >= PulseThresholds.highCPU {
            raw[.highCPU] = .elevated
        }
        if let pressure = input.pressure {
            switch pressure {
            case .critical: raw[.memoryPressure] = .critical
            case .warning: raw[.memoryPressure] = .elevated
            case .normal: break
            }
        }
        if let swap = input.swapUsed, let ram = input.physicalMemory, ram > 0, let pressure = input.pressure,
           pressure >= .warning, Double(swap) >= Double(ram) * PulseThresholds.swapFractionOfRAM {
            raw[.highSwap] = .elevated
        }
        if let thermal = input.thermal {
            switch thermal {
            case .critical: raw[.thermal] = .critical
            case .serious: raw[.thermal] = .elevated
            case .nominal, .fair: break
            }
        }
        if let available = input.startupAvailable, let capacity = input.startupCapacity, capacity > 0 {
            if available < PulseThresholds.criticalDiskBytes {
                raw[.lowDiskSpace] = .critical
            } else if available < PulseThresholds.lowDiskBytes
                        || Double(available) < Double(capacity) * PulseThresholds.lowDiskFraction {
                raw[.lowDiskSpace] = .elevated
            }
        }
        if let rate = input.networkBytesPerSecond, rate >= PulseThresholds.highNetworkBytesPerSecond {
            raw[.highNetwork] = .info
        }
        if input.batteryServiceRecommended == true {
            raw[.batteryService] = .elevated
        }

        // Haltezeiten: CPU und Netz brauchen ~10 s, Speicherdruck/Swap 2 Messungen; Thermalstatus, Speicherplatz
        // und Akkuzustand sind Systemmeldungen bzw. ändern sich langsam – sofort.
        var findings: [PulseFinding] = []
        for kind in PulseFindingKind.allCases {
            guard let severity = raw[kind] else {
                streaks[kind] = 0
                continue
            }
            let streak = (streaks[kind] ?? 0) + 1
            streaks[kind] = streak
            let required: Int
            switch kind {
            case .highCPU: required = samples(forSeconds: PulseThresholds.highCPUSeconds)
            case .highNetwork: required = samples(forSeconds: PulseThresholds.highNetworkSeconds)
            case .memoryPressure, .highSwap: required = PulseThresholds.minimumStreak
            case .thermal, .lowDiskSpace, .batteryService: required = 1
            }
            if streak >= required {
                findings.append(PulseFinding(kind: kind, severity: severity))
            }
        }
        return Pulse(findings: findings)
    }

    public mutating func reset() {
        streaks.removeAll()
    }
}
