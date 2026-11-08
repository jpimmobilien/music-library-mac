import Foundation
import AppKit
import MLCore
import MLStore
import MLStudio

// Feste Ersatzdienste für Vorschaubilder (Demo-Modus): keine Datei- und Netzwerkzugriffe.
// Dazu erfundene Demo-Werte (Wellenform, Quellen, Aufträge, Verlauf, Werkzeuge) für die Szenarien „60-studio-*“.

extension StudioServiceSet {
    static var demo: StudioServiceSet {
        let s = DemoStudioService()
        return StudioServiceSet(exporter: s, waveforms: s, local: s, remote: s, tools: s)
    }
}

struct DemoStudioService: AudioExporting, WaveformProviding, LocalSourceAnalyzing, RemoteSourceProviding, StudioToolManaging {
    func export(_ request: ExportRequest, pause: PauseGate?, progress: @escaping @Sendable (Double) -> Void) async throws -> ExportResult {
        throw StudioError.other("Im Vorschaumodus nicht verfügbar.")
    }
    func waveform(for file: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> WaveformData {
        throw StudioError.other("Im Vorschaumodus nicht verfügbar.")
    }
    func analyze(file: URL) async throws -> SourceInfo { throw StudioError.other("Im Vorschaumodus nicht verfügbar.") }
    func analyze(url: URL, kind: SourceKind) async throws -> SourceInfo { throw StudioError.other("Im Vorschaumodus nicht verfügbar.") }
    func download(_ source: SourceInfo, into directory: URL, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL {
        throw StudioError.other("Im Vorschaumodus nicht verfügbar.")
    }
    func thumbnail(for source: SourceInfo) async -> Data? { nil }
    func status() async -> StudioToolStatus { StudioToolStatus() }
    func installOrUpdate(progress: @escaping @Sendable (ToolInstallProgress) -> Void) async throws -> StudioToolStatus {
        throw StudioError.other("Im Vorschaumodus nicht verfügbar.")
    }
    func removeManaged() async throws -> StudioToolStatus { StudioToolStatus() }
}

// MARK: - Demo-Werte

/// Erfundene Werte für die Vorschaubilder des Audio Studios. Alle Titel, Kanäle und Adressen sind ausgedacht.
@MainActor
enum StudioDemo {
    /// Feste Dubletten (nur im Demo-Modus angezeigt).
    static var duplicates: [DuplicateCheck.Candidate]?
    /// Rückfrage zu Dubletten gleich geöffnet zeigen.
    static var askDuplicates = false
    /// Reiter der Warteschlangen-Spalte beim Öffnen.
    static var queueTab: StudioQueueTab?

    // MARK: Wellenform

    private static var waveCache: [String: WaveformData] = [:]

    /// Musikähnliche Hüllkurve: Intro, Strophe, Refrain, Bridge, Schluss; Schläge bei 120 BPM; deterministisch.
    static func waveform(duration: Double, seed: UInt64 = 7) -> WaveformData {
        let key = "\(duration)-\(seed)"
        if let w = waveCache[key] { return w }
        let rate = 44_100.0
        let fpb = 256
        let count = Int(duration * rate / Double(fpb))
        var rng = seed &* 6364136223846793005 &+ 1442695040888963407
        func random() -> Double {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Double(rng >> 11) / Double(1 << 53)
        }
        // (Ende in Anteilen der Dauer, Lautstärke)
        let sections: [(Double, Double)] = [(0.06, 0.32), (0.22, 0.52), (0.28, 0.62), (0.43, 0.9), (0.58, 0.55), (0.73, 0.94), (0.82, 0.42), (0.96, 1.0), (1.0, 0.25)]
        var mins = [Float](repeating: 0, count: count)
        var maxs = [Float](repeating: 0, count: count)
        var smooth = 0.3
        for i in 0..<count {
            let t = Double(i * fpb) / rate
            let p = t / duration
            var level = sections.first(where: { p <= $0.0 })?.1 ?? 0.5
            if p < 0.06 { level *= 0.5 + 0.5 * (p / 0.06) }
            if p > 0.96 { level *= max(0, (1 - p) / 0.04) }
            smooth += (level - smooth) * 0.002
            let beat = t.truncatingRemainder(dividingBy: 0.5)
            let kick = 0.72 + 0.28 * exp(-beat / 0.07)
            let offbeat = 0.94 + 0.06 * sin(t * .pi * 8)
            let jitter = 0.78 + 0.22 * random()
            let amp = min(1, smooth * kick * offbeat * jitter)
            maxs[i] = Float(amp)
            mins[i] = Float(-amp * (0.86 + 0.14 * random()))
        }
        let w = WaveformData(base: mins, maxs: maxs, framesPerBucket: fpb, sampleRate: rate, duration: duration)
        waveCache[key] = w
        return w
    }

    // MARK: Bilder

    private static var imageCache: [String: Data] = [:]

    /// Quadratisches Cover eines Demo-Albums (JPEG).
    static func cover(album index: Int) -> Data? {
        let key = "cover-\(index)"
        if let d = imageCache[key] { return d }
        let spec = DemoLibrary.albums[index % DemoLibrary.albums.count]
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("StudioDemoCover-\(ProcessInfo.processInfo.processIdentifier)-\(index).png").path
        DemoLibrary.writeCover(spec, index: index, to: path)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let image = NSImage(data: data),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let jpeg = NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.88])
        imageCache[key] = jpeg
        return jpeg
    }

