import Foundation

/// Vollständiger, im Hintergrund berechneter Überblick über die Bibliothek: Titel, Alben,
/// Interpreten, Genres und Suchtexte (Portierung von `library/LibraryIndex.kt`). Wird bei jeder
/// Änderung der Titelliste neu berechnet.
public struct LibraryIndex: Sendable {
    public let tracks: [Track]
    public let albums: [AlbumInfo]
    public let artists: [ArtistInfo]
    public let genres: [GenreInfo]
    public let albumKeyByTrack: [Int64: String]

    public let trackByUid: [Int64: Track]
    public let albumByKey: [String: AlbumInfo]
    public let artistByKey: [String: ArtistInfo]
    public let genreByKey: [String: GenreInfo]

    /// Normalisierte Suchtexte je Titel: Titel, Interpreten, Album, Genres.
    public let trackSearchText: [Int64: String]
    /// Normalisierte Suchtexte je Album: Albumtitel, Album-Interpret, Interpreten der Titel, Genres.
    public let albumSearchText: [String: String]

    /// Trennzeichen zwischen den Feldern eines Suchtexts (verhindert Treffer über Feldgrenzen hinweg).
    static let fieldSeparator = " \u{0001} "

    private init(tracks: [Track], albums: [AlbumInfo], artists: [ArtistInfo], genres: [GenreInfo], albumKeyByTrack: [Int64: String]) {
        self.tracks = tracks
        self.albums = albums
        self.artists = artists
        self.genres = genres
        self.albumKeyByTrack = albumKeyByTrack
        // Wie Kotlin `associateBy`: bei doppelten Schlüsseln gewinnt der letzte.
        let trackByUid = Dictionary(tracks.map { ($0.uid, $0) }, uniquingKeysWith: { _, last in last })
        self.trackByUid = trackByUid
        albumByKey = Dictionary(albums.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
        artistByKey = Dictionary(artists.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
        genreByKey = Dictionary(genres.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })

        var trackSearch: [Int64: String] = [:]
        trackSearch.reserveCapacity(tracks.count)
        for t in tracks {
            let fields = [t.displayTitle, t.artistText, t.albumArtistText, t.album, t.genreText].compactMap { $0 }
            trackSearch[t.uid] = TextNorm.key(fields.joined(separator: LibraryIndex.fieldSeparator))
        }
        trackSearchText = trackSearch

        var albumSearch: [String: String] = [:]
        albumSearch.reserveCapacity(albums.count)
        for a in albums {
            let members = a.trackUids.compactMap { trackByUid[$0] }
            let artistNames = members.flatMap(\.artists).distinctInOrder()
            let genreNames = members.flatMap(\.genres).distinctInOrder()
            let head = [a.title, a.artist, a.isVarious ? "Verschiedene Interpreten" : nil].compactMap { $0 }
            albumSearch[a.key] = TextNorm.key((head + artistNames + genreNames).joined(separator: LibraryIndex.fieldSeparator))
        }
        albumSearchText = albumSearch
    }

    public func tracksOf(_ uids: [Int64]) -> [Track] { uids.compactMap { trackByUid[$0] } }

    public func albumOf(_ trackUid: Int64) -> AlbumInfo? { albumKeyByTrack[trackUid].flatMap { albumByKey[$0] } }

    /// Titel, dessen Cover für das Album verwendet wird: der erste mit eingebettetem Bild, sonst der erste.
    public func coverTrackOf(_ album: AlbumInfo) -> Track? {
        let members = album.trackUids.compactMap { trackByUid[$0] }
        return members.first(where: \.hasPicture) ?? members.first
    }

    /// Titel, auf die alle Suchbegriffe zutreffen (Reihenfolge wie `tracks`).
    public func searchTracks(_ query: String) -> [Track] {
        let terms = TextNorm.searchTerms(query)
        if terms.isEmpty { return tracks }
        return tracks.filter { TextNorm.matchesAll(terms, trackSearchText[$0.uid] ?? "") }
    }

    public static let empty = LibraryIndex.build([])

    public static func build(_ tracks: [Track]) -> LibraryIndex {
        let grouping = AlbumGrouping.group(tracks)
        let artists = ArtistIndex.build(tracks, albumKeyByTrack: grouping.albumKeyByTrack)
        let genres = GenreIndex.build(tracks)
        return LibraryIndex(tracks: tracks, albums: grouping.albums, artists: artists, genres: genres, albumKeyByTrack: grouping.albumKeyByTrack)
    }
}
