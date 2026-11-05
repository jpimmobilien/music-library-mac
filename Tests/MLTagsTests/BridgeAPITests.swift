import Foundation
import MLCore
import TagBridge
import XCTest
@testable import MLTags

/// Tests der C-Schnittstelle (Fehlercodes, Speicher, Bilder-Operationen, Eigenschaften).
final class BridgeAPITests: TagTestCase {
    private func open(_ url: URL, flags: UInt32 = 0) throws -> OpaquePointer {
        var handle: OpaquePointer?
        let status = url.path.withCString { tb_open($0, flags, &handle) }
        XCTAssertEqual(status, TB_OK, "open \(url.lastPathComponent)")
        return try XCTUnwrap(handle)
    }

    func testVersionAndStatusMessages() {
        XCTAssertEqual(String(cString: tb_taglib_version()), "2.3.2")
        XCTAssertEqual(String(cString: tb_status_message(TB_ERROR_FILE_NOT_FOUND)), "file not found")
        XCTAssertFalse(String(cString: tb_status_message(TBStatus(rawValue: 999))).isEmpty)
    }

    func testOpenErrors() throws {
        var handle: OpaquePointer?
        XCTAssertEqual(tb_open(nil, 0, &handle), TB_ERROR_INVALID_ARGUMENT)
        XCTAssertEqual(tb_open("", 0, &handle), TB_ERROR_INVALID_ARGUMENT)
        XCTAssertEqual(tempDir.appendingPathComponent("nope.mp3").path.withCString { tb_open($0, 0, &handle) },
                       TB_ERROR_FILE_NOT_FOUND)
        XCTAssertNil(handle)
        XCTAssertEqual(tempDir.path.withCString { tb_open($0, 0, &handle) }, TB_ERROR_OPEN_FAILED)
        let text = tempDir.appendingPathComponent("readme.txt")
        try Data("plain text".utf8).write(to: text)
        XCTAssertEqual(text.path.withCString { tb_open($0, 0, &handle) }, TB_ERROR_UNSUPPORTED_FORMAT)
        // FLAC magic but broken body
        let broken = tempDir.appendingPathComponent("broken.flac")
        try (Data("fLaC".utf8) + Data(repeating: 0xEE, count: 64)).write(to: broken)
        XCTAssertEqual(broken.path.withCString { tb_open($0, 0, &handle) }, TB_ERROR_INVALID_FILE)
        tb_close(nil)  // must be harmless
    }

    func testInformationFunctions() throws {
        let h = try open(Fixtures.url("id3v23.mp3"), flags: UInt32(TB_OPEN_READ_ONLY))
        defer { tb_close(h) }
        XCTAssertEqual(tb_file_type(h), TB_FILE_MPEG)
        XCTAssertEqual(String(cString: tb_file_format_name(h)), "MP3")
        XCTAssertEqual(tb_id3v2_version(h), 3)
        XCTAssertEqual(tb_tag_types(h) & UInt32(TB_TAG_ID3V2), UInt32(TB_TAG_ID3V2))
        XCTAssertEqual(tb_tag_types(h) & UInt32(TB_TAG_ID3V1), UInt32(TB_TAG_ID3V1))
        XCTAssertEqual(String(cString: tb_tag_format_description(h)), "ID3v2.3, ID3v1")
        XCTAssertEqual(tb_is_writable(h), 1)
        XCTAssertEqual(tb_handle_is_read_only(h), 1)
        XCTAssertEqual(tb_supports_pictures(h), 1)
        XCTAssertEqual(tb_field_supported(h, TB_FIELD_WORK), 1)
        var props = TBAudioProperties()
        XCTAssertEqual(tb_audio_properties(h, &props), TB_OK)
        XCTAssertEqual(props.sampleRate, 8000)
        XCTAssertGreaterThan(props.durationMs, 1000)
    }

    func testFieldErrorsAndMessages() throws {
        let url = try copyFixture("wma.wma")
        let h = try open(url)
        defer { tb_close(h) }
        XCTAssertEqual(tb_field_supported(h, TB_FIELD_WORK), 0)
        let value = strdup("x")
        defer { free(value) }
        var values: [UnsafePointer<CChar>?] = [UnsafePointer(value)]
        XCTAssertEqual(tb_set_strings(h, TB_FIELD_WORK, &values, 1), TB_ERROR_UNSUPPORTED_FIELD)
        XCTAssertFalse(String(cString: tb_last_error(h)).isEmpty)
        XCTAssertEqual(tb_set_strings(h, TB_FIELD_DATE, &values, 1), TB_ERROR_INVALID_ARGUMENT)
        XCTAssertEqual(tb_set_strings(h, TB_FIELD_YEAR, &values, 1), TB_ERROR_INVALID_ARGUMENT)
        XCTAssertEqual(tb_set_int(h, TB_FIELD_TITLE, 1, 1), TB_ERROR_INVALID_ARGUMENT)
        XCTAssertEqual(tb_set_int(h, TB_FIELD_RATING, 150, 1), TB_ERROR_INVALID_ARGUMENT)
        XCTAssertEqual(tb_set_int(h, TB_FIELD_BPM, -1, 1), TB_ERROR_INVALID_ARGUMENT)
        XCTAssertEqual(tb_set_strings(h, TB_FIELD_TITLE, nil, 1), TB_ERROR_INVALID_ARGUMENT)
        var list: UnsafeMutablePointer<TBStringList>?
        XCTAssertEqual(tb_get_strings(h, TB_FIELD_YEAR, &list), TB_ERROR_INVALID_ARGUMENT)
        XCTAssertNil(list)
        // a successful call clears the message
        XCTAssertEqual(tb_set_strings(h, TB_FIELD_TITLE, &values, 1), TB_OK)
        XCTAssertEqual(String(cString: tb_last_error(h)), "")
    }

