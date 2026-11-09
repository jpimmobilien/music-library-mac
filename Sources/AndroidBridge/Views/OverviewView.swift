import SwiftUI
import AppKit
import ABCore

/// Übersicht: Bühne mit Telefon und Mac, Speicher, Schnellzugriffe – oder ohne Gerät: Anleitung.
struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var devices: DeviceManager
    @StateObject private var showcase = DeviceShowcase()
    @StateObject private var thumbs = ThumbLoader()
    @Environment(\.animationsEnabled) private var animations

    private var primary: DeviceConnection? {
        if let selected = model.selectedDevice, selected.state == .connected { return selected }
        return devices.connectedDevices.first ?? devices.devices.first(where: { $0.state != .disconnected }) ?? devices.devices.first
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    if let device = primary {
                        DeviceHero(device: device, showcase: showcase, thumbs: thumbs)
                        DeviceSections(device: device, showcase: showcase)
                        if devices.devices.count > 1 {
                            OtherDevicesRow(devices: devices.devices.filter { $0.id != device.id })
                        }
                    } else {
                        WelcomeHero()
                        ConnectSteps()
                    }
                    PrivacyNote()
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.top, NavChrome.contentTop + 4)
                .padding(.bottom, 40)
                .frame(maxWidth: 1240, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .animation(animations ? .bridgeSpring : nil, value: primary?.state)
            }
            WindowDragArea().frame(height: 40)
        }
        .onAppear(perform: loadShowcase)
        .onChange(of: primary?.state) { _ in loadShowcase() }
        .onChange(of: showcase.photos.map(\.id)) { _ in
            if let d = primary { thumbs.load(showcase.photos, device: d, limit: 8) }
        }
    }

    private func loadShowcase() {
        guard let device = primary else { showcase.reset(); return }
        if device.state == .connected {
            showcase.load(for: device, gallery: model.gallery)
            if !showcase.photos.isEmpty { thumbs.load(showcase.photos, device: device, limit: 8) }
        }
    }
}

// MARK: - Bühne

