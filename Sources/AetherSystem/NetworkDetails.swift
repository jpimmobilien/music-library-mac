import Darwin
import Foundation
import SystemConfiguration
import CoreWLAN
import AetherCore

// =============================================================================================
// Netzwerkdetails – nur lesend und ohne eigene Netzwerkverbindungen:
//   Schnittstellen und Adressen  getifaddrs, SystemConfiguration (Name, Typ, Standardroute)
//   WLAN                         CoreWLAN (Signal, Rauschen, Kanal, Rate, Verfahren; Netzname nur mit Ortungsfreigabe)
//   Verbindungen                 /usr/sbin/netstat -anv (liest die Socket-Tabellen des Kernels)
// Bewusst nicht verwendet: socket()/ioctl, Network.framework – der Build prüft, dass keine solchen Symbole enthalten sind.
// =============================================================================================

public enum InterfaceInventory {
    /// Alle Schnittstellen mit Status, Adressen, Anzeigename und Typ. Kann einige Millisekunden dauern (nicht im Hauptthread).
    public static func read() -> [NetworkInterfaceInfo] {
        var flags: [String: UInt32] = [:]
        var addresses: [String: [InterfaceAddress]] = [:]
        var order: [String] = []

        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }
        var cursor = head
        while let entry = cursor {
            let name = String(cString: entry.pointee.ifa_name)
            if flags[name] == nil {
                order.append(name)
                flags[name] = entry.pointee.ifa_flags
            } else {
                flags[name] = (flags[name] ?? 0) | entry.pointee.ifa_flags
            }
            if let address = entry.pointee.ifa_addr, let parsed = parse(address, mask: entry.pointee.ifa_netmask) {
                addresses[name, default: []].append(parsed)
            }
            cursor = entry.pointee.ifa_next
        }

        // Anzeigename und Typ aus SystemConfiguration (Tunnel und AirDrop fehlen dort – dann gilt das Namensschema)
        var displayNames: [String: String] = [:]
        var types: [String: String] = [:]
        if let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for interface in all {
                guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
                if let display = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? { displayNames[bsd] = display }
                if let type = SCNetworkInterfaceGetInterfaceType(interface) as String? { types[bsd] = type }
            }
        }
        let primary = primaryInterfaces()

        return order.map { name -> NetworkInterfaceInfo in
            let f = flags[name] ?? 0
            let unique = Array(Set(addresses[name] ?? [])).sorted { a, b in
                if a.isIPv6 != b.isIPv6 { return !a.isIPv6 }
                if a.isLinkLocal != b.isLinkLocal { return !a.isLinkLocal }
                return a.address < b.address
            }
            return NetworkInterfaceInfo(bsdName: name, displayName: displayNames[name],
                                        kind: InterfaceClassifier.kind(bsdName: name, systemType: types[name]),
                                        isUp: f & UInt32(IFF_UP) != 0, isRunning: f & UInt32(IFF_RUNNING) != 0,
                                        addresses: unique, isPrimary: primary.contains(name))
        }
        .sorted { a, b in
            if a.isPrimary != b.isPrimary { return a.isPrimary }
            if a.isConnected != b.isConnected { return a.isConnected }
            let ra = InterfaceClassifier.sortRank(a.kind), rb = InterfaceClassifier.sortRank(b.kind)
            if ra != rb { return ra < rb }
            return a.bsdName.localizedStandardCompare(b.bsdName) == .orderedAscending
        }
    }

    /// Adresse als Text (numerisch, ohne Namensauflösung) und Präfixlänge aus der Netzmaske.
    private static func parse(_ address: UnsafeMutablePointer<sockaddr>, mask: UnsafeMutablePointer<sockaddr>?) -> InterfaceAddress? {
        switch Int32(address.pointee.sa_family) {
        case AF_INET:
            var value = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &value, &buffer, socklen_t(buffer.count)) != nil else { return nil }
            let offset = MemoryLayout<sockaddr_in>.offset(of: \sockaddr_in.sin_addr) ?? 4
            let prefix = mask.flatMap { maskBytes($0, offset: offset, count: 4) }.flatMap { InterfaceAddress.prefixLength(mask: $0) }
            return InterfaceAddress(address: String(cString: buffer), isIPv6: false, prefixLength: prefix)
        case AF_INET6:
            var value = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
            // KAME: Bei link-lokalen Adressen steht die Schnittstellennummer in Byte 2–3 – für die Anzeige entfernen.
            withUnsafeMutableBytes(of: &value) { bytes in
                if bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80 {
                    bytes[2] = 0
                    bytes[3] = 0
                }
            }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &value, &buffer, socklen_t(buffer.count)) != nil else { return nil }
            let offset = MemoryLayout<sockaddr_in6>.offset(of: \sockaddr_in6.sin6_addr) ?? 8
            let prefix = mask.flatMap { maskBytes($0, offset: offset, count: 16) }.flatMap { InterfaceAddress.prefixLength(mask: $0) }
            return InterfaceAddress(address: String(cString: buffer), isIPv6: true, prefixLength: prefix)
        default:
            return nil
        }
    }

    /// Netzmasken sind in BSD oft verkürzt (`sa_len` kleiner als die Struktur): nur vorhandene Bytes lesen, Rest = 0.
    private static func maskBytes(_ mask: UnsafeMutablePointer<sockaddr>, offset: Int, count: Int) -> [UInt8]? {
        let length = Int(mask.pointee.sa_len)
        guard length > offset else { return nil }
        let raw = UnsafeRawPointer(mask)
        return (0..<count).map { index in
            offset + index < length ? raw.load(fromByteOffset: offset + index, as: UInt8.self) : 0
        }
    }

    /// Schnittstellen der Standardrouten (IPv4 und IPv6) laut SystemConfiguration.
    public static func primaryInterfaces() -> Set<String> {
        guard let store = SCDynamicStoreCreate(nil, "AETHER" as CFString, nil, nil) else { return [] }
        var result: Set<String> = []
        for key in ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] {
            if let dictionary = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
               let name = dictionary["PrimaryInterface"] as? String {
                result.insert(name)
            }
        }
        return result
    }
}

