import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MLCore
import MLStore
import MLStudio

// Audio Studio – Export: Format und Qualität (sechs Formate mit passenden Reglern und ehrlichen Hinweisen),
// Metadaten mit Cover-Ablage, Dateiname mit Live-Vorschau, Ziel (Musikbibliothek oder Ordner), beim Schneiden
// „Als neue Datei“ / „Original ersetzen“, Exportleiste mit Doppel-Warnung.

// MARK: - Format und Qualität

struct StudioFormatCard: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        let keep = studio.isLibraryTrack && studio.keepOriginalFormat && studio.originalFormat != nil
        StudioCard(icon: Icons.tune, title: "Format und Qualität", subtitle: keep ? "Wie das Original" : studio.options.summary(sourceRate: studio.source?.sampleRate)) {
            VStack(alignment: .leading, spacing: 16) {
                if studio.isLibraryTrack { keepOriginalRow }
                if !keep {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 3), alignment: .leading, spacing: 8) {
                        ForEach(StudioFormat.allCases, id: \.self) { f in
                            StudioFormatTile(format: f, selected: studio.options.format == f) {
                                withAnimation(Motion.easeOut(Motion.short)) { studio.setFormat(f) }
                            }
                        }
                    }
                    StudioQualityControls(studio: studio)
                }
                let notes = keep ? [] : studio.qualityNotes
                if !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(notes, id: \.self) { StudioInfoLine(text: $0) }
                    }
                    .transition(.opacity)
                }
            }
            .animation(Motion.easeOut(Motion.short), value: studio.options.format)
        }
    }

    private var keepOriginalRow: some View {
        let original = studio.originalFormat
        let ext = (studio.source?.localFile ?? studio.source?.url)?.pathExtension.uppercased() ?? ""
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Format wie Original")
                        .textStyle(Typo.bodyLarge)
                        .foregroundColor(colors.textPrimary)
                    if let badge = studio.passthroughBadge {
                        StudioBadge(text: badge, icon: Icons.check, tint: colors.accentText)
                    }
                }
                Text(original != nil
                     ? "\(ext.isEmpty ? (original?.label ?? "") : ext) mit gleicher Qualität. Tags, Cover und Liedtexte bleiben erhalten\(studio.fadeIn > 0 || studio.fadeOut > 0 ? " – Blenden erfordern eine Neukodierung." : ".")"
                     : "„\(ext)“ kann nicht geschrieben werden – bitte ein Zielformat wählen.")
                    .textStyle(Typo.bodySmall)
                    .foregroundColor(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            MusicToggle(isOn: Binding(get: { studio.keepOriginalFormat && original != nil }, set: { studio.keepOriginalFormat = $0 }), label: "Format wie Original")
                .disabled(original == nil)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(colors.textPrimary.opacity(colors.dark ? 0.05 : 0.03)))
    }
}

