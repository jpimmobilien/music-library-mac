import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AetherCore

/// Dateien (Finder Plus): Seitenleiste, Liste/Symbole/Spalten, Spotlight-Suche, Dateioperationen mit Widerrufen,
/// Quick Look, Informationen. Nichts wird endgültig gelöscht – nur in den Papierkorb gelegt.
struct FilesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        FilesContent(browser: model.files, storage: model.engine.storage)
    }
}

private struct FilesContent: View {
    @ObservedObject var browser: FileBrowserModel
    @ObservedObject var storage: StorageStore
    @EnvironmentObject private var model: AppModel
    @Environment(\.aether) private var theme
    @Environment(\.undoManager) private var undoManager
    @FocusState private var searchFocused: Bool
    @State private var renaming: FileItem?
    @State private var batchRenaming: BatchRenameRequest?
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            PageHeader(title: tr("Files"), subtitle: displayPath(browser.location)) {
                SearchControls(browser: browser, focused: $searchFocused)
            }
            HStack(spacing: 0) {
                FilesSidebar(browser: browser, volumes: storage.snapshot?.volumes ?? [])
                    .frame(width: 196)
                Rectangle().fill(theme.hairline).frame(width: 1)
                VStack(spacing: 0) {
                    FilesToolbar(browser: browser, rename: startRename)
                    Rectangle().fill(theme.hairline).frame(height: 1)
                    if let banner = browser.banner {
                        BannerRow(banner: banner, browser: browser)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    mainContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .bottom) {
                            if let operation = browser.operation {
                                OperationRow(operation: operation) { browser.cancelOperation() }
                                    .padding(Spacing.m)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                            guard browser.results == nil else { return false }
                            return browser.handleDrop(providers, into: browser.location)
                        }
                        .overlay {
                            if dropTargeted {
                                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                                    .strokeBorder(theme.accent, lineWidth: 2)
                                    .padding(4)
                                    .allowsHitTesting(false)
                            }
                        }
                    Rectangle().fill(theme.hairline).frame(height: 1)
                    PathAndStatusBar(browser: browser)
                }
                if browser.showInspector {
                    Rectangle().fill(theme.hairline).frame(width: 1)
                    FileInspector(browser: browser)
                        .frame(width: 270)
                }
            }
            .glassCard(cornerRadius: Radius.panel)
            .padding(.bottom, Spacing.gutter)
        }
        .padding(.horizontal, Spacing.gutter)
        .background(ShortcutButtons(browser: browser, disabled: searchFocused, rename: startRename,
                                    focusSearch: { searchFocused = true }))
        .background(QuickLookAnchor())
        .aetherAnimation(Motion.spring, value: browser.operation != nil)
        .aetherAnimation(Motion.spring, value: browser.banner?.text)
        .sheet(item: $renaming) { item in
            RenameSheet(browser: browser, item: item) { renaming = nil }
        }
        .sheet(item: $batchRenaming) { request in
            BatchRenameSheet(browser: browser, items: request.items) { batchRenaming = nil }
        }
        .onAppear {
            browser.undoManager = undoManager
            browser.start()
            if let request = model.filesRequest {
                browser.reveal(request)
                model.filesRequest = nil
            }
        }
        .onChange(of: model.filesRequest) { request in
            guard let request else { return }
            browser.reveal(request)
            model.filesRequest = nil
        }
        .onChange(of: browser.selection) { _ in
            QuickLook.update(browser.selectedItems.map(\.url))
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if let results = browser.results {
            VStack(spacing: 0) {
                ResultsHeader(results: results) { browser.clearResults() }
                if results.items.isEmpty && !results.isGathering {
                    EmptyState(symbol: "magnifyingglass", title: tr("No results"),
                               detail: tr("Spotlight found nothing that matches. Try another term or a wider search scope."))
                } else {
                    FileTable(browser: browser, items: results.items, showsLocation: true, rename: startRename)
                }
            }
        } else {
            switch browser.state {
            case .loading:
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .noPermission:
                AccessDeniedView(browser: browser)
            case .notFound:
                EmptyState(symbol: "questionmark.folder", title: tr("Folder not found"),
                           detail: tr("The folder was moved or deleted."))
            case .failed(let message):
                EmptyState(symbol: "exclamationmark.triangle", title: tr("The folder couldn’t be read"), detail: message)
            case .loaded:
                if browser.items.isEmpty && browser.viewMode != .columns {
                    EmptyState(symbol: "folder", title: tr("This folder is empty"),
                               detail: tr("Drop files here to move or copy them into this folder."))
                } else {
                    switch browser.viewMode {
                    case .list: FileTable(browser: browser, items: browser.items, showsLocation: false, rename: startRename)
                    case .icons: IconGrid(browser: browser, rename: startRename)
                    case .columns: ColumnBrowser(browser: browser)
                    }
                }
            }
        }
    }