/// Großer Kopfbereich: dunkle Kino-Bühne mit Telefon und Mac, darüber Zustand, Titel und Hauptaktionen.
struct DeviceHero: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var device: DeviceConnection
    @ObservedObject var showcase: DeviceShowcase
    @ObservedObject var thumbs: ThumbLoader
    @Environment(\.openWindow) private var openWindow

    private var connected: Bool { device.state == .connected }

    var body: some View {
        CinemaStage(connected: connected) {
            VStack(spacing: 14) {
                StateEyebrow(state: device.state, onDark: true)
                Text(heroTitle)
                    .font(.display(50, .bold))
                    .tracking(-1.2)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                Text(heroSubtitle)
                    .font(.ui(16))
                    .foregroundStyle(.white.opacity(0.66))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
                    .fixedSize(horizontal: false, vertical: true)
                if connected {
                    stats.padding(.top, 2)
                    actions.padding(.top, 6)
                } else {
                    stateActions.padding(.top, 4)
                }
                stage
                    .padding(.top, 8)
            }
        }
        // Farbe des neuesten Fotos färbt den App-Hintergrund und erscheint in der Gerätekapsel
        .onAppear { if connected { PhotoAmbience.shared.update(thumbs.images.first) } }
        .onChange(of: thumbs.images.first) { img in if connected { PhotoAmbience.shared.update(img) } }
    }

    private var stage: some View {
        DeviceStage(connected: connected,
                    wallpaper: thumbs.images.first,
                    macPhotos: Array(thumbs.images.prefix(8)),
                    stateSymbol: connected ? "cable.connector" : device.state.symbolName,
                    stateText: connected ? "USB · Dateiübertragung" : device.state.title,
                    phoneCaption: device.displayName)
            .aspectRatio(1.75, contentMode: .fit)
            .frame(maxWidth: 820)
    }

    private var stats: some View {
        HStack(spacing: 22) {
            if let level = device.batteryLevel { BatteryGauge(level: level, outline: .white.opacity(0.6)) }
            Label("\(ByteFormat.string(device.totalFree)) frei", systemImage: "internaldrive")
            if device.storages.count > 1 {
                Label("\(device.storages.count) Speicher", systemImage: "sdcard")
            }
        }
        .font(.ui(13, .semibold))
        .foregroundStyle(.white.opacity(0.9))
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                model.select(device: device)
                model.gallery.filter = .media
                model.selection = .media
            } label: {
                Label("Fotos & Videos", systemImage: "photo.on.rectangle.angled")
            }
            .buttonStyle(GlassButtonStyle(prominent: true))
            Button {
                model.openFiles(device: device)
            } label: {
                Label("Dateien", systemImage: "folder")
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

    private var heroTitle: String {
        switch device.state {
        case .connected: return device.displayName
        case .waitingForFileTransfer: return "Dateiübertragung einschalten"
        case .waitingForAuthorization: return "Telefon entsperren"
        case .busy: return "Gerät ist belegt"
        case .interrupted: return "Verbindung unterbrochen"
        case .disconnected: return "Gerät getrennt"
        case .detected, .connecting, .readingStorage: return device.displayName
        }
    }

    private var heroSubtitle: String {
        switch device.state {
        case .connected:
            var parts = [device.manufacturer, device.model].filter { !$0.isEmpty && $0 != device.displayName }
            if let since = device.connectedAt { parts.append("verbunden seit \(since.formatted(date: .omitted, time: .shortened))") }
            return parts.joined(separator: " · ")
        case .waitingForFileTransfer:
            return "„\(device.displayName)“ lädt gerade nur. Wählen Sie auf dem Telefon „Dateiübertragung / Android Auto“."
        case .waitingForAuthorization:
            return "Android gibt die Speicher von „\(device.displayName)“ erst frei, wenn das Telefon entsperrt ist."
        case .busy:
            return device.issue?.message ?? "Ein anderes Programm verwendet die USB-Verbindung."
        case .interrupted:
            return device.issue?.message ?? "Das Telefon antwortet nicht mehr."
        case .disconnected:
            return "Schließen Sie das Telefon erneut an."
        case .detected: return "Gerät erkannt – Verbindung wird vorbereitet …"
        case .connecting: return "Verbindung wird hergestellt …"
        case .readingStorage: return "Speicher werden gelesen …"
        }
    }

    @ViewBuilder
    private var stateActions: some View {
        switch device.state {
        case .busy:
            HStack(spacing: 10) {
                Button("Freigeben und verbinden") { Task { await device.releasePhotoServiceAndRetry() } }
                    .buttonStyle(GlassButtonStyle(prominent: true))
                Button("Erneut versuchen") { device.reconnect() }
                    .buttonStyle(GlassButtonStyle())
            }
        case .interrupted, .waitingForAuthorization:
            Button("Erneut verbinden") { device.reconnect() }
                .buttonStyle(GlassButtonStyle(prominent: true))
        case .detected:
            if model.settings.autoConnect == false, case .fileTransfer? = device.record?.mode {
                Button("Verbinden") { device.connect() }.buttonStyle(GlassButtonStyle(prominent: true))
            } else {
                ProgressView().controlSize(.small)
            }
        case .connecting, .readingStorage:
            ProgressView().controlSize(.small)
        default:
            EmptyView()
        }
    }
}

/// Dunkle Bühne wie in einer Produktpräsentation – in Hell und Dunkel gleich: tiefes Schwarz,
/// ein Lichtband von oben, farbige Lichtfelder in Blau und Violett, die sehr langsam wandern.
struct CinemaStage<Content: View>: View {
    var connected: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.top, 44)
            .padding(.bottom, 28)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
            .background(CinemaBackdrop(connected: connected))
            .clipShape(RoundedRectangle(cornerRadius: Radius.hero, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04), .white.opacity(0.08)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.28), radius: 30, y: 16)
            .environment(\.colorScheme, .dark)
    }
}

