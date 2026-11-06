import SwiftUI
import AppKit
import ABCore

/// Hauptfenster: Seitenleiste + Inhalt.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var transfers: TransferEngine

    var body: some View {
        NavigationSplitView {
            SidebarView(devices: model.devices, transfers: transfers)
                .navigationSplitViewColumnWidth(min: 210, ideal: 236, max: 320)
        } detail: {
            DetailView()
                .frame(minWidth: 640, minHeight: 520)
                .background(AmbientBackground())
        }
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
    }
}

/// Seitenleiste.
struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var devices: DeviceManager
    @ObservedObject var transfers: TransferEngine

    var body: some View {
        List(selection: $model.selection) {
            Section {
                Label("Übersicht", systemImage: "square.grid.2x2")
                    .tag(SidebarItem.overview)
            }
            Section("Geräte") {
                if devices.devices.isEmpty {
                    Label("Kein Gerät angeschlossen", systemImage: "cable.connector.slash")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                } else {
                    ForEach(devices.devices) { device in
                        DeviceSidebarRow(device: device)
                            .tag(SidebarItem.device(device.id))
                    }
                }
            }
            Section("Bibliothek") {
                Label("Dateimanager", systemImage: "folder")
                    .tag(SidebarItem.files)
                Label("Fotos & Videos", systemImage: "photo.on.rectangle.angled")
                    .tag(SidebarItem.media)
                Label("Übertragungen", systemImage: "arrow.up.arrow.down.circle")
                    .badge(transfers.activeCount)
                    .tag(SidebarItem.transfers)
                Label("Favoriten", systemImage: "star")
                    .tag(SidebarItem.favorites)
                Label("Zuletzt verwendet", systemImage: "clock")
                    .tag(SidebarItem.recents)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let fraction = transfers.overallFraction {
                    Button {
                        model.selection = .transfers
                    } label: {
                        HStack(spacing: 10) {
                            ProgressRing(fraction: fraction, lineWidth: 3).frame(width: 18, height: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Übertragung läuft").font(.system(size: 12, weight: .semibold))
                                Text("\(Int(fraction * 100)) %").font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                            }
                            Spacer()
                        }
                        .padding(10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .glassCard(cornerRadius: 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                HStack {
                    SettingsButton()
                    Spacer()
                    Button {
                        model.showDiagnostics = true
                    } label: {
                        Image(systemName: "stethoscope")
                    }
                    .buttonStyle(.borderless)
                    .help("Diagnose")
                }
                .padding(.horizontal, 6)
            }
            .padding(10)
            .animation(.bridgeSpring, value: transfers.overallFraction == nil)
        }
    }
}

/// Öffnet das Einstellungsfenster (macOS 14+: SettingsLink, macOS 13: Menübefehl).
struct SettingsButton: View {
    var body: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                Label("Einstellungen", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
        } else {
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Label("Einstellungen", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
        }
    }
}

struct DeviceSidebarRow: View {
    @ObservedObject var device: DeviceConnection

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Image(systemName: "smartphone")
                    .font(.system(size: 15, weight: .medium))
                Circle()
                    .fill(device.state == .connected ? Palette.success : (device.state == .disconnected ? Color.gray : Palette.warning))
                    .frame(width: 7, height: 7)
                    .offset(x: 7, y: 7)
            }
            .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.displayName).lineLimit(1)
                Text(device.state.title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .opacity(device.state == .disconnected ? 0.5 : 1)
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
            }
        }
        .transition(.opacity)
    }
}
