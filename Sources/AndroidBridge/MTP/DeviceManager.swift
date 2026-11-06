import Foundation
import SwiftUI
import AppKit
import Combine
import ABCore

/// Verwaltet alle angeschlossenen Android-Geräte (mehrere gleichzeitig, jedes mit eigener Sitzung).
@MainActor
final class DeviceManager: ObservableObject {
    @Published private(set) var devices: [DeviceConnection] = []
    /// Alle USB-Geräte (für die Diagnose).
    @Published private(set) var allUSBDevices: [USBDeviceRecord] = []
    @Published private(set) var monitorError: String?

    private let monitor = USBDeviceMonitor()
    private let settings: SettingsStore
    var onDeviceReady: ((DeviceConnection) -> Void)?
    var onDeviceRemoved: ((DeviceConnection) -> Void)?
    private var readyObservers: [UInt64: AnyCancellable] = [:]
    private var removalTasks: [UInt64: Task<Void, Never>] = [:]

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func start() {
        monitor.onChange = { [weak self] record in
            Task { @MainActor in self?.handle(record) }
        }
        monitor.onRemoval = { [weak self] id in
            Task { @MainActor in self?.handleRemoval(id) }
        }
        monitor.start()
        monitorError = monitor.startError
    }

    func stop() {
        for d in devices { d.disconnectGracefully() }
        monitor.stop()
    }

    func device(id: UInt64?) -> DeviceConnection? {
        guard let id else { return nil }
        return devices.first { $0.id == id }
    }

    var connectedDevices: [DeviceConnection] { devices.filter { $0.state == .connected } }

    /// Nur für Bildschirmfotos im Build.
    func installPreviewDevices(_ list: [DeviceConnection]) {
        devices = list
    }

    private func handle(_ record: USBDeviceRecord) {
        if let idx = allUSBDevices.firstIndex(where: { $0.id == record.id }) {
            allUSBDevices[idx] = record
        } else {
            allUSBDevices.append(record)
        }
        let mode = record.mode
        if let existing = devices.first(where: { $0.id == record.id }) {
            existing.update(record: record)
            return
        }
        guard mode != .unrelated else { return }
        Diagnostics.shared.log(.usb, "Android-Gerät angeschlossen: \(record.idString), \(record.interfaces.count) Schnittstellen\(record.speedDescription.map { ", \($0)" } ?? "")")
        let connection = DeviceConnection(record: record, settings: settings)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            devices.append(connection)
        }
        observeReadiness(connection)
        connection.evaluate()
    }

    private func observeReadiness(_ connection: DeviceConnection) {
        readyObservers[connection.id] = connection.$state
            .removeDuplicates()
            .sink { [weak self, weak connection] state in
                guard let self, let connection, state == .connected else { return }
                Task { @MainActor in self.onDeviceReady?(connection) }
            }
    }

    private func handleRemoval(_ id: UInt64) {
        allUSBDevices.removeAll { $0.id == id }
        guard let connection = devices.first(where: { $0.id == id }) else { return }
        Diagnostics.shared.log(.usb, "Gerät getrennt")
        connection.markDisconnected()
        onDeviceRemoved?(connection)
        // Getrenntes Gerät kurz anzeigen, dann entfernen.
        removalTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                self.devices.removeAll { $0.id == id }
            }
            self.readyObservers[id] = nil
            self.removalTasks[id] = nil
        }
    }
}
