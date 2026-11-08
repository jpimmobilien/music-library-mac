import Foundation
import MLStudio

// MP3 ohne Neukodierung: Frames finden (ID3v2/ID3v1/APE überspringen), alten Xing/Info-Frame verwerfen,
// an Frame-Grenzen schneiden und einen neuen Info/Xing-Frame mit LAME-Erweiterung schreiben.
// Reines Swift – auch unter Linux testbar.

/// Kopf eines MPEG-Audio-Frames (nur Layer III).
struct MP3FrameHeader: Equatable {
    enum Version: Equatable {
        case mpeg1, mpeg2, mpeg25
    }

    let version: Version
    let bitrateIndex: Int
    let bitrateKbps: Int
    let sampleRateIndex: Int
    let sampleRate: Int
    let padding: Bool
    let hasCRC: Bool
    /// 0 = Stereo, 1 = Joint Stereo, 2 = Zweikanal, 3 = Mono
    let channelMode: Int
    /// Byte 3 des Kopfes (Kanalmodus, Erweiterung, Copyright, Original, Emphasis).
    let byte3: UInt8

    static let bitratesV1: [Int] = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0]
    static let bitratesV2: [Int] = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0]

    var isMono: Bool { channelMode == 3 }
    var channels: Int { isMono ? 1 : 2 }
    var samplesPerFrame: Int { version == .mpeg1 ? 1152 : 576 }
    var frameLength: Int { Self.frameLength(version: version, kbps: bitrateKbps, sampleRate: sampleRate, padding: padding) }
    /// Größe der Seiteninformation (ohne Kopf und CRC).
    var sideInfoSize: Int { version == .mpeg1 ? (isMono ? 17 : 32) : (isMono ? 9 : 17) }

    static func frameLength(version: Version, kbps: Int, sampleRate: Int, padding: Bool) -> Int {
        let base = version == .mpeg1 ? 144_000 * kbps / sampleRate : 72_000 * kbps / sampleRate
        return base + (padding ? 1 : 0)
    }

    static func parse(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8) -> MP3FrameHeader? {
        guard b0 == 0xFF, b1 & 0xE0 == 0xE0 else { return nil }
        let versionBits = (b1 >> 3) & 3
        let layerBits = (b1 >> 1) & 3
        guard versionBits != 1, layerBits == 1 else { return nil }   // 1 = reserviert; Layer III = 01
        let version: Version = versionBits == 3 ? .mpeg1 : (versionBits == 2 ? .mpeg2 : .mpeg25)
        let brIdx = Int(b2 >> 4)
        guard brIdx != 0, brIdx != 15 else { return nil }   // freies Format wird nicht unterstützt
        let srIdx = Int((b2 >> 2) & 3)
        guard srIdx != 3 else { return nil }
        guard b3 & 3 != 2 else { return nil }   // reservierte Emphasis
        let rates: [Int]
        switch version {
        case .mpeg1: rates = [44_100, 48_000, 32_000]
        case .mpeg2: rates = [22_050, 24_000, 16_000]
        case .mpeg25: rates = [11_025, 12_000, 8_000]
        }
        let kbps = version == .mpeg1 ? bitratesV1[brIdx] : bitratesV2[brIdx]
        return MP3FrameHeader(version: version, bitrateIndex: brIdx, bitrateKbps: kbps, sampleRateIndex: srIdx,
                              sampleRate: rates[srIdx], padding: (b2 >> 1) & 1 == 1, hasCRC: b1 & 1 == 0,
                              channelMode: Int(b3 >> 6), byte3: b3)
    }

    /// Gleicher Datenstrom (Version, Abtastrate, Kanalzahl)?
    func isCompatible(with other: MP3FrameHeader) -> Bool {
        version == other.version && sampleRate == other.sampleRate && isMono == other.isMono
    }

    /// Kopf-Bytes mit gewünschtem Bitraten-Index, ohne CRC und ohne Auffüllung.
    func bytes(bitrateIndex idx: Int) -> [UInt8] {
        let versionBits: UInt8 = version == .mpeg1 ? 3 : (version == .mpeg2 ? 2 : 0)
        let b1: UInt8 = 0xE0 | (versionBits << 3) | (1 << 1) | 1   // Layer III, ohne CRC
        let b2: UInt8 = UInt8(idx << 4) | UInt8(sampleRateIndex << 2)
        return [0xFF, b1, b2, byte3]
    }
}

