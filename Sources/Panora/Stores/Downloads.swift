import Foundation
import PanoraCore

// =============================================================================================
// Downloads von Hugging Face direkt in den gewählten Modellordner (bevorzugt die externe SSD).
// Fortsetzbar: bereits vollständige Dateien werden übersprungen. Erst nach dem letzten Byte wird der
// Ordner freigeschaltet (…partial → endgültiger Name), damit nie ein halbes Modell geladen wird.
// =============================================================================================

enum DownloadState: Equatable {
    case preparing
    case running
    case finishing
    case done
    case failed(String)
    case cancelled

    var isActive: Bool { self == .preparing || self == .running || self == .finishing }
}

struct DownloadItem: Identifiable, Equatable {
    var id: String { repo }
    var repo: String
    var resolvedRepo: String
    var name: String
    var family: String
    var targetDirectory: String
    var totalBytes: Int64 = 0
    var receivedBytes: Int64 = 0
    var bytesPerSecond: Double = 0
    var currentFile: String = ""
    var state: DownloadState = .preparing
    var license: LicenseInfo?

    var fraction: Double { totalBytes > 0 ? Double(receivedBytes) / Double(totalBytes) : 0 }
}

/// Fortschritt eines laufenden Datei-Downloads (aus dem URLSession-Thread geschrieben).
final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _bytes: Int64 = 0
    var bytes: Int64 {
        get { lock.lock(); defer { lock.unlock() }; return _bytes }
        set { lock.lock(); _bytes = newValue; lock.unlock() }
    }
}

final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let box: ProgressBox
    private var continuation: CheckedContinuation<Void, Error>?
    private var task: URLSessionDownloadTask?
    private var session: URLSession?
    private let lock = NSLock()
    private var finished = false

    init(destination: URL, box: ProgressBox) {
        self.destination = destination
        self.box = box
    }

    func download(_ url: URL) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                lock.lock()
                continuation = cont
                lock.unlock()
                let config = URLSessionConfiguration.default
                config.timeoutIntervalForRequest = 120
                config.timeoutIntervalForResource = 60 * 60 * 24
                let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
                self.session = session
                var request = URLRequest(url: url)
                request.setValue("Panora/0.1 (macOS)", forHTTPHeaderField: "User-Agent")
                let task = session.downloadTask(with: request)
                self.task = task
                task.resume()
            }
        } onCancel: {
            self.task?.cancel()
        }
    }

    private func finish(_ error: Error?) {
        lock.lock()
        guard !finished, let cont = continuation else { lock.unlock(); return }
        finished = true
        continuation = nil
        lock.unlock()
        session?.finishTasksAndInvalidate()
        if let error { cont.resume(throwing: error) } else { cont.resume() }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        box.bytes = totalBytesWritten
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode >= 400 {
            finish(EngineError.unsupported(http.statusCode == 401 || http.statusCode == 403
                                           ? "Zugriff verweigert (Status \(http.statusCode)) – das Modell erfordert eine Freigabe auf Hugging Face."
                                           : "Download fehlgeschlagen (Status \(http.statusCode))."))
            return
        }
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: location, to: destination)
            finish(nil)
        } catch {
            finish(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(error) } else { finish(nil) }
    }
}

