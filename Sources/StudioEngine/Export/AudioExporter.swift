import Foundation
import MLStudio

/// Export: Lesen → Schneiden → Blenden → Umrechnen → Kodieren → Tags → Ergebnis aus der fertigen Datei.
///
/// Läuft vollständig außerhalb des Hauptthreads, blockweise (nie die ganze Datei im Speicher), abbrechbar
/// (Task-Abbruch → `StudioError.cancelled`, keine Restdatei) und anhaltbar (`PauseGate`).
public struct AudioExporter: AudioExporting {
    public init() {}

    public func export(_ request: ExportRequest, pause: PauseGate?, progress: @escaping @Sendable (Double) -> Void) async throws -> ExportResult {
        let job = ExportJob(request: request, control: JobControl(pause: pause), reporter: ProgressReporter(progress))
        do {
            return try await job.run()
        } catch let error as StudioError {
            throw error
        } catch is CancellationError {
            throw StudioError.cancelled
        } catch let error as MP3StreamError {
            throw StudioError.decodeFailed("MP3-Datenstrom: \(error)")
        } catch {
            throw StudioError.encodeFailed(error.localizedDescription)
        }
    }
}
