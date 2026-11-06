import SwiftUI
import AppKit

// Auswahlrahmen (Gummiband) über Kacheln und Zeilen – in Rastern, Listen und Detaillisten aller Bereiche.
//
// Auslösen (v2.1):
// • Auf freier Fläche (zwischen Kacheln, im Rand links/rechts der Liste, unter dem letzten Eintrag) beginnt
//   Ziehen sofort einen Auswahlrahmen.
// • Auf einem Eintrag: kurz gedrückt halten (≈ 0,35 s, ohne zu bewegen), dann ziehen. Wer sofort zieht,
//   zieht wie bisher die Auswahl per Drag & Drop (z. B. auf eine Playlist).
// • ⌘ beim Aufziehen kehrt die getroffenen Einträge in der bestehenden Auswahl um, ⇧ ergänzt sie.
// • Am oberen/unteren Rand scrollt die Ansicht beim Ziehen mit.
// • Ein einfacher Klick auf freie Fläche hebt die Auswahl auf.
//
// Umsetzung: ein lokaler Ereignismonitor (keine eigene Ebene über dem Inhalt – Scrollen, Hover, Klicks und
// Ziehen & Ablegen bleiben unberührt). Erst wenn ein Rahmen tatsächlich aufgezogen wird, werden die
// Ziehereignisse abgefangen, damit kein Drag & Drop beginnt. Die Rahmen der Einträge werden im eigenen
// Koordinatenraum des Containers gemerkt – sie ändern sich beim Scrollen nicht, also entsteht dabei keine Arbeit.

// MARK: - Ziel eines Auswahlrahmens

@MainActor
protocol MarqueeTarget: AnyObject {
    /// Unsichtbare AppKit-Ansicht mit genau dem Rahmen des Containers (Umrechnung Fenster → Container).
    var anchorView: NSView? { get }
    /// Höhe der festen Kopfleisten über dem Inhalt (Navigation, Werkzeugleiste) – dort beginnt kein Rahmen.
    var topChrome: CGFloat { get }
    func anchorAttached(_ view: NSView)
    func anchorDetached(_ view: NSView)
    /// Liegt der Punkt (Containerkoordinaten) im Bereich, der einen Rahmen beginnen darf?
    func regionContains(_ point: CGPoint) -> Bool
    /// Liegt der Punkt auf einem Eintrag?
    func itemHit(at point: CGPoint) -> Bool
    func marqueeBegan(at point: CGPoint, modifiers: NSEvent.ModifierFlags)
    func marqueeMoved(to point: CGPoint)
    func marqueeEnded()
    /// Einfacher Klick auf freie Fläche.
    func emptyClick()
}

// MARK: - Ereignisse (ein Monitor für alle Sammlungen)

@MainActor
final class MarqueeRouter {
    static let shared = MarqueeRouter()

    /// Haltezeit auf einem Eintrag, bevor Ziehen einen Rahmen statt Drag & Drop beginnt.
    static let holdDelay: TimeInterval = 0.35
    /// Ab dieser Strecke (Punkte) gilt eine Mausbewegung als Ziehen.
    static let dragThreshold: CGFloat = 4

    private struct WeakTarget {
        weak var target: MarqueeTarget?
    }

    private var targets: [WeakTarget] = []
    private var monitor: Any?

    // Zustand der laufenden Mausgeste
    private weak var active: MarqueeTarget?
    private var tracking = false
    private var startPoint: NSPoint = .zero
    private var lastPoint: NSPoint = .zero
    private var startedOnItem = false
    private var armed = false
    private var running = false
    private var passthrough = false
    private var modifiers: NSEvent.ModifierFlags = []
    private var holdWork: DispatchWorkItem?
    private var scrollWork: DispatchWorkItem?
    private var scrollSpeed: CGFloat = 0
    private var lastMarqueeEnd: TimeInterval = 0

    /// Kam gerade ein Auswahlrahmen zu Ende? Dann löst das zugehörige Loslassen keinen Klick auf einen
    /// Eintrag aus (zusätzliche Absicherung zum verlegten Loslassen-Ereignis).
    var justFinishedMarquee: Bool {
        ProcessInfo.processInfo.systemUptime - lastMarqueeEnd < 0.3
    }

    func register(_ target: MarqueeTarget) {
        targets.removeAll { $0.target == nil || $0.target === target }
        targets.append(WeakTarget(target: target))
        installMonitor()
    }

