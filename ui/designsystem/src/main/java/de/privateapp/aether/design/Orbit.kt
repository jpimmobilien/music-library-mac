package de.privateapp.aether.design

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.PowerManager
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.isSpecified
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.addOutline
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.privateapp.aether.model.appearance.EffectIntensity
import de.privateapp.aether.model.orbit.OrbitEffects
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.sin

/*
 * ORBIT – „Spatial Liquid Glass“ für Android: Grundfarben, Effekt-Schalter, Atmosphären-Verschiebung, Lichtreflex
 * an der Berührstelle, ORBIT-Zeichen, flüssiger Fortschritt, Akku-Flüssigkeit, ruhige Zahlenwechsel, Haptik.
 *
 * Leistungsregeln: Dauerbewegung nur, solange der dargestellte Vorgang echt läuft (Laden, Dateivorgang) oder im
 * Profil „Immersiv“ für den Hintergrund (gedrosselt, nur im Vordergrund, nicht im Energiesparmodus). Animierte Werte
 * werden in der Zeichenphase gelesen – es wird neu gezeichnet, nicht neu komponiert.
 */

/** Grundfarben von ORBIT (identisch mit macOS: Sources/AetherCore/Orbit.swift). */
object OrbitPalette {
    const val ARCTIC_BLUE = 0xFF3D8BFF
    const val ELECTRIC_CYAN = 0xFF18D6F0
    const val DEEP_OCEAN = 0xFF07142B
    const val SAPPHIRE = 0xFF2446C8
    const val SOFT_VIOLET = 0xFF8C7CFF
    const val PEARL_WHITE = 0xFFF4F7FB
    const val GRAPHITE = 0xFF2B2F38
}

/** Farben mit Bedeutung: Blau = System, Cyan = Datenströme, Violett = Auswertungen. */
@Stable
class OrbitTones(val isDark: Boolean) {
    val system: Color = if (isDark) Color(0xFF6FB5FF) else Color(0xFF0952C0)
    val data: Color = if (isDark) Color(0xFF3FDDEF) else Color(0xFF00667F)
    val smart: Color = if (isDark) Color(0xFFB3A3FF) else Color(0xFF5B41C7)
    val sapphire: Color = if (isDark) Color(0xFF8F9BFF) else Color(0xFF2446C8)
    val core: List<Color> = listOf(Color(OrbitPalette.ELECTRIC_CYAN), Color(OrbitPalette.ARCTIC_BLUE), Color(OrbitPalette.SAPPHIRE))

    /** Schrift und Lichtkanten auf dem leuchtenden Kern (immer hell – der Kern ist in jedem Theme kräftig blau). */
    val onCore: Color = Color.White
}

val LocalOrbitEffects = staticCompositionLocalOf { OrbitEffects.resolve(EffectIntensity.BALANCED, reducedMotion = false, powerSave = false) }

/** Haptik aus den Einstellungen (Android selbst kann Vibration zusätzlich ausschalten). */
val LocalHapticsEnabled = staticCompositionLocalOf { true }

/**
 * Verschiebung der Atmosphären-Lichtfelder als Anteil der Fläche. Wird in der Zeichenphase gelesen (Lambda), damit
 * Hintergrund und Kantenübergänge deckungsgleich bleiben und nur neu gezeichnet wird.
 */
val LocalAtmosphereShift = staticCompositionLocalOf<() -> Offset> { { Offset.Zero } }

object Orbit {
    val effects: OrbitEffects
        @Composable get() = LocalOrbitEffects.current

    val tones: OrbitTones
        @Composable get() {
            val dark = Aether.colors.isDark
            return remember(dark) { OrbitTones(dark) }
        }
}

/** Energiesparmodus des Geräts (beendet die Hintergrund-Drift sofort). */
@Composable
fun rememberPowerSaveMode(): Boolean {
    val context = LocalContext.current
    val power = remember(context) { context.getSystemService(PowerManager::class.java) }
    var saving by remember { mutableStateOf(power?.isPowerSaveMode == true) }
    DisposableEffect(context) {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, intent: Intent?) {
                saving = power?.isPowerSaveMode == true
            }
        }
        val filter = IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
        onDispose { runCatching { context.unregisterReceiver(receiver) } }
    }
    return saving
}

// MARK: Lichtreflex an der Berührstelle

/**
 * Weicher Lichtreflex auf Glasflächen dort, wo der Finger aufsetzt; verblasst beim Loslassen. Beobachtet nur
 * (verbraucht keine Ereignisse) – Klicks und Wischgesten funktionieren unverändert.
 */
