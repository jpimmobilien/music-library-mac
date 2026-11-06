import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLook
import ABCore

extension UTType {
    /// Interner Typ für gezogene/kopierte Objekte vom Telefon.
    static let androidBridgeEntries = UTType(exportedAs: "de.androidbridge.device-entries")
}

/// Inhalt beim Ziehen/Kopieren von Telefonobjekten innerhalb der App.
struct DeviceDragPayload: Codable {
    var deviceID: UInt64
    var entries: [DeviceEntry]
    var path: [String]
}

/// Dateimanager mit Mac-Spalte (links) und Telefon-Spalte (rechts).
struct FileManagerView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var files: FileManagerModel
    @ObservedObject var settings: SettingsStore
    @State private var newFolderName = "Neuer Ordner"
    @State private var renameText = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            content
            SelectionActionBar(files: files, local: files.local, device: files.device)
                .padding(.bottom, 16)
        }
        .navigationTitle("Dateimanager")
        .toolbar { toolbarContent }
        .sheet(item: Binding(get: { files.newFolderPane.map(PaneBox.init) }, set: { files.newFolderPane = $0?.pane })) { box in
            NameSheet(title: "Neuer Ordner", subtitle: box.pane == .device ? "Auf dem Telefon" : "Auf dem Mac",
                      initial: "Neuer Ordner", confirm: "Anlegen") { name in
                if box.pane == .device {
                    Task { await files.device.createFolder(named: name) }
                } else {
                    files.local.createFolder(named: name)
                }
            }
        }
        .sheet(item: Binding(get: { files.renamePane.map(PaneBox.init) }, set: { files.renamePane = $0?.pane })) { box in
            NameSheet(title: "Umbenennen", subtitle: nil, initial: renameInitial(box.pane), confirm: "Umbenennen") { name in
                if box.pane == .device, let e = files.device.selectedEntries.first {
                    Task { await files.device.rename(e, to: name) }
                } else if box.pane == .local, let e = files.local.selectedEntries.first {
                    files.local.rename(e, to: name)
                }
            }
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { files.confirmDelete != nil }, set: { if !$0 { files.confirmDelete = nil } }),
                            titleVisibility: .visible) {
            if files.confirmDelete == .device {
                Button("Endgültig löschen", role: .destructive) {
                    let list = files.device.selectedEntries
                    Task { await files.device.delete(list) }
                }
            } else {
                Button("In den Papierkorb legen", role: .destructive) {
                    files.local.moveToTrash(files.local.selectedEntries)
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(files.confirmDelete == .device
                 ? "Objekte auf dem Telefon werden sofort gelöscht und lassen sich nicht wiederherstellen."
                 : "Die Objekte können aus dem Papierkorb wiederhergestellt werden.")
        }
    }

    private var deleteTitle: String {
        let n = files.confirmDelete == .device ? files.device.selection.count : files.local.selection.count
        return n == 1 ? "1 Objekt löschen?" : "\(n) Objekte löschen?"
    }

    private func renameInitial(_ pane: Pane) -> String {
        pane == .device ? (files.device.selectedEntries.first?.name ?? "") : (files.local.selectedEntries.first?.url.lastPathComponent ?? "")
    }

    @ViewBuilder
    private var content: some View {
        switch files.layout {
        case .dual:
            HSplitView {
                LocalPaneView(browser: files.local, files: files)
                    .frame(minWidth: 300, idealWidth: 460)
                DevicePaneView(browser: files.device, files: files)
                    .frame(minWidth: 340, idealWidth: 560)
            }
        case .single:
            DevicePaneView(browser: files.device, files: files)
        case .gallery:
            GalleryView(gallery: model.gallery, devices: model.devices)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { activeBack() } label: { Image(systemName: "chevron.left") }
                .help("Zurück")
                .disabled(!(files.activePane == .device ? files.device.canGoBack : files.local.canGoBack))
            Button { activeForward() } label: { Image(systemName: "chevron.right") }
                .help("Vor")
                .disabled(!(files.activePane == .device ? files.device.canGoForward : files.local.canGoForward))
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Ansicht", selection: $files.layout) {
                ForEach(FileManagerLayout.allCases) { l in
                    Image(systemName: l.symbolName).tag(l).help(l.title)
                }
            }
            .pickerStyle(.segmented)
            .help("Ansicht")

            Menu {
                Picker("Sortieren nach", selection: activeSortBinding) {
                    ForEach(EntrySort.allCases) { s in Text(s.title).tag(s) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .help("Sortieren")

            Button { files.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .help("Aktualisieren (⌘R)")

            Button { files.requestNewFolder() } label: { Image(systemName: "folder.badge.plus") }
                .help("Neuer Ordner (⌘N)")

            Button {
                if files.activePane == .device { files.transferDeviceSelectionToMac() } else { files.transferLocalSelectionToDevice() }
            } label: {
                Label(files.activePane == .device ? "Auf den Mac" : "Aufs Telefon",
                      systemImage: files.activePane == .device ? "arrow.down.to.line" : "arrow.up.to.line")
            }
            .help(files.activePane == .device ? "Auswahl auf den Mac übertragen" : "Auswahl auf das Telefon übertragen")
            .disabled(files.activePane == .device ? files.device.selection.isEmpty : (files.local.selection.isEmpty || files.device.device == nil))

            Menu {
                Button("Alles auswählen") { files.selectAll() }
                Button("Auswahl aufheben") { files.deselectAll() }
                Button("Auswahl umkehren") { files.invertSelection() }
                Divider()
                Toggle("Versteckte Mac-Dateien zeigen", isOn: Binding(get: { files.local.showHidden }, set: { files.local.showHidden = $0 }))
                Toggle("Versteckte Android-Dateien zeigen", isOn: Binding(get: { settings.showHiddenAndroidFiles },
                                                                          set: { settings.showHiddenAndroidFiles = $0; files.device.recompute() }))
                Divider()
                Button("Mac-Ordner im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([files.local.folder]) }
                if let loc = files.device.location {
                    Button(model.favorites.contains(loc) ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen") {
                        model.favorites.toggle(loc)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .help("Weitere Optionen")
        }
    }

    private var activeSortBinding: Binding<EntrySort> {
        let device = files.device
        let local = files.local
        if files.activePane == .device {
            return Binding(get: { device.sort }, set: { device.sort = $0 })
        }
        return Binding(get: { local.sort }, set: { local.sort = $0 })
    }

    private func activeBack() { files.activePane == .device ? files.device.back() : files.local.back() }
    private func activeForward() { files.activePane == .device ? files.device.forward() : files.local.forward() }
}

private struct PaneBox: Identifiable {
    let pane: Pane
    var id: Pane { pane }
}

/// Eingabe eines Namens (neuer Ordner, Umbenennen).
struct NameSheet: View {
    let title: String
    let subtitle: String?
    let initial: String
    let confirm: String
    let action: (String) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 15, weight: .semibold))
            if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary) }
            TextField("Name", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(commit)
                .frame(width: 320)
            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(confirm, action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .onAppear {
            text = initial
            focused = true
        }
    }

    private func commit() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        action(t)
        dismiss()
    }
}

// MARK: - Kopfzeile einer Spalte

struct PaneHeader<Leading: View, Crumbs: View>: View {
    let isActive: Bool
    @Binding var search: String
    let focusToken: UUID
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var crumbs: () -> Crumbs
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                leading()
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
                    TextField("Suchen", text: $search)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .focused($searchFocused)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: 220)
                .glassSurface(Capsule())
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) { crumbs() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(isActive ? Palette.bridgeGreen.opacity(0.7) : Palette.hairline).frame(height: isActive ? 2 : 1)
        }
        .onChange(of: focusToken) { _ in if isActive { searchFocused = true } }
    }
}

