import Foundation
import ABCore

/// Speicherort für lokale App-Daten (Favoriten, Verlauf, zuletzt verwendet) – nur auf diesem Mac.
enum AppPaths {
    static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Android Bridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Vorschauen großer Bilder/Videos: temporär, wird beim Beenden und Start geleert.
    static var previewCache: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AndroidBridge-Preview", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func clearPreviewCache() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AndroidBridge-Preview", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }
}

/// Pfad auf einem Android-Gerät, unabhängig von (sitzungsabhängigen) Objekt-Handles.
struct DeviceLocation: Codable, Hashable {
    var deviceSerial: String
    var deviceName: String
    var storageID: UInt32
    var storageName: String
    var path: [String]

    var displayPath: String { ([storageName] + path).joined(separator: " › ") }
}

struct FavoriteFolder: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var location: DeviceLocation
}

struct RecentFile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var size: UInt64
    var location: DeviceLocation
    var date: Date
}

struct HistoryRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var title: String
    var direction: String
    var fileCount: Int
    var bytes: UInt64
    var succeeded: Bool
    var detail: String
}

/// JSON-Dateien im Programmunterstützungsordner.
final class JSONFileStore<T: Codable> {
    let url: URL
    init(fileName: String) { url = AppPaths.applicationSupport.appendingPathComponent(fileName) }

    func load() -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(T.self, from: data)
    }

    func save(_ value: T) {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? e.encode(value) { try? data.write(to: url, options: .atomic) }
    }

    func delete() { try? FileManager.default.removeItem(at: url) }
}

final class FavoritesStore: ObservableObject {
    @Published private(set) var favorites: [FavoriteFolder] = []
    private let store = JSONFileStore<[FavoriteFolder]>(fileName: "Favoriten.json")
    private let persist: Bool

    init(persist: Bool = true) {
        self.persist = persist
        if persist { favorites = store.load() ?? [] }
    }

    func contains(_ location: DeviceLocation) -> Bool {
        favorites.contains { $0.location.deviceSerial == location.deviceSerial && $0.location.storageID == location.storageID && $0.location.path == location.path }
    }

    func toggle(_ location: DeviceLocation) {
        if contains(location) {
            favorites.removeAll { $0.location.deviceSerial == location.deviceSerial && $0.location.storageID == location.storageID && $0.location.path == location.path }
        } else {
            favorites.append(FavoriteFolder(name: location.path.last ?? location.storageName, location: location))
        }
        save()
    }

    func remove(_ favorite: FavoriteFolder) {
        favorites.removeAll { $0.id == favorite.id }
        save()
    }

    func move(from: IndexSet, to: Int) {
        favorites.move(fromOffsets: from, toOffset: to)
        save()
    }

    private func save() { if persist { store.save(favorites) } }
}

final class RecentsStore: ObservableObject {
    @Published private(set) var recents: [RecentFile] = []
    private let store = JSONFileStore<[RecentFile]>(fileName: "Zuletzt.json")
    private let persist: Bool
    var isEnabled: () -> Bool = { true }

    init(persist: Bool = true) {
        self.persist = persist
        if persist { recents = store.load() ?? [] }
    }

    func add(name: String, size: UInt64, location: DeviceLocation) {
        guard isEnabled() else { return }
        recents.removeAll { $0.name == name && $0.location == location }
        recents.insert(RecentFile(name: name, size: size, location: location, date: Date()), at: 0)
        if recents.count > 60 { recents.removeLast(recents.count - 60) }
        save()
    }

    func clear() {
        recents = []
        if persist { store.delete() }
    }

    private func save() { if persist { store.save(recents) } }
}

final class HistoryStore: ObservableObject {
    @Published private(set) var records: [HistoryRecord] = []
    private let store = JSONFileStore<[HistoryRecord]>(fileName: "Verlauf.json")
    private let persist: Bool
    var isEnabled: () -> Bool = { true }

    init(persist: Bool = true) {
        self.persist = persist
        if persist { records = store.load() ?? [] }
    }

    func add(_ record: HistoryRecord) {
        guard isEnabled() else { return }
        records.insert(record, at: 0)
        if records.count > 300 { records.removeLast(records.count - 300) }
        save()
    }

    func clear() {
        records = []
        if persist { store.delete() }
    }

    private func save() { if persist { store.save(records) } }
}
