import Foundation
import AppKit
import QuickLookThumbnailing
import ABCore

/// Vorschaubilder: vom Telefon (MTP „GetThumb“, klein und schnell) bzw. für Mac-Dateien über Quick Look.
/// Nur im Arbeitsspeicher zwischengespeichert (mit Obergrenze) – keine Kopien auf der Festplatte.
@MainActor
final class ThumbnailService {
    static let shared = ThumbnailService()

    private let cache = NSCache<NSString, NSImage>()
    private let missing = NSCache<NSString, NSNumber>()
    private var inflight: [String: Task<NSImage?, Never>] = [:]

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
        if let running = inflight[key] { return await running.value }
        let task = Task<NSImage?, Never> {
            guard let data = try? await backend.thumbnail(handle: entry.handle), let image = NSImage(data: data) else { return nil }
            return image
        }
        inflight[key] = task
        let image = await task.value
        inflight[key] = nil
        if let image {
            let cost = Int(image.size.width * image.size.height * 4)
            cache.setObject(image, forKey: key as NSString, cost: max(cost, 1))
        } else if !Task.isCancelled {
            missing.setObject(1, forKey: key as NSString)
        }
        return image
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
