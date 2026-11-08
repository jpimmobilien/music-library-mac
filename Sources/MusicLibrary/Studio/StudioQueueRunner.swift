import Foundation
import AppKit
import MLCore
import MLStudio
import StudioEngine

// Warteschlange, Verlauf und Ersetzen/Rückgängig des Audio Studios.
//
// Regeln: genau ein aktiver Auftrag (`StudioQueueLogic.nextRunnable`), Reihenfolge wie hinzugefügt, nach
// einem Fehler geht es mit dem nächsten weiter. Ablauf je Auftrag: (Abfrage) → Laden → Umwandeln
// (`services.exporter`, anhaltbar über `PauseGate`) → Datei an einen freien Namen im Ziel verschieben bzw.
// Original sicher ersetzen → Bibliothek einlesen → Verlauf.
extension StudioModel {
    // MARK: - Aktionen: Warteschlange

    /// Anhalten: Laden → Prozess beenden (Teil-Datei bleibt, Fortsetzen lädt weiter); Umwandeln → `PauseGate`;
    /// wartend → wird übersprungen. Während ein Auftrag angehalten ist, läuft der nächste.
    func pause(_ id: UUID) {
        guard let job = self.job(id), StudioQueueLogic.canPause(job) else { return }
        switch job.phase {
        case .waiting:
            if let gate = jobGates[id] { gate.pause() }
            updateJob(id) { $0.phase = .paused; $0.detail = nil }
        case .downloading:
            pauseRequested.insert(id)
            jobTasks[id]?.cancel()
        case .converting, .tagging:
            jobGates[id]?.pause()
            updateJob(id) { $0.phase = .paused; $0.detail = "Angehalten" }
            if runningJobID == id { runningJobID = nil }
            scheduleNext()
        default:
            break
        }
    }

    func resume(_ id: UUID) {
        guard let job = self.job(id), StudioQueueLogic.canResume(job) else { return }
        if jobTasks[id] != nil, let gate = jobGates[id] {
            // Angehaltene Umwandlung: sofort weiter, wenn nichts anderes läuft – sonst danach.
            if runningJobID == nil {
                runningJobID = id
                updateJob(id) { $0.phase = .converting; $0.detail = nil }
                gate.resume()
            } else {
                updateJob(id) { $0.phase = .waiting; $0.detail = "Wird danach fortgesetzt" }
            }
            return
        }
        updateJob(id) { $0.phase = .waiting; $0.detail = nil }
        scheduleNext()
    }

    func cancel(_ id: UUID) {
        guard let job = self.job(id), StudioQueueLogic.canCancel(job) else { return }
        pauseRequested.remove(id)
        if let task = jobTasks[id] {
            task.cancel()
            // Ein angehaltener Exporter muss weiterlaufen dürfen, um den Abbruch zu bemerken.
            jobGates[id]?.resume()
            if job.phase == .paused || job.phase == .waiting {
                updateJob(id) { $0.phase = .cancelled; $0.detail = nil; $0.finished = Date() }
            }
        } else {
            updateJob(id) { $0.phase = .cancelled; $0.detail = nil; $0.finished = Date() }
            removeWorkDirectory(id)
        }
    }

    func retry(_ id: UUID) {
        guard let job = self.job(id), StudioQueueLogic.canRetry(job), jobTasks[id] == nil else { return }
        updateJob(id) {
            $0.phase = .waiting
            $0.progress = 0
            $0.error = nil
            $0.detail = nil
            $0.finished = nil
            $0.outputPath = nil
        }
        scheduleNext()
    }

    func remove(_ id: UUID) {
        guard let job = self.job(id), StudioQueueLogic.canRemove(job) else { return }
        if let task = jobTasks[id] {
            task.cancel()
            jobGates[id]?.resume()
        } else {
            removeWorkDirectory(id)
        }
        pendingAnalysis.remove(id)
        pauseRequested.remove(id)
        jobs.removeAll { $0.id == id }
    }

    func clearFinished() {
        let finished = jobs.filter { $0.phase.isFinished && jobTasks[$0.id] == nil }.map(\.id)
        guard !finished.isEmpty else { return }
        for id in finished {
            removeWorkDirectory(id)
            pendingAnalysis.remove(id)
        }
        let set = Set(finished)
        jobs.removeAll { set.contains($0.id) }
    }

