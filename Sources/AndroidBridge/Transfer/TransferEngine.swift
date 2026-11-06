import Foundation
import AppKit
import SwiftUI
import CryptoKit
import ABCore

/// Übertragungswarteschlange, unabhängig von der Oberfläche.
/// Je Gerät läuft genau eine Übertragung zur selben Zeit (MTP ist seriell); mehrere Geräte arbeiten parallel.
@MainActor
final class TransferEngine: ObservableObject {
    @Published private(set) var jobs: [TransferJob] = []
    @Published var conflict: ConflictPrompt?

    private let devices: DeviceManager
    private let settings: SettingsStore
    private let history: HistoryStore
    private var runners: [UInt64: Task<Void, Never>] = [:]
    private var tickers: [UUID: Task<Void, Never>] = [:]

    /// Abschnittsgröße beim Lesen vom Gerät (Teilstücke).
    private let segmentSize: UInt32 = 16 * 1024 * 1024

    init(devices: DeviceManager, settings: SettingsStore, history: HistoryStore) {
        self.devices = devices
        self.settings = settings
        self.history = history
    }

    var activeJobs: [TransferJob] { jobs.filter { !$0.status.isFinished } }
    var activeCount: Int { activeJobs.count }

    var overallFraction: Double? {
        let active = activeJobs
        guard !active.isEmpty else { return nil }
        let total = active.reduce(UInt64(0)) { $0 + $1.totalBytes }
        let done = active.reduce(UInt64(0)) { $0 + $1.transferredBytes }
        return total > 0 ? Double(done) / Double(total) : 0
    }

    // MARK: - Aufträge anlegen

    @discardableResult
    func download(_ entries: [DeviceEntry], from device: DeviceConnection, sourcePath: [String], to destination: URL) -> TransferJob? {
        guard !entries.isEmpty else { return nil }
        let title = entries.count == 1 ? entries[0].name : "\(entries.count) Objekte"
        let job = TransferJob(direction: .toMac, deviceID: device.id, deviceName: device.displayName,
                              request: .download(entries: entries, sourcePath: sourcePath, destination: destination),
                              title: title,
                              source: ([device.displayName] + sourcePath).joined(separator: " › "),
                              destination: destination.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
        enqueue(job)
        return job
    }

    @discardableResult
    func upload(_ urls: [URL], to device: DeviceConnection, storageID: UInt32, parent: UInt32, destinationPath: [String]) -> TransferJob? {
        let filtered = urls.filter { !(settings.skipMacMetadata && HiddenFiles.isMacMetadata($0.lastPathComponent)) }
        guard !filtered.isEmpty else { return nil }
        let title = filtered.count == 1 ? filtered[0].lastPathComponent : "\(filtered.count) Objekte"
        let storageName = device.storages.first { $0.id == storageID }?.displayName ?? "Speicher"
        let job = TransferJob(direction: .toDevice, deviceID: device.id, deviceName: device.displayName,
                              request: .upload(urls: filtered, storageID: storageID, parent: parent, destinationPath: destinationPath),
                              title: title,
                              source: filtered.count == 1 ? filtered[0].deletingLastPathComponent().path : "Mac",
                              destination: ([device.displayName, storageName] + destinationPath).joined(separator: " › "))
        enqueue(job)
        return job
    }

    private func enqueue(_ job: TransferJob) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { jobs.insert(job, at: 0) }
        Diagnostics.shared.log(.transfer, "Neue Übertragung (\(job.direction == .toMac ? "zum Mac" : "zum Telefon"))")
        startRunner(for: job.deviceID)
    }

    // MARK: - Steuerung

    func cancel(_ job: TransferJob) {
        job.cancelRequested = true
        job.isPauseRequested = false
        if job.status == .waiting || job.status == .paused && !isRunning(job) {
            job.status = .cancelled
            job.finishedAt = Date()
        }
    }

    func pause(_ job: TransferJob) {
        guard !job.status.isFinished else { return }
        job.isPauseRequested = true
        if job.status == .waiting { job.status = .paused }
    }

    func resume(_ job: TransferJob) {
        job.isPauseRequested = false
        if job.status == .paused && !isRunning(job) { job.status = .waiting }
        startRunner(for: job.deviceID)
    }

