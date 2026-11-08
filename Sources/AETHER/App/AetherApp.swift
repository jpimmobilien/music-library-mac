import SwiftUI
import AppKit
import Combine
import AetherCore

@main
struct AetherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("AETHER", id: "main") {
            RootView()
                .environmentObject(model)
                .environmentObject(model.settings)
                .onAppear { appDelegate.attach(model) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 800)
        .commands { AppCommands(model: model) }

        Window(tr("Live Monitor"), id: "live-monitor") {
            LiveMonitorView()
                .environmentObject(model)
                .environmentObject(model.settings)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)
        // Menüleisten-Anzeige: AppKit-Statusobjekt (StatusItemController) – bewusst kein `MenuBarExtra`, siehe dort.
    }
}

/// Lebenszyklus: Erscheinungsbild anwenden, Messungen starten, Automatikmodi im Build.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?
    private var attached = false
    private var cancellables: Set<AnyCancellable> = []
    private var statusItem: StatusItemController?

    func attach(_ model: AppModel) {
        guard !attached else { return }
        attached = true
        self.model = model
        model.settings.$theme
            .sink { theme in
                switch ThemeCatalog.spec(theme).appearance {
                case .system: NSApp.appearance = nil
                case .light: NSApp.appearance = NSAppearance(named: .aqua)
                case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
                }
            }
            .store(in: &cancellables)
        model.settings.$refreshInterval
            .combineLatest(model.settings.$lowImpact)
            .dropFirst()
            .sink { [weak model] _, _ in
                Task { @MainActor in model?.intervalChanged() }
            }
            .store(in: &cancellables)
        model.settings.$historyEnabled
            .combineLatest(model.settings.$historyRetentionDays)
            .sink { [weak model] enabled, days in
                guard let model else { return }
                model.engine.history.configure(enabled: enabled, retentionDays: days, allowed: !model.launchMode.isAutomated)
            }
            .store(in: &cancellables)
        model.settings.$smcEnabled
            .sink { [weak model] enabled in model?.engine.setSMCEnabled(enabled) }
            .store(in: &cancellables)
        model.settings.$showRawValues
            .sink { [weak model] raw in model?.engine.telemetry.showRaw = raw }
            .store(in: &cancellables)
        model.settings.$diagnosticsEnabled
            .sink { [weak model] enabled in model?.engine.diagnostics.enabled = enabled }
            .store(in: &cancellables)
        model.settings.$menuBarEnabled
            .dropFirst()
            .sink { [weak model] _ in
                Task { @MainActor in model?.menuBarSettingChanged() }
            }
            .store(in: &cancellables)
        // Menüleiste nur auf Wunsch (Einstellungen) und nie in den Automatikmodi des Builds
        let statusItem = StatusItemController(model: model)
        self.statusItem = statusItem
        let automated = model.launchMode.isAutomated
        model.settings.$menuBarEnabled
            .removeDuplicates()
            .sink { [weak statusItem] enabled in statusItem?.setEnabled(enabled && !automated) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didHideNotification)
            .sink { [weak model] _ in model?.setAppActive(false) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didUnhideNotification)
            .sink { [weak model] _ in model?.setAppActive(true) }
            .store(in: &cancellables)

        switch model.launchMode {
        case .normal:
            model.start()
        case .selfTest(let output):
            Task { @MainActor in
                await SelfTest.run(model: model, output: output)
                NSApp.terminate(nil)
            }
        case .snapshot(let directory):
            Task { @MainActor in
                await SnapshotRunner.run(model: model, output: directory)
                NSApp.terminate(nil)
            }
        }
    }

    /// Normal: Schließen des Fensters beendet AETHER (kein versteckter Hintergrundbetrieb).
    /// Selbsttest und Bildschirmfotos blenden Fenster aus und beenden sich selbst, sobald sie fertig sind.
    /// Mit Menüleisten-Anzeige läuft AETHER weiter, bis „Beenden“ gewählt wird.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !LaunchMode.fromArguments().isAutomated && !(model?.settings.menuBarEnabled ?? false)
    }

    /// Angefangene Verlaufsminute noch speichern.
    func applicationWillTerminate(_ notification: Notification) {
        model?.engine.history.flushNow()
    }
}

/// Menübefehle mit den üblichen Kurzbefehlen.
struct AppCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(tr("Settings…")) { model.select(.settings) }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(replacing: .newItem) {}
        CommandMenu(tr("Go")) {
            ForEach(AppSection.allCases.filter { $0 != .settings }) { section in
                if let key = section.shortcut {
                    Button(section.title) { model.select(section) }
                        .keyboardShortcut(key, modifiers: .command)
                }
            }
        }
        CommandGroup(after: .windowArrangement) {
            OpenLiveMonitorButton()
        }
        CommandGroup(after: .sidebar) {
            Button(model.sidebarVisible ? tr("Hide Sidebar") : tr("Show Sidebar")) {
                model.sidebarVisible.toggle()
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
        }
    }
}