struct CinemaBackdrop: View {
    var connected: Bool
    @Environment(\.animationsEnabled) private var animations
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let animate = animations && !reduceMotion && !SnapshotMode.isActive
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !animate)) { context in
            let t = animate ? context.date.timeIntervalSinceReferenceDate : 0
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let power = connected ? 1.0 : 0.55
                ZStack {
                    LinearGradient(colors: [Color(hex: 0x0C0E14), Color(hex: 0x040406), Color.black], startPoint: .top, endPoint: .bottom)
                    // Lichtkegel von oben
                    RadialGradient(colors: [Color.white.opacity(0.13), .clear], center: UnitPoint(x: 0.5, y: -0.05),
                                   startRadius: 0, endRadius: max(w, h) * 0.55)
                    // farbige Lichtfelder
                    RadialGradient(colors: [Color(hex: 0x2A6BFF).opacity(0.5 * power), .clear],
                                   center: UnitPoint(x: 0.18 + 0.05 * sin(t / 9), y: 0.92 + 0.04 * cos(t / 11)),
                                   startRadius: 0, endRadius: w * 0.48)
                    RadialGradient(colors: [Color(hex: 0x8C5BFF).opacity(0.42 * power), .clear],
                                   center: UnitPoint(x: 0.84 + 0.05 * cos(t / 13), y: 0.8 + 0.05 * sin(t / 10)),
                                   startRadius: 0, endRadius: w * 0.42)
                    RadialGradient(colors: [Color(hex: 0xFF5FA8).opacity(0.12 * power), .clear],
                                   center: UnitPoint(x: 0.55, y: 1.05), startRadius: 0, endRadius: w * 0.35)
                    // Lichtband an der Oberkante
                    Capsule()
                        .fill(LinearGradient(colors: [.clear, .white.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing))
                        .frame(width: w * 0.55, height: 1.2)
                        .position(x: w / 2, y: 0.6)
                    Ellipse()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: w * 0.6, height: 70)
                        .blur(radius: 30)
                        .position(x: w / 2, y: 0)
                }
                .frame(width: w, height: h)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Zustand als leuchtende Zeile über dem Titel.
struct StateEyebrow: View {
    let state: ConnectionState
    var onDark = false
    @State private var pulse = false
    @Environment(\.animationsEnabled) private var animations

    private var color: Color {
        switch state {
        case .connected: return Palette.success
        case .interrupted: return Palette.danger
        case .disconnected: return onDark ? Color.white.opacity(0.55) : Palette.textTertiary
        case .detected, .connecting, .readingStorage: return Palette.accent
        default: return Palette.warning
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(color.opacity(0.35)).frame(width: 14, height: 14).scaleEffect(pulse ? 1.6 : 1).opacity(pulse ? 0 : 1)
                Circle().fill(color).frame(width: 8, height: 8).shadow(color: color, radius: 4)
            }
            Text(state == .connected ? "Verbunden über USB" : (state == .disconnected ? "Kein Telefon verbunden" : state.title))
                .font(Typo.eyebrow)
                .foregroundStyle(state == .disconnected ? (onDark ? Color.white.opacity(0.7) : Palette.textSecondary) : color)
        }
        .padding(.horizontal, onDark ? 12 : 0)
        .padding(.vertical, onDark ? 6 : 0)
        .background { if onDark { Capsule().fill(Color.white.opacity(0.08)).overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.6)) } }
        .onAppear {
            guard animations, !SnapshotMode.isActive, state != .disconnected else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// Telefon, Lichtverbindung und dieser Mac – in seiner echten Bauform (siehe MacRender).
struct DeviceStage: View {
    var connected: Bool
    var wallpaper: NSImage?
    var macPhotos: [NSImage] = []
    var stateSymbol: String?
    var stateText: String?
    var phoneCaption: String?
    var hardware: MacHardware = .current

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let laptop = hardware.form.isLaptop
            let macW = min(w * (laptop ? 0.6 : 0.46), h * (laptop ? 1.12 : 0.82))
            let phoneW = min(w * 0.17, h * 0.34)
            let phoneX = w * 0.2, macX = w * 0.62
            ZStack {
                // Bodenlicht unter beiden Geräten
                Ellipse()
                    .fill(RadialGradient(colors: [Palette.accent.opacity(connected ? 0.55 : 0.18), Palette.accent2.opacity(connected ? 0.2 : 0.06), .clear],
                                         center: .center, startRadius: 0, endRadius: w * 0.42))
                    .frame(width: w * 0.92, height: h * 0.22)
                    .blur(radius: 14)
                    .position(x: w * 0.47, y: h * 0.86)
                // Spiegelung auf dem „Boden“
                Rectangle()
                    .fill(LinearGradient(colors: [.white.opacity(0.07), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.8, height: 1)
                    .position(x: w * 0.47, y: h * 0.84)
                VStack(spacing: 12) {
                    MacRender(width: macW, hardware: hardware) {
                        LaptopScreenContent(photos: connected ? macPhotos : [])
                            .opacity(connected ? 1 : 0.5)
                    }
                    MacCaption(hardware: hardware)
                }
                .position(x: macX, y: h * 0.46)
                ConnectionBeam(active: connected)
                    .frame(width: w * 0.2, height: h * 0.26)
                    .position(x: w * 0.36, y: h * 0.66)
                VStack(spacing: 12) {
                    PhoneRender(width: phoneW, glow: Palette.accent, glowAmount: connected ? 0.75 : 0.15) {
                        PhoneScreenContent(wallpaper: connected ? wallpaper : nil, stateSymbol: stateSymbol, stateText: stateText,
                                           dimmed: !connected)
                    }
                    .rotation3DEffect(.degrees(-10), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    if let phoneCaption {
                        HStack(spacing: 6) {
                            Image(systemName: "smartphone")
                            Text(phoneCaption).fontWeight(.semibold)
                        }
                        .font(.ui(11.5))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: w * 0.3)
                    }
                }
                .position(x: phoneX, y: h * 0.5)
            }
            .frame(width: w, height: h)
        }
    }
}

/// Ohne Gerät: großer Einstieg auf der Kino-Bühne.
struct WelcomeHero: View {
    var body: some View {
        CinemaStage(connected: false) {
            VStack(spacing: 14) {
                StateEyebrow(state: .disconnected, onDark: true)
                Text("Ihr Android.\nDirekt auf Ihrem Mac.")
                    .font(.display(52, .bold))
                    .tracking(-1.3)
                    .foregroundStyle(
                        LinearGradient(colors: [.white, Color(hex: 0xC9D6FF)], startPoint: .top, endPoint: .bottom)
                    )
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Fotos, Videos und Dateien per USB – ohne Cloud, ohne Konto, mit voller Geschwindigkeit.")
                    .font(.ui(16))
                    .foregroundStyle(.white.opacity(0.66))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .fixedSize(horizontal: false, vertical: true)
                DeviceStage(connected: false, stateSymbol: "cable.connector", stateText: "Nicht verbunden", phoneCaption: "Ihr Android-Telefon")
                    .aspectRatio(1.75, contentMode: .fit)
                    .frame(maxWidth: 820)
                    .padding(.top, 8)
            }
        }
    }
}

/// Drei Schritte zum Verbinden – mit kleinen Illustrationen.
struct ConnectSteps: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            SectionHeading(title: "So verbinden Sie Ihr Telefon", subtitle: "Android Bridge erkennt das Gerät automatisch – unabhängig vom Hersteller.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                StepCard(number: 1, symbol: "cable.connector", tint: Palette.bridgeBlue, title: "Mit USB verbinden",
                         detail: "Am besten mit einem Kabel, das Daten überträgt – manche Ladekabel können nur laden.")
                StepCard(number: 2, symbol: "lock.open", tint: Palette.violet, title: "Telefon entsperren",
                         detail: "Android gibt den Speicher erst frei, wenn das Telefon entsperrt ist.")
                StepCard(number: 3, symbol: "arrow.left.arrow.right", tint: Palette.accent, title: "„Dateiübertragung“ wählen",
                         detail: "In der Mitteilung „USB-Verbindung“ auf „Dateiübertragung / Android Auto“ tippen.")
            }
        }
    }
}

