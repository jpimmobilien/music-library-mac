import SwiftUI
import AppKit
import ABCore

// =============================================================================================
// Eigene Produktdarstellungen von Android Bridge: Telefon, Mac (neutrales Notebook ohne Markenzeichen),
// Lichtverbindung, Speicherringe, Akku. Alles gezeichnet – keine fremden Bilder.
// =============================================================================================

/// Ein modernes Telefon: dünner Rahmen, Kameraloch, Seitentasten, Glasreflex. Der Bildschirm zeigt echte Inhalte.
struct PhoneRender<Screen: View>: View {
    var width: CGFloat = 150
    var glow: Color = Palette.accent
    var glowAmount: Double = 0.6
    @ViewBuilder var screen: () -> Screen

    var body: some View {
        let height = width * 2.08
        let corner = width * 0.16
        ZStack {
            // Leuchten hinter dem Gerät
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(glow.opacity(0.55 * glowAmount))
                .blur(radius: width * 0.28)
                .scaleEffect(1.02)
            // Seitentasten
            RoundedRectangle(cornerRadius: 1.5)
                .fill(LinearGradient(colors: [Color(hex: 0x6A717B), Color(hex: 0x2B3036)], startPoint: .top, endPoint: .bottom))
                .frame(width: width * 0.025, height: height * 0.11)
                .offset(x: width * 0.505, y: -height * 0.17)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(LinearGradient(colors: [Color(hex: 0x6A717B), Color(hex: 0x2B3036)], startPoint: .top, endPoint: .bottom))
                .frame(width: width * 0.025, height: height * 0.18)
                .offset(x: width * 0.505, y: -height * 0.01)
            // Gehäuse mit metallischer Kante
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x5B626B), Color(hex: 0x1C1F23), Color(hex: 0x3D434A)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: corner * 0.94, style: .continuous)
                .fill(Color.black)
                .padding(width * 0.018)
            // Bildschirm
            screen()
                .frame(width: width * 0.9, height: height * 0.953)
                .clipShape(RoundedRectangle(cornerRadius: corner * 0.82, style: .continuous))
            // Kameraloch
            Circle()
                .fill(Color.black)
                .overlay(Circle().fill(RadialGradient(colors: [Color(hex: 0x24364A), .black], center: .center, startRadius: 0, endRadius: width * 0.02)))
                .frame(width: width * 0.065, height: width * 0.065)
                .offset(y: -height * 0.448)
            // Glasreflex
            RoundedRectangle(cornerRadius: corner * 0.82, style: .continuous)
                .fill(LinearGradient(stops: [.init(color: Color.white.opacity(0.16), location: 0),
                                             .init(color: Color.white.opacity(0.0), location: 0.38),
                                             .init(color: Color.white.opacity(0.0), location: 1)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: width * 0.9, height: height * 0.953)
                .allowsHitTesting(false)
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.05), Color.white.opacity(0.25)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
        .frame(width: width, height: height)
        .compositingGroup()
        .shadow(color: .black.opacity(0.45), radius: width * 0.12, y: width * 0.08)
        .accessibilityHidden(true)
    }
}

/// Neutrales Notebook (eigene Form, kein Markenzeichen) – nur noch für kleine Symbole; die Bühne nutzt MacRender.
struct LaptopRender<Screen: View>: View {
    var width: CGFloat = 320
    @ViewBuilder var screen: () -> Screen

    var body: some View {
        let lidH = width * 0.64
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: width * 0.035, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x4A5058), Color(hex: 0x1E2125)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: width * 0.03, style: .continuous)
                    .fill(Color.black)
                    .padding(width * 0.008)
                screen()
                    .frame(width: width * 0.94, height: lidH * 0.9)
                    .clipShape(RoundedRectangle(cornerRadius: width * 0.012, style: .continuous))
                    .offset(y: lidH * 0.012)
                // Kamera
                Circle().fill(Color(hex: 0x1C2633)).frame(width: width * 0.012).offset(y: -lidH * 0.47)
                RoundedRectangle(cornerRadius: width * 0.035, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
            }
            .frame(width: width, height: lidH)
            // Unterteil
            LaptopBase()
                .fill(LinearGradient(colors: [Color(hex: 0x8C939C), Color(hex: 0x3B4047)], startPoint: .top, endPoint: .bottom))
                .frame(width: width * 1.16, height: width * 0.04)
                .overlay(
                    Capsule().fill(Color.black.opacity(0.35)).frame(width: width * 0.16, height: width * 0.012).offset(y: -width * 0.012)
                )
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.5), radius: width * 0.06, y: width * 0.04)
        .accessibilityHidden(true)
    }
}

