package de.privateapp.aether.ui.files

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import de.privateapp.aether.AppGraph
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.Notice
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.design.Tone
import de.privateapp.aether.files.FileEntry
import de.privateapp.aether.files.FileSorting
import de.privateapp.aether.files.SortOrder
import de.privateapp.aether.model.Fmt
import de.privateapp.aether.platform.storage.CategoryPage
import de.privateapp.aether.platform.storage.MediaCategory
import de.privateapp.aether.settings.FilesPrefs
import de.privateapp.aether.settings.ViewMode
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers

data class CategoryState(
    val category: MediaCategory,
    val page: CategoryPage? = null,
    val entries: List<FileEntry> = emptyList(),
    val prefs: FilesPrefs = FilesPrefs(),
    val now: Long = System.currentTimeMillis(),
) {
    val viewMode: ViewMode get() = if (category.isVisual) prefs.mediaViewMode else prefs.viewMode
}

/** Eine Kategorie aus dem Medienindex (neueste zuerst geladen, danach in der gewählten Sortierung). */
@OptIn(FlowPreview::class)
class CategoryViewModel(private val graph: AppGraph, val category: MediaCategory) : ViewModel() {
    private val _state = MutableStateFlow(CategoryState(category))
    val state: StateFlow<CategoryState> = _state.asStateFlow()

    var selection: Set<String>? by mutableStateOf(null)
        private set

    private var loadJob: Job? = null
    private var visible = false

    /** Sichtbar (im Vordergrund): neu laden; unsichtbar: Änderungen nur vormerken. */
    fun setVisible(v: Boolean) {
        visible = v
        if (v) reload()
    }

    init {
        viewModelScope.launch {
            graph.filesPrefs.filterNotNull().collect { prefs ->
                val page = _state.value.page
                val entries = withContext(Dispatchers.Default) { sorted(page, prefs.sort) }
                _state.update { it.copy(prefs = prefs, entries = if (it.page === page) entries else it.entries) }
            }
        }
        viewModelScope.launch {
            // Nur nachladen, solange die Seite sichtbar ist; sonst beim nächsten Erscheinen (siehe [setVisible]).
            merge(graph.mediaIndex.changes(), graph.operations.finished.map { }).debounce(800).collect { if (visible) reload() }
        }
    }

    fun reload() {
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            val page = graph.mediaIndex.list(category)
            val order = _state.value.prefs.sort
            val entries = withContext(Dispatchers.Default) { sorted(page, order) }
            _state.update { it.copy(page = page, entries = if (it.prefs.sort == order) entries else sorted(page, it.prefs.sort), now = System.currentTimeMillis()) }
            selection?.let { sel ->
                val present = page.entries.map { it.path }.toSet()
                selection = sel.filterTo(LinkedHashSet()) { it in present }
            }
        }
    }

    private fun sorted(page: CategoryPage?, order: SortOrder): List<FileEntry> =
        page?.entries?.let { FileSorting.sorted(it, order) }.orEmpty()

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

    fun setSort(order: SortOrder) = viewModelScope.launch { graph.settings.setSort(order) }

    fun setViewMode(mode: ViewMode) = viewModelScope.launch { graph.settings.setViewMode(mode, forMedia = category.isVisual) }
}

@Composable
fun CategoryScreen(graph: AppGraph, category: MediaCategory, insets: PaddingValues, onBack: () -> Unit) {
    val vm: CategoryViewModel = viewModel { CategoryViewModel(graph, category) }
    val state by vm.state.collectAsStateWithLifecycle()
    val actions = fileActions
    val selection = vm.selection
    val selecting = selection != null
    LifecycleResumeEffect(vm) {
        vm.setVisible(true)
        onPauseOrDispose { vm.setVisible(false) }
    }
    BackHandler(enabled = selecting) { vm.endSelection() }
    EndSelectionOnOperation(graph, selection, vm::endSelection)
    SelectionToolbar(owner = "category:${category.name}", active = selecting, selected = vm.selectedEntries(), onDone = vm::endSelection)

    val page = state.page
    val subtitle = when {
        page == null -> "Wird geladen …"
        page.total == 0 -> category.description
        else -> "${Fmt.count(page.total)} ${if (page.total == 1) "Datei" else "Dateien"} · ${category.description}"
    }
    BrowserGrid(insets, state.viewMode) {
        fullWidth("header") {
            Column {
                BrowserHeader(
                    title = category.label,
                    subtitle = subtitle,
                    onBack = onBack,
                    selectionCount = selection?.size,
                    onEndSelection = vm::endSelection,
                    onSelectAll = vm::selectAll,
                    allSelected = selection != null && selection.size == state.entries.size && state.entries.isNotEmpty(),
                ) {
                    BrowserMenu(
                        sort = state.prefs.sort,
                        onSort = { vm.setSort(it) },
                        viewMode = state.viewMode,
                        onViewMode = { vm.setViewMode(it) },
                        showHidden = null,
                        onShowHidden = {},
                        extra = listOf(MenuEntry("Auswählen", AetherIcons.SelectAll, enabled = state.entries.isNotEmpty()) { vm.startSelection() }),
                    )
                }
                if (page != null && page.isLimited) {
                    Spacer(Modifier.height(Spacing.s))
                    Notice(
                        title = "Die ${Fmt.count(page.entries.size)} neuesten von ${Fmt.count(page.total)}",
                        message = "So bleibt die Liste flüssig. Ältere findest du über die Suche oder im jeweiligen Ordner.",
                        tone = Tone.INFO,
                    )
                }
                Spacer(Modifier.height(Spacing.s))
            }
        }
        if (page != null && page.total == 0) {
            fullWidth("empty") {
                EmptyState(
                    icon = category.icon(),
                    title = "Nichts in „${category.label}“",
                    message = "Der Medienindex von Android kennt auf den eingebundenen Speichern keine passenden Dateien. Neue Dateien erscheinen, sobald Android sie erfasst hat.",
                    tone = category.tone(),
                )
            }
        }
        fileItems(
            entries = state.entries,
            viewMode = state.viewMode,
            selection = selection.orEmpty(),
            selecting = selecting,
            nowMillis = state.now,
            onOpen = actions::open,
            onToggle = vm::toggle,
            onStartSelection = vm::startSelection,
            onMore = { actions.showActions(listOf(it)) },
            showLocation = true,
        )
    }
}
