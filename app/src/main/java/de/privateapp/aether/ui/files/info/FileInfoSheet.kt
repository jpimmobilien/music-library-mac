package de.privateapp.aether.ui.files.info

import android.content.ClipData
import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import de.privateapp.aether.AppGraph
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.CapacityBar
import de.privateapp.aether.design.GlassSheet
import de.privateapp.aether.design.InfoRow
import de.privateapp.aether.design.Notice
import de.privateapp.aether.design.PillButton
import de.privateapp.aether.design.Radii
import de.privateapp.aether.design.SheetHeader
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.design.Tone
import de.privateapp.aether.files.Checksums
import de.privateapp.aether.files.FileEntry
import de.privateapp.aether.files.FileKind
import de.privateapp.aether.files.FolderStats
import de.privateapp.aether.files.FolderStatsCalculator
import de.privateapp.aether.model.ByteFormat
import de.privateapp.aether.model.Fmt
import de.privateapp.aether.model.Reading
import de.privateapp.aether.platform.storage.ApkDetails
import de.privateapp.aether.platform.storage.ApkInspector
import de.privateapp.aether.platform.storage.ImageDetails
import de.privateapp.aether.platform.storage.MediaDetails
import de.privateapp.aether.platform.storage.MediaDetailsReader
import de.privateapp.aether.platform.storage.PdfDetails
import de.privateapp.aether.ui.files.FileThumbnail
import de.privateapp.aether.ui.files.FolderViewModel
import de.privateapp.aether.ui.files.displayParent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.coroutines.cancellation.CancellationException

private const val UNKNOWN = "Nicht verfügbar"

/**
 * „Informationen“ zu einer Datei oder einem Ordner: was das Dateisystem meldet, dazu je nach Art Angaben aus der
 * Datei selbst (Bildgröße, Aufnahmedatum, Dauer, Seiten, App-Version) und auf Wunsch die SHA-256-Prüfsumme.
 * Was nicht in der Datei steht, heißt „Nicht verfügbar“ – es wird nichts geschätzt.
 */
@Composable
fun FileInfoSheet(graph: AppGraph, entry: FileEntry, onDismiss: () -> Unit) {
    val root = remember(entry.path) { graph.volumeRoots.rootFor(entry.path) }
    GlassSheet(onDismiss = onDismiss) {
        SheetHeader(
            title = entry.name,
            subtitle = if (entry.isDirectory) "Ordner" else kindLabel(entry),
            leading = { FileThumbnail(entry, size = 56.dp) },
        )
        Spacer(Modifier.height(Spacing.s))
        Group("Allgemein") {
            if (entry.isDirectory) {
                FolderContentRow(entry)
            } else {
                InfoRow("Größe", ByteFormat.format(entry.sizeBytes), caption = "${Fmt.count(entry.sizeBytes)} Byte")
            }
            InfoRow("Geändert", if (entry.modifiedMillis > 0) Fmt.dateTime(entry.modifiedMillis) else UNKNOWN, muted = entry.modifiedMillis <= 0)
            InfoRow(
                "Zugriff",
                when {
                    entry.readable && entry.writable -> "Lesen und Schreiben"
                    entry.readable -> "Nur lesen"
                    else -> "Kein Zugriff"
                },
                caption = if (root?.readOnly == true) "Speicher ist nur lesbar eingebunden" else null,
            )
            if (!entry.isDirectory) InfoRow("MIME-Typ", entry.mimeType ?: UNKNOWN, muted = entry.mimeType == null)
            InfoRow("Versteckt", if (entry.isHidden) "Ja" else "Nein", caption = if (entry.isHidden) "Name beginnt mit einem Punkt" else null)
        }
        Group("Ort") {
            InfoRow("Speicher", root?.let { FolderViewModel.rootLabel(it) } ?: UNKNOWN, muted = root == null)
            InfoRow("Ordner", displayParent(entry.path).ifEmpty { "/" })
            PathRow(entry.path)
        }
        when (entry.kind) {
            FileKind.IMAGE -> ImageGroup(entry)
            FileKind.VIDEO, FileKind.AUDIO -> MediaGroup(entry)
            FileKind.PDF -> PdfGroup(entry)
            FileKind.APK -> ApkGroup(graph, entry)
            else -> Unit
        }
        if (!entry.isDirectory) ChecksumGroup(entry)
    }
}

private fun kindLabel(entry: FileEntry): String =
    entry.kind.label + if (entry.extension.isNotEmpty()) " (${entry.extension.uppercase(Locale.ROOT)})" else ""

