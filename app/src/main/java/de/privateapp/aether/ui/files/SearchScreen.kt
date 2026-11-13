package de.privateapp.aether.ui.files

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.TextFieldValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import de.privateapp.aether.AppGraph
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.GlassCircleButton
import de.privateapp.aether.design.GlassTextField
import de.privateapp.aether.design.PillButton
import de.privateapp.aether.design.SegmentedControl
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.design.Tone
import de.privateapp.aether.files.FileEntry
import de.privateapp.aether.files.FileSearch
import de.privateapp.aether.model.Fmt
import de.privateapp.aether.settings.FilesPrefs
import de.privateapp.aether.settings.ViewMode
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.withContext

/** Wo gesucht wird. */
enum class SearchMode(val label: String) {
    /** Medienindex von Android: sofort, alle eingebundenen Speicher, ohne versteckte Ordner. */
    INDEX("Schnell"),

    /** Direkt im Dateisystem: auch versteckte und nicht erfasste Dateien, dafür langsamer. */
    THOROUGH("Gründlich"),
}

data class SearchResults(
    val query: String,
    val results: List<FileEntry> = emptyList(),
    val searching: Boolean = false,
    /** Gründliche Suche: bisher durchsuchte Ordner. */
    val foldersScanned: Int = 0,
    val limitReached: Boolean = false,
)

@OptIn(FlowPreview::class, ExperimentalCoroutinesApi::class)
class SearchViewModel(private val graph: AppGraph) : ViewModel() {
    val query = MutableStateFlow("")
    val mode = MutableStateFlow(SearchMode.INDEX)

    val results: StateFlow<SearchResults> = combine(query.debounce(250), mode) { q, m -> q.trim() to m }
        .flatMapLatest { (q, m) ->
            when {
                q.isEmpty() -> flowOf(SearchResults(q))
                m == SearchMode.INDEX -> flow {
                    emit(SearchResults(q, searching = true))
                    emit(SearchResults(q, graph.mediaIndex.search(q)))
                }
                else -> flow {
                    emit(SearchResults(q, searching = true))
                    val roots = withContext(Dispatchers.IO) { graph.volumeRoots.list().map { it.path } }
                    emitAll(
                        FileSearch.search(roots, q, includeHidden = true)
                            .map { p -> SearchResults(q, p.matches, searching = !p.done, foldersScanned = p.foldersScanned, limitReached = p.limitReached) },
                    )
                }
            }
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SearchResults(""))

    val prefs: StateFlow<FilesPrefs?> get() = graph.filesPrefs

    fun remember(text: String) = viewModelScope.launch { graph.settings.addRecentSearch(text) }

    fun clearHistory() = viewModelScope.launch { graph.settings.clearRecentSearches() }
}

