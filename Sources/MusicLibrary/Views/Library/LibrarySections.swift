import SwiftUI
import MLCore

// Abschnitte in den Übersichten (2.2.2): Bei Sortierung nach Erscheinungsjahr oder „Hinzugefügt“ steht über
// jedem Abschnitt eine Überschrift („2024 · 37 Alben“, „November 2026 · 12 Titel“). Beim Scrollen zeigt eine
// Glaskapsel links auf Höhe der festen Werkzeugleiste, in welchem Abschnitt man sich gerade befindet.

/// Platz eines Eintrags innerhalb eines Abschnitts (Position in der ganzen Liste + Kennung).
struct SectionSlot<ID: Hashable>: Identifiable {
    let index: Int
    let id: ID
}

extension LibrarySectionRun {
    /// Positionen, auf die Liste begrenzt (Abschnitte und Liste stammen aus derselben Berechnung).
    func slots<ID: Hashable>(count: Int, id: (Int) -> ID) -> [SectionSlot<ID>] {
        let r = range.clamped(to: 0..<max(count, 0))
        return r.map { SectionSlot(index: $0, id: id($0)) }
    }
}

/// Merkt sich, welche Abschnitts-Überschriften wo stehen, und bestimmt daraus den aktuellen Abschnitt.
/// Nur die kleine Kapsel beobachtet es – die Listen selbst werden beim Scrollen nicht neu ausgewertet.
@MainActor
final class LibrarySectionTracker: ObservableObject {
    @Published private(set) var current: String?
    /// Oberkante des sichtbaren Inhalts unter Navigation und Werkzeugleiste (Koordinaten des Scrollbereichs).
    var threshold: CGFloat = 0
    private var ids: [String] = []
    private var titles: [String] = []
    private var order: [String: Int] = [:]
    private var positions: [String: CGFloat] = [:]

    func setRuns(_ runs: [LibrarySectionRun]) {
        let newIds = runs.map(\.id)
        if newIds == ids, runs.map(\.title) == titles { return }
        ids = newIds
        titles = runs.map(\.title)
        order = Dictionary(uniqueKeysWithValues: newIds.enumerated().map { ($1, $0) })
        positions = positions.filter { order[$0.key] != nil }
        recompute()
    }

    func report(_ id: String, minY: CGFloat) {
        guard order[id] != nil else { return }
        if let old = positions[id], abs(old - minY) < 0.5 { return }
        positions[id] = minY
        recompute()
    }

    func remove(_ id: String) {
        guard positions.removeValue(forKey: id) != nil else { return }
        recompute()
    }

    private func recompute() {
        guard !ids.isEmpty else { return set(nil) }
        // Überschrift, die zuletzt unter die Leiste gewandert ist → deren Abschnitt läuft gerade.
        var best: (index: Int, y: CGFloat)?
        var firstVisible: Int?
        for (id, y) in positions {
            guard let i = order[id] else { continue }
            if y <= threshold + 1 {
                if best == nil || y > best!.y { best = (i, y) }
            } else if firstVisible == nil || i < firstVisible! {
                firstVisible = i
            }
        }
        if let best { return set(titles[best.index]) }
        // Keine Überschrift oberhalb sichtbar: Wir sind im Abschnitt vor der ersten sichtbaren (ganz oben: keiner).
        if let k = firstVisible { return set(k > 0 ? titles[k - 1] : nil) }
        // Gar keine Überschrift sichtbar (großer Abschnitt): unverändert lassen.
    }

    private func set(_ title: String?) {
        if title != current { current = title }
    }
}

private struct LibrarySectionTrackerKey: EnvironmentKey {
    static let defaultValue: LibrarySectionTracker? = nil
}

extension EnvironmentValues {
    /// Vom Gerüst der Übersichten bereitgestellt (nil in Detailansichten).
    var librarySectionTracker: LibrarySectionTracker? {
        get { self[LibrarySectionTrackerKey.self] }
        set { self[LibrarySectionTrackerKey.self] = newValue }
    }
}

/// Überschrift eines Abschnitts: großes Datum, leise Anzahl, feine Linie bis zum Rand.
struct LibrarySectionHeader: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.librarySectionTracker) private var tracker
    let run: LibrarySectionRun
    let countText: String
    /// Erste Überschrift der Liste: weniger Abstand nach oben.
    let first: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(run.title)
                .textStyle(Typo.headlineSmall)
                .foregroundColor(colors.textPrimary)
                .lineLimit(1)
            Text(countText)
                .textStyle(Typo.bodySmall)
                .foregroundColor(colors.textSecondary)
                .lineLimit(1)
            Rectangle()
                .fill(colors.textSecondary.opacity(0.18))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] + 5 }
        }
        .padding(.top, first ? 6 : 26)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SectionPositionReporter(id: run.id, tracker: tracker))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Meldet die Lage einer Überschrift an den Tracker (nur solange sie geladen ist).
private struct SectionPositionReporter: View {
    let id: String
    let tracker: LibrarySectionTracker?

    var body: some View {
        if let tracker {
            GeometryReader { g in
                let y = g.frame(in: .named("scaffold")).minY
                Color.clear
                    .onAppear { tracker.report(id, minY: y) }
                    .onChange(of: y) { tracker.report(id, minY: $0) }
                    .onDisappear { tracker.remove(id) }
            }
        }
    }
}

/// Kapsel mit dem aktuellen Abschnitt, links auf Höhe der festen Werkzeugleiste.
struct LibrarySectionPill: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var tracker: LibrarySectionTracker

    var body: some View {
        ZStack(alignment: .leading) {
            if let title = tracker.current {
                Text(title)
                    .textStyle(Typo.titleMedium)
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .glassSurface(Capsule(), strong: true)
                    .id(title)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                    .accessibilityLabel("Abschnitt \(title)")
            }
        }
        .animation(reduceMotion ? nil : Motion.easeOut(0.2), value: tracker.current)
        .allowsHitTesting(false)
    }
}

/// Abschnitte einer Liste an den Tracker geben (beim Erscheinen und wenn sie sich ändern).
struct SectionRunsPublisher: ViewModifier {
    @Environment(\.librarySectionTracker) private var tracker
    let runs: [LibrarySectionRun]?

    func body(content: Content) -> some View {
        content
            .onAppear { tracker?.setRuns(runs ?? []) }
            .onChange(of: runs?.map(\.id) ?? []) { _ in tracker?.setRuns(runs ?? []) }
            .onDisappear { tracker?.setRuns([]) }
    }
}
