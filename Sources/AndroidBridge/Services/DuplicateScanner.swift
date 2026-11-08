import Foundation
import SwiftUI
import AppKit
import ABCore

/// Welcher Bereich untersucht wird.
struct DuplicateScope: Identifiable, Hashable {
    var id: String { "\(storageID)/" + path.joined(separator: "/") }
    let storageID: UInt32
    let storageName: String
    let path: [String]

    var title: String { path.isEmpty ? "Gesamter Speicher" : path.joined(separator: " › ") }
    var subtitle: String { storageName }
    var symbolName: String {
        switch path.last?.lowercased() {
        case nil: return "internaldrive"
        case "dcim": return "camera"
        case "pictures": return "photo"
        case "movies": return "film"
        case "download": return "arrow.down.circle"
        case "documents": return "doc"
        default: return "folder"
        }
    }
}

/// Liest Inhalte über MTP (Teilstücke, wo das Gerät sie kann).
private final class MTPContentReader: DuplicateContentReader, @unchecked Sendable {
    let backend: DeviceBackend
    let supportsRanges: Bool

    init(backend: DeviceBackend) {
        self.backend = backend
        self.supportsRanges = backend.supportsPartialDownload
    }

    func read(_ file: DuplicateFile, offset: UInt64, length: UInt32) async throws -> Data {
        let box = ChunkBuffer()
        _ = try await backend.downloadSegment(handle: file.entry.handle, offset: offset, length: length) { box.append($0) }
        return box.data
    }

    func stream(_ file: DuplicateFile, chunk: @escaping @Sendable (Data) -> Void) async throws {
        if supportsRanges && file.entry.size > 16 * 1024 * 1024 {
            var offset: UInt64 = 0
            while offset < file.entry.size {
                try Task.checkCancellation()
                let n = try await backend.downloadSegment(handle: file.entry.handle, offset: offset, length: 16 * 1024 * 1024) { chunk($0) }
                if n == 0 { break }
                offset += n
            }
        } else {
            try await backend.download(handle: file.entry.handle, sink: { chunk($0) }, progress: { _ in !Task.isCancelled })
        }
    }

    /// Antworten des Telefons („Zugriff verweigert“ …) betreffen nur diese Datei; Trennung/Abbruch die ganze Suche.
    func isFatal(_ error: Error) -> Bool {
        guard let e = error as? MTPError else { return true }
        return e.responseCode == nil
    }
}

/// Reicht Fortschritt aus der Gerätewarteschlange an die Oberfläche weiter (nur auf dem Hauptthread gelesen).
private final class ProgressRelay: @unchecked Sendable {
    weak var scanner: DuplicateScanner?
}

private final class ChunkBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()
    var data: Data { lock.lock(); defer { lock.unlock() }; return storage }
    func append(_ d: Data) { lock.lock(); storage.append(d); lock.unlock() }
}

/// Duplikatsuche auf dem Telefon: Erfassung, Inhaltsvergleich, Ergebnisse, Auswahl. Gelöscht wird nur über den
/// `DeletionService` nach ausdrücklicher Bestätigung.
@MainActor
final class DuplicateScanner: ObservableObject {
    enum State: Equatable {
        case idle, scanning, finished, cancelled
        case failed(String)
    }

    @Published private(set) var device: DeviceConnection?
    @Published private(set) var state: State = .idle
    @Published private(set) var progress = DuplicateScanProgress()
    @Published private(set) var identical: [DuplicateGroup] = []
    @Published private(set) var similar: [DuplicateGroup] = []
    @Published var marked = Set<String>()
    @Published var skipped = Set<String>()
    @Published var selectedScopes = Set<DuplicateScope>()
    @Published var findSimilarImages = false
    @Published private(set) var lastFailures: [(name: String, reason: String)] = []
    @Published private(set) var lastFreed: UInt64?
    @Published private(set) var scannedAt: Date?
    @Published var selectionHint: String?

    private var task: Task<Void, Never>?
    private let skippedFolders: Set<String> = ["android/data", "android/obb"]

    func attach(_ device: DeviceConnection) {
        if self.device?.id == device.id {
            if selectedScopes.isEmpty { selectedScopes = defaultScopes(device) }
            return
        }
        cancel()
        self.device = device
        identical = []; similar = []; marked = []; skipped = []
        state = .idle
        selectedScopes = defaultScopes(device)
    }

