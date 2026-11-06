import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

// =============================================================================================
// Duplikaterkennung (ohne Oberfläche, vollständig testbar)
//
// Stufen: 1) Dateien erfassen  2) nach Größe gruppieren (Einzelgrößen scheiden aus)
//         3) Fingerabdruck aus Anfang + Ende (je 64 KB) für Gruppen gleicher Größe
//         4) vollständige SHA-256-Prüfsumme nur für Dateien mit gleichem Fingerabdruck
//         5) Dateien mit gleicher SHA-256 bilden eine Duplikatgruppe.
// Gleiche Namen oder gleiche Größe allein machen nie ein Duplikat. Ähnliche Bilder (Wahrnehmungs-Hash)
// werden getrennt geführt und nie als identisch behandelt.
// =============================================================================================

/// Eine Datei, die untersucht wird.
public struct DuplicateFile: Identifiable, Hashable, Sendable {
    public var id: String { entry.id }
    public let entry: DeviceEntry
    /// Ordnerpfad (ohne Dateinamen).
    public let path: [String]
    public let storageName: String

    public init(entry: DeviceEntry, path: [String], storageName: String) {
        self.entry = entry
        self.path = path
        self.storageName = storageName
    }

    public var displayPath: String { ([storageName] + path).joined(separator: " › ") }
}

public enum DuplicateKind: String, Sendable {
    /// Inhalt byte-genau identisch (SHA-256).
    case identical
    /// Bilder sehen gleich bzw. sehr ähnlich aus (Wahrnehmungs-Hash) – nicht identisch.
    case similar
}

/// Eine Gruppe zusammengehöriger Dateien.
public struct DuplicateGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: DuplicateKind
    public var files: [DuplicateFile]
    /// SHA-256 (nur bei identischen Gruppen).
    public let checksum: String?
    /// Vorschlag zum Behalten (nur eine Empfehlung).
    public var suggestedKeep: String
    public var suggestionReason: String

    public init(id: String, kind: DuplicateKind, files: [DuplicateFile], checksum: String?) {
        self.id = id
        self.kind = kind
        self.files = files
        self.checksum = checksum
        let s = KeepSuggestion.suggest(files, preferResolution: kind == .similar)
        self.suggestedKeep = s.id
        self.suggestionReason = s.reason
    }

    /// Speicher, der frei würde, wenn nur eine Datei bleibt.
    public var reclaimableBytes: UInt64 {
        let sizes = files.map(\.entry.size)
        guard let maxSize = sizes.max() else { return 0 }
        return sizes.reduce(0, +) - (kind == .identical ? sizes[0] : maxSize)
    }

    public var redundantCount: Int { max(0, files.count - 1) }
}

/// Fortschritt eines Durchlaufs.
public struct DuplicateScanProgress: Equatable, Sendable {
    public enum Phase: String, Sendable {
        case collecting, grouping, fingerprint, hashing, similar, done
    }
    public var phase: Phase = .collecting
    public var filesFound = 0
    public var foldersScanned = 0
    public var candidates = 0
    public var examined = 0
    public var bytesRead: UInt64 = 0
    public var groupsFound = 0
    public var currentLocation = ""
    /// Dateien, die das Telefon nicht lesen ließ (werden nie als Duplikat gewertet).
    public var unreadable = 0

    public init() {}

    /// Gesamtfortschritt 0…1 (Phasen gewichtet).
    public var fraction: Double {
        let part = candidates > 0 ? min(1, Double(examined) / Double(candidates)) : 0
        switch phase {
        case .collecting: return 0.05
        case .grouping: return 0.15
        case .fingerprint: return 0.15 + 0.35 * part
        case .hashing: return 0.5 + 0.4 * part
        case .similar: return 0.9 + 0.1 * part
        case .done: return 1
        }
    }

    public var remaining: Int { max(0, candidates - examined) }
}

