import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MLCore
import MLStudio

// Audio Studio – Quelle: großes Glas-Eingabefeld (eine oder mehrere Adressen), Einfügen, Datei öffnen,
// Quellkarte mit Vorschaubild und Formatangaben, Zustände (Analyse, Fehler, Spotify, Live) und Leerzustand.

// MARK: - Eingabe

struct StudioSourceInput: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    @FocusState private var focused: Bool

    var body: some View {
        let lines = Self.addressCount(studio.urlText)
        let empty = studio.urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Icon(Icons.link, size: 19, color: focused ? colors.accentText : colors.textSecondary)
                    .padding(.leading, 2)
                ZStack(alignment: .leading) {
                    if studio.urlText.isEmpty {
                        Text("YouTube- oder SoundCloud-Adresse einfügen …")
                            .font(Typo.inter(15, .regular))
                            .foregroundColor(colors.textTertiary)
                            .lineLimit(1)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $studio.urlText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(Typo.inter(15, .regular))
                        .foregroundColor(colors.textPrimary)
                        .lineLimit(1...4)
                        .focused($focused)
                        .onSubmit { if !empty { studio.analyzeInput() } }
                        .accessibilityLabel("Adresse oder mehrere Adressen, je Zeile eine")
                }
                if !studio.urlText.isEmpty {
                    IconTap(icon: Icons.clear, label: "Eingabe leeren", tint: colors.textSecondary, iconSize: 14, touch: 26) {
                        studio.urlText = ""
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        PillButton(title: "Einfügen", icon: Icons.paste) { studio.pasteFromClipboard() }
                            .help("Adresse oder Dateien aus der Zwischenablage einfügen und analysieren")
                        PillButton(title: "Datei öffnen …", icon: Icons.audioFile) { studio.chooseFiles() }
                            .help("Audio- oder Videodateien öffnen")
                        analyzeButton(lines: lines, empty: empty, compact: false)
                    }
                    .fixedSize()
                    HStack(spacing: 2) {
                        IconTap(icon: Icons.paste, label: "Einfügen", tint: colors.accentText, iconSize: 18, touch: 34) { studio.pasteFromClipboard() }
                        IconTap(icon: Icons.audioFile, label: "Datei öffnen …", tint: colors.accentText, iconSize: 18, touch: 34) { studio.chooseFiles() }
                        analyzeButton(lines: lines, empty: empty, compact: true)
                    }
                    .fixedSize()
                }
                // Schaltflächen zuerst ausmessen: mit Beschriftung, solange Platz ist – das Feld nimmt den Rest
                .layoutPriority(1)
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .frame(minHeight: 54)
            .glassSurface(RoundedRectangle(cornerRadius: Radius.card, style: .continuous), strong: true, elevated: focused)
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(colors.accent.opacity(focused ? 0.55 : 0), lineWidth: 1.5))
            .animation(Motion.easeOut(Motion.short), value: focused)
            if lines > 1 {
                StudioInfoLine(text: "\(lines) Adressen – sie kommen als einzelne Aufträge mit den gemeinsamen Einstellungen in die Warteschlange.", icon: Icons.queue, tint: colors.accentText)
                    .padding(.horizontal, 6)
                    .transition(.opacity)
            }
        }
        .animation(Motion.easeOut(), value: lines > 1)
    }

    @ViewBuilder
    private func analyzeButton(lines: Int, empty: Bool, compact: Bool) -> some View {
        PillButton(title: lines > 1 ? "\(lines) analysieren" : "Analysieren", icon: compact ? nil : Icons.search, style: .filled) {
            studio.analyzeInput()
        }
        .disabled(empty)
        .help("Adresse prüfen (Eingabetaste)")
    }

    /// Anzahl der Zeilen mit Inhalt (je Zeile eine Adresse).
    static func addressCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isNewline).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }
}

// MARK: - Quellkarte

struct StudioSourceCard: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors

    var body: some View {
        switch studio.sourceState {
        case .analyzing(let text):
            StudioAnalyzingCard(text: text) { studio.clearSource() }
                .transition(.opacity)
        case .failed(let message):
            StudioFailedCard(studio: studio, message: message)
                .transition(.opacity)
        case .ready, .empty:
            if let source = studio.source {
                StudioSourceInfoCard(studio: studio, source: source)
                    .transition(.opacity)
            }
        }
    }
}

