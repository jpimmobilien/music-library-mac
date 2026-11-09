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
    /// Vorgeladene Nachbarfotos (Eintrag → Datei), damit Blättern ohne Wartezeit geht.
    @State private var prefetched: [DeviceEntry.ID: URL] = [:]
    @State private var prefetchTask: Task<Void, Never>?
    @State private var showInfo = false
    @State private var backdrop: NSImage?
    @State private var chromeVisible = true
    /// Aufzoomen aus der Galeriekachel: Vorschaubild fliegt von `item.origin` an seinen Platz.
    @State private var flying = false
    @State private var landed = false
    @Environment(\.animationsEnabled) private var animations
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                .opacity(flying ? 0 : 1)
            if flying { flight }
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
            startFlight()
        }
        .onDisappear(perform: cleanup)
    }

    // MARK: Aufzoomen

    private func startFlight() {
        guard item.origin != nil, backdrop != nil, animations, !reduceMotion, !SnapshotMode.isActive else { return }
        flying = true
        landed = false
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) { landed = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 0.15)) { flying = false }
        }
    }

    /// Fläche, in der das Foto steht (wie `stage` mit seinen Abständen).
    private func stageRect(in size: CGSize) -> CGRect {
        let bottom: CGFloat = items.count > 1 ? 112 : 40
        let right: CGFloat = 70 + (showInfo ? 300 : 0)
        return CGRect(x: 70, y: 70, width: max(10, size.width - 70 - right), height: max(10, size.height - 70 - bottom))
    }

    private var flight: some View {
        GeometryReader { geo in
            if let thumb = backdrop, let origin = item.origin {
                let area = stageRect(in: geo.size)
                let aspect = thumb.size.width / max(thumb.size.height, 1)
                let fitW = min(area.width, area.height * aspect)
                let target = CGRect(x: area.midX - fitW / 2, y: area.midY - fitW / aspect / 2, width: fitW, height: fitW / aspect)
                let r = landed ? target : origin
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: r.width, height: r.height)
                    .clipShape(RoundedRectangle(cornerRadius: landed ? 2 : 12, style: .continuous))
                    .shadow(color: .black.opacity(landed ? 0.6 : 0.2), radius: landed ? 30 : 8)
                    .position(x: r.midX, y: r.midY)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Ebenen

    private var background: some View {
        ZStack {
            // Die übrige Oberfläche bleibt dahinter sichtbar – stark weichgezeichnet und abgedunkelt
            BackdropBlur(material: .fullScreenUI, blending: .withinWindow)
            Color.black.opacity(0.62)
            if let backdrop {
                Color.clear
                    .overlay(Image(nsImage: BackdropImage.tiny(backdrop)).resizable().interpolation(.high).aspectRatio(contentMode: .fill))
                    .clipped()
                    .opacity(0.32)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.4), value: backdrop != nil)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { close() }
    }

    @ViewBuilder
    private var stage: some View {
        if let image {
            let px = Self.pixelSize(image)
            // Die Bildfläche hat das Seitenverhältnis des Bildes und ist höchstens so groß wie das Bild –
            // SwiftUI zentriert sie; Zoomen und Verschieben bleiben im Inneren möglich.
            ZoomableImageView(image: image)
                .aspectRatio(px, contentMode: .fit)
                .frame(maxWidth: px.width, maxHeight: px.height)
                .shadow(color: .black.opacity(0.6), radius: 30)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else if let player {
            VideoPlayer(player: player)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.6), radius: 30)
                .onAppear { player.play() }
        } else if loading {
            ZStack(alignment: .bottom) {
                if let backdrop {
                    // Vorschaubild an der Stelle, an der gleich das Foto erscheint
                    Image(nsImage: backdrop).resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .shadow(color: .black.opacity(0.6), radius: 30)
                }
                VStack(spacing: 8) {
                    ProgressView(value: progress).frame(width: 220).tint(Palette.accent)
                    Text("Wird vom Telefon geladen … \(Int(progress * 100)) %")
                        .font(.ui(12, .medium)).foregroundStyle(.white.opacity(0.85)).monospacedDigit()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassSurface(Capsule())
                .padding(.bottom, 18)
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

    static func pixelSize(_ image: NSImage) -> CGSize {
        let rep = image.representations.first
        let w = CGFloat(rep?.pixelsWide ?? 0), h = CGFloat(rep?.pixelsHigh ?? 0)
        if w > 0 && h > 0 { return CGSize(width: w, height: h) }
        return CGSize(width: max(image.size.width, 1), height: max(image.size.height, 1))
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
        prefetchTask?.cancel()
        if current.kind == .photo, let url = prefetched[current.id], let img = NSImage(contentsOf: url) {
            // Schon vorgeladen – sofort zeigen
            loading = false
            image = img
            prefetchNeighbors()
            return
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
                    prefetched[current.id] = url
                    prefetchNeighbors()
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

    /// Lädt das nächste und das vorige Foto im Hintergrund (nacheinander, über dieselbe USB-Warteschlange).
    private func prefetchNeighbors() {
        guard let backend = device.backend else { return }
        let neighbors = [index + 1, index - 1, index + 2]
            .filter { items.indices.contains($0) }
            .map { items[$0] }
            .filter { $0.kind == .photo && $0.size < 80_000_000 && prefetched[$0.id] == nil }
        for e in neighbors where ThumbnailService.shared.cached(ThumbnailService.key(device: device, entry: e)) == nil {
            Task { _ = await ThumbnailService.shared.thumbnail(for: e, device: device) }
        }
        guard !neighbors.isEmpty else { return }
        let folder = AppPaths.previewCache
        prefetchTask = Task {
            for e in neighbors {
                if Task.isCancelled { return }
                let url = folder.appendingPathComponent("\(UUID().uuidString)-\(FileNameSanitizer.macSafe(e.name))")
                do {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                    let handle = try FileHandle(forWritingTo: url)
                    defer { try? handle.close() }
                    let flag = CancelFlag()
                    try await withTaskCancellationHandler {
                        try await backend.download(handle: e.handle, sink: { data in
                            try handle.write(contentsOf: data)
                        }, progress: { _ in !flag.isCancelled })
                    } onCancel: {
                        flag.cancel()
                    }
                    try handle.synchronize()
                    if Task.isCancelled {
                        try? FileManager.default.removeItem(at: url)
                        return
                    }
                    tempFiles.append(url)
                    prefetched[e.id] = url
                } catch {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
            }
        }
    }

    private func cleanup() {
        prefetchTask?.cancel()
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
        let scroll = FittingScrollView()
        scroll.contentView = CenteringClipView()
        // Überlagernde Rollbalken auch mit Maus (sonst verkleinern sie die Fläche und das Bild passt nie ganz)
        scroll.scrollerStyle = .overlay
        scroll.onResize = { [weak coordinator = context.coordinator] in
            guard let coordinator, coordinator.isFitted else { return }
            coordinator.fit()
        }
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
        } else if context.coordinator.isFitted, context.coordinator.fittedSize != scroll.frame.size {
            // Fenstergröße geändert: weiterhin ganz zeigen
            DispatchQueue.main.async { context.coordinator.fit() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        weak var scrollView: NSScrollView?
        var fittedSize: NSSize = .zero
        var isFitted = true

        func fit() {
            guard let scroll = scrollView, let doc = scroll.documentView else { return }
            let visible = scroll.frame.size
            guard doc.frame.width > 0, doc.frame.height > 0, visible.width > 0, visible.height > 0 else { return }
            let scale = min(visible.width / doc.frame.width, visible.height / doc.frame.height, 1)
            scroll.magnification = max(scale, scroll.minMagnification)
            fittedSize = scroll.frame.size
            isFitted = true
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
                isFitted = false
                scroll.animator().setMagnification(1, centeredAt: point)
            } else {
                fit()
            }
        }
    }
}

/// Meldet Größenänderungen (Fenster, Infobereich), damit ein eingepasstes Bild eingepasst bleibt.
final class FittingScrollView: NSScrollView {
    var onResize: (() -> Void)?
    private var lastSize: NSSize = .zero

    override func layout() {
        super.layout()
        if scrollerStyle != .overlay { scrollerStyle = .overlay }
        if frame.size != lastSize {
            lastSize = frame.size
            onResize?()
        }
    }
}

/// Hält ein kleineres Bild in der Mitte (statt unten links).
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return rect }
        if rect.width > doc.frame.width { rect.origin.x = (doc.frame.width - rect.width) / 2 }
        if rect.height > doc.frame.height { rect.origin.y = (doc.frame.height - rect.height) / 2 }
        return rect
    }
}

/// Stark verkleinertes Bild – vergrößert wirkt es weich wie unscharf, ohne teuren Unschärfefilter.
enum BackdropImage {
    static func tiny(_ image: NSImage) -> NSImage {
        let size = NSSize(width: 24, height: 18)
        let out = NSImage(size: size)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        out.unlockFocus()
        return out
    }
}
