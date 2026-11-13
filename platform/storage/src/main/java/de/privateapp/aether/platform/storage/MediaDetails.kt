package de.privateapp.aether.platform.storage

import android.graphics.BitmapFactory
import android.graphics.pdf.PdfRenderer
import android.media.ExifInterface
import android.media.MediaMetadataRetriever
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.IOException
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.time.format.ResolverStyle

/** Angaben aus einem Bild (Dateikopf und EXIF). `null` = steht nicht in der Datei. */
data class ImageDetails(
    /** Breite und Höhe so, wie das Bild angezeigt wird (EXIF-Drehung berücksichtigt). */
    val width: Int?,
    val height: Int?,
    /** Aufnahmezeit laut Kamera – Ortszeit der Kamera, ohne Zeitzone (so speichert EXIF sie). */
    val takenAt: LocalDateTime?,
    val cameraMake: String?,
    val cameraModel: String?,
    /** Die Datei enthält GPS-Koordinaten (sie werden bewusst nicht angezeigt). */
    val hasLocation: Boolean,
)

/** Angaben aus einer Audio- oder Videodatei laut `MediaMetadataRetriever`. */
data class MediaDetails(
    val durationMillis: Long?,
    val width: Int?,
    val height: Int?,
    val title: String?,
    val artist: String?,
    val album: String?,
    val hasVideo: Boolean,
    val hasAudio: Boolean,
)

/** Angaben aus einem PDF. [protected] = Kennwortschutz, Seitenzahl dann unbekannt. */
data class PdfDetails(val pageCount: Int?, val protected: Boolean)

/**
 * Liest Angaben aus Medien- und PDF-Dateien – nur lesend, mit den Bordmitteln von Android. Alle Funktionen blockieren
 * kurz (Datei wird geöffnet) und gehören auf einen Hintergrund-Thread. Was die Datei nicht enthält oder Android nicht
 * lesen kann, bleibt `null` – nichts wird geschätzt.
 */
object MediaDetailsReader {

    // Streng: „2023:02:30“ ist ungültig und wird nicht stillschweigend zum 28. Februar.
    private val exifDate = DateTimeFormatter.ofPattern("uuuu:MM:dd HH:mm:ss").withResolverStyle(ResolverStyle.STRICT)

    fun image(path: String): ImageDetails? {
        val file = File(path)
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        try {
            BitmapFactory.decodeFile(path, bounds)
        } catch (e: RuntimeException) {
            // Kopf nicht lesbar – vielleicht liefert EXIF trotzdem etwas.
        }
        val exif = try {
            ExifInterface(file)
        } catch (e: IOException) {
            null
        } catch (e: RuntimeException) {
            null
        }
        var w = bounds.outWidth.takeIf { it > 0 } ?: exif?.getAttributeInt(ExifInterface.TAG_IMAGE_WIDTH, 0)?.takeIf { it > 0 }
        var h = bounds.outHeight.takeIf { it > 0 } ?: exif?.getAttributeInt(ExifInterface.TAG_IMAGE_LENGTH, 0)?.takeIf { it > 0 }
        val orientation = exif?.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) ?: ExifInterface.ORIENTATION_NORMAL
        if (orientation in ROTATED) {
            val t = w
            w = h
            h = t
        }
        if (w == null && h == null && exif == null) return null
        val taken = exif?.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL)?.trim()?.let {
            try {
                LocalDateTime.parse(it, exifDate)
            } catch (e: DateTimeParseException) {
                null
            }
        }
        return ImageDetails(
            width = w,
            height = h,
            takenAt = taken,
            cameraMake = exif?.getAttribute(ExifInterface.TAG_MAKE)?.trim()?.takeIf { it.isNotEmpty() },
            cameraModel = exif?.getAttribute(ExifInterface.TAG_MODEL)?.trim()?.takeIf { it.isNotEmpty() },
            hasLocation = exif?.getAttribute(ExifInterface.TAG_GPS_LATITUDE) != null,
        )
    }

    fun media(path: String): MediaDetails? {
        val r = MediaMetadataRetriever()
        return try {
            r.setDataSource(path)
            fun key(k: Int) = r.extractMetadata(k)?.trim()?.takeIf { it.isNotEmpty() }
            val rotation = key(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            var w = key(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
            var h = key(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()
            if (rotation == 90 || rotation == 270) {
                val t = w
                w = h
                h = t
            }
            MediaDetails(
                durationMillis = key(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()?.takeIf { it >= 0 },
                width = w,
                height = h,
                title = key(MediaMetadataRetriever.METADATA_KEY_TITLE),
                artist = key(MediaMetadataRetriever.METADATA_KEY_ARTIST) ?: key(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST),
                album = key(MediaMetadataRetriever.METADATA_KEY_ALBUM),
                hasVideo = key(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes",
                hasAudio = key(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes",
            )
        } catch (e: RuntimeException) {
            // Kein lesbares Medium (IllegalArgumentException) oder Fehler im Medien-Framework.
            null
        } finally {
            try {
                r.release()
            } catch (e: IOException) {
                // bereits freigegeben
            }
        }
    }

    fun pdf(path: String): PdfDetails = try {
        ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
            PdfRenderer(fd).use { PdfDetails(it.pageCount, protected = false) }
        }
    } catch (e: SecurityException) {
        PdfDetails(null, protected = true)
    } catch (e: IOException) {
        PdfDetails(null, protected = false)
    } catch (e: RuntimeException) {
        PdfDetails(null, protected = false)
    }

    private val ROTATED = setOf(
        ExifInterface.ORIENTATION_ROTATE_90,
        ExifInterface.ORIENTATION_ROTATE_270,
        ExifInterface.ORIENTATION_TRANSPOSE,
        ExifInterface.ORIENTATION_TRANSVERSE,
    )
}
