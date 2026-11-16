import SwiftUI
import AppKit
import PanoraCore

// MARK: - Projekte

struct ProjectsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var projects: ProjectStore
    @Environment(\.panora) private var colors
    @State private var search = ""

    var body: some View {
        let list = projects.projects.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.path.localizedCaseInsensitiveContains(search) }
        PageScaffold(title: "Projekte", subtitle: "\(Formatting.count(list.count, "Projekt", "Projekte")) · nur lesend analysiert, nichts wird verändert",
                     search: $search, searchPrompt: "Projekt oder Pfad", bottomInset: 120) {
            ToolbarCapsule {
                ToolbarIcon(systemName: "plus", label: "Projekt", help: "Ordner hinzufügen") {
                    Task { _ = await projects.chooseAndAdd() }
                }
            }
        } content: {
            if let scanning = projects.scanning {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Lese \(scanning) …").font(Typo.label(12.5)).foregroundStyle(colors.textSecondary) }
                    .padding(.bottom, 12)
            }
            if list.isEmpty {
                EmptyStateView(systemImage: "folder.badge.plus", title: "Noch keine Projekte",
                               text: "Füge einen Projektordner hinzu (z. B. deine Android- oder macOS-App). Panora liest Struktur, Build-Dateien und angefragte Dateien als Kontext – offline.",
                               actionTitle: "Projekt hinzufügen") { Task { _ = await projects.chooseAndAdd() } }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 360, maximum: 520), spacing: 20)], alignment: .leading, spacing: 20) {
                ForEach(list) { p in ProjectCard(project: p) }
            }
            if !list.isEmpty {
                Text("Geplant: Agenten mit Dateibearbeitung, Builds und Tests (Gradle, xcodebuild) – jeder Schreibzugriff wird vorher angezeigt und bestätigt.")
                    .font(Typo.label(12)).foregroundStyle(colors.textTertiary).padding(.top, 18)
            }
        }
    }
}

private struct ProjectCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var projects: ProjectStore
    @Environment(\.panora) private var colors
    let project: ProjectSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: project.kind.contains("Android") ? "apps.iphone" : (project.kind.contains("Swift") || project.kind.contains("Xcode") ? "swift" : "folder.fill"))
                    .font(.system(size: 22)).foregroundStyle(colors.accent).frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name).font(Typo.body(16, .semibold)).foregroundStyle(colors.textPrimary)
                    Text(project.kind).font(Typo.label(12.5)).foregroundStyle(colors.textSecondary)
                }
                Spacer()
                Text("\(Formatting.integer(project.fileCount)) Dateien").font(Typo.label(12)).foregroundStyle(colors.textTertiary)
            }
            let top = project.languages.prefix(5)
            let total = max(1, top.reduce(0) { $0 + $1.files })
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(top.enumerated()), id: \.offset) { i, lang in
                        Rectangle().fill(colors.family(["Qwen", "Gemma", "Mistral", "DeepSeek", "gpt-oss"][i % 5])[0])
                            .frame(width: max(4, geo.size.width * CGFloat(lang.files) / CGFloat(total) - 2))
                    }
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
            Text(top.map { "\($0.name) \($0.files)" }.joined(separator: " · ")).font(Typo.label(12)).foregroundStyle(colors.textSecondary)
            Text(project.path).font(Typo.label(11.5)).foregroundStyle(colors.textTertiary).lineLimit(1).truncationMode(.middle)
            HStack(spacing: 8) {
                ActionButton(title: "Im Chat verwenden", systemImage: "bubble.left.and.text.bubble.right", prominent: true) {
                    model.chat.attachProject(project.path)
                    model.open(.chat)
                }
                ActionButton(title: "Neu einlesen", systemImage: "arrow.clockwise") { Task { await projects.rescan(project.path) } }
                ActionButton(title: "Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.path)])
                }
                Spacer()
                Button { projects.remove(project.path) } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(colors.textTertiary).help("Aus der Liste entfernen (der Ordner bleibt)")
            }
        }
        .padding(18)
        .cardSurface(colors, radius: 16)
    }
}

// MARK: - Hardware

struct HardwareView: View {
    @EnvironmentObject private var hardware: HardwareMonitor
    @EnvironmentObject private var engine: InferenceCoordinator
    @EnvironmentObject private var library: ModelLibrary
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var chat: ChatController
    @Environment(\.panora) private var colors

