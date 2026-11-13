package de.privateapp.aether.ui.files.preview

import androidx.compose.animation.core.animate
import androidx.compose.foundation.Image
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculateCentroidSize
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.PillButton
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.design.StatusBadge
import de.privateapp.aether.design.Tone
import de.privateapp.aether.files.FileEntry
import de.privateapp.aether.model.Fmt
import de.privateapp.aether.platform.storage.ImageDecodeResult
import de.privateapp.aether.platform.storage.PreviewImages
import de.privateapp.aether.ui.files.EmptyState
import de.privateapp.aether.ui.files.fileActions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

private const val MAX_ZOOM = 5f
private const val DOUBLE_TAP_ZOOM = 2.5f

/** Höchstens zwei Bilder werden gleichzeitig dekodiert – schnelles Wischen stapelt sonst Dutzende große Bitmaps. */
private val decodeDispatcher = Dispatchers.IO.limitedParallelism(2)

/**
 * Bilder: alle Bilder des Ordners zum Wischen (Reihenfolge wie in der Ordneransicht), jedes zoombar. Die Bildleiste
 * besteht von Anfang an (zuerst nur mit dem geöffneten Bild); kommen die übrigen dazu, bleibt das gezeigte Bild
 * stehen – ohne neu zu laden und ohne den Zoom zu verlieren.
 */
@Composable
internal fun ImagePreview(vm: PreviewViewModel, bottomPadding: Dp) {
    val start = vm.entry ?: return
    val siblings = vm.siblings.ifEmpty { listOf(start) }
    val initial = remember { siblings.indexOfFirst { it.path == start.path }.coerceAtLeast(0) }
    val state = rememberPagerState(initialPage = initial) { siblings.size }
    LaunchedEffect(state, siblings) {
        // Neue Liste (übrige Bilder geladen, ein Bild gelöscht oder umbenannt): erst zum gezeigten Bild bzw. zu dem
        // Ersatz, den das ViewModel gewählt hat, dann wieder dem Wischen folgen.
        val target = siblings.indexOfFirst { it.path == vm.entry?.path }
        if (target >= 0 && target != state.currentPage) state.scrollToPage(target)
        snapshotFlow { state.currentPage }.collect { page -> siblings.getOrNull(page)?.let(vm::showSibling) }
    }
    HorizontalPager(
        state = state,
        modifier = Modifier.fillMaxSize(),
        key = { siblings.getOrNull(it)?.path ?: it },
        beyondViewportPageCount = 0,
    ) { page ->
        siblings.getOrNull(page)?.let { ZoomableImage(it, bottomPadding, Modifier.fillMaxSize()) }
    }
}

private sealed interface ImageState {
    data object Loading : ImageState

    class Done(val result: ImageDecodeResult) : ImageState
}

/**
 * Ein Bild, verkleinert auf etwa die doppelte Bildschirmgröße dekodiert. Zwei Finger zoomen (1- bis 5-fach),
 * Doppeltippen wechselt zwischen Einpassen und 2,5-fach an der getippten Stelle; gezoomt verschiebt man mit einem
 * Finger – nie über den Bildrand hinaus. Ungezoomt wischt man zum nächsten Bild.
 */