private struct LaptopBase: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - r.width * 0.03, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.03, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Bildschirm des Notebooks: ruhige Arbeitsfläche mit dem Android-Bridge-Fenster in klein.
struct LaptopScreenContent: View {
    var photos: [NSImage] = []

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0A1A3A), Color(hex: 0x0A0F24), Color(hex: 0x24104A)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(hex: 0x4D93FF).opacity(0.5), .clear], center: UnitPoint(x: 0.1, y: 0.0), startRadius: 0, endRadius: 160)
            // Mini-Fenster
            GeometryReader { geo in
                let w = geo.size.width * 0.78, h = geo.size.height * 0.7
                HStack(spacing: 0) {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(width: w * 0.2)
                    VStack(alignment: .leading, spacing: h * 0.04) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.7)).frame(width: w * 0.22, height: h * 0.05)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 4), spacing: 3) {
                            ForEach(0..<8, id: \.self) { i in
                                Group {
                                    if i < photos.count {
                                        Color.clear.overlay(Image(nsImage: photos[i]).resizable().aspectRatio(contentMode: .fill))
                                    } else {
                                        LinearGradient(colors: [Color(hue: Double(i) / 8, saturation: 0.45, brightness: 0.8),
                                                                Color(hue: Double(i) / 8 + 0.08, saturation: 0.6, brightness: 0.5)],
                                                       startPoint: .top, endPoint: .bottom)
                                    }
                                }
                                .frame(height: h * 0.3)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                            }
                        }
                    }
                    .padding(w * 0.04)
                }
                .frame(width: w, height: h)
                .background(Color.black.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                .position(x: geo.size.width / 2, y: geo.size.height * 0.52)
            }
        }
    }
}

/// Telefonbildschirm: echtes Foto als Hintergrund, Uhrzeit, Zustand.
struct PhoneScreenContent: View {
    var wallpaper: NSImage?
    var stateSymbol: String?
    var stateText: String?
    var dimmed = false

