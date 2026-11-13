package de.privateapp.aether.ui.common

import androidx.compose.ui.graphics.vector.ImageVector
import de.privateapp.aether.design.AetherIcons
import de.privateapp.aether.design.Tone
import de.privateapp.aether.model.ByteFormat
import de.privateapp.aether.model.Fmt
import de.privateapp.aether.model.Reading
import de.privateapp.aether.model.device.BatterySnapshot
import de.privateapp.aether.model.device.ChargeStatus
import de.privateapp.aether.model.device.ThermalLevel
import de.privateapp.aether.model.storage.Capacity
import de.privateapp.aether.model.storage.MountState
import de.privateapp.aether.model.storage.StorageVolumeInfo
import de.privateapp.aether.model.storage.VolumeKind

/*
 * Übersetzung von Modellwerten in Darstellung (Symbol, Tonalität, Kurztext). Statusfarben nur für echte
 * Zustände; jede Farbe kommt zusammen mit Text und Symbol.
 */

fun VolumeKind.icon(): ImageVector = when (this) {
    VolumeKind.INTERNAL -> AetherIcons.Drive
    VolumeKind.SD_CARD -> AetherIcons.SdCard
    VolumeKind.USB -> AetherIcons.Usb
    VolumeKind.REMOVABLE, VolumeKind.OTHER -> AetherIcons.Drive
}

/** Tonalität der Thermalstufen: normal → Erfolg, leicht → neutral, erhöht/stark → Warnung, ab kritisch → kritisch. */
fun ThermalLevel.tone(): Tone = when (this) {
    ThermalLevel.NONE -> Tone.SUCCESS
    ThermalLevel.LIGHT -> Tone.NEUTRAL
    ThermalLevel.MODERATE, ThermalLevel.SEVERE -> Tone.WARNING
    ThermalLevel.CRITICAL, ThermalLevel.EMERGENCY, ThermalLevel.SHUTDOWN -> Tone.CRITICAL
}

/** Kurzbeschreibung des Zustands eines Speicherorts (für Plaketten), `null` = unauffällig. */
fun StorageVolumeInfo.stateBadge(): Pair<String, Tone>? = when {
    state == MountState.MOUNTED_READ_ONLY -> "Nur lesbar" to Tone.WARNING
    state == MountState.CHECKING -> "Wird geprüft" to Tone.NEUTRAL
    state == MountState.MOUNTED -> null
    state == MountState.UNMOUNTABLE || state == MountState.NO_FILESYSTEM -> "Nicht lesbar" to Tone.CRITICAL
    else -> state.label to Tone.NEUTRAL
}

/** „47,3 GB frei von 128 GB“ bzw. der Grund, warum es keine Angabe gibt. */
fun Reading<Capacity>.freeOfTotal(): String = when (this) {
    is Reading.Value -> "${ByteFormat.format(value.freeBytes)} frei von ${ByteFormat.format(value.totalBytes)}"
    is Reading.Unavailable -> missing.text
}

/** Tonalität für den Akkustand: nur „kritisch“ wird farbig hervorgehoben, sonst Akzent. */
fun BatterySnapshot.levelTone(): Tone {
    val level = (level as? Reading.Value)?.value ?: return Tone.NEUTRAL
    return when {
        status == ChargeStatus.CHARGING || status == ChargeStatus.FULL -> Tone.SUCCESS
        level <= 15 -> Tone.CRITICAL
        else -> Tone.ACCENT
    }
}

/** „Lädt über USB“, „Entlädt“, „Voll, am Netzteil“ … */
fun BatterySnapshot.statusText(): String {
    val src = sources.joinToString(", ") { it.label }
    return when {
        !present -> "Kein Akku erkannt"
        sources.isEmpty() -> status.label
        status == ChargeStatus.CHARGING -> "Lädt über $src"
        else -> "${status.label}, angeschlossen: $src"
    }
}

/** Belegung für TalkBack: „Interner Speicher: 63 Prozent belegt, 47,3 GB frei von 128 GB“. */
fun StorageVolumeInfo.accessibleSummary(): String = when (val c = capacity) {
    is Reading.Value -> "$description: ${Fmt.percent(c.value.usedFraction).replace("%", "Prozent")} belegt, ${capacity.freeOfTotal()}"
    is Reading.Unavailable -> "$description: ${c.missing.text}"
}
