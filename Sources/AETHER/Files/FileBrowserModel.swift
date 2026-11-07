import Foundation
import AppKit
import UniformTypeIdentifiers
import AetherCore

/// Zustand und Aktionen von „Dateien“ (Finder Plus). Alle Dateizugriffe laufen außerhalb des Hauptthreads.
/// Grundsätze: nie überschreiben (Namenskonflikte → „Name 2“), nie endgültig löschen (nur Papierkorb, mit Widerrufen).
@MainActor
final class FileBrowserModel: ObservableObject {
    enum ViewMode: String, CaseIterable, Identifiable {
        case list, icons, columns
        var id: String { rawValue }
    }

    enum LoadState: Equatable {
        case loading
        case loaded
        case noPermission
        case notFound
        case failed(String)
    }

    enum SearchScope: String, CaseIterable, Identifiable {
        case folder, home, mac
        var id: String { rawValue }
    }

    enum SearchKind: String, CaseIterable, Identifiable {
        case any, folders, documents, images, videos, audio, pdf, apps
        var id: String { rawValue }
    }

    enum SearchDate: String, CaseIterable, Identifiable {
        case any, today, week, month, year
        var id: String { rawValue }
    }

    /// Ergebnisliste statt Ordnerinhalt (Spotlight-Suche oder „Zuletzt verwendet“).
    struct ResultList: Equatable {
        enum Kind: Equatable { case search, recents }
        var kind: Kind
        var title: String
        var items: [FileItem]
        var isGathering: Bool
        var truncated: Bool
    }

