import Foundation
import MLCore

/// Ein vom Benutzer gewählter Musikordner.
public struct LibraryFolder: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var path: String
    /// Security-Scoped-Bookmark (macOS), damit der Zugriff nach Neustart erhalten bleibt.
    public var bookmark: Data?
    public var name: String
    public var addedAt: Int64
    public var lastScanAt: Int64?
    public var volumeName: String?
    public var isExternal: Bool
    public var enabled: Bool

    public init(id: Int64, path: String, bookmark: Data?, name: String, addedAt: Int64, lastScanAt: Int64?, volumeName: String?, isExternal: Bool, enabled: Bool) {
        self.id = id
        self.path = path
        self.bookmark = bookmark
        self.name = name
        self.addedAt = addedAt
        self.lastScanAt = lastScanAt
        self.volumeName = volumeName
        self.isExternal = isExternal
        self.enabled = enabled
    }
}

/// Ergebnis des Einlesens einer Datei (für Einfügen/Aktualisieren).
public struct TrackRecord: Sendable {
    public var folderID: Int64
    public var path: String
    public var relativePath: String
    public var fileName: String
    /// Dateikennung (Inode) zum Wiedererkennen verschobener Dateien; 0 = unbekannt.
    public var fileID: Int64
    public var sizeBytes: Int64
    public var dateModified: Int64
    /// `nil` = Tags nicht lesbar (Titel wird dann aus dem Dateinamen angezeigt).
    public var tags: TagValues?
    public var audio: AudioProperties
    public var hasLyrics: Bool
    public var metaVersion: Int

    public init(folderID: Int64, path: String, relativePath: String, fileName: String, fileID: Int64, sizeBytes: Int64, dateModified: Int64, tags: TagValues?, audio: AudioProperties, hasLyrics: Bool, metaVersion: Int) {
        self.folderID = folderID
        self.path = path
        self.relativePath = relativePath
        self.fileName = fileName
        self.fileID = fileID
        self.sizeBytes = sizeBytes
        self.dateModified = dateModified
        self.tags = tags
        self.audio = audio
        self.hasLyrics = hasLyrics
        self.metaVersion = metaVersion
    }
}

/// Zugriff auf die Bibliotheksdatenbank. Alle Zugriffe laufen nacheinander über eine eigene Warteschlange,
/// daher darf die Klasse von beliebigen Threads benutzt werden.
public final class LibraryStore: @unchecked Sendable {
    private let db: SQLiteConnection
    private let queue = DispatchQueue(label: "de.privateapp.musiclibrary.store", qos: .userInitiated)
    public let path: String

    public init(path: String) throws {
        self.path = path
        db = try SQLiteConnection(path: path)
        try Schema.migrate(db)
    }

    /// Datenbank im Arbeitsspeicher (Tests, Vorschau).
    public static func inMemory() throws -> LibraryStore { try LibraryStore(path: ":memory:") }

    private func sync<T>(_ body: (SQLiteConnection) throws -> T) throws -> T {
        try queue.sync { try body(db) }
    }

    private static func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    // MARK: - Ordner

    public func folders() throws -> [LibraryFolder] {
        try sync { db in
            try db.query("SELECT id, path, bookmark, name, addedAt, lastScanAt, volumeName, isExternal, enabled FROM folders ORDER BY name COLLATE NOCASE, id") { r in
                LibraryFolder(id: r.int64(0), path: r.string(1), bookmark: r.data(2), name: r.string(3), addedAt: r.int64(4), lastScanAt: r.optInt64(5), volumeName: r.optString(6), isExternal: r.bool(7), enabled: r.bool(8))
            }
        }
    }

    /// Fügt einen Musikordner hinzu (oder aktualisiert das Bookmark, wenn er schon bekannt ist).
    @discardableResult
    public func addFolder(path: String, bookmark: Data?, name: String, volumeName: String?, isExternal: Bool) throws -> LibraryFolder {
        try sync { db in
            let now = Self.now()
            if let existing = try db.queryOne("SELECT id FROM folders WHERE path = ?", [.text(path)], { $0.int64(0) }) {
                try db.run("UPDATE folders SET bookmark = ?, name = ?, volumeName = ?, isExternal = ?, enabled = 1 WHERE id = ?",
                           [SQLValue(bookmark), .text(name), SQLValue(volumeName), SQLValue(isExternal), .int(existing)])
                return LibraryFolder(id: existing, path: path, bookmark: bookmark, name: name, addedAt: now, lastScanAt: nil, volumeName: volumeName, isExternal: isExternal, enabled: true)
            }
            try db.run("INSERT INTO folders (path, bookmark, name, addedAt, volumeName, isExternal) VALUES (?, ?, ?, ?, ?, ?)",
                       [.text(path), SQLValue(bookmark), .text(name), .int(now), SQLValue(volumeName), SQLValue(isExternal)])
            return LibraryFolder(id: db.lastInsertRowID, path: path, bookmark: bookmark, name: name, addedAt: now, lastScanAt: nil, volumeName: volumeName, isExternal: isExternal, enabled: true)
        }
    }

