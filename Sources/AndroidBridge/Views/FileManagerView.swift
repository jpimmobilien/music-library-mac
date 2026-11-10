import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLook
import ABCore

extension UTType {
    /// Interner Typ für gezogene/kopierte Objekte vom Telefon.
    static let androidBridgeEntries = UTType(exportedAs: "de.androidbridge.device-entries")
}

/// Inhalt beim Ziehen/Kopieren von Telefonobjekten innerhalb der App.
struct DeviceDragPayload: Codable {
    var deviceID: UInt64
    var entries: [DeviceEntry]
    var path: [String]
}

/// Dateimanager mit Mac-Spalte (links) und Telefon-Spalte (rechts).
struct FileManagerView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var files: FileManagerModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject private var deviceBrowser: DeviceBrowserModel
    @ObservedObject private var localBrowser: LocalBrowserModel
    @AppStorage("fileSplitFraction") private var splitFraction: Double = 0.44
    @AppStorage("filePaneStyle") private var paneStyleRaw: String = PaneStyle.grid.rawValue

    private var paneStyle: PaneStyle { PaneStyle(rawValue: paneStyleRaw) ?? .grid }

    init(files: FileManagerModel, settings: SettingsStore) {
        self.files = files
        self.settings = settings
        self.deviceBrowser = files.device
        self.localBrowser = files.local
    }

    var body: some View {
        PageScaffold(title: "Dateimanager", subtitle: subtitle) {
            toolbar
        } content: {
            ZStack(alignment: .bottom) {
                content
                    .padding(.horizontal, Spacing.gutter - 10)
                    .padding(.bottom, 14)
                SelectionActionBar(files: files, local: files.local, device: files.device)
                    .padding(.bottom, 28)
            }
        }
        .sheet(item: Binding(get: { files.newFolderPane.map(PaneBox.init) }, set: { files.newFolderPane = $0?.pane })) { box in
            NameSheet(title: "Neuer Ordner", subtitle: box.pane == .device ? "Auf dem Telefon" : "Auf dem Mac",
                      initial: "Neuer Ordner", confirm: "Anlegen") { name in
                if box.pane == .device {
                    Task { await files.device.createFolder(named: name) }
                } else {
                    files.local.createFolder(named: name)
                }
            }
        }
        .sheet(item: Binding(get: { files.renamePane.map(PaneBox.init) }, set: { files.renamePane = $0?.pane })) { box in
            NameSheet(title: "Umbenennen", subtitle: nil, initial: renameInitial(box.pane), confirm: "Umbenennen") { name in
                if box.pane == .device, let e = files.device.selectedEntries.first {
                    Task { await files.device.rename(e, to: name) }
                } else if box.pane == .local, let e = files.local.selectedEntries.first {
                    files.local.rename(e, to: name)
                }
            }
        }
        // Telefon: Bestätigung mit Anzahl, Größe und Ort (DeleteConfirmationSheet). Mac: Papierkorb.
        .onChange(of: files.confirmDelete) { pane in
            if pane == .device {
                files.confirmDelete = nil
                model.deleteDeviceSelection(in: files)
            }
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { files.confirmDelete == .local }, set: { if !$0 { files.confirmDelete = nil } }),
                            titleVisibility: .visible) {
            Button("In den Papierkorb legen", role: .destructive) {
                files.local.moveToTrash(files.local.selectedEntries)
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die Objekte können aus dem Papierkorb wiederhergestellt werden.")
        }
    }

    private var subtitle: String {
        if let loc = deviceBrowser.location, let device = deviceBrowser.device, device.state == .connected {
            return "\(device.displayName) · \(loc.displayPath)"
        }
        return "Mac und Telefon nebeneinander – ziehen, kopieren, einfügen"
    }

    private var deleteTitle: String {
        let n = files.local.selection.count
        return n == 1 ? "1 Objekt in den Papierkorb legen?" : "\(n) Objekte in den Papierkorb legen?"
    }

    private func renameInitial(_ pane: Pane) -> String {
        pane == .device ? (files.device.selectedEntries.first?.name ?? "") : (files.local.selectedEntries.first?.url.lastPathComponent ?? "")
    }

    @ViewBuilder
    private var content: some View {
        switch files.layout {
        case .dual:
            SplitPanes(fraction: $splitFraction, minLeading: 300, minTrailing: 340) {
                LocalPaneView(browser: files.local, files: files, style: paneStyle)
                    .paneCard()
            } trailing: {
                DevicePaneView(browser: files.device, files: files, style: paneStyle)
                    .paneCard()
            }
        case .single, .gallery:
            DevicePaneView(browser: files.device, files: files, style: paneStyle)
                .paneCard()
        }
    }

    private var deviceActive: Bool { files.activePane == .device }

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 10) {
            ToolbarCapsule {
                ToolbarIconButton(symbol: "chevron.left", help: "Zurück (⌘[)") { activeBack() }
                    .disabled(!(deviceActive ? deviceBrowser.canGoBack : localBrowser.canGoBack))
                ToolbarIconButton(symbol: "chevron.right", help: "Vor (⌘])") { activeForward() }
                    .disabled(!(deviceActive ? deviceBrowser.canGoForward : localBrowser.canGoForward))
            }
            GlassSegmented(selection: Binding(get: { files.layout == .gallery ? .single : files.layout }, set: { files.layout = $0 }), options: [
                SegmentOption(value: FileManagerLayout.dual, symbol: FileManagerLayout.dual.symbolName, help: "Zwei Spalten: Mac und Telefon"),
                SegmentOption(value: FileManagerLayout.single, symbol: FileManagerLayout.single.symbolName, help: "Eine Spalte: nur Telefon"),
            ])
            GlassSegmented(selection: $paneStyleRaw, options: [
                SegmentOption(value: PaneStyle.list.rawValue, symbol: "list.bullet", help: "Liste"),
                SegmentOption(value: PaneStyle.grid.rawValue, symbol: "square.grid.2x2", help: "Raster mit Vorschaubildern"),
            ])
            ToolbarCapsule {
                ToolbarMenu(symbol: "arrow.up.arrow.down", help: "Sortieren") {
                    Picker("Sortieren nach", selection: activeSortBinding) {
                        ForEach(EntrySort.allCases) { s in Text(s.title).tag(s) }
                    }
                    .pickerStyle(.inline)
                }
                ToolbarIconButton(symbol: "arrow.clockwise", help: "Aktualisieren (⌘R)") { files.refresh() }
                ToolbarIconButton(symbol: "folder.badge.plus", help: "Neuer Ordner (⌘N)") { files.requestNewFolder() }
                ToolbarDivider()
                ToolbarIconButton(symbol: deviceActive ? "arrow.down.to.line" : "arrow.up.to.line",
                                  help: deviceActive ? "Auswahl auf den Mac übertragen (⌘T)" : "Auswahl auf das Telefon übertragen (⌘T)") {
                    if deviceActive { files.transferDeviceSelectionToMac() } else { files.transferLocalSelectionToDevice() }
                }
                .disabled(deviceActive ? deviceBrowser.selection.isEmpty : (localBrowser.selection.isEmpty || deviceBrowser.device == nil))
                ToolbarIconButton(symbol: "trash", help: deviceActive ? "Auf dem Telefon löschen … (⌘⌫)" : "In den Papierkorb legen … (⌘⌫)",
                                  tint: Palette.danger) {
                    model.requestDeleteForCurrentPage()
                }
                .disabled(deviceActive ? deviceBrowser.selection.isEmpty || deviceBrowser.device?.state != .connected : localBrowser.selection.isEmpty)
                ToolbarMenu(symbol: "ellipsis", help: "Weitere Optionen") {
                    Button("Alles auswählen") { files.selectAll() }
                    Button("Auswahl aufheben") { files.deselectAll() }
                    Button("Auswahl umkehren") { files.invertSelection() }
                    Divider()
                    Toggle("Versteckte Mac-Dateien zeigen", isOn: Binding(get: { files.local.showHidden }, set: { files.local.showHidden = $0 }))
                    Toggle("Versteckte Android-Dateien zeigen", isOn: Binding(get: { settings.showHiddenAndroidFiles },
                                                                              set: { settings.showHiddenAndroidFiles = $0; files.device.recompute() }))
                    Divider()
                    Button("Mac-Ordner im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([files.local.folder]) }
                    if let loc = files.device.location {
                        Button(model.favorites.contains(loc) ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen") {
                            model.favorites.toggle(loc)
                        }
                    }
                }
            }
        }
    }

    private var activeSortBinding: Binding<EntrySort> {
        let device = files.device
        let local = files.local
        if files.activePane == .device {
            return Binding(get: { device.sort }, set: { device.sort = $0 })
        }
        return Binding(get: { local.sort }, set: { local.sort = $0 })
    }

    private func activeBack() { files.activePane == .device ? files.device.back() : files.local.back() }
    private func activeForward() { files.activePane == .device ? files.device.forward() : files.local.forward() }
}