    private func startRename() {
        let selected = browser.selectedItems
        if selected.count == 1 {
            renaming = selected.first
        } else if selected.count > 1 {
            batchRenaming = BatchRenameRequest(items: selected)
        }
    }
}

struct BatchRenameRequest: Identifiable {
    let id = UUID()
    let items: [FileItem]
}

/// Pfad mit „~“ für den Benutzerordner.
func displayPath(_ url: URL) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let path = url.path
    if path == home { return "~" }
    if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
    return path
}

// MARK: - Suche

private struct SearchControls: View {
    @ObservedObject var browser: FileBrowserModel
    var focused: FocusState<Bool>.Binding
    @Environment(\.aether) private var theme

    var body: some View {
        HStack(spacing: Spacing.s) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(theme.textSecondary)
                TextField(tr("Search with Spotlight"), text: $browser.searchText)
                    .textFieldStyle(.plain)
                    .focused(focused)
                    .onSubmit { browser.runSearch() }
                    .frame(width: 200)
                if !browser.searchText.isEmpty {
                    Button {
                        browser.searchText = ""
                        browser.clearResults()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help(tr("Clear search"))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(theme.fieldFill))
            Menu {
                Picker(tr("Search in"), selection: $browser.searchScope) {
                    Text(tr("This folder")).tag(FileBrowserModel.SearchScope.folder)
                    Text(tr("Home folder")).tag(FileBrowserModel.SearchScope.home)
                    Text(tr("This Mac")).tag(FileBrowserModel.SearchScope.mac)
                }
                Picker(tr("Kind"), selection: $browser.searchKind) {
                    ForEach(FileBrowserModel.SearchKind.allCases) { kind in Text(searchKindName(kind)).tag(kind) }
                }
                Picker(tr("Modified"), selection: $browser.searchDate) {
                    ForEach(FileBrowserModel.SearchDate.allCases) { date in Text(searchDateName(date)).tag(date) }
                }
                Toggle(tr("Also search file contents"), isOn: $browser.searchContents)
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(tr("Search options"))
            Button(tr("Search")) { browser.runSearch() }
                .buttonStyle(CapsuleButtonStyle(prominent: true))
                .disabled(browser.searchText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

func searchKindName(_ kind: FileBrowserModel.SearchKind) -> String {
    switch kind {
    case .any: return tr("Any kind")
    case .folders: return tr("Folders")
    case .documents: return tr("Documents")
    case .images: return tr("Images")
    case .videos: return tr("Videos")
    case .audio: return tr("Audio")
    case .pdf: return "PDF"
    case .apps: return tr("Applications")
    }
}

func searchDateName(_ date: FileBrowserModel.SearchDate) -> String {
    switch date {
    case .any: return tr("Any time")
    case .today: return tr("Today")
    case .week: return tr("Last 7 days")
    case .month: return tr("Last 30 days")
    case .year: return tr("Last 12 months")
    }
}

private struct ResultsHeader: View {
    let results: FileBrowserModel.ResultList
    let close: () -> Void
    @Environment(\.aether) private var theme

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: results.kind == .recents ? "clock" : "magnifyingglass").foregroundStyle(theme.accent)
            Text(results.title).font(Typo.bodyMedium).lineLimit(1)
            Text(tr("%ld items", results.items.count)).font(Typo.caption).foregroundStyle(theme.textSecondary)
            if results.truncated {
                Text(tr("(first 1,000 shown)")).font(Typo.caption).foregroundStyle(theme.textTertiary)
            }
            if results.isGathering { ProgressView().controlSize(.small) }
            Spacer()
            Button(tr("Back to folder"), action: close).buttonStyle(CapsuleButtonStyle())
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 8)
    }
}

// MARK: - Seitenleiste

private struct FilesSidebar: View {
    @ObservedObject var browser: FileBrowserModel
    let volumes: [VolumeInfo]
    @Environment(\.aether) private var theme
    private let favorites = FilePlace.favorites()

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 2) {
                section(tr("Favorites"))
                ForEach(favorites) { place in
                    row(place.title, symbol: place.symbol, url: place.url,
                        active: browser.results == nil && browser.location == place.url.standardizedFileURL)
                }
                row(tr("Recent"), symbol: "clock", url: nil, active: browser.results?.kind == .recents) {
                    browser.showRecents()
                }
                section(tr("Locations"))
                ForEach(volumes) { volume in
                    let url = URL(fileURLWithPath: volume.path, isDirectory: true)
                    row(volume.name, symbol: volume.isNetwork ? "network" : (volume.isRemovable ? "externaldrive" : SymbolName.ssd),
                        url: url, active: browser.results == nil && browser.location == url.standardizedFileURL)
                }
            }
            .padding(.vertical, Spacing.m)
            .padding(.horizontal, Spacing.s)
        }
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Typo.sectionLabel)
            .foregroundStyle(theme.textTertiary)
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    private func row(_ title: String, symbol: String, url: URL?, active: Bool, action: (() -> Void)? = nil) -> some View {
        Button {
            if let action { action() } else if let url { browser.navigate(to: url) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(active ? theme.accent : theme.textSecondary)
                    .frame(width: 18)
                Text(title).font(Typo.callout).lineLimit(1).foregroundStyle(theme.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(active ? theme.selectionFill : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let url else { return false }
            return browser.handleDrop(providers, into: url)
        }
    }
}

// MARK: - Werkzeugleiste

private struct FilesToolbar: View {
    @ObservedObject var browser: FileBrowserModel
    let rename: () -> Void
    @Environment(\.aether) private var theme

    var body: some View {
        let selected = browser.selectedItems
        HStack(spacing: 6) {
            // Gruppe: kleine Builder-Blöcke halten die Typprüfung schnell
            Group {
                iconButton("chevron.left", tr("Back"), enabled: browser.canGoBack) { browser.goBack() }
                iconButton("chevron.right", tr("Forward"), enabled: browser.canGoForward) { browser.goForward() }
                iconButton("chevron.up", tr("Enclosing folder"), enabled: browser.canGoUp && browser.results == nil) { browser.goUp() }
            }
            Picker("", selection: $browser.viewMode) {
                Image(systemName: "list.bullet").help(tr("List")).tag(FileBrowserModel.ViewMode.list)
                Image(systemName: "square.grid.2x2").help(tr("Icons")).tag(FileBrowserModel.ViewMode.icons)
                Image(systemName: "rectangle.split.3x1").help(tr("Columns")).tag(FileBrowserModel.ViewMode.columns)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 120)
            .disabled(browser.results != nil)
            .padding(.leading, 6)
            Spacer(minLength: Spacing.s)
            iconButton("folder.badge.plus", tr("New Folder"), enabled: browser.results == nil && browser.state == .loaded) {
                if browser.newFolder() != nil { rename() }
            }
            iconButton("eye", tr("Quick Look"), enabled: !selected.isEmpty) { QuickLook.toggle(selected.map(\.url)) }
            if !selected.isEmpty {
                ShareLink(items: selected.map(\.url)) {
                    Image(systemName: "square.and.arrow.up").frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)
                .help(tr("Share"))
            }
            iconButton("trash", tr("Move to Trash"), enabled: !selected.isEmpty) { browser.trashSelection() }
            Menu {
                Toggle(tr("Show hidden files"), isOn: $browser.showHidden)
                Toggle(tr("Folders on top"), isOn: $browser.foldersFirst)
                Toggle(tr("Calculate folder sizes"), isOn: $browser.showFolderSizes)
                Divider()
                Toggle(tr("Show Info"), isOn: $browser.showInspector)
                Divider()
                Button(tr("Show in Finder")) { browser.showInFinder(selected.isEmpty ? [browser.location] : selected.map(\.url)) }
                Button(tr("Copy Path")) { browser.copyPaths(selected.isEmpty ? [browser.location] : selected.map(\.url)) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(tr("More"))
            iconButton("info.circle", tr("Show Info"), enabled: true, active: browser.showInspector) { browser.showInspector.toggle() }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 8)
    }

    private func iconButton(_ symbol: String, _ help: String, enabled: Bool, active: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? theme.accent : (enabled ? theme.textPrimary : theme.textTertiary))
                .frame(width: 26, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(active ? theme.selectionFill : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}

// MARK: - Tastaturkurzbefehle

/// Unsichtbare Knöpfe mit den Finder-Kurzbefehlen. Solange das Suchfeld den Fokus hat, sind sie aus –
/// dann gelten ⌘C, ⌘V, ⌘A usw. für den Text.
private struct ShortcutButtons: View {
    @ObservedObject var browser: FileBrowserModel
    let disabled: Bool
    let rename: () -> Void
    let focusSearch: () -> Void

    var body: some View {
        let selected = browser.selectedItems
        let inFolder = browser.results == nil
        ZStack {
            Group {
            shortcut("[", .command) { browser.goBack() }
            shortcut("]", .command) { browser.goForward() }
            shortcut(.upArrow, .command) { browser.goUp() }
            shortcut(.downArrow, .command) { browser.openSelection() }
            shortcut("o", .command) { browser.openSelection() }
            shortcut("c", .command) { browser.copyToPasteboard(selected.map(\.url)) }
            shortcut("v", .command, enabled: inFolder) { browser.paste(move: false) }
            shortcut("v", [.command, .option], enabled: inFolder) { browser.paste(move: true) }
            shortcut("d", .command, enabled: inFolder) { browser.duplicateSelection() }
            shortcut(.delete, .command) { browser.trashSelection() }
            }
            Group {
            shortcut("n", [.command, .shift], enabled: inFolder) { if browser.newFolder() != nil { rename() } }
            shortcut(.space, []) { QuickLook.toggle(selected.map(\.url)) }
            shortcut("y", .command) { QuickLook.toggle(selected.map(\.url)) }
            shortcut(.return, []) { rename() }
            shortcut("i", .command) { browser.showInspector.toggle() }
            shortcut(".", [.command, .shift]) { browser.showHidden.toggle() }
            shortcut("f", .command) { focusSearch() }
            shortcut("a", .command) { browser.selection = Set(browser.displayedItems.map(\.url)) }
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func shortcut(_ key: KeyEquivalent, _ modifiers: EventModifiers, enabled: Bool = true,
                          action: @escaping () -> Void) -> some View {
        Button("", action: action)
            .keyboardShortcut(key, modifiers: modifiers)
            .disabled(disabled || !enabled)
    }
}

// MARK: - Liste

struct FileTable: View {
    @ObservedObject var browser: FileBrowserModel
    let items: [FileItem]
    let showsLocation: Bool
    let rename: () -> Void
    @Environment(\.aether) private var theme

    var body: some View {
        Group {
            if showsLocation {
                Table(of: FileItem.self, selection: $browser.selection, sortOrder: $browser.sortOrder) {
                    TableColumn(tr("Name"), value: \.name, comparator: .localizedStandard) { item in nameCell(item) }
                        .width(min: 160, ideal: 280)
                    TableColumn(tr("Where"), value: \.parentPath, comparator: .localizedStandard) { item in
                        Text(displayPath(item.url.deletingLastPathComponent())).foregroundStyle(theme.textSecondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .width(min: 120, ideal: 240)
                    TableColumn(tr("Date Modified"), value: \.sortDate) { item in dateCell(item) }
                        .width(min: 110, ideal: 150)
                    TableColumn(tr("Size"), value: \.sortSize) { item in sizeCell(item) }
                        .width(min: 70, ideal: 90)
                } rows: {
                    ForEach(items) { item in
                        TableRow(item).itemProvider { NSItemProvider(object: item.url as NSURL) }
                    }
                }
            } else {
                Table(of: FileItem.self, selection: $browser.selection, sortOrder: $browser.sortOrder) {
                    TableColumn(tr("Name"), value: \.name, comparator: .localizedStandard) { item in nameCell(item) }
                        .width(min: 160, ideal: 320)
                    TableColumn(tr("Date Modified"), value: \.sortDate) { item in dateCell(item) }
                        .width(min: 110, ideal: 150)
                    TableColumn(tr("Size"), value: \.sortSize) { item in sizeCell(item) }
                        .width(min: 70, ideal: 90)
                    TableColumn(tr("Kind"), value: \.kind, comparator: .localizedStandard) { item in
                        Text(item.kind).foregroundStyle(theme.textSecondary).lineLimit(1)
                    }
                    .width(min: 90, ideal: 150)
                } rows: {
                    ForEach(items) { item in
                        TableRow(item).itemProvider { NSItemProvider(object: item.url as NSURL) }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: URL.self) { ids in
            FileContextMenu(browser: browser, urls: ids, rename: rename)
        } primaryAction: { ids in
            let chosen = browser.displayedItems.filter { ids.contains($0.url) }
            if chosen.count == 1, let item = chosen.first {
                browser.open(item)
            } else {
                for item in chosen where !item.isFolder { _ = NSWorkspace.shared.open(item.url) }
            }
        }
    }

    private func nameCell(_ item: FileItem) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: FileIcons.icon(for: item.url))
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
            Text(item.name).lineLimit(1).opacity(item.isHidden ? 0.55 : 1)
            if item.isSymlink {
                Image(systemName: "arrow.turn.up.right").font(.system(size: 9)).foregroundStyle(theme.textTertiary)
            }
        }
    }

    private func dateCell(_ item: FileItem) -> some View {
        Text(item.modified.map { fileDate($0) } ?? "–").foregroundStyle(theme.textSecondary).monospacedDigit().lineLimit(1)
    }

    private func sizeCell(_ item: FileItem) -> some View {
        Text(sizeText(item, browser: browser)).foregroundStyle(theme.textSecondary).monospacedDigit().lineLimit(1)
    }
}

/// Datum kurz (heute nur Uhrzeit).
func fileDate(_ date: Date) -> String {
    if Calendar.current.isDateInToday(date) {
        return tr("Today, %@", DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short))
    }
    return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
}

@MainActor
func sizeText(_ item: FileItem, browser: FileBrowserModel) -> String {
    if item.isFolder {
        if let size = browser.folderSizes[item.url] { return fmt.bytes(size) }
        return browser.sizing.contains(item.url) ? "…" : "–"
    }
    return item.size.map { fmt.bytes($0) } ?? "–"
}

// MARK: - Symbole

private struct IconGrid: View {
    @ObservedObject var browser: FileBrowserModel
    let rename: () -> Void
    @Environment(\.aether) private var theme

    var body: some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 132), spacing: 6)], spacing: 10) {
                ForEach(browser.items) { item in
                    let selected = browser.selection.contains(item.url)
                    VStack(spacing: 4) {
                        Image(nsImage: FileIcons.icon(for: item.url))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 56, height: 56)
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? theme.selectionFill : Color.clear))
                        Text(item.name)
                            .font(Typo.caption)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(selected ? theme.accent.opacity(0.85) : Color.clear))
                            .foregroundStyle(selected ? Color.white : theme.textPrimary)
                            .opacity(item.isHidden ? 0.55 : 1)
                    }
                    .frame(width: 104)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { browser.open(item) }
                    .onTapGesture { select(item) }
                    .onDrag { NSItemProvider(object: item.url as NSURL) }
                    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                        item.isFolder ? browser.handleDrop(providers, into: item.url) : false
                    }
                    .contextMenu {
                        FileContextMenu(browser: browser, urls: selected ? browser.selection : [item.url], rename: rename)
                    }
                }
            }
            .padding(Spacing.m)
        }
        .background(Color.clear.contentShape(Rectangle()).onTapGesture { browser.selection = [] })
    }

    private func select(_ item: FileItem) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if browser.selection.contains(item.url) { browser.selection.remove(item.url) } else { browser.selection.insert(item.url) }
        } else if flags.contains(.shift), let anchor = browser.items.firstIndex(where: { browser.selection.contains($0.url) }),
                  let target = browser.items.firstIndex(of: item) {
            let range = min(anchor, target)...max(anchor, target)
            browser.selection = Set(browser.items[range].map(\.url))
        } else {
            browser.selection = [item.url]
        }
    }
}

