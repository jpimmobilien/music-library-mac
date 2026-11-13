import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import MLCore
import MLStudio
import StudioEngine

/// Zustand und Abläufe des Audio Studios (Version 2.2).
///
/// Vertrag zwischen Oberfläche und Verarbeitung: Die Ansichten lesen nur die veröffentlichten Werte und rufen
/// nur die Methoden unter „Aktionen“ auf. Alles Langsame (Analyse, Laden, Wellenform, Export) läuft in
/// Hintergrund-Tasks; der Hauptthread wird nie blockiert. Die Bibliothek, der Hauptplayer, EQ und Tonhöhe
/// werden nicht verändert – fertige Dateien kommen über das normale Einlesen in die Bibliothek.
@MainActor
final class StudioPlayback: ObservableObject {
    @Published var playing = false
    /// Abspielkopf in Sekunden.
    @Published var playhead: Double = 0
}

/// Hinweis zur Leistung: Häufige Änderungen (Fortschritt von Laden, Export, Wellenform) höchstens ~5× pro
/// Sekunde veröffentlichen – jede Änderung eines `@Published`-Werts lässt alle beobachtenden Ansichten neu auswerten.
@MainActor
final class StudioModel: ObservableObject {
    weak var app: AppModel?
    let services: StudioServiceSet
    let preview: StudioPreviewing?
    /// Demo-Modus (Vorschaubilder): keine Datei- und Netzwerkzugriffe.
    let demo: Bool

    // MARK: Einstellungen (gespeichert unter `StudioSettings.userDefaultsKey`)

    @Published var settings: StudioSettings {
        didSet { if settings != oldValue { saveSettings() } }
    }

    // MARK: Werkzeuge für Internet-Quellen

    enum ToolInstallState: Equatable {
        case idle
        case running(ToolInstallProgress)
        case failed(String)
    }

    @Published var toolStatus = StudioToolStatus()
    @Published var toolInstall: ToolInstallState = .idle

    // MARK: Quelle

    enum SourceState: Equatable {
        /// Noch nichts gewählt.
        case empty
        /// Analyse läuft (Text für die Anzeige, z. B. „YouTube wird abgefragt …“).
        case analyzing(String)
        /// Quelle bekannt (Metadaten). Für Internet-Quellen ist die Audiospur evtl. noch nicht geladen.
        case ready
        case failed(String)
    }

    /// Eingabefeld (eine oder mehrere Adressen, je Zeile eine).
    @Published var urlText = ""
    @Published var sourceState: SourceState = .empty
    @Published var source: SourceInfo?

    /// Laden der Audiospur einer Internet-Quelle zum Bearbeiten (nur auf Knopfdruck).
    enum PrepareState: Equatable {
        case notNeeded
        case needed
        case downloading(DownloadProgress)
        case ready
        case failed(String)
    }

    @Published var prepare: PrepareState = .notNeeded

    // MARK: Editor

    @Published var waveform: WaveformData?
    /// Fortschritt der Wellenform-Berechnung (nil = keine Berechnung).
    @Published var waveformProgress: Double?
    /// Gewählter Ausschnitt in Sekunden (ganze Datei = 0…Dauer).
    @Published var selection: TrimRange = TrimRange(start: 0, end: 0)
    /// true = ganze Datei exportieren (Auswahl wird ignoriert).
    @Published var exportWholeFile = true
    /// Zoom: 1 = ganze Datei sichtbar, 2 = halbe Länge … (max. so, dass ~0,5 s die Breite füllen).
    @Published var zoom: Double = 1
    /// Linker Rand des sichtbaren Bereichs in Sekunden.
    @Published var visibleStart: Double = 0
    /// Vorhören: eigenes Objekt, damit der Abspielkopf (~30×/s) nur die Wellenform neu zeichnet und nicht
    /// das ganze Studio.
    let playback = StudioPlayback()

    // MARK: Export der aktuellen Quelle

    @Published var options: ExportOptions = .defaults(for: .m4a)
    @Published var metadata = StudioMetadata()
    @Published var customFileName = ""

    // MARK: Schneiden vorhandener Songs (Quelle aus der Bibliothek, `source.libraryUid != nil`)

    enum CutSaveMode: String, CaseIterable {
        /// Als neue Datei neben dem Original speichern (Standard, nichts wird überschrieben).
        case newFile
        /// Original ersetzen – nach Sicherung, mit Bestätigung und „Rückgängig“ im Verlauf.
        case replaceOriginal
    }

    @Published var cutSaveMode: CutSaveMode = .newFile {
        didSet {
            // Ersetzen geht nur im Format des Originals (der Pfad und damit die Endung bleiben gleich).
            if cutSaveMode == .replaceOriginal, oldValue != .replaceOriginal, !keepOriginalFormat { keepOriginalFormat = true }
        }
    }
    /// Format und Qualität des Originals behalten; MP3/M4A dann ohne Neukodierung, wenn möglich.
    @Published var keepOriginalFormat = true {
        didSet {
            guard keepOriginalFormat != oldValue else { return }
            if keepOriginalFormat {
                applyOriginalFormat()
            } else if cutSaveMode == .replaceOriginal {
                cutSaveMode = .newFile
            }
        }
    }
    /// Ein-/Ausblenden in Sekunden (0 = aus; erzwingt Neukodierung).
    @Published var fadeIn: Double = 0
    @Published var fadeOut: Double = 0

    var isLibraryTrack: Bool { source?.libraryUid != nil }

    // MARK: Titel bearbeiten (2.3, siehe StudioTrackEdit.swift)

