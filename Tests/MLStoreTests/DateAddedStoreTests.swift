import XCTest
import MLCore
@testable import MLStore

/// v2.1: Hinzufügedatum je Datei, Herkunft, additive Migration (Version 2.0 kann die Datenbank weiter öffnen).
final class DateAddedStoreTests: XCTestCase {
    private func record(_ name: String, folder: Int64) -> TrackRecord {
        var tags = TagValues()
        tags.title = name
        tags.album = "Album"
        return TrackRecord(folderID: folder, path: "/Musik/\(name)", relativePath: "", fileName: name, fileID: 0, sizeBytes: 1,
                           dateModified: 1_700_000_000, tags: tags, audio: AudioProperties(durationMs: 1000, bitrate: 256, sampleRate: 44100, channels: 2, codec: "AAC"),
                           hasLyrics: false, metaVersion: 1)
    }

    private func makeStore() throws -> (LibraryStore, LibraryFolder) {
        let store = try LibraryStore.inMemory()
        let folder = try store.addFolder(path: "/Musik", bookmark: nil, name: "Musik", volumeName: nil, isExternal: false)
        return (store, folder)
    }

    func testScanStoresIndividualDatesAndSources() throws {
        let (store, folder) = try makeStore()
        let uids = try store.applyScan(inserts: [record("a.m4a", folder: folder.id), record("b.m4a", folder: folder.id)],
                                       addedDates: [(1_500_000_000, .appleMusic), (1_600_000_000, .fileCreated)], updates: [], missing: [])
        let a = try XCTUnwrap(store.track(uid: uids[0]))
        let b = try XCTUnwrap(store.track(uid: uids[1]))
        XCTAssertEqual(a.dateAdded, 1_500_000_000)
        XCTAssertEqual(a.dateAddedSource, .appleMusic)
        XCTAssertEqual(b.dateAdded, 1_600_000_000)
        XCTAssertEqual(b.dateAddedSource, .fileCreated)
    }

    func testRescanUpdateNeverOverwritesDateAdded() throws {
        let (store, folder) = try makeStore()
        let uid = try store.insertTrack(record("a.m4a", folder: folder.id), dateAdded: 1_400_000_000, source: .appleMusic)
        var changed = record("a.m4a", folder: folder.id)
        changed.tags?.title = "Neu"
        _ = try store.applyScan(inserts: [], updates: [(uid, changed)], missing: [], dateAdded: 1_900_000_000)
        let t = try XCTUnwrap(store.track(uid: uid))
        XCTAssertEqual(t.title, "Neu")
        XCTAssertEqual(t.dateAdded, 1_400_000_000)
        XCTAssertEqual(t.dateAddedSource, .appleMusic)
    }

    func testSetDateAddedAndRowsAndMeta() throws {
        let (store, folder) = try makeStore()
        let uid = try store.insertTrack(record("a.m4a", folder: folder.id), dateAdded: 1_800_000_000)
        try store.setDateAdded([(uid, 1_300_000_000, .fileCreated)])
        let row = try XCTUnwrap(store.dateAddedRows().first)
        XCTAssertEqual(row.dateAdded, 1_300_000_000)
        XCTAssertEqual(row.source, .fileCreated)
        XCTAssertNil(try store.meta("x"))
        try store.setMeta("x", "1")
        XCTAssertEqual(try store.meta("x"), "1")
    }

    /// Eine Datenbank von Version 2.0 (ohne die neue Spalte) wird beim Öffnen ergänzt; Daten bleiben erhalten,
    /// die Schemaversion bleibt 1 (Version 2.0 kann sie danach weiter öffnen).
    func testAdditiveMigrationOfVersion20Database() throws {
        let path = NSTemporaryDirectory() + "dateadded-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let db = try SQLiteConnection(path: path)
            try db.execute(Schema.v1)
            try db.setUserVersion(1)
            try db.run("INSERT INTO folders (path, name, addedAt) VALUES ('/Musik', 'Musik', 0)")
            try db.run("INSERT INTO tracks (folderId, path, relativePath, fileName, dateAdded, title) VALUES (1, '/Musik/a.mp3', '', 'a.mp3', 1700000000, 'Alt')")
        }
        let store = try LibraryStore(path: path)
        let t = try XCTUnwrap(store.allTracks().first)
        XCTAssertEqual(t.title, "Alt")
        XCTAssertEqual(t.dateAdded, 1_700_000_000)
        XCTAssertEqual(t.dateAddedSource, .unknown)
        // zweites Öffnen ist unschädlich
        _ = try LibraryStore(path: path)
        let db = try SQLiteConnection(path: path)
        XCTAssertEqual(db.userVersion, 1)
    }
}
