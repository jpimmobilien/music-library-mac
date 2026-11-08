import SwiftUI
import AppKit
import MLStudio

// Einstellungen → „Audio Studio“: Status der Werkzeuge für Internet-Quellen und Standards für neue Exporte
// (Format, Ziel, Dateiname, Finder). Alle Werte wirken sofort und gelten auch im Studio selbst.

struct StudioSettingsPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        StudioSettingsContent(studio: model.studio)
            .onAppear { if !model.studio.demo { model.studio.refreshToolStatus() } }
    }
}

private struct StudioSettingsContent: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        let s = studio.toolStatus
        EditorCard(title: "Werkzeuge für Internet-Quellen") {
            SettingRow(title: "yt-dlp", text: toolText(origin: s.ytDlpOrigin, version: s.ytDlpVersion, purpose: "YouTube, SoundCloud und weitere Seiten")) {
                statusDot(s.ytDlpOrigin != .missing)
            }
            Hairline()
            SettingRow(title: "Deno", text: toolText(origin: s.denoOrigin, version: s.denoVersion, purpose: "zusätzlich für YouTube")) {
                statusDot(s.denoOrigin != .missing)
            }
            Hairline()
            SettingRow(title: "Werkzeuge verwalten", text: "Installieren, aktualisieren oder entfernen – nur auf deinen Wunsch, aus den offiziellen GitHub-Veröffentlichungen, mit Prüfsumme.") {
                PillButton(title: "Verwalten …", icon: Icons.wrench) { StudioToolsSheet.present() }
            }
            Text(StudioText.rightsNote)
                .textStyle(Typo.bodySmall)
                .foregroundColor(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        EditorCard(title: "Standards für neue Exporte") {
            SettingRow(title: "Format", text: studio.options.summary()) {
                SegmentedControl(options: StudioFormat.allCases, selection: Binding(get: { studio.options.format }, set: { studio.setFormat($0) }),
                                 label: { $0.label })
                    .frame(width: 330)
            }
            Hairline()
            SettingRow(title: "Ziel", text: studio.settings.importToLibrary ? "In einen Musikordner speichern und sofort einlesen." : "In einem Ordner speichern, ohne die Bibliothek zu ändern.") {
                SegmentedControl(options: [true, false], selection: $studio.settings.importToLibrary,
                                 label: { $0 ? "Bibliothek" : "Nur speichern" })
                    .frame(width: 230)
            }
            Hairline()
            SettingRow(title: "Dateiname", text: "Vorschau: \(studio.fileNamePreview)") {
                Picker("", selection: Binding(get: { studio.isCustomScheme ? -1 : (FileNameScheme.presets.firstIndex(of: studio.settings.fileNameScheme) ?? 0) },
                                              set: { i in if i >= 0 { studio.settings.fileNameScheme = FileNameScheme.presets[i] } })) {
                    ForEach(Array(FileNameScheme.presets.enumerated()), id: \.offset) { i, scheme in Text(scheme.label).tag(i) }
                    if studio.isCustomScheme { Text("Eigener Name").tag(-1) }
                }
                .labelsHidden()
                .frame(width: 180)
            }
            Hairline()
            SettingRow(title: "Nach dem Export im Finder zeigen") {
                MusicToggle(isOn: $studio.settings.revealAfterExport, label: "Nach dem Export im Finder zeigen")
            }
            Hairline()
            SettingRow(title: "Audio Studio öffnen", text: "Auch über ⌘7 oder den siebten Eintrag der Navigation.") {
                PillButton(title: "Öffnen", icon: Icons.studio) {
                    model.openStudio()
                    if let main = MainWindowRef.window { main.makeKeyAndOrderFront(nil) }
                }
            }
        }
    }

    private func toolText(origin: StudioToolStatus.Origin, version: String?, purpose: String) -> String {
        let state: String
        switch origin {
        case .missing: state = "nicht installiert"
        case .managed: state = "von der App installiert" + (version.map { ", Version \($0)" } ?? "")
        case .system: state = "auf dem Mac vorhanden" + (version.map { ", Version \($0)" } ?? "")
        }
        return "\(purpose) – \(state)"
    }

    private func statusDot(_ ok: Bool) -> some View {
        HStack(spacing: 6) {
            Circle().fill(ok ? Color(nsColor: .systemGreen) : colors.textTertiary.opacity(0.5)).frame(width: 8, height: 8)
            Text(ok ? "Bereit" : "Fehlt")
                .font(Typo.inter(12, .semibold))
                .foregroundColor(ok ? colors.textSecondary : colors.textTertiary)
        }
    }
}
