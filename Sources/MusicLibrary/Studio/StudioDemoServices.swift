import Foundation
import MLStudio

// Feste Ersatzdienste für Vorschaubilder (Demo-Modus): keine Datei- und Netzwerkzugriffe.
// TODO(UI): Demo-Werte (Wellenform, Quelle, Warteschlange) für die Vorschaubilder.

extension StudioServiceSet {
    static var demo: StudioServiceSet {
        let s = DemoStudioService()
        return StudioServiceSet(exporter: s, waveforms: s, local: s, remote: s, tools: s)
    }
}

struct DemoStudioService: AudioExporting, WaveformProviding, LocalSourceAnalyzing, RemoteSourceProviding, StudioToolManaging {
    func export(_ request: ExportRequest, pause: PauseGate?, progress: @escaping @Sendable (Double) -> Void) async throws -> ExportResult {
        throw StudioError.other("Im Vorschaumodus nicht verfügbar.")
    }
    func waveform(for file: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> WaveformData {
        throw StudioError.other("Im Vorschaumodus nicht verfügbar.")
    }
    func analyze(file: URL) async throws -> SourceInfo { throw StudioError.other("Im Vorschaumodus nicht verfügbar.") }
    func analyze(url: URL, kind: SourceKind) async throws -> SourceInfo { throw StudioError.other("Im Vorschaumodus nicht verfügbar.") }
    func download(_ source: SourceInfo, into directory: URL, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL {
        throw StudioError.other("Im Vorschaumodus nicht verfügbar.")
    }
    func thumbnail(for source: SourceInfo) async -> Data? { nil }
    func status() async -> StudioToolStatus { StudioToolStatus() }
    func installOrUpdate(progress: @escaping @Sendable (ToolInstallProgress) -> Void) async throws -> StudioToolStatus {
        throw StudioError.other("Im Vorschaumodus nicht verfügbar.")
    }
    func removeManaged() async throws -> StudioToolStatus { StudioToolStatus() }
}
