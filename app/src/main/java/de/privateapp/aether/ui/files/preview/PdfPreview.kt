package de.privateapp.aether.ui.files.preview

import android.graphics.Bitmap
import androidx.compose.animation.core.animate
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.GlassSurface
import de.privateapp.aether.design.Notice
import de.privateapp.aether.design.PillButton
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.design.Tone
import de.privateapp.aether.files.FileEntry
import de.privateapp.aether.model.Fmt
import de.privateapp.aether.platform.storage.PdfPages
import de.privateapp.aether.ui.files.fileActions
import kotlinx.coroutines.launch
import kotlin.math.max

private const val PDF_MAX_ZOOM = 3f

/**
 * PDF: alle Seiten untereinander, erst beim Erscheinen gezeichnet. Zwei Finger zoomen (bis 3-fach) und verschieben –
 * auch bis an den oberen und unteren Rand –, Doppeltippen zoomt 2-fach bzw. zurück. Unten steht, welche Seite gerade
 * zu sehen ist.
 */
@Composable
internal fun PdfPreview(vm: PreviewViewModel, entry: FileEntry, bottomPadding: Dp) {
    val actions = fileActions
    when (val p = vm.pdf) {
        PdfLoad.Loading -> Text(
            "Wird geöffnet …",
            color = Aether.colors.textTertiary,
            style = Aether.type.callout,
            modifier = Modifier.fillMaxWidth().padding(Spacing.xl),
        )
        PdfLoad.Protected -> PdfProblem(
            "Kennwortgeschützt",
            "Dieses PDF ist mit einem Kennwort geschützt. ORBIT kann geschützte PDFs nicht öffnen – eine PDF-App kann es.",
        ) { actions.openWith(entry) }
        PdfLoad.Broken -> PdfProblem(
            "PDF kann nicht angezeigt werden",
            "Android kann diese Datei nicht als PDF lesen – sie ist beschädigt oder nutzt Funktionen, die Android nicht darstellt.",
        ) { actions.openWith(entry) }
        is PdfLoad.Open -> PdfPagesView(vm, p.pages, bottomPadding)
    }
}

@Composable
private fun PdfProblem(title: String, message: String, onOpenWith: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = Spacing.page), verticalArrangement = Arrangement.spacedBy(Spacing.m)) {
        Notice(title = title, message = message, tone = Tone.WARNING)
        PillButton("Öffnen mit …", onClick = onOpenWith, icon = AetherIcons.OpenExternal, primary = true)
    }
}

