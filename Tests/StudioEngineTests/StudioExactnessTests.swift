import AVFoundation
import XCTest
import MLCore
import MLStudio
import MLTags
@testable import StudioEngine

/// Bitgenaue Kopien, Schnittgenauigkeit (Klickmarken), Blenden, kurze Ausschnitte, keine Übersteuerung.
final class StudioExactnessTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = try TS.makeDir("exact")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Bytes des „data“-Blocks einer WAV-Datei.
    func wavData(_ url: URL) throws -> Data {
        let d = try Data(contentsOf: url)
        var p = 12
        while p + 8 <= d.count {
            let id = String(decoding: d[p..<(p + 4)], as: UTF8.self)
            let size = Int(d[p + 4]) | Int(d[p + 5]) << 8 | Int(d[p + 6]) << 16 | Int(d[p + 7]) << 24
            if id == "data" { return d[(p + 8)..<min(d.count, p + 8 + size)] }
            p += 8 + size + (size & 1)
        }
        throw StudioError.decodeFailed("kein data-Block")
    }

    func testBitExactWAVCopies() async throws {
        for bits in [16, 24, 32] {
            let source = try TS.writePCM(dir.appendingPathComponent("q\(bits).wav"), rate: 44_100, channels: 2, bits: bits, seconds: 3, signal: .sweep)
            // „Format wie Original“ (ohne Neukodierung) – Bittiefe der Quelle bleibt, egal was eingestellt ist
            let out = dir.appendingPathComponent("kopie\(bits).wav")
            let (r, _) = try await TS.export(ExportRequest(input: source, trim: nil, options: ExportOptions(format: .wav, pcmDepth: .int16),
                                                           metadata: StudioMetadata(), output: out, preferPassthrough: true))
            let a = try TS.readAll(source), b = try TS.readAll(out)
            XCTAssertEqual(a.channels, b.channels, "WAV \(bits) Bit: Samples identisch")
            XCTAssertEqual(try wavData(source), try wavData(out), "WAV \(bits) Bit: data-Block identisch")
            XCTAssertTrue(r.passthrough, "WAV \(bits) Bit: als verlustfreie Kopie gekennzeichnet")
            XCTAssertEqual(r.bitDepth, bits)
            TS.log("Bitgenaue Kopie WAV \(bits) Bit → WAV: Samples und data-Block identisch, passthrough=\(r.passthrough)")
        }
        // Normaler Weg 16 → 16 Bit: ebenfalls exakt (kein Dither, da nichts verändert wird)
        let s16 = dir.appendingPathComponent("q16.wav")
        let out = dir.appendingPathComponent("normal16.wav")
        let (r, _) = try await TS.export(ExportRequest(input: s16, trim: nil, options: ExportOptions(format: .wav, pcmDepth: .int16),
                                                       metadata: StudioMetadata(), output: out))
        XCTAssertEqual(try wavData(s16), try wavData(out), "WAV 16 → WAV 16 ohne Dither")
        XCTAssertFalse(r.passthrough)
    }

    func testBitExactFLACAndAIFF() async throws {
        for bits in [16, 24] {
            let wav = try TS.writePCM(dir.appendingPathComponent("w\(bits).wav"), rate: 48_000, channels: 2, bits: bits, seconds: 3, signal: .sweep)
            let flac = dir.appendingPathComponent("f\(bits).flac")
            _ = try await TS.export(ExportRequest(input: wav, trim: nil, options: ExportOptions(format: .flac, flacKeepSourceDepth: true, flacLevel: 5),
                                                  metadata: StudioMetadata(), output: flac))
            let w = try TS.readAll(wav), f = try TS.readAll(flac)
            XCTAssertEqual(w.channels, f.channels, "WAV \(bits) → FLAC verlustfrei")
            let copy = dir.appendingPathComponent("f\(bits)-kopie.flac")
            let (r, _) = try await TS.export(ExportRequest(input: flac, trim: nil, options: ExportOptions(format: .flac, flacKeepSourceDepth: false, flacLevel: 8),
                                                           metadata: TS.metadata(cover: TS.jpeg), output: copy, preferPassthrough: true))
            let c = try TS.readAll(copy)
            XCTAssertEqual(f.channels, c.channels, "FLAC \(bits) → FLAC bitgenau")
            XCTAssertEqual(r.bitDepth, bits)
            XCTAssertTrue(r.passthrough)
            let md5a = try Data(contentsOf: flac)[26..<42], md5b = try Data(contentsOf: copy)[26..<42]
            XCTAssertEqual(md5a, md5b, "FLAC-MD5 gleich")
            XCTAssertNotEqual(md5a, Data(count: 16), "FLAC-MD5 gesetzt")
            TS.log("Bitgenaue Kopie FLAC \(bits) Bit → FLAC: Samples identisch, MD5 \(md5b.map { String(format: "%02x", $0) }.joined())")

            let aiff = dir.appendingPathComponent("a\(bits).aiff")
            _ = try await TS.export(ExportRequest(input: wav, trim: nil, options: ExportOptions(format: .aiff, pcmDepth: bits == 16 ? .int16 : .int24),
                                                  metadata: StudioMetadata(), output: aiff))
            let aiffCopy = dir.appendingPathComponent("a\(bits)-kopie.aiff")
            let (ra, _) = try await TS.export(ExportRequest(input: aiff, trim: nil, options: ExportOptions(format: .aiff, pcmDepth: .float32),
                                                            metadata: StudioMetadata(), output: aiffCopy, preferPassthrough: true))
            XCTAssertEqual(try TS.readAll(aiffCopy).channels, w.channels, "AIFF \(bits) → AIFF bitgenau")
            XCTAssertEqual(ra.bitDepth, bits)
        }
    }

    /// Klickmarken: der Ausschnitt muss auf den Frame genau sitzen.
    func testTrimAccuracyWithClickMarkers() async throws {
        let rate = 44_100.0
        let clicks = stride(from: 4_410, to: 220_500, by: 22_050).map { $0 + 37 }   // alle 0,5 s, krumme Lage
        let wav = try TS.writePCM(dir.appendingPathComponent("klick.wav"), rate: rate, channels: 2, bits: 16, seconds: 5, signal: .clicks(clicks))
        let flac = dir.appendingPathComponent("klick.flac")
        _ = try await TS.export(ExportRequest(input: wav, trim: nil, options: ExportOptions(format: .flac), metadata: StudioMetadata(), output: flac))
        let trim = TrimRange(start: 1.2345, end: 3.3456)
        let startFrame = Int((trim.start * rate).rounded())
        let endFrame = Int((trim.end * rate).rounded())
        let expected = clicks.filter { $0 >= startFrame && $0 < endFrame }.map { $0 - startFrame }
        var failures: [String] = []
        for (source, name) in [(wav, "WAV"), (flac, "FLAC")] {
            for format in [StudioFormat.wav, .flac, .aiff] {
                let out = dir.appendingPathComponent("schnitt-\(name).\(format.fileExtension)")
                let (r, _) = try await TS.export(ExportRequest(input: source, trim: trim, options: ExportOptions(format: format, pcmDepth: .int16, flacKeepSourceDepth: true),
                                                               metadata: StudioMetadata(), output: out))
                let a = try TS.readAll(out)
                let found = TS.clickPositions(a)
                let ok = found == expected && a.frames == endFrame - startFrame
                if !ok { failures.append("\(name) → \(format.label): Klicks \(found) statt \(expected), Frames \(a.frames) statt \(endFrame - startFrame)") }
                TS.log("Schnitt \(name) → \(format.label): \(a.frames) Frames (erwartet \(endFrame - startFrame)), Klickversatz \(zip(found, expected).map { $0 - $1 }), Dauer \(String(format: "%.6f", r.duration)) s")
            }
        }
        // Verlustbehaftete Quellen: Versatz nur berichten (Decoder-Genauigkeit von AVFoundation)
        for format in [StudioFormat.mp3, .m4a] {
            let lossy = dir.appendingPathComponent("klick.\(format.fileExtension)")
            _ = try await TS.export(ExportRequest(input: wav, trim: nil, options: ExportOptions.defaults(for: format), metadata: StudioMetadata(), output: lossy))
            let out = dir.appendingPathComponent("schnitt-aus-\(format.rawValue).wav")
            _ = try await TS.export(ExportRequest(input: lossy, trim: trim, options: ExportOptions(format: .wav), metadata: StudioMetadata(), output: out))
            let a = try TS.readAll(out)
            // Lauteste Stelle um den ersten erwarteten Klick (Codecs verschmieren Klicks etwas)
            let e0 = expected.first ?? 0
            let lo = max(0, e0 - 2_000), hi = min(a.frames, e0 + 2_000)
            var firstFound = -1
            var best: Float = 0
            for i in lo..<hi where abs(a.channels[0][i]) > best { best = abs(a.channels[0][i]); firstFound = i }
            TS.log("Schnitt aus \(format.label) → WAV: \(a.frames) Frames (erwartet \(endFrame - startFrame)), erster Klick bei \(firstFound) (erwartet \(e0), Versatz \(firstFound - e0) Frames, Pegel \(String(format: "%.2f", best)))")
            XCTAssertLessThanOrEqual(abs(firstFound - e0), 64, "\(format.label): Klick innerhalb ±64 Frames")
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    func testFadesAreSmoothAndExact() async throws {
        let rate = 48_000.0
        let source = try TS.writePCM(dir.appendingPathComponent("sinus.wav"), rate: rate, channels: 2, bits: 32, seconds: 4, signal: .sine(1000, 0.5))
        let out = dir.appendingPathComponent("blende.wav")
        _ = try await TS.export(ExportRequest(input: source, trim: TrimRange(start: 0.5, end: 3.5), options: ExportOptions(format: .wav, pcmDepth: .float32),
                                              metadata: StudioMetadata(), output: out, fadeIn: 1.0, fadeOut: 1.0))
        let a = try TS.readAll(out)
        let src = try TS.readAll(source)
        XCTAssertEqual(a.frames, Int(3 * rate))
        func envelope(_ t: Double) -> Float {
            let i0 = Int(t * rate), i1 = min(a.frames, i0 + Int(rate / 500))   // 2 ms ≥ eine Periode
            return a.channels[0][i0..<i1].map { abs($0) }.max() ?? 0
        }
        let e0 = abs(a.channels[0][0]), eQuarter = envelope(0.25), eHalf = envelope(0.5), eFull = envelope(1.5)
        let eEnd = abs(a.channels[0][a.frames - 1]), eOutHalf = envelope(2.5 - 0.002)
        TS.log(String(format: "Blenden: Anfang %.5f, 0,25 s %.3f, 0,5 s %.3f, Mitte %.3f, 2,5 s %.3f, Ende %.5f (Sinus 0,5)", e0, eQuarter, eHalf, eFull, eOutHalf, eEnd))
        XCTAssertLessThan(e0, 0.001)
        XCTAssertLessThan(eEnd, 0.001)
        XCTAssertEqual(eHalf, 0.25, accuracy: 0.02, "Halbkosinus: Hälfte der Amplitude in der Mitte der Blende")
        XCTAssertLessThan(eQuarter, eHalf)
        XCTAssertEqual(eFull, 0.5, accuracy: 0.001)
        XCTAssertEqual(eOutHalf, 0.25, accuracy: 0.02)
        // Zwischen den Blenden bitgenau unverändert
        let offset = Int(0.5 * rate)
        for i in stride(from: Int(1.05 * rate), to: Int(1.95 * rate), by: 7) {
            XCTAssertEqual(a.channels[0][i], src.channels[0][i + offset])
        }
    }

    func testVeryShortSelections() async throws {
        let source = try TS.writePCM(dir.appendingPathComponent("kurz.wav"), rate: 44_100, channels: 2, bits: 16, seconds: 3, signal: .sweep)
        var failures: [String] = []
        for format in StudioFormat.allCases {
            let out = dir.appendingPathComponent("kurz.\(format.fileExtension)")
            let (r, _) = try await TS.export(ExportRequest(input: source, trim: TrimRange(start: 1.0, end: 1.2), options: .defaults(for: format),
                                                           metadata: TS.metadata(cover: nil), output: out))
            let err = (r.duration - 0.2) * 1000
            TS.log(String(format: "Ausschnitt 0,2 s → %@: Dauer %.4f s (Δ %+.2f ms)", format.label, r.duration, err))
            let tol = format.isLossless ? 0.03 : (format == .aac ? 120 : 30)
            if abs(err) > tol { failures.append("\(format.label): Δ \(err) ms") }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    /// Vollaussteuerung + Abtastratenwandlung + 16 Bit: weich begrenzt, keine Übersteuerung.
    func testNoClippingAfterResampling() async throws {
        let source = try TS.writePCM(dir.appendingPathComponent("laut.wav"), rate: 44_100, channels: 2, bits: 32, seconds: 2, signal: .sine(9_000, 0.999))
        let out = dir.appendingPathComponent("laut48.wav")
        _ = try await TS.export(ExportRequest(input: source, trim: nil, options: ExportOptions(format: .wav, pcmDepth: .int16, sampleRate: 48_000),
                                              metadata: StudioMetadata(), output: out))
        let a = try TS.readAll(out)
        let peak = a.channels.flatMap { $0 }.map { abs($0) }.max() ?? 0
        let clipped = a.channels.flatMap { $0 }.filter { $0 <= -1 || $0 >= 32_767.0 / 32_768 }.count
        TS.log(String(format: "Keine Übersteuerung: Spitze %.5f, Samples an der Grenze %d", peak, clipped))
        XCTAssertLessThan(peak, 1.0)
        XCTAssertEqual(clipped, 0)
    }
}
