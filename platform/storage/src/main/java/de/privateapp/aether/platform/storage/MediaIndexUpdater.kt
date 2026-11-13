package de.privateapp.aether.platform.storage

import android.content.Context
import android.media.MediaScannerConnection
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.atomic.AtomicInteger
import kotlin.coroutines.resume

/**
 * Hält den Medienindex von Android (MediaStore) aktuell, nachdem ORBIT Dateien angelegt, verschoben oder gelöscht
 * hat – sonst zeigen Galerie, Musik-Apps und die Kategorien von ORBIT veraltete Einträge.
 *
 * Android prüft jeden gemeldeten Pfad: Existiert er, wird er (bei Ordnern samt Inhalt) neu eingelesen; existiert er
 * nicht mehr, verschwindet er aus dem Index. Das geschieht im Hintergrund und kann bei großen Ordnern einige
 * Sekunden dauern.
 */
class MediaIndexUpdater(context: Context) {

    private val appContext = context.applicationContext

    /** Meldet [paths] und wartet höchstens [timeoutMillis] auf Android (danach läuft der Abgleich ohne uns weiter). */
    suspend fun update(paths: Collection<String>, timeoutMillis: Long = 15_000L) {
        val unique = paths.filter { it.isNotBlank() }.distinct()
        if (unique.isEmpty()) return
        withTimeoutOrNull(timeoutMillis) {
            suspendCancellableCoroutine { cont ->
                val remaining = AtomicInteger(unique.size)
                try {
                    MediaScannerConnection.scanFile(appContext, unique.toTypedArray(), null) { _, _ ->
                        if (remaining.decrementAndGet() == 0 && cont.isActive) cont.resume(Unit)
                    }
                } catch (e: RuntimeException) {
                    if (cont.isActive) cont.resume(Unit)
                }
            }
        }
    }
}
