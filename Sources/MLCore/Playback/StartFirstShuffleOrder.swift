import Foundation

/// Zufallsreihenfolge der Warteschlange (Portierung von `playback/StartFirstShuffleOrder.kt`, dort die
/// Media3-Schnittstelle `ShuffleOrder`). Die Logik steckt in `ShuffleLogic`:
/// Starttitel vorn, alle übrigen genau einmal danach; „Als Nächstes“ eingereihte Titel direkt hinter dem
/// laufenden Titel.
///
/// Werte sind Listenpositionen (Index in der Warteschlange); `order[k]` = k-ter Titel der Abspielfolge.
public struct StartFirstShuffleOrder: Hashable, Sendable, Codable {
    public let order: [Int]
    private let position: [Int]

    public static let empty = StartFirstShuffleOrder(validOrder: [])

    private init(validOrder: [Int]) {
        order = validOrder
        var pos = Array(repeating: 0, count: validOrder.count)
        for (i, v) in validOrder.enumerated() { pos[v] = i }
        position = pos
    }

    /// Übernimmt eine gespeicherte Reihenfolge; ist sie keine gültige Permutation von 0..<n, `nil`.
    public init?(order: [Int]) {
        guard StartFirstShuffleOrder.isPermutation(order) else { return nil }
        self.init(validOrder: order)
    }

    /// Neue Zufallsreihenfolge; `first` (Listenposition, falls gültig) steht vorn.
    public init<R: RandomNumberGenerator>(length: Int, first: Int?, using random: inout R) {
        self.init(validOrder: ShuffleLogic.create(length: length, first: first, using: &random))
    }

    public init(length: Int, first: Int?) {
        var rng = SystemRandomNumberGenerator()
        self.init(length: length, first: first, using: &rng)
    }

    public var length: Int { order.count }
    public var firstIndex: Int? { order.first }
    public var lastIndex: Int? { order.last }

    /// Stelle der Listenposition `index` in der Abspielfolge.
    public func playPosition(of index: Int) -> Int? {
        guard index >= 0 && index < position.count else { return nil }
        return position[index]
    }

    public func nextIndex(after index: Int) -> Int? {
        guard let p = playPosition(of: index), p + 1 < order.count else { return nil }
        return order[p + 1]
    }

    public func previousIndex(before index: Int) -> Int? {
        guard let p = playPosition(of: index), p - 1 >= 0 else { return nil }
        return order[p - 1]
    }

    /// `count` Einträge ab Listenposition `insertionIndex` eingefügt (direkt hinter ihrem Vorgänger).
    public func inserting(at insertionIndex: Int, count: Int) -> StartFirstShuffleOrder {
        StartFirstShuffleOrder(validOrder: ShuffleLogic.insert(order, insertionIndex: insertionIndex, count: count))
    }

    /// `count` Einträge am Ende der Liste angehängt – sie kommen ans Ende der Abspielfolge
    /// („Zur Warteschlange hinzufügen“).
    public func appending(count: Int) -> StartFirstShuffleOrder {
        guard count > 0 else { return self }
        return StartFirstShuffleOrder(validOrder: order + Array(order.count..<(order.count + count)))
    }

    /// Listenpositionen `from..<toExclusive` entfernt; spätere rücken nach.
    public func removing(from: Int, toExclusive: Int) -> StartFirstShuffleOrder {
        StartFirstShuffleOrder(validOrder: ShuffleLogic.remove(order, from: from, toExclusive: toExclusive))
    }

    /// Eintrag der Abspielfolge an Stelle `from` an Stelle `to` verschieben (Ziehen in „Als Nächstes“).
    public func movingPlayPosition(from: Int, to: Int) -> StartFirstShuffleOrder {
        StartFirstShuffleOrder(validOrder: PlaylistOrdering.move(order, from: from, to: to))
    }

    static func isPermutation(_ order: [Int]) -> Bool {
        var seen = Array(repeating: false, count: order.count)
        for v in order {
            guard v >= 0 && v < order.count && !seen[v] else { return false }
            seen[v] = true
        }
        return true
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode([Int].self)
        guard StartFirstShuffleOrder.isPermutation(raw) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Keine gültige Reihenfolge")
        }
        self.init(validOrder: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(order)
    }

    public static func == (lhs: StartFirstShuffleOrder, rhs: StartFirstShuffleOrder) -> Bool { lhs.order == rhs.order }
    public func hash(into hasher: inout Hasher) { hasher.combine(order) }
}
