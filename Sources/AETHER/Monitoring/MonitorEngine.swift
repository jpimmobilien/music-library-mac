import Foundation
import AppKit
import AetherCore
import AetherSystem

// =============================================================================================
// Messmaschine: ein Takt auf einer eigenen seriellen Warteschlange. Systemabfragen laufen nie im Hauptthread.
//
//   schnell (Intervall)   CPU, Speicher, Netz, SSD-Aktivität, GPU-Auslastung
//   mittel (≥ 5 s)        Batterie, Thermalstatus
//   langsam (≥ 30 s)      Volumes (zusätzlich sofort bei Ein-/Aushängen)
//   einmalig              Hardware (sysctl sofort, system_profiler im Hintergrund), GPU-Geräte
//
// Pausiert, wenn das Fenster nicht sichtbar ist (verdeckt, minimiert, App ausgeblendet).
// =============================================================================================

@MainActor
final class MonitorEngine {
    let cpu = CPUStore()
    let memory = MemoryStore()
    let network = NetworkStore()
    let storage = StorageStore()
    let power = PowerStore()
    let gpu = GPUStore()
    let system = SystemStore()
    let processes = ProcessStore()

    private let queue = DispatchQueue(label: "aether.monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var interval: RefreshInterval = .twoSeconds
    private(set) var isRunning = false
    private var observers: [NSObjectProtocol] = []

    // Nur auf `queue` benutzt
    private let samplers = Samplers()

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshVolumes() }
            })
        }
    }

    /// Einmalige Angaben laden (sysctl sofort, system_profiler im Hintergrund).
    func loadStaticInfo() {
        let basic = HardwareSource.basic()
        system.apply(hardware: basic)
        let appleSilicon = basic.isAppleSilicon
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let devices = GPUSource.devices(appleSilicon: appleSilicon)
            Task { @MainActor in self?.gpu.apply(devices: devices) }
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let profiler = HardwareSource.profiler()
            Task { @MainActor in self?.system.apply(profiler: profiler) }
        }
    }

    func start(interval: RefreshInterval) {
        self.interval = interval
        guard !isRunning else {
            reschedule()
            return
        }
        isRunning = true
        reschedule()
    }

    func stop() {
        isRunning = false
        timer?.cancel()
        timer = nil
    }

    /// Prozessliste nur messen, wenn ein sichtbarer Bereich sie braucht (Aktivität, CPU, Arbeitsspeicher).
    func setProcessDemand(_ wanted: Bool) {
        queue.async { [samplers] in samplers.wantProcesses = wanted }
        if wanted && isRunning { refreshNow() }
    }

    /// Sofort eine Messung (z. B. beim Öffnen eines Bereichs), ohne auf den nächsten Takt zu warten.
    func refreshNow() {
        queue.async { [weak self, samplers] in
            let result = samplers.tick(interval: 0)
            Task { @MainActor in self?.apply(result) }
        }
    }

    func setInterval(_ interval: RefreshInterval) {
        guard interval != self.interval else { return }
        self.interval = interval
        samplers.pulseInterval = interval.seconds
        if isRunning { reschedule() }
    }

    private func reschedule() {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let seconds = interval.seconds
        // Toleranz 10 % – erlaubt dem System, Aufwachvorgänge zu bündeln (Energie).
        timer.schedule(deadline: .now(), repeating: seconds, leeway: .milliseconds(Int(seconds * 100)))
        timer.setEventHandler(handler: Self.makeTickHandler(samplers: samplers, seconds: seconds) { [weak self] result in
            Task { @MainActor in self?.apply(result) }
        })
        self.timer = timer
        samplers.pulseInterval = seconds
        timer.resume()
    }

    /// Der Takt läuft auf der Messwarteschlange – bewusst außerhalb des Hauptakteurs erzeugt.
    nonisolated private static func makeTickHandler(samplers: Samplers, seconds: Double,
                                                    deliver: @escaping @Sendable (TickResult) -> Void) -> @Sendable () -> Void {
        return {
            deliver(samplers.tick(interval: seconds))
        }
    }

    /// Sofort messen (z. B. nach Ein-/Aushängen eines Laufwerks).
    func refreshVolumes() {
        queue.async { [weak self, samplers] in
            samplers.forceVolumes = true
            let result = samplers.tick(interval: 0)
            Task { @MainActor in self?.apply(result) }
        }
    }

    /// Für Selbsttest und Fotos: synchron mehrere Messungen ausführen.
    func sampleNow(count: Int, spacing: TimeInterval) async {
        for index in 0..<count {
            let result = await withCheckedContinuation { (continuation: CheckedContinuation<TickResult, Never>) in
                queue.async { [samplers] in
                    continuation.resume(returning: samplers.tick(interval: spacing))
                }
            }
            apply(result)
            if index < count - 1 { try? await Task.sleep(nanoseconds: UInt64(spacing * 1_000_000_000)) }
        }
    }

    private func apply(_ result: TickResult) {
        cpu.apply(result.cpu)
        memory.apply(result.memory)
        network.apply(result.network)
        if let storage = result.storage { self.storage.apply(storage) }
        if let battery = result.battery, let thermal = result.thermal { power.apply(battery: battery, thermal: thermal) }
        gpu.apply(utilization: result.gpuUtilization)
        if let tick = result.processes { processes.apply(snapshot: tick.snapshot, cpu: tick.cpu) }
        system.apply(pulse: result.pulse, input: result.pulseInput, ownUsage: result.ownUsage, at: result.date)
    }
}

