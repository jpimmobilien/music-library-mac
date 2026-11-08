import SwiftUI
import AppKit
import MLStudio

// Audio Studio – Wellenform-Editor: Zeitlineal, symmetrische Balken (nur die sichtbaren Spalten), Auswahl mit
// zwei Griffen, Abspielkopf (eigene kleine Ansicht – nur sie beobachtet `StudioPlayback`), Zoom per Regler,
// Trackpad und ⌘-Mausrad, horizontales Verschieben, Übersicht beim Zoomen.

// MARK: - Karte

struct StudioEditorCard: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        let ready = studio.waveform != nil && !studio.needsPreparation
        StudioCard(icon: studio.isLibraryTrack ? Icons.cut : Icons.waveform, title: "Ausschnitt", subtitle: subtitle) {
            StudioZoomControls(studio: studio)
                .disabled(!ready)
                .opacity(ready ? 1 : 0.5)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                if studio.needsPreparation {
                    StudioPreparePanel(studio: studio)
                } else if let wf = studio.waveform {
                    StudioWaveformEditor(studio: studio, waveform: wf)
                } else {
                    StudioWaveformPlaceholder(progress: studio.waveformProgress)
                }
                StudioTransportBar(studio: studio)
                    .disabled(!ready)
            }
        }
    }

    private var subtitle: String {
        if studio.needsPreparation { return "Zum Schneiden die Audiospur laden – oder direkt die ganze Datei exportieren" }
        if studio.waveform == nil { return "Wellenform wird vorbereitet" }
        let sel = studio.shownSelection
        if studio.exportWholeFile { return "Ganze Datei · \(StudioTime.format(studio.duration, millis: false))" }
        return "\(StudioTime.format(sel.start)) – \(StudioTime.format(sel.end)) · Länge \(StudioTime.format(sel.length))"
    }
}

enum WaveformMetrics {
    static let ruler: CGFloat = 20
    static let wave: CGFloat = 156
    static let handleHit: CGFloat = 10
}

// MARK: - Editor

struct StudioWaveformEditor: View {
    @ObservedObject var studio: StudioModel
    let waveform: WaveformData
    @Environment(\.musicColors) private var colors
    @StateObject private var input = WaveformInputMonitor()
    /// Auswahl während des Ziehens (wird beim Loslassen übernommen – flüssig, ohne das ganze Studio neu zu zeichnen).
    @State private var live: TrimRange?
    @State private var mode: DragMode?
    @State private var resizeCursor = false

