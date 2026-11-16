import SwiftUI
import AppKit
import PanoraCore

// MARK: - Verlauf (wie „Alben“ nach Monat gruppiert)

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var chats: ChatStore
    @Environment(\.panora) private var colors
    @State private var search = ""
    @State private var favoritesOnly = false

    var body: some View {
        let filtered = chats.conversations.filter { c in
            (!favoritesOnly || c.favorite) &&
            (search.isEmpty || c.title.localizedCaseInsensitiveContains(search) ||
             c.messages.contains { $0.text.localizedCaseInsensitiveContains(search) })
        }
        let groups = Dictionary(grouping: filtered) { Formatting.monthYear($0.updated) }
        let order = filtered.map { Formatting.monthYear($0.updated) }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        PageScaffold(title: "Verlauf", subtitle: Formatting.count(filtered.count, "Chat", "Chats"), search: $search,
                     searchPrompt: "Titel oder Inhalt", bottomInset: 120) {
            ToolbarCapsule {
                ToolbarIcon(systemName: "square.grid.2x2", selected: model.historyGrid, help: "Raster") { model.historyGrid = true }
                ToolbarIcon(systemName: "list.bullet", selected: !model.historyGrid, help: "Liste") { model.historyGrid = false }
                ToolbarDivider()
                ToolbarIcon(systemName: favoritesOnly ? "star.fill" : "star", selected: favoritesOnly, help: "Nur Favoriten") { favoritesOnly.toggle() }
                ToolbarIcon(systemName: "square.and.pencil", help: "Neuer Chat") { model.newChat() }
            }
        } content: {
            if filtered.isEmpty {
                EmptyStateView(systemImage: "bubble.left.and.text.bubble.right", title: chats.conversations.isEmpty ? "Noch keine Chats" : "Nichts gefunden",
                               text: "Unterhaltungen werden lokal auf deinem Mac gespeichert.", actionTitle: "Neuer Chat") { model.newChat() }
            }
            ForEach(order, id: \.self) { month in
                let items = groups[month] ?? []
                SectionHeader(title: month, count: Formatting.count(items.count, "Chat", "Chats"))
                if model.historyGrid {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 260), spacing: 26)], alignment: .leading, spacing: 26) {
                        ForEach(items) { c in ChatCard(conversation: c) }
                    }
                    .padding(.bottom, 18)
                } else {
                    VStack(spacing: 6) { ForEach(items) { c in ChatRow(conversation: c) } }.padding(.bottom, 18)
                }
            }
        }
    }
}

private struct ChatCover: View {
    @Environment(\.panora) private var colors
    let conversation: Conversation

