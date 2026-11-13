package de.privateapp.aether.ui.motion

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.CapacityBar
import de.privateapp.aether.design.CompassDial
import de.privateapp.aether.design.Hairline
import de.privateapp.aether.design.InfoRow
import de.privateapp.aether.design.Notice
import de.privateapp.aether.design.Panel
import de.privateapp.aether.design.PanelHeader
import de.privateapp.aether.design.PillButton
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.design.Tone
import de.privateapp.aether.model.Fmt
import de.privateapp.aether.model.Missing
import de.privateapp.aether.model.Reading
import de.privateapp.aether.model.ValueKind
import de.privateapp.aether.model.motion.ConstellationCount
import de.privateapp.aether.model.motion.MotionFormat
import de.privateapp.aether.model.motion.NorthReference
import de.privateapp.aether.model.motion.Speed

/**
 * Zeile für einen Messwert mit Herkunft: Wert rechts, darunter klein Genauigkeit ([detail]), Art (berechnet) und
 * Quelle. Ohne Wert steht der Grund in ruhiger Schrift da.
 */
@Composable
private fun <T> MeasuredRow(label: String, reading: Reading<T>, format: (T) -> String, detail: (T) -> String? = { null }) {
    when (reading) {
        is Reading.Value -> InfoRow(
            label,
            format(reading.value),
            caption = listOfNotNull(
                detail(reading.value),
                reading.kind.takeIf { it != ValueKind.REPORTED }?.label,
                reading.source,
            ).joinToString(" · "),
        )
        is Reading.Unavailable -> InfoRow(label, reading.missing.text, muted = true)
    }
}

// ------------------------------------------------------------------------------------------------ Kompass

@Composable
internal fun CompassPanel(vm: MotionViewModel) {
    // Eigener Zustand: Nur diese Karte zeichnet bei jeder Kompassmeldung (≈ 15/s) neu.
    val compass by vm.compass.collectAsStateWithLifecycle()
    val colors = Aether.colors
    val type = Aether.type
    val heading = (compass as? CompassState.Live)?.heading
    Panel {
        PanelHeader(
            AetherIcons.Compass,
            "Kompass",
            subtitle = when (compass) {
                is CompassState.Live -> "Bezogen auf ${heading?.reference?.label}"
                CompassState.Pending -> Missing.Pending.text
                CompassState.NoSensor -> Missing.NotReported.text
            },
            tone = if (compass == CompassState.NoSensor) Tone.NEUTRAL else Tone.ACCENT,
        )
        if (compass == CompassState.NoSensor) {
            Spacer(Modifier.height(Spacing.m))
            Text(
                "Android meldet auf diesem Gerät keinen Magnetfeldsensor – ohne ihn lässt sich keine Himmelsrichtung bestimmen.",
                color = colors.textSecondary,
                style = type.callout,
            )
            return@Panel
        }
        Spacer(Modifier.height(Spacing.l))
        val description = heading?.let {
            "Richtung ${MotionFormat.degrees(it.degrees).removeSuffix("°")} Grad, ${it.cardinal.long}, ${it.reference.label}"
        } ?: "Kompass wird gelesen"
        CompassDial(
            headingDegrees = heading?.degrees,
            description = description,
            modifier = Modifier.fillMaxWidth(0.84f).widthIn(max = 340.dp).align(Alignment.CenterHorizontally),
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(heading?.let { MotionFormat.degrees(it.degrees) } ?: "–", color = colors.text, style = type.numberLarge)
                Text(heading?.cardinal?.long ?: Missing.Pending.text, color = colors.textSecondary, style = type.subhead)
            }
        }
        Spacer(Modifier.height(Spacing.l))
        if (heading != null) {
            InfoRow(
                "Bezug",
                heading.reference.label,
                caption = when (heading.reference) {
                    NorthReference.TRUE -> "Missweisung ${heading.declinationDegrees?.let { MotionFormat.declination(it) }} aus dem Standort eingerechnet (Erdmagnetfeld-Modell von Android)"
                    NorthReference.MAGNETIC -> "Ohne Standortfreigabe keine Umrechnung auf geografisch Nord"
                },
            )
            InfoRow(
                "Geschätzte Genauigkeit",
                heading.accuracyDegrees?.let { MotionFormat.degreesAccuracy(it) } ?: Missing.NotReported.text,
                caption = if (heading.accuracyDegrees != null) "vom Rotationsvektor gemeldet" else null,
                muted = heading.accuracyDegrees == null,
            )
            InfoRow("Kalibrierung", heading.calibration?.label ?: "Noch nicht gemeldet", muted = heading.calibration == null, caption = "laut Magnetfeldsensor")
            InfoRow("Sensoren", heading.sensor.label)
            val calibration = heading.calibration
            if (calibration?.needsCalibration == true) {
                Spacer(Modifier.height(Spacing.s))
                Notice(
                    title = "Kompass kalibrieren",
                    message = "Android meldet die Kalibrierung als „${calibration.label}“. Bewege das Telefon einige Male in Form einer liegenden Acht – mit Abstand zu Magneten, Laptops, Lautsprechern und Metall.",
                    tone = Tone.WARNING,
                )
            }
            if (heading.tilted) {
                Spacer(Modifier.height(Spacing.s))
                Notice(
                    title = "Telefon flacher halten",
                    message = "Der Kompass zeigt, wohin die Oberkante des Telefons zeigt. Steil gehalten wird die Richtung unzuverlässig.",
                    tone = Tone.INFO,
                )
            }
        }
    }
}