    enum StudioMode: String { case convert, edit }
    /// „Bearbeiten“: eigene Ansicht mit Lautstärke, Tempo, Tonhöhe, Stimmung, Equalizer, Auto-Tune und Verbesserung.
    @Published var mode: StudioMode = .convert
    @Published var trackEdit = TrackEdit() {
        didSet { if trackEdit != oldValue { trackEditChanged() } }
    }
    /// Analyse des Titels (Stimmung, Tonart, Lautheit) – nil, solange sie läuft.
    @Published var trackAnalysis: TrackAnalysis?
    @Published var trackAnalysisProgress: Double?
    /// Vorhören: bearbeitet (true) oder Original (false).
    @Published var previewEdited = true {
        didSet { if previewEdited != oldValue { pushPreviewEdit(immediately: true) } }
    }
    var trackAnalysisTask: Task<Void, Never>?
    var previewEditTask: Task<Void, Never>?
    /// Nach dem Laden des Titels in den Bearbeitungsmodus wechseln.
    var opensInEditMode = false
    /// Stimmung und Tonart vom Nutzer gewählt (dann nicht mehr aus der Analyse übernehmen).
    var tuningTouched = false
    var keyTouched = false

    // MARK: Warteschlange und Verlauf

    @Published var jobs: [StudioJob] = []
    @Published var history = StudioHistory()

    // MARK: Laufzeit (nicht veröffentlicht)

    /// Ordner für Werkzeuge, Zwischenspeicher, Sicherungen und Verlauf.
    let supportDirectory: URL
    let defaults: UserDefaults
    /// Ersatz für `app` (Tests).
    let libraryOverride: StudioLibraryAccess?
    var lib: StudioLibraryAccess? {
        if let libraryOverride { return libraryOverride }
        return app
    }

    var cacheRoot: URL { supportDirectory.appendingPathComponent("Cache", isDirectory: true) }
    var backupsRoot: URL { supportDirectory.appendingPathComponent("Backups", isDirectory: true) }
    var historyURL: URL { supportDirectory.appendingPathComponent("history.json") }

    private var observers: [AnyCancellable] = []
    private var sourceTask: Task<Void, Never>?
    private var prepareTask: Task<Void, Never>?
    private var waveformTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?
    private var toolTask: Task<Void, Never>?
    /// Zwischenspeicher der aktuell bearbeiteten Internet-Quelle.
    private var editCacheDir: URL?
    private var previewLoadedFile: URL?
    private var playheadTask: Task<Void, Never>?
    /// Ende des laufenden Vorhörbereichs (nil = Dateiende).
    private var previewEnd: Double?
    private var toolsChecked = false
    /// Zählt jede neue Quelle hoch – Ergebnisse älterer Abfragen werden verworfen.
    private(set) var sourceGeneration = 0

    // Warteschlange (siehe StudioQueueRunner.swift)
    var runningJobID: UUID?
    var jobTasks: [UUID: Task<Void, Never>] = [:]
    var jobGates: [UUID: PauseGate] = [:]
    /// Laden angehalten (Prozess beendet, Teil-Datei bleibt) – kein Abbruch.
    var pauseRequested: Set<UUID> = []
    /// Aufträge aus mehreren Adressen, Playlists oder Dateien: Quelle wird erst beim Start abgefragt.
    var pendingAnalysis: Set<UUID> = []
    var historyLoaded = false
    /// Ergebnisse seit die Warteschlange zuletzt leer war (für die Mitteilung am Ende).
    var queueRun = StudioQueueRun()

    // Doppel-Erkennung
    private var dupIndex: StudioDuplicateIndex?
    private var dupIndexBuilding = false
    private var dupGeneration = 0

    /// Für Dateiarbeiten des Verlaufs und des Zwischenspeichers (Reihenfolge bleibt erhalten).
    nonisolated static let ioQueue = DispatchQueue(label: "MusicLibrary.AudioStudio.io", qos: .utility)

    init(app: AppModel?, services: StudioServiceSet, preview: StudioPreviewing?, demo: Bool,
         library: StudioLibraryAccess? = nil, supportDirectory: URL? = nil, defaults: UserDefaults = .standard) {
        self.app = app
        self.services = services
        self.preview = preview
        self.demo = demo
        self.libraryOverride = library
        self.supportDirectory = supportDirectory ?? StudioServiceSet.supportDirectory
        self.defaults = defaults
        self.settings = demo ? StudioSettings() : StudioSettings.decode(defaults.data(forKey: StudioSettings.userDefaultsKey))
        self.options = settings.options(for: settings.lastFormat)
        guard !demo else { return }
        startUp()
    }

