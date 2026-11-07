import Darwin
import Foundation
import AetherCore

/// CPU-Auslastung aus den Rechenzeit-Zählern des Kernels (öffentliche Mach-Schnittstelle).
public final class CPUSource {
    private let host = mach_host_self()
    private var previous: [CPUTicks]?

    public init() {}

    /// Aktuelle Zählerstände aller logischen Kerne.
    public func readTicks() -> [CPUTicks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let stride = Int(CPU_STATE_MAX)
        var ticks: [CPUTicks] = []
        ticks.reserveCapacity(Int(cpuCount))
        for core in 0..<Int(cpuCount) {
            let base = core * stride
            ticks.append(CPUTicks(user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                                  system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                                  idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                                  nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])))
        }
        return ticks
    }

    /// Eine Messung: Differenz zur vorigen. Die erste Messung liefert „wartet auf zweite Messung“.
    public func sample(at date: Date = Date()) -> CPUSnapshot {
        let load = Self.loadAverage(at: date)
        guard let current = readTicks() else {
            return CPUSnapshot(total: Reading(unavailable: .queryFailed, source: .cpuTicks, at: date), perCore: [], loadAverage: load)
        }
        let last = self.previous
        self.previous = current
        guard let last, last.count == current.count else {
            return CPUSnapshot(total: Reading(unavailable: .awaitingSecondSample, source: .cpuTicks, at: date),
                               perCore: current.map { _ in nil }, loadAverage: load)
        }
        let total: Reading<CPUUsage>
        if let usage = CPUMath.total(from: last, to: current) {
            total = Reading(usage, source: .cpuTicks, at: date)
        } else {
            total = Reading(unavailable: .awaitingSecondSample, source: .cpuTicks, at: date)
        }
        return CPUSnapshot(total: total, perCore: CPUMath.perCore(from: last, to: current), loadAverage: load)
    }

    public static func loadAverage(at date: Date = Date()) -> Reading<[Double]> {
        var values = [Double](repeating: 0, count: 3)
        let count = getloadavg(&values, 3)
        guard count == 3 else { return Reading(unavailable: .queryFailed, source: .loadAverage, at: date) }
        return Reading(values, source: .loadAverage, at: date)
    }
}

/// Arbeitsspeicher, Swap und Speicherdruck.
public final class MemorySource {
    private let host = mach_host_self()
    public let physicalMemory: UInt64?
    /// Kernel-Seitengröße – nicht `vm_page_size` (unter Rosetta 4 KB statt 16 KB).
    public let pageSize: UInt64

    public init() {
        physicalMemory = Sysctl.uint64("hw.memsize")
        pageSize = UInt64(vm_kernel_page_size)
    }

    public func readPageCounts() -> VMPageCounts? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(host, HOST_VM_INFO64, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return VMPageCounts(free: UInt64(stats.free_count), active: UInt64(stats.active_count),
                            inactive: UInt64(stats.inactive_count), speculative: UInt64(stats.speculative_count),
                            wired: UInt64(stats.wire_count), compressor: UInt64(stats.compressor_page_count),
                            purgeable: UInt64(stats.purgeable_count), fileBacked: UInt64(stats.external_page_count),
                            anonymous: UInt64(stats.internal_page_count), compressions: UInt64(stats.compressions),
                            decompressions: UInt64(stats.decompressions), pageins: UInt64(stats.pageins),
                            pageouts: UInt64(stats.pageouts), swapins: UInt64(stats.swapins), swapouts: UInt64(stats.swapouts),
                            uncompressedInCompressor: UInt64(stats.total_uncompressed_pages_in_compressor))
    }

    private var previousCounts: (counts: VMPageCounts, uptime: Double)?

    public func sample(at date: Date = Date(), uptime: Double = ProcessInfo.processInfo.systemUptime) -> MemorySnapshot {
        let breakdown: Reading<MemoryBreakdown>
        let counts = readPageCounts()
        var activity: Reading<MemoryActivity>?
        var ratio: Double?
        if let counts {
            ratio = CompressionRatio.ratio(uncompressedPages: counts.uncompressedInCompressor, compressorPages: counts.compressor)
            if let previous = previousCounts, let rates = MemoryActivity.between(previous.counts, counts, seconds: uptime - previous.uptime) {
                activity = Reading(rates, source: .vmStatistics, at: date)
            } else {
                activity = Reading(unavailable: .awaitingSecondSample, source: .vmStatistics, at: date)
            }
            previousCounts = (counts, uptime)
        }
        if let counts, let physicalMemory, pageSize > 0 {
            breakdown = Reading(MemoryMath.breakdown(counts, pageSize: pageSize, physical: physicalMemory), source: .vmStatistics, at: date)
        } else {
            breakdown = Reading(unavailable: .queryFailed, source: .vmStatistics, at: date)
        }

        let swap: Reading<SwapUsage>
        if let usage = Sysctl.value("vm.swapusage", initial: xsw_usage()) {
            swap = Reading(SwapUsage(total: usage.xsu_total, used: usage.xsu_used, encrypted: usage.xsu_encrypted != 0),
                           source: .swapUsage, at: date)
        } else {
            swap = Reading(unavailable: .queryFailed, source: .swapUsage, at: date)
        }

        let pressure: Reading<PressureLevel>
        if let raw = Sysctl.int("kern.memorystatus_vm_pressure_level"), let level = PressureLevel(sysctlValue: raw) {
            pressure = Reading(level, source: .memoryPressure, at: date)
        } else {
            pressure = Reading(unavailable: .notProvidedByMacOS, source: .memoryPressure, at: date)
        }
        return MemorySnapshot(breakdown: breakdown, swap: swap, pressure: pressure, activity: activity,
                              compressionRatio: ratio, pageSize: pageSize)
    }
}

/// Thermalstatus (öffentlich) und Akkutemperatur (IORegistry).
public enum ThermalSource {
    public static func sample(batteryTemperature: Reading<Double>, smc: (sensors: Reading<[ThermalSensor]>, fans: Reading<[FanReading]>),
                              at date: Date = Date()) -> ThermalSnapshot {
        let level: ThermalLevel?
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: level = .nominal
        case .fair: level = .fair
        case .serious: level = .serious
        case .critical: level = .critical
        @unknown default: level = nil // unbekannte neue Stufe: nicht raten
        }
        let state: Reading<ThermalLevel> = level.map { Reading($0, source: .thermalState, at: date) }
            ?? Reading(unavailable: .implausibleValue, source: .thermalState, at: date)
        return ThermalSnapshot(state: state, batteryTemperature: batteryTemperature, sensors: smc.sensors, fans: smc.fans)
    }
}
