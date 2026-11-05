import XCTest
import MLCore
@testable import MLStore

final class LibraryStoreTests: XCTestCase {
    private func scanned(_ name: String, folder: Int64, title: String? = nil, artists: [String] = [], fileID: Int64 = 0) -> TrackRecord {
        var tags = TagValues()
        tags.title = title
        tags.artists = artists
        tags.album = "Album"
        tags.genres = ["Pop", "Rock"]
        tags.composers = ["Komponist Ä"]
        tags.trackNumber = 3
        tags.rating = 80
        return TrackRecord(folderID: folder, path: "/Musik/\(name)", relativePath: "", fileName: name, fileID: fileID, sizeBytes: 1234,
                           dateModified: 1_700_000_000, tags: tags, audio: AudioProperties(durationMs: 180_000, bitrate: 256, sampleRate: 44100, channels: 2, codec: "AAC"),
                           hasLyrics: false, metaVersion: 1)
    }

    private func makeStore() throws -> (LibraryStore, LibraryFolder) {
        let store = try LibraryStore.inMemory()
        let folder = try store.addFolder(path: "/Musik", bookmark: Data([1, 2, 3]), name: "Musik", volumeName: "Macintosh HD", isExternal: false)
        return (store, folder)
    }

    func testInsertAndReadTrackRoundTrip() throws {
        let (store, folder) = try makeStore()
        let uid = try store.insertTrack(scanned("a.m4a", folder: folder.id, title: "Я буду жить", artists: ["Ploho", "Gast"]), dateAdded: 42)
        let t = try XCTUnwrap(store.track(uid: uid))
        XCTAssertEqual(t.title, "Я буду жить")
        XCTAssertEqual(t.artists, ["Ploho", "Gast"])
        XCTAssertEqual(t.genres, ["Pop", "Rock"])
        XCTAssertEqual(t.composers, ["Komponist Ä"])
        XCTAssertEqual(t.trackNumber, 3)
        XCTAssertEqual(t.rating, 80)
        XCTAssertEqual(t.durationMs, 180_000)
        XCTAssertEqual(t.codec, "AAC")
        XCTAssertEqual(t.dateAdded, 42)
        XCTAssertTrue(t.available)
        XCTAssertEqual(try store.folders().first?.bookmark, Data([1, 2, 3]))
    }

    func testTagUpdateKeepsUidAndUserData() throws {
        let (store, folder) = try makeStore()
        let uid = try store.insertTrack(scanned("a.mp3", folder: folder.id, title: "Alt"), dateAdded: 1)
        try store.setFavorite(trackUids: [uid], true)
        let pl = try store.createPlaylist(name: "Liste", trackUids: [uid, uid])
        var v = TagValues()
        v.title = "Neu"
        v.artists = ["X"]
        try store.updateTags(uid: uid, values: v, sizeBytes: 999, dateModified: 5, hasLyrics: true)
        let t = try XCTUnwrap(store.track(uid: uid))
        XCTAssertEqual(t.title, "Neu")
        XCTAssertEqual(t.sizeBytes, 999)
        XCTAssertTrue(t.hasLyrics)
        XCTAssertEqual(try store.favoriteTracks().map(\.trackUid), [uid])
        XCTAssertEqual(try store.playlists().first { $0.id == pl }?.entries.count, 2)
    }