    private func saveSettings() {
        guard !demo, let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: StudioSettings.userDefaultsKey)
    }

    /// Beobachter, Aufräumen alter Reste, Verlauf laden.
    private func startUp() {
        observers = lib?.studioObserve(libraryChanged: { [weak self] in self?.libraryDidChange() },
                                       visibilityChanged: { [weak self] open in self?.studioVisibilityChanged(open) }) ?? []
        // Reste einer früheren Sitzung (Zwischenspeicher, angefangene Downloads) löschen – die Warteschlange wird
        // nicht gespeichert, sie werden also nicht mehr gebraucht. Erst umbenennen (sofort), dann im Hintergrund
        // löschen, damit neue Aufträge nie in einen Ordner schreiben, der gerade gelöscht wird.
        let cache = cacheRoot
        let support = supportDirectory
        let fm = FileManager.default
        if fm.fileExists(atPath: cache.path) {
            try? fm.moveItem(at: cache, to: support.appendingPathComponent(".Cache-alt-\(UUID().uuidString)", isDirectory: true))
        }
        Self.ioQueue.async {
            let items = (try? FileManager.default.contentsOfDirectory(at: support, includingPropertiesForKeys: nil, options: [])) ?? []
            for item in items where item.lastPathComponent.hasPrefix(".Cache-alt-") { try? FileManager.default.removeItem(at: item) }
        }
        loadHistory()
        // Beim Beenden: laufende Hilfsprogramme beenden und den Zwischenspeicher leeren.
        let token = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            StudioProcess.terminateAll()
            try? FileManager.default.removeItem(at: cache)
        }
        observers.append(AnyCancellable { NotificationCenter.default.removeObserver(token) })
    }

    private func libraryDidChange() {
        dupIndex = nil
        dupGeneration += 1
        dupIndexBuilding = false
    }

    private func studioVisibilityChanged(_ open: Bool) {
        if open {
            if !toolsChecked { refreshToolStatus() }
        } else {
            stopPreview()
        }
    }

    // MARK: - Abgeleitete Werte (für die Oberfläche)

    var duration: Double { source?.duration ?? waveform?.duration ?? 0 }

    /// Effektiver Ausschnitt für den Export (nil = ganze Datei).
    var effectiveTrim: TrimRange? { exportWholeFile ? nil : selection.clamped(to: duration) }

    /// Dateiname ohne Endung nach aktuellem Schema. Beim Schneiden eines Bibliothekstitels:
    /// „<Original> (Ausschnitt)“ (bzw. der eigene Name).
    var fileNameBase: String {
        if isCustomScheme, !customFileName.studioTrimmed.isEmpty || !isLibraryTrack {
            return FileNameScheme.custom(customFileName).render(metadata, fallback: source?.title ?? "Audio")
        }
        if let source, source.libraryUid != nil {
            let original = (source.localFile ?? source.url).deletingPathExtension().lastPathComponent
            if cutSaveMode == .replaceOriginal { return FileNames.sanitize(original) }
            let suffix = mode == .edit ? " (bearbeitet)" : " (Ausschnitt)"
            let base = FileNames.sanitize(original + suffix)
            return base.isEmpty ? (mode == .edit ? "Bearbeitet" : "Ausschnitt") : base
        }
        return settings.fileNameScheme.render(metadata, fallback: source?.title ?? "Audio")
    }

    var isCustomScheme: Bool {
        if case .custom = settings.fileNameScheme { return true }
        return false
    }

    /// „Interpret – Titel.m4a“
    var fileNamePreview: String { fileNameBase + "." + options.format.fileExtension }

    /// Ehrliche Hinweise zur gewählten Qualität.
    var qualityNotes: [String] {
        QualityAdvice.notes(options: options, sourceLossless: source?.isLossless, sourceBitrate: source?.bitrateKbps,
                            sourceRate: source?.sampleRate, sourceBits: source?.bitDepth)
    }

    /// Standardordner für „nur speichern“ und als Rückfall ohne Musikordner: ~/Music/Audio Studio
    /// (gleicher Pfad wie `defaultSaveFolder` der Oberfläche).
    nonisolated static var standardSaveFolder: String {
        (NSHomeDirectory() as NSString).appendingPathComponent("Music/Audio Studio")
    }

    /// Ziel nach den Einstellungen: Musikordner der Bibliothek (gewählter oder erster), ohne Musikordner
    /// ~/Music/Audio Studio, bei „nur speichern“ der gewählte Ordner.
    var settingsDestination: StudioDestination {
        if settings.importToLibrary {
            let folders = (lib?.studioFolders ?? []).filter(\.enabled)
            if let folder = folders.first(where: { $0.id == settings.libraryFolderID }) ?? folders.first {
                return .library(folderID: folder.id, folderPath: folder.path, subfolder: settings.librarySubfolder)
            }
            return .folder(path: Self.standardSaveFolder)
        }
        return .folder(path: settings.saveFolderPath ?? Self.standardSaveFolder)
    }

    /// Ziel nach den Einstellungen (Bibliotheksordner oder freier Ordner). Beim Schneiden eines
    /// Bibliothekstitels: derselbe Ordner wie das Original bzw. „Original ersetzen“.
    var destination: StudioDestination? {
        guard let source, let uid = source.libraryUid else { return settingsDestination }
        let path = lib?.studioTrack(uid)?.path ?? (source.localFile ?? source.url).path
        if cutSaveMode == .replaceOriginal {
            guard let same = source.sameFormat, options.format == same else { return nil }
            return .replaceOriginal(uid: uid, path: path)
        }
        let dir = (path as NSString).deletingLastPathComponent
        let folderID = lib?.studioTrack(uid)?.folderID
        if let folder = lib?.studioFolders.first(where: { $0.id == folderID }) {
            let root = folder.path.hasSuffix("/") ? String(folder.path.dropLast()) : folder.path
            if dir == root || dir.hasPrefix(root + "/") {
                let sub = dir == root ? "" : String(dir.dropFirst(root.count + 1))
                let candidate = StudioDestination.library(folderID: folder.id, folderPath: folder.path, subfolder: sub)
                // Nur, wenn der Ordnername unverändert bleibt (Bereinigung könnte ihn sonst ändern)
                if candidate.directoryPath == dir { return candidate }
            }
        }
        return .folder(path: dir)
    }

    /// Mögliche Dubletten in der Bibliothek für die aktuelle Quelle (leer = keine).
    var duplicateCandidates: [DuplicateCheck.Candidate] {
        guard let source, let index = duplicateIndexIfReady() else { return [] }
        let title = metadata.title.studioTrimmed.isEmpty ? source.title : metadata.title
        var pool = index.byTitle[DuplicateCheck.normalize(title)] ?? []
        var targetPath: String?
        if let dest = destination, !dest.replacesOriginal {
            let path = dest.directoryPath + "/" + fileNameBase + "." + options.format.fileExtension
            targetPath = path
            if let c = index.byPath[path] { pool.append(c) }
        }
        let length = effectiveTrim?.length ?? source.duration
        var seen = Set<Int64>()
        return DuplicateCheck.matches(title: title, artist: metadata.artist, duration: length, targetPath: targetPath, in: pool)
            .filter { $0.uid != source.libraryUid && seen.insert($0.uid).inserted }
    }

    /// Diese Quelle wurde schon einmal erfolgreich exportiert (Doppel-Warnung „Quelle schon exportiert“).
    /// Gleiche Schlüssel wie `previousExport` der Oberfläche (Adresse bzw. Dateipfad).
    var previousExportEntry: StudioHistoryEntry? {
        guard let source else { return nil }
        return history.previousExport(of: Self.historyKey(source))
    }

    var canExport: Bool {
        guard let source, source.kind.supportsAudio, sourceState == .ready, destination != nil else { return false }
        return !source.isLive
    }

    /// Schlüssel einer Quelle im Verlauf: Adresse (Internet) bzw. Dateipfad.
    nonisolated static func historyKey(_ source: SourceInfo) -> String {
        if source.kind == .localFile || source.libraryUid != nil { return (source.localFile ?? source.url).path }
        return source.url.absoluteString
    }

    /// Index der Bibliothekstitel nach normalisiertem Titel – im Hintergrund aufgebaut, damit auch große
    /// Bibliotheken die Oberfläche nicht bremsen. Bis er fertig ist, gibt es keine Treffer.
    private func duplicateIndexIfReady() -> StudioDuplicateIndex? {
        if let dupIndex { return dupIndex }
        guard !dupIndexBuilding, let lib else { return nil }
        dupIndexBuilding = true
        let tracks = lib.studioTracks
        let generation = dupGeneration
        Task { [weak self] in
            let index = await Task.detached(priority: .utility) { StudioDuplicateIndex(tracks: tracks) }.value
            guard let self, generation == self.dupGeneration else { return }
            self.dupIndex = index
            self.dupIndexBuilding = false
            self.objectWillChange.send()
        }
        return nil
    }

    // MARK: - Aktionen: Quelle

    /// Text aus dem Eingabefeld analysieren (mehrere Zeilen = mehrere Aufträge mit gemeinsamen Einstellungen).
    func analyzeInput() {
        let parsed = Self.parseInput(urlText)
        if parsed.urls.isEmpty && parsed.files.isEmpty {
            guard !urlText.studioTrimmed.isEmpty else { return }
            resetForNewSource()
            sourceState = .failed(StudioError.unsupportedURL.errorDescription ?? "")
            return
        }
        if parsed.urls.isEmpty {
            importFiles(parsed.files)
            return
        }
        if parsed.urls.count == 1 && parsed.files.isEmpty {
            loadRemote(parsed.urls[0].url, kind: parsed.urls[0].kind)
            return
        }
        let remote = parsed.urls.map { SourceInfo(id: $0.url.absoluteString, kind: $0.kind, url: $0.url, title: Self.displayName($0.url)) }
        let files = parsed.files.map(Self.provisionalSource(file:))
        let added = enqueuePending(remote + files)
        if added > 0 {
            urlText = ""
            lib?.studioToast(added == 1 ? "1 Auftrag in die Warteschlange gelegt" : "\(added) Aufträge in die Warteschlange gelegt", action: nil, isError: false, perform: nil)
        }
    }

    /// Zwischenablage einfügen (Adresse oder Dateien) und analysieren.
    func pasteFromClipboard() {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            importFiles(urls)
            return
        }
        if let text = pb.string(forType: .string), !text.studioTrimmed.isEmpty {
            urlText = text.studioTrimmed
            analyzeInput()
            return
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            urlText = urls.map(\.absoluteString).joined(separator: "\n")
            analyzeInput()
            return
        }
        lib?.studioToast("Die Zwischenablage enthält keine Adresse und keine Datei.", action: nil, isError: true, perform: nil)
    }

    /// Dateien (Drag & Drop oder Öffnen-Dialog). Eine Datei → Editor; mehrere → Warteschlange.
    func importFiles(_ urls: [URL]) {
        let files = urls.filter { Self.isSupportedFile($0) }
        guard !files.isEmpty else {
            lib?.studioToast("Keine Audio- oder Videodatei gefunden.", action: nil, isError: true, perform: nil)
            return
        }
        if files.count == 1 {
            loadLocal(files[0])
        } else {
            let added = enqueuePending(files.map(Self.provisionalSource(file:)))
            lib?.studioToast("\(added) Dateien in die Warteschlange gelegt", action: nil, isError: false, perform: nil)
        }
    }

    /// „Öffnen …“-Dialog für lokale Audio- und Videodateien.
    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "Audio- oder Videodateien öffnen"
        panel.prompt = "Öffnen"
        panel.message = "Eine Datei öffnet den Editor, mehrere Dateien kommen in die Warteschlange."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = Self.openPanelTypes
        panel.begin { response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor [weak self] in self?.importFiles(urls) }
        }
    }

    /// Audiospur einer Internet-Quelle zum Bearbeiten laden (danach Wellenform).
    func prepareForEditing() {
        guard let source, source.kind != .localFile, source.libraryUid == nil else { return }
        guard source.kind.supportsAudio else {
            prepare = .failed(StudioError.spotifyDRM.errorDescription ?? "")
            return
        }
        if case .downloading = prepare { return }
        if let file = source.localFile, FileManager.default.fileExists(atPath: file.path) {
            prepare = .ready
            if waveform == nil { computeWaveform(file) }
            return
        }
        let generation = sourceGeneration
        let dir = editCacheDirectory()
        prepare = .downloading(DownloadProgress())
        prepareTask = Task { [weak self] in
            guard let self else { return }
            do {
                let file = try await self.services.remote.download(source, into: dir) { p in
                    Task { @MainActor [weak self] in
                        guard let self, generation == self.sourceGeneration, case .downloading = self.prepare else { return }
                        self.prepare = .downloading(p)
                    }
                }
                guard generation == self.sourceGeneration else { return }
                self.source?.localFile = file
                // Genaue Angaben (Codec, Abtastrate, Dauer) aus der geladenen Datei
                if let local = try? await self.services.local.analyze(file: file), generation == self.sourceGeneration {
                    self.mergeAudioDetails(from: local)
                }
                guard generation == self.sourceGeneration else { return }
                self.prepare = .ready
                self.computeWaveform(file)
            } catch {
                guard generation == self.sourceGeneration else { return }
                self.prepare = .failed(Self.message(error))
            }
        }
    }

    func clearSource() {
        resetForNewSource()
        sourceState = .empty
        urlText = ""
    }

    /// Titel aus der Bibliothek zum Schneiden öffnen (Kontextmenü „Im Audio Studio schneiden …“).
    func openLibraryTrack(_ uid: Int64) {
        guard let lib else { return }
        guard let track = lib.studioTrack(uid) else {
            lib.studioToast("Der Titel wurde in der Bibliothek nicht gefunden.", action: nil, isError: true, perform: nil)
            return
        }
        lib.studioShow()
        if !demo, !FileManager.default.fileExists(atPath: track.path) {
            resetForNewSource()
            sourceState = .failed("Die Datei ist nicht erreichbar – ist das Laufwerk angeschlossen?")
            return
        }
        loadLocal(URL(fileURLWithPath: track.path), libraryUid: uid, track: track)
    }

    // MARK: Quelle – intern

    private func loadRemote(_ url: URL, kind: SourceKind) {
        resetForNewSource()
        let generation = sourceGeneration
        sourceState = .analyzing(Self.analyzingText(kind, url: url))
        sourceTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.services.remote.lookup(url: url, kind: kind)
                guard generation == self.sourceGeneration else { return }
                switch result {
                case .single(let info):
                    self.showRemote(info)
                case .playlist(let title, let entries):
                    self.sourceState = .empty
                    let sources = entries.map { SourceInfo(id: $0.url.absoluteString, kind: SourceURL.classify($0.url.absoluteString)?.kind ?? kind,
                                                           url: $0.url, title: $0.title ?? Self.displayName($0.url), duration: $0.duration) }
                    let added = self.enqueuePending(sources)
                    self.urlText = ""
                    self.lib?.studioToast("\(added) Titel aus „\(title)“ in die Warteschlange gelegt", action: nil, isError: false, perform: nil)
                }
            } catch {
                guard generation == self.sourceGeneration else { return }
                self.sourceState = .failed(Self.message(error))
                if let e = error as? StudioError, case .toolMissing = e { self.refreshToolStatus() }
            }
        }
    }

    private func showRemote(_ info: SourceInfo) {
        source = info
        metadata = info.suggested
        if metadata.cover == nil, let thumb = info.thumbnail { metadata.cover = thumb }
        selection = TrimRange(start: 0, end: info.duration ?? 0)
        exportWholeFile = true
        if info.isLive {
            prepare = .notNeeded
            sourceState = .failed(StudioError.liveStream.errorDescription ?? "")
            return
        }
        prepare = info.kind.supportsAudio ? .needed : .notNeeded
        sourceState = .ready
        if info.thumbnail == nil, info.thumbnailURL != nil { loadThumbnail(for: info) }
    }

    private func loadThumbnail(for info: SourceInfo) {
        let generation = sourceGeneration
        thumbnailTask = Task { [weak self] in
            guard let self else { return }
            let data = await self.services.remote.thumbnail(for: info)
            guard generation == self.sourceGeneration, let data else { return }
            self.source?.thumbnail = data
            if self.metadata.cover == nil { self.metadata.cover = data }
        }
    }

    private func loadLocal(_ file: URL, libraryUid: Int64? = nil, track: Track? = nil) {
        resetForNewSource()
        let generation = sourceGeneration
        sourceState = .analyzing(libraryUid == nil ? "Datei wird gelesen …" : "Titel wird gelesen …")
        sourceTask = Task { [weak self] in
            guard let self else { return }
            do {
                var info = try await self.services.local.analyze(file: file)
                guard generation == self.sourceGeneration else { return }
                if info.localFile == nil { info.localFile = file }
                info.libraryUid = libraryUid
                self.showLocal(info, track: track)
            } catch {
                guard generation == self.sourceGeneration else { return }
                self.sourceState = .failed(Self.message(error))
            }
        }
    }

    private func showLocal(_ info: SourceInfo, track: Track?) {
        source = info
        var meta = info.suggested
        if let track {
            // Fehlende Felder aus der Bibliothek ergänzen (die Tags der Datei haben Vorrang)
            if meta.title.studioTrimmed.isEmpty { meta.title = track.title ?? track.displayTitle }
            if meta.artist.studioTrimmed.isEmpty { meta.artist = track.artists.joined(separator: ", ") }
            if meta.album.studioTrimmed.isEmpty { meta.album = track.album ?? "" }
            if meta.albumArtist.studioTrimmed.isEmpty { meta.albumArtist = track.albumArtists.joined(separator: ", ") }
            if meta.genre.studioTrimmed.isEmpty { meta.genre = track.genres.first ?? "" }
            if meta.year == nil { meta.year = track.year }
            if meta.trackNumber == nil { meta.trackNumber = track.trackNumber }
        }
        if meta.cover == nil, let thumb = info.thumbnail { meta.cover = thumb }
        metadata = meta
        selection = TrimRange(start: 0, end: info.duration ?? 0)
        exportWholeFile = true
        prepare = .notNeeded
        if info.libraryUid != nil {
            cutSaveMode = .newFile
            keepOriginalFormat = true
            applyOriginalFormat()
        }
        sourceState = .ready
        computeWaveform(info.localFile ?? info.url)
        if info.libraryUid != nil && opensInEditMode {
            opensInEditMode = false
            enterEditMode()
        }
    }

    /// Format und Qualität wie das Original (Schneiden vorhandener Songs); sonst M4A.
    private func applyOriginalFormat() {
        guard let source, source.libraryUid != nil else { return }
        let format = source.sameFormat ?? .m4a
        var o = settings.options(for: format)
        o.sampleRate = nil
        if let kbps = source.bitrateKbps, kbps > 0 {
            o.mp3Bitrate = kbps
            o.aacBitrate = kbps
        }
        if let bits = source.bitDepth {
            o.pcmDepth = bits <= 16 ? .int16 : (bits <= 24 ? .int24 : .float32)
        }
        o.flacKeepSourceDepth = true
        options = o.normalized()
    }

    private func mergeAudioDetails(from local: SourceInfo) {
        guard var s = source else { return }
        s.codec = local.codec ?? s.codec
        s.bitrateKbps = local.bitrateKbps ?? s.bitrateKbps
        s.sampleRate = local.sampleRate ?? s.sampleRate
        s.bitDepth = local.bitDepth ?? s.bitDepth
        s.channels = local.channels ?? s.channels
        s.fileSize = local.fileSize ?? s.fileSize
        if let d = local.duration, d > 0 {
            let wasWhole = exportWholeFile || selection.end <= 0 || abs(selection.end - (s.duration ?? 0)) < 0.01
            s.duration = d
            source = s
            if wasWhole { selection = TrimRange(start: 0, end: d) } else { setSelection() }
        } else {
            source = s
        }
    }

    /// Alles der vorigen Quelle beenden und zurücksetzen.
    private func resetForNewSource() {
        stopPreview()
        sourceTask?.cancel()
        prepareTask?.cancel()
        waveformTask?.cancel()
        thumbnailTask?.cancel()
        sourceGeneration += 1
        let wasLibrary = isLibraryTrack
        releaseEditCache()
        previewLoadedFile = nil
        source = nil
        waveform = nil
        waveformProgress = nil
        prepare = .notNeeded
        selection = TrimRange(start: 0, end: 0)
        exportWholeFile = true
        zoom = 1
        visibleStart = 0
        playback.playhead = 0
        metadata = StudioMetadata()
        customFileName = ""
        fadeIn = 0
        fadeOut = 0
        if wasLibrary {
            cutSaveMode = .newFile
            keepOriginalFormat = true
            options = settings.options(for: settings.lastFormat)
        }
        resetTrackEditState()
    }

    private func editCacheDirectory() -> URL {
        if let editCacheDir { return editCacheDir }
        let dir = cacheRoot.appendingPathComponent("edit-\(UUID().uuidString)", isDirectory: true)
        editCacheDir = dir
        return dir
    }

    private func releaseEditCache() {
        guard let dir = editCacheDir else { return }
        editCacheDir = nil
        Self.ioQueue.async { try? FileManager.default.removeItem(at: dir) }
    }

    func computeWaveform(_ file: URL) {
        waveformTask?.cancel()
        waveform = nil
        waveformProgress = 0
        let generation = sourceGeneration
        let throttle = ThrottleGate(interval: 0.2)
        waveformTask = Task { [weak self] in
            guard let self else { return }
            do {
                let w = try await self.services.waveforms.waveform(for: file) { f in
                    guard throttle.allow(force: f >= 1) else { return }
                    Task { @MainActor [weak self] in
                        guard let self, generation == self.sourceGeneration, self.waveformProgress != nil else { return }
                        self.waveformProgress = f
                    }
                }
                guard generation == self.sourceGeneration, !Task.isCancelled else { return }
                self.waveform = w
                self.waveformProgress = nil
                if (self.source?.duration ?? 0) <= 0 { self.source?.duration = w.duration }
                if self.exportWholeFile || self.selection.end <= 0 { self.selection = TrimRange(start: 0, end: self.duration) }
            } catch {
                guard generation == self.sourceGeneration else { return }
                self.waveformProgress = nil
                if !Self.isCancellation(error) {
                    self.lib?.studioToast("Die Wellenform konnte nicht berechnet werden. \(Self.message(error))", action: nil, isError: true, perform: nil)
                }
            }
        }
    }

    // MARK: - Aktionen: Editor

    func setSelection(start: Double? = nil, end: Double? = nil) {
        let d = duration
        var s = start ?? selection.start
        var e = end ?? selection.end
        s = min(max(0, s), d)
        e = min(max(0, e), d)
        if e < s { swap(&s, &e) }
        selection = TrimRange(start: s, end: e)
        exportWholeFile = false
    }

    func selectAll() {
        selection = TrimRange(start: 0, end: duration)
        exportWholeFile = true
    }

    /// Wiedergabe/Pause: Auswahl (oder ganze Datei) ab dem Abspielkopf vorhören.
    func togglePreview() {
        guard let preview else { return }
        if playback.playing {
            preview.pause()
            setPlaying(false)
            return
        }
        let d = duration
        var start = playback.playhead
        var end: Double?
        if exportWholeFile || selection.length < 0.01 {
            if start >= d - 0.05 { start = 0 }
        } else {
            end = selection.end
            if start < selection.start || start >= selection.end - 0.02 { start = selection.start }
        }
        startPreview(from: start, to: end)
    }

    /// Auswahl von Anfang an vorhören.
    func previewSelection() {
        if exportWholeFile || selection.length < 0.01 {
            startPreview(from: 0, to: nil)
        } else {
            startPreview(from: selection.start, to: selection.end)
        }
    }

    func seek(to seconds: Double) {
        let t = min(max(0, seconds), max(duration, 0))
        playback.playhead = t
        if playback.playing {
            let end = previewEnd.flatMap { $0 > t + 0.02 ? $0 : nil }
            startPreview(from: t, to: end)
        }
    }

    func stopPreview() {
        playheadTask?.cancel()
        playheadTask = nil
        if playback.playing { playback.playing = false }
        preview?.stop()
    }

    /// Datei für das Vorhören: lokale Datei bzw. geladene Audiospur.
    private var previewFile: URL? {
        guard let source else { return nil }
        if let f = source.localFile { return f }
        return source.kind == .localFile ? source.url : nil
    }

    private func startPreview(from start: Double, to end: Double?) {
        guard let preview, let file = previewFile else { return }
        do {
            if previewLoadedFile != file {
                try preview.load(file)
                previewLoadedFile = file
            }
        } catch {
            lib?.studioToast("Vorhören ist nicht möglich. \(Self.message(error))", action: nil, isError: true, perform: nil)
            return
        }
        preview.onFinish = { [weak self] in self?.previewFinished() }
        previewEnd = end
        playback.playhead = start
        preview.setEdit(previewEditSettings, normalizationGainDb: previewNormalizationGain)
        preview.play(from: start, to: end)
        setPlaying(true)
    }

    private func previewFinished() {
        setPlaying(false)
        if let end = previewEnd { playback.playhead = end }
    }

    /// Abspielkopf ~30× pro Sekunde, nur während der Wiedergabe (nur `playback` ändert sich).
    private func setPlaying(_ on: Bool) {
        playheadTask?.cancel()
        playheadTask = nil
        if playback.playing != on { playback.playing = on }
        guard on else { return }
        playheadTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let preview = self.preview else { return }
                let p = preview.position
                if abs(self.playback.playhead - p) > 0.0005 { self.playback.playhead = p }
                if !preview.isPlaying {
                    if self.playback.playing { self.playback.playing = false }
                    return
                }
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }
    }

    // MARK: - Aktionen: Export

    func setFormat(_ format: StudioFormat) {
        let keep = isLibraryTrack && keepOriginalFormat
        if !keep { settings.remember(options) }
        if isLibraryTrack, format != source?.sameFormat, keepOriginalFormat { keepOriginalFormat = false }
        options = settings.options(for: format)
        if !isLibraryTrack { settings.lastFormat = format }
    }

    /// Optionen ändern und merken.
    func updateOptions(_ change: (inout ExportOptions) -> Void) {
        var o = options
        change(&o)
        options = o.normalized()
        if !(isLibraryTrack && keepOriginalFormat) { settings.remember(options) }
    }

    /// Aktuelle Quelle als Auftrag in die Warteschlange (startet automatisch, wenn nichts anderes läuft).
    @discardableResult
    func addToQueue() -> StudioJob? {
        guard canExport, let source, let destination else { return nil }
        var job = StudioJob(source: source, options: options, trim: effectiveTrim, metadata: metadata, fileName: fileNameBase,
                            destination: destination)
        job.fadeIn = max(0, fadeIn)
        job.fadeOut = max(0, fadeOut)
        job.edit = activeTrackEdit
        job.preferPassthrough = job.edit == nil && isLibraryTrack && keepOriginalFormat && fadeIn <= 0 && fadeOut <= 0 && options.sampleRate == nil
        jobs.append(job)
        if !(isLibraryTrack && keepOriginalFormat) { settings.remember(options) }
        scheduleNext()
        return job
    }

    func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: - Aktionen: Werkzeuge

    /// Zustand von yt-dlp, Deno und FFmpeg neu bestimmen (beim ersten Öffnen und nach Installation).
    func refreshToolStatus() {
        guard !demo else { return }
        toolsChecked = true
        Task { [weak self] in
            guard let self else { return }
            let status = await self.services.tools.status()
            if status != self.toolStatus { self.toolStatus = status }
        }
    }

    func installTools() {
        guard !demo else { return }
        if case .running = toolInstall { return }
        toolInstall = .running(ToolInstallProgress(step: "Wird vorbereitet …", fraction: 0))
        toolTask = Task { [weak self] in
            guard let self else { return }
            do {
                let status = try await self.services.tools.installOrUpdate { p in
                    Task { @MainActor [weak self] in
                        guard let self, case .running = self.toolInstall else { return }
                        self.toolInstall = .running(p)
                    }
                }
                self.toolStatus = status
                self.toolInstall = .idle
                self.lib?.studioToast("Werkzeuge für Internet-Quellen sind bereit", action: nil, isError: false, perform: nil)
                // Eine an fehlenden Werkzeugen gescheiterte Abfrage erneut versuchen
                if case .failed = self.sourceState, self.source == nil, !self.urlText.studioTrimmed.isEmpty { self.analyzeInput() }
            } catch {
                self.toolInstall = .failed(Self.message(error))
                self.refreshToolStatus()
            }
        }
    }

    func removeTools() {
        guard !demo else { return }
        if case .running = toolInstall { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                self.toolStatus = try await self.services.tools.removeManaged()
                self.toolInstall = .idle
                self.lib?.studioToast("Von der App installierte Werkzeuge entfernt", action: nil, isError: false, perform: nil)
            } catch {
                self.lib?.studioToast(Self.message(error), action: nil, isError: true, perform: nil)
            }
        }
    }

    // MARK: - Hilfen

    /// Verständliche Meldung zu einem Fehler.
    nonisolated static func message(_ error: Error) -> String {
        if let e = error as? StudioError { return e.errorDescription ?? "Fehler" }
        if error is CancellationError { return StudioError.cancelled.errorDescription ?? "Abgebrochen." }
        return error.localizedDescription
    }

    nonisolated static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let e = error as? StudioError, e == .cancelled { return true }
        return false
    }

    nonisolated static func analyzingText(_ kind: SourceKind, url: URL? = nil) -> String {
        if kind == .web, let url, SourceURL.isInstagram(url) { return "Instagram wird abgefragt …" }
        switch kind {
        case .youtube: return "YouTube wird abgefragt …"
        case .soundcloud: return "SoundCloud wird abgefragt …"
        case .spotify: return "Spotify wird abgefragt …"
        case .web, .localFile: return "Adresse wird abgefragt …"
        }
    }

    /// Kurzname einer Adresse für die Warteschlange, bis die Abfrage den Titel liefert.
    nonisolated static func displayName(_ url: URL) -> String {
        let host = (url.host ?? "").replacingOccurrences(of: "www.", with: "")
        let path = url.path == "/" ? "" : url.path
        let q = url.query.map { "?" + $0 } ?? ""
        let text = host + path + q
        return text.count > 80 ? String(text.prefix(79)) + "…" : text
    }

    nonisolated static func provisionalSource(file: URL) -> SourceInfo {
        SourceInfo(id: file.path, kind: .localFile, url: file, title: file.deletingPathExtension().lastPathComponent, localFile: file)
    }

    /// Eingabe zerlegen: Adressen (auch mehrere je Zeile) und Dateipfade (ganze Zeile).
    struct ParsedInput {
        var urls: [(kind: SourceKind, url: URL)] = []
        var files: [URL] = []
        var invalid: [String] = []
    }

    nonisolated static func parseInput(_ text: String) -> ParsedInput {
        var out = ParsedInput()
        var seen = Set<String>()
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("/") || line.hasPrefix("~/") || line.lowercased().hasPrefix("file://") {
                let url: URL
                if line.lowercased().hasPrefix("file://"), let u = URL(string: line), u.isFileURL {
                    url = u
                } else {
                    url = URL(fileURLWithPath: (line as NSString).expandingTildeInPath)
                }
                if FileManager.default.fileExists(atPath: url.path) {
                    if seen.insert(url.path).inserted { out.files.append(url) }
                } else {
                    out.invalid.append(line)
                }
                continue
            }
            for token in line.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
                var t = String(token).trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'«»„“”"))
                while let last = t.last, ".,;!".contains(last) { t.removeLast() }
                if let c = SourceURL.classify(t) {
                    if seen.insert(c.url.absoluteString).inserted { out.urls.append((c.kind, c.url)) }
                } else if !t.isEmpty {
                    out.invalid.append(t)
                }
            }
        }
        return out
    }

    nonisolated static let extraFileExtensions: Set<String> = ["ogg", "oga", "opus", "webm", "mkv", "mka", "flac", "caf", "aac", "m4b"]

    nonisolated static func isSupportedFile(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return false }
        let ext = url.pathExtension.lowercased()
        if extraFileExtensions.contains(ext) || LibraryService.audioExtensions.contains(ext) { return true }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .audio) || type.conforms(to: .audiovisualContent)
    }

    static var openPanelTypes: [UTType] {
        var types: [UTType] = [.audio, .audiovisualContent, .movie]
        for ext in extraFileExtensions.sorted() {
            if let t = UTType(filenameExtension: ext), !types.contains(t) { types.append(t) }
        }
        return types
    }
}

