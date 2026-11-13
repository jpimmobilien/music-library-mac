package de.privateapp.aether.files

import java.io.File

/*
 * Liest Ordnerinhalte für die Anzeige.
 *
 *  - Eigene Dateien von ORBIT (Zwischendateien „*.aether-part“, der Papierkorb „.AetherTrash“) erscheinen nie und
 *    zählen auch nicht als „ausgeblendet“.
 *  - Versteckte Einträge (Name beginnt mit „.“) werden auf Wunsch ausgeblendet und gezählt.
 *  - `Android/data` und `Android/obb` sind ab Android 11 für jede App gesperrt – auch mit „Zugriff auf alle Dateien“.
 *    Das wird als [Listing.AccessDenied] mit `protectedBySystem = true` gemeldet, damit die Oberfläche es erklären
 *    kann, statt einen leeren Ordner zu zeigen.
 *  - Verknüpfungen werden für die Anzeige aufgelöst (ein Link auf einen Ordner erscheint als Ordner), nie aber beim
 *    Zählen, Kopieren oder Löschen.
 */

/** Ordner auflisten und einzelne Einträge lesen. */
object DirectoryReader {

    private val PROTECTED = Regex(
        """^/(?:storage/(?:emulated/\d+|self/primary|[0-9a-f]{4}-[0-9a-f]{4}|[0-9a-f]{16})|sdcard|mnt/sdcard)""" +
            """/android/(?:data|obb)(?:/.*)?$""",
        RegexOption.IGNORE_CASE,
    )

    /** Name gehört ORBIT selbst und wird nie angezeigt. */
    fun isInternal(name: String): Boolean = FileNames.isReserved(name)

    /**
     * Inhalt von [dirPath], sortiert nach Namen (Ordner zuerst). Die Oberfläche sortiert danach selbst neu.
     * [Listing.Entries.hiddenCount] zählt die ausgeblendeten versteckten Einträge (0, wenn [includeHidden]).
     */
    fun list(dirPath: String, includeHidden: Boolean): Listing {
        val path = Fs.normalize(dirPath)
        if (isSystemProtected(path)) return Listing.AccessDenied(protectedBySystem = true)
        val dir = File(path)
        val directory = try {
            entryOf(dir)
        } catch (e: SecurityException) {
            return Listing.AccessDenied(protectedBySystem = false)
        } ?: return Listing.NotFound
        if (!directory.isDirectory) return Listing.NotADirectory
        val children = try {
            dir.listFiles()
        } catch (e: SecurityException) {
            null
        } ?: return Listing.AccessDenied(protectedBySystem = false)

        var hidden = 0
        val entries = ArrayList<FileEntry>(children.size)
        for (child in children) {
            val name = child.name
            if (isInternal(name)) continue
            if (!includeHidden && name.startsWith('.')) {
                hidden++
                continue
            }
            // Zwischen Auflisten und Lesen entfernte Einträge werden einfach übergangen.
            val entry = try {
                entryOf(child)
            } catch (e: SecurityException) {
                null
            } ?: continue
            entries += entry
        }
        return Listing.Entries(directory, FileSorting.sorted(entries, SortOrder()), hidden)
    }

    /** Eintrag für [path] oder `null`, wenn es ihn nicht (mehr) gibt oder er nicht lesbar ist. */
    fun entryFor(path: String): FileEntry? = try {
        entryOf(File(Fs.normalize(path)))
    } catch (e: SecurityException) {
        null
    }

    /** Anzahl sichtbarer Einträge in [dirPath] (ohne die von ORBIT) oder `null`, wenn er nicht lesbar ist. */
    fun childCount(dirPath: String, includeHidden: Boolean): Int? {
        val path = Fs.normalize(dirPath)
        if (isSystemProtected(path)) return null
        val names = try {
            File(path).list()
        } catch (e: SecurityException) {
            null
        } ?: return null
        return names.count { !isInternal(it) && (includeHidden || !it.startsWith('.')) }
    }

    /** `Android/data` oder `Android/obb` (oder darin) direkt unter einer Speicherwurzel. */
    internal fun isSystemProtected(path: String): Boolean = PROTECTED.matches(Fs.normalize(path))

    internal fun entryOf(file: File): FileEntry? {
        val attrs = Fs.displayAttrs(file) ?: return null
        val name = file.name
        val isDirectory = attrs.isDirectory
        val extension = if (isDirectory) "" else FileTypes.extensionOf(name)
        val mimeType = if (isDirectory) null else FileTypes.mimeTypeOf(extension)
        return FileEntry(
            path = file.path,
            name = name,
            isDirectory = isDirectory,
            sizeBytes = if (isDirectory) 0 else attrs.size(),
            modifiedMillis = Fs.modifiedMillis(attrs),
            isHidden = name.startsWith('.'),
            kind = FileTypes.kindOf(name, isDirectory, mimeType),
            extension = extension,
            mimeType = mimeType,
            readable = file.canRead(),
            writable = file.canWrite(),
        )
    }
}
