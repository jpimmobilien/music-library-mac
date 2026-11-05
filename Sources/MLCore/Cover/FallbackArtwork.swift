import Foundation

/// Bauplan des Ersatz-Covers für Titel ohne eigenes Cover (reine Logik aus `cover/FallbackArtwork.kt`;
/// das Zeichnen selbst übernimmt die App mit Core Graphics).
///
/// Gleiche Bildsprache wie auf Android: Genre-Titelbild, sonst gedeckter Farbverlauf der Genre-Familie
/// mit hellem Symbol – statt einer leeren grauen Fläche erscheint so immer ein ruhiges Motiv.
public struct FallbackArtworkSpec: Hashable, Sendable {
    /// Name des eigenen Genre-Titelbilds (Asset), falls vorhanden (`genre_art_darkwave` …).
    public var artworkName: String?
    /// Linearer Verlauf von oben links (0) nach unten rechts (1): drei Farben (ARGB) an `gradientStops`.
    public var gradientColors: [UInt32]
    public var gradientStops: [Float]
    /// Weiches Licht oben links: Mittelpunkt (relativ zur Kantenlänge), Radius, Farben innen → außen.
    public var highlightCenter: (x: Float, y: Float)
    public var highlightRadius: Float
    public var highlightColors: [UInt32]
    /// Abdunklung zum Rand: Mittelpunkt, Radius, Farben und Stopps.
    public var vignetteCenter: (x: Float, y: Float)
    public var vignetteRadius: Float
    public var vignetteColors: [UInt32]
    public var vignetteStops: [Float]
    /// Farbe des Genre-Symbols (ARGB) und seine Größe relativ zur Kantenlänge (zentriert).
    public var iconTint: UInt32
    public var iconSizeFraction: Float

    public static func == (a: FallbackArtworkSpec, b: FallbackArtworkSpec) -> Bool {
        a.artworkName == b.artworkName && a.gradientColors == b.gradientColors && a.gradientStops == b.gradientStops
            && a.highlightCenter == b.highlightCenter && a.highlightRadius == b.highlightRadius
            && a.highlightColors == b.highlightColors && a.vignetteCenter == b.vignetteCenter
            && a.vignetteRadius == b.vignetteRadius && a.vignetteColors == b.vignetteColors
            && a.vignetteStops == b.vignetteStops && a.iconTint == b.iconTint && a.iconSizeFraction == b.iconSizeFraction
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(artworkName)
        hasher.combine(gradientColors)
    }
}

public enum FallbackArtwork {

    /// Eigene Titelbilder einzelner Genres (seit 1.2.0).
    public static func artworkName(_ category: GenreCategory) -> String? {
        switch category {
        case .darkwave: return "genre_art_darkwave"
        case .hardstyle: return "genre_art_hardstyle"
        case .hardtekk: return "genre_art_hardtekk"
        case .anthems: return "genre_art_hymnen"
        case .sounds: return "genre_art_sounds"
        default: return nil
        }
    }

    public static func spec(for category: GenreCategory) -> FallbackArtworkSpec {
        let base = GenrePalette.forCategory(category)
        return FallbackArtworkSpec(
            artworkName: artworkName(category),
            gradientColors: [mix(base, 0xFFFF_FFFF, 0.22), base, mix(base, 0xFF00_0000, 0.28)],
            gradientStops: [0, 0.5, 1],
            highlightCenter: (0.28, 0.22),
            highlightRadius: 0.85,
            highlightColors: [0x38FF_FFFF, 0x00FF_FFFF],
            vignetteCenter: (0.5, 0.5),
            vignetteRadius: 0.75,
            vignetteColors: [0x0000_0000, 0x0000_0000, 0x4000_0000],
            vignetteStops: [0, 0.6, 1],
            iconTint: 0xEBFF_FFFF,
            iconSizeFraction: 0.42
        )
    }

    /// Mischt zwei Farben (deckend): `t` = Anteil von `b`.
    public static func mix(_ a: UInt32, _ b: UInt32, _ t: Float) -> UInt32 {
        func ch(_ shift: UInt32) -> UInt32 {
            let va = Float((a >> shift) & 0xFF), vb = Float((b >> shift) & 0xFF)
            return UInt32(min(max(JvmMath.toInt(va * (1 - t) + vb * t), 0), 255))
        }
        return 0xFF00_0000 | ch(16) << 16 | ch(8) << 8 | ch(0)
    }
}
