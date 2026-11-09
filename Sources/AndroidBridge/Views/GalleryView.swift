import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ABCore

/// Fotos & Videos: große Vorschaubilder, nach Monaten gruppiert, mit Mosaik zum Auftakt jedes Monats.
struct GalleryView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var gallery: GalleryModel
    @ObservedObject var devices: DeviceManager
    @State private var anchor: String?
    @AppStorage("galleryThumbSize") private var thumbSize: Double = 190
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
                    ToolbarIconButton(symbol: "minus.magnifyingglass", help: "Kleinere Vorschaubilder") { thumbSize = max(120, thumbSize - 35) }
                        .disabled(thumbSize <= 120)
                    ToolbarIconButton(symbol: "plus.magnifyingglass", help: "Größere Vorschaubilder") { thumbSize = min(330, thumbSize + 35) }
                        .disabled(thumbSize >= 330)
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
                        if gallery.visible.isEmpty {
                            if gallery.isScanning {
                                GalleryLoadingView(folders: gallery.scannedFolders)
                            } else {
                                EmptyStateView(symbol: gallery.filter.symbolName, title: "Nichts gefunden",
                                               message: "In den Ordnern des Telefons gibt es keine passenden Dateien für „\(gallery.filter.title)“.")
                            }
                        } else {
                            grid(device: device)
                        }
                        actionBar(device: device)
                            .padding(.bottom, 22)
                    }
                }
            } else {
                EmptyStateView(symbol: "photo.on.rectangle.angled", title: "Kein Telefon verbunden",
                               message: "Schließen Sie Ihr Android-Gerät an – hier erscheinen dann alle Fotos und Videos, nach Monaten geordnet.") {
                    Button("Zur Übersicht") { model.selection = .overview }.buttonStyle(GlassButtonStyle(prominent: true))
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
        .mask(
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 18)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 36)
            }
        )
        .padding(.bottom, 8)
    }

    private var groupedByDate: Bool { gallery.sort == .newest || gallery.sort == .oldest }

    private func grid(device: DeviceConnection) -> some View {
        GeometryReader { geo in
            let spacing: CGFloat = 8
            let width = max(200, geo.size.width - Spacing.gutter * 2)
            let columns = max(2, Int((width + spacing) / (CGFloat(thumbSize) + spacing)))
            let cell = floor((width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
            let sections = GallerySection.make(gallery.visible, byMonth: groupedByDate)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26, pinnedViews: [.sectionHeaders]) {
                    ForEach(sections) { section in
                        Section {
                            SectionMosaic(items: section.items, columns: columns, cell: cell, spacing: spacing,
                                          feature: groupedByDate && section.items.count >= 5 && columns >= 4) { item, w, h in
                                cellView(item, device: device, width: w, height: h)
                            }
                        } header: {
                            if let title = section.title {
                                MonthHeader(title: title, count: section.items.count,
                                            allSelected: section.items.allSatisfy { gallery.selection.contains($0.id) }) {
                                    let ids = Set(section.items.map(\.id))
                                    if ids.isSubset(of: gallery.selection) { gallery.selection.subtract(ids) } else { gallery.selection.formUnion(ids) }
                                }
                            }
                        }
                    }
                }
                .reportsScrollEdge()
                .padding(.horizontal, Spacing.gutter)
                .padding(.bottom, 110)
            }
        }
    }

    private func cellView(_ item: MediaItem, device: DeviceConnection, width: CGFloat, height: CGFloat) -> some View {
        GalleryCell(item: item, device: device, width: width, height: height, selected: gallery.selection.contains(item.id),
                    selectionActive: !gallery.selection.isEmpty) {
            toggle(item)
        }
        .background(GeometryReader { geo in
            let frame = geo.frame(in: .global)
            Color.clear
                .onAppear { ViewerOrigins.shared.frames[item.id] = frame }
                .onChange(of: frame) { ViewerOrigins.shared.frames[item.id] = $0 }
        })
        .onTapGesture(count: 2) { open(item, device: device) }
        .onTapGesture { select(item) }
        .onDrag { makeDeviceDragProvider(entry: item.entry, list: dragList(for: item), device: device, path: item.path) }
        .contextMenu {
            Button("Öffnen") { open(item, device: device) }
            Button(gallery.selection.contains(item.id) ? "Aus Auswahl entfernen" : "Zur Auswahl hinzufügen") { toggle(item) }
            Button("Informationen") {
                model.infoEntry = EntryInfoBox(deviceID: device.id, entry: item.entry, path: item.path)
            }
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
            model.viewerItem = MediaViewerItem(deviceID: device.id, items: media, index: index,
                                               origin: ViewerOrigins.shared.frames[item.id])
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
                    ToolbarIconButton(symbol: "xmark", help: "Auswahl aufheben") { gallery.selection = [] }
                }
            }
        }
        .animation(animations ? .bridgeSpring : nil, value: count)
    }
}

