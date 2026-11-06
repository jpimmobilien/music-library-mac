import Foundation

/// Geschwindigkeit (gleitender Mittelwert) und Restzeit einer Übertragung.
public struct TransferRateEstimator: Sendable {
    public private(set) var bytesPerSecond: Double = 0
    private var lastBytes: UInt64 = 0
    private var lastTime: TimeInterval?
    /// Glättung: kleiner = ruhiger.
    public var smoothing: Double = 0.25

    public init() {}

    public mutating func reset() {
        bytesPerSecond = 0
        lastBytes = 0
        lastTime = nil
    }

    /// Neuer Messpunkt (Gesamtbytes bis jetzt, Zeitstempel in Sekunden).
    public mutating func update(totalBytes: UInt64, at time: TimeInterval) {
        guard let t0 = lastTime else {
            lastTime = time
            lastBytes = totalBytes
            return
        }
        let dt = time - t0
        guard dt >= 0.2 else { return }
        let delta = totalBytes >= lastBytes ? Double(totalBytes - lastBytes) : 0
        let instant = delta / dt
        bytesPerSecond = bytesPerSecond == 0 ? instant : bytesPerSecond * (1 - smoothing) + instant * smoothing
        lastTime = time
        lastBytes = totalBytes
    }

    /// Restzeit in Sekunden (nil, solange keine Geschwindigkeit bekannt ist).
    public func remainingSeconds(done: UInt64, total: UInt64) -> Double? {
        guard bytesPerSecond > 1, total > done else { return total > 0 && done >= total ? 0 : nil }
        return Double(total - done) / bytesPerSecond
    }
}

public enum ByteFormat {
    /// „1,2 GB“ (Dezimaleinheiten wie der Finder, deutsches Zahlformat).
    public static func string(_ bytes: UInt64) -> String {
        let units = ["Byte", "KB", "MB", "GB", "TB", "PB"]
        if bytes < 1000 { return "\(bytes) \(bytes == 1 ? "Byte" : "Byte")" }
        var value = Double(bytes)
        var i = 0
        while value >= 1000 && i < units.count - 1 {
            value /= 1000
            i += 1
        }
        let digits = value < 10 ? 1 : (value < 100 ? 1 : 0)
        return decimal(value, digits: digits) + " " + units[i]
    }

    public static func rate(_ bytesPerSecond: Double) -> String {
        string(UInt64(max(0, bytesPerSecond))) + "/s"
    }

    static func decimal(_ v: Double, digits: Int) -> String {
        let s = String(format: "%.\(digits)f", v)
        return s.replacingOccurrences(of: ".", with: ",")
    }
}

public enum DurationFormat {
    /// „3 Min. 12 Sek.“, „45 Sek.“, „1 Std. 5 Min.“
    public static func string(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(max(s, 1)) Sek." }
        if s < 3600 { return "\(s / 60) Min. \(s % 60) Sek." }
        return "\(s / 3600) Std. \((s % 3600) / 60) Min."
    }
}

/// Zustände einer Übertragung (unabhängig von der Oberfläche).
public enum TransferStatus: Equatable, Sendable {
    case waiting
    case preparing
    case running
    case paused
    case verifying
    case completed
    case skipped
    case cancelled
    case failed(String)

    public var isFinished: Bool {
        switch self {
        case .completed, .skipped, .cancelled, .failed: return true
        default: return false
        }
    }

    public var isActive: Bool {
        switch self {
        case .preparing, .running, .verifying: return true
        default: return false
        }
    }

    public var canRetry: Bool {
        switch self {
        case .failed, .cancelled: return true
        default: return false
        }
    }

    public var title: String {
        switch self {
        case .waiting: return "Wartet"
        case .preparing: return "Wird vorbereitet"
        case .running: return "Wird übertragen"
        case .paused: return "Angehalten"
        case .verifying: return "Wird geprüft"
        case .completed: return "Fertig"
        case .skipped: return "Übersprungen"
        case .cancelled: return "Abgebrochen"
        case let .failed(reason): return "Fehler: \(reason)"
        }
    }
}

/// Prüfung nach der Übertragung.
public enum TransferVerification {
    /// Größe stimmt? (Ist die erwartete Größe unbekannt, gilt nur „> 0 oder erwartet 0“.)
    public static func sizeMatches(expected: UInt64?, actual: UInt64) -> Bool {
        guard let expected else { return true }
        return expected == actual
    }
}
