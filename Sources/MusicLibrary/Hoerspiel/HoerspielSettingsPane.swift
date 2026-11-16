import SwiftUI
import AppKit
import MLCore
import MLStudio
import StudioEngine

// Einstellungen → „KI-Hörbücher“: Eignung, Umgebung, Modelle (laden, entfernen), Leerlauf, Ablage, Lizenzen.

struct HoerspielSettingsPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HoerspielSettingsContent(hs: model.hoerspiel)
            .onAppear { model.hoerspiel.refreshSetup() }
    }
}

private struct HoerspielSettingsContent: View {
    @ObservedObject var hs: HoerspielModel
    @Environment(\.musicColors) private var colors
    @State private var confirmRemoveAll = false

    var body: some View {
        EditorCard(title: "Dieser Mac") {
            SettingRow(title: "Eignung", text: supportText) {
                Circle().fill(hs.support.isUsable ? Color(argb: 0xFF34C759) : colors.danger).frame(width: 9, height: 9)
            }
            if let free = hs.freeSpace, let story = hs.storyModel {
                Hairline()
                SettingRow(title: "Freier Speicher", text: "Für alles zusammen werden etwa \(KIFormat.bytes(HSHardware.requiredBytes(story: story))) gebraucht.") {
                    Text(KIFormat.bytes(free)).textStyle(Typo.labelLarge).foregroundColor(colors.textSecondary)
                }
            }
        }
        if hs.support.isUsable {
            EditorCard(title: "Umgebung") {
                SettingRow(title: "Python mit mlx-audio, mlx-lm, Whisper", text: environmentText) {
                    if hs.setup == .needsEnvironment {
                        PillButton(title: "Einrichten …", icon: Icons.download, style: .filled) { hs.installEverything() }.disabled(hs.installing)
                    } else {
                        Text("bereit").textStyle(Typo.labelLarge).foregroundColor(colors.textSecondary)
                    }
                }
                Hairline()
                SettingRow(title: "Rechenprozess beenden nach", text: "Ohne Nutzung wird der Prozess beendet und sein Arbeitsspeicher freigegeben.") {
                    Picker("", selection: $hs.unloadMinutes) {
                        Text("2 Minuten").tag(2)
                        Text("10 Minuten").tag(10)
                        Text("30 Minuten").tag(30)
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                Hairline()
                SettingRow(title: "Protokoll", text: "Meldungen des Rechenprozesses (bei Fehlern hilfreich).") {
                    PillButton(title: "Im Finder zeigen", style: .plain) { hs.revealLog() }
                }
            }
            EditorCard(title: "Modelle") {
                ForEach(Array(HSModel.all.enumerated()), id: \.element.repo) { i, m in
                    if i > 0 { Hairline() }
                    modelRow(m)
                }
                if case .running(let title, let p) = hs.installTask {
                    Hairline()
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(title).textStyle(Typo.titleSmall).foregroundColor(colors.textPrimary)
                            Spacer()
                            PillButton(title: "Abbrechen", style: .plain) { hs.cancelInstall() }
                        }
                        if let f = p.fraction { ProgressView(value: f).tint(colors.accent) } else { ProgressView().progressViewStyle(.linear) }
                        Text(p.step).textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).lineLimit(2)
                    }
                    .padding(.vertical, 6)
                }
                if case .failed(let message) = hs.installTask {
                    Hairline()
                    Text(message).textStyle(Typo.bodySmall).foregroundColor(colors.danger).fixedSize(horizontal: false, vertical: true)
                }
            }
            EditorCard(title: "Ablage") {
                SettingRow(title: "Ordner", text: hs.store.root.path + " – Produktionen, Stimmen, Referenzen, Geräusche. Gehört nicht zur Musikbibliothek.") {
                    PillButton(title: "Öffnen", style: .plain) { hs.revealFolder() }
                }
                Hairline()
                SettingRow(title: "KI-Hörbücher vollständig entfernen", text: "Löscht Umgebung und alle Modelle. Produktionen, Stimmen und Referenzen bleiben erhalten.") {
                    PillButton(title: confirmRemoveAll ? "Wirklich entfernen" : "Entfernen …", icon: Icons.delete, style: .plain) {
                        if confirmRemoveAll { hs.removeEverything(); confirmRemoveAll = false } else { confirmRemoveAll = true }
                    }
                    .disabled(hs.installing || hs.isWorking)
                }
            }
            EditorCard(title: "Lizenzen und Stimmrechte") {
                SettingRow(title: "Code", text: "mlx-audio, mlx-lm, mlx-whisper: MIT. Die App liefert keine Modelle mit; sie werden auf Wunsch von Hugging Face geladen.") { EmptyView() }
                Hairline()
                SettingRow(title: "Modelle", text: "Gemma 4 und Qwen3.5: Apache-2.0 · Qwen3-TTS: Apache-2.0 · Whisper: MIT · Silero VAD: MIT · SpeechBrain ECAPA: Apache-2.0 · Stable Audio 3 small: Stability AI Community License (Text-Encoder: Gemma-Nutzungsbedingungen).") { EmptyView() }
                Hairline()
                SettingRow(title: "Stimmen", text: "Entworfene Stimmen gehören keiner realen Person. Stimmen realer Personen nur mit dokumentierter Einwilligung derselben Person (Stimmprüfung). Referenzanalysen speichern nur allgemeine Merkmale.") { EmptyView() }
            }
        }
    }

    private var supportText: String {
        switch hs.support {
        case .supported: return "Apple-Chip mit genug Arbeitsspeicher – großes Geschichtenmodell (\(hs.storyModel?.title ?? ""))."
        case .limited(_, let reason): return reason
        case .unsupported(let reason): return reason
        }
    }

    private var environmentText: String {
        let s = hs.installState
        var parts: [String] = []
        if let uv = s.uvVersion { parts.append("uv \(uv)") }
        if let d = s.environmentDate { parts.append("eingerichtet \(d.formatted(date: .abbreviated, time: .omitted))") }
        return parts.isEmpty ? "noch nicht eingerichtet" : parts.joined(separator: " · ")
    }

    @ViewBuilder private func modelRow(_ m: HSModel) -> some View {
        let installed = hs.isInstalled(m)
        let info = hs.installState.models[m.repo]
        let recommended = hs.requiredModels.contains(m)
        SettingRow(title: m.title + (recommended ? " (nötig)" : ""), text: modelText(m, installed: installed, info: info)) {
            if installed {
                PillButton(title: "Entfernen", icon: Icons.delete, style: .plain) { hs.remove(m) }.disabled(hs.installing || hs.isWorking)
            } else {
                PillButton(title: "Laden", icon: Icons.download, style: .tonal) { hs.download(m) }
                    .disabled(hs.installing || hs.setup == .needsEnvironment)
            }
        }
    }

    private func modelText(_ m: HSModel, installed: Bool, info: HSInstaller.State.Model?) -> String {
        var parts = [m.detail]
        if let info, installed { parts.append("\(KIFormat.bytes(info.bytes)) · Stand \(String(info.revision.prefix(7)))") } else { parts.append("ca. " + KIFormat.bytes(m.bytes)) }
        parts.append("Lizenz \(m.license)")
        return parts.joined(separator: " · ")
    }
}