    func unregister(_ target: MarqueeTarget) {
        targets.removeAll { $0.target == nil || $0.target === target }
        if active === target { cancel() }
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .leftMouseDown:
            mouseDown(event)
            return event
        case .leftMouseDragged:
            return mouseDragged(event)
        case .leftMouseUp:
            return mouseUp(event)
        default:
            return event
        }
    }

    // MARK: Maus

    private func mouseDown(_ event: NSEvent) {
        cancel()
        guard event.clickCount == 1, let window = event.window else { return }
        if let main = MainWindowRef.window, window !== main { return }
        // Vollbild-Player liegt über der Bibliothek
        if AppModel.shared?.playerOpen == true { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) { return }   // ⌃-Klick = Kontextmenü
        guard let hit = candidate(at: event.locationInWindow, in: window) else { return }
        active = hit.target
        tracking = true
        startPoint = event.locationInWindow
        lastPoint = startPoint
        modifiers = flags
        startedOnItem = hit.target.itemHit(at: hit.point)
        if startedOnItem {
            let work = DispatchWorkItem { [weak self] in self?.arm() }
            holdWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDelay, execute: work)
        }
    }

    private func mouseDragged(_ event: NSEvent) -> NSEvent? {
        guard tracking, !passthrough, let target = active, let anchor = target.anchorView else { return event }
        let point = event.locationInWindow
        let dx = point.x - startPoint.x
        let dy = point.y - startPoint.y
        let distance = (dx * dx + dy * dy).squareRoot()
        if !running {
            if startedOnItem && !armed {
                // Sofort gezogen: normales Ziehen & Ablegen des Eintrags bzw. der Auswahl
                if distance > 2 {
                    passthrough = true
                    holdWork?.cancel()
                }
                return event
            }
            // Gehalten (oder freie Fläche): kleine Zitterbewegungen schlucken, damit kein Drag & Drop beginnt
            guard distance > Self.dragThreshold else { return startedOnItem ? nil : event }
            running = true
            holdWork?.cancel()
            NSCursor.crosshair.set()
            target.marqueeBegan(at: Self.local(startPoint, in: anchor), modifiers: modifiers)
        }
        lastPoint = point
        target.marqueeMoved(to: Self.local(point, in: anchor))
        updateAutoScroll()
        return nil
    }

    private func mouseUp(_ event: NSEvent) -> NSEvent? {
        guard tracking, let target = active else {
            cancel()
            return event
        }
        let wasRunning = running
        let emptyClick = !running && !passthrough && !startedOnItem
        cancel()
        if wasRunning {
            target.marqueeEnded()
            lastMarqueeEnd = ProcessInfo.processInfo.systemUptime
            NSCursor.arrow.set()
            // Loslassen außerhalb melden: so löst der gedrückte Eintrag keinen Klick aus und keine Schaltfläche
            // bleibt gedrückt (die Ansicht hat die Ziehereignisse nicht gesehen).
            return Self.detachedMouseUp(event)
        }
        if emptyClick { target.emptyClick() }
        return event
    }

    private func arm() {
        guard tracking, !passthrough, !running else { return }
        armed = true
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func cancel() {
        if running { active?.marqueeEnded() }
        holdWork?.cancel()
        holdWork = nil
        scrollWork?.cancel()
        scrollWork = nil
        scrollSpeed = 0
        tracking = false
        running = false
        armed = false
        passthrough = false
        startedOnItem = false
        active = nil
    }

    // MARK: Ziel unter dem Zeiger

    private func candidate(at windowPoint: NSPoint, in window: NSWindow) -> (target: MarqueeTarget, point: CGPoint)? {
        var fallback: (target: MarqueeTarget, point: CGPoint)?
        for entry in targets {
            guard let each = entry.target, let anchor = each.anchorView, anchor.window === window,
                  !anchor.isHiddenOrHasHiddenAncestor else { continue }
            guard Self.inVisibleContent(windowPoint, anchor: anchor, topChrome: each.topChrome) else { continue }
            let local = Self.local(windowPoint, in: anchor)
            if anchor.bounds.contains(local) { return (target: each, point: local) }
            if fallback == nil, each.regionContains(local) { fallback = (target: each, point: local) }
        }
        return fallback
    }

    /// Fensterpunkt → Koordinaten des Containers (oben links = 0,0).
    static func local(_ windowPoint: NSPoint, in anchor: NSView) -> CGPoint {
        let p = anchor.convert(windowPoint, from: nil)
        return CGPoint(x: p.x, y: anchor.isFlipped ? p.y : anchor.bounds.height - p.y)
    }

    /// Liegt der Punkt im sichtbaren Inhalt – nicht unter Navigation, Werkzeugleiste, Auswahlleiste,
    /// Mitteilungen oder Mini-Player?
    private static func inVisibleContent(_ windowPoint: NSPoint, anchor: NSView, topChrome: CGFloat) -> Bool {
        guard let scroll = anchor.enclosingScrollView else { return true }
        let p = scroll.convert(windowPoint, from: nil)
        let y = scroll.isFlipped ? p.y : scroll.bounds.height - p.y
        guard p.x >= 0, p.x <= scroll.bounds.width else { return false }
        return y >= topChrome && y <= scroll.bounds.height - bottomChrome()
    }

    private static func bottomChrome() -> CGFloat {
        let model = AppModel.shared
        var height = Chrome.contentBottom(miniPlayer: model?.player.current != nil)
        if LibrarySelectionStore.shared.info != nil { height += SelectionBarMetrics.reservedHeight }
        height += CGFloat(model?.toasts.count ?? 0) * 50
        return height
    }

    /// Kopie des Ereignisses „Maustaste losgelassen“ weit außerhalb des Fensters.
    private static func detachedMouseUp(_ event: NSEvent) -> NSEvent? {
        NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: -10_000, y: -10_000), modifierFlags: event.modifierFlags,
                           timestamp: event.timestamp, windowNumber: event.windowNumber, context: nil,
                           eventNumber: event.eventNumber, clickCount: event.clickCount, pressure: event.pressure) ?? event
    }

    // MARK: Mitscrollen am Rand

    private func updateAutoScroll() {
        guard running, let target = active, let anchor = target.anchorView, let scroll = anchor.enclosingScrollView else {
            scrollSpeed = 0
            return
        }
        let p = scroll.convert(lastPoint, from: nil)
        let y = scroll.isFlipped ? p.y : scroll.bounds.height - p.y
        let zone: CGFloat = 56
        let top = target.topChrome
        let bottom = scroll.bounds.height - Self.bottomChrome()
        var speed: CGFloat = 0
        if y < top + zone {
            speed = -max(2, (top + zone - y) / zone * 22)
        } else if y > bottom - zone {
            speed = max(2, (y - (bottom - zone)) / zone * 22)
        }
        scrollSpeed = min(max(speed, -48), 48)
        if scrollSpeed != 0 && scrollWork == nil { scheduleScrollTick() }
    }

    private func scheduleScrollTick() {
        let work = DispatchWorkItem { [weak self] in self?.scrollTick() }
        scrollWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0, execute: work)
    }

    private func scrollTick() {
        scrollWork = nil
        guard running, scrollSpeed != 0, let target = active, let anchor = target.anchorView,
              let scroll = anchor.enclosingScrollView, let document = scroll.documentView else { return }
        guard LibraryScrolling.scroll(scroll, by: scrollSpeed, document: document) else { return }
        // Der Inhalt bewegt sich unter dem ruhenden Zeiger → Rahmen nachführen
        target.marqueeMoved(to: Self.local(lastPoint, in: anchor))
        scheduleScrollTick()
    }
}

