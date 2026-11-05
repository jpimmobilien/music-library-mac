import XCTest
@testable import MLCore

final class PlayQueueTests: XCTestCase {

    private var rng = SeededRandom(seed: 42)
    private let source = PlaybackSource(kind: .album, label: "Album")

    private func queue(_ uids: [Int64], start: Int? = 0, shuffle: ShuffleStart = .off, repeatMode: RepeatSetting = .off) -> PlayQueue {
        var q = PlayQueue()
        q.repeatMode = repeatMode
        q.replace(with: uids, startIndex: start, shuffle: shuffle, source: source, using: &rng)
        return q
    }

    private func uids(_ items: [PlayQueue.Item]) -> [Int64] { items.map(\.trackUid) }

    // MARK: - Aufbau

    func testNeueWarteschlange_listenreihenfolge() {
        let q = queue([10, 20, 30], start: 1)
        XCTAssertEqual(q.currentTrackUid, 20)
        XCTAssertEqual(q.currentIndex, 1)
        XCTAssertEqual(uids(q.upNext), [30])
        XCTAssertEqual(uids(q.history), [10])
        XCTAssertEqual(q.source, source)
        XCTAssertFalse(q.shuffleEnabled)
    }

    func testEintraegeHabenEigeneKennungen_doppelteTitelErlaubt() {
        let q = queue([7, 8, 7])
        XCTAssertEqual(Set(q.items.map(\.id)).count, 3)
        XCTAssertEqual(uids(q.items), [7, 8, 7])
    }

    func testLeereListe_leereWarteschlange() {
        var q = queue([1, 2])
        q.replace(with: [], startIndex: 0, shuffle: .off, using: &rng)
        XCTAssertTrue(q.isEmpty)
        XCTAssertNil(q.current)
        XCTAssertFalse(q.skipToNext())
        XCTAssertEqual(q.previous(positionMs: 0), .none)
        XCTAssertEqual(q.advanceAfterCompletion(), .none)
        XCTAssertEqual(q.upNext, [])
    }

    func testStartIndexWirdBegrenzt() {
        XCTAssertEqual(queue([1, 2, 3], start: 9).currentTrackUid, 3)
        XCTAssertEqual(queue([1, 2, 3], start: -4).currentTrackUid, 1)
        XCTAssertEqual(queue([1, 2, 3], start: nil).currentTrackUid, 1)
    }

    func testMischen_starttitelVorn_alleGenauEinmal() {
        for seed in 0..<30 {
            rng = SeededRandom(seed: UInt64(seed))
            let q = queue(Array(1...9), start: 4, shuffle: .on)
            XCTAssertTrue(q.shuffleEnabled)
            XCTAssertEqual(q.currentTrackUid, 5)
            XCTAssertEqual(q.currentPlayPosition, 0)
            XCTAssertEqual(Set(uids(q.upNext)), Set([1, 2, 3, 4, 6, 7, 8, 9]))
            XCTAssertEqual(q.upNext.count, 8)
            XCTAssertTrue(q.history.isEmpty)
        }
    }

    func testMischenOhneStart_beginntMitErstemDerZufallsfolge() {
        let q = queue([1, 2, 3, 4], start: nil, shuffle: .on)
        XCTAssertEqual(q.currentIndex, q.playOrder.first)
        XCTAssertEqual(q.upNext.count, 3)
    }

    func testKeep_behaeltZufallsmodus() {
        var q = queue([1, 2, 3], shuffle: .on)
        q.replace(with: [5, 6, 7, 8], startIndex: 2, shuffle: .keep, using: &rng)
        XCTAssertTrue(q.shuffleEnabled)
        XCTAssertEqual(q.currentTrackUid, 7) // angeklickter Titel beginnt
        XCTAssertEqual(q.currentPlayPosition, 0)
        var off = queue([1, 2, 3])
        off.replace(with: [5, 6, 7], startIndex: 1, shuffle: .keep, using: &rng)
        XCTAssertFalse(off.shuffleEnabled)
        XCTAssertEqual(off.currentTrackUid, 6)
    }

    func testPlay_mitQueuePlan() {
        var q = PlayQueue()
        let plan = QueuePlan.tapped([3, 4, 5], tappedIndex: 2, source: source)!
        q.play(plan, using: &rng)
        XCTAssertEqual(q.currentTrackUid, 5)
        XCTAssertEqual(q.source, source)
    }

    // MARK: - Blättern

