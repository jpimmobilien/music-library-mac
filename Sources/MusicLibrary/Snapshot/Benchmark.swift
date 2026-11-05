import SwiftUI
import AppKit
import MLCore
import MLStore

/// Messlauf mit einer großen, erfundenen Bibliothek (Standard: 10.000 Titel, 1.600 Alben):
/// `"Music Library.app/Contents/MacOS/MusicLibrary" --benchmark <Ordner> [--tracks 10000]`
///
/// Gemessen wird, was sich beim Bedienen „zäh“ anfühlen würde – jeweils die Zeit, die der Hauptthread für
/// Aktualisierung, Layout und Zeichnen braucht (Budget bei 60 Hz: 16,7 ms je Bild):
/// Index und Listen berechnen, Bereich wechseln, Ansicht wechseln, Suchen, Scrollen, Player öffnen.
/// Ergebnis: `benchmark.json` und `benchmark.txt` im Ordner. Keine Benutzerdaten, keine Wiedergabe.
enum Benchmark {
    static var isRequested: Bool { CommandLine.arguments.contains("--benchmark") }

    static var outputDirectory: URL {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--benchmark"), i + 1 < args.count {
            return URL(fileURLWithPath: args[i + 1], isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("benchmark", isDirectory: true)
    }

    static var trackCount: Int {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--tracks"), i + 1 < args.count, let n = Int(args[i + 1]) { return max(100, n) }
        return 10_000
    }

    struct Measurement: Codable {
        var name: String
        var samples: [Double]   // Millisekunden
        var mean: Double { samples.isEmpty ? 0 : samples.reduce(0, +) / Double(samples.count) }
        var max: Double { samples.max() ?? 0 }
        var p95: Double {
            guard !samples.isEmpty else { return 0 }
            let s = samples.sorted()
            return s[min(s.count - 1, Int(Double(s.count) * 0.95))]
        }
    }

    // MARK: - Bibliothek erzeugen

    @MainActor
    static func makeModel() -> AppModel {
        let store = try! LibraryStore.inMemory()
        let model = AppModel(store: store, demo: true)
        let lib = makeLibrary(tracks: trackCount)
        ArtworkStore.shared.setOverrides(lib.covers)
        model.setDemoData(tracks: lib.tracks, favorites: lib.favorites, favoriteAlbums: [:], stats: lib.stats, playlists: lib.playlists, history: [])
        return model
    }

    /// Erfundene Bibliothek: Titel verteilen sich auf Alben (6 Titel im Schnitt), Interpreten, Genres und Jahre.
    /// Cover: 320 verschiedene, gezeichnete Bilder, reihum auf die Alben verteilt.
    static func makeLibrary(tracks count: Int) -> (tracks: [Track], covers: [Int64: String], favorites: [Int64: Int64],
                                                   stats: [Int64: PlayStats], playlists: [Playlist]) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MusicLibraryBenchmark-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let genres = ["Pop", "Rock", "Indie Rock", "Jazz", "Electronic", "Klassik", "Hip-Hop", "Soul", "Country", "Schlager", "Darkwave",
                      "Metal", "Folk", "Reggae", "Soundtrack", "Ambient", "Dance", "Blues", "Latin", "Singer-Songwriter"]
        let words = ["Licht", "Nacht", "Sommer", "Stadt", "Meer", "Herz", "Wind", "Feuer", "Glas", "Traum", "Stern", "Regen", "Morgen",
                     "Echo", "Neon", "Gold", "Silber", "Wolke", "Fluss", "Berg", "Blue", "Night", "Fire", "Dream", "Heart", "City",
                     "River", "Love", "Ghost", "Wild", "Velvet", "Electric", "Paper", "Summer", "Winter", "Shadow", "Light", "Ocean"]
        let coverCount = 320
        var coverPaths: [String] = []
        for i in 0..<coverCount {
            let path = dir.appendingPathComponent("c\(i).png").path
            let a = DemoLibrary.albums[i % DemoLibrary.albums.count]
            let hueShift = UInt32((i * 37) % 200)
            let spec = DemoLibrary.AlbumSpec(title: "", artist: "", genre: "", year: 2000,
                                             colors: (a.colors.0 ^ (hueShift << 8), a.colors.1 ^ (hueShift << 4)), tracks: [])
            DemoLibrary.writeCover(spec, index: i, to: path)
            coverPaths.append(path)
        }
        let albumCount = max(1, count / 6)
        let artistCount = max(1, albumCount / 3)
        let now = Int64(Date().timeIntervalSince1970)
        var tracks: [Track] = []
        tracks.reserveCapacity(count)
        var covers: [Int64: String] = [:]
        var uid: Int64 = 1
        for album in 0..<albumCount {
            let artist = "\(words[album % words.count]) \(words[(album / 7 + 3) % words.count]) \(album % artistCount)"
            let title = "\(words[(album * 5) % words.count]) \(words[(album * 11 + 2) % words.count]) \(album)"
            let genre = genres[album % genres.count]
            let year = 1960 + (album * 13) % 65
            let n = count / albumCount + (album < count % albumCount ? 1 : 0)
            let cover = coverPaths[album % coverCount]
            for t in 0..<n {
                let seconds: Int = (album * 31 + t * 17) % 300
                let duration: Int64 = Int64(120_000 + seconds * 1000)
                let kbps: Int = album % 4 == 0 ? 900 : 256
                let bpm: Int = 80 + (t * 9 + album) % 90
                let rating: Int? = (album + t) % 5 == 0 ? 80 : nil
                let bytes: Int64 = duration * Int64(kbps) / 8 + uid
                let modified: Int64 = now - Int64(album * 3600)
                let added: Int64 = now - Int64(album * 7200 + t)
                let codec: String = album % 4 == 0 ? "ALAC" : "AAC"
                let fileName: String = "\(t + 1) \(words[(album + t) % words.count]).m4a"
                let trackTitle: String = "\(words[(album + t * 3) % words.count]) \(words[(t * 7 + album) % words.count])"
                let track = Track(
                    uid: uid, folderID: 1, path: "/Benchmark/\(artist)/\(title)/\(t + 1).m4a", relativePath: "\(artist)/\(title)/",
                    fileName: fileName,
                    title: trackTitle,
                    artists: [artist], album: title, albumArtists: [artist], genres: [genre], year: year,
                    trackNumber: t + 1, trackTotal: n, discNumber: 1, discTotal: 1, bpm: bpm,
                    rating: rating, durationMs: duration, sizeBytes: bytes,
                    dateModified: modified, dateAdded: added,
                    codec: codec, sampleRate: 44_100, bitrate: kbps, channels: 2,
                    hasPicture: true, hasLyrics: t == 0, available: true)
                tracks.append(track)
                covers[uid] = cover
                uid += 1
            }
        }
        var favorites: [Int64: Int64] = [:]
        var stats: [Int64: PlayStats] = [:]
        for t in tracks {
            if t.uid % 9 == 0 { favorites[t.uid] = (now - t.uid) * 1000 }
            if t.uid % 3 != 0 {
                let plays: Int = Int(t.uid % 29) + 1
                let last: Int64 = (now - t.uid * 60) * 1000
                let first: Int64 = (now - 9_000_000) * 1000
                stats[t.uid] = PlayStats(trackUid: t.uid, playCount: plays, lastPlayedAt: last, firstPlayedAt: first, totalListenedMs: 300_000)
            }
        }
        var playlists: [Playlist] = []
        for p in 0..<40 {
            var entries: [PlaylistEntry] = []
            for i in 0..<60 {
                let entryId: Int64 = Int64(p * 100 + i + 1)
                let slot: Int = (p * 53 + i * 17) % tracks.count
                let addedAt: Int64 = now * 1000
                entries.append(PlaylistEntry(entryId: entryId, trackUid: Int64(slot + 1), position: i, addedAt: addedAt))
            }
            let created: Int64 = (now - Int64(p) * 86_400) * 1000
            let updated: Int64 = (now - Int64(p) * 3_600) * 1000
            let name: String = "Playlist \(words[p % words.count]) \(p + 1)"
            playlists.append(Playlist(id: Int64(p + 1), name: name, createdAt: created, updatedAt: updated, entries: entries))
        }
        return (tracks, covers, favorites, stats, playlists)
    }

