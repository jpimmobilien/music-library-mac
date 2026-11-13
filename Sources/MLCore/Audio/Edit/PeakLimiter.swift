import Foundation

/// Begrenzer mit Vorausschau: Kein Abtastwert überschreitet `ceiling` (linear), ohne harte Kanten.
///
/// Verfahren: benötigte Verstärkung je Frame (ceiling / Spitze über alle Kanäle) → gleitendes Minimum über
/// Vorausschau + 1 Frames → Rückkehr mit `release` → gleitender Mittelwert über dieselbe Länge. Das Signal wird
/// um die Vorausschau verzögert; dadurch ist die Verstärkung an jeder Spitze garantiert klein genug (der
/// Mittelwert besteht dort nur aus Werten ≤ der benötigten Verstärkung) und sinkt vorher weich ab.
///
/// Die Ausgabe ist um `latency` Frames verzögert (Anfang: Stille). Am Ende `latency` Frames Stille nachschieben
/// und die ersten `latency` Frames verwerfen, um dieselbe Länge zu erhalten (das erledigt `EditChain`).
public final class PeakLimiter {
    public let channels: Int
    public let ceiling: Float
    public let latency: Int
    private let window: Int
    private let releaseCoef: Double
    // Verzögerungsleitung je Kanal
    private var delay: [[Float]]
    private var delayPos = 0
    // gleitendes Minimum (monotone Schlange)
    private var minIdx: [Int64]
    private var minVal: [Double]
    private var minHead = 0
    private var minCount = 0
    // gleitender Mittelwert
    private var avgRing: [Double]
    private var avgPos = 0
    private var avgSum: Double
    private var smoothed = 1.0
    private var index: Int64 = 0
    /// Kleinste angewendete Verstärkung (Diagnose).
    public private(set) var minimumGain: Double = 1

    /// - Parameters:
    ///   - ceiling: Höchstwert (linear), z. B. 0,891 für −1 dBFS.
    ///   - lookahead: Vorausschau in Sekunden (Standard 5 ms).
    ///   - release: Rückkehrzeit in Sekunden (Standard 80 ms).
    public init(sampleRate: Double, channels: Int, ceiling: Float, lookahead: Double = 0.005, release: Double = 0.08) {
        precondition(channels >= 1 && ceiling > 0 && sampleRate > 0)
        self.channels = channels
        self.ceiling = ceiling
        latency = max(1, Int((lookahead * sampleRate).rounded()))
        window = latency + 1
        releaseCoef = exp(-1 / max(release * sampleRate, 1))
        delay = Array(repeating: Array(repeating: 0, count: latency), count: channels)
        minIdx = Array(repeating: 0, count: window + 1)
        minVal = Array(repeating: 1, count: window + 1)
        avgRing = Array(repeating: 1, count: window)
        avgSum = Double(window)
    }

    /// Verarbeitet `frames` Frames in-place (Ausgabe um `latency` verzögert).
    public func process(_ data: [UnsafeMutablePointer<Float>], frames: Int) {
        guard frames > 0 else { return }
        precondition(data.count >= channels, "Ein Zeiger je Kanal")
        let cap = minIdx.count
        let ceil = Double(ceiling)
        for i in 0..<frames {
            var peak: Float = 0
            for c in 0..<channels { peak = max(peak, abs(data[c][i])) }
            let need = peak > ceiling ? ceil / Double(peak) : 1
            // gleitendes Minimum über die letzten `window` Werte
            while minCount > 0 {
                let last = (minHead + minCount - 1) % cap
                if minVal[last] >= need { minCount -= 1 } else { break }
            }
            let slot = (minHead + minCount) % cap
            minIdx[slot] = index
            minVal[slot] = need
            minCount += 1
            while minIdx[minHead] <= index - Int64(window) {
                minHead = (minHead + 1) % cap
                minCount -= 1
            }
            let g1 = minVal[minHead]
            // weiche Rückkehr (nie über g1)
            smoothed = g1 < smoothed ? g1 : smoothed + (g1 - smoothed) * (1 - releaseCoef)
            // gleitender Mittelwert
            avgSum += smoothed - avgRing[avgPos]
            avgRing[avgPos] = smoothed
            avgPos = (avgPos + 1) % window
            let gain = min(1, avgSum / Double(window))
            if gain < minimumGain { minimumGain = gain }
            let g = Float(gain)
            for c in 0..<channels {
                let p = data[c]
                let x = p[i]
                let delayed = delay[c][delayPos]
                delay[c][delayPos] = x
                var y = delayed * g
                // Rundungsreserve: nie über die Grenze
                if y > ceiling { y = ceiling } else if y < -ceiling { y = -ceiling }
                p[i] = y
            }
            delayPos = (delayPos + 1) % latency
            index += 1
        }
        // Gleitkomma-Drift des Mittelwerts gelegentlich bereinigen
        if index % 65_536 < Int64(frames) { avgSum = avgRing.reduce(0, +) }
    }
}
