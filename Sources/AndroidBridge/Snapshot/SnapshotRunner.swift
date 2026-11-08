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

    func thumbnail(handle: UInt32) async throws -> Data? { Self.previewImage(handle: handle, scale: 1) }

    /// Erzeugtes Beispielbild (Vorschaugerät): `scale` 1 = 160×120 wie Android-Vorschaubilder, größer für die Großansicht.
    static func previewImage(handle: UInt32, scale: CGFloat) -> Data? {
        let hues: [CGFloat] = [0.02, 0.08, 0.13, 0.33, 0.52, 0.58, 0.62, 0.75, 0.9]
        let h = hues[Int(handle) % hues.count]
        // Wie echte Android-Vorschaubilder: 160×120, Hochformat mit schwarzen Balken links/rechts.
        let portrait = handle % 3 == 0
        let size = NSSize(width: 160 * scale, height: 120 * scale)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGraphicsContext.current?.cgContext.scaleBy(x: 1, y: 1)
        NSColor.black.setFill()
        NSRect(origin: .zero, size: size).fill()
        let content = portrait ? NSRect(x: 35 * scale, y: 0, width: 90 * scale, height: 120 * scale)
            : NSRect(origin: .zero, size: size)
        if scale > 1 && portrait {
            // Großansicht: echtes Hochformat ohne Balken
            image.unlockFocus()
            return previewPortrait(handle: handle, hue: h, scale: scale)
        }
        NSBezierPath(rect: content).setClip()
        let g = NSGradient(colors: [NSColor(hue: h, saturation: 0.55, brightness: 0.95, alpha: 1),
                                    NSColor(hue: (h + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.55, alpha: 1)])
        g?.draw(in: content, angle: CGFloat(Int(handle) % 4) * 45 + 30)
        NSColor(white: 1, alpha: 0.25).setFill()
        NSBezierPath(ovalIn: NSRect(x: (30 + CGFloat(handle % 5) * 12) * scale, y: 80 * scale, width: 46 * scale, height: 46 * scale)).fill()
        NSColor(white: 0, alpha: 0.18).setFill()
        let hill = NSBezierPath()
        hill.move(to: NSPoint(x: 0, y: 0)); hill.line(to: NSPoint(x: 0, y: 50 * scale))
        hill.curve(to: NSPoint(x: 160 * scale, y: 40 * scale), controlPoint1: NSPoint(x: 60 * scale, y: 95 * scale), controlPoint2: NSPoint(x: 100 * scale, y: 20 * scale))
        hill.line(to: NSPoint(x: 160 * scale, y: 0)); hill.close()
        hill.fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    private static func previewPortrait(handle: UInt32, hue h: CGFloat, scale: CGFloat) -> Data? {
        let size = NSSize(width: 90 * scale, height: 120 * scale)
        let image = NSImage(size: size)
        image.lockFocus()
        let g = NSGradient(colors: [NSColor(hue: h, saturation: 0.55, brightness: 0.95, alpha: 1),
                                    NSColor(hue: (h + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.55, alpha: 1)])
        g?.draw(in: NSRect(origin: .zero, size: size), angle: 60)
        NSColor(white: 1, alpha: 0.25).setFill()
        NSBezierPath(ovalIn: NSRect(x: 20 * scale, y: 80 * scale, width: 40 * scale, height: 40 * scale)).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    func download(handle: UInt32, sink: @escaping (Data) throws -> Void, progress: @escaping (UInt64) -> Bool) async throws {
        // Nur für die Großansicht im Bildschirmfoto: erzeugtes Bild statt Dateiinhalt.
        guard let data = Self.previewImage(handle: handle, scale: 10) else { throw MTPError.notSupported("Vorschau") }
        try sink(data)
        _ = progress(UInt64(data.count))
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
    func deleteTree(handle: UInt32, storage: UInt32, isFolder: Bool) async throws -> MTPSession.DeleteTreeResult { throw MTPError.notSupported("Vorschau") }
    func rename(handle: UInt32, to name: String) async throws { throw MTPError.notSupported("Vorschau") }
    func batteryLevel() async -> Int? { 82 }
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
        var custom: ((AppModel) -> AnyView)? = nil
        let prepare: (AppModel) async -> Void

        init(name: String, size: CGSize, custom: ((AppModel) -> AnyView)? = nil, prepare: @escaping (AppModel) async -> Void) {
            self.name = name
            self.size = size
            self.custom = custom
            self.prepare = prepare
        }
    }

    static func run(model: AppModel, output: URL) async {
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var manifest: [[String: String]] = []
        try? await Task.sleep(nanoseconds: 800_000_000)
        for w in NSApp.windows { w.orderOut(nil) }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        SnapshotMode.isActive = true
        // Fenstergrößen: kleinstes Fenster, 13" (1280×800), 14" (1512×945), 16" (1728×1117)
        let small = CGSize(width: 960, height: 640)
        let mb13 = CGSize(width: 1280, height: 800)
        let mb14 = CGSize(width: 1512, height: 945)
        let mb16 = CGSize(width: 1728, height: 1080)

        func files(_ m: AppModel, layout: FileManagerLayout, grid: Bool) async {
            await installPreview(m, state: .connected)
            UserDefaults.standard.set(grid ? PaneStyle.grid.rawValue : PaneStyle.list.rawValue, forKey: "filePaneStyle")
            m.files.layout = layout
            m.selection = .files
            await m.files.device.navigate(storageID: 0x10001, path: ["DCIM", "Camera"], recordHistory: false)
            m.files.device.selection = Set(m.files.device.visible.prefix(3).map(\.id))
            m.files.activePane = .device
        }
        func gallery(_ m: AppModel) async {
            await installPreview(m, state: .connected)
            m.selection = .media
            m.gallery.filter = .media
            if let d = m.devices.connectedDevices.first { m.gallery.attach(d) }
            m.gallery.scan()
            // warten, bis die Suche fertig ist (höchstens 8 s)
            for _ in 0..<80 where m.gallery.isScanning || m.gallery.visible.isEmpty {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            m.gallery.selection = Set(m.gallery.visible.dropFirst(2).prefix(3).map(\.id))
        }

        let scenarios: [Scenario] = [
            Scenario(name: "01-uebersicht-ohne-geraet", size: mb14) { m in
                m.devices.installPreviewDevices([])
                m.selection = .overview
            },
            Scenario(name: "02-uebersicht-verbunden", size: mb14) { m in
                await installPreview(m, state: .connected)
                m.selection = .overview
            },
            Scenario(name: "02b-uebersicht-verbunden", size: mb16) { m in
                await installPreview(m, state: .connected)
                m.selection = .overview
            },
            Scenario(name: "02c-uebersicht-verbunden", size: small) { m in
                await installPreview(m, state: .connected)
                m.selection = .overview
            },
            Scenario(name: "03-dateimanager-zwei-spalten", size: mb14) { m in await files(m, layout: .dual, grid: false) },
            Scenario(name: "03b-dateimanager-raster", size: mb14) { m in await files(m, layout: .dual, grid: true) },
            Scenario(name: "03c-dateimanager-zwei-spalten", size: small) { m in await files(m, layout: .dual, grid: false) },
            Scenario(name: "03d-dateimanager-eine-spalte-raster", size: mb13) { m in await files(m, layout: .single, grid: true) },
            Scenario(name: "04-galerie", size: mb14) { m in await gallery(m) },
            Scenario(name: "04b-galerie", size: small) { m in await gallery(m) },
            Scenario(name: "04c-galerie", size: mb16) { m in await gallery(m) },
            Scenario(name: "05-grossansicht", size: mb14) { m in
                await gallery(m)
                m.gallery.selection = []
                let media = m.gallery.visible.filter { $0.entry.kind == .photo }.map(\.entry)
                if !media.isEmpty, let device = m.devices.connectedDevices.first {
                    m.viewerItem = MediaViewerItem(deviceID: device.id, items: media, index: min(3, media.count - 1))
                }
            },
            Scenario(name: "06-dateiuebertragung-einschalten", size: mb13) { m in
                m.viewerItem = nil
                await installPreview(m, state: .waitingForFileTransfer)
                m.selection = .overview
            },
            Scenario(name: "07-speicher-verwalten", size: mb14) { m in
                await gallery(m)
                m.gallery.selection = []
                if let d = m.devices.connectedDevices.first { m.selection = .device(d.id) }
            },
            Scenario(name: "08-duplikate-bereich", size: mb13) { m in
                await installPreview(m, state: .connected)
                m.duplicates.reset()
                m.selection = .duplicates
            },
            Scenario(name: "09-duplikate-ergebnisse", size: mb14) { m in
                await installPreview(m, state: .connected)
                let (identical, similar) = previewDuplicateGroups()
                let marked = Set(identical.prefix(2).flatMap { DuplicateSelection.suggested(for: $0) })
                m.duplicates.showPreviewResults(identical: identical, similar: similar, marked: marked)
                m.selection = .duplicates
            },
            Scenario(name: "10-loeschen-bestaetigen", size: CGSize(width: 560, height: 720), custom: { m in
                AnyView(DeleteConfirmationSheet(request: previewDeletionRequest(), onConfirm: {}, onCancel: {})
                    .environment(\.glassEnabled, m.settings.glassEffects)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(Palette.background))
            }) { m in
                await installPreview(m, state: .connected)
            },
            Scenario(name: "11-einstellungen", size: mb13) { m in
                m.selection = .settings
            },
            Scenario(name: "12-favoriten", size: mb13) { m in
                await installPreview(m, state: .connected)
                if let d = m.devices.connectedDevices.first {
                    for path in [["DCIM", "Camera"], ["Pictures"], ["Download"], ["Documents"]] {
                        let loc = d.location(storageID: 0x10001, path: path)
                        if !m.favorites.contains(loc) { m.favorites.toggle(loc) }
                    }
                }
                m.selection = .favorites
            },
            Scenario(name: "13-uebertragungen-leer", size: mb13) { m in
                m.selection = .transfers
            },
            Scenario(name: "14-duplikate-ergebnisse-klein", size: small) { m in
                await installPreview(m, state: .connected)
                let (identical, similar) = previewDuplicateGroups()
                m.duplicates.showPreviewResults(identical: identical, similar: similar, marked: [])
                m.selection = .duplicates
            },
        ]

        for scenario in scenarios {
            for dark in [false, true] {
                print("[Snapshot] ▸ \(scenario.name) \(dark ? "dunkel" : "hell")")
                fflush(stdout)
                model.settings.appearance = dark ? .dark : .light
                NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                model.viewerItem = nil
                await scenario.prepare(model)
                // nie größer als der sichtbare Bildschirm der Build-Maschine (sonst schneidet macOS das Fenster ab)
                var size = scenario.size
                if let v = NSScreen.main?.visibleFrame {
                    size.width = min(size.width, v.width - 40)
                    size.height = min(size.height, v.height - 40)
                }
                let window = SnapshotWindow(contentRect: NSRect(origin: .zero, size: size),
                                            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                            backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.isReleasedWhenClosed = false
                window.title = "Android Bridge"
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                let content: AnyView = scenario.custom?(model)
                    ?? AnyView(RootView(settings: model.settings, transfers: model.transfers, deletion: model.deletion))
                // Füllt das ganze Fenster (inklusive Titelleistenbereich) – wie in der App.
                let root = content
                    .environmentObject(model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                let host = NSHostingView(rootView: root)
                host.sizingOptions = []
                window.contentView = host
                window.setContentSize(size)
                if let screen = NSScreen.main {
                    let v = screen.visibleFrame
                    window.setFrameTopLeftPoint(NSPoint(x: v.minX + 20, y: v.maxY - 20))
                }
                window.makeKeyAndOrderFront(nil)
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                let file = output.appendingPathComponent("\(scenario.name)-\(dark ? "dunkel" : "hell")-\(Int(size.width))x\(Int(size.height)).png")
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

    /// Beispielgruppen für das Bildschirmfoto (Vorschaugerät).
    private static func previewDuplicateGroups() -> ([DuplicateGroup], [DuplicateGroup]) {
        func e(_ h: UInt32, _ name: String, size: UInt64, storage: UInt32 = 0x10001, days: Double, w: UInt32 = 0, hgt: UInt32 = 0) -> DeviceEntry {
            DeviceEntry(handle: h, storageID: storage, parent: 0, name: name, isFolder: false, size: size, format: MTPFormat.forFileName(name),
                        modified: Date(timeIntervalSinceNow: -days * 86_400), imageWidth: w, imageHeight: hgt)
        }
        let a = [DuplicateFile(entry: e(1003, "PXL_20261103_143507.mp4", size: 207_000_000, days: 2.1), path: ["DCIM", "Camera"], storageName: "Interner Speicher"),
                 DuplicateFile(entry: e(7001, "VID-20261103-WA0004.mp4", size: 207_000_000, days: 2.0), path: ["Android", "media", "com.whatsapp", "WhatsApp", "Media"], storageName: "Interner Speicher"),
                 DuplicateFile(entry: e(7002, "PXL_20261103_143507.mp4", size: 207_000_000, storage: 0x20001, days: 1.2), path: ["DCIM", "Backup"], storageName: "SD-Karte")]
        let b = [DuplicateFile(entry: e(1001, "PXL_20261101_113107.jpg", size: 2_461_000, days: 0.7, w: 4080, hgt: 3072), path: ["DCIM", "Camera"], storageName: "Interner Speicher"),
                 DuplicateFile(entry: e(7003, "IMG-20261101-WA0012.jpg", size: 2_461_000, days: 0.6, w: 4080, hgt: 3072), path: ["Pictures", "WhatsApp"], storageName: "Interner Speicher")]
        let c = [DuplicateFile(entry: e(300, "Rechnung_Oktober.pdf", size: 248_000, days: 3), path: ["Documents"], storageName: "Interner Speicher"),
                 DuplicateFile(entry: e(7004, "Rechnung_Oktober(1).pdf", size: 248_000, days: 2), path: ["Download"], storageName: "Interner Speicher")]
        let s = [DuplicateFile(entry: e(1005, "PXL_20261105_153507.jpg", size: 3_120_000, days: 3.5, w: 4080, hgt: 3072), path: ["DCIM", "Camera"], storageName: "Interner Speicher"),
                 DuplicateFile(entry: e(7005, "Screenshot_20261105.jpg", size: 410_000, days: 3.4, w: 1080, hgt: 813), path: ["Pictures", "Screenshots"], storageName: "Interner Speicher")]
        let identical = [DuplicateGroup(id: "sha-a", kind: .identical, files: a, checksum: "a"),
                         DuplicateGroup(id: "sha-b", kind: .identical, files: b, checksum: "b"),
                         DuplicateGroup(id: "sha-c", kind: .identical, files: c, checksum: "c")]
        return (identical, [DuplicateGroup(id: "sim-1", kind: .similar, files: s, checksum: nil)])
    }

    private static func previewDeletionRequest() -> DeletionRequest {
        var files: [DeviceEntry] = []
        for i in 0..<12 {
            let name: String = "PXL_2026110" + String(i % 9) + "_1" + String(i % 10) + "3" + String(i % 6) + "07.jpg"
            let size: UInt64 = 2_400_000 + UInt64(i) * 61_000
            files.append(DeviceEntry(handle: UInt32(1000 + i), storageID: 0x10001, parent: 100, name: name,
                                     isFolder: false, size: size, format: MTPFormat.forFileName(name)))
        }
        let folder = DeviceEntry(handle: 101, storageID: 0x10001, parent: 12, name: "Screenshots", isFolder: true, size: 0, format: MTPFormat.association)
        return DeletionRequest(deviceID: 4242, deviceName: "Pixel 6 Pro", entries: files + [folder],
                               locations: ["Interner Speicher › DCIM › Camera", "Interner Speicher › DCIM"])
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
