package de.privateapp.aether.ui.files

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.privateapp.aether.AppGraph
import de.privateapp.aether.files.DirectoryReader
import de.privateapp.aether.files.FileEntry
import de.privateapp.aether.files.FileOperation
import de.privateapp.aether.files.FileSorting
import de.privateapp.aether.files.Listing
import de.privateapp.aether.files.OperationReport
import de.privateapp.aether.files.SortOrder
import de.privateapp.aether.platform.storage.BrowseRoot
import de.privateapp.aether.platform.storage.DirectoryWatcher
import de.privateapp.aether.settings.FilesPrefs
import de.privateapp.aether.settings.ViewMode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class FolderState(
    val path: String,
    /** `null` = wird zum ersten Mal gelesen. */
    val listing: Listing? = null,
    /** Einträge in der gewählten Sortierung (leer, solange nicht gelesen oder bei Fehlern). */
    val entries: List<FileEntry> = emptyList(),
    val root: BrowseRoot? = null,
    val prefs: FilesPrefs = FilesPrefs(),
    val now: Long = System.currentTimeMillis(),
) {
    val directory: FileEntry? get() = (listing as? Listing.Entries)?.directory
    val hiddenCount: Int get() = (listing as? Listing.Entries)?.hiddenCount ?: 0
    val isFavorite: Boolean get() = path in prefs.favorites
    val writable: Boolean get() = directory?.writable == true && root?.readOnly != true
}

/**
 * Ein geöffneter Ordner: Inhalt (frisch vom Dateisystem), Sortierung und Ansicht aus den Einstellungen, Auswahl.
 * Lädt neu bei Änderungen im Ordner (auch durch andere Apps, soweit Android sie meldet), nach eigenen Vorgängen und
 * wenn man in die App zurückkehrt.
 */
@OptIn(FlowPreview::class)
class FolderViewModel(private val graph: AppGraph, val path: String) : ViewModel() {

    private val _state = MutableStateFlow(FolderState(path))
    val state: StateFlow<FolderState> = _state.asStateFlow()

    /** Ausgewählte Pfade; `null` = keine Auswahl aktiv. */
    var selection: Set<String>? by mutableStateOf(null)
        private set

    private var loadJob: Job? = null
    private var visible = false

    /** Sichtbar (im Vordergrund): neu laden; unsichtbar: Änderungen nur vormerken (keine Arbeit im Hintergrund). */
    fun setVisible(v: Boolean) {
        visible = v
        if (v) reload()
    }

    init {
        viewModelScope.launch {
            graph.filesPrefs.filterNotNull().collect { prefs ->
                val hiddenChanged = prefs.showHidden != _state.value.prefs.showHidden
                // Natürliche Sortierung großer Ordner (Tausende Einträge) nicht im Hauptthread.
                val listing = _state.value.listing
                val sorted = withContext(Dispatchers.Default) { sortedEntries(listing, prefs.sort) }
                _state.update { it.copy(prefs = prefs, entries = if (it.listing === listing) sorted else it.entries) }
                if (hiddenChanged && visible) reload()
            }
        }
        viewModelScope.launch {
            DirectoryWatcher.changes(path).debounce(300).collect { if (visible) reload() }
        }
        viewModelScope.launch {
            graph.operations.finished.collect { report -> if (visible && affects(report)) reload() }
        }
    }

    fun reload() {
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            val showHidden = _state.value.prefs.showHidden
            val order = _state.value.prefs.sort
            val (listing, root, sorted) = withContext(Dispatchers.IO) {
                val l = DirectoryReader.list(path, includeHidden = showHidden)
                Triple(l, graph.volumeRoots.rootFor(path), sortedEntries(l, order))
            }
            _state.update {
                // Hat sich die Sortierung inzwischen geändert, sortiert der Einstellungs-Zweig ohnehin neu.
                it.copy(listing = listing, entries = if (it.prefs.sort == order) sorted else sortedEntries(listing, it.prefs.sort), root = root, now = System.currentTimeMillis())
            }
            // Ausgewählte Objekte, die es nicht mehr gibt, fallen aus der Auswahl.
            selection?.let { sel ->
                val present = _state.value.entries.map { it.path }.toSet()
                selection = sel.filterTo(LinkedHashSet()) { it in present }
            }
        }
    }

    private fun sortedEntries(listing: Listing?, order: SortOrder): List<FileEntry> =
        (listing as? Listing.Entries)?.entries?.let { FileSorting.sorted(it, order) }.orEmpty()

    /** Betrifft der Vorgang diesen Ordner (etwas hinein, heraus, darin geändert)? */
    private fun affects(report: OperationReport): Boolean {
        val paths = report.createdPaths + report.removedPaths + when (val op = report.operation) {
            is FileOperation.Rename -> listOf(op.source)
            is FileOperation.WriteText -> listOf(op.path)
            is FileOperation.CreateFolder -> listOf(op.parentDir + "/" + op.name)
            else -> emptyList()
        }
        return paths.any { p -> p.substringBeforeLast('/') == path || p == path || path.startsWith("$p/") }
    }

    // --- Auswahl ------------------------------------------------------------------------------------------------

    fun startSelection(first: FileEntry? = null) {
        selection = if (first != null) linkedSetOf(first.path) else linkedSetOf()
    }

    fun toggle(entry: FileEntry) {
        val sel = selection ?: return startSelection(entry)
        selection = if (entry.path in sel) sel - entry.path else sel + entry.path
    }

    fun selectAll() {
        val all = _state.value.entries.map { it.path }
        selection = if (selection?.size == all.size) linkedSetOf() else LinkedHashSet(all)
    }

    fun endSelection() {
        selection = null
    }

    fun selectedEntries(): List<FileEntry> {
        val sel = selection ?: return emptyList()
        return _state.value.entries.filter { it.path in sel }
    }

    // --- Einstellungen ------------------------------------------------------------------------------------------

    fun setSort(order: SortOrder) = viewModelScope.launch { graph.settings.setSort(order) }

    fun setViewMode(mode: ViewMode) = viewModelScope.launch { graph.settings.setViewMode(mode, forMedia = false) }

    fun setShowHidden(show: Boolean) = viewModelScope.launch { graph.settings.setShowHidden(show) }

    companion object {
        /** Abschnitte der Pfadleiste: Speicherwurzel (mit Bezeichnung) bis zum aktuellen Ordner. */
        fun segments(path: String, root: BrowseRoot?): List<Pair<String, String>> {
            if (root == null) {
                val parts = path.split('/').filter { it.isNotEmpty() }
                return parts.mapIndexed { i, name -> name to "/" + parts.take(i + 1).joinToString("/") }
            }
            val rel = path.removePrefix(root.path).split('/').filter { it.isNotEmpty() }
            return listOf(rootLabel(root) to root.path) + rel.mapIndexed { i, name -> name to root.path + "/" + rel.take(i + 1).joinToString("/") }
        }

        fun rootLabel(root: BrowseRoot): String = if (root.isPrimary) "Interner Speicher" else root.label

        /** Anzeigename eines Ordners: die Wurzel heißt wie der Speicher. */
        fun title(path: String, root: BrowseRoot?): String =
            if (root != null && root.path == path) rootLabel(root) else path.trimEnd('/').substringAfterLast('/').ifEmpty { "/" }
    }
}
