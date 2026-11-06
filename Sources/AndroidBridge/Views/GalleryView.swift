import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ABCore

/// Fotos & Videos: Raster mit Vorschaubildern, Filtern und Mehrfachauswahl.
struct GalleryView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var gallery: GalleryModel
    @ObservedObject var devices: DeviceManager
    @State private var anchor: String?
    @State private var thumbSize: CGFloat = 150
    @Environment(\.animationsEnabled) private var animations

    private var connectedDevice: DeviceConnection? {
        guard let d = gallery.device, d.state == .connected else { return nil }
        return d
    }

    var body: some View {
        PageScaffold(title: "Fotos & Videos", subtitle: subtitle) {
            HStack(spacing: 10) {
                GlassSearchField(text: $gallery.search, prompt: "In Medien suchen", width: 200, focusToken: model.files.focusSearchToken)
                ToolbarCapsule {
                    ToolbarIconButton(symbol: "minus.magnifyingglass", help: "Kleinere Vorschaubilder") { thumbSize = max(96, thumbSize - 26) }
                        .disabled(thumbSize <= 96)
                    ToolbarIconButton(symbol: "plus.magnifyingglass", help: "Größere Vorschaubilder") { thumbSize = min(260, thumbSize + 26) }
                        .disabled(thumbSize >= 260)
                    ToolbarDivider()
                    ToolbarMenu(symbol: "arrow.up.arrow.down", help: "Sortieren") {
                        Picker("Sortieren nach", selection: $gallery.sort) {
                            ForEach(EntrySort.allCases) { s in Text(s.title).tag(s) }
                        }
                        .pickerStyle(.inline)
                    }
                    ToolbarIconButton(symbol: "checkmark.circle", help: "Alle sichtbaren auswählen (⌘A)") {
                        gallery.selection = Set(gallery.visible.map(\.id))
                    }
                    .disabled(gallery.visible.isEmpty)
                    ToolbarIconButton(symbol: "arrow.clockwise", help: "Neu durchsuchen") { gallery.scan() }
                        .disabled(connectedDevice == nil)
                    ToolbarIconButton(symbol: "trash", help: "Auswahl auf dem Telefon löschen … (⌘⌫)", tint: Palette.danger) {
                        model.deleteGallerySelection()
                    }
                    .disabled(gallery.selection.isEmpty || connectedDevice == nil)
                }
            }
        } content: {
            if let device = connectedDevice {
                VStack(spacing: 0) {
                    filters
                    ZStack(alignment: .bottom) {
                        grid(device: device)
                        if gallery.visible.isEmpty {
                            if gallery.isScanning {
                                VStack(spacing: 12) {
                                    ProgressView()
                                    Text("Medien werden gesucht … (\(gallery.scannedFolders) Ordner)")
                                        .font(Typo.callout).foregroundStyle(Palette.textSecondary).monospacedDigit()
                                }
                                .frame(maxHeight: .infinity)
                            } else {
                                EmptyStateView(symbol: gallery.filter.symbolName, title: "Nichts gefunden",
                                               message: "In den Ordnern des Telefons gibt es keine passenden Dateien für „\(gallery.filter.title)“.")
                            }
                        }
                        actionBar(device: device)
                            .padding(.bottom, 20)
                    }
                }
            } else {
                EmptyStateView(symbol: "photo.on.rectangle.angled", title: "Kein Telefon verbunden",
                               message: "Schließen Sie Ihr Android-Gerät an, um Fotos und Videos zu sehen.") {
                    Button("Zur Übersicht") { model.selection = .overview }.buttonStyle(GlassButtonStyle())
                }
            }
        }
        .onAppear {
            if gallery.device == nil, let d = model.selectedDevice, d.state == .connected { gallery.attach(d) }
            gallery.scanIfNeeded()
        }
        .onChange(of: gallery.device?.id) { _ in gallery.scanIfNeeded() }
    }

    private var subtitle: String {
        guard let d = connectedDevice else { return "Ihre Medien vom Telefon – ansehen, auswählen, übertragen" }
        var parts = [d.displayName, "\(gallery.visible.count) \(gallery.visible.count == 1 ? "Objekt" : "Objekte")"]
        if gallery.isScanning { parts.append("\(gallery.scannedFolders) Ordner durchsucht …") }
        return parts.joined(separator: " · ")
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassGroup(spacing: 6) {
                HStack(spacing: 6) {
                    let counts = gallery.counts()
                    ForEach(MediaFilter.allCases) { f in
                        FilterChip(title: f.title, symbol: f.symbolName, count: counts[f] ?? 0, selected: gallery.filter == f) {
                            gallery.filter = f
                        }
                    }
                    if gallery.isScanning { ProgressView().controlSize(.small).padding(.leading, 6) }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, Spacing.gutter)
            }
        }
        .padding(.bottom, 10)
    }

    private func grid(device: DeviceConnection) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: thumbSize, maximum: thumbSize * 1.35), spacing: 12)], spacing: 12) {
                ForEach(gallery.visible) { item in
                    GalleryCell(item: item, device: device, size: thumbSize, selected: gallery.selection.contains(item.id),
                                selectionActive: !gallery.selection.isEmpty) {
                        toggle(item)
                    }
                    .onTapGesture(count: 2) { open(item, device: device) }
                    .onTapGesture { select(item) }
                    .onDrag { makeDeviceDragProvider(entry: item.entry, list: dragList(for: item), device: device, path: item.path) }
                    .contextMenu {
                        Button("Öffnen") { open(item, device: device) }
                        Button(gallery.selection.contains(item.id) ? "Aus Auswahl entfernen" : "Zur Auswahl hinzufügen") { toggle(item) }
                        Divider()
                        Button("Auf den Mac übertragen") { transfer(dragList(for: item), device: device) }
                        Button("Im Dateimanager zeigen") {
                            model.selection = .files
                            Task { await model.files.device.navigate(storageID: item.entry.storageID, path: item.path) }
                        }
                        Divider()
                        Button(dragList(for: item).count > 1 ? "\(dragList(for: item).count) Objekte löschen …" : "Auf dem Telefon löschen …",
                               role: .destructive) {
                            let list = gallery.selection.contains(item.id) ? gallery.selectedItems : [item]
                            model.deleteGallerySelection(list)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, 100)
        }
    }

    private func dragList(for item: MediaItem) -> [DeviceEntry] {
        gallery.selection.contains(item.id) ? gallery.selectedItems.map(\.entry) : [item.entry]
    }

    private func toggle(_ item: MediaItem) {
        if gallery.selection.contains(item.id) { gallery.selection.remove(item.id) } else { gallery.selection.insert(item.id) }
        anchor = item.id
    }

    private func select(_ item: MediaItem) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            toggle(item)
        } else if flags.contains(.shift), let anchor, let a = gallery.visible.firstIndex(where: { $0.id == anchor }),
                  let b = gallery.visible.firstIndex(where: { $0.id == item.id }) {
            let range = min(a, b)...max(a, b)
            gallery.selection.formUnion(gallery.visible[range].map(\.id))
        } else {
            gallery.selection = gallery.selection == [item.id] ? [] : [item.id]
            anchor = item.id
        }
    }

    private func open(_ item: MediaItem, device: DeviceConnection) {
        if item.entry.kind.isMedia {
            let media = gallery.visible.filter { $0.entry.kind.isMedia }.map(\.entry)
            let index = media.firstIndex(of: item.entry) ?? 0
            model.viewerItem = MediaViewerItem(deviceID: device.id, items: media, index: index)
            model.recents.add(name: item.entry.name, size: item.entry.size, location: device.location(storageID: item.entry.storageID, path: item.path))
        } else {
            transfer([item.entry], device: device)
        }
    }

    private func transfer(_ entries: [DeviceEntry], device: DeviceConnection, to destination: URL? = nil) {
        if let destination {
            model.transfers.download(entries, from: device, sourcePath: [], to: destination)
            return
        }
        let groups = Dictionary(grouping: entries) { model.settings.destination(for: $0.kind).path }
        for (path, group) in groups.sorted(by: { $0.key < $1.key }) {
            model.transfers.download(group, from: device, sourcePath: [], to: URL(fileURLWithPath: path, isDirectory: true))
        }
    }

    @ViewBuilder
    private func actionBar(device: DeviceConnection) -> some View {
        let count = gallery.selection.count
        Group {
            if count > 0 {
                FloatingActionBar {
                    SelectionSummary(count: count, bytes: gallery.selectedSize)
                    Button {
                        transfer(gallery.selectedItems.map(\.entry), device: device)
                        gallery.selection = []
                    } label: {
                        Label("Auf den Mac", systemImage: "arrow.down.to.line")
                    }
                    .buttonStyle(GlassButtonStyle(prominent: true, compact: true))
                    Button("Nach …") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.canCreateDirectories = true
                        panel.prompt = "Hierhin übertragen"
                        if panel.runModal() == .OK, let url = panel.url {
                            transfer(gallery.selectedItems.map(\.entry), device: device, to: url)
                            gallery.selection = []
                        }
                    }
                    .buttonStyle(GlassButtonStyle(compact: true))
                    Button {
                        model.deleteGallerySelection()
                    } label: {
                        Label("Löschen …", systemImage: "trash")
                    }
                    .buttonStyle(GlassButtonStyle(destructive: true, compact: true))
                    .help("Auf dem Telefon endgültig löschen (⌘⌫)")
                    Button("Alle") { gallery.selection = Set(gallery.visible.map(\.id)) }
                        .buttonStyle(GlassButtonStyle(compact: true))
                    ToolbarIconButton(symbol: "xmark", help: "Auswahl aufheben") { gallery.selection = [] }
                }
            }
        }
        .animation(animations ? .bridgeSpring : nil, value: count)
    }
}

