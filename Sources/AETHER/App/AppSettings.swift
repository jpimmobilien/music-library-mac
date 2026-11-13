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
    /// ORBIT-Effektprofil: Minimal (Leistungsmodus), Ausgewogen (Standard), Immersiv.
    @Published var effectProfile: EffectProfile { didSet { save(effectProfile.rawValue, "effectProfile") } }
    @Published var density: Density { didSet { save(density.rawValue, "density") } }
    @Published var refreshInterval: RefreshInterval { didSet { save(refreshInterval.rawValue, "refreshInterval") } }
    @Published var lowImpact: Bool { didSet { save(lowImpact, "lowImpact") } }
    /// Temperaturen und Lüfter über das SMC lesen (nur lesend, undokumentiertes Protokoll – siehe Konzept 8.3).
    @Published var smcEnabled: Bool { didSet { save(smcEnabled, "smcEnabled") } }
    /// Anzeige in der Menüleiste (misst dann auch bei geschlossenem Fenster, höchstens alle 5 s).
    @Published var menuBarEnabled: Bool { didSet { save(menuBarEnabled, "menuBarEnabled") } }
    /// Rohwerte statt geglätteter Anzeige (Monitoring 2.0).
    @Published var showRawValues: Bool { didSet { save(showRawValues, "showRawValues") } }
    /// Entwickler-Diagnose: Eigenverbrauch, Takt, Verarbeitungsdauer.
    @Published var diagnosticsEnabled: Bool { didSet { save(diagnosticsEnabled, "diagnosticsEnabled") } }
    /// Live-Monitor schwebt über anderen Fenstern.
    @Published var liveMonitorOnTop: Bool { didSet { save(liveMonitorOnTop, "liveMonitorOnTop") } }
    /// Lokaler Verlauf (Opt-in, standardmäßig aus) und seine Aufbewahrungsdauer in Tagen.
    @Published var historyEnabled: Bool { didSet { save(historyEnabled, "historyEnabled") } }
    @Published var historyRetentionDays: Int { didSet { save(historyRetentionDays, "historyRetentionDays") } }
    static let historyRetentionChoices = [1, 7, 30, 90]
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
        effectProfile = (read("effectProfile") as? String).flatMap(EffectProfile.init(rawValue:)) ?? .balanced
        density = (read("density") as? String).flatMap(Density.init(rawValue:)) ?? .standard
        // Ab Version 2 der Einstellungen ist der Grundtakt 1 s (die Anzeige wird geglättet, einzelne Quellen haben
        // eigene, längere Takte). Ältere gespeicherte 2-s-Takte werden einmalig umgestellt.
        let storedInterval = (read("refreshInterval") as? Int).flatMap(RefreshInterval.init(rawValue:))
        let settingsVersion = (read("settingsVersion") as? Int) ?? 1
        refreshInterval = settingsVersion < 2 && storedInterval == .twoSeconds ? .oneSecond : (storedInterval ?? .oneSecond)
        lowImpact = (read("lowImpact") as? Bool) ?? false
        smcEnabled = (read("smcEnabled") as? Bool) ?? true
        menuBarEnabled = (read("menuBarEnabled") as? Bool) ?? false
        showRawValues = (read("showRawValues") as? Bool) ?? false
        diagnosticsEnabled = (read("diagnosticsEnabled") as? Bool) ?? false
        liveMonitorOnTop = (read("liveMonitorOnTop") as? Bool) ?? true
        historyEnabled = (read("historyEnabled") as? Bool) ?? false
        historyRetentionDays = (read("historyRetentionDays") as? Int).flatMap { AppSettings.historyRetentionChoices.contains($0) ? $0 : nil } ?? 7
        dashboard = DashboardLayout.restore(order: (read("dashboardOrder") as? [String]) ?? [],
                                            hidden: (read("dashboardHidden") as? [String]) ?? [])
        if persist && settingsVersion < 2 {
            defaults.set(refreshInterval.rawValue, forKey: "aether.refreshInterval")
            defaults.set(2, forKey: "aether.settingsVersion")
        }
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
        effectProfile = .balanced
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
