package de.privateapp.aether.ui.files

import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.GlassCircleButton
import de.privateapp.aether.design.GlassToolbar
import de.privateapp.aether.design.IconBadge
import de.privateapp.aether.design.OrbitMark
import de.privateapp.aether.design.MinTouchTarget
import de.privateapp.aether.design.PillButton
import de.privateapp.aether.design.Radii
import de.privateapp.aether.design.SelectionMark
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.design.Tone
import de.privateapp.aether.design.ToolbarAction
import de.privateapp.aether.files.FileEntry
import de.privateapp.aether.files.SortKey
import de.privateapp.aether.files.SortOrder
import de.privateapp.aether.settings.ViewMode
import de.privateapp.aether.ui.BottomBarOverride
import de.privateapp.aether.ui.common.entrance

/*
 * Gemeinsame Bausteine für Ordner, Kategorien und Suche: Liste/Raster, Zeilen und Kacheln mit Auswahl, Kopf mit
 * Menü, Pfadleiste und Werkzeugleiste für die Auswahl.
 */

/**
 * Scrollbare Fläche für Dateien – Liste oder Raster in einem: Kopfzeilen nehmen die volle Breite ein. In der Liste
 * stehen auf breiten Displays zwei Spalten nebeneinander.
 */
@Composable
fun BrowserGrid(
    insets: PaddingValues,
    viewMode: ViewMode,
    modifier: Modifier = Modifier,
    reselect: Int = 0,
    content: LazyGridScope.() -> Unit,
) {
    val state = rememberLazyGridState()
    val motion = Aether.motion
    var handled by rememberSaveable { mutableIntStateOf(reselect) }
    LaunchedEffect(reselect) {
        if (reselect > handled) {
            handled = reselect
            if (motion.reduced) state.scrollToItem(0) else state.animateScrollToItem(0)
        } else if (reselect < handled) {
            handled = reselect
        }
    }
    val dir = LocalLayoutDirection.current
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        LazyVerticalGrid(
            state = state,
            columns = if (viewMode == ViewMode.GRID) GridCells.Adaptive(minSize = 104.dp) else GridCells.Adaptive(minSize = 340.dp),
            modifier = Modifier.fillMaxHeight().widthIn(max = Spacing.contentMaxWidth + 200.dp).fillMaxWidth(),
            contentPadding = PaddingValues(
                start = insets.calculateStartPadding(dir) + Spacing.page,
                end = insets.calculateEndPadding(dir) + Spacing.page,
                top = insets.calculateTopPadding() + Spacing.xl,
                bottom = insets.calculateBottomPadding() + Spacing.xxl,
            ),
            horizontalArrangement = Arrangement.spacedBy(if (viewMode == ViewMode.GRID) Spacing.m else Spacing.l),
            verticalArrangement = Arrangement.spacedBy(if (viewMode == ViewMode.GRID) Spacing.l else 0.dp),
            content = content,
        )
    }
}

/** Element über die volle Breite (Kopf, Hinweise, Abschnittstitel). */
fun LazyGridScope.fullWidth(key: Any, content: @Composable () -> Unit) {
    item(key = key, span = { GridItemSpan(maxLineSpan) }, contentType = "full") { content() }
}

/** Dateien als Zeilen bzw. Kacheln, je nach [viewMode]. */
fun LazyGridScope.fileItems(
    entries: List<FileEntry>,
    viewMode: ViewMode,
    selection: Set<String>,
    selecting: Boolean,
    nowMillis: Long,
    onOpen: (FileEntry) -> Unit,
    onToggle: (FileEntry) -> Unit,
    onStartSelection: (FileEntry) -> Unit,
    onMore: (FileEntry) -> Unit,
    showLocation: Boolean = false,
) {
    items(entries.size, key = { entries[it].path }, contentType = { viewMode }) { i ->
        val entry = entries[i]
        val selected = entry.path in selection
        val click = { if (selecting) onToggle(entry) else onOpen(entry) }
        if (viewMode == ViewMode.GRID) {
            FileTile(entry, selected, selecting, onClick = click, onLongClick = { if (selecting) onToggle(entry) else onStartSelection(entry) }, onMore = { onMore(entry) })
        } else {
            FileRow(
                entry = entry,
                selected = selected,
                selecting = selecting,
                detail = entry.detailLine(nowMillis),
                location = if (showLocation) displayParent(entry.path) else null,
                onClick = click,
                onLongClick = { if (selecting) onToggle(entry) else onStartSelection(entry) },
                onMore = { onMore(entry) },
                showDivider = i < entries.lastIndex,
            )
        }
    }
}

