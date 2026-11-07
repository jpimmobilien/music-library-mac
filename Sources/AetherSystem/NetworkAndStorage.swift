import Darwin
import Foundation
import IOKit
import AetherCore

/// Netzwerkraten aus den 64-Bit-Zählern der Schnittstellen (`NET_RT_IFLIST2`). `getifaddrs` liefert nur 32-Bit-Zähler,
/// die bei 4 GB überlaufen.
public final class NetworkSource {
    private var downRate = CounterRate()
    private var upRate = CounterRate()
    private var downTotal = CounterAccumulator()
    private var upTotal = CounterAccumulator()
    /// Zähler je Schnittstelle (für die Netzwerkseite).
    private struct InterfaceTracker {
        var down = CounterRate()
        var up = CounterRate()
        var totalIn = CounterAccumulator()
        var totalOut = CounterAccumulator()
    }
    private var trackers: [String: InterfaceTracker] = [:]

    public init() {}

    public struct InterfaceCounters: Sendable {
        public var name: String
        public var isUp: Bool
        public var bytesIn: UInt64
        public var bytesOut: UInt64
    }

    /// Physische Schnittstellen: Ethernet, WLAN, Thunderbolt/USB-Ethernet tragen „en“. Tunnel (utun, ipsec), AirDrop
    /// (awdl, llw), Brücken und Loopback werden nicht gezählt – sonst wäre derselbe Verkehr doppelt enthalten.
    public static func isCountedInterface(_ name: String) -> Bool {
        name.hasPrefix("en")
    }

    public static func readCounters() -> [InterfaceCounters]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }

        var result: [InterfaceCounters] = []
        buffer.withUnsafeBytes { raw in
            var offset = 0
            let headerSize = MemoryLayout<if_msghdr>.size
            while offset + headerSize <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
                    if if_indextoname(UInt32(message.ifm_index), &nameBuffer) != nil {
                        let name = String(cString: nameBuffer)
                        let flags = message.ifm_flags
                        let isUp = (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0
                        result.append(InterfaceCounters(name: name, isUp: isUp, bytesIn: message.ifm_data.ifi_ibytes,
                                                        bytesOut: message.ifm_data.ifi_obytes))
                    }
                }
                offset += messageLength
            }
        }
        return result
    }

    public func sample(at date: Date = Date(), uptime: Double = ProcessInfo.processInfo.systemUptime) -> NetworkSnapshot {
        guard let all = Self.readCounters() else {
            return NetworkSnapshot(download: Reading(unavailable: .queryFailed, source: .interfaceCounters, at: date),
                                   upload: Reading(unavailable: .queryFailed, source: .interfaceCounters, at: date),
                                   sessionDownloaded: downTotal.total, sessionUploaded: upTotal.total, activeInterfaces: [])
        }
        let counted = all.filter { Self.isCountedInterface($0.name) }
        let inSum = counted.reduce(UInt64(0)) { $0 &+ $1.bytesIn }
        let outSum = counted.reduce(UInt64(0)) { $0 &+ $1.bytesOut }
        downTotal.update(Dictionary(counted.map { ($0.name, $0.bytesIn) }, uniquingKeysWith: { a, _ in a }))
        upTotal.update(Dictionary(counted.map { ($0.name, $0.bytesOut) }, uniquingKeysWith: { a, _ in a }))

        func reading(_ value: Double?) -> Reading<Double> {
            if let value { return Reading(value, source: .interfaceCounters, at: date) }
            return Reading(unavailable: .awaitingSecondSample, source: .interfaceCounters, at: date)
        }
        let down = downRate.update(value: inSum, time: uptime)
        let up = upRate.update(value: outSum, time: uptime)
        let active = counted.filter { $0.isUp && ($0.bytesIn > 0 || $0.bytesOut > 0) }.map(\.name).sorted()
        var snapshot = NetworkSnapshot(download: reading(down), upload: reading(up), sessionDownloaded: downTotal.total,
                                       sessionUploaded: upTotal.total, activeInterfaces: active)
        snapshot.interfaces = perInterface(all, uptime: uptime)
        return snapshot
    }

    /// Raten und Summen je Schnittstelle (gleiche Zähler wie oben, ohne Summenbildung über Schnittstellen).
    private func perInterface(_ all: [InterfaceCounters], uptime: Double) -> [InterfaceTraffic] {
        var result: [InterfaceTraffic] = []
        var seen: Set<String> = []
        for counters in all where !seen.contains(counters.name) {
            seen.insert(counters.name)
            var tracker = trackers[counters.name] ?? InterfaceTracker()
            let down = tracker.down.update(value: counters.bytesIn, time: uptime)
            let up = tracker.up.update(value: counters.bytesOut, time: uptime)
            tracker.totalIn.update([counters.name: counters.bytesIn])
            tracker.totalOut.update([counters.name: counters.bytesOut])
            trackers[counters.name] = tracker
            result.append(InterfaceTraffic(name: counters.name, isUp: counters.isUp, download: down, upload: up,
                                           sessionDownloaded: tracker.totalIn.total, sessionUploaded: tracker.totalOut.total))
        }
        // Verschwundene Schnittstellen vergessen
        trackers = trackers.filter { seen.contains($0.key) }
        return result
    }
}

