import SwiftUI
import AppKit
import MLCore
import MLStore
import MLTags

/// Einstellungen (Android `SettingsScreen`), ergänzt um Musikordner, Metadaten-Sicherungen und Wiedergabe.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    @State private var tab = Tab.appearance

    enum Tab: String, CaseIterable, Hashable {
        case appearance, library, playback, metadata, about

        var label: String {
            switch self {
            case .appearance: return "Darstellung"
            case .library: return "Bibliothek"
            case .playback: return "Wiedergabe"
            case .metadata: return "Metadaten"
            case .about: return "Über"
            }
        }

        var icon: String {
            switch self {
            case .appearance: return "tune"
            case .library: return Icons.folder
            case .playback: return Icons.play
            case .metadata: return Icons.editNote
            case .about: return Icons.info
            }
        }
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: 0) {
                SegmentedControl(options: Tab.allCases, selection: $tab, label: { $0.label }, icon: { $0.icon })
                    .frame(maxWidth: 600)
                    .padding(.top, 36)
                    .padding(.horizontal, 24)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch tab {
                        case .appearance: AppearanceSettings()
                        case .library: LibrarySettings()
                        case .playback: PlaybackSettings()
                        case .metadata: MetadataSettings()
                        case .about: AboutSettings()
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(width: 680, height: 640)
    }
}

/// Zeile „Text + Erklärung + Bedienelement“ in einer Glaskarte.
private struct SettingRow<Control: View>: View {
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
        .padding(.vertical, 6)
    }
}

private struct AppearanceSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        EditorCard(title: "Darstellung") {
            SettingRow(title: "Design", text: "Hell, Dunkel oder wie macOS – beide Modi sind eigenständig gestaltet.") {
                SegmentedControl(options: ThemeMode.allCases, selection: Binding(get: { model.settings.themeMode }, set: { model.settings.themeMode = $0 }),
                                 label: { $0.label })
                    .frame(width: 280)
            }
            Hairline()
            SettingRow(title: "Glas-Effekte",
                       text: LiquidGlass.isAvailable
                       ? "Liquid Glass von macOS für Navigation, Mini-Player und Kopfleisten sowie atmosphärische Farbflächen. Ausgeschaltet: ruhige, undurchsichtige Flächen."
                       : "Echte Hintergrundunschärfe für Navigation, Mini-Player und Kopfleisten sowie atmosphärische Farbflächen. Ausgeschaltet: ruhige, undurchsichtige Flächen (spart etwas Rechenleistung).") {
                MusicToggle(isOn: Binding(get: { model.settings.glassEffects }, set: { model.settings.glassEffects = $0 }), label: "Glas-Effekte")
            }
        }
        EditorCard(title: "Player-Design") {
            Text("Vier Designs für den großen Player – mit gleicher Bedienung. Die Auswahl bleibt gespeichert; ein Wechsel unterbricht die Wiedergabe nicht und ändert keine Klangeinstellung.")
                .textStyle(Typo.bodySmall).foregroundColor(.secondary)
            PlayerThemePicker(columns: 4)
            Hairline()
            SettingRow(title: "Klangvisualisierung", text: "Dezente Frequenzbalken bzw. Pegelanzeigen im Player, berechnet aus der tatsächlichen Wiedergabe. Nur aktiv, solange der Player sichtbar ist; aus bei „Bewegung reduzieren“. Beeinflusst den Klang nicht.") {
                MusicToggle(isOn: Binding(get: { model.settings.visualizer }, set: { model.settings.visualizer = $0 }), label: "Klangvisualisierung")
            }
        }
    }
}

