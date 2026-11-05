import Foundation
import AppKit
import MLCore
import MLStore

/// Beispielbibliothek für Vorschaubilder (Snapshot-Modus). Alle Titel, Interpreten und Cover sind erfunden;
/// die Cover werden zur Laufzeit gezeichnet. Es werden keine Dateien des Benutzers berührt.
enum DemoLibrary {
    struct AlbumSpec {
        let title: String
        let artist: String
        let genre: String
        let year: Int
        let colors: (UInt32, UInt32)
        let tracks: [String]
    }

    static let albums: [AlbumSpec] = [
        AlbumSpec(title: "Nachtlichter", artist: "Lina Sommer", genre: "Pop", year: 2023, colors: (0xFFE8899E, 0xFF5B2A49),
                  tracks: ["Stadt aus Glas", "Rosé am Morgen", "Kometen", "Leise laut", "Ozean in mir", "Zurück zu dir", "Neonherz", "Sternstaub"]),
        AlbumSpec(title: "Low Tide Sessions", artist: "The Harbor Lights", genre: "Indie Rock", year: 2021, colors: (0xFF4F9592, 0xFF1C2E3A),
                  tracks: ["Salt & Silver", "Northbound", "Paper Boats", "Lighthouse Keeper", "Undertow", "Driftwood"]),
        AlbumSpec(title: "Midnight Blue", artist: "Ella Marquez Trio", genre: "Jazz", year: 2019, colors: (0xFF5E7DB0, 0xFF141B33),
                  tracks: ["Blue in Green Hours", "Velvet Rain", "Late Train", "Café Noir", "Moonlit Avenue"]),
        AlbumSpec(title: "Elektrische Felder", artist: "Kraftfeld", genre: "Electronic", year: 2022, colors: (0xFF8C5F9E, 0xFF0E0A1F),
                  tracks: ["Puls", "Frequenz", "Spannung", "Ladung", "Strom", "Feld", "Welle"]),
        AlbumSpec(title: "Sinfonie der Jahreszeiten", artist: "Kammerorchester Lindenau", genre: "Klassik", year: 2017, colors: (0xFFC99A45, 0xFF3A2614),
                  tracks: ["Frühling – Allegro", "Sommer – Adagio", "Herbst – Andante", "Winter – Presto"]),
        AlbumSpec(title: "Dust & Diesel", artist: "Hank Morrow", genre: "Country", year: 2016, colors: (0xFFD9765F, 0xFF3B1E14),
                  tracks: ["Highway 9", "Old Porch Song", "Whiskey Sunset", "Long Way Home", "Rust"]),
        AlbumSpec(title: "Fernweh", artist: "Clara Wendt", genre: "Singer-Songwriter", year: 2020, colors: (0xFF7E9F78, 0xFF1D2B1B),
                  tracks: ["Bahnhof", "Briefe", "Kiesweg", "Fernweh", "Haus am See"]),
        AlbumSpec(title: "Hypercolor", artist: "VELVET//MACHINE", genre: "Darkwave", year: 2024, colors: (0xFFB27390, 0xFF120B14),
                  tracks: ["Static Bloom", "Ghost Signal", "Chrome Hearts", "Afterglow"]),
        AlbumSpec(title: "Golden Hour Vol. 2", artist: "Verschiedene Interpreten", genre: "Soul", year: 1974, colors: (0xFFAA916E, 0xFF2B1E10),
                  tracks: ["Sunday Groove", "Sweet Thing", "Love Is Gold", "Funky Avenue", "Hold On"]),
        AlbumSpec(title: "Bergwelt", artist: "Die Alpenfreunde", genre: "Schlager", year: 1988, colors: (0xFFD4566F, 0xFF4A1020),
                  tracks: ["Gipfelglück", "Almrausch", "Edelweiß-Walzer"]),
    ]

    static let lyrics = """
    [ar:Lina Sommer]
    [ti:Stadt aus Glas]
    [00:08.20]Die Straßen glänzen nach dem Regen
    [00:13.60]wir laufen barfuß durch das Licht
    [00:19.10]in einer Stadt aus Glas und Träumen
    [00:24.40]zerbricht der Morgen, doch wir nicht
    [00:30.00]
    [00:31.80]Und wenn die Sterne leiser werden
    [00:37.20]singt die Stadt ein letztes Lied
    [00:42.60]wir tanzen auf den hellen Scherben
    [00:48.10]bis der Tag die Nacht verschiebt
    """

