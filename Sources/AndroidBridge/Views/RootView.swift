import SwiftUI
import AppKit
import ABCore

/// Hauptfenster (4.2): schwebende Liquid-Glass-Navigation oben in der Mitte, darunter die Seiten über dem
/// Lichtfeld-Hintergrund, unten die schwebende Gerätekapsel.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var transfers: TransferEngine
    @ObservedObject var deletion: DeletionService

    var body: some View {
        ZStack(alignment: .top) {
            CinematicBackground()
            PhotoAmbienceLight()
            ChromeHost(devices: model.devices, transfers: transfers, animations: settings.animations)

            // Oberer Rand: Inhalte laufen weich unter die schwebende Navigation; der Streifen zieht das Fenster
            ChromeEdgeFade(top: true)
                .frame(height: NavChrome.contentTop - 8)
                .allowsHitTesting(false)
            WindowDragArea()
                .frame(height: NavChrome.topPadding + NavChrome.barHeight + 4)
            NavBar(transfers: transfers)
                .padding(.top, NavChrome.topPadding)

            VStack {
                Spacer()
                if let progress = deletion.progress {
                    DeletionProgressBadge(progress: progress)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let toast = model.toast {
                    ToastView(toast: toast)
                        .id(toast.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, NavChrome.dockHeight + 34)
            .animation(settings.animations ? .bridgeSpring : nil, value: deletion.progress == nil)
            .animation(settings.animations ? .bridgeSpring : nil, value: model.toast?.id)
            .allowsHitTesting(false)

            // Vollbild-Betrachter über allem (Fotos, Videos)
            if let item = model.viewerItem, let device = model.devices.device(id: item.deviceID) {
                MediaViewer(device: device, item: item)
                    .id(item.id)
                    .transition(.asymmetric(insertion: item.origin == nil ? .opacity.combined(with: .scale(scale: 0.96)) : .opacity,
                                            removal: .opacity.combined(with: .scale(scale: 0.98))))
                    .zIndex(10)
            }
        }
        .animation(settings.animations ? Motion.gentle : nil, value: model.viewerItem?.id)
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowConfigurator())
        .environment(\.glassEnabled, settings.glassEffects)
        .environment(\.animationsEnabled, settings.animations)
        .environment(\.lightIntensity, model.devices.connectedDevices.isEmpty ? 0.25 : 1)
        .tint(settings.accent.color)
        .sheet(item: $transfers.conflict) { prompt in
            ConflictSheet(prompt: prompt)
                .environment(\.glassEnabled, settings.glassEffects)
        }
        .sheet(isPresented: $model.showDiagnostics) {
            DiagnosticsView(devices: model.devices, diagnostics: Diagnostics.shared)
        }
        .sheet(item: $model.infoEntry) { box in
            EntryInfoSheet(box: box) { model.infoEntry = nil }
                .environmentObject(model)
                .environment(\.glassEnabled, settings.glassEffects)
        }
        .deletionSheets(model: model, origin: "main", glass: settings.glassEffects)
    }
}

/// Seiten und – unten schwebend – die Gerätekapsel. Seiten bekommen unten einen Sicherheitsabstand, so dass
/// Inhalte unter die Kapsel scrollen und Aktionsleisten der Seiten darüber stehen.
struct ChromeHost: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var devices: DeviceManager
    @ObservedObject var transfers: TransferEngine
    var animations: Bool

    var body: some View {
        let hasDevice = model.selectedDevice != nil
        DetailView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(animations && !SnapshotMode.isActive ? .spring(response: 0.42, dampingFraction: 0.86) : nil, value: model.selection)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if hasDevice {
                    DeviceDock(devices: devices, transfers: transfers)
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .padding(.bottom, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(animations ? .bridgeSpring : nil, value: hasDevice)
            .onChange(of: model.selectedDevice?.state) { state in
                if state != .connected { PhotoAmbience.shared.clear() }
            }
    }
}

/// Frühere Seitenleiste (bis 4.1) – nicht mehr im Hauptfenster verwendet.
struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var devices: DeviceManager
    @ObservedObject var transfers: TransferEngine
    let rail: Bool
    @Binding var userCollapsed: Bool
    @Environment(\.animationsEnabled) private var animations
    @Environment(\.glassEnabled) private var glass
    @Namespace private var navGlass

    private struct NavEntry: Identifiable {
        var id: String { title }
        let symbol: String
        let title: String
        let item: SidebarItem
        let fill: Bool
    }

    private let items: [NavEntry] = [
        NavEntry(symbol: "square.grid.2x2", title: "Übersicht", item: .overview, fill: true),
        NavEntry(symbol: "folder", title: "Dateimanager", item: .files, fill: true),
        NavEntry(symbol: "photo.on.rectangle.angled", title: "Fotos & Videos", item: .media, fill: false),
        NavEntry(symbol: "arrow.up.arrow.down.circle", title: "Übertragungen", item: .transfers, fill: true),
        NavEntry(symbol: "star", title: "Favoriten", item: .favorites, fill: true),
        NavEntry(symbol: "clock", title: "Zuletzt verwendet", item: .recents, fill: true),
        NavEntry(symbol: "doc.on.doc", title: "Duplikate finden", item: .duplicates, fill: true),
        NavEntry(symbol: "gearshape", title: "Einstellungen", item: .settings, fill: true),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: Metrics.trafficLights)
                .background(WindowDragArea())
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: rail ? .center : .leading, spacing: 2) {
                    ForEach(items) { entry in
                        SidebarRow(symbol: entry.symbol, title: entry.title, item: entry.item, rail: rail,
                                   badge: entry.item == .transfers && transfers.activeCount > 0 ? "\(transfers.activeCount)" : nil,
                                   filledSymbol: entry.fill, glassNamespace: navGlass)
                    }

                    if rail {
                        Divider().opacity(0.6).padding(.vertical, 10).padding(.horizontal, 14)
                    } else {
                        Text("GERÄTE")
                            .font(Typo.sectionLabel)
                            .tracking(0.7)
                            .foregroundStyle(Palette.textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.top, 22)
                            .padding(.bottom, 6)
                    }
                    if devices.devices.isEmpty {
                        if rail {
                            Image(systemName: "cable.connector")
                                .font(.ui(15))
                                .foregroundStyle(Palette.textTertiary)
                                .frame(width: 44, height: Metrics.sidebarRow)
                                .help("Kein Gerät angeschlossen")
                        } else {
                            HStack(spacing: 10) {
                                Image(systemName: "cable.connector").frame(width: 22)
                                Text("Kein Gerät angeschlossen").lineLimit(1)
                            }
                            .font(Typo.caption)
                            .foregroundStyle(Palette.textTertiary)
                            .padding(.horizontal, 10)
                            .frame(height: Metrics.sidebarRow)
                        }
                    } else {
                        ForEach(devices.devices) { device in
                            DeviceSidebarRow(device: device, rail: rail)
                        }
                    }

                    // Dieser Mac – in seiner Bauform
                    if !rail {
                        Text("DIESER MAC")
                            .font(Typo.sectionLabel)
                            .tracking(0.7)
                            .foregroundStyle(Palette.textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.top, 18)
                            .padding(.bottom, 6)
                    }
                    ThisMacRow(rail: rail)
                }
                .padding(.horizontal, rail ? 0 : 10)
                .frame(maxWidth: .infinity, alignment: rail ? .center : .leading)
                .padding(.bottom, 8)
            }
            Spacer(minLength: 0)
            footer
        }
        .frame(maxHeight: .infinity)
        .background(sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Palette.hairline).frame(width: 1)
        }
    }

    @ViewBuilder
    private var sidebarBackground: some View {
        if glass {
            ZStack {
                BackdropBlur(material: .sidebar, blending: .withinWindow)
                Palette.sidebarTint
                LinearGradient(colors: [Palette.glassSheen.opacity(0.6), .clear], startPoint: .top, endPoint: .center)
            }
            .ignoresSafeArea()
        } else {
            Palette.surface.ignoresSafeArea()
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let fraction = transfers.overallFraction {
                Button {
                    model.selection = .transfers
                } label: {
                    HStack(spacing: 10) {
                        ProgressRing(fraction: fraction, lineWidth: 3).frame(width: 20, height: 20)
                        if !rail {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Übertragung läuft").font(Typo.captionMedium).lineLimit(1)
                                Text("\(Int(fraction * 100)) %").font(Typo.caption).foregroundStyle(Palette.textSecondary).monospacedDigit()
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).fill(Palette.fieldFill))
                .help("Übertragungen anzeigen")
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if rail {
                VStack(spacing: 6) {
                    footerButton("sidebar.left", help: "Seitenleiste ausklappen") { userCollapsed = false }
                    footerButton("stethoscope", help: "Diagnose") { model.showDiagnostics = true }
                }
            } else {
                HStack(spacing: 8) {
                    AppMark(size: 22)
                    Text("Android Bridge").font(Typo.captionMedium).foregroundStyle(Palette.textSecondary).lineLimit(1)
                    Spacer(minLength: 4)
                    footerButton("stethoscope", help: "Diagnose") { model.showDiagnostics = true }
                    footerButton("sidebar.left", help: "Seitenleiste einklappen (⌃⌘S)") { userCollapsed = true }
                }
                .padding(.horizontal, 6)
            }
        }
        .padding(10)
        .animation(animations ? .bridgeSpring : nil, value: transfers.overallFraction == nil)
    }

    private func footerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.ui(13, .medium))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Eintrag der Seitenleiste.
struct SidebarRow: View {
    @EnvironmentObject private var model: AppModel
    let symbol: String
    let title: String
    let item: SidebarItem
    var rail = false
    var badge: String?
    var filledSymbol = true
    var glassNamespace: Namespace.ID? = nil
    @State private var hovering = false
    @Environment(\.animationsEnabled) private var animations

    private var selected: Bool { (model.selection ?? .overview) == item }

    var body: some View {
        Button {
            model.selection = item
        } label: {
            Group {
                if rail {
                    ZStack(alignment: .topTrailing) {
                        icon.font(.ui(16, .medium))
                            .frame(width: 44, height: 38)
                        if let badge {
                            Text(badge)
                                .font(.ui(9.5, .bold))
                                .foregroundStyle(Palette.onAccent)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 15, minHeight: 15)
                                .background(Capsule().fill(Palette.accent))
                                .offset(x: 2, y: 1)
                        }
                    }
                } else {
                    HStack(spacing: 10) {
                        icon.font(.ui(14, .medium)).frame(width: 22)
                        Text(title)
                            .font(.ui(13, selected ? .semibold : .medium))
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let badge {
                            Text(badge)
                                .font(.ui(10.5, .bold))
                                .foregroundStyle(Palette.onAccent)
                                .padding(.horizontal, 6)
                                .frame(minWidth: 18, minHeight: 17)
                                .background(Capsule().fill(Palette.accent))
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: Metrics.sidebarRow)
                }
            }
            .background {
                if selected {
                    // Schwebende Glasfläche, die beim Wechsel federnd zum neuen Eintrag gleitet
                    SidebarGlassPill(namespace: glassNamespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Palette.hoverFill)
                        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .strokeBorder(Palette.glassEdgeLight.opacity(0.5), lineWidth: 0.6))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GelButtonStyle())
        .animation(animations ? .spring(response: 0.38, dampingFraction: 0.78) : nil, value: selected)
        .help(rail ? title : "")
        .accessibilityLabel(title)
        .onHover { hovering = $0 }
        .animation(.bridgeQuick, value: hovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var icon: some View {
        Image(systemName: selected && filledSymbol ? symbol + ".fill" : symbol)
            .foregroundStyle(selected ? Palette.accent : Palette.textSecondary)
    }
}

struct DeviceSidebarRow: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var device: DeviceConnection
    var rail = false
    @State private var hovering = false

    private var selected: Bool { model.selection == .device(device.id) }

    var body: some View {
        Button {
            model.selection = .device(device.id)
        } label: {
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "smartphone")
                        .font(.ui(rail ? 17 : 15, .medium))
                        .foregroundStyle(selected ? Palette.accent : Palette.textSecondary)
                        .frame(width: 22)
                    Circle()
                        .fill(dotColor)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 1.2))
                        .offset(x: 1, y: 1)
                }
                if !rail {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(device.displayName).font(.ui(12.5, .semibold)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                        Text(device.state.title).font(.ui(10.5)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, rail ? 11 : 10)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(selected ? Palette.selectionFill : (hovering ? Palette.hoverFill : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(device.displayName) – \(device.state.title)")
        .opacity(device.state == .disconnected ? 0.5 : 1)
        .onHover { hovering = $0 }
    }

    private var dotColor: Color {
        switch device.state {
        case .connected: return Palette.success
        case .disconnected: return Color.gray
        case .interrupted: return Palette.danger
        default: return Palette.warning
        }
    }
}

/// Inhalt je Seitenleisteneintrag.
struct DetailView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            switch model.selection ?? .overview {
            case .overview:
                OverviewView(devices: model.devices)
            case .device(let id):
                if let device = model.devices.device(id: id) {
                    DeviceDetailView(device: device, gallery: model.gallery)
                } else {
                    OverviewView(devices: model.devices)
                }
            case .files:
                FileManagerView(files: model.files, settings: model.settings)
            case .media:
                GalleryView(gallery: model.gallery, devices: model.devices)
            case .transfers:
                TransferCenterView(engine: model.transfers, history: model.history)
            case .favorites:
                FavoritesView(favorites: model.favorites, devices: model.devices)
            case .recents:
                RecentsView(recents: model.recents, devices: model.devices)
            case .duplicates:
                DuplicatesView(scanner: model.duplicates, devices: model.devices)
            case .settings:
                SettingsPage(settings: model.settings, favorites: model.favorites, recents: model.recents, history: model.history)
            }
        }
        .id(model.selection)
        // Seitenwechsel: neue Seite blendet ein und gleitet federnd an ihren Platz
        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 12)).combined(with: .scale(scale: 0.992, anchor: .top)),
                                removal: .opacity))
    }
}


