import SwiftUI
import AppKit
import ABCore

/// „Duplikate finden“: Bereich wählen, Inhalte vergleichen (SHA-256), Ergebnisse prüfen, gezielt löschen.
struct DuplicatesView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var scanner: DuplicateScanner
    @ObservedObject var devices: DeviceManager
    @State private var showSimilar = false
    @Environment(\.animationsEnabled) private var animations

    private var device: DeviceConnection? { scanner.device }

    var body: some View {
        PageScaffold(title: "Duplikate finden", subtitle: subtitle) {
            if scanner.state == .finished {
                ToolbarCapsule {
                    ToolbarIconButton(symbol: "wand.and.stars", help: "Alle Vorschläge übernehmen") {
                        scanner.applyAllSuggestions(includeSimilar: showSimilar)
                    }
                    .disabled(scanner.allGroups.isEmpty)
                    ToolbarIconButton(symbol: "checkmark.circle.badge.xmark", help: "Markierungen aufheben") { scanner.clearSelection() }
                        .disabled(scanner.marked.isEmpty)
                    ToolbarDivider()
                    ToolbarIconButton(symbol: "arrow.clockwise", help: "Neu suchen") { scanner.start() }
                    ToolbarIconButton(symbol: "slider.horizontal.3", help: "Suchbereich ändern") { scanner.reset() }
                }
            }
        } content: {
            ZStack(alignment: .bottom) {
                content
                if scanner.state == .finished && !scanner.marked.isEmpty {
                    FloatingActionBar {
                        SelectionSummary(count: scanner.marked.count, bytes: scanner.markedBytes)
                        Button("Aufheben") { scanner.clearSelection() }
                            .buttonStyle(GlassButtonStyle(compact: true))
                        Button {
                            model.deleteMarkedDuplicates()
                        } label: {
                            Label("Ausgewählte Duplikate löschen", systemImage: "trash")
                        }
                        .buttonStyle(GlassButtonStyle(prominent: true, destructive: true, compact: true))
                        .help("Öffnet die Bestätigung (⌘⌫)")
                    }
                    .padding(.bottom, 20)
                }
            }
            .animation(animations ? .bridgeSpring : nil, value: scanner.marked.isEmpty)
        }
        .onAppear {
            if scanner.device == nil, let d = model.selectedDevice, d.state == .connected { scanner.attach(d) }
        }
    }

    private var subtitle: String {
        guard let device else { return "Exakte Kopien per Inhaltsvergleich (SHA-256) – ähnliche Bilder getrennt" }
        switch scanner.state {
        case .scanning: return "\(device.displayName) · Suche läuft"
        case .finished:
            if let at = scanner.scannedAt { return "\(device.displayName) · geprüft \(at.formatted(date: .omitted, time: .shortened))" }
            return device.displayName
        default: return "\(device.displayName) · Exakte Kopien per Inhaltsvergleich"
        }
    }

    @ViewBuilder
    private var content: some View {
        if let device, device.state == .connected {
            switch scanner.state {
            case .scanning:
                ScanProgressPanel(progress: scanner.progress, wantsSimilar: scanner.findSimilarImages) { scanner.cancel() }
            case .finished:
                results(device: device)
            default:
                ScanSetupPanel(scanner: scanner)
            }
        } else {
            EmptyStateView(symbol: "doc.on.doc", title: "Kein Telefon verbunden",
                           message: "Schließen Sie Ihr Android-Gerät per USB an und wählen Sie „Dateiübertragung“, um nach doppelten Dateien zu suchen.") {
                Button("Zur Übersicht") { model.selection = .overview }.buttonStyle(GlassButtonStyle())
            }
        }
    }

    // MARK: Ergebnisse

    @ViewBuilder
    private func results(device: DeviceConnection) -> some View {
        let groups = showSimilar ? scanner.similar : scanner.identical
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HStack(spacing: 12) {
                    StatTile(value: "\(scanner.identical.count)", label: "Gruppen identischer Dateien", symbol: "square.stack.3d.up")
                    StatTile(value: "\(scanner.redundantTotal)", label: "Doppelte Dateien", symbol: "doc.on.doc", tint: Palette.bridgeTeal)
                    StatTile(value: ByteFormat.string(scanner.reclaimableTotal), label: "Freigebbar", symbol: "externaldrive.badge.minus", tint: Palette.bridgeBlue)
                }
                if let freed = scanner.lastFreed {
                    LastDeletionNote(freed: freed, failures: scanner.lastFailures)
                }
                if scanner.progress.unreadable > 0 {
                    Label("\(scanner.progress.unreadable) Dateien ließ das Telefon nicht lesen – sie wurden nicht verglichen und nie als Duplikat gewertet.",
                          systemImage: "lock.doc")
                        .font(Typo.caption).foregroundStyle(Palette.textSecondary)
                }
                HStack(spacing: 12) {
                    GlassSegmented(selection: $showSimilar, options: [
                        SegmentOption(value: false, title: "Identisch (\(scanner.identical.count))", symbol: "equal.square"),
                        SegmentOption(value: true, title: "Ähnliche Bilder (\(scanner.similar.count))", symbol: "photo.on.rectangle"),
                    ])
                    Spacer()
                    if let hint = scanner.selectionHint {
                        Label(hint, systemImage: "info.circle").font(Typo.caption).foregroundStyle(Palette.warning)
                    }
                }
                if showSimilar {
                    Label("Ähnliche Bilder sehen gleich aus, sind aber nicht byte-gleich (z. B. andere Auflösung, Bearbeitung oder Kompression). Prüfen Sie jede Gruppe selbst.",
                          systemImage: "exclamationmark.triangle")
                        .font(Typo.callout).foregroundStyle(Palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if groups.isEmpty {
                    EmptyStateView(symbol: showSimilar ? "photo.on.rectangle" : "checkmark.seal",
                                   title: showSimilar ? (scanner.findSimilarImages ? "Keine ähnlichen Bilder" : "Ähnliche Bilder nicht gesucht")
                                                      : "Keine Duplikate gefunden",
                                   message: showSimilar && !scanner.findSimilarImages
                                       ? "Schalten Sie vor der Suche „Ähnliche Bilder finden“ ein."
                                       : "Im gewählten Bereich gibt es keine Dateien mit identischem Inhalt.")
                        .frame(minHeight: 260)
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(groups) { group in
                            DuplicateGroupCard(group: group, scanner: scanner, device: device)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, 100)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Auswahl von Bereich und Methode.
private struct ScanSetupPanel: View {
    @ObservedObject var scanner: DuplicateScanner
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let scopes = scanner.availableScopes(currentFolder: model.files.device.location)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                if scanner.state == .cancelled {
                    Label("Suche abgebrochen – es wurde nichts verändert.", systemImage: "stop.circle")
                        .font(Typo.bodyMedium).foregroundStyle(Palette.textSecondary)
                } else if case .failed(let reason) = scanner.state {
                    Label("Suche unterbrochen: \(reason). Es wurde nichts verändert.", systemImage: "exclamationmark.triangle.fill")
                        .font(Typo.bodyMedium).foregroundStyle(Palette.warning)
                }

                GlassSection(title: "Wo suchen?", symbol: "scope",
                             footer: "Mehrere Bereiche lassen sich kombinieren. Überschneidungen (z. B. „Gesamter Speicher“ und „DCIM“) werden nur einmal durchsucht. App-Daten (Android/data, Android/obb) und versteckte Ordner werden übersprungen.") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                        ForEach(scopes) { scope in
                            ScopeChip(scope: scope, selected: scanner.selectedScopes.contains(scope)) {
                                if scanner.selectedScopes.contains(scope) { scanner.selectedScopes.remove(scope) } else { scanner.selectedScopes.insert(scope) }
                            }
                        }
                    }
                }

                GlassSection(title: "Vergleich", symbol: "equal.square") {
                    LabeledRow(title: "Exakte Duplikate (immer)",
                               detail: "Dateien gelten nur dann als Duplikat, wenn ihr Inhalt byte-genau übereinstimmt (SHA-256) – unabhängig von Name, Ordner oder Speicher. Gleicher Name oder gleiche Größe allein genügt nie.") {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.bridgeGreen).font(.inter(18))
                    }
                    Divider().opacity(0.5)
                    LabeledRow(title: "Ähnliche Bilder finden",
                               detail: "Vergleicht zusätzlich die Vorschaubilder (Wahrnehmungs-Hash). Treffer werden getrennt als „ähnlich“ gezeigt und nie als identisch behandelt. Dauert länger.") {
                        Toggle("", isOn: $scanner.findSimilarImages).toggleStyle(.switch).labelsHidden()
                    }
                }

                GlassSection(title: "So schont die Suche Ihr Telefon", symbol: "bolt.horizontal") {
                    VStack(alignment: .leading, spacing: 8) {
                        step("1", "Ordner und Dateigrößen erfassen – ohne Inhalte zu lesen.")
                        step("2", "Nur Dateien mit gleicher Größe kommen in Frage.")
                        step("3", "Von diesen werden Anfang und Ende verglichen.")
                        step("4", "Nur bei Übereinstimmung wird die ganze Datei gelesen und per SHA-256 geprüft.")
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        scanner.start()
                    } label: {
                        Label("Suche starten", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(GlassButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(scanner.selectedScopes.isEmpty)
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, 40)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(n)
                .font(.inter(11, .bold))
                .foregroundStyle(Palette.bridgeGreen)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Palette.accentSoft))
            Text(text).font(Typo.body).foregroundStyle(Palette.textPrimary)
        }
    }
}