    func testPlaylistOrderOperations() throws {
        let (store, folder) = try makeStore()
        let uids = try (0..<5).map { try store.insertTrack(scanned("\($0).mp3", folder: folder.id, title: "T\($0)"), dateAdded: 1) }
        let pl = try store.createPlaylist(name: "P", trackUids: Array(uids[0..<3]))
        try store.addToPlaylist(id: pl, trackUids: [uids[3], uids[4]], at: 1)
        var entries = try XCTUnwrap(store.playlists().first).entries
        XCTAssertEqual(entries.map(\.trackUid), [uids[0], uids[3], uids[4], uids[1], uids[2]])
        // Einträge 3 und 4 ans Ende verschieben
        try store.movePlaylistEntries(id: pl, entryIds: [entries[1].entryId, entries[2].entryId], toIndex: 5)
        entries = try XCTUnwrap(store.playlists().first).entries
        XCTAssertEqual(entries.map(\.trackUid), [uids[0], uids[1], uids[2], uids[3], uids[4]])
        // nach vorne verschieben
        try store.movePlaylistEntries(id: pl, entryIds: [entries[4].entryId], toIndex: 0)
        entries = try XCTUnwrap(store.playlists().first).entries
        XCTAssertEqual(entries.map(\.trackUid), [uids[4], uids[0], uids[1], uids[2], uids[3]])
        XCTAssertEqual(entries.map(\.position), [0, 1, 2, 3, 4])
        try store.removeFromPlaylist(id: pl, entryIds: [entries[0].entryId])
        entries = try XCTUnwrap(store.playlists().first).entries
        XCTAssertEqual(entries.map(\.trackUid), [uids[0], uids[1], uids[2], uids[3]])
        XCTAssertEqual(entries.map(\.position), [0, 1, 2, 3])
        try store.renamePlaylist(id: pl, name: "Umbenannt")
        XCTAssertEqual(try store.playlists().first?.name, "Umbenannt")
        let copy = try store.duplicatePlaylist(id: pl, name: "Kopie")
        XCTAssertEqual(try store.playlists().first { $0.id == copy }?.entries.map(\.trackUid), entries.map(\.trackUid))
        try store.deletePlaylist(id: pl)
        XCTAssertEqual(try store.playlists().map(\.id), [copy])
    }

    func testStatsHistoryAndReset() throws {
        let (store, folder) = try makeStore()
        let uid = try store.insertTrack(scanned("a.mp3", folder: folder.id, title: "A"), dateAdded: 1)
        try store.recordPlayback(trackUid: uid, startedAt: 1000, listenedMs: 60_000, counted: true, addToHistory: true)
        try store.recordPlayback(trackUid: uid, startedAt: 2000, listenedMs: 3_000, counted: false, addToHistory: false)
        try store.recordPlayback(trackUid: uid, startedAt: 3000, listenedMs: 90_000, counted: true, addToHistory: true)
        let s = try XCTUnwrap(store.playStats()[uid])
        XCTAssertEqual(s.playCount, 2)
        XCTAssertEqual(s.lastPlayedAt, 3000)
        XCTAssertEqual(s.firstPlayedAt, 1000)
        XCTAssertEqual(s.totalListenedMs, 153_000)
        XCTAssertEqual(try store.history().map(\.playedAt), [3000, 1000])
        try store.resetStats(trackUids: [uid])
        XCTAssertNil(try store.playStats()[uid])
        try store.clearHistory()
        XCTAssertTrue(try store.history().isEmpty)
        // unbekannte uid: nichts passiert
        try store.recordPlayback(trackUid: 9999, startedAt: 1, listenedMs: 1, counted: true, addToHistory: true)
        XCTAssertTrue(try store.history().isEmpty)
    }

    func testCountPlayAndFinishPlaybackAreSeparate() throws {
        let (store, folder) = try makeStore()
        let uid = try store.insertTrack(scanned("a.mp3", folder: folder.id, title: "A"), dateAdded: 1)
        try store.countPlay(trackUid: uid, at: 5000)
        try store.finishPlayback(trackUid: uid, startedAt: 4000, listenedMs: 95_000, counted: true, addToHistory: true)
        try store.finishPlayback(trackUid: uid, startedAt: 9000, listenedMs: 2_000, counted: false, addToHistory: false)
        let s = try XCTUnwrap(store.playStats()[uid])
        XCTAssertEqual(s.playCount, 1)
        XCTAssertEqual(s.lastPlayedAt, 5000)
        XCTAssertEqual(s.totalListenedMs, 97_000)
        let h = try store.history()
        XCTAssertEqual(h.count, 1)
        XCTAssertEqual(h.first?.counted, true)
        XCTAssertEqual(h.first?.listenedMs, 95_000)
    }

    func testMissingTracksAreKeptAndDeleteCascades() throws {
        let (store, folder) = try makeStore()
        let a = try store.insertTrack(scanned("a.mp3", folder: folder.id, title: "A"), dateAdded: 1)
        let b = try store.insertTrack(scanned("b.mp3", folder: folder.id, title: "B"), dateAdded: 1)
        try store.setFavorite(trackUids: [a, b], true)
        try store.recordPlayback(trackUid: a, startedAt: 1, listenedMs: 40_000, counted: true, addToHistory: true)
        _ = try store.applyScan(inserts: [], updates: [], missing: [a], dateAdded: 2)
        XCTAssertEqual(try store.track(uid: a)?.available, false)
        XCTAssertEqual(try store.allTracks().count, 2)
        try store.deleteTracks(uids: [a])
        XCTAssertNil(try store.track(uid: a))
        XCTAssertEqual(try store.favoriteTracks().map(\.trackUid), [b])
        XCTAssertTrue(try store.history().isEmpty)
        XCTAssertNil(try store.playStats()[a])
    }

