import Foundation

/// Schnelle Fourier-Transformation für reelle Signale der Länge `n` (Zweierpotenz) –
/// Portierung von `audio/Fft.kt` (`RealFft`) der Android-App.
///
/// Intern eine komplexe Radix-2-FFT der Länge n/2 mit dem üblichen „Packing“-Trick (gerade/ungerade
/// Samples als Real-/Imaginärteil) – etwa halb so teuer wie eine komplexe FFT der Länge n.
/// Ergebnis: Bins 0…n/2 (n/2+1 Werte). Rücktransformation inklusive Skalierung (1/n).
///
/// Echtzeit-sicher: Alle Tabellen und Arbeitspuffer werden im `init` angelegt; `forward`/`inverse`
/// fordern keinen Speicher an. Nicht threadsicher (interne Arbeitspuffer) – eine Instanz pro Thread.
public final class RealFFT {
    public let n: Int
    private let half: Int
    private let bitrev: UnsafeMutablePointer<Int>
    private let cosTable: UnsafeMutablePointer<Double>
    private let sinTable: UnsafeMutablePointer<Double>
    private let postCos: UnsafeMutablePointer<Double>
    private let postSin: UnsafeMutablePointer<Double>
    private let workRe: UnsafeMutablePointer<Double>
    private let workIm: UnsafeMutablePointer<Double>

    public init(n: Int) {
        precondition(n >= 4 && n & (n - 1) == 0, "FFT-Länge muss eine Zweierpotenz ≥ 4 sein")
        self.n = n
        half = n / 2
        bitrev = .allocate(capacity: half)
        cosTable = .allocate(capacity: half / 2)
        sinTable = .allocate(capacity: half / 2)
        postCos = .allocate(capacity: half)
        postSin = .allocate(capacity: half)
        workRe = .allocate(capacity: half)
        workIm = .allocate(capacity: half)
        workRe.initialize(repeating: 0, count: half)
        workIm.initialize(repeating: 0, count: half)

        var bits = 0
        while 1 << bits < half { bits += 1 }
        for i in 0..<half {
            var r = 0
            var x = i
            for _ in 0..<bits {
                r = (r << 1) | (x & 1)
                x >>= 1
            }
            bitrev[i] = r
        }
        // Gleiche Rechenreihenfolge wie in Kotlin (2π·i / half), damit die Tabellen übereinstimmen.
        for i in 0..<half / 2 {
            cosTable[i] = cos(2.0 * Double.pi * Double(i) / Double(half))
            sinTable[i] = -sin(2.0 * Double.pi * Double(i) / Double(half))
        }
        for k in 0..<half {
            postCos[k] = cos(2.0 * Double.pi * Double(k) / Double(n))
            postSin[k] = -sin(2.0 * Double.pi * Double(k) / Double(n))
        }
    }

    deinit {
        bitrev.deallocate()
        cosTable.deallocate()
        sinTable.deallocate()
        postCos.deallocate()
        postSin.deallocate()
        workRe.deallocate()
        workIm.deallocate()
    }

    /// Komplexe FFT (in-place, vorwärts) der Länge n/2.
    private func complexFFT(_ re: UnsafeMutablePointer<Double>, _ im: UnsafeMutablePointer<Double>) {
        let half = self.half
        for i in 0..<half {
            let j = bitrev[i]
            if j > i {
                let tr = re[i]; re[i] = re[j]; re[j] = tr
                let ti = im[i]; im[i] = im[j]; im[j] = ti
            }
        }
        var size = 2
        while size <= half {
            let halfSize = size / 2
            let step = half / size
            var start = 0
            while start < half {
                var k = 0
                var j = start
                let end = start + halfSize
                while j < end {
                    let wr = cosTable[k]
                    let wi = sinTable[k]
                    let l = j + halfSize
                    let tr = re[l] * wr - im[l] * wi
                    let ti = re[l] * wi + im[l] * wr
                    re[l] = re[j] - tr
                    im[l] = im[j] - ti
                    re[j] += tr
                    im[j] += ti
                    k += step
                    j += 1
                }
                start += size
            }
            size *= 2
        }
    }