private struct ScopeChip: View {
    let scope: DuplicateScope
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: scope.symbolName)
                    .font(.inter(15, .medium))
                    .foregroundStyle(selected ? Palette.bridgeGreen : Palette.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? Palette.accentSoft : Palette.fieldFill))
                VStack(alignment: .leading, spacing: 1) {
                    Text(scope.title).font(Typo.bodyMedium).foregroundStyle(Palette.textPrimary).lineLimit(1)
                    Text(scope.subtitle).font(Typo.caption).foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.inter(16))
                    .foregroundStyle(selected ? Palette.bridgeGreen : Palette.textTertiary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                    .fill(selected ? Palette.selectionFill : (hovering ? Palette.hoverFill : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                    .strokeBorder(selected ? Palette.bridgeGreen.opacity(0.45) : Palette.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Fortschritt der Suche.
private struct ScanProgressPanel: View {
    let progress: DuplicateScanProgress
    let wantsSimilar: Bool
    let cancel: () -> Void

    private var phaseTitle: String {
        switch progress.phase {
        case .collecting: return "Ordner werden erfasst"
        case .grouping: return "Dateien gleicher Größe werden gesucht"
        case .fingerprint: return "Anfang und Ende werden verglichen"
        case .hashing: return "Inhalte werden per SHA-256 geprüft"
        case .similar: return "Ähnliche Bilder werden verglichen"
        case .done: return "Fertig"
        }
    }

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer(minLength: 0)
            ZStack {
                ProgressRing(fraction: progress.fraction, lineWidth: 8)
                    .frame(width: 132, height: 132)
                VStack(spacing: 0) {
                    Text("\(Int(progress.fraction * 100)) %").font(.display(28, .bold)).monospacedDigit()
                    Text(progress.phase == .collecting ? "Erfassen" : "Prüfen").font(Typo.caption).foregroundStyle(Palette.textSecondary)
                }
            }
            VStack(spacing: 6) {
                Text(phaseTitle).font(Typo.title2)
                Text(progress.currentLocation.isEmpty ? " " : progress.currentLocation)
                    .font(Typo.callout).foregroundStyle(Palette.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: 520)
            }
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                GridRow {
                    metric("Dateien gefunden", "\(progress.filesFound)")
                    metric("Ordner durchsucht", "\(progress.foldersScanned)")
                    metric("Gruppen gefunden", "\(progress.groupsFound)")
                }
                GridRow {
                    metric("Geprüft", progress.candidates > 0 ? "\(progress.examined) von \(progress.candidates)" : "–")
                    metric("Verbleibend", progress.candidates > 0 ? "\(progress.remaining)" : "–")
                    metric("Daten gelesen", ByteFormat.string(progress.bytesRead))
                }
            }
            .padding(20)
            .glassCard(cornerRadius: Radius.card)
            Button("Suche abbrechen", action: cancel)
                .buttonStyle(GlassButtonStyle())
                .keyboardShortcut(.cancelAction)
            Text("Die Suche liest nur – auf dem Telefon wird dabei nichts verändert.")
                .font(Typo.caption).foregroundStyle(Palette.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(Spacing.gutter)
        .frame(maxWidth: .infinity)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.display(17, .semibold)).monospacedDigit()
            Text(label).font(Typo.caption).foregroundStyle(Palette.textSecondary)
        }
        .frame(minWidth: 130, alignment: .leading)
    }
}

/// Hinweis nach einer Löschung aus der Duplikatliste.
private struct LastDeletionNote: View {
    let freed: UInt64
    let failures: [(name: String, reason: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(ByteFormat.string(freed)) frei geworden – Ergebnisse aktualisiert.", systemImage: "checkmark.circle.fill")
                .font(Typo.bodyMedium)
                .foregroundStyle(Palette.success)
            if !failures.isEmpty {
                Text("\(failures.count) Dateien wurden nicht gelöscht:").font(Typo.callout).foregroundStyle(Palette.danger)
                ForEach(Array(failures.prefix(8).enumerated()), id: \.offset) { _, f in
                    HStack(spacing: 6) {
                        Text(f.name).font(Typo.caption).lineLimit(1).truncationMode(.middle)
                        Text("– \(f.reason)").font(Typo.caption).foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Radius.tile)
    }
}

/// Eine Gruppe gleicher bzw. ähnlicher Dateien.
struct DuplicateGroupCard: View {
    @EnvironmentObject private var model: AppModel
    let group: DuplicateGroup
    @ObservedObject var scanner: DuplicateScanner
    let device: DeviceConnection

    private var skipped: Bool { scanner.skipped.contains(group.id) }
    private var markedInGroup: Int { group.files.filter { scanner.marked.contains($0.id) }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if group.kind == .identical {
                    TagLabel(text: "Identisch · SHA-256", symbol: "equal", tint: Palette.bridgeGreen)
                } else {
                    TagLabel(text: "Ähnlich – nicht identisch", symbol: "exclamationmark.triangle.fill", tint: Palette.warning)
                }
                Text("\(group.files.count) Dateien · \(ByteFormat.string(group.files[0].entry.size)) je Datei")
                    .font(Typo.callout).foregroundStyle(Palette.textSecondary).monospacedDigit()
                if skipped { TagLabel(text: "Übersprungen", tint: Palette.textSecondary) }
                Spacer()
                if markedInGroup > 0 {
                    Text("\(markedInGroup) zum Löschen markiert").font(Typo.captionMedium).foregroundStyle(Palette.danger)
                }
                Button("Vorschlag übernehmen") { scanner.applySuggestion(group) }
                    .buttonStyle(GlassButtonStyle(compact: true))
                Button(skipped ? "Einbeziehen" : "Überspringen") {
                    if skipped { scanner.skipped.remove(group.id) } else { scanner.skip(group) }
                }
                .buttonStyle(GlassButtonStyle(compact: true))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.5)

            ForEach(Array(group.files.enumerated()), id: \.element.id) { index, file in
                DuplicateFileRow(file: file, group: group, scanner: scanner, device: device)
                if index < group.files.count - 1 { Divider().opacity(0.4).padding(.leading, 112) }
            }
        }
        .glassCard(cornerRadius: Radius.card)
        .opacity(skipped ? 0.6 : 1)
    }
}

private struct DuplicateFileRow: View {
    @EnvironmentObject private var model: AppModel
    let file: DuplicateFile
    let group: DuplicateGroup
    @ObservedObject var scanner: DuplicateScanner
    let device: DeviceConnection
    @State private var hovering = false

    private var marked: Bool { scanner.marked.contains(file.id) }
    private var suggested: Bool { group.suggestedKeep == file.id }

    var body: some View {
        HStack(spacing: 14) {
            Button {
                scanner.toggle(file, in: group)
            } label: {
                Image(systemName: marked ? "trash.circle.fill" : "checkmark.circle")
                    .font(.inter(22))
                    .foregroundStyle(marked ? Palette.danger : Palette.bridgeGreen)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(marked ? "Wird gelöscht – klicken, um zu behalten" : "Wird behalten – klicken, um zum Löschen zu markieren")

            DeviceThumb(entry: file.entry, device: device, size: 52)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous).strokeBorder(Palette.hairline))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(file.entry.name)
                        .font(Typo.bodyMedium)
                        .strikethrough(marked, color: Palette.danger)
                        .foregroundStyle(marked ? Palette.textSecondary : Palette.textPrimary)
                        .lineLimit(1).truncationMode(.middle)
                    if suggested {
                        TagLabel(text: "Vorschlag: behalten", symbol: "star.fill", tint: Palette.bridgeGreen)
                            .help(group.suggestionReason)
                    }
                }
                Text(file.displayPath)
                    .font(Typo.caption).foregroundStyle(Palette.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 18) {
                detail(ByteFormat.string(file.entry.size), "Größe")
                if file.entry.imageWidth > 0 && file.entry.imageHeight > 0 {
                    detail("\(file.entry.imageWidth)×\(file.entry.imageHeight)", "Pixel")
                }
                detail(formatName, "Format")
                detail(file.entry.bestDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "–", "Datum")
                detail(file.storageName, "Speicher")
            }

            Button("Nur diese behalten") { scanner.keepOnly(file, in: group) }
                .buttonStyle(GlassButtonStyle(compact: true))
                .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(marked ? Palette.dangerSoft.opacity(0.6) : (hovering ? Palette.hoverFill : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button(marked ? "Behalten" : "Zum Löschen markieren") { scanner.toggle(file, in: group) }
            Button("Nur diese behalten") { scanner.keepOnly(file, in: group) }
            Divider()
            if file.entry.kind.isMedia {
                Button("Vorschau") {
                    let media = group.files.map(\.entry).filter { $0.kind.isMedia }
                    model.viewerItem = MediaViewerItem(deviceID: device.id, items: media, index: media.firstIndex(of: file.entry) ?? 0)
                }
            }
            Button("Im Dateimanager zeigen") {
                model.selection = .files
                Task { await model.files.device.navigate(storageID: file.entry.storageID, path: file.path) }
            }
        }
    }

    private var formatName: String {
        let ext = FileKind.fileExtension(of: file.entry.name)
        return ext.isEmpty ? kindName(file.entry.kind, name: file.entry.name) : ext.uppercased()
    }

    private func detail(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value).font(Typo.callout).foregroundStyle(Palette.textPrimary).monospacedDigit().lineLimit(1)
            Text(label).font(.inter(10)).foregroundStyle(Palette.textTertiary)
        }
        .frame(minWidth: 54, alignment: .trailing)
    }
}
