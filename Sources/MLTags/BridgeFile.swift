import Foundation
import MLCore
import TagBridge

/// Swift-Hülle um ein `TBFile`-Handle der C-Schnittstelle (intern).
///
/// Das Handle wird in `deinit` geschlossen; alle von der Bridge gelieferten Speicherblöcke
/// werden sofort wieder freigegeben.
final class BridgeFile {
    private let handle: OpaquePointer
    let path: String

    init(path: String, readOnly: Bool, readAudioProperties: Bool = true) throws {
        self.path = path
        var flags: UInt32 = 0
        if readOnly { flags |= UInt32(TB_OPEN_READ_ONLY) }
        if !readAudioProperties { flags |= UInt32(TB_OPEN_NO_AUDIO_PROPERTIES) }
        var out: OpaquePointer?
        let status = path.withCString { tb_open($0, flags, &out) }
        guard status == TB_OK, let h = out else {
            throw BridgeFile.error(for: status, path: path, message: String(cString: tb_status_message(status)))
        }
        handle = h
    }

    deinit {
        tb_close(handle)
    }

    static func error(for status: TBStatus, path: String, message: String) -> TagError {
        switch status {
        case TB_ERROR_FILE_NOT_FOUND: return .fileNotFound(path: path)
        case TB_ERROR_OPEN_FAILED: return .cannotOpen(path: path)
        case TB_ERROR_UNSUPPORTED_FORMAT: return .unsupportedFormat(path: path)
        case TB_ERROR_INVALID_FILE: return .invalidFile(path: path)
        case TB_ERROR_READ_ONLY: return .formatNotWritable(path: path, reason: message)
        default: return .writeFailed(path: path, reason: message)
        }
    }

    private func check(_ status: TBStatus) throws {
        guard status == TB_OK else {
            let message = String(cString: tb_last_error(handle))
            throw BridgeFile.error(for: status, path: path,
                                   message: message.isEmpty ? String(cString: tb_status_message(status)) : message)
        }
    }

    // MARK: - Information

    var fileType: TBFileType { tb_file_type(handle) }
    var formatName: String { String(cString: tb_file_format_name(handle)) }
    var tagDescription: String { String(cString: tb_tag_format_description(handle)) }
    var tagTypes: UInt32 { tb_tag_types(handle) }
    var id3v2Version: Int { Int(tb_id3v2_version(handle)) }
    var isFormatWritable: Bool { tb_is_writable(handle) != 0 }
    var writableReason: String { String(cString: tb_writable_reason(handle)) }
    var handleIsReadOnly: Bool { tb_handle_is_read_only(handle) != 0 }
    var supportsPictures: Bool { tb_supports_pictures(handle) != 0 }

    func supports(_ field: TBField) -> Bool { tb_field_supported(handle, field) != 0 }

    func audioProperties() throws -> AudioProperties {
        var p = TBAudioProperties()
        try check(tb_audio_properties(handle, &p))
        let codec = withUnsafeBytes(of: p.codec) { raw -> String in
            let bytes = raw.bindMemory(to: UInt8.self)
            let end = bytes.firstIndex(of: 0) ?? bytes.count
            return String(decoding: bytes[0..<end], as: UTF8.self)
        }
        return AudioProperties(durationMs: p.durationMs, bitrate: Int(p.bitrateKbps), sampleRate: Int(p.sampleRate),
                               channels: Int(p.channels), bitsPerSample: Int(p.bitsPerSample), codec: codec)
    }

    /// Prüfsumme nur der Audiodaten (ohne Tags), `nil` wenn das Format dafür nicht bekannt ist.
    func audioPayloadChecksum() -> String? {
        var buffer = [CChar](repeating: 0, count: 64)
        let status = tb_audio_payload_checksum(handle, &buffer, buffer.count)
        guard status == TB_OK else { return nil }
        return String(cString: buffer)
    }

    // MARK: - Fields

    func strings(_ field: TBField) throws -> [String] {
        var list: UnsafeMutablePointer<TBStringList>?
        try check(tb_get_strings(handle, field, &list))
        defer { tb_string_list_free(list) }
        return BridgeFile.convert(list)
    }

    func setStrings(_ field: TBField, _ values: [String]) throws {
        try BridgeFile.withCStrings(values) { pointers, count in
            try check(tb_set_strings(handle, field, pointers, count))
        }
    }

    func int(_ field: TBField) throws -> Int? {
        var value: Int64 = 0
        var has: Int32 = 0
        try check(tb_get_int(handle, field, &value, &has))
        return has != 0 ? Int(value) : nil
    }

    func setInt(_ field: TBField, _ value: Int?) throws {
        try check(tb_set_int(handle, field, Int64(value ?? 0), value == nil ? 0 : 1))
    }

    // MARK: - Pictures

    func pictures() throws -> [EmbeddedPicture] {
        var list: UnsafeMutablePointer<TBPictureList>?
        try check(tb_get_pictures(handle, &list))
        defer { tb_picture_list_free(list) }
        guard let l = list, l.pointee.count > 0, let items = l.pointee.items else { return [] }
        var result: [EmbeddedPicture] = []
        result.reserveCapacity(l.pointee.count)
        for i in 0..<l.pointee.count {
            let p = items[i]
            let data = p.size > 0 && p.data != nil ? Data(bytes: p.data, count: p.size) : Data()
            result.append(EmbeddedPicture(
                kind: PictureKind(rawValue: Int(p.type)) ?? .other,
                mimeType: p.mimeType.map { String(cString: $0) } ?? "",
                description: p.description.map { String(cString: $0) } ?? "",
                data: data))
        }
        return result
    }

