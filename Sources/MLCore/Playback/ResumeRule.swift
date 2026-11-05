import Foundation

/// Gespeicherter Wiedergabezustand (beim Beenden bzw. regelmäßig gesichert, beim Start wiederhergestellt).
public struct SavedPlaybackState: Hashable, Codable, Sendable {
    public var queue: PlayQueue
    /// Position im laufenden Titel (ms).
    public var positionMs: Int64
    /// Zeitpunkt der Sicherung (ms seit 1970).
    public var savedAt: Int64

    public init(queue: PlayQueue, positionMs: Int64, savedAt: Int64) {
        self.queue = queue
        self.positionMs = positionMs
        self.savedAt = savedAt
    }
}

/// Fortsetzen der Wiedergabe (neu gegenüber Android).
///
/// 1. **Beim Start der App** (Einstellung „Wiedergabe beim Start fortsetzen“, Standard an): Warteschlange,
///    laufender Titel und Position werden IMMER wiederhergestellt – pausiert, nie automatisch abspielend.
///    Nicht mehr verfügbare Titel werden herausgenommen (Regeln von `PlayQueue.removeAll`); fehlt der
///    laufende Titel, beginnt der nächste verfügbare bei 0. Eine Position im letzten Sekundenbruchteil
///    (≥ Dauer − 1 s) gilt als „zu Ende gehört“ und beginnt bei 0.
/// 2. **Lange Titel** (≥ 10 Minuten, z. B. Hörbücher, Live-Mitschnitte, DJ-Mixe) merken sich zusätzlich
///    ihre eigene Position: beim Stoppen/Überspringen, wenn mindestens 30 s gehört wurden und noch mehr
///    als 30 s fehlen. Zu Ende gespielt (oder in den letzten 30 s beendet) → Position wird gelöscht.
///    Unter 30 s → nichts ändern (ein versehentlicher Neustart löscht keine gemerkte Stelle).
public enum ResumeRule {
    public static let longTrackMinDurationMs: Int64 = 10 * 60_000
    public static let marginMs: Int64 = 30_000
    /// Beim Start: so nah am Ende gilt ein Titel als zu Ende gehört.
    public static let launchEndToleranceMs: Int64 = 1_000

    // MARK: - Start der App

    /// Wiederherzustellender Zustand oder `nil` (Einstellung aus, nichts gespeichert, nichts mehr verfügbar).
    /// - Parameters:
    ///   - isAvailable: Ist der Titel noch in der Bibliothek und erreichbar?
    ///   - durationOf: Dauer des Titels in ms (`nil`/0 = unbekannt → Position wird nur nach unten begrenzt).
    public static func restoreOnLaunch(
        _ saved: SavedPlaybackState?,
        enabled: Bool,
        isAvailable: (Int64) -> Bool,
        durationOf: (Int64) -> Int64?
    ) -> SavedPlaybackState? {
        guard enabled, var state = saved, !state.queue.isEmpty else { return nil }
        let change = state.queue.removeAll { !isAvailable($0.trackUid) }
        guard let current = state.queue.currentTrackUid else { return nil }
        switch change {
        case .unchanged:
            state.positionMs = clampedLaunchPosition(state.positionMs, durationMs: durationOf(current) ?? 0)
        case .changed, .emptied:
            state.positionMs = 0
        }
        return state
    }

    static func clampedLaunchPosition(_ positionMs: Int64, durationMs: Int64) -> Int64 {
        let p = max(positionMs, 0)
        if durationMs > 0 && p >= durationMs - launchEndToleranceMs { return 0 }
        return p
    }

    // MARK: - Gemerkte Position langer Titel

    public static func isLongTrack(durationMs: Int64) -> Bool { durationMs >= longTrackMinDurationMs }

    public enum PointUpdate: Hashable, Sendable {
        /// Position merken.
        case save(positionMs: Int64)
        /// Gemerkte Position löschen.
        case clear
        /// Nichts ändern.
        case keep
    }

    /// Was beim Stoppen, Überspringen oder Beenden eines Titels mit seiner gemerkten Position geschieht.
    /// - Parameter finished: Titel wurde bis zum Ende gespielt.
    public static func update(positionMs: Int64, durationMs: Int64, finished: Bool) -> PointUpdate {
        guard isLongTrack(durationMs: durationMs) else { return .keep }
        if finished { return .clear }
        if positionMs > durationMs - marginMs { return .clear }
        if positionMs >= marginMs { return .save(positionMs: positionMs) }
        return .keep
    }

    /// Wendet `update` auf eine vorhandene gemerkte Position an.
    public static func apply(_ update: PointUpdate, to existing: ResumePoint?, trackUid: Int64, now: Int64) -> ResumePoint? {
        switch update {
        case .save(let position): return ResumePoint(trackUid: trackUid, positionMs: position, updatedAt: now)
        case .clear: return nil
        case .keep: return existing
        }
    }

    /// Startposition beim Abspielen eines Titels: gemerkte Position langer Titel (wenn noch gültig), sonst 0.
    public static func startPosition(durationMs: Int64, point: ResumePoint?) -> Int64 {
        guard let point, isLongTrack(durationMs: durationMs) else { return 0 }
        guard point.positionMs >= marginMs && point.positionMs <= durationMs - marginMs else { return 0 }
        return point.positionMs
    }
}
