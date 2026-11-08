import Foundation
import AppKit
import IOKit.ps
import AetherCore
import AetherSystem

// =============================================================================================
// Messmaschine (Monitoring 2.0): ein Grundtakt auf einer eigenen seriellen Warteschlange, je Quelle ein eigener
// Takt (siehe `Samplers`). Systemabfragen und Glättung laufen nie im Hauptthread; der Hauptthread veröffentlicht
// nur geänderte Anzeigewerte (`Telemetry`). Pausiert, wenn nichts davon sichtbar ist.
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
    /// Lokaler Verlauf (nur bei eingeschalteter Einstellung).
    let history = HistoryStore()
    /// Geglättete Anzeigewerte und zeitbasierte Verläufe je Messgröße (Monitoring 2.0).
    let telemetry = Telemetry()
    /// Eigenverbrauch und Takt-Zeiten (Diagnosemodus).
    let diagnostics = EngineDiagnostics()

    private let queue = DispatchQueue(label: "aether.monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var interval: RefreshInterval = .oneSecond
    private var powerNotification: CFRunLoopSource?
    private(set) var isRunning = false
    private var observers: [NSObjectProtocol] = []

    // Nur auf `queue` benutzt
    private let samplers = Samplers()

    init() {
        observePowerSources()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshVolumes() }
            })
        }
    }

    /// macOS meldet Änderungen an Netzteil und Ladezustand – die Batterie wird dann sofort neu gelesen, statt bis
    /// zum nächsten 10-s-Takt zu warten.
    private func observePowerSources() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let engine = Unmanaged<MonitorEngine>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { engine.powerSourcesChanged() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerNotification = source
    }

    private func powerSourcesChanged() {
        queue.async { [samplers] in samplers.batteryDirty = true }
        if isRunning { refreshNow() }
    }

    /// Einmalige Angaben laden (sysctl sofort, system_profiler im Hintergrund).
    func loadStaticInfo() {
        let basic = HardwareSource.basic()
        system.apply(hardware: basic)
        let isVirtual = basic.isVirtualMachine
        queue.async { [samplers] in samplers.isVirtualMachine = isVirtual }
        refreshPowerProfiler()
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
        telemetry.configure(interval: interval.seconds)
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

    /// Batterieangaben aus den Systeminformationen (Apples Zustand und maximale Kapazität) – im Hintergrund.
    func refreshPowerProfiler() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let info = HardwareSource.run("/usr/sbin/system_profiler", ["SPPowerDataType", "-json", "-detailLevel", "mini"], timeout: 25)
                .flatMap(PowerProfilerParser.parse)
            Task { @MainActor in self?.power.apply(profiler: info) }
        }
    }

    /// Sensoren über SMC lesen (Einstellung).
    func setSMCEnabled(_ enabled: Bool) {
        queue.async { [samplers] in samplers.smcEnabled = enabled }
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
        telemetry.configure(interval: interval.seconds)
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
        let started = DispatchTime.now().uptimeNanoseconds
        cpu.apply(result.cpu)
        if let memory = result.memory { self.memory.apply(memory) }
        network.apply(result.network)
        if let storage = result.storage { self.storage.apply(storage) }
        if let battery = result.battery, let thermal = result.thermal { power.apply(battery: battery, thermal: thermal) }
        if let gpu = result.gpuUtilization { self.gpu.apply(utilization: gpu) }
        if let tick = result.processes { processes.apply(snapshot: tick.snapshot, cpu: tick.cpu) }
        system.apply(pulse: result.pulse, input: result.pulseInput, ownUsage: result.ownUsage, at: result.date)
        telemetry.ingest(result.frame)
        history.record(result)
        let applyMs = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        diagnostics.record(result.timing, applyMs: applyMs, publishes: telemetry.takePublishCount(), ownUsage: result.ownUsage,
                           interval: interval.seconds, processesActive: result.processes != nil)
    }
}

