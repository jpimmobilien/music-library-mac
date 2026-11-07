import Darwin
import Foundation
import IOKit
import AetherCore

/// Prozessliste: Kernel-Prozesstabelle (alle Prozesse), libproc (eigene Prozesse), /bin/ps (fremde Prozesse, falls mit
/// Systemrechten installiert). Keine privaten Schnittstellen, keine Administratorrechte.
public final class ProcessSource {
    public let currentUID: UInt32 = getuid()
    private let timebaseFactor: Double
    private var pathCache: [ProcessIdentity: String] = [:]
    private var noPath: Set<ProcessIdentity> = []
    /// Ist /bin/ps mit Systemrechten installiert (setuid root)? Nur dann liefert es Werte fremder Prozesse.
    public let psHasSystemRights: Bool

    public init() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        timebaseFactor = info.denom == 0 ? 1 : Double(info.numer) / Double(info.denom)
        let attributes = try? FileManager.default.attributesOfItem(atPath: "/bin/ps")
        let permissions = (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? 0
        let owner = (attributes?[.ownerAccountID] as? NSNumber)?.intValue ?? -1
        psHasSystemRights = owner == 0 && (permissions & 0o4000) != 0
    }

    /// Kernel-Prozesstabelle (`sysctl KERN_PROC_ALL`) – für alle Benutzer lesbar.
    static func kernelTable() -> [kinfo_proc]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        let stride = MemoryLayout<kinfo_proc>.stride
        for _ in 0..<4 {
            var size = 0
            guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return nil }
            let count = size / stride + 32 // Reserve für neu entstehende Prozesse
            var list = [kinfo_proc](repeating: kinfo_proc(), count: count)
            var bytes = count * stride
            let result = list.withUnsafeMutableBytes { buffer -> Int32 in
                sysctl(&mib, 4, buffer.baseAddress, &bytes, nil, 0)
            }
            if result == 0 { return Array(list.prefix(bytes / stride)) }
            if errno != ENOMEM { return nil }
        }
        return nil
    }

    private static func command(_ process: kinfo_proc) -> String {
        var comm = process.kp_proc.p_comm
        return withUnsafeBytes(of: &comm) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }

    private func path(for identity: ProcessIdentity) -> String? {
        if let cached = pathCache[identity] { return cached }
        if noPath.contains(identity) { return nil }
        var buffer = [CChar](repeating: 0, count: 4 * 1_024)
        let length = proc_pidpath(identity.pid, &buffer, UInt32(buffer.count))
        guard length > 0 else {
            noPath.insert(identity)
            return nil
        }
        let value = String(cString: buffer)
        pathCache[identity] = value
        return value
    }

    /// CPU-Zeit (Sekunden), Threads und Speicherbedarf eigener Prozesse.
    private func ownValues(_ pid: Int32) -> (cpu: Double, threads: Int, footprint: UInt64?)? {
        var task = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, size) == size else { return nil }
        // pti_total_* sind Mach-Zeiteinheiten (auf Apple Silicon ≠ Nanosekunden)
        let seconds = Double(task.pti_total_user &+ task.pti_total_system) * timebaseFactor / 1_000_000_000
        var usage = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &usage) { pointer -> Int32 in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return (seconds, Int(task.pti_threadnum), status == 0 ? usage.ri_phys_footprint : nil)
    }

    /// Fremde Prozesse über /bin/ps: PID → (CPU-Sekunden, RSS).
    private func psValues() -> [Int32: (cpuSeconds: Double, rss: UInt64)] {
        guard psHasSystemRights,
              let data = HardwareSource.run("/bin/ps", ["-axo", "pid=,time=,rss="], timeout: 8),
              let text = String(data: data, encoding: .utf8) else { return [:] }
        return PSParser.parse(text)
    }

    /// Eine Messung aller Prozesse.
    public func sample(at date: Date = Date()) -> ProcessSnapshot? {
        guard let table = Self.kernelTable() else { return nil }
        let ps = psValues()
        var samples: [ProcessSample] = []
        samples.reserveCapacity(table.count)
        var alive: Set<ProcessIdentity> = []
        for entry in table {
            let pid = entry.kp_proc.p_pid
            guard pid >= 0 else { continue }
            let start = entry.kp_proc.p_un.__p_starttime
            let startDate = start.tv_sec > 0 ? Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000) : nil
            let uid = entry.kp_eproc.e_ucred.cr_uid
            let identity = ProcessIdentity(pid: pid, start: startDate?.timeIntervalSince1970 ?? 0)
            alive.insert(identity)
            var sample = ProcessSample(pid: pid, ppid: entry.kp_eproc.e_ppid, uid: uid, name: Self.command(entry),
                                       path: pid == 0 ? nil : path(for: identity),
                                       state: ProcessState(kernelStat: Int(entry.kp_proc.p_stat)), startTime: startDate,
                                       isTranslated: (entry.kp_proc.p_flag & 0x0002_0000) != 0,
                                       cpuSeconds: nil, memory: nil, threads: nil, source: .unavailable)
            if uid == currentUID, pid > 0, let own = ownValues(pid) {
                sample.cpuSeconds = own.cpu
                sample.threads = own.threads
                sample.memory = own.footprint
                sample.source = .libproc
            } else if let values = ps[pid] {
                sample.cpuSeconds = values.cpuSeconds
                sample.memory = values.rss
                sample.source = .ps
            }
            samples.append(sample)
        }
        // Zwischenspeicher für beendete Prozesse leeren
        if pathCache.count > alive.count * 2 || noPath.count > alive.count * 2 {
            pathCache = pathCache.filter { alive.contains($0.key) }
            noPath = noPath.filter { alive.contains($0) }
        }
        return ProcessSnapshot(samples: samples, timestamp: date, othersAvailable: psHasSystemRights && !ps.isEmpty,
                               currentUID: currentUID)
    }

    /// Threads eines fremden Prozesses über `ps -M` (nur für die Detailansicht).
    public func threadCount(pid: Int32) -> Int? {
        guard psHasSystemRights,
              let data = HardwareSource.run("/bin/ps", ["-M", "-p", String(pid)], timeout: 5),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.split(whereSeparator: \.isNewline)
        return lines.count > 1 ? lines.count - 1 : nil
    }
}

