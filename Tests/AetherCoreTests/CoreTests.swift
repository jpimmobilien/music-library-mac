import XCTest
@testable import AetherCore

final class CPUMathTests: XCTestCase {
    func testUsageFromTickDelta() throws {
        let a = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let b = CPUTicks(user: 160, system: 70, idle: 870, nice: 20)
        let u = try XCTUnwrap(CPUMath.usage(from: a, to: b))
        XCTAssertEqual(u.user, 80.0 / 120.0, accuracy: 1e-9)
        XCTAssertEqual(u.system, 20.0 / 120.0, accuracy: 1e-9)
        XCTAssertEqual(u.idle, 20.0 / 120.0, accuracy: 1e-9)
        XCTAssertEqual(u.busy, 100.0 / 120.0, accuracy: 1e-9)
    }

    func testCounterWrapAroundIsHandled() throws {
        let a = CPUTicks(user: UInt32.max - 9, system: 0, idle: UInt32.max - 9, nice: 0)
        let b = CPUTicks(user: 10, system: 0, idle: 10, nice: 0) // je 20 Ticks nach Überlauf
        let u = try XCTUnwrap(CPUMath.usage(from: a, to: b))
        XCTAssertEqual(u.user, 0.5, accuracy: 1e-9)
        XCTAssertEqual(u.idle, 0.5, accuracy: 1e-9)
    }

    func testNoElapsedTicksGivesNilNotZero() {
        let a = CPUTicks(user: 5, system: 5, idle: 5, nice: 0)
        XCTAssertNil(CPUMath.usage(from: a, to: a))
        XCTAssertNil(CPUMath.total(from: [a], to: [a]))
    }

    func testTotalWeightsByTicksNotByCoreAverage() throws {
        let old = [CPUTicks(user: 0, system: 0, idle: 0, nice: 0), CPUTicks(user: 0, system: 0, idle: 0, nice: 0)]
        let new = [CPUTicks(user: 100, system: 0, idle: 0, nice: 0), CPUTicks(user: 0, system: 0, idle: 300, nice: 0)]
        let t = try XCTUnwrap(CPUMath.total(from: old, to: new))
        XCTAssertEqual(t.busy, 0.25, accuracy: 1e-9)
        XCTAssertNil(CPUMath.total(from: old, to: Array(new.prefix(1))), "unterschiedliche Kernzahl")
    }

    func testClusterNames() {
        XCTAssertEqual(CoreCluster.kind(forSystemName: "Performance"), .performance)
        XCTAssertEqual(CoreCluster.kind(forSystemName: "Efficiency"), .efficiency)
        XCTAssertEqual(CoreCluster.kind(forSystemName: "Something"), .uniform)
    }
}

final class MemoryMathTests: XCTestCase {
    func testBreakdownLikeActivityMonitor() {
        let page: UInt64 = 16_384
        let counts = VMPageCounts(free: 1_000, wired: 100_000, compressor: 50_000, purgeable: 10_000, fileBacked: 200_000,
                                  anonymous: 400_000)
        let b = MemoryMath.breakdown(counts, pageSize: page, physical: 16 * 1_073_741_824)
        XCTAssertEqual(b.app, 390_000 * page)
        XCTAssertEqual(b.wired, 100_000 * page)
        XCTAssertEqual(b.compressed, 50_000 * page)
        XCTAssertEqual(b.cached, 210_000 * page)
        XCTAssertEqual(b.used, (390_000 + 100_000 + 50_000) * page)
        XCTAssertEqual(b.free, 16 * 1_073_741_824 - (540_000 + 210_000) * page)
    }

    func testFreeNeverNegativeAndAppNeverUnderflows() {
        let counts = VMPageCounts(wired: 10, purgeable: 50, fileBacked: 0, anonymous: 20)
        let b = MemoryMath.breakdown(counts, pageSize: 4096, physical: 4096)
        XCTAssertEqual(b.app, 0)
        XCTAssertEqual(b.free, 0)
        XCTAssertLessThanOrEqual(b.usedFraction, 1)
    }

