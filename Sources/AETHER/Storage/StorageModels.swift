import SwiftUI
import AppKit
import AetherCore
import AetherSystem

// =============================================================================================
// Modelle der Speicherseite. Alles Teure läuft im Hintergrund; nichts startet ohne ausdrücklichen Klick
// (außer dem SMART-Protokoll, das in Millisekunden gelesen ist). Gelöscht wird nie – Dateien gehen nur nach
// Bestätigung in den Papierkorb und lassen sich sofort zurücklegen.
// =============================================================================================

/// Ordneranalyse: größte Dateien, Ordner, Kategorien, Duplikate.
@MainActor
final class StorageAnalysisModel: ObservableObject {
    static let shared = StorageAnalysisModel()

    enum Phase: Equatable {
        case idle
        case running(StorageScanner.Progress)
        case finished
    }

    enum ThresholdChoice: String, CaseIterable, Identifiable {
        case mb100, mb500, gb1, custom
        var id: String { rawValue }
    }

    struct TrashedItem: Equatable {
        let original: URL
        let trashed: URL?
    }

    struct Notice: Equatable {
        let text: String
        let isError: Bool
        let canUndo: Bool
    }

    /// Wartet auf Bestätigung: genau diese Dateien, mit Gesamtgröße.
    struct PendingTrash: Identifiable {
        let id = UUID()
        let files: [ScannedFile]
        let totalSize: Int64
        /// Duplikatgruppen, von denen keine Kopie außerhalb des Papierkorbs bliebe.
        let fullySelectedGroups: Int
    }

    @Published var root: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var result: StorageScanResult?
    @Published var threshold: ThresholdChoice = .mb100
    @Published var customMegabytes: Int = 250
    @Published var selection: Set<String> = []
    @Published private(set) var lastTrashed: [TrashedItem] = []
    @Published var notice: Notice?
    private var scanner: StorageScanner?

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    /// Kleinste Größe, die die Analyse behält (für Duplikate und die eigene Schwelle).
    static let retainMinimum: Int64 = 1_000_000

    var thresholdBytes: Int64 {
        switch threshold {
        case .mb100: return SizeThreshold.mb100.bytes
        case .mb500: return SizeThreshold.mb500.bytes
        case .gb1: return SizeThreshold.gb1.bytes
        case .custom: return SizeThreshold.custom(megabytes: max(1, customMegabytes)).bytes
        }
    }

    func chooseFolder() {
        guard !isRunning else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = root
        panel.prompt = tr("Choose")
        panel.message = tr("Choose the folder AETHER should analyse.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        root = url
        result = nil
        selection = []
        lastTrashed = []
        notice = nil
        phase = .idle
    }

    func start() {
        guard !isRunning else { return }
        let scanner = StorageScanner()
        self.scanner = scanner
        selection = []
        lastTrashed = []
        notice = nil
        let root = self.root
        let minimum = Self.retainMinimum
        phase = .running(StorageScanner.Progress(phase: .scanning, files: 0, bytes: 0, total: 0, done: 0, currentPath: root.path))
        DispatchQueue.global(qos: .userInitiated).async {
            let result = scanner.scan(root: root, retainAtLeast: minimum, findDuplicates: true, duplicateMinimum: minimum) { progress in
                Task { @MainActor in StorageAnalysisModel.shared.update(progress, from: scanner) }
            }
            Task { @MainActor in StorageAnalysisModel.shared.finish(result, from: scanner) }
        }
    }

    func cancel() {
        scanner?.cancel()
    }

    private func update(_ progress: StorageScanner.Progress, from scanner: StorageScanner) {
        guard self.scanner === scanner, isRunning else { return }
        phase = .running(progress)
    }

    private func finish(_ result: StorageScanResult, from scanner: StorageScanner) {
        guard self.scanner === scanner else { return }
        self.scanner = nil
        self.result = result
        phase = .finished
    }

    // MARK: Papierkorb (nur nach Bestätigung)

    func prepareTrash(_ paths: Set<String>) -> PendingTrash? {
        guard let result, !paths.isEmpty else { return nil }
        var byPath: [String: ScannedFile] = [:]
        for file in result.files { byPath[file.path] = file }
        for group in result.duplicates {
            for file in group.files { byPath[file.path] = file }
        }
        let files = paths.compactMap { byPath[$0] }.sorted { $0.size > $1.size }
        guard !files.isEmpty else { return nil }
        let full = DuplicateFinder.fullySelected(result.duplicates, selection: paths).count
        return PendingTrash(files: files, totalSize: files.reduce(0) { $0 + $1.size }, fullySelectedGroups: full)
    }

    func trash(_ pending: PendingTrash) {
        var done: [TrashedItem] = []
        var failures: [String] = []
        for file in pending.files {
            let url = URL(fileURLWithPath: file.path)
            var resulting: NSURL?
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
                done.append(TrashedItem(original: url, trashed: resulting as URL?))
            } catch {
                failures.append("\(file.name): \(error.localizedDescription)")
            }
        }
        let paths = Set(done.map(\.original.path))
        result?.remove(paths: paths)
        selection.subtract(paths)
        lastTrashed = done
        if failures.isEmpty {
            notice = Notice(text: tr("Moved %ld items to the Trash.", done.count), isError: false, canUndo: !done.isEmpty)
        } else {
            notice = Notice(text: tr("Moved %ld items to the Trash. Not possible for: %@", done.count, failures.joined(separator: "; ")),
                            isError: true, canUndo: !done.isEmpty)
        }
    }

