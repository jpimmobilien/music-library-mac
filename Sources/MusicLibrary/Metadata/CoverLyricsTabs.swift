import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MLCore
import MLTags

// MARK: - Cover

/// Cover-Verwaltung: mehrere Bilder je Datei (Vorderseite, Rückseite, Booklet …), Hinzufügen per Dialog,
/// Drag & Drop oder Einfügen, Ersetzen, Entfernen, Exportieren, für das ganze Album übernehmen.
struct CoverTab: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    @ObservedObject var session: EditorSession
    @State private var targeted = false

    var body: some View {
        let pictures = session.pictures
        let selected = pictures.indices.contains(session.selectedPicture) ? pictures[session.selectedPicture] : nil
        let canStore = session.files.allSatisfy { $0.result?.supportsPictures ?? false }
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.artworkLarge, style: .continuous)
                        .fill(colors.fieldFill)
                    if let selected, let img = NSImage(data: selected.data) {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.artworkLarge, style: .continuous))
                    } else if session.picturesMixed {
                        VStack(spacing: 6) {
                            Icon(Icons.photoLibrary, size: 34, color: colors.textTertiary)
                            Text("Die ausgewählten Titel haben unterschiedliche Cover.")
                                .textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).multilineTextAlignment(.center)
                        }
                        .padding(20)
                    } else {
                        VStack(spacing: 6) {
                            Icon(Icons.image, size: 34, color: colors.textTertiary)
                            Text("Kein Cover").textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary)
                        }
                    }
                }
                .frame(width: 300, height: 300)
                .shadow(color: .black.opacity(selected == nil ? 0 : 0.2), radius: 16, y: 8)
                if let selected {
                    let info = ImageProbe.info(data: selected.data)
                    Text([selected.kind.label, info.map { "\($0.width) × \($0.height) px" }, info?.format, Formatting.fileSize(Int64(selected.data.count))].compactMap { $0 }.joined(separator: " · "))
                        .textStyle(Typo.labelMedium)
                        .foregroundColor(colors.textSecondary)
                    Picker("Art", selection: Binding(get: { selected.kind }, set: { session.setKind($0, at: session.selectedPicture) })) {
                        ForEach(PictureKind.editable, id: \.self) { k in Text(k.label).tag(k) }
                    }
                    .frame(width: 300)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("BILDER IN \(session.isMulti ? "DEN DATEIEN" : "DIESER DATEI")")
                    .textStyle(Typo.sectionLabel)
                    .foregroundColor(colors.textSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(pictures.enumerated()), id: \.offset) { i, p in
                            VStack(spacing: 5) {
                                Group {
                                    if let img = NSImage(data: p.data) {
                                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                                    } else {
                                        colors.fieldFill
                                    }
                                }
                                .frame(width: 74, height: 74)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(i == session.selectedPicture ? colors.accent : colors.artworkStroke, lineWidth: i == session.selectedPicture ? 2.5 : 0.6))
                                Text(p.kind.label).textStyle(Typo.labelSmall).foregroundColor(colors.textSecondary).lineLimit(1)
                            }
                            .frame(width: 80)
                            .onTapGesture { session.selectedPicture = i }
                        }
                        Button { addFromPanel() } label: {
                            VStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(colors.textTertiary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                    .frame(width: 74, height: 74)
                                    .overlay(Icon(Icons.add, size: 22, color: colors.textSecondary))
                                Text("weiteres").textStyle(Typo.labelSmall).foregroundColor(colors.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(2)
                }
                VStack(spacing: 4) {
                    Text("Bild hierher ziehen").textStyle(Typo.titleSmall).foregroundColor(colors.accentText)
                    Text("oder einfügen (⌘V) – JPEG, PNG, HEIC, WebP, TIFF. HEIC, WebP und TIFF werden beim Einbetten in JPEG umgewandelt.")
                        .textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).multilineTextAlignment(.center)
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(targeted ? colors.accentSoft.opacity(2) : colors.accentSoft.opacity(0.6)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(colors.accent, style: StrokeStyle(lineWidth: targeted ? 2.5 : 1.5, dash: [7, 5])))
                .onDrop(of: [UTType.image, UTType.fileURL], isTargeted: $targeted) { providers in
                    model.metadata.loadDroppedImages(providers) { pics in for p in pics { session.addPicture(p) } }
                    return true
                }
                // In einer Zeile, wenn Platz ist – sonst zwei Zeilen (keine abgeschnittenen Beschriftungen)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        addButton
                        replaceButton(selected)
                        removeButton(selected)
                        exportButton(selected)
                    }
                    .fixedSize()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            addButton
                            replaceButton(selected)
                        }
                        .fixedSize()
                        HStack(spacing: 8) {
                            removeButton(selected)
                            exportButton(selected)
                        }
                        .fixedSize()
                    }
                }
                PillButton(title: "Aus Zwischenablage einfügen", icon: Icons.paste, style: .plain) {
                    if let pic = model.metadata.pictureFromPasteboard(downscale: session.downscaleLargeImages) { session.addPicture(pic) }
                }
                .keyboardShortcut("v", modifiers: .command)
                Toggle(isOn: $session.applyCoverToAlbum) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Für alle Titel des Albums übernehmen").textStyle(Typo.bodySmall)
                        if let album = session.files.first.flatMap({ model.index.albumOf($0.track.uid) }) {
                            Text("„\(album.title ?? "Album")“ – \(Formatting.tracks(album.trackCount))").textStyle(Typo.labelSmall).foregroundColor(colors.textTertiary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(!session.picturesDirty)
                Toggle("Sehr große Bilder vor dem Einbetten verkleinern (längste Seite 3000 px)", isOn: $session.downscaleLargeImages)
                    .toggleStyle(.checkbox)
                    .font(Typo.inter(12, .regular))
                if !canStore {
                    Text("Mindestens ein Dateiformat kann kein Cover speichern. Für diese Titel wird das Cover nur in der Bibliothek gespeichert.")
                        .textStyle(Typo.labelSmall).foregroundColor(colors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Glaskarte wie die Feldgruppen der übrigen Reiter
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .padding(.bottom, 14)
    }

    private var addButton: some View {
        PillButton(title: "Hinzufügen …", icon: Icons.add) { addFromPanel() }
    }

    private func replaceButton(_ selected: EmbeddedPicture?) -> some View {
        PillButton(title: "Ersetzen …") { replaceFromPanel() }.disabled(selected == nil)
    }

    private func removeButton(_ selected: EmbeddedPicture?) -> some View {
        PillButton(title: "Entfernen", style: .plain) { session.removeSelectedPicture() }.disabled(selected == nil)
    }

    private func exportButton(_ selected: EmbeddedPicture?) -> some View {
        PillButton(title: "Exportieren …", icon: Icons.fileExport) {
            if let selected { model.metadata.export(selected, suggestedName: session.files.first?.track.album ?? "Cover") }
        }
        .disabled(selected == nil)
    }

    private func addFromPanel() {
        for p in model.metadata.chooseImages(downscale: session.downscaleLargeImages) { session.addPicture(p) }
    }

    private func replaceFromPanel() {
        if let p = model.metadata.chooseImages(downscale: session.downscaleLargeImages, multiple: false).first { session.replaceSelectedPicture(p) }
    }
}

// MARK: - Liedtext

/// Liedtext bearbeiten – unsynchronisiert oder synchronisiert (LRC). Synchronisieren: Titel abspielen und bei
/// jeder Zeile „Zeitmarke setzen“ (⌘T) drücken.
struct LyricsTab: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    @ObservedObject var session: EditorSession
    @State private var syncLine = 0

    var body: some View {
        let text = session.value(.lyrics)
        let parsed = LyricsParser.parse(text)
        let single = session.files.count == 1
        VStack(alignment: .leading, spacing: 12) {
            if !single {
                EmptyStateView(icon: Icons.lyrics, title: "Liedtexte einzeln bearbeiten", text: "Liedtexte gehören zu genau einem Titel. Öffne die Informationen eines einzelnen Titels.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(parsed.isSynced ? "Synchronisiert · \(parsed.lines.count) Zeilen" : (text.isEmpty ? "Kein Liedtext" : "Nicht synchronisiert"))
                            .textStyle(Typo.labelMedium)
                            .foregroundColor(parsed.isSynced ? colors.accentText : colors.textSecondary)
                        Spacer()
                        PillButton(title: "Laden …", icon: Icons.folderOpen, style: .plain) { importLRC() }
                        PillButton(title: "Als .lrc sichern …", icon: Icons.fileExport, style: .plain) { exportLRC(text) }
                            .disabled(text.isEmpty)
                    }
                    TextEditor(text: session.binding(.lyrics))
                        .font(Typo.inter(13.5, .regular))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 300)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors.fieldFill))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(session.dirty.contains(.lyrics) ? colors.accent : .clear, lineWidth: 1.6))
                }
                // Glaskarte wie die Feldgruppen der übrigen Reiter
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                EditorCard(title: "Synchronisieren") {
                    Text("Spiele den Titel ab und setze bei Beginn jeder Zeile eine Zeitmarke. Vorhandene Zeitmarken werden ersetzt.")
                        .textStyle(Typo.bodySmall)
                        .foregroundColor(colors.textSecondary)
                    HStack(spacing: 8) {
                        PillButton(title: player.isPlaying && player.current?.uid == session.uids.first ? "Pause" : "Titel abspielen", icon: player.isPlaying ? Icons.pause : Icons.play) {
                            if let uid = session.uids.first {
                                if player.current?.uid == uid { player.togglePlay() } else {
                                    player.play(uids: [uid], startIndex: 0, shuffle: .off, source: PlaybackSource(kind: .singleTrack, label: "Liedtext"))
                                    syncLine = 0
                                }
                            }
                        }
                        PillButton(title: "Zeitmarke setzen (Zeile \(syncLine + 1))", icon: Icons.timer, style: .filled) { stamp() }
                            .keyboardShortcut("t", modifiers: .command)
                            .disabled(player.current?.uid != session.uids.first)
                        PillButton(title: "Von vorn", style: .plain) { syncLine = 0 }
                        PillButton(title: "Zeitmarken entfernen", style: .plain) {
                            session.set(.lyrics, parsed.isSynced ? parsed.lines.map(\.text).joined(separator: "\n") : text)
                        }
                        .disabled(!parsed.isSynced)
                    }
                }
            }
        }
    }

    /// Setzt für die nächste Zeile die aktuelle Wiedergabeposition.
    private func stamp() {
        var lines = session.value(.lyrics).components(separatedBy: "\n")
        guard !lines.isEmpty else { return }
        // Leere Zeilen und reine Metadaten-Zeilen überspringen
        while syncLine < lines.count, lines[syncLine].trimmingCharacters(in: .whitespaces).isEmpty { syncLine += 1 }
        guard syncLine < lines.count else { return }
        let ms = player.positionMs
        let stripped = lines[syncLine].replacingOccurrences(of: #"^(\[\d{1,3}:\d{2}([.:]\d{1,3})?\])+"#, with: "", options: .regularExpression)
        let m = Int(ms / 60_000), s = Int((ms / 1000) % 60), cs = Int((ms % 1000) / 10)
        lines[syncLine] = String(format: "[%02ld:%02ld.%02ld]", m, s, cs) + stripped
        session.set(.lyrics, lines.joined(separator: "\n"))
        syncLine += 1
    }

    private func importLRC() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .plainText, .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        session.set(.lyrics, text)
    }

    private func exportLRC(_ text: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .plainText]
        let name = session.files.first.map { Track.fileNameWithoutExtension($0.track.fileName) } ?? "Liedtext"
        panel.nameFieldStringValue = name + ".lrc"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? text.data(using: .utf8)?.write(to: url, options: .atomic)
    }
}
