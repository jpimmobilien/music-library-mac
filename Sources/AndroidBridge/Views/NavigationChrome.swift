import SwiftUI
import AppKit
import ABCore

// =============================================================================================
// 4.2 – Navigation wie in der Musikbibliothek: schwebende Liquid-Glass-Leiste oben in der Mitte (Symbol über
// Beschriftung, gleitende Linse unter dem aktiven Bereich) und unten eine schwebende Gerätekapsel – das
// Gegenstück zum Mini-Player: neuestes Foto, Gerät, Zustand, Speicher bzw. laufende Übertragung, Schnellaktionen.
// Der Hintergrund nimmt dezent die Farbe des neuesten Fotos auf dem Telefon an.
// =============================================================================================

enum NavChrome {
    static let topPadding: CGFloat = 10
    static let barHeight: CGFloat = 54
    /// Abstand, ab dem Seiteninhalte beginnen (unter der Leiste).
    static let contentTop: CGFloat = topPadding + barHeight + 16
    static let itemWidth: CGFloat = 80
    static let dockHeight: CGFloat = 84
}

struct NavBar: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var transfers: TransferEngine
    @Environment(\.animationsEnabled) private var animations

    struct Entry: Identifiable {
        var id: String { label }
        let symbol: String
        let label: String
        let item: SidebarItem
        var filled = true
    }

    static let entries: [Entry] = [
        Entry(symbol: "square.grid.2x2", label: "Übersicht", item: .overview),
        Entry(symbol: "folder", label: "Dateien", item: .files),
        Entry(symbol: "photo.on.rectangle.angled", label: "Fotos", item: .media, filled: false),
        Entry(symbol: "arrow.up.arrow.down.circle", label: "Übertragen", item: .transfers),
        Entry(symbol: "star", label: "Favoriten", item: .favorites),
        Entry(symbol: "clock", label: "Zuletzt", item: .recents),
        Entry(symbol: "doc.on.doc", label: "Duplikate", item: .duplicates),
        Entry(symbol: "gearshape", label: "Einstellungen", item: .settings),
    ]

    var body: some View {
        let entries = Self.entries
        let current = model.selection ?? .overview
        let index = entries.firstIndex { $0.item == current }
        let w = NavChrome.itemWidth
        ZStack(alignment: .leading) {
            // Linse unter dem aktiven Eintrag – gleitet federnd
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Palette.accentSoft)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Palette.glassEdgeLight.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 0.7))
                .frame(width: w, height: NavChrome.barHeight - 10)
                .offset(x: 5 + w * CGFloat(index ?? 0))
                .opacity(index == nil ? 0 : 1)
                .animation(animations ? .spring(response: 0.42, dampingFraction: 0.78) : nil, value: index)
            HStack(spacing: 0) {
                ForEach(entries) { e in
                    NavItem(entry: e, selected: e.item == current,
                            badge: e.item == .transfers && transfers.activeCount > 0 ? transfers.activeCount : nil) {
                        model.selection = e.item
                    }
                    .frame(width: w, height: NavChrome.barHeight - 10)
                }
            }
            .padding(.horizontal, 5)
        }
        .frame(width: w * CGFloat(entries.count) + 10, height: NavChrome.barHeight)
        .glassSurface(RoundedRectangle(cornerRadius: 27, style: .continuous), elevated: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bereiche")
    }
}

