import Foundation
import MLStudio

/// Lokale Audio-/Videodatei untersuchen. (Platzhalter – wird vom Engine-Teil ersetzt.)
public struct LocalSourceAnalyzer: LocalSourceAnalyzing {
    public init() {}

    public func analyze(file: URL) async throws -> SourceInfo {
        throw StudioError.other("Analyse ist noch nicht verfügbar.")
    }
}
