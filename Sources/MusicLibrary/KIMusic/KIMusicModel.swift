import SwiftUI
import AppKit
import Combine
import MLCore
import MLStudio
import StudioEngine

/// KI-Musik: Einrichtung, Erzeugung, Kreationen. Alles Rechnen läuft im eigenen Python-Prozess (KIEngine);
/// diese Klasse hält nur den Zustand für die Oberfläche und die Abläufe. Der Hauptthread wird nie blockiert.
@MainActor
final class KIMusicModel: ObservableObject {
    // MARK: Einrichtung

    enum Setup: Equatable {
        case unsupported(String)
        /// Umgebung (Python, ACE-Step) fehlt.
        case needsEnvironment
        /// Grundpaket der Modelle fehlt.
        case needsModels
        case ready
    }

    enum InstallActivity: Equatable {
        case idle
        case running(title: String, progress: KIInstaller.Progress)
        case failed(String)
    }

    let support: KISupport
    let demo: Bool
    private let installer: KIInstaller?
    private var engine: KIEngineServing?
    private let defaults: UserDefaults

    @Published private(set) var setup: Setup = .needsEnvironment
    @Published private(set) var installTask: InstallActivity = .idle
    @Published private(set) var installState = KIInstaller.State()
    @Published private(set) var freeSpace: Int64?
    private var installJob: Task<Void, Never>?

    // MARK: Erzeugen

    @Published var request: KIGenerationRequest {
        didSet { if request != oldValue { saveDraft() } }
    }
    @Published private(set) var history: [String] = []

    enum Phase: Equatable {
        case idle
        case working(step: String, progress: Double?, started: Date, estimate: Double)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// Ergebnisse der letzten Erzeugung (Varianten).
    @Published private(set) var results: [KICreation] = []
    /// Vom Sprachmodell geschriebener Text der letzten Erzeugung (wird angezeigt und kann übernommen werden).
    @Published private(set) var lastLyrics: String?
    private var generateJob: Task<Void, Never>?
    private var idleTimer: Timer?

    // MARK: Kreationen

    @Published private(set) var creations = KICreationIndex()
    @Published var filter: KICreationFilter = .all
    @Published var query = ""
    @Published private(set) var playingID: UUID?
    let preview: StudioPreviewing?

    /// Ordner der Kreationen (nicht Teil der Musikbibliothek): ~/Music/KI-Musik
    let creationsFolder: URL
    private var indexURL: URL { creationsFolder.appendingPathComponent(".kreationen.json") }

    // MARK: Gelernte Zeiten

    private var secondsPerAudioSecond: Double? {
        get { defaults.object(forKey: "ki.secondsPerAudioSecond") as? Double }
        set { defaults.set(newValue, forKey: "ki.secondsPerAudioSecond") }
    }
    private var planningSeconds: Double? {
        get { defaults.object(forKey: "ki.planningSeconds") as? Double }
        set { defaults.set(newValue, forKey: "ki.planningSeconds") }
    }
    /// Minuten ohne Nutzung, nach denen der KI-Prozess beendet wird (Speicher frei).
    @Published var unloadMinutes: Int {
        didSet { defaults.set(unloadMinutes, forKey: "ki.unloadMinutes") }
    }

    init(demo: Bool, support: KISupport? = nil, installer: KIInstaller? = nil, engine: KIEngineServing? = nil,
         creationsFolder: URL? = nil, defaults: UserDefaults = .standard, preview: StudioPreviewing? = nil) {
        self.demo = demo
        self.defaults = defaults
        self.support = support ?? (demo ? .supported(recommendedLM: KIModel.lmMedium.id) : Self.detectSupport())
        self.creationsFolder = creationsFolder ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Music/KI-Musik", isDirectory: true)
        self.preview = preview
        self.unloadMinutes = (defaults.object(forKey: "ki.unloadMinutes") as? Int) ?? 10
        if let data = defaults.data(forKey: "ki.draft"), let r = try? JSONDecoder().decode(KIGenerationRequest.self, from: data) {
            self.request = r
        } else {
            self.request = KIGenerationRequest()
        }
        self.history = defaults.stringArray(forKey: "ki.history") ?? []
        if demo {
            self.installer = nil
            return
        }
        let base = StudioServiceSet.supportDirectory.deletingLastPathComponent().appendingPathComponent("KI-Musik", isDirectory: true)
        let scripts = Bundle.main.resourceURL?.appendingPathComponent("KIEngine", isDirectory: true)
            ?? URL(fileURLWithPath: "/nonexistent")
        let inst = installer ?? KIInstaller(base: base, scripts: scripts)
        self.installer = inst
        self.engine = engine
        refreshSetup()
        loadCreations()
        preview?.onFinish = { [weak self] in Task { @MainActor in self?.playingID = nil } }
    }

