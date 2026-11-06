import Foundation
import AppKit
import CoreServices
import MLCore
import MLStore
import MLTags

/// Musikordner verwalten und einlesen (Android: MediaStoreScanner + LibrarySync).
///
/// - mehrere Musikordner, auch auf externen Laufwerken und Netzlaufwerken
/// - Einlesen im Hintergrund (nie im Hauptthread), mit Fortschritt
/// - Abgleich mit `SyncPlanner`: verschobene/umbenannte Dateien behalten Favoriten, Playlists und Statistik,
///   nicht gefundene Titel werden nie gelöscht, nur als „nicht verfügbar“ markiert
/// - Änderungen in den Ordnern werden über FSEvents erkannt, Laufwerke beim An-/Abmelden neu geprüft
@MainActor
final class LibraryService {
    /// Version des Tag-Lesers: bei einer Erhöhung werden alle Titel beim nächsten Einlesen neu gelesen.
    nonisolated static let tagReaderVersion = 1

    /// Abspielbare Dateiendungen (AVFoundation + eigener Ogg-Vorbis-Decoder).
    nonisolated static let audioExtensions: Set<String> = ["mp3", "m4a", "m4b", "mp4", "aac", "alac", "flac", "wav", "wave", "aif", "aiff", "aifc", "caf", "ogg", "oga", "opus"]

    weak var model: AppModel?
    let store: LibraryStore
    private var scanTask: Task<Void, Never>?
    private var pendingRescan = false
    private var lastProgressReport: TimeInterval = 0
    private var watcher: FolderWatcher?
    private var observers: [NSObjectProtocol] = []

    init(store: LibraryStore) {
        self.store = store
    }

    // MARK: - Start