    /// Format eines wartenden Auftrags ändern (unterschiedliche Formate je Datei).
    func setFormat(_ format: StudioFormat, for id: UUID) {
        guard let job = self.job(id), job.phase == .waiting || job.phase == .paused, jobTasks[id] == nil,
              !job.destination.replacesOriginal, job.options.format != format else { return }
        updateJob(id) { j in
            j.options = settings.options(for: format)
            if j.source.libraryUid != nil {
                j.preferPassthrough = format == j.source.sameFormat && j.fadeIn <= 0 && j.fadeOut <= 0
            }
        }
    }

    /// Fertige Datei in der Bibliothek abspielen (falls importiert), sonst im Finder zeigen.
    func playExported(_ path: String) {
        if let uid = lib?.studioTracks.first(where: { $0.path == path })?.uid {
            lib?.studioPlay(uid: uid)
        } else if FileManager.default.fileExists(atPath: path) {
            revealInFinder(path)
            lib?.studioToast("Die Datei ist (noch) nicht in der Bibliothek – sie wird im Finder gezeigt.", action: nil, isError: false, perform: nil)
        } else {
            lib?.studioToast("Die Datei wurde nicht gefunden.", action: nil, isError: true, perform: nil)
        }
    }

    // MARK: - Ablauf

    func job(_ id: UUID) -> StudioJob? { jobs.first { $0.id == id } }

    func updateJob(_ id: UUID, _ change: (inout StudioJob) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        var j = jobs[i]
        change(&j)
        if j != jobs[i] { jobs[i] = j }
    }

    /// Nächsten Auftrag starten, falls keiner läuft.
    func scheduleNext() {
        guard runningJobID == nil, let id = StudioQueueLogic.nextRunnable(jobs) else { return }
        if jobTasks[id] != nil, let gate = jobGates[id] {
            // Angehaltene Umwandlung, die wieder an der Reihe ist
            runningJobID = id
            updateJob(id) { $0.phase = .converting; $0.detail = nil }
            gate.resume()
            return
        }
        runningJobID = id
        let gate = PauseGate()
        jobGates[id] = gate
        jobTasks[id] = Task { [weak self] in
            await self?.runJob(id, gate: gate)
        }
    }

    /// Mehrere Quellen (Adressen, Playlist-Einträge, Dateien) mit den gemeinsamen Einstellungen einreihen.
    /// Die Quellen werden erst beim Start abgefragt. Spotify wird übersprungen (DRM).
    @discardableResult
    func enqueuePending(_ sources: [SourceInfo]) -> Int {
        let opts = isLibraryTrack ? settings.options(for: settings.lastFormat) : options
        let dest = settingsDestination
        var added = 0
        var skipped = 0
        for s in sources.prefix(RemoteLookup.maxEntries) {
            if !s.kind.supportsAudio { skipped += 1; continue }
            let job = StudioJob(source: s, options: opts, trim: nil, metadata: StudioMetadata(title: s.title),
                                fileName: batchScheme.render(StudioMetadata(title: s.title), fallback: s.title), destination: dest)
            jobs.append(job)
            pendingAnalysis.insert(job.id)
            added += 1
        }
        if skipped > 0 {
            lib?.studioToast(skipped == 1 ? "1 Spotify-Link übersprungen – Spotify-Audio ist kopiergeschützt (DRM)."
                                          : "\(skipped) Spotify-Links übersprungen – Spotify-Audio ist kopiergeschützt (DRM).",
                             action: nil, isError: true, perform: nil)
        }
        scheduleNext()
        return added
    }

    /// Dateinamen-Schema für mehrere Aufträge: ein eigener fester Name passt nicht – dann „Interpret – Titel“.
    var batchScheme: FileNameScheme {
        if case .custom = settings.fileNameScheme { return .artistTitle }
        return settings.fileNameScheme
    }

    func jobWorkDirectory(_ id: UUID) -> URL {
        cacheRoot.appendingPathComponent("job-\(id.uuidString)", isDirectory: true)
    }

