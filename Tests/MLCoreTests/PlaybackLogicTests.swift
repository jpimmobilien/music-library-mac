import XCTest
@testable import MLCore

/// Portierung von `playback/PlaybackLogicTest.kt` (plus Pitch-Tempo und Vorheriger-Regel).
final class PlaybackLogicTests: XCTestCase {

    func testWiedergabeZaehlt_haelfteOderDreissigSekunden() {
        XCTAssertEqual(PlayCountRule.requiredListenMs(durationMs: 240_000), 30_000)
        XCTAssertEqual(PlayCountRule.requiredListenMs(durationMs: 20_000), 10_000)
        XCTAssertEqual(PlayCountRule.requiredListenMs(durationMs: 1_500), 1_000)
        XCTAssertEqual(PlayCountRule.requiredListenMs(durationMs: 0), 30_000)
        XCTAssertTrue(PlayCountRule.counts(listenedMs: 30_000, durationMs: 240_000))
        XCTAssertFalse(PlayCountRule.counts(listenedMs: 29_999, durationMs: 240_000))
    }

    func testHoerzeit_nurWaehrendWiedergabe_einmalGezaehlt() {
        var t = ListenTracker()
        t.start(1, nowMs: 0, playing: true)
        XCTAssertFalse(t.shouldCount(nowMs: 20_000, durationMs: 240_000))
        t.setPlaying(false, nowMs: 20_000)
        // Pause zählt nicht
        XCTAssertFalse(t.shouldCount(nowMs: 100_000, durationMs: 240_000))
        t.setPlaying(true, nowMs: 100_000)
        XCTAssertTrue(t.shouldCount(nowMs: 110_000, durationMs: 240_000))
        // nur einmal
        XCTAssertFalse(t.shouldCount(nowMs: 200_000, durationMs: 240_000))
        // neuer Titel startet neu
        t.start(2, nowMs: 200_000, playing: true)
        XCTAssertFalse(t.counted)
        XCTAssertEqual(t.listened(nowMs: 205_000), 5_000)
    }

    func testOhneTitel_wirdNichtsGezaehlt() {
        var t = ListenTracker()
        t.start(nil, nowMs: 0, playing: true)
        XCTAssertFalse(t.shouldCount(nowMs: 100_000, durationMs: 1_000))
        XCTAssertEqual(t.listened(nowMs: 100_000), 0)
    }

    func testNurDiesenTitel_wirdAlleinAbgespielt() {
        let plan = QueuePlan.single(42, title: "Song")
        XCTAssertEqual(plan.trackUids, [42])
        XCTAssertEqual(plan.startIndex, 0)
        XCTAssertEqual(plan.shuffle, .off)
        XCTAssertEqual(plan.source.kind, .singleTrack)
    }

    func testAngetippterTitel_startetDieGanzeListe() {
        let source = PlaybackSource(kind: .list, label: "Alle Titel")
        let plan = QueuePlan.tapped([10, 20, 30, 40], tappedIndex: 2, source: source)!
        XCTAssertEqual(plan.trackUids, [10, 20, 30, 40])
        XCTAssertEqual(plan.startIndex, 2)
        // Zufall wird nicht verändert (ist er an, beginnt der angetippte Titel)
        XCTAssertEqual(plan.shuffle, .keep)
        XCTAssertNil(QueuePlan.tapped([], tappedIndex: 0, source: source))
        // Position außerhalb wird begrenzt
        XCTAssertEqual(QueuePlan.tapped([1, 2, 3, 4], tappedIndex: 9, source: source)!.startIndex, 3)
    }

    func testPlaylistMitDoppeltemTitel_startetAnDerAngetipptenStelle() {
        let source = PlaybackSource(kind: .playlist, label: "Playlist")
        let plan = QueuePlan.tapped([7, 8, 7, 9], tappedIndex: 2, source: source)!
        XCTAssertEqual(plan.startIndex, 2) // nicht die erste 7
    }

