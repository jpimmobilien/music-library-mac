import AppKit
import SwiftUI
import Combine
import AetherCore

// =============================================================================================
// Menüleisten-Anzeige als AppKit-Statusobjekt (statt SwiftUI `MenuBarExtra`).
//
// Grund (gemessen im Selbsttest, Profil mit /usr/bin/sample): Die Beschriftung eines `MenuBarExtra` gehört zum
// App-Graphen von SwiftUI. Jede Änderung – die CPU-Anzeige ändert sich jede Sekunde – meldet „Szenen geändert“, und
// SwiftUI wertet daraufhin die gesamte Ansicht JEDES offenen Fensters neu aus (Präferenzwerte). Das kostete fast einen
// ganzen CPU-Kern, auch wenn die Menüleisten-Anzeige ausgeschaltet war. Hier wird nur der Titel des Knopfs gesetzt.
// =============================================================================================

@MainActor
final class StatusItemController: NSObject {
    private var item: NSStatusItem?
    private var popover: NSPopover?
    private weak var model: AppModel?
    private var cancellables: Set<AnyCancellable> = []
    private var title = ""

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func setEnabled(_ enabled: Bool) {
        if enabled { install() } else { remove() }
    }

    private func install() {
        guard item == nil, let model else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "AETHER")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.target = self
            button.action = #selector(togglePanel(_:))
            button.toolTip = "AETHER"
        }
        self.item = item
        title = ""
        // CPU-Anzeige wie in der App (geglättet bzw. roh); geschrieben wird nur bei sichtbarer Änderung
        let metric = model.engine.telemetry.value(.cpuTotal)
        metric.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self, weak metric] _ in
                guard let metric else { return }
                self?.updateTitle(metric)
            }
            .store(in: &cancellables)
        model.settings.$showRawValues
            .receive(on: RunLoop.main)
            .sink { [weak self, weak metric] _ in
                guard let metric else { return }
                self?.updateTitle(metric)
            }
            .store(in: &cancellables)
        updateTitle(metric)
    }

    private func remove() {
        cancellables.removeAll()
        popover?.performClose(nil)
        popover = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    private func updateTitle(_ metric: MetricValue) {
        guard let model, let button = item?.button else { return }
        let value = metric.isAvailable ? metric.display(raw: model.settings.showRawValues) : nil
        let text = value.map { fmt.percent($0) } ?? "–"
        guard text != title else { return }
        title = text
        button.title = text
        button.setAccessibilityLabel(tr("CPU %@", text))
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        if let popover, popover.isShown {
            popover.performClose(sender)
            return
        }
        guard let model else { return }
        let popover = self.popover ?? makePopover(model: model)
        self.popover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makePopover(model: AppModel) -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: MenuBarPanel()
            .environmentObject(model)
            .environmentObject(model.settings))
        return popover
    }
}
