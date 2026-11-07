import Foundation

// =============================================================================================
// Netzwerk: Schnittstellen einordnen, Verbindungen aus `netstat -anv` lesen, WLAN-Kennwerte benennen.
// Lokaler Verlauf: Minutenwerte bilden, für Diagramme verdichten, als CSV schreiben.
// Alles hier ist reine Logik (unter Linux getestet); die Systemabfragen stehen in AetherSystem.
// =============================================================================================

// MARK: - Schnittstellen

public enum InterfaceKind: String, Sendable, Codable, CaseIterable {
    case wifi, ethernet, vpn, bridge, peerToPeer, cellular, loopback, other
}

public enum InterfaceClassifier {
    /// Einordnung aus dem SystemConfiguration-Typ (`SCNetworkInterfaceGetInterfaceType`, z. B. „IEEE80211“) und dem
    /// BSD-Namen. Der Typ hat Vorrang; ohne Typ entscheidet das übliche Namensschema von macOS.
    public static func kind(bsdName: String, systemType: String?) -> InterfaceKind {
        switch systemType {
        case "IEEE80211": return .wifi
        case "Ethernet", "FireWire": return bsdName.hasPrefix("bridge") ? .bridge : .ethernet
        case "Bridge", "Bond", "VLAN": return .bridge
        case "PPP", "IPSec", "VPN", "L2TP", "PPTP": return .vpn
        case "WWAN": return .cellular
        default: break
        }
        let name = bsdName.lowercased()
        if name.hasPrefix("lo") { return .loopback }
        if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") || name.hasPrefix("tun")
            || name.hasPrefix("tap") || name.hasPrefix("gif") || name.hasPrefix("stf") { return .vpn }
        if name.hasPrefix("bridge") { return .bridge }
        if name.hasPrefix("awdl") || name.hasPrefix("llw") { return .peerToPeer }
        if name.hasPrefix("pdp_ip") { return .cellular }
        if name.hasPrefix("en") { return .ethernet }
        return .other
    }

    /// Reihenfolge in der Liste: aktive physische Verbindungen zuerst.
    public static func sortRank(_ kind: InterfaceKind) -> Int {
        switch kind {
        case .wifi: return 0
        case .ethernet: return 1
        case .vpn: return 2
        case .bridge: return 3
        case .cellular: return 4
        case .peerToPeer: return 5
        case .other: return 6
        case .loopback: return 7
        }
    }
}

public struct InterfaceAddress: Sendable, Equatable, Hashable {
    public var address: String
    public var isIPv6: Bool
    public var prefixLength: Int?

    public init(address: String, isIPv6: Bool, prefixLength: Int?) {
        self.address = address
        self.isIPv6 = isIPv6
        self.prefixLength = prefixLength
    }

    /// IPv6 „link-local“ (fe80::/10) – nur im lokalen Netzsegment gültig.
    public var isLinkLocal: Bool {
        guard isIPv6 else { return address.hasPrefix("169.254.") }
        let lower = address.lowercased()
        return ["fe8", "fe9", "fea", "feb"].contains { lower.hasPrefix($0) }
    }

    /// Anzahl gesetzter Bits einer Netzmaske (Bytes in Netzwerkreihenfolge). Nicht zusammenhängende Masken → nil.
    public static func prefixLength(mask: [UInt8]) -> Int? {
        var count = 0
        var ended = false
        for byte in mask {
            for bit in (0..<8).reversed() {
                let set = (byte >> UInt8(bit)) & 1 == 1
                if set {
                    if ended { return nil }
                    count += 1
                } else {
                    ended = true
                }
            }
        }
        return count
    }
}

public struct NetworkInterfaceInfo: Sendable, Equatable, Identifiable {
    public var id: String { bsdName }
    public var bsdName: String
    /// Name, wie macOS ihn in den Systemeinstellungen zeigt („WLAN“, „Thunderbolt-Brücke“).
    public var displayName: String?
    public var kind: InterfaceKind
    public var isUp: Bool
    public var isRunning: Bool
    public var addresses: [InterfaceAddress]
    /// Schnittstelle der Standardroute (IPv4 oder IPv6).
    public var isPrimary: Bool

