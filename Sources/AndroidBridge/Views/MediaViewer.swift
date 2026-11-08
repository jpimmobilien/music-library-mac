import SwiftUI
import AppKit
import AVKit
import ABCore

/// Immersive Großansicht eines Fotos bzw. Videos über dem ganzen Fenster: unscharfer Bildhintergrund,
/// schwebende Glas-Bedienelemente, Filmstreifen, Informationen, Übertragen und Löschen.
/// Die Datei wird dafür in einen temporären Ordner geladen und beim Schließen gelöscht.
struct MediaViewer: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var device: DeviceConnection
    let item: MediaViewerItem
    @State private var items: [DeviceEntry] = []
    @State private var index: Int = 0
    @State private var image: NSImage?
    @State private var player: AVPlayer?
    @State private var loading = false
    @State private var progress: Double = 0
    @State private var loadError: String?
    @State private var tempFiles: [URL] = []
    @State private var transferred = Set<String>()
    @State private var loadTask: Task<Void, Never>?
    @State private var showInfo = false
    @State private var backdrop: NSImage?
    @State private var chromeVisible = true

    private var entry: DeviceEntry? {
        guard !items.isEmpty else { return nil }
        return items[min(max(index, 0), items.count - 1)]
    }

    var body: some View {
        ZStack {
            background
            stage
                .padding(.horizontal, 70)
                .padding(.top, 70)
                .padding(.bottom, items.count > 1 ? 112 : 40)
                .padding(.trailing, showInfo ? 300 : 0)
            navigation
            VStack(spacing: 0) {
                topBar
                    .padding(.leading, 64) // Platz für die Ampel-Knöpfe des Fensters
                Spacer()
                if items.count > 1 { filmstrip }
            }
            .padding(16)
            .padding(.trailing, showInfo ? 300 : 0)
            if showInfo, let entry {
                HStack {
                    Spacer()
                    infoPanel(entry)
                        .frame(width: 284)
                        .padding(.vertical, 16)
                        .padding(.trailing, 16)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .animation(Motion.gentle, value: showInfo)
        .onAppear {
            items = item.items
            index = item.index
            load()
        }
        .onDisappear(perform: cleanup)
    }

    // MARK: Ebenen

    private var background: some View {
        ZStack {
            Color.black
            if let backdrop {
                Image(nsImage: backdrop)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 60)
                    .opacity(0.55)
                    .transition(.opacity)
            }
            Color.black.opacity(0.35)
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.4), value: backdrop != nil)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { close() }
    }

    @ViewBuilder
    private var stage: some View {
        if let image {
            ZoomableImageView(image: image)
                .shadow(color: .black.opacity(0.6), radius: 30)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else if let player {
            VideoPlayer(player: player)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.6), radius: 30)
                .onAppear { player.play() }
        } else if loading {
            VStack(spacing: 18) {
                if let backdrop {
                    Image(nsImage: backdrop).resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 460, maxHeight: 460)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.25)))
                }
                ProgressView(value: progress).frame(width: 240).tint(Palette.bridgeGreen)
                Text("Wird vom Telefon geladen … \(Int(progress * 100)) %")
                    .font(.ui(12.5, .medium)).foregroundStyle(.white.opacity(0.8)).monospacedDigit()
            }
        } else if let loadError {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle").font(.ui(34)).foregroundStyle(.white)
                Text(loadError).foregroundStyle(.white.opacity(0.85)).font(.ui(14))
                Button("Erneut versuchen") { load() }.buttonStyle(GlassButtonStyle())
            }
        }
    }

    private var navigation: some View {
        HStack {
            roundButton("chevron.left", help: "Vorheriges (←)", enabled: index > 0) { step(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Spacer()
            roundButton("chevron.right", help: "Nächstes (→)", enabled: index < items.count - 1) { step(1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .padding(.horizontal, 18)
        .padding(.trailing, showInfo ? 300 : 0)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            roundButton("xmark", help: "Schließen (esc)", enabled: true, size: 36) { close() }
                .keyboardShortcut(.cancelAction)
            if let entry {
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name).font(.ui(14, .semibold)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                    Text(subtitle(for: entry)).font(.ui(11.5)).foregroundStyle(.white.opacity(0.65)).lineLimit(1).monospacedDigit()
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .glassSurface(Capsule())
                .frame(maxWidth: 520, alignment: .leading)
            }
            Spacer(minLength: 12)
            if let entry {
                GlassGroup {
                    HStack(spacing: 2) {
                        if transferred.contains(entry.id) {
                            Label("Übertragung gestartet", systemImage: "checkmark.circle.fill")
                                .font(.ui(12, .semibold))
                                .foregroundStyle(Palette.success)
                                .padding(.horizontal, 10)
                                .transition(.opacity)
                        }
                        ToolbarIconButton(symbol: "arrow.down.to.line", help: "Auf den Mac übertragen", tint: .white) { transfer(entry) }
                        ToolbarIconButton(symbol: "info.circle", help: "Informationen (I)", tint: .white, isOn: showInfo) { showInfo.toggle() }
                            .keyboardShortcut("i", modifiers: [])
                        ToolbarIconButton(symbol: "trash", help: "Auf dem Telefon löschen …", tint: Palette.danger) { delete(entry) }
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 44)
                    .glassSurface(Capsule())
                }
            }
        }
    }

    private var filmstrip: some View {
        let lower = max(0, index - 7)
        let upper = min(items.count, index + 8)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(lower..<upper, id: \.self) { i in
                    Button {
                        guard i != index else { return }
                        index = i
                        load()
                    } label: {
                        DeviceThumb(entry: items[i], device: device, size: 46, corner: 8)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(i == index ? Color.white : Color.clear, lineWidth: 2))
                            .scaleEffect(i == index ? 1.08 : 1)
                            .opacity(i == index ? 1 : 0.7)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: 760)
        .fixedSize(horizontal: true, vertical: false)
        .glassSurface(Capsule())
        .animation(Motion.spring, value: index)
    }

    private func infoPanel(_ entry: DeviceEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Informationen").font(Typo.title2).foregroundStyle(.white)
                infoRow("Name", entry.name)
                infoRow("Art", kindName(entry.kind, name: entry.name))
                infoRow("Größe", ByteFormat.string(entry.size))
                if let dims = dimensions(for: entry) { infoRow("Abmessungen", dims) }
                if let d = entry.modified { infoRow("Geändert", d.formatted(date: .long, time: .shortened)) }
                if let d = entry.created, d != entry.modified { infoRow("Aufgenommen", d.formatted(date: .long, time: .shortened)) }
                if let storage = device.storages.first(where: { $0.id == entry.storageID }) { infoRow("Speicher", storage.displayName) }
                infoRow("Gerät", device.displayName)
                infoRow("Position", "\(index + 1) von \(items.count)")
            }
            .padding(20)
        }
        .glassCard(cornerRadius: Radius.panel)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.ui(10, .semibold)).tracking(0.6).foregroundStyle(.white.opacity(0.5))
            Text(value).font(.ui(13)).foregroundStyle(.white).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func roundButton(_ symbol: String, help: String, enabled: Bool, size: CGFloat = 44, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.ui(size * 0.4, .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassSurface(Circle(), interactive: true)
        .opacity(enabled ? 1 : 0)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: Logik

    private func subtitle(for entry: DeviceEntry) -> String {
        var parts = [ByteFormat.string(entry.size)]
        if let dims = dimensions(for: entry) { parts.append(dims) }
        if let date = entry.bestDate { parts.append(date.formatted(date: .abbreviated, time: .shortened)) }
        parts.append("\(index + 1) von \(items.count)")
        return parts.joined(separator: " · ")
    }

    private func dimensions(for entry: DeviceEntry) -> String? {
        if entry.id == self.entry?.id, let image, let rep = image.representations.first, rep.pixelsWide > 0 {
            return "\(rep.pixelsWide) × \(rep.pixelsHigh)"
        }
        if entry.imageWidth > 0 { return "\(entry.imageWidth) × \(entry.imageHeight)" }
        return nil
    }

    private func close() {
        cleanup()
        model.viewerItem = nil
    }

    private func transfer(_ entry: DeviceEntry) {
        let destination = model.settings.destination(for: entry.kind)
        model.transfers.download([entry], from: device, sourcePath: [], to: destination)
        withAnimation(.bridgeQuick) { _ = transferred.insert(entry.id) }
    }

    private func delete(_ entry: DeviceEntry) {
        let location = device.storages.first(where: { $0.id == entry.storageID })?.displayName ?? device.displayName
        model.requestDeletion([entry], on: device, locations: [location]) { outcome in
            guard outcome.deletedIDs.contains(entry.id) else { return }
            items.removeAll { $0.id == entry.id }
            if items.isEmpty {
                close()
            } else {
                index = min(index, items.count - 1)
                load()
            }
        }
    }

    private func step(_ delta: Int) {
        let next = index + delta
        guard next >= 0 && next < items.count else { return }
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
        guard let current = entry else { return }
        backdrop = ThumbnailService.shared.cached(ThumbnailService.key(device: device, entry: current))
        if backdrop == nil {
            Task { backdrop = await ThumbnailService.shared.thumbnail(for: current, device: device) }
        }
        guard let backend = device.backend else {
            loadError = "Das Telefon ist nicht mehr verbunden."
            return
        }
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
                guard !Task.isCancelled, current.id == entry?.id else { return }
                loading = false
                if current.kind == .video {
                    player = AVPlayer(url: url)
                } else if let img = NSImage(contentsOf: url) {
                    withAnimation(Motion.easeOut(0.35)) { image = img }
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