    private var unique: [String] {
        let families = conversation.messages.compactMap { m -> String? in
            guard m.role == .assistant, let id = m.modelID else { return nil }
            return ModelNameParser.parse(id.replacingOccurrences(of: "mlx:", with: "").replacingOccurrences(of: "ollama:", with: "")).family
        }
        var unique: [String] = []
        for f in families where !unique.contains(f) { unique.append(f) }
        return unique.isEmpty ? ["Weitere"] : unique
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HStack(spacing: 0) {
                ForEach(unique.prefix(4), id: \.self) { f in
                    LinearGradient(colors: colors.family(f), startPoint: .top, endPoint: .bottom)
                }
            }
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: conversation.projectPath != nil ? "folder.fill" : "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 22, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                if conversation.switchCount > 0 {
                    Text("\(conversation.switchCount) Modellwechsel").font(Typo.label(11, .semibold)).foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(14)
            if conversation.favorite {
                Image(systemName: "star.fill").foregroundStyle(.white).padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ChatCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var chats: ChatStore
    @Environment(\.panora) private var colors
    let conversation: Conversation
    @State private var hover = false

    var body: some View {
        Button { model.openChat(conversation.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                ChatCover(conversation: conversation)
                    .scaleEffect(hover ? 1.015 : 1)
                    .shadow(color: .black.opacity(hover ? 0.25 : 0.12), radius: hover ? 12 : 6, y: 4)
                Text(conversation.title).font(Typo.body(14, .semibold)).foregroundStyle(colors.textPrimary).lineLimit(1)
                Text(conversation.modelsUsed.first ?? "Noch keine Antwort").font(Typo.label(12.5)).foregroundStyle(colors.textSecondary).lineLimit(1)
                Text("\(Formatting.count(conversation.messages.filter { $0.role != .event }.count, "Nachricht", "Nachrichten")) · \(Formatting.count(conversation.modelsUsed.count, "Modell", "Modelle"))")
                    .font(Typo.label(11.5)).foregroundStyle(colors.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Motion.quick) { hover = h } }
        .contextMenu { ChatContextMenu(conversation: conversation) }
    }
}

private struct ChatRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.panora) private var colors
    let conversation: Conversation

    var body: some View {
        Button { model.openChat(conversation.id) } label: {
            HStack(spacing: 14) {
                ChatCover(conversation: conversation).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title).font(Typo.body(14, .semibold)).foregroundStyle(colors.textPrimary).lineLimit(1)
                    Text(conversation.modelsUsed.joined(separator: " → ")).font(Typo.label(12)).foregroundStyle(colors.textSecondary).lineLimit(1)
                }
                Spacer()
                Text(Formatting.dateTime(conversation.updated)).font(Typo.label(12)).foregroundStyle(colors.textTertiary)
            }
            .padding(10)
            .cardSurface(colors, radius: 12)
        }
        .buttonStyle(.plain)
        .contextMenu { ChatContextMenu(conversation: conversation) }
    }
}

private struct ChatContextMenu: View {
    @EnvironmentObject private var chats: ChatStore
    @EnvironmentObject private var model: AppModel
    let conversation: Conversation

    var body: some View {
        Button("Öffnen") { model.openChat(conversation.id) }
        Button(conversation.favorite ? "Aus Favoriten entfernen" : "Zu Favoriten") { chats.toggleFavorite(conversation.id) }
        Button("Als Markdown kopieren") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(chats.markdown(conversation), forType: .string)
        }
        Divider()
        Button("Löschen", role: .destructive) {
            if model.chat.conversation.id == conversation.id { model.chat.newChat() }
            chats.delete(conversation.id)
        }
    }
}

// MARK: - Modelle

struct ModelsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: ModelLibrary
    @EnvironmentObject private var engine: InferenceCoordinator
    @Environment(\.panora) private var colors
    @State private var search = ""
    @State private var backendFilter: BackendKind?
    @State private var detail: InstalledModel?

    var body: some View {
        let filtered = library.models.filter { m in
            (backendFilter == nil || m.spec.backend == backendFilter) &&
            (search.isEmpty || m.spec.displayName.localizedCaseInsensitiveContains(search) || m.spec.repo.localizedCaseInsensitiveContains(search)
             || m.spec.family.localizedCaseInsensitiveContains(search))
        }
        let families = filtered.map(\.spec.family).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let total = library.mlxModels.filter(\.available).reduce(Int64(0)) { $0 + $1.spec.sizeBytes }
        PageScaffold(title: "Modelle",
                     subtitle: "\(Formatting.count(filtered.count, "Modell", "Modelle")) · \(Formatting.bytes(total)) auf Datenträgern · \(Formatting.count(engine.loaded.count, "geladen", "geladen"))",
                     search: $search, searchPrompt: "Modell, Familie oder Repository", bottomInset: 120) {
            ToolbarCapsule {
                ToolbarIcon(systemName: "square.grid.2x2", selected: model.modelsGrid, help: "Raster") { model.modelsGrid = true }
                ToolbarIcon(systemName: "list.bullet", selected: !model.modelsGrid, help: "Liste") { model.modelsGrid = false }
                ToolbarDivider()
                ToolbarIcon(systemName: "line.3.horizontal.decrease", label: backendFilter?.label ?? "Alle", selected: backendFilter != nil,
                            help: "Rechenwerk filtern") {
                    backendFilter = backendFilter == nil ? .mlx : (backendFilter == .mlx ? .ollama : nil)
                }
                ToolbarIcon(systemName: "arrow.clockwise", help: "Neu einlesen") { Task { await library.refresh() } }
                ToolbarIcon(systemName: "plus", help: "Modelle entdecken") { model.open(.discover) }
            }
        } content: {
            ForEach(library.missingDirectories, id: \.self) { dir in
                WarningCard(title: "Laufwerk „\(ModelLibrary.volumeName(of: dir))“ nicht verbunden",
                            text: "Modelle in \(dir) sind gerade nicht verfügbar. Nach dem Anschließen erscheinen sie automatisch wieder.")
                    .padding(.bottom, 12)
            }
            if filtered.isEmpty {
                EmptyStateView(systemImage: "cube", title: library.models.isEmpty ? "Noch keine Modelle" : "Nichts gefunden",
                               text: "Lade Open-Weight-Modelle unter „Entdecken“. Sie laufen danach komplett lokal und offline.",
                               actionTitle: "Entdecken") { model.open(.discover) }
            }
            ForEach(families, id: \.self) { family in
                let items = filtered.filter { $0.spec.family == family }
                SectionHeader(title: family, count: Formatting.count(items.count, "Modell", "Modelle"))
                if model.modelsGrid {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 250), spacing: 26)], alignment: .leading, spacing: 26) {
                        ForEach(items) { m in
                            ModelCard(item: m) { detail = m }
                        }
                    }
                    .padding(.bottom, 18)
                } else {
                    VStack(spacing: 6) { ForEach(items) { m in ModelRow(item: m) { detail = m } } }.padding(.bottom, 18)
                }
            }
        }
        .sheet(item: $detail) { m in
            ModelDetailSheet(item: m) { detail = nil }
                .environmentObject(model)
                .environmentObject(library)
                .environmentObject(engine)
        }
    }
}

