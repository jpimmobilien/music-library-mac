import Foundation

/// Erkennt Bildformat und Abmessungen anhand der Dateiköpfe (reines Swift, ohne ImageIO).
///
/// Unterstützt JPEG, PNG, GIF, WebP (VP8, VP8L, VP8X), BMP sowie HEIC/AVIF (Größe aus dem
/// `ispe`-Kasten, sonst 0 × 0). Unbekannte Daten liefern `nil`.
public enum ImageProbe {
    /// Format („jpeg“, „png“, „gif“, „webp“, „bmp“, „heic“, „avif“) und Größe in Pixeln.
    public static func info(data: Data) -> (format: String, width: Int, height: Int)? {
        guard let d = details(data: data) else { return nil }
        return (d.format, d.width, d.height)
    }

    /// MIME-Typ zu einem Format von `info(data:)`.
    public static func mimeType(forFormat format: String) -> String {
        switch format {
        case "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        case "heic": return "image/heic"
        case "avif": return "image/avif"
        default: return "application/octet-stream"
        }
    }

    /// MIME-Typ der Bilddaten (`nil` = unbekannt).
    public static func mimeType(of data: Data) -> String? {
        info(data: data).map { mimeType(forFormat: $0.format) }
    }

    struct Details: Equatable {
        var format: String
        var width: Int
        var height: Int
        /// Bits pro Pixel (0 = unbekannt), wie für FLAC-Bildblöcke benötigt.
        var colorDepth: Int = 0
        /// Anzahl Farben bei Palettenbildern (0 = keine Palette).
        var numColors: Int = 0
    }

