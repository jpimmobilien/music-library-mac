package de.privateapp.aether.model.motion

import de.privateapp.aether.model.Missing
import de.privateapp.aether.model.Reading
import de.privateapp.aether.model.derived
import de.privateapp.aether.model.unavailable
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin
import kotlin.math.sqrt

/*
 * Werte seit dem Öffnen der Seite (oder seit „Zurücksetzen“). Alles hier ist BERECHNET aus gemeldeten Messungen –
 * mit bewusst vorsichtigen Regeln, damit Messrauschen nicht als Strecke oder Höhenmeter gezählt wird:
 *  - Strecke: nur Positionen mit einer Genauigkeit von höchstens 25 m; gezählt wird erst, wenn die neue Position
 *    weiter vom letzten gezählten Punkt entfernt ist als die Ungenauigkeit beider Punkte. Wer still steht, sammelt
 *    so keine Meter durch „wandernde“ Positionen. Kurven werden dadurch leicht abgekürzt (eher zu wenig als zu viel).
 *  - Sprünge, die einer Geschwindigkeit über 515 m/s entsprächen, werden verworfen.
 *  - Ø in Bewegung: Mittel der GPS-Geschwindigkeit über genau die Abschnitte, die als „Zeit in Bewegung“ zählen
 *    (beide Positionen in Bewegung, höchstens 5 s Abstand) – Zähler und Nenner unter derselben Bedingung.
 *  - Anstieg/Abstieg: Höhenänderungen zählen erst ab einer Schwelle (Barometer 2 m, GPS 6 m) – Schwankungen darunter
 *    nicht. Je Richtungswechsel kann dadurch bis zu eine Schwelle fehlen.
 *  - Ohne Barometer wird eine einzige GPS-Höhe verwendet: die Ellipsoid-Höhe (Unterschiede sind dieselben wie über dem
 *    Meeresspiegel, das Geoid ändert sich auf solchen Strecken kaum). Nur wenn sie fehlt, die Meereshöhe. Wechselt die
 *    Bezugshöhe, beginnt die Zählung neu – ein Wechsel ist kein Höhenunterschied (sonst entstünde ein Sprung von 35–50 m).
 *  - Gemessen wird nur, solange die Seite angezeigt wird; Pausen zählen nicht zur Messdauer.
 */

/** Woraus Anstieg und Abstieg berechnet werden. */
enum class ClimbSource(val label: String, val thresholdMeters: Double) {
    /** Bevorzugt: Luftdruck misst Höhenunterschiede viel ruhiger als GPS. */
    BAROMETER("aus dem Luftdruck", 2.0),
    GPS("aus der GPS-Höhe", 6.0),
}

/** Worauf sich eine Höhe bezieht. Höhen verschiedener Bezüge werden nie miteinander verrechnet. */
enum class AltitudeReference {
    /** Druckhöhe (Normatmosphäre). */
    PRESSURE,

    /** GPS-Höhe über dem WGS-84-Ellipsoid. */
    ELLIPSOID,

    /** Höhe über dem Meeresspiegel (Geoid). */
    MSL,
}

/** Zählt Anstieg und Abstieg mit Schwelle (Hysterese). */
data class ClimbCounter(
    val thresholdMeters: Double,
    val reference: Double? = null,
    val ascentMeters: Double = 0.0,
    val descentMeters: Double = 0.0,
) {
    fun add(altitudeMeters: Double): ClimbCounter {
        if (!altitudeMeters.isFinite()) return this
        val ref = reference ?: return copy(reference = altitudeMeters)
        val d = altitudeMeters - ref
        return when {
            d >= thresholdMeters -> copy(reference = altitudeMeters, ascentMeters = ascentMeters + d)
            -d >= thresholdMeters -> copy(reference = altitudeMeters, descentMeters = descentMeters - d)
            else -> this
        }
    }
}

/** Ergebnis für die Anzeige. */
data class SessionStats(
    val activeMillis: Long,
    val distanceMeters: Reading<Double>,
    val maxSpeed: Reading<Speed>,
    /** Mittlere GPS-Geschwindigkeit während der Zeit in Bewegung. */
    val averageMovingSpeedMetersPerSecond: Reading<Double>,
    val movingMillis: Long,
    val ascentMeters: Reading<Double>,
    val descentMeters: Reading<Double>,
    /** Höhenänderung seit dem Start (aus derselben Quelle wie der Anstieg). */
    val altitudeChangeMeters: Reading<Double>,
    val climbSource: ClimbSource,
)

