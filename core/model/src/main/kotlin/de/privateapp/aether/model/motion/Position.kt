package de.privateapp.aether.model.motion

import de.privateapp.aether.model.Missing
import de.privateapp.aether.model.Reading
import de.privateapp.aether.model.ValueKind
import de.privateapp.aether.model.reported
import de.privateapp.aether.model.unavailable

/*
 * GPS-Position und was sich daraus ehrlich ablesen lässt. Android meldet jede Größe einzeln mit „has…()“ – fehlt sie,
 * bleibt sie hier `null` und wird nie geschätzt.
 */

/** Standortfreigabe laut Android. */
enum class LocationPermission {
    /** „Genauer Standort“ (ACCESS_FINE_LOCATION) – nötig für GPS-Geschwindigkeit, Höhe und Satelliten. */
    PRECISE,

    /**
     * Nur „Ungefährer Standort“: Android liefert dann eine bewusst auf etwa 2 km vergröberte Position ohne
     * Geschwindigkeit, Kurs und Höhe und keine Satellitendaten.
     */
    APPROXIMATE,
    NONE,
}

/** Ob und wie GPS gerade nutzbar ist. */
data class LocationAccess(
    val permission: LocationPermission,
    /** Standort in den Android-Einstellungen eingeschaltet. */
    val servicesEnabled: Boolean,
    /** Gerät hat einen GPS-Empfänger (GNSS). */
    val hasGps: Boolean,
) {
    val canUseGps: Boolean get() = hasGps && servicesEnabled && permission == LocationPermission.PRECISE

    /** Für die Missweisung (geografisch Nord) reicht auch der ungefähre Standort. */
    val canUseAnyLocation: Boolean get() = servicesEnabled && permission != LocationPermission.NONE
}

/** Woher die Höhe über dem Meeresspiegel stammt. */
enum class MslSource(val label: String) {
    /** Der GNSS-Empfänger hat sie selbst geliefert. */
    RECEIVER("vom GNSS-Empfänger gemeldet"),

    /** Android hat die GPS-Höhe mit seinem Geoid-Modell umgerechnet (`AltitudeConverter`, Android 14+). */
    CONVERTED("von Android aus der GPS-Höhe umgerechnet"),
}

/** Höhe mit Genauigkeit. */
data class Altitude(val meters: Double, val accuracyMeters: Float?)

/** Eine GPS-Position (LocationManager, Anbieter „gps“). */
data class GpsFix(
    /** Zeitpunkt der Messung auf der monotonen Uhr (`elapsedRealtime`) – für Alter und Abstände. */
    val elapsedRealtimeMillis: Long,
    val latitude: Double,
    val longitude: Double,
    val horizontalAccuracyMeters: Float?,
    val speedMetersPerSecond: Float?,
    val speedAccuracyMetersPerSecond: Float?,
    val bearingDegrees: Float?,
    val bearingAccuracyDegrees: Float?,
    /** Höhe über dem WGS-84-Ellipsoid (so meldet GPS sie ursprünglich). */
    val ellipsoidAltitudeMeters: Double?,
    val verticalAccuracyMeters: Float?,
    /** Höhe über dem Meeresspiegel oder warum es sie nicht gibt. */
    val msl: Reading<Altitude>,
    /** Position stammt aus einer Simulations-App (Entwickleroption „Simulierte Standorte“). */
    val isMock: Boolean,
)

/** Geschwindigkeit. */
data class Speed(val metersPerSecond: Float, val accuracyMetersPerSecond: Float?) {
    val kmh: Double get() = metersPerSecond * MS_TO_KMH
    val accuracyKmh: Double? get() = accuracyMetersPerSecond?.let { it * MS_TO_KMH }

    /**
     * Der Messwert ist kleiner als seine eigene Ungenauigkeit – er lässt sich von Stillstand nicht unterscheiden.
     * Angezeigt wird trotzdem der gemessene Wert (nicht „0“): ORBIT ersetzt keine Messung durch eine Vermutung,
     * kennzeichnet sie aber als „Stillstand innerhalb der Messgenauigkeit“. Ohne Genauigkeitsangabe wird nichts
     * gekennzeichnet.
     */
    val withinNoise: Boolean get() = accuracyMetersPerSecond != null && metersPerSecond < accuracyMetersPerSecond

    /** In Bewegung: deutlich über der Ungenauigkeit und mindestens Schrittgeschwindigkeit-Untergrenze (0,5 m/s). */
    val moving: Boolean get() = !withinNoise && metersPerSecond >= MOVING_THRESHOLD_MS

