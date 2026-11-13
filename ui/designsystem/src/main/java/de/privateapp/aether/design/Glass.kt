package de.privateapp.aether.design

import android.graphics.ColorMatrixColorFilter
import android.graphics.Shader
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.RenderEffect
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.asComposeRenderEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import kotlin.math.ceil

/*
 * Liquid Glass unter Android.
 *
 * Android kennt keine Hintergrundunschärfe für einzelne Bereiche innerhalb eines Fensters. Umsetzung
 * (bewährt in Musikbibliothek 1.3.0, für ORBIT übernommen und angepasst):
 *  1. Der Inhalt hinter schwebenden Leisten wird mit [backdropSource] zusätzlich in eine Grafikebene
 *     (RenderNode) aufgezeichnet. Die Quelle enthält den deckenden App-Hintergrund – sonst schiene der
 *     scharfe Inhalt durch freie Stellen der Unschärfe.
 *  2. [GlassSurface] zeichnet genau ihren Ausschnitt dieser Ebene in eine eigene Ebene mit Weichzeichner
 *     und leicht erhöhter Sättigung (GPU, RenderEffect ab Android 12) und legt Tönung, Glanz und eine
 *     zweifarbige Lichtkante darüber.
 * Es werden keine Bitmaps kopiert. Unschärfe gibt es nur für schwebende Elemente; Karten im Inhalt nutzen
 * das gezeichnete Glasmaterial [glassPanel] – ruhiger, besser lesbar, sparsamer. Ohne Unschärfe (Effektstärke
 * „Minimal“, Low-RAM-Geräte) wird die Tönung fast deckend; die Lesbarkeit hängt nie von der Unschärfe ab.
 */

/** Quelle für Glas-Unschärfe (der Inhalt hinter schwebenden Leisten). */
@Stable
class Backdrop internal constructor(internal val layer: GraphicsLayer) {
    internal var coordinates: LayoutCoordinates? = null

    /** Zählt neue Aufnahmen; Glasflächen lesen den Wert beim Zeichnen und werden so aktualisiert. */
    internal var version by mutableIntStateOf(0)
}

@Composable
fun rememberBackdrop(): Backdrop {
    val layer = rememberGraphicsLayer()
    return remember(layer) { Backdrop(layer) }
}

/**
 * Zeichnet den Inhalt normal und zusätzlich in [backdrop]. Glasflächen, die [backdrop] verwenden, dürfen NICHT
 * innerhalb dieses Inhalts liegen (sonst entstünde eine Rückkopplung).
 */
fun Modifier.backdropSource(backdrop: Backdrop): Modifier = this
    .onGloballyPositioned { backdrop.coordinates = it }
    .drawWithContent {
        backdrop.layer.record { this@drawWithContent.drawContent() }
        drawLayer(backdrop.layer)
        // Ohne Lese-Beobachtung erhöhen – sonst würde sich die Quelle selbst ständig neu zeichnen.
        Snapshot.withoutReadObservation { backdrop.version = backdrop.version + 1 }
    }

/** Weichzeichner + leicht erhöhte Sättigung (wie bei Glas, durch das farbige Inhalte leuchten). */
private fun glassRenderEffect(radiusPx: Float, saturation: Float): RenderEffect {
    val blur = android.graphics.RenderEffect.createBlurEffect(radiusPx, radiusPx, Shader.TileMode.CLAMP)
    // Sättigungsmatrix (entspricht ColorMatrix.setSaturation, Luminanzgewichte nach Rec. 709)
    val inv = 1f - saturation
    val r = 0.213f * inv
    val g = 0.715f * inv
    val b = 0.072f * inv
    val matrix = floatArrayOf(
        r + saturation, g, b, 0f, 0f,
        r, g + saturation, b, 0f, 0f,
        r, g, b + saturation, 0f, 0f,
        0f, 0f, 0f, 1f, 0f,
    )
    val saturate = android.graphics.RenderEffect.createColorFilterEffect(ColorMatrixColorFilter(matrix))
    return android.graphics.RenderEffect.createChainEffect(saturate, blur).asComposeRenderEffect()
}

/** Hält den zuletzt erzeugten Effekt, damit beim Scrollen nicht in jedem Bild neue Objekte entstehen. */
private class GlassEffectCache {
    private var radius = -1f
    private var saturation = -1f
    private var effect: RenderEffect? = null

    fun get(radiusPx: Float, sat: Float): RenderEffect {
        val e = effect
        if (e != null && radiusPx == radius && sat == saturation) return e
        return glassRenderEffect(radiusPx, sat).also {
            effect = it
            radius = radiusPx
            saturation = sat
        }
    }
}

