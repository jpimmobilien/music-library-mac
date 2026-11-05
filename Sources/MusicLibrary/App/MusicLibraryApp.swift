import SwiftUI
import AppKit
import MLCore
import MLStore

@main
struct MusicLibraryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model: AppModel = AppDelegate.makeModel()

    var body: some Scene {
        WindowGroup("Music Library", id: "main") {
            ThemedRoot(model: model) {
                MainWindow()
                    .frame(minWidth: 900, minHeight: 620)
                    .background(WindowRegistrar())
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 840)
        .commands { AppCommands(model: model) }

        Window("Informationen", id: "editor") {
            ThemedRoot(model: model) { EditorWindowRoot() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 780, height: 780)

        Window("Mini-Player", id: "mini") {
            ThemedRoot(model: model) { MiniPlayerWindow() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Window("Equalizer", id: "equalizer") {
            ThemedRoot(model: model) { EqualizerWindow() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Settings {
            ThemedRoot(model: model) { SettingsView() }
        }

        MenuBarExtra {
            ThemedRoot(model: model) { MenuBarPlayer() }
        } label: {
            Image(nsImage: NSImage.icon("vinyl", size: 16))
        }
        .menuBarExtraStyle(.window)
    }
}

/// Setzt Farbsatz, Erscheinungsbild (Hell/Dunkel/System) und Umgebungsobjekte für jedes Fenster.
struct ThemedRoot<Content: View>: View {
    @ObservedObject var model: AppModel
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .environmentObject(model)
            .environmentObject(model.player)
            .environmentObject(model.metadata)
            .musicTheme(glass: model.settings.glassEffects)
            .preferredColorScheme(model.settings.themeMode == .system ? nil : (model.settings.themeMode == .dark ? .dark : .light))
    }
}

/// Meldet die Fenster-Öffner (openWindow) an den `WindowRouter`, damit Menüs und Tastatur Fenster öffnen können.
private struct WindowRegistrar: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .onAppear {
                WindowRouter.shared.openEditorAction = { openWindow(id: "editor") }
                WindowRouter.shared.openMiniPlayerAction = { openWindow(id: "mini") }
                WindowRouter.shared.openEqualizerAction = { openWindow(id: "equalizer") }
            }
    }
}

// MARK: - App-Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    /// Erzeugt den App-Zustand (Datenbank in „Application Support/Music Library“).
    @MainActor
    static func makeModel() -> AppModel {
        if let existing = AppModel.shared { return existing }
        if SnapshotRunner.isRequested {
            return SnapshotRunner.makeDemoModel()
        }
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Music Library", isDirectory: true)
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        let dbURL = support.appendingPathComponent("Library.sqlite")
        do {
            let store = try LibraryStore(path: dbURL.path)
            // (SQLiteError hat keinen öffentlichen Initialisierer – daher ein Foundation-Fehler)
            if store.integrityCheck() != "ok" { throw CocoaError(.fileReadCorruptFile) }
            return AppModel(store: store)
        } catch {
            // Beschädigte Datenbank: beiseitelegen (nicht löschen) und neu beginnen
            let broken = support.appendingPathComponent("Library-defekt-\(Int(Date().timeIntervalSince1970)).sqlite")
            try? fm.moveItem(at: dbURL, to: broken)
            let store = (try? LibraryStore(path: dbURL.path)) ?? (try! LibraryStore.inMemory())
            let model = AppModel(store: store)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                model.toast("Die Bibliotheksdatenbank war beschädigt und wurde neu angelegt. Die alte Datei liegt unter „\(broken.lastPathComponent)“.", isError: true)
            }
            return model
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            let model = AppDelegate.makeModel()
            if SnapshotRunner.isRequested {
                SnapshotRunner.run(model: model)
                return
            }
            model.reloadLibrary()
            model.library.start()
            model.metadata.cleanupBackups(days: model.settings.backupRetentionDays)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { model.player.restoreState() }
            self.installKeyMonitor(model: model)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for w in sender.windows where w.identifier?.rawValue.hasPrefix("main") == true || w.title == "Music Library" {
                w.makeKeyAndOrderFront(nil)
                return false
            }
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared?.player.shutdown()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        guard let player = AppModel.shared?.player else { return menu }
        if let t = player.current {
            let title = NSMenuItem(title: "\(t.displayTitle) – \(t.artistText ?? "")", action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
            menu.addItem(.separator())
        }
        menu.addItem(DockAction(title: player.isPlaying ? "Pause" : "Abspielen") { player.togglePlay() }.item)
        menu.addItem(DockAction(title: "Nächster Titel") { player.next() }.item)
        menu.addItem(DockAction(title: "Vorheriger Titel") { player.previous() }.item)
        return menu
    }

    /// Tastaturbedienung außerhalb von Textfeldern (Leertaste, Eingabe, Pfeile, Löschen, ⌘A, Esc).
    @MainActor
    private func installKeyMonitor(model: AppModel) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // In Textfeldern bleibt alles beim Alten
            if let responder = event.window?.firstResponder, responder is NSText || responder is NSTextView { return event }
            guard event.window?.isKeyWindow == true else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let list = KeyboardFocus.shared.activeList
            switch event.keyCode {
            case 49 where flags.isEmpty: // Leertaste
                model.player.togglePlay()
                return nil
            case 36 where flags.isEmpty, 76 where flags.isEmpty: // Eingabe
                if let list { list.playSelection(); return nil }
            case 51 where flags.isEmpty || flags == .command, 117 where flags.isEmpty: // Löschen
                if let list { list.deleteSelection(); return nil }
            case 126 where flags.isEmpty || flags == .shift: // ↑
                if let list { list.moveSelection(-1, flags.contains(.shift)); return nil }
            case 125 where flags.isEmpty || flags == .shift: // ↓
                if let list { list.moveSelection(1, flags.contains(.shift)); return nil }
            case 0 where flags == .command: // ⌘A
                if let list { list.selectAll(); return nil }
            case 34 where flags == .command: // ⌘I
                let uids = list?.selectedUids() ?? []
                if !uids.isEmpty { model.showInfo(uids) } else if let c = model.player.current { model.showInfo([c.uid]) }
                return nil
            case 53: // Esc
                if model.playerOpen { model.playerOpen = false; return nil }
                if model.sidePanel != nil { model.sidePanel = nil; return nil }
            default:
                break
            }
            return event
        }
    }
}

