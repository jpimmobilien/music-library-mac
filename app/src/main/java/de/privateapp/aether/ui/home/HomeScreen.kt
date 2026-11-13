package de.privateapp.aether.ui.home

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import de.privateapp.aether.AppGraph
import de.privateapp.aether.BuildConfig
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.BatteryGlyph
import de.privateapp.aether.design.CapacityBar
import de.privateapp.aether.design.Hairline
import de.privateapp.aether.design.IconBadge
import de.privateapp.aether.design.Notice
import de.privateapp.aether.design.Panel
import de.privateapp.aether.design.PanelHeader
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.design.StatusBadge
import de.privateapp.aether.design.StorageRing
import de.privateapp.aether.design.Tone
import de.privateapp.aether.model.ByteFormat
import de.privateapp.aether.model.Fmt
import de.privateapp.aether.model.Insight
import de.privateapp.aether.model.InsightTarget
import de.privateapp.aether.model.Insights
import de.privateapp.aether.model.Reading
import de.privateapp.aether.model.Severity
import de.privateapp.aether.model.device.ChargeStatus
import de.privateapp.aether.model.storage.StorageVolumeInfo
import de.privateapp.aether.navigation.Route
import de.privateapp.aether.navigation.TopLevel
import de.privateapp.aether.platform.storage.AllFilesAccess
import de.privateapp.aether.platform.storage.MediaCategory
import de.privateapp.aether.ui.common.GridRows
import de.privateapp.aether.ui.files.icon
import de.privateapp.aether.ui.files.tone
import de.privateapp.aether.design.Radii
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextOverflow
import androidx.lifecycle.compose.LifecycleResumeEffect
import de.privateapp.aether.ui.common.ScreenList
import de.privateapp.aether.ui.common.accessibleSummary
import de.privateapp.aether.ui.common.entrance
import de.privateapp.aether.ui.common.freeOfTotal
import de.privateapp.aether.ui.common.icon
import de.privateapp.aether.ui.common.levelTone
import de.privateapp.aether.ui.common.stateBadge
import de.privateapp.aether.ui.common.statusText
import de.privateapp.aether.ui.common.tone

/**
 * Übersicht: Gerät auf einen Blick – Speicher, weitere Speicherorte, Gerätestatus und Hinweise. Alle Werte
 * sind echt; was (noch) nicht gelesen ist, sagt das.
 */
@Composable
fun HomeScreen(graph: AppGraph, insets: PaddingValues, reselect: Int, onOpen: (TopLevel) -> Unit, onOpenRoute: (TopLevel, Route) -> Unit) {
    val vm: HomeViewModel = viewModel { HomeViewModel(graph) }
    val state by vm.state.collectAsStateWithLifecycle()
    val insights = Insights.from(state.storage, state.battery, state.thermal)
    var filesAccess by remember { mutableStateOf(AllFilesAccess.isGranted()) }
    LifecycleResumeEffect(Unit) {
        filesAccess = AllFilesAccess.isGranted()
        onPauseOrDispose { }
    }

    ScreenList(insets, reselect) {
        item(key = "header") { HomeHeader(state, Modifier.entrance(0)) }
        item(key = "storage") { StorageHero(state, onClick = { onOpen(TopLevel.STORAGE) }, modifier = Modifier.entrance(1)) }
        item(key = "shortcuts") {
            QuickAccessPanel(
                filesAccess = filesAccess,
                onCategory = { c -> if (filesAccess) onOpenRoute(TopLevel.FILES, Route.Category(c)) else onOpen(TopLevel.FILES) },
                onMotion = { onOpenRoute(TopLevel.DEVICE, Route.Motion) },
                modifier = Modifier.entrance(2),
            )
        }
        if (insights.isNotEmpty()) {
            item(key = "insights") {
                InsightsPanel(insights, onOpen = { target ->
                    onOpen(
                        when (target) {
                            InsightTarget.STORAGE -> TopLevel.STORAGE
                            InsightTarget.DEVICE -> TopLevel.DEVICE
                            InsightTarget.FILES -> TopLevel.FILES
                        },
                    )
                }, modifier = Modifier.entrance(3))
            }
        }
        item(key = "device") { DeviceStatusPanel(state, onClick = { onOpen(TopLevel.DEVICE) }, modifier = Modifier.entrance(4)) }
        if (state.externalVolumes.isNotEmpty()) {
            item(key = "volumes") { VolumesPanel(state.externalVolumes, onClick = { onOpen(TopLevel.STORAGE) }, modifier = Modifier.entrance(5)) }
        }
    }
}

