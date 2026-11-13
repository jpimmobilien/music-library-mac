package de.privateapp.aether.design

import android.app.ActivityManager
import android.content.ContentResolver
import android.content.Context
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import de.privateapp.aether.model.appearance.AccentChoice
import de.privateapp.aether.model.appearance.AppearanceSettings
import de.privateapp.aether.model.appearance.EffectIntensity

val LocalEffects = staticCompositionLocalOf {
    EffectConfig.of(PaletteSpec.GlassLight, EffectIntensity.BALANCED, lowRamDevice = false)
}
val LocalMotion = staticCompositionLocalOf { MotionScheme(reduced = false, decorative = true) }

/** Ergebnis der Theme-Auflösung – z. B. für die Einstellungen („Systemfarbe nicht kontrastreich genug“). */
data class ResolvedAccent(val argb: Long, val systemAccentRejected: Boolean)

/**
 * Thema von ORBIT. Löst Design, Akzent und Effektstärke auf, stellt die eigenen Gestaltungswerte bereit und
 * bildet sie zusätzlich auf Material 3 ab, damit Standardbausteine (Schalter, Menüs, Auswahl) passen.
 *
 * Wichtig (Lehre aus Musikbibliothek 1.3.0): `MaterialTheme` setzt die Inhaltsfarbe NICHT – Compose nimmt
 * dann Schwarz an. Deshalb wird `LocalContentColor` hier zentral auf die Textfarbe gesetzt; Text ohne eigene
 * Farbe ist so in jedem Theme lesbar.
 *
 * Themewechsel blenden alle Farbrollen weich über (450 ms); bei reduzierter Bewegung sofort.
 */
@Composable
fun AetherTheme(
    settings: AppearanceSettings,
    content: @Composable () -> Unit,
) {
    val context = LocalContext.current
    val systemDark = isSystemInDarkTheme()
    val base = PaletteSpec.base(settings.theme, systemDark)
    val lowRam = remember(context) { context.getSystemService(ActivityManager::class.java)?.isLowRamDevice == true }
    val effects = EffectConfig.of(base, settings.intensity, lowRam)
    val accent = remember(base, settings.accent, context) { resolveAccent(settings.accent, base, context) }
    val target = remember(base, accent, effects) { AetherColors.from(base, accent.argb, effects) }

    val systemReducedMotion = rememberSystemReducedMotion()
    val reduced = systemReducedMotion || settings.reduceMotion
    val motion = MotionScheme(reduced = reduced, decorative = !reduced && settings.intensity != EffectIntensity.MINIMAL)
    val colors = animateColors(target, if (reduced) snap() else tween(Motion.THEME_MS, easing = Motion.Standard))

    CompositionLocalProvider(
        LocalAetherColors provides colors,
        LocalAetherTypography provides DefaultTypography,
        LocalEffects provides effects,
        LocalMotion provides motion,
        LocalSystemReducedMotion provides systemReducedMotion,
        LocalResolvedAccent provides accent,
    ) {
        MaterialTheme(colorScheme = materialScheme(colors), typography = materialTypography) {
            CompositionLocalProvider(LocalContentColor provides colors.text, content = content)
        }
    }
}

/** `true`, wenn Android selbst Animationen entfernt (unabhängig von der App-Einstellung). */
val LocalSystemReducedMotion = staticCompositionLocalOf { false }
val LocalResolvedAccent = staticCompositionLocalOf { ResolvedAccent(PaletteSpec.fallbackAccent.onLight, systemAccentRejected = false) }

/**
 * Akzentfarbe auflösen. Die Systemfarbe (Material You) wird erst übernommen, wenn sie dieselben Kontrastregeln
 * erfüllt wie die festen Akzente – sonst bleibt Ocean Blue, und die Einstellungen sagen das.
 */
