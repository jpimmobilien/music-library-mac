import XCTest
@testable import AetherCore

final class SMCDecoderTests: XCTestCase {
    func testSP78() {
        // 0x2A80 = 42.5 °C (7 Ganzzahl-, 8 Nachkommabits)
        XCTAssertEqual(SMCDecoder.value(type: "sp78", bytes: [0x2A, 0x80]), 42.5)
        // negativ: 0xFF00 = −1 °C
        XCTAssertEqual(SMCDecoder.value(type: "sp78", bytes: [0xFF, 0x00]), -1)
    }

    func testFPE2Fan() {
        // fpe2: 14 Ganzzahl-, 2 Nachkommabits – 0x1F40 / 4 = 2000 U/min
        XCTAssertEqual(SMCDecoder.value(type: "fpe2", bytes: [0x1F, 0x40]), 2000)
    }

    func testFloatLittleEndian() {
        let bits = Float(47.25).bitPattern
        let bytes = [UInt8(bits & 0xFF), UInt8((bits >> 8) & 0xFF), UInt8((bits >> 16) & 0xFF), UInt8((bits >> 24) & 0xFF)]
        XCTAssertEqual(SMCDecoder.value(type: "flt ", bytes: bytes), 47.25)
    }

    func testIntegersAndUnknown() {
        XCTAssertEqual(SMCDecoder.value(type: "ui8 ", bytes: [3]), 3)
        XCTAssertEqual(SMCDecoder.value(type: "ui16", bytes: [0x01, 0x00]), 256)
        XCTAssertEqual(SMCDecoder.value(type: "si16", bytes: [0xFF, 0xFE]), -2)
        XCTAssertEqual(SMCDecoder.value(type: "ui32", bytes: [0, 0, 1, 0]), 256)
        XCTAssertNil(SMCDecoder.value(type: "ch8*", bytes: [0x41]))
        XCTAssertNil(SMCDecoder.value(type: "ui16", bytes: [0x01]))
        // NaN aus einem Gleitkommawert wird verworfen
        let nan = Float.nan.bitPattern
        XCTAssertNil(SMCDecoder.value(type: "flt ", bytes: [UInt8(nan & 0xFF), UInt8((nan >> 8) & 0xFF),
                                                            UInt8((nan >> 16) & 0xFF), UInt8((nan >> 24) & 0xFF)]))
    }

    func testPlausibility() {
        XCTAssertFalse(SMCDecoder.plausibleTemperature(0))
        XCTAssertFalse(SMCDecoder.plausibleTemperature(-40))
        XCTAssertFalse(SMCDecoder.plausibleTemperature(200))
        XCTAssertTrue(SMCDecoder.plausibleTemperature(36.5))
        XCTAssertTrue(SMCDecoder.isTemperatureType("sp78"))
        XCTAssertTrue(SMCDecoder.isTemperatureType("flt "))
        XCTAssertFalse(SMCDecoder.isTemperatureType("ui8 "))
    }
}

final class SensorCatalogTests: XCTestCase {
    func testKnownAndPrefixClassification() {
        XCTAssertEqual(SensorCatalog.classify("TC0P").group, .cpu)
        XCTAssertEqual(SensorCatalog.classify("TC0P").meaning, "CPU proximity")
        XCTAssertEqual(SensorCatalog.classify("Tp09").group, .cpu)
        XCTAssertNil(SensorCatalog.classify("Tp09").meaning)
        XCTAssertEqual(SensorCatalog.classify("Tg05").group, .gpu)
        XCTAssertEqual(SensorCatalog.classify("TB1T").group, .battery)
        XCTAssertEqual(SensorCatalog.classify("TW0P").group, .wireless)
        XCTAssertEqual(SensorCatalog.classify("Ts0P").group, .enclosure)
        XCTAssertEqual(SensorCatalog.classify("TZ99").group, .other)
    }

    func testAggregateComputesAverageAndMaximum() {
        let sensors = [
            ThermalSensor(key: "Tp01", group: .cpu, meaning: nil, celsius: 40),
            ThermalSensor(key: "Tp05", group: .cpu, meaning: nil, celsius: 60),
            ThermalSensor(key: "Tg05", group: .gpu, meaning: nil, celsius: 35),
        ]
        let summary = SensorCatalog.aggregate(sensors)
        XCTAssertEqual(summary.map(\.group), [.cpu, .gpu])
        XCTAssertEqual(summary[0].average, 50)
        XCTAssertEqual(summary[0].maximum, 60)
        XCTAssertEqual(summary[0].count, 2)
        XCTAssertTrue(SensorCatalog.aggregate([]).isEmpty)
    }

    func testHottestPrefersCPUArea() {
        let date = Date()
        let sensors = [
            ThermalSensor(key: "Tp01", group: .cpu, meaning: nil, celsius: 55),
            ThermalSensor(key: "TB0T", group: .battery, meaning: "Battery", celsius: 70),
        ]
        let snapshot = ThermalSnapshot(state: Reading(.nominal, source: .thermalState, at: date),
                                       batteryTemperature: Reading(unavailable: .notPresent, source: .batteryTemperature, at: date),
                                       sensors: Reading(sensors, source: .smcSensors, at: date),
                                       fans: Reading([], source: .smcFans, at: date))
        XCTAssertEqual(snapshot.hottest?.key, "Tp01")
        let none = ThermalSnapshot(state: Reading(.nominal, source: .thermalState, at: date),
                                   batteryTemperature: Reading(unavailable: .notPresent, source: .batteryTemperature, at: date),
                                   sensors: Reading(unavailable: .virtualMachine, source: .smcSensors, at: date),
                                   fans: Reading(unavailable: .virtualMachine, source: .smcFans, at: date))
        XCTAssertNil(none.hottest)
    }