/**
 * Schnellzugriffe auf echte Ziele: häufige Dateikategorien und „Bewegung“. Ohne Dateizugriff führen die Kategorien
 * zur Erklärung unter „Dateien“ (keine Schaltfläche ins Leere).
 */
@Composable
private fun QuickAccessPanel(filesAccess: Boolean, onCategory: (MediaCategory) -> Unit, onMotion: () -> Unit, modifier: Modifier = Modifier) {
    val colors = Aether.colors
    Panel(modifier) {
        PanelHeader(
            icon = AetherIcons.Sparkle,
            title = "Schnellzugriff",
            subtitle = if (filesAccess) "Kategorien und Live-Werte" else "Für Dateien zuerst den Zugriff erlauben",
        )
        Spacer(Modifier.height(Spacing.m))
        val targets = listOf(MediaCategory.DOWNLOADS, MediaCategory.IMAGES, MediaCategory.DOCUMENTS, MediaCategory.RECENT)
        GridRows(targets + listOf<MediaCategory?>(null), columns = 3) { c, m ->
            val label = c?.label ?: "Bewegung"
            Column(
                m
                    .clip(RoundedCornerShape(Radii.control))
                    .background(colors.fill)
                    .clickable(role = Role.Button, onClick = { if (c != null) onCategory(c) else onMotion() })
                    .padding(vertical = Spacing.m, horizontal = Spacing.xs),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                IconBadge(c?.icon() ?: AetherIcons.Gauge, tone = c?.tone() ?: Tone.ACCENT, size = 34.dp)
                Spacer(Modifier.height(Spacing.xs))
                Text(label, color = colors.text, style = Aether.type.caption, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@Composable
private fun HomeHeader(state: HomeState, modifier: Modifier = Modifier) {
    val colors = Aether.colors
    val type = Aether.type
    val motion = Aether.motion
    Column(modifier.fillMaxWidth().padding(bottom = Spacing.s)) {
        Text(BuildConfig.APP_NAME.uppercase(), color = colors.accent, style = type.eyebrow)
        Spacer(Modifier.height(Spacing.xs))
        Text(state.device?.displayName ?: "Übersicht", color = colors.text, style = type.largeTitle)
        Spacer(Modifier.height(Spacing.xs))
        AnimatedContent(
            targetState = state.statusLine,
            transitionSpec = { fadeIn(motion.fade(240)) togetherWith fadeOut(motion.fade(160)) },
            label = "statusLine",
        ) { line ->
            Text(line, color = colors.textSecondary, style = type.callout)
        }
    }
}

@Composable
private fun StorageHero(state: HomeState, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = Aether.colors
    val type = Aether.type
    val internal = state.storage?.internal
    val capacity = internal?.capacity
    Panel(modifier, onClick = onClick, onClickLabel = "Speicher öffnen") {
        PanelHeader(
            icon = AetherIcons.Drive,
            title = "Interner Speicher",
            subtitle = when {
                state.storage == null -> "Wird gelesen …"
                capacity == null -> "Android meldet keinen internen Speicher"
                capacity is Reading.Value -> "${capacity.source} · belegt = gesamt − frei"
                capacity is Reading.Unavailable -> capacity.missing.text
                else -> null
            },
            trailing = { Icon(AetherIcons.ChevronRight, contentDescription = null, tint = colors.textTertiary, modifier = Modifier.size(20.dp)) },
        )
        Spacer(Modifier.height(Spacing.l))
        Row(verticalAlignment = Alignment.CenterVertically) {
            val fraction = state.internalUsedFraction
            StorageRing(
                usedFraction = fraction,
                description = internal?.accessibleSummary()
                    ?: if (state.storage == null) "Interner Speicher: wird gelesen" else "Kein interner Speicher gemeldet",
                modifier = Modifier.size(136.dp),
                thickness = 15.dp,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        if (fraction != null) Fmt.percent(fraction.toDouble()) else "–",
                        color = colors.text,
                        style = type.numberMedium,
                        textAlign = TextAlign.Center,
                    )
                    Text("belegt", color = colors.textSecondary, style = type.caption)
                }
            }
            Spacer(Modifier.width(Spacing.xl))
            Column(Modifier.weight(1f)) {
                val c = (capacity as? Reading.Value)?.value
                LegendRow("Belegt", c?.let { ByteFormat.format(it.usedBytes) }, colors.accent)
                LegendRow("Frei", c?.let { ByteFormat.format(it.freeBytes) }, colors.fill)
                Spacer(Modifier.height(Spacing.s))
                Hairline()
                Spacer(Modifier.height(Spacing.s))
                LegendRow("Gesamt", c?.let { ByteFormat.format(it.totalBytes) }, null)
            }
        }
    }
}

@Composable
private fun LegendRow(label: String, value: String?, dot: Color?) {
    val colors = Aether.colors
    val type = Aether.type
    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp).semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically) {
        if (dot != null) {
            // Punkt in der Farbe des Diagramms (Frei = Spur); feine Kontur, damit auch die zarte Spurfarbe sichtbar ist
            Box(Modifier.size(9.dp).clip(CircleShape).background(dot).border(1.dp, colors.hairline, CircleShape))
            Spacer(Modifier.width(Spacing.s))
        } else {
            Spacer(Modifier.width(9.dp + Spacing.s))
        }
        Text(label, color = colors.textSecondary, style = type.footnote, modifier = Modifier.weight(1f))
        Text(value ?: "–", color = colors.text, style = type.numberSmall)
    }
}

@Composable
private fun InsightsPanel(insights: List<Insight>, onOpen: (InsightTarget) -> Unit, modifier: Modifier = Modifier) {
    Panel(modifier) {
        PanelHeader(icon = AetherIcons.Sparkle, title = "Hinweise", subtitle = "Aus den aktuellen Werten dieses Geräts")
        Spacer(Modifier.height(Spacing.m))
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
            insights.forEach { insight ->
                val tone = when (insight.severity) {
                    Severity.INFO -> Tone.INFO
                    Severity.ATTENTION -> Tone.WARNING
                    Severity.CRITICAL -> Tone.CRITICAL
                }
                Notice(
                    title = insight.title,
                    message = insight.message,
                    tone = tone,
                    onClick = { onOpen(insight.target) },
                    onClickLabel = "Öffnen",
                )
            }
        }
    }
}

