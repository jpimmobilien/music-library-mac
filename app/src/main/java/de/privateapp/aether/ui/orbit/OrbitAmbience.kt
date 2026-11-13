package de.privateapp.aether.ui.orbit

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateOffsetAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.LocalAtmosphereShift
import de.privateapp.aether.design.Motion
import de.privateapp.aether.design.Orbit
import de.privateapp.aether.design.OrbitMark
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/*
 * ORBIT-Atmosphäre und Auftakt.
 *  - Räumlicher Hintergrund: Jeder Bereich hat eine eigene, leicht versetzte Lage der Lichtfelder; beim Wechsel
 *    gleiten sie in 1,4 s dorthin (Ausgewogen, Immersiv).
 *  - Lebendiger Hintergrund (nur Immersiv): sehr langsame Drift (Umlauf ≈ 1 min), gedrosselt auf ~15 Bilder/s, nur
 *    solange die App im Vordergrund ist und der Energiesparmodus aus ist (OrbitEffects.livingBackground).
 *  - Auftakt: ≈ 0,8 s beim Kaltstart, liegt über dem bereits gezeichneten Inhalt, nimmt keine Eingaben an.
 */

@Composable
fun ProvideAtmosphereMotion(area: Int, areaCount: Int, content: @Composable () -> Unit) {
    val effects = Orbit.effects
    val target = if (effects.spatialBackground && areaCount > 0) {
        val a = area.toDouble() / areaCount * 2 * PI
        Offset((cos(a) * 0.06).toFloat(), (sin(a) * 0.04).toFloat())
    } else {
        Offset.Zero
    }
    val spatial = animateOffsetAsState(target, tween(1400, easing = Motion.Emphasized), label = "atmosphere")
    val drift = remember { mutableStateOf(Offset.Zero) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(effects.livingBackground, lifecycle) {
        if (!effects.livingBackground) {
            drift.value = Offset.Zero
            return@LaunchedEffect
        }
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            val start = System.nanoTime()
            while (isActive) {
                val t = (System.nanoTime() - start) / 1e9
                drift.value = Offset((sin(t * 2 * PI / 58) * 0.05).toFloat(), (cos(t * 2 * PI / 73) * 0.035).toFloat())
                delay(66) // ~15 Bilder/s genügen für eine Bewegung von wenigen Pixeln pro Sekunde
            }
        }
    }
    val shift = remember(spatial, drift) { { spatial.value + drift.value } }
    CompositionLocalProvider(LocalAtmosphereShift provides shift, content = content)
}

/** Pro Prozess einmal (weitere Aktivitäten, z. B. nach dem Drehen, ohne Auftakt). */
private object IntroState {
    var played = false
}

/** Auftakt beim Kaltstart (ORBIT-Zeichen, Schriftzug). Ohne Bewegung nur eine kurze Überblendung; Minimal: nichts. */
@Composable
fun OrbitIntroOverlay() {
    val effects = Orbit.effects
    if (IntroState.played || !effects.ambientIntro) {
        IntroState.played = true
        return
    }
    val colors = Aether.colors
    val cover = remember { Animatable(1f) }
    val mark = remember { Animatable(0f) }
    val visible = remember { mutableStateOf(true) }
    LaunchedEffect(Unit) {
        if (effects.introFadeOnly) {
            cover.animateTo(0f, tween(220))
        } else {
            launch { mark.animateTo(1f, tween(360, easing = Motion.Emphasized)) }
            delay(430)
            cover.animateTo(0f, tween(400, easing = Motion.Standard))
        }
        IntroState.played = true
        visible.value = false
    }
    if (!visible.value) return
    Box(
        Modifier
            .fillMaxSize()
            .graphicsLayer { alpha = cover.value }
            .background(Brush.verticalGradient(listOf(colors.backgroundTop, colors.background, colors.backgroundBottom)))
            .clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) {
        if (!effects.introFadeOnly) {
            Column(
                Modifier.graphicsLayer {
                    alpha = mark.value
                    val s = 0.94f + 0.06f * mark.value
                    scaleX = s
                    scaleY = s
                },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                OrbitMark(size = 128.dp)
                Text("ORBIT", color = colors.text, style = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 9.sp))
            }
        }
    }
}
