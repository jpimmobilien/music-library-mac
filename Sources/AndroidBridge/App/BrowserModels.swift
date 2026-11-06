import Foundation
import SwiftUI
import AppKit
import ABCore

enum Pane: Hashable { case local, device }

/// Ein Element des Brotkrumenpfads auf dem Gerät.
struct DeviceCrumb: Hashable {
    let handle: UInt32
    let name: String
}

/// Ort auf dem Gerät für Zurück/Vor.
private struct DeviceNavState: Equatable {
    var storageID: UInt32
    var crumbs: [DeviceCrumb]
}

/// Ordneransicht des Android-Geräts.
@MainActor
final class DeviceBrowserModel: ObservableObject {
    @Published private(set) var device: DeviceConnection?
    @Published private(set) var storageID: UInt32?
    @Published private(set) var crumbs: [DeviceCrumb] = []
    @Published private(set) var entries: [DeviceEntry] = []
    @Published var selection = Set<String>()
    @Published var sort: EntrySort = .name { didSet { recompute() } }
    @Published var search = "" { didSet { recompute() } }
    @Published private(set) var visible: [DeviceEntry] = []
    @Published private(set) var isLoading = false
    @Published var issue: ABIssue?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false

    private let settings: SettingsStore
    private var backStack: [DeviceNavState] = []
    private var forwardStack: [DeviceNavState] = []
    private var cache: [String: [DeviceEntry]] = [:]
    private var cacheOrder: [String] = []
    private var loadTask: Task<Void, Never>?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var parentHandle: UInt32 { crumbs.last?.handle ?? MTPHandle.root }
    var pathNames: [String] { crumbs.map(\.name) }
    var storage: DeviceStorage? { device?.storages.first { $0.id == storageID } }
    var selectedEntries: [DeviceEntry] { visible.filter { selection.contains($0.id) } }
    var location: DeviceLocation? {
        guard let device, let storageID else { return nil }
        return device.location(storageID: storageID, path: pathNames)
    }

    func attach(_ device: DeviceConnection) {
        guard self.device?.id != device.id || storageID == nil || entries.isEmpty else { return }
        self.device = device
        cache.removeAll()
        cacheOrder.removeAll()
        backStack.removeAll()
        forwardStack.removeAll()
        updateNavFlags()
        let prefs = settings.preferences(forSerial: device.serial)
        let initialStorage = device.storages.first { $0.id == prefs.lastStorageID }?.id ?? device.storages.first?.id
        storageID = initialStorage
        crumbs = []
        entries = []
        recompute()
        if let initialStorage, settings.rememberDevicePreferences, !prefs.lastPath.isEmpty {
            Task { await navigate(storageID: initialStorage, path: prefs.lastPath, recordHistory: false) }
        } else {
            reload()
        }
    }

    func detach() {
        loadTask?.cancel()
        device = nil
        storageID = nil
        crumbs = []
        entries = []
        selection = []
        recompute()
    }

    func selectStorage(_ id: UInt32) {
        guard id != storageID || !crumbs.isEmpty else { return }
        pushHistory()
        storageID = id
        crumbs = []
        selection = []
        reload()
    }

    func enter(_ folder: DeviceEntry) {
        guard folder.isFolder else { return }
        pushHistory()
        crumbs.append(DeviceCrumb(handle: folder.handle, name: folder.name))
        selection = []
        search = ""
        reload()
    }

    func goTo(crumbIndex: Int?) {
        pushHistory()
        if let crumbIndex { crumbs = Array(crumbs.prefix(crumbIndex + 1)) } else { crumbs = [] }
        selection = []
        reload()
    }

    func goUp() {
        guard !crumbs.isEmpty else { return }
        goTo(crumbIndex: crumbs.count >= 2 ? crumbs.count - 2 : nil)
    }

    func back() {
        guard let previous = backStack.popLast(), let storageID else { return }
        forwardStack.append(DeviceNavState(storageID: storageID, crumbs: crumbs))
        apply(previous)
    }

    func forward() {
        guard let next = forwardStack.popLast(), let storageID else { return }
        backStack.append(DeviceNavState(storageID: storageID, crumbs: crumbs))
        apply(next)
    }

