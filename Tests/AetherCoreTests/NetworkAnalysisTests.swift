import XCTest
@testable import AetherCore

final class NetstatParserTests: XCTestCase {
    /// Format bis macOS 13: Spalte „pid“.
    private let ventura = """
    Active Internet connections (including servers)
    Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)     rhiwat shiwat    pid   epid  state    options
    tcp4       0      0  192.168.178.20.50612   17.57.144.84.5223      ESTABLISHED 131072 131768    401      0 0x0102 0x00000020
    tcp6       0      0  *.5000                 *.*                    LISTEN      131072 131072    512      0 0x0100 0x00000006
    tcp4       0      0  127.0.0.1.631          *.*                    LISTEN      131072 131072    210      0 0x0080 0x00000006
    """

    private let venturaUDP = """
    Active Internet connections (including servers)
    Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)     rhiwat shiwat    pid   epid  state    options
    udp4       0      0  *.5353                 *.*                                786896   9216    312      0 0x0000 0x00000000
    udp6       0      0  fe80::1%lo0.123        *.*                                786896   9216    100      0 0x0000 0x00000000
    """

    /// Neueres Format: Spalte „process:pid“, Namen können Leerzeichen enthalten.
    private let sequoia = """
    Active Internet connections (including servers)
    Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)          rxbytes      txbytes  rhiwat  shiwat    process:pid    state      options              gencnt    flags   flags1 usscnt rtncnt fltrs
    tcp4       0      0  192.168.1.10.55123     140.82.112.25.443      ESTABLISHED         5123        2210  131072  131768  Google Chrome H:4567  00102 00000008 000000000003c7b1 00000080 00000900      1      0 000001
    udp4       0      0  *.5353                 *.*                                  0           0  786896    9216  mDNSResponder:312 00000 00000000 000000000000013a 00000000 00000800      1      0 000001
    """

    func testVenturaTCP() {
        let result = NetstatParser.parse(ventura)
        XCTAssertTrue(result.hasProcessColumn)
        XCTAssertEqual(result.connections.count, 3)
        let first = result.connections[0]
        XCTAssertEqual(first.proto, "tcp4")
        XCTAssertEqual(first.local, ConnectionEndpoint(host: "192.168.178.20", port: "50612"))
        XCTAssertEqual(first.remote.display, "17.57.144.84:5223")
        XCTAssertEqual(first.state, .established)
        XCTAssertEqual(first.pid, 401)
        XCTAssertNil(first.processName)
        XCTAssertTrue(result.connections[1].isListening)
        XCTAssertEqual(result.connections[1].pid, 512)
    }

    func testUDPWithoutStateColumnValue() {
        let result = NetstatParser.parse(venturaUDP)
        XCTAssertEqual(result.connections.count, 2)
        XCTAssertNil(result.connections[0].state)
        XCTAssertEqual(result.connections[0].pid, 312)
        XCTAssertTrue(result.connections[0].isListening)
        XCTAssertEqual(result.connections[1].local.host, "fe80::1%lo0")
        XCTAssertEqual(result.connections[1].local.display, "[fe80::1%lo0]:123")
        XCTAssertEqual(result.connections[1].pid, 100)
    }

    func testProcessColumnWithSpaces() {
        let result = NetstatParser.parse(sequoia)
        XCTAssertTrue(result.hasProcessColumn)
        XCTAssertEqual(result.connections.count, 2)
        XCTAssertEqual(result.connections[0].processName, "Google Chrome H")
        XCTAssertEqual(result.connections[0].pid, 4567)
        XCTAssertEqual(result.connections[0].state, .established)
        XCTAssertEqual(result.connections[1].processName, "mDNSResponder")
        XCTAssertEqual(result.connections[1].pid, 312)
        XCTAssertNil(result.connections[1].state)
    }

    func testWithoutProcessColumnAndGarbage() {
        let plain = """
        Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)
        tcp4       0      0  10.0.0.2.22            10.0.0.9.50000         ESTABLISHED
        """
        let result = NetstatParser.parse(plain)
        XCTAssertFalse(result.hasProcessColumn)
        XCTAssertEqual(result.connections.count, 1)
        XCTAssertNil(result.connections[0].pid)
        XCTAssertTrue(NetstatParser.parse("netstat: sysctl: Operation not permitted").connections.isEmpty)
        XCTAssertTrue(NetstatParser.parse("").connections.isEmpty)
    }

