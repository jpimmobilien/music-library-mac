import AVFoundation
import XCTest
import MLCore
import MLStudio
import MLTags
@testable import StudioEngine

/// Schneiden ohne Neukodierung (MP3 an Frame-Grenzen, M4A über AVAssetExportSession) inkl. Dauer und Tags.
final class StudioPassthroughTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = try TS.makeDir("pass")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Quelle mit allen Tag-Arten (inkl. Liedtext, Sortierfelder, WebP-Cover) für `copyTagsFrom`.
    func richTags(_ url: URL, webpCover: Bool = true) throws {
        var v = TagValues()
        v.title = "Original-Titel"
        v.artists = ["Original-Interpret"]
        v.album = "Original-Album"
        v.year = 1999
        v.genres = ["Jazz"]
        v.trackNumber = 3
        v.lyrics = "Erste Zeile\nZweite Zeile"
        v.titleSort = "Titel, Original"
        v.artistSort = "Interpret, Original"
        v.comment = "Kommentar"
        v.composers = ["Komponist"]
        let front = webpCover ? EmbeddedPicture(kind: .frontCover, mimeType: "image/webp", data: TS.webp)
                              : EmbeddedPicture(kind: .frontCover, mimeType: "image/jpeg", data: TS.jpeg)
        let pics = [front,
                    EmbeddedPicture(kind: .backCover, mimeType: "image/png", data: TS.png)]
        try TagFile.write(url: url, edit: TagEdit(values: v, fields: Set(TagField.allCases), pictures: .replaceAll(pics)))
    }

    func testMP3PassthroughCutsAtFrameBoundaries() async throws {
        let wav = try TS.writePCM(dir.appendingPathComponent("q.wav"), rate: 44_100, channels: 2, bits: 16, seconds: 30, signal: .sweep)
        let mp3 = dir.appendingPathComponent("q.mp3")
        _ = try await TS.export(ExportRequest(input: wav, trim: nil, options: ExportOptions(format: .mp3, mp3Bitrate: 192), metadata: StudioMetadata(), output: mp3))
        try richTags(mp3)
        let sourceInfo = try MP3Stream.scan(url: mp3)

        let out = dir.appendingPathComponent("schnitt.mp3")
        let trim = TrimRange(start: 5.0, end: 15.0)
        let (r, _) = try await TS.export(ExportRequest(input: mp3, trim: trim, options: ExportOptions(format: .mp3, mp3Bitrate: 320),
                                                       metadata: StudioMetadata(title: "Neuer Titel"), output: out,
                                                       preferPassthrough: true, copyTagsFrom: mp3))
        XCTAssertTrue(r.passthrough)
        XCTAssertEqual(r.bitrateKbps, 192, "Bitrate der Quelle bleibt (keine Neukodierung)")
        let info = try MP3Stream.scan(url: out)
        // Die Audioframes sind Byte für Byte die der Quelle
        let src = try Data(contentsOf: mp3), dst = try Data(contentsOf: out)
        let firstOut = Int(info.frameOffsets[0])
        let firstInSource = src.range(of: dst[firstOut..<(firstOut + 2_000)])
        XCTAssertNotNil(firstInSource, "Frames unverändert übernommen")
        if let range = firstInSource {
            let len = Int(info.audioEnd) - firstOut
            XCTAssertEqual(src[range.lowerBound..<(range.lowerBound + len)], dst[firstOut..<(firstOut + len)])
        }
        let avDuration = r.duration
        let ffFrames = TS.ffmpegDecodedFrames(out, channels: 2)
        TS.log(String(format: "MP3 ohne Neukodierung 5–15 s: AVAudioFile %.4f s (Δ %+.2f ms), LAME-Angaben %.4f s, FFmpeg %@ Frames (erwartet 441000), %d Frames, Verzögerung %@, Auffüllung %@",
                      avDuration, (avDuration - 10) * 1000, info.duration, ffFrames.map { "\($0)" } ?? "–", info.frameCount,
                      info.infoTag?.encoderDelay.map { "\($0)" } ?? "–", info.infoTag?.encoderPadding.map { "\($0)" } ?? "–"))
        XCTAssertEqual(info.duration, 10, accuracy: 0.0001, "samplegenau laut LAME-Angaben")
        XCTAssertEqual(avDuration, 10, accuracy: 0.03, "Dauer laut AVAudioFile ±30 ms")
        if let ffFrames { XCTAssertEqual(ffFrames, 441_000, "FFmpeg dekodiert samplegenau") }
        XCTAssertLessThan(Double(info.frameCount) * 1152 / 44_100, sourceInfo.duration)

        // Klang: gegen den entsprechenden Abschnitt der dekodierten Quelle
        let whole = try TS.readAll(mp3), cut = try TS.readAll(out)
        let offset = Int(5.0 * 44_100)
        let refPart = whole.channels.map { Array($0[offset..<min($0.count, offset + cut.frames)]) }
        let (lag, snr) = TS.alignedSNR(reference: refPart, test: cut.channels)
        TS.log(String(format: "MP3 ohne Neukodierung: Versatz %d Frames, Störabstand zur Quelle %.1f dB", lag, snr))
        XCTAssertLessThanOrEqual(abs(lag), 2)
        XCTAssertGreaterThan(snr, 40)

        // Tags: alle aus dem Original, Titel überschrieben, WebP-Cover als JPEG
        let tags = try TagFile.read(url: out).values
        XCTAssertEqual(tags.title, "Neuer Titel")
        XCTAssertEqual(tags.artists, ["Original-Interpret"])
        XCTAssertEqual(tags.lyrics, "Erste Zeile\nZweite Zeile")
        XCTAssertEqual(tags.titleSort, "Titel, Original")
        XCTAssertEqual(tags.artistSort, "Interpret, Original")
        XCTAssertEqual(tags.composers, ["Komponist"])
        XCTAssertEqual(tags.year, 1999)
        XCTAssertEqual(tags.pictures.count, 2)
        XCTAssertEqual(tags.frontCover.flatMap { ImageProbe.mimeType(of: $0.data) }, "image/jpeg", "WebP-Cover in JPEG umgewandelt")
        XCTAssertEqual(tags.pictures.first { $0.kind == .backCover }?.data, TS.png)
        TS.log("MP3 ohne Neukodierung: Tags übernommen (Liedtext, Sortierfelder, 2 Bilder, WebP → JPEG)")

        // Ganze Datei, Ausschnitt am Anfang und am Ende
        for (t, expected) in [(TrimRange(start: 0, end: 2), 2.0), (TrimRange(start: 28, end: 30), 2.0), (TrimRange(start: 10, end: 10.2), 0.2)] {
            let o = dir.appendingPathComponent("teil-\(t.start).mp3")
            let (rr, _) = try await TS.export(ExportRequest(input: mp3, trim: t, options: ExportOptions(format: .mp3), metadata: StudioMetadata(), output: o, preferPassthrough: true))
            let i = try MP3Stream.scan(url: o)
            let ff = TS.ffmpegDecodedFrames(o, channels: 2)
            TS.log(String(format: "MP3 ohne Neukodierung %.1f–%.1f s: AVAudioFile %.4f s, LAME %.4f s, FFmpeg %@ Frames (erwartet %d)",
                          t.start, t.end, rr.duration, i.duration, ff.map { "\($0)" } ?? "–", Int(expected * 44_100)))
            XCTAssertTrue(rr.passthrough)
            XCTAssertEqual(i.duration, expected, accuracy: 0.0001)
            XCTAssertEqual(rr.duration, expected, accuracy: 0.03)
            if let ff { XCTAssertEqual(ff, Int(expected * 44_100)) }
        }
    }

    func testM4APassthrough() async throws {
        let wav = try TS.writePCM(dir.appendingPathComponent("q.wav"), rate: 44_100, channels: 2, bits: 16, seconds: 30, signal: .sweep)
        let m4a = dir.appendingPathComponent("q.m4a")
        let (orig, _) = try await TS.export(ExportRequest(input: wav, trim: nil, options: ExportOptions(format: .m4a, aacBitrate: 192),
                                                          metadata: TS.metadata(cover: TS.jpeg), output: m4a))
        try richTags(m4a, webpCover: false)   // MP4 „covr“ kennt kein WebP
        for (trim, expected) in [(TrimRange(start: 5, end: 15), 10.0), (TrimRange(start: 1, end: 1.2), 0.2)] {
            let out = dir.appendingPathComponent("schnitt-\(trim.start).m4a")
            let (r, _) = try await TS.export(ExportRequest(input: m4a, trim: trim, options: ExportOptions(format: .m4a, aacBitrate: 320),
                                                           metadata: StudioMetadata(), output: out, preferPassthrough: true, copyTagsFrom: m4a))
            let ff = TS.ffmpegDecodedFrames(out, channels: 2)
            TS.log(String(format: "M4A ohne Neukodierung %.1f–%.1f s: Dauer %.4f s (Δ %+.2f ms), %d kbit/s (Quelle %d), FFmpeg %@ Frames, passthrough=%@",
                          trim.start, trim.end, r.duration, (r.duration - expected) * 1000, r.bitrateKbps, orig.bitrateKbps,
                          ff.map { "\($0)" } ?? "–", r.passthrough ? "ja" : "nein"))
            XCTAssertTrue(r.passthrough)
            XCTAssertEqual(r.duration, expected, accuracy: 0.05)
            let tags = try TagFile.read(url: out).values
            XCTAssertEqual(tags.title, "Original-Titel")
            XCTAssertEqual(tags.lyrics, "Erste Zeile\nZweite Zeile")
            XCTAssertNotNil(tags.frontCover)
        }
        // Klang des 10-s-Schnitts gegen die Quelle
        let whole = try TS.readAll(m4a), cut = try TS.readAll(dir.appendingPathComponent("schnitt-5.0.m4a"))
        let offset = Int(5.0 * 44_100)
        let refPart = whole.channels.map { Array($0[offset..<min($0.count, offset + cut.frames)]) }
        let (lag, snr) = TS.alignedSNR(reference: refPart, test: cut.channels)
        TS.log(String(format: "M4A ohne Neukodierung: Versatz %d Frames, Störabstand zur Quelle %.1f dB", lag, snr))
    }

    /// Blenden erzwingen Neukodierung; andere Formate ebenfalls.
    func testPassthroughOnlyWhenPossible() async throws {
        let wav = try TS.writePCM(dir.appendingPathComponent("q.wav"), rate: 44_100, channels: 2, bits: 16, seconds: 5, signal: .sweep)
        let mp3 = dir.appendingPathComponent("q.mp3")
        _ = try await TS.export(ExportRequest(input: wav, trim: nil, options: ExportOptions(format: .mp3), metadata: StudioMetadata(), output: mp3))
        let (a, _) = try await TS.export(ExportRequest(input: mp3, trim: TrimRange(start: 1, end: 3), options: ExportOptions(format: .mp3),
                                                       metadata: StudioMetadata(), output: dir.appendingPathComponent("blende.mp3"),
                                                       fadeIn: 0.5, preferPassthrough: true))
        XCTAssertFalse(a.passthrough, "Blende → Neukodierung")
        let (b, _) = try await TS.export(ExportRequest(input: mp3, trim: TrimRange(start: 1, end: 3), options: ExportOptions(format: .m4a),
                                                       metadata: StudioMetadata(), output: dir.appendingPathComponent("anders.m4a"), preferPassthrough: true))
        XCTAssertFalse(b.passthrough, "anderes Format → Neukodierung")
        let (c, _) = try await TS.export(ExportRequest(input: mp3, trim: TrimRange(start: 1, end: 3), options: ExportOptions(format: .mp3, sampleRate: 48_000),
                                                       metadata: StudioMetadata(), output: dir.appendingPathComponent("rate.mp3"), preferPassthrough: true))
        XCTAssertFalse(c.passthrough, "andere Abtastrate → Neukodierung")
        XCTAssertEqual(c.sampleRate, 48_000)
        TS.log("Ohne Neukodierung nur, wenn möglich: Blende/anderes Format/andere Rate → neu kodiert")
    }
}
