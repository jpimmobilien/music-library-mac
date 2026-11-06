import SwiftUI
import AppKit
import MLCore

// Gemeinsame Bausteine der Bibliotheksansichten (v2): Ansichtsarten, Einträge als schlanke Werte,
// Spalten der Detailliste, Formatierung und eine fließende Anordnung für Filter-Chips.

// MARK: - Symbole

/// Symbolnamen der Bibliotheksansichten – direkt die Namen aus IconData, damit diese Dateien nicht von
/// späteren Ergänzungen in Design/Icons.swift abhängen.
enum LibIcon {
    static let grid = "view_module"
    static let compactGrid = "grid_view"
    static let list = "view_list"
    static let detailed = "table_rows"
    static let coverFlow = "view_carousel"
    static let sort = "swap_vert"
    static let ascending = "arrow_upward"
    static let descending = "arrow_downward"
    static let filter = "filter_alt"
    static let filterOff = "filter_alt_off"
    static let options = "tune"
    static let zoomIn = "zoom_in"
    static let zoomOut = "zoom_out"
    static let minus = "remove"
    static let restart = "restart_alt"
    static let open = "open_in_new"
    static let newReleases = "new_releases"
    static let schedule = "schedule"
    static let discover = "manage_search"
    static let category = "category"
}

// MARK: - Ansichtsarten und Bereiche

extension LibraryViewMode {
    /// Symbol im Umschalter.
    var libIcon: String {
        switch self {
        case .grid: return LibIcon.grid
        case .compactGrid: return LibIcon.compactGrid
        case .list: return LibIcon.list
        case .detailedList: return LibIcon.detailed
        case .coverFlow: return LibIcon.coverFlow
        }
    }

    /// Wirkt die Covergröße in dieser Ansicht?
    var usesCoverSize: Bool { self == .grid || self == .compactGrid || self == .coverFlow }

    var isGrid: Bool { self == .grid || self == .compactGrid }
}

extension LibraryViewContext {
    /// Erste, breite Spalte der Detailliste (mit Cover) – wird immer gezeigt.
    var primaryColumn: DetailColumn {
        switch self {
        case .albums, .favoriteAlbums: return .album
        case .tracks, .favoriteTracks, .playlists, .artists, .genres: return .title
        }
    }

    /// Playlists werden nur gesucht, nicht gefiltert.
    var supportsFilter: Bool { self != .playlists }

    /// Spaltenüberschrift („Name“ bei Playlists, Interpreten und Genres; „Erstellt“ bei Playlists).
    func columnLabel(_ column: DetailColumn) -> String {
        column.label(for: self)
    }

    /// Wählbare Spalten (ohne die feste erste Spalte).
    var optionalColumns: [DetailColumn] {
        let primary = primaryColumn
        return LibraryViewOptions.availableColumns(for: self).filter { $0 != primary }
    }
}

// MARK: - Fenstergröße für adaptive Ansichten

private struct LibraryViewportKey: EnvironmentKey {
    static let defaultValue = CGSize(width: 1100, height: 760)
}

extension EnvironmentValues {
    /// Sichtbare Größe des Bibliotheksbereichs (in 20-pt-Schritten, damit Größenänderungen nicht ständig neu zeichnen).
    var libraryViewport: CGSize {
        get { self[LibraryViewportKey.self] }
        set { self[LibraryViewportKey.self] = newValue }
    }
}

// MARK: - Live-Werte während Regler/Zoom (erst beim Loslassen gespeichert)

final class LibraryLiveState: ObservableObject {
    static let shared = LibraryLiveState()
    @Published var coverSize: [LibraryViewContext: Double] = [:]
    @Published var spacing: [LibraryViewContext: Double] = [:]

    func apply(_ options: LibraryViewOptions, _ context: LibraryViewContext) -> LibraryViewOptions {
        var o = options
        if let c = coverSize[context] { o.coverSize = c }
        if let s = spacing[context] { o.spacing = s }
        return o
    }

    static func clampCover(_ value: Double) -> Double {
        let r = LibraryViewOptions.coverSizeRange
        return min(max(value, r.lowerBound), r.upperBound)
    }