    func testSaveOnReadOnlyHandleFails() throws {
        let url = try copyFixture("flac.flac")
        let before = try bytes(url)
        let h = try open(url, flags: UInt32(TB_OPEN_READ_ONLY))
        defer { tb_close(h) }
        XCTAssertEqual(tb_set_int(h, TB_FIELD_BPM, 100, 1), TB_OK)
        XCTAssertEqual(tb_save(h), TB_ERROR_READ_ONLY)
        XCTAssertTrue(String(cString: tb_last_error(h)).contains("read-only"))
        XCTAssertEqual(try bytes(url), before)
    }

    func testPictureOperations() throws {
        for name in ["flac.flac", "id3v24.mp3", "vorbis.ogg", "aac.m4a", "wma.wma"] {
            let url = try copyFixture(name)
            let png = Fixtures.png
            let jpg = Fixtures.jpg
            func picture(_ data: Data, _ type: Int32, _ mime: String, _ description: String,
                         _ body: (UnsafePointer<TBPicture>) -> TBStatus) -> TBStatus {
                data.withUnsafeBytes { raw in
                    mime.withCString { m in
                        description.withCString { d in
                            var p = TBPicture(type: type, mimeType: m, description: d,
                                              data: raw.bindMemory(to: UInt8.self).baseAddress, size: raw.count,
                                              width: 16, height: 16, colorDepth: 24, numColors: 0)
                            return body(&p)
                        }
                    }
                }
            }
            var h = try open(url)
            XCTAssertEqual(tb_set_pictures(h, nil, 0), TB_OK, name)
            XCTAssertEqual(picture(png, 3, "image/png", "eins") { tb_add_picture(h, $0) }, TB_OK, name)
            XCTAssertEqual(picture(jpg, 4, "image/jpeg", "zwei") { tb_add_picture(h, $0) }, TB_OK, name)
            XCTAssertEqual(picture(png, 8, "image/png", "drei") { tb_add_picture(h, $0) }, TB_OK, name)
            XCTAssertEqual(picture(jpg, 18, "image/jpeg", "ersetzt") { tb_replace_picture(h, 0, $0) }, TB_OK, name)
            XCTAssertEqual(tb_remove_picture(h, 1), TB_OK, name)
            XCTAssertEqual(tb_remove_picture(h, 7), TB_ERROR_INVALID_ARGUMENT, name)
            XCTAssertEqual(picture(png, 3, "", "") { tb_replace_picture(h, 9, $0) }, TB_ERROR_INVALID_ARGUMENT, name)
            XCTAssertEqual(tb_save(h), TB_OK, name)
            tb_close(h)

            h = try open(url, flags: UInt32(TB_OPEN_READ_ONLY))
            var list: UnsafeMutablePointer<TBPictureList>?
            XCTAssertEqual(tb_get_pictures(h, &list), TB_OK)
            let l = try XCTUnwrap(list)
            XCTAssertEqual(l.pointee.count, 2, name)
            let items = (0..<l.pointee.count).map { l.pointee.items[$0] }
            let datas = items.map { Data(bytes: $0.data!, count: $0.size) }
            if name == "wma.wma" {
                XCTAssertEqual(Set(datas), [jpg, png], name)
            } else {
                XCTAssertEqual(datas, [jpg, png], name)
                if name != "aac.m4a" {
                    XCTAssertEqual(items.map { $0.type }, [18, 8], name)
                    XCTAssertEqual(items.map { String(cString: $0.description) }, ["ersetzt", "drei"], name)
                }
            }
            if name == "flac.flac" {
                XCTAssertEqual(items.map { $0.width }, [16, 16])
                XCTAssertEqual(items.map { $0.colorDepth }, [24, 24])
            }
            tb_picture_list_free(list)
            tb_close(h)
        }
    }

    func testGenericProperties() throws {
        let url = try copyFixture("flac.flac")
        var h = try open(url)
        let a = strdup("eins"), b = strdup("zwei ✓")
        defer { free(a); free(b) }
        var values: [UnsafePointer<CChar>?] = [UnsafePointer(a), UnsafePointer(b)]
        XCTAssertEqual(tb_set_property(h, "MOOD", &values, 2), TB_OK)
        XCTAssertEqual(tb_save(h), TB_OK)
        tb_close(h)

        h = try open(url, flags: UInt32(TB_OPEN_READ_ONLY))
        defer { tb_close(h) }
        var list: UnsafeMutablePointer<TBStringList>?
        XCTAssertEqual(tb_get_property(h, "mood", &list), TB_OK)
        let l = try XCTUnwrap(list)
        XCTAssertEqual((0..<l.pointee.count).map { String(cString: l.pointee.items[$0]!) }, ["eins", "zwei ✓"])
        tb_string_list_free(list)
        list = nil
        XCTAssertEqual(tb_get_property_keys(h, &list), TB_OK)
        let keys = (0..<list!.pointee.count).map { String(cString: list!.pointee.items[$0]!) }
        XCTAssertTrue(keys.contains("MOOD"))
        XCTAssertTrue(keys.contains("MLTEST_CUSTOM"))
        tb_string_list_free(list)
        tb_string_list_free(nil)
        tb_picture_list_free(nil)
    }

    func testManyOpenReadCloseCycles() throws {
        // exercises allocation/free paths; would crash or leak file descriptors if handles were not released
        for _ in 0..<300 {
            for name in ["id3v24.mp3", "aac.m4a", "flac.flac"] {
                let file = try BridgeFile(path: Fixtures.url(name).path, readOnly: true)
                _ = try file.strings(TB_FIELD_ARTISTS)
                _ = try file.pictures()
            }
        }
    }
}