    func testNaechster_ohneWiederholung_endetAmEnde() {
        var q = queue([1, 2, 3])
        XCTAssertTrue(q.hasNext)
        XCTAssertTrue(q.skipToNext())
        XCTAssertTrue(q.skipToNext())
        XCTAssertEqual(q.currentTrackUid, 3)
        XCTAssertFalse(q.hasNext)
        XCTAssertFalse(q.skipToNext())
        XCTAssertEqual(q.currentTrackUid, 3)
    }

    func testNaechster_mitQuelleWiederholen_beginntVonVorn() {
        var q = queue([1, 2, 3], start: 2, repeatMode: .all)
        XCTAssertTrue(q.hasNext)
        XCTAssertTrue(q.skipToNext())
        XCTAssertEqual(q.currentTrackUid, 1)
    }

    func testNaechster_mitTitelWiederholen_wieAus() {
        var q = queue([1, 2], start: 1, repeatMode: .one)
        XCTAssertFalse(q.hasNext) // wie Media3: beim Blättern zählt „Titel wiederholen“ wie „aus“
        XCTAssertFalse(q.skipToNext())
        var q2 = queue([1, 2], start: 0, repeatMode: .one)
        XCTAssertTrue(q2.skipToNext())
        XCTAssertEqual(q2.currentTrackUid, 2)
    }

    func testVorheriger_dreiSekundenRegel() {
        var q = queue([1, 2, 3], start: 1)
        XCTAssertEqual(q.previous(positionMs: 3_001), .restartCurrent)
        XCTAssertEqual(q.currentTrackUid, 2)
        XCTAssertEqual(q.previous(positionMs: 3_000), .movedToPrevious)
        XCTAssertEqual(q.currentTrackUid, 1)
        // am Anfang ohne Wiederholung: an den Anfang des Titels
        XCTAssertEqual(q.previous(positionMs: 0), .restartCurrent)
        XCTAssertEqual(q.currentTrackUid, 1)
        // mit „Quelle wiederholen“: zum letzten
        q.repeatMode = .all
        XCTAssertTrue(q.hasPrevious)
        XCTAssertEqual(q.previous(positionMs: 500), .movedToPrevious)
        XCTAssertEqual(q.currentTrackUid, 3)
    }

    func testBlaettern_imZufallsmodus_folgtDerZufallsreihenfolge() {
        let q0 = queue(Array(1...6), start: 2, shuffle: .on)
        var q = q0
        var visited = [q.currentTrackUid!]
        while q.skipToNext() { visited.append(q.currentTrackUid!) }
        XCTAssertEqual(visited, uids(q0.itemsInPlayOrder))
        XCTAssertEqual(visited.first, 3)
        // zurück
        XCTAssertEqual(q.previous(positionMs: 0), .movedToPrevious)
        XCTAssertEqual(q.currentTrackUid, visited[visited.count - 2])
    }

    func testTitelende_allePfade() {
        var q = queue([1, 2], repeatMode: .off)
        XCTAssertEqual(q.advanceAfterCompletion(), .advanced(wrapped: false))
        XCTAssertEqual(q.currentTrackUid, 2)
        XCTAssertEqual(q.advanceAfterCompletion(), .endOfQueue)
        XCTAssertEqual(q.currentTrackUid, 2) // bleibt beim letzten
        q.rewindToStart()
        XCTAssertEqual(q.currentTrackUid, 1)

        q.repeatMode = .all
        _ = q.advanceAfterCompletion()
        XCTAssertEqual(q.advanceAfterCompletion(), .advanced(wrapped: true))
        XCTAssertEqual(q.currentTrackUid, 1)

        q.repeatMode = .one
        XCTAssertEqual(q.advanceAfterCompletion(), .repeatCurrent)
        XCTAssertEqual(q.currentTrackUid, 1)
    }

    func testEndeImZufallsmodus_vonVornBeginntMitErstemDerZufallsfolge() {
        var q = queue(Array(1...5), start: 3, shuffle: .on)
        while case .advanced = q.advanceAfterCompletion() {}
        XCTAssertEqual(q.currentIndex, q.playOrder.last)
        q.rewindToStart()
        XCTAssertEqual(q.currentTrackUid, 4)
    }

    func testSprungZuEintrag() {
        var q = queue([1, 2, 3, 2])
        let target = q.items[3]
        XCTAssertTrue(q.jump(toItemID: target.id))
        XCTAssertEqual(q.currentIndex, 3) // die zweite 2, nicht die erste
        XCTAssertFalse(q.jump(toItemID: 9999))
    }

    func testUpcoming_wieAndroid() {
        var q = queue([1, 2, 3, 4], start: 2)
        XCTAssertEqual(uids(q.upcoming()), [3, 4])
        q.repeatMode = .all
        XCTAssertEqual(uids(q.upcoming()), [3, 4, 1, 2]) // einmal ringsum
        XCTAssertEqual(uids(q.upcoming(limit: 2)), [3, 4])
    }