// MARK: - Spalten

private struct ColumnBrowser: View {
    @ObservedObject var browser: FileBrowserModel
    @Environment(\.aether) private var theme

    var body: some View {
        let chain = columnChain()
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(chain.enumerated()), id: \.element) { index, folder in
                        ColumnList(browser: browser, folder: folder,
                                   highlighted: index + 1 < chain.count ? chain[index + 1] : nil)
                            .frame(width: 230)
                            .id(folder)
                        Rectangle().fill(theme.hairline).frame(width: 1)
                    }
                }
            }
            .onAppear {
                if let last = chain.last { proxy.scrollTo(last, anchor: .trailing) }
            }
            .onChange(of: browser.location) { _ in
                guard let last = columnChain().last else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .trailing) }
            }
        }
    }

    /// Vom Benutzerordner bzw. Volume bis zum aktuellen Ordner (höchstens fünf Spalten).
    private func columnChain() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = browser.location.path
        var start = "/"
        if PathTrail.isInside(path, folder: home) {
            start = home
        } else if path.hasPrefix("/Volumes/") {
            let parts = path.split(separator: "/")
            if parts.count >= 2 { start = "/" + parts[0] + "/" + parts[1] }
        }
        let chain = PathTrail.ancestors(of: path).filter { PathTrail.isInside($0, folder: start) }
        return chain.suffix(5).map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
    }
}