    private enum DragMode: Equatable {
        /// Griff ziehen; `fixed` = der andere, feststehende Rand.
        case handle(fixed: Double)
        /// Neue Auswahl ab `anchor`.
        case create(anchor: Double)
        /// Maustaste gedrückt, noch nicht bewegt (Klick = Abspielkopf setzen).
        case pending(at: Double)
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let range = studio.visibleRange
                let sel = live ?? studio.shownSelection
                let x0 = x(for: sel.start, range: range, width: width)
                let x1 = x(for: sel.end, range: range, width: width)
                ZStack(alignment: .topLeading) {
                    WaveformRuler(range: range, label: colors.textTertiary, tick: colors.textPrimary.opacity(0.22))
                        .equatable()
                        .frame(width: width, height: WaveformMetrics.ruler)
                    waveArea(width: width, range: range, sel: sel, x0: x0, x1: x1)
                        .offset(y: WaveformMetrics.ruler)
                }
                .frame(width: width, height: WaveformMetrics.ruler + WaveformMetrics.wave, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(dragGesture(width: width, range: range, sel: sel, x0: x0, x1: x1))
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let p):
                        input.hoverX = p.x
                        let near = abs(p.x - x0) <= WaveformMetrics.handleHit || abs(p.x - x1) <= WaveformMetrics.handleHit
                        setResizeCursor(near && p.y > WaveformMetrics.ruler)
                    case .ended:
                        input.hoverX = nil
                        setResizeCursor(false)
                    }
                }
                .onAppear { input.width = width }
                .onChange(of: width) { input.width = $0 }
            }
            .frame(height: WaveformMetrics.ruler + WaveformMetrics.wave)
            if studio.zoom > 1.01 {
                WaveformOverview(studio: studio, waveform: waveform)
                    .frame(height: 30)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Motion.easeOut(Motion.short), value: studio.zoom > 1.01)
        .onAppear {
            input.studio = studio
            input.install()
        }
        .onDisappear {
            input.uninstall()
            setResizeCursor(false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wellenform")
        .accessibilityValue(studio.exportWholeFile ? "Ganze Datei ausgewählt" : "Auswahl von \(StudioTime.format(studio.selection.start)) bis \(StudioTime.format(studio.selection.end))")
        .accessibilityHint("Ziehen wählt einen Ausschnitt, Klicken setzt den Abspielkopf. Genaue Zeiten in den Feldern Start und Ende.")
    }

    @ViewBuilder
    private func waveArea(width: CGFloat, range: ClosedRange<Double>, sel: TrimRange, x0: CGFloat, x1: CGFloat) -> some View {
        let h = WaveformMetrics.wave
        let bx0 = min(max(x0, 0), width)
        let bx1 = min(max(x1, 0), width)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colors.textPrimary.opacity(colors.dark ? 0.05 : 0.035))
            Rectangle()
                .fill(colors.textPrimary.opacity(0.08))
                .frame(width: width, height: 1)
                .offset(y: h / 2 - 0.5)
            // Auswahl: zarte Fläche mit Rahmen oben und unten
            if bx1 - bx0 > 0.5 {
                ZStack(alignment: .top) {
                    Rectangle().fill(colors.accent.opacity(colors.dark ? 0.15 : 0.10))
                    Rectangle().fill(colors.accent).frame(height: 2)
                    Rectangle().fill(colors.accent).frame(height: 2).offset(y: h - 2)
                }
                .frame(width: bx1 - bx0, height: h)
                .offset(x: bx0)
            }
            WaveformCanvas(waveform: waveform, range: range, selection: sel, fadeIn: studio.fadeIn, fadeOut: studio.fadeOut,
                           selected: colors.accent, muted: colors.textPrimary.opacity(colors.dark ? 0.30 : 0.24))
                .equatable()
                .frame(width: width, height: h)
            if x0 >= -WaveformMetrics.handleHit, x0 <= width + WaveformMetrics.handleHit {
                TrimHandle(active: isDragging(edge: sel.start))
                    .offset(x: x0 - 8)
            }
            if x1 >= -WaveformMetrics.handleHit, x1 <= width + WaveformMetrics.handleHit {
                TrimHandle(active: isDragging(edge: sel.end))
                    .offset(x: x1 - 8)
            }
            WaveformPlayhead(playback: studio.playback, range: range, width: width, height: h)
            if let live, let label = dragLabel(live) {
                Text(label)
                    .font(Typo.inter(11, .semibold))
                    .monospacedDigit()
                    .foregroundColor(colors.onAccent)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Capsule().fill(colors.accent))
                    .fixedSize()
                    .offset(x: min(max(labelX(live, range: range, width: width) - 40, 2), max(2, width - 150)), y: 8)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: h, alignment: .topLeading)
    }

    // MARK: Gesten

    private func dragGesture(width: CGFloat, range: ClosedRange<Double>, sel: TrimRange, x0: CGFloat, x1: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { g in
                let t = time(at: g.location.x, range: range, width: width)
                if mode == nil {
                    let sx = g.startLocation.x
                    let onWave = g.startLocation.y > WaveformMetrics.ruler
                    let d0 = abs(sx - x0)
                    let d1 = abs(sx - x1)
                    if onWave, min(d0, d1) <= WaveformMetrics.handleHit {
                        mode = .handle(fixed: d0 <= d1 ? sel.end : sel.start)
                    } else {
                        mode = .pending(at: time(at: sx, range: range, width: width))
                    }
                }
                switch mode {
                case .handle(let fixed)?:
                    guard abs(g.translation.width) > 0.5 || live != nil else { return }
                    live = ordered(fixed, t)
                case .pending(let a)?:
                    if abs(g.translation.width) > 3 {
                        mode = .create(anchor: a)
                        live = ordered(a, t)
                    }
                case .create(let a)?:
                    live = ordered(a, t)
                case nil:
                    break
                }
            }
            .onEnded { g in
                switch mode {
                case .pending(let a)?:
                    studio.seek(to: a)
                default:
                    if let l = live, l.length >= 0.01 {
                        studio.setSelection(start: l.start, end: l.end)
                    }
                }
                live = nil
                mode = nil
            }
    }

    private func ordered(_ a: Double, _ b: Double) -> TrimRange {
        TrimRange(start: min(a, b), end: max(a, b))
    }

    private func isDragging(edge: Double) -> Bool {
        guard case .handle(let fixed)? = mode, live != nil else { return false }
        return abs(fixed - edge) > 1e-9
    }

    private func dragLabel(_ r: TrimRange) -> String? {
        switch mode {
        case .handle(let fixed)?:
            let moving = abs(r.start - fixed) < 1e-9 ? r.end : r.start
            return StudioTime.format(moving)
        case .create?:
            return "\(StudioTime.format(r.start)) – \(StudioTime.format(r.end))"
        default:
            return nil
        }
    }

    private func labelX(_ r: TrimRange, range: ClosedRange<Double>, width: CGFloat) -> CGFloat {
        if case .handle(let fixed)? = mode {
            let moving = abs(r.start - fixed) < 1e-9 ? r.end : r.start
            return x(for: moving, range: range, width: width)
        }
        return x(for: r.start, range: range, width: width)
    }

    // MARK: Umrechnung

    private func x(for t: Double, range: ClosedRange<Double>, width: CGFloat) -> CGFloat {
        let span = max(range.upperBound - range.lowerBound, 1e-6)
        return CGFloat((t - range.lowerBound) / span) * width
    }

    private func time(at x: CGFloat, range: ClosedRange<Double>, width: CGFloat) -> Double {
        let span = range.upperBound - range.lowerBound
        var t = range.lowerBound + Double(min(max(x, 0), width) / width) * span
        // Am Rand einrasten (Anfang/Ende der Datei)
        let snap = Double(4 / width) * span
        if t < snap { t = 0 }
        if t > studio.duration - snap { t = studio.duration }
        return min(max(t, 0), studio.duration)
    }

    private func setResizeCursor(_ on: Bool) {
        guard on != resizeCursor else { return }
        resizeCursor = on
        if on { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
    }
}