@Composable
private fun Group(title: String, content: @Composable ColumnScope.() -> Unit) {
    val colors = Aether.colors
    Text(
        title,
        color = colors.textSecondary,
        style = Aether.type.subhead,
        modifier = Modifier.padding(top = Spacing.m, bottom = Spacing.xs, start = Spacing.xs).semantics { heading() },
    )
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radii.control))
            .background(colors.fill)
            .padding(horizontal = Spacing.l, vertical = Spacing.xs),
        content = content,
    )
}

@Composable
private fun FolderContentRow(entry: FileEntry) {
    val stats: FolderStats? by produceState<FolderStats?>(null, entry.path) {
        value = try {
            FolderStatsCalculator.compute(entry.path)
        } catch (e: IOException) {
            null
        }
    }
    val s = stats
    if (s == null) {
        InfoRow("Inhalt", "Wird gezählt …", muted = true)
    } else {
        val files = if (s.files == 1) "1 Datei" else "${Fmt.count(s.files)} Dateien"
        val folders = if (s.folders == 1) "1 Ordner" else "${Fmt.count(s.folders)} Ordner"
        InfoRow(
            "Inhalt",
            "$files, $folders",
            caption = ByteFormat.format(s.totalBytes) + if (!s.complete) " – mindestens: Teile waren nicht lesbar" else "",
        )
    }
}

@Composable
private fun PathRow(path: String) {
    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) {
        if (copied) {
            delay(2_000)
            copied = false
        }
    }
    InfoRow("Pfad", path)
    Row(Modifier.fillMaxWidth().padding(bottom = Spacing.s), horizontalArrangement = Arrangement.End) {
        PillButton(
            if (copied) "Kopiert" else "Pfad kopieren",
            onClick = {
                scope.launch {
                    clipboard.setClipEntry(ClipEntry(ClipData.newPlainText("Pfad", path)))
                    copied = !systemConfirmsCopy
                }
            },
            icon = if (copied) AetherIcons.Check else AetherIcons.Copy,
        )
    }
}

// --- Art-spezifische Angaben ----------------------------------------------------------------------------------------

private sealed interface Load<out T> {
    data object Loading : Load<Nothing>

    data class Done<T>(val value: T?) : Load<T>
}

@Composable
private fun <T> rememberDetails(key: Any, read: () -> T?): Load<T> {
    val state by produceState<Load<T>>(Load.Loading, key) {
        value = Load.Done(withContext(Dispatchers.IO) { read() })
    }
    return state
}

private val takenFormat = DateTimeFormatter.ofPattern("d. MMMM yyyy, HH:mm", Locale.GERMANY)

@Composable
private fun ImageGroup(entry: FileEntry) {
    val d = rememberDetails<ImageDetails>(entry.path to entry.modifiedMillis) { MediaDetailsReader.image(entry.path) }
    Group("Bild") {
        when (d) {
            Load.Loading -> InfoRow("Angaben", "Werden gelesen …", muted = true)
            is Load.Done -> {
                val v = d.value
                val w = v?.width
                val h = v?.height
                InfoRow(
                    "Abmessungen",
                    if (w != null && h != null) "${Fmt.count(w)} × ${Fmt.count(h)} Pixel" else UNKNOWN,
                    caption = if (w != null && h != null) "${Fmt.decimal(w.toLong() * h / 1_000_000.0, 1)} Megapixel" else null,
                    muted = w == null || h == null,
                )
                val taken: LocalDateTime? = v?.takenAt
                InfoRow(
                    "Aufgenommen",
                    taken?.format(takenFormat) ?: UNKNOWN,
                    caption = if (taken != null) "Uhrzeit der Kamera" else null,
                    muted = taken == null,
                )
                val camera = cameraName(v?.cameraMake, v?.cameraModel)
                InfoRow("Kamera", camera ?: UNKNOWN, muted = camera == null)
                if (v?.hasLocation == true) {
                    Spacer(Modifier.height(Spacing.xs))
                    Notice(
                        title = "Enthält Standortdaten",
                        message = "In diesem Bild ist gespeichert, wo es aufgenommen wurde. Wer die Datei erhält, kann den Ort sehen. ORBIT zeigt die Koordinaten bewusst nicht an.",
                        tone = Tone.INFO,
                        icon = AetherIcons.LocationPin,
                    )
                    Spacer(Modifier.height(Spacing.s))
                }
            }
        }
    }
}

/** „Google Pixel 6 Pro“ statt „Google Google Pixel 6 Pro“ – viele Hersteller wiederholen sich im Modellnamen. */
private fun cameraName(make: String?, model: String?): String? = when {
    make == null && model == null -> null
    make == null -> model
    model == null -> make
    model.startsWith(make, ignoreCase = true) -> model
    else -> "$make $model"
}

