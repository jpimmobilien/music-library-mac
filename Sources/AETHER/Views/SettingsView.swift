import SwiftUI
import AppKit
import AetherCore

/// Einstellungen: Darstellung, Messung, Übersicht, Sprache, Datenschutz, Info.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var model: AppModel
    @Environment(\.aether) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: tr("Settings"), subtitle: tr("Everything is stored on this Mac only."))
                appearance
                monitoring
                windows
                HistorySettingsPanel(store: model.engine.history)
                language
                privacy
                AboutPanel(system: model.engine.system)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.gutter)
            .frame(maxWidth: 980, alignment: .leading)
        }
    }

    // MARK: Darstellung

    private var appearance: some View {
        SettingsPanel(title: tr("Appearance"), symbol: "paintpalette") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132, maximum: 180), spacing: Spacing.m)], spacing: Spacing.m) {
                ForEach(ThemeID.allCases) { id in
                    ThemeSwatch(id: id, selected: settings.theme == id) { settings.theme = id }
                }
            }
            SettingsRow(title: tr("Accent color")) {
                HStack(spacing: 10) {
                    ForEach(AccentChoice.allCases) { accent in
                        AccentDot(accent: accent, selected: settings.accent == accent, dark: theme.isDark) {
                            settings.accent = accent
                        }
                    }
                }
            }
            SettingsRow(title: tr("Glass intensity"), detail: glassDetail) {
                HStack(spacing: Spacing.s) {
                    Image(systemName: "square.fill").font(.system(size: 10)).foregroundStyle(theme.textTertiary)
                    Slider(value: $settings.glassIntensity, in: 0...1)
                        .frame(width: 200)
                        .disabled(!ThemeCatalog.spec(settings.theme).usesGlass)
                    Image(systemName: "square.on.square.dashed").font(.system(size: 11)).foregroundStyle(theme.textTertiary)
                    Text(fmt.percent(settings.glassIntensity)).font(Typo.callout).monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
            SettingsRow(title: tr("Animations"), detail: tr("The system setting “Reduce motion” always takes precedence.")) {
                Picker("", selection: $settings.motion) {
                    Text(tr("Full")).tag(MotionLevel.full)
                    Text(tr("Reduced")).tag(MotionLevel.reduced)
                    Text(tr("Off")).tag(MotionLevel.off)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
            }
            SettingsRow(title: tr("Effects"), detail: effectDetail) {
                Picker("", selection: $settings.effectProfile) {
                    Text(tr("Minimal")).tag(EffectProfile.minimal)
                    Text(tr("Balanced")).tag(EffectProfile.balanced)
                    Text(tr("Immersive")).tag(EffectProfile.immersive)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
            }
            SettingsRow(title: tr("Information density")) {
                Picker("", selection: $settings.density) {
                    Text(tr("Compact")).tag(Density.compact)
                    Text(tr("Standard")).tag(Density.standard)
                    Text(tr("Detailed")).tag(Density.detailed)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
            }
            HStack {
                Spacer()
                Button(tr("Reset appearance")) { settings.resetAppearance() }
                    .buttonStyle(CapsuleButtonStyle())
            }
        }
    }

    private var effectDetail: String {
        switch settings.effectProfile {
        case .minimal:
            return tr("No light effects or decorative motion – the most economical setting. Real activity (data flow, charging) is still shown.")
        case .balanced:
            return tr("Light fields, glass reflection under the pointer and spatial transitions. Nothing moves permanently.")
        case .immersive:
            return tr("Additionally a very slow drift of the light fields, magnetic hover and rolling numbers. Uses slightly more energy.")
        }
    }

    private var glassDetail: String? {
        if !ThemeCatalog.spec(settings.theme).usesGlass { return tr("This theme uses solid surfaces.") }
        if reduceTransparency && !model.launchMode.isSnapshot {
            return tr("“Reduce transparency” is on in System Settings – surfaces stay solid.")
        }
        return nil
    }

    // MARK: Messung

    private var monitoring: some View {
        SettingsPanel(title: tr("Monitoring"), symbol: "waveform.path.ecg") {
            SettingsRow(title: tr("Update interval"),
                        detail: tr("Shorter intervals react faster but cost a little more energy.")) {
                Picker("", selection: $settings.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(intervalName(interval)).tag(interval)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
            }
            SettingsRow(title: tr("Low-impact mode"),
                        detail: tr("Measures at most every 5 seconds and skips everything that isn’t visible.")) {
                Toggle("", isOn: $settings.lowImpact).toggleStyle(.switch).labelsHidden()
            }
            SettingsRow(title: tr("Temperature sensors and fans (SMC)"),
                        detail: tr("Reads temperatures and fan speeds from the System Management Controller via public IOKit functions – read-only, no administrator rights. Apple doesn’t document the sensor keys.")) {
                Toggle("", isOn: $settings.smcEnabled).toggleStyle(.switch).labelsHidden()
            }
            SettingsRow(title: tr("When the window isn’t visible"), detail: nil) {
                Text(tr("Measurements pause automatically")).font(Typo.callout).foregroundStyle(theme.textSecondary)
            }
            SettingsRow(title: tr("Show raw values"),
                        detail: tr("Off: large numbers are smoothed (time-based, rises fast, falls slowly) so they don’t flicker – peaks of the last 10 seconds stay visible, and the latest raw value is shown underneath. On: every number shows exactly the latest measurement.")) {
                Toggle("", isOn: $settings.showRawValues).toggleStyle(.switch).labelsHidden()
            }
            SettingsRow(title: tr("Developer diagnostics"),
                        detail: tr("Shows how much CPU and memory ORBIT itself uses, how long each measurement takes and how often the display updates. Also shows a small overlay in the window.")) {
                Toggle("", isOn: $settings.diagnosticsEnabled).toggleStyle(.switch).labelsHidden()
            }
            if settings.diagnosticsEnabled {
                DiagnosticsPanel(diagnostics: model.engine.diagnostics)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(theme.fieldFill))
            }
        }
    }

    // MARK: Live-Monitor und Menüleiste

    private var windows: some View {
        SettingsPanel(title: tr("Live Monitor & Menu Bar"), symbol: "menubar.rectangle") {
            SettingsRow(title: tr("Show in the menu bar"),
                        detail: tr("Shows the CPU load in the menu bar. ORBIT then keeps running when the window is closed and measures at most every 5 seconds.")) {
                Toggle("", isOn: $settings.menuBarEnabled).toggleStyle(.switch).labelsHidden()
            }
            SettingsRow(title: tr("Keep Live Monitor on top"), detail: tr("The Live Monitor (⌥⌘M) floats above other windows.")) {
                Toggle("", isOn: $settings.liveMonitorOnTop).toggleStyle(.switch).labelsHidden()
            }
            HStack {
                Spacer()
                OpenLiveMonitorButton(withShortcut: false).buttonStyle(CapsuleButtonStyle())
            }
        }
    }

    // MARK: Sprache

    private var language: some View {
        SettingsPanel(title: tr("Language"), symbol: "globe") {
            SettingsRow(title: tr("App language"),
                        detail: tr("Takes effect after restarting ORBIT. You can also set it in System Settings → General → Language & Region → Applications.")) {
                Picker("", selection: Binding(get: { settings.languageChoice }, set: { settings.setLanguage($0) })) {
                    Text(tr("Same as system")).tag(AppSettings.LanguageChoice.system)
                    Text("English").tag(AppSettings.LanguageChoice.english)
                    Text("Deutsch").tag(AppSettings.LanguageChoice.german)
                }
                .labelsHidden()
                .frame(width: 200)
            }
            HStack {
                Spacer()
                Button(tr("Restart ORBIT")) { relaunch() }
                    .buttonStyle(CapsuleButtonStyle())
            }
        }
    }

    private func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: Datenschutz

    private var privacy: some View {
        SettingsPanel(title: tr("Privacy"), symbol: "hand.raised") {
            VStack(alignment: .leading, spacing: 8) {
                privacyLine("network.slash", tr("ORBIT makes no network connections and sends no data anywhere."))
                privacyLine("chart.bar.xaxis", tr("No telemetry, no accounts, no passwords."))
                privacyLine("lock.shield", tr("No administrator rights, no background helpers."))
                privacyLine("clock.arrow.circlepath", tr("Long-term history is off unless you turn it on – and then stays on this Mac."))
                privacyLine("number", tr("The serial number is only read when you ask for it (Hardware → Show) and is never stored."))
                privacyLine("checkmark.seal", tr("Every value shows where it comes from – click the small symbol next to it."))
            }
            Divider().overlay(theme.hairline)
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Data sources")).font(Typo.captionMedium).foregroundStyle(theme.textSecondary)
                ForEach(DataSource.all) { source in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        ProvenanceBadge(source: source)
                        Text(source.api).font(Typo.mono).foregroundStyle(theme.textSecondary).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(source.provenance.title).font(Typo.caption).foregroundStyle(theme.textTertiary)
                    }
                }
            }
        }
    }

    private func privacyLine(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(theme.accent).frame(width: 18)
            Text(text).font(Typo.body).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Bausteine

struct SettingsPanel<Content: View>: View {
    @Environment(\.aether) private var theme
    let title: String
    let symbol: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Label(title, systemImage: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

struct SettingsRow<Control: View>: View {
    @Environment(\.aether) private var theme
    let title: String
    var detail: String? = nil
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.bodyMedium)
                if let detail {
                    Text(detail).font(Typo.caption).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Spacing.l)
            control()
        }
    }
}

/// Vorschau eines Themes als kleine Miniatur des Fensters.
private struct ThemeSwatch: View {
    @Environment(\.aether) private var theme
    @Environment(\.colorScheme) private var colorScheme
    let id: ThemeID
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let spec = ThemeCatalog.spec(id)
        let palette = spec.palette(dark: spec.appearance == .system ? colorScheme == .dark : spec.appearance == .dark)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [Color(palette.backgroundTop), Color(palette.backgroundBottom)], startPoint: .top, endPoint: .bottom)
                    if let first = palette.ambient.first {
                        RadialGradient(colors: [Color(first), .clear], center: .topLeading, startRadius: 0, endRadius: 90)
                    }
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(spec.usesGlass ? palette.glassTint : palette.surface))
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color(palette.hairline)))
                            .frame(width: 26)
                        VStack(spacing: 5) {
                            HStack(spacing: 5) {
                                miniCard(palette, spec.usesGlass, accent: palette.cpuUser)
                                miniCard(palette, spec.usesGlass, accent: palette.memory)
                            }
                            miniCard(palette, spec.usesGlass, accent: palette.networkDown)
                        }
                    }
                    .padding(7)
                }
                .frame(height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? theme.accent : theme.hairline, lineWidth: selected ? 2 : 1)
                )
                HStack(spacing: 5) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent).font(.system(size: 11))
                    }
                    Text(themeName(id)).font(.system(size: 12, weight: selected ? .semibold : .regular)).lineLimit(1)
                }
            }
            .scaleEffect(hovering ? 1.02 : 1)
            .aetherAnimation(Motion.quick, value: hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(themeName(id))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func miniCard(_ palette: ThemePalette, _ glass: Bool, accent: RGBA) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color(glass ? palette.glassTintStrong : palette.surface))
            .overlay(alignment: .bottomLeading) {
                Capsule().fill(Color(accent)).frame(width: 18, height: 3).padding(4)
            }
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color(palette.hairline)))
    }
}