/// Ergebnis eines Takts. Nicht jede Messgröße wird in jedem Takt gemessen (eigene Takte je Quelle) –
/// optionale Felder sind dann `nil` und die Stores behalten ihren Stand.
struct TickResult: Sendable {
    var date: Date
    var cpu: CPUSnapshot
    var memory: MemorySnapshot?
    var network: NetworkSnapshot
    var storage: StorageSnapshot?
    var battery: BatterySnapshot?
    var thermal: ThermalSnapshot?
    var gpuUtilization: Reading<Double>?
    var pulse: Pulse
    var pulseInput: PulseInput
    var ownUsage: SelfUsage.Sample?
    var processes: ProcessTick?
    /// Geglättete Werte für die Anzeige (Rohwert, Glättung, Spitze).
    var frame: TelemetryFrame
    /// Dauer je Quelle (ms) und Verspätung des Takts – für den Diagnosemodus.
    var timing: TickTiming
}

struct ProcessTick: Sendable {
    var snapshot: ProcessSnapshot
    var cpu: [ProcessIdentity: Double]
}

/// Ein Satz geglätteter Werte (Zeit = Systemlaufzeit in Sekunden).
struct TelemetryFrame: Sendable {
    var time: Double
    var entries: [TelemetryEntry] = []
}

struct TelemetryEntry: Sendable {
    var id: MetricID
    var unit: MetricUnit
    /// `nil` = in diesem Takt nicht verfügbar (Lücke im Verlauf)
    var value: SmoothedValue?
}

struct TickTiming: Sendable {
    var sources: [String: Double] = [:]
    var totalMs: Double = 0
    /// Abweichung vom geplanten Zeitpunkt (ms, positiv = verspätet)
    var lateMs: Double = 0
    var activeSources = 0
}

/// Alle Messquellen. Nur auf der Warteschlange der Messmaschine benutzt (deshalb unchecked Sendable).
///
/// Eigene Takte je Quelle (Grundtakt = Einstellung, Standard 1 s):
///   jeder Takt     CPU (gesamt und je Kern), Netz, SSD-Aktivität
///   ≥ 2 s          Arbeitsspeicher, GPU-Auslastung, Prozesse (nur wenn sichtbar), Eigenverbrauch
///   ≥ 3 s          Thermalstatus, SMC-Sensoren und Lüfter
///   ≥ 10 s         Batterie – und sofort nach einer Benachrichtigung von macOS (Netzteil, Ladezustand)
///   ≥ 30 s         Volumes – und sofort beim Ein-/Aushängen
final class Samplers: @unchecked Sendable {
    private let cpu = CPUSource()
    private let memory = MemorySource()
    private let network = NetworkSource()
    private let storage = StorageSource()
    private let selfUsage = SelfUsage()
    private let processSource = ProcessSource()
    private let smcSource = SMCSource()
    var smcEnabled = true
    var isVirtualMachine = false
    private var cpuTracker = ProcessCPUTracker()
    var wantProcesses = false
    private var evaluator = PulseEvaluator(sampleInterval: 1)
    private var lastSlow: Double = -.infinity
    private var lastThermal: Double = -.infinity
    private var lastBattery: Double = -.infinity
    private var lastMemory: Double = -.infinity
    private var lastGPU: Double = -.infinity
    private var lastProcesses: Double = -.infinity
    private var lastOwn: Double = -.infinity
    private var lastTickUptime: Double?
    private var volumes: [VolumeInfo] = []
    private var battery: BatterySnapshot?
    private var thermal: ThermalSnapshot?
    private var memorySnapshot: MemorySnapshot?
    private var ownUsage: SelfUsage.Sample?
    private var smoothers: [MetricID: MetricSmoother] = [:]
    var forceVolumes = false
    /// Von der Batterie-Benachrichtigung gesetzt: beim nächsten Takt sofort messen.
    var batteryDirty = false
    var pulseInterval: Double = 1 {
        didSet { evaluator.sampleInterval = max(0.5, pulseInterval) }
    }

