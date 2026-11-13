package de.privateapp.aether.ui.files

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextOverflow
import de.privateapp.aether.design.ActionDivider
import de.privateapp.aether.design.ActionGroup
import de.privateapp.aether.design.ActionRow
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.GlassDialog
import de.privateapp.aether.design.GlassSheet
import de.privateapp.aether.design.GlassTextField
import de.privateapp.aether.design.SheetHeader
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.files.FileEntry
import de.privateapp.aether.files.FileKind
import de.privateapp.aether.files.FileNames
import de.privateapp.aether.files.FileOperation
import de.privateapp.aether.files.FileTypes
import de.privateapp.aether.files.OperationReport
import de.privateapp.aether.files.OperationTexts
import de.privateapp.aether.files.TrashedItem
import de.privateapp.aether.model.ByteFormat
import de.privateapp.aether.navigation.LocalAppNavigator
import de.privateapp.aether.navigation.Route
import de.privateapp.aether.ui.files.info.FileInfoSheet
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Zeigt, was die [FileActions] gerade brauchen: Aktionsblatt, Umbenennen, Neuer Ordner, Bestätigungen, Ziel-Auswahl,
 * Informationen. Hält außerdem die Navigation aktuell, wenn geöffnete Ordner umbenannt, verschoben oder gelöscht
 * wurden.
 */
@Composable
fun FileActionsHost(actions: FileActions) {
    val vm = actions.vm
    val navigator = LocalAppNavigator.current
    LaunchedEffect(vm) {
        vm.finished.collect { report ->
            // Was es wirklich nicht mehr gibt, prüft das Dateisystem – außerhalb des Hauptthreads (bis zu Tausende Pfade).
            val gone = withContext(Dispatchers.IO) { report.removedPaths.filter { !File(it).exists() } }
            followOpenPages(report, navigator, gone)
        }
    }
    when (val d = vm.dialog) {
        null -> Unit
        is FileDialog.Actions -> ActionsSheet(d.entries, actions)
        is FileDialog.Rename -> RenameDialog(d.entry, actions)
        is FileDialog.NewFolder -> NewFolderDialog(d.parentDir, d.suggestedName, actions)
        is FileDialog.ConfirmDelete -> ConfirmDeleteDialog(d.entries, actions)
        is FileDialog.ConfirmDeleteFromTrash -> ConfirmDeleteFromTrashDialog(d.items, d.emptiesTrash, actions)
        is FileDialog.Compress -> CompressDialog(d, actions)
        is FileDialog.Pick -> DestinationPicker(d, actions)
        is FileDialog.Info -> FileInfoSheet(vm.graph, d.entry, onDismiss = vm::dismissDialog)
        is FileDialog.InstallPermission -> GlassDialog(
            title = "Installation erlauben",
            message = "Android fragt einmalig, ob ORBIT App-Pakete an den Installer übergeben darf. Schalte dazu in der folgenden Seite „Aus dieser Quelle zulassen“ ein und kehre zurück. Vor jeder Installation zeigt Android Name und Berechtigungen der App und fragt erneut.",
            icon = AetherIcons.FilePackage,
            onDismiss = vm::dismissDialog,
            confirmText = "Einstellungen öffnen",
            onConfirm = actions::openInstallSettings,
        )
        is FileDialog.Failures -> FailuresSheet(d.report, onDismiss = vm::dismissDialog)
    }
}

/** Seiten von umbenannten/verschobenen Ordnern folgen dem neuen Ort; gelöschte schließen sich. */
private fun followOpenPages(report: OperationReport, navigator: de.privateapp.aether.navigation.AppNavigator, gone: List<String>) {
    when (val op = report.operation) {
        is FileOperation.Rename -> report.createdPaths.firstOrNull()?.let { navigator.remapPaths(op.source, it) }
        is FileOperation.Move -> op.sources.forEach { src ->
            val target = op.targetDir.trimEnd('/') + "/" + src.substringAfterLast('/')
            if (src in report.removedPaths && target in report.createdPaths) navigator.remapPaths(src, target)
        }
        else -> Unit
    }
    if (gone.isNotEmpty()) {
        navigator.closeWhere { route ->
            val p = when (route) {
                is Route.Folder -> route.path
                // Bilder blättern in ihrem Ordner weiter (die Schnellansicht zeigt das nächste) – nur andere schließen.
                is Route.Preview -> route.path.takeIf { FileTypes.kindOf(it.substringAfterLast('/'), isDirectory = false) != FileKind.IMAGE }
                else -> null
            }
            p != null && gone.any { g -> p == g || p.startsWith("$g/") }
        }
    }
}