    private func apply(_ state: DeviceNavState) {
        storageID = state.storageID
        crumbs = state.crumbs
        selection = []
        updateNavFlags()
        reload()
    }

    private func pushHistory() {
        guard let storageID else { return }
        backStack.append(DeviceNavState(storageID: storageID, crumbs: crumbs))
        if backStack.count > 100 { backStack.removeFirst() }
        forwardStack.removeAll()
        updateNavFlags()
    }

    private func updateNavFlags() {
        canGoBack = !backStack.isEmpty
        canGoForward = !forwardStack.isEmpty
    }

    private func cacheKey(_ storage: UInt32, _ parent: UInt32) -> String { "\(storage)/\(parent)" }

    /// Lädt den aktuellen Ordner (aus dem Zwischenspeicher sofort, danach frisch vom Gerät).
    func reload(force: Bool = false) {
        loadTask?.cancel()
        guard let device, let storageID, let backend = device.backend, device.state == .connected else {
            entries = []
            recompute()
            return
        }
        let parent = parentHandle
        let key = cacheKey(storageID, parent)
        if !force, let cached = cache[key] {
            entries = cached
            recompute()
        } else if force == false {
            entries = []
            recompute()
        }
        isLoading = true
        issue = nil
        settings.updatePreferences(forSerial: device.serial) { p in
            p.lastStorageID = storageID
            p.lastPath = pathNames
        }
        loadTask = Task { [weak self] in
            do {
                let list = try await backend.list(storage: storageID, parent: parent)
                guard let self, !Task.isCancelled, self.storageID == storageID, self.parentHandle == parent else { return }
                self.store(key, list)
                withAnimation(.bridgeQuick) {
                    self.entries = list
                    self.recompute()
                }
                self.isLoading = false
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.isLoading = false
                self.issue = ABIssue.from(error, context: "Ordner konnte nicht geladen werden")
                device.reportFailure(error)
            }
        }
    }

    private func store(_ key: String, _ list: [DeviceEntry]) {
        cache[key] = list
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        if cacheOrder.count > 40 { cache[cacheOrder.removeFirst()] = nil }
    }

    func invalidateCache() {
        cache.removeAll()
        cacheOrder.removeAll()
    }

    func recompute() {
        var list = entries
        if !settings.showHiddenAndroidFiles { list = list.filter { !$0.isHidden } }
        if !search.isEmpty { list = list.filter { EntrySorting.matches(name: $0.name, query: search) } }
        visible = EntrySorting.sorted(list, by: sort)
        selection = selection.intersection(Set(visible.map(\.id)))
    }

    /// Navigiert über Namen (Favoriten, Zuletzt verwendet – Handles ändern sich zwischen Sitzungen).
    func navigate(storageID: UInt32, path: [String], recordHistory: Bool = true) async {
        guard let device, let backend = device.backend else { return }
        if recordHistory { pushHistory() }
        self.storageID = storageID
        var newCrumbs: [DeviceCrumb] = []
        var parent = MTPHandle.root
        isLoading = true
        for name in path {
            guard let children = try? await backend.list(storage: storageID, parent: parent),
                  let match = children.first(where: { $0.isFolder && $0.name == name }) ?? children.first(where: { $0.isFolder && $0.name.lowercased() == name.lowercased() }) else {
                break
            }
            store(cacheKey(storageID, parent), children)
            newCrumbs.append(DeviceCrumb(handle: match.handle, name: match.name))
            parent = match.handle
        }
        crumbs = newCrumbs
        selection = []
        reload()
    }

    func selectAll() { selection = Set(visible.map(\.id)) }
    func deselectAll() { selection = [] }
    func invertSelection() { selection = Set(visible.map(\.id)).subtracting(selection) }

    func createFolder(named name: String) async {
        guard let device, let backend = device.backend, let storageID else { return }
        let clean = FileNameSanitizer.androidSafe(name)
        let unique = ConflictNaming.uniqueName(for: clean, existing: Set(entries.map(\.name)))
        do {
            let handle = try await backend.createFolder(name: unique, storage: storageID, parent: parentHandle)
            invalidateCache()
            reload(force: true)
            selection = ["\(storageID):\(handle)"]
        } catch {
            issue = ABIssue.from(error, context: "Ordner konnte nicht angelegt werden")
        }
    }

