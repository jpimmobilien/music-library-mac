import Foundation

/// Sortierung in Listen und Galerie.
public enum EntrySort: String, CaseIterable, Identifiable, Codable, Sendable {
    case name, newest, oldest, size, type

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .name: return "Name"
        case .newest: return "Neueste zuerst"
        case .oldest: return "Älteste zuerst"
        case .size: return "Größe"
        case .type: return "Art"
        }
    }
}

/// Allgemeine Eigenschaften, die lokale und Android-Einträge gemeinsam haben.
public protocol SortableEntry {
    var sortName: String { get }
    var sortIsFolder: Bool { get }
    var sortSize: UInt64 { get }
    var sortDate: Date? { get }
}

extension DeviceEntry: SortableEntry {
    public var sortName: String { name }
    public var sortIsFolder: Bool { isFolder }
    public var sortSize: UInt64 { size }
    public var sortDate: Date? { bestDate }
}

public enum EntrySorting {
    /// Sortiert stabil; Ordner stehen immer oben, Namen in natürlicher Reihenfolge („Bild 2“ vor „Bild 10“).
    public static func sorted<T: SortableEntry>(_ items: [T], by sort: EntrySort, foldersFirst: Bool = true) -> [T] {
        let indexed = Array(items.enumerated())
        let result = indexed.sorted { a, b in
            let x = a.element, y = b.element
            if foldersFirst && x.sortIsFolder != y.sortIsFolder { return x.sortIsFolder }
            let order: ComparisonResult
            switch sort {
            case .name:
                order = naturalCompare(x.sortName, y.sortName)
            case .newest, .oldest:
                let dx = x.sortDate ?? .distantPast, dy = y.sortDate ?? .distantPast
                if dx == dy { order = naturalCompare(x.sortName, y.sortName) }
                else { order = (dx < dy) == (sort == .oldest) ? .orderedAscending : .orderedDescending }
            case .size:
                if x.sortSize == y.sortSize { order = naturalCompare(x.sortName, y.sortName) }
                else { order = x.sortSize > y.sortSize ? .orderedAscending : .orderedDescending }
            case .type:
                let ex = FileKind.fileExtension(of: x.sortName), ey = FileKind.fileExtension(of: y.sortName)
                order = ex == ey ? naturalCompare(x.sortName, y.sortName) : (ex < ey ? .orderedAscending : .orderedDescending)
            }
            if order == .orderedSame { return a.offset < b.offset }
            return order == .orderedAscending
        }
        return result.map(\.element)
    }

    public static func naturalCompare(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(b, options: [.caseInsensitive, .numeric, .diacriticInsensitive, .widthInsensitive], range: nil, locale: Locale(identifier: "de_DE"))
    }

    /// Suche: alle Wörter müssen im Namen vorkommen (ohne Groß-/Kleinschreibung und Akzente).
    public static func matches(name: String, query: String) -> Bool {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return true }
        return words.allSatisfy { name.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

/// Verhalten bei Namenskonflikten am Ziel.
public enum ConflictResolution: String, CaseIterable, Identifiable, Codable, Sendable {
    case ask, replace, keepBoth, skip

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ask: return "Jedes Mal fragen"
        case .replace: return "Ersetzen"
        case .keepBoth: return "Beide behalten"
        case .skip: return "Überspringen"
        }
    }
}

public enum ConflictNaming {
    /// Freier Name nach dem Muster „Foto 2.jpg“, „Foto 3.jpg“ … (wie der Finder).
    public static func uniqueName(for name: String, existing: Set<String>) -> String {
        let lowered = Set(existing.map { $0.lowercased() })
        if !lowered.contains(name.lowercased()) { return name }
        let ext = FileKind.fileExtension(of: name)
        let hasExt = !ext.isEmpty && !name.hasPrefix(".")
        let base = hasExt ? String(name.dropLast(ext.count + 1)) : name
        var stem = base
        var start = 2
        // „Foto 2“ → weiterzählen statt „Foto 2 2“
        if let space = base.lastIndex(of: " "), let n = Int(base[base.index(after: space)...]), n >= 2, n < 100_000 {
            stem = String(base[..<space])
            start = n + 1
        }
        var i = start
        while true {
            let candidate = hasExt ? "\(stem) \(i).\(name.suffix(ext.count))" : "\(stem) \(i)"
            if !lowered.contains(candidate.lowercased()) { return candidate }
            i += 1
        }
    }
}

/// Unerwünschte macOS-Metadaten, die nicht auf das Telefon übertragen werden sollen.
public enum HiddenFiles {
    public static let macMetadataNames: Set<String> = [".DS_Store", ".localized", ".Spotlight-V100", ".Trashes", ".fseventsd",
                                                       ".TemporaryItems", ".DocumentRevisions-V100", ".VolumeIcon.icns",
                                                       ".com.apple.timemachine.donotpresent", ".apdisk", "Icon\r"]

    /// macOS-Metadaten (.DS_Store, AppleDouble „._Name“ …) – echte Android-Dateien wie „.nomedia“ bleiben unberührt.
    public static func isMacMetadata(_ name: String) -> Bool {
        if macMetadataNames.contains(name) { return true }
        if name.hasPrefix("._") && name.count > 2 { return true }
        return false
    }

    /// Versteckte Datei im Unix-Sinne (Name beginnt mit Punkt).
    public static func isHidden(_ name: String) -> Bool { name.hasPrefix(".") }
}

/// Dateinamen, die auf Android-Dateisystemen (FAT/exFAT der SD-Karte) unzulässig sind, entschärfen.
public enum FileNameSanitizer {
    public static func androidSafe(_ name: String) -> String {
        let forbidden: Set<Character> = ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]
        var out = String(name.map { forbidden.contains($0) ? "_" : $0 })
        out = out.trimmingCharacters(in: .whitespaces)
        while out.hasSuffix(".") && out.count > 1 { out.removeLast() }
        return out.isEmpty ? "Unbenannt" : out
    }

    /// Mac-Dateinamen: „/“ ist unzulässig, „:“ erscheint im Finder als „/“.
    public static func macSafe(_ name: String) -> String {
        var out = name.replacingOccurrences(of: "/", with: "_")
        if out == "." || out == ".." || out.isEmpty { out = "Unbenannt" }
        return out
    }
}
