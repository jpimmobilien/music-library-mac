import SwiftUI
import AppKit
import AetherCore

/// Fenster: Atmosphäre, schwebende Glas-Seitenleiste, Inhalt bis an den Rand.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.openWindow) private var openWindow
    /// Für Fotos im Build: feste Fenstergröße ohne Fensterkonfiguration.
    var embedded = false

    var body: some View {
        let theme = AetherTheme.resolve(settings: settings, systemIsDark: colorScheme == .dark,
                                        reduceTransparency: reduceTransparency && !model.launchMode.isSnapshot)
        ZStack(alignment: .topLeading) {
            AmbientBackground()
            HStack(spacing: 0) {
                if model.sidebarVisible {
                    SidebarView()
                        .frame(width: Metrics.sidebarWidth)
                        .padding(Metrics.sidebarInset)
                        .padding(.trailing, -Metrics.sidebarInset / 2)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                ContentArea()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aetherAnimation(Motion.spring, value: model.sidebarVisible)
        }
        .overlay(alignment: .bottomTrailing) {
            if settings.diagnosticsEnabled && !embedded {
                DiagnosticsHUD(diagnostics: model.engine.diagnostics)
                    .padding(14)
            }
        }
        .frame(minWidth: Metrics.minWindow.width, minHeight: Metrics.minWindow.height)
        .background {
            if !embedded {
                WindowConfigurator { visible in model.setWindowVisible(visible) }
            }
        }
        .environment(\.aether, theme)
        .tint(theme.accent)
        .foregroundStyle(theme.textPrimary)
        .animation(theme.motion == .off ? nil : .easeInOut(duration: 0.25), value: settings.theme)
        .onAppear {
            if !embedded {
                let action = openWindow
                model.openWindowHandler = { id in action(id: id) }
            }
        }
        .onDisappear {
            // Fenster geschlossen (z. B. bei Menüleisten-Anzeige): nicht mehr im vollen Takt messen
            if !embedded { model.setWindowVisible(false) }
        }
    }
}

/// Inhaltsbereich mit weichem Übergang beim Bereichswechsel.
private struct ContentArea: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.aether) private var theme

    var body: some View {
        ZStack {
            page(for: model.selection)
                .id(model.selection)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
        }
        .aetherAnimation(Motion.easeOut(0.3), value: model.selection)
        .overlay(alignment: .top) {
            // Oberer Rand dient als Titelleiste zum Verschieben des Fensters
            WindowDragArea().frame(height: 22)
        }
    }

    @ViewBuilder
    private func page(for section: AppSection) -> some View {
        switch section {
        case .overview: OverviewView()
        case .settings: SettingsView()
        case .activity: ActivityView(store: model.engine.processes)
        case .cpuGPU: CPUGPUView()
        case .memory: MemoryView()
        case .thermal: ThermalView()
        case .battery: BatteryView()
        case .hardware: HardwareView()
        case .storage: StorageView()
        case .network: NetworkView()
        case .files: FilesView()
        }
    }
}

/// Kopf jeder Seite: großer Titel, Untertitel, Werkzeuge rechts in einer Glaskapsel.
struct PageHeader<Tools: View>: View {
    @Environment(\.aether) private var theme
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var tools: () -> Tools

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typo.pageTitle)
                    .foregroundStyle(theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Typo.pageSubtitle)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Spacing.l)
            tools()
        }
        .padding(.top, Metrics.headerTop)
    }
}

extension PageHeader where Tools == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}