    public func updateFolderBookmark(id: Int64, bookmark: Data?) throws {
        try sync { db in _ = try db.run("UPDATE folders SET bookmark = ? WHERE id = ?", [SQLValue(bookmark), .int(id)]) }
    }

    public func setFolderEnabled(id: Int64, enabled: Bool) throws {
        try sync { db in _ = try db.run("UPDATE folders SET enabled = ? WHERE id = ?", [SQLValue(enabled), .int(id)]) }
    }

    public func setFolderScanned(id: Int64, at time: Int64) throws {
        try sync { db in _ = try db.run("UPDATE folders SET lastScanAt = ? WHERE id = ?", [.int(time), .int(id)]) }
    }

    /// Entfernt einen Musikordner. Die Dateien selbst bleiben unberührt.
    /// - Parameter deleteTracks: Titel des Ordners samt Favoriten/Playlist-Einträgen/Statistik aus der Bibliothek entfernen.
    public func removeFolder(id: Int64, deleteTracks: Bool) throws {
        try sync { db in
            try db.transaction {
                if deleteTracks {
                    try db.run("DELETE FROM tracks WHERE folderId = ?", [.int(id)])
                } else {
                    try db.run("UPDATE tracks SET available = 0, missingSince = COALESCE(missingSince, ?) WHERE folderId = ?", [.int(Self.now()), .int(id)])
                }
                try db.run("DELETE FROM folders WHERE id = ?", [.int(id)])
            }
        }
    }

    // MARK: - Titel

    private static let trackColumns = """
    uid, folderId, path, relativePath, fileName, title, artists, album, albumArtists, genres, composers, grouping, \
    year, trackNumber, trackTotal, discNumber, discTotal, compilation, bpm, rating, comment, durationMs, sizeBytes, \
    dateModified, dateAdded, codec, sampleRate, bitrate, channels, bitsPerSample, titleSort, artistSort, albumSort, \
    albumArtistSort, composerSort, hasPicture, hasLyrics, available, dateAddedSource
    """

    private static func track(_ r: SQLRow) -> Track {
        Track(
            uid: r.int64(0), folderID: r.int64(1), path: r.string(2), relativePath: r.string(3), fileName: r.string(4),
            title: r.optString(5), artists: ListCodec.decode(r.optString(6)), album: r.optString(7),
            albumArtists: ListCodec.decode(r.optString(8)), genres: ListCodec.decode(r.optString(9)),
            composers: ListCodec.decode(r.optString(10)), grouping: r.optString(11), year: r.optInt(12),
            trackNumber: r.optInt(13), trackTotal: r.optInt(14), discNumber: r.optInt(15), discTotal: r.optInt(16),
            compilation: r.bool(17), bpm: r.optInt(18), rating: r.optInt(19), comment: r.optString(20),
            durationMs: r.int64(21), sizeBytes: r.int64(22), dateModified: r.int64(23), dateAdded: r.int64(24),
            codec: r.optString(25), sampleRate: r.int(26), bitrate: r.int(27), channels: r.int(28), bitsPerSample: r.int(29),
            titleSort: r.optString(30), artistSort: r.optString(31), albumSort: r.optString(32),
            albumArtistSort: r.optString(33), composerSort: r.optString(34), hasPicture: r.bool(35),
            hasLyrics: r.bool(36), available: r.bool(37)
        )
        .withDateAddedSource(DateAddedSource(rawValue: r.int(38)) ?? .unknown)
    }

    /// Alle sichtbaren Titel (auch nicht verfügbare – die App blendet sie je nach Ansicht aus).
    public func allTracks(includeHidden: Bool = false) throws -> [Track] {
        try sync { db in
            try db.query("SELECT \(Self.trackColumns) FROM tracks" + (includeHidden ? "" : " WHERE hidden = 0"), [], Self.track)
        }
    }

    public func track(uid: Int64) throws -> Track? {
        try sync { db in try db.queryOne("SELECT \(Self.trackColumns) FROM tracks WHERE uid = ?", [.int(uid)], Self.track) }
    }

    public func tracks(uids: [Int64]) throws -> [Track] {
        guard !uids.isEmpty else { return [] }
        return try sync { db in
            var result: [Int64: Track] = [:]
            for chunk in uids.chunked(500) {
                let marks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                for t in try db.query("SELECT \(Self.trackColumns) FROM tracks WHERE uid IN (\(marks))", chunk.map { .int($0) }, Self.track) {
                    result[t.uid] = t
                }
            }
            return uids.compactMap { result[$0] }
        }
    }

