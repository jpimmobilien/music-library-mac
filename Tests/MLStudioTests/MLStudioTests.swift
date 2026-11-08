import XCTest
@testable import MLStudio
import MLCore

final class StudioFormatTests: XCTestCase {
    func testDefaultsAreSensible() {
        XCTAssertEqual(ExportOptions.defaults(for: .mp3).mp3Bitrate, 320)
        XCTAssertEqual(ExportOptions.defaults(for: .m4a).aacBitrate, 256)
        XCTAssertEqual(ExportOptions.defaults(for: .wav).pcmDepth, .int16)
        XCTAssertEqual(ExportOptions.defaults(for: .flac).flacLevel, 5)
        XCTAssertTrue(ExportOptions.defaults(for: .flac).flacKeepSourceDepth)
        for f in StudioFormat.allCases { XCTAssertEqual(ExportOptions.defaults(for: f).format, f) }
    }

    func testAllRequiredMP3Bitrates() {
        XCTAssertEqual(ExportOptions.mp3Bitrates, [96, 128, 160, 192, 224, 256, 320])
    }

    func testNormalizedClampsInvalidValues() {
        var o = ExportOptions(format: .mp3, mp3Bitrate: 300, aacBitrate: 999, flacLevel: 12)
        o.sampleRate = 22_050
        let n = o.normalized()
        XCTAssertEqual(n.mp3Bitrate, 320)
        XCTAssertEqual(n.aacBitrate, 320)
        XCTAssertEqual(n.flacLevel, 8)
        XCTAssertNil(n.sampleRate)
    }

    func testOutputSampleRate() {
        let mp3 = ExportOptions.defaults(for: .mp3)
        XCTAssertEqual(mp3.outputSampleRate(sourceRate: 44_100), 44_100)
        XCTAssertEqual(mp3.outputSampleRate(sourceRate: 96_000), 48_000)   // MPEG-1 kennt keine 96 kHz
        XCTAssertEqual(mp3.outputSampleRate(sourceRate: 22_050), 32_000)
        var wav = ExportOptions.defaults(for: .wav)
        XCTAssertEqual(wav.outputSampleRate(sourceRate: 88_200), 88_200)  // Original bleibt
        wav.sampleRate = 96_000
        XCTAssertEqual(wav.outputSampleRate(sourceRate: 44_100), 96_000)
    }

    func testOutputDepth() {
        let flac = ExportOptions.defaults(for: .flac)
        XCTAssertEqual(flac.outputDepth(sourceBits: 16), .int16)
        XCTAssertEqual(flac.outputDepth(sourceBits: 24), .int24)
        XCTAssertEqual(flac.outputDepth(sourceBits: 32), .int24)
        var wav = ExportOptions.defaults(for: .wav)
        wav.pcmDepth = .float32
        XCTAssertEqual(wav.outputDepth(sourceBits: 16), .float32)
    }

    func testHonestNotesForLossyToLossless() {
        let notes = QualityAdvice.notes(options: .defaults(for: .wav), sourceLossless: false, sourceBitrate: 128, sourceRate: 44_100, sourceBits: nil)
        XCTAssertTrue(notes.contains { $0.contains("macht sie aber nicht besser") })
        let mp3 = QualityAdvice.notes(options: .defaults(for: .mp3), sourceLossless: false, sourceBitrate: 128, sourceRate: 44_100, sourceBits: nil)
        XCTAssertTrue(mp3.contains { $0.contains("128 kbit/s") && $0.contains("nicht die Qualität") })
        let lossless = QualityAdvice.notes(options: .defaults(for: .flac), sourceLossless: true, sourceBitrate: nil, sourceRate: 44_100, sourceBits: 16)
        XCTAssertTrue(lossless.isEmpty, "\(lossless)")
        var up = ExportOptions.defaults(for: .wav)
        up.sampleRate = 96_000
        XCTAssertTrue(QualityAdvice.notes(options: up, sourceLossless: true, sourceBitrate: nil, sourceRate: 44_100, sourceBits: 16).contains { $0.contains("96 kHz") })
        XCTAssertTrue(QualityAdvice.notes(options: .defaults(for: .aac), sourceLossless: true, sourceBitrate: nil, sourceRate: nil, sourceBits: nil).contains { $0.contains("keine Tags") })
    }