/// Inhalt eines Xing/Info-Frames (und der LAME-Erweiterung).
struct MP3InfoTag: Equatable {
    var isInfo: Bool
    var frames: Int?
    var bytes: Int?
    var encoder: String?
    var encoderDelay: Int?
    var encoderPadding: Int?
}

/// Aufbau einer MP3-Datei.
struct MP3StreamInfo {
    /// Erster Audioframe (nach ID3v2 und nach einem vorhandenen Xing/Info-Frame).
    var frameOffsets: [Int64]
    /// Ende des letzten vollständigen Frames.
    var audioEnd: Int64
    /// Kopf des ersten Audioframes.
    var header: MP3FrameHeader
    /// Alle Audioframes haben dieselbe Bitrate.
    var isCBR: Bool
    var infoTag: MP3InfoTag?
    var id3v2Size: Int64
    /// Summe der Frame-Bytes (ohne Infoframe).
    var audioBytes: Int64 { (frameOffsets.first).map { audioEnd - $0 } ?? 0 }
    var frameCount: Int { frameOffsets.count }

    /// Samples, die LAME-kundige Decoder am Anfang überspringen (Encoder-Verzögerung + 529).
    var decoderSkip: Int {
        guard let tag = infoTag, let delay = tag.encoderDelay else { return 0 }
        return delay + 529
    }
    var trailingPadding: Int { infoTag?.encoderPadding ?? 0 }

    /// Dauer wie von LAME-kundigen Decodern ausgegeben (Frames · Samples − Verzögerung − Auffüllung;
    /// die Auffüllung enthält die 529 Samples Decoder-Verzögerung bereits).
    var duration: Double {
        let delay = infoTag?.encoderDelay ?? 0
        let total = frameCount * header.samplesPerFrame - (infoTag?.encoderDelay == nil ? 0 : delay + trailingPadding)
        return Double(max(total, 0)) / Double(header.sampleRate)
    }

    /// Mittlere Bitrate der Audioframes in kbit/s.
    var averageKbps: Double {
        let secs = Double(frameCount * header.samplesPerFrame) / Double(header.sampleRate)
        return secs > 0 ? Double(audioBytes) * 8 / secs / 1000 : 0
    }
}

enum MP3StreamError: Error, Equatable {
    case noFrames
    case unsupported(String)
}

enum MP3Stream {
    // MARK: - Analyse

    /// Untersucht eine MP3-Datei (über eine eingeblendete, nicht vollständig geladene Kopie).
    static func scan(url: URL) throws -> MP3StreamInfo {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        return try data.withUnsafeBytes { raw -> MP3StreamInfo in
            let b = raw.bindMemory(to: UInt8.self)
            return try scan(bytes: b)
        }
    }

