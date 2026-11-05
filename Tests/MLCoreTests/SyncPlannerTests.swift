import XCTest
@testable import MLCore

/// Portierung von `library/SyncPlannerTest.kt`, angepasst an den Mac (Ordner statt Medienbibliothek,
/// Dateikennung/Inode statt Medien-ID, Laufwerk/Ordner offline statt Speicherkarte entnommen).
final class SyncPlannerTests: XCTestCase {

    private let v = 1 // Version des Tag-Lesers
    private let music: Int64 = 1 // Musikordner „~/Music“
    private let usb: Int64 = 2   // Musikordner auf einem USB-Laufwerk

    private func file(
        _ id: UInt64, path: String = "/Users/me/Music/A/", name: String? = nil, size: Int64? = nil, mod: Int64 = 100,
        folder: Int64? = nil, fileID: UInt64? = nil
    ) -> ScannedFile {
        ScannedFile(
            folderID: folder ?? music,
            path: path + (name ?? "song\(id).m4a"),
            sizeBytes: size ?? (1000 + Int64(id)),
            dateModified: mod,
            fileID: fileID ?? id
        )
    }

    private func known(_ uid: Int64, _ f: ScannedFile, available: Bool = true, metaVersion: Int? = nil) -> KnownFile {
        KnownFile(uid: uid, folderID: f.folderID, path: f.path, sizeBytes: f.sizeBytes, dateModified: f.dateModified,
                  fileID: f.fileID, volumeID: f.volumeID, available: available, metaVersion: metaVersion ?? v)
    }

    private func plan(_ known: [KnownFile], _ scanned: [ScannedFile], online: Set<Int64>? = nil, trusted: Set<Int64>? = nil) -> SyncPlan {
        SyncPlanner.plan(known: known, scanned: scanned, onlineFolders: online ?? [music], tagReaderVersion: v, trustedFileIDFolders: trusted)
    }

    private func with(_ f: ScannedFile, path: String? = nil, size: Int64? = nil, mod: Int64? = nil, fileID: UInt64?? = nil) -> ScannedFile {
        var c = f
        if let path { c.path = path }
        if let size { c.sizeBytes = size }
        if let mod { c.dateModified = mod }
        if let fileID { c.fileID = fileID }
        return c
    }

    func testErstscan_allesNeu() {
        let p = plan([], [file(1), file(2)])
        XCTAssertEqual(p.items.count, 2)
        XCTAssertTrue(p.items.allSatisfy { $0.uid == nil && $0.readTags && $0.kind == .new })
        XCTAssertEqual(p.newItems.count, 2)
    }

    func testUnveraendert_nichtsZuTun() {
        let f = file(1)
        let p = plan([known(10, f)], [f])
        XCTAssertTrue(p.isEmpty)
        XCTAssertEqual(p.unchangedCount, 1)
    }

    func testGeaenderteDatei_metadatenNeuLesen_kennungBleibt() {
        let old = file(1, mod: 100)
        let new = with(old, size: 2222, mod: 200)
        let item = plan([known(10, old)], [new]).items.first!
        XCTAssertEqual(item.uid, 10)
        XCTAssertTrue(item.readTags)
        XCTAssertFalse(item.relinked)
        XCTAssertEqual(item.kind, .changed)
    }

    func testNeueTagLeserVersion_liestNeu() {
        let f = file(1)
        let item = plan([known(10, f, metaVersion: 0)], [f]).items.first!
        XCTAssertTrue(item.readTags)
        XCTAssertEqual(item.kind, .refreshed)
    }

    func testErsetzteDateiMitNeuerKennung_amSelbenOrt_behaeltKennung() {
        // z. B. Tags sicher geschrieben: Kopie bearbeitet, dann ersetzt → neuer Inode, gleicher Pfad
        let old = file(1)
        let replaced = with(old, mod: 300, fileID: 77)
        let p = plan([known(10, old)], [replaced])
        let item = p.items.first!
        XCTAssertEqual(item.uid, 10)
        XCTAssertTrue(item.relinked)
        XCTAssertFalse(item.moved)
        XCTAssertTrue(item.readTags)
        XCTAssertTrue(p.missing.isEmpty)
    }

    func testVerschobeneDatei_neueKennungNeuerOrdner_wirdWiedererkannt() {
        // neu kopiert (neuer Inode) in einen anderen Ordner
        let old = file(1, path: "/Users/me/Music/Alt/", name: "Song.m4a", size: 5_000_000)
        let moved = file(55, path: "/Users/me/Music/Neu/", name: "Song.m4a", size: 5_000_000)
        let p = plan([known(10, old)], [moved])
        let item = p.items.first!
        XCTAssertEqual(item.uid, 10)
        XCTAssertTrue(item.relinked)
        XCTAssertEqual(item.kind, .moved)
        XCTAssertFalse(item.readTags) // gleicher Inhalt
        XCTAssertTrue(p.missing.isEmpty)
    }

