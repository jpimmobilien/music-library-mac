import Foundation
import AppKit
import Network
import IOKit
import Security
import PanoraCore

// =============================================================================================
// Hardware, Laufwerke, Netzwerk und Schlüsselbund.
// =============================================================================================

@MainActor
final class HardwareMonitor: ObservableObject {
    @Published private(set) var totalMemory: Int64 = Int64(ProcessInfo.processInfo.physicalMemory)
    @Published private(set) var availableMemory: Int64 = 0
    @Published private(set) var cpuLoad: Double = 0
    @Published private(set) var gpuLoad: Double?
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var gpuHistory: [Double] = []
    @Published private(set) var memoryHistory: [Double] = []
    let chipName: String
    let modelIdentifier: String
    let coreCount = ProcessInfo.processInfo.activeProcessorCount
    let isAppleSilicon: Bool

    private var timer: Timer?
    private var lastTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

    init() {
        chipName = HardwareMonitor.sysctlString("machdep.cpu.brand_string") ?? "Unbekannter Prozessor"
        modelIdentifier = HardwareMonitor.sysctlString("hw.model") ?? "Mac"
        #if arch(arm64)
        isAppleSilicon = true
        #else
        isAppleSilicon = false
        #endif
        sample()
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    func sample() {
        availableMemory = HardwareMonitor.availableMemory()
        if let load = cpuSample() { cpuLoad = load }
        gpuLoad = HardwareMonitor.gpuUtilization()
        append(&cpuHistory, cpuLoad)
        append(&gpuHistory, gpuLoad ?? 0)
        append(&memoryHistory, 1 - Double(availableMemory) / Double(max(totalMemory, 1)))
    }

    private func append(_ list: inout [Double], _ v: Double) {
        list.append(v)
        if list.count > 90 { list.removeFirst(list.count - 90) }
    }

    /// Speicherbandbreite in GB/s (Herstellerangaben, für neuere Chips geschätzt). Bestimmt die Token-Rate.
    var memoryBandwidthGBs: Double {
        let c = chipName.lowercased()
        let table: [(String, Double)] = [("m5 max", 614), ("m5 pro", 307), ("m5", 153),
                                         ("m4 max", 546), ("m4 pro", 273), ("m4", 120),
                                         ("m3 ultra", 819), ("m3 max", 400), ("m3 pro", 150), ("m3", 100),
                                         ("m2 ultra", 800), ("m2 max", 400), ("m2 pro", 200), ("m2", 100),
                                         ("m1 ultra", 800), ("m1 max", 400), ("m1 pro", 200), ("m1", 68)]
        for (key, value) in table where c.contains(key) { return value }
        return 100
    }

    func snapshot(settings: AppSettings, diskReadGBs: Double) -> HardwareSnapshot {
        HardwareSnapshot(totalMemory: totalMemory, availableMemory: availableMemory,
                         modelBudget: Int64(Double(totalMemory) * settings.modelBudgetFraction),
                         memoryBandwidthGBs: memoryBandwidthGBs, diskReadGBs: diskReadGBs, cpuLoad: cpuLoad, gpuLoad: gpuLoad ?? 0)
    }

    private func cpuSample() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let now = (user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
        defer { lastTicks = now }
        guard let last = lastTicks else { return nil }
        let user = Double(now.user &- last.user) + Double(now.nice &- last.nice)
        let system = Double(now.system &- last.system)
        let idle = Double(now.idle &- last.idle)
        let total = user + system + idle
        return total > 0 ? (user + system) / total : nil
    }

    static func availableMemory() -> Int64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let page = Int64(vm_kernel_page_size)
        let pages = Int64(stats.free_count) + Int64(stats.inactive_count) + Int64(stats.purgeable_count)
        return pages * page
    }

    static func gpuUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var value: Double?
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let perf = dict["PerformanceStatistics"] as? [String: Any] {
                if let util = perf["Device Utilization %"] as? Int { value = Double(util) / 100 }
                else if let util = perf["Device Utilization %"] as? Double { value = util / 100 }
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return value
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}

// MARK: - Laufwerke

struct VolumeInfo: Identifiable, Equatable {
    var id: String { path }
    var path: String
    var name: String
    var total: Int64
    var available: Int64
    var isInternal: Bool
    var isEjectable: Bool
    var isRoot: Bool
    var media: String?
    var bus: String?
    var solidState: Bool?

    var used: Int64 { max(0, total - available) }
    var kindLabel: String {
        if isRoot { return "Interne SSD (Startvolume)" }
        if isInternal { return "Internes Volume" }
        return "Externes Laufwerk"
    }
}

struct SpeedResult: Equatable {
    var writeMBs: Double
    var readMBs: Double
    var date: Date
}

@MainActor
final class StorageMonitor: ObservableObject {
    @Published private(set) var volumes: [VolumeInfo] = []
    @Published var speedTestRunning: String?
    @Published var speedResults: [String: SpeedResult] = [:]
    /// Wird bei jedem Ein- oder Aushängen erhöht (Modellbibliothek scannt dann neu).
    @Published private(set) var mountGeneration = 0