    static func clampSpacing(_ value: Double) -> Double {
        let r = LibraryViewOptions.spacingRange
        return min(max(value, r.lowerBound), r.upperBound)
    }
}

// MARK: - Bewegung

enum LibraryMotion {
    static func modeAnimation(_ level: AnimationLevel, reduceMotion: Bool) -> Animation? {
        switch level {
        case .off: return nil
        case .reduced: return Motion.easeOut(Motion.short)
        case .full: return reduceMotion ? Motion.easeOut(Motion.short) : Motion.easeOut(Motion.medium)
        }
    }

    static func modeTransition(_ level: AnimationLevel, reduceMotion: Bool) -> AnyTransition {
        if level == .off { return .identity }
        if level == .reduced || reduceMotion { return .opacity }
        return AnyTransition.opacity.combined(with: .scale(scale: 0.985, anchor: .top))
    }

    /// Einrasten im Cover Flow.
    static func snap(_ level: AnimationLevel, reduceMotion: Bool) -> Animation? {
        switch level {
        case .off: return nil
        case .reduced: return Motion.easeOut(Motion.short)
        case .full: return reduceMotion ? Motion.easeOut(Motion.short) : Motion.gentleSpring
        }
    }
}

// MARK: - Formatierung

enum LibraryFormat {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM.yyyy"
        return f
    }()

    static func date(seconds: Int64) -> String {
        guard seconds > 0 else { return "–" }
        return dayFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }

    static func date(ms: Int64?) -> String {
        guard let ms, ms > 0 else { return "–" }
        return date(seconds: ms / 1000)
    }

    static func year(_ year: Int?) -> String {
        guard let year else { return "–" }
        return String(year)
    }

    /// Bewertung 0…100 als Sterne („★★★★☆“).
    static func stars(_ rating: Int?) -> String {
        guard let rating, rating > 0 else { return "–" }
        let filled = min(5, max(1, Int((Double(rating) / 20).rounded())))
        return String(repeating: "★", count: filled) + String(repeating: "☆", count: 5 - filled)
    }
}

/// Titel mehrerer Gruppen (Alben, Interpreten …).
enum TrackUids {
    /// Vereinigung ohne Doppelte, Reihenfolge wie angegeben.
    static func union(_ groups: [[Int64]]) -> [Int64] {
        var seen = Set<Int64>()
        var out: [Int64] = []
        for group in groups {
            for uid in group where seen.insert(uid).inserted { out.append(uid) }
        }
        return out
    }
}

/// „1.234 Titel“ bzw. „12 von 1.234 Titel“, wenn gesucht oder gefiltert wird.
func librarySummary(_ shown: Int, _ total: Int, narrowed: Bool, _ format: (Int) -> String) -> String {
    narrowed ? "\(Formatting.integer(shown)) von \(format(total))" : format(total)
}

