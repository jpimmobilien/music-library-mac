import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import MLCore
import MLStore
import MLTags

/// Metadaten schreiben (sicher, mit Rückgängig), Cover verarbeiten, Kopieren/Einfügen.
@MainActor
final class MetadataService: ObservableObject {
    weak var model: AppModel?
    let store: LibraryStore
    let writer = SafeTagWriter()

    /// Kopierte Metadaten (Werte + Felder) für „Metadaten einfügen“.
    @Published var clipboard: (TagValues, Set<TagField>)?
    /// Bereich, mit dem das Informationsfenster beim nächsten Öffnen beginnt.
    var requestedTab: EditorTab?
    /// Zuletzt geschriebene Stapel (für ⌘Z), neueste zuletzt.
    @Published private(set) var undoStack: [(id: UUID, label: String)] = []
    @Published private(set) var writing = false

    var hasClipboard: Bool { clipboard != nil }

    init(store: LibraryStore) {
        self.store = store
    }

    /// Alte Sicherungen entfernen (Einstellung „Sicherungen aufbewahren“).
    func cleanupBackups(days: Int) {
        let writer = self.writer
        Task.detached(priority: .background) { _ = try? writer.cleanupBackups(olderThan: days) }
    }

    // MARK: - Schreiben

    /// Schreibt die Änderungen des Bearbeitungsfensters. Gibt `true` zurück, wenn alles geschrieben wurde.
    func apply(session: EditorSession) async -> Bool {
        guard let model else { return false }
        let edit = session.makeEdit()
        guard !edit.isEmpty else { return true }
        if model.settings.confirmBeforeWritingTags && session.files.count > 1 {
            let alert = NSAlert()
            alert.messageText = "\(Formatting.tracks(session.files.count)) ändern?"
            alert.informativeText = "Geändert wird: \(session.summary).\n\nJede Datei wird vorher gesichert, als Kopie bearbeitet, gegengelesen und erst dann ersetzt. Die Originale bleiben \(model.settings.backupRetentionDays) Tage gesichert."
            alert.addButton(withTitle: "Ändern")
            alert.addButton(withTitle: "Abbrechen")
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
        }
        var requests: [(uid: Int64, request: TagWriteRequest)] = session.files.map { ($0.track.uid, TagWriteRequest(url: $0.url, edit: edit)) }
        // Cover für das ganze Album übernehmen: übrige Titel des Albums erhalten nur die Bilder
        if session.applyCoverToAlbum, session.picturesDirty, let first = session.files.first,
           let album = model.index.albumOf(first.track.uid) {
            let selected = Set(session.uids)
            for uid in album.trackUids where !selected.contains(uid) {
                if let t = model.track(uid), t.available {
                    requests.append((uid, TagWriteRequest(url: URL(fileURLWithPath: t.path), edit: TagEdit(pictures: edit.pictures))))
                }
            }
        }
        return await write(requests, label: session.files.count == 1 ? "„\(session.files[0].track.displayTitle)“" : Formatting.tracks(requests.count))
    }

    /// Gemeinsamer Schreibweg (Bearbeitungsfenster, Einfügen, Bewertung …).
    func write(_ requests: [(uid: Int64, request: TagWriteRequest)], label: String) async -> Bool {
        guard let model, !requests.isEmpty else { return true }
        writing = true
        let writer = self.writer
        let reqs = requests.map(\.request)
        let result = await Task.detached(priority: .userInitiated) { writer.write(batch: reqs) }.value
        writing = false
        // Bibliothek aktualisieren (neu einlesen der geschriebenen Dateien)
        var updated = 0
        for (i, r) in result.results.enumerated() where r.succeeded {
            let uid = requests[i].uid
            if let t = model.track(uid) { ArtworkStore.shared.invalidate(t) }
            model.library.refreshTrack(uid: uid)
            updated += 1
        }
        if updated > 0 {
            undoStack.append((result.batchID, label))
            model.reloadLibrary()
            NotificationCenter.default.post(name: .lyricsChanged, object: nil)
        }
        let failed = result.failed
        if failed.isEmpty {
            model.toast("\(label) geändert", action: "Rückgängig") { [weak self] in self?.undo(batch: result.batchID) }
            return true
        }
        let details = failed.prefix(5).map { "• \($0.url.lastPathComponent): \($0.error?.localizedDescription ?? "Fehler")" }.joined(separator: "\n")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = failed.count == requests.count ? "Die Änderungen konnten nicht geschrieben werden." : "\(failed.count) von \(requests.count) Dateien konnten nicht geändert werden."
        alert.informativeText = details + (failed.count > 5 ? "\n…" : "") + "\n\nDie betroffenen Originaldateien sind unverändert."
        alert.runModal()
        return false
    }

