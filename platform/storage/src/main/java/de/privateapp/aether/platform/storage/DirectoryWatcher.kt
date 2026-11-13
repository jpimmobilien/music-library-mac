package de.privateapp.aether.platform.storage

import android.os.FileObserver
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.conflate
import java.io.File

/**
 * Meldet Änderungen in einem Ordner (neue, gelöschte, umbenannte oder fertig geschriebene Dateien), damit eine
 * geöffnete Ordneransicht sich selbst aktualisiert – auch wenn eine andere App etwas ändert.
 *
 * Android liefert diese Meldungen über das Dateisystem (inotify). Auf dem gemeinsamen Speicher kommen sie seit
 * Android 11 nicht für jede Änderung jeder App zuverlässig an; ORBIT lädt deshalb zusätzlich nach eigenen Vorgängen
 * und beim Zurückkehren in die App neu.
 */
object DirectoryWatcher {

    private const val MASK = FileObserver.CREATE or FileObserver.DELETE or FileObserver.MOVED_FROM or
        FileObserver.MOVED_TO or FileObserver.CLOSE_WRITE or FileObserver.DELETE_SELF or FileObserver.MOVE_SELF

    fun changes(path: String): Flow<Unit> = callbackFlow {
        val observer = object : FileObserver(File(path), MASK) {
            override fun onEvent(event: Int, name: String?) {
                trySend(Unit)
            }
        }
        observer.startWatching()
        awaitClose { observer.stopWatching() }
    }.conflate()
}
