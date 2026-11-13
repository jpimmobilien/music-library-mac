package de.privateapp.aether.design

import de.privateapp.aether.model.appearance.AccentChoice
import de.privateapp.aether.model.appearance.ThemeStyle

/*
 * Farbwerte aller Themes als reine Zahlen (0xAARRGGBB) – ohne Compose, damit die Kontrastprüfung
 * (ContrastTest) auf der JVM läuft. Die Oberfläche liest diese Werte ausschließlich über AetherColors.
 *
 * Grundsatz „Licht und Luft“: Die Flächen selbst sind fast farblos; Farbe trägt Bedeutung. Der Akzent
 * erscheint dort, wo man tippen kann oder etwas ausgewählt ist, und färbt die Atmosphäre ganz leicht.
 * Grün, Bernstein und Rot sind ausschließlich echten Zuständen vorbehalten – und erscheinen nie allein,
 * sondern immer mit Symbol und Text.
 *
 * Alle Paare Text/Fläche erfüllen WCAG AA (≥ 4,5 : 1), auch auf durchscheinenden Flächen über dem
 * hellsten bzw. dunkelsten Punkt der Atmosphäre und auf schwebendem Glas über rein weißem bzw. rein
 * schwarzem Inhalt (z. B. Bildvorschauen). Nachweis: src/test/…/ContrastTest.kt.
 */

/** Grundpalette eines Themes. */
data class BaseSpec(
    val isDark: Boolean,
    /** Glasmaterial erlaubt (Minimal Hell zeichnet deckende Flächen ohne Licht und Unschärfe). */
    val glass: Boolean,
    val backgroundTop: Long,
    val background: Long,
    val backgroundBottom: Long,
    /** Atmosphäre: Deckkraft des Akzentfelds sowie zwei feste Felder (Farbe mit eingerechneter Deckkraft). Höchstwerte (Immersiv). */
    val atmosphereAccentAlpha: Float,
    val atmosphereCool: Long,
    val atmosphereWarm: Long,
    /** Inhaltsflächen (Glas ohne Echtzeit-Unschärfe), Verlauf oben → unten. */
    val panelTop: Long,
    val panelBottom: Long,
    val panelEdgeTop: Long,
    val panelEdgeBottom: Long,
    val sheen: Long,
    /** Deckende Flächen: Menüs, Dialoge, Blätter. */
    val surface: Long,
    val surfaceRaised: Long,
    /** Schwebendes Glas über weichgezeichnetem Inhalt bzw. ohne Unschärfe. */
    val glassTint: Long,
    val glassTintSolid: Long,
    val glassEdgeLight: Long,
    val glassEdgeDark: Long,
    val shadow: Long,
    /** Mulden, Spuren von Diagrammen, gedrückte Zustände. */
    val fill: Long,
    val fillStrong: Long,
    val hairline: Long,
    val text: Long,
    val textSecondary: Long,
    val textTertiary: Long,
    val textDisabled: Long,
    val onAccent: Long,
    val success: Long,
    val warning: Long,
    val critical: Long,
    val info: Long,
    val scrim: Long,
)

/** Akzentfarbe je Helligkeit. */
data class AccentSpec(val onLight: Long, val onDark: Long) {
    fun forDark(isDark: Boolean): Long = if (isDark) onDark else onLight
}

object PaletteSpec {