// MARK: - Scrollen per Programm (Mitscrollen, Vorschaubilder)

@MainActor
enum LibraryScrolling {
    /// Verschiebt den sichtbaren Ausschnitt um `delta` Punkte (positiv = nach unten). `false` am Ende.
    @discardableResult
    static func scroll(_ scroll: NSScrollView, by delta: CGFloat, document: NSView) -> Bool {
        let clip = scroll.contentView
        let maxY = max(0, document.frame.height - clip.bounds.height)
        var origin = clip.bounds.origin
        let current = origin.y
        let wanted = document.isFlipped ? current + delta : current - delta
        origin.y = min(max(wanted, 0), maxY)
        guard abs(origin.y - current) > 0.5 else { return false }
        clip.scroll(to: origin)
        scroll.reflectScrolledClipView(clip)
        return true
    }
}

/// Für Vorschaubilder: Bibliotheksansicht nach dem Aufbau um diese Strecke nach unten scrollen
/// (wird einmal angewendet und dann zurückgesetzt).
@MainActor
enum LibraryScrollSeed {
    static var pendingOffset: CGFloat?
}

/// Unsichtbare Hilfsansicht im Scrollinhalt: wendet `LibraryScrollSeed` an.
struct LibraryScrollSeedReader: NSViewRepresentable {
    func makeNSView(context: Context) -> SeedView { SeedView() }
    func updateNSView(_ nsView: SeedView, context: Context) {}

