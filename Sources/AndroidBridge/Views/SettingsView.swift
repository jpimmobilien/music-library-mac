import SwiftUI
import AppKit
import ABCore

/// Einstellungen als Seite im Hauptfenster (⌘,).
struct SettingsPage: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var favorites: FavoritesStore
    @ObservedObject var recents: RecentsStore
    @ObservedObject var history: HistoryStore
    @State private var category: SettingsCategory = .general

    var body: some View {
        PageScaffold(title: "Einstellungen", subtitle: category.subtitle) {
            GlassSegmented(selection: $category, options: SettingsCategory.allCases.map {
                SegmentOption(value: $0, title: nil, symbol: $0.symbol, help: $0.title)
            })
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    Text(category.title).font(Typo.title).foregroundStyle(Palette.textPrimary)
                    switch category {
                    case .general: GeneralSettings(settings: settings)
                    case .appearance: AppearanceSettings(settings: settings)
                    case .transfers: TransferSettings(settings: settings)
                    case .devices: DeviceSettings(settings: settings)
                    case .privacy: PrivacySettings(settings: settings, recents: recents, history: history, favorites: favorites)
                    case .about: AboutSettings()
                    }
                }
                .reportsScrollEdge()
                .padding(.horizontal, Spacing.gutter)
                .padding(.bottom, 40)
                .frame(maxWidth: 780, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, appearance, transfers, devices, privacy, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Allgemein"
        case .appearance: return "Darstellung"
        case .transfers: return "Übertragungen"
        case .devices: return "Geräte"
        case .privacy: return "Datenschutz"
        case .about: return "Über Android Bridge"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Start, Dateimanager und Zielordner"
        case .appearance: return "Erscheinungsbild, Akzent, Glas und Animationen"
        case .transfers: return "Konflikte, Prüfung, versteckte Dateien"
        case .devices: return "Verbindung, andere Programme, gemerkte Geräte"
        case .privacy: return "Lokale Listen und Berechtigungen"
        case .about: return "Version, Systeminformationen und Lizenzen"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .transfers: return "arrow.up.arrow.down"
        case .devices: return "smartphone"
        case .privacy: return "hand.raised"
        case .about: return "info.circle"
        }
    }
}

/// Ordnerwahl.
private struct FolderRow: View {
    let title: String
    @Binding var path: String

    var body: some View {
        LabeledRow(title: title, detail: path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")) {
            Button("Wählen …") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.canCreateDirectories = true
                panel.directoryURL = URL(fileURLWithPath: path)
                if panel.runModal() == .OK, let url = panel.url { path = url.path }
            }
            .buttonStyle(GlassButtonStyle(compact: true))
        }
    }
}

private struct ToggleRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        LabeledRow(title: title, detail: detail) {
            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden()
        }
    }
}

private struct RowDivider: View {
    var body: some View { Divider().opacity(0.5) }
}