    func testPressureLevels() {
        XCTAssertEqual(PressureLevel(sysctlValue: 1), .normal)
        XCTAssertEqual(PressureLevel(sysctlValue: 2), .warning)
        XCTAssertEqual(PressureLevel(sysctlValue: 4), .critical)
        XCTAssertNil(PressureLevel(sysctlValue: 0))
        XCTAssertNil(PressureLevel(sysctlValue: 3))
        XCTAssertTrue(PressureLevel.warning < .critical)
    }
}

final class RateTests: XCTestCase {
    func testRateNeedsTwoSamplesAndIgnoresResets() {
        var r = CounterRate()
        XCTAssertNil(r.update(value: 1_000, time: 10))
        XCTAssertEqual(r.update(value: 3_000, time: 12) ?? -1, 1_000, accuracy: 1e-9)
        XCTAssertNil(r.update(value: 500, time: 13), "Zähler zurückgesetzt → kein Sprung")
        XCTAssertEqual(r.update(value: 1_500, time: 14) ?? -1, 1_000, accuracy: 1e-9)
        XCTAssertNil(r.update(value: 1_600, time: 14), "keine verstrichene Zeit")
    }

    func testAccumulatorAcrossInterfaces() {
        var acc = CounterAccumulator()
        XCTAssertEqual(acc.update(["en0": 100, "en1": 50]), 0)
        XCTAssertEqual(acc.update(["en0": 160, "en1": 70]), 80)
        XCTAssertEqual(acc.update(["en0": 10, "en1": 90, "en5": 1_000]), 20, "Rücksetzung von en0 und neue Schnittstelle zählen nicht")
        XCTAssertEqual(acc.total, 100)
    }

    func testRingBufferKeepsNewestInOrder() {
        var ring = RingBuffer<Int>(capacity: 3)
        XCTAssertNil(ring.last)
        for i in 1...5 { ring.append(i) }
        XCTAssertEqual(ring.elements, [3, 4, 5])
        XCTAssertEqual(ring.last, 5)
        XCTAssertEqual(ring.count, 3)
        ring.removeAll()
        XCTAssertTrue(ring.isEmpty)
    }
}

final class PulseTests: XCTestCase {
    func testCalmWhenEverythingUnavailable() {
        var e = PulseEvaluator(sampleInterval: 2)
        let p = e.evaluate(PulseInput())
        XCTAssertEqual(p, .calm)
        XCTAssertNil(p.level)
    }

    func testHighCPUNeedsTenSeconds() {
        var e = PulseEvaluator(sampleInterval: 2)
        let busy = PulseInput(cpuBusy: 0.95)
        for _ in 0..<4 { XCTAssertTrue(e.evaluate(busy).findings.isEmpty) }
        XCTAssertEqual(e.evaluate(busy).findings.map(\.kind), [.highCPU])
        // Ein ruhiger Wert setzt die Haltezeit zurück
        XCTAssertTrue(e.evaluate(PulseInput(cpuBusy: 0.10)).findings.isEmpty)
        XCTAssertTrue(e.evaluate(busy).findings.isEmpty)
    }

    func testMinimumStreakEvenWithLongInterval() {
        var e = PulseEvaluator(sampleInterval: 10)
        let busy = PulseInput(cpuBusy: 0.99)
        XCTAssertTrue(e.evaluate(busy).findings.isEmpty)
        XCTAssertEqual(e.evaluate(busy).findings.count, 1)
    }

    func testMemoryPressureAndSwap() {
        var e = PulseEvaluator(sampleInterval: 1)
        let input = PulseInput(pressure: .critical, swapUsed: 5_000_000_000, physicalMemory: 16_000_000_000)
        XCTAssertTrue(e.evaluate(input).findings.isEmpty)
        let p = e.evaluate(input)
        XCTAssertEqual(Set(p.findings.map(\.kind)), [.memoryPressure, .highSwap])
        XCTAssertEqual(p.level, .critical)
        XCTAssertEqual(p.findings.first?.kind, .memoryPressure, "schwerster zuerst")
    }

