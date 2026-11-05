import SwiftUI
import AppKit
import MLCore
import MLRender

// Gemeinsame Bausteine der Player-Designs: Farbsätze, Rasterbilder → CGImage, Ebenen-Zwischenspeicher,
// Cover als RasterImage, Farbpalette (siehe docs/PLAYER_SPEC.md, Kapitel 0 und 1.2).

extension MusicColors {
    /// Farbsatz eines Player-Designs (Spec 1.2).
    static func forPlayer(_ theme: PlayerTheme, app: MusicColors) -> MusicColors {
        switch theme {
        case .vinylStudio, .portableCD: return app
        case .classic: return classic
        case .cassette: return cassette
        }
    }

    /// `ClassicColors` (immer dunkel).
    static let classic = MusicColors(
        dark: true,
        background: Color(argb: 0xFF121012), backgroundGrouped: Color(argb: 0xFF151213), surface: Color(argb: 0xFF1C1819),
        surfaceMuted: Color(argb: 0xFF231F20), textPrimary: Color(argb: 0xFFFFFFFF), textSecondary: Color(argb: 0xB8FFFFFF),
        textTertiary: Color(argb: 0x8FFFFFFF), accent: Color(argb: 0xFFFF8FA6), accentText: Color(argb: 0xFFFFA8BA),
        accentStrong: Color(argb: 0xFFFF6F8F), accentSoft: Color(argb: 0x33FF8FA6), onAccent: Color(argb: 0xFF2A0E17),
        heart: Color(argb: 0xFFFF6F8F), danger: Color(argb: 0xFFFF6B6B), hairline: Color(argb: 0x1FFFFFFF),
        ambient: MusicColors.darkPalette.ambient, glassTint: Color(argb: 0x21FFFFFF), glassTintStrong: Color(argb: 0x2BFFFFFF),
        glassEdgeLight: Color(argb: 0x40FFFFFF), glassEdgeDark: Color(argb: 0x12FFFFFF), glassSheen: Color(argb: 0x17FFFFFF),
        glassShadow: Color(argb: 0x66000000), scrim: Color(argb: 0x8C000000), backgroundARGB: 0xFF121012, accentARGB: 0xFFFF8FA6
    )

    /// `CassetteColors` (immer dunkel, warm).
    static let cassette = MusicColors(
        dark: true,
        background: Color(argb: 0xFF141012), backgroundGrouped: Color(argb: 0xFF181315), surface: Color(argb: 0xFF211B1D),
        surfaceMuted: Color(argb: 0xFF231F20), textPrimary: Color(argb: 0xFFF6F2F3), textSecondary: Color(argb: 0xFFB3A8A9),
        textTertiary: Color(argb: 0xFFA8A0A2), accent: Color(argb: 0xFFFF8FA6), accentText: Color(argb: 0xFFFF9DB2),
        accentStrong: Color(argb: 0xFFFF6F8F), accentSoft: Color(argb: 0x2EFF9DB2), onAccent: Color(argb: 0xFF2A0E17),
        heart: Color(argb: 0xFFFF6F8F), danger: Color(argb: 0xFFFF6B6B), hairline: Color(argb: 0x17FFFFFF),
        ambient: MusicColors.darkPalette.ambient, glassTint: Color(argb: 0x24FFE9E0), glassTintStrong: Color(argb: 0x2EFFE9E0),
        glassEdgeLight: Color(argb: 0x3DFFF1EA), glassEdgeDark: Color(argb: 0x0FFFFFFF), glassSheen: Color(argb: 0x14FFF4EE),
        glassShadow: Color(argb: 0x8C000000), scrim: Color(argb: 0x8C000000), backgroundARGB: 0xFF141012, accentARGB: 0xFFFF8FA6
    )
}

enum Raster {
    /// RasterImage (ARGB, nicht vormultipliziert) → CGImage (Spec 0.1).
    static func cgImage(_ r: RasterImage) -> CGImage? {
        guard r.width > 0, r.height > 0 else { return nil }
        let data = r.pixels.withUnsafeBytes { Data($0) } as CFData
        guard let provider = CGDataProvider(data: data), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: r.width, height: r.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: r.width * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.first.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Bild → RasterImage (nicht vormultipliziert), optional auf eine Größe gebracht.
    static func raster(from image: CGImage, width: Int? = nil, height: Int? = nil) -> RasterImage? {
        let w = width ?? image.width
        let h = height ?? image.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt32](repeating: 0, count: w * h)
        let ok: Bool = pixels.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        // Vormultiplikation rückgängig machen
        for i in 0..<pixels.count {
            let p = pixels[i]
            let a = p >> 24
            if a == 0 || a == 255 { continue }
            let r = min(255, ((p >> 16) & 0xFF) * 255 / a)
            let g = min(255, ((p >> 8) & 0xFF) * 255 / a)
            let b = min(255, (p & 0xFF) * 255 / a)
            pixels[i] = (a << 24) | (r << 16) | (g << 8) | b
        }
        return RasterImage(width: w, height: h, pixels: pixels)
    }