    func testStableUniqueIDs() {
        let doubled = ventura + "\ntcp4       0      0  127.0.0.1.631          *.*                    LISTEN      131072 131072    210      0 0x0080 0x00000006"
        let ids = NetstatParser.parse(doubled).connections.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(NetstatParser.parse(ventura).connections.map(\.id), Array(ids.prefix(3)))
    }

    func testEndpoints() {
        XCTAssertTrue(ConnectionEndpoint.parse("*.*").isWildcard)
        XCTAssertEqual(ConnectionEndpoint.parse("*.443").display, "*:443")
        XCTAssertEqual(ConnectionEndpoint.parse("10.0.0.1.22").display, "10.0.0.1:22")
        XCTAssertEqual(ConnectionEndpoint.parse("::1.631").display, "[::1]:631")
    }

    func testFilterSearchAndSorting() {
        let all = NetstatParser.parse(ventura).connections + NetstatParser.parse(sequoia).connections
        XCTAssertEqual(all.filter { ConnectionFilter.established.matches($0) }.count, 2)
        XCTAssertEqual(all.filter { ConnectionFilter.listening.matches($0) }.count, 3)
        XCTAssertEqual(all.filter { ConnectionSearch.matches($0, query: "chrome") }.count, 1)
        XCTAssertEqual(all.filter { ConnectionSearch.matches($0, query: "5223") }.count, 1)
        XCTAssertEqual(all.filter { ConnectionSearch.matches($0, query: "  ") }.count, all.count)
        XCTAssertEqual(ConnectionSearch.sorted(all).first?.state, .established)
    }
}

final class InterfaceAnalysisTests: XCTestCase {
    func testClassification() {
        XCTAssertEqual(InterfaceClassifier.kind(bsdName: "en0", systemType: "IEEE80211"), .wifi)
        XCTAssertEqual(InterfaceClassifier.kind(bsdName: "en1", systemType: "Ethernet"), .ethernet)
        XCTAssertEqual(InterfaceClassifier.kind(bsdName: "bridge0", systemType: "Bridge"), .bridge)
        XCTAssertEqual(InterfaceClassifier.kind(bsdName: "utun3", systemType: nil), .vpn)
        XCTAssertEqual(InterfaceClassifier.kind(bsdName: "awdl0", systemType: nil), .peerToPeer)
        XCTAssertEqual(InterfaceClassifier.kind(bsdName: "lo0", systemType: nil), .loopback)
        XCTAssertEqual(InterfaceClassifier.kind(bsdName: "en5", systemType: nil), .ethernet)
        XCTAssertEqual(InterfaceClassifier.kind(bsdName: "anpi0", systemType: nil), .other)
    }

    func testPrefixLength() {
        XCTAssertEqual(InterfaceAddress.prefixLength(mask: [255, 255, 255, 0]), 24)
        XCTAssertEqual(InterfaceAddress.prefixLength(mask: [255, 255, 240, 0]), 20)
        XCTAssertNil(InterfaceAddress.prefixLength(mask: [255, 0, 255, 0]))
        XCTAssertEqual(InterfaceAddress.prefixLength(mask: [UInt8](repeating: 255, count: 8) + [UInt8](repeating: 0, count: 8)), 64)
    }

    func testLinkLocalAndConnected() {
        XCTAssertTrue(InterfaceAddress(address: "fe80::1c2b:3", isIPv6: true, prefixLength: 64).isLinkLocal)
        XCTAssertFalse(InterfaceAddress(address: "2001:db8::1", isIPv6: true, prefixLength: 64).isLinkLocal)
        XCTAssertTrue(InterfaceAddress(address: "169.254.10.2", isIPv6: false, prefixLength: 16).isLinkLocal)
        XCTAssertFalse(InterfaceAddress(address: "192.168.1.4", isIPv6: false, prefixLength: 24).isLinkLocal)
        let onlyLinkLocal = NetworkInterfaceInfo(bsdName: "en0", displayName: "Wi‑Fi", kind: .wifi, isUp: true, isRunning: true,
                                                 addresses: [InterfaceAddress(address: "fe80::1", isIPv6: true, prefixLength: 64)],
                                                 isPrimary: false)
        XCTAssertFalse(onlyLinkLocal.isConnected)
        var connected = onlyLinkLocal
        connected.addresses.append(InterfaceAddress(address: "192.168.1.4", isIPv6: false, prefixLength: 24))
        XCTAssertTrue(connected.isConnected)
        XCTAssertEqual(connected.ipv4.count, 1)
    }