    func rename(_ entry: DeviceEntry, to name: String) async {
        guard let backend = device?.backend else { return }
        let clean = FileNameSanitizer.androidSafe(name)
        guard clean != entry.name else { return }
        if entries.contains(where: { $0.name.lowercased() == clean.lowercased() && $0.id != entry.id }) {
            issue = ABIssue(kind: .conflict, title: "Name bereits vergeben", message: "„\(clean)“ gibt es in diesem Ordner schon.", recommendation: nil, technical: nil)
            return
        }
        do {
            try await backend.rename(handle: entry.handle, to: clean)
            invalidateCache()
            reload(force: true)
        } catch {
            issue = ABIssue.from(error, context: "Umbenennen fehlgeschlagen")
        }
    }

    func delete(_ list: [DeviceEntry]) async {
        guard let backend = device?.backend else { return }
        var failures = 0
        var lastError: Error?
        for e in list {
            do { try await backend.delete(handle: e.handle) } catch { failures += 1; lastError = error }
        }
        invalidateCache()
        reload(force: true)
        await device?.refreshStorages()
        if failures > 0, let lastError {
            var i = ABIssue.from(lastError, context: "Löschen fehlgeschlagen")
            i.message = "\(failures) von \(list.count) Objekten konnten nicht gelöscht werden. " + i.message
            issue = i
        }
    }
}

/// Ordneransicht des Macs.
@MainActor
final class LocalBrowserModel: ObservableObject {
    @Published private(set) var folder: URL
    @Published private(set) var entries: [LocalEntry] = []
    @Published private(set) var visible: [LocalEntry] = []
    @Published var selection = Set<URL>()
    @Published var sort: EntrySort = .name { didSet { recompute() } }
    @Published var search = "" { didSet { recompute() } }
    @Published var showHidden = false { didSet { reload() } }
    @Published var issue: ABIssue?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false

    private var backStack: [URL] = []
    private var forwardStack: [URL] = []
    private var watcher: DispatchSourceFileSystemObject?
    private var reloadScheduled = false

    init(start: URL) {
        folder = start
        reload()
    }

    var selectedEntries: [LocalEntry] { visible.filter { selection.contains($0.url) } }

    var crumbs: [URL] {
        var list: [URL] = []
        var u = folder.standardizedFileURL
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        while true {
            list.insert(u, at: 0)
            if u.path == "/" || u == home { break }
            let parent = u.deletingLastPathComponent()
            if parent.path == u.path { break }
            u = parent
        }
        return list
    }

    func open(_ url: URL, recordHistory: Bool = true) {
        let target = url.standardizedFileURL
        guard target != folder.standardizedFileURL else { return }
        if recordHistory {
            backStack.append(folder)
            forwardStack.removeAll()
        }
        folder = target
        selection = []
        search = ""
        updateFlags()
        reload()
    }

    func enter(_ entry: LocalEntry) {
        if entry.isFolder && !entry.isPackage {
            open(entry.url)
        } else {
            NSWorkspace.shared.open(entry.url)
        }
    }

    func goUp() {
        let parent = folder.deletingLastPathComponent()
        if parent.path != folder.path { open(parent) }
    }

    func back() {
        guard let prev = backStack.popLast() else { return }
        forwardStack.append(folder)
        folder = prev
        selection = []
        updateFlags()
        reload()
    }