struct WarningCard: View {
    @Environment(\.panora) private var colors
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(colors.warning).font(.system(size: 16))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Typo.body(14, .semibold)).foregroundStyle(colors.textPrimary)
                Text(text).font(Typo.label(12.5)).foregroundStyle(colors.textSecondary)
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(colors.warning.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(colors.warning.opacity(0.35), lineWidth: 1))
    }
}

private struct ModelStatus: View {
    @EnvironmentObject private var engine: InferenceCoordinator
    @Environment(\.panora) private var colors
    let item: InstalledModel

    var body: some View {
        if !item.available {
            Badge(text: "Laufwerk fehlt", color: colors.warning, systemImage: "externaldrive.badge.xmark")
        } else if engine.isLoaded(item.id) {
            Badge(text: "Geladen", color: colors.success, systemImage: "bolt.fill")
        } else {
            Badge(text: item.spec.backend.label, color: colors.textSecondary)
        }
    }
}

private struct ModelCard: View {
    @Environment(\.panora) private var colors
    @EnvironmentObject private var engine: InferenceCoordinator
    let item: InstalledModel
    let open: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    ModelCover(family: item.spec.family, name: item.spec.displayName, detail: item.spec.shapeLabel, dimmed: !item.available)
                    if engine.isLoaded(item.id) {
                        Image(systemName: "waveform").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 28, height: 28).background(Circle().fill(.black.opacity(0.35))).padding(10)
                    }
                }
                .scaleEffect(hover ? 1.015 : 1)
                .shadow(color: .black.opacity(hover ? 0.25 : 0.12), radius: hover ? 12 : 6, y: 4)
                Text(item.spec.displayName).font(Typo.body(14, .semibold)).foregroundStyle(colors.textPrimary).lineLimit(1)
                Text("\(Formatting.bytes(item.spec.sizeBytes)) · \(Formatting.context(item.spec.contextLength)) Kontext")
                    .font(Typo.label(12.5)).foregroundStyle(colors.textSecondary).lineLimit(1)
                HStack(spacing: 6) {
                    ModelStatus(item: item)
                    Badge(text: item.spec.license.terms.label, color: item.spec.license.terms.color(colors))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Motion.quick) { hover = h } }
    }
}

