import SwiftUI
import AppKit
import MLCore

// Symbole der App: dieselben Vektorpfade wie in der Android-App (Material Symbols Rounded + eigene Zeichnungen),
// siehe IconData.swift (erzeugt mit scripts/gen_icons.py).

enum IconCap { case butt, round, square }
enum IconJoin { case miter, round, bevel }

struct IconPath {
    let d: String
    let fill: Double
    let evenOdd: Bool
    let stroke: Double
    let lineWidth: Double
    let cap: IconCap
    let join: IconJoin
}

struct IconSpec {
    let width: Double
    let height: Double
    var minY: Double = 0
    let paths: [IconPath]
}

/// Bereits in CGPath umgewandelte Symbole (einmal je Name).
final class IconCache: @unchecked Sendable {
    static let shared = IconCache()

    struct Parsed {
        let width: CGFloat
        let height: CGFloat
        let parts: [(path: CGPath, spec: IconPath)]
    }

    private var cache: [String: Parsed] = [:]
    private let lock = NSLock()

    func parsed(_ name: String) -> Parsed? {
        lock.lock()
        defer { lock.unlock() }
        if let p = cache[name] { return p }
        guard let spec = IconData.spec(name) else { return nil }
        let parts = spec.paths.map { p -> (CGPath, IconPath) in
            let path = CGMutablePath()
            for cmd in SVGPath.parse(p.d) {
                switch cmd {
                case let .move(x, y): path.move(to: CGPoint(x: x, y: y - spec.minY))
                case let .line(x, y): path.addLine(to: CGPoint(x: x, y: y - spec.minY))
                case let .quad(cx, cy, x, y):
                    path.addQuadCurve(to: CGPoint(x: x, y: y - spec.minY), control: CGPoint(x: cx, y: cy - spec.minY))
                case let .cubic(c1x, c1y, c2x, c2y, x, y):
                    path.addCurve(to: CGPoint(x: x, y: y - spec.minY), control1: CGPoint(x: c1x, y: c1y - spec.minY), control2: CGPoint(x: c2x, y: c2y - spec.minY))
                case .close: path.closeSubpath()
                }
            }
            return (path, p)
        }
        let result = Parsed(width: CGFloat(spec.width), height: CGFloat(spec.height), parts: parts)
        cache[name] = result
        return result
    }
}

private extension IconCap {
    var cg: CGLineCap {
        switch self {
        case .butt: return .butt
        case .round: return .round
        case .square: return .square
        }
    }
}

private extension IconJoin {
    var cg: CGLineJoin {
        switch self {
        case .miter: return .miter
        case .round: return .round
        case .bevel: return .bevel
        }
    }
}

/// Ein Symbol der App in der angegebenen Größe und Farbe (ohne Farbe: Vordergrundfarbe der Umgebung).
struct Icon: View {
    let name: String
    var size: CGFloat = 20
    var color: Color? = nil

    init(_ name: String, size: CGFloat = 20, color: Color? = nil) {
        self.name = name
        self.size = size
        self.color = color
    }

