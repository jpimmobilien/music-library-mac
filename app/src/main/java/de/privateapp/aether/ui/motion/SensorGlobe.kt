package de.privateapp.aether.ui.motion

import android.graphics.Paint
import android.graphics.Typeface
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.Orbit
import de.privateapp.aether.design.Panel
import de.privateapp.aether.design.PanelHeader
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.design.rememberOrbitHaptics
import de.privateapp.aether.model.motion.SatelliteSignal
import kotlin.math.cos
import kotlin.math.sin

/*
 * ORBIT „Interactive Sensor Globe“: Himmelskugel über dem Gerät mit den Satelliten, die der GNSS-Empfänger gerade
 * meldet (Richtung = Azimut, Höhe = Elevation, Punktgröße = Signalstärke, hell = für die Position genutzt) und der
 * Blickrichtung des Telefons (Kompass). Alles sind Messwerte des Geräts; nichts wird simuliert. Ziehen dreht und
 * neigt die Kugel, Doppeltippen stellt die Ansicht zurück.
 */

private const val DEFAULT_TILT = 55f

@Composable
internal fun SensorGlobePanel(state: MotionState, vm: MotionViewModel) {
    val compass by vm.compass.collectAsStateWithLifecycle()
    val heading = (compass as? CompassState.Live)?.heading?.degrees?.toFloat()
    val colors = Aether.colors
    val tones = Orbit.tones
    val haptics = rememberOrbitHaptics()
    var yaw by rememberSaveable { mutableFloatStateOf(0f) }
    var tilt by rememberSaveable { mutableFloatStateOf(DEFAULT_TILT) }
    val signals = state.satellites.signals
    val received = signals.count { it.cn0DbHz > 0f }
    val used = signals.count { it.usedInFix }
    val labelPaint = remember {
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
    }
    Panel {
        PanelHeader(AetherIcons.Satellite, "Sensor-Globus", subtitle = "Satelliten über dir – ziehen zum Drehen")
        Spacer(Modifier.height(Spacing.m))
        Canvas(
            Modifier
                .fillMaxWidth()
                .aspectRatio(1.15f)
                .pointerInput(Unit) {
                    detectDragGestures { change, drag ->
                        change.consume()
                        yaw = (yaw + drag.x * 0.35f) % 360f
                        tilt = (tilt - drag.y * 0.25f).coerceIn(15f, 90f)
                    }
                }
                .pointerInput(Unit) {
                    detectTapGestures(onDoubleTap = {
                        yaw = 0f
                        tilt = DEFAULT_TILT
                        haptics.tick()
                    })
                }
                .semantics {
                    contentDescription = "Sensor-Globus: $received Satelliten mit Signal, davon $used genutzt" +
                        (heading?.let { ", Blickrichtung ${it.toInt()} Grad" } ?: "")
                },
        ) {
            val r = size.minDimension * 0.44f
            val c = Offset(size.width / 2, size.height / 2 + r * 0.08f)
            fun project(azimuth: Float, elevation: Float): Pair<Offset, Float> {
                val a = Math.toRadians((azimuth + yaw).toDouble())
                val e = Math.toRadians(elevation.toDouble())
                val x = cos(e) * sin(a)
                val y = cos(e) * cos(a)
                val z = sin(e)
                val t = Math.toRadians(tilt.toDouble())
                // Neigung um die Ost-West-Achse: 90° = Draufsicht (Himmelskarte), kleiner = schräger Blick
                val yv = y * sin(t) - z * cos(t)
                val depth = y * cos(t) + z * sin(t)
                return Offset(c.x + (x * r).toFloat(), c.y - (yv * r).toFloat()) to depth.toFloat()
            }
            // Kugel
            drawCircle(Brush.radialGradient(listOf(tones.system.copy(alpha = 0.18f), Color.Transparent), c, r * 1.15f), r * 1.15f, c)
            drawGrid(::project, colors.hairline.copy(alpha = 0.9f), colors.textTertiary.copy(alpha = 0.55f))
            // Himmelsrichtungen
            labelPaint.textSize = 12f.dp2px(this)
            labelPaint.color = colors.textSecondary.toArgb()
            for ((label, az) in listOf("N" to 0f, "O" to 90f, "S" to 180f, "W" to 270f)) {
                val (p, d) = project(az, -6f)
                labelPaint.alpha = if (d < -0.2f) 110 else 255
                drawContext.canvas.nativeCanvas.drawText(label, p.x, p.y + labelPaint.textSize / 3, labelPaint)
            }
            // Blickrichtung des Telefons (Kompass)
            if (heading != null) {
                val (from, _) = project(heading, 0f)
                val (to, _) = project(heading, 12f)
                drawLine(tones.smart, c, from, strokeWidth = 2.5f.dp2px(this))
                drawCircle(tones.smart, 4f.dp2px(this), from)
                drawLine(tones.smart.copy(alpha = 0.4f), from, to, strokeWidth = 1.5f.dp2px(this))
            }
            // Satelliten: hinten (Tiefe < 0) blasser, genutzte hell mit Lichthof
            val sorted = signals.sortedBy { project(it.azimuthDegrees, it.elevationDegrees).second }
            for (s in sorted) drawSatellite(s, project(s.azimuthDegrees, s.elevationDegrees), tones.data, colors.textTertiary)
            // Kern: das Gerät
            drawCircle(Brush.linearGradient(tones.core, start = Offset(c.x + 8f, c.y - 8f), end = Offset(c.x - 8f, c.y + 8f)), 7f.dp2px(this), c)
        }
        Spacer(Modifier.height(Spacing.s))
        Text(
            if (signals.isEmpty()) "Der Empfänger hat noch keine Satelliten gemeldet." else "$received mit Signal · $used für die Position genutzt · Größe = Signalstärke",
            style = Aether.type.footnote,
            color = colors.textTertiary,
        )
    }
}