private struct LibrarySettings: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        EditorCard(title: "Musikordner") {
            if model.folders.isEmpty {
                Text("Noch keine Musikordner gewählt.").textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary)
            }
            ForEach(model.folders) { f in
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
                    Menu {
                        Button("Entfernen (Titel als nicht verfügbar behalten)") { model.library.removeFolder(f, deleteTracks: false) }
                        Button("Entfernen und Titel aus der Bibliothek löschen") { confirmRemove(f) }
                    } label: {
                        Icon(Icons.moreHoriz, size: 17, color: colors.textSecondary).frame(width: 28, height: 28)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                .padding(.vertical, 4)
                Hairline()
            }
            HStack(spacing: 10) {
                PillButton(title: "Ordner hinzufügen …", icon: Icons.add, style: .filled) { model.library.chooseFolders() }
                PillButton(title: model.scanState.isRunning ? "läuft …" : "Jetzt abgleichen", icon: Icons.refresh) { model.library.rescan(reason: "Einstellungen") }
                    .disabled(model.scanState.isRunning)
                PillButton(title: "Alle Tags neu lesen", style: .plain) { model.library.rescan(reason: "Neu lesen", fullTagRefresh: true) }
                    .disabled(model.scanState.isRunning)
            }
            .padding(.top, 6)
            Text("Neue, geänderte, verschobene und gelöschte Musik wird automatisch erkannt – auch auf externen Laufwerken. Ein manueller Abgleich ist nur ergänzend nötig.")
                .textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).padding(.top, 4)
        }
        EditorCard(title: "Bibliothek") {
            let counts = (try? model.store.counts()) ?? (available: 0, total: 0)
            Text("\(Formatting.tracks(counts.total)) in der Bibliothek" + (counts.total - counts.available > 0 ? " · \(Formatting.tracks(counts.total - counts.available)) derzeit nicht erreichbar" : ""))
                .textStyle(Typo.bodyMedium)
            Text("Favoriten, Playlists, Zähler und Verlauf bleiben erhalten, auch wenn Dateien zeitweise fehlen.")
                .textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary)
            HStack(spacing: 10) {
                PillButton(title: "Duplikate finden", icon: Icons.difference) {
                    model.section = .tracks
                    model.open(.duplicates)
                    NSApp.keyWindow?.performClose(nil)
                }
                PillButton(title: "Datenbank sichern …", icon: Icons.backup, style: .plain) { backupDatabase() }
                PillButton(title: "Zwischenspeicher leeren", style: .plain) {
                    ArtworkStore.shared.clearDiskCache()
                    OggTranscoder.clearCache()
                    model.toast("Cover- und Ogg-Zwischenspeicher geleert")
                }
                .help("Verkleinerte Cover und für die Wiedergabe umgewandelte Ogg-Dateien löschen (werden bei Bedarf neu erstellt)")
            }
        }
    }

    private func confirmRemove(_ f: LibraryFolder) {
        let alert = NSAlert()
        alert.messageText = "„\(f.name)“ entfernen und Titel löschen?"
        alert.informativeText = "Die Titel dieses Ordners werden samt Favoriten, Playlist-Einträgen und Zählern aus der Bibliothek entfernt. Die Musikdateien bleiben unverändert."
        alert.addButton(withTitle: "Entfernen")
        alert.addButton(withTitle: "Abbrechen")
        if alert.runModal() == .alertFirstButtonReturn { model.library.removeFolder(f, deleteTracks: true) }
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

private struct PlaybackSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        EditorCard(title: "Wiedergabe") {
            SettingRow(title: "Beim Start fortsetzen", text: "Warteschlange und Position werden beim nächsten Start wiederhergestellt (pausiert). Lange Titel ab 10 Minuten merken sich zusätzlich ihre Position.") {
                MusicToggle(isOn: Binding(get: { model.settings.resumeOnLaunch }, set: { model.settings.resumeOnLaunch = $0 }), label: "Beim Start fortsetzen")
            }
            Hairline()
            SettingRow(title: "Equalizer und Klang", text: "10-Band-Equalizer, Bass, automatische Aussteuerung, Lautstärke bis 300 % mit Begrenzer.") {
                PillButton(title: "Equalizer …", icon: Icons.tune) { WindowRouter.shared.openEqualizer() }
            }
            Hairline()
            SettingRow(title: "Mediatasten", text: "Wiedergabe, Pause, Weiter und Zurück funktionieren mit den Medientasten der Tastatur, AirPods und im Kontrollzentrum.") { EmptyView() }
        }
        EditorCard(title: "Tastaturkürzel") {
            ForEach([("Leertaste", "Abspielen / Pause"), ("⌘ →  /  ⌘ ←", "Nächster / vorheriger Titel"), ("⌘ ↑  /  ⌘ ↓", "Lauter / leiser"),
                     ("⌘1 … ⌘6", "Bereiche"), ("⌘F", "Suchen"), ("⌘I", "Informationen"), ("⌘L", "Liedtext"), ("⌥⌘U", "Warteschlange"),
                     ("⇧⌘F", "Player öffnen/schließen"), ("⌥⌘M", "Mini-Player"), ("⌥⌘E", "Equalizer"), ("⌘N", "Neue Playlist"),
                     ("Eingabe", "Auswahl abspielen"), ("⌫", "Auswahl entfernen"), ("Esc", "Player schließen")] as [(String, String)], id: \.0) { k, v in
                HStack {
                    Text(k).font(Typo.inter(12, .semibold)).frame(width: 140, alignment: .leading)
                    Text(v).textStyle(Typo.bodySmall)
                    Spacer()
                }
            }
        }
    }
}