    func forward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(folder)
        folder = next
        selection = []
        updateFlags()
        reload()
    }

    private func updateFlags() {
        canGoBack = !backStack.isEmpty
        canGoForward = !forwardStack.isEmpty
    }

    func reload() {
        do {
            entries = try LocalFiles.list(folder, showHidden: showHidden)
            issue = nil
        } catch {
            entries = []
            issue = ABIssue.from(error, context: "Ordner konnte nicht gelesen werden")
        }
        recompute()
        watch()
    }

    func recompute() {
        var list = entries
        if !search.isEmpty { list = list.filter { EntrySorting.matches(name: $0.name, query: search) } }
        visible = EntrySorting.sorted(list, by: sort)
        selection = selection.intersection(Set(visible.map(\.url)))
    }

    /// Ordner beobachten und bei Änderungen neu einlesen (ohne Abfragen im Takt).
    private func watch() {
        watcher?.cancel()
        watcher = nil
        let fd = Darwin.open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, !self.reloadScheduled else { return }
            self.reloadScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                self.reloadScheduled = false
                self.reloadKeepingSelection()
            }
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        watcher = source
    }

    private func reloadKeepingSelection() {
        let keep = selection
        if let list = try? LocalFiles.list(folder, showHidden: showHidden) {
            entries = list
            recompute()
            selection = keep.intersection(Set(visible.map(\.url)))
        }
    }

    func selectAll() { selection = Set(visible.map(\.url)) }
    func deselectAll() { selection = [] }
    func invertSelection() { selection = Set(visible.map(\.url)).subtracting(selection) }

    func createFolder(named name: String) {
        let clean = FileNameSanitizer.macSafe(name)
        let unique = ConflictNaming.uniqueName(for: clean, existing: Set(entries.map(\.url.lastPathComponent)))
        let url = folder.appendingPathComponent(unique, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            reloadKeepingSelection()
            selection = [url.standardizedFileURL]
        } catch {
            issue = ABIssue.from(error, context: "Ordner konnte nicht angelegt werden")
        }
    }

    func rename(_ entry: LocalEntry, to name: String) {
        let clean = FileNameSanitizer.macSafe(name)
        guard clean != entry.url.lastPathComponent else { return }
        let target = entry.url.deletingLastPathComponent().appendingPathComponent(clean)
        do {
            try FileManager.default.moveItem(at: entry.url, to: target)
            reloadKeepingSelection()
        } catch {
            issue = ABIssue.from(error, context: "Umbenennen fehlgeschlagen")
        }
    }

    /// In den Papierkorb legen (nie endgültig löschen).
    func moveToTrash(_ list: [LocalEntry]) {
        var failed = 0
        for e in list {
            do { try FileManager.default.trashItem(at: e.url, resultingItemURL: nil) } catch { failed += 1 }
        }
        reloadKeepingSelection()
        if failed > 0 {
            issue = ABIssue(kind: .permissionDenied, title: "Nicht alles konnte in den Papierkorb gelegt werden",
                            message: "\(failed) Objekte wurden nicht bewegt.", recommendation: nil, technical: nil)
        }
    }
}

/// Zwischenablage für Kopieren/Einfügen zwischen den Spalten.
enum TransferClipboard {
    case device(deviceID: UInt64, entries: [DeviceEntry], path: [String])
    case local([URL])
}

/// Zustand des Dateimanagers (beide Spalten, aktive Spalte, Ansicht).
@MainActor
final class FileManagerModel: ObservableObject {
    @Published var layout: FileManagerLayout = .dual
    @Published var activePane: Pane = .device
    @Published var clipboard: TransferClipboard?
    @Published var confirmDelete: Pane?
    @Published var newFolderPane: Pane?
    @Published var renamePane: Pane?
    @Published var focusSearchToken = UUID()

    let local: LocalBrowserModel
    let device: DeviceBrowserModel
    private let settings: SettingsStore
    private let transfers: TransferEngine
    private let recents: RecentsStore

    init(settings: SettingsStore, transfers: TransferEngine, recents: RecentsStore) {
        self.settings = settings
        self.transfers = transfers
        self.recents = recents
        let start = URL(fileURLWithPath: settings.downloadFolderPath).deletingLastPathComponent()
        let exists = FileManager.default.fileExists(atPath: start.path)
        local = LocalBrowserModel(start: exists ? start : FileManager.default.homeDirectoryForCurrentUser)
        device = DeviceBrowserModel(settings: settings)
    }

    var deviceSelectionCount: Int { device.selection.count }
    var localSelectionCount: Int { local.selection.count }

    var deviceSelectionSize: UInt64 { device.selectedEntries.reduce(0) { $0 + ($1.isFolder ? 0 : $1.size) } }
    var localSelectionSize: UInt64 { local.selectedEntries.reduce(0) { $0 + ($1.isFolder ? 0 : $1.size) } }

    // MARK: Übertragen

    /// Auswahl vom Telefon in den links geöffneten Mac-Ordner (bzw. in die intelligenten Ziele in Einzelspaltenansicht).
    func transferDeviceSelectionToMac(useSmartDestination: Bool = false) {
        transferToMac(device.selectedEntries, useSmartDestination: useSmartDestination || layout != .dual)
    }