struct FilterChip: View {
    let title: String
    let symbol: String
    let count: Int
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.inter(11.5, .semibold))
                Text(title).font(.inter(12.5, selected ? .semibold : .medium))
                if count > 0 {
                    Text("\(count)")
                        .font(.inter(10.5, .semibold))
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : Palette.textTertiary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 30)
            .foregroundStyle(selected ? Color.white : Palette.textPrimary)
            .background {
                if selected {
                    Capsule().fill(LinearGradient(colors: [Palette.bridgeGreen, Palette.bridgeTeal], startPoint: .topLeading, endPoint: .bottomTrailing))
                } else if hovering {
                    Capsule().fill(Palette.hoverFill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassSurface(Capsule(), strong: !selected, tint: selected ? Palette.bridgeGreen.opacity(0.35) : nil, interactive: true)
        .onHover { hovering = $0 }
    }
}

struct GalleryCell: View {
    let item: MediaItem
    let device: DeviceConnection
    let size: CGFloat
    let selected: Bool
    var selectionActive = false
    var onToggle: (() -> Void)?
    @State private var image: NSImage?
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.fieldFill)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipped()
                        .transition(.opacity)
                } else {
                    VStack(spacing: 6) {
                        FileGlyph(kind: item.entry.kind, size: 28)
                        if !item.entry.kind.isMedia {
                            Text(item.entry.name).font(.inter(10.5)).lineLimit(2).multilineTextAlignment(.center).padding(.horizontal, 6)
                        }
                    }
                }
                if item.entry.kind == .video {
                    VStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill").font(.inter(9.5, .bold))
                            Text(ByteFormat.string(item.entry.size)).font(.inter(10, .semibold))
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(8)
                    }
                    .frame(width: size, height: size)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom))
                }
                if selected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.bridgeGreen.opacity(0.14))
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Palette.bridgeGreen : Color.white.opacity(hovering ? 0.35 : 0.12), lineWidth: selected ? 3 : 1)
            )
            .scaleEffect(selected ? 0.94 : (hovering ? 1.015 : 1))
            .shadow(color: Palette.shadow.opacity(hovering ? 1 : 0.5), radius: hovering ? 10 : 4, y: hovering ? 4 : 2)

            if selected || hovering || selectionActive {
                Button { onToggle?() } label: {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.inter(20, .medium))
                        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.9), selected ? Palette.bridgeGreen : Color.black.opacity(0.25))
                        .shadow(color: .black.opacity(0.35), radius: 2)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(selected ? "Aus Auswahl entfernen" : "Auswählen")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.bridgeQuick, value: selected)
        .animation(.bridgeQuick, value: hovering)
        .animation(.easeOut(duration: 0.2), value: image != nil)
        .onHover { hovering = $0 }
        .help("\(item.entry.name) · \(ByteFormat.string(item.entry.size))")
        .task(id: item.id) {
            guard item.entry.kind.isMedia else { return }
            if let cached = ThumbnailService.shared.cached(ThumbnailService.key(device: device, entry: item.entry)) {
                image = cached
                return
            }
            image = await ThumbnailService.shared.thumbnail(for: item.entry, device: device)
        }
    }
}