@Composable
fun Modifier.touchReflection(shape: Shape): Modifier {
    val effects = Orbit.effects
    val glass = Aether.effects.glassMaterial
    if (!effects.touchReflection || !glass) return this
    val colors = Aether.colors
    val scope = rememberCoroutineScope()
    val alpha = remember { Animatable(0f) }
    var point by remember { mutableStateOf(Offset.Unspecified) }
    val tint = if (colors.isDark) Color.White.copy(alpha = 0.16f) else Color.White.copy(alpha = 0.7f)
    return this
        .pointerInput(Unit) {
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false)
                point = down.position
                scope.launch { alpha.animateTo(1f, tween(110)) }
                waitForUpOrCancellation()
                scope.launch { alpha.animateTo(0f, tween(480)) }
            }
        }
        .drawWithContent {
            drawContent()
            val a = alpha.value
            val p = point
            if (a > 0.01f && p.isSpecified) {
                val outline = shape.createOutline(size, layoutDirection, this)
                val clip = Path().apply { addOutline(outline) }
                val r = size.maxDimension * 0.65f
                clipPath(clip) {
                    drawCircle(
                        Brush.radialGradient(listOf(tint.copy(alpha = tint.alpha * a), Color.Transparent), center = p, radius = r),
                        radius = r,
                        center = p,
                    )
                }
            }
        }
}

// MARK: ORBIT-Zeichen (Auftakt, leere Zustände)

/** Kern mit zwei Umlaufbahnen und Lichtpunkt; optional mit Symbol in der Mitte. Rein illustrativ. */
@Composable
fun OrbitMark(modifier: Modifier = Modifier, size: Dp = 96.dp, icon: ImageVector? = null, muted: Boolean = false) {
    val tones = Orbit.tones
    val colors = Aether.colors
    val ring = if (muted) listOf(colors.textTertiary.copy(alpha = 0.45f), colors.textTertiary.copy(alpha = 0.12f))
    else listOf(tones.data.copy(alpha = 0.9f), tones.system.copy(alpha = 0.5f), tones.smart.copy(alpha = 0.6f))
    val core = if (muted) listOf(colors.textTertiary.copy(alpha = 0.35f), colors.textTertiary.copy(alpha = 0.18f)) else tones.core
    Box(modifier.size(size, size * 0.62f).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(size, size * 0.62f)) {
            val w = this.size.width
            val c = center
            val stroke = (w * 0.018f).coerceAtLeast(1.5f)
            rotate(-24f, c) {
                drawOval(Brush.horizontalGradient(ring), topLeft = Offset(c.x - w / 2, c.y - w * 0.21f), size = Size(w, w * 0.42f), style = Stroke(stroke))
            }
            rotate(38f, c) {
                drawOval(
                    Brush.horizontalGradient(ring.map { it.copy(alpha = it.alpha * 0.7f) }),
                    topLeft = Offset(c.x - w * 0.42f, c.y - w * 0.17f),
                    size = Size(w * 0.84f, w * 0.34f),
                    style = Stroke(stroke * 0.8f),
                )
            }
            val r = w * 0.17f
            if (!muted) drawCircle(Brush.radialGradient(listOf(tones.system.copy(alpha = 0.45f), Color.Transparent), c, r * 2.2f), r * 2.2f, c)
            drawCircle(Brush.linearGradient(core, start = Offset(c.x + r, c.y - r), end = Offset(c.x - r, c.y + r)), r, c)
            drawCircle(Color.White.copy(alpha = if (colors.isDark) 0.25f else 0.6f), r, c, style = Stroke(1.dp.toPx()))
            drawCircle(if (muted) colors.textTertiary else tones.data, w * 0.035f, Offset(c.x + w * 0.45f, c.y - w * 0.12f))
        }
        if (icon != null) Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(size * 0.15f))
    }
}

// MARK: Flüssiger Fortschritt

/**
 * Fortschrittsbalken: Die Füllung folgt dem echten Fortschritt (weich), der Lichtschimmer läuft nur, solange
 * [active] (der Vorgang arbeitet wirklich) und Bewegung erlaubt ist.
 */
@Composable
fun LiquidProgressBar(fraction: Float, active: Boolean, modifier: Modifier = Modifier, color: Color = Orbit.tones.data, height: Dp = 6.dp) {
    val colors = Aether.colors
    val motion = Aether.motion
    val shown by animateFloatAsState(fraction.coerceIn(0f, 1f), motion.standard(Motion.STANDARD_MS), label = "progress")
    val flowing = active && Orbit.effects.dataFlow
    val sheen = if (flowing) {
        val t = rememberInfiniteTransition(label = "sheen")
        t.animateFloat(0f, 1f, infiniteRepeatable(tween(1600, easing = LinearEasing), RepeatMode.Restart), label = "sheenPos")
    } else {
        null
    }
    Canvas(modifier.fillMaxWidth().height(height)) {
        val r = CornerRadius(size.height / 2, size.height / 2)
        drawRoundRect(colors.fill, cornerRadius = r)
        val w = size.width * shown
        if (w > 0f) {
            drawRoundRect(Brush.horizontalGradient(listOf(color.copy(alpha = 0.75f), color), endX = w), size = Size(w, size.height), cornerRadius = r)
            val s = sheen?.value
            if (s != null) {
                val band = size.width * 0.25f
                val x = -band + (w + band * 2) * s
                clipPath(Path().apply { addRoundRect(androidx.compose.ui.geometry.RoundRect(0f, 0f, w, size.height, r)) }) {
                    drawRect(
                        Brush.horizontalGradient(listOf(Color.Transparent, Color.White.copy(alpha = 0.45f), Color.Transparent), startX = x - band / 2, endX = x + band / 2),
                        topLeft = Offset(x - band / 2, 0f),
                        size = Size(band, size.height),
                    )
                }
            }
        }
    }
}

