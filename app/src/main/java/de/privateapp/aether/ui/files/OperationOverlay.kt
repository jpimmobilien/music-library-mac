package de.privateapp.aether.ui.files

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.clickable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import de.privateapp.aether.design.ActionDivider
import de.privateapp.aether.design.ActionGroup
import de.privateapp.aether.design.ActionRow
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.Backdrop
import de.privateapp.aether.design.CapacityBar
import de.privateapp.aether.design.GlassModal
import de.privateapp.aether.design.GlassSheet
import de.privateapp.aether.design.GlassSurface
import de.privateapp.aether.design.IconBadge
import de.privateapp.aether.design.MinTouchTarget
import de.privateapp.aether.design.Radii
import de.privateapp.aether.design.SelectionMark
import de.privateapp.aether.design.SheetHeader
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.design.Tone
import de.privateapp.aether.files.Conflict
import de.privateapp.aether.files.ConflictChoice
import de.privateapp.aether.files.FileEntry
import de.privateapp.aether.files.OperationPhase
import de.privateapp.aether.files.OperationProgress
import de.privateapp.aether.files.OperationTexts
import de.privateapp.aether.files.Resolution
import de.privateapp.aether.model.ByteFormat
import de.privateapp.aether.model.Fmt
import de.privateapp.aether.operations.JobStatus
import de.privateapp.aether.operations.OperationJob

/**
 * Über der Navigation: Fortschritt des laufenden Vorgangs (antippen = alle Vorgänge), Rückmeldungen nach einem
 * Vorgang und die Frage bei Namenskonflikten. [clearance] = Abstand vom unteren Rand (über der Reiterleiste).
 */
@Composable
fun BoxScope.OperationOverlay(actions: FileActions, backdrop: Backdrop, clearance: Dp) {
    val vm = actions.vm
    val jobs by vm.graph.operations.jobs.collectAsStateWithLifecycle()
    val active = jobs
    val current = active.firstOrNull { it.status != JobStatus.QUEUED } ?: active.firstOrNull()
    var showAll by remember { mutableStateOf(false) }

    Column(
        Modifier
            .align(Alignment.BottomCenter)
            .padding(start = Spacing.page, end = Spacing.page, bottom = clearance)
            .widthIn(max = 560.dp)
            .fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(Spacing.s),
    ) {
        val banner = vm.banner
        AnimatedVisibility(
            visible = banner != null,
            enter = fadeIn(Aether.motion.fade()) + slideInVertically(Aether.motion.standard()) { it / 2 },
            exit = fadeOut(Aether.motion.fade()) + slideOutVertically(Aether.motion.standard()) { it / 2 },
        ) {
            // Letzten Inhalt halten, während die Meldung ausblendet.
            val shown = remember { mutableStateOf(banner) }
            if (banner != null) shown.value = banner
            shown.value?.let { BannerCard(it, backdrop, onDismiss = vm::dismissBanner, onDetails = { r -> vm.dismissBanner(); vm.show(FileDialog.Failures(r)) }) }
        }
        AnimatedVisibility(
            visible = current != null,
            enter = fadeIn(Aether.motion.fade()) + slideInVertically(Aether.motion.standard()) { it / 2 },
            exit = fadeOut(Aether.motion.fade()) + slideOutVertically(Aether.motion.standard()) { it / 2 },
        ) {
            val shown = remember { mutableStateOf(current) }
            if (current != null) shown.value = current
            shown.value?.let { job ->
                ProgressCapsule(job, queued = (active.size - 1).coerceAtLeast(0), backdrop = backdrop, onOpen = { showAll = true }, onCancel = { vm.graph.operations.cancel(job.id) })
            }
        }
    }

    // Namenskonflikt: wartet auf die Entscheidung (der Vorgang hält so lange an).
    val waiting = active.firstOrNull { it.status == JobStatus.WAITING_FOR_DECISION && it.conflict != null }
    if (waiting != null) {
        ConflictSheet(
            job = waiting,
            conflict = waiting.conflict!!,
            onDecide = { vm.graph.operations.decide(waiting.id, it) },
            onCancelJob = { vm.graph.operations.cancel(waiting.id) },
        )
    }
    if (showAll && active.isNotEmpty()) {
        JobsSheet(active, onDismiss = { showAll = false }, onCancel = { vm.graph.operations.cancel(it) })
    } else if (showAll) {
        showAll = false
    }
}