    func testWiFiNames() {
        XCTAssertEqual(WiFiNames.band(rawValue: 2), "5 GHz")
        XCTAssertNil(WiFiNames.band(rawValue: 0))
        XCTAssertEqual(WiFiNames.widthMHz(rawValue: 3), 80)
        XCTAssertTrue(WiFiNames.phyMode(rawValue: 6)?.contains("ax") ?? false)
        XCTAssertEqual(WiFiNames.security(rawValue: 4), "WPA2 Personal")
        XCTAssertNil(WiFiNames.security(rawValue: Int.max))
        XCTAssertEqual(WiFiNames.quality(rssi: -50), 1)
        XCTAssertEqual(WiFiNames.quality(rssi: -95), 0)
        XCTAssertFalse(WiFiNames.plausibleSignal(0))
        XCTAssertTrue(WiFiNames.plausibleSignal(-61))
    }
}

final class HistoryLogicTests: XCTestCase {
    private func at(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }

    func testAccumulatorAveragesAndKeepsMaximumLevels() {
        var accumulator = HistoryAccumulator()
        XCTAssertNil(accumulator.add(HistorySample(time: at(6_005), cpuBusy: 0.2, pressure: 1, download: 100)))
        XCTAssertNil(accumulator.add(HistorySample(time: at(6_030), cpuBusy: 0.4, pressure: 2, download: nil)))
        let finished = accumulator.add(HistorySample(time: at(6_065), cpuBusy: 0.9, pressure: 1))
        XCTAssertEqual(finished?.time, at(6_000))
        XCTAssertEqual(finished?.cpuBusy ?? 0, 0.3, accuracy: 1e-9)
        XCTAssertEqual(finished?.pressure, 2)
        XCTAssertEqual(finished?.download, 100)
        XCTAssertNil(finished?.upload)
        let last = accumulator.flush()
        XCTAssertEqual(last?.time, at(6_060))
        XCTAssertEqual(last?.cpuBusy, 0.9)
        XCTAssertNil(accumulator.flush())
    }

    func testEmptyMinuteIsNotStored() {
        var accumulator = HistoryAccumulator()
        XCTAssertNil(accumulator.add(HistorySample(time: at(120))))
        XCTAssertNil(accumulator.flush())
    }

    func testBucketingLeavesGaps() {
        let start = at(0)
        let end = at(3_600)
        let samples = [HistorySample(time: at(600), cpuBusy: 0.5), HistorySample(time: at(660), cpuBusy: 0.7),
                       HistorySample(time: at(3_000), thermalState: 2), HistorySample(time: at(3_060), thermalState: 0)]
        let cpu = HistoryBucketing.points(samples, metric: .cpu, start: start, end: end, buckets: 6)
        XCTAssertEqual(cpu.count, 6)
        XCTAssertEqual(cpu[1].value ?? 0, 0.6, accuracy: 1e-9)
        XCTAssertNil(cpu[0].value)
        XCTAssertNil(cpu[2].value)
        let thermal = HistoryBucketing.points(samples, metric: .thermalState, start: start, end: end, buckets: 6)
        XCTAssertEqual(thermal[5].value, 2) // Stufen: Maximum, nicht Mittel
        let summary = HistoryBucketing.summary(samples, metric: .cpu)
        XCTAssertEqual(summary?.minimum, 0.5)
        XCTAssertEqual(summary?.maximum, 0.7)
        XCTAssertEqual(summary?.count, 2)
        XCTAssertNil(HistoryBucketing.summary(samples, metric: .download))
    }

    func testBatteryPowerUsesMagnitude() {
        XCTAssertEqual(HistoryMetric.batteryPower.value(in: HistorySample(time: at(0), batteryPower: -12.5)), 12.5)
    }

    func testCSV() {
        let csv = HistoryCSV.make([HistorySample(time: at(6_000), cpuBusy: 0.25, pressure: 1, download: 1_234)])
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(lines[0], HistoryCSV.header.joined(separator: ","))
        XCTAssertEqual(lines[1], "1970-01-01T01:40:00Z,0.25,,1,,1234.0,,,,,")
        XCTAssertEqual(lines.count, 3) // abschließender Zeilenumbruch
    }
}
