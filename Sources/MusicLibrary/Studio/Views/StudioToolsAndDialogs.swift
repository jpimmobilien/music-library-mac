import SwiftUI
import AppKit
import MLCore
import MLStudio

// Audio Studio – Werkzeuge für Internet-Quellen (yt-dlp, Deno) als Glas-Blatt, Status-Kapsel im Kopf und
// Bestätigungsdialoge („Original ersetzen?“, „Verlauf löschen?“). „Abbrechen“ ist jeweils Standard.

// MARK: - Werkzeuge

enum StudioToolsSheet {
    @MainActor
    static func present() {
        guard let model = AppModel.shared else { return }
        let studio = model.studio!
        GlassSheet.present(width: 560) { close in
            StudioToolsView(studio: studio, close: close)
        }
    }
}

/// Status-Kapsel im Kopf des Studios (öffnet das Werkzeug-Blatt).
struct StudioToolsChip: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    @State private var hover = false

    var body: some View {
        let s = studio.toolStatus
        let installing: ToolInstallProgress? = {
            if case .running(let p) = studio.toolInstall { return p }
            return nil
        }()
        Button { StudioToolsSheet.present() } label: {
            HStack(spacing: 7) {
                if let p = installing {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
                    Text(p.fraction.map { "Werkzeuge werden installiert … \(Int(($0 * 100).rounded())) %" } ?? "Werkzeuge werden installiert …")
                } else if s.readyForYouTube {
                    Circle().fill(Color(nsColor: .systemGreen)).frame(width: 7, height: 7)
                    Text("Internet-Quellen bereit")
                } else if s.readyForWeb {
                    Icon(Icons.warning, size: 14, color: colors.accentText)
                    Text("Für YouTube fehlt Deno")
                } else {
                    Icon(Icons.wrench, size: 14, color: colors.accentText)
                    Text("Werkzeuge einrichten")
                }
            }
            .font(Typo.inter(12, .semibold))
            .monospacedDigit()
            .foregroundColor(s.readyForYouTube && installing == nil ? colors.textSecondary : colors.accentText)
            .lineLimit(1)
            .padding(.horizontal, 13)
            .frame(height: 32)
            .glassSurface(Capsule(), strong: true, interactive: true)
            .overlay(Capsule().strokeBorder(colors.accent.opacity(hover ? 0.4 : 0), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle(scale: 0.96))
        .onHover { hover = $0 }
        .help("Werkzeuge für Internet-Quellen (yt-dlp, Deno)")
        .accessibilityLabel("Werkzeuge für Internet-Quellen")
    }
}

/// Inhalt des Werkzeug-Blatts (auch für Vorschaubilder direkt verwendbar).
struct StudioToolsView: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    let close: () -> Void

    var body: some View {
        let s = studio.toolStatus
        let running: ToolInstallProgress? = {
            if case .running(let p) = studio.toolInstall { return p }
            return nil
        }()
        let managed = s.ytDlpOrigin == .managed || s.denoOrigin == .managed
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(colors.accentSoft)
                    .frame(width: 48, height: 48)
                    .overlay(Icon(Icons.wrench, size: 24, color: colors.accentText))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Werkzeuge für Internet-Quellen")
                        .textStyle(Typo.titleLarge)
                        .foregroundColor(colors.textPrimary)
                    Text("Für YouTube, SoundCloud und viele weitere Seiten nutzt das Audio Studio zwei bewährte Open-Source-Werkzeuge. Für eigene Dateien werden sie nicht gebraucht.")
                        .textStyle(Typo.bodyMedium)
                        .foregroundColor(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(spacing: 8) {
                StudioToolRow(name: "yt-dlp", purpose: "Liest Internet-Quellen und lädt die Audiospur (Unlicense).",
                              origin: s.ytDlpOrigin, version: s.ytDlpVersion, path: s.ytDlpPath)
                StudioToolRow(name: "Deno", purpose: "JavaScript-Laufzeit, die YouTube zusätzlich benötigt (MIT).",
                              origin: s.denoOrigin, version: s.denoVersion, path: s.denoPath)
                if let ffmpeg = s.ffmpegPath {
                    StudioToolRow(name: "FFmpeg", purpose: "Optional – nur für seltene lokale Formate (z. B. WebM, MKV).",
                                  origin: .system, version: nil, path: ffmpeg)
                }
            }
            .padding(.top, 18)
            Group {
                switch studio.toolInstall {
                case .running(let p):
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(p.step)
                                .textStyle(Typo.labelMedium)
                                .foregroundColor(colors.textPrimary)
                            Spacer()
                            if let f = p.fraction {
                                Text("\(Int((f * 100).rounded())) %")
                                    .textStyle(Typo.labelMedium)
                                    .monospacedDigit()
                                    .foregroundColor(colors.textSecondary)
                            }
                        }
                        StudioProgressBar(value: p.fraction)
                    }
                case .failed(let message):
                    StudioInfoLine(text: message, icon: Icons.error, tint: colors.danger)
                case .idle:
                    EmptyView()
                }
            }
            .padding(.top, 14)
            VStack(alignment: .leading, spacing: 8) {
                StudioInfoLine(text: "Geladen wird nur auf deinen Wunsch – von den offiziellen GitHub-Veröffentlichungen. Jede Datei wird vor der Verwendung mit ihrer SHA-256-Prüfsumme geprüft und unter „Application Support/Music Library/Audio Studio“ abgelegt. Vorhandene Installationen (z. B. über Homebrew) werden erkannt und verwendet.",
                               icon: Icons.shield, tint: colors.accentText)
                StudioInfoLine(text: "Keine Anmeldung, keine Cookies: Private, altersbeschränkte oder kostenpflichtige Inhalte werden nicht geladen.", icon: Icons.privacy)
                StudioInfoLine(text: StudioText.rightsNote, icon: Icons.info)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(colors.textPrimary.opacity(colors.dark ? 0.05 : 0.03)))
            .padding(.top, 14)
            HStack(spacing: 10) {
                if managed {
                    Button { studio.removeTools() } label: {
                        Text("Entfernen")
                            .textStyle(Typo.labelLarge)
                            .foregroundColor(colors.danger)
                            .padding(.horizontal, 6)
                            .frame(minHeight: 30)
                    }
                    .buttonStyle(.plain)
                    .help("Von der App installierte Werkzeuge löschen (vorhandene Installationen bleiben unberührt)")
                    .disabled(running != nil)
                }
                Spacer()
                PillButton(title: "Erneut prüfen", icon: Icons.refresh, style: .plain) { studio.refreshToolStatus() }
                    .disabled(running != nil)
                if s.readyForYouTube {
                    if managed {
                        PillButton(title: "Aktualisieren", icon: Icons.download) { studio.installTools() }
                            .disabled(running != nil)
                    }
                    PillButton(title: "Fertig", style: .filled, minWidth: 100) { close() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    PillButton(title: "Später", minWidth: 90) { close() }
                    PillButton(title: s.readyForWeb ? "Deno installieren" : "Installieren", icon: Icons.download, style: .filled, minWidth: 140) {
                        studio.installTools()
                    }
                    .disabled(running != nil)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, 18)
            StudioEscapeButton { close() }
        }
        .padding(22)
        .background(AmbientBackground())
        .animation(Motion.easeOut(), value: studio.toolInstall)
        .onAppear { if !studio.demo { studio.refreshToolStatus() } }
    }
}