@Composable
private fun BannerCard(b: Banner, backdrop: Backdrop, onDismiss: () -> Unit, onDetails: (de.privateapp.aether.files.OperationReport) -> Unit) {
    val colors = Aether.colors
    GlassSurface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(Radii.card), backdrop = backdrop) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(start = Spacing.l, end = Spacing.xs, top = Spacing.s, bottom = Spacing.s)
                .semantics { liveRegion = LiveRegionMode.Polite },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconBadge(if (b.isProblem) AetherIcons.Warning else AetherIcons.CheckCircle, tone = if (b.isProblem) Tone.WARNING else Tone.SUCCESS, size = 32.dp)
            Spacer(Modifier.width(Spacing.m))
            Column(Modifier.weight(1f)) {
                Text(b.headline, color = colors.text, style = Aether.type.bodyStrong, maxLines = 2, overflow = TextOverflow.Ellipsis)
                if (b.detail != null) Text(b.detail, color = colors.textSecondary, style = Aether.type.footnote, maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
            when {
                b.undo != null -> TextAction("Widerrufen", b.undo)
                b.report != null -> TextAction("Details") { onDetails(b.report) }
            }
            Box(
                Modifier.size(MinTouchTarget).clip(CircleShape).clickable(role = Role.Button, onClick = onDismiss).semantics { contentDescription = "Meldung schließen" },
                contentAlignment = Alignment.Center,
            ) {
                Icon(AetherIcons.Close, contentDescription = null, tint = colors.textTertiary, modifier = Modifier.size(16.dp))
            }
        }
    }
}

@Composable
private fun TextAction(text: String, onClick: () -> Unit) {
    Text(
        text,
        color = Aether.colors.accent,
        style = Aether.type.bodyStrong,
        modifier = Modifier
            .heightIn(min = MinTouchTarget)
            .clip(RoundedCornerShape(Radii.small))
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = Spacing.s, vertical = Spacing.m),
    )
}