    static func details(data input: Data) -> Details? {
        // Work on a zero-based array slice of the header to avoid index surprises with Data slices.
        let bytes = [UInt8](input.prefix(256 * 1024))
        guard bytes.count >= 4 else { return nil }
        if bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF { return jpeg(bytes) }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return png(bytes) }
        if bytes.starts(with: Array("GIF87a".utf8)) || bytes.starts(with: Array("GIF89a".utf8)) { return gif(bytes) }
        if bytes.count >= 12, bytes.starts(with: Array("RIFF".utf8)), Array(bytes[8..<12]) == Array("WEBP".utf8) {
            return webp(bytes)
        }
        if bytes.starts(with: Array("BM".utf8)) { return bmp(bytes) }
        if bytes.count >= 12, Array(bytes[4..<8]) == Array("ftyp".utf8) {
            let brand = String(decoding: bytes[8..<12], as: UTF8.self)
            let heif: Set<String> = ["heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1"]
            if brand == "avif" || brand == "avis" { return isobmffImage(bytes, format: "avif") }
            if heif.contains(brand) { return isobmffImage(bytes, format: "heic") }
        }
        return nil
    }

    // MARK: - Formats

    private static func be16(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) << 8 | Int(b[i + 1]) }
    private static func le16(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
    private static func be32(_ b: [UInt8], _ i: Int) -> Int {
        Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3])
    }
    private static func le32(_ b: [UInt8], _ i: Int) -> Int {
        Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24
    }
    private static func le24(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 }

    private static func jpeg(_ b: [UInt8]) -> Details? {
        var i = 2
        while i + 9 < b.count {
            guard b[i] == 0xFF else { i += 1; continue }
            let marker = b[i + 1]
            if marker == 0xFF { i += 1; continue }  // fill bytes
            if marker == 0xD8 || marker == 0x01 || (0xD0...0xD7).contains(marker) { i += 2; continue }
            if marker == 0xD9 || marker == 0xDA { break }  // end of image / start of scan
            let length = be16(b, i + 2)
            guard length >= 2 else { return nil }
            // SOF0...SOF15 except DHT (C4), JPG (C8), DAC (CC)
            if (0xC0...0xCF).contains(marker), marker != 0xC4, marker != 0xC8, marker != 0xCC {
                let precision = Int(b[i + 4])
                let height = be16(b, i + 5)
                let width = be16(b, i + 7)
                let components = Int(b[i + 9])
                return Details(format: "jpeg", width: width, height: height, colorDepth: precision * components)
            }
            i += 2 + length
        }
        return Details(format: "jpeg", width: 0, height: 0)
    }

    private static func png(_ b: [UInt8]) -> Details? {
        guard b.count >= 29, Array(b[12..<16]) == Array("IHDR".utf8) else {
            return Details(format: "png", width: 0, height: 0)
        }
        let width = be32(b, 16)
        let height = be32(b, 20)
        let bitDepth = Int(b[24])
        let colorType = Int(b[25])
        let channels: Int
        switch colorType {
        case 0: channels = 1
        case 2: channels = 3
        case 3: channels = 1
        case 4: channels = 2
        case 6: channels = 4
        default: channels = 0
        }
        var details = Details(format: "png", width: width, height: height, colorDepth: bitDepth * channels)
        if colorType == 3 {
            // PLTE chunk follows IHDR (possibly after other chunks)
            var i = 8
            while i + 8 <= b.count {
                let length = be32(b, i)
                let type = String(decoding: b[(i + 4)..<(i + 8)], as: UTF8.self)
                if type == "PLTE" { details.numColors = length / 3; break }
                if type == "IDAT" || length < 0 { break }
                i += 12 + length
            }
            details.colorDepth = bitDepth
        }
        return details
    }

    private static func gif(_ b: [UInt8]) -> Details? {
        guard b.count >= 11 else { return Details(format: "gif", width: 0, height: 0) }
        let width = le16(b, 6)
        let height = le16(b, 8)
        let packed = Int(b[10])
        let hasTable = packed & 0x80 != 0
        let bits = (packed & 0x07) + 1
        return Details(format: "gif", width: width, height: height, colorDepth: bits, numColors: hasTable ? 1 << bits : 0)
    }

    private static func webp(_ b: [UInt8]) -> Details? {
        guard b.count >= 30 else { return Details(format: "webp", width: 0, height: 0) }
        let chunk = String(decoding: b[12..<16], as: UTF8.self)
        switch chunk {
        case "VP8 ":
            // frame tag (3) + start code 9D 01 2A + 14-bit width/height
            guard b[23] == 0x9D, b[24] == 0x01, b[25] == 0x2A else { break }
            return Details(format: "webp", width: le16(b, 26) & 0x3FFF, height: le16(b, 28) & 0x3FFF, colorDepth: 24)
        case "VP8L":
            guard b[20] == 0x2F else { break }
            let v = le32(b, 21)
            return Details(format: "webp", width: (v & 0x3FFF) + 1, height: ((v >> 14) & 0x3FFF) + 1, colorDepth: 32)
        case "VP8X":
            return Details(format: "webp", width: le24(b, 24) + 1, height: le24(b, 27) + 1, colorDepth: 32)
        default: break
        }
        return Details(format: "webp", width: 0, height: 0)
    }

    private static func bmp(_ b: [UInt8]) -> Details? {
        guard b.count >= 30 else { return nil }
        let headerSize = le32(b, 14)
        if headerSize == 12 {
            return Details(format: "bmp", width: le16(b, 18), height: le16(b, 20), colorDepth: le16(b, 24))
        }
        guard headerSize >= 40, b.count >= 30 else { return nil }
        var height = Int(Int32(bitPattern: UInt32(le32(b, 22))))
        if height < 0 { height = -height }  // top-down bitmap
        return Details(format: "bmp", width: le32(b, 18), height: height, colorDepth: le16(b, 28))
    }

    /// HEIF/AVIF: dimensions from the first `ispe` (image spatial extents) property.
    private static func isobmffImage(_ b: [UInt8], format: String) -> Details? {
        let ispe = Array("ispe".utf8)
        var i = 4
        while i + 16 <= b.count {
            if b[i] == ispe[0], b[i + 1] == ispe[1], b[i + 2] == ispe[2], b[i + 3] == ispe[3] {
                // box: size(4) 'ispe'(4) version/flags(4) width(4) height(4)
                let width = be32(b, i + 8)
                let height = be32(b, i + 12)
                if width > 0, height > 0 { return Details(format: format, width: width, height: height) }
            }
            i += 1
        }
        return Details(format: format, width: 0, height: 0)
    }
}
