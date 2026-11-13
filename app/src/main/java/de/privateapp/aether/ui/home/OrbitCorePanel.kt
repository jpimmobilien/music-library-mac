package de.privateapp.aether.ui.home

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import de.privateapp.aether.AppGraph
import de.privateapp.aether.design.Aether
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.BatteryLiquid
import de.privateapp.aether.design.Orbit
import de.privateapp.aether.design.OrbitRings
import de.privateapp.aether.design.OrbitTrack
import de.privateapp.aether.design.Panel
import de.privateapp.aether.design.PanelHeader
import de.privateapp.aether.design.Radii
import de.privateapp.aether.design.RollingText
import de.privateapp.aether.design.Spacing
import de.privateapp.aether.design.Tone
import de.privateapp.aether.design.rememberOrbitHaptics
import de.privateapp.aether.model.ByteFormat
import de.privateapp.aether.model.Fmt
import de.privateapp.aether.model.orbit.OrbitBasis
import de.privateapp.aether.model.orbit.OrbitRing
import de.privateapp.aether.model.orbit.OrbitRingState

/*
 * ORBIT Core (Android): Kern mit fünf Bahnen – Arbeitsspeicher, Speicher, Thermik (Reserve bis zur Drosselung),
 * Netzwerk (bezogen auf die Spitze der letzten 5 Minuten), Akku. Jede Bahn zeigt einen gemessenen Anteil; ohne Wert
 * bleibt sie gestrichelt. CPU- und GPU-Auslastung gibt Android normalen Apps nicht frei – das steht im Panel, statt
 * Werte zu erfinden. Ein Antippen einer Zeile verwandelt sie in eine Detailkarte (Morphing Card).
 */

@Composable
fun OrbitCorePanel(graph: AppGraph, onOpenDevice: () -> Unit, onOpenStorage: () -> Unit, modifier: Modifier = Modifier) {
    val vm: OrbitCoreViewModel = viewModel { OrbitCoreViewModel(graph) }
    val state by vm.state.collectAsStateWithLifecycle()
    val colors = Aether.colors
    val type = Aether.type
    val haptics = rememberOrbitHaptics()
    var expanded by rememberSaveable { mutableStateOf<String?>(null) }

    Panel(modifier.animateContentSize(Aether.motion.gentleSpring())) {
        PanelHeader(icon = AetherIcons.Pulse, title = "ORBIT Core", subtitle = "Jede Bahn ein gemessener Anteil", tone = Tone.ACCENT)
        Spacer(Modifier.height(Spacing.m))
        // Kern oben (zentriert), Legende darunter in voller Breite – so bleiben die Namen auch auf schmalen Telefonen lesbar
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            Box(Modifier.size(176.dp), contentAlignment = Alignment.Center) {
                OrbitRings(
                    tracks = state.rings.map { OrbitTrack(if (it.basis == OrbitBasis.UNAVAILABLE) null else it.arc, ringColor(it.ring, it.fraction)) },
                    modifier = Modifier
                        .size(176.dp)
                        .semantics { contentDescription = ringsDescription(state) },
                    flowIndex = OrbitRing.entries.indexOf(OrbitRing.NETWORK),
                    flow = state.flow,
                )
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    val memory = state.ring(OrbitRing.MEMORY).fraction
                    RollingText(memory?.let { Fmt.percent(it.toDouble()) } ?: "–", style = type.numberSmall, color = Orbit.tones.onCore)
                    Text("RAM", style = type.caption, color = Orbit.tones.onCore.copy(alpha = 0.85f))
                }
            }
        }
        Spacer(Modifier.height(Spacing.m))
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            for (ring in OrbitRing.entries) {
                OrbitLegendLine(state.ring(ring), valueText(state, ring), expanded == ring.name) {
                    haptics.tick()
                    expanded = if (expanded == ring.name) null else ring.name
                }
            }
        }
        val open = expanded?.let { name -> OrbitRing.entries.firstOrNull { it.name == name } }
        AnimatedVisibility(
            visible = open != null,
            enter = fadeIn(Aether.motion.fade()) + expandVertically(Aether.motion.gentleSpring()),
            exit = fadeOut(Aether.motion.fade()) + shrinkVertically(Aether.motion.gentleSpring()),
        ) {
            if (open != null) {
                OrbitDetailCard(open, state, onOpenDevice = onOpenDevice, onOpenStorage = onOpenStorage)
            }
        }
        Spacer(Modifier.height(Spacing.s))
        Text(
            "CPU- und GPU-Auslastung gibt Android normalen Apps nicht frei – ORBIT schätzt sie nicht.",
            style = type.footnote,
            color = colors.textTertiary,
        )
    }
}

