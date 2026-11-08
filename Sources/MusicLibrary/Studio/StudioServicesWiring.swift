import Foundation
import MLStudio

// Zusammenstellung der Audio-Studio-Dienste. `live` verwendet die echten Dienste aus StudioEngine,
// `demo` feste Ersatzdienste für Vorschaubilder.
// TODO(Engine, Web/Queue): Platzhalter durch die echten Implementierungen ersetzen.

extension StudioServiceSet {
    static var live: StudioServiceSet {
        StudioServiceSet(exporter: UnavailableStudioService(), waveforms: UnavailableStudioService(), local: UnavailableStudioService(),
                         remote: UnavailableStudioService(), tools: UnavailableStudioService())
    }
}

/// Platzhalter, solange ein Dienst fehlt: meldet einen verständlichen Fehler.
struct UnavailableStudioService: AudioExporting, WaveformProviding, LocalSourceAnalyzing, RemoteSourceProviding, StudioToolManaging {
    func export(_ request: ExportRequest, pause: PauseGate?, progress: @escaping @Sendable (Double) -> Void) async throws -> ExportResult {
        throw StudioError.other("Export ist noch nicht verfügbar.")
    }
    func waveform(for file: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> WaveformData {
        throw StudioError.other("Wellenform ist noch nicht verfügbar.")
    }
    func analyze(file: URL) async throws -> SourceInfo { throw StudioError.other("Analyse ist noch nicht verfügbar.") }
    func analyze(url: URL, kind: SourceKind) async throws -> SourceInfo { throw StudioError.other("Analyse ist noch nicht verfügbar.") }
    func download(_ source: SourceInfo, into directory: URL, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL {
        throw StudioError.other("Laden ist noch nicht verfügbar.")
    }
    func thumbnail(for source: SourceInfo) async -> Data? { nil }
    func status() async -> StudioToolStatus { StudioToolStatus() }
    func installOrUpdate(progress: @escaping @Sendable (ToolInstallProgress) -> Void) async throws -> StudioToolStatus {
        throw StudioError.other("Installation ist noch nicht verfügbar.")
    }
    func removeManaged() async throws -> StudioToolStatus { StudioToolStatus() }
}

extension StudioServiceSet {
    /// Feste Ersatzdienste für Vorschaubilder (keine Datei- und Netzwerkzugriffe).
    /// TODO(UI): durch Demo-Dienste mit festen Werten ersetzen.
    static var demo: StudioServiceSet { live }
}

/// Erzeugt den Vorhör-Player (TODO(Engine): `StudioPreviewPlayer` aus StudioEngine).
@MainActor
enum StudioPreviewFactory {
    static func make() -> StudioPreviewing? { nil }
}
