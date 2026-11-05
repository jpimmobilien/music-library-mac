import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import MLCore
import XCTest
@testable import MLTags

final class SafeTagWriterTests: TagTestCase {
    private var backupRoot: URL!
    private var music: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        backupRoot = tempDir.appendingPathComponent("Backups", isDirectory: true)
        music = tempDir.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
    }

    private func writer() -> SafeTagWriter { SafeTagWriter(backupRoot: backupRoot) }

    private func titleEdit(_ title: String) -> TagEdit {
        var v = TagValues()
        v.title = title
        return TagEdit(values: v, fields: [.title])
    }

    private func backupFiles() -> [String] {
        let fm = FileManager.default
        return ((try? fm.subpathsOfDirectory(atPath: backupRoot.path)) ?? [])
            .filter { !$0.hasPrefix("Journal") && $0.contains("/") }
    }

    /// Original unverändert, keine temporären Dateien, keine Sicherung, kein Journal.
    private func assertUntouched(_ url: URL, original: Data, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try bytes(url), original, "original modified", file: file, line: line)
        XCTAssertEqual(leftoverTempFiles(in: url.deletingLastPathComponent()), [], file: file, line: line)
        XCTAssertEqual(backupFiles(), [], "backup left behind", file: file, line: line)
        XCTAssertTrue(writer().journals().isEmpty, "journal entry left behind", file: file, line: line)
    }

    // MARK: - Success

    func testSuccessfulWriteCreatesBackupAndJournal() throws {
        let url = try copyFixture("id3v23.mp3", into: music)
        let original = try bytes(url)
        let w = writer()
        let entry = try w.write(url: url, edit: SampleValues.fullEdit)

        let result = try TagFile.read(url: url)
        XCTAssertEqual(result.values.title, SampleValues.full.title)
        XCTAssertEqual(result.values.pictures.count, 2)
        // backup: <root>/<yyyy-MM-dd>/<uuid>-<filename>, byte-identical
        let backup = URL(fileURLWithPath: entry.backupPath)
        XCTAssertEqual(try bytes(backup), original)
        XCTAssertEqual(backup.deletingLastPathComponent().lastPathComponent,
                       SafeTagWriter.dayFormatter().string(from: Date()))
        XCTAssertEqual(backup.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path,
                       backupRoot.standardizedFileURL.path)
        XCTAssertTrue(backup.lastPathComponent.hasSuffix("-id3v23.mp3"))
        XCTAssertEqual(UUID(uuidString: String(backup.lastPathComponent.prefix(36))) != nil, true)
        // journal
        XCTAssertEqual(entry.originalSHA256, try sha256(backup))
        XCTAssertEqual(entry.resultSHA256, try sha256(url))
        XCTAssertEqual(entry.originalSize, Int64(original.count))
        XCTAssertEqual(Set(entry.fieldsChanged), Set(TagField.allCases.map(\.rawValue) + ["pictures"]))
        XCTAssertEqual(entry.before["title"], "Fixture Title")
        XCTAssertEqual(entry.after["title"], SampleValues.full.title)
        XCTAssertEqual(entry.originalPath, url.resolvingSymlinksInPath().path)
        let journal = try XCTUnwrap(try w.journal(batch: entry.batchID))
        XCTAssertEqual(journal.entries, [entry])
        let jsonPath = backupRoot.appendingPathComponent("Journal/\(entry.batchID.uuidString).json").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonPath))
        let json = try String(contentsOfFile: jsonPath, encoding: .utf8)
        XCTAssertTrue(json.contains("\"originalPath\""))
        XCTAssertEqual(leftoverTempFiles(in: music), [])
        try assertMarkers(Fixtures.named("id3v23.mp3"), in: url)
    }

    func testEveryFormatThroughSafeWriter() throws {
        let w = writer()
        for fixture in Fixtures.all {
            let url = try copyFixture(fixture.file, into: music)
            let before = try TagFile.read(url: url)
            let entry = try w.write(url: url, edit: SampleValues.fullEdit)
            XCTAssertEqual(Set(entry.skippedFields), Set(fixture.unsupported.map(\.rawValue)), "\(fixture)")
            let after = try TagFile.read(url: url)
            XCTAssertEqual(after.values.title, SampleValues.full.title, "\(fixture)")
            assertSameAudio(before.audio, after.audio, fixture.file)
            try assertMarkers(fixture, in: url)
            // edit again (file written by us)
            try w.write(url: url, edit: titleEdit("Zweiter Durchgang"))
            XCTAssertEqual(try TagFile.read(url: url).values.title, "Zweiter Durchgang", "\(fixture)")
        }
        XCTAssertEqual(leftoverTempFiles(in: music), [])
    }

    func testPermissionsArePreserved() throws {
        let url = try copyFixture("flac.flac", into: music)
        XCTAssertEqual(chmod(url.path, 0o640), 0)
        try writer().write(url: url, edit: titleEdit("Rechte"))
        let mode = try XCTUnwrap(FileSystem.fileStat(url.path)).mode & 0o7777
        XCTAssertEqual(mode, 0o640)
    }

    func testWriteThroughSymlinkKeepsTheLink() throws {
        let target = try copyFixture("aac.m4a", into: music)
        let link = tempDir.appendingPathComponent("link.m4a")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let entry = try writer().write(url: link, edit: titleEdit("Über Symlink"))
        XCTAssertEqual(entry.originalPath, target.resolvingSymlinksInPath().path)
        let attributes = try FileManager.default.attributesOfItem(atPath: link.path)
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeSymbolicLink)
        XCTAssertEqual(try TagFile.read(url: target).values.title, "Über Symlink")
    }

    // MARK: - Failures leave the original untouched

    func testSimulatedWriteFailure() throws {
        let url = try copyFixture("id3v24.mp3", into: music)
        let original = try bytes(url)
        let w = writer()
        struct Boom: Error {}
        w.hooks.applyEdit = { _, _ in throw Boom() }
        XCTAssertThrowsError(try w.write(url: url, edit: titleEdit("x"))) { error in
            guard case .writeFailed? = error as? TagError else { return XCTFail("\(error)") }
        }
        try assertUntouched(url, original: original)
    }

    func testCorruptedTempFileIsDetected() throws {
        let url = try copyFixture("flac.flac", into: music)
        let original = try bytes(url)
        let w = writer()
        w.hooks.applyEdit = { temp, edit in
            try TagFile.write(url: temp, edit: edit)
            // simulate a broken write: cut the audio data
            let handle = try FileHandle(forWritingTo: temp)
            handle.truncateFile(atOffset: 2000)
            handle.closeFile()
        }
        XCTAssertThrowsError(try w.write(url: url, edit: titleEdit("x"))) { error in
            guard case .verificationFailed? = error as? TagError else { return XCTFail("\(error)") }
        }
        try assertUntouched(url, original: original)
    }

    func testSingleChangedAudioByteIsDetected() throws {
        for name in ["flac.flac", "id3v24.mp3", "alac.m4a", "vorbis.ogg", "wave.wav", "wavpack.wv", "wma.wma"] {
            let url = try copyFixture(name, into: music)
            let original = try bytes(url)
            let w = writer()
            w.hooks.applyEdit = { temp, edit in
                try TagFile.write(url: temp, edit: edit)
                // flip one byte in the last quarter of the file (audio data, not metadata)
                var data = try Data(contentsOf: temp)
                var index = data.count * 3 / 4
                if name == "wma.wma" || name == "alac.m4a" { index = data.count / 2 }
                data[index] ^= 0x01
                try data.write(to: temp)
            }
            XCTAssertThrowsError(try w.write(url: url, edit: titleEdit("x")), name) { error in
                guard case .verificationFailed(_, let details)? = error as? TagError else { return XCTFail("\(error)") }
                XCTAssertTrue(details.contains("Audiodaten verändert"), "\(name): \(details)")
            }
            try assertUntouched(url, original: original)
            try FileManager.default.removeItem(at: url)
        }
    }

    func testVerificationMismatchOfEditedField() throws {
        let url = try copyFixture("aac.m4a", into: music)
        let original = try bytes(url)
        let w = writer()
        w.hooks.applyEdit = { temp, edit in
            var wrong = edit
            wrong.values.title = "Falscher Titel"
            try TagFile.write(url: temp, edit: wrong)
        }
        XCTAssertThrowsError(try w.write(url: url, edit: titleEdit("Richtiger Titel"))) { error in
            guard case .verificationFailed(_, let details)? = error as? TagError else { return XCTFail("\(error)") }
            XCTAssertTrue(details.contains { $0.hasPrefix("Titel") }, "\(details)")
            XCTAssertTrue((error as? TagError)?.localizedDescription.contains("nicht verändert") == true)
        }
        try assertUntouched(url, original: original)
    }

    func testVerificationMismatchOfUntouchedFieldAndPictures() throws {
        let url = try copyFixture("vorbis.ogg", into: music)
        let original = try bytes(url)
        let w = writer()
        w.hooks.applyEdit = { temp, edit in
            try TagFile.write(url: temp, edit: edit)
            var other = TagValues()
            other.album = "Heimlich geändert"
            try TagFile.write(url: temp, edit: TagEdit(values: other, fields: [.album], pictures: .replaceAll([])))
        }
        XCTAssertThrowsError(try w.write(url: url, edit: titleEdit("Titel"))) { error in
            guard case .verificationFailed(_, let details)? = error as? TagError else { return XCTFail("\(error)") }
            XCTAssertTrue(details.contains { $0.hasPrefix("Album") }, "\(details)")
            XCTAssertTrue(details.contains { $0.hasPrefix("Bilder") }, "\(details)")
        }
        try assertUntouched(url, original: original)
    }

    func testOriginalModifiedDuringEdit() throws {
        let url = try copyFixture("wave.wav", into: music)
        let w = writer()
        w.hooks.beforeReplace = { original in
            // another program appends data while we are working
            let handle = try FileHandle(forWritingTo: original)
            handle.seekToEndOfFile()
            handle.write(Data("EXTERN".utf8))
            handle.closeFile()
        }
        XCTAssertThrowsError(try w.write(url: url, edit: titleEdit("x"))) { error in
            XCTAssertEqual(error as? TagError, .originalModified(path: url.resolvingSymlinksInPath().path))
        }
        let data = try bytes(url)
        XCTAssertEqual(data.suffix(6), Data("EXTERN".utf8), "external change kept")
        XCTAssertEqual(try TagFile.read(url: url).values.title, "Fixture Title")
        XCTAssertEqual(leftoverTempFiles(in: music), [])
        XCTAssertEqual(backupFiles(), [])
        XCTAssertTrue(w.journals().isEmpty)
    }

    func testOriginalTouchedDuringEditIsDetectedByModificationTime() throws {
        let url = try copyFixture("tta.tta", into: music)
        let w = writer()
        w.hooks.beforeReplace = { original in
            let date = Date(timeIntervalSinceNow: -3600)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: original.path)
        }
        XCTAssertThrowsError(try w.write(url: url, edit: titleEdit("x"))) { error in
            guard case .originalModified? = error as? TagError else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try TagFile.read(url: url).values.title, "Fixture Title")
    }

    func testReadOnlyFileIsRefused() throws {
        let url = try copyFixture("flac.flac", into: music)
        let original = try bytes(url)
        XCTAssertEqual(chmod(url.path, 0o444), 0)
        XCTAssertFalse(try TagFile.read(url: url).writable)
        XCTAssertThrowsError(try writer().write(url: url, edit: titleEdit("x"))) { error in
            XCTAssertEqual(error as? TagError, .fileReadOnly(path: url.resolvingSymlinksInPath().path))
            XCTAssertTrue((error as? TagError)?.localizedDescription.contains("schreibgeschützt") == true)
        }
        try assertUntouched(url, original: original)
    }

    func testReadOnlyDirectoryIsRefused() throws {
        let url = try copyFixture("flac.flac", into: music)
        let original = try bytes(url)
        XCTAssertEqual(chmod(music.path, 0o555), 0)
        defer { _ = chmod(music.path, 0o755) }
        XCTAssertThrowsError(try writer().write(url: url, edit: titleEdit("x"))) { error in
            guard case .directoryNotWritable? = error as? TagError else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try bytes(url), original)
    }

    func testMissingFileAndUnsupportedFile() throws {
        let missing = music.appendingPathComponent("weg.mp3")
        XCTAssertThrowsError(try writer().write(url: missing, edit: titleEdit("x"))) { error in
            XCTAssertEqual(error as? TagError, .fileNotFound(path: missing.resolvingSymlinksInPath().path))
        }
        let text = music.appendingPathComponent("notes.mp3")
        try Data("kein Audio".utf8).write(to: text)
        XCTAssertThrowsError(try writer().write(url: text, edit: titleEdit("x"))) { error in
            guard let e = error as? TagError else { return XCTFail("\(error)") }
            switch e {
            case .unsupportedFormat, .invalidFile: break
            default: XCTFail("\(e)")
            }
        }
        XCTAssertThrowsError(try writer().write(url: music, edit: titleEdit("x"))) { error in
            XCTAssertEqual(error as? TagError, .notAFile(path: music.resolvingSymlinksInPath().path))
        }
        let empty = try copyFixture("flac.flac", into: music)
        XCTAssertThrowsError(try writer().write(url: empty, edit: TagEdit())) { error in
            XCTAssertEqual(error as? TagError, .nothingToWrite(path: empty.resolvingSymlinksInPath().path))
        }
        XCTAssertEqual(backupFiles(), [])
    }

    func testInsufficientDiskSpaceIsRefused() throws {
        let url = try copyFixture("aiff.aiff", into: music)
        let original = try bytes(url)
        let w = writer()
        w.hooks.freeSpace = { _ in 10_000 }
        XCTAssertThrowsError(try w.write(url: url, edit: titleEdit("x"))) { error in
            guard case .insufficientDiskSpace(_, let required, let available)? = error as? TagError else {
                return XCTFail("\(error)")
            }
            XCTAssertGreaterThan(required, available)
        }
        try assertUntouched(url, original: original)
    }

    func testFormatThatWouldLoseDataIsRefused() throws {
        let url = try copyFixture("aac.m4a", into: music)
        var data = try bytes(url)
        let xyz = try XCTUnwrap(data.range(of: Data([0xA9]) + Data("xyz".utf8)))
        let atom = try XCTUnwrap(data[xyz.upperBound...].range(of: Data("data".utf8)))
        data[atom.upperBound + 3] = 99
        try data.write(to: url)
        XCTAssertThrowsError(try writer().write(url: url, edit: titleEdit("x"))) { error in
            guard case .formatNotWritable? = error as? TagError else { return XCTFail("\(error)") }
        }
        try assertUntouched(url, original: data)
    }

    // MARK: - Batch

    func testBatchContinuesAfterFailures() throws {
        let a = try copyFixture("id3v23.mp3", into: music)
        let b = try copyFixture("flac.flac", into: music)
        XCTAssertEqual(chmod(b.path, 0o444), 0)
        let bOriginal = try bytes(b)
        let c = music.appendingPathComponent("missing.ogg")
        let d = try copyFixture("aac.m4a", into: music)
        var progress: [Int] = []
        let result = writer().write(batch: [a, b, c, d].map { TagWriteRequest(url: $0, edit: titleEdit("Stapel")) },
                                    progress: { done, total in
                                        XCTAssertEqual(total, 4)
                                        progress.append(done)
                                    })
        XCTAssertEqual(progress, [1, 2, 3, 4])
        XCTAssertEqual(result.succeededCount, 2)
        XCTAssertEqual(result.failed.map(\.url), [b, c])
        XCTAssertEqual(result.results[1].error, .fileReadOnly(path: b.resolvingSymlinksInPath().path))
        XCTAssertEqual(result.results[2].error, .fileNotFound(path: c.resolvingSymlinksInPath().path))
        XCTAssertEqual(try TagFile.read(url: a).values.title, "Stapel")
        XCTAssertEqual(try TagFile.read(url: d).values.title, "Stapel")
        XCTAssertEqual(try bytes(b), bOriginal)
        let journal = try XCTUnwrap(try writer().journal(batch: result.batchID))
        XCTAssertEqual(journal.entries.count, 2)
        XCTAssertEqual(leftoverTempFiles(in: music), [])
    }

    // MARK: - Undo

    func testUndoRestoresByteIdenticalOriginals() throws {
        let names = ["id3v23.mp3", "aac.m4a", "flac.flac", "wave.wav", "wma.wma"]
        let urls = try names.map { try copyFixture($0, into: music) }
        let originals = try urls.map { try bytes($0) }
        let w = writer()
        let result = w.write(batch: urls.map { TagWriteRequest(url: $0, edit: SampleValues.fullEdit) })
        XCTAssertEqual(result.succeededCount, names.count, "\(result.failed.map { $0.error?.localizedDescription ?? "" })")
        for (url, original) in zip(urls, originals) { XCTAssertNotEqual(try bytes(url), original) }

        let undo = try w.undo(batch: result.batchID)
        XCTAssertTrue(undo.allSucceeded)
        XCTAssertEqual(undo.results.map(\.outcome), Array(repeating: .restored, count: names.count))
        for (url, original) in zip(urls, originals) {
            XCTAssertEqual(try bytes(url), original, url.lastPathComponent)
        }
        XCTAssertTrue(try XCTUnwrap(try w.journal(batch: result.batchID)).entries.allSatisfy { $0.undoneAt != nil })
        // undoing twice is harmless
        let again = try w.undo(batch: result.batchID)
        XCTAssertEqual(again.results.map(\.outcome), Array(repeating: .alreadyOriginal, count: names.count))
        XCTAssertEqual(leftoverTempFiles(in: music), [])
    }

    func testUndoRefusesFileChangedAfterWriteUnlessForced() throws {
        let url = try copyFixture("opus.opus", into: music)
        let original = try bytes(url)
        let w = writer()
        let entry = try w.write(url: url, edit: titleEdit("Bearbeitet"))
        try w.write(url: url, edit: titleEdit("Später geändert"))  // another (separate) edit

        let undo = try w.undo(batch: entry.batchID)
        XCTAssertEqual(undo.results.first?.outcome, .failed(.modifiedSinceWrite(path: entry.originalPath)))
        XCTAssertEqual(try TagFile.read(url: url).values.title, "Später geändert")

        let forced = try w.undo(batch: entry.batchID, force: true)
        XCTAssertEqual(forced.results.first?.outcome, .restored)
        XCTAssertEqual(try bytes(url), original)
    }

    func testUndoWithDamagedOrMissingBackup() throws {
        let url = try copyFixture("speex.spx", into: music)
        let w = writer()
        let entry = try w.write(url: url, edit: titleEdit("Bearbeitet"))
        let edited = try bytes(url)
        // damage the backup
        var backup = try Data(contentsOf: URL(fileURLWithPath: entry.backupPath))
        backup[backup.count / 2] ^= 0xFF
        try backup.write(to: URL(fileURLWithPath: entry.backupPath))
        XCTAssertEqual(try w.undo(batch: entry.batchID).results.first?.outcome,
                       .failed(.backupCorrupted(path: entry.originalPath)))
        XCTAssertEqual(try bytes(url), edited)
        // remove it
        try FileManager.default.removeItem(atPath: entry.backupPath)
        XCTAssertEqual(try w.undo(batch: entry.batchID).results.first?.outcome,
                       .failed(.backupMissing(path: entry.originalPath)))
        XCTAssertEqual(try bytes(url), edited)
        XCTAssertThrowsError(try w.undo(batch: UUID())) { error in
            guard case .batchNotFound? = error as? TagError else { return XCTFail("\(error)") }
        }
    }

    // MARK: - Cleanup

    func testCleanupRemovesOldBackupsAndJournals() throws {
        let old = writer()
        let tenDaysAgo = Date(timeIntervalSinceNow: -10 * 86_400)
        old.hooks.now = { tenDaysAgo }
        let a = try copyFixture("id3v23.mp3", into: music)
        let oldEntry = try old.write(url: a, edit: titleEdit("Alt"))
        let recent = writer()
        let b = try copyFixture("flac.flac", into: music)
        let newEntry = try recent.write(url: b, edit: titleEdit("Neu"))

        XCTAssertTrue(FileManager.default.fileExists(atPath: oldEntry.backupPath))
        XCTAssertEqual(try recent.cleanupBackups(olderThan: 30), 0)
        XCTAssertEqual(try recent.cleanupBackups(olderThan: 7), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldEntry.backupPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: (oldEntry.backupPath as NSString).deletingLastPathComponent))
        XCTAssertNil(try recent.journal(batch: oldEntry.batchID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newEntry.backupPath))
        XCTAssertNotNil(try recent.journal(batch: newEntry.batchID))
        XCTAssertThrowsError(try recent.undo(batch: oldEntry.batchID))
        // unrelated files in the backup root are left alone
        let foreign = backupRoot.appendingPathComponent("notes.txt")
        try Data("x".utf8).write(to: foreign)
        _ = try recent.cleanupBackups(olderThan: 0, now: Date(timeIntervalSinceNow: 2 * 86_400))
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreign.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newEntry.backupPath))
    }

    func testVeryLongFileName() throws {
        let name = String(repeating: "ä", count: 120) + ".flac"  // 245 bytes, close to NAME_MAX
        let url = try copyFixture("flac.flac", as: name, into: music)
        let entry = try writer().write(url: url, edit: titleEdit("Langer Name"))
        XCTAssertEqual(try TagFile.read(url: url).values.title, "Langer Name")
        XCTAssertTrue(entry.backupPath.hasSuffix(".flac"))
        XCTAssertLessThanOrEqual((entry.backupPath as NSString).lastPathComponent.utf8.count, 255)
        XCTAssertEqual(try writer().undo(batch: entry.batchID).results.first?.outcome, .restored)
        XCTAssertEqual(try bytes(url), try Data(contentsOf: Fixtures.url("flac.flac")))
    }

    func testRemoveLeftoverTemporaryFiles() throws {
        let old = music.appendingPathComponent(".mltags-1234-song.mp3")
        let fresh = music.appendingPathComponent(".mltags-5678-song.mp3")
        let normal = try copyFixture("id3v23.mp3", into: music)
        try Data("x".utf8).write(to: old)
        try Data("y".utf8).write(to: fresh)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -7200)], ofItemAtPath: old.path)
        XCTAssertEqual(SafeTagWriter.removeLeftoverTemporaryFiles(in: music), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: normal.path))
    }

    func testDefaultBackupRoot() {
        let root = SafeTagWriter.defaultBackupRoot.path
        XCTAssertTrue(root.hasSuffix("Music Library/Backups"), root)
    }

    // MARK: - Helpers used by the writer

    func testSHA256KnownVectors() {
        XCTAssertEqual(SHA256Digest.hex(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256Digest.hex(Data("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256Digest.hex(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        let million = Data(repeating: UInt8(ascii: "a"), count: 1_000_000)
        var streamed = SHA256Digest()
        var portable = PortableSHA256()  // the pure Swift fallback is tested on every platform
        for chunk in stride(from: 0, to: million.count, by: 4093) {
            streamed.update(million[chunk..<min(chunk + 4093, million.count)])
            portable.update(million[chunk..<min(chunk + 4093, million.count)])
        }
        XCTAssertEqual(streamed.finalize(), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
        XCTAssertEqual(portable.finalize(), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
        var empty = PortableSHA256()
        XCTAssertEqual(empty.finalize(), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }
}