struct CrumbButton: View {
    let title: String
    let symbol: String?
    let isLast: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button(action: action) {
                HStack(spacing: 4) {
                    if let symbol { Image(systemName: symbol).font(.system(size: 11)) }
                    Text(title).lineLimit(1)
                }
                .font(.system(size: 12, weight: isLast ? .semibold : .regular))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isLast ? .primary : .secondary)
            if !isLast {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Telefon-Spalte

struct DevicePaneView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var browser: DeviceBrowserModel
    @ObservedObject var files: FileManagerModel
    @State private var dropTargeted = false
    @FocusState private var tableFocused: Bool

    private var isActive: Bool { files.activePane == .device }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(isActive: isActive, search: $browser.search, focusToken: files.focusSearchToken) {
                deviceAndStoragePicker
            } crumbs: {
                if let storage = browser.storage {
                    CrumbButton(title: storage.displayName, symbol: storage.symbolName, isLast: browser.crumbs.isEmpty) {
                        browser.goTo(crumbIndex: nil)
                    }
                    ForEach(Array(browser.crumbs.enumerated()), id: \.offset) { index, crumb in
                        CrumbButton(title: crumb.name, symbol: nil, isLast: index == browser.crumbs.count - 1) {
                            browser.goTo(crumbIndex: index)
                        }
                    }
                }
            }
            ZStack {
                if let device = browser.device, device.state == .connected {
                    table(device: device)
                    if browser.isLoading && browser.visible.isEmpty {
                        ProgressView("Dateien werden geladen …").controlSize(.small)
                    } else if !browser.isLoading && browser.visible.isEmpty && browser.issue == nil {
                        EmptyStateView(symbol: browser.search.isEmpty ? "folder" : "magnifyingglass",
                                       title: browser.search.isEmpty ? "Ordner ist leer" : "Keine Treffer",
                                       message: browser.search.isEmpty ? "Ziehen Sie Dateien aus dem Finder oder der linken Spalte hierher." : "Kein Objekt passt zu „\(browser.search)“.")
                            .allowsHitTesting(false)
                    }
                } else {
                    noDevice
                }
                if let issue = browser.issue {
                    VStack {
                        IssueBanner(issue: issue, primaryTitle: "Erneut versuchen", primaryAction: { browser.reload(force: true) },
                                    dismiss: { browser.issue = nil })
                            .padding(14)
                        Spacer()
                    }
                }
            }
        }
        .background(isActive ? Color.primary.opacity(0.012) : .clear)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Palette.bridgeGreen, lineWidth: 2.5)
                .padding(3)
                .opacity(dropTargeted ? 1 : 0)
                .allowsHitTesting(false)
        )
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard browser.device?.state == .connected else { return false }
            loadFileURLs(providers) { urls in files.uploadToDevice(urls) }
            return true
        }
        .simultaneousGesture(TapGesture().onEnded { files.activePane = .device })
    }

    private var deviceAndStoragePicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "smartphone").foregroundStyle(Palette.bridgeGreen)
            if model.devices.connectedDevices.count > 1 {
                Menu {
                    ForEach(model.devices.connectedDevices) { d in
                        Button(d.displayName) { model.select(device: d) }
                    }
                } label: {
                    Text(browser.device?.displayName ?? "Gerät").font(.system(size: 13, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                Text(browser.device?.displayName ?? "Telefon")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(2)
            }
            if let device = browser.device, device.storages.count > 1 {
                Picker("", selection: Binding(get: { browser.storageID ?? 0 }, set: { browser.selectStorage($0) })) {
                    ForEach(device.storages) { s in Label(s.displayName, systemImage: s.symbolName).tag(s.id) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 190)
                .layoutPriority(1)
            }
            if browser.isLoading && !browser.visible.isEmpty { ProgressView().controlSize(.mini) }
        }
    }

    private var noDevice: some View {
        EmptyStateView(symbol: "cable.connector", title: "Kein Telefon verbunden",
                       message: "Schließen Sie Ihr Android-Gerät per USB an, entsperren Sie es und wählen Sie „Dateiübertragung“.") {
            Button("Zur Übersicht") { model.selection = .overview }.buttonStyle(GlassButtonStyle())
        }
    }

    private func table(device: DeviceConnection) -> some View {
        Table(of: DeviceEntry.self, selection: $browser.selection) {
            TableColumn("Name") { e in
                HStack(spacing: 8) {
                    DeviceThumb(entry: e, device: device, size: 22)
                    Text(e.name).lineLimit(1).truncationMode(.middle)
                }
            }
            .width(min: 180, ideal: 320)
            TableColumn("Geändert") { e in
                Text(e.bestDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "–")
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 140)
            TableColumn("Größe") { e in
                Text(e.isFolder ? "–" : ByteFormat.string(e.size)).foregroundStyle(.secondary).monospacedDigit()
            }
            .width(min: 60, ideal: 80)
            TableColumn("Art") { e in
                Text(kindName(e.kind, name: e.name)).foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 90)
        } rows: {
            ForEach(browser.visible) { e in
                TableRow(e).itemProvider { dragProvider(for: e, device: device) }
            }
        }
        .focused($tableFocused)
        .onChange(of: tableFocused) { f in if f { files.activePane = .device } }
        .onChange(of: browser.selection) { s in if !s.isEmpty { files.activePane = .device } }
        .contextMenu(forSelectionType: String.self) { ids in
            rowMenu(ids: ids, device: device)
        } primaryAction: { ids in
            open(ids: ids, device: device)
        }
        .onDeleteCommand { files.activePane = .device; files.requestDelete() }
        .onCopyCommand {
            files.activePane = .device
            files.copySelection()
            let selected = browser.selectedEntries
            guard !selected.isEmpty else { return [] }
            return [payloadProvider(entries: selected, device: device)]
        }
        .onPasteCommand(of: [.fileURL]) { providers in
            files.activePane = .device
            loadFileURLs(providers) { urls in files.uploadToDevice(urls) }
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func rowMenu(ids: Set<String>, device: DeviceConnection) -> some View {
        let entries = browser.visible.filter { ids.contains($0.id) }
        if !entries.isEmpty {
            Button("Auf den Mac übertragen") { files.transferToMac(entries, useSmartDestination: files.layout != .dual) }
            Button("In intelligente Zielordner übertragen") { files.transferToMac(entries, useSmartDestination: true) }
            Button("Übertragen nach …") { chooseDestination(entries) }
            Divider()
            if entries.count == 1, let e = entries.first {
                if e.isFolder {
                    Button("Öffnen") { browser.enter(e) }
                    if let loc = browser.location {
                        let folderLoc = DeviceLocation(deviceSerial: loc.deviceSerial, deviceName: loc.deviceName, storageID: loc.storageID,
                                                       storageName: loc.storageName, path: loc.path + [e.name])
                        Button(model.favorites.contains(folderLoc) ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen") {
                            model.favorites.toggle(folderLoc)
                        }
                    }
                } else if e.kind.isMedia {
                    Button("Vorschau") { preview(e) }
                }
                Button("Umbenennen …") { browser.selection = [e.id]; files.renamePane = .device }
            }
            Divider()
            Button("Löschen …", role: .destructive) {
                browser.selection = ids
                files.activePane = .device
                files.requestDelete()
            }
        } else {
            Button("Neuer Ordner …") { files.activePane = .device; files.requestNewFolder() }
            Button("Aktualisieren") { browser.invalidateCache(); browser.reload(force: true) }
        }
    }

    private func open(ids: Set<String>, device: DeviceConnection) {
        let entries = browser.visible.filter { ids.contains($0.id) }
        guard let first = entries.first else { return }
        if entries.count == 1 && first.isFolder {
            browser.enter(first)
        } else if entries.count == 1 && first.kind.isMedia {
            preview(first)
        } else {
            files.transferToMac(entries, useSmartDestination: files.layout != .dual)
        }
    }

    private func preview(_ entry: DeviceEntry) {
        guard let device = browser.device else { return }
        let media = browser.visible.filter { $0.kind.isMedia }
        let index = media.firstIndex(of: entry) ?? 0
        model.viewerItem = MediaViewerItem(deviceID: device.id, items: media, index: index)
        if let loc = browser.location { model.recents.add(name: entry.name, size: entry.size, location: loc) }
    }

    private func chooseDestination(_ entries: [DeviceEntry]) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Hierhin übertragen"
        panel.directoryURL = files.local.folder
        if panel.runModal() == .OK, let url = panel.url {
            files.transferToMac(entries, useSmartDestination: false, destination: url)
        }
    }

    private func payloadProvider(entries: [DeviceEntry], device: DeviceConnection) -> NSItemProvider {
        let payload = DeviceDragPayload(deviceID: device.id, entries: entries, path: browser.pathNames)
        let provider = NSItemProvider()
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.androidBridgeEntries.identifier, visibility: .ownProcess) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    /// Ziehen: innerhalb der App als Objektliste, in den Finder als Datei (wird beim Ablegen geladen).
    private func dragProvider(for entry: DeviceEntry, device: DeviceConnection) -> NSItemProvider {
        let list = browser.selection.contains(entry.id) ? browser.selectedEntries : [entry]
        let provider = payloadProvider(entries: list, device: device)
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
                        try await backend.download(handle: entry.handle, sink: { data in try handle.write(contentsOf: data) },
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
}

func kindName(_ kind: FileKind, name: String) -> String {
    switch kind {
    case .folder: return "Ordner"
    case .photo: return "Bild"
    case .video: return "Video"
    case .audio: return "Audio"
    case .document: return "Dokument"
    case .archive: return "Archiv"
    case .apk: return "App-Paket"
    case .other:
        let ext = FileKind.fileExtension(of: name)
        return ext.isEmpty ? "Datei" : ext.uppercased()
    }
}

/// Lädt Datei-URLs aus abgelegten bzw. eingefügten Elementen.
func loadFileURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    let group = DispatchGroup()
    let lock = NSLock()
    var urls: [URL] = []
    for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        group.enter()
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            defer { group.leave() }
            var url: URL?
            if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
            else if let u = item as? URL { url = u }
            else if let s = item as? String { url = URL(string: s) }
            if let url, url.isFileURL {
                lock.lock(); urls.append(url); lock.unlock()
            }
        }
    }
    group.notify(queue: .main) { if !urls.isEmpty { completion(urls) } }
}

/// Vorschaubild bzw. Symbol eines Telefonobjekts.
struct DeviceThumb: View {
    let entry: DeviceEntry
    let device: DeviceConnection
    var size: CGFloat = 22
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
            } else {
                FileGlyph(kind: entry.kind, size: size - 4)
                    .frame(width: size, height: size)
            }
        }
        .task(id: entry.id) {
            guard entry.kind.isMedia else { return }
            if let cached = ThumbnailService.shared.cached(ThumbnailService.key(device: device, entry: entry)) {
                image = cached
                return
            }
            image = await ThumbnailService.shared.thumbnail(for: entry, device: device)
        }
    }
}

