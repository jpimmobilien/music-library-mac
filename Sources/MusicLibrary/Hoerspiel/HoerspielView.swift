import SwiftUI
import AppKit
import MLCore
import MLStudio

// KI-Hörbücher & Hörspiele – Hauptansicht: Kopf mit Status, sieben Unterbereiche, Einrichtung (falls nötig),
// laufende Arbeit mit Fortschritt und der jeweilige Bereich.

struct HoerspielView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @ObservedObject var hs: HoerspielModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        GeometryReader { geo in
            let bottom = Chrome.contentBottom(miniPlayer: player.current != nil)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    HSHeader(hs: hs)
                    HSSectionBar(hs: hs)
                    switch hs.setup {
                    case .unsupported(let reason):
                        StudioNotice(icon: Icons.info, title: "Auf diesem Mac nicht verfügbar", text: reason) { EmptyView() }
                    case .needsEnvironment, .needsModels:
                        HSSetupCard(hs: hs)
                    case .ready:
                        EmptyView()
                    }
                    if hs.isWorking { HSProgressCard(hs: hs).transition(.opacity) }
                    if case .failed(let message) = hs.phase {
                        StudioNotice(icon: Icons.warning, title: "Nicht abgeschlossen", text: message, tint: colors.danger) {
                            PillButton(title: "Protokoll zeigen", style: .plain) { hs.revealLog() }
                            PillButton(title: "Schließen", style: .plain) { hs.dismissError() }
                        }
                    }
                    if let notice = hs.notice {
                        StudioNotice(icon: Icons.info, title: "Hinweis", text: notice) {
                            PillButton(title: "Schließen", style: .plain) { hs.setNotice(nil) }
                        }
                    }
                    section(width: geo.size.width)
                }
                .padding(.top, Chrome.contentTop + 2)
                .padding(.bottom, bottom + 16)
                .padding(.horizontal, Spacing.gutter)
                .frame(maxWidth: 1240)
                .frame(maxWidth: .infinity)
                .animation(Motion.easeOut(Motion.medium), value: hs.isWorking)
            }
        }
        .overlay(alignment: .top) {
            WindowDragArea()
                .frame(height: Chrome.topPadding + Metrics.navBarHeight)
                .frame(maxWidth: .infinity)
        }
        .onAppear {
            hs.refreshSetup()
            hs.reload()
        }
        .onDisappear { hs.stopPlayback() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("KI-Hörbücher")
    }

    @ViewBuilder private func section(width: CGFloat) -> some View {
        switch hs.section {
        case .hoerbuch: HSCreateView(hs: hs, mode: .hoerbuch)
        case .hoerspiel: HSCreateView(hs: hs, mode: .hoerspiel)
        case .reference: HSReferenceView(hs: hs)
        case .voices: HSVoicesView(hs: hs)
        case .editor: HSEditorView(hs: hs)
        case .sound: HSSoundView(hs: hs)
        case .productions: HSProductionsView(hs: hs)
        }
    }
}

// MARK: - Kopf und Bereiche

private struct HSHeader: View {
    @ObservedObject var hs: HoerspielModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("KI-Hörbücher")
                    .textStyle(Typo.headlineLarge)
                    .foregroundColor(colors.textPrimary)
                Text("Geschichten, Stimmen, Geräusche und Musik – vollständig auf deinem Mac, ohne Cloud.")
                    .textStyle(Typo.bodyMedium)
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            HStack(spacing: 7) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(statusText)
                    .font(Typo.inter(12, .semibold))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .glassSurface(Capsule(), strong: true)
            .help("Rechnet lokal: Sprachmodell (mlx-lm), Stimmen (Qwen3-TTS), Geräusche, Musik über KI-Musik")
        }
        .padding(.horizontal, 4)
    }

    private var statusText: String {
        switch hs.setup {
        case .unsupported: return "Nicht verfügbar"
        case .needsEnvironment, .needsModels: return hs.installing ? "Wird eingerichtet" : "Einrichtung nötig"
        case .ready: return hs.isWorking ? "Arbeitet …" : "Bereit · lokal"
        }
    }

    private var statusColor: Color {
        switch hs.setup {
        case .ready: return hs.isWorking ? colors.accent : Color(argb: 0xFF34C759)
        case .unsupported: return colors.danger
        default: return Color(argb: 0xFFFF9F0A)
        }
    }
}

