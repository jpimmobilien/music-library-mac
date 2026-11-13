package de.privateapp.aether.design

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

/*
 * Typografie: Inter (SIL OFL 1.1) für die Oberfläche, Inter Display für Titel und große Zahlen. Alle
 * Zahlenstile nutzen gleich breite Ziffern („tnum“), damit sich ändernde Werte nicht springen.
 * Lizenz: Einstellungen › Lizenzen (assets/licenses/OFL-Inter.txt).
 *
 * Hierarchie: Titel groß und ruhig, Werte leicht, Einheiten klein, Beschriftungen mittelstark,
 * Erklärungen normal. Alle Größen in sp – sie folgen der Schriftgröße des Systems.
 */

val Inter = FontFamily(
    Font(R.font.inter_regular, FontWeight.Normal),
    Font(R.font.inter_medium, FontWeight.Medium),
    Font(R.font.inter_semibold, FontWeight.SemiBold),
    Font(R.font.inter_bold, FontWeight.Bold),
)

/** Optische Größe „Display“ für Titel und große Zahlen. */
val InterDisplay = FontFamily(
    Font(R.font.inter_display_light, FontWeight.Light),
    Font(R.font.inter_display_semibold, FontWeight.SemiBold),
)

private const val TABULAR = "tnum"

@Immutable
data class AetherTypography(
    /** Bildschirmtitel. */
    val largeTitle: TextStyle,
    /** Titel großer Karten. */
    val title: TextStyle,
    /** Kartenüberschriften. */
    val title2: TextStyle,
    val headline: TextStyle,
    val body: TextStyle,
    val bodyStrong: TextStyle,
    val callout: TextStyle,
    val subhead: TextStyle,
    val footnote: TextStyle,
    val caption: TextStyle,
    /** Reiterbeschriftungen und kleinste Hinweise. */
    val micro: TextStyle,
    /** Kleine Oberzeile in gesperrter Schrift (z. B. Markenzeile, Kategorie). */
    val eyebrow: TextStyle,
    val numberHero: TextStyle,
    val numberLarge: TextStyle,
    val numberMedium: TextStyle,
    val numberSmall: TextStyle,
)

val DefaultTypography = AetherTypography(
    largeTitle = TextStyle(fontFamily = InterDisplay, fontWeight = FontWeight.SemiBold, fontSize = 32.sp, lineHeight = 38.sp, letterSpacing = (-0.02).em),
    title = TextStyle(fontFamily = InterDisplay, fontWeight = FontWeight.SemiBold, fontSize = 24.sp, lineHeight = 30.sp, letterSpacing = (-0.015).em),
    title2 = TextStyle(fontFamily = InterDisplay, fontWeight = FontWeight.SemiBold, fontSize = 19.sp, lineHeight = 24.sp, letterSpacing = (-0.01).em),
    headline = TextStyle(fontFamily = Inter, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, lineHeight = 22.sp, letterSpacing = (-0.005).em),
    body = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Normal, fontSize = 15.sp, lineHeight = 22.sp),
    bodyStrong = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Medium, fontSize = 15.sp, lineHeight = 22.sp),
    callout = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Normal, fontSize = 14.sp, lineHeight = 20.sp),
    subhead = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Medium, fontSize = 13.sp, lineHeight = 18.sp),
    footnote = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Normal, fontSize = 13.sp, lineHeight = 18.sp),
    caption = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Medium, fontSize = 12.sp, lineHeight = 16.sp),
    micro = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Medium, fontSize = 11.sp, lineHeight = 13.sp, letterSpacing = 0.005.em),
    eyebrow = TextStyle(fontFamily = Inter, fontWeight = FontWeight.SemiBold, fontSize = 12.sp, lineHeight = 16.sp, letterSpacing = 0.12.em),
    numberHero = TextStyle(fontFamily = InterDisplay, fontWeight = FontWeight.Light, fontSize = 52.sp, lineHeight = 56.sp, letterSpacing = (-0.03).em, fontFeatureSettings = TABULAR),
    numberLarge = TextStyle(fontFamily = InterDisplay, fontWeight = FontWeight.Light, fontSize = 38.sp, lineHeight = 42.sp, letterSpacing = (-0.025).em, fontFeatureSettings = TABULAR),
    numberMedium = TextStyle(fontFamily = InterDisplay, fontWeight = FontWeight.SemiBold, fontSize = 24.sp, lineHeight = 28.sp, letterSpacing = (-0.015).em, fontFeatureSettings = TABULAR),
    numberSmall = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Medium, fontSize = 15.sp, lineHeight = 20.sp, fontFeatureSettings = TABULAR),
)

val LocalAetherTypography = staticCompositionLocalOf { DefaultTypography }
