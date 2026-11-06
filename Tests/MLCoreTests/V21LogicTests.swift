import XCTest
@testable import MLCore

/// Deterministischer Zufallsgenerator für Tests (SplitMix64).
private struct TestRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class DateAddedResolverTests: XCTestCase {
    private let now: Int64 = 1_780_000_000

    func testNewTrackPrefersAppleMusicThenCreationThenFolder() {
        XCTAssertEqual(DateAddedResolver.forNewTrack(.init(appleMusic: 1_300_000_000, fileCreated: 1_500_000_000), now: now).source, .appleMusic)
        let c = DateAddedResolver.forNewTrack(.init(fileCreated: 1_500_000_000, addedToFolder: 1_600_000_000), now: now)
        XCTAssertEqual(c.date, 1_500_000_000)
        XCTAssertEqual(c.source, .fileCreated)
        XCTAssertEqual(DateAddedResolver.forNewTrack(.init(addedToFolder: 1_600_000_000), now: now).source, .addedToFolder)
        let none = DateAddedResolver.forNewTrack(.init(), now: now)
        XCTAssertEqual(none.date, now)
        XCTAssertEqual(none.source, .firstImport)
    }

    func testImplausibleDatesAreIgnored() {
        // 1970/1984 (FAT, defekte Kopien) und Zukunft werden verworfen
        let r = DateAddedResolver.forNewTrack(.init(fileCreated: 0, addedToFolder: 441_763_200), now: now)
        XCTAssertEqual(r.source, .firstImport)
        XCTAssertEqual(DateAddedResolver.forNewTrack(.init(fileCreated: now + 10 * 86_400), now: now).source, .firstImport)
    }

    func testReconstructOnlyMovesDatesEarlierAndKeepsAppleMusic() {
        // Importdatum 2026, Datei 2019 erstellt → 2019
        let a = DateAddedResolver.reconstruct(current: 1_770_000_000, source: .unknown, .init(fileCreated: 1_550_000_000), now: now)
        XCTAssertEqual(a?.date, 1_550_000_000)
        XCTAssertEqual(a?.source, .fileCreated)
        // Datei nach dem Import erstellt (z. B. kopiert) → Importdatum bleibt
        let b = DateAddedResolver.reconstruct(current: 1_600_000_000, source: .unknown, .init(fileCreated: 1_700_000_000), now: now)
        XCTAssertEqual(b?.date, 1_600_000_000)
        XCTAssertEqual(b?.source, .firstImport)
        // Bereits rekonstruiert: nur Apple Musik ändert noch etwas
        XCTAssertNil(DateAddedResolver.reconstruct(current: 1_550_000_000, source: .fileCreated, .init(fileCreated: 1_400_000_000), now: now))
        XCTAssertEqual(DateAddedResolver.reconstruct(current: 1_550_000_000, source: .fileCreated, .init(appleMusic: 1_200_000_000), now: now)?.source, .appleMusic)
        // Apple-Musik-Datum wird nie ersetzt
        XCTAssertNil(DateAddedResolver.reconstruct(current: 1_200_000_000, source: .appleMusic, .init(appleMusic: 1_100_000_000), now: now))
    }

