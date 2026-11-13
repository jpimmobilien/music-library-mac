import Foundation

// =============================================================================================
// ORBIT – gemeinsame Grundlagen des Designsystems „Spatial Liquid Glass“ (ohne Apple-Frameworks, unter Linux getestet)
//
//  - OrbitPalette: die sieben Grundfarben (identisch mit Android: ui/designsystem/…/OrbitPalette.kt)
//  - EffectProfile: Minimal / Ausgewogen / Immersiv – welche Effekte laufen dürfen
//  - OrbitEffects: aus Profil, Animations-Einstellung und Systemeinstellung „Bewegung reduzieren“ aufgelöst
//  - RollingPeak, OrbitCoreModel: Daten der ORBIT-Core-Ringe – ausschließlich aus Messwerten, nie geschätzt
// =============================================================================================

/// Grundfarben von ORBIT. Bedeutung: Blau = System, Cyan = Datenströme, Violett = intelligente Funktionen
/// (Auswertungen), Grün = positiver Zustand, Orange = erhöhte Werte, Rot nur für kritische Zustände.
public enum OrbitPalette {
    public static let arcticBlue = RGBA(0x3D8BFF)
    public static let electricCyan = RGBA(0x18D6F0)
    public static let deepOcean = RGBA(0x07142B)
    public static let sapphire = RGBA(0x2446C8)
    public static let softViolet = RGBA(0x8C7CFF)
    public static let pearlWhite = RGBA(0xF4F7FB)
    public static let graphite = RGBA(0x2B2F38)
}

/// Stärke der visuellen Effekte. Wählbar in den Einstellungen; „Minimal“ ist zugleich der Leistungsmodus.
public enum EffectProfile: String, Codable, Sendable, CaseIterable, Identifiable {
    case minimal
    case balanced
    case immersive

    public var id: String { rawValue }
}

/// Aufgelöste Effekt-Schalter. Reihenfolge der Vorrangregeln:
/// Systemeinstellung „Bewegung reduzieren“ > Animations-Einstellung der App > Effektprofil.
public struct OrbitEffects: Equatable, Sendable {
    /// Kurzer Auftakt beim Start (≈ 0,9 s, blockiert nichts).
    public var ambientIntro: Bool
    /// Statt des Auftakts nur eine kurze Überblendung (bei reduzierter Bewegung).
    public var introCrossfadeOnly: Bool
    /// Hintergrund-Lichtfelder sichtbar.
    public var ambientLights: Bool
    /// Lichtfelder wandern sehr langsam (nur „Immersiv“, Core Animation, ≤ 12 Bilder/s).
    public var livingBackground: Bool
    /// Lichtfelder verschieben sich beim Bereichswechsel (räumliche Orientierung).
    public var spatialBackground: Bool
    /// Glasreflexion folgt dem Zeiger.
    public var hoverReflection: Bool
    /// Leichte magnetische Anziehung ausgewählter Elemente zum Zeiger.
    public var magneticHover: Bool
    /// Räumliche Übergänge zwischen Bereichen (Tiefe statt nur Überblendung).
    public var spatialTransitions: Bool
    /// Karten verwandeln sich in Detailansichten (gemeinsame Geometrie).
    public var morphingCards: Bool
    /// Große Zahlen wechseln mit einer kurzen, ruhigen Bewegung.
    public var numberTransitions: Bool
    /// Animierte Datenflüsse und Flüssigkeiten (nur bei echter Aktivität bzw. echtem Laden).
    public var dataFlow: Bool

    public static func resolve(profile: EffectProfile, motion: MotionLevel, systemReduceMotion: Bool) -> OrbitEffects {
        let moving = !systemReduceMotion && motion == .full
        let reduced = systemReduceMotion || motion == .reduced
        let none = motion == .off
        switch profile {
        case .minimal:
            return OrbitEffects(ambientIntro: false, introCrossfadeOnly: false, ambientLights: false, livingBackground: false,
                                spatialBackground: false, hoverReflection: false, magneticHover: false,
                                spatialTransitions: false, morphingCards: moving, numberTransitions: false, dataFlow: moving)
        case .balanced:
            return OrbitEffects(ambientIntro: !none, introCrossfadeOnly: reduced, ambientLights: true, livingBackground: false,
                                spatialBackground: moving, hoverReflection: !none, magneticHover: false,
                                spatialTransitions: moving, morphingCards: moving, numberTransitions: false, dataFlow: moving)
        case .immersive:
            return OrbitEffects(ambientIntro: !none, introCrossfadeOnly: reduced, ambientLights: true, livingBackground: moving,
                                spatialBackground: moving, hoverReflection: !none, magneticHover: moving,
                                spatialTransitions: moving, morphingCards: moving, numberTransitions: moving, dataFlow: moving)
        }
    }
}