    /// Bekannte Titel für den Abgleich beim Einlesen (`SyncPlanner`).
    public func knownFiles(folderID: Int64? = nil) throws -> [KnownFile] {
        try sync { db in
            let sql = "SELECT uid, folderId, path, sizeBytes, dateModified, fileID, available, metaVersion FROM tracks"
                + (folderID != nil ? " WHERE folderId = ?" : "")
            return try db.query(sql, folderID.map { [.int($0)] } ?? []) { r in
                KnownFile(uid: r.int64(0), folderID: r.int64(1), path: r.string(2), sizeBytes: r.int64(3), dateModified: r.int64(4),
                          fileID: r.int64(5) == 0 ? nil : UInt64(bitPattern: r.int64(5)), volumeID: nil, available: r.bool(6), metaVersion: r.int(7))
            }
        }
    }

    private static func tagValues(_ s: TrackRecord) -> [SQLValue] {
        let t = s.tags
        return [
            .text(s.path), .text(s.relativePath), .text(s.fileName), .int(s.fileID), .int(s.sizeBytes), .int(s.dateModified),
            .int(s.audio.durationMs), SQLValue(s.audio.codec.isEmpty ? nil : s.audio.codec), .int(Int64(s.audio.sampleRate)),
            .int(Int64(s.audio.bitrate)), .int(Int64(s.audio.channels)), .int(Int64(s.audio.bitsPerSample)),
            SQLValue(t?.title), SQLValue(ListCodec.encode(t?.artists ?? [])), SQLValue(t?.album),
            SQLValue(ListCodec.encode(t?.albumArtists ?? [])), SQLValue(ListCodec.encode(t?.genres ?? [])),
            SQLValue(ListCodec.encode(t?.composers ?? [])), SQLValue(t?.grouping), SQLValue(t?.year),
            SQLValue(t?.trackNumber), SQLValue(t?.trackTotal), SQLValue(t?.discNumber), SQLValue(t?.discTotal),
            SQLValue(t?.compilation ?? false), SQLValue(t?.bpm), SQLValue(t?.rating), SQLValue(t?.comment),
            SQLValue(t?.titleSort), SQLValue(t?.artistSort), SQLValue(t?.albumSort), SQLValue(t?.albumArtistSort),
            SQLValue(t?.composerSort), SQLValue(!(t?.pictures.isEmpty ?? true)), SQLValue(s.hasLyrics || (t?.lyrics != nil)),
            .int(Int64(s.metaVersion)), .int(now()),
        ]
    }

    private static let tagColumnList = """
    path, relativePath, fileName, fileID, sizeBytes, dateModified, durationMs, codec, sampleRate, bitrate, channels, \
    bitsPerSample, title, artists, album, albumArtists, genres, composers, grouping, year, trackNumber, trackTotal, \
    discNumber, discTotal, compilation, bpm, rating, comment, titleSort, artistSort, albumSort, albumArtistSort, \
    composerSort, hasPicture, hasLyrics, metaVersion, metaReadAt
    """

    /// Neuer Titel. Gibt die neue `uid` zurück.
    @discardableResult
    public func insertTrack(_ s: TrackRecord, dateAdded: Int64, source: DateAddedSource = .firstImport) throws -> Int64 {
        try sync { db in try Self.insert(db, s, dateAdded: dateAdded, source: source) }
    }

    private static func insert(_ db: SQLiteConnection, _ s: TrackRecord, dateAdded: Int64, source: DateAddedSource = .firstImport) throws -> Int64 {
        let cols = tagColumnList + ", folderId, dateAdded, available, dateAddedSource"
        let values = tagValues(s) + [.int(s.folderID), .int(dateAdded), .int(1), .int(Int64(source.rawValue))]
        let marks = Array(repeating: "?", count: values.count).joined(separator: ",")
        try db.run("INSERT INTO tracks (\(cols)) VALUES (\(marks))", values)
        return db.lastInsertRowID
    }

    /// Titel neu eingelesen (Datei geändert, verschoben oder wieder aufgetaucht). `uid` bleibt erhalten.
    public func updateTrack(uid: Int64, _ s: TrackRecord) throws {
        try sync { db in try Self.update(db, uid: uid, s) }
    }

    private static func update(_ db: SQLiteConnection, uid: Int64, _ s: TrackRecord) throws {
        let assignments = tagColumnList.split(separator: ",").map { "\($0.trimmingCharacters(in: .whitespaces)) = ?" }.joined(separator: ", ")
        try db.run("UPDATE tracks SET \(assignments), folderId = ?, available = 1, missingSince = NULL WHERE uid = ?",
                   tagValues(s) + [.int(s.folderID), .int(uid)])
    }

    /// Ergebnis eines Einlesevorgangs in einer Transaktion übernehmen.
    public func applyScan(inserts: [TrackRecord], updates: [(uid: Int64, file: TrackRecord)], missing: [Int64], dateAdded: Int64) throws -> [Int64] {
        try applyScan(inserts: inserts, addedDates: inserts.map { _ in (dateAdded, .firstImport) }, updates: updates, missing: missing)
    }

