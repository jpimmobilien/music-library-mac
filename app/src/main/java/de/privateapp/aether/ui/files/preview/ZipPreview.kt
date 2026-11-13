package de.privateapp.aether.ui.files.preview

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.Hairline
import de.privateapp.aether.design.InfoRow
import de.privateapp.aether.design.Notice
import de.privateapp.aether.design.Panel
import de.privateapp.aether.design.PanelHeader
import de.privateapp.aether.design.PillButton
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.design.Tone
import de.privateapp.aether.files.FileEntry
import de.privateapp.aether.files.FileTypes
import de.privateapp.aether.files.ZipContents
import de.privateapp.aether.files.ZipEntryInfo
import de.privateapp.aether.model.ByteFormat
import de.privateapp.aether.model.Fmt
import de.privateapp.aether.ui.files.fileActions
import de.privateapp.aether.ui.files.icon

/**
 * ZIP-Archiv: Inhaltsverzeichnis ohne zu entpacken – Anzahl, Größe entpackt/gepackt, Warnungen (unsichere Pfade,
 * Verschlüsselung, nicht unterstützte Verfahren, zu wenig Platz) und Entpacken hierher oder an einen anderen Ort.
 */
@Composable
internal fun ZipPreview(vm: PreviewViewModel, entry: FileEntry, bottomPadding: Dp) {
    val actions = fileActions
    val colors = Aether.colors
    when (val z = vm.zip) {
        null -> Text("Inhalt wird gelesen …", color = colors.textTertiary, style = Aether.type.callout, modifier = Modifier.padding(Spacing.xl))
        ZipContents.NotFound -> FallbackPreview(entry, bottomPadding, message = "Das Archiv ist nicht mehr vorhanden.")
        ZipContents.Encrypted -> ZipProblem(
            entry,
            bottomPadding,
            "Verschlüsseltes Archiv",
            "Dieses ZIP-Archiv ist mit einem Kennwort geschützt. ORBIT kann verschlüsselte Archive nicht entpacken – eine Archiv-App kann es.",
        )
        is ZipContents.Unsupported -> ZipProblem(
            entry,
            bottomPadding,
            "Kein lesbares ZIP-Archiv",
            "Die Datei ist beschädigt oder kein ZIP-Archiv (trotz der Endung „.zip“).",
        )
        is ZipContents.Failed -> ZipProblem(entry, bottomPadding, "Archiv nicht lesbar", z.reason.message + ".")
        is ZipContents.Listed -> ZipListing(vm, entry, z, bottomPadding, onExtract = { actions.extractHere(entry) }, onExtractTo = { actions.extractTo(entry) })
    }
}

@Composable
private fun ZipProblem(entry: FileEntry, bottomPadding: Dp, title: String, message: String) {
    val actions = fileActions
    Column(Modifier.fillMaxWidth().padding(horizontal = Spacing.page), verticalArrangement = Arrangement.spacedBy(Spacing.m)) {
        Notice(title = title, message = message, tone = Tone.WARNING)
        PillButton("Öffnen mit …", onClick = { actions.openWith(entry) }, icon = AetherIcons.OpenExternal, primary = true)
        Spacer(Modifier.height(bottomPadding))
    }
}

