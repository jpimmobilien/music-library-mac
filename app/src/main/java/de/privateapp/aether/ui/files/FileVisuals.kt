package de.privateapp.aether.ui.files

import android.graphics.Bitmap
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.Tone
import de.privateapp.aether.files.FileEntry
import de.privateapp.aether.files.FileKind
import de.privateapp.aether.model.ByteFormat
import de.privateapp.aether.model.Fmt
import de.privateapp.aether.platform.storage.MediaCategory

/** Symbol je Dateiart. */
fun FileKind.icon(): ImageVector = when (this) {
    FileKind.FOLDER -> AetherIcons.Folder
    FileKind.IMAGE -> AetherIcons.FileImage
    FileKind.VIDEO -> AetherIcons.FileVideo
    FileKind.AUDIO -> AetherIcons.FileAudio
    FileKind.DOCUMENT -> AetherIcons.Document
    FileKind.PDF -> AetherIcons.FilePdf
    FileKind.TEXT -> AetherIcons.FileText
    FileKind.ARCHIVE -> AetherIcons.FileArchive
    FileKind.APK -> AetherIcons.FilePackage
    FileKind.OTHER -> AetherIcons.FileGeneric
}

/**
 * Farbton je Art – zurückhaltend wie bei Apple: Ordner in der Akzentfarbe, Medien und Dokumente ruhig unterscheidbar.
 * Die Art steht immer zusätzlich als Symbol und in Worten da (nicht nur farblich).
 */
fun FileKind.tone(): Tone = when (this) {
    FileKind.FOLDER -> Tone.ACCENT
    FileKind.IMAGE, FileKind.VIDEO -> Tone.INFO
    FileKind.AUDIO -> Tone.SUCCESS
    FileKind.PDF -> Tone.CRITICAL
    FileKind.ARCHIVE, FileKind.APK -> Tone.WARNING
    FileKind.DOCUMENT, FileKind.TEXT, FileKind.OTHER -> Tone.NEUTRAL
}

fun MediaCategory.icon(): ImageVector = when (this) {
    MediaCategory.IMAGES -> AetherIcons.FileImage
    MediaCategory.VIDEOS -> AetherIcons.FileVideo
    MediaCategory.MUSIC, MediaCategory.AUDIO -> AetherIcons.FileAudio
    MediaCategory.DOCUMENTS -> AetherIcons.Document
    MediaCategory.PDF -> AetherIcons.FilePdf
    MediaCategory.TEXT -> AetherIcons.FileText
    MediaCategory.ARCHIVES -> AetherIcons.FileArchive
    MediaCategory.APKS -> AetherIcons.FilePackage
    MediaCategory.DOWNLOADS -> AetherIcons.Download
    MediaCategory.RECENT -> AetherIcons.Clock
}

fun MediaCategory.tone(): Tone = when (this) {
    MediaCategory.IMAGES, MediaCategory.VIDEOS -> Tone.INFO
    MediaCategory.MUSIC, MediaCategory.AUDIO -> Tone.SUCCESS
    MediaCategory.PDF -> Tone.CRITICAL
    MediaCategory.ARCHIVES, MediaCategory.APKS -> Tone.WARNING
    MediaCategory.DOWNLOADS, MediaCategory.RECENT -> Tone.ACCENT
    MediaCategory.DOCUMENTS, MediaCategory.TEXT -> Tone.NEUTRAL
}

/** Kategorien, die man sich am besten als Raster ansieht (wie in Fotos-Apps). */
val MediaCategory.isVisual: Boolean get() = this == MediaCategory.IMAGES || this == MediaCategory.VIDEOS

/** „2,4 MB · Heute, 14:32“ bzw. für Ordner nur das Datum. */
fun FileEntry.detailLine(nowMillis: Long): String {
    val date = if (modifiedMillis > 0) Fmt.fileDate(modifiedMillis, nowMillis) else null
    return if (isDirectory) date ?: kind.label else listOfNotNull(ByteFormat.format(sizeBytes), date).joinToString(" · ")
}

/**
 * Vorschaubild einer Datei (Bild, Video, Albumcover, erste PDF-Seite, App-Symbol) – solange es entsteht oder wenn es
 * keines gibt, das Symbol der Art. Erzeugt wird es nur für sichtbare Einträge und im Arbeitsspeicher zwischengespeichert.
 */
@Composable
fun FileThumbnail(entry: FileEntry, size: Dp, modifier: Modifier = Modifier, corner: Dp = size * 0.24f, fill: Boolean = false) {
    val graph = fileActions.vm.graph
    val loader = graph.thumbnails
    val px = with(LocalDensity.current) { size.roundToPx() }.coerceAtLeast(48)
    val bitmap: Bitmap? by produceState(loader.cached(entry, px), entry.path, entry.modifiedMillis, entry.sizeBytes, px) {
        if (value == null && loader.supports(entry)) value = loader.load(entry, px)
    }
    val colors = Aether.colors
    val motion = Aether.motion
    val shape = RoundedCornerShape(corner)
    AnimatedContent(
        targetState = bitmap,
        transitionSpec = { fadeIn(motion.fade()) togetherWith fadeOut(motion.fade()) },
        contentKey = { it != null },
        modifier = modifier.size(size),
        label = "thumb",
    ) { b ->
        if (b != null) {
            Image(
                bitmap = b.asImageBitmap(),
                contentDescription = null,
                contentScale = if (fill || entry.kind != FileKind.APK) ContentScale.Crop else ContentScale.Fit,
                modifier = Modifier.fillMaxSize().clip(shape).background(colors.fill),
            )
        } else {
            val tone = entry.kind.tone()
            val tint = if (tone == Tone.NEUTRAL) colors.textSecondary else colors.tone(tone)
            Box(Modifier.fillMaxSize().clip(shape).background(if (tone == Tone.NEUTRAL) colors.fill else colors.toneSoft(tone)), contentAlignment = Alignment.Center) {
                Icon(entry.kind.icon(), contentDescription = null, tint = tint, modifier = Modifier.size(size * 0.52f))
            }
        }
    }
}
