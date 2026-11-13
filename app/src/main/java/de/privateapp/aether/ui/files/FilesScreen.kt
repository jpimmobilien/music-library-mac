package de.privateapp.aether.ui.files

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import de.privateapp.aether.AppGraph
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.CapacityBar
import de.privateapp.aether.design.Hairline
import de.privateapp.aether.design.IconBadge
import de.privateapp.aether.design.NavRow
import de.privateapp.aether.design.Panel
import de.privateapp.aether.design.PanelHeader
import de.privateapp.aether.design.PillButton
import de.privateapp.aether.design.Radii
import de.privateapp.aether.design.ScreenTitle
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.design.Tone
import de.privateapp.aether.model.ByteFormat
import de.privateapp.aether.model.Fmt
import de.privateapp.aether.model.Reading
import de.privateapp.aether.navigation.LocalAppNavigator
import de.privateapp.aether.navigation.Route
import de.privateapp.aether.platform.storage.AllFilesAccess
import de.privateapp.aether.platform.storage.MediaCategory
import de.privateapp.aether.ui.common.GridRows
import de.privateapp.aether.ui.common.ScreenList
import de.privateapp.aether.ui.common.entrance
import de.privateapp.aether.ui.common.freeOfTotal
import de.privateapp.aether.ui.common.icon

/**
 * „Dateien“ – Startseite des Dateimanagers wie „Durchsuchen“ in der Dateien-App von Apple: Suche, Speicherorte mit
 * Belegung, Favoriten, Schnellzugriff, Kategorien, zuletzt geöffnet und Papierkorb. Ohne „Zugriff auf alle Dateien“
 * erklärt die Seite zuerst, wozu er dient, und führt mit einem Tipp in die Einstellung.
 */
@Composable
fun FilesScreen(graph: AppGraph, insets: PaddingValues, reselect: Int) {
    val vm: FilesHomeViewModel = viewModel { FilesHomeViewModel(graph) }
    val state by vm.state.collectAsStateWithLifecycle()
    val navigator = LocalAppNavigator.current
    val actions = fileActions
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { vm.onResume() }

    ScreenList(insets, reselect) {
        item(key = "title") {
            ScreenTitle("Dateien", subtitle = "Interner Speicher, SD-Karten und USB-Speicher", modifier = Modifier.entrance(0))
        }
        if (state.access == false) {
            item(key = "access") { AccessPanel() }
        }
        if (state.access == true) {
            item(key = "search") { SearchEntry(onClick = { navigator.push(Route.Search) }) }
        }
        item(key = "locations") {
            Panel(Modifier.entrance(1)) {
                PanelHeader(icon = AetherIcons.Drive, title = "Speicherorte", subtitle = if (state.access == true) "Antippen zum Durchsuchen" else "Laut Android")
                state.roots.forEachIndexed { i, info ->
                    if (i > 0) Hairline(Modifier.padding(vertical = Spacing.xs))
                    RootRow(info, enabled = state.access == true) { navigator.push(Route.Folder(info.root.path)) }
                }
                if (state.roots.isEmpty()) {
                    Spacer(Modifier.height(Spacing.s))
                    Text("Wird gelesen …", color = Aether.colors.textSecondary, style = Aether.type.callout)
                }
            }
        }
        if (state.access == true) {
            if (state.favorites.isNotEmpty() || state.missingFavorites.isNotEmpty()) {
                item(key = "favorites") {
                    Panel {
                        PanelHeader(icon = AetherIcons.StarFilled, title = "Favoriten", subtitle = "Im Ordnermenü hinzufügen oder entfernen")
                        state.favorites.forEach { f ->
                            NavRow(title = f.name, subtitle = displayParent(f.path), icon = AetherIcons.Folder, onClick = { navigator.push(Route.Folder(f.path)) })
                        }
                        state.missingFavorites.forEach { p ->
                            MissingFavoriteRow(p, onRemove = { vm.removeFavorite(p) })
                        }
                    }
                }
            }
            if (state.quick.isNotEmpty()) {
                item(key = "quick") {
                    Panel {
                        PanelHeader(icon = AetherIcons.Folder, title = "Schnellzugriff", subtitle = "Häufige Ordner im internen Speicher")
                        Spacer(Modifier.height(Spacing.s))
                        GridRows(state.quick, columns = 3) { q, m ->
                            QuickTile(q.label, m) { navigator.push(Route.Folder(q.path)) }
                        }
                    }
                }
            }
            item(key = "categories") {
                Panel {
                    PanelHeader(icon = AetherIcons.Layers, title = "Kategorien", subtitle = "Aus dem Medienindex von Android")
                    Spacer(Modifier.height(Spacing.m))
                    GridRows(MediaCategory.entries, columns = 2) { c, m ->
                        CategoryTile(c, state.categories[c], m) { navigator.push(Route.Category(c)) }
                    }
                }
            }
            if (state.recent.isNotEmpty()) {
                item(key = "recent") {
                    Panel {
                        PanelHeader(icon = AetherIcons.Clock, title = "Zuletzt geöffnet", subtitle = "Nur auf diesem Gerät gespeichert") {
                            PillButton("Leeren", onClick = { vm.clearRecent() })
                        }
                        Spacer(Modifier.height(Spacing.s))
                        state.recent.forEachIndexed { i, e ->
                            FileRow(
                                entry = e,
                                selected = false,
                                selecting = false,
                                detail = e.detailLine(state.now),
                                location = displayParent(e.path),
                                onClick = { actions.open(e) },
                                onLongClick = { actions.showActions(listOf(e)) },
                                onMore = { actions.showActions(listOf(e)) },
                                showDivider = i < state.recent.lastIndex,
                            )
                        }
                    }
                }
            }
            item(key = "trash") {
                Panel {
                    val t = state.trash
                    NavRow(
                        title = "Papierkorb",
                        subtitle = when {
                            t == null -> "Wird gelesen …"
                            t.count == 0 -> "Leer"
                            else -> "${if (t.count == 1) "1 Objekt" else "${Fmt.count(t.count)} Objekte"} · ${ByteFormat.format(t.bytes)}"
                        },
                        icon = AetherIcons.Trash,
                        onClick = { navigator.push(Route.Trash) },
                    )
                }
            }
        }
    }
}