    struct Banner: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var isError: Bool
        var undoable: Bool
    }

    struct FileOperation: Equatable {
        var title: String
        var completedItems: Int
        var totalItems: Int
        var completedBytes: Int64
        var totalBytes: Int64
        var current: String
    }

    // MARK: Zustand

    @Published private(set) var location: URL
    @Published private(set) var items: [FileItem] = []
    @Published private(set) var state: LoadState = .loading
    @Published var selection: Set<URL> = []
    @Published var sortOrder: [KeyPathComparator<FileItem>] = [KeyPathComparator(\FileItem.name, comparator: .localizedStandard)] {
        didSet { applySort() }
    }
    @Published var foldersFirst = true { didSet { applySort() } }
    @Published var viewMode: ViewMode = .list
    @Published var showHidden = false { didSet { columnItems.removeAll(); reload() } }
    @Published var showInspector = false
    @Published var showFolderSizes = false { didSet { if showFolderSizes { computeFolderSizes() } else { cancelFolderSizes() } } }
    @Published private(set) var backStack: [URL] = []
    @Published private(set) var forwardStack: [URL] = []
    @Published private(set) var availableSpace: Int64?
    @Published private(set) var folderSizes: [URL: Int64] = [:]
    @Published private(set) var sizing: Set<URL> = []
    @Published private(set) var columnItems: [URL: [FileItem]] = [:]
    @Published private(set) var results: ResultList?
    @Published private(set) var operation: FileOperation?
    @Published var banner: Banner?
    @Published var searchText = ""
    @Published var searchScope: SearchScope = .folder
    @Published var searchKind: SearchKind = .any
    @Published var searchDate: SearchDate = .any
    @Published var searchContents = false

    weak var undoManager: UndoManager?
    private var generation = 0
    private var watcher: DispatchSourceFileSystemObject?
    private var reloadPending = false
    private var columnLoading: Set<URL> = []
    private var sizeCancel: CancelFlag?
    private var operationCancel: CancelFlag?
    private var query: NSMetadataQuery?
    private var queryObservers: [NSObjectProtocol] = []
    private var lastUndo: (() -> Void)?
    private let ioQueue = DispatchQueue(label: "aether.files.io", qos: .userInitiated)
    private let operationQueue = DispatchQueue(label: "aether.files.operations", qos: .userInitiated)
    private let isSnapshot: Bool

    init(start: URL = FileManager.default.homeDirectoryForCurrentUser, isSnapshot: Bool = false) {
        location = start
        self.isSnapshot = isSnapshot
    }

    var isSnapshotMode: Bool { isSnapshot }

    var displayedItems: [FileItem] { results?.items ?? items }

    var selectedItems: [FileItem] {
        displayedItems.filter { selection.contains($0.url) }
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool { location.path != "/" }

    // MARK: Navigation

    func start() {
        if items.isEmpty { reload() }
    }

    func navigate(to url: URL, select: URL? = nil) {
        let target = url.standardizedFileURL
        clearResults()
        guard target != location else {
            if let select { selection = [select] }
            return
        }
        backStack.append(location)
        forwardStack.removeAll()
        location = target
        selection = select.map { [$0] } ?? []
        reload()
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        clearResults()
        forwardStack.append(location)
        location = previous
        selection = []
        reload()
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        clearResults()
        backStack.append(location)
        location = next
        selection = []
        reload()
    }

    func goUp() {
        guard canGoUp else { return }
        let current = location
        navigate(to: location.deletingLastPathComponent(), select: current)
    }

    /// Öffnet eine Anfrage von außerhalb (z. B. „In Dateien öffnen“ aus dem Speicherbereich).
    func reveal(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            banner = Banner(text: tr("“%@” no longer exists.", url.lastPathComponent), isError: true, undoable: false)
            return
        }
        let isPackage = (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
        if isDirectory.boolValue && !isPackage {
            navigate(to: url)
        } else {
            navigate(to: url.deletingLastPathComponent(), select: url)
        }
    }

    // MARK: Laden

    func reload() {
        generation += 1
        let current = generation
        let folder = location
        let hidden = showHidden
        if items.isEmpty || items.first?.parentPath != folder.path { state = .loading }
        cancelFolderSizes()
        ioQueue.async { [weak self] in
            let result = DirectoryLoader.load(folder, showHidden: hidden)
            let space = (try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                .volumeAvailableCapacityForImportantUsage
            Task { @MainActor in
                guard let self, current == self.generation else { return }
                self.availableSpace = space
                switch result {
                case .success(let list):
                    self.items = self.sorted(list)
                    self.state = .loaded
                    self.selection = self.selection.filter { url in list.contains { $0.url == url } }
                    self.columnItems[folder] = self.items
                    self.watch(folder)
                    if self.showFolderSizes { self.computeFolderSizes() }
                case .failure(let failure):
                    self.items = []
                    self.stopWatching()
                    switch failure {
                    case .noPermission: self.state = .noPermission
                    case .notFound: self.state = .notFound
                    case .other(let message): self.state = .failed(message)
                    }
                }
            }
        }
    }

    private func sorted(_ list: [FileItem]) -> [FileItem] {
        var result = list.sorted(using: sortOrder)
        if foldersFirst {
            result = result.filter(\.isFolder) + result.filter { !$0.isFolder }
        }
        return result
    }

    private func applySort() {
        items = sorted(items)
        if var list = results {
            list.items = list.items.sorted(using: sortOrder)
            results = list
        }
        for (url, list) in columnItems { columnItems[url] = sorted(list) }
    }

    /// Ordner beobachten: Änderungen von außen (Finder, andere Apps) erscheinen sofort.
    private func watch(_ folder: URL) {
        stopWatching()
        let descriptor = Darwin.open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete],
                                                               queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.scheduleReload() }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
        watcher = source
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }

    private func scheduleReload() {
        guard !reloadPending else { return }
        reloadPending = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            self?.reloadPending = false
            self?.reload()
        }
    }

    /// Inhalt eines Ordners für die Spaltenansicht (zwischengespeichert, lädt bei Bedarf).
    func children(of folder: URL) -> [FileItem]? {
        if folder == location, state == .loaded { return items }
        if let cached = columnItems[folder] { return cached }
        guard !columnLoading.contains(folder) else { return nil }
        columnLoading.insert(folder)
        let hidden = showHidden
        ioQueue.async { [weak self] in
            let list = (try? DirectoryLoader.load(folder, showHidden: hidden).get()) ?? []
            Task { @MainActor in
                guard let self else { return }
                self.columnLoading.remove(folder)
                self.columnItems[folder] = self.sorted(list)
            }
        }
        return nil
    }

    // MARK: Öffnen

    func open(_ item: FileItem) {
        if item.isFolder {
            navigate(to: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    func openSelection() {
        let selected = selectedItems
        if selected.count == 1, let item = selected.first {
            open(item)
        } else {
            for item in selected where !item.isFolder { NSWorkspace.shared.open(item.url) }
        }
    }

    func showPackageContents(_ item: FileItem) {
        navigate(to: item.url)
    }

    func open(_ urls: [URL], with application: URL) {
        NSWorkspace.shared.open(urls, withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            if let error {
                Task { @MainActor in self?.banner = Banner(text: error.localizedDescription, isError: true, undoable: false) }
            }
        }
    }

    func applications(for url: URL) -> [URL] {
        Array(NSWorkspace.shared.urlsForApplications(toOpen: url).prefix(15))
    }

    func showInFinder(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls.isEmpty ? [location] : urls)
    }

    func copyPaths(_ urls: [URL]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    // MARK: Zwischenablage

    func copyToPasteboard(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls.map { $0 as NSURL })
    }

    var pasteboardURLs: [URL] {
        (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    func paste(move: Bool) {
        let urls = pasteboardURLs
        guard !urls.isEmpty else { return }
        transfer(urls, to: location, move: move)
    }

    // MARK: Kopieren und Verschieben

    /// Kopiert oder verschiebt Objekte in einen Ordner. Namenskonflikte → „Name 2“ (nie überschreiben).
    func transfer(_ sources: [URL], to destination: URL, move: Bool) {
        guard operation == nil else {
            banner = Banner(text: tr("Another operation is still running."), isError: true, undoable: false)
            return
        }
        let sources = sources.filter { $0.standardizedFileURL != destination.standardizedFileURL }
        if let bad = sources.first(where: { PathTrail.isInside(destination.path, folder: $0.path) }) {
            banner = Banner(text: tr("“%@” can’t be placed inside itself.", bad.lastPathComponent), isError: true, undoable: false)
            return
        }
        // Verschieben innerhalb desselben Ordners ist nichts
        let effective = move ? sources.filter { $0.deletingLastPathComponent().standardizedFileURL != destination.standardizedFileURL } : sources
        guard !effective.isEmpty else { return }

        let cancel = CancelFlag()
        operationCancel = cancel
        let title = move ? tr("Moving") : tr("Copying")
        operation = FileOperation(title: title, completedItems: 0, totalItems: effective.count, completedBytes: 0, totalBytes: 0, current: "")
        operationQueue.async { [weak self] in
            let fm = FileManager.default
            // Gesamtgröße vorab (für den Fortschritt)
            var sizes: [Int64] = []
            for url in effective {
                let size = move ? 0 : Self.itemSize(url)
                sizes.append(size)
            }
            let total = sizes.reduce(0, +)
            Task { @MainActor in self?.operation?.totalBytes = total }

            var existing = Set((try? fm.contentsOfDirectory(atPath: destination.path)) ?? [])
            var created: [(source: URL, result: URL)] = []
            var failures: [String] = []
            var done: Int64 = 0
            for (index, source) in effective.enumerated() {
                if cancel.isCancelled { break }
                let isDirectory = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let name = FileNaming.uniqueName(for: source.lastPathComponent, existing: existing, isDirectory: isDirectory)
                existing.insert(name)
                let target = destination.appendingPathComponent(name)
                let currentName = source.lastPathComponent
                Task { @MainActor in self?.operation?.current = currentName }
                do {
                    if move {
                        try fm.moveItem(at: source, to: target)
                    } else {
                        try fm.copyItem(at: source, to: target)
                    }
                    created.append((source, target))
                } catch {
                    failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
                }
                done += sizes[index]
                let completed = index + 1
                let bytes = done
                Task { @MainActor in
                    self?.operation?.completedItems = completed
                    self?.operation?.completedBytes = bytes
                }
            }
            let records = created
            let errors = failures
            Task { @MainActor in
                guard let self else { return }
                self.operation = nil
                self.operationCancel = nil
                self.reload()
                self.selection = Set(records.map(\.result).filter { $0.deletingLastPathComponent().standardizedFileURL == self.location })
                if !records.isEmpty {
                    if move {
                        self.registerUndo(name: tr("Move")) { model in model.undoMove(records) }
                    } else {
                        self.registerUndo(name: tr("Copy")) { model in model.trashCopies(records.map(\.result)) }
                    }
                }
                if !errors.isEmpty {
                    self.banner = Banner(text: tr("%ld items couldn’t be processed: %@", errors.count, errors.prefix(3).joined(separator: "; ")),
                                         isError: true, undoable: false)
                } else if !records.isEmpty {
                    let text = move ? tr("%ld items moved", records.count) : tr("%ld items copied", records.count)
                    self.banner = Banner(text: text, isError: false, undoable: true)
                }
            }
        }
    }

    func cancelOperation() {
        operationCancel?.cancel()
    }

    nonisolated private static func itemSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey])
        if values?.isDirectory == true {
            return DirectoryLoader.folderSize(url, isCancelled: { false })?.bytes ?? 0
        }
        return Int64(values?.fileSize ?? values?.totalFileAllocatedSize ?? 0)
    }

    private func undoMove(_ records: [(source: URL, result: URL)]) {
        var failures = 0
        var reversed: [(source: URL, result: URL)] = []
        for record in records {
            let back = record.source
            if FileManager.default.fileExists(atPath: back.path) { failures += 1; continue }
            do {
                try FileManager.default.moveItem(at: record.result, to: back)
                reversed.append((record.result, back))
            } catch {
                failures += 1
            }
        }
        reload()
        if !reversed.isEmpty {
            registerUndo(name: tr("Move")) { model in model.undoMove(reversed) }
        }
        if failures > 0 {
            banner = Banner(text: tr("%ld items couldn’t be moved back.", failures), isError: true, undoable: false)
        }
    }

    /// Widerrufen eines Kopiervorgangs: die Kopien kommen in den Papierkorb (nicht endgültig gelöscht).
    private func trashCopies(_ urls: [URL]) {
        trash(urls, actionName: tr("Copy"))
    }

    // MARK: Papierkorb

    func trashSelection() {
        trash(selectedItems.map(\.url), actionName: tr("Move to Trash"))
    }

    func trash(_ urls: [URL], actionName: String) {
        guard !urls.isEmpty else { return }
        var records: [(original: URL, trashed: URL)] = []
        var failures: [String] = []
        for url in urls {
            var resulting: NSURL?
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
                if let trashed = resulting as URL? { records.append((url, trashed)) }
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        selection = []
        reload()
        if !records.isEmpty {
            registerUndo(name: actionName) { model in model.restoreFromTrash(records, actionName: actionName) }
            banner = Banner(text: tr("%ld items moved to the Trash", records.count), isError: false, undoable: true)
        }
        if !failures.isEmpty {
            banner = Banner(text: tr("%ld items couldn’t be moved to the Trash: %@", failures.count, failures.prefix(3).joined(separator: "; ")),
                            isError: true, undoable: false)
        }
    }

    private func restoreFromTrash(_ records: [(original: URL, trashed: URL)], actionName: String) {
        var restored: [URL] = []
        var failures = 0
        for record in records {
            guard !FileManager.default.fileExists(atPath: record.original.path) else { failures += 1; continue }
            do {
                try FileManager.default.moveItem(at: record.trashed, to: record.original)
                restored.append(record.original)
            } catch {
                failures += 1
            }
        }
        reload()
        selection = Set(restored.filter { $0.deletingLastPathComponent().standardizedFileURL == location })
        if !restored.isEmpty {
            registerUndo(name: actionName) { model in model.trash(restored, actionName: actionName) }
            banner = Banner(text: tr("%ld items put back", restored.count), isError: false, undoable: false)
        }
        if failures > 0 {
            banner = Banner(text: tr("%ld items couldn’t be put back.", failures), isError: true, undoable: false)
        }
    }

    // MARK: Neu, Umbenennen, Duplizieren

    /// Legt „Neuer Ordner“ an und gibt die Adresse zurück (zum anschließenden Umbenennen).
    @discardableResult
    func newFolder() -> URL? {
        let existing = Set(((try? FileManager.default.contentsOfDirectory(atPath: location.path)) ?? []))
        let name = FileNaming.uniqueName(for: tr("untitled folder"), existing: existing, isDirectory: true)
        let url = location.appendingPathComponent(name, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            registerUndo(name: tr("New Folder")) { model in model.trash([url], actionName: tr("New Folder")) }
            reload()
            selection = [url]
            return url
        } catch {
            banner = Banner(text: error.localizedDescription, isError: true, undoable: false)
            return nil
        }
    }

    func duplicateSelection() {
        transfer(selectedItems.map(\.url), to: location, move: false)
    }

    /// Prüft einen neuen Namen für ein Objekt (nil = in Ordnung).
    func renameProblem(for item: FileItem, newName: String) -> String? {
        if let problem = FileNaming.validate(newName), FileNaming.isBlocking(problem) {
            return problemText(problem)
        }
        if newName.lowercased() != item.fileName.lowercased() {
            let target = item.url.deletingLastPathComponent().appendingPathComponent(newName)
            if FileManager.default.fileExists(atPath: target.path) { return tr("An item with this name already exists.") }
        }
        return nil
    }

    func problemText(_ problem: FileNaming.Problem) -> String {
        switch problem {
        case .empty: return tr("The name can’t be empty.")
        case .containsSlash: return tr("The name can’t contain “/”.")
        case .containsColon: return tr("The name can’t contain “:”.")
        case .tooLong: return tr("The name is too long.")
        case .reserved: return tr("This name is reserved.")
        case .hidden: return tr("Names starting with a dot are hidden.")
        }
    }

    func rename(_ item: FileItem, to newName: String) {
        guard newName != item.fileName, renameProblem(for: item, newName: newName) == nil else { return }
        let target = item.url.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: item.url, to: target)
            let oldName = item.fileName
            registerUndo(name: tr("Rename")) { model in
                if let renamed = FileItem(url: target) { model.rename(renamed, to: oldName) }
            }
            reload()
            selection = [target]
        } catch {
            banner = Banner(text: error.localizedDescription, isError: true, undoable: false)
        }
    }

    /// Stapel-Umbenennung in zwei Schritten (über temporäre Namen), damit Tausch-Umbenennungen nicht kollidieren.
    func applyBatchRename(_ entries: [BatchRenameEntry], items: [FileItem]) {
        guard BatchRenamePlanner.canApply(entries), entries.count == items.count else { return }
        let fm = FileManager.default
        var temporary: [(item: FileItem, temp: URL, final: URL)] = []
        var failures = 0
        for (entry, item) in zip(entries, items) where entry.changes {
            let folder = item.url.deletingLastPathComponent()
            let temp = folder.appendingPathComponent(".aether-rename-\(UUID().uuidString)")
            do {
                try fm.moveItem(at: item.url, to: temp)
                temporary.append((item, temp, folder.appendingPathComponent(entry.proposed)))
            } catch {
                failures += 1
            }
        }
        var done: [(from: URL, to: URL)] = []
        for record in temporary {
            do {
                try fm.moveItem(at: record.temp, to: record.final)
                done.append((record.item.url, record.final))
            } catch {
                // Zurück auf den alten Namen, damit nichts unter einem temporären Namen liegen bleibt
                try? fm.moveItem(at: record.temp, to: record.item.url)
                failures += 1
            }
        }
        reload()
        selection = Set(done.map(\.to))
        if !done.isEmpty {
            let reverse = done
            registerUndo(name: tr("Rename")) { model in model.revertBatchRename(reverse) }
        }
        if failures > 0 {
            banner = Banner(text: tr("%ld items couldn’t be renamed.", failures), isError: true, undoable: false)
        } else if !done.isEmpty {
            banner = Banner(text: tr("%ld items renamed", done.count), isError: false, undoable: true)
        }
    }

    private func revertBatchRename(_ records: [(from: URL, to: URL)]) {
        let fm = FileManager.default
        var temps: [(temp: URL, original: URL, renamed: URL)] = []
        for record in records {
            let temp = record.to.deletingLastPathComponent().appendingPathComponent(".aether-rename-\(UUID().uuidString)")
            if (try? fm.moveItem(at: record.to, to: temp)) != nil { temps.append((temp, record.from, record.to)) }
        }
        var redone: [(from: URL, to: URL)] = []
        for t in temps {
            if (try? fm.moveItem(at: t.temp, to: t.original)) != nil {
                redone.append((t.renamed, t.original))
            } else {
                try? fm.moveItem(at: t.temp, to: t.renamed)
            }
        }
        reload()
        if !redone.isEmpty {
            registerUndo(name: tr("Rename")) { model in model.revertBatchRename(redone) }
        }
    }

    // MARK: Widerrufen

    private func registerUndo(name: String, _ action: @escaping @MainActor (FileBrowserModel) -> Void) {
        lastUndo = { [weak self] in
            guard let self else { return }
            action(self)
        }
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            // Widerrufen läuft im Hauptthread; synchron ausführen, damit macOS die Gegenaktion als „Wiederholen“ einträgt.
            MainActor.assumeIsolated { action(model) }
        }
        undoManager.setActionName(name)
    }

    /// „Widerrufen“ im Hinweisbalken (entspricht ⌘Z).
    func undoLast() {
        if let undoManager, undoManager.canUndo {
            undoManager.undo()
        } else {
            lastUndo?()
        }
        lastUndo = nil
        banner = nil
    }

    // MARK: Ordnergrößen

    func computeFolderSizes(_ only: [URL]? = nil) {
        sizeCancel?.cancel()
        let cancel = CancelFlag()
        sizeCancel = cancel
        let targets = only ?? items.filter(\.isFolder).map(\.url)
        let pending = targets.filter { folderSizes[$0] == nil }
        guard !pending.isEmpty else { return }
        sizing.formUnion(pending)
        ioQueue.async { [weak self] in
            for url in pending {
                guard !cancel.isCancelled else { return }
                let result = DirectoryLoader.folderSize(url, isCancelled: { cancel.isCancelled })
                Task { @MainActor in
                    guard let self else { return }
                    self.sizing.remove(url)
                    if let result { self.folderSizes[url] = result.bytes }
                }
            }
        }
    }

    private func cancelFolderSizes() {
        sizeCancel?.cancel()
        sizeCancel = nil
        sizing.removeAll()
    }

    // MARK: Drag & Drop

    func handleDrop(_ providers: [NSItemProvider], into folder: URL) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        let forceCopy = NSEvent.modifierFlags.contains(.option)
        let group = DispatchGroup()
        let collector = URLCollector()
        for provider in fileProviders {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { collector.add(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            let urls = collector.all
            Task { @MainActor in self?.finishDrop(urls, into: folder, forceCopy: forceCopy) }
        }
        return true
    }

    private func finishDrop(_ urls: [URL], into folder: URL, forceCopy: Bool) {
        guard !urls.isEmpty else { return }
        // Wie im Finder: innerhalb desselben Volumes verschieben, zwischen Volumes kopieren; ⌥ erzwingt Kopieren.
        let destinationVolume = (try? folder.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
        let sameVolume = urls.allSatisfy {
            ((try? $0.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject) == destinationVolume
        }
        transfer(urls, to: folder, move: sameVolume && !forceCopy)
    }

    // MARK: Suche (Spotlight) und „Zuletzt verwendet“

    func runSearch() {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            clearResults()
            return
        }
        var predicates: [NSPredicate] = []
        let pattern = "*\(text)*"
        if searchContents {
            predicates.append(NSPredicate(format: "(%K LIKE[cd] %@) || (%K LIKE[cd] %@)", NSMetadataItemFSNameKey, pattern,
                                          "kMDItemTextContent", pattern))
        } else {
            predicates.append(NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, pattern))
        }
        if let kind = kindPredicate(searchKind) { predicates.append(kind) }
        if let since = sinceDate(searchDate) {
            predicates.append(NSPredicate(format: "%K >= %@", NSMetadataItemFSContentChangeDateKey, since as NSDate))
        }
        let scopes: [Any]
        switch searchScope {
        case .folder: scopes = [location]
        case .home: scopes = [NSMetadataQueryUserHomeScope]
        case .mac: scopes = [NSMetadataQueryLocalComputerScope]
        }
        startQuery(NSCompoundPredicate(andPredicateWithSubpredicates: predicates), scopes: scopes,
                   sort: nil, kind: .search, title: tr("Search: “%@”", text))
    }

    func showRecents() {
        searchText = ""
        let since = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let predicate = NSPredicate(format: "%K >= %@", "kMDItemLastUsedDate", since as NSDate)
        startQuery(predicate, scopes: [NSMetadataQueryUserHomeScope],
                   sort: NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false), kind: .recents, title: tr("Recent"))
    }

    private func kindPredicate(_ kind: SearchKind) -> NSPredicate? {
        let key = "kMDItemContentTypeTree"
        func tree(_ types: [String]) -> NSPredicate {
            NSCompoundPredicate(orPredicateWithSubpredicates: types.map { NSPredicate(format: "%K == %@", key, $0) })
        }
        switch kind {
        case .any: return nil
        case .folders: return tree(["public.folder"])
        case .documents: return tree(["public.text", "public.composite-content", "com.adobe.pdf", "public.spreadsheet", "public.presentation"])
        case .images: return tree(["public.image"])
        case .videos: return tree(["public.movie"])
        case .audio: return tree(["public.audio"])
        case .pdf: return tree(["com.adobe.pdf"])
        case .apps: return tree(["com.apple.application-bundle"])
        }
    }

    private func sinceDate(_ date: SearchDate) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        switch date {
        case .any: return nil
        case .today: return calendar.startOfDay(for: now)
        case .week: return calendar.date(byAdding: .day, value: -7, to: now)
        case .month: return calendar.date(byAdding: .month, value: -1, to: now)
        case .year: return calendar.date(byAdding: .year, value: -1, to: now)
        }
    }

    private static let resultLimit = 1_000

    private func startQuery(_ predicate: NSPredicate, scopes: [Any], sort: NSSortDescriptor?, kind: ResultList.Kind, title: String) {
        stopQuery()
        selection = []
        let query = NSMetadataQuery()
        query.predicate = predicate
        query.searchScopes = scopes
        if let sort { query.sortDescriptors = [sort] }
        results = ResultList(kind: kind, title: title, items: [], isGathering: true, truncated: false)
        let center = NotificationCenter.default
        queryObservers.append(center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.collectResults(final: true) }
        })
        queryObservers.append(center.addObserver(forName: .NSMetadataQueryGatheringProgress, object: query, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.collectResults(final: false) }
        })
        self.query = query
        if !query.start() {
            results = ResultList(kind: kind, title: title, items: [], isGathering: false, truncated: false)
            banner = Banner(text: tr("Spotlight search couldn’t be started."), isError: true, undoable: false)
        }
    }

    private func collectResults(final: Bool) {
        guard let query, let list = results else { return }
        query.disableUpdates()
        let count = query.resultCount
        var paths: [String] = []
        for index in 0..<min(count, Self.resultLimit) {
            if let item = query.result(at: index) as? NSMetadataItem,
               let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                paths.append(path)
            }
        }
        query.enableUpdates()
        if final { stopQuery() }
        let keepOrder = list.kind == .recents
        let order = sortOrder
        let base = list
        let truncated = count > Self.resultLimit
        ioQueue.async { [weak self] in
            var found = paths.compactMap { FileItem(url: URL(fileURLWithPath: $0)) }
            if !keepOrder { found = found.sorted(using: order) }
            let items = found
            Task { @MainActor in
                guard let self, self.results?.title == base.title, self.results?.kind == base.kind else { return }
                self.results = ResultList(kind: base.kind, title: base.title, items: items, isGathering: !final, truncated: truncated)
            }
        }
    }

    private func stopQuery() {
        query?.stop()
        query = nil
        queryObservers.forEach { NotificationCenter.default.removeObserver($0) }
        queryObservers.removeAll()
    }

    func clearResults() {
        stopQuery()
        if results != nil {
            results = nil
            selection = []
        }
    }
}

/// Abbruchsignal für Hintergrundarbeit (threadsicher).
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

/// Sammelt URLs aus mehreren Drag-&-Drop-Anbietern (Rückrufe kommen auf beliebigen Threads).
private final class URLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func add(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }

    var all: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }
}
