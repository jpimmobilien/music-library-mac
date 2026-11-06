import SwiftUI
import AppKit
import ABCore

/// Einstellungsfenster.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var favorites: FavoritesStore
    @ObservedObject var recents: RecentsStore
    @ObservedObject var history: HistoryStore

    var body: some View {
        TabView {
            GeneralSettings(settings: settings)
                .tabItem { Label("Allgemein", systemImage: "gearshape") }
            AppearanceSettings(settings: settings)
                .tabItem { Label("Darstellung", systemImage: "paintbrush") }
            TransferSettings(settings: settings)
                .tabItem { Label("Übertragungen", systemImage: "arrow.up.arrow.down") }
            DeviceSettings(settings: settings)
                .tabItem { Label("Geräte", systemImage: "smartphone") }
            PrivacySettings(settings: settings, recents: recents, history: history, favorites: favorites)
                .tabItem { Label("Datenschutz", systemImage: "hand.raised") }
            AboutSettings()
                .tabItem { Label("Über", systemImage: "info.circle") }
        }
        .frame(width: 620)
        .tint(settings.accent.color)
        .preferredColorScheme(settings.appearance.colorScheme)
    }
}

private struct FolderField: View {
    let title: String
    @Binding var path: String

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text(path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    .lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 260, alignment: .trailing)
                Button("Wählen …") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    panel.directoryURL = URL(fileURLWithPath: path)
                    if panel.runModal() == .OK, let url = panel.url { path = url.path }
                }
            }
        }
    }
}

struct GeneralSettings: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Bei der Anmeldung starten", isOn: $settings.launchAtLogin)
                if let e = settings.launchAtLoginError { Text(e).font(.caption).foregroundStyle(Palette.danger) }
                Toggle("Beim Anschließen eines Geräts in den Vordergrund holen", isOn: $settings.bringToFrontOnConnect)
                Text("Android Bridge läuft nach dem Schließen des Fensters weiter, solange die App geöffnet ist, und erkennt angeschlossene Telefone sofort.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Dateimanager") {
                Picker("Standardansicht", selection: $settings.defaultLayout) {
                    ForEach(FileManagerLayout.allCases) { Text($0.title).tag($0) }
                }
                FolderField(title: "Standard-Zielordner", path: $settings.downloadFolderPath)
                Picker("Hochladen ohne geöffneten Unterordner", selection: $settings.uploadTarget) {
                    ForEach(UploadTarget.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Intelligente Zielordner") {
                Toggle("Nach Dateiart in passende Ordner übertragen", isOn: $settings.smartDestinations)
                FolderField(title: "Fotos", path: $settings.photoDestination).disabled(!settings.smartDestinations)
                FolderField(title: "Videos", path: $settings.videoDestination).disabled(!settings.smartDestinations)
                FolderField(title: "Dokumente", path: $settings.documentDestination).disabled(!settings.smartDestinations)
                Text("Gilt für „Auf den Mac übertragen“ in der Galerie, in der Einzelspalten-Ansicht und in der Vorschau. Im Zwei-Spalten-Modus ist das Ziel der links geöffnete Mac-Ordner.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 520)
    }
}

struct AppearanceSettings: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Erscheinungsbild", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Akzentfarbe", selection: $settings.accent) {
                    ForEach(AccentChoice.allCases) { a in
                        HStack { Circle().fill(a.color).frame(width: 10, height: 10); Text(a.title) }.tag(a)
                    }
                }
            }
            Section {
                Toggle("Animationen", isOn: $settings.animations)
                Toggle("Glaseffekte", isOn: $settings.glassEffects)
                Text(LiquidGlass.isAvailable ? "Auf diesem Mac wird natives Liquid Glass (macOS 26) verwendet."
                     : "Auf diesem macOS wird eine gleichwertige Glasdarstellung mit Systemmaterialien verwendet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
    }
}

struct TransferSettings: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Bei vorhandenen Dateien", selection: $settings.conflictResolution) {
                    ForEach(ConflictResolution.allCases) { Text($0.title).tag($0) }
                }
                Picker("Prüfung nach der Übertragung", selection: $settings.verification) {
                    ForEach(VerificationLevel.allCases) { Text($0.title).tag($0) }
                }
                Text("Jede Übertragung wird mindestens über die Dateigröße geprüft. Mit Prüfsumme wird die Datei zusätzlich vom Ziel erneut gelesen und verglichen.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Änderungsdatum übernehmen", isOn: $settings.preserveDates)
            }
            Section("Versteckte Dateien") {
                Toggle("macOS-Metadaten nicht aufs Telefon kopieren (.DS_Store, ._Dateien)", isOn: $settings.skipMacMetadata)
                Toggle("Versteckte Android-Dateien anzeigen (z. B. .nomedia)", isOn: $settings.showHiddenAndroidFiles)
                Text("Versteckte Android-Dateien werden nie verworfen – sie werden beim Kopieren ganzer Ordner immer mitübertragen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Mitteilungen und Verlauf") {
                Toggle("Mitteilung nach abgeschlossener Übertragung", isOn: $settings.notifications)
                Toggle("Verlauf abgeschlossener Übertragungen führen", isOn: $settings.keepHistory)
            }
        }
        .formStyle(.grouped)
        .frame(height: 470)
    }
}