    private func defaultScopes(_ device: DeviceConnection) -> Set<DuplicateScope> {
        Set(device.storages.map { DuplicateScope(storageID: $0.id, storageName: $0.shortName, path: []) })
    }

    func detach() {
        cancel()
        device = nil
        state = .idle
    }

    /// Angebotene Bereiche: je Speicher „gesamt“ und die üblichen Ordner.
    func availableScopes(currentFolder: DeviceLocation?) -> [DuplicateScope] {
        guard let device else { return [] }
        var list: [DuplicateScope] = []
        for s in device.storages {
            list.append(DuplicateScope(storageID: s.id, storageName: s.shortName, path: []))
        }
        if let primary = device.storages.first(where: { !$0.isRemovable }) ?? device.storages.first {
            for folder in ["DCIM", "Pictures", "Movies", "Download", "Documents"] {
                list.append(DuplicateScope(storageID: primary.id, storageName: primary.shortName, path: [folder]))
            }
        }
        if let loc = currentFolder, !loc.path.isEmpty, loc.deviceSerial == device.serial {
            let scope = DuplicateScope(storageID: loc.storageID, storageName: loc.storageName, path: loc.path)
            if !list.contains(scope) { list.append(scope) }
        }
        return list
    }

    var allGroups: [DuplicateGroup] { identical + similar }

    // MARK: Suche

    func start() {
        guard let device, let backend = device.backend, device.state == .connected, !selectedScopes.isEmpty else { return }
        cancel()
        state = .scanning
        identical = []; similar = []; marked = []; skipped = []; lastFailures = []; lastFreed = nil
        progress = DuplicateScanProgress()
        // überlappende Bereiche zusammenfassen (z. B. „gesamt“ + „DCIM“)
        let scopes = selectedScopes.filter { scope in
            !selectedScopes.contains { other in other != scope && other.storageID == scope.storageID && scope.path.starts(with: other.path) && other.path.count < scope.path.count }
        }.sorted { $0.id < $1.id }
        let wantSimilar = findSimilarImages
        let flag = CancelFlag()
        let relay = ProgressRelay()
        relay.scanner = self
        task = Task { [weak self] in
            do {
                let files = try await Self.collect(scopes: scopes, backend: backend, skipped: self?.skippedFolders ?? [], flag: flag) { p in
                    self?.progress = p
                }
                try Task.checkCancellation()
                let reader = MTPContentReader(backend: backend)
                let groups = try await ExactDuplicateFinder().find(in: files, reader: reader, progress: { p in
                    Task { @MainActor in relay.scanner?.mergeProgress(p) }
                }, isCancelled: { flag.isCancelled || Task.isCancelled })
                guard let self else { return }
                self.identical = groups
                if wantSimilar {
                    self.similar = try await self.findSimilar(in: files, excluding: groups, device: device, flag: flag)
                }
                self.progress.phase = .done
                self.progress.groupsFound = self.identical.count + self.similar.count
                // Vorschläge werden nur angezeigt – markiert wird erst auf Wunsch (nie automatisch).
                self.marked = []
                self.state = .finished
                self.scannedAt = Date()
                Diagnostics.shared.log(.app, "Duplikatsuche: \(files.count) Dateien, \(self.identical.count) identische Gruppen, \(self.similar.count) ähnliche Gruppen, \(ByteFormat.string(self.progress.bytesRead)) gelesen")
            } catch is CancellationError {
                self?.state = .cancelled
            } catch let e as MTPError where e == .cancelled {
                self?.state = .cancelled
            } catch {
                self?.state = .failed(ABIssue.from(error).title)
                device.reportFailure(error)
            }
        }
        taskFlag = flag
    }

    private var taskFlag: CancelFlag?

    fileprivate func mergeProgress(_ p: DuplicateScanProgress) {
        guard state == .scanning else { return }
        var merged = p
        merged.foldersScanned = progress.foldersScanned
        progress = merged
    }

    /// Nur für die Bildschirmfotos im Build (Vorschaugerät, kein Telefon am Build-Rechner).
    func showPreviewResults(identical: [DuplicateGroup], similar: [DuplicateGroup], marked: Set<String>) {
        cancel()
        self.identical = identical
        self.similar = similar
        self.marked = marked
        var p = DuplicateScanProgress()
        p.phase = .done
        p.groupsFound = identical.count + similar.count
        progress = p
        scannedAt = Date()
        state = .finished
    }