    final class SeedView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, LibraryScrollSeed.pendingOffset != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, let offset = LibraryScrollSeed.pendingOffset,
                      let scroll = self.enclosingScrollView, let document = scroll.documentView else { return }
                LibraryScrollSeed.pendingOffset = nil
                LibraryScrolling.scroll(scroll, by: offset, document: document)
            }
        }
    }
}

// MARK: - Rahmen eines Containers

/// Sichtbarer Auswahlrahmen (nur er zeichnet sich beim Aufziehen neu).
@MainActor
final class MarqueeBand: ObservableObject {
    @Published var rect: CGRect?
}

/// Auswahlrahmen einer Sammlung bzw. Titelliste. Hält die Rahmen der Einträge (nicht beobachtet – kein
/// Neuzeichnen) und rechnet die getroffenen Einträge aus. Die Ansicht setzt bei jedem Aufbau `selection`
/// und `apply` neu.
@MainActor
final class MarqueeController<ID: Hashable>: ObservableObject, MarqueeTarget {
    let band = MarqueeBand()
    /// Name des Koordinatenraums des Containers.
    let space = "marquee-" + UUID().uuidString
    private(set) weak var anchorView: NSView?
    var topChrome: CGFloat = Chrome.contentTop
    /// Zusätzlicher Startbereich links/rechts des Containers (Seitenrand der Bibliothek).
    var horizontalSlack: CGFloat = Spacing.gutter
    /// Zusätzlicher Startbereich unter dem Container.
    var bottomSlack: CGFloat = 160

    var selection: () -> Set<ID> = { [] }
    var apply: (Set<ID>) -> Void = { _ in }

    private var frames: [ID: CGRect] = [:]
    private var generation = 0
    private var origin: CGPoint = .zero
    private var base: Set<ID> = []
    private var toggles = false
    private var lastHits: Set<ID> = []

    /// Neuer Aufbau (andere Einträge, Reihenfolge, Größe oder Ansicht): alte Rahmen verwerfen.
    func prepare(generation g: Int) {
        guard g != generation else { return }
        generation = g
        frames.removeAll(keepingCapacity: true)
    }

    func setFrame(_ rect: CGRect, for id: ID, generation g: Int) {
        guard g == generation else { return }
        frames[id] = rect
    }

    // MARK: MarqueeTarget

    func anchorAttached(_ view: NSView) {
        anchorView = view
        MarqueeRouter.shared.register(self)
    }

    func anchorDetached(_ view: NSView) {
        guard anchorView === view else { return }
        anchorView = nil
        band.rect = nil
        MarqueeRouter.shared.unregister(self)
    }

    func regionContains(_ point: CGPoint) -> Bool {
        guard let view = anchorView else { return false }
        let region = CGRect(x: -horizontalSlack, y: 0,
                            width: view.bounds.width + horizontalSlack * 2, height: view.bounds.height + bottomSlack)
        return region.contains(point)
    }

    func itemHit(at point: CGPoint) -> Bool {
        frames.values.contains { $0.contains(point) }
    }

    func marqueeBegan(at point: CGPoint, modifiers: NSEvent.ModifierFlags) {
        origin = point
        toggles = modifiers.contains(.command)
        base = (modifiers.contains(.command) || modifiers.contains(.shift)) ? selection() : []
        lastHits = []
        band.rect = CGRect(origin: point, size: .zero)
        if base != selection() { apply(base) }
    }

    func marqueeMoved(to point: CGPoint) {
        let rect = CGRect(x: min(origin.x, point.x), y: min(origin.y, point.y),
                          width: abs(point.x - origin.x), height: abs(point.y - origin.y))
        band.rect = rect
        var hits = Set<ID>()
        for (id, frame) in frames where frame.intersects(rect) { hits.insert(id) }
        guard hits != lastHits else { return }
        lastHits = hits
        apply(toggles ? base.symmetricDifference(hits) : base.union(hits))
    }