private struct ModelRow: View {
    @Environment(\.panora) private var colors
    let item: InstalledModel
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                ModelCover(family: item.spec.family, name: item.spec.displayName, corner: 8, dimmed: !item.available).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.spec.displayName).font(Typo.body(14, .semibold)).foregroundStyle(colors.textPrimary)
                    Text("\(item.spec.shapeLabel) · \(Formatting.bytes(item.spec.sizeBytes)) · \(Formatting.context(item.spec.contextLength))")
                        .font(Typo.label(12)).foregroundStyle(colors.textSecondary)
                }
                Spacer()
                LicenseBadges(license: item.spec.license)
                ModelStatus(item: item)
            }
            .padding(10)
            .cardSurface(colors, radius: 12)
        }
        .buttonStyle(.plain)
    }
}

struct ModelDetailSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: ModelLibrary
    @EnvironmentObject private var engine: InferenceCoordinator
    @Environment(\.colorScheme) private var scheme
    let item: InstalledModel
    let close: () -> Void
    @State private var busy = false
    @State private var error: String?
    @State private var confirmDelete = false

    var body: some View {
        let colors = PanoraColors(dark: scheme == .dark)
        let spec = item.spec
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 18) {
                ModelCover(family: spec.family, name: spec.displayName, detail: spec.shapeLabel).frame(width: 130)
                VStack(alignment: .leading, spacing: 6) {
                    Text(spec.displayName).font(Typo.title(24))
                    Text(spec.repo).font(Typo.label(12)).foregroundStyle(colors.textSecondary).textSelection(.enabled)
                    if let summary = spec.summary { Text(summary).font(Typo.body(13)).foregroundStyle(colors.textSecondary) }
                    if let role = item.catalog?.role { Badge(text: "AUTO-Rolle: \(role)", color: colors.accent) }
                    LicenseBadges(license: spec.license)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                InfoRow(label: "Rechenwerk", value: spec.backend.label)
                InfoRow(label: "Bauart", value: spec.shapeLabel.isEmpty ? "unbekannt" : spec.shapeLabel)
                InfoRow(label: "Größe", value: Formatting.bytes(spec.sizeBytes))
                InfoRow(label: "Kontextfenster", value: Formatting.context(spec.contextLength) + " Tokens")
                InfoRow(label: "Speicherbedarf (8K Kontext)", value: Formatting.bytes(MemoryPlanner.requiredBytes(for: spec, contextTokens: 8192)))
                InfoRow(label: "Fähigkeiten", value: spec.capabilities.sorted { $0.rawValue < $1.rawValue }.map(\.label).joined(separator: ", "))
                if let path = spec.localPath { InfoRow(label: "Ort", value: path) }
                if let tps = model.settings.measuredTokensPerSecond[spec.id] {
                    InfoRow(label: "Gemessen auf diesem Mac", value: "\(Int(tps.rounded())) Token/s")
                }
                if let note = spec.license.note { InfoRow(label: "Lizenz", value: note) }
                if let block = spec.license.regionBlock { InfoRow(label: "Sperre", value: block, valueColor: colors.danger) }
                if !item.available { InfoRow(label: "Status", value: item.unavailableReason ?? "nicht verfügbar", valueColor: colors.warning) }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(colors.surfaceSunken))
            VStack(alignment: .leading, spacing: 6) {
                Text("Qualität (Startwerte, 0–10)").font(Typo.label(12, .semibold)).foregroundStyle(colors.textSecondary)
                SkillBar(label: "Allgemein", value: spec.skills.general, colors: colors)
                SkillBar(label: "Coding", value: spec.skills.coding, colors: colors)
                SkillBar(label: "Reasoning", value: spec.skills.reasoning, colors: colors)
                SkillBar(label: "Texte", value: spec.skills.writing, colors: colors)
            }
            if let error { Text(error).font(Typo.label(12)).foregroundStyle(colors.danger) }
            HStack(spacing: 10) {
                if engine.isLoaded(spec.id) {
                    Button("Entladen") { Task { await engine.unload(spec.id) } }
                } else {
                    Button(busy ? "Lädt …" : "Jetzt laden") {
                        busy = true
                        Task {
                            do { try await engine.ensureLoaded(spec, unloadFirst: [], contextTokens: 8192) }
                            catch { self.error = error.localizedDescription }
                            busy = false
                        }
                    }
                    .disabled(!item.available || busy)
                }
                Button("Im Chat fest verwenden") {
                    model.chat.pin(spec.id)
                    close()
                    model.open(.chat)
                }
                .disabled(!item.available)
                if let path = spec.localPath {
                    Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                }
                Spacer()
                if spec.backend == .mlx && item.available {
                    Button("Entfernen …", role: .destructive) { confirmDelete = true }
                }
                Button("Fertig", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620)
        .confirmationDialog("\(spec.displayName) entfernen?", isPresented: $confirmDelete) {
            Button("In den Papierkorb legen", role: .destructive) {
                Task {
                    await engine.unload(spec.id)
                    do { try library.remove(item); close() } catch { self.error = error.localizedDescription }
                }
            }
        } message: {
            Text("Der Ordner (\(Formatting.bytes(spec.sizeBytes))) wird in den Papierkorb gelegt.")
        }
    }
}