@Composable
private fun DeviceStatusPanel(state: HomeState, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = Aether.colors
    val type = Aether.type
    val battery = state.battery
    val thermal = state.thermal
    Panel(modifier, onClick = onClick, onClickLabel = "Gerät öffnen") {
        PanelHeader(
            icon = AetherIcons.Pulse,
            title = "Gerätestatus",
            subtitle = "Akku und Wärme",
            trailing = { Icon(AetherIcons.ChevronRight, contentDescription = null, tint = colors.textTertiary, modifier = Modifier.size(20.dp)) },
        )
        Spacer(Modifier.height(Spacing.m))

        // Akku (ohne Akku – z. B. Emulator – keine Akkuwerte)
        val noBattery = battery != null && !battery.present
        StatusRow(
            leading = {
                val level = (battery?.level as? Reading.Value)?.value
                BatteryGlyph(level, charging = battery?.status == ChargeStatus.CHARGING, tone = battery?.levelTone() ?: Tone.NEUTRAL)
            },
            label = "Akku",
            detail = battery?.statusText() ?: "Wird gelesen …",
            value = if (noBattery) "–" else (battery?.level as? Reading.Value)?.value?.let { Fmt.percentInt(it) } ?: "–",
        )
        Hairline(Modifier.padding(vertical = Spacing.s))
        // Akku-Temperatur
        val temp = battery?.temperatureCelsius
        StatusRow(
            leading = { IconBadge(AetherIcons.Thermometer, tone = Tone.NEUTRAL, size = 32.dp) },
            label = "Akku-Temperatur",
            detail = when {
                noBattery -> "Kein Akku erkannt"
                temp == null -> "Wird gelesen …"
                temp is Reading.Value -> "Sensor im Akku"
                temp is Reading.Unavailable -> temp.missing.text
                else -> ""
            },
            value = if (noBattery) "–" else (temp as? Reading.Value)?.value?.let { Fmt.celsius(it) } ?: "–",
        )
        Hairline(Modifier.padding(vertical = Spacing.s))
        // Thermalstatus
        val level = (thermal?.level as? Reading.Value)?.value
        StatusRow(
            leading = { IconBadge(AetherIcons.Sensor, tone = level?.tone() ?: Tone.NEUTRAL, size = 32.dp) },
            label = "Thermalstatus",
            detail = level?.meaning ?: when (val l = thermal?.level) {
                null -> "Wird gelesen …"
                is Reading.Unavailable -> l.missing.text
                else -> ""
            },
            trailingContent = {
                if (level != null) {
                    StatusBadge(level.label, level.tone(), icon = if (level.isElevated) AetherIcons.Warning else AetherIcons.CheckCircle)
                } else {
                    Text("–", color = colors.text, style = type.numberSmall)
                }
            },
        )
    }
}

