import SwiftUI
import AppKit
import MLCore
import MLStudio
import StudioEngine

// Einstellungen → „KI-Musik“: Hardware, Umgebung, Modelle (Größe, Version, laden, entfernen), Speicher freigeben,
// Ort der Kreationen, Protokoll. Nichts wird ohne Klick geladen.

struct KIMusicSettingsPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        KIMusicSettingsContent(ki: model.ki)
            .onAppear { model.ki.refreshSetup() }
    }
}

private struct KIMusicSettingsContent: View {
    @ObservedObject var ki: KIMusicModel
    @Environment(\.musicColors) private var colors
    @State private var confirmRemoveAll = false

    var body: some View {
        EditorCard(title: "Dieser Mac") {
            SettingRow(title: "Eignung", text: supportText) {
                Circle().fill(ki.support.isUsable ? Color(argb: 0xFF34C759) : colors.danger).frame(width: 9, height: 9)
            }
            if let free = ki.freeSpace {
                Hairline()
                SettingRow(title: "Freier Speicher", text: "Für Umgebung und Grundpaket werden etwa 13 GB gebraucht.") {
                    Text(Formatting.fileSize(free)).textStyle(Typo.labelLarge).foregroundColor(colors.textSecondary)
                }
            }
        }
        if ki.support.isUsable {
            EditorCard(title: "Umgebung") {
                SettingRow(title: "Python mit ACE-Step 1.5", text: environmentText) {
                    if ki.setup == .needsEnvironment {
                        PillButton(title: "Einrichten …", icon: Icons.download, style: .filled) { ki.installEverything() }
                            .disabled(ki.installing)
                    } else {
                        Text("bereit").textStyle(Typo.labelLarge).foregroundColor(colors.textSecondary)
                    }
                }
                Hairline()
                SettingRow(title: "KI-Prozess beenden nach", text: "Ohne Nutzung wird der Rechenprozess beendet und sein Arbeitsspeicher freigegeben. Im Leerlauf rechnet nichts.") {
                    Picker("", selection: $ki.unloadMinutes) {
                        Text("2 Minuten").tag(2)
                        Text("10 Minuten").tag(10)
                        Text("30 Minuten").tag(30)
                        Text("nie").tag(0)
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                Hairline()
                SettingRow(title: "Protokoll", text: "Meldungen des KI-Prozesses (bei Fehlern hilfreich).") {
                    PillButton(title: "Im Finder zeigen", style: .plain) { ki.revealLog() }
                }
            }
            EditorCard(title: "Modelle") {
                modelRow(.core, removable: true)
                ForEach(KIModel.optional) { m in
                    Hairline()
                    modelRow(m, removable: true)
                }
                if case .running(let title, let p) = ki.installTask {
                    Hairline()
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(title).textStyle(Typo.titleSmall).foregroundColor(colors.textPrimary)
                            Spacer()
                            PillButton(title: "Abbrechen", style: .plain) { ki.cancelInstall() }
                        }
                        if let f = p.fraction { ProgressView(value: f).tint(colors.accent) } else { ProgressView().progressViewStyle(.linear) }
                        Text(p.step).textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).lineLimit(2)
                    }
                    .padding(.vertical, 6)
                }
                if case .failed(let message) = ki.installTask {
                    Hairline()
                    Text(message).textStyle(Typo.bodySmall).foregroundColor(colors.danger).fixedSize(horizontal: false, vertical: true)
                }
            }
            EditorCard(title: "Kreationen und Speicher") {
                SettingRow(title: "Ordner der Kreationen", text: ki.creationsFolder.path + " – gehört nicht zur Musikbibliothek; übernehmen nur auf Wunsch.") {
                    PillButton(title: "Öffnen", style: .plain) {
                        try? FileManager.default.createDirectory(at: ki.creationsFolder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(ki.creationsFolder)
                    }
                }
                Hairline()
                SettingRow(title: "KI-Musik vollständig entfernen", text: "Löscht Umgebung und alle Modelle. Deine Kreationen bleiben erhalten.") {
                    PillButton(title: confirmRemoveAll ? "Wirklich entfernen" : "Entfernen …", icon: Icons.delete, style: .plain) {
                        if confirmRemoveAll { ki.removeEverything(); confirmRemoveAll = false } else { confirmRemoveAll = true }
                    }
                    .disabled(ki.installing || ki.isWorking)
                }
            }
            EditorCard(title: "Lizenzen") {
                SettingRow(title: "ACE-Step 1.5", text: "Quelltext MIT (© 2026 ACEStep), Modelle MIT laut Modellkarte. Erzeugte Musik darf laut den Entwicklern kommerziell genutzt werden. Die App liefert weder Quelltext noch Modelle mit – beides wird auf Wunsch von den offiziellen Quellen geladen.") { EmptyView() }
            }
        }
    }

    private var supportText: String {
        switch ki.support {
        case .supported: return "Apple-Chip mit genug Arbeitsspeicher – alle Funktionen."
        case .limited(_, let reason): return reason
        case .unsupported(let reason): return reason
        }
    }

    private var environmentText: String {
        let s = ki.installState
        var parts: [String] = ["ACE-Step \(String((s.aceCommit ?? KIInstaller.aceCommit).prefix(7)))"]
        if let uv = s.uvVersion { parts.append("uv \(uv)") }
        if let d = s.environmentDate { parts.append("eingerichtet \(d.formatted(date: .abbreviated, time: .omitted))") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func modelRow(_ m: KIModel, removable: Bool) -> some View {
        let installed = ki.isInstalled(m)
        let info = ki.installState.models[m.id]
        SettingRow(title: m.title, text: modelText(m, installed: installed, info: info)) {
            if installed {
                PillButton(title: "Entfernen", icon: Icons.delete, style: .plain) { ki.remove(m) }
                    .disabled(ki.installing || ki.isWorking)
            } else {
                PillButton(title: "Laden", icon: Icons.download, style: .tonal) {
                    if m.core { ki.installEverything() } else { ki.download(m) }
                }
                .disabled(ki.installing || ki.setup == .needsEnvironment && !m.core)
            }
        }
    }

    private func modelText(_ m: KIModel, installed: Bool, info: KIInstaller.State.Model?) -> String {
        var parts = [m.purpose]
        if let info, installed {
            parts.append("\(Formatting.fileSize(info.bytes)) · Stand \(String(info.revision.prefix(7)))")
        } else if let b = m.bytes {
            parts.append((m.approximate ? "ca. " : "") + Formatting.fileSize(b))
        }
        parts.append("Lizenz \(m.license)")
        return parts.joined(separator: " · ")
    }
}
