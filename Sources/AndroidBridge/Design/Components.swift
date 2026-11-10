import SwiftUI
import AppKit
import ABCore

extension FileKind {
    var tint: Color {
        switch self {
        case .folder: return Palette.tint(for: .folder)
        case .photo: return Palette.tint(for: .photo)
        case .video: return Palette.tint(for: .video)
        case .audio: return Palette.tint(for: .audio)
        case .document: return Palette.tint(for: .document)
        case .archive: return Palette.tint(for: .archive)
        case .apk: return Palette.tint(for: .apk)
        case .other: return Palette.tint(for: .other)
        }
    }
}

/// Farbiges Symbol einer Dateiart.
struct FileGlyph: View {
    let kind: FileKind
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: kind.symbolName)
            .font(.ui(size * 0.82, .medium))
            .foregroundStyle(kind.tint)
            .frame(width: size + 4, height: size + 4)
    }
}

/// Runde Kachel mit Symbol.
struct IconTile: View {
    let symbol: String
    var tint: Color = Palette.accent
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6)
            Image(systemName: symbol)
                .font(.ui(size * 0.46, .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: tint.opacity(0.28), radius: 6, y: 2)
    }
}

/// Zustand eines Geräts als Kapsel.
struct StatusPill: View {
    let state: ConnectionState
    @Environment(\.animationsEnabled) private var animations

    private var color: Color {
        switch state {
        case .connected: return Palette.success
        case .waitingForFileTransfer, .waitingForAuthorization, .busy: return Palette.warning
        case .interrupted: return Palette.danger
        case .disconnected: return .secondary
        default: return Palette.bridgeBlue
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if state.isWorking {
                ProgressView().controlSize(.mini)
            } else {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(state.title)
                .font(.ui(11.5, .semibold))
                .foregroundStyle(state == .disconnected ? .secondary : .primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.13)))
        .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.6))
        .animation(animations ? .bridgeQuick : nil, value: state)
    }
}

/// Belegungsbalken.
struct CapacityBar: View {
    let fraction: Double
    var tint: Color = Palette.accent
    var height: CGFloat = 8
    @State private var shown: Double = 0
    @Environment(\.animationsEnabled) private var animations

    private var barColor: Color {
        fraction > 0.92 ? Palette.danger : (fraction > 0.8 ? Palette.warning : tint)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [barColor.opacity(0.85), barColor], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * CGFloat(min(max(shown, 0), 1))))
                    .opacity(shown > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .onAppear {
            if animations {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.9).delay(0.1)) { shown = fraction }
            } else {
                shown = fraction
            }
        }
        .onChange(of: fraction) { new in
            withAnimation(animations ? .bridgeSpring : nil) { shown = new }
        }
    }
}

/// Speicherkarte (interner Speicher, SD-Karte …).
struct StorageCard: View {
    let storage: DeviceStorage
    var compact = false
    var action: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        Button {
            action?()
        } label: {
            VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                HStack(spacing: 12) {
                    IconTile(symbol: storage.symbolName, tint: storage.isRemovable ? Palette.bridgeBlue : Palette.accent, size: compact ? 30 : 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(storage.displayName)
                            .font(.ui(compact ? 13 : 15, .semibold))
                            .lineLimit(1)
                        Text(storage.typeName + (storage.isReadOnly ? " · schreibgeschützt" : ""))
                            .font(.ui(11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if action != nil {
                        Image(systemName: "chevron.right")
                            .font(.ui(12, .semibold))
                            .foregroundStyle(.tertiary)
                            .opacity(hovering ? 1 : 0.5)
                    }
                }
                if storage.capacity > 0 {
                    CapacityBar(fraction: storage.usedFraction, tint: storage.isRemovable ? Palette.bridgeBlue : Palette.accent)
                    HStack {
                        Text("\(ByteFormat.string(storage.used)) belegt")
                        Spacer()
                        Text("\(ByteFormat.string(storage.free)) frei von \(ByteFormat.string(storage.capacity))")
                    }
                    .font(.ui(11, .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                } else {
                    Text("Kapazität nicht verfügbar")
                        .font(.ui(11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(compact ? 14 : 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 18, elevated: hovering)
        .scaleEffect(hovering && action != nil ? 1.01 : 1)
        .animation(.bridgeQuick, value: hovering)
        .onHover { hovering = $0 }
    }
}

/// Leerer Zustand mit Symbol, Text und optionalen Aktionen.
struct EmptyStateView<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        // Passt sich der Höhe an: große Illustration, kleine Illustration oder nur Text –
        // so ragt ein leerer Zustand in kleinen Fenstern nie unter die Gerätekapsel.
        ViewThatFits(in: .vertical) {
            layout(illustration: 64, titleSize: 24, spacing: 12, padding: 30)
            layout(illustration: 40, titleSize: 20, spacing: 10, padding: 18)
            layout(illustration: nil, titleSize: 17, spacing: 6, padding: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .revealOnAppear()
    }

    private func layout(illustration: CGFloat?, titleSize: CGFloat, spacing: CGFloat, padding: CGFloat) -> some View {
        VStack(spacing: spacing) {
            if let illustration {
                EmptyIllustration(symbol: symbol, size: illustration)
            }
            Text(title)
                .font(.display(titleSize, .bold))
                .tracking(-0.6)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.ui(illustration == nil ? 13 : 14.5))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .fixedSize(horizontal: false, vertical: true)
            actions()
                .padding(.top, 4)
        }
        .padding(padding)
    }
}

/// Leerer Zustand wie in Finder und Fotos: ein ruhiges Systemsymbol in Grau – keine Platzhalter-Grafik.
struct EmptyIllustration: View {
    let symbol: String
    var size: CGFloat = 64

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .light))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Palette.textTertiary)
            .frame(height: size * 1.15)
            .accessibilityHidden(true)
    }
}

private struct HillShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY + 6))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.midY), control: CGPoint(x: r.width * 0.25, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY - 4), control: CGPoint(x: r.width * 0.75, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(symbol: String, title: String, message: String) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}

