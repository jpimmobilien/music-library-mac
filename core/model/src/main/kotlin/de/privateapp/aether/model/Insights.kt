package de.privateapp.aether.model

import de.privateapp.aether.model.device.BatterySnapshot
import de.privateapp.aether.model.device.ThermalLevel
import de.privateapp.aether.model.device.ThermalSnapshot
import de.privateapp.aether.model.storage.MountState
import de.privateapp.aether.model.storage.StorageOverview
import de.privateapp.aether.model.storage.VolumeKind

/** Gewicht eines Hinweises. */
enum class Severity { INFO, ATTENTION, CRITICAL }

/** Wohin ein Hinweis führt. */
enum class InsightTarget { STORAGE, DEVICE, FILES }

/** Ein Hinweis für die Übersicht – ausschließlich aus tatsächlich gelesenen Werten. */
data class Insight(
    /** Stabile Kennung (für Listen). */
    val id: String,
    val title: String,
    val message: String,
    val severity: Severity,
    val target: InsightTarget,
)

/**
 * Hinweise der Übersicht. Regeln: nur echte, aktuelle Befunde; sachliche Sprache ohne Druck („Bereinigen Sie
 * jetzt!“ gibt es nicht); keine Behauptungen über Dinge, die ORBIT nicht wissen kann.
 */
object Insights {
    /** Ab diesem Anteil wird ein fast voller interner Speicher erwähnt. */
    const val NEARLY_FULL = 0.90

    /** Ab diesem Anteil gilt er als kritisch voll. */
    const val CRITICALLY_FULL = 0.97

    fun from(storage: StorageOverview?, battery: BatterySnapshot?, thermal: ThermalSnapshot?): List<Insight> {
        val out = mutableListOf<Insight>()

        storage?.internal?.capacity?.valueOrNull?.let { c ->
            val used = c.usedFraction
            if (used >= NEARLY_FULL) {
                out += Insight(
                    id = "internal-full",
                    title = "Interner Speicher zu ${Fmt.percent(used)} belegt",
                    message = "Noch ${ByteFormat.format(c.freeBytes)} frei. Android braucht freien Platz, etwa für System-Updates.",
                    severity = if (used >= CRITICALLY_FULL) Severity.CRITICAL else Severity.ATTENTION,
                    target = InsightTarget.STORAGE,
                )
            }
        }

        storage?.external.orEmpty().forEach { v ->
            val name = v.description
            val what = when (v.kind) {
                VolumeKind.SD_CARD -> "SD-Karte"
                VolumeKind.USB -> "USB-Speicher"
                else -> "Wechseldatenträger"
            }
            when {
                v.state == MountState.MOUNTED_READ_ONLY -> out += Insight(
                    id = "ro-${v.id}",
                    title = "$what nur lesbar",
                    message = "Android hat „$name“ schreibgeschützt eingebunden. Dateien lassen sich lesen, aber nicht ändern.",
                    severity = Severity.ATTENTION,
                    target = InsightTarget.STORAGE,
                )
                v.state == MountState.UNMOUNTABLE || v.state == MountState.NO_FILESYSTEM -> out += Insight(
                    id = "bad-${v.id}",
                    title = "$what nicht lesbar",
                    message = "Android kann das Dateisystem von „$name“ nicht lesen.",
                    severity = Severity.ATTENTION,
                    target = InsightTarget.STORAGE,
                )
                v.state == MountState.MOUNTED -> {
                    val c = v.capacity.valueOrNull
                    out += Insight(
                        id = "ext-${v.id}",
                        title = "$what erkannt",
                        message = if (c != null) "„$name“ · ${ByteFormat.format(c.freeBytes)} frei von ${ByteFormat.format(c.totalBytes)}" else "„$name“ ist eingebunden.",
                        severity = Severity.INFO,
                        target = InsightTarget.STORAGE,
                    )
                }
                else -> Unit
            }
        }

        thermal?.level?.valueOrNull?.let { level ->
            if (level.isElevated) {
                out += Insight(
                    id = "thermal",
                    title = "Gerät drosselt wegen Wärme",
                    message = "Thermalstatus „${level.label}“: ${level.meaning}",
                    severity = if (level >= ThermalLevel.CRITICAL) Severity.CRITICAL else Severity.ATTENTION,
                    target = InsightTarget.DEVICE,
                )
            }
        }

        battery?.health?.valueOrNull?.let { h ->
            if (h.isProblem) {
                out += Insight(
                    id = "battery-health",
                    title = "Akkuzustand: ${h.label}",
                    message = "Android meldet für den Akku den Zustand „${h.label}“.",
                    severity = Severity.ATTENTION,
                    target = InsightTarget.DEVICE,
                )
            }
        }

        // Wichtigstes zuerst; innerhalb gleicher Stufe in der Reihenfolge oben.
        return out.sortedByDescending { it.severity.ordinal }
    }
}