/// Glas-Kapsel eines Formats mit Kurzbeschreibung.
struct StudioFormatTile: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.isEnabled) private var enabled
    let format: StudioFormat
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(format.label)
                        .font(Typo.inter(15, .bold))
                        .foregroundColor(selected ? colors.accentText : colors.textPrimary)
                    if format.isLossless {
                        Text("verlustfrei")
                            .font(Typo.inter(9.5, .semibold))
                            .foregroundColor(colors.textTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(colors.textPrimary.opacity(0.06)))
                    }
                    Spacer(minLength: 0)
                    ZStack {
                        Circle().strokeBorder(selected ? colors.accent : colors.textTertiary.opacity(0.45), lineWidth: 1.4)
                        if selected { Icon(Icons.check, size: 11, color: colors.onAccent).frame(width: 16, height: 16).background(Circle().fill(colors.accent)) }
                    }
                    .frame(width: 16, height: 16)
                }
                Text(format.summary)
                    .textStyle(Typo.labelSmall)
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
            .background(shape.fill(selected ? colors.accentSoft : colors.textPrimary.opacity(hover && enabled ? (colors.dark ? 0.08 : 0.05) : (colors.dark ? 0.045 : 0.025))))
            .overlay(shape.strokeBorder(selected ? colors.accent.opacity(0.6) : colors.hairline, lineWidth: selected ? 1.5 : 1))
            .contentShape(shape)
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
        .onHover { hover = $0 }
        .accessibilityLabel("\(format.label): \(format.summary)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Regler je Format (Bitrate, Bittiefe, Abtastrate, FLAC-Stufe, Mono).
struct StudioQualityControls: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        let o = studio.options
        VStack(alignment: .leading, spacing: 14) {
            switch o.format {
            case .mp3:
                StudioChoiceRow(label: "Bitrate (kbit/s, konstant)", options: ExportOptions.mp3Bitrates, selected: o.mp3Bitrate,
                                title: { "\($0)" }) { v in studio.updateOptions { $0.mp3Bitrate = v } }
            case .aac, .m4a:
                StudioChoiceRow(label: "Bitrate (kbit/s)", options: ExportOptions.aacBitrates, selected: o.aacBitrate,
                                title: { "\($0)" }) { v in studio.updateOptions { $0.aacBitrate = v } }
            case .wav, .aiff:
                StudioChoiceRow(label: "Bittiefe", options: PCMDepth.allCases, selected: o.pcmDepth, title: { $0.label }) { v in
                    studio.updateOptions { $0.pcmDepth = v }
                }
            case .flac:
                flacControls(o)
            }
            StudioChoiceRow(label: "Abtastrate", options: o.format.sampleRateChoices.map { RateChoice(hz: $0) }, selected: RateChoice(hz: o.sampleRate),
                            title: { rateTitle($0.hz) }) { v in studio.updateOptions { $0.sampleRate = v.hz } }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mono-Quellen mono lassen")
                        .textStyle(Typo.bodyMedium)
                        .foregroundColor(colors.textPrimary)
                    Text("Mehr als zwei Kanäle werden immer auf Stereo heruntergemischt.")
                        .textStyle(Typo.labelSmall)
                        .foregroundColor(colors.textTertiary)
                }
                Spacer(minLength: 8)
                MusicToggle(isOn: Binding(get: { studio.options.keepMono }, set: { v in studio.updateOptions { $0.keepMono = v } }), label: "Mono-Quellen mono lassen")
            }
        }
    }

    @ViewBuilder
    private func flacControls(_ o: ExportOptions) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Kompression")
                    .textStyle(Typo.labelMedium)
                    .foregroundColor(colors.textSecondary)
                Spacer()
                Text("Stufe \(o.flacLevel)\(o.flacLevel == 5 ? " (Standard)" : "")")
                    .font(Typo.inter(12, .semibold))
                    .monospacedDigit()
                    .foregroundColor(colors.textPrimary)
            }
            MusicSlider(value: Binding(get: { Double(studio.options.flacLevel) }, set: { v in
                let level = Int(v.rounded())
                if level != studio.options.flacLevel { studio.updateOptions { $0.flacLevel = level } }
            }), range: 0...8, showsKnob: true, step: 1, label: "FLAC-Kompressionsstufe", valueText: "Stufe \(o.flacLevel)")
            HStack {
                Text("schneller")
                Spacer()
                Text("kleiner")
            }
            .textStyle(Typo.labelSmall)
            .foregroundColor(colors.textTertiary)
            Text("Alle Stufen sind verlustfrei – höhere Stufen sparen etwas Platz und brauchen länger.")
                .textStyle(Typo.labelSmall)
                .foregroundColor(colors.textTertiary)
        }
        .frame(maxWidth: 420)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bittiefe wie Quelle")
                    .textStyle(Typo.bodyMedium)
                    .foregroundColor(colors.textPrimary)
                Text(studio.source?.bitDepth.map { "Quelle: \($0) Bit → \($0 <= 16 ? 16 : 24) Bit" } ?? "16 Bit bleiben 16 Bit, mehr wird zu 24 Bit.")
                    .textStyle(Typo.labelSmall)
                    .foregroundColor(colors.textTertiary)
            }
            Spacer(minLength: 8)
            MusicToggle(isOn: Binding(get: { studio.options.flacKeepSourceDepth }, set: { v in studio.updateOptions { $0.flacKeepSourceDepth = v } }), label: "Bittiefe wie Quelle")
        }
        if !o.flacKeepSourceDepth {
            StudioChoiceRow(label: "Bittiefe", options: [PCMDepth.int16, PCMDepth.int24], selected: o.pcmDepth == .int16 ? .int16 : .int24, title: { $0.label }) { v in
                studio.updateOptions { $0.pcmDepth = v }
            }
        }
    }

    private func rateTitle(_ hz: Int?) -> String {
        guard let hz else {
            if let src = studio.source?.sampleRate, src > 0 {
                // Was „wie Quelle“ ergibt (MP3/AAC können nicht jede Rate – dann die nächstpassende)
                var o = studio.options
                o.sampleRate = nil
                return "Wie Quelle (\(ExportOptions.rateLabel(o.outputSampleRate(sourceRate: src))))"
            }
            return "Wie Quelle"
        }
        return ExportOptions.rateLabel(hz)
    }

    /// Hashbarer Wrapper für „Abtastrate oder Original“.
    struct RateChoice: Hashable { let hz: Int? }
}

