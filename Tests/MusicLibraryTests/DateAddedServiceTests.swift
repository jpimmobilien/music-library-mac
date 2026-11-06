import XCTest
import MLCore
import MLStore
@testable import MusicLibrary

/// v2.1: Übernahme des Hinzufügedatums aus einer Apple-Musik-/iTunes-Mediathek-XML und Zuordnung zu den Titeln.
final class DateAddedServiceTests: XCTestCase {
    private func writeLibraryXML(_ tracks: [[String: Any]]) throws -> URL {
        var dict: [String: Any] = [:]
        for (i, t) in tracks.enumerated() { dict[String(i + 1)] = t }
        let plist: [String: Any] = ["Major Version": 1, "Tracks": dict]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Library-\(UUID().uuidString).xml")
        try data.write(to: url)
        return url
    }

    func testXMLDatesMatchByPathOrUniqueMetadata() throws {
        let added2015 = Date(timeIntervalSince1970: 1_420_070_400)
        let added2019 = Date(timeIntervalSince1970: 1_546_300_800)
        let older = Date(timeIntervalSince1970: 1_300_000_000)
        let url = try writeLibraryXML([
            ["Name": "Chasing Cars", "Artist": "Snow Patrol", "Album": "Eyes Open", "Total Time": 267_000,
             "Date Added": added2015, "Location": "file:///Users/test/Music/Music/Media.localized/Music/Snow%20Patrol/Eyes%20Open/01%20Chasing%20Cars.m4a"],
            ["Name": "Wonderwall", "Artist": "Oasis", "Album": "(What's the Story) Morning Glory?", "Total Time": 258_000,
             "Date Added": added2019, "Location": "file:///Volumes/Alt/Oasis/03%20Wonderwall.mp3"],
            // zweite, ältere Mediathek mit demselben Titel → frühestes Datum zählt
            ["Name": "Chasing Cars", "Artist": "Snow Patrol", "Album": "Eyes Open", "Total Time": 267_000,
             "Date Added": older, "Location": "file:///Users/test/Music/Music/Media.localized/Music/Snow%20Patrol/Eyes%20Open/01%20Chasing%20Cars.m4a"],
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let dates = try XCTUnwrap(AppleMusicDates.loadXML(from: [url]))
        // Pfad (Groß-/Kleinschreibung egal), frühestes Datum
        XCTAssertEqual(dates.lookup(path: "/Users/test/Music/Music/Media.localized/Music/Snow Patrol/Eyes Open/01 chasing cars.m4a",
                                    title: nil, artist: nil, album: nil, durationMs: 0), 1_300_000_000)
        // Datei liegt woanders: eindeutig über Titel/Interpret/Album und ähnliche Dauer
        XCTAssertEqual(dates.lookup(path: "/Users/test/Musik/Oasis/Wonderwall.mp3", title: "Wonderwall", artist: "oasis",
                                    album: "(What's the Story) Morning Glory?", durationMs: 259_500), 1_546_300_800)
        // Dauer weicht zu stark ab → kein Treffer (anderer Mix)
        XCTAssertNil(dates.lookup(path: "/x.mp3", title: "Wonderwall", artist: "Oasis", album: "(What's the Story) Morning Glory?", durationMs: 300_000))
        XCTAssertNil(dates.lookup(path: "/y.mp3", title: "Unbekannt", artist: "Niemand", album: nil, durationMs: 1000))
    }

    func testMissingXMLGivesNil() {
        XCTAssertNil(AppleMusicDates.loadXML(from: [URL(fileURLWithPath: "/nicht/vorhanden/Library.xml")]))
    }

    /// Rekonstruktion vorhandener Titel aus dem Erstellungsdatum der Dateien; zweiter Lauf ändert nichts;
    /// nach erneutem Öffnen der Datenbank (App-Neustart) sind die Daten erhalten.
    func testReconstructionFromFileDatesPersistsAcrossRestart() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ml-dates-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbPath = dir.appendingPathComponent("library.sqlite").path
        let created: [Int64] = [1_514_764_800, 1_577_836_800]   // 2018, 2020
        var uids: [Int64] = []
        do {
            let store = try LibraryStore(path: dbPath)
            let folder = try store.addFolder(path: dir.path, bookmark: nil, name: "Test", volumeName: nil, isExternal: false)
            for (i, c) in created.enumerated() {
                let file = dir.appendingPathComponent("t\(i).m4a")
                try Data([0]).write(to: file)
                try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: TimeInterval(c))], ofItemAtPath: file.path)
                var tags = TagValues()
                tags.title = "T\(i)"
                let rec = TrackRecord(folderID: folder.id, path: file.path, relativePath: "", fileName: file.lastPathComponent, fileID: 0,
                                      sizeBytes: 1, dateModified: 1_700_000_000, tags: tags,
                                      audio: AudioProperties(durationMs: 1000, bitrate: 256, sampleRate: 44100, channels: 2, codec: "AAC"),
                                      hasLyrics: false, metaVersion: 1)
                // wie ein Import durch Version 2.0: Importzeit, Herkunft unbekannt
                uids.append(try store.insertTrack(rec, dateAdded: 1_780_000_000, source: .unknown))
            }
            let first = LibraryService.performDateReconstruction(store: store, useITLibrary: false, force: false)
            XCTAssertEqual(first.changed, 2, first.message)
            let second = LibraryService.performDateReconstruction(store: store, useITLibrary: false, force: false)
            XCTAssertEqual(second.changed, 0)
        }
        // „Neustart“: Datenbank neu öffnen
        let reopened = try LibraryStore(path: dbPath)
        for (i, uid) in uids.enumerated() {
            let t = try XCTUnwrap(reopened.track(uid: uid))
            XCTAssertEqual(t.dateAdded, created[i])
            XCTAssertEqual(t.dateAddedSource, .fileCreated)
        }
        // Sortierung „Hinzugefügt – Neueste zuerst“ über die gespeicherten Daten
        let sorted = Sorting.tracks(try reopened.allTracks(), sort: Sort(TrackSort.dateAdded, descending: true), stats: [:]).map(\.uid)
        XCTAssertEqual(sorted, [uids[1], uids[0]])
    }
}
