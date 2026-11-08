import Foundation

// =============================================================================================
// Monitoring 2.0: Glättung, Spitzen, Anzeige-Hysterese und zeitbasierte Verläufe.
//
// Grundsatz: Der Rohwert bleibt immer erhalten. Geglättet wird nur die Anzeige – asymmetrisch, damit Anstiege
// (echte Lastspitzen) schnell sichtbar werden und Abfälle ruhig verlaufen. Kurze Spitzen hält `PeakWindow` fest.
// Alles hier ist reine Logik und auf Linux getestet.
// =============================================================================================

/// Kennung einer Messgröße (CPU gesamt, Kern 3, Netz ↓ …).
public struct MetricID: Hashable, Sendable, CustomStringConvertible {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
    public var description: String { raw }

    public static let cpuTotal = MetricID("cpu.total")
    public static let cpuUser = MetricID("cpu.user")
    public static let cpuSystem = MetricID("cpu.system")
    public static func core(_ index: Int) -> MetricID { MetricID("cpu.core.\(index)") }
    public static let gpu = MetricID("gpu")
    public static let memoryUsed = MetricID("memory.used")
    public static let memoryCompressed = MetricID("memory.compressed")
    public static let swapUsed = MetricID("memory.swap")
    public static let networkDown = MetricID("network.down")
    public static let networkUp = MetricID("network.up")
    public static let diskRead = MetricID("disk.read")
    public static let diskWrite = MetricID("disk.write")
    public static let hottest = MetricID("thermal.hottest")
    public static func fan(_ index: Int) -> MetricID { MetricID("thermal.fan.\(index)") }
    public static let batteryPercent = MetricID("battery.percent")
    public static let batteryPower = MetricID("battery.power")
}

/// Einheit – bestimmt Glättung und Anzeige-Raster.
public enum MetricUnit: Sendable, Equatable {
    /// 0…1
    case fraction
    /// Bytes
    case bytes
    case bytesPerSecond
    case celsius
    case rpm
    case watts
    /// Batterie in Prozent (ganze Zahlen, ohne Glättung)
    case percentInteger
}

/// Zeitkonstanten der Glättung (Sekunden) für Anstieg und Abfall.
public struct SmoothingProfile: Sendable, Equatable {
    public var rise: Double
    public var fall: Double
    /// Zeitfenster der Spitzenanzeige (0 = keine).
    public var peakWindow: Double

    public init(rise: Double, fall: Double, peakWindow: Double) {
        self.rise = rise
        self.fall = fall
        self.peakWindow = peakWindow
    }

    public static let cpu = SmoothingProfile(rise: 0.5, fall: 2.5, peakWindow: 10)
    public static let core = SmoothingProfile(rise: 0.4, fall: 2.0, peakWindow: 0)
    public static let gpu = SmoothingProfile(rise: 1.0, fall: 3.0, peakWindow: 10)
    public static let memory = SmoothingProfile(rise: 4.0, fall: 4.0, peakWindow: 0)
    public static let throughput = SmoothingProfile(rise: 0.6, fall: 3.0, peakWindow: 10)
    public static let temperature = SmoothingProfile(rise: 6.0, fall: 4.0, peakWindow: 0)
    public static let fan = SmoothingProfile(rise: 4.0, fall: 4.0, peakWindow: 0)
    public static let power = SmoothingProfile(rise: 3.0, fall: 3.0, peakWindow: 0)
    /// Keine Glättung (z. B. Batterieladung: nur echte Änderungen).
    public static let none = SmoothingProfile(rise: 0, fall: 0, peakWindow: 0)
}

/// Exponentielle Glättung mit zeitabhängigem Alpha: `alpha = 1 − exp(−Δt / τ)`, getrennt für Anstieg und Abfall.
public struct AsymmetricEMA: Sendable, Equatable {
    public var rise: Double
    public var fall: Double
    public private(set) var value: Double?
    private var lastTime: Double?

    public init(rise: Double, fall: Double) {
        self.rise = rise
        self.fall = fall
    }

    public static func alpha(deltaTime: Double, tau: Double) -> Double {
        guard tau > 0 else { return 1 }
        guard deltaTime > 0 else { return 0 }
        return 1 - exp(-deltaTime / tau)
    }

    /// Neuer Rohwert zum Zeitpunkt `time` (monotone Sekunden). Liefert den geglätteten Wert.
    @discardableResult
    public mutating func update(_ raw: Double, at time: Double) -> Double {
        guard raw.isFinite else { return value ?? raw }
        guard let previous = value, let last = lastTime else {
            value = raw
            lastTime = time
            return raw
        }
        let dt = time - last
        // Große Lücke (z. B. Fenster war geschlossen): neu beginnen statt alte Werte nachzuziehen.
        if dt > max(30, 10 * max(rise, fall)) || dt < 0 {
            value = raw
            lastTime = time
            return raw
        }
        let tau = raw >= previous ? rise : fall
        let a = Self.alpha(deltaTime: dt, tau: tau)
        let next = a * raw + (1 - a) * previous
        value = next
        lastTime = time
        return next
    }

