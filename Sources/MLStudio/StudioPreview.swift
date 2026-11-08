import Foundation

/// Vorhören im Editor – eigener, vom Hauptplayer getrennter Wiedergabeweg (Hauptplayer, EQ und Tonhöhe
/// bleiben unberührt).
@MainActor
public protocol StudioPreviewing: AnyObject {
    /// Datei laden (beendet eine laufende Vorschau).
    func load(_ file: URL) throws
    /// Von `start` bis `end` (Sekunden; nil = Dateiende) abspielen.
    func play(from start: Double, to end: Double?)
    func pause()
    func stop()
    /// Aktuelle Position in Sekunden (für den Abspielkopf; die Oberfläche fragt sie ~30× pro Sekunde ab).
    var position: Double { get }
    var isPlaying: Bool { get }
    /// Wird aufgerufen, wenn die Wiedergabe das Ende des Bereichs erreicht.
    var onFinish: (() -> Void)? { get set }
}

/// Alle Dienste des Audio Studios (echte unter macOS, feste Ersatzdienste für Vorschaubilder und Tests).
public struct StudioServiceSet: Sendable {
    public var exporter: any AudioExporting
    public var waveforms: any WaveformProviding
    public var local: any LocalSourceAnalyzing
    public var remote: any RemoteSourceProviding
    public var tools: any StudioToolManaging

    public init(exporter: any AudioExporting, waveforms: any WaveformProviding, local: any LocalSourceAnalyzing,
                remote: any RemoteSourceProviding, tools: any StudioToolManaging) {
        self.exporter = exporter
        self.waveforms = waveforms
        self.local = local
        self.remote = remote
        self.tools = tools
    }
}
