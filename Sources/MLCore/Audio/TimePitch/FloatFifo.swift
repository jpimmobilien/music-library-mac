import Foundation

/// Puffer für planare (nicht verschachtelte) Float-Samples mit `channels` Kanälen und **fester** Kapazität –
/// Gegenstück zu `FloatFifo` in `audio/SincResampler.kt` der Android-App.
///
/// Unterschiede zu Android:
/// - Planar statt verschachtelt: Kanal c liegt zusammenhängend ab `plane(c)` (macOS arbeitet mit getrennten Kanälen).
/// - Die Kapazität wird im `init` festgelegt und wächst nie (Echtzeit-Sicherheit). Die Verarbeitungsstufen
///   berechnen sie aus den Höchstmengen je Aufruf. Reicht der Platz trotzdem einmal nicht, wird der Überschuss
///   verworfen und in `overflowFrames` gezählt (Diagnose; bleibt bei richtiger Bemessung immer 0).
///
/// Gelesen wird vorn, geschrieben hinten; verbrauchte Daten werden bei Bedarf nach vorn verschoben (memmove).
final class FloatFifo {
    let channels: Int
    let capacity: Int
    /// Speicher aller Kanäle; Kanal c beginnt bei `data + c * capacity`.
    let data: UnsafeMutablePointer<Float>
    /// Index (in Frames) des ersten gültigen Frames.
    private(set) var start = 0
    /// Anzahl gültiger Frames ab `start`.
    private(set) var frames = 0
    /// Verworfene Frames wegen fehlender Kapazität (soll immer 0 bleiben).
    private(set) var overflowFrames = 0

    init(channels: Int, capacity: Int) {
        precondition(channels >= 1 && capacity >= 1)
        self.channels = channels
        self.capacity = capacity
        data = .allocate(capacity: channels * capacity)
        data.initialize(repeating: 0, count: channels * capacity)
    }

    deinit {
        data.deallocate()
    }

    func clear() {
        start = 0
        frames = 0
        overflowFrames = 0
    }

    /// Anfang von Kanal `channel` im Speicher (Index 0 = Speicheranfang, nicht `start`).
    @inline(__always) func plane(_ channel: Int) -> UnsafeMutablePointer<Float> {
        data + channel * capacity
    }

    /// Zeiger auf Frame `frame` (relativ zu `start`) in Kanal `channel`.
    @inline(__always) func pointer(_ channel: Int, _ frame: Int) -> UnsafeMutablePointer<Float> {
        data + channel * capacity + start + frame
    }

    /// Schafft hinten Platz für bis zu `additional` Frames und gibt zurück, wie viele tatsächlich passen.
    private func makeRoom(_ additional: Int) -> Int {
        if start + frames + additional <= capacity { return additional }
        if start > 0 {
            if frames > 0 {
                for c in 0..<channels {
                    let p = plane(c)
                    p.update(from: p + start, count: frames) // überlappend erlaubt (memmove)
                }
            }
            start = 0
        }
        let free = capacity - frames
        if additional > free {
            overflowFrames += additional - free
            return free
        }
        return additional
    }

    /// Hängt `count` Frames aus den Kanalzeigern `src` (ab Frame `offset`) an.
    func append(_ src: UnsafePointer<UnsafePointer<Float>>, offset: Int, count: Int) {
        if count <= 0 { return }
        let n = makeRoom(count)
        if n <= 0 { return }
        let at = start + frames
        for c in 0..<channels {
            (plane(c) + at).update(from: src[c] + offset, count: n)
        }
        frames += n
    }

    /// Hängt `count` Frames aus einem anderen FIFO (ab dessen Frame `offset`) an.
    func append(from other: FloatFifo, offset: Int, count: Int) {
        if count <= 0 { return }
        let n = makeRoom(count)
        if n <= 0 { return }
        let at = start + frames
        for c in 0..<channels {
            (plane(c) + at).update(from: other.pointer(c, offset), count: n)
        }
        frames += n
    }

    func appendZeros(_ count: Int) {
        if count <= 0 { return }
        let n = makeRoom(count)
        if n <= 0 { return }
        let at = start + frames
        for c in 0..<channels {
            (plane(c) + at).update(repeating: 0, count: n)
        }
        frames += n
    }

    /// Hängt einen (uninitialisierten) Bereich an. Gibt den Frame-Index seines Beginns im Speicher
    /// (für `plane(c)[index]`) und die tatsächlich gewährte Anzahl zurück.
    func appendSpace(_ count: Int) -> (index: Int, count: Int) {
        if count <= 0 { return (start + frames, 0) }
        let n = makeRoom(count)
        let at = start + frames
        frames += n
        return (at, n)
    }

    func drop(_ count: Int) {
        let n = min(count, frames)
        if n <= 0 { return }
        start += n
        frames -= n
        if frames == 0 { start = 0 }
    }

    /// Kürzt auf höchstens `count` Frames (hinten abschneiden).
    func truncate(_ count: Int) {
        if count < frames { frames = max(0, count) }
    }

    /// Kopiert bis zu `maxFrames` Frames nach `dest` (Kanalzeiger, ab Frame `offset`), verwirft sie hier
    /// und gibt die Anzahl zurück.
    func read(into dest: UnsafePointer<UnsafeMutablePointer<Float>>, offset: Int, maxFrames: Int) -> Int {
        let n = min(maxFrames, frames)
        if n <= 0 { return 0 }
        for c in 0..<channels {
            (dest[c] + offset).update(from: pointer(c, 0), count: n)
        }
        drop(n)
        return n
    }
}
