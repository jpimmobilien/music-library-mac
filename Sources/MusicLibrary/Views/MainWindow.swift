import SwiftUI
import AppKit
import MLCore

/// Höhen der schwebenden Leisten (Inhalte beginnen darunter und laufen weich darunter aus).
enum Chrome {
    static let topPadding: CGFloat = 10
    static let contentTop: CGFloat = topPadding + Metrics.navBarHeight + 14
    static let trafficLightsWidth: CGFloat = 78
    static func contentBottom(miniPlayer: Bool) -> CGFloat { miniPlayer ? Metrics.miniPlayerHeight + 34 : 24 }
}

/// Hauptfenster: Bibliothek mit schwebender Glas-Navigation oben, Mini-Player-Kapsel unten und – darüber –
/// dem Vollbild-Player, der wie unter Android von unten hereingleitet, während die Bibliothek zurücktritt.
struct MainWindow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors

    var body: some View {
        let open = model.playerOpen && player.current != nil
        ZStack {
            Color.black.ignoresSafeArea()
            LibraryLayer()
                .scaleEffect(open ? 0.94 : 1)
                .clipShape(RoundedRectangle(cornerRadius: open ? 30 : 0, style: .continuous))
                .overlay(
                    Color.black.opacity(open ? (colors.dark ? 0.55 : 0.38) : 0)
                        .allowsHitTesting(false)
                        .clipShape(RoundedRectangle(cornerRadius: open ? 30 : 0, style: .continuous))
                )
                .allowsHitTesting(!open)
                .accessibilityHidden(open)
            if open {
                FullPlayerView()
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .transition(.move(edge: .bottom))
                    .zIndex(2)
            }
        }
        .animation(Motion.playerSpring, value: open)
        .background(WindowConfigurator())
        .sheet(isPresented: Binding(get: { model.addToPlaylistUids != nil }, set: { if !$0 { model.addToPlaylistUids = nil } })) {
            AddToPlaylistSheet(uids: model.addToPlaylistUids ?? [])
                .environmentObject(model)
                .musicTheme(glass: model.settings.glassEffects)
        }
    }
}

