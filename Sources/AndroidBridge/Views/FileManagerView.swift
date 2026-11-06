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
    @ObservedObject private var deviceBrowser: DeviceBrowserModel
    @ObservedObject private var localBrowser: LocalBrowserModel

    init(files: FileManagerModel, settings: SettingsStore) {
        self.files = files
        self.settings = settings
        self.deviceBrowser = files.device
        self.localBrowser = files.local
    }

    var body: some View {
        PageScaffold(title: "Dateimanager", subtitle: subtitle) {
            toolbar
        } content: {
            ZStack(alignment: .bottom) {
                content
                    .padding(.horizontal, Spacing.gutter - 10)
                    .padding(.bottom, 14)
                SelectionActionBar(files: files, local: files.local, device: files.device)
                    .padding(.bottom, 28)
            }
        }
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
        // Telefon: Bestätigung mit Anzahl, Größe und Ort (DeleteConfirmationSheet). Mac: Papierkorb.
        .onChange(of: files.confirmDelete) { pane in
            if pane == .device {
                files.confirmDelete = nil
                model.deleteDeviceSelection(in: files)
            }
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { files.confirmDelete == .local }, set: { if !$0 { files.confirmDelete = nil } }),
                            titleVisibility: .visible) {
            Button("In den Papierkorb legen", role: .destructive) {
                files.local.moveToTrash(files.local.selectedEntries)
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die Objekte können aus dem Papierkorb wiederhergestellt werden.")
        }
    }

    private var subtitle: String {
        if let loc = deviceBrowser.location, let device = deviceBrowser.device, device.state == .connected {
            return "\(device.displayName) · \(loc.displayPath)"
        }
        return "Mac und Telefon nebeneinander – ziehen, kopieren, einfügen"
    }

    private var deleteTitle: String {
        let n = files.local.selection.count
        return n == 1 ? "1 Objekt in den Papierkorb legen?" : "\(n) Objekte in den Papierkorb legen?"
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
                    .glassCard(cornerRadius: Radius.panel)
                    .padding(.trailing, 5)
                    .frame(minWidth: 300, idealWidth: 460)
                DevicePaneView(browser: files.device, files: files)
                    .glassCard(cornerRadius: Radius.panel)
                    .padding(.leading, 5)
                    .frame(minWidth: 340, idealWidth: 560)
            }
        case .single, .gallery:
            DevicePaneView(browser: files.device, files: files)
                .glassCard(cornerRadius: Radius.panel)
        }
    }

    private var deviceActive: Bool { files.activePane == .device }

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 10) {
            ToolbarCapsule {
                ToolbarIconButton(symbol: "chevron.left", help: "Zurück (⌘[)") { activeBack() }
                    .disabled(!(deviceActive ? deviceBrowser.canGoBack : localBrowser.canGoBack))
                ToolbarIconButton(symbol: "chevron.right", help: "Vor (⌘])") { activeForward() }
                    .disabled(!(deviceActive ? deviceBrowser.canGoForward : localBrowser.canGoForward))
            }
            GlassSegmented(selection: Binding(get: { files.layout == .gallery ? .single : files.layout }, set: { files.layout = $0 }), options: [
                SegmentOption(value: FileManagerLayout.dual, symbol: FileManagerLayout.dual.symbolName, help: "Zwei Spalten: Mac und Telefon"),
                SegmentOption(value: FileManagerLayout.single, symbol: FileManagerLayout.single.symbolName, help: "Eine Spalte: nur Telefon"),
            ])
            ToolbarCapsule {
                ToolbarMenu(symbol: "arrow.up.arrow.down", help: "Sortieren") {
                    Picker("Sortieren nach", selection: activeSortBinding) {
                        ForEach(EntrySort.allCases) { s in Text(s.title).tag(s) }
                    }
                    .pickerStyle(.inline)
                }
                ToolbarIconButton(symbol: "arrow.clockwise", help: "Aktualisieren (⌘R)") { files.refresh() }
                ToolbarIconButton(symbol: "folder.badge.plus", help: "Neuer Ordner (⌘N)") { files.requestNewFolder() }
                ToolbarDivider()
                ToolbarIconButton(symbol: deviceActive ? "arrow.down.to.line" : "arrow.up.to.line",
                                  help: deviceActive ? "Auswahl auf den Mac übertragen (⌘T)" : "Auswahl auf das Telefon übertragen (⌘T)") {
                    if deviceActive { files.transferDeviceSelectionToMac() } else { files.transferLocalSelectionToDevice() }
                }
                .disabled(deviceActive ? deviceBrowser.selection.isEmpty : (localBrowser.selection.isEmpty || deviceBrowser.device == nil))
                ToolbarIconButton(symbol: "trash", help: deviceActive ? "Auf dem Telefon löschen … (⌘⌫)" : "In den Papierkorb legen … (⌘⌫)",
                                  tint: Palette.danger) {
                    model.requestDeleteForCurrentPage()
                }
                .disabled(deviceActive ? deviceBrowser.selection.isEmpty || deviceBrowser.device?.state != .connected : localBrowser.selection.isEmpty)
                ToolbarMenu(symbol: "ellipsis", help: "Weitere Optionen") {
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
                }
            }
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
            Text(title).font(.inter(15, .semibold))
            if let subtitle { Text(subtitle).font(.inter(12)).foregroundStyle(.secondary) }
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

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                leading()
                Spacer(minLength: 8)
                GlassSearchField(text: $search, prompt: "Suchen", width: 200, focusToken: focusToken, focusEnabled: isActive)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) { crumbs() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(isActive ? Palette.bridgeGreen.opacity(0.75) : Palette.hairline).frame(height: isActive ? 2 : 1)
                .padding(.horizontal, 14)
        }
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
                    if let symbol { Image(systemName: symbol).font(.inter(11)) }
                    Text(title).lineLimit(1)
                }
                .font(.inter(12, isLast ? .semibold : .regular))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isLast ? .primary : .secondary)
            if !isLast {
                Image(systemName: "chevron.right").font(.inter(9, .semibold)).foregroundStyle(.tertiary)
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
        .overlay(
            RoundedRectangle(cornerRadius: Radius.panel - 3, style: .continuous)
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
                    Text(browser.device?.displayName ?? "Gerät").font(.inter(13, .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                Text(browser.device?.displayName ?? "Telefon")
                    .font(.inter(13, .semibold))
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
        .onDeleteCommand { files.activePane = .device; model.deleteDeviceSelection(in: files) }
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
            Button("Auf dem Telefon löschen …", role: .destructive) {
                browser.selection = ids
                files.activePane = .device
                model.deleteDeviceSelection(in: files, entries: entries)
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
            RoundedRectangle(cornerRadius: Radius.panel - 3, style: .continuous)
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
                Text("Mac").font(.inter(13, .semibold))
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
    @EnvironmentObject private var model: AppModel
    @ObservedObject var files: FileManagerModel
    @ObservedObject var local: LocalBrowserModel
    @ObservedObject var device: DeviceBrowserModel
    @Environment(\.animationsEnabled) private var animations

    private var deviceCount: Int { device.selection.count }
    private var localCount: Int { local.selection.count }

    var body: some View {
        Group {
            if files.activePane == .device ? deviceCount > 0 : localCount > 0 {
                FloatingActionBar {
                    if files.activePane == .device {
                        SelectionSummary(count: deviceCount, bytes: files.deviceSelectionSize)
                        Button {
                            files.transferDeviceSelectionToMac()
                        } label: {
                            Label(files.layout == .dual ? "In „\(local.folder.lastPathComponent)“ übertragen" : "Auf den Mac übertragen",
                                  systemImage: "arrow.down.to.line")
                        }
                        .buttonStyle(GlassButtonStyle(prominent: true, compact: true))
                        Button {
                            model.deleteDeviceSelection(in: files)
                        } label: {
                            Label("Löschen …", systemImage: "trash")
                        }
                        .buttonStyle(GlassButtonStyle(destructive: true, compact: true))
                        .help("Auf dem Telefon endgültig löschen (⌘⌫)")
                    } else {
                        SelectionSummary(count: localCount, bytes: files.localSelectionSize)
                        Button {
                            files.transferLocalSelectionToDevice()
                        } label: {
                            Label("Aufs Telefon übertragen", systemImage: "arrow.up.to.line")
                        }
                        .buttonStyle(GlassButtonStyle(prominent: true, compact: true))
                        .disabled(device.device == nil)
                    }
                    ToolbarIconButton(symbol: "xmark", help: "Auswahl aufheben") { files.deselectAll() }
                }
            }
        }
        .animation(animations ? .bridgeSpring : nil, value: files.activePane == .device ? deviceCount : localCount)
    }
}