private struct ColumnList: View {
    @ObservedObject var browser: FileBrowserModel
    let folder: URL
    let highlighted: URL?
    @Environment(\.aether) private var theme

    var body: some View {
        if let list = browser.children(of: folder) {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(list) { item in
                        let active = item.url.standardizedFileURL == highlighted
                            || (folder == browser.location && browser.selection.contains(item.url))
                        HStack(spacing: 6) {
                            Image(nsImage: FileIcons.icon(for: item.url)).resizable().frame(width: 16, height: 16)
                            Text(item.name).font(Typo.callout).lineLimit(1)
                                .foregroundStyle(active ? Color.white : theme.textPrimary)
                            Spacer(minLength: 0)
                            if item.isFolder {
                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(active ? Color.white : theme.textTertiary)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(active ? theme.accent.opacity(0.85) : Color.clear))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { if !item.isFolder { browser.open(item) } }
                        .onTapGesture {
                            if item.isFolder {
                                browser.navigate(to: item.url)
                            } else if folder == browser.location {
                                browser.selection = [item.url]
                            } else {
                                browser.navigate(to: folder, select: item.url)
                            }
                        }
                        .onDrag { NSItemProvider(object: item.url as NSURL) }
                        .contextMenu {
                            FileContextMenu(browser: browser, urls: [item.url], rename: {})
                        }
                    }
                }
                .padding(6)
            }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Kontextmenü

private struct FileContextMenu: View {
    @ObservedObject var browser: FileBrowserModel
    let urls: Set<URL>
    let rename: () -> Void

    var body: some View {
        let chosen = browser.displayedItems.filter { urls.contains($0.url) }
        let list = chosen.map(\.url)
        if chosen.isEmpty {
            Button(tr("New Folder")) { if browser.newFolder() != nil { rename() } }
            Button(tr("Paste")) { browser.paste(move: false) }.disabled(browser.pasteboardURLs.isEmpty)
            Button(tr("Show in Finder")) { browser.showInFinder([browser.location]) }
        } else {
            Group {
                Button(tr("Open")) {
                    if chosen.count == 1, let item = chosen.first {
                        browser.open(item)
                    } else {
                        for item in chosen where !item.isFolder { _ = NSWorkspace.shared.open(item.url) }
                    }
                }
                if chosen.count == 1, let item = chosen.first, !item.isFolder {
                    Menu(tr("Open With")) {
                        ForEach(browser.applications(for: item.url), id: \.self) { app in
                            Button(FileManager.default.displayName(atPath: app.path)) { browser.open([item.url], with: app) }
                        }
                    }
                    if item.isPackage {
                        Button(tr("Show Package Contents")) { browser.showPackageContents(item) }
                    }
                }
                Button(tr("Quick Look")) {
                    browser.selection = urls
                    QuickLook.toggle(list)
                }
                Divider()
                Button(tr("Show Info")) {
                    browser.selection = urls
                    browser.showInspector = true
                }
                Button(chosen.count == 1 ? tr("Rename…") : tr("Rename %ld Items…", chosen.count)) {
                    browser.selection = urls
                    rename()
                }
            }
            Group {
                Button(tr("Duplicate")) {
                    browser.selection = urls
                    browser.duplicateSelection()
                }
                .disabled(browser.results != nil)
                Button(tr("Copy")) { browser.copyToPasteboard(list) }
                Button(tr("Copy Path")) { browser.copyPaths(list) }
                if chosen.count == 1, let item = chosen.first, item.isFolder, !browser.pasteboardURLs.isEmpty {
                    Button(tr("Paste into “%@”", item.name)) { browser.transfer(browser.pasteboardURLs, to: item.url, move: false) }
                }
                Divider()
                Button(tr("Show in Finder")) { browser.showInFinder(list) }
                ShareLink(items: list) { Text(tr("Share…")) }
            }
            Group {
                if browser.results == nil {
                    Button(tr("Calculate Folder Size")) { browser.computeFolderSizes(chosen.filter(\.isFolder).map(\.url)) }
                        .disabled(!chosen.contains(where: \.isFolder))
                }
                Divider()
                Button(tr("Move to Trash")) {
                    browser.selection = urls
                    browser.trashSelection()
                }
            }
        }
    }
}

// MARK: - Zustände, Leisten

private struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        OrbitEmptyState(symbol: symbol, title: title, detail: detail,
                        problem: symbol.contains("exclamationmark") || symbol.contains("questionmark"))
    }
}

