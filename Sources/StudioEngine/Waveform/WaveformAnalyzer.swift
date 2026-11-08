import Foundation
import MLStudio

/// Hüllkurve einer Datei für die Wellenform. (Platzhalter – wird vom Engine-Teil ersetzt.)
public struct WaveformAnalyzer: WaveformProviding {
    public init() {}

    public func waveform(for file: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> WaveformData {
        throw StudioError.other("Wellenform ist noch nicht verfügbar.")
    }
}