@Composable
private fun PdfPagesView(vm: PreviewViewModel, pages: PdfPages, bottomPadding: Dp) {
    val colors = Aether.colors
    val motion = Aether.motion
    val list = rememberLazyListState()
    val scope = rememberCoroutineScope()
    var scale by remember(pages) { mutableFloatStateOf(1f) }
    var shift by remember(pages) { mutableStateOf(Offset.Zero) }
    val current by remember(list) {
        derivedStateOf {
            val info = list.layoutInfo
            // Die Seite, die die Mitte des sichtbaren Bereichs einnimmt.
            val mid = (info.viewportStartOffset + info.viewportEndOffset) / 2
            info.visibleItemsInfo.firstOrNull { it.offset <= mid && it.offset + it.size >= mid }?.index ?: list.firstVisibleItemIndex
        }
    }
    // Gezeichnete Seiten freigeben, sobald die Ansicht verschwindet oder die App in den Hintergrund geht.
    DisposableEffect(pages) { onDispose { vm.trimPdfCache() } }
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) { vm.trimPdfCache() }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val width = constraints.maxWidth.toFloat().coerceAtLeast(1f)
        val height = constraints.maxHeight.toFloat().coerceAtLeast(1f)
        val center = Offset(width / 2f, height / 2f)
        // Vergrößert um die Mitte reicht der Inhalt über alle Ränder; so weit darf man ihn verschieben.
        fun clamp(o: Offset, s: Float): Offset {
            val limitX = max(0f, (width * s - width) / 2f)
            val limitY = max(0f, (height * s - height) / 2f)
            return Offset(o.x.coerceIn(-limitX, limitX), o.y.coerceIn(-limitY, limitY))
        }
        fun zoomTo(target: Float, focus: Offset) {
            val fromS = scale
            val fromO = shift
            val toO = if (target <= 1f) Offset.Zero else clamp((focus - center) * (1f - target / fromS) + fromO * (target / fromS), target)
            scope.launch {
                animate(0f, 1f, animationSpec = motion.standard()) { f, _ ->
                    scale = fromS + (target - fromS) * f
                    shift = fromO + (toO - fromO) * f
                }
            }
        }
        LazyColumn(
            state = list,
            modifier = Modifier
                .fillMaxSize()
                .semantics {
                    customActions = listOf(
                        CustomAccessibilityAction("Vergrößern") {
                            zoomTo(minOf(PDF_MAX_ZOOM, scale * 1.5f), center)
                            true
                        },
                        CustomAccessibilityAction("Verkleinern") {
                            zoomTo(1f, center)
                            true
                        },
                    )
                }
                // Zwei Finger fangen wir ab, bevor die Liste sie als Scrollen deutet; ein Finger scrollt wie gewohnt.
                .pointerInput(pages) {
                    awaitEachGesture {
                        awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                        do {
                            val event = awaitPointerEvent(PointerEventPass.Initial)
                            if (event.changes.count { it.pressed } >= 2) {
                                val zoom = event.calculateZoom()
                                val pan = event.calculatePan()
                                val c = event.calculateCentroid(useCurrent = true)
                                val newScale = (scale * zoom).coerceIn(1f, PDF_MAX_ZOOM)
                                val ratio = newScale / scale
                                val focus = if (c == Offset.Unspecified) center else c
                                shift = clamp((focus - center) * (1f - ratio) + shift * ratio + pan, newScale)
                                scale = newScale
                                event.changes.forEach { if (it.positionChanged()) it.consume() }
                            }
                        } while (event.changes.any { it.pressed })
                        if (scale < 1.01f) {
                            scale = 1f
                            shift = Offset.Zero
                        }
                    }
                }
                .pointerInput(pages) {
                    detectTapGestures(onDoubleTap = { p -> zoomTo(if (scale > 1.01f) 1f else 2f, p) })
                }
                .graphicsLayer {
                    scaleX = scale
                    scaleY = scale
                    translationX = shift.x
                    translationY = shift.y
                },
            contentPadding = PaddingValues(start = Spacing.page, end = Spacing.page, bottom = bottomPadding + 64.dp),
            verticalArrangement = Arrangement.spacedBy(Spacing.m),
        ) {
            items(pages.pageCount, key = { it }) { index -> PdfPage(vm, pages, index) }
        }
        if (pages.pageCount > 0) {
            GlassSurface(
                Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = bottomPadding + Spacing.s),
                elevated = true,
            ) {
                Text(
                    "Seite ${Fmt.count(current + 1)} von ${Fmt.count(pages.pageCount)}",
                    color = colors.text,
                    style = Aether.type.caption,
                    modifier = Modifier.padding(horizontal = Spacing.l, vertical = Spacing.s),
                )
            }
        }
    }
}

@Composable
private fun PdfPage(vm: PreviewViewModel, pages: PdfPages, index: Int) {
    val colors = Aether.colors
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        // 1,5-fache Auflösung: bleibt beim Zoomen lesbar, ohne den Speicher zu sprengen.
        val widthPx = (constraints.maxWidth * 1.5f).toInt().coerceIn(200, 2400)
        val bitmap: Bitmap? by produceState<Bitmap?>(null, pages, index, widthPx) { value = vm.renderPage(index, widthPx) }
        // Bis die Seite gezeichnet ist, gilt die erste Seite als Muster für das Seitenverhältnis.
        val aspect = bitmap?.let { it.width.toFloat() / it.height.coerceAtLeast(1) }
            ?: (pages.knownPageSize(index) ?: pages.firstPageSize).let { (w, h) -> w.toFloat().coerceAtLeast(1f) / h.toFloat().coerceAtLeast(1f) }
        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(aspect)
                .clip(RoundedCornerShape(4.dp))
                .background(colors.fill)
                .semantics { contentDescription = "Seite ${index + 1} von ${pages.pageCount}" },
        ) {
            bitmap?.let { b ->
                Image(b.asImageBitmap(), contentDescription = null, contentScale = ContentScale.FillBounds, modifier = Modifier.fillMaxSize())
            }
        }
    }
}
