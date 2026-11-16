import Foundation
import AppKit
import PanoraCore

// =============================================================================================
// Modellbibliothek: findet installierte MLX-Modelle in allen Modellordnern (auch auf externen SSDs),
// merkt sich Modelle auf getrennten Laufwerken („Laufwerk fehlt“) und ergänzt Ollama-Modelle.
// =============================================================================================

struct InstalledModel: Identifiable, Equatable {
    var spec: ModelSpec
    var directory: String
    var folder: String?
    var available: Bool
    var unavailableReason: String?
    var catalog: CatalogEntry?
    var installedAt: Date?

    var id: String { spec.id }
}

/// Merkzettel im Modellordner (von Panora beim Download geschrieben).
struct ModelManifest: Codable {
    var repo: String
    var license: String?
    var downloadedAt: Date
    var totalBytes: Int64
}

@MainActor
final class ModelLibrary: ObservableObject {
    @Published private(set) var models: [InstalledModel] = []
    @Published private(set) var missingDirectories: [String] = []
    @Published private(set) var ollamaRunning = false
    @Published private(set) var scanning = false
    @Published private(set) var lastScan: Date?

    private let settings: AppSettings
    private var known: [String: KnownModel] = [:]
    private let indexURL: URL
    var demoMode = false

    struct KnownModel: Codable {
        var spec: ModelSpec
        var directory: String
        var folder: String
    }

    init(settings: AppSettings, persist: Bool = true) {
        self.settings = settings
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        indexURL = base.appendingPathComponent("Panora/bibliothek.json")
        if persist, let data = try? Data(contentsOf: indexURL), let list = try? JSONDecoder().decode([KnownModel].self, from: data) {
            for k in list { known[k.spec.id] = k }
        }
    }

    var mlxModels: [InstalledModel] { models.filter { $0.spec.backend == .mlx } }
    var availableModels: [InstalledModel] { models.filter(\.available) }

    func model(_ id: String?) -> InstalledModel? {
        guard let id else { return nil }
        return models.first { $0.id == id }
    }

    func spec(_ id: String?) -> ModelSpec? { model(id)?.spec }

    func isInstalled(repo: String) -> Bool {
        models.contains { $0.spec.backend == .mlx && $0.spec.repo.caseInsensitiveCompare(repo) == .orderedSame }
    }

    func candidates(measured: [String: Double]) -> [ModelCandidate] {
        models.map { ModelCandidate(spec: $0.spec, available: $0.available, unavailableReason: $0.unavailableReason,
                                    measuredTokensPerSecond: measured[$0.id]) }
    }

    /// Ordner durchsuchen (im Hintergrund) und Ollama abfragen.
    func refresh() async {
        guard !demoMode else { return }
        scanning = true
        let dirs = settings.modelDirectories
        let scanned = await Task.detached(priority: .userInitiated) { ModelLibrary.scan(directories: dirs) }.value
        var result: [InstalledModel] = []
        var missing: [String] = []
        for dir in dirs where !FileManager.default.fileExists(atPath: dir) { missing.append(dir) }
        for item in scanned {
            result.append(item)
            known[item.id] = KnownModel(spec: item.spec, directory: item.directory, folder: item.folder ?? "")
        }
        // Modelle auf getrennten Laufwerken weiter anzeigen – als nicht verfügbar
        for (id, k) in known where !result.contains(where: { $0.id == id }) {
            if missing.contains(k.directory) {
                result.append(InstalledModel(spec: k.spec, directory: k.directory, folder: k.folder, available: false,
                                             unavailableReason: "Laufwerk nicht verbunden (\(ModelLibrary.volumeName(of: k.directory)))",
                                             catalog: ModelCatalog.entry(for: k.spec.repo), installedAt: nil))
            } else if !settings.modelDirectories.contains(k.directory) {
                known[id] = nil
            } else {
                known[id] = nil   // gelöscht
            }
        }
        // Ollama
        if settings.ollamaEnabled {
            let client = OllamaClient(urlString: settings.ollamaURL)
            if await client.ping(), let list = try? await client.models() {
                ollamaRunning = true
                for m in list {
                    result.append(InstalledModel(spec: OllamaClient.spec(for: m), directory: "Ollama", folder: nil, available: true,
                                                 unavailableReason: nil, catalog: nil, installedAt: nil))
                }
            } else {
                ollamaRunning = false
            }
        } else {
            ollamaRunning = false
        }
        models = result.sorted { ($0.spec.family, $0.spec.displayName) < ($1.spec.family, $1.spec.displayName) }
        missingDirectories = missing
        lastScan = Date()
        scanning = false
        saveIndex()
    }

