package de.privateapp.aether.model.device

import de.privateapp.aether.model.Fmt
import de.privateapp.aether.model.Missing
import de.privateapp.aether.model.Reading
import de.privateapp.aether.model.reported
import de.privateapp.aether.model.unavailable

/**
 * Thermalstatus von Android (`PowerManager.THERMAL_STATUS_*`). Das ist KEINE gemessene Temperatur, sondern
 * die Einstufung des Systems, wie stark es wegen Wärme drosselt. Die Texte geben die Bedeutung der
 * Android-Stufen wieder.
 */
enum class ThermalLevel(val androidValue: Int, val label: String, val meaning: String) {
    NONE(0, "Normal", "Keine Einschränkung wegen Wärme."),
    LIGHT(1, "Leicht erhöht", "Leichte Drosselung – im Alltag nicht spürbar."),
    MODERATE(2, "Erhöht", "Mäßige Drosselung – die Bedienung ist kaum beeinträchtigt."),
    SEVERE(3, "Stark erhöht", "Starke Drosselung – die Leistung ist spürbar verringert."),
    CRITICAL(4, "Kritisch", "Android hat alle Maßnahmen ergriffen, um die Leistungsaufnahme zu senken."),
    EMERGENCY(5, "Notfall", "Wichtige Komponenten werden wegen der Wärme abgeschaltet – Funktionen sind eingeschränkt."),
    SHUTDOWN(6, "Abschalten erforderlich", "Das Gerät muss sofort abgeschaltet werden."),
    ;

    /** Ab hier verdient der Zustand eine deutliche Warnung. */
    val isCritical: Boolean get() = this >= CRITICAL

    /** Ab hier wird spürbar gedrosselt. */
    val isElevated: Boolean get() = this >= MODERATE

    companion object {
        fun fromAndroid(value: Int): ThermalLevel? = entries.firstOrNull { it.androidValue == value }
    }
}

/**
 * Genutzter thermischer Spielraum (`PowerManager.getThermalHeadroom`). 1,0 bedeutet: Das Gerät hat die Schwelle
 * zur starken Drosselung ([ThermalLevel.SEVERE]) erreicht. Laut Android steigt der Wert zwischen 0 und 1 etwa
 * linear mit der Temperatur; 0 entspricht aber keiner bestimmten Temperatur, und über 1 gibt es keine feste
 * Zuordnung zu weiteren Stufen.
 */
data class ThermalHeadroom(
    /** Genutzter Anteil des Spielraums bis zur starken Drosselung (0 … >1). */
    val usedFraction: Float,
    /** Prognose-Horizont in Sekunden (0 = jetzt). */
    val forecastSeconds: Int,
) {
    val overThreshold: Boolean get() = usedFraction >= 1f

    /** „38 % genutzt“ bzw. „Drosselschwelle erreicht“. */
    val label: String
        get() = if (overThreshold) "Drosselschwelle erreicht" else "${Fmt.percent(usedFraction.toDouble())} genutzt"
}

data class ThermalSnapshot(
    val level: Reading<ThermalLevel>,
    val headroom: Reading<ThermalHeadroom>,
    val observedAtMillis: Long,
)

object ThermalInterpreter {
    const val STATUS_SOURCE = "Thermalstatus (PowerManager)"
    const val HEADROOM_SOURCE = "Thermische Reserve (PowerManager)"

    fun level(raw: Int): Reading<ThermalLevel> {
        val level = ThermalLevel.fromAndroid(raw) ?: return unavailable(Missing.Implausible("Stufe $raw"))
        return reported(level, STATUS_SOURCE)
    }

    /**
     * `getThermalHeadroom` liefert `NaN`, wenn das Gerät keine Prognose unterstützt – oder wenn zu häufig
     * gefragt wurde (Android erlaubt etwa eine Abfrage pro Sekunde). Beides wird als „nicht verfügbar“ geführt.
     */
    fun headroom(raw: Float, forecastSeconds: Int): Reading<ThermalHeadroom> = when {
        raw.isNaN() -> unavailable(Missing.NotReported)
        raw < 0f || raw.isInfinite() || raw > 10f -> unavailable(Missing.Implausible(raw.toString()))
        else -> reported(ThermalHeadroom(raw, forecastSeconds), HEADROOM_SOURCE)
    }
}
