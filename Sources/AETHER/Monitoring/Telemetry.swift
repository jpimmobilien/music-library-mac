import SwiftUI
import AetherCore
import AetherSystem

// =============================================================================================
// Monitoring 2.0 – Veröffentlichung im Hauptthread.
//
// Je Messgröße zwei kleine beobachtbare Objekte:
//   MetricValue   die Anzeige (Rohwert, geglättet, Spitze) – veröffentlicht NUR, wenn sich die gerundete Darstellung
//                 ändert. Große Zahlen zeichnen sich dadurch nicht in jedem Takt neu und flackern nicht.
//   MetricSeries  der zeitbasierte Verlauf (1 h) für Diagramme – ändert sich mit jeder Messung.
// So beobachtet jede Ansicht genau das, was sie zeigt.
// =============================================================================================

/// Verlaufsdauer aller Messgrößen (Sekunden).
let telemetryRetention: Double = 3_600

@MainActor
final class MetricValue: ObservableObject {
    let id: MetricID
    /// Einheit (bestimmt das Anzeigeraster). Legt eine Ansicht den Kanal vor der ersten Messung an, übernimmt die
    /// Messung ihre Einheit.
    private(set) var unit: MetricUnit
    @Published private(set) var value: SmoothedValue?
    @Published private(set) var isAvailable = false
    private var lastKey: Int64?
    private var lastPeakKey: Int64?

    init(id: MetricID, unit: MetricUnit) {
        self.id = id
        self.unit = unit
    }

    /// Angezeigter Wert je nach Einstellung „Rohwerte zeigen“.
    func display(raw: Bool) -> Double? {
        guard let value else { return nil }
        return raw ? value.raw : value.smoothed
    }

    /// - Returns: true, wenn veröffentlicht wurde
    @discardableResult
    func ingest(_ newValue: SmoothedValue?, raw: Bool) -> Bool {
        guard let newValue else {
            guard isAvailable else { return false }
            isAvailable = false
            lastKey = nil
            return true
        }
        let key = DisplayQuantizer.key(raw ? newValue.raw : newValue.smoothed, unit: unit)
        let peakKey = newValue.peak.map { DisplayQuantizer.key($0, unit: unit) }
        guard key != lastKey || peakKey != lastPeakKey || !isAvailable else { return false }
        lastKey = key
        lastPeakKey = peakKey
        value = newValue
        if !isAvailable { isAvailable = true }
        return true
    }

    func resetDisplayGate() {
        lastKey = nil
    }

    func adopt(unit newUnit: MetricUnit) {
        guard newUnit != unit else { return }
        unit = newUnit
        lastKey = nil
        lastPeakKey = nil
    }
}

@MainActor
final class MetricSeries: ObservableObject {
    let id: MetricID
    /// Rohwerte (ehrlicher Verlauf, für die Bänder Min…Max)
    private(set) var raw: TimeSeries
    /// Geglättete Werte (ruhige Linie)
    private(set) var smooth: TimeSeries
    /// Zeitpunkt der letzten Messung (Systemlaufzeit)
    private(set) var now: Double = 0
    private(set) var latest: SmoothedValue?
    @Published private(set) var revision = 0

    init(id: MetricID, capacity: Int) {
        self.id = id
        raw = TimeSeries(capacity: capacity)
        smooth = TimeSeries(capacity: capacity)
    }

    func append(_ value: SmoothedValue?, at time: Double) {
        raw.append(value?.raw, at: time)
        smooth.append(value?.smoothed, at: time)
        latest = value
        now = time
        revision &+= 1
    }
}

/// Eine Messgröße: Anzeige und Verlauf.
@MainActor
final class MetricChannel {
    let value: MetricValue
    let series: MetricSeries

    init(id: MetricID, unit: MetricUnit, capacity: Int) {
        value = MetricValue(id: id, unit: unit)
        series = MetricSeries(id: id, capacity: capacity)
    }
}

/// Geglättete Auslastung aller Kerne als eine Liste (für Kernansichten) – veröffentlicht nur bei sichtbarer Änderung
/// (Raster 2 %).
@MainActor
final class CoreActivity: ObservableObject {
    @Published private(set) var levels: [Double?] = []
    private var keys: [Int] = []

    func update(_ values: [Double?]) {
        let newKeys = values.map { $0.map { Int(($0 * 50).rounded()) } ?? -1 }
        guard newKeys != keys else { return }
        keys = newKeys
        levels = values
    }
}

/// Alle Messgrößen. Kanäle entstehen beim ersten Zugriff (Ansicht) oder bei der ersten Messung.
@MainActor
final class Telemetry: ObservableObject {
    /// Alle Kerne zusammen (Lichtsäulen, Kernraster)
    let cores = CoreActivity()
    private var channels: [MetricID: MetricChannel] = [:]
    private var units: [MetricID: MetricUnit] = [:]
    /// Rohwerte statt geglätteter Werte anzeigen (Einstellung).
    var showRaw = false {
        didSet {
            guard showRaw != oldValue else { return }
            for channel in channels.values { channel.value.resetDisplayGate() }
        }
    }
    /// Kapazität der Verläufe in Messungen (hängt vom Grundtakt ab).
    var capacity = Int(telemetryRetention) + 60
    /// Anzahl der Kerne (für die Kernansicht) – veröffentlicht, sobald bekannt.
    @Published private(set) var coreCount = 0
    @Published private(set) var fanCount = 0
    private var publishCount = 0