/// Griff am Rand der Auswahl (rosé Linie mit Griffleiste).
private struct TrimHandle: View {
    @Environment(\.musicColors) private var colors
    let active: Bool

    var body: some View {
        ZStack {
            Capsule()
                .fill(colors.accent)
                .frame(width: 3, height: WaveformMetrics.wave)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(colors.accent)
                .frame(width: active ? 14 : 12, height: active ? 46 : 40)
                .overlay(
                    HStack(spacing: 2.5) {
                        Capsule().fill(Color.white.opacity(0.9)).frame(width: 1.5, height: 16)
                        Capsule().fill(Color.white.opacity(0.9)).frame(width: 1.5, height: 16)
                    }
                )
                .shadow(color: Color.black.opacity(colors.dark ? 0.45 : 0.22), radius: 4, y: 1.5)
        }
        .frame(width: 16, height: WaveformMetrics.wave)
        .animation(Motion.standardSpring, value: active)
        .allowsHitTesting(false)
    }
}

// MARK: - Zeichnen

/// Zeitlineal über der Wellenform (Teilstriche und Zeiten, je nach Zoom).
struct WaveformRuler: View, Equatable {
    let range: ClosedRange<Double>
    let label: Color
    let tick: Color

    var body: some View {
        Canvas { ctx, size in
            let span = range.upperBound - range.lowerBound
            guard span > 0, size.width > 1 else { return }
            let pxPerSecond = Double(size.width) / span
            let major = Self.majorSteps.first { $0 * pxPerSecond >= 74 } ?? 3600
            let ratio = Self.minorRatio(major)
            let minor = major / Double(ratio)
            let first = Int((range.lowerBound / minor).rounded(.up))
            let last = Int((range.upperBound / minor).rounded(.down))
            guard last >= first, last - first < 4000 else { return }
            var ticks = Path()
            for i in first...last {
                let t = Double(i) * minor
                let x = CGFloat((t - range.lowerBound) * pxPerSecond)
                let isMajor = i % ratio == 0
                let h: CGFloat = isMajor ? 7 : 3.5
                ticks.addRect(CGRect(x: x - 0.5, y: size.height - h, width: 1, height: h))
                if isMajor {
                    let text = Text(Self.label(t, step: major)).font(Typo.inter(10, .medium)).foregroundColor(label).monospacedDigit()
                    ctx.draw(text, at: CGPoint(x: x + 3, y: 1), anchor: .topLeading)
                }
            }
            ctx.fill(ticks, with: .color(tick))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static let majorSteps: [Double] = [0.05, 0.1, 0.2, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]

    static func minorRatio(_ major: Double) -> Int {
        switch major {
        case 0.2, 2, 60, 120, 3600: return 4
        case 15, 30, 900, 1800: return 3
        default: return 5
        }
    }

    static func label(_ t: Double, step: Double) -> String {
        if step >= 1 { return StudioTime.format(t, millis: false) }
        let full = StudioTime.format(t)            // „1:05.250“
        let digits = step >= 0.1 ? 1 : 2
        return String(full.dropLast(3 - digits))
    }
}

/// Symmetrische, abgerundete Balken – nur die sichtbaren Spalten. Zwei Füllungen (Auswahl / Rest) statt einer je Balken.
struct WaveformCanvas: View, Equatable {
    let waveform: WaveformData
    let range: ClosedRange<Double>
    let selection: TrimRange
    var fadeIn: Double = 0
    var fadeOut: Double = 0
    let selected: Color
    let muted: Color
    var barWidth: CGFloat = 2.2
    var step: CGFloat = 3.4

    var body: some View {
        Canvas { ctx, size in
            let n = max(1, Int(size.width / step))
            let cols = waveform.columns(range: range, columns: n)
            guard !cols.isEmpty else { return }
            let span = range.upperBound - range.lowerBound
            let peak = max(Double(waveform.peak), 0.05)
            let mid = size.height / 2
            let maxH = max(mid - 6, 1)
            let corner = CGSize(width: barWidth / 2, height: barWidth / 2)
            var inside = Path()
            var outside = Path()
            for i in 0..<cols.count {
                let c = cols[i]
                let t = range.lowerBound + (Double(i) + 0.5) * span / Double(n)
                var a = c.min <= c.max ? Double(max(abs(c.min), abs(c.max))) / peak : 0
                a = min(max(a, 0), 1)
                let sel = t >= selection.start && t <= selection.end
                if sel {
                    if fadeIn > 0 { a *= min(max((t - selection.start) / fadeIn, 0), 1) }
                    if fadeOut > 0 { a *= min(max((selection.end - t) / fadeOut, 0), 1) }
                }
                let h = max(1.2, CGFloat(pow(a, 0.85)) * maxH)
                let rect = CGRect(x: CGFloat(i) * step + (step - barWidth) / 2, y: mid - h, width: barWidth, height: 2 * h)
                if sel { inside.addRoundedRect(in: rect, cornerSize: corner) } else { outside.addRoundedRect(in: rect, cornerSize: corner) }
            }
            ctx.fill(outside, with: .color(muted))
            ctx.fill(inside, with: .color(selected))
            // Blendkurven (Hüllkurve über dem Ausschnitt)
            if fadeIn > 0 || fadeOut > 0 {
                func px(_ t: Double) -> CGFloat { CGFloat((t - range.lowerBound) / max(span, 1e-6)) * size.width }
                var curve = Path()
                if fadeIn > 0 {
                    curve.move(to: CGPoint(x: px(selection.start), y: mid))
                    curve.addLine(to: CGPoint(x: px(min(selection.start + fadeIn, selection.end)), y: mid - maxH))
                    curve.move(to: CGPoint(x: px(selection.start), y: mid))
                    curve.addLine(to: CGPoint(x: px(min(selection.start + fadeIn, selection.end)), y: mid + maxH))
                }
                if fadeOut > 0 {
                    curve.move(to: CGPoint(x: px(max(selection.end - fadeOut, selection.start)), y: mid - maxH))
                    curve.addLine(to: CGPoint(x: px(selection.end), y: mid))
                    curve.addLine(to: CGPoint(x: px(max(selection.end - fadeOut, selection.start)), y: mid + maxH))
                }
                ctx.stroke(curve, with: .color(selected.opacity(0.9)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [3, 3]))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Abspielkopf – eigene kleine Ansicht: nur sie wird ~30× pro Sekunde neu gezeichnet.
struct WaveformPlayhead: View {
    @ObservedObject var playback: StudioPlayback
    @Environment(\.musicColors) private var colors
    let range: ClosedRange<Double>
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let t = playback.playhead
        let span = max(range.upperBound - range.lowerBound, 1e-6)
        let x = CGFloat((t - range.lowerBound) / span) * width
        if (playback.playing || t > 0.0005), x >= -1, x <= width + 1 {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(colors.textPrimary)
                    .frame(width: 1.6, height: height)
                Circle()
                    .fill(colors.textPrimary)
                    .frame(width: 9, height: 9)
                    .offset(y: -4.5)
            }
            .frame(width: 10, height: height)
            .offset(x: x - 5)
            .shadow(color: colors.background.opacity(0.6), radius: 1.5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Übersicht der ganzen Datei beim Zoomen: sichtbarer Bereich als Glasfenster, Ziehen verschiebt.
private struct WaveformOverview: View {
    @ObservedObject var studio: StudioModel
    let waveform: WaveformData
    @Environment(\.musicColors) private var colors

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let d = max(studio.duration, 0.001)
            let vr = studio.visibleRange
            let tx0 = CGFloat(vr.lowerBound / d) * w
            let tx1 = CGFloat(vr.upperBound / d) * w
            ZStack(alignment: .topLeading) {
                WaveformCanvas(waveform: waveform, range: 0...d, selection: studio.shownSelection,
                               selected: colors.accent.opacity(0.75), muted: colors.textPrimary.opacity(0.22), barWidth: 1.4, step: 2.2)
                    .equatable()
                    .frame(width: w, height: geo.size.height)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(colors.dark ? 0.10 : 0.35))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(colors.accent, lineWidth: 1.5))
                    .frame(width: max(tx1 - tx0, 10), height: geo.size.height)
                    .offset(x: min(tx0, w - max(tx1 - tx0, 10)))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let center = Double(min(max(g.location.x, 0), w) / w) * d
                let span = studio.visibleSpan
                studio.visibleStart = studio.clampedStart(center - span / 2, span: span)
            })
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(colors.textPrimary.opacity(colors.dark ? 0.05 : 0.035)))
        .accessibilityElement()
        .accessibilityLabel("Übersicht")
        .accessibilityValue("Sichtbar von \(StudioTime.format(studio.visibleRange.lowerBound, millis: false)) bis \(StudioTime.format(studio.visibleRange.upperBound, millis: false))")
    }
}

/// Platzhalter, solange die Wellenform berechnet wird: ruhig wogende Balken mit Fortschritt.
struct StudioWaveformPlaceholder: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.continuousMotion) private var motion
    let progress: Double?
    var showsLabel: Bool = true
    var animated: Bool = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colors.textPrimary.opacity(colors.dark ? 0.05 : 0.035))
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !(motion && animated))) { context in
                let t = (motion && animated) ? context.date.timeIntervalSinceReferenceDate : 0
                Canvas { ctx, size in
                    let step: CGFloat = 3.4
                    let n = Int(size.width / step)
                    let mid = size.height / 2
                    let done = CGFloat(progress ?? 0) * size.width
                    var lit = Path()
                    var dim = Path()
                    for i in 0..<max(n, 0) {
                        let p = Double(i) / Double(max(n, 1))
                        let env = 0.35 + 0.65 * sin(p * .pi) * (0.6 + 0.4 * sin(p * 9.0))
                        let wave = 0.55 + 0.45 * sin(Double(i) * 0.31 - t * 2.4) * sin(Double(i) * 0.07 + t * 0.9)
                        let h = max(1.2, CGFloat(env * wave) * (mid - 10))
                        let x = CGFloat(i) * step
                        let rect = CGRect(x: x, y: mid - h, width: 2.2, height: 2 * h)
                        if x < done { lit.addRoundedRect(in: rect, cornerSize: CGSize(width: 1.1, height: 1.1)) } else { dim.addRoundedRect(in: rect, cornerSize: CGSize(width: 1.1, height: 1.1)) }
                    }
                    ctx.fill(dim, with: .color(colors.textPrimary.opacity(colors.dark ? 0.16 : 0.12)))
                    ctx.fill(lit, with: .color(colors.accent.opacity(0.55)))
                }
            }
            if showsLabel {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).scaleEffect(0.75)
                    Text(progress.map { "Wellenform wird berechnet … \(Int(($0 * 100).rounded())) %" } ?? "Wellenform wird vorbereitet …")
                        .textStyle(Typo.labelMedium)
                        .monospacedDigit()
                        .foregroundColor(colors.textSecondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 30)
                .glassSurface(Capsule(), strong: true)
            }
        }
        .frame(height: WaveformMetrics.ruler + WaveformMetrics.wave)
        .accessibilityElement(children: .combine)
    }
}