    func retry(_ job: TransferJob) {
        guard job.status.canRetry || job.failedCount > 0 else { return }
        job.cancelRequested = false
        job.isPauseRequested = false
        job.issue = nil
        job.conflictDecision = nil
        for i in job.items.indices {
            switch job.items[i].status {
            case .failed, .cancelled, .waiting, .running, .preparing, .verifying, .paused: job.items[i].status = .waiting
            default: break
            }
        }
        job.status = .waiting
        job.finishedAt = nil
        startRunner(for: job.deviceID)
    }

    func remove(_ job: TransferJob) {
        guard job.status.isFinished else { return }
        withAnimation { jobs.removeAll { $0.id == job.id } }
    }

    func clearFinished() {
        withAnimation { jobs.removeAll { $0.status.isFinished } }
    }

    func cancelAll(for deviceID: UInt64) {
        for job in jobs where job.deviceID == deviceID && !job.status.isFinished { cancel(job) }
    }

    private var runningJobIDs = Set<UUID>()
    private func isRunning(_ job: TransferJob) -> Bool { runningJobIDs.contains(job.id) }

    // MARK: - Ablauf

    private func startRunner(for deviceID: UInt64) {
        guard runners[deviceID] == nil else { return }
        runners[deviceID] = Task { [weak self] in
            guard let self else { return }
            while let job = self.jobs.last(where: { $0.deviceID == deviceID && $0.status == .waiting && !$0.isPauseRequested }) {
                await self.run(job)
            }
            self.runners[deviceID] = nil
        }
    }

    private func run(_ job: TransferJob) async {
        guard let device = devices.device(id: job.deviceID), device.backend != nil, device.state == .connected else {
            job.status = .failed("Gerät nicht verbunden")
            job.issue = ABIssue.from(MTPError.disconnected)
            job.finishedAt = Date()
            return
        }
        runningJobIDs.insert(job.id)
        defer { runningJobIDs.remove(job.id) }
        job.startedAt = job.startedAt ?? Date()
        job.status = .preparing
        startTicker(job)
        defer { stopTicker(job) }

        do {
            if !job.planned {
                try await plan(job, device: device)
                job.planned = true
            }
            job.status = .running
            switch job.request {
            case let .download(_, _, destination):
                try await runDownload(job, device: device, destination: destination)
            case let .upload(_, storageID, parent, _):
                try await runUpload(job, device: device, storageID: storageID, parent: parent)
            }
            finish(job)
        } catch {
            if job.cancelRequested || error is CancellationError || (error as? MTPError) == .cancelled {
                for i in job.items.indices where !job.items[i].status.isFinished { job.items[i].status = .cancelled }
                job.status = .cancelled
            } else {
                let issue = ABIssue.from(error, context: "Übertragung fehlgeschlagen")
                job.issue = issue
                job.status = .failed(issue.title)
                for i in job.items.indices where !job.items[i].status.isFinished { job.items[i].status = .failed(issue.title) }
                device.reportFailure(error)
                Diagnostics.shared.log(.transfer, "Übertragung fehlgeschlagen: \(issue.title) – \(issue.technical ?? "")", error: true)
            }
            job.finishedAt = Date()
            record(job)
        }
    }

    private func finish(_ job: TransferJob) {
        refreshNumbers(job)
        let failed = job.failedCount
        if failed > 0 {
            job.status = .failed("\(failed) \(failed == 1 ? "Datei" : "Dateien") fehlgeschlagen")
        } else {
            job.status = .completed
        }
        job.finishedAt = Date()
        job.remainingSeconds = nil
        Diagnostics.shared.log(.transfer, "Übertragung beendet: \(job.completedCount) ok, \(job.skippedCount) übersprungen, \(failed) Fehler, \(ByteFormat.string(job.transferredBytes))")
        record(job)
        if settings.notifications && !NSApp.isActive {
            NotificationService.post(title: failed > 0 ? "Übertragung mit Fehlern beendet" : "Übertragung abgeschlossen",
                                     body: "\(job.title) · \(job.summary)")
        }
        if job.direction == .toDevice {
            Task { await devices.device(id: job.deviceID)?.refreshStorages() }
        }
    }

