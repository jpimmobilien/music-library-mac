package de.privateapp.aether.design

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties

/*
 * Blätter (von unten) und Dialoge im Material von ORBIT: deckende, leicht angehobene Fläche mit Lichtkante – über
 * fremdem Inhalt bleibt Text so in jedem Theme lesbar. Farben ausschließlich aus dem Theme.
 */

/**
 * Blatt von unten (wie das Aktionsblatt in iOS): für Aktionen zu einer Datei, Informationen, Auswahl. Wischen nach
 * unten, Tippen daneben und Zurück schließen es.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GlassSheet(
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    skipPartiallyExpanded: Boolean = true,
    /** `false` für Blätter mit eigener scrollbarer Liste (die dann selbst die Höhe bestimmt). */
    scrollable: Boolean = true,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = Aether.colors
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = skipPartiallyExpanded)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        modifier = modifier,
        sheetState = state,
        sheetMaxWidth = 640.dp,
        shape = RoundedCornerShape(topStart = Radii.sheet, topEnd = Radii.sheet),
        containerColor = colors.surfaceRaised,
        contentColor = colors.text,
        tonalElevation = 0.dp,
        scrimColor = colors.scrim,
        dragHandle = {
            Box(
                Modifier
                    .padding(top = Spacing.s, bottom = Spacing.xs)
                    .size(width = 36.dp, height = 5.dp)
                    .clip(RoundedCornerShape(50))
                    .background(colors.fillStrong),
            )
        },
    ) {
        CompositionLocalProvider(LocalContentColor provides colors.text) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .then(if (scrollable) Modifier.verticalScroll(rememberScrollState()) else Modifier)
                    .padding(horizontal = Spacing.page)
                    .padding(bottom = Spacing.xl)
                    .navigationBarsPadding(),
                content = content,
            )
        }
    }
}

/** Kopf eines Blatts: Symbol oder Vorschau links, Titel und Unterzeile. */
@Composable
fun SheetHeader(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    leading: (@Composable () -> Unit)? = null,
) {
    val colors = Aether.colors
    Row(modifier.fillMaxWidth().padding(vertical = Spacing.s), verticalAlignment = Alignment.CenterVertically) {
        if (leading != null) {
            leading()
            Spacer(Modifier.width(Spacing.m))
        }
        Column(Modifier.weight(1f)) {
            Text(
                title,
                color = colors.text,
                style = Aether.type.headline,
                maxLines = 2,
                overflow = TextOverflow.MiddleEllipsis,
                modifier = Modifier.semantics { heading() },
            )
            if (subtitle != null) Text(subtitle, color = colors.textSecondary, style = Aether.type.footnote, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** Gruppe von Aktionen in einem Blatt (abgerundete Fläche mit feinen Trennlinien). */
@Composable
fun ActionGroup(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val colors = Aether.colors
    Column(
        modifier
            .fillMaxWidth()
            .padding(vertical = Spacing.xs)
            .clip(RoundedCornerShape(Radii.control))
            .background(colors.fill),
        content = content,
    )
}

/** Eine Aktion: Symbol, Bezeichnung, optional Zusatz rechts. [destructive] = rot (Löschen). */
@Composable
fun ActionRow(
    title: String,
    icon: ImageVector,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    detail: String? = null,
    destructive: Boolean = false,
    enabled: Boolean = true,
) {
    val colors = Aether.colors
    val tint = when {
        !enabled -> colors.textDisabled
        destructive -> colors.critical
        else -> colors.text
    }
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = MinTouchTarget + 4.dp)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = Spacing.l, vertical = Spacing.s),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = if (destructive || !enabled) tint else colors.accent, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(Spacing.m))
        Text(title, color = tint, style = Aether.type.body, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (detail != null) Text(detail, color = colors.textTertiary, style = Aether.type.footnote)
    }
}

/** Feine Linie zwischen zwei [ActionRow]. */
@Composable
fun ActionDivider() {
    Box(Modifier.fillMaxWidth().padding(start = 50.dp).heightIn(min = 0.5.dp, max = 0.5.dp).background(Aether.colors.hairline))
}

/**
 * Dialog in der Mitte (Bestätigen, Umbenennen, Neuer Ordner). Schaltflächen stehen unten nebeneinander, die
 * bestätigende rechts – wie auf Apple-Geräten; eine zerstörerische Bestätigung ist rot.
 */
@Composable
fun GlassDialog(
    title: String,
    onDismiss: () -> Unit,
    confirmText: String,
    onConfirm: () -> Unit,
    modifier: Modifier = Modifier,
    message: String? = null,
    dismissText: String = "Abbrechen",
    confirmEnabled: Boolean = true,
    destructive: Boolean = false,
    icon: ImageVector? = null,
    content: (@Composable ColumnScope.() -> Unit)? = null,
) {
    val colors = Aether.colors
    val type = Aether.type
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        CompositionLocalProvider(LocalContentColor provides colors.text) {
            Column(
                modifier
                    .padding(Spacing.xxl)
                    .widthIn(max = 420.dp)
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(Radii.card))
                    .background(colors.surfaceRaised)
                    .border(0.8.dp, colors.glassEdgeLight, RoundedCornerShape(Radii.card))
                    .padding(Spacing.xl),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                if (icon != null) {
                    IconBadge(icon, tone = if (destructive) Tone.CRITICAL else Tone.ACCENT, size = 44.dp)
                    Spacer(Modifier.size(Spacing.m))
                }
                Text(title, color = colors.text, style = type.headline, textAlign = TextAlign.Center, modifier = Modifier.semantics { heading() })
                if (message != null) {
                    Spacer(Modifier.size(Spacing.s))
                    Text(message, color = colors.textSecondary, style = type.callout, textAlign = TextAlign.Center)
                }
                if (content != null) {
                    Spacer(Modifier.size(Spacing.l))
                    Column(Modifier.fillMaxWidth(), content = content)
                }
                Spacer(Modifier.size(Spacing.xl))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Spacing.s)) {
                    DialogButton(dismissText, onDismiss, Modifier.weight(1f), prominent = false, destructive = false, enabled = true)
                    DialogButton(confirmText, onConfirm, Modifier.weight(1f), prominent = true, destructive = destructive, enabled = confirmEnabled)
                }
            }
        }
    }
}

