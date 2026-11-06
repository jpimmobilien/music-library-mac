import SwiftUI
import AppKit
import ABCore

/// Übersicht: Anleitung ohne Gerät, sonst Gerätekarten mit Speichern.
struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var devices: DeviceManager
    @Environment(\.animationsEnabled) private var animations

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                if devices.devices.isEmpty {
                    NoDeviceHero()
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    ForEach(devices.devices) { device in
                        DeviceHeroCard(device: device)
                            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                    removal: .opacity.combined(with: .scale(scale: 0.96))))
                    }
                }
                PrivacyNote()
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
            .animation(animations ? .bridgeSpring : nil, value: devices.devices.map(\.id))
        }
        .navigationTitle("Übersicht")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            AppMark(size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("Android Bridge")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(devices.devices.isEmpty ? "Fotos, Videos und Dateien zwischen Android und Mac – per USB, ganz ohne Cloud."
                     : "\(devices.connectedDevices.count) von \(devices.devices.count) \(devices.devices.count == 1 ? "Gerät" : "Geräten") bereit")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

/// Markenzeichen: das App-Symbol (im Bundle), sonst eine gezeichnete Rückfallform.
struct AppMark: View {
    var size: CGFloat = 40

    var body: some View {
        if Bundle.main.url(forResource: "AppIcon", withExtension: "icns") != nil {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: size * 1.22, height: size * 1.22)
                .frame(width: size, height: size)
        } else {
            drawnMark
        }
    }

    private var drawnMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(LinearGradient(colors: [Palette.bridgeGreen, Palette.bridgeTeal, Palette.bridgeBlue], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8)
            BridgeArcShape()
                .stroke(Color.white, style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
                .frame(width: size * 0.62, height: size * 0.4)
                .offset(y: -size * 0.02)
            HStack(spacing: size * 0.32) {
                RoundedRectangle(cornerRadius: size * 0.05).fill(Color.white).frame(width: size * 0.12, height: size * 0.22)
                RoundedRectangle(cornerRadius: size * 0.04).fill(Color.white).frame(width: size * 0.2, height: size * 0.14)
            }
            .offset(y: size * 0.19)
        }
        .frame(width: size, height: size)
        .shadow(color: Palette.bridgeTeal.opacity(0.35), radius: 8, y: 3)
    }
}

struct BridgeArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                   control1: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.minY - rect.height * 0.25),
                   control2: CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.minY - rect.height * 0.25))
        return p
    }
}

/// Ohne Gerät: Anleitung zum Anschließen.
struct NoDeviceHero: View {
    @State private var cableOffset: CGFloat = 14
    @Environment(\.animationsEnabled) private var animations