    var body: some View {
        Canvas { ctx, area in
            guard let icon = IconCache.shared.parsed(name) else { return }
            let s = min(area.width / icon.width, area.height / icon.height)
            let ox = (area.width - icon.width * s) / 2
            let oy = (area.height - icon.height * s) / 2
            let transform = CGAffineTransform(translationX: ox, y: oy).scaledBy(x: s, y: s)
            let shading: GraphicsContext.Shading = color.map { .color($0) } ?? .foreground
            for part in icon.parts {
                let path = Path(part.path).applying(transform)
                if part.spec.fill > 0 {
                    var c = ctx
                    c.opacity = part.spec.fill
                    c.fill(path, with: shading, style: FillStyle(eoFill: part.spec.evenOdd, antialiased: true))
                }
                if part.spec.stroke > 0 && part.spec.lineWidth > 0 {
                    var c = ctx
                    c.opacity = part.spec.stroke
                    c.stroke(path, with: shading, style: StrokeStyle(lineWidth: CGFloat(part.spec.lineWidth) * s, lineCap: part.spec.cap.cg, lineJoin: part.spec.join.cg))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension NSImage {
    /// Symbol als Bild (für Menüs, Dock-Menü, Menüleiste). `template` = passt sich an das Erscheinungsbild an.
    static func icon(_ name: String, size: CGFloat = 16, color: NSColor = .black, template: Bool = true) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let icon = IconCache.shared.parsed(name), let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let s = min(rect.width / icon.width, rect.height / icon.height)
            ctx.translateBy(x: (rect.width - icon.width * s) / 2, y: (rect.height - icon.height * s) / 2)
            ctx.scaleBy(x: s, y: s)
            for part in icon.parts {
                if part.spec.fill > 0 {
                    ctx.addPath(part.path)
                    ctx.setFillColor(color.withAlphaComponent(CGFloat(part.spec.fill)).cgColor)
                    ctx.fillPath(using: part.spec.evenOdd ? .evenOdd : .winding)
                }
                if part.spec.stroke > 0 && part.spec.lineWidth > 0 {
                    ctx.addPath(part.path)
                    ctx.setStrokeColor(color.withAlphaComponent(CGFloat(part.spec.stroke)).cgColor)
                    ctx.setLineWidth(CGFloat(part.spec.lineWidth))
                    ctx.setLineCap(part.spec.cap.cg)
                    ctx.setLineJoin(part.spec.join.cg)
                    ctx.strokePath()
                }
            }
            return true
        }
        image.isTemplate = template
        return image
    }
}

/// Symbolnamen, die in der App verwendet werden (zentral, damit Tippfehler auffallen).
enum Icons {
    static let play = "play"
    static let pause = "pause"
    static let next = "fast_forward"
    static let previous = "fast_rewind"
    static let shuffle = "shuffle"
    static let repeatAll = "repeat"
    static let repeatOne = "repeat_one"
    static let favorite = "favorite"
    static let favoriteBorder = "favorite_border"
    static let search = "search"
    static let clear = "clear"
    static let sort = "sort"
    static let settings = "settings"
    static let back = "arrow_back"
    static let more = "more_vert"
    static let queue = "queue_music"
    static let lyrics = "lyrics"
    static let equalizer = "graphic_eq"
    static let tune = "tune"
    static let pitch = "pitch"
    static let sleep = "bedtime"
    static let sleepFill = "bedtime_fill"
    static let info = "info"
    static let vinyl = "vinyl"
    static let album = "album"
    static let musicNote = "music_note"
    static let volumeDown = "volume_down"
    static let volumeUp = "volume_up"
    static let volumeOff = "volume_off"
    static let add = "add"
    static let playlistAdd = "playlist_add"
    static let playlistPlay = "playlist_play"
    static let playlistRemove = "playlist_remove"
    static let delete = "delete"
    static let edit = "edit"
    static let check = "check"
    static let chevronRight = "chevron_right"
    static let expandMore = "expand_more"
    static let history = "history"
    static let trending = "trending_up"
    static let autoAwesome = "auto_awesome"
    static let refresh = "refresh"
    static let warning = "warning"
    static let dragHandle = "drag_handle"
    static let replay10 = "replay_10"
    static let forward10 = "forward_10"
    static let image = "image"
    static let folder = "folder"
    static let folderOpen = "folder_open"
    static let copy = "content_copy"
    static let paste = "content_paste"
    static let undo = "undo"
    static let close = "close"
    static let miniPlayer = "picture_in_picture_alt"
    static let openFull = "open_in_full"
    static let closeFull = "close_fullscreen"
    static let star = "star"
    static let starFill = "star_fill"
    static let speed = "speed"
    static let timer = "timer"
    static let description = "description"
    static let difference = "difference"
    static let gridView = "grid_view"
    static let list = "list"
    static let selectAll = "select_all"
    static let editNote = "edit_note"
    static let backup = "backup"
    static let restore = "history"
    static let hardDrive = "hard_drive"
    static let usb = "usb"
    static let label = "label"
    static let photoLibrary = "photo_library"
    static let fileExport = "file_export"
    static let checkCircle = "check_circle_fill"
    static let error = "error"
    static let chevronLeft = "chevron_left"
    static let moreHoriz = "more_horiz"
    static let sync = "sync"
    static let libraryMusic = "library_music"
    static let person = "person"
    static let textFields = "text_fields"
    static let sortByAlpha = "sort_by_alpha"
    static let filter = "filter_list"
    static let dragIndicator = "drag_indicator"
    static let timerFill = "timer_fill"
    static let openInNew = "open_in_new"

    // v2
    static let viewGrid = "grid_view"
    static let viewCompact = "view_module"
    static let viewList = "view_list"
    static let viewDetailed = "table_rows"
    static let viewCoverFlow = "view_carousel"
    static let coverSize = "photo_size_select_large"
    static let filterAlt = "filter_alt"
    static let filterOff = "filter_alt_off"
    static let swapVert = "swap_vert"
    static let arrowUp = "arrow_upward"
    static let arrowDown = "arrow_downward"
    static let palette = "palette"
    static let darkMode = "dark_mode"
    static let lightMode = "light_mode"
    static let autoMode = "brightness_auto"
    static let keyboard = "keyboard"
    static let storage = "storage"
    static let privacy = "privacy_tip"
    static let stats = "bar_chart"
    static let schedule = "schedule"
    static let newReleases = "new_releases"
    static let event = "event"
    static let category = "category"
    static let save = "save"
    static let addCircle = "add_circle"
    static let remove = "remove"
    static let waves = "waves"
    static let blur = "blur_on"
    static let animation = "animation"
    static let cleaning = "cleaning_services"
    static let restart = "restart_alt"
    static let headphones = "headphones"
    static let speaker = "speaker"
    static let volumeMute = "volume_mute"
    static let leaderboard = "leaderboard"
    static let visibility = "visibility"
    static let expandLess = "expand_less"
    static let unfoldMore = "unfold_more"
    static let radio = "radio"
    static let equalizerBars = "equalizer"
    static let instantMix = "instant_mix"
    static let dashboard = "dashboard_customize"
    static let style = "style"
    static let motion = "motion_photos_on"
    static let timerOff = "timer_off"
    static let playlistCheck = "playlist_add_check"
    static let pin = "push_pin"
    static let fullscreen = "fullscreen"
    static let fullscreenExit = "fullscreen_exit"
    static let tag = "tag"
    static let manageSearch = "manage_search"
    static let pageInfo = "page_info"
    static let linearScale = "linear_scale"
    static let skipNext = "skip_next"
    static let skipPrevious = "skip_previous"
    static let insights = "insights"
    static let database = "database"
    static let shield = "shield"
    static let musicOff = "music_off"
    static let calendar = "calendar_month"
    static let bookmarkAdd = "bookmark_add"
    static let openWith = "open_with"
    static let north = "north"
    static let south = "south"
}