    /// Zurück zur Bereichsauswahl (Ergebnisse verwerfen; auf dem Telefon ändert sich nichts).
    func reset() {
        cancel()
        state = .idle
        identical = []; similar = []; marked = []; skipped = []; selectionHint = nil
    }

    func cancel() {
        taskFlag?.cancel()
        task?.cancel()
        task = nil
        if state == .scanning { state = .cancelled }
    }

    /// Stufe 1–2: Verzeichnisse durchlaufen, Name/Größe/Typ erfassen.
    private static func collect(scopes: [DuplicateScope], backend: DeviceBackend, skipped: Set<String>, flag: CancelFlag,
                                progress: @escaping (DuplicateScanProgress) -> Void) async throws -> [DuplicateFile] {
        var p = DuplicateScanProgress()
        p.phase = .collecting
        var files: [DuplicateFile] = []
        var seen = Set<String>()
        for scope in scopes {
            // Startordner auflösen (über Namen)
            var parent = MTPHandle.root
            var resolved = true
            for name in scope.path {
                let children = try await backend.list(storage: scope.storageID, parent: parent)
                guard let folder = children.first(where: { $0.isFolder && $0.name.lowercased() == name.lowercased() }) else { resolved = false; break }
                parent = folder.handle
            }
            guard resolved else { continue }
            var queue: [(UInt32, [String])] = [(parent, scope.path)]
            while !queue.isEmpty {
                if flag.isCancelled || Task.isCancelled { throw CancellationError() }
                let (handle, path) = queue.removeFirst()
                p.currentLocation = ([scope.storageName] + path).joined(separator: " › ")
                let children = try await backend.list(storage: scope.storageID, parent: handle)
                p.foldersScanned += 1
                for c in children {
                    if c.isFolder {
                        let childPath = path + [c.name]
                        let key = childPath.joined(separator: "/").lowercased()
                        if !skipped.contains(key) && !c.name.hasPrefix(".") && childPath.count < 14 {
                            queue.append((c.handle, childPath))
                        }
                    } else if c.size > 0, seen.insert(c.id).inserted {
                        files.append(DuplicateFile(entry: c, path: path, storageName: scope.storageName))
                    }
                }
                p.filesFound = files.count
                if p.foldersScanned % 5 == 0 { progress(p) }
            }
        }
        progress(p)
        return files
    }

