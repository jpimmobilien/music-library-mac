import SwiftUI
import AppKit
import MLCore
import MLStudio

/// Zustand und Abläufe des Audio Studios (Version 2.2).
///
/// Vertrag zwischen Oberfläche und Verarbeitung: Die Ansichten lesen nur die veröffentlichten Werte und rufen
/// nur die Methoden unter „Aktionen“ auf. Alles Langsame (Analyse, Laden, Wellenform, Export) läuft in
/// Hintergrund-Tasks; der Hauptthread wird nie blockiert. Die Bibliothek, der Hauptplayer, EQ und Tonhöhe
/// werden nicht verändert – fertige Dateien kommen über das normale Einlesen in die Bibliothek.
@MainActor
final class StudioModel: ObservableObject {
    weak var app: AppModel?
    let services: StudioServiceSet
    let preview: StudioPreviewing?
    /// Demo-Modus (Vorschaubilder): keine Datei- und Netzwerkzugriffe.
    let demo: Bool

    // MARK: Einstellungen (gespeichert unter `StudioSettings.userDefaultsKey`)

    @Published var settings: StudioSettings {
        didSet { if settings != oldValue { saveSettings() } }
    }

    // MARK: Werkzeuge für Internet-Quellen

    enum ToolInstallState: Equatable {
        case idle
        case running(ToolInstallProgress)
        case failed(String)
    }

    @Published var toolStatus = StudioToolStatus()
    @Published var toolInstall: ToolInstallState = .idle

    // MARK: Quelle

    enum SourceState: Equatable {
        /// Noch nichts gewählt.
        case empty
        /// Analyse läuft (Text für die Anzeige, z. B. „YouTube wird abgefragt …“).
        case analyzing(String)
        /// Quelle bekannt (Metadaten). Für Internet-Quellen ist die Audiospur evtl. noch nicht geladen.
        case ready
        case failed(String)
    }

    /// Eingabefeld (eine oder mehrere Adressen, je Zeile eine).
    @Published var urlText = ""
    @Published var sourceState: SourceState = .empty
    @Published var source: SourceInfo?

    /// Laden der Audiospur einer Internet-Quelle zum Bearbeiten (nur auf Knopfdruck).
    enum PrepareState: Equatable {
        case notNeeded
        case needed
        case downloading(DownloadProgress)
        case ready
        case failed(String)
    }

    @Published var prepare: PrepareState = .notNeeded

    // MARK: Editor

    @Published var waveform: WaveformData?
    /// Fortschritt der Wellenform-Berechnung (nil = keine Berechnung).
    @Published var waveformProgress: Double?
    /// Gewählter Ausschnitt in Sekunden (ganze Datei = 0…Dauer).
    @Published var selection: TrimRange = TrimRange(start: 0, end: 0)
    /// true = ganze Datei exportieren (Auswahl wird ignoriert).
    @Published var exportWholeFile = true
    /// Zoom: 1 = ganze Datei sichtbar, 2 = halbe Länge … (max. so, dass ~0,5 s die Breite füllen).
    @Published var zoom: Double = 1
    /// Linker Rand des sichtbaren Bereichs in Sekunden.
    @Published var visibleStart: Double = 0
    @Published var previewPlaying = false
    /// Abspielkopf in Sekunden (während der Vorschau ~30× pro Sekunde aktualisiert).
    @Published var playhead: Double = 0

    // MARK: Export der aktuellen Quelle

    @Published var options: ExportOptions = .defaults(for: .m4a)
    @Published var metadata = StudioMetadata()
    @Published var customFileName = ""

    // MARK: Schneiden vorhandener Songs (Quelle aus der Bibliothek, `source.libraryUid != nil`)

    enum CutSaveMode: String, CaseIterable {
        /// Als neue Datei neben dem Original speichern (Standard, nichts wird überschrieben).
        case newFile
        /// Original ersetzen – nach Sicherung, mit Bestätigung und „Rückgängig“ im Verlauf.
        case replaceOriginal
    }

    @Published var cutSaveMode: CutSaveMode = .newFile
    /// Format und Qualität des Originals behalten; MP3/M4A dann ohne Neukodierung, wenn möglich.
    @Published var keepOriginalFormat = true
    /// Ein-/Ausblenden in Sekunden (0 = aus; erzwingt Neukodierung).
    @Published var fadeIn: Double = 0
    @Published var fadeOut: Double = 0

    var isLibraryTrack: Bool { source?.libraryUid != nil }

    // MARK: Warteschlange und Verlauf

    @Published var jobs: [StudioJob] = []
    @Published var history = StudioHistory()

    init(app: AppModel?, services: StudioServiceSet, preview: StudioPreviewing?, demo: Bool) {
        self.app = app
        self.services = services
        self.preview = preview
        self.demo = demo
        self.settings = demo ? StudioSettings() : StudioSettings.decode(UserDefaults.standard.data(forKey: StudioSettings.userDefaultsKey))
        self.options = settings.options(for: settings.lastFormat)
    }