private struct PaneBox: Identifiable {
    let pane: Pane
    var id: Pane { pane }
}

/// Eingabe eines Namens (neuer Ordner, Umbenennen).
extension View {
    /// Bereich des Dateimanagers: alles – Tabelle, Raster, Rollbalken – folgt den runden Ecken der Karte.
    func paneCard() -> some View {
        clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
            .glassCard(cornerRadius: Radius.panel)
    }

    /// Leere Tabelle ohne Zebrastreifen, damit „Ordner ist leer“ auf ruhigem Grund steht (macOS 14+).
    @ViewBuilder
    func quietRows(when empty: Bool) -> some View {
        if #available(macOS 14.0, *) {
            alternatingRowBackgrounds(empty ? .disabled : .enabled)
        } else {
            self
        }
    }
}

struct NameSheet: View {
    let title: String
    let subtitle: String?
    let initial: String
    let confirm: String
    let action: (String) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.ui(15, .semibold))
            if let subtitle { Text(subtitle).font(.ui(12)).foregroundStyle(.secondary) }
            TextField("Name", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(commit)
                .frame(width: 320)
            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(confirm, action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .onAppear {
            text = initial
            focused = true
        }
    }

    private func commit() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        action(t)
        dismiss()
    }
}

// MARK: - Kopfzeile einer Spalte

/// Darstellung der Spalten.
enum PaneStyle: String { case list, grid }

/// Belegung eines Speichers für die Kopfzeile.
struct CapacityInfo {
    let used: Double
    let label: String
}