    /** Liquid Glass Hell – „Morgenluft“: kühles Perlgrau, weißes Glas, weiche Schatten. */
    val GlassLight = BaseSpec(
        isDark = false,
        glass = true,
        backgroundTop = 0xFFF4F7FB,
        background = 0xFFEDF1F6,
        backgroundBottom = 0xFFE5EAF1,
        atmosphereAccentAlpha = 0.10f,
        atmosphereCool = 0x8CCFE4FB,
        atmosphereWarm = 0x80FCE3D2,
        panelTop = 0xC7FFFFFF,
        panelBottom = 0x9EFFFFFF,
        panelEdgeTop = 0xF2FFFFFF,
        panelEdgeBottom = 0x140F1A2A,
        sheen = 0x8CFFFFFF,
        surface = 0xFFFBFCFD,
        surfaceRaised = 0xFFFFFFFF,
        glassTint = 0xCCF7F9FC,
        glassTintSolid = 0xF0F7F9FC,
        glassEdgeLight = 0xF2FFFFFF,
        glassEdgeDark = 0x1A0F1A2A,
        shadow = 0x2E1B2A40,
        fill = 0x120F1A2A,
        fillStrong = 0x1F0F1A2A,
        hairline = 0x170F1A2A,
        text = 0xFF0E141C,
        textSecondary = 0xFF454F5C,
        textTertiary = 0xFF535D6A,
        textDisabled = 0xFF9AA2AD,
        onAccent = 0xFFFFFFFF,
        success = 0xFF0F6A39,
        warning = 0xFF8A4E00,
        critical = 0xFFAD2822,
        info = 0xFF245885,
        scrim = 0x660E141C,
    )

    /** Liquid Glass Dunkel – „Nachthimmel“: tiefes Blaugraphit, leuchtende Glaskanten. */
    val GlassDark = BaseSpec(
        isDark = true,
        glass = true,
        backgroundTop = 0xFF0F141C,
        background = 0xFF0A0E14,
        backgroundBottom = 0xFF06080C,
        atmosphereAccentAlpha = 0.10f,
        atmosphereCool = 0x661E3A5C,
        atmosphereWarm = 0x2E4A3420,
        panelTop = 0x13FFFFFF,
        panelBottom = 0x0AFFFFFF,
        panelEdgeTop = 0x33FFFFFF,
        panelEdgeBottom = 0x0AFFFFFF,
        sheen = 0x12FFFFFF,
        surface = 0xFF151A22,
        surfaceRaised = 0xFF1C222B,
        glassTint = 0xD1161C25,
        glassTintSolid = 0xF2161C25,
        glassEdgeLight = 0x3DFFFFFF,
        glassEdgeDark = 0x0DFFFFFF,
        shadow = 0x8C000000,
        fill = 0x14FFFFFF,
        fillStrong = 0x24FFFFFF,
        hairline = 0x14FFFFFF,
        text = 0xFFF2F4F7,
        textSecondary = 0xFFAEB6C1,
        textTertiary = 0xFFA0A9B5,
        textDisabled = 0xFF5D6570,
        onAccent = 0xFF08111C,
        success = 0xFF5DD394,
        warning = 0xFFF2B44C,
        critical = 0xFFFF7B70,
        info = 0xFF93C6EA,
        scrim = 0x99000000,
    )

    /** Minimal Hell – deckende, ruhige Flächen mit feinen Linien, ohne Glas und Atmosphäre. */
    val MinimalLight = BaseSpec(
        isDark = false,
        glass = false,
        backgroundTop = 0xFFF5F6F8,
        background = 0xFFF5F6F8,
        backgroundBottom = 0xFFF5F6F8,
        atmosphereAccentAlpha = 0f,
        atmosphereCool = 0x00000000,
        atmosphereWarm = 0x00000000,
        panelTop = 0xFFFFFFFF,
        panelBottom = 0xFFFFFFFF,
        panelEdgeTop = 0x1A0F1A2A,
        panelEdgeBottom = 0x1A0F1A2A,
        sheen = 0x00FFFFFF,
        surface = 0xFFFFFFFF,
        surfaceRaised = 0xFFFFFFFF,
        glassTint = 0xF5FFFFFF,
        glassTintSolid = 0xFAFFFFFF,
        glassEdgeLight = 0x1A0F1A2A,
        glassEdgeDark = 0x1A0F1A2A,
        shadow = 0x1F1B2A40,
        fill = 0x0F0F1A2A,
        fillStrong = 0x1A0F1A2A,
        hairline = 0x170F1A2A,
        text = 0xFF0E141C,
        textSecondary = 0xFF47505C,
        textTertiary = 0xFF58616D,
        textDisabled = 0xFF9AA2AD,
        onAccent = 0xFFFFFFFF,
        success = 0xFF0F6A39,
        warning = 0xFF8A4E00,
        critical = 0xFFAD2822,
        info = 0xFF245885,
        scrim = 0x660E141C,
    )