/// Internet-Quelle: Audiospur zum Bearbeiten laden (nur auf Knopfdruck), mit Fortschritt.
struct StudioPreparePanel: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        ZStack {
            StudioWaveformPlaceholder(progress: fraction, showsLabel: false, animated: isDownloading)
                .opacity(0.8)
            VStack(spacing: 10) {
                switch studio.prepare {
                case .downloading(let p):
                    Text("Audiospur wird geladen …")
                        .textStyle(Typo.titleSmall)
                        .foregroundColor(colors.textPrimary)
                    StudioProgressBar(value: p.fraction)
                        .frame(width: 260)
                    Text(detail(p))
                        .textStyle(Typo.labelMedium)
                        .monospacedDigit()
                        .foregroundColor(colors.textSecondary)
                case .failed(let message):
                    HStack(spacing: 8) {
                        Icon(Icons.error, size: 16, color: colors.danger)
                        Text("Laden fehlgeschlagen")
                            .textStyle(Typo.titleSmall)
                            .foregroundColor(colors.textPrimary)
                    }
                    Text(message)
                        .textStyle(Typo.bodySmall)
                        .foregroundColor(colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    PillButton(title: "Erneut versuchen", icon: Icons.refresh, style: .filled) { studio.prepareForEditing() }
                default:
                    Text("Zum Schneiden die Audiospur laden")
                        .textStyle(Typo.titleSmall)
                        .foregroundColor(colors.textPrimary)
                    Text("Für Wellenform, Vorhören und Schnitt wird die Tonspur einmal geladen. Ohne Schnitt kannst du die ganze Datei auch direkt exportieren.")
                        .textStyle(Typo.bodySmall)
                        .foregroundColor(colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    PillButton(title: "Zum Bearbeiten laden", icon: Icons.download, style: .filled, minWidth: 200) { studio.prepareForEditing() }
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .frame(maxWidth: 440)
            .glassSurface(RoundedRectangle(cornerRadius: Radius.card, style: .continuous), strong: true, elevated: true)
            .animation(Motion.easeOut(), value: studio.prepare)
        }
    }

    private var isDownloading: Bool {
        if case .downloading = studio.prepare { return true }
        return false
    }

    private var fraction: Double? {
        if case .downloading(let p) = studio.prepare { return p.fraction }
        return nil
    }

    private func detail(_ p: DownloadProgress) -> String {
        let text = StudioText.download(p)
        if let f = p.fraction { return text.isEmpty ? "\(Int((f * 100).rounded())) %" : "\(Int((f * 100).rounded())) % · \(text)" }
        return text.isEmpty ? "Verbindung wird aufgebaut …" : text
    }
}

// MARK: - Zoom

struct StudioZoomControls: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        let maxZ = studio.maxZoom
        let level = maxZ > 1.0001 ? log(max(studio.zoom, 1)) / log(maxZ) : 0
        HStack(spacing: 2) {
            IconTap(icon: Icons.fitWidth, label: "Auf die Auswahl zoomen", tint: colors.textSecondary, iconSize: 17, touch: 30) {
                withAnimation(Motion.easeOut()) { studio.zoomToSelection() }
            }
            .disabled(studio.exportWholeFile)
            IconTap(icon: "zoom_out", label: "Verkleinern (⌘ + Mausrad, Zusammenziehen)", tint: colors.textSecondary, iconSize: 17, touch: 30) {
                studio.zoomBy(1 / 1.8)
            }
            .disabled(studio.zoom <= 1.0001)
            MusicSlider(value: Binding(get: { level }, set: { v in studio.setZoomLevel(pow(maxZ, v)) }),
                        range: 0...1, label: "Zoom", valueText: "\(Int(studio.zoom.rounded()))-fach")
                .frame(width: 104)
            IconTap(icon: "zoom_in", label: "Vergrößern (⌘ + Mausrad, Aufziehen)", tint: colors.textSecondary, iconSize: 17, touch: 30) {
                studio.zoomBy(1.8)
            }
            .disabled(studio.zoom >= maxZ - 0.001)
        }
    }
}

