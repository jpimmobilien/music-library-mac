import SwiftUI
import AppKit
import MLCore
import MLStore
import MLTags

/// Vorschaubilder aller wichtigen Ansichten in Hell/Dunkel und verschiedenen Fenstergrößen.
///
/// Aufruf: `"Music Library.app/Contents/MacOS/MusicLibrary" --snapshot <Ordner>` – nutzt die erfundene
/// Beispielbibliothek (`DemoLibrary`), spielt keinen Ton ab und berührt keine Benutzerdaten.
/// Die CI-Pipeline erzeugt damit Bilder zur Sichtprüfung der Gestaltung.
enum SnapshotRunner {
    static var isRequested: Bool { CommandLine.arguments.contains("--snapshot") }

    static var outputDirectory: URL {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            return URL(fileURLWithPath: args[i + 1], isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("snapshots", isDirectory: true)
    }

    @MainActor
    static func makeDemoModel() -> AppModel {
        let store = try! LibraryStore.inMemory()
        let model = AppModel(store: store, demo: true)
        let demo = DemoLibrary.make()
        ArtworkStore.shared.setOverrides(demo.covers)
        model.setDemoData(tracks: demo.tracks, favorites: demo.favorites, favoriteAlbums: demo.favoriteAlbums, stats: demo.stats, playlists: demo.playlists, history: demo.history)
        EditorSession.demoResult = { t in
            var v = TagValues()
            v.title = t.title
            v.artists = t.artists
            v.album = t.album
            v.albumArtists = t.albumArtists
            v.genres = t.genres
            v.composers = t.composers
            v.year = t.year
            v.trackNumber = t.trackNumber
            v.trackTotal = t.trackTotal
            v.discNumber = t.discNumber
            v.discTotal = t.discTotal
            v.compilation = t.compilation
            v.bpm = t.bpm
            v.rating = t.rating
            v.comment = t.uid == 1 ? "Aufgenommen im Studio am Hafen." : nil
            v.lyrics = t.uid == 1 ? DemoLibrary.lyrics : nil
            if let path = demo.covers[t.uid], let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                v.pictures = [EmbeddedPicture(kind: .frontCover, mimeType: "image/png", data: data)]
                if t.uid == 1 {
                    v.pictures.append(EmbeddedPicture(kind: .backCover, mimeType: "image/png", data: data))
                }
            }
            let audio = AudioProperties(durationMs: t.durationMs, bitrate: t.bitrate, sampleRate: t.sampleRate, channels: t.channels, bitsPerSample: t.bitsPerSample, codec: t.codec ?? "AAC")
            return TagReadResult(values: v, audio: audio, fileFormat: "MPEG-4 Audio", tagFormat: "MP4 (iTunes)", supportsPictures: true, writable: true)
        }
        LyricsSource.demo = [1: DemoLibrary.lyrics]
        return model
    }

    struct Scenario {
        let name: String
        let size: CGSize
        let prepare: @MainActor (AppModel) -> Void
        let view: @MainActor () -> AnyView
    }

    @MainActor
    static func run(model: AppModel) {
        Task { @MainActor in
            await runAll(model)
            NSApp.terminate(nil)
        }
    }

