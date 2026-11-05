import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import MLCore
import MLTags

// Cover und Ersatzbilder – Übertragung von ui/components/Artwork.kt und cover/CoverLoader.kt.

/// Größenklassen der Cover (Punkte; gerendert wird in doppelter Auflösung).
enum ArtworkSize: Int, CaseIterable {
    case small = 64     // Listen, Mini-Player
    case thumb = 150    // kompaktes Raster, kleine Kacheln, Cover Flow am Rand
    case medium = 260   // Raster, Kopf von Detailansichten
    case large = 720    // Player, Bearbeitungsfenster

    /// Passende Größe für eine Kachel/Fläche der angegebenen Breite in Punkten.
    static func fitting(_ points: CGFloat) -> ArtworkSize {
        if points <= 64 { return .small }
        if points <= 150 { return .thumb }
        if points <= 300 { return .medium }
        return .large
    }

    var pixels: Int { rawValue * 2 }
}

/// Lädt Cover im Hintergrund, verkleinert sie (ImageIO) und hält sie im Arbeitsspeicher und auf der Platte vor.
final class ArtworkStore: @unchecked Sendable {
    static let shared = ArtworkStore()

    private let memory = NSCache<NSString, NSImage>()
    private let lock = NSLock()
    private var missing = Set<String>()
    private var overrides: [Int64: String] = [:]
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 4
        q.qualityOfService = .utility
        q.name = "Cover"
        return q
    }()
    let cacheDirectory: URL

    init() {
        memory.totalCostLimit = 320 * 1024 * 1024
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        cacheDirectory = caches.appendingPathComponent("Music Library/Covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Eigene Cover aus der Bibliothek (für Formate ohne Bildspeicher) – vom AppModel gesetzt.
    func setOverrides(_ map: [Int64: String]) {
        lock.lock()
        overrides = map
        lock.unlock()
    }

    private func key(_ track: Track, _ size: ArtworkSize) -> String { "\(track.coverKey)@\(size.rawValue)" }

    func cached(_ track: Track, _ size: ArtworkSize) -> NSImage? {
        memory.object(forKey: key(track, size) as NSString)
    }

    func knownMissing(_ track: Track) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return missing.contains(track.coverKey)
    }

    /// Verwirft alles zu einem Titel (nach dem Ändern des Covers).
    func invalidate(_ track: Track) {
        for s in ArtworkSize.allCases { memory.removeObject(forKey: key(track, s) as NSString) }
        lock.lock()
        missing.remove(track.coverKey)
        lock.unlock()
    }

    func clearDiskCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        memory.removeAllObjects()
        lock.lock()
        missing.removeAll()
        lock.unlock()
    }

    /// Cover laden (Zwischenspeicher zuerst, dann im Hintergrund).
    func image(for track: Track, size: ArtworkSize) async -> NSImage? {
        if let img = cached(track, size) { return img }
        if knownMissing(track) { return nil }
        let k = key(track, size)
        return await withCheckedContinuation { (cont: CheckedContinuation<NSImage?, Never>) in
            queue.addOperation { [weak self] in
                guard let self else { return cont.resume(returning: nil) }
                let img = self.load(track, size)
                if let img {
                    self.memory.setObject(img, forKey: k as NSString, cost: size.pixels * size.pixels * 4)
                } else {
                    self.lock.lock()
                    self.missing.insert(track.coverKey)
                    self.lock.unlock()
                }
                cont.resume(returning: img)
            }
        }
    }

    private func diskURL(_ track: Track, _ size: ArtworkSize) -> URL {
        cacheDirectory.appendingPathComponent("\(track.coverKey)-\(size.rawValue).jpg")
    }

    private func load(_ track: Track, _ size: ArtworkSize) -> NSImage? {
        let disk = diskURL(track, size)
        // Sofort im Hintergrund dekodieren und in den Farbraum des Bildschirms umrechnen – sonst würde das Bild
        // beim Anzeigen auf dem Hauptthread entpackt und farbkonvertiert (gemessen: bis zu 12 % der
        // Hauptthread-Zeit beim Scrollen großer Raster, `CA::Render::copy_image`).
        if let cg = Self.decodeFile(disk) {
            return Self.nsImage(Self.displayReady(cg, space: displayColorSpace()))
        }
        guard let data = Self.sourceImageData(for: track, overrides: currentOverrides()) else { return nil }
        guard let cg = Self.downsample(data: data, maxPixels: size.pixels) else { return nil }
        if let jpeg = Self.jpegData(cg, quality: 0.86) {
            try? jpeg.write(to: disk, options: .atomic)
            noteDiskWrite()
        }
        return Self.nsImage(Self.displayReady(cg, space: displayColorSpace()))
    }

    private static func nsImage(_ cg: CGImage) -> NSImage {
        NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
    }

    // MARK: Farbraum des Bildschirms

    private var screenSpace: CGColorSpace?

    /// Farbraum des Hauptbildschirms merken (auf dem Hauptthread aufrufen: beim Start und wenn sich die
    /// Bildschirme ändern). Bereits geladene Cover bleiben gültig, werden aber ggf. noch einmal umgerechnet.
    @MainActor
    func updateDisplayColorSpace() {
        let space = NSScreen.main?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        lock.lock()
        let changed = screenSpace != space
        screenSpace = space
        lock.unlock()
        if changed { memory.removeAllObjects() }
    }

    private func displayColorSpace() -> CGColorSpace? {
        lock.lock()
        defer { lock.unlock() }
        return screenSpace
    }

    /// Bild im Format, das Core Animation direkt übernimmt (BGRA, vormultipliert, Farbraum des Bildschirms) –
    /// die Umrechnung geschieht hier im Hintergrund statt beim Zeichnen auf dem Hauptthread.
    static func displayReady(_ image: CGImage, space: CGColorSpace?) -> CGImage {
        guard let space = space ?? CGColorSpace(name: CGColorSpace.sRGB) else { return image }
        let info: UInt32 = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        if image.colorSpace == space && image.bitmapInfo.rawValue == info && image.bitsPerComponent == 8 { return image }
        guard image.width > 0, image.height > 0,
              let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: info) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage() ?? image
    }

    /// Datei lesen und sofort dekodieren (kein verzögertes Entpacken beim Zeichnen).
    static func decodeFile(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    // MARK: Größe des Zwischenspeichers auf der Platte

    private var diskLimitBytes: Int64 = 500 * 1024 * 1024
    private var writesSincePrune = 0

    /// Obergrenze des Cover-Zwischenspeichers (Einstellung „Speicher & Cache“); ältere Bilder werden entfernt.
    func setDiskLimit(megabytes: Int) {
        lock.lock()
        diskLimitBytes = Int64(max(50, megabytes)) * 1024 * 1024
        lock.unlock()
        queue.addOperation { [weak self] in self?.pruneDisk() }
    }

    private func noteDiskWrite() {
        lock.lock()
        writesSincePrune += 1
        let due = writesSincePrune >= 300
        if due { writesSincePrune = 0 }
        lock.unlock()
        if due { pruneDisk() }
    }

    /// Belegter Platz des Cover-Zwischenspeichers in Bytes.
    func diskUsage() -> Int64 {
        let keys: [URLResourceKey] = [.fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: keys)) ?? []
        return files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: Set(keys)).fileSize) ?? 0) }
    }

    private func pruneDisk() {
        lock.lock()
        let limit = diskLimitBytes
        lock.unlock()
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: keys) else { return }
        var entries = files.compactMap { url -> (URL, Int64, Date)? in
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, Int64(v.fileSize ?? 0), v.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(Int64(0)) { $0 + $1.1 }
        guard total > limit else { return }
        entries.sort { $0.2 < $1.2 }
        for (url, size, _) in entries {
            if total <= limit * 9 / 10 { break }
            try? FileManager.default.removeItem(at: url)
            total -= size
        }
    }

    private func currentOverrides() -> [Int64: String] {
        lock.lock()
        defer { lock.unlock() }
        return overrides
    }

    /// Bilddaten eines Titels: eigenes Bibliothekscover, eingebettetes Cover (Vorderseite) oder Bild im Ordner.
    static func sourceImageData(for track: Track, overrides: [Int64: String]) -> Data? {
        if let custom = overrides[track.uid], let data = try? Data(contentsOf: URL(fileURLWithPath: custom)) { return data }
        if track.hasPicture, let result = try? TagFile.read(url: URL(fileURLWithPath: track.path)), let pic = result.values.frontCover {
            return pic.data
        }
        return folderImageData(for: track)
    }

    /// Typische Cover-Dateien neben der Musik („cover.jpg“, „folder.jpg“ …).
    static func folderImageData(for track: Track) -> Data? {
        let dir = URL(fileURLWithPath: track.path).deletingLastPathComponent()
        let names = ["cover", "folder", "front", "album", "albumart", "Cover", "Folder", "Front", "AlbumArt"]
        let exts = ["jpg", "jpeg", "png", "webp", "JPG", "PNG"]
        for n in names {
            for e in exts {
                let url = dir.appendingPathComponent("\(n).\(e)")
                if FileManager.default.fileExists(atPath: url.path), let data = try? Data(contentsOf: url) { return data }
            }
        }
        return nil
    }

    static func downsample(data: Data, maxPixels: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    static func jpegData(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    /// Mittlere Farben eines Covers (für Hintergründe) – über das portierte CoverPalette-Modell.
    static func pixels(of image: NSImage, side: Int = 48) -> (pixels: [UInt32], width: Int, height: Int)? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var buffer = [UInt32](repeating: 0, count: side * side)
        let ok: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return ok ? (buffer, side, side) : nil
    }
}

