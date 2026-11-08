import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AetherCore
import AetherSystem

/// Ein Prozess, wie ihn die Oberfläche zeigt (Messwerte + App-Zuordnung + Schutzstufe).
struct ProcessRow: Identifiable, Equatable {
    let id: Int32
    var pid: Int32 { id }
    var ppid: Int32
    var uid: UInt32
    var user: String
    /// Anzeigename: App-Name, sonst Programmdatei (vollständig), sonst Kernel-Kurzname.
    var name: String
    var command: String
    var path: String?
    var state: ProcessState
    var startTime: Date?
    var isTranslated: Bool
    /// Anteil eines Kerns – geglättet (τ Anstieg 0,8 s / Abfall 2,5 s), damit die Liste nicht bei jeder Messung
    /// umsortiert wird. `cpuRaw` ist der zuletzt gemessene Wert.
    var cpu: Double?
    var cpuRaw: Double?
    var memory: UInt64?
    var threads: Int?
    var source: ProcessValueSource
    var appName: String?
    var bundleID: String?
    var bundlePath: String?
    /// Reguläre App (Dock, Menüleiste).
    var isApp: Bool
    var isOwn: Bool
    var familyKey: String
    var protection: ProcessProtection

    // Sortierschlüssel (fehlende Werte ans Ende)
    var nameSort: String { name.lowercased() }
    /// Auf 0,5 % gerundet: kleine Schwankungen vertauschen keine Zeilen.
    var cpuSort: Double { cpu.map { ($0 * 200).rounded() / 200 } ?? -1 }
    var memorySort: Double { memory.map(Double.init) ?? -1 }
    var threadSort: Int { threads ?? -1 }
    var pidSort: Int { Int(pid) }
    var userSort: String { user }
    var kindSort: Int { isApp ? 0 : (isOwn ? 1 : 2) }
    var isSystem: Bool { !isOwn || protection == .confirmSystem || protection == .blocked }
}

extension ProcessFilter {
    func passes(_ row: ProcessRow) -> Bool {
        switch self {
        case .all: return true
        case .mine: return row.isOwn
        case .system: return row.isSystem
        case .apps: return row.isApp
        case .highCPU: return (row.cpu ?? 0) >= ProcessFilter.highCPUThreshold
        case .highMemory: return (row.memory ?? 0) >= ProcessFilter.highMemoryThreshold
        }
    }
}

/// Eine App-Familie für die gruppierte Ansicht.
struct FamilyRow: Identifiable, Equatable {
    let id: String
    var name: String
    var members: [Int32]
    var cpu: Double?
    var memory: UInt64?
    var bundlePath: String?
    var mixedMemorySources: Bool

    var nameSort: String { name.lowercased() }
    var cpuSort: Double { cpu ?? -1 }
    var memorySort: Double { memory.map(Double.init) ?? -1 }
    var countSort: Int { members.count }
}

@MainActor
final class ProcessStore: ObservableObject {
    @Published private(set) var rows: [ProcessRow] = []
    @Published private(set) var families: [FamilyRow] = []
    @Published private(set) var othersAvailable = true
    @Published private(set) var loaded = false
    @Published private(set) var lastUpdate: Date?
    /// Anzahl je Filter – einmal je Messung berechnet statt bei jedem Neuzeichnen.
    @Published private(set) var filterCounts: [ProcessFilter: Int] = [:]
    /// Verlauf der CPU-Last des ausgewählten Prozesses.
    @Published private(set) var selectedHistory = RingBuffer<Double>(capacity: sparklineCapacity)
    var selectedPID: Int32? {
        didSet { if selectedPID != oldValue { selectedHistory.removeAll() } }
    }

    private var userNames: [UInt32: String] = [:]
    private let ownPID = getpid()
    /// Zwischenspeicher für Angaben, die sich während der Laufzeit eines Prozesses nicht ändern.
    private var protectionCache: [Int32: (name: String, protection: ProcessProtection)] = [:]
    private var bundleNames: [String: String] = [:]
    private var cpuSmoothers: [Int32: (start: Date?, ema: AsymmetricEMA)] = [:]