/// Reine Gruppierungslogik.
public enum DuplicateGrouping {
    /// Gruppen gleicher Größe mit mindestens zwei Dateien (leere Dateien ausgenommen).
    public static func sizeGroups(_ files: [DuplicateFile]) -> [[DuplicateFile]] {
        var map: [UInt64: [DuplicateFile]] = [:]
        for f in files where !f.entry.isFolder && f.entry.size > 0 {
            map[f.entry.size, default: []].append(f)
        }
        return map.values.filter { $0.count > 1 }.sorted { $0[0].entry.size > $1[0].entry.size }
    }

    /// Teilt eine Menge nach Schlüssel; nur Teilgruppen mit mindestens zwei Elementen bleiben.
    public static func split<T>(_ items: [T], key: (T) -> String?) -> [[T]] {
        var map: [String: [T]] = [:]
        var order: [String] = []
        for item in items {
            guard let k = key(item) else { continue }
            if map[k] == nil { order.append(k) }
            map[k, default: []].append(item)
        }
        return order.compactMap { map[$0] }.filter { $0.count > 1 }
    }
}

/// Empfehlung, welche Datei behalten werden sollte.
public enum KeepSuggestion {
    static let copyMarkers = ["kopie", "copy", "(1)", "(2)", "(3)", "_1.", "-1.", " 2.", " 3.", "duplicate", "duplikat"]

    public static func score(_ f: DuplicateFile, preferResolution: Bool) -> (score: Int, reasons: [String]) {
        var score = 0
        var reasons: [String] = []
        let lowerPath = f.path.map { $0.lowercased() }
        let name = f.entry.name.lowercased()
        if lowerPath.first == "dcim" || lowerPath.contains("camera") {
            score += 40; reasons.append("Kameraordner")
        }
        if !copyMarkers.contains(where: { name.contains($0) }) {
            score += 25; reasons.append("ursprünglicher Name")
        }
        if lowerPath.contains(where: { $0.contains("whatsapp") || $0.contains("telegram") || $0 == "download" || $0 == "downloads" || $0.contains("sent") }) {
            score -= 15
        }
        if f.entry.created != nil { score += 4 }
        if f.entry.modified != nil { score += 2 }
        if preferResolution {
            let pixels = Int(f.entry.imageWidth) * Int(f.entry.imageHeight)
            if pixels > 0 { score += min(60, pixels / 200_000) }
            score += Int(min(UInt64(30), f.entry.size / 500_000))
        }
        return (score, reasons)
    }

    /// Wählt eine Datei: höchste Wertung; bei Gleichstand die älteste, dann der kürzeste Pfad.
    public static func suggest(_ files: [DuplicateFile], preferResolution: Bool) -> (id: String, reason: String) {
        guard !files.isEmpty else { return ("", "") }
        let scored = files.map { ($0, score($0, preferResolution: preferResolution)) }
        let best = scored.max { a, b in
            if a.1.score != b.1.score { return a.1.score < b.1.score }
            let da = a.0.entry.bestDate ?? .distantFuture, db = b.0.entry.bestDate ?? .distantFuture
            if da != db { return da > db }
            return a.0.displayPath.count + a.0.entry.name.count > b.0.displayPath.count + b.0.entry.name.count
        }!
        var reasons = best.1.reasons
        if preferResolution {
            reasons.insert(best.0.entry.imageWidth > 0 ? "höchste Auflösung" : "größte Datei", at: 0)
        } else if reasons.isEmpty {
            reasons.append("älteste Datei")
        }
        return (best.0.id, reasons.joined(separator: ", "))
    }
}

/// Wahrnehmungs-Hash (Differenz-Hash, 64 Bit) für ähnliche Bilder.
public enum PerceptualHash {
    /// `gray` = 9 × 8 Graustufen (Zeilen von oben), Ergebnis: je Zeile 8 Vergleiche „links heller als rechts“.
    public static func dHash(gray9x8 gray: [UInt8]) -> UInt64? {
        guard gray.count == 72 else { return nil }
        var hash: UInt64 = 0
        var bit: UInt64 = 0
        for row in 0..<8 {
            for col in 0..<8 {
                if gray[row * 9 + col] > gray[row * 9 + col + 1] { hash |= (1 << bit) }
                bit += 1
            }
        }
        return hash
    }