// MARK: - Ansichten

/// Genre-Familie eines Titels/Namens und ihre Farben (über das portierte GenreCategories/GenrePalette).
enum GenreStyle {
    static func category(_ name: String?) -> GenreCategory { GenreCategories.of(name) }

    static func tint(_ category: GenreCategory) -> Color { Color(argb: GenrePalette.forCategory(category)) }

    static func tint(text: String) -> Color { Color(argb: GenrePalette.forText(text)) }

    /// Sanfter Verlauf aus einem Grundton (oben heller, unten satter) – Android `Tints.gradient`.
    static func gradient(_ base: Color) -> LinearGradient {
        let ns = NSColor(base).usingColorSpace(.sRGB) ?? .gray
        func mix(_ f: CGFloat, toWhite: Bool) -> Color {
            let r = ns.redComponent, g = ns.greenComponent, b = ns.blueComponent
            if toWhite {
                return Color(.sRGB, red: Double(r + (1 - r) * f), green: Double(g + (1 - g) * f), blue: Double(b + (1 - b) * f), opacity: 1)
            }
            return Color(.sRGB, red: Double(r * (1 - f)), green: Double(g * (1 - f)), blue: Double(b * (1 - f)), opacity: 1)
        }
        return LinearGradient(colors: [mix(0.22, toWhite: true), base, mix(0.18, toWhite: false)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Symbol der Genre-Familie (Android `GenreIcons.res`).
    static func icon(_ category: GenreCategory) -> String {
        switch category {
        case .rock: return "genre_rock"
        case .metal: return "genre_metal"
        case .punk: return "genre_punk"
        case .alternative: return "genre_alternative"
        case .pop: return "genre_pop"
        case .hiphop: return "genre_hiphop"
        case .soulFunk: return "genre_soul"
        case .jazz: return "genre_jazz"
        case .blues: return "genre_blues"
        case .classical: return "genre_classical"
        case .electronic: return "genre_electronic"
        case .dance: return "genre_dance"
        case .reggae: return "genre_reggae"
        case .country: return "genre_country"
        case .folk: return "genre_folk"
        case .latin: return "genre_latin"
        case .world: return "genre_world"
        case .soundtrack: return "genre_soundtrack"
        case .ambient: return "genre_ambient"
        case .schlager: return "genre_schlager"
        case .children: return "genre_children"
        case .spoken: return "genre_spoken"
        case .gospel: return "genre_gospel"
        case .holiday: return "genre_holiday"
        case .instrumental: return "genre_instrumental"
        case .other: return "genre_other"
        case .darkwave: return "genre_alternative"
        case .hardstyle: return "genre_dance"
        case .hardtekk: return "genre_electronic"
        case .anthems: return "genre_classical"
        case .sounds: return "genre_other"
        case .unknown: return Icons.musicNote
        }
    }

    /// Eigenes Titelbild einzelner Genres (Android `GenreArtwork`).
    static func artworkName(_ category: GenreCategory) -> String? {
        switch category {
        case .darkwave: return "genre_art_darkwave"
        case .hardstyle: return "genre_art_hardstyle"
        case .hardtekk: return "genre_art_hardtekk"
        case .anthems: return "genre_art_hymnen"
        case .sounds: return "genre_art_sounds"
        default: return nil
        }
    }

    private static var artCache: [String: NSImage] = [:]

    @MainActor
    static func artwork(_ category: GenreCategory) -> NSImage? {
        guard let name = artworkName(category) else { return nil }
        if let img = artCache[name] { return img }
        guard let url = Bundle.main.url(forResource: name, withExtension: "webp", subdirectory: "GenreArt"),
              let loaded = NSImage(contentsOf: url) else { return nil }
        // einmal in den Bildschirmfarbraum umrechnen (nicht bei jedem Anzeigen)
        var img = loaded
        if let cg = loaded.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let ready = ArtworkStore.displayReady(cg, space: NSScreen.main?.colorSpace?.cgColorSpace)
            img = NSImage(cgImage: ready, size: loaded.size)
        }
        artCache[name] = img
        return img
    }
}

/// Cover-Fläche mit feiner Kontur; ohne Cover gedeckter Verlauf der Genre-Familie mit weißem Symbol
/// (Android `ArtworkBox`).
struct ArtworkBox: View {
    @Environment(\.musicColors) private var colors
    let image: NSImage?
    let category: GenreCategory
    var cornerRadius: CGFloat = Radius.artworkSmall
    var iconFraction: CGFloat = 0.5
    var loading: Bool = false
    var circle: Bool = false

    // Ohne GeometryReader für den häufigen Fall „Cover vorhanden“: Kacheln und Zeilen werden beim Scrollen
    // laufend neu angelegt, jeder GeometryReader kostet dabei einen zusätzlichen Layout-Durchgang.
    var body: some View {
        ZStack {
            if let image {
                Color.clear.overlay(
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                )
                .clipped()
            } else if !loading, let art = GenreStyle.artwork(category) {
                Color.clear.overlay(
                    Image(nsImage: art)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                )
                .clipped()
            } else if loading {
                colors.dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
            } else {
                GenreStyle.gradient(GenreStyle.tint(category))
                GeometryReader { geo in
                    Icon(GenreStyle.icon(category), size: min(geo.size.width, geo.size.height) * iconFraction, color: Color.white.opacity(0.92))
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(colors.artworkStroke, lineWidth: 0.6))
    }

    private var shape: AnyInsettableShape {
        circle ? AnyInsettableShape(Circle()) : AnyInsettableShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Typlöschende einfügbare Form (für Kreis/Rechteck-Wechsel).
struct AnyInsettableShape: InsettableShape {
    private let pathBuilder: (CGRect) -> Path
    private let insetBuilder: (CGFloat) -> AnyInsettableShape

    init<S: InsettableShape>(_ shape: S) {
        pathBuilder = { shape.path(in: $0) }
        insetBuilder = { AnyInsettableShape(shape.inset(by: $0)) }
    }

    func path(in rect: CGRect) -> Path { pathBuilder(rect) }
    func inset(by amount: CGFloat) -> AnyInsettableShape { insetBuilder(amount) }
}

/// Cover eines Titels (eingebettet, sonst Genre-Ersatz). Lädt asynchron und zeigt nie das Cover des vorigen Titels.
struct TrackArtwork: View {
    let track: Track?
    var size: ArtworkSize = .small
    var cornerRadius: CGFloat = Radius.artworkSmall
    var iconFraction: CGFloat = 0.5
    var circle: Bool = false
    @State private var image: NSImage?
    @State private var loadedKey: String?

    var body: some View {
        let key = track.map { "\($0.coverKey)@\(size.rawValue)" }
        let cached = track.flatMap { ArtworkStore.shared.cached($0, size) }
        let shown = cached ?? (loadedKey == key ? image : nil)
        let loading = shown == nil && track.map { $0.hasPicture && !ArtworkStore.shared.knownMissing($0) && loadedKey != key } == true
        ArtworkBox(image: shown, category: GenreStyle.category(track?.genres.first), cornerRadius: cornerRadius,
                   iconFraction: iconFraction, loading: loading, circle: circle)
            .task(id: key) {
                guard let track, cached == nil else { return }
                let img = await ArtworkStore.shared.image(for: track, size: size)
                image = img
                loadedKey = key
            }
    }
}

/// Genre-Kachel: eigenes Titelbild, sonst Farbverlauf mit Symbol (Android `GenreArtTile`).
struct GenreArtTile: View {
    let category: GenreCategory
    var cornerRadius: CGFloat = Radius.artwork
    var iconFraction: CGFloat = 0.5

    var body: some View {
        ArtworkBox(image: nil, category: category, cornerRadius: cornerRadius, iconFraction: iconFraction)
    }
}

/// Kachel mit Farbverlauf und weißem Symbol (automatische Playlists) – Android `GradientTile`.
struct GradientTile: View {
    let icon: String
    let base: Color
    var cornerRadius: CGFloat = Radius.artwork
    var iconFraction: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            ZStack {
                GenreStyle.gradient(base)
                Icon(icon, size: min(geo.size.width, geo.size.height) * iconFraction, color: .white)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Monogramm als Ersatzbild (Interpreten ohne Cover) – Android `Monogram`.
struct Monogram: View {
    let name: String
    var size: CGFloat

    var body: some View {
        let initials: String = {
            let parts = name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "&" })
                .filter { $0.first.map { $0.isLetter || $0.isNumber } ?? false }
                .prefix(2)
                .map { String($0.first!).uppercased() }
            return parts.isEmpty ? "♪" : parts.joined()
        }()
        ZStack {
            Circle().fill(GenreStyle.gradient(GenreStyle.tint(text: name)))
            Text(initials)
                .font(Typo.inter(size * 0.36, .bold, display: true))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

/// 2×2-Mosaik aus bis zu vier Covern (Playlists); weniger als vier → das erste Cover groß.
struct MosaicArtwork: View {
    @Environment(\.musicColors) private var colors
    let tracks: [Track]
    var cornerRadius: CGFloat = Radius.artwork
    var fallbackIcon: String = Icons.queue
    var size: ArtworkSize = .small

    var body: some View {
        let withCover: [Track] = {
            var seen = Set<String>()
            var result: [Track] = []
            for t in tracks where t.hasPicture && !seen.contains(t.coverKey) {
                seen.insert(t.coverKey)
                result.append(t)
                if result.count == 4 { break }
            }
            return result
        }()
        Group {
            if withCover.count >= 4 {
                VStack(spacing: 0) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<2, id: \.self) { col in
                                TrackArtwork(track: withCover[row * 2 + col], size: size, cornerRadius: 0)
                            }
                        }
                    }
                }
            } else if let first = withCover.first {
                TrackArtwork(track: first, size: size, cornerRadius: 0)
            } else {
                GradientTile(icon: fallbackIcon, base: Color(argb: 0xFFB27390), cornerRadius: 0, iconFraction: 0.46)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(colors.artworkStroke, lineWidth: 0.6))
    }
}
