import SwiftUI
import AppKit
import MLCore
import MLStore
import MLTags

// Einstellungen v2: eigenes Fenster mit Kategorien links und Inhalt rechts. Jede Einstellung wirkt –
// es gibt keine Schalter ohne Funktion.

enum SettingsCategory: String, CaseIterable, Hashable, Identifiable {
    case general, appearance, playerDesigns, library, folders, sorting, playback, equalizer, pitch, volume,
         lyrics, metadata, studio, shortcuts, storage, privacy, about

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "Allgemein"
        case .appearance: return "Erscheinungsbild"
        case .playerDesigns: return "Player-Designs"
        case .library: return "Bibliothek"
        case .folders: return "Import & Musikordner"
        case .sorting: return "Sortierung"
        case .playback: return "Wiedergabe"
        case .equalizer: return "Equalizer"
        case .pitch: return "Tonhöhe"
        case .volume: return "Lautstärke"
        case .lyrics: return "Liedtexte"
        case .metadata: return "Metadaten"
        case .studio: return "Hinzufügen & Studio"
        case .shortcuts: return "Tastaturkurzbefehle"
        case .storage: return "Speicher & Cache"
        case .privacy: return "Datenschutz"
        case .about: return "Über die App"
        }
    }

    var icon: String {
        switch self {
        case .general: return Icons.settings
        case .appearance: return Icons.palette
        case .playerDesigns: return Icons.vinyl
        case .library: return Icons.libraryMusic
        case .folders: return Icons.folder
        case .sorting: return Icons.sort
        case .playback: return Icons.play
        case .equalizer: return Icons.equalizer
        case .pitch: return Icons.pitch
        case .volume: return Icons.volumeUp
        case .lyrics: return Icons.lyrics
        case .metadata: return Icons.editNote
        case .studio: return Icons.studio
        case .shortcuts: return Icons.keyboard
        case .storage: return Icons.storage
        case .privacy: return Icons.privacy
        case .about: return Icons.info
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    @State private var category: SettingsCategory = .general

    var body: some View {
        ZStack {
            AmbientBackground()
            HStack(spacing: 0) {
                SettingsSidebar(selection: $category)
                    .frame(width: 222)
                    .padding(.top, 34)
                    .padding(.leading, 12)
                    .padding(.bottom, 14)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(category.label)
                            .textStyle(Typo.headlineSmall)
                            .foregroundColor(colors.textPrimary)
                            .padding(.bottom, 16)
                        SettingsContent(category: category)
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 36)
                    .padding(.bottom, 26)
                    .frame(maxWidth: 720, alignment: .leading)
                    .id(category)
                }
                .frame(maxWidth: .infinity)
            }
        }
        // Verdeckte Titelleiste: oberer Rand verschiebt das Fenster (Inhalte beginnen darunter)
        .overlay(alignment: .top) {
            WindowDragArea().frame(height: 28)
        }
        .frame(minWidth: 780, minHeight: 560)
        .onAppear(perform: takePendingCategory)
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsCategory)) { _ in takePendingCategory() }
    }

    private func takePendingCategory() {
        guard let raw = WindowRouter.shared.pendingSettingsCategory else { return }
        WindowRouter.shared.pendingSettingsCategory = nil
        if let c = SettingsCategory(rawValue: raw) { category = c }
    }
}

private struct SettingsSidebar: View {
    @Environment(\.musicColors) private var colors
    @Binding var selection: SettingsCategory

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsCategory.allCases) { c in
                    SidebarRow(category: c, selected: c == selection) {
                        withAnimation(Motion.easeOut(0.16)) { selection = c }
                    }
                }
            }
            .padding(8)
        }
        .glassSurface(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous), strong: true)
    }
}

private struct SidebarRow: View {
    @Environment(\.musicColors) private var colors
    let category: SettingsCategory
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Icon(category.icon, size: 16, color: selected ? colors.accentText : colors.textSecondary)
                    .frame(width: 20)
                Text(category.label)
                    .font(Typo.inter(13, selected ? .semibold : .regular))
                    .foregroundColor(selected ? colors.textPrimary : colors.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? colors.accentSoft : (hover ? colors.textPrimary.opacity(0.05) : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SettingsContent: View {
    let category: SettingsCategory

    var body: some View {
        switch category {
        case .general: GeneralSettings()
        case .appearance: AppearanceSettings()
        case .playerDesigns: PlayerDesignSettings()
        case .library: LibraryBehaviourSettings()
        case .folders: FolderSettings()
        case .sorting: SortingSettings()
        case .playback: PlaybackSettings()
        case .equalizer: EqualizerSettings()
        case .pitch: PitchSettingsView()
        case .volume: VolumeSettings()
        case .lyrics: LyricsSettings()
        case .metadata: MetadataSettings()
        case .studio: StudioSettingsPane()
        case .shortcuts: ShortcutSettings()
        case .storage: StorageSettings()
        case .privacy: PrivacySettings()
        case .about: AboutSettings()
        }
    }
}

// MARK: - Bausteine

extension AppModel {
    /// Bindung an eine Einstellung (speichert gebündelt).
    func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { self.settings[keyPath: keyPath] }, set: { self.settings[keyPath: keyPath] = $0 })
    }
}

/// Zeile „Titel + Erklärung + Bedienelement“.
struct SettingRow<Control: View>: View {
    @Environment(\.musicColors) private var colors
    let title: String
    var text: String? = nil
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).textStyle(Typo.bodyLarge).foregroundColor(colors.textPrimary)
                if let text {
                    Text(text).textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.vertical, 5)
    }
}

/// Schalterzeile.
private struct ToggleRow: View {
    let title: String
    var text: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(title: title, text: text) {
            MusicToggle(isOn: $isOn, label: title)
        }
    }
}

/// Erklärender Text in einer Karte.
private struct Note: View {
    @Environment(\.musicColors) private var colors
    let text: String

