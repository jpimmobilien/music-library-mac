package de.privateapp.aether.files

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.InvalidPathException
import java.nio.file.LinkOption
import java.nio.file.Paths
import java.nio.file.StandardCopyOption
import java.nio.file.attribute.BasicFileAttributes
import java.util.Locale
import java.nio.file.FileAlreadyExistsException as NioFileAlreadyExistsException

/*
 * Kleine Dateisystem-Helfer, die überall gleich funktionieren müssen (JVM und Android ab API 31).
 *
 * Grundsätze:
 *  - Verknüpfungen (symbolische Links) werden nie verfolgt, wenn etwas gezählt, kopiert oder gelöscht wird –
 *    sonst könnte ein Link auf einen anderen Ordner dessen Inhalt mitlöschen.
 *  - Umbenennen geschieht immer als echtes, atomares `rename()` (ATOMIC_MOVE). Die Standardvariante von
 *    `Files.move` würde bei verschiedenen Dateisystemen stillschweigend kopieren und löschen – ohne Prüfung.
 */
internal object Fs {

    /** Reserve, die beim Prüfen des freien Speichers zusätzlich frei bleiben muss. */
    const val SPACE_RESERVE_BYTES = 1024L * 1024L

    fun attrs(file: File): BasicFileAttributes? = try {
        Files.readAttributes(file.toPath(), BasicFileAttributes::class.java, LinkOption.NOFOLLOW_LINKS)
    } catch (e: IOException) {
        null
    } catch (e: SecurityException) {
        null
    } catch (e: InvalidPathException) {
        null
    }

    /** Wie [attrs], folgt aber einer Verknüpfung zu ihrem Ziel (für die Anzeige). Fehlt das Ziel: die Verknüpfung. */
    fun displayAttrs(file: File): BasicFileAttributes? {
        val own = attrs(file) ?: return null
        if (!own.isSymbolicLink) return own
        return try {
            Files.readAttributes(file.toPath(), BasicFileAttributes::class.java)
        } catch (e: IOException) {
            own
        } catch (e: SecurityException) {
            own
        }
    }

    fun exists(file: File): Boolean = attrs(file) != null

    fun modifiedMillis(attrs: BasicFileAttributes): Long = attrs.lastModifiedTime().toMillis()

    /** Absoluter Pfad ohne „.“, „..“, doppelte und abschließende Schrägstriche (Verknüpfungen bleiben stehen). */
    fun normalize(path: String): String = try {
        Paths.get(path).toAbsolutePath().normalize().toString()
    } catch (e: InvalidPathException) {
        File(path).absolutePath
    }

    /** [path] ist [ancestor] selbst oder liegt darin. Groß-/Kleinschreibung zählt nicht (wie im gemeinsamen Speicher). */
    fun isSameOrInside(path: String, ancestor: String): Boolean {
        if (isPrefixPath(normalize(path).lowercase(Locale.ROOT), normalize(ancestor).lowercase(Locale.ROOT))) return true
        val canonicalPath = canonical(path) ?: return false
        val canonicalAncestor = canonical(ancestor) ?: return false
        return isPrefixPath(canonicalPath, canonicalAncestor)
    }

    private fun isPrefixPath(path: String, ancestor: String): Boolean =
        path == ancestor || path.startsWith(if (ancestor.endsWith("/")) ancestor else "$ancestor/")

    private fun canonical(path: String): String? = try {
        File(path).canonicalPath.lowercase(Locale.ROOT)
    } catch (e: IOException) {
        null
    } catch (e: SecurityException) {
        null
    }

    /** Dieselben Ordner – auch wenn sie über verschiedene Pfade erreicht werden (z. B. `/sdcard` und `/storage/…`). */
    fun sameDirectory(a: File?, b: File?): Boolean {
        if (a == null || b == null) return false
        if (normalize(a.path) == normalize(b.path)) return true
        return try {
            Files.isSameFile(a.toPath(), b.toPath())
        } catch (e: IOException) {
            false
        } catch (e: SecurityException) {
            false
        }
    }

    fun isSameFile(a: File, b: File): Boolean = try {
        Files.isSameFile(a.toPath(), b.toPath())
    } catch (e: IOException) {
        false
    } catch (e: SecurityException) {
        false
    }

    /** Atomar umbenennen, aber nie ein vorhandenes Ziel überschreiben. */
    fun renameNoReplace(from: File, to: File) {
        if (exists(to)) throw NioFileAlreadyExistsException(to.path)
        atomicMove(from, to)
    }

    /** Atomares `rename()`: ersetzt ein vorhandenes Ziel (Datei) in einem Schritt, kopiert nie. */
    fun atomicMove(from: File, to: File) {
        Files.move(from.toPath(), to.toPath(), StandardCopyOption.ATOMIC_MOVE)
    }

    /** Der Fehler bedeutet „anderes Dateisystem“ (EXDEV) – Umbenennen geht dann grundsätzlich nicht. */
    fun isCrossDevice(e: IOException): Boolean {
        if (e is AtomicMoveNotSupportedException) return true
        val message = e.message ?: return false
        return "EXDEV" in message || message.contains("cross-device", ignoreCase = true)
    }

