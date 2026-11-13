import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MLCore
import MLStudio

// Audio Studio (2.2) – Hauptansicht im Fenster der Bibliothek (siebter Eintrag der Navigation).
//
// Aufbau: links die Arbeitsspalte (Kopf, Quelle, Ausschnitt, Format, Metadaten, Ziel) mit schwebender
// Exportleiste; rechts – bei breitem Fenster – die Glas-Spalte mit Warteschlange und Verlauf, sonst als
// Abschnitt unten. Dateien lassen sich auf das ganze Studio ziehen.

struct StudioView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    @State private var dropTargeted = false
    @State private var queueTab: StudioQueueTab = .queue
    @State private var askDuplicates = false

    /// Ab dieser Breite steht die Warteschlange als eigene Spalte rechts.
    static let columnBreakpoint: CGFloat = 1140
    /// Größte Breite von Arbeitsfläche und Spalte zusammen.
    static let maxContentWidth: CGFloat = 1680
    /// Größte Breite der Arbeitsfläche.
    static let maxMainWidth: CGFloat = 1240

    var body: some View {
        GeometryReader { geo in
            // Eigene Spalte nur, wenn es Aufträge oder Verlauf gibt – sonst bekommt die Arbeitsfläche die ganze Breite
            let wide = geo.size.width >= Self.columnBreakpoint && (!studio.jobs.isEmpty || !studio.history.entries.isEmpty)
            let queueWidth: CGFloat = geo.size.width >= 1440 ? 372 : 336
            let bottom = Chrome.contentBottom(miniPlayer: player.current != nil)
            HStack(alignment: .top, spacing: 18) {
                StudioMainColumn(studio: studio, wide: wide, bottomInset: bottom, queueTab: $queueTab, askDuplicates: $askDuplicates)
                    .frame(maxWidth: .infinity)
                if wide {
                    StudioQueuePanel(studio: studio, tab: $queueTab, column: true)
                        .frame(width: queueWidth)
                        .padding(.top, Chrome.contentTop + 2)
                        .padding(.bottom, bottom)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            // Vollbild: Arbeitsfläche und Spalte bleiben beieinander (mittig) statt auseinanderzudriften
            .frame(maxWidth: Self.maxContentWidth)
            .padding(.leading, Spacing.gutter)
            .padding(.trailing, wide ? 18 : Spacing.gutter)
            .frame(maxWidth: .infinity)
            .animation(Motion.easeOut(Motion.medium), value: wide)
        }
        // Obere Zeile (neben der Navigation) verschiebt das Fenster wie eine Titelleiste
        .overlay(alignment: .top) {
            WindowDragArea()
                .frame(height: Chrome.topPadding + Metrics.navBarHeight)
                .frame(maxWidth: .infinity)
        }
        .overlay { if dropTargeted { StudioDropOverlay().transition(.opacity) } }
        .animation(Motion.easeOut(Motion.short), value: dropTargeted)
        .onDrop(of: [UTType.fileURL, UTType.url, UTType.plainText], isTargeted: $dropTargeted) { providers in
            StudioDrop.handle(providers, studio: studio)
        }
        .onAppear {
            if !studio.demo { studio.refreshToolStatus() }
            if studio.demo && StudioDemo.askDuplicates { askDuplicates = true }
            if studio.jobs.isEmpty && !studio.history.entries.isEmpty { queueTab = .history }
            if studio.demo, let tab = StudioDemo.queueTab { queueTab = tab }
        }
        .onChange(of: studio.jobs.count) { count in
            if count > 0 { queueTab = .queue }
        }
        .onChange(of: studio.source?.id) { _ in askDuplicates = false }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Audio Studio")
    }
}

/// Arbeitsspalte: scrollt; die Exportleiste schwebt unten.
private struct StudioMainColumn: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    let wide: Bool
    let bottomInset: CGFloat
    @Binding var queueTab: StudioQueueTab
    @Binding var askDuplicates: Bool

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let twoColumns = width >= 900
            let showsBar = studio.showsEditor
            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 16) {
                            StudioHeader(studio: studio, showsJobs: !wide) {
                                withAnimation(Motion.easeOut()) { proxy.scrollTo(StudioAnchor.queue, anchor: .top) }
                            }
                            .studioAnchor(.top)
                            if studio.mode != .edit {
                                StudioSourceInput(studio: studio)
                            }
                            if studio.isEmptyStudio {
                                StudioEmptyState(studio: studio, columns: width >= 760 ? 3 : 1)
                            } else {
                                StudioSourceCard(studio: studio)
                            }
                            if studio.showsEditor {
                                StudioEditorCard(studio: studio)
                                    .studioAnchor(.editor)
                                if studio.mode == .edit {
                                    TrackEditTools(studio: studio, width: width)
                                        .transition(.opacity)
                                }
                                exportSection(twoColumns: twoColumns, width: width)
                            }
                            if !wide && (!studio.jobs.isEmpty || !studio.history.entries.isEmpty) {
                                StudioQueuePanel(studio: studio, tab: $queueTab, column: false)
                                    .studioAnchor(.queue)
                            }
                        }
                        .padding(.top, Chrome.contentTop + 2)
                        .padding(.bottom, bottomInset + (showsBar ? 92 : 12))
                        .frame(maxWidth: StudioView.maxMainWidth)
                        .frame(maxWidth: .infinity)
                        .animation(Motion.easeOut(Motion.medium), value: studio.isEmptyStudio)
                        .animation(Motion.easeOut(Motion.medium), value: studio.showsEditor)
                        .animation(Motion.easeOut(Motion.medium), value: studio.mode)
                    }
                    .onAppear { StudioScrollSeed.apply(proxy) }
                }
                if showsBar {
                    // Inhalte laufen vor der Exportleiste weich aus (statt hart unter Leiste und Mini-Player)
                    EdgeFade(top: false, strength: 0.8)
                        .frame(height: bottomInset + 104)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    StudioExportBar(studio: studio, askDuplicates: $askDuplicates, export: startExport, proceed: proceed)
                        .frame(maxWidth: StudioView.maxMainWidth)
                        .padding(.bottom, bottomInset - 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Motion.easeOut(Motion.medium), value: showsBar)
            // Kleine Fenster: flachere Wellenform, damit Bedienleiste und Zeiten über der Exportleiste bleiben
            .environment(\.studioWaveHeight, geo.size.height < 760 ? WaveformMetrics.compactWave : WaveformMetrics.wave)
        }
    }

    @ViewBuilder
    private func exportSection(twoColumns: Bool, width: CGFloat) -> some View {
        if studio.mode == .edit {
            // Bearbeiten: Format und Speichern (Tags, Cover und Liedtexte bleiben wie im Original)
            if twoColumns {
                HStack(alignment: .top, spacing: 16) {
                    StudioFormatCard(studio: studio)
                        .frame(maxWidth: .infinity)
                    StudioDestinationCard(studio: studio, compact: true)
                        .frame(maxWidth: .infinity)
                        .studioAnchor(.destination)
                }
                .studioAnchor(.export)
            } else {
                StudioFormatCard(studio: studio)
                    .studioAnchor(.export)
                StudioDestinationCard(studio: studio, compact: width < 720)
                    .studioAnchor(.destination)
            }
        } else if twoColumns {
            HStack(alignment: .top, spacing: 16) {
                StudioFormatCard(studio: studio)
                    .frame(maxWidth: .infinity)
                StudioMetadataCard(studio: studio, compact: width < 1060)
                    .frame(maxWidth: .infinity)
                    .studioAnchor(.metadata)
            }
            .studioAnchor(.export)
        } else {
            StudioFormatCard(studio: studio)
                .studioAnchor(.export)
            StudioMetadataCard(studio: studio, compact: width < 560)
                .studioAnchor(.metadata)
        }
        if studio.mode != .edit {
            StudioDestinationCard(studio: studio, compact: width < 720)
                .studioAnchor(.destination)
        }
    }

    /// „Exportieren“: beim Ersetzen erst bestätigen, bei möglichen Dubletten erst nachfragen.
    private func startExport() {
        if studio.replacesOriginal {
            StudioDialogs.confirmReplace(studio: studio)
            return
        }
        if !askDuplicates && (!studio.shownDuplicates.isEmpty || studio.previousExport != nil) {
            withAnimation(Motion.easeOut()) { askDuplicates = true }
            return
        }
        proceed()
    }

    private func proceed() {
        withAnimation(Motion.easeOut()) { askDuplicates = false }
        studio.addToQueue()
    }
}