/// Kopf einer Spalte – als „Speicherfläche“: Gerät bzw. Mac, Suche, Pfad und Füllstand.
struct PaneHeader<Leading: View, Crumbs: View>: View {
    let isActive: Bool
    @Binding var search: String
    let focusToken: UUID
    var tint: Color = Palette.accent
    var capacity: CapacityInfo?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var crumbs: () -> Crumbs

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    leading()
                    Spacer(minLength: 8)
                    GlassSearchField(text: $search, prompt: "Suchen", width: 190, focusToken: focusToken, focusEnabled: isActive)
                }
                VStack(alignment: .leading, spacing: 8) {
                    leading()
                    GlassSearchField(text: $search, prompt: "Suchen", width: 190, focusToken: focusToken, focusEnabled: isActive)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) { crumbs() }
            }
            if let capacity {
                HStack(spacing: 10) {
                    CapacityBar(fraction: capacity.used, tint: tint, height: 7)
                    Text(capacity.label)
                        .font(.ui(10.5, .medium))
                        .foregroundStyle(Palette.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 10)
        .background(
            LinearGradient(colors: [tint.opacity(isActive ? 0.10 : 0.04), .clear], startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(isActive ? tint.opacity(0.7) : Palette.hairline).frame(height: isActive ? 2 : 1)
        }
    }
}

/// Zwei Spalten mit verschiebbarem Trenner (ersetzt die Systemteilung, die unter macOS 26 einen Titelleistenstreifen erzeugt).
struct SplitPanes<Leading: View, Trailing: View>: View {
    @Binding var fraction: Double
    var minLeading: CGFloat = 280
    var minTrailing: CGFloat = 320
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    @State private var dragStart: Double?
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let total = geo.size.width
            let handle: CGFloat = 12
            let usable = max(total - handle, 1)
            let lower = min(minLeading / usable, 0.5)
            let upper = max(1 - minTrailing / usable, 0.5)
            let f = min(max(fraction, lower), upper)
            HStack(spacing: 0) {
                leading().frame(width: usable * f)
                ZStack {
                    Color.clear
                    Capsule()
                        .fill(hovering || dragStart != nil ? Palette.accent.opacity(0.7) : Palette.textTertiary.opacity(0.35))
                        .frame(width: 4, height: 44)
                }
                .frame(width: handle)
                .contentShape(Rectangle())
                .onHover { inside in
                    hovering = inside
                    if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if dragStart == nil { dragStart = f }
                            let next = (dragStart ?? f) + Double(value.translation.width / usable)
                            fraction = min(max(next, lower), upper)
                        }
                        .onEnded { _ in dragStart = nil }
                )
                .onTapGesture(count: 2) { fraction = 0.44 }
                .help("Ziehen, um die Spalten anzupassen (Doppelklick: zurücksetzen)")
                trailing().frame(width: usable * (1 - f))
            }
        }
    }
}

