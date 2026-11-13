package de.privateapp.aether.ui.files.preview

import android.graphics.Bitmap
import android.util.LruCache
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.privateapp.aether.AppGraph
import de.privateapp.aether.files.DirectoryReader
import de.privateapp.aether.files.FailureReason
import de.privateapp.aether.files.FileEntry
import de.privateapp.aether.files.FileKind
import de.privateapp.aether.files.FileNames
import de.privateapp.aether.files.FileOperation
import de.privateapp.aether.files.FileSorting
import de.privateapp.aether.files.Listing
import de.privateapp.aether.files.OperationReport
import de.privateapp.aether.files.TextPreview
import de.privateapp.aether.files.TextPreviewReader
import de.privateapp.aether.files.ZipContents
import de.privateapp.aether.files.ZipContentsReader
import de.privateapp.aether.operations.JobStatus
import de.privateapp.aether.platform.storage.PdfPages
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException

/** Eine Anzeigezeile; [number] = echte Zeilennummer, `null` für die Fortsetzung einer sehr langen Zeile. */
class DisplayLine(val number: Int?, val text: String)

/** Text einer Datei – so, wie die Vorschau ihn zeigt. */
sealed interface TextLoad {
    data object Loading : TextLoad

    /** [modifiedAtLoad] = Änderungszeit beim Lesen (Schutz vor Überschreiben fremder Änderungen). */
    class Ready(val preview: TextPreview, val lines: List<DisplayLine>, val lineCount: Int, val modifiedAtLoad: Long, val sizeAtLoad: Long) : TextLoad

    data object Failed : TextLoad
}

sealed interface PdfLoad {
    data object Loading : PdfLoad

    class Open(val pages: PdfPages) : PdfLoad

    data object Protected : PdfLoad

    data object Broken : PdfLoad
}

/** Warum Sichern nicht geklappt hat – für einen Hinweis, der die Lage richtig beschreibt. */
enum class SaveProblem { CHANGED, DELETED, OTHER }

/** Warum Bearbeiten gesperrt ist (`null` = Bearbeiten möglich). */
enum class EditBlock { TRUNCATED, TOO_LARGE, LOSSY, READ_ONLY }

/**
 * Zustand der Schnellansicht einer Datei. Bei Bildern zusätzlich die übrigen Bilder desselben Ordners (Wischen), bei
 * Text der Editor-Zustand – er liegt hier, damit eine Bearbeitung Drehen und kurze Wechsel übersteht (nicht aber das
 * Beenden der App durch Android, siehe GRENZEN).
 */
class PreviewViewModel(private val graph: AppGraph, val path: String) : ViewModel() {

    /** Datei der Route (bzw. das gerade gezeigte Bild beim Wischen). `null` = noch nicht gelesen. */
    var entry: FileEntry? by mutableStateOf(null)
        private set

    /** Datei gibt es nicht (mehr). */
    var missing by mutableStateOf(false)
        private set

    /** Bilder im selben Ordner (Sortierung wie in der Ordneransicht); leer, solange nicht gelesen. */
    var siblings: List<FileEntry> by mutableStateOf(emptyList())
        private set

    var text: TextLoad by mutableStateOf(TextLoad.Loading)
        private set

    var zip: ZipContents? by mutableStateOf(null)
        private set

    /** Freier Platz im Ordner des Archivs (für den Hinweis vor dem Entpacken), `null` = unbekannt. */
    var zipFreeBytes: Long? by mutableStateOf(null)
        private set

    var pdf: PdfLoad by mutableStateOf(PdfLoad.Loading)
        private set

    /** Nach „Als Kopie sichern“: Pfad der neuen Datei (die Oberfläche öffnet sie), danach [consumeOpenedCopy]. */
    var savedCopy: String? by mutableStateOf(null)
        private set

    // --- Editor ---------------------------------------------------------------------------------------------------

    /** Inhalt während der Bearbeitung; `null` = nicht im Bearbeitungsmodus. */
    var editor: TextFieldState? by mutableStateOf(null)
        private set