func themeName(_ id: ThemeID) -> String {
    switch id {
    case .liquidGlassDark: return tr("Liquid Glass Dark")
    case .liquidGlassLight: return tr("Liquid Glass Light")
    case .minimalDark: return tr("Minimal Dark")
    case .minimalLight: return tr("Minimal Light")
    case .graphite: return tr("Graphite")
    case .system: return tr("Adaptive (System)")
    }
}

private struct AccentDot: View {
    @Environment(\.aether) private var theme
    let accent: AccentChoice
    let selected: Bool
    let dark: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if let fixed = accent.fixed {
                    Circle().fill(Color(dark ? fixed.dark : fixed.light))
                } else {
                    Circle().fill(LinearGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                if selected {
                    Circle().strokeBorder(theme.textPrimary, lineWidth: 2).padding(-4)
                }
            }
            .frame(width: 20, height: 20)
            .padding(4)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(accentName(accent))
        .accessibilityLabel(accentName(accent))
    }
}

func accentName(_ accent: AccentChoice) -> String {
    switch accent {
    case .system: return tr("System accent color")
    case .aetherBlue: return tr("Arctic Blue")
    case .electricCyan: return tr("Electric Cyan")
    case .mint: return tr("Mint")
    case .violet: return tr("Violet")
    case .orange: return tr("Orange")
    case .pink: return tr("Pink")
    case .graphite: return tr("Graphite")
    }
}

