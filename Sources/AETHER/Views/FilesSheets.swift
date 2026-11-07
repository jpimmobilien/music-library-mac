import SwiftUI
import AppKit
import Quartz
import QuickLookThumbnailing
import UniformTypeIdentifiers
import AetherCore

// MARK: - Umbenennen

struct RenameSheet: View {
    @ObservedObject var browser: FileBrowserModel
    let item: FileItem
    let dismiss: () -> Void
    @State private var name = ""
    @Environment(\.aether) private var theme

    var body: some View {
        let problem = name.isEmpty ? nil : browser.renameProblem(for: item, newName: name)
        let hint = FileNaming.validate(name) == .hidden ? browser.problemText(.hidden) : nil
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                Image(nsImage: FileIcons.icon(for: item.url)).resizable().frame(width: 32, height: 32)
                Text(tr("Rename “%@”", item.fileName)).font(.system(size: 15, weight: .semibold)).lineLimit(1)
            }
            TextField(tr("Name"), text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(apply)
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(Typo.caption).foregroundStyle(theme.statusElevated)
            } else if let hint {
                Label(hint, systemImage: "eye.slash").font(Typo.caption).foregroundStyle(theme.textSecondary)
            }
            HStack {
                Spacer()
                Button(tr("Cancel"), action: dismiss).keyboardShortcut(.cancelAction)
                Button(tr("Rename"), action: apply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || problem != nil || name == item.fileName)
            }
        }
        .padding(Spacing.xxl)
        .frame(width: 420)
        .onAppear { name = item.fileName }
    }

    private func apply() {
        guard !name.isEmpty, browser.renameProblem(for: item, newName: name) == nil else { return }
        browser.rename(item, to: name)
        dismiss()
    }
}

struct BatchRenameSheet: View {
    @ObservedObject var browser: FileBrowserModel
    let items: [FileItem]
    let dismiss: () -> Void
    @Environment(\.aether) private var theme

    private enum Mode: String, CaseIterable, Identifiable {
        case replace, add, format
        var id: String { rawValue }
    }

    @State private var mode: Mode = .replace
    @State private var find = ""
    @State private var replacement = ""
    @State private var caseSensitive = false
    @State private var addText = ""
    @State private var addAtEnd = true
    @State private var baseName = ""
    @State private var start = 1
    @State private var digits = 2
    @State private var numberAtEnd = true

    var body: some View {
        let plan = currentPlan()
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(tr("Rename %ld Items", items.count)).font(.system(size: 15, weight: .semibold))
            Picker("", selection: $mode) {
                Text(tr("Replace Text")).tag(Mode.replace)
                Text(tr("Add Text")).tag(Mode.add)
                Text(tr("Format")).tag(Mode.format)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Group {
                switch mode {
                case .replace:
                    TextField(tr("Find"), text: $find).textFieldStyle(.roundedBorder)
                    TextField(tr("Replace with"), text: $replacement).textFieldStyle(.roundedBorder)
                    Toggle(tr("Match case"), isOn: $caseSensitive)
                case .add:
                    TextField(tr("Text"), text: $addText).textFieldStyle(.roundedBorder)
                    Picker(tr("Position"), selection: $addAtEnd) {
                        Text(tr("Before name")).tag(false)
                        Text(tr("After name")).tag(true)
                    }
                    .pickerStyle(.segmented)
                case .format:
                    TextField(tr("Name"), text: $baseName).textFieldStyle(.roundedBorder)
                    HStack {
                        Stepper(tr("Start at %ld", start), value: $start, in: 0...99_999)
                        Stepper(tr("%ld digits", digits), value: $digits, in: 1...6)
                    }
                    Picker(tr("Number"), selection: $numberAtEnd) {
                        Text(tr("Before name")).tag(false)
                        Text(tr("After name")).tag(true)
                    }
                    .pickerStyle(.segmented)
                }
            }
            Text(tr("Preview")).font(Typo.captionMedium).foregroundStyle(theme.textSecondary)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(plan.enumerated()), id: \.offset) { _, entry in
                        HStack(spacing: 6) {
                            Text(entry.original).lineLimit(1).truncationMode(.middle).foregroundStyle(theme.textSecondary)
                            Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(theme.textTertiary)
                            Text(entry.proposed).lineLimit(1).truncationMode(.middle)
                                .foregroundStyle(entry.problem == nil ? theme.textPrimary : theme.statusElevated)
                            if let problem = entry.problem {
                                Text(problemText(problem)).font(Typo.caption).foregroundStyle(theme.statusElevated)
                            }
                        }
                        .font(Typo.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 160)
            HStack {
                Text(tr("File extensions stay unchanged. Undo with ⌘Z.")).font(Typo.caption).foregroundStyle(theme.textTertiary)
                Spacer()
                Button(tr("Cancel"), action: dismiss).keyboardShortcut(.cancelAction)
                Button(tr("Rename")) {
                    browser.applyBatchRename(plan, items: items)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!BatchRenamePlanner.canApply(plan))
            }
        }
        .padding(Spacing.xxl)
        .frame(width: 560)
    }

