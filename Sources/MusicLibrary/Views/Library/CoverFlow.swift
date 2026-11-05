import SwiftUI
import AppKit
import MLCore

// Cover Flow: räumliches Karussell. Das Cover in der Mitte steht groß und frontal, die Nachbarn sind um
// knapp 60° gedreht und überlappen, darunter eine zarte Spiegelung. Bedienung mit Trackpad, Mausrad,
// Ziehen, Pfeiltasten und Positionsregler; rastet ohne macOS-14-Schnittstellen auf das nächste Cover ein.
// Gezeichnet werden nur die Cover um den Fokus (± `CoverFlowController.visibleRange`), nie Tausende.

/// Zustand und Eingaben des Cover Flow (Position als Kommazahl, damit Ziehen und Scrollen fließend sind).
@MainActor
final class CoverFlowController: ObservableObject {
    static let visibleRange = 12
    /// Zuletzt gezeigtes Cover je Bereich (solange die App läuft).
    private static var memory: [String: Double] = [:]

    @Published var position: Double = 0
    var count = 0
    var hovering = false
    /// Vollbild-Player offen: keine Tasten/Scrollereignisse abfangen.
    var suspended = false
    /// Fenster des Cover Flow – Ereignisse anderer Fenster (Einstellungen, Mini-Player) bleiben unberührt.
    weak var window: NSWindow?
    var animation: Animation? = Motion.gentleSpring
    /// Punkte Scrollweg je Cover (Trackpad).
    var scrollStep: CGFloat = 60
    private var key = ""
    private var scrollMonitor: Any?
    private var keyMonitor: Any?
    private var dragStart: Double?
    private var lastWheel: TimeInterval = 0
    private var velocity: Double = 0
    private var pendingSnap: DispatchWorkItem?

    var focus: Int {
        guard count > 0 else { return 0 }
        return min(max(Int(position.rounded()), 0), count - 1)
    }

    func attach(count: Int, key: String) {
        self.count = count
        self.key = key
        let saved = Self.memory[key] ?? 0
        position = min(max(saved, 0), Double(max(count - 1, 0)))
        installMonitors()
    }

    func detach() {
        Self.memory[key] = Double(focus)
        if let m = scrollMonitor { NSEvent.removeMonitor(m) }
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        scrollMonitor = nil
        keyMonitor = nil
        pendingSnap?.cancel()
        pendingSnap = nil
        hovering = false
    }

    func updateCount(_ n: Int) {
        count = n
        let maxPosition = Double(max(n - 1, 0))
        if position > maxPosition { position = maxPosition }
    }

    func go(to index: Int, animation: Animation?) {
        guard count > 0 else { return }
        let target = Double(min(max(index, 0), count - 1))
        if let animation, abs(target - position) <= Double(Self.visibleRange) {
            withAnimation(animation) { position = target }
        } else {
            position = target
        }
    }

    func step(_ delta: Int) {
        go(to: focus + delta, animation: animation)
    }

    func snap(using animation: Animation?, velocity v: Double = 0) {
        let limited = max(-8, min(8, v))
        go(to: Int((position + limited).rounded()), animation: animation)
    }

    /// Positionsregler: springt ohne Animation.
    func scrub(to value: Double) {
        guard count > 0 else { return }
        position = min(max(value.rounded(), 0), Double(count - 1))
    }

    // MARK: Ziehen

    func drag(translation: CGFloat, step: CGFloat) {
        guard count > 1 else { return }
        if dragStart == nil {
            dragStart = position
            pendingSnap?.cancel()
        }
        let start = dragStart ?? position
        position = clamped(start - Double(translation / max(step, 1)))
    }

    func endDrag(predicted: CGFloat, step: CGFloat) {
        let start = dragStart ?? position
        dragStart = nil
        let target = clamped(start - Double(predicted / max(step, 1)))
        go(to: Int(target.rounded()), animation: animation)
    }