/**
 * Schwebende Glasfläche (Reiterleiste, Kopfleiste, Bedienfelder).
 *
 * @param backdrop Inhalt dahinter, der unscharf durchscheinen soll. Ohne Angabe: fast deckende Tönung.
 * @param elevated weicher Schatten (in dunklen Themes trägt die Lichtkante die Tiefe).
 */
@Composable
fun GlassSurface(
    modifier: Modifier = Modifier,
    shape: Shape = RoundedCornerShape(Radii.bar),
    backdrop: Backdrop? = null,
    elevated: Boolean = true,
    content: @Composable BoxScope.() -> Unit,
) {
    val colors = Aether.colors
    val effects = Aether.effects
    val useBlur = effects.blur && backdrop != null
    val blurLayer = if (useBlur) rememberGraphicsLayer() else null
    val cache = remember { GlassEffectCache() }
    // Position dieser Fläche im Koordinatensystem der Quelle (für den passenden Ausschnitt).
    var offsetInSource by remember { mutableStateOf(Offset.Zero) }

    val fill = if (useBlur) colors.glassTint else colors.glassTintSolid
    val shadowModifier = if (elevated && colors.shadow.alpha > 0f) {
        Modifier.shadow(Elevation.floating, shape, clip = false, ambientColor = colors.shadow, spotColor = colors.shadow)
    } else {
        Modifier
    }
    val positionModifier = if (useBlur) {
        Modifier.onGloballyPositioned { coords ->
            val source = backdrop.coordinates
            if (source != null && source.isAttached && coords.isAttached) {
                val p = source.localPositionOf(coords, Offset.Zero)
                if (p != offsetInSource) offsetInSource = p
            }
        }
    } else {
        Modifier
    }
    val edge = Brush.linearGradient(
        listOf(colors.glassEdgeLight, colors.glassEdgeDark, colors.glassEdgeLight.copy(alpha = colors.glassEdgeLight.alpha * 0.5f)),
    )
    val sheenAlpha = effects.sheen
    Box(
        modifier = modifier
            .then(shadowModifier)
            .then(positionModifier)
            .clip(shape)
            .drawBehind {
                if (blurLayer != null && backdrop != null) {
                    backdrop.version // beobachten: neu zeichnen, wenn sich der Inhalt dahinter ändert
                    val radiusPx = effects.blurRadius.toPx()
                    val margin = ceil(radiusPx).toInt()
                    blurLayer.renderEffect = cache.get(radiusPx, effects.saturation)
                    val o = offsetInSource
                    blurLayer.record(size = IntSize(size.width.toInt() + 2 * margin, size.height.toInt() + 2 * margin)) {
                        translate(-o.x + margin, -o.y + margin) { drawLayer(backdrop.layer) }
                    }
                    translate(-margin.toFloat(), -margin.toFloat()) { drawLayer(blurLayer) }
                }
                drawRect(fill)
                if (sheenAlpha > 0f) {
                    // Glanz von oben und ein Hauch Tiefe nach unten.
                    drawRect(
                        Brush.verticalGradient(
                            0f to colors.glassEdgeLight.copy(alpha = colors.glassEdgeLight.alpha * 0.22f * sheenAlpha),
                            0.5f to Color.Transparent,
                        ),
                    )
                    drawRect(Brush.verticalGradient(0.6f to Color.Transparent, 1f to Color.Black.copy(alpha = if (colors.isDark) 0.10f else 0.025f)))
                }
            }
            .border(width = 0.8.dp, brush = edge, shape = shape)
            // Glas ist eine eigene Ebene: Berührungen auf freien Stellen dürfen nicht zum Inhalt darunter durchrutschen.
            .pointerInput(Unit) { awaitPointerEventScope { while (true) awaitPointerEvent() } },
    ) {
        CompositionLocalProvider(LocalContentColor provides colors.text) { content() }
    }
}

/**
 * Glasmaterial für Inhaltsflächen (ohne Echtzeit-Unschärfe): Verlauf, Glanz im oberen Drittel, Lichtkante oben,
 * Schattenkante unten; im hellen Thema ein weicher Schatten (Tiefe), im dunklen trägt das Licht die Tiefe.
 * Ohne Glasmaterial (Minimal Hell, Effektstärke Minimal): deckende Fläche mit feiner Linie.
 */
fun Modifier.glassPanel(colors: AetherColors, radius: Dp = Radii.card, lift: Boolean = true): Modifier {
    val shape = RoundedCornerShape(radius)
    val shadowed = if (lift && !colors.isDark && colors.shadow.alpha > 0f) {
        this.shadow(Elevation.card, shape, clip = false, ambientColor = colors.shadow.copy(alpha = colors.shadow.alpha * 0.7f), spotColor = colors.shadow)
    } else {
        this
    }
    return shadowed.drawBehind { drawPanelMaterial(colors, radius.toPx()) }
}