    func transferToMac(_ entries: [DeviceEntry], useSmartDestination: Bool, destination: URL? = nil) {
        guard let dev = device.device, !entries.isEmpty else { return }
        if let destination {
            transfers.download(entries, from: dev, sourcePath: device.pathNames, to: destination)
        } else if useSmartDestination {
            // nach Art gruppieren (Fotos → Bilder, Videos → Filme …)
            let groups = Dictionary(grouping: entries) { settings.destination(for: $0.kind).path }
            for (path, group) in groups.sorted(by: { $0.key < $1.key }) {
                transfers.download(group, from: dev, sourcePath: device.pathNames, to: URL(fileURLWithPath: path, isDirectory: true))
            }
        } else {
            transfers.download(entries, from: dev, sourcePath: device.pathNames, to: local.folder)
        }
        if let loc = device.location {
            for e in entries where !e.isFolder { recents.add(name: e.name, size: e.size, location: loc) }
        }
    }

    func transferLocalSelectionToDevice() {
        uploadToDevice(local.selectedEntries.map(\.url))
    }

    func uploadToDevice(_ urls: [URL]) {
        guard let dev = device.device, let storageID = device.storageID, !urls.isEmpty else { return }
        var parent = device.parentHandle
        var path = device.pathNames
        if device.crumbs.isEmpty, let folderName = settings.uploadTarget.folderName,
           let target = device.entries.first(where: { $0.isFolder && $0.name.lowercased() == folderName.lowercased() }) {
            parent = target.handle
            path = [target.name]
        }
        transfers.upload(urls, to: dev, storageID: storageID, parent: parent, destinationPath: path)
    }

    // MARK: Befehle (Tastenkürzel wirken auf die aktive Spalte)

    func copySelection() {
        switch activePane {
        case .device:
            guard let dev = device.device, !device.selection.isEmpty else { return }
            clipboard = .device(deviceID: dev.id, entries: device.selectedEntries, path: device.pathNames)
        case .local:
            guard !local.selection.isEmpty else { return }
            clipboard = .local(local.selectedEntries.map(\.url))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(local.selectedEntries.map { $0.url as NSURL })
        }
    }

    func paste() {
        switch (clipboard, activePane) {
        case let (.device(deviceID, entries, path)?, .local):
            guard let dev = device.device, dev.id == deviceID else { return }
            transfers.download(entries, from: dev, sourcePath: path, to: local.folder)
        case let (.local(urls)?, .device):
            uploadToDevice(urls)
        case (nil, .device):
            // Dateien aus dem Finder (⌘C im Finder, ⌘V hier)
            let urls = (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            uploadToDevice(urls)
        default:
            break
        }
    }

    func selectAll() { activePane == .device ? device.selectAll() : local.selectAll() }
    func deselectAll() { activePane == .device ? device.deselectAll() : local.deselectAll() }
    func invertSelection() { activePane == .device ? device.invertSelection() : local.invertSelection() }

    func refresh() {
        if activePane == .device {
            device.invalidateCache()
            device.reload(force: true)
        } else {
            local.reload()
        }
    }

    func requestDelete() {
        if activePane == .device ? !device.selection.isEmpty : !local.selection.isEmpty { confirmDelete = activePane }
    }

    func requestNewFolder() {
        if activePane == .device && device.device == nil { return }
        newFolderPane = activePane
    }

    func openSelection() {
        switch activePane {
        case .device:
            if let e = device.selectedEntries.first, device.selection.count == 1, e.isFolder { device.enter(e) }
        case .local:
            if let e = local.selectedEntries.first, local.selection.count == 1 { local.enter(e) }
        }
    }

    func focusSearch() { focusSearchToken = UUID() }
}

/// Ein Medium in der Galerie (mit Ordnerpfad für Filter).
struct MediaItem: Identifiable, Hashable {
    var id: String { entry.id }
    let entry: DeviceEntry
    let path: [String]
}

/// Bild- bzw. Videoansicht.
struct MediaViewerItem: Identifiable, Equatable {
    let id = UUID()
    let deviceID: UInt64
    let items: [DeviceEntry]
    var index: Int
}

/// Galerie: durchsucht die üblichen Medienordner aller Speicher.
@MainActor
final class GalleryModel: ObservableObject {
    @Published private(set) var device: DeviceConnection?
    @Published private(set) var items: [MediaItem] = []
    @Published private(set) var visible: [MediaItem] = []
    @Published var filter: MediaFilter = .media { didSet { recompute() } }
    @Published var sort: EntrySort = .newest { didSet { recompute() } }
    @Published var search = "" { didSet { recompute() } }
    @Published var selection = Set<String>()
    @Published private(set) var isScanning = false
    @Published private(set) var scannedFolders = 0
    @Published var issue: ABIssue?
    @Published private(set) var lastScan: Date?

