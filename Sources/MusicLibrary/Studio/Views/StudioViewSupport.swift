import SwiftUI
import AppKit
import ImageIO
import MLCore
import MLStore
import MLStudio

// Audio Studio (2.2) – reine Ansichts-Hilfen: abgeleitete Anzeigewerte, Zoom/Verschieben der Wellenform und
// kleine Bausteine im Stil des Designsystems (Glaskarten, Abzeichen, Fortschritt, Hinweise).
// `StudioModel` selbst gehört dem Ablauf-Teil; hier stehen nur Erweiterungen ohne eigene Logik der Abläufe.

// MARK: - Anzeigewerte

extension StudioModel {
    /// Ausschnitt, wie ihn die Wellenform zeigt (ganze Datei = 0…Dauer).
    var shownSelection: TrimRange {
        let d = duration
        if exportWholeFile || selection.length < 0.005 { return TrimRange(start: 0, end: d) }
        return TrimRange(start: min(selection.start, d), end: min(selection.end, d))
    }

    /// Sichtbare Länge der Wellenform in Sekunden.
    var visibleSpan: Double { duration > 0 ? duration / max(zoom, 1) : 0 }

    /// Größter Zoom: etwa eine halbe Sekunde füllt die Breite.
    var maxZoom: Double { max(1, duration / 0.5) }

    /// Sichtbarer Bereich (Sekunden), auf die Dauer begrenzt.
    var visibleRange: ClosedRange<Double> {
        let span = visibleSpan
        let start = clampedStart(visibleStart, span: span)
        return start...(start + max(span, 0.001))
    }

    /// Quelle bereit zum Bearbeiten und Exportieren (Audio vorhanden, keine Live-Übertragung).
    var showsEditor: Bool {
        guard let source, sourceState == .ready else { return false }
        return source.kind.supportsAudio && !source.isLive
    }

    /// Internet-Quelle, deren Audiospur noch geladen werden muss, bevor geschnitten werden kann.
    var needsPreparation: Bool {
        switch prepare {
        case .needed, .downloading, .failed: return true
        case .notNeeded, .ready: return false
        }
    }

    var isEmptyStudio: Bool { source == nil && sourceState == .empty }

    /// Ersetzt das Original (Schneiden vorhandener Songs).
    var replacesOriginal: Bool { isLibraryTrack && cutSaveMode == .replaceOriginal }

    /// Format, das beim Schneiden mit „Format wie Original“ entsteht.
    var originalFormat: StudioFormat? { source?.sameFormat }

    /// „ohne Neukodierung“ bzw. „verlustfrei“ – nur als Hinweis; die tatsächliche Art steht nach dem Export im Ergebnis.
    var passthroughBadge: String? {
        guard isLibraryTrack, keepOriginalFormat, let f = originalFormat else { return nil }
        if activeTrackEdit != nil { return f.isLossless ? "verlustfrei" : nil }   // Klang verändert: neu kodiert
        if f.isLossless { return "verlustfrei" }
        if (f == .mp3 || f == .m4a), fadeIn == 0, fadeOut == 0 { return "ohne Neukodierung" }
        return nil
    }

    /// Zielordner zur Anzeige: aus dem Ablauf (`destination`), sonst aus den Einstellungen abgeleitet.
    var shownDestination: (title: String, path: String?) {
        if isLibraryTrack, let src = source {
            let original = (src.localFile ?? src.url).path
            if cutSaveMode == .replaceOriginal { return ("Ersetzt das Original", original) }
            let dir = (original as NSString).deletingLastPathComponent
            return ("Neben dem Original", dir)
        }
        if let d = destination {
            switch d {
            case .library(let id, let folderPath, _):
                let name = app?.folders.first(where: { $0.id == id })?.name ?? (folderPath as NSString).lastPathComponent
                return ("Musikbibliothek · \(name)", d.directoryPath)
            case .folder(let path): return ("Ordner", path)
            case .replaceOriginal(_, let path): return ("Ersetzt das Original", path)
            }
        }
        if settings.importToLibrary {
            guard let folder = libraryFolder else { return ("Kein Musikordner", nil) }
            let path = StudioDestination.library(folderID: folder.id, folderPath: folder.path, subfolder: settings.librarySubfolder).directoryPath
            return ("Musikbibliothek · \(folder.name)", path)
        }
        return ("Ordner", settings.saveFolderPath ?? StudioModel.defaultSaveFolder)
    }

    /// Musikordner für den Import (gewählter, sonst der erste).
    var libraryFolder: LibraryFolderInfo? {
        guard let folders = app?.folders, !folders.isEmpty else { return nil }
        let f = folders.first(where: { $0.id == settings.libraryFolderID }) ?? folders[0]
        return LibraryFolderInfo(id: f.id, name: f.name, path: f.path)
    }