    func removeWorkDirectory(_ id: UUID) {
        let dir = jobWorkDirectory(id)
        Self.ioQueue.async { try? FileManager.default.removeItem(at: dir) }
    }

    private func runJob(_ id: UUID, gate: PauseGate) async {
        let workDir = jobWorkDirectory(id)
        do {
            guard var job = self.job(id) else { throw StudioError.cancelled }
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

            // 1. Abfrage (Aufträge aus mehreren Adressen, Playlists oder Dateien)
            if pendingAnalysis.contains(id) {
                let remote = job.source.kind != .localFile
                updateJob(id) { $0.phase = remote ? .downloading : .converting; $0.progress = 0; $0.detail = remote ? "Wird abgefragt …" : "Datei wird gelesen …" }
                var info: SourceInfo
                if remote {
                    info = try await services.remote.analyze(url: job.source.url, kind: job.source.kind)
                } else {
                    let file = job.source.localFile ?? job.source.url
                    info = try await services.local.analyze(file: file)
                    if info.localFile == nil { info.localFile = file }
                }
                try Task.checkCancellation()
                if info.isLive { throw StudioError.liveStream }
                if !info.kind.supportsAudio { throw StudioError.spotifyDRM }
                var meta = info.suggested
                if meta.cover == nil {
                    if let t = info.thumbnail {
                        meta.cover = t
                    } else if remote, info.thumbnailURL != nil {
                        meta.cover = await services.remote.thumbnail(for: info)
                    }
                }
                let scheme = batchScheme
                updateJob(id) { j in
                    j.source = info
                    j.metadata = meta
                    j.fileName = scheme.render(meta, fallback: info.title)
                    j.detail = nil
                }
                pendingAnalysis.remove(id)
                guard let updated = self.job(id) else { throw StudioError.cancelled }
                job = updated
            }

            // 2. Laden (Internet-Quellen)
            let input = try await inputFile(for: job, workDir: workDir)
            try Task.checkCancellation()

            // 3. Umwandeln
            if pauseRequested.contains(id) { throw StudioError.cancelled }
            updateJob(id) { $0.phase = gate.isPaused ? .paused : .converting; $0.progress = 0; $0.detail = nil }
            guard let current = self.job(id) else { throw StudioError.cancelled }
            job = current
            let output = workDir.appendingPathComponent("export.\(job.options.format.fileExtension)")
            try? FileManager.default.removeItem(at: output)
            let request = ExportRequest(input: input, trim: job.trim, options: job.options, metadata: job.metadata, output: output,
                                        fadeIn: job.fadeIn, fadeOut: job.fadeOut, preferPassthrough: job.preferPassthrough,
                                        copyTagsFrom: job.source.libraryUid != nil ? input : nil)
            let throttle = ThrottleGate(interval: 0.2)
            let result = try await services.exporter.export(request, pause: gate) { value in
                guard throttle.allow(force: value >= 1) else { return }
                Task { @MainActor [weak self] in
                    self?.updateJob(id) { j in if j.phase == .converting { j.progress = min(1, max(0, value)) } }
                }
            }
            try Task.checkCancellation()

            // 4. Ablegen bzw. Original ersetzen
            updateJob(id) { $0.phase = job.destination.importsIntoLibrary ? .importing : .converting; $0.progress = 1; $0.detail = nil }
            let produced = result.output.path.isEmpty ? output : result.output
            var finalPath: String
            var backupPath: String?
            switch job.destination {
            case .replaceOriginal(let uid, let path):
                try Self.checkExportedDuration(result, job: job)
                let backups = backupsRoot
                let record = try await Self.offMain { try StudioFileOps.replaceOriginal(at: path, with: produced, uid: uid, backupsRoot: backups) }
                finalPath = path
                backupPath = record.backupPath
                lib?.studioRefreshTrack(uid)
            case .library(_, let folderPath, _):
                guard FileManager.default.fileExists(atPath: folderPath) else {
                    throw StudioError.other("Der Musikordner „\(folderPath)“ ist nicht erreichbar – ist das Laufwerk angeschlossen?")
                }
                fallthrough
            case .folder:
                let dir = job.destination.directoryPath
                let base = job.fileName.isEmpty ? "Audio" : job.fileName
                let ext = job.options.format.fileExtension
                finalPath = try await Self.offMain { try StudioFileOps.moveIntoPlace(produced, directory: dir, base: base, ext: ext) }
                let folders = (lib?.studioFolders ?? []).filter(\.enabled).map(\.path)
                if job.destination.importsIntoLibrary || StudioFileOps.isInside(finalPath, folders: folders) {
                    lib?.studioRescan()
                }
            }

            // 5. Fertig
            updateJob(id) { j in
                j.phase = .done
                j.progress = 1
                j.outputPath = finalPath
                j.finished = Date()
                j.error = nil
                j.detail = Self.formatSummary(result, options: job.options)
            }
            let entry = StudioHistoryEntry(sourceKind: job.source.kind, source: Self.historyKey(job.source),
                                           title: job.metadata.title.studioTrimmed.isEmpty ? job.source.title : job.metadata.title,
                                           artist: job.metadata.artist, outputPath: finalPath,
                                           formatSummary: Self.formatSummary(result, options: job.options),
                                           duration: result.duration > 0 ? result.duration : (job.trim?.length ?? job.source.duration),
                                           imported: job.destination.importsIntoLibrary, succeeded: true, backupPath: backupPath)
            addHistory(entry)
            if job.destination.replacesOriginal { notifyReplaced(path: finalPath, historyID: entry.id) }
            queueRun.done += 1
            queueRun.last = (job, finalPath)
            removeWorkDirectory(id)
        } catch {
            if Self.isCancellation(error) || Task.isCancelled {
                if pauseRequested.contains(id), self.job(id) != nil {
                    // Laden angehalten: Teil-Datei bleibt liegen, „Fortsetzen“ lädt weiter (--continue).
                    updateJob(id) { $0.phase = .paused; $0.detail = "Angehalten – Fortsetzen lädt weiter" }
                } else {
                    updateJob(id) { $0.phase = .cancelled; $0.detail = nil; $0.finished = Date() }
                    removeWorkDirectory(id)
                }
            } else {
                let message = Self.message(error)
                updateJob(id) { $0.phase = .failed; $0.error = message; $0.detail = nil; $0.finished = Date() }
                queueRun.failed += 1
                if let job = self.job(id) {
                    queueRun.lastFailure = (job.metadata.title.studioTrimmed.isEmpty ? job.source.title : job.metadata.title, message)
                    addHistory(StudioHistoryEntry(sourceKind: job.source.kind, source: Self.historyKey(job.source),
                                                  title: job.metadata.title.studioTrimmed.isEmpty ? job.source.title : job.metadata.title,
                                                  artist: job.metadata.artist, outputPath: "", formatSummary: job.options.summary(),
                                                  duration: job.trim?.length ?? job.source.duration,
                                                  imported: false, succeeded: false, error: message))
                }
                // Angefangene Downloads bleiben für „Wiederholen“ liegen (Aufräumen beim Entfernen/Beenden).
            }
        }
        jobTasks[id] = nil
        jobGates[id] = nil
        pauseRequested.remove(id)
        if runningJobID == id { runningJobID = nil }
        scheduleNext()
        if runningJobID == nil { finishQueueRun() }
    }