/// Version, Architektur, Liquid Glass, Eigenverbrauch.
private struct AboutPanel: View {
    @ObservedObject var system: SystemStore
    @Environment(\.aether) private var theme

    var body: some View {
        let info = Bundle.main.infoDictionary ?? [:]
        SettingsPanel(title: tr("About ORBIT"), symbol: "info.circle") {
            VStack(spacing: 6) {
                InfoRow(label: tr("Version"), value: "\(info["CFBundleShortVersionString"] as? String ?? "–") (\(info["CFBundleVersion"] as? String ?? "–"))")
                InfoRow(label: tr("This process"), value: processArchitecture)
                InfoRow(label: tr("Liquid Glass"), value: LiquidGlass.isAvailable ? tr("Native (macOS 26)") : tr("Equivalent fallback"))
                if let own = system.ownUsage {
                    InfoRow(label: tr("ORBIT itself"),
                            value: [own.cpu.map { fmt.percent($0, fractionDigits: 1) + " CPU" }, own.footprint.map { fmt.bytes($0, style: .memory) }]
                                .compactMap { $0 }.joined(separator: " · "))
                }
            }
            Text(tr("ORBIT – macOS Edition · System Intelligence & File Explorer"))
                .font(Typo.caption).foregroundStyle(theme.textTertiary)
        }
    }

    private var processArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return system.hardware.isTranslated ? "x86_64 (Rosetta)" : "x86_64"
        #endif
    }
}