    public static func distance(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }

    /// Gruppiert Elemente mit Abstand ≤ `threshold` (Vereinigungssuche); Einzelgänger fallen weg.
    /// Fast einfarbige Bilder (Hash 0 bzw. alle Bits) werden nicht gruppiert – zu viele Fehltreffer.
    public static func cluster<ID: Hashable>(_ items: [(id: ID, hash: UInt64)], threshold: Int) -> [[ID]] {
        let usable = items.filter { $0.hash != 0 && $0.hash != UInt64.max && $0.hash.nonzeroBitCount > 3 && $0.hash.nonzeroBitCount < 61 }
        var parent = Array(0..<usable.count)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        for i in 0..<usable.count {
            for j in (i + 1)..<usable.count where distance(usable[i].hash, usable[j].hash) <= threshold {
                let a = find(i), b = find(j)
                if a != b { parent[a] = b }
            }
        }
        var groups: [Int: [ID]] = [:]
        for i in 0..<usable.count { groups[find(i), default: []].append(usable[i].id) }
        return groups.values.filter { $0.count > 1 }.map { $0 }
    }
}

/// Liest Dateiinhalte für die Prüfsummen. Die App setzt das mit MTP um, die Tests mit Speicherdaten.
public protocol DuplicateContentReader: Sendable {
    var supportsRanges: Bool { get }
    /// Abschnitt lesen (nur wenn `supportsRanges`).
    func read(_ file: DuplicateFile, offset: UInt64, length: UInt32) async throws -> Data
    /// Ganze Datei stückweise lesen.
    func stream(_ file: DuplicateFile, chunk: @escaping @Sendable (Data) -> Void) async throws
    /// Bricht dieser Fehler die ganze Suche ab (Trennung, Abbruch)? Sonst wird nur die Datei übersprungen.
    func isFatal(_ error: Error) -> Bool
}

extension DuplicateContentReader {
    public func isFatal(_ error: Error) -> Bool { true }
}

/// Findet byte-genau identische Dateien mit möglichst wenig Lesezugriffen.
public struct ExactDuplicateFinder: Sendable {
    public var edgeSize: UInt32 = 64 * 1024
    public var segmentSize: UInt32 = 16 * 1024 * 1024

    public init() {}

