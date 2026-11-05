import XCTest
@testable import MLCore

/// Zeitmessung der v2-Funktionen mit 20.000 erzeugten Titeln. Keine harte Grenze (Debug-Builds und
/// CI-Rechner sind unterschiedlich schnell) – die Zeiten werden nur ausgegeben; geprüft werden
/// Plausibilität und Konsistenz der Ergebnisse.
final class V2PerformanceTests: XCTestCase {

    private static func library(count: Int) -> [Track] {
        var rng = SeededRandom(seed: 2026)
        let genres = ["Rock", "Pop", "Jazz", "Klassik", "Hip-Hop", "Electronic", "Soul", "Metal", "Folk", "Schlager",
                      "Blues", "Reggae", "Country", "Ambient", "Soundtrack", "Indie", "Punk", "Latin", "Dance", "Techno"]
        let codecs: [(String?, String)] = [("MP3", "mp3"), ("AAC", "m4a"), ("ALAC", "m4a"), ("FLAC", "flac"), ("PCM", "wav"),
                                           ("PCM", "aiff"), ("Vorbis", "ogg"), ("Opus", "opus"), (nil, "mp3")]
        let now: Int64 = 1_800_000_000
        return (0..<count).map { i in
            let artist = "Interpret \(Int.random(in: 0..<2_000, using: &rng))"
            let album = Int.random(in: 0..<1_500, using: &rng)
            let (codec, ext) = codecs[Int.random(in: 0..<codecs.count, using: &rng)]
            let feat = Int.random(in: 0..<20, using: &rng) == 0 ? " feat. Gast \(i % 50)" : ""
            return V2Tracks.make(
                Int64(i + 1), "Titel \(i)",
                artist: artist + feat,
                album: "Album \(album)",
                albumArtist: Int.random(in: 0..<4, using: &rng) == 0 ? artist : nil,
                genres: Int.random(in: 0..<10, using: &rng) == 0 ? [] : [genres[Int.random(in: 0..<genres.count, using: &rng)]],
                year: Int.random(in: 0..<8, using: &rng) == 0 ? nil : Int.random(in: 1950...2025, using: &rng),
                disc: Int.random(in: 0..<10, using: &rng) == 0 ? 2 : nil,
                number: Int.random(in: 1...16, using: &rng),
                rating: Int.random(in: 0..<3, using: &rng) == 0 ? nil : Int.random(in: 1...5, using: &rng) * 20,
                bpm: Int.random(in: 0..<2, using: &rng) == 0 ? nil : Int.random(in: 60...180, using: &rng),
                dateAdded: now - Int64(Int.random(in: 0..<(400 * 86_400), using: &rng)),
                codec: codec,
                fileName: "t\(i).\(ext)",
                folder: "Musik/\(album)/",
                hasPicture: Int.random(in: 0..<5, using: &rng) != 0,
                hasLyrics: Int.random(in: 0..<3, using: &rng) == 0
            )
        }
    }

    private func measure<R>(_ label: String, _ body: () -> R) -> R {
        let start = Date()
        let result = body()
        print(String(format: "[v2-perf] %@: %.1f ms", label, Date().timeIntervalSince(start) * 1_000))
        return result
    }

    func testZeiten_mit20000Titeln() {
        let tracks = Self.library(count: 20_000)
        let index = measure("LibraryIndex.build (Vergleich)") { LibraryIndex.build(tracks) }
        let facets = measure("facets") { LibraryFiltering.facets(tracks) }
        XCTAssertEqual(facets.artists.count, LibraryFiltering.maxArtistFacets)
        XCTAssertEqual(facets.formats.reduce(0) { $0 + $1.count }, tracks.count)
        XCTAssertEqual(facets.genres.reduce(0) { $0 + $1.count }, tracks.count) // ein Genre je Titel oder unbekannt

        var stats: [Int64: PlayStats] = [:]
        for t in tracks where t.uid % 3 == 0 { stats[t.uid] = PlayStats(trackUid: t.uid, playCount: Int(t.uid % 7), lastPlayedAt: t.uid * 1_000) }
        let ctx = FilterContext(favorites: Set(tracks.filter { $0.uid % 11 == 0 }.map(\.uid)), stats: stats, nowSeconds: 1_800_000_000)

        var f = LibraryFilter()
        f.genres = Set(facets.genres.prefix(5).map(\.id))
        f.decades = [1970, 1980, 1990]
        f.quick = [.lossless, .highRating]
        let filtered = measure("filter (Genres + Jahrzehnte + 2 Schnellfilter)") { LibraryFiltering.tracks(tracks, f, ctx) }
        XCTAssertFalse(filtered.isEmpty)
        XCTAssertTrue(filtered.allSatisfy { LibraryFiltering.matches($0, f, ctx) })

        var byArtist = LibraryFilter()
        byArtist.artists = Set(facets.artists.prefix(20).map(\.id))
        byArtist.formats = ["FLAC", "MP3"]
        let artistHits = measure("filter (Interpreten + Formate)") { LibraryFiltering.tracks(tracks, byArtist, ctx) }
        XCTAssertFalse(artistHits.isEmpty)

        var all = LibraryFilter()
        all.quick = Set(QuickFilter.allCases)
        _ = measure("filter (alle Schnellfilter)") { LibraryFiltering.tracks(tracks, all, ctx) }

        let albums = measure("filter Alben") { LibraryFiltering.albums(index.albums, f, index: index, ctx) }
        XCTAssertLessThanOrEqual(albums.count, index.albums.count)
        _ = measure("filter Interpreten") { LibraryFiltering.artists(index.artists, f, index: index, ctx) }
        _ = measure("filter Genres") { LibraryFiltering.genres(index.genres, f, index: index, ctx) }

        for field: TrackSort in [.title, .album, .albumArtist, .dateAdded, .rating, .bpm] {
            let sorted = measure("Sortierung Titel \(field.rawValue)") { Sorting.tracks(tracks, sort: Sort(field, descending: true), stats: stats) }
            XCTAssertEqual(sorted.count, tracks.count)
        }
        for field: AlbumSort in [.dateAdded, .trackCount] {
            _ = measure("Sortierung Alben \(field.rawValue)") { Sorting.albums(index.albums, sort: Sort(field), stats: stats) }
        }
        _ = measure("Sortierung Interpreten ALBUM_COUNT") { Sorting.artists(index.artists, sort: Sort(ArtistSort.albumCount)) }

        let genreLists = measure("SmartPlaylists.byGenre") { SmartPlaylists.byGenre(tracks) }
        XCTAssertEqual(genreLists.count, 12)
        _ = measure("SmartPlaylists.recentlyAdded") { SmartPlaylists.recentlyAdded(tracks) }
        _ = measure("SmartPlaylists.recentlyPlayed") { SmartPlaylists.recentlyPlayed(tracks, stats: stats) }
        _ = measure("SmartPlaylists.neverPlayed") { SmartPlaylists.neverPlayed(tracks, stats: stats) }
        _ = measure("SmartPlaylists.topRated") { SmartPlaylists.topRated(tracks) }
    }
}