private struct StudioToolRow: View {
    @Environment(\.musicColors) private var colors
    let name: String
    let purpose: String
    let origin: StudioToolStatus.Origin
    let version: String?
    let path: String?

    var body: some View {
        let present = origin != .missing
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(present ? Color(nsColor: .systemGreen).opacity(0.16) : colors.textPrimary.opacity(0.06))
                Icon(present ? Icons.check : Icons.download, size: 15, color: present ? Color(nsColor: .systemGreen) : colors.textTertiary)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(name)
                        .font(Typo.inter(14, .semibold))
                        .foregroundColor(colors.textPrimary)
                    StudioBadge(text: originLabel, tint: present ? colors.textSecondary : colors.accentText)
                }
                Text(purpose)
                    .textStyle(Typo.bodySmall)
                    .foregroundColor(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let path {
                    Text(StudioText.abbreviated(path))
                        .font(Typo.inter(11, .regular))
                        .foregroundColor(colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 8)
            Text(version ?? (present ? "" : "fehlt"))
                .font(Typo.inter(12, .semibold))
                .monospacedDigit()
                .foregroundColor(present ? colors.textSecondary : colors.textTertiary)
                .padding(.top, 6)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(colors.textPrimary.opacity(colors.dark ? 0.05 : 0.03)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(colors.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var originLabel: String {
        switch origin {
        case .missing: return "Nicht installiert"
        case .managed: return "Von der App installiert"
        case .system: return "Auf dem Mac vorhanden"
        }
    }
}

// MARK: - Bestätigungen

@MainActor
enum StudioDialogs {
    /// „Original ersetzen?“ – erst nach Bestätigung kommt der Auftrag in die Warteschlange.
    static func confirmReplace(studio: StudioModel) {
        GlassSheet.present(width: 480) { close in
            StudioReplaceDialogView(studio: studio, close: close)
        }
    }

    static func confirmClearHistory(studio: StudioModel) {
        GlassSheet.present(width: 440) { close in
            StudioClearHistoryDialogView(studio: studio, close: close)
        }
    }
}

struct StudioReplaceDialogView: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    let close: () -> Void

    var body: some View {
        let title = studio.metadata.title.isEmpty ? (studio.source?.title ?? "Titel") : studio.metadata.title
        let sel = studio.shownSelection
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(colors.danger.opacity(0.14))
                    .frame(width: 48, height: 48)
                    .overlay(Icon(Icons.swap, size: 24, color: colors.danger))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Original ersetzen?")
                        .textStyle(Typo.titleLarge)
                        .foregroundColor(colors.textPrimary)
                    Text(studio.exportWholeFile
                         ? "„\(title)“ wird neu geschrieben\(studio.fadeIn > 0 || studio.fadeOut > 0 ? " (mit Blenden)" : "")."
                         : "„\(title)“ wird durch den Ausschnitt \(StudioTime.format(sel.start, millis: false)) – \(StudioTime.format(sel.end, millis: false)) ersetzt (Länge \(StudioTime.format(sel.length, millis: false))).")
                        .textStyle(Typo.bodyMedium)
                        .foregroundColor(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                point(Icons.backup, "Vorher wird eine Sicherung des Originals angelegt.")
                point(Icons.undo, "Im Verlauf des Studios lässt sich das Ersetzen mit „Rückgängig“ zurücknehmen.")
                point(Icons.favoriteBorder, "Favoriten, Playlists, Wiedergabestatistik und Hinzufügedatum bleiben am Titel.")
                point(Icons.label, "Tags, Cover und Liedtexte bleiben erhalten.")
                if let badge = studio.passthroughBadge {
                    point(Icons.check, passthroughText(badge))
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(colors.textPrimary.opacity(colors.dark ? 0.05 : 0.03)))
            .padding(.top, 16)
            HStack(spacing: 10) {
                Spacer()
                PillButton(title: "Abbrechen", minWidth: 110) { close() }
                    .keyboardShortcut(.defaultAction)
                StudioDangerButton(title: "Original ersetzen", icon: Icons.swap) {
                    close()
                    studio.addToQueue()
                }
            }
            .padding(.top, 20)
            StudioEscapeButton { close() }
        }
        .padding(22)
        .background(AmbientBackground())
    }

    private func passthroughText(_ badge: String) -> String {
        guard badge == "ohne Neukodierung" else { return "Format wie Original – verlustfrei." }
        switch studio.originalFormat {
        case .mp3?: return "Format wie Original – ohne Neukodierung geschnitten (an MP3-Frame-Grenzen, auf etwa 26 ms genau)."
        case .m4a?: return "Format wie Original – ohne Neukodierung geschnitten (an AAC-Blockgrenzen, auf etwa 23 ms genau)."
        default: return "Format wie Original – ohne Neukodierung geschnitten."
        }
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Icon(icon, size: 15, color: colors.accentText)
                .padding(.top, 1)
            Text(text)
                .textStyle(Typo.bodySmall)
                .foregroundColor(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

struct StudioClearHistoryDialogView: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    let close: () -> Void

    var body: some View {
        let entries = studio.history.entries
        let undoable = entries.filter { $0.backupPath != nil && !$0.undone && $0.succeeded }.count
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(colors.danger.opacity(0.14))
                    .frame(width: 48, height: 48)
                    .overlay(Icon(Icons.delete, size: 24, color: colors.danger))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Verlauf löschen?")
                        .textStyle(Typo.titleLarge)
                        .foregroundColor(colors.textPrimary)
                    Text("\(StudioHistoryList.count(entries.count)) werden entfernt. Die exportierten Dateien bleiben erhalten."
                         + (undoable > 0 ? " \(undoable == 1 ? "Ein ersetztes Original lässt" : "\(undoable) ersetzte Originale lassen") sich danach nicht mehr über das Studio wiederherstellen." : ""))
                        .textStyle(Typo.bodyMedium)
                        .foregroundColor(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                Spacer()
                PillButton(title: "Abbrechen", minWidth: 110) { close() }
                    .keyboardShortcut(.defaultAction)
                StudioDangerButton(title: "Verlauf löschen", icon: Icons.delete) {
                    close()
                    studio.clearHistory()
                }
            }
            .padding(.top, 20)
            StudioEscapeButton { close() }
        }
        .padding(22)
        .background(AmbientBackground())
    }
}