/** Übergeordneter Ordner in lesbarer Form („Interner Speicher › Download“). */
fun displayParent(path: String): String {
    val parent = path.substringBeforeLast('/', "")
    return parent
        .replaceFirst(Regex("^/storage/emulated/0"), "Interner Speicher")
        .replaceFirst(Regex("^/storage/([0-9A-Fa-f]{4}-[0-9A-Fa-f]{4})"), "Speicher $1")
        .split('/').filter { it.isNotEmpty() }.joinToString(" › ")
}

@Composable
fun FileRow(
    entry: FileEntry,
    selected: Boolean,
    selecting: Boolean,
    detail: String,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    onMore: () -> Unit,
    modifier: Modifier = Modifier,
    location: String? = null,
    showDivider: Boolean = true,
) {
    val colors = Aether.colors
    val type = Aether.type
    val description = listOfNotNull(entry.name, if (entry.isDirectory) "Ordner" else entry.kind.label, detail, location?.let { "in $it" }).joinToString(", ")
    Column(modifier.fillMaxWidth()) {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 64.dp)
                .clip(RoundedCornerShape(Radii.control))
                .background(if (selected) colors.fill else androidx.compose.ui.graphics.Color.Transparent)
                .combinedClickable(
                    onClick = onClick,
                    // Spürbare Rückmeldung beim langen Drücken liefert combinedClickable selbst.
                    onLongClick = onLongClick,
                    onLongClickLabel = "Auswählen",
                )
                .semantics(mergeDescendants = true) {
                    contentDescription = description
                    if (selecting) {
                        role = Role.Checkbox
                        this.selected = selected
                        stateDescription = if (selected) "Ausgewählt" else "Nicht ausgewählt"
                    }
                    customActions = listOf(CustomAccessibilityAction("Aktionen") { onMore(); true })
                }
                .padding(horizontal = Spacing.xs, vertical = Spacing.s),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (selecting) {
                SelectionMark(selected)
                Spacer(Modifier.width(Spacing.m))
            }
            FileThumbnail(entry, size = 44.dp)
            Spacer(Modifier.width(Spacing.m))
            Column(Modifier.weight(1f).clearAndSetSemantics { }) {
                Text(entry.name, color = colors.text, style = type.bodyStrong, maxLines = 2, overflow = TextOverflow.MiddleEllipsis)
                Text(detail, color = colors.textSecondary, style = type.footnote, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (location != null) {
                    // Auf der Auswahlfläche reicht Tertiärschrift nicht für 4,5 : 1 – dann Sekundärschrift.
                    Text(location, color = if (selected) colors.textSecondary else colors.textTertiary, style = type.caption, maxLines = 1, overflow = TextOverflow.StartEllipsis)
                }
            }
            if (!selecting) {
                MoreButton(onMore, Modifier.clearAndSetSemantics { })
            }
        }
        if (showDivider) {
            Box(Modifier.fillMaxWidth().padding(start = if (selecting) 96.dp else 60.dp).height(0.5.dp).background(colors.hairline))
        }
    }
}