// MARK: Akku-Flüssigkeit

/**
 * Akku als Glaskörper mit Flüssigkeit: Füllstand = gemessener Ladestand. Die Oberfläche bewegt sich nur, solange
 * Android „lädt“ meldet ([charging]) und Bewegung erlaubt ist – sonst ruht sie glatt.
 */
@Composable
fun BatteryLiquid(level: Float?, charging: Boolean, color: Color, modifier: Modifier = Modifier) {
    val colors = Aether.colors
    val moving = charging && Orbit.effects.dataFlow && level != null
    val fill by animateFloatAsState((level ?: 0f).coerceIn(0f, 1f), Aether.motion.standard(Motion.EMPHASIZED_MS), label = "level")
    val phase = if (moving) {
        val t = rememberInfiniteTransition(label = "wave")
        t.animateFloat(0f, (2 * PI).toFloat(), infiniteRepeatable(tween(2200, easing = LinearEasing)), label = "wavePhase")
    } else {
        null
    }
    Canvas(modifier.width(64.dp).height(30.dp)) {
        val capW = size.width * 0.07f
        val bodyW = size.width - capW - 2.dp.toPx()
        val h = size.height
        val corner = CornerRadius(h * 0.26f, h * 0.26f)
        // Gehäuse
        drawRoundRect(colors.fill, size = Size(bodyW, h), cornerRadius = corner)
        drawRoundRect(colors.hairline.copy(alpha = 0.9f), size = Size(bodyW, h), cornerRadius = corner, style = Stroke(1.dp.toPx()))
        drawRoundRect(colors.fillStrong, topLeft = Offset(bodyW + 2.dp.toPx(), h * 0.32f), size = Size(capW, h * 0.36f), cornerRadius = CornerRadius(capW / 2, capW / 2))
        if (level == null) return@Canvas
        val inset = h * 0.12f
        val innerW = bodyW - inset * 2
        val innerH = h - inset * 2
        val x = inset + innerW * fill
        val inner = androidx.compose.ui.geometry.RoundRect(inset, inset, inset + innerW, inset + innerH, CornerRadius(h * 0.18f, h * 0.18f))
        clipPath(Path().apply { addRoundRect(inner) }) {
            val p = Path()
            val amp = if (phase != null) h * 0.06f else 0f
            val ph = phase?.value ?: 0f
            p.moveTo(inset, inset)
            // Vorderkante der Flüssigkeit (senkrecht): leichte Welle beim Laden
            val steps = 16
            for (i in 0..steps) {
                val y = inset + innerH * i / steps
                val dx = amp * sin(ph + i * 0.8f)
                p.lineTo(x + dx, y)
            }
            p.lineTo(inset, inset + innerH)
            p.close()
            drawPath(p, Brush.verticalGradient(listOf(color, color.copy(alpha = 0.7f))))
            drawRect(Color.White.copy(alpha = if (colors.isDark) 0.18f else 0.32f), topLeft = Offset(inset, inset + innerH * 0.08f), size = Size(x - inset, innerH * 0.14f))
        }
    }
}

// MARK: Ruhige Zahlenwechsel

/** Text, der bei einer Änderung kurz von unten einblendet (nur „Immersiv“); sonst ein gewöhnlicher Text. */
@Composable
fun RollingText(text: String, style: TextStyle, color: Color, modifier: Modifier = Modifier) {
    if (!Orbit.effects.numberTransitions) {
        Text(text, style = style, color = color, modifier = modifier)
        return
    }
    AnimatedContent(
        targetState = text,
        transitionSpec = {
            (slideInVertically(tween(260, easing = Motion.Standard)) { it / 3 } + fadeIn(tween(200))) togetherWith
                (slideOutVertically(tween(220, easing = Motion.Exit)) { -it / 3 } + fadeOut(tween(160)))
        },
        modifier = modifier,
        label = "rolling",
    ) { value ->
        Text(value, style = style, color = color)
    }
}

// MARK: Haptik

