import Foundation
import MLStudio
import StudioEngine

// Zusammenstellung der echten Audio-Studio-Dienste (StudioEngine).

extension StudioServiceSet {
    /// Ordner für Werkzeuge, Zwischenspeicher und Verlauf: ~/Library/Application Support/Music Library/Audio Studio
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Music Library", isDirectory: true).appendingPathComponent("Audio Studio", isDirectory: true)
    }

    static var live: StudioServiceSet {
        let tools = StudioToolManager(supportDirectory: supportDirectory.appendingPathComponent("Tools", isDirectory: true))
        return StudioServiceSet(exporter: AudioExporter(), waveforms: WaveformAnalyzer(), local: LocalSourceAnalyzer(),
                                remote: YtDlpSourceProvider(tools: tools), tools: tools)
    }
}

/// Erzeugt den Vorhör-Player (eigener AVAudioEngine, getrennt vom Hauptplayer).
@MainActor
enum StudioPreviewFactory {
    static func make() -> StudioPreviewing? { StudioPreviewPlayer() }
}