    // MARK: Vorschaubilder

    /// Feste Zustände für Vorschaubilder (Demo-Modus, keine Dateien, kein Prozess).
    func applyDemo(setup: Setup, installTask: InstallActivity = .idle, phase: Phase = .idle, results: [KICreation] = [],
                   creations: [KICreation] = [], lastLyrics: String? = nil, freeSpace: Int64? = 412_000_000_000) {
        guard demo else { return }
        self.setup = setup
        self.installTask = installTask
        self.phase = phase
        self.results = results
        self.creations = KICreationIndex(items: creations)
        self.lastLyrics = lastLyrics
        self.freeSpace = freeSpace
    }

    // MARK: Hardware

    static func detectSupport() -> KISupport {
        func sysctl(_ name: String) -> Int64? {
            var value: Int64 = 0
            var size = MemoryLayout<Int64>.size
            return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
        }
        func sysctlInt32(_ name: String) -> Int32? {
            var value: Int32 = 0
            var size = MemoryLayout<Int32>.size
            return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
        }
        // hw.optional.arm64 ist auch unter Rosetta 1 auf Apple-Chips
        let appleSilicon = (sysctlInt32("hw.optional.arm64") ?? 0) == 1
        #if arch(arm64)
        let machine = "arm64"
        #else
        let machine = "x86_64"
        #endif
        let memory = Double(sysctl("hw.memsize") ?? 0) / 1_073_741_824
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return KIHardware.support(machine: machine, translated: machine != "arm64" && appleSilicon, memoryGB: memory, macOSMajor: major)
    }

    // MARK: Einrichtung

    func refreshSetup() {
        guard support.isUsable else {
            if case .unsupported(let reason) = support { setup = .unsupported(reason) }
            return
        }
        guard let installer else { return }
        installState = installer.loadState()
        freeSpace = installer.freeSpace()
        if !installer.environmentReady { setup = .needsEnvironment }
        else if !installer.isInstalled(.core) { setup = .needsModels }
        else { setup = .ready }
    }

    func isInstalled(_ model: KIModel) -> Bool {
        if demo { return demoInstalled.contains(model.id) || (model.id == KIModel.lmMedium.id && demoInstalled.contains(KIModel.core.id)) }
        return installer?.isInstalled(model) ?? false
    }

    /// Vorschaubilder: als geladen geltende Modelle.
    var demoInstalled: Set<String> = []

    var installing: Bool {
        if case .running = installTask { return true }
        return false
    }

    /// Umgebung und Grundpaket nacheinander einrichten (ein Klick, je Schritt abbrechbar).
    func installEverything() {
        guard let installer, !installing else { return }
        installJob = Task { [weak self] in
            guard let self else { return }
            do {
                if !installer.environmentReady {
                    self.installTask = .running(title: "KI-Umgebung", progress: .init(step: "Wird vorbereitet …", fraction: 0))
                    try await installer.installEnvironment { p in Task { @MainActor in self.installTask = .running(title: "KI-Umgebung", progress: p) } }
                }
                if !installer.isInstalled(.core) {
                    self.installTask = .running(title: KIModel.core.title, progress: .init(step: "Wird vorbereitet …", fraction: nil))
                    try await installer.download(.core) { p in Task { @MainActor in self.installTask = .running(title: KIModel.core.title, progress: p) } }
                }
                self.installTask = .idle
            } catch {
                self.installTask = Task.isCancelled || error is CancellationError || StudioModel.isCancellation(error)
                    ? .idle : .failed(StudioModel.message(error))
            }
            self.refreshSetup()
        }
    }

