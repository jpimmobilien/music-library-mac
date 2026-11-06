import Foundation

/// Grobe Dateiart für Symbole, Galerie-Filter und Zielordner.
public enum FileKind: String, CaseIterable, Codable, Sendable {
    case folder, photo, video, audio, document, archive, apk, other

    public static let photoExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "bmp", "tif", "tiff", "dng", "raw", "avif"]
    public static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "3gp", "3g2", "mkv", "webm", "avi", "wmv", "mpg", "mpeg", "ts"]
    public static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "oga", "opus", "amr", "wma", "mid", "midi", "aiff", "aif"]
    public static let documentExtensions: Set<String> = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "md", "csv", "odt", "ods", "odp", "pages", "numbers", "key", "epub", "html", "htm", "json", "xml", "vcf", "ics"]
    public static let archiveExtensions: Set<String> = ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz"]

    public static func fileExtension(of name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return String(name[name.index(after: dot)...]).lowercased()
    }

    public static func of(name: String, isFolder: Bool) -> FileKind {
        if isFolder { return .folder }
        let ext = fileExtension(of: name)
        if photoExtensions.contains(ext) { return .photo }
        if videoExtensions.contains(ext) { return .video }
        if audioExtensions.contains(ext) { return .audio }
        if documentExtensions.contains(ext) { return .document }
        if archiveExtensions.contains(ext) { return .archive }
        if ext == "apk" || ext == "apks" || ext == "xapk" { return .apk }
        return .other
    }

    public var isMedia: Bool { self == .photo || self == .video }

    /// SF-Symbol für die Dateiart.
    public var symbolName: String {
        switch self {
        case .folder: return "folder.fill"
        case .photo: return "photo"
        case .video: return "film"
        case .audio: return "music.note"
        case .document: return "doc.text"
        case .archive: return "archivebox"
        case .apk: return "shippingbox"
        case .other: return "doc"
        }
    }
}

/// Filter der Medien-/Dateiansicht.
public enum MediaFilter: String, CaseIterable, Identifiable, Codable, Sendable {
    case all, media, photos, videos, screenshots, downloads, documents, audio

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "Alle Dateien"
        case .media: return "Fotos & Videos"
        case .photos: return "Fotos"
        case .videos: return "Videos"
        case .screenshots: return "Bildschirmfotos"
        case .downloads: return "Downloads"
        case .documents: return "Dokumente"
        case .audio: return "Audio"
        }
    }

    public var symbolName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .media: return "photo.stack"
        case .photos: return "photo.on.rectangle"
        case .videos: return "film.stack"
        case .screenshots: return "camera.viewfinder"
        case .downloads: return "arrow.down.circle"
        case .documents: return "doc.on.doc"
        case .audio: return "waveform"
        }
    }

    /// Passt ein Eintrag (Name + Pfad der Elternordner) zum Filter?
    public func matches(name: String, kind: FileKind, path: [String]) -> Bool {
        let lowerPath = path.map { $0.lowercased() }
        switch self {
        case .all: return kind != .folder
        case .media: return kind.isMedia
        case .photos: return kind == .photo
        case .videos: return kind == .video
        case .audio: return kind == .audio
        case .documents: return kind == .document
        case .screenshots:
            return kind == .photo && (lowerPath.contains("screenshots") || lowerPath.contains("screenshot")
                || name.lowercased().hasPrefix("screenshot"))
        case .downloads:
            return kind != .folder && (lowerPath.contains("download") || lowerPath.contains("downloads"))
        }
    }
}
