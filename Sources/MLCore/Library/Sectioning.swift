import Foundation

/// Abschnitt einer sortierten Liste (2.2.2): z. B. „2024“ bei Sortierung nach Erscheinungsjahr oder
/// „November 2026“ bei Sortierung nach „Hinzugefügt“. `range` sind die Positionen in der Liste.
public struct LibrarySectionRun: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let range: Range<Int>

    public init(id: String, title: String, range: Range<Int>) {
        self.id = id
        self.title = title
        self.range = range
    }

    public var count: Int { range.count }
}

/// Bildet Abschnitte aus bereits sortierten Listen. Benachbarte Einträge mit gleichem Schlüssel bilden einen
/// Abschnitt – die Reihenfolge (auf- oder absteigend) bestimmt die Sortierung.
public enum LibrarySectioning {
    /// Schlüssel eines Eintrags; `nil` = unbekannt („Ohne Jahr“ bzw. „Unbekannt“).
    public enum Key: Hashable, Sendable {
        case year(Int)
        case month(year: Int, month: Int)
        case unknown
    }

    static let monthNames = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August",
                             "September", "Oktober", "November", "Dezember"]

    /// Erscheinungsjahr (plausibel 1000…9999).
    public static func yearKey(_ year: Int?) -> Key {
        guard let year, year >= 1000, year <= 9999 else { return .unknown }
        return .year(year)
    }

    /// Hinzugefügt (Sekunden seit 1970): im laufenden und im vorigen Kalenderjahr nach Monat, davor nach Jahr.
    public static func addedKey(_ seconds: Int64, nowYear: Int, calendar: Calendar) -> Key {
        guard seconds > 0 else { return .unknown }
        let c = calendar.dateComponents([.year, .month], from: Date(timeIntervalSince1970: TimeInterval(seconds)))
        guard let y = c.year, let m = c.month else { return .unknown }
        return y >= nowYear - 1 ? .month(year: y, month: m) : .year(y)
    }

    /// Wie `addedKey`, aber mit Zwischenspeicher: Der Kalender rechnet nur, wenn ein Eintrag den zuletzt
    /// bestimmten Monat bzw. das zuletzt bestimmte Jahr verlässt. In einer nach „Hinzugefügt“ sortierten Liste
    /// also einmal je Abschnitt statt einmal je Titel (der Kalender ist vergleichsweise teuer).
    public struct AddedKeyer {
        public let nowYear: Int
        public let calendar: Calendar
        /// Gültigkeitsbereich des letzten Ergebnisses in ganzen Sekunden: lower ≤ s < upper (anfangs leer).
        private var lower: Int64 = 1
        private var upper: Int64 = 0
        private var cached: Key = .unknown

        public init(nowYear: Int, calendar: Calendar) {
            self.nowYear = nowYear
            self.calendar = calendar
        }

        public mutating func key(_ seconds: Int64) -> Key {
            guard seconds > 0 else { return .unknown }
            if seconds >= lower && seconds < upper { return cached }
            let k = LibrarySectioning.addedKey(seconds, nowYear: nowYear, calendar: calendar)
            let unit: Calendar.Component
            switch k {
            case .month: unit = .month
            case .year: unit = .year
            case .unknown: return k
            }
            if let iv = calendar.dateInterval(of: unit, for: Date(timeIntervalSince1970: TimeInterval(seconds))) {
                // Ganze Sekunden: s ≥ start ⇔ s ≥ ⌈start⌉ und s < end ⇔ s < ⌈end⌉
                let lo = Int64(iv.start.timeIntervalSince1970.rounded(.up))
                let hi = Int64(iv.end.timeIntervalSince1970.rounded(.up))
                if lo <= seconds && seconds < hi {
                    lower = lo
                    upper = hi
                    cached = k
                }
            }
            return k
        }
    }

    public static func title(_ key: Key, unknown: String) -> String {
        switch key {
        case .year(let y): return String(y)
        case .month(let y, let m): return "\(monthNames[max(0, min(11, m - 1))]) \(y)"
        case .unknown: return unknown
        }
    }

    static func id(_ key: Key) -> String {
        switch key {
        case .year(let y): return "y\(y)"
        case .month(let y, let m): return "m\(y)-\(m)"
        case .unknown: return "unbekannt"
        }
    }

    /// Abschnitte aus der sortierten Liste. Kommt ein Schlüssel ein zweites Mal vor (nicht zusammenhängend),
    /// bekommt der Abschnitt eine eindeutige Kennung, damit Ansichten ihn auseinanderhalten.
    public static func runs<T>(_ items: [T], unknown: String, key: (T) -> Key) -> [LibrarySectionRun] {
        var out: [LibrarySectionRun] = []
        var seen: [String: Int] = [:]
        var start = 0
        var current: Key?
        func close(_ end: Int) {
            guard let k = current, end > start else { return }
            var ident = id(k)
            if let n = seen[ident] {
                seen[ident] = n + 1
                ident += "-\(n + 1)"
            } else {
                seen[ident] = 1
            }
            out.append(LibrarySectionRun(id: ident, title: title(k, unknown: unknown), range: start..<end))
        }
        for (i, item) in items.enumerated() {
            let k = key(item)
            if k != current {
                close(i)
                start = i
                current = k
            }
        }
        close(items.count)
        return out
    }

    /// Abschnitte für Titel nach der Sortierung (nur Erscheinungsjahr und Hinzugefügt).
    public static func tracks(_ tracks: [Track], sort: Sort<TrackSort>, now: Date = Date(), calendar: Calendar = .current) -> [LibrarySectionRun]? {
        switch sort.field {
        case .year:
            return runs(tracks, unknown: "Ohne Jahr") { yearKey($0.year) }
        case .dateAdded:
            var keyer = AddedKeyer(nowYear: calendar.component(.year, from: now), calendar: calendar)
            return runs(tracks, unknown: "Unbekannt") { keyer.key($0.dateAdded) }
        default:
            return nil
        }
    }

    /// Abschnitte für Alben nach der Sortierung (nur Erscheinungsjahr und Hinzugefügt).
    public static func albums(_ albums: [AlbumInfo], sort: Sort<AlbumSort>, now: Date = Date(), calendar: Calendar = .current) -> [LibrarySectionRun]? {
        switch sort.field {
        case .year:
            return runs(albums, unknown: "Ohne Jahr") { yearKey($0.year) }
        case .dateAdded:
            var keyer = AddedKeyer(nowYear: calendar.component(.year, from: now), calendar: calendar)
            return runs(albums, unknown: "Unbekannt") { keyer.key($0.dateAdded) }
        default:
            return nil
        }
    }
}
