import Foundation

// Schnittstellen zwischen Oberfläche (App) und Verarbeitung (StudioEngine). Die App kennt nur diese
// Protokolle; für Vorschaubilder und Tests gibt es feste Ersatz-Implementierungen.

/// Auftrag an den Exporter.
public struct ExportRequest: Hashable, Sendable {
    /// Lokale Audio- oder Videodatei.
    public var input: URL
    public var trim: TrimRange?
    public var options: ExportOptions
    public var metadata: StudioMetadata
    /// Zieldatei (wird angelegt; existiert sie, wird sie ersetzt – Eindeutigkeit regelt der Aufrufer).
    public var output: URL
    /// Ein- und Ausblenden in Sekunden (0 = aus). Erzwingt Neukodierung.
    public var fadeIn: Double
    public var fadeOut: Double
    /// Ohne Neukodierung schneiden, wenn Quelle und Ziel dasselbe verlustbehaftete Format haben
    /// (MP3: an Frame-Grenzen ≈ 26 ms; M4A/AAC: über AVFoundation ohne Umwandlung). Sonst normal kodieren.
    public var preferPassthrough: Bool
    /// Alle Tags und Bilder dieser Datei übernehmen (Schneiden vorhandener Songs); `metadata` wird darüber gelegt.
    public var copyTagsFrom: URL?

    public init(input: URL, trim: TrimRange?, options: ExportOptions, metadata: StudioMetadata, output: URL,
                fadeIn: Double = 0, fadeOut: Double = 0, preferPassthrough: Bool = false, copyTagsFrom: URL? = nil) {
        self.input = input
        self.trim = trim
        self.options = options
        self.metadata = metadata
        self.output = output
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.preferPassthrough = preferPassthrough
        self.copyTagsFrom = copyTagsFrom
    }
}

/// Ergebnis eines Exports – aus der fertigen Datei gelesen, nicht aus den Einstellungen übernommen.
public struct ExportResult: Hashable, Sendable {
    public var output: URL
    public var duration: Double
    public var sampleRate: Int
    public var channels: Int
    public var bitDepth: Int?
    /// Durchschnittliche Bitrate in kbit/s.
    public var bitrateKbps: Int
    public var fileSize: Int64
    /// Tags wurden geschrieben (false bei rohem AAC oder wenn es keine Metadaten gab).
    public var tagsWritten: Bool
    /// Ohne Neukodierung geschnitten (verlustfrei gegenüber der Quelle).
    public var passthrough: Bool = false

    public init(output: URL, duration: Double, sampleRate: Int, channels: Int, bitDepth: Int?, bitrateKbps: Int, fileSize: Int64, tagsWritten: Bool, passthrough: Bool = false) {
        self.passthrough = passthrough
        self.output = output
        self.duration = duration
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitDepth = bitDepth
        self.bitrateKbps = bitrateKbps
        self.fileSize = fileSize
        self.tagsWritten = tagsWritten
    }
}

/// Anhalten/Fortsetzen einer laufenden Umwandlung (der Exporter fragt zwischen zwei Blöcken nach).
public final class PauseGate: @unchecked Sendable {
    private let lock = NSLock()
    private var paused = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public var isPaused: Bool { lock.lock(); defer { lock.unlock() }; return paused }

    public func pause() { lock.lock(); paused = true; lock.unlock() }

    public func resume() {
        lock.lock()
        paused = false
        let w = waiters
        waiters.removeAll()
        lock.unlock()
        w.forEach { $0.resume() }
    }

    /// Wartet, solange angehalten ist. Kehrt sofort zurück, wenn nicht angehalten.
    public func waitIfPaused() async {
        lock.lock()
        if !paused { lock.unlock(); return }
        lock.unlock()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.lock()
            if paused { waiters.append(c); lock.unlock() } else { lock.unlock(); c.resume() }
        }
    }
}

public protocol AudioExporting: Sendable {
    /// Wandelt um (abbrechbar über Task-Abbruch → `StudioError.cancelled`). `progress` 0…1.
    func export(_ request: ExportRequest, pause: PauseGate?, progress: @escaping @Sendable (Double) -> Void) async throws -> ExportResult
}

public protocol WaveformProviding: Sendable {
    /// Hüllkurve der Datei. `progress` 0…1; abbrechbar.
    func waveform(for file: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> WaveformData
}

/// Lokale Datei untersuchen (Dauer, Format, Tags, Cover).
public protocol LocalSourceAnalyzing: Sendable {
    func analyze(file: URL) async throws -> SourceInfo
}

/// Fortschritt eines Downloads.
public struct DownloadProgress: Hashable, Sendable {
    public var fraction: Double?
    public var bytesDone: Int64?
    public var bytesTotal: Int64?
    public var bytesPerSecond: Double?
    public var etaSeconds: Double?