// --- Aktionsblatt ---------------------------------------------------------------------------------------------------

@Composable
private fun ActionsSheet(entries: List<FileEntry>, actions: FileActions) {
    val vm = actions.vm
    val single = entries.singleOrNull()
    val files = entries.filter { !it.isDirectory }
    val prefs by vm.graph.filesPrefs.collectAsStateWithLifecycle()
    GlassSheet(onDismiss = vm::dismissDialog) {
        if (single != null) {
            SheetHeader(
                title = single.name,
                subtitle = if (single.isDirectory) "Ordner" else "${single.kind.label} · ${ByteFormat.format(single.sizeBytes)}",
                leading = { FileThumbnail(single, size = 48.dp) },
            )
        } else {
            SheetHeader(
                title = OperationTexts.items(entries.size),
                subtitle = listOfNotNull(
                    files.size.takeIf { it > 0 }?.let { if (it == 1) "1 Datei" else "$it Dateien" },
                    (entries.size - files.size).takeIf { it > 0 }?.let { if (it == 1) "1 Ordner" else "$it Ordner" },
                    files.sumOf { it.sizeBytes }.takeIf { it > 0 }?.let { ByteFormat.format(it) },
                ).joinToString(" · "),
            )
        }
        Spacer(Modifier.height(Spacing.s))
        ActionGroup {
            if (single != null && !single.isDirectory) {
                ActionRow("Öffnen", AetherIcons.OpenExternal, onClick = { vm.dismissDialog(); actions.open(single) })
                ActionDivider()
                ActionRow("Öffnen mit …", AetherIcons.OpenExternal, onClick = { actions.openWith(single) })
                ActionDivider()
            }
            if (single != null && single.kind == FileKind.APK) {
                ActionRow("Installieren", AetherIcons.Download, onClick = { actions.install(single) })
                ActionDivider()
            }
            ActionRow("Teilen", AetherIcons.Share, enabled = files.isNotEmpty(), onClick = { actions.share(entries) })
            if (single != null) {
                ActionDivider()
                ActionRow("Informationen", AetherIcons.Info, onClick = { actions.info(single) })
            }
        }
        ActionGroup {
            if (single != null) {
                ActionRow("Umbenennen", AetherIcons.Pencil, enabled = single.writable, onClick = { actions.rename(single) })
                ActionDivider()
            }
            ActionRow("Kopieren nach …", AetherIcons.Copy, onClick = { actions.copy(entries) })
            ActionDivider()
            ActionRow("Verschieben nach …", AetherIcons.MoveTo, enabled = entries.all { it.writable }, onClick = { actions.move(entries) })
            ActionDivider()
            ActionRow("Duplizieren", AetherIcons.Layers, onClick = { vm.dismissDialog(); actions.duplicate(entries) })
            ActionDivider()
            ActionRow("Komprimieren", AetherIcons.FileArchive, onClick = { actions.compress(entries) })
            if (single != null && single.kind == FileKind.ARCHIVE && single.extension == "zip") {
                ActionDivider()
                ActionRow("Entpacken", AetherIcons.Extract, onClick = { vm.dismissDialog(); actions.extractHere(single) })
                ActionDivider()
                ActionRow("Entpacken nach …", AetherIcons.Extract, onClick = { actions.extractTo(single) })
            }
            if (single != null && single.isDirectory) {
                val favorite = prefs?.favorites?.contains(single.path) == true
                ActionDivider()
                ActionRow(
                    if (favorite) "Aus Favoriten entfernen" else "Zu Favoriten",
                    if (favorite) AetherIcons.StarFilled else AetherIcons.Star,
                    onClick = { actions.toggleFavorite(single.path) },
                )
            }
        }
        ActionGroup {
            ActionRow("In den Papierkorb legen", AetherIcons.Trash, destructive = true, enabled = entries.all { it.writable }, onClick = {
                vm.dismissDialog()
                actions.trash(entries)
            })
            ActionDivider()
            ActionRow("Endgültig löschen …", AetherIcons.Trash, destructive = true, enabled = entries.all { it.writable }, onClick = { actions.deletePermanently(entries) })
        }
    }
}

// --- Umbenennen / Neuer Ordner / Komprimieren -------------------------------------------------------------------

