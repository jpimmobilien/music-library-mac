import SwiftUI
import AppKit
import MLCore
import MLStudio

// Audio Studio – Warteschlange und Verlauf: Aufträge mit Vorschaubild, Phase, Fortschritt, Fehlern und allen
// Aktionen (Anhalten, Fortsetzen, Abbrechen, Wiederholen, Entfernen, Im Finder zeigen, Format wartender
// Aufträge); Verlauf mit Suche, „Im Finder zeigen“, „Rückgängig“ für ersetzte Originale und „Verlauf löschen“.

enum StudioQueueTab: Hashable {
    case queue
    case history
}

/// Glas-Spalte (breites Fenster) bzw. Abschnitt unter dem Editor (schmales Fenster).
struct StudioQueuePanel: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    @Binding var tab: StudioQueueTab
    /// Breite Spalte: füllt die Höhe und scrollt selbst.
    var column: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SegmentedControl(options: [StudioQueueTab.queue, .history], selection: $tab,
                             label: { $0 == .queue ? queueLabel : "Verlauf" },
                             icon: { $0 == .queue ? Icons.queue : Icons.history }, height: 32)
            if tab == .queue {
                StudioQueueList(studio: studio, scrolls: column)
            } else {
                StudioHistoryList(studio: studio, scrolls: column)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: column ? .infinity : nil, alignment: .top)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous), strong: column)
    }

    private var queueLabel: String {
        let open = studio.unfinishedJobCount
        return open > 0 ? "Warteschlange (\(open))" : "Warteschlange"
    }
}

// MARK: - Warteschlange

struct StudioQueueList: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    let scrolls: Bool

    var body: some View {
        let jobs = studio.jobs
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(StudioQueueLogic.summary(jobs))
                    .textStyle(Typo.labelMedium)
                    .monospacedDigit()
                    .foregroundColor(colors.textSecondary)
                Spacer(minLength: 4)
                if jobs.contains(where: { $0.phase.isFinished }) {
                    StudioLinkButton(title: "Erledigte entfernen") { withAnimation(Motion.easeOut()) { studio.clearFinished() } }
                }
            }
            .padding(.horizontal, 4)
            if jobs.isEmpty {
                StudioPanelEmpty(icon: Icons.queue, title: "Keine Aufträge",
                                 text: "Exporte erscheinen hier mit Fortschritt. Sie laufen nacheinander – auch während du schon die nächste Quelle bearbeitest.")
            } else if scrolls {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 4) {
                        ForEach(jobs) { job in StudioJobRow(studio: studio, job: job) }
                    }
                    .padding(.bottom, 6)
                }
            } else {
                VStack(spacing: 4) {
                    ForEach(jobs) { job in StudioJobRow(studio: studio, job: job) }
                }
            }
        }
        .animation(Motion.easeOut(), value: jobs.map(\.id))
    }
}