    private func saveIndex() {
        guard !demoMode else { return }
        let list = Array(known.values)
        if let data = try? JSONEncoder().encode(list) {
            try? FileManager.default.createDirectory(at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    nonisolated static func volumeName(of path: String) -> String {
        let parts = path.split(separator: "/")
        if parts.count >= 2, parts[0] == "Volumes" { return String(parts[1]) }
        return path
    }

    /// Sucht Modellordner (Tiefe 1 und 2, z. B. LM-Studio-Struktur „org/name“).
    nonisolated static func scan(directories: [String]) -> [InstalledModel] {
        var result: [InstalledModel] = []
        let fm = FileManager.default
        for dir in directories {
            guard let level1 = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in level1 where !name.hasPrefix(".") && !name.hasSuffix(".partial") {
                let path = (dir as NSString).appendingPathComponent(name)
                if let model = inspect(folder: path, directory: dir) {
                    result.append(model)
                } else if let level2 = try? fm.contentsOfDirectory(atPath: path) {
                    for sub in level2 where !sub.hasPrefix(".") {
                        let subPath = (path as NSString).appendingPathComponent(sub)
                        if let model = inspect(folder: subPath, directory: dir, repoHint: "\(name)/\(sub)") { result.append(model) }
                    }
                }
            }
        }
        // Doppelte (gleiches Repository in zwei Ordnern): das erste gewinnt
        var seen: Set<String> = []
        return result.filter { seen.insert($0.id).inserted }
    }

    nonisolated static func inspect(folder: String, directory: String, repoHint: String? = nil) -> InstalledModel? {
        let fm = FileManager.default
        let configURL = URL(fileURLWithPath: folder).appendingPathComponent("config.json")
        guard let configData = try? Data(contentsOf: configURL),
              let files = try? fm.contentsOfDirectory(atPath: folder) else { return nil }
        let weights = files.filter { $0.hasSuffix(".safetensors") }
        guard !weights.isEmpty else { return nil }
        var size: Int64 = 0
        for f in weights {
            let attrs = try? fm.attributesOfItem(atPath: (folder as NSString).appendingPathComponent(f))
            size += (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        }
        var manifest: ModelManifest?
        if let data = try? Data(contentsOf: URL(fileURLWithPath: folder).appendingPathComponent("panora-model.json")) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            manifest = try? decoder.decode(ModelManifest.self, from: data)
        }
        let folderName = (folder as NSString).lastPathComponent
        let repo = manifest?.repo ?? HuggingFaceAPI.repo(fromFolderName: folderName) ?? repoHint ?? folderName
        let config = ModelConfigInfo.parse(configData)
        let catalog = ModelCatalog.entry(for: repo)
        var parsed = ModelNameParser.parse(repo)
        if parsed.bits == nil { parsed.bits = config.quantBits }
        let context = config.contextLength ?? catalog?.spec.contextLength ?? 32_768
        var spec: ModelSpec
        if let catalog {
            spec = catalog.spec
            spec.sizeBytes = size
            spec.contextLength = context
            spec.bits = config.quantBits ?? catalog.spec.bits
        } else {
            let name = repo.split(separator: "/").last.map(String.init) ?? repo
            spec = ModelSpec(id: ModelSpec.mlxID(repo), backend: .mlx, repo: repo, displayName: prettyName(name),
                             family: parsed.family, parametersB: parsed.parametersB, activeParametersB: parsed.activeParametersB,
                             bits: parsed.bits, sizeBytes: size, contextLength: context,
                             capabilities: ModelNameParser.estimatedCapabilities(for: parsed, contextLength: context),
                             skills: ModelNameParser.estimatedSkills(for: parsed),
                             license: LicenseInfo.fromIdentifier(manifest?.license),
                             summary: "Eigenes Modell – Fähigkeiten aus Name und Größe geschätzt.")
        }
        spec.kvBytesPerToken = config.kvBytesPerToken
        spec.localPath = folder
        if config.hasVision && !spec.capabilities.contains(.vision) { spec.capabilities.insert(.vision) }
        let created = (try? fm.attributesOfItem(atPath: folder))?[.creationDate] as? Date
        return InstalledModel(spec: spec, directory: directory, folder: folder, available: true, unavailableReason: nil,
                              catalog: catalog, installedAt: manifest?.downloadedAt ?? created)
    }

    nonisolated static func prettyName(_ raw: String) -> String {
        var name = raw
        for suffix in ["-4bit", "-8bit", "-6bit", "-3bit", "-5bit", "-MLX", "-mlx", "-bf16", "-fp16", "-DWQ", "-dwq"] {
            name = name.replacingOccurrences(of: suffix, with: "")
        }
        return name.replacingOccurrences(of: "-", with: " ")
    }

    /// Modell in den Papierkorb legen.
    func remove(_ model: InstalledModel) throws {
        guard let folder = model.folder, model.spec.backend == .mlx else { return }
        var resulting: NSURL?
        try FileManager.default.trashItem(at: URL(fileURLWithPath: folder), resultingItemURL: &resulting)
        known[model.id] = nil
        models.removeAll { $0.id == model.id }
        saveIndex()
    }

    // MARK: Fotomodus

    func installDemo(_ items: [InstalledModel]) {
        demoMode = true
        models = items
        ollamaRunning = false
        missingDirectories = []
    }
}