    static var defaultSaveFolder: String {
        (NSHomeDirectory() as NSString).appendingPathComponent("Music/Audio Studio")
    }

    /// Mögliche Dubletten zur Anzeige (Vorschaubilder können feste Werte setzen).
    var shownDuplicates: [DuplicateCheck.Candidate] {
        if demo, let fixed = StudioDemo.duplicates { return fixed }
        return duplicateCandidates
    }

    /// Diese Quelle wurde schon einmal erfolgreich exportiert (Verlauf).
    var previousExport: StudioHistoryEntry? {
        guard let src = source else { return nil }
        return history.previousExport(of: src.url.absoluteString) ?? src.localFile.flatMap { history.previousExport(of: $0.path) }
    }

    var activeJob: StudioJob? { jobs.first { $0.phase.isActive } }
    var unfinishedJobCount: Int { jobs.filter { !$0.phase.isFinished }.count }

    // MARK: Zoom und Verschieben (nur Ansichtszustand)

    func clampedStart(_ start: Double, span: Double) -> Double {
        min(max(0, start), max(0, duration - span))
    }

    /// Zoomt um `factor`; die Zeit an `anchor` (0…1 der Breite) bleibt an ihrer Stelle.
    func zoomBy(_ factor: Double, anchor: Double = 0.5) {
        guard duration > 0, factor.isFinite, factor > 0 else { return }
        let a = min(max(anchor, 0), 1)
        let anchorTime = visibleRange.lowerBound + a * visibleSpan
        let z = min(max(zoom * factor, 1), maxZoom)
        guard abs(z - zoom) > 1e-6 else { return }
        zoom = z
        let span = duration / z
        visibleStart = clampedStart(anchorTime - a * span, span: span)
    }

    func setZoomLevel(_ z: Double) {
        guard zoom > 0 else { return }
        zoomBy(z / zoom, anchor: 0.5)
    }

    func pan(by seconds: Double) {
        guard duration > 0, zoom > 1 else { return }
        let s = clampedStart(visibleStart + seconds, span: visibleSpan)
        if abs(s - visibleStart) > 1e-6 { visibleStart = s }
    }

    /// Ausschnitt mit etwas Rand füllt die Breite.
    func zoomToSelection() {
        let sel = shownSelection
        guard duration > 0, sel.length > 0.01 else { return }
        let margin = sel.length * 0.08
        let z = min(max(duration / (sel.length + 2 * margin), 1), maxZoom)
        zoom = z
        visibleStart = clampedStart(sel.start - margin, span: duration / z)
    }

    func showWholeWaveform() {
        zoom = 1
        visibleStart = 0
    }
}

/// Musikordner zur Anzeige (ohne Abhängigkeit vom Speichermodul in den Ansichten).
struct LibraryFolderInfo: Hashable {
    let id: Int64
    let name: String
    let path: String
}

// MARK: - Texte

enum StudioText {
    /// Kurzname eines Codecs („mp4a.40.2“ → „AAC“, „opus“ → „Opus“).
    static func codecName(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, raw != "none" else { return nil }
        let c = raw.lowercased()
        if c.hasPrefix("mp4a") || c.contains("aac") { return "AAC" }
        if c.contains("opus") { return "Opus" }
        if c.contains("vorbis") { return "Vorbis" }
        if c.contains("mp3") || c == "mpga" || c.contains("mpeg") { return "MP3" }
        if c.contains("flac") { return "FLAC" }
        if c.contains("alac") { return "ALAC" }
        if c.contains("pcm") || c.contains("lpcm") || c == "wav" { return "PCM" }
        if c.contains("aiff") { return "AIFF" }
        return raw.uppercased()
    }