    public init(bsdName: String, displayName: String?, kind: InterfaceKind, isUp: Bool, isRunning: Bool,
                addresses: [InterfaceAddress], isPrimary: Bool) {
        self.bsdName = bsdName
        self.displayName = displayName
        self.kind = kind
        self.isUp = isUp
        self.isRunning = isRunning
        self.addresses = addresses
        self.isPrimary = isPrimary
    }

    /// Verbunden: aktiv und mit mindestens einer nicht lokalen Adresse.
    public var isConnected: Bool {
        isUp && isRunning && addresses.contains { !$0.isLinkLocal }
    }

    public var ipv4: [InterfaceAddress] { addresses.filter { !$0.isIPv6 } }
    public var ipv6: [InterfaceAddress] { addresses.filter { $0.isIPv6 } }
}

/// Live-Verkehr einer Schnittstelle (aus den 64-Bit-Zählern).
public struct InterfaceTraffic: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var isUp: Bool
    /// Bytes pro Sekunde; `nil` bis zur zweiten Messung oder nach einer Zählerrücksetzung.
    public var download: Double?
    public var upload: Double?
    /// Seit Start von AETHER übertragen.
    public var sessionDownloaded: UInt64
    public var sessionUploaded: UInt64

    public init(name: String, isUp: Bool, download: Double?, upload: Double?, sessionDownloaded: UInt64, sessionUploaded: UInt64) {
        self.name = name
        self.isUp = isUp
        self.download = download
        self.upload = upload
        self.sessionDownloaded = sessionDownloaded
        self.sessionUploaded = sessionUploaded
    }
}

// MARK: - WLAN

public enum WiFiNames {
    /// `CWChannelBand.rawValue`: 1 = 2,4 GHz, 2 = 5 GHz, 3 = 6 GHz.
    public static func band(rawValue: Int) -> String? {
        switch rawValue {
        case 1: return "2.4 GHz"
        case 2: return "5 GHz"
        case 3: return "6 GHz"
        default: return nil
        }
    }

    /// `CWChannelWidth.rawValue`: 1 = 20, 2 = 40, 3 = 80, 4 = 160 MHz.
    public static func widthMHz(rawValue: Int) -> Int? {
        switch rawValue {
        case 1: return 20
        case 2: return 40
        case 3: return 80
        case 4: return 160
        case 5: return 320
        default: return nil
        }
    }

    /// `CWPHYMode.rawValue` → Standard.
    public static func phyMode(rawValue: Int) -> String? {
        switch rawValue {
        case 1: return "802.11a"
        case 2: return "802.11b"
        case 3: return "802.11g"
        case 4: return "802.11n (Wi‑Fi 4)"
        case 5: return "802.11ac (Wi‑Fi 5)"
        case 6: return "802.11ax (Wi‑Fi 6)"
        case 7: return "802.11be (Wi‑Fi 7)"
        default: return nil
        }
    }

    /// `CWSecurity.rawValue` → Verfahren (nur der Typ – nie Schlüssel oder Passwörter).
    public static func security(rawValue: Int) -> String? {
        switch rawValue {
        case 0: return "none"
        case 1: return "WEP"
        case 2: return "WPA Personal"
        case 3: return "WPA/WPA2 Personal"
        case 4: return "WPA2 Personal"
        case 5: return "Personal"
        case 6: return "Dynamic WEP"
        case 7: return "WPA Enterprise"
        case 8: return "WPA/WPA2 Enterprise"
        case 9: return "WPA2 Enterprise"
        case 10: return "Enterprise"
        case 11: return "WPA3 Personal"
        case 12: return "WPA3 Enterprise"
        case 13: return "WPA2/WPA3 Personal"
        case 14: return "OWE"
        case 15: return "OWE Transition"
        default: return nil
        }
    }

    /// Plausible Signalwerte (dBm). 0 meldet CoreWLAN, wenn keine Verbindung besteht.
    public static func plausibleSignal(_ dBm: Int) -> Bool { dBm < 0 && dBm > -120 }

    /// Signalqualität grob eingeordnet (übliche Faustregeln für RSSI).
    public static func quality(rssi: Int) -> Double {
        // −90 dBm → 0, −50 dBm und besser → 1
        min(1, max(0, Double(rssi + 90) / 40))
    }
}

// MARK: - Verbindungen (netstat -anv)

