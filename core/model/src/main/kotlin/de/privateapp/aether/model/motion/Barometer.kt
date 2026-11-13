package de.privateapp.aether.model.motion

import de.privateapp.aether.model.Missing
import de.privateapp.aether.model.Reading
import de.privateapp.aether.model.derived
import de.privateapp.aether.model.reported
import de.privateapp.aether.model.unavailable
import kotlin.math.exp
import kotlin.math.pow

/*
 * Luftdruck (Barometer) und daraus berechnete Höhe. Die „Druckhöhe“ setzt den Luftdruck der Normatmosphäre auf
 * Meereshöhe (1013,25 hPa) voraus. Das Wetter verschiebt den tatsächlichen Druck um bis zu ±30 hPa – die Druckhöhe
 * kann deshalb um mehrere hundert Meter von der wahren Höhe abweichen. Höhen-UNTERSCHIEDE über Minuten bis Stunden
 * misst das Barometer dagegen auf etwa einen Meter genau – dafür wird es hier verwendet (Anstieg, Änderung seit Start).
 */
object PressureInterpreter {
    const val SOURCE = "Luftdrucksensor (SensorManager)"
    const val STANDARD_SEA_LEVEL_HPA = 1013.25

    /** Messbereich üblicher Telefon-Barometer (Mount Everest ≈ 337 hPa, tiefster Luftdruck auf Meereshöhe ≈ 870 hPa). */
    private val PLAUSIBLE = 260.0..1_100.0

    fun pressure(hPa: Float): Reading<Double> {
        val p = hPa.toDouble()
        return if (p.isFinite() && p in PLAUSIBLE) reported(p, SOURCE) else unavailable(Missing.Implausible("$hPa hPa"))
    }

    /**
     * Höhe in der Normatmosphäre – dieselbe Formel wie `SensorManager.getAltitude`:
     * h = 44330 · (1 − (p / p₀)^(1 / 5,255)).
     */
    fun pressureAltitudeMeters(hPa: Double, seaLevelHPa: Double = STANDARD_SEA_LEVEL_HPA): Double =
        44_330.0 * (1.0 - (hPa / seaLevelHPa).pow(1.0 / 5.255))

    fun pressureAltitude(pressure: Reading<Double>): Reading<Double> = when (pressure) {
        is Reading.Value -> derived(pressureAltitudeMeters(pressure.value), "aus dem Luftdruck (Normatmosphäre, nicht kalibriert)")
        is Reading.Unavailable -> pressure
    }
}

/**
 * Exponentielle Glättung mit fester Zeitkonstante – unabhängig davon, wie oft der Sensor meldet. Unveränderlich:
 * [next] liefert den neuen Zustand.
 */
data class Smoothed(val value: Double, val atMillis: Long) {
    fun next(sample: Double, atMillis: Long, timeConstantMillis: Double): Smoothed {
        val dt = atMillis - this.atMillis
        if (dt <= 0) return this
        val alpha = 1.0 - exp(-dt / timeConstantMillis)
        return Smoothed(value + (sample - value) * alpha, atMillis)
    }

    companion object {
        fun next(previous: Smoothed?, sample: Double, atMillis: Long, timeConstantMillis: Double): Smoothed =
            previous?.next(sample, atMillis, timeConstantMillis) ?: Smoothed(sample, atMillis)
    }
}
