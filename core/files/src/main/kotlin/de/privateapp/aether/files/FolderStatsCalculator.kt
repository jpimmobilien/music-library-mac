package de.privateapp.aether.files

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.File

/*
 * Zählt den Inhalt eines Ordners (Dateien, Unterordner, Gesamtgröße) – für „Informationen“ und Bestätigungsdialoge.
 *
 *  - Läuft im Hintergrund (IO) und lässt sich jederzeit abbrechen (Abbruch wird als CancellationException
 *    weitergegeben, wie bei Coroutines üblich).
 *  - Verknüpfungen werden nicht verfolgt (sie zählen als Datei mit 0 Byte), damit nichts doppelt oder endlos zählt.
 *  - Versteckte Dateien zählen mit (sie belegen echten Platz); Dateien von ORBIT selbst nicht.
 *  - Ist ein Unterordner nicht lesbar, ist das Ergebnis eine Untergrenze: `complete = false`.
 */

/** Rekursive Ordnerstatistik. */
object FolderStatsCalculator {

    /** Inhalt von [path]. Für eine Datei: 1 Datei mit ihrer Größe. Fehlt [path]: alles 0 und `complete = false`. */
    suspend fun compute(path: String): FolderStats = withContext(Dispatchers.IO) {
        val root = File(Fs.normalize(path))
        val rootAttrs = Fs.attrs(root) ?: return@withContext FolderStats(0, 0, 0, complete = false)
        if (!rootAttrs.isDirectory) {
            val bytes = if (rootAttrs.isRegularFile) rootAttrs.size() else 0L
            return@withContext FolderStats(files = 1, folders = 0, totalBytes = bytes, complete = true)
        }
        var files = 0
        var folders = 0
        var bytes = 0L
        var complete = true
        val pending = ArrayDeque<File>()
        pending.addLast(root)
        while (pending.isNotEmpty()) {
            coroutineContext.ensureActive()
            val dir = pending.removeLast()
            val children = try {
                dir.listFiles()
            } catch (e: SecurityException) {
                null
            }
            if (children == null) {
                complete = false
                continue
            }
            for (child in children) {
                if (FileNames.isReserved(child.name)) continue
                val attrs = Fs.attrs(child)
                if (attrs == null) {
                    complete = false
                    continue
                }
                when {
                    attrs.isDirectory -> {
                        folders++
                        pending.addLast(child)
                    }
                    attrs.isRegularFile -> {
                        files++
                        bytes += attrs.size()
                    }
                    else -> files++
                }
            }
        }
        FolderStats(files, folders, bytes, complete)
    }
}
