package de.privateapp.aether.ui.files

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import de.privateapp.aether.AppGraph
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.ActionDivider
import de.privateapp.aether.design.ActionGroup
import de.privateapp.aether.design.ActionRow
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.GlassSheet
import de.privateapp.aether.design.SheetHeader
import de.privateapp.aether.design.GlassToolbar
import de.privateapp.aether.design.Notice
import de.privateapp.aether.design.PillButton
import de.privateapp.aether.design.Radii
import de.privateapp.aether.design.SectionLabel
import de.privateapp.aether.design.SelectionMark
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.design.Tone
import de.privateapp.aether.design.ToolbarAction
import de.privateapp.aether.files.DirectoryReader
import de.privateapp.aether.files.FileEntry
import de.privateapp.aether.files.FileKind
import de.privateapp.aether.files.FileTypes
import de.privateapp.aether.files.TrashedItem
import de.privateapp.aether.model.ByteFormat
import de.privateapp.aether.model.Fmt
import de.privateapp.aether.platform.storage.BrowseRoot
import de.privateapp.aether.settings.ViewMode
import de.privateapp.aether.ui.BottomBarOverride
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Ein Eintrag im Papierkorb mit dem Objekt, wie es jetzt dort liegt (für Vorschaubild und Art). */
data class TrashRow(val item: TrashedItem, val entry: FileEntry)

/** Papierkorb eines Speichers. [root] ist eindeutig (zwei Karten können gleich heißen), [label] die Anzeige. */
data class TrashGroup(val root: String, val label: String, val rows: List<TrashRow>)

data class TrashState(
    val loaded: Boolean = false,
    /** Je Speicher die Einträge, neueste zuerst. */
    val groups: List<TrashGroup> = emptyList(),
    val now: Long = System.currentTimeMillis(),
) {
    val all: List<TrashRow> get() = groups.flatMap { it.rows }
}

class TrashViewModel(private val graph: AppGraph) : ViewModel() {
    private val _state = MutableStateFlow(TrashState())
    val state: StateFlow<TrashState> = _state.asStateFlow()

    var selection: Set<String>? by mutableStateOf(null)
        private set

    private var visible = false

    init {
        viewModelScope.launch { graph.operations.finished.collect { if (visible) reload() } }
    }

    fun setVisible(v: Boolean) {
        visible = v
        if (v) reload()
    }

    fun reload() {
        viewModelScope.launch {
            val groups = withContext(Dispatchers.IO) {
                val roots = graph.volumeRoots.list()
                val items = graph.trash.list(roots.map { it.path })
                items.groupBy { it.volumeRoot }.map { (root, list) ->
                    TrashGroup(root, label(root, roots), list.map { TrashRow(it, entryOf(it)) })
                }
            }
            _state.value = TrashState(loaded = true, groups = groups, now = System.currentTimeMillis())
            selection?.let { sel ->
                val ids = groups.flatMap { g -> g.rows.map { it.item.id } }.toSet()
                selection = sel.filterTo(LinkedHashSet()) { it in ids }
            }
        }
    }

    private fun label(root: String, roots: List<BrowseRoot>): String =
        roots.firstOrNull { it.path == root }?.let { FolderViewModel.rootLabel(it) } ?: root

    /** Das Objekt im Papierkorb – mit ursprünglichem Namen, damit Art und Symbol stimmen. */
    private fun entryOf(item: TrashedItem): FileEntry {
        val stored = DirectoryReader.entryFor(item.storedPath)
        val ext = if (item.isDirectory) "" else FileTypes.extensionOf(item.name)
        return (stored ?: FileEntry(item.storedPath, item.name, item.isDirectory, item.sizeBytes, item.deletedAtMillis, false, FileKind.OTHER, ext, null, true, true))
            .copy(name = item.name, kind = FileTypes.kindOf(item.name, item.isDirectory), extension = ext, mimeType = if (item.isDirectory) null else FileTypes.mimeTypeOf(ext))
    }

    fun toggle(id: String) {
        val sel = selection ?: linkedSetOf()
        selection = if (id in sel) sel - id else sel + id
    }