    private func saveSettings() {
        guard !demo, let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: StudioSettings.userDefaultsKey)
    }

    // MARK: - Abgeleitete Werte (für die Oberfläche)

    var duration: Double { source?.duration ?? waveform?.duration ?? 0 }

    /// Effektiver Ausschnitt für den Export (nil = ganze Datei).
    var effectiveTrim: TrimRange? { exportWholeFile ? nil : selection.clamped(to: duration) }

    /// Dateiname ohne Endung nach aktuellem Schema.
    var fileNameBase: String {
        let scheme: FileNameScheme = isCustomScheme ? .custom(customFileName) : settings.fileNameScheme
        return scheme.render(metadata, fallback: source?.title ?? "Audio")
    }

    var isCustomScheme: Bool {
        if case .custom = settings.fileNameScheme { return true }
        return false
    }

    /// „Interpret – Titel.m4a“
    var fileNamePreview: String { fileNameBase + "." + options.format.fileExtension }

    /// Ehrliche Hinweise zur gewählten Qualität.
    var qualityNotes: [String] {
        QualityAdvice.notes(options: options, sourceLossless: source?.isLossless, sourceBitrate: source?.bitrateKbps,
                            sourceRate: source?.sampleRate, sourceBits: source?.bitDepth)
    }

    /// Ziel nach den Einstellungen (Bibliotheksordner oder freier Ordner).
    var destination: StudioDestination? {
        // TODO(Web/Queue): aus settings + app.folders bestimmen
        nil
    }

    /// Mögliche Dubletten in der Bibliothek für die aktuelle Quelle (leer = keine).
    var duplicateCandidates: [DuplicateCheck.Candidate] {
        // TODO(Web/Queue): DuplicateCheck.matches gegen app.index
        []
    }

    var canExport: Bool {
        guard let source, source.kind.supportsAudio, sourceState == .ready, destination != nil else { return false }
        return !source.isLive
    }

    // MARK: - Aktionen: Quelle

    /// Text aus dem Eingabefeld analysieren (mehrere Zeilen = mehrere Aufträge mit gemeinsamen Einstellungen).
    func analyzeInput() {
        // TODO(Web/Queue)
    }

    /// Zwischenablage einfügen (Adresse oder Dateien) und analysieren.
    func pasteFromClipboard() {
        // TODO(Web/Queue)
    }

    /// Dateien (Drag & Drop oder Öffnen-Dialog). Eine Datei → Editor; mehrere → Warteschlange.
    func importFiles(_ urls: [URL]) {
        // TODO(Web/Queue)
    }

    /// „Öffnen …“-Dialog für lokale Audio- und Videodateien.
    func chooseFiles() {
        // TODO(Web/Queue)
    }

    /// Audiospur einer Internet-Quelle zum Bearbeiten laden (danach Wellenform).
    func prepareForEditing() {
        // TODO(Web/Queue)
    }

    func clearSource() {
        // TODO(Web/Queue)
    }

    /// Titel aus der Bibliothek zum Schneiden öffnen (Kontextmenü „Im Audio Studio schneiden …“).
    func openLibraryTrack(_ uid: Int64) {
        // TODO(Web/Queue): Track → SourceInfo (localFile = Pfad, libraryUid = uid), Metadaten aus den Tags,
        // keepOriginalFormat = true, Wellenform berechnen; app?.studioOpen = true
    }

    // MARK: - Aktionen: Editor

    func setSelection(start: Double? = nil, end: Double? = nil) {
        let d = duration
        var s = start ?? selection.start
        var e = end ?? selection.end
        s = min(max(0, s), d)
        e = min(max(0, e), d)
        if e < s { swap(&s, &e) }
        selection = TrimRange(start: s, end: e)
        exportWholeFile = false
    }

    func selectAll() {
        selection = TrimRange(start: 0, end: duration)
        exportWholeFile = true
    }

    func togglePreview() {
        // TODO(Web/Queue): Auswahl (oder ab Abspielkopf) vorhören
    }

    func previewSelection() {
        // TODO(Web/Queue)
    }

    func seek(to seconds: Double) {
        // TODO(Web/Queue)
    }

    func stopPreview() {
        // TODO(Web/Queue)
    }

    // MARK: - Aktionen: Export

    func setFormat(_ format: StudioFormat) {
        settings.remember(options)
        options = settings.options(for: format)
        settings.lastFormat = format
    }

    /// Optionen ändern und merken.
    func updateOptions(_ change: (inout ExportOptions) -> Void) {
        var o = options
        change(&o)
        options = o.normalized()
        settings.remember(options)
    }

    /// Aktuelle Quelle als Auftrag in die Warteschlange (startet automatisch, wenn nichts anderes läuft).
    @discardableResult
    func addToQueue() -> StudioJob? {
        // TODO(Web/Queue)
        nil
    }

    // MARK: - Aktionen: Warteschlange

    func pause(_ id: UUID) { /* TODO(Web/Queue) */ }
    func resume(_ id: UUID) { /* TODO(Web/Queue) */ }
    func cancel(_ id: UUID) { /* TODO(Web/Queue) */ }
    func retry(_ id: UUID) { /* TODO(Web/Queue) */ }
    func remove(_ id: UUID) { /* TODO(Web/Queue) */ }
    func clearFinished() { /* TODO(Web/Queue) */ }
    /// Format eines wartenden Auftrags ändern (unterschiedliche Formate je Datei).
    func setFormat(_ format: StudioFormat, for id: UUID) { /* TODO(Web/Queue) */ }

    func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Fertige Datei in der Bibliothek zeigen bzw. abspielen (falls importiert).
    func playExported(_ path: String) { /* TODO(Web/Queue) */ }

    func clearHistory() { /* TODO(Web/Queue) */ }

    /// Ersetztes Original aus der Sicherung wiederherstellen.
    func undoReplace(_ historyID: UUID) { /* TODO(Web/Queue) */ }

    // MARK: - Aktionen: Werkzeuge

    func refreshToolStatus() { /* TODO(Web/Queue) */ }
    func installTools() { /* TODO(Web/Queue) */ }
    func removeTools() { /* TODO(Web/Queue) */ }
}