private fun resolveAccent(choice: AccentChoice, base: BaseSpec, context: Context): ResolvedAccent {
    if (choice != AccentChoice.SYSTEM) {
        val spec = PaletteSpec.accents[choice] ?: PaletteSpec.fallbackAccent
        return ResolvedAccent(spec.forDark(base.isDark), systemAccentRejected = false)
    }
    val fallback = PaletteSpec.fallbackAccent.forDark(base.isDark)
    val system = try {
        val scheme = if (base.isDark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        scheme.primary.toArgb().toLong() and 0xFFFFFFFFL
    } catch (e: RuntimeException) {
        return ResolvedAccent(fallback, systemAccentRejected = true)
    }
    val grounds = ColorMath.textGrounds(base, system)
    val tracks = grounds.map { ColorMath.over(base.fill, it) }
    val ok = ColorMath.minContrast(system, grounds) >= 4.5 &&
        ColorMath.contrast(base.onAccent, system) >= 4.5 &&
        ColorMath.minContrast(ColorMath.glow(system, base.isDark), tracks) >= 3.0
    return if (ok) ResolvedAccent(system, systemAccentRejected = false) else ResolvedAccent(fallback, systemAccentRejected = true)
}

@Composable
private fun animateColors(t: AetherColors, spec: AnimationSpec<Color>): AetherColors {
    @Composable
    fun a(c: Color): Color = animateColorAsState(c, spec, label = "theme").value
    return AetherColors(
        isDark = t.isDark,
        backgroundTop = a(t.backgroundTop),
        background = a(t.background),
        backgroundBottom = a(t.backgroundBottom),
        atmosphereAccent = a(t.atmosphereAccent),
        atmosphereCool = a(t.atmosphereCool),
        atmosphereWarm = a(t.atmosphereWarm),
        panelTop = a(t.panelTop),
        panelBottom = a(t.panelBottom),
        panelEdgeTop = a(t.panelEdgeTop),
        panelEdgeBottom = a(t.panelEdgeBottom),
        sheen = a(t.sheen),
        surface = a(t.surface),
        surfaceRaised = a(t.surfaceRaised),
        glassTint = a(t.glassTint),
        glassTintSolid = a(t.glassTintSolid),
        glassEdgeLight = a(t.glassEdgeLight),
        glassEdgeDark = a(t.glassEdgeDark),
        shadow = a(t.shadow),
        fill = a(t.fill),
        fillStrong = a(t.fillStrong),
        hairline = a(t.hairline),
        text = a(t.text),
        textSecondary = a(t.textSecondary),
        textTertiary = a(t.textTertiary),
        textDisabled = a(t.textDisabled),
        accent = a(t.accent),
        onAccent = a(t.onAccent),
        accentSoft = a(t.accentSoft),
        accentGlow = a(t.accentGlow),
        success = a(t.success),
        warning = a(t.warning),
        critical = a(t.critical),
        info = a(t.info),
        scrim = a(t.scrim),
    )
}

private fun materialScheme(c: AetherColors) = if (c.isDark) {
    darkColorScheme(
        primary = c.accent,
        onPrimary = c.onAccent,
        primaryContainer = c.accentSoft.compositeOver(c.surface),
        onPrimaryContainer = c.text,
        secondary = c.textSecondary,
        onSecondary = c.surface,
        secondaryContainer = c.fillStrong.compositeOver(c.surface),
        onSecondaryContainer = c.text,
        tertiary = c.info,
        onTertiary = c.surface,
        background = c.background,
        onBackground = c.text,
        surface = c.surface,
        onSurface = c.text,
        surfaceVariant = c.fill.compositeOver(c.surface),
        onSurfaceVariant = c.textSecondary,
        surfaceTint = Color.Transparent,
        inverseSurface = c.text,
        inverseOnSurface = c.surface,
        error = c.critical,
        onError = c.surface,
        outline = c.textTertiary,
        outlineVariant = c.hairline.compositeOver(c.surface),
        scrim = c.scrim,
        surfaceBright = c.surfaceRaised,
        surfaceDim = c.surface,
        surfaceContainer = c.surface,
        surfaceContainerHigh = c.surfaceRaised,
        surfaceContainerHighest = c.surfaceRaised,
        surfaceContainerLow = c.surface,
        surfaceContainerLowest = c.surface,
    )
} else {
    lightColorScheme(
        primary = c.accent,
        onPrimary = c.onAccent,
        primaryContainer = c.accentSoft.compositeOver(c.surface),
        onPrimaryContainer = c.text,
        secondary = c.textSecondary,
        onSecondary = c.surface,
        secondaryContainer = c.fillStrong.compositeOver(c.surface),
        onSecondaryContainer = c.text,
        tertiary = c.info,
        onTertiary = c.surface,
        background = c.background,
        onBackground = c.text,
        surface = c.surface,
        onSurface = c.text,
        surfaceVariant = c.fill.compositeOver(c.surface),
        onSurfaceVariant = c.textSecondary,
        surfaceTint = Color.Transparent,
        inverseSurface = c.text,
        inverseOnSurface = c.surface,
        error = c.critical,
        onError = c.surface,
        outline = c.textTertiary,
        outlineVariant = c.hairline.compositeOver(c.surface),
        scrim = c.scrim,
        surfaceBright = c.surfaceRaised,
        surfaceDim = c.surface,
        surfaceContainer = c.surface,
        surfaceContainerHigh = c.surfaceRaised,
        surfaceContainerHighest = c.surfaceRaised,
        surfaceContainerLow = c.surface,
        surfaceContainerLowest = c.surface,
    )
}

private val materialTypography: Typography = DefaultTypography.let { t ->
    Typography(
        displayLarge = t.numberHero,
        headlineLarge = t.largeTitle,
        headlineMedium = t.title,
        headlineSmall = t.title2,
        titleLarge = t.title2,
        titleMedium = t.headline,
        titleSmall = t.subhead,
        bodyLarge = t.body,
        bodyMedium = t.callout,
        bodySmall = t.footnote,
        labelLarge = t.subhead,
        labelMedium = t.caption,
        labelSmall = t.micro,
    )
}

/**
 * „Animationen entfernen“ (Bedienungshilfen) bzw. Animationsmaßstab 0 in den Entwickleroptionen. Wird beobachtet:
 * Ändert man die Einstellung bei laufender App, folgt die Oberfläche sofort. (Bewährt aus DriveGlass.)
 */
@Composable
private fun rememberSystemReducedMotion(): Boolean {
    val resolver: ContentResolver = LocalContext.current.contentResolver
    fun read(): Boolean = try {
        Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    } catch (e: SecurityException) {
        false
    }
    var reduced by remember(resolver) { mutableStateOf(read()) }
    DisposableEffect(resolver) {
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                reduced = read()
            }
        }
        resolver.registerContentObserver(Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE), false, observer)
        onDispose { resolver.unregisterContentObserver(observer) }
    }
    return reduced
}

/** Kurzzugriff: `Aether.colors`, `Aether.type`, `Aether.effects`, `Aether.motion`. */
object Aether {
    val colors: AetherColors
        @Composable @ReadOnlyComposable get() = LocalAetherColors.current

    val type: AetherTypography
        @Composable @ReadOnlyComposable get() = LocalAetherTypography.current

    val effects: EffectConfig
        @Composable @ReadOnlyComposable get() = LocalEffects.current

    val motion: MotionScheme
        @Composable @ReadOnlyComposable get() = LocalMotion.current
}
