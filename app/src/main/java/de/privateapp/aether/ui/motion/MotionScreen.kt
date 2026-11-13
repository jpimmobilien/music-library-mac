package de.privateapp.aether.ui.motion

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import de.privateapp.aether.AppGraph
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.HeroValue
import de.privateapp.aether.design.MetricTile
import de.privateapp.aether.design.Notice
import de.privateapp.aether.design.Panel
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.design.StatusBadge
import de.privateapp.aether.design.Tone
import de.privateapp.aether.model.Fmt
import de.privateapp.aether.model.Reading
import de.privateapp.aether.model.motion.ClimbSource
import de.privateapp.aether.model.motion.MotionFormat
import de.privateapp.aether.ui.common.ScreenList
import de.privateapp.aether.ui.common.SubpageHeader

/**
 * Bewegung (Bereich „Gerät“): Geschwindigkeit, Höhe, Kompass, Satelliten und eine Messung seit dem Öffnen.
 * Hierarchie wie bei Kompass und Fitness auf dem iPhone: eine große Hauptzahl, darunter vier Kacheln, dann die
 * Details je Thema. Jeder Wert kommt aus einer benannten Quelle – fehlt er, steht dort warum.
 */
@Composable
fun MotionScreen(graph: AppGraph, insets: PaddingValues, onBack: () -> Unit) {
    val context = graph.context
    val vm: MotionViewModel = viewModel { MotionViewModel(context) }
    val state by vm.state.collectAsStateWithLifecycle()
    // Zurück aus den Einstellungen (Freigabe erteilt, Standort eingeschaltet) → sofort neu prüfen.
    LifecycleResumeEffect(vm) {
        vm.refreshAccess()
        onPauseOrDispose { }
    }
    var showCoordinates by rememberSaveable { mutableStateOf(false) }
    val gpsUsable = state.phase != GpsPhase.BLOCKED

    ScreenList(insets, reselect = 0) {
        item(key = "header") { SubpageHeader("Bewegung", onBack) }
        if (gpsUsable) {
            item(key = "speed") { SpeedHero(state) }
            item(key = "tiles") { MetricTiles(state) }
        } else {
            item(key = "access") { LocationAccessPanel(state.access, onAccessChanged = vm::refreshAccess) }
        }
        item(key = "compass") { CompassPanel(vm) }
        item(key = "altitude") { AltitudePanel(state) }
        if (gpsUsable) item(key = "satellites") { SatellitesPanel(state) }
        if (gpsUsable || state.session.climbSource == ClimbSource.BAROMETER) {
            item(key = "session") { SessionPanel(state, gpsUsable, onReset = vm::resetSession) }
        }
        if (gpsUsable) {
            item(key = "position") { PositionPanel(state, showCoordinates, onToggle = { showCoordinates = !showCoordinates }) }
        }
        item(key = "privacy") {
            Notice(
                title = "Bleibt auf diesem Gerät",
                message = "GPS und Sensoren laufen nur, solange diese Seite geöffnet ist – nie im Hintergrund. ORBIT hat keine Internet-Berechtigung; Position und Messwerte werden weder gespeichert noch gesendet.",
                tone = Tone.NEUTRAL,
                icon = AetherIcons.Shield,
            )
        }
    }
}