/// Auswahl in der Seitenleiste: kleine Liquid-Glass-Fläche (unter macOS 26 nativ) mit Akzent-Tönung.
struct SidebarGlassPill: View {
    var namespace: Namespace.ID?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        let pill = Color.clear
            .glassSurface(shape, tint: Palette.selectionFill)
            .overlay(shape.strokeBorder(LinearGradient(colors: [Palette.accent.opacity(0.35), Palette.accent2.opacity(0.15)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
        if let namespace {
            pill.matchedGeometryEffect(id: "sidebar-selection", in: namespace)
        } else {
            pill
        }
    }
}

/// „Dieser Mac“: der eigene Mac in seiner Bauform, mit Modellname.
struct ThisMacRow: View {
    var rail: Bool
    private let mac = MacHardware.current

    var body: some View {
        Group {
            if rail {
                MacRender(width: 34, hardware: mac) { LaptopScreenContent() }
                    .frame(width: 44, height: 36)
            } else {
                HStack(spacing: 10) {
                    MacRender(width: 38, hardware: mac) { LaptopScreenContent() }
                        .frame(width: 40, height: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(mac.familyName)
                            .font(.ui(12.5, .semibold))
                            .foregroundStyle(Palette.textPrimary)
                        Text(mac.detailName ?? (mac.isAppleSilicon ? "Apple Silicon" : "Intel"))
                            .font(Typo.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
        .help("\(mac.marketingName) – Gehäusefarbe unter Einstellungen → Erscheinungsbild")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dieser Mac: \(mac.marketingName)")
    }
}
