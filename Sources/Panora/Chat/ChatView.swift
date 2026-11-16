import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PanoraCore

/// Chat: Verlauf mit sichtbarem Modell an jeder Antwort, Modellwechsel als Hinweis im Gespräch,
/// unten die schwebende Eingabe mit der Modell-Scheibe (wie der Player der Musik-App).
struct ChatView: View {
    @EnvironmentObject private var chat: ChatController
    @EnvironmentObject private var experts: ExpertService
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.panora) private var colors

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ChatHeader()
                        if chat.conversation.messages.isEmpty {
                            WelcomeView()
                        } else {
                            ForEach(chat.conversation.messages) { message in
                                MessageRow(message: message, isLast: message.id == chat.conversation.messages.last?.id)
                                    .id(message.id)
                            }
                        }
                        Color.clear.frame(height: 230).id("bottom")
                    }
                    .padding(.horizontal, Metrics.pageInset)
                    .padding(.top, Metrics.contentTop)
                    .frame(maxWidth: 980)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: chat.conversation.messages.last?.text) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: chat.conversation.messages.count) { _, _ in
                    withAnimation(Motion.medium) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: chat.conversation.id) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            EdgeFade(top: false, strength: 0.85).frame(height: 190).frame(maxHeight: .infinity, alignment: .bottom)
            VStack(spacing: 10) {
                if let notice = chat.notice {
                    NoticeBanner(text: notice, systemImage: "info.circle") { chat.notice = nil }
                }
                if let s = chat.pendingSuggestion, let suggestion = s.suggestion {
                    SuggestionBanner(text: s.suggestionReason ?? "Stattdessen \(suggestion.displayName) verwenden?",
                                     modelName: suggestion.displayName) { chat.acceptSuggestion() } dismiss: { chat.pendingSuggestion = nil }
                }
                ComposerPanel()
            }
            .frame(maxWidth: 1040)
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .sheet(item: $experts.draft) { draft in
            ExpertPreviewSheet(draft: draft) { chat.confirmExpert(draft) } cancel: { experts.draft = nil }
        }
    }
}

private struct ChatHeader: View {
    @EnvironmentObject private var chat: ChatController
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var chats: ChatStore
    @EnvironmentObject private var projects: ProjectStore
    @Environment(\.panora) private var colors

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(chat.conversation.messages.isEmpty ? "Neuer Chat" : chat.conversation.title)
                    .font(Typo.title(30)).foregroundStyle(colors.textPrimary).lineLimit(1)
                HStack(spacing: 8) {
                    let used = chat.conversation.modelsUsed
                    if !used.isEmpty {
                        Text(used.count == 1 ? "Modell: \(used[0])" : "\(used.count) Modelle: \(used.joined(separator: " → "))")
                            .font(Typo.label(12)).foregroundStyle(colors.textSecondary).lineLimit(1)
                    }
                    if let p = projects.project(chat.conversation.projectPath) {
                        Badge(text: p.name, color: colors.teal, systemImage: "folder.fill")
                    }
                }
            }
            Spacer()
            ToolbarCapsule {
                ToolbarIcon(systemName: "square.and.pencil", help: "Neuer Chat (⌘N)") { model.newChat() }
                ToolbarIcon(systemName: "clock.arrow.circlepath", help: "Verlauf") { model.open(.history) }
                ToolbarDivider()
                ToolbarIcon(systemName: "square.and.arrow.up", help: "Als Markdown exportieren") { export() }
                    .disabled(chat.conversation.messages.isEmpty)
            }
        }
        .padding(.bottom, 4)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = chat.conversation.title.replacingOccurrences(of: "/", with: "-") + ".md"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? chats.markdown(chat.conversation).write(to: url, atomically: true, encoding: .utf8)
    }
}

private struct WelcomeView: View {
    @EnvironmentObject private var chat: ChatController
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: ModelLibrary
    @EnvironmentObject private var hardware: HardwareMonitor
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var network: NetworkMonitor
    @Environment(\.panora) private var colors

    private struct Suggestion: Hashable {
        let icon: String
        let text: String
    }