    var body: some View {
        Text(text).textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// Regler mit Wert, der erst beim Loslassen gespeichert wird.
private struct CommitSlider: View {
    @Environment(\.musicColors) private var colors
    let value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    let label: String
    let format: (Double) -> String
    let commit: (Double) -> Void
    @State private var local: Double?

    var body: some View {
        let shown = local ?? value
        HStack(spacing: 12) {
            MusicSlider(value: Binding(get: { local ?? value }, set: { local = $0 }), range: range, showsKnob: true, step: step,
                        label: label, valueText: format(shown)) { editing in
                if !editing, let v = local {
                    commit(v)
                    local = nil
                }
            }
            .frame(width: 220, height: 22)
            Text(verbatim: format(shown))
                .font(Typo.inter(12, .semibold))
                .foregroundColor(colors.textSecondary)
                .frame(width: 70, alignment: .trailing)
        }
    }
}

// MARK: - 1 Allgemein

private struct GeneralSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        EditorCard(title: "Start") {
            SettingRow(title: "Bereich beim Start", text: "Welcher Bereich nach dem Öffnen der App angezeigt wird.") {
                Picker("", selection: Binding(get: { model.settings.startSection?.rawValue ?? "" },
                                              set: { model.settings.startSection = LibrarySection(rawValue: $0) })) {
                    Text("Zuletzt benutzt").tag("")
                    ForEach(LibrarySection.allCases, id: \.self) { s in Text(s.label).tag(s.rawValue) }
                }
                .labelsHidden()
                .frame(width: 180)
            }
            Hairline()
            ToggleRow(title: "Wiedergabe beim Start fortsetzen",
                      text: "Warteschlange, Titel und Position werden wiederhergestellt (pausiert).",
                      isOn: model.binding(\.resumeOnLaunch))
        }
        EditorCard(title: "Fenster und Menüleiste") {
            ToggleRow(title: "Player in der Menüleiste",
                      text: "Kleiner Player mit Cover und Steuerung oben rechts in der Menüleiste.",
                      isOn: model.binding(\.showMenuBarPlayer))
            Hairline()
            SettingRow(title: "Mini-Player-Fenster", text: "Eigenes kleines Fenster, auf Wunsch immer im Vordergrund (⌥⌘M).") {
                PillButton(title: "Öffnen", icon: Icons.miniPlayer) { WindowRouter.shared.openMiniPlayer() }
            }
            Hairline()
            SettingRow(title: "Equalizer-Fenster", text: "Equalizer in einem eigenen Fenster (⌥⌘E).") {
                PillButton(title: "Öffnen", icon: Icons.equalizer) { WindowRouter.shared.openEqualizer() }
            }
        }
    }
}

// MARK: - 2 Erscheinungsbild

private struct AppearanceSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        EditorCard(title: "Design") {
            SettingRow(title: "Hell, Dunkel oder automatisch", text: "Beide Modi sind eigenständig gestaltet. „Wie macOS“ folgt der Systemeinstellung.") {
                SegmentedControl(options: ThemeMode.allCases, selection: model.binding(\.themeMode), label: { $0.label },
                                 icon: { mode -> String? in
                                     switch mode {
                                     case .system: return Icons.autoMode
                                     case .light: return Icons.lightMode
                                     case .dark: return Icons.darkMode
                                     }
                                 })
                .frame(width: 330)
            }
        }
        EditorCard(title: "Glas und Farben") {
            ToggleRow(title: "Glas-Effekte",
                      text: LiquidGlass.isAvailable
                        ? "Liquid Glass von macOS für Navigation, Mini-Player, Kopfleisten und Menüs. Aus: ruhige, undurchsichtige Flächen."
                        : "Glas mit Hintergrundunschärfe für Navigation, Mini-Player, Kopfleisten und Menüs (Liquid Glass gibt es ab macOS 26). Aus: ruhige, undurchsichtige Flächen.",
                      isOn: model.binding(\.glassEffects))
            Hairline()
            ToggleRow(title: "Leistungsmodus (weniger Transparenz)",
                      text: "Glasflächen ohne Echtzeit-Unschärfe – deutlich weniger Grafiklast auf älteren Macs, das Aussehen bleibt ähnlich.",
                      isOn: model.binding(\.reduceTransparency))
            Hairline()
            ToggleRow(title: "Farben des Covers",
                      text: "Der Hintergrund nimmt dezent die Farben des gerade gespielten Albums an.",
                      isOn: model.binding(\.dynamicCoverColors))
        }
        EditorCard(title: "Bewegung") {
            SettingRow(title: "Animationen", text: "Reduziert: nur sanfte Überblendungen. Aus: keine Animationen (Platte, Kassette und CD stehen still).") {
                SegmentedControl(options: AnimationLevel.allCases, selection: model.binding(\.animationLevel), label: { $0.label })
                    .frame(width: 280)
            }
        }
    }
}

// MARK: - 3 Player-Designs

private struct PlayerDesignSettings: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        EditorCard(title: "Großer Player") {
            Note(text: "Alle Designs haben dieselbe Bedienung. Die Auswahl bleibt gespeichert; ein Wechsel unterbricht die Wiedergabe nicht.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 8) {
                ForEach(PlayerTheme.allCases, id: \.self) { theme in
                    ChoiceChip(title: theme.label, selected: model.settings.playerTheme == theme) { model.settings.playerTheme = theme }
                        .help(theme.description)
                }
            }
            Note(text: model.settings.playerTheme.description)
            Hairline()
            SettingRow(title: "Farbe der Kassette", text: "Gehäusefarbe im Design „Cassette Studio“ – „Cover“ übernimmt die Farbe des Albums.") {
                Picker("", selection: model.binding(\.cassetteColor)) {
                    ForEach(CassetteColor.allCases, id: \.self) { c in Text(c.label).tag(c) }
                }
                .labelsHidden()
                .frame(width: 160)
            }
            Hairline()
            ToggleRow(title: "Klangvisualisierung",
                      text: "Frequenzbalken bzw. Lichtring aus der tatsächlichen Wiedergabe. Nur aktiv, solange der Player sichtbar ist; beeinflusst den Klang nicht.",
                      isOn: model.binding(\.visualizer))
        }
        EditorCard(title: "Hintergrund") {
            PlayerBackgroundPicker(showsTitle: false)
        }
        EditorCard(title: "Mini-Player") {
            SettingRow(title: "Größe",
                       text: "Der schwebende Player am unteren Fensterrand. „Sehr groß“ und „Riesig“ zeigen Lautstärke, Equalizer und Tonhöhe direkt in der Leiste.") {
                EmptyView()
            }
            // v2.1: fünf Größen – eigene Zeile, damit alle Beschriftungen vollständig lesbar sind
            SegmentedControl(options: MiniPlayerSize.allCases,
                             selection: Binding(get: { model.settings.miniPlayerSize },
                                                set: { s in withAnimation(Motion.easeOut(Motion.medium)) { model.settings.miniPlayerSize = s } }),
                             label: { $0.label })
                .frame(maxWidth: 480)
            Hairline()
            ToggleRow(title: "Player-Design im Mini-Player",
                      text: "Zeigt die kleine drehende Platte, Kassette oder CD des gewählten Designs statt nur des Covers.",
                      isOn: model.binding(\.miniPlayerShowsDesign))
        }
    }
}

