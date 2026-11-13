package de.privateapp.aether.ui.files

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.privateapp.aether.AppGraph
import de.privateapp.aether.files.DirectoryReader
import de.privateapp.aether.files.FileEntry
import de.privateapp.aether.model.Reading
import de.privateapp.aether.model.storage.Capacity
import de.privateapp.aether.platform.storage.AllFilesAccess
import de.privateapp.aether.platform.storage.BrowseRoot
import de.privateapp.aether.platform.storage.CategorySummary
import de.privateapp.aether.platform.storage.MediaCategory
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/** Ein Speicher mit seiner Kapazität (aus der Speicherübersicht, falls Android sie meldet). */
data class RootInfo(val root: BrowseRoot, val capacity: Reading<Capacity>?)

/** Ein Ordner für den Schnellzugriff (Download, Kamera …), nur wenn es ihn gibt. */
data class QuickFolder(val label: String, val path: String)

data class TrashSummary(val count: Int, val bytes: Long)

data class FilesHomeState(
    /** `null` = noch nicht geprüft. */
    val access: Boolean? = null,
    val roots: List<RootInfo> = emptyList(),
    val quick: List<QuickFolder> = emptyList(),
    val favorites: List<FileEntry> = emptyList(),
    /** Favoriten, die es gerade nicht gibt (z. B. SD-Karte entnommen) – werden ehrlich als „nicht verfügbar“ gezeigt. */
    val missingFavorites: List<String> = emptyList(),
    val recent: List<FileEntry> = emptyList(),
    /** `null` je Kategorie = wird gezählt. */
    val categories: Map<MediaCategory, CategorySummary?> = EMPTY_COUNTS,
    val trash: TrashSummary? = null,
    val now: Long = System.currentTimeMillis(),
)

private val EMPTY_COUNTS: Map<MediaCategory, CategorySummary?> = MediaCategory.entries.associateWith { null }

private data class Places(
    val roots: List<RootInfo>,
    val quick: List<QuickFolder>,
    val favorites: List<FileEntry>,
    val missingFavorites: List<String>,
    val recent: List<FileEntry>,
)

/**
 * Startseite des Dateimanagers: Zugriff, Speicherorte, Favoriten, Schnellzugriff, Kategorien, zuletzt geöffnet,
 * Papierkorb. Alles wird nur gelesen, solange die Seite sichtbar ist (danach meldet sich die Seite nach 5 s bei
 * Android ab); Kategorien zählt der Medienindex von Android – erst, wenn der Zugriff erlaubt ist.
 */
@OptIn(FlowPreview::class, ExperimentalCoroutinesApi::class)
class FilesHomeViewModel(private val graph: AppGraph) : ViewModel() {

    private val access = MutableStateFlow<Boolean?>(null)
    private val refresh = MutableStateFlow(0)

    private val places: Flow<Places> = combine(graph.storage, graph.filesPrefs.filterNotNull(), refresh) { storage, prefs, _ -> storage to prefs }
        .map { (storage, prefs) ->
            withContext(Dispatchers.IO) {
                val roots = graph.volumeRoots.list()
                val fav = prefs.favorites.map { it to DirectoryReader.entryFor(it) }
                Places(
                    roots = roots.map { r -> RootInfo(r, storage?.volumes?.firstOrNull { it.path?.trimEnd('/') == r.path }?.capacity) },
                    quick = roots.firstOrNull { it.isPrimary }?.let { quickFolders(it.path) }.orEmpty(),
                    favorites = fav.mapNotNull { it.second },
                    missingFavorites = fav.filter { it.second == null }.map { it.first },
                    recent = prefs.recentFiles.asSequence().mapNotNull { DirectoryReader.entryFor(it) }.filter { !it.isDirectory }.take(6).toList(),
                )
            }
        }

    /** Kategorien nacheinander zählen (die Kacheln füllen sich der Reihe nach); neu bei Änderungen im Index. */
    private val counts: Flow<Map<MediaCategory, CategorySummary?>> = access.flatMapLatest { granted ->
        if (granted != true) {
            flowOf(EMPTY_COUNTS)
        } else {
            // Während z. B. die Kamera filmt, ändert sich der Index ständig – höchstens alle 4 s neu zählen.
            merge(graph.mediaIndex.changes(), graph.operations.finished.map { })
                .debounce(4_000)
                .onStart { emit(Unit) }
                .flatMapLatest {
                    channelFlow {
                        var map = state.value.categories
                        for (c in MediaCategory.entries) {
                            map = map + (c to graph.mediaIndex.summary(c))
                            send(map)
                        }
                    }
                }
        }
    }

    private val trash: Flow<TrashSummary?> = combine(access, refresh, graph.operations.finished.map { }.onStart { emit(Unit) }) { a, _, _ -> a }
        .map { granted ->
            if (granted != true) {
                null
            } else {
                withContext(Dispatchers.IO) {
                    val items = graph.trash.list(graph.volumeRoots.list().map { it.path })
                    TrashSummary(items.size, items.sumOf { it.sizeBytes })
                }
            }
        }

    val state: StateFlow<FilesHomeState> = combine(access, places.onStart { emit(Places(emptyList(), emptyList(), emptyList(), emptyList(), emptyList())) }, counts, trash.onStart { emit(null) }) { a, p, c, t ->
        FilesHomeState(a, p.roots, p.quick, p.favorites, p.missingFavorites, p.recent, c, t, System.currentTimeMillis())
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), FilesHomeState())

    /** Beim Erscheinen und bei Rückkehr in die App: Der Zugriff könnte in den Einstellungen geändert worden sein. */
    fun onResume() {
        access.value = AllFilesAccess.isGranted()
        refresh.value++
    }

    fun clearRecent() = viewModelScope.launch { graph.settings.clearRecentFiles() }

    fun removeFavorite(path: String) = viewModelScope.launch { graph.settings.removeFavorite(path) }

    private fun quickFolders(primary: String): List<QuickFolder> = listOf(
        "Download" to "Downloads",
        "DCIM" to "Kamera",
        "Pictures" to "Bilder",
        "Documents" to "Dokumente",
        "Music" to "Musik",
        "Movies" to "Filme",
    ).mapNotNull { (dir, label) -> "$primary/$dir".takeIf { File(it).isDirectory }?.let { QuickFolder(label, it) } }
}