    // MARK: - Ablauf

    @MainActor
    static func run(model: AppModel) {
        // Wie eine App im Vordergrund messen: ohne App Nap (sonst bündelt macOS Zeitgeber und alle Wartezeiten
        // werden künstlich länger)
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Messlauf")
        Task { @MainActor in
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            await runAll(model)
            NSApp.terminate(nil)
        }
    }

    private static var activity: NSObjectProtocol?

    /// Rechenzeit des aufrufenden Threads (Hauptthread) in Sekunden.
    static func threadCPUSeconds() -> Double {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let port = mach_thread_self()
        defer { mach_port_deallocate(mach_task_self_, port) }
        let kr: kern_return_t = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { thread_info(port, thread_flavor_t(THREAD_BASIC_INFO), $0, &count) }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let user: Double = Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1e6
        let system: Double = Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1e6
        return user + system
    }

    /// Rechenzeit des ganzen Prozesses (alle Threads) in Sekunden.
    static func processCPUSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user: Double = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
        let system: Double = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
        return user + system
    }

    /// Auslastung im Leerlauf: Anteil der Zeit, die der Hauptthread bzw. der ganze Prozess rechnet (Prozent).
    @MainActor
    static func idleLoad(window: NSWindow, seconds: Double) async -> (main: Double, process: Double) {
        let wall0 = CACurrentMediaTime()
        let main0 = threadCPUSeconds()
        let proc0 = processCPUSeconds()
        while CACurrentMediaTime() - wall0 < seconds {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let wall: Double = CACurrentMediaTime() - wall0
        let main: Double = (threadCPUSeconds() - main0) / wall * 100
        let process: Double = (processCPUSeconds() - proc0) / wall * 100
        return (main, process)
    }

    @MainActor
    private static func runAll(_ model: AppModel) async {
        let out = outputDirectory
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var results: [Measurement] = []
        var notes: [String] = []
        let runStart = CACurrentMediaTime()
        func record(_ name: String, _ samples: [Double]) {
            let m = Measurement(name: name, samples: samples)
            results.append(m)
            // Zwischenstand (Fortschritt und Zeitpunkt – für Profilaufnahmen und abgebrochene Läufe)
            print(String(format: "[Messlauf] %6.1f s  %@: Ø %.1f ms, p95 %.1f ms", CACurrentMediaTime() - runStart, name, m.mean, m.p95))
            fflush(stdout)
            write(results, notes: notes + ["(Zwischenstand)"], to: out, quiet: true)
        }

        // 1. Reine Logik (Hintergrund, nicht im Hauptthread – hier zur Einordnung)
        let tracks = model.index.tracks
        var t0 = CACurrentMediaTime()
        let idx = LibraryIndex.build(tracks)
        record("Index aufbauen (\(tracks.count) Titel)", [(CACurrentMediaTime() - t0) * 1000])
        t0 = CACurrentMediaTime()
        _ = AppModel.computeLists(index: idx, settings: model.settings, stats: model.stats, favorites: model.favoriteTracks,
                                  favoriteAlbums: model.favoriteAlbums, playlists: model.playlists, queries: [:])
        record("Alle Listen berechnen (Hintergrund)", [(CACurrentMediaTime() - t0) * 1000])
        var searchSamples: [Double] = []
        for q in ["licht", "nacht stadt", "blue", "a", "zzz"] {
            t0 = CACurrentMediaTime()
            _ = AppModel.computeLists(index: idx, settings: model.settings, stats: model.stats, favorites: model.favoriteTracks,
                                      favoriteAlbums: model.favoriteAlbums, playlists: model.playlists, queries: [.tracks: q, .albums: q])
            searchSamples.append((CACurrentMediaTime() - t0) * 1000)
        }
        record("Suche berechnen (Hintergrund)", searchSamples)

        // 2. Fenster
        for w in NSApp.windows { w.orderOut(nil) }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let size = CGSize(width: 1280, height: 820)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: ThemedRoot(model: model) { MainWindow() }.frame(width: size.width, height: size.height))
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(size)
        window.center()
        window.makeKeyAndOrderFront(nil)
        model.recomputeLists()
        await settle(window, seconds: 2.5)

        /// Zeit bis die Änderung aktualisiert, ausgelegt und gezeichnet ist (Hauptthread).
        func measureChange(_ change: () -> Void) async -> Double {
            let start = CACurrentMediaTime()
            change()
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            // zweiter Durchlauf: SwiftUI verteilt Aktualisierungen oft auf den nächsten Runloop-Durchgang
            await Task.yield()
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            return (CACurrentMediaTime() - start) * 1000
        }

        // 3. Bereiche wechseln (zweimal: kalt und warm)
        var sectionSamples: [Double] = []
        for _ in 0..<2 {
            for s in LibrarySection.allCases {
                sectionSamples.append(await measureChange { model.select(s) })
                await settle(window, seconds: 0.6)
            }
        }
        record("Bereich wechseln", sectionSamples)

        // 4. Ansichten wechseln und scrollen (Titel, Alben, Interpreten)
        let contexts: [(LibrarySection, LibraryViewContext)] = [(.tracks, .tracks), (.albums, .albums), (.artists, .artists), (.genres, .genres)]
        for (section, ctx) in contexts {
            model.select(section)
            await settle(window, seconds: 0.8)
            let original = model.viewOptions(ctx)
            for mode in LibraryViewMode.allCases {
                var o = original
                o.mode = mode
                let switchMs = await measureChange { model.setViewOptions(o, for: ctx) }
                record("\(ctx.label): Ansicht „\(mode.label)“ öffnen", [switchMs])
                await settle(window, seconds: 1.2)
                if mode != .coverFlow {
                    let samples = await scrollSamples(window: window, steps: 60, step: 360)
                    if samples.isEmpty {
                        notes.append("\(ctx.label)/\(mode.label): keine Scrollfläche gefunden")
                    } else {
                        record("\(ctx.label) · \(mode.label): Scrollschritt", samples)
                    }
                }
            }
            model.setViewOptions(original, for: ctx)
            await settle(window, seconds: 0.5)
        }

        // 5. Suche eintippen (Hauptthread-Anteil inkl. Neuzeichnen)
        model.select(.tracks)
        await settle(window, seconds: 0.8)
        var typing: [Double] = []
        var text = ""
        for ch in "nacht licht" {
            text.append(ch)
            let q = text
            typing.append(await measureChange { model.setQuery(.tracks, q) })
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
        try? await Task.sleep(nanoseconds: 600_000_000)
        typing.append(await measureChange { })
        record("Suche tippen (je Taste, Hauptthread)", typing)
        model.setQuery(.tracks, "")
        await settle(window, seconds: 0.8)

        // 6. Player öffnen/schließen
        model.player.setDemoState(queueUids: Array(1...40), currentIndex: 0, positionMs: 30_000, playing: true)
        await settle(window, seconds: 0.8)
        var playerSamples: [Double] = []
        for theme in PlayerTheme.allCases {
            model.settings.playerTheme = theme
            playerSamples.append(await measureChange { model.playerOpen = true })
            await settle(window, seconds: 1.0)
            playerSamples.append(await measureChange { model.playerOpen = false })
            await settle(window, seconds: 0.6)
        }
        record("Player öffnen/schließen (alle Designs)", playerSamples)

        // 7. Leerlauf bei laufender Wiedergabe (Mini-Player mit drehender Platte + Liste sichtbar)
        model.settings.playerTheme = .vinylStudio
        model.playerOpen = false
        await settle(window, seconds: 1.0)
        let idle = await frameSamples(window: window, seconds: 3)
        record("Leerlauf mit Wiedergabe: Verspätung je Bild", idle)
        let load = await idleLoad(window: window, seconds: 4)
        record("Leerlauf mit Wiedergabe: Hauptthread belegt [%]", [load.main])
        record("Leerlauf mit Wiedergabe: Prozess-CPU [%]", [load.process])
        // 8. Großer Player offen (Vinyl dreht sich)
        model.playerOpen = true
        await settle(window, seconds: 1.5)
        let playerLoad = await idleLoad(window: window, seconds: 4)
        record("Großer Player (Vinyl) läuft: Hauptthread belegt [%]", [playerLoad.main])
        record("Großer Player (Vinyl) läuft: Prozess-CPU [%]", [playerLoad.process])
        model.playerOpen = false
        await settle(window, seconds: 0.8)

        window.orderOut(nil)
        write(results, notes: notes, to: out)
    }

    /// Wartet, bis Hintergrundarbeit (Listen, Cover) erledigt ist und gezeichnet wurde.
    @MainActor
    private static func settle(_ window: NSWindow, seconds: Double) async {
        let end = CACurrentMediaTime() + seconds
        while CACurrentMediaTime() < end {
            try? await Task.sleep(nanoseconds: 50_000_000)
            window.displayIfNeeded()
        }
    }

    /// Größte Scrollfläche des Fensters in Schritten bewegen; je Schritt die Zeit für Layout + Zeichnen.
    @MainActor
    private static func scrollSamples(window: NSWindow, steps: Int, step: CGFloat) async -> [Double] {
        guard let root = window.contentView, let scroll = largestScrollView(in: root) else { return [] }
        let clip = scroll.contentView
        let docHeight = scroll.documentView?.frame.height ?? 0
        var samples: [Double] = []
        var y = clip.bounds.origin.y
        for _ in 0..<steps {
            y += step
            if y > docHeight - clip.bounds.height { y = 0 }
            let start = CACurrentMediaTime()
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
            scroll.reflectScrolledClipView(clip)
            root.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            samples.append((CACurrentMediaTime() - start) * 1000)
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
        return samples
    }

    @MainActor
    private static func largestScrollView(in view: NSView) -> NSScrollView? {
        var best: NSScrollView?
        var bestArea: CGFloat = 0
        func visit(_ v: NSView) {
            if let s = v as? NSScrollView, !s.isHidden {
                let area = s.frame.width * s.frame.height
                let scrollable = (s.documentView?.frame.height ?? 0) > s.contentView.bounds.height + 50
                if scrollable && area > bestArea {
                    best = s
                    bestArea = area
                }
            }
            for sub in v.subviews { visit(sub) }
        }
        visit(view)
        return best
    }

    /// Abstände der Hauptthread-Takte über einige Sekunden (zeigt Ruckler durch zu häufiges Neuzeichnen).
    @MainActor
    private static func frameSamples(window: NSWindow, seconds: Double) async -> [Double] {
        var samples: [Double] = []
        var last = CACurrentMediaTime()
        let end = last + seconds
        while CACurrentMediaTime() < end {
            try? await Task.sleep(nanoseconds: 16_000_000)
            window.displayIfNeeded()
            let now = CACurrentMediaTime()
            samples.append((now - last) * 1000 - 16)
            last = now
        }
        return samples.map { max(0, $0) }
    }

    private static func write(_ results: [Measurement], notes: [String], to dir: URL, quiet: Bool = false) {
        let info: [String: Any] = [
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "architecture": AboutArchitecture.current,
            "cpu": cpuName(),
            "tracks": trackCount,
            "liquidGlass": LiquidGlass.isAvailable,
            "notes": notes,
            "results": results.map { ["name": $0.name, "mean_ms": round2($0.mean), "p95_ms": round2($0.p95), "max_ms": round2($0.max), "n": $0.samples.count] as [String: Any] },
        ]
        if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("benchmark.json"))
        }
        var text = "Music Library – Messlauf mit \(trackCount) Titeln\n\(ProcessInfo.processInfo.operatingSystemVersionString) · \(AboutArchitecture.current) · \(cpuName())\n\n"
        text += "Messung".padding(toLength: 58, withPad: " ", startingAt: 0) + "  Mittel     p95     Max   (ms bzw. %)\n"
        for r in results {
            text += r.name.padding(toLength: 58, withPad: " ", startingAt: 0)
            text += String(format: "%8.1f %8.1f %8.1f\n", r.mean, r.p95, r.max)
        }
        if !notes.isEmpty { text += "\nHinweise:\n" + notes.map { "- " + $0 }.joined(separator: "\n") + "\n" }
        try? text.write(to: dir.appendingPathComponent("benchmark.txt"), atomically: true, encoding: .utf8)
        if !quiet { print(text) }
    }

    private static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    private static func cpuName() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "?" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
}
