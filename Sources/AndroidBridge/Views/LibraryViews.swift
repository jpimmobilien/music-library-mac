import SwiftUI
import AppKit
import ABCore

/// Favorisierte Ordner auf Android-Geräten.
struct FavoritesView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var favorites: FavoritesStore
    @ObservedObject var devices: DeviceManager

    var body: some View {
        PageScaffold(title: "Favoriten", subtitle: "Häufig genutzte Ordner auf Ihren Telefonen – mit einem Klick geöffnet") {
        Group {
            if favorites.favorites.isEmpty {
                EmptyStateView(symbol: "star", title: "Noch keine Favoriten",
                               message: "Markieren Sie häufig genutzte Ordner – etwa „DCIM/Camera“ oder „Download“ – über das Kontextmenü im Dateimanager.") {
                    if let device = devices.connectedDevices.first {
                        Button("Vorschläge hinzufügen") { addSuggestions(device) }
                            .buttonStyle(GlassButtonStyle(prominent: true))
                    }
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                        ForEach(Array(favorites.favorites.enumerated()), id: \.element.id) { index, fav in
                            let available = devices.connectedDevices.contains { $0.serial == fav.location.deviceSerial }
                            FavoriteTile(name: fav.name,
                                         detail: "\(fav.location.deviceName) › \(fav.location.displayPath)"
                                            .replacingOccurrences(of: "Interner gemeinsamer Speicher", with: "Interner Speicher"),
                                         available: available) {
                                model.openLocation(fav.location)
                            }
                            .contextMenu {
                                if index > 0 {
                                    Button("An den Anfang") { favorites.move(from: IndexSet(integer: index), to: 0) }
                                }
                                Button("Entfernen", role: .destructive) { favorites.remove(fav) }
                            }
                        }
                    }
                    .reportsScrollEdge()
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.bottom, 30)
                }
            }
        }
        }
    }

    private func addSuggestions(_ device: DeviceConnection) {
        guard let storage = device.storages.first(where: { !$0.isRemovable }) ?? device.storages.first else { return }
        for path in [["DCIM", "Camera"], ["Pictures"], ["Download"], ["Documents"]] {
            let loc = device.location(storageID: storage.id, path: path)
            if !favorites.contains(loc) { favorites.toggle(loc) }
        }
    }
}