    static func scan(bytes b: UnsafeBufferPointer<UInt8>) throws -> MP3StreamInfo {
        let count = b.count
        var pos = 0
        // ID3v2 (auch mehrere hintereinander)
        while pos + 10 <= count, b[pos] == 0x49, b[pos + 1] == 0x44, b[pos + 2] == 0x33 {
            let size = (Int(b[pos + 6] & 0x7F) << 21) | (Int(b[pos + 7] & 0x7F) << 14) | (Int(b[pos + 8] & 0x7F) << 7) | Int(b[pos + 9] & 0x7F)
            let footer = (b[pos + 5] & 0x10) != 0 ? 10 : 0
            pos += 10 + size + footer
        }
        let id3v2Size = Int64(min(pos, count))
        let end = audioEnd(b)
        guard pos < end else { throw MP3StreamError.noFrames }

        func header(at p: Int) -> MP3FrameHeader? {
            guard p >= 0, p + 4 <= end else { return nil }
            return MP3FrameHeader.parse(b[p], b[p + 1], b[p + 2], b[p + 3])
        }
        /// Gültiger Frame, dem ein passender Frame folgt (oder das Ende).
        func confirmed(at p: Int) -> MP3FrameHeader? {
            guard let h = header(at: p) else { return nil }
            let next = p + h.frameLength
            if next == end { return h }
            if next > end { return nil }
            guard let h2 = header(at: next), h2.isCompatible(with: h) else { return nil }
            return h
        }
        func resync(from start: Int, limit: Int, like ref: MP3FrameHeader?) -> (Int, MP3FrameHeader)? {
            var p = start
            let stop = min(end - 4, start + limit)
            while p <= stop {
                if b[p] == 0xFF, let h = confirmed(at: p), ref.map({ h.isCompatible(with: $0) }) ?? true { return (p, h) }
                p += 1
            }
            return nil
        }

        guard let (first, firstHeader) = resync(from: pos, limit: 1 << 20, like: nil) else { throw MP3StreamError.noFrames }
        var offsets: [Int64] = []
        offsets.reserveCapacity(max(16, (end - first) / max(firstHeader.frameLength, 1) + 16))
        var p = first
        var bitrates = Set<Int>()
        var lastEnd = first
        while p + 4 <= end {
            guard let h = header(at: p), h.isCompatible(with: firstHeader) else {
                // Störung im Datenstrom: zum nächsten passenden Frame springen
                guard let (q, _) = resync(from: p + 1, limit: 1 << 16, like: firstHeader) else { break }
                p = q
                continue
            }
            let len = h.frameLength
            if p + len > end { break }   // unvollständiger letzter Frame
            offsets.append(Int64(p))
            bitrates.insert(h.bitrateIndex)
            p += len
            lastEnd = p
        }
        guard !offsets.isEmpty else { throw MP3StreamError.noFrames }

        // Xing/Info/VBRI im ersten Frame?
        var tag: MP3InfoTag?
        let f0 = Int(offsets[0])
        if let h0 = header(at: f0), let t = parseInfoTag(b, frameStart: f0, header: h0) {
            tag = t
            offsets.removeFirst()
            bitrates = []
            for o in offsets {
                if let h = header(at: Int(o)) { bitrates.insert(h.bitrateIndex) }
            }
        }
        guard let firstAudio = offsets.first, let h = header(at: Int(firstAudio)) else { throw MP3StreamError.noFrames }
        return MP3StreamInfo(frameOffsets: offsets, audioEnd: Int64(lastEnd), header: h, isCBR: bitrates.count <= 1,
                             infoTag: tag, id3v2Size: id3v2Size)
    }

    /// Ende der Audiodaten ohne ID3v1, Lyrics3v2 und APEv2 am Dateiende.
    static func audioEnd(_ b: UnsafeBufferPointer<UInt8>) -> Int {
        var end = b.count
        func matches(_ s: String, at p: Int) -> Bool {
            let a = Array(s.utf8)
            guard p >= 0, p + a.count <= b.count else { return false }
            for i in 0..<a.count where b[p + i] != a[i] { return false }
            return true
        }
        if matches("TAG", at: end - 128) { end -= 128 }
        // Lyrics3 v2: „LYRICS200“ mit 6-stelliger Größe davor
        if matches("LYRICS200", at: end - 9), end >= 15 {
            let digits = (0..<6).map { b[end - 15 + $0] }
            if let size = Int(String(decoding: digits, as: UTF8.self)), size > 0, end - 15 - size >= 0 { end -= 15 + size }
        }
        // APEv2-Fußzeile
        if matches("APETAGEX", at: end - 32) {
            let base = end - 32
            let size = Int(b[base + 12]) | Int(b[base + 13]) << 8 | Int(b[base + 14]) << 16 | Int(b[base + 15]) << 24
            let flags = Int(b[base + 20]) | Int(b[base + 21]) << 8 | Int(b[base + 22]) << 16 | Int(b[base + 23]) << 24
            let hasHeader = (flags & (1 << 31)) != 0
            let total = size + (hasHeader ? 32 : 0)
            if total > 0, end - total >= 0 { end -= total }
        }
        return end
    }