/// Ziehen von Telefonobjekten: als interne Liste und – für den Finder – als Datei, die beim Ablegen geladen wird.
@MainActor
func makeDeviceDragProvider(entry: DeviceEntry, list: [DeviceEntry], device: DeviceConnection, path: [String]) -> NSItemProvider {
    let provider = NSItemProvider()
    let payload = DeviceDragPayload(deviceID: device.id, entries: list, path: path)
    let data = (try? JSONEncoder().encode(payload)) ?? Data()
    provider.registerDataRepresentation(forTypeIdentifier: UTType.androidBridgeEntries.identifier, visibility: .ownProcess) { completion in
        completion(data, nil)
        return nil
    }
    if !entry.isFolder, let backend = device.backend {
        provider.suggestedName = entry.name
        let type = UTType(filenameExtension: FileKind.fileExtension(of: entry.name)) ?? .data
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
            let progress = Progress(totalUnitCount: Int64(max(entry.size, 1)))
            let folder = AppPaths.previewCache.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(FileNameSanitizer.macSafe(entry.name))
            Task {
                do {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                    let handle = try FileHandle(forWritingTo: url)
                    try await backend.download(handle: entry.handle, sink: { d in try handle.write(contentsOf: d) },
                                               progress: { bytes in progress.completedUnitCount = Int64(bytes); return !progress.isCancelled })
                    try handle.close()
                    completion(url, false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return progress
        }
    }
    return provider
}
