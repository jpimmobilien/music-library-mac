package de.privateapp.aether.model.device

import de.privateapp.aether.model.Missing
import de.privateapp.aether.model.Reading
import de.privateapp.aether.model.reported
import de.privateapp.aether.model.unavailable
import kotlin.math.roundToInt

/** Ladezustand (`BatteryManager.BATTERY_STATUS_*`). */
enum class ChargeStatus(val androidValue: Int, val label: String) {
    CHARGING(2, "Lädt"),
    DISCHARGING(3, "Entlädt"),
    NOT_CHARGING(4, "Lädt nicht"),
    FULL(5, "Voll"),
    UNKNOWN(1, "Unbekannt"),
    ;

    companion object {
        fun fromAndroid(value: Int): ChargeStatus = entries.firstOrNull { it.androidValue == value } ?: UNKNOWN
    }
}

/** Stromquelle (`BatteryManager.BATTERY_PLUGGED_*`, Bitmaske). */
enum class PowerSource(val androidBit: Int, val label: String) {
    AC(1, "Netzteil"),
    USB(2, "USB"),
    WIRELESS(4, "Kabellos"),
    DOCK(8, "Dockingstation"),
    ;

    companion object {
        /** Alle gesetzten Quellen; leer = nicht angeschlossen. Unbekannte Bits werden ignoriert. */
        fun fromAndroid(bits: Int): Set<PowerSource> = entries.filter { bits and it.androidBit != 0 }.toSet()
    }
}

/** Akkuzustand laut Android (`BatteryManager.BATTERY_HEALTH_*`). Android meldet nur diese Stufen – keinen Prozentwert. */
enum class BatteryHealth(val androidValue: Int, val label: String) {
    GOOD(2, "Gut"),
    OVERHEAT(3, "Überhitzt"),
    DEAD(4, "Defekt"),
    OVER_VOLTAGE(5, "Überspannung"),
    UNSPECIFIED_FAILURE(6, "Fehler (nicht näher bezeichnet)"),
    COLD(7, "Zu kalt"),
    ;

    /** `true` für Zustände, die Aufmerksamkeit verdienen. */
    val isProblem: Boolean get() = this != GOOD

    companion object {
        /** `null` für „unbekannt“ (1) und unbekannte Werte. */
        fun fromAndroid(value: Int): BatteryHealth? = entries.firstOrNull { it.androidValue == value }
    }
}

/** Momentaufnahme des Akkus. */
data class BatterySnapshot(
    val present: Boolean,
    val level: Reading<Int>,
    val status: ChargeStatus,
    val sources: Set<PowerSource>,
    val health: Reading<BatteryHealth>,
    /** Akku-Temperatur in °C. */
    val temperatureCelsius: Reading<Double>,
    /** Akku-Spannung in Volt. */
    val voltage: Reading<Double>,
    val technology: Reading<String>,
    /** Ladezyklen (Android 14+, nur wenn das Gerät sie meldet). */
    val cycleCount: Reading<Int>,
    val observedAtMillis: Long,
) {
    val isPluggedIn: Boolean get() = sources.isNotEmpty()
}

/**
 * Deutung der Rohwerte aus `ACTION_BATTERY_CHANGED`. Alles, was nicht eindeutig ist, wird nicht angezeigt.
 */
object BatteryInterpreter {
    const val SOURCE = "Akku (BatteryManager)"
    const val TEMPERATURE_SOURCE = "Temperatursensor des Akkus (BatteryManager)"

    /** Plausibler Bereich für eine Akku-Temperatur. Außerhalb davon liegt ein Mess- oder Meldefehler vor. */
    val plausibleCelsius = -40.0..100.0

    /** Akkustand in Prozent aus `EXTRA_LEVEL` und `EXTRA_SCALE`. */
    fun level(level: Int, scale: Int): Reading<Int> {
        if (level < 0 || scale <= 0) return unavailable(Missing.NotReported)
        if (level > scale) return unavailable(Missing.Implausible("$level von $scale"))
        return reported((level * 100.0 / scale).roundToInt().coerceIn(0, 100), SOURCE)
    }

    /**
     * `EXTRA_TEMPERATURE` ist in Zehntelgrad Celsius angegeben (315 = 31,5 °C). Fehlt der Wert
     * ([Int.MIN_VALUE] als Vorgabe beim Auslesen), meldet das Gerät keine Temperatur.
     */
    fun temperature(tenthsCelsius: Int): Reading<Double> {
        if (tenthsCelsius == Int.MIN_VALUE) return unavailable(Missing.NotReported)
        val celsius = tenthsCelsius / 10.0
        if (celsius !in plausibleCelsius) return unavailable(Missing.Implausible("$tenthsCelsius Zehntelgrad"))
        return reported(celsius, TEMPERATURE_SOURCE)
    }

    /**
     * `EXTRA_VOLTAGE` ist laut Android in Millivolt angegeben. Einige Geräte melden abweichend Mikrovolt;
     * das ist an der Größenordnung eindeutig erkennbar (ein Lithium-Akku liegt bei 2,5–5,5 V). Ganze Volt
     * (z. B. „4“) wären zu ungenau und gelten wie alles andere als nicht plausibel.
     */
    fun voltage(raw: Int): Reading<Double> {
        if (raw == Int.MIN_VALUE || raw <= 0) return unavailable(Missing.NotReported)
        val volts = when (raw) {
            in 2_500..5_500 -> raw / 1000.0
            in 2_500_000..5_500_000 -> raw / 1_000_000.0
            else -> return unavailable(Missing.Implausible("$raw"))
        }
        return reported(volts, SOURCE)
    }

    /**
     * Ladezyklen (`EXTRA_CYCLE_COUNT`, Android 14+). [raw] = `null`, wenn Android den Wert auf dieser Version
     * noch nicht kennt; ein negativer Wert bzw. die Vorgabe beim Auslesen bedeutet „nicht gemeldet“.
     */
    fun cycleCount(raw: Int?): Reading<Int> = when {
        raw == null -> unavailable(Missing.RequiresAndroid(34, "14"))
        raw < 0 || raw == Int.MIN_VALUE -> unavailable(Missing.NotReported)
        raw > 20_000 -> unavailable(Missing.Implausible("$raw"))
        else -> reported(raw, SOURCE)
    }

    fun health(raw: Int): Reading<BatteryHealth> {
        val h = BatteryHealth.fromAndroid(raw) ?: return unavailable(Missing.NotReported)
        return reported(h, SOURCE)
    }

    fun technology(raw: String?): Reading<String> =
        if (raw.isNullOrBlank()) unavailable(Missing.NotReported) else reported(raw.trim(), SOURCE)
}