@Composable
private fun StatusRow(
    leading: @Composable () -> Unit,
    label: String,
    detail: String,
    value: String? = null,
    trailingContent: (@Composable () -> Unit)? = null,
) {
    val colors = Aether.colors
    val type = Aether.type
    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.width(48.dp), contentAlignment = Alignment.CenterStart) { leading() }
        Spacer(Modifier.width(Spacing.s))
        Column(Modifier.weight(1f)) {
            Text(label, color = colors.text, style = type.bodyStrong)
            if (detail.isNotEmpty()) Text(detail, color = colors.textSecondary, style = type.footnote)
        }
        Spacer(Modifier.width(Spacing.s))
        if (trailingContent != null) trailingContent() else Text(value ?: "–", color = colors.text, style = type.numberSmall)
    }
}

@Composable
private fun VolumesPanel(volumes: List<StorageVolumeInfo>, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = Aether.colors
    val type = Aether.type
    Panel(modifier, onClick = onClick, onClickLabel = "Speicherorte öffnen") {
        PanelHeader(icon = AetherIcons.SdCard, title = "Weitere Speicherorte", subtitle = "Von Android gemeldet")
        volumes.forEach { v ->
            Spacer(Modifier.height(Spacing.m))
            Column(Modifier.semantics(mergeDescendants = true) {}) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(v.kind.icon(), contentDescription = null, tint = colors.textSecondary, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.width(Spacing.s))
                    Text(v.description, color = colors.text, style = type.bodyStrong, modifier = Modifier.weight(1f))
                    v.stateBadge()?.let { (text, tone) -> StatusBadge(text, tone) }
                }
                Spacer(Modifier.height(Spacing.s))
                CapacityBar((v.capacity as? Reading.Value)?.value?.usedFraction?.toFloat())
                Spacer(Modifier.height(Spacing.xs))
                Text(v.capacity.freeOfTotal(), color = colors.textSecondary, style = type.footnote)
            }
        }
    }
}
