import Foundation

// =============================================================================================
// Prozesse – Datenmodelle und Logik ohne Apple-Frameworks (unit-getestet).
//
// Quellen: Liste, Eltern, Benutzer, Zustand, Start, Rosetta-Kennzeichen aus der Kernel-Prozesstabelle (für alle);
// CPU-Zeit, Threads und Speicherbedarf eigener Prozesse aus libproc; CPU-Zeit und residenter Speicher fremder
// Prozesse aus /bin/ps (mit Systemrechten installiert – wird geprüft, nicht angenommen).
// =============================================================================================

public enum ProcessState: String, Sendable, Codable, CaseIterable {
    case running, sleeping, idle, stopped, zombie, unknown

    /// `p_stat` aus `extern_proc`: 1 SIDL, 2 SRUN, 3 SSLEEP, 4 SSTOP, 5 SZOMB.
    public init(kernelStat: Int) {
        switch kernelStat {
        case 1: self = .idle
        case 2: self = .running
        case 3: self = .sleeping
        case 4: self = .stopped
        case 5: self = .zombie
        default: self = .unknown
        }
    }
}

/// Woher CPU- und Speicherwerte eines Prozesses stammen.
public enum ProcessValueSource: String, Sendable, Codable {
    /// libproc (eigene Prozesse): CPU-Zeit in Nanosekunden, Speicherbedarf (phys_footprint) wie die Aktivitätsanzeige.
    case libproc
    /// /bin/ps (fremde Prozesse): CPU-Zeit auf 1/100 s, residenter Speicher (RSS).
    case ps
    /// Weder noch – macOS gibt die Werte ohne Administratorrechte nicht heraus.
    case unavailable
}

/// Rohdaten eines Prozesses aus einer Messung (ohne Raten).
public struct ProcessSample: Sendable, Equatable {
    public var pid: Int32
    public var ppid: Int32
    public var uid: UInt32
    public var name: String
    public var path: String?
    public var state: ProcessState
    public var startTime: Date?
    public var isTranslated: Bool
    /// Kumulierte CPU-Zeit in Sekunden (Benutzer + System).
    public var cpuSeconds: Double?
    /// Bytes: phys_footprint (libproc) bzw. RSS (ps).
    public var memory: UInt64?
    public var threads: Int?
    public var source: ProcessValueSource

    public init(pid: Int32, ppid: Int32, uid: UInt32, name: String, path: String?, state: ProcessState, startTime: Date?,
                isTranslated: Bool, cpuSeconds: Double?, memory: UInt64?, threads: Int?, source: ProcessValueSource) {
        self.pid = pid
        self.ppid = ppid
        self.uid = uid
        self.name = name
        self.path = path
        self.state = state
        self.startTime = startTime
        self.isTranslated = isTranslated
        self.cpuSeconds = cpuSeconds
        self.memory = memory
        self.threads = threads
        self.source = source
    }

    /// Eindeutig über die Lebenszeit (PIDs werden wiederverwendet).
    public var identity: ProcessIdentity { ProcessIdentity(pid: pid, start: startTime?.timeIntervalSince1970 ?? 0) }
}

public struct ProcessIdentity: Hashable, Sendable {
    public var pid: Int32
    public var start: Double
}

public struct ProcessSnapshot: Sendable {
    public var samples: [ProcessSample]
    public var timestamp: Date
    /// Liefert /bin/ps Werte fremder Prozesse?
    public var othersAvailable: Bool
    public var currentUID: UInt32

    public init(samples: [ProcessSample], timestamp: Date, othersAvailable: Bool, currentUID: UInt32) {
        self.samples = samples
        self.timestamp = timestamp
        self.othersAvailable = othersAvailable
        self.currentUID = currentUID
    }
}

// MARK: - /bin/ps