@Composable
private fun MediaGroup(entry: FileEntry) {
    val d = rememberDetails<MediaDetails>(entry.path to entry.modifiedMillis) { MediaDetailsReader.media(entry.path) }
    val video = entry.kind == FileKind.VIDEO
    Group(if (video) "Video" else "Audio") {
        when (d) {
            Load.Loading -> InfoRow("Angaben", "Werden gelesen …", muted = true)
            is Load.Done -> {
                val v = d.value
                val duration = v?.durationMillis
                InfoRow("Dauer", duration?.let(::formatDuration) ?: UNKNOWN, muted = duration == null)
                if (video) {
                    val w = v?.width
                    val h = v?.height
                    InfoRow("Auflösung", if (w != null && h != null) "${Fmt.count(w)} × ${Fmt.count(h)} Pixel" else UNKNOWN, muted = w == null || h == null)
                }
                InfoRow("Titel", v?.title ?: UNKNOWN, muted = v?.title == null)
                InfoRow("Interpret", v?.artist ?: UNKNOWN, muted = v?.artist == null)
                if (!video) InfoRow("Album", v?.album ?: UNKNOWN, muted = v?.album == null)
                if (v == null) {
                    Text(
                        "Android kann aus dieser Datei keine Angaben lesen (Format nicht unterstützt oder Datei beschädigt).",
                        color = Aether.colors.textTertiary,
                        style = Aether.type.footnote,
                        modifier = Modifier.padding(bottom = Spacing.s),
                    )
                }
            }
        }
    }
}

/** „3:07“, „1:02:45“. */
internal fun formatDuration(millis: Long): String {
    val total = millis / 1000
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) String.format(Locale.GERMANY, "%d:%02d:%02d", h, m, s) else String.format(Locale.GERMANY, "%d:%02d", m, s)
}

@Composable
private fun PdfGroup(entry: FileEntry) {
    val d = rememberDetails<PdfDetails>(entry.path to entry.modifiedMillis) { MediaDetailsReader.pdf(entry.path) }
    Group("PDF") {
        when (d) {
            Load.Loading -> InfoRow("Seiten", "Werden gezählt …", muted = true)
            is Load.Done -> {
                val v = d.value
                val pages = v?.pageCount
                when {
                    v?.protected == true -> InfoRow("Seiten", "Kennwortgeschützt", muted = true)
                    pages != null -> InfoRow("Seiten", Fmt.count(pages))
                    else -> InfoRow("Seiten", UNKNOWN, caption = "Android kann dieses PDF nicht lesen", muted = true)
                }
            }
        }
    }
}

@Composable
private fun ApkGroup(graph: AppGraph, entry: FileEntry) {
    val d = rememberDetails<Reading<ApkDetails>>(entry.path to entry.modifiedMillis) { graph.apkInspector.inspect(entry.path) }
    Group("App-Paket") {
        when (d) {
            Load.Loading -> InfoRow("Angaben", "Werden gelesen …", muted = true)
            is Load.Done -> when (val r = d.value) {
                null -> InfoRow("Angaben", UNKNOWN, muted = true)
                is Reading.Unavailable -> InfoRow("Angaben", r.missing.text, muted = true)
                is Reading.Value -> {
                    val a = r.value
                    InfoRow("App", a.label ?: UNKNOWN, muted = a.label == null)
                    InfoRow("Paket", a.packageName)
                    // Versionsnummer ohne Tausenderpunkt – „10203“ ist eine Kennzahl, keine Menge.
                    InfoRow("Version", a.versionName ?: UNKNOWN, caption = "Versionscode ${a.versionCode}", muted = a.versionName == null)
                    InfoRow("Benötigt", a.minSdk?.let(::androidLevel) ?: UNKNOWN, muted = a.minSdk == null)
                    InfoRow("Erstellt für", a.targetSdk?.let(::androidLevel) ?: UNKNOWN, muted = a.targetSdk == null)
                    InfoRow(
                        "Installiert",
                        when {
                            a.installed == null -> "Nicht feststellbar"
                            a.installedVersionName != null -> "Ja, Version ${a.installedVersionName}"
                            else -> "Ja"
                        },
                        muted = a.installed == null,
                        caption = if (a.installed == null) "Android zeigt anderen Apps nicht jede installierte App – der Installer sagt es vor der Installation" else null,
                    )
                    val min = a.minSdk
                    if (min != null && min > Build.VERSION.SDK_INT) {
                        Spacer(Modifier.height(Spacing.xs))
                        Notice(
                            title = "Für dieses Gerät zu neu",
                            message = "Die App benötigt ${androidLevel(min)}, dieses Gerät hat Android ${Build.VERSION.RELEASE}. Android wird die Installation ablehnen.",
                            tone = Tone.WARNING,
                        )
                        Spacer(Modifier.height(Spacing.s))
                    }
                }
            }
        }
    }
}