// MARK: - 4 Bibliothek

private struct LibraryBehaviourSettings: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        EditorCard(title: "Übersicht") {
            let total = model.index.tracks.count
            let unavailable = model.unavailableCount
            Text(verbatim: "\(Formatting.tracks(total)) · \(Formatting.albums(model.index.albums.count)) · \(Formatting.artists(model.index.artists.count))"
                 + (unavailable > 0 ? " · \(Formatting.tracks(unavailable)) derzeit nicht erreichbar" : ""))
                .textStyle(Typo.bodyMedium)
            Note(text: "Favoriten, Playlists, Zähler und Verlauf bleiben erhalten, auch wenn Dateien zeitweise fehlen.")
            HStack(spacing: 10) {
                PillButton(title: "Duplikate finden", icon: Icons.difference) {
                    model.playerOpen = false
                    model.select(.tracks)
                    model.open(.duplicates)
                    NSApp.keyWindow?.performClose(nil)
                }
                PillButton(title: "Wiedergabeverlauf", icon: Icons.history, style: .plain) {
                    model.playerOpen = false
                    model.select(.playlists)
                    model.open(.history)
                    NSApp.keyWindow?.performClose(nil)
                }
            }
        }
        EditorCard(title: "Darstellung je Bereich") {
            Note(text: "Ansicht, die ein Bereich beim Öffnen zeigt. Umschalten geht jederzeit oben rechts im Bereich; die Wahl bleibt gespeichert.")
            ForEach(LibraryViewContext.allCases, id: \.self) { ctx in
                SettingRow(title: ctx.label) {
                    Picker("", selection: Binding(get: { model.viewOptions(ctx).mode },
                                                  set: { mode in
                                                      var o = model.viewOptions(ctx)
                                                      o.mode = mode
                                                      model.setViewOptions(o, for: ctx)
                                                  })) {
                        ForEach(LibraryViewMode.allCases, id: \.self) { m in Text(m.label).tag(m) }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
            }
            PillButton(title: "Alle Ansichten zurücksetzen", icon: Icons.restart, style: .plain) {
                for ctx in LibraryViewContext.allCases { model.setViewOptions(LibraryViewOptions.defaults(for: ctx), for: ctx) }
            }
        }
        EditorCard(title: "Angaben") {
            ToggleRow(title: "Komponist anzeigen", text: "Komponist zusätzlich in Listen und im Player.", isOn: model.binding(\.showComposer))
        }
        DateAddedSettings()
    }
}

/// Hinzufügedatum (v2.1): Quellen erklären, aus Apple Musik übernehmen oder neu bestimmen, Fortschritt zeigen.
private struct DateAddedSettings: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        let running = model.datesAddedRunning
        EditorCard(title: "Hinzufügedatum") {
            Note(text: "Wann ein Titel in deine Sammlung kam – Grundlage für „Zuletzt hinzugefügt“ und die Sortierung nach Datum. Die App verwendet die beste verfügbare Quelle:")
            VStack(alignment: .leading, spacing: 8) {
                DateSourceLine(icon: Icons.libraryMusic, title: "Apple Musik",
                               text: "„Hinzugefügt“ aus deiner Apple-Musik- bzw. iTunes-Mediathek – das genaueste Datum, wenn die Titel dort bereits waren. Wird nie durch eine schwächere Quelle ersetzt.")
                DateSourceLine(icon: Icons.description, title: "Erstellungsdatum der Datei",
                               text: "Oder der Zeitpunkt, zu dem die Datei in ihren Ordner gelegt wurde. Das Änderungsdatum zählt nie – es ändert sich z. B. beim Bearbeiten der Tags.")
                DateSourceLine(icon: Icons.event, title: "Import",
                               text: "Erster Import in Music Library – nur, wenn nichts Besseres bekannt ist. Ein bekanntes Datum wird nie auf später verschoben.")
            }
            .padding(.vertical, 2)
            Hairline()
            SettingRow(title: "Aus Apple Musik übernehmen",
                       text: "Liest die Mediathek von Apple Musik und übernimmt deren Hinzufügedaten für alle passenden Titel. macOS fragt dabei einmal nach der Erlaubnis für den Zugriff auf die Mediathek.") {
                PillButton(title: "Aus Apple Musik übernehmen …", icon: Icons.libraryMusic, style: .filled) {
                    model.rebuildDatesAdded(useAppleMusic: true)
                }
                .disabled(running)
            }
            Hairline()
            SettingRow(title: "Neu bestimmen",
                       text: "Bestimmt die Daten erneut aus Dateien und Ordnern (ohne Apple Musik). Bereits aus Apple Musik übernommene Daten bleiben erhalten.") {
                PillButton(title: "Neu bestimmen", icon: Icons.refresh) {
                    model.rebuildDatesAdded(useAppleMusic: false)
                }
                .disabled(running)
            }
            if running || model.datesAddedStatus != nil {
                HStack(spacing: 8) {
                    if running {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                    } else {
                        Icon(Icons.checkCircle, size: 15, color: colors.accentText)
                    }
                    Text(model.datesAddedStatus ?? "Hinzufügedaten werden bestimmt …")
                        .textStyle(Typo.bodySmall)
                        .foregroundColor(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors.fieldFill))
                .transition(.opacity)
            }
        }
        .animation(Motion.easeOut(), value: running)
    }
}