/// Hinweisbox für Fehler mit Erklärung, Empfehlung und technischen Details.
struct IssueBanner: View {
    let issue: ABIssue
    var primaryTitle: String?
    var primaryAction: (() -> Void)?
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?
    var dismiss: (() -> Void)?
    @State private var showDetails = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: issue.symbolName)
                .font(.ui(22, .semibold))
                .foregroundStyle(Palette.warning)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 6) {
                Text(issue.title).font(.ui(14, .semibold))
                Text(issue.message).font(.ui(12.5)).foregroundStyle(.secondary)
                if let r = issue.recommendation {
                    Label(r, systemImage: "lightbulb")
                        .font(.ui(12.5))
                        .labelStyle(.titleAndIcon)
                }
                HStack(spacing: 8) {
                    if let primaryTitle, let primaryAction {
                        Button(primaryTitle, action: primaryAction).buttonStyle(GlassButtonStyle(prominent: true))
                    }
                    if let secondaryTitle, let secondaryAction {
                        Button(secondaryTitle, action: secondaryAction).buttonStyle(GlassButtonStyle())
                    }
                    if issue.technical != nil {
                        Button(showDetails ? "Details ausblenden" : "Technische Details") { showDetails.toggle() }
                            .buttonStyle(.link)
                            .font(.ui(11.5))
                    }
                }
                .padding(.top, 2)
                if showDetails, let t = issue.technical {
                    Text(t)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
            if let dismiss {
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Schließen")
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 16, strong: true)
    }
}

/// Abschnittsüberschrift.
struct SectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(Typo.sectionLabel).foregroundStyle(Palette.textSecondary)
                .tracking(0.7)
            if let subtitle { Text(subtitle).font(.ui(12)).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Fortschrittsring.
struct ProgressRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 4
    var tint: Color = Palette.accent

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(fraction, 0.001), 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: fraction)
        }
    }
}

/// Gezeichnetes Telefon (eigene, neutrale Form) – für Verbindungsanimation und Anleitung.
struct PhoneShapeView<Screen: View>: View {
    var width: CGFloat = 92
    var tint: Color = Palette.accent
    @ViewBuilder var screen: () -> Screen

    var body: some View {
        let height = width * 2.05
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.2, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x3A3F47), Color(hex: 0x1E2126)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            RoundedRectangle(cornerRadius: width * 0.17, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.35), Palette.bridgeBlue.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(width * 0.045)
            screen()
                .frame(width: width * 0.86, height: height * 0.9)
                .clipShape(RoundedRectangle(cornerRadius: width * 0.16, style: .continuous))
            Circle().fill(Color.black.opacity(0.65)).frame(width: width * 0.07).offset(y: -height * 0.44)
        }
        .frame(width: width, height: height)
    }
}

/// Pulsierende Ringe während der Verbindung.
struct PulseRings: View {
    var tint: Color = Palette.accent
    var active: Bool
    @State private var phase = false
    @Environment(\.animationsEnabled) private var animations

    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .stroke(tint.opacity(0.35), lineWidth: 1.5)
                    .scaleEffect(phase ? 1.0 + CGFloat(i) * 0.28 + 0.4 : 0.7)
                    .opacity(phase ? 0 : 0.8)
                    .animation(active && animations ? .easeOut(duration: 2.1).repeatForever(autoreverses: false).delay(Double(i) * 0.5) : .default,
                               value: phase)
            }
        }
        .onAppear { phase = active && animations }
        .onChange(of: active) { new in phase = new && animations }
    }
}