    /// Wie oben, aber mit eigenem Hinzufügedatum je neuem Titel (v2.1). Bestehende Titel behalten ihr Datum –
    /// ein erneutes Einlesen überschreibt `dateAdded` nie.
    public func applyScan(inserts: [TrackRecord], addedDates: [(Int64, DateAddedSource)], updates: [(uid: Int64, file: TrackRecord)], missing: [Int64]) throws -> [Int64] {
        precondition(addedDates.count == inserts.count)
        return try sync { db in
            try db.transaction {
                var newUids: [Int64] = []
                for (i, s) in inserts.enumerated() {
                    newUids.append(try Self.insert(db, s, dateAdded: addedDates[i].0, source: addedDates[i].1))
                }
                for u in updates { try Self.update(db, uid: u.uid, u.file) }
                let now = Self.now()
                for uid in missing {
                    try db.run("UPDATE tracks SET available = 0, missingSince = COALESCE(missingSince, ?) WHERE uid = ?", [.int(now), .int(uid)])
                }
                return newUids
            }
        }
    }

    // MARK: - Hinzufügedatum (v2.1)

    /// Stand des Hinzufügedatums aller Titel (auch ausgeblendeter) für die Rekonstruktion.
    public struct DateAddedRow: Hashable, Sendable {
        public let uid: Int64
        public let path: String
        public let dateAdded: Int64
        public let source: DateAddedSource
        public let available: Bool
        public let title: String?
        public let artist: String?
        public let album: String?
        public let durationMs: Int64
        public let sizeBytes: Int64
    }

    public func dateAddedRows() throws -> [DateAddedRow] {
        try sync { db in
            try db.query("SELECT uid, path, dateAdded, dateAddedSource, available, title, artists, album, durationMs, sizeBytes FROM tracks") { r in
                DateAddedRow(uid: r.int64(0), path: r.string(1), dateAdded: r.int64(2), source: DateAddedSource(rawValue: r.int(3)) ?? .unknown,
                             available: r.bool(4), title: r.optString(5), artist: ListCodec.decode(r.optString(6)).first, album: r.optString(7),
                             durationMs: r.int64(8), sizeBytes: r.int64(9))
            }
        }
    }

    /// Hinzufügedaten setzen (eine Transaktion).
    public func setDateAdded(_ changes: [(uid: Int64, date: Int64, source: DateAddedSource)]) throws {
        guard !changes.isEmpty else { return }
        try sync { db in
            try db.transaction {
                for c in changes {
                    try db.run("UPDATE tracks SET dateAdded = ?, dateAddedSource = ? WHERE uid = ?", [.int(c.date), .int(Int64(c.source.rawValue)), .int(c.uid)])
                }
            }
        }
    }

    /// Kleiner Schlüssel-Wert-Speicher für einmalige Aufgaben (z. B. „Hinzufügedaten rekonstruiert“).
    public func meta(_ key: String) throws -> String? {
        try sync { db in try db.queryOne("SELECT value FROM app_meta WHERE key = ?", [.text(key)]) { $0.string(0) } }
    }

    public func setMeta(_ key: String, _ value: String) throws {
        try sync { db in _ = try db.run("INSERT OR REPLACE INTO app_meta (key, value) VALUES (?, ?)", [.text(key), .text(value)]) }
    }

    /// Nur Dateiangaben aktualisieren (verschoben/umbenannt, Tags unverändert).
    public func updateFileLocation(uid: Int64, folderID: Int64, path: String, relativePath: String, fileName: String, fileID: Int64, sizeBytes: Int64, dateModified: Int64) throws {
        try sync { db in
            _ = try db.run("UPDATE tracks SET folderId = ?, path = ?, relativePath = ?, fileName = ?, fileID = ?, sizeBytes = ?, dateModified = ?, available = 1, missingSince = NULL WHERE uid = ?",
                           [.int(folderID), .text(path), .text(relativePath), .text(fileName), .int(fileID), .int(sizeBytes), .int(dateModified), .int(uid)])
        }
    }

    /// Nach dem Schreiben von Tags: neue Werte und Dateiangaben übernehmen.
    public func updateTags(uid: Int64, values t: TagValues, sizeBytes: Int64, dateModified: Int64, hasLyrics: Bool? = nil) throws {
        try sync { db in
            _ = try db.run("""
            UPDATE tracks SET title = ?, artists = ?, album = ?, albumArtists = ?, genres = ?, composers = ?, grouping = ?, \
            year = ?, trackNumber = ?, trackTotal = ?, discNumber = ?, discTotal = ?, compilation = ?, bpm = ?, rating = ?, \
            comment = ?, titleSort = ?, artistSort = ?, albumSort = ?, albumArtistSort = ?, composerSort = ?, hasPicture = ?, \
            hasLyrics = COALESCE(?, hasLyrics), sizeBytes = ?, dateModified = ?, metaReadAt = ? WHERE uid = ?
            """, [
                SQLValue(t.title), SQLValue(ListCodec.encode(t.artists)), SQLValue(t.album), SQLValue(ListCodec.encode(t.albumArtists)),
                SQLValue(ListCodec.encode(t.genres)), SQLValue(ListCodec.encode(t.composers)), SQLValue(t.grouping), SQLValue(t.year),
                SQLValue(t.trackNumber), SQLValue(t.trackTotal), SQLValue(t.discNumber), SQLValue(t.discTotal), SQLValue(t.compilation),
                SQLValue(t.bpm), SQLValue(t.rating), SQLValue(t.comment), SQLValue(t.titleSort), SQLValue(t.artistSort),
                SQLValue(t.albumSort), SQLValue(t.albumArtistSort), SQLValue(t.composerSort), SQLValue(!t.pictures.isEmpty),
                hasLyrics.map { SQLValue($0) } ?? .null, .int(sizeBytes), .int(dateModified), .int(Self.now()), .int(uid),
            ])
        }
    }

