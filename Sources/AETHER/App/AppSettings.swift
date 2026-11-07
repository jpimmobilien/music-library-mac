import SwiftUI
import AppKit
import AetherCore

/// Alle Einstellungen, lokal in den UserDefaults der App gespeichert.
@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults
    /// Im Fotomodus des Builds werden Einstellungen nicht gespeichert (die echten des Nutzers bleiben unberührt).
    private let persist: Bool

    @Published var theme: ThemeID { didSet { save(theme.rawValue, "theme") } }
    @Published var accent: AccentChoice { didSet { save(accent.rawValue, "accent") } }
    @Published var glassIntensity: Double { didSet { save(glassIntensity, "glassIntensity") } }
    @Published var motion: MotionLevel { didSet { save(motion.rawValue, "motion") } }
    @Published var density: Density { didSet { save(density.rawValue, "density") } }
    @Published var refreshInterval: RefreshInterval { didSet { save(refreshInterval.rawValue, "refreshInterval") } }
    @Published var lowImpact: Bool { didSet { save(lowImpact, "lowImpact") } }
    @Published var dashboard: DashboardLayout {
        didSet {
            save(dashboard.order.map(\.rawValue), "dashboardOrder")
            save(dashboard.hidden.map(\.rawValue).sorted(), "dashboardHidden")
        }
    }

    init(defaults: UserDefaults = .standard, persist: Bool = true) {
        self.defaults = defaults
        self.persist = persist
        let read: (String) -> Any? = { persist ? defaults.object(forKey: "aether.\($0)") : nil }
        theme = (read("theme") as? String).flatMap(ThemeID.init(rawValue:)) ?? .liquidGlassDark
        accent = (read("accent") as? String).flatMap(AccentChoice.init(rawValue:)) ?? .aetherBlue
        glassIntensity = min(1, max(0, (read("glassIntensity") as? Double) ?? 0.85))
        motion = (read("motion") as? String).flatMap(MotionLevel.init(rawValue:)) ?? .full
        density = (read("density") as? String).flatMap(Density.init(rawValue:)) ?? .standard
        refreshInterval = (read("refreshInterval") as? Int).flatMap(RefreshInterval.init(rawValue:)) ?? .twoSeconds
        lowImpact = (read("lowImpact") as? Bool) ?? false
        dashboard = DashboardLayout.restore(order: (read("dashboardOrder") as? [String]) ?? [],
                                            hidden: (read("dashboardHidden") as? [String]) ?? [])
    }

    var effectiveInterval: RefreshInterval { refreshInterval.effective(lowImpact: lowImpact) }

    private func save(_ value: Any, _ key: String) {
        guard persist else { return }
        defaults.set(value, forKey: "aether.\(key)")
    }

    /// Alle Darstellungseinstellungen zurücksetzen.
    func resetAppearance() {
        theme = .liquidGlassDark
        accent = .aetherBlue
        glassIntensity = 0.85
        motion = .full
        density = .standard
        dashboard = DashboardLayout()
    }

    // MARK: Sprache (pro App, wie in den Systemeinstellungen)

    enum LanguageChoice: String, CaseIterable, Identifiable {
        case system, english = "en", german = "de"
        var id: String { rawValue }
    }

    var languageChoice: LanguageChoice {
        guard let languages = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String],
              let first = languages.first else { return .system }
        return first.hasPrefix("de") ? .german : (first.hasPrefix("en") ? .english : .system)
    }

    func setLanguage(_ choice: LanguageChoice) {
        switch choice {
        case .system: UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .english, .german: UserDefaults.standard.set([choice.rawValue], forKey: "AppleLanguages")
        }
        objectWillChange.send()
    }
}
