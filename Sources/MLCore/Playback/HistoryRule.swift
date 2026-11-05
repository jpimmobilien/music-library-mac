import Foundation

/// Wiedergabeverlauf und Statistik (neu gegenüber Android, baut auf `PlayCountRule` auf).
///
/// Zwei getrennte Begriffe:
/// - **Gezählte Wiedergabe** (Statistik: „Meistgespielt“, „Zuletzt abgespielt“, Albumstatistik): genau
///   `PlayCountRule` – mindestens die Hälfte, höchstens 30 s tatsächlich gehört, höchstens einmal je Start.
///   Gezählt wird in dem Moment, in dem die Schwelle erreicht ist – wie auf Android
///   (`playCount + 1`, `lastPlayedAt = jetzt`, `firstPlayedAt` bleibt bzw. = jetzt,
///   `totalListenedMs +=` bis dahin gehörte Zeit).
/// - **Verlaufseintrag**: jeder Start eines Titels, der mindestens 5 s tatsächlich gehört wurde ODER als
///   Wiedergabe gezählt wurde (sehr kurze Titel < 10 s erreichen `PlayCountRule` schon vor 5 s).
///   Der Eintrag wird beim Ende der Sitzung (Titelwechsel, Stopp) mit der gesamten gehörten Zeit
///   geschrieben; `counted` zeigt, ob er in die Statistik einging. Jeder Start ist ein eigener Eintrag –
///   auch eine Wiederholung durch „Titel wiederholen“ (wie auf Android).
public enum HistoryRule {
    public static let minimumListenMs: Int64 = 5_000

    /// Gehört dieser Start in den Verlauf?
    public static func shouldRecord(listenedMs: Int64, durationMs: Int64, counted: Bool = false) -> Bool {
        counted || listenedMs >= minimumListenMs || PlayCountRule.counts(listenedMs: listenedMs, durationMs: durationMs)
    }

    /// Verlaufseintrag für einen beendeten Start (oder `nil`, wenn er nicht in den Verlauf gehört).
    public static func entry(
        id: Int64, trackUid: Int64, startedAt: Int64, listenedMs: Int64, durationMs: Int64, counted: Bool? = nil
    ) -> HistoryEntry? {
        let isCounted = counted ?? PlayCountRule.counts(listenedMs: listenedMs, durationMs: durationMs)
        guard shouldRecord(listenedMs: listenedMs, durationMs: durationMs, counted: isCounted) else { return nil }
        return HistoryEntry(id: id, trackUid: trackUid, playedAt: startedAt, listenedMs: max(listenedMs, 0), counted: isCounted)
    }

    /// Statistik nach einer gezählten Wiedergabe (Android `StatsDao.recordPlay`).
    public static func recordingCountedPlay(_ old: PlayStats?, trackUid: Int64, now: Int64, listenedMs: Int64) -> PlayStats {
        PlayStats(
            trackUid: trackUid,
            playCount: (old?.playCount ?? 0) + 1,
            lastPlayedAt: now,
            firstPlayedAt: old?.firstPlayedAt ?? now,
            totalListenedMs: (old?.totalListenedMs ?? 0) + max(listenedMs, 0)
        )
    }
}

/// Eine Wiedergabesitzung = ein Start eines Titels (bis Titelwechsel oder Stopp).
///
/// Verbindet `ListenTracker` (monotone Uhr) mit der Wanduhr des Starts (für den Verlauf).
public struct PlaySession: Hashable, Sendable {
    public let trackUid: Int64
    /// Wanduhrzeit des Starts (ms seit 1970) – `HistoryEntry.playedAt`.
    public let startedAt: Int64
    public private(set) var tracker = ListenTracker()

    public init(trackUid: Int64, startedAt: Int64, nowMonotonic: Int64, playing: Bool) {
        self.trackUid = trackUid
        self.startedAt = startedAt
        tracker.start(trackUid, nowMs: nowMonotonic, playing: playing)
    }

    public var counted: Bool { tracker.counted }

    public mutating func setPlaying(_ playing: Bool, nowMonotonic: Int64) {
        tracker.setPlaying(playing, nowMs: nowMonotonic)
    }

    public func listened(nowMonotonic: Int64) -> Int64 { tracker.listened(nowMs: nowMonotonic) }

    /// Regelmäßig (z. B. sekündlich) aufrufen: liefert genau einmal die neue Statistik, sobald die
    /// Wiedergabe zählt.
    public mutating func countIfDue(nowMonotonic: Int64, nowWall: Int64, durationMs: Int64, stats: PlayStats?) -> PlayStats? {
        guard tracker.shouldCount(nowMs: nowMonotonic, durationMs: durationMs) else { return nil }
        return HistoryRule.recordingCountedPlay(stats, trackUid: trackUid, now: nowWall, listenedMs: tracker.listened(nowMs: nowMonotonic))
    }

    /// Sitzung beenden: Verlaufseintrag (oder `nil`). Vorher `countIfDue` aufrufen (wie Android beim Titelwechsel).
    public func finish(id: Int64, nowMonotonic: Int64, durationMs: Int64) -> HistoryEntry? {
        HistoryRule.entry(
            id: id, trackUid: trackUid, startedAt: startedAt,
            listenedMs: tracker.listened(nowMs: nowMonotonic), durationMs: durationMs, counted: tracker.counted
        )
    }
}