@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var items: [DownloadItem] = []

    private let settings: AppSettings
    private let network: NetworkMonitor
    weak var library: ModelLibrary?
    private var tasks: [String: Task<Void, Never>] = [:]
    private var boxes: [String: (box: ProgressBox, base: Int64)] = [:]
    private var timer: Timer?
    private var lastSample: [String: (Date, Int64)] = [:]

    init(settings: AppSettings, network: NetworkMonitor) {
        self.settings = settings
        self.network = network
    }

    var activeCount: Int { items.filter { $0.state.isActive }.count }

    func item(_ repo: String) -> DownloadItem? { items.first { $0.repo == repo } }

    var canDownload: Bool { network.online && !settings.forceOffline }

    func start(repo: String, name: String, family: String, hint: String? = nil) {
        if let existing = item(repo), existing.state.isActive { return }
        items.removeAll { $0.repo == repo }
        var item = DownloadItem(repo: repo, resolvedRepo: repo, name: name, family: family, targetDirectory: settings.downloadDirectory)
        guard canDownload else {
            item.state = .failed("Keine Internetverbindung – Downloads sind offline nicht möglich.")
            items.insert(item, at: 0)
            return
        }
        items.insert(item, at: 0)
        ensureTimer()
        tasks[repo] = Task { [weak self] in
            await self?.run(repo: repo, hint: hint)
        }
    }

    func cancel(_ repo: String) {
        tasks[repo]?.cancel()
        tasks[repo] = nil
        update(repo) { $0.state = .cancelled }
    }

    func dismiss(_ repo: String) {
        items.removeAll { $0.repo == repo && !$0.state.isActive }
    }

    private func update(_ repo: String, _ change: (inout DownloadItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.repo == repo }) else { return }
        change(&items[i])
    }

    private func ensureTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        let now = Date()
        for (repo, entry) in boxes {
            let received = entry.base + entry.box.bytes
            update(repo) { item in
                item.receivedBytes = received
                if let sample = lastSample[repo] {
                    let (t, b) = sample
                    let dt = now.timeIntervalSince(t)
                    if dt > 0.4 {
                        let rate = Double(received - b) / dt
                        item.bytesPerSecond = item.bytesPerSecond == 0 ? rate : item.bytesPerSecond * 0.7 + rate * 0.3
                    }
                }
            }
            lastSample[repo] = (now, received)
        }
        if activeCount == 0 {
            timer?.invalidate()
            timer = nil
        }
    }

    private func fetch(_ url: URL) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Panora/0.1 (macOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func run(repo: String, hint: String?) async {
        do {
            // 1. Repository prüfen – bei Umbenennung über den Suchbegriff die aktuelle Version finden
            var resolved = repo
            var (data, status) = try await fetch(HuggingFaceAPI.infoURL(repo: repo))
            if status == 404 || status == 401, let hint {
                let (searchData, _) = try await fetch(HuggingFaceAPI.searchURL(query: hint, limit: 10))
                let results = try HuggingFaceAPI.parseSearch(searchData)
                guard let match = results.first(where: { $0.id.lowercased().contains(hint.lowercased()) && $0.id.lowercased().contains("4bit") })
                        ?? results.first(where: { $0.id.lowercased().contains(hint.lowercased()) }) else {
                    throw EngineError.unsupported("Auf Hugging Face gibt es „\(repo)“ (noch) nicht als MLX-Version.")
                }
                resolved = match.id
                (data, status) = try await fetch(HuggingFaceAPI.infoURL(repo: resolved))
            }
            guard status == 200 else { throw EngineError.unsupported("Hugging Face antwortet mit Status \(status) für \(resolved).") }
            let info = try HuggingFaceAPI.parseInfo(data)
            if let block = info.license.regionBlock { throw EngineError.unsupported("Installation gesperrt: \(block)") }
            if info.gated { throw EngineError.unsupported("Dieses Modell ist auf Hugging Face zugangsbeschränkt und kann nicht ohne Freigabe geladen werden.") }
            let files = HuggingFaceAPI.filesToDownload(info.files)
            guard files.contains(where: { $0.path.hasSuffix(".safetensors") }) else {
                throw EngineError.unsupported("Keine MLX-Gewichte (.safetensors) in \(resolved) gefunden.")
            }
            let total = files.reduce(Int64(0)) { $0 + $1.size }
            let target = settings.downloadDirectory
            update(repo) { $0.resolvedRepo = resolved; $0.totalBytes = total; $0.license = info.license; $0.state = .running; $0.targetDirectory = target }

            // 2. Platz prüfen
            let targetURL = URL(fileURLWithPath: target)
            do {
                try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
            } catch {
                throw EngineError.unsupported("Der Modellordner \(target) ist nicht erreichbar. Ist das Laufwerk angeschlossen?")
            }
            if let values = try? targetURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
               let free = values.volumeAvailableCapacityForImportantUsage, free < total + 1_000_000_000 {
                throw EngineError.unsupported("Nicht genug Platz: benötigt \(Formatting.bytes(total)), frei \(Formatting.bytes(free)).")
            }

            // 3. Dateien laden
            let finalFolder = targetURL.appendingPathComponent(HuggingFaceAPI.folderName(for: resolved))
            let partial = targetURL.appendingPathComponent(HuggingFaceAPI.folderName(for: resolved) + ".partial")
            try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
            var done: Int64 = 0
            for file in files {
                try Task.checkCancellation()
                let dest = partial.appendingPathComponent(file.path)
                if let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path),
                   let size = (attrs[.size] as? NSNumber)?.int64Value, file.size > 0, size == file.size {
                    done += file.size
                    update(repo) { $0.receivedBytes = done }
                    continue
                }
                update(repo) { $0.currentFile = file.path }
                let box = ProgressBox()
                boxes[repo] = (box, done)
                let downloader = FileDownloader(destination: dest, box: box)
                try await downloader.download(HuggingFaceAPI.fileURL(repo: resolved, path: file.path))
                done += max(file.size, box.bytes)
                boxes[repo] = nil
                update(repo) { $0.receivedBytes = done }
            }

            // 4. Merkzettel schreiben und freischalten
            update(repo) { $0.state = .finishing; $0.currentFile = "" }
            let manifest = ModelManifest(repo: resolved, license: info.license.id, downloadedAt: Date(), totalBytes: total)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: partial.appendingPathComponent("panora-model.json"))
            if FileManager.default.fileExists(atPath: finalFolder.path) {
                var trashed: NSURL?
                try? FileManager.default.trashItem(at: finalFolder, resultingItemURL: &trashed)
            }
            try FileManager.default.moveItem(at: partial, to: finalFolder)
            if !settings.modelDirectories.contains(target) { settings.addModelDirectory(target) }
            update(repo) { $0.state = .done; $0.receivedBytes = total }
            boxes[repo] = nil
            tasks[repo] = nil
            await library?.refresh()
        } catch is CancellationError {
            boxes[repo] = nil
            update(repo) { $0.state = .cancelled }
        } catch {
            boxes[repo] = nil
            tasks[repo] = nil
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if (error as NSError).code == NSURLErrorCancelled {
                update(repo) { $0.state = .cancelled }
            } else {
                update(repo) { $0.state = .failed(message) }
            }
        }
    }
}

/// Suche nach MLX-Modellen auf Hugging Face (nur online).
@MainActor
final class HubSearch: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [HFModelSummary] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var searchedOnce = false

    func search(online: Bool) async {
        guard online else {
            error = "Offline – die Suche auf Hugging Face braucht eine Internetverbindung. Installierte Modelle funktionieren weiter."
            return
        }
        loading = true
        error = nil
        defer { loading = false; searchedOnce = true }
        do {
            var request = URLRequest(url: HuggingFaceAPI.searchURL(query: query, limit: 60))
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                error = "Hugging Face antwortet mit Status \(http.statusCode)."
                return
            }
            let all = try HuggingFaceAPI.parseSearch(data)
            // Nur Sprachmodelle (keine Bild-, Audio- oder Embedding-Modelle)
            results = all.filter { s in
                let tag = s.pipelineTag ?? "text-generation"
                return ["text-generation", "image-text-to-text", "conversational"].contains(tag)
            }
        } catch {
            self.error = "Suche fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
