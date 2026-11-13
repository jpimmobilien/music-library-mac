package de.privateapp.aether.design

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Eintrag einer [GlassToolbar]. */
@Immutable
data class ToolbarAction(
    val label: String,
    val icon: ImageVector,
    val enabled: Boolean = true,
    val destructive: Boolean = false,
    val onClick: () -> Unit,
)

/**
 * Schwebende Werkzeugleiste mit Symbol und Beschriftung (z. B. Teilen, Kopieren, Verschieben, Löschen bei einer
 * Auswahl). Sitzt an der Stelle der Reiterleiste und hat deren Höhe, damit nichts springt.
 */
@Composable
fun GlassToolbar(actions: List<ToolbarAction>, modifier: Modifier = Modifier, backdrop: Backdrop? = null) {
    GlassSurface(modifier.fillMaxWidth().height(TabBarHeight), backdrop = backdrop) {
        Row(
            Modifier.fillMaxWidth().fillMaxHeight().padding(horizontal = Spacing.xs),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            actions.forEach { ToolbarButton(it, Modifier.weight(1f)) }
        }
    }
}

@Composable
private fun ToolbarButton(action: ToolbarAction, modifier: Modifier) {
    val colors = Aether.colors
    val tint = when {
        !action.enabled -> colors.textDisabled
        action.destructive -> colors.critical
        else -> colors.text
    }
    Column(
        modifier
            .fillMaxHeight()
            .padding(vertical = Spacing.xs)
            .clip(RoundedCornerShape(Radii.control))
            .clickable(enabled = action.enabled, role = Role.Button, onClick = action.onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(action.icon, contentDescription = null, tint = tint, modifier = Modifier.size(22.dp))
        Spacer(Modifier.height(2.dp))
        Text(action.label, color = tint, style = Aether.type.micro, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/**
 * Auswahlmarke einer Datei: leerer Kreis bzw. gefüllter Kreis mit Haken. Form und Haken tragen die Bedeutung –
 * nicht nur die Farbe.
 */
@Composable
fun SelectionMark(selected: Boolean, modifier: Modifier = Modifier, size: Dp = 24.dp) {
    val colors = Aether.colors
    val base = modifier.size(size).clip(CircleShape)
    if (selected) {
        Box(base.background(colors.accent), contentAlignment = Alignment.Center) {
            Icon(AetherIcons.Check, contentDescription = null, tint = colors.onAccent, modifier = Modifier.size(size * 0.62f))
        }
    } else {
        Box(base.background(colors.surfaceRaised.copy(alpha = 0.72f)).border(1.5.dp, colors.textTertiary, CircleShape))
    }
}