private struct SkillBar: View {
    let label: String
    let value: Double
    let colors: PanoraColors

    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(Typo.label(12)).foregroundStyle(colors.textSecondary).frame(width: 80, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(colors.hairline)
                    Capsule().fill(colors.accent).frame(width: geo.size.width * CGFloat(min(1, value / 10)))
                }
            }
            .frame(height: 6)
            Text(Formatting.decimal(value, digits: 1)).font(Typo.label(12, .semibold)).frame(width: 30, alignment: .trailing)
        }
    }
}

// MARK: - Entdecken

struct DiscoverView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: ModelLibrary
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var hub: HubSearch
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var storage: StorageMonitor
    @Environment(\.panora) private var colors

    var body: some View {
        let offline = !network.online || settings.forceOffline
        let target = storage.volume(containing: settings.downloadDirectory)
        PageScaffold(title: "Entdecken",
                     subtitle: "Open-Weight-Modelle für deinen Mac · Ziel: \(target?.name ?? settings.downloadDirectory) (\(target.map { Formatting.bytes($0.available) + " frei" } ?? "nicht verbunden"))",
                     search: $hub.query, searchPrompt: "Hugging Face durchsuchen (MLX-Modelle), z. B. „Qwen3 Coder“ oder „Gemma 4“", bottomInset: 120) {
            ToolbarCapsule {
                ToolbarIcon(systemName: "magnifyingglass", label: "Suchen", help: "Auf Hugging Face suchen") {
                    Task { await hub.search(online: !offline) }
                }
                ToolbarDivider()
                Menu {
                    ForEach(settings.modelDirectories, id: \.self) { dir in
                        Button(dir == settings.downloadDirectory ? "✓ \(dir)" : dir) { settings.downloadDirectory = dir }
                    }
                    if let ext = model.suggestedExternalDirectory, !settings.modelDirectories.contains(ext) {
                        Divider()
                        Button("Externe SSD verwenden: \(ext)") { model.useDirectory(ext, asDownloadTarget: true) }
                    }
                } label: {
                    Label("Ziel", systemImage: "externaldrive").font(Typo.label(13, .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 8)
            }
        } content: {
            if offline {
                WarningCard(title: "Offline", text: "Downloads und die Suche brauchen Internet. Installierte Modelle funktionieren weiter.")
                    .padding(.bottom, 14)
            }
            if let ext = model.suggestedExternalDirectory, target?.isInternal ?? true, !settings.modelDirectories.contains(ext) {
                HStack(spacing: 12) {
                    Image(systemName: "externaldrive.fill.badge.checkmark").font(.system(size: 20)).foregroundStyle(colors.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Externe SSD erkannt").font(Typo.body(14, .semibold)).foregroundStyle(colors.textPrimary)
                        Text("Große Modelle dort speichern und die interne SSD schonen: \(ext)").font(Typo.label(12.5)).foregroundStyle(colors.textSecondary)
                    }
                    Spacer()
                    ActionButton(title: "Als Ziel verwenden", prominent: true) { model.useDirectory(ext, asDownloadTarget: true) }
                }
                .padding(14)
                .cardSurface(colors, radius: 14, highlighted: true)
                .padding(.bottom, 14)
            }
            if !downloads.items.isEmpty {
                SectionHeader(title: "Downloads", count: Formatting.count(downloads.activeCount, "aktiv", "aktiv"))
                VStack(spacing: 8) { ForEach(downloads.items) { DownloadRow(item: $0) } }.padding(.bottom, 18)
            }
            if hub.searchedOnce || hub.loading || hub.error != nil {
                SectionHeader(title: "Hugging Face", count: hub.loading ? "sucht …" : Formatting.count(hub.results.count, "Treffer", "Treffer"))
                if let error = hub.error { WarningCard(title: "Suche nicht möglich", text: error).padding(.bottom, 10) }
                VStack(spacing: 6) { ForEach(hub.results) { HubRow(summary: $0) } }.padding(.bottom, 18)
            }
            SectionHeader(title: "Empfohlen für deinen Mac", count: Formatting.count(ModelCatalog.entries.count, "Modell", "Modelle"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 250), spacing: 26)], alignment: .leading, spacing: 26) {
                ForEach(ModelCatalog.entries) { CatalogCard(entry: $0) }
            }
            .padding(.bottom, 24)
            SectionHeader(title: "Modellfamilien im Blick")
            VStack(spacing: 6) {
                ForEach(ModelCatalog.families, id: \.name) { f in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(f.name).font(Typo.body(14, .semibold)).foregroundStyle(colors.textPrimary).frame(width: 90, alignment: .leading)
                        Text(f.license).font(Typo.label(12.5, .semibold)).foregroundStyle(colors.accentText).frame(width: 240, alignment: .leading)
                        Text(f.note).font(Typo.label(12.5)).foregroundStyle(colors.textSecondary)
                        Spacer()
                    }
                    .padding(10)
                    .cardSurface(colors, radius: 10)
                }
            }
            Text("„Open Source“ steht nur bei OSI-konformen Modellen (Gewichte, Daten und Code offen). Fast alle bekannten Modelle sind „Open Weight“: Die Gewichte sind frei, Trainingsdaten nicht.")
                .font(Typo.label(12)).foregroundStyle(colors.textTertiary).padding(.top, 10)
        }
    }
}