    /// Bewertung nur in der Bibliothek setzen (z. B. wenn das Format keine Bewertung speichern kann).
    public func setRating(uid: Int64, rating: Int?) throws {
        try sync { db in _ = try db.run("UPDATE tracks SET rating = ? WHERE uid = ?", [SQLValue(rating), .int(uid)]) }
    }

    public func setAvailability(uids: [Int64], available: Bool) throws {
        try sync { db in
            try db.transaction {
                let now = Self.now()
                for uid in uids {
                    if available {
                        try db.run("UPDATE tracks SET available = 1, missingSince = NULL WHERE uid = ?", [.int(uid)])
                    } else {
                        try db.run("UPDATE tracks SET available = 0, missingSince = COALESCE(missingSince, ?) WHERE uid = ?", [.int(now), .int(uid)])
                    }
                }
            }
        }
    }

    /// Alle Titel eines Ordners als (nicht) verfügbar markieren – z. B. externes Laufwerk getrennt/angeschlossen.
    public func setFolderAvailability(folderID: Int64, available: Bool) throws {
        try sync { db in
            if available {
                _ = try db.run("UPDATE tracks SET available = 1, missingSince = NULL WHERE folderId = ?", [.int(folderID)])
            } else {
                _ = try db.run("UPDATE tracks SET available = 0, missingSince = COALESCE(missingSince, ?) WHERE folderId = ?", [.int(Self.now()), .int(folderID)])
            }
        }
    }

    public func setHidden(uids: [Int64], hidden: Bool) throws {
        try sync { db in
            try db.transaction {
                for uid in uids { try db.run("UPDATE tracks SET hidden = ? WHERE uid = ?", [SQLValue(hidden), .int(uid)]) }
            }
        }
    }

    /// Entfernt Titel endgültig aus der Bibliothek (samt Favoriten, Playlist-Einträgen, Statistik, Verlauf).
    public func deleteTracks(uids: [Int64]) throws {
        try sync { db in
            try db.transaction {
                for uid in uids { try db.run("DELETE FROM tracks WHERE uid = ?", [.int(uid)]) }
            }
        }
    }

    // MARK: - Favoriten

    public func favoriteTracks() throws -> [FavoriteTrack] {
        try sync { db in try db.query("SELECT trackUid, addedAt FROM favorite_tracks") { FavoriteTrack(trackUid: $0.int64(0), addedAt: $0.int64(1)) } }
    }

    public func setFavorite(trackUids: [Int64], _ favorite: Bool) throws {
        try sync { db in
            try db.transaction {
                let now = Self.now()
                for uid in trackUids {
                    if favorite {
                        try db.run("INSERT OR IGNORE INTO favorite_tracks (trackUid, addedAt) VALUES (?, ?)", [.int(uid), .int(now)])
                    } else {
                        try db.run("DELETE FROM favorite_tracks WHERE trackUid = ?", [.int(uid)])
                    }
                }
            }
        }
    }

    public func favoriteAlbums() throws -> [FavoriteAlbum] {
        try sync { db in
            try db.query("SELECT albumKey, title, artist, addedAt FROM favorite_albums") {
                FavoriteAlbum(albumKey: $0.string(0), title: $0.optString(1), artist: $0.optString(2), addedAt: $0.int64(3))
            }
        }
    }

    public func setFavoriteAlbum(key: String, title: String?, artist: String?, _ favorite: Bool) throws {
        try sync { db in
            if favorite {
                _ = try db.run("INSERT OR REPLACE INTO favorite_albums (albumKey, title, artist, addedAt) VALUES (?, ?, ?, COALESCE((SELECT addedAt FROM favorite_albums WHERE albumKey = ?), ?))",
                               [.text(key), SQLValue(title), SQLValue(artist), .text(key), .int(Self.now())])
            } else {
                _ = try db.run("DELETE FROM favorite_albums WHERE albumKey = ?", [.text(key)])
            }
        }
    }

    // MARK: - Playlists

