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
        // ohne App Nap (Zeitgeber werden sonst gebündelt, die gemessene Hauptthread-Verzögerung wäre verfälscht)
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Vorschaubilder")
        Task { @MainActor in
            await runAll(model)
            NSApp.terminate(nil)
        }
    }

    private static var activity: NSObjectProtocol?

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
            Scenario(name: "17-einstellungen", size: CGSize(width: 860, height: 680), prepare: { _ in WindowRouter.shared.pendingSettingsCategory = SettingsCategory.general.rawValue }, view: { AnyView(SettingsView()) }),
        ]
        list.append(Scenario(name: "13-player-equalizer-blatt", size: CGSize(width: 640, height: 720), prepare: { _ in }, view: {
            AnyView(PlayerSheetHost(sheet: .equalizer, theme: .vinylStudio, artwork: NowPlayingArtwork()))
        }))
        list += v2Scenarios(library: library, main: main, big: big, small: small)
        return list
    }

    /// Version 2: Ansichtsarten je Bereich, Filter, neue Player-Designs, Kassettenfarben, Mini-Player-Größen,
    /// Einstellungskategorien.
    @MainActor
    private static func v2Scenarios(library: @escaping @MainActor (LibrarySection, Destination?, SidePanel?, Bool, PlayerTheme) -> @MainActor (AppModel) -> Void,
                                    main: @escaping @MainActor () -> AnyView, big: CGSize, small: CGSize) -> [Scenario] {
        /// Bereich mit einer bestimmten Ansichtsart (alle anderen Bereiche auf Standard).
        func view(_ section: LibrarySection, _ context: LibraryViewContext, _ mode: LibraryViewMode,
                  favoritesTab: FavoritesTab? = nil, filter: LibraryFilter? = nil) -> @MainActor (AppModel) -> Void {
            return { m in
                library(section, nil, nil, false, .vinylStudio)(m)
                for c in LibraryViewContext.allCases { m.setViewOptions(.defaults(for: c), for: c) }
                var o = LibraryViewOptions.defaults(for: context)
                o.mode = mode
                m.setViewOptions(o, for: context)
                if let tab = favoritesTab { m.settings.favoritesTab = tab }
                for c in LibraryViewContext.allCases { m.setFilter(LibraryFilter(), for: c) }
                if let f = filter { m.setFilter(f, for: context) }
            }
        }
        func player(_ theme: PlayerTheme, cassette: CassetteColor = .smoke) -> @MainActor (AppModel) -> Void {
            return { m in
                for c in LibraryViewContext.allCases { m.setViewOptions(.defaults(for: c), for: c) }
                m.settings.cassetteColor = cassette
                library(.tracks, nil, nil, true, theme)(m)
            }
        }
        func mini(_ size: MiniPlayerSize) -> @MainActor (AppModel) -> Void {
            return { m in
                for c in LibraryViewContext.allCases { m.setViewOptions(.defaults(for: c), for: c) }
                m.settings.miniPlayerSize = size
                library(.albums, nil, nil, false, .vinylStudio)(m)
            }
        }
        func settings(_ category: SettingsCategory) -> @MainActor (AppModel) -> Void {
            return { m in
                m.settings.miniPlayerSize = .standard
                WindowRouter.shared.pendingSettingsCategory = category.rawValue
            }
        }
        var genreFilter = LibraryFilter()
        genreFilter.decades = [2010, 2020]
        let settingsSize = CGSize(width: 860, height: 680)
        var list: [Scenario] = [
            Scenario(name: "20-titel-raster", size: big, prepare: view(.tracks, .tracks, .grid), view: main),
            Scenario(name: "20-titel-detailliste", size: big, prepare: view(.tracks, .tracks, .detailedList), view: main),
            Scenario(name: "20-titel-coverflow", size: big, prepare: view(.tracks, .tracks, .coverFlow), view: main),
            Scenario(name: "21-alben-kompakt", size: big, prepare: view(.albums, .albums, .compactGrid), view: main),
            Scenario(name: "21-alben-liste", size: big, prepare: view(.albums, .albums, .list), view: main),
            Scenario(name: "21-alben-detailliste", size: big, prepare: view(.albums, .albums, .detailedList), view: main),
            Scenario(name: "21-alben-coverflow", size: big, prepare: view(.albums, .albums, .coverFlow), view: main),
            Scenario(name: "21-alben-coverflow-klein", size: small, prepare: view(.albums, .albums, .coverFlow), view: main),
            Scenario(name: "21-alben-gefiltert", size: big, prepare: view(.albums, .albums, .grid, filter: genreFilter), view: main),
            Scenario(name: "22-interpreten-liste", size: big, prepare: view(.artists, .artists, .list), view: main),
        ]
        list += [
            Scenario(name: "22-interpreten-coverflow", size: big, prepare: view(.artists, .artists, .coverFlow), view: main),
            Scenario(name: "23-genres-detailliste", size: big, prepare: view(.genres, .genres, .detailedList), view: main),
            Scenario(name: "24-playlists-liste", size: big, prepare: view(.playlists, .playlists, .list), view: main),
            Scenario(name: "25-favoriten-alben-raster", size: big, prepare: view(.favorites, .favoriteAlbums, .grid, favoritesTab: .albums), view: main),
            Scenario(name: "25-favoriten-titel-detailliste", size: big, prepare: view(.favorites, .favoriteTracks, .detailedList, favoritesTab: .tracks), view: main),
            Scenario(name: "30-modern-glass", size: big, prepare: player(.modernGlass), view: main),
            Scenario(name: "30-modern-glass-klein", size: small, prepare: player(.modernGlass), view: main),
            Scenario(name: "31-aurora", size: big, prepare: player(.aurora), view: main),
            Scenario(name: "32-studio-reel", size: big, prepare: player(.reelToReel), view: main),
            Scenario(name: "33-kassette-rose", size: big, prepare: player(.cassette, cassette: .rose), view: main),
        ]
        list += [
            Scenario(name: "33-kassette-ozean", size: big, prepare: player(.cassette, cassette: .ocean), view: main),
            Scenario(name: "34-mini-kompakt", size: big, prepare: mini(.compact), view: main),
            Scenario(name: "34-mini-gross", size: big, prepare: mini(.large), view: main),
            Scenario(name: "40-einstellungen-darstellung", size: settingsSize, prepare: settings(.appearance), view: { AnyView(SettingsView()) }),
            Scenario(name: "40-einstellungen-player", size: settingsSize, prepare: settings(.playerDesigns), view: { AnyView(SettingsView()) }),
            Scenario(name: "40-einstellungen-equalizer", size: settingsSize, prepare: settings(.equalizer), view: { AnyView(SettingsView()) }),
            Scenario(name: "40-einstellungen-tonhoehe", size: settingsSize, prepare: settings(.pitch), view: { AnyView(SettingsView()) }),
            Scenario(name: "40-einstellungen-speicher", size: settingsSize, prepare: settings(.storage), view: { AnyView(SettingsView()) }),
            Scenario(name: "40-einstellungen-kurzbefehle", size: settingsSize, prepare: settings(.shortcuts), view: { AnyView(SettingsView()) }),
        ]
        /// Popover-Inhalte (Popover sind eigene Fenster und werden deshalb einzeln abgebildet).
        func popover<V: View>(_ width: CGFloat, @ViewBuilder _ content: @escaping @MainActor () -> V) -> @MainActor () -> AnyView {
            return { AnyView(ZStack { AmbientBackground(); GlassMenuPanel(width: width) { content() } }) }
        }
        let userPresets: @MainActor (AppModel) -> Void = { m in
            var s = m.settings
            s.eqUserPresets = []   // Szenario läuft mehrfach (hell/dunkel, zwei Ansichten)
            s.effects = AudioEffectsSettings().withPreset(EqPresets.rock).withBass(3)
            _ = s.saveEqPreset(name: "Abend")
            s.effects = AudioEffectsSettings().withPreset(EqPresets.jazz)
            _ = s.saveEqPreset(name: "Kopfhörer")
            m.settings = s
            m.player.setDemoState(queueUids: Array(1...12), currentIndex: 0, positionMs: 74_000, playing: true)
        }
        list += [
            Scenario(name: "35-popover-tonhoehe", size: CGSize(width: 380, height: 460), prepare: { m in
                m.settings.pitch = PitchSettings().withSemitones(1.5)
            }, view: popover(340) { PitchControls(compact: true) }),
            Scenario(name: "35-popover-equalizer", size: CGSize(width: 400, height: 520), prepare: userPresets,
                     view: popover(360) { EqualizerQuickPanel(close: {}) }),
            Scenario(name: "35-popover-designs", size: CGSize(width: 520, height: 520), prepare: { m in
                m.player.setDemoState(queueUids: Array(1...12), currentIndex: 0, positionMs: 74_000, playing: true)
            }, view: popover(480) { DesignQuickPicker(artwork: NowPlayingArtwork(), more: {}) }),
            Scenario(name: "13-equalizer-eigene", size: CGSize(width: 640, height: 720), prepare: userPresets, view: { AnyView(EqualizerWindow()) }),
            Scenario(name: "34-mini-kassette", size: big, prepare: { m in
                for c in LibraryViewContext.allCases { m.setViewOptions(.defaults(for: c), for: c) }
                m.settings.pitch = PitchSettings()
                m.settings.miniPlayerSize = .large
                m.settings.cassetteColor = .mint
                library(.tracks, nil, nil, false, .cassette)(m)
            }, view: main),
            Scenario(name: "20-titel-detailliste-klein", size: small, prepare: view(.tracks, .tracks, .detailedList), view: main),
            Scenario(name: "24-playlists-raster", size: big, prepare: view(.playlists, .playlists, .grid), view: main),
        ]
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
        // ML_SNAPSHOT_ONLY="03-alben,30-modern" → nur Szenarien, deren Name einen der Teile enthält (Fehlersuche)
        let only = (ProcessInfo.processInfo.environment["ML_SNAPSHOT_ONLY"] ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty }
        let selected = scenarios(model).filter { sc in only.isEmpty || only.contains { sc.name.contains($0) } }
        for scenario in selected {
            for dark in [false, true] {
                print("[Snapshot] ▸ \(scenario.name) \(dark ? "dunkel" : "hell")")
                fflush(stdout)
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
                // Warten und dabei die Auslastung des Hauptthreads messen: Verspätung kurzer Schlafphasen
                // (bei ruhender Ansicht ≈ 0; hoch, wenn die Ansicht ständig neu berechnet/gezeichnet wird).
                let started = CACurrentMediaTime()
                var lag: [Double] = []
                let hold = Double(ProcessInfo.processInfo.environment["ML_SNAPSHOT_HOLD"] ?? "") ?? 2.2
                var cpuStart: (wall: Double, cpu: Double)?
                while CACurrentMediaTime() - started < hold {
                    let t0 = CACurrentMediaTime()
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    let late = (CACurrentMediaTime() - t0 - 0.05) * 1000
                    if CACurrentMediaTime() - started > 1.2 {   // nach dem Aufbau
                        lag.append(max(0, late))
                        if cpuStart == nil { cpuStart = (CACurrentMediaTime(), Benchmark.threadCPUSeconds()) }
                    }
                }
                let meanLag = lag.isEmpty ? 0 : lag.reduce(0, +) / Double(lag.count)
                let maxLag = lag.max() ?? 0
                let elapsed = (CACurrentMediaTime() - started) * 1000
                var mainLoad: Double = 0
                if let c = cpuStart, CACurrentMediaTime() - c.wall > 0.2 {
                    mainLoad = (Benchmark.threadCPUSeconds() - c.cpu) / (CACurrentMediaTime() - c.wall) * 100
                }
                print(String(format: "[Snapshot] %@ %@: Aufbau+Warten %.0f ms, Hauptthread-Verzögerung Ø %.1f ms, max %.1f ms, Hauptthread belegt %.0f %%",
                             scenario.name, dark ? "dunkel" : "hell", elapsed, meanLag, maxLag, mainLoad))
                fflush(stdout)
                if window.contentRect(forFrameRect: window.frame).size != scenario.size {
                    window.setContentSize(scenario.size)
                    try? await Task.sleep(nanoseconds: 600_000_000)
                }
                let file = out.appendingPathComponent("\(scenario.name)-\(dark ? "dunkel" : "hell")-\(Int(scenario.size.width))x\(Int(scenario.size.height)).png")
                let method = capture(window, to: file)
                manifest.append(["file": file.lastPathComponent, "method": method, "glass": LiquidGlass.isAvailable ? "liquid-glass" : "fallback",
                                 "mainThreadLagMeanMs": String(format: "%.1f", meanLag), "mainThreadLagMaxMs": String(format: "%.1f", maxLag),
                                 "elapsedMs": String(format: "%.0f", elapsed), "mainThreadBusyPercent": String(format: "%.0f", mainLoad)])
                try? (manifest.map { "\($0["file"] ?? "") \($0["mainThreadLagMeanMs"] ?? "") \($0["mainThreadBusyPercent"] ?? "")% \($0["elapsedMs"] ?? "")" }.joined(separator: "\n"))
                    .write(to: out.appendingPathComponent("progress.txt"), atomically: true, encoding: .utf8)
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