    func testFanFraction() {
        XCTAssertEqual(FanReading(index: 0, rpm: 3000, minimum: 1000, maximum: 5000, target: nil).fraction, 0.5)
        XCTAssertEqual(FanReading(index: 0, rpm: 6000, minimum: 1000, maximum: 5000, target: nil).fraction, 1)
        XCTAssertNil(FanReading(index: 0, rpm: 3000, minimum: nil, maximum: 5000, target: nil).fraction)
        XCTAssertNil(FanReading(index: 0, rpm: 3000, minimum: 5000, maximum: 5000, target: nil).fraction)
    }

    func testKnownMeaningsAreNamed() {
        XCTAssertTrue(SensorCatalog.knownMeanings.contains("CPU die"))
        XCTAssertFalse(SensorCatalog.knownMeanings.contains(""))
    }
}

final class PowerProfilerParserTests: XCTestCase {
    func testAppleSiliconLayout() throws {
        let json = """
        {"SPPowerDataType":[{"_name":"spbattery_information",
          "sppower_battery_charge_info":{"sppower_battery_at_warn_level":"FALSE","sppower_battery_state_of_charge":81},
          "sppower_battery_health_info":{"sppower_battery_cycle_count":212,"sppower_battery_health":"Good",
                                         "sppower_battery_health_maximum_capacity":"89%"},
          "sppower_battery_model_info":{"sppower_battery_manufacturer":"SMP","sppower_battery_device_name":"bq40z651",
                                        "sppower_battery_firmware_version":"1203"}},
          {"_name":"sppower_ac_charger_information","sppower_ac_charger_watts":"96","sppower_ac_charger_name":"96W USB-C Power Adapter"}]}
        """
        let info = try XCTUnwrap(PowerProfilerParser.parse(Data(json.utf8)))
        XCTAssertEqual(info.condition, "Good")
        XCTAssertEqual(info.maximumCapacity, "89%")
        XCTAssertEqual(info.cycleCount, 212)
        XCTAssertEqual(info.manufacturer, "SMP")
        XCTAssertEqual(info.deviceName, "bq40z651")
        XCTAssertEqual(info.firmware, "1203")
        XCTAssertEqual(info.chargerWatts, 96)
        XCTAssertEqual(info.chargerName, "96W USB-C Power Adapter")
    }

    func testDesktopWithoutBatteryReturnsNil() {
        let json = #"{"SPPowerDataType":[{"_name":"sppower_ac_charger_information"}]}"#
        XCTAssertNil(PowerProfilerParser.parse(Data(json.utf8)))
        XCTAssertNil(PowerProfilerParser.parse(Data("not json".utf8)))
    }
}

final class AdapterUnitsTests: XCTestCase {
    func testMillivoltsAndVolts() {
        XCTAssertEqual(AdapterUnits.volts(20_000), 20)
        XCTAssertEqual(AdapterUnits.volts(20), 20)
        XCTAssertNil(AdapterUnits.volts(0))
        XCTAssertNil(AdapterUnits.volts(120_000))
        XCTAssertEqual(AdapterUnits.amperes(4_700), 4.7)
        XCTAssertEqual(AdapterUnits.amperes(3), 3)
        XCTAssertNil(AdapterUnits.amperes(nil))
    }
}

final class ReportFormatterTests: XCTestCase {
    private let sections = [
        ReportSection(title: "Mac", symbol: "laptopcomputer", rows: [
            ReportRow("Model", "MacBook Pro", source: .systemProfiler),
            ReportRow("Serial number", "C02TEST", source: .serialNumber, isSensitive: true),
        ]),
        ReportSection(title: "Empty", symbol: "x", rows: []),
        ReportSection(title: "Pipes", symbol: "x", rows: [ReportRow("A|B", "line1\nline2")]),
    ]

    func testSensitiveRowsOnlyOnRequest() {
        let without = ReportFormatter.markdown(title: "T", subtitle: "S", columns: ("Item", "Value", "Type"), sections: sections,
                                               includeSensitive: false, describe: { $0.provenance.rawValue })
        XCTAssertFalse(without.contains("C02TEST"))
        XCTAssertTrue(without.contains("| Model | MacBook Pro | systemReported |"))
        let with = ReportFormatter.markdown(title: "T", subtitle: "S", columns: ("Item", "Value", "Type"), sections: sections,
                                            includeSensitive: true, describe: { $0.provenance.rawValue })
        XCTAssertTrue(with.contains("C02TEST"))
    }

    func testEmptySectionsSkippedAndCellsEscaped() {
        let text = ReportFormatter.markdown(title: "T", subtitle: "S", columns: ("Item", "Value", "Type"), sections: sections,
                                            includeSensitive: false, footer: "F", describe: { _ in "x" })
        XCTAssertFalse(text.contains("## Empty"))
        XCTAssertTrue(text.contains("| A\\|B | line1 line2 | – |"))
        XCTAssertTrue(text.hasPrefix("# T\n\nS\n"))
        XCTAssertTrue(text.contains("---\n\nF"))
    }

    func testFileName() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 9, minute: 5))!
        XCTAssertEqual(ReportFormatter.fileName(prefix: "AETHER System/Report", date: date, calendar: calendar),
                       "AETHER-System-Report_2026-03-07_09-05.md")
    }
}
