import Foundation
import SwiftUI
import AppKit
import Combine
import ABCore

enum SidebarItem: Hashable {
    case overview
    case device(UInt64)
    case files
    case media
    case transfers
    case favorites
    case recents
    case duplicates
    case settings
}

/// Startmodus (normale App, Bildschirmfotos im Build, Selbsttest).
enum LaunchMode {
    case normal
    case snapshot(URL)
    case selfTest(URL)

    static let current: LaunchMode = {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count { return .snapshot(URL(fileURLWithPath: args[i + 1])) }
        if let i = args.firstIndex(of: "--selftest"), i + 1 < args.count { return .selfTest(URL(fileURLWithPath: args[i + 1])) }
        return .normal
    }()

    var isAutomated: Bool {
        if case .normal = self { return false }
        return true
    }
}

/// Wurzelzustand der App.
@MainActor
final class AppModel: ObservableObject {
    let settings: SettingsStore
    let devices: DeviceManager
    let transfers: TransferEngine
    let favorites: FavoritesStore
    let recents: RecentsStore
    let history: HistoryStore
    let files: FileManagerModel
    let gallery: GalleryModel
    let deletion = DeletionService()
    let duplicates = DuplicateScanner()

    @Published var selection: SidebarItem? = .overview
    @Published var selectedDeviceID: UInt64?
    @Published var showDiagnostics = false
    @Published var viewerItem: MediaViewerItem?
    /// Löschwunsch, der auf ausdrückliche Bestätigung wartet.
    @Published var pendingDeletion: DeletionRequest?
    /// Ergebnis mit Fehlern (wird als Bericht gezeigt).
    @Published var deletionReport: DeletionOutcomeBox?
    @Published var toast: ToastMessage?
    /// Informationsfenster zu einer Telefondatei.
    @Published var infoEntry: EntryInfoBox?
    private var toastTask: Task<Void, Never>?
    let launchMode: LaunchMode

    private var cancellables: Set<AnyCancellable> = []

    init(launchMode: LaunchMode = LaunchMode.current) {
        self.launchMode = launchMode
        let automated = launchMode.isAutomated
        let settings = SettingsStore(defaults: automated ? (UserDefaults(suiteName: "AndroidBridge.Automated") ?? .standard) : .standard)
        self.settings = settings
        let devices = DeviceManager(settings: settings)
        self.devices = devices
        let history = HistoryStore(persist: !automated)
        self.history = history
        self.favorites = FavoritesStore(persist: !automated)
        let recents = RecentsStore(persist: !automated)
        self.recents = recents
        let transfers = TransferEngine(devices: devices, settings: settings, history: history)
        self.transfers = transfers
        self.files = FileManagerModel(settings: settings, transfers: transfers, recents: recents)
        self.gallery = GalleryModel(settings: settings)
        recents.isEnabled = { [weak settings] in settings?.recentFilesEnabled ?? false }
        history.isEnabled = { [weak settings] in settings?.keepHistory ?? false }
        files.layout = settings.defaultLayout == .gallery ? .dual : settings.defaultLayout
        if automated { NotificationService.disabled = true }

        // Änderungen der Unterobjekte weiterreichen (Seitenleiste, Abzeichen)
        devices.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        transfers.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        deletion.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)