    public func playlists() throws -> [Playlist] {
        try sync { db in
            var entries: [Int64: [PlaylistEntry]] = [:]
            for (pid, e) in try db.query("SELECT playlistId, id, trackUid, position, addedAt FROM playlist_entries ORDER BY playlistId, position, id", [], { r in
                (r.int64(0), PlaylistEntry(entryId: r.int64(1), trackUid: r.int64(2), position: r.int(3), addedAt: r.int64(4)))
            }) {
                entries[pid, default: []].append(e)
            }
            return try db.query("SELECT id, name, createdAt, updatedAt FROM playlists ORDER BY id") { r in
                Playlist(id: r.int64(0), name: r.string(1), createdAt: r.int64(2), updatedAt: r.int64(3), entries: entries[r.int64(0)] ?? [])
            }
        }
    }

    @discardableResult
    public func createPlaylist(name: String, trackUids: [Int64] = []) throws -> Int64 {
        try sync { db in
            try db.transaction {
                let now = Self.now()
                try db.run("INSERT INTO playlists (name, createdAt, updatedAt) VALUES (?, ?, ?)", [.text(name), .int(now), .int(now)])
                let id = db.lastInsertRowID
                for (i, uid) in trackUids.enumerated() {
                    try db.run("INSERT INTO playlist_entries (playlistId, trackUid, position, addedAt) VALUES (?, ?, ?, ?)", [.int(id), .int(uid), .int(Int64(i)), .int(now)])
                }
                return id
            }
        }
    }

    public func renamePlaylist(id: Int64, name: String) throws {
        try sync { db in _ = try db.run("UPDATE playlists SET name = ?, updatedAt = ? WHERE id = ?", [.text(name), .int(Self.now()), .int(id)]) }
    }

    public func deletePlaylist(id: Int64) throws {
        try sync { db in _ = try db.run("DELETE FROM playlists WHERE id = ?", [.int(id)]) }
    }

    /// Fügt Titel ein (`position` = Einfügestelle, `nil` = ans Ende). Doppelte Titel sind erlaubt.
    public func addToPlaylist(id: Int64, trackUids: [Int64], at position: Int? = nil) throws {
        guard !trackUids.isEmpty else { return }
        try sync { db in
            try db.transaction {
                let now = Self.now()
                var order = try Self.entryOrder(db, id)
                let insertAt = min(max(position ?? order.count, 0), order.count)
                var newIds: [Int64] = []
                for uid in trackUids {
                    try db.run("INSERT INTO playlist_entries (playlistId, trackUid, position, addedAt) VALUES (?, ?, ?, ?)", [.int(id), .int(uid), .int(0), .int(now)])
                    newIds.append(db.lastInsertRowID)
                }
                order.insert(contentsOf: newIds, at: insertAt)
                try Self.writeOrder(db, id, order)
                try db.run("UPDATE playlists SET updatedAt = ? WHERE id = ?", [.int(now), .int(id)])
            }
        }
    }

    public func removeFromPlaylist(id: Int64, entryIds: [Int64]) throws {
        try sync { db in
            try db.transaction {
                for e in entryIds { try db.run("DELETE FROM playlist_entries WHERE id = ? AND playlistId = ?", [.int(e), .int(id)]) }
                try Self.writeOrder(db, id, try Self.entryOrder(db, id))
                try db.run("UPDATE playlists SET updatedAt = ? WHERE id = ?", [.int(Self.now()), .int(id)])
            }
        }
    }

    /// Verschiebt Einträge (Drag & Drop) vor die Stelle `toIndex` der bisherigen Reihenfolge.
    public func movePlaylistEntries(id: Int64, entryIds: [Int64], toIndex: Int) throws {
        try sync { db in
            try db.transaction {
                let order = try Self.entryOrder(db, id)
                let moving = Set(entryIds)
                let movingInOrder = order.filter { moving.contains($0) }
                let before = order.prefix(min(max(toIndex, 0), order.count)).filter { !moving.contains($0) }.count
                var rest = order.filter { !moving.contains($0) }
                rest.insert(contentsOf: movingInOrder, at: min(before, rest.count))
                try Self.writeOrder(db, id, rest)
                try db.run("UPDATE playlists SET updatedAt = ? WHERE id = ?", [.int(Self.now()), .int(id)])
            }
        }
    }

    /// Setzt die Reihenfolge vollständig (z. B. nach „Sortieren nach …“ → „Als Reihenfolge übernehmen“).
    public func setPlaylistOrder(id: Int64, entryIds: [Int64]) throws {
        try sync { db in
            try db.transaction {
                let existing = Set(try Self.entryOrder(db, id))
                var order = entryIds.filter { existing.contains($0) }
                let missing = existing.subtracting(order)
                order.append(contentsOf: try Self.entryOrder(db, id).filter { missing.contains($0) })
                try Self.writeOrder(db, id, order)
                try db.run("UPDATE playlists SET updatedAt = ? WHERE id = ?", [.int(Self.now()), .int(id)])
            }
        }
    }

    @discardableResult
    public func duplicatePlaylist(id: Int64, name: String) throws -> Int64 {
        let uids = try sync { db in
            try db.query("SELECT trackUid FROM playlist_entries WHERE playlistId = ? ORDER BY position, id", [.int(id)]) { $0.int64(0) }
        }
        return try createPlaylist(name: name, trackUids: uids)
    }

