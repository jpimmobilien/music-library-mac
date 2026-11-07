import Foundation

// =============================================================================================
// Speicheranalyse: Kategorien, größte Dateien und Ordner, Duplikat-Kandidaten, NVMe-SMART-Dekodierung,
// Bereinigungsorte. Reine Logik ohne Apple-Frameworks (unter Linux getestet); das Durchsuchen des Dateisystems,
// die Prüfsummen (CryptoKit) und das Lesen der SMART-Daten (IOKit) liegen in AetherSystem.
// =============================================================================================

// MARK: - Kategorien

/// Grobe Dateiart, nur aus der Dateiendung abgeleitet (keine Inhaltsanalyse).
public enum FileCategory: String, CaseIterable, Sendable, Codable {
    case images, videos, audio, documents, archives, applications, code, other

    private static let table: [String: FileCategory] = {
        var map: [String: FileCategory] = [:]
        func add(_ category: FileCategory, _ extensions: String) {
            for ext in extensions.split(separator: " ") { map[String(ext)] = category }
        }
        add(.images, "jpg jpeg png gif heic heif tif tiff bmp webp avif raw cr2 cr3 nef arw dng orf rw2 raf psd svg ico icns photoslibrary")
        add(.videos, "mov mp4 m4v avi mkv webm mpg mpeg wmv flv 3gp mts m2ts vob fcpbundle imovielibrary tvlibrary")
        add(.audio, "mp3 m4a m4b aac wav aif aiff flac alac ogg oga opus wma caf mid midi logicx band musiclibrary")
        add(.documents, "pdf doc docx xls xlsx ppt pptx pages numbers key txt rtf rtfd md markdown csv tsv odt ods odp epub tex log")
        add(.archives, "zip rar 7z tar gz tgz bz2 xz zst lz4 cpio xip dmg iso img pkg mpkg sparseimage sparsebundle")
        add(.applications, "app appex framework prefpane plugin bundle kext saver qlgenerator")
        add(.code, "swift c h m mm cpp hpp cc cxx py js mjs ts tsx jsx java kt kts go rs rb php sh zsh bash json yaml yml xml html htm css scss sql pl lua dart cs xcodeproj xcworkspace playground ipynb")
        return map
    }()

    /// Ordnet einen Dateinamen (oder ein Paket wie „.app“) einer Kategorie zu.
    public static func classify(fileName: String) -> FileCategory {
        guard let dot = fileName.lastIndex(of: "."), dot != fileName.startIndex else { return .other }
        let ext = fileName[fileName.index(after: dot)...].lowercased()
        return table[ext] ?? .other
    }
}

// MARK: - Dateien und Summen

/// Eine beim Durchsuchen gefundene Datei (oder ein Paket, das als eine Einheit zählt).
public struct ScannedFile: Sendable, Equatable, Hashable, Identifiable {
    public var id: String { path }
    public var path: String
    /// Belegter Platz auf dem Datenträger (totalFileAllocatedSize).
    public var size: Int64
    /// Logische Größe (Dateilänge) – maßgeblich für den Inhaltsvergleich.
    public var logicalSize: Int64
    public var modified: Date?
    public var category: FileCategory
    public var isPackage: Bool
    /// Gerät und Inode: gleiche Werte = harter Link auf dieselben Daten.
    public var device: UInt64
    public var inode: UInt64

    public init(path: String, size: Int64, logicalSize: Int64, modified: Date?, category: FileCategory, isPackage: Bool,
                device: UInt64, inode: UInt64) {
        self.path = path
        self.size = size
        self.logicalSize = logicalSize
        self.modified = modified
        self.category = category
        self.isPackage = isPackage
        self.device = device
        self.inode = inode
    }

    public var name: String { path.split(separator: "/").last.map(String.init) ?? path }

    /// Übergeordneter Ordner.
    public var parentPath: String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return slash == path.startIndex ? "/" : String(path[..<slash])
    }
}

public struct FolderTotal: Sendable, Equatable, Identifiable {
    public var id: String { path }
    public var path: String
    public var name: String
    public var size: Int64
    public var files: Int
    /// `true` für die Dateien, die direkt im untersuchten Ordner liegen.
    public var isLooseFiles: Bool