public enum ConnectionState: String, Sendable, CaseIterable {
    case established = "ESTABLISHED", listen = "LISTEN", synSent = "SYN_SENT", synReceived = "SYN_RECEIVED"
    case finWait1 = "FIN_WAIT_1", finWait2 = "FIN_WAIT_2", closeWait = "CLOSE_WAIT", closing = "CLOSING"
    case lastAck = "LAST_ACK", timeWait = "TIME_WAIT", closed = "CLOSED"
}

public struct ConnectionEndpoint: Sendable, Equatable, Hashable {
    public var host: String
    public var port: String

    public init(host: String, port: String) {
        self.host = host
        self.port = port
    }

    /// netstat schreibt Adresse und Port mit einem Punkt getrennt („192.168.1.2.443“, „fe80::1%lo0.5353“, „*.*“).
    public static func parse(_ text: String) -> ConnectionEndpoint {
        guard let dot = text.lastIndex(of: ".") else { return ConnectionEndpoint(host: text, port: "") }
        return ConnectionEndpoint(host: String(text[..<dot]), port: String(text[text.index(after: dot)...]))
    }

    public var isWildcard: Bool { host == "*" && (port == "*" || port.isEmpty) }

    public var display: String {
        if port.isEmpty || port == "*" { return host == "*" ? "*" : host }
        return host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }
}

public struct NetConnection: Sendable, Equatable, Identifiable {
    public var id: String
    /// „tcp4“, „tcp6“, „udp4“, „udp6“, „tcp46“ …
    public var proto: String
    public var local: ConnectionEndpoint
    public var remote: ConnectionEndpoint
    public var state: ConnectionState?
    public var pid: Int32?
    /// Prozessname aus der Spalte „process:pid“ (neuere macOS-Versionen, gekürzt) oder später ergänzt.
    public var processName: String?

    public init(id: String, proto: String, local: ConnectionEndpoint, remote: ConnectionEndpoint, state: ConnectionState?,
                pid: Int32?, processName: String?) {
        self.id = id
        self.proto = proto
        self.local = local
        self.remote = remote
        self.state = state
        self.pid = pid
        self.processName = processName
    }

    public var isTCP: Bool { proto.hasPrefix("tcp") }
    public var isListening: Bool { state == .listen || (!isTCP && remote.isWildcard) }
}

public struct NetstatParseResult: Sendable, Equatable {
    public var connections: [NetConnection]
    /// Die Ausgabe enthält eine Prozessspalte („pid“ oder „process:pid“).
    public var hasProcessColumn: Bool

    public init(connections: [NetConnection], hasProcessColumn: Bool) {
        self.connections = connections
        self.hasProcessColumn = hasProcessColumn
    }
}