    func testSummary() {
        XCTAssertEqual(ExportOptions.defaults(for: .mp3).summary(sourceRate: 44_100), "MP3 · 320 kbit/s · 44,1 kHz")
        var wav = ExportOptions.defaults(for: .wav)
        wav.pcmDepth = .int24
        wav.sampleRate = 48_000
        XCTAssertEqual(wav.summary(), "WAV · 24 Bit · 48 kHz")
    }
}

final class StudioNamingTests: XCTestCase {
    func testSchemes() {
        let m = StudioMetadata(title: "Blue Sky", artist: "Nova")
        XCTAssertEqual(FileNameScheme.artistTitle.render(m, fallback: "x"), "Nova – Blue Sky")
        XCTAssertEqual(FileNameScheme.titleArtist.render(m, fallback: "x"), "Blue Sky – Nova")
        XCTAssertEqual(FileNameScheme.title.render(m, fallback: "x"), "Blue Sky")
        XCTAssertEqual(FileNameScheme.custom("Mein Mix").render(m, fallback: "x"), "Mein Mix")
        XCTAssertEqual(FileNameScheme.artistTitle.render(StudioMetadata(title: "Nur Titel"), fallback: "x"), "Nur Titel")
        XCTAssertEqual(FileNameScheme.artistTitle.render(StudioMetadata(), fallback: "Video 1"), "Video 1")
        XCTAssertEqual(FileNameScheme.custom("   ").render(StudioMetadata(), fallback: ""), "Audio")
    }

    func testSanitize() {
        XCTAssertEqual(FileNames.sanitize("AC/DC: Live\n"), "AC-DC- Live")
        XCTAssertEqual(FileNames.sanitize("..versteckt"), "versteckt")
        XCTAssertEqual(FileNames.sanitize("  viel    Platz  "), "viel Platz")
        XCTAssertEqual(FileNames.sanitize(String(repeating: "a", count: 300)).count, 180)
    }

    func testUnique() {
        let taken: Set<String> = ["/m/A.mp3", "/m/A (2).mp3"]
        XCTAssertEqual(FileNames.unique(base: "A", ext: "mp3", in: "/m/", exists: { taken.contains($0) }), "/m/A (3).mp3")
        XCTAssertEqual(FileNames.unique(base: "B", ext: "mp3", in: "/m", exists: { taken.contains($0) }), "/m/B.mp3")
    }

    func testTagEditOnlyFilledFields() {
        let m = StudioMetadata(title: " T ", artist: "A", album: "", year: 2024, genre: "Pop", trackNumber: 3, cover: Data([1, 2, 3]))
        let edit = m.tagEdit(coverMimeType: "image/jpeg")
        XCTAssertEqual(edit.fields, [.title, .artists, .year, .genres, .trackNumber])
        XCTAssertEqual(edit.values.title, "T")
        if case .replaceAll(let pics) = edit.pictures {
            XCTAssertEqual(pics.count, 1)
            XCTAssertEqual(pics[0].kind, .frontCover)
        } else {
            XCTFail("Cover fehlt")
        }
        XCTAssertEqual(StudioMetadata(title: "x").tagEdit(coverMimeType: nil).pictures, .keep)
    }
}

final class StudioSourceTests: XCTestCase {
    func testClassify() {
        XCTAssertEqual(SourceURL.classify("https://www.youtube.com/watch?v=abc")?.kind, .youtube)
        XCTAssertEqual(SourceURL.classify("youtu.be/abc")?.kind, .youtube)
        XCTAssertEqual(SourceURL.classify("https://music.youtube.com/watch?v=abc")?.kind, .youtube)
        XCTAssertEqual(SourceURL.classify("https://soundcloud.com/artist/track")?.kind, .soundcloud)
        XCTAssertEqual(SourceURL.classify("https://on.soundcloud.com/xyz")?.kind, .soundcloud)
        XCTAssertEqual(SourceURL.classify("https://open.spotify.com/track/123")?.kind, .spotify)
        XCTAssertEqual(SourceURL.classify("https://example.org/a.mp3")?.kind, .web)
        XCTAssertNil(SourceURL.classify(""))
        XCTAssertNil(SourceURL.classify("file:///etc/passwd"))
        XCTAssertNil(SourceURL.classify("ftp://example.org/x"))
        XCTAssertNil(SourceURL.classify("kein link"))
        XCTAssertFalse(SourceKind.spotify.supportsAudio)
    }