/// Eine Quelle des Hinzufügedatums (Symbol, Name, Erklärung).
private struct DateSourceLine: View {
    @Environment(\.musicColors) private var colors
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Icon(icon, size: 16, color: colors.accentText)
                .frame(width: 22, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).textStyle(Typo.labelLarge).foregroundColor(colors.textPrimary)
                Text(text).textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 5 Import & Musikordner

private struct FolderSettings: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        EditorCard(title: "Musikordner") {
            if model.folders.isEmpty {
                Note(text: "Noch keine Musikordner gewählt.")
            }
            ForEach(model.folders) { f in
                FolderRow(folder: f)
                Hairline()
            }
            HStack(spacing: 10) {
                PillButton(title: "Ordner hinzufügen …", icon: Icons.add, style: .filled) { model.library.chooseFolders() }
                PillButton(title: model.scanState.isRunning ? "läuft …" : "Jetzt abgleichen", icon: Icons.refresh) { model.library.rescan(reason: "Einstellungen") }
                    .disabled(model.scanState.isRunning)
                PillButton(title: "Alle Tags neu lesen", style: .plain) { model.library.rescan(reason: "Neu lesen", fullTagRefresh: true) }
                    .disabled(model.scanState.isRunning)
            }
            .padding(.top, 4)
        }
        EditorCard(title: "Automatisch") {
            ToggleRow(title: "Ordner überwachen",
                      text: "Neue, geänderte, verschobene und gelöschte Dateien werden sofort erkannt (auch auf externen Laufwerken).",
                      isOn: model.binding(\.watchFolders))
            Hairline()
            ToggleRow(title: "Beim Start abgleichen", text: "Vergleicht die Ordner bei jedem Start mit der Bibliothek.", isOn: model.binding(\.scanOnLaunch))
            Hairline()
            Note(text: "Unterstützt: MP3, AAC/M4A, ALAC, FLAC, WAV, AIFF, CAF, Ogg Vorbis. Opus und Ogg FLAC erscheinen in der Bibliothek, können aber noch nicht abgespielt werden. Beschädigte Dateien werden übersprungen und beim nächsten Abgleich erneut versucht.")
        }
    }
}

private struct FolderRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    let folder: LibraryFolder

    var body: some View {
        let f = folder
        let online = model.library.isOnline(f)
        HStack(spacing: 12) {
            Icon(f.isExternal ? Icons.usb : Icons.folder, size: 20, color: online ? colors.accentText : colors.textTertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text(f.name).textStyle(Typo.bodyLarge).foregroundColor(colors.textPrimary)
                Text(f.path).textStyle(Typo.labelSmall).foregroundColor(colors.textTertiary).lineLimit(1).truncationMode(.middle)
                Text(online ? (f.isExternal ? "Externes Laufwerk · verbunden" : "Verfügbar") : "Nicht erreichbar – Titel bleiben erhalten und sind wieder da, sobald das Laufwerk angeschlossen ist")
                    .textStyle(Typo.labelSmall).foregroundColor(online ? colors.textSecondary : colors.danger)
            }
            Spacer()
            IconTap(icon: Icons.folderOpen, label: "Im Finder zeigen") { model.library.reveal(f) }
                .disabled(!online)
            GlassMenuButton(icon: Icons.moreHoriz, help: "Ordner entfernen", width: 330) { menu in
                GlassMenuItem(title: "Entfernen (Titel als nicht verfügbar behalten)", icon: Icons.remove) {
                    menu.close()
                    model.library.removeFolder(f, deleteTracks: false)
                }
                GlassMenuItem(title: "Entfernen und Titel aus der Bibliothek löschen", icon: Icons.delete, destructive: true) {
                    menu.close()
                    confirmRemove(f)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func confirmRemove(_ f: LibraryFolder) {
        let alert = NSAlert()
        alert.messageText = "„\(f.name)“ entfernen und Titel löschen?"
        alert.informativeText = "Die Titel dieses Ordners werden samt Favoriten, Playlist-Einträgen und Zählern aus der Bibliothek entfernt. Die Musikdateien bleiben unverändert."
        alert.addButton(withTitle: "Entfernen")
        alert.addButton(withTitle: "Abbrechen")
        if alert.runModal() == .alertFirstButtonReturn { model.library.removeFolder(f, deleteTracks: true) }
    }
}

// MARK: - 6 Sortierung

private struct SortingSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        EditorCard(title: "Sortierung je Bereich") {
            Note(text: "Dieselbe Sortierung wie oben rechts im jeweiligen Bereich – hier alle auf einen Blick. Sie bleibt gespeichert.")
            SortRow(title: "Titel", sort: model.binding(\.trackSort))
            SortRow(title: "Alben", sort: model.binding(\.albumSort))
            SortRow(title: "Interpreten", sort: model.binding(\.artistSort))
            SortRow(title: "Genres", sort: model.binding(\.genreSort))
            SortRow(title: "Playlists", sort: model.binding(\.playlistSort))
            SortRow(title: "Favoriten · Titel", sort: model.binding(\.favoriteTrackSort))
            SortRow(title: "Favoriten · Alben", sort: model.binding(\.favoriteAlbumSort))
        }
        EditorCard(title: "Suche") {
            Note(text: "Jeder Bereich hat eine eigene Suche. Mehrere Suchbegriffe werden kombiniert („queen 1975“ findet Titel, die beides enthalten); Groß-/Kleinschreibung und Akzente spielen keine Rolle.")
        }
    }
}

private struct SortRow<F: SortField>: View {
    let title: String
    @Binding var sort: Sort<F>

    var body: some View {
        SettingRow(title: title) {
            HStack(spacing: 8) {
                Picker("", selection: Binding(get: { sort.field }, set: { sort = Sort($0, descending: $0.defaultDescending) })) {
                    ForEach(Array(F.allCases), id: \.self) { f in Text(f.label).tag(f) }
                }
                .labelsHidden()
                .frame(width: 190)
                Picker("", selection: Binding(get: { sort.descending }, set: { sort = Sort(sort.field, descending: $0) })) {
                    Text(sort.field.ascendingLabel).tag(false)
                    Text(sort.field.descendingLabel).tag(true)
                }
                .labelsHidden()
                .frame(width: 170)
            }
        }
    }
}

// MARK: - 7 Wiedergabe

private struct PlaybackSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        EditorCard(title: "Wiedergabe") {
            ToggleRow(title: "Beim Start fortsetzen", text: "Warteschlange und Position wiederherstellen (pausiert).", isOn: model.binding(\.resumeOnLaunch))
            Hairline()
            ToggleRow(title: "Position langer Titel merken",
                      text: "Titel ab 10 Minuten (Hörbücher, Mixe, Podcasts) setzen beim nächsten Abspielen dort fort, wo du aufgehört hast.",
                      isOn: model.binding(\.rememberLongTrackPosition))
            Hairline()
            SettingRow(title: "Sprungweite", text: "Für die Tasten „zurück“/„vor“ im Player und im Mini-Player.") {
                Picker("", selection: model.binding(\.skipSeconds)) {
                    ForEach([5, 10, 15, 30], id: \.self) { s in Text(verbatim: "\(s) Sekunden").tag(s) }
                }
                .labelsHidden()
                .frame(width: 150)
            }
        }
        EditorCard(title: "Sleep-Timer") {
            ToggleRow(title: "Sanft ausblenden", text: "In den letzten 10 Sekunden wird leiser ausgeblendet, dann angehalten.", isOn: model.binding(\.sleepTimerFadeOut))
            Hairline()
            SettingRow(title: "Timer stellen", text: model.player.sleepTimer == nil ? "Kein Timer aktiv." : "Ein Timer läuft.") {
                HStack(spacing: 8) {
                    ForEach([15, 30, 60], id: \.self) { m in
                        PillButton(title: "\(m) min", style: .plain) { model.player.startSleepTimer(minutes: m) }
                    }
                    PillButton(title: "Aus", style: .plain) { model.player.cancelSleepTimer() }
                        .disabled(model.player.sleepTimer == nil)
                }
            }
        }
    }
}