    @MainActor
    private static func scenarios(_ model: AppModel) -> [Scenario] {
        let firstAlbum = model.index.albums.first?.key ?? ""
        let firstArtist = model.index.artistByKey.keys.sorted().first ?? ""
        let firstGenre = model.index.genres.first?.key ?? ""
        let main = { AnyView(MainWindow()) }
        func library(_ section: LibrarySection, _ destination: Destination? = nil, panel: SidePanel? = nil, player open: Bool = false, theme: PlayerTheme = .vinylStudio) -> @MainActor (AppModel) -> Void {
            return { m in
                m.playerOpen = false
                m.section = section
                m.stacks = destination.map { [section: [$0]] } ?? [:]
                m.sidePanel = panel
                m.settings.playerTheme = theme
                m.settings.visualizer = false
                m.player.setDemoState(queueUids: Array(1...12), currentIndex: 0, positionMs: 74_000, playing: true)
                m.playerOpen = open
            }
        }
        let big = CGSize(width: 1280, height: 820)
        let small = CGSize(width: 940, height: 660)
        let wide = CGSize(width: 1520, height: 940)
        var list: [Scenario] = [
            Scenario(name: "01-bibliothek", size: wide, prepare: library(.tracks, panel: .queue), view: main),
            Scenario(name: "02-titel", size: big, prepare: library(.tracks), view: main),
            Scenario(name: "02-titel-klein", size: small, prepare: library(.tracks), view: main),
            Scenario(name: "03-alben", size: big, prepare: library(.albums), view: main),
            Scenario(name: "03-album-detail", size: big, prepare: library(.albums, .album(firstAlbum)), view: main),
            Scenario(name: "03-album-detail-klein", size: small, prepare: library(.albums, .album(firstAlbum)), view: main),
            Scenario(name: "04-interpreten", size: big, prepare: library(.artists), view: main),
            Scenario(name: "04-interpret-detail", size: big, prepare: library(.artists, .artist(firstArtist)), view: main),
            Scenario(name: "05-genres", size: big, prepare: library(.genres), view: main),
            Scenario(name: "05-genre-detail", size: big, prepare: library(.genres, .genre(firstGenre)), view: main),
            Scenario(name: "06-playlists", size: big, prepare: library(.playlists), view: main),
            Scenario(name: "06-playlist-detail", size: big, prepare: library(.playlists, .playlist(1)), view: main),
            Scenario(name: "06-verlauf", size: big, prepare: library(.playlists, .history), view: main),
            Scenario(name: "07-favoriten", size: big, prepare: library(.favorites), view: main),
            Scenario(name: "07-duplikate", size: big, prepare: library(.tracks, .duplicates), view: main),
            Scenario(name: "08-mini-player", size: CGSize(width: 320, height: 150), prepare: library(.tracks), view: { AnyView(MiniPlayerWindow()) }),
            Scenario(name: "09-vollbild-classic", size: big, prepare: library(.tracks, player: true, theme: .classic), view: main),
            Scenario(name: "10-vinyl", size: big, prepare: library(.tracks, player: true, theme: .vinylStudio), view: main),
            Scenario(name: "10-vinyl-klein", size: small, prepare: library(.tracks, player: true, theme: .vinylStudio), view: main),
            Scenario(name: "11-cd", size: big, prepare: library(.tracks, player: true, theme: .portableCD), view: main),
            Scenario(name: "12-kassette", size: big, prepare: library(.tracks, player: true, theme: .cassette), view: main),
            Scenario(name: "13-equalizer", size: CGSize(width: 640, height: 720), prepare: { m in
                m.settings.effects = AudioEffectsSettings().withPreset(EqPresets.rock).withBass(3)
            }, view: { AnyView(EqualizerWindow()) }),
            Scenario(name: "14-metadaten", size: CGSize(width: 780, height: 780), prepare: { m in m.editorUids = [1]; m.metadata.requestedTab = .details }, view: { AnyView(EditorView(uids: [1])) }),
            Scenario(name: "14-metadaten-mehrfach", size: CGSize(width: 780, height: 780), prepare: { m in m.metadata.requestedTab = .details }, view: { AnyView(EditorView(uids: [1, 2, 3, 4])) }),
            Scenario(name: "15-cover", size: CGSize(width: 780, height: 780), prepare: { m in m.metadata.requestedTab = .cover }, view: { AnyView(EditorView(uids: [1])) }),
            Scenario(name: "16-liedtext", size: big, prepare: library(.tracks, panel: .lyrics), view: main),
            Scenario(name: "16-liedtext-bearbeiten", size: CGSize(width: 780, height: 780), prepare: { m in m.metadata.requestedTab = .lyrics }, view: { AnyView(EditorView(uids: [1])) }),
            Scenario(name: "17-einstellungen", size: CGSize(width: 680, height: 640), prepare: { _ in }, view: { AnyView(SettingsView()) }),
        ]
        list.append(Scenario(name: "13-player-equalizer-blatt", size: CGSize(width: 640, height: 720), prepare: { _ in }, view: {
            AnyView(PlayerSheetHost(sheet: .equalizer, theme: .vinylStudio, artwork: NowPlayingArtwork()))
        }))
        return list
    }