/**
 * Farbe einer Bahn nach ORBIT-Bedeutung. Thermik: Saphir im Normalbereich; Orange erst ab 60 % genutzter Reserve,
 * Rot ab 85 % bzw. an der Drosselschwelle – Warnfarben nur für erhöhte Werte, nicht als Dekoration.
 */
@Composable
private fun ringColor(ring: OrbitRing, fraction: Float? = null): Color {
    val tones = Orbit.tones
    val colors = Aether.colors
    return when (ring) {
        OrbitRing.MEMORY -> tones.smart
        OrbitRing.STORAGE -> tones.system
        OrbitRing.THERMAL -> when {
            (fraction ?: 0f) >= 0.85f -> colors.critical
            (fraction ?: 0f) >= 0.6f -> colors.warning
            else -> tones.sapphire
        }
        OrbitRing.NETWORK -> tones.data
        OrbitRing.BATTERY -> colors.success
    }
}

private fun ringIcon(ring: OrbitRing): ImageVector = when (ring) {
    OrbitRing.MEMORY -> AetherIcons.Memory
    OrbitRing.STORAGE -> AetherIcons.StorageRing
    OrbitRing.THERMAL -> AetherIcons.Thermometer
    OrbitRing.NETWORK -> AetherIcons.Pulse
    OrbitRing.BATTERY -> AetherIcons.Battery
}

private fun valueText(state: OrbitCoreState, ring: OrbitRing): String {
    val r = state.ring(ring)
    if (r.basis == OrbitBasis.UNAVAILABLE) return "–"
    return when (ring) {
        OrbitRing.NETWORK -> state.sample.networkRate?.let { ByteFormat.format(it.toLong()) + "/s" } ?: "–"
        OrbitRing.BATTERY -> state.batteryPercent?.let { Fmt.percentInt(it) } ?: "–"
        else -> Fmt.percent((r.fraction ?: 0f).toDouble())
    }
}

private fun ringsDescription(state: OrbitCoreState): String =
    state.rings.joinToString(", ") { r ->
        r.ring.label + " " + (if (r.basis == OrbitBasis.UNAVAILABLE) "nicht verfügbar" else valueText(state, r.ring))
    }

@Composable
private fun OrbitLegendLine(ring: OrbitRingState, value: String, expanded: Boolean, onClick: () -> Unit) {
    val colors = Aether.colors
    val type = Aether.type
    val color = ringColor(ring.ring, ring.fraction)
    val available = ring.basis != OrbitBasis.UNAVAILABLE
    val chevron by animateFloatAsState(if (expanded) 180f else 0f, Aether.motion.standard(), label = "chevron")
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radii.small))
            .background(if (expanded) colors.fill else Color.Transparent)
            .clickable(role = Role.Button, onClickLabel = if (expanded) "Details ausblenden" else "Details zeigen", onClick = onClick)
            .padding(horizontal = 8.dp, vertical = 7.dp)
            .semantics { stateDescription = if (expanded) "Details offen" else "Details geschlossen" },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(9.dp)
                .clip(CircleShape)
                .then(if (available) Modifier.background(color) else Modifier.border(1.dp, colors.textTertiary, CircleShape)),
        )
        Spacer(Modifier.width(8.dp))
        Text(ring.ring.label, style = type.subhead, color = colors.text, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        Text(value, style = type.subhead, color = if (available) colors.textSecondary else colors.textTertiary, maxLines = 1)
        Spacer(Modifier.width(4.dp))
        Icon(AetherIcons.ChevronDown, contentDescription = null, tint = colors.textTertiary, modifier = Modifier.size(14.dp).rotate(chevron))
    }
}

