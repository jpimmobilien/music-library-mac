package de.privateapp.aether.files

import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.nio.file.Files
import java.util.Properties
import java.util.UUID
import java.nio.file.FileAlreadyExistsException as NioFileAlreadyExistsException

/*
 * Papierkorb von ORBIT – je Speicher ein eigener, versteckter Ordner direkt in der Speicherwurzel:
 *
 *   <Speicherwurzel>/.AetherTrash/
 *       .nomedia                     → Galerie- und Musik-Apps zeigen den Inhalt nicht an
 *       <id>/meta.properties         → ursprünglicher Pfad, Name, Löschzeit, Größe, Ordner ja/nein (UTF-8)
 *       <id>/files/<ursprünglicher Name>
 *
 * Warum so:
 *  - In den Papierkorb legen ist ein atomares Umbenennen auf DEMSELBEN Speicher. Es wird nie kopiert: Das wäre bei
 *    großen Ordnern langsam, bräuchte freien Platz und könnte bei einem Abbruch Daten doppelt oder halb hinterlassen.
 *    Geht das Umbenennen nicht, meldet ORBIT ehrlich „Papierkorb nicht verfügbar“ – und löscht NICHT ersatzweise.
 *  - Die Metadaten liegen neben dem Objekt. Damit bleibt der Papierkorb auch nach einer Neuinstallation von ORBIT
 *    oder mit der SD-Karte in einem anderen Telefon wiederherstellbar.
 *  - Der Papierkorb löscht nie von selbst. Leeren und automatisches Aufräumen entscheidet die Oberfläche.
 *  - Unvollständige Einträge (z. B. nach einem Absturz mitten im Umbenennen) werden beim Auflisten übergangen, nicht
 *    gelöscht.
 */