/** Suche nach Namen – im Medienindex (sofort) oder gründlich im Dateisystem. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SearchScreen(graph: AppGraph, insets: PaddingValues, onBack: () -> Unit) {
    val vm: SearchViewModel = viewModel { SearchViewModel(graph) }
    val results by vm.results.collectAsStateWithLifecycle()
    val mode by vm.mode.collectAsStateWithLifecycle()
    val prefs by vm.prefs.collectAsStateWithLifecycle()
    val actions = fileActions
    val colors = Aether.colors
    val keyboard = LocalSoftwareKeyboardController.current
    var field by remember { mutableStateOf(TextFieldValue(vm.query.value)) }
    val focus = remember { FocusRequester() }

    val open: (FileEntry) -> Unit = { e ->
        vm.remember(results.query)
        keyboard?.hide()
        actions.open(e)
    }

    BrowserGrid(insets, ViewMode.LIST) {
        fullWidth("header") {
            Column {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    GlassCircleButton(icon = AetherIcons.ChevronLeft, contentDescription = "Zurück", onClick = onBack)
                    Spacer(Modifier.width(Spacing.m))
                    GlassTextField(
                        value = field,
                        onValueChange = {
                            field = it
                            vm.query.value = it.text
                        },
                        label = "Dateien und Ordner suchen",
                        leadingIcon = AetherIcons.Search,
                        imeAction = ImeAction.Search,
                        onImeAction = {
                            keyboard?.hide()
                            vm.remember(field.text)
                        },
                        focusRequester = focus,
                        onClear = {
                            field = TextFieldValue("")
                            vm.query.value = ""
                        },
                        modifier = Modifier.weight(1f),
                    )
                    // Hier (im selben Listeneintrag wie das Feld) ist es sicher angebunden.
                    LaunchedEffect(Unit) {
                        if (vm.query.value.isEmpty()) {
                            try {
                                focus.requestFocus()
                            } catch (e: IllegalStateException) {
                                // ohne automatische Tastatur
                            }
                        }
                    }
                }
                Spacer(Modifier.height(Spacing.m))
                SegmentedControl(
                    options = SearchMode.entries,
                    selected = mode,
                    onSelect = { vm.mode.value = it },
                    label = { it.label },
                )
                Spacer(Modifier.height(Spacing.xs))
                Text(
                    when (mode) {
                        SearchMode.INDEX -> "Sucht sofort im Medienindex von Android – alle Speicher, ohne versteckte Ordner."
                        SearchMode.THOROUGH -> "Durchsucht jeden Ordner direkt, auch versteckte und noch nicht erfasste Dateien. Dauert länger."
                    },
                    color = colors.textTertiary,
                    style = Aether.type.footnote,
                )
                Spacer(Modifier.height(Spacing.m))
                val status = when {
                    results.query.isEmpty() -> null
                    results.searching && mode == SearchMode.THOROUGH -> "Sucht … ${Fmt.count(results.foldersScanned)} Ordner durchsucht, ${Fmt.count(results.results.size)} Treffer"
                    results.searching -> "Sucht …"
                    results.limitReached -> "Die ersten ${Fmt.count(results.results.size)} Treffer – bitte genauer suchen"
                    else -> if (results.results.size == 1) "1 Treffer" else "${Fmt.count(results.results.size)} Treffer"
                }
                if (status != null) Text(status, color = colors.textSecondary, style = Aether.type.subhead)
            }
        }
        if (results.query.isEmpty()) {
            val recent = prefs?.recentSearches.orEmpty()
            if (recent.isNotEmpty()) {
                fullWidth("recent") {
                    Column(Modifier.padding(top = Spacing.s)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("Zuletzt gesucht", color = colors.text, style = Aether.type.headline, modifier = Modifier.weight(1f))
                            PillButton("Löschen", onClick = { vm.clearHistory() })
                        }
                        Spacer(Modifier.height(Spacing.s))
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.s), verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
                            recent.forEach { r ->
                                PillButton(r, onClick = {
                                    field = TextFieldValue(r)
                                    vm.query.value = r
                                }, icon = AetherIcons.Clock)
                            }
                        }
                    }
                }
            }
        } else if (!results.searching && results.results.isEmpty()) {
            fullWidth("none") {
                EmptyState(
                    icon = AetherIcons.Search,
                    title = "Nichts gefunden",
                    message = if (mode == SearchMode.INDEX) {
                        "Kein Name enthält „${results.query}“. Versteckte oder gerade erst angelegte Dateien findet die gründliche Suche."
                    } else {
                        "Kein Name enthält „${results.query}“."
                    },
                    tone = Tone.NEUTRAL,
                    action = if (mode == SearchMode.INDEX) {
                        { PillButton("Gründlich suchen", onClick = { vm.mode.value = SearchMode.THOROUGH }) }
                    } else {
                        null
                    },
                )
            }
        }
        fileItems(
            entries = results.results,
            viewMode = ViewMode.LIST,
            selection = emptySet(),
            selecting = false,
            nowMillis = System.currentTimeMillis(),
            onOpen = open,
            onToggle = {},
            onStartSelection = { actions.showActions(listOf(it)) },
            onMore = { actions.showActions(listOf(it)) },
            showLocation = true,
        )
    }
}