    private func currentPlan() -> [BatchRenameEntry] {
        let batchMode: BatchRenameMode
        switch mode {
        case .replace: batchMode = .replace(find: find, with: replacement, caseSensitive: caseSensitive)
        case .add: batchMode = .add(text: addText, atEnd: addAtEnd)
        case .format: batchMode = .format(base: baseName, start: start, digits: digits, atEnd: numberAtEnd)
        }
        let folder = items.first?.url.deletingLastPathComponent()
        let renamed = Set(items.map(\.fileName))
        let others = Set(((folder.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) }) ?? [])
            .filter { !renamed.contains($0) })
        return BatchRenamePlanner.plan(items.map { (name: $0.fileName, isDirectory: $0.isFolder || $0.isPackage) }, mode: batchMode,
                                       others: others)
    }

    private func problemText(_ problem: BatchRenameProblem) -> String {
        switch problem {
        case .invalidName(let issue): return browser.problemText(issue)
        case .duplicateInBatch: return tr("used twice")
        case .existsInFolder: return tr("already exists")
        }
    }
}

// MARK: - Informationen

struct FileInspector: View {
    @ObservedObject var browser: FileBrowserModel
    @Environment(\.aether) private var theme

    var body: some View {
        let selected = browser.selectedItems
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                if selected.count == 1, let item = selected.first {
                    SingleInfo(browser: browser, item: item)
                } else if selected.count > 1 {
                    MultiInfo(browser: browser, items: selected)
                } else if let folder = FileItem(url: browser.location) {
                    SingleInfo(browser: browser, item: folder)
                }
            }
            .padding(Spacing.l)
        }
    }
}

private struct SingleInfo: View {
    @ObservedObject var browser: FileBrowserModel
    let item: FileItem
    @Environment(\.aether) private var theme
    @State private var thumbnail: NSImage?
    @State private var details: FileDetails?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Spacer()
                Image(nsImage: thumbnail ?? FileIcons.icon(for: item.url))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 150, maxHeight: 150)
                Spacer()
            }
            Text(item.name).font(Typo.bodyMedium).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Text(item.kind).font(Typo.caption).foregroundStyle(theme.textSecondary)
            Divider().overlay(theme.hairline)
            if item.isFolder {
                HStack {
                    Text(tr("Size")).font(Typo.callout).foregroundStyle(theme.textSecondary)
                    Spacer()
                    if let size = browser.folderSizes[item.url] {
                        Text(fmt.bytes(size)).font(Typo.callout.weight(.medium)).monospacedDigit()
                    } else if browser.sizing.contains(item.url) {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(tr("Calculate")) { browser.computeFolderSizes([item.url]) }.buttonStyle(CapsuleButtonStyle())
                    }
                }
            } else {
                if let size = item.size { infoRow(tr("Size"), fmt.bytes(size) + " (" + tr("%@ bytes", fmt.integer(Int(size))) + ")") }
                if let allocated = item.allocatedSize { infoRow(tr("On disk"), fmt.bytes(allocated)) }
            }
            // Gruppe: kleine Builder-Blöcke halten die Typprüfung schnell
            Group {
                if let created = item.created { infoRow(tr("Created"), DateFormatter.localizedString(from: created, dateStyle: .medium, timeStyle: .short)) }
                if let modified = item.modified { infoRow(tr("Modified"), DateFormatter.localizedString(from: modified, dateStyle: .medium, timeStyle: .short)) }
                if let opened = details?.lastOpened { infoRow(tr("Last opened"), DateFormatter.localizedString(from: opened, dateStyle: .medium, timeStyle: .short)) }
                infoRow(tr("Where"), displayPath(item.url.deletingLastPathComponent()))
                if let permissions = details?.permissions { infoRow(tr("Permissions"), permissions) }
                if let owner = details?.owner { infoRow(tr("Owner"), owner) }
                if let type = item.contentType?.identifier { infoRow(tr("Type"), type) }
                if let count = details?.itemCount { infoRow(tr("Contains"), tr("%ld items", count)) }
            }
            Divider().overlay(theme.hairline)
            HStack(spacing: Spacing.s) {
                Button(tr("Open")) { browser.open(item) }.buttonStyle(CapsuleButtonStyle())
                Button(tr("Show in Finder")) { browser.showInFinder([item.url]) }.buttonStyle(CapsuleButtonStyle())
            }
            HStack(spacing: Spacing.s) {
                Button(tr("Copy Path")) { browser.copyPaths([item.url]) }.buttonStyle(CapsuleButtonStyle())
                ShareLink(item: item.url) { Text(tr("Share…")) }.buttonStyle(CapsuleButtonStyle())
            }
        }
        .task(id: item.url) { await load() }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(Typo.caption).foregroundStyle(theme.textTertiary)
            Text(value).font(Typo.callout).textSelection(.enabled).lineLimit(3).truncationMode(.middle)
        }
    }

    private func load() async {
        thumbnail = nil
        let url = item.url
        let isFolder = item.isFolder
        details = await Task.detached(priority: .utility) { FileDetails.read(url, countChildren: isFolder) }.value
        guard !browser.isSnapshotMode, !isFolder else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 150, height: 150), scale: scale,
                                                   representationTypes: .thumbnail)
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request),
           item.url == url {
            thumbnail = representation.nsImage
        }
    }
}