        devices.onDeviceReady = { [weak self] device in self?.deviceBecameReady(device) }
        devices.onDeviceRemoved = { [weak self] device in self?.deviceRemoved(device) }
    }

    func start() {
        AppPaths.clearPreviewCache()
        if case .normal = launchMode { devices.start() }
        if case .selfTest = launchMode { devices.start() }
    }

    func shutdown() {
        devices.stop()
        AppPaths.clearPreviewCache()
    }

    /// Ausgewähltes Gerät (sonst das erste verbundene).
    var selectedDevice: DeviceConnection? {
        if let d = devices.device(id: selectedDeviceID), d.state != .disconnected { return d }
        return devices.devices.first { $0.state == .connected } ?? devices.devices.first { $0.state != .disconnected }
    }

    func select(device: DeviceConnection) {
        selectedDeviceID = device.id
        files.device.attach(device)
        gallery.attach(device)
        duplicates.attach(device)
    }

    func openFiles(device: DeviceConnection, storageID: UInt32? = nil) {
        select(device: device)
        if let storageID { files.device.selectStorage(storageID) }
        selection = .files
    }

    func openLocation(_ location: DeviceLocation) {
        guard let device = devices.devices.first(where: { $0.serial == location.deviceSerial && $0.state == .connected }) else { return }
        select(device: device)
        selection = .files
        Task { await files.device.navigate(storageID: location.storageID, path: location.path) }
    }

    private func deviceBecameReady(_ device: DeviceConnection) {
        if selectedDeviceID == nil || devices.device(id: selectedDeviceID)?.state != .connected {
            select(device: device)
        }
        if files.device.device == nil || files.device.device?.id == device.id || files.device.device?.state != .connected {
            files.device.attach(device)
        }
        if gallery.device == nil || gallery.device?.state != .connected { gallery.attach(device) }
        if duplicates.device == nil || duplicates.device?.state != .connected { duplicates.attach(device) }
        if settings.bringToFrontOnConnect && !launchMode.isAutomated {
            NSApp.activate(ignoringOtherApps: true)
            if NSApp.windows.filter({ $0.isVisible && $0.canBecomeMain }).isEmpty {
                for w in NSApp.windows where w.canBecomeMain { w.makeKeyAndOrderFront(nil) }
            }
        }
    }

    private func deviceRemoved(_ device: DeviceConnection) {
        transfers.cancelAll(for: device.id)
        if selectedDeviceID == device.id {
            selectedDeviceID = devices.devices.first { $0.id != device.id && $0.state == .connected }?.id
        }
        if files.device.device?.id == device.id { files.device.detach() }
        if gallery.device?.id == device.id { gallery.detach() }
        if duplicates.device?.id == device.id { duplicates.detach() }
        if pendingDeletion?.deviceID == device.id { pendingDeletion = nil }
        if case .device(let id) = selection, id == device.id { selection = .overview }
        if let next = devices.device(id: selectedDeviceID) {
            files.device.attach(next)
            gallery.attach(next)
            duplicates.attach(next)
        }
    }

    // MARK: - Löschen auf dem Telefon (nur nach ausdrücklicher Bestätigung)

    /// Öffnet die Bestätigung. Gelöscht wird erst in `confirmDeletion`.
    func requestDeletion(_ entries: [DeviceEntry], on device: DeviceConnection, locations: [String],
                         summaryRows: [(label: String, value: String)] = [], origin: String = "main",
                         completion: ((DeletionOutcome) -> Void)? = nil) {
        guard !entries.isEmpty, device.state == .connected, deletion.progress == nil else { return }
        var unique: [DeviceEntry] = []
        var seen = Set<String>()
        for e in entries where seen.insert(e.id).inserted { unique.append(e) }
        let locs = Array(NSOrderedSet(array: locations).compactMap { $0 as? String })
        pendingDeletion = DeletionRequest(deviceID: device.id, deviceName: device.displayName, entries: unique,
                                          locations: locs, origin: origin, summaryRows: summaryRows, completion: completion)
    }

    /// ⌘⌫ bzw. „Löschen …“ – je nach geöffneter Seite.
    func requestDeleteForCurrentPage() {
        switch selection ?? .overview {
        case .media: deleteGallerySelection()
        case .duplicates: deleteMarkedDuplicates()
        case .files:
            if files.activePane == .device { deleteDeviceSelection(in: files) } else { files.requestDelete() }
        default: break
        }
    }

    /// Auswahl der Telefon-Spalte eines Dateimanagers (Hauptfenster oder Gerätefenster).
    func deleteDeviceSelection(in fm: FileManagerModel, entries: [DeviceEntry]? = nil) {
        guard let device = fm.device.device else { return }
        let list = entries ?? fm.device.selectedEntries
        let location = fm.device.location?.displayPath ?? device.displayName
        requestDeletion(list, on: device, locations: [location], origin: fm.windowOrigin) { [weak fm, weak self] _ in
            guard let fm, fm !== self?.files else { return }
            fm.device.invalidateCache()
            fm.device.reload(force: true)
        }
    }

    func deleteGallerySelection(_ items: [MediaItem]? = nil) {
        guard let device = gallery.device else { return }
        let list = items ?? gallery.selectedItems
        let locations = list.map { device.location(storageID: $0.entry.storageID, path: $0.path).displayPath }
        requestDeletion(list.map(\.entry), on: device, locations: locations)
    }

    func deleteMarkedDuplicates() {
        guard let device = duplicates.device else { return }
        let marked = duplicates.markedFiles
        guard !marked.isEmpty else { return }
        guard duplicates.everyGroupKeepsAFile else {
            showToast(ToastMessage(symbol: "exclamationmark.triangle.fill", tint: Palette.warning, title: "Auswahl nicht möglich",
                                   detail: "Von jeder Gruppe muss mindestens eine Datei erhalten bleiben."))
            return
        }
        let affectedGroups = duplicates.allGroups.filter { g in g.files.contains { duplicates.marked.contains($0.id) } }
        let remaining = Set(affectedGroups.flatMap(\.files).map(\.id)).subtracting(duplicates.marked).count
        var rows: [(label: String, value: String)] = [
            (label: "Gruppen", value: "\(affectedGroups.count)"),
            (label: "Verbleiben", value: remaining == 1 ? "1 Datei" : "\(remaining) Dateien – aus jeder Gruppe mindestens eine"),
            (label: "Wird frei", value: "ca. \(ByteFormat.string(duplicates.markedBytes))"),
        ]
        if affectedGroups.contains(where: { $0.kind == .similar }) {
            rows.append((label: "Hinweis", value: "Enthält ähnliche, nicht identische Bilder"))
        }
        requestDeletion(marked.map(\.entry), on: device, locations: marked.map { ([$0.storageName] + $0.path).joined(separator: " › ") },
                        summaryRows: rows) { [weak self] outcome in
            self?.duplicates.apply(outcome)
        }
    }

    /// Wird ausschließlich von der Bestätigungsschaltfläche aufgerufen.
    func confirmDeletion(_ request: DeletionRequest) {
        pendingDeletion = nil
        guard let device = devices.device(id: request.deviceID), device.state == .connected else {
            showToast(ToastMessage(symbol: "cable.connector.slash", tint: Palette.warning, title: "Telefon nicht verbunden",
                                   detail: "Es wurde nichts gelöscht."))
            return
        }
        Task {
            let outcome = await deletion.perform(request, device: device)
            afterDeletion(outcome, device: device)
            request.completion?(outcome)
            if outcome.failed.isEmpty {
                let n = outcome.deleted.count
                let freed = outcome.freedBytes.map { " · \(ByteFormat.string($0)) frei" } ?? ""
                showToast(ToastMessage(symbol: "checkmark.circle.fill", tint: Palette.success,
                                       title: n == 1 ? "1 Objekt gelöscht" : "\(n) Objekte gelöscht",
                                       detail: "Endgültig vom Telefon entfernt" + freed))
            } else {
                deletionReport = DeletionOutcomeBox(outcome: outcome, origin: request.origin)
            }
        }
    }

    private func afterDeletion(_ outcome: DeletionOutcome, device: DeviceConnection) {
        let gone = outcome.deletedIDs
        if files.device.device?.id == device.id {
            files.device.selection.subtract(gone)
            files.device.invalidateCache()
            files.device.reload(force: true)
        }
        if gallery.device?.id == device.id { gallery.remove(ids: gone) }
    }

    func showToast(_ toast: ToastMessage) {
        toastTask?.cancel()
        self.toast = toast
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
