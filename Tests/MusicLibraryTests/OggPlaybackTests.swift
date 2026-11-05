import XCTest
import AVFoundation
@testable import MusicLibrary

/// Ogg Vorbis → CAF für die Wiedergabe über AVAudioFile.
final class OggPlaybackTests: XCTestCase {
    private var fixture: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("OggVorbisTests/Fixtures/tone-1k-stereo-2s.ogg")
    }

    func testTranscodedFileIsPlayableWithFullLength() throws {
        // Kopie mit eigenem Namen, damit der Test den Zwischenspeicher nicht mit echten Dateien teilt
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ogg-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("Ton.ogg")
        try FileManager.default.copyItem(at: fixture, to: source)

        XCTAssertTrue(OggTranscoder.isOgg(source))
        XCTAssertNil(OggTranscoder.cached(for: source))
        let decoded = try OggTranscoder.decode(source)
        defer { try? FileManager.default.removeItem(at: decoded) }
        XCTAssertEqual(OggTranscoder.cached(for: source), decoded)

        let file = try AVAudioFile(forReading: decoded)
        XCTAssertEqual(file.length, 88_200)
        XCTAssertEqual(file.processingFormat.sampleRate, 44_100)
        XCTAssertEqual(file.processingFormat.channelCount, 2)

        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let left = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
        let peak = left[22_050..<66_150].map(abs).max() ?? 0
        XCTAssertEqual(peak, 0.5, accuracy: 0.06)
    }

    func testNonVorbisOggFails() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ogg-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bogus = dir.appendingPathComponent("kaputt.ogg")
        try Data(repeating: 7, count: 4096).write(to: bogus)
        XCTAssertThrowsError(try OggTranscoder.decode(bogus))
        XCTAssertNil(OggTranscoder.cached(for: bogus))
    }
}
