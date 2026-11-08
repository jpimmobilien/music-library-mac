import Foundation

/// Hüllkurve einer Audiodatei für die Wellenform-Anzeige: je Block der kleinste und größte Wert
/// (Kanäle zusammengefasst) in der Grundauflösung, dazu vorberechnete gröbere Stufen (je Faktor 4),
/// damit auch eine Stunde Audio flüssig gezeichnet und gezoomt werden kann.
public struct WaveformData: Hashable, Sendable {
    /// Dauer in Sekunden.
    public var duration: Double
    /// Audio-Frames je Block der Grundauflösung (Standard 256).
    public var framesPerBucket: Int
    public var sampleRate: Double
    /// Stufe 0 = Grundauflösung, jede weitere Stufe fasst 4 Blöcke zusammen.
    public var levels: [Level]

    public struct Level: Hashable, Sendable {
        public var mins: [Float]
        public var maxs: [Float]
        public var framesPerBucket: Int

        public init(mins: [Float], maxs: [Float], framesPerBucket: Int) {
            self.mins = mins
            self.maxs = maxs
            self.framesPerBucket = framesPerBucket
        }
    }

    public init(duration: Double, framesPerBucket: Int, sampleRate: Double, levels: [Level]) {
        self.duration = duration
        self.framesPerBucket = framesPerBucket
        self.sampleRate = sampleRate
        self.levels = levels
    }

    /// Aus der Grundauflösung alle Stufen bilden.
    public init(base mins: [Float], maxs: [Float], framesPerBucket: Int, sampleRate: Double, duration: Double) {
        var levels = [Level(mins: mins, maxs: maxs, framesPerBucket: framesPerBucket)]
        while let last = levels.last, last.mins.count > 2048 {
            var lo: [Float] = []
            var hi: [Float] = []
            lo.reserveCapacity(last.mins.count / 4 + 1)
            hi.reserveCapacity(last.maxs.count / 4 + 1)
            var i = 0
            while i < last.mins.count {
                let end = min(i + 4, last.mins.count)
                var a: Float = .greatestFiniteMagnitude
                var b: Float = -.greatestFiniteMagnitude
                for j in i..<end {
                    a = min(a, last.mins[j])
                    b = max(b, last.maxs[j])
                }
                lo.append(a)
                hi.append(b)
                i = end
            }
            levels.append(Level(mins: lo, maxs: hi, framesPerBucket: last.framesPerBucket * 4))
        }
        self.init(duration: duration, framesPerBucket: framesPerBucket, sampleRate: sampleRate, levels: levels)
    }

    /// Spalten für die Anzeige: für den Zeitbereich `range` (Sekunden) genau `columns` Paare (min, max).
    /// Verwendet die gröbste Stufe, die noch mindestens einen Block je Spalte liefert.
    public func columns(range: ClosedRange<Double>, columns: Int) -> [(min: Float, max: Float)] {
        guard columns > 0, duration > 0, let base = levels.first, !base.mins.isEmpty else { return [] }
        let span = max(range.upperBound - range.lowerBound, 1e-6)
        let framesPerColumn = span * sampleRate / Double(columns)
        var level = base
        for l in levels where Double(l.framesPerBucket) <= framesPerColumn { level = l }
        let bucketSeconds = Double(level.framesPerBucket) / sampleRate
        var out: [(Float, Float)] = []
        out.reserveCapacity(columns)
        for c in 0..<columns {
            let t0 = range.lowerBound + span * Double(c) / Double(columns)
            let t1 = range.lowerBound + span * Double(c + 1) / Double(columns)
            var i0 = Int((t0 / bucketSeconds).rounded(.down))
            var i1 = Int((t1 / bucketSeconds).rounded(.up))
            i0 = max(0, min(i0, level.mins.count - 1))
            i1 = max(i0 + 1, min(i1, level.mins.count))
            var a: Float = .greatestFiniteMagnitude
            var b: Float = -.greatestFiniteMagnitude
            for j in i0..<i1 {
                a = min(a, level.mins[j])
                b = max(b, level.maxs[j])
            }
            if t0 >= duration { out.append((0, 0)) } else { out.append((a, b)) }
        }
        return out
    }

    /// Lautester Wert (0…1) – zum Skalieren leiser Aufnahmen in der Anzeige.
    public var peak: Float {
        guard let top = levels.last else { return 0 }
        let a = top.mins.map { abs($0) }.max() ?? 0
        let b = top.maxs.map { abs($0) }.max() ?? 0
        return max(a, b)
    }
}

/// Zeitangaben im Editor: „1:05.250“ bzw. „1:02:03.000“.
public enum StudioTime {
    public static func format(_ seconds: Double, millis: Bool = true) -> String {
        let s = max(0, seconds.isFinite ? seconds : 0)
        let totalMs = Int((s * 1000).rounded())
        let ms = totalMs % 1000
        let total = totalMs / 1000
        let h = total / 3600
        let m = (total % 3600) / 60
        let sec = total % 60
        let base = h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
        return millis ? base + String(format: ".%03d", ms) : base
    }

    /// Liest „65“, „1:05“, „1:05.25“, „1:05,25“, „01:02:03.5“. nil bei ungültiger Eingabe.
    public static func parse(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if t.isEmpty { return nil }
        let parts = t.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (1...3).contains(parts.count) else { return nil }
        var total = 0.0
        for (i, p) in parts.enumerated() {
            let isLast = i == parts.count - 1
            guard let v = Double(p), v >= 0, v.isFinite else { return nil }
            if !isLast, v != v.rounded() { return nil }
            if i > 0, v >= 60 { return nil }
            total = total * 60 + v
        }
        return total
    }
}