    public func find(in files: [DuplicateFile], reader: DuplicateContentReader,
                     progress: @escaping @Sendable (DuplicateScanProgress) -> Void,
                     isCancelled: @escaping @Sendable () -> Bool) async throws -> [DuplicateGroup] {
        var p = DuplicateScanProgress()
        p.phase = .grouping
        p.filesFound = files.count
        progress(p)
        let bySize = DuplicateGrouping.sizeGroups(files)
        var candidates = bySize.flatMap { $0 }
        p.candidates = candidates.count
        p.phase = .fingerprint
        progress(p)

        // Stufe 3: Anfang + Ende (große Dateien) – kleine Dateien werden dabei vollständig gelesen.
        var fingerprint: [String: String] = [:]
        var fullHashKnown: [String: String] = [:]
        for group in bySize {
            for file in group {
                if isCancelled() { throw CancellationError() }
                let size = file.entry.size
                do {
                    if size <= UInt64(edgeSize) * 2 {
                        let data: Data
                        if reader.supportsRanges {
                            data = try await reader.read(file, offset: 0, length: UInt32(size))
                        } else {
                            data = try await collect(file, reader: reader)
                        }
                        p.bytesRead += UInt64(data.count)
                        let h = Self.sha256Hex(data)
                        fingerprint[file.id] = h
                        if UInt64(data.count) == size { fullHashKnown[file.id] = h }
                    } else if reader.supportsRanges {
                        let head = try await reader.read(file, offset: 0, length: edgeSize)
                        let tail = try await reader.read(file, offset: size - UInt64(edgeSize), length: edgeSize)
                        p.bytesRead += UInt64(head.count + tail.count)
                        var d = head
                        d.append(tail)
                        fingerprint[file.id] = "\(size)-" + Self.sha256Hex(d)
                    } else {
                        fingerprint[file.id] = "\(size)" // ohne Teillesen: direkt vollständig prüfen
                    }
                } catch {
                    if error is CancellationError || reader.isFatal(error) { throw error }
                    fingerprint[file.id] = nil
                    p.unreadable += 1
                }
                p.examined += 1
                p.currentLocation = file.displayPath
                progress(p)
            }
        }

        // Stufe 4: vollständige Prüfsumme nur für Dateien mit gleichem Fingerabdruck.
        let fingerprintGroups = bySize.flatMap { group in DuplicateGrouping.split(group) { fingerprint[$0.id] } }
        candidates = fingerprintGroups.flatMap { $0 }.filter { fullHashKnown[$0.id] == nil }
        p.phase = .hashing
        p.examined = 0
        p.candidates = candidates.count
        progress(p)
        var fullHash = fullHashKnown
        for file in candidates {
            if isCancelled() { throw CancellationError() }
            let hasher = HashBox()
            do {
                try await reader.stream(file) { chunk in hasher.update(chunk) }
                let (hex, count) = hasher.finish()
                p.bytesRead += count
                // Größe muss stimmen, sonst ist die Lesung unvollständig – Datei dann nicht als Duplikat werten.
                if count == file.entry.size { fullHash[file.id] = hex } else { p.unreadable += 1 }
            } catch {
                if error is CancellationError || reader.isFatal(error) { throw error }
                p.unreadable += 1
            }
            p.examined += 1
            p.currentLocation = file.displayPath
            progress(p)
        }

        // Stufe 5: Gruppen gleicher SHA-256.
        var groups: [DuplicateGroup] = []
        for fpGroup in fingerprintGroups {
            for same in DuplicateGrouping.split(fpGroup, key: { fullHash[$0.id] }) {
                let checksum = fullHash[same[0].id]!
                groups.append(DuplicateGroup(id: "sha-" + checksum, kind: .identical, files: same, checksum: checksum))
            }
        }
        groups.sort { $0.reclaimableBytes > $1.reclaimableBytes }
        p.groupsFound = groups.count
        p.phase = .done
        progress(p)
        return groups
    }

    private func collect(_ file: DuplicateFile, reader: DuplicateContentReader) async throws -> Data {
        let box = DataBox()
        try await reader.stream(file) { box.append($0) }
        return box.data
    }

    public static func sha256Hex(_ data: Data) -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        return String(data.hashValue)
        #endif
    }
}

/// Fortlaufende SHA-256 (threadsicher, für Datenstücke aus der Gerätewarteschlange).
public final class HashBox: @unchecked Sendable {
    private let lock = NSLock()
    #if canImport(CryptoKit)
    private var hasher = SHA256()
    #endif
    private var count: UInt64 = 0

    public init() {}

    public func update(_ data: Data) {
        lock.lock()
        #if canImport(CryptoKit)
        hasher.update(data: data)
        #endif
        count += UInt64(data.count)
        lock.unlock()
    }

    public func finish() -> (String, UInt64) {
        lock.lock(); defer { lock.unlock() }
        #if canImport(CryptoKit)
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), count)
        #else
        return ("", count)
        #endif
    }
}

final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()
    var data: Data { lock.lock(); defer { lock.unlock() }; return storage }
    func append(_ d: Data) { lock.lock(); storage.append(d); lock.unlock() }
}

/// Auswahl in einer Gruppe: welche Dateien gelöscht werden sollen.
public enum DuplicateSelection {
    /// Vorschlag übernehmen: alle außer der empfohlenen Datei markieren.
    public static func suggested(for group: DuplicateGroup) -> Set<String> {
        Set(group.files.map(\.id)).subtracting([group.suggestedKeep])
    }

    /// Sicherheitsprüfung: In jeder Gruppe muss mindestens eine Datei erhalten bleiben.
    public static func keepsAtLeastOne(_ marked: Set<String>, in group: DuplicateGroup) -> Bool {
        group.files.contains { !marked.contains($0.id) }
    }
}