    /// Fällig, wenn seit der letzten Messung `every` Sekunden vergangen sind (mit etwas Spielraum für den Takt).
    private func due(_ last: inout Double, every: Double, uptime: Double, force: Bool) -> Bool {
        guard force || uptime - last >= every - 0.25 else { return false }
        last = uptime
        return true
    }

    private func smoothed(_ id: MetricID, _ unit: MetricUnit, _ raw: Double?, profile: SmoothingProfile, at time: Double) -> TelemetryEntry {
        guard let raw, raw.isFinite else { return TelemetryEntry(id: id, unit: unit, value: nil) }
        var smoother = smoothers[id] ?? MetricSmoother(profile: profile)
        let value = smoother.update(raw: raw, at: time)
        smoothers[id] = smoother
        return TelemetryEntry(id: id, unit: unit, value: value)
    }

    /// `interval == 0`: alles sofort messen (Bereich geöffnet, Selbsttest).
    func tick(interval: Double) -> TickResult {
        let tickStart = DispatchTime.now().uptimeNanoseconds
        let now = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        let force = interval == 0
        var timing = TickTiming()
        if let last = lastTickUptime, interval > 0 {
            timing.lateMs = max(0, (uptime - last - interval) * 1_000)
        }
        lastTickUptime = uptime
        func timed<T>(_ name: String, _ body: () -> T) -> T {
            let t0 = DispatchTime.now().uptimeNanoseconds
            let result = body()
            timing.sources[name] = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
            return result
        }
        var frame = TelemetryFrame(time: uptime)

        // Jeder Takt: CPU, Netz, SSD-Aktivität
        let cpuSnapshot = timed("cpu") { cpu.sample(at: now) }
        let total = cpuSnapshot.total.value
        frame.entries.append(smoothed(.cpuTotal, .fraction, total?.busy, profile: .cpu, at: uptime))
        frame.entries.append(smoothed(.cpuUser, .fraction, total?.user, profile: .cpu, at: uptime))
        frame.entries.append(smoothed(.cpuSystem, .fraction, total?.system, profile: .cpu, at: uptime))
        for (index, core) in cpuSnapshot.perCore.enumerated() {
            frame.entries.append(smoothed(.core(index), .fraction, core?.busy, profile: .core, at: uptime))
        }

        let networkSnapshot = timed("network") { network.sample(at: now, uptime: uptime) }
        frame.entries.append(smoothed(.networkDown, .bytesPerSecond, networkSnapshot.download.value, profile: .throughput, at: uptime))
        frame.entries.append(smoothed(.networkUp, .bytesPerSecond, networkSnapshot.upload.value, profile: .throughput, at: uptime))

        if forceVolumes || due(&lastSlow, every: 30, uptime: uptime, force: force) {
            volumes = timed("volumes") { StorageSource.volumes() }
            lastSlow = uptime
            forceVolumes = false
        }
        let storageSnapshot = timed("disk") { storage.sample(volumes: volumes, at: now, uptime: uptime) }
        frame.entries.append(smoothed(.diskRead, .bytesPerSecond, storageSnapshot.readRate.value, profile: .throughput, at: uptime))
        frame.entries.append(smoothed(.diskWrite, .bytesPerSecond, storageSnapshot.writeRate.value, profile: .throughput, at: uptime))

        // ≥ 2 s: Arbeitsspeicher, GPU
        var freshMemory: MemorySnapshot?
        if due(&lastMemory, every: 2, uptime: uptime, force: force) || memorySnapshot == nil {
            let m = timed("memory") { memory.sample(at: now) }
            memorySnapshot = m
            freshMemory = m
            if let b = m.breakdown.value {
                frame.entries.append(smoothed(.memoryUsed, .bytes, Double(b.used), profile: .memory, at: uptime))
                frame.entries.append(smoothed(.memoryCompressed, .bytes, Double(b.compressed), profile: .memory, at: uptime))
            } else {
                frame.entries.append(TelemetryEntry(id: .memoryUsed, unit: .bytes, value: nil))
            }
            frame.entries.append(smoothed(.swapUsed, .bytes, m.swap.value.map { Double($0.used) }, profile: .memory, at: uptime))
        }
        var gpu: Reading<Double>?
        if due(&lastGPU, every: 2, uptime: uptime, force: force) {
            let g = timed("gpu") { GPUSource.utilization(at: now) }
            gpu = g
            frame.entries.append(smoothed(.gpu, .fraction, g.value, profile: .gpu, at: uptime))
        }

        // ≥ 10 s oder nach Benachrichtigung: Batterie (keine Glättung – nur echte Änderungen)
        var freshBattery: BatterySnapshot?
        if batteryDirty || due(&lastBattery, every: 10, uptime: uptime, force: force) || battery == nil {
            let b = timed("battery") { BatterySource.sample(at: now) }
            battery = b
            freshBattery = b
            batteryDirty = false
            lastBattery = uptime
            frame.entries.append(smoothed(.batteryPercent, .percentInteger, b.percent.value.map(Double.init), profile: .none, at: uptime))
            frame.entries.append(smoothed(.batteryPower, .watts, b.power.value.map(abs), profile: .power, at: uptime))
        }

        // ≥ 3 s: Thermik und SMC
        var freshThermal: ThermalSnapshot?
        if due(&lastThermal, every: 3, uptime: uptime, force: force) || thermal == nil {
            let smc = timed("smc") {
                smcEnabled
                    ? smcSource.sample(at: now, isVirtualMachine: isVirtualMachine)
                    : (Reading<[ThermalSensor]>(unavailable: .disabledInSettings, source: .smcSensors, at: now),
                       Reading<[FanReading]>(unavailable: .disabledInSettings, source: .smcFans, at: now))
            }
            let t = ThermalSource.sample(batteryTemperature: battery?.temperature
                                         ?? Reading(unavailable: .notPresent, source: .batteryTemperature, at: now),
                                         smc: smc, at: now)
            thermal = t
            freshThermal = t
            frame.entries.append(smoothed(.hottest, .celsius, t.hottest?.celsius, profile: .temperature, at: uptime))
            for fan in t.fans.value ?? [] {
                frame.entries.append(smoothed(.fan(fan.index), .rpm, fan.rpm, profile: .fan, at: uptime))
            }
        }

        let startup = storageSnapshot.startup
        let input = PulseInput(cpuBusy: total?.busy,
                               pressure: memorySnapshot?.pressure.value,
                               swapUsed: memorySnapshot?.swap.value?.used,
                               physicalMemory: memorySnapshot?.breakdown.value?.physical,
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
        if wantProcesses, due(&lastProcesses, every: 2, uptime: uptime, force: force),
           let snapshot = timed("processes", { processSource.sample(at: now) }) {
            processTick = ProcessTick(snapshot: snapshot, cpu: cpuTracker.update(snapshot.samples, time: uptime))
        }
        var freshOwn: SelfUsage.Sample?
        if due(&lastOwn, every: 2, uptime: uptime, force: force) {
            let own = selfUsage.sample(uptime: uptime)
            ownUsage = own
            freshOwn = own
        }

        let powerFresh = freshBattery != nil || freshThermal != nil
        timing.activeSources = timing.sources.count
        timing.totalMs = Double(DispatchTime.now().uptimeNanoseconds - tickStart) / 1_000_000
        return TickResult(date: now, cpu: cpuSnapshot, memory: freshMemory, network: networkSnapshot, storage: storageSnapshot,
                          battery: powerFresh ? battery : nil,
                          thermal: powerFresh ? thermal : nil,
                          gpuUtilization: gpu, pulse: pulse, pulseInput: input,
                          ownUsage: freshOwn, processes: processTick, frame: frame, timing: timing)
    }
}