    func testAlbumAbTitel_undMischen() {
        let source = PlaybackSource(kind: .album, label: "Album")
        let plan = QueuePlan.fromSource([1, 2, 3], startUid: 2, shuffle: false, source: source)!
        XCTAssertEqual(plan.startIndex, 1)
        XCTAssertEqual(plan.shuffle, .off)
        let shuffled = QueuePlan.fromSource([1, 2, 3], startUid: nil, shuffle: true, source: source)!
        XCTAssertEqual(shuffled.shuffle, .on)
        // „Mischen“: zufälliger Starttitel (steht dann vorn in der Zufallsreihenfolge)
        XCTAssertTrue((0...2).contains(shuffled.startIndex!))
        let starts = Set((0..<40).map { seed -> Int in
            var rng = SeededRandom(seed: UInt64(seed))
            return QueuePlan.fromSource([1, 2, 3, 4, 5], startUid: nil, shuffle: true, source: source, using: &rng)!.startIndex!
        })
        XCTAssertGreaterThanOrEqual(starts.count, 4, "Starttitel ist tatsächlich zufällig: \(starts)")
        // „Abspielen“ beginnt immer vorn
        XCTAssertEqual(QueuePlan.fromSource([1, 2, 3], startUid: nil, shuffle: false, source: source)!.startIndex, 0)
        XCTAssertNil(QueuePlan.fromSource([], startUid: nil, shuffle: false, source: source))
    }

    func testFehlendeTitel_werdenEntfernt_undStartWandertMit() {
        let source = PlaybackSource(kind: .list, label: "Liste")
        let plan = QueuePlan.tapped([1, 2, 3, 4, 5], tappedIndex: 3, source: source)! // Start bei 4
        let filtered = QueuePlan.filterAvailable(plan) { $0 != 2 }!
        XCTAssertEqual(filtered.trackUids, [1, 3, 4, 5])
        XCTAssertEqual(filtered.startIndex, 2) // weiterhin Titel 4
        // Starttitel selbst fehlt → nächster verbliebener
        let gone = QueuePlan.filterAvailable(plan) { $0 != 4 }!
        XCTAssertEqual(gone.trackUids[gone.startIndex!], 5)
        // Starttitel war der letzte und fehlt → letzter verbliebener
        let last = QueuePlan.filterAvailable(QueuePlan.tapped([1, 2, 3], tappedIndex: 2, source: source)!) { $0 != 3 }!
        XCTAssertEqual(last.startIndex, 1)
        XCTAssertNil(QueuePlan.filterAvailable(plan) { _ in false })
    }

    func testZufallsreihenfolge_starttitelVorn_alleGenauEinmal() {
        for seed in 0..<50 {
            let n = 1 + seed % 17
            let first = seed % n
            var rng = SeededRandom(seed: UInt64(seed))
            let order = ShuffleLogic.create(length: n, first: first, using: &rng)
            XCTAssertEqual(order[0], first)
            XCTAssertEqual(Set(order), Set(0..<n))
            XCTAssertEqual(order.count, n)
        }
        // ohne Startposition: trotzdem eine vollständige Reihenfolge
        var rng = SeededRandom(seed: 3)
        let free = ShuffleLogic.create(length: 8, first: nil, using: &rng)
        XCTAssertEqual(Set(free), Set(0..<8))
        XCTAssertEqual(ShuffleLogic.create(length: 0, first: 0, using: &rng), [])
        // Reihenfolge ist tatsächlich gemischt (nicht immer 0,1,2,…)
        let orders = Set((0..<20).map { seed -> [Int] in
            var r = SeededRandom(seed: UInt64(seed))
            return ShuffleLogic.create(length: 10, first: 0, using: &r)
        })
        XCTAssertGreaterThan(orders.count, 15)
    }

    func testAlsNaechstesEingereiht_folgtImZufallDirektAufDenLaufendenTitel() {
        // Liste 0..4, Zufallsreihenfolge [2, 0, 4, 1, 3], es läuft Position 2
        let order = [2, 0, 4, 1, 3]
        // „Als Nächstes“: Einfügen hinter dem laufenden Titel (Listenposition 3)
        let after = ShuffleLogic.insert(order, insertionIndex: 3, count: 1)
        // alte Positionen ≥ 3 rücken auf: 3→4, 4→5; neuer Titel = 3 direkt hinter der 2
        XCTAssertEqual(after, [2, 3, 0, 5, 1, 4])
        // Einfügen ganz vorn landet am Anfang der Zufallsreihenfolge
        XCTAssertEqual(ShuffleLogic.insert(order, insertionIndex: 0, count: 1), [0, 3, 1, 5, 2, 4])
    }