/// Karte während der Analyse: Skelett mit Schimmer.
private struct StudioAnalyzingCard: View {
    @Environment(\.musicColors) private var colors
    let text: String
    let cancel: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            StudioSkeleton(width: 160, height: 90, radius: Radius.artwork)
            VStack(alignment: .leading, spacing: 9) {
                StudioSkeleton(width: 70, height: 18, radius: 9)
                StudioSkeleton(width: 280, height: 16)
                StudioSkeleton(width: 170, height: 12)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).scaleEffect(0.75)
                    Text(text.isEmpty ? "Quelle wird analysiert …" : text)
                        .textStyle(Typo.labelMedium)
                        .foregroundColor(colors.textSecondary)
                }
            }
            Spacer(minLength: 0)
            PillButton(title: "Abbrechen", style: .plain) { cancel() }
        }
        .studioShimmer()
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.card + 4, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text.isEmpty ? "Quelle wird analysiert" : text)
    }
}

/// Verständlicher Fehler mit passenden Wegen weiter.
private struct StudioFailedCard: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    let message: String

    var body: some View {
        let kind = Self.kind(of: message, tools: studio.toolStatus)
        StudioNotice(icon: kind.icon, title: kind.title, text: message, tint: kind.danger ? colors.danger : colors.accentText) {
            if kind.needsTools {
                PillButton(title: "Werkzeuge einrichten …", icon: Icons.wrench, style: .filled) { StudioToolsSheet.present() }
            } else if !studio.urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                PillButton(title: "Erneut versuchen", icon: Icons.refresh) { studio.analyzeInput() }
            }
            PillButton(title: "Schließen", style: .plain) { studio.clearSource() }
        }
        .padding(2)
    }

    struct Kind {
        let icon: String
        let title: String
        var danger: Bool = true
        var needsTools: Bool = false
    }

    static func kind(of message: String, tools: StudioToolStatus) -> Kind {
        if message == StudioError.liveStream.errorDescription { return Kind(icon: Icons.live, title: "Live-Übertragung", danger: false) }
        if message == StudioError.previewOnly.errorDescription { return Kind(icon: Icons.timer, title: "Nur eine Hörprobe verfügbar", danger: false) }
        if message == StudioError.spotifyDRM.errorDescription { return Kind(icon: Icons.lock, title: "Kopiergeschützt", danger: false) }
        if message.contains("Anmeldung") || message == StudioError.privateContent.errorDescription {
            return Kind(icon: Icons.lock, title: "Nicht frei zugänglich", danger: false)
        }
        if message.contains("Werkzeugen installieren") || (!tools.readyForWeb && message.contains("yt-dlp")) {
            return Kind(icon: Icons.wrench, title: "Werkzeuge fehlen", danger: false, needsTools: true)
        }
        return Kind(icon: Icons.error, title: "Die Quelle konnte nicht geöffnet werden")
    }
}

