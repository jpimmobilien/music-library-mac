import Foundation
import AppKit
import UniformTypeIdentifiers
import AetherCore

/// Ein Eintrag in einem Ordner – nur Angaben, die macOS über öffentliche Ressourcenschlüssel liefert.
struct FileItem: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    /// Name wie im Finder (z. B. ohne ausgeblendete Endung).
    let name: String
    /// Echter Dateiname auf dem Datenträger.
    let fileName: String
    /// Ordner, in den man hineinnavigiert (Pakete wie .app zählen nicht dazu).
    let isFolder: Bool
    let isPackage: Bool
    let isHidden: Bool
    let isSymlink: Bool
    let isReadable: Bool
    /// Logische Größe (nur Dateien und Pakete, sofern gemeldet).
    let size: Int64?
    let allocatedSize: Int64?
    let modified: Date?
    let created: Date?
    let kind: String
    let contentType: UTType?

    // Sortierschlüssel für die Tabelle
    var sortSize: Int64 { size ?? -1 }
    var sortDate: Date { modified ?? .distantPast }
    var parentPath: String { url.deletingLastPathComponent().path }

    static let resourceKeys: [URLResourceKey] = [
        .localizedNameKey, .nameKey, .isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey, .isReadableKey,
        .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey, .creationDateKey,
        .localizedTypeDescriptionKey, .contentTypeKey,
    ]

    init?(url: URL) {
        guard let values = try? url.resourceValues(forKeys: Set(Self.resourceKeys)) else { return nil }
        self.url = url
        fileName = values.name ?? url.lastPathComponent
        name = values.localizedName ?? fileName
        isPackage = values.isPackage ?? false
        isFolder = (values.isDirectory ?? false) && !isPackage
        isHidden = values.isHidden ?? fileName.hasPrefix(".")
        isSymlink = values.isSymbolicLink ?? false
        isReadable = values.isReadable ?? true
        size = isFolder ? nil : values.fileSize.map(Int64.init)
        allocatedSize = values.totalFileAllocatedSize.map(Int64.init)
        modified = values.contentModificationDate
        created = values.creationDate
        kind = values.localizedTypeDescription ?? (isFolder ? tr("Folder") : tr("Document"))
        contentType = values.contentType
    }
}

/// Liest Ordnerinhalte (immer außerhalb des Hauptthreads aufrufen).
enum DirectoryLoader {
    enum Failure: Error {
        case noPermission
        case notFound
        case other(String)
    }

    static func load(_ folder: URL, showHidden: Bool) -> Result<[FileItem], Failure> {
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: FileItem.resourceKeys,
                                                                   options: showHidden ? [] : [.skipsHiddenFiles])
            return .success(urls.compactMap(FileItem.init(url:)))
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            return .failure(.noPermission)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return .failure(.notFound)
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && (error.code == Int(EPERM) || error.code == Int(EACCES)) {
            return .failure(.noPermission)
        } catch {
            return .failure(.other(error.localizedDescription))
        }
    }

    /// Belegter Platz eines Ordners (Summe der zugewiesenen Größen). Abbrechbar über `isCancelled`.
    /// Nicht lesbare Unterordner werden übersprungen und gezählt.
    static func folderSize(_ folder: URL, isCancelled: () -> Bool) -> (bytes: Int64, items: Int, unreadable: Int)? {
        var bytes: Int64 = 0
        var count = 0
        var unreadable = 0
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [],
                                                              errorHandler: { _, _ in unreadable += 1; return true }) else { return nil }
        for case let url as URL in enumerator {
            if count % 500 == 0, isCancelled() { return nil }
            count += 1
            if let size = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize {
                bytes += Int64(size)
            }
        }
        return (bytes, count, unreadable)
    }
}

/// Symbole aus dem System (wie im Finder), zwischengespeichert.
@MainActor
enum FileIcons {
    private static let cache = NSCache<NSURL, NSImage>()

    static func icon(for url: URL) -> NSImage {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// Orte in der Seitenleiste.
struct FilePlace: Identifiable, Hashable {
    var id: URL { url }
    let title: String
    let symbol: String
    let url: URL

    static func favorites() -> [FilePlace] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        func dir(_ directory: FileManager.SearchPathDirectory) -> URL? {
            fm.urls(for: directory, in: .userDomainMask).first
        }
        var result: [FilePlace] = [FilePlace(title: NSUserName(), symbol: "house", url: home)]
        let entries: [(String, String, URL?)] = [
            (tr("Desktop"), "menubar.dock.rectangle", dir(.desktopDirectory)),
            (tr("Documents"), "doc", dir(.documentDirectory)),
            (tr("Downloads"), "arrow.down.circle", dir(.downloadsDirectory)),
            (tr("Applications"), "square.grid.3x3", URL(fileURLWithPath: "/Applications")),
            (tr("Pictures"), "photo", dir(.picturesDirectory)),
            (tr("Music"), "music.note", dir(.musicDirectory)),
            (tr("Movies"), "film", dir(.moviesDirectory)),
        ]
        for (title, symbol, url) in entries {
            if let url, fm.fileExists(atPath: url.path) { result.append(FilePlace(title: title, symbol: symbol, url: url)) }
        }
        return result
    }
}
