import SwiftUI
import AppKit
import AetherCore
import AetherSystem

/// Netzwerk: Durchsatz mit Verlauf, Schnittstellen mit Adressen und eigenem Verkehr, WLAN-Kennwerte, aktive
/// Verbindungen und der lokale Langzeitverlauf. AETHER baut dabei selbst keine Verbindung auf.
struct NetworkView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.aether) private var theme
    @StateObject private var details = NetworkDetailsStore()
    @StateObject private var location = LocationAccess()

    var body: some View {
        let engine = model.engine
        let primary = details.primary
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: theme.density.cardSpacing + 4) {
                StudioHero(section: .network, eyebrow: tr("Network"), headline: headline,
                           lead: tr("Throughput counts only network adapters with a routable address (Ethernet, Wi‑Fi). VPN tunnels and internal links are listed separately, so nothing counts twice."),
                           height: 250) {
                    NetworkHero(telemetry: engine.telemetry, network: engine.network,
                                deviceKind: engine.system.hardware.kind,
                                interfaceName: primary.map { $0.displayName ?? interfaceKindName($0.kind) },
                                interfaceSymbol: primary.map { interfaceSymbol($0.kind) } ?? "network",
                                address: primary?.ipv4.first?.address)
                }
                ThroughputPanel(store: engine.network, telemetry: engine.telemetry)
                InterfacesPanel(details: details, traffic: engine.network)
                WiFiPanel(details: details, location: location, isSnapshot: model.launchMode.isSnapshot)
                ConnectionsPanel(details: details)
                HistoryTimelinePanel(metrics: [.download, .upload])
                NoticeBar(text: tr("AETHER makes no network connections itself. It only reads the counters, interface details and socket tables macOS provides."),
                          symbol: "lock.shield")
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.gutter)
        }
        .task { await details.run() }
    }

    /// Aussage: über welche Schnittstelle der Mac verbunden ist – oder ehrlich, dass keine aktiv ist.
    private var headline: String {
        guard let primary = details.primary else {
            return details.interfacesLoaded ? tr("No active connection") : tr("Interfaces, Wi‑Fi and connections")
        }
        return tr("Connected via %@", primary.displayName ?? interfaceKindName(primary.kind))
    }
}

func interfaceKindName(_ kind: InterfaceKind) -> String {
    switch kind {
    case .wifi: return tr("Wi‑Fi")
    case .ethernet: return tr("Ethernet")
    case .vpn: return tr("VPN / tunnel")
    case .bridge: return tr("Bridge")
    case .peerToPeer: return tr("Peer-to-peer (AirDrop)")
    case .cellular: return tr("Cellular")
    case .loopback: return tr("Loopback")
    case .other: return tr("Other")
    }
}

func interfaceSymbol(_ kind: InterfaceKind) -> String {
    switch kind {
    case .wifi: return SymbolName.wifi
    case .ethernet: return SymbolName.ethernet
    case .vpn: return SymbolName.vpn
    case .bridge: return "link"
    case .peerToPeer: return SymbolName.pick("dot.radiowaves.left.and.right", "antenna.radiowaves.left.and.right")
    case .cellular: return "antenna.radiowaves.left.and.right"
    case .loopback: return "arrow.triangle.2.circlepath"
    case .other: return "network"
    }
}

// MARK: - Durchsatz

private struct ThroughputPanel: View {
    @ObservedObject var store: NetworkStore
    let telemetry: Telemetry
    @Environment(\.aether) private var theme
    @AppStorage("aether.network.range") private var range: ChartRange = .fiveMinutes

