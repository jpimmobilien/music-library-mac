package de.privateapp.aether.ui.device

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.semantics
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import de.privateapp.aether.AppGraph
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.BatteryGlyph
import de.privateapp.aether.design.CapacityBar
import de.privateapp.aether.design.Hairline
import de.privateapp.aether.design.InfoRow
import de.privateapp.aether.design.LevelScale
import de.privateapp.aether.design.NavRow
import de.privateapp.aether.design.Notice
import de.privateapp.aether.design.Panel
import de.privateapp.aether.design.PanelHeader
import de.privateapp.aether.design.ReadingRow
import de.privateapp.aether.design.ScreenTitle
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.design.StatusBadge
import de.privateapp.aether.design.Tone
import de.privateapp.aether.design.ValueWithUnit
import de.privateapp.aether.model.ByteFormat
import de.privateapp.aether.model.Fmt
import de.privateapp.aether.model.Reading
import de.privateapp.aether.model.device.BatterySnapshot
import de.privateapp.aether.model.device.ChargeStatus
import de.privateapp.aether.model.device.DeviceSummary
import de.privateapp.aether.model.device.ThermalLevel
import de.privateapp.aether.model.device.ThermalSnapshot
import de.privateapp.aether.ui.common.ScreenList
import de.privateapp.aether.ui.common.UpdatedAt
import de.privateapp.aether.ui.common.levelTone
import de.privateapp.aether.ui.common.statusText
import de.privateapp.aether.ui.common.tone

/**
 * Gerät: Akku, Temperatur und Thermalstatus, Geräteübersicht, Arbeitsspeicher, Display, Sensoren. Jede Zeile
 * zeigt einen von Android gemeldeten Wert – oder ausdrücklich, dass es ihn auf diesem Gerät nicht gibt.
 */
@Composable
fun DeviceScreen(graph: AppGraph, insets: PaddingValues, reselect: Int, onOpenMotion: () -> Unit) {
    val vm: DeviceViewModel = viewModel { DeviceViewModel(graph) }
    val state by vm.state.collectAsStateWithLifecycle()
    val summary = state.summary

    ScreenList(insets, reselect) {
        item(key = "title") {
            ScreenTitle(
                title = summary?.displayName ?: "Gerät",
                subtitle = summary?.let { "Android ${it.androidRelease} · API ${it.sdkInt}" } ?: "Wird gelesen …",
            )
        }
        item(key = "motion") { MotionEntryPanel(onOpenMotion) }
        item(key = "battery") { BatteryPanel(state.battery) }
        item(key = "thermal") { ThermalPanel(state.thermal, state.battery) }
        if (summary != null) {
            item(key = "device") { DevicePanel(summary) }
            item(key = "memory") { MemoryPanel(summary) }
            item(key = "display") { DisplayPanel(summary) }
            item(key = "sensors") { SensorsPanel(summary) }
        }
    }
}

/** Einstieg in „Bewegung“ – Live-Werte aus GPS, Barometer und Kompass auf einer eigenen Seite. */
@Composable
private fun MotionEntryPanel(onOpen: () -> Unit) {
    Panel {
        NavRow(
            title = "Bewegung",
            subtitle = "Geschwindigkeit, Höhe, Kompass und Satelliten – live",
            icon = AetherIcons.Gauge,
            onClick = onOpen,
        )
    }
}

@Composable
private fun BatteryPanel(b: BatterySnapshot?) {
    val colors = Aether.colors
    Panel {
        PanelHeader(icon = AetherIcons.Battery, title = "Akku", subtitle = b?.statusText() ?: "Wird gelesen …")
        if (b != null && !b.present) {
            Spacer(Modifier.height(Spacing.m))
            Notice(
                title = "Kein Akku erkannt",
                message = "Android meldet, dass kein Akku vorhanden ist (z. B. Emulator oder Gerät am Netzteil ohne Akku). Akkuwerte werden deshalb nicht angezeigt.",
                tone = Tone.NEUTRAL,
            )
        }
        if (b != null && b.present) {
            Spacer(Modifier.height(Spacing.l))
            val level = (b.level as? Reading.Value)?.value
            Row(verticalAlignment = Alignment.CenterVertically) {
                BatteryGlyph(level, charging = b.status == ChargeStatus.CHARGING, tone = b.levelTone())
                Spacer(Modifier.width(Spacing.l))
                if (level != null) {
                    ValueWithUnit(level.toString(), "%", large = true)
                } else {
                    Text((b.level as? Reading.Unavailable)?.missing?.text ?: "–", color = colors.textTertiary, style = Aether.type.callout)
                }
            }
            Spacer(Modifier.height(Spacing.m))
            Column {
                InfoRow("Ladezustand", b.status.label)
                InfoRow("Stromquelle", if (b.sources.isEmpty()) "Nicht angeschlossen" else b.sources.joinToString(", ") { it.label })
                ReadingRow("Zustand", b.health) { it.label }
                ReadingRow("Spannung", b.voltage) { Fmt.volts(it) }
                ReadingRow("Technologie", b.technology) { it }
                ReadingRow("Ladezyklen", b.cycleCount) { Fmt.count(it) }
            }
            val health = (b.health as? Reading.Value)?.value
            if (health != null && health.isProblem) {
                Spacer(Modifier.height(Spacing.s))
                Notice(
                    title = "Akkuzustand: ${health.label}",
                    message = "So meldet Android den Zustand des Akkus. Einen Prozentwert für den Verschleiß stellt Android gewöhnlichen Apps nicht bereit.",
                    tone = Tone.WARNING,
                )
            }
            UpdatedAt(b.observedAtMillis, label = "Letzte Meldung von Android um")
        }
    }
}