    /// Einen Stapel rückgängig machen (Originale bytegleich wiederherstellen).
    func undo(batch id: UUID) {
        guard let model else { return }
        let writer = self.writer
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<TagUndoResult, Error> in
                do { return .success(try writer.undo(batch: id)) } catch { return .failure(error) }
            }.value
            undoStack.removeAll { $0.id == id }
            switch result {
            case .success(let r):
                for f in r.results {
                    if let t = model.index.tracks.first(where: { $0.path == f.path }) {
                        ArtworkStore.shared.invalidate(t)
                        model.library.refreshTrack(uid: t.uid)
                    }
                }
                model.reloadLibrary()
                NotificationCenter.default.post(name: .lyricsChanged, object: nil)
                if r.allSucceeded {
                    model.toast("Änderungen rückgängig gemacht")
                } else {
                    model.toast("Nicht alle Dateien konnten wiederhergestellt werden (wurden sie seitdem geändert?)", isError: true)
                }
            case .failure(let e):
                model.toast("Rückgängig nicht möglich: \(e.localizedDescription)", isError: true)
            }
        }
    }

    func undoLast() {
        if let last = undoStack.last { undo(batch: last.id) }
    }

    var canUndo: Bool { !undoStack.isEmpty }

    /// Zuletzt geschriebene Stapel (Einstellungen → Metadaten).
    func recentJournals() -> [TagWriteJournal] {
        writer.journals().sorted { $0.created > $1.created }
    }

    // MARK: - Bewertung direkt aus Listen

    func setRating(_ stars: Int, for uids: [Int64]) {
        var values = TagValues()
        values.rating = stars == 0 ? nil : stars * 20
        let edit = TagEdit(values: values, fields: [.rating])
        let reqs = model?.tracks(uids).map { ($0.uid, TagWriteRequest(url: URL(fileURLWithPath: $0.path), edit: edit)) } ?? []
        Task { _ = await write(reqs, label: Formatting.tracks(uids.count)) }
    }

    // MARK: - Kopieren / Einfügen

    func copyMetadata(from uid: Int64?) {
        guard let uid, let t = model?.track(uid) else { return }
        Task {
            let result = await Task.detached { try? TagFile.read(url: URL(fileURLWithPath: t.path)) }.value
            guard let values = result?.values else { return }
            let fields = Set(TagField.allCases.filter { !$0.isPerTrackOnly && !values.text(for: $0).isEmpty })
            clipboard = (values, fields)
            model?.toast("Metadaten von „\(t.displayTitle)“ kopiert (\(fields.count) Felder)")
        }
    }

    /// Kopierte Metadaten auf die ausgewählten Titel übertragen (Felder wählbar).
    func pasteMetadata(to uids: [Int64]) {
        guard let clip = clipboard, let model, !uids.isEmpty else { return }
        let (values, fields) = clip
        let ordered = TagField.allCases.filter { fields.contains($0) }
        let alert = NSAlert()
        alert.messageText = "Metadaten auf \(Formatting.tracks(uids.count)) übertragen?"
        alert.informativeText = "Gewählte Felder werden überschrieben. Alles wird vorher gesichert und kann rückgängig gemacht werden."
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        var boxes: [(TagField, NSButton)] = []
        for f in ordered {
            let v = values.text(for: f)
            let b = NSButton(checkboxWithTitle: "\(f.label): \(v.count > 40 ? String(v.prefix(40)) + "…" : v)", target: nil, action: nil)
            b.state = [.album, .albumArtists, .genres, .year, .composers, .compilation, .publisher, .copyright].contains(f) ? .on : .off
            stack.addArrangedSubview(b)
            boxes.append((f, b))
        }
        stack.frame = NSRect(x: 0, y: 0, width: 380, height: CGFloat(boxes.count) * 22)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Übertragen")
        alert.addButton(withTitle: "Abbrechen")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let chosen = Set(boxes.filter { $0.1.state == .on }.map(\.0))
        guard !chosen.isEmpty else { return }
        let edit = TagEdit(values: values, fields: chosen)
        let reqs = model.tracks(uids).map { ($0.uid, TagWriteRequest(url: URL(fileURLWithPath: $0.path), edit: edit)) }
        Task { _ = await write(reqs, label: Formatting.tracks(uids.count)) }
    }

    // MARK: - Bilder

    /// Bilddaten für das Einbetten vorbereiten: JPEG/PNG bleiben (ggf. verkleinert), andere Formate → JPEG.
    nonisolated static func preparePicture(_ data: Data, downscale: Bool, kind: PictureKind = .frontCover) -> EmbeddedPicture? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(src) > 0 else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let w = (props?[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let h = (props?[kCGImagePropertyPixelHeight] as? Int) ?? 0
        let type = CGImageSourceGetType(src) as String?
        let isJPEG = type == UTType.jpeg.identifier
        let isPNG = type == UTType.png.identifier
        let tooLarge = downscale && max(w, h) > 3000
        if (isJPEG || isPNG) && !tooLarge {
            return EmbeddedPicture(kind: kind, mimeType: isJPEG ? "image/jpeg" : "image/png", data: data)
        }
        let maxSide = tooLarge ? 3000 : max(w, h, 1)
        guard let cg = ArtworkStore.downsample(data: data, maxPixels: maxSide) else { return nil }
        if isPNG, let png = pngData(cg) {
            return EmbeddedPicture(kind: kind, mimeType: "image/png", data: png)
        }
        guard let jpeg = ArtworkStore.jpegData(cg, quality: 0.92) else { return nil }
        return EmbeddedPicture(kind: kind, mimeType: "image/jpeg", data: jpeg)
    }

    nonisolated static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    func chooseImages(downscale: Bool, multiple: Bool = true) -> [EmbeddedPicture] {
        let panel = NSOpenPanel()
        panel.title = "Bild wählen"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = multiple
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { url in (try? Data(contentsOf: url)).flatMap { Self.preparePicture($0, downscale: downscale) } }
    }

    func pictureFromPasteboard(downscale: Bool) -> EmbeddedPicture? {
        let pb = NSPasteboard.general
        for type in [NSPasteboard.PasteboardType.png, .tiff, NSPasteboard.PasteboardType("public.jpeg"), NSPasteboard.PasteboardType("public.heic")] {
            if let data = pb.data(forType: type), let pic = Self.preparePicture(data, downscale: downscale) { return pic }
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL] {
            for url in urls { if let data = try? Data(contentsOf: url), let pic = Self.preparePicture(data, downscale: downscale) { return pic } }
        }
        return nil
    }

    func loadDroppedImages(_ providers: [NSItemProvider], completion: @escaping ([EmbeddedPicture]) -> Void) {
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, let data = try? Data(contentsOf: url), let pic = MetadataService.preparePicture(data, downscale: true) else { return }
                    DispatchQueue.main.async { completion([pic]) }
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data, let pic = MetadataService.preparePicture(data, downscale: true) else { return }
                    DispatchQueue.main.async { completion([pic]) }
                }
            }
        }
    }

    func export(_ picture: EmbeddedPicture, suggestedName: String) {
        let panel = NSSavePanel()
        let isPNG = picture.mimeType == "image/png"
        panel.allowedContentTypes = [isPNG ? .png : .jpeg]
        panel.nameFieldStringValue = suggestedName.replacingOccurrences(of: "/", with: "-") + (isPNG ? ".png" : ".jpg")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try picture.data.write(to: url, options: .atomic)
            model?.toast("Cover gesichert: \(url.lastPathComponent)")
        } catch {
            model?.toast("Cover konnte nicht gesichert werden: \(error.localizedDescription)", isError: true)
        }
    }
}
