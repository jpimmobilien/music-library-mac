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

    @Published var selection: SidebarItem? = .overview
    @Published var selectedDeviceID: UInt64?
    @Published var showDiagnostics = false
    @Published var viewerItem: MediaViewerItem?
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
        files.layout = settings.defaultLayout
        if automated { NotificationService.disabled = true }

        // Änderungen der Unterobjekte weiterreichen (Seitenleiste, Abzeichen)
        devices.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        transfers.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)

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
        if case .device(let id) = selection, id == device.id { selection = .overview }
        if let next = devices.device(id: selectedDeviceID) {
            files.device.attach(next)
            gallery.attach(next)
        }
    }
}