    public mutating func reset() {
        value = nil
        lastTime = nil
    }
}

/// Höchstwert der letzten `window` Sekunden.
public struct PeakWindow: Sendable, Equatable {
    public let window: Double
    private var samples: [(time: Double, value: Double)] = []

    public init(window: Double) {
        self.window = window
    }

    public static func == (lhs: PeakWindow, rhs: PeakWindow) -> Bool {
        lhs.window == rhs.window && lhs.samples.map(\.value) == rhs.samples.map(\.value)
    }

    @discardableResult
    public mutating func add(_ value: Double, at time: Double) -> Double {
        // Monotone Warteschlange: kleinere ältere Werte können nie mehr Maximum werden.
        while let last = samples.last, last.value <= value { samples.removeLast() }
        samples.append((time, value))
        while let first = samples.first, first.time < time - window { samples.removeFirst() }
        return samples.first?.value ?? value
    }

    public var peak: Double? { samples.first?.value }
}

/// Ein Messwert in drei Formen: Rohwert, geglättete Anzeige, Spitze im Zeitfenster.
public struct SmoothedValue: Sendable, Equatable {
    public var raw: Double
    public var smoothed: Double
    public var peak: Double?

    public init(raw: Double, smoothed: Double, peak: Double?) {
        self.raw = raw
        self.smoothed = smoothed
        self.peak = peak
    }
}

/// Glättung + Spitze für eine Messgröße.
public struct MetricSmoother: Sendable, Equatable {
    public let profile: SmoothingProfile
    private var ema: AsymmetricEMA
    private var peaks: PeakWindow?

    public init(profile: SmoothingProfile) {
        self.profile = profile
        ema = AsymmetricEMA(rise: profile.rise, fall: profile.fall)
        peaks = profile.peakWindow > 0 ? PeakWindow(window: profile.peakWindow) : nil
    }

    public mutating func update(raw: Double, at time: Double) -> SmoothedValue {
        let smoothed = ema.update(raw, at: time)
        let peak = peaks?.add(raw, at: time)
        return SmoothedValue(raw: raw, smoothed: smoothed, peak: peak)
    }

    public mutating func reset() {
        ema.reset()
        if let window = peaks?.window { peaks = PeakWindow(window: window) }
    }
}

/// Anzeige-Raster: Ein neuer Wert wird nur veröffentlicht, wenn sich seine gerundete Darstellung ändert.
public enum DisplayQuantizer {
    public static func key(_ value: Double, unit: MetricUnit) -> Int64 {
        guard value.isFinite else { return Int64.min }
        switch unit {
        case .fraction: return Int64((value * 100).rounded())                 // 1 %
        case .percentInteger: return Int64(value.rounded())
        case .celsius: return Int64((value * 2).rounded())                    // 0,5 °C
        case .rpm: return Int64((value / 10).rounded())                       // 10 U/min
        case .watts: return Int64((value * 10).rounded())                     // 0,1 W
        case .bytes: return Int64((value / 10_000_000).rounded())             // 0,01 GB
        case .bytesPerSecond:
            // drei gültige Stellen (logarithmisches Raster): 1,23 KB/s · 12,3 MB/s
            guard value >= 1 else { return 0 }
            let exponent = floor(log10(value))
            let scale = pow(10, exponent - 2)
            return Int64((value / scale).rounded()) + Int64(exponent) * 1_000
        }
    }
}

/// Zeitbasierter Verlauf mit fester Kapazität (älteste Werte fallen heraus). Fehlende Werte bleiben Lücken.
public struct TimeSeries: Sendable, Equatable {
    public let capacity: Int
    private var times: [Double] = []
    private var values: [Double] = []
    private var head = 0

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    public var count: Int { times.count }
    public var isEmpty: Bool { times.isEmpty }

    /// `value == nil` → Lücke (z. B. nicht verfügbar).
    public mutating func append(_ value: Double?, at time: Double) {
        let v = value ?? .nan
        if times.count < capacity {
            times.append(time)
            values.append(v)
        } else {
            times[head] = time
            values[head] = v
            head = (head + 1) % capacity
        }
    }

    public mutating func removeAll() {
        times.removeAll(keepingCapacity: true)
        values.removeAll(keepingCapacity: true)
        head = 0
    }

    /// Älteste zuerst.
    public var points: [(time: Double, value: Double?)] {
        let order = times.count < capacity ? Array(0..<times.count) : Array(head..<capacity) + Array(0..<head)
        return order.map { (times[$0], values[$0].isNaN ? nil : values[$0]) }
    }

