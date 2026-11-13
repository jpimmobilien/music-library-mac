package de.privateapp.aether.ui.storage

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import de.privateapp.aether.AppGraph
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.CapacityBar
import de.privateapp.aether.design.Hairline
import de.privateapp.aether.design.InfoRow
import de.privateapp.aether.design.Notice
import de.privateapp.aether.design.Panel
import de.privateapp.aether.design.PanelHeader
import de.privateapp.aether.design.ReadingRow
import de.privateapp.aether.design.ScreenTitle
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.design.StatusBadge
import de.privateapp.aether.design.Tone
import de.privateapp.aether.model.ByteFormat
import de.privateapp.aether.model.Fmt
import de.privateapp.aether.model.Reading
import de.privateapp.aether.model.storage.CapacityMethod
import de.privateapp.aether.model.storage.StorageOverview
import de.privateapp.aether.model.storage.StorageVolumeInfo
import de.privateapp.aether.ui.common.ScreenList
import de.privateapp.aether.ui.common.UpdatedAt
import de.privateapp.aether.ui.common.icon
import de.privateapp.aether.ui.common.stateBadge
import kotlinx.coroutines.flow.StateFlow

class StorageViewModel(graph: AppGraph) : ViewModel() {
    val overview: StateFlow<StorageOverview?> = graph.storage
}

/**
 * Speicher: Kapazität und Belegung jedes Speicherorts – mit der Unterscheidung, was Android als Kapazität,
 * als Datenpartition und als sofort nutzbaren Platz meldet. Die Analyse nach Dateitypen folgt in Phase 5.
 */
@Composable
fun StorageScreen(graph: AppGraph, insets: PaddingValues, reselect: Int) {
    val vm: StorageViewModel = viewModel { StorageViewModel(graph) }
    val overview by vm.overview.collectAsStateWithLifecycle()

    ScreenList(insets, reselect) {
        item(key = "title") {
            ScreenTitle("Speicher", subtitle = "Kapazität und Belegung aller Speicherorte, die Android meldet")
        }
        val volumes = overview?.volumes
        when {
            volumes == null -> item(key = "loading") {
                Panel { Text("Speicherorte werden gelesen …", color = Aether.colors.textSecondary, style = Aether.type.callout) }
            }
            volumes.isEmpty() -> item(key = "none") {
                Notice(
                    title = "Keine Speicherorte gemeldet",
                    message = "Android hat keine Speicherorte zurückgegeben. Das ist ungewöhnlich – ein Neustart des Geräts behebt es meist.",
                    tone = Tone.WARNING,
                )
            }
            else -> items(volumes, key = { "vol-${it.id}" }) { VolumePanel(it) }
        }
        item(key = "updated") { UpdatedAt(overview?.observedAtMillis, label = "Zuletzt geändert um") }
        item(key = "next") {
            Notice(
                title = "Speicheranalyse folgt",
                message = "Verteilung nach Dateitypen, große Dateien, mögliche Duplikate und alte Downloads kommen mit dem " +
                    "Speicherassistenten (Phase 5). Er wertet nur zugängliche Bereiche aus und zeigt offen, was nicht " +
                    "zugänglich war. Dateien durchsuchen und verwalten: Bereich „Dateien“.",
                tone = Tone.INFO,
                icon = AetherIcons.Info,
            )
        }
    }
}

@Composable
private fun VolumePanel(v: StorageVolumeInfo) {
    val colors = Aether.colors
    val type = Aether.type
    val badge = v.stateBadge()
    Panel {
        PanelHeader(
            icon = v.kind.icon(),
            title = v.description,
            subtitle = if (v.isPrimary) "Interner Speicher" else v.kind.label,
            trailing = if (badge != null) {
                { StatusBadge(badge.first, badge.second) }
            } else {
                null
            },
        )
        val c = (v.capacity as? Reading.Value)?.value
        if (c != null) {
            Spacer(Modifier.height(Spacing.l))
            Row(verticalAlignment = Alignment.Bottom) {
                Text(ByteFormat.format(c.usedBytes), color = colors.text, style = type.numberMedium)
                Spacer(Modifier.width(Spacing.s))
                Text("von ${ByteFormat.format(c.totalBytes)} belegt", color = colors.textSecondary, style = type.callout)
            }
            Spacer(Modifier.height(Spacing.s))
            CapacityBar(c.usedFraction.toFloat(), height = 8.dp)
            Spacer(Modifier.height(Spacing.s))
        }
        Column {
            if (c != null) {
                InfoRow("Belegt", "${ByteFormat.format(c.usedBytes)} (${Fmt.percent(c.usedFraction)})", caption = "berechnet · gesamt − frei")
            }
            ReadingRow("Frei", v.capacity, showSource = true) { ByteFormat.format(it.freeBytes) }
            InfoRow("Zustand", v.state.label)
            v.path?.let { InfoRow("Pfad", it, caption = if (v.isEmulated) "Freigegebener Speicher von Android" else null) }
        }
        if (v.isPrimary && c != null && c.method == CapacityMethod.SYSTEM_STATS) {
            Spacer(Modifier.height(Spacing.s))
            Hairline()
            Spacer(Modifier.height(Spacing.s))
            Text("Was Android hier unterscheidet", color = colors.text, style = type.subhead)
            InfoRow("Kapazität", ByteFormat.format(c.totalBytes), caption = "wie im Handel angegeben (Speicherstatistik)")
            v.partition?.let { p ->
                ReadingRow("Datenpartition", p, showSource = true) { ByteFormat.format(it.sizeBytes) }
                ReadingRow("Sofort für Apps verfügbar", p) { ByteFormat.format(it.availableBytes) }
            }
            v.reclaimableCache?.let { r ->
                ReadingRow("Freigebbarer Zwischenspeicher", r) { ByteFormat.format(it) }
            }
            v.outsideDataPartition?.let { r ->
                ReadingRow("Außerhalb der Datenpartition", r) { ByteFormat.format(it) }
            }
            Spacer(Modifier.height(Spacing.s))
            Notice(
                title = "Warum „frei“ mehr ist als „sofort verfügbar“",
                message = "Android zählt Zwischenspeicher von Apps, den es bei Platzbedarf selbst löscht, zum freien Platz – " +
                    "genau wie die Android-Einstellungen. Der Teil außerhalb der Datenpartition enthält das Betriebssystem " +
                    "und Firmware; er ist für Dateien nicht nutzbar.",
                tone = Tone.NEUTRAL,
            )
        }
    }
}