@Composable
private fun DialogButton(text: String, onClick: () -> Unit, modifier: Modifier, prominent: Boolean, destructive: Boolean, enabled: Boolean) {
    val colors = Aether.colors
    // Zerstörerische Bestätigung wie bei Apple: rote Schrift auf neutraler Fläche (lesbar in jedem Theme).
    val bg = when {
        !enabled -> colors.fill
        prominent && destructive -> colors.fill
        prominent -> colors.accent
        else -> colors.fill
    }
    val fg = when {
        !enabled -> colors.textDisabled
        prominent && destructive -> colors.critical
        prominent -> colors.onAccent
        else -> colors.text
    }
    Box(
        modifier
            .heightIn(min = MinTouchTarget)
            .clip(RoundedCornerShape(Radii.control))
            .background(bg)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = Spacing.m, vertical = Spacing.m),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, color = fg, style = Aether.type.bodyStrong, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/**
 * Fläche eines Dialogs mit freiem Inhalt. [dismissible] = `false` für Fragen, die beantwortet werden müssen (z. B.
 * Namenskonflikt beim Kopieren): Dann schließen weder Zurück noch Tippen daneben – nichts geschieht versehentlich.
 */
@Composable
fun GlassModal(
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    dismissible: Boolean = true,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = Aether.colors
    Dialog(
        onDismissRequest = { if (dismissible) onDismiss() },
        properties = DialogProperties(usePlatformDefaultWidth = false, dismissOnBackPress = dismissible, dismissOnClickOutside = dismissible),
    ) {
        CompositionLocalProvider(LocalContentColor provides colors.text) {
            Column(
                modifier
                    .padding(Spacing.l)
                    .widthIn(max = 480.dp)
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(Radii.card))
                    .background(colors.surfaceRaised)
                    .border(0.8.dp, colors.glassEdgeLight, RoundedCornerShape(Radii.card))
                    .verticalScroll(rememberScrollState())
                    .padding(Spacing.xl),
                content = content,
            )
        }
    }
}