public enum NetstatParser {
    /// Liest die Ausgabe von `netstat -anv -p tcp|udp`. Die Spalten werden über die Kopfzeile gefunden (sie
    /// unterscheiden sich zwischen macOS-Versionen). Unlesbare Zeilen werden übersprungen, nicht geraten.
    public static func parse(_ text: String) -> NetstatParseResult {
        var result: [NetConnection] = []
        var columns: [String] = []
        var hasProcess = false
        var seen: [String: Int] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            if line.hasPrefix("Proto") {
                columns = headerColumns(line)
                hasProcess = columns.contains { $0 == "pid" || $0 == "process:pid" }
                continue
            }
            guard let first = line.split(separator: " ").first, first.hasPrefix("tcp") || first.hasPrefix("udp") else { continue }
            guard !columns.isEmpty else { continue }
            var tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard tokens.count >= 5 else { continue }
            guard let stateIndex = columns.firstIndex(of: "(state)") else { continue }
            // UDP (und manche TCP-Zeilen) haben keinen Zustand: eine leere Spalte einschieben, damit der Rest passt.
            if tokens.count > stateIndex {
                if ConnectionState(rawValue: tokens[stateIndex]) == nil && !tokens[stateIndex].isEmpty
                    && looksLikeValue(tokens[stateIndex]) {
                    tokens.insert("", at: stateIndex)
                }
            }
            let proto = tokens[0]
            guard let localIndex = columns.firstIndex(of: "local-address"),
                  let remoteIndex = columns.firstIndex(of: "foreign-address"),
                  tokens.count > max(localIndex, remoteIndex) else { continue }
            let local = ConnectionEndpoint.parse(tokens[localIndex])
            let remote = ConnectionEndpoint.parse(tokens[remoteIndex])
            let state = tokens.count > stateIndex ? ConnectionState(rawValue: tokens[stateIndex]) : nil

            var pid: Int32?
            var name: String?
            if let pidIndex = columns.firstIndex(of: "pid"), tokens.count > pidIndex {
                pid = Int32(tokens[pidIndex]).flatMap { $0 > 0 ? $0 : nil }
            } else if let processIndex = columns.firstIndex(of: "process:pid"), tokens.count > processIndex {
                // Namen können Leerzeichen enthalten: Tokens zusammenfügen, bis eines auf „:Zahl“ endet.
                var joined = ""
                var index = processIndex
                while index < tokens.count {
                    joined += (joined.isEmpty ? "" : " ") + tokens[index]
                    if let parsed = splitProcess(joined) {
                        pid = parsed.pid
                        name = parsed.name
                        break
                    }
                    index += 1
                    if index - processIndex > 6 { break }
                }
            }
            // Stabile Kennung über Aktualisierungen hinweg; gleiche Zeilen werden durchnummeriert.
            let base = "\(proto)|\(local.host)|\(local.port)|\(remote.host)|\(remote.port)|\(pid ?? 0)"
            let duplicate = seen[base, default: 0]
            seen[base] = duplicate + 1
            let id = duplicate == 0 ? base : "\(base)#\(duplicate)"
            result.append(NetConnection(id: id, proto: proto, local: local, remote: remote, state: state, pid: pid,
                                        processName: name))
        }
        return NetstatParseResult(connections: result, hasProcessColumn: hasProcess)
    }

    /// Kopfzeile in Spalten zerlegen; „Local Address“ und „Foreign Address“ sind je eine Spalte.
    static func headerColumns(_ line: String) -> [String] {
        let normalized = line.replacingOccurrences(of: "Local Address", with: "local-address")
            .replacingOccurrences(of: "Foreign Address", with: "foreign-address")
        return normalized.split(whereSeparator: { $0 == " " || $0 == "\t" }).map { $0.lowercased() }
    }

    /// Zahl oder Hexwert (also kein Zustand).
    static func looksLikeValue(_ token: String) -> Bool {
        if Int(token) != nil { return true }
        return token.hasPrefix("0x")
    }

    /// „Safari:1234“ → (Safari, 1234). Der Name selbst kann Doppelpunkte enthalten.
    static func splitProcess(_ text: String) -> (name: String, pid: Int32)? {
        guard let colon = text.lastIndex(of: ":"), let pid = Int32(text[text.index(after: colon)...]), pid >= 0 else { return nil }
        let name = String(text[..<colon]).trimmingCharacters(in: .whitespaces)
        return (name, pid)
    }
}

public enum ConnectionFilter: String, Sendable, CaseIterable {
    case all, established, listening

    public func matches(_ connection: NetConnection) -> Bool {
        switch self {
        case .all: return true
        case .established: return connection.state == .established
        case .listening: return connection.isListening
        }
    }
}

public enum ConnectionSearch {
    /// Groß-/Kleinschreibung egal; durchsucht Prozess, PID, Adressen, Ports, Protokoll und Zustand.
    public static func matches(_ connection: NetConnection, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        let fields = [connection.processName ?? "", connection.pid.map { String($0) } ?? "", connection.local.display,
                      connection.remote.display, connection.proto, connection.state?.rawValue ?? ""]
        return fields.contains { $0.lowercased().contains(q) }
    }

    /// Reihenfolge: aufgebaute Verbindungen, dann lauschende, dann der Rest; innerhalb nach Prozess.
    public static func sorted(_ list: [NetConnection]) -> [NetConnection] {
        func rank(_ c: NetConnection) -> Int {
            if c.state == .established { return 0 }
            if c.isListening { return 1 }
            return 2
        }
        return list.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            let na = a.processName ?? "~", nb = b.processName ?? "~"
            if na != nb { return na.localizedCaseInsensitiveCompare(nb) == .orderedAscending }
            return a.id < b.id
        }
    }
}

// MARK: - Lokaler Verlauf

/// Ein Minutenwert. `nil` = in dieser Minute nicht gemessen (wird als NULL gespeichert, nie ersetzt).
public struct HistorySample: Sendable, Equatable {
    public var time: Date
    public var cpuBusy: Double?
    public var memoryUsed: Double?
    public var pressure: Int?
    public var swapUsed: Double?
    public var download: Double?
    public var upload: Double?
    public var batteryPercent: Double?
    public var batteryPower: Double?
    public var hottest: Double?
    public var thermalState: Int?