    var body: some View {
        let budget = Int64(Double(hardware.totalMemory) * settings.modelBudgetFraction)
        PageScaffold(title: "Hardware", subtitle: "\(hardware.chipName) · \(Formatting.bytes(hardware.totalMemory)) Unified Memory · \(hardware.coreCount) Kerne",
                     bottomInset: 120) {
            ToolbarCapsule {
                ToolbarIcon(systemName: "eject", label: "Alle entladen", help: "Alle Modelle aus dem Speicher entfernen") {
                    Task { await engine.unloadAll() }
                }
            }
        } content: {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 18)], alignment: .leading, spacing: 18) {
                PanelCard(title: "Arbeitsspeicher", systemImage: "memorychip", trailing: "live") {
                    let used = hardware.totalMemory - hardware.availableMemory
                    InfoRow(label: "Belegt", value: "\(Formatting.bytes(used)) von \(Formatting.bytes(hardware.totalMemory))")
                    MeterBar(fraction: Double(used) / Double(max(hardware.totalMemory, 1)), color: colors.teal, height: 8)
                    InfoRow(label: "Sofort verfügbar", value: Formatting.bytes(hardware.availableMemory))
                    InfoRow(label: "Modellbudget (\(Formatting.percent(settings.modelBudgetFraction)))", value: Formatting.bytes(budget))
                    MeterBar(fraction: Double(engine.loadedBytes) / Double(max(budget, 1)), height: 8)
                    InfoRow(label: "Durch Modelle belegt", value: Formatting.bytes(engine.loadedBytes))
                }
                PanelCard(title: "Auslastung", systemImage: "waveform.path.ecg") {
                    Sparkline(values: hardware.cpuHistory, color: colors.accent, label: "CPU \(Formatting.percent(hardware.cpuLoad))")
                    Sparkline(values: hardware.gpuHistory, color: colors.teal,
                              label: hardware.gpuLoad.map { "GPU \(Formatting.percent($0))" } ?? "GPU – keine Messwerte")
                    Sparkline(values: hardware.memoryHistory, color: colors.warning, label: "Speicherdruck")
                }
                PanelCard(title: "Geladene Modelle", systemImage: "cube.fill", trailing: engine.activity.label) {
                    if engine.loaded.isEmpty {
                        Text("Kein Modell geladen. Panora lädt das passende Modell bei der nächsten Anfrage und entlädt nach \(settings.idleUnloadMinutes) Minuten Leerlauf.")
                            .font(Typo.label(12.5)).foregroundStyle(colors.textSecondary)
                    }
                    ForEach(engine.loaded) { info in
                        HStack(spacing: 10) {
                            ModelDisc(family: info.family, active: engine.activity == .generating(info.name), size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(info.name).font(Typo.body(13.5, .semibold)).foregroundStyle(colors.textPrimary)
                                Text("\(info.backend.label) · \(Formatting.bytes(info.bytes)) · geladen in \(Formatting.duration(info.loadSeconds))")
                                    .font(Typo.label(12)).foregroundStyle(colors.textSecondary)
                            }
                            Spacer()
                            ActionButton(title: "Entladen") { Task { await engine.unload(info.id) } }
                        }
                    }
                }
                PanelCard(title: "Rechenwerke und Verbindung", systemImage: "gearshape.2") {
                    InfoRow(label: "MLX (Apple Silicon)", value: hardware.isAppleSilicon ? "verfügbar · \(library.mlxModels.count) Modelle" : "nicht verfügbar (Intel-Mac)",
                            valueColor: hardware.isAppleSilicon ? colors.success : colors.danger)
                    InfoRow(label: "Ollama", value: !settings.ollamaEnabled ? "ausgeschaltet" : (library.ollamaRunning ? "läuft · \(settings.ollamaURL)" : "nicht gefunden"),
                            valueColor: library.ollamaRunning ? colors.success : colors.textSecondary)
                    InfoRow(label: "Speicherbandbreite", value: "ca. \(Int(hardware.memoryBandwidthGBs)) GB/s (Herstellerangabe/Schätzung)")
                    InfoRow(label: "Internet", value: network.online ? (settings.forceOffline ? "verbunden, Offline-Modus erzwungen" : "verbunden") : "offline – lokale Funktionen aktiv",
                            valueColor: network.online && !settings.forceOffline ? colors.textPrimary : colors.warning)
                    InfoRow(label: "Cloud", value: settings.expertsEnabled ? "nur auf Klick (Zweitmeinung)" : "aus")
                }
            }
            if let decision = chat.lastDecision {
                SectionHeader(title: "Letzte AUTO-Entscheidung", count: decision.task.label).padding(.top, 18)
                PanelCard(title: decision.summary, systemImage: "arrow.triangle.branch") {
                    ForEach(decision.reasons, id: \.self) { Text("• " + $0).font(Typo.label(12.5)).foregroundStyle(colors.textSecondary) }
                    Divider().padding(.vertical, 4)
                    HStack {
                        Text("Modell").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Qualität").frame(width: 70, alignment: .trailing)
                        Text("Tempo").frame(width: 90, alignment: .trailing)
                        Text("Punkte").frame(width: 70, alignment: .trailing)
                    }
                    .font(Typo.label(11.5, .semibold)).foregroundStyle(colors.textTertiary)
                    ForEach(decision.scores.sorted { ($0.excluded == nil ? 0 : 1, -$0.total) < ($1.excluded == nil ? 0 : 1, -$1.total) }) { s in
                        HStack {
                            Text(s.name).font(Typo.label(12.5, s.id == decision.chosen?.id ? .bold : .regular))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let excluded = s.excluded {
                                Text(excluded).font(Typo.label(11.5)).foregroundStyle(colors.warning).lineLimit(1)
                            } else {
                                Text(Formatting.decimal(s.quality, digits: 1)).frame(width: 70, alignment: .trailing)
                                Text("\(Int(s.tokensPerSecond.rounded())) T/s").frame(width: 90, alignment: .trailing)
                                Text(Formatting.decimal(s.total, digits: 2)).frame(width: 70, alignment: .trailing)
                            }
                        }
                        .font(Typo.label(12.5))
                        .foregroundStyle(colors.textPrimary)
                    }
                }
            }
        }
    }
}

