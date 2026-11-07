import Foundation
import IOKit
import AetherC
import AetherCore

/// Temperaturen und Lüfter aus dem System Management Controller – ausschließlich lesend.
/// Beim ersten Aufruf werden alle Schlüssel durchsucht und die Temperaturschlüssel mit plausiblen Werten gemerkt.
public final class SMCSource {
    private var connection: io_connect_t = 0
    private var opened = false
    private var discovered = false
    private var temperatureKeys: [String] = []
    private var fanCount: Int?
    public private(set) var keyCount = 0

    public init() {}

    deinit {
        aether_smc_close(connection)
    }

    /// Ist ein SMC vorhanden und zugänglich?
    public var isAvailable: Bool {
        if !opened {
            connection = aether_smc_open()
            opened = true
        }
        return connection != 0
    }

    private func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        guard connection != 0 else { return nil }
        var value = AetherSMCValue()
        let ok = key.withCString { aether_smc_read(connection, $0, &value) }
        guard ok else { return nil }
        let type = withUnsafeBytes(of: &value.type) { String(decoding: $0.prefix(4), as: UTF8.self) }
        let size = Int(min(value.size, 32))
        let bytes = withUnsafeBytes(of: &value.bytes) { Array($0.prefix(size)) }
        return (type, bytes)
    }

    private func number(_ key: String) -> Double? {
        guard let raw = read(key) else { return nil }
        return SMCDecoder.value(type: raw.type, bytes: raw.bytes)
    }

    private func discover() {
        discovered = true
        let count = Int(aether_smc_key_count(connection))
        keyCount = count
        guard count > 0, count < 20_000 else { return }
        var keys: [String] = []
        var buffer = [CChar](repeating: 0, count: 5)
        for index in 0..<count {
            guard aether_smc_key_at(connection, UInt32(index), &buffer) else { continue }
            let key = String(cString: buffer)
            guard key.count == 4, key.hasPrefix("T") else { continue }
            guard let raw = read(key), SMCDecoder.isTemperatureType(raw.type),
                  let value = SMCDecoder.value(type: raw.type, bytes: raw.bytes),
                  SMCDecoder.plausibleTemperature(value) else { continue }
            keys.append(key)
        }
        temperatureKeys = keys.sorted()
        if let fans = number("FNum") { fanCount = Int(fans) }
    }

    /// Eine Messung. `isVirtualMachine` bestimmt die Begründung, wenn kein SMC vorhanden ist.
    public func sample(at date: Date = Date(), isVirtualMachine: Bool) -> (sensors: Reading<[ThermalSensor]>, fans: Reading<[FanReading]>) {
        guard isAvailable else {
            let reason: UnavailableReason = isVirtualMachine ? .virtualMachine : .notProvidedByMacOS
            return (Reading(unavailable: reason, source: .smcSensors, at: date), Reading(unavailable: reason, source: .smcFans, at: date))
        }
        if !discovered { discover() }

        var sensors: [ThermalSensor] = []
        for key in temperatureKeys {
            guard let value = number(key), SMCDecoder.plausibleTemperature(value) else { continue }
            let info = SensorCatalog.classify(key)
            sensors.append(ThermalSensor(key: key, group: info.group, meaning: info.meaning, celsius: value))
        }
        let sensorReading: Reading<[ThermalSensor]> = temperatureKeys.isEmpty
            ? Reading(unavailable: .notProvidedByMacOS, source: .smcSensors, at: date)
            : Reading(sensors, source: .smcSensors, at: date)

        let fanReading: Reading<[FanReading]>
        if let fanCount {
            var fans: [FanReading] = []
            for index in 0..<max(0, min(fanCount, 8)) {
                guard let rpm = number("F\(index)Ac"), rpm >= 0, rpm < 20_000 else { continue }
                fans.append(FanReading(index: index, rpm: rpm, minimum: number("F\(index)Mn"), maximum: number("F\(index)Mx"),
                                       target: number("F\(index)Tg")))
            }
            fanReading = Reading(fans, source: .smcFans, at: date)
        } else {
            fanReading = Reading(unavailable: .notProvidedByMacOS, source: .smcFans, at: date)
        }
        return (sensorReading, fanReading)
    }
}