/// Bibliotheksebene (alles außer dem Vollbild-Player).
private struct LibraryLayer: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors

    var body: some View {
        let showMini = player.current != nil
        ZStack(alignment: .top) {
            AmbientBackground()
            HStack(spacing: 0) {
                SectionHost()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let panel = model.sidePanel {
                    SidePanelView(panel: panel)
                        .frame(width: 344)
                        .padding(.top, Chrome.contentTop - 4)
                        .padding(.bottom, Chrome.contentBottom(miniPlayer: showMini) - 6)
                        .padding(.trailing, 14)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(Motion.easeOut(Motion.medium), value: model.sidePanel)

            // Oberer Rand: Inhalte laufen weich unter die Navigation
            EdgeFade(top: true, strength: 0.86)
                .frame(height: Chrome.contentTop + 6)
                .frame(maxWidth: .infinity, alignment: .top)

            NavBar()
                .padding(.top, Chrome.topPadding)

            // Unten: weicher Auslauf, Mitteilungen und Mini-Player
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                EdgeFade(top: false, strength: 0.72)
                    .frame(height: showMini ? Metrics.miniPlayerHeight + 56 : 36)
            }
            .allowsHitTesting(false)

            VStack(spacing: 10) {
                Spacer(minLength: 0)
                ToastStack()
                if showMini {
                    MiniPlayerBar()
                        .frame(maxWidth: 940)
                        .padding(.horizontal, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, 14)
            .animation(Motion.easeOut(Motion.medium), value: showMini)

            ScanBanner()
                .padding(.top, Chrome.contentTop - 6)
                .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

/// Inhalt des aktiven Bereichs (Übersicht oder Detailansicht).
struct SectionHost: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let destination = model.currentDestination
        ZStack {
            switch destination {
            case .album(let key)?: AlbumDetailView(albumKey: key)
            case .artist(let key)?: ArtistDetailView(artistKey: key)
            case .genre(let key)?: GenreDetailView(genreKey: key)
            case .playlist(let id)?: PlaylistDetailView(playlistID: id)
            case .smartPlaylist(let id)?: SmartPlaylistDetailView(smartID: id)
            case .history?: HistoryView()
            case .duplicates?: DuplicatesView()
            case nil:
                switch model.section {
                case .tracks: TracksView()
                case .albums: AlbumsView()
                case .playlists: PlaylistsView()
                case .artists: ArtistsView()
                case .genres: GenresView()
                case .favorites: FavoritesView()
                }
            }
        }
        .id(sectionID(destination))
        .transition(.opacity.combined(with: .offset(x: destination == nil ? -12 : 12)))
        .animation(Motion.easeOut(Motion.medium), value: sectionID(destination))
    }

    private func sectionID(_ d: Destination?) -> String { "\(model.section.rawValue)/\(String(describing: d))" }
}

/// Schwebende Glas-Navigation mit genau sechs Bereichen und gleitender Rosé-Linse (Android `FloatingNavBar`).
struct NavBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        let entries = LibrarySection.allCases
        let index = CGFloat(entries.firstIndex(of: model.section) ?? 0)
        GeometryReader { geo in
            let itemWidth = max(0, geo.size.width - 10) / CGFloat(max(entries.count, 1))
            ZStack(alignment: .leading) {
                // Linse unter dem aktiven Eintrag
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(colors.accentSoft)
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [colors.glassEdgeLight.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 0.7))
                    .frame(width: itemWidth, height: geo.size.height - 10)
                    .offset(x: 5 + itemWidth * index)
                    .animation(Motion.lensSpring, value: index)
                HStack(spacing: 0) {
                    ForEach(entries, id: \.self) { s in
                        NavItem(section: s, selected: s == model.section) { model.select(s) }
                            .frame(width: itemWidth, height: geo.size.height - 10)
                    }
                }
                .padding(.horizontal, 5)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(width: 560, height: Metrics.navBarHeight)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.bar, style: .continuous), elevated: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bereiche")
    }
}

private struct NavItem: View {
    @Environment(\.musicColors) private var colors
    let section: LibrarySection
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let fg = selected ? colors.accentText : colors.textPrimary.opacity(hover ? 0.9 : 0.72)
        Button(action: action) {
            VStack(spacing: 1) {
                Icon(section.icon(selected: selected), size: 19, color: fg)
                Text(section.label)
                    .font(Typo.inter(10, selected ? .semibold : .medium))
                    .foregroundColor(fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.94))
        .onHover { hover = $0 }
        .help("\(section.label) (⌘\(section.shortcutDigit))")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .animation(Motion.easeOut(Motion.short), value: selected)
    }
}

/// Mitteilungen (Android-Snackbar): dunkle, gerundete Karte mit rosé Aktion.
struct ToastStack: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        VStack(spacing: 8) {
            ForEach(model.toasts) { t in
                HStack(spacing: 12) {
                    if t.isError { Icon(Icons.warning, size: 16, color: Color(argb: 0xFFFF8FA6)) }
                    Text(t.text)
                        .textStyle(Typo.bodyMedium)
                        .foregroundColor(Color(argb: 0xFFF6F2F3))
                        .lineLimit(2)
                    if let label = t.actionLabel {
                        Button(label) {
                            t.action?()
                            model.toasts.removeAll { $0.id == t.id }
                        }
                        .buttonStyle(.plain)
                        .font(Typo.inter(13, .semibold))
                        .foregroundColor(Color(argb: 0xFFFF8FA6))
                    }
                    Button {
                        model.toasts.removeAll { $0.id == t.id }
                    } label: {
                        Icon(Icons.clear, size: 13, color: Color(argb: 0xFFF6F2F3).opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Schließen")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color(argb: colors.dark ? 0xF02B2627 : 0xF02B2729)))
                .shadow(color: Color.black.opacity(0.25), radius: 14, y: 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: 560)
        .animation(Motion.easeOut(Motion.medium), value: model.toasts)
    }
}

/// Fortschritt des Einlesens (dezent unter der Navigation).
struct ScanBanner: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        Group {
            switch model.scanState {
            case .running(let done, let total, let folder):
                let progressText: String = total > 0 ? "Musik wird eingelesen … \(done) von \(total)"
                    : (folder.isEmpty ? "Musikordner werden geprüft …" : "Durchsuche „\(folder)“ …")
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                    Text(progressText)
                        .textStyle(Typo.labelMedium)
                        .foregroundColor(colors.textSecondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 30)
                .glassSurface(Capsule(), strong: true)
                .transition(.opacity.combined(with: .move(edge: .top)))
            case .failed(let message):
                HStack(spacing: 8) {
                    Icon(Icons.warning, size: 14, color: colors.danger)
                    Text("Einlesen fehlgeschlagen: \(message)")
                        .textStyle(Typo.labelMedium)
                        .foregroundColor(colors.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .frame(height: 30)
                .glassSurface(Capsule(), strong: true)
            default:
                EmptyView()
            }
        }
        .animation(Motion.easeOut(), value: model.scanState)
    }
}

/// Fensterkonfiguration: transparente Titelleiste, Inhalt bis unter die Ampel, Mindestgröße.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            // Kein isMovableByWindowBackground: sonst würden Ziehgesten (Regler, Ziehen & Ablegen)
            // das Fenster verschieben. Verschoben wird über die (unsichtbare) Titelleiste oben.
            window.minSize = NSSize(width: 900, height: 620)
            window.tabbingMode = .disallowed
            window.collectionBehavior.insert(.fullScreenPrimary)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