    companion object {
        const val MS_TO_KMH = 3.6
        const val MOVING_THRESHOLD_MS = 0.5f
    }
}

/** Kurs über Grund (Bewegungsrichtung laut GPS, nicht die Blickrichtung des Telefons). */
data class Course(val degrees: Float, val accuracyDegrees: Float?) {
    val cardinal: Cardinal get() = Cardinal.of(degrees.toDouble())
}

object PositionInterpreter {
    const val SOURCE_GPS = "GPS-Empfänger (LocationManager)"

    /** Ab hier gilt eine Position als veraltet: Geschwindigkeit und Kurs werden nicht mehr gezeigt. */
    const val STALE_AFTER_MILLIS = 10_000L

    /** Höchstgeschwindigkeit, die zivile GNSS-Empfänger melden dürfen (515 m/s, „COCOM-Grenze“). */
    private const val MAX_PLAUSIBLE_SPEED_MS = 515f

    private val NO_SIGNAL = Missing.Condition("Kein aktuelles GPS-Signal")

    fun isStale(fix: GpsFix, nowElapsedMillis: Long): Boolean = nowElapsedMillis - fix.elapsedRealtimeMillis > STALE_AFTER_MILLIS

    fun speed(fix: GpsFix, nowElapsedMillis: Long): Reading<Speed> {
        if (isStale(fix, nowElapsedMillis)) return unavailable(NO_SIGNAL)
        val v = fix.speedMetersPerSecond ?: return unavailable(Missing.Condition("Vom GPS gerade nicht gemeldet"))
        if (v.isNaN() || v < 0f || v > MAX_PLAUSIBLE_SPEED_MS) return unavailable(Missing.Implausible("$v m/s"))
        val acc = fix.speedAccuracyMetersPerSecond?.takeIf { it.isFinite() && it >= 0f }
        return reported(Speed(v, acc), SOURCE_GPS)
    }

    /** GPS-Kurs entsteht aus der Bewegung – im Stillstand ist er Zufall und wird nicht gezeigt. */
    fun course(fix: GpsFix, nowElapsedMillis: Long): Reading<Course> {
        if (isStale(fix, nowElapsedMillis)) return unavailable(NO_SIGNAL)
        val speed = speed(fix, nowElapsedMillis)
        val stationary = (speed as? Reading.Value)?.value?.moving == false
        val bearing = fix.bearingDegrees
        return when {
            bearing == null || bearing.isNaN() -> unavailable(Missing.Condition("Erst in Bewegung bestimmbar"))
            stationary -> unavailable(Missing.Condition("Im Stillstand nicht bestimmbar"))
            else -> reported(Course(Angles.normalize(bearing.toDouble()).toFloat(), fix.bearingAccuracyDegrees?.takeIf { it.isFinite() && it >= 0f }), SOURCE_GPS)
        }
    }

    fun ellipsoidAltitude(fix: GpsFix): Reading<Altitude> {
        val h = fix.ellipsoidAltitudeMeters ?: return unavailable(Missing.Condition("Vom GPS gerade nicht gemeldet"))
        if (!h.isFinite() || h < -1_000.0 || h > 100_000.0) return unavailable(Missing.Implausible("${h.toInt()} m"))
        return reported(Altitude(h, fix.verticalAccuracyMeters?.takeIf { it.isFinite() && it >= 0f }), SOURCE_GPS)
    }

    fun horizontalAccuracy(fix: GpsFix): Reading<Float> {
        val a = fix.horizontalAccuracyMeters ?: return unavailable(Missing.Condition("Vom GPS nicht gemeldet"))
        return if (a.isFinite() && a >= 0f) reported(a, SOURCE_GPS) else unavailable(Missing.Implausible("$a m"))
    }

    /** MSL-Höhe aus dem Empfänger oder aus der Umrechnung von Android. */
    fun msl(meters: Double, accuracy: Float?, source: MslSource): Reading<Altitude> {
        if (!meters.isFinite() || meters < -1_000.0 || meters > 100_000.0) return unavailable(Missing.Implausible("${meters.toInt()} m"))
        val kind = if (source == MslSource.CONVERTED) ValueKind.DERIVED else ValueKind.REPORTED
        return Reading.Value(Altitude(meters, accuracy?.takeIf { it.isFinite() && it >= 0f }), kind, source.label)
    }
}