public enum PSParser {
    /// CPU-Zeit im Format von `ps -o time`: „[[TT-]HH:]MM:SS.cc“ → Sekunden.
    public static func cpuTime(_ text: String) -> Double? {
        var rest = Substring(text.trimmingCharacters(in: .whitespaces))
        guard !rest.isEmpty else { return nil }
        var days = 0.0
        if let dash = rest.firstIndex(of: "-") {
            guard let d = Double(rest[..<dash]) else { return nil }
            days = d
            rest = rest[rest.index(after: dash)...]
        }
        let parts = rest.split(separator: ":")
        guard (1...3).contains(parts.count), let seconds = Double(parts.last!) else { return nil }
        var total = seconds
        if parts.count >= 2 {
            guard let minutes = Double(parts[parts.count - 2]) else { return nil }
            total += minutes * 60
        }
        if parts.count == 3 {
            guard let hours = Double(parts[0]) else { return nil }
            total += hours * 3_600
        }
        return total + days * 86_400
    }

    /// Ausgabe von `ps -axo pid=,time=,rss=` → PID → (CPU-Sekunden, RSS in Bytes). Unlesbare Zeilen werden übersprungen.
    public static func parse(_ output: String) -> [Int32: (cpuSeconds: Double, rss: UInt64)] {
        var result: [Int32: (cpuSeconds: Double, rss: UInt64)] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 3, let pid = Int32(fields[0]), let cpu = cpuTime(String(fields[1])),
                  let rssKB = UInt64(fields[2]) else { continue }
            result[pid] = (cpu, rssKB * 1_024)
        }
        return result
    }
}

// MARK: - CPU-Anteile

/// Anteil eines Kerns (0,25 = 25 % eines Kerns; Summe über alle Prozesse bis Kernzahl × 100 %).
public struct ProcessCPUTracker: Sendable {
    private var last: [ProcessIdentity: (seconds: Double, time: Double)] = [:]

    public init() {}

    /// - Parameter time: monotone Zeit in Sekunden.
    public mutating func update(_ samples: [ProcessSample], time: Double) -> [ProcessIdentity: Double] {
        var next: [ProcessIdentity: (seconds: Double, time: Double)] = [:]
        var rates: [ProcessIdentity: Double] = [:]
        for sample in samples {
            guard let seconds = sample.cpuSeconds else { continue }
            let id = sample.identity
            if let previous = last[id], time > previous.time, seconds >= previous.seconds {
                rates[id] = (seconds - previous.seconds) / (time - previous.time)
            }
            next[id] = (seconds, time)
        }
        last = next
        return rates
    }
}

// MARK: - Schutz kritischer Prozesse

public enum ProcessProtection: Equatable, Sendable {
    /// Darf beendet werden (eigener Prozess, nicht kritisch).
    case allowed
    /// Systemnaher Prozess: nur mit ausdrücklicher Bestätigung.
    case confirmSystem
    /// Wird nie beendet (Kernel, launchd, Fenstersystem, Anmeldung, AETHER selbst).
    case blocked
    /// Gehört einem anderen Benutzer – ohne Administratorrechte nicht möglich.
    case otherUser

    /// Prozesse, deren Beenden den Mac abmeldet, einfriert oder neu startet.
    public static let criticalNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow", "logd", "configd", "notifyd", "opendirectoryd",
        "coreservicesd", "securityd", "syslogd", "UserEventAgent", "distnoted", "powerd", "diskarbitrationd",
        "fseventsd", "cfprefsd", "trustd", "runningboardd", "launchservicesd", "kextd", "kernelmanagerd",
        "watchdogd", "mds", "mds_stores", "airportd", "bluetoothd", "coreaudiod", "hidd", "Dock", "SystemUIServer",
        "ControlCenter", "Finder", "sandboxd", "tccd", "authd", "lsd", "usbd", "thermalmonitord", "apsd",
    ]

    public static func evaluate(pid: Int32, name: String, uid: UInt32, currentUID: UInt32, ownPID: Int32,
                                path: String?) -> ProcessProtection {
        if pid <= 1 || pid == ownPID { return .blocked }
        if ["kernel_task", "launchd", "WindowServer", "loginwindow"].contains(name) { return .blocked }
        if uid != currentUID { return .otherUser }
        if criticalNames.contains(name) { return .confirmSystem }
        if let path, path.hasPrefix("/System/") || path.hasPrefix("/usr/libexec/") || path.hasPrefix("/usr/sbin/") {
            return .confirmSystem
        }
        return .allowed
    }
}

