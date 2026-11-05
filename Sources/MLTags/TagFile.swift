import Foundation
import MLCore
import TagBridge

/// Ergebnis von `TagFile.write(url:edit:)`.
public struct TagWriteReport: Hashable, Sendable {
    /// Geschriebene Felder (in der Reihenfolge von `TagField.allCases`).
    public var writtenFields: [TagField] = []
    /// Felder, die das Tag-Format dieser Datei nicht speichern kann und die daher übersprungen wurden.
    public var skippedFields: [TagField] = []
    /// Wurden die Bilder ersetzt?
    public var picturesWritten = false
    /// Bilder sollten gesetzt werden, das Format kann aber keine Bilder speichern.
    public var picturesSkipped = false

    public init() {}
}

/// Lesen und Schreiben der Tags einer Audiodatei über TagLib (TagBridge).
///
/// `write(url:edit:)` ändert die Datei direkt. Für Dateien der Bibliothek wird es nur über den
/// `SafeTagWriter` auf einer temporären Kopie aufgerufen.
public enum TagFile {
    /// Liest Tags, Bilder und technische Angaben.
    public static func read(url: URL) throws -> TagReadResult {
        try inspect(url: url).result
    }

    /// Wendet `edit` direkt auf die Datei an (nur die Felder in `edit.fields` und ggf. die Bilder).
    ///
    /// Felder, die das Tag-Format nicht kennt (z. B. „Werk“ in WMA), werden übersprungen und im
    /// Bericht genannt. Werte werden vorher normalisiert (siehe `canonicalValues`).
    @discardableResult
    public static func write(url: URL, edit: TagEdit) throws -> TagWriteReport {
        let path = url.path
        let file = try BridgeFile(path: path, readOnly: false, readAudioProperties: false)
        guard file.isFormatWritable else {
            throw TagError.formatNotWritable(path: path, reason: file.writableReason)
        }
        guard !file.handleIsReadOnly else { throw TagError.fileReadOnly(path: path) }
        let traits = TagFormatTraits(file: file)
        let values = canonicalValues(edit.values, traits: traits)
        var report = TagWriteReport()
        for field in TagField.allCases where edit.fields.contains(field) {
            guard traits.supportedFields.contains(field) else {
                report.skippedFields.append(field)
                continue
            }
            try apply(field, from: values, to: file)
            report.writtenFields.append(field)
        }
        if case .replaceAll(let pictures) = edit.pictures {
            if traits.pictureStyle == .none {
                report.picturesSkipped = !pictures.isEmpty
            } else {
                try file.setPictures(canonicalPictures(pictures, traits: traits))
                report.picturesWritten = true
            }
        }
        try file.save()
        return report
    }

    /// Felder, die das Tag-Format dieser Datei speichern kann.
    public static func supportedFields(url: URL) throws -> Set<TagField> {
        let file = try BridgeFile(path: url.path, readOnly: true, readAudioProperties: false)
        return TagFormatTraits(file: file).supportedFields
    }

    // MARK: - Internal

    /// Liest die Datei und liefert zusätzlich die Format-Eigenschaften.
    static func inspect(url: URL) throws -> (result: TagReadResult, traits: TagFormatTraits) {
        let path = url.path
        let file = try BridgeFile(path: path, readOnly: true)
        let traits = TagFormatTraits(file: file)
        var values = TagValues()
        for field in TagField.allCases {
            try read(field, from: file, into: &values)
        }
        values.date = try file.strings(TB_FIELD_DATE).first
        values.pictures = traits.pictureStyle == .none ? [] : try file.pictures()
        let audio = try file.audioProperties()
        let writable = file.isFormatWritable && FileSystem.isUserWritable(path: path)
        let result = TagReadResult(values: values, audio: audio, fileFormat: formatName(file),
                                   tagFormat: file.tagDescription, supportsPictures: file.supportsPictures,
                                   writable: writable)
        return (result, traits)
    }