    func testSwapAloneIsNotAWarning() {
        var e = PulseEvaluator(sampleInterval: 1)
        let input = PulseInput(pressure: .normal, swapUsed: 12_000_000_000, physicalMemory: 16_000_000_000)
        _ = e.evaluate(input)
        XCTAssertTrue(e.evaluate(input).findings.isEmpty)
    }

    func testThermalAndDiskAreImmediate() {
        var e = PulseEvaluator(sampleInterval: 2)
        let p = e.evaluate(PulseInput(thermal: .serious, startupAvailable: 8_000_000_000, startupCapacity: 500_000_000_000))
        XCTAssertEqual(Set(p.findings.map(\.kind)), [.thermal, .lowDiskSpace])
        XCTAssertEqual(p.level, .elevated)
        XCTAssertTrue(e.evaluate(PulseInput(thermal: .fair)).findings.isEmpty)
        XCTAssertEqual(e.evaluate(PulseInput(startupAvailable: 500_000_000, startupCapacity: 500_000_000_000)).level, .critical)
    }

    func testLowDiskByFraction() {
        var e = PulseEvaluator(sampleInterval: 2)
        // 40 GB frei von 512 GB → 7,8 % < 10 %
        XCTAssertEqual(e.evaluate(PulseInput(startupAvailable: 40_000_000_000, startupCapacity: 512_000_000_000)).level, .elevated)
        // 200 GB frei → ruhig
        XCTAssertNil(e.evaluate(PulseInput(startupAvailable: 200_000_000_000, startupCapacity: 512_000_000_000)).level)
    }

    func testNetworkIsInfoOnly() {
        var e = PulseEvaluator(sampleInterval: 5)
        let input = PulseInput(networkBytesPerSecond: 80_000_000)
        _ = e.evaluate(input)
        let p = e.evaluate(input)
        XCTAssertEqual(p.findings.map(\.kind), [.highNetwork])
        XCTAssertNil(p.level, "Netzaktivität ist keine Warnung")
    }

    func testBatteryServiceFromSystemOnly() {
        var e = PulseEvaluator(sampleInterval: 2)
        XCTAssertEqual(e.evaluate(PulseInput(batteryServiceRecommended: true)).findings.map(\.kind), [.batteryService])
        XCTAssertTrue(e.evaluate(PulseInput(batteryServiceRecommended: false)).findings.isEmpty)
    }
}

final class FormattingTests: XCTestCase {
    let de = ValueFormatter(locale: Locale(identifier: "de_DE"))
    let en = ValueFormatter(locale: Locale(identifier: "en_US"))
    let s = ValueFormatter.unitSpace

    func testSignificantDigits() {
        XCTAssertEqual(de.significant(2.4), "2,4")
        XCTAssertEqual(de.significant(12.34), "12,3")
        XCTAssertEqual(de.significant(412.7), "413")
        XCTAssertEqual(en.significant(3.27), "3.27")
        XCTAssertEqual(en.significant(16.0), "16")
        XCTAssertEqual(en.significant(0), "0")
    }

    func testBytes() {
        XCTAssertEqual(de.bytes(UInt64(994_660_000_000)), "995\(s)GB")
        XCTAssertEqual(de.bytes(UInt64(1_500_000)), "1,5\(s)MB")
        XCTAssertEqual(en.bytes(UInt64(512)), "512\(s)B")
        XCTAssertEqual(en.bytes(UInt64(17_179_869_184), style: .memory), "16\(s)GB")
        XCTAssertEqual(en.bytes(UInt64(999_700)), "1\(s)MB", "Rundungsgrenze springt zur nächsten Einheit")
        XCTAssertEqual(en.bytes(UInt64(2_000_000_000_000)), "2\(s)TB")
    }

