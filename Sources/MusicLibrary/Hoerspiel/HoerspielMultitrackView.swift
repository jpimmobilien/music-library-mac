import SwiftUI
import AppKit
import MLCore
import MLStudio

// Mehrspur-Editor: Erzähler, Sprecher, Musik, Geräusche, Atmo als Spuren. Solo, Stumm, Lautstärke je Spur;
// Clips verschieben, schneiden, ein-/ausblenden, Pegel; Übergänge verlängern/kürzen; danach „Neu abmischen“.
// Alles verlustfrei – die Quellclips bleiben unverändert.

struct HSMultitrackView: View {
    @ObservedObject var hs: HoerspielModel
    let productionID: UUID
    @Environment(\.musicColors) private var colors
    @State private var timeline: HSTimeline?
    @State private var loadedFrom: Date?
    @State private var selected: String?
    @State private var scale: CGFloat = 12        // Punkte je Sekunde
    @State private var playhead: Double = 0
    @State private var dirty = false
    @State private var drag: (id: String, dx: CGFloat)?

    private let header: CGFloat = 190
    private let rowHeight: CGFloat = 46

    var body: some View {
        if let p = hs.production(productionID) {
            if p.mix == nil {
                StudioNotice(icon: Icons.info, title: "Noch keine Mischung", text: "Der Mehrspur-Editor öffnet die fertige Mischung. Zuerst die Produktion abschließen (Schritt „Audio abmischen“).") {
                    PillButton(title: "Abmischen", style: .filled) { hs.runStep(.mix, productionID) }.disabled(hs.isWorking || hs.setup != .ready)
                }
            } else if let t = timeline {
                VStack(alignment: .leading, spacing: 10) {
                    toolbar(p, t)
                    tracks(p, t)
                    inspector(t)
                }
                .padding(14)
                .glassSurface(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .onChange(of: p.mix?.date) { _ in reload(p) }
            } else {
                Text("Die Zeitleiste dieser Mischung fehlt (ältere Mischung). „Neu abmischen“ in „Meine Produktionen“ legt sie an.")
                    .textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary)
                    .onAppear { reload(p) }
            }
        }
    }

    private func reload(_ p: HSProduction) {
        timeline = hs.loadTimeline(p)
        loadedFrom = p.mix?.date
        dirty = false
        selected = nil
    }

    // MARK: Werkzeugleiste

    private func toolbar(_ p: HSProduction, _ t: HSTimeline) -> some View {
        HStack(spacing: 10) {
            GlassIconButton(icon: hs.playingKey == "mt-\(p.id)" ? Icons.pause : Icons.play, label: "Mischung ab Abspielposition anhören", size: 32, iconSize: 15) {
                if let mix = p.mix { hs.playFrom(hs.file(mix.master, in: p), key: "mt-\(p.id)", at: playhead) }
            }
            Text(HSFormat.elapsed(playhead)).font(Typo.inter(12, .medium)).monospacedDigit().foregroundColor(colors.textSecondary).frame(width: 56)
            HStack(spacing: 6) {
                Icon("zoom_out", size: 14, color: colors.textTertiary)
                Slider(value: $scale, in: 2...80).frame(width: 140)
                Icon("zoom_in", size: 14, color: colors.textTertiary)
            }
            Spacer()
            if dirty { Text("Geändert – noch nicht abgemischt").textStyle(Typo.bodySmall).foregroundColor(Color(argb: 0xFFFF9F0A)) }
            PillButton(title: "Verwerfen", style: .plain) { reload(p) }.disabled(!dirty)
            PillButton(title: "Neu abmischen", icon: Icons.instantMix, style: .filled) {
                hs.renderTimeline(productionID, t)
                dirty = false
            }
            .disabled(!dirty || hs.isWorking || hs.setup != .ready)
        }
    }

    // MARK: Spuren