/**
 * Name eingeben mit sofortiger Prüfung: verbotene Zeichen, Länge, bereits vorhanden (ohne Rücksicht auf
 * Groß-/Kleinschreibung – so behandelt Android den gemeinsamen Speicher).
 */
@Composable
private fun NameDialog(
    title: String,
    message: String?,
    initial: String,
    selectStem: Boolean,
    confirmText: String,
    parentDir: String,
    ownName: String?,
    suffix: String = "",
    extensionWarning: (String) -> String? = { null },
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit,
) {
    val stemEnd = if (selectStem) initial.length - FileTypes.extensionOf(initial).let { if (it.isEmpty()) 0 else it.length + 1 } else initial.length
    var field by remember { mutableStateOf(TextFieldValue(initial, TextRange(0, stemEnd.coerceAtLeast(0)))) }
    val focus = remember { FocusRequester() }
    val name = field.text.trim()
    // „urlaub.zip“ eingetippt → nicht „urlaub.zip.zip“.
    val full = if (suffix.isNotEmpty() && name.endsWith(suffix, ignoreCase = true)) name else name + suffix
    // Der gemeinsame Speicher unterscheidet nicht zwischen Groß- und Kleinschreibung: „foto.jpg“ belegt auch
    // „Foto.JPG“. Nur das Objekt selbst darf so heißen (reine Änderung der Schreibweise ist erlaubt).
    val taken by produceState(false, full, parentDir) {
        value = full.isNotEmpty() && withContext(Dispatchers.IO) {
            val existing = File(parentDir).list()?.firstOrNull { it.equals(full, ignoreCase = true) }
            existing != null && existing != ownName
        }
    }
    val problem = FileNames.validate(full)?.message ?: if (taken) "„$full“ gibt es hier bereits." else null
    val unchanged = ownName != null && full == ownName
    val warning = if (problem == null && !unchanged) extensionWarning(full) else null
    GlassDialog(
        title = title,
        message = message,
        onDismiss = onDismiss,
        confirmText = if (warning != null) "Endung ändern" else confirmText,
        confirmEnabled = problem == null && name.isNotEmpty() && !unchanged,
        onConfirm = { onConfirm(full) },
    ) {
        GlassTextField(
            value = field,
            onValueChange = { field = it },
            label = "Name",
            error = if (name.isEmpty()) null else problem,
            imeAction = ImeAction.Done,
            onImeAction = { if (problem == null && name.isNotEmpty() && !unchanged) onConfirm(full) },
            focusRequester = focus,
            onClear = { field = TextFieldValue("") },
        )
        if (suffix.isNotEmpty()) {
            Text("Wird gespeichert als „$full“", color = Aether.colors.textTertiary, style = Aether.type.footnote, maxLines = 2, overflow = TextOverflow.MiddleEllipsis)
        }
        if (warning != null) {
            Spacer(Modifier.height(Spacing.s))
            Text(warning, color = Aether.colors.warning, style = Aether.type.footnote)
        }
        // Im Dialog selbst (eigenes Fenster): erst dort ist das Feld angebunden, dann öffnet sich die Tastatur.
        LaunchedEffect(Unit) {
            try {
                focus.requestFocus()
            } catch (e: IllegalStateException) {
                // Feld noch nicht angebunden – dann ohne automatische Tastatur.
            }
        }
    }
}

@Composable
private fun RenameDialog(entry: FileEntry, actions: FileActions) {
    val oldExt = if (entry.isDirectory) "" else FileTypes.extensionOf(entry.name)
    NameDialog(
        title = "Umbenennen",
        message = null,
        initial = entry.name,
        selectStem = !entry.isDirectory,
        confirmText = "Umbenennen",
        parentDir = entry.parentPath,
        ownName = entry.name,
        extensionWarning = { newName ->
            val newExt = FileTypes.extensionOf(newName)
            when {
                entry.isDirectory || newExt == oldExt -> null
                oldExt.isEmpty() -> "Die Datei bekommt die Endung „.$newExt“. Andere Apps erkennen sie dann als diesen Typ."
                newExt.isEmpty() -> "Die Endung „.$oldExt“ wird entfernt – andere Apps erkennen die Datei dann eventuell nicht mehr."
                else -> "Die Endung ändert sich von „.$oldExt“ zu „.$newExt“. Der Inhalt der Datei wird dabei nicht umgewandelt."
            }
        },
        onDismiss = actions.vm::dismissDialog,
        onConfirm = { actions.vm.submit(FileOperation.Rename(entry.path, it)) },
    )
}