/// Kopf: großer Titel, Unterzeile, rechts Aufträge (schmales Fenster) und Werkzeug-Status.
private struct StudioHeader: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    let showsJobs: Bool
    let showQueue: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(studio.mode == .edit ? "Titel bearbeiten" : (studio.isLibraryTrack ? "Schneiden" : "Audio Studio"))
                        .textStyle(Typo.headlineLarge)
                        .foregroundColor(colors.textPrimary)
                        .lineLimit(1)
                        .fixedSize()
                    if studio.isLibraryTrack, let title = studio.source?.title {
                        Text("· \(title)")
                            .textStyle(Typo.headlineLarge)
                            .foregroundColor(colors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Text(studio.mode == .edit
                     ? "Lautstärke, Tempo, Tonhöhe, Stimmung, Equalizer, Auto-Tune und Verbesserung – dauerhaft gespeichert."
                     : studio.isLibraryTrack
                     ? "Titel aus deiner Bibliothek – speichere den Ausschnitt als neue Datei oder ersetze das Original."
                     : "Laden, schneiden und umwandeln – direkt in deine Musikbibliothek.")
                    .textStyle(Typo.bodyMedium)
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            if studio.isLibraryTrack {
                SegmentedControl(options: [StudioModel.StudioMode.convert, .edit], selection: modeBinding,
                                 label: { $0 == .edit ? "Bearbeiten" : "Schneiden" },
                                 icon: { $0 == .edit ? Icons.tune : Icons.cut }, height: 32)
                    .frame(width: 230)
                    .help("Nur schneiden oder den Klang dauerhaft bearbeiten")
            }
            if showsJobs, let chip = jobChipText {
                Button(action: showQueue) {
                    HStack(spacing: 7) {
                        if studio.activeJob != nil { ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14) }
                        else { Icon(Icons.queue, size: 14, color: colors.accentText) }
                        Text(chip)
                            .font(Typo.inter(12, .semibold))
                            .monospacedDigit()
                            .foregroundColor(colors.accentText)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .glassSurface(Capsule(), strong: true, interactive: true)
                    .contentShape(Capsule())
                }
                .buttonStyle(PressScaleStyle(scale: 0.96))
                .help("Zur Warteschlange")
                .accessibilityLabel("Warteschlange: \(chip)")
            }
            StudioToolsChip(studio: studio)
        }
        .padding(.horizontal, 4)
    }

    private var modeBinding: Binding<StudioModel.StudioMode> {
        Binding(get: { studio.mode }, set: { $0 == .edit ? studio.enterEditMode() : studio.leaveEditMode() })
    }

    private var jobChipText: String? {
        if let job = studio.activeJob {
            return "\(job.phase.label) · \(Int((job.overallProgress * 100).rounded())) %"
        }
        let open = studio.unfinishedJobCount
        return open > 0 ? (open == 1 ? "1 Auftrag" : "\(open) Aufträge") : nil
    }
}

