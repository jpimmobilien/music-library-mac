import Foundation

/// Datenbankschema und Migrationen. `PRAGMA user_version` enthält die Schemaversion.
///
/// Grundsätze (wie Android):
///  - Musikdateien bleiben, wo sie sind; die Datenbank ist nur ein Index.
///  - Nicht gefundene Titel werden nie automatisch gelöscht, nur als nicht verfügbar markiert.
///  - Favoriten, Playlists, Statistik, Verlauf und Wiedergabepositionen hängen an der dauerhaften `uid`.
enum Schema {
    static let currentVersion = 1

    static func migrate(_ db: SQLiteConnection) throws {
        let version = db.userVersion
        if version > currentVersion {
            throw SQLiteError(code: -1, message: "Die Datenbank stammt von einer neueren App-Version (\(version)).", sql: nil)
        }
        if version < 1 {
            try db.transaction {
                try db.execute(v1)
                try db.setUserVersion(1)
            }
        }
    }

    static let v1 = """
    CREATE TABLE IF NOT EXISTS folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT NOT NULL UNIQUE,
        bookmark BLOB,
        name TEXT NOT NULL,
        addedAt INTEGER NOT NULL,
        lastScanAt INTEGER,
        volumeName TEXT,
        isExternal INTEGER NOT NULL DEFAULT 0,
        enabled INTEGER NOT NULL DEFAULT 1
    );

    CREATE TABLE IF NOT EXISTS tracks (
        uid INTEGER PRIMARY KEY AUTOINCREMENT,
        folderId INTEGER NOT NULL,
        path TEXT NOT NULL,
        relativePath TEXT NOT NULL,
        fileName TEXT NOT NULL,
        fileID INTEGER NOT NULL DEFAULT 0,
        sizeBytes INTEGER NOT NULL DEFAULT 0,
        dateModified INTEGER NOT NULL DEFAULT 0,
        dateAdded INTEGER NOT NULL DEFAULT 0,
        durationMs INTEGER NOT NULL DEFAULT 0,
        codec TEXT,
        sampleRate INTEGER NOT NULL DEFAULT 0,
        bitrate INTEGER NOT NULL DEFAULT 0,
        channels INTEGER NOT NULL DEFAULT 0,
        bitsPerSample INTEGER NOT NULL DEFAULT 0,
        available INTEGER NOT NULL DEFAULT 1,
        missingSince INTEGER,
        hidden INTEGER NOT NULL DEFAULT 0,
        title TEXT,
        artists TEXT,
        album TEXT,
        albumArtists TEXT,
        genres TEXT,
        composers TEXT,
        grouping TEXT,
        year INTEGER,
        trackNumber INTEGER,
        trackTotal INTEGER,
        discNumber INTEGER,
        discTotal INTEGER,
        compilation INTEGER NOT NULL DEFAULT 0,
        bpm INTEGER,
        rating INTEGER,
        comment TEXT,
        titleSort TEXT,
        artistSort TEXT,
        albumSort TEXT,
        albumArtistSort TEXT,
        composerSort TEXT,
        hasPicture INTEGER NOT NULL DEFAULT 0,
        hasLyrics INTEGER NOT NULL DEFAULT 0,
        metaVersion INTEGER NOT NULL DEFAULT 0,
        metaReadAt INTEGER NOT NULL DEFAULT 0
    );
    CREATE UNIQUE INDEX IF NOT EXISTS tracks_path ON tracks(path);
    CREATE INDEX IF NOT EXISTS tracks_folder ON tracks(folderId);
    CREATE INDEX IF NOT EXISTS tracks_fileid ON tracks(fileID);
    CREATE INDEX IF NOT EXISTS tracks_available ON tracks(available, hidden);

    CREATE TABLE IF NOT EXISTS favorite_tracks (
        trackUid INTEGER PRIMARY KEY REFERENCES tracks(uid) ON DELETE CASCADE,
        addedAt INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS favorite_albums (
        albumKey TEXT PRIMARY KEY,
        title TEXT,
        artist TEXT,
        addedAt INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS playlist_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlistId INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
        trackUid INTEGER NOT NULL REFERENCES tracks(uid) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        addedAt INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS playlist_entries_order ON playlist_entries(playlistId, position);
    CREATE INDEX IF NOT EXISTS playlist_entries_track ON playlist_entries(trackUid);

    CREATE TABLE IF NOT EXISTS play_stats (
        trackUid INTEGER PRIMARY KEY REFERENCES tracks(uid) ON DELETE CASCADE,
        playCount INTEGER NOT NULL DEFAULT 0,
        lastPlayedAt INTEGER,
        firstPlayedAt INTEGER,
        totalListenedMs INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS play_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trackUid INTEGER NOT NULL REFERENCES tracks(uid) ON DELETE CASCADE,
        playedAt INTEGER NOT NULL,
        listenedMs INTEGER NOT NULL DEFAULT 0,
        counted INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS play_history_time ON play_history(playedAt);

    CREATE TABLE IF NOT EXISTS resume_points (
        trackUid INTEGER PRIMARY KEY REFERENCES tracks(uid) ON DELETE CASCADE,
        positionMs INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS custom_artwork (
        trackUid INTEGER PRIMARY KEY REFERENCES tracks(uid) ON DELETE CASCADE,
        imagePath TEXT NOT NULL,
        updatedAt INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS app_state (
        key TEXT PRIMARY KEY,
        value TEXT
    );
    """
}