    func marqueeEnded() {
        band.rect = nil
        lastHits = []
        base = []
    }

    func emptyClick() {
        if !selection().isEmpty { apply([]) }
    }
}

// MARK: - Bausteine für die Ansichten

extension View {
    /// Macht diese Ansicht zum Container eines Auswahlrahmens (Koordinatenraum, Anker, sichtbarer Rahmen).
    func marqueeContainer<ID: Hashable>(_ controller: MarqueeController<ID>) -> some View {
        self
            .coordinateSpace(name: controller.space)
            .background(MarqueeAnchor(target: controller))
            .overlay(MarqueeBandView(band: controller.band))
    }
}

/// Unsichtbare AppKit-Ansicht im Hintergrund des Containers; nimmt keine Klicks an.
struct MarqueeAnchor: NSViewRepresentable {
    let target: MarqueeTarget

    func makeNSView(context: Context) -> MarqueeAnchorView {
        let view = MarqueeAnchorView()
        view.target = target
        return view
    }

    func updateNSView(_ nsView: MarqueeAnchorView, context: Context) {
        if nsView.target !== target {
            nsView.target?.anchorDetached(nsView)
            nsView.target = target
            if nsView.window != nil { target.anchorAttached(nsView) }
        }
    }

    static func dismantleNSView(_ nsView: MarqueeAnchorView, coordinator: ()) {
        nsView.target?.anchorDetached(nsView)
        nsView.target = nil
    }
}

final class MarqueeAnchorView: NSView {
    weak var target: MarqueeTarget?

    override var isFlipped: Bool { true }

    /// Nie Ziel von Mausereignissen – die Ansichten darüber bleiben voll bedienbar.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            target?.anchorAttached(self)
        } else {
            target?.anchorDetached(self)
        }
    }
}

/// Meldet den Rahmen eines Eintrags im Koordinatenraum des Containers (beim Erscheinen und bei Änderungen
/// des Layouts – nicht beim Scrollen).
struct MarqueeFrameReporter<ID: Hashable>: View {
    let id: ID
    let generation: Int
    let controller: MarqueeController<ID>

    var body: some View {
        GeometryReader { geo in
            let stamp = MarqueeFrameStamp(frame: geo.frame(in: .named(controller.space)), generation: generation)
            Color.clear
                .onAppear { controller.setFrame(stamp.frame, for: id, generation: stamp.generation) }
                .onChange(of: stamp) { value in controller.setFrame(value.frame, for: id, generation: value.generation) }
        }
    }
}

struct MarqueeFrameStamp: Equatable {
    let frame: CGRect
    let generation: Int
}

/// Der sichtbare Rahmen: zarte Rosé-Fläche mit feiner Kante.
struct MarqueeBandView: View {
    @Environment(\.musicColors) private var colors
    @ObservedObject var band: MarqueeBand

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let rect = band.rect, rect.width > 1 || rect.height > 1 {
                let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
                shape
                    .fill(colors.accent.opacity(colors.dark ? 0.16 : 0.11))
                    .overlay(shape.strokeBorder(colors.accent.opacity(0.75), lineWidth: 1))
                    .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Höhe der festen Kopfleisten (für Auswahlrahmen)

private struct LibraryTopChromeKey: EnvironmentKey {
    static let defaultValue: CGFloat = Chrome.contentTop
}

private struct LibraryMarqueeTailKey: EnvironmentKey {
    static let defaultValue: CGFloat = 160
}

extension EnvironmentValues {
    /// Höhe der schwebenden Leisten über dem Inhalt (Navigation, ggf. feste Werkzeugleiste).
    var libraryTopChrome: CGFloat {
        get { self[LibraryTopChromeKey.self] }
        set { self[LibraryTopChromeKey.self] = newValue }
    }

    /// Wie weit unter einer Liste ein Auswahlrahmen noch beginnen darf. Klein, wenn darunter weitere
    /// ziehbare Inhalte folgen (z. B. „Mehr von …“ in der Albumansicht).
    var libraryMarqueeTail: CGFloat {
        get { self[LibraryMarqueeTailKey.self] }
        set { self[LibraryMarqueeTailKey.self] = newValue }
    }
}
