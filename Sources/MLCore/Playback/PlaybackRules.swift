import Foundation

/// Wann zählt eine Wiedergabe? (Portierung von `playback/PlaybackRules.kt`)
///
/// Eine Wiedergabe wird gezählt, sobald ein Titel in dieser Wiedergabesitzung TATSÄCHLICH so lange
/// gehört wurde (ohne Vorspulen): mindestens die Hälfte, höchstens aber 30 Sekunden. Pro Start eines
/// Titels wird höchstens einmal gezählt.
public enum PlayCountRule {
    public static let maxRequiredMs: Int64 = 30_000
    public static let minRequiredMs: Int64 = 1_000

    public static func requiredListenMs(durationMs: Int64) -> Int64 {
        if durationMs <= 0 { return maxRequiredMs }
        return max(minRequiredMs, min(maxRequiredMs, durationMs / 2))
    }

    public static func counts(listenedMs: Int64, durationMs: Int64) -> Bool {
        listenedMs >= requiredListenMs(durationMs: durationMs)
    }
}

/// Misst die tatsächlich gehörte Zeit eines Titels: nur während die Wiedergabe läuft; Spulen zählt
/// nicht. Die Uhrzeit (monoton, Millisekunden) wird von außen übergeben (testbar).
public struct ListenTracker: Hashable, Sendable {
    public private(set) var currentKey: Int64?
    private var listenedMs: Int64 = 0
    private var runningSince: Int64?
    public private(set) var counted = false

    public init() {}

    /// Neuer Titel: Messung beginnt bei null.
    public mutating func start(_ key: Int64?, nowMs: Int64, playing: Bool) {
        currentKey = key
        listenedMs = 0
        counted = false
        runningSince = (playing && key != nil) ? nowMs : nil
    }

    public mutating func setPlaying(_ playing: Bool, nowMs: Int64) {
        if playing {
            if runningSince == nil && currentKey != nil { runningSince = nowMs }
        } else {
            if let since = runningSince { listenedMs += max(nowMs - since, 0) }
            runningSince = nil
        }
    }

    public func listened(nowMs: Int64) -> Int64 {
        listenedMs + (runningSince.map { max(nowMs - $0, 0) } ?? 0)
    }

    /// Liefert `true` genau einmal, wenn die Wiedergabe zu zählen ist.
    public mutating func shouldCount(nowMs: Int64, durationMs: Int64) -> Bool {
        if counted || currentKey == nil { return false }
        if PlayCountRule.counts(listenedMs: listened(nowMs: nowMs), durationMs: durationMs) {
            counted = true
            return true
        }
        return false
    }
}

/// „Vorheriger Titel“ wie bei Media3 (`seekToPrevious`, Standard 3 s): Bis einschließlich 3 Sekunden
/// Wiedergabeposition geht es zum vorherigen Titel (falls vorhanden), danach an den Anfang des Titels.
public enum PreviousRule {
    public static let maxPositionForPreviousMs: Int64 = 3_000

    /// `true` = an den Anfang des laufenden Titels springen, `false` = zum vorherigen Titel.
    public static func restartsCurrent(positionMs: Int64, hasPrevious: Bool) -> Bool {
        !(hasPrevious && positionMs <= maxPositionForPreviousMs)
    }
}

/// Wiederholen-Modus wie in der Oberfläche angezeigt.
public enum RepeatSetting: String, CaseIterable, Codable, Hashable, Sendable {
    case off = "OFF"
    case all = "ALL"
    case one = "ONE"

    public var label: String {
        switch self {
        case .off: return "Wiederholen aus"
        case .all: return "Quelle wiederholen"
        case .one: return "Titel wiederholen"
        }
    }

    /// Aus → Quelle wiederholen → Titel wiederholen → Aus (wie die Taste in der Android-App).
    public var next: RepeatSetting {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

/// Wiedergabequelle – damit die Oberfläche zeigen kann, woher die aktuelle Warteschlange stammt.
public struct PlaybackSource: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case singleTrack = "SINGLE_TRACK"
        case album = "ALBUM"
        case playlist = "PLAYLIST"
        case smartPlaylist = "SMART_PLAYLIST"
        case artist = "ARTIST"
        case genre = "GENRE"
        case favorites = "FAVORITES"
        case list = "LIST"
    }

    public var kind: Kind
    public var label: String
    public var id: String?

    public init(kind: Kind, label: String, id: String? = nil) {
        self.kind = kind
        self.label = label
        self.id = id
    }
}