struct Sparkline: View {
    @Environment(\.panora) private var colors
    let values: [Double]
    let color: Color
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Typo.label(12, .semibold)).foregroundStyle(colors.textSecondary)
            GeometryReader { geo in
                Path { p in
                    guard values.count > 1 else { return }
                    let step = geo.size.width / CGFloat(max(values.count - 1, 1))
                    for (i, v) in values.enumerated() {
                        let pt = CGPoint(x: CGFloat(i) * step, y: geo.size.height * (1 - CGFloat(min(1, max(0, v)))))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 6).fill(colors.surfaceSunken.opacity(0.6)))
        }
    }
}

// MARK: - Speicher

struct StorageView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var storage: StorageMonitor
    @EnvironmentObject private var library: ModelLibrary
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.panora) private var colors

    var body: some View {
        PageScaffold(title: "Speicher", subtitle: "\(Formatting.count(storage.volumes.count, "Laufwerk", "Laufwerke")) · \(Formatting.count(settings.modelDirectories.count, "Modellordner", "Modellordner"))",
                     bottomInset: 120) {
            ToolbarCapsule {
                ToolbarIcon(systemName: "folder.badge.plus", label: "Ordner", help: "Modellordner hinzufügen") { addFolder() }
                ToolbarIcon(systemName: "arrow.clockwise", help: "Aktualisieren") {
                    storage.refresh()
                    Task { await library.refresh() }
                }
            }
        } content: {
            ForEach(library.missingDirectories, id: \.self) { dir in
                WarningCard(title: "Laufwerk „\(ModelLibrary.volumeName(of: dir))“ fehlt",
                            text: "\(library.models.filter { $0.directory == dir }.count) Modelle sind nicht verfügbar. Panora erkennt das Laufwerk automatisch wieder, sobald es angeschlossen ist.")
                    .padding(.bottom, 12)
            }
            SectionHeader(title: "Laufwerke", count: Formatting.count(storage.volumes.count, "verbunden", "verbunden"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 18)], alignment: .leading, spacing: 18) {
                ForEach(storage.volumes) { v in VolumeCard(volume: v) }
            }
            .padding(.bottom, 20)
            SectionHeader(title: "Modellordner", count: "Ziel für Downloads markiert")
            VStack(spacing: 8) {
                ForEach(settings.modelDirectories, id: \.self) { dir in
                    let exists = FileManager.default.fileExists(atPath: dir)
                    let models = library.models.filter { $0.directory == dir }
                    HStack(spacing: 12) {
                        Image(systemName: dir == settings.downloadDirectory ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(dir == settings.downloadDirectory ? colors.accent : colors.textTertiary)
                            .onTapGesture { settings.downloadDirectory = dir }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dir).font(Typo.body(13.5, .semibold)).foregroundStyle(colors.textPrimary).lineLimit(1).truncationMode(.middle)
                            Text(exists ? "\(Formatting.count(models.count, "Modell", "Modelle")) · \(Formatting.bytes(models.reduce(0) { $0 + $1.spec.sizeBytes }))"
                                        : "Nicht erreichbar – Laufwerk getrennt?")
                                .font(Typo.label(12)).foregroundStyle(exists ? colors.textSecondary : colors.warning)
                        }
                        Spacer()
                        if dir != settings.downloadDirectory {
                            ActionButton(title: "Als Ziel") { settings.downloadDirectory = dir }
                        }
                        if exists {
                            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: dir)]) } label: { Image(systemName: "folder") }
                                .buttonStyle(.plain).foregroundStyle(colors.textSecondary)
                        }
                        if settings.modelDirectories.count > 1 {
                            Button {
                                settings.modelDirectories.removeAll { $0 == dir }
                                if settings.downloadDirectory == dir { settings.downloadDirectory = settings.modelDirectories.first ?? AppSettings.defaultModelDirectory }
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain).foregroundStyle(colors.textTertiary).help("Ordner aus der Liste entfernen (Dateien bleiben)")
                        }
                    }
                    .padding(12)
                    .cardSurface(colors, radius: 12, highlighted: dir == settings.downloadDirectory)
                }
            }
            Text("Tipp: Ein Laufwerk „USB-C“ sagt noch nichts über das Tempo – USB 3.2 Gen 2 schafft etwa 1 GB/s, Thunderbolt deutlich mehr. Die Messung zeigt den echten Wert; Panora nutzt ihn für die Ladezeiten im AUTO MODE.")
                .font(Typo.label(12)).foregroundStyle(colors.textTertiary).padding(.top, 14)
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Als Modellordner verwenden"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.useDirectory(url.path, asDownloadTarget: false)
    }
}

