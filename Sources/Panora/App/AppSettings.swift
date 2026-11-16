import Foundation
import SwiftUI
import PanoraCore

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Hell"
        case .dark: return "Dunkel"
        }
    }
}

/// Einstellungen (UserDefaults). Im Fotomodus des Builds wird nichts gespeichert.
@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults
    private let persist: Bool

    @Published var appearance: AppearanceMode { didSet { save(appearance.rawValue, "appearance") } }
    @Published var glassEffects: Bool { didSet { save(glassEffects, "glassEffects") } }
    @Published var defaultMode: RoutingMode { didSet { save(defaultMode.rawValue, "defaultMode") } }
    @Published var allowSwitchInManual: Bool { didSet { save(allowSwitchInManual, "allowSwitchInManual") } }
    @Published var stickiness: Double { didSet { save(stickiness, "stickiness") } }
    @Published var modelBudgetFraction: Double { didSet { save(modelBudgetFraction, "modelBudgetFraction") } }
    @Published var idleUnloadMinutes: Int { didSet { save(idleUnloadMinutes, "idleUnloadMinutes") } }
    @Published var maxContextTokens: Int { didSet { save(maxContextTokens, "maxContextTokens") } }
    @Published var maxAnswerTokens: Int { didSet { save(maxAnswerTokens, "maxAnswerTokens") } }
    @Published var temperature: Double { didSet { save(temperature, "temperature") } }
    @Published var showReasoning: Bool { didSet { save(showReasoning, "showReasoning") } }
    @Published var showRoutingDetails: Bool { didSet { save(showRoutingDetails, "showRoutingDetails") } }
    @Published var modelDirectories: [String] { didSet { save(modelDirectories, "modelDirectories") } }
    @Published var downloadDirectory: String { didSet { save(downloadDirectory, "downloadDirectory") } }
    @Published var ollamaEnabled: Bool { didSet { save(ollamaEnabled, "ollamaEnabled") } }
    @Published var ollamaURL: String { didSet { save(ollamaURL, "ollamaURL") } }
    @Published var expertsEnabled: Bool { didSet { save(expertsEnabled, "expertsEnabled") } }
    @Published var openAIModel: String { didSet { save(openAIModel, "openAIModel") } }
    @Published var anthropicModel: String { didSet { save(anthropicModel, "anthropicModel") } }
    @Published var forceOffline: Bool { didSet { save(forceOffline, "forceOffline") } }
    /// Gemessene Lesegeschwindigkeit je Laufwerk (GB/s).
    @Published var diskReadGBs: [String: Double] { didSet { save(diskReadGBs, "diskReadGBs") } }
    /// Gemessene Token-Rate je Modell auf diesem Mac.
    @Published var measuredTokensPerSecond: [String: Double] { didSet { save(measuredTokensPerSecond, "measuredTPS") } }
    @Published var onboardingDone: Bool { didSet { save(onboardingDone, "onboardingDone") } }

    static var defaultModelDirectory: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Panora/Modelle").path
    }

    init(persist: Bool = true, defaults: UserDefaults = .standard) {
        self.persist = persist
        self.defaults = defaults
        let d = defaults
        appearance = AppearanceMode(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        glassEffects = d.object(forKey: "glassEffects") as? Bool ?? true
        defaultMode = RoutingMode(rawValue: d.string(forKey: "defaultMode") ?? "") ?? .auto
        allowSwitchInManual = d.object(forKey: "allowSwitchInManual") as? Bool ?? false
        stickiness = d.object(forKey: "stickiness") as? Double ?? 0.45
        modelBudgetFraction = d.object(forKey: "modelBudgetFraction") as? Double ?? 0.70
        idleUnloadMinutes = d.object(forKey: "idleUnloadMinutes") as? Int ?? 20
        maxContextTokens = d.object(forKey: "maxContextTokens") as? Int ?? 32_768
        maxAnswerTokens = d.object(forKey: "maxAnswerTokens") as? Int ?? 4096
        temperature = d.object(forKey: "temperature") as? Double ?? 0.6
        showReasoning = d.object(forKey: "showReasoning") as? Bool ?? true
        showRoutingDetails = d.object(forKey: "showRoutingDetails") as? Bool ?? true
        modelDirectories = d.stringArray(forKey: "modelDirectories") ?? [AppSettings.defaultModelDirectory]
        downloadDirectory = d.string(forKey: "downloadDirectory") ?? AppSettings.defaultModelDirectory
        ollamaEnabled = d.object(forKey: "ollamaEnabled") as? Bool ?? true
        ollamaURL = d.string(forKey: "ollamaURL") ?? "http://127.0.0.1:11434"
        expertsEnabled = d.object(forKey: "expertsEnabled") as? Bool ?? false
        openAIModel = d.string(forKey: "openAIModel") ?? ExpertProvider.openAI.defaultModel
        anthropicModel = d.string(forKey: "anthropicModel") ?? ExpertProvider.anthropic.defaultModel
        forceOffline = d.object(forKey: "forceOffline") as? Bool ?? false
        diskReadGBs = d.dictionary(forKey: "diskReadGBs") as? [String: Double] ?? [:]
        measuredTokensPerSecond = d.dictionary(forKey: "measuredTPS") as? [String: Double] ?? [:]
        onboardingDone = d.object(forKey: "onboardingDone") as? Bool ?? false
    }

    private func save(_ value: Any, _ key: String) {
        guard persist else { return }
        defaults.set(value, forKey: key)
    }

    func expertModel(_ provider: ExpertProvider) -> String {
        provider == .openAI ? openAIModel : anthropicModel
    }

    func addModelDirectory(_ path: String) {
        let clean = URL(fileURLWithPath: path).standardizedFileURL.path
        if !modelDirectories.contains(clean) { modelDirectories.append(clean) }
    }
}