/// Zufallswiedergabe beim Start einer Quelle.
public enum ShuffleStart: String, Codable, Hashable, Sendable {
    /// In Listenreihenfolge (Schaltfläche „Abspielen“).
    case off = "OFF"
    /// Gemischt (Schaltfläche „Mischen“).
    case on = "ON"
    /// Aktuellen Modus beibehalten (Klick auf einen Titel): ist Zufall an, beginnt der angeklickte Titel.
    case keep = "KEEP"
}

/// Was soll abgespielt werden?
///
/// Grundsatz: Ein angeklickter Titel startet die **Liste, in der er steht** – genau in der angezeigten
/// Sortierung und mit aktivem Filter bzw. Suchergebnis – ab diesem Titel. Damit funktionieren „Nächster“
/// und „Vorheriger“ überall. Ohne Wiederholung endet die Wiedergabe am Ende der Liste, mit „Quelle
/// wiederholen“ beginnt sie von vorn. Nur „Nur diesen Titel abspielen“ spielt einen Titel allein.
public struct QueuePlan: Hashable, Codable, Sendable {
    public var trackUids: [Int64]
    /// Position in `trackUids`, mit der begonnen wird; `nil` = Anfang der (ggf. gemischten) Reihenfolge.
    public var startIndex: Int?
    public var shuffle: ShuffleStart
    public var source: PlaybackSource

    public init(trackUids: [Int64], startIndex: Int?, shuffle: ShuffleStart, source: PlaybackSource) {
        self.trackUids = trackUids
        self.startIndex = startIndex
        self.shuffle = shuffle
        self.source = source
    }

    /// Nur dieser eine Titel (ausdrücklich im Menü gewählt).
    public static func single(_ uid: Int64, title: String) -> QueuePlan {
        QueuePlan(trackUids: [uid], startIndex: 0, shuffle: .off, source: PlaybackSource(kind: .singleTrack, label: title))
    }

    /// Titel in einer Liste angeklickt: die ganze Liste ab dieser Stelle. `tappedIndex` ist die Position
    /// in der Liste (nicht die Titel-ID – Playlists können einen Titel mehrfach enthalten).
    public static func tapped(_ uids: [Int64], tappedIndex: Int, source: PlaybackSource) -> QueuePlan? {
        if uids.isEmpty { return nil }
        return QueuePlan(trackUids: uids, startIndex: min(max(tappedIndex, 0), uids.count - 1), shuffle: .keep, source: source)
    }

    /// Ganze Quelle ab `startUid` (bzw. ab Anfang) – „Abspielen“, „Mischen“. Beim Mischen ohne Starttitel
    /// wird der erste Titel zufällig gewählt; die Zufallsreihenfolge beginnt mit ihm.
    public static func fromSource<R: RandomNumberGenerator>(
        _ uids: [Int64], startUid: Int64?, shuffle: Bool, source: PlaybackSource, using random: inout R
    ) -> QueuePlan? {
        if uids.isEmpty { return nil }
        let index: Int
        if let startUid {
            index = uids.firstIndex(of: startUid) ?? 0
        } else if shuffle {
            index = Int.random(in: 0..<uids.count, using: &random)
        } else {
            index = 0
        }
        return QueuePlan(trackUids: uids, startIndex: index, shuffle: shuffle ? .on : .off, source: source)
    }

    public static func fromSource(_ uids: [Int64], startUid: Int64?, shuffle: Bool, source: PlaybackSource) -> QueuePlan? {
        var rng = SystemRandomNumberGenerator()
        return fromSource(uids, startUid: startUid, shuffle: shuffle, source: source, using: &rng)
    }

    /// Liste ohne nicht mehr vorhandene Titel; die Startposition wandert mit (zählt nur verbliebene
    /// Einträge davor). Liefert `nil`, wenn nichts übrig bleibt.
    public static func filterAvailable(_ plan: QueuePlan, available: (Int64) -> Bool) -> QueuePlan? {
        var kept: [Int64] = []
        kept.reserveCapacity(plan.trackUids.count)
        var newStart: Int?
        for (i, uid) in plan.trackUids.enumerated() {
            if available(uid) {
                if plan.startIndex == i { newStart = kept.count }
                kept.append(uid)
            } else if plan.startIndex == i {
                newStart = kept.count // nächster verbliebener Titel
            }
        }
        if kept.isEmpty { return nil }
        var copy = plan
        copy.trackUids = kept
        copy.startIndex = plan.startIndex.map { _ in min(newStart ?? 0, kept.count - 1) }
        return copy
    }
}