struct DeviceSettings: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Unterstützte Geräte automatisch verbinden", isOn: $settings.autoConnect)
                Toggle("Einstellungen je Gerät merken (Name, letzter Ordner)", isOn: $settings.rememberDevicePreferences)
                LabeledContent("Zeitlimit für Antworten") {
                    HStack {
                        Slider(value: $settings.connectionTimeout, in: 10...120, step: 5).frame(width: 200)
                        Text("\(Int(settings.connectionTimeout)) s").monospacedDigit().frame(width: 40)
                    }
                }
            }
            Section("Andere Programme") {
                Toggle("macOS-Fotodienst bei Belegung automatisch freigeben", isOn: $settings.releasePhotoServiceAutomatically)
                Text("macOS beansprucht angeschlossene Telefone manchmal für „Digitale Bilder“ bzw. „Fotos“. Android Bridge kann diesen Dienst (ptpcamerad) kurz beenden; macOS startet ihn bei Bedarf selbst wieder.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Gemerkte Geräte") {
                if settings.devicePreferences.isEmpty {
                    Text("Keine").foregroundStyle(.secondary)
                } else {
                    ForEach(settings.devicePreferences.keys.sorted(), id: \.self) { serial in
                        HStack {
                            Text(settings.devicePreferences[serial]?.customName ?? "Gerät …\(serial.suffix(4))")
                            Spacer()
                            Button("Vergessen") { settings.devicePreferences[serial] = nil }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 470)
    }
}

struct PrivacySettings: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var recents: RecentsStore
    @ObservedObject var history: HistoryStore
    @ObservedObject var favorites: FavoritesStore
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                Label("Alle Übertragungen laufen ausschließlich lokal per USB zwischen Telefon und Mac.", systemImage: "lock.shield")
                Label("Kein Konto, keine Cloud, keine Telemetrie, keine Verbindung ins Internet.", systemImage: "network.slash")
                Label("Vorschaubilder liegen nur im Arbeitsspeicher; Vorschaudateien werden beim Schließen gelöscht.", systemImage: "memorychip")
                Label("Das Diagnoseprotokoll enthält keine Dateinamen oder Inhalte.", systemImage: "doc.text.magnifyingglass")
            }
            .font(.system(size: 12.5))
            Section("Lokale Listen") {
                Toggle("„Zuletzt verwendet“ führen", isOn: $settings.recentFilesEnabled)
                Toggle("Übertragungsverlauf führen", isOn: $settings.keepHistory)
                HStack {
                    Button("Zuletzt verwendet löschen") { recents.clear() }.disabled(recents.recents.isEmpty)
                    Button("Verlauf löschen") { history.clear() }.disabled(history.records.isEmpty)
                }
            }
            Section("Berechtigungen") {
                Text("Für Ordner wie Schreibtisch, Dokumente, Downloads oder externe Laufwerke fragt macOS beim ersten Zugriff nach. Sie können das jederzeit unter Systemeinstellungen → Datenschutz & Sicherheit → Dateien und Ordner ändern. Für den USB-Zugriff ist keine Berechtigung und kein Treiber nötig.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Alle Einstellungen zurücksetzen …", role: .destructive) { confirmReset = true }
            }
        }
        .formStyle(.grouped)
        .frame(height: 470)
        .confirmationDialog("Alle Einstellungen zurücksetzen?", isPresented: $confirmReset) {
            Button("Zurücksetzen", role: .destructive) { settings.resetAll() }
        } message: {
            Text("Favoriten, Verlauf und Ihre Dateien bleiben erhalten.")
        }
    }
}

struct AboutSettings: View {
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    var body: some View {
        VStack(spacing: 14) {
            AppMark(size: 72)
            Text("Android Bridge").font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Version \(info["CFBundleShortVersionString"] as? String ?? "–") (Build \(info["CFBundleVersion"] as? String ?? "–"))")
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow { Text("Architektur").foregroundStyle(.secondary); Text(SystemInfo.architecture) }
                GridRow { Text("Universal-App").foregroundStyle(.secondary); Text("Apple Silicon + Intel") }
                GridRow { Text("macOS").foregroundStyle(.secondary); Text(ProcessInfo.processInfo.operatingSystemVersionString) }
                GridRow { Text("Unterstützt").foregroundStyle(.secondary); Text("macOS 13 Ventura oder neuer") }
                GridRow { Text("Liquid Glass").foregroundStyle(.secondary); Text(LiquidGlass.isAvailable ? "nativ" : "Systemmaterialien (Rückfall)") }
            }
            .font(.system(size: 12.5))
            GroupBox("Open-Source-Lizenzen") {
                ScrollView {
                    Text(Self.licenses)
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 110)
            }
            Text("Updates: Android Bridge prüft nicht selbst auf Updates (keine Netzwerkverbindungen). Neue Versionen erhalten Sie als DMG.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(height: 520)
    }

    static let licenses = """
    Android Bridge verwendet ausschließlich Apple-Systemframeworks (SwiftUI, AppKit, IOKit, IOUSBHost, \
    QuickLook, AVKit, CryptoKit) und eine eigene Implementierung des Media Transfer Protocol (MTP) nach der \
    öffentlichen USB-IF-Spezifikation „Media Transfer Protocol v1.1“ und ISO 15740 (PTP).

    Es sind keine Bibliotheken Dritter eingebunden; daher gelten keine zusätzlichen Lizenzbedingungen.
    """
}