    private static func entryOrder(_ db: SQLiteConnection, _ playlistId: Int64) throws -> [Int64] {
        try db.query("SELECT id FROM playlist_entries WHERE playlistId = ? ORDER BY position, id", [.int(playlistId)]) { $0.int64(0) }
    }

    private static func writeOrder(_ db: SQLiteConnection, _ playlistId: Int64, _ order: [Int64]) throws {
        for (i, e) in order.enumerated() {
            try db.run("UPDATE playlist_entries SET position = ? WHERE id = ? AND playlistId = ?", [.int(Int64(i)), .int(e), .int(playlistId)])
        }
    }

    // MARK: - Statistik, Verlauf, Wiedergabepositionen

    public func playStats() throws -> [Int64: PlayStats] {
        try sync { db in
            var result: [Int64: PlayStats] = [:]
            for s in try db.query("SELECT trackUid, playCount, lastPlayedAt, firstPlayedAt, totalListenedMs FROM play_stats", [], { r in
                PlayStats(trackUid: r.int64(0), playCount: r.int(1), lastPlayedAt: r.optInt64(2), firstPlayedAt: r.optInt64(3), totalListenedMs: r.int64(4))
            }) {
                result[s.trackUid] = s
            }
            return result
        }
    }

    /// Eine beendete Wiedergabe festhalten: Verlaufseintrag (wenn `addToHistory`) und Statistik.
    public func recordPlayback(trackUid: Int64, startedAt: Int64, listenedMs: Int64, counted: Bool, addToHistory: Bool) throws {
        try sync { db in
            try db.transaction {
                guard try db.queryOne("SELECT 1 FROM tracks WHERE uid = ?", [.int(trackUid)], { $0.int(0) }) != nil else { return }
                if addToHistory {
                    try db.run("INSERT INTO play_history (trackUid, playedAt, listenedMs, counted) VALUES (?, ?, ?, ?)",
                               [.int(trackUid), .int(startedAt), .int(max(0, listenedMs)), SQLValue(counted)])
                }
                try db.run("INSERT OR IGNORE INTO play_stats (trackUid, playCount, totalListenedMs) VALUES (?, 0, 0)", [.int(trackUid)])
                if counted {
                    try db.run("UPDATE play_stats SET playCount = playCount + 1, lastPlayedAt = ?, firstPlayedAt = COALESCE(firstPlayedAt, ?), totalListenedMs = totalListenedMs + ? WHERE trackUid = ?",
                               [.int(startedAt), .int(startedAt), .int(max(0, listenedMs)), .int(trackUid)])
                } else {
                    try db.run("UPDATE play_stats SET totalListenedMs = totalListenedMs + ? WHERE trackUid = ?", [.int(max(0, listenedMs)), .int(trackUid)])
                }
            }
        }
    }

    /// Eine Wiedergabe zählen (sobald `PlayCountRule` erfüllt ist – auch wenn der Titel danach weiterläuft).
    public func countPlay(trackUid: Int64, at time: Int64) throws {
        try sync { db in
            try db.transaction {
                guard try db.queryOne("SELECT 1 FROM tracks WHERE uid = ?", [.int(trackUid)], { $0.int(0) }) != nil else { return }
                try db.run("INSERT OR IGNORE INTO play_stats (trackUid, playCount, totalListenedMs) VALUES (?, 0, 0)", [.int(trackUid)])
                try db.run("UPDATE play_stats SET playCount = playCount + 1, lastPlayedAt = ?, firstPlayedAt = COALESCE(firstPlayedAt, ?) WHERE trackUid = ?",
                           [.int(time), .int(time), .int(trackUid)])
            }
        }
    }

    /// Ende einer Wiedergabe: gehörte Zeit addieren und (optional) Verlaufseintrag anlegen. Zählt NICHT (siehe `countPlay`).
    public func finishPlayback(trackUid: Int64, startedAt: Int64, listenedMs: Int64, counted: Bool, addToHistory: Bool) throws {
        try sync { db in
            try db.transaction {
                guard try db.queryOne("SELECT 1 FROM tracks WHERE uid = ?", [.int(trackUid)], { $0.int(0) }) != nil else { return }
                if addToHistory {
                    try db.run("INSERT INTO play_history (trackUid, playedAt, listenedMs, counted) VALUES (?, ?, ?, ?)",
                               [.int(trackUid), .int(startedAt), .int(max(0, listenedMs)), SQLValue(counted)])
                }
                try db.run("INSERT OR IGNORE INTO play_stats (trackUid, playCount, totalListenedMs) VALUES (?, 0, 0)", [.int(trackUid)])
                try db.run("UPDATE play_stats SET totalListenedMs = totalListenedMs + ? WHERE trackUid = ?", [.int(max(0, listenedMs)), .int(trackUid)])
            }
        }
    }