    /// Vorschaubild im Format 16:9 (wie bei Videoportalen): Verlauf in den Albumfarben, Cover links, Lichtkreise.
    static func videoThumbnail(album index: Int) -> Data? {
        let key = "thumb-\(index)"
        if let d = imageCache[key] { return d }
        let spec = DemoLibrary.albums[index % DemoLibrary.albums.count]
        guard let coverData = cover(album: index), let coverImage = NSImage(data: coverData),
              let coverCG = coverImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = 1280, h = 720
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let c1 = NSColor(argb: spec.colors.0).cgColor
        let c2 = NSColor(argb: spec.colors.1).cgColor
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [c2, c1] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: CGFloat(w), y: CGFloat(h)), options: [])
        for i in 0..<5 {
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.05 + 0.025 * CGFloat(i)).cgColor)
            let r = CGFloat(90 + i * 46)
            ctx.fillEllipse(in: CGRect(x: 980 - r, y: 380 - r, width: 2 * r, height: 2 * r))
        }
        ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.draw(coverCG, in: CGRect(x: 110, y: 110, width: 500, height: 500))
        guard let image = ctx.makeImage() else { return nil }
        let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        imageCache[key] = jpeg
        return jpeg
    }

    // MARK: Quellen

    static func youtubeSource() -> SourceInfo {
        var meta = StudioMetadata(title: "Stadt aus Glas", artist: "Lina Sommer", album: "Nachtlichter", year: 2023, genre: "Pop")
        meta.cover = nil
        return SourceInfo(id: "demo-youtube-1", kind: .youtube, url: URL(string: "https://www.youtube.com/watch?v=Beispiel01")!,
                          title: "Lina Sommer – Stadt aus Glas (Official Video)", uploader: "Lina Sommer", duration: 212.4,
                          thumbnail: videoThumbnail(album: 0), suggested: meta, codec: "mp4a.40.2", bitrateKbps: 129,
                          sampleRate: 44_100, channels: 2, isLossless: false, fileSize: 3_480_000)
    }

    static func localWavSource() -> SourceInfo {
        let url = URL(fileURLWithPath: "/Demo/Aufnahmen/Proberaum – Sternstaub (Take 3).wav")
        return SourceInfo(id: "demo-file-1", kind: .localFile, url: url, title: "Proberaum – Sternstaub (Take 3)", uploader: nil, duration: 248.6,
                          suggested: StudioMetadata(title: "Sternstaub (Take 3)", artist: "Lina Sommer", album: "Proberaum", year: 2026, genre: "Pop"),
                          codec: "lpcm", bitrateKbps: 2304, sampleRate: 48_000, bitDepth: 24, channels: 2, isLossless: true,
                          fileSize: 71_600_000, localFile: url)
    }

    static func spotifySource() -> SourceInfo {
        SourceInfo(id: "demo-spotify-1", kind: .spotify, url: URL(string: "https://open.spotify.com/track/Beispiel")!,
                   title: "Static Bloom", uploader: "VELVET//MACHINE", thumbnail: cover(album: 7),
                   suggested: StudioMetadata(title: "Static Bloom", artist: "VELVET//MACHINE"))
    }

    /// Titel der Demo-Bibliothek zum Schneiden (Standard: „Salt & Silver“, AAC in M4A – ohne Neukodierung schneidbar).
    static func libraryTrackSource(_ model: AppModel, uid: Int64 = 9) -> SourceInfo? {
        guard let t = model.track(uid) else { return nil }
        let url = URL(fileURLWithPath: t.path)
        let meta = StudioMetadata(title: t.displayTitle, artist: t.artistText ?? "", album: t.album ?? "", albumArtist: t.albumArtistText ?? "",
                                  year: t.year, genre: t.genres.first ?? "", trackNumber: t.trackNumber)
        return SourceInfo(id: "library-\(uid)", kind: .localFile, url: url, title: t.displayTitle, uploader: t.artistText,
                          duration: Double(t.durationMs) / 1000, suggested: meta, codec: t.codec, bitrateKbps: t.bitrate,
                          sampleRate: t.sampleRate, bitDepth: t.bitsPerSample > 0 ? t.bitsPerSample : nil, channels: t.channels,
                          isLossless: t.codec == "ALAC", fileSize: t.sizeBytes, localFile: url, libraryUid: uid)
    }

    /// Gleichbleibende Prüfzahl eines Textes (`hashValue` wechselt von Start zu Start).
    static func stableHash(_ text: String) -> Int {
        text.unicodeScalars.reduce(17) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
    }

    // MARK: Aufträge und Verlauf

    static func jobs() -> [StudioJob] {
        func job(_ title: String, _ artist: String, album: Int, kind: SourceKind, format: StudioFormat, phase: JobPhase,
                 progress: Double = 0, detail: String? = nil, error: String? = nil, minutesAgo: Double = 0) -> StudioJob {
            let src = SourceInfo(id: "job-\(title)", kind: kind, url: URL(string: "https://soundcloud.com/beispiel/\(stableHash(title))")!,
                                 title: "\(artist) – \(title)", uploader: artist, duration: 190,
                                 thumbnail: kind == .soundcloud ? cover(album: album) : videoThumbnail(album: album))
            var j = StudioJob(source: src, options: ExportOptions.defaults(for: format), trim: nil,
                              metadata: StudioMetadata(title: title, artist: artist, cover: cover(album: album)),
                              fileName: "\(artist) – \(title)", destination: .library(folderID: 1, folderPath: "/Demo/Musik", subfolder: "Audio Studio"),
                              created: Date().addingTimeInterval(-minutesAgo * 60))
            j.phase = phase
            j.progress = progress
            j.detail = detail
            j.error = error
            if phase == .done { j.outputPath = "/Demo/Musik/Audio Studio/\(artist) – \(title).\(format.fileExtension)" }
            return j
        }
        return [
            job("Paper Boats", "The Harbor Lights", album: 1, kind: .youtube, format: .m4a, phase: .done, progress: 1, detail: "4,2 MB · 256 kbit/s", minutesAgo: 9),
            job("Velvet Rain", "Ella Marquez Trio", album: 2, kind: .soundcloud, format: .flac, phase: .converting, progress: 0.62, detail: "2:01 von 3:15", minutesAgo: 6),
            job("Frequenz", "Kraftfeld", album: 3, kind: .youtube, format: .mp3, phase: .downloading, progress: 0.35, detail: "2,6 MB von 7,4 MB · 1,8 MB/s", minutesAgo: 5),
            job("Kiesweg", "Clara Wendt", album: 6, kind: .youtube, format: .mp3, phase: .waiting, minutesAgo: 4),
            job("Highway 9", "Hank Morrow", album: 5, kind: .soundcloud, format: .wav, phase: .paused, progress: 0.4, minutesAgo: 3),
            job("Ghost Signal", "VELVET//MACHINE", album: 7, kind: .youtube, format: .m4a, phase: .failed, progress: 0.2,
                error: "Dieser Inhalt ist altersbeschränkt und erfordert eine Anmeldung – er wird nicht geladen.", minutesAgo: 2),
            job("Sunday Groove", "Marvin Day", album: 8, kind: .youtube, format: .aac, phase: .cancelled, minutesAgo: 1),
        ]
    }

    static func history() -> StudioHistory {
        let now = Date()
        func entry(_ title: String, _ artist: String, kind: SourceKind, format: String, hoursAgo: Double, imported: Bool = true,
                   succeeded: Bool = true, error: String? = nil, backup: String? = nil, undone: Bool = false, ext: String = "m4a") -> StudioHistoryEntry {
            var e = StudioHistoryEntry(date: now.addingTimeInterval(-hoursAgo * 3600), sourceKind: kind,
                                       source: kind == .localFile ? "/Demo/Musik/\(artist)/\(title).\(ext)" : "https://www.youtube.com/watch?v=\(stableHash(title))",
                                       title: title, artist: artist,
                                       outputPath: succeeded ? "/Demo/Musik/Audio Studio/\(artist) – \(title).\(ext)" : "",
                                       formatSummary: format, duration: 200, imported: imported, succeeded: succeeded, error: error, backupPath: backup)
            e.undone = undone
            return e
        }
        return StudioHistory(entries: [
            entry("Paper Boats", "The Harbor Lights", kind: .youtube, format: "M4A · 256 kbit/s · 44,1 kHz", hoursAgo: 0.15),
            entry("Stadt aus Glas", "Lina Sommer", kind: .localFile, format: "M4A · ohne Neukodierung", hoursAgo: 2.5,
                  backup: "/Demo/Sicherungen/Stadt aus Glas.m4a"),
            entry("Lighthouse Keeper", "The Harbor Lights", kind: .soundcloud, format: "MP3 · 320 kbit/s · 44,1 kHz", hoursAgo: 26, ext: "mp3"),
            entry("Café Noir", "Ella Marquez Trio", kind: .localFile, format: "FLAC · 24 Bit · Stufe 5 · 48 kHz", hoursAgo: 30, backup: "/Demo/Sicherungen/Café Noir.flac", undone: true, ext: "flac"),
            entry("Puls (Live)", "Kraftfeld", kind: .youtube, format: "MP3 · 256 kbit/s", hoursAgo: 49, imported: false, succeeded: false,
                  error: "Netzwerkfehler: Die Verbindung wurde unterbrochen."),
            entry("Bahnhof", "Clara Wendt", kind: .youtube, format: "WAV · 24 Bit · 48 kHz", hoursAgo: 75, imported: false, ext: "wav"),
        ])
    }

    static let readyTools = StudioToolStatus(
        ytDlpPath: StudioServiceSet.supportDirectory.appendingPathComponent("Tools/yt-dlp").path, ytDlpVersion: "2026.10.22", ytDlpOrigin: .managed,
        denoPath: StudioServiceSet.supportDirectory.appendingPathComponent("Tools/deno").path, denoVersion: "2.5.6", denoOrigin: .managed)

    static let partialTools = StudioToolStatus(ytDlpPath: "/opt/homebrew/bin/yt-dlp", ytDlpVersion: "2026.10.22", ytDlpOrigin: .system)

    // MARK: Zustände für Szenarien

    /// Alles auf Anfang (die Szenarien laufen nacheinander mit demselben Modell).
    static func reset(_ m: AppModel) {
        let s = m.studio!
        duplicates = nil
        askDuplicates = false
        queueTab = nil
        StudioScrollSeed.pending = nil
        // Ein Musikordner für die Ziel-Auswahl (nur in der Demo-Datenbank im Speicher)
        if m.folders.isEmpty {
            _ = try? m.store.addFolder(path: "/Demo/Musik", bookmark: nil, name: "Musik", volumeName: nil, isExternal: false)
            m.reloadFolders()
        }
        s.settings = StudioSettings()
        s.options = s.settings.options(for: .m4a)
        s.urlText = ""
        s.sourceState = .empty
        s.source = nil
        s.prepare = .notNeeded
        s.waveform = nil
        s.waveformProgress = nil
        s.selection = TrimRange(start: 0, end: 0)
        s.exportWholeFile = true
        s.zoom = 1
        s.visibleStart = 0
        s.playback.playing = false
        s.playback.playhead = 0
        s.metadata = StudioMetadata()
        s.customFileName = ""
        s.cutSaveMode = .newFile
        s.keepOriginalFormat = true
        s.fadeIn = 0
        s.fadeOut = 0
        s.jobs = []
        s.history = StudioHistory()
        s.toolStatus = readyTools
        s.toolInstall = .idle
        m.studioOpen = true
    }

    /// Quelle mit fertiger Wellenform und Auswahl.
    static func load(_ s: StudioModel, _ source: SourceInfo, selection: TrimRange? = nil, playhead: Double = 0) {
        s.source = source
        s.sourceState = .ready
        s.prepare = source.kind == .localFile ? .notNeeded : .ready
        s.waveform = waveform(duration: source.duration ?? 200, seed: UInt64(stableHash(source.id) % 97 + 3))
        var meta = source.suggested
        if meta.cover == nil, let thumb = source.thumbnail { meta.cover = StudioImages.squareCover(from: thumb) }
        s.metadata = meta
        if let selection {
            s.selection = selection
            s.exportWholeFile = false
        }
        s.playback.playhead = playhead
    }
}