struct GeneralSettings: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            GlassSection(title: "Start", symbol: "power",
                         footer: "Android Bridge läuft nach dem Schließen des Fensters weiter, solange die App geöffnet ist, und erkennt angeschlossene Telefone sofort.") {
                ToggleRow(title: "Bei der Anmeldung starten", isOn: $settings.launchAtLogin)
                if let e = settings.launchAtLoginError { Text(e).font(Typo.caption).foregroundStyle(Palette.danger) }
                RowDivider()
                ToggleRow(title: "Beim Anschließen eines Geräts in den Vordergrund holen", isOn: $settings.bringToFrontOnConnect)
            }
            GlassSection(title: "Dateimanager", symbol: "folder") {
                LabeledRow(title: "Standardansicht") {
                    Picker("", selection: $settings.defaultLayout) {
                        ForEach([FileManagerLayout.dual, .single]) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                RowDivider()
                FolderRow(title: "Standard-Zielordner", path: $settings.downloadFolderPath)
                RowDivider()
                LabeledRow(title: "Hochladen ohne geöffneten Unterordner") {
                    Picker("", selection: $settings.uploadTarget) {
                        ForEach(UploadTarget.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
            }
            GlassSection(title: "Intelligente Zielordner", symbol: "wand.and.stars",
                         footer: "Gilt für „Auf den Mac übertragen“ in Fotos & Videos, in der Einzelspalten-Ansicht und in der Vorschau. Im Zwei-Spalten-Modus ist das Ziel der links geöffnete Mac-Ordner.") {
                ToggleRow(title: "Nach Dateiart in passende Ordner übertragen", isOn: $settings.smartDestinations)
                RowDivider()
                FolderRow(title: "Fotos", path: $settings.photoDestination).disabled(!settings.smartDestinations)
                FolderRow(title: "Videos", path: $settings.videoDestination).disabled(!settings.smartDestinations)
                FolderRow(title: "Dokumente", path: $settings.documentDestination).disabled(!settings.smartDestinations)
            }
        }
    }
}

struct AppearanceSettings: View {
    @ObservedObject var settings: SettingsStore
    @AppStorage(MacAppearance.storageKey) private var macFinish = "auto"
    private let mac = MacHardware.current

    private func finishButton(_ f: MacFinish?) -> some View {
        let selected = f.map { MacAppearance.finish(for: mac, stored: macFinish) == $0 && macFinish != "auto" } ?? (macFinish == "auto")
        return Button { macFinish = f?.rawValue ?? "auto" } label: {
            Group {
                if let f {
                    Circle().fill(LinearGradient(colors: [f.metal.0, f.metal.1], startPoint: .top, endPoint: .bottom))
                } else {
                    Circle().fill(Palette.fieldFill).overlay(Text("A").font(.ui(10, .bold)).foregroundStyle(Palette.textSecondary))
                }
            }
            .frame(width: 22, height: 22)
            .overlay(Circle().strokeBorder(Palette.accent, lineWidth: selected ? 2 : 0).padding(-3))
            .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(f?.title ?? "Automatisch (\(mac.suggestedFinish.title))")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            GlassSection(title: "Erscheinungsbild", symbol: "circle.lefthalf.filled") {
                LabeledRow(title: "Modus") {
                    GlassSegmented(selection: $settings.appearance, options: AppearanceMode.allCases.map { SegmentOption(value: $0, title: $0.title) })
                }
                RowDivider()
                LabeledRow(title: "Akzentfarbe für Systemelemente", detail: "Auswahl in Listen, Schalter und Fortschrittsbalken.") {
                    HStack(spacing: 8) {
                        ForEach(AccentChoice.allCases) { a in
                            Button { settings.accent = a } label: {
                                Circle().fill(a.color)
                                    .frame(width: 20, height: 20)
                                    .overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: settings.accent == a ? 2 : 0))
                                    .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 1))
                                    .shadow(color: a.color.opacity(settings.accent == a ? 0.5 : 0), radius: 4)
                            }
                            .buttonStyle(.plain)
                            .help(a.title)
                        }
                    }
                }
            }
            GlassSection(title: "Ihr Mac", symbol: "laptopcomputer",
                         footer: "Android Bridge erkennt das Modell (\(mac.identifier)) und zeichnet seine Bauform. Die Gehäusefarbe lässt sich nicht auslesen – wählen Sie sie hier.") {
                HStack(alignment: .center, spacing: 20) {
                    Group {
                        if let photo = MacPhoto.front(for: mac) {
                            PhotoLaptop(photo: photo) { MiniAppScreen(connected: false, deviceName: "") }
                        } else if mac.form.isLaptop {
                            PerspectiveLaptop(hardware: mac) { MiniAppScreen(connected: false, deviceName: "") }
                        } else {
                            MacRender(width: 150, hardware: mac) { ScaledScreen { MiniAppScreen(connected: false, deviceName: "") } }
                        }
                    }
                    .frame(width: 190, height: 130)
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mac.familyName).font(.ui(15, .semibold)).foregroundStyle(Palette.textPrimary)
                            if let d = mac.detailName { Text(d).font(Typo.callout).foregroundStyle(Palette.textSecondary) }
                        }
                        HStack(spacing: 8) {
                            finishButton(nil)
                            ForEach(MacFinish.options(for: mac.form)) { f in finishButton(f) }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            GlassSection(title: "Effekte", symbol: "sparkles",
                         footer: LiquidGlass.isAvailable ? "Auf diesem Mac wird natives Liquid Glass (macOS 26) verwendet."
                                                         : "Auf diesem macOS wird eine gleichwertige Glasdarstellung mit Systemmaterialien verwendet.") {
                ToggleRow(title: "Animationen", isOn: $settings.animations)
                RowDivider()
                ToggleRow(title: "Glaseffekte", detail: "Ausgeschaltet: ruhige, deckende Flächen.", isOn: $settings.glassEffects)
            }
        }
    }
}