    fun startSelection(id: String? = null) {
        selection = if (id != null) linkedSetOf(id) else linkedSetOf()
    }

    fun endSelection() {
        selection = null
    }

    fun selectAll() {
        val all = _state.value.all.map { it.item.id }
        selection = if (selection?.size == all.size) linkedSetOf() else LinkedHashSet(all)
    }

    fun selectedItems(): List<TrashedItem> {
        val sel = selection ?: return emptyList()
        return _state.value.all.map { it.item }.filter { it.id in sel }
    }
}

/**
 * Papierkorb – je Speicher ein eigener. Nichts wird von selbst gelöscht: Objekte bleiben, bis man sie
 * wiederherstellt oder endgültig löscht. Wiederherstellen legt sie an ihren ursprünglichen Ort zurück.
 */
@Composable
fun TrashScreen(graph: AppGraph, insets: PaddingValues, onBack: () -> Unit) {
    val vm: TrashViewModel = viewModel { TrashViewModel(graph) }
    val state by vm.state.collectAsStateWithLifecycle()
    val actions = fileActions
    val selection = vm.selection
    var sheetFor by remember { mutableStateOf<TrashRow?>(null) }
    val selecting = selection != null
    LifecycleResumeEffect(vm) {
        vm.setVisible(true)
        onPauseOrDispose { vm.setVisible(false) }
    }
    BackHandler(enabled = selecting) { vm.endSelection() }
    EndSelectionOnOperation(graph, selection?.let { vm.selectedItems().map { it.storedPath }.toSet() }, vm::endSelection)
    BottomBarOverride("trash", selecting) { backdrop ->
        val items = vm.selectedItems()
        GlassToolbar(
            actions = listOf(
                ToolbarAction("Wiederherstellen", AetherIcons.Restore, enabled = items.isNotEmpty()) { actions.restore(items) },
                ToolbarAction("Endgültig löschen", AetherIcons.Trash, enabled = items.isNotEmpty(), destructive = true) { actions.deleteFromTrash(items) },
            ),
            backdrop = backdrop,
        )
    }

    val all = state.all
    BrowserGrid(insets, ViewMode.LIST) {
        fullWidth("header") {
            Column {
                BrowserHeader(
                    title = "Papierkorb",
                    subtitle = if (!state.loaded) "Wird gelesen …" else if (all.isEmpty()) "Leer" else "${Fmt.count(all.size)} ${if (all.size == 1) "Objekt" else "Objekte"} · ${ByteFormat.format(all.sumOf { it.item.sizeBytes })}",
                    onBack = onBack,
                    selectionCount = selection?.size,
                    onEndSelection = vm::endSelection,
                    onSelectAll = vm::selectAll,
                    allSelected = selection != null && selection.size == all.size && all.isNotEmpty(),
                ) {
                    if (all.isNotEmpty()) PillButton("Auswählen", onClick = { vm.startSelection() })
                }
                Spacer(Modifier.height(Spacing.m))
                Notice(
                    title = "Nichts wird von selbst gelöscht",
                    message = "Objekte bleiben im Papierkorb ihres Speichers, bis du sie wiederherstellst oder endgültig löschst. Sie belegen so lange weiter Platz.",
                    tone = Tone.INFO,
                    icon = AetherIcons.Info,
                )
                if (all.isNotEmpty() && !selecting) {
                    Spacer(Modifier.height(Spacing.m))
                    PillButton(
                        "Papierkorb leeren",
                        onClick = { actions.deleteFromTrash(all.map { it.item }, emptiesTrash = true) },
                        icon = AetherIcons.Trash,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        }
        if (state.loaded && all.isEmpty()) {
            fullWidth("empty") {
                EmptyState(AetherIcons.Trash, "Der Papierkorb ist leer", "Was du in ORBIT löschst, landet zuerst hier – und lässt sich wiederherstellen.")
            }
        }
        state.groups.forEach { group ->
            val rows = group.rows
            if (state.groups.size > 1) fullWidth("label:${group.root}") { SectionLabel(group.label, Modifier.padding(top = Spacing.l, bottom = Spacing.xs)) }
            rows.forEachIndexed { i, row ->
                item(key = row.item.storedPath) {
                    TrashRowItem(
                        row = row,
                        now = state.now,
                        selecting = selecting,
                        selected = selection?.contains(row.item.id) == true,
                        onClick = { if (selecting) vm.toggle(row.item.id) else sheetFor = row },
                        onLongClick = { if (selecting) vm.toggle(row.item.id) else vm.startSelection(row.item.id) },
                        onRestore = { actions.restore(listOf(row.item)) },
                        showDivider = i < rows.lastIndex,
                    )
                }
            }
        }
    }
    sheetFor?.let { row ->
        GlassSheet(onDismiss = { sheetFor = null }) {
            SheetHeader(
                title = row.item.name,
                subtitle = "Gelöscht ${Fmt.dateTime(row.item.deletedAtMillis)} · ${ByteFormat.format(row.item.sizeBytes)}",
                leading = { FileThumbnail(row.entry, size = 48.dp) },
            )
            Text(
                "Ursprünglicher Ort: ${displayParent(row.item.originalPath).ifEmpty { "/" }}",
                color = Aether.colors.textSecondary,
                style = Aether.type.footnote,
            )
            Spacer(Modifier.height(Spacing.s))
            ActionGroup {
                ActionRow("Wiederherstellen", AetherIcons.Restore, onClick = {
                    sheetFor = null
                    actions.restore(listOf(row.item))
                })
                ActionDivider()
                ActionRow("Endgültig löschen …", AetherIcons.Trash, destructive = true, onClick = {
                    sheetFor = null
                    actions.deleteFromTrash(listOf(row.item))
                })
            }
        }
    }
}

@Composable
private fun TrashRowItem(
    row: TrashRow,
    now: Long,
    selecting: Boolean,
    selected: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    onRestore: () -> Unit,
    showDivider: Boolean,
) {
    val colors = Aether.colors
    val item = row.item
    val deleted = "Gelöscht ${Fmt.fileDate(item.deletedAtMillis, now)}"
    val origin = "aus ${displayParent(item.originalPath).ifEmpty { "/" }}"
    Column(Modifier.fillMaxWidth()) {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 64.dp)
                .clip(RoundedCornerShape(Radii.control))
                .background(if (selected) colors.fill else androidx.compose.ui.graphics.Color.Transparent)
                .combinedClickable(onClick = onClick, onLongClick = onLongClick, onLongClickLabel = "Auswählen")
                .semantics(mergeDescendants = true) {
                    contentDescription = "${item.name}, $deleted, $origin, ${ByteFormat.format(item.sizeBytes)}"
                    if (selecting) {
                        role = Role.Checkbox
                        this.selected = selected
                    }
                    customActions = listOf(CustomAccessibilityAction("Wiederherstellen") { onRestore(); true })
                }
                .padding(horizontal = Spacing.xs, vertical = Spacing.s),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (selecting) {
                SelectionMark(selected)
                Spacer(Modifier.width(Spacing.m))
            }
            FileThumbnail(row.entry, size = 44.dp)
            Spacer(Modifier.width(Spacing.m))
            Column(Modifier.weight(1f).clearAndSetSemantics { }) {
                Text(item.name, color = colors.text, style = Aether.type.bodyStrong, maxLines = 2, overflow = TextOverflow.MiddleEllipsis)
                Text("$deleted · ${ByteFormat.format(item.sizeBytes)}", color = colors.textSecondary, style = Aether.type.footnote, maxLines = 1)
                Text(origin, color = if (selected) colors.textSecondary else colors.textTertiary, style = Aether.type.caption, maxLines = 1, overflow = TextOverflow.StartEllipsis)
            }
            if (!selecting) {
                PillButton("Wiederherstellen", onClick = onRestore, modifier = Modifier.clearAndSetSemantics { })
            }
        }
        if (showDivider) Box(Modifier.fillMaxWidth().padding(start = 60.dp).height(0.5.dp).background(colors.hairline))
    }
}