    /// Prüfsumme der Audiodaten ohne Tags (`nil` = Format ohne bekannte Struktur).
    static func audioPayloadChecksum(url: URL) throws -> String? {
        try BridgeFile(path: url.path, readOnly: true, readAudioProperties: false).audioPayloadChecksum()
    }

    private static func formatName(_ file: BridgeFile) -> String {
        file.formatName
    }

    private static func read(_ field: TagField, from file: BridgeFile, into v: inout TagValues) throws {
        let f = field.bridgeField
        if field.isNumeric {
            let n = try file.int(f)
            func positive(_ x: Int?) -> Int? { x.flatMap { $0 > 0 ? $0 : nil } }
            switch field {
            case .year: v.year = positive(n)
            case .trackNumber: v.trackNumber = positive(n)
            case .trackTotal: v.trackTotal = positive(n)
            case .discNumber: v.discNumber = positive(n)
            case .discTotal: v.discTotal = positive(n)
            case .compilation: v.compilation = (n ?? 0) != 0
            case .rating: v.rating = positive(n).map { min(100, $0) }
            case .bpm: v.bpm = positive(n)
            default: break
            }
            return
        }
        let raw = try file.strings(f)
        if field.isList {
            let list = cleanList(raw)
            switch field {
            case .artists: v.artists = list
            case .albumArtists: v.albumArtists = list
            case .composers: v.composers = list
            case .genres: v.genres = list
            default: break
            }
            return
        }
        let text = cleanText(raw.isEmpty ? nil : raw.joined(separator: "; "))
        switch field {
        case .title: v.title = text
        case .album: v.album = text
        case .grouping: v.grouping = text
        case .work: v.work = text
        case .comment: v.comment = text
        case .lyrics: v.lyrics = text
        case .titleSort: v.titleSort = text
        case .artistSort: v.artistSort = text
        case .albumSort: v.albumSort = text
        case .albumArtistSort: v.albumArtistSort = text
        case .composerSort: v.composerSort = text
        case .copyright: v.copyright = text
        case .publisher: v.publisher = text
        case .isrc: v.isrc = text
        case .encodedBy: v.encodedBy = text
        default: break
        }
    }

    private static func apply(_ field: TagField, from v: TagValues, to file: BridgeFile) throws {
        let f = field.bridgeField
        func text(_ s: String?) throws { try file.setStrings(f, s.map { [$0] } ?? []) }
        switch field {
        case .title: try text(v.title)
        case .artists: try file.setStrings(f, v.artists)
        case .album: try text(v.album)
        case .albumArtists: try file.setStrings(f, v.albumArtists)
        case .composers: try file.setStrings(f, v.composers)
        case .grouping: try text(v.grouping)
        case .work: try text(v.work)
        case .genres: try file.setStrings(f, v.genres)
        case .year: try file.setInt(f, v.year)
        case .trackNumber: try file.setInt(f, v.trackNumber)
        case .trackTotal: try file.setInt(f, v.trackTotal)
        case .discNumber: try file.setInt(f, v.discNumber)
        case .discTotal: try file.setInt(f, v.discTotal)
        case .compilation: try file.setInt(f, v.compilation ? 1 : nil)
        case .rating: try file.setInt(f, v.rating)
        case .bpm: try file.setInt(f, v.bpm)
        case .comment: try text(v.comment)
        case .lyrics: try text(v.lyrics)
        case .titleSort: try text(v.titleSort)
        case .artistSort: try text(v.artistSort)
        case .albumSort: try text(v.albumSort)
        case .albumArtistSort: try text(v.albumArtistSort)
        case .composerSort: try text(v.composerSort)
        case .copyright: try text(v.copyright)
        case .publisher: try text(v.publisher)
        case .isrc: try text(v.isrc)
        case .encodedBy: try text(v.encodedBy)
        }
    }

    // MARK: - Canonical values
    //
    // The canonical form is what a value looks like after it was written and read back:
    // NUL characters removed, empty text = nil, list entries split at ";" and trimmed,
    // numbers outside the storable range = nil, ratings rounded to what the format can store,
    // pictures reduced to what the format can store.

