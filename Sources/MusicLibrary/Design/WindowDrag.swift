import SwiftUI
import AppKit

/// Fläche, an der sich das Fenster verschieben lässt – Ersatz für die verdeckte Titelleiste, weil der Inhalt
/// bis an den oberen Fensterrand reicht. Doppelklick verhält sich wie auf einer Titelleiste
/// (Systemeinstellung „Doppelklick auf Titelleiste“: Zoomen oder Im Dock ablegen).
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
