package de.privateapp.aether.platform.storage

import android.content.ContentResolver
import android.content.Context
import android.database.ContentObserver
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import de.privateapp.aether.files.FileEntry
import de.privateapp.aether.files.FileKind
import de.privateapp.aether.files.FileTypes
import de.privateapp.aether.files.TrashStore
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.withContext
import java.io.File

/** Anzahl und Gesamtgröße einer Kategorie laut Medienindex. */
data class CategorySummary(val category: MediaCategory, val count: Int, val totalBytes: Long)

/**
 * Inhalt einer Kategorie. Bei sehr vielen Dateien werden die [limit] neuesten geladen ([total] nennt dann die
 * tatsächliche Anzahl) – die Oberfläche sagt das ausdrücklich.
 */
data class CategoryPage(
    val category: MediaCategory,
    val entries: List<FileEntry>,
    val total: Int,
    val limit: Int,
) {
    val isLimited: Boolean get() = total > entries.size
}

/**
 * Kategorien und Suche über den Medienindex von Android (MediaStore).
 *
 * Mit „Zugriff auf alle Dateien“ enthält der Index sämtliche Dateien des gemeinsamen Speichers und eingebundener
 * SD-Karten/USB-Speicher – nicht nur Medien. Er wird von Android gepflegt und ist deshalb schnell, kann aber nach
 * Änderungen durch andere Apps kurz hinterherhinken. Nicht enthalten sind versteckte Ordner (Name beginnt mit „.“)
 * und Ordner, die Android nicht einliest; dafür gibt es die Suche im Dateisystem.
 */
