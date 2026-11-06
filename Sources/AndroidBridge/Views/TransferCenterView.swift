import SwiftUI
import AppKit
import ABCore

/// Übertragungszentrale: laufende, wartende und abgeschlossene Übertragungen sowie der Verlauf.
struct TransferCenterView: View {
    @ObservedObject var engine: TransferEngine
    @ObservedObject var history: HistoryStore
    @State private var tab = 0
    @Environment(\.animationsEnabled) private var animations

    var body: some View {
        PageScaffold(title: "Übertragungen", subtitle: subtitle) {
            HStack(spacing: 10) {
                GlassSegmented(selection: $tab, options: [
                    SegmentOption(value: 0, title: "Warteschlange", symbol: "list.bullet"),
                    SegmentOption(value: 1, title: "Verlauf", symbol: "clock.arrow.circlepath"),
                ])
                ToolbarCapsule {
                    if tab == 0 {
                        ToolbarIconButton(symbol: "checkmark.circle.badge.xmark", help: "Abgeschlossene entfernen") { engine.clearFinished() }
                            .disabled(!engine.jobs.contains { $0.status.isFinished })
                    } else {
                        ToolbarIconButton(symbol: "trash.slash", help: "Verlauf löschen") { history.clear() }
                            .disabled(history.records.isEmpty)
                    }
                }
            }
        } content: {
        VStack(spacing: 0) {

            if tab == 0 {
                if engine.jobs.isEmpty {
                    EmptyStateView(symbol: "arrow.up.arrow.down.circle", title: "Keine Übertragungen",
                                   message: "Ziehen Sie Dateien zwischen Mac und Telefon oder wählen Sie Fotos aus – die Übertragungen erscheinen hier.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(engine.jobs) { job in
                                TransferJobRow(job: job, engine: engine)
                                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                            }
                        }
                        .padding(.horizontal, Spacing.gutter)
                        .padding(.bottom, 22)
                        .animation(animations ? .bridgeSpring : nil, value: engine.jobs.map(\.id))
                    }
                }
            } else {
                historyList
            }
        }
        }
    }

    private var subtitle: String {
        let active = engine.activeCount
        if active > 0 { return active == 1 ? "1 Übertragung läuft" : "\(active) Übertragungen laufen" }
        return "Warteschlange und Verlauf – alles lokal per USB"
    }

    private var historyList: some View {
        Group {
            if history.records.isEmpty {
                EmptyStateView(symbol: "clock.arrow.circlepath", title: "Kein Verlauf",
                               message: "Abgeschlossene Übertragungen werden hier aufgeführt (abschaltbar in den Einstellungen).")
            } else {
                List(history.records) { r in
                    HStack(spacing: 12) {
                        Image(systemName: r.direction == TransferDirection.toMac.rawValue ? "arrow.down.to.line" : "arrow.up.to.line")
                            .foregroundStyle(r.succeeded ? Palette.success : Palette.warning)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(.inter(13, .medium)).lineLimit(1)
                            Text(r.detail).font(.inter(11.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(r.fileCount) \(r.fileCount == 1 ? "Datei" : "Dateien") · \(ByteFormat.string(r.bytes))")
                                .font(.inter(12)).monospacedDigit()
                            Text(r.date.formatted(date: .abbreviated, time: .shortened)).font(.inter(11)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
                .scrollContentBackground(.hidden)
                .glassCard(cornerRadius: Radius.panel)
                .padding(.horizontal, Spacing.gutter - 6)
                .padding(.bottom, 18)
            }
        }
    }
}

struct TransferJobRow: View {
    @ObservedObject var job: TransferJob
    let engine: TransferEngine
    @State private var expanded = false

    private var tint: Color {
        switch job.status {
        case .completed: return Palette.success
        case .failed: return Palette.danger
        case .cancelled, .skipped: return .secondary
        case .paused: return Palette.warning
        default: return Palette.bridgeGreen
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    ProgressRing(fraction: job.fraction, lineWidth: 3.5, tint: tint)
                    Image(systemName: statusSymbol)
                        .font(.inter(13, .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(job.title).font(.inter(14, .semibold)).lineLimit(1).truncationMode(.middle)
                        Text(job.direction.verb)
                            .font(.inter(10.5, .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                    Text("\(job.sourceDescription)  →  \(job.destinationDescription)")
                        .font(.inter(11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if job.status == .running || job.status == .verifying || job.status == .paused {
                        ProgressView(value: job.fraction).tint(tint)
                        HStack(spacing: 12) {
                            if !job.currentName.isEmpty {
                                Text("\(job.currentIndex)/\(job.items.filter { !$0.name.isEmpty }.count): \(job.currentName)")
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text("\(ByteFormat.string(job.transferredBytes)) von \(ByteFormat.string(job.totalBytes)) · \(Int(job.fraction * 100)) %")
                            if job.bytesPerSecond > 0 { Text(ByteFormat.rate(job.bytesPerSecond)) }
                            if let r = job.remainingSeconds, r > 0 { Text("noch \(DurationFormat.string(r))") }
                        }
                        .font(.inter(11.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    } else {
                        Text(statusLine)
                            .font(.inter(12))
                            .foregroundStyle(job.status == .completed ? Palette.success : .secondary)
                    }
                }
                Spacer(minLength: 8)
                controls
            }
            if let issue = job.issue {
                IssueBanner(issue: issue)
            }
            if expanded {
                itemList
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 18)
    }

    private var statusSymbol: String {
        switch job.status {
        case .completed: return "checkmark"
        case .failed: return "exclamationmark"
        case .cancelled: return "xmark"
        case .paused: return "pause.fill"
        case .waiting: return "clock"
        default: return job.direction == .toMac ? "arrow.down" : "arrow.up"
        }
    }

    private var statusLine: String {
        switch job.status {
        case .waiting: return "Wartet · \(job.planned ? job.summary : "noch nicht vorbereitet")"
        case .preparing: return "Wird vorbereitet …"
        case .completed:
            let secs = (job.finishedAt ?? Date()).timeIntervalSince(job.startedAt ?? Date())
            return "Fertig · \(job.summary) · \(ByteFormat.string(job.transferredBytes)) in \(DurationFormat.string(max(secs, 1))) · geprüft"
        default: return "\(job.status.title) · \(job.summary)"
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 6) {
            if !job.status.isFinished {
                if job.status == .paused || job.isPauseRequested {
                    iconButton("play.fill", help: "Fortsetzen") { engine.resume(job) }
                } else {
                    iconButton("pause.fill", help: "Anhalten (große Dateien nach dem aktuellen Abschnitt, sonst nach der aktuellen Datei)") { engine.pause(job) }
                }
                iconButton("xmark", help: "Abbrechen") { engine.cancel(job) }
            } else {
                if job.status.canRetry || job.failedCount > 0 {
                    iconButton("arrow.clockwise", help: "Fehlgeschlagene wiederholen") { engine.retry(job) }
                }
                if job.direction == .toMac, case let .download(_, _, destination) = job.request, job.status == .completed {
                    iconButton("folder", help: "Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([destination]) }
                }
                iconButton("trash", help: "Aus der Liste entfernen") { engine.remove(job) }
            }
            if job.items.count > 1 || job.failedCount > 0 {
                iconButton(expanded ? "chevron.up" : "chevron.down", help: "Einzelne Dateien") {
                    withAnimation(.bridgeQuick) { expanded.toggle() }
                }
            }
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.inter(11, .bold)).frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .glassSurface(Circle(), interactive: true)
        .help(help)
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(job.items.filter { !$0.name.isEmpty }.prefix(400)) { item in
                HStack(spacing: 8) {
                    Image(systemName: symbol(for: item.status))
                        .foregroundStyle(color(for: item.status))
                        .frame(width: 14)
                    Text((item.folderPath + [item.resultName ?? item.name]).joined(separator: "/"))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(ByteFormat.string(item.size)).foregroundStyle(.secondary).monospacedDigit()
                    if case let .failed(reason) = item.status {
                        Text(reason).foregroundStyle(Palette.danger).lineLimit(1)
                    }
                }
                .font(.inter(11.5))
            }
            if job.items.count > 400 {
                Text("… und \(job.items.count - 400) weitere").font(.inter(11)).foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 52)
    }

    private func symbol(for status: TransferStatus) -> String {
        switch status {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .skipped: return "arrow.uturn.right.circle"
        case .cancelled: return "xmark.circle"
        case .running, .verifying, .preparing: return "arrow.triangle.2.circlepath.circle"
        default: return "circle"
        }
    }

    private func color(for status: TransferStatus) -> Color {
        switch status {
        case .completed: return Palette.success
        case .failed: return Palette.danger
        case .running, .verifying, .preparing: return Palette.bridgeGreen
        default: return .secondary
        }
    }
}

/// Rückfrage bei Namenskonflikten.
struct ConflictSheet: View {
    let prompt: ConflictPrompt
    @State private var applyToAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                IconTile(symbol: "doc.on.doc", tint: Palette.warning, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("„\(prompt.fileName)“ ist bereits vorhanden")
                        .font(.inter(15, .semibold))
                        .lineLimit(2)
                    Text("Im Ziel „\(prompt.destination)“ gibt es bereits ein Objekt mit diesem Namen.")
                        .font(.inter(12.5))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                compareCard(title: "Vorhanden", size: prompt.existingSize, date: prompt.existingDate)
                Image(systemName: "arrow.left").foregroundStyle(.secondary)
                compareCard(title: "Neu", size: prompt.newSize, date: prompt.newDate)
            }
            if prompt.remainingCount > 0 {
                Toggle("Für alle weiteren Konflikte dieser Übertragung übernehmen (\(prompt.remainingCount) Dateien folgen)", isOn: $applyToAll)
                    .font(.inter(12.5))
            }
            HStack {
                Button("Überspringen") { prompt.resolve(.skip, applyToAll) }
                Spacer()
                Button("Beide behalten") { prompt.resolve(.keepBoth, applyToAll) }
                Button("Ersetzen") { prompt.resolve(.replace, applyToAll) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .interactiveDismissDisabled()
    }

    private func compareCard(title: String, size: UInt64?, date: Date?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.inter(11, .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            Text(size.map { ByteFormat.string($0) } ?? "–").font(.inter(13, .medium))
            Text(date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Datum unbekannt").font(.inter(11.5)).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 12)
    }
}