/** Haptisches Feedback für wichtige Interaktionen. Respektiert die App-Einstellung und die Android-Einstellung. */
@Stable
class OrbitHaptics internal constructor(private val view: View, private val enabled: Boolean) {
    /** Auswahl (Bereich, Segment). */
    fun tick() = perform(HapticFeedbackConstants.CLOCK_TICK)

    /** Vorgang erfolgreich abgeschlossen. */
    fun confirm() = perform(HapticFeedbackConstants.CONFIRM)

    /** Vorgang fehlgeschlagen oder abgelehnt. */
    fun reject() = perform(HapticFeedbackConstants.REJECT)

    /** Langes Drücken (Auswahl beginnt). */
    fun longPress() = perform(HapticFeedbackConstants.LONG_PRESS)

    private fun perform(constant: Int) {
        if (enabled) view.performHapticFeedback(constant)
    }
}

@Composable
fun rememberOrbitHaptics(): OrbitHaptics {
    val view = LocalView.current
    val enabled = LocalHapticsEnabled.current
    return remember(view, enabled) { OrbitHaptics(view, enabled) }
}

// MARK: Ringe (ORBIT Core)

/** Eine Bahn des ORBIT Core: Bogen (0…1) oder – ohne Wert – gestrichelte, leere Bahn. */
data class OrbitTrack(val arc: Float?, val color: Color)

/**
 * Konzentrische Bahnen mit Kern. Bögen gleiten bei Änderung (in der Zeichenphase gelesen); Lichtpunkt auf der Bahn
 * [flowIndex] kreist nur, solange [flow] > 0 (echter Durchsatz) und Bewegung erlaubt ist – Geschwindigkeit folgt [flow].
 */
@Composable
fun OrbitRings(tracks: List<OrbitTrack>, modifier: Modifier = Modifier, flowIndex: Int = -1, flow: Float = 0f) {
    val colors = Aether.colors
    val tones = Orbit.tones
    val motion = Aether.motion
    val arcs = tracks.map { t ->
        animateFloatAsState(t.arc ?: 0f, if (Orbit.effects.dataFlow) motion.standard(600) else motion.standard(0), label = "arc")
    }
    val moving = Orbit.effects.dataFlow && flow >= 0.02f && flowIndex in tracks.indices
    val angle = if (moving) {
        val period = (12_000 - 9_500 * flow.coerceIn(0f, 1f)).toInt().coerceAtLeast(1_500)
        val t = rememberInfiniteTransition(label = "satellite")
        t.animateFloat(0f, 360f, infiniteRepeatable(tween(period, easing = LinearEasing)), label = "satAngle")
    } else {
        null
    }
    val dash = remember { PathEffect.dashPathEffect(floatArrayOf(6f, 12f)) }
    Canvas(modifier) {
        val line = 7.dp.toPx()
        val gap = 5.dp.toPx()
        val outer = size.minDimension / 2 - line / 2 - 2.dp.toPx()
        val n = tracks.size
        for ((i, t) in tracks.withIndex()) {
            val radius = outer - (n - 1 - i) * (line + gap)
            val tl = Offset(center.x - radius, center.y - radius)
            val sz = Size(radius * 2, radius * 2)
            if (t.arc == null) {
                drawCircle(colors.textTertiary.copy(alpha = 0.35f), radius, center, style = Stroke(1.5.dp.toPx(), pathEffect = dash))
            } else {
                drawCircle(colors.fill, radius, center, style = Stroke(line))
                val sweep = 360f * arcs[i].value.coerceIn(0.004f, 1f)
                drawArc(t.color, -90f, sweep, false, tl, sz, style = Stroke(line, cap = StrokeCap.Round))
            }
        }
        val innermost = outer - (n - 1) * (line + gap)
        val coreR = (innermost - line / 2 - 10.dp.toPx()).coerceAtLeast(16.dp.toPx())
        drawCircle(Brush.radialGradient(listOf(tones.system.copy(alpha = 0.35f), Color.Transparent), center, coreR * 1.9f), coreR * 1.9f, center)
        drawCircle(Brush.linearGradient(tones.core, start = Offset(center.x + coreR, center.y - coreR), end = Offset(center.x - coreR, center.y + coreR)), coreR, center)
        drawCircle(Color.White.copy(alpha = 0.3f), coreR, center, style = Stroke(1.dp.toPx()))
        val a = angle?.value
        if (a != null) {
            val radius = outer - (n - 1 - flowIndex) * (line + gap)
            val rad = Math.toRadians((a - 90).toDouble())
            val p = Offset(center.x + radius * kotlin.math.cos(rad).toFloat(), center.y + radius * kotlin.math.sin(rad).toFloat())
            drawCircle(Color.White.copy(alpha = 0.5f), 5.dp.toPx(), p)
            drawCircle(Color.White, 2.5.dp.toPx(), p)
        }
    }
}
