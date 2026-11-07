import Foundation

/// Rohwerte aus `host_statistics64(HOST_VM_INFO64)` (Seitenzahlen) – plattformneutral gespiegelt.
public struct VMPageCounts: Equatable, Sendable {
    public var free: UInt64
    public var active: UInt64
    public var inactive: UInt64
    public var speculative: UInt64
    public var wired: UInt64
    public var compressor: UInt64
    public var purgeable: UInt64
    /// Dateigestützte Seiten (`external_page_count`, Zwischenspeicher für Dateien).
    public var fileBacked: UInt64
    /// Anonyme Seiten (`internal_page_count`, Programmdaten).
    public var anonymous: UInt64
    public var compressions: UInt64
    public var decompressions: UInt64
    public var pageins: UInt64
    public var pageouts: UInt64
    public var swapins: UInt64
    public var swapouts: UInt64

    public init(free: UInt64 = 0, active: UInt64 = 0, inactive: UInt64 = 0, speculative: UInt64 = 0, wired: UInt64 = 0,
                compressor: UInt64 = 0, purgeable: UInt64 = 0, fileBacked: UInt64 = 0, anonymous: UInt64 = 0,
                compressions: UInt64 = 0, decompressions: UInt64 = 0, pageins: UInt64 = 0, pageouts: UInt64 = 0,
                swapins: UInt64 = 0, swapouts: UInt64 = 0) {
        self.free = free
        self.active = active
        self.inactive = inactive
        self.speculative = speculative
        self.wired = wired
        self.compressor = compressor
        self.purgeable = purgeable
        self.fileBacked = fileBacked
        self.anonymous = anonymous
        self.compressions = compressions
        self.decompressions = decompressions
        self.pageins = pageins
        self.pageouts = pageouts
        self.swapins = swapins
        self.swapouts = swapouts
    }
}

/// Aufteilung des Arbeitsspeichers in Bytes – berechnet wie die Aktivitätsanzeige.
public struct MemoryBreakdown: Equatable, Sendable {
    public var physical: UInt64
    /// App-Speicher: anonyme Seiten ohne löschbare.
    public var app: UInt64
    /// Fest zugeordnet (Kernel, nicht auslagerbar).
    public var wired: UInt64
    /// Vom Kompressor belegt.
    public var compressed: UInt64
    /// Zwischengespeicherte Dateien (jederzeit freigebbar).
    public var cached: UInt64
    /// Belegt = App + fest zugeordnet + komprimiert.
    public var used: UInt64 { app &+ wired &+ compressed }
    /// Weder belegt noch Zwischenspeicher (nicht negativ).
    public var free: UInt64 {
        let taken = used &+ cached
        return physical > taken ? physical - taken : 0
    }

    public init(physical: UInt64, app: UInt64, wired: UInt64, compressed: UInt64, cached: UInt64) {
        self.physical = physical
        self.app = app
        self.wired = wired
        self.compressed = compressed
        self.cached = cached
    }

    public var usedFraction: Double { physical > 0 ? min(1, Double(used) / Double(physical)) : 0 }
}

public enum MemoryMath {
    /// Wichtig: `pageSize` muss die Kernel-Seitengröße sein (`vm_kernel_page_size`), nicht `vm_page_size`.
    /// Unter Rosetta meldet `vm_page_size` 4 KB, obwohl die Kernelseiten auf Apple Silicon 16 KB groß sind.
    public static func breakdown(_ c: VMPageCounts, pageSize: UInt64, physical: UInt64) -> MemoryBreakdown {
        let appPages = c.anonymous > c.purgeable ? c.anonymous - c.purgeable : 0
        return MemoryBreakdown(
            physical: physical,
            app: appPages &* pageSize,
            wired: c.wired &* pageSize,
            compressed: c.compressor &* pageSize,
            cached: (c.fileBacked &+ c.purgeable) &* pageSize
        )
    }
}

/// Swap-Nutzung (`vm.swapusage`).
public struct SwapUsage: Equatable, Sendable {
    public var total: UInt64
    public var used: UInt64
    public var encrypted: Bool

    public init(total: UInt64, used: UInt64, encrypted: Bool) {
        self.total = total
        self.used = used
        self.encrypted = encrypted
    }
}

/// Speicherdruck wie vom System gemeldet.
public enum PressureLevel: Int, Comparable, Sendable, Codable, CaseIterable {
    case normal = 1
    case warning = 2
    case critical = 4

    /// `kern.memorystatus_vm_pressure_level`: 1 = normal, 2 = Warnung, 4 = kritisch. Unbekannte Werte → `nil`.
    public init?(sysctlValue: Int) {
        switch sysctlValue {
        case 1: self = .normal
        case 2: self = .warning
        case 4: self = .critical
        default: return nil
        }
    }

    public static func < (lhs: PressureLevel, rhs: PressureLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Thermalstatus (`ProcessInfo.ThermalState`) plattformneutral.
public enum ThermalLevel: Int, Comparable, Sendable, Codable, CaseIterable {
    case nominal = 0
    case fair = 1
    case serious = 2
    case critical = 3

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}