    /// Mehrere Titel und Alben, beide Richtungen: das Album-Datum ist das neueste seiner Titel; unterschiedliche
    /// Daten ergeben eine Reihenfolge nach Datum statt alphabetisch.
    func testTracksAndAlbumsSortByDateAddedBothDirections() {
        func t(_ uid: Int64, _ title: String, album: String, added: Int64) -> Track {
            Track(uid: uid, folderID: 1, path: "/m/\(uid).mp3", relativePath: "", fileName: "\(uid).mp3", title: title,
                  artists: ["A"], album: album, albumArtists: ["A"], durationMs: 1000, sizeBytes: 1, dateModified: 0, dateAdded: added)
        }
        let tracks = [t(1, "Zebra", album: "Älter", added: 1_400_000_000), t(2, "Apfel", album: "Neu", added: 1_700_000_000),
                      t(3, "Mitte", album: "Mittel", added: 1_550_000_000), t(4, "Banane", album: "Älter", added: 1_450_000_000)]
        let newest = Sorting.tracks(tracks, sort: Sort(TrackSort.dateAdded, descending: true), stats: [:]).map(\.uid)
        XCTAssertEqual(newest, [2, 3, 4, 1])
        let oldest = Sorting.tracks(tracks, sort: Sort(TrackSort.dateAdded, descending: false), stats: [:]).map(\.uid)
        XCTAssertEqual(oldest, [1, 4, 3, 2])
        let albums = AlbumGrouping.group(tracks).albums
        let older = albums.first { $0.title == "Älter" }
        XCTAssertEqual(older?.dateAdded, 1_450_000_000)
        let albumOrder = Sorting.albums(albums, sort: Sort(AlbumSort.dateAdded, descending: true), stats: [:]).map(\.title)
        XCTAssertEqual(albumOrder, ["Neu", "Mittel", "Älter"])
        let albumOldest = Sorting.albums(albums, sort: Sort(AlbumSort.dateAdded, descending: false), stats: [:]).map(\.title)
        XCTAssertEqual(albumOldest, ["Älter", "Mittel", "Neu"])
    }
}

final class AlbumShuffleTests: XCTestCase {
    func testAlbumsStayInTrackOrderAndCurrentAlbumFirst() {
        var rng = TestRNG(state: 7)
        // drei Alben: 0 = [0,1,2], 1 = [3,4], 2 = [5,6,7]
        let groups = [0, 0, 0, 1, 1, 2, 2, 2]
        for seed in 0..<50 {
            rng.state = UInt64(seed)
            let order = AlbumShuffle.order(groups: groups, current: 4, using: &rng)
            XCTAssertEqual(Set(order), Set(0..<8))
            XCTAssertEqual(Array(order.prefix(2)), [3, 4])       // laufendes Album zuerst, in Titelreihenfolge
            let rest = Array(order.dropFirst(2))
            XCTAssertTrue(rest == [0, 1, 2, 5, 6, 7] || rest == [5, 6, 7, 0, 1, 2])
        }
    }

    func testAllAlbumOrdersOccur() {
        var rng = TestRNG(state: 1)
        var seen = Set<[Int]>()
        for _ in 0..<200 { seen.insert(AlbumShuffle.order(groups: [0, 1, 2], current: nil, using: &rng)) }
        XCTAssertEqual(seen.count, 6)   // echte Zufallsfolge: alle 3! Reihenfolgen kommen vor
    }

    func testQueueAlbumShuffleAndRepeatWithoutImmediateRepeat() {
        var q = PlayQueue()
        var rng = TestRNG(state: 3)
        q.replaceAlbums([[10, 11, 12], [20, 21], [30]], currentTrackUid: nil, shuffle: true, source: nil, using: &rng)
        XCTAssertTrue(q.isAlbumShuffle)
        // Abspielfolge: jedes Album zusammenhängend und in Titelreihenfolge
        let played = q.itemsInPlayOrder.map(\.trackUid)
        XCTAssertEqual(played.count, 6)
        let albums: [[Int64]] = [[10, 11, 12], [20, 21], [30]]
        for album in albums {
            let i = played.firstIndex(of: album[0])!
            XCTAssertEqual(Array(played[i..<(i + album.count)]), album)
        }
        XCTAssertEqual(q.currentTrackUid, played.first)
        // Wiederholen: neuer Durchgang beginnt nie mit dem zuletzt gespielten Album
        q.repeatMode = .all
        for _ in 0..<40 {
            var lastAlbum: Int64 = 0
            for _ in 0..<6 {
                lastAlbum = q.currentTrackUid! / 10
                _ = q.advanceAfterCompletion()
            }
            XCTAssertNotEqual(q.currentTrackUid! / 10, lastAlbum)
            // wieder am Anfang eines Albums
            XCTAssertEqual(q.currentTrackUid! % 10, 0)
        }
    }

