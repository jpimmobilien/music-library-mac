package de.privateapp.aether.design

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/** Tonalität für Status, Hinweise und Markierungen. Farbe ist nie der einzige Träger einer Aussage. */
enum class Tone { NEUTRAL, ACCENT, SUCCESS, WARNING, CRITICAL, INFO }

/**
 * Alle Farbrollen der Oberfläche. Bildschirme verwenden ausschließlich diese Rollen – nie feste Farben.
 */
@Immutable
data class AetherColors(
    val isDark: Boolean,
    val backgroundTop: Color,
    val background: Color,
    val backgroundBottom: Color,
    /** Drei sehr weiche Lichtfelder der Atmosphäre (Akzent, kühl, warm) – bereits mit Effektstärke verrechnet. */
    val atmosphereAccent: Color,
    val atmosphereCool: Color,
    val atmosphereWarm: Color,
    val panelTop: Color,
    val panelBottom: Color,
    val panelEdgeTop: Color,
    val panelEdgeBottom: Color,
    val sheen: Color,
    val surface: Color,
    val surfaceRaised: Color,
    val glassTint: Color,
    val glassTintSolid: Color,
    val glassEdgeLight: Color,
    val glassEdgeDark: Color,
    val shadow: Color,
    val fill: Color,
    val fillStrong: Color,
    val hairline: Color,
    val text: Color,
    val textSecondary: Color,
    val textTertiary: Color,
    val textDisabled: Color,
    val accent: Color,
    val onAccent: Color,
    /** Zarte Akzentfläche (Auswahl, Linse der Reiterleiste). */
    val accentSoft: Color,
    /** Hellere bzw. kräftigere Variante für Verläufe in Diagrammen. */
    val accentGlow: Color,
    val success: Color,
    val warning: Color,
    val critical: Color,
    val info: Color,
    val scrim: Color,
) {
    fun tone(t: Tone): Color = when (t) {
        Tone.NEUTRAL -> textSecondary
        Tone.ACCENT -> accent
        Tone.SUCCESS -> success
        Tone.WARNING -> warning
        Tone.CRITICAL -> critical
        Tone.INFO -> info
    }

    /** Zarte Hinterlegung passend zur Tonalität (Hinweisflächen, Plaketten). */
    fun toneSoft(t: Tone): Color = when (t) {
        Tone.NEUTRAL -> fill
        else -> tone(t).copy(alpha = if (isDark) 0.16f else 0.10f)
    }

    companion object {
        /** Farbrollen aus Grundpalette, Akzent (0xAARRGGBB) und Effektkonfiguration. */
        fun from(base: BaseSpec, accentArgb: Long, effects: EffectConfig): AetherColors {
            val accent = argb(accentArgb)
            val atmosphere = effects.atmosphere.coerceIn(0f, 1f)
            val sheenScale = if (effects.glassMaterial) effects.sheen.coerceIn(0f, 1f) else 0f
            fun scaled(c: Long, factor: Float): Color = argb(c).let { it.copy(alpha = it.alpha * factor) }
            // Ohne Glasmaterial (Minimal-Stufe): Inhaltsflächen deckend wie „surface“, Kanten als feine Linie.
            val panelTop = if (effects.glassMaterial) argb(base.panelTop) else argb(base.surface)
            val panelBottom = if (effects.glassMaterial) argb(base.panelBottom) else argb(base.surface)
            val edgeTop = if (effects.glassMaterial) argb(base.panelEdgeTop) else argb(base.hairline)
            val edgeBottom = if (effects.glassMaterial) argb(base.panelEdgeBottom) else argb(base.hairline)
            return AetherColors(
                isDark = base.isDark,
                backgroundTop = argb(base.backgroundTop),
                background = argb(base.background),
                backgroundBottom = argb(base.backgroundBottom),
                atmosphereAccent = accent.copy(alpha = base.atmosphereAccentAlpha * atmosphere),
                atmosphereCool = scaled(base.atmosphereCool, atmosphere),
                atmosphereWarm = scaled(base.atmosphereWarm, atmosphere),
                panelTop = panelTop,
                panelBottom = panelBottom,
                panelEdgeTop = edgeTop,
                panelEdgeBottom = edgeBottom,
                sheen = scaled(base.sheen, sheenScale),
                surface = argb(base.surface),
                surfaceRaised = argb(base.surfaceRaised),
                glassTint = argb(base.glassTint),
                glassTintSolid = argb(base.glassTintSolid),
                glassEdgeLight = argb(base.glassEdgeLight),
                glassEdgeDark = argb(base.glassEdgeDark),
                shadow = if (effects.shadows) argb(base.shadow) else Color.Transparent,
                fill = argb(base.fill),
                fillStrong = argb(base.fillStrong),
                hairline = argb(base.hairline),
                text = argb(base.text),
                textSecondary = argb(base.textSecondary),
                textTertiary = argb(base.textTertiary),
                textDisabled = argb(base.textDisabled),
                accent = accent,
                onAccent = argb(base.onAccent),
                accentSoft = accent.copy(alpha = if (base.isDark) 0.20f else 0.13f),
                accentGlow = argb(ColorMath.glow(accentArgb, base.isDark)),
                success = argb(base.success),
                warning = argb(base.warning),
                critical = argb(base.critical),
                info = argb(base.info),
                scrim = argb(base.scrim),
            )
        }

        /** 0xAARRGGBB → Compose-Farbe (ohne die Vorzeichenfallen von Int). */
        fun argb(value: Long): Color = Color(
            red = ((value ushr 16) and 0xFF).toInt(),
            green = ((value ushr 8) and 0xFF).toInt(),
            blue = (value and 0xFF).toInt(),
            alpha = ((value ushr 24) and 0xFF).toInt(),
        )
    }
}

val LocalAetherColors = staticCompositionLocalOf {
    AetherColors.from(
        PaletteSpec.GlassLight,
        PaletteSpec.fallbackAccent.onLight,
        EffectConfig.of(PaletteSpec.GlassLight, de.privateapp.aether.model.appearance.EffectIntensity.BALANCED, lowRamDevice = false),
    )
}