    /** Freier Name für eine Zwischendatei „<Name>.aether-part“ in [dir] (gekürzt, falls der Name sehr lang ist). */
    fun tempFileIn(dir: File, finalName: String): File {
        var n = 1
        while (true) {
            val marker = if (n == 1) "" else "~$n"
            val room = FileNames.MAX_BYTES - FileNames.utf8Length(marker + FileNames.TEMP_SUFFIX)
            val candidate = File(dir, FileNames.fitToBytes(finalName, room) + marker + FileNames.TEMP_SUFFIX)
            if (!exists(candidate)) return candidate
            n++
        }
    }

    /**
     * Ändert nur die Schreibweise eines Namens („foto.jpg“ → „Foto.jpg“). Auf Speichern ohne Unterscheidung von
     * Groß-/Kleinschreibung geht das nur über einen Zwischennamen. Nie wird dabei etwas überschrieben: Gibt es (auf einem
     * Speicher MIT Unterscheidung) bereits einen ANDEREN Eintrag mit der gewünschten Schreibweise, wird
     * FileAlreadyExistsException geworfen und nichts verändert. Schlägt der zweite Schritt fehl, wird der ursprüngliche
     * Name wiederhergestellt.
     */
    fun renameCaseOnly(file: File, newName: String): File {
        val parent = file.parentFile ?: throw IOException("Kein übergeordneter Ordner: ${file.path}")
        val target = File(parent, newName)
        if (exists(target) && !isSameFile(file, target)) throw NioFileAlreadyExistsException(target.path)
        var n = 1
        var intermediate: File
        do {
            val marker = if (n == 1) "~aether" else "~aether$n"
            intermediate = File(parent, FileNames.fitToBytes(newName, FileNames.MAX_BYTES - marker.length) + marker)
            n++
        } while (exists(intermediate))
        atomicMove(file, intermediate)
        try {
            // Ohne ATOMIC_MOVE/REPLACE_EXISTING: wirft, statt einen inzwischen vorhandenen Eintrag zu ersetzen.
            // Im selben Ordner ist das ein einfaches rename() – es wird nie kopiert.
            Files.move(intermediate.toPath(), target.toPath())
        } catch (e: IOException) {
            try {
                atomicMove(intermediate, file)
            } catch (ignored: IOException) {
                // Der Zwischenname bleibt sichtbar stehen – nichts geht verloren.
            }
            throw e
        }
        return target
    }

    /**
     * Nach einem Ersetzen die Schreibweise der neuen Fassung übernehmen – nur wenn das gefahrlos geht: Liegt bereits ein
     * anderer Eintrag mit genau dieser Schreibweise daneben, bleibt der Name, wie er ist.
     */
    fun fixCaseBestEffort(file: File, desiredName: String): File {
        if (file.name == desiredName) return file
        val parent = file.parentFile ?: return file
        val desired = File(parent, desiredName)
        if (exists(desired) && !isSameFile(file, desired)) return file
        return try {
            renameCaseOnly(file, desiredName)
        } catch (e: IOException) {
            file
        }
    }

    /** Anzahl normaler Dateien unter [file] (ohne Verknüpfungen zu folgen, ohne Dateien von ORBIT) – blockierend. */
    fun countFilesBlocking(file: File): Int {
        val attrs = attrs(file) ?: return 0
        if (!attrs.isDirectory) return if (attrs.isRegularFile && !FileNames.isReserved(file.name)) 1 else 0
        var count = 0
        file.listFiles()?.forEach { child -> if (!FileNames.isReserved(child.name)) count += countFilesBlocking(child) }
        return count
    }

    /** Änderungszeit setzen, soweit das Dateisystem es erlaubt (Android-FUSE lehnt es teils ab). */
    fun setModified(file: File, millis: Long) {
        if (millis <= 0) return
        try {
            file.setLastModified(millis)
        } catch (e: SecurityException) {
            // bewusst ignoriert: Änderungszeit ist „nach Möglichkeit“
        }
    }

    /** Löscht [file] samt Inhalt, ohne Verknüpfungen zu folgen. `true` = danach nicht mehr vorhanden. */
    fun deleteRecursively(file: File): Boolean {
        val attrs = attrs(file) ?: return true
        if (attrs.isDirectory) file.listFiles()?.forEach { deleteRecursively(it) }
        return try {
            Files.deleteIfExists(file.toPath())
            true
        } catch (e: IOException) {
            false
        } catch (e: SecurityException) {
            false
        }
    }

    /** Größe eines Baums in Byte, blockierend und ohne Verknüpfungen zu folgen (nur für seltene Fälle). */
    fun treeBytesBlocking(file: File): Long {
        val attrs = attrs(file) ?: return 0
        if (!attrs.isDirectory) return if (attrs.isRegularFile) attrs.size() else 0
        return file.listFiles()?.sumOf { treeBytesBlocking(it) } ?: 0
    }

    fun isVolumeRoot(layout: VolumeLayout, path: String): Boolean {
        val root = layout.volumeRootOf(path) ?: return false
        return normalize(root) == normalize(path)
    }

    /** Liegt im Papierkorb-Ordner von ORBIT (irgendwo im Pfad). */
    fun isInsideTrash(path: String): Boolean =
        normalize(path).split('/').any { it.equals(TrashStore.DIR_NAME, ignoreCase = true) }
}

/** Gepufferte Daten auf das Speichermedium schreiben (fsync), bevor umbenannt wird. */
internal fun FileOutputStream.syncToDisk() {
    flush()
    channel.force(true)
}