/** Fortschritt als schwebende Kapsel: Titel, Balken, „1,2 GB von 4 GB · noch etwa 2 Min.“, Abbrechen. */
@Composable
private fun ProgressCapsule(job: OperationJob, queued: Int, backdrop: Backdrop, onOpen: () -> Unit, onCancel: () -> Unit) {
    val colors = Aether.colors
    val p = job.progress
    val eta = rememberEta(job.id, p)
    val line = progressLine(job, p, eta) + if (queued > 0) " · danach $queued weitere" else ""
    GlassSurface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(Radii.card), backdrop = backdrop) {
        Row(
            Modifier
                .fillMaxWidth()
                .clickable(role = Role.Button, onClickLabel = "Alle Vorgänge zeigen", onClick = onOpen)
                .padding(start = Spacing.l, end = Spacing.xs, top = Spacing.m, bottom = Spacing.m),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Kein Live-Bereich: Der Text ändert sich bis zu zehnmal je Sekunde und würde TalkBack überfluten. Den Abschluss
            // sagt die Rückmeldung an (dort Live-Bereich); den Stand liest man durch Antippen.
            Column(Modifier.weight(1f).semantics(mergeDescendants = true) { }) {
                Text(job.title, color = colors.text, style = Aether.type.bodyStrong, maxLines = 1, overflow = TextOverflow.MiddleEllipsis)
                Spacer(Modifier.height(Spacing.xs))
                CapacityBar(fraction = if (job.status == JobStatus.RUNNING) p?.fraction else null, height = 4.dp)
                Spacer(Modifier.height(Spacing.xs))
                Text(line, color = colors.textSecondary, style = Aether.type.caption, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Box(
                Modifier.size(MinTouchTarget).clip(CircleShape).clickable(role = Role.Button, onClick = onCancel).semantics { contentDescription = "Vorgang abbrechen" },
                contentAlignment = Alignment.Center,
            ) {
                Icon(AetherIcons.Close, contentDescription = null, tint = colors.textSecondary, modifier = Modifier.size(18.dp))
            }
        }
    }
}

private fun progressLine(job: OperationJob, p: OperationProgress?, etaMillis: Long?): String = when {
    job.status == JobStatus.WAITING_FOR_DECISION -> "Wartet auf deine Entscheidung"
    job.status == JobStatus.QUEUED -> "Wartet"
    p == null -> OperationPhase.PREPARING.label
    p.phase != OperationPhase.RUNNING -> p.phase.label
    p.totalBytes > 0 -> "${ByteFormat.format(p.completedBytes)} von ${ByteFormat.format(p.totalBytes)}" + (etaMillis?.let { if (it < 60_000L) " · noch unter 1 Min." else " · noch etwa ${Fmt.duration(it)}" } ?: "")
    p.totalItems > 0 -> OperationTexts.progressItems(p.completedItems, p.totalItems)
    else -> p.phase.label
}

/**
 * Restdauer aus dem bisherigen Durchsatz – erst nach 3 s und mindestens 2 % Fortschritt, vorher wäre sie geraten.
 * Ausdrücklich „etwa“: Kleine Dateien kopieren langsamer als große, SD-Karten schwanken.
 */
@Composable
private fun rememberEta(jobId: Long, p: OperationProgress?): Long? {
    var startMillis by remember(jobId) { mutableLongStateOf(0L) }
    var startBytes by remember(jobId) { mutableLongStateOf(0L) }
    LaunchedEffect(jobId, p?.phase) {
        if (p?.phase == OperationPhase.RUNNING) {
            startMillis = System.currentTimeMillis()
            startBytes = p.completedBytes
        }
    }
    if (p == null || p.phase != OperationPhase.RUNNING || p.totalBytes <= 0 || startMillis == 0L) return null
    val elapsed = System.currentTimeMillis() - startMillis
    val done = p.completedBytes - startBytes
    if (elapsed < 3_000L || done <= 0 || p.completedBytes < p.totalBytes / 50) return null
    val rate = done.toDouble() / elapsed
    return ((p.totalBytes - p.completedBytes) / rate).toLong().coerceAtLeast(0)
}

@Composable
private fun JobsSheet(jobs: List<OperationJob>, onDismiss: () -> Unit, onCancel: (Long) -> Unit) {
    val colors = Aether.colors
    GlassSheet(onDismiss = onDismiss) {
        SheetHeader(title = "Vorgänge", subtitle = "Laufen nacheinander – so kommen sich zwei Vorgänge nie in die Quere.")
        Spacer(Modifier.height(Spacing.s))
        ActionGroup {
            jobs.forEachIndexed { i, job ->
                if (i > 0) ActionDivider()
                Row(Modifier.fillMaxWidth().padding(start = Spacing.l, end = Spacing.xs, top = Spacing.s, bottom = Spacing.s), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(job.title, color = colors.text, style = Aether.type.bodyStrong, maxLines = 2, overflow = TextOverflow.MiddleEllipsis)
                        Text(progressLine(job, job.progress, null), color = colors.textSecondary, style = Aether.type.footnote)
                        if (job.status == JobStatus.RUNNING) {
                            Spacer(Modifier.height(Spacing.xs))
                            CapacityBar(fraction = job.progress?.fraction, height = 4.dp)
                        }
                    }
                    Box(
                        Modifier.size(MinTouchTarget).clip(CircleShape).clickable(role = Role.Button) { onCancel(job.id) }.semantics { contentDescription = "„${job.title}“ abbrechen" },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(AetherIcons.Close, contentDescription = null, tint = colors.textSecondary, modifier = Modifier.size(18.dp))
                    }
                }
            }
        }
    }
}

/**
 * „„Foto.jpg“ ist bereits vorhanden“ – mit beiden Ständen im Vergleich (Größe, Änderungsdatum), damit man nicht
 * blind entscheidet. „Für alle weiteren“ übernimmt die Wahl für den Rest des Vorgangs.
 */