    /** Deep Dark – echtes Schwarz (OLED), sehr zurückhaltendes Glas, keine Atmosphäre. */
    val DeepDark = BaseSpec(
        isDark = true,
        glass = true,
        backgroundTop = 0xFF000000,
        background = 0xFF000000,
        backgroundBottom = 0xFF000000,
        atmosphereAccentAlpha = 0f,
        atmosphereCool = 0x00000000,
        atmosphereWarm = 0x00000000,
        panelTop = 0x0FFFFFFF,
        panelBottom = 0x0BFFFFFF,
        panelEdgeTop = 0x1FFFFFFF,
        panelEdgeBottom = 0x08FFFFFF,
        sheen = 0x08FFFFFF,
        surface = 0xFF101113,
        surfaceRaised = 0xFF17181B,
        glassTint = 0xD60C0D0F,
        glassTintSolid = 0xF50C0D0F,
        glassEdgeLight = 0x29FFFFFF,
        glassEdgeDark = 0x0AFFFFFF,
        shadow = 0x00000000,
        fill = 0x14FFFFFF,
        fillStrong = 0x24FFFFFF,
        hairline = 0x14FFFFFF,
        text = 0xFFF5F5F7,
        textSecondary = 0xFFA3A6AD,
        textTertiary = 0xFF8E9199,
        textDisabled = 0xFF55585E,
        onAccent = 0xFF08111C,
        success = 0xFF5DD394,
        warning = 0xFFF2B44C,
        critical = 0xFFFF7B70,
        info = 0xFF93C6EA,
        scrim = 0xB3000000,
    )

    /** Feste Akzentfarben (hell / dunkel). Systemfarbe: siehe Theme.kt (wird zur Laufzeit geprüft). */
    val accents: Map<AccentChoice, AccentSpec> = mapOf(
        AccentChoice.OCEAN to AccentSpec(0xFF1B58B3, 0xFF8DB9FF),
        AccentChoice.ARCTIC to AccentSpec(0xFF006680, 0xFF6DD3EA),
        AccentChoice.VIOLET to AccentSpec(0xFF5F41C2, 0xFFBBA6FF),
        AccentChoice.EMERALD to AccentSpec(0xFF156E45, 0xFF6CD6A1),
        AccentChoice.AMBER to AccentSpec(0xFF8A5000, 0xFFF3B556),
        AccentChoice.ROSE to AccentSpec(0xFFA82B58, 0xFFFF92B6),
        AccentChoice.GRAPHITE to AccentSpec(0xFF38424E, 0xFFC8D0DA),
    )

    /** Ersatz, falls die Systemfarbe nicht genug Kontrast bietet. */
    val fallbackAccent: AccentSpec get() = accents.getValue(AccentChoice.OCEAN)

    fun base(theme: ThemeStyle, systemDark: Boolean): BaseSpec = when (theme) {
        ThemeStyle.ADAPTIVE -> if (systemDark) GlassDark else GlassLight
        ThemeStyle.GLASS_LIGHT -> GlassLight
        ThemeStyle.GLASS_DARK -> GlassDark
        ThemeStyle.MINIMAL_LIGHT -> MinimalLight
        ThemeStyle.DEEP_DARK -> DeepDark
    }

    val allBases: List<Pair<String, BaseSpec>> = listOf(
        "Liquid Glass Hell" to GlassLight,
        "Liquid Glass Dunkel" to GlassDark,
        "Minimal Hell" to MinimalLight,
        "Deep Dark" to DeepDark,
    )
}

/** Farbrechnung nach WCAG 2.x – auch zur Laufzeit genutzt (Prüfung der Systemfarbe). */
object ColorMath {
    fun alpha(c: Long): Float = ((c ushr 24) and 0xFF).toFloat() / 255f