// ------------------------------------------------------------------------------------------------ Höhe

@Composable
internal fun AltitudePanel(state: MotionState) {
    Panel {
        PanelHeader(AetherIcons.Mountain, "Höhe", subtitle = "Aus GPS und Luftdruck – mit Quelle")
        Spacer(Modifier.height(Spacing.s))
        MeasuredRow("Über dem Meeresspiegel", state.msl, { MotionFormat.meters(it.meters) }) { a -> a.accuracyMeters?.let { MotionFormat.metersAccuracy(it) } }
        MeasuredRow("Über dem Ellipsoid (WGS 84)", state.ellipsoid, { MotionFormat.meters(it.meters) }) { a -> a.accuracyMeters?.let { MotionFormat.metersAccuracy(it) } }
        Hairline(Modifier.padding(vertical = Spacing.xs))
        MeasuredRow("Druckhöhe", state.pressureAltitude, { MotionFormat.meters(it) })
        MeasuredRow("Luftdruck", state.pressureHPa, { MotionFormat.hectopascal(it) }) { state.barometerName }
        MeasuredRow("Änderung seit Beginn", state.session.altitudeChangeMeters, { MotionFormat.metersChange(it) })
        Spacer(Modifier.height(Spacing.s))
        Notice(
            title = "Drei Höhen, drei Bedeutungen",
            message = "GPS misst über einem mathematischen Erdmodell (Ellipsoid); über dem Meeresspiegel liegt derselbe Punkt in Mitteleuropa etwa 35–50 m tiefer. " +
                "Die Druckhöhe folgt dem Wetter und kann um mehrere hundert Meter abweichen – Höhenänderungen misst das Barometer dagegen auf etwa einen Meter genau.",
            tone = Tone.INFO,
        )
    }
}

// ------------------------------------------------------------------------------------------------ Satelliten

@Composable
internal fun SatellitesPanel(state: MotionState) {
    val s = state.satellites.summary
    Panel {
        PanelHeader(
            AetherIcons.Satellite,
            "Satelliten",
            subtitle = s?.let { "${Fmt.count(it.used)} von ${Fmt.count(it.received)} empfangenen für die Position genutzt" } ?: "Warten auf den GNSS-Empfänger …",
        )
        if (s != null && s.byConstellation.isNotEmpty()) {
            Spacer(Modifier.height(Spacing.m))
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
                s.byConstellation.forEach { ConstellationRow(it) }
            }
            Spacer(Modifier.height(Spacing.s))
        }
        if (s != null) {
            InfoRow(
                "Stärkstes Signal",
                s.strongestCn0DbHz?.let { MotionFormat.dbHz(it) } ?: "Kein Signal empfangen",
                muted = s.strongestCn0DbHz == null,
                caption = "Träger-Rausch-Verhältnis (C/N0)",
            )
            InfoRow(
                "Mittlere Signalstärke (genutzt)",
                s.meanUsedCn0DbHz?.let { MotionFormat.dbHz(it) } ?: "Noch keine Satelliten genutzt",
                muted = s.meanUsedCn0DbHz == null,
                caption = s.quality?.let { "${it.label} (${it.range}) · berechnet aus den genutzten Satelliten" },
            )
            InfoRow(
                "Frequenzbänder",
                if (s.reportsFrequencies) s.bands.sortedBy { it.ordinal }.joinToString(", ") { it.label }.ifEmpty { "–" } else "Vom Empfänger nicht gemeldet",
                muted = !s.reportsFrequencies,
                caption = when (s.dualFrequency) {
                    true -> "Zweifrequenz-Empfang – robuster zwischen Häusern und unter Bäumen"
                    false -> "ein Frequenzbereich"
                    null -> null
                },
            )
        }
        val ttff = state.satellites.timeToFirstFixMillis
        InfoRow(
            "Zeit bis zur ersten Position",
            when {
                ttff != null -> MotionFormat.seconds(ttff)
                // Position da, aber kein „erste Position“-Ereignis: Der Empfänger lief vermutlich schon (andere App).
                state.fix != null -> "Nicht gemessen"
                else -> "Noch keine Position"
            },
            muted = ttff == null,
            caption = when {
                ttff != null -> "seit dem Einschalten des Empfängers"
                state.fix != null -> "Android hat keinen Startzeitpunkt gemeldet – GPS lief vermutlich bereits für eine andere App"
                else -> null
            },
        )
        InfoRow("GNSS-Empfänger", state.satellites.hardwareName ?: Missing.NotReported.text, muted = state.satellites.hardwareName == null)
    }
}

