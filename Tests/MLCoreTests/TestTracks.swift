import Foundation
@testable import MLCore

/// Kurzschreibweise für Testtitel (Portierung von `library/TestTracks.kt`).
enum TestTracks {
    /// Fortlaufende Kennungen (threadsicher, damit auch strikte Nebenläufigkeitsprüfung zufrieden ist).
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Int64 = 1
        func next() -> Int64 {
            lock.lock()
            defer { lock.unlock() }
            defer { value += 1 }
            return value
        }
    }
    private static let counter = Counter()

    static func track(
        _ title: String? = "Titel",
        _ artist: String? = nil,
        _ album: String? = nil,
        _ albumArtist: String? = nil,
        genre: String? = nil,
        year: Int? = nil,
        track: Int? = nil,
        disc: Int? = nil,
        folder: String = "Music/",
        fileName: String? = nil,
        compilation: Bool = false,
        durationMs: Int64 = 180_000,
        uid: Int64? = nil,
        artists: [String]? = nil,
        genres: [String]? = nil,
        dateAdded: Int64 = 0,
        titleSort: String? = nil,
        artistSort: String? = nil,
        sizeBytes: Int64 = 0,
        bitrate: Int = 0,
        codec: String? = nil,
        hasPicture: Bool = false,
        available: Bool = true
    ) -> Track {
        let id = uid ?? counter.next()
        let name = fileName ?? "\(title ?? "unbenannt").mp3"
        return Track(
            uid: id,
            folderID: 0,
            path: "/Volumes/Musik/\(folder)\(name)",
            relativePath: folder,
            fileName: name,
            title: title,
            artists: artists ?? [artist].compactMap { $0 },
            album: album,
            albumArtists: [albumArtist].compactMap { $0 },
            genres: genres ?? [genre].compactMap { $0 },
            year: year,
            trackNumber: track,
            discNumber: disc,
            compilation: compilation,
            durationMs: durationMs,
            sizeBytes: sizeBytes,
            dateAdded: dateAdded,
            codec: codec,
            bitrate: bitrate,
            titleSort: titleSort,
            artistSort: artistSort,
            hasPicture: hasPicture,
            available: available
        )
    }
}

extension Track {
    /// Kopie mit anderer Kennung (wie Kotlin `copy(uid = …)`).
    func with(uid: Int64) -> Track {
        var t = self
        t.uid = uid
        return t
    }
}
