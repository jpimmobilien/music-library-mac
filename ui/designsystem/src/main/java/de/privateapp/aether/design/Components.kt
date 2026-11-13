package de.privateapp.aether.design

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.ripple
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.privateapp.aether.model.Reading
import de.privateapp.aether.model.ValueKind

/*
 * Grundbausteine. Jeder Baustein setzt seine Farben selbst aus dem Theme – es gibt keinen Text, der auf eine
 * zufällig geerbte Farbe angewiesen ist.
 */

/** Leichte Verkleinerung beim Drücken (räumliche Rückmeldung). Entfällt bei reduzierter Bewegung. */
@Composable
fun Modifier.pressFeedback(interaction: MutableInteractionSource, enabled: Boolean = true): Modifier {
    val motion = Aether.motion
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (pressed && enabled && !motion.reduced) 0.975f else 1f,
        animationSpec = motion.standard(Motion.PRESS_MS),
        label = "press",
    )
    return this.graphicsLayer {
        scaleX = scale
        scaleY = scale
    }
}

/**
 * Inhaltsfläche aus Glas. Mit [onClick] als Schaltfläche (Rückmeldung durch Welle und leichte Verkleinerung).
 */
@Composable
fun Panel(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    onClickLabel: String? = null,
    contentPadding: PaddingValues = PaddingValues(Spacing.cardPadding),
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = Aether.colors
    val shape = RoundedCornerShape(Radii.card)
    val interaction = remember { MutableInteractionSource() }
    val clickModifier = if (onClick != null) {
        Modifier
            .pressFeedback(interaction)
            .glassPanel(colors)
            .clip(shape)
            .clickable(interactionSource = interaction, indication = ripple(), onClickLabel = onClickLabel, role = Role.Button, onClick = onClick)
    } else {
        Modifier.glassPanel(colors).clip(shape)
    }
    CompositionLocalProvider(LocalContentColor provides colors.text) {
        Column(modifier.fillMaxWidth().then(clickModifier).padding(contentPadding), content = content)
    }
}

/** Großer Bildschirmtitel mit optionaler Oberzeile und Unterzeile. */
@Composable
fun ScreenTitle(title: String, modifier: Modifier = Modifier, eyebrow: String? = null, subtitle: String? = null) {
    val colors = Aether.colors
    val type = Aether.type
    Column(modifier.fillMaxWidth()) {
        if (eyebrow != null) {
            Text(eyebrow.uppercase(), color = colors.accent, style = type.eyebrow)
            Spacer(Modifier.height(Spacing.xs))
        }
        Text(title, color = colors.text, style = type.largeTitle, modifier = Modifier.semantics { heading() })
        if (subtitle != null) {
            Spacer(Modifier.height(Spacing.xs))
            Text(subtitle, color = colors.textSecondary, style = type.callout)
        }
    }
}

/** Abschnittsüberschrift zwischen Karten. */
@Composable
fun SectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        color = Aether.colors.textSecondary,
        style = Aether.type.subhead,
        modifier = modifier
            .padding(start = Spacing.xs, top = Spacing.l, bottom = Spacing.s)
            .semantics { heading() },
    )
}

/** Rundes, zart hinterlegtes Symbol (Kopf von Karten, Zeilen). */
@Composable
fun IconBadge(icon: ImageVector, modifier: Modifier = Modifier, tone: Tone = Tone.ACCENT, size: Dp = 36.dp) {
    val colors = Aether.colors
    Box(
        modifier
            .size(size)
            .clip(CircleShape)
            .background(colors.toneSoft(tone)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = colors.tone(tone), modifier = Modifier.size(size * 0.56f))
    }
}

/** Kopfzeile einer Karte: Symbol, Titel, Unterzeile und optional etwas am rechten Rand. */
@Composable
fun PanelHeader(
    icon: ImageVector,
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    tone: Tone = Tone.ACCENT,
    trailing: (@Composable RowScope.() -> Unit)? = null,
) {
    val colors = Aether.colors
    val type = Aether.type
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        IconBadge(icon, tone = tone)
        Spacer(Modifier.width(Spacing.m))
        Column(Modifier.weight(1f)) {
            Text(title, color = colors.text, style = type.headline, modifier = Modifier.semantics { heading() })
            if (subtitle != null) Text(subtitle, color = colors.textSecondary, style = type.footnote)
        }
        if (trailing != null) {
            Spacer(Modifier.width(Spacing.s))
            trailing()
        }
    }
}

