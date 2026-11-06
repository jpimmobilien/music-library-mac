import Foundation
import SwiftUI
import ABCore

/// Verbindungszustand eines Geräts, wie ihn die Oberfläche zeigt.
enum ConnectionState: Equatable {
    case detected
    case waitingForFileTransfer
    case connecting
    case waitingForAuthorization
    case readingStorage
    case connected
    case busy
    case interrupted
    case disconnected

    var title: String {
        switch self {
        case .detected: return "Gerät erkannt"
        case .waitingForFileTransfer: return "Warte auf Dateiübertragung"
        case .connecting: return "Verbinde …"
        case .waitingForAuthorization: return "Warte auf Freigabe am Gerät"
        case .readingStorage: return "Speicher wird gelesen …"
        case .connected: return "Verbunden"
        case .busy: return "Von anderem Programm belegt"
        case .interrupted: return "Verbindung unterbrochen"
        case .disconnected: return "Gerät getrennt"
        }
    }

    var symbolName: String {
        switch self {
        case .detected: return "cable.connector"
        case .waitingForFileTransfer: return "bolt.badge.clock"
        case .connecting, .readingStorage: return "arrow.triangle.2.circlepath"
        case .waitingForAuthorization: return "lock.iphone"
        case .connected: return "checkmark.circle.fill"
        case .busy: return "hourglass"
        case .interrupted: return "exclamationmark.triangle.fill"
        case .disconnected: return "cable.connector.slash"
        }
    }

    var isWorking: Bool { self == .connecting || self == .readingStorage || self == .detected }
    var isUsable: Bool { self == .connected }
}

/// Ein Android-Gerät mit seinem Verbindungsablauf.
@MainActor
final class DeviceConnection: ObservableObject, Identifiable {
    let id: UInt64
    @Published private(set) var record: USBDeviceRecord?
    @Published private(set) var state: ConnectionState = .detected
    @Published private(set) var storages: [DeviceStorage] = []
    @Published private(set) var info: MTPDeviceInfo?
    @Published var issue: ABIssue?
    @Published private(set) var connectedAt: Date?

    private(set) var backend: DeviceBackend?
    private weak var settings: SettingsStore?
    private var connectTask: Task<Void, Never>?
    private var unlockTask: Task<Void, Never>?
    private var gracePeriodTask: Task<Void, Never>?
    private var releaseAttempted = false
    /// Nur Vorschaumodus (Bildschirmfotos im Build): feste Angaben ohne USB.
    let isPreview: Bool
    private var previewIdentity: (manufacturer: String, model: String, serial: String)?

    init(record: USBDeviceRecord, settings: SettingsStore) {
        self.id = record.id
        self.record = record
        self.settings = settings
        self.isPreview = false
    }

    /// Vorschaugerät für die Bildschirmfotos im Build (nicht in der normalen App erreichbar).
    init(preview backend: DeviceBackend, id: UInt64, manufacturer: String, model: String, serial: String,
         storages: [DeviceStorage], state: ConnectionState, settings: SettingsStore) {
        self.id = id
        self.record = nil
        self.settings = settings
        self.isPreview = true
        self.backend = backend
        self.previewIdentity = (manufacturer, model, serial)
        self.storages = storages
        self.state = state
        self.connectedAt = Date()
    }

    // MARK: - Identität

    var manufacturer: String {
        if let p = previewIdentity { return p.manufacturer }
        if let m = info?.manufacturer, !m.isEmpty { return m }
        if let r = record {
            return r.vendorName ?? USBDeviceClassifier.vendorName(r.vendorID) ?? "Android"
        }
        return "Android"
    }

    var model: String {
        if let p = previewIdentity { return p.model }
        if let m = info?.model, !m.isEmpty { return m }
        return record?.productName ?? "Android-Gerät"
    }

    var serial: String {
        if let p = previewIdentity { return p.serial }
        if let s = info?.serialNumber, !s.isEmpty { return s }
        return record?.serialNumber ?? record.map { "\($0.idString)-\($0.locationID)" } ?? ""
    }