    func testEntfernen_ausDerZufallsreihenfolge() {
        let order = [2, 0, 4, 1, 3]
        XCTAssertEqual(ShuffleLogic.remove(order, from: 2, toExclusive: 3), [0, 3, 1, 2])
        XCTAssertEqual(ShuffleLogic.remove(order, from: 2, toExclusive: 5), [0, 1])
    }

    func testStartFirstShuffleOrder_navigation() {
        let s = StartFirstShuffleOrder(order: [2, 0, 1])!
        XCTAssertEqual(s.firstIndex, 2)
        XCTAssertEqual(s.lastIndex, 1)
        XCTAssertEqual(s.nextIndex(after: 2), 0)
        XCTAssertEqual(s.nextIndex(after: 0), 1)
        XCTAssertNil(s.nextIndex(after: 1))
        XCTAssertNil(s.previousIndex(before: 2))
        XCTAssertEqual(s.previousIndex(before: 1), 0)
        XCTAssertNil(StartFirstShuffleOrder(order: [0, 0, 1]))
        XCTAssertNil(StartFirstShuffleOrder(order: [0, 3]))
        XCTAssertEqual(s.appending(count: 2).order, [2, 0, 1, 3, 4])
        XCTAssertEqual(s.removing(from: 0, toExclusive: 1).order, [1, 0])
        XCTAssertEqual(s.inserting(at: 3, count: 1).order, [2, 3, 0, 1]) // hinter dem Vorgänger (Liste 2)
    }

    func testSleepTimer_countdownUndAusblenden() {
        let s = SleepTimerLogic.start(nowElapsed: 1_000, minutes: 15)
        XCTAssertEqual(SleepTimerLogic.remainingMs(s, nowElapsed: 1_000), 15 * 60_000)
        XCTAssertFalse(SleepTimerLogic.isExpired(s, nowElapsed: 1_000 + 15 * 60_000 - 1))
        XCTAssertTrue(SleepTimerLogic.isExpired(s, nowElapsed: 1_000 + 15 * 60_000))
        XCTAssertEqual(SleepTimerLogic.fadeFactor(s, nowElapsed: 1_000), 1)
        let fiveSecondsLeft = s.endsAt - 5_000
        XCTAssertEqual(SleepTimerLogic.fadeFactor(s, nowElapsed: fiveSecondsLeft), 0.25, accuracy: 0.001)
        XCTAssertEqual(SleepTimerLogic.fadeFactor(s, nowElapsed: s.endsAt), 0, accuracy: 0.0001)
        XCTAssertEqual(SleepTimerLogic.fadeFactor(nil, nowElapsed: 0), 1)
        XCTAssertEqual(SleepTimerLogic.presetMinutes, [15, 30, 45, 60, 90])
        // freie Dauer wird begrenzt
        XCTAssertEqual(SleepTimerLogic.start(nowElapsed: 0, minutes: 100_000).totalMs, Int64(SleepTimerLogic.maxMinutes) * 60_000)
        XCTAssertEqual(SleepTimerLogic.start(nowElapsed: 0, minutes: 0).totalMs, 60_000)
    }