/// Ergebnisse eines Durchlaufs der Warteschlange (bis sie wieder leer ist).
struct StudioQueueRun {
    var done = 0
    var failed = 0
    var last: (job: StudioJob, path: String)?
    var lastFailure: (title: String, message: String)?
}

/// Bibliothekstitel nach normalisiertem Titel und Pfad (für `DuplicateCheck`).
struct StudioDuplicateIndex: Sendable {
    var byTitle: [String: [DuplicateCheck.Candidate]] = [:]
    var byPath: [String: DuplicateCheck.Candidate] = [:]

    init(tracks: [Track]) {
        for t in tracks {
            let title = t.title ?? t.displayTitle
            let seconds = Double(t.durationMs) / 1000
            let joined = DuplicateCheck.Candidate(uid: t.uid, title: title, artist: t.artists.joined(separator: ", "), durationSeconds: seconds, path: t.path)
            byPath[t.path] = joined
            let key = DuplicateCheck.normalize(title)
            guard !key.isEmpty else { continue }
            byTitle[key, default: []].append(joined)
            // Mehrere Interpreten: auch jeden einzeln vergleichen („A, B“ ↔ „A“)
            if t.artists.count > 1 {
                for a in t.artists {
                    byTitle[key, default: []].append(DuplicateCheck.Candidate(uid: t.uid, title: title, artist: a, durationSeconds: seconds, path: t.path))
                }
            }
        }
    }
}

extension String {
    /// Ohne führende/folgende Leerzeichen und Zeilenumbrüche (Audio Studio).
    var studioTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