/// Reihenfolge der Zufallswiedergabe (Portierung von `ShuffleLogic`).
///
/// - Der Titel, mit dem gestartet wird (angeklickter Titel bzw. laufender Titel beim Einschalten von
///   „Zufall“), steht **vorn** – danach folgen alle übrigen genau einmal.
/// - Eingefügte Titel („Als Nächstes spielen“) folgen direkt auf ihren Vorgänger in der Liste – also auf
///   den laufenden Titel – statt an einer zufälligen Stelle zu landen.
/// Zufall „nach Alben“ (v2.1, wie iTunes): Alben in Zufallsfolge, jedes Album in seiner Titelreihenfolge.
public enum AlbumShuffle {
    /// Abspielfolge (Permutation der Listenpositionen). `groups[i]` = Album der Listenposition `i`.
    /// - `current`: laufender Titel – sein Album kommt zuerst (davor liegende Titel des Albums gelten als gespielt).
    /// - `avoidFirstGroup`: dieses Album soll nicht als erstes kommen (neuer Durchgang bei „Wiederholen“).
    public static func order<R: RandomNumberGenerator>(groups: [Int], current: Int?, avoidFirstGroup: Int? = nil, using random: inout R) -> [Int] {
        guard !groups.isEmpty else { return [] }
        var members: [Int: [Int]] = [:]
        var keys: [Int] = []
        for (i, g) in groups.enumerated() {
            if members[g] == nil {
                keys.append(g)
                members[g] = []
            }
            members[g]!.append(i)
        }
        var shuffled = keys
        shuffled.shuffle(using: &random)
        if let current, groups.indices.contains(current) {
            let g = groups[current]
            shuffled.removeAll { $0 == g }
            shuffled.insert(g, at: 0)
        } else if let avoid = avoidFirstGroup, shuffled.count > 1, shuffled.first == avoid {
            shuffled.swapAt(0, Int.random(in: 1..<shuffled.count, using: &random))
        }
        return shuffled.flatMap { members[$0] ?? [] }
    }
}

public enum ShuffleLogic {
    /// Neuer Durchgang („Wiederholen“ mit Zufall): neue Zufallsfolge, deren erster Eintrag nicht der zuletzt
    /// gespielte ist – keine direkte Wiederholung an der Grenze zweier Durchgänge.
    public static func nextCycle<R: RandomNumberGenerator>(length: Int, lastPlayed: Int?, using random: inout R) -> [Int] {
        var order = create(length: length, first: nil, using: &random)
        if length > 1, let last = lastPlayed, order.first == last {
            order.swapAt(0, Int.random(in: 1..<length, using: &random))
        }
        return order
    }


    /// Zufällige Reihenfolge aller `length` Positionen; `first` (falls gültig) steht vorn.
    public static func create<R: RandomNumberGenerator>(length: Int, first: Int?, using random: inout R) -> [Int] {
        guard length > 0 else { return [] }
        var order = Array(0..<length)
        var i = length - 1
        while i >= 1 {
            let j = Int.random(in: 0...i, using: &random)
            order.swapAt(i, j)
            i -= 1
        }
        if let first, first >= 0, first < length, let pos = order.firstIndex(of: first) {
            // Gewählten Titel nach vorn holen, Rest in seiner Zufallsreihenfolge lassen.
            order.remove(at: pos)
            order.insert(first, at: 0)
        }
        return order
    }

    /// `count` neue Positionen ab `insertionIndex` (Liste) einfügen, direkt hinter ihren Vorgänger.
    public static func insert(_ order: [Int], insertionIndex: Int, count: Int) -> [Int] {
        if count <= 0 { return order }
        let shifted = order.map { $0 >= insertionIndex ? $0 + count : $0 }
        let after = insertionIndex > 0 ? (shifted.firstIndex(of: insertionIndex - 1) ?? -1) : -1
        let at = after + 1 // -1 (kein Vorgänger) → ganz vorn
        return Array(shifted[0..<at]) + Array(insertionIndex..<(insertionIndex + count)) + Array(shifted[at...])
    }

    /// Positionen `from..<toExclusive` entfernen; spätere rücken nach.
    public static func remove(_ order: [Int], from: Int, toExclusive: Int) -> [Int] {
        let n = toExclusive - from
        if n <= 0 { return order }
        return order.compactMap { v in
            if v >= from && v < toExclusive { return nil }
            return v >= toExclusive ? v - n : v
        }
    }
}
