import SwiftUI
import AetherCore

// =============================================================================================
// Bildschirmfoto-Szenario für den Build: alle Bauformen der Geräte-Illustrationen nebeneinander (Vorderansicht und
// Aufsicht). Die Build-Rechner sind virtuelle Macs – ohne diese Galerie wären die Modellzeichnungen im Build nicht zu
// sehen. Nur im Fotomodus erreichbar; der Bildschirminhalt ist hier ein neutraler Verlauf (keine Messwerte).
// =============================================================================================

struct MacModelGalleryHost: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    /// Je Bauform und Größe ein Vertreter
    static let representatives = [
        "MacBookPro14,1", "MacBookPro15,2", "MacBookPro15,1", "MacBookPro16,1",
        "MacBookPro18,3", "MacBookPro18,1", "Mac17,11", "Mac17,10",
        "MacBookAir7,2", "MacBookAir8,1", "Mac14,2", "Mac14,15",
        "MacBook10,1", "iMac18,2", "iMac19,1", "iMacPro1,1",
        "iMac21,1", "Macmini8,1", "Macmini9,1", "Mac16,10",
        "Mac13,1", "MacPro7,1", "MacPro6,1",
    ]

    var body: some View {
        let theme = AetherTheme.resolve(settings: settings, systemIsDark: colorScheme == .dark, reduceTransparency: false)
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                ForEach(Self.representatives, id: \.self) { id in
                    if let model = MacModelCatalog.all[id] {
                        GalleryCell(model: model)
                    }
                }
            }
            .padding(20)
        }
        // feste Mindestgröße: sonst verkleinert NSHostingView das Fenster auf die kleinste passende Breite
        .frame(minWidth: 1600, maxWidth: .infinity, minHeight: 1800, maxHeight: .infinity)
        .background(theme.backgroundTop)
        .environment(\.aether, theme)
        .foregroundStyle(theme.textPrimary)
    }
}

private struct GalleryCell: View {
    @Environment(\.aether) private var theme
    let model: MacModelInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DeviceArt(model: model, kind: .unknown) {
                LinearGradient(colors: [theme.accent.opacity(0.55), Color(red: 0.05, green: 0.06, blue: 0.12)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .frame(height: 200)
            HStack(alignment: .center, spacing: 12) {
                MacTopArt(model: model)
                    .aspectRatio(MacTopArt.aspect(model), contentMode: .fit)
                    .frame(width: 200, height: 130)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.displayName).font(Typo.bodyMedium).lineLimit(2)
                    Text(model.identifier).font(Typo.mono).foregroundStyle(theme.textSecondary)
                    Text(model.design.rawValue).font(Typo.caption).foregroundStyle(theme.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.fieldFill))
    }
}