struct StepCard: View {
    let number: Int
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: symbol)
                    .font(.ui(40, .light))
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("\(number)")
                    .font(.ui(12, .bold))
                    .foregroundStyle(Palette.onAccent)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(tint))
                    .padding(10)
            }
            .frame(height: 110)
            Text(title).font(.ui(15, .semibold)).foregroundStyle(Palette.textPrimary)
            Text(detail).font(Typo.callout).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Radius.card)
        .interactiveCard(pressable: false)
    }
}

/// Abschnittsüberschrift (Titel groß, Untertitel dezent).
struct SectionHeading<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Typo.title).tracking(-0.3).foregroundStyle(Palette.textPrimary)
                if let subtitle {
                    Text(subtitle).font(Typo.callout).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension SectionHeading where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

// MARK: - Abschnitte bei verbundenem Gerät

struct DeviceSections: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var device: DeviceConnection
    @ObservedObject var showcase: DeviceShowcase

    var body: some View {
        switch device.state {
        case .connected:
            VStack(alignment: .leading, spacing: Spacing.section) {
                StorageOverview(device: device)
                QuickActions(device: device, showcase: showcase)
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
        default:
            EmptyView()
        }
    }
}

/// Speicher als Ringe.
struct StorageOverview: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var device: DeviceConnection

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            SectionHeading(title: "Speicher", subtitle: "\(ByteFormat.string(device.totalFree)) frei auf \(device.storages.count == 1 ? "1 Speicher" : "\(device.storages.count) Speichern")") {
                Button("Speicher verwalten") { model.selection = .device(device.id) }
                    .buttonStyle(GlassButtonStyle(compact: true))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                ForEach(device.storages) { storage in
                    StorageTile(storage: storage) { model.openFiles(device: device, storageID: storage.id) }
                }
            }
        }
    }
}

