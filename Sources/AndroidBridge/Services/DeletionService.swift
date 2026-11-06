import Foundation
import SwiftUI
import ABCore

/// Ein Löschwunsch, der vor der Ausführung bestätigt werden muss.
struct DeletionRequest: Identifiable {
    let id = UUID()
    let deviceID: UInt64
    let deviceName: String
    let entries: [DeviceEntry]
    /// Speicherorte (für die Bestätigung), z. B. „Interner Speicher › DCIM › Camera“.
    let locations: [String]
    /// Fenster, in dem die Bestätigung erscheint („main“ oder ein Gerätefenster).
    var origin = "main"
    /// Zusätzliche Angaben für die Bestätigung (z. B. „Verbleiben: 120 Dateien“).
    var summaryRows: [(label: String, value: String)] = []
    /// Wird nach der Löschung aufgerufen (Liste aktualisieren, Duplikate neu berechnen …).
    var completion: ((DeletionOutcome) -> Void)?

    var fileCount: Int { entries.filter { !$0.isFolder }.count }
    var folderCount: Int { entries.filter(\.isFolder).count }
    var knownBytes: UInt64 { entries.filter { !$0.isFolder }.reduce(0) { $0 + $1.size } }
}

/// Ergebnis einer Löschung.
struct DeletionOutcome {
    var deleted: [DeviceEntry] = []
    var failed: [(entry: DeviceEntry, reason: String)] = []
    /// Tatsächlich freigegebener Speicher laut Gerät (falls ermittelbar).
    var freedBytes: UInt64?
    var deletedIDs: Set<String> { Set(deleted.map(\.id)) }
}

/// Führt Löschungen über MTP aus (DeleteObject; Ordner rekursiv, wo nötig) – nie ohne vorherige Bestätigung.
@MainActor
final class DeletionService: ObservableObject {
    struct Progress: Equatable {
        var done: Int
        var total: Int
        var current: String
    }

    @Published private(set) var progress: Progress?
    @Published var lastOutcome: DeletionOutcomeBox?

    func perform(_ request: DeletionRequest, device: DeviceConnection) async -> DeletionOutcome {
        var outcome = DeletionOutcome()
        guard let backend = device.backend, device.state == .connected else {
            outcome.failed = request.entries.map { (entry: $0, reason: "Telefon nicht verbunden") }
            return outcome
        }
        let freeBefore = device.storages.reduce(UInt64(0)) { $0 + $1.free }
        progress = Progress(done: 0, total: request.entries.count, current: "")
        Diagnostics.shared.log(.mtp, "Lösche \(request.entries.count) Objekte (\(request.folderCount) Ordner)")
        var disconnected = false
        for (i, entry) in request.entries.enumerated() {
            progress = Progress(done: i, total: request.entries.count, current: entry.name)
            if disconnected {
                outcome.failed.append((entry: entry, reason: "Verbindung unterbrochen"))
                continue
            }
            do {
                let result = try await backend.deleteTree(handle: entry.handle, storage: entry.storageID, isFolder: entry.isFolder)
                if result.succeeded {
                    outcome.deleted.append(entry)
                } else {
                    let code = result.failed[entry.handle] ?? result.failed.values.first ?? PTPResponse.generalError.rawValue
                    let inside = result.failed.count - (result.failed[entry.handle] == nil ? 0 : 1)
                    let reason = Self.reason(for: code, partial: entry.isFolder && result.deletedObjects > 0, blockedInside: inside)
                    outcome.failed.append((entry: entry, reason: reason))
                }
            } catch let e as MTPError where e == .disconnected || e == .timeout {
                disconnected = true
                outcome.failed.append((entry: entry, reason: ABIssue.from(e).title))
                device.reportFailure(e)
            } catch {
                outcome.failed.append((entry: entry, reason: ABIssue.from(error).title))
            }
        }
        progress = nil
        await device.refreshStorages()
        let freeAfter = device.storages.reduce(UInt64(0)) { $0 + $1.free }
        if freeAfter > freeBefore { outcome.freedBytes = freeAfter - freeBefore }
        Diagnostics.shared.log(.mtp, "Löschen beendet: \(outcome.deleted.count) gelöscht, \(outcome.failed.count) nicht gelöscht", error: !outcome.failed.isEmpty)
        lastOutcome = DeletionOutcomeBox(outcome: outcome)
        return outcome
    }

    static func reason(for code: UInt16, partial: Bool, blockedInside: Int) -> String {
        switch PTPResponse(rawValue: code) {
        case .accessDenied?, .objectWriteProtected?:
            return partial || blockedInside > 0 ? "Teilweise gelöscht – \(blockedInside) geschützte Objekte blieben erhalten" : "Android erlaubt das Löschen hier nicht (geschützt)"
        case .storeReadOnly?: return "Speicher ist schreibgeschützt"
        case .partialDeletion?: return "Nur teilweise gelöscht – einige Inhalte sind geschützt"
        case .operationNotSupported?: return "Das Telefon unterstützt das Löschen nicht"
        case .storeNotAvailable?, .invalidStorageID?: return "Speicher nicht verfügbar"
        case .deviceBusy?: return "Telefon ist beschäftigt"
        default: return "Vom Telefon abgelehnt (0x\(String(code, radix: 16)))"
        }
    }
}

/// Hülle für die Ergebnisanzeige (Identifiable).
struct DeletionOutcomeBox: Identifiable {
    let id = UUID()
    let outcome: DeletionOutcome
    var origin = "main"
}
