import Foundation

/// Planarer Float32-Block: je Kanal ein eigener, zusammenhängender Speicherbereich mit `capacity` Frames.
/// Wird zwischen Lesen, Verarbeiten und Kodieren weitergereicht und wiederverwendet (keine Kopien
/// der ganzen Datei, nur Blöcke von einigen Zehntausend Frames).
final class FloatBlock {
    let channelCount: Int
    let capacity: Int
    /// Gültige Frames ab Index 0.
    var frames: Int = 0
    let channels: [UnsafeMutablePointer<Float>]

    init(channels: Int, capacity: Int) {
        precondition(channels > 0 && capacity > 0, "FloatBlock braucht Kanäle und Kapazität")
        self.channelCount = channels
        self.capacity = capacity
        self.channels = (0..<channels).map { _ in
            let p = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
            p.initialize(repeating: 0, count: capacity)
            return p
        }
    }

    deinit {
        for p in channels {
            p.deinitialize(count: capacity)
            p.deallocate()
        }
    }

    /// Setzt `count` Frames ab `start` in allen Kanälen auf 0.
    func zero(from start: Int, count: Int) {
        guard count > 0 else { return }
        for p in channels { (p + start).update(repeating: 0, count: count) }
    }

    /// Kopiert `count` Frames aus `other` (gleiche Kanalzahl) ab `sourceStart` nach `destStart`.
    func copy(from other: FloatBlock, sourceStart: Int, destStart: Int, count: Int) {
        guard count > 0 else { return }
        for c in 0..<min(channelCount, other.channelCount) {
            (channels[c] + destStart).update(from: other.channels[c] + sourceStart, count: count)
        }
    }

    /// Größter Betrag aller gültigen Werte (für Tests und Diagnose).
    var peak: Float {
        var m: Float = 0
        for p in channels {
            for i in 0..<frames { m = max(m, abs(p[i])) }
        }
        return m
    }
}
