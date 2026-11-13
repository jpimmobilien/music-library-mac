package de.privateapp.aether.design

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.ripple
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/*
 * Schwebende Navigation aus Glas: unten eine Reiterleiste in Pillenform (Telefone), seitlich eine Leiste
 * (Querformat, Tablets, Faltgeräte). Die Auswahl zeigt eine weich gleitende Glaslinse – zusätzlich zur
 * Farbe, damit sie auch ohne Farbwahrnehmung erkennbar ist.
 */

@Immutable
data class NavItem(val label: String, val icon: ImageVector)

/** Höhe der Reiterleiste. */
val TabBarHeight = 64.dp

/** Breite der seitlichen Leiste. */
val RailWidth = 80.dp

/**
 * Reiterleiste. Beschriftungen wachsen mit der Systemschrift nur bis 130 % mit (wie Systemleisten) – größere
 * Schrift würde die Leiste sprengen; TalkBack liest die Beschriftung unabhängig davon vollständig vor.
 */
@Composable
fun GlassTabBar(
    items: List<NavItem>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
    backdrop: Backdrop? = null,
) {
    val colors = Aether.colors
    val motion = Aether.motion
    // Ist kein Reiter gewählt (z. B. Einstellungen neben der Leiste), blendet die Linse an ihrem Platz aus und
    // kehrt von dort zurück – statt vom Rand hereinzugleiten.
    val lastValid = remember { mutableIntStateOf(selectedIndex.coerceAtLeast(0)) }
    SideEffect { if (selectedIndex >= 0) lastValid.intValue = selectedIndex }
    val target = if (selectedIndex >= 0) selectedIndex else lastValid.intValue
    val position by animateFloatAsState(target.toFloat(), motion.gentleSpring(), label = "tabLens")
    val lensAlpha by animateFloatAsState(if (selectedIndex >= 0) 1f else 0f, motion.standard(Motion.QUICK_MS), label = "tabLensAlpha")
    GlassSurface(modifier.height(TabBarHeight), shape = RoundedCornerShape(Radii.bar), backdrop = backdrop) {
        Row(
            Modifier
                .fillMaxSize()
                .drawBehind {
                    if (lensAlpha > 0f && items.isNotEmpty()) {
                        val inset = 6.dp.toPx()
                        val w = size.width / items.size
                        val lensSize = Size(w - inset, size.height - 2 * inset)
                        val topLeft = Offset(position * w + inset / 2f, inset)
                        val r = CornerRadius(lensSize.height / 2f)
                        drawRoundRect(colors.accentSoft, topLeft, lensSize, r, alpha = lensAlpha)
                        drawRoundRect(
                            Brush.verticalGradient(listOf(colors.glassEdgeLight.copy(alpha = colors.glassEdgeLight.alpha * 0.5f), colors.accentSoft.copy(alpha = 0f)), startY = topLeft.y, endY = topLeft.y + lensSize.height),
                            topLeft, lensSize, r,
                            alpha = lensAlpha,
                            style = Stroke(1.dp.toPx()),
                        )
                    }
                }
                .selectableGroup(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            items.forEachIndexed { index, item ->
                NavCell(item, selected = index == selectedIndex, onClick = { onSelect(index) }, modifier = Modifier.weight(1f).fillMaxHeight())
            }
        }
    }
}

/** Seitliche Leiste für breite Fenster. */
@Composable
fun GlassRail(
    items: List<NavItem>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
    backdrop: Backdrop? = null,
) {
    val colors = Aether.colors
    val motion = Aether.motion
    val position by animateFloatAsState(selectedIndex.toFloat(), motion.gentleSpring(), label = "railLens")
    val cell = 68.dp
    GlassSurface(modifier.width(RailWidth), shape = RoundedCornerShape(Radii.bar), backdrop = backdrop) {
        Column(
            Modifier
                .padding(vertical = Spacing.s)
                .drawBehind {
                    if (selectedIndex >= 0) {
                        val inset = 6.dp.toPx()
                        val h = cell.toPx()
                        val lensSize = Size(size.width - 2 * inset, h - inset)
                        val topLeft = Offset(inset, position * h + inset / 2f)
                        drawRoundRect(colors.accentSoft, topLeft, lensSize, CornerRadius(22.dp.toPx()))
                    }
                }
                .selectableGroup(),
        ) {
            items.forEachIndexed { index, item ->
                NavCell(item, selected = index == selectedIndex, onClick = { onSelect(index) }, modifier = Modifier.fillMaxWidth().height(cell))
            }
        }
    }
}

@Composable
private fun NavCell(item: NavItem, selected: Boolean, onClick: () -> Unit, modifier: Modifier) {
    val colors = Aether.colors
    val motion = Aether.motion
    val interaction = remember { MutableInteractionSource() }
    val iconColor by animateColorAsState(if (selected) colors.accent else colors.textSecondary, motion.standard(Motion.QUICK_MS), label = "navIcon")
    val labelColor by animateColorAsState(if (selected) colors.text else colors.textSecondary, motion.standard(Motion.QUICK_MS), label = "navLabel")
    // Beschriftung höchstens bis 130 % der Systemschrift vergrößern
    val fontScale = LocalDensity.current.fontScale
    val labelSize = (11f * minOf(fontScale, 1.3f) / fontScale).sp
    Column(
        modifier
            .clip(RoundedCornerShape(22.dp))
            .selectable(selected = selected, interactionSource = interaction, indication = ripple(bounded = true), role = Role.Tab, onClick = onClick)
            .pressFeedback(interaction),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(item.icon, contentDescription = null, tint = iconColor, modifier = Modifier.size(24.dp))
        Spacer(Modifier.height(3.dp))
        Text(
            item.label,
            color = labelColor,
            style = Aether.type.micro.copy(fontSize = labelSize),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(horizontal = 2.dp),
        )
    }
}

/**
 * Runde Glas-Schaltfläche. [asTab] = gehört zur Navigation (Einstellungen neben der Reiterleiste, TalkBack:
 * „Reiter“, mit Auswahlzustand); sonst eine gewöhnliche Schaltfläche (z. B. Zurück in Unterseiten).
 */
@Composable
fun GlassCircleButton(
    icon: ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    backdrop: Backdrop? = null,
    selected: Boolean = false,
    asTab: Boolean = false,
) {
    val colors = Aether.colors
    val interaction = remember { MutableInteractionSource() }
    GlassSurface(
        modifier
            .size(TabBarHeight)
            .pressFeedback(interaction),
        shape = CircleShape,
        backdrop = backdrop,
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .clip(CircleShape)
                .drawBehind { if (selected) drawCircle(colors.accentSoft, radius = size.minDimension / 2f - 6.dp.toPx()) }
                .then(
                    if (asTab) {
                        Modifier.selectable(selected = selected, interactionSource = interaction, indication = ripple(bounded = true), role = Role.Tab, onClick = onClick)
                    } else {
                        Modifier.clickable(interactionSource = interaction, indication = ripple(bounded = true), role = Role.Button, onClick = onClick)
                    },
                )
                .semantics { this.contentDescription = contentDescription },
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = if (selected) colors.accent else colors.text, modifier = Modifier.size(24.dp))
        }
    }
}