    // MARK: - Zufall umschalten

    func testZufallEinschalten_laufenderBleibt_undStehtVorn() {
        var q = queue([1, 2, 3, 4, 5], start: 3)
        q.setShuffle(true, using: &rng)
        XCTAssertEqual(q.currentTrackUid, 4)
        XCTAssertEqual(q.currentPlayPosition, 0)
        XCTAssertEqual(Set(uids(q.upNext)), [1, 2, 3, 5])
        XCTAssertTrue(q.history.isEmpty)
        // Ausschalten: Listenreihenfolge, laufender bleibt
        _ = q.skipToNext()
        let now = q.currentTrackUid
        q.setShuffle(false, using: &rng)
        XCTAssertEqual(q.currentTrackUid, now)
        XCTAssertEqual(q.playOrder, [0, 1, 2, 3, 4])
        XCTAssertEqual(q.shuffleOrder, .empty)
    }

    func testZufallNochmalEinschalten_aendertNichts() {
        var q = queue([1, 2, 3, 4], shuffle: .on)
        let order = q.playOrder
        q.setShuffle(true, using: &rng)
        XCTAssertEqual(q.playOrder, order)
    }

    // MARK: - Hinzufügen

    func testAlsNaechstes_direktHinterDemLaufenden() {
        var q = queue([1, 2, 3], start: 0)
        q.playNext([9])
        XCTAssertEqual(uids(q.upNext), [9, 2, 3])
        q.playNext([8])
        XCTAssertEqual(uids(q.upNext), [8, 9, 2, 3]) // zuletzt gewählter zuerst
        XCTAssertEqual(q.currentTrackUid, 1)
    }

    func testAlsNaechstes_imZufallsmodus_direktHinterDemLaufenden() {
        var q = queue(Array(1...6), start: 1, shuffle: .on)
        _ = q.skipToNext()
        _ = q.skipToNext()
        let current = q.currentTrackUid
        let before = uids(q.upNext)
        q.playNext([70, 71])
        XCTAssertEqual(q.currentTrackUid, current)
        XCTAssertEqual(uids(q.upNext), [70, 71] + before)
        XCTAssertEqual(q.items.count, 8)
        XCTAssertEqual(Set(q.playOrder), Set(0..<8))
    }

    func testZurWarteschlange_amEndeDerAbspielfolge() {
        var q = queue([1, 2, 3], start: 1)
        q.addToEnd([7, 8])
        XCTAssertEqual(uids(q.upNext), [3, 7, 8])
        var s = queue(Array(1...5), start: 0, shuffle: .on)
        let before = uids(s.upNext)
        s.addToEnd([9])
        XCTAssertEqual(uids(s.upNext), before + [9])
    }

    func testHinzufuegenZuLeererWarteschlange_startetDamit() {
        var q = PlayQueue()
        q.playNext([5])
        XCTAssertEqual(q.currentTrackUid, 5)
        var q2 = PlayQueue()
        q2.setShuffle(true, using: &rng)
        q2.addToEnd([5, 6])
        XCTAssertEqual(q2.currentTrackUid, 5)
        XCTAssertEqual(q2.playOrder, [0, 1])
        XCTAssertEqual(q.playNext([]), [])
    }

    // MARK: - Entfernen

    func testEntfernen_nichtLaufend() {
        var q = queue([1, 2, 3, 4], start: 2)
        XCTAssertEqual(q.remove(itemID: q.items[0].id), .unchanged)
        XCTAssertEqual(q.currentTrackUid, 3)
        XCTAssertEqual(q.currentIndex, 1)
        XCTAssertEqual(uids(q.items), [2, 3, 4])
        XCTAssertEqual(q.remove(itemID: 12345), .unchanged)
    }

    func testEntfernen_laufend_naechsterWirdLaufend() {
        var q = queue([1, 2, 3, 4], start: 1)
        XCTAssertEqual(q.remove(itemID: q.items[1].id), .changed(continuePlayback: true))
        XCTAssertEqual(q.currentTrackUid, 3)
    }

    func testEntfernen_laufenderLetzter_ohneWiederholung_halten() {
        var q = queue([1, 2, 3], start: 2)
        XCTAssertEqual(q.remove(itemID: q.items[2].id), .changed(continuePlayback: false))
        XCTAssertEqual(q.currentTrackUid, 1) // Anfang der Abspielfolge, angehalten
        var r = queue([1, 2, 3], start: 2, repeatMode: .all)
        XCTAssertEqual(r.remove(itemID: r.items[2].id), .changed(continuePlayback: true))
        XCTAssertEqual(r.currentTrackUid, 1)
    }