@Composable
private fun ThermalPanel(t: ThermalSnapshot?, b: BatterySnapshot?) {
    val colors = Aether.colors
    val type = Aether.type
    val motion = Aether.motion
    Panel {
        PanelHeader(icon = AetherIcons.Thermometer, title = "Temperatur und Thermalstatus", subtitle = "Was Android offiziell meldet")
        Spacer(Modifier.height(Spacing.l))

        // Akku-Temperatur (einzige Temperatur, die Android gewöhnlichen Apps allgemein bereitstellt)
        val temp = b?.temperatureCelsius
        Row(verticalAlignment = Alignment.Bottom) {
            when (temp) {
                is Reading.Value -> ValueWithUnit(Fmt.decimal(temp.value, 1), "°C", large = true)
                is Reading.Unavailable -> Text(temp.missing.text, color = colors.textTertiary, style = type.callout)
                null -> Text("Wird gelesen …", color = colors.textTertiary, style = type.callout)
            }
        }
        Text("Akku-Temperatur · ${BATTERY_TEMP_SOURCE}", color = colors.textSecondary, style = type.footnote)

        Spacer(Modifier.height(Spacing.l))
        Hairline()
        Spacer(Modifier.height(Spacing.l))

        // Thermalstatus – Stufe, Skala, Bedeutung
        val level = (t?.level as? Reading.Value)?.value
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Thermalstatus", color = colors.text, style = type.headline, modifier = Modifier.weight(1f))
            AnimatedContent(
                targetState = level,
                transitionSpec = { fadeIn(motion.fade(220)) togetherWith fadeOut(motion.fade(140)) },
                label = "thermalLevel",
                modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
            ) { l ->
                if (l != null) {
                    StatusBadge(l.label, l.tone(), icon = if (l.isElevated) AetherIcons.Warning else AetherIcons.CheckCircle)
                } else {
                    Text(
                        (t?.level as? Reading.Unavailable)?.missing?.text ?: "Wird gelesen …",
                        color = colors.textTertiary,
                        style = type.footnote,
                    )
                }
            }
        }
        Spacer(Modifier.height(Spacing.m))
        val steps = ThermalLevel.entries
        LevelScale(
            steps = steps.size,
            current = level?.ordinal,
            toneOf = { steps[it].tone() },
            description = if (level != null) "Thermalstatus Stufe ${level.ordinal + 1} von ${steps.size}: ${level.label}" else "Thermalstatus nicht verfügbar",
        )
        Row(Modifier.padding(top = Spacing.xs)) {
            Text(steps.first().label, color = colors.textTertiary, style = type.caption, modifier = Modifier.weight(1f))
            Text(steps.last().label, color = colors.textTertiary, style = type.caption)
        }
        if (level != null) {
            Spacer(Modifier.height(Spacing.s))
            Text(level.meaning, color = colors.textSecondary, style = type.callout)
        }
        if (level != null && level.isCritical) {
            Spacer(Modifier.height(Spacing.m))
            Notice(
                title = "Kritischer Thermalstatus",
                message = "Android meldet „${level.label}“. Rechenintensive Apps schließen, das Gerät nicht laden und an einem kühlen Ort ablegen.",
                tone = Tone.CRITICAL,
            )
        }

        Spacer(Modifier.height(Spacing.s))
        t?.let { snap ->
            ReadingRow("Genutzter thermischer Spielraum", snap.headroom, showSource = false) { it.label }
        }

        Spacer(Modifier.height(Spacing.s))
        Notice(
            title = "Keine Prozessortemperatur",
            message = "Der Thermalstatus ist keine Temperatur, sondern Androids Einstufung der Drosselung. CPU- oder " +
                "GPU-Temperaturen stellt Android gewöhnlichen Apps nicht bereit – ORBIT liest deshalb keine Systemdateien " +
                "aus und zeigt nur, was offiziell gemeldet wird. Der genutzte Spielraum zeigt, wie nah das Gerät der starken " +
                "Drosselung ist (100 % = Schwelle erreicht); er steigt etwa mit der Temperatur, 0 % entspricht aber keiner " +
                "bestimmten Temperatur.",
            tone = Tone.NEUTRAL,
        )
        UpdatedAt(t?.observedAtMillis, label = "Gelesen um")
    }
}