// MARK: - App-Familien

public enum AppFamilyKey {
    /// Äußerstes App-Paket eines Programmpfads: „/Applications/Google Chrome.app/Contents/Frameworks/…/Helper.app/…“
    /// → „/Applications/Google Chrome.app“. Kein App-Paket → `nil`.
    public static func outermostAppBundle(of path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        let joined = components[...index].joined(separator: "/")
        return path.hasPrefix("/") ? "/" + joined : joined
    }

    /// Anzeigename aus dem Paketpfad („Google Chrome“).
    public static func displayName(ofBundlePath bundle: String) -> String {
        let last = bundle.split(separator: "/").last.map(String.init) ?? bundle
        return last.hasSuffix(".app") ? String(last.dropLast(4)) : last
    }
}

/// Eine App mit allen zugehörigen Prozessen (Hilfsprozesse, Renderer, XPC-Dienste).
public struct ProcessFamily: Identifiable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var members: [Int32]
    public var cpu: Double?
    public var memory: UInt64?
    /// Mindestens ein Wert stammt aus einer Quelle mit anderer Bedeutung (RSS statt Speicherbedarf).
    public var mixedMemorySources: Bool

    public init(id: String, name: String, members: [Int32], cpu: Double?, memory: UInt64?, mixedMemorySources: Bool) {
        self.id = id
        self.name = name
        self.members = members
        self.cpu = cpu
        self.memory = memory
        self.mixedMemorySources = mixedMemorySources
    }
}

public enum FamilyBuilder {
    public struct Input: Sendable {
        public var pid: Int32
        public var ppid: Int32
        public var name: String
        public var path: String?
        public var cpu: Double?
        public var memory: UInt64?
        public var source: ProcessValueSource

        public init(pid: Int32, ppid: Int32, name: String, path: String?, cpu: Double?, memory: UInt64?, source: ProcessValueSource) {
            self.pid = pid
            self.ppid = ppid
            self.name = name
            self.path = path
            self.cpu = cpu
            self.memory = memory
            self.source = source
        }
    }

    /// Familie je Prozess: zuerst über das äußerste App-Paket im Pfad, sonst über den Elternprozess (Kette), sonst
    /// der Prozess allein. Gibt PID → Familienschlüssel zurück.
    public static func familyKeys(_ inputs: [Input]) -> [Int32: String] {
        var byPID: [Int32: Input] = [:]
        for input in inputs { byPID[input.pid] = input }
        var direct: [Int32: String] = [:]
        for input in inputs {
            if let path = input.path, let bundle = AppFamilyKey.outermostAppBundle(of: path) {
                direct[input.pid] = bundle
            }
        }
        var result: [Int32: String] = [:]
        for input in inputs {
            if let key = direct[input.pid] {
                result[input.pid] = key
                continue
            }
            // Elternkette (höchstens 8 Schritte, nie über launchd hinaus)
            var parent = input.ppid
            var steps = 0
            var found: String?
            while parent > 1, steps < 8, let p = byPID[parent] {
                if let key = direct[p.pid] {
                    found = key
                    break
                }
                parent = p.ppid
                steps += 1
            }
            result[input.pid] = found ?? "pid:\(input.pid)"
        }
        return result
    }

    public static func families(_ inputs: [Input]) -> [ProcessFamily] {
        let keys = familyKeys(inputs)
        var grouped: [String: [Input]] = [:]
        for input in inputs { grouped[keys[input.pid] ?? "pid:\(input.pid)", default: []].append(input) }
        return grouped.map { key, members in
            let cpuValues = members.compactMap(\.cpu)
            let memValues = members.compactMap(\.memory)
            let sources = Set(members.filter { $0.memory != nil }.map(\.source))
            let name: String
            if key.hasPrefix("pid:") {
                name = members.first?.name ?? key
            } else {
                name = AppFamilyKey.displayName(ofBundlePath: key)
            }
            return ProcessFamily(id: key, name: name, members: members.map(\.pid).sorted(),
                                 cpu: cpuValues.isEmpty ? nil : cpuValues.reduce(0, +),
                                 memory: memValues.isEmpty ? nil : memValues.reduce(0, +),
                                 mixedMemorySources: sources.count > 1)
        }
    }
}