    var displayName: String {
        if let custom = settings?.preferences(forSerial: serial).customName, !custom.isEmpty { return custom }
        let m = model
        let man = manufacturer
        if m.lowercased().hasPrefix(man.lowercased()) || man == "Android" { return m }
        return "\(man) \(m)"
    }

    var symbolName: String { "smartphone" }

    var totalCapacity: UInt64 { storages.reduce(0) { $0 + $1.capacity } }
    var totalFree: UInt64 { storages.reduce(0) { $0 + $1.free } }

    // MARK: - Ablauf

    /// Aktualisierte Registry-Daten (z. B. erschienene Schnittstellen nach dem Umschalten auf „Dateiübertragung“).
    func update(record new: USBDeviceRecord) {
        record = new
        switch state {
        case .detected, .waitingForFileTransfer, .interrupted:
            evaluate()
        default:
            break
        }
    }

    func evaluate() {
        guard let record, !isPreview else { return }
        switch record.mode {
        case .fileTransfer:
            gracePeriodTask?.cancel()
            if settings?.autoConnect ?? true || state == .interrupted { connect() } else { state = .detected }
        case .androidWithoutFileTransfer:
            // Schnittstellen erscheinen oft erst kurz nach dem Gerät – erst nach einer Schonfrist Anleitung zeigen.
            if state != .waitingForFileTransfer {
                state = .detected
                gracePeriodTask?.cancel()
                gracePeriodTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    guard let self, !Task.isCancelled else { return }
                    if case .androidWithoutFileTransfer = self.record?.mode, self.state == .detected {
                        self.state = .waitingForFileTransfer
                        self.issue = .chargingOnly
                        Diagnostics.shared.log(.usb, "Gerät \(self.record?.idString ?? "") ohne Dateiübertragung (nur Laden/ADB)")
                    }
                }
            }
        case .unrelated:
            state = .detected
        }
    }

    func connect(seize: Bool = false) {
        guard !isPreview, let record else { return }
        guard case let .fileTransfer(interfaceNumber, ptpOnly) = record.mode else {
            evaluate()
            return
        }
        connectTask?.cancel()
        unlockTask?.cancel()
        backend?.close(graceful: false)
        backend = nil
        guard let service = record.copyInterfaceService(number: interfaceNumber) else {
            state = .detected
            Diagnostics.shared.log(.usb, "Schnittstelle \(interfaceNumber) noch nicht verfügbar – warte", error: false)
            return
        }
        state = .connecting
        issue = nil
        let timeout = settings?.connectionTimeout ?? 30
        Diagnostics.shared.log(.mtp, "Verbinde mit \(record.idString), Schnittstelle \(interfaceNumber)\(ptpOnly ? " (PTP-Modus)" : "")")
        let worker = MTPWorker(name: record.idString)
        connectTask = Task { [weak self] in
            do {
                let info = try await worker.open(interfaceService: service, timeout: timeout, seize: seize)
                guard let self, !Task.isCancelled else { worker.close(graceful: true); return }
                self.info = info
                self.backend = MTPBackend(worker: worker, info: info)
                self.releaseAttempted = false
                if ptpOnly && !info.isMTP {
                    Diagnostics.shared.log(.mtp, "Gerät im PTP-Modus: nur Fotos/Videos sichtbar")
                }
                await self.loadStorages()
            } catch {
                worker.close(graceful: false)
                guard let self else { return }
                await self.handleConnectError(error)
            }
        }
    }

    private func handleConnectError(_ error: Error) async {
        let mapped = (error as? MTPError) ?? .transport("\(error)")
        Diagnostics.shared.log(.mtp, "Verbindung fehlgeschlagen: \(mapped)", error: true)
        if mapped == .busy {
            state = .busy
            issue = Self.busyIssue(programs: ConflictingPrograms.running().map(\.name))
            if settings?.releasePhotoServiceAutomatically == true && !releaseAttempted {
                releaseAttempted = true
                await releasePhotoServiceAndRetry()
            }
        } else if mapped == .accessDenied {
            state = .waitingForAuthorization
            issue = .locked
        } else {
            state = .interrupted
            issue = ABIssue.from(mapped, context: "Verbindung fehlgeschlagen")
        }
    }

    /// Gibt das Telefon frei: beendet Programme, die es beanspruchen (z. B. Android File Transfer und dessen
    /// unsichtbaren Agenten) sowie den macOS-Fotodienst, und verbindet dann mit „Übernahme“ erneut.
    func releasePhotoServiceAndRetry() async {
        state = .connecting
        let released = await ConflictingPrograms.releaseAll()
        if !released.isEmpty { Diagnostics.shared.log(.usb, "Beendet: \(released.joined(separator: ", "))") }
        connect(seize: true)
    }

    static func busyIssue(programs: [String]) -> ABIssue {
        var issue = ABIssue.from(MTPError.busy)
        if !programs.isEmpty {
            let list = programs.joined(separator: ", ")
            issue.message = "Auf diesem Mac läuft \(list) und hält das Telefon fest. Solange es läuft, kann kein anderes Programm auf das Telefon zugreifen."
            issue.recommendation = "Klicken Sie auf „Freigeben und verbinden“ – Android Bridge beendet \(list) und verbindet. Dauerhaft: Android File Transfer deinstallieren bzw. unter Systemeinstellungen → Allgemein → Anmeldeobjekte den „Android File Transfer Agent“ entfernen."
        }
        return issue
    }

    func loadStorages() async {
        guard let backend else { return }
        state = .readingStorage
        do {
            let list = try await backend.storages()
            if list.isEmpty {
                // Gesperrtes Telefon: Android gibt den Speicher erst nach dem Entsperren frei.
                state = .waitingForAuthorization
                issue = .locked
                startUnlockPolling()
                return
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                storages = list
                state = .connected
            }
            issue = nil
            connectedAt = Date()
            Diagnostics.shared.log(.mtp, "Verbunden: \(list.count) Speicher")
        } catch {
            let mapped = (error as? MTPError) ?? .transport("\(error)")
            if mapped.responseCode == PTPResponse.accessDenied.rawValue || mapped.responseCode == PTPResponse.storeNotAvailable.rawValue {
                state = .waitingForAuthorization
                issue = .locked
                startUnlockPolling()
            } else {
                state = .interrupted
                issue = ABIssue.from(error, context: "Speicher konnte nicht gelesen werden")
            }
        }
    }

    private func startUnlockPolling() {
        unlockTask?.cancel()
        unlockTask = Task { [weak self] in
            // Nur in diesem Zustand wird nachgefragt (alle 1,5 s) – sonst kein Abfragen im Takt.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self, self.state == .waitingForAuthorization, let backend = self.backend else { return }
                if let list = try? await backend.storages(), !list.isEmpty {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        self.storages = list
                        self.state = .connected
                    }
                    self.issue = nil
                    self.connectedAt = Date()
                    return
                }
            }
        }
    }

    func refreshStorages() async {
        guard let backend, state == .connected else { return }
        if let list = try? await backend.storages() { storages = list }
    }

    /// Fehler während der Nutzung (z. B. Kabel gezogen) – Verbindung als unterbrochen markieren.
    func reportFailure(_ error: Error) {
        guard let e = error as? MTPError else { return }
        if e == .disconnected || e == .timeout {
            if state == .connected { state = .interrupted; issue = ABIssue.from(e) }
        }
    }

    func reconnect() {
        releaseAttempted = false
        connect()
    }

    func markDisconnected() {
        connectTask?.cancel()
        unlockTask?.cancel()
        gracePeriodTask?.cancel()
        backend?.close(graceful: false)
        backend = nil
        withAnimation(.easeInOut(duration: 0.3)) { state = .disconnected }
        issue = nil
    }

    func disconnectGracefully() {
        connectTask?.cancel()
        unlockTask?.cancel()
        backend?.close(graceful: true)
        backend = nil
    }

    /// Ort (Speicher + Pfad) für Favoriten und „Zuletzt verwendet“.
    func location(storageID: UInt32, path: [String]) -> DeviceLocation {
        let name = storages.first { $0.id == storageID }?.displayName ?? "Speicher"
        return DeviceLocation(deviceSerial: serial, deviceName: displayName, storageID: storageID, storageName: name, path: path)
    }
}