/// Quelle mit Vorschaubild, Titel, Hochlader, Dauer, Herkunft und Format.
private struct StudioSourceInfoCard: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    let source: SourceInfo

    var body: some View {
        let web = source.kind != .localFile && source.libraryUid == nil
        // Querformat nur für Video-Vorschaubilder; quadratische Cover (z. B. Spotify, SoundCloud) bleiben quadratisch
        let thumb = StudioImages.image(source.thumbnail, key: "thumb-" + source.id)
        let landscape = web && (thumb.map { $0.size.width / max($0.size.height, 1) > 1.25 } ?? true)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                StudioArtwork(source: source, key: source.id, cornerRadius: Radius.artwork)
                    .frame(width: landscape ? 176 : 104, height: landscape ? 99 : 104)
                    .shadow(color: Color.black.opacity(colors.dark ? 0.35 : 0.14), radius: 10, y: 4)
                VStack(alignment: .leading, spacing: 5) {
                    StudioFlow(spacing: 6) {
                        StudioBadge(text: StudioText.sourceLabel(source), icon: StudioText.sourceIcon(source), tint: colors.accentText)
                        if let format = StudioText.formatBadge(source) {
                            StudioBadge(text: format)
                        }
                        if source.isLossless == true { StudioBadge(text: "Verlustfrei", tint: colors.accentText) }
                        if source.isLive { StudioBadge(text: "Live", icon: Icons.live, tint: colors.danger) }
                    }
                    Text(source.title)
                        .textStyle(Typo.titleLarge)
                        .foregroundColor(colors.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                        .textSelection(.enabled)
                    if let uploader = source.uploader, !uploader.isEmpty {
                        Text(uploader)
                            .textStyle(Typo.bodyMedium)
                            .foregroundColor(colors.accentText)
                            .lineLimit(1)
                    }
                    Text(meta)
                        .textStyle(Typo.labelMedium)
                        .monospacedDigit()
                        .foregroundColor(colors.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    if web {
                        IconTap(icon: Icons.openInNew, label: "Im Browser öffnen", tint: colors.textSecondary) {
                            NSWorkspace.shared.open(source.url)
                        }
                    } else if let file = source.localFile {
                        IconTap(icon: Icons.folderOpen, label: "Im Finder zeigen", tint: colors.textSecondary) {
                            studio.revealInFinder(file.path)
                        }
                    }
                    IconTap(icon: Icons.close, label: "Andere Quelle wählen", tint: colors.textSecondary) {
                        studio.clearSource()
                    }
                }
            }
            if source.kind == .spotify {
                StudioSpotifyNotice(studio: studio, source: source)
            } else if source.isLive {
                StudioNotice(icon: Icons.live, title: "Live-Übertragungen werden nicht unterstützt",
                             text: "Sobald die Übertragung beendet und als Video verfügbar ist, kannst du die Adresse erneut analysieren.")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.card + 4, style: .continuous))
    }

    private var meta: String {
        var parts: [String] = []
        if let d = StudioText.duration(source.duration) { parts.append(d) }
        if let size = source.fileSize, size > 0 { parts.append(Formatting.fileSize(size)) }
        if source.libraryUid != nil, let album = source.suggested.album.isEmpty ? nil : source.suggested.album { parts.append(album) }
        if source.kind == .localFile || source.libraryUid != nil {
            parts.append((source.localFile ?? source.url).lastPathComponent)
        } else if let host = source.url.host {
            parts.append(host.replacingOccurrences(of: "www.", with: ""))
        }
        return parts.joined(separator: " · ")
    }
}

/// Spotify: Audio ist kopiergeschützt – nur Titel und Cover lassen sich übernehmen.
private struct StudioSpotifyNotice: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    let source: SourceInfo
    @State private var copied = false

    var body: some View {
        StudioNotice(icon: Icons.lock, title: "Spotify-Audio ist kopiergeschützt (DRM)",
                     text: "Musik von Spotify kann nicht geladen oder umgewandelt werden. Titel, Interpret und Cover lassen sich übernehmen – etwa für eine eigene Aufnahme oder eine gekaufte Datei.",
                     tint: colors.accentText) {
            PillButton(title: copied ? "Kopiert" : "Angaben kopieren", icon: copied ? Icons.check : Icons.copy) {
                let meta = source.suggested
                let artist = meta.artist.isEmpty ? (source.uploader ?? "") : meta.artist
                let title = meta.title.isEmpty ? source.title : meta.title
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(artist.isEmpty ? title : "\(artist) – \(title)", forType: .string)
                withAnimation(Motion.easeOut()) { copied = true }
            }
            if let data = source.thumbnail {
                PillButton(title: "Cover sichern …", icon: Icons.image) { Self.saveCover(data, name: source.title) }
            }
        }
    }

    static func saveCover(_ data: Data, name: String) {
        let panel = NSSavePanel()
        let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
        panel.allowedContentTypes = [isPNG ? .png : .jpeg]
        let base = FileNames.sanitize(name)
        panel.nameFieldStringValue = (base.isEmpty ? "Cover" : base) + (isPNG ? ".png" : ".jpg")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            AppModel.shared?.toast("Das Cover konnte nicht gespeichert werden: \(error.localizedDescription)", isError: true)
        }
    }
}