/// Hervorhebung beim Ziehen von Dateien auf das Studio.
private struct StudioDropOverlay: View {
    @Environment(\.musicColors) private var colors

    var body: some View {
        ZStack {
            colors.background.opacity(0.35)
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(colors.accentSoft)
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(colors.accent, style: StrokeStyle(lineWidth: 2.5, dash: [10, 8])))
                .padding(.horizontal, 18)
                .padding(.top, Chrome.contentTop - 4)
                .padding(.bottom, 18)
            VStack(spacing: 10) {
                Icon(Icons.download, size: 38, color: colors.accentText)
                Text("Zum Öffnen loslassen")
                    .textStyle(Typo.headlineSmall)
                    .foregroundColor(colors.textPrimary)
                Text("Audio- und Videodateien oder ein Link – mehrere Dateien kommen als Aufträge in die Warteschlange.")
                    .textStyle(Typo.bodyMedium)
                    .foregroundColor(colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            .padding(28)
            .glassSurface(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous), strong: true, elevated: true)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Ziehen und Ablegen

@MainActor
enum StudioDrop {
    /// Dateien → `importFiles`; ein Link (z. B. aus Safari) → Eingabefeld und Analyse.
    static func handle(_ providers: [NSItemProvider], studio: StudioModel) -> Bool {
        guard !providers.isEmpty else { return false }
        let group = DispatchGroup()
        let found = Collected()
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url, url.isFileURL { found.add(file: url) }
                    group.leave()
                }
            } else if p.canLoadObject(ofClass: URL.self) {
                group.enter()
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url, url.scheme?.hasPrefix("http") == true { found.add(link: url) }
                    group.leave()
                }
            } else if p.canLoadObject(ofClass: NSString.self) {
                group.enter()
                _ = p.loadObject(ofClass: NSString.self) { text, _ in
                    if let s = text as? String {
                        for line in s.split(whereSeparator: \.isNewline) {
                            if let u = URL(string: line.trimmingCharacters(in: .whitespaces)), u.scheme?.hasPrefix("http") == true {
                                found.add(link: u)
                            }
                        }
                    }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            Task { @MainActor in
                let (files, links) = found.result()
                if !files.isEmpty {
                    studio.importFiles(files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
                } else if !links.isEmpty {
                    studio.urlText = links.map(\.absoluteString).joined(separator: "\n")
                    studio.analyzeInput()
                }
            }
        }
        return true
    }

    /// Gesammelte Adressen (Rückrufe kommen auf beliebigen Threads).
    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var files: [URL] = []
        private var links: [URL] = []

        func add(file: URL) { lock.lock(); files.append(file); lock.unlock() }
        func add(link: URL) { lock.lock(); links.append(link); lock.unlock() }
        func result() -> ([URL], [URL]) { lock.lock(); defer { lock.unlock() }; return (files, links) }
    }
}

// MARK: - Sprungziele (Scrollen)

enum StudioAnchor: Hashable {
    case top, editor, export, metadata, destination, queue
}

extension View {
    /// Sprungziel knapp oberhalb der Ansicht: Beim Scrollen dorthin bleibt Platz für die schwebende Navigation.
    func studioAnchor(_ anchor: StudioAnchor) -> some View {
        background(alignment: .top) {
            // Ausrichtungslinie statt `offset`: Nur die Lage im Layout zählt für `scrollTo`.
            Color.clear
                .frame(width: 1, height: 1)
                .alignmentGuide(.top) { d in d[.top] + Chrome.contentTop + 6 }
                .id(anchor)
                .accessibilityHidden(true)
        }
    }
}

/// Vorschaubilder: Studio beim Öffnen an eine Stelle scrollen (z. B. zum Export).
@MainActor
enum StudioScrollSeed {
    static var pending: StudioAnchor?

    static func apply(_ proxy: ScrollViewProxy) {
        guard let target = pending else { return }
        pending = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            proxy.scrollTo(target, anchor: .top)
        }
    }
}
