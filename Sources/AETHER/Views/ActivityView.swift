import SwiftUI
import AppKit
import AetherCore
import AetherSystem

/// Aktivität: alle Prozesse oder App-Familien, Filter, Suche, Sortierung, Inspektor und sichere Aktionen.
struct ActivityView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: ProcessStore
    @Environment(\.aether) private var theme
    @State private var filter: ProcessFilter = .all
    @State private var query = ""
    @State private var grouped = false
    @State private var selection: Set<Int32> = []
    @State private var familySelection: Set<String> = []
    @State private var sortOrder = [KeyPathComparator(\ProcessRow.cpuSort, order: .reverse)]
    @State private var familySortOrder = [KeyPathComparator(\FamilyRow.cpuSort, order: .reverse)]
    @State private var pending: PendingAction?
    @State private var message: String?
    /// Prozesslandschaft über der Tabelle (ausblendbar, damit die Tabelle mehr Platz hat).
    @AppStorage("aether.activity.landscape") private var showLandscape = true

    struct PendingAction: Identifiable {
        let id = UUID()
        let row: ProcessRow
        let force: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if showLandscape {
                ZStack {
                    StageLight(color: AppSection.activity.tint(theme))
                        .padding(.horizontal, -Spacing.gutter)
                        .padding(.vertical, -24)
                    ProcessLandscapeHero(store: store, selected: grouped ? nil : selection.first) { pid in
                        grouped = false
                        selection = [pid]
                    }
                }
                .frame(height: 196)
                .padding(.vertical, 4)
                .transition(.opacity)
            }
            filterBar
            if store.loaded && !store.othersAvailable {
                NoticeBar(text: tr("CPU and memory values of other users’ and system processes are only available to programs with administrator rights. AETHER deliberately doesn’t ask for them."))
            }
            if let message {
                NoticeBar(text: message, symbol: "exclamationmark.triangle")
                    .onTapGesture { self.message = nil }
            }
            HStack(alignment: .top, spacing: theme.density.cardSpacing) {
                Group {
                    if grouped { familyTable } else { processTable }
                }
                .padding(6)
                .glassCard()
                if grouped, let id = familySelection.first, let family = store.families.first(where: { $0.id == id }) {
                    FamilyInspector(family: family, store: store) { pid in
                        grouped = false
                        selection = [pid]
                    }
                    .frame(width: 300)
                } else if !grouped, let pid = selection.first, let row = store.row(pid) {
                    ProcessInspector(row: row, store: store, parentName: store.row(row.ppid)?.name) { force in
                        request(row, force: force)
                    }
                    .frame(width: 300)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.bottom, Spacing.gutter)
        .aetherAnimation(Motion.easeOut(0.3), value: showLandscape)
        .onAppear {
            if let pid = model.focusedPID {
                selection = [pid]
                model.focusedPID = nil
            }
        }
        .onChange(of: selection) { newValue in
            store.selectedPID = newValue.count == 1 ? newValue.first : nil
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible, presenting: pending) { action in
            Button(action.force ? tr("Force Quit") : tr("Quit"), role: .destructive) { perform(action) }
            Button(tr("Cancel"), role: .cancel) {}
        } message: { action in
            Text(confirmMessage(action))
        }
    }

    // MARK: Kopf und Filter

    /// Überzeile, Aussage, Anzahl – daneben (oder bei schmalem Fenster darunter) die Werkzeuge.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Spacing.xl) {
                headline
                Spacer(minLength: Spacing.l)
                tools
            }
            VStack(alignment: .leading, spacing: Spacing.m) {
                headline
                tools
            }
        }
        .padding(.top, Metrics.headerTop + 6)
    }

    private var headline: some View {
        StudioHeadline(eyebrow: tr("Activity"), headline: tr("What your Mac is working on"), lead: subtitle,
                       tint: AppSection.activity.tint(theme), compact: true)
    }

    private var tools: some View {
        HStack(spacing: Spacing.s) {
            Picker("", selection: $grouped) {
                Text(tr("Processes")).tag(false)
                Text(tr("App families")).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 230)
            SearchField(text: $query, prompt: tr("Name, PID or path"))
                .frame(width: 220)
            ToolbarIconButton(symbol: "chart.bar.xaxis",
                              help: showLandscape ? tr("Hide process landscape") : tr("Show process landscape"),
                              active: showLandscape) {
                showLandscape.toggle()
            }
        }
    }

    private var subtitle: String {
        guard store.loaded else { return tr("Measuring…") }
        let apps = store.rows.filter(\.isApp).count
        return tr("%ld processes · %ld apps", store.rows.count, apps)
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(ProcessFilter.allCases) { f in
                Button {
                    filter = f
                } label: {
                    HStack(spacing: 5) {
                        Text(filterName(f))
                        Text("\(count(for: f))").foregroundStyle(filter == f ? theme.onAccent.opacity(0.8) : theme.textTertiary)
                    }
                    .font(.system(size: 12, weight: filter == f ? .semibold : .regular))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .foregroundStyle(filter == f ? theme.onAccent : theme.textPrimary)
                    .background(Capsule().fill(filter == f ? theme.accent : theme.fieldFill))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(filterHelp(f))
            }
            Spacer()
        }
    }

    private func filterName(_ f: ProcessFilter) -> String {
        switch f {
        case .all: return tr("All")
        case .mine: return tr("My processes")
        case .system: return tr("System")
        case .apps: return tr("Apps")
        case .highCPU: return tr("High CPU")
        case .highMemory: return tr("High memory")
        }
    }

    private func filterHelp(_ f: ProcessFilter) -> String {
        switch f {
        case .highCPU: return tr("At least %@ of one core", fmt.percent(ProcessFilter.highCPUThreshold))
        case .highMemory: return tr("At least %@", fmt.bytes(ProcessFilter.highMemoryThreshold, style: .memory))
        case .system: return tr("Processes of other users (root and system services) and protected system processes")
        default: return filterName(f)
        }
    }

    private func passes(_ row: ProcessRow, _ f: ProcessFilter) -> Bool { f.passes(row) }

    /// Einmal je Messung im Store berechnet (nicht bei jedem Neuzeichnen).
    private func count(for f: ProcessFilter) -> Int { store.filterCounts[f] ?? 0 }

    private var visibleRows: [ProcessRow] {
        store.rows
            .filter { passes($0, filter) && ProcessSearch.matches(query: query, name: $0.name, pid: $0.pid, path: $0.path, appName: $0.appName) }
            .sorted(using: sortOrder)
    }

    private var visibleFamilies: [FamilyRow] {
        let rowsByPID = Dictionary(store.rows.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        return store.families
            .filter { family in
                family.members.contains { pid in
                    guard let row = rowsByPID[pid] else { return false }
                    return passes(row, filter)
                        && ProcessSearch.matches(query: query, name: row.name, pid: row.pid, path: row.path, appName: row.appName)
                } || (!query.isEmpty && family.name.lowercased().contains(query.lowercased()))
            }
            .sorted(using: familySortOrder)
    }

    // MARK: Tabellen

    private var processTable: some View {
        Table(visibleRows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn(tr("Name"), value: \ProcessRow.nameSort) { row in
                HStack(spacing: 7) {
                    Image(nsImage: IconCache.icon(pid: row.pid, bundlePath: row.bundlePath))
                        .resizable().frame(width: 16, height: 16)
                    Text(row.name).lineLimit(1)
                    if row.isTranslated {
                        Text("Rosetta").font(.system(size: 9, weight: .semibold)).padding(.horizontal, 4)
                            .background(Capsule().fill(theme.statusElevated.opacity(0.2)))
                    }
                }
                .help(row.path ?? row.command)
            }
            .width(min: 180, ideal: 260)
            TableColumn(tr("CPU"), value: \ProcessRow.cpuSort) { row in
                Text(row.cpu.map { fmt.percent($0, fractionDigits: 1) } ?? "–").monospacedDigit()
                    .foregroundStyle(row.cpu == nil ? theme.textTertiary : theme.textPrimary)
            }
            .width(min: 56, ideal: 70)
            TableColumn(tr("Memory"), value: \ProcessRow.memorySort) { row in
                HStack(spacing: 3) {
                    Text(row.memory.map { fmt.bytes($0, style: .memory) } ?? "–").monospacedDigit()
                    if row.source == .ps && row.memory != nil {
                        Text("RSS").font(.system(size: 8, weight: .semibold)).foregroundStyle(theme.textTertiary)
                    }
                }
                .foregroundStyle(row.memory == nil ? theme.textTertiary : theme.textPrimary)
            }
            .width(min: 70, ideal: 90)
            TableColumn(tr("Threads"), value: \ProcessRow.threadSort) { row in
                Text(row.threads.map { "\($0)" } ?? "–").monospacedDigit()
                    .foregroundStyle(row.threads == nil ? theme.textTertiary : theme.textPrimary)
            }
            .width(min: 50, ideal: 60)
            TableColumn("PID", value: \ProcessRow.pidSort) { row in
                Text(String(row.pid)).monospacedDigit().foregroundStyle(theme.textSecondary)
            }
            .width(min: 46, ideal: 56)
            TableColumn(tr("User"), value: \ProcessRow.userSort) { row in
                Text(row.user).foregroundStyle(row.isOwn ? theme.textPrimary : theme.textSecondary).lineLimit(1)
            }
            .width(min: 60, ideal: 90)
            TableColumn(tr("Kind"), value: \ProcessRow.kindSort) { row in
                Text(kindName(row)).foregroundStyle(theme.textSecondary).lineLimit(1)
            }
            .width(min: 60, ideal: 90)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        // Neue Messwerte ohne Zeilenanimation übernehmen (530 Zeilen umzustellen kostet sonst viel Rechenzeit)
        .transaction { $0.animation = nil }
        .contextMenu(forSelectionType: Int32.self) { ids in
            if let pid = ids.first, let row = store.row(pid) {
                processMenu(row)
            }
        } primaryAction: { ids in
            selection = ids
        }
    }

    @ViewBuilder
    private func processMenu(_ row: ProcessRow) -> some View {
        Button(tr("Quit")) { request(row, force: false) }
        Button(tr("Force Quit…")) { request(row, force: true) }
        Divider()
        if let path = row.bundlePath ?? row.path {
            Button(tr("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
            Button(tr("Copy Path")) { copy(path) }
        }
        Button(tr("Copy PID")) { copy(String(row.pid)) }
    }

    private var familyTable: some View {
        Table(visibleFamilies, selection: $familySelection, sortOrder: $familySortOrder) {
            TableColumn(tr("App or process"), value: \FamilyRow.nameSort) { family in
                HStack(spacing: 7) {
                    Image(nsImage: family.bundlePath.map { IconCache.icon(path: $0) }
                          ?? IconCache.icon(pid: family.members.first ?? 0, bundlePath: nil))
                        .resizable().frame(width: 16, height: 16)
                    Text(family.name).lineLimit(1)
                }
            }
            .width(min: 200, ideal: 300)
            TableColumn(tr("Processes"), value: \FamilyRow.countSort) { family in
                Text("\(family.members.count)").monospacedDigit()
            }
            .width(min: 60, ideal: 80)
            TableColumn(tr("CPU"), value: \FamilyRow.cpuSort) { family in
                Text(family.cpu.map { fmt.percent($0, fractionDigits: 1) } ?? "–").monospacedDigit()
            }
            .width(min: 60, ideal: 80)
            TableColumn(tr("Memory"), value: \FamilyRow.memorySort) { family in
                HStack(spacing: 3) {
                    Text(family.memory.map { fmt.bytes($0, style: .memory) } ?? "–").monospacedDigit()
                    if family.mixedMemorySources {
                        Text("≈").foregroundStyle(theme.textTertiary).help(tr("Mixed sources: memory footprint and resident memory"))
                    }
                }
            }
            .width(min: 80, ideal: 100)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
    }

    private func kindName(_ row: ProcessRow) -> String {
        if row.isApp { return tr("App") }
        if !row.isOwn { return tr("System") }
        if row.protection == .confirmSystem { return tr("System service") }
        return tr("Background")
    }

    // MARK: Aktionen

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func request(_ row: ProcessRow, force: Bool) {
        switch row.protection {
        case .blocked:
            message = tr("“%@” is essential for macOS and is never quit by AETHER.", row.name)
        case .otherUser:
            message = tr("“%@” belongs to another user (%@). macOS only allows quitting it with administrator rights.", row.name, row.user)
        case .allowed where !force && row.isApp:
            perform(PendingAction(row: row, force: false))
        case .allowed, .confirmSystem:
            pending = PendingAction(row: row, force: force)
        }
    }

    private var confirmTitle: String {
        guard let pending else { return "" }
        return pending.force ? tr("Force quit “%@”?", pending.row.name) : tr("Quit “%@”?", pending.row.name)
    }

    private func confirmMessage(_ action: PendingAction) -> String {
        var text = action.force
            ? tr("Unsaved changes will be lost. The process ends immediately.")
            : tr("The process is asked to quit; apps can still ask to save.")
        if action.row.protection == .confirmSystem {
            text += "\n\n" + tr("This is a system process. macOS usually restarts it, but quitting it can briefly affect your Mac.")
        }
        return text
    }

    private func perform(_ action: PendingAction) {
        let row = action.row
        if let app = NSRunningApplication(processIdentifier: row.pid) {
            let ok = action.force ? app.forceTerminate() : app.terminate()
            message = ok ? nil : tr("“%@” didn’t accept the request.", row.name)
        } else {
            switch ProcessControl.signal(pid: row.pid, force: action.force) {
            case .sent: message = nil
            case .notPermitted: message = tr("macOS doesn’t allow quitting “%@” without administrator rights.", row.name)
            case .notRunning: message = tr("“%@” is no longer running.", row.name)
            case .failed(let code): message = tr("Quitting failed (error %ld).", Int(code))
            }
        }
        pending = nil
        model.engine.refreshNow()
    }
}

/// Suchfeld im Stil der Systemsuche.
struct SearchField: View {
    @Binding var text: String
    let prompt: String
    @Environment(\.aether) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(theme.textTertiary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Capsule().fill(theme.fieldFill))
    }
}

/// Details eines Prozesses mit Aktionen.
private struct ProcessInspector: View {
    let row: ProcessRow
    @ObservedObject var store: ProcessStore
    let parentName: String?
    let onQuit: (Bool) -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.aether) private var theme
    @State private var foreignThreads: Int?

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(spacing: 10) {
                    Image(nsImage: IconCache.icon(pid: row.pid, bundlePath: row.bundlePath)).resizable().frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                        Text(row.bundleID ?? row.command).font(Typo.mono).foregroundStyle(theme.textTertiary).lineLimit(1)
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    ValueText(value: row.cpu.map { fmt.number($0 * 100, fractionDigits: 1) } ?? "–", unit: "%", font: Typo.metric)
                    Text(tr("CPU")).font(Typo.caption).foregroundStyle(theme.textSecondary)
                    Spacer()
                }
                Sparkline(values: store.selectedHistory.elements, color: theme.cpuUser, capacity: sparklineCapacity,
                          scaleMax: max(1, store.selectedHistory.maximum ?? 1))
                    .frame(height: 36)
                VStack(spacing: 6) {
                    InfoRow(label: tr("Memory"), value: row.memory.map { fmt.bytes($0, style: .memory) } ?? tr("Not available"))
                    InfoRow(label: tr("Measured as"), value: memoryKind(row))
                    InfoRow(label: tr("Threads"), value: (row.threads ?? foreignThreads).map { "\($0)" } ?? "–")
                    InfoRow(label: "PID", value: String(row.pid))
                    InfoRow(label: tr("Parent process"), value: parentName.map { "\($0) (\(row.ppid))" } ?? String(row.ppid))
                    InfoRow(label: tr("User"), value: row.user)
                    InfoRow(label: tr("State"), value: stateName(row.state))
                    InfoRow(label: tr("Architecture"), value: architecture(row))
                    if let start = row.startTime {
                        InfoRow(label: tr("Started"), value: start.formatted(date: .abbreviated, time: .shortened))
                        InfoRow(label: tr("Running for"), value: fmt.duration(seconds: Date().timeIntervalSince(start)))
                    }
                    if let app = row.appName { InfoRow(label: tr("App"), value: app) }
                }
                if let path = row.path {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("Path")).font(Typo.caption).foregroundStyle(theme.textSecondary)
                        Text(path).font(Typo.mono).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider().overlay(theme.hairline)
                VStack(alignment: .leading, spacing: 8) {
                    Button(tr("Quit")) { onQuit(false) }.buttonStyle(CapsuleButtonStyle())
                    Button(tr("Force Quit…")) { onQuit(true) }.buttonStyle(CapsuleButtonStyle())
                    if let path = row.bundlePath ?? row.path {
                        Button(tr("Show in Finder")) {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        }
                        .buttonStyle(CapsuleButtonStyle())
                    }
                    if row.isApp, let app = NSRunningApplication(processIdentifier: row.pid) {
                        Button(tr("Bring to front")) { app.activate(options: [.activateAllWindows]) }
                            .buttonStyle(CapsuleButtonStyle())
                    }
                }
                protectionNote
            }
            .padding(16)
        }
        .glassCard()
        .task(id: row.pid) {
            foreignThreads = nil
            guard row.threads == nil else { return }
            let pid = row.pid
            foreignThreads = await Task.detached(priority: .utility) { ProcessSource().threadCount(pid: pid) }.value
        }
    }

    @ViewBuilder
    private var protectionNote: some View {
        switch row.protection {
        case .blocked:
            Label(tr("Essential for macOS – protected."), systemImage: "lock.fill").font(Typo.caption).foregroundStyle(theme.textSecondary)
        case .otherUser:
            Label(tr("Belongs to another user – quitting needs administrator rights."), systemImage: "person.2")
                .font(Typo.caption).foregroundStyle(theme.textSecondary)
        case .confirmSystem:
            Label(tr("System process – quitting asks for confirmation."), systemImage: "exclamationmark.shield")
                .font(Typo.caption).foregroundStyle(theme.textSecondary)
        case .allowed:
            EmptyView()
        }
    }

    private func memoryKind(_ row: ProcessRow) -> String {
        switch row.source {
        case .libproc: return tr("Memory footprint (like Activity Monitor)")
        case .ps: return tr("Resident memory (RSS, via ps)")
        case .unavailable: return tr("Not available without administrator rights")
        }
    }

    private func architecture(_ row: ProcessRow) -> String {
        if row.isTranslated { return tr("Intel (via Rosetta)") }
        return model.engine.system.hardware.isAppleSilicon ? tr("Apple Silicon (native)") : tr("Intel (native)")
    }
}

