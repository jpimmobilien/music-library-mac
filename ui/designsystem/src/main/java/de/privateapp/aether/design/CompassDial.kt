package de.privateapp.aether.design

import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import de.privateapp.aether.model.motion.Angles
import kotlin.math.cos
import kotlin.math.sin

/**
 * Kompassrose: Die Skala dreht sich, die Markierung oben steht fest – oben liegt immer die Richtung, in die die
 * Oberkante des Telefons zeigt (wie beim Kompass auf dem iPhone). Striche alle 2°, längere alle 10°, Zahlen alle 30°,
 * Himmelsrichtungen aufrecht lesbar; Nord trägt zusätzlich ein Dreieck (nicht nur Farbe).
 *
 * Neue Richtungen gleiten über den kürzesten Weg an (359° → 1° dreht 2° vorwärts, nicht 358° zurück); bei
 * reduzierter Bewegung springt die Skala. [headingDegrees] `null` = kein Kompass – die Skala bleibt blass stehen.
 * TalkBack liest [description] (z. B. „Richtung 245 Grad, Südwesten“).
 */
@Composable
fun CompassDial(
    headingDegrees: Double?,
    description: String,
    modifier: Modifier = Modifier,
    center: @Composable BoxScope.() -> Unit = {},
) {
    val colors = Aether.colors
    val type = Aether.type
    val motion = Aether.motion
    val measurer = rememberTextMeasurer()

    // Fortlaufender Winkel (nicht auf 0…360 begrenzt), damit die Animation nie „rückwärts herum“ läuft.
    val angle = remember { Animatable((headingDegrees ?: 0.0).toFloat()) }
    LaunchedEffect(headingDegrees, motion.reduced) {
        val target = headingDegrees ?: return@LaunchedEffect
        val destination = angle.value + Angles.shortestDelta(angle.value.toDouble(), target).toFloat()
        if (motion.reduced) angle.snapTo(destination) else angle.animateTo(destination, motion.gentleSpring())
    }

    val labels: Map<Int, TextLayoutResult> = remember(measurer, colors, type) {
        (0 until 360 step 30).associateWith { deg ->
            val cardinal = when (deg) {
                0 -> "N"
                90 -> "O"
                180 -> "S"
                270 -> "W"
                else -> null
            }
            val style = when {
                deg == 0 -> type.headline.copy(color = colors.critical)
                cardinal != null -> type.headline.copy(color = colors.text)
                else -> type.micro.copy(color = colors.textSecondary)
            }
            measurer.measure(cardinal ?: deg.toString(), style)
        }
    }

    Box(
        modifier
            .aspectRatio(1f)
            .graphicsLayer { alpha = if (headingDegrees == null) 0.4f else 1f }
            .clearAndSetSemantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val r = size.minDimension / 2f
            val c = this.center
            val heading = angle.value
            fun polar(radius: Float, dialDegrees: Float): Offset {
                val a = Math.toRadians((dialDegrees - heading).toDouble())
                return Offset(c.x + radius * sin(a).toFloat(), c.y - radius * cos(a).toFloat())
            }

            // Ruhige Fläche hinter der Anzeige in der Mitte
            drawCircle(colors.fill, radius = r * 0.56f, center = c)

            // Skala
            val outer = r * 0.95f
            for (deg in 0 until 360 step 2) {
                val major = deg % 30 == 0
                val mid = deg % 10 == 0
                val length = when {
                    major -> r * 0.12f
                    mid -> r * 0.085f
                    else -> r * 0.05f
                }
                val color = when {
                    deg == 0 -> colors.critical
                    major -> colors.text
                    mid -> colors.textSecondary
                    else -> colors.textTertiary
                }
                val width = when {
                    major -> 2.dp
                    mid -> 1.5.dp
                    else -> 1.dp
                }
                drawLine(color, polar(outer - length, deg.toFloat()), polar(outer, deg.toFloat()), strokeWidth = width.toPx(), cap = StrokeCap.Round)
            }

            // Beschriftung (aufrecht)
            for ((deg, layout) in labels) {
                val p = polar(r * 0.69f, deg.toFloat())
                drawText(layout, topLeft = Offset(p.x - layout.size.width / 2f, p.y - layout.size.height / 2f))
            }

            // Nord-Dreieck außen an der Skala
            val tip = polar(r * 0.995f, 0f)
            val baseL = polar(outer - r * 0.005f, -3.2f)
            val baseR = polar(outer - r * 0.005f, 3.2f)
            if (headingDegrees != null) {
                drawPath(
                    Path().apply {
                        moveTo(tip.x, tip.y)
                        lineTo(baseL.x, baseL.y)
                        lineTo(baseR.x, baseR.y)
                        close()
                    },
                    colors.critical,
                )
            }

            // Feste Markierung oben: hierhin zeigt das Telefon
            drawLine(
                colors.accent,
                Offset(c.x, c.y - r * 0.995f),
                Offset(c.x, c.y - r * 0.74f),
                strokeWidth = 3.dp.toPx(),
                cap = StrokeCap.Round,
            )
        }
        center()
    }
}