/// Volumes (öffentliche Volume-Schlüssel von Foundation) und SSD-Aktivität (IOBlockStorageDriver-Statistik).
public final class StorageSource {
    private var readRate = CounterRate()
    private var writeRate = CounterRate()

    public init() {}

    private static let keys: [URLResourceKey] = [
        .volumeNameKey, .volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey, .volumeLocalizedFormatDescriptionKey, .volumeIsInternalKey,
        .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsRootFileSystemKey, .volumeIsReadOnlyKey, .volumeIsLocalKey,
        .volumeIsEncryptedKey,
    ]

    public static func volumes() -> [VolumeInfo] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        var result: [VolumeInfo] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let capacity = values.volumeTotalCapacity, capacity > 0 else { continue }
            let available = Int64(values.volumeAvailableCapacity ?? 0)
            result.append(VolumeInfo(
                name: values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent,
                path: url.path,
                capacity: Int64(capacity),
                available: available,
                availableForImportantUsage: values.volumeAvailableCapacityForImportantUsage,
                format: values.volumeLocalizedFormatDescription,
                isInternal: values.volumeIsInternal,
                isRemovable: (values.volumeIsRemovable ?? false) || (values.volumeIsEjectable ?? false),
                isRoot: values.volumeIsRootFileSystem ?? (url.path == "/"),
                isReadOnly: values.volumeIsReadOnly ?? false,
                isEncrypted: values.volumeIsEncrypted,
                isNetwork: values.volumeIsLocal == false
            ))
        }
        // Startvolume zuerst, dann interne, dann nach Name
        return result.sorted { a, b in
            if a.isRoot != b.isRoot { return a.isRoot }
            if (a.isInternal ?? false) != (b.isInternal ?? false) { return a.isInternal ?? false }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// Summe aller Lese-/Schreibzähler der Blockgeräte (öffentliche Schlüssel aus IOBlockStorageDriver.h).
    public static func blockCounters() -> (read: UInt64, write: UInt64)? {
        let all = IORegistry.property("Statistics", ofAll: "IOBlockStorageDriver")
        guard !all.isEmpty else { return nil }
        var read: UInt64 = 0, write: UInt64 = 0
        for case let stats as [String: Any] in all {
            read &+= (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            write &+= (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return (read, write)
    }

    public func sample(volumes: [VolumeInfo], at date: Date = Date(), uptime: Double = ProcessInfo.processInfo.systemUptime) -> StorageSnapshot {
        guard let counters = Self.blockCounters() else {
            return StorageSnapshot(volumes: volumes, readRate: Reading(unavailable: .notProvidedByMacOS, source: .blockStorage, at: date),
                                   writeRate: Reading(unavailable: .notProvidedByMacOS, source: .blockStorage, at: date))
        }
        func reading(_ value: Double?) -> Reading<Double> {
            if let value { return Reading(value, source: .blockStorage, at: date) }
            return Reading(unavailable: .awaitingSecondSample, source: .blockStorage, at: date)
        }
        return StorageSnapshot(volumes: volumes,
                               readRate: reading(readRate.update(value: counters.read, time: uptime)),
                               writeRate: reading(writeRate.update(value: counters.write, time: uptime)))
    }
}
