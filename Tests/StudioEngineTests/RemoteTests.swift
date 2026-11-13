import XCTest
import ImageIO
import MLStudio
@testable import StudioEngine

/// Internet-Quellen ohne Netzwerk: Fortschritt, Fehlertexte, Prüfsummen, Werkzeugsuche und -installation
/// (mit lokalen Dateien), Prozessabbruch, Spotify (DRM) und ein Ersatz-yt-dlp als Shell-Skript.
final class RemoteTests: XCTestCase {
    private var temp: URL!

    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("RemoteTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temp)
    }

    // MARK: Hilfen

    @discardableResult
    private func script(_ dir: URL, _ name: String, _ body: String) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: url.path)
        return url
    }

    private func dir(_ name: String) -> URL { temp.appendingPathComponent(name, isDirectory: true) }

    // MARK: Fortschritt

    func testProgressLinesAreParsed() {
        let p = YtDlpOutput.parseProgress("ML-PROGRESS downloading 1048576 4194304 NA 524288.5 6 NA NA")
        XCTAssertEqual(p?.fraction ?? -1, 0.25, accuracy: 1e-9)
        XCTAssertEqual(p?.bytesDone, 1_048_576)
        XCTAssertEqual(p?.bytesTotal, 4_194_304)
        XCTAssertEqual(p?.bytesPerSecond ?? 0, 524_288.5, accuracy: 1e-6)
        XCTAssertEqual(p?.etaSeconds, 6)

        // nur geschätzte Größe
        XCTAssertEqual(YtDlpOutput.parseProgress("ML-PROGRESS downloading 100 NA 400 NA NA NA NA")?.fraction ?? -1, 0.25, accuracy: 1e-9)
        // HLS-Fragmente ohne Größe
        XCTAssertEqual(YtDlpOutput.parseProgress("ML-PROGRESS downloading 5000 NA NA 1000 NA 3 12")?.fraction ?? -1, 0.25, accuracy: 1e-9)
        // fertig
        XCTAssertEqual(YtDlpOutput.parseProgress("ML-PROGRESS finished 4194304 4194304 NA NA NA NA NA")?.fraction, 1)
        // unbekannt
        let unknown = YtDlpOutput.parseProgress("ML-PROGRESS downloading 10 NA NA NA NA NA NA")
        XCTAssertNotNil(unknown)
        XCTAssertNil(unknown?.fraction)
        XCTAssertEqual(unknown?.bytesDone, 10)
        // andere Zeilen
        XCTAssertNil(YtDlpOutput.parseProgress("[download]  10.0% of 3.50MiB at 1.00MiB/s ETA 00:03"))
        XCTAssertNil(YtDlpOutput.parseProgress("/tmp/x/abc.m4a"))
    }

    func testProgressTemplateHasAllFields() {
        let t = YtDlpOutput.progressTemplate
        XCTAssertTrue(t.hasPrefix("download:\(YtDlpOutput.progressPrefix) "))
        for field in ["status", "downloaded_bytes", "total_bytes", "total_bytes_estimate", "speed", "eta", "fragment_index", "fragment_count"] {
            XCTAssertTrue(t.contains("%(progress.\(field))s"), field)
        }
    }

    func testArguments() {
        let url = URL(string: "https://www.youtube.com/watch?v=aqz-KE-bpKQ")!
        let a = YtDlpOutput.analyzeArguments(url: url, kind: .youtube, cacheDirectory: URL(fileURLWithPath: "/tmp/c"), denoPath: "/x/deno")
        for flag in ["-J", "--flat-playlist", "--skip-download", "--no-playlist", "--ignore-config", "--no-warnings", "--cache-dir", "--js-runtimes", "deno:/x/deno"] {
            XCTAssertTrue(a.contains(flag), flag)
        }
        XCTAssertEqual(a.suffix(2), ["--", url.absoluteString])

        let d = YtDlpOutput.downloadArguments(url: url, kind: .soundcloud, directory: URL(fileURLWithPath: "/tmp/d"), cacheDirectory: nil,
                                              denoPath: "/x/deno", convertWith: nil)
        for flag in ["--newline", "--progress", "--progress-template", "--print", "after_move:filepath", "--continue", "--no-mtime", "--no-cache-dir", "-P", "/tmp/d"] {
            XCTAssertTrue(d.contains(flag), flag)
        }
        XCTAssertFalse(d.contains("--js-runtimes"), "JavaScript-Laufzeit nur für YouTube")
        XCTAssertFalse(d.contains("-x"))
        let i = d.firstIndex(of: "-f")!
        XCTAssertEqual(d[i + 1], "bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/bestaudio[ext=mp3]/bestaudio/best[acodec!=none][height<=?720]/best[acodec!=none]/best")
        XCTAssertEqual(d[d.firstIndex(of: "--concurrent-fragments")! + 1], "4")

        let c = YtDlpOutput.downloadArguments(url: url, kind: .youtube, directory: URL(fileURLWithPath: "/tmp/d"), cacheDirectory: nil,
                                              denoPath: "/x/deno", convertWith: "/opt/homebrew/bin/ffmpeg")
        XCTAssertTrue(c.contains("--ffmpeg-location"))
        XCTAssertTrue(c.contains("-x"))
        XCTAssertTrue(c.contains("wav"))
        XCTAssertTrue(c.contains("deno:/x/deno"))
        // keine Cookies, keine Anmeldung
        for forbidden in ["--cookies", "--cookies-from-browser", "--username", "--password", "--age-limit"] {
            XCTAssertFalse((a + d + c).contains(forbidden), forbidden)
        }
    }

    // MARK: Fehlertexte

    func testErrorMapping() {
        func map(_ text: String, _ kind: SourceKind = .youtube) -> StudioError { YtDlpOutput.mapError(text, kind: kind) }
        XCTAssertEqual(map("ERROR: [youtube] abc: Sign in to confirm your age. This video may be inappropriate for some users."), .ageRestricted)
        XCTAssertEqual(map("ERROR: [youtube] abc: Private video. Sign in if you've been granted access to this video"), .privateContent)
        XCTAssertEqual(map("ERROR: [youtube] abc: Video unavailable. The uploader has not made this video available in your country"), .geoBlocked)
        XCTAssertEqual(map("ERROR: [youtube] abc: This live event will begin in 3 hours."), .liveStream)
        XCTAssertEqual(map("ERROR: [youtube] abc: Join this channel to get access to members-only content like this video, and other exclusive perks."), .loginRequired)
        XCTAssertEqual(map("ERROR: [vimeo] 1: This video requires authentication. Use --cookies"), .loginRequired)
        XCTAssertEqual(map("ERROR: [youtube] abc: Video unavailable"), .unavailable("Video unavailable"))
        // Instagram: „Requested content is not available, rate-limit reached or login required“ verständlich erklären
        if case .unavailable(let text) = map("ERROR: [Instagram] Dbn: Requested content is not available, rate-limit reached or login required. Use --cookies, --cookies-from-browser, --username and --password, --netrc-cmd, or --netrc (instagram) to provide account credentials", .web) {
            XCTAssertTrue(text.contains("Instagram") && text.contains("später"), text)
        } else { XCTFail("Instagram-Sperre falsch zugeordnet") }
        XCTAssertEqual(map("ERROR: [Instagram] abc: There is no video in this post", .web), .unavailable("Dieser Beitrag enthält kein Video und damit keinen Ton."))
        XCTAssertEqual(map("ERROR: [soundcloud] 1: Unable to download JSON metadata: HTTP Error 404: Not Found", .soundcloud),
                       .unavailable("Unable to download JSON metadata: HTTP Error 404: Not Found"))
        if case .network = map("ERROR: Unable to download webpage: <urlopen error [Errno 8] nodename nor servname provided, or not known>") {} else {
            XCTFail("Netzwerkfehler erwartet")
        }
        XCTAssertEqual(map("ERROR: Unsupported URL: https://example.com/"), .unsupportedURL)
        XCTAssertEqual(map("ERROR: unable to write data: [Errno 28] No space left on device"), .diskFull)
        XCTAssertEqual(map("ERROR: [soundcloud] 1: This track is only available as a preview", .soundcloud), .previewOnly)
        // Bot-Prüfung von YouTube: ehrlich benennen, nicht umgehen
        if case .unavailable(let text) = map("ERROR: [youtube] abc: Sign in to confirm you’re not a bot. Use --cookies-from-browser or --cookies for the authentication.") {
            XCTAssertTrue(text.contains("Bot"))
        } else {
            XCTFail("Bot-Prüfung erwartet")
        }
        if case .other(let text) = map("ERROR: Postprocessing: ffprobe and ffmpeg not found. Please install or provide the path using --ffmpeg-location") {
            XCTAssertTrue(text.contains("FFmpeg"))
        } else {
            XCTFail("FFmpeg-Hinweis erwartet")
        }
        XCTAssertEqual(map("ERROR: something odd happened"), .other("yt-dlp: something odd happened"))
        XCTAssertEqual(map(""), .other("yt-dlp ist mit einem Fehler beendet worden."))
    }

    func testLastErrorLine() {
        XCTAssertEqual(YtDlpOutput.lastErrorLine("WARNING: [youtube] x\nERROR: [youtube] abc: Video unavailable\n"), "Video unavailable")
        XCTAssertEqual(YtDlpOutput.lastErrorLine("ERROR: Unsupported URL: https://a.b/"), "Unsupported URL: https://a.b/")
        XCTAssertNil(YtDlpOutput.lastErrorLine(""))
    }

    func testNeedsConversion() {
        XCTAssertFalse(YtDlpOutput.needsConversion(codec: "mp4a.40.2", ext: "m4a"))
        XCTAssertFalse(YtDlpOutput.needsConversion(codec: "mp3", ext: "mp3"))
        XCTAssertTrue(YtDlpOutput.needsConversion(codec: "opus", ext: nil))
        XCTAssertTrue(YtDlpOutput.needsConversion(codec: nil, ext: "webm"))
        XCTAssertFalse(YtDlpOutput.needsConversion(codec: "vorbis", ext: "ogg"))
        XCTAssertFalse(YtDlpOutput.needsConversion(codec: nil, ext: nil))
    }

    // MARK: Analyse-Antworten

    func testParseSingleVideo() throws {
        let json = """
        {"id":"aqz-KE-bpKQ","title":"Big Buck Bunny 60fps 4K - Official Blender Foundation Short Film","uploader":"Blender","channel":"Blender",
         "duration":634.5,"thumbnail":"https://i.ytimg.com/vi/aqz-KE-bpKQ/maxresdefault.webp","webpage_url":"https://www.youtube.com/watch?v=aqz-KE-bpKQ",
         "acodec":"mp4a.40.2","abr":129.5,"asr":44100,"audio_channels":2,"ext":"m4a","format_id":"140","upload_date":"20141110","live_status":"not_live"}
        """
        guard case .single(let info) = try YtDlpSourceProvider.parseLookup(Data(json.utf8), kind: .youtube,
                                                                          requestedURL: URL(string: "https://youtu.be/aqz-KE-bpKQ")!) else {
            return XCTFail("einzelner Titel erwartet")
        }
        XCTAssertEqual(info.url.absoluteString, "https://www.youtube.com/watch?v=aqz-KE-bpKQ")
        XCTAssertEqual(info.duration, 634.5)
        XCTAssertEqual(info.codec, "mp4a.40.2")
        XCTAssertEqual(info.bitrateKbps, 130)
        XCTAssertEqual(info.sampleRate, 44100)
        XCTAssertEqual(info.suggested.artist, "Big Buck Bunny 60fps 4K")
        XCTAssertEqual(info.suggested.year, 2014)
        XCTAssertFalse(info.isLive)
    }

    func testParsePlaylistAndPreview() throws {
        let playlist = """
        {"_type":"playlist","id":"PL1","title":"Freie Musik","entries":[
          {"id":"aaaaaaaaaaa","url":"https://www.youtube.com/watch?v=aaaaaaaaaaa","title":"Eins","duration":61},
          {"id":"bbbbbbbbbbb","url":"bbbbbbbbbbb","ie_key":"Youtube","title":"Zwei"},
          {"id":"aaaaaaaaaaa","url":"https://www.youtube.com/watch?v=aaaaaaaaaaa","title":"Eins doppelt"},
          {"id":"x","url":"javascript:alert(1)"}]}
        """
        guard case .playlist(let title, let entries) = try YtDlpSourceProvider.parseLookup(Data(playlist.utf8), kind: .youtube,
                                                                                          requestedURL: URL(string: "https://www.youtube.com/playlist?list=PL1")!) else {
            return XCTFail("Playlist erwartet")
        }
        XCTAssertEqual(title, "Freie Musik")
        XCTAssertEqual(entries.map(\.url.absoluteString), ["https://www.youtube.com/watch?v=aaaaaaaaaaa", "https://www.youtube.com/watch?v=bbbbbbbbbbb"])
        XCTAssertEqual(entries.first?.title, "Eins")
        XCTAssertEqual(entries.first?.duration, 61)

        // höchstens 200 Einträge
        let many = (0..<250).map { "{\"id\":\"\($0)\",\"url\":\"https://soundcloud.com/a/t\($0)\"}" }.joined(separator: ",")
        guard case .playlist(_, let capped) = try YtDlpSourceProvider.parseLookup(Data("{\"_type\":\"playlist\",\"title\":\"Set\",\"entries\":[\(many)]}".utf8),
                                                                                 kind: .soundcloud, requestedURL: URL(string: "https://soundcloud.com/a/sets/s")!) else {
            return XCTFail("Playlist erwartet")
        }
        XCTAssertEqual(capped.count, 200)

        let preview = "{\"id\":\"1\",\"title\":\"Go+\",\"duration\":215,\"format_id\":\"hls_aac_160k_preview\",\"ext\":\"m4a\"}"
        XCTAssertThrowsError(try YtDlpSourceProvider.parseLookup(Data(preview.utf8), kind: .soundcloud, requestedURL: URL(string: "https://soundcloud.com/a/b")!)) {
            XCTAssertEqual($0 as? StudioError, .previewOnly)
        }
    }

    // MARK: Prüfsummen

    func testChecksumListParsing() {
        let sums = """
        e51e69e89489f199530f13d32a4342da3ddb2cf34842f364603a066db05afbf3  yt-dlp
        0f922c15ccc0b83eefa1c8bc9104e434318c4bf16e408e1ee93b7745a6efe0aa  yt-dlp_macos
        20d98fa608998eff87d1d35a6e9fb65e4b874639a6cc89addc19da3becde3ef1  yt-dlp_macos.zip
        """
        XCTAssertEqual(ToolChecksum.expected(in: sums, for: "yt-dlp_macos"), "0f922c15ccc0b83eefa1c8bc9104e434318c4bf16e408e1ee93b7745a6efe0aa")
        XCTAssertEqual(ToolChecksum.expected(in: sums, for: "yt-dlp"), "e51e69e89489f199530f13d32a4342da3ddb2cf34842f364603a066db05afbf3")
        XCTAssertNil(ToolChecksum.expected(in: sums, for: "yt-dlp_linux"))
        let deno = "9f0bf660393da2eaff044cdc7444cb08c73f235849b61d224d825a194ce7c98e  deno-aarch64-apple-darwin.zip\n"
        XCTAssertEqual(ToolChecksum.expected(in: deno, for: "deno-aarch64-apple-darwin.zip"), "9f0bf660393da2eaff044cdc7444cb08c73f235849b61d224d825a194ce7c98e")
        XCTAssertNil(ToolChecksum.expected(in: deno, for: "deno-x86_64-apple-darwin.zip"))
        XCTAssertEqual(ToolChecksum.expected(in: "4B2F5EDD2639B7470F034238B321D7002D8DFB4726D8558F52C17AFAC370EB2C\n", for: "x.zip"),
                       "4b2f5edd2639b7470f034238b321d7002d8dfb4726d8558f52c17afac370eb2c")
        XCTAssertEqual(ToolChecksum.expected(in: "SHA256 (deno.zip) = 9f0bf660393da2eaff044cdc7444cb08c73f235849b61d224d825a194ce7c98e", for: "deno.zip"),
                       "9f0bf660393da2eaff044cdc7444cb08c73f235849b61d224d825a194ce7c98e")
        XCTAssertEqual(ToolChecksum.expected(in: "9f0bf660393da2eaff044cdc7444cb08c73f235849b61d224d825a194ce7c98e *bin/deno.zip", for: "deno.zip"),
                       "9f0bf660393da2eaff044cdc7444cb08c73f235849b61d224d825a194ce7c98e")
        XCTAssertNil(ToolChecksum.expected(in: "kein Hash", for: "x"))
    }

    func testSHA256OfLocalFiles() throws {
        let abc = temp.appendingPathComponent("abc.txt")
        try Data("abc".utf8).write(to: abc)
        XCTAssertEqual(try ToolChecksum.sha256(of: abc), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let empty = temp.appendingPathComponent("empty")
        try Data().write(to: empty)
        XCTAssertEqual(try ToolChecksum.sha256(of: empty), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        // größer als ein Leseblock (1 MiB)
        let big = temp.appendingPathComponent("big")
        try Data(repeating: 0x61, count: 3 * 1024 * 1024 + 7).write(to: big)
        XCTAssertEqual(try ToolChecksum.sha256(of: big).count, 64)

        XCTAssertNoThrow(try ToolChecksum.verify(file: abc, expected: "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD", name: "abc"))
        XCTAssertThrowsError(try ToolChecksum.verify(file: abc, expected: String(repeating: "0", count: 64), name: "abc")) { error in
            guard case .other(let text) = error as? StudioError else { return XCTFail("StudioError erwartet") }
            XCTAssertTrue(text.contains("nichts installiert"))
        }
    }

    // MARK: Werkzeugsuche

    func testToolLookupPrefersManagedAndFindsSystemTools() async throws {
        let support = dir("support")
        let sys1 = dir("sys1")
        let sys2 = dir("sys2")
        try script(support, "yt-dlp", "echo 2026.10.21")
        try script(sys1, "yt-dlp", "echo 2020.01.01")
        try script(sys2, "deno", "echo 'deno 2.9.8 (stable, release, aarch64-apple-darwin)'; echo 'v8 14.0'; echo 'typescript 5.9'")
        try script(sys1, "ffmpeg", "echo ffmpeg")
        // nicht ausführbar → wird ignoriert
        try "kein Programm".write(to: sys1.appendingPathComponent("deno"), atomically: true, encoding: .utf8)

        let manager = StudioToolManager(supportDirectory: support, systemSearchPaths: [sys1.path, sys2.path])
        let s = await manager.status()
        XCTAssertEqual(s.ytDlpPath, support.appendingPathComponent("yt-dlp").path)
        XCTAssertEqual(s.ytDlpOrigin, .managed)
        XCTAssertEqual(s.ytDlpVersion, "2026.10.21")
        XCTAssertEqual(s.denoPath, sys2.appendingPathComponent("deno").path)
        XCTAssertEqual(s.denoOrigin, .system)
        XCTAssertEqual(s.denoVersion, "2.9.8")
        XCTAssertEqual(s.ffmpegPath, sys1.appendingPathComponent("ffmpeg").path)
        XCTAssertTrue(s.readyForYouTube)

        // ohne verwaltete Datei: System
        try FileManager.default.removeItem(at: support.appendingPathComponent("yt-dlp"))
        let s2 = await manager.status()
        XCTAssertEqual(s2.ytDlpOrigin, .system)
        XCTAssertEqual(s2.ytDlpVersion, "2020.01.01")

        // nichts gefunden
        let empty = StudioToolManager(supportDirectory: dir("leer"), systemSearchPaths: [dir("nichts").path])
        let s3 = await empty.status()
        XCTAssertNil(s3.ytDlpPath)
        XCTAssertEqual(s3.ytDlpOrigin, .missing)
        XCTAssertEqual(s3.denoOrigin, .missing)
        XCTAssertNil(s3.ffmpegPath)
        XCTAssertFalse(s3.readyForWeb)
    }

    func testDefaultSearchPathsCoverFinderApps() {
        let paths = StudioToolManager.defaultSystemSearchPaths
        XCTAssertTrue(paths.contains("/opt/homebrew/bin"))
        XCTAssertTrue(paths.contains("/usr/local/bin"))
        XCTAssertTrue(paths.contains(NSHomeDirectory() + "/.local/bin"))
    }

    // MARK: Installation mit lokalen Veröffentlichungen

    private struct LocalReleases: ToolReleaseSource {
        var yt: ToolRelease
        var deno: ToolRelease
        func ytDlp() async throws -> ToolRelease { yt }
        func deno(arch: String) async throws -> ToolRelease { deno }
    }

    /// Erzeugt Ersatz-Veröffentlichungen: yt-dlp als Skript, Deno als ZIP (mit ditto), Prüfsummen passend
    /// oder absichtlich falsch.
    private func makeReleases(ytVersion: String, denoVersion: String, breakYt: Bool = false, breakDeno: Bool = false) throws -> LocalReleases {
        let rel = dir("release-\(UUID().uuidString)")
        let yt = try script(rel, "yt-dlp_macos", "echo \(ytVersion)")
        let ytHash = breakYt ? String(repeating: "1", count: 64) : try ToolChecksum.sha256(of: yt)
        let sums = rel.appendingPathComponent("SHA2-256SUMS")
        try "\(String(repeating: "2", count: 64))  yt-dlp\n\(ytHash)  yt-dlp_macos\n".write(to: sums, atomically: true, encoding: .utf8)

        let denoSrc = dir("deno-src-\(UUID().uuidString)")
        let denoBin = try script(denoSrc, "deno", "echo 'deno \(denoVersion) (stable, release, test)'")
        let zipName = "deno-\(StudioToolManager.denoArch)-apple-darwin.zip"
        let zip = rel.appendingPathComponent(zipName)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", denoBin.path, zip.path]
        try ditto.run()
        ditto.waitUntilExit()
        XCTAssertEqual(ditto.terminationStatus, 0)
        let denoHash = breakDeno ? String(repeating: "3", count: 64) : try ToolChecksum.sha256(of: zip)
        let denoSums = rel.appendingPathComponent(zipName + ".sha256sum")
        try "\(denoHash)  \(zipName)\n".write(to: denoSums, atomically: true, encoding: .utf8)

        return LocalReleases(yt: ToolRelease(version: ytVersion, binaryURL: yt, checksumURL: sums, assetName: "yt-dlp_macos"),
                             deno: ToolRelease(version: denoVersion, binaryURL: zip, checksumURL: denoSums, assetName: zipName))
    }

    private final class StepLog: @unchecked Sendable {
        private let lock = NSLock()
        private var steps: [ToolInstallProgress] = []
        func add(_ p: ToolInstallProgress) { lock.lock(); steps.append(p); lock.unlock() }
        var all: [ToolInstallProgress] { lock.lock(); defer { lock.unlock() }; return steps }
    }

    func testInstallVerifiesAndInstallsFromLocalReleases() async throws {
        let support = dir("Tools")
        let system = dir("system")
        try script(system, "yt-dlp", "echo 1999.01.01")   // Systeminstallation bleibt unberührt
        let manager = StudioToolManager(supportDirectory: support, systemSearchPaths: [system.path],
                                        releases: try makeReleases(ytVersion: "2099.01.01", denoVersion: "9.8.7"))
        let log = StepLog()
        let status = try await manager.installOrUpdate { log.add($0) }
        XCTAssertEqual(status.ytDlpOrigin, .managed)
        XCTAssertEqual(status.ytDlpVersion, "2099.01.01")
        XCTAssertEqual(status.denoOrigin, .managed)
        XCTAssertEqual(status.denoVersion, "9.8.7")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: support.appendingPathComponent("yt-dlp").path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: support.appendingPathComponent("deno").path))
        XCTAssertEqual(log.all.last?.fraction, 1)
        XCTAssertTrue(log.all.contains { $0.step.contains("Prüfsumme wird geprüft") })
        let fractions = log.all.compactMap(\.fraction)
        XCTAssertEqual(fractions, fractions.sorted(), "Fortschritt steigt")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: support.path).filter { $0.hasPrefix(".install-") }
        XCTAssertTrue(leftovers.isEmpty, "Vorbereitungsordner aufgeräumt")

        // Gleiche Versionen: nichts wird erneut geladen
        let log2 = StepLog()
        _ = try await manager.installOrUpdate { log2.add($0) }
        XCTAssertTrue(log2.all.contains { $0.step == "yt-dlp 2099.01.01 ist aktuell" })
        XCTAssertTrue(log2.all.contains { $0.step == "Deno 9.8.7 ist aktuell" })

        // Entfernen löscht nur die verwalteten Dateien
        let removed = try await manager.removeManaged()
        XCTAssertEqual(removed.ytDlpOrigin, .system)
        XCTAssertEqual(removed.ytDlpVersion, "1999.01.01")
        XCTAssertEqual(removed.denoOrigin, .missing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent("yt-dlp").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: system.appendingPathComponent("yt-dlp").path))
    }

    func testInstallAbortsOnChecksumMismatchAndInstallsNothing() async throws {
        // yt-dlp falsch
        let support = dir("ToolsA")
        let a = StudioToolManager(supportDirectory: support, systemSearchPaths: [],
                                  releases: try makeReleases(ytVersion: "2099.01.01", denoVersion: "1.0.0", breakYt: true))
        do {
            _ = try await a.installOrUpdate { _ in }
            XCTFail("Prüfsummenfehler erwartet")
        } catch {
            XCTAssertTrue(messageOf(error).contains("Prüfsumme"), "\(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent("yt-dlp").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent("deno").path))

        // yt-dlp richtig, Deno falsch → auch yt-dlp wird nicht installiert (alles oder nichts)
        let supportB = dir("ToolsB")
        let b = StudioToolManager(supportDirectory: supportB, systemSearchPaths: [],
                                  releases: try makeReleases(ytVersion: "2099.01.01", denoVersion: "1.0.0", breakDeno: true))
        do {
            _ = try await b.installOrUpdate { _ in }
            XCTFail("Prüfsummenfehler erwartet")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: supportB.appendingPathComponent("yt-dlp").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: supportB.appendingPathComponent("deno").path))
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: supportB.path).filter { $0.hasPrefix(".install-") }) ?? []
        XCTAssertTrue(leftovers.isEmpty)
        let status = await b.status()
        XCTAssertEqual(status.ytDlpOrigin, .missing)
    }

    private func messageOf(_ error: Error) -> String {
        (error as? StudioError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: Prozesse

    func testCancellationTerminatesProcessTree() async throws {
        let pids = PidBox()
        let task = Task {
            try await StudioProcess.run("/bin/sh", ["-c", "sleep 60 & echo $!; wait"]) { line, _ in
                if let pid = Int32(line.trimmingCharacters(in: .whitespaces)) { pids.set(pid) }
            }
        }
        let deadline = Date().addingTimeInterval(10)
        while pids.value == nil && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        let child = try XCTUnwrap(pids.value, "Kindprozess gestartet")
        XCTAssertEqual(kill(child, 0), 0, "Kind läuft")
        let start = Date()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Abbruch erwartet")
        } catch {
            XCTAssertEqual(error as? StudioError, .cancelled)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        // Enkel (sleep) ist ebenfalls beendet
        var alive = true
        for _ in 0..<60 {
            if kill(child, 0) != 0 { alive = false; break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(alive, "Kindprozess wurde beendet")
        XCTAssertEqual(StudioProcess.runningCount, 0)
    }

    func testTimeoutAndExitStatus() async throws {
        let r = try await StudioProcess.run("/bin/sleep", ["30"], timeout: 0.5)
        XCTAssertTrue(r.timedOut)
        let ok = try await StudioProcess.run("/bin/sh", ["-c", "echo hallo; echo fehler >&2; exit 3"])
        XCTAssertEqual(ok.status, 3)
        XCTAssertEqual(ok.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hallo")
        XCTAssertEqual(ok.stderr.trimmingCharacters(in: .whitespacesAndNewlines), "fehler")
        do {
            _ = try await StudioProcess.run(temp.appendingPathComponent("gibt-es-nicht").path, [])
            XCTFail("Startfehler erwartet")
        } catch {
            guard case .other = error as? StudioError else { return XCTFail("StudioError.other erwartet") }
        }
    }

    func testEnvironmentHasUsefulPath() {
        let env = StudioProcess.environment(extraPaths: ["/x/tools"])
        let path = env["PATH"] ?? ""
        XCTAssertTrue(path.hasPrefix("/x/tools:"))
        XCTAssertTrue(path.contains("/opt/homebrew/bin"))
        XCTAssertTrue(path.contains("/usr/local/bin"))
        XCTAssertEqual(env["LC_ALL"], "en_US.UTF-8")
    }

    // MARK: Anbieter mit Ersatz-yt-dlp

    /// Ersatz für yt-dlp: `-J` liefert JSON, sonst wird eine Datei in `-P` angelegt, Fortschritt ausgegeben und
    /// der Pfad wie bei `--print after_move:filepath` gemeldet. Die Argumente werden mitgeschrieben.
    private func fakeYtDlp(in tools: URL, json: String, ext: String = "m4a", fail: String? = nil) throws {
        let argsLog = tools.appendingPathComponent("args.txt").path
        let body = """
        printf '%s\\n' "$@" > '\(argsLog)'
        \(fail.map { "echo \"ERROR: [youtube] abc: \($0)\" >&2; exit 1" } ?? "")
        for a in "$@"; do if [ "$a" = "-J" ]; then cat <<'JSON'
        \(json)
        JSON
        exit 0; fi; done
        DIR=""; prev=""
        for a in "$@"; do if [ "$prev" = "-P" ]; then DIR="$a"; fi; prev="$a"; done
        mkdir -p "$DIR"
        echo "ML-PROGRESS downloading 50 100 NA 25 2 NA NA" >&2
        printf 'Audiodaten' > "$DIR/abc.\(ext)"
        echo "ML-PROGRESS finished 100 100 NA NA NA NA NA" >&2
        echo "$DIR/abc.\(ext)"
        """
        try script(tools, "yt-dlp", body)
    }

    private final class ProgressLog: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [DownloadProgress] = []
        func add(_ p: DownloadProgress) { lock.lock(); values.append(p); lock.unlock() }
        var all: [DownloadProgress] { lock.lock(); defer { lock.unlock() }; return values }
    }

    func testProviderAnalyzeAndDownloadWithFakeTool() async throws {
        let tools = dir("Tools")
        try fakeYtDlp(in: tools, json: #"{"id":"t1","title":"Künstlerin - Lied (Official Audio)","duration":185,"acodec":"mp4a.40.2","abr":128,"webpage_url":"https://soundcloud.com/a/lied"}"#)
        let manager = StudioToolManager(supportDirectory: tools, systemSearchPaths: [])
        let provider = YtDlpSourceProvider(tools: manager)
        let info = try await provider.analyze(url: URL(string: "https://soundcloud.com/a/lied")!, kind: .soundcloud)
        XCTAssertEqual(info.suggested.artist, "Künstlerin")
        XCTAssertEqual(info.suggested.title, "Lied")
        XCTAssertEqual(info.duration, 185)
        let args = try String(contentsOf: tools.appendingPathComponent("args.txt"), encoding: .utf8)
        XCTAssertTrue(args.contains("--ignore-config"))
        XCTAssertTrue(args.contains(manager.cacheDirectory.path), "eigener Zwischenspeicher")

        let out = dir("download")
        let log = ProgressLog()
        var source = info
        source.duration = nil   // keine Hörproben-Prüfung (Ersatzdatei ist kein Audio)
        let file = try await provider.download(source, into: out) { log.add($0) }
        XCTAssertEqual(file.path, out.appendingPathComponent("abc.m4a").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(log.all.contains { $0.fraction == 1 })
        XCTAssertTrue(log.all.contains { $0.bytesDone == 50 || $0.bytesDone == 100 })
    }

    func testProviderMapsToolErrors() async throws {
        let tools = dir("ToolsErr")
        try fakeYtDlp(in: tools, json: "{}", fail: "Private video. Sign in if you've been granted access to this video")
        let provider = YtDlpSourceProvider(tools: StudioToolManager(supportDirectory: tools, systemSearchPaths: []))
        do {
            _ = try await provider.analyze(url: URL(string: "https://soundcloud.com/a/b")!, kind: .soundcloud)
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertEqual(error as? StudioError, .privateContent)
        }
    }

    func testMissingToolsAreReported() async throws {
        let none = YtDlpSourceProvider(tools: StudioToolManager(supportDirectory: dir("keine"), systemSearchPaths: []))
        do {
            _ = try await none.analyze(url: URL(string: "https://soundcloud.com/a/b")!, kind: .soundcloud)
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertEqual(error as? StudioError, .toolMissing("yt-dlp"))
        }
        // yt-dlp vorhanden, Deno fehlt → YouTube nicht möglich
        let tools = dir("nurYt")
        try fakeYtDlp(in: tools, json: "{}")
        let onlyYt = YtDlpSourceProvider(tools: StudioToolManager(supportDirectory: tools, systemSearchPaths: []))
        do {
            _ = try await onlyYt.analyze(url: URL(string: "https://www.youtube.com/watch?v=aqz-KE-bpKQ")!, kind: .youtube)
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertEqual(error as? StudioError, .toolMissing("Deno"))
        }
    }

    func testOpusWithoutFFmpegIsRejectedClearly() async throws {
        let tools = dir("ToolsOpus")
        try fakeYtDlp(in: tools, json: "{}", ext: "webm")
        let provider = YtDlpSourceProvider(tools: StudioToolManager(supportDirectory: tools, systemSearchPaths: []))
        let source = SourceInfo(id: "x", kind: .soundcloud, url: URL(string: "https://soundcloud.com/a/b")!, title: "x", codec: "opus")
        do {
            _ = try await provider.download(source, into: dir("dl"), progress: { _ in })
            XCTFail("Fehler erwartet")
        } catch {
            guard case .other(let text) = error as? StudioError else { return XCTFail("\(error)") }
            XCTAssertTrue(text.contains("FFmpeg"))
        }
    }

    // MARK: Spotify

    func testSpotifyDownloadIsRefusedAsDRM() async {
        let provider = YtDlpSourceProvider(tools: StudioToolManager(supportDirectory: dir("sp"), systemSearchPaths: []))
        let source = SourceInfo(id: "s", kind: .spotify, url: URL(string: "https://open.spotify.com/track/abc")!, title: "Lied")
        do {
            _ = try await provider.download(source, into: dir("sp-out"), progress: { _ in })
            XCTFail("DRM-Fehler erwartet")
        } catch {
            XCTAssertEqual(error as? StudioError, .spotifyDRM)
        }
        XCTAssertFalse(SourceKind.spotify.supportsAudio)
    }

    func testDefaultExpandPlaylistOfSimpleProvider() async throws {
        struct Simple: RemoteSourceProviding {
            func analyze(url: URL, kind: SourceKind) async throws -> SourceInfo { SourceInfo(id: "1", kind: kind, url: url, title: "Eins") }
            func download(_ source: SourceInfo, into directory: URL, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL { directory }
            func thumbnail(for source: SourceInfo) async -> Data? { nil }
        }
        let url = URL(string: "https://soundcloud.com/a/b")!
        let urls = try await Simple().expandPlaylist(url: url)
        XCTAssertEqual(urls, [url])
        guard case .single(let info) = try await Simple().lookup(url: url, kind: .soundcloud) else { return XCTFail() }
        XCTAssertEqual(info.title, "Eins")
    }

    // MARK: Vorschaubilder

    func testThumbnailNormalization() throws {
        // 2×2-Bild als GIF → JPEG
        let ctx = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = ctx.makeImage()!
        func encode(_ type: String) -> Data {
            let out = NSMutableData()
            let dest = CGImageDestinationCreateWithData(out as CFMutableData, type as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(dest))
            return out as Data
        }
        let png = encode("public.png")
        XCTAssertEqual(StudioHTTP.normalizedImage(png), png, "PNG bleibt unverändert")
        let gif = encode("com.compuserve.gif")
        let jpeg = try XCTUnwrap(StudioHTTP.normalizedImage(gif))
        XCTAssertEqual(Array(jpeg.prefix(3)), [0xFF, 0xD8, 0xFF])
        XCTAssertNil(StudioHTTP.normalizedImage(Data("kein Bild".utf8)))
    }

    func testThumbnailOnlyOverHTTPS() async {
        let data = await StudioHTTP.thumbnail(from: URL(string: "http://example.com/a.jpg")!)
        XCTAssertNil(data)
        let file = await StudioHTTP.thumbnail(from: temp.appendingPathComponent("a.jpg"))
        XCTAssertNil(file)
    }
}

private final class PidBox: @unchecked Sendable {
    private let lock = NSLock()
    private var pid: Int32?
    func set(_ p: Int32) { lock.lock(); if pid == nil { pid = p }; lock.unlock() }
    var value: Int32? { lock.lock(); defer { lock.unlock() }; return pid }
}
