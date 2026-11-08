import Foundation
import MLStudio

/// Export: Lesen → Schneiden → Umrechnen → Kodieren → Tags. (Platzhalter – wird vom Engine-Teil ersetzt.)
public struct AudioExporter: AudioExporting {
    public init() {}

    public func export(_ request: ExportRequest, pause: PauseGate?, progress: @escaping @Sendable (Double) -> Void) async throws -> ExportResult {
        throw StudioError.other("Export ist noch nicht verfügbar.")
    }
}