    public init(fraction: Double? = nil, bytesDone: Int64? = nil, bytesTotal: Int64? = nil, bytesPerSecond: Double? = nil, etaSeconds: Double? = nil) {
        self.fraction = fraction
        self.bytesDone = bytesDone
        self.bytesTotal = bytesTotal
        self.bytesPerSecond = bytesPerSecond
        self.etaSeconds = etaSeconds
    }
}

/// Internet-Quellen (über yt-dlp; Spotify nur Metadaten).
public protocol RemoteSourceProviding: Sendable {
    func analyze(url: URL, kind: SourceKind) async throws -> SourceInfo
    /// Lädt die Audiospur in `directory` (Fortsetzen möglich: angefangene Dateien bleiben liegen).
    /// Abbrechbar über Task-Abbruch.
    func download(_ source: SourceInfo, into directory: URL, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL
    /// Vorschaubild laden (JPEG/PNG), falls vorhanden.
    func thumbnail(for source: SourceInfo) async -> Data?
    /// Adresse abfragen: einzelner Titel oder Playlist/Set (additiv; Standard: `analyze`, siehe StudioRemoteLookup.swift).
    func lookup(url: URL, kind: SourceKind) async throws -> RemoteLookup
    /// Adressen der einzelnen Titel einer Playlist/eines Sets (höchstens 200); bei einem einzelnen Titel `[url]`.
    func expandPlaylist(url: URL) async throws -> [URL]
}

/// Zustand der Hilfswerkzeuge für Internet-Quellen.
public struct StudioToolStatus: Hashable, Sendable {
    public enum Origin: String, Hashable, Sendable {
        case missing
        /// Von der App in „Application Support“ installiert.
        case managed
        /// Vom System (z. B. Homebrew) gefunden.
        case system
    }

    public var ytDlpPath: String?
    public var ytDlpVersion: String?
    public var ytDlpOrigin: Origin
    public var denoPath: String?
    public var denoVersion: String?
    public var denoOrigin: Origin
    /// Optional, nur für exotische lokale Formate (z. B. WebM, MKV).
    public var ffmpegPath: String?

    public init(ytDlpPath: String? = nil, ytDlpVersion: String? = nil, ytDlpOrigin: Origin = .missing, denoPath: String? = nil,
                denoVersion: String? = nil, denoOrigin: Origin = .missing, ffmpegPath: String? = nil) {
        self.ytDlpPath = ytDlpPath
        self.ytDlpVersion = ytDlpVersion
        self.ytDlpOrigin = ytDlpOrigin
        self.denoPath = denoPath
        self.denoVersion = denoVersion
        self.denoOrigin = denoOrigin
        self.ffmpegPath = ffmpegPath
    }

    public var readyForWeb: Bool { ytDlpPath != nil }
    /// YouTube braucht zusätzlich eine JavaScript-Laufzeit (Deno).
    public var readyForYouTube: Bool { ytDlpPath != nil && denoPath != nil }
}

/// Fortschritt beim Installieren der Werkzeuge.
public struct ToolInstallProgress: Hashable, Sendable {
    public var step: String
    public var fraction: Double?

    public init(step: String, fraction: Double? = nil) {
        self.step = step
        self.fraction = fraction
    }
}

public protocol StudioToolManaging: Sendable {
    func status() async -> StudioToolStatus
    /// Lädt yt-dlp und Deno von den offiziellen GitHub-Veröffentlichungen, prüft die SHA-256-Prüfsummen und
    /// legt sie in „Application Support“ ab. Nur auf ausdrücklichen Wunsch des Nutzers.
    func installOrUpdate(progress: @escaping @Sendable (ToolInstallProgress) -> Void) async throws -> StudioToolStatus
    /// Von der App installierte Werkzeuge entfernen.
    func removeManaged() async throws -> StudioToolStatus
}

/// Gespeicherte Einstellungen des Audio Studios (eigener UserDefaults-Schlüssel, getrennt von AppSettings).
public struct StudioSettings: Codable, Hashable, Sendable {
    public var lastFormat: StudioFormat
    /// Zuletzt verwendete Einstellungen je Format.
    public var optionsByFormat: [String: ExportOptions]
    public var fileNameScheme: FileNameScheme
    /// true = in einen Musikordner der Bibliothek, false = nur speichern.
    public var importToLibrary: Bool
    /// Musikordner (ID) für den Import; nil = erster Ordner.
    public var libraryFolderID: Int64?
    public var librarySubfolder: String
    /// Ordner für „nur speichern“; nil = ~/Music/Audio Studio.
    public var saveFolderPath: String?
    /// Nach dem Export im Finder zeigen.
    public var revealAfterExport: Bool

    public init(lastFormat: StudioFormat = .m4a, optionsByFormat: [String: ExportOptions] = [:], fileNameScheme: FileNameScheme = .artistTitle,
                importToLibrary: Bool = true, libraryFolderID: Int64? = nil, librarySubfolder: String = "Audio Studio",
                saveFolderPath: String? = nil, revealAfterExport: Bool = false) {
        self.lastFormat = lastFormat
        self.optionsByFormat = optionsByFormat
        self.fileNameScheme = fileNameScheme
        self.importToLibrary = importToLibrary
        self.libraryFolderID = libraryFolderID
        self.librarySubfolder = librarySubfolder
        self.saveFolderPath = saveFolderPath
        self.revealAfterExport = revealAfterExport
    }

    public func options(for format: StudioFormat) -> ExportOptions {
        (optionsByFormat[format.rawValue] ?? ExportOptions.defaults(for: format)).normalized()
    }

    public mutating func remember(_ options: ExportOptions) {
        lastFormat = options.format
        optionsByFormat[options.format.rawValue] = options.normalized()
    }

    public static let userDefaultsKey = "audioStudioSettings"

    /// Robust laden: unbekannte oder beschädigte Daten → Standardwerte.
    public static func decode(_ data: Data?) -> StudioSettings {
        guard let data, let s = try? JSONDecoder().decode(StudioSettings.self, from: data) else { return StudioSettings() }
        return s
    }
}
