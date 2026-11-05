import SwiftUI
import AppKit
import MLCore

// MARK: - Modern Glass (v2)

/// Modern Glass – großes Cover, das auf geschichtetem Glas schwebt: weiches Lichtfeld in den Coverfarben
/// dahinter, eine echte Glasplatte (Liquid Glass bzw. Hintergrundunschärfe, unbewegt), eine zweite, leicht
/// gedrehte Scheibe, Glanzlicht und Spiegelung. Beim Überfahren mit der Maus neigt sich das Cover leicht
/// (Parallaxe); in der Pause tritt es etwas zurück und das Licht wird ruhiger.
///
/// Leistung: keine Unschärfe auf bewegten Ebenen; Schatten liegen auf eigenen, ruhenden Formen.
struct ModernGlassHero: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    let side: CGFloat
    @ObservedObject var artwork: NowPlayingArtwork
    /// Ruhende Vorschau (Design-Auswahl).
    var still: Bool = false
    /// Neigung −1 … 1 in beiden Achsen.
    @State private var tilt: CGSize = .zero

    var body: some View {
        let playing = still || player.isPlaying || model.settings.animationLevel == .off
        let lights = AuroraColors(palette: artwork.palette, dark: colors.dark)
        let allowTilt = !still && PlayerMotionPolicy.continuous(model.settings)
        let cover = side * 0.68
        ZStack {
            GlassLightField(lights: lights, side: side, dark: colors.dark, intensity: playing ? 1 : 0.55)
            GlassPlates(side: side, tilt: tilt, dark: colors.dark, realGlass: !still)
            FloatingCover(image: artwork.image, category: GenreStyle.category(player.current?.genres.first), loading: artwork.loading,
                          coverKey: artwork.key ?? "-", side: side, cover: cover, tilt: tilt, playing: playing, dark: colors.dark)
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            guard allowTilt else { return }
            if case .active(let p) = phase {
                let half = max(side / 2, 1)
                let x = max(-1, min(1, (p.x - half) / half))
                let y = max(-1, min(1, (p.y - half) / half))
                withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.82)) { tilt = CGSize(width: x, height: y) }
            } else {
                withAnimation(Motion.gentleSpring) { tilt = .zero }
            }
        }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.55), value: playing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(player.current.map { "Albumcover „\($0.album ?? $0.displayTitle)“ auf Glas" } ?? "Albumcover auf Glas")
    }
}

/// Weiches Lichtfeld in den Coverfarben (drei radiale Verläufe, keine Unschärfe).
private struct GlassLightField: View {
    let lights: AuroraColors
    let side: CGFloat
    let dark: Bool
    let intensity: Double

    var body: some View {
        let a: Double = (dark ? 0.62 : 0.48) * intensity
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [lights.primary.opacity(a), lights.primary.opacity(0)], center: .center, startRadius: 0, endRadius: side * 0.5))
                .frame(width: side, height: side)
                .offset(x: -side * 0.14, y: -side * 0.12)
            Circle()
                .fill(RadialGradient(colors: [lights.secondary.opacity(a * 0.85), lights.secondary.opacity(0)], center: .center, startRadius: 0, endRadius: side * 0.45))
                .frame(width: side * 0.9, height: side * 0.9)
                .offset(x: side * 0.17, y: side * 0.14)
            Circle()
                .fill(RadialGradient(colors: [lights.tertiary.opacity(a * 0.55), lights.tertiary.opacity(0)], center: .center, startRadius: 0, endRadius: side * 0.36))
                .frame(width: side * 0.72, height: side * 0.72)
                .offset(x: side * 0.12, y: -side * 0.2)
        }
        .frame(width: side, height: side)
        .animation(.easeInOut(duration: 0.9), value: lights)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Zwei Glasscheiben: hinten eine leicht gedrehte, helle Scheibe (Parallaxe), darüber eine ruhende
/// echte Glasplatte (Liquid Glass ab macOS 26, sonst Hintergrundunschärfe – sie bewegt sich nie).
private struct GlassPlates: View {
    let side: CGFloat
    let tilt: CGSize
    let dark: Bool
    /// Echte Glasplatte (in kleinen Vorschauen nur angedeutet).
    let realGlass: Bool