/// Ein Monat (bzw. alles, wenn nicht nach Datum sortiert).
struct GallerySection: Identifiable {
    let id: String
    let title: String?
    let items: [MediaItem]

    static func make(_ items: [MediaItem], byMonth: Bool) -> [GallerySection] {
        guard byMonth else { return [GallerySection(id: "all", title: nil, items: items)] }
        var sections: [GallerySection] = []
        var currentKey: Int?
        var bucket: [MediaItem] = []
        var currentTitle = ""
        let calendar = Calendar.current
        func flush() {
            if let key = currentKey, !bucket.isEmpty {
                sections.append(GallerySection(id: "m\(key)", title: currentTitle, items: bucket))
            }
        }
        for item in items {
            let key: Int
            let title: String
            if let date = item.entry.bestDate {
                let c = calendar.dateComponents([.year, .month], from: date)
                key = (c.year ?? 0) * 100 + (c.month ?? 0)
                title = date.formatted(.dateTime.month(.wide).year())
            } else {
                key = -1
                title = "Ohne Datum"
            }
            if key != currentKey {
                flush()
                currentKey = key
                currentTitle = title
                bucket = []
            }
            bucket.append(item)
        }
        flush()
        return sections
    }
}

/// Monatskopf (bleibt beim Scrollen oben stehen).
struct MonthHeader: View {
    let title: String
    let count: Int
    let allSelected: Bool
    let toggleAll: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(Typo.title)
                .tracking(-0.3)
                .foregroundStyle(Palette.textPrimary)
            Text("\(count)")
                .font(Typo.callout)
                .foregroundStyle(Palette.textSecondary)
                .monospacedDigit()
            Spacer()
            Button(allSelected ? "Auswahl aufheben" : "Auswählen", action: toggleAll)
                .buttonStyle(GlassButtonStyle(compact: true))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .glassSurface(Capsule(), strong: true)
        .padding(.vertical, 4)
    }
}

/// Raster eines Monats: auf Wunsch zuerst ein Mosaik (neuestes Bild groß), dann gleichmäßige Kacheln.
struct SectionMosaic<Cell: View>: View {
    let items: [MediaItem]
    let columns: Int
    let cell: CGFloat
    let spacing: CGFloat
    let feature: Bool
    let make: (MediaItem, CGFloat, CGFloat) -> Cell

    init(items: [MediaItem], columns: Int, cell: CGFloat, spacing: CGFloat, feature: Bool,
         @ViewBuilder make: @escaping (MediaItem, CGFloat, CGFloat) -> Cell) {
        self.items = items
        self.columns = columns
        self.cell = cell
        self.spacing = spacing
        self.feature = feature
        self.make = make
    }

    private var featureCount: Int { feature ? min(items.count, 1 + 2 * (columns - 2)) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if feature {
                let big = cell * 2 + spacing
                let side = Array(items[1..<featureCount])
                HStack(alignment: .top, spacing: spacing) {
                    make(items[0], big, big)
                    VStack(alignment: .leading, spacing: spacing) {
                        HStack(spacing: spacing) {
                            ForEach(Array(side.prefix(columns - 2))) { item in make(item, cell, cell) }
                        }
                        HStack(spacing: spacing) {
                            ForEach(Array(side.dropFirst(columns - 2))) { item in make(item, cell, cell) }
                        }
                    }
                }
            }
            let rest = Array(items.dropFirst(featureCount))
            if !rest.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: spacing), count: columns),
                          alignment: .leading, spacing: spacing) {
                    ForEach(rest) { item in make(item, cell, cell) }
                }
            }
        }
    }
}