    func download(_ model: KIModel) {
        guard let installer, !installing else { return }
        installJob = Task { [weak self] in
            guard let self else { return }
            do {
                self.installTask = .running(title: model.title, progress: .init(step: "Wird vorbereitet …", fraction: nil))
                try await installer.download(model) { p in Task { @MainActor in self.installTask = .running(title: model.title, progress: p) } }
                self.installTask = .idle
            } catch {
                self.installTask = StudioModel.isCancellation(error) ? .idle : .failed(StudioModel.message(error))
            }
            self.refreshSetup()
        }
    }

    func cancelInstall() {
        installJob?.cancel()
        installJob = nil
    }

    func remove(_ model: KIModel) {
        guard let installer else { return }
        engine?.shutdown()
        do { try installer.remove(model) } catch { installTask = .failed(StudioModel.message(error)) }
        refreshSetup()
    }

    func removeEverything() {
        guard let installer else { return }
        engine?.shutdown()
        engine = nil
        do { try installer.removeEverything() } catch { installTask = .failed(StudioModel.message(error)) }
        refreshSetup()
    }

    func revealLog() {
        guard let installer else { return }
        NSWorkspace.shared.activateFileViewerSelecting([installer.paths.log])
    }

    // MARK: Erzeugen

    var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    var estimate: Double {
        KIEstimate.seconds(for: request, secondsPerAudioSecond: secondsPerAudioSecond, planningSeconds: planningSeconds)
    }

    /// Sprachmodell für diesen Rechner (installiert und empfohlen; sonst das des Grundpakets).
    var languageModel: String? {
        switch support {
        case .supported(let lm), .limited(let lm?, _):
            if lm == KIModel.lmLarge.id, isInstalled(.lmLarge) { return lm }
            if lm == KIModel.lmSmall.id, isInstalled(.lmSmall) { return lm }
            return KIModel.lmMedium.id
        case .limited(nil, _): return nil
        case .unsupported: return nil
        }
    }

    /// Hinweis, warum gerade nicht erzeugt werden kann (nil = bereit).
    var blocker: String? {
        if let p = request.problem { return p }
        if setup != .ready { return "Zuerst KI-Musik einrichten." }
        if request.quality == .high && !isInstalled(.xlTurbo) { return "Für „Hohe Qualität“ das Musikmodell XL laden (Einstellungen → KI-Musik)." }
        if (request.lyricsMode == .aiWrites || request.lyricsMode == .revise || request.quality.usesPlanning) && languageModel == nil {
            return "Auf diesem Mac läuft kein Sprachmodell – wähle „Schnell“ und einen eigenen Text oder Instrumental."
        }
        return nil
    }