/// Trackpad (Zusammenziehen/Aufziehen, Wischen nach links/rechts) und ⌘-Mausrad über der Wellenform.
/// Lokaler Ereignis-Monitor, aktiv nur solange der Zeiger über der Wellenform steht; senkrechtes Scrollen
/// geht unverändert an die Seite weiter.
@MainActor
final class WaveformInputMonitor: ObservableObject {
    weak var studio: StudioModel?
    var width: CGFloat = 1
    var hoverX: CGFloat?
    private var monitor: Any?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
            guard let self, self.handle(event) else { return event }
            return nil
        }
    }

    func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let x = hoverX, let studio, studio.duration > 0, width > 1 else { return false }
        let anchor = Double(x / width)
        switch event.type {
        case .magnify:
            studio.zoomBy(Double(1 + event.magnification), anchor: anchor)
            return true
        case .scrollWheel:
            let precise = event.hasPreciseScrollingDeltas
            if event.modifierFlags.contains(.command) {
                let dy = Double(event.scrollingDeltaY) * (precise ? 0.012 : 0.12)
                studio.zoomBy(exp(dy), anchor: anchor)
                return true
            }
            let dx = Double(event.scrollingDeltaX)
            if abs(dx) > abs(Double(event.scrollingDeltaY)), studio.zoom > 1.0001 {
                studio.pan(by: -dx * (precise ? 1 : 8) / Double(width) * studio.visibleSpan)
                return true
            }
            return false
        default:
            return false
        }
    }
}