/** „Android 12“ – oder „API-Stufe 37“, wenn die Android-Version zu einer Stufe (noch) nicht bekannt ist. */
private fun androidLevel(api: Int): String {
    val release = ApkInspector.releaseFor(api)
    return if (release.startsWith("API")) "API-Stufe $api" else "Android $release"
}

/** Ab Android 13 bestätigt das System das Kopieren selbst – dann keine zweite Meldung. */
private val systemConfirmsCopy: Boolean get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU

// --- Prüfsumme --------------------------------------------------------------------------------------------------

private sealed interface HashState {
    data object Idle : HashState

    data class Running(val done: Long) : HashState

    data class Done(val hex: String) : HashState

    data class Failed(val message: String) : HashState
}

@Composable
private fun ChecksumGroup(entry: FileEntry) {
    val colors = Aether.colors
    val scope = rememberCoroutineScope()
    val clipboard = LocalClipboard.current
    var state by remember(entry.path, entry.modifiedMillis) { mutableStateOf<HashState>(HashState.Idle) }
    var job by remember { mutableStateOf<Job?>(null) }
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) {
        if (copied) {
            delay(2_000)
            copied = false
        }
    }
    Group("Prüfsumme") {
        when (val s = state) {
            HashState.Idle -> {
                Text(
                    "Mit der SHA-256-Prüfsumme lässt sich prüfen, ob eine Datei unverändert ist – z. B. mit der Angabe auf einer Download-Seite.",
                    color = colors.textSecondary,
                    style = Aether.type.footnote,
                    modifier = Modifier.padding(vertical = Spacing.s),
                )
                Row(Modifier.fillMaxWidth().padding(bottom = Spacing.s), horizontalArrangement = Arrangement.End) {
                    PillButton("SHA-256 berechnen", onClick = {
                        state = HashState.Running(0)
                        job = scope.launch {
                            state = try {
                                HashState.Done(
                                    Checksums.sha256(entry.path) { done ->
                                        // Fortschritt höchstens alle 4 MB zeichnen.
                                        if (done % (4L * 1024 * 1024) < 256 * 1024) state = HashState.Running(done)
                                    },
                                )
                            } catch (e: CancellationException) {
                                HashState.Idle
                            } catch (e: IOException) {
                                HashState.Failed("Die Datei ließ sich nicht vollständig lesen (entfernt, gesperrt oder Lesefehler).")
                            }
                        }
                    }, icon = AetherIcons.Shield)
                }
            }
            is HashState.Running -> {
                val fraction = if (entry.sizeBytes > 0) (s.done.toDouble() / entry.sizeBytes).toFloat() else null
                InfoRow("SHA-256", "Wird berechnet …", caption = if (entry.sizeBytes > 0) "${ByteFormat.format(s.done)} von ${ByteFormat.format(entry.sizeBytes)}" else null, muted = true)
                CapacityBar(fraction = fraction, height = 4.dp)
                Row(Modifier.fillMaxWidth().padding(vertical = Spacing.s), horizontalArrangement = Arrangement.End) {
                    PillButton("Abbrechen", onClick = {
                        job?.cancel()
                        state = HashState.Idle
                    })
                }
            }
            is HashState.Done -> {
                Text("SHA-256", color = colors.textSecondary, style = Aether.type.callout, modifier = Modifier.padding(top = Spacing.s))
                Text(
                    s.hex.chunked(8).joinToString(" "),
                    color = colors.text,
                    style = Aether.type.footnote.copy(fontFamily = FontFamily.Monospace),
                    modifier = Modifier.padding(vertical = Spacing.xs),
                )
                Row(Modifier.fillMaxWidth().padding(bottom = Spacing.s), horizontalArrangement = Arrangement.End) {
                    PillButton(
                        if (copied) "Kopiert" else "Kopieren",
                        onClick = {
                            scope.launch {
                                clipboard.setClipEntry(ClipEntry(ClipData.newPlainText("SHA-256", s.hex)))
                                copied = !systemConfirmsCopy
                            }
                        },
                        icon = if (copied) AetherIcons.Check else AetherIcons.Copy,
                    )
                }
            }
            is HashState.Failed -> {
                InfoRow("SHA-256", "Nicht berechnet", caption = s.message, muted = true)
                Row(Modifier.fillMaxWidth().padding(bottom = Spacing.s), horizontalArrangement = Arrangement.End) {
                    PillButton("Erneut versuchen", onClick = { state = HashState.Idle }, icon = AetherIcons.Refresh)
                }
            }
        }
    }
}
