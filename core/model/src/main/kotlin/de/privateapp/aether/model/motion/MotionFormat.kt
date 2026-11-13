package de.privateapp.aether.model.motion

import de.privateapp.aether.model.Fmt
import de.privateapp.aether.model.Fmt.NBSP
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.roundToLong

/** Zahlenformate der Seite „Bewegung“ (metrisch, deutsche Schreibweise). Zahl und Einheit getrennt, wo die Oberfläche sie verschieden groß setzt. */
object MotionFormat {
    private const val MINUS = '−'

    /** Geschwindigkeit in km/h ohne Einheit: unter 10 km/h mit einer Nachkommastelle („4,3“), sonst ganzzahlig („52“). */
    fun kmhNumber(kmh: Double): String = if (kmh < 9.95) Fmt.decimal(kmh, 1) else Fmt.count(kmh.roundToLong())

    fun kmh(kmh: Double): String = kmhNumber(kmh) + "${NBSP}km/h"

    /** Ungenauigkeit einer Geschwindigkeit, z. B. „± 1,2 km/h“. */
    fun kmhAccuracy(kmh: Double): String = "±${NBSP}" + Fmt.decimal(kmh, 1) + "${NBSP}km/h"

    /** Höhe ohne Einheit, ganzzahlig, mit echtem Minuszeichen („−12“). */
    fun metersNumber(meters: Double): String = signed(meters.roundToLong(), plus = false)

    fun meters(meters: Double): String = metersNumber(meters) + "${NBSP}m"

    /** Änderung mit Vorzeichen: „+12 m“, „−3 m“, „±0 m“. */
    fun metersChange(meters: Double): String {
        val v = meters.roundToLong()
        return if (v == 0L) "±0${NBSP}m" else signed(v, plus = true) + "${NBSP}m"
    }

    /** Genauigkeit in Metern, z. B. „± 4 m“; unter 1 m „< 1 m“. */
    fun metersAccuracy(meters: Float): String =
        if (meters < 0.5f) "<${NBSP}1${NBSP}m" else "±${NBSP}" + Fmt.count(meters.roundToInt()) + "${NBSP}m"

    /** Strecke: „0 m“, „820 m“, „1,24 km“, „12,4 km“, „124 km“. */
    fun distance(meters: Double): String {
        val m = meters.coerceAtLeast(0.0)
        return when {
            m < 999.5 -> "${m.roundToLong()}${NBSP}m"
            m < 9_995.0 -> Fmt.decimal(m / 1000.0, 2) + "${NBSP}km"
            m < 99_950.0 -> Fmt.decimal(m / 1000.0, 1) + "${NBSP}km"
            else -> Fmt.count((m / 1000.0).roundToLong()) + "${NBSP}km"
        }
    }

    /** Richtung, z. B. „245°“ (359,6° wird „0°“, nie „360°“). */
    fun degrees(degrees: Double): String = "${Angles.normalize(degrees.roundToInt().toDouble()).roundToInt()}°"

    /** Ungenauigkeit einer Richtung, z. B. „± 5°“. */
    fun degreesAccuracy(degrees: Float): String = "±${NBSP}${degrees.roundToInt().coerceAtLeast(1)}°"

    /** Missweisung, z. B. „2,9° Ost“ / „1,4° West“ / „0,0°“. */
    fun declination(degrees: Double): String = when {
        abs(degrees) < 0.05 -> "0,0°"
        degrees > 0 -> Fmt.decimal(degrees, 1) + "°${NBSP}Ost"
        else -> Fmt.decimal(-degrees, 1) + "°${NBSP}West"
    }

    /** Luftdruck, z. B. „1.013,2 hPa“. */
    fun hectopascal(hPa: Double): String = Fmt.decimal(hPa, 1) + "${NBSP}hPa"

    /** Signalstärke, z. B. „38 dB-Hz“. */
    fun dbHz(value: Float): String = "${value.roundToInt()}${NBSP}dB-Hz"

    /** Alter einer Messung: „gerade eben“, „vor 4 s“, „vor 3 Min.“ */
    fun age(millis: Long): String = when {
        millis < 1_500L -> "gerade eben"
        millis < 60_000L -> "vor ${(millis / 1000L)}${NBSP}s"
        millis < 3_600_000L -> "vor ${millis / 60_000L}${NBSP}Min."
        else -> "vor über 1${NBSP}Std."
    }

    /** Messdauer wie eine Stoppuhr: „0:42“, „12:05“, „1:03:09“. */
    fun stopwatch(millis: Long): String {
        val total = (millis.coerceAtLeast(0L) / 1000L)
        val h = total / 3600
        val m = (total / 60) % 60
        val s = total % 60
        return if (h > 0) "$h:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}" else "$m:${s.toString().padStart(2, '0')}"
    }

    /** Zeit bis zur ersten Position, z. B. „4,2 s“ bzw. „1 Min. 12 s“. */
    fun seconds(millis: Long): String =
        if (millis < 60_000L) Fmt.decimal(millis / 1000.0, 1) + "${NBSP}s" else "${millis / 60_000L}${NBSP}Min. ${(millis / 1000L) % 60}${NBSP}s"

    /** Koordinate mit fünf Nachkommastellen (≈ 1 m), z. B. „52,51630° N, 13,37770° O“. */
    fun coordinates(latitude: Double, longitude: Double): String {
        val lat = Fmt.decimal(abs(latitude), 5) + "°${NBSP}" + if (latitude >= 0) "N" else "S"
        val lon = Fmt.decimal(abs(longitude), 5) + "°${NBSP}" + if (longitude >= 0) "O" else "W"
        return "$lat, $lon"
    }

    private fun signed(v: Long, plus: Boolean): String = when {
        v < 0 -> "$MINUS${Fmt.count(-v)}"
        plus && v > 0 -> "+${Fmt.count(v)}"
        else -> Fmt.count(v)
    }
}