    func apply(snapshot: ProcessSnapshot, cpu: [ProcessIdentity: Double]) {
        var apps: [Int32: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications { apps[app.processIdentifier] = app }

        let inputs = snapshot.samples.map { s in
            FamilyBuilder.Input(pid: s.pid, ppid: s.ppid, name: s.name, path: s.path, cpu: cpu[s.identity],
                                memory: s.memory, source: s.source)
        }
        let familyKeys = FamilyBuilder.familyKeys(inputs)

        var next: [ProcessRow] = []
        next.reserveCapacity(snapshot.samples.count)
        let time = ProcessInfo.processInfo.systemUptime
        var seen = Set<Int32>()
        for s in snapshot.samples {
            seen.insert(s.pid)
            let app = apps[s.pid]
            let user = userNames[s.uid] ?? {
                let name = ProcessControl.userName(uid: s.uid)
                userNames[s.uid] = name
                return name
            }()
            let fileName = s.path.map { ($0 as NSString).lastPathComponent }
            let display = app?.localizedName ?? (fileName.flatMap { $0.isEmpty ? nil : $0 } ?? s.name)
            let familyKey = familyKeys[s.pid] ?? "pid:\(s.pid)"
            let protection: ProcessProtection
            if let cached = protectionCache[s.pid], cached.name == s.name {
                protection = cached.protection
            } else {
                protection = ProcessProtection.evaluate(pid: s.pid, name: s.name, uid: s.uid, currentUID: snapshot.currentUID,
                                                        ownPID: ownPID, path: s.path)
                protectionCache[s.pid] = (s.name, protection)
            }
            let raw = cpu[s.identity]
            var smoothedCPU: Double?
            if let raw {
                // Neuer Prozess unter derselben PID (anderer Start): Glättung neu beginnen
                var entry = cpuSmoothers[s.pid] ?? (s.startTime, AsymmetricEMA(rise: 0.8, fall: 2.5))
                if entry.start != s.startTime { entry = (s.startTime, AsymmetricEMA(rise: 0.8, fall: 2.5)) }
                smoothedCPU = entry.ema.update(raw, at: time)
                cpuSmoothers[s.pid] = entry
            }
            next.append(ProcessRow(
                id: s.pid, ppid: s.ppid, uid: s.uid, user: user, name: display, command: s.name, path: s.path,
                state: s.state, startTime: s.startTime, isTranslated: s.isTranslated, cpu: smoothedCPU, cpuRaw: raw,
                memory: s.memory, threads: s.threads, source: s.source, appName: app?.localizedName,
                bundleID: app?.bundleIdentifier, bundlePath: app?.bundleURL?.path ?? (familyKey.hasPrefix("pid:") ? nil : familyKey),
                isApp: app?.activationPolicy == .regular, isOwn: s.uid == snapshot.currentUID, familyKey: familyKey,
                protection: protection))
        }
        // Beendete Prozesse vergessen
        if protectionCache.count > seen.count + 64 { protectionCache = protectionCache.filter { seen.contains($0.key) } }
        cpuSmoothers = cpuSmoothers.filter { seen.contains($0.key) }

        let builtFamilies = FamilyBuilder.families(inputs).map { family -> FamilyRow in
            let bundle = family.id.hasPrefix("pid:") ? nil : family.id
            var name = family.name
            if let bundle {
                if let cached = bundleNames[bundle] {
                    name = cached
                } else {
                    name = (FileManager.default.displayName(atPath: bundle) as NSString).deletingPathExtension
                    bundleNames[bundle] = name
                }
            }
            return FamilyRow(id: family.id, name: name, members: family.members, cpu: family.cpu, memory: family.memory,
                             bundlePath: bundle, mixedMemorySources: family.mixedMemorySources)
        }

        var counts: [ProcessFilter: Int] = [:]
        for filter in ProcessFilter.allCases {
            counts[filter] = next.reduce(0) { $0 + (filter.passes($1) ? 1 : 0) }
        }
        rows = next
        families = builtFamilies
        if counts != filterCounts { filterCounts = counts }
        othersAvailable = snapshot.othersAvailable
        loaded = true
        lastUpdate = snapshot.timestamp
        if let selectedPID, let value = next.first(where: { $0.pid == selectedPID })?.cpu {
            selectedHistory.append(value)
        }
    }

    func row(_ pid: Int32) -> ProcessRow? { rows.first { $0.pid == pid } }

    /// Die größten Verbraucher (für CPU- und Speicherseite).
    func top(by key: KeyPath<ProcessRow, Double>, limit: Int) -> [ProcessRow] {
        Array(rows.filter { $0[keyPath: key] > 0 }.sorted { $0[keyPath: key] > $1[keyPath: key] }.prefix(limit))
    }
}

/// Symbole für Prozesse und Apps (zwischengespeichert).
@MainActor
enum IconCache {
    private static var byPID: [Int32: NSImage] = [:]
    private static var byPath: [String: NSImage] = [:]
    private static let executable: NSImage = NSWorkspace.shared.icon(for: .unixExecutable)

    static func icon(pid: Int32, bundlePath: String?) -> NSImage {
        if let cached = byPID[pid] { return cached }
        if let app = NSRunningApplication(processIdentifier: pid), let icon = app.icon {
            byPID[pid] = icon
            return icon
        }
        if let bundlePath { return icon(path: bundlePath) }
        return executable
    }

    static func icon(path: String) -> NSImage {
        if let cached = byPath[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        byPath[path] = icon
        return icon
    }

    static func trim() {
        if byPID.count > 600 { byPID.removeAll() }
    }
}