private struct MetadataSettings: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var metadata: MetadataService
    @Environment(\.musicColors) private var colors
    @State private var journals: [TagWriteJournal] = []

    var body: some View {
        EditorCard(title: "Sicheres Schreiben") {
            Text("Änderungen an Tags werden nie direkt in die Originaldatei geschrieben: Die App sichert das Original, bearbeitet eine Kopie, liest sie zur Kontrolle wieder ein und ersetzt das Original erst danach. Bei Fehlern bleibt das Original unverändert.")
                .textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary)
            SettingRow(title: "Vor dem Ändern mehrerer Titel nachfragen") {
                MusicToggle(isOn: Binding(get: { model.settings.confirmBeforeWritingTags }, set: { model.settings.confirmBeforeWritingTags = $0 }), label: "Nachfragen")
            }
            Hairline()
            SettingRow(title: "Sicherungen aufbewahren", text: "Originale werden so lange aufbewahrt und können so lange wiederhergestellt werden.") {
                Picker("", selection: Binding(get: { model.settings.backupRetentionDays }, set: { model.settings.backupRetentionDays = $0 })) {
                    ForEach([7, 30, 90, 365], id: \.self) { d in Text("\(d) Tage").tag(d) }
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
                Text("Noch keine Änderungen.").textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary)
            }
            ForEach(journals.prefix(20), id: \.batchID) { j in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Self.date.string(from: j.created)).textStyle(Typo.bodyMedium)
                        Text("\(Formatting.tracks(j.entries.count)) · " + Array(Set(j.entries.flatMap(\.fieldsChanged))).sorted().prefix(6).joined(separator: ", "))
                            .textStyle(Typo.labelSmall).foregroundColor(colors.textSecondary).lineLimit(1)
                    }
                    Spacer()
                    if j.entries.allSatisfy({ $0.undoneAt != nil }) {
                        Text("rückgängig gemacht").textStyle(Typo.labelSmall).foregroundColor(colors.textTertiary)
                    } else {
                        PillButton(title: "Rückgängig", icon: Icons.undo, style: .plain) {
                            metadata.undo(batch: j.batchID)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { journals = metadata.recentJournals() }
                        }
                    }
                }
                Hairline()
            }
        }
        .onAppear { journals = metadata.recentJournals() }
    }

    private static let date: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

private struct AboutSettings: View {
    @Environment(\.musicColors) private var colors

    var body: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        EditorCard(title: "Über die App") {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Music Library \(version)").textStyle(Typo.titleLarge)
                    Text("Build \(build) · \(Self.architecture)").textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary)
                }
            }
            Text("Eigenständige App für die lokale Musiksammlung – die Mac-Fassung der Android-Musikbibliothek.")
                .textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary)
        }
        EditorCard(title: "Datenschutz") {
            ForEach(["Keine Anmeldung, kein Konto, keine Cloud.", "Keine Werbung, keine Analyse, keine Telemetrie – die App sendet nichts.",
                     "Favoriten, Playlists, Zähler, Verlauf und Einstellungen liegen nur auf diesem Mac.",
                     "Musikdateien werden nur gelesen – geändert werden sie ausschließlich beim Bearbeiten der Metadaten (mit Sicherung) oder über „In den Papierkorb“."], id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Icon(Icons.check, size: 14, color: colors.accentText)
                    Text(line).textStyle(Typo.bodySmall)
                }
            }
        }
        EditorCard(title: "Verwendete Gestaltungsmittel und Bibliotheken") {
            Text("Schrift „Inter“ © The Inter Project Authors, SIL Open Font License 1.1 · Symbole „Material Symbols Rounded“ © Google, Apache License 2.0 · TagLib 2.3.2 (Mozilla Public License 1.1, unverändert) zum Lesen und Schreiben der Tags · stb_vorbis 1.22 (MIT/Public Domain) zum Abspielen von Ogg Vorbis · Grafik von Plattenspieler, Kassette, CD-Player und Genre-Titelbildern: eigene Berechnung der App, keine fremden Vorlagen.")
                .textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary)
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