/// Zuletzt geöffnete bzw. übertragene Dateien.
struct RecentsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var recents: RecentsStore
    @ObservedObject var devices: DeviceManager

    var body: some View {
        PageScaffold(title: "Zuletzt verwendet", subtitle: "Dateien, die Sie zuletzt angesehen oder übertragen haben") {
            ToolbarCapsule {
                ToolbarIconButton(symbol: "trash.slash", help: "Liste leeren (Dateien bleiben erhalten)") { recents.clear() }
                    .disabled(recents.recents.isEmpty)
            }
        } content: {
        Group {
            if !model.settings.recentFilesEnabled {
                EmptyStateView(symbol: "clock.badge.xmark", title: "Ausgeschaltet",
                               message: "„Zuletzt verwendet“ ist in den Einstellungen unter Datenschutz ausgeschaltet.")
            } else if recents.recents.isEmpty {
                EmptyStateView(symbol: "clock", title: "Noch nichts verwendet",
                               message: "Hier erscheinen Dateien, die Sie zuletzt angesehen oder übertragen haben.")
            } else {
                List(recents.recents) { r in
                    let available = devices.connectedDevices.contains { $0.serial == r.location.deviceSerial }
                    Button {
                        model.openLocation(r.location)
                    } label: {
                        HStack(spacing: 12) {
                            TypeIcon(name: r.name, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).font(.ui(13, .medium)).lineLimit(1)
                                Text("\(r.location.deviceName) › \(r.location.displayPath)")
                                    .font(.ui(11.5)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(ByteFormat.string(r.size)).font(.ui(11.5)).monospacedDigit()
                                Text(r.date.formatted(date: .abbreviated, time: .shortened)).font(.ui(11)).foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!available)
                    .padding(.vertical, 3)
                }
                .scrollContentBackground(.hidden)
                .glassCard(cornerRadius: Radius.panel)
                .padding(.horizontal, Spacing.gutter - 6)
                .padding(.bottom, 18)
            }
        }
        }
    }
}

/// Technische Diagnose: USB-Geräte, Schnittstellen, Protokoll.
struct DiagnosticsView: View {
    @ObservedObject var devices: DeviceManager
    @ObservedObject var diagnostics: Diagnostics
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Diagnose").font(.ui(17, .semibold))
                Spacer()
                Button("In Zwischenablage kopieren") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                }
                Button("Fertig") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text("Enthält keine Dateinamen oder Inhalte – nur Geräte, Schnittstellen und Vorgänge.")
                .font(.ui(11.5)).foregroundStyle(.secondary)
            GroupBox("USB-Geräte") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let e = devices.monitorError { Text("Überwachung: \(e)").foregroundStyle(Palette.danger) }
                        ForEach(devices.allUSBDevices) { r in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(r.productName ?? "Unbekannt") – \(r.vendorName ?? USBDeviceClassifier.vendorName(r.vendorID) ?? "?") [\(r.idString)]")
                                    .font(.ui(12, .medium))
                                Text("Modus: \(modeText(r.mode))\(r.speedDescription.map { " · \($0)" } ?? "")")
                                    .font(.ui(11)).foregroundStyle(.secondary)
                                ForEach(r.interfaces, id: \.self) { i in
                                    Text("  Schnittstelle \(i.number): Klasse \(hex(i.interfaceClass))/\(hex(i.subClass))/\(hex(i.interfaceProtocol)) \(i.name ?? "")")
                                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if devices.allUSBDevices.isEmpty { Text("Keine USB-Geräte gefunden.").foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 160)
            }
            GroupBox("Protokoll") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(diagnostics.entries.reversed()) { e in
                            Text("\(e.date.formatted(date: .omitted, time: .standard)) [\(e.category.rawValue)] \(e.message)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(e.isError ? Palette.danger : .primary)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 220)
            }
        }
        .padding(22)
        .frame(width: 760, height: 600)
    }

    private func hex(_ v: Int) -> String { v < 0 ? "?" : String(format: "%02X", v) }

    private func modeText(_ mode: USBDeviceMode) -> String {
        switch mode {
        case let .fileTransfer(i, ptp): return "Dateiübertragung (Schnittstelle \(i)\(ptp ? ", PTP" : ""))"
        case .androidWithoutFileTransfer: return "Android ohne Dateiübertragung"
        case .unrelated: return "kein Android-Gerät"
        }
    }

    private var report: String {
        var lines: [String] = []
        let info = Bundle.main.infoDictionary
        lines.append("Android Bridge \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))")
        lines.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString), \(SystemInfo.architecture)")
        for r in devices.allUSBDevices {
            lines.append("USB \(r.idString) \(r.productName ?? "") – \(modeText(r.mode))")
            for i in r.interfaces {
                lines.append("   if\(i.number) \(hex(i.interfaceClass))/\(hex(i.subClass))/\(hex(i.interfaceProtocol)) \(i.name ?? "")")
            }
        }
        lines.append("")
        lines.append(diagnostics.exportText())
        return lines.joined(separator: "\n")
    }
}

enum SystemInfo {
    static var architecture: String {
        #if arch(arm64)
        let native = "Apple Silicon (arm64)"
        #else
        let native = "Intel (x86_64)"
        #endif
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0, translated == 1 {
            return native + " über Rosetta"
        }
        return native
    }
}

/// Favoritenordner als Kachel.
struct FavoriteTile: View {
    let name: String
    let detail: String
    let available: Bool
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    TypeIcon(name: name, isFolder: true, size: 58)
                        .shadow(color: Palette.shadow, radius: 6, y: 3)
                    Spacer()
                    Image(systemName: "star.fill")
                        .font(.ui(13))
                        .foregroundStyle(available ? Palette.warning : Palette.textTertiary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.ui(15, .semibold)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                    Text(detail).font(Typo.caption).foregroundStyle(Palette.textSecondary).lineLimit(2).truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    Circle().fill(available ? Palette.success : Palette.textTertiary).frame(width: 7, height: 7)
                    Text(available ? "Bereit" : "Gerät nicht verbunden").font(.ui(11, .medium)).foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(GelButtonStyle())
        .disabled(!available)
        .glassCard(cornerRadius: Radius.card, elevated: hovering && available)
        .interactiveCard()
        .opacity(available ? 1 : 0.6)
        .offset(y: hovering && available ? -2 : 0)
        .onHover { hovering = $0 }
        .animation(.bridgeQuick, value: hovering)
    }
}
