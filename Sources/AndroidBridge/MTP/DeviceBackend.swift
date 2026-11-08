import Foundation
import ABCore

/// Dateizugriff auf ein verbundenes Gerät. In der App immer echtes MTP über USB;
/// die Vorschau-Implementierung existiert ausschließlich für automatische Bildschirmfotos im Build.
protocol DeviceBackend: AnyObject {
    var supportsPartialDownload: Bool { get }
    func storages() async throws -> [DeviceStorage]
    func list(storage: UInt32, parent: UInt32) async throws -> [DeviceEntry]
    func entry(handle: UInt32) async throws -> DeviceEntry
    func thumbnail(handle: UInt32) async throws -> Data?
    /// Ganze Datei (Bytes werden auf der Gerätewarteschlange an `sink` gereicht).
    func download(handle: UInt32, sink: @escaping (Data) throws -> Void, progress: @escaping (UInt64) -> Bool) async throws
    /// Abschnitt einer Datei; liefert die Anzahl Bytes.
    func downloadSegment(handle: UInt32, offset: UInt64, length: UInt32, sink: @escaping (Data) throws -> Void) async throws -> UInt64
    /// Neue Datei; `next` liefert die Bytes stückweise. Ergebnis: neues Handle.
    func upload(name: String, size: UInt64, storage: UInt32, parent: UInt32, modified: Date?,
                next: @escaping (Int) throws -> Data, progress: @escaping (UInt64) -> Bool) async throws -> UInt32
    func createFolder(name: String, storage: UInt32, parent: UInt32) async throws -> UInt32
    func delete(handle: UInt32) async throws
    /// Löscht eine Datei bzw. einen Ordner samt Inhalt (echte MTP-Löschung, kein Papierkorb).
    func deleteTree(handle: UInt32, storage: UInt32, isFolder: Bool) async throws -> MTPSession.DeleteTreeResult
    func rename(handle: UInt32, to name: String) async throws
    /// Akkustand in Prozent oder `nil`.
    func batteryLevel() async -> Int?
    func close(graceful: Bool)
}

/// Echte Geräteverbindung über MTP.
final class MTPBackend: DeviceBackend {
    let worker: MTPWorker
    private(set) var supportsPartialDownload = false
    private(set) var supportsBattery = false

    init(worker: MTPWorker, info: MTPDeviceInfo) {
        self.worker = worker
        supportsPartialDownload = info.supports(.getPartialObject64) || info.supports(.getPartialObject)
        supportsBattery = info.supports(.getDevicePropValue) && info.devicePropertiesSupported.contains(0x5001)
    }

    func storages() async throws -> [DeviceStorage] {
        try await worker.withSession(priority: .veryHigh) { s, _ in
            try s.storageIDs().map { id in DeviceStorage(id: id, info: try s.storageInfo(id)) }
        }
    }

    func list(storage: UInt32, parent: UInt32) async throws -> [DeviceEntry] {
        try await worker.withSession(priority: .high) { s, flag in
            try s.children(storage: storage, parent: parent, cancelled: { flag.isCancelled })
        }
    }

    func entry(handle: UInt32) async throws -> DeviceEntry {
        try await worker.withSession(priority: .high) { s, _ in
            let info = try s.objectInfo(handle)
            var size: UInt64? = nil
            if info.sizeIsTruncated && !info.isFolder { size = try? s.objectSize64(handle) }
            return DeviceEntry(handle: handle, info: info, fullSize: size)
        }
    }

    func thumbnail(handle: UInt32) async throws -> Data? {
        try await worker.withSession(priority: .low) { s, _ in
            do {
                let data = try s.thumbnail(handle)
                return data.isEmpty ? nil : data
            } catch let e as MTPError where e.responseCode != nil {
                return nil // kein Vorschaubild vorhanden
            }
        }
    }

    func download(handle: UInt32, sink: @escaping (Data) throws -> Void, progress: @escaping (UInt64) -> Bool) async throws {
        try await worker.withSession(priority: .normal) { s, flag in
            try s.download(handle, sink: sink, progress: { bytes in !flag.isCancelled && progress(bytes) })
        }
    }

    func downloadSegment(handle: UInt32, offset: UInt64, length: UInt32, sink: @escaping (Data) throws -> Void) async throws -> UInt64 {
        try await worker.withSession(priority: .normal) { s, _ in
            try s.downloadPartial(handle, offset: offset, length: length, sink: sink)
        }
    }

    func upload(name: String, size: UInt64, storage: UInt32, parent: UInt32, modified: Date?,
                next: @escaping (Int) throws -> Data, progress: @escaping (UInt64) -> Bool) async throws -> UInt32 {
        try await worker.withSession(priority: .normal) { s, flag in
            let info = MTPObjectInfo.forUpload(name: name, size: size, storageID: storage, parent: parent, modified: modified)
            let handle = try s.sendObjectInfo(info, storage: storage, parent: parent)
            do {
                try s.sendObject(length: size, next: next, progress: { bytes in !flag.isCancelled && progress(bytes) })
            } catch {
                // Unvollständiges Objekt auf dem Gerät nicht zurücklassen.
                try? s.delete(handle)
                throw error
            }
            return handle
        }
    }

    func createFolder(name: String, storage: UInt32, parent: UInt32) async throws -> UInt32 {
        try await worker.withSession(priority: .high) { s, _ in
            try s.createFolder(name: name, storage: storage, parent: parent)
        }
    }

    func delete(handle: UInt32) async throws {
        try await worker.withSession(priority: .high) { s, _ in try s.delete(handle) }
    }

    func deleteTree(handle: UInt32, storage: UInt32, isFolder: Bool) async throws -> MTPSession.DeleteTreeResult {
        try await worker.withSession(priority: .high) { s, flag in
            try s.deleteTree(handle, storage: storage, isFolder: isFolder, cancelled: { flag.isCancelled })
        }
    }

    func rename(handle: UInt32, to name: String) async throws {
        try await worker.withSession(priority: .high) { s, _ in try s.rename(handle, to: name) }
    }

    func batteryLevel() async -> Int? {
        guard supportsBattery else { return nil }
        return try? await worker.withSession(priority: .low) { s, _ in try s.batteryLevel() }
    }

    func close(graceful: Bool) { worker.close(graceful: graceful) }
}