    var body: some View {
        let back = RoundedRectangle(cornerRadius: side * 0.085, style: .continuous)
        let plate = RoundedRectangle(cornerRadius: side * 0.08, style: .continuous)
        let edge = LinearGradient(colors: [Color.white.opacity(dark ? 0.32 : 0.85), Color.white.opacity(dark ? 0.04 : 0.25), Color.white.opacity(dark ? 0.16 : 0.6)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        ZStack {
            back
                .fill(Color.white.opacity(dark ? 0.045 : 0.22))
                .overlay(back.strokeBorder(edge, lineWidth: 1))
                .frame(width: side * 0.78, height: side * 0.8)
                .rotationEffect(.degrees(-7))
                .offset(x: -side * 0.05 - tilt.width * 7, y: -side * 0.015 - tilt.height * 7)
            Group {
                if realGlass {
                    Color.clear
                        .frame(width: side * 0.84, height: side * 0.84)
                        .glassSurface(plate, strong: false)
                } else {
                    plate
                        .fill(Color.white.opacity(dark ? 0.08 : 0.42))
                        .overlay(plate.strokeBorder(edge, lineWidth: 1))
                        .frame(width: side * 0.84, height: side * 0.84)
                }
            }
            .offset(y: side * 0.035)
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Das schwebende Cover mit Glanzlicht, Lichtkante, ruhendem Schatten und Spiegelung.
private struct FloatingCover: View {
    let image: NSImage?
    let category: GenreCategory
    let loading: Bool
    let coverKey: String
    let side: CGFloat
    let cover: CGFloat
    let tilt: CGSize
    let playing: Bool
    let dark: Bool

    var body: some View {
        let corner = cover * 0.07
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let reflection = side * 0.13
        let lift: CGFloat = playing ? 1 : 0.9
        ZStack(alignment: .top) {
            // Ruhender Schatten (bewegt sich nicht mit der Neigung → wird nicht ständig neu berechnet)
            shape
                .fill(Color.black.opacity(dark ? 0.55 : 0.22))
                .frame(width: cover * 0.92, height: cover * 0.92)
                .shadow(color: Color.black.opacity(dark ? 0.55 : 0.28), radius: side * 0.05, x: 0, y: side * 0.045)
                .offset(y: cover * 0.06)
                .scaleEffect(lift)
            VStack(spacing: side * 0.012) {
                CoverFace(image: image, category: category, loading: loading, cover: cover, corner: corner, tilt: tilt, dark: dark)
                    .rotation3DEffect(.degrees(Double(-tilt.height) * 7), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
                    .rotation3DEffect(.degrees(Double(tilt.width) * 7), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
                // Spiegelung auf der Glasplatte
                ArtworkBox(image: image, category: category, cornerRadius: corner, iconFraction: 0.4, loading: loading)
                    .frame(width: cover, height: cover)
                    .scaleEffect(x: 1, y: -1)
                    .frame(width: cover, height: reflection, alignment: .top)
                    .clipped()
                    .mask(LinearGradient(colors: [Color.white.opacity(dark ? 0.32 : 0.26), Color.white.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .offset(x: tilt.width * 9, y: tilt.height * 9)
            .scaleEffect(lift, anchor: UnitPoint(x: 0.5, y: 0.45))
        }
        .frame(width: side, height: side * 0.86 + reflection, alignment: .top)
        .offset(y: side * 0.1)
        .frame(width: side, height: side)
        .id(coverKey)
        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)), removal: .opacity))
        .animation(.easeOut(duration: 0.42), value: coverKey)
    }
}

/// Cover-Fläche mit Glanzlicht (wandert mit der Neigung) und heller Lichtkante.
private struct CoverFace: View {
    let image: NSImage?
    let category: GenreCategory
    let loading: Bool
    let cover: CGFloat
    let corner: CGFloat
    let tilt: CGSize
    let dark: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let sx: CGFloat = 0.1 - tilt.width * 0.25
        let sy: CGFloat = 0.0 - tilt.height * 0.25
        ArtworkBox(image: image, category: category, cornerRadius: corner, iconFraction: 0.4, loading: loading)
            .frame(width: cover, height: cover)
            .overlay(
                LinearGradient(stops: [
                    .init(color: Color.white.opacity(dark ? 0.20 : 0.26), location: 0),
                    .init(color: Color.white.opacity(0.04), location: 0.38),
                    .init(color: .clear, location: 0.55),
                ], startPoint: UnitPoint(x: sx, y: sy), endPoint: UnitPoint(x: 0.9 - tilt.width * 0.2, y: 0.95 - tilt.height * 0.2))
                .clipShape(shape)
                .blendMode(.screen)
                .allowsHitTesting(false)
            )
            .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.06), Color.white.opacity(0.22)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
    }
}