struct CrumbButton: View {
    let title: String
    let symbol: String?
    let isLast: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button(action: action) {
                HStack(spacing: 4) {
                    if let symbol { Image(systemName: symbol).font(.ui(11)) }
                    Text(title).lineLimit(1)
                }
                .font(.ui(12, isLast ? .semibold : .regular))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isLast ? .primary : .secondary)
            if !isLast {
                Image(systemName: "chevron.right").font(.ui(9, .semibold)).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Telefon-Spalte

struct DevicePaneView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var browser: DeviceBrowserModel
    @ObservedObject var files: FileManagerModel
    var style: PaneStyle = .list
    @State private var dropTargeted = false
    @State private var gridAnchor: String?
    @FocusState private var tableFocused: Bool

    private var isActive: Bool { files.activePane == .device }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(isActive: isActive, search: $browser.search, focusToken: files.focusSearchToken,
                       tint: Palette.accent, capacity: deviceCapacity) {
                deviceAndStoragePicker
            } crumbs: {
                if let storage = browser.storage {
                    CrumbButton(title: storage.displayName, symbol: storage.symbolName, isLast: browser.crumbs.isEmpty) {
                        browser.goTo(crumbIndex: nil)
                    }
                    ForEach(Array(browser.crumbs.enumerated()), id: \.offset) { index, crumb in
                        CrumbButton(title: crumb.name, symbol: nil, isLast: index == browser.crumbs.count - 1) {
                            browser.goTo(crumbIndex: index)
                        }
                    }
                }
            }
            ZStack {
                if let device = browser.device, device.state == .connected {
                    if style == .grid { grid(device: device) } else { table(device: device) }
                    if browser.isLoading && browser.visible.isEmpty {
                        ProgressView("Dateien werden geladen …").controlSize(.small)
                    } else if !browser.isLoading && browser.visible.isEmpty && browser.issue == nil {
                        EmptyStateView(symbol: browser.search.isEmpty ? "folder" : "magnifyingglass",
                                       title: browser.search.isEmpty ? "Ordner ist leer" : "Keine Treffer",
                                       message: browser.search.isEmpty ? "Ziehen Sie Dateien aus dem Finder oder der linken Spalte hierher." : "Kein Objekt passt zu „\(browser.search)“.")
                            .allowsHitTesting(false)
                    }
                } else {
                    noDevice
                }
                if let issue = browser.issue {
                    VStack {
                        IssueBanner(issue: issue, primaryTitle: "Erneut versuchen", primaryAction: { browser.reload(force: true) },
                                    dismiss: { browser.issue = nil })
                            .padding(14)
                        Spacer()
                    }
                }
            }
            // Abstand zu den runden Ecken: Zeilen und Rollbalken werden nicht angeschnitten
            .padding(.horizontal, 6)
            .padding(.bottom, 10)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Radius.panel - 3, style: .continuous)
                .strokeBorder(Palette.accent, lineWidth: 2.5)
                .padding(3)
                .opacity(dropTargeted ? 1 : 0)
                .allowsHitTesting(false)
        )
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard browser.device?.state == .connected else { return false }
            loadFileURLs(providers) { urls in files.uploadToDevice(urls) }
            return true
        }
        .simultaneousGesture(TapGesture().onEnded { files.activePane = .device })
    }

    private var deviceCapacity: CapacityInfo? {
        guard let s = browser.storage, s.capacity > 0, browser.device?.state == .connected else { return nil }
        return CapacityInfo(used: s.usedFraction, label: "\(ByteFormat.string(s.free)) frei von \(ByteFormat.string(s.capacity))")
    }

    private func grid(device: DeviceConnection) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132, maximum: 180), spacing: 14)], spacing: 16) {
                ForEach(browser.visible) { e in
                    FileTile(name: e.name, detail: e.isFolder ? "Ordner" : ByteFormat.string(e.size), selected: browser.selection.contains(e.id)) {
                        DeviceThumb(entry: e, device: device, size: 92, corner: 12)
                    }
                    .onTapGesture(count: 2) { open(ids: [e.id], device: device) }
                    .onTapGesture { selectInGrid(e.id) }
                    .onDrag { dragProvider(for: e, device: device) }
                    .contextMenu {
                        rowMenu(ids: browser.selection.contains(e.id) ? browser.selection : [e.id], device: device)
                    }
                }
            }
            .reportsScrollEdge()
            .padding(14)
            .padding(.bottom, 80)
        }
        .contentShape(Rectangle())
        .onTapGesture { browser.selection = []; files.activePane = .device }
    }

    private func selectInGrid(_ id: String) {
        files.activePane = .device
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if browser.selection.contains(id) { browser.selection.remove(id) } else { browser.selection.insert(id) }
        } else if flags.contains(.shift), let anchor = gridAnchor,
                  let a = browser.visible.firstIndex(where: { $0.id == anchor }), let b = browser.visible.firstIndex(where: { $0.id == id }) {
            browser.selection.formUnion(browser.visible[min(a, b)...max(a, b)].map(\.id))
            return
        } else {
            browser.selection = [id]
        }
        gridAnchor = id
    }

    private var deviceAndStoragePicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "smartphone").foregroundStyle(Palette.accent)
            if model.devices.connectedDevices.count > 1 {
                Menu {
                    ForEach(model.devices.connectedDevices) { d in
                        Button(d.displayName) { model.select(device: d) }
                    }
                } label: {
                    Text(browser.device?.displayName ?? "Gerät").font(.ui(13, .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                Text(browser.device?.displayName ?? "Telefon")
                    .font(.ui(13, .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(2)
            }
            if let device = browser.device, device.storages.count > 1 {
                Picker("", selection: Binding(get: { browser.storageID ?? 0 }, set: { browser.selectStorage($0) })) {
                    ForEach(device.storages) { s in Label(s.shortName, systemImage: s.symbolName).tag(s.id) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 190)
                .layoutPriority(1)
            }
            if browser.isLoading && !browser.visible.isEmpty { ProgressView().controlSize(.mini) }
        }
    }

    private var noDevice: some View {
        EmptyStateView(symbol: "cable.connector", title: "Kein Telefon verbunden",
                       message: "Schließen Sie Ihr Android-Gerät per USB an, entsperren Sie es und wählen Sie „Dateiübertragung“.") {
            Button("Zur Übersicht") { model.selection = .overview }.buttonStyle(GlassButtonStyle())
        }
    }

    private func table(device: DeviceConnection) -> some View {
        Table(of: DeviceEntry.self, selection: $browser.selection) {
            TableColumn("Name") { e in
                HStack(spacing: 8) {
                    DeviceThumb(entry: e, device: device, size: 22)
                    Text(e.name).lineLimit(1).truncationMode(.middle)
                }
            }
            .width(min: 140, ideal: 210)
            TableColumn("Geändert") { e in
                Text(e.bestDate.map { $0.formatted(date: .numeric, time: .shortened) } ?? "–")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .width(min: 88, ideal: 112)
            TableColumn("Größe") { e in
                Text(e.isFolder ? "–" : ByteFormat.string(e.size)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
            .width(min: 52, ideal: 64)
            TableColumn("Art") { e in
                Text(kindName(e.kind, name: e.name)).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 40, ideal: 56)
        } rows: {
            ForEach(browser.visible) { e in
                TableRow(e).itemProvider { dragProvider(for: e, device: device) }
            }
        }
        .focused($tableFocused)
        .onChange(of: tableFocused) { f in if f { files.activePane = .device } }
        .onChange(of: browser.selection) { s in if !s.isEmpty { files.activePane = .device } }
        .contextMenu(forSelectionType: String.self) { ids in
            rowMenu(ids: ids, device: device)
        } primaryAction: { ids in
            open(ids: ids, device: device)
        }
        .onDeleteCommand { files.activePane = .device; model.deleteDeviceSelection(in: files) }
        .onCopyCommand {
            files.activePane = .device
            files.copySelection()
            let selected = browser.selectedEntries
            guard !selected.isEmpty else { return [] }
            return [payloadProvider(entries: selected, device: device)]
        }
        .onPasteCommand(of: [.fileURL]) { providers in
            files.activePane = .device
            loadFileURLs(providers) { urls in files.uploadToDevice(urls) }
        }
        .scrollContentBackground(.hidden)
        .quietRows(when: browser.visible.isEmpty)
    }

    @ViewBuilder
    private func rowMenu(ids: Set<String>, device: DeviceConnection) -> some View {
        let entries = browser.visible.filter { ids.contains($0.id) }
        if !entries.isEmpty {
            Button("Auf den Mac übertragen") { files.transferToMac(entries, useSmartDestination: files.layout != .dual) }
            Button("In intelligente Zielordner übertragen") { files.transferToMac(entries, useSmartDestination: true) }
            Button("Übertragen nach …") { chooseDestination(entries) }
            Divider()
            if entries.count == 1, let e = entries.first {
                if e.isFolder {
                    Button("Öffnen") { browser.enter(e) }
                    if let loc = browser.location {
                        let folderLoc = DeviceLocation(deviceSerial: loc.deviceSerial, deviceName: loc.deviceName, storageID: loc.storageID,
                                                       storageName: loc.storageName, path: loc.path + [e.name])
                        Button(model.favorites.contains(folderLoc) ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen") {
                            model.favorites.toggle(folderLoc)
                        }
                    }
                } else if e.kind.isMedia {
                    Button("Vorschau") { preview(e) }
                }
                Button("Umbenennen …") { browser.selection = [e.id]; files.renamePane = .device }
                Button("Informationen") {
                    model.infoEntry = EntryInfoBox(deviceID: device.id, entry: e, path: browser.pathNames)
                }
            }
            Divider()
            Button("Auf dem Telefon löschen …", role: .destructive) {
                browser.selection = ids
                files.activePane = .device
                model.deleteDeviceSelection(in: files, entries: entries)
            }
        } else {
            Button("Neuer Ordner …") { files.activePane = .device; files.requestNewFolder() }
            Button("Aktualisieren") { browser.invalidateCache(); browser.reload(force: true) }
        }
    }

    private func open(ids: Set<String>, device: DeviceConnection) {
        let entries = browser.visible.filter { ids.contains($0.id) }
        guard let first = entries.first else { return }
        if entries.count == 1 && first.isFolder {
            browser.enter(first)
        } else if entries.count == 1 && first.kind.isMedia {
            preview(first)
        } else {
            files.transferToMac(entries, useSmartDestination: files.layout != .dual)
        }
    }

    private func preview(_ entry: DeviceEntry) {
        guard let device = browser.device else { return }
        let media = browser.visible.filter { $0.kind.isMedia }
        let index = media.firstIndex(of: entry) ?? 0
        model.viewerItem = MediaViewerItem(deviceID: device.id, items: media, index: index)
        if let loc = browser.location { model.recents.add(name: entry.name, size: entry.size, location: loc) }
    }

    private func chooseDestination(_ entries: [DeviceEntry]) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Hierhin übertragen"
        panel.directoryURL = files.local.folder
        if panel.runModal() == .OK, let url = panel.url {
            files.transferToMac(entries, useSmartDestination: false, destination: url)
        }
    }

    private func payloadProvider(entries: [DeviceEntry], device: DeviceConnection) -> NSItemProvider {
        let payload = DeviceDragPayload(deviceID: device.id, entries: entries, path: browser.pathNames)
        let provider = NSItemProvider()
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.androidBridgeEntries.identifier, visibility: .ownProcess) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    /// Ziehen: innerhalb der App als Objektliste, in den Finder als Datei (wird beim Ablegen geladen).
    private func dragProvider(for entry: DeviceEntry, device: DeviceConnection) -> NSItemProvider {
        let list = browser.selection.contains(entry.id) ? browser.selectedEntries : [entry]
        let provider = payloadProvider(entries: list, device: device)
        if !entry.isFolder, let backend = device.backend {
            provider.suggestedName = entry.name
            let type = UTType(filenameExtension: FileKind.fileExtension(of: entry.name)) ?? .data
            provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
                let progress = Progress(totalUnitCount: Int64(max(entry.size, 1)))
                let folder = AppPaths.previewCache.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appendingPathComponent(FileNameSanitizer.macSafe(entry.name))
                Task {
                    do {
                        FileManager.default.createFile(atPath: url.path, contents: nil)
                        let handle = try FileHandle(forWritingTo: url)
                        try await backend.download(handle: entry.handle, sink: { data in try handle.write(contentsOf: data) },
                                                   progress: { bytes in progress.completedUnitCount = Int64(bytes); return !progress.isCancelled })
                        try handle.close()
                        completion(url, false, nil)
                    } catch {
                        completion(nil, false, error)
                    }
                }
                return progress
            }
        }
        return provider
    }
}

func kindName(_ kind: FileKind, name: String) -> String {
    switch kind {
    case .folder: return "Ordner"
    case .photo: return "Bild"
    case .video: return "Video"
    case .audio: return "Audio"
    case .document: return "Dokument"
    case .archive: return "Archiv"
    case .apk: return "App-Paket"
    case .other:
        let ext = FileKind.fileExtension(of: name)
        return ext.isEmpty ? "Datei" : ext.uppercased()
    }
}

/// Lädt Datei-URLs aus abgelegten bzw. eingefügten Elementen.
func loadFileURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    let group = DispatchGroup()
    let lock = NSLock()
    var urls: [URL] = []
    for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        group.enter()
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            defer { group.leave() }
            var url: URL?
            if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
            else if let u = item as? URL { url = u }
            else if let s = item as? String { url = URL(string: s) }
            if let url, url.isFileURL {
                lock.lock(); urls.append(url); lock.unlock()
            }
        }
    }
    group.notify(queue: .main) { if !urls.isEmpty { completion(urls) } }
}

/// Vorschaubild bzw. Symbol eines Telefonobjekts.
struct DeviceThumb: View {
    let entry: DeviceEntry
    let device: DeviceConnection
    var size: CGFloat = 22
    /// `0` = füllt den umgebenden Rahmen (Kacheln, Mosaike); sonst Eckenradius des Quadrats.
    var corner: CGFloat?
    @State private var image: NSImage?

    private var fills: Bool { corner == 0 }

    var body: some View {
        Group {
            if let image {
                if fills {
                    Color.clear
                        .overlay(Image(nsImage: image).resizable().aspectRatio(contentMode: .fill))
                        .clipped()
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: corner ?? size * 0.2, style: .continuous))
                }
            } else if fills {
                ZStack {
                    LinearGradient(colors: [entry.kind.tint.opacity(0.22), entry.kind.tint.opacity(0.06)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    TypeIcon(name: entry.name, isFolder: entry.isFolder, size: min(size * 0.42, 96))
                }
            } else {
                TypeIcon(name: entry.name, isFolder: entry.isFolder, size: size)
                    .frame(width: size, height: size)
            }
        }
        .task(id: entry.id) {
            guard entry.kind.isMedia else { return }
            if let cached = ThumbnailService.shared.cached(ThumbnailService.key(device: device, entry: entry)) {
                image = cached
                return
            }
            image = await ThumbnailService.shared.thumbnail(for: entry, device: device)
        }
    }
}

/// macOS-Symbol des Dateityps (wie im Finder) – hochwertiger als ein generisches Zeichen.
struct TypeIcon: View {
    let name: String
    var isFolder = false
    var size: CGFloat = 32

    var body: some View {
        Image(nsImage: TypeIconCache.icon(name: name, isFolder: isFolder))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

@MainActor
enum TypeIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(name: String, isFolder: Bool) -> NSImage {
        let ext = isFolder ? "/folder" : FileKind.fileExtension(of: name).lowercased()
        if let hit = cache[ext] { return hit }
        let type: UTType
        if isFolder {
            type = .folder
        } else if ext == "apk" {
            type = UTType(filenameExtension: "apk") ?? .archive
        } else {
            type = UTType(filenameExtension: ext) ?? .data
        }
        let image = NSWorkspace.shared.icon(for: type)
        image.size = NSSize(width: 256, height: 256)
        cache[ext] = image
        return image
    }
}

// MARK: - Mac-Spalte

struct LocalPaneView: View {
    @ObservedObject var browser: LocalBrowserModel
    @ObservedObject var files: FileManagerModel
    var style: PaneStyle = .list
    @State private var dropTargeted = false
    @State private var gridAnchor: URL?
    @State private var quickLookURL: URL?
    @FocusState private var tableFocused: Bool

    private var isActive: Bool { files.activePane == .local }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(isActive: isActive, search: $browser.search, focusToken: files.focusSearchToken,
                       tint: Palette.bridgeBlue, capacity: macCapacity) {
                placesMenu
            } crumbs: {
                let crumbs = browser.crumbs
                ForEach(Array(crumbs.enumerated()), id: \.offset) { index, url in
                    CrumbButton(title: index == 0 && url == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL ? NSUserName() : (url.path == "/" ? "Macintosh HD" : url.lastPathComponent),
                                symbol: index == 0 ? (url.path == "/" ? "internaldrive" : "house") : nil,
                                isLast: index == crumbs.count - 1) {
                        browser.open(url)
                    }
                }
            }
            ZStack {
                if style == .grid { grid } else { table }
                if browser.visible.isEmpty {
                    EmptyStateView(symbol: "folder", title: browser.search.isEmpty ? "Ordner ist leer" : "Keine Treffer",
                                   message: browser.search.isEmpty ? "Ziehen Sie Dateien vom Telefon hierher." : "Kein Objekt passt zu „\(browser.search)“.")
                        .allowsHitTesting(false)
                }
                if let issue = browser.issue {
                    VStack {
                        IssueBanner(issue: issue, dismiss: { browser.issue = nil }).padding(14)
                        Spacer()
                    }
                }
            }
            // Abstand zu den runden Ecken: Zeilen und Rollbalken werden nicht angeschnitten
            .padding(.horizontal, 6)
            .padding(.bottom, 10)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Radius.panel - 3, style: .continuous)
                .strokeBorder(Palette.bridgeBlue, lineWidth: 2.5)
                .padding(3)
                .opacity(dropTargeted ? 1 : 0)
                .allowsHitTesting(false)
        )
        .onDrop(of: [.androidBridgeEntries], isTargeted: $dropTargeted) { providers in
            receive(providers)
            return true
        }
        .simultaneousGesture(TapGesture().onEnded { files.activePane = .local })
        .quickLookPreview($quickLookURL)
    }

    private var macCapacity: CapacityInfo? {
        guard let values = try? browser.folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
              let total = values.volumeTotalCapacity, total > 0,
              let free = values.volumeAvailableCapacityForImportantUsage else { return nil }
        let used = Double(Int64(total) - free) / Double(total)
        return CapacityInfo(used: min(max(used, 0), 1),
                            label: "\(ByteFormat.string(UInt64(max(free, 0)))) frei von \(ByteFormat.string(UInt64(total)))")
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132, maximum: 180), spacing: 14)], spacing: 16) {
                ForEach(browser.visible) { e in
                    FileTile(name: e.name, detail: e.isFolder && !e.isPackage ? "Ordner" : ByteFormat.string(e.size),
                             selected: browser.selection.contains(e.url)) {
                        LocalThumb(url: e.url, size: 92)
                    }
                    .onTapGesture(count: 2) {
                        if e.isFolder && !e.isPackage { browser.enter(e) } else { quickLookURL = e.url }
                    }
                    .onTapGesture { selectInGrid(e.url) }
                    .onDrag { NSItemProvider(object: e.url as NSURL) }
                    .contextMenu {
                        Button("Auf das Telefon übertragen") { files.uploadToDevice([e.url]) }
                            .disabled(files.device.device == nil)
                        Button("Vorschau") { quickLookURL = e.url }
                        Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([e.url]) }
                        Button("Umbenennen …") { browser.selection = [e.url]; files.renamePane = .local }
                        Divider()
                        Button("In den Papierkorb legen …", role: .destructive) {
                            browser.selection = [e.url]
                            files.activePane = .local
                            files.requestDelete()
                        }
                    }
                }
            }
            .reportsScrollEdge()
            .padding(14)
            .padding(.bottom, 80)
        }
        .contentShape(Rectangle())
        .onTapGesture { browser.selection = []; files.activePane = .local }
    }

    private func selectInGrid(_ url: URL) {
        files.activePane = .local
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if browser.selection.contains(url) { browser.selection.remove(url) } else { browser.selection.insert(url) }
        } else if flags.contains(.shift), let anchor = gridAnchor,
                  let a = browser.visible.firstIndex(where: { $0.url == anchor }), let b = browser.visible.firstIndex(where: { $0.url == url }) {
            browser.selection.formUnion(browser.visible[min(a, b)...max(a, b)].map(\.url))
            return
        } else {
            browser.selection = [url]
        }
        gridAnchor = url
    }

    private var placesMenu: some View {
        Menu {
            Section("Orte") {
                ForEach(LocalFiles.places) { p in
                    Button { browser.open(p.url) } label: { Label(p.name, systemImage: p.symbolName) }
                }
            }
            Section("Laufwerke") {
                ForEach(LocalFiles.volumes) { v in
                    Button { browser.open(v.url) } label: { Label(v.name, systemImage: v.symbolName) }
                }
            }
            Divider()
            Button("Ordner wählen …") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.canCreateDirectories = true
                panel.directoryURL = browser.folder
                if panel.runModal() == .OK, let url = panel.url { browser.open(url) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: MacHardware.current.symbolName).foregroundStyle(Palette.accent)
                Text(MacHardware.current.familyName).font(.ui(13, .semibold)).lineLimit(1)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var table: some View {
        Table(of: LocalEntry.self, selection: $browser.selection) {
            TableColumn("Name") { e in
                HStack(spacing: 8) {
                    // Echte Vorschau (Fotos, PDFs, Dokumente) – sonst das Finder-Symbol
                    LocalThumb(url: e.url, size: 22)
                    Text(e.name).lineLimit(1).truncationMode(.middle)
                }
            }
            .width(min: 130, ideal: 200)
            TableColumn("Geändert") { e in
                Text(e.modified.map { $0.formatted(date: .numeric, time: .shortened) } ?? "–").foregroundStyle(.secondary)
                    .monospacedDigit().lineLimit(1)
            }
            .width(min: 88, ideal: 112)
            TableColumn("Größe") { e in
                Text(e.isFolder && !e.isPackage ? "–" : ByteFormat.string(e.size)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
            .width(min: 52, ideal: 64)
        } rows: {
            ForEach(browser.visible) { e in
                TableRow(e).itemProvider { NSItemProvider(object: e.url as NSURL) }
            }
        }
        .focused($tableFocused)
        .onChange(of: tableFocused) { f in if f { files.activePane = .local } }
        .onChange(of: browser.selection) { s in if !s.isEmpty { files.activePane = .local } }
        .contextMenu(forSelectionType: URL.self) { ids in
            let entries = browser.visible.filter { ids.contains($0.url) }
            if !entries.isEmpty {
                Button("Auf das Telefon übertragen") { files.uploadToDevice(entries.map(\.url)) }
                    .disabled(files.device.device == nil)
                Button("Vorschau") { quickLookURL = entries.first?.url }
                Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting(entries.map(\.url)) }
                if entries.count == 1, let e = entries.first {
                    Button("Umbenennen …") { browser.selection = [e.url]; files.renamePane = .local }
                }
                Divider()
                Button("In den Papierkorb legen …", role: .destructive) {
                    browser.selection = ids
                    files.activePane = .local
                    files.requestDelete()
                }
            } else {
                Button("Neuer Ordner …") { files.activePane = .local; files.requestNewFolder() }
            }
        } primaryAction: { ids in
            if let e = browser.visible.first(where: { ids.contains($0.url) }), ids.count == 1 { browser.enter(e) }
        }
        .onDeleteCommand { files.activePane = .local; files.requestDelete() }
        .onCopyCommand {
            files.activePane = .local
            files.copySelection()
            return browser.selectedEntries.map { NSItemProvider(object: $0.url as NSURL) }
        }
        .onPasteCommand(of: [.androidBridgeEntries]) { providers in
            files.activePane = .local
            receive(providers)
        }
        .scrollContentBackground(.hidden)
        .quietRows(when: browser.visible.isEmpty)
    }

    private func receive(_ providers: [NSItemProvider]) {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.androidBridgeEntries.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.androidBridgeEntries.identifier) { data, _ in
                guard let data, let payload = try? JSONDecoder().decode(DeviceDragPayload.self, from: data) else { return }
                DispatchQueue.main.async {
                    guard files.device.device?.id == payload.deviceID else { return }
                    files.transferToMac(payload.entries, useSmartDestination: false, destination: browser.folder)
                }
            }
            break
        }
    }
}

