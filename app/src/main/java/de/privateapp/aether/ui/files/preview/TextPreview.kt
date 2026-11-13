package de.privateapp.aether.ui.files.preview

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.Notice
import de.privateapp.aether.design.PillButton
import de.privateapp.aether.design.Radii
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.design.StatusBadge
import de.privateapp.aether.design.Tone
import de.privateapp.aether.files.FileEntry
import de.privateapp.aether.model.ByteFormat
import de.privateapp.aether.model.Fmt

/** Endungen, die als Quelltext/Daten gelesen werden (gleichmäßige Schrift, Zeilennummern). */
private val CODE_EXTENSIONS = setOf(
    "csv", "json", "log", "xml", "yaml", "yml", "kt", "java", "js", "css", "html", "htm", "ini", "conf", "cfg",
    "sh", "py", "c", "h", "cpp", "toml", "properties", "gradle", "kts", "sql", "ts", "swift",
)

/** Grenze des Vorschaulesers (TextPreviewReader): so viel wird höchstens gelesen. */
private const val READ_LIMIT_BYTES = 512L * 1024

/**
 * Text lesen und bearbeiten. Gesichert wird über die Datei-Engine: erst vollständig schreiben, dann ersetzen – und nur,
 * wenn die Datei seit dem Öffnen nicht von anderer Seite geändert wurde. Abgeschnittene, nicht verlustfrei lesbare
 * und sehr große Dateien lassen sich nicht bearbeiten, damit beim Sichern nie etwas verloren geht oder verfälscht wird.
 */
@Composable
internal fun TextPreviewContent(vm: PreviewViewModel, bottomPadding: Dp) {
    val entry = vm.entry ?: return
    val code = entry.extension in CODE_EXTENSIONS
    if (vm.editor != null) {
        TextEditor(vm, entry, code, bottomPadding)
        return
    }
    when (val t = vm.text) {
        TextLoad.Loading -> Text(
            "Wird gelesen …",
            color = Aether.colors.textTertiary,
            style = Aether.type.callout,
            modifier = Modifier.fillMaxWidth().padding(Spacing.xl),
            textAlign = TextAlign.Center,
        )
        TextLoad.Failed -> Column(Modifier.padding(horizontal = Spacing.page)) {
            Notice(
                title = "Datei nicht lesbar",
                message = "Android erlaubt das Lesen dieser Datei gerade nicht, oder sie wurde während des Öffnens entfernt.",
                tone = Tone.WARNING,
            )
        }
        is TextLoad.Ready -> if (t.preview.looksBinary) {
            FallbackPreview(
                entry,
                bottomPadding,
                message = "Trotz der Endung „.${entry.extension}“ enthält diese Datei vermutlich Binärdaten und keinen lesbaren Text. ORBIT zeigt sie deshalb nicht als Text an.",
            )
        } else {
            TextViewer(vm, entry, t, code, bottomPadding)
        }
    }
}