/** Feine Trennlinie. */
@Composable
fun Hairline(modifier: Modifier = Modifier) {
    val c = Aether.colors.hairline
    Box(modifier.fillMaxWidth().height(1.dp).background(c))
}

/**
 * Zeile „Bezeichnung – Wert“. [caption] steht klein unter dem Wert (z. B. Quelle oder Erklärung).
 * Lange Werte brechen um, statt abgeschnitten zu werden. TalkBack liest die Zeile als Einheit.
 */
@Composable
fun InfoRow(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    caption: String? = null,
    valueColor: Color = Color.Unspecified,
    muted: Boolean = false,
) {
    val colors = Aether.colors
    val type = Aether.type
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 40.dp)
            .padding(vertical = Spacing.s)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.Top,
    ) {
        Text(label, color = colors.textSecondary, style = type.callout, modifier = Modifier.weight(0.9f).padding(end = Spacing.m))
        Column(Modifier.weight(1.1f), horizontalAlignment = Alignment.End) {
            Text(
                value,
                color = when {
                    valueColor != Color.Unspecified -> valueColor
                    muted -> colors.textTertiary
                    else -> colors.text
                },
                style = if (muted) type.callout else type.bodyStrong,
                textAlign = TextAlign.End,
            )
            if (caption != null) {
                Text(caption, color = colors.textTertiary, style = type.footnote, textAlign = TextAlign.End)
            }
        }
    }
}

/**
 * Zeile für einen [Reading]: zeigt den Wert – oder ausdrücklich, warum es ihn nicht gibt. Berechnete und
 * geschätzte Werte werden als solche gekennzeichnet.
 */
@Composable
fun <T> ReadingRow(
    label: String,
    reading: Reading<T>,
    modifier: Modifier = Modifier,
    showSource: Boolean = false,
    format: (T) -> String,
) {
    when (reading) {
        is Reading.Value -> {
            val note = buildList {
                if (reading.kind != ValueKind.REPORTED) add(reading.kind.label)
                if (showSource) add(reading.source)
            }.joinToString(" · ").ifEmpty { null }
            InfoRow(label, format(reading.value), modifier, caption = note)
        }
        is Reading.Unavailable -> InfoRow(label, reading.missing.text, modifier, muted = true)
    }
}

/** Kleine Plakette mit Text und optionalem Symbol – nie nur Farbe. */
@Composable
fun StatusBadge(text: String, tone: Tone, modifier: Modifier = Modifier, icon: ImageVector? = null) {
    val colors = Aether.colors
    Row(
        modifier
            .clip(RoundedCornerShape(50))
            .background(colors.toneSoft(tone))
            .padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = colors.tone(tone), modifier = Modifier.size(14.dp))
            Spacer(Modifier.width(5.dp))
        }
        Text(text, color = colors.tone(tone), style = Aether.type.caption, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** Hinweisfläche: Symbol, Titel, Text. Für Erklärungen, Grenzen von Android und Warnungen. */
@Composable
fun Notice(
    title: String,
    message: String,
    modifier: Modifier = Modifier,
    tone: Tone = Tone.INFO,
    icon: ImageVector = if (tone == Tone.WARNING || tone == Tone.CRITICAL) AetherIcons.Warning else AetherIcons.Info,
    /** Optional: Der ganze Hinweis ist eine Schaltfläche (TalkBack liest Titel und Text als eine Schaltfläche). */
    onClick: (() -> Unit)? = null,
    onClickLabel: String? = null,
) {
    val colors = Aether.colors
    val type = Aether.type
    val base = modifier
        .fillMaxWidth()
        .clip(RoundedCornerShape(Radii.control))
        .background(colors.toneSoft(tone))
    val interaction = if (onClick != null) Modifier.clickable(role = Role.Button, onClickLabel = onClickLabel, onClick = onClick) else Modifier.semantics(mergeDescendants = true) {}
    Row(
        base
            .then(interaction)
            .padding(Spacing.m),
    ) {
        Icon(icon, contentDescription = null, tint = colors.tone(tone), modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(Spacing.m))
        Column(Modifier.weight(1f)) {
            Text(title, color = colors.text, style = type.subhead)
            Spacer(Modifier.height(2.dp))
            Text(message, color = colors.textSecondary, style = type.footnote)
        }
    }
}

/** Zeile, die zu einer Unterseite führt. */
@Composable
fun NavRow(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    subtitle: String? = null,
) {
    val colors = Aether.colors
    val type = Aether.type
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = MinTouchTarget + 8.dp)
            .clip(RoundedCornerShape(Radii.control))
            .clickable(role = Role.Button, onClick = onClick)
            .padding(vertical = Spacing.s, horizontal = Spacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            IconBadge(icon, size = 32.dp)
            Spacer(Modifier.width(Spacing.m))
        }
        Column(Modifier.weight(1f)) {
            Text(title, color = colors.text, style = type.bodyStrong)
            if (subtitle != null) Text(subtitle, color = colors.textSecondary, style = type.footnote)
        }
        Icon(AetherIcons.ChevronRight, contentDescription = null, tint = colors.textTertiary, modifier = Modifier.size(20.dp))
    }
}