    /// Erzeugt Titel, Cover (PNG im temporären Ordner) und Benutzerdaten.
    static func make() -> (tracks: [Track], covers: [Int64: String], favorites: [Int64: Int64], favoriteAlbums: [String: FavoriteAlbum],
                           stats: [Int64: PlayStats], playlists: [Playlist], history: [HistoryEntry]) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MusicLibraryDemo-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var tracks: [Track] = []
        var covers: [Int64: String] = [:]
        var uid: Int64 = 1
        let now = Int64(Date().timeIntervalSince1970)
        for (ai, a) in albums.enumerated() {
            let coverPath = dir.appendingPathComponent("cover\(ai).png").path
            let hasCover = ai != 6 // ein Album ohne Cover (Genre-Ersatz)
            if hasCover { writeCover(a, index: ai, to: coverPath) }
            for (ti, title) in a.tracks.enumerated() {
                let various = a.artist == "Verschiedene Interpreten"
                let artist = various ? ["Marvin Day", "The Soulettes", "Ruby Shaw", "Otis Bell", "June Carter-Lee"][ti % 5] : a.artist
                let durationMs = Int64(150_000 + (ti * 37_000 + ai * 11_000) % 160_000)
                let kbps = ai % 3 == 0 ? 900 : 256
                let t = Track(
                    uid: uid, folderID: 1, path: "/Demo/\(a.artist)/\(a.title)/\(ti + 1) \(title).m4a",
                    relativePath: "\(a.artist)/\(a.title)/", fileName: "\(ti + 1) \(title).m4a",
                    title: title, artists: [artist], album: a.title, albumArtists: [a.artist], genres: [a.genre],
                    composers: ai == 4 ? ["Antonia Lind"] : [], year: a.year, trackNumber: ti + 1, trackTotal: a.tracks.count,
                    discNumber: 1, discTotal: 1, compilation: various, bpm: 90 + (ti * 7) % 60, rating: (ti % 6) * 20 == 0 ? nil : (ti % 6) * 20,
                    durationMs: durationMs, sizeBytes: durationMs * Int64(kbps) / 8 + 48_000 + Int64(uid * 97), dateModified: now - Int64(ai * 86_400),
                    dateAdded: now - Int64(ai * 86_400 * 3 + ti * 600), codec: ai % 3 == 0 ? "ALAC" : "AAC", sampleRate: 44_100, bitrate: kbps,
                    channels: 2, bitsPerSample: ai % 3 == 0 ? 16 : 0, hasPicture: hasCover, hasLyrics: ai == 0 && ti == 0, available: true
                )
                tracks.append(t)
                if hasCover { covers[uid] = coverPath }
                uid += 1
            }
        }
        // Ein echtes Duplikat für die Duplikat-Ansicht: derselbe Titel noch einmal in einem zweiten Ordner
        if let original = tracks.first(where: { $0.uid == 2 }) {
            var copy = original
            copy.uid = uid
            copy.path = "/Demo/Import/\(original.fileName)"
            copy.relativePath = "Import/"
            copy.dateAdded = now - 3_600
            tracks.append(copy)
            if let c = covers[original.uid] { covers[uid] = c }
            uid += 1
        }
        var favorites: [Int64: Int64] = [:]
        for u in [1, 3, 9, 12, 17, 25, 31, 40] where u < uid { favorites[Int64(u)] = (now - Int64(u) * 3600) * 1000 }
        var favAlbums: [String: FavoriteAlbum] = [:]
        let idx = LibraryIndex.build(tracks)
        for a in idx.albums.prefix(3) {
            favAlbums[a.key] = FavoriteAlbum(albumKey: a.key, title: a.title, artist: a.artist, addedAt: now * 1000)
        }
        var stats: [Int64: PlayStats] = [:]
        for t in tracks where t.uid % 3 != 0 {
            stats[t.uid] = PlayStats(trackUid: t.uid, playCount: Int((t.uid * 7) % 23) + 1, lastPlayedAt: (now - t.uid * 5000) * 1000, firstPlayedAt: (now - 2_000_000) * 1000, totalListenedMs: 600_000)
        }
        let playlists = [
            Playlist(id: 1, name: "Sonntagmorgen", createdAt: now * 1000, updatedAt: now * 1000,
                     entries: [3, 14, 20, 27, 33, 46, 9, 1].enumerated().map { PlaylistEntry(entryId: Int64($0.offset + 1), trackUid: Int64($0.element), position: $0.offset, addedAt: now * 1000) }),
            Playlist(id: 2, name: "Laufen", createdAt: now * 1000, updatedAt: now * 1000,
                     entries: [15, 16, 17, 18, 19, 20, 21, 41, 42].enumerated().map { PlaylistEntry(entryId: Int64($0.offset + 20), trackUid: Int64($0.element), position: $0.offset, addedAt: now * 1000) }),
            Playlist(id: 3, name: "Abendessen mit Freunden", createdAt: now * 1000, updatedAt: now * 1000,
                     entries: [10, 11, 12, 13, 44, 45, 46].enumerated().map { PlaylistEntry(entryId: Int64($0.offset + 40), trackUid: Int64($0.element), position: $0.offset, addedAt: now * 1000) }),
        ]
        var history: [HistoryEntry] = []
        for i in 0..<18 {
            let u = Int64((i * 5) % tracks.count + 1)
            history.append(HistoryEntry(id: Int64(i + 1), trackUid: u, playedAt: (now - Int64(i) * 2_400) * 1000, listenedMs: Int64(60_000 + i * 9_000), counted: i % 4 != 3))
        }
        return (tracks, covers, favorites, favAlbums, stats, playlists, history)
    }

    /// Zeichnet ein abstraktes Cover (Verlauf, Kreise, Linien) – reine Geometrie, keine fremden Bilder.
    static func writeCover(_ a: AlbumSpec, index: Int, to path: String) {
        let size = 900
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        let c1 = NSColor(argb: a.colors.0).cgColor, c2 = NSColor(argb: a.colors.1).cgColor
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [c1, c2] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: CGFloat(size), y: 0), options: [])
        let s = CGFloat(size)
        switch index % 5 {
        case 0:
            for i in 0..<6 {
                ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.12 + 0.05 * CGFloat(i)).cgColor)
                ctx.setLineWidth(10)
                let r = s * (0.12 + 0.07 * CGFloat(i))
                ctx.strokeEllipse(in: CGRect(x: s * 0.62 - r, y: s * 0.4 - r, width: 2 * r, height: 2 * r))
            }
        case 1:
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
            ctx.fillEllipse(in: CGRect(x: s * 0.58, y: s * 0.58, width: s * 0.22, height: s * 0.22))
            for i in 0..<12 {
                ctx.setFillColor(NSColor.white.withAlphaComponent(0.06 + 0.02 * CGFloat(i % 4)).cgColor)
                ctx.fill(CGRect(x: 0, y: s * (0.08 + 0.035 * CGFloat(i)), width: s, height: s * 0.012))
            }
        case 2:
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.25).cgColor)
            ctx.fillEllipse(in: CGRect(x: s * 0.15, y: s * 0.15, width: s * 0.7, height: s * 0.7))
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
            ctx.fillEllipse(in: CGRect(x: s * 0.44, y: s * 0.44, width: s * 0.12, height: s * 0.12))
        case 3:
            for i in 0..<9 {
                ctx.setFillColor(NSColor.white.withAlphaComponent(0.08 * CGFloat(i % 3 + 1)).cgColor)
                ctx.saveGState()
                ctx.translateBy(x: s / 2, y: s / 2)
                ctx.rotate(by: CGFloat(i) * .pi / 9)
                ctx.fill(CGRect(x: -s * 0.02, y: -s * 0.45, width: s * 0.04, height: s * 0.9))
                ctx.restoreGState()
            }
        default:
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.18).cgColor)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: s * 0.25))
            path.addLine(to: CGPoint(x: s * 0.35, y: s * 0.62))
            path.addLine(to: CGPoint(x: s * 0.55, y: s * 0.42))
            path.addLine(to: CGPoint(x: s, y: s * 0.78))
            path.addLine(to: CGPoint(x: s, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.fillPath()
        }
        guard let image = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
