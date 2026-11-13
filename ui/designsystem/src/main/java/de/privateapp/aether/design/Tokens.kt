package de.privateapp.aether.design

import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Immutable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.privateapp.aether.model.appearance.EffectIntensity

/*
 * Zentrale Gestaltungswerte. Farben: PaletteSpec.kt / Palette.kt. Kein Bildschirm legt eigene Abstände,
 * Radien, Dauern oder Farben fest – alles kommt von hier.
 */

/** Abstände (Raster 4 dp). */
object Spacing {
    val xxs = 2.dp
    val xs = 4.dp
    val s = 8.dp
    val m = 12.dp
    val l = 16.dp
    val xl = 20.dp
    val xxl = 24.dp
    val xxxl = 32.dp
    val huge = 48.dp

    /** Seitenrand auf Telefonen. */
    val page = 20.dp

    /** Abstand zwischen Karten. */
    val cardGap = 14.dp

    /** Innenabstand von Karten. */
    val cardPadding = 18.dp

    /** Höchstbreite des Inhalts auf großen Displays (Lesbarkeit). */
    val contentMaxWidth = 760.dp
}

/** Eckenradien – bewusst nur fünf Stufen. */
object Radii {
    val small = 10.dp
    val control = 14.dp
    val card = 24.dp
    val sheet = 30.dp

    /** Schwebende Leisten (Pillenform). */
    val bar = 32.dp
}

/** Schatten (nur in hellen Themes sichtbar; im Dunkeln trägt Licht an den Kanten die Tiefe). */
object Elevation {
    val card = 10.dp
    val floating = 24.dp
}

/** Mindestgröße für Berührflächen (Bedienungshilfen). */
val MinTouchTarget: Dp = 48.dp

/**
 * Bewegung: kurz, ruhig, physikalisch nachvollziehbar. Rückmeldung 110–160 ms, Übergänge 300–420 ms.
 * Keine Dauerbewegung, kein Pulsieren, keine künstlichen Wartezeiten.
 */
object Motion {
    const val PRESS_MS = 110
    const val QUICK_MS = 160
    const val STANDARD_MS = 300
    const val EMPHASIZED_MS = 420
    const val THEME_MS = 450

    /** Kurze Überblendung, wenn Bewegung reduziert ist. */
    const val REDUCED_FADE_MS = 90

    val Standard: Easing = CubicBezierEasing(0.2f, 0f, 0f, 1f)
    val Emphasized: Easing = CubicBezierEasing(0.05f, 0.7f, 0.1f, 1f)
    val Exit: Easing = CubicBezierEasing(0.3f, 0f, 0.8f, 0.15f)
}

/**
 * Bewegungsschema, abhängig von „Animationen entfernen“ (Android) bzw. „Bewegung reduzieren“ (App).
 * Ist Bewegung reduziert, springen Werte ohne Gleiten auf das Ziel; Übergänge werden kurze Überblendungen.
 */
@Immutable
data class MotionScheme(val reduced: Boolean, val decorative: Boolean) {
    fun <T> standard(durationMs: Int = Motion.STANDARD_MS): FiniteAnimationSpec<T> =
        if (reduced) snap() else tween(durationMs, easing = Motion.Standard)

    fun <T> emphasized(durationMs: Int = Motion.EMPHASIZED_MS): FiniteAnimationSpec<T> =
        if (reduced) snap() else tween(durationMs, easing = Motion.Emphasized)

    /** Weiche Feder ohne Überschwingen – für Auswahl-Linsen und Größenänderungen. */
    fun <T> gentleSpring(): FiniteAnimationSpec<T> =
        if (reduced) snap() else spring(dampingRatio = 0.86f, stiffness = Spring.StiffnessMediumLow)

    /** Für Überblendungen, die auch bei reduzierter Bewegung sinnvoll sind (Inhaltswechsel). */
    fun <T> fade(durationMs: Int = Motion.QUICK_MS): FiniteAnimationSpec<T> =
        tween(if (reduced) Motion.REDUCED_FADE_MS else durationMs, easing = Motion.Standard)
}

/** Effekt-Konfiguration aus Theme und Effektstärke. */
@Immutable
data class EffectConfig(
    val intensity: EffectIntensity,
    /** Glasmaterial (Verlauf, Glanz, Lichtkante) für Inhaltsflächen. */
    val glassMaterial: Boolean,
    /** Echtzeit-Unschärfe für schwebende Leisten. */
    val blur: Boolean,
    val blurRadius: Dp,
    /** Farbsättigung des weichgezeichneten Hintergrunds (1 = unverändert). */
    val saturation: Float,
    /** Stärke der Atmosphäre 0…1 (1 = geprüfter Höchstwert). */
    val atmosphere: Float,
    /** Stärke von Glanz und Lichtkanten 0…1. */
    val sheen: Float,
    val shadows: Boolean,
) {
    companion object {
        fun of(base: BaseSpec, intensity: EffectIntensity, lowRamDevice: Boolean): EffectConfig = when (intensity) {
            EffectIntensity.MINIMAL -> EffectConfig(
                intensity, glassMaterial = false, blur = false, blurRadius = 0.dp, saturation = 1f,
                atmosphere = 0f, sheen = 0f, shadows = !base.isDark,
            )
            EffectIntensity.BALANCED -> EffectConfig(
                intensity, glassMaterial = base.glass, blur = base.glass && !lowRamDevice, blurRadius = 26.dp, saturation = 1.35f,
                atmosphere = 0.7f, sheen = 0.8f, shadows = true,
            )
            EffectIntensity.IMMERSIVE -> EffectConfig(
                intensity, glassMaterial = base.glass, blur = base.glass && !lowRamDevice, blurRadius = 38.dp, saturation = 1.6f,
                atmosphere = 1f, sheen = 1f, shadows = true,
            )
        }
    }
}