/** Detailkarte einer Bahn: Bedeutung und Grundlage, dazu die passende Visualisierung aus echten Werten. */
@Composable
private fun OrbitDetailCard(ring: OrbitRing, state: OrbitCoreState, onOpenDevice: () -> Unit, onOpenStorage: () -> Unit) {
    val colors = Aether.colors
    val type = Aether.type
    val r = state.ring(ring)
    Column(
        Modifier
            .fillMaxWidth()
            .padding(top = Spacing.m)
            .clip(RoundedCornerShape(Radii.control))
            .background(colors.fill)
            .border(1.dp, ringColor(ring, r.fraction).copy(alpha = 0.35f), RoundedCornerShape(Radii.control))
            .padding(Spacing.m),
        verticalArrangement = Arrangement.spacedBy(Spacing.s),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(ringIcon(ring), contentDescription = null, tint = ringColor(ring, r.fraction), modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text(ring.label, style = type.bodyStrong, color = colors.text)
        }
        when (ring) {
            OrbitRing.MEMORY -> {
                val m = state.sample.memory
                if (m != null) {
                    MemoryLayers(m.totalBytes, m.availableBytes, m.thresholdBytes)
                    Text(
                        "${ByteFormat.format(m.totalBytes - m.availableBytes)} belegt · ${ByteFormat.format(m.availableBytes)} verfügbar" +
                            (if (m.low) " · Android meldet wenig Speicher" else ""),
                        style = type.footnote, color = colors.textSecondary,
                    )
                }
            }
            OrbitRing.BATTERY -> {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    BatteryLiquid(state.batteryPercent?.let { it / 100f }, state.charging, colors.success)
                    Spacer(Modifier.width(Spacing.m))
                    Text(
                        listOfNotNull(
                            state.batteryPercent?.let { Fmt.percentInt(it) },
                            if (state.charging) "lädt" else null,
                            state.batteryTemperature?.let { Fmt.celsius(it) },
                        ).joinToString(" · ").ifEmpty { "Kein Wert" },
                        style = type.subhead, color = colors.textSecondary,
                    )
                }
            }
            OrbitRing.THERMAL -> ThermalGauge(r.fraction, state.thermalLabel)
            else -> {}
        }
        Text(basisText(ring, r), style = type.footnote, color = colors.textTertiary)
        val target = when (ring) {
            OrbitRing.STORAGE -> "Speicher öffnen" to onOpenStorage
            OrbitRing.NETWORK -> null
            else -> "Gerät öffnen" to onOpenDevice
        }
        if (target != null) {
            Text(
                target.first,
                style = type.bodyStrong,
                color = colors.accent,
                modifier = Modifier.clip(RoundedCornerShape(Radii.small)).clickable(role = Role.Button, onClick = target.second).padding(vertical = 4.dp),
            )
        }
    }
}