// MARK: - 8 Equalizer

private struct EqualizerSettings: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    @State private var newName = ""
    @State private var renaming: String?
    @State private var renameText = ""

    var body: some View {
        let effects = model.settings.effects
        EditorCard(title: "Equalizer") {
            ToggleRow(title: "Equalizer eingeschaltet", text: "10 Bänder von 31 Hz bis 16 kHz, je ±12 dB. Wirkt sofort, nur auf die Musik dieser App.",
                      isOn: Binding(get: { model.settings.effects.eqEnabled }, set: { model.settings.effects.eqEnabled = $0 }))
            Hairline()
            ToggleRow(title: "Automatische Aussteuerung", text: "Senkt den Pegel bei angehobenen Bändern, damit nichts verzerrt.",
                      isOn: Binding(get: { model.settings.effects.autoHeadroom }, set: { model.settings.effects.autoHeadroom = $0 }))
            Hairline()
            SettingRow(title: "Grafischer Equalizer", text: "Regler, Bass und Kurve in einem eigenen Fenster.") {
                PillButton(title: "Equalizer öffnen …", icon: Icons.tune, style: .filled) { WindowRouter.shared.openEqualizer() }
            }
        }
        EditorCard(title: "Voreinstellungen") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(EqPresets.all, id: \.id) { p in
                    ChoiceChip(title: p.name, selected: effects.eqEnabled && EqPresets.matching(effects.bandGains)?.id == p.id) {
                        model.settings.effects = model.settings.effects.withPreset(p)
                    }
                }
            }
        }
        EditorCard(title: "Eigene Presets") {
            if model.settings.eqUserPresets.isEmpty {
                Note(text: "Noch keine eigenen Presets. Stelle den Equalizer ein und sichere die Einstellung hier unter einem Namen.")
            }
            ForEach(model.settings.eqUserPresets) { p in
                UserPresetRow(preset: p, active: effects.activeUserPreset(in: model.settings.eqUserPresets)?.id == p.id,
                              renaming: $renaming, renameText: $renameText)
                Hairline()
            }
            HStack(spacing: 8) {
                TextField("Name für die aktuelle Einstellung", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .onSubmit(saveNew)
                PillButton(title: "Als Preset sichern", icon: Icons.save, style: .filled, action: saveNew)
            }
        }
    }

    private func saveNew() {
        var s = model.settings
        let p = s.saveEqPreset(name: newName)
        model.settings = s
        model.toast("Preset „\(p.name)“ gesichert")
        newName = ""
    }
}

