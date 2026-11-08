import Foundation
import ImageIO
import MLTags

/// Coverbilder für Tags: JPEG und PNG bleiben unverändert, alles andere (WebP, HEIC, GIF, BMP, TIFF …)
/// wird über ImageIO in JPEG umgewandelt.
enum CoverImage {
    /// Liefert (Daten, MIME-Typ) für das Einbetten, nil bei unlesbaren Daten.
    static func embeddable(_ data: Data) -> (data: Data, mimeType: String)? {
        guard !data.isEmpty else { return nil }
        if let mime = ImageProbe.mimeType(of: data), mime == "image/jpeg" || mime == "image/png" {
            return (data, mime)
        }
        guard let jpeg = jpegData(from: data) else { return nil }
        return (jpeg, "image/jpeg")
    }

    /// Wandelt beliebige von ImageIO lesbare Bilddaten in JPEG (Qualität 0,9).
    static func jpegData(from data: Data, maxPixelSize: Int? = nil) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { return nil }
        let image: CGImage?
        if let maxPixelSize {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let image else { return nil }
        return jpegData(from: image)
    }

    static func jpegData(from image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, "public.jpeg" as CFString, 1, nil) else { return nil }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