    /// „AAC · 129 kbit/s · 44,1 kHz“ (Angaben, soweit bekannt).
    static func formatBadge(_ s: SourceInfo) -> String? {
        var parts: [String] = []
        if let c = codecName(s.codec) {
            parts.append(c)
        } else if s.kind == .localFile || s.libraryUid != nil {
            let ext = (s.localFile ?? s.url).pathExtension.uppercased()
            if !ext.isEmpty { parts.append(ext) }
        }
        if let kbps = s.bitrateKbps, kbps > 0, s.isLossless != true { parts.append(Formatting.bitrate(kbps: kbps)) }
        if let bits = s.bitDepth, bits > 0, s.isLossless == true { parts.append("\(bits) Bit") }
        if let sr = s.sampleRate, sr > 0 { parts.append(Formatting.sampleRate(sr)) }
        if let ch = s.channels, ch == 1 { parts.append("Mono") } else if let ch = s.channels, ch > 2 { parts.append("\(ch) Kanäle") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Dauer kurz, z. B. „3:32“ bzw. „1:02:03“.
    static func duration(_ seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
        return StudioTime.format(seconds, millis: false)
    }

    /// Pfad mit „~“ statt des Benutzerordners.
    static func abbreviated(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    static func sourceIcon(_ s: SourceInfo) -> String {
        if s.libraryUid != nil { return Icons.libraryMusic }
        switch s.kind {
        case .localFile: return Icons.audioFile
        case .youtube: return Icons.play
        case .soundcloud: return Icons.waves
        case .spotify: return Icons.lock
        case .web: return SourceURL.isInstagram(s.url) ? Icons.photoLibrary : Icons.globe
        }
    }

    static func sourceLabel(_ s: SourceInfo) -> String {
        s.libraryUid != nil ? "Bibliothek" : SourceURL.label(kind: s.kind, url: s.url)
    }

    static func megabytes(_ bytes: Int64) -> String { Formatting.fileSize(bytes) }

    /// „3,2 MB von 8,1 MB · 1,4 MB/s · noch 0:12“
    static func download(_ p: DownloadProgress) -> String {
        var parts: [String] = []
        if let done = p.bytesDone {
            if let total = p.bytesTotal, total > 0 { parts.append("\(megabytes(done)) von \(megabytes(total))") } else { parts.append(megabytes(done)) }
        }
        if let bps = p.bytesPerSecond, bps > 0 { parts.append("\(megabytes(Int64(bps)))/s") }
        if let eta = p.etaSeconds, eta.isFinite, eta > 0 { parts.append("noch \(StudioTime.format(eta, millis: false))") }
        return parts.joined(separator: " · ")
    }

    static let rightsNote = "Lade nur Inhalte, für die du die Rechte hast. Spotify-Audio ist kopiergeschützt."

    static func relativeDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.doesRelativeDateFormatting = true
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Bilder (Vorschaubilder, Cover)

/// Zwischenspeicher für dekodierte Vorschaubilder (Daten werden nicht bei jedem Zeichnen neu dekodiert).
@MainActor
enum StudioImages {
    private static var cache: [String: NSImage] = [:]

    static func image(_ data: Data?, key: String) -> NSImage? {
        guard let data, !data.isEmpty else { return nil }
        let k = "\(key)#\(data.count)"
        if let img = cache[k] { return img }
        guard let img = NSImage(data: data) else { return nil }
        if cache.count > 80 { cache.removeAll() }
        cache[k] = img
        return img
    }

    /// Quadratischer Ausschnitt aus der Mitte (z. B. 16:9-Vorschaubild → Cover) als JPEG.
    static func squareCover(from data: Data) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let side = min(cg.width, cg.height)
        let rect = CGRect(x: (cg.width - side) / 2, y: (cg.height - side) / 2, width: side, height: side)
        guard let cropped = cg.cropping(to: rect) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cropped)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }
}

// MARK: - Bausteine

/// Glaskarte des Studios mit Kopfzeile (Symbol, Titel, Untertitel, Zusatz rechts).
struct StudioCard<Accessory: View, Content: View>: View {
    @Environment(\.musicColors) private var colors
    let icon: String
    let title: String
    var subtitle: String? = nil
    var padding: CGFloat = 16
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colors.accentSoft)
                    .frame(width: 28, height: 28)
                    .overlay(Icon(icon, size: 16, color: colors.accentText))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .textStyle(Typo.titleMedium)
                        .foregroundColor(colors.textPrimary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .textStyle(Typo.labelMedium)
                            .foregroundColor(colors.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                accessory()
            }
            .accessibilityElement(children: .combine)
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.card + 4, style: .continuous))
    }
}

extension StudioCard where Accessory == EmptyView {
    init(icon: String, title: String, subtitle: String? = nil, padding: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.init(icon: icon, title: title, subtitle: subtitle, padding: padding, accessory: { EmptyView() }, content: content)
    }
}

/// Kleines Abzeichen (Kapsel) mit optionalem Symbol.
struct StudioBadge: View {
    @Environment(\.musicColors) private var colors
    let text: String
    var icon: String? = nil
    var tint: Color? = nil
    var filled: Bool = false