struct TransferSettings: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            GlassSection(title: "Übertragung", symbol: "arrow.up.arrow.down",
                         footer: "Jede Übertragung wird mindestens über die Dateigröße geprüft. Mit Prüfsumme wird die Datei zusätzlich vom Ziel erneut gelesen und verglichen.") {
                LabeledRow(title: "Bei vorhandenen Dateien") {
                    Picker("", selection: $settings.conflictResolution) {
                        ForEach(ConflictResolution.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                RowDivider()
                LabeledRow(title: "Prüfung nach der Übertragung") {
                    Picker("", selection: $settings.verification) {
                        ForEach(VerificationLevel.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                RowDivider()
                ToggleRow(title: "Änderungsdatum übernehmen", isOn: $settings.preserveDates)
            }
            GlassSection(title: "Versteckte Dateien", symbol: "eye.slash",
                         footer: "Versteckte Android-Dateien werden nie verworfen – sie werden beim Kopieren ganzer Ordner immer mitübertragen.") {
                ToggleRow(title: "macOS-Metadaten nicht aufs Telefon kopieren", detail: ".DS_Store, ._Dateien", isOn: $settings.skipMacMetadata)
                RowDivider()
                ToggleRow(title: "Versteckte Android-Dateien anzeigen", detail: "z. B. .nomedia", isOn: $settings.showHiddenAndroidFiles)
            }
            GlassSection(title: "Mitteilungen und Verlauf", symbol: "bell") {
                ToggleRow(title: "Mitteilung nach abgeschlossener Übertragung", isOn: $settings.notifications)
                RowDivider()
                ToggleRow(title: "Verlauf abgeschlossener Übertragungen führen", isOn: $settings.keepHistory)
            }
        }
    }
}

struct DeviceSettings: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            GlassSection(title: "Verbindung", symbol: "cable.connector") {
                ToggleRow(title: "Unterstützte Geräte automatisch verbinden", isOn: $settings.autoConnect)
                RowDivider()
                ToggleRow(title: "Einstellungen je Gerät merken", detail: "Name, letzter Ordner, Speicherwahl", isOn: $settings.rememberDevicePreferences)
                RowDivider()
                LabeledRow(title: "Zeitlimit für Antworten") {
                    HStack {
                        Slider(value: $settings.connectionTimeout, in: 10...120, step: 5).frame(width: 180)
                        Text("\(Int(settings.connectionTimeout)) s").font(Typo.body).monospacedDigit().frame(width: 40)
                    }
                }
            }
            GlassSection(title: "Andere Programme", symbol: "app.badge",
                         footer: "macOS beansprucht angeschlossene Telefone manchmal für „Digitale Bilder“ bzw. „Fotos“. Android Bridge kann diesen Dienst (ptpcamerad) kurz beenden; macOS startet ihn bei Bedarf selbst wieder.") {
                ToggleRow(title: "Bei Belegung automatisch freigeben", detail: "Android File Transfer, macOS-Fotodienst …",
                          isOn: $settings.releasePhotoServiceAutomatically)
            }
            GlassSection(title: "Gemerkte Geräte", symbol: "smartphone") {
                if settings.devicePreferences.isEmpty {
                    Text("Keine").font(Typo.body).foregroundStyle(Palette.textSecondary)
                } else {
                    ForEach(settings.devicePreferences.keys.sorted(), id: \.self) { serial in
                        LabeledRow(title: settings.devicePreferences[serial]?.customName ?? "Gerät …\(serial.suffix(4))") {
                            Button("Vergessen") { settings.devicePreferences[serial] = nil }
                                .buttonStyle(GlassButtonStyle(compact: true))
                        }
                    }
                }
            }
        }
    }
}