    /// Etwas Spiel an den Enden (gummiartig), danach rastet es ein.
    private func clamped(_ p: Double) -> Double {
        min(max(p, -0.4), Double(max(count - 1, 0)) + 0.4)
    }

    // MARK: Trackpad, Mausrad, Pfeiltasten

    private func installMonitors() {
        if scrollMonitor == nil {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.hovering, !self.suspended else { return event }
                if let window = self.window, event.window !== window { return event }
                self.handleScroll(event)
                return nil
            }
        }
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handleKey(event) ? nil : event
            }
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if let responder = event.window?.firstResponder, responder is NSText || responder is NSTextView { return false }
        guard !suspended, event.window?.isKeyWindow == true, count > 0 else { return false }
        if let window, event.window !== window { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
        guard flags.isEmpty else { return false }
        switch event.keyCode {
        case 123: // ←
            step(-1)
            return true
        case 124: // →
            step(1)
            return true
        default:
            return false
        }
    }

    private func handleScroll(_ event: NSEvent) {
        guard count > 1 else { return }
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        let delta: CGFloat = abs(dx) >= abs(dy) ? dx : dy
        if !event.hasPreciseScrollingDeltas {
            // Mausrad: ein Cover je Raste
            let now = ProcessInfo.processInfo.systemUptime
            guard delta != 0, now - lastWheel > 0.05 else { return }
            lastWheel = now
            step(delta > 0 ? -1 : 1)
            return
        }
        // Schwung nach dem Loslassen ignorieren – es wird stattdessen eingerastet
        if !event.momentumPhase.isEmpty { return }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            velocity = 0
            pendingSnap?.cancel()
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            snap(using: animation, velocity: velocity * 5)
            velocity = 0
            return
        }
        let change = -Double(delta / max(scrollStep, 1))
        position = clamped(position + change)
        velocity = change
        if event.phase.isEmpty { scheduleSnap() }
    }

    private func scheduleSnap() {
        pendingSnap?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.snap(using: self.animation)
        }
        pendingSnap = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }
}