// MARK: - Mac-Spalte

struct LocalPaneView: View {
    @ObservedObject var browser: LocalBrowserModel
    @ObservedObject var files: FileManagerModel
    @State private var dropTargeted = false
    @State private var quickLookURL: URL?
    @FocusState private var tableFocused: Bool

    private var isActive: Bool { files.activePane == .local }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(isActive: isActive, search: $browser.search, focusToken: files.focusSearchToken) {
                placesMenu
            } crumbs: {
                let crumbs = browser.crumbs
                ForEach(Array(crumbs.enumerated()), id: \.offset) { index, url in
                    CrumbButton(title: index == 0 && url == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL ? NSUserName() : (url.path == "/" ? "Macintosh HD" : url.lastPathComponent),
                                symbol: index == 0 ? (url.path == "/" ? "internaldrive" : "house") : nil,
                                isLast: index == crumbs.count - 1) {
                        browser.open(url)
                    }
                }
            }
            ZStack {
                table
                if browser.visible.isEmpty {
                    EmptyStateView(symbol: "folder", title: browser.search.isEmpty ? "Ordner ist leer" : "Keine Treffer",
                                   message: browser.search.isEmpty ? "Ziehen Sie Dateien vom Telefon hierher." : "Kein Objekt passt zu „\(browser.search)“.")
                        .allowsHitTesting(false)
                }
                if let issue = browser.issue {
                    VStack {
                        IssueBanner(issue: issue, dismiss: { browser.issue = nil }).padding(14)
                        Spacer()
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Palette.bridgeBlue, lineWidth: 2.5)
                .padding(3)
                .opacity(dropTargeted ? 1 : 0)
                .allowsHitTesting(false)
        )
        .onDrop(of: [.androidBridgeEntries], isTargeted: $dropTargeted) { providers in
            receive(providers)
            return true
        }
        .simultaneousGesture(TapGesture().onEnded { files.activePane = .local })
        .quickLookPreview($quickLookURL)
    }