/// Ergebnis eines Takts.
struct TickResult: Sendable {
    var date: Date
    var cpu: CPUSnapshot
    var memory: MemorySnapshot
    var network: NetworkSnapshot
    var storage: StorageSnapshot?
    var battery: BatterySnapshot?
    var thermal: ThermalSnapshot?
    var gpuUtilization: Reading<Double>
    var pulse: Pulse
    var pulseInput: PulseInput
    var ownUsage: SelfUsage.Sample
    var processes: ProcessTick?
}

struct ProcessTick: Sendable {
    var snapshot: ProcessSnapshot
    var cpu: [ProcessIdentity: Double]
}

/// Alle Messquellen. Nur auf der Warteschlange der Messmaschine benutzt (deshalb unchecked Sendable).
final class Samplers: @unchecked Sendable {
    private let cpu = CPUSource()
    private let memory = MemorySource()
    private let network = NetworkSource()
    private let storage = StorageSource()
    private let selfUsage = SelfUsage()
    private let processSource = ProcessSource()
    private var cpuTracker = ProcessCPUTracker()
    var wantProcesses = false
    private var evaluator = PulseEvaluator(sampleInterval: 2)
    private var lastSlow: Double = -.infinity
    private var lastMedium: Double = -.infinity
    private var volumes: [VolumeInfo] = []
    private var battery: BatterySnapshot?
    private var thermal: ThermalSnapshot?
    var forceVolumes = false
    var pulseInterval: Double = 2 {
        didSet { evaluator.sampleInterval = max(0.5, pulseInterval) }
    }

    func tick(interval: Double) -> TickResult {
        let now = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        let cpuSnapshot = cpu.sample(at: now)
        let memorySnapshot = memory.sample(at: now)
        let networkSnapshot = network.sample(at: now, uptime: uptime)

        var storageSnapshot: StorageSnapshot?
        if forceVolumes || uptime - lastSlow >= 30 {
            volumes = StorageSource.volumes()
            lastSlow = uptime
            forceVolumes = false
        }
        storageSnapshot = storage.sample(volumes: volumes, at: now, uptime: uptime)

        if uptime - lastMedium >= max(5, interval) || battery == nil {
            let b = BatterySource.sample(at: now)
            battery = b
            thermal = ThermalSource.sample(batteryTemperature: b.temperature, at: now)
            lastMedium = uptime
        }

        let gpu = GPUSource.utilization(at: now)
        let startup = storageSnapshot?.startup
        let input = PulseInput(cpuBusy: cpuSnapshot.total.value?.busy,
                               pressure: memorySnapshot.pressure.value,
                               swapUsed: memorySnapshot.swap.value?.used,
                               physicalMemory: memorySnapshot.breakdown.value?.physical,
                               thermal: thermal?.state.value,
                               startupAvailable: startup?.effectiveAvailable,
                               startupCapacity: startup?.capacity,
                               networkBytesPerSecond: {
                                   guard let d = networkSnapshot.download.value, let u = networkSnapshot.upload.value else { return nil }
                                   return d + u
                               }(),
                               batteryServiceRecommended: battery?.serviceRecommended)
        let pulse = evaluator.evaluate(input)
        var processTick: ProcessTick?
        if wantProcesses, let snapshot = processSource.sample(at: now) {
            processTick = ProcessTick(snapshot: snapshot, cpu: cpuTracker.update(snapshot.samples, time: uptime))
        }
        return TickResult(date: now, cpu: cpuSnapshot, memory: memorySnapshot, network: networkSnapshot, storage: storageSnapshot,
                          battery: battery, thermal: thermal, gpuUtilization: gpu, pulse: pulse, pulseInput: input,
                          ownUsage: selfUsage.sample(uptime: uptime), processes: processTick)
    }
}