/// Kleine Hilfe für Dock-Menüeinträge mit Closure.
@MainActor
final class DockAction: NSObject {
    let item: NSMenuItem
    private let action: () -> Void
    private static var retained: [DockAction] = []

    init(title: String, action: @escaping () -> Void) {
        self.action = action
        self.item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        super.init()
        item.target = self
        item.action = #selector(run)
        DockAction.retained.append(self)
        if DockAction.retained.count > 30 { DockAction.retained.removeFirst(10) }
    }

    @objc private func run() { action() }
}

// MARK: - Menüs

struct AppCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Neue Playlist …") { NewPlaylistDialog.present(model: model, trackUids: []) }
                .keyboardShortcut("n", modifiers: .command)
            Button("Musikordner hinzufügen …") { model.library.chooseFolders() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Bibliothek neu einlesen") { model.library.rescan(reason: "Menü") }
                .keyboardShortcut("r", modifiers: .command)
        }
        CommandGroup(after: .undoRedo) {
            Divider()
            Button("Letzte Metadaten-Änderung widerrufen") { model.metadata.undoLast() }
                .keyboardShortcut("z", modifiers: [.command, .option])
                .disabled(!model.metadata.canUndo)
        }
        CommandGroup(after: .textEditing) {
            Button("Suchen") { model.searchFocusRequest += 1 }
                .keyboardShortcut("f", modifiers: .command)
        }
        CommandMenu("Darstellung") {
            ForEach(LibrarySection.allCases, id: \.self) { s in
                Button(s.label) { model.playerOpen = false; model.select(s) }
                    .keyboardShortcut(KeyEquivalent(s.shortcutDigit), modifiers: .command)
            }
            Divider()
            Button(model.playerOpen ? "Player schließen" : "Player öffnen") { model.playerOpen.toggle() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(model.player.current == nil)
            Button("Warteschlange") { model.sidePanel = model.sidePanel == .queue ? nil : .queue }
                .keyboardShortcut("u", modifiers: [.command, .option])
            Button("Liedtext") { model.sidePanel = model.sidePanel == .lyrics ? nil : .lyrics }
                .keyboardShortcut("l", modifiers: .command)
            Divider()
            Button("Mini-Player") { WindowRouter.shared.openMiniPlayer() }
                .keyboardShortcut("m", modifiers: [.command, .option])
            Button("Equalizer") { WindowRouter.shared.openEqualizer() }
                .keyboardShortcut("e", modifiers: [.command, .option])
            Divider()
            Button("Zurück") { model.back() }
                .keyboardShortcut("[", modifiers: .command)
        }
        // Gruppen: ViewBuilder erlaubt bei Zielsystem macOS 13 höchstens 10 direkte Elemente je Block.
        CommandMenu("Steuerung") {
            Group {
                Button(model.player.isPlaying ? "Pause (Leertaste)" : "Abspielen (Leertaste)") { model.player.togglePlay() }
                Button("Nächster Titel") { model.player.next() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Vorheriger Titel") { model.player.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("10 Sekunden vor") { model.player.skip(by: 10) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                Button("10 Sekunden zurück") { model.player.skip(by: -10) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            }
            Divider()
            Group {
                Button("Lauter") { adjustVolume(0.05) }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Button("Leiser") { adjustVolume(-0.05) }
                    .keyboardShortcut(.downArrow, modifiers: .command)
            }
            Divider()
            Button(model.player.shuffleEnabled ? "Zufallswiedergabe aus" : "Zufallswiedergabe an") { model.player.toggleShuffle() }
                .keyboardShortcut("s", modifiers: [.command, .option])
            Menu("Wiederholen") {
                ForEach(RepeatSetting.allCases, id: \.self) { r in
                    Button((model.player.repeatMode == r ? "✓ " : "") + r.label) { model.player.setRepeat(r) }
                }
            }
            Menu("Sleep-Timer") {
                ForEach(SleepTimerLogic.presetMinutes, id: \.self) { m in
                    Button("\(m) Minuten") { model.player.startSleepTimer(minutes: m) }
                }
                Button("Am Ende des Titels") { model.player.sleepAtEndOfTrack() }
                Divider()
                Button("Ausschalten") { model.player.cancelSleepTimer() }
                    .disabled(model.player.sleepTimer == nil)
            }
            Divider()
            Button("Aktuellen Titel zu Favoriten") {
                if let c = model.player.current { model.toggleFavorite([c.uid]) }
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(model.player.current == nil)
            Button("Informationen …") {
                let uids = KeyboardFocus.shared.activeList?.selectedUids() ?? []
                if !uids.isEmpty { model.showInfo(uids) } else if let c = model.player.current { model.showInfo([c.uid]) }
            }
            .keyboardShortcut("i", modifiers: .command)
        }
    }

    @MainActor
    private func adjustVolume(_ delta: Float) {
        let v = min(AudioEffectsSettings.maxVolume, max(0, model.player.liveVolume + delta))
        model.player.setLiveVolume(v)
        model.settings.effects.volume = v
    }
}
