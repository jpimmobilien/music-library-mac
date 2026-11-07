import Foundation

/// Rate aus einem monoton steigenden Zähler (Bytes, Operationen). Rücksetzungen (Zähler kleiner als zuvor, z. B.
/// nach Neuverbindung einer Schnittstelle) liefern für diese eine Messung keinen Wert statt eines Sprungs.
public struct CounterRate: Sendable {
    private var lastValue: UInt64?
    private var lastTime: Double?

    public init() {}

    /// - Parameters:
    ///   - value: aktueller Zählerstand
    ///   - time: monotone Zeit in Sekunden (z. B. `ProcessInfo.systemUptime`)
    /// - Returns: Einheiten pro Sekunde oder `nil` (erste Messung, Rücksetzung, keine verstrichene Zeit).
    public mutating func update(value: UInt64, time: Double) -> Double? {
        let previousValue = self.lastValue
        let previousTime = self.lastTime
        self.lastValue = value
        self.lastTime = time
        guard let previousValue, let previousTime else { return nil }
        let dt = time - previousTime
        guard dt > 0.000_1, value >= previousValue else { return nil }
        return Double(value - previousValue) / dt
    }

    public mutating func reset() {
        lastValue = nil
        lastTime = nil
    }
}

/// Summiert Zuwächse mehrerer Zähler (z. B. je Netzwerkschnittstelle) über die Laufzeit – robust gegen
/// Rücksetzungen einzelner Zähler und gegen neu auftauchende oder verschwindende Schnittstellen.
public struct CounterAccumulator: Sendable {
    private var last: [String: UInt64] = [:]
    public private(set) var total: UInt64 = 0

    public init() {}

    /// Gibt den Zuwachs seit dem letzten Aufruf zurück (neue Schlüssel zählen erst ab ihrer zweiten Messung).
    @discardableResult
    public mutating func update(_ counters: [String: UInt64]) -> UInt64 {
        var delta: UInt64 = 0
        for (key, value) in counters {
            if let previous = last[key], value >= previous {
                delta &+= value - previous
            }
        }
        last = counters
        total &+= delta
        return delta
    }
}

/// Fester Ringpuffer für Verläufe (Sparklines). Älteste Werte fallen heraus.
public struct RingBuffer<Element: Sendable>: Sendable {
    public let capacity: Int
    private var storage: [Element] = []
    private var head = 0

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    public mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    public mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        head = 0
    }

    /// Älteste zuerst.
    public var elements: [Element] {
        storage.count < capacity ? storage : Array(storage[head...] + storage[..<head])
    }

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }
    public var last: Element? {
        guard !storage.isEmpty else { return nil }
        return storage.count < capacity ? storage.last : storage[(head + capacity - 1) % capacity]
    }
}

public extension RingBuffer where Element == Double {
    var maximum: Double? { elements.max() }
}