private struct CatalogCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: ModelLibrary
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.panora) private var colors
    let entry: CatalogEntry

    var body: some View {
        let spec = entry.spec
        let installed = library.isInstalled(repo: spec.repo)
        let fit = model.fit(for: spec.sizeBytes, kvPerToken: spec.kvBytesPerTokenEstimate)
        let dl = downloads.item(spec.repo)
        VStack(alignment: .leading, spacing: 6) {
            ModelCover(family: spec.family, name: spec.displayName, detail: spec.shapeLabel)
            Text(spec.displayName).font(Typo.body(14, .semibold)).foregroundStyle(colors.textPrimary).lineLimit(1)
            Text(entry.role).font(Typo.label(12.5)).foregroundStyle(colors.textSecondary).lineLimit(1)
            HStack(spacing: 6) {
                Badge(text: "ca. \(Formatting.bytes(spec.sizeBytes))", color: colors.textSecondary)
                Badge(text: fit.label, color: fit.ok == true ? colors.success : (fit.ok == nil ? colors.warning : colors.danger))
            }
            Badge(text: "\(spec.license.name) · \(spec.license.terms.label)", color: spec.license.terms.color(colors))
            if let dl, dl.state.isActive {
                MeterBar(fraction: dl.fraction).padding(.top, 4)
                Text("\(Formatting.percent(dl.fraction)) · \(Formatting.bytes(Int64(dl.bytesPerSecond)))/s").font(Typo.label(11.5)).foregroundStyle(colors.textTertiary)
            } else if installed {
                Badge(text: "Installiert", color: colors.success, systemImage: "checkmark")
            } else {
                ActionButton(title: "Laden", systemImage: "arrow.down.circle", prominent: true,
                             disabled: !downloads.canDownload || fit.ok == false) {
                    downloads.start(repo: spec.repo, name: spec.displayName, family: spec.family, hint: entry.searchHint)
                }
                .padding(.top, 2)
            }
        }
        .help(spec.summary ?? "")
    }
}