    var body: some View {
        ZStack {
            if let wallpaper {
                // Füllt die Fläche, ohne den Stapel zu vergrößern (sonst würde die Uhr zu groß gezeichnet)
                Color.clear.overlay(Image(nsImage: wallpaper).resizable().aspectRatio(contentMode: .fill)).clipped()
            } else {
                // Ohne Foto: ruhiger, dunkler Sperrbildschirm
                LinearGradient(colors: [Color(hex: 0x2A2C31), Color(hex: 0x111214), Color.black], startPoint: .top, endPoint: .bottom)
            }
            LinearGradient(colors: [Color.black.opacity(0.35), .clear, Color.black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
            GeometryReader { geo in
                VStack(spacing: geo.size.width * 0.02) {
                    Text(Date(), format: .dateTime.hour().minute())
                        .font(.system(size: geo.size.width * 0.19, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, geo.size.width * 0.06)
                    Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.system(size: geo.size.width * 0.06, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, geo.size.width * 0.06)
                    Spacer()
                    if let stateSymbol, let stateText {
                        HStack(spacing: 5) {
                            Image(systemName: stateSymbol)
                            Text(stateText).lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .font(.system(size: geo.size.width * 0.058, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, geo.size.width * 0.06)
                        .padding(.vertical, geo.size.width * 0.03)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .environment(\.colorScheme, .dark)
                        .padding(.horizontal, geo.size.width * 0.05)
                    }
                }
                .padding(.top, geo.size.height * 0.12)
                .padding(.bottom, geo.size.height * 0.07)
                .frame(width: geo.size.width, height: geo.size.height)
            }
            if dimmed { Color.black.opacity(0.55) }
        }
    }
}

/// Lichtverbindung zwischen zwei Punkten: weich leuchtende Kurve, auf der Lichtpunkte wandern.
struct ConnectionBeam: View {
    var active: Bool
    var color: Color = Palette.accent
    @Environment(\.animationsEnabled) private var animations
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let animate = active && animations && !reduceMotion && !SnapshotMode.isActive
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animate)) { context in
            let phase = animate ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4 : 0.35
            ZStack {
                BeamPath()
                    .stroke(color.opacity(active ? 0.35 : 0.12), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .blur(radius: 8)
                BeamPath()
                    .stroke(LinearGradient(colors: [color.opacity(active ? 0.9 : 0.25), Palette.accent2.opacity(active ? 0.8 : 0.2)],
                                           startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: active ? 2 : 1.4, lineCap: .round, dash: active ? [] : [4, 6]))
                if active {
                    ForEach(0..<3, id: \.self) { i in
                        let t = (phase + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        BeamPath()
                            .trim(from: max(0, t - 0.06), to: t)
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .shadow(color: color, radius: 6)
                            .opacity(sin(t * .pi))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Bogen vom Telefon (links unten) zum Notebook (rechts).
struct BeamPath: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY * 0.92))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.maxY * 0.62),
                   control1: CGPoint(x: r.minX + r.width * 0.35, y: r.maxY * 1.2),
                   control2: CGPoint(x: r.minX + r.width * 0.55, y: r.minY + r.height * 0.15))
        return p
    }
}

/// Großer Speicherring mit Belegung, frei/gesamt.
struct StorageRing: View {
    let storage: DeviceStorage
    var size: CGFloat = 132
    @State private var shown: Double = 0
    @Environment(\.animationsEnabled) private var animations

    private var tint: Color {
        let f = storage.usedFraction
        if f > 0.92 { return Palette.danger }
        if f > 0.8 { return Palette.warning }
        return storage.isRemovable ? Palette.accent2 : Palette.accent
    }

    var body: some View {
        ZStack {
            Circle().stroke(Palette.fieldFill, lineWidth: size * 0.075)
            Circle()
                .trim(from: 0, to: CGFloat(max(0.004, shown)))
                .stroke(AngularGradient(colors: [tint.opacity(0.6), tint], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * max(shown, 0.01))),
                        style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.5), radius: 8)
            VStack(spacing: 2) {
                Text("\(Int((storage.usedFraction * 100).rounded())) %")
                    .font(.display(size * 0.2, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                Text("belegt")
                    .font(.ui(size * 0.085, .medium))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            if animations && !SnapshotMode.isActive {
                withAnimation(.spring(response: 1.1, dampingFraction: 0.9).delay(0.15)) { shown = storage.usedFraction }
            } else {
                shown = storage.usedFraction
            }
        }
        .onChange(of: storage.usedFraction) { new in withAnimation(animations ? .bridgeSpring : nil) { shown = new } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(storage.displayName): \(Int(storage.usedFraction * 100)) Prozent belegt")
    }
}

/// Akkuanzeige.
struct BatteryGauge: View {
    let level: Int
    var outline: Color = Palette.textSecondary.opacity(0.6)

    private var color: Color { level <= 15 ? Palette.danger : (level <= 30 ? Palette.warning : Palette.success) }

    var body: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(outline, lineWidth: 1.2)
                    .frame(width: 26, height: 13)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: max(2, 22 * CGFloat(level) / 100), height: 9)
                    .padding(.leading, 2)
            }
            RoundedRectangle(cornerRadius: 1).fill(outline).frame(width: 2, height: 5).offset(x: -5)
            Text("\(level) %").font(.ui(13, .semibold)).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Akku \(level) Prozent")
    }
}

/// Mosaik aus echten Vorschaubildern (für Kacheln und leere Zustände).
struct ThumbnailMosaic: View {
    let items: [MediaItem]
    let device: DeviceConnection
    var columns = 2
    var rows = 2
    var spacing: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let w = (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let h = (geo.size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
            VStack(spacing: spacing) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: spacing) {
                        ForEach(0..<columns, id: \.self) { c in
                            let i = r * columns + c
                            Group {
                                if i < items.count {
                                    DeviceThumb(entry: items[i].entry, device: device, size: max(w, h), corner: 0)
                                } else {
                                    Palette.fieldFill
                                }
                            }
                            .frame(width: w, height: h)
                            .clipped()
                        }
                    }
                }
            }
        }
    }
}

/// Lädt ein Vorschaubild (für Telefonbildschirm und Notebook).
@MainActor
final class ThumbLoader: ObservableObject {
    @Published var images: [NSImage] = []
    private var loadedIDs: [String] = []

    func load(_ items: [MediaItem], device: DeviceConnection, limit: Int = 8) {
        let ids = items.prefix(limit).map(\.id)
        guard ids != loadedIDs else { return }
        loadedIDs = ids
        Task {
            var out: [NSImage] = []
            for item in items.prefix(limit) {
                if let img = await ThumbnailService.shared.thumbnail(for: item.entry, device: device) { out.append(img) }
            }
            images = out
        }
    }
}