// MARK: - Aktionsleiste unten

struct SelectionActionBar: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var files: FileManagerModel
    @ObservedObject var local: LocalBrowserModel
    @ObservedObject var device: DeviceBrowserModel
    @Environment(\.animationsEnabled) private var animations

    private var deviceCount: Int { device.selection.count }
    private var localCount: Int { local.selection.count }

    var body: some View {
        Group {
            if files.activePane == .device ? deviceCount > 0 : localCount > 0 {
                FloatingActionBar {
                    if files.activePane == .device {
                        SelectionSummary(count: deviceCount, bytes: files.deviceSelectionSize)
                        Button {
                            files.transferDeviceSelectionToMac()
                        } label: {
                            Label(files.layout == .dual ? "In „\(local.folder.lastPathComponent)“ übertragen" : "Auf den Mac übertragen",
                                  systemImage: "arrow.down.to.line")
                        }
                        .buttonStyle(GlassButtonStyle(prominent: true, compact: true))
                        if deviceCount == 1, let e = device.selectedEntries.first, let d = device.device {
                            ToolbarIconButton(symbol: "pencil", help: "Umbenennen …") { files.activePane = .device; files.renamePane = .device }
                            ToolbarIconButton(symbol: "info.circle", help: "Informationen") {
                                model.infoEntry = EntryInfoBox(deviceID: d.id, entry: e, path: device.pathNames)
                            }
                            if e.isFolder, let loc = device.location {
                                let folderLoc = DeviceLocation(deviceSerial: loc.deviceSerial, deviceName: loc.deviceName, storageID: loc.storageID,
                                                               storageName: loc.storageName, path: loc.path + [e.name])
                                ToolbarIconButton(symbol: model.favorites.contains(folderLoc) ? "star.fill" : "star",
                                                  help: model.favorites.contains(folderLoc) ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen") {
                                    model.favorites.toggle(folderLoc)
                                }
                            }
                        }
                        Button {
                            model.deleteDeviceSelection(in: files)
                        } label: {
                            Label("Löschen …", systemImage: "trash")
                        }
                        .buttonStyle(GlassButtonStyle(destructive: true, compact: true))
                        .help("Auf dem Telefon endgültig löschen (⌘⌫)")
                    } else {
                        SelectionSummary(count: localCount, bytes: files.localSelectionSize)
                        Button {
                            files.transferLocalSelectionToDevice()
                        } label: {
                            Label("Aufs Telefon übertragen", systemImage: "arrow.up.to.line")
                        }
                        .buttonStyle(GlassButtonStyle(prominent: true, compact: true))
                        .disabled(device.device == nil)
                        if localCount == 1 {
                            ToolbarIconButton(symbol: "pencil", help: "Umbenennen …") { files.activePane = .local; files.renamePane = .local }
                        }
                        ToolbarIconButton(symbol: "magnifyingglass", help: "Im Finder zeigen") {
                            NSWorkspace.shared.activateFileViewerSelecting(local.selectedEntries.map(\.url))
                        }
                        ToolbarIconButton(symbol: "trash", help: "In den Papierkorb legen …", tint: Palette.danger) {
                            files.activePane = .local
                            files.requestDelete()
                        }
                    }
                    ToolbarIconButton(symbol: "xmark", help: "Auswahl aufheben") { files.deselectAll() }
                }
            }
        }
        .animation(animations ? .bridgeSpring : nil, value: files.activePane == .device ? deviceCount : localCount)
    }
}