// MARK: - Filter

public enum ProcessFilter: String, CaseIterable, Sendable, Identifiable {
    case all, mine, system, apps, highCPU, highMemory
    public var id: String { rawValue }

    /// Schwellen für „hohe CPU“ (Anteil eines Kerns) und „hoher Speicher“.
    public static let highCPUThreshold = 0.10
    public static let highMemoryThreshold: UInt64 = 500 * 1_048_576
}

public enum ProcessSearch {
    /// Groß-/Kleinschreibung egal; sucht in Name, PID, Pfad und App-Name.
    public static func matches(query: String, name: String, pid: Int32, path: String?, appName: String?) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        if String(pid) == q { return true }
        let lower = q.lowercased()
        return name.lowercased().contains(lower)
            || (path?.lowercased().contains(lower) ?? false)
            || (appName?.lowercased().contains(lower) ?? false)
    }
}

// MARK: - Kerncluster je logischem Kern

public enum CoreClusterMap {
    /// Aus Einträgen des Gerätebaums (logische CPU-ID, Cluster-Typ „E“/„P“) die Art je Kern in Reihenfolge der IDs.
    /// Unvollständige oder widersprüchliche Angaben → `nil` (lieber keine Zuordnung als eine falsche).
    public static func kinds(entries: [(logicalID: Int, type: String)], coreCount: Int) -> [CoreCluster.Kind]? {
        guard coreCount > 0, entries.count == coreCount else { return nil }
        var kinds = [CoreCluster.Kind?](repeating: nil, count: coreCount)
        for entry in entries {
            guard (0..<coreCount).contains(entry.logicalID), kinds[entry.logicalID] == nil else { return nil }
            switch entry.type.uppercased().prefix(1) {
            case "P": kinds[entry.logicalID] = .performance
            case "E": kinds[entry.logicalID] = .efficiency
            default: return nil
            }
        }
        let resolved = kinds.compactMap { $0 }
        return resolved.count == coreCount ? resolved : nil
    }
}

// MARK: - Speicher-Raten

public struct MemoryActivity: Equatable, Sendable {
    /// Seiten pro Sekunde.
    public var pageIns: Double
    public var pageOuts: Double
    public var swapIns: Double
    public var swapOuts: Double
    public var compressions: Double
    public var decompressions: Double

    public init(pageIns: Double, pageOuts: Double, swapIns: Double, swapOuts: Double, compressions: Double, decompressions: Double) {
        self.pageIns = pageIns
        self.pageOuts = pageOuts
        self.swapIns = swapIns
        self.swapOuts = swapOuts
        self.compressions = compressions
        self.decompressions = decompressions
    }

    /// Aus zwei Zählerständen; Rücksetzungen (Zähler kleiner) → `nil`.
    public static func between(_ a: VMPageCounts, _ b: VMPageCounts, seconds: Double) -> MemoryActivity? {
        guard seconds > 0 else { return nil }
        func rate(_ x: UInt64, _ y: UInt64) -> Double? { y >= x ? Double(y - x) / seconds : nil }
        guard let pi = rate(a.pageins, b.pageins), let po = rate(a.pageouts, b.pageouts),
              let si = rate(a.swapins, b.swapins), let so = rate(a.swapouts, b.swapouts),
              let c = rate(a.compressions, b.compressions), let d = rate(a.decompressions, b.decompressions) else { return nil }
        return MemoryActivity(pageIns: pi, pageOuts: po, swapIns: si, swapOuts: so, compressions: c, decompressions: d)
    }
}

public enum CompressionRatio {
    /// Verhältnis unkomprimierter zu komprimiert gespeicherten Seiten (z. B. 2,6 : 1). Ohne Kompressor-Seiten `nil`.
    public static func ratio(uncompressedPages: UInt64, compressorPages: UInt64) -> Double? {
        guard compressorPages > 0, uncompressedPages >= compressorPages else { return nil }
        return Double(uncompressedPages) / Double(compressorPages)
    }
}
