import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MLCore
import MLTags

/// Informationsfenster (Metadaten, Cover, Liedtext, Sortierung, Datei) im Stil der App – Glaskarten,
/// Rosé-Akzente, Inter – statt des klassischen iTunes-Rasters.
struct EditorWindowRoot: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        Group {
            if model.editorUids.isEmpty {
                ZStack {
                    AmbientBackground()
                    EmptyStateView(icon: Icons.info, title: "Kein Titel ausgewählt", text: "Wähle in der Bibliothek einen oder mehrere Titel und drücke ⌘I.")
                }
            } else {
                EditorView(uids: model.editorUids)
                    .id(model.editorUids)
            }
        }
        .frame(minWidth: 680, idealWidth: 780, minHeight: 600, idealHeight: 760)
    }
}

struct EditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    @StateObject private var session: EditorSession
    @State private var saving = false
    @State private var headerImage: NSImage?

    init(uids: [Int64]) {
        _session = StateObject(wrappedValue: EditorSession(uids: uids))
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: 0) {
                header
                SegmentedControl(options: EditorTab.allCases, selection: $session.tab, label: { $0.label }, icon: { $0.icon })
                    .frame(maxWidth: 560)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                if session.loading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Group {
                            switch session.tab {
                            case .details: DetailsTab(session: session)
                            case .cover: CoverTab(session: session)
                            case .lyrics: LyricsTab(session: session)
                            case .sorting: SortingTab(session: session)
                            case .file: FileTab(session: session)
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                    }
                }
                footer
            }
        }
        .task {
            let tracks = model.tracks(session.uids)
            await session.load(tracks: tracks)
            if let t = model.metadata.requestedTab {
                session.tab = t
                model.metadata.requestedTab = nil
            }
            if let first = tracks.first { headerImage = await ArtworkStore.shared.image(for: first, size: .medium) }
        }
    }

    // MARK: Kopf

    private var header: some View {
        let tracks = session.files.map(\.track)
        let single = tracks.count == 1 ? tracks.first : nil
        return ZStack(alignment: .leading) {
            HeroBackdrop(image: headerImage)
                .frame(height: 150)
                .clipped()
            HStack(spacing: 20) {
                if let single {
                    TrackArtwork(track: single, size: .medium, cornerRadius: Radius.artwork)
                        .frame(width: 104, height: 104)
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                } else {
                    ZStack {
                        ForEach(Array(tracks.prefix(4).enumerated()), id: \.offset) { i, t in
                            TrackArtwork(track: t, size: .small, cornerRadius: Radius.artworkSmall)
                                .frame(width: 84, height: 84)
                                .rotationEffect(.degrees(Double(i) * 5 - 8))
                                .offset(x: CGFloat(i) * 12, y: CGFloat(3 - i) * 2)
                                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                        }
                    }
                    .frame(width: 124, height: 104, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let single {
                        Text(single.displayTitle)
                            .textStyle(Typo.headlineMedium)
                            .foregroundColor(colors.textPrimary)
                            .lineLimit(2)
                        Text(single.artistText ?? "Unbekannter Interpret")
                            .textStyle(Typo.titleMedium)
                            .foregroundColor(colors.accentText)
                            .lineLimit(1)
                        Text(single.album ?? "")
                            .textStyle(Typo.bodyMedium)
                            .foregroundColor(colors.textSecondary)
                            .lineLimit(1)
                    } else {
                        Text(Formatting.tracks(tracks.count))
                            .textStyle(Typo.headlineMedium)
                            .foregroundColor(colors.textPrimary)
                        let artists = Set(tracks.compactMap(\.artistText))
                        let albums = Set(tracks.compactMap(\.album))
                        Text(artists.count == 1 ? artists.first! : "Verschiedene Interpreten")
                            .textStyle(Typo.titleMedium)
                            .foregroundColor(colors.accentText)
                        Text(albums.count == 1 ? albums.first! : "\(albums.count) Alben")
                            .textStyle(Typo.bodyMedium)
                            .foregroundColor(colors.textSecondary)
                    }
                }
                Spacer()
                if single != nil {
                    HStack(spacing: 6) {
                        GlassIconButton(icon: Icons.chevronLeft, label: "Vorheriger Titel (⌘[)", size: 30, iconSize: 15) { navigate(-1) }
                            .keyboardShortcut("[", modifiers: .command)
                        GlassIconButton(icon: Icons.chevronRight, label: "Nächster Titel (⌘])", size: 30, iconSize: 15) { navigate(1) }
                            .keyboardShortcut("]", modifiers: .command)
                    }
                    .padding(.top, -50)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 26)
        }
        .frame(height: 150)
    }

    private func navigate(_ delta: Int) {
        guard let uid = session.uids.first else { return }
        let list = model.trackList.map(\.uid)
        guard let i = list.firstIndex(of: uid) else { return }
        let j = i + delta
        guard list.indices.contains(j) else { return }
        if session.hasChanges {
            Task {
                if await model.metadata.apply(session: session) { model.editorUids = [list[j]] }
            }
        } else {
            model.editorUids = [list[j]]
        }
    }

    // MARK: Fuß

    private var footer: some View {
        let format = session.files.first?.result.map { "\($0.fileFormat) · \($0.tagFormat)" } ?? ""
        return VStack(spacing: 0) {
            if session.hasChanges {
                HStack(alignment: .top, spacing: 10) {
                    Icon(Icons.checkCircle, size: 16, color: colors.accentText)
                    Text("**Vor dem Schreiben:** \(Formatting.tracks(session.files.count)), \(session.summary). Jede Datei wird gesichert, als Kopie bearbeitet, gegengelesen und erst dann ersetzt. Rückgängig über „Bearbeiten → Widerrufen“ (⌘Z) oder in den Einstellungen.")
                        .textStyle(Typo.bodySmall)
                        .foregroundColor(colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors.accentSoft))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(colors.accent.opacity(0.3), lineWidth: 1))
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    if !session.allWritable && !session.loading {
                        Label {
                            Text("Mindestens eine Datei ist schreibgeschützt oder ihr Format kann nicht beschrieben werden.")
                        } icon: { Icon(Icons.warning, size: 13, color: colors.danger) }
                        .textStyle(Typo.labelSmall)
                        .foregroundColor(colors.danger)
                    } else if !format.isEmpty {
                        Text(session.isMulti ? "\(Formatting.tracks(session.files.count)) · nur Felder mit rosé Punkt werden geschrieben" : format)
                            .textStyle(Typo.labelSmall)
                            .foregroundColor(colors.textTertiary)
                    }
                }
                Spacer()
                // Glas-Menü statt `Menu`: dessen Beschriftung mit eigenem Symbol bliebe unter macOS 13 unsichtbar
                GlassMenuButton(icon: Icons.moreHoriz, help: "Kopieren, Einfügen, Verwerfen", touch: 30, width: 240) { menu in
                    GlassMenuItem(title: "Metadaten kopieren", icon: Icons.copy) {
                        let (v, f) = session.copyableValues()
                        model.metadata.clipboard = (v, f)
                        menu.close()
                    }
                    GlassMenuItem(title: "Metadaten einfügen", icon: Icons.paste) {
                        if let c = model.metadata.clipboard { session.paste(c.0, fields: c.1) }
                        menu.close()
                    }
                    .disabled(model.metadata.clipboard == nil)
                    GlassMenuDivider()
                    GlassMenuItem(title: "Alle Änderungen verwerfen", icon: Icons.undo, destructive: true) {
                        session.revertAll()
                        menu.close()
                    }
                    .disabled(!session.hasChanges)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                PillButton(title: "Abbrechen") { close() }
                    .keyboardShortcut(.cancelAction)
                PillButton(title: saving ? "Wird geschrieben …" : (session.isMulti ? "\(Formatting.tracks(session.files.count)) ändern" : "Sichern"),
                           icon: Icons.check, style: .filled, minWidth: 130) {
                    save()
                }
                .disabled(!session.hasChanges || saving || session.loading)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .animation(Motion.easeOut(), value: session.hasChanges)
        .background(EdgeFade(top: false, strength: 0.9))
    }

    private func save() {
        saving = true
        Task {
            let ok = await model.metadata.apply(session: session)
            saving = false
            if ok { close() }
        }
    }

    private func close() {
        NSApp.keyWindow?.performClose(nil)
    }
}

// MARK: - Feld-Bausteine

/// Beschriftete Eingabezeile im App-Stil (zarte Fläche, Rosé-Ring und -Punkt bei Änderungen, „Gemischt“).
struct EditorFieldRow<Field: View>: View {
    @Environment(\.musicColors) private var colors
    let label: String
    var dirty: Bool = false
    var labelWidth: CGFloat = 132
    @ViewBuilder var field: () -> Field

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .textStyle(Typo.bodySmall)
                .foregroundColor(colors.textSecondary)
                .frame(width: labelWidth, alignment: .trailing)
            field()
            Circle()
                .fill(dirty ? colors.accent : .clear)
                .frame(width: 7, height: 7)
                .help(dirty ? "Wird geändert" : "")
        }
        .frame(minHeight: 30)
    }
}