class MediaIndex(
    context: Context,
    private val io: CoroutineDispatcher = Dispatchers.IO,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val resolver: ContentResolver = context.applicationContext.contentResolver

    private val filesUri: Uri = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)
    private val audioUri: Uri = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)

    /** Meldet Änderungen im Index (neue, geänderte, gelöschte Dateien) – zusammengefasst, nie mehrfach gestaut. */
    fun changes(): Flow<Unit> = callbackFlow {
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                trySend(Unit)
            }
        }
        try {
            resolver.registerContentObserver(filesUri, true, observer)
        } catch (e: SecurityException) {
            close()
            return@callbackFlow
        }
        awaitClose { resolver.unregisterContentObserver(observer) }
    }.conflate()

    suspend fun summary(category: MediaCategory): CategorySummary = withContext(io) {
        val q = queryFor(category)
        var count = 0
        var bytes = 0L
        query(q.uri, arrayOf(MediaStore.MediaColumns.DATA, MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.SIZE), q.selection, q.args, null, null)
            ?.use { c ->
                val data = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
                val name = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                val size = c.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
                while (c.moveToNext()) {
                    if (count % 512 == 0) ensureActive()
                    val path = c.getString(data) ?: continue
                    if (!q.accepts(path, c.getString(name) ?: path.substringAfterLast('/'))) continue
                    count++
                    bytes += c.getLong(size).coerceAtLeast(0)
                }
            }
        CategorySummary(category, count, bytes)
    }

    /** Dateien einer Kategorie, neueste zuerst (die Oberfläche sortiert anschließend nach Wahl des Nutzers). */
    suspend fun list(category: MediaCategory, limit: Int = DEFAULT_LIMIT): CategoryPage = withContext(io) {
        val q = queryFor(category)
        val entries = ArrayList<FileEntry>()
        var total = 0
        query(q.uri, ROW_PROJECTION, q.selection, q.args, "${MediaStore.MediaColumns.DATE_MODIFIED} DESC", null)?.use { c ->
            val cols = Columns(c)
            while (c.moveToNext()) {
                if (total % 256 == 0) ensureActive()
                val row = cols.row(c) ?: continue
                if (!q.accepts(row.path, row.name)) continue
                total++
                if (entries.size < limit) row.toEntry()?.let { entries += it }
            }
        }
        CategoryPage(category, entries, total, limit)
    }

    /**
     * Suche nach Namen (enthält [text], Groß-/Kleinschreibung egal) in Dateien und Ordnern. Treffer, deren Name mit
     * dem Suchtext beginnt, stehen vorn; danach die zuletzt geänderten.
     */
    suspend fun search(text: String, limit: Int = 500): List<FileEntry> = withContext(io) {
        val needle = text.trim()
        if (needle.isEmpty()) return@withContext emptyList()
        // SQLite vergleicht nur ASCII ohne Rücksicht auf Groß-/Kleinschreibung; für „Ä/ä“ usw. wird zusätzlich mit
        // klein-, groß- und am Anfang großgeschriebenem Suchtext gefragt. Die endgültige Prüfung folgt unten.
        val variants = listOf(needle, needle.lowercase(), needle.uppercase(), needle.replaceFirstChar { it.titlecase() }).distinct()
        val selection = buildString {
            append("(")
            append(variants.joinToString(" OR ") { "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ? ESCAPE '\\'" })
            append(") AND ")
            append(EXCLUSIONS)
        }
        val args = variants.map { "%${escapeLike(it)}%" } + EXCLUSION_ARGS
        val found = ArrayList<FileEntry>()
        query(filesUri, ROW_PROJECTION, selection, args.toTypedArray(), "${MediaStore.MediaColumns.DATE_MODIFIED} DESC", limit * 2)?.use { c ->
            val cols = Columns(c)
            while (c.moveToNext() && found.size < limit) {
                ensureActive()
                val row = cols.row(c) ?: continue
                if (isHiddenPath(row.path) || !row.name.contains(needle, ignoreCase = true)) continue
                row.toEntry(allowDirectories = true)?.let { found += it }
            }
        }
        found.sortedWith(compareByDescending<FileEntry> { it.name.startsWith(needle, ignoreCase = true) })
    }

    // -------------------------------------------------------------------------------------------------------------

    private class CategoryQuery(
        val uri: Uri,
        val selection: String,
        val args: Array<String>,
        /** Abschließende Prüfung in Kotlin (Dateiart wie im restlichen ORBIT, versteckte Pfade ausgeschlossen). */
        val kinds: Set<FileKind>?,
    ) {
        fun accepts(path: String, name: String): Boolean {
            if (isHiddenPath(path)) return false
            return kinds == null || FileTypes.kindOf(name, isDirectory = false, mimeType = null) in kinds
        }
    }

    private fun queryFor(category: MediaCategory): CategoryQuery {
        val type = MediaStore.Files.FileColumns.MEDIA_TYPE
        val notFolder = "${MediaStore.MediaColumns.MIME_TYPE} IS NOT NULL"
        fun byExtension(kind: FileKind): CategoryQuery {
            val exts = FileTypes.extensionsOf(kind).sorted()
            val likes = exts.joinToString(" OR ") { "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?" }
            return CategoryQuery(filesUri, "($likes) AND $EXCLUSIONS", (exts.map { "%.$it" } + EXCLUSION_ARGS).toTypedArray(), setOf(kind))
        }
        return when (category) {
            MediaCategory.IMAGES -> CategoryQuery(filesUri, "$type = ${MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE} AND $EXCLUSIONS", EXCLUSION_ARGS.toTypedArray(), null)
            MediaCategory.VIDEOS -> CategoryQuery(filesUri, "$type = ${MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO} AND $EXCLUSIONS", EXCLUSION_ARGS.toTypedArray(), null)
            MediaCategory.MUSIC -> CategoryQuery(audioUri, "${MediaStore.Audio.AudioColumns.IS_MUSIC} != 0 AND $EXCLUSIONS", EXCLUSION_ARGS.toTypedArray(), null)
            MediaCategory.AUDIO -> CategoryQuery(audioUri, "${MediaStore.Audio.AudioColumns.IS_MUSIC} = 0 AND $EXCLUSIONS", EXCLUSION_ARGS.toTypedArray(), null)
            MediaCategory.DOCUMENTS -> byExtension(FileKind.DOCUMENT)
            MediaCategory.PDF -> byExtension(FileKind.PDF)
            MediaCategory.TEXT -> byExtension(FileKind.TEXT)
            MediaCategory.ARCHIVES -> byExtension(FileKind.ARCHIVE)
            MediaCategory.APKS -> byExtension(FileKind.APK)
            MediaCategory.DOWNLOADS -> CategoryQuery(
                filesUri,
                "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ? AND $notFolder AND $EXCLUSIONS",
                (listOf("Download/%") + EXCLUSION_ARGS).toTypedArray(),
                null,
            )
            MediaCategory.RECENT -> CategoryQuery(
                filesUri,
                "${MediaStore.MediaColumns.DATE_ADDED} >= ? AND $notFolder AND $EXCLUSIONS",
                (listOf(((clock() - RECENT_WINDOW_MILLIS) / 1000).toString()) + EXCLUSION_ARGS).toTypedArray(),
                null,
            )
        }
    }

    private fun query(uri: Uri, projection: Array<String>, selection: String, args: Array<String>, sort: String?, limit: Int?): Cursor? {
        val bundle = Bundle().apply {
            putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
            putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, args)
            if (sort != null) putString(ContentResolver.QUERY_ARG_SQL_SORT_ORDER, sort)
            if (limit != null) putInt(ContentResolver.QUERY_ARG_LIMIT, limit)
        }
        return try {
            resolver.query(uri, projection, bundle, null)
        } catch (e: SecurityException) {
            null
        } catch (e: IllegalArgumentException) {
            null
        } catch (e: IllegalStateException) {
            null
        }
    }

    private class Row(val path: String, val name: String, val size: Long, val modifiedMillis: Long, val mime: String?) {
        fun toEntry(allowDirectories: Boolean = false): FileEntry? {
            val file = File(path)
            // Ordner tragen im Index keinen Dateityp; ob es wirklich (noch) ein Ordner ist, sagt das Dateisystem.
            val isDirectory = mime == null && file.isDirectory
            if (isDirectory && !allowDirectories) return null
            val ext = if (isDirectory) "" else FileTypes.extensionOf(name)
            return FileEntry(
                path = path,
                name = name,
                isDirectory = isDirectory,
                sizeBytes = if (isDirectory) 0 else size.coerceAtLeast(0),
                modifiedMillis = modifiedMillis,
                isHidden = name.startsWith('.'),
                kind = FileTypes.kindOf(name, isDirectory, mime),
                extension = ext,
                mimeType = if (isDirectory) null else (mime ?: FileTypes.mimeTypeOf(ext)),
                readable = true,
                writable = true,
            )
        }
    }

    private class Columns(c: Cursor) {
        private val data = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
        private val name = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
        private val size = c.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
        private val modified = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
        private val mime = c.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)

        fun row(c: Cursor): Row? {
            val path = c.getString(data) ?: return null
            return Row(
                path = path,
                name = c.getString(name) ?: path.substringAfterLast('/'),
                size = if (c.isNull(size)) 0 else c.getLong(size),
                // Der Index speichert Sekunden.
                modifiedMillis = if (c.isNull(modified)) 0 else c.getLong(modified) * 1000,
                mime = c.getString(mime),
            )
        }
    }

    companion object {
        const val DEFAULT_LIMIT = 5_000
        private const val RECENT_WINDOW_MILLIS = 30L * 24 * 60 * 60 * 1000

        private val ROW_PROJECTION = arrayOf(
            MediaStore.MediaColumns.DATA,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.MIME_TYPE,
        )

        /** Papierkorb und unfertige Kopien von ORBIT gehören in keine Kategorie und keine Suche. */
        private val EXCLUSIONS = "${MediaStore.MediaColumns.DATA} NOT LIKE ? AND ${MediaStore.MediaColumns.DISPLAY_NAME} NOT LIKE ?"
        private val EXCLUSION_ARGS = listOf("%/${TrashStore.DIR_NAME}/%", "%${de.privateapp.aether.files.FileNames.TEMP_SUFFIX}")

        /** Liegt in einem versteckten Ordner oder ist selbst versteckt (Name beginnt mit „.“). */
        internal fun isHiddenPath(path: String): Boolean = path.split('/').any { it.length > 1 && it.startsWith('.') }

        internal fun escapeLike(text: String): String =
            text.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    }
}
