package de.privateapp.aether.model.motion

import kotlin.math.abs
import kotlin.math.exp

/** Winkelrechnung im Kreis (0° = Norden, im Uhrzeigersinn). */
object Angles {
    /** Auf 0 ≤ Winkel < 360 bringen. */
    fun normalize(degrees: Double): Double {
        if (!degrees.isFinite()) return degrees
        val r = degrees % 360.0
        val n = if (r < 0) r + 360.0 else r
        return if (n >= 360.0) 0.0 else n
    }

    /** Kürzester Weg von [from] nach [to]: −180 < Ergebnis ≤ 180 (von 350° nach 10° sind es +20°, nicht −340°). */
    fun shortestDelta(from: Double, to: Double): Double {
        val d = normalize(to - from)
        return if (d > 180.0) d - 360.0 else d
    }

    /**
     * Glättung im Kreis: bewegt [previous] um den Anteil, der sich aus [dtMillis] und der Zeitkonstante
     * [timeConstantMillis] ergibt, in Richtung [next] – über den kürzesten Weg, also ohne Sprung bei 359° → 0°.
     */
    fun smooth(previous: Double?, next: Double, dtMillis: Long, timeConstantMillis: Double): Double {
        if (previous == null || !previous.isFinite() || dtMillis <= 0) return normalize(next)
        val alpha = 1.0 - exp(-dtMillis / timeConstantMillis)
        return normalize(previous + shortestDelta(previous, next) * alpha)
    }
}

/** Himmelsrichtung in acht Schritten. */
enum class Cardinal(val short: String, val long: String) {
    N("N", "Norden"),
    NE("NO", "Nordosten"),
    E("O", "Osten"),
    SE("SO", "Südosten"),
    S("S", "Süden"),
    SW("SW", "Südwesten"),
    W("W", "Westen"),
    NW("NW", "Nordwesten"),
    ;

    companion object {
        /** Jede Richtung deckt 45° ab, mittig um ihren Nennwert (Nord = 337,5° bis unter 22,5°). */
        fun of(degrees: Double): Cardinal = entries[((Angles.normalize(degrees) + 22.5) / 45.0).toInt() % 8]
    }
}

/** Kalibrierzustand des Magnetfeldsensors laut `SensorManager.SENSOR_STATUS_*`. */
enum class CompassAccuracy(val label: String) {
    UNRELIABLE("unzuverlässig"),
    LOW("niedrig"),
    MEDIUM("mittel"),
    HIGH("hoch"),
    ;

    /** Android empfiehlt dann, den Kompass zu kalibrieren. */
    val needsCalibration: Boolean get() = this == UNRELIABLE || this == LOW

    companion object {
        /** −1 kein Kontakt, 0 unzuverlässig, 1 niedrig, 2 mittel, 3 hoch. */
        fun fromAndroid(status: Int): CompassAccuracy = when (status) {
            3 -> HIGH
            2 -> MEDIUM
            1 -> LOW
            else -> UNRELIABLE
        }
    }
}

/** Welche Sensoren die Richtung liefern. */
enum class CompassSensor(val label: String) {
    ROTATION_VECTOR("Rotationsvektor (Gyroskop, Beschleunigung und Magnetfeld)"),
    GEOMAGNETIC_ROTATION_VECTOR("Geomagnetischer Rotationsvektor (Beschleunigung und Magnetfeld)"),
    ACCELEROMETER_MAGNETOMETER("Beschleunigungs- und Magnetfeldsensor"),
}

/** Bezug der angezeigten Richtung. */
enum class NorthReference(val label: String) {
    TRUE("geografisch Nord"),
    MAGNETIC("magnetisch Nord"),
}

/** Rohwert des Kompasses (Richtung der Oberkante des Bildschirms). */
data class CompassSample(
    val magneticAzimuthDegrees: Double,
    /** Neigung nach vorn/hinten und zur Seite in Grad (0 = flach). */
    val pitchDegrees: Double,
    val rollDegrees: Double,
    /** Vom Rotationsvektor geschätzte Genauigkeit der Richtung, `null` wenn nicht gemeldet. */
    val headingAccuracyDegrees: Float?,
    val accuracy: CompassAccuracy?,
    val sensor: CompassSensor,
)

/** Angezeigte Richtung. */
data class Heading(
    val degrees: Double,
    val reference: NorthReference,
    /** Missweisung (Ost positiv), wenn geografisch Nord angezeigt wird. */
    val declinationDegrees: Double?,
    val accuracyDegrees: Float?,
    val calibration: CompassAccuracy?,
    /** Telefon ist so stark geneigt, dass die Richtung unzuverlässig wird. */
    val tilted: Boolean,
    val sensor: CompassSensor,
) {
    val cardinal: Cardinal get() = Cardinal.of(degrees)
}

object CompassInterpreter {
    /** Ab dieser Neigung wird die Richtung aus der Lage unsicher (Hinweis „Telefon flacher halten“). */
    const val TILT_LIMIT_DEGREES = 55.0

    /**
     * Richtung für die Anzeige. Mit bekannter Missweisung (aus dem Standort, `GeomagneticField`) wird auf geografisch
     * Nord umgerechnet – so zeigt es auch eine Karte. Ohne Standort bleibt es bei magnetisch Nord, ausdrücklich benannt.
     */
    fun heading(sample: CompassSample, declinationDegrees: Double?): Heading {
        val decl = declinationDegrees?.takeIf { it.isFinite() && abs(it) <= 180.0 }
        val degrees = Angles.normalize(sample.magneticAzimuthDegrees + (decl ?: 0.0))
        return Heading(
            degrees = degrees,
            reference = if (decl != null) NorthReference.TRUE else NorthReference.MAGNETIC,
            declinationDegrees = decl,
            accuracyDegrees = sample.headingAccuracyDegrees?.takeIf { it.isFinite() && it >= 0f },
            calibration = sample.accuracy,
            tilted = abs(sample.pitchDegrees) > TILT_LIMIT_DEGREES || abs(sample.rollDegrees) > TILT_LIMIT_DEGREES,
            sensor = sample.sensor,
        )
    }
}
