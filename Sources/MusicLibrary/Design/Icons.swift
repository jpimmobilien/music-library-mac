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
        guard let spec = IconData.spec(name) ?? HandDrawnIcons.spec(name) else { return nil }
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

    // v2.2 Audio Studio (eigene Zeichnungen, siehe `HandDrawnIcons`)
    static let studio = "studio"
    static let studioFill = "studio_fill"
    static let waveform = "waveform"
    static let download = "download"
    static let cut = "content_cut"
    static let link = "link"
    static let audioFile = "audio_file"
    static let newFile = "note_add"
    static let lock = "lock"
    static let fadeIn = "fade_in"
    static let fadeOut = "fade_out"
    static let fitWidth = "fit_width"
    static let globe = "public"
    static let wrench = "build"
    static let live = "live"
    static let swap = "swap_horiz"
    static let previewSelection = "preview_selection"
}

/// Eigene Symbole des Audio Studios (Version 2.2), von Hand im Stil von Material Symbols Rounded gezeichnet
/// (24-pt-Raster, Strichstärke 2, runde Enden – wie die Genre-Symbole). Bewusst nicht in `IconData.swift`,
/// das von `scripts/gen_icons.py` erzeugt und dabei überschrieben wird.
enum HandDrawnIcons {
    private static func stroke(_ d: String, _ width: Double = 2) -> IconPath {
        IconPath(d: d, fill: 0, evenOdd: false, stroke: 1, lineWidth: width, cap: .round, join: .round)
    }

    private static func fill(_ d: String, _ alpha: Double = 1) -> IconPath {
        IconPath(d: d, fill: alpha, evenOdd: false, stroke: 0, lineWidth: 0, cap: .butt, join: .miter)
    }

    private static func icon(_ paths: [IconPath]) -> IconSpec { IconSpec(width: 24, height: 24, paths: paths) }

    /// Dokument mit Eselsohr (gemeinsam für Datei-Symbole).
    private static let document = [
        stroke("M13.5,3.5H7.2A2.2,2.2 0 0 0 5,5.7v12.6a2.2,2.2 0 0 0 2.2,2.2h9.6a2.2,2.2 0 0 0 2.2,-2.2V9Z", 1.8),
        stroke("M13.5,3.5V7.2a1.8,1.8 0 0 0 1.8,1.8H19", 1.8),
    ]

    /// Klammern links und rechts (Auswahl in der Wellenform).
    private static let brackets = [
        stroke("M6.2,4.5H4.5v15h1.7"),
        stroke("M17.8,4.5h1.7v15h-1.7"),
    ]

    static func spec(_ name: String) -> IconSpec? {
        switch name {
        case "studio":
            return icon(brackets + [stroke("M9,9.5v5"), stroke("M12,6.5v11"), stroke("M15,9v6")])
        case "studio_fill":
            return icon([fill("M4.5,4.5h15v15h-15z", 0.24)] + brackets + [stroke("M9,9.5v5", 2.2), stroke("M12,6.5v11", 2.2), stroke("M15,9v6", 2.2)])
        case "waveform":
            return icon([stroke("M3.5,10.5v3"), stroke("M6.3,8.5v7"), stroke("M9.2,5.5v13"), stroke("M12,3.5v17"),
                         stroke("M14.8,6.5v11"), stroke("M17.7,9v6"), stroke("M20.5,10.5v3")])
        case "download":
            return icon([stroke("M12,4.5v10"), stroke("M7.5,10.5L12,15l4.5,-4.5"), stroke("M5.5,19.5h13")])
        case "content_cut":
            return icon([stroke("M6.5,14.5a3,3 0 1 0 0,6a3,3 0 1 0 0,-6z"), stroke("M17.5,14.5a3,3 0 1 0 0,6a3,3 0 1 0 0,-6z"),
                         stroke("M8.6,15.4L17.5,4"), stroke("M15.4,15.4L6.5,4")])
        case "link":
            return icon([stroke("M10.5,7.5H8a4.5,4.5 0 0 0 0,9h2.5"), stroke("M13.5,7.5H16a4.5,4.5 0 0 1 0,9h-2.5"), stroke("M8.5,12h7")])
        case "audio_file":
            return icon(document + [fill("M10.3,14.6a1.8,1.8 0 1 0 0,3.6a1.8,1.8 0 1 0 0,-3.6z"), stroke("M12,16.4V11.6l2.6,0.9", 1.6)])
        case "note_add":
            return icon(document + [stroke("M12,11.5v6", 1.8), stroke("M9,14.5h6", 1.8)])
        case "lock":
            return icon([stroke("M7.2,10.5h9.6a1.7,1.7 0 0 1 1.7,1.7v6.1a1.7,1.7 0 0 1 -1.7,1.7H7.2a1.7,1.7 0 0 1 -1.7,-1.7v-6.1A1.7,1.7 0 0 1 7.2,10.5z"),
                         stroke("M8.5,10.5V8a3.5,3.5 0 0 1 7,0v2.5"), stroke("M12,14.4v1.8")])
        case "fade_in":
            return icon([fill("M4.5,18.5L19.5,5.5V18.5Z", 0.22), stroke("M4.5,18.5L19.5,5.5V18.5Z", 1.8)])
        case "fade_out":
            return icon([fill("M4.5,5.5L19.5,18.5H4.5Z", 0.22), stroke("M4.5,5.5L19.5,18.5H4.5Z", 1.8)])
        case "fit_width":
            return icon([stroke("M4,5v14"), stroke("M20,5v14"), stroke("M8,12h8"), stroke("M10.5,9L7.5,12l3,3"), stroke("M13.5,9l3,3l-3,3")])
        case "public":
            return icon([stroke("M12,3.5a8.5,8.5 0 1 0 0,17a8.5,8.5 0 1 0 0,-17z", 1.8),
                         stroke("M12,3.5c-2.2,2.3 -3.4,5.2 -3.4,8.5s1.2,6.2 3.4,8.5", 1.8),
                         stroke("M12,3.5c2.2,2.3 3.4,5.2 3.4,8.5s-1.2,6.2 -3.4,8.5", 1.8),
                         stroke("M4,9.3h16", 1.8), stroke("M4,14.7h16", 1.8)])
        case "build":
            return icon([stroke("M14.6,4.1a4.6,4.6 0 0 0 -4.9,6.2L4.7,15.3a2.1,2.1 0 0 0 3,3l5,-5a4.6,4.6 0 0 0 6.2,-4.9l-2.8,2.8l-2.6,-0.6l-0.6,-2.6z", 1.8)])
        case "live":
            return icon([fill("M12,10a2,2 0 1 0 0,4a2,2 0 1 0 0,-4z"),
                         stroke("M8.4,8.4a5.1,5.1 0 0 0 0,7.2"), stroke("M15.6,8.4a5.1,5.1 0 0 1 0,7.2"),
                         stroke("M5.6,5.6a9,9 0 0 0 0,12.8"), stroke("M18.4,5.6a9,9 0 0 1 0,12.8")])
        case "swap_horiz":
            return icon([stroke("M4.5,8.5h14"), stroke("M15.5,5.5l3,3l-3,3"), stroke("M19.5,15.5h-14"), stroke("M8.5,12.5l-3,3l3,3")])
        case "preview_selection":
            return icon(brackets + [fill("M10,8.6v6.8a0.8,0.8 0 0 0 1.2,0.7l5.2,-3.4a0.8,0.8 0 0 0 0,-1.4L11.2,7.9A0.8,0.8 0 0 0 10,8.6z")])
        default:
            return nil
        }
    }
}