    func testSleepTimer_endeDesTitelsUndPruefabstand() {
        let eot = SleepTimerLogic.endOfTrack()
        XCTAssertNil(SleepTimerLogic.remainingMs(eot, nowElapsed: 0))
        XCTAssertFalse(SleepTimerLogic.isExpired(eot, nowElapsed: Int64.max - 1))
        XCTAssertEqual(SleepTimerLogic.fadeFactor(eot, nowElapsed: 0), 1)
        let s = SleepTimerLogic.start(nowElapsed: 0, minutes: 1)
        XCTAssertEqual(SleepTimerLogic.nextCheckDelayMs(s, nowElapsed: 0), 1_000)
        XCTAssertEqual(SleepTimerLogic.nextCheckDelayMs(s, nowElapsed: 49_970), 50) // 20 ms bis zum Ausblenden → min. 50
        XCTAssertEqual(SleepTimerLogic.nextCheckDelayMs(s, nowElapsed: 55_000), 100)
        XCTAssertEqual(SleepTimerLogic.nextCheckDelayMs(s, nowElapsed: 60_000), 0)
        XCTAssertEqual(SleepTimerLogic.nextCheckDelayMs(nil, nowElapsed: 0), 1_000)
        XCTAssertEqual(Formatting.countdown(899_001), "15:00")
    }

    func testPitch_zweiModi() {
        let key = PitchSettings(mode: .key, semitones: 12)
        XCTAssertEqual(key.speed, 1)
        XCTAssertEqual(key.pitch, 2, accuracy: 0.0001)
        let vinyl = PitchSettings(mode: .varispeed, semitones: -12)
        XCTAssertEqual(vinyl.speed, 0.5, accuracy: 0.0001)
        XCTAssertEqual(vinyl.pitch, 0.5, accuracy: 0.0001)
        XCTAssertTrue(PitchSettings().isOriginal)
        XCTAssertEqual(PitchSettings().withSemitones(40).semitones, 12)
        XCTAssertEqual(PitchSettings(mode: .varispeed, semitones: PitchSettings.rpm33To45).speed, 1.35, accuracy: 0.0001)
    }

    func testPitch_tempoUnabhaengigImModusTonhoehe() {
        let s = PitchSettings(mode: .key, semitones: 0).withTempo(1.25)
        XCTAssertEqual(s.speed, 1.25)
        XCTAssertEqual(s.pitch, 1) // Tonhöhe bleibt
        XCTAssertFalse(s.isOriginal)
        XCTAssertEqual(s.withTempo(5).tempo, 2)
        XCTAssertEqual(s.withTempo(0.1).tempo, 0.5)
        // Schallplatte: Tempo folgt den Halbtönen, eigenes Tempo wird ignoriert
        let v = PitchSettings(mode: .varispeed, semitones: 0, tempo: 1.5)
        XCTAssertEqual(v.speed, 1)
        XCTAssertTrue(v.isOriginal)
        XCTAssertEqual(PitchSettings(mode: .key, semitones: -3).pitchCents, -300)
        XCTAssertEqual(PitchMode.key.label, "Tonhöhe")
        XCTAssertEqual(PitchMode.varispeed.description, "Tonhöhe und Tempo ändern sich gemeinsam")
    }

    func testPitch_tolerantesLesen() throws {
        let json = #"{"mode":"GIBTESNICHT","semitones":40,"tempo":9}"#
        let s = try JSONDecoder().decode(PitchSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s, PitchSettings(mode: .key, semitones: 12, tempo: 2))
        let empty = try JSONDecoder().decode(PitchSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, PitchSettings())
        let roundTrip = try JSONDecoder().decode(PitchSettings.self, from: JSONEncoder().encode(PitchSettings(mode: .varispeed, semitones: -2.5, tempo: 0.8)))
        XCTAssertEqual(roundTrip, PitchSettings(mode: .varispeed, semitones: -2.5, tempo: 0.8))
    }

    func testVorherigerTitel_dreiSekundenRegel() {
        XCTAssertFalse(PreviousRule.restartsCurrent(positionMs: 3_000, hasPrevious: true))
        XCTAssertTrue(PreviousRule.restartsCurrent(positionMs: 3_001, hasPrevious: true))
        XCTAssertTrue(PreviousRule.restartsCurrent(positionMs: 0, hasPrevious: false))
    }

    func testWiederholenZyklus() {
        XCTAssertEqual(RepeatSetting.off.next, .all)
        XCTAssertEqual(RepeatSetting.all.next, .one)
        XCTAssertEqual(RepeatSetting.one.next, .off)
        XCTAssertEqual(RepeatSetting.all.label, "Quelle wiederholen")
    }
}
