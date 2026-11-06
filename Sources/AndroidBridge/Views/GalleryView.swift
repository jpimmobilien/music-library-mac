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
    @State private var thumbSize: CGFloat = 138
    @Environment(\.animationsEnabled) private var animations

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack(alignment: .bottom) {
                if let device = gallery.device, device.state == .connected {
                    grid(device: device)
                    if gallery.visible.isEmpty {
                        if gallery.isScanning {
                            VStack(spacing: 10) {
                                ProgressView()
                                Text("Medien werden gesucht … (\(gallery.scannedFolders) Ordner)")
                                    .font(.system(size: 12.5)).foregroundStyle(.secondary).monospacedDigit()
                            }
                        } else {
                            EmptyStateView(symbol: gallery.filter.symbolName, title: "Nichts gefunden",
                                           message: "In den Ordnern des Telefons gibt es keine passenden Dateien für „\(gallery.filter.title)“.")
                        }
                    }
                    actionBar(device: device)
                        .padding(.bottom, 16)
                } else {
                    EmptyStateView(symbol: "photo.on.rectangle.angled", title: "Kein Telefon verbunden",
                                   message: "Schließen Sie Ihr Android-Gerät an, um Fotos und Videos zu sehen.") {
                        Button("Zur Übersicht") { model.selection = .overview }.buttonStyle(GlassButtonStyle())
                    }
                }
            }
        }
        .navigationTitle("Fotos & Videos")
        .onAppear {
            if gallery.device == nil, let d = model.selectedDevice, d.state == .connected { gallery.attach(d) }
            gallery.scanIfNeeded()
        }
        .onChange(of: gallery.device?.id) { _ in gallery.scanIfNeeded() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Picker("Sortieren nach", selection: $gallery.sort) {
                        ForEach(EntrySort.allCases) { s in Text(s.title).tag(s) }
                    }
                    .pickerStyle(.inline)
                } label: { Image(systemName: "arrow.up.arrow.down") }
                .help("Sortieren")
                Button { gallery.scan() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Neu durchsuchen")
                    .disabled(gallery.device == nil)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let d = gallery.device {
                    Label(d.displayName, systemImage: "smartphone").font(.system(size: 13, weight: .semibold))
                }
                if gallery.isScanning && !gallery.visible.isEmpty {
                    ProgressView().controlSize(.mini)
                    Text("\(gallery.scannedFolders) Ordner durchsucht").font(.system(size: 11.5)).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                Slider(value: $thumbSize, in: 90...240)
                    .frame(width: 110)
                    .help("Größe der Vorschaubilder")
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
                    TextField("Suchen", text: $gallery.search).textFieldStyle(.plain).font(.system(size: 12.5))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(width: 200)
                .glassSurface(Capsule())
            }
            ScrollView(.horizontal, showsIndicators: false) {
                GlassGroup(spacing: 6) {
                    HStack(spacing: 6) {
                        let counts = gallery.counts()
                        ForEach(MediaFilter.allCases) { f in
                            FilterChip(title: f.title, symbol: f.symbolName, count: counts[f] ?? 0, selected: gallery.filter == f) {
                                gallery.filter = f
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func grid(device: DeviceConnection) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: thumbSize, maximum: thumbSize * 1.4), spacing: 10)], spacing: 10) {
                ForEach(gallery.visible) { item in
                    GalleryCell(item: item, device: device, size: thumbSize, selected: gallery.selection.contains(item.id))
                        .onTapGesture(count: 2) { open(item, device: device) }
                        .onTapGesture { select(item) }
                        .onDrag { makeDeviceDragProvider(entry: item.entry, list: dragList(for: item), device: device, path: item.path) }
                        .contextMenu {
                            Button("Öffnen") { open(item, device: device) }
                            Button("Auf den Mac übertragen") { transfer(dragList(for: item), device: device) }
                            Button("Im Dateimanager zeigen") {
                                model.selection = .files
                                if model.files.layout == .gallery { model.files.layout = .dual }
                                Task { await model.files.device.navigate(storageID: item.entry.storageID, path: item.path) }
                            }
                        }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 90)
        }
    }

    private func dragList(for item: MediaItem) -> [DeviceEntry] {
        gallery.selection.contains(item.id) ? gallery.selectedItems.map(\.entry) : [item.entry]
    }

    private func select(_ item: MediaItem) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if gallery.selection.contains(item.id) { gallery.selection.remove(item.id) } else { gallery.selection.insert(item.id) }
            anchor = item.id
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
                GlassGroup {
                    HStack(spacing: 14) {
                        Text("\(count) ausgewählt · \(ByteFormat.string(gallery.selectedSize))")
                            .font(.system(size: 12.5, weight: .medium))
                            .monospacedDigit()
                        Button {
                            transfer(gallery.selectedItems.map(\.entry), device: device)
                            gallery.selection = []
                        } label: {
                            Label("Auf den Mac übertragen", systemImage: "arrow.down.to.line")
                        }
                        .buttonStyle(GlassButtonStyle(prominent: true))
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
                        .buttonStyle(GlassButtonStyle())
                        Button("Alle") { gallery.selection = Set(gallery.visible.map(\.id)) }
                            .buttonStyle(.borderless)
                        Button { gallery.selection = [] } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless)
                            .help("Auswahl aufheben")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .glassSurface(Capsule(), elevated: true)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11))
                Text(title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background { if selected { Capsule().fill(Palette.bridgeGreen) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassSurface(Capsule(), tint: selected ? Palette.bridgeGreen.opacity(0.5) : nil, interactive: true)
    }
}

struct GalleryCell: View {
    let item: MediaItem
    let device: DeviceConnection
    let size: CGFloat
    let selected: Bool
    @State private var image: NSImage?
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06))
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                } else {
                    VStack(spacing: 6) {
                        FileGlyph(kind: item.entry.kind, size: 28)
                        if !item.entry.kind.isMedia {
                            Text(item.entry.name).font(.system(size: 10.5)).lineLimit(2).multilineTextAlignment(.center).padding(.horizontal, 6)
                        }
                    }
                }
                if item.entry.kind == .video {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
                            Text(ByteFormat.string(item.entry.size)).font(.system(size: 10, weight: .semibold))
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(7)
                    }
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom))
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Palette.bridgeGreen : Color.primary.opacity(hovering ? 0.18 : 0.06), lineWidth: selected ? 3 : 1)
            )
            .scaleEffect(selected ? 0.95 : 1)
            .shadow(color: .black.opacity(hovering ? 0.18 : 0), radius: 8, y: 3)

            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white, Palette.bridgeGreen)
                    .padding(6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.bridgeQuick, value: selected)
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