    private let suggestions: [Suggestion] = [
        Suggestion(icon: "hammer", text: "Analysiere mein Android-Projekt und schlage eine Architektur vor"),
        Suggestion(icon: "chevron.left.forwardslash.chevron.right", text: "Implementiere eine Login-Ansicht in SwiftUI"),
        Suggestion(icon: "doc.text", text: "Fasse den folgenden Text in fünf Stichpunkten zusammen:"),
        Suggestion(icon: "envelope", text: "Schreibe eine freundliche E-Mail an einen Kunden"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 18) {
                Image(nsImage: BrandImage.icon)
                    .resizable().interpolation(.high).frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Was möchtest du erledigen?").font(Typo.title(26)).foregroundStyle(colors.textPrimary)
                    Text("Panora wählt selbst das passende lokale Modell und wechselt bei Bedarf – alles läuft auf deinem \(hardware.chipName.replacingOccurrences(of: "Apple ", with: "")) mit \(Formatting.bytes(hardware.totalMemory)) Unified Memory.")
                        .font(Typo.body(14)).foregroundStyle(colors.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                Badge(text: Formatting.count(library.availableModels.count, "Modell bereit", "Modelle bereit"), color: colors.accent, systemImage: "cube.fill")
                Badge(text: network.online ? "Funktioniert auch offline" : "Offline – lokal aktiv", color: colors.success, systemImage: "wifi.slash")
                Badge(text: "Kein Abo nötig", color: colors.teal, systemImage: "checkmark.seal.fill")
            }
            if library.models.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Noch kein lokales Modell installiert").font(Typo.body(16, .semibold)).foregroundStyle(colors.textPrimary)
                    Text("Empfehlung für den Start: Qwen3.6 35B A3B (ca. 20 GB, sehr gut für Coding und Alltag). Große Modelle speichert Panora bevorzugt auf deiner externen SSD.")
                        .font(Typo.body(13)).foregroundStyle(colors.textSecondary)
                    HStack(spacing: 10) {
                        if let starter = ModelCatalog.entries.first(where: { $0.spec.repo.contains("Qwen3.6-35B") }) {
                            ActionButton(title: "Qwen3.6 35B A3B laden", systemImage: "arrow.down.circle.fill", prominent: true,
                                         disabled: !downloads.canDownload) {
                                downloads.start(repo: starter.spec.repo, name: starter.spec.displayName, family: starter.spec.family, hint: starter.searchHint)
                                model.open(.discover)
                            }
                        }
                        ActionButton(title: "Alle Modelle entdecken", systemImage: "sparkles") { model.open(.discover) }
                    }
                }
                .padding(18)
                .cardSurface(colors, radius: 16, highlighted: true)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(suggestions, id: \.self) { item in
                    Button { chat.draft = item.text } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(colors.accent).frame(width: 22)
                            Text(item.text).font(Typo.body(13.5)).foregroundStyle(colors.textPrimary).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                        .cardSurface(colors, radius: 14)
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.98))
                }
            }
        }
        .padding(.top, 8)
    }
}

