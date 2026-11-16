import SwiftUI
import AppKit
import MLCore
import MLStudio
import MLTags
import StudioEngine

// „Meine Produktionen“: alle Hörbücher/Hörspiele mit Stand, Anhören, Fortsetzen, Bearbeiten, Exportieren.

struct HSProductionsView: View {
    @ObservedObject var hs: HoerspielModel
    @Environment(\.musicColors) private var colors
    @State private var exporting: HSProduction?
    @State private var renaming: HSProduction?
    @State private var newName = ""
    @State private var confirmTrash: HSProduction?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(text: "Meine Produktionen")
                Spacer()
                PillButton(title: "Ordner zeigen", icon: Icons.folderOpen, style: .plain) { hs.revealFolder() }
            }
            if hs.productions.isEmpty {
                EmptyStateView(icon: Icons.audiobook, title: "Noch keine Produktionen",
                               text: "Unter „Hörspiel erstellen“ oder „Hörbuch erstellen“ beginnt deine erste Geschichte.")
            }
            ForEach(hs.productions) { p in row(p) }
        }
        .sheet(item: $exporting) { p in HSExportSheet(hs: hs, production: p) }
        .alert("Produktion umbenennen", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Titel", text: $newName)
            Button("Umbenennen") { if let r = renaming { hs.rename(r, to: newName) }; renaming = nil }
            Button("Abbrechen", role: .cancel) { renaming = nil }
        }
        .alert("In den Papierkorb legen?", isPresented: Binding(get: { confirmTrash != nil }, set: { if !$0 { confirmTrash = nil } })) {
            Button("In den Papierkorb", role: .destructive) { if let p = confirmTrash { hs.trash(p) }; confirmTrash = nil }
            Button("Abbrechen", role: .cancel) { confirmTrash = nil }
        } message: {
            Text("Der Ordner der Produktion (Drehbuch, Stimmen, Mischung) wird in den Papierkorb gelegt und lässt sich von dort zurückholen.")
        }
    }

    private func row(_ p: HSProduction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [colors.accent.opacity(0.85), colors.accentStrong], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 54, height: 54)
                    Icon(p.mode == .hoerspiel ? Icons.drama : Icons.audiobook, size: 26, color: .white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.title.isEmpty ? "Neue Produktion" : p.title)
                        .textStyle(Typo.titleMedium).foregroundColor(colors.textPrimary).lineLimit(1)
                    Text(subtitle(p)).textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).lineLimit(2)
                    if !p.logline.isEmpty {
                        Text(p.logline).textStyle(Typo.bodySmall).foregroundColor(colors.textTertiary).lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                if let mix = p.mix {
                    let url = hs.file(mix.master, in: p)
                    GlassIconButton(icon: hs.playingKey == "master-\(p.id)" ? Icons.pause : Icons.play, label: "Fertige Mischung anhören",
                                    size: 36) { hs.play(url, key: "master-\(p.id)") }
                }
            }
            HSStepsRow(production: p)
            HStack(spacing: 8) {
                let finished = p.state(.mix) == .done
                PillButton(title: finished ? "Neu abmischen" : "Fortsetzen", icon: Icons.play, style: finished ? .tonal : .filled) {
                    hs.currentID = p.id
                    if finished { hs.runStep(.mix, p.id) } else { hs.produce(p.id) }
                }
                .disabled(hs.isWorking || hs.setup != .ready)
                PillButton(title: "Bearbeiten", icon: Icons.editNote, style: .tonal) {
                    hs.currentID = p.id
                    hs.section = .editor
                }
                PillButton(title: "Exportieren", icon: Icons.fileExport, style: .tonal) { exporting = p }
                    .disabled(p.mix == nil)
                Spacer()
                GlassMenuButton(help: "Weitere Aktionen", width: 240) {
                    Icon(Icons.moreHoriz, size: 18, color: colors.textSecondary).frame(width: 32, height: 32)
                } content: { menu in
                    GlassMenuItem(title: "Umbenennen", icon: Icons.edit) { newName = p.title; renaming = p; menu.close() }
                    GlassMenuItem(title: "Im Finder zeigen", icon: Icons.folderOpen) {
                        NSWorkspace.shared.activateFileViewerSelecting([hs.folder(p)])
                        menu.close()
                    }
                    GlassMenuDivider()
                    GlassMenuItem(title: "In den Papierkorb …", icon: Icons.delete) { confirmTrash = p; menu.close() }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func subtitle(_ p: HSProduction) -> String {
        var parts = [p.mode.title, "\(p.figures.count) Figuren", "\(p.scenes.count) Szenen"]
        if let mix = p.mix { parts.append(HSFormat.duration(mix.duration)) } else if p.spokenWords > 0 {
            parts.append("ca. \(Int(p.estimatedMinutes.rounded())) min (geschätzt)")
        }
        if let l = p.mix?.loudness { parts.append(String(format: "%.1f LUFS", l)) }
        parts.append(p.modified.formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: " · ")
    }
}

// MARK: - Export

struct HSExportSheet: View {
    @ObservedObject var hs: HoerspielModel
    let production: HSProduction
    @Environment(\.musicColors) private var colors
    @Environment(\.dismiss) private var dismiss
    @State private var format: StudioFormat = .mp3
    @State private var bitrate = 192
    @State private var scope: HSExportScope = .whole
    @State private var title = ""
    @State private var artist = "KI-Hörspiel"
    @State private var genre = ""
    @State private var cover: Data?
    @State private var running = false
    @State private var progress = 0.0
    @State private var result: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Exportieren").textStyle(Typo.headlineSmall).foregroundColor(colors.textPrimary)
            HSFormat.label("Umfang", colors)
            SegmentedControl(options: HSExportScope.allCases, selection: $scope, label: { $0.label })
            HSFormat.label("Format", colors)
            SegmentedControl(options: [StudioFormat.mp3, .m4a, .flac, .wav], selection: $format, label: { $0.label })
            if format == .mp3 {
                SegmentedControl(options: [128, 192, 256, 320], selection: $bitrate, label: { "\($0) kbit/s" })
            }
            HSFormat.label("Metadaten", colors)
            HStack {
                TextField("Titel", text: $title)
                TextField("Interpret", text: $artist)
                TextField("Genre", text: $genre)
            }
            .textFieldStyle(.roundedBorder)
            HStack(spacing: 10) {
                if let cover, let img = NSImage(data: cover) {
                    Image(nsImage: img).resizable().scaledToFill().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                PillButton(title: cover == nil ? "Cover hinzufügen …" : "Anderes Cover …", icon: Icons.image, style: .tonal) { pickCover() }
                if cover != nil { PillButton(title: "Ohne Cover", style: .plain) { cover = nil } }
            }
            Text(note).textStyle(Typo.bodySmall).foregroundColor(colors.textTertiary).fixedSize(horizontal: false, vertical: true)
            if running { ProgressView(value: progress).tint(colors.accent) }
            if let result { Text(result).textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary) }
            HStack {
                Spacer()
                PillButton(title: "Schließen", style: .plain) { dismiss() }
                PillButton(title: "Exportieren …", icon: Icons.fileExport, style: .filled) { start() }
                    .disabled(running || HSExportPlan.items(for: production, scope: scope).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 560)
        .onAppear {
            title = production.title
            genre = production.mode == .hoerspiel ? "Hörspiel" : "Hörbuch"
        }
    }

    private var note: String {
        switch scope {
        case .whole: return "Eine Datei mit der fertigen Mischung – bei MP3 und M4A mit Kapitelmarken (Kapitel bzw. Szenen)."
        case .chapters: return "Je Kapitel eine Datei, nummeriert – so bleibt die Kapitelstruktur in jedem Player erhalten."
        case .scenes: return "Je Szene eine Datei, nummeriert."
        case .stems: return "Jede Spur (Erzähler, Figuren, Musik, Geräusche, Atmo) als eigene Datei – zum Weiterbearbeiten."
        }
    }

    /// Kapitelmarken der Gesamtdatei: Kapitel, wenn es mehrere gibt, sonst Szenen.
    static func chapterMarks(_ p: HSProduction) -> [ChapterWriter.Chapter] {
        if p.chapters.count > 1 {
            return HSExportPlan.items(for: p, scope: .chapters).compactMap { i in i.trim.map { ChapterWriter.Chapter(title: i.title, start: $0.start) } }
        }
        return (p.mix?.chapters ?? []).map { ChapterWriter.Chapter(title: $0.title, start: $0.start) }
    }

    private func pickCover() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { cover = try? Data(contentsOf: url) }
    }

    private func start() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Hierhin exportieren"
        panel.directoryURL = hs.store.root
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        let meta = StudioMetadata(title: title, artist: artist, album: production.title, albumArtist: artist,
                                  year: Calendar.current.component(.year, from: Date()), genre: genre, cover: cover)
        running = true
        progress = 0
        result = nil
        let p = production
        Task { @MainActor in
            do {
                let files = try await hs.export(p, scope: scope, format: format, bitrate: bitrate, metadata: meta, to: dir) { v in
                    Task { @MainActor in progress = v }
                }
                result = "\(files.count) Datei\(files.count == 1 ? "" : "en") exportiert nach \(dir.path)."
                NSWorkspace.shared.activateFileViewerSelecting([dir])
            } catch {
                result = "Export abgebrochen: \(StudioModel.message(error))"
            }
            running = false
        }
    }
}