    private var placesMenu: some View {
        Menu {
            Section("Orte") {
                ForEach(LocalFiles.places) { p in
                    Button { browser.open(p.url) } label: { Label(p.name, systemImage: p.symbolName) }
                }
            }
            Section("Laufwerke") {
                ForEach(LocalFiles.volumes) { v in
                    Button { browser.open(v.url) } label: { Label(v.name, systemImage: v.symbolName) }
                }
            }
            Divider()
            Button("Ordner wählen …") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.canCreateDirectories = true
                panel.directoryURL = browser.folder
                if panel.runModal() == .OK, let url = panel.url { browser.open(url) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "laptopcomputer").foregroundStyle(Palette.bridgeBlue)
                Text("Mac").font(.system(size: 13, weight: .semibold))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var table: some View {
        Table(of: LocalEntry.self, selection: $browser.selection) {
            TableColumn("Name") { e in
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: e.url.path))
                        .resizable()
                        .frame(width: 20, height: 20)
                    Text(e.name).lineLimit(1).truncationMode(.middle)
                }
            }
            .width(min: 160, ideal: 280)
            TableColumn("Geändert") { e in
                Text(e.modified.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "–").foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 140)
            TableColumn("Größe") { e in
                Text(e.isFolder && !e.isPackage ? "–" : ByteFormat.string(e.size)).foregroundStyle(.secondary).monospacedDigit()
            }
            .width(min: 60, ideal: 80)
        } rows: {
            ForEach(browser.visible) { e in
                TableRow(e).itemProvider { NSItemProvider(object: e.url as NSURL) }
            }
        }
        .focused($tableFocused)
        .onChange(of: tableFocused) { f in if f { files.activePane = .local } }
        .onChange(of: browser.selection) { s in if !s.isEmpty { files.activePane = .local } }
        .contextMenu(forSelectionType: URL.self) { ids in
            let entries = browser.visible.filter { ids.contains($0.url) }
            if !entries.isEmpty {
                Button("Auf das Telefon übertragen") { files.uploadToDevice(entries.map(\.url)) }
                    .disabled(files.device.device == nil)
                Button("Vorschau") { quickLookURL = entries.first?.url }
                Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting(entries.map(\.url)) }
                if entries.count == 1, let e = entries.first {
                    Button("Umbenennen …") { browser.selection = [e.url]; files.renamePane = .local }
                }
                Divider()
                Button("In den Papierkorb legen …", role: .destructive) {
                    browser.selection = ids
                    files.activePane = .local
                    files.requestDelete()
                }
            } else {
                Button("Neuer Ordner …") { files.activePane = .local; files.requestNewFolder() }
            }
        } primaryAction: { ids in
            if let e = browser.visible.first(where: { ids.contains($0.url) }), ids.count == 1 { browser.enter(e) }
        }
        .onDeleteCommand { files.activePane = .local; files.requestDelete() }
        .onCopyCommand {
            files.activePane = .local
            files.copySelection()
            return browser.selectedEntries.map { NSItemProvider(object: $0.url as NSURL) }
        }
        .onPasteCommand(of: [.androidBridgeEntries]) { providers in
            files.activePane = .local
            receive(providers)
        }
        .scrollContentBackground(.hidden)
    }

    private func receive(_ providers: [NSItemProvider]) {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.androidBridgeEntries.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.androidBridgeEntries.identifier) { data, _ in
                guard let data, let payload = try? JSONDecoder().decode(DeviceDragPayload.self, from: data) else { return }
                DispatchQueue.main.async {
                    guard files.device.device?.id == payload.deviceID else { return }
                    files.transferToMac(payload.entries, useSmartDestination: false, destination: browser.folder)
                }
            }
            break
        }
    }
}

