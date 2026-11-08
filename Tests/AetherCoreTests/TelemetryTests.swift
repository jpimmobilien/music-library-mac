import XCTest
@testable import AetherCore

final class SmoothingTests: XCTestCase {
    func testAlpha() {
        XCTAssertEqual(AsymmetricEMA.alpha(deltaTime: 1, tau: 1), 1 - exp(-1), accuracy: 1e-12)
        XCTAssertEqual(AsymmetricEMA.alpha(deltaTime: 1, tau: 0), 1)
        XCTAssertEqual(AsymmetricEMA.alpha(deltaTime: 0, tau: 2), 0)
    }

    func testFirstValueIsTakenAsIs() {
        var ema = AsymmetricEMA(rise: 1, fall: 3)
        XCTAssertEqual(ema.update(0.4, at: 10), 0.4)
    }

    func testRiseIsFasterThanFall() {
        var up = AsymmetricEMA(rise: 0.5, fall: 3)
        up.update(0, at: 0)
        let afterRise = up.update(1, at: 1)            // alpha = 1 - e^-2 ≈ 0.8647
        XCTAssertEqual(afterRise, 1 - exp(-2), accuracy: 1e-9)

        var down = AsymmetricEMA(rise: 0.5, fall: 3)
        down.update(1, at: 0)
        let afterFall = down.update(0, at: 1)          // alpha = 1 - e^-1/3 ≈ 0.2835 → 0.7165
        XCTAssertEqual(afterFall, exp(-1.0 / 3.0), accuracy: 1e-9)
        XCTAssertGreaterThan(afterRise, 1 - afterFall)
    }

    func testTimeDependentAlphaIsIntervalIndependent() {
        // zwei Schritte à 0,5 s ergeben dasselbe wie ein Schritt à 1 s bei konstantem Rohwert
        var a = AsymmetricEMA(rise: 2, fall: 2)
        a.update(0, at: 0)
        a.update(1, at: 0.5)
        let two = a.update(1, at: 1)
        var b = AsymmetricEMA(rise: 2, fall: 2)
        b.update(0, at: 0)
        let one = b.update(1, at: 1)
        XCTAssertEqual(two, one, accuracy: 1e-12)
    }

    func testLargeGapRestarts() {
        var ema = AsymmetricEMA(rise: 1, fall: 1)
        ema.update(0, at: 0)
        XCTAssertEqual(ema.update(0.9, at: 1_000), 0.9)
    }

    func testNonFiniteIgnored() {
        var ema = AsymmetricEMA(rise: 1, fall: 1)
        ema.update(0.5, at: 0)
        XCTAssertEqual(ema.update(.nan, at: 1), 0.5)
    }

    func testPeakWindowKeepsSpike() {
        var peaks = PeakWindow(window: 10)
        XCTAssertEqual(peaks.add(1, at: 0), 1)
        XCTAssertEqual(peaks.add(9, at: 1), 9)
        XCTAssertEqual(peaks.add(2, at: 5), 9)
        XCTAssertEqual(peaks.add(3, at: 10.5), 9)       // 9 bei t=1 liegt noch im Fenster [0,5 … 10,5]
        XCTAssertEqual(peaks.add(1, at: 11.5), 3)       // 9 ist herausgefallen
    }

    func testSmootherCarriesRawAndPeak() {
        var smoother = MetricSmoother(profile: .throughput)
        _ = smoother.update(raw: 0, at: 0)
        let spike = smoother.update(raw: 1_000_000, at: 1)
        XCTAssertEqual(spike.raw, 1_000_000)
        XCTAssertEqual(spike.peak, 1_000_000)
        XCTAssertLessThan(spike.smoothed, 1_000_000)
        XCTAssertGreaterThan(spike.smoothed, 500_000)    // Anstieg schnell (τ 0,6 s)
        let after = smoother.update(raw: 0, at: 2)
        XCTAssertEqual(after.peak, 1_000_000)            // Spitze bleibt 10 s sichtbar
        XCTAssertGreaterThan(after.smoothed, 0)
    }