    /// Warteschlange leer gelaufen: ein Auftrag → eigene Mitteilung, mehrere → eine Zusammenfassung
    /// (keine Flut von Mitteilungen bei Playlists).
    private func finishQueueRun() {
        let run = queueRun
        queueRun = StudioQueueRun()
        let total = run.done + run.failed
        guard total > 0 else { return }
        if total == 1 {
            if let last = run.last {
                if !last.job.destination.replacesOriginal { notifySuccess(last.job, path: last.path) }
            } else if let failure = run.lastFailure {
                lib?.studioToast("„\(failure.title)“: \(failure.message)", action: nil, isError: true, perform: nil)
            }
            return
        }
        let text = run.failed == 0 ? "\(run.done) Aufträge fertig" : "\(run.done) von \(total) Aufträgen fertig · \(run.failed) Fehler"
        guard let path = run.last?.path else {
            lib?.studioToast(text, action: nil, isError: true, perform: nil)
            return
        }
        if settings.revealAfterExport {
            revealInFinder(path)
            lib?.studioToast(text, action: nil, isError: run.failed > 0, perform: nil)
        } else {
            lib?.studioToast(text, action: "Im Finder zeigen", isError: run.failed > 0) { [weak self] in self?.revealInFinder(path) }
        }
    }

    /// Lokale Datei des Auftrags: Datei bzw. Bibliothekstitel direkt; Internet-Quelle aus dem Zwischenspeicher
    /// des Editors (als Klon im Arbeitsordner) oder neu geladen.
    private func inputFile(for job: StudioJob, workDir: URL) async throws -> URL {
        let id = job.id
        if job.source.kind == .localFile || job.source.libraryUid != nil {
            let file = job.source.localFile ?? job.source.url
            guard FileManager.default.fileExists(atPath: file.path) else {
                throw StudioError.other("Die Datei wurde nicht gefunden: \(file.path)")
            }
            return file
        }
        guard job.source.kind.supportsAudio else { throw StudioError.spotifyDRM }
        if job.source.isLive { throw StudioError.liveStream }
        let fm = FileManager.default
        if let cached = job.source.localFile, fm.fileExists(atPath: cached.path) {
            if cached.path.hasPrefix(workDir.path + "/") { return cached }
            let clone = workDir.appendingPathComponent("quelle." + cached.pathExtension)
            if let copied = try? await Self.offMain({ () -> URL in
                try? FileManager.default.removeItem(at: clone)
                try FileManager.default.copyItem(at: cached, to: clone)   // APFS: Klon ohne zusätzlichen Platz
                return clone
            }) {
                return copied
            }
        }
        updateJob(id) { $0.phase = .downloading; $0.detail = nil }
        let file = try await services.remote.download(job.source, into: workDir) { p in
            Task { @MainActor [weak self] in
                self?.updateJob(id) { j in
                    guard j.phase == .downloading else { return }
                    if let f = p.fraction { j.progress = min(1, max(0, f)) }
                    j.detail = StudioModel.describe(p)
                }
            }
        }
        updateJob(id) { $0.source.localFile = file }
        return file
    }