@Composable
private fun ConflictSheet(job: OperationJob, conflict: Conflict, onDecide: (Resolution) -> Unit, onCancelJob: () -> Unit) {
    val colors = Aether.colors
    var applyToAll by remember(job.id, conflict) { mutableStateOf(false) }
    val bothFolders = conflict.source.isDirectory && conflict.existing.isDirectory
    val bothFiles = !conflict.source.isDirectory && !conflict.existing.isDirectory
    GlassModal(onDismiss = {}, dismissible = false) {
        SheetHeader(
            title = "„${conflict.existing.name}“ ist bereits vorhanden",
            subtitle = "Beim Vorgang „${job.title}“. Was soll geschehen?",
        )
        Spacer(Modifier.height(Spacing.s))
        CompareRow("Bereits im Ziel", conflict.existing)
        CompareRow("Neu", conflict.source)
        if (!bothFolders && !bothFiles) {
            Spacer(Modifier.height(Spacing.xs))
            Text(
                "Ein Ordner und eine Datei mit demselben Namen: Ersetzen ist hier nicht möglich – ORBIT löscht nie einen Ordner, um Platz zu machen.",
                color = colors.textSecondary,
                style = Aether.type.footnote,
            )
        }
        Spacer(Modifier.height(Spacing.s))
        // Angeboten wird nur, was die Engine bei dieser Kombination wirklich tut (Ordner werden nie ersetzt, nur
        // zusammengeführt; Datei gegen Ordner nur „Beide behalten“ oder „Überspringen“).
        ActionGroup {
            if (bothFolders) {
                ActionRow("Zusammenführen", AetherIcons.Layers, detail = "Inhalte vereinen", onClick = { onDecide(Resolution(ConflictChoice.MERGE, applyToAll)) })
                ActionDivider()
            }
            ActionRow("Beide behalten", AetherIcons.Copy, detail = "Neue erhält einen Zusatz", onClick = { onDecide(Resolution(ConflictChoice.KEEP_BOTH, applyToAll)) })
            ActionDivider()
            ActionRow("Überspringen", AetherIcons.ChevronRight, onClick = { onDecide(Resolution(ConflictChoice.SKIP, applyToAll)) })
            if (bothFiles) {
                ActionDivider()
                ActionRow(
                    "Ersetzen",
                    AetherIcons.Refresh,
                    detail = "Erst wenn die neue fertig ist",
                    destructive = true,
                    onClick = { onDecide(Resolution(ConflictChoice.REPLACE, applyToAll)) },
                )
            }
        }
        Row(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(Radii.control))
                // Als Kontrollkästchen mit Zustand – TalkBack sagt „aktiviert/nicht aktiviert“.
                .toggleable(value = applyToAll, role = Role.Checkbox, onValueChange = { applyToAll = it })
                .padding(vertical = Spacing.m, horizontal = Spacing.xs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SelectionMark(applyToAll, size = 22.dp)
            Spacer(Modifier.width(Spacing.m))
            Text("Für alle weiteren Konflikte übernehmen", color = colors.text, style = Aether.type.body)
        }
        ActionGroup {
            ActionRow("Vorgang abbrechen", AetherIcons.Close, destructive = true, onClick = onCancelJob)
        }
    }
}

@Composable
private fun CompareRow(label: String, entry: FileEntry) {
    val colors = Aether.colors
    Row(Modifier.fillMaxWidth().padding(vertical = Spacing.xs), verticalAlignment = Alignment.CenterVertically) {
        FileThumbnail(entry, size = 40.dp)
        Spacer(Modifier.width(Spacing.m))
        Column(Modifier.weight(1f)) {
            Text(label, color = colors.textSecondary, style = Aether.type.caption)
            Text(
                listOfNotNull(
                    if (entry.isDirectory) "Ordner" else ByteFormat.format(entry.sizeBytes),
                    entry.modifiedMillis.takeIf { it > 0 }?.let { "geändert ${Fmt.dateTime(it)}" },
                ).joinToString(" · "),
                color = colors.text,
                style = Aether.type.footnote,
            )
        }
    }
}

