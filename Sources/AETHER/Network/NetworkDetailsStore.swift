import Foundation
import AppKit
import CoreLocation
import AetherCore
import AetherSystem

/// Schnittstellen, WLAN und Verbindungen – nur gemessen, solange die Netzwerkseite sichtbar ist (alle 5 s).
@MainActor
final class NetworkDetailsStore: ObservableObject {
    @Published private(set) var interfaces: [NetworkInterfaceInfo] = []
    @Published private(set) var interfacesLoaded = false
    /// `nil` = kein WLAN vorhanden (nach dem ersten Laden).
    @Published private(set) var wifi: WiFiDetails?
    @Published private(set) var wifiTimestamp: Date?
    @Published private(set) var connections: Reading<NetstatParseResult>?
    @Published private(set) var loaded = false

    private struct Batch: Sendable {
        var interfaces: [NetworkInterfaceInfo]
        var wifi: WiFiDetails?
        var connections: Reading<NetstatParseResult>
        var date: Date
    }

    /// Läuft, bis die Aufgabe abgebrochen wird (beim Verlassen der Seite).
    func run() async {
        while !Task.isCancelled {
            let result = await Task.detached(priority: .utility) { () -> Batch in
                let date = Date()
                return Batch(interfaces: InterfaceInventory.read(), wifi: WiFiSource.sample(),
                              connections: ConnectionSource.sample(at: date), date: date)
            }.value
            guard !Task.isCancelled else { return }
            interfaces = result.interfaces
            interfacesLoaded = true
            wifi = result.wifi
            wifiTimestamp = result.date
            connections = result.connections
            loaded = true
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    var primary: NetworkInterfaceInfo? { interfaces.first { $0.isPrimary && $0.isConnected } }
}

/// Ortungsfreigabe – ausschließlich, weil macOS den WLAN-Namen nur damit herausgibt. Der Standort wird nie abgefragt.
@MainActor
final class LocationAccess: NSObject, ObservableObject, CLLocationManagerDelegate {
    /// Rohwert von `CLAuthorizationStatus` (0 offen, 1 eingeschränkt, 2 abgelehnt, 3 immer, 4 bei Nutzung).
    @Published private(set) var statusRaw: Int32
    private let manager: CLLocationManager

    override init() {
        manager = CLLocationManager()
        statusRaw = manager.authorizationStatus.rawValue
        super.init()
        manager.delegate = self
    }

    var isAuthorized: Bool { statusRaw == 3 || statusRaw == 4 }
    var isDenied: Bool { statusRaw == 1 || statusRaw == 2 }
    var isUndetermined: Bool { statusRaw == 0 }

    /// Fragt einmalig nach (nur auf Klick des Nutzers).
    func request() {
        manager.requestWhenInUseAuthorization()
    }

    func openPrivacySettings() {
        for link in ["x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices",
                     "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices"] {
            if let url = URL(string: link), NSWorkspace.shared.open(url) { return }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let raw = manager.authorizationStatus.rawValue
        Task { @MainActor in self.statusRaw = raw }
    }
}
