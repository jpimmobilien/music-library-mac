import XCTest
@testable import MLCore

final class ResumeRuleTests: XCTestCase {

    private func saved(_ uids: [Int64], current: Int, position: Int64) -> SavedPlaybackState {
        var q = PlayQueue()
        q.replace(with: uids, startIndex: current, shuffle: .off)
        return SavedPlaybackState(queue: q, positionMs: position, savedAt: 1_000)
    }

    func testStart_stelltWarteschlangeTitelUndPositionWiederHer() {
        let s = saved([1, 2, 3], current: 1, position: 42_000)
        let r = ResumeRule.restoreOnLaunch(s, enabled: true, isAvailable: { _ in true }, durationOf: { _ in 200_000 })!
        XCTAssertEqual(r.queue.currentTrackUid, 2)
        XCTAssertEqual(r.positionMs, 42_000)
        XCTAssertEqual(r.queue.items.map(\.trackUid), [1, 2, 3])
    }

    func testStart_ausgeschaltet_oderNichtsGespeichert() {
        let s = saved([1], current: 0, position: 5)
        XCTAssertNil(ResumeRule.restoreOnLaunch(s, enabled: false, isAvailable: { _ in true }, durationOf: { _ in nil }))
        XCTAssertNil(ResumeRule.restoreOnLaunch(nil, enabled: true, isAvailable: { _ in true }, durationOf: { _ in nil }))
        XCTAssertNil(ResumeRule.restoreOnLaunch(saved([], current: 0, position: 0), enabled: true, isAvailable: { _ in true }, durationOf: { _ in nil }))
    }

    func testStart_fehlenderLaufenderTitel_naechsterBeginntBeiNull() {
        let s = saved([1, 2, 3], current: 1, position: 42_000)
        let r = ResumeRule.restoreOnLaunch(s, enabled: true, isAvailable: { $0 != 2 }, durationOf: { _ in 200_000 })!
        XCTAssertEqual(r.queue.currentTrackUid, 3)
        XCTAssertEqual(r.positionMs, 0)
        XCTAssertEqual(r.queue.items.map(\.trackUid), [1, 3])
        // nichts mehr verfügbar
        XCTAssertNil(ResumeRule.restoreOnLaunch(s, enabled: true, isAvailable: { _ in false }, durationOf: { _ in nil }))
        // anderer Titel fehlt: Position bleibt
        let r2 = ResumeRule.restoreOnLaunch(s, enabled: true, isAvailable: { $0 != 1 }, durationOf: { _ in 200_000 })!
        XCTAssertEqual(r2.queue.currentTrackUid, 2)
        XCTAssertEqual(r2.positionMs, 42_000)
    }

    func testStart_positionAmEnde_oderUngueltig() {
        let atEnd = saved([1], current: 0, position: 199_500)
        XCTAssertEqual(ResumeRule.restoreOnLaunch(atEnd, enabled: true, isAvailable: { _ in true }, durationOf: { _ in 200_000 })?.positionMs, 0)
        let negative = saved([1], current: 0, position: -50)
        XCTAssertEqual(ResumeRule.restoreOnLaunch(negative, enabled: true, isAvailable: { _ in true }, durationOf: { _ in nil })?.positionMs, 0)
        let unknownDuration = saved([1], current: 0, position: 999_999)
        XCTAssertEqual(ResumeRule.restoreOnLaunch(unknownDuration, enabled: true, isAvailable: { _ in true }, durationOf: { _ in nil })?.positionMs, 999_999)
    }