    func testShuffleToggleKeepsCurrentAlbumAndOffRestoresListOrder() {
        var q = PlayQueue()
        q.replaceAlbums([[1, 2, 3], [4, 5], [6, 7]], currentTrackUid: 2, shuffle: false, source: nil)
        XCTAssertEqual(q.currentTrackUid, 2)
        XCTAssertFalse(q.isAlbumShuffle)
        q.setShuffle(true)
        XCTAssertTrue(q.isAlbumShuffle)
        XCTAssertEqual(q.currentTrackUid, 2)
        XCTAssertEqual(q.upNext.first?.trackUid, 3)            // Album läuft zu Ende
        q.setShuffle(false)
        XCTAssertEqual(q.itemsInPlayOrder.map(\.trackUid), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(q.currentTrackUid, 2)
    }

    func testTrackShuffleNewCycleDoesNotRepeatLastTrack() {
        var q = PlayQueue()
        q.replace(with: [1, 2, 3, 4], startIndex: 0, shuffle: .on)
        q.repeatMode = .all
        for _ in 0..<50 {
            var last: Int64 = 0
            for _ in 0..<4 {
                last = q.currentTrackUid!
                _ = q.advanceAfterCompletion()
            }
            XCTAssertNotEqual(q.currentTrackUid, last)
        }
    }

    func testAlbumGroupsSurviveCodingAndManualEditsFallBack() throws {
        var q = PlayQueue()
        q.replaceAlbums([[1, 2], [3, 4]], currentTrackUid: 1, shuffle: true, source: nil)
        let decoded = try JSONDecoder().decode(PlayQueue.self, from: JSONEncoder().encode(q))
        XCTAssertTrue(decoded.isAlbumShuffle)
        XCTAssertEqual(decoded.itemsInPlayOrder.map(\.trackUid), q.itemsInPlayOrder.map(\.trackUid))
        q.addToEnd([9])
        XCTAssertFalse(q.isAlbumShuffle)            // Warteschlange von Hand geändert → normaler Zufall
        XCTAssertTrue(q.shuffleEnabled)
    }
}

final class V21SettingsTests: XCTestCase {
    func testNewSettingsRoundTripAndOldValuesStay() {
        var s = AppSettings()
        XCTAssertEqual(s.playerBackground, .auto)
        s.playerBackground = .custom
        s.playerBackgroundCustom = 0xFF112233
        s.playerBackgroundTintsMini = false
        s.miniPlayerSize = .huge
        let d = AppSettings.decode(from: s.encoded())
        XCTAssertEqual(d.playerBackground, .custom)
        XCTAssertEqual(d.playerBackgroundCustom, 0xFF112233)
        XCTAssertFalse(d.playerBackgroundTintsMini)
        XCTAssertEqual(d.miniPlayerSize, .huge)
        // gespeicherte Werte der bisherigen Größen bleiben gültig
        XCTAssertEqual(MiniPlayerSize(rawValue: "COMPACT"), .compact)
        XCTAssertEqual(MiniPlayerSize(rawValue: "LARGE")?.height, 112)
        XCTAssertEqual(MiniPlayerSize.allCases.map(\.label), ["Klein", "Mittel", "Groß", "Sehr groß", "Riesig"])
        XCTAssertTrue(MiniPlayerSize.allCases.map(\.height) == MiniPlayerSize.allCases.map(\.height).sorted())
    }

    func testBackgroundBrightness() {
        XCTAssertTrue(PlayerBackgroundStyle.white.isLight(custom: 0))
        XCTAssertFalse(PlayerBackgroundStyle.black.isLight(custom: 0))
        XCTAssertTrue(PlayerBackgroundStyle.custom.isLight(custom: 0xFFFFF0F5))
        XCTAssertFalse(PlayerBackgroundStyle.custom.isLight(custom: 0xFF101020))
    }

    func testCoverSizeAllowsLargeTiles() {
        XCTAssertEqual(LibraryViewOptions(coverSize: 520).coverSize, 520)
        XCTAssertEqual(LibraryViewOptions(coverSize: 2000).coverSize, 560)
    }
}