    func testUmbenannt_gleicheGroesseUndAenderungsdatum_wirdWiedererkannt() {
        // Android: gleiche Größe und Dauer; auf dem Mac (vor dem Tag-Lesen): gleiche Größe und Änderungsdatum
        let old = file(1, name: "01 Song.mp3", size: 4_000_000, mod: 500)
        let renamed = file(9, name: "Song (Remaster).mp3", size: 4_000_000, mod: 500)
        XCTAssertEqual(plan([known(10, old)], [renamed]).items.first?.uid, 10)
        // andere Endung → nicht dieselbe Datei
        let other = file(9, name: "Song (Remaster).m4a", size: 4_000_000, mod: 500)
        XCTAssertNil(plan([known(10, old)], [other]).items.first?.uid)
    }

    func testMehrdeutigerKandidat_wirdNichtGeraten() {
        let a = file(1, path: "/Users/me/Music/X/", name: "Track.mp3", size: 3000)
        let b = file(2, path: "/Users/me/Music/Y/", name: "Track.mp3", size: 3000)
        let newFile = file(3, path: "/Users/me/Music/Z/", name: "Track.mp3", size: 3000)
        let p = plan([known(10, a), known(11, b)], [newFile])
        XCTAssertNil(p.items.first?.uid)
        XCTAssertEqual(Set(p.missing), [10, 11])
    }

    func testMehrdeutigerKandidat_gleichesAenderungsdatumEntscheidet() {
        let a = file(1, path: "/Users/me/Music/X/", name: "Track.mp3", size: 3000, mod: 100)
        let b = file(2, path: "/Users/me/Music/Y/", name: "Track.mp3", size: 3000, mod: 200)
        let newFile = file(3, path: "/Users/me/Music/Z/", name: "Track.mp3", size: 3000, mod: 200)
        XCTAssertEqual(plan([known(10, a), known(11, b)], [newFile]).items.first?.uid, 11)
    }

    func testGeloeschteDatei_wirdNurAlsFehlendMarkiert() {
        let a = file(1)
        let b = file(2)
        let p = plan([known(10, a), known(11, b)], [a])
        XCTAssertEqual(p.missing, [11])
        XCTAssertTrue(p.offline.isEmpty)
    }

    func testLaufwerkGetrennt_offline_nichtFehlend() {
        let internalFile = file(1)
        let usbFile = file(2, path: "/Volumes/USB/Musik/", folder: usb)
        let p = plan([known(10, internalFile), known(11, usbFile)], [internalFile], online: [music])
        XCTAssertEqual(p.offline, [11])
        XCTAssertTrue(p.missing.isEmpty)
        XCTAssertEqual(p.offlineFolders, [usb])
    }

    func testLaufwerkWiederAngeschlossen_wirdWiederVerfuegbar() {
        let usbFile = file(2, path: "/Volumes/USB/Musik/", folder: usb)
        let p = plan([known(11, usbFile, available: false)], [usbFile], online: [music, usb])
        let item = p.items.first!
        XCTAssertEqual(item.uid, 11)
        XCTAssertFalse(item.readTags)
        XCTAssertTrue(item.reappeared)
        XCTAssertEqual(item.kind, .reappeared)
        XCTAssertEqual(p.reappearedItems.count, 1)
    }

    func testOrdnerErreichbarAberLeer_wirdWieOfflineBehandelt() {
        // z. B. fehlende Zugriffsrechte: kein einziger Titel gefunden → nichts als „fehlend“ werten
        let a = file(1, path: "/Volumes/USB/Musik/", folder: usb)
        let b = file(2, path: "/Volumes/USB/Musik/", folder: usb)
        let p = plan([known(10, a), known(11, b)], [], online: [music, usb])
        XCTAssertEqual(Set(p.offline), [10, 11])
        XCTAssertTrue(p.missing.isEmpty)
        XCTAssertEqual(p.offlineFolders, [usb])
    }

    func testLoeschenUndNeuKopieren_inSpaeteremAbgleich_wirdWiedererkannt() {
        let old = file(1, name: "Song.m4a", size: 9999)
        let other = file(2)
        // Erster Abgleich: Datei weg → fehlend
        let first = plan([known(10, old), known(20, other)], [other])
        XCTAssertEqual(first.missing, [10])
        // Zweiter Abgleich: neu kopiert (neuer Inode, gleicher Ort)
        let recopied = with(old, mod: 999, fileID: 500)
        let second = plan([known(10, old, available: false), known(20, other)], [recopied, other])
        XCTAssertEqual(second.items.first?.uid, 10)
        XCTAssertTrue(second.items.first!.reappeared)
    }

    func testPfadSchluessel_ohneGrossKlein_undNormalform() {
        XCTAssertEqual(SyncPlanner.pathKey("/Users/me/Music/A/Song.MP3"), "/users/me/music/a/song.mp3")
        // NFD (wie HFS+ liefert) und NFC ergeben denselben Schlüssel
        XCTAssertEqual(SyncPlanner.pathKey("/M/Bjo\u{0308}rk.mp3"), SyncPlanner.pathKey("/M/Bj\u{00F6}rk.mp3"))
        XCTAssertEqual(SyncPlanner.fileName(of: "/a/b/c.mp3"), "c.mp3")
    }