    /// „3,2 MB von 8,1 MB · 1,4 MB/s · noch 0:05“
    nonisolated static func describe(_ p: DownloadProgress) -> String? {
        var parts: [String] = []
        if let done = p.bytesDone {
            parts.append(p.bytesTotal.map { "\(Formatting.fileSize(done)) von \(Formatting.fileSize($0))" } ?? Formatting.fileSize(done))
        }
        if let s = p.bytesPerSecond, s > 0 { parts.append("\(Formatting.fileSize(Int64(s)))/s") }
        if let eta = p.etaSeconds, eta > 0 { parts.append("noch \(Formatting.duration(Int64(eta * 1000)))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Angaben aus der fertigen Datei, z. B. „MP3 · 320 kbit/s · 44,1 kHz“ oder „FLAC · 24 Bit · 48 kHz“.
    nonisolated static func formatSummary(_ r: ExportResult, options: ExportOptions) -> String {
        var parts = [options.format.label]
        if options.format.isLossless {
            if let b = r.bitDepth, b > 0 { parts.append(b == 32 && options.format != .flac ? "32 Bit Float" : "\(b) Bit") }
        } else if r.bitrateKbps > 0 {
            parts.append("\(r.bitrateKbps) kbit/s")
        }
        if r.sampleRate > 0 { parts.append(ExportOptions.rateLabel(r.sampleRate)) }
        if r.passthrough { parts.append("ohne Neukodierung") }
        return parts.joined(separator: " · ")
    }

    /// Vor dem Ersetzen: Die neue Datei muss die erwartete Länge haben (sonst bleibt das Original unverändert).
    nonisolated static func checkExportedDuration(_ r: ExportResult, job: StudioJob) throws {
        guard r.duration > 0.05 else { throw StudioError.encodeFailed("Die neue Datei enthält kein Audio – das Original bleibt unverändert.") }
        if let expected = job.trim?.length ?? job.source.duration, expected > 0 {
            let tolerance = max(1.0, expected * 0.02)
            if abs(r.duration - expected) > tolerance {
                throw StudioError.encodeFailed("Die neue Datei ist \(StudioTime.format(r.duration, millis: false)) lang statt \(StudioTime.format(expected, millis: false)) – das Original bleibt unverändert.")
            }
        }
    }

    /// Dateiarbeit im Hintergrund (nie auf dem Hauptthread).
    nonisolated static func offMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .utility) { try work() }.value
    }

    /// Original ersetzt: sofort melden, mit „Rückgängig“.
    private func notifyReplaced(path: String, historyID: UUID) {
        let name = (path as NSString).lastPathComponent
        lib?.studioToast("Original ersetzt: „\(name)“ (Sicherung angelegt)", action: "Rückgängig", isError: false) { [weak self] in
            self?.undoReplace(historyID)
        }
    }

    private func notifySuccess(_ job: StudioJob, path: String) {
        let name = (path as NSString).lastPathComponent
        switch job.destination {
        case .replaceOriginal:
            return
        case .library:
            let text = "„\(name)“ in die Bibliothek übernommen"
            if settings.revealAfterExport {
                revealInFinder(path)
                lib?.studioToast(text, action: nil, isError: false, perform: nil)
            } else {
                lib?.studioToast(text, action: "Im Finder zeigen", isError: false) { [weak self] in self?.revealInFinder(path) }
            }
        case .folder:
            let text = "„\(name)“ gespeichert"
            if settings.revealAfterExport {
                revealInFinder(path)
                lib?.studioToast(text, action: nil, isError: false, perform: nil)
            } else {
                lib?.studioToast(text, action: "Im Finder zeigen", isError: false) { [weak self] in self?.revealInFinder(path) }
            }
        }
    }

    // MARK: - Verlauf

    func addHistory(_ entry: StudioHistoryEntry) {
        history.add(entry)
        saveHistory()
    }

    func clearHistory() {
        guard !history.entries.isEmpty else { return }
        history = StudioHistory()
        saveHistory()
    }

    /// Verlauf atomar speichern (Hintergrund, Reihenfolge bleibt erhalten).
    func saveHistory() {
        guard !demo else { return }
        let snapshot = history
        let url = historyURL
        Self.ioQueue.async {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("Audio Studio: Verlauf konnte nicht gespeichert werden: \(error.localizedDescription)")
            }
        }
    }