    static func cleanText(_ s: String?) -> String? {
        guard let s else { return nil }
        let cleaned = s.contains("\u{0}") ? s.replacingOccurrences(of: "\u{0}", with: "") : s
        return cleaned.isEmpty ? nil : cleaned
    }

    static func cleanList(_ list: [String]) -> [String] {
        list.flatMap { entry -> [String] in
            entry.replacingOccurrences(of: "\u{0}", with: "")
                .split(separator: ";", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        .filter { !$0.isEmpty }
    }

    static func canonicalRating(_ rating: Int?, step: Int) -> Int? {
        guard let r = rating, r > 0 else { return nil }
        let clamped = min(100, r)
        switch step {
        case 10: return max(1, min(10, (clamped + 5) / 10)) * 10   // ID3 POPM: half stars
        case 20: return max(1, min(5, (clamped + 10) / 20)) * 20   // WMA: full stars
        default: return clamped
        }
    }

    /// Normalisierte Werte, wie sie nach dem Schreiben in eine Datei mit `traits` gelesen werden.
    static func canonicalValues(_ v: TagValues, traits: TagFormatTraits) -> TagValues {
        func number(_ x: Int?, _ range: ClosedRange<Int>) -> Int? { x.flatMap { range.contains($0) ? $0 : nil } }
        var c = v
        c.title = cleanText(v.title)
        c.artists = cleanList(v.artists)
        c.album = cleanText(v.album)
        c.albumArtists = cleanList(v.albumArtists)
        c.composers = cleanList(v.composers)
        c.grouping = cleanText(v.grouping)
        c.work = cleanText(v.work)
        c.genres = cleanList(v.genres)
        c.year = number(v.year, 1...9999)
        c.trackNumber = number(v.trackNumber, 1...32767)
        c.trackTotal = number(v.trackTotal, 1...32767)
        c.discNumber = number(v.discNumber, 1...32767)
        c.discTotal = number(v.discTotal, 1...32767)
        c.rating = canonicalRating(v.rating, step: traits.ratingStep)
        c.bpm = number(v.bpm, 1...32767)
        c.comment = cleanText(v.comment)
        c.lyrics = cleanText(v.lyrics)
        c.titleSort = cleanText(v.titleSort)
        c.artistSort = cleanText(v.artistSort)
        c.albumSort = cleanText(v.albumSort)
        c.albumArtistSort = cleanText(v.albumArtistSort)
        c.composerSort = cleanText(v.composerSort)
        c.copyright = cleanText(v.copyright)
        c.publisher = cleanText(v.publisher)
        c.isrc = cleanText(v.isrc)
        c.encodedBy = cleanText(v.encodedBy)
        c.pictures = canonicalPictures(v.pictures, traits: traits)
        return c
    }

    /// MIME-Typ nach Dateikopf (gleiche Regeln wie die C++-Bridge).
    static func sniffMime(_ d: Data) -> String? {
        let b = [UInt8](d.prefix(16))
        func starts(_ p: [UInt8]) -> Bool { b.count >= p.count && Array(b[0..<p.count]) == p }
        if starts([0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "image/png" }
        if starts(Array("GIF87a".utf8)) || starts(Array("GIF89a".utf8)) { return "image/gif" }
        if starts(Array("BM".utf8)) { return "image/bmp" }
        if b.count >= 12, starts(Array("RIFF".utf8)), Array(b[8..<12]) == Array("WEBP".utf8) { return "image/webp" }
        if starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A]) { return "image/tiff" }
        if b.count >= 12, Array(b[4..<8]) == Array("ftyp".utf8) {
            let brand = String(decoding: b[8..<12], as: UTF8.self)
            if ["heic", "heix", "mif1", "msf1"].contains(brand) { return "image/heic" }
            if brand == "avif" { return "image/avif" }
        }
        return nil
    }

    static func normalizedMime(_ mime: String, data: Data) -> String {
        var m = mime.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if m == "image/jpg" || m == "jpg" || m == "jpeg" { m = "image/jpeg" }
        if m == "png" { m = "image/png" }
        if m.isEmpty { m = sniffMime(data) ?? "" }
        return m
    }

    static func canonicalPictures(_ pictures: [EmbeddedPicture], traits: TagFormatTraits) -> [EmbeddedPicture] {
        let valid = pictures.filter { !$0.data.isEmpty }.map { p -> EmbeddedPicture in
            var p = p
            p.mimeType = normalizedMime(p.mimeType, data: p.data)
            p.description = p.description.replacingOccurrences(of: "\u{0}", with: "")
            return p
        }
        switch traits.pictureStyle {
        case .none:
            return []
        case .full:
            return valid
        case .coverList:
            // MP4 "covr": no picture types or descriptions; format from the image data.
            let mp4Formats: Set<String> = ["image/jpeg", "image/png", "image/gif", "image/bmp"]
            return valid.map { p in
                let m = sniffMime(p.data) ?? p.mimeType
                return EmbeddedPicture(kind: .frontCover, mimeType: mp4Formats.contains(m) ? m : (sniffMime(p.data) ?? ""),
                                       description: "", data: p.data)
            }
        case .onePerKind:
            // APEv2: one "Cover Art (…)" item per picture type, MIME type from the data.
            var seen = Set<PictureKind>()
            var result: [EmbeddedPicture] = []
            for p in valid where !seen.contains(p.kind) {
                seen.insert(p.kind)
                result.append(EmbeddedPicture(kind: p.kind, mimeType: sniffMime(p.data) ?? "",
                                              description: p.description, data: p.data))
            }
            return result.sorted { $0.kind.rawValue < $1.kind.rawValue }
        }
    }

    /// Erwartete Werte nach Anwenden von `edit` auf `before` (nur unterstützte Felder).
    static func expectedValues(before: TagValues, edit: TagEdit, traits: TagFormatTraits) -> TagValues {
        var expected = before
        let canonical = canonicalValues(edit.values, traits: traits)
        expected.merge(canonical, fields: edit.fields.intersection(traits.supportedFields))
        if case .replaceAll = edit.pictures, traits.pictureStyle != .none {
            expected.pictures = canonical.pictures
        }
        return expected
    }
}

/// Was das Tag-Format einer Datei speichern kann (intern).
struct TagFormatTraits: Hashable {
    enum PictureStyle: Hashable {
        /// Keine Bilder.
        case none
        /// Beliebig viele Bilder mit Art, MIME-Typ und Beschreibung (ID3v2, FLAC, Vorbis, WMA).
        case full
        /// MP4 „covr“: nur Bilddaten (alle als Vorderseite, Reihenfolge bleibt).
        case coverList
        /// APEv2: höchstens ein Bild je Art.
        case onePerKind
    }