@Composable
fun FileTile(
    entry: FileEntry,
    selected: Boolean,
    selecting: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    onMore: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = Aether.colors
    val type = Aether.type
    Column(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radii.control))
            .background(if (selected) colors.fill else androidx.compose.ui.graphics.Color.Transparent)
            .combinedClickable(
                onClick = onClick,
                onLongClick = onLongClick,
                onLongClickLabel = "Auswählen",
            )
            .semantics(mergeDescendants = true) {
                contentDescription = listOf(entry.name, if (entry.isDirectory) "Ordner" else entry.kind.label).joinToString(", ")
                if (selecting) {
                    role = Role.Checkbox
                    this.selected = selected
                    stateDescription = if (selected) "Ausgewählt" else "Nicht ausgewählt"
                }
                customActions = listOf(CustomAccessibilityAction("Aktionen") { onMore(); true })
            }
            .padding(Spacing.xs),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(Modifier.fillMaxWidth().aspectRatio(1f)) {
            BoxWithThumb(entry)
            if (selecting) {
                SelectionMark(selected, Modifier.align(Alignment.BottomEnd).padding(Spacing.xs))
            }
        }
        Spacer(Modifier.height(Spacing.xs))
        Text(
            entry.name,
            color = colors.text,
            style = type.caption,
            maxLines = 2,
            overflow = TextOverflow.MiddleEllipsis,
            textAlign = TextAlign.Center,
            modifier = Modifier.clearAndSetSemantics { },
        )
    }
}

@Composable
private fun BoxWithThumb(entry: FileEntry) {
    androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        val size = if (entry.isDirectory) maxWidth * 0.82f else maxWidth
        FileThumbnail(entry, size = size, corner = if (entry.isDirectory) size * 0.2f else 12.dp, fill = true)
    }
}

@Composable
private fun MoreButton(onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = Aether.colors
    Box(
        modifier
            .size(MinTouchTarget)
            .clip(CircleShape)
            .combinedClickable(onClick = onClick, role = Role.Button, onClickLabel = "Aktionen"),
        contentAlignment = Alignment.Center,
    ) {
        Icon(AetherIcons.More, contentDescription = "Aktionen", tint = colors.textSecondary, modifier = Modifier.size(20.dp))
    }
}

/**
 * Kopf einer Dateiseite: Zurück, Titel mit Unterzeile, rechts Schaltflächen. In der Auswahl stattdessen: Schließen,
 * „n ausgewählt“, „Alle auswählen“.
 */