/** Unveränderlicher Zustand; jede Messung liefert einen neuen. */
data class SessionTracker(
    val climbSource: ClimbSource,
    val activeMillis: Long = 0L,
    val lastTickMillis: Long? = null,
    val distanceMeters: Double = 0.0,
    val reliableFixes: Int = 0,
    /** Letzter gezählter Punkt der Strecke. */
    val anchor: GpsFix? = null,
    val lastFix: GpsFix? = null,
    val movingMillis: Long = 0L,
    /** Über die Zeit in Bewegung aufsummierte GPS-Geschwindigkeit (m/s · s) – Grundlage für „Ø in Bewegung“. */
    val movingDistanceMeters: Double = 0.0,
    val maxSpeed: Speed? = null,
    val climb: ClimbCounter = ClimbCounter(climbSource.thresholdMeters),
    /** Bezug der Höhen in [climb], [baselineAltitudeMeters] und [latestAltitudeMeters]. */
    val altitudeReference: AltitudeReference? = null,
    val baselineAltitudeMeters: Double? = null,
    val latestAltitudeMeters: Double? = null,
    /** Höhenänderung, die vor einem Wechsel der Bezugshöhe gemessen wurde. */
    val altitudeChangeBeforeSwitchMeters: Double = 0.0,
) {
    /**
     * Uhr der Seite (etwa jede Sekunde). Eine Lücke über [MAX_TICK_GAP_MILLIS] heißt: Die Seite war nicht sichtbar,
     * es wurde nicht gemessen. Die Lücke zählt nicht zur Messdauer, und Strecke bzw. Höhenmeter setzen danach neu an –
     * der Weg während der Pause wird nicht nachträglich als gerade Linie gezählt.
     */
    fun tick(nowElapsedMillis: Long): SessionTracker {
        val last = lastTickMillis ?: return copy(lastTickMillis = nowElapsedMillis)
        val dt = nowElapsedMillis - last
        if (dt > MAX_TICK_GAP_MILLIS) {
            return copy(lastTickMillis = nowElapsedMillis, anchor = null, lastFix = null, climb = climb.copy(reference = null))
        }
        return copy(lastTickMillis = nowElapsedMillis, activeMillis = activeMillis + if (dt > 0) dt else 0L)
    }

    /** Neue GPS-Position. [distance] = Abstand zweier Positionen in Metern (auf dem Gerät: WGS-84-Ellipsoid). */
    fun withFix(fix: GpsFix, distance: (GpsFix, GpsFix) -> Double = ::greatCircleMeters): SessionTracker {
        val accuracy = fix.horizontalAccuracyMeters
        val reliable = accuracy != null && accuracy.isFinite() && accuracy <= MAX_ACCURACY_METERS
        val speed = fix.speedMetersPerSecond?.takeIf { it.isFinite() && it >= 0f }?.let { Speed(it, fix.speedAccuracyMetersPerSecond) }
        val previous = lastFix
        val previousSpeed = previous?.speedMetersPerSecond?.let { Speed(it, previous.speedAccuracyMetersPerSecond) }

        var moving = movingMillis
        var movingDistance = movingDistanceMeters
        if (previous != null && previousSpeed != null && speed?.moving == true && previousSpeed.moving) {
            val dt = fix.elapsedRealtimeMillis - previous.elapsedRealtimeMillis
            if (dt in 1..MAX_FIX_GAP_MILLIS) {
                moving += dt
                // Trapezregel über denselben Abschnitt, der als Zeit in Bewegung zählt.
                movingDistance += (previousSpeed.metersPerSecond + speed.metersPerSecond) / 2.0 * (dt / 1000.0)
            }
        }

        var top = maxSpeed
        if (reliable && speed != null && speed.moving && speed.metersPerSecond <= MAX_PLAUSIBLE_SPEED_MS) {
            val acc = speed.accuracyMetersPerSecond
            val trustworthy = acc == null || acc <= max(1.5f, 0.2f * speed.metersPerSecond)
            if (trustworthy && (top == null || speed.metersPerSecond > top.metersPerSecond)) top = speed
        }

        var total = distanceMeters
        var newAnchor = anchor
        if (reliable) {
            val a = anchor
            if (a == null) {
                newAnchor = fix
            } else {
                val d = distance(a, fix)
                val seconds = ((fix.elapsedRealtimeMillis - a.elapsedRealtimeMillis).coerceAtLeast(1L)) / 1000.0
                val jitter = max(a.horizontalAccuracyMeters ?: 0f, accuracy).toDouble()
                if (d.isFinite() && d / seconds <= MAX_PLAUSIBLE_SPEED_MS && d >= jitter) {
                    total += d
                    newAnchor = fix
                }
            }
        }

        var next = copy(
            lastFix = fix,
            movingMillis = moving,
            movingDistanceMeters = movingDistance,
            maxSpeed = top,
            distanceMeters = total,
            anchor = newAnchor,
            reliableFixes = reliableFixes + if (reliable) 1 else 0,
        )
        if (climbSource == ClimbSource.GPS) {
            val msl = (fix.msl as? Reading.Value)?.value
            val ellipsoid = fix.ellipsoidAltitudeMeters
            val (altitude, vertical, reference) = when {
                ellipsoid != null -> Triple(ellipsoid, fix.verticalAccuracyMeters, AltitudeReference.ELLIPSOID)
                msl != null -> Triple(msl.meters, msl.accuracyMeters ?: fix.verticalAccuracyMeters, AltitudeReference.MSL)
                else -> Triple(null, null, null)
            }
            if (altitude != null && reference != null && vertical != null && vertical <= MAX_VERTICAL_ACCURACY_METERS) {
                next = next.withAltitude(altitude, reference)
            }
        }
        return next
    }

    /** Geglättete Druckhöhe (nur bei [ClimbSource.BAROMETER] berücksichtigt). */
    fun withBarometricAltitude(meters: Double): SessionTracker =
        if (climbSource == ClimbSource.BAROMETER) withAltitude(meters, AltitudeReference.PRESSURE) else this

    private fun withAltitude(meters: Double, reference: AltitudeReference): SessionTracker {
        if (!meters.isFinite()) return this
        val current = altitudeReference
        if (current != null && current != reference) {
            // Neuer Bezug: bisherige Änderung festhalten, Zählung ab hier neu – der Unterschied der Bezüge zählt nicht.
            val before = altitudeChangeBeforeSwitchMeters + ((latestAltitudeMeters ?: meters) - (baselineAltitudeMeters ?: meters))
            return copy(
                climb = climb.copy(reference = meters),
                altitudeReference = reference,
                baselineAltitudeMeters = meters,
                latestAltitudeMeters = meters,
                altitudeChangeBeforeSwitchMeters = before,
            )
        }
        return copy(
            climb = climb.add(meters),
            altitudeReference = reference,
            baselineAltitudeMeters = baselineAltitudeMeters ?: meters,
            latestAltitudeMeters = meters,
        )
    }

    fun stats(): SessionStats {
        val src = "berechnet seit Beginn der Messung"
        val noFix = Missing.Condition("Noch keine genaue GPS-Position")
        val distance: Reading<Double> = if (reliableFixes == 0) unavailable(noFix) else derived(distanceMeters, "aus GPS-Positionen, $src")
        val top: Reading<Speed> = when {
            maxSpeed != null -> derived(maxSpeed, "höchste verlässliche GPS-Geschwindigkeit, $src")
            reliableFixes == 0 -> unavailable(noFix)
            else -> unavailable(Missing.Condition("Noch keine Bewegung gemessen"))
        }
        val average: Reading<Double> = when {
            movingMillis >= MIN_MOVING_MILLIS ->
                derived(movingDistanceMeters / (movingMillis / 1000.0), "Mittel der GPS-Geschwindigkeit während der Bewegung")
            reliableFixes == 0 -> unavailable(noFix)
            else -> unavailable(Missing.Condition("Noch zu wenig Bewegung"))
        }
        val waiting = when (climbSource) {
            ClimbSource.BAROMETER -> Missing.Condition("Wartet auf den Luftdrucksensor")
            ClimbSource.GPS -> Missing.Condition("Noch keine genaue GPS-Höhe")
        }
        val climbNote = "${climbSource.label}, ab ${climbSource.thresholdMeters.toInt()} m Änderung"
        val base = baselineAltitudeMeters
        val latest = latestAltitudeMeters
        return SessionStats(
            activeMillis = activeMillis,
            distanceMeters = distance,
            maxSpeed = top,
            averageMovingSpeedMetersPerSecond = average,
            movingMillis = movingMillis,
            ascentMeters = if (base == null) unavailable(waiting) else derived(climb.ascentMeters, climbNote),
            descentMeters = if (base == null) unavailable(waiting) else derived(climb.descentMeters, climbNote),
            altitudeChangeMeters = if (base == null || latest == null) {
                unavailable(waiting)
            } else {
                derived(altitudeChangeBeforeSwitchMeters + (latest - base), climbSource.label)
            },
            climbSource = climbSource,
        )
    }

    companion object {
        const val MAX_ACCURACY_METERS = 25f
        const val MAX_VERTICAL_ACCURACY_METERS = 12f
        const val MAX_TICK_GAP_MILLIS = 3_000L
        const val MAX_FIX_GAP_MILLIS = 5_000L
        const val MIN_MOVING_MILLIS = 10_000L
        private const val MAX_PLAUSIBLE_SPEED_MS = 515f

        fun start(climbSource: ClimbSource): SessionTracker = SessionTracker(climbSource)
    }
}

/**
 * Großkreisabstand auf einer Kugel mit mittlerem Erdradius (Haversine). Auf dem Gerät wird stattdessen
 * `Location.distanceBetween` (WGS-84-Ellipsoid) verwendet; der Unterschied liegt unter 0,5 %.
 */
fun greatCircleMeters(a: GpsFix, b: GpsFix): Double {
    val r = 6_371_008.8
    val lat1 = Math.toRadians(a.latitude)
    val lat2 = Math.toRadians(b.latitude)
    val dLat = lat2 - lat1
    val dLon = Math.toRadians(b.longitude - a.longitude)
    val h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
    return 2 * r * asin(sqrt(h.coerceIn(0.0, 1.0)))
}
