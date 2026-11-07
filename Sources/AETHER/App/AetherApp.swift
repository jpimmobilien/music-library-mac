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
    }
}

/// Lebenszyklus: Erscheinungsbild anwenden, Messungen starten, Automatikmodi im Build.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?
    private var attached = false
    private var cancellables: Set<AnyCancellable> = []

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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
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
        CommandGroup(after: .sidebar) {
            Button(model.sidebarVisible ? tr("Hide Sidebar") : tr("Show Sidebar")) {
                model.sidebarVisible.toggle()
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
        }
    }
}