/// Ein Auftrag.
struct StudioJobRow: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    let job: StudioJob
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                StudioArtwork(source: job.source, cover: job.metadata.cover, key: job.id.uuidString, cornerRadius: 8)
                    .frame(width: 44, height: 44)
                    .opacity(job.phase == .cancelled ? 0.5 : 1)
                if job.phase == .done {
                    phaseBadge(Icons.check, colors.accent)
                } else if job.phase == .failed {
                    phaseBadge(Icons.close, colors.danger)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .textStyle(Typo.titleSmall)
                    .foregroundColor(job.phase == .cancelled ? colors.textTertiary : colors.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if job.phase == .waiting {
                        StudioJobFormatMenu(studio: studio, job: job)
                    } else {
                        Text(job.options.summary(sourceRate: job.source.sampleRate))
                            .textStyle(Typo.labelSmall)
                            .foregroundColor(colors.textSecondary)
                            .lineLimit(1)
                    }
                    Text(destinationLabel)
                        .textStyle(Typo.labelSmall)
                        .foregroundColor(colors.textTertiary)
                        .lineLimit(1)
                }
                if showsProgress {
                    StudioProgressBar(value: job.overallProgress, tint: job.phase == .paused ? colors.textTertiary : colors.accent, height: 4)
                        .padding(.top, 2)
                }
                HStack(spacing: 6) {
                    Text(job.phase.label)
                        .textStyle(Typo.labelMedium)
                        .foregroundColor(phaseColor)
                        .lineLimit(1)
                    if let detail = job.detail, !detail.isEmpty, !job.phase.isFinished || job.phase == .done {
                        Text(detail)
                            .textStyle(Typo.labelSmall)
                            .monospacedDigit()
                            .foregroundColor(colors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    if job.phase.isActive || job.phase == .paused {
                        Text("\(Int((job.overallProgress * 100).rounded())) %")
                            .textStyle(Typo.labelMedium)
                            .monospacedDigit()
                            .foregroundColor(colors.textSecondary)
                    }
                }
                if job.phase == .failed, let error = job.error, !error.isEmpty {
                    Text(error)
                        .textStyle(Typo.bodySmall)
                        .foregroundColor(colors.danger)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
            actions
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors.textPrimary.opacity(hover ? 0.045 : 0)))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hover = $0 }
        .contextMenu { menuItems }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(job.phase.label)")
    }

    private var title: String {
        let t = job.metadata.title.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return job.fileName.isEmpty ? job.source.title : job.fileName }
        let a = job.metadata.artist.trimmingCharacters(in: .whitespaces)
        return a.isEmpty ? t : "\(t) – \(a)"
    }

    private var destinationLabel: String {
        switch job.destination {
        case .library: return "→ Bibliothek"
        case .folder: return "→ Ordner"
        case .replaceOriginal: return "→ ersetzt Original"
        }
    }

    private var showsProgress: Bool { job.phase.isActive || job.phase == .paused }

    private var phaseColor: Color {
        switch job.phase {
        case .failed: return colors.danger
        case .done: return colors.accentText
        case .downloading, .converting, .tagging, .importing: return colors.textPrimary
        default: return colors.textSecondary
        }
    }

    private func phaseBadge(_ icon: String, _ tint: Color) -> some View {
        Icon(icon, size: 10, color: .white)
            .frame(width: 17, height: 17)
            .background(Circle().fill(tint))
            .overlay(Circle().strokeBorder(colors.background, lineWidth: 1.5))
            .offset(x: 4, y: 4)
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 0) {
            switch job.phase {
            case .waiting:
                tap(Icons.pause, "Anhalten") { studio.pause(job.id) }
                tap(Icons.close, "Aus der Warteschlange entfernen") { studio.remove(job.id) }
            case .downloading, .converting, .tagging, .importing:
                if StudioQueueLogic.canPause(job) { tap(Icons.pause, "Anhalten") { studio.pause(job.id) } }
                tap(Icons.close, "Abbrechen") { studio.cancel(job.id) }
            case .paused:
                tap(Icons.play, "Fortsetzen") { studio.resume(job.id) }
                tap(Icons.close, "Abbrechen") { studio.cancel(job.id) }
            case .done:
                if let path = job.outputPath {
                    if job.destination.importsIntoLibrary { tap(Icons.play, "In der Bibliothek abspielen") { studio.playExported(path) } }
                    tap(Icons.folderOpen, "Im Finder zeigen") { studio.revealInFinder(path) }
                }
                tap(Icons.close, "Aus der Liste entfernen") { studio.remove(job.id) }
            case .failed, .cancelled:
                tap(Icons.refresh, "Wiederholen") { studio.retry(job.id) }
                tap(Icons.close, "Aus der Liste entfernen") { studio.remove(job.id) }
            }
        }
    }

    private func tap(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        IconTap(icon: icon, label: label, tint: colors.textSecondary, iconSize: 15, touch: 28, action: action)
    }

    @ViewBuilder
    private var menuItems: some View {
        if StudioQueueLogic.canResume(job) { Button("Fortsetzen") { studio.resume(job.id) } }
        if StudioQueueLogic.canPause(job) { Button("Anhalten") { studio.pause(job.id) } }
        if StudioQueueLogic.canRetry(job) { Button("Wiederholen") { studio.retry(job.id) } }
        if StudioQueueLogic.canCancel(job) { Button("Abbrechen") { studio.cancel(job.id) } }
        if let path = job.outputPath, job.phase == .done {
            Divider()
            Button("Im Finder zeigen") { studio.revealInFinder(path) }
            if job.destination.importsIntoLibrary { Button("In der Bibliothek abspielen") { studio.playExported(path) } }
        }
        if StudioQueueLogic.canRemove(job) {
            Divider()
            Button("Aus der Liste entfernen") { studio.remove(job.id) }
        }
    }
}

