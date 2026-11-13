package de.privateapp.aether.ui.files.preview

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.PillButton
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.files.FileEntry
import de.privateapp.aether.files.FileKind
import de.privateapp.aether.ui.files.FileThumbnail
import de.privateapp.aether.ui.files.fileActions

/**
 * Für alles, was ORBIT nicht selbst darstellt: großes Vorschaubild bzw. Symbol, Angaben und die Wege weiter –
 * „Öffnen mit …“, Teilen, Informationen (bei App-Paketen „Installieren“).
 */
@Composable
internal fun FallbackPreview(entry: FileEntry, bottomPadding: Dp, message: String) {
    val colors = Aether.colors
    val actions = fileActions
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(start = Spacing.page, end = Spacing.page, top = Spacing.xxl, bottom = bottomPadding + Spacing.xxl),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        FileThumbnail(entry, size = 132.dp)
        Spacer(Modifier.height(Spacing.l))
        Text(
            entry.name,
            color = colors.text,
            style = Aether.type.title2,
            textAlign = TextAlign.Center,
            maxLines = 3,
            overflow = TextOverflow.Ellipsis,
        )
        Spacer(Modifier.height(Spacing.xs))
        Text(subtitleOf(entry), color = colors.textSecondary, style = Aether.type.footnote, textAlign = TextAlign.Center)
        Spacer(Modifier.height(Spacing.l))
        Text(message, color = colors.textSecondary, style = Aether.type.callout, textAlign = TextAlign.Center, modifier = Modifier.widthIn(max = 420.dp))
        Spacer(Modifier.height(Spacing.xl))
        Column(Modifier.widthIn(max = 320.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
            if (entry.kind == FileKind.APK) {
                PillButton("Installieren", onClick = { actions.install(entry) }, icon = AetherIcons.Download, primary = true, modifier = Modifier.fillMaxWidth())
            }
            PillButton(
                "Öffnen mit …",
                onClick = { actions.openWith(entry) },
                icon = AetherIcons.OpenExternal,
                primary = entry.kind != FileKind.APK,
                modifier = Modifier.fillMaxWidth(),
            )
            PillButton("Teilen", onClick = { actions.share(listOf(entry)) }, icon = AetherIcons.Share, modifier = Modifier.fillMaxWidth())
            PillButton("Informationen", onClick = { actions.info(entry) }, icon = AetherIcons.Info, modifier = Modifier.fillMaxWidth())
        }
    }
}