private struct HSSectionBar: View {
    @ObservedObject var hs: HoerspielModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        StudioFlow(spacing: 8) {
            ForEach(HoerspielModel.Section.allCases) { s in
                let on = hs.section == s
                Button { hs.section = s } label: {
                    HStack(spacing: 6) {
                        Icon(s.icon, size: 15, color: on ? colors.accentText : colors.textSecondary)
                        Text(s.title)
                            .font(Typo.inter(12.5, on ? .semibold : .medium))
                            .foregroundColor(on ? colors.accentText : colors.textPrimary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Capsule().fill(on ? colors.accentSoft : Color.clear))
                    .glassSurface(Capsule(), interactive: true)
                }
                .buttonStyle(PressScaleStyle(scale: 0.96))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

// MARK: - Einrichtung

private struct HSSetupCard: View {
    @ObservedObject var hs: HoerspielModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(colors: [colors.accent.opacity(0.9), colors.accentStrong], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 64, height: 64)
                    Icon(Icons.audiobook, size: 32, color: .white)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("KI-Hörbücher einrichten")
                        .textStyle(Typo.headlineSmall)
                        .foregroundColor(colors.textPrimary)
                    Text("Einmalig werden eine Python-Umgebung (mlx-audio, mlx-lm, Whisper – ca. 1 GB), ein Sprachmodell für Geschichten (\(hs.storyModel?.title ?? "–"), \(KIFormat.bytes(hs.storyModel?.bytes ?? 0))) und das Stimmmodell Qwen3-TTS (ca. 9 GB) geladen. Danach entstehen Geschichten und Stimmen ohne Internet.")
                        .textStyle(Typo.bodyMedium)
                        .foregroundColor(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                point(Icons.shield, "Quellen: Python-Pakete von PyPI, uv von Astral (geprüfte Prüfsumme), Modelle von Hugging Face – nur auf Knopfdruck. Geräusch- und Analysemodelle lädst du bei Bedarf in den Einstellungen.")
                point(Icons.lock, "Geschichten, Stimmen und Referenzaufnahmen verlassen den Mac nicht. Der Rechenprozess läuft ohne Netzwerkzugriff.")
                point(Icons.voice, "Stimmen werden aus Beschreibungen entworfen. Echte Stimmen realer Personen nur mit dokumentierter, geprüfter Einwilligung.")
                if let free = hs.freeSpace, let story = hs.storyModel {
                    point(Icons.hardDrive, "Frei: \(KIFormat.bytes(free)) – gebraucht werden etwa \(KIFormat.bytes(HSHardware.requiredBytes(story: story))) (mit Geräuschen und Analyse).")
                }
                if case .limited(_, let reason) = hs.support { point(Icons.info, reason) }
            }
            switch hs.installTask {
            case .running(let title, let p):
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(title).textStyle(Typo.titleSmall).foregroundColor(colors.textPrimary)
                        Spacer()
                        PillButton(title: "Abbrechen", style: .plain) { hs.cancelInstall() }
                    }
                    if let f = p.fraction { ProgressView(value: f).tint(colors.accent) } else { ProgressView().progressViewStyle(.linear).tint(colors.accent) }
                    Text(p.step).textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).lineLimit(2)
                }
            case .failed(let message):
                StudioNotice(icon: Icons.warning, title: "Einrichtung unterbrochen", text: message, tint: colors.danger) {
                    PillButton(title: "Erneut versuchen", icon: Icons.refresh, style: .filled) { hs.installEverything() }
                    PillButton(title: "Protokoll", style: .plain) { hs.revealLog() }
                }
            case .idle:
                HStack(spacing: 10) {
                    PillButton(title: "Jetzt einrichten", icon: Icons.download, style: .filled) { hs.installEverything() }
                    Text("Abbrechen ist jederzeit möglich; ein neuer Versuch setzt fort.")
                        .textStyle(Typo.bodySmall)
                        .foregroundColor(colors.textTertiary)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous), strong: true)
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Icon(icon, size: 15, color: colors.accentText).padding(.top, 1)
            Text(text).textStyle(Typo.bodySmall).foregroundColor(colors.textPrimary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Fortschritt

struct HSProgressCard: View {
    @ObservedObject var hs: HoerspielModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            if case .working(let title, let detail, let progress, let started) = hs.phase {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text(title).textStyle(Typo.titleMedium).foregroundColor(colors.textPrimary)
                        Spacer()
                        Text(HSFormat.elapsed(ctx.date.timeIntervalSince(started)))
                            .font(Typo.inter(12, .medium)).monospacedDigit()
                            .foregroundColor(colors.textSecondary)
                        PillButton(title: "Abbrechen", style: .plain) { hs.cancel() }
                    }
                    if let progress { ProgressView(value: progress).tint(colors.accent) } else { ProgressView().progressViewStyle(.linear).tint(colors.accent) }
                    Text(detail).textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).lineLimit(2)
                    if let p = hs.current { HSStepsRow(production: p) }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous), strong: true)
            }
        }
    }
}

/// Die acht Produktionsschritte mit Stand.
struct HSStepsRow: View {
    let production: HSProduction
    @Environment(\.musicColors) private var colors

    var body: some View {
        StudioFlow(spacing: 6) {
            ForEach(steps, id: \.self) { step in
                let state = production.state(step)
                HStack(spacing: 5) {
                    Circle().fill(color(state)).frame(width: 7, height: 7)
                    Text(step.title).font(Typo.inter(11.5, .medium)).foregroundColor(colors.textPrimary)
                }
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(Capsule().fill(colors.textPrimary.opacity(0.05)))
                .help(HSFormat.state(state))
            }
        }
    }

    private var steps: [HSStep] {
        HSStep.allCases.filter { s in
            switch s {
            case .sfx: return production.useSFX
            case .music: return production.useMusic
            default: return true
            }
        }
    }

    private func color(_ s: HSStepState) -> Color {
        switch s {
        case .done: return Color(argb: 0xFF34C759)
        case .running: return colors.accent
        case .failed: return colors.danger
        case .outdated: return Color(argb: 0xFFFF9F0A)
        case .pending: return colors.textTertiary.opacity(0.5)
        }
    }
}

enum HSFormat {
    static func elapsed(_ s: TimeInterval) -> String {
        let t = Int(s.rounded())
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }

    static func duration(_ s: Double) -> String {
        let t = Int(s.rounded())
        return t >= 3600 ? "\(t / 3600) h \(t / 60 % 60) min" : (t >= 60 ? "\(t / 60) min \(t % 60) s" : "\(t) s")
    }

    static func state(_ s: HSStepState) -> String {
        switch s {
        case .pending: return "Offen"
        case .running: return "Läuft"
        case .done: return "Fertig"
        case .failed: return "Fehler – erneut starten setzt fort"
        case .outdated: return "Veraltet – nach einer Änderung neu erzeugen"
        }
    }

    static func label(_ t: String, _ colors: MusicColors) -> some View {
        Text(t.uppercased()).font(Typo.inter(10.5, .semibold)).tracking(0.6).foregroundColor(colors.textTertiary)
    }
}