    /// Liest einen Xing/Info- oder VBRI-Kopf im Frame bei `frameStart`.
    static func parseInfoTag(_ b: UnsafeBufferPointer<UInt8>, frameStart: Int, header h: MP3FrameHeader) -> MP3InfoTag? {
        let frameEnd = min(b.count, frameStart + h.frameLength)
        func be32(_ p: Int) -> Int? {
            guard p + 4 <= frameEnd else { return nil }
            return Int(b[p]) << 24 | Int(b[p + 1]) << 16 | Int(b[p + 2]) << 8 | Int(b[p + 3])
        }
        func isTag(_ s: String, at p: Int) -> Bool {
            let a = Array(s.utf8)
            guard p + 4 <= frameEnd else { return false }
            return b[p] == a[0] && b[p + 1] == a[1] && b[p + 2] == a[2] && b[p + 3] == a[3]
        }
        // Übliche Lage: nach Kopf und Seiteninformation (mit CRC zwei Bytes später)
        let candidates = [frameStart + 4 + h.sideInfoSize, frameStart + 6 + h.sideInfoSize, frameStart + 2 + h.sideInfoSize]
        for x in candidates where isTag("Xing", at: x) || isTag("Info", at: x) {
            var tag = MP3InfoTag(isInfo: isTag("Info", at: x))
            guard let flags = be32(x + 4) else { return tag }
            var p = x + 8
            if flags & 1 != 0 { tag.frames = be32(p); p += 4 }
            if flags & 2 != 0 { tag.bytes = be32(p); p += 4 }
            if flags & 4 != 0 { p += 100 }
            if flags & 8 != 0 { p += 4 }
            // LAME-Erweiterung (36 Bytes): Kennung, …, Verzögerung/Auffüllung an Position 21
            if p + 24 <= frameEnd {
                let idBytes = (0..<9).map { b[p + $0] }
                let id = String(decoding: idBytes.prefix { $0 != 0 }, as: UTF8.self)
                if id.hasPrefix("LAME") || id.hasPrefix("Lavf") || id.hasPrefix("Lavc") || id.hasPrefix("L3.99") || id.hasPrefix("GOGO") {
                    tag.encoder = id.trimmingCharacters(in: .whitespaces)
                    let d0 = Int(b[p + 21]), d1 = Int(b[p + 22]), d2 = Int(b[p + 23])
                    let delay = (d0 << 4) | (d1 >> 4)
                    let padding = ((d1 & 0x0F) << 8) | d2
                    if delay <= 3000 { tag.encoderDelay = delay }
                    if padding <= 3000 { tag.encoderPadding = padding }
                }
            }
            return tag
        }
        // Fraunhofer VBRI: immer 32 Bytes nach dem Kopf
        let v = frameStart + 4 + 32
        if isTag("VBRI", at: v) {
            var tag = MP3InfoTag(isInfo: false)
            tag.bytes = be32(v + 10)
            tag.frames = be32(v + 14)
            return tag
        }
        return nil
    }

    // MARK: - Schreiben

    /// CRC-16/ARC (Polynom 0x8005, reflektiert) wie in LAME (VbrTag.c).
    static let crcTable: [UInt16] = (0..<256).map { i -> UInt16 in
        var c = UInt16(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (c >> 1) ^ 0xA001 : c >> 1 }
        return c
    }

