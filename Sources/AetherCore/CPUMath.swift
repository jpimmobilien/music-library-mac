import Foundation

/// Rechenzeit-Zähler eines Kerns (Ticks seit Systemstart; `natural_t`, also 32 Bit – sie können überlaufen).
public struct CPUTicks: Equatable, Sendable {
    public var user: UInt32
    public var system: UInt32
    public var idle: UInt32
    public var nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

/// Auslastung als Anteile 0…1 (Summe = 1).
public struct CPUUsage: Equatable, Sendable {
    public var user: Double
    public var system: Double
    public var idle: Double

    public init(user: Double, system: Double, idle: Double) {
        self.user = user
        self.system = system
        self.idle = idle
    }

    /// Belegt = Benutzer + System (nice zählt wie die Aktivitätsanzeige zum Benutzeranteil).
    public var busy: Double { min(1, max(0, user + system)) }

    public static let zero = CPUUsage(user: 0, system: 0, idle: 1)
}

public enum CPUMath {
    /// Auslastung zwischen zwei Zählerständen eines Kerns. Überläufe der 32-Bit-Zähler werden korrekt behandelt
    /// (Differenz modulo 2³²). Ohne verstrichene Ticks: `nil` (nichts gemessen – nicht „0 %“ erfinden).
    public static func usage(from old: CPUTicks, to new: CPUTicks) -> CPUUsage? {
        let user = Double(new.user &- old.user) + Double(new.nice &- old.nice)
        let system = Double(new.system &- old.system)
        let idle = Double(new.idle &- old.idle)
        let total = user + system + idle
        guard total > 0 else { return nil }
        return CPUUsage(user: user / total, system: system / total, idle: idle / total)
    }

    /// Gesamtauslastung über alle Kerne (Summe der Ticks, nicht Mittel der Prozente – so wie der Kernel zählt).
    public static func total(from old: [CPUTicks], to new: [CPUTicks]) -> CPUUsage? {
        guard old.count == new.count, !new.isEmpty else { return nil }
        var user = 0.0, system = 0.0, idle = 0.0
        for (o, n) in zip(old, new) {
            user += Double(n.user &- o.user) + Double(n.nice &- o.nice)
            system += Double(n.system &- o.system)
            idle += Double(n.idle &- o.idle)
        }
        let total = user + system + idle
        guard total > 0 else { return nil }
        return CPUUsage(user: user / total, system: system / total, idle: idle / total)
    }

    /// Auslastung je Kern; Kerne ohne verstrichene Ticks erscheinen als `nil`.
    public static func perCore(from old: [CPUTicks], to new: [CPUTicks]) -> [CPUUsage?] {
        guard old.count == new.count else { return new.map { _ in nil } }
        return zip(old, new).map { usage(from: $0, to: $1) }
    }
}

/// Kerncluster (Apple Silicon: Leistungs-/Effizienzkerne; Intel: ein Cluster).
public struct CoreCluster: Equatable, Sendable {
    public enum Kind: String, Sendable, Codable {
        case performance
        case efficiency
        /// Intel oder unbekannter Name.
        case uniform
    }

    public var kind: Kind
    /// Bezeichnung wie vom System gemeldet (z. B. „Performance“, „Efficiency“).
    public var systemName: String
    public var physicalCores: Int
    public var logicalCores: Int

    public init(kind: Kind, systemName: String, physicalCores: Int, logicalCores: Int) {
        self.kind = kind
        self.systemName = systemName
        self.physicalCores = physicalCores
        self.logicalCores = logicalCores
    }

    /// Ordnet den von `hw.perflevelN.name` gemeldeten Namen zu.
    public static func kind(forSystemName name: String) -> Kind {
        let n = name.lowercased()
        if n.hasPrefix("perf") || n.contains("performance") || n.contains("super") { return .performance }
        if n.hasPrefix("eff") || n.contains("efficiency") { return .efficiency }
        return .uniform
    }
}