    static func cgImage(_ image: NSImage) -> CGImage? {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

/// Zwischenspeicher gerenderter Ebenen je Pixelgröße (höchstens 3 Größen, Spec 0.2).
/// Laufende Berechnungen werden von allen Anfragen derselben Größe geteilt.
final class LayerCache<Layers>: @unchecked Sendable {
    private var cache: [Int: Layers] = [:]
    private var order: [Int] = []
    private var running: [Int: Task<Layers?, Never>] = [:]
    private let lock = NSLock()
    private let render: @Sendable (Int) -> Layers?

    init(render: @escaping @Sendable (Int) -> Layers?) {
        self.render = render
    }

    func cached(_ size: Int) -> Layers? {
        locked { cache[size] }
    }

    /// Kurzer kritischer Abschnitt (synchron, nie über ein `await` hinweg).
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func layers(_ size: Int) async -> Layers? {
        let task: Task<Layers?, Never>? = locked {
            if cache[size] != nil { return nil }
            if let t = running[size] { return t }
            let render = self.render
            let t = Task.detached(priority: .userInitiated) { render(size) }
            running[size] = t
            return t
        }
        guard let task else { return cached(size) }
        let result = await task.value
        locked {
            running[size] = nil
            if let result {
                cache[size] = result
                order.removeAll { $0 == size }
                order.append(size)
                while order.count > 3 {
                    let old = order.removeFirst()
                    cache[old] = nil
                }
            }
        }
        return result
    }
}

/// Ergebnisfach für parallele Berechnungen (jede Aufgabe schreibt genau ein Fach).
final class Slot<T>: @unchecked Sendable {
    var value: T?
}

/// Ebenen des Plattenspielers (Spec 2.3).
struct VinylLayers {
    let size: Int
    let plinth: CGImage
    let record: CGImage
    let sheen: CGImage
    let arm: CGImage
    let armShadow: CGImage
    let armRaster: ArmRaster
    let fallbackLabel: CGImage
    let recordPx: Int
    let labelPx: Int

    static let cache = LayerCache<VinylLayers> { s in
        let recordPx = VinylRenderer.recordSizePx(s)
        let labelPx = VinylRenderer.labelSizePx(s)
        let pl = Slot<RasterImage>(), rc = Slot<RasterImage>(), sh0 = Slot<RasterImage>(), am = Slot<ArmRaster>(), lb = Slot<RasterImage>()
        DispatchQueue.concurrentPerform(iterations: 5) { i in
            switch i {
            case 0: pl.value = VinylRenderer.plinth(s)
            case 1: rc.value = VinylRenderer.record(recordPx)
            case 2: sh0.value = VinylRenderer.sheen(recordPx)
            case 3: am.value = VinylRenderer.tonearm(s)
            default: lb.value = VinylRenderer.fallbackLabel(labelPx)
            }
        }
        guard let plinth = pl.value, let record = rc.value, let sheen = sh0.value, let arm = am.value, let label = lb.value,
              let p = Raster.cgImage(plinth), let r = Raster.cgImage(record), let sh = Raster.cgImage(sheen),
              let a = Raster.cgImage(arm.arm), let as_ = Raster.cgImage(arm.shadow), let l = Raster.cgImage(label) else { return nil }
        return VinylLayers(size: s, plinth: p, record: r, sheen: sh, arm: a, armShadow: as_, armRaster: arm, fallbackLabel: l, recordPx: recordPx, labelPx: labelPx)
    }
}

/// Ebenen der Kassette (Spec 4.3).
struct CassetteLayers {
    let width: Int
    let height: Int
    let back: CGImage
    let front: CGImage
    let pack: CGImage
    let hub: CGImage
    let packPx: Int
    let hubPx: Int

    static let cache = LayerCache<CassetteLayers> { w in
        let bk = Slot<RasterImage>(), fr = Slot<RasterImage>(), pk = Slot<RasterImage>(), hb = Slot<RasterImage>()
        DispatchQueue.concurrentPerform(iterations: 4) { i in
            switch i {
            case 0: bk.value = CassetteRenderer.back(w)
            case 1: fr.value = CassetteRenderer.front(w)
            case 2: pk.value = CassetteRenderer.pack(w)
            default: hb.value = CassetteRenderer.hub(w)
            }
        }
        guard let back = bk.value, let front = fr.value, let pack = pk.value, let hub = hb.value, let b = Raster.cgImage(back), let f = Raster.cgImage(front),
              let p = Raster.cgImage(pack), let h = Raster.cgImage(hub) else { return nil }
        return CassetteLayers(width: w, height: CassetteRenderer.heightFor(w), back: b, front: f, pack: p, hub: h, packPx: pack.width, hubPx: hub.width)
    }
}

/// Ebenen des CD-Players (Spec 5.3) – nacheinander gerechnet (jede Ebene nutzt intern alle Kerne).
struct CDLayers {
    let width: Int
    let height: Int
    let body: CGImage
    let disc: CGImage
    let overlay: CGImage
    let fallbackLabel: CGImage
    let discPx: Int
    let overlayPx: Int
    let labelPx: Int

    static let cache = LayerCache<CDLayers> { w in
        let labelPx = CdGeometry.labelSizePx(w)
        guard let body = Raster.cgImage(CdRenderer.body(w)), let disc = Raster.cgImage(CdRenderer.disc(w)),
              let overlay = Raster.cgImage(CdRenderer.overlay(w)), let label = Raster.cgImage(CdRenderer.fallbackLabel(labelPx)) else { return nil }
        return CDLayers(width: w, height: CdGeometry.heightFor(w), body: body, disc: disc, overlay: overlay, fallbackLabel: label,
                        discPx: CdGeometry.discSizePx(w), overlayPx: CdGeometry.overlaySizePx(w), labelPx: labelPx)
    }
}

/// Cover des laufenden Titels in großer Fassung, als NSImage und als Palette (Classic, CD-Hintergrund).
@MainActor
final class NowPlayingArtwork: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var loading = false
    @Published private(set) var palette: CoverPalette = .neutral
    @Published private(set) var key: String?
    private var paletteCache: [String: CoverPalette] = [:]

    func update(for track: Track?) async {
        guard let track else {
            image = nil
            key = nil
            loading = false
            return
        }
        guard key != track.coverKey else { return }
        key = track.coverKey
        image = ArtworkStore.shared.cached(track, .large)
        loading = image == nil && track.hasPicture
        if image == nil {
            let img = await ArtworkStore.shared.image(for: track, size: .large)
            guard key == track.coverKey else { return }
            image = img
        }
        loading = false
        // Palette: Cover (32 × 32) oder Farbe der Genre-Familie
        if let p = paletteCache[track.coverKey] {
            palette = p
            return
        }
        let img = image
        let category = GenreCategories.of(track.genres.first)
        let p: CoverPalette = await Task.detached(priority: .utility) {
            if let img, let cg = Raster.cgImage(img), let r = Raster.raster(from: cg, width: 32, height: 32) {
                return CoverPalette.from(pixels: r.pixels, width: 32, height: 32)
            }
            return CoverPalette.from(pixels: [UInt32](repeating: GenrePalette.forCategory(category), count: 64))
        }.value
        guard key == track.coverKey else { return }
        if paletteCache.count > 32 { paletteCache.removeAll() }
        paletteCache[track.coverKey] = p
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.9)) { palette = p }
    }
}