    var body: some View {
        let down = telemetry.series(.networkDown, unit: .bytesPerSecond)
        let up = telemetry.series(.networkUp, unit: .bytesPerSecond)
        Panel {
            HStack(alignment: .center, spacing: Spacing.l) {
                PanelTitle(title: tr("Throughput"), symbol: "arrow.up.arrow.down")
                RangePicker(range: $range)
            }
            LiveChart(series: down, secondary: up, range: range, color: theme.networkDown, secondaryColor: theme.networkUp,
                      scale: .auto(minimum: 10_000), height: 150, label: { fmt.rate($0) })
                .help(tr("Short spikes stay visible: the large numbers show the peak of the last 10 seconds, the history band the lowest and highest value of each time slice."))
            HStack(alignment: .top, spacing: Spacing.xxl) {
                SeriesLegend(items: [(tr("Download"), theme.networkDown), (tr("Upload"), theme.networkUp)])
                Spacer(minLength: Spacing.l)
                VStack(alignment: .leading, spacing: 5) {
                    InfoRow(label: tr("Received since AETHER started"), value: fmt.bytes(store.snapshot?.sessionDownloaded ?? 0),
                            source: .interfaceCounters)
                    InfoRow(label: tr("Sent since AETHER started"), value: fmt.bytes(store.snapshot?.sessionUploaded ?? 0),
                            source: .interfaceCounters)
                    WindowPeakRow(down: down, up: up, range: range)
                }
                .frame(maxWidth: 360)
            }
            Text(tr("Adds up Ethernet and Wi‑Fi interfaces. VPN tunnels, AirDrop links and loopback are listed separately below and not added – otherwise the same traffic would count twice."))
                .font(Typo.caption)
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Höchste gemessene Rohwerte im gewählten Zeitraum.
private struct WindowPeakRow: View {
    @ObservedObject var down: MetricSeries
    @ObservedObject var up: MetricSeries
    let range: ChartRange

    var body: some View {
        let downPeak = down.raw.maximum(window: range.seconds, now: down.now)
        let upPeak = up.raw.maximum(window: range.seconds, now: up.now)
        InfoRow(label: tr("Peak in this window ↓ / ↑"),
                value: "\(downPeak.map { fmt.rate($0) } ?? "–") / \(upPeak.map { fmt.rate($0) } ?? "–")")
    }
}

// MARK: - Schnittstellen

private struct InterfacesPanel: View {
    @ObservedObject var details: NetworkDetailsStore
    @ObservedObject var traffic: NetworkStore
    @Environment(\.aether) private var theme
    @State private var showAll = false

    var body: some View {
        let all = details.interfaces
        let visible = showAll ? all : all.filter(isRelevant)
        let trafficByName = Dictionary((traffic.snapshot?.interfaces ?? []).map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        Panel {
            HStack(spacing: Spacing.m) {
                PanelTitle(title: tr("Interfaces"), symbol: "network",
                           trailing: details.interfacesLoaded ? tr("%ld active", all.filter { $0.isConnected && $0.kind != .loopback }.count) : nil)
                if details.interfacesLoaded && all.count > visible.count || showAll {
                    Button(showAll ? tr("Show Fewer") : tr("Show All (%ld)", all.count)) { showAll.toggle() }
                        .buttonStyle(CapsuleButtonStyle())
                }
            }
            if !details.interfacesLoaded {
                Text(tr("Measuring…")).font(Typo.callout).foregroundStyle(theme.textSecondary)
            } else if visible.isEmpty {
                HStack {
                    Text(tr("No active network interface")).font(Typo.callout).foregroundStyle(theme.textSecondary)
                    Spacer()
                    ProvenanceBadge(source: .networkInterfaces)
                }
            } else {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, info in
                    if index > 0 { Divider().overlay(theme.hairline) }
                    InterfaceRow(info: info, traffic: trafficByName[info.bsdName])
                }
            }
        }
    }

    /// Standardansicht: verbundene Schnittstellen und eingeschaltete WLAN-/Ethernet-Anschlüsse; kein Loopback.
    private func isRelevant(_ info: NetworkInterfaceInfo) -> Bool {
        if info.kind == .loopback { return false }
        if info.isConnected { return true }
        return (info.kind == .wifi || info.kind == .ethernet) && info.displayName != nil
    }
}

private struct InterfaceRow: View {
    let info: NetworkInterfaceInfo
    let traffic: InterfaceTraffic?
    @Environment(\.aether) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: interfaceSymbol(info.kind))
                .font(.system(size: 16))
                .foregroundStyle(info.isConnected ? theme.accent : theme.textTertiary)
                .frame(width: 26, height: 22)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(info.displayName ?? interfaceKindName(info.kind)).font(Typo.bodyMedium).lineLimit(1)
                    Text(info.bsdName).font(Typo.mono).foregroundStyle(theme.textTertiary)
                    if info.isPrimary && info.isConnected {
                        Text(tr("Default route"))
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(theme.accent.opacity(0.18)))
                            .foregroundStyle(theme.accent)
                    }
                    Spacer(minLength: Spacing.s)
                    Text(statusText)
                        .font(Typo.caption)
                        .foregroundStyle(info.isConnected ? theme.statusNormal : theme.textSecondary)
                    ProvenanceBadge(source: .networkInterfaces)
                }
                let shown = Array(info.addresses.prefix(4))
                ForEach(shown, id: \.self) { address in
                    HStack(spacing: 8) {
                        Text(address.isIPv6 ? "IPv6" : "IPv4")
                            .font(Typo.caption)
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 34, alignment: .leading)
                        Text(address.address + (address.prefixLength.map { "/\($0)" } ?? ""))
                            .font(Typo.mono)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        if address.isLinkLocal {
                            Text(tr("link-local")).font(Typo.caption).foregroundStyle(theme.textTertiary)
                        }
                    }
                }
                if info.addresses.count > shown.count {
                    Text(tr("+ %ld more addresses", info.addresses.count - shown.count))
                        .font(Typo.caption).foregroundStyle(theme.textTertiary)
                }
                if let traffic, traffic.isUp, traffic.download != nil || traffic.sessionDownloaded > 0 || traffic.sessionUploaded > 0 {
                    HStack(spacing: Spacing.l) {
                        Label(traffic.download.map { fmt.rate($0) } ?? "–", systemImage: "arrow.down")
                        Label(traffic.upload.map { fmt.rate($0) } ?? "–", systemImage: "arrow.up")
                        Text(tr("%@ received · %@ sent since AETHER started", fmt.bytes(traffic.sessionDownloaded),
                                fmt.bytes(traffic.sessionUploaded)))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        ProvenanceBadge(source: .interfaceCounters)
                    }
                    .font(Typo.caption)
                    .monospacedDigit()
                    .foregroundStyle(theme.textSecondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var statusText: String {
        if info.isConnected { return tr("Connected") }
        if info.isUp && info.isRunning { return tr("Active, no address") }
        if info.isUp { return tr("On, no link") }
        return tr("Inactive")
    }
}

// MARK: - WLAN

private struct WiFiPanel: View {
    @ObservedObject var details: NetworkDetailsStore
    @ObservedObject var location: LocationAccess
    let isSnapshot: Bool
    @Environment(\.aether) private var theme

    var body: some View {
        Panel {
            PanelTitle(title: tr("Wi‑Fi"), symbol: SymbolName.wifi, trailing: details.wifi?.interfaceName)
            if !details.loaded {
                Text(tr("Measuring…")).font(Typo.callout).foregroundStyle(theme.textSecondary)
            } else if let wifi = details.wifi {
                if !wifi.isPoweredOn {
                    statusLine(tr("Wi‑Fi is turned off"))
                } else if !wifi.isAssociated {
                    statusLine(tr("Not connected to a Wi‑Fi network"))
                } else {
                    connected(wifi)
                }
            } else {
                HStack {
                    Text(tr("This Mac has no Wi‑Fi interface")).font(Typo.callout).foregroundStyle(theme.textSecondary)
                    Spacer()
                    UnavailableValue(reason: .notPresent, source: .wifi, compact: true)
                }
            }
            Text(tr("Passwords and keys are never read. Security shows only the method in use."))
                .font(Typo.caption).foregroundStyle(theme.textTertiary)
        }
    }

    private func statusLine(_ text: String) -> some View {
        HStack {
            Text(text).font(Typo.callout).foregroundStyle(theme.textSecondary)
            Spacer()
            ProvenanceBadge(source: .wifi, timestamp: details.wifiTimestamp)
        }
    }

    @ViewBuilder
    private func connected(_ wifi: WiFiDetails) -> some View {
        networkName(wifi)
        HStack(alignment: .top, spacing: Spacing.xxl) {
            if let rssi = wifi.rssi {
                VStack(alignment: .leading, spacing: 4) {
                    label(tr("Signal (RSSI)"), source: .wifi)
                    ValueText(value: fmt.integer(rssi), unit: "dBm", font: Typo.metric)
                    FillBar(fraction: WiFiNames.quality(rssi: rssi), color: theme.networkDown, height: 6)
                        .frame(width: 120)
                }
            }
            if let noise = wifi.noise {
                VStack(alignment: .leading, spacing: 4) {
                    label(tr("Noise"), source: .wifi)
                    ValueText(value: fmt.integer(noise), unit: "dBm", font: Typo.metric)
                }
            }
            if let snr = wifi.snr {
                VStack(alignment: .leading, spacing: 4) {
                    label(tr("Signal-to-noise ratio"), source: .wifiSNR)
                    ValueText(value: fmt.integer(snr), unit: "dB", font: Typo.metric)
                }
            }
            if let rate = wifi.transmitRate {
                VStack(alignment: .leading, spacing: 4) {
                    label(tr("Data rate"), source: .wifi)
                    ValueText(value: fmt.number(rate, fractionDigits: 0), unit: "Mbit/s", font: Typo.metric)
                }
            }
            Spacer(minLength: 0)
        }
        VStack(spacing: 5) {
            if let channel = wifi.channel {
                InfoRow(label: tr("Channel"),
                        value: [fmt.integer(channel), wifi.band, wifi.channelWidthMHz.map { "\($0) MHz" }].compactMap { $0 }.joined(separator: " · "),
                        source: .wifi, timestamp: details.wifiTimestamp)
            }
            if let phy = wifi.phyMode {
                InfoRow(label: tr("Standard"), value: phy, source: .wifi)
            }
            if let security = wifi.security {
                InfoRow(label: tr("Security"), value: security == "none" ? tr("None (open network)") : security, source: .wifi)
            }
            if let power = wifi.transmitPower {
                InfoRow(label: tr("Transmit power"), value: "\(fmt.integer(power)) mW", source: .wifi)
            }
            if let country = wifi.countryCode {
                InfoRow(label: tr("Country code"), value: country, source: .wifi)
            }
        }
    }

    @ViewBuilder
    private func networkName(_ wifi: WiFiDetails) -> some View {
        if let ssid = wifi.ssid {
            InfoRow(label: tr("Network name"), value: ssid, source: .wifi, timestamp: details.wifiTimestamp)
        } else if location.isAuthorized {
            HStack {
                Text(tr("Network name")).font(Typo.callout).foregroundStyle(theme.textSecondary)
                Spacer()
                UnavailableValue(reason: .notProvidedByMacOS, source: .wifi, compact: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Spacing.m) {
                    Text(tr("Network name")).font(Typo.callout).foregroundStyle(theme.textSecondary)
                    Spacer()
                    Text(tr("Needs location access")).font(Typo.callout.weight(.medium)).foregroundStyle(theme.textSecondary)
                    if location.isDenied {
                        Button(tr("Open Privacy Settings…")) { location.openPrivacySettings() }
                            .buttonStyle(CapsuleButtonStyle())
                    } else {
                        Button(tr("Allow Location Access…")) {
                            if !isSnapshot { location.request() }
                        }
                        .buttonStyle(CapsuleButtonStyle())
                    }
                }
                Text(tr("macOS only reveals the Wi‑Fi name to apps with location access. AETHER never asks for your location itself."))
                    .font(Typo.caption).foregroundStyle(theme.textTertiary)
            }
        }
    }

    private func label(_ text: String, source: DataSource) -> some View {
        HStack(spacing: 4) {
            Text(text).font(Typo.captionMedium).foregroundStyle(theme.textSecondary)
            ProvenanceBadge(source: source, timestamp: details.wifiTimestamp)
        }
    }
}

// MARK: - Verbindungen

private struct ConnectionsPanel: View {
    @ObservedObject var details: NetworkDetailsStore
    @Environment(\.aether) private var theme
    @State private var filter: ConnectionFilter = .established
    @State private var query = ""
    private let limit = 300

    var body: some View {
        Panel {
            HStack(spacing: Spacing.m) {
                PanelTitle(title: tr("Connections"), symbol: "arrow.left.arrow.right")
                Picker("", selection: $filter) {
                    ForEach(ConnectionFilter.allCases, id: \.self) { item in
                        Text(filterName(item)).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 270)
                TextField(tr("Search"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            if let reading = details.connections {
                if let result = reading.value {
                    content(result, reading: reading)
                } else {
                    HStack {
                        Text(tr("Connection list")).font(Typo.callout).foregroundStyle(theme.textSecondary)
                        Spacer()
                        UnavailableValue(reason: reading.reason ?? .queryFailed, source: reading.source, compact: true)
                    }
                }
            } else {
                Text(tr("Measuring…")).font(Typo.callout).foregroundStyle(theme.textSecondary)
            }
            Text(tr("The process is the socket’s last owner as recorded by the kernel. Data volumes per process are only available through private interfaces and aren’t shown."))
                .font(Typo.caption)
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func content(_ result: NetstatParseResult, reading: Reading<NetstatParseResult>) -> some View {
        let all = result.connections
        let established = all.filter { $0.state == .established }.count
        let listening = all.filter(\.isListening).count
        let list = ConnectionSearch.sorted(all.filter { filter.matches($0) && ConnectionSearch.matches($0, query: query) })
        HStack(spacing: 6) {
            Text(tr("%ld sockets · %ld established · %ld listening", all.count, established, listening))
                .font(Typo.caption).foregroundStyle(theme.textSecondary)
            ProvenanceBadge(source: reading.source, timestamp: reading.timestamp)
            Spacer()
        }
        if list.isEmpty {
            Text(tr("No matching connections")).font(Typo.callout).foregroundStyle(theme.textSecondary)
        } else {
            ConnectionHeader()
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(list.prefix(limit).enumerated()), id: \.element.id) { index, connection in
                    ConnectionRow(connection: connection, shaded: index % 2 == 1)
                }
            }
            if list.count > limit {
                Text(tr("Showing the first %ld of %ld – use the search to narrow the list.", limit, list.count))
                    .font(Typo.caption).foregroundStyle(theme.textTertiary)
            }
        }
        if !result.hasProcessColumn {
            Text(tr("netstat on this macOS version doesn’t name the process – the process column stays empty."))
                .font(Typo.caption).foregroundStyle(theme.textTertiary)
        }
    }

    private func filterName(_ filter: ConnectionFilter) -> String {
        switch filter {
        case .all: return tr("All")
        case .established: return tr("Established")
        case .listening: return tr("Listening")
        }
    }
}

private enum ConnectionColumns {
    static let process: CGFloat = 190
    static let proto: CGFloat = 52
    static let state: CGFloat = 110
}

private struct ConnectionHeader: View {
    @Environment(\.aether) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Text(tr("Process")).frame(width: ConnectionColumns.process, alignment: .leading)
            Text(tr("Protocol")).frame(width: ConnectionColumns.proto, alignment: .leading)
            Text(tr("Local")).frame(maxWidth: .infinity, alignment: .leading)
            Text(tr("Remote")).frame(maxWidth: .infinity, alignment: .leading)
            Text(tr("State")).frame(width: ConnectionColumns.state, alignment: .leading)
        }
        .font(Typo.sectionLabel)
        .foregroundStyle(theme.textTertiary)
        .padding(.horizontal, 8)
    }
}

private struct ConnectionRow: View {
    let connection: NetConnection
    let shaded: Bool
    @Environment(\.aether) private var theme

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Text(connection.processName ?? "–").lineLimit(1).truncationMode(.tail)
                if let pid = connection.pid {
                    Text(String(pid)).foregroundStyle(theme.textTertiary)
                }
            }
            .font(Typo.caption)
            .frame(width: ConnectionColumns.process, alignment: .leading)
            Text(connection.proto).font(Typo.mono).foregroundStyle(theme.textSecondary)
                .frame(width: ConnectionColumns.proto, alignment: .leading)
            Text(connection.local.display).font(Typo.mono).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(connection.remote.isWildcard ? "–" : connection.remote.display).font(Typo.mono).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(stateName)
                .font(Typo.caption)
                .foregroundStyle(connection.state == .established ? theme.statusNormal : theme.textSecondary)
                .frame(width: ConnectionColumns.state, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(shaded ? theme.fieldFill.opacity(0.6) : Color.clear))
        .textSelection(.enabled)
    }

    private var stateName: String {
        switch connection.state {
        case .established: return tr("Established")
        case .listen: return tr("Listening")
        case .timeWait: return "TIME_WAIT"
        case .closeWait: return "CLOSE_WAIT"
        case .some(let other): return other.rawValue
        case .none: return connection.isTCP ? "–" : tr("Open (UDP)")
        }
    }
}
