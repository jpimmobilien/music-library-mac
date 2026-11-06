import Foundation
import AppKit
import ABCore

/// Eintrag im Mac-Dateisystem.
struct LocalEntry: Identifiable, Hashable, SortableEntry {
    var id: URL { url }
    let url: URL
    let name: String
    let isFolder: Bool
    let isPackage: Bool
    let size: UInt64
    let modified: Date?
    let isHidden: Bool

    var kind: FileKind { FileKind.of(name: name, isFolder: isFolder && !isPackage) }
    var sortName: String { name }
    var sortIsFolder: Bool { isFolder && !isPackage }
    var sortSize: UInt64 { size }
    var sortDate: Date? { modified }
}

struct LocalPlace: Identifiable, Hashable {
    var id: URL { url }
    let name: String
    let url: URL
    let symbolName: String
}

enum LocalFiles {
    static let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .fileSizeKey, .totalFileAllocatedSizeKey,
                                         .contentModificationDateKey, .isHiddenKey, .localizedNameKey]

    static func list(_ folder: URL, showHidden: Bool) throws -> [LocalEntry] {
        let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: options)
        return urls.compactMap { entry(for: $0) }
    }

    static func entry(for url: URL) -> LocalEntry? {
        guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        let isDir = v.isDirectory ?? false
        return LocalEntry(url: url, name: v.localizedName ?? url.lastPathComponent, isFolder: isDir,
                          isPackage: v.isPackage ?? false, size: UInt64(max(0, v.fileSize ?? 0)),
                          modified: v.contentModificationDate, isHidden: v.isHidden ?? false)
    }

    static var places: [LocalPlace] {
        let fm = FileManager.default
        var list: [LocalPlace] = []
        let home = fm.homeDirectoryForCurrentUser
        list.append(LocalPlace(name: "Benutzerordner", url: home, symbolName: "house"))
        let standard: [(FileManager.SearchPathDirectory, String, String)] = [
            (.desktopDirectory, "Schreibtisch", "menubar.dock.rectangle"),
            (.documentDirectory, "Dokumente", "doc"),
            (.downloadsDirectory, "Downloads", "arrow.down.circle"),
            (.picturesDirectory, "Bilder", "photo"),
            (.moviesDirectory, "Filme", "film"),
            (.musicDirectory, "Musik", "music.note"),
        ]
        for (dir, name, symbol) in standard {
            if let url = fm.urls(for: dir, in: .userDomainMask).first { list.append(LocalPlace(name: name, url: url, symbolName: symbol)) }
        }
        return list
    }

    /// Angeschlossene Laufwerke (externe Festplatten, USB-Sticks).
    static var volumes: [LocalPlace] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeLocalizedNameKey, .volumeIsRemovableKey, .volumeIsInternalKey],
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            let v = try? url.resourceValues(forKeys: [.volumeLocalizedNameKey, .volumeIsRemovableKey, .volumeIsInternalKey])
            let isInternal = v?.volumeIsInternal ?? false
            if url.path == "/" { return LocalPlace(name: v?.volumeLocalizedName ?? "Macintosh HD", url: url, symbolName: "internaldrive") }
            return LocalPlace(name: v?.volumeLocalizedName ?? url.lastPathComponent, url: url, symbolName: isInternal ? "internaldrive" : "externaldrive")
        }
    }

    static func availableCapacity(at url: URL) -> UInt64? {
        var probe = url
        while !FileManager.default.fileExists(atPath: probe.path) && probe.path != "/" { probe.deleteLastPathComponent() }
        guard let v = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]) else { return nil }
        if let important = v.volumeAvailableCapacityForImportantUsage, important > 0 { return UInt64(important) }
        if let cap = v.volumeAvailableCapacity { return UInt64(max(0, cap)) }
        return nil
    }

    /// Alle Dateien eines Ordners rekursiv (für Ordnerübertragungen), relative Pfade.
    static func enumerateFiles(in folder: URL, skipMetadata: Bool) -> (files: [(url: URL, relative: [String], size: UInt64)], folders: [[String]]) {
        var files: [(URL, [String], UInt64)] = []
        var folders: [[String]] = []
        guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]) else {
            return ([], [])
        }
        let baseCount = folder.standardizedFileURL.pathComponents.count
        for case let url as URL in e {
            let name = url.lastPathComponent
            if skipMetadata && HiddenFiles.isMacMetadata(name) {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { e.skipDescendants() }
                continue
            }
            let rel = Array(url.standardizedFileURL.pathComponents.dropFirst(baseCount))
            let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey])
            if v?.isDirectory == true && v?.isPackage != true {
                folders.append(rel)
            } else {
                files.append((url, rel, UInt64(max(0, v?.fileSize ?? 0))))
            }
        }
        return (files.map { (url: $0.0, relative: $0.1, size: $0.2) }, folders)
    }
}
