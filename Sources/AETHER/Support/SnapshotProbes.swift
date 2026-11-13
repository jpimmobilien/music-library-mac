import SwiftUI
import AppKit
import AetherCore

// =============================================================================================
// Diagnose für den Build (`AETHER_SNAPSHOT_PROBE=1`): einzelne Bausteine getrennt im hellen und dunklen
// Erscheinungsbild zeichnen. Auf dem virtuellen Intel-Build-Rechner (Grafikgerät ohne Metal-Architektur) bricht
// SwiftUI beim Zeichnen mancher Inhalte mit einer Metal-Assertion ab – die Proben zeigen, welcher Baustein das auslöst.
// =============================================================================================

enum SnapshotProbe: String, CaseIterable {
    case empty, plainText, text, secondaryText, ambient, glassCard, solidCard, sidebar, hierarchicalSymbol, sparkline, ring, badge,
         controls, scroll, statusDot
}

struct ProbeHost: View {
    let probe: SnapshotProbe
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = AetherTheme.resolve(settings: settings, systemIsDark: colorScheme == .dark, reduceTransparency: false)
        content
            .padding(24)
            .frame(width: 420, height: 320)
            .background(theme.backgroundTop)
            .environment(\.aether, theme)
            .foregroundStyle(theme.textPrimary)
    }

    @ViewBuilder
    private var content: some View {
        switch probe {
        case .empty:
            Color.clear
        case .plainText:
            Text("Plain")
        case .text:
            Text("ORBIT 123 °C").font(Typo.metricLarge)
        case .secondaryText:
            Text("Secondary").foregroundStyle(.secondary)
        case .ambient:
            AmbientBackground()
        case .glassCard:
            Text("Glass").padding(30).glassCard()
        case .solidCard:
            Text("Solid").padding(30).glassSurface(RoundedRectangle(cornerRadius: 20), elevated: true)
        case .sidebar:
            SidebarView().frame(width: 232)
        case .hierarchicalSymbol:
            Image(systemName: "cpu").symbolRenderingMode(.hierarchical).font(.system(size: 40))
        case .sparkline:
            Sparkline(values: [0.1, 0.4, 0.2, 0.8, 0.5], color: .blue, capacity: 5).frame(height: 60)
        case .ring:
            MetricRing(segments: [(0.4, .blue), (0.2, .orange)]) { Text("60 %") }
        case .badge:
            UnavailableValue(reason: .notPresent, source: .powerSources)
        case .controls:
            VStack {
                Toggle("Toggle", isOn: .constant(true)).toggleStyle(.switch)
                Picker("", selection: .constant(1)) { Text("A").tag(1); Text("B").tag(2) }.pickerStyle(.segmented)
                Button("Button") {}.buttonStyle(CapsuleButtonStyle(prominent: true))
            }
        case .scroll:
            ScrollView { VStack { ForEach(0..<30) { Text("Row \($0)") } } }
        case .statusDot:
            StatusDot(color: .green)
        }
    }
}