    /// Vorwärts: `input` (Länge n) → Spektrum `outRe`/`outIm` (Länge ≥ n/2+1).
    public func forward(_ input: UnsafePointer<Double>, _ outRe: UnsafeMutablePointer<Double>, _ outIm: UnsafeMutablePointer<Double>) {
        let re = workRe
        let im = workIm
        let half = self.half
        for i in 0..<half {
            re[i] = input[2 * i]
            im[i] = input[2 * i + 1]
        }
        complexFFT(re, im)
        // Entpacken: X[k] = (Z[k] + conj(Z[N/2-k]))/2 + W^k (Z[k] - conj(Z[N/2-k]))/(2i)
        outRe[0] = re[0] + im[0]
        outIm[0] = 0
        outRe[half] = re[0] - im[0]
        outIm[half] = 0
        var k = 1
        while k < half {
            let zr = re[k]
            let zi = im[k]
            let cr = re[half - k]
            let ci = -im[half - k]
            let er = 0.5 * (zr + cr)
            let ei = 0.5 * (zi + ci)
            let orr = 0.5 * (zi - ci)
            let oi = -0.5 * (zr - cr)
            let wr = postCos[k]
            let wi = postSin[k]
            outRe[k] = er + (orr * wr - oi * wi)
            outIm[k] = ei + (orr * wi + oi * wr)
            k += 1
        }
    }

    /// Rückwärts: Spektrum `inRe`/`inIm` (Bins 0…n/2) → reelles Signal `output` (Länge n), skaliert mit 1/n.
    public func inverse(_ inRe: UnsafePointer<Double>, _ inIm: UnsafePointer<Double>, _ output: UnsafeMutablePointer<Double>) {
        let re = workRe
        let im = workIm
        let half = self.half
        // Umkehr des Entpackens: Z[k] = E[k] + i·O[k], mit E/O aus X[k] und X[N/2-k]
        for k in 0..<half {
            let xr = inRe[k]
            let xi = inIm[k]
            let yr = inRe[half - k]
            let yi = -inIm[half - k]
            let er = 0.5 * (xr + yr)
            let ei = 0.5 * (xi + yi)
            // O = (X - conj(X[N/2-k])) / (2·W^k)  → Multiplikation mit conj(W^k)
            let dr = 0.5 * (xr - yr)
            let di = 0.5 * (xi - yi)
            let wr = postCos[k]
            let wi = -postSin[k]
            let orr = dr * wr - di * wi
            let oi = dr * wi + di * wr
            // Z = E + i·O  (konjugiert für inverse FFT über Vorwärts-FFT)
            re[k] = er - oi
            im[k] = -(ei + orr)
        }
        complexFFT(re, im)
        let scale = 1.0 / Double(half)
        for i in 0..<half {
            output[2 * i] = re[i] * scale
            output[2 * i + 1] = -im[i] * scale
        }
    }

    /// Bequeme Variante mit Arrays (fordert Speicher an – nicht für den Audio-Thread; für Analysen und Tests).
    /// - Returns: Real- und Imaginärteil der Bins 0…n/2.
    public func forward(_ input: [Double]) -> (re: [Double], im: [Double]) {
        precondition(input.count >= n, "Eingang kürzer als die FFT-Länge")
        var re = [Double](repeating: 0, count: half + 1)
        var im = [Double](repeating: 0, count: half + 1)
        input.withUnsafeBufferPointer { ip in
            re.withUnsafeMutableBufferPointer { rp in
                im.withUnsafeMutableBufferPointer { mp in
                    forward(ip.baseAddress!, rp.baseAddress!, mp.baseAddress!)
                }
            }
        }
        return (re, im)
    }
}