    func testNoneProfileIsRaw() {
        var smoother = MetricSmoother(profile: .none)
        _ = smoother.update(raw: 50, at: 0)
        XCTAssertEqual(smoother.update(raw: 51, at: 1).smoothed, 51)
    }
}

final class DisplayQuantizerTests: XCTestCase {
    func testFractionStepsOfOnePercent() {
        XCTAssertEqual(DisplayQuantizer.key(0.421, unit: .fraction), DisplayQuantizer.key(0.4249, unit: .fraction))
        XCTAssertNotEqual(DisplayQuantizer.key(0.42, unit: .fraction), DisplayQuantizer.key(0.43, unit: .fraction))
    }

    func testThroughputThreeSignificantDigits() {
        XCTAssertEqual(DisplayQuantizer.key(12_340, unit: .bytesPerSecond), DisplayQuantizer.key(12_344, unit: .bytesPerSecond))
        XCTAssertNotEqual(DisplayQuantizer.key(12_300, unit: .bytesPerSecond), DisplayQuantizer.key(12_400, unit: .bytesPerSecond))
        XCTAssertNotEqual(DisplayQuantizer.key(999, unit: .bytesPerSecond), DisplayQuantizer.key(9_990, unit: .bytesPerSecond))
        XCTAssertEqual(DisplayQuantizer.key(0.2, unit: .bytesPerSecond), 0)
    }

    func testOtherUnits() {
        XCTAssertEqual(DisplayQuantizer.key(61.1, unit: .celsius), DisplayQuantizer.key(60.9, unit: .celsius))
        XCTAssertNotEqual(DisplayQuantizer.key(61.0, unit: .celsius), DisplayQuantizer.key(61.6, unit: .celsius))
        XCTAssertEqual(DisplayQuantizer.key(2_004, unit: .rpm), DisplayQuantizer.key(1_996, unit: .rpm))
        XCTAssertEqual(DisplayQuantizer.key(.nan, unit: .watts), Int64.min)
    }
}

final class TimeSeriesTests: XCTestCase {
    func testCapacityAndOrder() {
        var series = TimeSeries(capacity: 3)
        for t in 0..<5 { series.append(Double(t), at: Double(t)) }
        XCTAssertEqual(series.points.map(\.time), [2, 3, 4])
        XCTAssertEqual(series.points.compactMap(\.value), [2, 3, 4])
        XCTAssertEqual(series.lastTime, 4)
    }

    func testGapsStayGaps() {
        var series = TimeSeries(capacity: 10)
        series.append(1, at: 0)
        series.append(nil, at: 1)
        series.append(3, at: 2)
        XCTAssertNil(series.points[1].value)
    }

    func testBucketsKeepSpikes() {
        var series = TimeSeries(capacity: 3_600)
        for t in 0..<3_600 { series.append(t == 1_234 ? 100 : 1, at: Double(t)) }
        let buckets = series.buckets(window: 3_600, now: 3_599, count: 240)
        XCTAssertEqual(buckets.count, 240)
        XCTAssertEqual(buckets.compactMap { $0.hasData ? $0.maximum : nil }.max(), 100)   // Spitze nicht verloren
        XCTAssertEqual(buckets.filter(\.hasData).count, 240)
        let total = buckets.reduce(0) { $0 + $1.count }
        XCTAssertEqual(total, 3_600)
    }

    func testBucketsOnlyWindow() {
        var series = TimeSeries(capacity: 100)
        for t in 0..<100 { series.append(Double(t), at: Double(t)) }
        let buckets = series.buckets(window: 10, now: 99, count: 5)
        XCTAssertEqual(buckets.reduce(0) { $0 + $1.count }, 11)        // t = 89 … 99
        XCTAssertEqual(buckets.last?.maximum, 99)
        XCTAssertEqual(series.maximum(window: 10, now: 99), 99)
    }