    public init(path: String, name: String, size: Int64, files: Int, isLooseFiles: Bool = false) {
        self.path = path
        self.name = name
        self.size = size
        self.files = files
        self.isLooseFiles = isLooseFiles
    }
}

public struct CategoryTotal: Sendable, Equatable, Identifiable {
    public var id: FileCategory { category }
    public var category: FileCategory
    public var size: Int64
    public var files: Int

    public init(category: FileCategory, size: Int64, files: Int) {
        self.category = category
        self.size = size
        self.files = files
    }
}

/// Größenschwelle für die Liste der größten Dateien (Dezimaleinheiten wie im Finder).
public enum SizeThreshold: Hashable, Sendable {
    case mb100, mb500, gb1
    case custom(megabytes: Int)

    public var bytes: Int64 {
        switch self {
        case .mb100: return 100_000_000
        case .mb500: return 500_000_000
        case .gb1: return 1_000_000_000
        case .custom(let megabytes): return Int64(max(1, megabytes)) * 1_000_000
        }
    }
}

/// Sammelt Summen beim Durchsuchen: Gesamtgröße, Ordner der obersten Ebene, Kategorien; behält nur Dateien ab
/// `retainThreshold` (für größte Dateien und Duplikate), damit der Speicherbedarf begrenzt bleibt.
public struct StorageTally: Sendable {
    public let rootPath: String
    public let retainThreshold: Int64
    public private(set) var totalSize: Int64 = 0
    public private(set) var fileCount = 0
    public private(set) var folderCount = 0
    public private(set) var retained: [ScannedFile] = []
    private var folderSizes: [String: Int64] = [:]
    private var folderFiles: [String: Int] = [:]
    private var looseSize: Int64 = 0
    private var looseFiles = 0
    private var categorySizes: [FileCategory: Int64] = [:]
    private var categoryFiles: [FileCategory: Int] = [:]

    public init(rootPath: String, retainThreshold: Int64) {
        self.rootPath = rootPath
        self.retainThreshold = retainThreshold
    }

    /// Erste Pfadkomponente unterhalb des Wurzelordners (`nil` = Datei liegt direkt im Wurzelordner oder außerhalb).
    public static func topLevelComponent(path: String, rootPath: String) -> String? {
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard path.hasPrefix(prefix) else { return nil }
        let rest = path.dropFirst(prefix.count)
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        let component = rest[..<slash]
        return component.isEmpty ? nil : String(component)
    }

    public mutating func addFolder() { folderCount += 1 }

    public mutating func add(_ file: ScannedFile) {
        totalSize += file.size
        fileCount += 1
        categorySizes[file.category, default: 0] += file.size
        categoryFiles[file.category, default: 0] += 1
        if let top = Self.topLevelComponent(path: file.path, rootPath: rootPath) {
            folderSizes[top, default: 0] += file.size
            folderFiles[top, default: 0] += 1
        } else {
            looseSize += file.size
            looseFiles += 1
        }
        if file.size >= retainThreshold || file.logicalSize >= retainThreshold {
            retained.append(file)
        }
    }

    /// Ordner der obersten Ebene, absteigend nach Größe; Dateien direkt im Wurzelordner als eigener Eintrag.
    public func folders() -> [FolderTotal] {
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        var result = folderSizes.map { name, size in
            FolderTotal(path: prefix + name, name: name, size: size, files: folderFiles[name] ?? 0)
        }
        if looseFiles > 0 {
            result.append(FolderTotal(path: rootPath, name: "", size: looseSize, files: looseFiles, isLooseFiles: true))
        }
        return result.sorted { $0.size != $1.size ? $0.size > $1.size : $0.name < $1.name }
    }

    /// Kategorien, absteigend nach Größe (nur vorhandene).
    public func categories() -> [CategoryTotal] {
        FileCategory.allCases.compactMap { category in
            guard let files = categoryFiles[category], files > 0 else { return nil }
            return CategoryTotal(category: category, size: categorySizes[category] ?? 0, files: files)
        }
        .sorted { $0.size != $1.size ? $0.size > $1.size : $0.category.rawValue < $1.category.rawValue }
    }
}

public enum StorageAnalysis {
    /// Größte Dateien ab der Schwelle, absteigend.
    public static func largest(_ files: [ScannedFile], minimum: Int64, limit: Int = 200) -> [ScannedFile] {
        Array(files.filter { $0.size >= minimum }.sorted { $0.size != $1.size ? $0.size > $1.size : $0.path < $1.path }.prefix(limit))
    }
}