/** Zugriff erklären – ehrlich, was er erlaubt, was nicht, und dass nichts das Gerät verlässt. */
@Composable
private fun AccessPanel() {
    val context = LocalContext.current
    val colors = Aether.colors
    val type = Aether.type
    Panel(Modifier.entrance(1)) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.height(Spacing.s))
            IconBadge(AetherIcons.Folder, size = 64.dp)
            Spacer(Modifier.height(Spacing.l))
            Text("Zugriff auf alle Dateien", color = colors.text, style = type.title2)
            Spacer(Modifier.height(Spacing.xs))
            Text(
                "Damit ORBIT als Dateimanager arbeiten kann, erlaubt Android das nur über eine eigene Einstellung.",
                color = colors.textSecondary,
                style = type.callout,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
        Spacer(Modifier.height(Spacing.l))
        Bullet(AetherIcons.Folder, "Ordner und Dateien durchsuchen, öffnen, umbenennen, kopieren, verschieben und löschen – im internen Speicher, auf SD-Karten und USB-Speichern.")
        Bullet(AetherIcons.Shield, "Alles bleibt auf dem Gerät: ORBIT hat keine Internet-Berechtigung und kann nichts senden.")
        Bullet(AetherIcons.Trash, "Gelöschtes landet zuerst im Papierkorb. Endgültig gelöscht wird nur nach ausdrücklicher Bestätigung.")
        Bullet(AetherIcons.Lock, "Auch mit dieser Erlaubnis sperrt Android die Ordner „Android/data“ und „Android/obb“ anderer Apps.")
        Spacer(Modifier.height(Spacing.l))
        PillButton(
            "In den Einstellungen erlauben",
            onClick = {
                val ok = try {
                    context.startActivity(AllFilesAccess.settingsIntent(context))
                    true
                } catch (e: RuntimeException) {
                    false
                }
                if (!ok) {
                    try {
                        context.startActivity(AllFilesAccess.fallbackIntent())
                    } catch (e: RuntimeException) {
                        context.startActivity(AllFilesAccess.appDetailsIntent(context))
                    }
                }
            },
            primary = true,
            icon = AetherIcons.OpenExternal,
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(Spacing.s))
        Text(
            "Schalte dort „Zugriff auf alle Dateien erlauben“ ein (Xiaomi/HyperOS: „Verwaltung aller Dateien erlauben“) und kehre zurück – ORBIT erkennt es sofort.",
            color = colors.textTertiary,
            style = type.footnote,
        )
    }
}

@Composable
private fun Bullet(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = Spacing.xs), verticalAlignment = Alignment.Top) {
        Icon(icon, contentDescription = null, tint = Aether.colors.accent, modifier = Modifier.size(20.dp).padding(top = 1.dp))
        Spacer(Modifier.width(Spacing.m))
        Text(text, color = Aether.colors.text, style = Aether.type.callout, modifier = Modifier.weight(1f))
    }
}