@Composable
private fun ConstellationRow(c: ConstellationCount) {
    val colors = Aether.colors
    val type = Aether.type
    Row(
        Modifier
            .fillMaxWidth()
            .clearAndSetSemantics { contentDescription = "${c.constellation.label}: ${c.used} von ${c.received} empfangenen Satelliten genutzt" },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(0.4f)) {
            Text(c.constellation.label, color = colors.text, style = type.bodyStrong)
            Text(c.constellation.operator, color = colors.textTertiary, style = type.caption)
        }
        CapacityBar(
            fraction = if (c.received > 0) c.used.toFloat() / c.received else 0f,
            modifier = Modifier.weight(0.42f),
            tone = if (c.used > 0) Tone.ACCENT else Tone.NEUTRAL,
        )
        Spacer(Modifier.width(Spacing.m))
        Text(
            "${c.used}/${c.received}",
            color = colors.textSecondary,
            style = type.numberSmall,
            textAlign = TextAlign.End,
            modifier = Modifier.weight(0.18f),
        )
    }
}

// ------------------------------------------------------------------------------------------------ Messung

@Composable
internal fun SessionPanel(state: MotionState, gpsUsable: Boolean, onReset: () -> Unit) {
    val colors = Aether.colors
    val type = Aether.type
    val st = state.session
    Panel {
        PanelHeader(AetherIcons.RoutePath, "Seit Beginn der Messung", subtitle = "Messdauer ${MotionFormat.stopwatch(st.activeMillis)} · berechnet")
        Spacer(Modifier.height(Spacing.s))
        if (gpsUsable) {
            MeasuredRow("Strecke", st.distanceMeters, { MotionFormat.distance(it) })
            MeasuredRow("Höchstgeschwindigkeit", st.maxSpeed, { MotionFormat.kmh(it.kmh) })
            MeasuredRow("Ø in Bewegung", st.averageMovingSpeedMetersPerSecond, { MotionFormat.kmh(it * Speed.MS_TO_KMH) })
            InfoRow("Zeit in Bewegung", MotionFormat.stopwatch(st.movingMillis), caption = "ab 1,8 km/h und über der Messgenauigkeit")
        }
        MeasuredRow("Anstieg", st.ascentMeters, { MotionFormat.meters(it) })
        MeasuredRow("Abstieg", st.descentMeters, { MotionFormat.meters(it) })
        Spacer(Modifier.height(Spacing.s))
        Text(
            "Gemessen wird nur, solange diese Seite geöffnet ist. Positions- und Höhenrauschen werden herausgefiltert – im Zweifel zählt ORBIT eher zu wenig als zu viel." +
                if (!gpsUsable) " Strecke und Geschwindigkeit brauchen GPS." else "",
            color = colors.textTertiary,
            style = type.footnote,
        )
        Spacer(Modifier.height(Spacing.m))
        PillButton("Zurücksetzen", onClick = onReset, icon = AetherIcons.Refresh, modifier = Modifier.align(Alignment.End))
    }
}

// ------------------------------------------------------------------------------------------------ Position

@Composable
internal fun PositionPanel(state: MotionState, showCoordinates: Boolean, onToggle: () -> Unit) {
    val fix = state.fix
    Panel {
        PanelHeader(AetherIcons.LocationPin, "Position", subtitle = "Wird nicht gespeichert und nicht gesendet")
        Spacer(Modifier.height(Spacing.s))
        when {
            fix == null -> InfoRow("Koordinaten", "Position wird gesucht …", muted = true)
            showCoordinates -> InfoRow(
                "Koordinaten",
                MotionFormat.coordinates(fix.latitude, fix.longitude),
                caption = listOfNotNull(
                    fix.horizontalAccuracyMeters?.let { MotionFormat.metersAccuracy(it) },
                    state.fixAgeMillis?.let { MotionFormat.age(it) },
                ).joinToString(" · "),
            )
            else -> InfoRow("Koordinaten", "Ausgeblendet", muted = true, caption = "Schützt deinen Standort auf Bildschirmfotos")
        }
        if (fix != null) {
            Spacer(Modifier.height(Spacing.s))
            PillButton(
                if (showCoordinates) "Koordinaten ausblenden" else "Koordinaten anzeigen",
                onClick = onToggle,
                icon = if (showCoordinates) AetherIcons.EyeOff else AetherIcons.Eye,
                modifier = Modifier.align(Alignment.End),
            )
        }
        if (fix?.isMock == true) {
            Spacer(Modifier.height(Spacing.s))
            Notice(
                title = "Simulierter Standort",
                message = "Diese Position stammt aus einer App für simulierte Standorte (Entwickleroptionen). Geschwindigkeit, Höhe und Strecke sind dann nicht echt gemessen.",
                tone = Tone.WARNING,
            )
        }
        val accuracy = (state.horizontalAccuracy as? Reading.Value)?.value
        if (accuracy != null && accuracy > 25f) {
            Spacer(Modifier.height(Spacing.s))
            Notice(
                title = "Ungenaue Position",
                message = "Android gibt die Genauigkeit gerade mit ${MotionFormat.metersAccuracy(accuracy)} an. Solche Positionen zählen nicht zur Strecke.",
                tone = Tone.INFO,
            )
        }
    }
}