    @MainActor
    private static func runAll(_ model: AppModel) async {
        let out = outputDirectory
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var manifest: [[String: String]] = []
        // Hauptfenster der Szene ausblenden; App aktivieren, damit Bedienelemente im aktiven Zustand erscheinen
        for w in NSApp.windows { w.orderOut(nil) }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for scenario in scenarios(model) {
            for dark in [false, true] {
                model.settings.themeMode = dark ? .dark : .light
                scenario.prepare(model)
                let window = SnapshotWindow(contentRect: NSRect(origin: .zero, size: scenario.size),
                                      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                      backing: .buffered, defer: false)
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.isReleasedWhenClosed = false
                let root = ThemedRoot(model: model) { scenario.view() }
                    .frame(width: scenario.size.width, height: scenario.size.height)
                let host = NSHostingView(rootView: root)
                // Fenstergröße nicht vom Inhalt verändern lassen (sonst schwankende Bildgrößen)
                host.sizingOptions = []
                window.contentView = host
                window.setContentSize(scenario.size)
                if let screen = NSScreen.main {
                    let v = screen.visibleFrame
                    window.setFrameTopLeftPoint(NSPoint(x: v.minX + 20, y: v.maxY - 20))
                }
                window.makeKeyAndOrderFront(nil)
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                if window.contentRect(forFrameRect: window.frame).size != scenario.size {
                    window.setContentSize(scenario.size)
                    try? await Task.sleep(nanoseconds: 600_000_000)
                }
                let file = out.appendingPathComponent("\(scenario.name)-\(dark ? "dunkel" : "hell")-\(Int(scenario.size.width))x\(Int(scenario.size.height)).png")
                let method = capture(window, to: file)
                manifest.append(["file": file.lastPathComponent, "method": method, "glass": LiquidGlass.isAvailable ? "liquid-glass" : "fallback"])
                window.orderOut(nil)
                window.contentView = nil
                window.close()
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        let info: [String: Any] = [
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "architecture": AboutArchitecture.current,
            "liquidGlass": LiquidGlass.isAvailable,
            "interFont": Typo.interAvailable,
            "screen": NSScreen.main.map { "\(Int($0.frame.width))x\(Int($0.frame.height)) @\($0.backingScaleFactor)x, sichtbar \(Int($0.visibleFrame.width))x\(Int($0.visibleFrame.height))" } ?? "?",
            "images": manifest,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: out.appendingPathComponent("manifest.json"))
        }
    }

    /// Fensterbild: bevorzugt der echte Bildschirminhalt (mit Unschärfe und Liquid Glass), sonst die Ansicht selbst.
    @MainActor
    private static func capture(_ window: NSWindow, to url: URL) -> String {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
            let fn = unsafeBitCast(sym, to: CreateImage.self)
            // kCGWindowListOptionIncludingWindow = 1 << 3, kCGWindowImageBoundsIgnoreFraming = 1 << 0, kCGWindowImageBestResolution = 1 << 3
            if let img = fn(.null, 1 << 3, UInt32(window.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue(), img.width > 10 {
                if write(img, to: url) { return "window-server" }
            }
        }
        if let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: url)
                return "cache-display"
            }
        }
        return "failed"
    }

    private static func write(_ image: CGImage, to url: URL) -> Bool {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url)) != nil
    }
}

enum AboutArchitecture {
    static var current: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
}

/// Fenster für Vorschaubilder: wird nicht an den Bildschirm angepasst (feste, vergleichbare Größen).
private final class SnapshotWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