// MARK: - Aktionsleiste unten

struct SelectionActionBar: View {
    @ObservedObject var files: FileManagerModel
    @ObservedObject var local: LocalBrowserModel
    @ObservedObject var device: DeviceBrowserModel
    @Environment(\.animationsEnabled) private var animations

    private var deviceCount: Int { device.selection.count }
    private var localCount: Int { local.selection.count }

    var body: some View {
        Group {
            if files.layout != .gallery && (files.activePane == .device ? deviceCount > 0 : localCount > 0) {
                GlassGroup {
                    HStack(spacing: 14) {
                        if files.activePane == .device {
                            Text("\(deviceCount) ausgewählt · \(ByteFormat.string(files.deviceSelectionSize))")
                                .font(.system(size: 12.5, weight: .medium))
                                .monospacedDigit()
                            Button {
                                files.transferDeviceSelectionToMac()
                            } label: {
                                Label(files.layout == .dual ? "In „\(local.folder.lastPathComponent)“ übertragen" : "Auf den Mac übertragen",
                                      systemImage: "arrow.down.to.line")
                            }
                            .buttonStyle(GlassButtonStyle(prominent: true))
                        } else {
                            Text("\(localCount) ausgewählt · \(ByteFormat.string(files.localSelectionSize))")
                                .font(.system(size: 12.5, weight: .medium))
                                .monospacedDigit()
                            Button {
                                files.transferLocalSelectionToDevice()
                            } label: {
                                Label("Aufs Telefon übertragen", systemImage: "arrow.up.to.line")
                            }
                            .buttonStyle(GlassButtonStyle(prominent: true))
                            .disabled(device.device == nil)
                        }
                        Button { files.deselectAll() } label: { Image(systemName: "xmark") }
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
        .animation(animations ? .bridgeSpring : nil, value: files.activePane == .device ? deviceCount : localCount)
    }
}