struct StorageTile: View {
    let storage: DeviceStorage
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 22) {
                StorageRing(storage: storage, size: 112)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: storage.symbolName)
                        Text(storage.shortName).lineLimit(1)
                    }
                    .font(.ui(15, .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    Text("\(ByteFormat.string(storage.free)) frei")
                        .font(.display(22, .bold))
                        .foregroundStyle(Palette.textPrimary)
                        .monospacedDigit()
                    Text("von \(ByteFormat.string(storage.capacity)) · \(ByteFormat.string(storage.used)) belegt")
                        .font(Typo.callout)
                        .foregroundStyle(Palette.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if storage.isReadOnly {
                        TagLabel(text: "Nur lesen", symbol: "lock", tint: Palette.warning)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.ui(13, .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .opacity(hovering ? 1 : 0.4)
            }
            .padding(20)
            .contentShape(Rectangle())
        }
        .buttonStyle(GelButtonStyle())
        .glassCard(cornerRadius: Radius.card, elevated: hovering)
        .interactiveCard()
        .scaleEffect(hovering ? 1.01 : 1)
        .animation(.bridgeQuick, value: hovering)
        .onHover { hovering = $0 }
        .help("\(storage.displayName) im Dateimanager öffnen")
    }
}

/// Schnellzugriffe mit echten Vorschaubildern.
struct QuickActions: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var device: DeviceConnection
    @ObservedObject var showcase: DeviceShowcase

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            SectionHeading(title: "Was möchten Sie tun?")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16)], spacing: 16) {
                FeatureTile(title: "Fotos importieren", subtitle: "Auswählen und auf den Mac übertragen", symbol: "photo.on.rectangle.angled",
                            tint: FileKind.photo.tint) {
                    if showcase.photos.isEmpty {
                        tileArt(symbol: "photo.stack", tint: FileKind.photo.tint)
                    } else {
                        ThumbnailMosaic(items: showcase.photos, device: device, columns: 3, rows: 2)
                    }
                } action: { openGallery(.photos) }
                FeatureTile(title: "Videos importieren", subtitle: "Große Dateien bequem übertragen", symbol: "film",
                            tint: FileKind.video.tint) {
                    if let video = showcase.videos.first {
                        ZStack {
                            DeviceThumb(entry: video.entry, device: device, size: 260, corner: 0)
                            Image(systemName: "play.circle.fill")
                                .font(.ui(38))
                                .foregroundStyle(.white, Color.black.opacity(0.35))
                                .shadow(radius: 6)
                        }
                    } else {
                        tileArt(symbol: "film.stack", tint: FileKind.video.tint)
                    }
                } action: { openGallery(.videos) }
                FeatureTile(title: "Dateien durchsuchen", subtitle: "Alle Ordner und Speicher des Telefons", symbol: "folder",
                            tint: FileKind.folder.tint) {
                    tileArt(symbol: "folder.fill", tint: FileKind.folder.tint)
                } action: {
                    model.files.layout = .single
                    model.openFiles(device: device)
                }
                FeatureTile(title: "Dateien übertragen", subtitle: "Mac und Telefon nebeneinander – ziehen und ablegen", symbol: "arrow.left.arrow.right",
                            tint: Palette.accent2) {
                    tileArt(symbol: "arrow.left.arrow.right.square.fill", tint: Palette.accent2)
                } action: {
                    model.files.layout = .dual
                    model.openFiles(device: device)
                }
                FeatureTile(title: "Duplikate finden", subtitle: "Exakte Kopien per Inhaltsvergleich", symbol: "doc.on.doc",
                            tint: Palette.violet) {
                    tileArt(symbol: "square.on.square.fill", tint: Palette.violet)
                } action: {
                    model.select(device: device)
                    model.selection = .duplicates
                }
                FeatureTile(title: "Speicherplatz verwalten", subtitle: "Belegung nach Art und größte Dateien", symbol: "chart.pie",
                            tint: Palette.accent) {
                    tileArt(symbol: "chart.pie.fill", tint: Palette.accent)
                } action: { model.selection = .device(device.id) }
            }
        }
    }

    private func openGallery(_ filter: MediaFilter) {
        model.select(device: device)
        model.gallery.filter = filter
        model.selection = .media
    }

    private func tileArt(symbol: String, tint: Color) -> some View {
        ZStack {
            LinearGradient(colors: [tint.opacity(0.42), tint.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color.white.opacity(0.35), .clear], center: UnitPoint(x: 0.2, y: 0.1), startRadius: 0, endRadius: 140)
            Image(systemName: symbol)
                .font(.ui(46, .regular))
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(0.6), radius: 14)
        }
    }
}

