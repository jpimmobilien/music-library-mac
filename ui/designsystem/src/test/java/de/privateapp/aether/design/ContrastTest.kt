package de.privateapp.aether.design

import de.privateapp.aether.model.appearance.AccentChoice
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Kritische Regel des Auftrags: Kein Text darf in einem Theme unlesbar werden. Geprüft wird jede Kombination
 * aus Theme und Akzentfarbe gegen alle Untergründe, auf denen Text stehen kann (ColorMath.textGrounds).
 */
class ContrastTest {

    private val fixedAccents = AccentChoice.entries.filter { it != AccentChoice.SYSTEM }

    private fun failures(): List<String> {
        val out = mutableListOf<String>()
        for ((name, base) in PaletteSpec.allBases) {
            for (choice in fixedAccents) {
                val accent = PaletteSpec.accents.getValue(choice).forDark(base.isDark)
                val grounds = ColorMath.textGrounds(base, accent)
                val roles = mapOf(
                    "Text" to base.text,
                    "Sekundärtext" to base.textSecondary,
                    "Tertiärtext" to base.textTertiary,
                    "Akzenttext" to accent,
                    "Erfolg" to base.success,
                    "Warnung" to base.warning,
                    "Kritisch" to base.critical,
                    "Hinweis" to base.info,
                )
                for ((role, color) in roles) {
                    val c = ColorMath.minContrast(color, grounds)
                    if (c < 4.5) out += "$name/$choice: $role nur ${"%.2f".format(c)} : 1"
                }
                // Text auf schwebendem Glas über rein schwarzem bzw. rein weißem Inhalt (Reiterleiste über Bildern)
                val worst = ColorMath.floatingGlassWorstCase(base)
                for ((role, color) in mapOf("Text auf Glas" to base.text, "Sekundärtext auf Glas" to base.textSecondary)) {
                    val c = ColorMath.minContrast(color, worst)
                    if (c < 4.5) out += "$name/$choice: $role nur ${"%.2f".format(c)} : 1"
                }
                // Schrift auf Akzentflächen (Hauptschaltfläche)
                val onAccent = ColorMath.contrast(base.onAccent, accent)
                if (onAccent < 4.5) out += "$name/$choice: Schrift auf Akzent nur ${"%.2f".format(onAccent)} : 1"
                // Grafische Elemente (Diagrammbogen gegen seine Spur) mindestens 3 : 1 (WCAG 1.4.11)
                val tracks = grounds.map { ColorMath.over(base.fill, it) }
                val arc = minOf(ColorMath.minContrast(accent, tracks), ColorMath.minContrast(ColorMath.glow(accent, base.isDark), tracks))
                if (arc < 3.0) out += "$name/$choice: Diagrammbogen nur ${"%.2f".format(arc)} : 1"
            }
        }
        return out
    }

    @Test
    fun everyTextRoleIsReadableInEveryThemeAndAccent() {
        val f = failures()
        assertTrue("Zu geringer Kontrast:\n" + f.joinToString("\n"), f.isEmpty())
    }

    /**
     * Flächen der Dateiverwaltung (Phase 3), so wie sie verwendet werden:
     *  - Gefüllte Flächen (Kategorien, Suchfeld, ausgewählte Zeilen) über jedem Untergrund: Text und Sekundärtext
     *    (Tertiärtext wird dort bewusst nicht verwendet – auf der Auswahl wechselt er zu Sekundärtext).
     *  - Aktionsgruppen auf Blättern und Dialogen (Füllung über der angehobenen Fläche): alle Rollen inklusive
     *    Akzent (Symbole) und Kritisch (Löschen, zerstörerische Bestätigung).
     */
    @Test
    fun textStaysReadableOnFilledControlsSheetsAndSelections() {
        val out = mutableListOf<String>()
        for ((name, base) in PaletteSpec.allBases) {
            for (choice in fixedAccents) {
                val accent = PaletteSpec.accents.getValue(choice).forDark(base.isDark)
                val filled = ColorMath.textGrounds(base, accent).map { ColorMath.over(base.fill, it) }
                for ((role, color) in mapOf("Text" to base.text, "Sekundärtext" to base.textSecondary)) {
                    val c = ColorMath.minContrast(color, filled)
                    if (c < 4.5) out += "$name/$choice: $role auf Füllung nur ${"%.2f".format(c)} : 1"
                }
                val sheetGroup = listOf(ColorMath.over(base.fill, base.surfaceRaised), base.surfaceRaised)
                val sheetRoles = mapOf(
                    "Text" to base.text,
                    "Sekundärtext" to base.textSecondary,
                    "Tertiärtext" to base.textTertiary,
                    "Akzent" to accent,
                    "Kritisch" to base.critical,
                )
                for ((role, color) in sheetRoles) {
                    val c = ColorMath.minContrast(color, sheetGroup)
                    if (c < 4.5) out += "$name/$choice: $role auf Blatt nur ${"%.2f".format(c)} : 1"
                }
            }
        }
        assertTrue("Zu geringer Kontrast:\n" + out.joinToString("\n"), out.isEmpty())
    }

    @Test
    fun allFixedAccentsAreDefined() {
        for (choice in fixedAccents) assertTrue(choice.name, PaletteSpec.accents.containsKey(choice))
    }

    @Test
    fun contrastMathMatchesKnownValues() {
        // Schwarz auf Weiß = 21 : 1, gleiche Farbe = 1 : 1
        assertTrue(kotlin.math.abs(ColorMath.contrast(0xFF000000, 0xFFFFFFFF) - 21.0) < 0.01)
        assertTrue(kotlin.math.abs(ColorMath.contrast(0xFF777777, 0xFF777777) - 1.0) < 0.0001)
        // #767676 auf Weiß ist der bekannte Grenzfall 4,54 : 1
        assertTrue(kotlin.math.abs(ColorMath.contrast(0xFF767676, 0xFFFFFFFF) - 4.54) < 0.01)
        // 50 % Schwarz über Weiß = #808080
        assertTrue(ColorMath.over(0x80000000, 0xFFFFFFFF) == 0xFF7F7F7FL || ColorMath.over(0x80000000, 0xFFFFFFFF) == 0xFF808080L)
    }

    @Test
    fun minimalLightHasNoGlassAndNoAtmosphere() {
        val m = PaletteSpec.MinimalLight
        assertTrue(!m.glass)
        assertTrue(m.atmosphereAccentAlpha == 0f && ColorMath.alpha(m.atmosphereCool) == 0f && ColorMath.alpha(m.atmosphereWarm) == 0f)
    }

    @Test
    fun deepDarkIsTrueBlack() {
        val d = PaletteSpec.DeepDark
        assertTrue(d.background == 0xFF000000L && d.backgroundTop == 0xFF000000L && d.backgroundBottom == 0xFF000000L)
    }
}