private struct DownloadRow: View {
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.panora) private var colors
    let item: DownloadItem

    var body: some View {
        HStack(spacing: 14) {
            ModelCover(family: item.family, name: item.name, corner: 8).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.name).font(Typo.body(14, .semibold)).foregroundStyle(colors.textPrimary)
                    if item.resolvedRepo != item.repo { Text("→ \(item.resolvedRepo)").font(Typo.label(11.5)).foregroundStyle(colors.textTertiary) }
                }
                switch item.state {
                case .preparing:
                    Text("Wird vorbereitet …").font(Typo.label(12)).foregroundStyle(colors.textSecondary)
                case .running, .finishing:
                    MeterBar(fraction: item.fraction)
                    Text("\(Formatting.bytes(item.receivedBytes)) von \(Formatting.bytes(item.totalBytes)) · \(Formatting.bytes(Int64(item.bytesPerSecond)))/s · \(item.currentFile)")
                        .font(Typo.label(11.5)).foregroundStyle(colors.textTertiary).lineLimit(1)
                case .done:
                    Text("Installiert in \(item.targetDirectory)").font(Typo.label(12)).foregroundStyle(colors.success)
                case .failed(let message):
                    Text(message).font(Typo.label(12)).foregroundStyle(colors.danger)
                case .cancelled:
                    Text("Abgebrochen").font(Typo.label(12)).foregroundStyle(colors.textSecondary)
                }
            }
            Spacer()
            if item.state.isActive {
                ActionButton(title: "Abbrechen", destructive: true) { downloads.cancel(item.repo) }
            } else {
                Button { downloads.dismiss(item.repo) } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(colors.textTertiary)
            }
        }
        .padding(12)
        .cardSurface(colors, radius: 12)
    }
}

private struct HubRow: View {
    @EnvironmentObject private var library: ModelLibrary
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.panora) private var colors
    let summary: HFModelSummary

    var body: some View {
        let parsed = summary.parsed
        HStack(spacing: 14) {
            ModelCover(family: parsed.family, name: summary.name, corner: 8).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.name).font(Typo.body(14, .semibold)).foregroundStyle(colors.textPrimary).lineLimit(1)
                HStack(spacing: 6) {
                    Text(summary.author).font(Typo.label(12)).foregroundStyle(colors.textTertiary)
                    if let p = parsed.parametersB { Text("· \(Formatting.params(p))").font(Typo.label(12)).foregroundStyle(colors.textSecondary) }
                    if let a = parsed.activeParametersB { Text("· \(Formatting.params(a)) aktiv").font(Typo.label(12)).foregroundStyle(colors.textSecondary) }
                    if let b = parsed.bits { Text("· \(Formatting.bits(b))").font(Typo.label(12)).foregroundStyle(colors.textSecondary) }
                    Text("· \(Formatting.integer(summary.downloads)) Downloads").font(Typo.label(12)).foregroundStyle(colors.textTertiary)
                }
            }
            Spacer()
            LicenseBadges(license: summary.license)
            if library.isInstalled(repo: summary.id) {
                Badge(text: "Installiert", color: colors.success, systemImage: "checkmark")
            } else if let dl = downloads.item(summary.id), dl.state.isActive {
                MeterBar(fraction: dl.fraction).frame(width: 90)
            } else {
                ActionButton(title: "Laden", systemImage: "arrow.down.circle", disabled: !downloads.canDownload || summary.license.regionBlock != nil) {
                    downloads.start(repo: summary.id, name: ModelLibrary.prettyName(summary.name), family: parsed.family)
                }
            }
        }
        .padding(10)
        .cardSurface(colors, radius: 12)
    }
}