    func testBucketsAfterWrapAround() {
        var series = TimeSeries(capacity: 3)
        for t in 0..<5 { series.append(Double(t), at: Double(t)) }       // behält t = 2, 3, 4
        let buckets = series.buckets(window: 10, now: 4, count: 5)
        XCTAssertEqual(buckets.reduce(0) { $0 + $1.count }, 3)
        XCTAssertEqual(buckets.compactMap { $0.hasData ? $0.maximum : nil }.max(), 4)
        XCTAssertEqual(series.maximum(window: 1, now: 4), 4)
        XCTAssertEqual(series.maximum(window: 10, now: 3), 3)
        XCTAssertNil(TimeSeries(capacity: 4).maximum(window: 10, now: 0))
        XCTAssertEqual(TimeSeries(capacity: 4).buckets(window: 10, now: 0, count: 3).count, 3)
    }

    func testDrawOrderBridgesSparseSamplesButNotGaps() {
        var series = TimeSeries(capacity: 100)
        // alle 3 s gemessen, 1-s-Abschnitte → zwei leere Abschnitte zwischen den Messungen werden überbrückt
        for t in stride(from: 0, through: 30, by: 3) { series.append(1, at: Double(t)) }
        var buckets = series.buckets(window: 30, now: 30, count: 30)
        XCTAssertFalse(SeriesBucket.drawOrder(buckets, bridge: 20).contains(where: { $0 == nil }))
        // ausdrücklich fehlender Wert → Unterbrechung
        series.append(nil, at: 33)
        series.append(1, at: 36)
        buckets = series.buckets(window: 36, now: 36, count: 36)
        XCTAssertEqual(SeriesBucket.drawOrder(buckets, bridge: 20).filter { $0 == nil }.count, 1)
        // lange Pause ohne Messung → Unterbrechung
        series.append(1, at: 80)
        buckets = series.buckets(window: 80, now: 80, count: 80)
        XCTAssertEqual(SeriesBucket.drawOrder(buckets, bridge: 20).filter { $0 == nil }.count, 2)
    }

    func testNiceScale() {
        XCTAssertEqual(NiceScale.upperBound(for: 0.7), 1)
        XCTAssertEqual(NiceScale.upperBound(for: 1_300), 2_000)
        XCTAssertEqual(NiceScale.upperBound(for: 2_400), 2_500)
        XCTAssertEqual(NiceScale.upperBound(for: 4_100), 5_000)
        XCTAssertEqual(NiceScale.upperBound(for: 7_000_000), 10_000_000)
    }
}

final class RoutableAddressTests: XCTestCase {
    func testIPv4() {
        XCTAssertTrue(RoutableAddress.isRoutable(ipv4: 0xC0A8_0164))     // 192.168.1.100
        XCTAssertFalse(RoutableAddress.isRoutable(ipv4: 0xA9FE_0101))    // 169.254.1.1
        XCTAssertFalse(RoutableAddress.isRoutable(ipv4: 0x7F00_0001))    // 127.0.0.1
        XCTAssertFalse(RoutableAddress.isRoutable(ipv4: 0))
    }

    func testIPv6() {
        var linkLocal = [UInt8](repeating: 0, count: 16)
        linkLocal[0] = 0xFE; linkLocal[1] = 0x80; linkLocal[15] = 0x01
        XCTAssertFalse(RoutableAddress.isRoutable(ipv6: linkLocal))
        var loopback = [UInt8](repeating: 0, count: 16)
        loopback[15] = 1
        XCTAssertFalse(RoutableAddress.isRoutable(ipv6: loopback))
        var global = [UInt8](repeating: 0, count: 16)
        global[0] = 0x2A; global[1] = 0x02; global[15] = 0x10
        XCTAssertTrue(RoutableAddress.isRoutable(ipv6: global))
        var uniqueLocal = [UInt8](repeating: 0, count: 16)
        uniqueLocal[0] = 0xFD; uniqueLocal[15] = 0x01
        XCTAssertTrue(RoutableAddress.isRoutable(ipv6: uniqueLocal))
        XCTAssertFalse(RoutableAddress.isRoutable(ipv6: [1, 2]))
    }
}
