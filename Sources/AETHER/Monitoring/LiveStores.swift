import SwiftUI
import AetherCore
import AetherSystem

// =============================================================================================
// Stores: je Bereich ein ObservableObject. Eine neue CPU-Zahl zeichnet nur, was die CPU beobachtet.
// Die Ansichten lesen ausschließlich hier – sie rufen nie selbst Systemfunktionen auf.
// =============================================================================================

/// Länge der Mini-Verläufe (Messungen).
let sparklineCapacity = 60

@MainActor
final class CPUStore: ObservableObject {
    @Published private(set) var snapshot: CPUSnapshot?
    @Published private(set) var busyHistory = RingBuffer<Double>(capacity: sparklineCapacity)
    @Published private(set) var peak: Double?

    func apply(_ snapshot: CPUSnapshot) {
        self.snapshot = snapshot
        if let usage = snapshot.total.value {
            busyHistory.append(usage.busy)
            peak = max(peak ?? 0, usage.busy)
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

    func apply(_ snapshot: MemorySnapshot) {
        self.snapshot = snapshot
        if let b = snapshot.breakdown.value { usedHistory.append(b.usedFraction) }
    }

    func clearHistory() { usedHistory.removeAll() }
}

@MainActor
final class NetworkStore: ObservableObject {
    @Published private(set) var snapshot: NetworkSnapshot?
    @Published private(set) var downHistory = RingBuffer<Double>(capacity: sparklineCapacity)
    @Published private(set) var upHistory = RingBuffer<Double>(capacity: sparklineCapacity)

    func apply(_ snapshot: NetworkSnapshot) {
        self.snapshot = snapshot
        if let d = snapshot.download.value, let u = snapshot.upload.value {
            downHistory.append(d)
            upHistory.append(u)
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

    func apply(_ snapshot: StorageSnapshot) { self.snapshot = snapshot }
}

@MainActor
final class PowerStore: ObservableObject {
    @Published private(set) var battery: BatterySnapshot?
    @Published private(set) var thermal: ThermalSnapshot?

    func apply(battery: BatterySnapshot, thermal: ThermalSnapshot) {
        self.battery = battery
        self.thermal = thermal
    }
}

@MainActor
final class GPUStore: ObservableObject {
    @Published private(set) var devices: [GPUDevice] = []
    @Published private(set) var utilization: Reading<Double>?
    @Published private(set) var history = RingBuffer<Double>(capacity: sparklineCapacity)

    func apply(devices: [GPUDevice]) { self.devices = devices }

    func apply(utilization: Reading<Double>) {
        self.utilization = utilization
        if let value = utilization.value { history.append(value) }
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

    func apply(pulse: Pulse, input: PulseInput, ownUsage: SelfUsage.Sample?, at date: Date) {
        if self.pulse != pulse { self.pulse = pulse }
        pulseInput = input
        self.ownUsage = ownUsage
        lastUpdate = date
    }
}