    private func tracks(_ p: HSProduction, _ t: HSTimeline) -> some View {
        let width = max(600, CGFloat(t.duration + 10) * scale)
        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                Color.clear.frame(height: 22)
                ForEach(t.orderedTracks, id: \.name) { track in trackHeader(track).frame(height: rowHeight) }
            }
            .frame(width: header)
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    ruler(t, width: width)
                    ForEach(t.orderedTracks, id: \.name) { track in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(colors.textPrimary.opacity(t.audible(track.name) ? 0.035 : 0.015))
                            ForEach(t.clips(on: track.name)) { c in clipView(c, track: track, audible: t.audible(track.name)) }
                        }
                        .frame(width: width, height: rowHeight)
                        .overlay(alignment: .bottom) { Hairline() }
                    }
                }
                .overlay(alignment: .topLeading) {
                    Rectangle().fill(colors.accent).frame(width: 1.5).offset(x: CGFloat(playhead) * scale).allowsHitTesting(false)
                }
            }
        }
    }

    private func ruler(_ t: HSTimeline, width: CGFloat) -> some View {
        let step: Double = scale > 40 ? 1 : scale > 15 ? 5 : scale > 6 ? 10 : 30
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.clear)
            ForEach(Array(stride(from: 0.0, through: t.duration + 10, by: step)), id: \.self) { s in
                Text(HSFormat.elapsed(s)).font(Typo.inter(9.5, .medium)).monospacedDigit().foregroundColor(colors.textTertiary)
                    .offset(x: CGFloat(s) * scale + 2, y: 3)
            }
            ForEach(t.chapters, id: \.start) { c in
                Rectangle().fill(colors.accentText.opacity(0.6)).frame(width: 1, height: 22).offset(x: CGFloat(c.start) * scale)
                    .help(c.title)
            }
        }
        .frame(width: width, height: 22)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onEnded { v in playhead = max(0, Double(v.location.x / scale)) })
        .help("Klicken setzt die Abspielposition")
    }

    private func trackHeader(_ track: HSTrack) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name.replacingOccurrences(of: "Sprecher ", with: "")).font(Typo.inter(12, .semibold)).foregroundColor(colors.textPrimary).lineLimit(1)
                Slider(value: Binding(get: { track.gainDB }, set: { v in edit { $0.setTrack(track.name) { $0.gainDB = v.rounded() } } }), in: -24...12)
                    .controlSize(.mini)
                    .help(String(format: "Spur-Lautstärke %.0f dB", track.gainDB))
            }
            toggle("M", on: track.mute, help: "Stumm") { edit { $0.setTrack(track.name) { $0.mute.toggle() } } }
            toggle("S", on: track.solo, help: "Solo") { edit { $0.setTrack(track.name) { $0.solo.toggle() } } }
        }
        .padding(.horizontal, 8)
    }

    private func toggle(_ title: String, on: Bool, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Typo.inter(11, .bold)).foregroundColor(on ? colors.onAccent : colors.textSecondary)
                .frame(width: 22, height: 20)
                .background(RoundedRectangle(cornerRadius: 5).fill(on ? colors.accent : colors.textPrimary.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func clipView(_ c: HSClip, track: HSTrack, audible: Bool) -> some View {
        let dx = drag?.id == c.id ? drag!.dx : 0
        let isSel = selected == c.id
        let tint: Color = track.isVoice ? colors.accent : track.name == "Musik" ? Color(argb: 0xFF5E8BFF) : track.name == "Atmo" ? Color(argb: 0xFF34C759) : Color(argb: 0xFFFF9F0A)
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(tint.opacity(audible ? (isSel ? 0.55 : 0.32) : 0.12))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(isSel ? tint : .clear, lineWidth: 1.5))
            .overlay(alignment: .leading) {
                Text(c.label).font(Typo.inter(10, .medium)).foregroundColor(colors.textPrimary).lineLimit(1).padding(.horizontal, 5)
            }
            .frame(width: max(3, CGFloat(c.duration) * scale), height: rowHeight - 12)
            .offset(x: CGFloat(c.start) * scale + dx)
            .onTapGesture { selected = c.id }
            .gesture(DragGesture(minimumDistance: 3)
                .onChanged { v in drag = (c.id, v.translation.width) }
                .onEnded { v in
                    edit { $0.move(c.id, to: c.start + Double(v.translation.width / scale)) }
                    drag = nil
                    selected = c.id
                })
            .help("\(c.label)\nStart \(HSFormat.elapsed(c.start)) · \(String(format: "%.1f s", c.duration)) – ziehen zum Verschieben")
    }

    // MARK: Auswahl

    @ViewBuilder private func inspector(_ t: HSTimeline) -> some View {
        if let id = selected, let c = t.clips.first(where: { $0.id == id }) {
            HStack(spacing: 14) {
                Text(c.label).textStyle(Typo.bodySmall).foregroundColor(colors.textPrimary).lineLimit(1).frame(maxWidth: 260, alignment: .leading)
                stepper("Pegel", value: c.gainDB, unit: "dB", step: 1) { v in edit { $0.update(id) { $0.gainDB = v } } }
                stepper("Einblenden", value: c.fadeIn, unit: "s", step: 0.25) { v in edit { $0.update(id) { $0.fadeIn = v } } }
                stepper("Ausblenden", value: c.fadeOut, unit: "s", step: 0.25) { v in edit { $0.update(id) { $0.fadeOut = v } } }
                PillButton(title: "Am Abspielkopf schneiden", icon: Icons.cut, style: .tonal) {
                    edit { if let new = $0.split(id, at: playhead) { selected = new } }
                }
                .disabled(playhead <= c.start || playhead >= c.end)
                PillButton(title: "Entfernen", icon: Icons.delete, style: .plain) { edit { $0.remove(id) }; selected = nil }
            }
        } else {
            HStack(spacing: 10) {
                Text("Clip anklicken zum Bearbeiten · Lineal anklicken setzt die Abspielposition.")
                    .textStyle(Typo.bodySmall).foregroundColor(colors.textTertiary)
                Spacer()
                PillButton(title: "Ab Abspielposition +1 s Pause", style: .plain) { edit { $0.shift(from: playhead, by: 1) } }
                PillButton(title: "−1 s", style: .plain) { edit { $0.shift(from: playhead, by: -1) } }
            }
        }
    }

    private func stepper(_ title: String, value: Double, unit: String, step: Double, _ set: @escaping (Double) -> Void) -> some View {
        Stepper(value: Binding(get: { value }, set: set), step: step) {
            Text("\(title) \(String(format: step < 1 ? "%.2f" : "%.0f", value)) \(unit)").font(Typo.inter(11.5, .medium)).monospacedDigit()
        }
        .fixedSize()
    }

    private func edit(_ change: (inout HSTimeline) -> Void) {
        guard var t = timeline else { return }
        change(&t)
        timeline = t
        dirty = true
    }
}
