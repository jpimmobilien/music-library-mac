import XCTest
import Combine
import MLCore
import MLStore
import MLStudio
@testable import MusicLibrary

// MARK: - Ersatzdienste

/// Bibliothek ohne Datenbank, Player und Fenster.
@MainActor
final class FakeStudioLibrary: StudioLibraryAccess {
    var folders: [LibraryFolder] = []
    var tracks: [Track] = []
    var rescans = 0
    var refreshed: [Int64] = []
    var toasts: [(text: String, action: String?, isError: Bool)] = []
    var shown = 0
    var played: [Int64] = []

    var studioFolders: [LibraryFolder] { folders }
    var studioTracks: [Track] { tracks }
    func studioTrack(_ uid: Int64) -> Track? { tracks.first { $0.uid == uid } }
    func studioRescan() { rescans += 1 }
    func studioRefreshTrack(_ uid: Int64) { refreshed.append(uid) }
    func studioToast(_ text: String, action: String?, isError: Bool, perform: (() -> Void)?) { toasts.append((text, action, isError)) }
    func studioShow() { shown += 1 }
    func studioPlay(uid: Int64) { played.append(uid) }
    func studioObserve(libraryChanged: @escaping @MainActor @Sendable () -> Void, visibilityChanged: @escaping @MainActor @Sendable (Bool) -> Void) -> [AnyCancellable] { [] }
}

/// Exporter, der eine kleine Datei schreibt; einzelne Titel können festgehalten oder zum Scheitern gebracht werden.
/// Er beachtet `PauseGate` und Task-Abbruch wie der echte Exporter (zwischen zwei Blöcken).
final class FakeExporter: AudioExporting, @unchecked Sendable {
    private let lock = NSLock()
    private var held: Set<String> = []
    private var holdEverything = false
    private var failing: Set<String> = []
    private var active = 0
    private(set) var maxActive = 0
    private(set) var requests: [ExportRequest] = []
    var content = Data("EXPORT".utf8)
    /// Dauer im Ergebnis (nil = Länge des Ausschnitts bzw. 120 s).
    var resultDuration: Double?

    func hold(_ titles: String...) { lock.lock(); held.formUnion(titles); lock.unlock() }
    func holdAll(_ on: Bool) { lock.lock(); holdEverything = on; lock.unlock() }
    func release(_ title: String) { lock.lock(); held.remove(title); lock.unlock() }
    func fail(_ title: String) { lock.lock(); failing.insert(title); lock.unlock() }
    func isHeld(_ t: String) -> Bool { lock.lock(); defer { lock.unlock() }; return holdEverything || held.contains(t) }
    var allRequests: [ExportRequest] { lock.lock(); defer { lock.unlock() }; return requests }

    /// Sperre nur in synchronen Hilfen (in `async`-Funktionen ist `NSLock.lock()` nicht erlaubt).
    private func begin(_ request: ExportRequest) -> (fail: Bool, data: Data, duration: Double?) {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
        active += 1
        maxActive = max(maxActive, active)
        return (failing.contains(request.metadata.title), content, resultDuration)
    }

    private func end() { lock.lock(); active -= 1; lock.unlock() }