/** Sieht aus wie ein Suchfeld, öffnet die Suche (dort mit Tastatur). */
@Composable
private fun SearchEntry(onClick: () -> Unit) {
    val colors = Aether.colors
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clip(RoundedCornerShape(Radii.control))
            .background(colors.fill)
            .clickable(role = Role.Button, onClickLabel = "Suche öffnen", onClick = onClick)
            .padding(horizontal = Spacing.m)
            .semantics(mergeDescendants = true) { contentDescription = "Dateien suchen" },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(AetherIcons.Search, contentDescription = null, tint = colors.textSecondary, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(Spacing.s))
        Text("Dateien und Ordner suchen", color = colors.textSecondary, style = Aether.type.body)
    }
}

@Composable
private fun RootRow(info: RootInfo, enabled: Boolean, onClick: () -> Unit) {
    val colors = Aether.colors
    val r = info.root
    val cap = (info.capacity as? Reading.Value)?.value
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radii.control))
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(vertical = Spacing.s, horizontal = Spacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconBadge(r.kind.icon(), size = 36.dp)
        Spacer(Modifier.width(Spacing.m))
        Column(Modifier.weight(1f)) {
            Text(FolderViewModel.rootLabel(r), color = colors.text, style = Aether.type.bodyStrong, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                listOfNotNull(info.capacity?.freeOfTotal(), if (r.readOnly) "nur lesbar" else null).joinToString(" · ").ifEmpty { "Kapazität wird gelesen …" },
                color = colors.textSecondary,
                style = Aether.type.footnote,
            )
            if (cap != null) {
                Spacer(Modifier.height(Spacing.xs))
                CapacityBar(cap.usedFraction.toFloat(), tone = if (cap.usedFraction > 0.9) Tone.WARNING else Tone.ACCENT, height = 4.dp)
            }
        }
        if (enabled) {
            Spacer(Modifier.width(Spacing.s))
            Icon(AetherIcons.ChevronRight, contentDescription = null, tint = colors.textTertiary, modifier = Modifier.size(20.dp))
        }
    }
}

@Composable
private fun QuickTile(label: String, modifier: Modifier, onClick: () -> Unit) {
    val colors = Aether.colors
    Column(
        modifier
            .clip(RoundedCornerShape(Radii.control))
            .background(colors.fill)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(vertical = Spacing.m),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(AetherIcons.Folder, contentDescription = null, tint = colors.accent, modifier = Modifier.size(26.dp))
        Spacer(Modifier.height(Spacing.xs))
        Text(label, color = colors.text, style = Aether.type.caption, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun CategoryTile(category: MediaCategory, summary: de.privateapp.aether.platform.storage.CategorySummary?, modifier: Modifier, onClick: () -> Unit) {
    val colors = Aether.colors
    Row(
        modifier
            .clip(RoundedCornerShape(Radii.control))
            .background(colors.fill)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(Spacing.m)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconBadge(category.icon(), tone = category.tone(), size = 34.dp)
        Spacer(Modifier.width(Spacing.s))
        Column(Modifier.weight(1f)) {
            Text(category.label, color = colors.text, style = Aether.type.subhead, maxLines = 1, overflow = TextOverflow.Ellipsis)
            // Anzahl und Größe in zwei Zeilen – auf schmalen Telefonen passt beides nicht in eine.
            Text(
                when {
                    summary == null -> "Wird gezählt …"
                    summary.count == 0 -> "Keine"
                    summary.count == 1 -> "1 Datei"
                    else -> "${Fmt.count(summary.count)} Dateien"
                },
                color = colors.textSecondary,
                style = Aether.type.caption,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            // Zweite Zeile immer belegen (notfalls leer), damit alle Kacheln einer Reihe gleich hoch sind.
            Text(
                if (summary != null && summary.count > 0) ByteFormat.format(summary.totalBytes) else "",
                color = colors.textSecondary,
                style = Aether.type.caption,
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun MissingFavoriteRow(path: String, onRemove: () -> Unit) {
    val colors = Aether.colors
    Row(Modifier.fillMaxWidth().padding(vertical = Spacing.s, horizontal = Spacing.xs), verticalAlignment = Alignment.CenterVertically) {
        IconBadge(AetherIcons.Folder, tone = Tone.NEUTRAL, size = 32.dp)
        Spacer(Modifier.width(Spacing.m))
        Column(Modifier.weight(1f)) {
            Text(path.substringAfterLast('/'), color = colors.textSecondary, style = Aether.type.bodyStrong, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("Gerade nicht verfügbar (gelöscht, verschoben oder Speicher entnommen)", color = colors.textTertiary, style = Aether.type.footnote)
        }
        PillButton("Entfernen", onClick = onRemove)
    }
}