@Composable
fun BrowserHeader(
    title: String,
    subtitle: String?,
    onBack: (() -> Unit)?,
    selectionCount: Int?,
    onEndSelection: () -> Unit,
    onSelectAll: () -> Unit,
    allSelected: Boolean,
    trailing: @Composable () -> Unit,
) {
    val colors = Aether.colors
    val type = Aether.type
    Row(Modifier.fillMaxWidth().entrance(0), verticalAlignment = Alignment.CenterVertically) {
        if (selectionCount != null) {
            GlassCircleButton(icon = AetherIcons.Close, contentDescription = "Auswahl beenden", onClick = onEndSelection)
            Spacer(Modifier.width(Spacing.l))
            Text(
                if (selectionCount == 0) "Objekte auswählen" else "$selectionCount ausgewählt",
                color = colors.text,
                style = type.title2,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            PillButton(if (allSelected) "Keine" else "Alle", onClick = onSelectAll, icon = AetherIcons.SelectAll)
        } else {
            if (onBack != null) {
                GlassCircleButton(icon = AetherIcons.ChevronLeft, contentDescription = "Zurück", onClick = onBack)
                Spacer(Modifier.width(Spacing.l))
            }
            Column(Modifier.weight(1f)) {
                Text(title, color = colors.text, style = type.title, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.semantics { heading() })
                if (subtitle != null) Text(subtitle, color = colors.textSecondary, style = type.footnote, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Spacer(Modifier.width(Spacing.s))
            trailing()
        }
    }
}

/** Pfadleiste: jeder Abschnitt antippbar (springt zurück), der aktuelle Ordner hervorgehoben. */
@Composable
fun PathBar(segments: List<Pair<String, String>>, onSelect: (String) -> Unit, modifier: Modifier = Modifier) {
    val colors = Aether.colors
    val scroll = rememberScrollState()
    LaunchedEffect(segments.size) { scroll.scrollTo(scroll.maxValue) }
    Row(
        modifier.fillMaxWidth().horizontalScroll(scroll).padding(vertical = Spacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        segments.forEachIndexed { i, (label, path) ->
            val last = i == segments.lastIndex
            Text(
                label,
                color = if (last) colors.text else colors.accent,
                style = if (last) Aether.type.subhead else Aether.type.footnote,
                maxLines = 1,
                modifier = Modifier
                    // Berührfläche mindestens 48 dp (Bedienungshilfen), auch wenn der Abschnitt nur ein Wort ist.
                    .minimumInteractiveComponentSize()
                    .clip(RoundedCornerShape(Radii.small))
                    .combinedClickable(enabled = !last, role = Role.Button, onClick = { onSelect(path) })
                    .padding(horizontal = Spacing.xs, vertical = Spacing.xs),
            )
            if (!last) Icon(AetherIcons.ChevronRight, contentDescription = null, tint = colors.textTertiary, modifier = Modifier.size(14.dp))
        }
    }
}

/** Menü „Darstellung und mehr“ wie in „Dateien“ von Apple. */
@Composable
fun BrowserMenu(
    sort: SortOrder,
    onSort: (SortOrder) -> Unit,
    viewMode: ViewMode,
    onViewMode: (ViewMode) -> Unit,
    showHidden: Boolean?,
    onShowHidden: (Boolean) -> Unit,
    extra: List<MenuEntry>,
) {
    var open by remember { mutableStateOf(false) }
    val colors = Aether.colors
    Box {
        GlassCircleButton(icon = AetherIcons.More, contentDescription = "Darstellung und weitere Aktionen", onClick = { open = true })
        DropdownMenu(
            expanded = open,
            onDismissRequest = { open = false },
            shape = RoundedCornerShape(Radii.control),
            containerColor = colors.surfaceRaised,
            tonalElevation = 0.dp,
            shadowElevation = 12.dp,
        ) {
            extra.forEach { e ->
                MenuItem(e.label, e.icon, checked = null, enabled = e.enabled) {
                    open = false
                    e.onClick()
                }
            }
            if (extra.isNotEmpty()) HorizontalDivider(color = colors.hairline, thickness = 0.5.dp)
            MenuItem("Liste", AetherIcons.ListView, checked = viewMode == ViewMode.LIST) { open = false; onViewMode(ViewMode.LIST) }
            MenuItem("Raster", AetherIcons.Grid, checked = viewMode == ViewMode.GRID) { open = false; onViewMode(ViewMode.GRID) }
            HorizontalDivider(color = colors.hairline, thickness = 0.5.dp)
            SortKey.entries.forEach { key ->
                val current = sort.key == key
                val arrow = if (current) (if (sort.ascending) AetherIcons.ChevronUp else AetherIcons.ChevronDown) else null
                MenuItem(
                    label = key.label,
                    icon = arrow ?: AetherIcons.Sort,
                    checked = current,
                    hint = if (current) (if (sort.ascending) sortHintAscending(key) else sortHintDescending(key)) else null,
                ) {
                    open = false
                    onSort(if (current) sort.copy(ascending = !sort.ascending) else SortOrder(key, ascending = key == SortKey.NAME || key == SortKey.KIND))
                }
            }
            if (showHidden != null) {
                HorizontalDivider(color = colors.hairline, thickness = 0.5.dp)
                MenuItem(
                    if (showHidden) "Versteckte Objekte ausblenden" else "Versteckte Objekte zeigen",
                    if (showHidden) AetherIcons.EyeOff else AetherIcons.Eye,
                    checked = null,
                ) { open = false; onShowHidden(!showHidden) }
            }
        }
    }
}

private fun sortHintAscending(key: SortKey) = when (key) {
    SortKey.NAME -> "A → Z"
    SortKey.DATE -> "Älteste zuerst"
    SortKey.SIZE -> "Kleinste zuerst"
    SortKey.KIND -> "A → Z"
}

private fun sortHintDescending(key: SortKey) = when (key) {
    SortKey.NAME -> "Z → A"
    SortKey.DATE -> "Neueste zuerst"
    SortKey.SIZE -> "Größte zuerst"
    SortKey.KIND -> "Z → A"
}

data class MenuEntry(val label: String, val icon: ImageVector, val enabled: Boolean = true, val onClick: () -> Unit)

@Composable
private fun MenuItem(label: String, icon: ImageVector, checked: Boolean?, enabled: Boolean = true, hint: String? = null, onClick: () -> Unit) {
    val colors = Aether.colors
    DropdownMenuItem(
        text = {
            Column {
                Text(label, color = if (enabled) colors.text else colors.textDisabled, style = Aether.type.body)
                if (hint != null) Text(hint, color = colors.textSecondary, style = Aether.type.caption)
            }
        },
        onClick = onClick,
        enabled = enabled,
        leadingIcon = { Icon(icon, contentDescription = null, tint = if (enabled) colors.textSecondary else colors.textDisabled, modifier = Modifier.size(20.dp)) },
        trailingIcon = if (checked == true) {
            { Icon(AetherIcons.Check, contentDescription = "Ausgewählt", tint = colors.accent, modifier = Modifier.size(18.dp)) }
        } else {
            null
        },
        modifier = Modifier.semantics { if (checked != null) selected = checked },
    )
}

/**
 * Werkzeugleiste der Auswahl anstelle der Reiterleiste: Teilen, Kopieren, Verschieben, Papierkorb, Mehr.
 * Ohne Auswahl sind die Schaltflächen sichtbar, aber nicht aktiv.
 */
@Composable
fun SelectionToolbar(owner: String, active: Boolean, selected: List<FileEntry>, onDone: () -> Unit) {
    val actions = fileActions
    BottomBarOverride(owner, active) { backdrop ->
        val any = selected.isNotEmpty()
        // Auf schreibgeschützten Speichern (oder ohne Schreibrecht) gibt es nur Teilen und Kopieren.
        val writable = selected.all { it.writable }
        GlassToolbar(
            actions = listOf(
                ToolbarAction("Teilen", AetherIcons.Share, enabled = any && selected.any { !it.isDirectory }) { actions.share(selected) },
                ToolbarAction("Kopieren", AetherIcons.Copy, enabled = any) { actions.copy(selected) },
                ToolbarAction("Verschieben", AetherIcons.MoveTo, enabled = any && writable) { actions.move(selected) },
                ToolbarAction("Papierkorb", AetherIcons.Trash, enabled = any && writable, destructive = true) {
                    actions.trash(selected)
                    onDone()
                },
                ToolbarAction("Mehr", AetherIcons.More, enabled = any) { actions.showActions(selected) },
            ),
            backdrop = backdrop,
        )
    }
}

/** Ruhiger Leerzustand mit Symbol, Titel und Erklärung (und optional einer Aktion). */
@Composable
fun EmptyState(icon: ImageVector, title: String, message: String, modifier: Modifier = Modifier, tone: Tone = Tone.NEUTRAL, action: (@Composable () -> Unit)? = null) {
    val colors = Aether.colors
    Column(
        modifier.fillMaxWidth().padding(vertical = Spacing.huge, horizontal = Spacing.l),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // ORBIT: eigene Illustration (Kern mit Umlaufbahnen und Symbol); Warnungen behalten ihr farbiges Zeichen
        if (tone == Tone.NEUTRAL || tone == Tone.ACCENT) {
            OrbitMark(size = 120.dp, icon = icon)
        } else {
            IconBadge(icon, tone = tone, size = 64.dp)
        }
        Spacer(Modifier.height(Spacing.l))
        Text(title, color = colors.text, style = Aether.type.headline, textAlign = TextAlign.Center)
        Spacer(Modifier.height(Spacing.xs))
        Text(message, color = colors.textSecondary, style = Aether.type.callout, textAlign = TextAlign.Center)
        if (action != null) {
            Spacer(Modifier.height(Spacing.l))
            action()
        }
    }
}
