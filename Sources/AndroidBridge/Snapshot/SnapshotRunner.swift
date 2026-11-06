import SwiftUI
import AppKit
import ABCore

// =============================================================================================
// Automatische Bildschirmfotos im Build (`--snapshot <Ordner>`) und Selbsttest (`--selftest <Datei>`).
//
// Nur für die Qualitätssicherung in der Build-Pipeline: Die Gerätedarstellung nutzt dort ein
// VORSCHAUGERÄT mit erfundenen Beispielordnern, weil an den Build-Rechnern kein Telefon hängt.
// In der normalen App ist dieser Modus nicht erreichbar; dort gibt es ausschließlich echtes MTP über USB.
// =============================================================================================

/// Vorschaudaten (nur Bildschirmfotos im Build).
final class PreviewBackend: DeviceBackend {
    let supportsPartialDownload = true
    private var tree: [UInt32: [DeviceEntry]] = [:]
    private var roots: [UInt32: [DeviceEntry]] = [:]

    init() {
        func entry(_ h: UInt32, _ parent: UInt32, _ name: String, folder: Bool = false, size: UInt64 = 0, days: Double = 1, storage: UInt32 = 0x10001) -> DeviceEntry {
            DeviceEntry(handle: h, storageID: storage, parent: parent, name: name, isFolder: folder, size: size,
                        format: folder ? MTPFormat.association : MTPFormat.forFileName(name),
                        modified: Date(timeIntervalSinceNow: -days * 86_400))
        }
        roots[0x10001] = ["Alarms", "Android", "DCIM", "Documents", "Download", "Movies", "Music", "Notifications", "Pictures", "Podcasts", "Recordings", "Ringtones"]
            .enumerated().map { i, n in entry(UInt32(10 + i), 0, n, folder: true, days: Double(i)) }
        tree[12] = [entry(100, 12, "Camera", folder: true), entry(101, 12, "Screenshots", folder: true)]
        var photos: [DeviceEntry] = []
        for i in 0..<48 {
            let isVideo = i % 7 == 3
            photos.append(entry(UInt32(1000 + i), 100, isVideo ? "PXL_2026110\(i % 9)_1\(i % 10)4512.mp4" : "PXL_2026110\(i % 9)_1\(i % 10)3\(i % 6)07.jpg",
                                size: isVideo ? UInt64(180_000_000 + i * 9_000_000) : UInt64(2_400_000 + i * 61_000), days: Double(i) * 0.7))
        }
        tree[100] = photos
        tree[14] = [entry(300, 14, "Rechnung_Oktober.pdf", size: 248_000, days: 3), entry(301, 14, "Bordkarte.pdf", size: 112_000, days: 9),
                    entry(302, 14, "Urlaub_2026.zip", size: 1_840_000_000, days: 20), entry(303, 14, "Notizen.txt", size: 4_200, days: 1)]
        roots[0x20001] = [entry(400, 0, "DCIM", folder: true, storage: 0x20001), entry(401, 0, "Musik", folder: true, storage: 0x20001),
                              entry(402, 0, "Filme", folder: true, storage: 0x20001)]
    }

    func storages() async throws -> [DeviceStorage] {
        [DeviceStorage(id: 0x10001, description: "Interner gemeinsamer Speicher", volumeLabel: "", capacity: 256_000_000_000, free: 97_300_000_000, isRemovable: false, isReadOnly: false),
         DeviceStorage(id: 0x20001, description: "SD-Karte", volumeLabel: "SANDISK", capacity: 128_000_000_000, free: 71_800_000_000, isRemovable: true, isReadOnly: false)]
    }

    func list(storage: UInt32, parent: UInt32) async throws -> [DeviceEntry] {
        if parent == MTPHandle.root { return roots[storage] ?? [] }
        return tree[parent] ?? []
    }

    func entry(handle: UInt32) async throws -> DeviceEntry {
        for list in Array(tree.values) + Array(roots.values) { if let e = list.first(where: { $0.handle == handle }) { return e } }
        throw MTPError.response(PTPResponse.invalidObjectHandle.rawValue)
    }

