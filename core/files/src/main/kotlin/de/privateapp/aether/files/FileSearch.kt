package de.privateapp.aether.files

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import java.io.File
import java.nio.file.Files
import java.nio.file.LinkOption
import java.text.Normalizer
import java.util.ArrayDeque
import kotlin.coroutines.coroutineContext

/**
 * Gründliche Suche direkt im Dateisystem – findet auch, was der Medienindex von Android nicht kennt (versteckte
 * Ordner, Ordner mit „.nomedia“, gerade erst angelegte Dateien). Langsamer als der Index, deshalb nur auf Wunsch.
 *
 * Durchsucht Ordner in Breite (nahe Treffer zuerst), folgt keinen Verknüpfungen (keine Endlosschleifen), überspringt
 * den Papierkorb und unfertige Dateien von ORBIT sowie die von Android gesperrten Ordner `Android/data` und
 * `Android/obb`. Vergleicht ohne Rücksicht auf Groß-/Kleinschreibung; Umlaute zählen gleich, ob sie als ein Zeichen
 * oder zerlegt (Buchstabe + Pünktchen, z. B. von macOS) gespeichert sind: „münchen“ findet „MÜNCHEN“.
 */
object FileSearch {

    /** Ergebnis-Zwischenstand: bisherige Treffer, durchsuchte Ordner, fertig? */
    data class Progress(val matches: List<FileEntry>, val foldersScanned: Int, val done: Boolean, val limitReached: Boolean)

    fun normalize(text: String): String = Normalizer.normalize(text, Normalizer.Form.NFC).lowercase()

    fun matches(name: String, normalizedQuery: String): Boolean = normalize(name).contains(normalizedQuery)

    /**
     * Sucht [query] in den Namen unter [roots]. Meldet etwa alle 250 Ordner oder bei neuen Treffern einen Zwischenstand.
     * [limit] begrenzt die Trefferzahl (die Suche endet dann mit `limitReached`).
     */
    fun search(roots: List<String>, query: String, includeHidden: Boolean, limit: Int = 1_000): Flow<Progress> = flow {
        val needle = normalize(query.trim())
        if (needle.isEmpty()) {
            emit(Progress(emptyList(), 0, done = true, limitReached = false))
            return@flow
        }
        val matches = ArrayList<FileEntry>()
        val queue = ArrayDeque<File>()
        roots.map { File(Fs.normalize(it)) }.distinctBy { it.path }.forEach { queue.add(it) }
        var scanned = 0
        var lastEmittedMatches = 0
        while (queue.isNotEmpty()) {
            coroutineContext.ensureActive()
            val dir = queue.removeFirst()
            if (DirectoryReader.isSystemProtected(dir.path)) continue
            val children = try {
                dir.listFiles()
            } catch (e: SecurityException) {
                null
            } ?: continue
            scanned++
            children.sortBy { it.name.lowercase() }
            for (child in children) {
                val name = child.name
                if (DirectoryReader.isInternal(name)) continue
                if (!includeHidden && name.startsWith('.')) continue
                val isLink = try {
                    Files.isSymbolicLink(child.toPath())
                } catch (e: Exception) {
                    true
                }
                val isDir = !isLink && try {
                    Files.isDirectory(child.toPath(), LinkOption.NOFOLLOW_LINKS)
                } catch (e: SecurityException) {
                    false
                }
                if (normalize(name).contains(needle)) {
                    DirectoryReader.entryFor(child.path)?.let { matches += it }
                    if (matches.size >= limit) {
                        emit(Progress(matches.toList(), scanned, done = true, limitReached = true))
                        return@flow
                    }
                }
                if (isDir) queue.add(child)
            }
            if (matches.size != lastEmittedMatches || scanned % 250 == 0) {
                lastEmittedMatches = matches.size
                emit(Progress(matches.toList(), scanned, done = false, limitReached = false))
            }
        }
        emit(Progress(matches.toList(), scanned, done = true, limitReached = false))
    }.flowOn(Dispatchers.IO)
}