/// Lädt noch: schimmernde Platzhalter statt leerer Fläche.
struct GalleryLoadingView: View {
    let folders: Int
    @State private var phase = false
    @Environment(\.animationsEnabled) private var animations

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Medien werden gesucht … \(folders) Ordner")
                    .font(Typo.callout).foregroundStyle(Palette.textSecondary).monospacedDigit()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(0..<18, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Palette.fieldFill)
                        .aspectRatio(1, contentMode: .fit)
                        .opacity(phase ? 0.45 : 1)
                        .animation(animations ? .easeInOut(duration: 1).repeatForever().delay(Double(i % 6) * 0.08) : nil, value: phase)
                }
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { phase = animations && !SnapshotMode.isActive }
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
                Image(systemName: symbol).font(.ui(11.5, .semibold))
                Text(title).font(.ui(12.5, selected ? .semibold : .medium)).lineLimit(1)
                if count > 0 {
                    Text("\(count)")
                        .font(.ui(10.5, .semibold))
                        .foregroundStyle(selected ? Palette.onAccent.opacity(0.75) : Palette.textTertiary)
                        .monospacedDigit()
                }
            }
            .fixedSize()
            .padding(.horizontal, 13)
            .frame(height: 30)
            .foregroundStyle(selected ? Palette.onAccent : Palette.textPrimary)
            .background {
                if selected {
                    Capsule().fill(LinearGradient(colors: [Palette.accent, Palette.accent2], startPoint: .topLeading, endPoint: .bottomTrailing))
                } else if hovering {
                    Capsule().fill(Palette.hoverFill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassSurface(Capsule(), strong: !selected, tint: selected ? Palette.accent.opacity(0.35) : nil, interactive: true)
        .onHover { hovering = $0 }
    }
}

struct GalleryCell: View {
    let item: MediaItem
    let device: DeviceConnection
    let width: CGFloat
    let height: CGFloat
    let selected: Bool
    var selectionActive = false
    var onToggle: (() -> Void)?
    @State private var image: NSImage?
    @State private var hovering = false

    private var corner: CGFloat { min(16, max(10, width * 0.07)) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                Palette.mediaWell
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width, height: height)
                        .clipped()
                        .scaleEffect(hovering ? 1.035 : 1)
                        .transition(.opacity)
                } else {
                    VStack(spacing: 8) {
                        TypeIcon(name: item.entry.name, isFolder: false, size: min(width * 0.36, 72))
                        if !item.entry.kind.isMedia || width > 220 {
                            Text(item.entry.name).font(.ui(10.5)).lineLimit(2).multilineTextAlignment(.center)
                                .foregroundStyle(Palette.textSecondary)
                                .padding(.horizontal, 8)
                        }
                    }
                }
                if item.entry.kind == .video {
                    VStack {
                        Spacer()
                        HStack(spacing: 5) {
                            Image(systemName: "play.fill").font(.ui(9.5, .bold))
                            Text(ByteFormat.string(item.entry.size)).font(.ui(10.5, .semibold)).monospacedDigit()
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(9)
                    }
                    .frame(width: width, height: height)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom))
                }
                if selected {
                    RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Palette.accent.opacity(0.16))
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(selected ? Palette.accent : Color.white.opacity(hovering ? 0.35 : 0.08), lineWidth: selected ? 3 : 1)
            )
            .scaleEffect(selected ? 0.95 : 1)
            .shadow(color: Palette.shadow.opacity(hovering ? 1 : 0.4), radius: hovering ? 14 : 4, y: hovering ? 6 : 2)

            if selected || hovering || selectionActive {
                Button { onToggle?() } label: {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.ui(21, .medium))
                        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.95), selected ? Palette.accent : Color.black.opacity(0.28))
                        .shadow(color: .black.opacity(0.35), radius: 2)
                        .padding(9)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(selected ? "Aus Auswahl entfernen" : "Auswählen")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: width, height: height)
        .animation(.bridgeQuick, value: selected)
        .animation(Motion.easeOut(0.35), value: hovering)
        .animation(.easeOut(duration: 0.25), value: image != nil)
        .onHover { hovering = $0 }
        .help("\(item.entry.name) · \(ByteFormat.string(item.entry.size))")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.entry.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