    func thumbnail(handle: UInt32) async throws -> Data? {
        let hues: [CGFloat] = [0.02, 0.08, 0.13, 0.33, 0.52, 0.58, 0.62, 0.75, 0.9]
        let h = hues[Int(handle) % hues.count]
        let size = NSSize(width: 160, height: 160)
        let image = NSImage(size: size)
        image.lockFocus()
        let g = NSGradient(colors: [NSColor(hue: h, saturation: 0.55, brightness: 0.95, alpha: 1),
                                    NSColor(hue: (h + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.55, alpha: 1)])
        g?.draw(in: NSRect(origin: .zero, size: size), angle: CGFloat(Int(handle) % 4) * 45 + 30)
        NSColor(white: 1, alpha: 0.25).setFill()
        NSBezierPath(ovalIn: NSRect(x: 30 + CGFloat(handle % 5) * 12, y: 80, width: 46, height: 46)).fill()
        NSColor(white: 0, alpha: 0.18).setFill()
        let hill = NSBezierPath()
        hill.move(to: NSPoint(x: 0, y: 0)); hill.line(to: NSPoint(x: 0, y: 50)); hill.curve(to: NSPoint(x: 160, y: 40), controlPoint1: NSPoint(x: 60, y: 95), controlPoint2: NSPoint(x: 100, y: 20)); hill.line(to: NSPoint(x: 160, y: 0)); hill.close()
        hill.fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }

    func download(handle: UInt32, sink: @escaping (Data) throws -> Void, progress: @escaping (UInt64) -> Bool) async throws {
        throw MTPError.notSupported("Vorschau")
    }

    func downloadSegment(handle: UInt32, offset: UInt64, length: UInt32, sink: @escaping (Data) throws -> Void) async throws -> UInt64 {
        throw MTPError.notSupported("Vorschau")
    }

    func upload(name: String, size: UInt64, storage: UInt32, parent: UInt32, modified: Date?, next: @escaping (Int) throws -> Data,
                progress: @escaping (UInt64) -> Bool) async throws -> UInt32 {
        throw MTPError.notSupported("Vorschau")
    }

    func createFolder(name: String, storage: UInt32, parent: UInt32) async throws -> UInt32 { throw MTPError.notSupported("Vorschau") }
    func delete(handle: UInt32) async throws { throw MTPError.notSupported("Vorschau") }
    func rename(handle: UInt32, to name: String) async throws { throw MTPError.notSupported("Vorschau") }
    func close(graceful: Bool) {}
}

private final class SnapshotWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
enum SnapshotRunner {
    struct Scenario {
        let name: String
        let size: CGSize
        let prepare: (AppModel) async -> Void
    }

