package de.privateapp.aether.ui.files

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.GlassSheet
import de.privateapp.aether.design.GlassTextField
import de.privateapp.aether.design.IconBadge
import de.privateapp.aether.design.MinTouchTarget
import de.privateapp.aether.design.PillButton
import de.privateapp.aether.design.Radii
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.files.DirectoryReader
import de.privateapp.aether.files.FileEntry
import de.privateapp.aether.files.FileNames
import de.privateapp.aether.files.FileOperation
import de.privateapp.aether.files.FileSorting
import de.privateapp.aether.files.Listing
import de.privateapp.aether.files.OperationTexts
import de.privateapp.aether.files.Resolution
import de.privateapp.aether.model.storage.VolumeKind
import de.privateapp.aether.platform.storage.BrowseRoot
import de.privateapp.aether.platform.storage.VolumeRoots
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Ziel wählen (Kopieren, Verschieben, Entpacken): durch Speicher und Ordner tippen, bei Bedarf einen Ordner anlegen,
 * „Hierher …“. Ziele, die nicht gehen, sind gesperrt und sagen warum (Ordner in sich selbst, schon dort, nur lesbar).
 */
@Composable
fun DestinationPicker(d: FileDialog.Pick, actions: FileActions) {
    val graph = actions.vm.graph
    val colors = Aether.colors
    val type = Aether.type
    val scope = rememberCoroutineScope()
    val roots by produceState(emptyList<BrowseRoot>()) { value = withContext(Dispatchers.IO) { graph.volumeRoots.list() } }
    // null = Übersicht der Speicher.
    var current by rememberSaveable { mutableStateOf<String?>(d.startDir) }
    var reloadToken by remember { mutableStateOf(0) }
    var creating by remember { mutableStateOf(false) }

    val here = current
    // Ordner und Schreibrecht des Ziels werden außerhalb des Hauptthreads gelesen.
    val listing by produceState<PickListing?>(null, here, reloadToken) {
        value = null
        value = if (here == null) {
            PickListing(emptyList(), writable = false)
        } else {
            withContext(Dispatchers.IO) {
                val found = when (val l = DirectoryReader.list(here, includeHidden = false)) {
                    is Listing.Entries -> FileSorting.sorted(l.entries.filter { it.isDirectory }, de.privateapp.aether.files.SortOrder())
                    else -> emptyList()
                }
                PickListing(found, writable = File(here).canWrite())
            }
        }
    }
    val currentListing = listing
    val folders = currentListing?.folders
    val root = here?.let { VolumeRoots.rootFor(it, roots) }
    val problem = if (here == null || currentListing == null) null else targetProblem(d, here, root, currentListing.writable)

    GlassSheet(onDismiss = actions.vm::dismissDialog, scrollable = false) {
        Column(Modifier.fillMaxWidth().fillMaxHeight(0.88f)) {
            // Kopf: was, wohin
            Row(Modifier.fillMaxWidth().padding(vertical = Spacing.s), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(d.purpose.title, color = colors.text, style = type.title2, modifier = Modifier.semantics { heading() })
                    Text(
                        d.entries.singleOrNull()?.let { "„${it.name}“" } ?: OperationTexts.items(d.entries.size),
                        color = colors.textSecondary,
                        style = type.footnote,
                        maxLines = 1,
                        overflow = TextOverflow.MiddleEllipsis,
                    )
                }
                PillButton("Abbrechen", onClick = actions.vm::dismissDialog)
            }
            // Ort
            Row(Modifier.fillMaxWidth().padding(vertical = Spacing.xs), verticalAlignment = Alignment.CenterVertically) {
                if (here != null) {
                    val parent = here.substringBeforeLast('/', "")
                    val atRoot = root != null && root.path == here
                    Box(
                        Modifier
                            .size(MinTouchTarget)
                            .clip(CircleShape)
                            .clickable(role = Role.Button) { current = if (atRoot || parent.isEmpty()) null else parent }
                            .semantics { contentDescription = "Zurück" },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(AetherIcons.ChevronLeft, contentDescription = null, tint = colors.accent, modifier = Modifier.size(22.dp))
                    }
                }
                Text(
                    if (here == null) "Speicherorte" else FolderViewModel.title(here, root),
                    color = colors.text,
                    style = type.headline,
                    modifier = Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            if (here != null) {
                PathBar(FolderViewModel.segments(here, root), onSelect = { current = it })
            }
            Spacer(Modifier.height(Spacing.s))

            // Liste
            Box(
                Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(Radii.control))
                    .background(colors.fill),
            ) {
                if (here == null) {
                    LazyColumn(Modifier.fillMaxWidth()) {
                        items(roots, key = { it.path }) { r -> RootRow(r) { current = r.path } }
                    }
                } else {
                    val list = folders
                    when {
                        list == null -> Unit
                        list.isEmpty() -> Text(
                            "Keine Unterordner",
                            color = colors.textTertiary,
                            style = type.callout,
                            modifier = Modifier.align(Alignment.Center).padding(Spacing.xl),
                        )
                        else -> LazyColumn(Modifier.fillMaxWidth()) {
                            items(list, key = { it.path }) { f ->
                                val blocked = d.entries.any { s -> s.isDirectory && (f.path == s.path || f.path.startsWith(s.path + "/")) }
                                FolderPickRow(f, enabled = !blocked) { current = f.path }
                            }
                        }
                    }
                }
            }

            // Neuer Ordner (eingeklappt)
            if (creating && here != null) {
                NewFolderInline(
                    parentDir = here,
                    onCancel = { creating = false },
                    onCreate = { name ->
                        scope.launch {
                            val report = graph.engine.run(FileOperation.CreateFolder(here, name), resolver = { Resolution(de.privateapp.aether.files.ConflictChoice.SKIP) })
                            creating = false
                            val created = report.createdPaths.firstOrNull()
                            if (created != null) current = created else reloadToken++
                            if (report.failures.isNotEmpty()) actions.vm.note("Ordner nicht erstellt", report.failures.first().reason.message)
                        }
                    },
                )
            }

            // Bestätigen
            Spacer(Modifier.height(Spacing.m))
            if (problem != null) {
                Text(problem, color = colors.textSecondary, style = type.footnote, modifier = Modifier.padding(bottom = Spacing.s))
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Spacing.s)) {
                PillButton(
                    "Neuer Ordner",
                    onClick = { creating = true },
                    icon = AetherIcons.FolderPlus,
                    enabled = here != null && root?.readOnly != true && !creating,
                )
                Spacer(Modifier.weight(1f))
                PillButton(
                    d.purpose.confirm,
                    onClick = { if (here != null) confirm(d, here, actions) },
                    primary = true,
                    enabled = here != null && listing != null && problem == null,
                )
            }
        }
    }
}