struct MessageRow: View {
    @EnvironmentObject private var chat: ChatController
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.panora) private var colors
    let message: ChatMessage
    var isLast = false
    @State private var showReasons = false
    @State private var showThinking = false

    var body: some View {
        switch message.role {
        case .user: userBubble
        case .assistant: assistantBlock
        case .event: eventRow
        case .expert: expertCard
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 120)
            Text(message.text)
                .font(Typo.body(14.5))
                .foregroundStyle(colors.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(colors.accentSoft))
        }
    }

    private var assistantBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ModelDisc(family: chat.conversation.messages.isEmpty ? nil : familyOf(message), active: isLast && chat.isGenerating, size: 22)
                Text(message.modelName ?? "Panora").font(Typo.label(13, .semibold)).foregroundStyle(colors.textPrimary)
                if let mode = message.routingMode {
                    Badge(text: mode == .auto ? "AUTO" : "MANUELL", color: mode == .auto ? colors.accent : colors.warning)
                }
                if let kind = message.taskKind { Text(kind.label).font(Typo.label(12)).foregroundStyle(colors.textTertiary) }
                if let tps = message.tokensPerSecond, tps > 0 {
                    Text("· \(Int(tps.rounded())) Token/s").font(Typo.label(12)).foregroundStyle(colors.textTertiary)
                }
                Spacer()
                if settings.showRoutingDetails, let reasons = message.routingReasons, !reasons.isEmpty {
                    Button(showReasons ? "Begründung ausblenden" : "Warum dieses Modell?") {
                        withAnimation(Motion.quick) { showReasons.toggle() }
                    }
                    .buttonStyle(.plain).font(Typo.label(12, .medium)).foregroundStyle(colors.accentText)
                }
            }
            if showReasons, let reasons = message.routingReasons {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(reasons, id: \.self) { r in
                        Text("• " + r).font(Typo.label(12)).foregroundStyle(colors.textSecondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors.surfaceSunken.opacity(0.8)))
            }
            if settings.showReasoning, let thinking = message.reasoning, !thinking.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(Motion.quick) { showThinking.toggle() }
                    } label: {
                        Label(isLast && chat.isGenerating && message.text.isEmpty ? "Denkt nach …" : "Gedankengang",
                              systemImage: showThinking ? "chevron.down" : "chevron.right")
                            .font(Typo.label(12, .semibold)).foregroundStyle(colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    if showThinking {
                        Text(thinking).font(Typo.body(12.5)).foregroundStyle(colors.textTertiary).textSelection(.enabled)
                            .padding(.leading, 14)
                    }
                }
            }
            if message.text.isEmpty && isLast && chat.isGenerating {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(statusText).font(Typo.label(13)).foregroundStyle(colors.textSecondary)
                }
            } else if message.isError {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(colors.warning)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message.text).font(Typo.body(14)).foregroundStyle(colors.textPrimary).textSelection(.enabled)
                        if isLast { ActionButton(title: "Erneut versuchen", systemImage: "arrow.clockwise") { chat.retryLast() } }
                    }
                }
                .padding(14)
                .cardSurface(colors, radius: 14)
            } else {
                MarkdownText(text: message.text)
            }
            if !message.text.isEmpty && !(isLast && chat.isGenerating) && !message.isError {
                HStack(spacing: 14) {
                    Button { copy(message.text) } label: { Label("Kopieren", systemImage: "doc.on.doc") }
                    if isLast { Button { chat.retryLast() } label: { Label("Neu erzeugen", systemImage: "arrow.clockwise") } }
                }
                .buttonStyle(.plain)
                .font(Typo.label(12))
                .foregroundStyle(colors.textTertiary)
            }
        }
        .padding(.trailing, 40)
    }

    private var statusText: String {
        if let d = chat.lastDecision, let m = d.chosen { return "\(m.displayName) bereitet die Antwort vor …" }
        return "Antwort wird vorbereitet …"
    }

    private var eventRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.swap").font(.system(size: 11, weight: .bold)).foregroundStyle(colors.accent)
                Text(message.text).font(Typo.label(12.5, .medium)).foregroundStyle(colors.textSecondary).multilineTextAlignment(.center)
                if let reasons = message.routingReasons, !reasons.isEmpty {
                    Button { withAnimation(Motion.quick) { showReasons.toggle() } } label: {
                        Image(systemName: showReasons ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain).foregroundStyle(colors.textTertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(colors.surfaceSunken.opacity(0.7)))
            .overlay(Capsule().strokeBorder(colors.hairline, lineWidth: 0.8))
            if showReasons, let reasons = message.routingReasons {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(reasons, id: \.self) { Text("• " + $0).font(Typo.label(12)).foregroundStyle(colors.textSecondary) }
                }
                .padding(12)
                .cardSurface(colors, radius: 12)
                .frame(maxWidth: 560)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var expertCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "cloud.fill").foregroundStyle(colors.teal)
                Text("Zweitmeinung · \(message.expertProvider ?? "extern")").font(Typo.label(13, .semibold)).foregroundStyle(colors.textPrimary)
                Badge(text: "Extern", color: colors.teal)
                Spacer()
            }
            if message.isError {
                Text(message.text).font(Typo.body(13.5)).foregroundStyle(colors.warning)
            } else {
                MarkdownText(text: message.text)
                HStack(spacing: 10) {
                    ActionButton(title: "Von Panora bewerten lassen", systemImage: "checkmark.bubble", disabled: chat.isGenerating) {
                        chat.evaluateExpert(message)
                    }
                    Text("Die Bewertung läuft wieder lokal.").font(Typo.label(12)).foregroundStyle(colors.textTertiary)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(colors.teal.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(colors.teal.opacity(0.35), lineWidth: 1))
        .padding(.trailing, 40)
    }

    private func familyOf(_ m: ChatMessage) -> String? {
        guard let id = m.modelID else { return nil }
        let parsed = ModelNameParser.parse(id.replacingOccurrences(of: "mlx:", with: "").replacingOccurrences(of: "ollama:", with: ""))
        return parsed.family
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

/// Schwebende Eingabe: Modell-Scheibe, Status, Textfeld, AUTO/Manuell, Projekt, Zweitmeinung, Senden.
struct ComposerPanel: View {
    @EnvironmentObject private var chat: ChatController
    @EnvironmentObject private var library: ModelLibrary
    @EnvironmentObject private var engine: InferenceCoordinator
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var projects: ProjectStore
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var experts: ExpertService
    @EnvironmentObject private var model: AppModel
    @Environment(\.panora) private var colors
    @FocusState private var focused: Bool

    var body: some View {
        let manual = chat.conversation.mode == .manual
        let pinned = library.model(chat.conversation.pinnedModelID)
        let current = library.model(chat.conversation.lastModelID)
        HStack(alignment: .center, spacing: 18) {
            ModelDisc(family: (manual ? pinned : current)?.spec.family ?? engine.loaded.last?.family,
                      active: chat.isGenerating, size: 96)
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text(statusTitle(manual: manual, pinned: pinned, current: current))
                        .font(Typo.body(15, .semibold)).foregroundStyle(colors.textPrimary).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(statusDetail).font(Typo.label(12)).foregroundStyle(colors.textTertiary).lineLimit(1)
                }
                TextField(library.availableModels.isEmpty ? "Zuerst ein Modell unter „Entdecken“ installieren …" : "Beschreibe deine Aufgabe …",
                          text: $chat.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Typo.body(15))
                    .lineLimit(1...8)
                    .focused($focused)
                    .onSubmit { chat.send() }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(colors.dark ? Color.white.opacity(0.07) : Color.black.opacity(0.045)))
                HStack(spacing: 8) {
                    ModeSwitch(mode: chat.conversation.mode) { chat.setMode($0) }
                    if manual {
                        Menu {
                            ForEach(library.models) { m in
                                Button {
                                    chat.pin(m.id)
                                } label: {
                                    Text(m.available ? "\(m.spec.displayName) · \(m.spec.backend.label)" : "\(m.spec.displayName) (nicht verfügbar)")
                                }
                                .disabled(!m.available)
                            }
                            Divider()
                            Toggle("Wechsel nach Rückfrage erlauben", isOn: Binding(get: { chat.conversation.allowSwitchInManual },
                                                                                   set: { chat.setAllowSwitch($0) }))
                        } label: {
                            Label(pinned?.spec.displayName ?? "Modell wählen", systemImage: "cube")
                                .font(Typo.label(12.5, .semibold))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    Menu {
                        ForEach(projects.projects) { p in
                            Button(p.name) { chat.attachProject(p.path) }
                        }
                        if !projects.projects.isEmpty { Divider() }
                        Button("Projekt hinzufügen …") {
                            Task { if let p = await projects.chooseAndAdd() { chat.attachProject(p.path) } }
                        }
                        if chat.conversation.projectPath != nil {
                            Button("Projekt lösen") { chat.attachProject(nil) }
                        }
                    } label: {
                        Label(projects.project(chat.conversation.projectPath)?.name ?? "Projekt", systemImage: "folder")
                            .font(Typo.label(12.5, .semibold))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Spacer(minLength: 6)
                    Menu {
                        ForEach(ExpertProvider.allCases) { p in
                            Button("Mit \(p.shortName) überprüfen") { chat.askExpert(p) }
                        }
                        Divider()
                        Text(expertMenuHint)
                    } label: {
                        Label("Zweitmeinung", systemImage: "cloud")
                            .font(Typo.label(12.5, .semibold))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(chat.conversation.messages.isEmpty || experts.sending != nil)
                    .help("Externe KI um Zweitmeinung bitten – nur auf Klick, mit Vorschau der Daten.")
                    if experts.sending != nil { ProgressView().controlSize(.small) }
                    SendButton(generating: chat.isGenerating, enabled: !chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                        if chat.isGenerating { chat.stop() } else { chat.send() }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .glassSurface(RoundedRectangle(cornerRadius: 32, style: .continuous), strong: true, elevated: true)
        .onAppear { focused = true }
    }

    private var expertMenuHint: String {
        if !settings.expertsEnabled { return "Ausgeschaltet – in den Einstellungen aktivieren" }
        if !network.online || settings.forceOffline { return "Offline – nicht verfügbar" }
        return "Kostenpflichtige API, separat abgerechnet"
    }

    private func statusTitle(manual: Bool, pinned: InstalledModel?, current: InstalledModel?) -> String {
        if engine.activity.isBusy { return engine.activity.label }
        if manual { return "Manuell · \(pinned?.spec.displayName ?? "kein Modell gewählt")" }
        if let d = chat.lastDecision, let m = d.chosen { return "Auto · \(m.displayName)" }
        if let c = current { return "Auto · zuletzt \(c.spec.displayName)" }
        return "Auto · Panora wählt das passende Modell"
    }

    private var statusDetail: String {
        var parts: [String] = []
        if let tps = engine.lastTokensPerSecond { parts.append("\(Int(tps.rounded())) Token/s") }
        if engine.loadedBytes > 0 { parts.append("\(Formatting.bytes(engine.loadedBytes)) geladen") }
        if parts.isEmpty { parts.append(Formatting.count(library.availableModels.count, "Modell lokal", "Modelle lokal")) }
        return parts.joined(separator: " · ")
    }
}

struct ModeSwitch: View {
    @Environment(\.panora) private var colors
    let mode: RoutingMode
    let select: (RoutingMode) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(RoutingMode.allCases, id: \.self) { m in
                Button { select(m) } label: {
                    Text(m == .auto ? "Auto" : "Manuell")
                        .font(Typo.label(12, .semibold))
                        .foregroundStyle(mode == m ? Color.white : colors.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(Capsule().fill(mode == m ? colors.accent : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(colors.dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)))
        .animation(Motion.quick, value: mode)
        .help("Auto: Panora wählt und wechselt das Modell selbst. Manuell: dein gewähltes Modell gilt für den ganzen Chat.")
    }
}

struct SendButton: View {
    @Environment(\.panora) private var colors
    let generating: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: generating ? "stop.fill" : "arrow.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(generating ? colors.danger : (enabled ? colors.accent : colors.textTertiary.opacity(0.5))))
        }
        .buttonStyle(PressScaleStyle(scale: 0.92))
        .disabled(!generating && !enabled)
        .keyboardShortcut(generating ? KeyEquivalent(".") : KeyEquivalent.return, modifiers: .command)
        .help(generating ? "Stoppen (⌘.)" : "Senden (⌘↩)")
    }
}

struct NoticeBanner: View {
    @Environment(\.panora) private var colors
    let text: String
    var systemImage: String = "info.circle"
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(colors.accent)
            Text(text).font(Typo.label(13)).foregroundStyle(colors.textPrimary)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                .buttonStyle(.plain).foregroundStyle(colors.textTertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .glassSurface(Capsule(), strong: true, elevated: true)
    }
}

struct SuggestionBanner: View {
    @Environment(\.panora) private var colors
    let text: String
    let modelName: String
    let accept: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.swap").foregroundStyle(colors.warning)
            Text(text).font(Typo.label(13)).foregroundStyle(colors.textPrimary)
            Spacer()
            ActionButton(title: "Zu \(modelName) wechseln", prominent: true, action: accept)
            ActionButton(title: "Behalten", action: dismiss)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous), strong: true, elevated: true)
    }
}

/// Vorschau vor dem Senden an einen externen Dienst – nichts verlässt den Mac ohne Bestätigung.
struct ExpertPreviewSheet: View {
    @Environment(\.panora) private var colors
    @Environment(\.colorScheme) private var scheme
    let draft: ExpertDraft
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        let c = PanoraColors(dark: scheme == .dark)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "cloud.fill").font(.system(size: 20)).foregroundStyle(c.teal)
                Text("Zweitmeinung von \(draft.provider.shortName) einholen").font(Typo.body(18, .bold))
            }
            Text("Der folgende Text verlässt deinen Mac und wird an \(draft.provider.company) (\(draft.provider.host)) gesendet. Modell: \(draft.model). Die Nutzung wird über dein API-Konto separat abgerechnet. Ohne deine Bestätigung wird nichts gesendet.")
                .font(Typo.body(13)).foregroundStyle(c.textSecondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(draft.brief)
                    .font(Typo.mono(12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 260, maxHeight: 380)
            .background(RoundedRectangle(cornerRadius: 10).fill(c.surfaceSunken))
            HStack {
                Text("ca. \(Formatting.integer(draft.tokens)) Tokens").font(Typo.label(12)).foregroundStyle(c.textTertiary)
                Spacer()
                Button("Abbrechen", action: cancel).keyboardShortcut(.cancelAction)
                Button("An \(draft.provider.shortName) senden", action: confirm).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 640)
    }
}