    func testRatesAndPercent() {
        XCTAssertEqual(de.rate(2_400_000), "2,4\(s)MB/s")
        XCTAssertEqual(en.rate(-5), "0\(s)B/s")
        XCTAssertEqual(de.percent(0.12), "12\(s)%")
        XCTAssertEqual(en.percent(0.12), "12%")
        XCTAssertEqual(en.percent(0.915, fractionDigits: 1), "91.5%")
    }

    func testIntegerGroupingAndTemperature() {
        XCTAssertEqual(de.integer(1850), "1.850")
        XCTAssertEqual(en.integer(1850), "1,850")
        XCTAssertEqual(en.integer(-1234567), "-1,234,567")
        XCTAssertEqual(de.celsius(46.27), "46,3\(s)°C")
        XCTAssertEqual(de.number(-0.0001, fractionDigits: 1), "0,0")
    }

    func testDuration() {
        XCTAssertEqual(de.duration(seconds: 2 * 86_400 + 4 * 3_600 + 30), "2\(s)T 4\(s)h")
        XCTAssertEqual(en.duration(seconds: 3 * 3_600 + 12 * 60), "3\(s)h 12\(s)min")
        XCTAssertEqual(en.duration(seconds: 45 * 60), "45\(s)min")
        XCTAssertEqual(en.duration(seconds: 9), "9\(s)s")
    }
}

final class PaletteTests: XCTestCase {
    func testAllThemesHaveReadableText() {
        for spec in ThemeCatalog.all {
            for palette in spec.palettes {
                let base = palette.contrastBase
                XCTAssertGreaterThanOrEqual(RGBA.contrast(palette.textPrimary, base), 7, "\(spec.id) primär")
                XCTAssertGreaterThanOrEqual(RGBA.contrast(palette.textSecondary, base), 4.5, "\(spec.id) sekundär")
                XCTAssertGreaterThanOrEqual(RGBA.contrast(palette.textTertiary, base), 3, "\(spec.id) tertiär")
                for (name, color) in [("normal", palette.statusNormal), ("erhöht", palette.statusElevated),
                                      ("kritisch", palette.statusCritical), ("n. v.", palette.statusUnavailable)] {
                    XCTAssertGreaterThanOrEqual(RGBA.contrast(color, base), 3, "\(spec.id) Status \(name)")
                }
            }
        }
    }

    func testAccentsCarryReadableLabels() {
        for accent in AccentChoice.allCases {
            guard let colors = accent.fixed else { continue }
            for color in [colors.light, colors.dark] {
                XCTAssertGreaterThanOrEqual(RGBA.contrast(color, color.preferredForeground), 4.5, "\(accent) Beschriftung")
            }
            XCTAssertGreaterThanOrEqual(RGBA.contrast(colors.light, ThemeCatalog.glassLight.contrastBase), 3, "\(accent) hell")
            XCTAssertGreaterThanOrEqual(RGBA.contrast(colors.dark, ThemeCatalog.glassDark.contrastBase), 3, "\(accent) dunkel")
        }
    }

    func testThemeAppearances() {
        XCTAssertEqual(ThemeCatalog.all.count, 6)
        XCTAssertTrue(ThemeCatalog.spec(.liquidGlassDark).palette(dark: false).isDark, "festes dunkles Theme bleibt dunkel")
        XCTAssertFalse(ThemeCatalog.spec(.minimalLight).palette(dark: true).isDark)
        XCTAssertNotNil(ThemeCatalog.spec(.system).light)
        XCTAssertNotNil(ThemeCatalog.spec(.system).dark)
        XCTAssertFalse(ThemeCatalog.spec(.minimalDark).usesGlass)
        XCTAssertTrue(ThemeCatalog.minimalDark.ambient.isEmpty)
    }

    func testLuminanceExtremes() {
        XCTAssertEqual(RGBA.contrast(RGBA(0x000000), RGBA(0xFFFFFF)), 21, accuracy: 0.01)
        XCTAssertEqual(RGBA(0xFF0000, 0.5).composited(over: RGBA(0x0000FF)).red, 0.5, accuracy: 1e-9)
    }
}

