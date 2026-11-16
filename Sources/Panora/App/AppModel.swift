import Foundation
import SwiftUI
import Combine
import PanoraCore

enum AppSection: String, CaseIterable, Identifiable {
    case chat, history, models, discover, projects, hardware, storage, settings

    var id: String { rawValue }

    static let primary: [AppSection] = [.chat, .history, .models, .discover, .projects]
    static let system: [AppSection] = [.hardware, .storage, .settings]

    var label: String {
        switch self {
        case .chat: return "Chat"
        case .history: return "Verlauf"
        case .models: return "Modelle"
        case .discover: return "Entdecken"
        case .projects: return "Projekte"
        case .hardware: return "Hardware"
        case .storage: return "Speicher"
        case .settings: return "Einstellungen"
        }
    }

    func icon(selected: Bool) -> String {
        switch self {
        case .chat: return selected ? "bubble.left.and.text.bubble.right.fill" : "bubble.left.and.text.bubble.right"
        case .history: return "clock.arrow.circlepath"
        case .models: return selected ? "cube.fill" : "cube"
        case .discover: return "sparkles"
        case .projects: return selected ? "folder.fill" : "folder"
        case .hardware: return "cpu"
        case .storage: return selected ? "externaldrive.fill" : "externaldrive"
        case .settings: return selected ? "gearshape.fill" : "gearshape"
        }
    }

    var shortcut: KeyEquivalent {
        let all = AppSection.allCases
        let i = all.firstIndex(of: self) ?? 0
        return KeyEquivalent(Character(String(i + 1)))
    }
}

enum LaunchMode: Equatable {
    case normal
    case selfTest(URL)
    case snapshot(URL)
    /// Ende-zu-Ende-Test: echtes MLX-Modell laden und eine Antwort erzeugen (CI).
    case e2e(model: URL, output: URL)

    var isAutomated: Bool { self != .normal }

    static func fromArguments() -> LaunchMode {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--selftest"), i + 1 < args.count { return .selfTest(URL(fileURLWithPath: args[i + 1])) }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count { return .snapshot(URL(fileURLWithPath: args[i + 1])) }
        if let i = args.firstIndex(of: "--e2e"), i + 2 < args.count {
            return .e2e(model: URL(fileURLWithPath: args[i + 1]), output: URL(fileURLWithPath: args[i + 2]))
        }
        return .normal
    }
}

@MainActor
final class AppModel: ObservableObject {
    /// Eine Instanz für App und AppDelegate (Automatikmodi starten ohne auf das Fenster zu warten).
    static let shared = AppModel()

    @Published var section: AppSection = .chat
    @Published var selectedModelID: String?
    @Published var historyGrid = true
    @Published var modelsGrid = true

    let launchMode: LaunchMode
    let settings: AppSettings
    let hardware: HardwareMonitor
    let storage: StorageMonitor
    let network: NetworkMonitor
    let library: ModelLibrary
    let downloads: DownloadManager
    let hub: HubSearch
    let chats: ChatStore
    let projects: ProjectStore
    let engine: InferenceCoordinator
    let experts: ExpertService
    let chat: ChatController

    private var cancellables: Set<AnyCancellable> = []
    private var started = false

    init(launchMode: LaunchMode = LaunchMode.fromArguments()) {
        self.launchMode = launchMode
        let persist = !launchMode.isAutomated
        settings = AppSettings(persist: persist, defaults: persist ? .standard : UserDefaults(suiteName: "panora.automated") ?? .standard)
        hardware = HardwareMonitor()
        storage = StorageMonitor()
        network = NetworkMonitor()
        library = ModelLibrary(settings: settings, persist: persist)
        downloads = DownloadManager(settings: settings, network: network)
        hub = HubSearch()
        chats = ChatStore(persist: persist)
        projects = ProjectStore(persist: persist)
        engine = InferenceCoordinator(settings: settings)
        experts = ExpertService(settings: settings, readKeys: persist)
        chat = ChatController(settings: settings, library: library, engine: engine, hardware: hardware, storage: storage,
                              chats: chats, projects: projects, network: network, experts: experts)
        downloads.library = library
        NSLog("Panora: AppModel bereit")
    }

    var isOffline: Bool { !network.online || settings.forceOffline }

    func start() {
        guard !started else { return }
        started = true
        hardware.start()
        engine.startIdleWatch()
        try? FileManager.default.createDirectory(atPath: AppSettings.defaultModelDirectory, withIntermediateDirectories: true)
        // Laufwerk angeschlossen oder getrennt → Bibliothek neu einlesen (Wiederherstellung nach erneutem Anschließen)
        storage.$mountGeneration.dropFirst().sink { [weak self] _ in
            Task { @MainActor in await self?.library.refresh() }
        }.store(in: &cancellables)
        settings.$modelDirectories.dropFirst().removeDuplicates().sink { [weak self] _ in
            Task { @MainActor in await self?.library.refresh() }
        }.store(in: &cancellables)
        settings.$ollamaEnabled.dropFirst().sink { [weak self] _ in
            Task { @MainActor in await self?.library.refresh() }
        }.store(in: &cancellables)
        Task { await library.refresh() }
    }

    func open(_ section: AppSection) {
        withAnimation(Motion.medium) { self.section = section }
    }

    func openChat(_ id: UUID) {
        chat.open(id)
        open(.chat)
    }

    func newChat() {
        chat.newChat()
        open(.chat)
    }

    /// Empfohlener Modellordner auf der externen SSD (falls vorhanden).
    var suggestedExternalDirectory: String? {
        guard let vol = storage.preferredExternal else { return nil }
        return (vol.path as NSString).appendingPathComponent("Panora/Modelle")
    }

    func useDirectory(_ path: String, asDownloadTarget: Bool) {
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        settings.addModelDirectory(path)
        if asDownloadTarget { settings.downloadDirectory = URL(fileURLWithPath: path).standardizedFileURL.path }
    }

    /// Passt ein Modell (Katalog/Suche) in das Speicherbudget dieses Macs?
    func fit(for sizeBytes: Int64, kvPerToken: Int = 160_000) -> (label: String, ok: Bool?) {
        let budget = Int64(Double(hardware.totalMemory) * settings.modelBudgetFraction)
        let need = Int64(Double(sizeBytes) * 1.04) + Int64(kvPerToken) * 8192 + MemoryPlanner.overheadBytes
        if need <= Int64(Double(budget) * 0.8) { return ("passt", true) }
        if need <= budget { return ("passt knapp", nil) }
        return ("zu groß", false)
    }
}
