import Foundation
import XCTest
@testable import MLTags

final class ImageProbeTests: XCTestCase {
    private func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
    private func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16(v >> 16 & 0xFFFF) }
    private func be32(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }

    func testJPEGAndPNGFixtures() {
        let jpeg = ImageProbe.info(data: Fixtures.jpg)
        XCTAssertEqual(jpeg?.format, "jpeg")
        XCTAssertEqual(jpeg?.width, 16)
        XCTAssertEqual(jpeg?.height, 16)
        let png = ImageProbe.info(data: Fixtures.png)
        XCTAssertEqual(png?.format, "png")
        XCTAssertEqual(png?.width, 16)
        XCTAssertEqual(png?.height, 16)
        XCTAssertEqual(ImageProbe.mimeType(of: Fixtures.png), "image/png")
        XCTAssertEqual(ImageProbe.mimeType(of: Fixtures.jpg), "image/jpeg")
        XCTAssertEqual(ImageProbe.details(data: Fixtures.jpg)?.colorDepth, 24)
    }

    func testJPEGWithSegmentsBeforeSOF() {
        // SOI, APP0 (JFIF), DQT stub, SOF2 (progressive) 640x480, 3 components
        var bytes: [UInt8] = [0xFF, 0xD8]
        bytes += [0xFF, 0xE0, 0x00, 0x10] + Array("JFIF".utf8) + [0, 1, 1, 0, 0, 1, 0, 1, 0, 0]
        bytes += [0xFF, 0xDB, 0x00, 0x04, 0x00, 0x00]
        bytes += [0xFF, 0xC2, 0x00, 0x11, 0x08, 0x01, 0xE0, 0x02, 0x80, 0x03] + [UInt8](repeating: 0, count: 9)
        bytes += [0xFF, 0xD9]
        let info = ImageProbe.info(data: Data(bytes))
        XCTAssertEqual(info?.format, "jpeg")
        XCTAssertEqual(info?.width, 640)
        XCTAssertEqual(info?.height, 480)
    }

    func testGIF() {
        var bytes: [UInt8] = Array("GIF89a".utf8)
        bytes += le16(320) + le16(200)
        bytes += [0xF7, 0, 0]
        let details = ImageProbe.details(data: Data(bytes))
        XCTAssertEqual(details?.format, "gif")
        XCTAssertEqual(details?.width, 320)
        XCTAssertEqual(details?.height, 200)
        XCTAssertEqual(details?.numColors, 256)
    }

    private func riffWebP(_ chunk: String, _ payload: [UInt8]) -> Data {
        var bytes: [UInt8] = Array("RIFF".utf8)
        bytes += le32(30)
        bytes += Array("WEBP".utf8)
        bytes += Array(chunk.utf8)
        bytes += le32(10)
        bytes += payload
        return Data(bytes)
    }

    func testWebPVariants() {
        var x: [UInt8] = [0x10, 0, 0, 0]
        x += [UInt8(1999 & 0xFF), UInt8(1999 >> 8), 0]
        x += [UInt8(999 & 0xFF), UInt8(999 >> 8), 0]
        x += [0, 0]
        let vp8x = riffWebP("VP8X", x)
        XCTAssertEqual(ImageProbe.info(data: vp8x)?.width, 2000)
        XCTAssertEqual(ImageProbe.info(data: vp8x)?.height, 1000)

        let bits: Int = (300 - 1) | ((150 - 1) << 14)
        var l: [UInt8] = [0x2F]
        l += le32(bits)
        l += [UInt8](repeating: 0, count: 8)
        let vp8l = riffWebP("VP8L", l)
        XCTAssertEqual(ImageProbe.info(data: vp8l)?.format, "webp")
        XCTAssertEqual(ImageProbe.info(data: vp8l)?.width, 300)
        XCTAssertEqual(ImageProbe.info(data: vp8l)?.height, 150)

        var v: [UInt8] = [0x10, 0x02, 0x00, 0x9D, 0x01, 0x2A]
        v += le16(64)
        v += le16(48)
        v += [UInt8](repeating: 0, count: 4)
        let vp8 = riffWebP("VP8 ", v)
        XCTAssertEqual(ImageProbe.info(data: vp8)?.width, 64)
        XCTAssertEqual(ImageProbe.info(data: vp8)?.height, 48)
    }

    func testBMP() {
        var bytes: [UInt8] = Array("BM".utf8)
        bytes += le32(0) + le32(0) + le32(54) + le32(40)
        bytes += le32(33)
        bytes += le32(-22 & 0xFFFFFFFF)
        bytes += le16(1) + le16(24)
        bytes += [UInt8](repeating: 0, count: 24)
        let info = ImageProbe.info(data: Data(bytes))
        XCTAssertEqual(info?.format, "bmp")
        XCTAssertEqual(info?.width, 33)
        XCTAssertEqual(info?.height, 22)
    }

    func testHEICWithAndWithoutSize() {
        var ftyp: [UInt8] = be32(24)
        ftyp += Array("ftypheic".utf8)
        ftyp += be32(0)
        ftyp += Array("mif1heic".utf8)
        var ispe: [UInt8] = be32(20)
        ispe += Array("ispe".utf8)
        ispe += be32(0) + be32(4032) + be32(3024)
        var heic: [UInt8] = ftyp
        heic += [0, 0, 0, 8]
        heic += Array("meta".utf8)
        heic += ispe
        let info = ImageProbe.info(data: Data(heic))
        XCTAssertEqual(info?.format, "heic")
        XCTAssertEqual(info?.width, 4032)
        XCTAssertEqual(info?.height, 3024)

        let unknownSize = ImageProbe.info(data: Data(ftyp + [UInt8](repeating: 0, count: 16)))
        XCTAssertEqual(unknownSize?.format, "heic")
        XCTAssertEqual(unknownSize?.width, 0)
        XCTAssertEqual(ImageProbe.mimeType(forFormat: "heic"), "image/heic")
    }

    func testUnknownAndTruncatedData() {
        XCTAssertNil(ImageProbe.info(data: Data()))
        XCTAssertNil(ImageProbe.info(data: Data("hello world, no image".utf8)))
        XCTAssertNil(ImageProbe.info(data: Data([0x00, 0x00, 0x01, 0xBA, 0x44])))
        // truncated headers must not crash
        XCTAssertEqual(ImageProbe.info(data: Fixtures.png.prefix(12))?.format, "png")
        XCTAssertEqual(ImageProbe.info(data: Fixtures.jpg.prefix(6))?.format, "jpeg")
        XCTAssertEqual(ImageProbe.info(data: Data(Array("GIF89a".utf8)))?.format, "gif")
        for length in 0..<min(64, Fixtures.jpg.count) {
            _ = ImageProbe.info(data: Fixtures.jpg.prefix(length))
            _ = ImageProbe.info(data: Fixtures.png.prefix(length))
        }
    }

    func testProbeWorksOnDataSlices() {
        let padded = Data([1, 2, 3]) + Fixtures.png
        let slice = padded[3...]
        XCTAssertEqual(ImageProbe.info(data: slice)?.width, 16)
    }
}
