import Foundation
import AppKit
import QuickLookThumbnailing
import ABCore

/// Hülle, damit Bilder auch unter macOS 13 (NSImage dort nicht als Sendable markiert) über Tasks gereicht werden können.
struct ImageBox: @unchecked Sendable { let image: NSImage? }

/// Vorschaubilder: vom Telefon (MTP „GetThumb“, klein und schnell) bzw. für Mac-Dateien über Quick Look.
/// Nur im Arbeitsspeicher zwischengespeichert (mit Obergrenze) – keine Kopien auf der Festplatte.
@MainActor
final class ThumbnailService {
    static let shared = ThumbnailService()

    private let cache = NSCache<NSString, NSImage>()
    private let missing = NSCache<NSString, NSNumber>()
    private var inflight: [String: Task<ImageBox, Never>] = [:]

    init() {
        cache.countLimit = 1500
        cache.totalCostLimit = 96 * 1024 * 1024
        missing.countLimit = 5000
    }

    func cached(_ key: String) -> NSImage? { cache.object(forKey: key as NSString) }

    static func key(device: DeviceConnection, entry: DeviceEntry) -> String {
        "\(device.id)-\(entry.storageID)-\(entry.handle)-\(entry.size)"
    }

    func thumbnail(for entry: DeviceEntry, device: DeviceConnection) async -> NSImage? {
        guard entry.kind.isMedia, let backend = device.backend else { return nil }
        let key = Self.key(device: device, entry: entry)
        if let image = cache.object(forKey: key as NSString) { return image }
        if missing.object(forKey: key as NSString) != nil { return nil }
        if let running = inflight[key] { return await running.value.image }
        let task = Task<ImageBox, Never> {
            guard let data = try? await backend.thumbnail(handle: entry.handle), let image = NSImage(data: data) else { return ImageBox(image: nil) }
            return ImageBox(image: Self.removingBars(image))
        }
        inflight[key] = task
        let image = await task.value.image
        inflight[key] = nil
        if let image {
            let cost = Int(image.size.width * image.size.height * 4)
            cache.setObject(image, forKey: key as NSString, cost: max(cost, 1))
        } else if !Task.isCancelled {
            missing.setObject(1, forKey: key as NSString)
        }
        return image
    }

    /// Schneidet schwarze Balken ab, die Android in MTP-Vorschaubilder einrechnet.
    nonisolated static func removingBars(_ image: NSImage) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let w = cg.width, h = cg.height
        guard w > 4, h > 4, w * h <= 1_000_000 else { return image }
        var gray = [UInt8](repeating: 0, count: w * h)
        let drawn: Bool = gray.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        // CGContext zeichnet mit Ursprung unten links; der Speicher beginnt dennoch mit der obersten Zeile.
        guard drawn, let r = Letterbox.contentRect(gray: gray, width: w, height: h),
              let cropped = cg.cropping(to: CGRect(x: r.x, y: r.y, width: r.width, height: r.height)) else { return image }
        return NSImage(cgImage: cropped, size: NSSize(width: r.width, height: r.height))
    }

    func localThumbnail(for url: URL, size: CGFloat) async -> NSImage? {
        let key = "local-\(url.path)-\(Int(size))"
        if let image = cache.object(forKey: key as NSString) { return image }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size), scale: scale,
                                                   representationTypes: .thumbnail)
        do {
            let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            let image = rep.nsImage
            cache.setObject(image, forKey: key as NSString, cost: Int(size * size * 4 * scale))
            return image
        } catch {
            return nil
        }
    }

    func clear() {
        cache.removeAllObjects()
        missing.removeAllObjects()
    }
}