@Composable
private fun ZoomableImage(entry: FileEntry, bottomPadding: Dp, modifier: Modifier) {
    val colors = Aether.colors
    val motion = Aether.motion
    val actions = fileActions
    BoxWithConstraints(modifier, contentAlignment = Alignment.Center) {
        val boxW = constraints.maxWidth.toFloat().coerceAtLeast(1f)
        val boxH = constraints.maxHeight.toFloat().coerceAtLeast(1f)
        val maxSide = (max(boxW, boxH) * 2f).toInt().coerceIn(1024, 4096)
        val state by produceState<ImageState>(ImageState.Loading, entry.path, entry.modifiedMillis, maxSide) {
            value = ImageState.Done(
                withContext(decodeDispatcher) {
                    // Inzwischen weggewischt? Dann gar nicht erst dekodieren.
                    ensureActive()
                    PreviewImages.decode(entry.path, maxSide)
                },
            )
        }
        when (val s = state) {
            ImageState.Loading -> Text("Wird geladen …", color = colors.textTertiary, style = Aether.type.callout)
            is ImageState.Done -> when (val r = s.result) {
                is ImageDecodeResult.Ok -> {
                    val image = r.image
                    val bitmap = remember(image) { image.bitmap.asImageBitmap() }
                    var scale by remember(entry.path) { mutableFloatStateOf(1f) }
                    var offset by remember(entry.path) { mutableStateOf(Offset.Zero) }
                    val scope = rememberCoroutineScope()
                    // Eingepasste Bildgröße im Rahmen (für die Grenzen beim Verschieben).
                    val fit = min(boxW / image.bitmap.width, boxH / image.bitmap.height)
                    val fitted = Size(image.bitmap.width * fit, image.bitmap.height * fit)
                    val center = Offset(boxW / 2f, boxH / 2f)
                    fun clamp(o: Offset, s: Float): Offset {
                        val maxX = max(0f, (fitted.width * s - boxW) / 2f)
                        val maxY = max(0f, (fitted.height * s - boxH) / 2f)
                        return Offset(o.x.coerceIn(-maxX, maxX), o.y.coerceIn(-maxY, maxY))
                    }
                    fun zoomTo(target: Float, focus: Offset) {
                        val fromScale = scale
                        val fromOffset = offset
                        val ratio = target / fromScale
                        val toOffset = clamp((focus - center) * (1f - ratio) + fromOffset * ratio, target)
                        scope.launch {
                            animate(0f, 1f, animationSpec = motion.standard()) { f, _ ->
                                scale = fromScale + (target - fromScale) * f
                                offset = fromOffset + (toOffset - fromOffset) * f
                            }
                        }
                    }
                    val description = "Bild „${entry.name}“, ${Fmt.count(image.width)} × ${Fmt.count(image.height)} Pixel" +
                        if (scale > 1.01f) ", ${Fmt.decimal(scale.toDouble(), 1)}-fach vergrößert" else ""
                    Image(
                        bitmap = bitmap,
                        contentDescription = null,
                        contentScale = ContentScale.Fit,
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics {
                                contentDescription = description
                                customActions = listOf(
                                    CustomAccessibilityAction("Vergrößern") {
                                        zoomTo(min(MAX_ZOOM, scale * 2f), center)
                                        true
                                    },
                                    CustomAccessibilityAction("Verkleinern") {
                                        zoomTo(1f, center)
                                        true
                                    },
                                )
                            }
                            // Gesten in Rahmenkoordinaten (vor der Transformation).
                            .pointerInput(entry.path, boxW, boxH) {
                                detectTapGestures(onDoubleTap = { p -> if (scale > 1.01f) zoomTo(1f, center) else zoomTo(DOUBLE_TAP_ZOOM, p) })
                            }
                            .pointerInput(entry.path, boxW, boxH) {
                                val slop = viewConfiguration.touchSlop
                                awaitEachGesture {
                                    awaitFirstDown(requireUnconsumed = false)
                                    // Erst ab einer kleinen Bewegung reagieren (wie Androids eigene Gesten) – sonst
                                    // brächte jedes Zittern das Doppeltippen durcheinander.
                                    var pastSlop = false
                                    var zoomSum = 1f
                                    var panSum = Offset.Zero
                                    do {
                                        val event = awaitPointerEvent()
                                        val pressed = event.changes.count { it.pressed }
                                        val consumed = event.changes.any { it.isConsumed }
                                        // Ungezoomt und mit einem Finger: nichts tun – dann wischt die Bildleiste.
                                        if (!consumed && (pressed >= 2 || scale > 1.01f)) {
                                            val zoom = event.calculateZoom()
                                            val pan = event.calculatePan()
                                            if (!pastSlop) {
                                                zoomSum *= zoom
                                                panSum += pan
                                                val zoomMotion = abs(1f - zoomSum) * event.calculateCentroidSize(useCurrent = false)
                                                pastSlop = zoomMotion > slop || panSum.getDistance() > slop
                                            }
                                            if (pastSlop) {
                                                val c = event.calculateCentroid(useCurrent = true)
                                                val newScale = (scale * zoom).coerceIn(1f, MAX_ZOOM)
                                                val ratio = newScale / scale
                                                val focus = if (c == Offset.Unspecified) center else c
                                                offset = clamp((focus - center) * (1f - ratio) + offset * ratio + pan, newScale)
                                                scale = newScale
                                                event.changes.forEach { if (it.positionChanged()) it.consume() }
                                            }
                                        }
                                    } while (event.changes.any { it.pressed })
                                    if (scale < 1.01f) {
                                        scale = 1f
                                        offset = Offset.Zero
                                    }
                                }
                            }
                            .graphicsLayer {
                                scaleX = scale
                                scaleY = scale
                                translationX = offset.x
                                translationY = offset.y
                            },
                    )
                    if (image.animated) {
                        StatusBadge(
                            "Animation – hier als Standbild",
                            tone = Tone.INFO,
                            icon = AetherIcons.Info,
                            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = bottomPadding + Spacing.m),
                        )
                    }
                }
                ImageDecodeResult.Missing -> Box(Modifier.fillMaxSize().padding(horizontal = Spacing.page), contentAlignment = Alignment.Center) {
                    EmptyState(
                        icon = AetherIcons.FileImage,
                        title = "Bild nicht mehr vorhanden",
                        message = "„${entry.name}“ wurde gelöscht oder verschoben – vielleicht von einer anderen App.",
                        tone = Tone.WARNING,
                    )
                }
                ImageDecodeResult.TooLarge -> ImageProblem(
                    "Bild zu groß für die Vorschau",
                    "Für dieses Bild reicht der Arbeitsspeicher nicht. Öffne es in einer anderen App.",
                ) { actions.openWith(entry) }
                is ImageDecodeResult.Unsupported -> ImageProblem(
                    "Bild kann nicht angezeigt werden",
                    "Android kann dieses Bildformat auf diesem Gerät nicht darstellen – oder die Datei ist beschädigt." +
                        if (entry.extension == "svg") " SVG-Grafiken zeigt Android nicht selbst an." else "",
                ) { actions.openWith(entry) }
            }
        }
    }
}

@Composable
private fun ImageProblem(title: String, message: String, onOpenWith: () -> Unit) {
    Box(Modifier.fillMaxSize().padding(horizontal = Spacing.page), contentAlignment = Alignment.Center) {
        EmptyState(
            icon = AetherIcons.FileImage,
            title = title,
            message = message,
            tone = Tone.WARNING,
            action = { PillButton("Öffnen mit …", onClick = onOpenWith, icon = AetherIcons.OpenExternal, primary = true) },
        )
    }
}