/// Einzeiliges Feld eines Tag-Werts.
struct TagTextField: View {
    @Environment(\.musicColors) private var colors
    @ObservedObject var session: EditorSession
    let field: TagField
    var placeholder: String = ""
    var width: CGFloat? = nil
    var disabledReason: String? = nil

    var body: some View {
        let mixed = session.mixed.contains(field) && !session.dirty.contains(field)
        let dirty = session.dirty.contains(field)
        let unsupported = !session.loading && !session.supportedFields.contains(field)
        let disabled = disabledReason != nil || unsupported
        TextField("", text: session.binding(field), prompt: Text(disabledReason ?? (unsupported ? "Vom Dateiformat nicht unterstützt" : (mixed ? ((width ?? .infinity) < 80 ? "–" : "Gemischt") : placeholder))).foregroundColor(colors.textTertiary))
            .textFieldStyle(.plain)
            .font(Typo.inter(13, .regular))
            .foregroundColor(colors.textPrimary)
            .padding(.horizontal, 9)
            .frame(width: width, height: 28)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(disabled ? colors.fieldFill.opacity(0.5) : colors.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(dirty ? colors.accent : .clear, lineWidth: 1.6))
            .disabled(disabled)
            .contextMenu {
                if dirty { Button("Änderung zurücknehmen") { session.revert(field) } }
                Button("Feld leeren") { session.set(field, "") }
            }
    }
}