    private var editorOriginal: String = ""

    /** Laufender Sichern-Auftrag dieser Seite (Kennung im OperationManager und der Auftrag selbst). */
    private var pendingSaveId: Long? by mutableStateOf(null)
    private var pendingSave: FileOperation.WriteText? = null
    private var pendingIsCopy = false

    /** Aufträge, die nach „Verwerfen“ nicht mehr abgebrochen werden konnten – ihr Ergebnis lädt nur neu. */
    private val orphanSaves = HashSet<FileOperation.WriteText>()

    /** Zwischen „Als Kopie sichern“ und dem Einreihen (freier Name wird gesucht). */
    private var preparingCopy by mutableStateOf(false)

    val saving: Boolean get() = pendingSaveId != null || preparingCopy

    /** Sichern wartet hinter einem anderen Vorgang (Vorgänge laufen nacheinander). */
    var saveQueued by mutableStateOf(false)
        private set

    /** Letztes Sichern gescheitert – Grund für den Hinweis im Editor. */
    var saveProblem: SaveProblem? by mutableStateOf(null)
        private set

    var saveProblemReason: FailureReason? by mutableStateOf(null)
        private set

    val editing: Boolean get() = editor != null

    /** Ungesicherte Änderungen. Vergleicht Zeichen für Zeichen, ohne den Text bei jedem Tastendruck zu kopieren. */
    val dirty: Boolean by derivedStateOf {
        val e = editor
        e != null && !e.text.contentEquals(editorOriginal)
    }

    private val loadLock = Mutex()
    private var initialLoad: Job? = null