final class HardwareTests: XCTestCase {
    func testAppleSiliconBrand() {
        let p = ProcessorName.parse("Apple M3 Pro")
        XCTAssertEqual(p.vendor, .apple)
        XCTAssertEqual(p.appleFamily, "M3")
        XCTAssertEqual(p.appleTier, "Pro")
        XCTAssertFalse(p.isVirtual)
        let vm = ProcessorName.parse("Apple M1 (Virtual)")
        XCTAssertTrue(vm.isVirtual)
        XCTAssertEqual(vm.displayName, "Apple M1")
        XCTAssertNil(vm.appleTier)
    }

    func testIntelBrand() {
        let p = ProcessorName.parse("Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz")
        XCTAssertEqual(p.vendor, .intel)
        XCTAssertEqual(p.displayName, "Intel Core i7-9750H")
        XCTAssertEqual(p.nominalClock, "2.60GHz")
    }

    func testDeviceKinds() {
        XCTAssertEqual(DeviceKind.from(machineName: "MacBook Pro", modelIdentifier: "Mac14,9"), .macBookPro)
        XCTAssertEqual(DeviceKind.from(machineName: nil, modelIdentifier: "Macmini9,1"), .macMini)
        XCTAssertEqual(DeviceKind.from(machineName: nil, modelIdentifier: "VirtualMac2,1"), .virtualMachine)
        XCTAssertEqual(DeviceKind.from(machineName: "Apple Virtual Machine 1", modelIdentifier: nil), .virtualMachine)
        XCTAssertEqual(DeviceKind.from(machineName: nil, modelIdentifier: "Mac14,9"), .unknown)
        XCTAssertTrue(DeviceKind.macBookAir.isPortable)
        XCTAssertFalse(DeviceKind.macStudio.isPortable)
    }

    func testProfilerAppleSilicon() throws {
        let json = """
        {"SPHardwareDataType":[{"_name":"hardware_overview","chip_type":"Apple M2 Pro","machine_model":"Mac14,9",
        "machine_name":"MacBook Pro","model_number":"MPHE3D/A","number_processors":"proc 10:6:4",
        "physical_memory":"16 GB","serial_number":"XXXXXXXXXX"}]}
        """
        let h = try XCTUnwrap(ProfilerParser.hardware(fromJSON: Data(json.utf8)))
        XCTAssertEqual(h.machineName, "MacBook Pro")
        XCTAssertEqual(h.chip, "Apple M2 Pro")
        XCTAssertEqual(h.totalCores, 10)
        XCTAssertEqual(h.performanceCores, 6)
        XCTAssertEqual(h.efficiencyCores, 4)
        XCTAssertEqual(h.memory, "16 GB")
    }

    func testProfilerIntelAndGarbage() throws {
        let json = """
        {"SPHardwareDataType":[{"cpu_type":"6-Core Intel Core i7","current_processor_speed":"2,6 GHz",
        "machine_model":"MacBookPro16,1","machine_name":"MacBook Pro","number_processors":6}]}
        """
        let h = try XCTUnwrap(ProfilerParser.hardware(fromJSON: Data(json.utf8)))
        XCTAssertEqual(h.chip, "6-Core Intel Core i7")
        XCTAssertEqual(h.processorSpeed, "2,6 GHz")
        XCTAssertEqual(h.totalCores, 6)
        XCTAssertNil(h.performanceCores)
        XCTAssertNil(ProfilerParser.hardware(fromJSON: Data("nicht json".utf8)))
        XCTAssertNil(ProfilerParser.hardware(fromJSON: Data("{}".utf8)))
    }
}

final class BatteryAndVolumeTests: XCTestCase {
    func testHealthIsComputedOnlyFromPlausibleValues() throws {
        XCTAssertEqual(try XCTUnwrap(BatteryMath.health(fullCharge: 4_500, design: 5_000)), 0.9, accuracy: 1e-9)
        XCTAssertNil(BatteryMath.health(fullCharge: 4_500, design: 0))
        XCTAssertNil(BatteryMath.health(fullCharge: 100, design: 1), "Verhältnis unplausibel")
        XCTAssertNil(BatteryMath.health(fullCharge: 0, design: 5_000))
    }

