package de.privateapp.aether.platform.storage

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.media.ThumbnailUtils
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.LruCache
import android.util.Size
import androidx.core.graphics.createBitmap
import androidx.core.graphics.drawable.toBitmap
import de.privateapp.aether.files.FileEntry
import de.privateapp.aether.files.FileKind
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException

/**
 * Vorschaubilder für Bilder, Videos, Musik (Albumcover), PDFs (erste Seite) und App-Pakete (App-Symbol).
 *
 * Erzeugt mit den Bordmitteln von Android (`ThumbnailUtils`, `PdfRenderer`, `PackageManager`) direkt aus der Datei,
 * nichts wird auf dem Speicher abgelegt. Ein Zwischenspeicher im Arbeitsspeicher (höchstens [maxCacheBytes]) sorgt
 * dafür, dass beim Scrollen nichts doppelt erzeugt wird; er hängt an Pfad, Änderungszeit und Größe – eine geänderte
 * Datei bekommt ein neues Vorschaubild. Höchstens vier Vorschaubilder entstehen gleichzeitig.
 */
class ThumbnailLoader(
    context: Context,
    maxCacheBytes: Int = 32 * 1024 * 1024,
    private val io: CoroutineDispatcher = Dispatchers.IO.limitedParallelism(4),
) {
    private val appContext = context.applicationContext

    private val cache = object : LruCache<String, Bitmap>(maxCacheBytes) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.allocationByteCount
    }

    /** Merkt sich Dateien ohne Vorschaubild (z. B. Musik ohne Cover), damit sie nicht immer wieder versucht werden. */
    private val misses = LruCache<String, Boolean>(2_000)

    fun supports(entry: FileEntry): Boolean = !entry.isDirectory && entry.kind in SUPPORTED

    /** Bereits erzeugtes Vorschaubild ohne Wartezeit (für den ersten Frame beim Scrollen). */
    fun cached(entry: FileEntry, sizePx: Int): Bitmap? = cache.get(key(entry, sizePx))

    /** `null` = kein Vorschaubild möglich (Datei ohne Bildinhalt, beschädigt, geschützt) – dann zeigt die Oberfläche das Symbol. */
    suspend fun load(entry: FileEntry, sizePx: Int): Bitmap? {
        if (!supports(entry)) return null
        val key = key(entry, sizePx)
        cache.get(key)?.let { return it }
        if (misses.get(key) == true) return null
        return withContext(io) {
            ensureActive()
            val bitmap = try {
                create(entry, sizePx.coerceIn(32, 1024))
            } catch (e: IOException) {
                null
            } catch (e: SecurityException) {
                null
            } catch (e: OutOfMemoryError) {
                null
            } catch (e: RuntimeException) {
                null
            }
            if (bitmap != null) cache.put(key, bitmap) else misses.put(key, true)
            bitmap
        }
    }

    fun clear() {
        cache.evictAll()
        misses.evictAll()
    }

    private fun create(entry: FileEntry, size: Int): Bitmap? {
        val file = File(entry.path)
        val target = Size(size, size)
        return when (entry.kind) {
            FileKind.IMAGE -> ThumbnailUtils.createImageThumbnail(file, target, null)
            FileKind.VIDEO -> ThumbnailUtils.createVideoThumbnail(file, target, null)
            FileKind.AUDIO -> ThumbnailUtils.createAudioThumbnail(file, target, null)
            FileKind.PDF -> pdfFirstPage(file, size)
            FileKind.APK -> apkIcon(entry.path, size)
            else -> null
        }
    }

    private fun pdfFirstPage(file: File, size: Int): Bitmap? =
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
            PdfRenderer(fd).use { renderer ->
                if (renderer.pageCount < 1) return null
                renderer.openPage(0).use { page ->
                    val scale = size.toFloat() / maxOf(page.width, page.height).coerceAtLeast(1)
                    val w = (page.width * scale).toInt().coerceAtLeast(1)
                    val h = (page.height * scale).toInt().coerceAtLeast(1)
                    val bitmap = createBitmap(w, h)
                    // PDF-Seiten sind durchsichtig gespeichert; dargestellt werden sie wie Papier.
                    Canvas(bitmap).drawColor(Color.WHITE)
                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    bitmap
                }
            }
        }

    private fun apkIcon(path: String, size: Int): Bitmap? {
        val pm = appContext.packageManager
        val info = archiveInfo(pm, path) ?: return null
        val app = info.applicationInfo ?: return null
        app.sourceDir = path
        app.publicSourceDir = path
        return app.loadIcon(pm).toBitmap(size, size)
    }

    private fun key(entry: FileEntry, sizePx: Int) = "${entry.path}|${entry.modifiedMillis}|${entry.sizeBytes}|$sizePx"

    companion object {
        private val SUPPORTED = setOf(FileKind.IMAGE, FileKind.VIDEO, FileKind.AUDIO, FileKind.PDF, FileKind.APK)

        internal fun archiveInfo(pm: PackageManager, path: String): PackageInfo? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getPackageArchiveInfo(path, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageArchiveInfo(path, 0)
            }
    }
}
