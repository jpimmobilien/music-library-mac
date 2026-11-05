import Foundation

/// Die Warteschlange des Players (neu gegenüber Android; dort übernahm Media3 diese Aufgabe).
///
/// Verhalten wie in der Android-App (Media3 + `StartFirstShuffleOrder`):
/// - **Listenreihenfolge** (`items`) = Reihenfolge der Quelle; **Abspielfolge** (`playOrder`) = bei Zufall
///   die gemischte Reihenfolge, sonst die Liste. Jeder Eintrag hat eine eigene, stabile Kennung – derselbe
///   Titel darf mehrfach vorkommen.
/// - **Zufall einschalten:** der laufende Titel bleibt der laufende und steht vorn, alle übrigen folgen
///   genau einmal gemischt. **Ausschalten:** Listenreihenfolge, der laufende Titel bleibt.
/// - **Nächster** (`skipToNext`): nächster Eintrag der Abspielfolge; mit „Quelle wiederholen“ nach dem
///   letzten wieder der erste. „Titel wiederholen“ gilt beim Blättern wie „aus“ (wie Media3).
/// - **Vorheriger** (`previous`): bis einschließlich 3 s Position zum vorherigen Eintrag (falls vorhanden),
///   sonst an den Anfang des Titels (`PreviousRule`).
/// - **Titelende** (`advanceAfterCompletion`): „Titel wiederholen“ → derselbe Titel noch einmal; sonst der
///   nächste; am Ende mit „Quelle wiederholen“ von vorn, sonst `endOfQueue` (der letzte Eintrag bleibt der
///   laufende; „Abspielen“ beginnt dann mit `rewindToStart()` am Anfang der Abspielfolge).
/// - **Als Nächstes spielen:** direkt hinter dem laufenden Eintrag (auch im Zufallsmodus); mehrfaches
///   „Als Nächstes“ stellt den zuletzt gewählten Titel nach vorn (wie Apple Musik und Media3).
/// - **Zur Warteschlange hinzufügen:** ans Ende der Abspielfolge (auch im Zufallsmodus).
/// - **Laufenden Eintrag entfernen:** der nächste verbleibende Eintrag der bisherigen Abspielfolge wird
///   der laufende (mit „Quelle wiederholen“ ringsum). Gibt es keinen, wird der erste Eintrag der
///   Abspielfolge der laufende und die Wiedergabe soll anhalten.
public struct PlayQueue: Hashable, Sendable {

    public struct Item: Hashable, Codable, Sendable, Identifiable {
        /// Kennung des Eintrags (eindeutig in dieser Warteschlange, bleibt bei Umsortieren erhalten).
        public let id: Int64
        public let trackUid: Int64

        public init(id: Int64, trackUid: Int64) {
            self.id = id
            self.trackUid = trackUid
        }
    }

    /// Ergebnis von „Vorheriger“.
    public enum PreviousResult: Hashable, Sendable {
        /// Warteschlange leer.
        case none
        /// An den Anfang des laufenden Titels springen.
        case restartCurrent
        /// Zum vorherigen Eintrag gewechselt (`current` ist jetzt der vorherige).
        case movedToPrevious
    }

    /// Ergebnis am Ende eines Titels.
    public enum AdvanceResult: Hashable, Sendable {
        case none
        /// „Titel wiederholen“: derselbe Eintrag noch einmal von vorn.
        case repeatCurrent
        /// Nächster Eintrag ist jetzt der laufende; `wrapped` = nach dem Ende wieder von vorn.
        case advanced(wrapped: Bool)
        /// Ende der Abspielfolge ohne Wiederholung: anhalten (laufender Eintrag bleibt der letzte).
        case endOfQueue
    }

    /// Auswirkung einer Änderung auf den laufenden Eintrag.
    public enum CurrentChange: Hashable, Sendable {
        case unchanged
        /// Der laufende Eintrag wurde entfernt; ein anderer ist jetzt der laufende.
        /// `continuePlayback == false`: Ende erreicht (anhalten).
        case changed(continuePlayback: Bool)
        /// Die Warteschlange ist jetzt leer.
        case emptied
    }