    func testFolderRemovalAndAvailability() throws {
        let (store, folder) = try makeStore()
        let a = try store.insertTrack(scanned("a.mp3", folder: folder.id, title: "A"), dateAdded: 1)
        try store.setFolderAvailability(folderID: folder.id, available: false)
        XCTAssertEqual(try store.track(uid: a)?.available, false)
        try store.setFolderAvailability(folderID: folder.id, available: true)
        XCTAssertEqual(try store.track(uid: a)?.available, true)
        try store.removeFolder(id: folder.id, deleteTracks: false)
        XCTAssertEqual(try store.track(uid: a)?.available, false)
        XCTAssertTrue(try store.folders().isEmpty)
    }

    func testResumePointsStateAndHidden() throws {
        let (store, folder) = try makeStore()
        let a = try store.insertTrack(scanned("a.mp3", folder: folder.id, title: "A"), dateAdded: 1)
        try store.setResumePoint(trackUid: a, positionMs: 61_000)
        XCTAssertEqual(try store.resumePoints()[a]?.positionMs, 61_000)
        try store.setResumePoint(trackUid: a, positionMs: nil)
        XCTAssertNil(try store.resumePoints()[a])
        store.setStateValue("{\"q\":1}", for: "queue")
        XCTAssertEqual(store.stateValue("queue"), "{\"q\":1}")
        store.setStateValue(nil, for: "queue")
        XCTAssertNil(store.stateValue("queue"))
        try store.setHidden(uids: [a], hidden: true)
        XCTAssertTrue(try store.allTracks().isEmpty)
        XCTAssertEqual(try store.allTracks(includeHidden: true).count, 1)
    }

    func testMovedFileKeepsUid() throws {
        let (store, folder) = try makeStore()
        let a = try store.insertTrack(scanned("a.mp3", folder: folder.id, title: "A", fileID: 77), dateAdded: 1)
        try store.updateFileLocation(uid: a, folderID: folder.id, path: "/Musik/Neu/a.mp3", relativePath: "Neu/", fileName: "a.mp3", fileID: 77, sizeBytes: 1234, dateModified: 1_700_000_000)
        let t = try XCTUnwrap(store.track(uid: a))
        XCTAssertEqual(t.path, "/Musik/Neu/a.mp3")
        XCTAssertEqual(t.relativePath, "Neu/")
        XCTAssertEqual(try store.knownFiles(folderID: folder.id).first?.fileID, 77)
    }

    func testFileDatabasePersistsAndBackup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mlstore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("library.sqlite").path
        do {
            let store = try LibraryStore(path: path)
            let f = try store.addFolder(path: "/M", bookmark: nil, name: "M", volumeName: nil, isExternal: true)
            try store.insertTrack(scanned("x.flac", folder: f.id, title: "X"), dateAdded: 1)
            try store.backup(to: dir.appendingPathComponent("backup.sqlite"))
        }
        let reopened = try LibraryStore(path: path)
        XCTAssertEqual(try reopened.allTracks().map(\.title), ["X"])
        XCTAssertEqual(reopened.integrityCheck(), "ok")
        let backup = try LibraryStore(path: dir.appendingPathComponent("backup.sqlite").path)
        XCTAssertEqual(try backup.allTracks().count, 1)
    }

    func testLargeLibraryPerformance() throws {
        let (store, folder) = try makeStore()
        let files = (0..<5000).map { scanned("f\($0).mp3", folder: folder.id, title: "Titel \($0)", artists: ["Interpret \($0 % 300)"]) }
        let start = Date()
        _ = try store.applyScan(inserts: files, updates: [], missing: [], dateAdded: 1)
        let insertTime = Date().timeIntervalSince(start)
        let t0 = Date()
        let all = try store.allTracks()
        let readTime = Date().timeIntervalSince(t0)
        XCTAssertEqual(all.count, 5000)
        print("5000 Titel: Einfügen \(String(format: "%.2f", insertTime)) s, Lesen \(String(format: "%.3f", readTime)) s")
        XCTAssertLessThan(readTime, 2.0)
    }
}
