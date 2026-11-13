package de.privateapp.aether.ui.files.preview

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.viewmodel.compose.viewModel
import de.privateapp.aether.AppGraph
import de.privateapp.aether.design.ActionDivider
import de.privateapp.aether.design.ActionGroup
import de.privateapp.aether.design.ActionRow
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.GlassCircleButton
import de.privateapp.aether.design.GlassDialog
import de.privateapp.aether.design.GlassSheet
import de.privateapp.aether.design.GlassToolbar
import de.privateapp.aether.design.PillButton
import de.privateapp.aether.design.SheetHeader
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.design.Tone
import de.privateapp.aether.design.ToolbarAction
import de.privateapp.aether.files.FileEntry
import de.privateapp.aether.files.FileKind
import de.privateapp.aether.model.ByteFormat
import de.privateapp.aether.model.Fmt
import de.privateapp.aether.navigation.LocalAppNavigator
import de.privateapp.aether.navigation.Route
import de.privateapp.aether.navigation.UnsavedGuard
import de.privateapp.aether.ui.BottomBarOverride
import de.privateapp.aether.ui.files.EmptyState
import de.privateapp.aether.ui.files.FileThumbnail
import de.privateapp.aether.ui.files.fileActions

/**
 * Schnellansicht einer Datei – wie „Quick Look“ bei Apple: Bilder (zoomen, wischen), Textdateien (lesen, bearbeiten),
 * PDF (alle Seiten), ZIP (Inhalt, Entpacken). Alles andere zeigt Angaben und „Öffnen mit …“.
 */
@Composable
fun PreviewScreen(graph: AppGraph, path: String, insets: PaddingValues, onBack: () -> Unit) {
    val vm: PreviewViewModel = viewModel { PreviewViewModel(graph, path) }
    val navigator = LocalAppNavigator.current
    val colors = Aether.colors
    val routeKey = Route.Preview(path).key
    var showMore by remember { mutableStateOf(false) }
    // Rückfrage „Änderungen verwerfen?“; [afterDiscard] = was danach geschehen soll (Seite schließen, Bereich wechseln …).
    var discardPrompt by remember { mutableStateOf<(() -> Unit)?>(null) }

    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { vm.refresh() }

    // Ungesicherte Änderungen schützen – auch gegen erneutes Antippen des Bereichs und Sprünge in der Pfadleiste.
    val dirty = vm.dirty
    DisposableEffect(dirty, routeKey) {
        if (dirty) {
            navigator.unsavedGuard = UnsavedGuard(routeKey) { proceed ->
                discardPrompt = {
                    vm.discardEditing()
                    proceed()
                }
            }
        } else if (navigator.unsavedGuard?.routeKey == routeKey) {
            navigator.unsavedGuard = null
        }
        onDispose {
            if (navigator.unsavedGuard?.routeKey == routeKey) navigator.unsavedGuard = null
        }
    }

    // Nach „Als Kopie sichern“: die neue Datei zeigen.
    val copy = vm.savedCopy
    LaunchedEffect(copy) {
        if (copy != null) {
            vm.consumeOpenedCopy()
            navigator.replaceTop(Route.Preview(copy))
        }
    }

    val leave = {
        when {
            vm.editing && vm.saving -> vm.cancelSave()
            vm.editing && vm.dirty -> discardPrompt = { vm.discardEditing() }
            vm.editing -> vm.discardEditing()
            else -> onBack()
        }
    }
    BackHandler(enabled = vm.editing) { leave() }
    EditorToolbar(vm, routeKey)

    val dir = LocalLayoutDirection.current
    val entry = vm.entry
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier
                .fillMaxSize()
                .widthIn(max = Spacing.contentMaxWidth + 200.dp)
                .padding(
                    start = insets.calculateStartPadding(dir),
                    end = insets.calculateEndPadding(dir),
                    top = insets.calculateTopPadding() + Spacing.l,
                ),
        ) {
            PreviewHeader(vm = vm, entry = entry, onBack = leave, onMore = { showMore = true })
            Spacer(Modifier.height(Spacing.m))
            // Die Abstände des Rahmens enthalten bereits die Tastatur (Systemleisten inkl. Bildschirmtastatur).
            val bottom = insets.calculateBottomPadding()
            Box(Modifier.fillMaxWidth().weight(1f)) {
                when {
                    entry == null && !vm.missing -> Text(
                        "Wird geöffnet …",
                        color = colors.textTertiary,
                        style = Aether.type.callout,
                        modifier = Modifier.align(Alignment.Center),
                    )
                    vm.missing || entry == null -> EmptyState(
                        icon = AetherIcons.FileGeneric,
                        title = "Nicht mehr vorhanden",
                        message = "Die Datei wurde gelöscht, verschoben oder umbenannt – oder der Speicher (z. B. die SD-Karte) wurde entfernt.",
                        tone = Tone.WARNING,
                        modifier = Modifier.padding(horizontal = Spacing.page),
                        action = { PillButton("Zurück", onClick = onBack, icon = AetherIcons.ChevronLeft) },
                    )
                    entry.isDirectory -> EmptyState(
                        icon = AetherIcons.Folder,
                        title = "Das ist ein Ordner",
                        message = "An dieser Stelle liegt inzwischen ein Ordner.",
                        modifier = Modifier.padding(horizontal = Spacing.page),
                        action = { PillButton("Ordner öffnen", onClick = { navigator.replaceTop(Route.Folder(entry.path)) }, icon = AetherIcons.Folder) },
                    )
                    entry.kind == FileKind.IMAGE -> ImagePreview(vm, bottom)
                    entry.kind == FileKind.TEXT -> TextPreviewContent(vm, bottom)
                    entry.kind == FileKind.PDF -> PdfPreview(vm, entry, bottom)
                    entry.kind == FileKind.ARCHIVE && entry.extension == "zip" -> ZipPreview(vm, entry, bottom)
                    else -> FallbackPreview(entry, bottom, message = "Für diesen Dateityp hat ORBIT keine Schnellansicht.")
                }
            }
        }
    }

    if (showMore && entry != null && !vm.editing) {
        MoreSheet(entry, onDismiss = { showMore = false })
    }
    val prompt = discardPrompt
    if (prompt != null) {
        GlassDialog(
            title = "Änderungen verwerfen?",
            message = "Deine Änderungen an „${entry?.name.orEmpty()}“ sind noch nicht gesichert.",
            onDismiss = { discardPrompt = null },
            dismissText = "Weiter bearbeiten",
            confirmText = "Verwerfen",
            destructive = true,
            onConfirm = {
                discardPrompt = null
                prompt()
            },
        )
    }
}