/// Zuordnung logischer Kerne zu Leistungs- und Effizienzkernen (Apple Silicon) aus dem Gerätebaum der IORegistry.
/// Undokumentierte Schlüssel („cluster-type“, „logical-cpu-id“) – unvollständige Angaben ergeben keine Zuordnung.
public enum CoreClusterSource {
    public static func kinds(coreCount: Int) -> [CoreCluster.Kind]? {
        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard cpus != 0 else { return nil }
        defer { IOObjectRelease(cpus) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(cpus, "IODeviceTree", &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var entries: [(logicalID: Int, type: String)] = []
        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { break }
            defer { IOObjectRelease(entry) }
            guard let properties = IORegistry.properties(of: entry),
                  let typeData = properties["cluster-type"] as? Data,
                  let idData = properties["logical-cpu-id"] as? Data, !idData.isEmpty else { continue }
            let type = String(decoding: typeData.prefix(while: { $0 != 0 }), as: UTF8.self)
            var id = 0
            for (offset, byte) in idData.prefix(4).enumerated() { id |= Int(byte) << (8 * offset) }
            entries.append((id, type))
        }
        return CoreClusterMap.kinds(entries: entries, coreCount: coreCount)
    }
}

/// Prozessbezogene Aktionen über offizielle Mechanismen.
public enum ProcessControl {
    public enum Outcome: Equatable, Sendable {
        case sent
        case notPermitted
        case notRunning
        case failed(Int32)
    }

    /// Signal an einen Prozess, der keine App ist (SIGTERM = regulär, SIGKILL = sofort).
    public static func signal(pid: Int32, force: Bool) -> Outcome {
        guard pid > 1 else { return .notPermitted }
        if kill(pid, force ? SIGKILL : SIGTERM) == 0 { return .sent }
        switch errno {
        case EPERM: return .notPermitted
        case ESRCH: return .notRunning
        default: return .failed(errno)
        }
    }

    /// Benutzername zu einer UID.
    public static func userName(uid: UInt32) -> String {
        guard let entry = getpwuid(uid) else { return String(uid) }
        return String(cString: entry.pointee.pw_name)
    }
}