    private fun channel(c: Long, shift: Int): Int = ((c ushr shift) and 0xFF).toInt()

    /** [fg] mit eigener Deckkraft über deckendem [bg] (Ergebnis deckend). */
    fun over(fg: Long, bg: Long): Long {
        val a = alpha(fg)
        fun mix(shift: Int): Long = Math.round(channel(fg, shift) * a + channel(bg, shift) * (1f - a)).toLong().coerceIn(0, 255)
        return (0xFFL shl 24) or (mix(16) shl 16) or (mix(8) shl 8) or mix(0)
    }

    /** Farbe [rgb] mit neuer Deckkraft [a]. */
    fun withAlpha(rgb: Long, a: Float): Long =
        ((Math.round(a.coerceIn(0f, 1f) * 255f).toLong() and 0xFF) shl 24) or (rgb and 0xFFFFFFL)

    fun luminance(c: Long): Double {
        fun lin(v: Int): Double {
            val s = v / 255.0
            return if (s <= 0.04045) s / 12.92 else Math.pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(channel(c, 16)) + 0.7152 * lin(channel(c, 8)) + 0.0722 * lin(channel(c, 0))
    }

    /** Kontrastverhältnis zweier deckender Farben (1 … 21). */
    fun contrast(a: Long, b: Long): Double {
        val la = luminance(a)
        val lb = luminance(b)
        return (maxOf(la, lb) + 0.05) / (minOf(la, lb) + 0.05)
    }

    /**
     * Alle Untergründe, auf denen Text eines Themes stehen kann: Hintergrund (oben, Mitte, unten), dieselben mit
     * den Atmosphärefeldern in voller Stärke, Inhaltsflächen darüber, deckende Flächen und Glas ohne Unschärfe.
     */
    fun textGrounds(base: BaseSpec, accent: Long): List<Long> {
        val bgs = mutableListOf(base.backgroundTop, base.background, base.backgroundBottom)
        val fields = listOf(withAlpha(accent, base.atmosphereAccentAlpha), base.atmosphereCool, base.atmosphereWarm)
        for (f in fields) for (b in listOf(base.backgroundTop, base.background, base.backgroundBottom)) bgs += over(f, b)
        val panels = bgs.flatMap { listOf(over(base.panelTop, it), over(base.panelBottom, it)) }
        val solid = bgs.map { over(base.glassTintSolid, it) }
        return bgs + panels + solid + listOf(base.surface, base.surfaceRaised)
    }

    /** Schwebendes Glas mit Unschärfe über dem ungünstigsten Inhalt: rein schwarz bzw. rein weiß. */
    fun floatingGlassWorstCase(base: BaseSpec): List<Long> =
        listOf(over(base.glassTint, 0xFF000000), over(base.glassTint, 0xFFFFFFFF))

    /** Mischung zweier deckender Farben im sRGB-Raum (t = 0 → [a], t = 1 → [b]). */
    fun mix(a: Long, b: Long, t: Float): Long {
        val f = t.coerceIn(0f, 1f)
        fun ch(shift: Int): Long = Math.round(channel(a, shift) * (1f - f) + channel(b, shift) * f).toLong().coerceIn(0, 255)
        return (0xFFL shl 24) or (ch(16) shl 16) or (ch(8) shl 8) or ch(0)
    }

    /**
     * Zweite Farbe für Verläufe in Diagrammen: im Dunkeln heller, im Hellen nur wenig heller – damit der Bogen
     * an jeder Stelle mindestens 3 : 1 gegen seine Spur behält (geprüft in ContrastTest).
     */
    fun glow(accent: Long, isDark: Boolean): Long = mix(accent, 0xFFFFFFFF, if (isDark) 0.28f else 0.08f)

    /** Kleinster Kontrast von [fg] gegenüber allen [grounds]. */
    fun minContrast(fg: Long, grounds: List<Long>): Double = grounds.minOf { contrast(fg, it) }
}