    public init(time: Date, cpuBusy: Double? = nil, memoryUsed: Double? = nil, pressure: Int? = nil, swapUsed: Double? = nil,
                download: Double? = nil, upload: Double? = nil, batteryPercent: Double? = nil, batteryPower: Double? = nil,
                hottest: Double? = nil, thermalState: Int? = nil) {
        self.time = time
        self.cpuBusy = cpuBusy
        self.memoryUsed = memoryUsed
        self.pressure = pressure
        self.swapUsed = swapUsed
        self.download = download
        self.upload = upload
        self.batteryPercent = batteryPercent
        self.batteryPower = batteryPower
        self.hottest = hottest
        self.thermalState = thermalState
    }
}

public enum HistoryMetric: String, Sendable, CaseIterable, Identifiable {
    case cpu, memory, pressure, swap, download, upload, batteryPercent, batteryPower, temperature, thermalState
    public var id: String { rawValue }

    public func value(in sample: HistorySample) -> Double? {
        switch self {
        case .cpu: return sample.cpuBusy
        case .memory: return sample.memoryUsed
        case .pressure: return sample.pressure.map { Double($0) }
        case .swap: return sample.swapUsed
        case .download: return sample.download
        case .upload: return sample.upload
        case .batteryPercent: return sample.batteryPercent
        case .batteryPower: return sample.batteryPower.map { abs($0) }
        case .temperature: return sample.hottest
        case .thermalState: return sample.thermalState.map { Double($0) }
        }
    }

    /// Stufen (Speicherdruck, Thermalstatus) werden beim Verdichten nicht gemittelt, sondern mit ihrem Maximum gezeigt.
    public var usesMaximum: Bool { self == .pressure || self == .thermalState }

    /// Fester Maßstab für Anteile und Stufen; `nil` = am Maximum ausrichten.
    public var fixedMaximum: Double? {
        switch self {
        case .cpu, .memory: return 1
        case .batteryPercent: return 100
        case .pressure: return 4
        case .thermalState: return 3
        default: return nil
        }
    }
}

public enum HistoryRange: Int, Sendable, CaseIterable, Identifiable {
    case hour = 3_600, day = 86_400, week = 604_800, month = 2_592_000
    public var id: Int { rawValue }
    public var seconds: TimeInterval { TimeInterval(rawValue) }
}

/// Sammelt die Messungen einer Minute und bildet daraus einen Minutenwert: Mittelwerte für Größen, das Maximum
/// für Stufen (Speicherdruck, Thermalstatus) – eine kurze Warnstufe soll nicht weggemittelt werden.
public struct HistoryAccumulator: Sendable {
    private var minute: Int?
    private var sums: [String: (sum: Double, count: Int)] = [:]
    private var maxima: [String: Int] = [:]

    public init() {}

    static func minuteIndex(_ date: Date) -> Int { Int((date.timeIntervalSince1970 / 60).rounded(.down)) }

    /// Fügt eine Messung hinzu. Beginnt eine neue Minute, wird der fertige Wert der vorigen zurückgegeben.
    public mutating func add(_ sample: HistorySample) -> HistorySample? {
        let index = Self.minuteIndex(sample.time)
        var finished: HistorySample?
        if let minute, minute != index {
            finished = flush()
        }
        minute = index
        for (key, value) in [("cpu", sample.cpuBusy), ("mem", sample.memoryUsed), ("swap", sample.swapUsed),
                             ("down", sample.download), ("up", sample.upload), ("bat", sample.batteryPercent),
                             ("batw", sample.batteryPower), ("temp", sample.hottest)] {
            guard let value, value.isFinite else { continue }
            let current = sums[key] ?? (sum: 0, count: 0)
            sums[key] = (sum: current.sum + value, count: current.count + 1)
        }
        if let p = sample.pressure { maxima["pressure"] = max(maxima["pressure"] ?? p, p) }
        if let t = sample.thermalState { maxima["thermal"] = max(maxima["thermal"] ?? t, t) }
        return finished
    }