    private func record(_ job: TransferJob) {
        guard settings.keepHistory else { return }
        history.add(HistoryRecord(date: Date(), title: job.title, direction: job.direction.rawValue,
                                  fileCount: job.completedCount, bytes: job.transferredBytes,
                                  succeeded: job.status == .completed,
                                  detail: "\(job.sourceDescription) → \(job.destinationDescription)"))
    }

    // MARK: Fortschritt

    private func startTicker(_ job: TransferJob) {
        job.estimator.reset()
        tickers[job.id] = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 150_000_000)
                self?.refreshNumbers(job)
            }
        }
    }

    private func stopTicker(_ job: TransferJob) {
        tickers[job.id]?.cancel()
        tickers[job.id] = nil
        refreshNumbers(job)
        job.bytesPerSecond = 0
    }

    private func refreshNumbers(_ job: TransferJob) {
        let done = job.counter.total
        if job.transferredBytes != done { job.transferredBytes = done }
        job.estimator.update(totalBytes: done, at: Date().timeIntervalSinceReferenceDate)
        job.bytesPerSecond = job.status == .running ? job.estimator.bytesPerSecond : 0
        job.remainingSeconds = job.status == .running ? job.estimator.remainingSeconds(done: done, total: job.totalBytes) : nil
    }

    /// Wartet während einer Pause; wirft bei Abbruch.
    private func checkpoint(_ job: TransferJob) async throws {
        if job.cancelRequested { throw MTPError.cancelled }
        if job.isPauseRequested {
            let before = job.status
            job.status = .paused
            while job.isPauseRequested && !job.cancelRequested {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            if job.cancelRequested { throw MTPError.cancelled }
            job.status = before == .paused ? .running : before
            job.estimator.reset()
        }
    }

    // MARK: Konflikte

    private func resolveConflict(_ job: TransferJob, name: String, destination: String, existingSize: UInt64?,
                                 existingDate: Date?, newSize: UInt64, newDate: Date?, remaining: Int) async -> ConflictResolution {
        if let decided = job.conflictDecision { return decided }
        if settings.conflictResolution != .ask { return settings.conflictResolution }
        let previous = job.status
        job.status = .paused
        let result: (ConflictResolution, Bool) = await withCheckedContinuation { continuation in
            conflict = ConflictPrompt(fileName: name, destination: destination, existingSize: existingSize, newSize: newSize,
                                      existingDate: existingDate, newDate: newDate, remainingCount: remaining) { [weak self] choice, all in
                self?.conflict = nil
                continuation.resume(returning: (choice, all))
            }
        }
        job.status = previous
        if result.1 { job.conflictDecision = result.0 }
        return result.0
    }

    // MARK: - Planung

    private func plan(_ job: TransferJob, device: DeviceConnection) async throws {
        guard let backend = device.backend else { throw MTPError.disconnected }
        var items: [TransferItem] = []
        switch job.request {
        case let .download(entries, _, _):
            for entry in entries {
                try await checkpoint(job)
                if entry.isFolder {
                    try await collectDeviceFolder(entry, path: [FileNameSanitizer.macSafe(entry.name)], backend: backend, job: job, into: &items)
                } else {
                    items.append(TransferItem(name: entry.name, folderPath: [], size: entry.size, deviceEntry: entry, modified: entry.bestDate))
                }
            }
        case let .upload(urls, _, _, _):
            for url in urls {
                let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey])
                if v?.isDirectory == true && v?.isPackage != true {
                    let folderName = url.lastPathComponent
                    let (files, folders) = LocalFiles.enumerateFiles(in: url, skipMetadata: settings.skipMacMetadata)
                    // leere Ordner ebenfalls anlegen
                    items.append(TransferItem(name: "", folderPath: [folderName], size: 0, localURL: nil))
                    for f in folders { items.append(TransferItem(name: "", folderPath: [folderName] + f, size: 0, localURL: nil)) }
                    for f in files {
                        let mod = try? f.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                        items.append(TransferItem(name: f.url.lastPathComponent, folderPath: [folderName] + f.relative.dropLast(),
                                                  size: f.size, localURL: f.url, modified: mod))
                    }
                } else if v?.isDirectory == true {
                    // Pakete (.app, .key …) sind Ordner – auf Android nicht sinnvoll als Einzeldatei.
                    items.append(TransferItem(name: url.lastPathComponent, folderPath: [], size: 0,
                                              status: .failed("Pakete (z. B. Apps) können nicht übertragen werden"), localURL: url))
                } else {
                    items.append(TransferItem(name: url.lastPathComponent, folderPath: [], size: UInt64(max(0, v?.fileSize ?? 0)),
                                              localURL: url, modified: v?.contentModificationDate))
                }
            }
        }
        job.items = items
        job.totalBytes = items.reduce(0) { $0 + ($1.status.isFinished ? 0 : $1.size) }
        Diagnostics.shared.log(.transfer, "Geplant: \(items.filter { !$0.name.isEmpty }.count) Dateien, \(ByteFormat.string(job.totalBytes))")
    }

    private func collectDeviceFolder(_ folder: DeviceEntry, path: [String], backend: DeviceBackend, job: TransferJob,
                                     into items: inout [TransferItem]) async throws {
        items.append(TransferItem(name: "", folderPath: path, size: 0))
        let children = try await backend.list(storage: folder.storageID, parent: folder.handle)
        for child in children {
            try await checkpoint(job)
            if child.isFolder {
                try await collectDeviceFolder(child, path: path + [FileNameSanitizer.macSafe(child.name)], backend: backend, job: job, into: &items)
            } else {
                items.append(TransferItem(name: child.name, folderPath: path, size: child.size, deviceEntry: child, modified: child.bestDate))
            }
        }
    }

    // MARK: - Gerät → Mac

    private func runDownload(_ job: TransferJob, device: DeviceConnection, destination: URL) async throws {
        guard let backend = device.backend else { throw MTPError.disconnected }
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        let pendingBytes = job.items.filter { !$0.status.isFinished }.reduce(UInt64(0)) { $0 + $1.size }
        if let free = LocalFiles.availableCapacity(at: destination), free < pendingBytes {
            throw ABIssue(kind: .insufficientMacSpace, title: "Nicht genug Speicherplatz auf dem Mac",
                          message: "Benötigt werden \(ByteFormat.string(pendingBytes)), frei sind \(ByteFormat.string(free)).",
                          recommendation: "Schaffen Sie Platz oder wählen Sie ein anderes Ziel.", technical: nil)
        }
        // bereits erledigte Dateien (bei „Wiederholen“) zählen als übertragen
        job.counter.reset()
        job.counter.finishCurrent(countingAs: job.items.filter { $0.status == .completed || $0.status == .skipped }.reduce(0) { $0 + $1.size })

        let fileCount = job.items.filter { !$0.name.isEmpty }.count
        var fileNumber = 0
        for index in job.items.indices {
            try await checkpoint(job)
            let item = job.items[index]
            if item.status.isFinished { continue }
            let folderURL = item.folderPath.reduce(destination) { $0.appendingPathComponent($1, isDirectory: true) }
            if item.name.isEmpty {
                try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
                job.items[index].status = .completed
                continue
            }
            fileNumber += 1
            guard let entry = item.deviceEntry else { continue }
            job.currentName = item.name
            job.currentIndex = fileNumber
            try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

            var finalName = FileNameSanitizer.macSafe(item.name)
            var finalURL = folderURL.appendingPathComponent(finalName)
            var replaceExisting = false
            if fm.fileExists(atPath: finalURL.path) {
                let attrs = try? fm.attributesOfItem(atPath: finalURL.path)
                let decision = await resolveConflict(job, name: finalName, destination: folderURL.lastPathComponent,
                                                     existingSize: (attrs?[.size] as? NSNumber)?.uint64Value,
                                                     existingDate: attrs?[.modificationDate] as? Date,
                                                     newSize: entry.size, newDate: entry.bestDate,
                                                     remaining: fileCount - fileNumber)
                try await checkpoint(job)
                switch decision {
                case .skip, .ask:
                    job.items[index].status = .skipped
                    job.counter.finishCurrent(countingAs: item.size)
                    continue
                case .keepBoth:
                    let existing = Set((try? fm.contentsOfDirectory(atPath: folderURL.path)) ?? [])
                    finalName = ConflictNaming.uniqueName(for: finalName, existing: existing)
                    finalURL = folderURL.appendingPathComponent(finalName)
                case .replace:
                    replaceExisting = true
                }
            }

            job.items[index].status = .running
            let tempURL = folderURL.appendingPathComponent(".\(finalName).\(UUID().uuidString.prefix(8)).abpart")
            do {
                let written = try await downloadFile(entry, to: tempURL, backend: backend, job: job)
                job.items[index].status = .verifying
                try await verifyDownload(entry: entry, file: tempURL, written: written, backend: backend)
                if replaceExisting {
                    _ = try fm.replaceItemAt(finalURL, withItemAt: tempURL, backupItemName: nil, options: [])
                } else {
                    if fm.fileExists(atPath: finalURL.path) {
                        // inzwischen entstanden – nichts überschreiben
                        let existing = Set((try? fm.contentsOfDirectory(atPath: folderURL.path)) ?? [])
                        finalName = ConflictNaming.uniqueName(for: finalName, existing: existing)
                        finalURL = folderURL.appendingPathComponent(finalName)
                    }
                    try fm.moveItem(at: tempURL, to: finalURL)
                }
                if settings.preserveDates, let date = entry.bestDate {
                    try? fm.setAttributes([.modificationDate: date, .creationDate: entry.created ?? date], ofItemAtPath: finalURL.path)
                }
                job.items[index].status = .completed
                job.items[index].resultName = finalName
                job.counter.finishCurrent(countingAs: item.size)
            } catch {
                try? fm.removeItem(at: tempURL)
                job.counter.finishCurrent(countingAs: 0)
                if job.cancelRequested || (error as? MTPError) == .cancelled || error is CancellationError {
                    job.items[index].status = .cancelled
                    throw MTPError.cancelled
                }
                let issue = ABIssue.from(error)
                job.items[index].status = .failed(issue.title)
                Diagnostics.shared.log(.transfer, "Datei fehlgeschlagen: \(issue.title) \(issue.technical ?? "")", error: true)
                if let mtp = error as? MTPError, mtp == .disconnected || mtp == .timeout { throw error }
                if issue.kind == .insufficientMacSpace { throw issue }
            }
        }
    }

    /// Lädt eine Datei in eine temporäre Datei; in Abschnitten, wenn das Gerät das kann (Pause/Fortsetzen möglich).
    private func downloadFile(_ entry: DeviceEntry, to tempURL: URL, backend: DeviceBackend, job: TransferJob) async throws -> UInt64 {
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tempURL)
        defer { try? handle.close() }
        let counter = job.counter
        counter.setCurrent(0)
        var written: UInt64 = 0
        let sink: (Data) throws -> Void = { data in
            try handle.write(contentsOf: data)
            counter.addCurrent(UInt64(data.count))
        }
        if backend.supportsPartialDownload && entry.size > UInt64(segmentSize) {
            var offset: UInt64 = 0
            while offset < entry.size {
                try await checkpoint(job)
                let n = try await backend.downloadSegment(handle: entry.handle, offset: offset, length: segmentSize, sink: sink)
                if n == 0 { break }
                offset += n
            }
            written = offset
        } else {
            let jobRef = CancelFlag()
            let watcher = Task { [weak job] in
                while !Task.isCancelled {
                    if job?.cancelRequested ?? true { jobRef.cancel(); return }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
            defer { watcher.cancel() }
            try await backend.download(handle: entry.handle, sink: sink, progress: { _ in !jobRef.isCancelled })
            written = counter.current
        }
        try handle.synchronize()
        return written
    }

    private func verifyDownload(entry: DeviceEntry, file: URL, written: UInt64, backend: DeviceBackend) async throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        let actual = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        var expected = entry.size
        if actual != expected {
            // Liste kann veraltet sein – aktuelle Größe beim Gerät erfragen.
            if let fresh = try? await backend.entry(handle: entry.handle) { expected = fresh.size }
        }
        guard TransferVerification.sizeMatches(expected: expected, actual: actual) else {
            throw MTPError.incomplete(expected: expected, received: actual)
        }
        if settings.verification == .checksum {
            let local = try await sha256(of: file)
            let remote = try await remoteSHA256(handle: entry.handle, size: expected, backend: backend)
            guard local == remote else {
                throw ABIssue(kind: .incompleteTransfer, title: "Prüfsumme stimmt nicht",
                              message: "Die übertragene Datei weicht vom Original ab.",
                              recommendation: "Wiederholen Sie die Übertragung, möglichst mit einem anderen Kabel.",
                              technical: "SHA-256 lokal \(local.prefix(12)) ≠ Gerät \(remote.prefix(12))")
            }
        }
    }

    /// SHA-256 einer Mac-Datei – im Hintergrund, nicht auf dem Hauptthread.
    private func sha256(of url: URL) async throws -> String {
        try await Task.detached(priority: .utility) { try TransferEngine.fileSHA256(url) }.value
    }

    private nonisolated static func fileSHA256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func remoteSHA256(handle: UInt32, size: UInt64, backend: DeviceBackend) async throws -> String {
        final class Box: @unchecked Sendable { var hasher = SHA256() }
        let box = Box()
        let sink: (Data) throws -> Void = { box.hasher.update(data: $0) }
        if backend.supportsPartialDownload && size > UInt64(segmentSize) {
            var offset: UInt64 = 0
            while offset < size {
                let n = try await backend.downloadSegment(handle: handle, offset: offset, length: segmentSize, sink: sink)
                if n == 0 { break }
                offset += n
            }
        } else {
            try await backend.download(handle: handle, sink: sink, progress: { _ in true })
        }
        return box.hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Mac → Gerät

    private func runUpload(_ job: TransferJob, device: DeviceConnection, storageID: UInt32, parent: UInt32) async throws {
        guard let backend = device.backend else { throw MTPError.disconnected }
        await device.refreshStorages()
        let pendingBytes = job.items.filter { !$0.status.isFinished }.reduce(UInt64(0)) { $0 + $1.size }
        if let storage = device.storages.first(where: { $0.id == storageID }) {
            if storage.isReadOnly {
                throw ABIssue(kind: .permissionDenied, title: "Speicher ist schreibgeschützt",
                              message: "Auf „\(storage.displayName)“ kann nicht geschrieben werden.", recommendation: nil, technical: nil)
            }
            if storage.free > 0 && storage.free < pendingBytes {
                throw ABIssue(kind: .insufficientDeviceSpace, title: "Nicht genug Speicher auf dem Telefon",
                              message: "Benötigt werden \(ByteFormat.string(pendingBytes)), frei sind \(ByteFormat.string(storage.free)).",
                              recommendation: "Schaffen Sie Platz auf dem Telefon oder wählen Sie einen anderen Speicher.", technical: nil)
            }
        }
        job.counter.reset()
        job.counter.finishCurrent(countingAs: job.items.filter { $0.status == .completed || $0.status == .skipped }.reduce(0) { $0 + $1.size })

        // Ordnerinhalte am Ziel (Name → Eintrag) je Elternobjekt, für Konflikte und vorhandene Ordner
        var listings: [UInt32: [String: DeviceEntry]] = [:]
        func listing(_ handle: UInt32) async throws -> [String: DeviceEntry] {
            if let l = listings[handle] { return l }
            let children = try await backend.list(storage: storageID, parent: handle)
            var map: [String: DeviceEntry] = [:]
            for c in children { map[c.name.lowercased()] = c }
            listings[handle] = map
            return map
        }
        var folderHandles: [[String]: UInt32] = [[]: parent]
        func ensureFolder(_ path: [String]) async throws -> UInt32 {
            if let h = folderHandles[path] { return h }
            let parentHandle = try await ensureFolder(Array(path.dropLast()))
            let name = FileNameSanitizer.androidSafe(path.last ?? "Ordner")
            let existing = try await listing(parentHandle)
            if let e = existing[name.lowercased()], e.isFolder {
                folderHandles[path] = e.handle
                return e.handle
            }
            let created = try await backend.createFolder(name: name, storage: storageID, parent: parentHandle)
            listings[parentHandle]?[name.lowercased()] = DeviceEntry(handle: created, storageID: storageID, parent: parentHandle,
                                                                     name: name, isFolder: true, size: 0, format: MTPFormat.association)
            listings[created] = [:]
            folderHandles[path] = created
            return created
        }

        let fileCount = job.items.filter { !$0.name.isEmpty }.count
        var fileNumber = 0
        for index in job.items.indices {
            try await checkpoint(job)
            let item = job.items[index]
            if item.status.isFinished { continue }
            if item.name.isEmpty {
                _ = try await ensureFolder(item.folderPath)
                job.items[index].status = .completed
                continue
            }
            fileNumber += 1
            guard let url = item.localURL else { continue }
            job.currentName = item.name
            job.currentIndex = fileNumber
            job.items[index].status = .running
            do {
                let parentHandle = try await ensureFolder(item.folderPath)
                var name = FileNameSanitizer.androidSafe(item.name)
                var existing = try await listing(parentHandle)
                var replaceHandle: UInt32?
                if let clash = existing[name.lowercased()] {
                    let decision = await resolveConflict(job, name: name, destination: job.destinationDescription,
                                                         existingSize: clash.isFolder ? nil : clash.size, existingDate: clash.bestDate,
                                                         newSize: item.size, newDate: item.modified, remaining: fileCount - fileNumber)
                    try await checkpoint(job)
                    switch decision {
                    case .skip, .ask:
                        job.items[index].status = .skipped
                        job.counter.finishCurrent(countingAs: item.size)
                        continue
                    case .keepBoth:
                        name = ConflictNaming.uniqueName(for: name, existing: Set(existing.values.map(\.name)))
                    case .replace:
                        if clash.isFolder {
                            name = ConflictNaming.uniqueName(for: name, existing: Set(existing.values.map(\.name)))
                        } else {
                            replaceHandle = clash.handle
                        }
                    }
                }
                // Beim Ersetzen zuerst unter vorläufigem Namen hochladen, erst danach das Original löschen.
                let uploadName = replaceHandle != nil ? ".\(name).abpart" : name
                let size = item.size
                let fileHandle = try FileHandle(forReadingFrom: url)
                defer { try? fileHandle.close() }
                let counter = job.counter
                counter.setCurrent(0)
                let flag = CancelFlag()
                let watcher = Task { [weak job] in
                    while !Task.isCancelled {
                        if job?.cancelRequested ?? true { flag.cancel(); return }
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    }
                }
                defer { watcher.cancel() }
                let newHandle = try await backend.upload(
                    name: uploadName, size: size, storage: storageID, parent: parentHandle,
                    modified: settings.preserveDates ? item.modified : nil,
                    next: { max in
                        try fileHandle.read(upToCount: max) ?? Data()
                    },
                    progress: { bytes in
                        counter.setCurrent(bytes)
                        return !flag.isCancelled
                    })
                job.items[index].status = .verifying
                let check = try await backend.entry(handle: newHandle)
                if !TransferVerification.sizeMatches(expected: size, actual: check.size) {
                    try? await backend.delete(handle: newHandle)
                    throw MTPError.incomplete(expected: size, received: check.size)
                }
                if settings.verification == .checksum {
                    let local = try await sha256(of: url)
                    let remote = try await remoteSHA256(handle: newHandle, size: size, backend: backend)
                    if local != remote {
                        try? await backend.delete(handle: newHandle)
                        throw ABIssue(kind: .incompleteTransfer, title: "Prüfsumme stimmt nicht",
                                      message: "Die Datei auf dem Telefon weicht vom Original ab.",
                                      recommendation: "Wiederholen Sie die Übertragung.", technical: nil)
                    }
                }
                if let old = replaceHandle {
                    try await backend.delete(handle: old)
                    try await backend.rename(handle: newHandle, to: name)
                    existing[name.lowercased()] = nil
                }
                var newEntry = check
                newEntry.name = name
                listings[parentHandle]?[name.lowercased()] = newEntry
                job.items[index].status = .completed
                job.items[index].resultName = name
                job.counter.finishCurrent(countingAs: item.size)
            } catch {
                job.counter.finishCurrent(countingAs: 0)
                if job.cancelRequested || (error as? MTPError) == .cancelled || error is CancellationError {
                    job.items[index].status = .cancelled
                    throw MTPError.cancelled
                }
                let issue = ABIssue.from(error)
                job.items[index].status = .failed(issue.title)
                Diagnostics.shared.log(.transfer, "Datei fehlgeschlagen: \(issue.title) \(issue.technical ?? "")", error: true)
                if let mtp = error as? MTPError, mtp == .disconnected || mtp == .timeout { throw error }
                if issue.kind == .insufficientDeviceSpace { throw issue }
            }
        }
    }
}
