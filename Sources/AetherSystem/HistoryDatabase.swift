import Foundation
import SQLite3
import AetherCore

/// Lokaler Verlauf in SQLite (Systembibliothek). Ein Datensatz je Minute; fehlende Messungen bleiben NULL.
/// Alle Zugriffe laufen über eine eigene serielle Warteschlange. Die Datei verlässt den Mac nie.
public final class HistoryDatabase: @unchecked Sendable {
    public enum OpenError: Error, CustomStringConvertible {
        case directory(String)
        case sqlite(String)

        public var description: String {
            switch self {
            case .directory(let message), .sqlite(let message): return message
            }
        }
    }

    public let url: URL
    private let queue = DispatchQueue(label: "aether.history.database", qos: .utility)
    private var db: OpaquePointer?

    /// ~/Library/Application Support/ORBIT/history.sqlite
    ///
    /// Bis Version 1.2 hieß die App AETHER und speicherte unter „…/Application Support/AETHER“. Gibt es den neuen Ordner
    /// noch nicht, wird der alte einmalig umbenannt (verschoben, nicht kopiert oder gelöscht) – der Verlauf bleibt erhalten.
    /// Schlägt das fehl (z. B. fehlende Rechte), bleibt die App beim alten Ordner, statt Daten zu verlieren.
    public static func defaultURL() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return migratedFolder(in: support).appendingPathComponent("history.sqlite")
    }

    /// Ordner für die Daten der App in `support` (mit einmaliger Übernahme des früheren AETHER-Ordners).
    public static func migratedFolder(in support: URL, fileManager: FileManager = .default) -> URL {
        let current = support.appendingPathComponent("ORBIT", isDirectory: true)
        let legacy = support.appendingPathComponent("AETHER", isDirectory: true) // Name bis Version 1.2
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: current.path) { return current }
        guard fileManager.fileExists(atPath: legacy.path, isDirectory: &isDir), isDir.boolValue else { return current }
        do {
            try fileManager.moveItem(at: legacy, to: current)
            return current
        } catch {
            return legacy
        }
    }

    /// Öffnet (und legt bei Bedarf an) die Datenbank.
    public init(url: URL) throws {
        self.url = url
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw OpenError.directory(error.localizedDescription)
        }
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite3_open_v2"
            sqlite3_close(handle)
            throw OpenError.sqlite(message)
        }
        db = handle
        let schema = """
        PRAGMA journal_mode=WAL;
        PRAGMA synchronous=NORMAL;
        CREATE TABLE IF NOT EXISTS samples (
            t INTEGER PRIMARY KEY,
            cpu REAL, mem REAL, pressure INTEGER, swap REAL,
            down REAL, up REAL, bat REAL, batw REAL, temp REAL, thermal INTEGER
        );
        """
        guard sqlite3_exec(handle, schema, nil, nil, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            db = nil
            throw OpenError.sqlite(message)
        }
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    /// Schließt die Datenbank (danach sind alle Aufrufe wirkungslos).
    public func close() {
        queue.sync { () -> Void in
            if let db { sqlite3_close(db) }
            db = nil
        }
    }

    // MARK: Schreiben

    /// Minutenwert speichern (im Hintergrund).
    public func insert(_ sample: HistorySample) {
        queue.async { [self] in _ = write(sample) }
    }

    /// Minutenwert sofort speichern (z. B. beim Beenden, im Selbsttest).
    @discardableResult
    public func insertNow(_ sample: HistorySample) -> Bool {
        queue.sync { write(sample) }
    }

    private func write(_ sample: HistorySample) -> Bool {
        guard let db else { return false }
        let sql = "INSERT OR REPLACE INTO samples (t, cpu, mem, pressure, swap, down, up, bat, batw, temp, thermal) VALUES (?,?,?,?,?,?,?,?,?,?,?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(sample.time.timeIntervalSince1970.rounded(.down)))
        bind(statement, 2, sample.cpuBusy)
        bind(statement, 3, sample.memoryUsed)
        bind(statement, 4, sample.pressure)
        bind(statement, 5, sample.swapUsed)
        bind(statement, 6, sample.download)
        bind(statement, 7, sample.upload)
        bind(statement, 8, sample.batteryPercent)
        bind(statement, 9, sample.batteryPower)
        bind(statement, 10, sample.hottest)
        bind(statement, 11, sample.thermalState)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func bind(_ statement: OpaquePointer, _ index: Int32, _ value: Double?) {
        if let value, value.isFinite { sqlite3_bind_double(statement, index, value) } else { sqlite3_bind_null(statement, index) }
    }

    private func bind(_ statement: OpaquePointer, _ index: Int32, _ value: Int?) {
        if let value { sqlite3_bind_int64(statement, index, Int64(value)) } else { sqlite3_bind_null(statement, index) }
    }

    // MARK: Lesen

    /// Werte im Zeitraum (aufsteigend). Blockiert – nicht im Hauptthread aufrufen.
    public func samples(from start: Date, to end: Date) -> [HistorySample] {
        queue.sync { read(from: start, to: end) }
    }

    /// Werte im Zeitraum, Ergebnis im Hintergrund.
    public func load(from start: Date, to end: Date, completion: @escaping @Sendable ([HistorySample]) -> Void) {
        queue.async { [self] in completion(read(from: start, to: end)) }
    }

    private func read(from start: Date, to end: Date) -> [HistorySample] {
        guard let db else { return [] }
        let sql = "SELECT t, cpu, mem, pressure, swap, down, up, bat, batw, temp, thermal FROM samples WHERE t >= ? AND t <= ? ORDER BY t"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(start.timeIntervalSince1970.rounded(.down)))
        sqlite3_bind_int64(statement, 2, Int64(end.timeIntervalSince1970.rounded(.up)))
        var result: [HistorySample] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            func double(_ column: Int32) -> Double? {
                sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : sqlite3_column_double(statement, column)
            }
            func integer(_ column: Int32) -> Int? {
                sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, column))
            }
            result.append(HistorySample(time: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 0))),
                                        cpuBusy: double(1), memoryUsed: double(2), pressure: integer(3), swapUsed: double(4),
                                        download: double(5), upload: double(6), batteryPercent: double(7),
                                        batteryPower: double(8), hottest: double(9), thermalState: integer(10)))
        }
        return result
    }

    /// Anzahl der gespeicherten Minutenwerte.
    public func count() -> Int {
        queue.sync { () -> Int in
            guard let db else { return 0 }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM samples", -1, &statement, nil) == SQLITE_OK, let statement else { return 0 }
            defer { sqlite3_finalize(statement) }
            return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
        }
    }

    // MARK: Aufräumen

    /// Werte vor dem Stichtag löschen (Aufbewahrungsdauer).
    public func prune(before date: Date) {
        queue.async { [self] in
            guard let db else { return }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM samples WHERE t < ?", -1, &statement, nil) == SQLITE_OK, let statement else { return }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, Int64(date.timeIntervalSince1970.rounded(.down)))
            _ = sqlite3_step(statement)
        }
    }

    /// Datenbank, Journal und gemeinsamer Speicher (alle drei Dateien).
    public static func files(for url: URL) -> [URL] {
        [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")]
    }

    /// Belegter Platz aller zugehörigen Dateien in Bytes (0, wenn es keine gibt).
    public static func fileSize(at url: URL) -> Int64 {
        files(for: url).reduce(Int64(0)) { total, file in
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
            return total + size
        }
    }

    /// Entfernt alle Dateien des Verlaufs. Die Datenbank muss vorher geschlossen sein.
    @discardableResult
    public static func removeFiles(at url: URL) -> Bool {
        var ok = true
        for file in files(for: url) where FileManager.default.fileExists(atPath: file.path) {
            do { try FileManager.default.removeItem(at: file) } catch { ok = false }
        }
        return ok
    }
}
