import XCTest
@testable import OggVorbis

/// Ogg-Vorbis-Decoder mit selbst erzeugten Testtönen (ffmpeg/libvorbis, siehe Fixtures/README.md).
final class VorbisDecoderTests: XCTestCase {
    private func fixture(_ name: String) -> String {
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!.path
    }

    private func decodeAll(_ d: VorbisDecoder) -> [Float] {
        var all: [Float] = []
        while true {
            let chunk = d.read(frames: 4096)
            if chunk.isEmpty { break }
            all += chunk
        }
        return all
    }

    func testStereoToneProperties() throws {
        let d = try VorbisDecoder(path: fixture("tone-1k-stereo-2s.ogg"))
        XCTAssertEqual(d.channels, 2)
        XCTAssertEqual(d.sampleRate, 44_100)
        XCTAssertEqual(d.totalFrames, 88_200)
        XCTAssertEqual(d.durationMs, 2000)
    }

    func testDecodesFullLengthWithExpectedContent() throws {
        let d = try VorbisDecoder(path: fixture("tone-1k-stereo-2s.ogg"))
        let samples = decodeAll(d)
        XCTAssertEqual(samples.count, 88_200 * 2)
        // Eingeschwungener Teil: Spitze ≈ 0,5, Frequenz ≈ 1 kHz, beide Kanäle gleich
        let left = stride(from: 0, to: samples.count, by: 2).map { samples[$0] }
        let right = stride(from: 1, to: samples.count, by: 2).map { samples[$0] }
        let mid = left[22_050..<66_150]
        let peak = mid.map(abs).max() ?? 0
        XCTAssertEqual(peak, 0.5, accuracy: 0.06)
        var crossings = 0
        for i in mid.indices.dropFirst() where mid[i - 1] < 0 && mid[i] >= 0 { crossings += 1 }
        XCTAssertEqual(Double(crossings) / (Double(mid.count) / 44_100), 1000, accuracy: 10)
        let diff = zip(left, right).map { abs($0 - $1) }.max() ?? 1
        XCTAssertLessThan(diff, 0.02)
    }

    func testMonoLowSampleRate() throws {
        let d = try VorbisDecoder(path: fixture("tone-440-mono-22k.ogg"))
        XCTAssertEqual(d.channels, 1)
        XCTAssertEqual(d.sampleRate, 22_050)
        XCTAssertEqual(decodeAll(d).count, Int(d.totalFrames))
        XCTAssertEqual(d.totalFrames, 33_075)
    }

    func testSeek() throws {
        let d = try VorbisDecoder(path: fixture("tone-1k-stereo-2s.ogg"))
        XCTAssertTrue(d.seek(toFrame: 44_100))
        XCTAssertEqual(decodeAll(d).count, 44_100 * 2)
    }

    func testRejectsNonOggFiles() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("kein-ogg-\(UUID().uuidString).ogg")
        try Data("Das ist keine Ogg-Datei".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        XCTAssertThrowsError(try VorbisDecoder(path: tmp.path))
        XCTAssertThrowsError(try VorbisDecoder(path: "/gibt/es/nicht.ogg"))
    }
}
