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
    /// Build-Rechner haben kleine virtuelle Bildschirme – Fenster nicht auf den Bildschirm beschränken, damit die
    /// gewünschte Fenstergröße wirklich entsteht (der Fensterserver liefert auch Teile außerhalb des Bildschirms).
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
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
        /// Statt des Hauptfensters den Live-Monitor fotografieren.
        var liveMonitor = false
        /// Diagnose: nur einen Baustein zeichnen (siehe SnapshotProbes.swift).
        var probe: SnapshotProbe? = nil
    }

    /// Diagnose-Szenarien: jeder Baustein hell und dunkel.
    static var probeScenarios: [Scenario] {
        SnapshotProbe.allCases.flatMap { probe in
            [Scenario(name: "p-\(probe.rawValue)-hell", size: CGSize(width: 420, height: 320), theme: .liquidGlassLight, probe: probe),
             Scenario(name: "p-\(probe.rawValue)-dunkel", size: CGSize(width: 420, height: 320), theme: .liquidGlassDark, probe: probe)]
        }
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
        Scenario(name: "13-dateien", size: CGSize(width: 1320, height: 900), theme: .graphite, section: .files),
        Scenario(name: "14-glas-intensitaet-0", size: CGSize(width: 1320, height: 900), theme: .liquidGlassDark, glassIntensity: 0),
        Scenario(name: "15-aktivitaet", size: CGSize(width: 1320, height: 900), theme: .liquidGlassDark, section: .activity),
        Scenario(name: "16-cpu-gpu", size: CGSize(width: 1320, height: 1000), theme: .liquidGlassDark, section: .cpuGPU),
        Scenario(name: "17-arbeitsspeicher", size: CGSize(width: 1320, height: 1000), theme: .liquidGlassLight, section: .memory),
        Scenario(name: "18-temperatur-luefter", size: CGSize(width: 1320, height: 1000), theme: .liquidGlassDark, section: .thermal),
        Scenario(name: "19-batterie", size: CGSize(width: 1320, height: 1000), theme: .liquidGlassLight, section: .battery),
        Scenario(name: "20-hardware", size: CGSize(width: 1320, height: 1100), theme: .graphite, section: .hardware),
        Scenario(name: "21-speicher", size: CGSize(width: 1320, height: 1000), theme: .minimalDark, section: .storage),
        Scenario(name: "22-netzwerk", size: CGSize(width: 1320, height: 1000), theme: .liquidGlassLight, section: .network),
        Scenario(name: "23-dateien-hell", size: CGSize(width: 1320, height: 900), theme: .liquidGlassLight, section: .files),
        Scenario(name: "24-live-monitor", size: CGSize(width: 340, height: 600), theme: .liquidGlassDark, liveMonitor: true),
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

        // Fortsetzen nach einem Absturz (scripts/run_snapshots.sh): bereits erledigte bzw. abgestürzte Szenarien überspringen.
        let skip = Set((ProcessInfo.processInfo.environment["AETHER_SNAPSHOT_SKIP"] ?? "").split(separator: ",").map(String.init))
        let manifestURL = output.appendingPathComponent("manifest.json")
        var manifest: [[String: Any]] = []
        if !skip.isEmpty, let data = try? Data(contentsOf: manifestURL),
           let previous = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let images = previous["images"] as? [[String: Any]] {
            manifest = images
        }
        let list = ProcessInfo.processInfo.environment["AETHER_SNAPSHOT_PROBE"] != nil ? probeScenarios : scenarios
        for scenario in list where !skip.contains(scenario.name) {
            try? Data(scenario.name.utf8).write(to: output.appendingPathComponent("current.txt"))
            print("▸ \(scenario.name)")
            fflush(stdout)
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
            if let probe = scenario.probe {
                window.contentView = NSHostingView(rootView: ProbeHost(probe: probe)
                    .environmentObject(model)
                    .environmentObject(settings))
            } else if scenario.liveMonitor {
                window.contentView = NSHostingView(rootView: LiveMonitorView(embedded: true)
                    .environmentObject(model)
                    .environmentObject(settings))
            } else {
                window.contentView = NSHostingView(rootView: RootView(embedded: true)
                    .environmentObject(model)
                    .environmentObject(settings))
            }
            window.setContentSize(scenario.size)
            if let screen = NSScreen.main?.visibleFrame {
                window.setFrameTopLeftPoint(NSPoint(x: screen.minX, y: screen.maxY))
            }
            window.setContentSize(scenario.size)
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(nanoseconds: 2_400_000_000)

            let actual = window.contentView?.bounds.size ?? .zero
            let language = Bundle.main.preferredLocalizations.first ?? "en"
            let file = output.appendingPathComponent("\(scenario.name)-\(language)-\(Int(actual.width))x\(Int(actual.height)).png")
            let method = capture(window, to: file)
            manifest.append([
                "file": file.lastPathComponent,
                "theme": scenario.theme.rawValue,
                "appearance": dark ? "dark" : "light",
                "section": scenario.section.rawValue,
                "requestedSize": "\(Int(scenario.size.width))x\(Int(scenario.size.height))",
                "actualSize": "\(Int(actual.width))x\(Int(actual.height))",
                "language": language,
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
            "systemReduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            "systemReduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            "note": "Im Fotomodus wird „Transparenz reduzieren“ des Build-Rechners ignoriert, damit das Glasdesign sichtbar ist. Im normalen Betrieb gilt die Systemeinstellung.",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: manifestURL)
        }
        try? FileManager.default.removeItem(at: output.appendingPathComponent("current.txt"))
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
