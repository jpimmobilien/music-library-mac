import Foundation
import SwiftUI
import ABCore

/// Echte Bildinhalte für die Übersicht: die neuesten Fotos und das neueste Video aus dem Kameraordner.
/// Liest nur zwei bis drei Ordnerlisten (keine Dateiinhalte) – schont das Telefon.
@MainActor
final class DeviceShowcase: ObservableObject {
    @Published private(set) var deviceID: UInt64?
    @Published private(set) var photos: [MediaItem] = []
    @Published private(set) var videos: [MediaItem] = []
    @Published private(set) var loaded = false
    private var task: Task<Void, Never>?

    func load(for device: DeviceConnection, gallery: GalleryModel) {
        // Schon vollständig durchsucht? Dann die Galerie nehmen.
        if gallery.device?.id == device.id, !gallery.items.isEmpty {
            apply(gallery.items, device: device)
            return
        }
        guard deviceID != device.id || !loaded, task == nil else { return }
        guard device.state == .connected, let backend = device.backend,
              let storage = device.storages.first(where: { !$0.isRemovable }) ?? device.storages.first else { return }
        deviceID = device.id
        task = Task { [weak self] in
            var found: [MediaItem] = []
            for path in [["DCIM", "Camera"], ["DCIM", "100ANDRO"], ["Pictures"], ["DCIM"]] {
                if let items = try? await Self.list(path: path, storage: storage.id, backend: backend), !items.isEmpty {
                    found += items
                    if found.filter({ $0.entry.kind == .photo }).count >= 8 { break }
                }
            }
            guard let self else { return }
            self.task = nil
            self.apply(found, device: device)
        }
    }

    func reset() {
        task?.cancel()
        task = nil
        deviceID = nil
        photos = []
        videos = []
        loaded = false
    }

    private func apply(_ items: [MediaItem], device: DeviceConnection) {
        deviceID = device.id
        let sorted = items.sorted { ($0.entry.bestDate ?? .distantPast) > ($1.entry.bestDate ?? .distantPast) }
        photos = Array(sorted.filter { $0.entry.kind == .photo }.prefix(12))
        videos = Array(sorted.filter { $0.entry.kind == .video }.prefix(4))
        loaded = true
    }

    private static func list(path: [String], storage: UInt32, backend: DeviceBackend) async throws -> [MediaItem] {
        var parent = MTPHandle.root
        for name in path {
            let children = try await backend.list(storage: storage, parent: parent)
            guard let folder = children.first(where: { $0.isFolder && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return [] }
            parent = folder.handle
        }
        let children = try await backend.list(storage: storage, parent: parent)
        return children.filter { !$0.isFolder && $0.kind.isMedia && !$0.isHidden }.map { MediaItem(entry: $0, path: path) }
    }
}

/// Belegung nach Dateiart (aus einer vollständigen Galerie-Suche).
struct StorageBreakdown {
    struct Slice: Identifiable {
        var id: String { title }
        let title: String
        let symbol: String
        let color: Color
        let bytes: UInt64
        let count: Int
    }

    let slices: [Slice]
    let largest: [MediaItem]

    init(items: [MediaItem]) {
        var photo: (UInt64, Int) = (0, 0), video: (UInt64, Int) = (0, 0), audio: (UInt64, Int) = (0, 0)
        var docs: (UInt64, Int) = (0, 0), other: (UInt64, Int) = (0, 0)
        for item in items {
            let s = item.entry.size
            switch item.entry.kind {
            case .photo: photo.0 += s; photo.1 += 1
            case .video: video.0 += s; video.1 += 1
            case .audio: audio.0 += s; audio.1 += 1
            case .document: docs.0 += s; docs.1 += 1
            default: other.0 += s; other.1 += 1
            }
        }
        slices = [
            Slice(title: "Fotos", symbol: "photo", color: FileKind.photo.tint, bytes: photo.0, count: photo.1),
            Slice(title: "Videos", symbol: "film", color: FileKind.video.tint, bytes: video.0, count: video.1),
            Slice(title: "Musik & Audio", symbol: "waveform", color: FileKind.audio.tint, bytes: audio.0, count: audio.1),
            Slice(title: "Dokumente", symbol: "doc.text", color: FileKind.document.tint, bytes: docs.0, count: docs.1),
            Slice(title: "Sonstiges", symbol: "shippingbox", color: FileKind.other.tint, bytes: other.0, count: other.1),
        ].filter { $0.count > 0 }
        largest = Array(items.filter { !$0.entry.isFolder }.sorted { $0.entry.size > $1.entry.size }.prefix(12))
    }

    var total: UInt64 { slices.reduce(0) { $0 + $1.bytes } }
}
