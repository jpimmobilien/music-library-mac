package de.privateapp.aether.design

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.error
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp

/**
 * Eingabefeld im Stil von ORBIT: ruhige, gefüllte Fläche, Akzent nur am Rand, wenn es aktiv ist; Fehler werden
 * unter dem Feld in Worten genannt (nicht nur farbig markiert).
 *
 * @param label Bezeichnung für TalkBack (und als Platzhalter, wenn [placeholder] fehlt).
 */
@Composable
fun GlassTextField(
    value: TextFieldValue,
    onValueChange: (TextFieldValue) -> Unit,
    label: String,
    modifier: Modifier = Modifier,
    placeholder: String? = null,
    leadingIcon: ImageVector? = null,
    error: String? = null,
    imeAction: ImeAction = ImeAction.Done,
    onImeAction: () -> Unit = {},
    focusRequester: FocusRequester? = null,
    capitalization: KeyboardCapitalization = KeyboardCapitalization.None,
    onClear: (() -> Unit)? = null,
) {
    val colors = Aether.colors
    val type = Aether.type
    val shape = RoundedCornerShape(Radii.control)
    val edge = if (error != null) colors.critical else colors.hairline
    Column(modifier.fillMaxWidth()) {
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            singleLine = true,
            textStyle = type.body.copy(color = colors.text),
            cursorBrush = SolidColor(colors.accent),
            keyboardOptions = KeyboardOptions(imeAction = imeAction, capitalization = capitalization, autoCorrectEnabled = false),
            keyboardActions = KeyboardActions(onAny = { onImeAction() }),
            modifier = Modifier
                .fillMaxWidth()
                .then(if (focusRequester != null) Modifier.focusRequester(focusRequester) else Modifier)
                .semantics {
                    contentDescription = label
                    if (error != null) error(error)
                },
            decorationBox = { inner ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = MinTouchTarget)
                        .clip(shape)
                        .background(colors.fill)
                        .border(0.8.dp, edge, shape)
                        .padding(horizontal = Spacing.m, vertical = Spacing.s),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (leadingIcon != null) {
                        Icon(leadingIcon, contentDescription = null, tint = colors.textSecondary, modifier = Modifier.size(20.dp))
                        Spacer(Modifier.width(Spacing.s))
                    }
                    Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                        if (value.text.isEmpty()) {
                            // Platzhalter in Sekundärschrift: Auf der gefüllten Fläche erreicht nur sie 4,5 : 1 (ContrastTest).
                            Text(placeholder ?: label, color = colors.textSecondary, style = type.body, maxLines = 1)
                        }
                        inner()
                    }
                    if (onClear != null && value.text.isNotEmpty()) {
                        Spacer(Modifier.width(Spacing.s))
                        Box(
                            Modifier
                                .size(28.dp)
                                .clip(CircleShape)
                                .background(colors.fillStrong)
                                .clickable(role = Role.Button, onClick = onClear)
                                .semantics { contentDescription = "Eingabe löschen" },
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(AetherIcons.Close, contentDescription = null, tint = colors.textSecondary, modifier = Modifier.size(14.dp))
                        }
                    }
                }
            },
        )
        if (error != null) {
            Text(error, color = colors.critical, style = type.footnote, modifier = Modifier.padding(top = Spacing.xs, start = Spacing.xs))
        }
    }
}