    /// Ähnliche Bilder (Wahrnehmungs-Hash der Vorschaubilder) – getrennt von identischen Dateien.
    private func findSimilar(in files: [DuplicateFile], excluding exact: [DuplicateGroup], device: DeviceConnection, flag: CancelFlag) async throws -> [DuplicateGroup] {
        let photos = files.filter { $0.entry.kind == .photo }
        progress.phase = .similar
        progress.candidates = photos.count
        progress.examined = 0
        var hashes: [(id: String, hash: UInt64)] = []
        let byID = Dictionary(photos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for photo in photos {
            if flag.isCancelled || Task.isCancelled { throw CancellationError() }
            if let image = await ThumbnailService.shared.thumbnail(for: photo.entry, device: device),
               let gray = Self.gray9x8(image), let h = PerceptualHash.dHash(gray9x8: gray) {
                hashes.append((photo.id, h))
            }
            progress.examined += 1
            progress.currentLocation = photo.displayPath
        }
        let exactSets = exact.map { Set($0.files.map(\.id)) }
        return PerceptualHash.cluster(hashes, threshold: 5).compactMap { ids in
            // Gruppen, die vollständig aus einer identischen Gruppe bestehen, sind schon erfasst.
            if exactSets.contains(where: { Set(ids).isSubset(of: $0) }) { return nil }
            let members = ids.compactMap { byID[$0] }
            guard members.count > 1 else { return nil }
            return DuplicateGroup(id: "sim-" + ids.sorted().joined(separator: "+"), kind: .similar, files: members, checksum: nil)
        }
    }

    nonisolated static func gray9x8(_ image: NSImage) -> [UInt8]? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixels = [UInt8](repeating: 0, count: 72)
        let ok: Bool = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: 9, height: 8, bitsPerComponent: 8, bytesPerRow: 9,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 9, height: 8))
            return true
        }
        return ok ? pixels : nil
    }

    // MARK: Auswahl

    func isMarked(_ file: DuplicateFile) -> Bool { marked.contains(file.id) }

    func toggle(_ file: DuplicateFile, in group: DuplicateGroup) {
        if marked.contains(file.id) {
            marked.remove(file.id)
        } else {
            var next = marked
            next.insert(file.id)
            // Nie alle Dateien einer Gruppe markieren – auch nicht über andere Gruppen hinweg.
            guard keepsAFileEverywhere(next) else {
                selectionHint = "Von jeder Gruppe bleibt mindestens eine Datei erhalten."
                return
            }
            marked = next
        }
        selectionHint = nil
        skipped.remove(group.id)
    }

    /// Nur diese Datei behalten, alle anderen der Gruppe markieren.
    func keepOnly(_ file: DuplicateFile, in group: DuplicateGroup) {
        var next = marked
        for f in group.files { if f.id == file.id { next.remove(f.id) } else { next.insert(f.id) } }
        marked = normalized(next, protecting: [file.id])
        skipped.remove(group.id)
    }

    func applySuggestion(_ group: DuplicateGroup) {
        var next = marked
        for f in group.files { next.remove(f.id) }
        next.formUnion(DuplicateSelection.suggested(for: group))
        marked = normalized(next, protecting: [group.suggestedKeep])
        skipped.remove(group.id)
    }

    func applyAllSuggestions(includeSimilar: Bool) {
        var next = Set<String>()
        var keep = Set<String>()
        for g in identical where !skipped.contains(g.id) {
            next.formUnion(DuplicateSelection.suggested(for: g)); keep.insert(g.suggestedKeep)
        }
        if includeSimilar {
            for g in similar where !skipped.contains(g.id) {
                next.formUnion(DuplicateSelection.suggested(for: g)); keep.insert(g.suggestedKeep)
            }
        }
        marked = normalized(next, protecting: keep)
    }

    func skip(_ group: DuplicateGroup) {
        for f in group.files { marked.remove(f.id) }
        skipped.insert(group.id)
    }

    /// Bleibt mit dieser Markierung in jeder Gruppe mindestens eine Datei?
    func keepsAFileEverywhere(_ set: Set<String>) -> Bool {
        allGroups.allSatisfy { DuplicateSelection.keepsAtLeastOne(set, in: $0) }
    }

    var everyGroupKeepsAFile: Bool { keepsAFileEverywhere(marked) }

    /// Hebt Markierungen auf, bis jede Gruppe mindestens eine Datei behält (bevorzugt die vorgeschlagene).
    private func normalized(_ set: Set<String>, protecting: Set<String>) -> Set<String> {
        var out = set.subtracting(protecting)
        for g in allGroups where !DuplicateSelection.keepsAtLeastOne(out, in: g) {
            out.remove(g.suggestedKeep)
        }
        return out
    }

    func clearSelection() { marked = [] }

    /// Markierte Dateien (gruppenübergreifend eindeutig).
    var markedFiles: [DuplicateFile] {
        var seen = Set<String>()
        return allGroups.flatMap(\.files).filter { marked.contains($0.id) && seen.insert($0.id).inserted }
    }

    var markedBytes: UInt64 { markedFiles.reduce(0) { $0 + $1.entry.size } }

    var reclaimableTotal: UInt64 { identical.reduce(0) { $0 + $1.reclaimableBytes } }
    var redundantTotal: Int { identical.reduce(0) { $0 + $1.redundantCount } }

    /// Nach dem Löschen: gelöschte Dateien entfernen, Gruppen mit weniger als zwei Dateien auflösen.
    func apply(_ outcome: DeletionOutcome) {
        let gone = outcome.deletedIDs
        func prune(_ groups: [DuplicateGroup]) -> [DuplicateGroup] {
            groups.compactMap { g in
                let rest = g.files.filter { !gone.contains($0.id) }
                guard rest.count > 1 else { return nil }
                return DuplicateGroup(id: g.id, kind: g.kind, files: rest, checksum: g.checksum)
            }
        }
        identical = prune(identical)
        similar = prune(similar)
        marked.subtract(gone)
        lastFailures = outcome.failed.map { (name: $0.entry.name, reason: $0.reason) }
        lastFreed = outcome.freedBytes ?? outcome.deleted.reduce(0) { $0 + $1.size }
    }
}