    public private(set) var items: [Item] = []
    /// Listenposition des laufenden Eintrags (`nil` = leer).
    public private(set) var currentIndex: Int?
    public private(set) var shuffleEnabled = false
    /// Zufallsreihenfolge (nur bei eingeschaltetem Zufall gepflegt, sonst leer).
    public private(set) var shuffleOrder = StartFirstShuffleOrder.empty
    public var repeatMode: RepeatSetting = .off
    /// Woher die Warteschlange stammt (Anzeige).
    public var source: PlaybackSource?
    private var nextItemID: Int64 = 1

    public init() {}

    // MARK: - Abfragen

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }

    public var current: Item? { currentIndex.map { items[$0] } }
    public var currentTrackUid: Int64? { current?.trackUid }

    /// Listenpositionen in Abspielreihenfolge.
    public var playOrder: [Int] { shuffleEnabled ? shuffleOrder.order : Array(items.indices) }

    /// Einträge in Abspielreihenfolge.
    public var itemsInPlayOrder: [Item] { playOrder.map { items[$0] } }

    /// Stelle des laufenden Eintrags in der Abspielfolge.
    public var currentPlayPosition: Int? { currentIndex.flatMap(playPosition(ofListIndex:)) }

    public func playPosition(ofListIndex index: Int) -> Int? {
        guard items.indices.contains(index) else { return nil }
        return shuffleEnabled ? shuffleOrder.playPosition(of: index) : index
    }

    public func listIndex(ofItemID id: Int64) -> Int? { items.firstIndex { $0.id == id } }

    /// „Als Nächstes“: Einträge nach dem laufenden in Abspielreihenfolge (ohne Wiederholung ringsum).
    public var upNext: [Item] {
        guard let p = currentPlayPosition else { return [] }
        return playOrder[(p + 1)...].map { items[$0] }
    }

    /// Bereits gespielte Einträge vor dem laufenden in Abspielreihenfolge.
    public var history: [Item] {
        guard let p = currentPlayPosition else { return [] }
        return playOrder[..<p].map { items[$0] }
    }

    /// Wie `PlaybackController.upcoming` der Android-App: laufender Eintrag, dann die folgenden in
    /// Abspielreihenfolge; mit „Quelle wiederholen“ einmal ringsum (nicht endlos).
    public func upcoming(limit: Int = 500) -> [Item] {
        guard let p = currentPlayPosition else { return [] }
        let order = playOrder
        var result: [Item] = []
        let total = repeatMode == .all ? order.count : order.count - p
        var k = 0
        while k < total && result.count < limit {
            result.append(items[order[(p + k) % order.count]])
            k += 1
        }
        return result
    }

    /// Wiederholungsmodus fürs Blättern: „Titel wiederholen“ zählt wie „aus“ (wie Media3).
    private var navigationRepeat: RepeatSetting { repeatMode == .one ? .off : repeatMode }

    private func nextListIndex(after index: Int, repeat mode: RepeatSetting) -> Int? {
        guard let p = playPosition(ofListIndex: index) else { return nil }
        let order = playOrder
        if p + 1 < order.count { return order[p + 1] }
        return mode == .all ? order.first : nil
    }

    private func previousListIndex(before index: Int, repeat mode: RepeatSetting) -> Int? {
        guard let p = playPosition(ofListIndex: index) else { return nil }
        let order = playOrder
        if p - 1 >= 0 { return order[p - 1] }
        return mode == .all ? order.last : nil
    }

    public var hasNext: Bool { currentIndex.flatMap { nextListIndex(after: $0, repeat: navigationRepeat) } != nil }
    public var hasPrevious: Bool { currentIndex.flatMap { previousListIndex(before: $0, repeat: navigationRepeat) } != nil }

    // MARK: - Neue Warteschlange

    /// Ersetzt die Warteschlange. `startIndex` = Listenposition des ersten Titels; `nil` = Anfang der
    /// (ggf. gemischten) Abspielfolge. Bei Zufall steht der Starttitel vorn in der Zufallsreihenfolge.
    public mutating func replace<R: RandomNumberGenerator>(
        with trackUids: [Int64], startIndex: Int?, shuffle: ShuffleStart, source: PlaybackSource? = nil, using random: inout R
    ) {
        self.source = source
        switch shuffle {
        case .on: shuffleEnabled = true
        case .off: shuffleEnabled = false
        case .keep: break
        }
        items = makeItems(trackUids)
        guard !items.isEmpty else {
            currentIndex = nil
            shuffleOrder = .empty
            return
        }
        let start = startIndex.map { min(max($0, 0), items.count - 1) }
        if shuffleEnabled {
            shuffleOrder = StartFirstShuffleOrder(length: items.count, first: start, using: &random)
            currentIndex = shuffleOrder.firstIndex
        } else {
            shuffleOrder = .empty
            currentIndex = start ?? 0
        }
    }

    public mutating func replace(with trackUids: [Int64], startIndex: Int?, shuffle: ShuffleStart, source: PlaybackSource? = nil) {
        var rng = SystemRandomNumberGenerator()
        replace(with: trackUids, startIndex: startIndex, shuffle: shuffle, source: source, using: &rng)
    }

    /// Spielt einen `QueuePlan` ab (Liste, Startposition, Zufall, Quelle).
    public mutating func play<R: RandomNumberGenerator>(_ plan: QueuePlan, using random: inout R) {
        replace(with: plan.trackUids, startIndex: plan.startIndex, shuffle: plan.shuffle, source: plan.source, using: &random)
    }

    public mutating func play(_ plan: QueuePlan) {
        var rng = SystemRandomNumberGenerator()
        play(plan, using: &rng)
    }

    public mutating func clear() {
        items = []
        currentIndex = nil
        shuffleOrder = .empty
        source = nil
    }

    // MARK: - Blättern

    /// Nächster Eintrag (Taste „Nächster“). `false` = es gibt keinen (nichts geändert).
    @discardableResult
    public mutating func skipToNext() -> Bool {
        guard let i = currentIndex, let next = nextListIndex(after: i, repeat: navigationRepeat) else { return false }
        currentIndex = next
        return true
    }

    /// Taste „Vorheriger“ bei Wiedergabeposition `positionMs`.
    public mutating func previous(positionMs: Int64) -> PreviousResult {
        guard let i = currentIndex else { return .none }
        let prev = previousListIndex(before: i, repeat: navigationRepeat)
        if PreviousRule.restartsCurrent(positionMs: positionMs, hasPrevious: prev != nil) { return .restartCurrent }
        currentIndex = prev
        return .movedToPrevious
    }

    /// Der laufende Titel ist zu Ende gespielt.
    public mutating func advanceAfterCompletion() -> AdvanceResult {
        guard let i = currentIndex, let p = playPosition(ofListIndex: i) else { return .none }
        if repeatMode == .one { return .repeatCurrent }
        let order = playOrder
        if p + 1 < order.count {
            currentIndex = order[p + 1]
            return .advanced(wrapped: false)
        }
        if repeatMode == .all, let first = order.first {
            currentIndex = first
            return .advanced(wrapped: true)
        }
        return .endOfQueue
    }

    /// Nach dem Ende der Abspielfolge erneut „Abspielen“: am Anfang der Abspielfolge beginnen
    /// (bei Zufall: erster Titel der gemischten Folge – wie in der Android-App).
    public mutating func rewindToStart() {
        currentIndex = playOrder.first
    }

    /// Zu einem Eintrag springen (Klick in der Warteschlange). `false` = unbekannte Kennung.
    @discardableResult
    public mutating func jump(toItemID id: Int64) -> Bool {
        guard let index = listIndex(ofItemID: id) else { return false }
        currentIndex = index
        return true
    }

    // MARK: - Zufall und Wiederholen

    /// Zufall ein-/ausschalten. Der laufende Eintrag bleibt der laufende; beim Einschalten steht er vorn
    /// und alle übrigen folgen genau einmal gemischt.
    public mutating func setShuffle<R: RandomNumberGenerator>(_ enabled: Bool, using random: inout R) {
        guard enabled != shuffleEnabled else { return }
        shuffleEnabled = enabled
        shuffleOrder = enabled ? StartFirstShuffleOrder(length: items.count, first: currentIndex, using: &random) : .empty
    }

    public mutating func setShuffle(_ enabled: Bool) {
        var rng = SystemRandomNumberGenerator()
        setShuffle(enabled, using: &rng)
    }

    /// Aus → Quelle wiederholen → Titel wiederholen → Aus.
    public mutating func cycleRepeat() { repeatMode = repeatMode.next }

    // MARK: - Hinzufügen

    /// „Als Nächstes spielen“: direkt hinter dem laufenden Eintrag (auch bei Zufall). Ist die Warteschlange
    /// leer, bilden die Titel die neue Warteschlange (der erste ist der laufende).
    @discardableResult
    public mutating func playNext(_ trackUids: [Int64]) -> [Item] {
        guard !trackUids.isEmpty else { return [] }
        let new = makeItems(trackUids)
        guard let current = currentIndex else { return startWith(new) }
        let at = current + 1
        items.insert(contentsOf: new, at: at)
        if shuffleEnabled { shuffleOrder = shuffleOrder.inserting(at: at, count: new.count) }
        return new
    }

    /// „Zur Warteschlange hinzufügen“: ans Ende der Abspielfolge (auch bei Zufall).
    @discardableResult
    public mutating func addToEnd(_ trackUids: [Int64]) -> [Item] {
        guard !trackUids.isEmpty else { return [] }
        let new = makeItems(trackUids)
        guard currentIndex != nil else { return startWith(new) }
        items.append(contentsOf: new)
        if shuffleEnabled { shuffleOrder = shuffleOrder.appending(count: new.count) }
        return new
    }

    private mutating func startWith(_ new: [Item]) -> [Item] {
        items = new
        currentIndex = 0
        shuffleOrder = shuffleEnabled ? StartFirstShuffleOrder(order: Array(new.indices))! : .empty
        return new
    }

    // MARK: - Entfernen

    /// Einen Eintrag entfernen.
    @discardableResult
    public mutating func remove(itemID id: Int64) -> CurrentChange {
        removeAll { $0.id == id }
    }

    /// Alle Einträge eines Titels entfernen (z. B. Datei gelöscht).
    @discardableResult
    public mutating func removeAll(trackUid: Int64) -> CurrentChange {
        removeAll { $0.trackUid == trackUid }
    }

    /// Einträge entfernen, auf die `shouldRemove` zutrifft (siehe Typbeschreibung zum laufenden Eintrag).
    @discardableResult
    public mutating func removeAll(where shouldRemove: (Item) -> Bool) -> CurrentChange {
        let removed = items.map(shouldRemove)
        guard removed.contains(true) else { return .unchanged }
        let oldOrder = playOrder
        let oldCurrent = currentIndex

        // Neue Listenpositionen der verbleibenden Einträge
        var newIndex = Array(repeating: -1, count: items.count)
        var kept: [Item] = []
        for (i, item) in items.enumerated() where !removed[i] {
            newIndex[i] = kept.count
            kept.append(item)
        }
        items = kept
        if kept.isEmpty {
            currentIndex = nil
            shuffleOrder = .empty
            return .emptied
        }
        if shuffleEnabled {
            shuffleOrder = StartFirstShuffleOrder(order: oldOrder.filter { !removed[$0] }.map { newIndex[$0] })!
        }
        guard let oldCurrent else {
            currentIndex = playOrder.first
            return .changed(continuePlayback: false)
        }
        if !removed[oldCurrent] {
            currentIndex = newIndex[oldCurrent]
            return .unchanged
        }
        // Laufender Eintrag entfernt: nächster verbleibender der bisherigen Abspielfolge.
        let p = oldOrder.firstIndex(of: oldCurrent)!
        let n = oldOrder.count
        let steps = repeatMode == .all ? n - 1 : n - 1 - p
        if steps > 0 {
            for k in 1...steps {
                let candidate = oldOrder[(p + k) % n]
                if !removed[candidate] {
                    currentIndex = newIndex[candidate]
                    return .changed(continuePlayback: true)
                }
            }
        }
        currentIndex = playOrder.first
        return .changed(continuePlayback: false)
    }

    // MARK: - Umsortieren

    /// Verschiebt innerhalb von „Als Nächstes“ (`upNext`): `from`/`to` sind Positionen in dieser Liste.
    @discardableResult
    public mutating func moveUpNext(from: Int, to: Int) -> Bool {
        guard let p = currentPlayPosition else { return false }
        let upCount = items.count - p - 1
        guard from >= 0, from < upCount, to >= 0, to < upCount else { return false }
        return movePlayPosition(from: p + 1 + from, to: p + 1 + to)
    }

    /// Verschiebt einen Eintrag innerhalb der Abspielfolge (Positionen wie in `itemsInPlayOrder`).
    /// Ohne Zufall wird die Liste umsortiert, mit Zufall nur die Zufallsreihenfolge. Der laufende Eintrag
    /// bleibt der laufende.
    @discardableResult
    public mutating func movePlayPosition(from: Int, to: Int) -> Bool {
        guard items.indices.contains(from), items.indices.contains(to) else { return false }
        if from == to { return true }
        if shuffleEnabled {
            shuffleOrder = shuffleOrder.movingPlayPosition(from: from, to: to)
        } else {
            let currentID = current?.id
            items = PlaylistOrdering.move(items, from: from, to: to)
            if let currentID { currentIndex = listIndex(ofItemID: currentID) }
        }
        return true
    }

    // MARK: - Intern

    private mutating func makeItems(_ uids: [Int64]) -> [Item] {
        var result: [Item] = []
        result.reserveCapacity(uids.count)
        for uid in uids {
            result.append(Item(id: nextItemID, trackUid: uid))
            nextItemID += 1
        }
        return result
    }
}