    func generate() {
        guard blocker == nil, !isWorking, let installer else { return }
        do {
            try installer.installScripts()
        } catch {
            phase = .failed(StudioModel.message(error))
            return
        }
        let req = request
        rememberPrompt(req.prompt)
        let engine = self.engine ?? KIEngine(installer: installer)
        self.engine = engine
        idleTimer?.invalidate()
        let started = Date()
        let estimate = self.estimate
        phase = .working(step: "KI-Prozess startet …", progress: nil, started: started, estimate: estimate)
        lastLyrics = nil
        generateJob = Task { [weak self] in
            guard let self else { return }
            let report: @Sendable (Double, String) -> Void = { value, text in
                Task { @MainActor in
                    if case .working(_, _, let s, let e) = self.phase {
                        self.phase = .working(step: text.isEmpty ? "Musik wird erzeugt …" : Self.translate(text), progress: value, started: s, estimate: e)
                    }
                }
            }
            do {
                let lm = (req.quality.usesPlanning || req.lyricsMode == .aiWrites || req.lyricsMode == .revise) ? self.languageModel : nil
                try await engine.prepare(dit: req.quality.ditModel, lm: lm, progress: report)
                var lyrics: String? = nil
                var caption: String? = nil
                if req.lyricsMode == .aiWrites || req.lyricsMode == .revise {
                    let t0 = Date()
                    let written = try await engine.writeLyrics(query: req.prompt, caption: req.prompt, lyrics: req.lyricsMode == .revise ? req.lyrics : "",
                                                               language: req.language, instrumental: false, progress: report)
                    lyrics = written.lyrics
                    if req.lyricsMode == .aiWrites, !written.caption.isEmpty { caption = written.caption }
                    self.planningSeconds = KIEstimate.learn(self.planningSeconds, measured: Date().timeIntervalSince(t0))
                    self.lastLyrics = written.lyrics
                }
                let work = self.creationsFolder.appendingPathComponent(".arbeit-\(UUID().uuidString)", isDirectory: true)
                let seeds = req.seed.map { s in (0..<req.variations).map { s + $0 } }
                let result = try await engine.generate(params: req.engineParams(lyricsOverride: lyrics, captionOverride: caption),
                                                       variations: req.variations, seeds: seeds, saveDirectory: work,
                                                       usePlanning: req.quality.usesPlanning && lm != nil, progress: report)
                if let d = req.duration, result.seconds > 0 {
                    self.secondsPerAudioSecond = KIEstimate.learn(self.secondsPerAudioSecond, measured: result.seconds / (d * Double(result.files.count)))
                }
                let made = try self.store(result, request: req, lyrics: lyrics ?? (req.instrumental ? "" : req.lyrics))
                try? FileManager.default.removeItem(at: work)
                self.results = made
                self.phase = .idle
            } catch {
                self.phase = StudioModel.isCancellation(error) || (error as? KIEngineClient.ClientError) == .cancelled
                    ? .idle : .failed(StudioModel.message(error))
            }
            self.scheduleUnload()
        }
    }

    func cancelGeneration() {
        generateJob?.cancel()
        engine?.shutdown()
        phase = .idle
    }

    func dismissError() {
        if case .failed = phase { phase = .idle }
        if case .failed = installTask { installTask = .idle }
    }

    /// Fortschrittstexte von ACE-Step auf Deutsch.
    nonisolated static func translate(_ text: String) -> String {
        let map: [(String, String)] = [("Preparing inputs", "Eingaben werden vorbereitet"), ("Decoding audio", "Audio wird dekodiert"),
                                       ("Preparing audio data", "Audio wird gespeichert"), ("Generating", "Musik wird erzeugt"),
                                       ("LM", "Sprachmodell plant"), ("Bereit", "Modelle geladen")]
        for (en, de) in map where text.contains(en) { return de + " …" }
        return text
    }