    func testYtDlpMapping() throws {
        let json = """
        {"id":"abc","title":"Nova - Blue Sky (Official Video)","uploader":"NovaVEVO","duration":213.5,
         "thumbnail":"https://i.ytimg.com/vi/abc/maxresdefault.jpg","webpage_url":"https://www.youtube.com/watch?v=abc",
         "upload_date":"20210304","abr":129.5,"acodec":"mp4a.40.2","asr":44100,"audio_channels":2,"live_status":"not_live"}
        """
        let info = try JSONDecoder().decode(YtDlpInfo.self, from: Data(json.utf8)).sourceInfo(kind: .youtube, requestedURL: URL(string: "https://youtu.be/abc")!)
        XCTAssertEqual(info.suggested.artist, "Nova")
        XCTAssertEqual(info.suggested.title, "Blue Sky")
        XCTAssertEqual(info.suggested.year, 2021)
        XCTAssertEqual(info.duration, 213.5)
        XCTAssertEqual(info.bitrateKbps, 130)
        XCTAssertEqual(info.sampleRate, 44_100)
        XCTAssertFalse(info.isLive)
        XCTAssertEqual(info.url.absoluteString, "https://www.youtube.com/watch?v=abc")
    }

    func testYtDlpMusicFieldsWin() throws {
        let json = #"{"id":"x","title":"Something","track":"Real Title","artist":"Real Artist","album":"LP","release_year":1999,"is_live":true}"#
        let info = try JSONDecoder().decode(YtDlpInfo.self, from: Data(json.utf8)).sourceInfo(kind: .soundcloud, requestedURL: URL(string: "https://soundcloud.com/a/b")!)
        XCTAssertEqual(info.suggested.title, "Real Title")
        XCTAssertEqual(info.suggested.artist, "Real Artist")
        XCTAssertEqual(info.suggested.album, "LP")
        XCTAssertEqual(info.suggested.year, 1999)
        XCTAssertTrue(info.isLive)
    }

    func testCleanTitleKeepsRemix() {
        XCTAssertEqual(YtDlpInfo.cleanTitle("Song (Official Audio) [HD]"), "Song")
        XCTAssertEqual(YtDlpInfo.cleanTitle("Song (Club Remix)"), "Song (Club Remix)")
        XCTAssertEqual(YtDlpInfo.cleanChannel("Nova - Topic"), "Nova")
        XCTAssertNil(YtDlpInfo.splitArtistTitle("Ohne Trenner"))
    }

    func testSpotifyEndpoint() {
        let url = SpotifyOEmbed.endpoint(for: URL(string: "https://open.spotify.com/track/1?si=x")!)
        XCTAssertEqual(url?.host, "open.spotify.com")
        XCTAssertTrue(url?.absoluteString.contains("oembed?url=") ?? false)
    }

    func testSameFormat() {
        func src(_ path: String, codec: String? = nil) -> SourceInfo {
            SourceInfo(id: path, kind: .localFile, url: URL(fileURLWithPath: path), title: "t", codec: codec, localFile: URL(fileURLWithPath: path))
        }
        XCTAssertEqual(src("/a/b.mp3").sameFormat, .mp3)
        XCTAssertEqual(src("/a/b.FLAC").sameFormat, .flac)
        XCTAssertEqual(src("/a/b.m4a", codec: "aac").sameFormat, .m4a)
        XCTAssertNil(src("/a/b.m4a", codec: "alac").sameFormat)
        XCTAssertNil(src("/a/b.ogg").sameFormat)
    }
}