/// Glaskarte mit Überschrift für Feldgruppen.
struct EditorCard<Content: View>: View {
    @Environment(\.musicColors) private var colors
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .textStyle(Typo.sectionLabel)
                .foregroundColor(colors.textSecondary)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 8) { content() }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .padding(.bottom, 14)
    }
}

// MARK: - Details

private struct DetailsTab: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    @ObservedObject var session: EditorSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorCard(title: "Titel und Mitwirkende") {
                row("Titel", .title) {
                    TagTextField(session: session, field: .title, disabledReason: session.isMulti ? "Bei mehreren Titeln nicht gemeinsam änderbar" : nil)
                }
                row("Interpret", .artists) { TagTextField(session: session, field: .artists, placeholder: "Mehrere mit „;“ trennen") }
                row("Album", .album) { TagTextField(session: session, field: .album) }
                row("Albuminterpret", .albumArtists) { TagTextField(session: session, field: .albumArtists) }
                row("Komponist", .composers) { TagTextField(session: session, field: .composers) }
                EditorFieldRow(label: "") {
                    Toggle("Komponist in Listen anzeigen", isOn: Binding(get: { model.settings.showComposer }, set: { model.settings.showComposer = $0 }))
                        .toggleStyle(.checkbox)
                        .font(Typo.inter(12, .regular))
                    Text("Bibliothek").textStyle(Typo.labelSmall).foregroundColor(colors.textTertiary)
                        .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(colors.fieldFill))
                    Spacer()
                }
                row("Werk", .work) { TagTextField(session: session, field: .work) }
                row("Gruppierung", .grouping) { TagTextField(session: session, field: .grouping) }
            }
            EditorCard(title: "Einordnung") {
                row("Genre", .genres) {
                    HStack(spacing: 6) {
                        TagTextField(session: session, field: .genres)
                        GlassMenuButton(help: "Vorhandenes Genre wählen", width: 240, label: {
                            Icon(Icons.expandMore, size: 16, color: colors.onAccent)
                                .frame(width: 22, height: 22)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(colors.accent))
                        }) { menu in
                            let names = model.index.genres.filter { !$0.isUnknown }.map(\.name).sorted()
                            // feste Höhe: das Menü passt sich sonst nicht an eine Scrollfläche an
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 1) {
                                    ForEach(names, id: \.self) { g in
                                        GlassMenuItem(title: g) { session.set(.genres, g); menu.close() }
                                    }
                                }
                            }
                            .frame(height: min(340, CGFloat(max(names.count, 1)) * 29))
                        }
                        .fixedSize()
                    }
                }
                row("Jahr", .year) { TagTextField(session: session, field: .year, width: 80); Spacer() }
                EditorFieldRow(label: "Titel", dirty: session.dirty.contains(.trackNumber) || session.dirty.contains(.trackTotal)) {
                    TagTextField(session: session, field: .trackNumber, width: 54)
                    Text("von").textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary)
                    TagTextField(session: session, field: .trackTotal, width: 54)
                    Spacer()
                }
                EditorFieldRow(label: "Disc", dirty: session.dirty.contains(.discNumber) || session.dirty.contains(.discTotal)) {
                    TagTextField(session: session, field: .discNumber, width: 54)
                    Text("von").textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary)
                    TagTextField(session: session, field: .discTotal, width: 54)
                    Spacer()
                }
                EditorFieldRow(label: "Compilation", dirty: session.dirty.contains(.compilation)) {
                    TriStateCheckbox(state: session.compilation) { session.setCompilation($0) }
                    Text("Album mit Titeln verschiedener Interpreten").textStyle(Typo.bodySmall).foregroundColor(colors.textPrimary)
                    Spacer()
                }
                row("BPM", .bpm) { TagTextField(session: session, field: .bpm, width: 80); Spacer() }
            }
            EditorCard(title: "Bewertung und Wiedergabe") {
                EditorFieldRow(label: "Bewertung", dirty: session.dirty.contains(.rating)) {
                    StarRating(stars: session.stars) { session.setStars($0) }
                    if session.stars == nil {
                        Text("Gemischt").textStyle(Typo.bodySmall).foregroundColor(colors.textTertiary).italic()
                    }
                    Spacer()
                }
                EditorFieldRow(label: "Favorit") {
                    let uids = session.uids
                    let fav = uids.allSatisfy { model.isFavorite($0) }
                    HeartButton(favorite: fav, iconSize: 17, touch: 26) { model.setFavorite(uids, !fav) }
                    Text(fav ? "Favorit" : "Kein Favorit").textStyle(Typo.bodySmall).foregroundColor(colors.textPrimary)
                    Text("Bibliothek").textStyle(Typo.labelSmall).foregroundColor(colors.textTertiary)
                        .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(colors.fieldFill))
                    Spacer()
                }
                EditorFieldRow(label: "Zähler") {
                    let count = session.uids.reduce(0) { $0 + (model.stats[$1]?.playCount ?? 0) }
                    let last = session.uids.compactMap { model.stats[$0]?.lastPlayedAt }.max()
                    Text(Formatting.plays(count) + (last.map { " · zuletzt " + Formatting.dateTime($0) } ?? ""))
                        .textStyle(Typo.bodySmall)
                        .foregroundColor(colors.textPrimary)
                    Spacer()
                    PillButton(title: "Zurücksetzen", style: .plain) { model.resetStats(session.uids) }
                        .disabled(count == 0)
                }
                EditorFieldRow(label: "Kommentar", dirty: session.dirty.contains(.comment)) {
                    TextEditor(text: session.binding(.comment))
                        .font(Typo.inter(13, .regular))
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .frame(height: 64)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(colors.fieldFill))
                        .overlay(alignment: .topLeading) {
                            if session.value(.comment).isEmpty && session.mixed.contains(.comment) {
                                Text("Gemischt").textStyle(Typo.bodySmall).foregroundColor(colors.textTertiary).padding(9).allowsHitTesting(false)
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(session.dirty.contains(.comment) ? colors.accent : .clear, lineWidth: 1.6))
                }
            }
        }
    }

    private func row<F: View>(_ label: String, _ field: TagField, @ViewBuilder _ content: @escaping () -> F) -> some View {
        EditorFieldRow(label: label, dirty: session.dirty.contains(field), field: content)
    }
}