private fun basisText(ring: OrbitRing, r: OrbitRingState): String {
    if (r.basis == OrbitBasis.UNAVAILABLE) {
        return when (ring) {
            OrbitRing.THERMAL -> "Dieses Gerät meldet keine Thermal-Reserve (PowerManager) – die Bahn bleibt leer."
            OrbitRing.NETWORK -> "Noch kein Wert (zweite Messung steht aus) oder das Gerät meldet keine Netzwerkzähler."
            OrbitRing.BATTERY -> "Kein Akku oder Android meldet keinen Ladestand."
            else -> "Noch kein Wert."
        }
    }
    return when (ring) {
        OrbitRing.MEMORY -> "Belegter Anteil des Arbeitsspeichers (ActivityManager). Die Linie markiert, ab wann Android Apps beendet."
        OrbitRing.STORAGE -> "Belegter Anteil des internen Speichers."
        OrbitRing.THERMAL -> "Genutzter Anteil der thermischen Reserve bis zur starken Drosselung (Android-Prognose)."
        OrbitRing.NETWORK -> "Datenrate aller Verbindungen (TrafficStats), bezogen auf die Spitze der letzten 5 Minuten – das Netz hat keinen festen Höchstwert."
        OrbitRing.BATTERY -> "Ladestand, wie Android ihn meldet. Die Oberfläche bewegt sich nur, während das Gerät wirklich lädt."
    }
}

/** „Memory Layers“: belegt / verfügbar als Schichten, dazu die Schwelle, ab der Android Apps beendet. */
@Composable
private fun MemoryLayers(total: Long, available: Long, threshold: Long) {
    val colors = Aether.colors
    val tones = Orbit.tones
    val used = (total - available).coerceAtLeast(0L)
    val usedShare by animateFloatAsState(used.toFloat() / total, Aether.motion.standard(600), label = "memUsed")
    val thresholdShare = (threshold.toFloat() / total).coerceIn(0f, 1f)
    Canvas(Modifier.fillMaxWidth().height(28.dp)) {
        val r = CornerRadius(8.dp.toPx(), 8.dp.toPx())
        drawRoundRect(colors.fill, cornerRadius = r)
        val depth = 4.dp.toPx()
        // hintere Schicht (verfügbar), vordere Schicht (belegt) – leicht versetzt wie gestapelte Glasplatten
        drawRoundRect(tones.smart.copy(alpha = 0.22f), topLeft = Offset(depth, 0f), size = Size(size.width - depth, size.height - depth), cornerRadius = r)
        drawRoundRect(tones.smart, topLeft = Offset(0f, depth), size = Size(size.width * usedShare, size.height - depth), cornerRadius = r)
        drawRect(tones.onCore.copy(alpha = 0.25f), topLeft = Offset(0f, depth + 1.dp.toPx()), size = Size(size.width * usedShare, 1.dp.toPx()))
        // Schwelle „wenig Speicher“ (Android): ab hier freier Speicher zu knapp
        val x = size.width * (1f - thresholdShare)
        drawLine(colors.warning, Offset(x, 0f), Offset(x, size.height), strokeWidth = 2.dp.toPx())
    }
}

/** Thermometer-Anzeige aus der echten Thermal-Reserve (0 … 100 %); ohne Wert leer. */
@Composable
private fun ThermalGauge(fraction: Float?, label: String?) {
    val colors = Aether.colors
    val tones = Orbit.tones
    val shown by animateFloatAsState((fraction ?: 0f).coerceIn(0f, 1f), Aether.motion.standard(600), label = "thermal")
    Row(verticalAlignment = Alignment.CenterVertically) {
        Canvas(Modifier.weight(1f).height(14.dp)) {
            val r = CornerRadius(size.height / 2, size.height / 2)
            drawRoundRect(colors.fill, cornerRadius = r)
            if (fraction != null) {
                val c = when {
                    shown >= 0.85f -> colors.critical
                    shown >= 0.6f -> colors.warning
                    else -> tones.data
                }
                drawRoundRect(androidx.compose.ui.graphics.Brush.horizontalGradient(listOf(tones.data, c)), size = Size(size.width * shown, size.height), cornerRadius = r)
            }
            drawRoundRect(colors.hairline, cornerRadius = r, style = Stroke(1.dp.toPx()))
        }
        Spacer(Modifier.width(Spacing.m))
        Text(label ?: "–", style = Aether.type.subhead, color = colors.textSecondary)
    }
}