private struct AccessDeniedView: View {
    @ObservedObject var browser: FileBrowserModel
    @Environment(\.aether) private var theme

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill").font(.system(size: 28, weight: .light)).foregroundStyle(theme.textSecondary)
            Text(tr("No access to this folder")).font(Typo.bodyMedium)
            Text(tr("macOS protects this folder. You can allow access for ORBIT in System Settings → Privacy & Security → Files and Folders (or Full Disk Access)."))
                .font(Typo.callout).foregroundStyle(theme.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            HStack {
                Button(tr("Open Privacy Settings")) { openPrivacySettings() }.buttonStyle(CapsuleButtonStyle(prominent: true))
                Button(tr("Try Again")) { browser.reload() }.buttonStyle(CapsuleButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func openPrivacySettings() {
        for link in ["x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_FilesAndFolders",
                     "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"] {
            if let url = URL(string: link), NSWorkspace.shared.open(url) { return }
        }
    }
}

private struct BannerRow: View {
    let banner: FileBrowserModel.Banner
    @ObservedObject var browser: FileBrowserModel
    @Environment(\.aether) private var theme

    var body: some View {
        HStack(spacing: Spacing.s) {
            CompletionSymbol(isError: banner.isError)
                .id(banner.text)
            Text(banner.text).font(Typo.callout).lineLimit(2)
            Spacer()
            if banner.undoable {
                Button(tr("Undo")) { browser.undoLast() }.buttonStyle(CapsuleButtonStyle())
            }
            Button {
                browser.banner = nil
            } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help(tr("Close"))
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 7)
        .background(theme.fieldFill)
    }
}

private struct OperationRow: View {
    let operation: FileBrowserModel.FileOperation
    let cancel: () -> Void
    @Environment(\.aether) private var theme

    /// Echter Fortschritt: Bytes, wenn bekannt, sonst Anzahl der Objekte.
    private var fraction: Double {
        if operation.totalBytes > 0 { return Double(operation.completedBytes) / Double(operation.totalBytes) }
        return Double(operation.completedItems) / Double(max(1, operation.totalItems))
    }

    var body: some View {
        HStack(spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "\(operation.title) · \(tr("%ld of %ld items", operation.completedItems, operation.totalItems))")
                    .font(Typo.captionMedium)
                LiquidProgressBar(fraction: fraction, active: theme.effects.dataFlow, color: theme.electricCyan, track: theme.fieldFill)
                    .frame(height: 6)
                    .accessibilityElement()
                    .accessibilityLabel(Text(operation.title))
                    .accessibilityValue(Text(fmt.percent(fraction)))
                Text(operation.current).font(Typo.caption).foregroundStyle(theme.textSecondary).lineLimit(1).truncationMode(.middle)
            }
            Button(tr("Stop"), action: cancel).buttonStyle(CapsuleButtonStyle())
        }
        .padding(Spacing.m)
        .frame(maxWidth: 420)
        .glassCard(cornerRadius: Radius.tile, strong: true, elevated: true)
    }
}

private struct PathAndStatusBar: View {
    @ObservedObject var browser: FileBrowserModel
    @Environment(\.aether) private var theme

    var body: some View {
        HStack(spacing: Spacing.m) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    let trail = PathTrail.ancestors(of: browser.location.path)
                    ForEach(Array(trail.enumerated()), id: \.element) { index, path in
                        if index > 0 {
                            Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(theme.textTertiary)
                        }
                        Button {
                            browser.navigate(to: URL(fileURLWithPath: path, isDirectory: true))
                        } label: {
                            HStack(spacing: 3) {
                                Image(nsImage: FileIcons.icon(for: URL(fileURLWithPath: path))).resizable().frame(width: 13, height: 13)
                                Text(FileManager.default.displayName(atPath: path)).font(Typo.caption).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
            Text(statusText).font(Typo.caption).foregroundStyle(theme.textSecondary).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 6)
    }

    private var statusText: String {
        var parts = [tr("%ld items", browser.displayedItems.count)]
        if !browser.selection.isEmpty { parts.append(tr("%ld selected", browser.selection.count)) }
        if let space = browser.availableSpace, browser.results == nil { parts.append(tr("%@ available", fmt.bytes(space))) }
        return parts.joined(separator: " · ")
    }
}