/// Cover-Flow-Ansicht für beliebige Einträge (Titel, Alben, Interpreten, Genres, Playlists).
struct CoverFlowView<MenuContent: View>: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.musicColors) private var colors
    @Environment(\.libraryViewport) private var viewport
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let count: Int
    let memoryKey: String
    let options: LibraryViewOptions
    let item: (Int) -> LibraryItem
    /// Doppelklick bzw. Eingabetaste auf das Cover in der Mitte.
    let activate: (Int) -> Void
    /// Abspielen (`false`) bzw. Mischen (`true`).
    let play: (Int, Bool) -> Void
    var openLabel: String? = nil
    var open: ((Int) -> Void)? = nil
    @ViewBuilder let menu: (Int) -> MenuContent
    @StateObject private var flow = CoverFlowController()

    var body: some View {
        let side = coverSide
        let focus = flow.focus
        VStack(spacing: 0) {
            stage(side)
                .frame(height: side * 1.4 + 24)
            caption(focus)
                .padding(.top, 4)
            controls(focus)
                .padding(.top, 14)
        }
        .padding(.top, 6)
        .background(HostWindowReader { window in flow.window = window })
        .onAppear { setUp() }
        .onDisappear { flow.detach() }
        .onChange(of: count) { n in flow.updateCount(n) }
        .onChange(of: flow.focus) { _ in registerKeyboard() }
        .onChange(of: model.playerOpen) { open in flow.suspended = open }
    }

    /// Kantenlänge des mittleren Covers: Covergröße der Ansicht, begrenzt durch Fensterhöhe und -breite.
    private var coverSide: CGFloat {
        let wanted: CGFloat = CGFloat(options.coverSize) * 1.3
        let byHeight: CGFloat = max(240, viewport.height - 340) / 1.4
        let byWidth: CGFloat = max(160, (viewport.width - Spacing.gutter * 2) * 0.34)
        return max(140, min(wanted, byHeight, byWidth))
    }

    private var snapAnimation: Animation? {
        LibraryMotion.snap(model.settings.animationLevel, reduceMotion: reduceMotion)
    }

    // MARK: Bühne

    private func stage(_ side: CGFloat) -> some View {
        let position = flow.position
        let focus = flow.focus
        let lower = max(0, focus - CoverFlowController.visibleRange)
        let upper = min(count, focus + CoverFlowController.visibleRange + 1)
        let indices: [Int] = lower < upper ? Array(lower..<upper) : []
        return GeometryReader { geo in
            let half: CGFloat = geo.size.width / 2
            ZStack {
                ForEach(indices, id: \.self) { i in
                    card(i, position: position, side: side, half: half)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(dragGesture(side))
        .onHover { inside in flow.hovering = inside }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cover Flow")
    }

    private func card(_ i: Int, position: Double, side: CGFloat, half: CGFloat) -> some View {
        let d: Double = Double(i) - position
        let distance: Double = abs(d)
        let t: Double = max(-1, min(1, d))
        let near: CGFloat = side * 0.62
        let gap: CGFloat = side * 0.2
        let direction: CGFloat = d < 0 ? -1 : 1
        let x: CGFloat = distance <= 1 ? CGFloat(d) * near : direction * (near + CGFloat(distance - 1) * gap)
        let edge: CGFloat = abs(x) + side * 0.3
        let fade: Double = edge > half ? max(0, 1 - Double((edge - half) / (side * 0.45))) : 1
        let angle: Double = t * 58
        let scale: CGFloat = 1 - 0.12 * CGFloat(min(distance, 1))
        let entry = item(i)
        return CoverFlowCard(item: entry, side: side, reflection: distance < 6, focused: distance < 0.5,
                             playing: entry.current && player.isPlaying)
            .equatable()
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: .center, anchorZ: 0, perspective: 0.55)
            .scaleEffect(scale)
            .offset(x: x)
            .opacity(fade)
            .zIndex(-distance)
            .onTapGesture { tap(i) }
            .contextMenu { menu(i) }
            .accessibilityAddTraits(distance < 0.5 ? [.isButton, .isSelected] : .isButton)
    }

    private func dragGesture(_ side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { g in flow.drag(translation: g.translation.width, step: side * 0.32) }
            .onEnded { g in flow.endDrag(predicted: g.predictedEndTranslation.width, step: side * 0.32) }
    }

    private func tap(_ i: Int) {
        let clicks = NSApp.currentEvent?.clickCount ?? 1
        registerKeyboard()
        if i == flow.focus {
            if clicks >= 2 { activate(i) }
        } else {
            flow.go(to: i, animation: snapAnimation)
        }
    }

    // MARK: Beschriftung und Bedienung

    @ViewBuilder
    private func caption(_ focus: Int) -> some View {
        if count > 0 {
            let entry = item(focus)
            VStack(spacing: 3) {
                Text(entry.title)
                    .textStyle(Typo.titleLarge)
                    .foregroundColor(entry.current ? colors.accentText : colors.textPrimary)
                    .lineLimit(1)
                if options.showSecondaryText, let subtitle = entry.subtitle {
                    Text(subtitle)
                        .textStyle(Typo.bodyMedium)
                        .foregroundColor(colors.textSecondary)
                        .lineLimit(1)
                }
                if options.showDetails, let detail = entry.detail {
                    Text(detail)
                        .textStyle(Typo.labelMedium)
                        .foregroundColor(colors.textTertiary)
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func controls(_ focus: Int) -> some View {
        if count > 0 {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    PillButton(title: "Abspielen", icon: Icons.play, style: .filled, minWidth: 124) { play(focus, false) }
                    PillButton(title: "Mischen", icon: Icons.shuffle, minWidth: 124) { play(focus, true) }
                    if let openLabel, let open {
                        PillButton(title: openLabel, icon: LibIcon.open) { open(focus) }
                    }
                }
                if count > 1 { scrubber(focus) }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func scrubber(_ focus: Int) -> some View {
        let upper = Double(max(count - 1, 1))
        return HStack(spacing: 10) {
            Text(verbatim: Formatting.integer(focus + 1))
                .font(Typo.inter(11, .medium))
                .monospacedDigit()
                .foregroundColor(colors.textTertiary)
                .frame(minWidth: 40, alignment: .trailing)
            MusicSlider(
                value: Binding(get: { flow.position }, set: { flow.scrub(to: $0) }),
                range: 0...upper,
                step: 1,
                label: "Position im Cover Flow",
                valueText: "\(focus + 1) von \(count)",
                onEditingChanged: { editing in
                    if !editing { flow.snap(using: nil) }
                }
            )
            Text(verbatim: Formatting.integer(count))
                .font(Typo.inter(11, .medium))
                .monospacedDigit()
                .foregroundColor(colors.textTertiary)
                .frame(minWidth: 40, alignment: .leading)
        }
        .frame(maxWidth: 520)
    }

    // MARK: Einrichtung

    private func setUp() {
        flow.animation = snapAnimation
        flow.suspended = model.playerOpen
        flow.attach(count: count, key: memoryKey)
        registerKeyboard()
    }

    /// Pfeil ↑/↓ blättern, Eingabe spielt bzw. öffnet, ⌘I zeigt Informationen (← → über den eigenen Monitor).
    private func registerKeyboard() {
        let flow = self.flow
        let activate = self.activate
        let item = self.item
        KeyboardFocus.shared.activeList = KeyboardFocus.ListHandle(
            moveSelection: { delta, _ in flow.step(delta) },
            playSelection: { if flow.count > 0 { activate(flow.focus) } },
            deleteSelection: {},
            selectAll: {},
            selectedUids: { flow.count > 0 ? item(flow.focus).trackUids : [] }
        )
    }
}

/// Ermittelt das Fenster, in dem eine Ansicht liegt.
private struct HostWindowReader: NSViewRepresentable {
    let found: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in found(view?.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Ein Cover im Cover Flow mit Spiegelung.
struct CoverFlowCard: View, Equatable {
    @Environment(\.musicColors) private var colors
    let item: LibraryItem
    let side: CGFloat
    let reflection: Bool
    let focused: Bool
    let playing: Bool

    static func == (a: CoverFlowCard, b: CoverFlowCard) -> Bool {
        a.item == b.item && a.side == b.side && a.reflection == b.reflection && a.focused == b.focused && a.playing == b.playing
    }

    var body: some View {
        VStack(spacing: 4) {
            art
                .frame(width: side, height: side)
                .overlay(alignment: .topLeading) { badge }
                .shadow(color: Color.black.opacity(focused ? (colors.dark ? 0.55 : 0.26) : 0), radius: focused ? 22 : 0, x: 0, y: focused ? 14 : 0)
            mirror
        }
    }

    private var art: some View {
        LibraryArtView(art: item.art, size: .medium, cornerRadius: item.circle ? 0 : Radius.artworkLarge, circle: item.circle, iconFraction: 0.4)
    }

    @ViewBuilder
    private var badge: some View {
        if item.current {
            Circle()
                .fill(Color.black.opacity(0.5))
                .frame(width: 30, height: 30)
                .overlay(NowPlayingBars(playing: playing, color: .white, size: 14))
                .padding(10)
        }
    }

    @ViewBuilder
    private var mirror: some View {
        if reflection {
            art
                .frame(width: side, height: side)
                .scaleEffect(x: 1, y: -1, anchor: .center)
                .frame(width: side, height: side * 0.32, alignment: .top)
                .clipped()
                .mask(LinearGradient(colors: [Color.black.opacity(colors.dark ? 0.34 : 0.24), Color.black.opacity(0)],
                                     startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(width: side, height: side * 0.32)
        }
    }
}