    func channel(_ id: MetricID, unit: MetricUnit = .fraction) -> MetricChannel {
        if let existing = channels[id] { return existing }
        let channel = MetricChannel(id: id, unit: units[id] ?? unit, capacity: capacity)
        channels[id] = channel
        return channel
    }

    func value(_ id: MetricID, unit: MetricUnit = .fraction) -> MetricValue { channel(id, unit: unit).value }
    func series(_ id: MetricID, unit: MetricUnit = .fraction) -> MetricSeries { channel(id, unit: unit).series }

    func ingest(_ frame: TelemetryFrame) {
        var cores = 0
        var fans = 0
        var coreValues: [Double?] = []
        for entry in frame.entries {
            if entry.id.raw.hasPrefix("cpu.core.") {
                coreValues.append(entry.value.map { showRaw ? $0.raw : $0.smoothed })
            }
            units[entry.id] = entry.unit
            let channel = self.channel(entry.id, unit: entry.unit)
            channel.value.adopt(unit: entry.unit)
            if channel.value.ingest(entry.value, raw: showRaw) { publishCount += 1 }
            channel.series.append(entry.value, at: frame.time)
            if entry.id.raw.hasPrefix("cpu.core.") { cores += 1 }
            if entry.id.raw.hasPrefix("thermal.fan.") { fans += 1 }
        }
        if !coreValues.isEmpty { self.cores.update(coreValues) }
        if cores > 0, cores != coreCount { coreCount = cores }
        if fans > 0, fans != fanCount { fanCount = fans }
    }

    /// Veröffentlichungen seit dem letzten Aufruf (Diagnose).
    func takePublishCount() -> Int {
        defer { publishCount = 0 }
        return publishCount
    }

    /// Bei geändertem Grundtakt: Verläufe behalten ihre Zeitstempel, nur die Kapazität neuer Kanäle passt sich an.
    func configure(interval: Double) {
        capacity = Int(telemetryRetention / max(0.5, interval)) + 60
    }
}

/// Diagnosemodus: Eigenverbrauch und Zeiten der Messmaschine.
@MainActor
final class EngineDiagnostics: ObservableObject {
    struct Snapshot: Equatable {
        var ownCPU: Double?
        var ownMemory: UInt64?
        var interval: Double = 1
        var tickMs: Double = 0
        var applyMs: Double = 0
        var lateMs: Double = 0
        var activeSources = 0
        var publishesPerSecond: Double = 0
        var processesActive = false
        var sources: [String: Double] = [:]
        /// Ausgewertete Messungen pro Sekunde (Takt + Sofortmessungen)
        var ticksPerSecond: Double = 0
        /// Meldungen von macOS über geänderte Stromquellen seit dem Start
        var powerNotifications = 0
    }

    @Published private(set) var snapshot = Snapshot()
    /// Nur wenn eingeschaltet wird veröffentlicht (sonst nichts zeichnen).
    var enabled = false
    private var tickMs = AsymmetricEMA(rise: 4, fall: 4)
    private var applyMs = AsymmetricEMA(rise: 4, fall: 4)
    private var late = AsymmetricEMA(rise: 4, fall: 4)
    private var publishes = AsymmetricEMA(rise: 4, fall: 4)
    private var sourceMs: [String: AsymmetricEMA] = [:]
    private var lastPublish: Double = 0
    private var draft = Snapshot()
    private var records = 0
    /// Von der Messmaschine gezählt (Stromquellen-Meldungen).
    var powerNotifications = 0

    func record(_ timing: TickTiming, applyMs apply: Double, publishes count: Int, ownUsage: SelfUsage.Sample?,
                interval: Double, processesActive: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        draft.tickMs = tickMs.update(timing.totalMs, at: now)
        draft.applyMs = applyMs.update(apply, at: now)
        draft.lateMs = late.update(timing.lateMs, at: now)
        draft.publishesPerSecond = publishes.update(Double(count) / max(0.5, interval), at: now)
        draft.interval = interval
        draft.activeSources = max(draft.activeSources, timing.activeSources)
        draft.processesActive = processesActive
        for (name, ms) in timing.sources {
            var ema = sourceMs[name] ?? AsymmetricEMA(rise: 4, fall: 4)
            draft.sources[name] = ema.update(ms, at: now)
            sourceMs[name] = ema
        }
        if let ownUsage {
            draft.ownCPU = ownUsage.cpu
            draft.ownMemory = ownUsage.footprint
        }
        records += 1
        guard enabled, now - lastPublish >= 1 else { return }
        draft.ticksPerSecond = lastPublish > 0 ? Double(records) / (now - lastPublish) : 0
        draft.powerNotifications = powerNotifications
        records = 0
        lastPublish = now
        snapshot = draft
        draft.activeSources = 0
    }
}