// MARK: - Metadaten

struct StudioMetadataCard: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    let compact: Bool

    var body: some View {
        let tags = studio.isLibraryTrack && studio.keepOriginalFormat ? (studio.originalFormat?.supportsTags ?? true) : studio.options.format.supportsTags
        StudioCard(icon: Icons.label, title: "Metadaten", subtitle: tags ? (studio.isLibraryTrack ? "Tags des Originals bleiben, Änderungen kommen dazu" : "Werden in die Datei geschrieben") : "AAC-Rohdaten können keine Tags speichern") {
            if let suggested = studio.source?.suggested, !suggested.isEmpty, Self.differs(suggested, studio.metadata) {
                IconTap(icon: Icons.restart, label: "Vorschlag der Quelle wiederherstellen", tint: colors.textSecondary, iconSize: 17, touch: 30) {
                    var m = suggested
                    if m.cover == nil { m.cover = studio.metadata.cover }
                    studio.metadata = m
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                if compact {
                    VStack(alignment: .leading, spacing: 14) {
                        StudioCoverWell(studio: studio)
                        fields
                    }
                } else {
                    HStack(alignment: .top, spacing: 18) {
                        StudioCoverWell(studio: studio)
                        fields
                    }
                }
                Hairline()
                StudioFileNameSection(studio: studio)
            }
            .opacity(tags ? 1 : 0.55)
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 10) {
            StudioLabeledField(label: "Titel") {
                StudioTextField(label: "Titel", text: $studio.metadata.title, placeholder: studio.source?.title ?? "Titel")
            }
            StudioLabeledField(label: "Interpret") {
                StudioTextField(label: "Interpret", text: $studio.metadata.artist, placeholder: "Interpret")
            }
            StudioLabeledField(label: "Album") {
                StudioTextField(label: "Album", text: $studio.metadata.album, placeholder: "Album")
            }
            HStack(alignment: .top, spacing: 10) {
                StudioLabeledField(label: "Jahr") {
                    StudioTextField(label: "Jahr", text: numberBinding(\.year, digits: 4), placeholder: "–", width: 72)
                }
                StudioLabeledField(label: "Nr.") {
                    StudioTextField(label: "Titelnummer", text: numberBinding(\.trackNumber, digits: 3), placeholder: "–", width: 56)
                }
                StudioLabeledField(label: "Genre") {
                    StudioTextField(label: "Genre", text: $studio.metadata.genre, placeholder: "Genre")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Felder geändert (das Cover zählt nicht – es wird oft aus dem Vorschaubild übernommen).
    static func differs(_ a: StudioMetadata, _ b: StudioMetadata) -> Bool {
        var x = a
        var y = b
        x.cover = nil
        y.cover = nil
        return x != y
    }

    private func numberBinding(_ key: WritableKeyPath<StudioMetadata, Int?>, digits: Int) -> Binding<String> {
        Binding(get: { studio.metadata[keyPath: key].map(String.init) ?? "" },
                set: { text in
                    let n = String(text.filter(\.isNumber).prefix(digits))
                    studio.metadata[keyPath: key] = Int(n).flatMap { $0 > 0 ? $0 : nil }
                })
    }
}

/// Cover-Ablage: Ziehen, Einfügen, Datei wählen, Vorschaubild verwenden, Entfernen.
struct StudioCoverWell: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    @State private var targeted = false

    var body: some View {
        let cover = studio.metadata.cover
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(spacing: 6) {
            ZStack {
                shape.fill(colors.fieldFill)
                if let image = StudioImages.image(cover, key: "metadata-cover") {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 136, height: 136)
                        .clipped()
                } else if let uid = studio.source?.libraryUid, let track = model.track(uid), track.hasPicture {
                    // Schneiden: Das Cover des Originals bleibt erhalten, solange kein neues gewählt wird
                    TrackArtwork(track: track, size: .medium, cornerRadius: 12)
                        .frame(width: 136, height: 136)
                        .overlay(alignment: .bottom) {
                            Text("Cover des Originals")
                                .font(Typo.inter(10, .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .frame(height: 20)
                                .background(Capsule().fill(Color.black.opacity(0.45)))
                                .padding(.bottom, 8)
                        }
                } else {
                    VStack(spacing: 6) {
                        Icon(Icons.image, size: 26, color: targeted ? colors.accentText : colors.textTertiary)
                        Text("Cover hierher ziehen")
                            .textStyle(Typo.labelSmall)
                            .foregroundColor(colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(10)
                }
                if targeted {
                    shape.fill(colors.accentSoft)
                }
            }
            .frame(width: 136, height: 136)
            .clipShape(shape)
            .overlay(
                Group {
                    if (cover == nil && studio.source?.libraryUid == nil) || targeted {
                        shape.strokeBorder(targeted ? colors.accent : colors.textTertiary.opacity(0.45), style: StrokeStyle(lineWidth: targeted ? 2 : 1.2, dash: [5, 4]))
                    } else {
                        shape.strokeBorder(colors.artworkStroke, lineWidth: 0.6)
                    }
                }
            )
            .shadow(color: Color.black.opacity(cover == nil ? 0 : (colors.dark ? 0.35 : 0.16)), radius: 10, y: 4)
            .onDrop(of: [UTType.image, UTType.fileURL], isTargeted: $targeted) { providers in
                model.metadata.loadDroppedImages(providers) { pics in
                    if let p = pics.first { studio.metadata.cover = p.data }
                }
                return true
            }
            .animation(Motion.easeOut(Motion.short), value: targeted)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(cover == nil ? "Kein Cover. Bild hierher ziehen." : "Cover")
            HStack(spacing: 0) {
                IconTap(icon: Icons.folderOpen, label: "Bild wählen …", tint: colors.textSecondary, iconSize: 16, touch: 28) {
                    if let p = model.metadata.chooseImages(downscale: true, multiple: false).first { studio.metadata.cover = p.data }
                }
                IconTap(icon: Icons.paste, label: "Bild aus der Zwischenablage einfügen", tint: colors.textSecondary, iconSize: 16, touch: 28) {
                    if let p = model.metadata.pictureFromPasteboard(downscale: true) {
                        studio.metadata.cover = p.data
                    } else {
                        model.toast("In der Zwischenablage ist kein Bild.")
                    }
                }
                IconTap(icon: Icons.photoLibrary, label: "Vorschaubild der Quelle verwenden (quadratisch zugeschnitten)", tint: colors.textSecondary, iconSize: 16, touch: 28) {
                    if let thumb = studio.source?.thumbnail { studio.metadata.cover = StudioImages.squareCover(from: thumb) ?? thumb }
                }
                .disabled(studio.source?.thumbnail == nil)
                IconTap(icon: Icons.delete, label: "Cover entfernen", tint: colors.textSecondary, iconSize: 16, touch: 28) {
                    studio.metadata.cover = nil
                }
                .disabled(cover == nil)
            }
        }
        .frame(width: 136)
    }
}

/// Dateiname: Schema und Live-Vorschau.
struct StudioFileNameSection: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(studio.replacesOriginal ? "Dateiname" : "Dateiname")
                .textStyle(Typo.labelMedium)
                .foregroundColor(colors.textSecondary)
            if studio.replacesOriginal {
                preview(name: (studio.source?.localFile ?? studio.source?.url)?.lastPathComponent ?? studio.fileNamePreview, note: "bleibt unverändert")
            } else {
                StudioFlow(spacing: 6) {
                    ForEach(FileNameScheme.presets, id: \.self) { s in
                        ChoiceChip(title: s.label, selected: !studio.isCustomScheme && studio.settings.fileNameScheme == s) {
                            studio.settings.fileNameScheme = s
                        }
                    }
                    ChoiceChip(title: "Eigener Name", selected: studio.isCustomScheme) {
                        if studio.customFileName.trimmingCharacters(in: .whitespaces).isEmpty { studio.customFileName = studio.fileNameBase }
                        studio.settings.fileNameScheme = .custom(studio.customFileName)
                    }
                }
                if studio.isCustomScheme {
                    StudioTextField(label: "Eigener Dateiname", text: $studio.customFileName, placeholder: "Dateiname ohne Endung")
                        .transition(.opacity)
                }
                preview(name: studio.fileNamePreview, note: nil)
            }
        }
        .animation(Motion.easeOut(Motion.short), value: studio.isCustomScheme)
    }

    private func preview(name: String, note: String?) -> some View {
        HStack(spacing: 8) {
            Icon(Icons.audioFile, size: 15, color: colors.accentText)
            Text(name)
                .font(Typo.inter(13, .medium))
                .foregroundColor(colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            if let note {
                Text(note)
                    .textStyle(Typo.labelSmall)
                    .foregroundColor(colors.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(colors.accentSoft.opacity(0.7)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vorschau des Dateinamens: \(name)")
    }
}

// MARK: - Ziel

struct StudioDestinationCard: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    let compact: Bool

    var body: some View {
        if studio.isLibraryTrack {
            cutCard
        } else {
            exportCard
        }
    }

    // Schneiden vorhandener Songs
    private var cutCard: some View {
        let dest = studio.shownDestination
        return StudioCard(icon: Icons.save, title: "Speichern", subtitle: dest.title) {
            VStack(alignment: .leading, spacing: 12) {
                let tiles = Group {
                    StudioOptionTile(icon: Icons.newFile, title: "Als neue Datei",
                                     text: studio.mode == .edit
                                        ? "Die bearbeitete Fassung wird neben dem Original gespeichert und in die Bibliothek aufgenommen. Das Original bleibt unverändert."
                                        : "Der Ausschnitt wird neben dem Original gespeichert und in die Bibliothek aufgenommen. Das Original bleibt unverändert.",
                                     selected: studio.cutSaveMode == .newFile) { studio.cutSaveMode = .newFile }
                    StudioOptionTile(icon: Icons.swap, title: "Original ersetzen",
                                     text: "Vorher wird eine Sicherung angelegt – im Verlauf lässt sich das rückgängig machen. Favoriten, Playlists und Statistik bleiben am Titel.",
                                     selected: studio.cutSaveMode == .replaceOriginal, destructive: true) { studio.cutSaveMode = .replaceOriginal }
                }
                if compact {
                    VStack(spacing: 10) { tiles }
                } else {
                    HStack(alignment: .top, spacing: 10) { tiles }
                }
                if let path = dest.path { pathLine(path) }
                if studio.cutSaveMode == .newFile { revealRow }
            }
        }
    }

    // Laden und Umwandeln
    private var exportCard: some View {
        let dest = studio.shownDestination
        return StudioCard(icon: Icons.folder, title: "Ziel", subtitle: dest.title) {
            VStack(alignment: .leading, spacing: 14) {
                SegmentedControl(options: [true, false], selection: $studio.settings.importToLibrary,
                                 label: { $0 ? "In die Musikbibliothek" : "Nur speichern" },
                                 icon: { $0 ? Icons.libraryMusic : Icons.folder }, height: 32)
                    .frame(maxWidth: 440)
                if studio.settings.importToLibrary {
                    libraryTarget
                } else {
                    folderTarget
                }
                revealRow
            }
            .animation(Motion.easeOut(Motion.short), value: studio.settings.importToLibrary)
        }
    }

    @ViewBuilder
    private var libraryTarget: some View {
        if let folder = studio.libraryFolder {
            HStack(alignment: .bottom, spacing: 10) {
                StudioLabeledField(label: "Musikordner") {
                    GlassMenuButton(help: "Musikordner wählen", width: 300) {
                        HStack(spacing: 7) {
                            Icon(Icons.libraryMusic, size: 15, color: colors.accentText)
                            Text(folder.name)
                                .font(Typo.inter(13, .medium))
                                .foregroundColor(colors.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Icon(Icons.unfoldMore, size: 14, color: colors.textTertiary)
                        }
                        .padding(.horizontal, 10)
                        .frame(minWidth: 170, maxWidth: 240, minHeight: 30)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(colors.fieldFill))
                        .contentShape(Rectangle())
                    } content: { menu in
                        GlassMenuHeader(title: "Musikordner")
                        ForEach(model.folders, id: \.id) { f in
                            GlassMenuItem(title: f.name, checked: f.id == folder.id, detail: StudioText.abbreviated(f.path)) {
                                studio.settings.libraryFolderID = f.id
                                menu.close()
                            }
                        }
                        GlassMenuDivider()
                        GlassMenuItem(title: "Musikordner hinzufügen …", icon: Icons.add) {
                            menu.close()
                            model.library.chooseFolders()
                        }
                    }
                }
                StudioLabeledField(label: "Unterordner") {
                    StudioTextField(label: "Unterordner", text: $studio.settings.librarySubfolder, placeholder: "direkt im Musikordner")
                        .frame(maxWidth: 260)
                }
            }
            if let path = studio.shownDestination.path { pathLine(path) }
            StudioInfoLine(text: "Die Datei wird dort gespeichert und sofort in die Bibliothek aufgenommen – mit Hinzufügedatum, Tags und Cover.")
        } else {
            StudioNotice(icon: Icons.folder, title: "Noch kein Musikordner",
                         text: "Füge einen Musikordner hinzu – fertige Dateien werden dort abgelegt und automatisch eingelesen. Oder wähle „Nur speichern“.") {
                PillButton(title: "Musikordner hinzufügen …", icon: Icons.add, style: .filled) { model.library.chooseFolders() }
            }
        }
    }

    private var folderTarget: some View {
        let path = studio.settings.saveFolderPath ?? StudioModel.defaultSaveFolder
        return HStack(spacing: 10) {
            pathLine(path)
            PillButton(title: "Ordner wählen …", icon: Icons.folderOpen) { chooseFolder() }
                .fixedSize()
        }
    }

    private var revealRow: some View {
        HStack(spacing: 12) {
            Text("Nach dem Export im Finder zeigen")
                .textStyle(Typo.bodyMedium)
                .foregroundColor(colors.textPrimary)
            Spacer(minLength: 8)
            MusicToggle(isOn: $studio.settings.revealAfterExport, label: "Nach dem Export im Finder zeigen")
        }
    }

    private func pathLine(_ path: String) -> some View {
        HStack(spacing: 8) {
            Icon(Icons.folder, size: 15, color: colors.textSecondary)
            Text(StudioText.abbreviated(path))
                .font(Typo.inter(12.5, .regular))
                .foregroundColor(colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.head)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(colors.fieldFill))
        .help(path)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Ordner für fertige Dateien"
        panel.prompt = "Wählen"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let current = studio.settings.saveFolderPath { panel.directoryURL = URL(fileURLWithPath: current) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        studio.settings.saveFolderPath = url.path
    }
}

// MARK: - Exportleiste

/// Schwebende Glasleiste: Dateiname, Zusammenfassung, Ziel und „Exportieren“ (mit Doppel-Warnung).
struct StudioExportBar: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    @Binding var askDuplicates: Bool
    let export: () -> Void
    let proceed: () -> Void

    var body: some View {
        let dups = studio.shownDuplicates
        let previous = studio.previousExport
        let warn = !studio.replacesOriginal && (!dups.isEmpty || previous != nil)
        VStack(spacing: 10) {
            if askDuplicates && warn {
                StudioDuplicateBanner(duplicates: dups, previous: previous, reveal: { studio.revealInFinder($0) },
                                      cancel: { withAnimation(Motion.easeOut()) { askDuplicates = false } },
                                      proceed: proceed)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 12) {
                StudioArtwork(source: studio.source, cover: studio.metadata.cover, key: "bar", cornerRadius: 8)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(studio.replacesOriginal ? ((studio.source?.localFile ?? studio.source?.url)?.lastPathComponent ?? "Original") : studio.fileNamePreview)
                        .textStyle(Typo.titleSmall)
                        .foregroundColor(colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(summary)
                        .textStyle(Typo.labelMedium)
                        .monospacedDigit()
                        .foregroundColor(colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if warn && !askDuplicates {
                    Button { withAnimation(Motion.easeOut()) { askDuplicates = true } } label: {
                        StudioBadge(text: "Schon vorhanden?", icon: Icons.warning, tint: colors.accentText)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Möglicherweise liegt diese Aufnahme schon in der Bibliothek")
                }
                PillButton(title: studio.replacesOriginal ? "Original ersetzen …" : "Exportieren",
                           icon: studio.replacesOriginal ? Icons.swap : Icons.download, style: .filled, minWidth: 150, action: export)
                    .disabled(!studio.exportEnabled)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help(studio.exportEnabled ? "Als Auftrag in die Warteschlange (⌘↩) – er startet automatisch." : studio.exportBlockedReason)
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .glassSurface(RoundedRectangle(cornerRadius: Radius.bar - 6, style: .continuous), strong: true, elevated: true)
        }
        .animation(Motion.easeOut(), value: askDuplicates)
    }

    private var summary: String {
        var parts: [String] = []
        if studio.isLibraryTrack && studio.keepOriginalFormat && studio.originalFormat != nil {
            parts.append("Format wie Original" + (studio.passthroughBadge.map { " · \($0)" } ?? ""))
        } else {
            parts.append(studio.options.summary(sourceRate: studio.source?.sampleRate))
        }
        if studio.exportWholeFile {
            if let d = StudioText.duration(studio.duration) { parts.append("ganze Datei \(d)") }
        } else {
            parts.append("Ausschnitt \(StudioTime.format(studio.shownSelection.length, millis: false))")
        }
        if studio.fadeIn > 0 || studio.fadeOut > 0 { parts.append("mit Blenden") }
        if let edit = studio.activeTrackEdit { parts.insert(edit.summary, at: 0) }
        parts.append("→ \(studio.shownDestination.title)")
        return parts.joined(separator: " · ")
    }
}

extension StudioModel {
    /// Exportieren möglich (im Vorschaumodus ohne echtes Ziel trotzdem aktiv dargestellt).
    var exportEnabled: Bool { canExport || (demo && showsEditor) }

    var exportBlockedReason: String {
        guard let source else { return "Zuerst eine Quelle wählen." }
        if !source.kind.supportsAudio { return "Spotify-Audio ist kopiergeschützt und kann nicht exportiert werden." }
        if source.isLive { return "Live-Übertragungen werden nicht unterstützt." }
        if sourceState != .ready { return "Die Quelle wird noch analysiert." }
        if settings.importToLibrary && libraryFolder == nil && !isLibraryTrack { return "Kein Musikordner – bitte einen hinzufügen oder „Nur speichern“ wählen." }
        return "Kein Ziel gewählt."
    }
}

/// Rückfrage bei möglichen Dubletten (gleicher Titel/Interpret/Dauer oder Quelle schon exportiert).
struct StudioDuplicateBanner: View {
    @Environment(\.musicColors) private var colors
    let duplicates: [DuplicateCheck.Candidate]
    let previous: StudioHistoryEntry?
    let reveal: (String) -> Void
    let cancel: () -> Void
    let proceed: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(colors.accentSoft)
                    .frame(width: 36, height: 36)
                    .overlay(Icon(Icons.warning, size: 19, color: colors.accentText))
                VStack(alignment: .leading, spacing: 4) {
                    Text(duplicates.isEmpty ? "Diese Quelle wurde schon exportiert" : "Möglicherweise schon in deiner Bibliothek")
                        .font(Typo.inter(14, .semibold))
                        .foregroundColor(colors.textPrimary)
                    Text(explanation)
                        .textStyle(Typo.bodySmall)
                        .foregroundColor(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if !duplicates.isEmpty {
                VStack(spacing: 4) {
                    ForEach(duplicates.prefix(3), id: \.uid) { c in
                        HStack(spacing: 10) {
                            Icon(Icons.musicNote, size: 14, color: colors.textTertiary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.artist.isEmpty ? c.title : "\(c.title) – \(c.artist)")
                                    .textStyle(Typo.bodyMedium)
                                    .foregroundColor(colors.textPrimary)
                                    .lineLimit(1)
                                Text("\(StudioTime.format(c.durationSeconds, millis: false)) · \(StudioText.abbreviated(c.path))")
                                    .textStyle(Typo.labelSmall)
                                    .monospacedDigit()
                                    .foregroundColor(colors.textTertiary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                            Spacer(minLength: 0)
                            IconTap(icon: Icons.folderOpen, label: "Im Finder zeigen", tint: colors.textSecondary, iconSize: 15, touch: 28) { reveal(c.path) }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(colors.textPrimary.opacity(colors.dark ? 0.05 : 0.03)))
                    }
                }
                .padding(.leading, 48)
            }
            HStack(spacing: 8) {
                Spacer()
                PillButton(title: "Abbrechen", action: cancel)
                    .keyboardShortcut(.cancelAction)
                PillButton(title: "Trotzdem exportieren", icon: Icons.download, style: .filled, action: proceed)
            }
        }
        .padding(14)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.card + 2, style: .continuous), strong: true, elevated: true)
    }

    private var explanation: String {
        if let first = duplicates.first {
            let more = duplicates.count > 1 ? " (und \(duplicates.count - 1) weitere)" : ""
            return "„\(first.title)“\(first.artist.isEmpty ? "" : " von \(first.artist)") mit gleicher Dauer liegt bereits in der Bibliothek\(more). Möchtest du trotzdem eine weitere Datei anlegen?"
        }
        if let previous {
            return "Am \(StudioText.relativeDate(previous.date)) als \(previous.formatSummary) gespeichert: \(StudioText.abbreviated(previous.outputPath)). Möchtest du sie erneut exportieren?"
        }
        return ""
    }
}