    func testBatteryTemperatureAndAmperage() {
        XCTAssertEqual(BatteryMath.celsius(fromCentidegrees: 3050), 30.5)
        XCTAssertNil(BatteryMath.celsius(fromCentidegrees: 0xFFFF))
        XCTAssertEqual(BatteryMath.signedMilliamps(65_036), -500)
        XCTAssertEqual(BatteryMath.signedMilliamps(4_294_966_296), -1_000)
        XCTAssertEqual(BatteryMath.signedMilliamps(1_200), 1_200)
        XCTAssertEqual(BatteryMath.signedMilliamps(-700), -700)
    }

    func testPowerFromVoltageAndCurrent() throws {
        let t = Date()
        let b = BatterySnapshot(isPresent: true, percent: Reading(80, source: .powerSources), isCharging: false, isFullyCharged: false,
                                powerSource: .battery, minutesToEmpty: Reading(unavailable: .awaitingSecondSample, source: .batteryTimeRemaining),
                                minutesToFull: Reading(unavailable: .notPresent, source: .batteryTimeRemaining),
                                cycleCount: Reading(312, source: .smartBattery), designCapacity: Reading(6_000, source: .smartBattery),
                                fullChargeCapacity: Reading(5_400, source: .smartBattery), computedHealth: Reading(0.9, source: .batteryHealth),
                                voltage: Reading(12_000, source: .smartBattery, at: t), amperage: Reading(-1_500, source: .smartBattery, at: t),
                                temperature: Reading(31, source: .smartBattery), adapterWatts: Reading(unavailable: .notPresent, source: .powerSources),
                                systemCondition: "Good")
        XCTAssertEqual(try XCTUnwrap(b.power.value), -18, accuracy: 1e-9)
        XCTAssertEqual(b.power.source.provenance, .computed)
        XCTAssertEqual(b.serviceRecommended, false)
    }

    func testVolumeUsesImportantUsageAndPurgeable() {
        let v = VolumeInfo(name: "Macintosh HD", path: "/", capacity: 1_000, available: 300, availableForImportantUsage: 450,
                           format: "APFS", isInternal: true, isRemovable: false, isRoot: true, isReadOnly: false,
                           isEncrypted: true, isNetwork: false)
        XCTAssertEqual(v.effectiveAvailable, 450)
        XCTAssertEqual(v.used, 550)
        XCTAssertEqual(v.purgeable, 150)
        XCTAssertEqual(v.usedFraction, 0.55, accuracy: 1e-9)
        let s = StorageSnapshot(volumes: [v], readRate: Reading(unavailable: .awaitingSecondSample, source: .blockStorage),
                                writeRate: Reading(unavailable: .awaitingSecondSample, source: .blockStorage))
        XCTAssertEqual(s.startup?.name, "Macintosh HD")
    }
}

final class PreferencesTests: XCTestCase {
    func testLayoutNormalizesAndRestores() {
        var layout = DashboardLayout.restore(order: ["gpu", "cpu", "gpu", "unbekannt"], hidden: ["battery", "nix"])
        XCTAssertEqual(layout.order.prefix(2), [.gpu, .cpu])
        XCTAssertEqual(layout.order.count, DashboardCard.allCases.count)
        XCTAssertFalse(layout.visible.contains(.battery))
        layout.move(.cpu, before: .gpu)
        XCTAssertEqual(layout.order.prefix(2), [.cpu, .gpu])
        layout.setVisible(.battery, true)
        XCTAssertTrue(layout.visible.contains(.battery))
    }

    func testLowImpactInterval() {
        XCTAssertEqual(RefreshInterval.oneSecond.effective(lowImpact: true), .fiveSeconds)
        XCTAssertEqual(RefreshInterval.tenSeconds.effective(lowImpact: true), .tenSeconds)
        XCTAssertEqual(RefreshInterval.twoSeconds.effective(lowImpact: false), .twoSeconds)
    }

