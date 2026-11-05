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
        case .vinylStudio, .portableCD, .modernGlass, .aurora: return app
        case .classic: return classic
        case .cassette, .reelToReel: return cassette
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
    /// Größe des geladenen Covers (Mini-Player: `.medium`, Vollbild: `.large`).
    private let size: ArtworkSize

    init(size: ArtworkSize = .large) {
        self.size = size
    }

    func update(for track: Track?) async {
        guard let track else {
            image = nil
            key = nil
            loading = false
            return
        }
        guard key != track.coverKey else { return }
        key = track.coverKey
        image = ArtworkStore.shared.cached(track, size) ?? (size != .large ? ArtworkStore.shared.cached(track, .large) : nil)
        loading = image == nil && track.hasPicture
        if image == nil {
            let img = await ArtworkStore.shared.image(for: track, size: size)
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

// MARK: - v2: Designs, Bewegung, Farben

/// Symbolnamen, die der Player zusätzlich nutzt (Namen aus IconData). Eigene Konstanten, damit es keine
/// Überschneidung mit Ergänzungen in Design/Icons.swift gibt.
enum PlayerIcons {
    static let palette = "palette"
    static let speaker = "speaker"
    static let volumeUp = "volume_up"
    static let waves = "waves"
    static let equalizerBars = "equalizer"
    static let instantMix = "instant_mix"
    static let save = "save"
    static let addCircle = "add_circle"
    static let remove = "remove"
    static let restart = "restart_alt"
    static let unfoldMore = "unfold_more"
    static let expandLess = "expand_less"
    static let fullscreen = "fullscreen"
    static let visibility = "visibility"
    static let blur = "blur_on"
    static let radio = "radio"
    static let linearScale = "linear_scale"
    static let lyricsFill = "lyrics_fill"
    static let queueFill = "queue_music_fill"
    static let arrowUp = "arrow_upward"
    static let arrowDown = "arrow_downward"
    static let keep = "keep"
    static let keepOff = "keep_off"
    static let image = "image"
    static let person = "person"
}

extension PlayerTheme {
    /// Immer dunkle Designs: Glas, Popover und Systemelemente werden ebenfalls dunkel dargestellt.
    var uiAlwaysDark: Bool {
        switch self {
        case .classic, .cassette, .reelToReel: return true
        case .vinylStudio, .portableCD, .modernGlass, .aurora: return false
        }
    }

    /// Symbol in Menüs.
    var uiIcon: String {
        switch self {
        case .vinylStudio: return Icons.vinyl
        case .classic: return PlayerIcons.image
        case .cassette: return PlayerIcons.radio
        case .portableCD: return Icons.album
        case .modernGlass: return PlayerIcons.blur
        case .aurora: return Icons.autoAwesome
        case .reelToReel: return PlayerIcons.linearScale
        }
    }

    /// Seitenverhältnis (Breite/Höhe) des kleinen Mittelstücks im Mini-Player.
    var uiMiniAspect: CGFloat {
        switch self {
        case .cassette, .reelToReel: return 1.45
        case .vinylStudio, .classic, .portableCD, .modernGlass, .aurora: return 1
        }
    }

    /// Klangvisualisierung als Balken unter dem Mittelstück? (Aurora, Kassette und Tonband zeigen eigene Pegel.)
    var uiShowsSpectrumBars: Bool {
        switch self {
        case .vinylStudio, .classic, .portableCD, .modernGlass: return true
        case .cassette, .aurora, .reelToReel: return false
        }
    }
}

/// Bewegungsregeln (Einstellung „Animationen“ und Systemeinstellung „Bewegung reduzieren“).
@MainActor
enum PlayerMotionPolicy {
    /// Dauerhafte Bewegung erlaubt (drehende Platten, Wickel, Lichtring, Pegel)?
    static func continuous(_ s: AppSettings) -> Bool {
        s.animationLevel == .full && !reduceMotion
    }

    /// Übergang beim Wechsel des Designs bzw. des Covers.
    static func transition(_ s: AppSettings) -> Animation? {
        switch s.animationLevel {
        case .off: return nil
        case .reduced: return .easeInOut(duration: 0.3)
        case .full: return reduceMotion ? .easeInOut(duration: 0.3) : .timingCurve(0.32, 0.72, 0, 1, duration: 0.62)
        }
    }

    /// Übergang zwischen zwei Designs: Einblenden mit leichtem Heranzoomen, Ausblenden mit leichtem Wegzoomen.
    static func themeTransition(_ s: AppSettings) -> AnyTransition {
        if s.animationLevel != .full || reduceMotion { return .opacity }
        return .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.9)),
                           removal: .opacity.combined(with: .scale(scale: 1.06)))
    }
}

/// Farben aus der Cover-Palette (Lichtfelder, Aurora, Kassettenfarbe „Cover“).
enum PaletteTone {
    /// Farbe mit verschobenem Farbton (0…1 = volle Drehung), Mindestsättigung und optional fester Helligkeit.
    static func color(_ argb: UInt32, hueShift: Double = 0, minSaturation: Double = 0, brightness: Double? = nil, opacity: Double = 1) -> Color {
        let base = NSColor(argb: argb)
        let ns = base.usingColorSpace(.sRGB) ?? base
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        var hue = Double(h) + hueShift
        hue -= floor(hue)
        let sat: Double = min(1, max(Double(s), minSaturation))
        let bri: Double = min(1, max(0, brightness ?? Double(b)))
        return Color(hue: hue, saturation: sat, brightness: bri, opacity: opacity)
    }
}

/// Vier Lichtfarben eines Covers für Aurora, Lichtfelder und den Mini-Player.
struct AuroraColors: Equatable {
    let primary: Color
    let secondary: Color
    let tertiary: Color
    let highlight: Color