// MARK: - Leerzustand

/// Einladender Beginn: drei Wege (Adresse, Datei, Titel aus der Bibliothek) – jede Kachel führt den Weg aus.
struct StudioEmptyState: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    let columns: Int

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(LinearGradient(colors: [colors.accent.opacity(0.9), colors.accentStrong], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 78, height: 78)
                        .shadow(color: colors.accent.opacity(0.35), radius: 18, y: 8)
                    Icon(Icons.studio, size: 40, color: .white)
                }
                Text("Laden, schneiden, umwandeln")
                    .textStyle(Typo.headlineMedium)
                    .foregroundColor(colors.textPrimary)
                    .padding(.top, 6)
                Text("Hol dir Audio aus dem Netz oder von deinem Mac, wähle den perfekten Ausschnitt und speichere ihn im Format deiner Wahl – direkt in deine Musikbibliothek.")
                    .textStyle(Typo.bodyLarge)
                    .foregroundColor(colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 18)
            let tiles = Group {
                StudioWayTile(number: 1, icon: Icons.link, title: "Adresse einfügen",
                              text: "YouTube- oder SoundCloud-Link kopieren und hier einfügen. Mehrere Zeilen werden zu mehreren Aufträgen.",
                              action: "Aus Zwischenablage einfügen") { studio.pasteFromClipboard() }
                StudioWayTile(number: 2, icon: Icons.audioFile, title: "Datei ziehen oder öffnen",
                              text: "Audio- oder Videodateien (MP3, M4A, WAV, FLAC, AIFF, MP4, MOV …) einfach auf dieses Fenster ziehen.",
                              action: "Datei öffnen …") { studio.chooseFiles() }
                StudioWayTile(number: 3, icon: Icons.cut, title: "Titel aus der Bibliothek",
                              text: "Rechtsklick auf einen Titel → „Im Audio Studio schneiden …“ – als neue Datei oder anstelle des Originals.",
                              action: "Zur Titelliste") { model.select(.tracks) }
            }
            if columns >= 3 {
                HStack(alignment: .top, spacing: 14) { tiles }
            } else {
                VStack(spacing: 12) { tiles }
            }
            HStack(spacing: 8) {
                Icon(Icons.shield, size: 14, color: colors.textTertiary)
                Text(StudioText.rightsNote)
                    .textStyle(Typo.bodySmall)
                    .foregroundColor(colors.textTertiary)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 10)
    }
}

private struct StudioWayTile: View {
    @Environment(\.musicColors) private var colors
    let number: Int
    let icon: String
    let title: String
    let text: String
    let action: String
    let perform: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: perform) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(colors.accentSoft)
                        .frame(width: 40, height: 40)
                        .overlay(Icon(icon, size: 21, color: colors.accentText))
                    Spacer()
                    Text("\(number)")
                        .font(Typo.inter(12, .semibold))
                        .foregroundColor(colors.textTertiary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(colors.textPrimary.opacity(0.06)))
                }
                Text(title)
                    .textStyle(Typo.titleMedium)
                    .foregroundColor(colors.textPrimary)
                Text(text)
                    .textStyle(Typo.bodySmall)
                    .foregroundColor(colors.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text(action)
                        .textStyle(Typo.labelLarge)
                        .foregroundColor(colors.accentText)
                    Icon(Icons.chevronRight, size: 14, color: colors.accentText)
                        .offset(x: hover ? 3 : 0)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 196, alignment: .topLeading)
            .glassSurface(RoundedRectangle(cornerRadius: Radius.card + 4, style: .continuous), interactive: true)
            .overlay(RoundedRectangle(cornerRadius: Radius.card + 4, style: .continuous).strokeBorder(colors.accent.opacity(hover ? 0.35 : 0), lineWidth: 1.2))
            .contentShape(RoundedRectangle(cornerRadius: Radius.card + 4, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .onHover { hover = $0 }
        .animation(Motion.easeOut(Motion.short), value: hover)
        .accessibilityLabel(title)
        .accessibilityHint(text)
    }
}