/// Kachel im Raster (Vorschaubild, Name, Größe).
struct FileTile<Thumb: View>: View {
    let name: String
    let detail: String
    let selected: Bool
    @ViewBuilder var thumb: () -> Thumb
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 7) {
            thumb()
                .frame(width: 92, height: 92)
                .shadow(color: Palette.shadow.opacity(hovering ? 1 : 0.4), radius: hovering ? 8 : 3, y: 2)
                .scaleEffect(hovering ? 1.04 : 1)
            Text(name)
                .font(.ui(11.5, .medium))
                .foregroundStyle(selected ? Palette.onAccent : Palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? Palette.accent : .clear))
            Text(detail)
                .font(.ui(10.5))
                .foregroundStyle(Palette.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .fill(selected ? Palette.selectionFill : (hovering ? Palette.hoverFill : .clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.bridgeQuick, value: hovering)
        .help(name)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Vorschaubild einer Mac-Datei (Quick Look), sonst Finder-Symbol.
struct LocalThumb: View {
    let url: URL
    var size: CGFloat = 92
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size * 0.86, height: size * 0.86)
                    .frame(width: size, height: size)
            }
        }
        .task(id: url) {
            image = await ThumbnailService.shared.localThumbnail(for: url, size: size)
        }
    }
}
