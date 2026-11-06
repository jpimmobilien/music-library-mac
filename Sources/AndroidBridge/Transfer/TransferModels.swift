import Foundation
import ABCore

enum TransferDirection: String {
    case toMac, toDevice

    var symbolName: String { self == .toMac ? "arrow.down.to.line" : "arrow.up.to.line" }
    var verb: String { self == .toMac ? "Auf den Mac" : "Auf das Telefon" }
}

/// Was übertragen werden soll (vom Benutzer ausgewählt).
enum TransferRequest {
    /// Objekte vom Gerät (Dateien und Ordner) in einen Mac-Ordner.
    case download(entries: [DeviceEntry], sourcePath: [String], destination: URL)
    /// Dateien/Ordner vom Mac in einen Ordner auf dem Gerät.
    case upload(urls: [URL], storageID: UInt32, parent: UInt32, destinationPath: [String])
}

/// Eine einzelne Datei innerhalb einer Übertragung.
struct TransferItem: Identifiable {
    let id = UUID()
    var name: String
    /// Unterordner relativ zum Ziel (ohne Dateinamen).
    var folderPath: [String]
    var size: UInt64
    var status: TransferStatus = .waiting
    var deviceEntry: DeviceEntry?
    var localURL: URL?
    var resultName: String?
    var modified: Date?
}

/// Threadsicherer Fortschrittszähler (wird auf der Gerätewarteschlange erhöht, auf dem Hauptthread gelesen).
final class ProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _completed: UInt64 = 0
    private var _current: UInt64 = 0

    var total: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return _completed + _current
    }

    func setCurrent(_ v: UInt64) { lock.lock(); _current = v; lock.unlock() }
    func addCurrent(_ v: UInt64) { lock.lock(); _current += v; lock.unlock() }
    var current: UInt64 { lock.lock(); defer { lock.unlock() }; return _current }

    /// Aktuelle Datei abschließen (zählt `bytes` als erledigt, setzt den laufenden Zähler zurück).
    func finishCurrent(countingAs bytes: UInt64) {
        lock.lock(); _completed += bytes; _current = 0; lock.unlock()
    }

    func reset() { lock.lock(); _completed = 0; _current = 0; lock.unlock() }
}

/// Eine Übertragung (eine Benutzeraktion, eine oder viele Dateien).
@MainActor
final class TransferJob: ObservableObject, Identifiable {
    let id = UUID()
    let direction: TransferDirection
    let deviceID: UInt64
    let deviceName: String
    let request: TransferRequest
    let title: String
    let sourceDescription: String
    let destinationDescription: String
    let createdAt = Date()

    @Published var status: TransferStatus = .waiting
    @Published var items: [TransferItem] = []
    @Published var totalBytes: UInt64 = 0
    @Published var transferredBytes: UInt64 = 0
    @Published var currentName: String = ""
    @Published var currentIndex: Int = 0
    @Published var bytesPerSecond: Double = 0
    @Published var remainingSeconds: Double?
    @Published var issue: ABIssue?
    @Published var isPauseRequested = false
    @Published var planned = false

    var conflictDecision: ConflictResolution?
    var cancelRequested = false
    var startedAt: Date?
    var finishedAt: Date?
    let counter = ProgressCounter()
    var estimator = TransferRateEstimator()

    init(direction: TransferDirection, deviceID: UInt64, deviceName: String, request: TransferRequest,
         title: String, source: String, destination: String) {
        self.direction = direction
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.request = request
        self.title = title
        self.sourceDescription = source
        self.destinationDescription = destination
    }

    var fraction: Double {
        guard totalBytes > 0 else { return status == .completed ? 1 : 0 }
        return min(1, Double(transferredBytes) / Double(totalBytes))
    }

    var completedCount: Int { items.filter { $0.status == .completed }.count }
    var failedCount: Int { items.filter { if case .failed = $0.status { return true } else { return false } }.count }
    var skippedCount: Int { items.filter { $0.status == .skipped }.count }

    var summary: String {
        let n = items.count
        if !planned { return "Wird vorbereitet …" }
        var parts = ["\(completedCount) von \(n) \(n == 1 ? "Datei" : "Dateien")"]
        if skippedCount > 0 { parts.append("\(skippedCount) übersprungen") }
        if failedCount > 0 { parts.append("\(failedCount) fehlgeschlagen") }
        return parts.joined(separator: " · ")
    }
}

/// Rückfrage bei Namenskonflikten.
struct ConflictPrompt: Identifiable {
    let id = UUID()
    let fileName: String
    let destination: String
    let existingSize: UInt64?
    let newSize: UInt64
    let existingDate: Date?
    let newDate: Date?
    let remainingCount: Int
    let resolve: (ConflictResolution, Bool) -> Void
}