// MARK: - Duplikate

/// Gruppe inhaltsgleicher Dateien (gleiche Größe und gleiche SHA-256-Prüfsumme).
public struct DuplicateGroup: Sendable, Equatable, Identifiable {
    public var id: String { hash }
    public var hash: String
    /// Logische Größe jeder Kopie.
    public var size: Int64
    public var files: [ScannedFile]
    /// Pfade, deren Daten laut Dateisystem mit anderen Dateien geteilt sein können (APFS-Klon).
    public var mayShareBlocks: Set<String>

    public init(hash: String, size: Int64, files: [ScannedFile], mayShareBlocks: Set<String> = []) {
        self.hash = hash
        self.size = size
        self.files = files
        self.mayShareBlocks = mayShareBlocks
    }

    /// Höchstens freizugebender Platz, wenn nur eine Kopie bleibt. Bei APFS-Klonen ist es weniger.
    public var reclaimable: Int64 { size * Int64(max(0, files.count - 1)) }
}

public enum DuplicateFinder {
    /// Kandidaten: Dateien gleicher logischer Größe ab `minimumSize`. Pakete sind ausgenommen (ein Paket ist ein Ordner);
    /// harte Links (gleiches Gerät und gleicher Inode) zählen nur einmal – sie belegen den Platz ohnehin nur einmal.
    public static func candidates(_ files: [ScannedFile], minimumSize: Int64) -> [[ScannedFile]] {
        var bySize: [Int64: [ScannedFile]] = [:]
        for file in files where !file.isPackage && file.logicalSize >= max(1, minimumSize) {
            bySize[file.logicalSize, default: []].append(file)
        }
        var result: [[ScannedFile]] = []
        for (_, group) in bySize where group.count > 1 {
            var seen = Set<String>()
            var unique: [ScannedFile] = []
            for file in group.sorted(by: { $0.path < $1.path }) {
                let identity = file.inode == 0 ? "path:\(file.path)" : "\(file.device):\(file.inode)"
                if seen.insert(identity).inserted { unique.append(file) }
            }
            if unique.count > 1 { result.append(unique) }
        }
        return result.sorted { ($0.first?.logicalSize ?? 0) > ($1.first?.logicalSize ?? 0) }
    }

    /// Bildet Gruppen aus Prüfsummen (`path → hash`). Dateien ohne Prüfsumme (nicht lesbar) fallen heraus.
    public static func groups(candidates: [[ScannedFile]], hashes: [String: String],
                              mayShareBlocks: Set<String> = []) -> [DuplicateGroup] {
        var result: [DuplicateGroup] = []
        for group in candidates {
            var byHash: [String: [ScannedFile]] = [:]
            for file in group {
                if let hash = hashes[file.path] { byHash[hash, default: []].append(file) }
            }
            for (hash, members) in byHash where members.count > 1 {
                let sorted = members.sorted { $0.path < $1.path }
                let shared = Set(sorted.map(\.path).filter { mayShareBlocks.contains($0) })
                result.append(DuplicateGroup(hash: hash, size: sorted[0].logicalSize, files: sorted, mayShareBlocks: shared))
            }
        }
        return result.sorted { $0.reclaimable != $1.reclaimable ? $0.reclaimable > $1.reclaimable : $0.hash < $1.hash }
    }

    /// Entfernt Dateien (z. B. nach dem Verschieben in den Papierkorb); Gruppen mit weniger als zwei Dateien entfallen.
    public static func removing(_ paths: Set<String>, from groups: [DuplicateGroup]) -> [DuplicateGroup] {
        groups.compactMap { group in
            var copy = group
            copy.files.removeAll { paths.contains($0.path) }
            copy.mayShareBlocks.subtract(paths)
            return copy.files.count > 1 ? copy : nil
        }
    }

    /// Gruppen, in denen alle Kopien ausgewählt sind (dann bliebe keine Kopie außerhalb des Papierkorbs).
    public static func fullySelected(_ groups: [DuplicateGroup], selection: Set<String>) -> [DuplicateGroup] {
        groups.filter { group in group.files.allSatisfy { selection.contains($0.path) } }
    }
}