    func setPictures(_ pictures: [EmbeddedPicture]) throws {
        // Copy everything into C memory that stays valid for the duration of the call.
        var allocations: [UnsafeMutableRawPointer] = []
        defer { allocations.forEach { free($0) } }
        func cString(_ s: String) -> UnsafePointer<CChar> {
            let p = strdup(s)!
            allocations.append(UnsafeMutableRawPointer(p))
            return UnsafePointer(p)
        }
        var items: [TBPicture] = []
        for picture in pictures {
            let raw = malloc(max(picture.data.count, 1))!
            allocations.append(raw)
            picture.data.copyBytes(to: raw.assumingMemoryBound(to: UInt8.self), count: picture.data.count)
            let probe = ImageProbe.details(data: picture.data)
            items.append(TBPicture(
                type: Int32(picture.kind.rawValue),
                mimeType: cString(picture.mimeType),
                description: cString(picture.description),
                data: UnsafePointer(raw.assumingMemoryBound(to: UInt8.self)),
                size: picture.data.count,
                width: Int32(clamping: probe?.width ?? 0),
                height: Int32(clamping: probe?.height ?? 0),
                colorDepth: Int32(clamping: probe?.colorDepth ?? 0),
                numColors: Int32(clamping: probe?.numColors ?? 0)))
        }
        try items.withUnsafeBufferPointer { buffer in
            try check(tb_set_pictures(handle, buffer.baseAddress, buffer.count))
        }
    }

    // MARK: - Generic properties

    func propertyKeys() throws -> [String] {
        var list: UnsafeMutablePointer<TBStringList>?
        try check(tb_get_property_keys(handle, &list))
        defer { tb_string_list_free(list) }
        return BridgeFile.convert(list)
    }

    func property(_ key: String) throws -> [String] {
        var list: UnsafeMutablePointer<TBStringList>?
        try check(key.withCString { tb_get_property(handle, $0, &list) })
        defer { tb_string_list_free(list) }
        return BridgeFile.convert(list)
    }

    func setProperty(_ key: String, _ values: [String]) throws {
        try BridgeFile.withCStrings(values) { pointers, count in
            try check(key.withCString { tb_set_property(handle, $0, pointers, count) })
        }
    }

    func unsupportedProperties() throws -> [String] {
        var list: UnsafeMutablePointer<TBStringList>?
        try check(tb_get_unsupported_properties(handle, &list))
        defer { tb_string_list_free(list) }
        return BridgeFile.convert(list)
    }

    func save() throws {
        try check(tb_save(handle))
    }

    // MARK: - Helpers

    private static func convert(_ list: UnsafeMutablePointer<TBStringList>?) -> [String] {
        guard let l = list, l.pointee.count > 0, let items = l.pointee.items else { return [] }
        return (0..<l.pointee.count).compactMap { i in items[i].map { String(cString: $0) } }
    }

    private static func withCStrings<R>(_ strings: [String],
                                        _ body: (UnsafePointer<UnsafePointer<CChar>?>?, Int) throws -> R) rethrows -> R {
        let duplicates: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
        defer { duplicates.forEach { free($0) } }
        let pointers: [UnsafePointer<CChar>?] = duplicates.map { $0.map { UnsafePointer($0) } }
        return try pointers.withUnsafeBufferPointer { buffer in
            try body(buffer.baseAddress, buffer.count)
        }
    }
}

extension TagField {
    /// Entsprechendes Feld der C-Schnittstelle.
    var bridgeField: TBField {
        switch self {
        case .title: return TB_FIELD_TITLE
        case .artists: return TB_FIELD_ARTISTS
        case .album: return TB_FIELD_ALBUM
        case .albumArtists: return TB_FIELD_ALBUM_ARTISTS
        case .composers: return TB_FIELD_COMPOSERS
        case .grouping: return TB_FIELD_GROUPING
        case .work: return TB_FIELD_WORK
        case .genres: return TB_FIELD_GENRES
        case .year: return TB_FIELD_YEAR
        case .trackNumber: return TB_FIELD_TRACK_NUMBER
        case .trackTotal: return TB_FIELD_TRACK_TOTAL
        case .discNumber: return TB_FIELD_DISC_NUMBER
        case .discTotal: return TB_FIELD_DISC_TOTAL
        case .compilation: return TB_FIELD_COMPILATION
        case .rating: return TB_FIELD_RATING
        case .bpm: return TB_FIELD_BPM
        case .comment: return TB_FIELD_COMMENT
        case .lyrics: return TB_FIELD_LYRICS
        case .titleSort: return TB_FIELD_TITLE_SORT
        case .artistSort: return TB_FIELD_ARTIST_SORT
        case .albumSort: return TB_FIELD_ALBUM_SORT
        case .albumArtistSort: return TB_FIELD_ALBUM_ARTIST_SORT
        case .composerSort: return TB_FIELD_COMPOSER_SORT
        case .copyright: return TB_FIELD_COPYRIGHT
        case .publisher: return TB_FIELD_PUBLISHER
        case .isrc: return TB_FIELD_ISRC
        case .encodedBy: return TB_FIELD_ENCODED_BY
        }
    }

    /// Mehrfachwert-Feld (Liste in `TagValues`)?
    var isList: Bool {
        switch self {
        case .artists, .albumArtists, .composers, .genres: return true
        default: return false
        }
    }

    /// Zahlen-/Wahrheitswert-Feld?
    var isNumeric: Bool {
        switch self {
        case .year, .trackNumber, .trackTotal, .discNumber, .discTotal, .compilation, .rating, .bpm: return true
        default: return false
        }
    }
}
