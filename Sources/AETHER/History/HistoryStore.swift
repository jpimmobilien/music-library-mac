import Foundation
import AetherCore
import AetherSystem

/// Lokaler Verlauf (Opt-in): sammelt die Messungen jeder Minute und speichert den Minutenwert in SQLite.
/// Ausgeschaltet (Standard) wird nichts gespeichert. Im Selbsttest- und Fotomodus wird nie etwas gespeichert.
@MainActor
final class HistoryStore: ObservableObject {
    /// Aufzeichnung läuft (eingeschaltet und erlaubt).
    @Published private(set) var isRecording = false
    /// Wird mit jedem gespeicherten Minutenwert erhöht – Verlaufsansichten laden dann neu.
    @Published private(set) var revision = 0
    /// Belegter Platz der Verlaufsdateien (Bytes).
    @Published private(set) var databaseSize: Int64 = 0
    @Published private(set) var lastError: String?

    let url: URL?
    private var database: HistoryDatabase?
    private var accumulator = HistoryAccumulator()
    private var retentionDays = 7
    private var lastPrune: Date?
    /// Im Selbsttest- und Fotomodus nie lesen oder schreiben (auch keine vorhandene Datei öffnen).
    private var allowed = false

    init(url: URL? = HistoryDatabase.defaultURL()) {
        self.url = url
    }

    /// Einstellungen übernehmen. `allowed` = false im Selbsttest- und Fotomodus.
    func configure(enabled: Bool, retentionDays: Int, allowed: Bool) {
        self.retentionDays = max(1, retentionDays)
        self.allowed = allowed
        let shouldRecord = enabled && allowed && url != nil
        if shouldRecord {
            if database == nil, let url {
                do {
                    database = try HistoryDatabase(url: url)
                    lastError = nil
                } catch {
                    lastError = String(describing: error)
                }
            }
            prune()
        } else if database != nil {
            flushNow()
            database?.close()
            database = nil
            accumulator = HistoryAccumulator()
        }
        isRecording = shouldRecord && database != nil
        refreshSize()
    }

    /// Eine Messung aufnehmen (aus dem Takt der Messmaschine).
    func record(_ result: TickResult) {
        guard isRecording, let database else { return }
        let battery = result.battery
        let sample = HistorySample(
            time: result.date,
            cpuBusy: result.cpu.total.value?.busy,
            memoryUsed: result.memory?.breakdown.value?.usedFraction,
            pressure: result.memory?.pressure.value?.rawValue,
            swapUsed: result.memory?.swap.value.map { Double($0.used) },
            download: result.network.download.value,
            upload: result.network.upload.value,
            batteryPercent: battery?.isPresent == true ? battery?.percent.value.map { Double($0) } : nil,
            batteryPower: battery?.isPresent == true ? battery?.power.value : nil,
            hottest: result.thermal?.hottest?.celsius,
            thermalState: result.thermal?.state.value?.rawValue)
        if let finished = accumulator.add(sample) {
            database.insert(finished)
            revision += 1
            if revision % 10 == 0 { refreshSize() }
        }
        if let lastPrune, Date().timeIntervalSince(lastPrune) < 3_600 { return }
        prune()
    }

    private func prune() {
        guard let database else { return }
        database.prune(before: Date().addingTimeInterval(-Double(retentionDays) * 86_400))
        lastPrune = Date()
    }

    /// Angefangene Minute sofort speichern (Beenden, Ausschalten).
    func flushNow() {
        guard let database, let finished = accumulator.flush() else { return }
        database.insertNow(finished)
    }

    /// Werte des Zeitraums bis jetzt.
    func load(range: HistoryRange) async -> [HistorySample] {
        guard let database = database ?? openExisting() else { return [] }
        let end = Date()
        let start = end.addingTimeInterval(-range.seconds)
        return await withCheckedContinuation { continuation in
            database.load(from: start, to: end) { samples in continuation.resume(returning: samples) }
        }
    }

    /// Gibt es gespeicherte Werte (auch bei ausgeschalteter Aufzeichnung)?
    var hasStoredData: Bool { databaseSize > 0 }

    /// Ganzer Verlauf als CSV in die gewählte Datei.
    func exportCSV(to destination: URL) async throws {
        guard let database = database ?? openExisting() else { throw CocoaError(.fileNoSuchFile) }
        flushNow()
        let samples: [HistorySample] = await withCheckedContinuation { continuation in
            database.load(from: Date(timeIntervalSince1970: 0), to: Date()) { samples in continuation.resume(returning: samples) }
        }
        let text = HistoryCSV.make(samples)
        try await Task.detached(priority: .utility) {
            try text.write(to: destination, atomically: true, encoding: .utf8)
        }.value
    }

    /// Verlauf vollständig löschen (Dateien entfernen). Läuft die Aufzeichnung, beginnt sie mit einer leeren Datei neu.
    func deleteAll() {
        guard allowed, let url else { return }
        let wasRecording = isRecording
        database?.close()
        database = nil
        accumulator = HistoryAccumulator()
        if !HistoryDatabase.removeFiles(at: url) {
            lastError = tr("The history files couldn’t be removed completely.")
        } else {
            lastError = nil
        }
        if wasRecording {
            database = try? HistoryDatabase(url: url)
            isRecording = database != nil
        }
        revision += 1
        refreshSize()
    }

    func refreshSize() {
        guard allowed else {
            databaseSize = 0
            return
        }
        databaseSize = url.map { HistoryDatabase.fileSize(at: $0) } ?? 0
    }

    /// Vorhandene Datei zum Lesen öffnen (Aufzeichnung aus, aber alte Werte da).
    private func openExisting() -> HistoryDatabase? {
        guard allowed, let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? HistoryDatabase(url: url)
    }
}