private struct NavItem: View {
    let entry: NavBar.Entry
    let selected: Bool
    var badge: Int?
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let fg = selected ? Palette.accent : Palette.textPrimary.opacity(hover ? 0.92 : 0.72)
        Button(action: action) {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: selected && entry.filled ? entry.symbol + ".fill" : entry.symbol)
                        .font(.ui(17, .medium))
                        .frame(height: 21)
                    if let badge {
                        Text("\(badge)")
                            .font(.ui(9, .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(Capsule().fill(Palette.accent))
                            .offset(x: 10, y: -4)
                    }
                }
                Text(entry.label)
                    .font(.ui(10, selected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(GelButtonStyle())
        .onHover { hover = $0 }
        .help(entry.label)
        .accessibilityLabel(entry.label)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .animation(.bridgeQuick, value: selected)
    }
}

// MARK: - Gerätekapsel unten

/// Schwebende Kapsel unten (Gegenstück zum Mini-Player): aktuelles Telefon mit neuestem Foto, Zustand,
/// Speicher oder laufender Übertragung und Schnellaktionen.
struct DeviceDock: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var devices: DeviceManager
    @ObservedObject var transfers: TransferEngine
    @ObservedObject private var ambience = PhotoAmbience.shared

    var body: some View {
        if let device = model.selectedDevice {
            DockContent(device: device, devices: devices, transfers: transfers, photo: ambience.image)
        }
    }
}

private struct DockContent: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var device: DeviceConnection
    @ObservedObject var devices: DeviceManager
    @ObservedObject var transfers: TransferEngine
    var photo: NSImage?
    @Environment(\.openWindow) private var openWindow

    private var connected: Bool { device.state == .connected }

    var body: some View {
        HStack(spacing: 16) {
            artwork
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    nameView
                    Spacer(minLength: 4)
                }
                statusLine
                progress
            }
            .frame(minWidth: 180)
            actions
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .frame(height: NavChrome.dockHeight)
        .frame(maxWidth: 1080)
        .glassSurface(RoundedRectangle(cornerRadius: 30, style: .continuous), strong: true, elevated: true)
    }

    private var artwork: some View {
        ZStack {
            if let photo, connected {
                Color.clear.overlay(Image(nsImage: photo).resizable().aspectRatio(contentMode: .fill)).clipped()
            } else {
                Palette.accent
                Image(systemName: "smartphone").font(.ui(24, .medium)).foregroundStyle(.white)
            }
        }
        .frame(width: 62, height: 62)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 0.7))
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(connected ? Palette.success : Palette.warning)
                .frame(width: 13, height: 13)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 2))
                .offset(x: 3, y: 3)
        }
        .shadow(color: Palette.shadow, radius: 8, y: 3)
    }

    @ViewBuilder
    private var nameView: some View {
        let others = devices.devices.filter { $0.id != device.id && $0.state != .disconnected }
        if others.isEmpty {
            Text(device.displayName).font(.ui(15, .semibold)).foregroundStyle(Palette.textPrimary).lineLimit(1)
        } else {
            Menu {
                ForEach(devices.devices.filter { $0.state != .disconnected }) { d in
                    Button(d.displayName) { model.select(device: d) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(device.displayName).font(.ui(15, .semibold)).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.ui(10, .semibold))
                }
                .foregroundStyle(Palette.textPrimary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Gerät wechseln")
        }
    }

    private var statusLine: some View {
        HStack(spacing: 10) {
            if transfers.activeCount > 0, let f = transfers.overallFraction {
                Text("Übertragung läuft · \(Int(f * 100)) %").foregroundStyle(Palette.accent).fontWeight(.semibold)
            } else {
                Text(connected ? "Verbunden über USB" : device.state.title)
                    .foregroundStyle(connected ? Palette.success : Palette.warning)
                    .fontWeight(.semibold)
            }
            if connected {
                if let level = device.batteryLevel {
                    Label("\(level) %", systemImage: level > 20 ? "battery.75" : "battery.25")
                }
                Text("\(ByteFormat.string(device.totalFree)) frei")
            }
        }
        .font(.ui(12))
        .foregroundStyle(Palette.textSecondary)
        .lineLimit(1)
    }

    private var progress: some View {
        let fraction: Double = {
            if transfers.activeCount > 0, let f = transfers.overallFraction { return f }
            guard device.totalCapacity > 0 else { return 0 }
            return 1 - Double(device.totalFree) / Double(device.totalCapacity)
        }()
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.fieldFill)
                Capsule()
                    .fill(Palette.accent)
                    .frame(width: max(4, geo.size.width * fraction))
            }
        }
        .frame(height: 4)
        .help(transfers.activeCount > 0 ? "Fortschritt aller Übertragungen" : "Belegter Speicher auf dem Telefon")
        .animation(.bridgeQuick, value: fraction)
    }

    private var actions: some View {
        HStack(spacing: 6) {
            dockButton("photo.on.rectangle.angled", "Fotos & Videos") {
                model.select(device: device)
                model.gallery.filter = .media
                model.selection = .media
            }
            dockButton("folder", "Dateien") { model.openFiles(device: device) }
            dockButton("internaldrive", "Speicher verwalten") { model.select(device: device); model.selection = .device(device.id) }
            dockButton("macwindow.badge.plus", "In eigenem Fenster öffnen") { openWindow(value: device.id) }
            dockButton("stethoscope", "Diagnose") { model.showDiagnostics = true }
        }
        .disabled(!connected && device.state != .waitingForFileTransfer)
    }

    private func dockButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.ui(15, .medium))
                .foregroundStyle(Palette.textPrimary.opacity(0.85))
                .frame(width: 38, height: 38)
                .background(Circle().fill(Palette.fieldFill))
                .contentShape(Circle())
        }
        .buttonStyle(GelButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Farbe aus dem neuesten Foto

/// Leuchtfarbe des neuesten Fotos auf dem Telefon – färbt den App-Hintergrund dezent ein
/// (wie die Cover-Farbe in der Musikbibliothek). Wird von der Übersicht gesetzt.
@MainActor
final class PhotoAmbience: ObservableObject {
    static let shared = PhotoAmbience()
    @Published private(set) var glow: Color?
    @Published private(set) var image: NSImage?

    func update(_ image: NSImage?) {
        guard image !== self.image else { return }
        self.image = image
        guard let image else { glow = nil; return }
        glow = Self.vividAverage(of: image).map { Color(nsColor: $0) }
    }

    func clear() {
        image = nil
        glow = nil
    }

    /// Durchschnittsfarbe (auf 8×8 verkleinert), etwas gesättigt, damit sie als Licht wirkt.
    static func vividAverage(of image: NSImage) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let size = 8
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let ctx = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
        var r = 0.0, g = 0.0, b = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            r += Double(pixels[i]); g += Double(pixels[i + 1]); b += Double(pixels[i + 2])
        }
        let n = Double(size * size) * 255
        let base = NSColor(srgbRed: r / n, green: g / n, blue: b / n, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        base.usingColorSpace(.sRGB)?.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        guard s > 0.08 else { return nil }   // graue Fotos: neutral bleiben
        return NSColor(hue: h, saturation: min(1, s * 1.35 + 0.15), brightness: max(0.55, min(0.95, v * 1.2)), alpha: 1)
    }
}

