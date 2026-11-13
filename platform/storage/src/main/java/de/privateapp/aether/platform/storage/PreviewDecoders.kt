package de.privateapp.aether.platform.storage

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageDecoder
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import androidx.core.graphics.createBitmap
import java.io.Closeable
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.roundToInt

/** Ein für die Schnellansicht dekodiertes Bild. [width]/[height] = Originalgröße in Pixeln. */
class DecodedImage(val bitmap: Bitmap, val width: Int, val height: Int, val animated: Boolean, val mimeType: String)

sealed interface ImageDecodeResult {
    class Ok(val image: DecodedImage) : ImageDecodeResult

    /** Format kann Android auf diesem Gerät nicht dekodieren (z. B. SVG) oder die Datei ist beschädigt. */
    data class Unsupported(val detail: String?) : ImageDecodeResult

    data object TooLarge : ImageDecodeResult

    /** Datei gibt es nicht mehr (z. B. von einer anderen App gelöscht). */
    data object Missing : ImageDecodeResult
}

/**
 * Bilder für die Schnellansicht: dekodiert mit `ImageDecoder` (berücksichtigt die EXIF-Drehung, kann HEIC/HEIF,
 * WebP, AVIF ab Android 12, GIF) und verkleinert auf höchstens [maxSidePx] – so bleibt auch ein 200-Megapixel-Foto
 * im Speicher handhabbar. Animierte Bilder erscheinen als erstes Bild.
 */
object PreviewImages {

    fun decode(path: String, maxSidePx: Int): ImageDecodeResult {
        var w = 0
        var h = 0
        var animated = false
        var mime = ""
        val file = File(path)
        if (!file.exists()) return ImageDecodeResult.Missing
        return try {
            val bitmap = ImageDecoder.decodeBitmap(ImageDecoder.createSource(file)) { decoder, info, _ ->
                w = info.size.width
                h = info.size.height
                animated = info.isAnimated
                mime = info.mimeType
                val longest = max(w, h)
                if (longest > maxSidePx && longest > 0) {
                    val scale = maxSidePx.toFloat() / longest
                    decoder.setTargetSize((w * scale).roundToInt().coerceAtLeast(1), (h * scale).roundToInt().coerceAtLeast(1))
                }
                decoder.memorySizePolicy = ImageDecoder.MEMORY_POLICY_LOW_RAM
            }
            ImageDecodeResult.Ok(DecodedImage(bitmap, w, h, animated, mime))
        } catch (e: FileNotFoundException) {
            ImageDecodeResult.Missing
        } catch (e: ImageDecoder.DecodeException) {
            ImageDecodeResult.Unsupported(e.message)
        } catch (e: IOException) {
            if (!file.exists()) ImageDecodeResult.Missing else ImageDecodeResult.Unsupported(e.message)
        } catch (e: OutOfMemoryError) {
            ImageDecodeResult.TooLarge
        } catch (e: RuntimeException) {
            ImageDecodeResult.Unsupported(e.message)
        }
    }
}

/**
 * Seiten eines PDFs für die Schnellansicht. Android kann je Dokument nur eine Seite zugleich öffnen; [render] ist
 * deshalb synchronisiert. Seitengrößen werden erst beim ersten Zeichnen ermittelt (bis dahin gilt die erste Seite als
 * Muster) – so öffnen sich auch Dokumente mit Tausenden Seiten sofort. Seiten werden auf weißem Papier gezeichnet
 * (PDF-Seiten sind durchsichtig gespeichert). Nach Gebrauch [closeInBackground] bzw. [close] aufrufen.
 */
class PdfPages private constructor(private val fd: ParcelFileDescriptor, private val renderer: PdfRenderer) : Closeable {

    val pageCount: Int = renderer.pageCount

    private val sizes = arrayOfNulls<Pair<Int, Int>>(pageCount)

    /** Größe der ersten Seite in PDF-Punkten – Muster für noch nicht vermessene Seiten. */
    val firstPageSize: Pair<Int, Int> = if (pageCount > 0) measure(0) else 595 to 842

    @Volatile
    private var closed = false

    /** Seitengröße in PDF-Punkten (1/72 Zoll), wenn schon bekannt. */
    fun knownPageSize(index: Int): Pair<Int, Int>? = sizes.getOrNull(index)

    private fun measure(index: Int): Pair<Int, Int> = synchronized(this) {
        sizes[index] ?: renderer.openPage(index).use { (it.width to it.height).also { s -> sizes[index] = s } }
    }

    /**
     * Zeichnet Seite [index] mit [widthPx] Breite (sehr lange Seiten werden so verkleinert, dass das Seitenverhältnis
     * erhalten bleibt). `null`, wenn das Dokument inzwischen geschlossen ist.
     */
    fun render(index: Int, widthPx: Int): Bitmap? = synchronized(this) {
        if (closed || index !in 0 until pageCount) return null
        renderer.openPage(index).use { page ->
            sizes[index] = page.width to page.height
            val pw = page.width.coerceAtLeast(1).toFloat()
            val ph = page.height.coerceAtLeast(1).toFloat()
            var w = widthPx.coerceIn(1, MAX_SIDE).toFloat()
            var h = w * ph / pw
            if (h > MAX_SIDE * 4) {
                h = (MAX_SIDE * 4).toFloat()
                w = h * pw / ph
            }
            val bitmap = createBitmap(w.roundToInt().coerceAtLeast(1), h.roundToInt().coerceAtLeast(1))
            Canvas(bitmap).drawColor(Color.WHITE)
            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            bitmap
        }
    }

    override fun close() {
        closed = true
        synchronized(this) {
            try {
                renderer.close()
            } catch (e: IllegalStateException) {
                // bereits geschlossen
            } finally {
                try {
                    fd.close()
                } catch (e: IOException) {
                    // bereits geschlossen
                }
            }
        }
    }

    /**
     * Schließt ohne den aufrufenden Thread zu blockieren: Ein gerade laufendes Zeichnen lässt sich nicht abbrechen und
     * würde sonst z. B. den Hauptthread beim Verlassen der Seite festhalten.
     */
    fun closeInBackground() {
        closed = true
        closer.execute { close() }
    }

    companion object {
        private const val MAX_SIDE = 2400

        private val closer = Executors.newSingleThreadExecutor { r -> Thread(r, "aether-pdf-close").apply { isDaemon = true } }

        /** Öffnet das PDF. [SecurityException] = kennwortgeschützt, [IOException] = beschädigt oder nicht lesbar. */
        fun open(path: String): PdfPages {
            val fd = ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
            val renderer = try {
                PdfRenderer(fd)
            } catch (e: Exception) {
                fd.close()
                throw e
            }
            return try {
                PdfPages(fd, renderer)
            } catch (e: Exception) {
                renderer.close()
                fd.close()
                throw e
            }
        }
    }
}
