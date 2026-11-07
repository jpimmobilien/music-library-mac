import SwiftUI
import AppKit

/// Fensterrahmen: verdeckte Titelleiste, Inhalt bis an den Rand, Mindestgröße; meldet die Sichtbarkeit des Fensters,
/// damit die Messungen ruhen, wenn niemand hinsieht.
struct WindowConfigurator: NSViewRepresentable {
    var minSize = Metrics.minWindow
    var onVisibilityChange: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [minSize] in
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = false
            window.minSize = NSSize(width: minSize.width, height: minSize.height)
            window.tabbingMode = .disallowed
            window.collectionBehavior.insert(.fullScreenPrimary)
            context.coordinator.observe(window, onChange: onVisibilityChange)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator {
        private var token: NSObjectProtocol?

        func observe(_ window: NSWindow, onChange: ((Bool) -> Void)?) {
            guard token == nil, let onChange else { return }
            token = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                           object: window, queue: .main) { [weak window] _ in
                guard let window else { return }
                onChange(window.occlusionState.contains(.visible))
            }
        }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }
}

/// Fläche, an der sich das Fenster verschieben lässt (Ersatz für die verdeckte Titelleiste).
/// Doppelklick verhält sich wie auf einer Titelleiste.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "Minimize": window.performMiniaturize(nil)
                case "None": break
                default: window.performZoom(nil)
                }
                return
            }
            window.performDrag(with: event)
        }
    }
}