final class StudioQueueTests: XCTestCase {
    private func job(_ phase: JobPhase, kind: SourceKind = .localFile) -> StudioJob {
        var j = StudioJob(source: SourceInfo(id: UUID().uuidString, kind: kind, url: URL(string: "https://example.org")!, title: "t"),
                          options: .defaults(for: .mp3), trim: nil, metadata: StudioMetadata(), fileName: "t",
                          destination: .folder(path: "/tmp"))
        j.phase = phase
        return j
    }

    func testOnlyOneActive() {
        let jobs = [job(.done), job(.converting), job(.waiting)]
        XCTAssertNil(StudioQueueLogic.nextRunnable(jobs))
    }

    func testContinuesAfterFailure() {
        let jobs = [job(.failed), job(.paused), job(.waiting), job(.waiting)]
        XCTAssertEqual(StudioQueueLogic.nextRunnable(jobs), jobs[2].id)
    }

    func testPermissions() {
        XCTAssertTrue(StudioQueueLogic.canPause(job(.downloading)))
        XCTAssertFalse(StudioQueueLogic.canPause(job(.importing)))
        XCTAssertTrue(StudioQueueLogic.canResume(job(.paused)))
        XCTAssertTrue(StudioQueueLogic.canRetry(job(.failed)))
        XCTAssertFalse(StudioQueueLogic.canRemove(job(.converting)))
        XCTAssertFalse(StudioQueueLogic.canCancel(job(.done)))
    }

    func testOverallProgress() {
        var j = job(.downloading, kind: .youtube)
        j.progress = 0.5
        XCTAssertEqual(j.overallProgress, 0.25, accuracy: 1e-9)
        j.phase = .converting
        XCTAssertEqual(j.overallProgress, 0.725, accuracy: 1e-9)
        var local = job(.converting)
        local.progress = 0.5
        XCTAssertEqual(local.overallProgress, 0.45, accuracy: 1e-9)
    }

    func testSummary() {
        XCTAssertEqual(StudioQueueLogic.summary([job(.done), job(.failed), job(.waiting)]), "1 von 3 fertig · 1 Fehler")
        XCTAssertEqual(StudioQueueLogic.summary([]), "Keine Aufträge")
    }

    func testTrimClamp() {
        XCTAssertNil(TrimRange(start: 0, end: 100).clamped(to: 100))
        XCTAssertNil(TrimRange(start: 5, end: 5).clamped(to: 100))
        XCTAssertEqual(TrimRange(start: -3, end: 50).clamped(to: 100), TrimRange(start: 0, end: 50))
        XCTAssertEqual(TrimRange(start: 10, end: 500).clamped(to: 100), TrimRange(start: 10, end: 100))
    }

    func testDestinations() {
        let lib = StudioDestination.library(folderID: 1, folderPath: "/Music/", subfolder: "Audio Studio/../x:y")
        XCTAssertEqual(lib.directoryPath, "/Music/Audio Studio/x-y")
        XCTAssertTrue(lib.importsIntoLibrary)
        XCTAssertEqual(StudioDestination.replaceOriginal(uid: 3, path: "/Music/A/b.mp3").directoryPath, "/Music/A")
        XCTAssertFalse(StudioDestination.folder(path: "/x").importsIntoLibrary)
    }

    func testHistoryLimitAndLookup() {
        var h = StudioHistory()
        for i in 0..<(StudioHistory.limit + 5) {
            h.add(StudioHistoryEntry(sourceKind: .youtube, source: "s\(i)", title: "t", artist: "a", outputPath: "/o", formatSummary: "MP3",
                                     duration: 1, imported: false, succeeded: i % 2 == 0))
        }
        XCTAssertEqual(h.entries.count, StudioHistory.limit)
        XCTAssertEqual(h.entries.first?.source, "s\(StudioHistory.limit + 4)")
        XCTAssertNotNil(h.previousExport(of: "s504"))
        XCTAssertNil(h.previousExport(of: "s503"))
    }