@Composable
private fun NewFolderDialog(parentDir: String, initial: String, actions: FileActions) {
    NameDialog(
        title = "Neuer Ordner",
        message = null,
        initial = initial,
        selectStem = false,
        confirmText = "Erstellen",
        parentDir = parentDir,
        ownName = null,
        onDismiss = actions.vm::dismissDialog,
        onConfirm = { actions.vm.submit(FileOperation.CreateFolder(parentDir, it)) },
    )
}

@Composable
private fun CompressDialog(d: FileDialog.Compress, actions: FileActions) {
    val initial = d.suggestedName
    NameDialog(
        title = "Komprimieren",
        message = "${OperationTexts.items(d.entries.size)} werden zu einem ZIP-Archiv im selben Ordner. Die Originale bleiben unverändert.",
        initial = initial,
        selectStem = false,
        confirmText = "Komprimieren",
        parentDir = d.targetDir,
        ownName = null,
        suffix = ".zip",
        onDismiss = actions.vm::dismissDialog,
        onConfirm = { full -> actions.vm.submit(FileOperation.Compress(d.entries.map { it.path }, d.targetDir, full)) },
    )
}

// --- Bestätigungen --------------------------------------------------------------------------------------------------

@Composable
private fun ConfirmDeleteDialog(entries: List<FileEntry>, actions: FileActions) {
    val subject = entries.singleOrNull()?.let { "„${it.name}“" } ?: OperationTexts.items(entries.size)
    GlassDialog(
        title = "$subject endgültig löschen?",
        message = "Das lässt sich nicht widerrufen – auch nicht über den Papierkorb." +
            if (entries.any { it.isDirectory }) " Ordner werden mit ihrem gesamten Inhalt gelöscht." else "",
        icon = AetherIcons.Trash,
        destructive = true,
        onDismiss = actions.vm::dismissDialog,
        confirmText = "Endgültig löschen",
        onConfirm = { actions.vm.submit(FileOperation.DeletePermanently(entries.map { it.path })) },
    )
}

@Composable
private fun ConfirmDeleteFromTrashDialog(items: List<TrashedItem>, emptiesTrash: Boolean, actions: FileActions) {
    val subject = items.singleOrNull()?.let { "„${it.name}“" } ?: OperationTexts.items(items.size)
    val bytes = items.sumOf { it.sizeBytes }
    GlassDialog(
        title = if (emptiesTrash) "Papierkorb leeren?" else "$subject endgültig löschen?",
        message = (if (emptiesTrash) "${OperationTexts.items(items.size)} (${ByteFormat.format(bytes)}) werden endgültig gelöscht. " else "") +
            "Das lässt sich nicht widerrufen.",
        icon = AetherIcons.Trash,
        destructive = true,
        onDismiss = actions.vm::dismissDialog,
        confirmText = if (emptiesTrash) "Papierkorb leeren" else "Endgültig löschen",
        onConfirm = { actions.vm.submit(FileOperation.DeleteFromTrash(items)) },
    )
}

@Composable
private fun FailuresSheet(report: OperationReport, onDismiss: () -> Unit) {
    val colors = Aether.colors
    val summary = OperationTexts.summary(report)
    GlassSheet(onDismiss = onDismiss) {
        SheetHeader(title = summary.headline, subtitle = summary.detail)
        Spacer(Modifier.height(Spacing.s))
        ActionGroup {
            report.failures.take(200).forEachIndexed { i, f ->
                if (i > 0) ActionDivider()
                Column(Modifier.padding(horizontal = Spacing.l, vertical = Spacing.s)) {
                    Text(f.path.substringAfterLast('/'), color = colors.text, style = Aether.type.bodyStrong, maxLines = 1, overflow = TextOverflow.MiddleEllipsis)
                    Text(f.reason.message + (f.detail?.let { " ($it)" } ?: ""), color = colors.textSecondary, style = Aether.type.footnote)
                    Text(displayParent(f.path), color = colors.textTertiary, style = Aether.type.caption, maxLines = 1, overflow = TextOverflow.StartEllipsis)
                }
            }
        }
        if (report.failures.size > 200) {
            Text("… und ${report.failures.size - 200} weitere", color = colors.textSecondary, style = Aether.type.footnote)
        }
    }
}