/// Format eines wartenden Auftrags ändern.
private struct StudioJobFormatMenu: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    let job: StudioJob

    var body: some View {
        GlassMenuButton(help: "Format dieses Auftrags ändern", width: 230) {
            HStack(spacing: 3) {
                Text(job.options.summary(sourceRate: job.source.sampleRate))
                    .font(Typo.inter(11, .semibold))
                    .foregroundColor(colors.accentText)
                    .lineLimit(1)
                Icon(Icons.expandMore, size: 11, color: colors.accentText)
            }
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Capsule().fill(colors.accentSoft))
            .contentShape(Capsule())
        } content: { menu in
            GlassMenuHeader(title: "Format")
            ForEach(StudioFormat.allCases, id: \.self) { f in
                GlassMenuItem(title: f.label, checked: job.options.format == f, detail: f.isLossless ? "verlustfrei" : nil) {
                    studio.setFormat(f, for: job.id)
                    menu.close()
                }
            }
        }
    }
}

// MARK: - Verlauf

struct StudioHistoryList: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    let scrolls: Bool
    @State private var query = ""

    var body: some View {
        let all = studio.history.entries
        let shown = filtered(all)
        VStack(alignment: .leading, spacing: 8) {
            if !all.isEmpty {
                SearchField(text: $query, placeholder: "Verlauf durchsuchen")
                HStack(spacing: 8) {
                    Text(query.isEmpty ? Self.count(all.count) : "\(shown.count) von \(Self.count(all.count))")
                        .textStyle(Typo.labelMedium)
                        .monospacedDigit()
                        .foregroundColor(colors.textSecondary)
                    Spacer(minLength: 4)
                    StudioLinkButton(title: "Verlauf löschen …") { StudioDialogs.confirmClearHistory(studio: studio) }
                }
                .padding(.horizontal, 4)
            }
            if all.isEmpty {
                StudioPanelEmpty(icon: Icons.history, title: "Noch kein Verlauf",
                                 text: "Jeder Export wird hier festgehalten – mit Ziel, Format und, beim Ersetzen eines Originals, „Rückgängig“.")
            } else if shown.isEmpty {
                StudioPanelEmpty(icon: Icons.search, title: "Keine Treffer", text: "Kein Eintrag passt zu „\(query)“.")
            } else if scrolls {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 4) {
                        ForEach(shown) { e in StudioHistoryRow(studio: studio, entry: e) }
                    }
                    .padding(.bottom, 6)
                }
            } else {
                VStack(spacing: 4) {
                    ForEach(shown.prefix(30)) { e in StudioHistoryRow(studio: studio, entry: e) }
                }
            }
        }
    }

    private func filtered(_ entries: [StudioHistoryEntry]) -> [StudioHistoryEntry] {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return entries }
        return entries.filter { e in
            let text = "\(e.title) \(e.artist) \(e.source) \(e.outputPath) \(e.formatSummary)".lowercased()
            return terms.allSatisfy { text.contains($0) }
        }
    }

    static func count(_ n: Int) -> String { n == 1 ? "1 Eintrag" : "\(Formatting.integer(n)) Einträge" }
}