/// Kontrollkästchen mit drittem Zustand „gemischt“.
struct TriStateCheckbox: View {
    @Environment(\.musicColors) private var colors
    let state: Bool?
    let set: (Bool) -> Void

    var body: some View {
        Button { set(!(state ?? false)) } label: {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(state == true ? colors.accent : colors.surface)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(state == true ? .clear : colors.textPrimary.opacity(0.3), lineWidth: 1))
                .overlay(Group {
                    if state == true { Icon(Icons.check, size: 12, color: colors.onAccent) }
                    if state == nil { Capsule().fill(colors.textSecondary).frame(width: 8, height: 2) }
                })
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .accessibilityValue(state == nil ? "gemischt" : (state == true ? "an" : "aus"))
    }
}

/// Bewertung mit fünf Sternen (Klick auf den aktuellen Stern entfernt die Bewertung).
struct StarRating: View {
    @Environment(\.musicColors) private var colors
    let stars: Int?
    let set: (Int) -> Void
    @State private var hover: Int?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                let filled = i <= (hover ?? stars ?? 0)
                Icon(filled ? Icons.starFill : Icons.star, size: 18, color: filled ? colors.accent : colors.textTertiary.opacity(0.6))
                    .onHover { h in hover = h ? i : (hover == i ? nil : hover) }
                    .onTapGesture { set(stars == i ? 0 : i) }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Bewertung")
        .accessibilityValue(stars.map { "\($0) von 5 Sternen" } ?? "gemischt")
        .accessibilityAdjustableAction { dir in
            let s = stars ?? 0
            set(dir == .increment ? min(5, s + 1) : max(0, s - 1))
        }
    }
}