    func testEntfernen_alle_leer() {
        var q = queue([1, 1])
        XCTAssertEqual(q.removeAll(trackUid: 1), .emptied)
        XCTAssertTrue(q.isEmpty)
        XCTAssertNil(q.currentIndex)
    }

    func testEntfernen_geloeschterTitel_alleVorkommen_imZufallsmodus() {
        var q = queue([1, 2, 3, 2, 4], start: 0, shuffle: .on)
        let orderBefore = uids(q.itemsInPlayOrder).filter { $0 != 2 }
        XCTAssertEqual(q.removeAll(trackUid: 2), .unchanged)
        XCTAssertEqual(uids(q.items), [1, 3, 4])
        XCTAssertEqual(uids(q.itemsInPlayOrder), orderBefore) // übrige Reihenfolge bleibt
        XCTAssertEqual(q.currentTrackUid, 1)
    }

    func testEntfernen_laufend_imZufallsmodus_naechsterDerZufallsfolge() {
        var q = queue(Array(1...6), start: 0, shuffle: .on)
        let expectedNext = q.upNext[0].trackUid
        XCTAssertEqual(q.remove(itemID: q.current!.id), .changed(continuePlayback: true))
        XCTAssertEqual(q.currentTrackUid, expectedNext)
    }

    // MARK: - Umsortieren

    func testUmsortieren_alsNaechstes_ohneZufall() {
        var q = queue([1, 2, 3, 4, 5], start: 1)
        XCTAssertTrue(q.moveUpNext(from: 2, to: 0)) // 5 nach vorn
        XCTAssertEqual(uids(q.upNext), [5, 3, 4])
        XCTAssertEqual(uids(q.items), [1, 2, 5, 3, 4])
        XCTAssertEqual(q.currentTrackUid, 2)
        XCTAssertFalse(q.moveUpNext(from: 3, to: 0))
        XCTAssertFalse(q.moveUpNext(from: 0, to: -1))
    }

    func testUmsortieren_alsNaechstes_mitZufall_listeBleibt() {
        var q = queue(Array(1...5), start: 0, shuffle: .on)
        let list = uids(q.items)
        let up = uids(q.upNext)
        XCTAssertTrue(q.moveUpNext(from: 0, to: 3))
        XCTAssertEqual(uids(q.upNext), [up[1], up[2], up[3], up[0]])
        XCTAssertEqual(uids(q.items), list)
        XCTAssertEqual(q.currentTrackUid, 1)
    }

    func testUmsortieren_ueberDenLaufendenHinweg_ohneZufall() {
        var q = queue([1, 2, 3, 4], start: 1)
        XCTAssertTrue(q.movePlayPosition(from: 0, to: 3)) // 1 ans Ende
        XCTAssertEqual(uids(q.items), [2, 3, 4, 1])
        XCTAssertEqual(q.currentTrackUid, 2)
        XCTAssertEqual(q.currentIndex, 0)
    }

    // MARK: - Speichern

    func testSpeichernUndLaden() throws {
        var q = queue(Array(1...6), start: 2, shuffle: .on, repeatMode: .all)
        _ = q.skipToNext()
        q.playNext([99])
        let data = try JSONEncoder().encode(q)
        var restored = try JSONDecoder().decode(PlayQueue.self, from: data)
        XCTAssertEqual(restored, q)
        // neue Einträge bekommen weiterhin eindeutige Kennungen
        let added = restored.addToEnd([100])
        XCTAssertFalse(q.items.map(\.id).contains(added[0].id))
    }

    func testLadenTolerant_defekteAngabenWerdenKorrigiert() throws {
        let json = #"""
        {"items":[{"id":1,"trackUid":10},{"id":1,"trackUid":11},{"id":2,"trackUid":12}],
         "currentIndex":7,"shuffleEnabled":true,"shuffleOrder":[0,0,1],"repeatMode":"WHATEVER"}
        """#
        let q = try JSONDecoder().decode(PlayQueue.self, from: Data(json.utf8))
        XCTAssertEqual(Set(q.items.map(\.id)).count, 3)
        XCTAssertEqual(q.currentIndex, 0)
        XCTAssertEqual(q.repeatMode, .off)
        XCTAssertTrue(q.shuffleEnabled)
        XCTAssertEqual(q.playOrder.first, 0)
        XCTAssertEqual(Set(q.playOrder), [0, 1, 2])
        let empty = try JSONDecoder().decode(PlayQueue.self, from: Data("{}".utf8))
        XCTAssertTrue(empty.isEmpty)
    }
}