    public var lastTime: Double? {
        guard !times.isEmpty else { return nil }
        return times.count < capacity ? times.last : times[(head + capacity - 1) % capacity]
    }

    /// Bündelt die Werte der letzten `window` Sekunden (bis `now`) in `buckets` gleich breite Zeitabschnitte.
    /// Jeder Abschnitt trägt Minimum, Maximum und Mittel – Spitzen bleiben so auch bei 1 h sichtbar.
    /// Läuft vom neuesten Wert rückwärts und hört am Fensteranfang auf (Zeitstempel sind aufsteigend) – ein
    /// 1-min-Diagramm liest also nur ~60 Werte, nicht den ganzen Verlauf.
    public func buckets(window: Double, now: Double, count buckets: Int) -> [SeriesBucket] {
        guard buckets > 0 else { return [] }
        var result = [SeriesBucket](repeating: SeriesBucket(), count: buckets)
        guard window > 0 else { return result }
        let start = now - window
        let width = window / Double(buckets)
        forEachNewestFirst(until: start) { t, v in
            guard t <= now else { return }
            let slot = min(buckets - 1, max(0, Int((t - start) / width)))
            if v.isNaN { result[slot].addGap() } else { result[slot].add(v) }
        }
        return result
    }

    /// Höchster Wert im Zeitfenster.
    public func maximum(window: Double, now: Double) -> Double? {
        var best: Double?
        forEachNewestFirst(until: now - window) { t, v in
            guard t <= now, !v.isNaN else { return }
            best = max(best ?? v, v)
        }
        return best
    }

    /// Neueste Werte zuerst, bis der Zeitstempel vor `start` liegt.
    private func forEachNewestFirst(until start: Double, _ body: (Double, Double) -> Void) {
        let n = times.count
        guard n > 0 else { return }
        let newest = n < capacity ? n - 1 : (head + capacity - 1) % capacity
        for step in 0..<n {
            let index = (newest - step + n) % n
            let t = times[index]
            if t < start { break }
            body(t, values[index])
        }
    }
}

/// Ein Zeitabschnitt eines Verlaufs.
public struct SeriesBucket: Sendable, Equatable {
    public private(set) var minimum: Double = .infinity
    public private(set) var maximum: Double = -.infinity
    public private(set) var sum: Double = 0
    public private(set) var count = 0
    /// Ausdrücklich als „nicht verfügbar“ erfasste Messungen in diesem Abschnitt.
    public private(set) var gapCount = 0

    public init() {}

    public mutating func addGap() {
        gapCount += 1
    }

    public mutating func add(_ value: Double) {
        minimum = min(minimum, value)
        maximum = max(maximum, value)
        sum += value
        count += 1
    }

    public var hasData: Bool { count > 0 }
    public var mean: Double? { count > 0 ? sum / Double(count) : nil }

    /// Reihenfolge der Stützstellen für eine Linie: Indizes der Abschnitte mit Daten, `nil` = Linie unterbrechen.
    /// Leere Abschnitte zwischen zwei Messungen (Quelle misst seltener, als die Abschnitte breit sind) werden
    /// überbrückt; unterbrochen wird bei ausdrücklich fehlenden Werten oder wenn länger als `bridge` Abschnitte
    /// nichts gemessen wurde (z. B. Fenster geschlossen).
    public static func drawOrder(_ buckets: [SeriesBucket], bridge: Int) -> [Int?] {
        var order: [Int?] = []
        var emptyRun = 0
        for (index, bucket) in buckets.enumerated() {
            if bucket.hasData {
                if emptyRun > bridge, !order.isEmpty { order.append(nil) }
                emptyRun = 0
                order.append(index)
            } else if bucket.gapCount > 0 {
                if let last = order.last, last != nil { order.append(nil) }
                emptyRun = 0
            } else {
                emptyRun += 1
            }
        }
        return order
    }
}

/// Zeiträume der Verlaufsdiagramme.
public enum ChartRange: Int, Sendable, CaseIterable, Identifiable {
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case oneHour = 3600

    public var id: Int { rawValue }
    public var seconds: Double { Double(rawValue) }

    /// Stützstellen der Darstellung (Min/Max je Abschnitt).
    public var buckets: Int {
        switch self {
        case .oneMinute: return 60
        case .fiveMinutes: return 150
        case .fifteenMinutes: return 180
        case .oneHour: return 240
        }
    }
}

/// „Schöne“ obere Skalengrenze für Diagramme (1, 2, 5 × 10ⁿ).
public enum NiceScale {
    public static func upperBound(for value: Double, minimum: Double = 1) -> Double {
        let v = max(value, minimum)
        let exponent = floor(log10(v))
        let base = pow(10, exponent)
        for step in [1.0, 2.0, 2.5, 5.0, 10.0] where step * base >= v {
            return step * base
        }
        return 10 * base
    }
}
