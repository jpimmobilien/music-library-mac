import SwiftUI
import AppKit
import Combine

@main
struct PanoraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("Panora", id: "main") {
            RootView()
                .environmentObject(model)
                .environmentObject(model.settings)
                .onAppear { appDelegate.attach(model) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Neuer Chat") { model.newChat() }.keyboardShortcut("n")
            }
            CommandMenu("Bereiche") {
                ForEach(AppSection.allCases) { s in
                    Button(s.label) { model.open(s) }.keyboardShortcut(s.shortcut, modifiers: .command)
                }
            }
            CommandMenu("Modelle") {
                Button("Antwort stoppen") { model.chat.stop() }.keyboardShortcut(".", modifiers: .command)
                Button("Alle Modelle entladen") { Task { await model.engine.unloadAll() } }
                Button("Bibliothek neu einlesen") { Task { await model.library.refresh() } }.keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var cancellables: Set<AnyCancellable> = []
    private var attached = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("Panora: Start abgeschlossen (%@)", String(describing: AppModel.shared.launchMode))
        // Automatikmodi und Dienste unabhängig vom ersten Erscheinen des Fensters starten
        attach(AppModel.shared)
    }

    func attach(_ model: AppModel) {
        guard !attached else { return }
        attached = true
        NSLog("Panora: Dienste werden gestartet")
        model.settings.$appearance
            .sink { mode in
                switch mode {
                case .system: NSApp.appearance = nil
                case .light: NSApp.appearance = NSAppearance(named: .aqua)
                case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
                }
            }
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
        case .e2e(let modelURL, let output):
            Task { @MainActor in
                await SelfTest.runE2E(model: model, modelFolder: modelURL, output: output)
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        LaunchMode.fromArguments() == .normal
    }
}

/// Transparente Titelleiste, Inhalt bis unter die Ampel, Mindestgröße.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.minSize = NSSize(width: 1080, height: 700)
            window.tabbingMode = .disallowed
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