    func testDuplicates() {
        let lib = [
            DuplicateCheck.Candidate(uid: 1, title: "Blue Sky", artist: "Nova", durationSeconds: 213, path: "/m/a.mp3"),
            DuplicateCheck.Candidate(uid: 2, title: "Blue Sky", artist: "Other", durationSeconds: 213, path: "/m/b.mp3"),
            DuplicateCheck.Candidate(uid: 3, title: "Blüe-Sky!", artist: "NOVA", durationSeconds: 300, path: "/m/c.mp3"),
        ]
        XCTAssertEqual(DuplicateCheck.matches(title: "blue sky", artist: "nova", duration: 214.5, targetPath: nil, in: lib).map(\.uid), [1])
        XCTAssertEqual(DuplicateCheck.matches(title: "x", artist: "y", duration: nil, targetPath: "/m/c.mp3", in: lib).map(\.uid), [3])
        XCTAssertEqual(DuplicateCheck.matches(title: "Blue Sky", artist: "", duration: nil, targetPath: nil, in: lib).map(\.uid), [1, 2, 3])
    }
}

final class StudioWaveformTests: XCTestCase {
    func testLevelsAndColumns() {
        let n = 20_000
        var mins = [Float](repeating: -0.1, count: n)
        var maxs = [Float](repeating: 0.1, count: n)
        mins[12_345] = -0.9
        maxs[777] = 0.8
        let w = WaveformData(base: mins, maxs: maxs, framesPerBucket: 256, sampleRate: 44_100, duration: Double(n * 256) / 44_100)
        XCTAssertGreaterThan(w.levels.count, 2)
        XCTAssertEqual(w.levels[1].mins.count, n / 4)
        XCTAssertEqual(w.peak, 0.9, accuracy: 1e-6)
        let cols = w.columns(range: 0...w.duration, columns: 400)
        XCTAssertEqual(cols.count, 400)
        XCTAssertEqual(cols.map(\.min).min()!, -0.9, accuracy: 1e-6)   // Spitzen gehen beim Verkleinern nicht verloren
        XCTAssertEqual(cols.map(\.max).max()!, 0.8, accuracy: 1e-6)
        let zoomed = w.columns(range: 0...1, columns: 100)
        XCTAssertEqual(zoomed.count, 100)
    }

    func testTimeFormatAndParse() {
        XCTAssertEqual(StudioTime.format(65.25), "1:05.250")
        XCTAssertEqual(StudioTime.format(3723.5, millis: false), "1:02:03")   // Uhr-Anzeige: abgeschnitten
        XCTAssertEqual(StudioTime.parse("65"), 65)
        XCTAssertEqual(StudioTime.parse("1:05,25")!, 65.25, accuracy: 1e-9)
        XCTAssertEqual(StudioTime.parse("01:02:03.5")!, 3723.5, accuracy: 1e-9)
        XCTAssertNil(StudioTime.parse("1:75"))
        XCTAssertNil(StudioTime.parse("a:b"))
        XCTAssertNil(StudioTime.parse(""))
        XCTAssertNil(StudioTime.parse("1.5:00"))
    }

    func testSettingsRoundTripAndCorruptData() throws {
        var s = StudioSettings()
        var o = ExportOptions.defaults(for: .mp3)
        o.mp3Bitrate = 192
        s.remember(o)
        let data = try JSONEncoder().encode(s)
        let back = StudioSettings.decode(data)
        XCTAssertEqual(back.lastFormat, .mp3)
        XCTAssertEqual(back.options(for: .mp3).mp3Bitrate, 192)
        XCTAssertEqual(back.options(for: .flac), ExportOptions.defaults(for: .flac))
        XCTAssertEqual(StudioSettings.decode(Data("kaputt".utf8)), StudioSettings())
    }
}

final class PauseGateTests: XCTestCase {
    func testWaitsUntilResumed() async {
        let gate = PauseGate()
        await gate.waitIfPaused()   // nicht angehalten → sofort
        gate.pause()
        let started = Date()
        Task.detached {
            try? await Task.sleep(nanoseconds: 150_000_000)
            gate.resume()
        }
        await gate.waitIfPaused()
        XCTAssertGreaterThan(Date().timeIntervalSince(started), 0.1)
        XCTAssertFalse(gate.isPaused)
    }
}