/** Schalter-Zeile. [note] erklärt z. B., dass Android die Einstellung bereits erzwingt. */
@Composable
fun ToggleRow(
    title: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    description: String? = null,
    enabled: Boolean = true,
    note: String? = null,
) {
    val colors = Aether.colors
    val type = Aether.type
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = MinTouchTarget + 8.dp)
            .clip(RoundedCornerShape(Radii.control))
            .toggleable(value = checked, enabled = enabled, role = Role.Switch, onValueChange = onCheckedChange)
            .padding(vertical = Spacing.s, horizontal = Spacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f).padding(end = Spacing.m)) {
            Text(title, color = if (enabled) colors.text else colors.textDisabled, style = type.bodyStrong)
            if (description != null) Text(description, color = colors.textSecondary, style = type.footnote)
            if (note != null) Text(note, color = colors.accent, style = type.footnote)
        }
        Switch(
            checked = checked,
            onCheckedChange = null, // Die ganze Zeile ist die Schaltfläche (größere Berührfläche).
            enabled = enabled,
            colors = SwitchDefaults.colors(
                checkedThumbColor = colors.onAccent,
                checkedTrackColor = colors.accent,
                checkedBorderColor = colors.accent,
                uncheckedThumbColor = colors.textSecondary,
                uncheckedTrackColor = colors.fill,
                uncheckedBorderColor = colors.textTertiary,
            ),
        )
    }
}

/**
 * Segmentierte Auswahl (z. B. Effektstärke) mit gleitender Glaslinse. Für TalkBack eine Gruppe von
 * Auswahlknöpfen.
 */
@Composable
fun <T> SegmentedControl(
    options: List<T>,
    selected: T,
    onSelect: (T) -> Unit,
    label: (T) -> String,
    modifier: Modifier = Modifier,
) {
    val colors = Aether.colors
    val motion = Aether.motion
    val index = options.indexOf(selected).coerceAtLeast(0)
    val position by animateFloatAsState(index.toFloat(), motion.gentleSpring(), label = "segment")
    var widthPx by remember { mutableIntStateOf(0) }
    val shape = RoundedCornerShape(Radii.control)
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = MinTouchTarget)
            .clip(shape)
            .background(colors.fill)
            .onSizeChanged { widthPx = it.width }
            .drawBehind {
                if (widthPx > 0 && options.isNotEmpty()) {
                    val inset = 3.dp.toPx()
                    val segment = size.width / options.size
                    drawRoundRect(
                        color = if (colors.isDark) colors.fillStrong else colors.surfaceRaised,
                        topLeft = Offset(position * segment + inset, inset),
                        size = Size(segment - 2 * inset, size.height - 2 * inset),
                        cornerRadius = CornerRadius((Radii.control - 3.dp).toPx()),
                    )
                }
            }
            .selectableGroup(),
    ) {
        options.forEachIndexed { i, option ->
            val isSelected = i == index
            Box(
                Modifier
                    .weight(1f)
                    .heightIn(min = MinTouchTarget)
                    .clip(shape)
                    .selectable(selected = isSelected, role = Role.RadioButton, onClick = { onSelect(option) }),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    label(option),
                    color = if (isSelected) colors.text else colors.textSecondary,
                    style = Aether.type.subhead,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(horizontal = Spacing.s),
                )
            }
        }
    }
}