func stateName(_ state: ProcessState) -> String {
    switch state {
    case .running: return tr("Running")
    case .sleeping: return tr("Waiting")
    case .idle: return tr("Starting")
    case .stopped: return tr("Stopped")
    case .zombie: return tr("Ended (zombie)")
    case .unknown: return tr("Unknown")
    }
}

/// Mitglieder einer App-Familie.
private struct FamilyInspector: View {
    let family: FamilyRow
    @ObservedObject var store: ProcessStore
    let onSelect: (Int32) -> Void
    @Environment(\.aether) private var theme

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(spacing: 10) {
                    Image(nsImage: family.bundlePath.map { IconCache.icon(path: $0) } ?? IconCache.icon(pid: family.members.first ?? 0, bundlePath: nil))
                        .resizable().frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(family.name).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                        Text(tr("%ld processes", family.members.count)).font(Typo.caption).foregroundStyle(theme.textSecondary)
                    }
                }
                InfoRow(label: tr("CPU together"), value: family.cpu.map { fmt.percent($0, fractionDigits: 1) } ?? "–")
                InfoRow(label: tr("Memory together"), value: family.memory.map { fmt.bytes($0, style: .memory) } ?? "–")
                Divider().overlay(theme.hairline)
                VStack(spacing: 4) {
                    ForEach(family.members, id: \.self) { pid in
                        if let row = store.row(pid) {
                            Button { onSelect(pid) } label: {
                                HStack {
                                    Text(row.name).font(Typo.callout).lineLimit(1)
                                    Spacer()
                                    Text(row.cpu.map { fmt.percent($0, fractionDigits: 1) } ?? "–").font(Typo.caption).monospacedDigit()
                                    Text(row.memory.map { fmt.bytes($0, style: .memory) } ?? "–").font(Typo.caption).monospacedDigit()
                                        .frame(width: 64, alignment: .trailing)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text(tr("Grouped by app bundle in the program path and by parent process. Helpers started by the system (e.g. web content) can’t be assigned without private interfaces."))
                    .font(Typo.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .glassCard()
    }
}