/// Ergebnis einer Analyse.
public struct StorageScanResult: Sendable {
    public var rootPath: String
    public var totalSize: Int64
    public var fileCount: Int
    public var folderCount: Int
    /// Einträge, die macOS nicht lesen ließ (Datenschutz, fehlende Rechte) – nicht geschätzt, nur gezählt.
    public var unreadableCount: Int
    public var unreadableSamples: [String]
    /// Dateien ab der Behalteschwelle, absteigend nach Größe.
    public var files: [ScannedFile]
    public var folders: [FolderTotal]
    public var categories: [CategoryTotal]
    public var duplicates: [DuplicateGroup]
    public var duplicatesChecked: Bool
    public var cancelled: Bool
    public var finished: Date
    /// Andere Volumes unterhalb des Ordners wurden nicht mitgezählt.
    public var skippedOtherVolumes: Int

    public init(rootPath: String, totalSize: Int64, fileCount: Int, folderCount: Int, unreadableCount: Int,
                unreadableSamples: [String], files: [ScannedFile], folders: [FolderTotal], categories: [CategoryTotal],
                duplicates: [DuplicateGroup], duplicatesChecked: Bool, cancelled: Bool, finished: Date, skippedOtherVolumes: Int) {
        self.rootPath = rootPath
        self.totalSize = totalSize
        self.fileCount = fileCount
        self.folderCount = folderCount
        self.unreadableCount = unreadableCount
        self.unreadableSamples = unreadableSamples
        self.files = files
        self.folders = folders
        self.categories = categories
        self.duplicates = duplicates
        self.duplicatesChecked = duplicatesChecked
        self.cancelled = cancelled
        self.finished = finished
        self.skippedOtherVolumes = skippedOtherVolumes
    }

    /// Entfernt Dateien aus dem Ergebnis (nach dem Verschieben in den Papierkorb). Summen bleiben die der Messung.
    public mutating func remove(paths: Set<String>) {
        files.removeAll { paths.contains($0.path) }
        duplicates = DuplicateFinder.removing(paths, from: duplicates)
    }
}

// MARK: - SSD-Gesundheit (NVMe SMART / Health Information Log, Seite 02h)

/// Kritische Warnungen laut NVMe-Spezifikation (Byte 0 des SMART-Protokolls).
public enum NVMeCriticalWarning: Int, CaseIterable, Sendable {
    case spareBelowThreshold = 0
    case temperature = 1
    case reliabilityDegraded = 2
    case readOnly = 3
    case volatileBackupFailed = 4
    case persistentMemoryReadOnly = 5
}

public struct NVMeHealth: Sendable, Equatable {
    public var criticalWarning: UInt8
    /// Gesamttemperatur des Controllers in °C (`nil`, wenn das Laufwerk keine meldet).
    public var temperatureCelsius: Double?
    /// Verbleibende Reserve in % und die Schwelle, ab der das Laufwerk warnt.
    public var availableSpare: Int
    public var availableSpareThreshold: Int
    /// Abnutzung laut Hersteller in % (kann über 100 steigen).
    public var percentageUsed: Int
    /// Gelesene/geschriebene Daten in Bytes (Dateneinheiten × 512 000).
    public var bytesRead: Double
    public var bytesWritten: Double
    public var powerCycles: Double
    public var powerOnHours: Double
    public var unsafeShutdowns: Double
    public var mediaErrors: Double
    public var errorLogEntries: Double

    public init(criticalWarning: UInt8, temperatureCelsius: Double?, availableSpare: Int, availableSpareThreshold: Int,
                percentageUsed: Int, bytesRead: Double, bytesWritten: Double, powerCycles: Double, powerOnHours: Double,
                unsafeShutdowns: Double, mediaErrors: Double, errorLogEntries: Double) {
        self.criticalWarning = criticalWarning
        self.temperatureCelsius = temperatureCelsius
        self.availableSpare = availableSpare
        self.availableSpareThreshold = availableSpareThreshold
        self.percentageUsed = percentageUsed
        self.bytesRead = bytesRead
        self.bytesWritten = bytesWritten
        self.powerCycles = powerCycles
        self.powerOnHours = powerOnHours
        self.unsafeShutdowns = unsafeShutdowns
        self.mediaErrors = mediaErrors
        self.errorLogEntries = errorLogEntries
    }