// MARK: - Sortierung

private struct SortingTab: View {
    @ObservedObject var session: EditorSession

    var body: some View {
        EditorCard(title: "Sortierung") {
            ForEach([TagField.titleSort, .artistSort, .albumSort, .albumArtistSort, .composerSort], id: \.self) { f in
                EditorFieldRow(label: f.label, dirty: session.dirty.contains(f)) {
                    TagTextField(session: session, field: f, placeholder: "Wie angezeigt", disabledReason: f == .titleSort && session.isMulti ? "Bei mehreren Titeln nicht gemeinsam änderbar" : nil)
                }
            }
            Text("Sortiernamen bestimmen die Reihenfolge, ohne die Anzeige zu ändern – z. B. „Beatles, The“.")
                .textStyle(Typo.bodySmall)
                .foregroundColor(.secondary)
                .padding(.leading, 144)
        }
    }
}

// MARK: - Datei

private struct FileTab: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    @ObservedObject var session: EditorSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorCard(title: "Weitere Angaben") {
                ForEach([TagField.publisher, .copyright, .isrc, .encodedBy], id: \.self) { f in
                    EditorFieldRow(label: f.label, dirty: session.dirty.contains(f)) {
                        TagTextField(session: session, field: f, disabledReason: f == .isrc && session.isMulti ? "Bei mehreren Titeln nicht gemeinsam änderbar" : nil)
                    }
                }
            }
            ForEach(session.files.prefix(20)) { file in
                EditorCard(title: session.isMulti ? file.track.displayTitle : "Datei") {
                    info("Ort", file.track.path) {
                        IconTap(icon: Icons.folderOpen, label: "Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                    }
                    if let r = file.result {
                        info("Format", "\(r.fileFormat) · \(r.audio.codec)")
                        info("Tags", r.tagFormat.isEmpty ? "keine" : r.tagFormat)
                        info("Dauer", Formatting.duration(r.audio.durationMs))
                        info("Qualität", [r.audio.bitrate > 0 ? "\(r.audio.bitrate) kbit/s" : nil,
                                           r.audio.sampleRate > 0 ? Formatting.sampleRate(r.audio.sampleRate) : nil,
                                           r.audio.bitsPerSample > 0 ? "\(r.audio.bitsPerSample) Bit" : nil,
                                           r.audio.channels > 0 ? Formatting.channels(r.audio.channels) : nil].compactMap { $0 }.joined(separator: " · "))
                        info("Größe", Formatting.fileSize(file.track.sizeBytes))
                        info("Geändert", Formatting.dateTime(file.track.dateModified * 1000))
                        info("Hinzugefügt", Formatting.dateTime(file.track.dateAdded * 1000))
                        info("Schreiben", r.writable ? "möglich – sicher über eine geprüfte Kopie" : "nicht möglich (Format oder Datei schreibgeschützt)")
                    } else if let e = file.error {
                        info("Fehler", e)
                    }
                }
            }
        }
    }

    private func info(_ label: String, _ value: String) -> some View {
        info(label, value) { EmptyView() }
    }

    private func info<T: View>(_ label: String, _ value: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .textStyle(Typo.bodySmall)
                .foregroundColor(colors.textSecondary)
                .frame(width: 132, alignment: .trailing)
            Text(value)
                .textStyle(Typo.bodySmall)
                .foregroundColor(colors.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
    }
}