private fun Float.dp2px(scope: DrawScope): Float = this * scope.density

private fun DrawScope.drawGrid(project: (Float, Float) -> Pair<Offset, Float>, line: Color, horizon: Color) {
    val dash = PathEffect.dashPathEffect(floatArrayOf(4f * density, 6f * density))
    // Horizont und Höhenkreise 30° / 60°
    for (elevation in listOf(0f, 30f, 60f)) {
        val path = Path()
        for (i in 0..72) {
            val (p, _) = project(i * 5f, elevation)
            if (i == 0) path.moveTo(p.x, p.y) else path.lineTo(p.x, p.y)
        }
        drawPath(path, if (elevation == 0f) horizon else line, style = Stroke(if (elevation == 0f) 1.5f * density else 1f * density, pathEffect = if (elevation == 0f) null else dash))
    }
    // Meridiane alle 45°
    for (k in 0 until 8) {
        val path = Path()
        for (e in 0..18) {
            val (p, _) = project(k * 45f, e * 5f)
            if (e == 0) path.moveTo(p.x, p.y) else path.lineTo(p.x, p.y)
        }
        drawPath(path, line, style = Stroke(1f * density, pathEffect = dash))
    }
}

private fun DrawScope.drawSatellite(s: SatelliteSignal, projected: Pair<Offset, Float>, active: Color, idle: Color) {
    val (p, depth) = projected
    val back = depth < 0f
    val strength = (s.cn0DbHz / 50f).coerceIn(0f, 1f)
    val radius = (2.5f + 4.5f * strength) * density
    val base = when {
        s.usedInFix -> active
        s.cn0DbHz > 0f -> active.copy(alpha = 0.55f)
        else -> idle.copy(alpha = 0.6f)
    }
    val color = if (back) base.copy(alpha = base.alpha * 0.45f) else base
    if (s.usedInFix && !back) drawCircle(Brush.radialGradient(listOf(active.copy(alpha = 0.45f), Color.Transparent), p, radius * 2.6f), radius * 2.6f, p)
    if (s.cn0DbHz > 0f) drawCircle(color, radius, p) else drawCircle(color, radius, p, style = Stroke(1.2f * density))
}
