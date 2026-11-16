import SwiftUI
import AppKit
import PanoraCore

/// Hauptfenster im Aufbau der Musik-App: schwebende Glas-Navigation oben, Inhalte laufen weich darunter,
/// schwebende Leiste unten (im Chat die Eingabe mit Modell-Scheibe, sonst die Modell-Leiste).
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var scheme
    var embedded = false

    var body: some View {
        let colors = PanoraColors(dark: scheme == .dark)
        ZStack(alignment: .top) {
            AmbientBackground()
            SectionHost()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            EdgeFade(top: true, strength: 0.9)
                .frame(height: Metrics.contentTop + 2)
                .frame(maxWidth: .infinity, alignment: .top)
            HStack(alignment: .top) {
                Spacer(minLength: 90)
                NavBar()
                Spacer(minLength: 12)
            }
            .padding(.top, Metrics.topPadding)
            HStack {
                Spacer()
                StatusPill()
            }
            .padding(.top, Metrics.topPadding + 10)
            .padding(.trailing, 18)
            if model.section != .chat {
                VStack {
                    Spacer()
                    EngineBarHost()
                        .padding(.horizontal, 18)
                        .padding(.bottom, 14)
                }
            }
        }
        .environment(\.panora, colors)
        .environment(\.glassEnabled, settings.glassEffects)
        .environmentObject(model.chat)
        .environmentObject(model.library)
        .environmentObject(model.engine)
        .environmentObject(model.hardware)
        .environmentObject(model.storage)
        .environmentObject(model.network)
        .environmentObject(model.downloads)
        .environmentObject(model.hub)
        .environmentObject(model.chats)
        .environmentObject(model.projects)
        .environmentObject(model.experts)
        .ignoresSafeArea(.container, edges: .top)
        .background(embedded ? nil : WindowConfigurator())
        .preferredColorScheme(settings.appearance == .system ? nil : (settings.appearance == .dark ? .dark : .light))
    }
}

struct SectionHost: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            switch model.section {
            case .chat: ChatView()
            case .history: HistoryView()
            case .models: ModelsView()
            case .discover: DiscoverView()
            case .projects: ProjectsView()
            case .hardware: HardwareView()
            case .storage: StorageView()
            case .settings: SettingsView()
            }
        }
        .id(model.section)
        .transition(.opacity.combined(with: .offset(y: 6)))
        .animation(Motion.medium, value: model.section)
    }
}

struct NavBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.panora) private var colors

    static let dividerGap: CGFloat = 11
    static var width: CGFloat {
        CGFloat(AppSection.allCases.count) * Metrics.navItemWidth + dividerGap + 12
    }

    var body: some View {
        let primary = AppSection.primary
        let system = AppSection.system
        let lensX: CGFloat = {
            if let i = primary.firstIndex(of: model.section) { return 6 + CGFloat(i) * Metrics.navItemWidth }
            let j = system.firstIndex(of: model.section) ?? 0
            return 6 + CGFloat(primary.count + j) * Metrics.navItemWidth + Self.dividerGap
        }()
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(colors.accentSoft)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [colors.glassEdgeLight.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 0.7))
                .frame(width: Metrics.navItemWidth, height: Metrics.navHeight - 10)
                .offset(x: lensX)
                .animation(Motion.lens, value: lensX)
            HStack(spacing: 0) {
                ForEach(primary) { s in
                    NavItem(section: s, selected: model.section == s) { model.open(s) }
                }
                Capsule().fill(colors.textPrimary.opacity(0.14)).frame(width: 1, height: 26).frame(width: Self.dividerGap)
                ForEach(system) { s in
                    NavItem(section: s, selected: model.section == s) { model.open(s) }
                }
            }
            .padding(.horizontal, 6)
        }
        .frame(width: Self.width, height: Metrics.navHeight)
        .glassSurface(RoundedRectangle(cornerRadius: 28, style: .continuous), elevated: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bereiche")
    }
}

private struct NavItem: View {
    @Environment(\.panora) private var colors
    let section: AppSection
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let fg = selected ? colors.accentText : colors.textPrimary.opacity(hover ? 0.92 : 0.72)
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: section.icon(selected: selected))
                    .font(.system(size: 17, weight: selected ? .semibold : .regular))
                    .frame(height: 20)
                Text(section.label)
                    .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(fg)
            .frame(width: Metrics.navItemWidth, height: Metrics.navHeight - 10)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.94))
        .onHover { hover = $0 }
        .help("\(section.label) (⌘\(String(section.shortcut.character)))")
        .accessibilityLabel(section.label)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Status oben rechts: lokal/offline, Cloud aus.
struct StatusPill: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.panora) private var colors

    var body: some View {
        let offline = !network.online || settings.forceOffline
        HStack(spacing: 7) {
            Circle().fill(offline ? colors.warning : colors.success).frame(width: 7, height: 7)
            Text(offline ? "Offline · lokal" : "Lokal").font(Typo.label(12, .semibold)).foregroundStyle(colors.textPrimary)
            Text("·").foregroundStyle(colors.textTertiary)
            Image(systemName: settings.expertsEnabled ? "cloud" : "icloud.slash")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .glassSurface(Capsule())
        .help(offline ? "Keine Internetverbindung – alle lokalen Funktionen arbeiten weiter. Cloud-Funktionen sind nicht verfügbar."
                      : (settings.expertsEnabled ? "Alles läuft lokal. Externe Experten nur auf ausdrücklichen Klick."
                                                 : "Alles läuft lokal. Externe Experten sind ausgeschaltet."))
    }
}

/// Modell-Leiste unten (außerhalb des Chats): arbeitendes Modell, Speicher, Downloads.
struct EngineBarHost: View {
    @EnvironmentObject private var engine: InferenceCoordinator
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var hardware: HardwareMonitor
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var model: AppModel
    @Environment(\.panora) private var colors

    var body: some View {
        let active = downloads.items.first { $0.state.isActive }
        if !engine.loaded.isEmpty || engine.activity.isBusy || active != nil {
            HStack(spacing: 16) {
                ModelDisc(family: engine.loaded.last?.family, active: engine.activity.isBusy, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(engine.activity.isBusy ? engine.activity.label : (engine.loaded.last.map { "\($0.name) ist geladen" } ?? "Download läuft"))
                        .font(Typo.body(14, .semibold)).foregroundStyle(colors.textPrimary).lineLimit(1)
                    let budget = Double(hardware.totalMemory) * settings.modelBudgetFraction
                    Text("\(Formatting.bytes(engine.loadedBytes)) von \(Formatting.bytes(Int64(budget))) Modellbudget belegt")
                        .font(Typo.label(12)).foregroundStyle(colors.textSecondary)
                }
                if let d = active {
                    Divider().frame(height: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Download: \(d.name)").font(Typo.label(12, .semibold)).foregroundStyle(colors.textPrimary).lineLimit(1)
                        MeterBar(fraction: d.fraction).frame(width: 180)
                    }
                }
                Spacer()
                if !engine.loaded.isEmpty {
                    ActionButton(title: "Entladen", systemImage: "eject") { Task { await engine.unloadAll() } }
                }
                ActionButton(title: "Zum Chat", systemImage: "bubble.left.and.text.bubble.right", prominent: true) { model.open(.chat) }
            }
            .padding(.horizontal, 18)
            .frame(height: 68)
            .frame(maxWidth: 1000)
            .glassSurface(RoundedRectangle(cornerRadius: 26, style: .continuous), strong: true, elevated: true)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