    func testReadingMap() {
        let r = Reading(2, source: .loadAverage).map { $0 * 10 }
        XCTAssertEqual(r.value, 20)
        let u = Reading<Int>(unavailable: .notPresent, source: .loadAverage).map { $0 * 10 }
        XCTAssertNil(u.value)
        XCTAssertEqual(u.reason, .notPresent)
        XCTAssertEqual(DataSource.all.count, Set(DataSource.all.map(\.id)).count, "eindeutige Quellen-IDs")
    }
}

final class DisplaysParserTests: XCTestCase {
    func testAppleSiliconGPU() throws {
        let json = """
        {"SPDisplaysDataType":[{"_name":"Apple M2 Pro","sppci_bus":"spdisplays_builtin","sppci_cores":"19",
        "sppci_model":"Apple M2 Pro","spdisplays_vendor":"sppci_vendor_Apple","spdisplays_mtlgpufamilysupport":"spdisplays_metal3",
        "spdisplays_ndrvs":[{"_name":"Color LCD"},{"_name":"Studio Display"}]}]}
        """
        let gpus = try XCTUnwrap(DisplaysParser.gpus(fromJSON: Data(json.utf8), appleSilicon: true))
        XCTAssertEqual(gpus.count, 1)
        let g = gpus[0]
        XCTAssertEqual(g.name, "Apple M2 Pro")
        XCTAssertEqual(g.vendor, "Apple")
        XCTAssertEqual(g.kind, .integrated)
        XCTAssertEqual(g.coreCount, 19)
        XCTAssertEqual(g.metalSupport, "Metal 3")
        XCTAssertTrue(g.hasUnifiedMemory)
        XCTAssertNil(g.vram, "Unified Memory hat keinen eigenen Grafikspeicher")
        XCTAssertEqual(g.displayCount, 2)
    }

    func testIntelMacWithTwoGPUs() throws {
        let json = """
        {"SPDisplaysDataType":[
        {"_name":"Intel UHD Graphics 630","sppci_bus":"spdisplays_builtin","sppci_model":"Intel UHD Graphics 630",
         "spdisplays_vendor":"Intel","spdisplays_vram_shared":"1536 MB","spdisplays_mtlgpufamilysupport":"spdisplays_metal2"},
        {"_name":"AMD Radeon Pro 5500M","sppci_bus":"spdisplays_pcie_device","sppci_model":"AMD Radeon Pro 5500M",
         "spdisplays_vendor":"sppci_vendor_amd","spdisplays_vram":"8 GB","spdisplays_mtlgpufamilysupport":"spdisplays_metal3"}]}
        """
        let gpus = try XCTUnwrap(DisplaysParser.gpus(fromJSON: Data(json.utf8), appleSilicon: false))
        XCTAssertEqual(gpus.map(\.kind), [.integrated, .discrete])
        XCTAssertEqual(gpus.map(\.vendor), ["Intel", "AMD"])
        XCTAssertEqual(gpus.map(\.vram), ["1536 MB", "8 GB"])
        XCTAssertEqual(gpus.map(\.metalSupport), ["Metal 2", "Metal 3"])
        XCTAssertFalse(gpus.contains(where: \.hasUnifiedMemory))
    }

    func testUnknownAndEmpty() throws {
        XCTAssertNil(DisplaysParser.gpus(fromJSON: Data("{}".utf8), appleSilicon: true))
        let empty = try XCTUnwrap(DisplaysParser.gpus(fromJSON: Data(#"{"SPDisplaysDataType":[]}"#.utf8), appleSilicon: false))
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(DisplaysParser.metalName("spdisplays_metal4"), "Metal 4")
        XCTAssertEqual(DisplaysParser.metalName("supported"), "supported")
        XCTAssertEqual(DisplaysParser.vendorName("sppci_vendor_nvidia"), "NVIDIA")
        XCTAssertEqual(DeviceKind.from(machineName: nil, modelIdentifier: "VMware7,1"), .virtualMachine)
    }
}
