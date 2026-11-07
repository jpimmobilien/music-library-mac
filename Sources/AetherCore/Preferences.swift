import Foundation

/// Aktualisierungsintervall der Live-Werte.
public enum RefreshInterval: Int, Codable, Sendable, CaseIterable, Identifiable {
    case oneSecond = 1
    case twoSeconds = 2
    case fiveSeconds = 5
    case tenSeconds = 10

    public var id: Int { rawValue }
    public var seconds: Double { Double(rawValue) }

    /// Im Sparmodus mindestens 5 s.
    public func effective(lowImpact: Bool) -> RefreshInterval {
        lowImpact && rawValue < 5 ? .fiveSeconds : self
    }
}

/// Animationsumfang. Die Systemeinstellung „Bewegung reduzieren“ hat immer Vorrang.
public enum MotionLevel: String, Codable, Sendable, CaseIterable, Identifiable {
    case full, reduced, off
    public var id: String { rawValue }
}

/// Informationsdichte.
public enum Density: String, Codable, Sendable, CaseIterable, Identifiable {
    case compact, standard, detailed
    public var id: String { rawValue }

    /// Abstand zwischen Karten und Innenabstand in Punkt.
    public var cardSpacing: Double {
        switch self {
        case .compact: return 10
        case .standard: return 14
        case .detailed: return 16
        }
    }

    public var cardPadding: Double {
        switch self {
        case .compact: return 14
        case .standard: return 18
        case .detailed: return 20
        }
    }
}

/// Karten der Übersicht.
public enum DashboardCard: String, Codable, Sendable, CaseIterable, Identifiable {
    case cpu, memory, thermal, battery, network, storage, gpu, thisMac
    public var id: String { rawValue }
}

/// Reihenfolge und Sichtbarkeit der Übersichtskarten – robust gegen alte oder beschädigte gespeicherte Werte.
public struct DashboardLayout: Equatable, Codable, Sendable {
    public var order: [DashboardCard]
    public var hidden: Set<DashboardCard>

    public init(order: [DashboardCard] = DashboardCard.allCases, hidden: Set<DashboardCard> = []) {
        self.order = order
        self.hidden = hidden
        normalize()
    }

    /// Doppelte entfernen, fehlende (neue) Karten am Ende ergänzen.
    public mutating func normalize() {
        var seen = Set<DashboardCard>()
        var cleaned: [DashboardCard] = []
        for card in order where !seen.contains(card) {
            seen.insert(card)
            cleaned.append(card)
        }
        for card in DashboardCard.allCases where !seen.contains(card) {
            cleaned.append(card)
        }
        order = cleaned
    }

    public var visible: [DashboardCard] { order.filter { !hidden.contains($0) } }

    public mutating func move(_ card: DashboardCard, before target: DashboardCard) {
        guard card != target, let from = order.firstIndex(of: card) else { return }
        order.remove(at: from)
        let to = order.firstIndex(of: target) ?? order.endIndex
        order.insert(card, at: to)
    }

    public mutating func setVisible(_ card: DashboardCard, _ visible: Bool) {
        if visible { hidden.remove(card) } else { hidden.insert(card) }
    }

    /// Aus gespeicherten Rohwerten (unbekannte Namen werden ignoriert).
    public static func restore(order: [String], hidden: [String]) -> DashboardLayout {
        DashboardLayout(order: order.compactMap(DashboardCard.init(rawValue:)),
                        hidden: Set(hidden.compactMap(DashboardCard.init(rawValue:))))
    }
}