    private func scheduleUnload() {
        idleTimer?.invalidate()
        guard unloadMinutes > 0 else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: Double(unloadMinutes) * 60, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isWorking else { return }
                self.engine?.shutdown()
            }
        }
    }

    /// Erzeugte Dateien in den Kreationen-Ordner verschieben und eintragen.
    private func store(_ result: KIGenerationResult, request: KIGenerationRequest, lyrics: String) throws -> [KICreation] {
        let fm = FileManager.default
        try fm.createDirectory(at: creationsFolder, withIntermediateDirectories: true)
        let base = KICreation.suggestedTitle(from: request.prompt)
        var made: [KICreation] = []
        for (i, file) in result.files.enumerated() {
            let title = result.files.count > 1 ? "\(base) (\(i + 1))" : base
            let name = FileNames.sanitize(title)
            var dest = creationsFolder.appendingPathComponent(name + "." + file.url.pathExtension)
            var n = 2
            while fm.fileExists(atPath: dest.path) {
                dest = creationsFolder.appendingPathComponent("\(name) \(n).\(file.url.pathExtension)")
                n += 1
            }
            try fm.moveItem(at: file.url, to: dest)
            let c = KICreation(title: title, kind: request.instrumental ? .instrumental : .song, file: dest.lastPathComponent,
                               duration: request.duration, prompt: request.prompt, lyrics: lyrics,
                               language: request.instrumental ? nil : request.language, genre: "", seed: file.seed,
                               model: request.quality.ditModel, modelVersion: "ACE-Step 1.5", request: request)
            creations.add(c)
            made.append(c)
        }
        saveCreations()
        return made
    }

    // MARK: Prompt-Verlauf und Entwurf

    private func saveDraft() {
        if let data = try? JSONEncoder().encode(request) { defaults.set(data, forKey: "ki.draft") }
    }

    private func rememberPrompt(_ prompt: String) {
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        history.removeAll { $0 == p }
        history.insert(p, at: 0)
        if history.count > 50 { history.removeLast(history.count - 50) }
        defaults.set(history, forKey: "ki.history")
    }

    func usePrompt(_ prompt: String) { request.prompt = prompt }

    func clearHistory() {
        history = []
        defaults.set(history, forKey: "ki.history")
    }

    // MARK: Kreationen

    func loadCreations() {
        guard let data = try? Data(contentsOf: indexURL), let idx = try? JSONDecoder().decode(KICreationIndex.self, from: data) else { return }
        // Nur Einträge, deren Datei noch existiert
        creations = KICreationIndex(items: idx.items.filter { FileManager.default.fileExists(atPath: url(of: $0).path) })
    }

    private func saveCreations() {
        guard !demo else { return }
        do {
            try FileManager.default.createDirectory(at: creationsFolder, withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(creations).write(to: indexURL, options: .atomic)
        } catch {
            NSLog("KI-Musik: Index konnte nicht gespeichert werden: \(error.localizedDescription)")
        }
    }

    func url(of c: KICreation) -> URL { creationsFolder.appendingPathComponent(c.file) }

    var shownCreations: [KICreation] { creations.filtered(filter, query: query) }

    func togglePlay(_ c: KICreation) {
        guard let preview else { return }
        if playingID == c.id {
            preview.stop()
            playingID = nil
            return
        }
        do {
            try preview.load(url(of: c))
            preview.play(from: 0, to: nil)
            playingID = c.id
        } catch {
            AppModel.shared?.toast("Abspielen nicht möglich: \(error.localizedDescription)", isError: true)
        }
    }

    func stopPlayback() {
        preview?.stop()
        playingID = nil
    }

    func toggleFavorite(_ c: KICreation) {
        var x = c
        x.favorite.toggle()
        replace(x)
    }

    func rename(_ c: KICreation, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var x = c
        x.title = t
        replace(x)
    }

    private func replace(_ c: KICreation) {
        if let i = creations.items.firstIndex(where: { $0.id == c.id }) { creations.items[i] = c }
        results = results.map { $0.id == c.id ? c : $0 }
        saveCreations()
    }

    /// Kreation löschen (Datei in den Papierkorb – wiederherstellbar).
    func delete(_ c: KICreation) {
        if playingID == c.id { stopPlayback() }
        try? FileManager.default.trashItem(at: url(of: c), resultingItemURL: nil)
        creations.remove(c.id)
        results.removeAll { $0.id == c.id }
        saveCreations()
    }

    func reveal(_ c: KICreation) {
        NSWorkspace.shared.activateFileViewerSelecting([url(of: c)])
    }

    /// Einstellungen der Kreation in den Editor übernehmen (erneut erzeugen / Variation).
    func reuse(_ c: KICreation, newVariation: Bool) {
        guard var r = c.request else { request.prompt = c.prompt; return }
        if newVariation { r.seed = nil } else { r.seed = c.seed }
        if !c.lyrics.isEmpty, r.lyricsMode == .aiWrites { r.lyricsMode = .own; r.lyrics = c.lyrics }
        request = r
    }

    /// In die Musikbibliothek übernehmen: über „Hinzufügen“ (gleiche Warteschlange, Format und Ziel wie dort).
    func addToLibrary(_ c: KICreation, app: AppModel) {
        let file = url(of: c)
        app.addStudio.importKICreation(file: file, title: c.title, genre: c.genre.isEmpty ? (c.kind == .instrumental ? "Instrumental" : "") : c.genre)
        var x = c
        x.exportedPath = file.path
        replace(x)
    }
}