// MARK: - WLAN

/// WLAN-Kennwerte. Passwörter und Schlüssel werden nie gelesen. Den Netzwerknamen gibt macOS (ab 14) nur bei
/// erteilter Ortungsfreigabe heraus – sonst ist `ssid` nil.
public struct WiFiDetails: Sendable, Equatable {
    public var interfaceName: String?
    public var isPoweredOn: Bool
    public var ssid: String?
    /// dBm; nil = nicht verbunden oder unplausibel.
    public var rssi: Int?
    public var noise: Int?
    public var channel: Int?
    public var band: String?
    public var channelWidthMHz: Int?
    /// Mbit/s
    public var transmitRate: Double?
    public var phyMode: String?
    public var security: String?
    public var countryCode: String?
    /// mW
    public var transmitPower: Int?

    public init(interfaceName: String?, isPoweredOn: Bool, ssid: String?, rssi: Int?, noise: Int?, channel: Int?, band: String?,
                channelWidthMHz: Int?, transmitRate: Double?, phyMode: String?, security: String?, countryCode: String?,
                transmitPower: Int?) {
        self.interfaceName = interfaceName
        self.isPoweredOn = isPoweredOn
        self.ssid = ssid
        self.rssi = rssi
        self.noise = noise
        self.channel = channel
        self.band = band
        self.channelWidthMHz = channelWidthMHz
        self.transmitRate = transmitRate
        self.phyMode = phyMode
        self.security = security
        self.countryCode = countryCode
        self.transmitPower = transmitPower
    }

    /// Mit einem Netz verbunden (plausibles Signal).
    public var isAssociated: Bool { rssi != nil }

    /// Signal-Rausch-Abstand in dB (berechnet).
    public var snr: Int? {
        guard let rssi, let noise else { return nil }
        return rssi - noise
    }
}