private struct UserPresetRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    let preset: EqUserPreset
    let active: Bool
    @Binding var renaming: String?
    @Binding var renameText: String

    var body: some View {
        HStack(spacing: 10) {
            Icon(active ? Icons.checkCircle : Icons.equalizer, size: 16, color: active ? colors.accentText : colors.textSecondary)
            if renaming == preset.id {
                TextField("Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .onSubmit(commitRename)
                PillButton(title: "OK", style: .filled, action: commitRename)
            } else {
                Text(preset.name).textStyle(Typo.bodyLarge).foregroundColor(colors.textPrimary)
                if preset.bassDb != nil {
                    Text("mit Bass").textStyle(Typo.labelSmall).foregroundColor(colors.textTertiary)
                }
            }
            Spacer()
            PillButton(title: "Anwenden", style: .tonal) {
                model.settings.effects = model.settings.effects.withUserPreset(preset)
            }
            GlassMenuButton(icon: Icons.moreHoriz, help: "Preset bearbeiten", width: 260) { menu in
                GlassMenuItem(title: "Umbenennen", icon: Icons.edit) {
                    menu.close()
                    renameText = preset.name
                    renaming = preset.id
                }
                GlassMenuItem(title: "Mit aktueller Einstellung überschreiben", icon: Icons.save) {
                    menu.close()
                    var s = model.settings
                    s.updateEqPreset(id: preset.id)
                    model.settings = s
                    model.toast("Preset „\(preset.name)“ aktualisiert")
                }
                GlassMenuDivider()
                GlassMenuItem(title: "Löschen", icon: Icons.delete, destructive: true) {
                    menu.close()
                    confirmDelete()
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func commitRename() {
        var s = model.settings
        s.renameEqPreset(id: preset.id, to: renameText)
        model.settings = s
        renaming = nil
    }

    private func confirmDelete() {
        let alert = NSAlert()
        alert.messageText = "Preset „\(preset.name)“ löschen?"
        alert.informativeText = "Die aktuelle Equalizer-Einstellung bleibt unverändert."
        alert.addButton(withTitle: "Löschen")
        alert.addButton(withTitle: "Abbrechen")
        if alert.runModal() == .alertFirstButtonReturn {
            var s = model.settings
            s.deleteEqPreset(id: preset.id)
            model.settings = s
        }
    }
}

// MARK: - 9 Tonhöhe

private struct PitchSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let pitch = model.settings.pitch
        EditorCard(title: "Tonhöhe") {
            SettingRow(title: "Modus", text: pitch.mode.description) {
                SegmentedControl(options: [PitchMode.key, PitchMode.varispeed], selection: Binding(get: { model.settings.pitch.mode },
                                                                                                    set: { model.settings.pitch = model.settings.pitch.withMode($0) }),
                                 label: { $0.label })
                    .frame(width: 260)
            }
            Hairline()
            SettingRow(title: "Halbtöne", text: "Feinschritte von 0,1 Halbtönen (10 Cent).") {
                CommitSlider(value: Double(pitch.semitones),
                             range: Double(PitchSettings.minSemitones)...Double(PitchSettings.maxSemitones),
                             step: Double(PitchSettings.fineStep), label: "Tonhöhe",
                             format: { Formatting.semitones(Float($0)) },
                             commit: { model.settings.pitch = model.settings.pitch.withSemitones(Float($0)) })
            }
            Hairline()
            HStack(spacing: 8) {
                PillButton(title: "−0,1", style: .plain) { model.settings.pitch = pitch.withSemitones(pitch.semitones - PitchSettings.fineStep) }
                PillButton(title: "+0,1", style: .plain) { model.settings.pitch = pitch.withSemitones(pitch.semitones + PitchSettings.fineStep) }
                PillButton(title: "−1", style: .plain) { model.settings.pitch = pitch.withSemitones(pitch.semitones - PitchSettings.coarseStep) }
                PillButton(title: "+1", style: .plain) { model.settings.pitch = pitch.withSemitones(pitch.semitones + PitchSettings.coarseStep) }
                Spacer()
                PillButton(title: "Original", icon: Icons.restart, style: .filled) { model.settings.pitch = PitchSettings(mode: pitch.mode) }
                    .disabled(pitch.isOriginal)
            }
        }
        EditorCard(title: "Beim Neustart") {
            ToggleRow(title: "Tonhöhe beibehalten",
                      text: "Aus (Standard, wie unter Android): Nach dem Neustart spielt die Musik wieder in Originaltonhöhe.",
                      isOn: model.binding(\.keepPitchOnRelaunch))
        }
    }
}

// MARK: - 10 Lautstärke

private struct VolumeSettings: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService

    var body: some View {
        EditorCard(title: "Lautstärke") {
            SettingRow(title: "Aktuelle Lautstärke", text: "Wirkt nur auf die Musik dieser App, nicht auf die Systemlautstärke.") {
                CommitSlider(value: Double(player.liveVolume), range: 0...Double(model.settings.maxVolume), step: 0.01, label: "Lautstärke",
                             format: { "\(Int(($0 * 100).rounded())) %" },
                             commit: { v in
                                 player.setLiveVolume(Float(v))
                                 model.settings.effects.volume = Float(v)
                             })
            }
            Hairline()
            SettingRow(title: "Höchste Verstärkung", text: "Obergrenze des Lautstärkereglers. Über 100 % wird digital verstärkt; ein Limiter verhindert Übersteuern.") {
                CommitSlider(value: Double(model.settings.maxVolume), range: 1...3, step: 0.05, label: "Höchste Verstärkung",
                             format: { "\(Int(($0 * 100).rounded())) %" },
                             commit: { v in
                                 model.settings.maxVolume = Float(v)
                                 if player.liveVolume > Float(v) {
                                     player.setLiveVolume(Float(v))
                                     model.settings.effects.volume = Float(v)
                                 }
                             })
            }
            Hairline()
            Note(text: "Schutz vor Übersteuerung: Der Limiter (Apple AUPeakLimiter) begrenzt Spitzen nach Equalizer und Verstärkung – gemessen bleibt der Pegel auch bei 300 % unter Vollaussteuerung.")
        }
    }
}

// MARK: - 11 Liedtexte

private struct LyricsSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        EditorCard(title: "Anzeige") {
            SettingRow(title: "Schriftgröße", text: "In der Liedtext-Seitenleiste und im Player.") {
                CommitSlider(value: model.settings.lyricsFontSize, range: 12...30, step: 1, label: "Schriftgröße",
                             format: { "\(Int($0)) pt" },
                             commit: { model.settings.lyricsFontSize = $0 })
            }
            Hairline()
            ToggleRow(title: "Mitlaufen", text: "Synchronisierte Liedtexte (LRC) scrollen automatisch zur aktuellen Zeile.", isOn: model.binding(\.lyricsAutoScroll))
        }
        EditorCard(title: "Quellen") {
            ToggleRow(title: ".lrc-Dateien verwenden",
                      text: "Ohne eingebetteten Liedtext wird eine gleichnamige .lrc-Datei neben der Musikdatei gelesen.",
                      isOn: model.binding(\.lyricsUseLrcFiles))
            Hairline()
            Note(text: "Liedtexte bearbeiten, synchronisieren (Zeitmarken setzen) sowie als .lrc laden oder sichern: im Informationsfenster eines Titels (⌘I) unter „Liedtext“.")
        }
    }
}

// MARK: - 12 Metadaten