/// Zusätzliche Angaben für die Informationen (außerhalb des Hauptthreads gelesen).
struct FileDetails: Sendable {
    var lastOpened: Date?
    var permissions: String?
    var owner: String?
    var itemCount: Int?

    static func read(_ url: URL, countChildren: Bool) -> FileDetails {
        var details = FileDetails()
        details.lastOpened = (try? url.resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
            if let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue { details.permissions = PosixPermissions.string(mode) }
            details.owner = attributes[.ownerAccountName] as? String
        }
        if countChildren {
            details.itemCount = (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.count
        }
        return details
    }
}

private struct MultiInfo: View {
    @ObservedObject var browser: FileBrowserModel
    let items: [FileItem]
    @Environment(\.aether) private var theme

    var body: some View {
        let files = items.filter { !$0.isFolder }
        let folders = items.filter(\.isFolder)
        let fileBytes = files.compactMap(\.size).reduce(0, +)
        let folderBytes = folders.compactMap { browser.folderSizes[$0.url] }.reduce(0, +)
        let allFoldersKnown = folders.allSatisfy { browser.folderSizes[$0.url] != nil }
        VStack(alignment: .leading, spacing: Spacing.s) {
            Image(systemName: "doc.on.doc").font(.system(size: 40, weight: .light)).foregroundStyle(theme.textSecondary)
                .frame(maxWidth: .infinity)
            Text(tr("%ld items selected", items.count)).font(Typo.bodyMedium)
            Text(tr("%ld files · %ld folders", files.count, folders.count)).font(Typo.caption).foregroundStyle(theme.textSecondary)
            Divider().overlay(theme.hairline)
            HStack {
                Text(tr("Total size")).font(Typo.callout).foregroundStyle(theme.textSecondary)
                Spacer()
                Text(fmt.bytes(fileBytes + folderBytes)).font(Typo.callout.weight(.medium)).monospacedDigit()
            }
            if !allFoldersKnown {
                Text(tr("Folder sizes not yet included.")).font(Typo.caption).foregroundStyle(theme.textTertiary)
                Button(tr("Calculate")) { browser.computeFolderSizes(folders.map(\.url)) }.buttonStyle(CapsuleButtonStyle())
            }
        }
    }
}

// MARK: - Quick Look

/// Datenquelle für das Quick-Look-Fenster.
final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()
    var urls: [URL] = []

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard urls.indices.contains(index) else { return nil }
        return urls[index] as NSURL
    }
}

/// Ein unsichtbares Element in der Responder-Kette, das Quick Look die Daten gibt (so verlangt es QLPreviewPanel).
final class QuickLookResponderView: NSView {
    override var acceptsFirstResponder: Bool { true }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = QuickLookController.shared
        panel.delegate = QuickLookController.shared
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}

struct QuickLookAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> QuickLookResponderView {
        let view = QuickLookResponderView()
        QuickLook.anchor = view
        return view
    }

    func updateNSView(_ view: QuickLookResponderView, context: Context) {
        QuickLook.anchor = view
    }
}

@MainActor
enum QuickLook {
    static weak var anchor: QuickLookResponderView?

    static var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && (QLPreviewPanel.shared()?.isVisible ?? false)
    }

    /// Zeigt oder schließt die Vorschau (Leertaste, ⌘Y).
    static func toggle(_ urls: [URL]) {
        if isVisible {
            QLPreviewPanel.shared()?.orderOut(nil)
            return
        }
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        QuickLookController.shared.urls = urls
        if let anchor, let window = anchor.window {
            window.makeFirstResponder(anchor)
        }
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    /// Bei geänderter Auswahl die offene Vorschau nachführen.
    static func update(_ urls: [URL]) {
        guard isVisible, !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        QuickLookController.shared.urls = urls
        panel.reloadData()
    }
}