    @inline(__always)
    static func crc16(_ p: UnsafePointer<UInt8>, count: Int, crc start: UInt16) -> UInt16 {
        var crc = start
        for i in 0..<count {
            crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt16(p[i])) & 0xFF)]
        }
        return crc
    }

    /// Baut einen Info- (CBR) bzw. Xing-Frame (VBR) mit Frameanzahl, Bytes, TOC und – falls
    /// `lame` gesetzt – LAME-Erweiterung mit Verzögerung/Auffüllung, Musiklänge und Prüfsummen.
    static func makeInfoFrame(template h: MP3FrameHeader, frames: Int, totalBytes: Int, toc: [UInt8], cbr: Bool,
                              lame: (delay: Int, padding: Int, musicCRC: UInt16)?) -> [UInt8] {
        let xingOffset = 4 + h.sideInfoSize
        let needed = xingOffset + 120 + 36
        // Gleiche Bitrate wie der Datenstrom (CBR), sonst die kleinste, in die alles passt
        let table = h.version == .mpeg1 ? MP3FrameHeader.bitratesV1 : MP3FrameHeader.bitratesV2
        var idx = h.bitrateIndex
        if MP3FrameHeader.frameLength(version: h.version, kbps: table[idx], sampleRate: h.sampleRate, padding: false) < needed {
            idx = (1...14).first {
                MP3FrameHeader.frameLength(version: h.version, kbps: table[$0], sampleRate: h.sampleRate, padding: false) >= needed
            } ?? 14
        }
        let length = MP3FrameHeader.frameLength(version: h.version, kbps: table[idx], sampleRate: h.sampleRate, padding: false)
        var f = [UInt8](repeating: 0, count: length)
        let head = h.bytes(bitrateIndex: idx)
        for i in 0..<4 { f[i] = head[i] }
        var p = xingOffset
        func put(_ bytes: [UInt8]) { for x in bytes { if p < f.count { f[p] = x }; p += 1 } }
        put(Array((cbr ? "Info" : "Xing").utf8))
        put(ByteWriter.be32(0x0F))                 // Frames, Bytes, TOC, Qualität
        put(ByteWriter.be32(frames))
        put(ByteWriter.be32(totalBytes + length))
        var t = toc
        if t.count != 100 { t = (0..<100).map { UInt8($0 * 256 / 100) } }
        put(t)
        put(ByteWriter.be32(0))                    // Qualität (unbekannt)
        guard let lame else { return f }
        put(Array("LAME3.100".utf8))
        put([cbr ? 0x01 : 0x00])                   // Revision 0, Methode CBR bzw. unbekannt
        put([0])                                   // Tiefpass unbekannt
        put([0, 0, 0, 0])                          // Spitzenpegel
        put([0, 0, 0, 0])                          // Replay Gain (Titel, Album)
        put([0])                                   // Flags, ATH
        put([UInt8(min(h.bitrateKbps, 255))])
        let d = max(0, min(lame.delay, 4095)), pad = max(0, min(lame.padding, 4095))
        put([UInt8(d >> 4), UInt8(((d & 0x0F) << 4) | (pad >> 8)), UInt8(pad & 0xFF)])
        put([0])                                   // Sonstiges
        put([0])                                   // MP3Gain
        put([0, 0])                                // Voreinstellung
        put(ByteWriter.be32(totalBytes + length))  // Musiklänge inkl. Infoframe
        put(ByteWriter.be16(Int(lame.musicCRC)))
        let crc = f.withUnsafeBufferPointer { crc16($0.baseAddress!, count: p, crc: 0) }
        put(ByteWriter.be16(Int(crc)))
        return f
    }

    /// TOC (100 Einträge) für Frames ab `offsets` (relativ zum Dateianfang der neuen Datei ohne Infoframe).
    static func toc(frameStarts: [Int64], totalBytes: Int64, infoLength: Int64) -> [UInt8] {
        guard !frameStarts.isEmpty, totalBytes > 0 else { return [UInt8](repeating: 0, count: 100) }
        let all = Double(totalBytes + infoLength)
        return (0..<100).map { i in
            let frameIdx = min(frameStarts.count - 1, Int(Double(i) / 100 * Double(frameStarts.count)))
            let pos = Double(frameStarts[frameIdx] + infoLength)
            return UInt8(min(255, Int(pos / all * 256)))
        }
    }

    // MARK: - Schneiden

    struct CutResult {
        var frames: Int
        var firstFrame: Int
        var preroll: Int
        var bytes: Int64
    }

    /// Schneidet `[start, end)` (Sekunden) an Frame-Grenzen aus `source` nach `dest` (ohne Tags).
    /// `progress` 0…1; `check` wird je Block aufgerufen (Abbruch durch Werfen).
    static func cut(source: URL, info: MP3StreamInfo, start: Double, end: Double?, to dest: URL,
                    progress: (Double) -> Void, check: () async throws -> Void) async throws -> CutResult {
        let h = info.header
        let spf = Double(h.samplesPerFrame)
        let sr = Double(h.sampleRate)
        let n = info.frameCount
        guard n > 0 else { throw MP3StreamError.noFrames }
        let skip = Double(info.decoderSkip)
        // Positionen in Samples der Decoder-Ausgabe der Quelle (inkl. übersprungener Verzögerung)
        let startPos = max(0, start) * sr + skip
        var first = Int((startPos / spf).rounded(.down))
        first = min(max(first, 0), n - 1)
        // Ende des Inhalts in Decoder-Ausgabe-Samples (LAME: Auffüllung zählt ab Ende der um 529 verschobenen Ausgabe)
        let contentEnd = Double(n) * spf - (info.infoTag?.encoderDelay == nil ? 0 : Double(info.trailingPadding) - 529)
        let endPos = min(end.map { $0 * sr + skip } ?? contentEnd, contentEnd)
        var last = Int((endPos / spf).rounded(.up))
        last = min(max(last, first + 1), n)
        // Ein Frame Vorlauf: der erste Frame braucht oft Daten aus dem Bit-Reservoir des vorigen.
        let preroll = first > 0 ? 1 : 0
        let copyFrom = first - preroll
        let startByte = info.frameOffsets[copyFrom]
        let endByte = last < n ? info.frameOffsets[last] : info.audioEnd
        let copyBytes = endByte - startByte
        let frames = last - copyFrom

        // LAME-Angaben für samplegenaue Wiedergabe: Vorlauf und Anfang des ersten Frames überspringen,
        // am Ende die überzähligen Samples als Auffüllung kennzeichnen.
        let offsetInFirst = max(0, Int((startPos - Double(first) * spf).rounded()))
        let delay = preroll * h.samplesPerFrame + offsetInFirst - 529
        let padding = max(0, Int((Double(last) * spf - endPos).rounded())) + 529
        let lame: (Int, Int)? = delay >= 0 && delay <= 4095 && padding <= 4095 ? (delay, padding) : nil

        let data = try Data(contentsOf: source, options: .alwaysMapped)
        let out = try BinaryFile(creating: dest)
        do {
            // Platzhalter für den Infoframe, dann die Frames blockweise kopieren (Musik-CRC nebenbei)
            let starts = (copyFrom..<last).map { info.frameOffsets[$0] - startByte }
            let placeholderTOC = toc(frameStarts: starts, totalBytes: copyBytes, infoLength: 0)
            let draft = makeInfoFrame(template: h, frames: frames, totalBytes: Int(copyBytes), toc: placeholderTOC, cbr: info.isCBR,
                                      lame: lame.map { ($0.0, $0.1, 0) })
            try out.write(draft)
            var crc: UInt16 = 0
            let chunk = 1 << 20
            var done: Int64 = 0
            var buffer = [UInt8](repeating: 0, count: chunk)
            while done < copyBytes {
                try await check()
                let len = Int(min(Int64(chunk), copyBytes - done))
                let from = Int(startByte + done)
                try buffer.withUnsafeMutableBufferPointer { buf in
                    guard let base = buf.baseAddress else { return }
                    data.copyBytes(to: base, from: from..<(from + len))
                    crc = crc16(base, count: len, crc: crc)
                    try out.write(UnsafeRawPointer(base), count: len)
                }
                done += Int64(len)
                progress(Double(done) / Double(max(copyBytes, 1)))
            }
            let tocFinal = toc(frameStarts: starts, totalBytes: copyBytes, infoLength: Int64(draft.count))
            let frame = makeInfoFrame(template: h, frames: frames, totalBytes: Int(copyBytes), toc: tocFinal, cbr: info.isCBR,
                                      lame: lame.map { ($0.0, $0.1, crc) })
            try out.seek(to: 0)
            try out.write(frame)
            try out.close()
        } catch {
            out.abandon()
            throw error
        }
        return CutResult(frames: frames, firstFrame: first, preroll: preroll, bytes: copyBytes)
    }
}