    func export(_ request: ExportRequest, pause: PauseGate?, progress: @escaping @Sendable (Double) -> Void) async throws -> ExportResult {
        let title = request.metadata.title
        let (shouldFail, data, duration) = begin(request)
        defer { end() }
        for i in 0..<10 {
            await pause?.waitIfPaused()
            if Task.isCancelled { throw StudioError.cancelled }
            while isHeld(title) {
                await pause?.waitIfPaused()
                if Task.isCancelled { throw StudioError.cancelled }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            progress(Double(i + 1) / 10)
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        if shouldFail { throw StudioError.encodeFailed("Testfehler") }
        try data.write(to: request.output)
        return ExportResult(output: request.output, duration: duration ?? request.trim?.length ?? 120, sampleRate: 44_100, channels: 2,
                            bitDepth: nil, bitrateKbps: 320, fileSize: Int64(data.count), tagsWritten: true, passthrough: request.preferPassthrough)
    }
}

struct FakeWaveforms: WaveformProviding {
    func waveform(for file: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> WaveformData {
        progress(1)
        return WaveformData(base: [Float](repeating: -0.5, count: 64), maxs: [Float](repeating: 0.5, count: 64), framesPerBucket: 256,
                            sampleRate: 44_100, duration: 120)
    }
}

/// Lokale Analyse: Titel = Dateiname, Interpret „Lina Hafen“, Dauer 120 s.
struct FakeLocal: LocalSourceAnalyzing {
    var duration: Double = 120
    func analyze(file: URL) async throws -> SourceInfo {
        guard FileManager.default.fileExists(atPath: file.path) else { throw StudioError.decodeFailed("fehlt") }
        let name = file.deletingPathExtension().lastPathComponent
        let ext = file.pathExtension.lowercased()
        return SourceInfo(id: file.path, kind: .localFile, url: file, title: name, duration: duration,
                          suggested: StudioMetadata(title: name, artist: "Lina Hafen", album: "Küste"),
                          codec: ext == "mp3" ? "MP3" : "AAC", bitrateKbps: 256, sampleRate: 44_100, channels: 2, isLossless: false,
                          localFile: file)
    }
}

/// Internet-Quellen ohne Netzwerk.
final class FakeRemote: RemoteSourceProviding, @unchecked Sendable {
    private let lock = NSLock()
    var playlists: [String: (String, [RemotePlaylistEntry])] = [:]
    private(set) var analyzed: [String] = []
    private(set) var downloadCalls = 0
    private(set) var sawPartialFile = false
    private var holdDownloads = false

    func holdDownloads(_ on: Bool) { lock.lock(); holdDownloads = on; lock.unlock() }
    private var isHeld: Bool { lock.lock(); defer { lock.unlock() }; return holdDownloads }

    func info(_ url: URL, kind: SourceKind) -> SourceInfo {
        let name = url.lastPathComponent
        return SourceInfo(id: url.absoluteString, kind: kind, url: url, title: "Band - \(name)", uploader: "Band", duration: 60,
                          suggested: StudioMetadata(title: "Lied \(name)", artist: "Band"), codec: "mp4a.40.2", bitrateKbps: 128)
    }

    private func record(_ url: URL) { lock.lock(); analyzed.append(url.absoluteString); lock.unlock() }

    /// Zählt den Aufruf; true, wenn schon eine Teil-Datei vorlag.
    private func countDownload(part: URL) {
        lock.lock(); defer { lock.unlock() }
        downloadCalls += 1
        if FileManager.default.fileExists(atPath: part.path) { sawPartialFile = true }
    }

    func analyze(url: URL, kind: SourceKind) async throws -> SourceInfo {
        record(url)
        return info(url, kind: kind)
    }

    func lookup(url: URL, kind: SourceKind) async throws -> RemoteLookup {
        if let p = playlists[url.absoluteString] { return .playlist(title: p.0, entries: p.1) }
        return .single(try await analyze(url: url, kind: kind))
    }

    func download(_ source: SourceInfo, into directory: URL, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL {
        if source.kind == .spotify { throw StudioError.spotifyDRM }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let part = directory.appendingPathComponent("audio.m4a.part")
        countDownload(part: part)
        if !FileManager.default.fileExists(atPath: part.path) { try Data("TEIL".utf8).write(to: part) }
        progress(DownloadProgress(fraction: 0.5, bytesDone: 50, bytesTotal: 100))
        while isHeld {
            if Task.isCancelled { throw StudioError.cancelled }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        if Task.isCancelled { throw StudioError.cancelled }
        let file = directory.appendingPathComponent("audio.m4a")
        try FileManager.default.moveItem(at: part, to: file)
        progress(DownloadProgress(fraction: 1))
        return file
    }

    func thumbnail(for source: SourceInfo) async -> Data? { nil }
}

/// Vorhören ohne Audio: merkt sich Aufrufe; Position und Ende setzt der Test.
@MainActor
final class FakePreview: StudioPreviewing {
    var loaded: [URL] = []
    var plays: [(start: Double, end: Double?)] = []
    var pauses = 0
    var stops = 0
    var position: Double = 0
    var isPlaying = false
    var onFinish: (() -> Void)?

    func load(_ file: URL) throws { loaded.append(file) }
    func play(from start: Double, to end: Double?) {
        plays.append((start, end))
        position = start
        isPlaying = true
    }
    func pause() { pauses += 1; isPlaying = false }
    func stop() { stops += 1; isPlaying = false }
    var edits: [TrackEdit?] = []
    func setEdit(_ edit: TrackEdit?, normalizationGainDb: Double?) { edits.append(edit) }
}

struct FakeTools: StudioToolManaging {
    func status() async -> StudioToolStatus { StudioToolStatus(ytDlpPath: "/x/yt-dlp", ytDlpVersion: "2026.10.21", ytDlpOrigin: .managed) }
    func installOrUpdate(progress: @escaping @Sendable (ToolInstallProgress) -> Void) async throws -> StudioToolStatus {
        progress(ToolInstallProgress(step: "Test", fraction: 1))
        return await status()
    }
    func removeManaged() async throws -> StudioToolStatus { StudioToolStatus() }
}

// MARK: - Tests

/// Abläufe des Audio Studios mit Ersatzdiensten: Warteschlange (Reihenfolge, ein aktiver Auftrag, Pause,
/// Abbruch, Wiederholen, Fehler), Verlauf, Ziel und Dateinamen, Doppel-Erkennung, Internet-Quellen und
/// Schneiden vorhandener Songs (neue Datei, Original ersetzen mit Sicherung, Rückgängig).
@MainActor
final class StudioModelTests: XCTestCase {
    private var temp: URL!
    private var out: URL!
    private var exporter: FakeExporter!
    private var remote: FakeRemote!
    private var library: FakeStudioLibrary!
    private var local = FakeLocal()

    override func setUp() async throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("StudioModelTests-\(UUID().uuidString)", isDirectory: true)
        out = temp.appendingPathComponent("Ausgabe", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        exporter = FakeExporter()
        remote = FakeRemote()
        library = FakeStudioLibrary()
        local = FakeLocal()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: temp)
    }

    private func makeModel(support: URL? = nil, defaults: UserDefaults? = nil, preview: StudioPreviewing? = nil,
                           editAnalyzer: any TrackEditAnalyzing = NoTrackEditAnalyzer()) -> StudioModel {
        let services = StudioServiceSet(exporter: exporter, waveforms: FakeWaveforms(), local: local, remote: remote, tools: FakeTools(),
                                        editAnalyzer: editAnalyzer)
        let model = StudioModel(app: nil, services: services, preview: preview, demo: false, library: library,
                                supportDirectory: support ?? temp.appendingPathComponent("Support", isDirectory: true),
                                defaults: defaults ?? UserDefaults(suiteName: "StudioModelTests-\(UUID().uuidString)")!)
        model.settings.importToLibrary = false
        model.settings.saveFolderPath = out.path
        return model
    }

    @discardableResult
    private func file(_ relative: String, _ content: String = "AUDIO") throws -> URL {
        let url = temp.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
        return url
    }

    private func waitUntil(_ what: String, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Zeitüberschreitung: \(what)", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func content(_ path: String) -> String? {
        (try? Data(contentsOf: URL(fileURLWithPath: path))).map { String(decoding: $0, as: UTF8.self) }
    }

    // MARK: Warteschlange

    func testQueueRunsInOrderWithExactlyOneActiveJob() async throws {
        let model = makeModel()
        let files = try ["a", "b", "c"].map { try file("Quelle/\($0).m4a") }
        exporter.holdAll(true)
        model.importFiles(files)
        XCTAssertEqual(model.jobs.count, 3)
        await waitUntil("erster Auftrag wandelt um") { model.jobs[0].phase == .converting }
        XCTAssertEqual(model.jobs.filter { $0.phase.isActive }.count, 1)
        XCTAssertEqual(model.jobs[1].phase, .waiting)
        XCTAssertEqual(model.jobs[2].phase, .waiting)
        exporter.holdAll(false)
        await waitUntil("alle fertig") { model.jobs.allSatisfy { $0.phase == .done } }
        XCTAssertEqual(exporter.maxActive, 1, "nie mehr als ein Export gleichzeitig")
        XCTAssertEqual(exporter.allRequests.map { $0.input.lastPathComponent }, ["a.m4a", "b.m4a", "c.m4a"])
        let finished = model.jobs.compactMap(\.finished)
        XCTAssertEqual(finished, finished.sorted(), "Reihenfolge wie hinzugefügt")
        // Metadaten aus der Analyse, gemeinsames Schema „Interpret – Titel“
        XCTAssertEqual(model.jobs.map { ($0.outputPath as NSString?)?.lastPathComponent },
                       ["Lina Hafen – a.m4a", "Lina Hafen – b.m4a", "Lina Hafen – c.m4a"])
        for job in model.jobs { XCTAssertEqual(content(job.outputPath ?? ""), "EXPORT") }
        XCTAssertEqual(model.history.entries.count, 3)
        XCTAssertTrue(model.history.entries.allSatisfy(\.succeeded))
        XCTAssertEqual(StudioQueueLogic.summary(model.jobs), "3 von 3 fertig")
        // eine Zusammenfassung statt einer Mitteilung je Auftrag
        XCTAssertTrue(library.toasts.contains { $0.text == "3 Aufträge fertig" && $0.action == "Im Finder zeigen" && !$0.isError })
        XCTAssertFalse(library.toasts.contains { $0.text.contains("gespeichert") })
    }

    func testPauseResumeCancelRetry() async throws {
        let model = makeModel()
        let files = try ["a", "b", "c"].map { try file("Quelle/\($0).m4a") }
        exporter.hold("a", "c")
        model.importFiles(files)
        let (a, b, c) = (model.jobs[0].id, model.jobs[1].id, model.jobs[2].id)
        await waitUntil("a wandelt um") { model.job(a)?.phase == .converting }

        // Anhalten während der Umwandlung: der nächste Auftrag läuft
        model.pause(a)
        XCTAssertEqual(model.job(a)?.phase, .paused)
        await waitUntil("b fertig") { model.job(b)?.phase == .done }
        await waitUntil("c wandelt um") { model.job(c)?.phase == .converting }
        XCTAssertEqual(model.job(a)?.phase, .paused)

        // Fortsetzen, während c läuft: a wartet, bis es wieder an der Reihe ist
        model.resume(a)
        XCTAssertEqual(model.job(a)?.phase, .waiting)
        XCTAssertEqual(model.jobs.filter { $0.phase.isActive }.count, 1)

        // Abbrechen von c → a läuft weiter
        model.cancel(c)
        await waitUntil("c abgebrochen") { model.job(c)?.phase == .cancelled }
        await waitUntil("a wandelt wieder um") { model.job(a)?.phase == .converting }
        XCTAssertEqual(model.jobs.filter { $0.phase.isActive }.count, 1)
        exporter.release("a")
        await waitUntil("a fertig") { model.job(a)?.phase == .done }

        // Wiederholen
        exporter.release("c")
        model.retry(c)
        await waitUntil("c fertig") { model.job(c)?.phase == .done }
        XCTAssertNotNil(model.job(c)?.outputPath)

        // Erledigte entfernen
        model.clearFinished()
        XCTAssertTrue(model.jobs.isEmpty)
    }

    func testPauseAndResumeWaitingJobAndRemove() async throws {
        let model = makeModel()
        let files = try ["a", "b", "c"].map { try file("Quelle/\($0).m4a") }
        exporter.hold("a")
        model.importFiles(files)
        let (a, b, c) = (model.jobs[0].id, model.jobs[1].id, model.jobs[2].id)
        await waitUntil("a wandelt um") { model.job(a)?.phase == .converting }
        model.pause(b)
        XCTAssertEqual(model.job(b)?.phase, .paused)
        model.remove(c)
        XCTAssertNil(model.job(c))
        model.remove(a)   // aktiv → nicht entfernbar
        XCTAssertNotNil(model.job(a))
        exporter.release("a")
        await waitUntil("a fertig") { model.job(a)?.phase == .done }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(model.job(b)?.phase, .paused, "angehaltene Aufträge werden übersprungen")
        model.resume(b)
        await waitUntil("b fertig") { model.job(b)?.phase == .done }
    }

    func testFailureMovesOnToNextJob() async throws {
        let model = makeModel()
        let files = try ["a", "b"].map { try file("Quelle/\($0).m4a") }
        exporter.fail("a")
        model.importFiles(files)
        await waitUntil("beide beendet") { model.jobs.allSatisfy { $0.phase.isFinished } }
        XCTAssertEqual(model.jobs[0].phase, .failed)
        XCTAssertTrue(model.jobs[0].error?.contains("Testfehler") ?? false)
        XCTAssertEqual(model.jobs[1].phase, .done)
        XCTAssertEqual(model.history.entries.count, 2)
        XCTAssertEqual(model.history.entries.filter(\.succeeded).count, 1)
        XCTAssertEqual(StudioQueueLogic.summary(model.jobs), "1 von 2 fertig · 1 Fehler")
        XCTAssertTrue(library.toasts.contains { $0.text == "1 von 2 Aufträgen fertig · 1 Fehler" && $0.isError })
    }

    func testSetFormatOfWaitingJob() async throws {
        let model = makeModel()
        let files = try ["a", "b"].map { try file("Quelle/\($0).m4a") }
        exporter.hold("a")
        model.importFiles(files)
        let b = model.jobs[1].id
        model.setFormat(.flac, for: b)
        XCTAssertEqual(model.job(b)?.options.format, .flac)
        exporter.release("a")
        await waitUntil("fertig") { model.jobs.allSatisfy { $0.phase == .done } }
        XCTAssertEqual((model.job(b)?.outputPath as NSString?)?.pathExtension, "flac")
        XCTAssertEqual(exporter.allRequests.last?.options.format, .flac)
    }

    // MARK: Vorhören

    func testPreviewPlaysSelectionAndFollowsPlayhead() async throws {
        let player = FakePreview()
        let model = makeModel(preview: player)
        let src = try file("Quelle/a.m4a")
        model.importFiles([src])
        await waitUntil("Quelle bereit") { model.sourceState == .ready }

        // ganze Datei ab Anfang
        model.togglePreview()
        XCTAssertEqual(player.loaded.map(\.path), [src.path])
        XCTAssertEqual(player.plays.last?.start, 0)
        XCTAssertNil(player.plays.last?.end ?? nil)
        XCTAssertTrue(model.playback.playing)
        player.position = 12.5
        await waitUntil("Abspielkopf folgt") { abs(model.playback.playhead - 12.5) < 0.001 }
        model.togglePreview()
        XCTAssertEqual(player.pauses, 1)
        XCTAssertFalse(model.playback.playing)

        // Auswahl: ab Abspielkopf (liegt in der Auswahl) bis zum Ende der Auswahl
        model.setSelection(start: 10, end: 20)
        model.togglePreview()
        XCTAssertEqual(player.plays.last?.start, 12.5)
        XCTAssertEqual(player.plays.last?.end ?? nil, 20)
        model.seek(to: 15)
        XCTAssertEqual(player.plays.last?.start, 15)
        XCTAssertEqual(player.plays.last?.end ?? nil, 20)
        // Ende erreicht
        player.isPlaying = false
        player.onFinish?()
        XCTAssertFalse(model.playback.playing)
        XCTAssertEqual(model.playback.playhead, 20)
        // Auswahl von Anfang an
        model.previewSelection()
        XCTAssertEqual(player.plays.last?.start, 10)
        XCTAssertEqual(player.loaded.count, 1, "Datei wird nur einmal geladen")

        // Neue bzw. keine Quelle beendet das Vorhören
        let stopsBefore = player.stops
        model.clearSource()
        XCTAssertGreaterThan(player.stops, stopsBefore)
        XCTAssertFalse(model.playback.playing)
        model.togglePreview()
        XCTAssertEqual(player.plays.count, 4, "ohne Quelle nichts abspielen")
    }

    // MARK: Ziel und Dateinamen

    func testFinishedFileGetsFreeName() async throws {
        let model = makeModel()
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let existing = out.appendingPathComponent("Lina Hafen – a.m4a")
        try Data("ALT".utf8).write(to: existing)
        model.importFiles([try file("Quelle/a.m4a"), try file("Quelle/b.m4a")])
        await waitUntil("fertig") { model.jobs.allSatisfy { $0.phase == .done } }
        XCTAssertEqual(model.jobs[0].outputPath, out.appendingPathComponent("Lina Hafen – a (2).m4a").path)
        XCTAssertEqual(content(existing.path), "ALT", "vorhandene Datei bleibt unverändert")
    }

    func testDestinationRules() throws {
        let model = makeModel()
        model.settings.saveFolderPath = nil
        XCTAssertEqual(model.destination, .folder(path: StudioModel.standardSaveFolder))
        XCTAssertTrue(StudioModel.standardSaveFolder.hasSuffix("/Music/Audio Studio"))
        model.settings.saveFolderPath = "/Volumes/Daten/Export"
        XCTAssertEqual(model.destination, .folder(path: "/Volumes/Daten/Export"))

        model.settings.importToLibrary = true
        XCTAssertEqual(model.destination, .folder(path: StudioModel.standardSaveFolder), "ohne Musikordner: ~/Music/Audio Studio")

        func folder(_ id: Int64, _ path: String, enabled: Bool = true) -> LibraryFolder {
            LibraryFolder(id: id, path: path, bookmark: nil, name: (path as NSString).lastPathComponent, addedAt: 0, lastScanAt: nil,
                          volumeName: nil, isExternal: false, enabled: enabled)
        }
        library.folders = [folder(1, "/Musik/Aus", enabled: false), folder(2, "/Musik/Eins"), folder(3, "/Musik/Zwei")]
        XCTAssertEqual(model.destination, .library(folderID: 2, folderPath: "/Musik/Eins", subfolder: "Audio Studio"))
        model.settings.libraryFolderID = 3
        model.settings.librarySubfolder = "Downloads/Neu"
        XCTAssertEqual(model.destination, .library(folderID: 3, folderPath: "/Musik/Zwei", subfolder: "Downloads/Neu"))
        XCTAssertEqual(model.destination?.directoryPath, "/Musik/Zwei/Downloads/Neu")
        model.settings.libraryFolderID = 99
        XCTAssertEqual(model.destination, .library(folderID: 2, folderPath: "/Musik/Eins", subfolder: "Downloads/Neu"))
    }

    func testImportIntoLibraryFolderRescans() async throws {
        let model = makeModel()
        let music = temp.appendingPathComponent("Musik", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        library.folders = [LibraryFolder(id: 1, path: music.path, bookmark: nil, name: "Musik", addedAt: 0, lastScanAt: nil, volumeName: nil,
                                         isExternal: false, enabled: true)]
        model.settings.importToLibrary = true
        model.importFiles([try file("Quelle/a.m4a")])
        await waitUntil("Quelle bereit") { model.sourceState == .ready }
        await waitUntil("Wellenform") { model.waveform != nil }
        let job = try XCTUnwrap(model.addToQueue())
        XCTAssertEqual(job.destination, .library(folderID: 1, folderPath: music.path, subfolder: "Audio Studio"))
        await waitUntil("fertig") { model.job(job.id)?.phase == .done }
        XCTAssertEqual(model.job(job.id)?.outputPath, music.appendingPathComponent("Audio Studio/Lina Hafen – a.m4a").path)
        XCTAssertEqual(library.rescans, 1)
        XCTAssertTrue(model.history.entries.first?.imported ?? false)
        XCTAssertTrue(library.toasts.contains { $0.text.contains("in die Bibliothek übernommen") && $0.action == "Im Finder zeigen" })
    }

    // MARK: Verlauf

    func testHistoryIsSavedAndLoaded() async throws {
        let support = temp.appendingPathComponent("Support", isDirectory: true)
        let model = makeModel(support: support)
        model.importFiles([try file("Quelle/a.m4a"), try file("Quelle/b.m4a")])
        await waitUntil("fertig") { model.jobs.allSatisfy { $0.phase == .done } }
        await model.waitForPendingWrites()
        let json = support.appendingPathComponent("history.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: json.path))

        let reopened = makeModel(support: support)
        await waitUntil("Verlauf geladen") { reopened.history.entries.count == 2 }
        XCTAssertEqual(reopened.history.entries.map(\.id), model.history.entries.map(\.id))
        XCTAssertEqual(reopened.history.entries.map(\.outputPath), model.history.entries.map(\.outputPath))
        XCTAssertEqual(reopened.history.entries.map(\.formatSummary), ["M4A · 320 kbit/s · 44,1 kHz", "M4A · 320 kbit/s · 44,1 kHz"])
        XCTAssertEqual(reopened.history.entries.first?.title, "b", "neueste zuerst")
        XCTAssertNotNil(reopened.history.previousExport(of: try file("Quelle/a.m4a").path))

        reopened.clearHistory(.add)
        await reopened.waitForPendingWrites()
        let saved = try JSONDecoder().decode(StudioHistory.self, from: Data(contentsOf: json))
        XCTAssertTrue(saved.entries.isEmpty)
    }

    func testSettingsAreStoredInInjectedDefaults() throws {
        let defaults = UserDefaults(suiteName: "StudioModelTests-\(UUID().uuidString)")!
        let model = makeModel(defaults: defaults)
        model.setFormat(.mp3)
        model.updateOptions { $0.mp3Bitrate = 192 }
        XCTAssertNotNil(defaults.data(forKey: StudioSettings.userDefaultsKey))
        let again = makeModel(defaults: defaults)
        XCTAssertEqual(again.settings.lastFormat, .mp3)
        XCTAssertEqual(again.options.format, .mp3)
        XCTAssertEqual(again.options.mp3Bitrate, 192)
    }

    // MARK: Doppel-Erkennung

    func testDuplicateCandidatesAndPreviousExport() async throws {
        let model = makeModel()
        library.tracks = [
            Track(uid: 5, path: "/m/Nordlicht.m4a", fileName: "Nordlicht.m4a", title: "Nordlicht", artists: ["Lina Hafen", "Ole"], durationMs: 121_000),
            Track(uid: 6, path: "/m/Nordlicht live.m4a", fileName: "Nordlicht live.m4a", title: "Nordlicht", artists: ["Lina Hafen"], durationMs: 300_000),
        ]
        let src = try file("Quelle/Nordlicht.m4a")
        model.importFiles([src])
        await waitUntil("Quelle bereit") { model.sourceState == .ready }
        await waitUntil("Doppel gefunden") { !model.duplicateCandidates.isEmpty }
        XCTAssertEqual(model.duplicateCandidates.map(\.uid), [5], "gleicher Titel, Interpret und Dauer ±2 s")
        model.metadata.artist = "Andere Band"
        XCTAssertTrue(model.duplicateCandidates.isEmpty)
        model.metadata.artist = "Lina Hafen"

        XCTAssertNil(model.previousExportEntry)
        let job = try XCTUnwrap(model.addToQueue())
        await waitUntil("fertig") { model.job(job.id)?.phase == .done }
        XCTAssertEqual(model.previousExportEntry?.outputPath, model.job(job.id)?.outputPath)
    }

    // MARK: Eingabe und Internet-Quellen

    func testParseInput() throws {
        let f = try file("Quelle/mit Leerzeichen.m4a")
        let parsed = StudioModel.parseInput("""
        https://www.youtube.com/watch?v=aqz-KE-bpKQ https://soundcloud.com/scottbuckley/echoes-cc-by.
          <https://open.spotify.com/track/abc>
        \(f.path)
        kein-link
        https://www.youtube.com/watch?v=aqz-KE-bpKQ
        """)
        XCTAssertEqual(parsed.urls.map { $0.kind }, [.youtube, .soundcloud, .spotify])
        XCTAssertEqual(parsed.urls[1].url.absoluteString, "https://soundcloud.com/scottbuckley/echoes-cc-by")
        XCTAssertEqual(parsed.files.map(\.path), [f.path])
        XCTAssertEqual(parsed.invalid, ["kein-link"])
    }

    func testSingleAddressShowsSourceAndExportDownloads() async throws {
        let model = makeModel()
        model.urlText = "https://soundcloud.com/a/lied"
        model.analyzeInput()
        XCTAssertEqual(model.sourceState, .analyzing("SoundCloud wird abgefragt …"))
        await waitUntil("Quelle bereit") { model.sourceState == .ready }
        XCTAssertEqual(model.source?.kind, .soundcloud)
        XCTAssertEqual(model.prepare, .needed)
        XCTAssertEqual(model.metadata.title, "Lied lied")
        XCTAssertTrue(model.canExport)
        XCTAssertEqual(model.fileNamePreview, "Band – Lied lied.m4a")
        let job = try XCTUnwrap(model.addToQueue())
        await waitUntil("fertig") { model.job(job.id)?.phase == .done }
        XCTAssertEqual(remote.downloadCalls, 1)
        let input = try XCTUnwrap(exporter.allRequests.last?.input)
        XCTAssertTrue(input.path.contains("/Cache/job-"), "geladen in den Arbeitsordner des Auftrags")
        XCTAssertEqual(model.history.entries.first?.source, "https://soundcloud.com/a/lied")
        await model.waitForPendingWrites()
        try await Task.sleep(nanoseconds: 50_000_000)
        await model.waitForPendingWrites()
        XCTAssertFalse(FileManager.default.fileExists(atPath: input.deletingLastPathComponent().path), "Arbeitsordner aufgeräumt")
    }

    func testPrepareForEditingUsesCacheAndCleansUp() async throws {
        let model = makeModel()
        model.urlText = "https://soundcloud.com/a/lied"
        model.analyzeInput()
        await waitUntil("Quelle bereit") { model.sourceState == .ready }
        model.prepareForEditing()
        await waitUntil("geladen") { model.prepare == .ready }
        let cached = try XCTUnwrap(model.source?.localFile)
        XCTAssertTrue(cached.path.contains("/Cache/edit-"))
        await waitUntil("Wellenform") { model.waveform != nil }
        // Auftrag verwendet die geladene Spur (kein zweiter Download)
        let job = try XCTUnwrap(model.addToQueue())
        await waitUntil("fertig") { model.job(job.id)?.phase == .done }
        XCTAssertEqual(remote.downloadCalls, 1)
        model.clearSource()
        XCTAssertNil(model.source)
        XCTAssertEqual(model.sourceState, .empty)
        await model.waitForPendingWrites()
        XCTAssertFalse(FileManager.default.fileExists(atPath: cached.deletingLastPathComponent().path), "Zwischenspeicher gelöscht")
    }

    func testPausingDownloadKeepsPartialFileAndResumes() async throws {
        let model = makeModel()
        remote.holdDownloads(true)
        model.urlText = "https://soundcloud.com/a/1\nhttps://soundcloud.com/a/2"
        model.analyzeInput()
        XCTAssertEqual(model.jobs.count, 2)
        let first = model.jobs[0].id
        await waitUntil("lädt") { model.job(first)?.phase == .downloading && self.remote.downloadCalls == 1 }
        model.pause(first)
        await waitUntil("angehalten") { model.job(first)?.phase == .paused }
        let part = model.jobWorkDirectory(first).appendingPathComponent("audio.m4a.part")
        XCTAssertTrue(FileManager.default.fileExists(atPath: part.path), "Teil-Datei bleibt")
        model.cancel(model.jobs[1].id)
        remote.holdDownloads(false)
        model.resume(first)
        await waitUntil("fertig") { model.job(first)?.phase == .done }
        XCTAssertTrue(remote.sawPartialFile, "Fortsetzen findet die Teil-Datei")
        XCTAssertEqual(model.job(first)?.metadata.title, "Lied 1", "Metadaten aus der Analyse")
    }

    func testPlaylistAndMultipleAddressesBecomeJobs() async throws {
        let model = makeModel()
        remote.playlists["https://soundcloud.com/a/sets/frei"] = ("Freies Set", (1...3).map {
            RemotePlaylistEntry(url: URL(string: "https://soundcloud.com/a/t\($0)")!, title: "Titel \($0)")
        })
        model.urlText = "https://soundcloud.com/a/sets/frei"
        model.analyzeInput()
        await waitUntil("Aufträge") { model.jobs.count == 3 }
        XCTAssertEqual(model.jobs.map { $0.source.url.lastPathComponent }, ["t1", "t2", "t3"])
        XCTAssertTrue(library.toasts.contains { $0.text.contains("3 Titel aus „Freies Set“") })
        await waitUntil("fertig") { model.jobs.allSatisfy { $0.phase == .done } }
        XCTAssertEqual(model.jobs.map(\.fileName), ["Band – Lied t1", "Band – Lied t2", "Band – Lied t3"])

        // mehrere Adressen; Spotify wird übersprungen (DRM)
        model.urlText = "https://soundcloud.com/b/1\nhttps://soundcloud.com/b/2 https://open.spotify.com/track/x"
        model.analyzeInput()
        XCTAssertEqual(model.jobs.count, 5)
        XCTAssertTrue(library.toasts.contains { $0.text.contains("Spotify") && $0.isError })
        await waitUntil("fertig") { model.jobs.allSatisfy { $0.phase == .done } }
    }

    func testSpotifyShowsMetadataButCannotExport() async throws {
        let model = makeModel()
        model.urlText = "https://open.spotify.com/track/abc"
        model.analyzeInput()
        await waitUntil("Quelle") { model.sourceState == .ready }
        XCTAssertEqual(model.source?.kind, .spotify)
        XCTAssertEqual(model.prepare, .notNeeded)
        XCTAssertFalse(model.canExport)
        XCTAssertNil(model.addToQueue())
    }

    // MARK: Schneiden vorhandener Songs

    private func libraryTrack() throws -> (music: URL, path: URL) {
        let music = temp.appendingPathComponent("Musik", isDirectory: true)
        let path = try file("Musik/Lina Hafen/Nordlicht.mp3", "ORIGINAL-AUDIO")
        library.folders = [LibraryFolder(id: 1, path: music.path, bookmark: nil, name: "Musik", addedAt: 0, lastScanAt: nil, volumeName: nil,
                                         isExternal: false, enabled: true)]
        library.tracks = [Track(uid: 7, folderID: 1, path: path.path, relativePath: "Lina Hafen/", fileName: "Nordlicht.mp3", title: "Nordlicht",
                                artists: ["Lina Hafen"], durationMs: 120_000)]
        return (music, path)
    }

    func testCutLibraryTrackAsNewFileNextToOriginal() async throws {
        let model = makeModel()
        let (music, original) = try libraryTrack()
        model.openLibraryTrack(7)
        XCTAssertEqual(library.shown, 1)
        await waitUntil("Titel bereit") { model.sourceState == .ready }
        XCTAssertTrue(model.isLibraryTrack)
        XCTAssertTrue(model.keepOriginalFormat)
        XCTAssertEqual(model.options.format, .mp3)
        XCTAssertEqual(model.options.mp3Bitrate, 256)
        XCTAssertEqual(model.cutSaveMode, .newFile)
        XCTAssertEqual(model.fileNameBase, "Nordlicht (Ausschnitt)")
        XCTAssertEqual(model.destination, .library(folderID: 1, folderPath: music.path, subfolder: "Lina Hafen"))
        await waitUntil("Wellenform") { model.waveform != nil }
        XCTAssertTrue(model.exportWholeFile)

        model.setSelection(start: 10, end: 40)
        let job = try XCTUnwrap(model.addToQueue())
        XCTAssertTrue(job.preferPassthrough)
        await waitUntil("fertig") { model.job(job.id)?.phase == .done }
        XCTAssertEqual(model.job(job.id)?.outputPath, music.appendingPathComponent("Lina Hafen/Nordlicht (Ausschnitt).mp3").path)
        let request = try XCTUnwrap(exporter.allRequests.last)
        XCTAssertEqual(request.copyTagsFrom?.path, original.path)
        XCTAssertEqual(request.trim, TrimRange(start: 10, end: 40))
        XCTAssertTrue(request.preferPassthrough)
        XCTAssertEqual(content(original.path), "ORIGINAL-AUDIO", "Original unverändert")
        XCTAssertEqual(library.rescans, 1)

        // Blenden erzwingen Neukodierung
        model.fadeIn = 2
        let faded = try XCTUnwrap(model.addToQueue())
        XCTAssertFalse(faded.preferPassthrough)
        await waitUntil("fertig") { model.job(faded.id)?.phase == .done }
        XCTAssertEqual(model.job(faded.id)?.outputPath, music.appendingPathComponent("Lina Hafen/Nordlicht (Ausschnitt) (2).mp3").path)

        // Anderes Format → nicht mehr „wie Original“
        model.setFormat(.wav)
        XCTAssertFalse(model.keepOriginalFormat)
        XCTAssertEqual(model.options.format, .wav)
        model.keepOriginalFormat = true
        XCTAssertEqual(model.options.format, .mp3)
    }

    func testReplaceOriginalWithBackupAndUndo() async throws {
        let support = temp.appendingPathComponent("Support", isDirectory: true)
        let model = makeModel(support: support)
        let (_, original) = try libraryTrack()
        model.openLibraryTrack(7)
        await waitUntil("Titel bereit") { model.sourceState == .ready }
        model.setSelection(start: 10, end: 40)
        model.cutSaveMode = .replaceOriginal
        XCTAssertEqual(model.destination, .replaceOriginal(uid: 7, path: original.path))
        exporter.content = Data("NEUE-AUDIO".utf8)
        let job = try XCTUnwrap(model.addToQueue())
        await waitUntil("fertig") { model.job(job.id)?.phase == .done }

        XCTAssertEqual(content(original.path), "NEUE-AUDIO")
        let entry = try XCTUnwrap(model.history.entries.first)
        let backup = try XCTUnwrap(entry.backupPath)
        XCTAssertTrue(backup.hasPrefix(support.appendingPathComponent("Backups").path))
        XCTAssertEqual(content(backup), "ORIGINAL-AUDIO", "Sicherung des Originals")
        XCTAssertEqual(library.refreshed, [7])
        XCTAssertTrue(library.toasts.contains { $0.action == "Rückgängig" })
        XCTAssertEqual(entry.outputPath, original.path)
        // keine Reste neben dem Original
        let siblings = try FileManager.default.contentsOfDirectory(atPath: original.deletingLastPathComponent().path)
        XCTAssertEqual(siblings, ["Nordlicht.mp3"])

        model.undoReplace(entry.id)
        await waitUntil("rückgängig") { model.history.entries.first?.undone == true }
        XCTAssertEqual(content(original.path), "ORIGINAL-AUDIO")
        XCTAssertEqual(library.refreshed, [7, 7])
        await model.waitForPendingWrites()
        let saved = try JSONDecoder().decode(StudioHistory.self, from: Data(contentsOf: support.appendingPathComponent("history.json")))
        XCTAssertEqual(saved.entries.first?.undone, true)
    }

    // MARK: Arbeitsbereiche (2.4)

    /// Studio-Modell, das Warteschlange, Verlauf und Einstellungen an `host` („Hinzufügen“) abgibt.
    private func makeStudio(host: StudioModel) -> StudioModel {
        let services = StudioServiceSet(exporter: exporter, waveforms: FakeWaveforms(), local: local, remote: remote, tools: FakeTools(),
                                        editAnalyzer: NoTrackEditAnalyzer())
        return StudioModel(app: nil, services: services, preview: nil, demo: false, library: library,
                           supportDirectory: host.supportDirectory, defaults: host.defaults, workspace: .edit, queueHost: host)
    }

    func testStudioQueuesOnHostAndShowsOnlyItsOwnJobsAndHistory() async throws {
        let support = temp.appendingPathComponent("Support", isDirectory: true)
        let adder = makeModel(support: support)
        let studio = makeStudio(host: adder)
        let (music, _) = try libraryTrack()

        // „Hinzufügen“: eine Datei umwandeln
        adder.importFiles([try file("Quelle/a.m4a")])
        await waitUntil("Datei bereit") { adder.sourceState == .ready }
        let first = try XCTUnwrap(adder.addToQueue())
        await waitUntil("Datei fertig") { adder.job(first.id)?.phase == .done }

        // Studio: Bibliothekstitel schneiden → Auftrag landet in der gemeinsamen Warteschlange
        studio.openLibraryTrack(7)
        await waitUntil("Titel bereit") { studio.sourceState == .ready }
        studio.setSelection(start: 10, end: 40)
        let job = try XCTUnwrap(studio.addToQueue())
        XCTAssertTrue(studio.jobs.isEmpty, "das Studio führt keine eigene Warteschlange")
        XCTAssertEqual(adder.jobs.count, 2)
        await waitUntil("Schnitt fertig") { adder.job(job.id)?.phase == .done }
        XCTAssertEqual(adder.job(job.id)?.outputPath, music.appendingPathComponent("Lina Hafen/Nordlicht (Ausschnitt).mp3").path)

        XCTAssertEqual(studio.visibleJobs.map(\.id), [job.id])
        XCTAssertEqual(adder.visibleJobs.count, 1)
        XCTAssertNotEqual(adder.visibleJobs.first?.id, job.id)
        XCTAssertEqual(studio.visibleHistory.map(\.title), ["Nordlicht"])
        XCTAssertEqual(studio.visibleHistory.first?.fromLibrary, true)
        XCTAssertEqual(adder.visibleHistory.map(\.title), ["a"])
        XCTAssertEqual(adder.visibleHistory.first?.fromLibrary, false)

        // Erledigte entfernen und Verlauf löschen betreffen nur den eigenen Bereich
        studio.clearFinished()
        XCTAssertEqual(adder.jobs.count, 1)
        XCTAssertTrue(studio.visibleJobs.isEmpty)
        adder.clearHistory(.edit)
        XCTAssertEqual(adder.history.entries.map(\.title), ["a"])
        await adder.waitForPendingWrites()
        let saved = try JSONDecoder().decode(StudioHistory.self, from: Data(contentsOf: support.appendingPathComponent("history.json")))
        XCTAssertEqual(saved.entries.map(\.title), ["a"])
    }

    func testKICreationGoesThroughAddQueueWithMetadata() async throws {
        let adder = makeModel()
        let studio = makeStudio(host: adder)
        let creation = try file("KI-Musik/Sommerabend am See.flac")
        // Aus einem beliebigen Bereich aufgerufen – der Auftrag landet in der Warteschlange von „Hinzufügen“
        studio.importKICreation(file: creation, title: "Sommerabend am See", genre: "Pop")
        await waitUntil("eingereiht") { adder.jobs.count == 1 }
        let job = try XCTUnwrap(adder.jobs.first)
        XCTAssertEqual(job.metadata.title, "Sommerabend am See")
        XCTAssertEqual(job.metadata.artist, "KI-Musik")
        XCTAssertEqual(job.metadata.genre, "Pop")
        XCTAssertNil(job.source.libraryUid)
        XCTAssertTrue(StudioWorkspace.add.includes(job))
        await waitUntil("fertig") { adder.job(job.id)?.phase == .done }
        XCTAssertEqual(content(creation.path), "AUDIO", "Kreation selbst bleibt unverändert")
        XCTAssertTrue(library.toasts.contains { $0.text.contains("wird in die Bibliothek übernommen") })
    }

    func testStudioSharesSettingsWithHost() async throws {
        let defaults = UserDefaults(suiteName: "StudioModelTests-\(UUID().uuidString)")!
        let adder = makeModel(defaults: defaults)
        let studio = makeStudio(host: adder)
        XCTAssertEqual(studio.settings, adder.settings)

        studio.settings.revealAfterExport = true
        XCTAssertTrue(adder.settings.revealAfterExport, "Änderung im Studio geht an „Hinzufügen“")
        let stored = StudioSettings.decode(defaults.data(forKey: StudioSettings.userDefaultsKey))
        XCTAssertTrue(stored.revealAfterExport, "gespeichert wird einmal, bei „Hinzufügen“")

        adder.settings.librarySubfolder = "Neu"
        await waitUntil("zurückgespiegelt") { studio.settings.librarySubfolder == "Neu" }
        XCTAssertEqual(studio.settings, adder.settings)
    }

    func testUndoIsRefusedWhenFileChangedAfterReplace() async throws {
        let model = makeModel()
        let (_, original) = try libraryTrack()
        model.openLibraryTrack(7)
        await waitUntil("Titel bereit") { model.sourceState == .ready }
        model.setSelection(start: 0, end: 30)
        model.cutSaveMode = .replaceOriginal
        exporter.content = Data("NEUE-AUDIO".utf8)
        let job = try XCTUnwrap(model.addToQueue())
        await waitUntil("fertig") { model.job(job.id)?.phase == .done }
        try Data("SPÄTER-GEÄNDERT".utf8).write(to: original)
        let entry = try XCTUnwrap(model.history.entries.first)
        model.undoReplace(entry.id)
        await waitUntil("Meldung") { self.library.toasts.contains { $0.isError && $0.text.contains("verändert") } }
        XCTAssertEqual(content(original.path), "SPÄTER-GEÄNDERT", "spätere Änderungen bleiben")
        XCTAssertEqual(model.history.entries.first?.undone, false)
    }

    func testReplaceIsAbortedWhenExportHasWrongLength() async throws {
        let support = temp.appendingPathComponent("Support", isDirectory: true)
        let model = makeModel(support: support)
        let (_, original) = try libraryTrack()
        model.openLibraryTrack(7)
        await waitUntil("Titel bereit") { model.sourceState == .ready }
        model.setSelection(start: 10, end: 40)
        model.cutSaveMode = .replaceOriginal
        exporter.resultDuration = 5
        let job = try XCTUnwrap(model.addToQueue())
        await waitUntil("beendet") { model.job(job.id)?.phase == .failed }
        XCTAssertTrue(model.job(job.id)?.error?.contains("Original bleibt unverändert") ?? false)
        XCTAssertEqual(content(original.path), "ORIGINAL-AUDIO")
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent("Backups").path), "keine Sicherung nötig")
        XCTAssertTrue(library.refreshed.isEmpty)
    }

    func testReplaceRequiresOriginalFormat() async throws {
        let model = makeModel()
        _ = try libraryTrack()
        model.openLibraryTrack(7)
        await waitUntil("Titel bereit") { model.sourceState == .ready }
        model.cutSaveMode = .replaceOriginal
        XCTAssertNotNil(model.destination)
        model.keepOriginalFormat = false
        XCTAssertEqual(model.cutSaveMode, .newFile, "Ersetzen nur im Format des Originals")
        model.cutSaveMode = .replaceOriginal
        XCTAssertTrue(model.keepOriginalFormat)
        XCTAssertEqual(model.options.format, .mp3)
        model.clearSource()
        XCTAssertFalse(model.isLibraryTrack)
        XCTAssertEqual(model.cutSaveMode, .newFile)
    }

    // MARK: Titel bearbeiten (2.3)

    private static let analysis = TrackAnalysis(reference: 441.9, referenceConfidence: 0.8, keyTonic: 9, keyScale: .minor, keyCorrelation: 0.8,
                                                loudness: -9, peakDb: -0.1, leadingSilence: 0.4, trailingSilence: 1.2)

    func testEditTrackReplacesOriginalAndUndo() async throws {
        let support = temp.appendingPathComponent("Support", isDirectory: true)
        let preview = FakePreview()
        let model = makeModel(support: support, preview: preview, editAnalyzer: NoTrackEditAnalyzer(result: Self.analysis))
        let (_, original) = try libraryTrack()
        model.openTrackEditor(7)
        XCTAssertEqual(library.shown, 1)
        await waitUntil("bereit") { model.sourceState == .ready && model.mode == .edit }
        XCTAssertEqual(model.cutSaveMode, .replaceOriginal, "Bearbeiten ersetzt standardmäßig das Original")
        await waitUntil("Analyse") { model.trackAnalysis != nil }
        // Erkannter Kammerton als Ausgangswert (unverändert), erkannte Tonart für Auto-Tune
        XCTAssertEqual(model.trackEdit.tuningFrom, 441.9)
        XCTAssertEqual(model.trackEdit.tuningTo, 441.9)
        XCTAssertEqual(model.trackEdit.autoTuneKey, 9)
        XCTAssertEqual(model.trackEdit.autoTuneScale, .minor)
        XCTAssertTrue(model.trackEdit.isNeutral)
        XCTAssertNil(model.activeTrackEdit)

        model.setTuningTarget(432)
        model.trackEdit.speed = 1.25
        XCTAssertEqual(model.fileNameBase, "Nordlicht")
        XCTAssertEqual(model.editedDuration, 96, accuracy: 0.001)
        XCTAssertEqual(model.passthroughBadge, nil, "MP3 wird für die Bearbeitung neu kodiert")
        await waitUntil("Vorhören bekommt die Bearbeitung") { preview.edits.last??.speed == 1.25 }
        model.previewEdited = false
        XCTAssertEqual(preview.edits.last ?? nil, nil, "Original vorhören")
        model.previewEdited = true

        exporter.content = Data("BEARBEITET".utf8)
        exporter.resultDuration = 96
        let job = try XCTUnwrap(model.addToQueue())
        XCTAssertFalse(job.preferPassthrough)
        XCTAssertEqual(job.edit?.speed, 1.25)
        XCTAssertEqual(job.edit?.tuningTo, 432)
        await waitUntil("fertig") { model.job(job.id)?.phase == .done }
        let request = try XCTUnwrap(exporter.allRequests.last)
        XCTAssertEqual(request.edit?.speed, 1.25)
        XCTAssertEqual(request.copyTagsFrom?.path, original.path, "Tags, Cover und Liedtexte des Originals")
        XCTAssertEqual(content(original.path), "BEARBEITET")
        let entry = try XCTUnwrap(model.history.entries.first)
        XCTAssertTrue(entry.formatSummary.contains("Tempo 1,25×"), entry.formatSummary)
        XCTAssertTrue(entry.formatSummary.contains("441,9 → 432 Hz"), entry.formatSummary)
        XCTAssertEqual(library.refreshed, [7])

        model.undoReplace(entry.id)
        await waitUntil("rückgängig") { model.history.entries.first?.undone == true }
        XCTAssertEqual(content(original.path), "ORIGINAL-AUDIO")
    }

    func testEditedReplaceChecksLengthWithTempoAndSilence() async throws {
        let model = makeModel()
        let (_, original) = try libraryTrack()
        model.openTrackEditor(7)
        await waitUntil("bereit") { model.sourceState == .ready && model.mode == .edit }
        model.trackEdit.speed = 1.25
        exporter.resultDuration = 120   // unverändert lang → falsch
        let wrong = try XCTUnwrap(model.addToQueue())
        await waitUntil("abgebrochen") { model.job(wrong.id)?.phase == .failed }
        XCTAssertEqual(content(original.path), "ORIGINAL-AUDIO")

        // „Stille entfernen“ darf kürzen
        model.trackEdit.speed = 1
        model.trackEdit.enhance = true
        exporter.resultDuration = 117.5
        exporter.content = Data("VERBESSERT".utf8)
        let ok = try XCTUnwrap(model.addToQueue())
        await waitUntil("fertig") { model.job(ok.id)?.phase == .done }
        XCTAssertEqual(content(original.path), "VERBESSERT")
    }

    func testLeavingEditModeAndNewSourceResetEdit() async throws {
        let model = makeModel()
        _ = try libraryTrack()
        model.openTrackEditor(7)
        await waitUntil("bereit") { model.sourceState == .ready && model.mode == .edit }
        model.trackEdit.semitones = 3
        model.leaveEditMode()
        XCTAssertEqual(model.mode, .convert)
        model.cutSaveMode = .newFile
        let job = try XCTUnwrap(model.addToQueue())
        XCTAssertNil(job.edit, "Schneiden ohne Klangbearbeitung")
        XCTAssertTrue(job.preferPassthrough)
        XCTAssertEqual(model.fileNameBase, "Nordlicht (Ausschnitt)")
        model.enterEditMode()
        XCTAssertEqual(model.trackEdit.semitones, 3, "Einstellungen bleiben beim Umschalten")
        XCTAssertEqual(model.cutSaveMode, .replaceOriginal)
        model.cutSaveMode = .newFile
        XCTAssertEqual(model.fileNameBase, "Nordlicht (bearbeitet)")
        // Neue Quelle: alles zurück
        let other = try file("Musik/Anderer.wav")
        model.importFiles([other])
        await waitUntil("andere Quelle") { model.source?.url == other && model.sourceState == .ready }
        XCTAssertEqual(model.mode, .convert)
        XCTAssertTrue(model.trackEdit.isNeutral)
        XCTAssertNil(model.trackAnalysis)
    }
}