@Composable
private fun ZipListing(
    vm: PreviewViewModel,
    entry: FileEntry,
    z: ZipContents.Listed,
    bottomPadding: Dp,
    onExtract: () -> Unit,
    onExtractTo: () -> Unit,
) {
    val colors = Aether.colors
    val free = vm.zipFreeBytes
    val canExtract = z.extractable
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = Spacing.page, end = Spacing.page, bottom = bottomPadding + Spacing.xxl),
        verticalArrangement = Arrangement.spacedBy(Spacing.cardGap),
    ) {
        item(key = "summary") {
            Panel {
                PanelHeader(
                    icon = AetherIcons.FileArchive,
                    title = "ZIP-Archiv",
                    subtitle = listOfNotNull(
                        plural(z.files, "Datei", "Dateien"),
                        z.folders.takeIf { it > 0 }?.let { plural(it, "Ordner", "Ordner") },
                    ).joinToString(", "),
                    tone = Tone.WARNING,
                )
                Spacer(Modifier.height(Spacing.s))
                // Größen stammen aus dem Archiv selbst und können gefälscht sein – dann ehrlich „Nicht verfügbar“.
                val unpackedKnown = z.totalBytes in 0 until Long.MAX_VALUE
                InfoRow(
                    "Entpackt",
                    when {
                        !unpackedKnown -> "Nicht verfügbar"
                        z.sizeUnknown -> ByteFormat.format(z.totalBytes) + " oder mehr"
                        else -> ByteFormat.format(z.totalBytes)
                    },
                    caption = when {
                        !unpackedKnown -> "Die Größenangaben im Archiv sind nicht glaubhaft"
                        z.sizeUnknown -> "Einige Einträge nennen ihre Größe nicht"
                        else -> null
                    },
                    muted = !unpackedKnown,
                )
                val packedKnown = z.compressedBytes in 0 until Long.MAX_VALUE
                InfoRow("Gepackt", if (packedKnown) ByteFormat.format(z.compressedBytes) else "Nicht verfügbar", muted = !packedKnown)
                InfoRow("Namen kodiert als", z.charsetName)
                if (free != null && free >= 0) InfoRow("Frei am Speicherort", ByteFormat.format(free))
                Spacer(Modifier.height(Spacing.m))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Spacing.s)) {
                    PillButton("Entpacken", onClick = onExtract, icon = AetherIcons.Extract, primary = true, enabled = canExtract)
                    PillButton("Entpacken nach …", onClick = onExtractTo, enabled = canExtract)
                }
                Spacer(Modifier.height(Spacing.s))
                Text(
                    if (canExtract) {
                        "Entpacken legt einen neuen Ordner neben das Archiv (bei genau einem Ordner im Archiv: diesen). Vorhandenes wird nie überschrieben."
                    } else {
                        "Entpacken ist mit ORBIT bei diesem Archiv nicht möglich – Gründe siehe unten. Eine Archiv-App kann es eventuell („Öffnen mit …“ im Menü oben)."
                    },
                    color = colors.textTertiary,
                    style = Aether.type.footnote,
                )
            }
        }
        val notices = buildList {
            if (z.encrypted) add(Triple("Verschlüsselt", "Das Archiv enthält kennwortgeschützte Einträge. ORBIT kann sie nicht entpacken.", Tone.WARNING))
            if (z.unsafeEntries > 0) {
                add(
                    Triple(
                        if (z.unsafeEntries == 1) "1 unsicherer Eintrag" else "${Fmt.count(z.unsafeEntries)} unsichere Einträge",
                        (if (z.unsafeEntries == 1) "Dieser Eintrag würde" else "Diese Einträge würden") +
                            " außerhalb des Zielordners landen („..“ oder absoluter Pfad) – ein bekannter Angriffsweg. ORBIT entpackt so etwas nie und meldet es.",
                        Tone.CRITICAL,
                    ),
                )
            }
            if (z.unsupportedEntries > 0) {
                add(
                    Triple(
                        "Packverfahren nicht unterstützt",
                        (if (z.unsupportedEntries == 1) "1 Eintrag nutzt" else "${Fmt.count(z.unsupportedEntries)} Einträge nutzen") +
                            " ein Verfahren, das Android nicht entpacken kann (z. B. BZip2, LZMA, Deflate64 – Windows nutzt Letzteres für sehr große Dateien).",
                        Tone.WARNING,
                    ),
                )
            }
            if (!z.readableByAndroid && !z.encrypted && z.unsupportedEntries == 0) {
                add(Triple("Von Android abgelehnt", "Android kann dieses Archiv nicht öffnen. Der Inhalt oben stammt aus ORBITs eigenem Lesen des Verzeichnisses.", Tone.WARNING))
            }
            if (free != null && !z.sizeUnknown && z.totalBytes in 0 until Long.MAX_VALUE && z.totalBytes > free) {
                add(Triple("Nicht genug Platz", "Entpackt braucht das Archiv ${ByteFormat.format(z.totalBytes)}, frei sind ${ByteFormat.format(free)}.", Tone.WARNING))
            }
            if (z.macosEntries > 0) {
                add(
                    Triple(
                        "macOS-Zusatzdaten",
                        (if (z.macosEntries == 1) "1 Eintrag" else "${Fmt.count(z.macosEntries)} Einträge") + " im Ordner „__MACOSX“ werden beim Entpacken übergangen.",
                        Tone.INFO,
                    ),
                )
            }
            if (z.truncated) add(Triple("Gekürzte Liste", "Gezeigt werden die ersten ${Fmt.count(z.entries.size)} von ${Fmt.count(z.totalEntries)} Einträgen. Entpackt wird alles.", Tone.INFO))
        }
        notices.forEachIndexed { i, (title, message, tone) ->
            item(key = "notice$i") { Notice(title = title, message = message, tone = tone) }
        }
        if (z.entries.isNotEmpty()) {
            item(key = "head") {
                Text("Inhalt", color = colors.textSecondary, style = Aether.type.subhead, modifier = Modifier.padding(top = Spacing.s).semantics { heading() })
            }
            itemsIndexed(z.entries, key = { i, _ -> "e$i" }) { i, e ->
                Column {
                    ZipRow(e)
                    if (i < z.entries.lastIndex) Hairline()
                }
            }
        } else {
            item(key = "empty") { Text("Das Archiv ist leer.", color = colors.textTertiary, style = Aether.type.callout) }
        }
    }
}

@Composable
private fun ZipRow(e: ZipEntryInfo) {
    val colors = Aether.colors
    val kind = FileTypes.kindOf(e.name, e.isDirectory)
    Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(vertical = Spacing.xs), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(28.dp), contentAlignment = Alignment.Center) {
            Icon(
                if (e.unsafe) AetherIcons.Warning else kind.icon(),
                contentDescription = if (e.unsafe) "Unsicher" else null,
                tint = if (e.unsafe) colors.critical else if (e.isDirectory) colors.accent else colors.textSecondary,
                modifier = Modifier.size(22.dp),
            )
        }
        Spacer(Modifier.width(Spacing.m))
        Column(Modifier.weight(1f)) {
            Text(e.name.ifEmpty { e.path }, color = colors.text, style = Aether.type.body, maxLines = 1, overflow = TextOverflow.MiddleEllipsis)
            val sub = when {
                e.unsafe -> "Wird beim Entpacken übergangen · ${e.path}"
                e.parent.isNotEmpty() -> e.parent
                else -> null
            }
            if (sub != null) Text(sub, color = if (e.unsafe) colors.critical else colors.textTertiary, style = Aether.type.caption, maxLines = 1, overflow = TextOverflow.StartEllipsis)
        }
        if (!e.isDirectory) {
            Spacer(Modifier.width(Spacing.s))
            Text(
                if (e.sizeBytes in 0 until Long.MAX_VALUE) ByteFormat.format(e.sizeBytes) else "Größe unbekannt",
                color = colors.textSecondary,
                style = Aether.type.footnote,
            )
        }
    }
}

private fun plural(n: Int, one: String, many: String): String = if (n == 1) "1 $one" else "${Fmt.count(n)} $many"