/** Hauptzahl: Geschwindigkeit über Grund laut GPS. */
@Composable
private fun SpeedHero(state: MotionState) {
    val colors = Aether.colors
    val type = Aether.type
    val speed = (state.speed as? Reading.Value)?.value
    Panel {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            when (state.phase) {
                GpsPhase.LIVE -> StatusBadge("Live · GPS", Tone.SUCCESS, icon = AetherIcons.Satellite)
                GpsPhase.STALE -> StatusBadge("Signal verloren", Tone.WARNING, icon = AetherIcons.Warning)
                else -> StatusBadge("Position wird gesucht …", Tone.INFO, icon = AetherIcons.Satellite)
            }
            Spacer(Modifier.weight(1f))
            if (state.fix?.isMock == true) StatusBadge("Simuliert", Tone.WARNING)
        }
        Spacer(Modifier.height(Spacing.l))
        Text("Geschwindigkeit", color = colors.textSecondary, style = type.subhead)
        HeroValue(
            value = speed?.let { MotionFormat.kmhNumber(it.kmh) } ?: "–",
            unit = "km/h",
            valueColor = if (speed == null) colors.textTertiary else Color.Unspecified,
            spokenValue = speed?.let { "Geschwindigkeit ${MotionFormat.kmhNumber(it.kmh)} Kilometer pro Stunde" }
                ?: "Geschwindigkeit: ${(state.speed as Reading.Unavailable).missing.text}",
        )
        val detail = when {
            speed != null -> listOfNotNull(
                speed.accuracyKmh?.let { MotionFormat.kmhAccuracy(it) },
                if (speed.withinNoise) "Stillstand innerhalb der Messgenauigkeit" else null,
            ).joinToString(" · ").ifEmpty { "vom GPS-Empfänger gemeldet" }
            state.phase == GpsPhase.SEARCHING -> searchingText(state)
            state.phase == GpsPhase.STALE -> "Letzte Position ${MotionFormat.age(state.fixAgeMillis ?: 0L)}"
            else -> (state.speed as Reading.Unavailable).missing.text
        }
        Text(detail, color = colors.textSecondary, style = type.footnote)
        if (state.phase != GpsPhase.LIVE) {
            Spacer(Modifier.height(Spacing.xs))
            Text(
                "Unter freiem Himmel findet GPS die Position am schnellsten. In Gebäuden, Tunneln und Tiefgaragen reicht das Signal oft nicht.",
                color = colors.textTertiary,
                style = type.footnote,
            )
        }
    }
}

private fun searchingText(state: MotionState): String {
    val s = state.satellites.summary
    val since = state.searchingForMillis?.let { " · seit ${MotionFormat.stopwatch(it)}" }.orEmpty()
    return if (s == null) "GPS-Empfänger startet$since" else "${Fmt.count(s.received)} Satelliten empfangen, ${Fmt.count(s.used)} genutzt$since"
}

private data class Tile(val icon: ImageVector, val label: String, val value: String, val unit: String?, val caption: String?, val muted: Boolean)

/** Vier Kacheln: Höhe, Kurs, Genauigkeit, Satelliten – gleich hoch, zwei je Zeile. */
@Composable
private fun MetricTiles(state: MotionState) {
    val altitude = run {
        val msl = (state.msl as? Reading.Value)?.value
        val ellipsoid = (state.ellipsoid as? Reading.Value)?.value
        when {
            msl != null -> Tile(AetherIcons.Mountain, "Höhe", MotionFormat.metersNumber(msl.meters), "m", "über dem Meeresspiegel", muted = false)
            ellipsoid != null -> Tile(AetherIcons.Mountain, "Höhe", MotionFormat.metersNumber(ellipsoid.meters), "m", "über dem Ellipsoid (GPS)", muted = false)
            else -> Tile(AetherIcons.Mountain, "Höhe", (state.ellipsoid as Reading.Unavailable).missing.text, null, null, muted = true)
        }
    }
    val course = when (val c = state.course) {
        is Reading.Value -> Tile(AetherIcons.Compass, "Kurs", MotionFormat.degrees(c.value.degrees.toDouble()), c.value.cardinal.short, "Bewegungsrichtung", muted = false)
        is Reading.Unavailable -> Tile(AetherIcons.Compass, "Kurs", c.missing.text, null, "Bewegungsrichtung", muted = true)
    }
    val accuracy = when (val a = state.horizontalAccuracy) {
        is Reading.Value -> {
            val text = MotionFormat.metersAccuracy(a.value)
            Tile(AetherIcons.LocationPin, "Genauigkeit", text.removeSuffix("${Fmt.NBSP}m"), "m", "Radius mit 68 % Sicherheit", muted = false)
        }
        is Reading.Unavailable -> Tile(AetherIcons.LocationPin, "Genauigkeit", a.missing.text, null, null, muted = true)
    }
    val satellites = state.satellites.summary.let { s ->
        if (s == null) {
            Tile(AetherIcons.Satellite, "Satelliten", "Wird gelesen …", null, null, muted = true)
        } else {
            Tile(AetherIcons.Satellite, "Satelliten", Fmt.count(s.used), "von ${Fmt.count(s.received)}", "für die Position genutzt", muted = false)
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.m)) {
        listOf(altitude, course, accuracy, satellites).chunked(2).forEach { row ->
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(Spacing.m)) {
                row.forEach { t ->
                    MetricTile(
                        icon = t.icon,
                        label = t.label,
                        value = t.value,
                        unit = t.unit,
                        caption = t.caption,
                        muted = t.muted,
                        modifier = Modifier.weight(1f).fillMaxHeight(),
                    )
                }
            }
        }
    }
}