    /// Den angefangenen Minutenwert abschließen (z. B. beim Beenden).
    public mutating func flush() -> HistorySample? {
        guard let minute else { return nil }
        func avg(_ key: String) -> Double? {
            guard let entry = sums[key], entry.count > 0 else { return nil }
            return entry.sum / Double(entry.count)
        }
        let hasData = !sums.isEmpty || !maxima.isEmpty
        let sample = HistorySample(time: Date(timeIntervalSince1970: Double(minute) * 60),
                                   cpuBusy: avg("cpu"), memoryUsed: avg("mem"), pressure: maxima["pressure"],
                                   swapUsed: avg("swap"), download: avg("down"), upload: avg("up"),
                                   batteryPercent: avg("bat"), batteryPower: avg("batw"), hottest: avg("temp"),
                                   thermalState: maxima["thermal"])
        self.minute = nil
        sums = [:]
        maxima = [:]
        return hasData ? sample : nil
    }
}

/// Punkt eines verdichteten Verlaufs: `x` 0…1 über den Zeitraum, `value` = Mittel des Abschnitts oder `nil` (Lücke).
public struct TimelinePoint: Sendable, Equatable {
    public var x: Double
    public var value: Double?

    public init(x: Double, value: Double?) {
        self.x = x
        self.value = value
    }
}

public struct TimelineSummary: Sendable, Equatable {
    public var minimum: Double
    public var average: Double
    public var maximum: Double
    public var count: Int

    public init(minimum: Double, average: Double, maximum: Double, count: Int) {
        self.minimum = minimum
        self.average = average
        self.maximum = maximum
        self.count = count
    }
}

public enum HistoryBucketing {
    /// Verdichtet Minutenwerte auf höchstens `buckets` Abschnitte im Zeitraum [start, end]. Abschnitte ohne Messung
    /// bleiben leer (Lücke im Diagramm) – es wird nichts interpoliert.
    public static func points(_ samples: [HistorySample], metric: HistoryMetric, start: Date, end: Date,
                              buckets: Int) -> [TimelinePoint] {
        let span = end.timeIntervalSince(start)
        guard span > 0, buckets > 0 else { return [] }
        var sums = [Double](repeating: 0, count: buckets)
        var maxima = [Double](repeating: -Double.infinity, count: buckets)
        var counts = [Int](repeating: 0, count: buckets)
        for sample in samples {
            guard let value = metric.value(in: sample) else { continue }
            let offset = sample.time.timeIntervalSince(start)
            guard offset >= 0, offset <= span else { continue }
            let index = min(buckets - 1, Int(offset / span * Double(buckets)))
            sums[index] += value
            maxima[index] = max(maxima[index], value)
            counts[index] += 1
        }
        return (0..<buckets).map { index in
            let value: Double? = counts[index] > 0 ? (metric.usesMaximum ? maxima[index] : sums[index] / Double(counts[index])) : nil
            return TimelinePoint(x: (Double(index) + 0.5) / Double(buckets), value: value)
        }
    }

    public static func summary(_ samples: [HistorySample], metric: HistoryMetric) -> TimelineSummary? {
        let values = samples.compactMap { metric.value(in: $0) }
        guard let minimum = values.min(), let maximum = values.max() else { return nil }
        return TimelineSummary(minimum: minimum, average: values.reduce(0, +) / Double(values.count), maximum: maximum,
                               count: values.count)
    }
}

public enum HistoryCSV {
    public static let header = ["time_utc", "cpu_busy_fraction", "memory_used_fraction", "memory_pressure_level",
                                "swap_used_bytes", "download_bytes_per_s", "upload_bytes_per_s", "battery_percent",
                                "battery_power_watts", "hottest_sensor_celsius", "thermal_state"]

    /// CSV (RFC 4180, Komma, Punkt als Dezimalzeichen, leere Felder für „nicht gemessen“, Zeit in UTC nach ISO 8601).
    public static func make(_ samples: [HistorySample]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        func number(_ value: Double?) -> String {
            guard let value, value.isFinite else { return "" }
            // Swift-Darstellung: unabhängig von der Region, kürzeste exakte Schreibweise
            return "\(value)"
        }
        func integer(_ value: Int?) -> String { value.map { String($0) } ?? "" }
        var lines = [header.joined(separator: ",")]
        for s in samples {
            lines.append([formatter.string(from: s.time), number(s.cpuBusy), number(s.memoryUsed), integer(s.pressure),
                          number(s.swapUsed), number(s.download), number(s.upload), number(s.batteryPercent),
                          number(s.batteryPower), number(s.hottest), integer(s.thermalState)].joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}
