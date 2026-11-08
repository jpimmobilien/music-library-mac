import SwiftUI
import AetherCore
import AetherSystem

// =============================================================================================
// Stores: je Bereich ein ObservableObject. Eine neue CPU-Zahl zeichnet nur, was die CPU beobachtet.
// Die Ansichten lesen ausschließlich hier – sie rufen nie selbst Systemfunktionen auf.
// =============================================================================================

/// Länge der Mini-Verläufe (Messungen).
let sparklineCapacity = 60
/// Länge der Verläufe auf den Detailseiten (Messungen; bei 2 s = 10 min).
let detailCapacity = 300

@MainActor
final class CPUStore: ObservableObject {
    @Published private(set) var snapshot: CPUSnapshot?
    @Published private(set) var busyHistory = RingBuffer<Double>(capacity: sparklineCapacity)
    @Published private(set) var longBusy = RingBuffer<Double>(capacity: detailCapacity)
    @Published private(set) var longSystem = RingBuffer<Double>(capacity: detailCapacity)
    @Published private(set) var peak: Double?
    @Published private(set) var peakTime: Date?

    func apply(_ snapshot: CPUSnapshot) {
        self.snapshot = snapshot
        if let usage = snapshot.total.value {
            busyHistory.append(usage.busy)
            longBusy.append(usage.busy)
            longSystem.append(usage.system)
            if usage.busy > (peak ?? -1) {
                peak = usage.busy
                peakTime = snapshot.total.timestamp
            }
        }
    }

    func clearHistory() {
        busyHistory.removeAll()
        peak = nil
    }
}

@MainActor
final class MemoryStore: ObservableObject {
    @Published private(set) var snapshot: MemorySnapshot?
    @Published private(set) var usedHistory = RingBuffer<Double>(capacity: sparklineCapacity)
    @Published private(set) var longUsed = RingBuffer<Double>(capacity: detailCapacity)
    @Published private(set) var longCompressed = RingBuffer<Double>(capacity: detailCapacity)
    /// Speicherdruck je Messung (1 normal, 2 Warnung, 4 kritisch; 0 = unbekannt).
    @Published private(set) var longPressure = RingBuffer<Double>(capacity: detailCapacity)

    func apply(_ snapshot: MemorySnapshot) {
        self.snapshot = snapshot
        if let b = snapshot.breakdown.value {
            usedHistory.append(b.usedFraction)
            longUsed.append(b.usedFraction)
            longCompressed.append(b.physical > 0 ? Double(b.compressed) / Double(b.physical) : 0)
        }
        longPressure.append(Double(snapshot.pressure.value?.rawValue ?? 0))
    }

    func clearHistory() { usedHistory.removeAll() }
}

@MainActor
final class NetworkStore: ObservableObject {
    @Published private(set) var snapshot: NetworkSnapshot?
    @Published private(set) var downHistory = RingBuffer<Double>(capacity: sparklineCapacity)
    @Published private(set) var upHistory = RingBuffer<Double>(capacity: sparklineCapacity)
    @Published private(set) var longDown = RingBuffer<Double>(capacity: detailCapacity)
    @Published private(set) var longUp = RingBuffer<Double>(capacity: detailCapacity)

    func apply(_ snapshot: NetworkSnapshot) {
        self.snapshot = snapshot
        if let d = snapshot.download.value, let u = snapshot.upload.value {
            downHistory.append(d)
            upHistory.append(u)
            longDown.append(d)
            longUp.append(u)
        }
    }

    func clearHistory() {
        downHistory.removeAll()
        upHistory.removeAll()
    }
}

@MainActor
final class StorageStore: ObservableObject {
    @Published private(set) var snapshot: StorageSnapshot?
    /// Lese- und Schreibrate aller Datenträger (Bytes/s) für die Speicherseite.
    @Published private(set) var longRead = RingBuffer<Double>(capacity: detailCapacity)
    @Published private(set) var longWrite = RingBuffer<Double>(capacity: detailCapacity)
    @Published private(set) var peakRead: Double?
    @Published private(set) var peakWrite: Double?

    func apply(_ snapshot: StorageSnapshot) {
        self.snapshot = snapshot
        if let read = snapshot.readRate.value, let write = snapshot.writeRate.value {
            longRead.append(read)
            longWrite.append(write)
            peakRead = max(peakRead ?? 0, read)
            peakWrite = max(peakWrite ?? 0, write)
        }
    }
}

/// Verlaufslänge für Batterie und Temperatur (Messungen im 5-s-Takt: 30 min).
let slowCapacity = 360

