import SwiftUI
import AppKit
import Combine
import ABCore

@main
struct AndroidBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Android Bridge", id: "main") {
            RootView(settings: model.settings, transfers: model.transfers)
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear {
                    appDelegate.attach(model)
                }
        }
        .defaultSize(width: 1320, height: 840)
        .commands { AppCommands(model: model, files: model.files) }

        WindowGroup("Gerät", id: "device", for: UInt64.self) { $deviceID in
            DeviceWindowView(deviceID: deviceID)
                .environmentObject(model)
                .frame(minWidth: 860, minHeight: 560)
        }
        .defaultSize(width: 1100, height: 720)

        Settings {
            SettingsView(settings: model.settings, favorites: model.favorites, recents: model.recents, history: model.history)
        }
    }
}

/// App-Lebenszyklus: Start der USB-Überwachung, Aufräumen, Automatikmodi im Build.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?
    private var started = false
    private var cancellables: Set<AnyCancellable> = []

    func attach(_ model: AppModel) {
        guard !started else { return }
        started = true
        self.model = model
        model.settings.$appearance
            .sink { mode in
                switch mode {
                case .system: NSApp.appearance = nil
                case .light: NSApp.appearance = NSAppearance(named: .aqua)
                case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
                }
            }
            .store(in: &cancellables)
        model.start()
        Diagnostics.shared.log(.app, "Gestartet: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"), \(SystemInfo.architecture), macOS \(ProcessInfo.processInfo.operatingSystemVersionString), Liquid Glass: \(LiquidGlass.isAvailable ? "ja" : "nein")")
        switch model.launchMode {
        case .snapshot(let dir):
            Task { @MainActor in
                await SnapshotRunner.run(model: model, output: dir)
                NSApp.terminate(nil)
            }
        case .selfTest(let file):
            Task { @MainActor in
                await SelfTest.run(model: model, output: file)
                NSApp.terminate(nil)
            }
        case .normal:
            break
        }
    }

    /// Weiterlaufen nach dem Schließen des Fensters, damit angeschlossene Telefone erkannt werden.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if case .normal = LaunchMode.current { return false }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, case .normal = model.launchMode else { return .terminateNow }
        let running = model.transfers.activeCount
        if running > 0 {
            let alert = NSAlert()
            alert.messageText = "Übertragungen laufen noch"
            alert.informativeText = "Beim Beenden werden \(running) laufende Übertragungen abgebrochen. Unvollständige Dateien werden entfernt."
            alert.addButton(withTitle: "Weiterlaufen lassen")
            alert.addButton(withTitle: "Beenden")
            if alert.runModal() == .alertFirstButtonReturn { return .terminateCancel }
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown()
        AppPaths.clearPreviewCache()
    }
}

/// Menübefehle und Tastenkürzel (wirken auf die aktive Spalte des Dateimanagers).
struct AppCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject var files: FileManagerModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Neuer Ordner") {
                model.selection = .files
                files.requestNewFolder()
            }
            .keyboardShortcut("n")
        }
        CommandGroup(replacing: .textEditing) {
            Button("Suchen") {
                if model.selection != .files && model.selection != .media { model.selection = .files }
                files.focusSearch()
            }
            .keyboardShortcut("f")
        }
        CommandGroup(after: .sidebar) {
            Button("Aktualisieren") { files.refresh() }
                .keyboardShortcut("r")
            Divider()
            Button("Zwei Spalten") { files.layout = .dual; model.selection = .files }
                .keyboardShortcut("1")
            Button("Eine Spalte") { files.layout = .single; model.selection = .files }
                .keyboardShortcut("2")
            Button("Galerie") { files.layout = .gallery; model.selection = .files }
                .keyboardShortcut("3")
            Divider()
        }
        CommandMenu("Gehe zu") {
            Button("Zurück") { files.activePane == .device ? files.device.back() : files.local.back() }
                .keyboardShortcut("[")
            Button("Vor") { files.activePane == .device ? files.device.forward() : files.local.forward() }
                .keyboardShortcut("]")
            Button("Übergeordneter Ordner") { files.activePane == .device ? files.device.goUp() : files.local.goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Öffnen") { files.openSelection() }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Divider()
            Button("Übersicht") { model.selection = .overview }
                .keyboardShortcut("0", modifiers: [.command, .option])
            Button("Dateimanager") { model.selection = .files }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button("Fotos & Videos") { model.selection = .media }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Button("Übertragungen") { model.selection = .transfers }
                .keyboardShortcut("3", modifiers: [.command, .option])
        }
        CommandMenu("Auswahl") {
            Button("Auswahl übertragen") {
                if files.activePane == .device { files.transferDeviceSelectionToMac() } else { files.transferLocalSelectionToDevice() }
            }
            .keyboardShortcut("t")
            Divider()
            Button("Auswahl aufheben") { files.deselectAll() }
                .keyboardShortcut("a", modifiers: [.command, .option])
            Button("Auswahl umkehren") { files.invertSelection() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Divider()
            Button("Umbenennen …") { files.renamePane = files.activePane }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
            Button("Löschen …") { files.requestDelete() }
                .keyboardShortcut(.delete, modifiers: .command)
        }
        CommandGroup(after: .help) {
            Button("Diagnose …") { model.showDiagnostics = true }
        }
    }
}

/// Eigenes Fenster für ein Gerät (mehrere Geräte nebeneinander).
struct DeviceWindowView: View {
    @EnvironmentObject private var model: AppModel
    let deviceID: UInt64?

    var body: some View {
        if let id = deviceID, let device = model.devices.device(id: id) {
            DeviceWindowContent(model: model, device: device)
        } else {
            EmptyStateView(symbol: "cable.connector.slash", title: "Gerät nicht verbunden",
                           message: "Dieses Fenster gehört zu einem Gerät, das nicht mehr angeschlossen ist.")
                .background(AmbientBackground())
        }
    }
}

private struct DeviceWindowContent: View {
    let model: AppModel
    @ObservedObject var device: DeviceConnection
    @ObservedObject var settings: SettingsStore
    @StateObject private var files: FileManagerModel

    init(model: AppModel, device: DeviceConnection) {
        self.model = model
        self.device = device
        self.settings = model.settings
        _files = StateObject(wrappedValue: FileManagerModel(settings: model.settings, transfers: model.transfers, recents: model.recents))
    }

    var body: some View {
        FileManagerView(files: files, settings: settings)
            .environment(\.glassEnabled, settings.glassEffects)
            .environment(\.animationsEnabled, settings.animations)
            .tint(settings.accent.color)
            .background(AmbientBackground())
            .navigationTitle(device.displayName)
            .onAppear { if device.state == .connected { files.device.attach(device) } }
            .onChange(of: device.state) { s in if s == .connected { files.device.attach(device) } }
    }
}