    init(palette: CoverPalette, dark: Bool) {
        let bri: Double = dark ? 0.92 : 0.78
        primary = PaletteTone.color(palette.glow, minSaturation: 0.5, brightness: bri)
        secondary = PaletteTone.color(palette.glow, hueShift: 0.09, minSaturation: 0.55, brightness: bri)
        tertiary = PaletteTone.color(palette.glow, hueShift: -0.32, minSaturation: 0.45, brightness: dark ? 0.85 : 0.72)
        highlight = PaletteTone.color(palette.top, hueShift: -0.06, minSaturation: 0.35, brightness: dark ? 0.98 : 0.9)
    }
}

/// Gehäusefarbe der Kassette.
enum CassetteShell {
    /// Tönung über dem Originalgehäuse; `nil` = Original „Rauch“ des Renderers (unverändert).
    static func tint(_ color: CassetteColor, palette: CoverPalette) -> Color? {
        if color == .smoke { return nil }
        if let v = color.argb { return Color(argb: v | 0xFF000000) }
        // „Cover“: Leuchtfarbe des Covers, in Sättigung und Helligkeit für Kunststoff angepasst
        return PaletteTone.color(palette.glow, minSaturation: 0.35, brightness: 0.62)
    }

    /// Farbe für kleine Darstellungen (Mini-Player, Farbauswahl) – auch für „Rauch“.
    static func swatch(_ color: CassetteColor, palette: CoverPalette) -> Color {
        tint(color, palette: palette) ?? Color(argb: 0xFF4A4144)
    }
}

/// Symbol „n Sekunden zurück/vor“: für 10 s das Material-Symbol, sonst ein Kreispfeil mit Zahl.
struct SkipGlyph: View {
    let seconds: Int
    let forward: Bool
    var size: CGFloat = 24
    var color: Color

    var body: some View {
        if seconds == 10 {
            Icon(forward ? Icons.forward10 : Icons.replay10, size: size, color: color)
        } else {
            ZStack {
                SkipArrow()
                    .stroke(color, style: StrokeStyle(lineWidth: max(1.3, size * 0.08), lineCap: .round, lineJoin: .round))
                    .scaleEffect(x: forward ? -1 : 1, y: 1)
                Text(verbatim: String(seconds))
                    .font(Typo.inter(max(7, size * 0.31), .bold))
                    .foregroundColor(color)
                    .offset(y: size * 0.045)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }
    }
}

/// Kreispfeil im Uhrzeigersinn mit Pfeilspitze oben (nach links zeigend).
struct SkipArrow: Shape {
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = min(rect.width, rect.height) * 0.37
        let cx: CGFloat = rect.midX
        let cy: CGFloat = rect.midY + rect.height * 0.045
        var p = Path()
        var first = true
        var deg: Double = -90
        while deg <= 205 {
            let a = deg * Double.pi / 180
            let pt = CGPoint(x: cx + r * CGFloat(cos(a)), y: cy + r * CGFloat(sin(a)))
            if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
            deg += 7.5
        }
        let tip = CGPoint(x: cx - r * 0.06, y: cy - r)
        p.move(to: CGPoint(x: tip.x + r * 0.42, y: tip.y - r * 0.38))
        p.addLine(to: tip)
        p.addLine(to: CGPoint(x: tip.x + r * 0.42, y: tip.y + r * 0.38))
        return p
    }
}

/// Beschriftung der Sprungtasten („10 Sekunden zurück“).
enum SkipText {
    static func label(_ seconds: Int, forward: Bool) -> String {
        "\(seconds) Sekunden \(forward ? "vor" : "zurück")"
    }
}

/// Restzeit des Sleep-Timers – liest nur `clock` (hochfrequent, deshalb eigene kleine Ansicht).
struct SleepCountdownText: View {
    @ObservedObject var clock: PlaybackClock

    var body: some View {
        Text(Formatting.countdown(clock.sleepRemainingMs ?? 0))
    }
}

/// Kurzform von Halbtönen für Chips und Werkzeugleisten („+1,5“, „−0,3“, „±0“).
enum PitchText {
    static func short(_ v: Float) -> String {
        let r = (v * 10).rounded() / 10
        if r == 0 { return "±0" }
        let sign = r > 0 ? "+" : "−"
        let a = abs(r)
        let num: String = a == a.rounded() ? String(Int(a)) : String(format: "%.1f", Double(a)).replacingOccurrences(of: ".", with: ",")
        return sign + num
    }

    /// Kurzform für Dezibel („+3“, „−1,5“).
    static func shortDb(_ v: Float) -> String { short(v) }
}

/// Schatten nur außerhalb einer Form – für schwebende Glasflächen, deren Inhalt sich bewegt
/// (der Schatten wird so nicht bei jedem Bild neu berechnet).
struct OuterShadow: View {
    let cornerRadius: CGFloat
    var color: Color
    var radius: CGFloat = 18
    var y: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.black)
            .shadow(color: color, radius: radius, x: 0, y: y)
            .mask(OutsideMask(cornerRadius: cornerRadius, outset: radius * 2 + abs(y)).fill(style: FillStyle(eoFill: true)))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Großes Rechteck minus abgerundetes Rechteck (für `OuterShadow`).
struct OutsideMask: Shape {
    let cornerRadius: CGFloat
    let outset: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path(rect.insetBy(dx: -outset, dy: -outset))
        // Loch 1 pt größer als die Form: die Kante der gefüllten Form bleibt sicher verdeckt
        p.addRoundedRect(in: rect.insetBy(dx: -1, dy: -1), cornerSize: CGSize(width: cornerRadius + 1, height: cornerRadius + 1), style: .continuous)
        return p
    }
}