    var fileTypeRaw: UInt32
    var supportedFields: Set<TagField>
    var pictureStyle: PictureStyle
    /// Auflösung der Bewertung: 1 (0…100 exakt), 10 (halbe Sterne, ID3 POPM), 20 (ganze Sterne, WMA).
    var ratingStep: Int
    /// Reihenfolge wiederholter Werte/Bilder ist nach dem Speichern nicht stabil (WMA/ASF in TagLib).
    var unstableValueOrder: Bool

    init(file: BridgeFile) {
        let type = file.fileType
        fileTypeRaw = type.rawValue
        supportedFields = Set(TagField.allCases.filter { file.supports($0.bridgeField) })
        if !file.supportsPictures {
            pictureStyle = .none
        } else if type == TB_FILE_MP4 {
            pictureStyle = .coverList
        } else if type == TB_FILE_APE || type == TB_FILE_WAVPACK || type == TB_FILE_MPC {
            pictureStyle = .onePerKind
        } else {
            pictureStyle = .full
        }
        unstableValueOrder = type == TB_FILE_ASF
        switch type {
        case TB_FILE_MPEG, TB_FILE_WAV, TB_FILE_AIFF, TB_FILE_DSF, TB_FILE_DSDIFF, TB_FILE_TRUEAUDIO:
            ratingStep = 10
        case TB_FILE_ASF:
            ratingStep = 20
        default:
            ratingStep = 1
        }
    }
}
