import Foundation

/// Wiedergabestatistik eines Titels (nur tatsächlich gezählte Wiedergaben, siehe `PlayCountRule`).
public struct PlayStats: Hashable, Sendable {
    public var trackUid: Int64
    public var playCount: Int
    /// Zeitpunkt der letzten gezählten Wiedergabe (Millisekunden seit 1970); `nil` = nie.
    public var lastPlayedAt: Int64?
    public var firstPlayedAt: Int64?
    public var totalListenedMs: Int64

    public init(trackUid: Int64, playCount: Int, lastPlayedAt: Int64?, firstPlayedAt: Int64? = nil, totalListenedMs: Int64 = 0) {
        self.trackUid = trackUid
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
        self.firstPlayedAt = firstPlayedAt
        self.totalListenedMs = totalListenedMs
    }
}

/// Eine selbst angelegte Playlist (Titel in fester, selbst gewählter Reihenfolge).
public struct Playlist: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var name: String
    public var createdAt: Int64
    public var updatedAt: Int64
    /// Titel in Playlist-Reihenfolge (auch derzeit nicht verfügbare).
    public var entries: [PlaylistEntry]

    public init(id: Int64, name: String, createdAt: Int64, updatedAt: Int64, entries: [PlaylistEntry]) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.entries = entries
    }
}

public struct PlaylistEntry: Identifiable, Hashable, Sendable {
    /// Eigene Kennung des Eintrags (ein Titel darf mehrfach in einer Playlist stehen).
    public var entryId: Int64
    public var trackUid: Int64
    public var position: Int
    public var addedAt: Int64
    public var id: Int64 { entryId }

    public init(entryId: Int64, trackUid: Int64, position: Int, addedAt: Int64) {
        self.entryId = entryId
        self.trackUid = trackUid
        self.position = position
        self.addedAt = addedAt
    }
}

/// Favorisierter Titel.
public struct FavoriteTrack: Hashable, Sendable {
    public var trackUid: Int64
    public var addedAt: Int64
    public init(trackUid: Int64, addedAt: Int64) {
        self.trackUid = trackUid
        self.addedAt = addedAt
    }
}

/// Favorisiertes Album (unabhängig von Titel-Favoriten). Titel/Interpret als Merkhilfe gespeichert.
public struct FavoriteAlbum: Hashable, Sendable {
    public var albumKey: String
    public var title: String?
    public var artist: String?
    public var addedAt: Int64
    public init(albumKey: String, title: String?, artist: String?, addedAt: Int64) {
        self.albumKey = albumKey
        self.title = title
        self.artist = artist
        self.addedAt = addedAt
    }
}

/// Ein Eintrag im Wiedergabeverlauf (neu gegenüber Android).
public struct HistoryEntry: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var trackUid: Int64
    /// Beginn der Wiedergabe (Millisekunden seit 1970).
    public var playedAt: Int64
    /// Tatsächlich gehörte Zeit in Millisekunden.
    public var listenedMs: Int64
    /// Als Wiedergabe gezählt (siehe `PlayCountRule`)?
    public var counted: Bool

    public init(id: Int64, trackUid: Int64, playedAt: Int64, listenedMs: Int64, counted: Bool) {
        self.id = id
        self.trackUid = trackUid
        self.playedAt = playedAt
        self.listenedMs = listenedMs
        self.counted = counted
    }
}

/// Gespeicherte Wiedergabeposition eines Titels (neu gegenüber Android).
public struct ResumePoint: Hashable, Sendable {
    public var trackUid: Int64
    public var positionMs: Int64
    public var updatedAt: Int64
    public init(trackUid: Int64, positionMs: Int64, updatedAt: Int64) {
        self.trackUid = trackUid
        self.positionMs = positionMs
        self.updatedAt = updatedAt
    }
}
