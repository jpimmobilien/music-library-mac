import XCTest
@testable import MLCore

/// 2.2.2: Abschnitte bei Sortierung nach Erscheinungsjahr und „Hinzugefügt“.
final class SectioningTests: XCTestCase {
    private var berlin: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }

    private func seconds(_ y: Int, _ m: Int, _ d: Int) -> Int64 {
        Int64(berlin.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!.timeIntervalSince1970)
    }

    func testYearRunsDescendingWithUnknownLast() {
        let tracks = [2024, 2024, 2023, 1999, 1999, 1999].map { TestTracks.track(year: $0) } + [TestTracks.track(year: nil)]
        let runs = LibrarySectioning.tracks(tracks, sort: Sort(.year, descending: true))!
        XCTAssertEqual(runs.map(\.title), ["2024", "2023", "1999", "Ohne Jahr"])
        XCTAssertEqual(runs.map(\.count), [2, 1, 3, 1])
        XCTAssertEqual(runs.map(\.range), [0..<2, 2..<3, 3..<6, 6..<7])
        XCTAssertEqual(Set(runs.map(\.id)).count, runs.count)
    }

    func testAddedRecentByMonthOlderByYear() {
        let now = Date(timeIntervalSince1970: TimeInterval(seconds(2026, 11, 12)))
        let dates = [seconds(2026, 11, 10), seconds(2026, 11, 1), seconds(2026, 10, 31), seconds(2025, 3, 2),
                     seconds(2024, 12, 24), seconds(2024, 1, 1), seconds(2019, 6, 1), 0]
        let tracks = dates.map { TestTracks.track(dateAdded: $0) }
        let runs = LibrarySectioning.tracks(tracks, sort: Sort(.dateAdded, descending: true), now: now, calendar: berlin)!
        XCTAssertEqual(runs.map(\.title), ["November 2026", "Oktober 2026", "März 2025", "2024", "2019", "Unbekannt"])
        XCTAssertEqual(runs.map(\.count), [2, 1, 1, 2, 1, 1])
    }

    func testAlbumsAndOtherSortsHaveNoSections() {
        let a = AlbumInfo(key: "a", title: "A", artist: "X", isVarious: false, year: 2020, genre: nil, trackUids: [1], discNumbers: [1],
                          totalDurationMs: 1000, sortTitle: nil, sortArtist: nil, dateAdded: 0)
        XCTAssertEqual(LibrarySectioning.albums([a], sort: Sort(.year, descending: true))?.map(\.title), ["2020"])
        XCTAssertNil(LibrarySectioning.albums([a], sort: Sort(.title, descending: false)))
        XCTAssertNil(LibrarySectioning.tracks([TestTracks.track()], sort: Sort(.title, descending: false)))
        XCTAssertEqual(LibrarySectioning.tracks([], sort: Sort(.year, descending: true))?.count, 0)
    }

    func testRepeatedKeysGetUniqueIDs() {
        let tracks = [2020, 2021, 2020].map { TestTracks.track(year: $0) }
        let runs = LibrarySectioning.tracks(tracks, sort: Sort(.year, descending: false))!
        XCTAssertEqual(runs.map(\.title), ["2020", "2021", "2020"])
        XCTAssertEqual(Set(runs.map(\.id)).count, 3)
    }

    /// Der Zwischenspeicher liefert für jede Sekunde dasselbe wie die direkte Rechnung – an Monats- und
    /// Jahresgrenzen, über Zeitumstellungen hinweg, auf- und absteigend sortiert und durcheinander.
    func testCachedAddedKeyMatchesDirectCalculation() {
        let nowYear = 2026
        var probes: [Int64] = [0, -5, 1]
        for y in 2017...2027 {
            for m in 1...12 {
                let start = Int64(berlin.date(from: DateComponents(year: y, month: m, day: 1))!.timeIntervalSince1970)
                probes += [start - 3601, start - 3600, start - 1, start, start + 1, start + 3600, start + 86_400 * 14]
            }
            // Zeitumstellung (letzter Sonntag im März und Oktober, Europe/Berlin)
            for m in [3, 10] {
                let d = berlin.date(from: DateComponents(year: y, month: m, day: 31, hour: 1))!
                let t = Int64(d.timeIntervalSince1970)
                probes += [t - 7200, t - 3600, t, t + 3600, t + 7200]
            }
        }
        var lcg: UInt64 = 0x9E37_79B9_7F4A_7C15
        for _ in 0..<2000 {
            lcg = lcg &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            probes.append(1_480_000_000 + Int64(lcg >> 35) % 340_000_000)
        }
        for order in [probes.sorted(), probes.sorted(by: >), probes] {
            for cal in [berlin, Calendar(identifier: .gregorian)] {
                var keyer = LibrarySectioning.AddedKeyer(nowYear: nowYear, calendar: cal)
                for s in order {
                    XCTAssertEqual(keyer.key(s), LibrarySectioning.addedKey(s, nowYear: nowYear, calendar: cal), "Sekunde \(s)")
                }
            }
        }
    }

    func testImplausibleYearIsUnknown() {
        XCTAssertEqual(LibrarySectioning.yearKey(0), .unknown)
        XCTAssertEqual(LibrarySectioning.yearKey(12_345), .unknown)
        XCTAssertEqual(LibrarySectioning.yearKey(1987), .year(1987))
    }
}