    /// Wiedergabezähler zurücksetzen („Zähler: Zurücksetzen“).
    public func resetStats(trackUids: [Int64]) throws {
        try sync { db in
            try db.transaction {
                for uid in trackUids { try db.run("DELETE FROM play_stats WHERE trackUid = ?", [.int(uid)]) }
            }
        }
    }

    public func history(limit: Int = 500) throws -> [HistoryEntry] {
        try sync { db in
            try db.query("SELECT id, trackUid, playedAt, listenedMs, counted FROM play_history ORDER BY playedAt DESC, id DESC LIMIT ?", [.int(Int64(limit))]) { r in
                HistoryEntry(id: r.int64(0), trackUid: r.int64(1), playedAt: r.int64(2), listenedMs: r.int64(3), counted: r.bool(4))
            }
        }
    }

    public func removeHistory(ids: [Int64]) throws {
        try sync { db in
            try db.transaction { for id in ids { try db.run("DELETE FROM play_history WHERE id = ?", [.int(id)]) } }
        }
    }

    public func clearHistory() throws {
        try sync { db in _ = try db.run("DELETE FROM play_history") }
    }

    public func resumePoints() throws -> [Int64: ResumePoint] {
        try sync { db in
            var result: [Int64: ResumePoint] = [:]
            for p in try db.query("SELECT trackUid, positionMs, updatedAt FROM resume_points", [], { ResumePoint(trackUid: $0.int64(0), positionMs: $0.int64(1), updatedAt: $0.int64(2)) }) {
                result[p.trackUid] = p
            }
            return result
        }
    }

    public func setResumePoint(trackUid: Int64, positionMs: Int64?) throws {
        try sync { db in
            if let positionMs {
                _ = try db.run("INSERT OR REPLACE INTO resume_points (trackUid, positionMs, updatedAt) VALUES (?, ?, ?)", [.int(trackUid), .int(positionMs), .int(Self.now())])
            } else {
                _ = try db.run("DELETE FROM resume_points WHERE trackUid = ?", [.int(trackUid)])
            }
        }
    }

    // MARK: - Eigene Cover (nur Bibliothek)

    public func customArtwork(trackUid: Int64) throws -> String? {
        try sync { db in try db.queryOne("SELECT imagePath FROM custom_artwork WHERE trackUid = ?", [.int(trackUid)]) { $0.string(0) } }
    }

    public func allCustomArtwork() throws -> [Int64: String] {
        try sync { db in
            var result: [Int64: String] = [:]
            for (uid, p) in try db.query("SELECT trackUid, imagePath FROM custom_artwork", [], { ($0.int64(0), $0.string(1)) }) { result[uid] = p }
            return result
        }
    }

    public func setCustomArtwork(trackUid: Int64, imagePath: String?) throws {
        try sync { db in
            if let imagePath {
                _ = try db.run("INSERT OR REPLACE INTO custom_artwork (trackUid, imagePath, updatedAt) VALUES (?, ?, ?)", [.int(trackUid), .text(imagePath), .int(Self.now())])
            } else {
                _ = try db.run("DELETE FROM custom_artwork WHERE trackUid = ?", [.int(trackUid)])
            }
        }
    }

    // MARK: - App-Zustand (Warteschlange usw.)

    public func stateValue(_ key: String) -> String? {
        do {
            let row: String?? = try sync { db in
                try db.queryOne("SELECT value FROM app_state WHERE key = ?", [.text(key)]) { $0.optString(0) }
            }
            return row ?? nil
        } catch {
            return nil
        }
    }

    public func setStateValue(_ value: String?, for key: String) {
        _ = try? sync { db in
            if let value {
                try db.run("INSERT OR REPLACE INTO app_state (key, value) VALUES (?, ?)", [.text(key), .text(value)])
            } else {
                try db.run("DELETE FROM app_state WHERE key = ?", [.text(key)])
            }
        }
    }

    // MARK: - Wartung

    /// Sicherungskopie der Datenbank (konsistent, auch während der Benutzung).
    public func backup(to url: URL) throws {
        try sync { db in
            try? FileManager.default.removeItem(at: url)
            let escaped = url.path.replacingOccurrences(of: "'", with: "''")
            try db.execute("VACUUM INTO '\(escaped)'")
        }
    }

    public func integrityCheck() -> String {
        (try? sync { db in db.integrityCheck() }) ?? "error"
    }

    /// Anzahl der Titel (verfügbar, gesamt).
    public func counts() throws -> (available: Int, total: Int) {
        try sync { db in
            let total = try db.queryOne("SELECT COUNT(*) FROM tracks WHERE hidden = 0") { $0.int(0) } ?? 0
            let available = try db.queryOne("SELECT COUNT(*) FROM tracks WHERE hidden = 0 AND available = 1") { $0.int(0) } ?? 0
            return (available, total)
        }
    }
}

extension Array {
    func chunked(_ size: Int) -> [ArraySlice<Element>] {
        stride(from: 0, to: count, by: size).map { self[$0 ..< Swift.min($0 + size, count)] }
    }
}