/// Große Kachel mit Bildfläche oben.
struct FeatureTile<Preview: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    @ViewBuilder var preview: () -> Preview
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                preview()
                    .frame(maxWidth: .infinity)
                    .frame(height: 132)
                    .scaleEffect(hovering ? 1.04 : 1)
                    .clipped()
                    .clipShape(TopRoundedRectangle(radius: Radius.card - 4))
                    .padding([.top, .horizontal], 6)
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.ui(15, .semibold)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                        Text(subtitle).font(Typo.caption).foregroundStyle(Palette.textSecondary).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.right")
                        .font(.ui(12, .bold))
                        .foregroundStyle(hovering ? Palette.onAccent : tint)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(hovering ? tint : tint.opacity(0.14)))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GelButtonStyle())
        .glassCard(cornerRadius: Radius.card, elevated: hovering)
        .interactiveCard()
        .offset(y: hovering ? -2 : 0)
        .animation(.bridgeQuick, value: hovering)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

/// Oben gerundetes Rechteck (UnevenRoundedRectangle gibt es erst ab macOS 14).
struct TopRoundedRectangle: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height / 2, rect.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Weitere angeschlossene Geräte.
struct OtherDevicesRow: View {
    @EnvironmentObject private var model: AppModel
    let devices: [DeviceConnection]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeading(title: "Weitere Geräte")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(devices) { d in
                        Button {
                            model.select(device: d)
                            model.selection = .device(d.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "smartphone").font(.ui(18))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(d.displayName).font(.ui(13, .semibold)).lineLimit(1)
                                    Text(d.state.title).font(Typo.caption).foregroundStyle(Palette.textSecondary).lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .glassCard(cornerRadius: Radius.tile)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - Bestehende Bausteine

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
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x10261F), Color(hex: 0x050708)], startPoint: .top, endPoint: .bottom))
                .overlay(Image(systemName: "smartphone").font(.ui(size * 0.45, .semibold)).foregroundStyle(Palette.accent))
                .frame(width: size, height: size)
        }
    }
}

/// Bebilderte Anleitung: USB-Modus auf „Dateiübertragung“ stellen.
struct ConnectionGuideView: View {
    @State private var highlight = false
    @Environment(\.animationsEnabled) private var animations

    private let options = ["Dateiübertragung / Android Auto", "USB-Tethering", "MIDI", "PTP", "Kein Datentransfer"]