// MARK: - Speichern (Wiederherstellen beim Start)

extension PlayQueue: Codable {
    private enum CodingKeys: String, CodingKey {
        case items, currentIndex, shuffleEnabled, shuffleOrder, repeatMode, source, nextItemID
    }

    /// Tolerantes Lesen: fehlerhafte Angaben werden korrigiert statt die ganze Warteschlange zu verwerfen.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var items = (try? c.decodeIfPresent([Item].self, forKey: .items)) ?? []
        // Kennungen müssen eindeutig sein
        var seen = Set<Int64>()
        var maxID: Int64 = 0
        for item in items { maxID = max(maxID, item.id) }
        var next = max(maxID + 1, ((try? c.decodeIfPresent(Int64.self, forKey: .nextItemID)) ?? nil) ?? 1)
        for i in items.indices where !seen.insert(items[i].id).inserted {
            items[i] = Item(id: next, trackUid: items[i].trackUid)
            seen.insert(next)
            next += 1
        }
        self.items = items
        nextItemID = next
        repeatMode = ((try? c.decodeIfPresent(RepeatSetting.self, forKey: .repeatMode)) ?? nil) ?? .off
        source = (try? c.decodeIfPresent(PlaybackSource.self, forKey: .source)) ?? nil
        let storedCurrent = ((try? c.decodeIfPresent(Int.self, forKey: .currentIndex)) ?? nil)
        if items.isEmpty {
            currentIndex = nil
        } else if let storedCurrent, items.indices.contains(storedCurrent) {
            currentIndex = storedCurrent
        } else {
            currentIndex = 0
        }
        shuffleEnabled = ((try? c.decodeIfPresent(Bool.self, forKey: .shuffleEnabled)) ?? nil) ?? false
        if shuffleEnabled {
            let stored = (try? c.decodeIfPresent(StartFirstShuffleOrder.self, forKey: .shuffleOrder)) ?? nil
            if let stored, stored.length == items.count {
                shuffleOrder = stored
            } else {
                // Ersatz ohne Zufall: laufender Eintrag vorn, Rest in Listenreihenfolge.
                let cur = currentIndex ?? 0
                shuffleOrder = items.isEmpty ? .empty : StartFirstShuffleOrder(order: [cur] + items.indices.filter { $0 != cur })!
            }
        } else {
            shuffleOrder = .empty
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(items, forKey: .items)
        try c.encodeIfPresent(currentIndex, forKey: .currentIndex)
        try c.encode(shuffleEnabled, forKey: .shuffleEnabled)
        if shuffleEnabled { try c.encode(shuffleOrder, forKey: .shuffleOrder) }
        try c.encode(repeatMode, forKey: .repeatMode)
        try c.encodeIfPresent(source, forKey: .source)
        try c.encode(nextItemID, forKey: .nextItemID)
    }
}