    static func run(model: AppModel, output: URL) async {
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var manifest: [[String: String]] = []
        try? await Task.sleep(nanoseconds: 800_000_000)
        for w in NSApp.windows { w.orderOut(nil) }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Szenen ohne Gerät zuerst, danach mit Vorschaugerät
        let scenarios: [Scenario] = [
            Scenario(name: "01-uebersicht-ohne-geraet", size: CGSize(width: 1320, height: 840)) { m in
                m.devices.installPreviewDevices([])
                m.selection = .overview
            },
            Scenario(name: "02-uebersicht-geraet", size: CGSize(width: 1320, height: 840)) { m in
                await installPreview(m, state: .connected)
                m.selection = .overview
            },
            Scenario(name: "03-dateimanager-zwei-spalten", size: CGSize(width: 1320, height: 840)) { m in
                await installPreview(m, state: .connected)
                m.files.layout = .dual
                m.selection = .files
                await m.files.device.navigate(storageID: 0x10001, path: ["DCIM", "Camera"], recordHistory: false)
                m.files.device.selection = Set(m.files.device.visible.prefix(5).map(\.id))
                m.files.activePane = .device
            },
            Scenario(name: "04-galerie", size: CGSize(width: 1320, height: 840)) { m in
                await installPreview(m, state: .connected)
                m.selection = .media
                m.gallery.scan()
                try? await Task.sleep(nanoseconds: 600_000_000)
                m.gallery.selection = Set(m.gallery.visible.prefix(3).map(\.id))
            },
            Scenario(name: "05-dateiuebertragung-einschalten", size: CGSize(width: 1320, height: 840)) { m in
                await installPreview(m, state: .waitingForFileTransfer)
                m.selection = .overview
            },
            Scenario(name: "06-uebertragungen-leer", size: CGSize(width: 1320, height: 840)) { m in
                m.selection = .transfers
            },
            Scenario(name: "07-kleines-fenster", size: CGSize(width: 1000, height: 660)) { m in
                await installPreview(m, state: .connected)
                m.files.layout = .dual
                m.selection = .files
            },
        ]

        for scenario in scenarios {
            for dark in [false, true] {
                print("[Snapshot] ▸ \(scenario.name) \(dark ? "dunkel" : "hell")")
                fflush(stdout)
                model.settings.appearance = dark ? .dark : .light
                NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                await scenario.prepare(model)
                let window = SnapshotWindow(contentRect: NSRect(origin: .zero, size: scenario.size),
                                            styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                            backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.isReleasedWhenClosed = false
                window.title = "Android Bridge"
                let root = RootView(settings: model.settings, transfers: model.transfers)
                    .environmentObject(model)
                    .frame(width: scenario.size.width, height: scenario.size.height)
                let host = NSHostingView(rootView: root)
                host.sizingOptions = []
                window.contentView = host
                window.setContentSize(scenario.size)
                if let screen = NSScreen.main {
                    let v = screen.visibleFrame
                    window.setFrameTopLeftPoint(NSPoint(x: v.minX + 20, y: v.maxY - 20))
                }
                window.makeKeyAndOrderFront(nil)
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                let file = output.appendingPathComponent("\(scenario.name)-\(dark ? "dunkel" : "hell").png")
                let method = capture(window, to: file)
                manifest.append(["file": file.lastPathComponent, "method": method,
                                 "glass": LiquidGlass.isAvailable ? "liquid-glass" : "fallback",
                                 "deviceData": scenario.name.contains("ohne") || scenario.name.contains("leer") ? "keine" : "Vorschaugerät (nur Build)"])
                window.orderOut(nil)
                window.contentView = nil
                window.close()
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        let info: [String: Any] = [
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "architecture": SystemInfo.architecture,
            "liquidGlass": LiquidGlass.isAvailable,
            "note": "Gerätedarstellungen verwenden ein Vorschaugerät mit erfundenen Ordnern (kein Telefon am Build-Rechner).",
            "images": manifest,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: output.appendingPathComponent("manifest.json"))
        }
    }

    private static func installPreview(_ model: AppModel, state: ConnectionState) async {
        let backend = PreviewBackend()
        let storages = (try? await backend.storages()) ?? []
        let device = DeviceConnection(preview: backend, id: 4242, manufacturer: "Google", model: "Pixel 6 Pro", serial: "PREVIEW0001",
                                      storages: state == .connected ? storages : [], state: state, settings: model.settings)
        if state == .waitingForFileTransfer { device.issue = .chargingOnly }
        model.devices.installPreviewDevices([device])
        model.select(device: device)
    }

    private static func capture(_ window: NSWindow, to url: URL) -> String {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
            let fn = unsafeBitCast(sym, to: CreateImage.self)
            if let img = fn(.null, 1 << 3, UInt32(window.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue(), img.width > 10 {
                let rep = NSBitmapImageRep(cgImage: img)
                if let data = rep.representation(using: .png, properties: [:]), (try? data.write(to: url)) != nil { return "window-server" }
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

/// Selbsttest beim Start (Build-Pipeline): prüft, dass die App startet, das Fenster zeigt und die USB-Überwachung läuft.
@MainActor
enum SelfTest {
    static func run(model: AppModel, output: URL) async {
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        let info = Bundle.main.infoDictionary ?? [:]
        let windows = NSApp.windows.filter { $0.isVisible }
        // ABCore-Kernlogik im fertigen Programm einmal durchlaufen
        var w = PTPWriter()
        w.string("Selbsttest ✓")
        var r = PTPReader(w.data)
        let roundTrip = (try? r.string()) == "Selbsttest ✓"
        let result: [String: Any] = [
            "ok": !windows.isEmpty && roundTrip,
            "version": info["CFBundleShortVersionString"] as? String ?? "",
            "build": info["CFBundleVersion"] as? String ?? "",
            "architecture": SystemInfo.architecture,
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "liquidGlass": LiquidGlass.isAvailable,
            "visibleWindows": windows.count,
            "usbDevicesSeen": model.devices.allUSBDevices.count,
            "androidDevices": model.devices.devices.count,
            "usbMonitorError": model.devices.monitorError ?? "",
            "ptpRoundTrip": roundTrip,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: output)
        }
        print("[Selbsttest] \(result)")
        fflush(stdout)
    }
}