/// Höchstwert eines Zeitfensters (z. B. Netzwerk: „bezogen auf die Spitze der letzten 5 Minuten“).
/// Speichert Minutenblöcke statt aller Messungen – konstanter Speicher, O(1) pro Messung.
public struct RollingPeak: Sendable, Equatable {
    public let window: TimeInterval
    public let bucket: TimeInterval
    private struct Bucket: Equatable, Sendable {
        var start: TimeInterval
        var max: Double
    }

    private var buckets: [Bucket] = []

    public init(window: TimeInterval = 300, bucket: TimeInterval = 15) {
        self.window = window
        self.bucket = max(1, bucket)
    }

    public mutating func add(_ value: Double, at time: TimeInterval) {
        guard value.isFinite else { return }
        let start = (time / bucket).rounded(.down) * bucket
        if let last = buckets.last, last.start == start {
            buckets[buckets.count - 1].max = Swift.max(last.max, value)
        } else {
            buckets.append(Bucket(start: start, max: value))
        }
        let limit = time - window
        while let first = buckets.first, first.start + bucket <= limit { buckets.removeFirst() }
    }

    /// Höchstwert im Fenster bis `time` (nil, solange keine Messung vorliegt).
    public func peak(at time: TimeInterval) -> Double? {
        let limit = time - window
        return buckets.filter { $0.start + bucket > limit }.map(\.max).max()
    }
}

/// Ringe des ORBIT Core (innen → außen).
public enum OrbitRingKind: String, CaseIterable, Sendable, Identifiable {
    case cpu, gpu, memory, storage, network, battery
    public var id: String { rawValue }
}

/// Zustand eines Rings. `fraction` ist immer ein gemessener Anteil (0…1) – oder fehlt.
public struct OrbitRingState: Equatable, Sendable {
    public enum Basis: Equatable, Sendable {
        /// Anteil gemessen (CPU-Last, belegter Speicher, Ladestand …).
        case measured
        /// Anteil bezogen auf die Spitze des Zeitfensters (Netzwerk) – im Text ausdrücklich so benannt.
        case relativeToPeak(window: TimeInterval)
        /// Kein Wert: macOS stellt ihn nicht bereit, das Gerät hat die Komponente nicht oder es wird noch gemessen.
        case unavailable
    }

    public var kind: OrbitRingKind
    public var fraction: Double?
    public var basis: Basis

    public init(kind: OrbitRingKind, fraction: Double?, basis: Basis) {
        self.kind = kind
        self.fraction = fraction.map { Swift.min(1, Swift.max(0, $0)) }
        self.basis = fraction == nil ? .unavailable : basis
    }

    /// Länge des Bogens (0…1) – auf 0,5 % gerastert, damit sich Ringe nur bei sichtbarer Änderung bewegen.
    public var arc: Double {
        guard let fraction else { return 0 }
        return (fraction * 200).rounded() / 200
    }
}

/// Baut die Ringe aus Messwerten. Kein Ring erhält einen geschätzten oder erfundenen Wert.
public enum OrbitCoreModel {
    /// Untergrenze für die Netzwerk-Skala: Ohne nennenswerten Verkehr soll ein Ring nicht „voll“ wirken.
    public static let networkFloor: Double = 64_000 // 64 kB/s

    public static func networkFraction(current: Double?, peak: Double?) -> Double? {
        guard let current, current.isFinite, current >= 0 else { return nil }
        let reference = Swift.max(peak ?? 0, current, networkFloor)
        return current / reference
    }

    public static func storageFraction(capacity: Int64?, available: Int64?) -> Double? {
        guard let capacity, let available, capacity > 0, available >= 0, available <= capacity else { return nil }
        return Double(capacity - available) / Double(capacity)
    }

    public static func memoryFraction(used: Double?, physical: Double?) -> Double? {
        guard let used, let physical, physical > 0, used >= 0 else { return nil }
        return Swift.min(1, used / physical)
    }
}
