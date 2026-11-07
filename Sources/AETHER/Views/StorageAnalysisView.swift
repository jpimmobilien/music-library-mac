import SwiftUI
import AppKit
import AetherCore
import AetherSystem

// =============================================================================================
// Ordneranalyse und Bereinigungsvorschläge der Speicherseite.
// =============================================================================================

func storageCategoryName(_ category: FileCategory) -> String {
    switch category {
    case .images: return tr("Images")
    case .videos: return tr("Videos")
    case .audio: return tr("Audio")
    case .documents: return tr("Documents")
    case .archives: return tr("Archives and disk images")
    case .applications: return tr("Apps")
    case .code: return tr("Code and developer files")
    case .other: return tr("Other")
    }
}

func storageCategorySymbol(_ category: FileCategory) -> String {
    switch category {
    case .images: return "photo"
    case .videos: return "film"
    case .audio: return "music.note"
    case .documents: return "doc.text"
    case .archives: return "archivebox"
    case .applications: return "app.badge"
    case .code: return "chevron.left.forwardslash.chevron.right"
    case .other: return "doc"
    }
}

extension AetherTheme {
    func color(for category: FileCategory) -> Color {
        switch category {
        case .images: return gpu
        case .videos: return cpuUser
        case .audio: return networkUp
        case .documents: return storage
        case .archives: return memoryCompressed
        case .applications: return accent
        case .code: return battery
        case .other: return statusUnavailable
        }
    }
}

/// Pfad mit „~“ statt Benutzerordner.
func storageDisplayPath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path == home { return "~" }
    if path.hasPrefix(home + "/") { return "~" + String(path.dropFirst(home.count)) }
    return path
}

// MARK: - Ordneranalyse

struct FolderAnalysisPanel: View {
    @ObservedObject var analysis: StorageAnalysisModel
    let isSnapshot: Bool
    let openInFiles: (URL) -> Void
    @Environment(\.aether) private var theme
    @State private var pending: StorageAnalysisModel.PendingTrash? = nil
    @State private var tab: ResultTab = .largest

    enum ResultTab: String, CaseIterable, Identifiable {
        case largest, folders, categories, duplicates
        var id: String { rawValue }
    }

    var body: some View {
        Panel {
            PanelTitle(title: tr("Folder analysis"), symbol: "magnifyingglass")
            controls
            status
            if let notice = analysis.notice {
                HStack(spacing: Spacing.m) {
                    NoticeBar(text: notice.text, symbol: notice.isError ? "exclamationmark.triangle" : "trash")
                    if notice.canUndo {
                        Button(tr("Put Back")) { analysis.undoTrash() }
                            .buttonStyle(CapsuleButtonStyle())
                    }
                }
            }
            if let result = analysis.result {
                summary(result)
                Picker("", selection: $tab) {
                    Text(tr("Largest files")).tag(ResultTab.largest)
                    Text(tr("Folders")).tag(ResultTab.folders)
                    Text(tr("Categories")).tag(ResultTab.categories)
                    Text(result.duplicates.isEmpty ? tr("Duplicates") : tr("Duplicates (%ld)", result.duplicates.count))
                        .tag(ResultTab.duplicates)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 560)
                switch tab {
                case .largest: largestFiles(result)
                case .folders: folders(result)
                case .categories: categories(result)
                case .duplicates: duplicates(result)
                }
            }
        }
        .alert(Text(tr("Move %ld items to the Trash?", pending?.files.count ?? 0)),
               isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
               presenting: pending) { item in
            Button(tr("Move to Trash"), role: .destructive) { analysis.trash(item) }
            Button(tr("Cancel"), role: .cancel) {}
        } message: { item in
            Text(confirmationMessage(item))
        }
    }

    // MARK: Steuerung