    var body: some View {
        HStack(alignment: .center, spacing: 40) {
            ZStack {
                PulseRings(active: true)
                    .frame(width: 210, height: 210)
                PhoneShapeView(width: 88) {
                    ZStack {
                        LinearGradient(colors: [Palette.bridgeGreen.opacity(0.5), Palette.bridgeBlue.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                        Image(systemName: "cable.connector")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                Capsule()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 10, height: 46)
                    .offset(y: 118 + cableOffset)
            }
            .frame(width: 230, height: 270)
            .onAppear {
                guard animations else { cableOffset = 0; return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { cableOffset = 0 }
            }

            VStack(alignment: .leading, spacing: 18) {
                Text("Android-Telefon anschließen")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                StepRow(number: 1, title: "Mit USB-Kabel verbinden", detail: "Verwenden Sie ein Kabel, das Daten überträgt – manche Ladekabel können nur laden.")
                StepRow(number: 2, title: "Telefon entsperren", detail: "Android gibt den Speicher erst frei, wenn das Telefon entsperrt ist.")
                StepRow(number: 3, title: "„Dateiübertragung“ wählen", detail: "Tippen Sie auf die Mitteilung „USB-Verbindung“ und wählen Sie „Dateiübertragung / Android Auto“.")
                Text("Android Bridge erkennt das Gerät automatisch – unabhängig vom Hersteller.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(30)
        .glassCard(cornerRadius: 26, elevated: true)
    }
}

struct StepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(LinearGradient(colors: [Palette.bridgeGreen, Palette.bridgeTeal], startPoint: .top, endPoint: .bottom)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Karte eines Geräts in der Übersicht.
struct DeviceHeroCard: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var device: DeviceConnection
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    PulseRings(active: device.state.isWorking || device.state == .waitingForAuthorization)
                        .frame(width: 92, height: 92)
                    PhoneShapeView(width: 40) {
                        ZStack {
                            LinearGradient(colors: [Palette.bridgeGreen.opacity(0.6), Palette.bridgeBlue.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                            Image(systemName: device.state == .connected ? "checkmark" : device.state.symbolName)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 6) {
                    Text(device.displayName)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    HStack(spacing: 8) {
                        StatusPill(state: device.state)
                        if device.state == .connected {
                            Text("\(ByteFormat.string(device.totalFree)) frei")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                if device.state == .connected {
                    GlassGroup {
                        HStack(spacing: 8) {
                            Button {
                                model.openFiles(device: device)
                            } label: {
                                Label("Dateien", systemImage: "folder")
                            }
                            .buttonStyle(GlassButtonStyle(prominent: true))
                            Button {
                                model.select(device: device)
                                model.selection = .media
                            } label: {
                                Label("Fotos & Videos", systemImage: "photo.on.rectangle")
                            }
                            .buttonStyle(GlassButtonStyle())
                            Button {
                                openWindow(value: device.id)
                            } label: {
                                Image(systemName: "macwindow.badge.plus")
                            }
                            .buttonStyle(GlassButtonStyle())
                            .help("In eigenem Fenster öffnen")
                        }
                    }
                }
            }

            stateContent
        }
        .padding(24)
        .glassCard(cornerRadius: 24, elevated: true)
    }

    @ViewBuilder
    private var stateContent: some View {
        switch device.state {
        case .connected:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                ForEach(device.storages) { storage in
                    StorageCard(storage: storage) { model.openFiles(device: device, storageID: storage.id) }
                }
            }
        case .waitingForFileTransfer:
            ConnectionGuideView()
        case .busy:
            if let issue = device.issue {
                IssueBanner(issue: issue,
                            primaryTitle: "Freigeben und verbinden",
                            primaryAction: { Task { await device.releasePhotoServiceAndRetry() } },
                            secondaryTitle: "Erneut versuchen",
                            secondaryAction: { device.reconnect() })
            }
        case .waitingForAuthorization:
            IssueBanner(issue: device.issue ?? .locked, secondaryTitle: "Erneut versuchen", secondaryAction: { device.reconnect() })
        case .interrupted:
            if let issue = device.issue {
                IssueBanner(issue: issue, primaryTitle: "Erneut verbinden", primaryAction: { device.reconnect() })
            }
        case .detected:
            if model.settings.autoConnect == false, case .fileTransfer? = device.record?.mode {
                Button("Verbinden") { device.connect() }.buttonStyle(GlassButtonStyle(prominent: true))
            } else {
                Text("Gerät wird erkannt …").font(.system(size: 13)).foregroundStyle(.secondary)
            }
        case .connecting, .readingStorage:
            Text(device.state == .connecting ? "Verbindung wird hergestellt …" : "Speicher werden gelesen …")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        case .disconnected:
            Text("Das Gerät wurde getrennt.").font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
}

/// Bebilderte Anleitung: USB-Modus auf „Dateiübertragung“ stellen.
struct ConnectionGuideView: View {
    @State private var highlight = false
    @Environment(\.animationsEnabled) private var animations

    private let options = ["Dateiübertragung / Android Auto", "USB-Tethering", "MIDI", "PTP", "Kein Datentransfer"]

    var body: some View {
        HStack(alignment: .center, spacing: 30) {
            PhoneShapeView(width: 120) {
                ZStack(alignment: .top) {
                    Color(nsColor: .windowBackgroundColor)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("USB-Einstellungen")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.top, 22)
                        Text("USB verwenden für")
                            .font(.system(size: 7.5))
                            .foregroundStyle(.secondary)
                        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                            HStack(spacing: 5) {
                                ZStack {
                                    Circle().strokeBorder(index == 0 ? Palette.bridgeGreen : Color.secondary, lineWidth: 1.2)
                                    if index == 0 && highlight { Circle().fill(Palette.bridgeGreen).padding(2.5) }
                                }
                                .frame(width: 10, height: 10)
                                Text(option)
                                    .font(.system(size: 7.2, weight: index == 0 ? .semibold : .regular))
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 3)
                            .padding(.horizontal, 4)
                            .background(RoundedRectangle(cornerRadius: 5).fill(index == 0 && highlight ? Palette.bridgeGreen.opacity(0.15) : .clear))
                        }
                    }
                    .padding(.horizontal, 9)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Label("Dateiübertragung einschalten", systemImage: "hand.tap")
                    .font(.system(size: 16, weight: .semibold))
                Text("Entsperren Sie Ihr Android-Gerät und wählen Sie in den USB-Verbindungseinstellungen „Dateiübertragung / Android Auto“.")
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Die Einstellung finden Sie in der Mitteilung „Gerät wird über USB aufgeladen“ – oder unter Einstellungen → Verbundene Geräte → USB.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Erscheint nichts? Dann überträgt das Kabel möglicherweise keine Daten – probieren Sie ein anderes.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .glassCard(cornerRadius: 18, strong: true)
        .onAppear {
            if animations {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(0.3)) { highlight = true }
            } else {
                highlight = true
            }
        }
    }
}

/// Hinweis zum Datenschutz.
struct PrivacyNote: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .foregroundStyle(Palette.bridgeGreen)
            Text("Alles bleibt lokal: Übertragungen laufen direkt per USB zwischen Telefon und Mac. Kein Konto, keine Cloud, keine Telemetrie.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }
}

/// Detailseite eines Geräts.
struct DeviceDetailView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var device: DeviceConnection
    @State private var customName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DeviceHeroCard(device: device)
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Gerät")
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                        infoRow("Hersteller", device.manufacturer)
                        infoRow("Modell", device.model)
                        if let v = device.info?.deviceVersion, !v.isEmpty { infoRow("Version", v) }
                        if let r = device.record {
                            infoRow("USB-Kennung", r.idString)
                            if let s = r.speedDescription { infoRow("Verbindung", s) }
                        }
                        if let info = device.info {
                            infoRow("Protokoll", info.isMTP ? "MTP (Media Transfer Protocol)" : "PTP (nur Fotos und Videos)")
                        }
                        infoRow("Seriennummer", maskedSerial)
                    }
                    .font(.system(size: 13))
                }
                .padding(20)
                .glassCard(cornerRadius: 20)

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Für dieses Gerät")
                    HStack {
                        Text("Anzeigename")
                        TextField(device.model, text: $customName, onCommit: saveName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 280)
                        Button("Übernehmen", action: saveName)
                    }
                    Text("Ordnerposition und Speicherwahl merkt sich Android Bridge je Gerät (abschaltbar in den Einstellungen).")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .glassCard(cornerRadius: 20)
            }
            .padding(30)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(device.displayName)
        .onAppear { customName = model.settings.preferences(forSerial: device.serial).customName ?? "" }
    }

    private var maskedSerial: String {
        let s = device.serial
        guard s.count > 4 else { return s }
        return String(repeating: "•", count: min(8, s.count - 4)) + s.suffix(4)
    }

    private func saveName() {
        let name = customName.trimmingCharacters(in: .whitespaces)
        model.settings.updatePreferences(forSerial: device.serial) { $0.customName = name.isEmpty ? nil : name }
        device.objectWillChange.send()
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}