    var body: some View {
        let c = tint ?? colors.textSecondary
        HStack(spacing: 4) {
            if let icon { Icon(icon, size: 12, color: filled ? colors.onAccent : c) }
            Text(text)
                .font(Typo.inter(11, .semibold))
                .foregroundColor(filled ? colors.onAccent : c)
                .lineLimit(1)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Capsule().fill(filled ? (tint ?? colors.accent) : c.opacity(colors.dark ? 0.16 : 0.10)))
        .fixedSize()
    }
}

/// Schlanker Fortschrittsbalken; `value == nil` = unbestimmt (sanft wandernder Glanz).
struct StudioProgressBar: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.continuousMotion) private var motion
    let value: Double?
    var tint: Color? = nil
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(colors.textPrimary.opacity(colors.dark ? 0.14 : 0.09))
                if let value {
                    Capsule()
                        .fill(tint ?? colors.accent)
                        .frame(width: max(height, w * CGFloat(min(max(value, 0), 1))))
                        .animation(Motion.easeOut(Motion.medium), value: value)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !motion)) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        let phase = motion ? CGFloat((t / 1.4).truncatingRemainder(dividingBy: 1)) : 0.35
                        Capsule()
                            .fill(tint ?? colors.accent)
                            .frame(width: w * 0.32)
                            .offset(x: -w * 0.32 + (w * 1.32) * phase)
                    }
                    .clipShape(Capsule())
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Fortschritt")
        .accessibilityValue(value.map { "\(Int(($0 * 100).rounded())) %" } ?? "läuft")
    }
}

/// Dezente Hinweiszeile (Symbol + Text).
struct StudioInfoLine: View {
    @Environment(\.musicColors) private var colors
    let text: String
    var icon: String = Icons.info
    var tint: Color? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Icon(icon, size: 14, color: tint ?? colors.textTertiary)
                .padding(.top, 1)
            Text(text)
                .textStyle(Typo.bodySmall)
                .foregroundColor(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Hervorgehobener Hinweis in einer zarten Fläche (Warnung, DRM, Fehler).
struct StudioNotice<Actions: View>: View {
    @Environment(\.musicColors) private var colors
    let icon: String
    let title: String
    var text: String? = nil
    var tint: Color? = nil
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        let c = tint ?? colors.accentText
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(c.opacity(0.14))
                    .frame(width: 34, height: 34)
                    .overlay(Icon(icon, size: 18, color: c))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Typo.inter(14, .semibold))
                        .foregroundColor(colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let text {
                        Text(text)
                            .textStyle(Typo.bodySmall)
                            .foregroundColor(colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) { actions() }
                .padding(.leading, 46)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(c.opacity(colors.dark ? 0.10 : 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(c.opacity(0.28), lineWidth: 1))
    }
}

extension StudioNotice where Actions == EmptyView {
    init(icon: String, title: String, text: String? = nil, tint: Color? = nil) {
        self.init(icon: icon, title: title, text: text, tint: tint) { EmptyView() }
    }
}

/// Eingabefeld im App-Stil (zarte Fläche, Rosé-Ring bei Fokus).
struct StudioTextField: View {
    @Environment(\.musicColors) private var colors
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var width: CGFloat? = nil
    var monospaced: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(colors.textTertiary))
            .textFieldStyle(.plain)
            .font(Typo.inter(13, .regular))
            .monospacedDigit()
            .foregroundColor(colors.textPrimary)
            .focused($focused)
            .padding(.horizontal, 10)
            .frame(width: width, height: 30)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(colors.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(focused ? colors.accent.opacity(0.7) : .clear, lineWidth: 1.5))
            .accessibilityLabel(label)
    }
}

/// Feld mit Beschriftung darüber (Metadaten, Zeitangaben).
struct StudioLabeledField<Field: View>: View {
    @Environment(\.musicColors) private var colors
    let label: String
    @ViewBuilder var field: () -> Field

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .textStyle(Typo.labelMedium)
                .foregroundColor(colors.textSecondary)
                .lineLimit(1)
            field()
        }
    }
}

/// Große Wahlfläche (Symbol, Titel, Erklärung) – z. B. „Als neue Datei“ / „Original ersetzen“.
struct StudioOptionTile: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.isEnabled) private var enabled
    let icon: String
    let title: String
    let text: String
    let selected: Bool
    var destructive: Bool = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let tint = destructive ? colors.danger : colors.accentText
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(selected ? 0.18 : 0.10))
                    .frame(width: 34, height: 34)
                    .overlay(Icon(icon, size: 18, color: tint))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Typo.inter(14, .semibold))
                        .foregroundColor(colors.textPrimary)
                    Text(text)
                        .textStyle(Typo.bodySmall)
                        .foregroundColor(colors.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle().strokeBorder(selected ? tint : colors.textTertiary.opacity(0.6), lineWidth: 1.5)
                    if selected { Circle().fill(tint).padding(4) }
                }
                .frame(width: 18, height: 18)
                .padding(.top, 8)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(selected ? tint.opacity(colors.dark ? 0.12 : 0.07) : colors.textPrimary.opacity(hover && enabled ? 0.05 : 0.02)))
            .overlay(shape.strokeBorder(selected ? tint.opacity(0.55) : colors.hairline, lineWidth: selected ? 1.5 : 1))
            .contentShape(shape)
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .onHover { hover = $0 }
        .opacity(enabled ? 1 : 0.5)
        .animation(Motion.easeOut(Motion.short), value: selected)
        .accessibilityLabel(title)
        .accessibilityHint(text)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Reihe kleiner Auswahl-Kapseln (Bitrate, Abtastrate, Bittiefe …).