public enum WiFiSource {
    /// `nil` = dieser Mac hat kein WLAN (oder CoreWLAN meldet keine Schnittstelle, z. B. in virtuellen Macs).
    public static func sample() -> WiFiDetails? {
        guard let interface = CWWiFiClient.shared().interface() else { return nil }
        let powered = interface.powerOn()
        guard powered else {
            return WiFiDetails(interfaceName: interface.interfaceName, isPoweredOn: false, ssid: nil, rssi: nil, noise: nil,
                               channel: nil, band: nil, channelWidthMHz: nil, transmitRate: nil, phyMode: nil, security: nil,
                               countryCode: nil, transmitPower: nil)
        }
        let rawRSSI = interface.rssiValue()
        let rawNoise = interface.noiseMeasurement()
        let rssi = WiFiNames.plausibleSignal(rawRSSI) ? rawRSSI : nil
        let noise = rssi != nil && WiFiNames.plausibleSignal(rawNoise) ? rawNoise : nil
        let channel = rssi != nil ? interface.wlanChannel() : nil
        let rate = interface.transmitRate()
        let power = interface.transmitPower()
        let ssid = interface.ssid().flatMap { $0.isEmpty ? nil : $0 }
        return WiFiDetails(interfaceName: interface.interfaceName,
                           isPoweredOn: true,
                           ssid: ssid,
                           rssi: rssi,
                           noise: noise,
                           channel: channel.map { $0.channelNumber }.flatMap { $0 > 0 ? $0 : nil },
                           band: channel.flatMap { WiFiNames.band(rawValue: $0.channelBand.rawValue) },
                           channelWidthMHz: channel.flatMap { WiFiNames.widthMHz(rawValue: $0.channelWidth.rawValue) },
                           transmitRate: rssi != nil && rate > 0 && rate < 100_000 ? rate : nil,
                           phyMode: rssi != nil ? WiFiNames.phyMode(rawValue: interface.activePHYMode().rawValue) : nil,
                           security: rssi != nil ? WiFiNames.security(rawValue: interface.security().rawValue) : nil,
                           countryCode: interface.countryCode().flatMap { $0.isEmpty ? nil : $0 },
                           transmitPower: rssi != nil && power > 0 && power < 10_000 ? power : nil)
    }
}

// MARK: - Verbindungen

public enum ConnectionSource {
    /// Liest TCP- und UDP-Sockets über `netstat -anv` (ohne Administratorrechte). Läuft einige Hundert Millisekunden –
    /// nie im Hauptthread aufrufen.
    public static func sample(at date: Date = Date(), timeout: TimeInterval = 8) -> Reading<NetstatParseResult> {
        var connections: [NetConnection] = []
        var hasProcess = false
        var answered = false
        for proto in ["tcp", "udp"] {
            // -W: lange (IPv6-)Adressen nicht abschneiden; ältere Versionen ohne -W: ohne erneut versuchen
            guard let data = HardwareSource.run("/usr/sbin/netstat", ["-a", "-n", "-v", "-W", "-p", proto], timeout: timeout)
                    ?? HardwareSource.run("/usr/sbin/netstat", ["-a", "-n", "-v", "-p", proto], timeout: timeout) else { continue }
            answered = true
            let parsed = NetstatParser.parse(String(decoding: data, as: UTF8.self))
            connections += parsed.connections
            hasProcess = hasProcess || parsed.hasProcessColumn
        }
        guard answered else { return Reading(unavailable: .queryFailed, source: .connections, at: date) }

        // Prozessnamen ergänzen, wo netstat nur die PID nennt
        var names: [Int32: String] = [:]
        var table: [Int32: String]?
        for index in connections.indices {
            guard connections[index].processName == nil, let pid = connections[index].pid else { continue }
            if let cached = names[pid] {
                connections[index].processName = cached
                continue
            }
            var name = processName(pid: pid)
            if name == nil {
                if table == nil { table = kernelNames() }
                name = table?[pid]
            }
            if let name {
                names[pid] = name
                connections[index].processName = name
            }
        }
        return Reading(NetstatParseResult(connections: connections, hasProcessColumn: hasProcess), source: .connections, at: date)
    }

    private static func processName(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let name = String(cString: buffer)
        return name.isEmpty ? nil : name
    }

    /// Kurznamen aller Prozesse aus der Kernel-Prozesstabelle (für fremde Prozesse, deren Name libproc nicht liefert).
    private static func kernelNames() -> [Int32: String] {
        guard let table = ProcessSource.kernelTable() else { return [:] }
        var result: [Int32: String] = [:]
        for var entry in table {
            let name = withUnsafeBytes(of: &entry.kp_proc.p_comm) { raw in
                String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            if !name.isEmpty { result[entry.kp_proc.p_pid] = name }
        }
        return result
    }
}