/** Zeichnet das Inhaltsglas in die gesamte Fläche (auch für eigene Zeichner nutzbar). */
fun DrawScope.drawPanelMaterial(colors: AetherColors, radiusPx: Float) {
    val r = CornerRadius(radiusPx)
    drawRoundRect(Brush.verticalGradient(listOf(colors.panelTop, colors.panelBottom)), cornerRadius = r)
    if (colors.sheen.alpha > 0f) {
        drawRoundRect(
            Brush.verticalGradient(0f to colors.sheen, 0.4f to colors.sheen.copy(alpha = 0f), 1f to Color.Transparent),
            cornerRadius = r,
        )
    }
    val stroke = 1.dp.toPx()
    val inset = stroke / 2f
    drawRoundRect(
        Brush.verticalGradient(
            0f to colors.panelEdgeTop,
            0.22f to colors.panelEdgeTop.copy(alpha = colors.panelEdgeTop.alpha * 0.4f),
            0.65f to colors.panelEdgeBottom,
            1f to colors.panelEdgeBottom,
        ),
        topLeft = Offset(inset, inset),
        size = Size(size.width - stroke, size.height - stroke),
        cornerRadius = CornerRadius((radiusPx - inset).coerceAtLeast(0f)),
        style = Stroke(width = stroke),
    )
}

/**
 * Atmosphärischer App-Hintergrund: sanfter Verlauf und drei sehr weiche Lichtfelder (Akzent oben links, kühl
 * oben rechts, warm unten). Statisch – keine Dauerbewegung; radiale Verläufe kosten praktisch nichts.
 */
@Composable
fun AtmosphereBackground(modifier: Modifier = Modifier) {
    val colors = Aether.colors
    Box(modifier.fillMaxSize().drawBehind { drawAtmosphere(colors) })
}

/**
 * Zeichnet die Atmosphäre. [area] = Fläche, auf die sich die Lichtfelder beziehen (normalerweise die eigene
 * Größe; für Kantenübergänge die ganze Bildschirmfläche, damit Übergang und Hintergrund deckungsgleich sind).
 */
fun DrawScope.drawAtmosphere(colors: AetherColors, area: Size = size) {
    if (area.width <= 0f || area.height <= 0f) return
    drawRect(
        Brush.verticalGradient(0f to colors.backgroundTop, 0.55f to colors.background, 1f to colors.backgroundBottom, startY = 0f, endY = area.height),
        size = area,
    )
    val w = area.width
    val h = area.height
    val radius = maxOf(w, h) * 0.62f
    fun field(color: Color, center: Offset, r: Float) {
        if (color.alpha <= 0f) return
        drawCircle(Brush.radialGradient(listOf(color, color.copy(alpha = 0f)), center = center, radius = r), radius = r, center = center)
    }
    field(colors.atmosphereAccent, Offset(w * -0.05f, h * 0.04f), radius)
    field(colors.atmosphereCool, Offset(w * 1.08f, h * 0.30f), radius * 0.9f)
    field(colors.atmosphereWarm, Offset(w * 0.25f, h * 1.02f), radius)
}

/**
 * Weicher Übergang an Bildschirmkanten: Inhalte laufen unter Statusleiste bzw. schwebender Navigation sanft
 * aus, statt hart abgeschnitten oder schlecht lesbar zu sein. Der Übergang zeichnet dieselbe Atmosphäre wie
 * der Hintergrund ([fullHeight] = Höhe der ganzen Fläche) und blendet sie mit einer Verlaufsmaske aus – so
 * entsteht keine sichtbare Farbkante.
 */
@Composable
fun EdgeFade(top: Boolean, fullHeight: Dp, modifier: Modifier = Modifier, strength: Float = 0.92f) {
    val colors = Aether.colors
    Box(
        modifier
            .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
            .drawBehind {
                val full = Size(size.width, fullHeight.toPx().coerceAtLeast(size.height))
                val dy = if (top) 0f else size.height - full.height
                translate(top = dy) { drawAtmosphere(colors, full) }
                val mask = if (top) {
                    Brush.verticalGradient(0f to Color.Black.copy(alpha = strength), 0.55f to Color.Black.copy(alpha = strength * 0.6f), 1f to Color.Transparent)
                } else {
                    Brush.verticalGradient(0f to Color.Transparent, 0.5f to Color.Black.copy(alpha = strength * 0.55f), 1f to Color.Black.copy(alpha = strength))
                }
                drawRect(mask, blendMode = BlendMode.DstIn)
            },
    )
}