    private let settings: SettingsStore
    private var scanTask: Task<Void, Never>?
    /// App-Daten (Android/data, Android/obb) enthalten keine Benutzermedien und sind teils riesig.
    private let skipped: Set<String> = ["android/data", "android/obb", ".thumbnails", ".trashed", ".pending"]

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var selectedItems: [MediaItem] { visible.filter { selection.contains($0.id) } }
    var selectedSize: UInt64 { selectedItems.reduce(0) { $0 + $1.entry.size } }

    func attach(_ device: DeviceConnection) {
        guard self.device?.id != device.id else { return }
        scanTask?.cancel()
        self.device = device
        items = []
        selection = []
        lastScan = nil
        recompute()
    }

    func detach() {
        scanTask?.cancel()
        device = nil
        items = []
        selection = []
        isScanning = false
        recompute()
    }

    func scanIfNeeded() {
        if lastScan == nil && !isScanning { scan() }
    }

    func scan() {
        guard let device, let backend = device.backend, device.state == .connected else { return }
        scanTask?.cancel()
        isScanning = true
        scannedFolders = 0
        issue = nil
        items = []
        recompute()
        let storages = device.storages
        scanTask = Task { [weak self] in
            var found: [MediaItem] = []
            var pendingFlush = 0
            for storage in storages {
                var queue: [(UInt32, [String], Int)] = [(MTPHandle.root, [], 0)]
                while !queue.isEmpty {
                    if Task.isCancelled { return }
                    let (parent, path, depth) = queue.removeFirst()
                    let children: [DeviceEntry]
                    do {
                        children = try await backend.list(storage: storage.id, parent: parent)
                    } catch is CancellationError {
                        return
                    } catch {
                        if (error as? MTPError) == .disconnected { break }
                        continue
                    }
                    guard let self else { return }
                    self.scannedFolders += 1
                    for c in children {
                        if c.isFolder {
                            let childPath = path + [c.name]
                            let key = childPath.joined(separator: "/").lowercased()
                            if depth < 10, !self.skipped.contains(key), !c.name.hasPrefix(".") || self.settings.showHiddenAndroidFiles {
                                queue.append((c.handle, childPath, depth + 1))
                            }
                        } else if c.kind != .other || !c.isHidden {
                            if c.isHidden && !self.settings.showHiddenAndroidFiles { continue }
                            found.append(MediaItem(entry: c, path: path))
                            pendingFlush += 1
                        }
                    }
                    if pendingFlush > 200 {
                        pendingFlush = 0
                        self.items = found
                        self.recompute()
                    }
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.items = found
            self.recompute()
            self.isScanning = false
            self.lastScan = Date()
        }
    }

    func recompute() {
        var list = items.filter { filter.matches(name: $0.entry.name, kind: $0.entry.kind, path: $0.path) }
        if !search.isEmpty { list = list.filter { EntrySorting.matches(name: $0.entry.name, query: search) } }
        let sorted = EntrySorting.sorted(list.map(\.entry), by: sort, foldersFirst: false)
        let byID = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        visible = sorted.compactMap { byID[$0.id] }
        selection = selection.intersection(Set(visible.map(\.id)))
    }

    func counts() -> [MediaFilter: Int] {
        var out: [MediaFilter: Int] = [:]
        for f in MediaFilter.allCases {
            out[f] = items.filter { f.matches(name: $0.entry.name, kind: $0.entry.kind, path: $0.path) }.count
        }
        return out
    }
}