/** Farbfeld für die Akzentauswahl. */
@Composable
fun AccentSwatch(
    color: Color,
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = Aether.colors
    Column(
        modifier
            .widthIn(min = 64.dp)
            .clip(RoundedCornerShape(Radii.control))
            .selectable(selected = selected, role = Role.RadioButton, onClick = onClick)
            .padding(vertical = Spacing.s, horizontal = Spacing.xs)
            .semantics(mergeDescendants = true) { stateDescription = if (selected) "ausgewählt" else "nicht ausgewählt" },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier
                .size(40.dp)
                .clip(CircleShape)
                .background(Brush.linearGradient(listOf(color, color.copy(alpha = 0.78f))))
                .border(if (selected) 2.5.dp else 1.dp, if (selected) colors.text else colors.hairline, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            if (selected) Icon(AetherIcons.Check, contentDescription = null, tint = colors.onAccent, modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.height(Spacing.xs))
        Text(
            label,
            color = if (selected) colors.text else colors.textSecondary,
            style = Aether.type.caption,
            maxLines = 2,
            textAlign = TextAlign.Center,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/**
 * Vorschau eines Themes als Kachel: Hintergrund, eine Glaskarte, Text- und Akzentprobe – gezeichnet mit den
 * echten Farbwerten des Themes.
 */
@Composable
fun ThemeTile(
    preview: AetherColors,
    title: String,
    description: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = Aether.colors
    val type = Aether.type
    val shape = RoundedCornerShape(Radii.control + 4.dp)
    val interaction = remember { MutableInteractionSource() }
    Column(
        modifier
            .pressFeedback(interaction)
            .clip(shape)
            .border(if (selected) 2.dp else 1.dp, if (selected) colors.accent else colors.hairline, shape)
            .selectable(selected = selected, interactionSource = interaction, indication = ripple(), role = Role.RadioButton, onClick = onClick)
            .padding(Spacing.s)
            .semantics(mergeDescendants = true) { stateDescription = if (selected) "ausgewählt" else "nicht ausgewählt" },
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(76.dp)
                .clip(RoundedCornerShape(Radii.small))
                .drawBehind {
                    drawAtmosphere(preview)
                    val pad = 8.dp.toPx()
                    val cardW = size.width - 2 * pad
                    val cardH = size.height * 0.56f
                    val r = 8.dp.toPx()
                    translate(left = pad, top = size.height - cardH - pad) {
                        drawRoundRect(Brush.verticalGradient(listOf(preview.panelTop, preview.panelBottom), 0f, cardH), size = Size(cardW, cardH), cornerRadius = CornerRadius(r))
                        drawRoundRect(preview.panelEdgeTop, size = Size(cardW, cardH), cornerRadius = CornerRadius(r), style = Stroke(1.dp.toPx()))
                        val line = 5.dp.toPx()
                        drawRoundRect(preview.text, topLeft = Offset(pad, pad), size = Size(cardW * 0.45f, line), cornerRadius = CornerRadius(line / 2))
                        drawRoundRect(preview.textTertiary, topLeft = Offset(pad, pad + line * 2f), size = Size(cardW * 0.3f, line), cornerRadius = CornerRadius(line / 2))
                        drawCircle(preview.accent, radius = 7.dp.toPx(), center = Offset(cardW - pad - 7.dp.toPx(), cardH / 2f))
                    }
                },
        )
        Spacer(Modifier.height(Spacing.s))
        Text(title, color = colors.text, style = type.subhead, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(description, color = colors.textSecondary, style = type.caption, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

/** Ruhige Schaltfläche in Pillenform (Glas bzw. gefüllt mit dem Akzent für die Hauptaktion). */
@Composable
fun PillButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    primary: Boolean = false,
    enabled: Boolean = true,
) {
    val colors = Aether.colors
    val interaction = remember { MutableInteractionSource() }
    val bg = when {
        !enabled -> colors.fill
        primary -> colors.accent
        else -> colors.fillStrong
    }
    val fg = when {
        !enabled -> colors.textDisabled
        primary -> colors.onAccent
        else -> colors.text
    }
    Row(
        modifier
            .heightIn(min = MinTouchTarget)
            .pressFeedback(interaction, enabled)
            .clip(RoundedCornerShape(50))
            .background(bg)
            .clickable(interactionSource = interaction, indication = ripple(), enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = Spacing.l, vertical = Spacing.s),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = fg, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(Spacing.s))
        }
        Text(text, color = fg, style = Aether.type.subhead)
    }
}

/** Wert mit kleiner Einheit, z. B. „82“ + „%“. Für TalkBack als ein Text. */
@Composable
fun ValueWithUnit(value: String, unit: String, modifier: Modifier = Modifier, large: Boolean = false, color: Color = Color.Unspecified) {
    val colors = Aether.colors
    val type = Aether.type
    Row(modifier.clearAndSetSemantics { contentDescription = "$value $unit" }, verticalAlignment = Alignment.Bottom) {
        Text(value, color = if (color != Color.Unspecified) color else colors.text, style = if (large) type.numberLarge else type.numberMedium)
        Spacer(Modifier.width(3.dp))
        Text(unit, color = colors.textSecondary, style = type.subhead, modifier = Modifier.padding(bottom = if (large) 6.dp else 3.dp))
    }
}