    private var controls: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "folder").foregroundStyle(theme.textSecondary)
            Text(storageDisplayPath(analysis.root.path))
                .font(Typo.mono).lineLimit(1).truncationMode(.middle)
                .help(analysis.root.path)
            Spacer(minLength: Spacing.s)
            Button(tr("Choose Folder…")) { analysis.chooseFolder() }
                .buttonStyle(CapsuleButtonStyle())
                .disabled(analysis.isRunning || isSnapshot)
            if analysis.isRunning {
                Button(tr("Stop")) { analysis.cancel() }
                    .buttonStyle(CapsuleButtonStyle())
            } else {
                Button(analysis.result == nil ? tr("Start Analysis") : tr("Analyse Again")) { analysis.start() }
                    .buttonStyle(CapsuleButtonStyle(prominent: true))
                    .disabled(isSnapshot)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch analysis.phase {
        case .idle:
            Text(tr("Finds the largest files and folders, groups the contents by kind and looks for identical copies. Runs only when you start it; macOS may ask for access to protected folders such as Desktop, Documents or Downloads."))
                .font(Typo.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        case .running(let progress):
            VStack(alignment: .leading, spacing: 6) {
                if progress.phase == .comparing, progress.total > 0 {
                    ProgressView(value: Double(progress.done), total: Double(progress.total))
                    Text(tr("Comparing possible duplicates: %ld of %ld files", progress.done, progress.total))
                        .font(Typo.callout).monospacedDigit()
                } else {
                    ProgressView().progressViewStyle(.linear)
                    Text(tr("%ld files · %@ analysed", progress.files, fmt.bytes(progress.bytes)))
                        .font(Typo.callout).monospacedDigit()
                }
                Text(storageDisplayPath(progress.currentPath))
                    .font(Typo.mono).foregroundStyle(theme.textTertiary).lineLimit(1).truncationMode(.middle)
            }
        case .finished:
            EmptyView()
        }
    }

    // MARK: Zusammenfassung

    @ViewBuilder
    private func summary(_ result: StorageScanResult) -> some View {
        if result.cancelled {
            NoticeBar(text: tr("The analysis was stopped – all numbers are incomplete."), symbol: "exclamationmark.triangle")
        }
        HStack(alignment: .top, spacing: Spacing.xxl) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Occupied")).font(Typo.captionMedium).foregroundStyle(theme.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    let parts = fmt.byteParts(Double(result.totalSize))
                    ValueText(value: parts.value, unit: parts.unit, font: Typo.metric)
                    ProvenanceBadge(source: .folderScan, timestamp: result.finished)
                }
            }
            Stat(label: tr("Files"), value: fmt.integer(result.fileCount))
            Stat(label: tr("Folders"), value: fmt.integer(result.folderCount))
            if result.unreadableCount > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Not readable")).font(Typo.captionMedium).foregroundStyle(theme.textSecondary)
                    Text(fmt.integer(result.unreadableCount)).font(Typo.metricSmall).monospacedDigit()
                        .foregroundStyle(theme.statusElevated)
                    Text(tr("privacy protection or missing rights – not included"))
                        .font(Typo.caption).foregroundStyle(theme.textTertiary)
                }
                .help(result.unreadableSamples.map(storageDisplayPath).joined(separator: "\n"))
            }
            Spacer(minLength: 0)
        }
        if result.skippedOtherVolumes > 0 {
            Text(tr("%ld other volumes inside this folder were not included.", result.skippedOtherVolumes))
                .font(Typo.caption).foregroundStyle(theme.textTertiary)
        }
    }

    // MARK: Größte Dateien

    @ViewBuilder
    private func largestFiles(_ result: StorageScanResult) -> some View {
        let list = StorageAnalysis.largest(result.files, minimum: analysis.thresholdBytes, limit: 200)
        HStack(spacing: Spacing.m) {
            Picker("", selection: $analysis.threshold) {
                Text("≥ 100 MB").tag(StorageAnalysisModel.ThresholdChoice.mb100)
                Text("≥ 500 MB").tag(StorageAnalysisModel.ThresholdChoice.mb500)
                Text("≥ 1 GB").tag(StorageAnalysisModel.ThresholdChoice.gb1)
                Text(tr("Custom")).tag(StorageAnalysisModel.ThresholdChoice.custom)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 360)
            if analysis.threshold == .custom {
                Text("≥").font(Typo.callout)
                TextField("", value: $analysis.customMegabytes, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Text("MB").font(Typo.callout).foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 0)
            Text(tr("%ld files", list.count)).font(Typo.caption).foregroundStyle(theme.textSecondary)
        }
        if list.isEmpty {
            Text(tr("No files of this size in the analysed folder.")).font(Typo.callout).foregroundStyle(theme.textSecondary)
        } else {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(list) { file in
                    fileRow(file, root: result.rootPath, shareHint: false)
                }
            }
            if list.count == 200 {
                Text(tr("Showing the 200 largest files.")).font(Typo.caption).foregroundStyle(theme.textTertiary)
            }
        }
        trashBar
    }

    // MARK: Ordner

    @ViewBuilder
    private func folders(_ result: StorageScanResult) -> some View {
        let top = Array(result.folders.prefix(20))
        let largest = max(top.first?.size ?? 1, 1)
        if top.isEmpty {
            Text(tr("No folders found.")).font(Typo.callout).foregroundStyle(theme.textSecondary)
        }
        ForEach(top) { folder in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: folder.isLooseFiles ? "doc.on.doc" : "folder").foregroundStyle(theme.storage).frame(width: 18)
                    Text(folder.isLooseFiles ? tr("Files directly in this folder") : folder.name)
                        .font(Typo.bodyMedium).lineLimit(1)
                    Text(tr("%ld files", folder.files)).font(Typo.caption).foregroundStyle(theme.textTertiary)
                    Spacer(minLength: 8)
                    Text(fmt.bytes(folder.size)).font(Typo.callout.weight(.medium)).monospacedDigit()
                    if !folder.isLooseFiles {
                        iconButton("folder", tr("Open in Files")) { openInFiles(URL(fileURLWithPath: folder.path)) }
                        iconButton("magnifyingglass", tr("Show in Finder")) {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder.path)])
                        }
                    }
                }
                FillBar(fraction: Double(folder.size) / Double(largest), color: theme.storage, height: 5)
            }
            .padding(.vertical, 3)
        }
    }

    // MARK: Kategorien

    @ViewBuilder
    private func categories(_ result: StorageScanResult) -> some View {
        let total = max(result.categories.reduce(Int64(0)) { $0 + $1.size }, 1)
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(result.categories) { entry in
                    Rectangle()
                        .fill(theme.color(for: entry.category))
                        .frame(width: max(2, (geo.size.width - CGFloat(result.categories.count) * 2) * CGFloat(Double(entry.size) / Double(total))))
                }
                Spacer(minLength: 0)
            }
            .clipShape(Capsule())
        }
        .frame(height: 12)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: Spacing.l, alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(result.categories) { entry in
                HStack(spacing: 8) {
                    Circle().fill(theme.color(for: entry.category)).frame(width: 9, height: 9)
                    Image(systemName: storageCategorySymbol(entry.category)).font(.system(size: 11)).foregroundStyle(theme.textSecondary)
                    Text(storageCategoryName(entry.category)).font(Typo.callout).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(fmt.bytes(entry.size)).font(Typo.callout.weight(.medium)).monospacedDigit()
                    Text(fmt.percent(Double(entry.size) / Double(total))).font(Typo.caption).foregroundStyle(theme.textTertiary)
                        .monospacedDigit().frame(width: 40, alignment: .trailing)
                }
                .help(tr("%ld files", entry.files))
            }
        }
        Text(tr("Kinds are derived from file extensions only; contents are not inspected."))
            .font(Typo.caption).foregroundStyle(theme.textTertiary)
    }

    // MARK: Duplikate

    @ViewBuilder
    private func duplicates(_ result: StorageScanResult) -> some View {
        if !result.duplicatesChecked {
            Text(tr("Duplicates weren’t checked because the analysis was stopped."))
                .font(Typo.callout).foregroundStyle(theme.textSecondary)
        } else if result.duplicates.isEmpty {
            Text(tr("No identical files of 1 MB or more found.")).font(Typo.callout).foregroundStyle(theme.textSecondary)
        } else {
            let reclaimable = result.duplicates.reduce(Int64(0)) { $0 + $1.reclaimable }
            HStack(spacing: 6) {
                Text(tr("%ld groups of identical files · up to %@ could be freed", result.duplicates.count, fmt.bytes(reclaimable)))
                    .font(Typo.callout)
                ProvenanceBadge(source: .duplicateCheck, timestamp: result.finished)
            }
            Text(tr("Nothing is selected automatically. Tick the copies you don’t need – keep at least one of each group."))
                .font(Typo.caption).foregroundStyle(theme.textTertiary)
            LazyVStack(alignment: .leading, spacing: Spacing.m) {
                ForEach(Array(result.duplicates.prefix(100))) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: storageCategorySymbol(group.files.first?.category ?? .other))
                                .foregroundStyle(theme.storage)
                            Text(tr("%ld copies · %@ each", group.files.count, fmt.bytes(group.size)))
                                .font(Typo.captionMedium)
                            Text(String(group.hash.prefix(12))).font(Typo.mono).foregroundStyle(theme.textTertiary)
                                .help("SHA-256 \(group.hash)")
                            Spacer(minLength: 0)
                        }
                        ForEach(group.files) { file in
                            fileRow(file, root: result.rootPath, shareHint: group.mayShareBlocks.contains(file.path))
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).fill(theme.fieldFill.opacity(0.5)))
                }
            }
            if result.duplicates.count > 100 {
                Text(tr("Showing the 100 groups that free the most space.")).font(Typo.caption).foregroundStyle(theme.textTertiary)
            }
        }
        trashBar
    }

    // MARK: Zeilen und Papierkorb

    private func fileRow(_ file: ScannedFile, root: String, shareHint: Bool) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { analysis.selection.contains(file.path) },
                                     set: { on in
                                         if on { analysis.selection.insert(file.path) } else { analysis.selection.remove(file.path) }
                                     }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            Image(systemName: storageCategorySymbol(file.category))
                .font(.system(size: 12)).foregroundStyle(theme.color(for: file.category)).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).font(Typo.callout).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(relativeFolder(file, root: root)).font(Typo.caption).foregroundStyle(theme.textTertiary)
                        .lineLimit(1).truncationMode(.middle)
                    if shareHint {
                        StorageTag(text: tr("may share storage (APFS clone)"))
                            .help(tr("The file system reports that this file may share its data with other files. Moving it to the Trash may free less space than its size."))
                    }
                }
            }
            Spacer(minLength: 8)
            if let modified = file.modified {
                Text(DateFormatter.localizedString(from: modified, dateStyle: .medium, timeStyle: .none))
                    .font(Typo.caption).foregroundStyle(theme.textTertiary).lineLimit(1)
            }
            Text(fmt.bytes(file.size)).font(Typo.callout.weight(.medium)).monospacedDigit().frame(minWidth: 70, alignment: .trailing)
            iconButton("folder", tr("Show in Files")) { openInFiles(URL(fileURLWithPath: file.parentPath)) }
            iconButton("magnifyingglass", tr("Show in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
            }
        }
        .padding(.vertical, 3)
        .help(file.path)
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(theme.textSecondary)
        .help(help)
    }

    private func relativeFolder(_ file: ScannedFile, root: String) -> String {
        let parent = file.parentPath
        let prefix = root.hasSuffix("/") ? root : root + "/"
        if parent == root || parent + "/" == prefix { return storageDisplayPath(root) }
        if parent.hasPrefix(prefix) { return "…/" + String(parent.dropFirst(prefix.count)) }
        return storageDisplayPath(parent)
    }

    @ViewBuilder
    private var trashBar: some View {
        if !analysis.selection.isEmpty, let prepared = analysis.prepareTrash(analysis.selection) {
            HStack(spacing: Spacing.m) {
                Text(tr("%ld selected · %@", prepared.files.count, fmt.bytes(prepared.totalSize)))
                    .font(Typo.callout).monospacedDigit()
                Spacer(minLength: 0)
                Button(tr("Deselect All")) { analysis.selection = [] }
                    .buttonStyle(CapsuleButtonStyle())
                Button(tr("Move to Trash…")) { pending = prepared }
                    .buttonStyle(CapsuleButtonStyle(prominent: true))
                    .disabled(isSnapshot)
            }
            .padding(.top, 4)
        }
    }

    private func confirmationMessage(_ item: StorageAnalysisModel.PendingTrash) -> String {
        var lines = item.files.prefix(8).map { "• \($0.name) (\(fmt.bytes($0.size)))" }
        if item.files.count > 8 {
            lines.append(tr("… and %ld more", item.files.count - 8))
        }
        lines.append("")
        lines.append(tr("Total: %@. You can put the items back right afterwards or restore them from the Trash.", fmt.bytes(item.totalSize)))
        if item.fullySelectedGroups > 0 {
            lines.append(tr("Caution: for %ld duplicate groups all copies are selected – no copy would remain outside the Trash.",
                            item.fullySelectedGroups))
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Bereinigungsvorschläge

struct CleanupPanel: View {
    @ObservedObject var cleanup: CleanupModel
    let isSnapshot: Bool
    @Environment(\.aether) private var theme

    var body: some View {
        Panel {
            HStack {
                PanelTitle(title: tr("Cleanup suggestions"), symbol: "sparkles")
                if cleanup.measuring {
                    ProgressView().controlSize(.small)
                }
                Button(cleanup.measurements.isEmpty ? tr("Measure") : tr("Measure Again")) { cleanup.measure() }
                    .buttonStyle(CapsuleButtonStyle())
                    .disabled(cleanup.measuring || isSnapshot)
            }
            Text(tr("Places that often grow large. AETHER only measures them – nothing is deleted. Decide in the Finder what you want to remove."))
                .font(Typo.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            ForEach(cleanup.measurements) { measurement in
                CleanupRow(measurement: measurement)
                if measurement.id != cleanup.measurements.last?.id {
                    Divider().overlay(theme.hairline)
                }
            }
        }
    }
}

private struct CleanupRow: View {
    let measurement: CleanupMeasurement
    @Environment(\.aether) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(theme.storage).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.bodyMedium)
                Text(explanation).font(Typo.caption).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                Text(storageDisplayPath(measurement.path)).font(Typo.mono).foregroundStyle(theme.textTertiary).lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                switch measurement.state {
                case .measured(let bytes, let items, let partial):
                    HStack(spacing: 5) {
                        Text(fmt.bytes(bytes)).font(Typo.callout.weight(.semibold)).monospacedDigit()
                        ProvenanceBadge(source: .folderScan)
                    }
                    Text(tr("%ld files", items)).font(Typo.caption).foregroundStyle(theme.textTertiary).monospacedDigit()
                    if partial {
                        Text(tr("partly not readable")).font(Typo.caption).foregroundStyle(theme.statusElevated)
                    }
                case .notPresent:
                    Text(tr("Not present")).font(Typo.callout).foregroundStyle(theme.textTertiary)
                case .notReadable:
                    Text(tr("Not readable – privacy protection")).font(Typo.callout).foregroundStyle(theme.textSecondary)
                        .help(tr("macOS only lets apps with Full Disk Access read this folder. AETHER doesn’t ask for it."))
                }
                if measurement.state != .notPresent {
                    Button(tr("Show in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: measurement.path)])
                    }
                    .buttonStyle(CapsuleButtonStyle())
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var symbol: String {
        switch measurement.kind {
        case .downloads: return "arrow.down.circle"
        case .caches: return "internaldrive"
        case .xcodeDerivedData: return "hammer"
        case .iosBackups: return "iphone"
        case .trash: return "trash"
        }
    }

    private var title: String {
        switch measurement.kind {
        case .downloads: return tr("Downloads")
        case .caches: return tr("App caches")
        case .xcodeDerivedData: return tr("Xcode build data")
        case .iosBackups: return tr("iPhone and iPad backups")
        case .trash: return tr("Trash")
        }
    }

    private var explanation: String {
        switch measurement.kind {
        case .downloads: return tr("Files you downloaded – often installers and archives you no longer need.")
        case .caches: return tr("Temporary data apps recreate when needed. Quit the apps before removing anything here.")
        case .xcodeDerivedData: return tr("Intermediate build products of Xcode. Xcode recreates them on the next build.")
        case .iosBackups: return tr("Local device backups. Only remove backups you no longer need; manage them in the Finder with the device connected.")
        case .trash: return tr("Items already in the Trash. The space is only freed when you empty it in the Finder.")
        }
    }
}
