import SwiftUI
import AppKit
import AVKit
import ABCore

/// Große Vorschau eines Fotos bzw. Videos mit Zoom, Vor/Zurück und Übertragung auf den Mac.
/// Die Datei wird dafür in einen temporären Ordner geladen und beim Schließen gelöscht.
struct MediaViewer: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var device: DeviceConnection
    let item: MediaViewerItem
    @State private var index: Int = 0
    @State private var image: NSImage?
    @State private var videoURL: URL?
    @State private var player: AVPlayer?
    @State private var loading = false
    @State private var progress: Double = 0
    @State private var loadError: String?
    @State private var tempFiles: [URL] = []
    @State private var transferred = Set<String>()
    @State private var loadTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    private var entry: DeviceEntry { item.items[min(max(index, 0), item.items.count - 1)] }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black.opacity(0.92)
                if let image {
                    ZoomableImageView(image: image)
                } else if let player {
                    VideoPlayer(player: player)
                } else if loading {
                    VStack(spacing: 12) {
                        if let thumb = ThumbnailService.shared.cached(ThumbnailService.key(device: device, entry: entry)) {
                            Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: 360, maxHeight: 360).blur(radius: 6)
                        }
                        ProgressView(value: progress).frame(width: 220).tint(Palette.bridgeGreen)
                        Text("Wird vom Telefon geladen … \(Int(progress * 100)) %").font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                    }
                } else if let loadError {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 30)).foregroundStyle(.white)
                        Text(loadError).foregroundStyle(.white.opacity(0.85)).font(.system(size: 13))
                    }
                }
                HStack {
                    navButton("chevron.left", enabled: index > 0) { step(-1) }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                    Spacer()
                    navButton("chevron.right", enabled: index < item.items.count - 1) { step(1) }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                }
                .padding(.horizontal, 14)
            }
            infoBar
        }
        .frame(minWidth: 820, idealWidth: 1040, minHeight: 600, idealHeight: 760)
        .onAppear {
            index = item.index
            load()
        }
        .onDisappear(perform: cleanup)
    }

    private var infoBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).font(.system(size: 14, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 10) {
                    Text(ByteFormat.string(entry.size))
                    if let dims = dimensions { Text(dims) }
                    if let date = entry.bestDate { Text(date.formatted(date: .long, time: .shortened)) }
                    Text("\(index + 1) von \(item.items.count)")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Spacer()
            if transferred.contains(entry.id) {
                Label("Übertragung gestartet", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.success).font(.system(size: 12.5, weight: .medium))
            }
            Button {
                let destination = model.settings.destination(for: entry.kind)
                model.transfers.download([entry], from: device, sourcePath: [], to: destination)
                transferred.insert(entry.id)
            } label: {
                Label("Auf den Mac übertragen", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(GlassButtonStyle(prominent: true))
            Button("Schließen") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(GlassButtonStyle())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private var dimensions: String? {
        if let image, let rep = image.representations.first, rep.pixelsWide > 0 {
            return "\(rep.pixelsWide) × \(rep.pixelsHigh)"
        }
        if entry.imageWidth > 0 { return "\(entry.imageWidth) × \(entry.imageHeight)" }
        return nil
    }

    private func navButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .glassSurface(Circle(), interactive: true)
        .opacity(enabled ? 1 : 0)
        .disabled(!enabled)
    }

    private func step(_ delta: Int) {
        let next = index + delta
        guard next >= 0 && next < item.items.count else { return }
        index = next
        load()
    }

    private func load() {
        loadTask?.cancel()
        player?.pause()
        player = nil
        image = nil
        loadError = nil
        progress = 0
        guard let backend = device.backend else {
            loadError = "Das Telefon ist nicht mehr verbunden."
            return
        }
        let current = entry
        loading = true
        let folder = AppPaths.previewCache
        let url = folder.appendingPathComponent("\(UUID().uuidString)-\(FileNameSanitizer.macSafe(current.name))")
        tempFiles.append(url)
        loadTask = Task {
            do {
                FileManager.default.createFile(atPath: url.path, contents: nil)
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                let total = Double(max(current.size, 1))
                let reporter = ProgressCounter()
                let ticker = Task { @MainActor in
                    while !Task.isCancelled {
                        progress = min(1, Double(reporter.current) / total)
                        try? await Task.sleep(nanoseconds: 120_000_000)
                    }
                }
                defer { ticker.cancel() }
                let flag = CancelFlag()
                try await withTaskCancellationHandler {
                    try await backend.download(handle: current.handle, sink: { data in
                        try handle.write(contentsOf: data)
                        reporter.addCurrent(UInt64(data.count))
                    }, progress: { _ in !flag.isCancelled })
                } onCancel: {
                    flag.cancel()
                }
                try handle.synchronize()
                guard !Task.isCancelled, current.id == entry.id else { return }
                loading = false
                if current.kind == .video {
                    player = AVPlayer(url: url)
                } else if let img = NSImage(contentsOf: url) {
                    image = img
                } else {
                    loadError = "Dieses Bildformat kann nicht angezeigt werden."
                }
            } catch {
                guard !Task.isCancelled else { return }
                loading = false
                loadError = ABIssue.from(error).title
            }
        }
    }

    private func cleanup() {
        loadTask?.cancel()
        player?.pause()
        player = nil
        for url in tempFiles { try? FileManager.default.removeItem(at: url) }
        tempFiles = []
    }
}

/// Bild mit Zoom (Trackpad, Doppelklick) – NSScrollView mit Vergrößerung.
struct ZoomableImageView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.05
        scroll.maxMagnification = 10
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        scroll.documentView = imageView
        let doubleClick = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.toggleZoom(_:)))
        doubleClick.numberOfClicksRequired = 2
        scroll.addGestureRecognizer(doubleClick)
        context.coordinator.scrollView = scroll
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let imageView = scroll.documentView as? NSImageView else { return }
        if imageView.image !== image {
            imageView.image = image
            let rep = image.representations.first
            let w = CGFloat(rep?.pixelsWide ?? Int(image.size.width))
            let h = CGFloat(rep?.pixelsHigh ?? Int(image.size.height))
            let size = NSSize(width: max(w, 1), height: max(h, 1))
            imageView.frame = NSRect(origin: .zero, size: size)
            DispatchQueue.main.async { context.coordinator.fit() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        weak var scrollView: NSScrollView?

        func fit() {
            guard let scroll = scrollView, let doc = scroll.documentView else { return }
            let visible = scroll.contentSize
            guard doc.frame.width > 0, doc.frame.height > 0, visible.width > 0 else { return }
            let scale = min(visible.width / doc.frame.width, visible.height / doc.frame.height, 1)
            scroll.magnification = max(scale, scroll.minMagnification)
            centre()
        }

        func centre() {
            guard let scroll = scrollView, let doc = scroll.documentView else { return }
            let visible = scroll.contentView.bounds.size
            let x = (doc.frame.width - visible.width) / 2
            let y = (doc.frame.height - visible.height) / 2
            scroll.contentView.scroll(to: NSPoint(x: max(0, x), y: max(0, y)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        @objc func toggleZoom(_ sender: NSClickGestureRecognizer) {
            guard let scroll = scrollView else { return }
            if scroll.magnification < 0.99 {
                let point = sender.location(in: scroll.documentView)
                scroll.animator().setMagnification(1, centeredAt: point)
            } else {
                fit()
            }
        }
    }
}
