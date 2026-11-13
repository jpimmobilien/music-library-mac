package de.privateapp.aether.design

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/*
 * Diagramme. Sie zeigen nur übergebene, echte Werte; ohne Wert bleibt die Spur leer. Jede Grafik trägt eine
 * Beschreibung für TalkBack – Farbe allein trägt nie die Aussage.
 */

/**
 * Speicherring: Spur als eingelassene Glasröhre, belegter Anteil als Bogen mit sanftem Verlauf und
 * Lichtkante. Neue Werte gleiten weich an (beim ersten Wert mit einer ruhigen Einlaufbewegung).
 */
@Composable
fun StorageRing(
    usedFraction: Float?,
    description: String,
    modifier: Modifier = Modifier,
    thickness: Dp = 16.dp,
    center: @Composable BoxScope.() -> Unit = {},
) {
    val colors = Aether.colors
    val motion = Aether.motion
    val effects = Aether.effects
    val target = (usedFraction ?: 0f).coerceIn(0f, 1f)
    val animated = remember { Animatable(0f) }
    LaunchedEffect(target, motion.reduced) {
        if (motion.reduced) {
            animated.snapTo(target)
        } else {
            // Erster Wert: ruhiger Einlauf; spätere Änderungen gleiten kurz – kein Springen, kein Pulsieren.
            val duration = if (animated.value == 0f) 900 else Motion.EMPHASIZED_MS
            animated.animateTo(target, tween(duration, easing = Motion.Emphasized))
        }
    }
    Box(modifier.clearAndSetSemantics { contentDescription = description }, contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val stroke = thickness.toPx()
            val diameter = size.minDimension - stroke
            val topLeft = Offset((size.width - diameter) / 2f, (size.height - diameter) / 2f)
            val arcSize = Size(diameter, diameter)
            // Spur
            drawArc(colors.fill, 0f, 360f, false, topLeft, arcSize, style = Stroke(stroke))
            if (effects.glassMaterial && colors.sheen.alpha > 0f) {
                // Innenschatten der Spur: oben eine Spur dunkler – die Röhre liegt tiefer
                drawArc(
                    Brush.verticalGradient(
                        listOf(Color.Black.copy(alpha = if (colors.isDark) 0.18f else 0.05f), Color.Transparent),
                        startY = topLeft.y, endY = topLeft.y + diameter,
                    ),
                    0f, 360f, false, topLeft, arcSize, style = Stroke(stroke),
                )
            }
            val sweep = 360f * animated.value
            if (sweep > 0.5f) {
                rotate(-90f) {
                    val brush = Brush.sweepGradient(
                        0f to colors.accent,
                        (animated.value * 0.999f).coerceAtLeast(0.001f) to colors.accentGlow,
                        // zurück zum Akzent: die runde Kappe am Bogenanfang liegt optisch kurz vor 360°
                        1f to colors.accent,
                        center = this.center,
                    )
                    drawArc(brush, 0f, sweep, false, topLeft, arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
                    if (effects.sheen > 0f && effects.glassMaterial) {
                        // Lichtkante auf dem Bogen (glasige Röhre)
                        val inset = stroke * 0.2f
                        val r = diameter / 2f - inset
                        val c = this.center
                        drawArc(
                            Color.White.copy(alpha = (if (colors.isDark) 0.22f else 0.38f) * effects.sheen),
                            2f, (sweep - 4f).coerceAtLeast(0f), false,
                            Offset(c.x - r, c.y - r), Size(2 * r, 2 * r),
                            style = Stroke(stroke * 0.22f, cap = StrokeCap.Round),
                        )
                    }
                }
            }
        }
        center()
    }
}

/** Schmaler Füllbalken (z. B. Belegung weiterer Speicherorte, Arbeitsspeicher). */
@Composable
fun CapacityBar(
    fraction: Float?,
    modifier: Modifier = Modifier,
    tone: Tone = Tone.ACCENT,
    height: Dp = 6.dp,
) {
    val colors = Aether.colors
    val motion = Aether.motion
    val value by animateFloatAsState((fraction ?: 0f).coerceIn(0f, 1f), motion.emphasized(), label = "bar")
    val fillColor = if (tone == Tone.ACCENT) colors.accent else colors.tone(tone)
    Canvas(modifier.fillMaxWidth().height(height)) {
        val r = CornerRadius(size.height / 2f)
        drawRoundRect(colors.fill, cornerRadius = r)
        if (value > 0f) {
            val w = (size.width * value).coerceAtLeast(size.height)
            drawRoundRect(
                Brush.horizontalGradient(listOf(fillColor, if (tone == Tone.ACCENT) colors.accentGlow else fillColor), endX = w),
                size = Size(w, size.height),
                cornerRadius = r,
            )
        }
    }
}