private struct MetadataSettings: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var metadata: MetadataService
    @Environment(\.musicColors) private var colors
    @State private var journals: [TagWriteJournal] = []

    var body: some View {
        EditorCard(title: "Sicheres Schreiben") {
            Note(text: "Änderungen an Tags werden nie direkt in die Originaldatei geschrieben: Die App sichert das Original, bearbeitet eine Kopie, liest sie zur Kontrolle wieder ein und ersetzt das Original erst danach. Bei Fehlern bleibt das Original unverändert; unbekannte Tags bleiben erhalten.")
            ToggleRow(title: "Vor dem Ändern mehrerer Titel nachfragen", isOn: model.binding(\.confirmBeforeWritingTags))
            Hairline()
            SettingRow(title: "Sicherungen aufbewahren", text: "Originale werden so lange aufbewahrt und können so lange wiederhergestellt werden.") {
                Picker("", selection: model.binding(\.backupRetentionDays)) {
                    ForEach([7, 30, 90, 365], id: \.self) { d in Text(verbatim: "\(d) Tage").tag(d) }
                }
                .labelsHidden()
                .frame(width: 120)
            }
            HStack(spacing: 10) {
                PillButton(title: "Sicherungsordner zeigen", icon: Icons.folderOpen, style: .plain) {
                    NSWorkspace.shared.activateFileViewerSelecting([metadata.writer.configuration.backupRoot])
                }
                PillButton(title: "Alte Sicherungen jetzt löschen", style: .plain) { metadata.cleanupBackups(days: model.settings.backupRetentionDays) }
            }
        }
        EditorCard(title: "Zuletzt geändert") {
            if journals.isEmpty {
                Note(text: "Noch keine Änderungen.")
            }
            ForEach(journals.prefix(20), id: \.batchID) { j in
                JournalRow(journal: j) {
                    metadata.undo(batch: j.batchID)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { journals = metadata.recentJournals() }
                }
                Hairline()
            }
        }
        .onAppear { journals = metadata.recentJournals() }
    }
}

private struct JournalRow: View {
    @Environment(\.musicColors) private var colors
    let journal: TagWriteJournal
    let undo: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.date.string(from: journal.created)).textStyle(Typo.bodyMedium)
                Text("\(Formatting.tracks(journal.entries.count)) · " + Array(Set(journal.entries.flatMap(\.fieldsChanged))).sorted().prefix(6).joined(separator: ", "))
                    .textStyle(Typo.labelSmall).foregroundColor(colors.textSecondary).lineLimit(1)
            }
            Spacer()
            if journal.entries.allSatisfy({ $0.undoneAt != nil }) {
                Text("rückgängig gemacht").textStyle(Typo.labelSmall).foregroundColor(colors.textTertiary)
            } else {
                PillButton(title: "Rückgängig", icon: Icons.undo, style: .plain, action: undo)
            }
        }
    }

    static let date: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

// MARK: - 13 Tastaturkurzbefehle

private struct ShortcutSettings: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors

    private static let shortcuts: [(String, String)] = [
        ("Leertaste", "Abspielen / Pause"), ("⌘ →  /  ⌘ ←", "Nächster / vorheriger Titel"), ("⌘ ↑  /  ⌘ ↓", "Lauter / leiser"),
        ("⌘1 … ⌘6", "Bereiche Titel … Favoriten"), ("⌘7 / ⌘8", "Hinzufügen / Studio"), ("⌘F", "Suchen im Bereich"), ("⌘I", "Informationen (Metadaten)"),
        ("⌘L", "Liedtext-Seitenleiste"), ("⌥⌘U", "Warteschlange"), ("⇧⌘F", "Großer Player öffnen/schließen"),
        ("⌥⌘M", "Mini-Player-Fenster"), ("⌥⌘E", "Equalizer"), ("⌘N", "Neue Playlist"), ("⇧⌘O", "Musikordner hinzufügen"),
        ("⌘R", "Bibliothek neu einlesen"), ("⌘,", "Einstellungen"), ("⌥⌘Z", "Letzte Metadaten-Änderung widerrufen"),
        ("⌘[", "Zurück"), ("Eingabe", "Auswahl abspielen"), ("⌫", "Auswahl aus der Bibliothek entfernen"), ("Esc", "Player schließen"),
        ("Leertaste (Studio)", "Auswahl vorhören / Pause"), ("I / O (Studio)", "Start / Ende am Abspielkopf setzen"),
        ("⌘↩ (Studio)", "Exportieren"),
    ]

    var body: some View {
        EditorCard(title: "Medientasten") {
            ToggleRow(title: "Medientasten und Kontrollzentrum",
                      text: "Wiedergabe, Pause, Weiter und Zurück über die Medientasten der Tastatur, AirPods/Kopfhörer und das Kontrollzentrum.",
                      isOn: model.binding(\.mediaKeysEnabled))
        }
        EditorCard(title: "Tastaturkurzbefehle") {
            ForEach(Self.shortcuts, id: \.0) { k, v in
                HStack(spacing: 12) {
                    Text(verbatim: k)
                        .font(Typo.inter(12, .semibold))
                        .foregroundColor(colors.textPrimary)
                        .padding(.horizontal, 8)
                        .frame(minWidth: 120, minHeight: 24, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(colors.textPrimary.opacity(0.06)))
                    Text(v).textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary)
                    Spacer()
                }
            }
            Note(text: "Trackpad: Zusammenziehen/Aufziehen mit zwei Fingern ändert im Raster die Covergröße; Wischen mit zwei Fingern blättert im Cover Flow.")
        }
    }
}

// MARK: - 14 Speicher & Cache

private struct StorageSettings: View {
    @EnvironmentObject private var model: AppModel
    @State private var coverBytes: Int64?
    @State private var oggBytes: Int64?
    @State private var dbBytes: Int64?