private fun confirm(d: FileDialog.Pick, target: String, actions: FileActions) {
    val sources = d.entries.map { it.path }
    when (d.purpose) {
        PickPurpose.COPY -> actions.vm.submit(FileOperation.Copy(sources, target))
        PickPurpose.MOVE -> actions.vm.submit(FileOperation.Move(sources, target))
        PickPurpose.EXTRACT -> actions.vm.submit(FileOperation.Extract(sources.first(), target))
    }
}

private class PickListing(val folders: List<FileEntry>, val writable: Boolean)

/** Warum [target] als Ziel nicht geht – oder `null`. */
private fun targetProblem(d: FileDialog.Pick, target: String, root: BrowseRoot?, writable: Boolean): String? {
    if (root?.readOnly == true) return "Dieser Speicher ist nur lesbar."
    if (!writable) return "In diesen Ordner darf nicht geschrieben werden."
    for (s in d.entries) {
        if (s.isDirectory && (target == s.path || target.startsWith(s.path + "/"))) return "Ein Ordner kann nicht in sich selbst ${if (d.purpose == PickPurpose.MOVE) "verschoben" else "kopiert"} werden."
    }
    if (d.purpose == PickPurpose.MOVE && d.entries.all { it.parentPath == target }) return "Liegt bereits hier."
    return null
}

@Composable
private fun RootRow(root: BrowseRoot, onClick: () -> Unit) {
    val colors = Aether.colors
    val icon = when (root.kind) {
        VolumeKind.INTERNAL -> AetherIcons.Phone
        VolumeKind.SD_CARD -> AetherIcons.SdCard
        VolumeKind.USB -> AetherIcons.Usb
        else -> AetherIcons.Drive
    }
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = Spacing.l, vertical = Spacing.s),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconBadge(icon, size = 32.dp)
        Spacer(Modifier.width(Spacing.m))
        Column(Modifier.weight(1f)) {
            Text(FolderViewModel.rootLabel(root), color = colors.text, style = Aether.type.bodyStrong)
            if (root.readOnly) Text("Nur lesbar", color = colors.textSecondary, style = Aether.type.footnote)
        }
        Icon(AetherIcons.ChevronRight, contentDescription = null, tint = colors.textTertiary, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun FolderPickRow(folder: FileEntry, enabled: Boolean, onClick: () -> Unit) {
    val colors = Aether.colors
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = Spacing.l, vertical = Spacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(AetherIcons.Folder, contentDescription = null, tint = if (enabled) colors.accent else colors.textDisabled, modifier = Modifier.size(24.dp))
        Spacer(Modifier.width(Spacing.m))
        Text(
            folder.name,
            color = if (enabled) colors.text else colors.textDisabled,
            style = Aether.type.body,
            modifier = Modifier.weight(1f),
            maxLines = 1,
            overflow = TextOverflow.MiddleEllipsis,
        )
        if (enabled) Icon(AetherIcons.ChevronRight, contentDescription = null, tint = colors.textTertiary, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun NewFolderInline(parentDir: String, onCancel: () -> Unit, onCreate: (String) -> Unit) {
    var value by remember { mutableStateOf(TextFieldValue("Neuer Ordner")) }
    // Freien Namen („Neuer Ordner 2“) im Hintergrund ermitteln; übernehmen, solange nichts getippt wurde.
    androidx.compose.runtime.LaunchedEffect(parentDir) {
        val free = withContext(Dispatchers.IO) {
            val names = File(parentDir).list()?.map { it.lowercase() }?.toSet().orEmpty()
            FileNames.uniqueName("Neuer Ordner", isDirectory = true) { it.lowercase() in names }
        }
        if (value.text == "Neuer Ordner") value = TextFieldValue(free)
    }
    val name = value.text.trim()
    val problem = FileNames.validate(name)?.message
    Column(Modifier.fillMaxWidth().padding(top = Spacing.m)) {
        GlassTextField(
            value = value,
            onValueChange = { value = it },
            label = "Name des neuen Ordners",
            leadingIcon = AetherIcons.FolderPlus,
            error = if (name.isEmpty()) null else problem,
            imeAction = ImeAction.Done,
            onImeAction = { if (problem == null) onCreate(name) },
        )
        Row(Modifier.fillMaxWidth().padding(top = Spacing.s), horizontalArrangement = Arrangement.spacedBy(Spacing.s)) {
            Spacer(Modifier.weight(1f))
            PillButton("Abbrechen", onClick = onCancel)
            PillButton("Erstellen", onClick = { onCreate(name) }, primary = true, enabled = problem == null)
        }
    }
}