/// Lichtfelder in der Farbe des neuesten Fotos über dem App-Hintergrund.
struct PhotoAmbienceLight: View {
    @ObservedObject private var ambience = PhotoAmbience.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.glassEnabled) private var glass

    var body: some View {
        GeometryReader { geo in
            let r = max(geo.size.width, geo.size.height) * 0.62
            ZStack {
                if let glow = ambience.glow, glass {
                    RadialGradient(colors: [glow.opacity(scheme == .dark ? 0.2 : 0.12), .clear],
                                   center: UnitPoint(x: 0.85, y: 0.06), startRadius: 0, endRadius: r)
                    RadialGradient(colors: [glow.opacity(scheme == .dark ? 0.1 : 0.06), .clear],
                                   center: UnitPoint(x: 0.08, y: 0.92), startRadius: 0, endRadius: r * 0.9)
                }
            }
            .animation(.easeInOut(duration: 1.2), value: ambience.glow)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Oberer und unterer Rand: Inhalte laufen weich unter die schwebenden Leisten.
struct ChromeEdgeFade: View {
    let top: Bool

    var body: some View {
        LinearGradient(stops: top
            ? [.init(color: Palette.background.opacity(0.85), location: 0), .init(color: Palette.background.opacity(0.4), location: 0.55), .init(color: .clear, location: 1)]
            : [.init(color: .clear, location: 0), .init(color: Palette.background.opacity(0.45), location: 0.5), .init(color: Palette.background.opacity(0.75), location: 1)],
            startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
    }
}