/** Papierkorb je Speicher. [clock] liefert die Löschzeit (für Tests austauschbar). */
class TrashStore(
    private val layout: VolumeLayout,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    companion object {
        /** Name des Papierkorb-Ordners in jeder Speicherwurzel. Für Nutzer reserviert ([NameProblem.RESERVED]). */
        const val DIR_NAME = ".AetherTrash"

        internal const val META_FILE = "meta.properties"
        internal const val FILES_DIR = "files"
        private const val NOMEDIA = ".nomedia"

        private const val KEY_ORIGINAL_PATH = "originalPath"
        private const val KEY_NAME = "name"
        private const val KEY_DELETED_AT = "deletedAt"
        private const val KEY_SIZE = "size"
        private const val KEY_IS_DIRECTORY = "isDirectory"
    }

    /** Für Tests: das atomare Umbenennen, über das alles in den Papierkorb gelangt. */
    internal var atomicMove: (File, File) -> Unit = { from, to -> Fs.atomicMove(from, to) }

    /** Ort eines vorhandenen Papierkorb-Eintrags auf dem Speicher. */
    internal class Located(val itemDir: File, val stored: File)

    /** Papierkorb-Ordner des Speichers mit der Wurzel [volumeRoot]. */
    fun trashDirFor(volumeRoot: String): String = File(Fs.normalize(volumeRoot), DIR_NAME).path

    /** Alle Einträge der Papierkörbe von [volumeRoots], neueste zuerst. Unvollständige Einträge werden übergangen. */
    fun list(volumeRoots: List<String>): List<TrashedItem> {
        val items = ArrayList<TrashedItem>()
        for (root in volumeRoots.map(Fs::normalize).distinct()) {
            val itemDirs = try {
                File(trashDirFor(root)).listFiles()
            } catch (e: SecurityException) {
                null
            } ?: continue
            for (itemDir in itemDirs) {
                val attrs = Fs.attrs(itemDir) ?: continue
                if (!attrs.isDirectory) continue
                read(root, itemDir)?.let(items::add)
            }
        }
        return items.sortedWith(compareByDescending<TrashedItem> { it.deletedAtMillis }.thenByDescending { it.id })
    }

    /**
     * Legt [source] in den Papierkorb seines Speichers – ausschließlich durch atomares Umbenennen. Wirft
     * [TrashUnavailableException], wenn der Speicher unbekannt ist oder der Papierkorb nicht angelegt werden kann, und
     * die [IOException] des Umbenennens (z. B. anderes Dateisystem), wenn es scheitert. In beiden Fällen bleibt
     * [source] unverändert, und es bleibt kein halber Eintrag zurück.
     */
    internal fun moveIn(source: File, isDirectory: Boolean, sizeBytes: Long): TrashedItem {
        val root = layout.volumeRootOf(source.path)?.let(Fs::normalize)
            ?: throw TrashUnavailableException("Speicher von ${source.path} unbekannt")
        val trashDir = File(trashDirFor(root))
        prepareTrashDir(trashDir)
        val now = clock()
        val itemDir = createItemDir(trashDir, now)
        try {
            val meta = Properties().apply {
                setProperty(KEY_ORIGINAL_PATH, source.path)
                setProperty(KEY_NAME, source.name)
                setProperty(KEY_DELETED_AT, now.toString())
                setProperty(KEY_SIZE, sizeBytes.toString())
                setProperty(KEY_IS_DIRECTORY, isDirectory.toString())
            }
            writeMeta(File(itemDir, META_FILE), meta)
            val filesDir = File(itemDir, FILES_DIR)
            Files.createDirectory(filesDir.toPath())
            val stored = File(filesDir, source.name)
            atomicMove(source, stored)
            return TrashedItem(
                id = itemDir.name,
                name = source.name,
                originalPath = source.path,
                deletedAtMillis = now,
                sizeBytes = sizeBytes,
                isDirectory = isDirectory,
                storedPath = stored.path,
                volumeRoot = root,
            )
        } catch (e: IOException) {
            removeShell(itemDir)
            throw e
        }
    }

    /** Prüft einen (evtl. veralteten) [TrashedItem] gegen den Speicher. `null`, wenn er so nicht (mehr) existiert. */
    internal fun locate(item: TrashedItem): Located? {
        val id = item.id
        if (id.isEmpty() || id == "." || id == ".." || '/' in id) return null
        val root = Fs.normalize(item.volumeRoot)
        val itemDir = File(trashDirFor(root), id)
        val actualRoot = layout.volumeRootOf(itemDir.path)?.let(Fs::normalize)
        if (actualRoot != root) return null
        val stored = File(item.storedPath)
        val storedName = stored.name
        if (storedName.isEmpty() || storedName == "." || storedName == "..") return null
        if (Fs.normalize(stored.parent ?: return null) != File(itemDir, FILES_DIR).path) return null
        if (!Fs.exists(itemDir) || !Fs.exists(stored)) return null
        return Located(itemDir, stored)
    }

    /**
     * Entfernt die Hülle eines Eintrags (Metadaten, leerer „files“-Ordner, Eintragsordner) – aber nur, was leer bzw.
     * von ORBIT ist. Liegt noch ein Objekt darin, bleibt alles stehen.
     */
    internal fun removeShell(itemDir: File): Boolean {
        val filesDir = File(itemDir, FILES_DIR)
        if (Fs.exists(filesDir)) {
            val remaining = filesDir.list()
            if (remaining == null || remaining.isNotEmpty()) return false
            if (!filesDir.delete()) return false
        }
        File(itemDir, META_FILE).delete()
        return itemDir.delete() || !Fs.exists(itemDir)
    }

    private fun read(volumeRoot: String, itemDir: File): TrashedItem? {
        val meta = readMeta(File(itemDir, META_FILE)) ?: return null
        val originalPath = meta.getProperty(KEY_ORIGINAL_PATH)?.takeIf { it.startsWith("/") } ?: return null
        val stored = storedObject(File(itemDir, FILES_DIR), meta.getProperty(KEY_NAME)) ?: return null
        val attrs = Fs.attrs(stored) ?: return null
        val isDirectory = attrs.isDirectory
        val size = meta.getProperty(KEY_SIZE)?.toLongOrNull()?.takeIf { it >= 0 }
            ?: if (isDirectory) Fs.treeBytesBlocking(stored) else attrs.size()
        val deletedAt = meta.getProperty(KEY_DELETED_AT)?.toLongOrNull() ?: itemDir.lastModified()
        return TrashedItem(
            id = itemDir.name,
            name = stored.name,
            originalPath = originalPath,
            deletedAtMillis = deletedAt,
            sizeBytes = size,
            isDirectory = isDirectory,
            storedPath = stored.path,
            volumeRoot = volumeRoot,
        )
    }

    /** Das gespeicherte Objekt: nach Namen aus den Metadaten, sonst das einzige Objekt im „files“-Ordner. */
    private fun storedObject(filesDir: File, name: String?): File? {
        if (name != null && name.isNotEmpty() && name != "." && name != ".." && '/' !in name) {
            val byName = File(filesDir, name)
            if (Fs.exists(byName)) return byName
        }
        val children = filesDir.listFiles() ?: return null
        return children.singleOrNull()
    }

    private fun prepareTrashDir(trashDir: File) {
        val attrs = Fs.attrs(trashDir)
        if (attrs == null) {
            try {
                Files.createDirectories(trashDir.toPath())
            } catch (e: IOException) {
                throw TrashUnavailableException("Papierkorb kann nicht angelegt werden: ${e.message}", e)
            }
        } else if (!attrs.isDirectory) {
            throw TrashUnavailableException("${trashDir.path} ist kein Ordner")
        }
        val nomedia = File(trashDir, NOMEDIA)
        if (!Fs.exists(nomedia)) {
            try {
                nomedia.createNewFile()
            } catch (e: IOException) {
                // Ohne .nomedia funktioniert der Papierkorb trotzdem; Galerie-Apps könnten den Inhalt dann sehen.
            }
        }
    }

    private fun createItemDir(trashDir: File, now: Long): File {
        repeat(8) {
            val id = "$now-" + UUID.randomUUID().toString().replace("-", "").take(8)
            val dir = File(trashDir, id)
            try {
                Files.createDirectory(dir.toPath())
                return dir
            } catch (e: NioFileAlreadyExistsException) {
                // anderer Zufallswert
            } catch (e: IOException) {
                throw TrashUnavailableException("Papierkorb-Eintrag kann nicht angelegt werden: ${e.message}", e)
            }
        }
        throw TrashUnavailableException("Kein freier Papierkorb-Eintrag")
    }

    private fun writeMeta(file: File, meta: Properties) {
        FileOutputStream(file).use { out ->
            val writer = OutputStreamWriter(out, Charsets.UTF_8)
            meta.store(writer, null)
            writer.flush()
            out.syncToDisk()
        }
    }

    private fun readMeta(file: File): Properties? = try {
        FileInputStream(file).use { input ->
            Properties().apply { load(InputStreamReader(input, Charsets.UTF_8)) }
        }
    } catch (e: IOException) {
        null
    } catch (e: IllegalArgumentException) {
        null // fehlerhafte \u-Folge in einer beschädigten Datei
    } catch (e: SecurityException) {
        null
    }
}

/** Der Papierkorb kann auf diesem Speicher nicht verwendet werden. */
internal class TrashUnavailableException(message: String, cause: Throwable? = null) : IOException(message, cause)