/**
 * Während der Bearbeitung ersetzt eine Werkzeugleiste die Reiterleiste: Rückgängig, Wiederholen, Als Kopie sichern. So kann
 * man nicht versehentlich den Bereich wechseln, und die Leiste sitzt griffbereit über der Tastatur.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun EditorToolbar(vm: PreviewViewModel, routeKey: String) {
    val state = vm.editor
    BottomBarOverride(owner = "editor:$routeKey", active = state != null) { backdrop ->
        val s = vm.editor
        if (s != null) {
            val undo = s.undoState
            GlassToolbar(
                actions = listOf(
                    ToolbarAction("Rückgängig", AetherIcons.Restore, enabled = undo.canUndo && !vm.saving) { undo.undo() },
                    ToolbarAction("Wiederholen", AetherIcons.Refresh, enabled = undo.canRedo && !vm.saving) { undo.redo() },
                    ToolbarAction("Als Kopie", AetherIcons.Copy, enabled = vm.dirty && !vm.saving) { vm.saveAsCopy() },
                ),
                backdrop = backdrop,
            )
        }
    }
}

/** Kopf: Zurück, Name, „Art · Größe · Datum“, Teilen und Mehr – im Editor: Abbrechen und Sichern. */
@Composable
private fun PreviewHeader(vm: PreviewViewModel, entry: FileEntry?, onBack: () -> Unit, onMore: () -> Unit) {
    val colors = Aether.colors
    val type = Aether.type
    val actions = fileActions
    Row(Modifier.fillMaxWidth().padding(horizontal = Spacing.page), verticalAlignment = Alignment.CenterVertically) {
        if (vm.editing) {
            PillButton(if (vm.saving) "Sichern abbrechen" else "Abbrechen", onClick = onBack)
            Spacer(Modifier.width(Spacing.m))
            Column(Modifier.weight(1f)) {
                Text(
                    entry?.name.orEmpty(),
                    color = colors.text,
                    style = type.headline,
                    maxLines = 1,
                    overflow = TextOverflow.MiddleEllipsis,
                    modifier = Modifier.semantics { heading() },
                )
                Text(
                    when {
                        vm.saveQueued -> "Wartet auf einen laufenden Vorgang …"
                        vm.saving -> "Wird gesichert …"
                        vm.dirty -> "Geändert – noch nicht gesichert"
                        else -> "Bearbeiten"
                    },
                    color = colors.textSecondary,
                    style = type.footnote,
                )
            }
            Spacer(Modifier.width(Spacing.s))
            PillButton("Sichern", onClick = vm::save, primary = true, enabled = vm.dirty && !vm.saving, icon = AetherIcons.Check)
            return@Row
        }
        GlassCircleButton(icon = AetherIcons.ChevronLeft, contentDescription = "Zurück", onClick = onBack)
        Spacer(Modifier.width(Spacing.m))
        Column(Modifier.weight(1f)) {
            Text(
                entry?.name ?: vm.path.substringAfterLast('/'),
                color = colors.text,
                style = type.title2,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.semantics { heading() },
            )
            if (entry != null && !entry.isDirectory) {
                val position = if (entry.kind == FileKind.IMAGE && vm.siblings.size > 1) {
                    val i = vm.siblings.indexOfFirst { it.path == entry.path }
                    if (i >= 0) " · ${i + 1} von ${vm.siblings.size}" else ""
                } else {
                    ""
                }
                Text(
                    subtitleOf(entry) + position,
                    color = colors.textSecondary,
                    style = type.footnote,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        if (entry != null && !entry.isDirectory) {
            Spacer(Modifier.width(Spacing.s))
            GlassCircleButton(icon = AetherIcons.Share, contentDescription = "Teilen", onClick = { actions.share(listOf(entry)) })
            Spacer(Modifier.width(Spacing.s))
            GlassCircleButton(icon = AetherIcons.More, contentDescription = "Weitere Aktionen", onClick = onMore)
        }
    }
}

internal fun subtitleOf(entry: FileEntry): String = listOfNotNull(
    entry.kind.label,
    ByteFormat.format(entry.sizeBytes.coerceAtLeast(0)),
    entry.modifiedMillis.takeIf { it > 0 }?.let { Fmt.fileDate(it, System.currentTimeMillis()) },
).joinToString(" · ")

@Composable
private fun MoreSheet(entry: FileEntry, onDismiss: () -> Unit) {
    val actions = fileActions
    fun then(block: () -> Unit) {
        onDismiss()
        block()
    }
    GlassSheet(onDismiss = onDismiss) {
        SheetHeader(title = entry.name, subtitle = subtitleOf(entry), leading = { FileThumbnail(entry, size = 48.dp) })
        Spacer(Modifier.height(Spacing.s))
        ActionGroup {
            if (entry.kind == FileKind.APK) {
                ActionRow("Installieren", AetherIcons.Download, onClick = { then { actions.install(entry) } })
                ActionDivider()
            }
            ActionRow("Öffnen mit …", AetherIcons.OpenExternal, onClick = { then { actions.openWith(entry) } })
            ActionDivider()
            ActionRow("Informationen", AetherIcons.Info, onClick = { then { actions.info(entry) } })
        }
        ActionGroup {
            ActionRow("Umbenennen", AetherIcons.Pencil, enabled = entry.writable, onClick = { then { actions.rename(entry) } })
            ActionDivider()
            ActionRow("Kopieren nach …", AetherIcons.Copy, onClick = { then { actions.copy(listOf(entry)) } })
            ActionDivider()
            ActionRow("Verschieben nach …", AetherIcons.MoveTo, enabled = entry.writable, onClick = { then { actions.move(listOf(entry)) } })
        }
        ActionGroup {
            ActionRow("In den Papierkorb legen", AetherIcons.Trash, destructive = true, enabled = entry.writable, onClick = { then { actions.trash(listOf(entry)) } })
            ActionDivider()
            ActionRow("Endgültig löschen …", AetherIcons.Trash, destructive = true, enabled = entry.writable, onClick = { then { actions.deletePermanently(listOf(entry)) } })
        }
    }
}
