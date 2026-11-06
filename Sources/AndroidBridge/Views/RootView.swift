import SwiftUI
import AppKit
import ABCore

/// Hauptfenster: schwebende Glas-Seitenleiste über dem Atmosphäre-Hintergrund, rechts die Seiten.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var transfers: TransferEngine
    @ObservedObject var deletion: DeletionService

    var body: some View {
        ZStack {
            AmbientBackground()
            HStack(spacing: 0) {
                SidebarView(devices: model.devices, transfers: transfers)
                    .frame(width: Metrics.sidebarWidth)
                    .padding(Metrics.sidebarInset)
                DetailView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
            .padding(.bottom, 22)
            .padding(.leading, Metrics.sidebarWidth + Metrics.sidebarInset * 2)
            .animation(settings.animations ? .bridgeSpring : nil, value: deletion.progress == nil)
            .animation(settings.animations ? .bridgeSpring : nil, value: model.toast?.id)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowConfigurator())
        .environment(\.glassEnabled, settings.glassEffects)
        .environment(\.animationsEnabled, settings.animations)
        .tint(settings.accent.color)
        .sheet(item: $transfers.conflict) { prompt in
            ConflictSheet(prompt: prompt)
                .environment(\.glassEnabled, settings.glassEffects)
        }
        .sheet(isPresented: $model.showDiagnostics) {
            DiagnosticsView(devices: model.devices, diagnostics: Diagnostics.shared)
        }
        .sheet(item: $model.viewerItem) { item in
            if let device = model.devices.device(id: item.deviceID) {
                MediaViewer(device: device, item: item)
                    .environmentObject(model)
            }
        }
        .deletionSheets(model: model, origin: "main", glass: settings.glassEffects)
    }
}

/// Seitenleiste als schwebende Glasfläche (die Ampel-Knöpfe liegen oben auf ihr).
struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var devices: DeviceManager
    @ObservedObject var transfers: TransferEngine
    @Environment(\.animationsEnabled) private var animations

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: Metrics.trafficLights)
                .background(WindowDragArea())
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    SidebarRow(symbol: "square.grid.2x2", title: "Übersicht", item: .overview)
                    SidebarRow(symbol: "folder", title: "Dateimanager", item: .files)
                    SidebarRow(symbol: "photo.on.rectangle.angled", title: "Fotos & Videos", item: .media, filledSymbol: false)
                    SidebarRow(symbol: "arrow.up.arrow.down.circle", title: "Übertragungen", item: .transfers,
                               badge: transfers.activeCount > 0 ? "\(transfers.activeCount)" : nil)
                    SidebarRow(symbol: "star", title: "Favoriten", item: .favorites)
                    SidebarRow(symbol: "clock", title: "Zuletzt verwendet", item: .recents)
                    SidebarRow(symbol: "doc.on.doc", title: "Duplikate finden", item: .duplicates)
                    SidebarRow(symbol: "gearshape", title: "Einstellungen", item: .settings)

                    Text("GERÄTE")
                        .font(Typo.sectionLabel)
                        .tracking(0.7)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, 20)
                        .padding(.bottom, 6)
                    if devices.devices.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "cable.connector.slash").frame(width: 22)
                            Text("Kein Gerät angeschlossen")
                        }
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, 10)
                        .frame(height: Metrics.sidebarRow)
                    } else {
                        ForEach(devices.devices) { device in
                            DeviceSidebarRow(device: device)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                if let fraction = transfers.overallFraction {
                    Button {
                        model.selection = .transfers
                    } label: {
                        HStack(spacing: 10) {
                            ProgressRing(fraction: fraction, lineWidth: 3).frame(width: 20, height: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Übertragung läuft").font(Typo.captionMedium)
                                Text("\(Int(fraction * 100)) %").font(Typo.caption).foregroundStyle(Palette.textSecondary).monospacedDigit()
                            }
                            Spacer()
                        }
                        .padding(10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).fill(Palette.fieldFill))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                HStack(spacing: 8) {
                    AppMark(size: 22)
                    Text("Android Bridge").font(Typo.captionMedium).foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Button {
                        model.showDiagnostics = true
                    } label: {
                        Image(systemName: "stethoscope")
                            .font(.inter(13, .medium))
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: 26, height: 26)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Diagnose")
                }
                .padding(.horizontal, 6)
            }
            .padding(10)
            .animation(animations ? .bridgeSpring : nil, value: transfers.overallFraction == nil)
        }
        .glassSurface(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous), elevated: true)
    }
}

/// Eintrag der Seitenleiste.
struct SidebarRow: View {
    @EnvironmentObject private var model: AppModel
    let symbol: String
    let title: String
    let item: SidebarItem
    var badge: String?
    var filledSymbol = true
    @State private var hovering = false

    private var selected: Bool { (model.selection ?? .overview) == item }

    var body: some View {
        Button {
            model.selection = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected && filledSymbol ? symbol + ".fill" : symbol)
                    .font(.inter(14, .medium))
                    .foregroundStyle(selected ? Palette.bridgeGreen : Palette.textSecondary)
                    .frame(width: 22)
                Text(title)
                    .font(.inter(13, selected ? .semibold : .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let badge {
                    Text(badge)
                        .font(.inter(10.5, .bold))
                        .foregroundStyle(Palette.onAccent)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 18, minHeight: 17)
                        .background(Capsule().fill(Palette.bridgeGreen))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: Metrics.sidebarRow)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(selected ? Palette.selectionFill : (hovering ? Palette.hoverFill : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.bridgeQuick, value: hovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct DeviceSidebarRow: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var device: DeviceConnection
    @State private var hovering = false

    private var selected: Bool { model.selection == .device(device.id) }

    var body: some View {
        Button {
            model.selection = .device(device.id)
        } label: {
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "smartphone")
                        .font(.inter(15, .medium))
                        .foregroundStyle(selected ? Palette.bridgeGreen : Palette.textSecondary)
                        .frame(width: 22)
                    Circle()
                        .fill(device.state == .connected ? Palette.success : (device.state == .disconnected ? Color.gray : Palette.warning))
                        .frame(width: 7, height: 7)
                        .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 1.2))
                        .offset(x: 1, y: 1)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(device.displayName).font(.inter(12.5, .semibold)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                    Text(device.state.title).font(.inter(10.5)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(selected ? Palette.selectionFill : (hovering ? Palette.hoverFill : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(device.state == .disconnected ? 0.5 : 1)
        .onHover { hovering = $0 }
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
                    DeviceDetailView(device: device)
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
        .transition(.opacity)
    }
}