    func start() {
        resolveBookmarks()
        model?.reloadFolders()
        if model?.settings.watchFolders ?? true { startWatching() }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.rescan(reason: "Laufwerk") }
            })
        }
        if model?.settings.scanOnLaunch ?? true {
            rescan(reason: "Start")
        } else {
            reconstructDatesAdded(useAppleMusic: false, force: false)
        }
    }

    /// Ordnerüberwachung ein- oder ausschalten (Einstellung „Ordner überwachen“).
    func setWatching(_ on: Bool) {
        if on { startWatching() } else { watcher = nil }
    }

    /// Ordner anhand gespeicherter Lesezeichen wiederfinden (z. B. umbenanntes externes Laufwerk).
    private func resolveBookmarks() {
        guard let folders = try? store.folders() else { return }
        for f in folders {
            guard let data = f.bookmark else { continue }
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale),
               url.path != f.path, FileManager.default.fileExists(atPath: url.path) {
                // Ordner wurde verschoben/Laufwerk umbenannt: neuen Pfad übernehmen
                _ = try? store.addFolder(path: url.path, bookmark: try? url.bookmarkData(), name: f.name, volumeName: Self.volumeName(url), isExternal: f.isExternal)
                try? store.removeFolder(id: f.id, deleteTracks: false)
            } else if stale, let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) {
                try? store.updateFolderBookmark(id: f.id, bookmark: try? url.bookmarkData())
            }
        }
    }

    // MARK: - Ordner

    /// Ordner auswählen (Dialog) und hinzufügen.
    func chooseFolders() {
        let panel = NSOpenPanel()
        panel.title = "Musikordner hinzufügen"
        panel.prompt = "Hinzufügen"
        panel.message = "Wähle einen oder mehrere Ordner mit deiner Musik. Die Dateien bleiben, wo sie sind."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK else { return }
        addFolders(panel.urls)
    }

    func addFolders(_ urls: [URL]) {
        var added = 0
        for url in urls {
            let std = url.standardizedFileURL
            // Unterordner eines bereits gewählten Ordners nicht doppelt aufnehmen
            if let existing = model?.folders, existing.contains(where: { std.path == $0.path || std.path.hasPrefix($0.path.hasSuffix("/") ? $0.path : $0.path + "/") }) {
                continue
            }
            let bookmark = try? std.bookmarkData()
            _ = try? store.addFolder(path: std.path, bookmark: bookmark, name: std.lastPathComponent, volumeName: Self.volumeName(std), isExternal: Self.isExternal(std))
            added += 1
        }
        model?.reloadFolders()
        if model?.settings.watchFolders ?? true { startWatching() }
        if added > 0 { rescan(reason: "Neuer Ordner") }
    }

    func removeFolder(_ folder: LibraryFolder, deleteTracks: Bool) {
        try? store.removeFolder(id: folder.id, deleteTracks: deleteTracks)
        model?.reloadFolders()
        model?.reloadLibrary()
        if model?.settings.watchFolders ?? true { startWatching() }
    }

    func reveal(_ folder: LibraryFolder) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder.path)])
    }

    static func volumeName(_ url: URL) -> String? {
        (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName
    }

    static func isExternal(_ url: URL) -> Bool {
        let v = try? url.resourceValues(forKeys: [.volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsLocalKey])
        if v?.volumeIsLocal == false { return true }
        if v?.volumeIsRemovable == true { return true }
        return v?.volumeIsInternal == false
    }

    func isOnline(_ folder: LibraryFolder) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: - Einlesen

    /// Bibliothek neu abgleichen. Läuft bereits ein Durchlauf, folgt direkt danach ein weiterer.
    func rescan(reason: String, fullTagRefresh: Bool = false) {
        guard let model, !model.demo else { return }
        if scanTask != nil {
            pendingRescan = true
            return
        }
        let store = self.store
        let folders = (try? store.folders()) ?? []
        let version = fullTagRefresh ? Int.max : Self.tagReaderVersion
        model.scanState = .running(done: 0, total: 0, folder: "")
        scanTask = Task.detached(priority: .utility) { [weak self] in
            let result = await LibraryService.performScan(store: store, folders: folders, tagReaderVersion: version) { [weak self] done, total, folder in
                Task { @MainActor [weak self] in self?.reportProgress(done: done, total: total, folder: folder) }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.scanTask = nil
                switch result {
                case .success(let summary):
                    self.model?.scanState = .finished(added: summary.added, updated: summary.updated, missing: summary.missing)
                    // Noch nicht rekonstruierte Hinzufügedaten (Import durch frühere Versionen) im Hintergrund bestimmen
                    self.reconstructDatesAdded(useAppleMusic: false, force: false)
                    if summary.added + summary.updated + summary.missing > 0 || !(self.model?.libraryLoaded ?? false) {
                        self.model?.reloadLibrary()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                        if case .finished = self?.model?.scanState { self?.model?.scanState = .idle }
                    }
                case .failure(let error):
                    self.model?.scanState = .failed(error.localizedDescription)
                    self.model?.reloadLibrary()
                }
                if self.pendingRescan {
                    self.pendingRescan = false
                    self.rescan(reason: "Nachholen")
                }
            }
        }
    }

    /// Fortschritt höchstens 4× pro Sekunde veröffentlichen – jede Änderung von `scanState` lässt das ganze
    /// Fenster neu auswerten (bei großen Bibliotheken sonst Hunderte Aktualisierungen während des Einlesens).
    private func reportProgress(done: Int, total: Int, folder: String) {
        let now = ProcessInfo.processInfo.systemUptime
        guard total == 0 || done >= total || now - lastProgressReport >= 0.25 else { return }
        lastProgressReport = now
        guard case .running = model?.scanState else { return }
        model?.scanState = .running(done: done, total: total, folder: folder)
    }

    struct ScanSummary {
        var added = 0
        var updated = 0
        var missing = 0
    }

    /// Der eigentliche Abgleich (Hintergrund).
    nonisolated static func performScan(store: LibraryStore, folders: [LibraryFolder], tagReaderVersion: Int,
                                        progress: @escaping @Sendable (Int, Int, String) -> Void) async -> Result<ScanSummary, Error> {
        do {
            let enabled = folders.filter(\.enabled)
            var scanned: [ScannedFile] = []
            var online = Set<Int64>()
            var trusted = Set<Int64>()
            let fm = FileManager.default
            for folder in enabled {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { continue }
                let root = URL(fileURLWithPath: folder.path, isDirectory: true)
                online.insert(folder.id)
                if fileIDsReliable(root) { trusted.insert(folder.id) }
                progress(0, 0, folder.name)
                scanned.append(contentsOf: enumerate(root: root, folderID: folder.id))
            }
            let known = try store.knownFiles()
            let plan = SyncPlanner.plan(known: known, scanned: scanned, onlineFolders: online, tagReaderVersion: tagReaderVersion, trustedFileIDFolders: trusted)
            var summary = ScanSummary()
            let folderByID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let total = plan.items.count
            var done = 0
            let now = Int64(Date().timeIntervalSince1970)
            // In Paketen verarbeiten: Tags parallel lesen, dann in einer Transaktion speichern
            for chunk in stride(from: 0, to: plan.items.count, by: 64).map({ Array(plan.items[$0..<min($0 + 64, plan.items.count)]) }) {
                if Task.isCancelled { break }
                let records: [(SyncItem, TrackRecord?)] = await withTaskGroup(of: (Int, TrackRecord?).self) { group in
                    for (i, item) in chunk.enumerated() {
                        group.addTask {
                            guard let folder = folderByID[item.file.folderID] else { return (i, nil) }
                            if !item.readTags { return (i, nil) }
                            return (i, makeRecord(item.file, folder: folder, version: tagReaderVersion == Int.max ? LibraryService.tagReaderVersion : tagReaderVersion))
                        }
                    }
                    var out = [TrackRecord?](repeating: nil, count: chunk.count)
                    for await (i, r) in group { out[i] = r }
                    return chunk.enumerated().map { ($0.element, out[$0.offset]) }
                }
                var inserts: [TrackRecord] = []
                var updates: [(uid: Int64, file: TrackRecord)] = []
                for (item, record) in records {
                    if let uid = item.uid {
                        if let record {
                            updates.append((uid, record))
                        } else if let folder = folderByID[item.file.folderID] {
                            // Nur Ort/Kennung aktualisieren
                            let rel = relativePath(item.file.path, root: folder.path)
                            try store.updateFileLocation(uid: uid, folderID: folder.id, path: item.file.path, relativePath: rel, fileName: item.file.fileName,
                                                         fileID: Int64(bitPattern: item.file.fileID ?? 0), sizeBytes: item.file.sizeBytes, dateModified: item.file.dateModified)
                        }
                        summary.updated += 1
                    } else if let record {
                        inserts.append(record)
                        summary.added += 1
                    }
                }
                // v2.1: eigenes Hinzufügedatum je neuer Datei (Apple Musik → Erstellungsdatum → Ordner → Import)
                let apple = inserts.isEmpty ? nil : LibraryService.loadAppleMusicIndex()
                let added = inserts.map { LibraryService.dateAddedForNewFile($0, apple: apple, now: now) }
                _ = try store.applyScan(inserts: inserts, addedDates: added, updates: updates, missing: [])
                done += chunk.count
                progress(done, total, "")
            }
            let gone = plan.missing + plan.offline
            if !gone.isEmpty {
                try store.setAvailability(uids: gone, available: false)
                summary.missing = plan.missing.count
            }
            for id in online { try? store.setFolderScanned(id: id, at: Int64(Date().timeIntervalSince1970 * 1000)) }
            return .success(summary)
        } catch {
            return .failure(error)
        }
    }

    /// Alle Audiodateien unterhalb eines Ordners (versteckte Dateien und Pakete übersprungen).
    nonisolated static func enumerate(root: URL, folderID: Int64) -> [ScannedFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .isAliasFileKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var result: [ScannedFile] = []
        for case let url as URL in e {
            let ext = url.pathExtension.lowercased()
            guard audioExtensions.contains(ext) else { continue }
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true, v.isAliasFile != true else { continue }
            var st = stat()
            let inode: UInt64? = lstat(url.path, &st) == 0 ? UInt64(st.st_ino) : nil
            let mtime = Int64(v.contentModificationDate?.timeIntervalSince1970 ?? 0)
            result.append(ScannedFile(folderID: folderID, path: url.path, sizeBytes: Int64(v.fileSize ?? 0), dateModified: mtime, fileID: inode, volumeID: nil))
        }
        return result
    }

    /// Dateikennungen sind auf APFS/HFS+ verlässlich, auf FAT/exFAT/Netzlaufwerken nicht.
    nonisolated static func fileIDsReliable(_ url: URL) -> Bool {
        var fs = statfs()
        guard statfs(url.path, &fs) == 0 else { return false }
        let name = withUnsafePointer(to: &fs.f_fstypename) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0) }
        }
        return ["apfs", "hfs"].contains(name)
    }

    nonisolated static func relativePath(_ path: String, root: String) -> String {
        let base = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(base) else { return "" }
        let rest = String(path.dropFirst(base.count))
        guard let slash = rest.lastIndex(of: "/") else { return "" }
        return String(rest[...slash])
    }

    /// Liest Tags und Audioangaben einer Datei; nicht lesbare Tags → Titel aus dem Dateinamen.
    nonisolated static func makeRecord(_ file: ScannedFile, folder: LibraryFolder, version: Int) -> TrackRecord {
        let url = URL(fileURLWithPath: file.path)
        var tags: TagValues?
        var audio = AudioProperties()
        if let result = try? TagFile.read(url: url) {
            tags = result.values
            audio = result.audio
        }
        let lrc = url.deletingPathExtension().appendingPathExtension("lrc")
        let hasLyrics = (tags?.lyrics?.isEmpty == false) || FileManager.default.fileExists(atPath: lrc.path)
        return TrackRecord(folderID: folder.id, path: file.path, relativePath: relativePath(file.path, root: folder.path), fileName: file.fileName,
                           fileID: Int64(bitPattern: file.fileID ?? 0), sizeBytes: file.sizeBytes, dateModified: file.dateModified,
                           tags: tags, audio: audio, hasLyrics: hasLyrics, metaVersion: version)
    }

    /// Eine einzelne Datei neu einlesen (z. B. nach dem Schreiben der Tags).
    func refreshTrack(uid: Int64) {
        guard let track = try? store.track(uid: uid), let folder = model?.folders.first(where: { $0.id == track.folderID }) else { return }
        var st = stat()
        let inode: UInt64? = lstat(track.path, &st) == 0 ? UInt64(st.st_ino) : nil
        let attrs = try? FileManager.default.attributesOfItem(atPath: track.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? track.sizeBytes
        let mtime = Int64((attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
        let file = ScannedFile(folderID: folder.id, path: track.path, sizeBytes: size, dateModified: mtime, fileID: inode)
        let record = Self.makeRecord(file, folder: folder, version: Self.tagReaderVersion)
        try? store.updateTrack(uid: uid, record)
    }

    // MARK: - Ordner beobachten

    private func startWatching() {
        let paths = ((try? store.folders()) ?? []).filter(\.enabled).map(\.path)
        watcher = paths.isEmpty ? nil : FolderWatcher(paths: paths) { [weak self] in
            Task { @MainActor in self?.rescan(reason: "Änderung im Ordner") }
        }
    }
}

/// Beobachtet Ordner rekursiv (FSEvents) und meldet Änderungen gebündelt (nach 2 s Ruhe).
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void
    private var pending: DispatchWorkItem?

    init(paths: [String], onChange: @escaping () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.changed()
        }
        stream = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, paths as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }

    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