    /// Legt die zuletzt verschobenen Dateien an ihren Ort zurück.
    func undoTrash() {
        var restored = 0
        var failures: [String] = []
        for item in lastTrashed {
            guard let trashed = item.trashed else {
                failures.append(item.original.lastPathComponent)
                continue
            }
            do {
                try FileManager.default.moveItem(at: trashed, to: item.original)
                restored += 1
            } catch {
                failures.append("\(item.original.lastPathComponent): \(error.localizedDescription)")
            }
        }
        lastTrashed = []
        if failures.isEmpty {
            notice = Notice(text: tr("Put back %ld items. Analyse again to include them in the lists.", restored), isError: false, canUndo: false)
        } else {
            notice = Notice(text: tr("Put back %ld items. Not possible for: %@ – they are still in the Trash.", restored,
                                     failures.joined(separator: "; ")), isError: true, canUndo: false)
        }
    }
}

/// SSD-Gesundheit (NVMe SMART): beim Öffnen der Seite und höchstens einmal pro Minute.
@MainActor
final class DriveHealthModel: ObservableObject {
    static let shared = DriveHealthModel()

    @Published private(set) var drives: Reading<[NVMeDrive]>?
    private var lastRead: Date?
    private var reading = false
    private var timer: Timer?

    /// Speicherseite sichtbar: sofort lesen (falls älter als 60 s), danach jede Minute.
    func pageAppeared(isVirtualMachine: Bool) {
        refresh(isVirtualMachine: isVirtualMachine)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in DriveHealthModel.shared.refresh(isVirtualMachine: isVirtualMachine, force: true) }
        }
    }

    func pageDisappeared() {
        timer?.invalidate()
        timer = nil
    }

    func refresh(isVirtualMachine: Bool, force: Bool = false) {
        guard !reading else { return }
        if !force, let lastRead, Date().timeIntervalSince(lastRead) < 60 { return }
        reading = true
        DispatchQueue.global(qos: .utility).async {
            let value = SMARTSource.read(isVirtualMachine: isVirtualMachine)
            Task { @MainActor in DriveHealthModel.shared.apply(value) }
        }
    }

    private func apply(_ value: Reading<[NVMeDrive]>) {
        drives = value
        lastRead = Date()
        reading = false
    }
}

/// Bereinigungsvorschläge: misst bekannte Orte – auf Klick, nie automatisch löschend.
@MainActor
final class CleanupModel: ObservableObject {
    static let shared = CleanupModel()

    @Published private(set) var measurements: [CleanupMeasurement] = []
    @Published private(set) var measuring = false
    @Published private(set) var measuredAt: Date?

    func measure() {
        guard !measuring else { return }
        measuring = true
        DispatchQueue.global(qos: .utility).async {
            let results = CleanupKind.allCases.map { StorageScanner.measure($0) }
            Task { @MainActor in CleanupModel.shared.apply(results) }
        }
    }

    private func apply(_ results: [CleanupMeasurement]) {
        measurements = results
        measuring = false
        measuredAt = Date()
    }
}

/// Auswerfen von Volumes (öffentliche Foundation-Funktion; Fehler werden unverändert angezeigt).
@MainActor
final class VolumeActionsModel: ObservableObject {
    static let shared = VolumeActionsModel()

    struct Message: Equatable {
        let text: String
        let isError: Bool
    }

    @Published private(set) var ejecting: Set<String> = []
    @Published var message: Message?

    func eject(_ volume: VolumeInfo) {
        guard !ejecting.contains(volume.path), !volume.isRoot else { return }
        ejecting.insert(volume.path)
        message = nil
        let path = volume.path
        let name = volume.name
        FileManager.default.unmountVolume(at: URL(fileURLWithPath: path), options: [.allPartitionsAndEjectDisk]) { error in
            let failure = error?.localizedDescription
            Task { @MainActor in VolumeActionsModel.shared.finishEject(path: path, name: name, failure: failure) }
        }
    }

    private func finishEject(path: String, name: String, failure: String?) {
        ejecting.remove(path)
        if let failure {
            message = Message(text: tr("“%@” couldn’t be ejected: %@", name, failure), isError: true)
        } else {
            message = Message(text: tr("“%@” was ejected.", name), isError: false)
        }
    }
}
