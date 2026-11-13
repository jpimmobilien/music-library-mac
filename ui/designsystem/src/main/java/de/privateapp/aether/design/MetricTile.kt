package de.privateapp.aether.design

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

/**
 * Kompakte Kachel für einen Live-Wert: Symbol und Bezeichnung oben, darunter der Wert groß mit kleiner Einheit,
 * optional eine Zeile zur Herkunft. [muted] = kein Wert vorhanden – dann steht der Grund in ruhiger Schrift da,
 * nie eine erfundene Zahl. TalkBack liest die Kachel als Einheit.
 */
@Composable
fun MetricTile(
    icon: ImageVector,
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    unit: String? = null,
    caption: String? = null,
    muted: Boolean = false,
    tone: Tone = Tone.ACCENT,
) {
    val colors = Aether.colors
    val type = Aether.type
    Panel(modifier.semantics(mergeDescendants = true) {}, contentPadding = PaddingValues(Spacing.l)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, contentDescription = null, tint = if (tone == Tone.ACCENT) colors.accent else colors.tone(tone), modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(Spacing.s))
            Text(label, color = colors.textSecondary, style = type.caption, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Spacer(Modifier.height(Spacing.s))
        if (muted) {
            Text(value, color = colors.textTertiary, style = type.callout)
        } else {
            Row(verticalAlignment = Alignment.Bottom) {
                Text(value, color = colors.text, style = type.numberMedium, maxLines = 1)
                if (unit != null) {
                    Spacer(Modifier.width(3.dp))
                    Text(unit, color = colors.textSecondary, style = type.subhead, modifier = Modifier.padding(bottom = 3.dp), maxLines = 1)
                }
            }
        }
        if (caption != null) {
            Spacer(Modifier.height(Spacing.xxs))
            Text(caption, color = colors.textTertiary, style = type.footnote, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

/**
 * Sehr große Hauptzahl (z. B. Geschwindigkeit) mit Einheit. Die Ziffern sind gleich breit und schrumpfen bei großer
 * Systemschrift oder langen Werten stufenweise, statt umzubrechen oder abgeschnitten zu werden.
 */
@Composable
fun HeroValue(value: String, unit: String, modifier: Modifier = Modifier, valueColor: Color = Color.Unspecified, spokenValue: String = "$value $unit") {
    val colors = Aether.colors
    val type = Aether.type
    Row(modifier.clearAndSetSemantics { contentDescription = spokenValue }, verticalAlignment = Alignment.Bottom) {
        Text(
            value,
            color = if (valueColor != Color.Unspecified) valueColor else colors.text,
            style = type.numberHero.copy(lineHeight = 1.em),
            maxLines = 1,
            softWrap = false,
            autoSize = TextAutoSize.StepBased(minFontSize = 40.sp, maxFontSize = 104.sp, stepSize = 4.sp),
            modifier = Modifier.weight(1f, fill = false),
        )
        Spacer(Modifier.width(Spacing.s))
        Text(unit, color = colors.textSecondary, style = type.title2, modifier = Modifier.padding(bottom = 14.dp), maxLines = 1)
    }
}
