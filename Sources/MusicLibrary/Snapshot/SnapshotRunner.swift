import SwiftUI
import AppKit
import MLCore
import MLStore
import MLTags
import MLStudio

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
                m.workspace = .library
                m.section = section
                m.stacks = destination.map { [section: [$0]] } ?? [:]
                m.sidePanel = panel
                m.settings.playerTheme = theme
                m.settings.visualizer = false
                m.settings.playerBackground = .auto
                m.player.engine.levels.demoValues = nil
                LibrarySelectionStore.shared.clear()
                LibraryScrollSeed.pendingOffset = nil
                SystemMotion.snapshotAllowsMotion = false
                // Sortierung je Szenario festlegen (sonst wirkt die eines vorigen Szenarios nach)
                m.settings.trackSort = Sort(TrackSort.title, descending: false)
                m.settings.albumSort = Sort(AlbumSort.title, descending: false)
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
        list += studioScenarios(library: library, main: main, big: big, small: small, wide: wide)
        return list
    }

    /// „Titel bearbeiten“ mit einem Titel der Demo-Bibliothek (erfundene Analyse; `configured` = Beispiel-Einstellungen).
    @MainActor
    static func editDemo(_ m: AppModel, _ s: StudioModel, configured: Bool) {
        if let src = StudioDemo.libraryTrackSource(m) {
            StudioDemo.load(s, src, playhead: 38.2)
        }
        s.mode = .edit
        s.cutSaveMode = .replaceOriginal
        s.trackAnalysisProgress = nil
        s.trackAnalysis = TrackAnalysis(reference: 441.6, referenceConfidence: 0.72, keyTonic: 9, keyScale: .minor, keyCorrelation: 0.81,
                                        loudness: -10.8, peakDb: -0.3, leadingSilence: 0.42, trailingSilence: 2.35)
        var e = TrackEdit()
        e.tuningFrom = 441.6
        e.tuningTo = 441.6
        e.autoTuneKey = 9
        e.autoTuneScale = .minor
        if configured {
            e.speed = 1.06
            e.tuningTo = 432
            e.bandGains = EqPresets.pop.gains
            e.bassDb = 2
            e.enhance = true
        }
        s.trackEdit = e
    }

    /// Version 2.2: Audio Studio – Leerzustand, Quellen, Editor, Export, Metadaten, Warteschlange, Verlauf,
    /// Werkzeuge, Spotify, Doppel-Warnung, Schneiden mit „Original ersetzen“, schmales Fenster.
    @MainActor
    private static func studioScenarios(library: @escaping @MainActor (LibrarySection, Destination?, SidePanel?, Bool, PlayerTheme) -> @MainActor (AppModel) -> Void,
                                        main: @escaping @MainActor () -> AnyView, big: CGSize, small: CGSize, wide: CGSize) -> [Scenario] {
        /// Grundzustand: Bibliothek mit Mini-Player, „Hinzufügen“ (bzw. mit `.studio` das Studio) geöffnet und
        /// zurückgesetzt, dann `setup` mit dem Modell des Bereichs.
        func studio(_ workspace: MainWorkspace = .add, _ setup: @escaping @MainActor (AppModel, StudioModel) -> Void = { _, _ in }) -> @MainActor (AppModel) -> Void {
            return { m in
                for c in LibraryViewContext.allCases { m.setViewOptions(.defaults(for: c), for: c) }
                library(.tracks, nil, nil, false, .vinylStudio)(m)
                m.settings.miniPlayerSize = .standard
                m.settings.playerBackground = .auto
                StudioDemo.reset(m)
                m.workspace = workspace
                setup(m, workspace == .studio ? m.studio : m.addStudio)
            }
        }
        /// Blatt-Inhalt wie in `GlassSheet` (feste Breite, Höhe nach Inhalt), oben im Bild.
        func sheet<V: View>(_ width: CGFloat, @ViewBuilder _ content: @escaping @MainActor () -> V) -> @MainActor () -> AnyView {
            return {
                AnyView(ZStack(alignment: .top) {
                    AmbientBackground()
                    content().frame(width: width).fixedSize(horizontal: false, vertical: true)
                })
            }
        }
        let withJobs: @MainActor (StudioModel) -> Void = { s in
            s.jobs = Array(StudioDemo.jobs().prefix(4))
            s.history = StudioDemo.history()
        }
        var list: [Scenario] = [
            Scenario(name: "60-studio-leer", size: big, prepare: studio(), view: main),
            Scenario(name: "60-studio-leer-schmal", size: small, prepare: studio(), view: main),
            Scenario(name: "60-studio-quelle", size: wide, prepare: studio { _, s in
                StudioDemo.load(s, StudioDemo.youtubeSource(), selection: TrimRange(start: 42.3, end: 190.5), playhead: 61.8)
                withJobs(s)
            }, view: main),
            Scenario(name: "60-studio-quelle-standard", size: big, prepare: studio { _, s in
                StudioDemo.load(s, StudioDemo.youtubeSource(), selection: TrimRange(start: 42.3, end: 190.5), playhead: 61.8)
                withJobs(s)
            }, view: main),
            Scenario(name: "60-studio-zoom-blenden", size: wide, prepare: studio { _, s in
                StudioDemo.load(s, StudioDemo.youtubeSource(), selection: TrimRange(start: 58.2, end: 92.6), playhead: 66.4)
                s.fadeIn = 2
                s.fadeOut = 3
                s.zoom = 4.5
                s.visibleStart = 48
                withJobs(s)
            }, view: main),
            Scenario(name: "60-studio-export-mp3", size: wide, prepare: studio { _, s in
                StudioDemo.load(s, StudioDemo.youtubeSource(), selection: TrimRange(start: 42.3, end: 190.5))
                s.setFormat(.mp3)
                s.updateOptions { $0.mp3Bitrate = 320 }
                withJobs(s)
                StudioScrollSeed.pending = .export
            }, view: main),
            Scenario(name: "60-studio-export-wav", size: wide, prepare: studio { _, s in
                StudioDemo.load(s, StudioDemo.localWavSource())
                s.setFormat(.wav)
                s.updateOptions { $0.pcmDepth = .int24; $0.sampleRate = 96_000 }
                StudioScrollSeed.pending = .export
            }, view: main),
            Scenario(name: "60-studio-export-flac", size: big, prepare: studio { _, s in
                StudioDemo.load(s, StudioDemo.localWavSource(), selection: TrimRange(start: 12.5, end: 231.0))
                s.setFormat(.flac)
                s.updateOptions { $0.flacKeepSourceDepth = false; $0.pcmDepth = .int16; $0.flacLevel = 8 }
                StudioScrollSeed.pending = .export
            }, view: main),
            Scenario(name: "60-studio-metadaten", size: big, prepare: studio { _, s in
                StudioDemo.load(s, StudioDemo.youtubeSource(), selection: TrimRange(start: 42.3, end: 190.5))
                s.metadata.trackNumber = 3
                s.settings.fileNameScheme = .custom("Lina Sommer – Stadt aus Glas (Radio Edit)")
                s.customFileName = "Lina Sommer – Stadt aus Glas (Radio Edit)"
                withJobs(s)
                StudioScrollSeed.pending = .metadata
            }, view: main),
        ]
        list += [
            Scenario(name: "60-studio-ziel", size: big, prepare: studio { _, s in
                StudioDemo.load(s, StudioDemo.youtubeSource(), selection: TrimRange(start: 42.3, end: 190.5))
                s.settings.librarySubfolder = "Audio Studio/Live"
                withJobs(s)
                StudioScrollSeed.pending = .destination
            }, view: main),
            Scenario(name: "60-studio-warteschlange", size: wide, prepare: studio { _, s in
                StudioDemo.load(s, StudioDemo.localWavSource())
                s.jobs = StudioDemo.jobs()
                s.history = StudioDemo.history()
            }, view: main),
            Scenario(name: "60-studio-verlauf", size: wide, prepare: studio { _, s in
                StudioDemo.load(s, StudioDemo.localWavSource())
                s.jobs = Array(StudioDemo.jobs().prefix(2))
                s.history = StudioDemo.history()
                StudioDemo.queueTab = .history
            }, view: main),
            Scenario(name: "60-studio-werkzeuge", size: CGSize(width: 560, height: 500), prepare: studio { _, s in
                s.toolStatus = StudioDemo.partialTools
            }, view: sheet(560) { StudioToolsView(studio: AppModel.shared!.addStudio, close: {}) }),
            Scenario(name: "60-studio-werkzeuge-installation", size: CGSize(width: 560, height: 540), prepare: studio { _, s in
                s.toolStatus = StudioToolStatus()
                s.toolInstall = .running(ToolInstallProgress(step: "Deno wird geladen und geprüft … 16,2 von 38,4 MB", fraction: 0.42))
            }, view: sheet(560) { StudioToolsView(studio: AppModel.shared!.addStudio, close: {}) }),
            Scenario(name: "60-studio-werkzeuge-fehlen", size: big, prepare: studio { _, s in
                s.toolStatus = StudioToolStatus()
                s.urlText = "https://www.youtube.com/watch?v=Beispiel01"
                s.sourceState = .failed(StudioError.toolMissing("yt-dlp").errorDescription ?? "")
            }, view: main),
            Scenario(name: "60-studio-spotify", size: big, prepare: studio { _, s in
                s.urlText = "https://open.spotify.com/track/Beispiel"
                s.source = StudioDemo.spotifySource()
                s.sourceState = .ready
                s.metadata = s.source?.suggested ?? StudioMetadata()
            }, view: main),
            Scenario(name: "60-studio-doppelt", size: big, prepare: studio { m, s in
                StudioDemo.load(s, StudioDemo.youtubeSource(), selection: TrimRange(start: 0, end: 212.4))
                s.exportWholeFile = true
                if let t = m.track(1) {
                    StudioDemo.duplicates = [DuplicateCheck.Candidate(uid: t.uid, title: t.displayTitle, artist: t.artistText ?? "",
                                                                      durationSeconds: 212.0, path: t.path)]
                }
                StudioDemo.askDuplicates = true
            }, view: main),
            Scenario(name: "61-studio-instagram", size: big, prepare: studio { _, s in
                StudioDemo.load(s, StudioDemo.instagramSource())
                s.urlText = "https://www.instagram.com/reel/Beispiel01/"
                s.exportWholeFile = true
            }, view: main),
            Scenario(name: "61-studio-instagram-analyse", size: big, prepare: studio { _, s in
                s.urlText = "https://www.instagram.com/reel/Beispiel01/"
                s.sourceState = .analyzing(StudioModel.analyzingText(.web, url: URL(string: "https://www.instagram.com/reel/Beispiel01/")))
            }, view: main),
            Scenario(name: "60-studio-analyse", size: big, prepare: studio { _, s in
                s.urlText = "https://soundcloud.com/beispiel/velvet-rain"
                s.sourceState = .analyzing("SoundCloud wird abgefragt …")
            }, view: main),
            Scenario(name: "60-studio-laden", size: big, prepare: studio { _, s in
                StudioDemo.load(s, StudioDemo.youtubeSource())
                s.waveform = nil
                s.prepare = .downloading(DownloadProgress(fraction: 0.46, bytesDone: 1_600_000, bytesTotal: 3_480_000, bytesPerSecond: 1_900_000, etaSeconds: 1))
            }, view: main),
            Scenario(name: "60-studio-laden-noetig", size: big, prepare: studio { _, s in
                StudioDemo.load(s, StudioDemo.youtubeSource())
                s.waveform = nil
                s.prepare = .needed
            }, view: main),
        ]
        list += [
            Scenario(name: "60-studio-wellenform-berechnung", size: big, prepare: studio { _, s in
                StudioDemo.load(s, StudioDemo.localWavSource())
                s.waveform = nil
                s.waveformProgress = 0.42
            }, view: main),
            Scenario(name: "60-studio-schneiden", size: wide, prepare: studio(.studio) { m, s in
                if let src = StudioDemo.libraryTrackSource(m) {
                    StudioDemo.load(s, src, selection: TrimRange(start: 8.4, end: 141.2), playhead: 20.5)
                }
                s.cutSaveMode = .replaceOriginal
                s.host.history = StudioDemo.history()
            }, view: main),
            Scenario(name: "60-studio-schneiden-speichern", size: big, prepare: studio(.studio) { m, s in
                if let src = StudioDemo.libraryTrackSource(m) {
                    StudioDemo.load(s, src, selection: TrimRange(start: 8.4, end: 141.2))
                }
                s.cutSaveMode = .replaceOriginal
                StudioScrollSeed.pending = .export
            }, view: main),
            Scenario(name: "60-studio-schneiden-bestaetigen", size: CGSize(width: 480, height: 372), prepare: studio(.studio) { m, s in
                if let src = StudioDemo.libraryTrackSource(m) {
                    StudioDemo.load(s, src, selection: TrimRange(start: 8.4, end: 141.2))
                }
                s.cutSaveMode = .replaceOriginal
            }, view: sheet(480) { StudioReplaceDialogView(studio: AppModel.shared!.studio, close: {}) }),
            Scenario(name: "62-studio-bearbeiten", size: wide, prepare: studio(.studio) { m, s in
                editDemo(m, s, configured: true)
                s.host.history = StudioDemo.history()
            }, view: main),
            Scenario(name: "62-studio-bearbeiten-standard", size: big, prepare: studio(.studio) { m, s in
                editDemo(m, s, configured: false)
                s.trackAnalysis = nil
                s.trackAnalysisProgress = 0.42
            }, view: main),
            Scenario(name: "62-studio-bearbeiten-regler", size: big, prepare: studio(.studio) { m, s in
                editDemo(m, s, configured: true)
                s.trackEdit.autoTune = true
                s.trackEdit.semitones = -2
                StudioScrollSeed.pending = .tools
            }, view: main),
            Scenario(name: "62-studio-bearbeiten-werkzeuge", size: big, prepare: studio(.studio) { m, s in
                editDemo(m, s, configured: true)
                s.trackEdit.autoTune = true
                StudioScrollSeed.pending = .export
            }, view: main),
            Scenario(name: "62-studio-bearbeiten-schmal", size: small, prepare: studio(.studio) { m, s in
                editDemo(m, s, configured: true)
                StudioScrollSeed.pending = .export
            }, view: main),
            Scenario(name: "62-studio-bearbeiten-bestaetigen", size: CGSize(width: 480, height: 400), prepare: studio(.studio) { m, s in
                editDemo(m, s, configured: true)
            }, view: sheet(480) { StudioReplaceDialogView(studio: AppModel.shared!.studio, close: {}) }),
            Scenario(name: "60-studio-verlauf-loeschen", size: CGSize(width: 440, height: 210), prepare: studio { _, s in
                s.history = StudioDemo.history()
            }, view: sheet(440) { StudioClearHistoryDialogView(studio: AppModel.shared!.addStudio, scope: .add, close: {}) }),
            Scenario(name: "60-studio-schmal", size: small, prepare: studio { _, s in
                StudioDemo.load(s, StudioDemo.youtubeSource(), selection: TrimRange(start: 42.3, end: 190.5), playhead: 61.8)
                withJobs(s)
            }, view: main),
            Scenario(name: "60-studio-schmal-export", size: small, prepare: studio { _, s in
                StudioDemo.load(s, StudioDemo.youtubeSource(), selection: TrimRange(start: 42.3, end: 190.5))
                withJobs(s)
                StudioScrollSeed.pending = .export
            }, view: main),
            Scenario(name: "63-studio-auswahl", size: big, prepare: studio(.studio) { m, s in
                s.host.history = StudioDemo.history()
            }, view: main),
            Scenario(name: "63-studio-auswahl-breit", size: wide, prepare: studio(.studio) { m, s in
                s.host.jobs = StudioDemo.jobs()
                s.host.history = StudioDemo.history()
                StudioDemo.queueTab = .history
            }, view: main),
            Scenario(name: "63-studio-auswahl-schmal", size: small, prepare: studio(.studio), view: main),
            Scenario(name: "63-studio-verlauf-loeschen", size: CGSize(width: 440, height: 210), prepare: studio(.studio) { _, s in
                s.host.history = StudioDemo.history()
            }, view: sheet(440) { StudioClearHistoryDialogView(studio: AppModel.shared!.addStudio, scope: .edit, close: {}) }),
            Scenario(name: "60-studio-einstellungen", size: CGSize(width: 860, height: 760), prepare: studio { m, _ in
                m.workspace = .library
                WindowRouter.shared.pendingSettingsCategory = SettingsCategory.studio.rawValue
            }, view: { AnyView(SettingsView()) }),
        ]
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
        // v2.1 Bibliothek: feste Werkzeugleiste beim Scrollen, größte Cover, Mehrfachauswahl, Dialoge
        list += [
            Scenario(name: "26-titel-raster-gescrollt", size: big, prepare: { m in
                view(.tracks, .tracks, .grid)(m)
                LibraryScrollSeed.pendingOffset = 760
            }, view: main),
            Scenario(name: "26-titel-liste-gescrollt", size: big, prepare: { m in
                view(.tracks, .tracks, .list)(m)
                LibraryScrollSeed.pendingOffset = 900
            }, view: main),
            // 2.2.2: Abschnitte nach Erscheinungsjahr / Hinzugefügt (oben und gescrollt mit Abschnitts-Kapsel)
            Scenario(name: "56-alben-abschnitte-jahr", size: big, prepare: { m in
                view(.albums, .albums, .grid)(m)
                m.settings.albumSort = Sort(AlbumSort.year, descending: true)
            }, view: main),
            Scenario(name: "56-alben-abschnitte-jahr-gescrollt", size: big, prepare: { m in
                view(.albums, .albums, .grid)(m)
                m.settings.albumSort = Sort(AlbumSort.year, descending: true)
                LibraryScrollSeed.pendingOffset = 900
            }, view: main),
            Scenario(name: "56-alben-abschnitte-hinzugefuegt-liste", size: big, prepare: { m in
                view(.albums, .albums, .list)(m)
                m.settings.albumSort = Sort(AlbumSort.dateAdded, descending: true)
                LibraryScrollSeed.pendingOffset = 500
            }, view: main),
            Scenario(name: "56-alben-abschnitte-jahr-detail", size: big, prepare: { m in
                view(.albums, .albums, .detailedList)(m)
                m.settings.albumSort = Sort(AlbumSort.year, descending: true)
            }, view: main),
            Scenario(name: "56-titel-abschnitte-hinzugefuegt-liste", size: big, prepare: { m in
                view(.tracks, .tracks, .list)(m)
                m.settings.trackSort = Sort(TrackSort.dateAdded, descending: true)
                LibraryScrollSeed.pendingOffset = 900
            }, view: main),
            Scenario(name: "56-titel-abschnitte-jahr-raster", size: big, prepare: { m in
                view(.tracks, .tracks, .grid)(m)
                m.settings.trackSort = Sort(TrackSort.year, descending: true)
            }, view: main),
            Scenario(name: "56-titel-abschnitte-jahr-klein", size: small, prepare: { m in
                view(.tracks, .tracks, .list)(m)
                m.settings.trackSort = Sort(TrackSort.year, descending: true)
                LibraryScrollSeed.pendingOffset = 600
            }, view: main),
            Scenario(name: "26-alben-raster-max", size: big, prepare: { m in
                view(.albums, .albums, .grid)(m)
                var o = m.viewOptions(.albums)
                o.coverSize = LibraryViewOptions.coverSizeRange.upperBound
                m.setViewOptions(o, for: .albums)
            }, view: main),
            Scenario(name: "26-alben-raster-max-breit", size: CGSize(width: 1520, height: 940), prepare: { m in
                view(.albums, .albums, .grid)(m)
                var o = m.viewOptions(.albums)
                o.coverSize = LibraryViewOptions.coverSizeRange.upperBound
                m.setViewOptions(o, for: .albums)
            }, view: main),
            Scenario(name: "27-auswahl-alben", size: big, prepare: { m in
                view(.albums, .albums, .grid)(m)
                LibrarySelectionSeed.pending = (kind: .albums, count: 3)
            }, view: main),
            Scenario(name: "27-auswahl-titel", size: big, prepare: { m in
                view(.tracks, .tracks, .list)(m)
                LibrarySelectionSeed.pending = (kind: .tracks, count: 12)
            }, view: main),
            Scenario(name: "28-loeschen-album", size: CGSize(width: 470, height: 480), prepare: { _ in }, view: {
                let a = AppModel.shared?.index.albums.first
                return AnyView(DeleteTracksDialogView(uids: a?.trackUids ?? [1], subject: .album(title: a?.title ?? "Album"), close: {}))
            }),
            Scenario(name: "28-loeschen-papierkorb", size: CGSize(width: 470, height: 480), prepare: { _ in }, view: {
                AnyView(DeleteTracksDialogView(uids: Array(1...12), subject: .tracks, close: {}, confirmTrash: true))
            }),
            Scenario(name: "29-als-album-zusammenfassen", size: CGSize(width: 500, height: 580), prepare: { _ in }, view: {
                AnyView(MergeAlbumSheet(uids: Array(1...8), close: {}))
            }),
        ]
        list += v21PlayerScenarios(library: library, main: main, big: big, small: small, mini: mini, settings: settings)
        return list
    }

    /// v2.1: alle fünf Mini-Player-Größen, Player-Hintergründe, Formatzeile, Pegelbalken, EQ-Fenster, Einstellungen.
    @MainActor
    private static func v21PlayerScenarios(library: @escaping @MainActor (LibrarySection, Destination?, SidePanel?, Bool, PlayerTheme) -> @MainActor (AppModel) -> Void,
                                           main: @escaping @MainActor () -> AnyView, big: CGSize, small: CGSize,
                                           mini: @escaping (MiniPlayerSize) -> @MainActor (AppModel) -> Void,
                                           settings: @escaping (SettingsCategory) -> @MainActor (AppModel) -> Void) -> [Scenario] {
        func playerBackground(_ style: PlayerBackgroundStyle, custom: UInt32 = 0xFF6B4FA0, theme: PlayerTheme = .vinylStudio, open: Bool = true) -> @MainActor (AppModel) -> Void {
            return { m in
                for c in LibraryViewContext.allCases { m.setViewOptions(.defaults(for: c), for: c) }
                library(.tracks, nil, nil, open, theme)(m)
                var s = m.settings
                s.miniPlayerSize = .standard
                s.playerBackground = style
                s.playerBackgroundCustom = custom
                s.playerBackgroundTintsMini = true
                m.settings = s
            }
        }
        var list: [Scenario] = [
            Scenario(name: "50-mini-klein", size: big, prepare: mini(.compact), view: main),
            Scenario(name: "50-mini-mittel", size: big, prepare: mini(.standard), view: main),
            Scenario(name: "50-mini-gross", size: big, prepare: mini(.large), view: main),
            Scenario(name: "50-mini-sehr-gross", size: big, prepare: mini(.extraLarge), view: main),
            Scenario(name: "50-mini-sehr-gross-schmal", size: small, prepare: mini(.extraLarge), view: main),
            Scenario(name: "50-mini-riesig", size: big, prepare: mini(.huge), view: main),
            Scenario(name: "50-mini-riesig-schmal", size: small, prepare: mini(.huge), view: main),
            Scenario(name: "51-hintergrund-rauchglas", size: big, prepare: playerBackground(.smokedGlass), view: main),
            Scenario(name: "51-hintergrund-weiss-kassette", size: big, prepare: playerBackground(.white, theme: .cassette), view: main),
        ]
        list += [
            Scenario(name: "51-hintergrund-blau-modern-glass", size: big, prepare: playerBackground(.blue, theme: .modernGlass), view: main),
            Scenario(name: "51-hintergrund-eigene-farbe-classic", size: big, prepare: playerBackground(.custom, custom: 0xFFE8C547, theme: .classic), view: main),
            Scenario(name: "51-hintergrund-schwarz-cd", size: big, prepare: playerBackground(.black, theme: .portableCD), view: main),
            Scenario(name: "51-hintergrund-mini-getoent", size: big, prepare: { m in
                playerBackground(.pink, open: false)(m)
                m.settings.miniPlayerSize = .huge
            }, view: main),
            Scenario(name: "52-player-formatzeile", size: big, prepare: playerBackground(.auto), view: main),
            Scenario(name: "52-player-formatzeile-hochkant", size: CGSize(width: 900, height: 1080), prepare: playerBackground(.auto, theme: .modernGlass), view: main),
            Scenario(name: "52-player-balken-cd", size: big, prepare: { m in
                playerBackground(.auto, theme: .portableCD)(m)
                m.settings.visualizer = true
                SystemMotion.snapshotAllowsMotion = true
                m.player.engine.levels.demoValues = [0.82, 0.9, 0.74, 0.66, 0.7, 0.58, 0.62, 0.5, 0.46, 0.52, 0.4, 0.36, 0.3, 0.26, 0.2, 0.14, 0.72, 0.66]
            }, view: main),
            Scenario(name: "52-player-balken-cd-klein", size: small, prepare: { m in
                playerBackground(.auto, theme: .portableCD)(m)
                m.settings.visualizer = true
                SystemMotion.snapshotAllowsMotion = true
                m.player.engine.levels.demoValues = [0.82, 0.9, 0.74, 0.66, 0.7, 0.58, 0.62, 0.5, 0.46, 0.52, 0.4, 0.36, 0.3, 0.26, 0.2, 0.14, 0.72, 0.66]
            }, view: main),
            Scenario(name: "53-equalizer-fenster-pop", size: CGSize(width: 640, height: 720), prepare: { m in
                m.settings.playerBackground = .auto
                m.player.engine.levels.demoValues = nil
                m.settings.effects = AudioEffectsSettings().withPreset(EqPresets.pop).withBass(2)
            }, view: { AnyView(EqualizerWindow()) }),
        ]
        list += [
            Scenario(name: "53-equalizer-fenster-aus", size: CGSize(width: 640, height: 720), prepare: { m in
                var fx = AudioEffectsSettings().withPreset(EqPresets.rock)
                fx.eqEnabled = false
                m.settings.effects = fx
            }, view: { AnyView(EqualizerWindow()) }),
            Scenario(name: "54-einstellungen-hinzufuegedatum", size: CGSize(width: 860, height: 1240), prepare: { m in
                settings(.library)(m)
                m.datesAddedStatus = "1.284 Hinzufügedaten bestimmt (1.102 aus Apple Musik, 182 aus dem Erstellungsdatum der Datei)."
            }, view: { AnyView(SettingsView()) }),
            Scenario(name: "54-einstellungen-player-hintergrund", size: CGSize(width: 860, height: 1000), prepare: { m in
                settings(.playerDesigns)(m)
                m.settings.playerBackground = .violet
            }, view: { AnyView(SettingsView()) }),
            Scenario(name: "55-alben-hinzugefuegt-neueste", size: big, prepare: { m in
                for c in LibraryViewContext.allCases { m.setViewOptions(.defaults(for: c), for: c) }
                library(.albums, nil, nil, false, .vinylStudio)(m)
                m.settings.playerBackground = .auto
                m.settings.miniPlayerSize = .standard
                m.datesAddedStatus = nil
                m.settings.albumSort = Sort(AlbumSort.dateAdded, descending: true)
            }, view: main),
            Scenario(name: "55-titel-hinzugefuegt-aelteste", size: big, prepare: { m in
                for c in LibraryViewContext.allCases { m.setViewOptions(.defaults(for: c), for: c) }
                library(.tracks, nil, nil, false, .vinylStudio)(m)
                m.settings.trackSort = Sort(TrackSort.dateAdded, descending: false)
            }, view: main),
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