    private val pdfIo = Dispatchers.IO.limitedParallelism(1)
    private val pageCache = object : LruCache<String, Bitmap>(pageCacheBytes()) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.allocationByteCount
    }

    init {
        initialLoad = viewModelScope.launch { loadLock.withLock { load(initial = true) } }
        viewModelScope.launch {
            graph.operations.finished.collect { report -> onFinished(report) }
        }
        viewModelScope.launch {
            graph.operations.jobs.collect { jobs ->
                val id = pendingSaveId
                saveQueued = id != null && jobs.firstOrNull { it.id == id }?.status == JobStatus.QUEUED
            }
        }
    }

    /** Beim Zurückkehren in die App: Datei könnte sich geändert haben. Während der Bearbeitung bleibt alles stehen. */
    fun refresh() {
        if (editing || initialLoad?.isActive == true) return
        viewModelScope.launch {
            loadLock.withLock {
                val e = entry
                if (e != null && e.kind == FileKind.IMAGE) refreshImages(e, renamedTo = null) else load(initial = false)
            }
        }
    }

    private suspend fun load(initial: Boolean) {
        val current = entry?.path ?: path
        val e = withContext(Dispatchers.IO) { DirectoryReader.entryFor(current) }
        val changed = e?.modifiedMillis != entry?.modifiedMillis || e?.sizeBytes != entry?.sizeBytes
        entry = e
        missing = e == null
        if (e == null || e.isDirectory) return
        when {
            e.kind == FileKind.IMAGE -> if (initial || siblings.isEmpty()) loadSiblings(e)
            e.kind == FileKind.TEXT -> if (initial || changed) loadText(e)
            e.kind == FileKind.PDF -> if (initial || changed) loadPdf(e)
            e.kind == FileKind.ARCHIVE && e.extension == "zip" -> if (initial || changed) loadZip(e)
            else -> Unit
        }
    }

    // --- Bilder ---------------------------------------------------------------------------------------------------

    private suspend fun imagesIn(dir: String, includeHidden: Boolean): List<FileEntry> {
        val prefs = graph.filesPrefs.filterNotNull().first()
        return withContext(Dispatchers.IO) {
            when (val l = DirectoryReader.list(dir, includeHidden = prefs.showHidden || includeHidden)) {
                is Listing.Entries -> FileSorting.sorted(l.entries.filter { it.kind == FileKind.IMAGE }, prefs.sort)
                else -> emptyList()
            }
        }
    }

    private suspend fun loadSiblings(e: FileEntry) {
        val list = imagesIn(e.parentPath, e.isHidden)
        siblings = if (list.any { it.path == e.path }) list else listOf(e)
    }

    /**
     * Ordner mit Bildern hat sich geändert (auch durch andere Apps): Liste neu lesen – mit frischen Änderungszeiten,
     * damit bearbeitete Bilder neu geladen werden. Ist das gezeigte Bild weg, rückt das nächste an seine Stelle; wurde
     * es umbenannt, bleibt es gezeigt.
     */
    private suspend fun refreshImages(e: FileEntry, renamedTo: String?) {
        val oldIndex = siblings.indexOfFirst { it.path == e.path }.coerceAtLeast(0)
        val list = imagesIn(e.parentPath, e.isHidden)
        val same = list.firstOrNull { it.path == (renamedTo ?: e.path) }
        siblings = list
        entry = same ?: list.getOrNull(oldIndex.coerceAtMost(list.lastIndex))
        missing = entry == null
    }

    /** Beim Wischen: Kopf und Aktionen beziehen sich auf das gezeigte Bild. */
    fun showSibling(e: FileEntry) {
        if (entry?.path != e.path) entry = e
    }

    // --- Text, ZIP, PDF ---------------------------------------------------------------------------------------------

    private suspend fun loadText(e: FileEntry) {
        text = try {
            val preview = withContext(Dispatchers.IO) { TextPreviewReader.read(e.path) }
            val lines = withContext(Dispatchers.Default) { displayLines(preview.text) }
            TextLoad.Ready(preview, lines, lineCount(preview.text), e.modifiedMillis, e.sizeBytes)
        } catch (ex: IOException) {
            TextLoad.Failed
        }
    }

    private suspend fun loadZip(e: FileEntry) {
        val (contents, free) = withContext(Dispatchers.IO) {
            ZipContentsReader.read(e.path) to try {
                File(e.parentPath).usableSpace.takeIf { it > 0 }
            } catch (ex: SecurityException) {
                null
            }
        }
        zip = contents
        zipFreeBytes = free
    }

    private suspend fun loadPdf(e: FileEntry) {
        (pdf as? PdfLoad.Open)?.pages?.closeInBackground()
        pageCache.evictAll()
        pdf = PdfLoad.Loading
        // Öffnen nicht mittendrin abbrechen: Sonst bliebe ein geöffnetes Dokument ohne Besitzer zurück.
        val result = withContext(NonCancellable + pdfIo) {
            try {
                PdfLoad.Open(PdfPages.open(e.path))
            } catch (ex: SecurityException) {
                PdfLoad.Protected
            } catch (ex: IOException) {
                PdfLoad.Broken
            } catch (ex: RuntimeException) {
                PdfLoad.Broken
            }
        }
        if (!currentCoroutineContext().isActive) {
            (result as? PdfLoad.Open)?.pages?.closeInBackground()
            return
        }
        pdf = result
    }

    /** Seite [index] in [widthPx] Breite – aus dem Zwischenspeicher oder frisch gezeichnet (immer eine zugleich). */
    suspend fun renderPage(index: Int, widthPx: Int): Bitmap? {
        val pages = (pdf as? PdfLoad.Open)?.pages ?: return null
        val key = "$index@$widthPx"
        pageCache.get(key)?.let { return it }
        return withContext(pdfIo) {
            pageCache.get(key) ?: try {
                pages.render(index, widthPx)?.also { pageCache.put(key, it) }
            } catch (ex: RuntimeException) {
                null
            } catch (ex: OutOfMemoryError) {
                null
            }
        }
    }

    /** Seite nicht sichtbar (anderer Bereich, App im Hintergrund): gezeichnete Seiten freigeben. */
    fun trimPdfCache() = pageCache.evictAll()

    // --- Bearbeiten -----------------------------------------------------------------------------------------------

    /** Warum diese Textdatei nicht bearbeitet werden kann – oder `null`. */
    fun editBlock(e: FileEntry, t: TextLoad.Ready): EditBlock? = when {
        t.preview.truncated -> EditBlock.TRUNCATED
        t.preview.lossy -> EditBlock.LOSSY
        e.sizeBytes > EDIT_LIMIT_BYTES -> EditBlock.TOO_LARGE
        !e.writable -> EditBlock.READ_ONLY
        else -> null
    }

    fun startEditing() {
        val e = entry ?: return
        val ready = text as? TextLoad.Ready ?: return
        if (editBlock(e, ready) != null) return
        editorOriginal = ready.preview.text
        editor = TextFieldState(ready.preview.text)
        clearProblem()
    }

    /**
     * Änderungen verwerfen. Ein noch wartendes Sichern wird abgebrochen; läuft es schon, wird sein Ergebnis nur noch
     * angezeigt (neu geladen), es beendet aber keine neue Bearbeitung.
     */
    fun discardEditing() {
        pendingSaveId?.let { graph.operations.cancel(it) }
        pendingSave?.let { orphanSaves += it }
        pendingSave = null
        pendingSaveId = null
        saveQueued = false
        editor = null
        clearProblem()
        val e = entry ?: return
        viewModelScope.launch {
            loadLock.withLock {
                val fresh = withContext(Dispatchers.IO) { DirectoryReader.entryFor(e.path) }
                entry = fresh
                missing = fresh == null
                if (fresh != null) loadText(fresh)
            }
        }
    }

    /** Sichern über die Datei-Engine: erst vollständig schreiben, dann ersetzen – nur wenn sich die Datei nicht geändert hat. */
    fun save() {
        val e = entry ?: return
        val state = editor ?: return
        val ready = text as? TextLoad.Ready ?: return
        if (saving) return
        submitSave(FileOperation.WriteText(e.path, state.text.toString(), ready.modifiedAtLoad), copy = false)
    }

    /** Eigene Fassung als neue Datei neben dem Original sichern („Notiz 2.txt“) – wenn das Original weg oder fremd geändert ist. */
    fun saveAsCopy() {
        val e = entry ?: return
        val state = editor ?: return
        if (saving) return
        val text = state.text.toString()
        preparingCopy = true
        viewModelScope.launch {
            val target = withContext(Dispatchers.IO) {
                val parent = File(e.parentPath)
                val taken = parent.list()?.map { it.lowercase() }?.toSet().orEmpty()
                File(parent, FileNames.uniqueName(e.name, isDirectory = false) { it.lowercase() in taken }).path
            }
            preparingCopy = false
            if (editor != null) submitSave(FileOperation.WriteText(target, text, expectedModifiedMillis = null), copy = true)
        }
    }

    private fun submitSave(op: FileOperation.WriteText, copy: Boolean) {
        clearProblem()
        pendingSave = op
        pendingIsCopy = copy
        val id = graph.operations.submit(op)
        pendingSaveId = id
        saveQueued = graph.operations.jobs.value.firstOrNull { it.id == id }?.status == JobStatus.QUEUED
    }

    /** „Sichern abbrechen“, solange es noch wartet bzw. läuft; die Änderungen bleiben im Editor. */
    fun cancelSave() {
        pendingSaveId?.let { graph.operations.cancel(it) }
    }

    private fun clearProblem() {
        saveProblem = null
        saveProblemReason = null
    }

    fun consumeOpenedCopy() {
        savedCopy = null
    }

    private suspend fun onFinished(report: OperationReport) {
        val op = report.operation
        if (op is FileOperation.WriteText) {
            if (op === pendingSave) {
                finishSave(op, report)
                return
            }
            if (orphanSaves.remove(op)) {
                if (!editing) loadLock.withLock { load(initial = false) }
                return
            }
        }
        val current = entry?.path ?: path
        val parent = current.substringBeforeLast('/')
        val touched = (report.createdPaths + report.removedPaths).any { it == current || it.substringBeforeLast('/') == parent }
        if (!touched) return
        loadLock.withLock {
            val e = entry
            if (e != null && e.kind == FileKind.IMAGE && siblings.size > 1) {
                val renamedTo = (op as? FileOperation.Rename)?.takeIf { it.source == e.path }?.let { report.createdPaths.firstOrNull() }
                refreshImages(e, renamedTo)
            } else if (!editing) {
                load(initial = false)
            }
        }
    }

    private suspend fun finishSave(op: FileOperation.WriteText, report: OperationReport) {
        pendingSave = null
        pendingSaveId = null
        saveQueued = false
        when {
            report.cancelled -> Unit // Änderungen bleiben im Editor
            report.isComplete && pendingIsCopy -> {
                editor = null
                savedCopy = op.path
            }
            report.isComplete -> {
                editor = null
                // Immer neu lesen: Auf FAT-Speichern (SD-Karte) ist die Änderungszeit nur auf 2 s genau.
                loadLock.withLock {
                    val fresh = withContext(Dispatchers.IO) { DirectoryReader.entryFor(op.path) }
                    entry = fresh
                    missing = fresh == null
                    if (fresh != null) loadText(fresh)
                }
            }
            else -> {
                val reason = report.failures.firstOrNull()?.reason ?: FailureReason.IO_ERROR
                saveProblemReason = reason
                val exists = withContext(Dispatchers.IO) { File(op.path).exists() }
                saveProblem = when {
                    pendingIsCopy -> SaveProblem.OTHER
                    reason == FailureReason.CHANGED_MEANWHILE && !exists -> SaveProblem.DELETED
                    reason == FailureReason.CHANGED_MEANWHILE -> SaveProblem.CHANGED
                    reason == FailureReason.NOT_FOUND -> SaveProblem.DELETED
                    else -> SaveProblem.OTHER
                }
            }
        }
    }

    override fun onCleared() {
        // Nicht auf dem Hauptthread warten, falls gerade eine Seite gezeichnet wird.
        (pdf as? PdfLoad.Open)?.pages?.closeInBackground()
        pageCache.evictAll()
    }

    companion object {
        /**
         * Bearbeiten bis 256 kB: Das Eingabefeld legt den ganzen Text auf einmal aus; darüber wird Tippen auf
         * Mittelklasse-Geräten zäh. Lesen geht bis 512 KiB (Grenze des Vorschaulesers).
         */
        const val EDIT_LIMIT_BYTES = 256_000L

        /** Sehr lange Zeilen (z. B. minimiertes JSON) werden für die Anzeige in Stücke geteilt – sonst stockt das Scrollen. */
        private const val MAX_LINE_CHARS = 4_000

        private fun pageCacheBytes(): Int = (Runtime.getRuntime().maxMemory() / 4).coerceIn(16L * 1024 * 1024, 64L * 1024 * 1024).toInt()

        fun displayLines(text: String): List<DisplayLine> {
            if (text.isEmpty()) return listOf(DisplayLine(1, ""))
            val out = ArrayList<DisplayLine>()
            var number = 0
            for (line in text.split('\n')) {
                number++
                val l = line.removeSuffix("\r")
                if (l.length <= MAX_LINE_CHARS) {
                    out += DisplayLine(number, l)
                    continue
                }
                var i = 0
                var first = true
                while (i < l.length) {
                    var end = minOf(l.length, i + MAX_LINE_CHARS)
                    // Nie ein Zeichen aus zwei Teilen (Emoji u. a.) zerschneiden.
                    if (end < l.length && Character.isHighSurrogate(l[end - 1])) end--
                    out += DisplayLine(if (first) number else null, l.substring(i, end))
                    first = false
                    i = end
                }
            }
            // Abschließender Zeilenumbruch erzeugt keine eigene (leere) Zeile.
            if (text.endsWith('\n') && out.size > 1 && out.last().text.isEmpty()) out.removeAt(out.lastIndex)
            return out
        }

        fun lineCount(text: String): Int = if (text.isEmpty()) 0 else text.count { it == '\n' } + if (text.endsWith('\n')) 0 else 1
    }
}