    var body: some View {
        HStack(alignment: .center, spacing: 34) {
            PhoneRender(width: 140, glowAmount: 0.4) {
                ZStack(alignment: .top) {
                    Color(hex: 0x16191D)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("USB-Einstellungen")
                            .font(.ui(11.5, .semibold))
                            .foregroundStyle(.white)
                            .padding(.top, 30)
                        Text("USB verwenden für")
                            .font(.ui(8.5))
                            .foregroundStyle(.white.opacity(0.6))
                        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                            HStack(spacing: 6) {
                                ZStack {
                                    Circle().strokeBorder(index == 0 ? Palette.accent : Color.white.opacity(0.5), lineWidth: 1.2)
                                    if index == 0 && highlight { Circle().fill(Palette.accent).padding(2.5) }
                                }
                                .frame(width: 11, height: 11)
                                Text(option)
                                    .font(.ui(8.2, index == 0 ? .semibold : .regular))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(index == 0 && highlight ? Palette.accent.opacity(0.22) : .clear))
                        }
                    }
                    .padding(.horizontal, 11)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Label("So geht’s", systemImage: "hand.tap")
                    .font(Typo.title2)
                Text("Entsperren Sie Ihr Android-Gerät und wählen Sie in den USB-Verbindungseinstellungen „Dateiübertragung / Android Auto“.")
                    .font(.ui(14))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Die Einstellung finden Sie in der Mitteilung „Gerät wird über USB aufgeladen“ – oder unter Einstellungen → Verbundene Geräte → USB.")
                    .font(Typo.callout)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Erscheint nichts? Dann überträgt das Kabel möglicherweise keine Daten – probieren Sie ein anderes.")
                    .font(Typo.callout)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .glassCard(cornerRadius: Radius.panel)
        .onAppear {
            if animations && !SnapshotMode.isActive {
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
                .foregroundStyle(Palette.accent)
            Text("Alles bleibt lokal: Übertragungen laufen direkt per USB zwischen Telefon und Mac. Kein Konto, keine Cloud, keine Telemetrie.")
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Speicher & Gerät

/// „Speicherplatz verwalten“: Belegung je Speicher, Aufschlüsselung nach Art, größte Dateien, Gerätedaten.
struct DeviceDetailView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var device: DeviceConnection
    @ObservedObject var gallery: GalleryModel
    @StateObject private var emptyShowcase = DeviceShowcase()
    @State private var customName = ""

    private var analysed: Bool { gallery.device?.id == device.id && !gallery.items.isEmpty && !gallery.isScanning }

    var body: some View {
        PageScaffold(title: device.displayName, subtitle: "Speicher & Gerät · \(device.state.title)") {
            if device.state == .connected {
                ToolbarCapsule {
                    ToolbarIconButton(symbol: "folder", help: "Im Dateimanager öffnen") { model.openFiles(device: device) }
                    ToolbarIconButton(symbol: "doc.on.doc", help: "Duplikate finden") {
                        model.select(device: device)
                        model.selection = .duplicates
                    }
                    ToolbarIconButton(symbol: "arrow.clockwise", help: "Speicher neu lesen") {
                        Task { await device.refreshStorages() }
                    }
                }
            }
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    if device.state == .connected {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                            ForEach(device.storages) { storage in
                                StorageTile(storage: storage) { model.openFiles(device: device, storageID: storage.id) }
                            }
                        }
                        analysis
                    } else {
                        DeviceSections(device: device, showcase: emptyShowcase)
                    }
                    deviceInfo
                }
                .reportsScrollEdge()
                .padding(.horizontal, Spacing.gutter)
                .padding(.bottom, 40)
                .frame(maxWidth: 1180, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { customName = model.settings.preferences(forSerial: device.serial).customName ?? "" }
    }

    @ViewBuilder
    private var analysis: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            SectionHeading(title: "Belegung nach Art",
                           subtitle: analysed ? "Aus der letzten Suche über alle Ordner" : "Android Bridge liest dafür nur die Ordnerlisten – keine Dateiinhalte.") {
                if gallery.isScanning && gallery.device?.id == device.id {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("\(gallery.scannedFolders) Ordner …").font(Typo.caption).foregroundStyle(Palette.textSecondary).monospacedDigit()
                    }
                } else {
                    Button(analysed ? "Neu analysieren" : "Speicher analysieren") {
                        model.select(device: device)
                        if gallery.device?.id != device.id { gallery.attach(device) }
                        gallery.scan()
                    }
                    .buttonStyle(GlassButtonStyle(prominent: !analysed, compact: true))
                }
            }
            if analysed {
                let breakdown = StorageBreakdown(items: gallery.items)
                BreakdownBar(breakdown: breakdown)
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text("Größte Dateien").font(Typo.title2)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                        ForEach(breakdown.largest) { item in
                            LargeFileCard(item: item, device: device)
                        }
                    }
                }
            }
        }
    }

    private var deviceInfo: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            SectionHeading(title: "Gerät")
            VStack(alignment: .leading, spacing: 16) {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 9) {
                    infoRow("Hersteller", device.manufacturer)
                    infoRow("Modell", device.model)
                    if let level = device.batteryLevel { infoRow("Akku", "\(level) %") }
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
                .font(Typo.body)
                Divider().opacity(0.5)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { nameEditor }
                    VStack(alignment: .leading, spacing: 8) { nameEditor }
                }
                Text("Ordnerposition und Speicherwahl merkt sich Android Bridge je Gerät (abschaltbar in den Einstellungen).")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
            .glassCard(cornerRadius: Radius.card)
        }
    }

    @ViewBuilder
    private var nameEditor: some View {
        Text("Anzeigename").font(Typo.bodyMedium)
        TextField(device.model, text: $customName, onCommit: saveName)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 180, maxWidth: 280)
        Button("Übernehmen", action: saveName).buttonStyle(GlassButtonStyle(compact: true))
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
            Text(label).foregroundStyle(Palette.textSecondary)
            Text(value).textSelection(.enabled)
        }
    }
}

