import Darwin
import Foundation

/// Eigenverbrauch von ORBIT (CPU-Anteil seit der letzten Messung, Speicherbedarf wie in der Aktivitätsanzeige).
public final class SelfUsage {
    public struct Sample: Sendable, Equatable {
        /// Anteil eines Kerns (0,01 = 1 % eines Kerns).
        public var cpu: Double?
        /// `phys_footprint` – entspricht der Spalte „Speicher“ der Aktivitätsanzeige.
        public var footprint: UInt64?
    }

    private var lastCPUTime: Double?
    private var lastUptime: Double?

    public init() {}

    public func sample(uptime: Double = ProcessInfo.processInfo.systemUptime) -> Sample {
        var usage = rusage()
        var cpu: Double?
        if getrusage(RUSAGE_SELF, &usage) == 0 {
            let seconds = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
                + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
            if let lastCPUTime, let lastUptime, uptime > lastUptime {
                cpu = max(0, (seconds - lastCPUTime) / (uptime - lastUptime))
            }
            lastCPUTime = seconds
            lastUptime = uptime
        }
        return Sample(cpu: cpu, footprint: Self.footprint())
    }

    public static func footprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }
}