extension HoerspielModel {
    /// Export wie im Dialog „Exportieren“: ganze Produktion, Kapitel oder Szenen; bei der ganzen Produktion als MP3/M4A
    /// mit Kapitelmarken. Gibt die geschriebenen Dateien zurück.
    func export(_ p: HSProduction, scope: HSExportScope, format: StudioFormat, bitrate: Int, metadata meta: StudioMetadata, to dir: URL,
                progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        let items = HSExportPlan.items(for: p, scope: scope)
        var options = ExportOptions.defaults(for: format)
        options.mp3Bitrate = bitrate
        var files: [URL] = []
        for item in items {
            var m = meta
            m.title = scope == .whole ? (meta.title.isEmpty ? p.title : meta.title) : item.title
            m.trackNumber = item.trackNumber
            let out = dir.appendingPathComponent(item.fileName).appendingPathExtension(format.fileExtension)
            let req = ExportRequest(input: file(item.source, in: p), trim: item.trim, options: options, metadata: m, output: out)
            let base = Double(files.count) / Double(items.count)
            let count = Double(items.count)
            let r = try await AudioExporter().export(req, pause: nil) { v in progress(base + v / count) }
            if scope == .whole, ChapterWriter.supportedExtensions.contains(format.fileExtension) {
                try ChapterWriter.write(HSExportSheet.chapterMarks(p), total: r.duration, to: r.output)
            }
            files.append(r.output)
        }
        update(p.id) { $0.set(.export, .done) }
        return files
    }
}