struct PrivacySettings: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var recents: RecentsStore
    @ObservedObject var history: HistoryStore
    @ObservedObject var favorites: FavoritesStore
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            GlassSection(title: "Grundsätze", symbol: "lock.shield") {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Alle Übertragungen laufen ausschließlich lokal per USB zwischen Telefon und Mac.", systemImage: "lock.shield")
                    Label("Kein Konto, keine Cloud, keine Telemetrie, keine Verbindung ins Internet.", systemImage: "network.slash")
                    Label("Vorschaubilder liegen nur im Arbeitsspeicher; Vorschaudateien werden beim Schließen gelöscht.", systemImage: "memorychip")
                    Label("Das Diagnoseprotokoll enthält keine Dateinamen oder Inhalte.", systemImage: "doc.text.magnifyingglass")
                }
                .font(Typo.body)
            }
            GlassSection(title: "Lokale Listen", symbol: "list.bullet") {
                ToggleRow(title: "„Zuletzt verwendet“ führen", isOn: $settings.recentFilesEnabled)
                RowDivider()
                ToggleRow(title: "Übertragungsverlauf führen", isOn: $settings.keepHistory)
                RowDivider()
                HStack {
                    Button("Zuletzt verwendet löschen") { recents.clear() }.disabled(recents.recents.isEmpty)
                    Button("Verlauf löschen") { history.clear() }.disabled(history.records.isEmpty)
                }
                .buttonStyle(GlassButtonStyle(compact: true))
            }
            GlassSection(title: "Berechtigungen", symbol: "checkmark.shield") {
                Text("Für Ordner wie Schreibtisch, Dokumente, Downloads oder externe Laufwerke fragt macOS beim ersten Zugriff nach. Sie können das jederzeit unter Systemeinstellungen → Datenschutz & Sicherheit → Dateien und Ordner ändern. Für den USB-Zugriff ist keine Berechtigung und kein Treiber nötig.")
                    .font(Typo.callout).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Alle Einstellungen zurücksetzen …") { confirmReset = true }
                .buttonStyle(GlassButtonStyle(destructive: true))
        }
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
        VStack(alignment: .leading, spacing: Spacing.xl) {
            HStack(spacing: 18) {
                AppMark(size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Android Bridge").font(.display(26, .bold))
                    Text("Version \(info["CFBundleShortVersionString"] as? String ?? "–") (Build \(info["CFBundleVersion"] as? String ?? "–"))")
                        .font(Typo.body).foregroundStyle(Palette.textSecondary)
                }
            }
            GlassSection(title: "System", symbol: "desktopcomputer") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow { Text("Architektur").foregroundStyle(Palette.textSecondary); Text(SystemInfo.architecture) }
                    GridRow { Text("Universal-App").foregroundStyle(Palette.textSecondary); Text("Apple Silicon + Intel") }
                    GridRow { Text("macOS").foregroundStyle(Palette.textSecondary); Text(ProcessInfo.processInfo.operatingSystemVersionString) }
                    GridRow { Text("Unterstützt").foregroundStyle(Palette.textSecondary); Text("macOS 13 Ventura oder neuer") }
                    GridRow { Text("Liquid Glass").foregroundStyle(Palette.textSecondary); Text(LiquidGlass.isAvailable ? "nativ" : "Systemmaterialien (Rückfall)") }
                }
                .font(Typo.body)
            }
            GlassSection(title: "Open-Source-Lizenzen", symbol: "doc.plaintext") {
                Text(Self.licenses)
                    .font(Typo.callout)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Updates: Android Bridge prüft nicht selbst auf Updates (keine Netzwerkverbindungen). Neue Versionen erhalten Sie als DMG.")
                .font(Typo.caption).foregroundStyle(Palette.textTertiary)
        }
    }

    static let licenses = """
    Android Bridge verwendet ausschließlich Apple-Systemframeworks (SwiftUI, AppKit, IOKit, IOUSBHost, QuickLook, AVKit, \
    CryptoKit) und die Systemschrift SF Pro, dazu eine eigene Implementierung des Media Transfer Protocol (MTP) nach der \
    öffentlichen USB-IF-Spezifikation „Media Transfer Protocol v1.1“ und ISO 15740 (PTP). \
    Alle Grafiken der App sind eigens gezeichnet.
    """
}