private struct VolumeCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var storage: StorageMonitor
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.panora) private var colors
    let volume: VolumeInfo

    var body: some View {
        PanelCard(title: volume.name, systemImage: volume.isInternal ? "internaldrive" : "externaldrive", trailing: volume.kindLabel) {
            MeterBar(fraction: Double(volume.used) / Double(max(volume.total, 1)), color: volume.isInternal ? colors.textSecondary : colors.accent, height: 8)
            InfoRow(label: "Frei", value: "\(Formatting.bytes(volume.available)) von \(Formatting.bytes(volume.total))")
            if let media = volume.media { InfoRow(label: "Gerät", value: media) }
            if let bus = volume.bus {
                InfoRow(label: "Anschluss", value: bus + (volume.solidState == true ? " · SSD" : ""))
            }
            if let r = storage.speedResults[volume.path] {
                InfoRow(label: "Gemessen", value: "Lesen \(Int(r.readMBs)) MB/s · Schreiben \(Int(r.writeMBs)) MB/s", valueColor: colors.accentText)
            }
            HStack(spacing: 8) {
                ActionButton(title: storage.speedTestRunning == volume.path ? "Misst …" : "Tempo messen", systemImage: "speedometer",
                             disabled: storage.speedTestRunning != nil) { storage.runSpeedTest(on: volume) }
                if !volume.isInternal {
                    let dir = (volume.path as NSString).appendingPathComponent("Panora/Modelle")
                    if settings.downloadDirectory != dir {
                        ActionButton(title: "Für Modelle verwenden", systemImage: "arrow.down.to.line", prominent: true) {
                            model.useDirectory(dir, asDownloadTarget: true)
                        }
                    } else {
                        Badge(text: "Ziel für Modelle", color: colors.success, systemImage: "checkmark")
                    }
                }
            }
        }
        .onChange(of: storage.speedResults[volume.path]?.readMBs) { _, value in
            if let value { settings.diskReadGBs[volume.name] = value / 1000 }
        }
    }
}