// MARK: - Fließende Anordnung (Chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth: CGFloat = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width
            widest = max(widest, x)
            x += spacing
            lineHeight = max(lineHeight, size.height)
        }
        var width: CGFloat = widest
        if let w = proposal.width, w.isFinite { width = w }
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > bounds.width {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            view.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Einträge als Werte

/// Bild eines Eintrags (vergleichbar, damit Kacheln/Zeilen `Equatable` sein können).
enum LibraryArt: Equatable {
    case track(Track?)
    case genre(GenreCategory)
    case gradient(icon: String, argb: UInt32)
    case mosaic([Track])
    case monogram(String)
    case add
}

/// Ein Eintrag einer Sammlung (Album, Interpret, Genre, Playlist, Titel) – schlanker Wert für Kacheln,
/// Zeilen, Detailliste und Cover Flow.
struct LibraryItem: Identifiable, Equatable {
    let id: String
    var title: String
    var subtitle: String? = nil
    var detail: String? = nil
    var art: LibraryArt
    var circle: Bool = false
    /// Name auf dem Bild (Genre-Karten).
    var titleInside: Bool = false
    /// Automatische Playlist (kleines Funkeln am Namen).
    var automatic: Bool = false
    /// `nil` = ohne Herz.
    var favorite: Bool? = nil
    /// Enthält den laufenden Titel.
    var current: Bool = false
    var trackUids: [Int64] = []
    /// Ziel für gezogene Titel (eigene Playlists, „Neue Playlist“).
    var acceptsDrop: Bool = false
    /// Lässt sich auswählen (⌘-Klick, Auswahlrahmen)? Nicht z. B. „Neue Playlist …“.
    var selectable: Bool = true
}

/// Darstellung eines `LibraryArt`.
struct LibraryArtView: View {
    @Environment(\.musicColors) private var colors
    let art: LibraryArt
    var size: ArtworkSize = .medium
    var cornerRadius: CGFloat = Radius.artwork
    var circle: Bool = false
    var iconFraction: CGFloat = 0.42

    var body: some View {
        switch art {
        case .track(let track):
            TrackArtwork(track: track, size: size, cornerRadius: cornerRadius, iconFraction: iconFraction, circle: circle)
        case .genre(let category):
            ArtworkBox(image: nil, category: category, cornerRadius: cornerRadius, iconFraction: iconFraction, circle: circle)
        case .gradient(let icon, let argb):
            GradientTile(icon: icon, base: Color(argb: argb), cornerRadius: circle ? 9999 : cornerRadius, iconFraction: iconFraction)
        case .mosaic(let tracks):
            MosaicArtwork(tracks: tracks, cornerRadius: cornerRadius, size: size == .small ? .small : .medium)
        case .monogram(let name):
            MonogramFill(name: name)
        case .add:
            AddArtwork(cornerRadius: cornerRadius)
        }
    }
}

/// Monogramm, das seinen Rahmen füllt.
struct MonogramFill: View {
    let name: String

    var body: some View {
        GeometryReader { geo in
            Monogram(name: name, size: min(geo.size.width, geo.size.height))
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// Fläche „Neue Playlist“.
struct AddArtwork: View {
    @Environment(\.musicColors) private var colors
    var cornerRadius: CGFloat = Radius.artwork

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        GeometryReader { geo in
            Icon(Icons.add, size: min(geo.size.width, geo.size.height) * 0.34, color: colors.accentText)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(shape.fill(colors.accentSoft))
        .overlay(shape.strokeBorder(colors.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
    }
}

// MARK: - Kachelmaße

struct TileStyle: Equatable {
    var compact: Bool
    var showSecondary: Bool
    var showDetails: Bool
    var artworkSize: ArtworkSize
}

/// Kachelbreite, Abstand und Stil aus den Ansichtsoptionen (Raster und kompaktes Raster).
///
/// v2.1 (Cover bis 560 pt): Die Spaltenzahl wird aus der verfügbaren Breite berechnet (so viele Kacheln der
/// gewählten Größe, wie nebeneinander passen – mindestens eine). Die Spalten sind flexibel: Ist das Fenster
/// schmaler als eine Kachel, wird sie kleiner statt abgeschnitten. Die Covergröße richtet sich nach der
/// tatsächlichen Kachelbreite in Bildpunkten (Retina), damit große Kacheln scharf bleiben.
struct TileMetrics: Equatable {
    var style: TileStyle
    var minWidth: CGFloat
    var spacing: CGFloat
    var columnCount: Int
    /// Erwartete Kachelbreite (für die Wahl der Covergröße).
    var tileWidth: CGFloat

    /// - Parameters:
    ///   - available: Breite für das Raster (Fensterbereich ohne Seitenränder).
    ///   - scale: Bildpunkte je Punkt des Bildschirms (2 bei Retina).
    init(options o: LibraryViewOptions, available: CGFloat, scale: CGFloat = 2) {
        let compact = o.mode == .compactGrid
        let base = CGFloat(o.coverSize)
        let width: CGFloat = compact ? max(64, base * 0.62) : base
        minWidth = width
        spacing = compact ? max(4, CGFloat(o.spacing) * 0.6) : CGFloat(o.spacing)
        let usable = max(available, 60)
        let count = max(1, Int(((usable + spacing) / (width + spacing)).rounded(.down)))
        columnCount = count
        let fill = (usable - CGFloat(count - 1) * spacing) / CGFloat(count)
        tileWidth = max(40, min(fill, width * 1.5)).rounded(.down)
        // Kleine Kacheln laden kleinere Cover (schneller, weniger Speicher auf älteren Macs), große ein großes.
        let artwork = ArtworkSize.forTile(points: tileWidth, scale: scale)
        style = TileStyle(compact: compact, showSecondary: o.showSecondaryText, showDetails: o.showDetails, artworkSize: artwork)
    }

    /// Genau `columnCount` Spalten mit **fester** Breite (aus der Fenstergröße berechnet).
    ///
    /// v2.1-Fehlerbehebung (macOS 26, auch Version 2.0 betroffen): Mit flexiblen bzw. adaptiven Spalten hing die
    /// Kachelgröße von der Inhaltsbreite der Scrollfläche ab. Bei immer sichtbaren Rollbalken (Maus statt Trackpad)
    /// und einem Inhalt knapp so hoch wie das Fenster entstand eine Endlosschleife: Rollbalken erscheint → Kacheln
    /// schmaler und niedriger → Inhalt passt → Rollbalken verschwindet → Kacheln größer → … – AppKit bricht dann
    /// mit „more Layout Window passes than there are views“ ab. Feste Breiten (mit Platz für den Rollbalken)
    /// machen die Höhe unabhängig vom Rollbalken.
    var columns: [GridItem] {
        if Self.flexibleForComparison {
            let maxWidth = max(40, minWidth * 1.5)
            return Array(repeating: GridItem(.flexible(minimum: 40, maximum: maxWidth), spacing: spacing, alignment: .top), count: columnCount)
        }
        return Array(repeating: GridItem(.fixed(tileWidth), spacing: spacing, alignment: .top), count: columnCount)
    }

    /// Nur zum Nachstellen des alten Verhaltens (`ML_AB_FLEXIBLE_GRID=1`).
    static let flexibleForComparison = ProcessInfo.processInfo.environment["ML_AB_FLEXIBLE_GRID"] == "1"
    /// Platz, den ein immer sichtbarer Rollbalken rechts einnimmt.
    static let scrollerAllowance: CGFloat = 16

    var rowSpacing: CGFloat { spacing + (style.compact ? 6 : 12) }

    /// Breite für Raster in einem Bereich (Fensterbereich abzüglich der Seitenränder).
    static func available(_ viewport: CGSize) -> CGFloat {
        viewport.width - Spacing.gutter * 2 - (flexibleForComparison ? 0 : scrollerAllowance)
    }
}

extension ArtworkSize {
    /// Kleinste Covergröße, die eine Fläche dieser Breite (Punkte) auf dem Bildschirm scharf füllt. Bis zu
    /// 15 % Hochrechnen gelten als scharf – so springt nicht schon eine 270-pt-Kachel auf die größte Stufe.
    static func forTile(points: CGFloat, scale: CGFloat) -> ArtworkSize {
        let needed = points * max(scale, 1) * 0.87
        for size in [ArtworkSize.small, .thumb, .medium, .large] where CGFloat(size.pixels) >= needed {
            return size
        }
        return .large
    }
}

// MARK: - Detailliste: Sortierung über die Spaltenköpfe

struct TableSortSpec {
    var descending: Bool = false
    var sortable: Set<DetailColumn> = []
    var isActive: (DetailColumn) -> Bool = { _ in false }
    var onSort: (DetailColumn) -> Void = { _ in }

    static var unsorted: TableSortSpec { TableSortSpec() }
}

/// Zuordnung Spalte → Sortierfeld je Bereich.
enum ColumnSorts {
    static let track: [DetailColumn: TrackSort] = [
        .title: .title, .artist: .artist, .album: .album, .albumArtist: .albumArtist, .genre: .genre, .year: .year,
        .duration: .duration, .plays: .playCount, .lastPlayed: .lastPlayed, .dateAdded: .dateAdded, .rating: .rating, .bpm: .bpm,
    ]
    static let favoriteTrack: [DetailColumn: FavoriteTrackSort] = [
        .title: .title, .artist: .artist, .album: .album, .dateAdded: .dateAdded, .rating: .rating,
    ]
    static let album: [DetailColumn: AlbumSort] = [
        .album: .title, .title: .title, .albumArtist: .artist, .artist: .artist, .genre: .genre, .year: .year, .duration: .duration,
        .plays: .playCount, .lastPlayed: .lastPlayed, .dateAdded: .dateAdded, .trackCount: .trackCount,
    ]
    static let favoriteAlbum: [DetailColumn: FavoriteAlbumSort] = [
        .album: .title, .title: .title, .albumArtist: .artist, .artist: .artist,
    ]
    static let artist: [DetailColumn: ArtistSort] = [
        .artist: .name, .title: .name, .trackCount: .trackCount, .albumCount: .albumCount,
    ]
    static let genre: [DetailColumn: GenreSort] = [
        .genre: .name, .title: .name, .trackCount: .trackCount,
    ]
    static let playlist: [DetailColumn: PlaylistSort] = [
        .title: .name, .trackCount: .trackCount, .dateAdded: .created, .lastPlayed: .modified,
    ]

    static func spec<F: SortField>(_ map: [DetailColumn: F], sort: Sort<F>, set: @escaping (Sort<F>) -> Void) -> TableSortSpec {
        TableSortSpec(
            descending: sort.descending,
            sortable: Set(map.keys),
            isActive: { column in map[column] == sort.field },
            onSort: { column in
                guard let field = map[column] else { return }
                set(field == sort.field ? Sort(field, descending: !sort.descending) : Sort(field))
            }
        )
    }
}

enum TableLayout {
    /// Spalten, die nebeneinander Platz haben (die übrigen entfallen bei schmalen Fenstern).
    static func fit(_ columns: [DetailColumn], available: CGFloat) -> [DetailColumn] {
        var out: [DetailColumn] = []
        var used: CGFloat = 0
        for column in columns {
            let width = CGFloat(column.defaultWidth) + 14
            if used + width > available { break }
            used += width
            out.append(column)
        }
        return out
    }

    /// Platz für Zusatzspalten neben Cover, Name und Herz.
    static func available(_ viewport: CGSize) -> CGFloat {
        viewport.width - Spacing.gutter * 2 - 320
    }
}

// MARK: - Zellen der Detailliste

enum TrackCells {
    static func value(_ t: Track, _ column: DetailColumn, stats: PlayStats?) -> String {
        switch column {
        case .trackNumber: return t.trackNumber.map { String($0) } ?? "–"
        case .title: return t.displayTitle
        case .artist: return t.artistText ?? "–"
        case .album: return t.album ?? "–"
        case .albumArtist: return t.albumArtistText ?? "–"
        case .genre: return t.genreText ?? "–"
        case .year: return LibraryFormat.year(t.year)
        case .duration: return t.durationMs > 0 ? Formatting.duration(t.durationMs) : "–"
        case .plays: return Formatting.integer(stats?.playCount ?? 0)
        case .lastPlayed: return LibraryFormat.date(ms: stats?.lastPlayedAt)
        case .dateAdded: return LibraryFormat.date(seconds: t.dateAdded)
        case .rating: return LibraryFormat.stars(t.rating)
        case .bpm: return t.bpm.map { String($0) } ?? "–"
        case .format: return AudioFormatFamily.of(t)
        case .bitrate: return t.bitrate > 0 ? Formatting.bitrate(kbps: t.bitrate) : "–"
        case .trackCount, .albumCount: return "–"
        }
    }
}

/// Angaben einer Gruppe von Titeln (Album, Interpret, Genre, Playlist) für die Detailliste.
struct GroupFacts {
    var title: String
    var uids: [Int64]
    var trackCount: Int
    var album: String? = nil
    var artist: String? = nil
    var genre: String? = nil
    var year: Int? = nil
    var durationMs: Int64? = nil
    var dateAddedSeconds: Int64? = nil
    var albumCount: Int? = nil
    /// Playlists: Änderungsdatum statt „zuletzt gespielt“.
    var modifiedMs: Int64? = nil
}

enum CollectionCells {
    static func value(_ f: GroupFacts, _ column: DetailColumn, index: LibraryIndex, stats: [Int64: PlayStats]) -> String {
        switch column {
        case .trackNumber, .rating, .bpm, .format, .bitrate:
            return "–"
        case .title:
            return f.title
        case .album:
            return f.album ?? "–"
        case .artist, .albumArtist:
            return f.artist ?? "–"
        case .genre:
            return f.genre ?? "–"
        case .year:
            return LibraryFormat.year(f.year)
        case .duration:
            let ms: Int64 = f.durationMs ?? f.uids.reduce(Int64(0)) { $0 + max(index.trackByUid[$1]?.durationMs ?? 0, 0) }
            return ms > 0 ? Formatting.longDuration(ms) : "–"
        case .plays:
            let plays: Int = f.uids.reduce(0) { $0 + (stats[$1]?.playCount ?? 0) }
            return Formatting.integer(plays)
        case .lastPlayed:
            if let modified = f.modifiedMs { return LibraryFormat.date(ms: modified) }
            return LibraryFormat.date(ms: f.uids.compactMap { stats[$0]?.lastPlayedAt }.max())
        case .dateAdded:
            return f.dateAddedSeconds.map { LibraryFormat.date(seconds: $0) } ?? "–"
        case .trackCount:
            return Formatting.integer(f.trackCount)
        case .albumCount:
            return f.albumCount.map { Formatting.integer($0) } ?? "–"
        }
    }

    static func album(_ a: AlbumInfo, _ column: DetailColumn, index: LibraryIndex, stats: [Int64: PlayStats]) -> String {
        let facts = GroupFacts(title: a.title ?? "Unbekanntes Album", uids: a.trackUids, trackCount: a.trackCount,
                               album: a.title ?? "Unbekanntes Album",
                               artist: a.isVarious ? "Verschiedene Interpreten" : a.artist,
                               genre: a.genre, year: a.year, durationMs: a.totalDurationMs, dateAddedSeconds: a.dateAdded)
        return value(facts, column, index: index, stats: stats)
    }

    static func artist(_ a: ArtistInfo, _ column: DetailColumn, index: LibraryIndex, stats: [Int64: PlayStats]) -> String {
        var facts = GroupFacts(title: a.name, uids: a.trackUids, trackCount: a.trackCount, artist: a.name, albumCount: a.albumKeys.count)
        if column == .genre {
            facts.genre = a.trackUids.first.flatMap { index.trackByUid[$0]?.genres.first }
        }
        return value(facts, column, index: index, stats: stats)
    }

    static func genre(_ g: GenreInfo, _ column: DetailColumn, index: LibraryIndex, stats: [Int64: PlayStats]) -> String {
        var facts = GroupFacts(title: g.name, uids: g.trackUids, trackCount: g.trackCount, genre: g.name)
        if column == .albumCount {
            facts.albumCount = Set(g.trackUids.compactMap { index.albumKeyByTrack[$0] }).count
        }
        return value(facts, column, index: index, stats: stats)
    }
}

// MARK: - Einträge aus den Bibliotheksdaten

@MainActor
enum LibraryItems {
    static func album(_ a: AlbumInfo, model: AppModel, currentUid: Int64?) -> LibraryItem {
        let yearText: String? = a.year.map { String($0) }
        let parts: [String?] = [yearText, Formatting.tracks(a.trackCount), Formatting.longDuration(a.totalDurationMs)]
        let current: Bool = currentUid.map { model.index.albumKeyByTrack[$0] == a.key } ?? false
        return LibraryItem(
            id: a.key,
            title: a.title ?? "Unbekanntes Album",
            subtitle: a.isVarious ? "Verschiedene Interpreten" : (a.artist ?? "Unbekannter Interpret"),
            detail: parts.compactMap { $0 }.joined(separator: " · "),
            art: .track(model.index.coverTrackOf(a)),
            favorite: model.isAlbumFavorite(a.key),
            current: current,
            trackUids: a.trackUids
        )
    }

    static func artist(_ a: ArtistInfo, model: AppModel, currentKeys: Set<String>) -> LibraryItem {
        let cover: Track? = a.trackUids.lazy.compactMap { model.index.trackByUid[$0] }.first { $0.hasPicture }
        let art: LibraryArt = cover.map { LibraryArt.track($0) } ?? .monogram(a.name)
        let albums: String? = a.albumKeys.isEmpty ? nil : Formatting.albums(a.albumKeys.count)
        let parts: [String?] = [Formatting.tracks(a.trackCount), albums]
        return LibraryItem(
            id: a.key,
            title: a.name,
            subtitle: parts.compactMap { $0 }.joined(separator: " · "),
            detail: nil,
            art: art,
            circle: true,
            current: currentKeys.contains(a.key),
            trackUids: a.trackUids
        )
    }

    static func genre(_ g: GenreInfo, currentKeys: Set<String>) -> LibraryItem {
        LibraryItem(
            id: g.key,
            title: g.name,
            subtitle: Formatting.tracks(g.trackCount),
            detail: g.isUnknown ? "Titel ohne Genre-Angabe" : nil,
            art: .genre(g.category),
            titleInside: true,
            current: currentKeys.contains(g.key),
            trackUids: g.trackUids
        )
    }

    static func track(_ t: Track, favorite: Bool, current: Bool) -> LibraryItem {
        LibraryItem(
            id: String(t.uid),
            title: t.displayTitle,
            subtitle: t.artistText ?? "Unbekannter Interpret",
            detail: t.album,
            art: .track(t),
            favorite: favorite,
            current: current,
            trackUids: [t.uid]
        )
    }

    /// Schlüssel der Interpreten des laufenden Titels (für die „läuft gerade“-Markierung).
    static func artistKeys(of track: Track?) -> Set<String> {
        guard let track else { return [] }
        let names = ArtistNames.primaries(track.artists) + ArtistNames.guests(track.artists) + track.albumArtists
        return Set(names.map { ArtistNames.key($0) })
    }

    /// Schlüssel der Genres des laufenden Titels.
    static func genreKeys(of track: Track?) -> Set<String> {
        guard let track else { return [] }
        let keys = track.genres.map { TextNorm.key($0) }.filter { !$0.isEmpty }
        return keys.isEmpty ? [GenreIndex.unknownKey] : Set(keys)
    }
}

// MARK: - Aktionen einer Sammlung

struct CollectionActions {
    var open: (LibraryItem) -> Void
    /// Abspielen (`false`) bzw. Mischen (`true`).
    var play: (LibraryItem, Bool) -> Void
    var toggleFavorite: ((LibraryItem) -> Void)? = nil
    var drop: ((LibraryItem, [Int64]) -> Void)? = nil
    var openLabel: String = "Öffnen"
    /// Wiedergabequelle eines Eintrags (Auswahlleiste, Eingabetaste).
    var source: ((LibraryItem) -> PlaybackSource)? = nil
    /// Nur Alben: die Alben der Ansicht (gefiltert, sortiert) – damit „Zufall“ im Player später nach Alben mischt.
    var albumContext: (() -> [[Int64]])? = nil
}

/// Ziel eines Kontextmenüs einer Sammlung: der angeklickte Eintrag bzw. – gehört er zur Auswahl – die ganze
/// Auswahl.
struct CollectionMenuTarget {
    let item: LibraryItem
    /// Alle betroffenen Titel (ohne Doppelte, in angezeigter Reihenfolge).
    let uids: [Int64]
    /// Je betroffenem Eintrag seine Titel.
    let groups: [[Int64]]
    /// Namen der betroffenen Einträge (höchstens einige).
    let names: [String]

    /// Wirkt das Menü auf mehrere gewählte Einträge?
    var isSelection: Bool { groups.count > 1 }
}

/// Zellen der Detailliste einer Sammlung.
struct CollectionTable<Element> {
    var sort: TableSortSpec
    var cell: (Element, DetailColumn) -> String
}