@Composable
private fun TextViewer(vm: PreviewViewModel, entry: FileEntry, t: TextLoad.Ready, code: Boolean, bottomPadding: Dp) {
    val colors = Aether.colors
    val block = vm.editBlock(entry, t)
    val style = textStyle(code)
    val fontScale = LocalDensity.current.fontScale
    val digits = t.lineCount.coerceAtLeast(1).toString().length
    val numberWidth = if (code) ((digits * 8.5f + 10f) * fontScale).dp else 0.dp
    val linesLabel = when {
        t.preview.truncated -> "mindestens ${Fmt.count(t.lineCount)} Zeilen"
        t.lineCount == 1 -> "1 Zeile"
        else -> "${Fmt.count(t.lineCount)} Zeilen"
    }
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = Spacing.page, end = Spacing.page, bottom = bottomPadding + Spacing.xxl),
    ) {
        item(key = "meta") {
            Column {
                Row(
                    Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(Spacing.s),
                ) {
                    StatusBadge(t.preview.charsetName, tone = Tone.NEUTRAL)
                    StatusBadge(linesLabel, tone = Tone.NEUTRAL)
                    Spacer(Modifier.weight(1f))
                    PillButton("Bearbeiten", onClick = vm::startEditing, icon = AetherIcons.Pencil, enabled = block == null)
                }
                if (block != null) {
                    Spacer(Modifier.height(Spacing.s))
                    Notice(title = block.title(), message = block.message(), tone = Tone.INFO)
                }
                Spacer(Modifier.height(Spacing.m))
            }
        }
        if (t.preview.text.isEmpty()) {
            item(key = "empty") {
                Text("Die Datei ist leer.", color = colors.textTertiary, style = Aether.type.callout)
            }
        } else {
            itemsIndexed(t.lines, key = { i, _ -> i }) { _, line ->
                Row(Modifier.fillMaxWidth()) {
                    if (code) {
                        Text(
                            line.number?.toString().orEmpty(),
                            color = colors.textTertiary,
                            style = style,
                            textAlign = TextAlign.End,
                            maxLines = 1,
                            softWrap = false,
                            modifier = Modifier.widthIn(min = numberWidth).padding(end = Spacing.s).clearAndSetSemantics { },
                        )
                    }
                    Text(line.text.ifEmpty { " " }, color = colors.text, style = style, modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

private fun EditBlock.title(): String = when (this) {
    EditBlock.TRUNCATED -> "Nur der Anfang wird gezeigt"
    EditBlock.TOO_LARGE -> "Zum Bearbeiten zu groß"
    EditBlock.LOSSY -> "Bearbeiten gesperrt"
    EditBlock.READ_ONLY -> "Nur lesbar"
}

private fun EditBlock.message(): String = when (this) {
    EditBlock.TRUNCATED ->
        "Die Datei ist größer als ${ByteFormat.format(READ_LIMIT_BYTES)}. Bearbeiten ist gesperrt – beim Sichern ginge sonst der nicht geladene Rest verloren. Für die ganze Datei: „Öffnen mit …“."
    EditBlock.TOO_LARGE ->
        "ORBIT bearbeitet Textdateien bis ${ByteFormat.format(PreviewViewModel.EDIT_LIMIT_BYTES)}, damit das Tippen flüssig bleibt. Für größere Dateien: „Öffnen mit …“."
    EditBlock.LOSSY ->
        "Die Datei enthält Zeichen, die sich nicht eindeutig lesen lassen (gemischte oder unbekannte Kodierung). Beim Sichern würden sie verfälscht – deshalb ist Bearbeiten gesperrt."
    EditBlock.READ_ONLY ->
        "ORBIT darf diese Datei nicht ändern (schreibgeschützter Speicher oder fehlende Berechtigung)."
}

@Composable
private fun TextEditor(vm: PreviewViewModel, entry: FileEntry, code: Boolean, bottomPadding: Dp) {
    val colors = Aether.colors
    val state = vm.editor ?: return
    val shape = RoundedCornerShape(Radii.control)
    Column(
        Modifier
            .fillMaxSize()
            // Kein zusätzliches imePadding: Die Abstände des Rahmens enthalten die Tastatur bereits.
            .padding(start = Spacing.page, end = Spacing.page, bottom = bottomPadding + Spacing.m),
    ) {
        val problem = vm.saveProblem
        if (problem != null) {
            Notice(
                title = when (problem) {
                    SaveProblem.CHANGED -> "Nicht gesichert – die Datei wurde inzwischen geändert"
                    SaveProblem.DELETED -> "Nicht gesichert – die Datei gibt es nicht mehr"
                    SaveProblem.OTHER -> "Nicht gesichert"
                },
                message = when (problem) {
                    SaveProblem.CHANGED ->
                        "„${entry.name}“ hat sich seit dem Öffnen geändert (z. B. durch eine andere App). Sichern hätte diese Änderungen überschrieben. Sichere deine Fassung als Kopie – oder lade die neue Fassung und verwirf deine Änderungen."
                    SaveProblem.DELETED ->
                        "„${entry.name}“ wurde gelöscht oder verschoben, während du bearbeitet hast. Deine Fassung ist noch hier – sichere sie als neue Datei."
                    SaveProblem.OTHER ->
                        (vm.saveProblemReason?.message ?: "Lese- oder Schreibfehler") + ". Deine Änderungen sind noch hier – versuche es erneut oder sichere sie als Kopie."
                },
                tone = Tone.WARNING,
            )
            Spacer(Modifier.height(Spacing.s))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Spacing.s, Alignment.End)) {
                if (problem == SaveProblem.CHANGED) {
                    PillButton("Neue Fassung laden", onClick = vm::discardEditing, icon = AetherIcons.Refresh)
                }
                PillButton("Als Kopie sichern", onClick = vm::saveAsCopy, icon = AetherIcons.Copy, primary = true, enabled = !vm.saving)
            }
            Spacer(Modifier.height(Spacing.s))
        }
        BasicTextField(
            state = state,
            enabled = !vm.saving,
            textStyle = textStyle(code).copy(color = colors.text),
            cursorBrush = SolidColor(colors.accent),
            keyboardOptions = KeyboardOptions(
                capitalization = if (code) KeyboardCapitalization.None else KeyboardCapitalization.Sentences,
                autoCorrectEnabled = !code,
            ),
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .clip(shape)
                .background(colors.fill)
                .border(0.8.dp, colors.hairline, shape)
                .padding(Spacing.m)
                .semantics { contentDescription = "Inhalt von ${entry.name}" },
        )
    }
}

@Composable
private fun textStyle(code: Boolean): TextStyle =
    if (code) Aether.type.footnote.copy(fontFamily = FontFamily.Monospace, fontSize = 13.sp, lineHeight = 19.sp) else Aether.type.body
