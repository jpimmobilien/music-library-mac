package de.privateapp.aether.model

import de.privateapp.aether.model.device.BatterySnapshot
import de.privateapp.aether.model.device.ChargeStatus
import de.privateapp.aether.model.device.ThermalLevel
import de.privateapp.aether.model.storage.Capacity

/**
 * Die Statuszeile der Übersicht – nur aus tatsächlich gelesenen Werten. Fehlt ein Wert, fehlt nur sein Teil;
 * fehlen alle, sagt die Zeile das.
 */
object StatusLine {
    const val SEPARATOR = " · "

    fun build(
        internal: Reading<Capacity>?,
        battery: BatterySnapshot?,
        thermal: Reading<ThermalLevel>?,
    ): String {
        val parts = buildList {
            (internal as? Reading.Value)?.value?.let { add("Speicher zu ${Fmt.percent(it.usedFraction)} belegt") }
            battery?.let { b ->
                val level = (b.level as? Reading.Value)?.value
                if (b.present && level != null) {
                    val suffix = when (b.status) {
                        ChargeStatus.CHARGING -> ", lädt"
                        ChargeStatus.FULL -> ", voll"
                        else -> ""
                    }
                    add("Akku ${Fmt.percentInt(level)}$suffix")
                }
            }
            (thermal as? Reading.Value)?.value?.let { add(thermalPhrase(it)) }
        }
        return when {
            parts.isNotEmpty() -> parts.joinToString(SEPARATOR)
            internal == null && battery == null && thermal == null -> "Gerätedaten werden gelesen …"
            else -> "Keine Gerätedaten verfügbar"
        }
    }

    private fun thermalPhrase(level: ThermalLevel): String = when (level) {
        ThermalLevel.NONE -> "thermisch normal"
        else -> "Wärme: ${level.label.lowercase()}"
    }
}