    private var observers: [NSObjectProtocol] = []
    private var details: [String: (media: String?, bus: String?, ssd: Bool?)] = [:]

    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                    self?.mountGeneration += 1
                }
            })
        }
    }

    func refresh() {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsInternalKey, .volumeIsEjectableKey, .volumeTotalCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
                                      .volumeIsRootFileSystemKey, .volumeIsBrowsableKey, .volumeIsLocalKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        var list: [VolumeInfo] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if v.volumeIsBrowsable == false || v.volumeIsLocal == false { continue }
            let total = Int64(v.volumeTotalCapacity ?? 0)
            guard total > 2_000_000_000 else { continue }
            let available = v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0)
            let detail = details[url.path]
            list.append(VolumeInfo(path: url.path, name: v.volumeName ?? url.lastPathComponent, total: total, available: available,
                                   isInternal: v.volumeIsInternal ?? true, isEjectable: v.volumeIsEjectable ?? false,
                                   isRoot: v.volumeIsRootFileSystem ?? false, media: detail?.media, bus: detail?.bus,
                                   solidState: detail?.ssd))
        }
        volumes = list.sorted { ($0.isRoot ? 0 : 1, $0.name) < ($1.isRoot ? 0 : 1, $1.name) }
        loadDetails()
    }

    /// Gerätedaten über diskutil (Modell, Anschluss, SSD) – im Hintergrund.
    private func loadDetails() {
        let missing = volumes.filter { details[$0.path] == nil }.map(\.path)
        guard !missing.isEmpty else { return }
        Task.detached(priority: .utility) {
            var found: [String: (String?, String?, Bool?)] = [:]
            for path in missing {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                p.arguments = ["info", "-plist", path]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = Pipe()
                do { try p.run() } catch { continue }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                guard let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { continue }
                found[path] = (plist["MediaName"] as? String, plist["BusProtocol"] as? String, plist["SolidState"] as? Bool)
            }
            let result = found
            await MainActor.run { [weak self] in
                guard let self else { return }
                for (k, v) in result { self.details[k] = (media: v.0, bus: v.1, ssd: v.2) }
                self.volumes = self.volumes.map { vol in
                    var vol = vol
                    if let d = self.details[vol.path] { vol.media = d.media; vol.bus = d.bus; vol.solidState = d.ssd }
                    return vol
                }
            }
        }
    }

    func volume(containing path: String) -> VolumeInfo? {
        let resolved = URL(fileURLWithPath: path).standardizedFileURL.path
        return volumes.filter { resolved == $0.path || resolved.hasPrefix($0.path == "/" ? "/" : $0.path + "/") }
            .max { $0.path.count < $1.path.count }
    }

    /// Größtes externes Laufwerk mit genug Platz – bevorzugter Ort für große Modelle.
    var preferredExternal: VolumeInfo? {
        volumes.filter { !$0.isInternal && !$0.isRoot && $0.available > 50_000_000_000 }.max { $0.available < $1.available }
    }

    /// Schreib- und Lesetest (512 MB, ohne Zwischenspeicher des Systems).
    func runSpeedTest(on volume: VolumeInfo) {
        guard speedTestRunning == nil else { return }
        speedTestRunning = volume.path
        let path = volume.path
        Task.detached(priority: .userInitiated) {
            let result = StorageMonitor.measure(directory: path)
            await MainActor.run { [weak self] in
                self?.speedTestRunning = nil
                if let result { self?.speedResults[path] = result }
            }
        }
    }

    nonisolated static func measure(directory: String) -> SpeedResult? {
        let url = URL(fileURLWithPath: directory).appendingPathComponent(".panora-speedtest-\(UUID().uuidString)")
        let chunk = 8 * 1024 * 1024
        let chunks = 64
        var buffer = [UInt8](repeating: 0, count: chunk)
        for i in stride(from: 0, to: chunk, by: 4096) { buffer[i] = UInt8(truncatingIfNeeded: i &* 31) }
        let fd = open(url.path, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
        guard fd >= 0 else { return nil }
        _ = fcntl(fd, F_NOCACHE, 1)
        let writeStart = Date()
        for _ in 0..<chunks {
            let written = buffer.withUnsafeBytes { write(fd, $0.baseAddress, chunk) }
            if written != chunk { close(fd); unlink(url.path); return nil }
        }
        fsync(fd)
        close(fd)
        let writeTime = Date().timeIntervalSince(writeStart)
        let rfd = open(url.path, O_RDONLY)
        guard rfd >= 0 else { unlink(url.path); return nil }
        _ = fcntl(rfd, F_NOCACHE, 1)
        let readStart = Date()
        var total = 0
        while true {
            let n = buffer.withUnsafeMutableBytes { read(rfd, $0.baseAddress, chunk) }
            if n <= 0 { break }
            total += n
        }
        close(rfd)
        let readTime = Date().timeIntervalSince(readStart)
        unlink(url.path)
        let mb = Double(chunk * chunks) / 1_000_000
        return SpeedResult(writeMBs: mb / max(writeTime, 0.001), readMBs: Double(total) / 1_000_000 / max(readTime, 0.001), date: Date())
    }
}

// MARK: - Netzwerk

@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var online = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let status = path.status == .satisfied
            Task { @MainActor in self?.online = status }
        }
        monitor.start(queue: DispatchQueue(label: "panora.network"))
    }
}

// MARK: - Schlüsselbund (API-Schlüssel der externen Experten)

enum Keychain {
    static let service = "de.panora.app.experts"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ account: String, value: String) -> Bool {
        delete(account)
        guard !value.isEmpty else { return true }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecValueData as String: Data(value.utf8),
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}