private const val BATTERY_TEMP_SOURCE = "Sensor im Akku (BatteryManager)"

@Composable
private fun DevicePanel(s: DeviceSummary) {
    Panel {
        PanelHeader(icon = AetherIcons.Phone, title = "Gerät", subtitle = "Laut Build-Informationen")
        Spacer(Modifier.height(Spacing.s))
        Column {
            ReadingRow("Gerätename", s.deviceName) { it }
            InfoRow("Hersteller", s.manufacturer.ifBlank { "–" })
            InfoRow("Modell", s.model.ifBlank { "–" }, caption = s.deviceCode.takeIf { it.isNotBlank() }?.let { "Gerätecode „$it“" })
            InfoRow("Android", "${s.androidRelease} (API ${s.sdkInt})")
            ReadingRow("Sicherheitsupdate", s.securityPatch) { Fmt.isoDate(it) }
            ReadingRow("Prozessor", s.socModel) { model ->
                val maker = (s.socManufacturer as? Reading.Value)?.value
                if (maker != null && !model.contains(maker, ignoreCase = true)) "$maker $model" else model
            }
            InfoRow("Architektur", s.supportedAbis.joinToString(", ").ifEmpty { "–" })
            InfoRow("Prozessorkerne", Fmt.count(s.cpuCores), caption = "für Apps verfügbar")
            InfoRow("Seit dem Neustart", Fmt.duration(s.uptimeMillis))
        }
    }
}

@Composable
private fun MemoryPanel(s: DeviceSummary) {
    Panel {
        PanelHeader(icon = AetherIcons.Memory, title = "Arbeitsspeicher", subtitle = "Laut ActivityManager")
        when (val m = s.memory) {
            is Reading.Value -> {
                Spacer(Modifier.height(Spacing.m))
                CapacityBar(m.value.usedFraction.toFloat())
                Spacer(Modifier.height(Spacing.s))
                Column {
                    ReadingRow("Ausstattung", m.value.advertisedBytes) { ByteFormat.format(it) }
                    InfoRow("Für Android nutzbar", ByteFormat.format(m.value.totalBytes))
                    InfoRow("Derzeit verfügbar", ByteFormat.format(m.value.availableBytes))
                    if (m.value.lowMemory) InfoRow("Hinweis", "Android meldet wenig freien Arbeitsspeicher", valueColor = Aether.colors.warning)
                }
            }
            is Reading.Unavailable -> InfoRow("Arbeitsspeicher", m.missing.text, muted = true)
        }
    }
}

@Composable
private fun DisplayPanel(s: DeviceSummary) {
    Panel {
        PanelHeader(icon = AetherIcons.Display, title = "Display", subtitle = "Laut DisplayManager")
        Spacer(Modifier.height(Spacing.s))
        when (val d = s.display) {
            is Reading.Value -> Column {
                InfoRow("Auflösung", "${Fmt.count(d.value.widthPx)} × ${Fmt.count(d.value.heightPx)} Pixel", caption = "im aktuellen Anzeigemodus")
                InfoRow("Bildschirmdichte", "${d.value.densityDpi} dpi", caption = "Anzeigedichte – ändert sich mit der Anzeigegröße")
                InfoRow(
                    "Bildwiederholrate",
                    Fmt.hertz(d.value.refreshRateHz),
                    caption = if (d.value.maxRefreshRateHz > d.value.refreshRateHz + 0.5f) "bis ${Fmt.hertz(d.value.maxRefreshRateHz)} möglich" else null,
                )
                InfoRow("HDR", if (d.value.hdr) "Unterstützt" else "Nicht gemeldet")
            }
            is Reading.Unavailable -> InfoRow("Display", d.missing.text, muted = true)
        }
    }
}

@Composable
private fun SensorsPanel(s: DeviceSummary) {
    Panel {
        PanelHeader(icon = AetherIcons.Sensor, title = "Sensoren", subtitle = "Laut SensorManager")
        Spacer(Modifier.height(Spacing.s))
        ReadingRow("Erkannte Sensoren", s.sensorCount) { Fmt.count(it) }
        Spacer(Modifier.height(Spacing.s))
        Notice(
            title = "Sensor-Explorer folgt",
            message = "Liste aller Sensoren mit Hersteller, Auflösung und Messbereich sowie Live-Werte kommen in Phase 6. " +
                "Ein registrierter Sensor beweist noch nicht, dass die Hardware fehlerfrei arbeitet.",
            tone = Tone.INFO,
        )
    }
}