struct StudioChoiceRow<T: Hashable>: View {
    @Environment(\.musicColors) private var colors
    let label: String
    let options: [T]
    let selected: T
    let title: (T) -> String
    let choose: (T) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .textStyle(Typo.labelMedium)
                .foregroundColor(colors.textSecondary)
            StudioFlow(spacing: 6) {
                ForEach(options, id: \.self) { o in
                    ChoiceChip(title: title(o), selected: o == selected) { choose(o) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// Fließende Anordnung (bricht in die nächste Zeile um, wenn der Platz nicht reicht).
struct StudioFlow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat? = nil

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += lineHeight + (lineSpacing ?? spacing)
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += lineHeight + (lineSpacing ?? spacing)
                x = bounds.minX
                lineHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// Rote Kapsel für eine endgültige Aktion („Original ersetzen“, „Verlauf löschen“).
struct StudioDangerButton: View {
    @Environment(\.musicColors) private var colors
    let title: String
    var icon: String? = nil
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Icon(icon, size: 16, color: .white) }
                Text(title)
                    .textStyle(Typo.labelLarge)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: Metrics.pillHeight)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(colors.danger))
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Color.white.opacity(hover ? 0.1 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.96))
        .onHover { hover = $0 }
    }
}

/// Unsichtbare Schaltfläche für Esc in Blättern.
struct StudioEscapeButton: View {
    let action: () -> Void

    var body: some View {
        Button("Abbrechen", action: action)
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}

/// Schimmer über Platzhaltern (Analyse läuft). Ruht bei „Bewegung reduzieren“.
struct StudioShimmer: ViewModifier {
    @Environment(\.musicColors) private var colors
    @Environment(\.continuousMotion) private var motion

    func body(content: Content) -> some View {
        content.overlay(
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !motion)) { context in
                GeometryReader { geo in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let phase = motion ? CGFloat((t / 1.6).truncatingRemainder(dividingBy: 1)) : 0.5
                    let w = geo.size.width
                    LinearGradient(colors: [.clear, Color.white.opacity(colors.dark ? 0.10 : 0.45), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: w * 0.45)
                        .offset(x: -w * 0.45 + (w * 1.45) * phase)
                }
            }
            .mask(content)
            .allowsHitTesting(false)
        )
    }
}

extension View {
    func studioShimmer() -> some View { modifier(StudioShimmer()) }
}

/// Platzhalter-Fläche (Skelett) für ladende Inhalte.
struct StudioSkeleton: View {
    @Environment(\.musicColors) private var colors
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var radius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(colors.textPrimary.opacity(colors.dark ? 0.10 : 0.07))
            .frame(width: width, height: height)
    }
}

/// Vorschaubild bzw. Cover einer Quelle oder eines Auftrags.
struct StudioArtwork: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    let source: SourceInfo?
    var cover: Data? = nil
    var key: String = ""
    var cornerRadius: CGFloat = Radius.artwork
    /// Bild füllt die Fläche (sonst eingepasst).
    var fill: Bool = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if let image = StudioImages.image(cover, key: "cover-" + key) ?? StudioImages.image(source?.thumbnail, key: "thumb-" + (source?.id ?? key)) {
                GeometryReader { geo in
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: fill ? .fill : .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            } else if let uid = source?.libraryUid, let track = model.track(uid) {
                TrackArtwork(track: track, size: .medium, cornerRadius: cornerRadius)
            } else {
                GeometryReader { geo in
                    ZStack {
                        LinearGradient(colors: [colors.accent.opacity(0.85), colors.accentStrong.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Icon(source.map(StudioText.sourceIcon) ?? Icons.waveform, size: min(geo.size.width, geo.size.height) * 0.42, color: .white.opacity(0.92))
                    }
                }
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(colors.artworkStroke, lineWidth: 0.6))
    }
}
