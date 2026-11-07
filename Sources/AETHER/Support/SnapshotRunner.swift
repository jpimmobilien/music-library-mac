import SwiftUI
import AppKit
import AetherCore

// =============================================================================================
// Bildschirmfotos im Build (`--snapshot <Ordner>`): alle Themes, beide Erscheinungen, mehrere Fenstergrößen.
// Die Werte sind ECHTE Messungen des Build-Rechners (ein virtueller Mac: ohne Akku und meist ohne Sensoren –
// genau so erscheinen diese Bereiche dann auch: „nicht vorhanden“ bzw. „nicht verfügbar“).
// Einstellungen werden in diesem Modus nicht gespeichert.
// =============================================================================================

private final class SnapshotWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
enum SnapshotRunner {
    struct Scenario {
        let name: String
        let size: CGSize
        let theme: ThemeID
        /// Nur für das System-Theme: hell oder dunkel erzwingen.
        var dark: Bool? = nil
        var section: AppSection = .overview
        var editing = false
        var density: Density = .standard
        var glassIntensity = 0.85
    }

    static let scenarios: [Scenario] = [
        Scenario(name: "01-uebersicht-liquid-glass-dark", size: CGSize(width: 1320, height: 900), theme: .liquidGlassDark),
        Scenario(name: "02-uebersicht-liquid-glass-light", size: CGSize(width: 1320, height: 900), theme: .liquidGlassLight),
        Scenario(name: "03-uebersicht-minimal-dark", size: CGSize(width: 1320, height: 900), theme: .minimalDark),
        Scenario(name: "04-uebersicht-minimal-light", size: CGSize(width: 1320, height: 900), theme: .minimalLight),
        Scenario(name: "05-uebersicht-graphite", size: CGSize(width: 1320, height: 900), theme: .graphite),
        Scenario(name: "06-uebersicht-system-hell", size: CGSize(width: 1320, height: 900), theme: .system, dark: false),
        Scenario(name: "07-uebersicht-system-dunkel", size: CGSize(width: 1320, height: 900), theme: .system, dark: true),
        Scenario(name: "08-macbook-air-13-kompakt", size: CGSize(width: 1024, height: 680), theme: .liquidGlassDark, density: .compact),
        Scenario(name: "09-grosses-fenster-ausfuehrlich", size: CGSize(width: 1680, height: 1000), theme: .liquidGlassLight, density: .detailed),
        Scenario(name: "10-uebersicht-anpassen", size: CGSize(width: 1320, height: 900), theme: .liquidGlassDark, editing: true),
        Scenario(name: "11-einstellungen-dark", size: CGSize(width: 1320, height: 900), theme: .liquidGlassDark, section: .settings),
        Scenario(name: "12-einstellungen-light", size: CGSize(width: 1320, height: 900), theme: .liquidGlassLight, section: .settings),
        Scenario(name: "13-bereich-in-arbeit", size: CGSize(width: 1320, height: 900), theme: .graphite, section: .thermal),
        Scenario(name: "14-glas-intensitaet-0", size: CGSize(width: 1320, height: 900), theme: .liquidGlassDark, glassIntensity: 0),
    ]

    static func run(model: AppModel, output: URL) async {
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let settings = model.settings
        settings.refreshInterval = .oneSecond
        model.start()
        // Verläufe füllen (echte Messungen im Sekundentakt)
        try? await Task.sleep(nanoseconds: 14_000_000_000)
        for window in NSApp.windows { window.orderOut(nil) }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        var manifest: [[String: Any]] = []
        for scenario in scenarios {
            settings.theme = scenario.theme
            settings.density = scenario.density
            settings.glassIntensity = scenario.glassIntensity
            model.selection = scenario.section
            model.editingDashboard = scenario.editing
            let spec = ThemeCatalog.spec(scenario.theme)
            let dark: Bool
            switch spec.appearance {
            case .dark: dark = true
            case .light: dark = false
            case .system: dark = scenario.dark ?? false
            }
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            NSApp.appearance = appearance

            let window = SnapshotWindow(contentRect: NSRect(origin: .zero, size: scenario.size),
                                        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                        backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.appearance = appearance
            window.isReleasedWhenClosed = false
            let root = RootView(embedded: true)
                .environmentObject(model)
                .environmentObject(settings)
            let host = NSHostingView(rootView: root)
            window.contentView = host
            window.setContentSize(scenario.size)
            if let screen = NSScreen.main?.visibleFrame {
                window.setFrameTopLeftPoint(NSPoint(x: screen.minX + 20, y: screen.maxY - 20))
            }
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(nanoseconds: 2_400_000_000)

            let file = output.appendingPathComponent("\(scenario.name)-\(Int(scenario.size.width))x\(Int(scenario.size.height)).png")
            let method = capture(window, to: file)
            manifest.append([
                "file": file.lastPathComponent,
                "theme": scenario.theme.rawValue,
                "appearance": dark ? "dark" : "light",
                "section": scenario.section.rawValue,
                "size": "\(Int(scenario.size.width))x\(Int(scenario.size.height))",
                "glass": LiquidGlass.isAvailable ? "native" : "fallback",
                "method": method,
            ])
            window.orderOut(nil)
            window.contentView = nil
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        let summary: [String: Any] = [
            "images": manifest,
            "data": "Echte Messwerte des Build-Rechners",
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "liquidGlass": LiquidGlass.isAvailable,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: output.appendingPathComponent("manifest.json"))
        }
    }

    /// Bevorzugt das Bild des Fensterservers (enthält Glas und Unschärfe); sonst die Ansicht selbst zeichnen.
    /// `CGWindowListCreateImage` ist im aktuellen SDK für Swift gesperrt, aber öffentlich – nur hier im Build-Modus genutzt.
    private static func capture(_ window: NSWindow, to url: URL) -> String {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
            let function = unsafeBitCast(symbol, to: CreateImage.self)
            // kCGWindowListOptionIncludingWindow = 1 << 3; kCGWindowImageBoundsIgnoreFraming | kCGWindowImageBestResolution
            if let image = function(.null, 1 << 3, UInt32(window.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue(),
               image.width > 10 {
                let rep = NSBitmapImageRep(cgImage: image)
                if let data = rep.representation(using: .png, properties: [:]), (try? data.write(to: url)) != nil {
                    return "window-server"
                }
            }
        }
        if let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: url)
                return "cache-display"
            }
        }
        return "failed"
    }
}
