import SwiftUI
import AppKit
import MLCore
import MLStudio
import StudioEngine

/// KI-Hörbücher & Hörspiele: Einrichtung, Produktionen, Stimmenstudio, Referenzen, Geräusche. Alles Rechnen läuft
/// im eigenen Python-Prozess (HSEngine); diese Klasse hält den Zustand und steuert die Abläufe Schritt für Schritt
/// (nach jedem Teilschritt gespeichert – eine unterbrochene Produktion lässt sich fortsetzen).
@MainActor
final class HoerspielModel: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case hoerbuch, hoerspiel, reference, voices, editor, sound, productions
        var id: String { rawValue }
        var title: String {
            switch self {
            case .hoerbuch: return "Hörbuch erstellen"
            case .hoerspiel: return "Hörspiel erstellen"
            case .reference: return "Referenz analysieren"
            case .voices: return "Stimmenstudio"
            case .editor: return "Geschichten-Editor"
            case .sound: return "Sounddesign"
            case .productions: return "Meine Produktionen"
            }
        }
        var icon: String {
            switch self {
            case .hoerbuch: return Icons.audiobook
            case .hoerspiel: return Icons.drama
            case .reference: return Icons.equalizer
            case .voices: return Icons.voice
            case .editor: return Icons.editNote
            case .sound: return Icons.sfx
            case .productions: return Icons.libraryMusic
            }
        }
    }

    enum Setup: Equatable {
        case unsupported(String)
        case needsEnvironment
        /// Fehlende Pflichtmodelle (Geschichte, Stimmen).
        case needsModels([HSModel])
        case ready
    }

    enum InstallActivity: Equatable {
        case idle
        case running(title: String, progress: KIInstaller.Progress)
        case failed(String)
    }

    enum Phase: Equatable {
        case idle
        case working(title: String, detail: String, progress: Double?, started: Date)
        case failed(String)
    }

    struct Draft: Codable, Equatable {
        var prompt = ""
        var minutes: Double = 10
        var characters: [String] = []
        var referenceID: UUID?
        var narration = "spannend"
        var retro: Double = 0.6
        var useMusic = true
        var useSFX = true
    }

    // MARK: Zustand

    let support: KISupport
    let demo: Bool
    let installer: HSInstaller?
    private(set) var engine: HSEngine?
    let store: HSStore
    weak var ki: KIMusicModel?
    let preview: StudioPreviewing?
    private let defaults: UserDefaults

    @Published var section: Section = .hoerspiel
    @Published private(set) var setup: Setup = .needsEnvironment
    @Published private(set) var installTask: InstallActivity = .idle
    @Published private(set) var installState = HSInstaller.State()
    @Published private(set) var freeSpace: Int64?
    private var installJob: Task<Void, Never>?

    @Published var drafts: [HSMode: Draft] = [:] { didSet { saveDrafts() } }
    @Published private(set) var productions: [HSProduction] = []
    @Published var currentID: UUID?
    @Published private(set) var voices: [HSVoiceProfile] = []
    @Published private(set) var references: [HSReference] = []
    @Published private(set) var sfxLibrary: [HSSFXEntry] = []
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var playingKey: String?
    /// Letzte Meldung eines Schritts, der übersprungen wurde (z. B. Musik ohne eingerichtete KI-Musik).
    @Published private(set) var notice: String?
    private var job: Task<Void, Never>?
    private var idleTimer: Timer?

    @Published var unloadMinutes: Int {
        didSet { defaults.set(unloadMinutes, forKey: "hs.unloadMinutes") }
    }

    var current: HSProduction? {
        get { productions.first { $0.id == currentID } }
        set {
            guard let newValue, let i = productions.firstIndex(where: { $0.id == newValue.id }) else { return }
            productions[i] = newValue
            persist(newValue)
        }
    }

    init(demo: Bool, support: KISupport? = nil, installer: HSInstaller? = nil, root: URL? = nil, defaults: UserDefaults = .standard,
         preview: StudioPreviewing? = nil) {
        self.demo = demo
        self.defaults = defaults
        self.preview = preview
        self.support = support ?? (demo ? .supported(recommendedLM: HSModel.storyLarge.repo) : Self.detectSupport())
        self.unloadMinutes = (defaults.object(forKey: "hs.unloadMinutes") as? Int) ?? 10
        let rootURL = root ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Music/KI-Hörspiele", isDirectory: true)
        self.store = HSStore(root: rootURL)
        if let data = defaults.data(forKey: "hs.drafts"), let d = try? JSONDecoder().decode([String: Draft].self, from: data) {
            var map: [HSMode: Draft] = [:]
            for (k, v) in d { if let m = HSMode(rawValue: k) { map[m] = v } }
            self.drafts = map
        }
        if demo {
            self.installer = nil
            return
        }
        let base = StudioServiceSet.supportDirectory.deletingLastPathComponent().appendingPathComponent("KI-Hoerspiel", isDirectory: true)
        let scripts = Bundle.main.resourceURL?.appendingPathComponent("HoerspielEngine", isDirectory: true) ?? URL(fileURLWithPath: "/nonexistent")
        self.installer = installer ?? HSInstaller(base: base, scripts: scripts)
        refreshSetup()
        reload()
        preview?.onFinish = { [weak self] in Task { @MainActor in self?.playingKey = nil } }
    }

    func draft(_ mode: HSMode) -> Draft { drafts[mode] ?? Draft() }

    private func saveDrafts() {
        guard !demo else { return }
        var d: [String: Draft] = [:]
        for (k, v) in drafts { d[k.rawValue] = v }
        if let data = try? JSONEncoder().encode(d) { defaults.set(data, forKey: "hs.drafts") }
    }

    // MARK: Vorschaubilder

    func applyDemo(setup: Setup, phase: Phase = .idle, productions: [HSProduction] = [], voices: [HSVoiceProfile] = [],
                   references: [HSReference] = [], sfx: [HSSFXEntry] = [], current: UUID? = nil) {
        guard demo else { return }
        self.setup = setup
        self.phase = phase
        self.productions = productions
        self.voices = voices
        self.references = references
        self.sfxLibrary = sfx
        self.currentID = current
        self.freeSpace = 412_000_000_000
    }

    // MARK: Hardware und Einrichtung

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
        let appleSilicon = (sysctlInt32("hw.optional.arm64") ?? 0) == 1
        #if arch(arm64)
        let machine = "arm64"
        #else
        let machine = "x86_64"
        #endif
        let memory = Double(sysctl("hw.memsize") ?? 0) / 1_073_741_824
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return HSHardware.support(machine: machine, translated: machine != "arm64" && appleSilicon, memoryGB: memory, macOSMajor: major)
    }

    /// Geschichtenmodell für diesen Mac (installiertes größtes passendes Modell bevorzugt).
    var storyModel: HSModel? {
        guard case .supported(let repo) = support else {
            if case .limited(let repo?, _) = support { return HSModel.story.first { $0.repo == repo } }
            return nil
        }
        return HSModel.story.first { $0.repo == repo }
    }

    var requiredModels: [HSModel] {
        guard let story = storyModel else { return [] }
        return [story] + HSModel.voices
    }

    func refreshSetup() {
        guard support.isUsable else {
            if case .unsupported(let reason) = support { setup = .unsupported(reason) }
            return
        }
        guard let installer else { return }
        installState = installer.loadState()
        freeSpace = installer.freeSpace()
        if !installer.environmentReady { setup = .needsEnvironment; return }
        let missing = requiredModels.filter { !installer.isInstalled($0) }
        setup = missing.isEmpty ? .ready : .needsModels(missing)
    }

    func isInstalled(_ m: HSModel) -> Bool { installer?.isInstalled(m) ?? false }

    var installing: Bool {
        if case .running = installTask { return true }
        return false
    }

    /// Umgebung und Pflichtmodelle nacheinander einrichten (abbrechbar, Fortsetzen beim nächsten Klick).
    func installEverything() {
        guard let installer, !installing else { return }
        installJob = Task { [weak self] in
            guard let self else { return }
            do {
                if !installer.environmentReady {
                    self.installTask = .running(title: "Hörspiel-Umgebung", progress: .init(step: "Wird vorbereitet …", fraction: 0))
                    try await installer.installEnvironment { p in Task { @MainActor in self.installTask = .running(title: "Hörspiel-Umgebung", progress: p) } }
                }
                for m in self.requiredModels where !installer.isInstalled(m) {
                    self.installTask = .running(title: m.title, progress: .init(step: "Wird vorbereitet …", fraction: nil))
                    try await installer.download(m) { p in Task { @MainActor in self.installTask = .running(title: m.title, progress: p) } }
                }
                self.installTask = .idle
            } catch {
                self.installTask = StudioModel.isCancellation(error) ? .idle : .failed(StudioModel.message(error))
            }
            self.refreshSetup()
        }
    }

    func download(_ model: HSModel) {
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

    func remove(_ model: HSModel) {
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

    func revealFolder() {
        try? FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([store.root])
    }

    // MARK: Daten

    func reload() {
        productions = store.loadProductions()
        voices = store.loadVoices()
        references = store.loadReferences()
        sfxLibrary = store.loadSFX()
        if currentID == nil { currentID = productions.first?.id }
    }

    func persist(_ p: HSProduction) {
        guard !demo else { return }
        do { try store.save(p) } catch { phase = .failed("Speichern fehlgeschlagen: \(StudioModel.message(error))") }
    }

    func update(_ id: UUID, _ change: (inout HSProduction) -> Void) {
        guard let i = productions.firstIndex(where: { $0.id == id }) else { return }
        var p = productions[i]
        change(&p)
        p.modified = Date()
        productions[i] = p
        persist(p)
    }

    func folder(_ p: HSProduction) -> URL { store.folder(for: p) }

    /// Datei einer Produktion (relativ zum Produktionsordner oder absolut).
    func file(_ path: String, in p: HSProduction) -> URL {
        path.hasPrefix("/") ? URL(fileURLWithPath: path) : folder(p).appendingPathComponent(path)
    }

    /// Produktion in den Papierkorb (nie endgültig löschen).
    func trash(_ p: HSProduction) {
        let dir = folder(p)
        if FileManager.default.fileExists(atPath: dir.path) {
            do { try FileManager.default.trashItem(at: dir, resultingItemURL: nil) } catch {
                phase = .failed("In den Papierkorb legen fehlgeschlagen: \(StudioModel.message(error))")
                return
            }
        }
        productions.removeAll { $0.id == p.id }
        if currentID == p.id { currentID = productions.first?.id }
    }

    func rename(_ p: HSProduction, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        update(p.id) { $0.title = t }
    }

    // MARK: Prozess

    var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    func engineForUse() throws -> HSEngine {
        guard let installer else { throw StudioError.other("Nicht verfügbar.") }
        guard setup == .ready else { throw StudioError.other("Zuerst KI-Hörbücher einrichten.") }
        try installer.installScripts()
        let e = engine ?? HSEngine(installer: installer)
        engine = e
        idleTimer?.invalidate()
        return e
    }

    /// Nach der Arbeit: Prozess nach der Leerlaufzeit beenden (Speicher frei).
    func scheduleIdleShutdown() {
        idleTimer?.invalidate()
        let minutes = unloadMinutes
        idleTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(max(1, minutes) * 60), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.engine?.shutdown() }
        }
    }

    func dismissError() {
        if case .failed = phase { phase = .idle }
    }

    func cancel() {
        job?.cancel()
        engine?.shutdown()
        job = nil
        if isWorking { phase = .idle }
    }

    /// Einen Ablauf starten (immer nur einer zur Zeit). Fehler landen in `phase`.
    func run(_ title: String, _ body: @escaping (HoerspielModel, HSEngine) async throws -> Void) {
        guard !isWorking else { return }
        let e: HSEngine
        do { e = try engineForUse() } catch {
            phase = .failed(StudioModel.message(error))
            return
        }
        notice = nil
        phase = .working(title: title, detail: "Rechenprozess startet …", progress: nil, started: Date())
        job = Task { [weak self] in
            guard let self else { return }
            do {
                try await body(self, e)
                self.phase = .idle
            } catch {
                self.phase = StudioModel.isCancellation(error) || Task.isCancelled ? .idle : .failed(StudioModel.message(error))
            }
            self.job = nil
            self.scheduleIdleShutdown()
        }
    }

    func report(_ detail: String, _ progress: Double?) {
        if case .working(let t, _, _, let s) = phase { phase = .working(title: t, detail: detail, progress: progress, started: s) }
    }

    nonisolated func reporter(prefix: String = "", range: ClosedRange<Double> = 0...1) -> HSEngine.Progress {
        { [weak self] value, text in
            Task { @MainActor in
                let v = range.lowerBound + (range.upperBound - range.lowerBound) * max(0, min(1, value))
                self?.report(prefix + text, v)
            }
        }
    }

    // MARK: Vorhören

    func play(_ url: URL, key: String) {
        guard let preview else { return }
        if playingKey == key {
            preview.stop()
            playingKey = nil
            return
        }
        do {
            try preview.load(url)
            preview.play(from: 0, to: nil)
            playingKey = key
        } catch {
            phase = .failed("Abspielen fehlgeschlagen: \(StudioModel.message(error))")
        }
    }

    func stopPlayback() {
        preview?.stop()
        playingKey = nil
    }

    // MARK: Hilfen für Unterklassen der Abläufe

    func setNotice(_ text: String?) { notice = text }
    func setVoices(_ v: [HSVoiceProfile]) {
        voices = v
        if !demo { try? store.saveVoices(v) }
    }
    func setReferences(_ r: [HSReference]) { references = r }
    func setSFX(_ s: [HSSFXEntry]) {
        sfxLibrary = s
        if !demo { try? store.saveSFX(s) }
    }
    func add(_ p: HSProduction) {
        productions.insert(p, at: 0)
        currentID = p.id
        persist(p)
    }
}