/**
 * Stufenanzeige (z. B. Thermalstatus mit sieben Android-Stufen). [current] = Index der aktuellen Stufe
 * oder `null`, wenn kein Wert vorliegt. Die aktuelle Stufe ist zusätzlich höher gezeichnet – nicht nur farbig.
 */
@Composable
fun LevelScale(
    steps: Int,
    current: Int?,
    toneOf: (Int) -> Tone,
    description: String,
    modifier: Modifier = Modifier,
) {
    val colors = Aether.colors
    val motion = Aether.motion
    val position by animateFloatAsState((current ?: -1).toFloat(), motion.gentleSpring(), label = "level")
    Canvas(modifier.fillMaxWidth().height(14.dp).clearAndSetSemantics { contentDescription = description }) {
        val gap = 3.dp.toPx()
        val w = (size.width - gap * (steps - 1)) / steps
        val low = 6.dp.toPx()
        for (i in 0 until steps) {
            val active = current != null && i <= current
            val isCurrent = current != null && kotlin.math.abs(position - i) < 0.5f
            val h = if (isCurrent) size.height else low
            val color = when {
                active -> colors.tone(toneOf(i))
                else -> colors.fill
            }
            drawRoundRect(
                color,
                topLeft = Offset(i * (w + gap), (size.height - h) / 2f),
                size = Size(w, h),
                cornerRadius = CornerRadius(h / 2f),
            )
        }
    }
}

/** Akku-Symbol mit Füllstand; beim Laden mit Blitz. Nur Darstellung – der Wert steht immer daneben als Text. */
@Composable
fun BatteryGlyph(level: Int?, charging: Boolean, tone: Tone, modifier: Modifier = Modifier) {
    val colors = Aether.colors
    val motion = Aether.motion
    val fill by animateFloatAsState(((level ?: 0) / 100f).coerceIn(0f, 1f), motion.emphasized(), label = "battery")
    val color = if (tone == Tone.ACCENT) colors.accent else colors.tone(tone)
    Canvas(modifier.size(width = 46.dp, height = 24.dp)) {
        val stroke = 1.7.dp.toPx()
        val nub = 3.dp.toPx()
        val body = Size(size.width - nub - stroke, size.height - stroke)
        val r = CornerRadius(6.dp.toPx())
        drawRoundRect(colors.textSecondary, topLeft = Offset(stroke / 2, stroke / 2), size = body, cornerRadius = r, style = Stroke(stroke))
        drawRoundRect(
            colors.textSecondary,
            topLeft = Offset(size.width - nub, size.height * 0.32f),
            size = Size(nub, size.height * 0.36f),
            cornerRadius = CornerRadius(nub / 2),
        )
        val pad = stroke + 2.dp.toPx()
        val inner = Size(body.width - 2 * pad + stroke, body.height - 2 * pad + stroke)
        if (level != null && fill > 0f) {
            drawRoundRect(
                color,
                topLeft = Offset(pad, pad),
                size = Size((inner.width * fill).coerceAtLeast(inner.height * 0.5f), inner.height),
                cornerRadius = CornerRadius(3.dp.toPx()),
            )
        }
        if (charging) {
            val cx = body.width / 2f + stroke / 2
            val cy = size.height / 2f
            val s = size.height * 0.34f
            val bolt = Path().apply {
                moveTo(cx + s * 0.15f, cy - s)
                lineTo(cx - s * 0.55f, cy + s * 0.12f)
                lineTo(cx - s * 0.02f, cy + s * 0.12f)
                lineTo(cx - s * 0.15f, cy + s)
                lineTo(cx + s * 0.55f, cy - s * 0.12f)
                lineTo(cx + s * 0.02f, cy - s * 0.12f)
                close()
            }
            drawPath(bolt, colors.surfaceRaised)
            drawPath(bolt, colors.text, style = Stroke(1.dp.toPx()))
        }
    }
}
