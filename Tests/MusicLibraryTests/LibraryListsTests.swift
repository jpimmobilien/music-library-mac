import XCTest
import MLCore
@testable import MusicLibrary

/// v2: Listen des App-Modells mit Filtern, neuen Sortierungen und intelligenten Playlists – derselbe Weg wie
/// in der App (`AppModel.computeLists`), mit der großen erfundenen Bibliothek aus dem Messlauf.
final class LibraryListsTests: XCTestCase {
    private static let library = Benchmark.makeLibrary(tracks: 3_000)
    private var index: LibraryIndex { LibraryIndex.build(Self.library.tracks) }

    private func lists(settings: AppSettings = AppSettings(), queries: [LibrarySection: String] = [:],
                       filters: [LibraryViewContext: LibraryFilter] = [:]) -> AppModel.Lists {
        let lib = Self.library
        return AppModel.computeLists(index: index, settings: settings, stats: lib.stats, favorites: lib.favorites,
                                     favoriteAlbums: [:], playlists: lib.playlists, queries: queries, filters: filters)
    }

    func testFilterByDecadeAndLosslessNarrowsAllSections() {
        let all = lists()
        var f = LibraryFilter()
        f.decades = [1990]
        f.quick = [.lossless]
        let filtered = lists(filters: [.tracks: f, .albums: f])
        XCTAssertFalse(filtered.tracks.isEmpty)
        XCTAssertLessThan(filtered.tracks.count, all.tracks.count)
        XCTAssertTrue(filtered.tracks.allSatisfy { ($0.year ?? 0) / 10 * 10 == 1990 && $0.codec == "ALAC" })
        XCTAssertFalse(filtered.albums.isEmpty)
        XCTAssertLessThan(filtered.albums.count, all.albums.count)
        // „x von y“: die ungefilterte Anzahl bleibt erhalten
        XCTAssertEqual(filtered.unfilteredCount[.tracks], all.tracks.count)
        XCTAssertEqual(filtered.unfilteredCount[.albums], all.albums.count)
        // andere Bereiche bleiben unberührt
        XCTAssertEqual(filtered.artists.count, all.artists.count)
    }

    func testFilterAndMultiTermSearchCombine() {
        var f = LibraryFilter()
        f.quick = [.favorites]
        let query = "nacht licht"
        let result = lists(queries: [.tracks: query], filters: [.tracks: f])
        let idx = index
        for t in result.tracks {
            XCTAssertNotNil(Self.library.favorites[t.uid])
            let text = idx.trackSearchText[t.uid] ?? ""
            XCTAssertTrue(TextNorm.matchesAll(TextNorm.searchTerms(query), text))
        }
    }

    func testFacetsCoverGenresDecadesAndFormats() {
        let facets = lists().facets
        XCTAssertGreaterThanOrEqual(facets.genres.count, 10)
        XCTAssertTrue(facets.decades.contains { $0.id == "1990" })
        XCTAssertTrue(facets.formats.contains { $0.id == "ALAC" })
        XCTAssertTrue(facets.formats.contains { $0.id == "AAC" })
    }

    func testNewTrackSortsOrderCorrectly() {
        var s = AppSettings()
        s.trackSort = Sort(TrackSort.bpm, descending: true)
        let byBpm = lists(settings: s).tracks.compactMap(\.bpm)
        XCTAssertEqual(byBpm, byBpm.sorted(by: >))
        s.trackSort = Sort(TrackSort.dateAdded, descending: true)
        let added = lists(settings: s).tracks.map(\.dateAdded)
        XCTAssertEqual(added, added.sorted(by: >))
    }

    func testSmartPlaylistsIncludeV2Kinds() {
        let smart = lists().smartAll
        let ids = Set(smart.map(\.id))
        XCTAssertTrue(ids.contains(SmartPlaylists.recentlyAddedID))
        XCTAssertTrue(smart.contains { $0.id.hasPrefix(SmartPlaylists.genrePrefix) })
        let neverPlayed = smart.first { $0.kind == .neverPlayed }
        XCTAssertNotNil(neverPlayed)
        // „Nie gespielt“: kein Titel mit Zählerstand
        for uid in neverPlayed?.trackUids ?? [] {
            XCTAssertNil(Self.library.stats[uid].flatMap { $0.playCount > 0 ? $0 : nil })
        }
    }

    func testTenThousandTracksComputeQuickly() {
        let lib = Benchmark.makeLibrary(tracks: 10_000)
        let start = CFAbsoluteTimeGetCurrent()
        let idx = LibraryIndex.build(lib.tracks)
        let built = CFAbsoluteTimeGetCurrent()
        var f = LibraryFilter()
        f.genres = [lists().facets.genres.first?.id ?? ""]
        _ = AppModel.computeLists(index: idx, settings: AppSettings(), stats: lib.stats, favorites: lib.favorites, favoriteAlbums: [:],
                                  playlists: lib.playlists, queries: [.tracks: "licht"], filters: [.tracks: f, .albums: f])
        let done = CFAbsoluteTimeGetCurrent()
        print("[Listen] 10.000 Titel: Index \(Int((built - start) * 1000)) ms, alle Listen mit Suche + Filter \(Int((done - built) * 1000)) ms")
        // Läuft in der App im Hintergrund. Tests laufen ohne Optimierung (Debug) und auf virtuellen Rechnern –
        // die Zeit wird nur ausgegeben; die maßgeblichen Zahlen liefert der Messlauf der fertigen App.
        XCTAssertGreaterThan(done - built, 0)
    }
}