    var body: some View {
        EditorCard(title: "Zwischenspeicher") {
            SettingRow(title: "Cover", text: "Verkleinerte Cover für schnelles Scrollen. Belegt: \(coverBytes.map { Formatting.fileSize($0) } ?? "…").") {
                PillButton(title: "Leeren", icon: Icons.cleaning, style: .plain) {
                    ArtworkStore.shared.clearDiskCache()
                    refresh()
                    model.toast("Cover-Zwischenspeicher geleert")
                }
            }
            SettingRow(title: "Höchstens", text: "Ältere Cover werden darüber hinaus automatisch entfernt.") {
                CommitSlider(value: Double(model.settings.coverCacheLimitMB), range: 100...4000, step: 100, label: "Höchstgröße Cover-Zwischenspeicher",
                             format: { "\(Int($0)) MB" },
                             commit: { model.settings.coverCacheLimitMB = Int($0) })
            }
            Hairline()
            SettingRow(title: "Ogg Vorbis", text: "Für die Wiedergabe umgewandelte Ogg-Dateien. Belegt: \(oggBytes.map { Formatting.fileSize($0) } ?? "…").") {
                PillButton(title: "Leeren", icon: Icons.cleaning, style: .plain) {
                    OggTranscoder.clearCache()
                    refresh()
                    model.toast("Ogg-Zwischenspeicher geleert")
                }
            }
        }
        EditorCard(title: "Datenbank") {
            SettingRow(title: "Bibliothek, Playlists, Favoriten, Statistik", text: "Größe: \(dbBytes.map { Formatting.fileSize($0) } ?? "…"). Wird bei jedem Start geprüft; eine beschädigte Datenbank wird gesichert und neu aufgebaut.") {
                PillButton(title: "Sichern …", icon: Icons.backup, style: .plain) { backupDatabase() }
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        let dbPath = model.store.path
        DispatchQueue.global(qos: .utility).async {
            let covers = ArtworkStore.shared.diskUsage()
            let ogg = OggTranscoder.diskUsage()
            let db = ((try? FileManager.default.attributesOfItem(atPath: dbPath))?[.size] as? NSNumber)?.int64Value ?? 0
            DispatchQueue.main.async {
                coverBytes = covers
                oggBytes = ogg
                dbBytes = db
            }
        }
    }

    private func backupDatabase() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Music Library Sicherung.sqlite"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.store.backup(to: url)
            model.toast("Datenbank gesichert")
        } catch {
            model.toast("Sicherung fehlgeschlagen: \(error.localizedDescription)", isError: true)
        }
    }
}

// MARK: - 15 Datenschutz

private struct PrivacySettings: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        EditorCard(title: "Aufzeichnen") {
            ToggleRow(title: "Wiedergabeverlauf speichern", text: "Liste der zuletzt gespielten Titel (Playlists → Verlauf).", isOn: model.binding(\.recordHistory))
            Hairline()
            ToggleRow(title: "Wiedergaben zählen", text: "Grundlage für „Meistgespielt“, „Am wenigsten gespielt“, „Nie gespielt“ und die Sortierung nach Häufigkeit.", isOn: model.binding(\.recordPlayCounts))
            HStack(spacing: 10) {
                PillButton(title: "Verlauf löschen", icon: Icons.delete, style: .plain) { model.clearHistory() }
                    .disabled(model.history.isEmpty)
                PillButton(title: "Alle Zähler zurücksetzen", icon: Icons.restart, style: .plain) { confirmResetStats() }
            }
            .padding(.top, 4)
        }
        EditorCard(title: "Grundsätze") {
            ForEach(["Keine Anmeldung, kein Konto, keine Cloud, kein externer Server.",
                     "Keine Werbung, keine Analyse, keine Telemetrie – die App sendet nichts.",
                     "Favoriten, Playlists, Zähler, Verlauf und Einstellungen liegen nur auf diesem Mac.",
                     "Musikdateien werden nur gelesen – geändert werden sie ausschließlich beim Bearbeiten der Metadaten (mit Sicherung) oder über „In den Papierkorb“."], id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Icon(Icons.check, size: 14, color: colors.accentText)
                    Text(line).textStyle(Typo.bodySmall).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func confirmResetStats() {
        let alert = NSAlert()
        alert.messageText = "Alle Wiedergabezähler zurücksetzen?"
        alert.informativeText = "Zähler und „zuletzt gespielt“ aller Titel werden gelöscht. Favoriten, Playlists und Verlauf bleiben."
        alert.addButton(withTitle: "Zurücksetzen")
        alert.addButton(withTitle: "Abbrechen")
        if alert.runModal() == .alertFirstButtonReturn {
            model.resetStats(model.index.tracks.map(\.uid))
            model.toast("Alle Zähler zurückgesetzt")
        }
    }
}

// MARK: - 16 Über

private struct AboutSettings: View {
    @Environment(\.musicColors) private var colors

    var body: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        EditorCard(title: "Music Library") {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Music Library \(version)").textStyle(Typo.titleLarge)
                    Text(verbatim: "Build \(build) · \(Self.architecture) · macOS \(os.majorVersion).\(os.minorVersion)")
                        .textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary)
                    Text(LiquidGlass.isAvailable ? "Liquid Glass aktiv" : "Glas-Darstellung für macOS \(os.majorVersion) (Liquid Glass ab macOS 26)")
                        .textStyle(Typo.labelSmall).foregroundColor(colors.textTertiary)
                }
            }
            Note(text: "Eigenständige App für die lokale Musiksammlung – die Mac-Fassung der Android-Musikbibliothek. Universal Binary für Apple Silicon und Intel.")
        }
        EditorCard(title: "Verwendete Gestaltungsmittel und Bibliotheken") {
            Note(text: "Schrift „Inter“ © The Inter Project Authors, SIL Open Font License 1.1 · Symbole „Material Symbols Rounded“ © Google, Apache License 2.0 · TagLib 2.3.2 (Mozilla Public License 1.1, unverändert) zum Lesen und Schreiben der Tags · stb_vorbis 1.22 (MIT/Public Domain) zum Abspielen von Ogg Vorbis · Grafik von Plattenspieler, Kassette, CD-Player, Tonbandmaschine und Genre-Titelbildern: eigene Berechnung der App, keine fremden Vorlagen.")
        }
    }

    static var architecture: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #else
        return "Intel (x86_64)"
        #endif
    }
}
