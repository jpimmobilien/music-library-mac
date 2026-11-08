import Foundation
import MLStudio

/// Vorhören im Editor über einen eigenen AVAudioEngine. (Platzhalter – wird vom Engine-Teil ersetzt.)
@MainActor
public final class StudioPreviewPlayer: StudioPreviewing {
    public init() {}

    public func load(_ file: URL) throws {}
    public func play(from start: Double, to end: Double?) {}
    public func pause() {}
    public func stop() {}
    public var position: Double { 0 }
    public var isPlaying: Bool { false }
    public var onFinish: (() -> Void)?
}