/// Rundes Plattenlabel bzw. CD-Ring aus dem Cover (im Hintergrund, je Titel einmal).
enum CoverLabels {
    static func make(_ image: NSImage?, size: Int, cd: Bool) async -> CGImage? {
        guard let image, size > 0 else { return nil }
        return await Task.detached(priority: .userInitiated) {
            guard let cg = Raster.cgImage(image) else { return nil }
            // Seitenverhältnis erhalten (CoverLabel schneidet selbst mittig quadratisch zu);
            // kürzere Seite höchstens max(2 · size, 256) px.
            let shortSide = min(cg.width, cg.height)
            guard shortSide > 0 else { return nil }
            let factor = min(1.0, Double(max(size * 2, 256)) / Double(shortSide))
            let w = max(1, Int((Double(cg.width) * factor).rounded()))
            let h = max(1, Int((Double(cg.height) * factor).rounded()))
            guard let raster = Raster.raster(from: cg, width: w, height: h) else { return nil }
            let label = cd ? CoverLabel.cdRing(raster, size: size) : CoverLabel.circular(raster, size: size)
            return Raster.cgImage(label)
        }.value
    }
}

/// Bildschleife für die Animationen: dt in Sekunden, auf 0,1 s begrenzt (Spec 0, „Bildschleife“).
final class FrameClock {
    private var last: Date?

    func dt(_ now: Date) -> Float {
        defer { last = now }
        guard let last else { return 0 }
        return Float(min(0.1, max(0, now.timeIntervalSince(last))))
    }

    func reset() { last = nil }
}

/// Reduzierte Bewegung (Systemeinstellung „Bewegung reduzieren“).
@MainActor
var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