@MainActor
final class PowerStore: ObservableObject {
    @Published private(set) var battery: BatterySnapshot?
    @Published private(set) var thermal: ThermalSnapshot?
    @Published private(set) var profiler: PowerProfilerInfo?
    @Published private(set) var profilerLoaded = false
    @Published private(set) var longPercent = RingBuffer<Double>(capacity: slowCapacity)
    @Published private(set) var longPower = RingBuffer<Double>(capacity: slowCapacity)
    @Published private(set) var longHottest = RingBuffer<Double>(capacity: slowCapacity)
    @Published private(set) var longFan = RingBuffer<Double>(capacity: slowCapacity)
    /// Verlauf je Sensorbereich (Maximum).
    @Published private(set) var groupHistory: [SensorGroup: RingBuffer<Double>] = [:]
    private var lastTimestamp: Date?

    func apply(battery: BatterySnapshot, thermal: ThermalSnapshot) {
        self.battery = battery
        self.thermal = thermal
        // Verläufe nur bei neuen Messungen (der mittlere Takt liefert dieselben Werte mehrfach)
        guard thermal.state.timestamp != lastTimestamp else { return }
        lastTimestamp = thermal.state.timestamp
        if let percent = battery.percent.value { longPercent.append(Double(percent)) }
        if let watts = battery.power.value { longPower.append(abs(watts)) }
        if let hottest = thermal.hottest { longHottest.append(hottest.celsius) }
        if let fan = thermal.fans.value?.first { longFan.append(fan.rpm) }
        if let sensors = thermal.sensors.value {
            for entry in SensorCatalog.aggregate(sensors) {
                var buffer = groupHistory[entry.group] ?? RingBuffer<Double>(capacity: slowCapacity)
                buffer.append(entry.maximum)
                groupHistory[entry.group] = buffer
            }
        }
    }

    func apply(profiler: PowerProfilerInfo?) {
        self.profiler = profiler
        profilerLoaded = true
    }
}

@MainActor
final class GPUStore: ObservableObject {
    @Published private(set) var devices: [GPUDevice] = []
    /// Die Geräteabfrage ist abgeschlossen (erfolgreich oder nicht).
    @Published private(set) var devicesLoaded = false
    @Published private(set) var devicesFailed = false
    @Published private(set) var utilization: Reading<Double>?
    @Published private(set) var history = RingBuffer<Double>(capacity: sparklineCapacity)
    @Published private(set) var longHistory = RingBuffer<Double>(capacity: detailCapacity)

    func apply(devices: [GPUDevice]?) {
        self.devices = devices ?? []
        devicesFailed = devices == nil
        devicesLoaded = true
    }

    func apply(utilization: Reading<Double>) {
        self.utilization = utilization
        if let value = utilization.value {
            history.append(value)
            longHistory.append(value)
        }
    }
}

@MainActor
final class SystemStore: ObservableObject {
    @Published private(set) var hardware = HardwareSummary()
    @Published private(set) var profiler: ProfilerHardware?
    @Published private(set) var profilerFinished = false
    @Published private(set) var pulse = Pulse.calm
    @Published private(set) var pulseInput = PulseInput()
    @Published private(set) var ownUsage: SelfUsage.Sample?
    @Published private(set) var lastUpdate: Date?

    func apply(hardware: HardwareSummary) { self.hardware = hardware }

    func apply(profiler: ProfilerHardware?) {
        self.profiler = profiler
        profilerFinished = true
        if let profiler {
            var h = hardware
            h.machineName = profiler.machineName
            h.kind = DeviceKind.from(machineName: profiler.machineName, modelIdentifier: h.modelIdentifier)
            hardware = h
        }
    }

    /// Nur veröffentlichen, was sich ändert bzw. seltener nötig ist – sonst würde jede Ansicht, die den Systemzustand
    /// beobachtet, in jedem Takt neu gezeichnet.
    func apply(pulse: Pulse, input: PulseInput, ownUsage: SelfUsage.Sample?, at date: Date) {
        if self.pulse != pulse { self.pulse = pulse }
        if let ownUsage, ownUsage != self.ownUsage { self.ownUsage = ownUsage }
        // Erklärungen des Pulses und Betriebszeit: alle 5 s genügen
        // (sofort, sobald die CPU-Auslastung erstmals berechenbar ist – sonst stünde „Wird gemessen …“ 5 s lang da)
        let firstCPU = pulseInput.cpuBusy == nil && input.cpuBusy != nil
        if firstCPU || lastUpdate.map({ date.timeIntervalSince($0) >= 5 }) ?? true {
            pulseInput = input
            lastUpdate = date
        }
    }
}