    func testGespeicherterZustand_codable() throws {
        let s = saved([4, 5], current: 1, position: 1234)
        let back = try JSONDecoder().decode(SavedPlaybackState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    func testLangeTitel_positionMerken() {
        let long: Int64 = 60 * 60_000 // 1 h
        XCTAssertTrue(ResumeRule.isLongTrack(durationMs: 600_000))
        XCTAssertFalse(ResumeRule.isLongTrack(durationMs: 599_999))
        XCTAssertEqual(ResumeRule.update(positionMs: 30_000, durationMs: long, finished: false), .save(positionMs: 30_000))
        XCTAssertEqual(ResumeRule.update(positionMs: 29_999, durationMs: long, finished: false), .keep)
        XCTAssertEqual(ResumeRule.update(positionMs: long - 30_000, durationMs: long, finished: false), .save(positionMs: long - 30_000))
        XCTAssertEqual(ResumeRule.update(positionMs: long - 29_999, durationMs: long, finished: false), .clear)
        XCTAssertEqual(ResumeRule.update(positionMs: 1_000_000, durationMs: long, finished: true), .clear)
        // kurze Titel: nie
        XCTAssertEqual(ResumeRule.update(positionMs: 120_000, durationMs: 300_000, finished: false), .keep)
        XCTAssertEqual(ResumeRule.update(positionMs: 300_000, durationMs: 300_000, finished: true), .keep)
    }

    func testLangeTitel_anwendenUndStartposition() {
        let long: Int64 = 30 * 60_000
        let p = ResumeRule.apply(.save(positionMs: 600_000), to: nil, trackUid: 7, now: 99)
        XCTAssertEqual(p, ResumePoint(trackUid: 7, positionMs: 600_000, updatedAt: 99))
        XCTAssertEqual(ResumeRule.apply(.keep, to: p, trackUid: 7, now: 100), p)
        XCTAssertNil(ResumeRule.apply(.clear, to: p, trackUid: 7, now: 100))
        XCTAssertEqual(ResumeRule.startPosition(durationMs: long, point: p), 600_000)
        XCTAssertEqual(ResumeRule.startPosition(durationMs: long, point: nil), 0)
        // Datei inzwischen kürzer (ersetzt) → gemerkte Stelle ungültig
        XCTAssertEqual(ResumeRule.startPosition(durationMs: 620_000, point: p), 0)
        // kurzer Titel → immer von vorn
        XCTAssertEqual(ResumeRule.startPosition(durationMs: 300_000, point: ResumePoint(trackUid: 7, positionMs: 60_000, updatedAt: 0)), 0)
    }
}

final class HistoryRuleTests: XCTestCase {

    func testVerlauf_abFuenfSekundenOderGezaehlt() {
        XCTAssertFalse(HistoryRule.shouldRecord(listenedMs: 4_999, durationMs: 240_000))
        XCTAssertTrue(HistoryRule.shouldRecord(listenedMs: 5_000, durationMs: 240_000))
        // sehr kurzer Titel: PlayCountRule (Hälfte, min. 1 s) schon vor 5 s erreicht
        XCTAssertTrue(HistoryRule.shouldRecord(listenedMs: 2_000, durationMs: 4_000))
        XCTAssertFalse(HistoryRule.shouldRecord(listenedMs: 900, durationMs: 1_500))
        XCTAssertTrue(HistoryRule.shouldRecord(listenedMs: 0, durationMs: 0, counted: true))
    }

    func testEintrag_mitZaehlung() {
        let notCounted = HistoryRule.entry(id: 1, trackUid: 5, startedAt: 1_000, listenedMs: 10_000, durationMs: 240_000)!
        XCTAssertFalse(notCounted.counted)
        XCTAssertEqual(notCounted.playedAt, 1_000)
        XCTAssertEqual(notCounted.listenedMs, 10_000)
        let counted = HistoryRule.entry(id: 2, trackUid: 5, startedAt: 1_000, listenedMs: 30_000, durationMs: 240_000)!
        XCTAssertTrue(counted.counted)
        XCTAssertNil(HistoryRule.entry(id: 3, trackUid: 5, startedAt: 0, listenedMs: 3_000, durationMs: 240_000))
    }

    func testStatistik_wieAndroidRecordPlay() {
        let first = HistoryRule.recordingCountedPlay(nil, trackUid: 9, now: 500, listenedMs: 30_000)
        XCTAssertEqual(first, PlayStats(trackUid: 9, playCount: 1, lastPlayedAt: 500, firstPlayedAt: 500, totalListenedMs: 30_000))
        let second = HistoryRule.recordingCountedPlay(first, trackUid: 9, now: 900, listenedMs: -5)
        XCTAssertEqual(second, PlayStats(trackUid: 9, playCount: 2, lastPlayedAt: 900, firstPlayedAt: 500, totalListenedMs: 30_000))
    }

    func testSitzung_zaehltEinmal_undSchreibtVerlauf() {
        var s = PlaySession(trackUid: 3, startedAt: 1_700_000_000_000, nowMonotonic: 0, playing: true)
        XCTAssertNil(s.countIfDue(nowMonotonic: 10_000, nowWall: 1, durationMs: 200_000, stats: nil))
        s.setPlaying(false, nowMonotonic: 10_000)
        s.setPlaying(true, nowMonotonic: 50_000)
        let stats = s.countIfDue(nowMonotonic: 70_000, nowWall: 2_000, durationMs: 200_000, stats: nil)
        XCTAssertEqual(stats?.playCount, 1)
        XCTAssertEqual(stats?.totalListenedMs, 30_000)
        XCTAssertNil(s.countIfDue(nowMonotonic: 80_000, nowWall: 3_000, durationMs: 200_000, stats: stats))
        let entry = s.finish(id: 11, nowMonotonic: 100_000, durationMs: 200_000)!
        XCTAssertTrue(entry.counted)
        XCTAssertEqual(entry.listenedMs, 60_000)
        XCTAssertEqual(entry.playedAt, 1_700_000_000_000)
    }

    func testSitzung_kurzAngespielt_keinEintrag() {
        let s = PlaySession(trackUid: 3, startedAt: 0, nowMonotonic: 0, playing: true)
        XCTAssertNil(s.finish(id: 1, nowMonotonic: 4_000, durationMs: 200_000))
        XCTAssertFalse(s.counted)
    }
}
