import Foundation
import MLCore
import XCTest
@testable import MLTags

/// Vergleicht mit ffmpeg (falls installiert) die MD5-Summen der Audiopakete und der dekodierten
/// PCM-Daten vor und nach dem Schreiben. Ohne ffmpeg wird der Test übersprungen.
final class AudioIntegrityTests: TagTestCase {
    private var ffmpeg: String? {
        ["/usr/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/opt/homebrew/bin/ffmpeg"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// MD5 of the compressed audio packets (stream copy) and of the decoded PCM. Decoding uses
    /// `-flags2 +skip_manual`: ffmpeg's automatic MP3 gapless trimming depends on trailing tags
    /// (e.g. whether an ID3v1 tag exists), which would make the PCM length vary although the
    /// MPEG frames are byte-identical.
    private func decodedMD5(_ url: URL, ffmpeg: String) throws -> String {
        try run(ffmpeg, ["-nostdin", "-v", "error", "-i", url.path, "-map", "0:a", "-c", "copy", "-f", "md5", "-"])
            + " " + run(ffmpeg, ["-nostdin", "-v", "error", "-flags2", "+skip_manual", "-i", url.path,
                                 "-map", "0:a", "-f", "md5", "-"])
    }

    private func run(_ ffmpeg: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testDecodedAudioIsIdenticalAfterWritingEveryFormat() throws {
        guard let ffmpeg else { throw XCTSkip("ffmpeg is not installed") }
        let writer = SafeTagWriter(backupRoot: tempDir.appendingPathComponent("Backups"))
        for fixture in Fixtures.all {
            let url = try copyFixture(fixture.file)
            let before = try decodedMD5(url, ffmpeg: ffmpeg)
            XCTAssertTrue(before.hasPrefix("MD5="), "\(fixture): \(before)")
            try writer.write(url: url, edit: SampleValues.fullEdit)
            XCTAssertEqual(try decodedMD5(url, ffmpeg: ffmpeg), before, "\(fixture) after full edit")
            try writer.write(url: url, edit: SampleValues.clearAll)
            XCTAssertEqual(try decodedMD5(url, ffmpeg: ffmpeg), before, "\(fixture) after clearing")
        }
    }
}