struct StudioHistoryRow: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    let entry: StudioHistoryEntry
    @State private var hover = false

    var body: some View {
        let replaced = entry.backupPath != nil
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill((entry.succeeded ? colors.accent : colors.danger).opacity(0.13))
                .frame(width: 32, height: 32)
                .overlay(Icon(icon, size: 16, color: entry.succeeded ? colors.accentText : colors.danger))
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.artist.isEmpty ? entry.title : "\(entry.title) – \(entry.artist)")
                    .textStyle(Typo.titleSmall)
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                Text("\(entry.formatSummary) · \(StudioText.relativeDate(entry.date))")
                    .textStyle(Typo.labelSmall)
                    .monospacedDigit()
                    .foregroundColor(colors.textTertiary)
                    .lineLimit(1)
                if !entry.succeeded, let error = entry.error {
                    Text(error)
                        .textStyle(Typo.bodySmall)
                        .foregroundColor(colors.danger)
                        .lineLimit(2)
                } else {
                    StudioFlow(spacing: 4) {
                        if replaced {
                            StudioBadge(text: entry.undone ? "Rückgängig gemacht" : "Original ersetzt", icon: entry.undone ? Icons.undo : Icons.swap,
                                        tint: entry.undone ? colors.textSecondary : colors.accentText)
                        } else if entry.imported {
                            StudioBadge(text: "In der Bibliothek", icon: Icons.libraryMusic, tint: colors.accentText)
                        }
                        StudioBadge(text: StudioText.sourceKindLabel(entry.sourceKind))
                    }
                    .padding(.top, 1)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                if replaced && !entry.undone && entry.succeeded {
                    IconTap(icon: Icons.undo, label: "Rückgängig – Original wiederherstellen", tint: colors.accentText, iconSize: 15, touch: 28) {
                        studio.undoReplace(entry.id)
                    }
                }
                if entry.succeeded && !entry.outputPath.isEmpty {
                    IconTap(icon: Icons.folderOpen, label: "Im Finder zeigen", tint: colors.textSecondary, iconSize: 15, touch: 28) {
                        studio.revealInFinder(entry.outputPath)
                    }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors.textPrimary.opacity(hover ? 0.045 : 0)))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hover = $0 }
        .contextMenu {
            if entry.succeeded && !entry.outputPath.isEmpty {
                Button("Im Finder zeigen") { studio.revealInFinder(entry.outputPath) }
            }
            if replaced && !entry.undone && entry.succeeded {
                Button("Rückgängig – Original wiederherstellen") { studio.undoReplace(entry.id) }
            }
            Button("Quelle kopieren") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.source, forType: .string)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(entry.title), \(entry.formatSummary)")
    }

    private var icon: String {
        if !entry.succeeded { return Icons.error }
        if entry.backupPath != nil { return entry.undone ? Icons.undo : Icons.swap }
        return Icons.check
    }
}

extension StudioText {
    static func sourceKindLabel(_ kind: SourceKind) -> String { kind.label }
}

// MARK: - Bausteine

/// Leerer Zustand in der Seitenspalte.
struct StudioPanelEmpty: View {
    @Environment(\.musicColors) private var colors
    let icon: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colors.accentSoft)
                .frame(width: 44, height: 44)
                .overlay(Icon(icon, size: 22, color: colors.accentText))
            Text(title)
                .textStyle(Typo.titleSmall)
                .foregroundColor(colors.textPrimary)
            Text(text)
                .textStyle(Typo.bodySmall)
                .foregroundColor(colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
    }
}

/// Zurückhaltende Text-Schaltfläche in Rosé.
struct StudioLinkButton: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.isEnabled) private var enabled
    let title: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .textStyle(Typo.labelLarge)
                .foregroundColor(enabled ? colors.accentText : colors.textTertiary)
                .underline(hover && enabled)
                .padding(.horizontal, 6)
                .frame(minHeight: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
