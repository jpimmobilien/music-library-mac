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
                List {
                    ForEach(favorites.favorites) { fav in
                        let available = devices.connectedDevices.contains { $0.serial == fav.location.deviceSerial }
                        Button {
                            model.openLocation(fav.location)
                        } label: {
                            HStack(spacing: 12) {
                                IconTile(symbol: "star.fill", tint: available ? Palette.warning : .gray, size: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fav.name).font(.inter(13.5, .medium))
                                    Text("\(fav.location.deviceName) › \(fav.location.displayPath)")
                                        .font(.inter(11.5)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if !available {
                                    Text("Gerät nicht verbunden").font(.inter(11)).foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!available)
                        .contextMenu {
                            Button("Entfernen", role: .destructive) { favorites.remove(fav) }
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove { favorites.move(from: $0, to: $1) }
                }
                .scrollContentBackground(.hidden)
                .glassCard(cornerRadius: Radius.panel)
                .padding(.horizontal, Spacing.gutter - 6)
                .padding(.bottom, 18)
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
                            FileGlyph(kind: FileKind.of(name: r.name, isFolder: false), size: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).font(.inter(13, .medium)).lineLimit(1)
                                Text("\(r.location.deviceName) › \(r.location.displayPath)")
                                    .font(.inter(11.5)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(ByteFormat.string(r.size)).font(.inter(11.5)).monospacedDigit()
                                Text(r.date.formatted(date: .abbreviated, time: .shortened)).font(.inter(11)).foregroundStyle(.secondary)
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
                Text("Diagnose").font(.inter(17, .semibold))
                Spacer()
                Button("In Zwischenablage kopieren") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                }
                Button("Fertig") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text("Enthält keine Dateinamen oder Inhalte – nur Geräte, Schnittstellen und Vorgänge.")
                .font(.inter(11.5)).foregroundStyle(.secondary)
            GroupBox("USB-Geräte") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let e = devices.monitorError { Text("Überwachung: \(e)").foregroundStyle(Palette.danger) }
                        ForEach(devices.allUSBDevices) { r in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(r.productName ?? "Unbekannt") – \(r.vendorName ?? USBDeviceClassifier.vendorName(r.vendorID) ?? "?") [\(r.idString)]")
                                    .font(.inter(12, .medium))
                                Text("Modus: \(modeText(r.mode))\(r.speedDescription.map { " · \($0)" } ?? "")")
                                    .font(.inter(11)).foregroundStyle(.secondary)
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