    /// Verlauf laden (Hintergrund) und mit Einträgen dieser Sitzung zusammenführen.
    func loadHistory() {
        guard !demo else { return }
        let url = historyURL
        Self.ioQueue.async {
            let loaded: StudioHistory? = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(StudioHistory.self, from: $0) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.historyLoaded = true
                guard let loaded, !loaded.entries.isEmpty else { return }
                let known = Set(loaded.entries.map(\.id))
                var merged = loaded.entries + self.history.entries.filter { !known.contains($0.id) }
                merged.sort { $0.date > $1.date }
                if merged.count > StudioHistory.limit { merged.removeLast(merged.count - StudioHistory.limit) }
                self.history = StudioHistory(entries: merged)
            }
        }
    }

    /// Wartet, bis alle Dateiarbeiten (Verlauf, Zwischenspeicher) erledigt sind (für Tests).
    func waitForPendingWrites() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            Self.ioQueue.async { c.resume() }
        }
    }

    /// Ersetztes Original aus der Sicherung wiederherstellen.
    func undoReplace(_ historyID: UUID) {
        guard let entry = history.entries.first(where: { $0.id == historyID }), let backup = entry.backupPath, !entry.undone else { return }
        Task { [weak self] in
            do {
                let record = try await StudioModel.offMain { try StudioFileOps.undoReplace(backupPath: backup) }
                guard let self else { return }
                if let i = self.history.entries.firstIndex(where: { $0.id == historyID }) {
                    self.history.entries[i].undone = true
                    self.saveHistory()
                }
                self.lib?.studioRefreshTrack(record.uid)
                self.lib?.studioToast("Original wiederhergestellt: „\((record.originalPath as NSString).lastPathComponent)“", action: nil, isError: false, perform: nil)
            } catch {
                self?.lib?.studioToast(StudioModel.message(error), action: nil, isError: true, perform: nil)
            }
        }
    }
}