/// Farbiger Balken mit Legende.
struct BreakdownBar: View {
    let breakdown: StorageBreakdown
    @State private var shown = false
    @Environment(\.animationsEnabled) private var animations

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeometryReader { geo in
                let available = geo.size.width - CGFloat(max(breakdown.slices.count - 1, 0)) * 3
                HStack(spacing: 3) {
                    ForEach(breakdown.slices) { slice in
                        let f = breakdown.total > 0 ? CGFloat(Double(slice.bytes) / Double(breakdown.total)) : 0
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(LinearGradient(colors: [slice.color.opacity(0.8), slice.color], startPoint: .top, endPoint: .bottom))
                            .frame(width: max(4, available * f * (shown ? 1 : 0)))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 22)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], alignment: .leading, spacing: 10) {
                ForEach(breakdown.slices) { slice in
                    HStack(spacing: 10) {
                        Image(systemName: slice.symbol)
                            .font(.ui(13, .semibold))
                            .foregroundStyle(slice.color)
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(slice.color.opacity(0.14)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(slice.title).font(Typo.bodyMedium).lineLimit(1)
                            Text("\(ByteFormat.string(slice.bytes)) · \(slice.count)")
                                .font(Typo.caption).foregroundStyle(Palette.textSecondary).monospacedDigit().lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(22)
        .glassCard(cornerRadius: Radius.card)
        .onAppear {
            if animations && !SnapshotMode.isActive { withAnimation(Motion.reveal.delay(0.1)) { shown = true } } else { shown = true }
        }
    }
}

/// Große Datei mit Vorschau und Aktionen.
struct LargeFileCard: View {
    @EnvironmentObject private var model: AppModel
    let item: MediaItem
    let device: DeviceConnection
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                DeviceThumb(entry: item.entry, device: device, size: 170, corner: 0)
                    .frame(maxWidth: .infinity)
                    .frame(height: 110)
                    .clipped()
                Text(ByteFormat.string(item.entry.size))
                    .font(.ui(12, .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.5)))
                    .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
            Text(item.entry.name).font(Typo.captionMedium).lineLimit(1).truncationMode(.middle)
            Text(item.path.joined(separator: " › ")).font(.ui(10.5)).foregroundStyle(Palette.textSecondary).lineLimit(1).truncationMode(.middle)
        }
        .padding(8)
        .glassCard(cornerRadius: Radius.card - 2, elevated: hovering)
        .onHover { hovering = $0 }
        .help("\(item.entry.name) – \(ByteFormat.string(item.entry.size))")
        .contextMenu {
            if item.entry.kind.isMedia {
                Button("Öffnen") {
                    model.viewerItem = MediaViewerItem(deviceID: device.id, items: [item.entry], index: 0)
                }
            }
            Button("Auf den Mac übertragen") {
                model.transfers.download([item.entry], from: device, sourcePath: [],
                                         to: model.settings.destination(for: item.entry.kind))
            }
            Button("Im Dateimanager zeigen") {
                model.selection = .files
                Task { await model.files.device.navigate(storageID: item.entry.storageID, path: item.path) }
            }
            Divider()
            Button("Auf dem Telefon löschen …", role: .destructive) {
                model.requestDeletion([item.entry], on: device,
                                      locations: [device.location(storageID: item.entry.storageID, path: item.path).displayPath])
            }
        }
    }
}