    /// Gesetzte Warnbits.
    public var warnings: [NVMeCriticalWarning] {
        NVMeCriticalWarning.allCases.filter { criticalWarning & (1 << UInt8($0.rawValue)) != 0 }
    }

    /// Werte innerhalb der Grenzen der Spezifikation.
    public var isPlausible: Bool {
        (0...100).contains(availableSpare) && (0...100).contains(availableSpareThreshold) && (0...255).contains(percentageUsed)
            && (temperatureCelsius.map { (-20...130).contains($0) } ?? true) && bytesRead >= 0 && bytesWritten >= 0
    }

    /// Dekodiert das 512-Byte-Protokoll nach NVMe-Spezifikation (Little Endian). Ein Puffer nur aus Nullen gilt als
    /// „keine Daten“ (`nil`), ebenso unplausible Inhalte.
    public static func decode(_ bytes: [UInt8]) -> NVMeHealth? {
        guard bytes.count >= 192, bytes.contains(where: { $0 != 0 }) else { return nil }
        let kelvin = Int(bytes[1]) | (Int(bytes[2]) << 8)
        var celsius: Double?
        if kelvin > 0 {
            let value = Double(kelvin) - 273.15
            celsius = (-20...130).contains(value) ? value : nil
        }
        let health = NVMeHealth(
            criticalWarning: bytes[0],
            temperatureCelsius: celsius,
            availableSpare: Int(bytes[3]),
            availableSpareThreshold: Int(bytes[4]),
            percentageUsed: Int(bytes[5]),
            bytesRead: uint128(bytes, at: 32) * 512_000,
            bytesWritten: uint128(bytes, at: 48) * 512_000,
            powerCycles: uint128(bytes, at: 112),
            powerOnHours: uint128(bytes, at: 128),
            unsafeShutdowns: uint128(bytes, at: 144),
            mediaErrors: uint128(bytes, at: 160),
            errorLogEntries: uint128(bytes, at: 176))
        return health.isPlausible ? health : nil
    }

    /// 128-Bit-Zähler (Little Endian) als Gleitkommazahl.
    public static func uint128(_ bytes: [UInt8], at offset: Int) -> Double {
        guard offset + 16 <= bytes.count else { return 0 }
        var value = 0.0
        for index in stride(from: offset + 15, through: offset, by: -1) {
            value = value * 256 + Double(bytes[index])
        }
        return value
    }
}

/// Ein NVMe-Laufwerk mit SMART-Schnittstelle. Die Seriennummer wird bewusst nicht gelesen.
public struct NVMeDrive: Sendable, Identifiable {
    public var id: Int { index }
    public var index: Int
    public var model: String?
    public var firmware: String?
    public var health: Reading<NVMeHealth>

    public init(index: Int, model: String?, firmware: String?, health: Reading<NVMeHealth>) {
        self.index = index
        self.model = model
        self.firmware = firmware
        self.health = health
    }
}

// MARK: - Bereinigungsorte (nur Anzeige – nie automatisch löschen)

public enum CleanupKind: String, CaseIterable, Sendable {
    case downloads, caches, xcodeDerivedData, iosBackups, trash

    /// Pfad relativ zum Benutzerordner.
    public var relativePath: String {
        switch self {
        case .downloads: return "Downloads"
        case .caches: return "Library/Caches"
        case .xcodeDerivedData: return "Library/Developer/Xcode/DerivedData"
        case .iosBackups: return "Library/Application Support/MobileSync/Backup"
        case .trash: return ".Trash"
        }
    }
}

public enum CleanupState: Sendable, Equatable {
    /// Gemessen; `partial` = einzelne Einträge waren nicht lesbar und fehlen in der Summe.
    case measured(bytes: Int64, items: Int, partial: Bool)
    case notPresent
    /// macOS verweigert das Lesen (Datenschutz – z. B. Festplattenvollzugriff nötig).
    case notReadable
}

public struct CleanupMeasurement: Sendable, Equatable, Identifiable {
    public var id: CleanupKind { kind }
    public var kind: CleanupKind
    public var path: String
    public var state: CleanupState

    public init(kind: CleanupKind, path: String, state: CleanupState) {
        self.kind = kind
        self.path = path
        self.state = state
    }
}