    func testNurSchreibweiseDesNamensGeaendert_behaeltKennung() {
        let old = file(1, name: "song.mp3")
        let renamed = with(old, path: "/Users/me/Music/A/Song.mp3", fileID: 999) // auch ohne Inode-Treffer
        let item = plan([known(10, old)], [renamed]).items.first!
        XCTAssertEqual(item.uid, 10)
        XCTAssertTrue(item.moved)
    }

    func testNormalformDesPfads_istKeineAenderung() {
        let nfc = file(1, name: "Bj\u{00F6}rk.mp3")
        let nfd = with(nfc, path: "/Users/me/Music/A/Bjo\u{0308}rk.mp3")
        let p = plan([known(10, nfc)], [nfd])
        XCTAssertEqual(p.unchangedCount, 1)
        XCTAssertTrue(p.items.isEmpty)
    }

    func testGrossKleinVerschiedeneDateien_exakterPfadHatVorrang() {
        // Laufwerk mit Unterscheidung von Groß-/Kleinschreibung: zwei verschiedene Dateien
        let upper = file(1, name: "A.mp3")
        let lower = file(2, name: "a.mp3")
        let p = plan([known(10, upper), known(20, lower)], [lower, upper])
        XCTAssertEqual(p.unchangedCount, 2)
        XCTAssertTrue(p.items.isEmpty)
    }

    func testUnzuverlaessigeKennungen_keineFalscheZuordnung() {
        // Android: Medienbibliothek neu aufgebaut. Mac: z. B. FAT-Laufwerk, dessen Kennungen sich ändern –
        // gleiche Kennung an anderer Stelle darf dann NICHT als derselbe Titel gelten.
        let a = file(1, name: "a.m4a", size: 5000)
        let b = file(2, name: "b.m4a", size: 6000)
        let scanned = [
            file(1, name: "n.m4a", size: 7000),  // Kennung 1 jetzt bei einer neuen Datei
            with(a, fileID: 2),
            with(b, fileID: 3),
        ]
        let p = plan([known(10, a), known(20, b)], scanned, trusted: [])
        let byName = Dictionary(uniqueKeysWithValues: p.items.map { ($0.file.fileName, $0) })
        XCTAssertEqual(byName["a.m4a"]?.uid, 10)
        XCTAssertEqual(byName["b.m4a"]?.uid, 20)
        XCTAssertNil(byName["n.m4a"]?.uid)
        XCTAssertTrue(p.missing.isEmpty)
    }

    func testGleicheKennungTrotzVertrauen_pfadHatVorrang_reihenfolgeEgal() {
        let a = file(1, name: "a.m4a", size: 5000)
        let b = file(2, name: "b.m4a", size: 6000)
        let scanned = [file(1, name: "n.m4a", size: 5000), with(a, fileID: 5), b]
        let p = plan([known(10, a), known(20, b)], scanned)
        let byName = Dictionary(uniqueKeysWithValues: p.items.map { ($0.file.fileName, $0) })
        XCTAssertEqual(byName["a.m4a"]?.uid, 10)
        XCTAssertNil(byName["n.m4a"]?.uid)
    }

    func testUmbenanntGleicheKennungUndGroesse_behaeltKennung() {
        let old = file(1, name: "alt.m4a", size: 5000)
        let renamed = with(old, path: "/Users/me/Music/B/neu.m4a")
        let item = plan([known(10, old)], [renamed]).items.first!
        XCTAssertEqual(item.uid, 10)
        XCTAssertTrue(item.relinked)
        XCTAssertFalse(item.readTags)
    }

    func testUmbenanntUndTagsGeaendert_gleicheGueltigeKennung_behaeltKennung() {
        let old = file(1, name: "01 alt.m4a", size: 5000, mod: 100)
        let changed = with(old, path: "/Users/me/Music/A/01 Neu.m4a", size: 5200, mod: 300)
        let item = plan([known(10, old)], [changed]).items.first!
        XCTAssertEqual(item.uid, 10)
        XCTAssertTrue(item.readTags)
        XCTAssertTrue(item.relinked)
        XCTAssertEqual(item.kind, .moved)
    }

    func testVerschobenZwischenOrdnernAufDemselbenLaufwerk_perKennung() {
        var old = file(1, path: "/Volumes/USB/Alt/", name: "x.flac", folder: usb)
        old.volumeID = "UUID-1"
        var moved = file(1, path: "/Users/me/Music/Neu/", name: "y.flac", size: 1, mod: 1)
        moved.volumeID = "UUID-1"
        let p = plan([known(10, old)], [moved], online: [music, usb])
        XCTAssertEqual(p.items.first?.uid, 10)
        XCTAssertTrue(p.items.first!.contentChanged)
    }

    func testReihenfolgeDerErgebnisse_wieGefunden() {
        let a = file(1)
        let b = file(2)
        let c = file(3)
        let p = plan([known(20, b)], [a, with(b, mod: 5), c])
        XCTAssertEqual(p.items.map(\.file.path), [a.path, b.path, c.path])
    }
}
