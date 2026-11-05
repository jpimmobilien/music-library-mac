import Foundation

/**
 * Bild als ARGB-Werte (`0xAARRGGBB`, **nicht** vormultipliziert, Zeile für Zeile, Ursprung oben links) –
 * entspricht `Raster` bzw. dem `IntArray` eines `Bitmap.Config.ARGB_8888` unter Android.
 *
 * Umwandlung in ein `CGImage` (macht die App): Die `UInt32`-Werte liegen im Speicher als
 * B, G, R, A (Little Endian) – also `CGBitmapInfo.byteOrder32Little` +
 * `CGImageAlphaInfo.first` (nicht vormultipliziert, für `CGImage(width:height:bitsPerComponent: 8,
 * bitsPerPixel: 32, bytesPerRow: width * 4, …)` zulässig). Wer einen `CGContext` füllen will, nimmt
 * [premultipliedPixels()] und `CGImageAlphaInfo.premultipliedFirst`.
 */
public struct RasterImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /** `width * height` Werte, `0xAARRGGBB`, nicht vormultipliziert. */
    public var pixels: [UInt32]

    /** Leeres (vollständig transparentes) Bild. */
    public init(width: Int, height: Int) {
        precondition(width >= 0 && height >= 0, "negative Bildgröße")
        self.width = width
        self.height = height
        self.pixels = [UInt32](repeating: 0, count: width * height)
    }

    /** Bild aus vorhandenen Pixeln (`pixels.count` muss `width * height` sein). */
    public init(width: Int, height: Int, pixels: [UInt32]) {
        precondition(pixels.count == width * height, "Pixelanzahl passt nicht zur Größe")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /** Pixel an (x, y) als `0xAARRGGBB`. */
    @inlinable
    public subscript(x: Int, y: Int) -> UInt32 {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }

    /** Deckkraft (0…255) an (x, y). */
    @inlinable
    public func alpha(x: Int, y: Int) -> Int { Int(pixels[y * width + x] >> 24) }

    /**
     * Dieselben Pixel vormultipliziert (`0xAARRGGBB` mit R, G, B · A / 255, gerundet) – passend für
     * `CGImageAlphaInfo.premultipliedFirst` + `byteOrder32Little`.
     */
    public func premultipliedPixels() -> [UInt32] {
        var out = [UInt32](repeating: 0, count: pixels.count)
        pixels.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for i in 0..<src.count {
                    let p = src[i]
                    let a = p >> 24
                    if a == 255 { dst[i] = p; continue }
                    if a == 0 { dst[i] = 0; continue }
                    let r = ((p >> 16) & 0xFF) * a
                    let g = ((p >> 8) & 0xFF) * a
                    let b = (p & 0xFF) * a
                    dst[i] = (a << 24) | (((r + 127) / 255) << 16) | (((g + 127) / 255) << 8) | ((b + 127) / 255)
                }
            }
        }
        return out
    }
}

/** Tonarm-Bild mit Schatten; [pivotX]/[pivotY] = Drehpunkt im Bild (Pixel). */
public struct ArmRaster: Sendable {
    /** Tonarm in Grundstellung (Rohr zeigt nach rechts, Drehpunkt links). */
    public let arm: RasterImage
    /** Weicher Schatten (nur Deckkraft, Farbe Schwarz), gleiche Größe wie [arm]. */
    public let shadow: RasterImage
    /** Drehpunkt im Bild (Pixel, gemessen von der linken oberen Ecke). */
    public let pivotX: Float
    public let pivotY: Float

    public init(arm: RasterImage, shadow: RasterImage, pivotX: Float, pivotY: Float) {
        self.arm = arm
        self.shadow = shadow
        self.pivotX = pivotX
        self.pivotY = pivotY
    }
}

// ---------------------------------------------------------------------------------------------
// Gemeinsame Hilfen für alle Renderer (intern)
// ---------------------------------------------------------------------------------------------

/** π als Float, genau wie Kotlins `PI.toFloat()` (3.1415927 – Swifts `Float.pi` ist 3.1415925). */
let PI_F: Float = Float(Double.pi)

/**
 * Zeilen (bzw. beliebige unabhängige Aufgaben) parallel auf allen Prozessorkernen berechnen – wie
 * `IntStream.range(0, n).parallel()` im Original. Jede Aufgabe darf nur ihre eigenen Pixel schreiben.
 */
@inline(__always)
func parallelFor(_ count: Int, _ body: (Int) -> Void) {
    if count <= 0 { return }
    if count == 1 { body(0); return }
    DispatchQueue.concurrentPerform(iterations: count, execute: body)
}

/** `Float.toInt()` wie in Kotlin: Richtung null abschneiden, NaN → 0, außerhalb des Bereichs begrenzen. */
@inline(__always)
func kInt(_ f: Float) -> Int32 {
    if f.isNaN { return 0 }
    if f >= 2147483648 { return Int32.max } // 2^31 (exakt als Float darstellbar)
    if f <= -2147483648 { return Int32.min }
    return Int32(f)
}

/** Wie [kInt], aber als `Int` (für Indizes). */
@inline(__always)
func kIdx(_ f: Float) -> Int { Int(kInt(f)) }

/** `coerceIn(lo, hi)` wie in Kotlin (NaN bleibt NaN). */
@inline(__always)
func clampf(_ v: Float, _ lo: Float, _ hi: Float) -> Float {
    if v < lo { return lo }
    if v > hi { return hi }
    return v
}

/** Kotlins `Math.max(Float, Float)` für endliche Werte. */
@inline(__always)
func fmaxk(_ a: Float, _ b: Float) -> Float { a >= b ? a : b }

@inline(__always)
func fmink(_ a: Float, _ b: Float) -> Float { a <= b ? a : b }

// Transzendente Funktionen wie in Kotlin/JVM: in Double gerechnet und nach Float gerundet
// (`kotlin.math.exp(Float)` = `Math.exp(x.toDouble()).toFloat()` usw.) – so stimmen die Pixel mit dem
// Original überein.
/// exp(x) in Double, nach Float gerundet. Für x < −104 ist das Ergebnis < 2⁻¹⁵⁰ und wird in Float exakt 0 –
/// dann ohne Bibliotheksaufruf (schmale Gauß-Keulen liegen auf den meisten Pixeln in diesem Bereich).
@inline(__always) func kexp(_ x: Float) -> Float { x < -104 ? 0 : Float(exp(Double(x))) }
@inline(__always) func ksin(_ x: Float) -> Float { Float(sin(Double(x))) }
@inline(__always) func kcos(_ x: Float) -> Float { Float(cos(Double(x))) }
@inline(__always) func kacos(_ x: Float) -> Float { Float(acos(Double(x))) }
@inline(__always) func katan2(_ y: Float, _ x: Float) -> Float { Float(atan2(Double(y), Double(x))) }
@inline(__always) func khypot(_ x: Float, _ y: Float) -> Float { Float(hypot(Double(x), Double(y))) }
@inline(__always) func ksqrt(_ x: Float) -> Float { x.squareRoot() }
@inline(__always) func kfloor(_ x: Float) -> Float { x.rounded(.down) }

/**
 * `Float.roundToInt()` wie in Kotlin (Halbe nach oben) für Werte 0…2³² (≤ 0 und NaN → 0). Ohne
 * Bibliotheksaufruf: `x − ⌊x⌋` ist in Float exakt, der Vergleich mit 0,5 daher genau.
 */
@inline(__always)
func kRound(_ x: Float) -> UInt32 {
    if !(x > 0) { return 0 }
    let t = UInt32(x)
    return x - Float(t) >= 0.5 ? t + 1 : t
}
